# ==============================================================================
# Dosya Yolu: R/helpers_pk_sql_execute.R
# Açıklama: Faz 6 (§5.10) — SINIRLI (bounded) SQL getirimi: ifade zaman aşımı,
#           parça parça getirim, parçalar arasında iptal/son tarih yoklaması ve
#           GARANTİLİ sonuç-kümesi/bağlantı temizliği.
#
# Neden `dbGetQuery` yetmez: tek atışta tüm sonucu materyalize eder. Bu üç şeyi
# imkânsız kılar — (a) tavanı AŞACAK parçayı kabul etmeden önce durmak,
# (b) uzun bir getirimin ORTASINDA iptali görmek, (c) ne kadar bellek
# tükettiğini gerçekten ölçmek. `dbSendQuery` + parça parça `dbFetch` üçünü de
# mümkün kılar.
#
# DÜRÜSTLÜK SINIRI: sürücü seviyesinde GERÇEK bir sorgu zaman aşımı, R `odbc`
# paketinin genel API'sinde yoktur. Bu yüzden üç katman birlikte uygulanır:
#   1) `SET LOCK_TIMEOUT` (SQL Server) — en yaygın gerçek asılma nedeni olan
#      kilit beklemesini sınırlar,
#   2) parça parça getirim + parça aralarında son tarih/iptal yoklaması —
#      uzun TARAMALARI kesilebilir kılar,
#   3) tüm analizin duvar-saati son tarihi — her zaman çalışan son çare.
# Katman (1)'in gerçekten uygulandığı, YALNIZCA Windows VM'de gerçek SQL
# Server'a karşı doğrulanabilir; bu yüzden uygulanan mekanizma raporlanır.
# ==============================================================================

#' İfade seviyesinde zaman aşımını uygula (mümkün olan mekanizmayla)
#'
#' @return `list(mechanism = "lock_timeout"|"none", applied = TRUE/FALSE,
#'   timeout_sec = <int>)`. `stop()` ATMAZ: zaman aşımı uygulanamaması analizi
#'   iptal etmemelidir — duvar-saati son tarihi hâlâ koruyordur.
pk_sql_apply_statement_timeout <- function(conn, timeout_sec) {
  saniye <- suppressWarnings(as.integer(timeout_sec)[1])
  if (length(saniye) != 1L || is.na(saniye) || saniye <= 0L) {
    return(list(mechanism = "none", applied = FALSE, timeout_sec = 0L))
  }

  if (is.null(conn) || !requireNamespace("DBI", quietly = TRUE)) {
    return(list(mechanism = "none", applied = FALSE, timeout_sec = saniye))
  }

  # SQL Server: LOCK_TIMEOUT milisaniye cinsindendir. Bu bizim OTURUM ayarımızdır;
  # sorgu kütüphanesinden gelen SQL DEĞİLDİR, dolayısıyla salt-okunur
  # sınıflandırıcı sözleşmesini ilgilendirmez.
  uygulandi <- tryCatch({
    DBI::dbExecute(conn, sprintf("SET LOCK_TIMEOUT %d", saniye * 1000L))
    TRUE
  }, error = function(e) FALSE)

  if (isTRUE(uygulandi)) {
    return(list(mechanism = "lock_timeout", applied = TRUE, timeout_sec = saniye))
  }

  list(mechanism = "none", applied = FALSE, timeout_sec = saniye)
}

# `execute_pk_sql_unicode()` ile AYNI sarmalayıcı: SQL metni ham batch olarak
# değil Unicode PARAMETRE olarak gönderilir. Türkçe/köşeli parantezli sütun
# adlarındaki ODBC parse sorunlarını önleyen bu davranış korunmalıdır.
.pk_sql_unicode_wrapper <- function() {
  paste(
    "DECLARE @sql NVARCHAR(MAX);",
    "SET @sql = ?;",
    "EXEC sp_executesql @sql;",
    sep = "\n"
  )
}

.pk_sql_frame_bytes <- function(df) {
  bayt <- tryCatch(as.numeric(utils::object.size(df)), error = function(e) NA_real_)
  if (length(bayt) != 1L || is.na(bayt) || !is.finite(bayt)) return(NA_real_)
  bayt
}

#' SINIRLI, KESİLEBİLİR SQL getirimi
#'
#' @param conn Açık DB bağlantısı (İŞÇİ TARAFINDA açılmış olmalıdır).
#' @param sql_text Salt-okunur kapısından GEÇMİŞ SQL metni.
#' @param unicode_param `TRUE` ise `sp_executesql` sarmalayıcısı kullanılır
#'   (SQL Server). `FALSE` ise SQL doğrudan gönderilir (test/SQLite).
#' @param chunk_rows Parça başına satır sayısı.
#' @param max_result_mb Aktif sonuç tavanı (MB); aşacak parça KABUL EDİLMEDEN
#'   önce durulur.
#' @param stop_check İptal/son tarih yoklayıcısı (`function() TRUE/FALSE`).
#' @param stage_gate `function()` -> `pk_async_stage_gate()` çıktısı; verilirse
#'   `stop_check` yerine TİPLİ durum döndürür.
#' @return `list(status = "ok"|"cancelled"|"deadline"|"too_large"|"error",
#'   data = <data.frame|NULL>, rows = <int>, bytes = <num>, chunks = <int>,
#'   error = <chr>)`.
pk_sql_execute_bounded <- function(conn, sql_text,
                                   unicode_param = TRUE,
                                   chunk_rows = 5000L,
                                   max_result_mb = 512,
                                   stop_check = NULL,
                                   stage_gate = NULL) {
  bos_sonuc <- function(status, error = NA_character_, data = NULL,
                        rows = 0L, bytes = 0, chunks = 0L) {
    list(status = status, data = data, rows = rows, bytes = bytes,
         chunks = chunks, error = error)
  }

  if (is.null(sql_text) || !nzchar(trimws(as.character(sql_text)[1]))) {
    return(bos_sonuc("error", error = "Bos SQL metni gonderilemez."))
  }
  if (is.null(conn) || !requireNamespace("DBI", quietly = TRUE)) {
    return(bos_sonuc("error", error = "DB baglantisi kullanilamiyor."))
  }

  parca_satir <- suppressWarnings(as.integer(chunk_rows)[1])
  if (length(parca_satir) != 1L || is.na(parca_satir) || parca_satir < 1L) parca_satir <- 5000L

  # Aşama kapısı: tipli durum tercih edilir, yoksa boolean stop_check.
  kapi <- function() {
    if (is.function(stage_gate)) {
      sonuc <- tryCatch(stage_gate(), error = function(e) NULL)
      if (is.list(sonuc) && isTRUE(sonuc$halt)) {
        return(as.character(sonuc$status %||% "cancelled")[1])
      }
      return("ok")
    }
    if (is.function(stop_check) && isTRUE(tryCatch(stop_check(), error = function(e) FALSE))) {
      return("cancelled")
    }
    "ok"
  }

  ilk_kapi <- kapi()
  if (!identical(ilk_kapi, "ok")) return(bos_sonuc(ilk_kapi))

  metin <- enc2utf8(trimws(as.character(sql_text)[1]))

  res <- tryCatch({
    if (isTRUE(unicode_param)) {
      parametreler <- if (exists("normalize_db_params", mode = "function", inherits = TRUE)) {
        normalize_db_params(list(metin))
      } else {
        list(metin)
      }
      DBI::dbSendQuery(conn, .pk_sql_unicode_wrapper(), params = parametreler)
    } else {
      DBI::dbSendQuery(conn, metin)
    }
  }, error = function(e) e)

  if (inherits(res, "condition")) {
    return(bos_sonuc("error", error = conditionMessage(res)))
  }

  # GARANTİLİ temizlik: iptal, son tarih, tavan aşımı ve beklenmeyen hata dahil
  # HER çıkış yolunda sonuç kümesi kapatılır. `after = FALSE` bilinçlidir:
  # temizlik, çağıranın bağlantı serbest bırakmasından ÖNCE çalışmalıdır.
  on.exit(tryCatch(DBI::dbClearResult(res), error = function(e) NULL), add = TRUE, after = FALSE)

  parcalar <- list()
  toplam_bayt <- 0
  toplam_satir <- 0L
  parca_sayisi <- 0L

  repeat {
    durum <- kapi()
    if (!identical(durum, "ok")) return(bos_sonuc(durum, chunks = parca_sayisi))

    parca <- tryCatch(DBI::dbFetch(res, n = parca_satir), error = function(e) e)
    if (inherits(parca, "condition")) {
      return(bos_sonuc("error", error = conditionMessage(parca), chunks = parca_sayisi))
    }
    if (!is.data.frame(parca) || nrow(parca) == 0L) break

    parca_bayt <- .pk_sql_frame_bytes(parca)
    karar <- pk_chunk_accumulate_decision(toplam_bayt, parca_bayt, max_result_mb)
    if (!identical(karar$action, "accept")) {
      # Tavanı aşacak parça KABUL EDİLMEZ; biriken parçalar da bırakılır ki
      # tam frame ile sınırsız bir hazırlık kopyası aynı anda tutulmasın.
      rm(parcalar)
      return(bos_sonuc("too_large", error = karar$reason, chunks = parca_sayisi))
    }

    parca_sayisi <- parca_sayisi + 1L
    parcalar[[parca_sayisi]] <- parca
    toplam_bayt <- karar$total_bytes
    toplam_satir <- toplam_satir + nrow(parca)

    if (nrow(parca) < parca_satir) break
  }

  veri <- if (parca_sayisi == 0L) {
    # Sonuç boş: sütun sözleşmesini korumak için 0 satırlı frame üret.
    tryCatch(DBI::dbFetch(res, n = 0L), error = function(e) data.frame())
  } else if (parca_sayisi == 1L) {
    parcalar[[1]]
  } else {
    tryCatch(do.call(rbind, parcalar), error = function(e) e)
  }

  if (inherits(veri, "condition")) {
    return(bos_sonuc("error", error = conditionMessage(veri), chunks = parca_sayisi))
  }

  list(status = "ok", data = veri, rows = nrow(veri), bytes = toplam_bayt,
       chunks = parca_sayisi, error = NA_character_)
}

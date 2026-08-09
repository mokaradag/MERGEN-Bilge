# ==============================================================================
# Dosya Yolu: R/helpers_pk_sql_execute.R
# Açıklama: Faz 6 (§5.10) — SINIRLI (bounded) SQL getirimi: fiziksel bağlantı
#           sabitleme, ifade/duvar-saati zaman aşımı, parça parça getirim,
#           iptal yoklaması ve GARANTİLİ sonuç-kümesi/bağlantı temizliği.
#
# `dbGetQuery()` tek atışta tüm sonucu materyalize eder. Bu yardımcı bunun
# yerine `dbSendQuery()` + sınırlı `dbFetch()` kullanır; havuz verildiyse aynı
# fiziksel bağlantıyı tüm ifade boyunca checkout eder. Üretim ODBC bağlantıları
# `interruptible_execution = TRUE` varsayılanıyla açılır: `setTimeLimit()` ile
# oluşturulan elapsed-time kesmesi odbc'nin kesilebilir yürütme döngüsünde
# aktif statement'a `SQLCancel` uygulanmasını tetikler. `SET LOCK_TIMEOUT` ise
# kilit beklemesi için ikinci, SQL Server'a özgü korumadır.
# ==============================================================================

#' İfade seviyesinde kilit zaman aşımını uygula (SQL Server, en iyi çaba)
#'
#' Pool nesnesinde AYAR YAPILMAZ: pool üzerinden iki ayrı DBI çağrısı farklı
#' fiziksel bağlantılara gidebilir. Çağıran önce fiziksel bağlantıyı checkout
#' etmeli, sonra bu fonksiyonu o bağlantıda çağırmalıdır.
#'
#' @return `list(mechanism = "lock_timeout"|"deferred_pool"|"none",
#'   applied = TRUE/FALSE, timeout_sec = <int>)`.
pk_sql_apply_statement_timeout <- function(conn, timeout_sec) {
  saniye <- suppressWarnings(as.integer(timeout_sec)[1])
  if (length(saniye) != 1L || is.na(saniye) || saniye <= 0L) {
    return(list(mechanism = "none", applied = FALSE, timeout_sec = 0L))
  }

  if (inherits(conn, "Pool")) {
    return(list(mechanism = "deferred_pool", applied = FALSE, timeout_sec = saniye))
  }

  if (is.null(conn) || !requireNamespace("DBI", quietly = TRUE)) {
    return(list(mechanism = "none", applied = FALSE, timeout_sec = saniye))
  }

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
# değil Unicode PARAMETRE olarak gönderilir.
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
#' @param conn Açık DB bağlantısı veya `pool::Pool`. Pool ise TEK fiziksel
#'   bağlantı checkout edilip `SET LOCK_TIMEOUT`, query ve fetch'ler aynı
#'   oturumda çalıştırılır; sonra ayar sıfırlanıp bağlantı iade edilir.
#' @param sql_text Salt-okunur kapısından GEÇMİŞ SQL metni.
#' @param unicode_param SQL Server Unicode parametre sarmalayıcısı kullanılsın mı.
#' @param chunk_rows Parça başına satır sayısı.
#' @param max_result_mb Süreçte bu sonuç için izin verilen yaklaşık tepe bellek.
#' @param stop_check Eski boolean iptal yoklayıcısı.
#' @param stage_gate Tipli iptal/son-tarih yoklayıcısı.
#' @param timeout_sec İfade zaman aşımı. NULL ise yapılandırmadan çözülür.
#' @param deadline_at Mutlak analiz son tarihi. NULL ise async worker seçeneği
#'   (`mergen.pk.async.deadline_at`) kullanılır.
#' @return `list(status = "ok"|"cancelled"|"deadline"|"timeout"|"too_large"|"error", ...)`.
pk_sql_execute_bounded <- function(conn, sql_text,
                                   unicode_param = TRUE,
                                   chunk_rows = 5000L,
                                   max_result_mb = 512,
                                   stop_check = NULL,
                                   stage_gate = NULL,
                                   timeout_sec = NULL,
                                   deadline_at = NULL) {
  bos_sonuc <- function(status, error = NA_character_, data = NULL,
                        rows = 0L, bytes = 0, chunks = 0L,
                        timeout_mechanism = "none") {
    list(status = status, data = data, rows = rows, bytes = bytes,
         chunks = chunks, error = error, timeout_mechanism = timeout_mechanism)
  }

  if (is.null(sql_text) || !nzchar(trimws(as.character(sql_text)[1]))) {
    return(bos_sonuc("error", error = "Bos SQL metni gonderilemez."))
  }
  if (is.null(conn) || !requireNamespace("DBI", quietly = TRUE)) {
    return(bos_sonuc("error", error = "DB baglantisi kullanilamiyor."))
  }

  parca_satir <- suppressWarnings(as.integer(chunk_rows)[1])
  if (length(parca_satir) != 1L || is.na(parca_satir) || parca_satir < 1L) parca_satir <- 5000L

  tavan_mb <- suppressWarnings(as.numeric(max_result_mb)[1])
  if (length(tavan_mb) != 1L || is.na(tavan_mb) || !is.finite(tavan_mb) || tavan_mb <= 0) {
    return(bos_sonuc("too_large", error = "ceiling_unresolved"))
  }

  if (is.null(deadline_at)) {
    deadline_at <- getOption("mergen.pk.async.deadline_at", NULL)
  }

  if (is.null(timeout_sec)) {
    timeout_sec <- if (exists("pk_config_resolve", mode = "function", inherits = TRUE)) {
      tryCatch(pk_config_resolve("MERGEN_PK_SQL_TIMEOUT_SEC"), error = function(e) 120L)
    } else {
      120L
    }
  }
  timeout_plan <- pk_sql_timeout_plan(
    timeout_sec,
    if (is.null(deadline_at)) Inf else pk_deadline_remaining_sec(deadline_at)
  )
  if (!isTRUE(timeout_plan$dispatch)) {
    return(bos_sonuc("deadline", error = timeout_plan$reason))
  }
  etkin_timeout <- suppressWarnings(as.numeric(timeout_plan$timeout_sec)[1])
  if (length(etkin_timeout) != 1L || is.na(etkin_timeout) || etkin_timeout < 0) etkin_timeout <- 0

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

  # Pool nesnesi bir DBI oturumu DEĞİLDİR. `SET LOCK_TIMEOUT` ile sorgunun aynı
  # SQL Server oturumunda kalması için TEK fiziksel bağlantı ödünç alınır.
  query_conn <- conn
  checked_out <- FALSE
  if (inherits(conn, "Pool")) {
    if (!requireNamespace("pool", quietly = TRUE)) {
      return(bos_sonuc("error", error = "Pool baglantisi icin 'pool' paketi gerekli."))
    }
    query_conn <- tryCatch(pool::poolCheckout(conn), error = function(e) e)
    if (inherits(query_conn, "condition")) {
      return(bos_sonuc("error", error = conditionMessage(query_conn)))
    }
    checked_out <- TRUE
  }

  zaman_asimi <- pk_sql_apply_statement_timeout(query_conn, etkin_timeout)
  odbc_kesilebilir <- inherits(query_conn, "OdbcConnection")
  mekanizma <- paste(
    c(if (odbc_kesilebilir) "odbc_interrupt" else character(0),
      if (isTRUE(zaman_asimi$applied)) "lock_timeout" else character(0)),
    collapse = "+"
  )
  if (!nzchar(mekanizma)) mekanizma <- zaman_asimi$mechanism %||% "none"

  on.exit({
    # Pooled bağlantıda oturum ayarı bir sonraki ödünç alana SIZMAMALIDIR.
    if (isTRUE(zaman_asimi$applied)) {
      try(DBI::dbExecute(query_conn, "SET LOCK_TIMEOUT -1"), silent = TRUE)
    }
    if (isTRUE(checked_out)) {
      try(pool::poolReturn(query_conn), silent = TRUE)
    }
  }, add = TRUE)

  # İfade bütçesi, send + bütün fetch çağrılarının ORTAK bütçesidir; her fetch'te
  # baştan başlamaz. Analiz mutlak son tarihi de ayrıca her çağrıdan önce yeniden
  # hesaplanır. Böylece DBI çağrısı blokluyken bile kalan bütçe üst sınırdır.
  ifade_son_tarihi <- if (is.finite(etkin_timeout) && etkin_timeout > 0) {
    Sys.time() + etkin_timeout
  } else {
    as.POSIXct(NA)
  }

  bloklayan_cagri <- function(fn) {
    kalan_analiz <- if (is.null(deadline_at)) Inf else pk_deadline_remaining_sec(deadline_at)
    kalan_ifade <- if (length(ifade_son_tarihi) == 1L && !is.na(ifade_son_tarihi)) {
      as.numeric(difftime(ifade_son_tarihi, Sys.time(), units = "secs"))
    } else {
      Inf
    }
    kalan <- min(kalan_analiz, kalan_ifade)

    if (is.finite(kalan) && kalan <= 0) {
      durum <- if (is.finite(kalan_analiz) && kalan_analiz <= 0) "deadline" else "timeout"
      return(list(ok = FALSE, status = durum, error = NA_character_))
    }

    deger <- tryCatch({
      if (is.finite(kalan)) {
        setTimeLimit(cpu = Inf, elapsed = max(0.05, kalan), transient = TRUE)
      }
      fn()
    }, error = function(e) e, finally = {
      if (is.finite(kalan)) try(setTimeLimit(cpu = Inf, elapsed = Inf, transient = TRUE), silent = TRUE)
    })

    if (!inherits(deger, "condition")) return(list(ok = TRUE, value = deger))

    kalan_analiz_son <- if (is.null(deadline_at)) Inf else pk_deadline_remaining_sec(deadline_at)
    kalan_ifade_son <- if (length(ifade_son_tarihi) == 1L && !is.na(ifade_son_tarihi)) {
      as.numeric(difftime(ifade_son_tarihi, Sys.time(), units = "secs"))
    } else {
      Inf
    }
    durum <- if (is.finite(kalan_analiz_son) && kalan_analiz_son <= 0) {
      "deadline"
    } else if (is.finite(kalan_ifade_son) && kalan_ifade_son <= 0) {
      "timeout"
    } else {
      "error"
    }
    list(ok = FALSE, status = durum, error = conditionMessage(deger))
  }

  metin <- enc2utf8(trimws(as.character(sql_text)[1]))
  gonderim <- bloklayan_cagri(function() {
    if (isTRUE(unicode_param)) {
      parametreler <- if (exists("normalize_db_params", mode = "function", inherits = TRUE)) {
        normalize_db_params(list(metin))
      } else {
        list(metin)
      }
      DBI::dbSendQuery(query_conn, .pk_sql_unicode_wrapper(), params = parametreler)
    } else {
      DBI::dbSendQuery(query_conn, metin)
    }
  })

  if (!isTRUE(gonderim$ok)) {
    return(bos_sonuc(gonderim$status, error = gonderim$error,
                     timeout_mechanism = mekanizma))
  }
  res <- gonderim$value

  # GARANTİLİ temizlik: sonuç kümesi bağlantı iadesinden ÖNCE kapanır.
  on.exit(tryCatch(DBI::dbClearResult(res), error = function(e) NULL), add = TRUE, after = FALSE)

  parcalar <- list()
  toplam_bayt <- 0
  toplam_satir <- 0L
  parca_sayisi <- 0L

  repeat {
    durum <- kapi()
    if (!identical(durum, "ok")) {
      return(bos_sonuc(durum, chunks = parca_sayisi, timeout_mechanism = mekanizma))
    }

    getirim <- bloklayan_cagri(function() DBI::dbFetch(res, n = parca_satir))
    if (!isTRUE(getirim$ok)) {
      return(bos_sonuc(getirim$status, error = getirim$error,
                       chunks = parca_sayisi, timeout_mechanism = mekanizma))
    }
    parca <- getirim$value
    if (!is.data.frame(parca) || nrow(parca) == 0L) break

    parca_bayt <- .pk_sql_frame_bytes(parca)

    # Çok parçalı sonuç sonunda `rbind` yeni bir tam frame üretir. İkinci parça
    # görüldüğü andan itibaren birikmiş parçalar için tavanın yarısı ayrılır;
    # kalan yarı final frame kopyası içindir. Tek parça ise kopya gerekmediğinden
    # tam tavanı kullanabilir.
    karar_tavani <- if (parca_sayisi == 0L) tavan_mb else tavan_mb / 2
    karar <- pk_chunk_accumulate_decision(toplam_bayt, parca_bayt, karar_tavani)
    if (!identical(karar$action, "accept")) {
      rm(parcalar)
      return(bos_sonuc("too_large", error = karar$reason,
                       chunks = parca_sayisi, timeout_mechanism = mekanizma))
    }

    # İlk parça tam chunk ise devamında ikinci parça gelebilir. İlk parça zaten
    # yarım tavanı aşıyorsa ikinci parça GELDİĞİNDE kabul edilmeyecek; tek parça
    # olarak biterse gereksiz yere reddedilmez.
    parca_sayisi <- parca_sayisi + 1L
    parcalar[[parca_sayisi]] <- parca
    toplam_bayt <- karar$total_bytes
    toplam_satir <- toplam_satir + nrow(parca)

    if (nrow(parca) < parca_satir) break
  }

  veri <- if (parca_sayisi == 0L) {
    bos_getirim <- bloklayan_cagri(function() DBI::dbFetch(res, n = 0L))
    if (!isTRUE(bos_getirim$ok)) {
      return(bos_sonuc(bos_getirim$status, error = bos_getirim$error,
                       chunks = 0L, timeout_mechanism = mekanizma))
    }
    bos_getirim$value
  } else if (parca_sayisi == 1L) {
    parcalar[[1]]
  } else {
    birlesik <- tryCatch(do.call(rbind, parcalar), error = function(e) e)
    if (inherits(birlesik, "condition")) {
      return(bos_sonuc("error", error = conditionMessage(birlesik),
                       chunks = parca_sayisi, timeout_mechanism = mekanizma))
    }
    birlesik
  }

  if (!is.data.frame(veri)) {
    return(bos_sonuc("error", error = "SQL sonucu data.frame degil.",
                     chunks = parca_sayisi, timeout_mechanism = mekanizma))
  }

  son_bayt <- .pk_sql_frame_bytes(veri)
  if (is.na(son_bayt) || son_bayt > tavan_mb * 1024 * 1024) {
    rm(veri)
    return(bos_sonuc("too_large", error = "would_exceed_max_result_mb",
                     chunks = parca_sayisi, timeout_mechanism = mekanizma))
  }

  list(status = "ok", data = veri, rows = nrow(veri), bytes = son_bayt,
       chunks = parca_sayisi, error = NA_character_,
       timeout_mechanism = mekanizma)
}

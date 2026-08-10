# ==============================================================================
# Faz 6: fiziksel bağlantı, duvar-saati timeout ve bellek tavanlı SQL getirimi.
# ==============================================================================

#' Kalan bütçeyle SINIRLI bloklayan DB çağrısı
#'
#' HER senkron sürücü çağrısı (checkout, kontrol ifadeleri, gönderim, getirim,
#' metadata, sonuç temizleme) bu sınırdan geçmelidir. Aksi hâlde tek bir askıda
#' kalan yardımcı çağrı, tüm analiz son tarihini ve iptali ETKİSİZ kılar:
#' istek zaman aşımına uğramış olsa bile işçi ve bağlantı meşgul kalır.
#'
#' @param budget_fn Kalan saniyeyi döndüren fonksiyon (`Inf` = bu katmanda
#'   bütçe yok).
#' @return `list(ok = TRUE, value = ) | list(ok = FALSE, status = , error = )`.
pk_sql_bounded_call <- function(fn, budget_fn, floor_sec = 0.05) {
  kalan <- tryCatch(budget_fn(), error = function(e) Inf)
  if (length(kalan) != 1L || is.na(kalan)) kalan <- Inf
  if (is.finite(kalan) && kalan <= 0) {
    return(list(ok = FALSE, status = "deadline", error = NA_character_))
  }

  deger <- tryCatch({
    if (is.finite(kalan)) {
      setTimeLimit(cpu = Inf, elapsed = max(floor_sec, kalan), transient = TRUE)
    }
    fn()
  }, error = function(e) e, finally = {
    if (is.finite(kalan)) {
      try(setTimeLimit(cpu = Inf, elapsed = Inf, transient = TRUE), silent = TRUE)
    }
  })

  if (!inherits(deger, "condition")) return(list(ok = TRUE, value = deger))
  list(ok = FALSE, status = "error", error = conditionMessage(deger))
}

# SQL Server oturum durumu olan LOCK_TIMEOUT, havuzdan alınan FİZİKSEL bir
# bağlantıda kalıcıdır. Eski kod temizlikte koşulsuz `-1` yazıyordu; bu, havuza
# iade edilen bağlantının ÖNCEKİ kilit-bekleme politikasını yok eder ve sonraki
# ilgisiz istekler sonsuza kadar bekleyebilir. Bu yüzden önceki değer okunur.
.pk_sql_read_lock_timeout <- function(conn, budget_fn) {
  okuma <- pk_sql_bounded_call(
    function() DBI::dbGetQuery(conn, "SELECT @@LOCK_TIMEOUT AS lt"), budget_fn
  )
  if (!isTRUE(okuma$ok) || !is.data.frame(okuma$value) || nrow(okuma$value) < 1L) {
    return(NA_integer_)
  }
  deger <- suppressWarnings(as.integer(okuma$value[[1]][1]))
  if (length(deger) != 1L || is.na(deger)) return(NA_integer_)
  deger
}

pk_sql_apply_statement_timeout <- function(conn, timeout_sec, budget_fn = NULL) {
  saniye <- suppressWarnings(as.integer(timeout_sec)[1])
  if (length(saniye) != 1L || is.na(saniye) || saniye <= 0L) {
    return(list(mechanism = "none", applied = FALSE, timeout_sec = 0L,
                previous = NA_integer_))
  }
  if (inherits(conn, "Pool")) {
    return(list(mechanism = "deferred_pool", applied = FALSE, timeout_sec = saniye,
                previous = NA_integer_))
  }
  if (is.null(conn) || !requireNamespace("DBI", quietly = TRUE)) {
    return(list(mechanism = "none", applied = FALSE, timeout_sec = saniye,
                previous = NA_integer_))
  }

  butce <- if (is.function(budget_fn)) budget_fn else function() Inf
  onceki <- .pk_sql_read_lock_timeout(conn, butce)

  uygulama <- pk_sql_bounded_call(
    function() DBI::dbExecute(conn, sprintf("SET LOCK_TIMEOUT %d", saniye * 1000L)),
    butce
  )
  if (isTRUE(uygulama$ok)) {
    return(list(mechanism = "lock_timeout", applied = TRUE, timeout_sec = saniye,
                previous = onceki))
  }
  list(mechanism = "none", applied = FALSE, timeout_sec = saniye, previous = onceki)
}

# Temizlikte ÖNCEKİ değeri geri yükle. Okunamamışsa `-1` (SQL Server
# varsayılanı) yazılır; bu, eski davranışın korunduğu tek durumdur.
.pk_sql_restore_lock_timeout <- function(conn, timeout_state, budget_fn) {
  if (!isTRUE(timeout_state$applied)) return(invisible(FALSE))
  onceki <- suppressWarnings(as.integer(timeout_state$previous)[1])
  hedef <- if (length(onceki) == 1L && !is.na(onceki)) onceki else -1L
  try(pk_sql_bounded_call(
    function() DBI::dbExecute(conn, sprintf("SET LOCK_TIMEOUT %d", hedef)),
    budget_fn
  ), silent = TRUE)
  invisible(TRUE)
}

.pk_sql_unicode_wrapper <- function() {
  paste("DECLARE @sql NVARCHAR(MAX);", "SET @sql = ?;", "EXEC sp_executesql @sql;", sep = "\n")
}

.pk_sql_frame_bytes <- function(df) {
  bayt <- tryCatch(as.numeric(utils::object.size(df)), error = function(e) NA_real_)
  if (length(bayt) != 1L || is.na(bayt) || !is.finite(bayt)) return(NA_real_)
  bayt
}

# NOT: eski `.pk_sql_has_unbounded_lob()` KALDIRILDI. İki ayrı kusuru vardı:
#
#   1) Sınıflandırma `dbColumnInfo()` çerçevesinin TÜM alanlarını (kolon ADI
#      dahil) düzleştirip tip adı arıyordu. Üretimdeki `odbc::OdbcResult`
#      yolunda `type` SAYISAL bir ODBC kodudur; dolayısıyla gerçek LOB'lar
#      YAKALANMIYOR, buna karşılık `text`/`xml` adlı bir kolon TAKMA ADI sonucu
#      tamamen reddedebiliyordu.
#   2) Kanıtlanamayan genişliği "kesinlikle çok büyük" sayıyordu. Kısa bir
#      `nvarchar(max)` değeri taşıyan TEK SATIRLIK sonuç da böylece
#      reddediliyordu — oysa sözleşme (§5.10) bu durumda ZORUNLU sınırlı-parça
#      getirimini seçmeyi söyler.
#
# Yerine `pk_sql_plan_chunk_rows()` (R/helpers_pk_result_size.R) kullanılır:
# metadata'dan KANITLANMIŞ satır genişliği türetilir, parça boyutu ona göre
# küçültülür ve kanıt yoksa granülarite tek satıra iner.

pk_sql_execute_bounded <- function(conn, sql_text, unicode_param = TRUE,
                                   chunk_rows = 5000L, max_result_mb = 512,
                                   stop_check = NULL, stage_gate = NULL,
                                   timeout_sec = NULL, deadline_at = NULL) {
  bos <- function(status, error = NA_character_, data = NULL, rows = 0L,
                  bytes = 0, chunks = 0L, timeout_mechanism = "none") {
    list(status = status, data = data, rows = rows, bytes = bytes, chunks = chunks,
         error = error, timeout_mechanism = timeout_mechanism)
  }
  if (is.null(sql_text) || !nzchar(trimws(as.character(sql_text)[1]))) {
    return(bos("error", error = "Bos SQL metni gonderilemez."))
  }
  if (is.null(conn) || !requireNamespace("DBI", quietly = TRUE)) {
    return(bos("error", error = "DB baglantisi kullanilamiyor."))
  }

  parca_satir <- suppressWarnings(as.integer(chunk_rows)[1])
  if (length(parca_satir) != 1L || is.na(parca_satir) || parca_satir < 1L) parca_satir <- 5000L
  tavan_mb <- suppressWarnings(as.numeric(max_result_mb)[1])
  if (length(tavan_mb) != 1L || is.na(tavan_mb) || !is.finite(tavan_mb) || tavan_mb <= 0) {
    return(bos("too_large", error = "ceiling_unresolved"))
  }
  if (is.null(deadline_at)) deadline_at <- getOption("mergen.pk.async.deadline_at", NULL)
  if (is.null(timeout_sec)) {
    timeout_sec <- if (exists("pk_config_resolve", mode = "function", inherits = TRUE)) {
      tryCatch(pk_config_resolve("MERGEN_PK_SQL_TIMEOUT_SEC"), error = function(e) 120L)
    } else 120L
  }

  plan <- pk_sql_timeout_plan(
    timeout_sec, if (is.null(deadline_at)) Inf else pk_deadline_remaining_sec(deadline_at)
  )
  if (!isTRUE(plan$dispatch)) return(bos("deadline", error = plan$reason))
  etkin_timeout <- suppressWarnings(as.numeric(plan$timeout_sec)[1])
  if (length(etkin_timeout) != 1L || is.na(etkin_timeout) || etkin_timeout < 0) etkin_timeout <- 0

  kapi <- function() {
    if (is.function(stage_gate)) {
      x <- tryCatch(stage_gate(), error = function(e) NULL)
      if (is.list(x) && isTRUE(x$halt)) return(as.character(x$status %||% "cancelled")[1])
      return("ok")
    }
    if (is.function(stop_check) &&
        isTRUE(tryCatch(stop_check(), error = function(e) FALSE))) return("cancelled")
    "ok"
  }
  ilk <- kapi()
  if (!identical(ilk, "ok")) return(bos(ilk))

  # Analiz bütçesi: kurulum/temizlik ÇAĞRILARI da bu bütçeden geçer.
  analiz_kalan <- function() {
    if (is.null(deadline_at)) Inf else pk_deadline_remaining_sec(deadline_at)
  }

  query_conn <- conn
  checked_out <- FALSE
  if (inherits(conn, "Pool")) {
    if (!requireNamespace("pool", quietly = TRUE)) {
      return(bos("error", error = "Pool baglantisi icin 'pool' paketi gerekli."))
    }
    # Checkout tek başına yeni bir FİZİKSEL ODBC bağlantısı kurabilir; yavaş bir
    # DSN/login burada kalan bütçeyi aşabilirdi.
    alim <- pk_sql_bounded_call(function() pool::poolCheckout(conn), analiz_kalan)
    if (!isTRUE(alim$ok)) {
      return(bos(if (identical(alim$status, "deadline")) "deadline" else "error",
                 error = alim$error))
    }
    query_conn <- alim$value
    checked_out <- TRUE
  }

  timeout_state <- pk_sql_apply_statement_timeout(query_conn, etkin_timeout, analiz_kalan)
  mekanizma <- paste(c(
    if (inherits(query_conn, "OdbcConnection")) "odbc_interrupt" else character(0),
    if (isTRUE(timeout_state$applied)) "lock_timeout" else character(0)
  ), collapse = "+")
  if (!nzchar(mekanizma)) mekanizma <- timeout_state$mechanism %||% "none"

  on.exit({
    # Temizlik de SINIRLIDIR: askıda kalan bir geri yükleme/iade çağrısı,
    # zaman aşımına uğramış bir isteğin işçisini ve bağlantısını tutmaya devam
    # ederdi. Temizliğin kendi tabanı vardır (bütçe tükense bile denenmelidir).
    temizlik_butce <- function() max(2, min(10, analiz_kalan()))
    .pk_sql_restore_lock_timeout(query_conn, timeout_state, temizlik_butce)
    if (isTRUE(checked_out)) {
      try(pk_sql_bounded_call(function() pool::poolReturn(query_conn), temizlik_butce),
          silent = TRUE)
    }
  }, add = TRUE)

  ifade_son_tarihi <- if (is.finite(etkin_timeout) && etkin_timeout > 0) {
    Sys.time() + etkin_timeout
  } else as.POSIXct(NA)

  ifade_kalan <- function() {
    if (!is.na(ifade_son_tarihi)) {
      as.numeric(difftime(ifade_son_tarihi, Sys.time(), units = "secs"))
    } else Inf
  }

  bloklayan <- function(fn) {
    kalan_analiz <- analiz_kalan()
    kalan_ifade <- ifade_kalan()
    kalan <- min(kalan_analiz, kalan_ifade)
    if (is.finite(kalan) && kalan <= 0) {
      return(list(ok = FALSE,
                  status = if (is.finite(kalan_analiz) && kalan_analiz <= 0) "deadline" else "timeout",
                  error = NA_character_))
    }

    sonuc <- pk_sql_bounded_call(fn, function() kalan)
    if (isTRUE(sonuc$ok)) return(sonuc)

    ka <- analiz_kalan()
    ki <- ifade_kalan()
    durum <- if (is.finite(ka) && ka <= 0) "deadline" else if (is.finite(ki) && ki <= 0) "timeout" else "error"
    list(ok = FALSE, status = durum, error = sonuc$error)
  }

  metin <- enc2utf8(trimws(as.character(sql_text)[1]))
  gonderim <- bloklayan(function() {
    if (isTRUE(unicode_param)) {
      params <- if (exists("normalize_db_params", mode = "function", inherits = TRUE)) {
        normalize_db_params(list(metin))
      } else list(metin)
      DBI::dbSendQuery(query_conn, .pk_sql_unicode_wrapper(), params = params)
    } else DBI::dbSendQuery(query_conn, metin)
  })
  if (!isTRUE(gonderim$ok)) {
    return(bos(gonderim$status, error = gonderim$error, timeout_mechanism = mekanizma))
  }
  res <- gonderim$value
  on.exit({
    try(pk_sql_bounded_call(function() DBI::dbClearResult(res),
                            function() max(2, min(10, analiz_kalan()))), silent = TRUE)
  }, add = TRUE, after = FALSE)

  # Metadata dbFetch()'ten ÖNCE okunur ve GÜVENLİ PARÇA BOYUTUNU belirler.
  # Sınırsız/bilinmeyen tip sonucu REDDETMEZ; yalnızca materyalizasyon
  # granülaritesini düşürür (bkz. pk_sql_plan_chunk_rows).
  meta_okuma <- bloklayan(function() DBI::dbColumnInfo(res))
  kolon_bilgisi <- if (isTRUE(meta_okuma$ok)) meta_okuma$value else NULL
  if (!isTRUE(meta_okuma$ok) && meta_okuma$status %in% c("deadline", "timeout")) {
    return(bos(meta_okuma$status, error = meta_okuma$error, timeout_mechanism = mekanizma))
  }

  parca_plani <- tryCatch(
    pk_sql_plan_chunk_rows(kolon_bilgisi, chunk_rows = parca_satir,
                           max_result_mb = tavan_mb),
    error = function(e) list(rows = parca_satir, bounded = FALSE,
                             reason = "plan_failed")
  )
  parca_satir <- max(1L, suppressWarnings(as.integer(parca_plani$rows)[1]))
  if (is.na(parca_satir)) parca_satir <- 1L

  parcalar <- list()
  toplam_bayt <- 0
  toplam_satir <- 0L
  parca_sayisi <- 0L
  repeat {
    durum <- kapi()
    if (!identical(durum, "ok")) return(bos(durum, chunks = parca_sayisi,
                                             timeout_mechanism = mekanizma))
    getirim <- bloklayan(function() DBI::dbFetch(res, n = parca_satir))
    if (!isTRUE(getirim$ok)) {
      return(bos(getirim$status, error = getirim$error, chunks = parca_sayisi,
                 timeout_mechanism = mekanizma))
    }
    parca <- getirim$value
    if (!is.data.frame(parca) || nrow(parca) == 0L) break

    parca_bayt <- .pk_sql_frame_bytes(parca)
    karar <- pk_chunk_accumulate_decision(
      toplam_bayt, parca_bayt, if (parca_sayisi == 0L) tavan_mb else tavan_mb / 2
    )
    if (!identical(karar$action, "accept")) {
      rm(parcalar)
      return(bos("too_large", error = karar$reason, chunks = parca_sayisi,
                 timeout_mechanism = mekanizma))
    }
    parca_sayisi <- parca_sayisi + 1L
    parcalar[[parca_sayisi]] <- parca
    toplam_bayt <- karar$total_bytes
    toplam_satir <- toplam_satir + nrow(parca)
    if (nrow(parca) < parca_satir) break
  }

  if (parca_sayisi == 0L) {
    bos_fetch <- bloklayan(function() DBI::dbFetch(res, n = 0L))
    if (!isTRUE(bos_fetch$ok)) return(bos(bos_fetch$status, error = bos_fetch$error,
                                          timeout_mechanism = mekanizma))
    veri <- bos_fetch$value
  } else if (parca_sayisi == 1L) {
    veri <- parcalar[[1]]
  } else {
    # BİRLEŞTİRME de pahalı bir aşamadır: `rbind` bir an için parçaların TAMAMI
    # ile birleşik frame'i AYNI ANDA tutar. Bu yüzden (a) hemen önce kapı tekrar
    # yoklanır ve (b) ikili tepe kullanımı tavana karşı kontrol edilir.
    durum <- kapi()
    if (!identical(durum, "ok")) {
      return(bos(durum, chunks = parca_sayisi, timeout_mechanism = mekanizma))
    }
    if (is.finite(toplam_bayt) && (toplam_bayt * 2) > tavan_mb * 1024 * 1024) {
      rm(parcalar)
      return(bos("too_large", error = "assembly_would_exceed_max_result_mb",
                 chunks = parca_sayisi, timeout_mechanism = mekanizma))
    }

    birlestirme <- bloklayan(function() do.call(rbind, parcalar))
    if (!isTRUE(birlestirme$ok)) {
      return(bos(birlestirme$status, error = birlestirme$error,
                 chunks = parca_sayisi, timeout_mechanism = mekanizma))
    }
    veri <- birlestirme$value

    # Birleştirmeden SONRA da kapı yoklanır: durdurulan bir istek buradan
    # `ok` ile çıkmamalıdır.
    durum <- kapi()
    if (!identical(durum, "ok")) {
      return(bos(durum, chunks = parca_sayisi, timeout_mechanism = mekanizma))
    }
  }

  son_bayt <- .pk_sql_frame_bytes(veri)
  if (!is.data.frame(veri)) return(bos("error", error = "SQL sonucu data.frame degil.",
                                       chunks = parca_sayisi, timeout_mechanism = mekanizma))
  if (is.na(son_bayt) || son_bayt > tavan_mb * 1024 * 1024) {
    rm(veri)
    return(bos("too_large", error = "would_exceed_max_result_mb",
               chunks = parca_sayisi, timeout_mechanism = mekanizma))
  }
  list(status = "ok", data = veri, rows = nrow(veri), bytes = son_bayt,
       chunks = parca_sayisi, error = NA_character_, timeout_mechanism = mekanizma)
}
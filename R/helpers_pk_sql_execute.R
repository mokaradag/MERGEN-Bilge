# ==============================================================================
# Faz 6: fiziksel bağlantı, duvar-saati timeout ve bellek tavanlı SQL getirimi.
# ==============================================================================

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

.pk_sql_unicode_wrapper <- function() {
  paste("DECLARE @sql NVARCHAR(MAX);", "SET @sql = ?;", "EXEC sp_executesql @sql;", sep = "\n")
}

.pk_sql_frame_bytes <- function(df) {
  bayt <- tryCatch(as.numeric(utils::object.size(df)), error = function(e) NA_real_)
  if (length(bayt) != 1L || is.na(bayt) || !is.finite(bayt)) return(NA_real_)
  bayt
}

# A DBI chunk sınırı SATIR sayısını sınırlar; tek bir satırdaki NVARCHAR(MAX),
# XML veya benzeri LOB yine dbFetch() içinde belleği aşabilir. Bu yüzden sonuç
# metadata'sı ilk satır materialize edilmeden incelenir. Yalnızca açıkça
# sınırsız/LOB olduğu kanıtlanan tipler reddedilir; eksik metadata fail-open
# bırakılır ki normal sabit genişlikli kolonlar yanlışlıkla engellenmesin.
.pk_sql_has_unbounded_lob <- function(column_info) {
  if (is.null(column_info) || !is.data.frame(column_info) || nrow(column_info) == 0L) {
    return(FALSE)
  }

  metadata_text <- unlist(lapply(column_info, function(x) {
    tryCatch(as.character(x), error = function(e) character(0))
  }), use.names = FALSE)
  metadata_text <- tolower(trimws(metadata_text))
  metadata_text <- metadata_text[!is.na(metadata_text) & nzchar(metadata_text)]

  if (any(grepl("\\b(n?varchar|varbinary)\\s*\\(\\s*max\\s*\\)",
                metadata_text, perl = TRUE))) {
    return(TRUE)
  }

  explicit_lob <- c(
    "text", "ntext", "image", "xml", "sql_variant", "json",
    "geography", "geometry", "longvarchar", "wlongvarchar", "longvarbinary"
  )
  if (any(metadata_text %in% explicit_lob)) return(TRUE)
  if (any(grepl("(^|[^a-z])(longvarchar|wlongvarchar|longvarbinary)([^a-z]|$)",
                metadata_text, perl = TRUE))) {
    return(TRUE)
  }

  alanlar <- tolower(names(column_info))
  tip_idx <- which(alanlar %in% c("type", "data_type", "sql_type", "type_name", "typename"))
  boyut_idx <- which(alanlar %in% c("max_length", "column_size", "length"))
  if (length(tip_idx) > 0L && length(boyut_idx) > 0L) {
    tipler <- tolower(trimws(as.character(column_info[[tip_idx[1L]]])))
    boyutlar <- suppressWarnings(as.numeric(column_info[[boyut_idx[1L]]]))
    if (any(tipler %in% c("varchar", "nvarchar", "varbinary") &
            !is.na(boyutlar) & boyutlar < 0, na.rm = TRUE)) {
      return(TRUE)
    }
  }

  FALSE
}

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

  query_conn <- conn
  checked_out <- FALSE
  if (inherits(conn, "Pool")) {
    if (!requireNamespace("pool", quietly = TRUE)) {
      return(bos("error", error = "Pool baglantisi icin 'pool' paketi gerekli."))
    }
    query_conn <- tryCatch(pool::poolCheckout(conn), error = function(e) e)
    if (inherits(query_conn, "condition")) return(bos("error", error = conditionMessage(query_conn)))
    checked_out <- TRUE
  }

  timeout_state <- pk_sql_apply_statement_timeout(query_conn, etkin_timeout)
  mekanizma <- paste(c(
    if (inherits(query_conn, "OdbcConnection")) "odbc_interrupt" else character(0),
    if (isTRUE(timeout_state$applied)) "lock_timeout" else character(0)
  ), collapse = "+")
  if (!nzchar(mekanizma)) mekanizma <- timeout_state$mechanism %||% "none"

  on.exit({
    if (isTRUE(timeout_state$applied)) {
      try(DBI::dbExecute(query_conn, "SET LOCK_TIMEOUT -1"), silent = TRUE)
    }
    if (isTRUE(checked_out)) try(pool::poolReturn(query_conn), silent = TRUE)
  }, add = TRUE)

  ifade_son_tarihi <- if (is.finite(etkin_timeout) && etkin_timeout > 0) {
    Sys.time() + etkin_timeout
  } else as.POSIXct(NA)

  bloklayan <- function(fn) {
    kalan_analiz <- if (is.null(deadline_at)) Inf else pk_deadline_remaining_sec(deadline_at)
    kalan_ifade <- if (!is.na(ifade_son_tarihi)) {
      as.numeric(difftime(ifade_son_tarihi, Sys.time(), units = "secs"))
    } else Inf
    kalan <- min(kalan_analiz, kalan_ifade)
    if (is.finite(kalan) && kalan <= 0) {
      return(list(ok = FALSE,
                  status = if (is.finite(kalan_analiz) && kalan_analiz <= 0) "deadline" else "timeout",
                  error = NA_character_))
    }

    deger <- tryCatch({
      if (is.finite(kalan)) setTimeLimit(cpu = Inf, elapsed = max(0.05, kalan), transient = TRUE)
      fn()
    }, error = function(e) e, finally = {
      if (is.finite(kalan)) try(setTimeLimit(cpu = Inf, elapsed = Inf, transient = TRUE), silent = TRUE)
    })
    if (!inherits(deger, "condition")) return(list(ok = TRUE, value = deger))

    ka <- if (is.null(deadline_at)) Inf else pk_deadline_remaining_sec(deadline_at)
    ki <- if (!is.na(ifade_son_tarihi)) {
      as.numeric(difftime(ifade_son_tarihi, Sys.time(), units = "secs"))
    } else Inf
    durum <- if (is.finite(ka) && ka <= 0) "deadline" else if (is.finite(ki) && ki <= 0) "timeout" else "error"
    list(ok = FALSE, status = durum, error = conditionMessage(deger))
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
  on.exit(try(DBI::dbClearResult(res), silent = TRUE), add = TRUE, after = FALSE)

  # LOB metadata kontrolü dbFetch()'ten ÖNCE yapılır; aksi halde tek bir dev
  # hücre satır-parça sınırını aşarak süreç belleğinde materialize olabilir.
  kolon_bilgisi <- tryCatch(DBI::dbColumnInfo(res), error = function(e) NULL)
  if (isTRUE(.pk_sql_has_unbounded_lob(kolon_bilgisi))) {
    return(bos("too_large", error = "unbounded_lob_schema",
               timeout_mechanism = mekanizma))
  }

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
    veri <- tryCatch(do.call(rbind, parcalar), error = function(e) e)
    if (inherits(veri, "condition")) return(bos("error", error = conditionMessage(veri),
                                                chunks = parca_sayisi,
                                                timeout_mechanism = mekanizma))
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
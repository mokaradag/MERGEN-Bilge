# ==============================================================================
# Faz 6: future işçisi PK giriş noktası.
# ==============================================================================

.pk_async_log <- function(fmt, ...) {
  metin <- try(sprintf(fmt, ...), silent = TRUE)
  if (!inherits(metin, "try-error")) try(cat(metin, "\n", sep = ""), silent = TRUE)
  invisible(NULL)
}

pk_async_run_analysis <- function(request) {
  basladi <- Sys.time()
  tanilama <- list(bootstrap_cached = NA, bootstrap_loaded = 0L,
                   bootstrap_failed = character(0), entry_missing = character(0),
                   duration_ms = 0)

  bitir <- function(status, result = NULL, session_writes = list(), error = NA_character_) {
    tanilama$duration_ms <- as.numeric(difftime(Sys.time(), basladi, units = "secs")) * 1000
    list(status = status, result = result, session_writes = session_writes,
         error = error, diagnostics = tanilama)
  }
  if (!is.list(request)) return(bitir("error", error = "Gecersiz istek anlik goruntusu."))

  boot <- tryCatch(
    pk_async_worker_bootstrap(request$repo_root, request$bootstrap_files),
    error = function(e) list(ok = FALSE, loaded = 0L, failed = conditionMessage(e), cached = FALSE)
  )
  tanilama$bootstrap_cached <- isTRUE(boot$cached)
  tanilama$bootstrap_loaded <- as.integer(boot$loaded %||% 0L)
  tanilama$bootstrap_failed <- as.character(boot$failed %||% character(0))
  if (!isTRUE(boot$ok)) {
    .pk_async_log("[PK_ASYNC] Isci bootstrap basarisiz: %s",
                  paste(utils::head(tanilama$bootstrap_failed, 5L), collapse = ", "))
    return(bitir("bootstrap_failed", error = "Isci yardimcilari yuklenemedi."))
  }

  hazir <- try(pk_async_worker_ready(), silent = TRUE)
  if (inherits(hazir, "try-error")) hazir <- list(ready = FALSE, missing = "unknown")
  if (!isTRUE(hazir$ready)) {
    tanilama$entry_missing <- as.character(hazir$missing %||% character(0))
    return(bitir("bootstrap_failed", error = "Isci giris noktalari eksik."))
  }

  # Token path ve deadline ana süreçte dispatch anında belirlenmiştir.
  jeton <- as.character(request$cancel_token %||% "")[1]
  if (!nzchar(jeton)) jeton <- NULL
  baslangic <- tryCatch(
    as.POSIXct(as.numeric(request$started_at_epoch %||% NA_real_), origin = "1970-01-01"),
    error = function(e) basladi
  )
  if (length(baslangic) != 1L || is.na(baslangic)) baslangic <- basladi
  son_tarih <- pk_deadline_at(baslangic, request$deadline_sec)

  stop_check <- function() isTRUE(pk_async_stage_gate(jeton, son_tarih)$halt)
  ilk_kapi <- pk_async_stage_gate(jeton, son_tarih)
  if (isTRUE(ilk_kapi$halt)) return(bitir(ilk_kapi$status))

  eski_deadline_option <- getOption("mergen.pk.async.deadline_at", NULL)
  options(mergen.pk.async.deadline_at = son_tarih)
  on.exit(options(mergen.pk.async.deadline_at = eski_deadline_option), add = TRUE)

  vekil <- tryCatch(pk_async_worker_session(request), error = function(e) NULL)
  if (is.null(vekil)) return(bitir("error", error = "Oturum vekili kurulamadi."))

  motor <- as.character(request$engine %||% "")[1]
  if (motor %in% c("v1", "v2")) {
    eski_motor <- getOption("mergen.pk.engine", NULL)
    options(mergen.pk.engine = motor)
    on.exit(options(mergen.pk.engine = eski_motor), add = TRUE)
  }

  # Bootstrap edilen gerçek PK giriş noktası kendi lexical ortamında global
  # yardımcıları çözer. Override'lar async wrapper'ın değil BU pipeline ortamına
  # yazılmalıdır; PSOCK'ta ikisi aynı olmak zorunda değildir.
  target_env <- environment(pk_analiz_process_request)
  eski_unicode <- get0("execute_pk_sql_unicode", envir = target_env,
                       inherits = TRUE, ifnotfound = NULL)
  chunk_rows <- tryCatch(pk_config_resolve("MERGEN_PK_FETCH_CHUNK_ROWS"),
                         error = function(e) 5000L)
  max_mb <- tryCatch(pk_config_resolve("MERGEN_PK_MAX_RESULT_MB"),
                     error = function(e) 512L)
  sql_timeout <- tryCatch(pk_config_resolve("MERGEN_PK_SQL_TIMEOUT_SEC"),
                          error = function(e) 120L)

  bounded_unicode <- function(conn, sql_text) {
    exec <- pk_sql_execute_bounded(
      conn, sql_text, unicode_param = TRUE, chunk_rows = chunk_rows,
      max_result_mb = max_mb,
      stage_gate = function() pk_async_stage_gate(jeton, son_tarih),
      timeout_sec = sql_timeout, deadline_at = son_tarih
    )
    if (identical(exec$status, "ok")) return(exec$data)
    if (exec$status %in% c("cancelled", "deadline")) return(pk_async_halt_message(exec$status))
    if (identical(exec$status, "too_large")) {
      return(get0("PK_RESULT_TOO_LARGE_MESSAGE", inherits = TRUE,
                  ifnotfound = "\U0001F50D **Sonuç Kümesi Çok Büyük:** Lütfen sorunuzu daraltın."))
    }
    if (identical(exec$status, "timeout")) {
      return("\U000023F1\U0000FE0F **Sorgu Zaman Aşımı:** Sorgu ayrılan sürede tamamlanamadı.")
    }
    stop(as.character(exec$error %||% "Sorgu calistirilamadi.")[1], call. = FALSE)
  }
  assign("execute_pk_sql_unicode", bounded_unicode, envir = target_env)
  on.exit({
    if (is.function(eski_unicode)) assign("execute_pk_sql_unicode", eski_unicode, envir = target_env)
  }, add = TRUE)

  # Deep orkestratörün içeride türettiği iki kurucu dispatch bağlamına sabitlenir.
  if (isTRUE(request$deep_thinking)) {
    eski_deadline_fn <- get0("pk_deadline_at", envir = target_env, inherits = TRUE)
    eski_token_fn <- get0("pk_cancel_token_path", envir = target_env, inherits = TRUE)
    assign("pk_deadline_at", function(started_at, deadline_sec) son_tarih, envir = target_env)
    assign("pk_cancel_token_path", function(request_id, base_dir = NULL) jeton, envir = target_env)
    on.exit({
      assign("pk_deadline_at", eski_deadline_fn, envir = target_env)
      assign("pk_cancel_token_path", eski_token_fn, envir = target_env)
    }, add = TRUE)
  }

  sonuc <- tryCatch({
    if (isTRUE(request$deep_thinking) &&
        exists("pk_deep_analysis_process", mode = "function", inherits = TRUE)) {
      pk_deep_analysis_process(
        request$user_prompt, request$chat_history, vekil,
        detail_level = request$detail_level, stop_check = stop_check
      )
    } else {
      pk_analiz_process_request(
        request$user_prompt, request$chat_history, vekil, stop_check = stop_check
      )
    }
  }, error = function(e) {
    .pk_async_log("[PK_ASYNC] Boru hatti hatasi: %s",
                  .pk_async_safe_error_text(conditionMessage(e)))
    structure(list(message = conditionMessage(e)), class = "pk_async_pipeline_error")
  })

  yazimlar <- tryCatch(pk_async_harvest_session(vekil), error = function(e) list())
  son_kapi <- pk_async_stage_gate(jeton, son_tarih)
  if (isTRUE(son_kapi$halt)) return(bitir(son_kapi$status, session_writes = yazimlar))
  if (inherits(sonuc, "pk_async_pipeline_error")) {
    return(bitir("error", session_writes = yazimlar,
                 error = .pk_async_safe_error_text(sonuc$message)))
  }

  # Ana süreç data'yı tüketmez; büyük frame future IPC'den önce bırakılır.
  if (is.list(sonuc) && !is.null(sonuc$data)) sonuc$data <- NULL
  bitir("ok", result = sonuc, session_writes = yazimlar)
}

.pk_async_safe_error_text <- function(message) {
  ham <- tryCatch(as.character(message)[1], error = function(e) NA_character_)
  if (is.null(ham) || !length(ham) || is.na(ham) || !nzchar(ham)) {
    return("Bilinmeyen analiz hatasi.")
  }
  if (exists("redact_sensitive_text", mode = "function", inherits = TRUE)) {
    ham <- tryCatch(redact_sensitive_text(ham), error = function(e) ham)
  }
  altyapi <- c("nanodbc", "SQLSTATE", "DSN=", "ODBC", "Driver", "sp_executesql",
               "TCP Provider", "SQL Server")
  if (any(vapply(altyapi, function(p) grepl(p, ham, fixed = TRUE), logical(1)))) {
    return("Veritabani erisiminde teknik bir hata olustu.")
  }
  substr(ham, 1L, 400L)
}

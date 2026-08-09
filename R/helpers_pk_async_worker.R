# ==============================================================================
# Dosya Yolu: R/helpers_pk_async_worker.R
# Açıklama: Faz 6 (§5.10) — İŞÇİ giriş noktası. Düz istek anlık görüntüsünü alır,
#           işçi tarafında yardımcıları bootstrap eder, OTURUM VEKİLİ kurar,
#           boru hattını çalıştırır ve HER çıkış yolunda kaynakları bırakır.
#
# Bu fonksiyon FUTURE İŞÇİSİNDE çalışır. Bu yüzden:
#   * Shiny/reaktif erişimi YOKTUR (vekil oturum düz bir ortamdır),
#   * DB bağlantısı İŞÇİDE açılır ve İŞÇİDE bırakılır,
#   * `stop_check` burada YEREL bir kapanıştır — serileştirme sorunu yoktur;
#     iptal jetonunu (dosya) ve son tarihi yoklar,
#   * standart ve derin SQL yolları AYNI bounded executor'a bağlanır,
#   * asla `stop()` ile dışarı sızmaz: her sonuç TİPLİ bir listedir.
# ==============================================================================

# Loglama işçide appender'sız olabilir; bu yüzden başarısızlığa dayanıklı sarmalayıcı.
.pk_async_log <- function(fmt, ...) {
  metin <- tryCatch(sprintf(fmt, ...), error = function(e) NA_character_)
  if (is.na(metin)) return(invisible(NULL))
  tryCatch(cat(metin, "\n", sep = ""), error = function(e) NULL)
  invisible(NULL)
}

#' İşçi tarafında PK analizini çalıştır
#'
#' @param request `pk_async_build_request()` çıktısı (DÜZ liste).
#' @return `list(status=, result=, session_writes=, diagnostics=)`.
#'   `status`: `ok` | `cancelled` | `deadline` | `bootstrap_failed` | `error`.
pk_async_run_analysis <- function(request) {
  basladi <- Sys.time()

  tanilama <- list(
    bootstrap_cached = NA,
    bootstrap_loaded = 0L,
    bootstrap_failed = character(0),
    entry_missing = character(0),
    duration_ms = 0
  )

  bitir <- function(status, result = NULL, session_writes = list(), error = NA_character_) {
    tanilama$duration_ms <- as.numeric(difftime(Sys.time(), basladi, units = "secs")) * 1000
    list(
      status = status,
      result = result,
      session_writes = session_writes,
      error = error,
      diagnostics = tanilama
    )
  }

  if (!is.list(request)) return(bitir("error", error = "Gecersiz istek anlik goruntusu."))

  # --- 1) İşçi bootstrap (SÜREÇ BAŞINA BİR KEZ) -------------------------------
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

  hazir <- tryCatch(pk_async_worker_ready(), error = function(e) list(ready = FALSE, missing = "unknown"))
  if (!isTRUE(hazir$ready)) {
    tanilama$entry_missing <- as.character(hazir$missing %||% character(0))
    .pk_async_log("[PK_ASYNC] Isci giris noktalari eksik: %s",
                  paste(tanilama$entry_missing, collapse = ", "))
    return(bitir("bootstrap_failed", error = "Isci giris noktalari eksik."))
  }

  # --- 2) İptal jetonu + MUTLAK son tarih ------------------------------------
  # `cancel_token` ve `started_at_epoch` ANA SÜREÇTE üretildi. İşçi bunları
  # yeniden tempdir()/Sys.time() üzerinden ÜRETMEZ; aksi hâlde PSOCK süreçleri
  # farklı tempdir kullandığında iptal görünmez ve kuyruk bekleme süresi analiz
  # bütçesine sayılmazdı.
  jeton <- as.character(request$cancel_token %||% "")[1]
  if (!nzchar(jeton)) jeton <- NULL

  baslangic <- tryCatch(
    as.POSIXct(as.numeric(request$started_at_epoch %||% NA_real_), origin = "1970-01-01"),
    error = function(e) basladi
  )
  if (length(baslangic) != 1L || is.na(baslangic)) baslangic <- basladi

  son_tarih <- pk_deadline_at(baslangic, request$deadline_sec)

  stop_check <- function() {
    kapi <- pk_async_stage_gate(jeton, son_tarih)
    isTRUE(kapi$halt)
  }

  ilk_kapi <- pk_async_stage_gate(jeton, son_tarih)
  if (isTRUE(ilk_kapi$halt)) return(bitir(ilk_kapi$status))

  # Bounded SQL alt katmanı da aynı dispatch-time mutlak son tarihi görür.
  eski_deadline_option <- getOption("mergen.pk.async.deadline_at", default = NULL)
  options(mergen.pk.async.deadline_at = son_tarih)
  on.exit(options(mergen.pk.async.deadline_at = eski_deadline_option), add = TRUE)

  # --- 3) Oturum vekili ------------------------------------------------------
  vekil <- tryCatch(pk_async_worker_session(request), error = function(e) NULL)
  if (is.null(vekil)) return(bitir("error", error = "Oturum vekili kurulamadi."))

  # Motor kipi işçide de AYNI çözülmelidir.
  motor <- as.character(request$engine %||% "")[1]
  if (motor %in% c("v1", "v2")) {
    eski_motor <- getOption("mergen.pk.engine", default = NULL)
    options(mergen.pk.engine = motor)
    on.exit(options(mergen.pk.engine = eski_motor), add = TRUE)
  }

  # --- 4) Standart SQL yolunu bounded executor'a bağla -----------------------
  # `module_proje_kaynak_analizi.R` geriye dönük olarak
  # `execute_pk_sql_unicode()` çağırır. Worker içinde bu TEK giriş noktasını
  # geçici olarak bounded executor'a yönlendiririz; süreç yeniden kullanılırsa
  # global fonksiyon MUTLAKA geri yüklenir.
  eski_unicode <- get0("execute_pk_sql_unicode", envir = .GlobalEnv,
                       inherits = FALSE, ifnotfound = NULL)
  had_unicode <- is.function(eski_unicode)

  bounded_unicode <- function(conn, sql_text) {
    coz <- function(key, fallback) {
      if (!exists("pk_config_resolve", mode = "function", inherits = TRUE)) return(fallback)
      tryCatch(pk_config_resolve(key), error = function(e) fallback)
    }

    exec <- pk_sql_execute_bounded(
      conn = conn,
      sql_text = sql_text,
      unicode_param = TRUE,
      chunk_rows = coz("MERGEN_PK_FETCH_CHUNK_ROWS", 5000L),
      max_result_mb = coz("MERGEN_PK_MAX_RESULT_MB", 512L),
      stage_gate = function() pk_async_stage_gate(jeton, son_tarih),
      timeout_sec = coz("MERGEN_PK_SQL_TIMEOUT_SEC", 120L),
      deadline_at = son_tarih
    )

    if (identical(exec$status, "ok")) return(exec$data)
    if (identical(exec$status, "cancelled")) return(pk_async_halt_message("cancelled"))
    if (identical(exec$status, "deadline")) return(pk_async_halt_message("deadline"))
    if (identical(exec$status, "too_large")) {
      return(if (exists("PK_RESULT_TOO_LARGE_MESSAGE", inherits = TRUE)) {
        get("PK_RESULT_TOO_LARGE_MESSAGE", inherits = TRUE)
      } else {
        "\U0001F50D **Sonuç Kümesi Çok Büyük:** Sonuç güvenli bellek sınırını aşıyor."
      })
    }
    if (identical(exec$status, "timeout")) {
      return(paste0(
        "\U000023F1\U0000FE0F **Sorgu Zaman Aşımı:** Veritabanı sorgusu ayrılan süre içinde ",
        "tamamlanamadı. Lütfen sorunuzu daraltıp tekrar deneyin."
      ))
    }

    hata <- as.character(exec$error %||% "Sorgu calistirilamadi.")[1]
    stop(hata, call. = FALSE)
  }

  assign("execute_pk_sql_unicode", bounded_unicode, envir = .GlobalEnv)
  on.exit({
    if (isTRUE(had_unicode)) {
      assign("execute_pk_sql_unicode", eski_unicode, envir = .GlobalEnv)
    } else if (exists("execute_pk_sql_unicode", envir = .GlobalEnv, inherits = FALSE)) {
      rm("execute_pk_sql_unicode", envir = .GlobalEnv)
    }
  }, add = TRUE)

  # --- 5) Derin yolun eski türetilmiş bağlamını dispatch bağlamına sabitle ---
  # Derin orkestratör tarih/token bilgisini tarihsel olarak içeride yeniden
  # türetiyor. İmzasını tüm çağıranlarda kırmadan worker sürecinde yalnızca bu
  # istek süresince iki saf kurucuyu sabitliyoruz. Böylece:
  #   - deadline başlangıcı worker'ın çalışmaya BAŞLADIĞI an değil dispatch anıdır,
  #   - cancel path worker tempdir'ından tekrar üretilmez; ana süreçteki TAM yol
  #     kullanılır.
  if (isTRUE(request$deep_thinking)) {
    eski_deadline_fn <- get0("pk_deadline_at", envir = .GlobalEnv,
                             inherits = FALSE, ifnotfound = NULL)
    eski_token_fn <- get0("pk_cancel_token_path", envir = .GlobalEnv,
                          inherits = FALSE, ifnotfound = NULL)
    had_deadline_fn <- is.function(eski_deadline_fn)
    had_token_fn <- is.function(eski_token_fn)

    assign("pk_deadline_at", function(started_at, deadline_sec) son_tarih, envir = .GlobalEnv)
    assign("pk_cancel_token_path", function(request_id, base_dir = NULL) jeton, envir = .GlobalEnv)

    on.exit({
      if (isTRUE(had_deadline_fn)) assign("pk_deadline_at", eski_deadline_fn, envir = .GlobalEnv)
      if (isTRUE(had_token_fn)) assign("pk_cancel_token_path", eski_token_fn, envir = .GlobalEnv)
    }, add = TRUE)
  }

  # --- 6) Boru hattını çalıştır ---------------------------------------------
  sonuc <- tryCatch({
    if (isTRUE(request$deep_thinking) &&
        exists("pk_deep_analysis_process", mode = "function", inherits = TRUE)) {
      pk_deep_analysis_process(
        request$user_prompt, request$chat_history, vekil,
        detail_level = request$detail_level,
        stop_check = stop_check
      )
    } else {
      pk_analiz_process_request(
        request$user_prompt, request$chat_history, vekil,
        stop_check = stop_check
      )
    }
  }, error = function(e) {
    .pk_async_log("[PK_ASYNC] Boru hatti hatasi (redakte): %s",
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

  # `data` alanı ana süreçte hiçbir zaman tüketilmiyor; prompt_context /
  # user_context / pk_answer_block ve attachment zaten worker içinde üretildi.
  # Tam frame'i future IPC üzerinden ikinci kez taşımak büyük sonuçlarda RAM'i
  # ikiye katlar. Bu yüzden yalnızca IPC'den HEMEN ÖNCE bırakılır.
  if (is.list(sonuc) && !is.null(sonuc$data)) sonuc$data <- NULL

  bitir("ok", result = sonuc, session_writes = yazimlar)
}

# Hata metni işçiden ana sürece taşınır ve loglanır; ham ODBC/DSN tanılaması
# TAŞINMAZ (D22 sözleşmesi işçide de geçerlidir).
.pk_async_safe_error_text <- function(message) {
  ham <- tryCatch(as.character(message)[1], error = function(e) NA_character_)
  if (is.null(ham) || length(ham) == 0L || is.na(ham) || !nzchar(ham)) {
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

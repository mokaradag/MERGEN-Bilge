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
#     iptal jetonunu (dosya) ve son tarihi yoklar, böylece mevcut boru hattının
#     aşama kontrolleri DEĞİŞTİRİLMEDEN iptal-farkında hâle gelir,
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

  # --- 2) İptal jetonu + son tarih -------------------------------------------
  jeton <- as.character(request$cancel_token %||% "")[1]
  if (!nzchar(jeton)) jeton <- NULL

  baslangic <- tryCatch(
    as.POSIXct(as.numeric(request$started_at_epoch %||% NA_real_), origin = "1970-01-01"),
    error = function(e) basladi
  )
  if (length(baslangic) != 1L || is.na(baslangic)) baslangic <- basladi

  son_tarih <- pk_deadline_at(baslangic, request$deadline_sec)

  # İşçi-YEREL kapanış. Boru hattı bunu her aşama sınırında ZATEN çağırıyor;
  # dolayısıyla iptal ve son tarih, mevcut aşama kontrolleri DEĞİŞTİRİLMEDEN
  # işçiye ULAŞIR. Reaktif bir kapanış olmadığı için serileştirme sorunu yoktur.
  stop_check <- function() {
    kapi <- pk_async_stage_gate(jeton, son_tarih)
    isTRUE(kapi$halt)
  }

  ilk_kapi <- pk_async_stage_gate(jeton, son_tarih)
  if (isTRUE(ilk_kapi$halt)) return(bitir(ilk_kapi$status))

  # --- 3) Oturum vekili ------------------------------------------------------
  vekil <- tryCatch(pk_async_worker_session(request), error = function(e) NULL)
  if (is.null(vekil)) return(bitir("error", error = "Oturum vekili kurulamadi."))

  # Motor kipi işçide de AYNI çözülmelidir; aksi hâlde ana süreç v2 seçerken
  # işçi v1 çalıştırabilir. Ortam değişkeni her iki süreçte de aynıdır, ancak
  # isteğin çözdüğü kip AÇIKÇA taşınır ve `options()` ile sabitlenir.
  motor <- as.character(request$engine %||% "")[1]
  if (motor %in% c("v1", "v2")) {
    eski_motor <- getOption("mergen.pk.engine", default = NULL)
    options(mergen.pk.engine = motor)
    on.exit(options(mergen.pk.engine = eski_motor), add = TRUE)
  }

  # --- 4) Boru hattını çalıştır ---------------------------------------------
  # Bağlantılar boru hattının KENDİ `on.exit`'i ile bırakılır ve o kod artık
  # İŞÇİDE çalışıyor; ek olarak buradaki tryCatch hiçbir hatanın işçiden dışarı
  # sızmasına izin vermez (sızan hata, geri çağrının reddedilmesine ve istek
  # yaşam döngüsünün yarı-temizlenmiş kalmasına yol açardı).
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

  # İptal/son tarih boru hattının içinde tetiklenmiş olabilir: `stop_check`
  # kullanıcıya görünen durdurma metnini döndürür. Durumu TİPLİ raporlamak,
  # "iptal", "zaman aşımı" ve "sıradan hata" ayrımının kaybolmamasını sağlar.
  son_kapi <- pk_async_stage_gate(jeton, son_tarih)
  if (isTRUE(son_kapi$halt)) return(bitir(son_kapi$status, session_writes = yazimlar))

  if (inherits(sonuc, "pk_async_pipeline_error")) {
    return(bitir("error", session_writes = yazimlar,
                 error = .pk_async_safe_error_text(sonuc$message)))
  }

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

  # Altyapı tanılaması gibi görünen metin genelleştirilir.
  altyapi <- c("nanodbc", "SQLSTATE", "DSN=", "ODBC", "Driver", "sp_executesql",
               "TCP Provider", "SQL Server")
  if (any(vapply(altyapi, function(p) grepl(p, ham, fixed = TRUE), logical(1)))) {
    return("Veritabani erisiminde teknik bir hata olustu.")
  }

  substr(ham, 1L, 400L)
}

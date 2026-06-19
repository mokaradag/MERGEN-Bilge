# ==============================================================================
# R/config_logging.R
# Loglama altyapısı: logger ayarları, hata yakalayıcı, debug çıktıları
# ve AI çağrılarını izleme fonksiyonları.
# global.R tarafından config_packages.R'den sonra source() ile çağrılır.
# ==============================================================================

# --- LOG DİZİNİ OLUŞTURMA ---
resolve_mergen_log_dir <- function(default = "logs") {
  log_dir <- trimws(Sys.getenv("MERGEN_LOG_DIR", default))
  if (!nzchar(log_dir)) {
    log_dir <- default
  }
  normalizePath(log_dir, winslash = "/", mustWork = FALSE)
}

resolve_mergen_log_threshold <- function(default = logger::INFO) {
  level <- tolower(trimws(Sys.getenv("MERGEN_LOG_THRESHOLD", "info")))

  switch(
    level,
    trace   = logger::TRACE,
    debug   = logger::DEBUG,
    info    = logger::INFO,
    warn    = logger::WARN,
    warning = logger::WARN,
    error   = logger::ERROR,
    fatal   = logger::FATAL,
    default
  )
}

# Log dizininin gerçekten YAZILABİLİR olduğunu doğrular. Birincil dizin
# (ör. UNC paylaşımı) yoksa oluşturmayı dener, sonra geçici bir sonda dosyasıyla
# yazma iznini test eder. Bu, "dizin var ama yazılamıyor" durumunu da yakalar.
mergen_log_dir_is_writable <- function(dir_path) {
  if (is.null(dir_path) || !nzchar(dir_path)) {
    return(FALSE)
  }
  if (!dir.exists(dir_path)) {
    tryCatch(
      dir.create(dir_path, recursive = TRUE, showWarnings = FALSE),
      error = function(e) FALSE
    )
  }
  if (!dir.exists(dir_path)) {
    return(FALSE)
  }
  probe <- file.path(dir_path, sprintf(".mergen_log_write_test_%s", Sys.getpid()))
  ok <- tryCatch({
    cat("", file = probe, append = TRUE)
    TRUE
  }, error = function(e) FALSE)
  if (file.exists(probe)) {
    unlink(probe)
  }
  isTRUE(ok)
}

mergen_log_dir <- resolve_mergen_log_dir()

# Birincil log dizinine yazılamıyorsa (ör. UNC paylaşımı erişilemez/izinsiz),
# uygulama loglarını SESSİZCE kaybetmek yerine repo kökündeki yerel "logs"
# dizinine düşülür ve durum konsola yüksek sesle bildirilir. Bu, Haziran
# regresyonundaki "konsol çalışıyor ama mergen_YYYYMMDD.log oluşmuyor"
# durumunun sessizce sürmesini engeller.
if (!mergen_log_dir_is_writable(mergen_log_dir)) {
  fallback_log_dir <- normalizePath(
    file.path(getwd(), "logs"),
    winslash = "/", mustWork = FALSE
  )
  message(sprintf(
    "[MERGEN LOGGING] Yapilandirilmis log dizinine yazilamiyor (%s). Yerel dizine dusuluyor: %s",
    mergen_log_dir, fallback_log_dir
  ))
  mergen_log_dir <- fallback_log_dir
}

if (!mergen_log_dir_is_writable(mergen_log_dir)) {
  stop(sprintf("Log dizini oluşturulamadı/yazılamıyor: %s", mergen_log_dir))
}

# --- LOGGER YAPILANDIRMASI ---
library(logger)
log_threshold(resolve_mergen_log_threshold())

# --- GÜNLÜK LOG DOSYASI ÇÖZÜMLEME (TARİH-DUYARLI) ---
# Tarih her log satırında yeniden çözülür. Bu, Haziran regresyonunun iki olası
# kök nedenini birden kapatır:
#   1) Her yeniden başlatma o günün mergen_YYYYMMDD.log dosyasını oluşturur.
#   2) Uzun süre açık kalan üretim süreci gece yarısını geçince otomatik olarak
#      yeni güne ait dosyaya yazmaya başlar; başlangıç tarihindeki eski dosyada
#      takılı kalmaz (son log 12.06 saat 23:51'de kalmıştı).
# Testler tarihi mergen.log.date_provider option'ı ile enjekte edebilir.
current_mergen_log_date <- function() {
  date_provider <- getOption("mergen.log.date_provider", NULL)
  current_date <- if (is.function(date_provider)) date_provider() else Sys.Date()
  if (inherits(current_date, "Date")) {
    return(current_date[1])
  }
  as.Date(current_date[1])
}

current_mergen_log_file_path <- function() {
  file.path(
    mergen_log_dir,
    sprintf("mergen_%s.log", format(current_mergen_log_date(), "%Y%m%d"))
  )
}

# Geriye dönük uyumluluk: bazı testler/çağıranlar log_file_path değişkenini okur.
log_file_path <- current_mergen_log_file_path()

# Hem konsola hem dosyaya log yaz.
# Bu appender, logger::appender_file ile AYNI yazım anlamını korur
# (cat(lines, sep = "\n", append = TRUE)); böylece dosya içeriği, kodlaması ve
# satır ayrımı eskisiyle bayt-bayt aynı kalır. Eklenen tek fark üç üretim
# güvenilirliği iyileştirmesidir:
#   1) Hedef dosya her satırda güncel tarihe göre yeniden çözülür (günlük devir).
#   2) Log dizini her yazımdan önce garanti edilir (UNC/ağ paylaşımı dayanıklılığı).
#   3) Yazma hatası SESSİZCE yutulmaz; konsola bildirilir; böylece bir paylaşım
#      hatası günlerce fark edilmeden log üretimini durduramaz.
# Not: cat() bir useBytes argümanı KABUL ETMEZ (o writeLines'a aittir); bu yüzden
# burada kullanılmaz. Konsol native-dönüşümü ayrı appender'da yapılır.
mergen_daily_file_appender <- function(lines) {
  if (!dir.exists(mergen_log_dir)) {
    dir.create(mergen_log_dir, recursive = TRUE, showWarnings = FALSE)
  }

  target_file <- current_mergen_log_file_path()
  tryCatch(
    cat(lines, sep = "\n", file = target_file, append = TRUE),
    error = function(e) {
      message(sprintf(
        "[MERGEN LOGGING ERROR] Gunluk log dosyasina yazilamadi (%s): %s",
        target_file, conditionMessage(e)
      ))
    }
  )
}

# Çoklu appender yapılandırması
# Dosya logu düz metin olmalı
log_appender(mergen_daily_file_appender, index = 1)
log_layout(layout_glue, index = 1)

# --- AÇILIŞTA GÜNLÜK DOSYAYI GARANTİLE (THRESHOLD-BAĞIMSIZ) ---
# Haziran regresyonunun çekirdek belirtisi: uygulama açılışında
# mergen_YYYYMMDD.log dosyası HİÇ oluşmuyordu (konsol logları çalışsa bile).
# Kök neden ne olursa olsun (yüksek MERGEN_LOG_THRESHOLD ilk INFO satırını
# filtreliyor; logger appender dağıtımı ilk çağrıda dosyaya ulaşmıyor; vb.),
# logger appender'ı dosyayı YALNIZCA eşiği geçen bir satır yazıldığında
# oluşturur. Bu yardımcı, her açılışta günün dosyasını DOĞRUDAN cat() ile
# (logger ve threshold'dan tamamen bağımsız) oluşturup açılış başlığını yazar;
# böylece dosyanın her gün, her yeniden başlatmada var olması garanti edilir.
# Yazım anlamı dosya appender'ı ile aynıdır (cat(..., append = TRUE)), dosya
# içeriği/kodlaması bayt-bayt uyumlu kalır.
mergen_ensure_daily_log_file <- function() {
  if (!dir.exists(mergen_log_dir)) {
    dir.create(mergen_log_dir, recursive = TRUE, showWarnings = FALSE)
  }
  target_file <- current_mergen_log_file_path()
  banner <- sprintf(
    "INFO [%s] === MERGEN Bilge gunluk log dosyasi hazir: %s ===",
    format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    target_file
  )
  tryCatch(
    cat(banner, sep = "\n", file = target_file, append = TRUE),
    error = function(e) {
      message(sprintf(
        "[MERGEN LOGGING ERROR] Acilis gunluk log dosyasi olusturulamadi (%s): %s",
        target_file, conditionMessage(e)
      ))
    }
  )
  invisible(target_file)
}

# Açılış dosyasını HEMEN oluştur (konsol appender'ı ve diğer kurulumdan önce
# yapılması gerekmez, ama açılışta dosyanın görünmesini garanti eder).
mergen_ensure_daily_log_file()

# Konsol renkleri üretimde varsayılan kapalıdır.
# Windows servis/VM koşullarında ANSI escape dizilerinin loglara karışmasını önler.
use_console_colors <- tolower(trimws(Sys.getenv("MERGEN_LOG_CONSOLE_COLORS", "false"))) %in%
  c("1", "true", "t", "yes", "y", "on")

# Windows PowerShell/R console bazen UTF-8 Türkçe karakterleri native geniş string'e
# çeviremeyip "unable to translate ... to a wide string" uyarısı üretir.
# Dosya logu UTF-8 kalır; yalnızca konsol çıktısı native-safe hale getirilir.
mergen_console_appender <- function(lines) {
  lines <- as.character(lines %||% "")
  if (exists("normalize_text_for_log", mode = "function", inherits = TRUE)) {
    lines <- normalize_text_for_log(lines)
  } else {
    lines <- enc2utf8(lines)
  }

  native_lines <- iconv(lines, from = "UTF-8", to = "", sub = "byte")
  native_lines[is.na(native_lines)] <- "<log encoding conversion failed>"

  cat(paste0(native_lines, collapse = "\n"), "\n", sep = "")
}

log_appender(mergen_console_appender, index = 2)

if (isTRUE(use_console_colors)) {
  log_layout(layout_glue_colors, index = 2)
} else {
  log_layout(layout_glue, index = 2)
}

# --- GÜVENLİ LOG SARICILARI ---
# Tüm uygulama logları bu sarmalayıcılardan geçer.
# ÖNEMLİ:
# - logger içindeki { ... } glue ifadeleri ÇAĞIRAN ortamda çözülmelidir.
# - Bu nedenle do.call(..., envir = caller_env) ile orijinal çağıran çerçeve korunur.
# - Önce msg ve ... içindeki doğrudan karakter veriler redakte edilir; sonra logger'a verilir.
.sanitize_log_value <- function(x) {
  if (is.null(x)) return(x)

  if (is.character(x) &&
      exists("normalize_text_for_log", mode = "function", inherits = TRUE)) {
    x <- normalize_text_for_log(x)
  }

  if (!exists("redact_sensitive_text", mode = "function", inherits = TRUE)) {
    return(x)
  }

  if (is.character(x)) {
    return(redact_sensitive_text(x))
  }

  x
}

.forward_log_call <- function(log_fun, msg, ..., .caller_env = parent.frame()) {
  clean_msg <- .sanitize_log_value(msg)
  clean_args <- lapply(list(...), .sanitize_log_value)

  do.call(
    what = log_fun,
    args = c(list(clean_msg), clean_args),
    envir = .caller_env
  )
}

log_info <- function(msg, ...) {
  .forward_log_call(logger::log_info, msg, ..., .caller_env = parent.frame())
}

log_warn <- function(msg, ...) {
  .forward_log_call(logger::log_warn, msg, ..., .caller_env = parent.frame())
}

log_error <- function(msg, ...) {
  .forward_log_call(logger::log_error, msg, ..., .caller_env = parent.frame())
}

log_debug <- function(msg, ...) {
  .forward_log_call(logger::log_debug, msg, ..., .caller_env = parent.frame())
}

log_info("Application starting up...")
# Çözülen log dosyası yolunu açıkça yaz: hem konsolda hem dosyada görünür, böylece
# logların hangi dizine yazıldığı (UNC/yerel) hiçbir zaman belirsiz kalmaz.
log_info("Gunluk log dosyasi (mergen_YYYYMMDD.log): {log_file_path}")

# --- GLOBAL HATA YAKALAYICI ---
# Süreç başına bir kez tanımlanır; argümansız çağrıları da tolere eder
shiny_error_handler <- function(e = NULL) {
  msg <- if (!is.null(e)) {
    if (inherits(e, "error")) conditionMessage(e) else as.character(e)
  } else {
    geterrmessage()
  }
  
  # Log dosyasına yaz
  log_error("[ERROR] {msg}")

  # Yapılandırılmış, sır-redakteli kayıt: yakalanmamış Shiny hataları olay
  # incelemesinde [RUNTIME_ERROR] satırı olarak aranabilir. Yardımcı yoksa veya
  # üretim başarısız olursa sessizce atlanır; bu global handler asla kırılmamalı.
  if (exists("mergen_build_runtime_error_record", mode = "function")) {
    structured_err <- tryCatch({
      rec <- mergen_build_runtime_error_record(
        if (!is.null(e)) e else msg,
        "shiny_uncaught"
      )
      as.character(jsonlite::toJSON(rec, auto_unbox = TRUE, null = "null"))
    }, error = function(err) NULL)

    if (!is.null(structured_err)) {
      log_error("[RUNTIME_ERROR] {structured_err}")
    }
  }
  
  # Debug modunda stack trace göster
  if (isTRUE(as.logical(Sys.getenv("MERGEN_DEBUG", "FALSE")))) {
    stack <- sys.calls()
    if (length(stack) > 0) {
      stack_str <- paste(sapply(stack, function(x) paste(deparse(x), collapse = " ")), collapse = " -> ")
      log_debug("[TRACE] {stack_str}")
    }
  }
}

options(shiny.error = shiny_error_handler)

# --- DEBUG DUMPER (logs/ai_debug_YYYYMMDD.log) ---
# Geriye dönük uyumluluk için değişken tanımlı kalır; gerçek yazım hedefi her
# çağrıda güncel tarihe göre yeniden çözülür (mergen log'u ile aynı günlük devir).
dbg_log_path <- file.path(
  mergen_log_dir,
  sprintf("ai_debug_%s.log", format(current_mergen_log_date(), "%Y%m%d"))
)

dbg_dump <- function(label, payload) {
  try({
    payload_json <- jsonlite::toJSON(
      payload,
      auto_unbox = TRUE,
      null = "null",
      pretty = TRUE
    )
    payload_json <- .sanitize_log_value(payload_json)
    label <- .sanitize_log_value(as.character(label))

    cat(
      sprintf("[%s] %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), label),
      payload_json,
      "\n---\n",
      file = file.path(
        mergen_log_dir,
        sprintf("ai_debug_%s.log", format(current_mergen_log_date(), "%Y%m%d"))
      ),
      append = TRUE
    )
  }, silent = TRUE)
}

# --- AI ÇAĞRI LOGLAMA ---
log_ai_call <- function(user_id, model, duration, success, tokens = NA) {
  log_info("AI Call: user={user_id}, model={model}, duration={duration}s, success={success}, tokens={tokens}")
}

# --- BAĞLAMLI HATA LOGLAMA ---
log_error_with_context <- function(error, context = "unknown") {
  # Yapılandırılmış ve sır-redakteli kayıt üret (yardımcı yoksa NULL döner).
  record <- tryCatch(
    mergen_build_runtime_error_record(error, context),
    error = function(e) NULL
  )

  if (!is.null(record)) {
    # Redakte edilmiş bağlam/mesaj ile insan-okur log satırı.
    ctx <- record$context
    msg <- record$message
    log_error("Error in {ctx}: {msg}")

    # İzlenebilir tek satır yapılandırılmış kayıt; olay incelemesinde aranır.
    structured <- tryCatch(
      jsonlite::toJSON(record, auto_unbox = TRUE, null = "null"),
      error = function(e) NULL
    )
    if (!is.null(structured)) {
      structured_line <- as.character(structured)
      log_debug("[RUNTIME_ERROR] {structured_line}")
    }
  } else {
    # Geriye dönük güvenli yol: yardımcı kullanılamıyorsa eski davranışı koru,
    # ancak yine de mümkünse mesajı redakte et.
    error_msg <- if (inherits(error, "error")) error$message else as.character(error)
    if (exists("redact_sensitive_text", mode = "function")) {
      error_msg <- tryCatch(
        as.character(redact_sensitive_text(error_msg))[1],
        error = function(e) error_msg
      )
    }
    log_error("Error in {context}: {error_msg}")
  }

  # Stack trace al
  stack <- sys.calls()
  if (length(stack) > 0) {
    stack_str <- paste(sapply(stack, function(x) paste(deparse(x), collapse = " ")), collapse = " -> ")
    log_debug("Stack trace: {stack_str}")
  }
}

# --- KULLANICI AKSİYON LOGLAMA ---
log_user_action <- function(user_id, action, details = "") {
  log_info("User action: user={user_id}, action={action}, details={details}")
}
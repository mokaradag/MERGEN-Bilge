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

mergen_log_dir <- resolve_mergen_log_dir()

if (!dir.exists(mergen_log_dir)) {
  dir.create(mergen_log_dir, recursive = TRUE, showWarnings = FALSE)
}

if (!dir.exists(mergen_log_dir)) {
  stop(sprintf("Log dizini oluşturulamadı: %s", mergen_log_dir))
}

# --- LOGGER YAPILANDIRMASI ---
library(logger)
log_threshold(resolve_mergen_log_threshold())

# Hem konsola hem dosyaya log yaz
log_file_path <- file.path(
  mergen_log_dir,
  sprintf("mergen_%s.log", format(Sys.Date(), "%Y%m%d"))
)

# Çoklu appender yapılandırması
# Dosya logu düz metin olmalı
log_appender(appender_file(log_file_path), index = 1)
log_layout(layout_glue, index = 1)

# Konsol renkleri üretimde varsayılan kapalıdır.
# Windows servis/VM koşullarında ANSI escape dizilerinin loglara karışmasını önler.
use_console_colors <- tolower(trimws(Sys.getenv("MERGEN_LOG_CONSOLE_COLORS", "false"))) %in%
  c("1", "true", "t", "yes", "y", "on")

log_appender(appender_console, index = 2)

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
dbg_log_path <- file.path(
  mergen_log_dir,
  sprintf("ai_debug_%s.log", format(Sys.Date(), "%Y%m%d"))
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
      file = dbg_log_path, append = TRUE
    )
  }, silent = TRUE)
}

# --- AI ÇAĞRI LOGLAMA ---
log_ai_call <- function(user_id, model, duration, success, tokens = NA) {
  log_info("AI Call: user={user_id}, model={model}, duration={duration}s, success={success}, tokens={tokens}")
}

# --- BAĞLAMLI HATA LOGLAMA ---
log_error_with_context <- function(error, context = "unknown") {
  error_msg <- if (inherits(error, "error")) error$message else as.character(error)
  log_error("Error in {context}: {error_msg}")
  
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
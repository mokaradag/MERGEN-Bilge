# ==============================================================================
# R/config_logging.R
# Loglama altyapısı: logger ayarları, hata yakalayıcı, debug çıktıları
# ve AI çağrılarını izleme fonksiyonları.
# global.R tarafından config_packages.R'den sonra source() ile çağrılır.
# ==============================================================================

# --- LOG DİZİNİ OLUŞTURMA ---
if (!dir.exists("logs")) {
  dir.create("logs", recursive = TRUE)
}

# --- LOGGER YAPILANDIRMASI ---
library(logger)
log_threshold(INFO)

# Hem konsola hem dosyaya log yaz
log_file_path <- file.path("logs", sprintf("mergen_%s.log", format(Sys.Date(), "%Y%m%d")))

# Çoklu appender yapılandırması
log_appender(appender_file(log_file_path), index = 1)
log_appender(appender_console, index = 2)

log_layout(layout_glue_colors)
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
dbg_log_path <- file.path("logs", sprintf("ai_debug_%s.log", format(Sys.Date(), "%Y%m%d")))
dbg_dump <- function(label, payload) {
  try({
    cat(
      sprintf("[%s] %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), label),
      jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null", pretty = TRUE),
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
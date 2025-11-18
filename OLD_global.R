# global.R

# Force UTF-8 encoding globally
options(encoding = "UTF-8")
try(suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8")), silent = TRUE)

# Limit suppression to only this locale call
try(suppressWarnings(Sys.setlocale("LC_CTYPE", "Turkish_Turkey.UTF-8")), silent = TRUE)

# --- LOGGING SETUP ---
# Create logs directory if it doesn't exist
if (!dir.exists("logs")) {
  dir.create("logs", recursive = TRUE)
}

library(logger)
log_threshold(INFO)

# Set up logging to both console and file
log_file_path <- file.path("logs", sprintf("mergen_%s.log", format(Sys.Date(), "%Y%m%d")))

# Configure multiple appenders manually
log_appender(appender_file(log_file_path), index = 1)
log_appender(appender_console, index = 2)

log_layout(layout_glue_colors)
log_info("Application starting up...")

# Global error handler (once per process) — tolerate calls without an argument
shiny_error_handler <- function(e = NULL) {
  msg <- if (!is.null(e)) {
    if (inherits(e, "error")) conditionMessage(e) else as.character(e)
  } else {
    geterrmessage()
  }
  cat("[ERROR]", msg, "\n")
  stack <- sys.calls()
  if (length(stack) > 0) {
    stack_str <- paste(sapply(stack, function(x) paste(deparse(x), collapse = " ")), collapse = " -> ")
    cat("[TRACE]", stack_str, "\n")
  }
}
options(shiny.error = shiny_error_handler)

# --- DEBUG DUMPER (adds logs/ai_debug_YYYYMMDD.log) ---
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

# --- LIBRARY IMPORTS ---
library(shiny)
library(shinydashboard)
library(shinyWidgets)
library(DT)
library(htmltools)
library(jsonlite)
library(lubridate)
library(stringr)
library(shinycssloaders)
library(shinyjs)
library(httr)
library(curl)
library(shinyBS)
library(writexl)
library(readxl)
library(base64enc)
library(markdown)
library(xml2)
library(promises)
library(future)
library(data.table)
library(commonmark)
library(DBI)
library(odbc)
library(pool)
library(urltools)
library(later)
library(pdftools)
library(cellranger)
library(openssl)

# Ortamda AES-GCM var mı? Eski openssl sürümlerinde bu fonksiyon yoktur.
HAVE_AES_GCM <- isTRUE("aes_gcm_encrypt" %in% getNamespaceExports("openssl"))

# --- OPTIONAL VIS LIBS (do-not-fail if missing) ---
have_highcharter <- requireNamespace("highcharter", quietly = TRUE)
have_plotly_gg   <- (requireNamespace("plotly", quietly = TRUE) && requireNamespace("ggplot2", quietly = TRUE))

# ===== Shared file store (same for main + workers) =====
MERGEN_FILES_ROOT <- tools::R_user_dir("mergen", which = "data")
dir.create(MERGEN_FILES_ROOT, showWarnings = FALSE, recursive = TRUE)

# Always-persisted uploads base: ./mergen_uploads  (override with MCP_FILES_BASE if set)
MERGEN_UPLOADS_DIR <- normalizePath(file.path(getwd(), "mergen_uploads"),
                                    winslash = "/", mustWork = FALSE)
dir.create(MERGEN_UPLOADS_DIR, showWarnings = FALSE, recursive = TRUE)

# Base dir for persisted uploads (defaults to mergen_uploads/, can be overridden by MCP_FILES_BASE)
MERGEN_MCP_BASE_DIR <- Sys.getenv("MCP_FILES_BASE", MERGEN_UPLOADS_DIR)
MERGEN_MCP_BASE_DIR <- normalizePath(MERGEN_MCP_BASE_DIR, winslash = "/", mustWork = FALSE)
dir.create(MERGEN_MCP_BASE_DIR, showWarnings = FALSE, recursive = TRUE)

# Registry lives under app data; now supports per-user buckets
MERGEN_INDEX_PATH <- file.path(MERGEN_FILES_ROOT, "index.json")

# tiny helpers used by both main and workers
.save_index <- function(idx) jsonlite::write_json(idx, MERGEN_INDEX_PATH, auto_unbox = TRUE, pretty = TRUE)
.load_index <- function() if (file.exists(MERGEN_INDEX_PATH)) jsonlite::read_json(MERGEN_INDEX_PATH, simplifyVector = TRUE) else list()

# Register a file (copy to persistent store + index under user bucket)
mergen_register_uploaded_file <- function(src_path,
                                          as_name = basename(src_path),
                                          user_id = NULL,
                                          persist_under_mcp_base = TRUE) {
  base_dir <- if (isTRUE(persist_under_mcp_base)) MERGEN_MCP_BASE_DIR else MERGEN_FILES_ROOT
  user_folder <- if (!is.null(user_id)) file.path(base_dir, paste0("user_", as.character(user_id))) else base_dir
  dir.create(user_folder, showWarnings = FALSE, recursive = TRUE)

  src_norm  <- normalizePath(src_path, winslash = "/", mustWork = FALSE)
  base_norm <- normalizePath(base_dir, winslash = "/", mustWork = FALSE)

  # If the source already lives under the chosen base, don't copy — just index it
  if (startsWith(tolower(src_norm), tolower(paste0(base_norm, "/")))) {
    dest_norm <- src_norm
  } else {
    unique_name <- paste0(format(Sys.time(), "%Y%m%d%H%M%S"), "_", sprintf("%04d", sample(0:9999, 1)), "_", basename(as_name))
    dest <- file.path(user_folder, unique_name)
    ok <- file.copy(src_path, dest, overwrite = TRUE)
    if (!ok) stop("Dosya kopyalanamadı: ", src_path)
    dest_norm <- normalizePath(dest, winslash = "/", mustWork = TRUE)
  }

  idx <- .load_index()
  key <- tolower(basename(as_name))

  # store both the real path and the original display name (BACKWARD-COMPATIBLE)
  entry <- list(path = dest_norm, display = basename(as_name))
  if (!is.null(user_id)) {
    uid <- as.character(user_id)
    if (is.null(idx[[uid]])) idx[[uid]] <- list()
    idx[[uid]][[key]] <- entry
  } else {
    idx[[key]] <- entry
  }

  .save_index(idx)
  dest_norm
}

# Alias with flexible options; used by server to persist MCP files
global_register_file <- function(src_path,
                                 filename,
                                 user_id = NULL,
                                 persist_under_mcp_base = TRUE) {
  mergen_register_uploaded_file(
    src_path,
    as_name = filename,
    user_id = user_id,
    persist_under_mcp_base = persist_under_mcp_base
  )
}

# Resolve a file name (or path) to an absolute path that exists (prefers per-user)
resolve_uploaded_file <- function(requested, user_id = NULL) {
  # Günlük: gelen parametreleri yaz
  log_debug("resolve_uploaded_file(): requested='{requested}', user_id='{user_id}'")
  if (is.null(requested) || !(is.character(requested) && length(requested) > 0 && nzchar(requested[1]))) return(NULL)

  if (file.exists(requested[1])) {
    p <- normalizePath(requested[1], winslash = "/", mustWork = TRUE)
    log_info("resolve_uploaded_file(): doğrudan mevcut dosya bulundu -> {p}")
    return(p)
  }

  # Not: önce TAM adla (display) ara, sonra basename'e düş
  full_key <- tolower(as.character(requested))
  key      <- tolower(basename(requested))
  idx <- .load_index()
  log_debug("resolve_uploaded_file(): full='{full_key}', anahtar='{key}', index kovası sayısı={length(idx)}")

  # 1) Kullanıcı kovası
  if (!is.null(user_id)) {
    uid <- as.character(user_id)
    if (!is.null(idx[[uid]])) {
      bucket <- idx[[uid]]

      # Önce display eşleşmesi (tam ad)
      if (is.list(bucket) && length(bucket)) {
        for (nm in names(bucket)) {
          ent <- bucket[[nm]]
          ent_path <- if (is.list(ent) && !is.null(ent$path)) ent$path else as.character(ent)
          ent_disp <- if (is.list(ent) && !is.null(ent$display)) tolower(as.character(ent$display)) else tolower(nm)
          if (!is.null(ent_path) && file.exists(ent_path) && identical(ent_disp, full_key)) {
            p <- normalizePath(ent_path, winslash = "/", mustWork = FALSE)
            log_info("resolve_uploaded_file(): kullanıcı kovasında TAM adla bulundu -> {p}")
            return(p)
          }
        }
      }

      # Sonra basename anahtarı
      hit <- bucket[[key]]
      if (is.list(hit) && !is.null(hit$path)) hit <- hit$path  # yeni yapı
      if (!is.null(hit) && file.exists(hit)) {
        p <- normalizePath(hit, winslash = "/", mustWork = FALSE)
        log_info("resolve_uploaded_file(): kullanıcı kovasında basename ile bulundu -> {p}")
        return(p)
      } else {
        log_debug("resolve_uploaded_file(): kullanıcı kovasında eşleşme yok (display/basename)")
      }
    } else {
      log_debug("resolve_uploaded_file(): kullanıcı kovası yok: user_id='{uid}'")
    }
  }

  # 2) Legacy düz harita: önce display'e göre tara, sonra basename
  # (Not: düz haritada display tuttuğumuz yeni kayıtlar olabilir)
  if (length(idx)) {
    # Display'e göre tam ad araması
    for (bucket_name in names(idx)) {
      bucket <- idx[[bucket_name]]
      if (is.list(bucket)) {
        for (nm in names(bucket)) {
          ent <- bucket[[nm]]
          ent_path <- if (is.list(ent) && !is.null(ent$path)) ent$path else as.character(ent)
          ent_disp <- if (is.list(ent) && !is.null(ent$display)) tolower(as.character(ent$display)) else tolower(nm)
          if (!is.null(ent_path) && file.exists(ent_path) && identical(ent_disp, full_key)) {
            p <- normalizePath(ent_path, winslash = "/", mustWork = FALSE)
            log_info("resolve_uploaded_file(): display ile kovalar arasında bulundu (bucket='{bucket_name}') -> {p}")
            return(p)
          }
        }
      }
    }
  }

  # 3) Basename ile klasik aramalar (düz + çapraz)
  hit <- idx[[key]]
  if (is.list(hit) && !is.null(hit$path)) hit <- hit$path
  if (!is.null(hit) && file.exists(hit)) {
    p <- normalizePath(hit, winslash = "/", mustWork = FALSE)
    log_info("resolve_uploaded_file(): legacy haritada (basename) bulundu -> {p}")
    return(p)
  }

  if (length(idx)) {
    for (bucket_name in names(idx)) {
      bucket <- idx[[bucket_name]]
      if (is.list(bucket)) {
        hit <- bucket[[key]]
        if (is.list(hit) && !is.null(hit$path)) hit <- hit$path
        if (!is.null(hit) && file.exists(hit)) {
          p <- normalizePath(hit, winslash = "/", mustWork = FALSE)
          log_info("resolve_uploaded_file(): çapraz kovada (basename) bulundu (bucket='{bucket_name}') -> {p}")
          return(p)
        }
      }
    }
  }

  log_warn("resolve_uploaded_file(): '{requested}' için eşleşme bulunamadı")
  NULL
}

# ---- USER UPLOADS HELPERS (persistence) ----
mergen_user_upload_dir <- function(user_id) {
  base <- getOption("mergen.mcp_base_dir", MERGEN_MCP_BASE_DIR)
  p <- file.path(base, sprintf("user_%s", as.character(user_id)))
  dir.create(p, showWarnings = FALSE, recursive = TRUE)
  normalizePath(p, winslash = "/", mustWork = FALSE)
}

mergen_list_user_files <- function(user_id) {
  idx <- .load_index()
  uid <- as.character(user_id)
  bucket <- idx[[uid]]

  if (!is.null(bucket) && length(bucket) > 0) {
    # Support both legacy string values and new list entries {path, display}
    paths <- vapply(bucket, function(v) {
      if (is.list(v) && !is.null(v$path)) v$path else as.character(v)
    }, character(1))
    names_disp <- vapply(names(bucket), function(k) {
      v <- bucket[[k]]
      if (is.list(v) && !is.null(v$display) && nzchar(v$display)) v$display else k
    }, character(1))

    return(data.frame(
      path = normalizePath(unname(paths), winslash = "/", mustWork = FALSE),
      name = unname(names_disp),
      stringsAsFactors = FALSE
    ))
  }

  # Fallback: plain folder listing (pre-index or very old data)
  dir <- mergen_user_upload_dir(user_id)
  if (!dir.exists(dir)) return(data.frame(path = character(), name = character(), stringsAsFactors = FALSE))
  paths <- list.files(dir, full.names = TRUE, recursive = FALSE, include.dirs = FALSE)
  data.frame(
    path = normalizePath(paths, winslash = "/", mustWork = FALSE),
    name = basename(paths),
    stringsAsFactors = FALSE
  )
}

mergen_remove_from_index <- function(user_id, filename) {
  idx <- .load_index()
  uid <- as.character(user_id)
  key <- tolower(basename(filename))
  if (!is.null(idx[[uid]])) {
    idx[[uid]][[key]] <- NULL
    .save_index(idx)
  }
}

mergen_clear_user_bucket <- function(user_id) {
  dir <- mergen_user_upload_dir(user_id)
  if (dir.exists(dir)) {
    files <- list.files(dir, full.names = TRUE, recursive = FALSE, include.dirs = FALSE)
    for (f in files) try(unlink(f, force = TRUE), silent = TRUE)
  }
  # wipe the user's index bucket
  idx <- .load_index()
  uid <- as.character(user_id)
  if (!is.null(idx[[uid]])) {
    idx[[uid]] <- NULL
    .save_index(idx)
  }
}

# Make these available to helper modules, too
options(mergen.files_root = MERGEN_FILES_ROOT,
        mergen.index_path = MERGEN_INDEX_PATH,
        mergen.mcp_base_dir = MERGEN_MCP_BASE_DIR)

# Memory management settings
options(
  shiny.maxRequestSize = 30*1024^2,  # 30MB max upload
  future.globals.maxSize = 200*1024^2  # 200MB for future operations
)

# Garbage collection scheduler
gc_scheduler <- function() {
  gc(verbose = FALSE)
  later::later(gc_scheduler, delay = 300)  # Run every 5 minutes
}
gc_scheduler()

pool <- NULL

# --- VALIDATE REQUIRED ENVIRONMENT VARIABLES ---
required_env_vars <- c("LOCAL_LLM_ENDPOINT", "DB_DSN", "AI_KEYS_MASTER")
missing_vars <- required_env_vars[sapply(required_env_vars, function(v) !nzchar(Sys.getenv(v)))]

if (length(missing_vars) > 0) {
  stop(sprintf(
    "Missing required environment variables: %s\n\nPlease configure them in .Renviron file:\n%s",
    paste(missing_vars, collapse = ", "),
    paste(sprintf("%s=your_value_here", missing_vars), collapse = "\n")
  ))
}

message("✓ All required environment variables are configured")

# --- ENHANCED LOGGING FRAMEWORK ---
log_ai_call <- function(user_id, model, duration, success, tokens = NA) {
  log_info("AI Call: user={user_id}, model={model}, duration={duration}s, success={success}, tokens={tokens}")
}

log_error_with_context <- function(error, context = "unknown") {
  error_msg <- if (inherits(error, "error")) error$message else as.character(error)
  log_error("Error in {context}: {error_msg}")
  
  # Get stack trace
  stack <- sys.calls()
  if (length(stack) > 0) {
    stack_str <- paste(sapply(stack, function(x) paste(deparse(x), collapse=" ")), collapse=" -> ")
    log_debug("Stack trace: {stack_str}")
  }
}

log_user_action <- function(user_id, action, details = "") {
  log_info("User action: user={user_id}, action={action}, details={details}")
}

rate_limiter <- list(
  max_requests_per_user = 10,  # Max requests per minute per user
  window_size = 60,             # Time window in seconds
  requests = new.env()          # Store request timestamps
)

# Global rate limiter (across all users)
global_rate_limiter <- list(
  max_total_requests = 100,  # Total requests per minute across all users
  window_size = 60,
  requests = list()
)

check_global_rate_limit <- function() {
  current_time <- Sys.time()
  
  # Clean old requests
  global_rate_limiter$requests <<- Filter(function(t) {
    difftime(current_time, t, units = "secs") < global_rate_limiter$window_size
  }, global_rate_limiter$requests)
  
  # Check if global limit exceeded
  if (length(global_rate_limiter$requests) >= global_rate_limiter$max_total_requests) {
    return(list(allowed = FALSE, message = "Sistem yoğunluğu nedeniyle geçici olarak hizmet verilemiyor. Lütfen birkaç saniye sonra tekrar deneyin."))
  }
  
  # Add current request
  global_rate_limiter$requests <<- c(global_rate_limiter$requests, list(current_time))
  
  return(list(allowed = TRUE, message = NULL))
}

check_rate_limit <- function(user_id) {
  current_time <- Sys.time()
  user_key <- as.character(user_id)
  
  if (!exists(user_key, envir = rate_limiter$requests)) {
    rate_limiter$requests[[user_key]] <- list()
  }
  
  # Clean old requests
  rate_limiter$requests[[user_key]] <- Filter(function(t) {
    difftime(current_time, t, units = "secs") < rate_limiter$window_size
  }, rate_limiter$requests[[user_key]])
  
  # Check if limit exceeded
  if (length(rate_limiter$requests[[user_key]]) >= rate_limiter$max_requests_per_user) {
    return(FALSE)
  }
  
  # Add current request
  rate_limiter$requests[[user_key]] <- c(
    rate_limiter$requests[[user_key]], 
    list(current_time)
  )
  
  return(TRUE)
}

# Configure worker pool based on system capabilities (never less than 1)
n_workers <- max(1, min(parallelly::availableCores() - 1, 10))  # Leave one core free
plan(multisession, workers = n_workers)

# Add worker pool monitoring
monitor_workers <- function() {
  list(
    n_workers = nbrOfWorkers(),
    free_workers = nbrOfFreeWorkers(),
    total_workers = nbrOfWorkers()
  )
}

# --- ROBUST EXCEL TABLE READER (auto-detects top-left of the real table) ---
safe_read_excel_table <- function(path, sheet = 1, n_max = Inf, min_header_cols = 2) {
  if (!file.exists(path)) stop(sprintf("Dosya bulunamadı: %s", path))
  ext <- tolower(tools::file_ext(path))
  if (!ext %in% c("xlsx", "xls", "xlsm")) {
    stop(sprintf("Excel uzantısı bekleniyor (.xlsx/.xls/.xlsm), bulundu: .%s", ext))
  }

  # 1) Read the sheet without assuming headers; keep everything
  raw <- tryCatch(
    readxl::read_excel(path, sheet = sheet, col_names = FALSE, .name_repair = "minimal"),
    error = function(e) stop(sprintf("readxl::read_excel hatası: %s", e$message))
  )
  if (nrow(raw) == 0 || ncol(raw) == 0) return(data.frame())

  # 2) Non-empty mask
  non_empty <- as.data.frame(lapply(raw, function(x) !(is.na(x) | (is.character(x) & trimws(x) == ""))))
  row_score <- rowSums(data.matrix(non_empty), na.rm = TRUE)

  # 3) Heuristic: first row that looks like a header (>= min_header_cols non-empty)
  # and (ideally) followed by another non-sparse row
  header_row <- NA_integer_
  for (r in seq_len(nrow(raw))) {
    if (row_score[r] >= min_header_cols) {
      if (r < nrow(raw) && row_score[r + 1] >= min_header_cols) { header_row <- r; break }
      if (is.na(header_row)) header_row <- r
    }
  }
  if (is.na(header_row)) header_row <- 1L

  # 4) Determine column bounds around the header area
  lookahead_rows <- seq(header_row, min(header_row + 10, nrow(raw)))
  col_score <- colSums(data.matrix(non_empty[lookahead_rows, , drop = FALSE]), na.rm = TRUE)
  if (all(col_score == 0)) return(data.frame())
  col_min <- which(col_score > 0)[1]
  col_max <- tail(which(col_score > 0), 1)

  # 5) Determine bottom row across these columns (end of the block)
  in_block <- rowSums(data.matrix(non_empty[, col_min:col_max, drop = FALSE]), na.rm = TRUE)
  row_max <- tail(which(in_block > 0), 1)
  if (is.na(row_max)) row_max <- nrow(raw)

  rng <- cellranger::cell_limits(ul = c(header_row, col_min), lr = c(row_max, col_max))

  # 6) Final read: treat header row as column names
  df <- readxl::read_excel(
    path,
    sheet = sheet,
    range = rng,
    col_names = TRUE,
    n_max = if (is.finite(n_max)) n_max else NULL
  )

  # Ensure safe, unique names (avoid NA/"")
  if (anyNA(names(df)) || any(names(df) == "")) {
    names(df) <- paste0("X", seq_along(df))
  }
  names(df) <- make.names(names(df), unique = TRUE, allow_ = TRUE)

  # (Opsiyonel politika): A1 dışı başlangıç için bilgilendirici mesaj
  if (header_row != 1L) {
    message(sprintf("BİLGİ: Tablo A1 hücresinden başlamıyor; başlangıç konumu satır %d, sütun %d.", header_row, col_min))
  }

  as.data.frame(df, stringsAsFactors = FALSE)
}

# --- SOURCE MODULES AND HELPERS ---
# Using standard relative paths is the most robust and conventional method for Shiny apps.
source("welcome_screen.R",     encoding = "UTF-8")
source("R/helpers_database.R", encoding ="UTF-8")
source("R/helpers_language.R", encoding ="UTF-8")
source("R/helpers_messaging.R", encoding ="UTF-8")
source("R/helpers_mcp_tools.R", encoding ="UTF-8")
source("R/helpers_chartlab.R",    encoding = "UTF-8")
source("R/helpers_preview.R",     encoding = "UTF-8")
source("R/helpers_file_pipeline.R", encoding = "UTF-8")
source("R/helpers_files.R",     encoding = "UTF-8")
source("R/helpers_chat_runtime.R", encoding = "UTF-8")
source("R/module_chat_history.R", encoding ="UTF-8")
source("R/module_file_manager.R", encoding ="UTF-8")
source("R/module_saved_chats.R", encoding ="UTF-8")
source("R/module_settings.R", encoding ="UTF-8")
source("R/module_performance.R", encoding ="UTF-8")
source("R/module_ai_processing.R", encoding ="UTF-8")
source("R/module_session_timeout.R", encoding = "UTF-8")
source("R/module_file_preview.R", encoding = "UTF-8")
source("R/module_api_key.R", encoding = "UTF-8")
source("R/module_message_search.R", encoding = "UTF-8")
source("R/module_chat_actions.R",  encoding = "UTF-8")
source("R/module_chat_export.R",   encoding = "UTF-8")

# --- GLOBAL CONFIGURATION ---

# Word preview mode: "html" (client-side via mammoth.js) or "pdf" (server-side convert via LibreOffice)
options(mergen.word_preview_mode = "html")

api_config <- list(
  local_llm_endpoint = Sys.getenv("LOCAL_LLM_ENDPOINT", ""),
  # Dropdown labels  -> technical ids (unchanged)
  local_models = c(
    "Dropdown display model 1" = "technical name 1",
    "Dropdown display model 2" = "technical name 2",
    "Dropdown display model 3" = "technical name 3",
    "Dropdown display model 4" = "technical name 4"
  ),
  # NEW: technical ids -> base folders (use ONLY the technical ids here)
  local_model_paths = list(
    "technical name 1" = "\\\\main folder\\secondary folder\\repository\\top folder",
    "technical name 2" = "\\\\main folder\\secondary folder\\repository\\top folder2"
    # "technical name 3" = "",
    # "technical name 4" = ""
  )
)

# Başlangıçta indeksleri hazırla (ilk tıklama gecikmesini azaltır)
try({
  bases <- unique(unname(api_config$local_model_paths %||% character()))
  invisible(lapply(bases, function(p) .build_basename_index(p)))
}, silent = TRUE)

# --- SERVICE DESK LINKS (configure via .Renviron) ---
SERVICE_DESK <- list(
  api_key_request_url = Sys.getenv("SERVICE_DESK_API_KEY_URL", "https://servicedesk.example.com/api-key"),
  rate_limit_url      = Sys.getenv("SERVICE_DESK_RATE_LIMIT_URL", "https://servicedesk.example.com/rate-limit")
)                    

# Static user configuration (remains the same)
user_config <- list(
  name = "Ahmet Yılmaz", 
  icon = "user-circle",
  userId = "12345" 
)

# --- GLOBAL HELPER FUNCTIONS ---

# --- PER-USER AI API KEY MANAGEMENT -----------------------------------------
API_KEYS_DIR <- normalizePath(file.path(getwd(), "api_keys"), winslash = "/", mustWork = FALSE)
dir.create(API_KEYS_DIR, showWarnings = FALSE, recursive = TRUE)

.api_user_file <- function(system_username) {
  file.path(API_KEYS_DIR, sprintf("%s_api_key", system_username))
}

# Create salted hash (hex) using SHA256(salt || key)
.hash_key_hex <- function(key_plain, salt_raw) {
  stopifnot(is.character(key_plain), length(key_plain) == 1)
  openssl::sha256(paste0(rawToChar(salt_raw), key_plain)) |>
    as.character() # hex string
}

# AES-256-GCM (kimlik doğrulamalı) şifreleme / çözme
# Geriye dönük uyumluluk: eski CBC kayıtlarını da okuyabilir (enc_obj$tag_b64 yoksa CBC dener).
.enc_key <- function(plain_text, master) {
  stopifnot(is.character(plain_text), length(plain_text) == 1)

  # Derive 32-byte key
  k <- openssl::sha256(charToRaw(master))

  # Prefer GCM if available AND it returns the expected list shape
  use_gcm <- isTRUE(exists("aes_gcm_encrypt", where = asNamespace("openssl"), inherits = FALSE))
  if (use_gcm) {
    iv12 <- openssl::rand_bytes(12L)
    gcm  <- openssl::aes_gcm_encrypt(
      data = charToRaw(plain_text),
      key  = k,
      iv   = iv12
      # aad = NULL
    )

    # Some openssl builds return a list(list(data=raw, tag=raw)), others may not.
    if (is.list(gcm) && !is.null(gcm$data) && is.raw(gcm$data) && !is.null(gcm$tag) && is.raw(gcm$tag)) {
      return(list(
        alg        = "aes-256-gcm",
        iv_b64     = base64enc::base64encode(iv12),
        cipher_b64 = base64enc::base64encode(gcm$data),
        tag_b64    = base64enc::base64encode(gcm$tag)
      ))
    }
    # If we got here, GCM exists but didn't return the expected structure → fall back to CBC
  }

  # Fallback: AES-256-CBC (always available)
  iv16 <- openssl::rand_bytes(16L)
  ct   <- openssl::aes_cbc_encrypt(charToRaw(plain_text), key = k, iv = iv16)
  list(
    alg        = "aes-256-cbc",
    iv_b64     = base64enc::base64encode(iv16),
    cipher_b64 = base64enc::base64encode(ct)
    # no tag_b64 in CBC
  )
}

.dec_key <- function(enc_obj, master) {

	# Basit doğrulama: zorunlu alanlar
	if (is.null(enc_obj$iv_b64) || is.null(enc_obj$cipher_b64)) {
	  stop("Kayıt bozuk: iv/cipher alanı yok.")
	}

  k <- openssl::sha256(charToRaw(master))

  # — Önce GCM varsay: tag varsa GCM çöz
  if (!is.null(enc_obj$tag_b64)) {
    iv <- base64enc::base64decode(enc_obj$iv_b64 %||% "")
    ct <- base64enc::base64decode(enc_obj$cipher_b64 %||% "")
    tg <- base64enc::base64decode(enc_obj$tag_b64 %||% "")

    raw <- openssl::aes_gcm_decrypt(
      data = ct,
      key  = k,
      iv   = iv,
      tag  = tg
      # aad = NULL
    )
    return(rawToChar(raw))
  }

  # — Geriye dönük: eski CBC kayıtları için çözüm
  iv <- base64enc::base64decode(enc_obj$iv_b64 %||% "")
  ct <- base64enc::base64decode(enc_obj$cipher_b64 %||% "")
  rawToChar(openssl::aes_cbc_decrypt(ct, key = k, iv = iv))
}

save_user_api_key <- function(system_username, key_plain) {
  f <- .api_user_file(system_username)
  master <- Sys.getenv("AI_KEYS_MASTER", "")
  if (!nzchar(master)) stop("AI_KEYS_MASTER is missing in .Renviron")

  salt <- openssl::rand_bytes(16L)
  hash_hex <- .hash_key_hex(key_plain, salt)
  enc <- .enc_key(key_plain, master)

  rec <- list(
    user = system_username,
    salt_b64 = base64enc::base64encode(salt),
    hash_hex = hash_hex,
    enc = enc,
    created_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )
  jsonlite::write_json(rec, f, auto_unbox = TRUE, pretty = TRUE)
  normalizePath(f, winslash = "/", mustWork = FALSE)
}

load_user_api_key <- function(system_username) {
  f <- .api_user_file(system_username)
  if (!file.exists(f)) return(NULL)
  master <- Sys.getenv("AI_KEYS_MASTER", "")
  if (!nzchar(master)) return(NULL)
  rec <- try(jsonlite::read_json(f, simplifyVector = TRUE), silent = TRUE)
  if (inherits(rec, "try-error") || is.null(rec$enc)) return(NULL)
  tryCatch(.dec_key(rec$enc, master), error = function(e) NULL)
}

user_api_key_exists <- function(system_username) file.exists(.api_user_file(system_username))

verify_user_api_key <- function(system_username, candidate_plain) {
  f <- .api_user_file(system_username)
  if (!file.exists(f)) return(FALSE)
  rec <- try(jsonlite::read_json(f, simplifyVector = TRUE), silent = TRUE)
  if (inherits(rec, "try-error")) return(FALSE)
  salt <- base64enc::base64decode(rec$salt_b64 %||% "")
  hash_hex <- .hash_key_hex(candidate_plain, salt)
  isTRUE(identical(tolower(hash_hex), tolower(rec$hash_hex %||% "")))
}

# --- API ANAHTARI DOĞRULAMA (anında kontrol) -------------------------------
# Sağlık ucu tercihi: LLM_HEALTH_ENDPOINT env set ise onu dener; yoksa sohbet endpoint'ine mini bir ping atar.
validate_api_key <- function(api_key, model_id = NULL, endpoint = NULL, timeout_seconds = 5) {
  if (!nzchar(api_key)) {
    return(list(valid = FALSE, message = "Anahtar boş."))
  }

  # 1) Health endpoint varsa onu kullan
  health_url <- Sys.getenv("LLM_HEALTH_ENDPOINT", "")
  if (!nzchar(endpoint)) {
    endpoint <- api_config$local_llm_endpoint %||% api_config$local_llm$endpoint %||% ""
  }

  # 2) Model belirle
  if (is.null(model_id) || !nzchar(model_id)) {
    # İlk modelin TEKNİK ID'sini kullan (api_config$local_models bir named vector)
    model_id <- as.character(api_config$local_models[1])
  }

  hdrs <- httr::add_headers(
    `Content-Type` = "application/json",
    `Authorization` = paste("Bearer", api_key)
  )

  # Önce health (GET) dene (varsa)
  if (nzchar(health_url)) {
    res <- try(httr::GET(health_url, hdrs, httr::timeout(timeout_seconds)), silent = TRUE)
    if (!inherits(res, "try-error")) {
      sc <- httr::status_code(res)
      if (sc == 200) return(list(valid = TRUE,  message = "Sağlık/kimlik doğrulama başarılı."))
      if (sc %in% c(401, 403)) return(list(valid = FALSE, message = "Anahtar reddedildi (401/403)."))
      # Diğer kodlar: devam edip ping deneyeceğiz
    }
  }

  # Health yoksa veya başarısızsa: sohbet endpoint'ine minimum POST ping
  if (!nzchar(endpoint)) {
    return(list(valid = NA, message = "Doğrulama yapılamadı (endpoint tanımsız)."))
  }

  body <- list(
    model = model_id,
    messages = list(list(role = "system", content = "health check")),
    stream = FALSE,
    temperature = 0
  )

  res2 <- try(httr::POST(endpoint, hdrs, body = body, encode = "json", httr::timeout(timeout_seconds)), silent = TRUE)
  if (inherits(res2, "try-error")) {
    return(list(valid = NA, message = "Doğrulama yapılamadı (bağlantı/timeout)."))
  }

  sc2 <- httr::status_code(res2)
  if (sc2 == 200)  return(list(valid = TRUE,  message = "Anahtar doğrulandı."))
  if (sc2 %in% c(401, 403)) return(list(valid = FALSE, message = "Anahtar reddedildi (401/403)."))
  if (sc2 == 429)  return(list(valid = NA,   message = "Hız limiti (429) — daha sonra deneyin."))
  if (sc2 >= 500)  return(list(valid = NA,   message = paste("Sunucu hatası:", sc2)))
  return(list(valid = NA, message = paste("Beklenmedik durum:", sc2)))
}

# ---------------------------------------------------------------------------

`%||%` <- function(a, b) {
  if (is.null(a)) b else a
}

safe_nzchar <- function(x) {
  is.character(x) && length(x) > 0 && !is.na(x[1]) && nzchar(x[1])
}

format_timestamp <- function() {
  format(Sys.time(), "%d.%m.%Y - %H:%M")
}

# --- Helper to strip planner/agent meta anywhere in text ---
strip_planner_text <- function(x) {
  # tolerate NULL/character(0) safely
  if (is.null(x)) return(x)
  if (!is.character(x) || length(x) == 0) return("")   # <-- key guard
  s <- x[1]
  if (!nzchar(s)) return(s)

  s <- gsub("\\{\\s*\"(tool|name)\"\\s*:\\s*\"[^\"]+\"[^{}]*\"arguments\"\\s*:\\s*\\{[^{}]*\\}\\s*\\}", "", s, perl = TRUE)
  s <- gsub("\\{\\s*\"action\"\\s*:\\s*\"[^\"]+\"[^{}]*\"parameters\"\\s*:\\s*\\{[^{}]*\\}\\s*\\}", "", s, perl = TRUE)
  s <- gsub("\\s*<tool_call>.*?</tool_call>\\s*", "", s, perl = TRUE)

  s <- gsub("(?im)^(we need to .*|let'?s try.*|probably .*|i'?ll try.*|we will call.*|we will invoke.*|now produce the tool call\\.?|we need to produce a tool call.*)$", "", s, perl = TRUE)
  s <- gsub("(?i)(we need to call|we need to invoke|we will call|we will invoke|let'?s call|let'?s invoke|now produce the tool call|we need to produce a tool call)[^\\n]*", "", s, perl = TRUE)

  s <- gsub("\n{3,}", "\n\n", trimws(s))
  s
}

# Optional DOCX -> PDF conversion with LibreOffice (used only if options(mergen.word_preview_mode) == "pdf")
convert_docx_to_pdf <- function(docx_path) {
  if (!file.exists(docx_path)) stop("Path not found: ", docx_path)
  cmd <- Sys.which("soffice")
  if (!nzchar(cmd)) stop("LibreOffice ('soffice') not found in PATH. Install it or set options(mergen.word_preview_mode = 'html').")
  outdir <- dirname(docx_path)
  # Do the conversion
  res <- try(
    system2(cmd,
      args = c("--headless", "--norestore", "--convert-to", "pdf", "--outdir", shQuote(outdir), shQuote(docx_path)),
      stdout = TRUE, stderr = TRUE
    ),
    silent = TRUE
  )
  pdf_path <- sub("\\.docx$", ".pdf", docx_path, ignore.case = TRUE)
  if (!file.exists(pdf_path)) stop("PDF not produced. LibreOffice output: ", paste(res, collapse = "\n"))
  normalizePath(pdf_path, winslash = "/", mustWork = TRUE)
}

# --- Build a concise Turkish answer directly from raw tool results (TR + EN keys) ---
format_answer_from_tool_results <- function(tool_results_raw) {
  if (length(tool_results_raw) == 0) return(NULL)
  tr <- tool_results_raw[[1]]
  if (is.null(tr)) return(NULL)

  get2 <- function(x, k1, k2 = NULL) {
    if (!is.null(x[[k1]])) return(x[[k1]])
    if (!is.null(k2) && !is.null(x[[k2]])) return(x[[k2]])
    NULL
  }

  # sql_query_uploaded_file: result preview (single cell)
  df <- get2(tr, "sonuç_önizleme", "result_preview")
  if (is.data.frame(df) && nrow(df) >= 1 && ncol(df) >= 1) {
    cname <- colnames(df)[1]
    v <- df[1, 1]
    if (is.numeric(v)) {
      val <- as.numeric(v)
      lc <- tolower(cname)
      if (grepl("avg|mean|average", lc))       return(sprintf("Ortalama: %.2f", val))
      if (grepl("max", lc))                    return(sprintf("En yüksek değer: %.2f", val))
      if (grepl("min", lc))                    return(sprintf("En düşük değer: %.2f", val))
      if (grepl("count|distinct", lc))         return(sprintf("Sayı: %d", as.integer(round(val))))
      return(sprintf("%s: %s", cname, format(val, trim = TRUE, scientific = FALSE)))
    } else {
      return(sprintf("%s: %s", cname, as.character(v)))
    }
  }

  # get_column_statistics (numeric)
  typ <- get2(tr, "tür", "type")
  if (identical(typ, "numeric")) {
    col   <- get2(tr, "sütun", "column")
    meanv <- get2(tr, "ortalama", "mean")
    med   <- get2(tr, "medyan", "median")
    minv  <- get2(tr, "minimum", "min")
    maxv  <- get2(tr, "maksimum", "max")
    return(sprintf(
      "%s sütunu — Ortalama: %.2f, Medyan: %.2f, Min: %.2f, Max: %.2f",
      col %||% "Seçilen", meanv %||% NA_real_, med %||% NA_real_, minv %||% NA_real_, maxv %||% NA_real_
    ))
  }

  # analyze_uploaded_file
  rows <- get2(tr, "satır_sayısı", "row_count")
  cols <- get2(tr, "sütun_sayısı", "column_count")
  if (!is.null(rows) && !is.null(cols)) {
    return(sprintf("Dosyada %d satır ve %d sütun var.", rows, cols))
  }

  NULL
}

# --- FAST EXCEL PROFILE (used by server + MCP tools) ---
fast_profile <- function(df, top_levels = 12) {
  dt <- data.table::as.data.table(df)
  n  <- nrow(dt)

  types <- vapply(dt, function(x) class(x)[1], character(1))
  miss  <- vapply(dt, function(x) mean(is.na(x)), numeric(1))

  num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
  cat_cols <- names(dt)[vapply(dt, function(x) is.character(x) || is.factor(x), logical(1))]

  num_stats <- if (length(num_cols)) {
    data.table::rbindlist(lapply(num_cols, function(cn) {
      x <- dt[[cn]]
      data.table::data.table(
        column = cn,
        min    = suppressWarnings(min(x, na.rm = TRUE)),
        p25    = suppressWarnings(as.numeric(stats::quantile(x, 0.25, na.rm = TRUE))),
        median = suppressWarnings(stats::median(x, na.rm = TRUE)),
        mean   = suppressWarnings(mean(x, na.rm = TRUE)),
        p75    = suppressWarnings(as.numeric(stats::quantile(x, 0.75, na.rm = TRUE))),
        max    = suppressWarnings(max(x, na.rm = TRUE)),
        sd     = suppressWarnings(stats::sd(x,  na.rm = TRUE))
      )
    }), fill = TRUE, use.names = TRUE)
  } else data.table::data.table()

  cat_top <- if (length(cat_cols)) {
    data.table::rbindlist(lapply(cat_cols, function(cn) {
      tbl <- sort(table(dt[[cn]]), decreasing = TRUE)
      head_tbl <- head(tbl, top_levels)
      data.table::data.table(column = cn, level = names(head_tbl), n = as.integer(head_tbl))
    }), fill = TRUE, use.names = TRUE)
  } else data.table::data.table()

  list(
    shape     = list(rows = n, cols = ncol(dt)),
    col_types = as.list(types),
    missing   = as.list(miss),
    numeric   = num_stats,
    categories= cat_top
  )
}

build_excel_digest_json <- function(path, top_levels = 12) {
  df <- safe_read_excel_table(path)
  prof <- fast_profile(df, top_levels = top_levels)
  jsonlite::toJSON(prof, dataframe = "rows", na = "string", auto_unbox = TRUE)
}

# Allow the model to do multiple tool/LLM rounds when tools are enabled
MAX_MCP_RECURSION <- 4

# Shared LLM worker function with prompt-based MCP support
call_llm_worker <- function(chat_history, settings, api_endpoint, api_key = NULL, enable_tools = NULL, recursion_depth = 0) {
  worker_start_time <- Sys.time()      # <— add this line
  # Prevent infinite recursion

  if (recursion_depth > 5) {
    cat("[MCP] Max recursion depth reached\n")
    enable_tools <- FALSE
  }
  
  # Check if tools should be enabled
  if (is.null(enable_tools)) {
    enable_tools <- settings$enable_mcp_tools %||% FALSE
  }
  
  tryCatch({
    selected_model <- settings$model_selection %||% "mergen-local-model"
    
    # NEW — resolve the OpenAI tool schema once per call
    session_obj <- settings$shiny_session %||% NULL
	
	# --- Build tools spec and derive flag BEFORE using it ---
	mcp_spec <- if (isTRUE(enable_tools) &&
					exists("helpers_mcp_tools", inherits = TRUE) &&
					(is.environment(helpers_mcp_tools) || is.list(helpers_mcp_tools)) &&
					is.function(helpers_mcp_tools$get_openai_tools)) {
	  helpers_mcp_tools$get_openai_tools(session_obj)
	} else {
	  list(tools = list())
	}

	# Define the flag once and reuse it everywhere
	mcp_enabled_now <- isTRUE(enable_tools) &&
					   is.list(mcp_spec$tools) &&
					   length(mcp_spec$tools) > 0

	# --- DEFENSIVE PATCH: ensure parameters.required is always a JSON array ---
	if (mcp_enabled_now) {
	  mcp_spec$tools <- lapply(mcp_spec$tools, function(tdef) {
		if (!is.null(tdef$`function`) && !is.null(tdef$`function`$parameters)) {
		  req <- tdef$`function`$parameters$required
		  # Some servers incorrectly serialize this as a string; normalize to array
		  if (is.character(req) && length(req) == 1) {
			tdef$`function`$parameters$required <- list(req)
		  }
		}
		tdef
	  })
	}

    cat("\n========================================\n")
    cat("[LLM CALL] Model:", selected_model, "\n")
    cat("[LLM CALL] MCP Enabled:", if (mcp_enabled_now) "TRUE" else "FALSE", "\n")
    cat("[LLM CALL] Recursion depth:", recursion_depth, "\n")
    cat("========================================\n")
    
    messages_payload <- lapply(chat_history, function(msg) {
      role_val <- if (!is.null(msg$type)) {
        if (identical(msg$type, "user")) "user"
        else if (identical(msg$type, "system")) "system"
        else "assistant"
      } else if (!is.null(msg$role)) {
        tolower(as.character(msg$role))
      } else {
        "user"
      }
      
      content_val <- msg$content %||% msg$message %||% as.character(msg)
      list(role = role_val, content = content_val)
    })
    
	# Inject tool descriptions if enabled
	if (isTRUE(enable_tools) &&
		exists("helpers_mcp_tools", inherits = TRUE) &&
		is.function(helpers_mcp_tools$get_mcp_tools_prompt)) {

	  tool_prompt <- helpers_mcp_tools$get_mcp_tools_prompt()

	  # Add to system message
	  system_msg <- list(
		role = "system",
		content = paste0(
		  tool_prompt,
		  "\nKarmaşık/nested mantık (filtrele + grupla + sırala + LIMIT, koşullu ortalama/toplam) için her zaman tek bir SQL sorgusu yaz ve 'sql_query_uploaded_file' aracını kullan. Tablo adı: t.\n",
		  "\n\nSEN BİR ARAÇ ÇAĞIRICI BOTUSUN.\n",
		  "Dosya sorusu gelirse:\n",
		  "1. SADECE araç çağrısı yap\n",
		  "2. Başka hiçbir şey yazma\n",
		  "3. Açıklama yapma, düşünme sürecini gösterme\n",
		  "4. Araç sonucu aldıktan sonra Türkçe cevap ver"
		)
	  )
	  messages_payload <- c(list(system_msg), messages_payload)
	  cat("[MCP] Tool descriptions injected into prompt\n")
	}
    
    temp_value <- if (!is.null(settings$temperature)) settings$temperature else 0.4
    
    body <- list(
      model = selected_model, 
      messages = messages_payload, 
      stream = FALSE,
      temperature = temp_value
    )

	# NEW — attach OpenAI tool schema so the model can emit structured tool calls
	if (mcp_enabled_now) {
	  body$tools <- mcp_spec$tools
	  # FIX: must be a scalar string per OpenAI schema, not an object
	  body$tool_choice <- "auto"
	}
    
    hdrs <- list(`Content-Type` = "application/json")
    if (!is.null(api_key) && nzchar(api_key)) {
      hdrs$Authorization <- paste("Bearer", api_key)
    }
    
	response <- httr::POST(
	  api_endpoint,
	  do.call(httr::add_headers, hdrs),
	  body = jsonlite::toJSON(body, auto_unbox = TRUE),
	  encode = "raw",
	  timeout(60)
	)

	status <- httr::status_code(response)

	if (status != 200) {
	  resp_txt_raw <- try(httr::content(response, "text", encoding = "UTF-8"), silent = TRUE)
	  # Coerce to a safe single string; empty on any problem/zero-length
	  resp_txt <- if (!inherits(resp_txt_raw, "try-error") && is.character(resp_txt_raw) && length(resp_txt_raw) > 0) {
		resp_txt_raw[[1]]
	  } else {
		""
	  }
	  msg_tail <- if (nzchar(resp_txt)) paste0(" — ", substr(resp_txt, 1, 500)) else ""
	  if (status == 429) stop("RATE_LIMIT: Çok fazla istek gönderildi.", call. = FALSE)
	  else if (status == 401 || status == 403) stop("AUTH_ERROR: Kimlik doğrulama hatası.", call. = FALSE)
	  else if (status >= 500) stop(sprintf("SERVER_ERROR: Sunucu hatası (Kod: %d)%s", status, msg_tail), call. = FALSE)
	  else stop(sprintf("API_ERROR: API hatası (Kod: %d)%s", status, msg_tail), call. = FALSE)
	}
    
    response_content <- httr::content(response, "parsed")
    
    ai_content <- NULL
    tool_calls_struct <- NULL
    
    if (is.list(response_content) &&
        !is.null(response_content$choices) &&
        length(response_content$choices) > 0) {
      first_choice <- response_content$choices[[1]]
      if (is.list(first_choice) && !is.null(first_choice$message)) {
        ai_content <- first_choice$message$content %||% ""
        # NEW: capture structured tool calls from the API
        if (!is.null(first_choice$message$tool_calls) && length(first_choice$message$tool_calls) > 0) {
          tool_calls_struct <- first_choice$message$tool_calls
        }
      }
    }
    
	# Only error if neither content nor structured tool calls exist (length-safe)
	has_content <- is.character(ai_content) && length(ai_content) > 0 && nzchar(ai_content[1])
	if (!has_content && (is.null(tool_calls_struct) || length(tool_calls_struct) == 0)) {
	  stop("EMPTY_RESPONSE: AI'dan geçerli bir yanıt alınamadı.")
	}
    
	cat("[RESPONSE] Content length:", if (has_content) nchar(ai_content[1]) else 0, "chars\n")
	cat("[RESPONSE] Preview:", if (has_content) substr(ai_content[1], 1, 200) else "", "...\n")
		
    # Buffer to collect charts to send back to the main session (do NOT touch session here)
    charts_to_store <- list()

    # Parse for tool calls if MCP enabled
    if (enable_tools) {
      tool_calls <- list()
    
      # 1) Prefer structured tool_calls returned by the API
      if (!is.null(tool_calls_struct) && length(tool_calls_struct) > 0) {
        cat("[MCP] Structured tool_calls detected from API:", length(tool_calls_struct), "\n")
        tool_calls <- lapply(tool_calls_struct, function(tc) {
          fn <- try(tc$`function`$name, silent = TRUE)
          arg_raw <- try(tc$`function`$arguments, silent = TRUE)
          args <- list()
          if (!inherits(arg_raw, "try-error") && is.character(arg_raw) && nzchar(arg_raw)) {
            args <- tryCatch(jsonlite::fromJSON(arg_raw, simplifyVector = FALSE), error = function(e) list())
          } else if (is.list(arg_raw)) {
            args <- arg_raw
          }
          list(function_name = fn %||% "", arguments = args %||% list())
        })
		} else if (exists("helpers_mcp_tools", inherits = TRUE) &&
				   is.function(helpers_mcp_tools$parse_tool_calls_from_text)) {
		  # 2) Fallback to textual parsing (helpers env)
		  tool_calls <- helpers_mcp_tools$parse_tool_calls_from_text(ai_content %||% "")
		}
    
      if (length(tool_calls) > 0) {
        cat("\n========================================\n")
        cat("[MCP SUCCESS] Parsed", length(tool_calls), "tool call(s)\n")
        cat("========================================\n")
    
        # Get session for resolvers
        current_session <- if (!is.null(settings$shiny_session)) settings$shiny_session else NULL
    
        # Execute all tools (keep RAW results separately)
        cat("[MCP] Executing tools...\n")
        tool_results_raw <- lapply(tool_calls, function(tc) {
          cat("[MCP] Executing:", tc$function_name, "\n")
    
          if (!is.null(tc$arguments) && !is.null(tc$arguments$file_name)) {
            cat("[MCP WORKER] Passing file_name through as:", tc$arguments$file_name, "\n")
          }
    
          helpers_mcp_tools$execute_parsed_tool(tc, session = current_session)
        })
		
		# --- NEW: collect any chart specs to be injected back into the chat (as fenced blocks) ---
		# IMPORTANT: we're in a worker. Do NOT touch the Shiny session here.
		chart_blocks_text <- ""
		try({
		  chart_specs <- Filter(function(x) is.list(x) && isTRUE(x[["__mcp_plot"]]) && !is.null(x[["chart"]]), tool_results_raw)
		  if (length(chart_specs)) {

			parts <- vapply(seq_along(chart_specs), function(i) {
			  cs <- chart_specs[[i]]
			  full <- cs$chart

				# unique ref id
				ref_id <- paste0(
				  "cl_", format(Sys.time(), "%Y%m%d%H%M%OS3"), "_", sprintf("%04d", sample(0:9999, 1))
				)

				# store full spec in the chart store (for backwards-compat / reuse)
				charts_to_store[[ref_id]] <<- full

				# IMPORTANT: KEEP data inline to avoid any race with chart_store resolution
				inline <- full
				inline$ref <- ref_id  # we still add ref, but we do NOT drop data anymore

				jsonlite::toJSON(inline, auto_unbox = TRUE, null = "null", digits = 12)
			}, character(1))

			chart_blocks_text <- paste0(
			  paste0("\n\n```chartlab\n", parts, "\n```"),
			  collapse = ""
			)
		  }
		}, silent = TRUE)
            
        # If any tool returned error, aggregate and short-circuit
        errs <- vapply(tool_results_raw, function(r) if (is.list(r) && !is.null(r$error)) r$error else "", "")
        if (any(nzchar(errs))) {
          err_text <- paste(errs[nzchar(errs)], collapse = "\n")
			return(list(
			  content  = paste("Araç hatası:\n", err_text),
			  duration = as.numeric(difftime(Sys.time(), worker_start_time, units = "secs")),
			  chart_store = charts_to_store
			))
        }
        
        # JSON-ify for feeding back to the model
        tool_results <- lapply(seq_along(tool_calls), function(i) {
          list(
            tool   = tool_calls[[i]]$function_name,
            result = jsonlite::toJSON(tool_results_raw[[i]], auto_unbox = TRUE, pretty = TRUE)
          )
        })
        for (tr in tool_results) {
          cat("[MCP] Tool result:\n", substr(tr$result, 1, 500), "...\n")
        }
        
        # Build result message for LLM
        results_text <- paste(
          sapply(tool_results, function(tr) {
            paste0("=== Araç: ", tr$tool, " ===\n", tr$result)
          }),
          collapse = "\n\n"
        )
        
        # Add to history - IMPORTANT: Don't include raw tool call text
        chat_history <- append(chat_history, list(
          list(role = "assistant", content = "[Araçlar kullanıldı]")
        ))
        chat_history <- append(chat_history, list(
          list(role = "user", content = paste0(
            "Araç sonuçları:\n\n", 
            results_text, 
            "\n\n===== ÖNEMLİ TALİMAT =====\n",
            "Yukarıdaki araç sonuçlarını kullanarak kullanıcının sorusunu Türkçe cevapla.\n",
            "Sadece sonuçları açıkla, araç çağrılarını tekrar etme.\n",
            "Sayıları doğru kullan, sonuçlardan kopyala."
          ))
        ))
        
        cat("\n========================================\n")
        cat("[MCP] Calling LLM again with tool results\n")
        cat("========================================\n")
        
        # SECOND PASS: ask the model to write the final answer from tool results (tools OFF)
        messages_payload2 <- lapply(chat_history, function(msg) {
          role_val <- if (!is.null(msg$type)) {
            if (identical(msg$type, "user")) "user"
            else if (identical(msg$type, "system")) "system"
            else "assistant"
          } else if (!is.null(msg$role)) {
            tolower(as.character(msg$role))
          } else {
            "user"
          }
          content_val <- msg$content %||% msg$message %||% as.character(msg)
          list(role = role_val, content = content_val)
        })
        
        body2 <- list(
          model = selected_model,
          messages = messages_payload2,
          stream = FALSE,
          temperature = temp_value
        )
        
        hdrs2 <- list(`Content-Type` = "application/json")
        if (!is.null(api_key) && nzchar(api_key)) {
          hdrs2$Authorization <- paste("Bearer", api_key)
        }
        
        response2 <- httr::POST(
          api_endpoint,
          do.call(httr::add_headers, hdrs2),
          body = jsonlite::toJSON(body2, auto_unbox = TRUE),
          encode = "raw",
          timeout(60)
        )
        
		status2 <- httr::status_code(response2)
		if (status2 != 200) {
			fb <- format_answer_from_tool_results(tool_results_raw)
			if (!(is.character(fb) && length(fb) > 0 && nzchar(trimws(fb[1])))) {
			  fb <- "Araç çıktıları alındı ancak yanıt üretilemedi."
			}
			if (is.character(chart_blocks_text) && nzchar(chart_blocks_text)) {
			  fb <- paste0(fb, "\n\n", chart_blocks_text)
			}
			return(list(
			  content  = fb,
			  duration = as.numeric(difftime(Sys.time(), worker_start_time, units = "secs")),
			  chart_store = charts_to_store
			))
		}

		rc2 <- httr::content(response2, "parsed")
        ai2 <- NULL
        if (is.list(rc2) && !is.null(rc2$choices) && length(rc2$choices) > 0) {
          first_choice2 <- rc2$choices[[1]]
          if (is.list(first_choice2) && !is.null(first_choice2$message)) {
            ai2 <- first_choice2$message$content
          }
        }
        
		if (!(is.character(ai2) && length(ai2) > 0 && nzchar(ai2[1]))) {
			fb <- format_answer_from_tool_results(tool_results_raw)
			if (!(is.character(fb) && length(fb) > 0 && nzchar(trimws(fb[1])))) {
			  fb <- "Araç çıktıları alındı ancak modelden içerik gelmedi."
			}
			if (is.character(chart_blocks_text) && nzchar(chart_blocks_text)) {
			  fb <- paste0(fb, "\n\n", chart_blocks_text)
			}
			return(list(
			  content  = fb,
			  duration = as.numeric(difftime(Sys.time(), worker_start_time, units = "secs")),
			  chart_store = charts_to_store
			))
		}
        
		ai2 <- strip_planner_text(ai2)

		# --- NEW: append chart blocks if any ---
		if (is.character(chart_blocks_text) && nzchar(chart_blocks_text)) {
		  ai2 <- paste0(ai2, "\n\n", chart_blocks_text)
		}

		return(list(
		  content  = ai2,
		  duration = as.numeric(difftime(Sys.time(), worker_start_time, units = "secs")),
		  chart_store = charts_to_store
		))

      } else {
        cat("[MCP] No tool calls detected (structured or textual)\n")
      }
    }
    
    cat("[SUCCESS] Returning response\n")
    cat("========================================\n\n")

    ai_content <- strip_planner_text(ai_content)
              
	return(list(
	  content = ai_content,
	  duration = as.numeric(difftime(Sys.time(), worker_start_time, units = "secs")),
	  chart_store = charts_to_store
	))
    
  }, error = function(e) {
    error_msg <- as.character(e$message)
    cat("[ERROR]", error_msg, "\n")
    
    if (grepl("^RATE_LIMIT:|^AUTH_ERROR:|^SERVER_ERROR:|^API_ERROR:|^EMPTY_RESPONSE:", error_msg)) {
      stop(error_msg)
    } else if (grepl("Timeout", error_msg, ignore.case = TRUE)) {
      stop("TIMEOUT: İstek zaman aşımına uğradı.")
    } else {
      stop(sprintf("UNKNOWN_ERROR: %s", error_msg))
    }
  })
}

  # Worker-safe LLM call - RESTORED FROM ORIGINAL WORKING VERSION
  call_local_llm <- function(chat_history, current_settings) {
	llm_start_time <- Sys.time()
    selected_model <- current_settings$model_selection
    
    # Handle both potential api_config structures
    api_url <- if (!is.null(api_config$local_llm_endpoint)) {
      api_config$local_llm_endpoint  # Your structure
    } else if (!is.null(api_config$local_llm$endpoint)) {
      api_config$local_llm$endpoint  # Alternative structure
    } else {
      stop("API endpoint not found in configuration")
    }
    
	# Get per-session user key from settings$shiny_session (set in server)
	sess <- current_settings$shiny_session %||% NULL
	api_key <- NULL
	if (!is.null(sess) && !is.null(sess$userData$ai_api_key)) {
	  api_key <- as.character(sess$userData$ai_api_key)[1]
	}
	if (!nzchar(api_key)) {
	  stop("AUTH_MISSING_KEY: Kullanıcı API anahtarı bulunamadı. Lütfen Ayarlar > Model Ayarları > API Anahtarı Güncelleme üzerinden girin.")
	}
    
    messages_payload <- lapply(chat_history, function(msg) {
      role_val <- NULL
		if (!is.null(msg$type)) {
		  role_val <- if (identical(msg$type, "user")) "user"
			else if (identical(msg$type, "system")) "system"
			else "assistant"
		} else if (!is.null(msg$role)) {
        role_val <- tolower(as.character(msg$role))
        if (!(role_val %in% c("user", "assistant", "system"))) {
          role_val <- "user"
        }
      } else {
        role_val <- "user"
      }
    
      content_val <- NULL
      if (!is.null(msg$content)) {
        content_val <- msg$content
      } else if (!is.null(msg$message)) {
        content_val <- msg$message
      } else {
        content_val <- as.character(msg)
      }
    
      list(role = role_val, content = content_val)
    })
  
    # Get temperature from settings if available
    temp_value <- if (!is.null(current_settings$temperature)) current_settings$temperature else 0.4
    
    body <- list(
      model = selected_model,
      messages = messages_payload,
      stream = FALSE,
      temperature = temp_value
    )
    
	response <- httr::POST(
	  url = api_url,
	  body = body,                 # pass the list; let httr serialize it
	  encode = "json",             # httr sets Content-Type and serializes once
	  httr::add_headers(
		`Content-Type` = "application/json",
		`Authorization` = paste("Bearer", api_key)
	  ),
	  httr::timeout(300)
	)
    
    httr::stop_for_status(response, "get local LLM response")
    response_content <- httr::content(response, "parsed")
    
    # Extract content and sources
    ai_content <- NULL
    sources_list <- NULL
    
    if (is.list(response_content) && 
        !is.null(response_content$choices) && 
        length(response_content$choices) > 0) {
      first_choice <- response_content$choices[[1]]
      if (is.list(first_choice) && 
          !is.null(first_choice$message) && 
          !is.null(first_choice$message$content)) {
        content_obj <- first_choice$message$content
		if (is.character(content_obj) && length(content_obj) > 0) {
		  ai_content <- trimws(content_obj[1])
		} else {
		  ai_content <- ""
		}
        
        # Extract sources if present
        if (!is.null(first_choice$message$sources)) {
          sources_list <- first_choice$message$sources
        }
      }
    }
	
	# DEBUG LOG: içerik çıkarımından hemen sonra
    cat("[LOCAL_LLM] parsed content length=",
        if (is.null(ai_content)) NA_integer_ else length(ai_content),
        " class=", paste(class(ai_content), collapse = ","),
        " nzchar1=",
        if (is.character(ai_content) && length(ai_content) > 0) nzchar(ai_content[1]) else NA,
        ' preview="', substr(as.character(ai_content)[1], 1, 120), '"\n',
        sep = "")
    
    # Check for sources at different levels
    if (is.null(sources_list) && !is.null(response_content$sources)) {
      sources_list <- response_content$sources
    }
    if (is.null(sources_list) && !is.null(response_content$message$sources)) {
      sources_list <- response_content$message$sources
    }
    
    # If sources found, extract filenames from metadata
    if (!is.null(sources_list) && length(sources_list) > 0) {
      cat("\n========== SOURCES PROCESSING ==========\n")
      
      extracted_sources <- list()
      seen_filenames <- character(0)
      
      for (i in seq_along(sources_list)) {
        src <- sources_list[[i]]
        
        if (is.list(src) && !is.null(src[["metadata"]])) {
          metadata_array <- src[["metadata"]]
          
          for (j in seq_along(metadata_array)) {
            doc <- metadata_array[[j]]
            
            # Extract filename from "name" or "source"
            filename <- doc[["name"]] %||% doc[["source"]]
            
            if (!is.null(filename) && is.character(filename)) {
              filename <- as.character(filename)[1]
              
              # Check for duplicate
              if (filename %in% seen_filenames) {
                cat("[DOCUMENT ", j, "] DUPLICATE - skipping: <", filename, ">\n\n", sep = "")
                next
              }
              
              cat("[DOCUMENT ", j, "] Extracted: <", filename, ">\n", sep = "")
              seen_filenames <- c(seen_filenames, filename)
              
              # Parse filename: extract process number and actual filename
              process_match <- regexpr("^[a-z]+_[0-9]+_[0-9]+_", filename, ignore.case = TRUE)
              
              process_num <- ""
              actual_filename <- filename
              
              if (process_match > 0) {
                match_length <- attr(process_match, "match.length")
                process_part <- substr(filename, 1, match_length - 1)
                actual_filename <- substr(filename, match_length + 1, nchar(filename))
                
                # Format process number: replace underscores AND dashes with spaces, uppercase
                process_num <- toupper(process_part)
                process_num <- gsub("_", " ", process_num)
                process_num <- gsub("-", " ", process_num)
                
                cat("[DOCUMENT ", j, "] Process: <", process_num, ">\n", sep = "")
                cat("[DOCUMENT ", j, "] Filename: <", actual_filename, ">\n", sep = "")
              }
              
              # Format actual filename
              file_ext <- tools::file_ext(actual_filename)
              file_base <- tools::file_path_sans_ext(actual_filename)
              file_base <- gsub("_", " ", file_base)
              file_base <- gsub("-", " ", file_base)
              file_base <- tools::toTitleCase(file_base)
              formatted_filename <- paste0(file_base, ".", file_ext)
              
              extracted_sources[[length(extracted_sources) + 1]] <- list(
                process = process_num,
                filename = formatted_filename,
                original_filename = filename
              )
              
              cat("[DOCUMENT ", j, "] Final: ", process_num, ": ", formatted_filename, "\n\n", sep = "")
            }
          }
        }
      }
      
      cat("[SUMMARY] Total unique sources:", length(extracted_sources), "\n")
      
		# Append Kaynakça section with clickable links
		if (length(extracted_sources) > 0) {
		  sources_text <- "\n\nKaynakça:\n"
		  
		  for (i in seq_along(extracted_sources)) {
			src_info <- extracted_sources[[i]]
			
			# Unique id for this source
			source_id <- paste0("source_", i, "_", gsub("[^a-z0-9]", "", tolower(src_info$filename)))
			
			# Always use the ORIGINAL filename as-is for opening
			original_filename <- src_info$original_filename
			file_ext <- tolower(tools::file_ext(original_filename))
			
			# Pick an icon by extension (Word/PDF, fallback generic)
			icon_html <- if (file_ext %in% c("doc","docx")) {
			  "<i class='fa-regular fa-file-word' style='margin-right:6px;color:#2b579a'></i>"
			} else if (identical(file_ext, "pdf")) {
			  "<i class='fa-regular fa-file-pdf' style='margin-right:6px;color:#c00'></i>"
			} else {
			  "<i class='fa-regular fa-file' style='margin-right:6px;'></i>"
			}
			
			# Görüntüde sadece son parçayı göster; ancak tıklama için TAM dosya adını taşı
			parts_raw <- strsplit(original_filename, "&&", fixed = TRUE)[[1]]
			
			# Label prefix (process info if present)
			label_prefix <- if (nchar(src_info$process) > 0) paste0(src_info$process, ": ") else ""
			
			if (length(parts_raw) > 1) {
			  parts <- trimws(parts_raw)
			  left_parts <- if (length(parts) > 1) parts[seq_len(length(parts) - 1)] else character(0)
			  right_part <- parts[length(parts)]
			  
			  left_html <- if (length(left_parts)) {
				paste(
				  vapply(left_parts, function(p) {
					paste0("<span class='source-chunk'>", htmltools::htmlEscape(p), "</span>")
				  }, character(1)),
				  collapse = " - "
				)
			  } else ""
			  
				clickable_html <- paste0(
				  "<span class='source-link' data-source-id='", source_id,
				  # tıklama için tam dosya adını (&& dahil) gönder
				  "' data-filename='", htmltools::htmlEscape(original_filename, attribute = TRUE),  # düzeltme: tam ad
				  "' style='color:#007bff; cursor:pointer; text-decoration:underline;'>",
				  htmltools::htmlEscape(trimws(right_part)),
				  "</span>"
				)
			  
			  # Compose the line:
			  #   i) [process:] [icon] [left - chunks] - [CLICKABLE last chunk]
			  line <- paste0(
				i, ") ", label_prefix, icon_html,
				if (nzchar(left_html)) paste0(left_html, " - ") else "",
				clickable_html, "\n"
			  )
			  
			} else {
			  # No "&&" — keep whole display clickable (as before), but keep the icon
			  clickable_html <- paste0(
				"<span class='source-link' data-source-id='", source_id,
				"' data-filename='", htmltools::htmlEscape(original_filename, attribute = TRUE),
				"' style='color:#007bff; cursor:pointer; text-decoration:underline;'>",
				htmltools::htmlEscape(src_info$filename),
				"</span>"
			  )
			  line <- paste0(i, ") ", label_prefix, icon_html, clickable_html, "\n")
			}
			
			sources_text <- paste0(sources_text, line)
		  }
		  
		  ai_content <- paste0(ai_content, sources_text)
		  cat("[SUCCESS] Kaynakça appended with", length(extracted_sources), "unique sources\n")
		}
      
      cat("========================================\n\n")
    }
    
	if (!(is.character(ai_content) && length(ai_content) > 0 && nzchar(ai_content[1]))) {
	  stop("EMPTY_RESPONSE: AI yanıtı boş veya geçersiz (content yok).")
	}

	ai_content <- strip_planner_text(ai_content)

	# --- SAĞLAMLAŞTIRMA: her zaman scalar string döndür ---
	if (!is.character(ai_content) || length(ai_content) == 0 || is.na(ai_content[1])) {
	  ai_content <- ""
	} else {
	  ai_content <- as.character(ai_content)[1]
	}
	if (!nzchar(ai_content)) ai_content <- ""

	# DEBUG: dönüş özeti
	cat("[LOCAL_LLM] returning shape=list content_nchar=", nchar(ai_content),
		" duration_s=", as.numeric(difftime(Sys.time(), llm_start_time, units = "secs")),
		"\n", sep = "")

	return(list(
	  content  = ai_content,
	  duration = as.numeric(difftime(Sys.time(), llm_start_time, units = "secs"))
	))
  }

  # Retry logic for API calls (available in main R session)
  call_llm_with_retry <- function(chat_history, settings, max_retries = 3) {
    for (i in 1:max_retries) {
      tryCatch({
        res <- call_local_llm(chat_history, settings)
		# Back-compat: if any older call expects a character, wrap it
		if (is.character(res)) {
		  res <- list(content = as.character(res)[1] %||% "", duration = NA_real_)
		}
		return(res)
      }, error = function(e) {
        if (i == max_retries) {
          stop(e)
        }
        Sys.sleep(2^i)
      })
    }
  }

# Character data
get_characters_data <- function() {
  list(
    title = "Yanıt Stili — Karakter Seçimi",
    default_style = "mergen",
    styles = list(
      list(
        id = "mergen", label = "Mergen", display_name = "MERGEN",
        avatar = "characters/avatar/Mergen_avatar_original.png",
        image = "characters/resim/Mergen_resim_original.png",
        accent = "#7C4DFF", accent_hover = "#8E66FF", accent_active = "#6A3BE6",
        selection_card_tr = "\"Zihin Yayından Çıkan Ok\" — hızlı, net, uygulanabilir",
        lore_tr = "Mergen, Türk ve Altay anlatılarında bilgeliğin ve keskin zekânın sembolüdür. Bazı kaynaklarda Kayra'nın oğlu olarak geçer. Oku ve yayı, isabetli düşünceyi ve doğru soruyu bulmayı temsil eder.",
        system_prompt_en = "Be a balanced, pragmatic assistant. First provide a 2–3 sentence executive summary, then a concise step-by-step plan, then a minimal example/output.",
        parameters = list(temperature = 0.4)
      ),
      list(
        id = "ulgen", label = "Ülgen", display_name = "ÜLGEN",
        avatar = "characters/avatar/Ulgen_avatar_original.png",
        image = "characters/resim/Ulgen_resim_original.png",
        accent = "#2F6DF6", accent_hover = "#4C80F7", accent_active = "#1E59E0",
        selection_card_tr = "\"Göğün Işığı\" — moral yükseltir, yolu aydınlatır",
        lore_tr = "Ülgen, göğün aydınlık yüzüdür; iyilik, düzen ve üretkenliğin tanrısı olarak tanınır.",
        system_prompt_en = "Act like a constructive expert: quickly frame the problem; propose 2–3 viable solution paths with trade-offs.",
        parameters = list(temperature = 0.5)
      ),
      list(
        id = "kayra", label = "Kayra", display_name = "KAYRA",
        avatar = "characters/avatar/Kayra_avatar_original.png",
        image = "characters/resim/Kayra_resim_original.png",
        accent = "#12A97B", accent_hover = "#26B790", accent_active = "#0C8C63",
        selection_card_tr = "\"Evrenin Haritacısı\" — büyük resmi kurar",
        lore_tr = "Kayra Han, bazı Sibirya ve Türk anlatılarında yaratıcı ve en yüce ilke olarak yer alır.",
        system_prompt_en = "Operate as a strategist: state objectives and guiding principles; map alternatives with trade-offs.",
        parameters = list(temperature = 0.3)
      ),
      list(
        id = "erlik", label = "Erlik", display_name = "ERLİK",
        avatar = "characters/avatar/Erlik_avatar_original.png",
        image = "characters/resim/Erlik_resim_original.png",
        accent = "#B66A2C", accent_hover = "#C27A3D", accent_active = "#8F5321",
        selection_card_tr = "\"Varsayım Avcısı\" — kör noktayı görür",
        lore_tr = "Erlik Han, yeraltı âleminin hükümdarı olarak tanınır.",
        system_prompt_en = "Be a respectful critical partner. Surface hidden assumptions; list risks and counterexamples.",
        parameters = list(temperature = 0.4)
      ),
      list(
        id = "umay", label = "Umay Ana", display_name = "UMAY ANA",
        avatar = "characters/avatar/Umay_Ana_avatar_original.png",
        image = "characters/resim/Umay_Ana_resim_original.png",
        accent = "#E98686", accent_hover = "#EE9B9B", accent_active = "#D96F6F",
        selection_card_tr = "\"Nazik Öğretici\" — yeni başlayanların korkusunu alır",
        lore_tr = "Umay Ana, Türk dünyasında bereketin ve çocukların koruyucu ruhu olarak sevilir.",
        system_prompt_en = "Be an empathetic teacher for beginners. Explain in simple language; break tasks into small numbered steps.",
        parameters = list(temperature = 0.6)
      )
    )
  )
}

# --- HIZLI DOSYA İNDEKSİ (önbellekli) ---
.FILE_INDEX_CACHE <- new.env(parent = emptyenv())
FILE_INDEX_TTL_MIN <- suppressWarnings(as.numeric(Sys.getenv("MCP_INDEX_TTL_MIN", "10")))
if (is.na(FILE_INDEX_TTL_MIN) || FILE_INDEX_TTL_MIN <= 0) FILE_INDEX_TTL_MIN <- 10

.build_basename_index <- function(base_path, pattern = "\\.(docx|doc|pdf|xlsx|xls|csv|txt|json|md|r|py|log)$", force = FALSE) {
  # not: büyük ağ klasörlerinde tekrar taramayı sınırlamak için TTL
  now <- Sys.time()
  key <- normalizePath(base_path, winslash = "/", mustWork = FALSE)
  ent <- .FILE_INDEX_CACHE[[key]]

  is_stale <- TRUE
  if (is.list(ent) && !is.null(ent$ts)) {
    age <- as.numeric(difftime(now, ent$ts, units = "mins"))
    is_stale <- isTRUE(age > FILE_INDEX_TTL_MIN)
  }

  if (force || is_stale || is.null(ent) || is.null(ent$map)) {
    if (!dir.exists(base_path)) {
      log_warn("[INDEX] Klasör yok, indeks oluşturulamadı: {base_path}")
      .FILE_INDEX_CACHE[[key]] <- list(ts = now, map = list())
      return(.FILE_INDEX_CACHE[[key]])
    }
    log_info("[INDEX] Taranıyor (TTL {FILE_INDEX_TTL_MIN}dk): {base_path}")
    # Yalnızca yaygın belge türleri
    all_files <- list.files(base_path, pattern = pattern, full.names = TRUE,
                            recursive = TRUE, include.dirs = FALSE, ignore.case = TRUE)
    # basename -> tam yol listesi (aynı ad birden fazlaysa liste tut)
    map <- split(all_files, tolower(basename(all_files)))
    .FILE_INDEX_CACHE[[key]] <- list(ts = now, map = map)
  }

  .FILE_INDEX_CACHE[[key]]
}

.search_from_index <- function(base_path, target_filename) {
  idx <- .build_basename_index(base_path)
  if (!length(idx$map)) return(NULL)
  key <- tolower(basename(target_filename))
  cand <- idx$map[[key]]
  if (is.null(cand) || !length(cand)) return(NULL)
  for (p in cand) { if (file.exists(p)) return(p) }
  NULL
}

# Yardımcı: ipucu parçalarını yol ile skorla (kaç parça geçiyor?)
.score_path_by_parts <- function(path, parts) {
  if (length(parts) == 0) return(0L)
  p <- tolower(path)
  sum(vapply(parts, function(s) grepl(tolower(trimws(s)), p, fixed = TRUE), logical(1)))
}

# 'A&&B&&C.docx' ipucu ile arama (indeksteki tüm C.docx adaylarını A/B parçalarına göre puanla)
.search_with_hint <- function(base_path, hint) {
  pr <- strsplit(hint, "&&", fixed = TRUE)[[1]]
  pr <- trimws(pr); pr <- pr[nzchar(pr)]
  if (!length(pr)) return(NULL)
  last <- tail(pr, 1)
  idx <- .build_basename_index(base_path)
  cand <- idx$map[[tolower(basename(last))]]
  if (is.null(cand) || !length(cand)) return(NULL)

  left <- if (length(pr) > 1) pr[seq_len(length(pr) - 1)] else character(0)
  if (!length(left)) {
    for (p in cand) { if (file.exists(p)) return(p) }
    return(NULL)
  }

  scores <- vapply(cand, .score_path_by_parts, integer(1), parts = left)
  ord <- order(scores, decreasing = TRUE, na.last = NA)
  for (i in ord) {
    p <- cand[[i]]
    if (file.exists(p)) return(p)
  }
  NULL
}

# Akıllı arama: önce TAM ipucu ile dene, sonra klasik basename
search_file_in_folder <- function(base_path, target_filename) {
  log_info("[FILE SEARCH] base='{base_path}', target='{target_filename}'")
  if (!dir.exists(base_path)) {
    log_error("[FILE SEARCH] taban klasör yok: '{base_path}'")
    return(NULL)
  }
  # 1) '&&' ipucu varsa onu kullan (indeks içi aday daraltma + puanlama)
  if (is.character(target_filename) && grepl("&&", target_filename, fixed = TRUE)) {
    hit_hint <- .search_with_hint(base_path, target_filename)
    if (!is.null(hit_hint)) {
      log_info("[FILE SEARCH] ipucu ile bulundu: {hit_hint}")
      return(hit_hint)
    }
  }
  # 2) Sade basename araması
  hit <- .search_from_index(base_path, target_filename)
  if (!is.null(hit)) {
    log_info("[FILE SEARCH] indeks eşleşmesi: {hit}")
    return(hit)
  }
  log_warn("[FILE SEARCH] eşleşme yok: target='{target_filename}'")
  NULL
}
# global.R

# Force UTF-8 encoding globally
options(encoding = "UTF-8")
options(future.rng.onMisuse = "ignore")
try(suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8")), silent = TRUE)

# Limit suppression to only this locale call
try(suppressWarnings(Sys.setlocale("LC_CTYPE", "Turkish_Turkey.UTF-8")), silent = TRUE)

# ------------------------------------------------------------------------------
# VERİTABANI HEDEF TANIMLARI (DATABASE TARGET CONSTANTS)
# ------------------------------------------------------------------------------
# Uygulama genelinde hangi veritabanına gidileceğini belirten standart etiketler.
# 'library_queries.R' içindeki sorgularda bu etiketleri kullanacağız.
DB_TARGETS <- list(
  PRIMARY   = "primary",   # Ana veritabanı (Varsayılan) -> .Renviron: DB_DSN
  SECONDARY = "secondary", # İkincil veritabanı          -> .Renviron: DB_DSN_2
  TERTIARY  = "tertiary"   # Üçüncül veritabanı          -> .Renviron: DB_DSN_3
)

# Yorumlu yanıtlara izin ver (LLM'in ikinci yazım geçişi açık kalsın)
options(mergen.ai.strict_data_only = FALSE)

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

library(arrow)
library(base64enc)
library(cellranger)
library(cli)
library(commonmark)
library(curl)
library(data.table)
library(DBI)
library(dplyr)
library(DT)
library(duckdb)
library(fastmatch)
library(future)
library(glue)
library(htmltools)
library(httr)
library(jsonlite)
library(later)
library(lubridate)
library(markdown)
library(odbc)
library(openssl)
library(pdftools)
library(pool)
library(promises)
library(purrr)
library(readr)
library(readxl)
library(shiny)
library(shinyBS)
library(shinycssloaders)
library(shinydashboard)
library(shinyjs)
library(shinyWidgets)
library(stringdist)
library(stringi)
library(stringr)
library(tibble)
library(tidyr)
library(urltools)
library(writexl)
library(xml2)
library(av)

# Normalize Windows paths (turn unicode-heavy paths into short 8.3 variants)
safe_windows_short_path <- function(path, must_exist = FALSE) {
  if (.Platform$OS.type != "windows") {
    return(path)
  }

  if (is.null(path) || length(path) == 0) {
    return(path)
  }

  candidate <- as.character(path[1])
  if (is.na(candidate) || !nzchar(candidate)) {
    return(candidate)
  }

  candidate_fs <- gsub("/", "\\\\", candidate, fixed = TRUE)
  if (isTRUE(must_exist) && !file.exists(candidate_fs)) {
    return(candidate)
  }

  short_raw <- tryCatch(utils::shortPathName(candidate_fs), error = function(e) candidate_fs)
  if (!nzchar(short_raw)) {
    short_raw <- candidate_fs
  }

  gsub("\\\\", "/", short_raw, fixed = TRUE)
}

# Helper: keep UTF-8 path strings intact while normalizing separators
normalize_utf8_path <- function(path, mustWork = FALSE) {
  if (is.null(path) || length(path) == 0) {
    return(path)
  }

  candidate <- as.character(path[1])
  if (is.na(candidate) || !nzchar(candidate)) {
    return(candidate)
  }

  normalized <- tryCatch(
    normalizePath(candidate, winslash = "/", mustWork = mustWork),
    error = function(e) candidate
  )
  
  # Windows'ta özel karakter içeren yollar için kısa (8.3) formu tercih et
  normalized <- safe_windows_short_path(normalized, must_exist = FALSE)

  enc2utf8(normalized)
}

# Guard against misconfigured base directories (e.g., relative paths that already
# include the working directory but miss a leading slash). If we detect a
# working-directory prefix without a leading separator, force it to be treated
# as an absolute path and fall back to the default when resolution fails.
sanitize_base_dir <- function(path_candidate, fallback_dir) {
  raw <- as.character(path_candidate %||% "")
  if (!nzchar(raw)) return(fallback_dir)

  # If the path is not absolute but starts with the current working directory
  # (minus leading slash), prepend '/' so normalizePath does not duplicate it.
  is_absolute <- grepl("^[A-Za-z]:|^/", raw)
  if (!is_absolute) {
    wd_no_slash <- sub("^/+", "", getwd())
    if (startsWith(raw, wd_no_slash)) {
      raw <- paste0("/", raw)
    }
  }

  normalized <- normalize_utf8_path(raw, mustWork = FALSE)
  if (!nzchar(normalized)) fallback_dir else normalized
}

# Preserve UNC-like network paths without forcing normalizePath (which can
# incorrectly prepend the working directory on non-Windows systems).
normalize_mcp_path <- function(path, must_exist = FALSE) {
  if (is.null(path) || length(path) == 0) return("")

  candidate <- trimws(as.character(path[1] %||% ""))
  if (!nzchar(candidate)) return("")

  # Normalize slash style up-front
  candidate <- gsub("\\\\", "/", candidate, fixed = TRUE)

  # Collapse accidental duplicated server/share prefixes that show up as
  #   /rehisds/uygulamalar/rehisds/uygulamalar/Primavera/...
  dedupe_leading_pair <- function(p) {
    parts <- strsplit(sub("^/+", "", p), "/", fixed = TRUE)[[1]]
    if (length(parts) >= 4 && identical(parts[1:2], parts[3:4])) {
      paste(c("", "", parts[1:2], parts[-(1:4)]), collapse = "/")
    } else {
      p
    }
  }

  candidate <- dedupe_leading_pair(candidate)

  # UNC prefix (\\server/share or //server/share) should be preserved exactly
  if (grepl("^\\\\", candidate) || grepl("^//", candidate)) {
    cleaned <- gsub("/{3,}", "//", candidate)
    return(enc2utf8(cleaned))
  }

  # Paths like "/server/share/..." coming from Windows UNC drops should be
  # treated as UNC (do NOT let normalizePath prepend the working directory).
  maybe_unc <- grepl("^/[^/]+/[^/]+", candidate)
  if (maybe_unc) {
    cleaned <- paste0("//", sub("^/+", "", candidate))
    cleaned <- dedupe_leading_pair(cleaned)
    return(enc2utf8(cleaned))
  }

  normalize_utf8_path(candidate, mustWork = must_exist)
}

resolve_mcp_base_dir <- function() {
  raw <- Sys.getenv("MCP_FILES_BASE", MERGEN_UPLOADS_DIR)
  base <- normalize_mcp_path(raw, must_exist = FALSE)

  created <- tryCatch({
    fs::dir_create(base, recurse = TRUE)
    TRUE
  }, error = function(e) FALSE)

  if (!isTRUE(created) || !dir.exists(base)) {
    base <- MERGEN_UPLOADS_DIR
    fs::dir_create(base, recurse = TRUE)
  }

  normalize_mcp_path(base, must_exist = dir.exists(base))
}

# ==============================================================================
# SQL DOSYALARINI ÖN YÜKLEME VE BOM TEMİZLİĞİ (PRE-LOADER)
# ==============================================================================
# library_queries.R dosyasının yüklü olduğundan emin olalım
if (!exists("query_library")) {
  source("R/library_queries.R")
}

cat("\n[GLOBAL] --- SQL Dosyalari Yukleniyor ---\n")

# Listeyi dolaş ve dosyadan okuma yap
for (i in seq_along(query_library)) {
  q_item <- query_library[[i]]
  
  if (!is.null(q_item$sql_file) && (is.null(q_item$sql) || !nzchar(q_item$sql))) {
    
    fpath <- q_item$sql_file
    fpath_abs <- tryCatch(normalizePath(fpath, winslash = "/", mustWork = FALSE), error = function(e) fpath)
    
    file_found <- FALSE
    path_to_use <- NULL
    
    if (file.exists(fpath)) {
      file_found <- TRUE
      path_to_use <- fpath
    } else if (file.exists(fpath_abs)) {
      file_found <- TRUE
      path_to_use <- fpath_abs
    }
    
    if (file_found) {
      lines <- readLines(path_to_use, warn = FALSE, encoding = "UTF-8")
      full_sql <- paste(lines, collapse = "\n")
      
      full_sql <- gsub("^\ufeff", "", full_sql)
      
      query_library[[i]]$sql <- full_sql
      
      cat(sprintf("[GLOBAL] OK: %s (%s) -> Yuklendi ve BOM temizlendi (%d karakter).\n", 
                  q_item$id, q_item$sql_file, nchar(full_sql)))
      
    } else {
      cat(sprintf("[GLOBAL] HATA: SQL dosyasi bulunamadi! ID: %s, Yol: %s\n", 
                  q_item$id, q_item$sql_file))
      cat(sprintf("[GLOBAL] Calisma dizini: %s\n", getwd()))
      cat(sprintf("[GLOBAL] Denenen yollar: '%s', '%s'\n", fpath, fpath_abs))
    }
  }
}
cat("[GLOBAL] --- SQL Yukleme Tamamlandi ---\n\n")

# Ortamda AES-GCM var mı? Eski openssl sürümlerinde bu fonksiyon yoktur.
HAVE_AES_GCM <- isTRUE("aes_gcm_encrypt" %in% getNamespaceExports("openssl"))

# --- OPTIONAL VIS LIBS (do-not-fail if missing) ---
have_highcharter <- requireNamespace("highcharter", quietly = TRUE)
have_plotly_gg   <- (requireNamespace("plotly", quietly = TRUE) && requireNamespace("ggplot2", quietly = TRUE))

# ===== Shared file store (same for main + workers) =====
MERGEN_FILES_ROOT <- tools::R_user_dir("mergen", which = "data")
dir.create(MERGEN_FILES_ROOT, showWarnings = FALSE, recursive = TRUE)
MERGEN_FILES_ROOT <- normalize_utf8_path(MERGEN_FILES_ROOT, mustWork = dir.exists(MERGEN_FILES_ROOT))

# Always-persisted uploads base: ./mergen_uploads  (override with MCP_FILES_BASE if set)
MERGEN_UPLOADS_DIR <- file.path(getwd(), "mergen_uploads")
dir.create(MERGEN_UPLOADS_DIR, showWarnings = FALSE, recursive = TRUE)
MERGEN_UPLOADS_DIR <- normalize_utf8_path(MERGEN_UPLOADS_DIR, mustWork = dir.exists(MERGEN_UPLOADS_DIR))

# Base dir for persisted uploads (defaults to mergen_uploads/, can be overridden by MCP_FILES_BASE)
MERGEN_MCP_BASE_DIR <- resolve_mcp_base_dir()

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
  base_dir <- if (isTRUE(persist_under_mcp_base)) resolve_mcp_base_dir() else MERGEN_FILES_ROOT
  user_folder <- if (!is.null(user_id)) file.path(base_dir, paste0("user_", as.character(user_id))) else base_dir
  fs::dir_create(user_folder, recurse = TRUE)

  src_norm  <- normalize_mcp_path(src_path, must_exist = FALSE)
  base_norm <- normalize_mcp_path(base_dir, must_exist = dir.exists(base_dir))

  normalize_for_compare <- function(p) {
    if (is.null(p)) return("")
    val <- tolower(as.character(p))
    val <- gsub("\\\\", "/", val, fixed = TRUE)
    val <- sub("^//\\?/", "", val, perl = TRUE)
    val <- sub("^//(?=[A-Za-z]:)", "", val, perl = TRUE)
    val <- gsub("(?<!:)//+", "/", val, perl = TRUE)
    trimws(val)
  }

  src_cmp  <- normalize_for_compare(src_norm)
  base_cmp <- normalize_for_compare(base_norm)
  
  # If the source already lives under the chosen base, don't copy — just index it
  if (nzchar(base_cmp) && (identical(src_cmp, base_cmp) || startsWith(src_cmp, paste0(base_cmp, "/")))) {
    dest_norm <- src_norm
  } else {
    unique_name <- paste0(format(Sys.time(), "%Y%m%d%H%M%S"), "_", sprintf("%04d", sample(0:9999, 1)), "_", basename(as_name))
    dest <- file.path(user_folder, unique_name)
    copy_ok <- tryCatch({
      fs::file_copy(src_path, dest, overwrite = TRUE)
      TRUE
    }, error = function(e) {
      message(sprintf("[UPLOAD] copy failed: %s", e$message))
      FALSE
    })

    if (!isTRUE(copy_ok) || !fs::file_exists(dest)) {
      stop(sprintf("Dosya kopyalanamadı: %s -> %s", src_path, dest))
    }

    dest_norm <- normalize_mcp_path(dest, must_exist = TRUE)
  }
  
  dest_norm <- safe_windows_short_path(dest_norm, must_exist = TRUE)

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

  if (path_exists_relaxed(requested[1])) {
    p <- tryCatch(normalize_mcp_path(requested[1], must_exist = TRUE),
                 error = function(e) normalizePath(requested[1], winslash = "/", mustWork = TRUE))
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
          if (!is.null(ent_path) && path_exists_relaxed(ent_path) && identical(ent_disp, full_key)) {
            p <- normalize_mcp_path(ent_path, must_exist = FALSE)
            log_info("resolve_uploaded_file(): kullanıcı kovasında TAM adla bulundu -> {p}")
            return(p)
          }
        }
      }

      # Sonra basename anahtarı
      hit <- bucket[[key]]
      if (is.list(hit) && !is.null(hit$path)) hit <- hit$path  # yeni yapı
      if (!is.null(hit) && path_exists_relaxed(hit)) {
        p <- normalize_mcp_path(hit, must_exist = FALSE)
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
          if (!is.null(ent_path) && path_exists_relaxed(ent_path) && identical(ent_disp, full_key)) {
            p <- normalize_mcp_path(ent_path, must_exist = FALSE)
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
  if (!is.null(hit) && path_exists_relaxed(hit)) {
    p <- normalize_mcp_path(hit, must_exist = FALSE)
    log_info("resolve_uploaded_file(): legacy haritada (basename) bulundu -> {p}")
    return(p)
  }

  if (length(idx)) {
    for (bucket_name in names(idx)) {
      bucket <- idx[[bucket_name]]
      if (is.list(bucket)) {
        hit <- bucket[[key]]
        if (is.list(hit) && !is.null(hit$path)) hit <- hit$path
        if (!is.null(hit) && path_exists_relaxed(hit)) {
          p <- normalize_mcp_path(hit, must_exist = FALSE)
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
  base <- resolve_mcp_base_dir()
  p <- file.path(base, sprintf("user_%s", as.character(user_id)))
  created <- tryCatch({
    fs::dir_create(p, recurse = TRUE)
    TRUE
  }, error = function(e) {
    log_warn("[INDEX] Kullanıcı klasörü oluşturulamadı ({conditionMessage(e)}); varsayılan dizine düşülüyor")
    FALSE
  })

  if (!isTRUE(created) || !dir.exists(p)) {
    fallback <- file.path(MERGEN_UPLOADS_DIR, sprintf("user_%s", as.character(user_id)))
    fs::dir_create(fallback, recurse = TRUE)
    return(normalize_mcp_path(fallback, must_exist = dir.exists(fallback)))
  }
  
  normalize_mcp_path(p, must_exist = dir.exists(p))
}

mergen_list_user_files <- function(user_id, prune_missing = TRUE) {
  idx <- .load_index()
  uid <- as.character(user_id)
  bucket <- idx[[uid]]
  
  drop_stale_entries <- function(keys_to_remove) {
    if (!length(keys_to_remove)) return(invisible(FALSE))
    idx_local <- .load_index()
    if (is.null(idx_local[[uid]])) return(invisible(FALSE))
    for (key in unique(keys_to_remove)) {
      idx_local[[uid]][[key]] <- NULL
    }
    if (is.list(idx_local[[uid]]) && !length(idx_local[[uid]])) {
      idx_local[[uid]] <- NULL
    }
    .save_index(idx_local)
    TRUE
  }

  if (!is.null(bucket) && length(bucket) > 0) {
    entries <- lapply(names(bucket), function(key) {
      val <- bucket[[key]]
      list(
        key = key,
        path = normalize_utf8_path(if (is.list(val) && !is.null(val$path)) val$path else as.character(val), mustWork = FALSE),
        name = {
          disp <- if (is.list(val) && !is.null(val$display)) val$display else NA_character_
          disp <- disp %||% NA_character_
          if (!is.na(disp) && nzchar(disp)) disp else key
        }
      )
    })

    df <- do.call(rbind, lapply(entries, function(rec) {
      data.frame(key = rec$key, path = rec$path, name = rec$name, stringsAsFactors = FALSE)
    }))

    rehydrated <- list()
    exists_vec <- vapply(seq_len(nrow(df)), function(i) {
      p <- df$path[i]
      exists_now <- path_exists_relaxed(p)

      if (!exists_now) {
        alt <- tryCatch({
          candidate <- file.path(mergen_user_upload_dir(user_id), basename(p %||% df$name[i]))
          normalize_mcp_path(candidate, must_exist = dir.exists(dirname(candidate)))
        }, error = function(e) NULL)

        if (!is.null(alt) && path_exists_relaxed(alt)) {
          df$path[i] <<- alt
          rehydrated[[df$key[i]]] <<- alt
          exists_now <- TRUE
          log_info("[INDEX] {df$name[i]} yolu yeniden oluşturuldu -> {alt}")
        }
      }

      exists_now
    }, logical(1))

    if (length(rehydrated)) {
      idx_local <- .load_index()
      if (!is.null(idx_local[[uid]])) {
        for (k in names(rehydrated)) {
          if (is.list(idx_local[[uid]][[k]])) {
            idx_local[[uid]][[k]]$path <- rehydrated[[k]]
          } else if (!is.null(idx_local[[uid]][[k]])) {
            idx_local[[uid]][[k]] <- rehydrated[[k]]
          }
        }
        .save_index(idx_local)
      }
    }

    if (prune_missing && any(!exists_vec)) {
      missing_keys <- unique(df$key[!exists_vec])
      missing_names <- unique(df$name[!exists_vec])
      log_warn("[INDEX] {length(missing_keys)} kayıt bulunamadı (user={uid}): {paste(missing_names, collapse = ', ')} — indeks temizleniyor")
      drop_stale_entries(missing_keys)
    }

    df <- df[exists_vec, , drop = FALSE]
    if (nrow(df) > 0) {
      out <- data.frame(
        path = df$path,
        name = df$name,
        stringsAsFactors = FALSE
      )
      attr(out, "source") <- "index"
      attr(out, "count") <- nrow(out)
      log_info("[INDEX] user={uid} için {nrow(out)} dosya bulundu (kaynak: index)")
      return(out)
    }
  }

  # Fallback: plain folder listing (pre-index or very old data)
  dir <- mergen_user_upload_dir(user_id)
  if (!dir.exists(dir)) {
    log_info("[INDEX] user={uid} için klasör bulunamadı: {dir}")
    return(data.frame(path = character(), name = character(), stringsAsFactors = FALSE))
  }
  
  paths <- list.files(dir, full.names = TRUE, recursive = FALSE, include.dirs = FALSE)
  if (!length(paths)) {
    log_info("[INDEX] user={uid} klasörü boş: {dir}")
    return(data.frame(path = character(), name = character(), stringsAsFactors = FALSE))
  }

  out <- data.frame(
    path = vapply(paths, normalize_utf8_path, character(1), mustWork = FALSE),
    name = basename(paths),
    stringsAsFactors = FALSE
  )
  attr(out, "source") <- "filesystem"
  attr(out, "count") <- nrow(out)
  log_info("[INDEX] user={uid} için {nrow(out)} dosya bulundu (kaynak: filesystem)")
  out
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
# Environment kullanarak daha verimli bellek yönetimi
global_rate_limiter <- new.env(parent = emptyenv())
global_rate_limiter$max_total_requests <- 100  # Total requests per minute across all users
global_rate_limiter$window_size <- 60
global_rate_limiter$max_buffer_size <- 200  # Bellek taşmasını önlemek için maksimum buffer boyutu
global_rate_limiter$requests <- list()
global_rate_limiter$last_cleanup <- Sys.time()

check_global_rate_limit <- function() {
  current_time <- Sys.time()
  
  # Eski istekleri temizle
  global_rate_limiter$requests <- Filter(function(t) {
    difftime(current_time, t, units = "secs") < global_rate_limiter$window_size
  }, global_rate_limiter$requests)
  
  # Bellek taşması koruması: buffer çok büyükse agresif temizlik yap
  if (length(global_rate_limiter$requests) > global_rate_limiter$max_buffer_size) {
    # Sadece son window_size/2 saniyelik istekleri tut
    half_window <- global_rate_limiter$window_size / 2
    global_rate_limiter$requests <- Filter(function(t) {
      difftime(current_time, t, units = "secs") < half_window
    }, global_rate_limiter$requests)
  }
  
  # Global limit aşıldı mı kontrol et
  if (length(global_rate_limiter$requests) >= global_rate_limiter$max_total_requests) {
    return(list(allowed = FALSE, message = "Sistem yoğunluğu nedeniyle geçici olarak hizmet verilemiyor. Lütfen birkaç saniye sonra tekrar deneyin."))
  }
  
  # Mevcut isteği ekle
  global_rate_limiter$requests <- c(global_rate_limiter$requests, list(current_time))
  
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
normalize_excel_path <- function(path) {
  if (is.null(path) || !nzchar(path)) return(path)

  if (exists("normalize_mcp_path", envir = globalenv(), inherits = TRUE)) {
    try_norm <- try(get("normalize_mcp_path", envir = globalenv(), inherits = TRUE)(path, must_exist = FALSE), silent = TRUE)
    if (!inherits(try_norm, "try-error") && !is.null(try_norm) && nzchar(try_norm)) {
      path <- try_norm
    }
  }

  p_fixed <- gsub("\\\\", "/", path)

  dedupe_leading_repeat <- function(p) {
    if (!nzchar(p)) return(p)
    slashes <- sub("^(/*).*", "\\1", p)
    parts <- strsplit(sub("^/+", "", p), "/", fixed = TRUE)[[1]]
    if (length(parts) < 4) return(p)
    if (identical(parts[1:2], parts[3:4])) {
      rebuilt <- paste(c(slashes, parts[1:2], parts[-(1:4)]), collapse = "/")
      return(gsub("/{2,}", "/", rebuilt))
    }
    p
  }

  p_fixed <- dedupe_leading_repeat(p_fixed)

  if (.Platform$OS.type != "windows") {
    p_fixed <- tryCatch(enc2utf8(p_fixed), error = function(e) p_fixed)
  }

  if (grepl("^/[^/]", p_fixed)) {
    p_fixed <- paste0("/", p_fixed)
  }

  if (grepl("^//", p_fixed)) {
    return(gsub("/{3,}", "//", p_fixed))
  }

  path_exists_check <- function(p) {
    if (is.null(p) || !nzchar(p)) return(FALSE)
    tryCatch({
      if (file.exists(p)) return(TRUE)
      if (requireNamespace("fs", quietly = TRUE) && fs::file_exists(p)) return(TRUE)
      FALSE
    }, error = function(e) FALSE)
  }
  
  if (.Platform$OS.type == "windows") {
    candidates <- unique(c(p_fixed, tryCatch(enc2utf8(p_fixed), error = function(e) NULL)))

    for (cand in candidates) {
      if (!is.null(cand) && path_exists_check(cand)) {
        return(cand)
      }
    }
  } else {
    if (path_exists_check(p_fixed)) return(enc2utf8(p_fixed))
  }

  normalized <- tryCatch(normalizePath(p_fixed, winslash = "/", mustWork = FALSE), error = function(e) p_fixed)
  dedupe_leading_repeat(normalized)
}

safe_read_excel_table <- function(path, sheet = 1, n_max = Inf, min_header_cols = 2) {
  path_prepared <- normalize_excel_path(path)

  if (!file.exists(path_prepared) && !fs::file_exists(path_prepared)) {
    if (file.exists(path)) path_prepared <- path
    else stop(sprintf("Dosya bulunamadı (Path: %s)", path_prepared))
  }

  # [FIX] Helper to choose correct reader (xlsx vs xls) based on signature
  # This solves the issue where Windows ShortPaths (e.g. DATA~1.XLS) have .XLS extension
  # but contain XML (.xlsx) data, which confuses the default read_excel().
  pick_reader <- function(p) {
    fmt <- tryCatch(readxl::excel_format(p), error = function(e) NULL)
    if (is.null(fmt)) {
      # Fallback to extension if signature detection fails
      ext <- tolower(tools::file_ext(p))
      if (ext %in% c("xlsx", "xlsm")) return(readxl::read_xlsx)
      return(readxl::read_xls)
    }
    if (fmt %in% c("xlsx", "xlsm")) return(readxl::read_xlsx)
    return(readxl::read_xls)
  }

  # 1. Initial Raw Read (to detect headers)
  raw <- tryCatch({
    reader <- pick_reader(path_prepared)
    reader(path_prepared, sheet = sheet, col_names = FALSE, .name_repair = "minimal")
  }, error = function(e) {
    # [FIX] Libxls mismatch recovery (e.g. ShortPath .XLS pointing to .xlsx content)
    if (grepl("libxls error", conditionMessage(e), ignore.case = TRUE)) {
      return(readxl::read_xlsx(path_prepared, sheet = sheet, col_names = FALSE, .name_repair = "minimal"))
    }

    # Windows ShortPath fallback
    if (.Platform$OS.type == "windows") {
      short_p <- tryCatch(utils::shortPathName(gsub("/", "\\\\", path_prepared)), error = function(x) NULL)
      if (!is.null(short_p) && nzchar(short_p)) {
        reader_s <- pick_reader(short_p)
        return(reader_s(short_p, sheet = sheet, col_names = FALSE, .name_repair = "minimal"))
      }
    }
    # UTF-8 fallback
    if (grepl("unable to translate", conditionMessage(e), fixed = TRUE)) {
      utf8_path <- tryCatch(enc2utf8(path_prepared), error = function(x) path_prepared)
      if (!identical(utf8_path, path_prepared) && file.exists(utf8_path)) {
        reader_u <- pick_reader(utf8_path)
        return(reader_u(utf8_path, sheet = sheet, col_names = FALSE, .name_repair = "minimal"))
      }
    }
    stop(e)
  })

  if (nrow(raw) == 0 || ncol(raw) == 0) return(data.frame())

  # 2. Detect Header Row
  non_empty <- as.data.frame(lapply(raw, function(x) !(is.na(x) | (is.character(x) & trimws(x) == ""))))
  row_score <- rowSums(data.matrix(non_empty), na.rm = TRUE)

  header_row <- NA_integer_
  for (r in seq_len(nrow(raw))) {
    if (row_score[r] >= min_header_cols) {
      if (r < nrow(raw) && row_score[r + 1] >= min_header_cols) { header_row <- r; break }
      if (is.na(header_row)) header_row <- r
    }
  }
  if (is.na(header_row)) header_row <- 1L

  lookahead_rows <- seq(header_row, min(header_row + 10, nrow(raw)))
  col_score <- colSums(data.matrix(non_empty[lookahead_rows, , drop = FALSE]), na.rm = TRUE)
  if (all(col_score == 0)) return(data.frame())
  col_min <- which(col_score > 0)[1]
  col_max <- tail(which(col_score > 0), 1)

  in_block <- rowSums(data.matrix(non_empty[, col_min:col_max, drop = FALSE]), na.rm = TRUE)
  row_max <- tail(which(in_block > 0), 1)
  if (is.na(row_max)) row_max <- nrow(raw)

  rng <- cellranger::cell_limits(ul = c(header_row, col_min), lr = c(row_max, col_max))

  # 3. Final Read
  df <- tryCatch({
    reader_final <- pick_reader(path_prepared)
    reader_final(
      path_prepared,
      sheet = sheet,
      range = rng,
      col_names = TRUE,
      n_max = if (is.finite(n_max)) n_max else NULL
    )
  }, error = function(e) {
    # [FIX] Libxls mismatch recovery (e.g. ShortPath .XLS pointing to .xlsx content)
    if (grepl("libxls error", conditionMessage(e), ignore.case = TRUE)) {
      return(readxl::read_xlsx(
        path_prepared, 
        sheet = sheet, 
        range = rng, 
        col_names = TRUE, 
        n_max = if (is.finite(n_max)) n_max else NULL
      ))
    }

    # Retry with ShortPath for final read if needed
    if (.Platform$OS.type == "windows") {
      short_p <- tryCatch(utils::shortPathName(gsub("/", "\\\\", path_prepared)), error = function(x) NULL)
      if (!is.null(short_p) && nzchar(short_p)) {
        reader_final_s <- pick_reader(short_p)
        return(reader_final_s(
          short_p,
          sheet = sheet,
          range = rng,
          col_names = TRUE,
          n_max = if (is.finite(n_max)) n_max else NULL
        ))
      }
    }
    stop(e)
  })

  if (anyNA(names(df)) || any(names(df) == "")) {
    names(df) <- paste0("X", seq_along(df))
  }
  names(df) <- make.names(names(df), unique = TRUE, allow_ = TRUE)

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
source("R/helpers_summarization_prompts.R", encoding = "UTF-8")
source("R/helpers_followup_questions.R", encoding = "UTF-8")
source("R/library_queries.R", encoding = "UTF-8")
source("R/module_summarization.R", encoding = "UTF-8")
source("R/module_proje_kaynak_analizi.R", encoding = "UTF-8")
source("R/module_chat_history.R", encoding ="UTF-8")
source("R/module_file_manager.R", encoding ="UTF-8")
source("R/module_saved_chats.R", encoding ="UTF-8")
source("R/module_settings.R", encoding ="UTF-8")
source("R/module_character_video.R", encoding ="UTF-8")
source("R/module_performance.R", encoding ="UTF-8")
source("R/module_ai_processing.R", encoding ="UTF-8")
source("R/module_tts.R", encoding ="UTF-8")
source("R/module_stt.R", encoding = "UTF-8")
source("R/module_session_timeout.R", encoding = "UTF-8")
source("R/module_file_preview.R", encoding = "UTF-8")
source("R/module_api_key.R", encoding = "UTF-8")
source("R/module_message_search.R", encoding = "UTF-8")
source("R/module_followup_questions.R", encoding = "UTF-8")
source("R/module_chat_actions.R",  encoding = "UTF-8")
source("R/module_chat_export.R",   encoding = "UTF-8")
source("R/module_admin_analytics.R", encoding = "UTF-8")
source("R/module_feedback.R", encoding = "UTF-8")
source("R/module_quick_actions.R", encoding = "UTF-8")
source("R/module_image_generation.R", encoding = "UTF-8")
source("R/server_observers_settings.R", encoding = "UTF-8")
source("R/server_observers_storage.R", encoding = "UTF-8")
source("R/server_outputs_chat.R", encoding = "UTF-8")
source("R/server_observers_files.R", encoding = "UTF-8")
source("R/server_observers_saved_chats.R", encoding = "UTF-8")
source("R/server_observers_chat_ui.R", encoding = "UTF-8")
source("R/server_observers_navigation.R", encoding = "UTF-8")
source("R/server_observers_file_clicks.R", encoding = "UTF-8")
source("R/server_observers_startup.R", encoding = "UTF-8")
source("R/server_observers_chat_input.R", encoding = "UTF-8")
source("R/server_observers_misc.R", encoding = "UTF-8")
source("R/server_outputs_downloads.R", encoding = "UTF-8")
source("R/server_tts_handlers.R", encoding = "UTF-8")
source("R/server_music_handlers.R", encoding = "UTF-8")
source("R/server_welcome_handlers.R", encoding = "UTF-8")
source("R/server_llm_response_handlers.R", encoding = "UTF-8")
source("R/server_send_message.R", encoding = "UTF-8")

# --- GLOBAL CONFIGURATION ---

# Word preview mode: "html" (client-side via mammoth.js) or "pdf" (server-side convert via LibreOffice)
options(mergen.word_preview_mode = "html")

primary_llm_endpoint   <- Sys.getenv("LOCAL_LLM_ENDPOINT", "")
secondary_llm_endpoint <- Sys.getenv("LOCAL_LLM_ENDPOINT_ALT", primary_llm_endpoint)
secondary_llm_api_key  <- Sys.getenv("LOCAL_LLM_ENDPOINT_ALT_API_KEY", "")

options(mergen.filter_model = Sys.getenv("FILTER_MODEL", "mergen-local-model"))

api_config <- list(
  # Backwards compatibility: keep the legacy single-endpoint field
  local_llm_endpoint = primary_llm_endpoint,
  # Multiple endpoint support (reference by key in model map below)
  local_llm_endpoints = list(
    primary   = primary_llm_endpoint,
    secondary = secondary_llm_endpoint
  ),
  local_llm_endpoint_keys = list(
    primary   = NULL,
    secondary = secondary_llm_api_key
  ),
  local_llm_endpoint_user_managed = c(
    primary   = TRUE,
    secondary = FALSE
  ),
  local_llm_default_endpoint_key = "primary",
  # Dropdown labels  -> technical ids (unchanged)
  local_models = c(
    "Dropdown display model 1" = "technical name 1",
    "Dropdown display model 2" = "technical name 2",
    "Dropdown display model 3" = "technical name 3",
    "Dropdown display model 4" = "technical name 4",
	"Dropdown display model 5" = "technical name 5",
    "Dropdown display model 6" = "technical name 6"
  ),
  # Model açıklamaları (tooltip'ler için)
  local_model_descriptions = list(
    "technical name 1" = "Genel amaçlı, dengeli performans",
    "technical name 2" = "Hızlı yanıt, günlük kullanım",
    "technical name 3" = "Gelişmiş akıl yürütme",
    "technical name 4" = "Yüksek hassasiyet, detaylı analiz",
    "technical name 5" = "İkincil endpoint modeli",
    "technical name 6" = "Özel görevler için optimize"
  ),
  # Map each technical id to an endpoint key (or direct URL if preferred)
  local_model_endpoint_map = c(
    "technical name 1" = "primary",
    "technical name 2" = "primary",
    "technical name 3" = "primary",
    "technical name 4" = "primary",
    "technical name 5" = "secondary",
    "technical name 6" = "secondary"
  ),
  # technical ids -> base folders (use ONLY the technical ids here)
  local_model_paths = list(
    "technical name 1" = "\\\\main folder\\secondary folder\\repository\\top folder",
    "technical name 2" = "\\\\main folder\\secondary folder\\repository\\top folder2"
    # "technical name 3" = ""
  )
)

# Text-to-speech configuration (OpenAI-compatible audio endpoint)
tts_config <- list(
  base_url = Sys.getenv("LOCAL_TTS_ENDPOINT", ""),
  api_key = Sys.getenv("LOCAL_TTS_API_KEY", ""),
  model = Sys.getenv("LOCAL_TTS_MODEL", "tts-1-hd"),
  default_voice = Sys.getenv("LOCAL_TTS_VOICE", "tr-male-1"),
  timeout_seconds = as.numeric(Sys.getenv("LOCAL_TTS_TIMEOUT", "30")),
  verify_ssl = isTRUE(as.logical(Sys.getenv("LOCAL_TTS_VERIFY_SSL", "TRUE")))
)

# 1. FORCE LOAD .Renviron to ensure keys are available
if (file.exists(".Renviron")) {
  readRenviron(".Renviron")
}

# 2. Update the STT Configuration to be robust
stt_config <- list(
  endpoint = Sys.getenv("LOCAL_STT_ENDPOINT"),
  model    = Sys.getenv("LOCAL_STT_MODEL"),
  api_key  = Sys.getenv("AI_KEYS_MASTER", Sys.getenv("OPENAI_API_KEY", "")) 
)

# Debug Print (Check the console when app starts!)
cat("--- STT CONFIG CHECK ---\n")
cat("Endpoint:", stt_config$endpoint, "\n")
cat("API Key Length:", nchar(stt_config$api_key), "(If 0, your .Renviron is not loading!)\n")
cat("------------------------\n")

# Başlangıçta indeksleri hazırla (ilk tıklama gecikmesini azaltır)
try({
  bases <- unique(unname(api_config$local_model_paths %||% character()))
  invisible(lapply(bases, function(p) .build_basename_index(p)))
}, silent = TRUE)

# Resolve the appropriate local endpoint for a given technical model id
resolve_local_llm_endpoint <- function(model_id = NULL, config = api_config) {
  default_endpoint <- config$local_llm_endpoint %||% config$local_llm$endpoint %||% ""
  endpoints <- config$local_llm_endpoints %||% list()
  endpoint_map <- config$local_model_endpoint_map %||% character()

  pick_endpoint <- function(key) {
    if (is.null(key) || !nzchar(key)) {
      return(NULL)
    }
    from_list <- endpoints[[key]]
    if (!is.null(from_list) && nzchar(from_list)) {
      return(from_list)
    }
    if (grepl("^https?://", key, ignore.case = TRUE)) {
      return(key)
    }
    NULL
  }

  # Prefer the endpoint tied to the requested model
  if (!is.null(model_id) && nzchar(model_id)) {
    endpoint_key <- endpoint_map[[model_id]]
    chosen <- pick_endpoint(endpoint_key)
    if (!is.null(chosen) && nzchar(chosen)) {
      return(chosen)
    }
  }

  # Next try the declared default key (if any)
  default_key <- config$local_llm_default_endpoint_key %||% endpoint_map[[as.character(config$local_models[1])]] %||% names(endpoints)[1]
  chosen_default <- pick_endpoint(default_key)
  if (!is.null(chosen_default) && nzchar(chosen_default)) {
    return(chosen_default)
  }

  # Fallback: first non-empty endpoint from the list
  if (length(endpoints)) {
    for (ep in endpoints) {
      if (!is.null(ep) && nzchar(ep)) {
        return(ep)
      }
    }
  }

  default_endpoint
}

# Resolve both endpoint and any default API key for the given model
resolve_local_llm_credentials <- function(model_id = NULL, config = api_config) {
  endpoints <- config$local_llm_endpoints %||% list()
  endpoint_map <- config$local_model_endpoint_map %||% character()
  key_map <- config$local_llm_endpoint_keys %||% list()
  user_key_flags <- config$local_llm_endpoint_user_managed %||% logical()

  default_key_id <- config$local_llm_default_endpoint_key %||% names(endpoints)[1] %||% ""
  endpoint_key <- NULL

  if (!is.null(model_id) && nzchar(as.character(model_id)[1])) {
    endpoint_key <- endpoint_map[[as.character(model_id)[1]]]
  }

  if (is.null(endpoint_key) || !nzchar(endpoint_key)) {
    endpoint_key <- default_key_id
  }

  endpoint_url <- resolve_local_llm_endpoint(model_id, config)
  default_api_key <- key_map[[endpoint_key]] %||% ""

  if (is.null(default_api_key) || is.na(default_api_key)) {
    default_api_key <- ""
  }
  
  allow_user_key <- TRUE
  if (!is.null(endpoint_key) && nzchar(endpoint_key) && length(user_key_flags)) {
    allow_user_key <- isTRUE(user_key_flags[[endpoint_key]])
  }

  list(
    endpoint = endpoint_url %||% "",
    endpoint_key = endpoint_key %||% "",
    default_api_key = as.character(default_api_key)[1] %||% "",
    allow_user_key = allow_user_key
  )
}

determine_api_key_validation_target <- function(requested_model_id = NULL, config = api_config) {
  models_vector <- config$local_models %||% character()
  requested_model_id <- as.character(requested_model_id %||% models_vector[1] %||% "")

  target_creds <- resolve_local_llm_credentials(requested_model_id, config)
  target_model <- requested_model_id
  target_endpoint <- target_creds$endpoint %||% resolve_local_llm_endpoint(requested_model_id, config)
  target_key <- target_creds$endpoint_key %||% ""
  allow_user_key <- isTRUE(target_creds$allow_user_key)
  fallback_used <- FALSE

  if (!allow_user_key) {
    endpoint_map <- config$local_model_endpoint_map %||% character()
    user_flags <- config$local_llm_endpoint_user_managed %||% logical()
    managed_keys <- names(user_flags)[vapply(user_flags, isTRUE, logical(1))]

    fallback_model <- NULL
    if (length(managed_keys)) {
      for (key in managed_keys) {
        candidate_vec <- names(endpoint_map)[which(endpoint_map == key)]
        candidate_vec <- candidate_vec[!is.na(candidate_vec) & nzchar(candidate_vec)]
        if (length(candidate_vec)) {
          fallback_model <- candidate_vec[1]
          break
        }
      }
    }

    if (is.null(fallback_model) || !nzchar(fallback_model)) {
      fallback_model <- models_vector[1] %||% ""
    }

    fallback_creds <- resolve_local_llm_credentials(fallback_model, config)
    if (isTRUE(fallback_creds$allow_user_key) && nzchar(fallback_creds$endpoint %||% "")) {
      target_model <- fallback_model
      target_endpoint <- fallback_creds$endpoint
      target_key <- fallback_creds$endpoint_key %||% ""
      allow_user_key <- TRUE
      fallback_used <- !identical(target_model, requested_model_id)
    } else {
      allow_user_key <- FALSE
    }
  }

  if (!nzchar(target_endpoint)) {
    target_endpoint <- resolve_local_llm_endpoint(target_model, config)
  }

  list(
    model_id = target_model,
    endpoint = target_endpoint %||% "",
    endpoint_key = target_key %||% "",
    allow_user_key = allow_user_key,
    fallback_used = fallback_used,
    requested_model_id = requested_model_id
  )
}

# --- SERVICE DESK LINKS (configure via .Renviron) ---
SERVICE_DESK <- list(
  api_key_request_url = Sys.getenv("SERVICE_DESK_API_KEY_URL", "https://servicedesk.example.com/api-key"),
  rate_limit_url      = Sys.getenv("SERVICE_DESK_RATE_LIMIT_URL", "https://servicedesk.example.com/rate-limit")
)                    

# Static user configuration (remains the same)
user_config <- list(
  name = "Ahmet Yılmaz", 
  icon = "user-circle",
  userId = "12345",
  auth_level = "ADMIN"
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

  # 1) Model belirle
  if (is.null(model_id) || !nzchar(model_id)) {
    # İlk modelin TEKNİK ID'sini kullan (api_config$local_models bir named vector)
    model_id <- as.character(api_config$local_models[1])
  }
  
  # 2) Health endpoint varsa onu kullan
  health_url <- Sys.getenv("LLM_HEALTH_ENDPOINT", "")
  if (!nzchar(endpoint)) {
    endpoint <- resolve_local_llm_endpoint(model_id)
  }

  hdrs <- httr::add_headers(
    `Content-Type` = "application/json",
    `Authorization` = paste("Bearer", api_key)
  )
  
  # Helper: build a lightweight models URL (fast validation)
  derive_models_url <- function(ep) {
    if (!nzchar(ep)) {
      return("")
    }

    url_no_query <- sub("\\?.*$", "", ep)
    url_no_query <- sub("/+$", "", url_no_query)

    if (grepl("/v1/", url_no_query, fixed = TRUE)) {
      sub("(/v1/).*", "\\1models", url_no_query)
    } else {
      paste0(url_no_query, "/v1/models")
    }
  }

  models_url <- derive_models_url(endpoint)
  model_fail_detail <- ""

  if (nzchar(models_url)) {
    res_models <- try(
      httr::GET(models_url, hdrs, httr::accept_json(), httr::timeout(min(timeout_seconds, 4))),
      silent = TRUE
    )

    if (!inherits(res_models, "try-error")) {
      sc_models <- httr::status_code(res_models)
      if (sc_models == 200) {
        return(list(valid = TRUE, message = "Anahtar doğrulandı (model listesi)."))
      }
      if (sc_models %in% c(401, 403)) {
        return(list(valid = FALSE, message = "Anahtar reddedildi (401/403)."))
      }
      if (sc_models == 429) {
        model_fail_detail <- "Model listesi isteği hız limitine takıldı (429)."
      } else if (sc_models >= 500) {
        model_fail_detail <- paste("Model listesi isteği sunucu hatası verdi:", sc_models)
      } else {
        model_fail_detail <- paste("Model listesi isteği beklenmedik yanıt döndürdü:", sc_models)
      }
    } else {
      model_fail_detail <- "Model listesi isteğine ulaşılamadı (bağlantı/timeout)."
    }
  }

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
    temperature = 0,
    max_tokens = 1,
    top_p = 1,
    n = 1
  )

  res2 <- try(httr::POST(endpoint, hdrs, body = body, encode = "json", httr::timeout(timeout_seconds)), silent = TRUE)
  if (inherits(res2, "try-error")) {
    extra <- if (nzchar(model_fail_detail)) paste(model_fail_detail, "→ sohbet doğrulaması da başarısız oldu.") else "Doğrulama yapılamadı (bağlantı/timeout)."
    return(list(valid = NA, message = extra))
  }

  sc2 <- httr::status_code(res2)
  if (sc2 == 200)  return(list(valid = TRUE,  message = "Anahtar doğrulandı."))
  if (sc2 %in% c(401, 403)) return(list(valid = FALSE, message = "Anahtar reddedildi (401/403)."))
  if (sc2 == 429)  return(list(valid = NA,   message = "Hız limiti (429) — daha sonra deneyin."))
  if (sc2 >= 500)  return(list(valid = NA,   message = paste("Sunucu hatası:", sc2)))
  msg <- paste("Beklenmedik durum:", sc2)
  if (nzchar(model_fail_detail)) {
    msg <- paste(model_fail_detail, "→", msg)
  }
  return(list(valid = NA, message = msg))
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

# --- MCP Excel fallback helpers -------------------------------------------------
get_mcp_excel_candidates <- function(session_obj) {
  if (is.null(session_obj)) return(character())
  files <- session_obj$userData$current_session_files
  if (is.null(files) || !length(files)) return(character())
  display_names <- vapply(files, function(obj) {
    nm <- obj$name %||% obj$display %||% ""
    if (!is.character(nm) || length(nm) == 0) nm <- ""
    as.character(nm[1])
  }, character(1))
  display_names <- unique(display_names[nzchar(display_names)])
  if (!length(display_names)) {
    display_names <- unique(names(files))
    display_names <- display_names[nzchar(display_names)]
  }
  display_names
}

build_mcp_excel_summary <- function(analysis_result, display_name) {
  if (is.null(analysis_result) || !is.list(analysis_result)) return(NULL)
  satir <- analysis_result$satır_sayısı %||% analysis_result$row_count
  sutun <- analysis_result$sütun_sayısı %||% analysis_result$column_count
  cols  <- analysis_result$sütun_isimleri %||% analysis_result$columns
  nums  <- analysis_result$sayısal_sütunlar %||% analysis_result$numeric_columns

  lines <- c(
    sprintf("Dosya: %s", display_name %||% analysis_result$dosya_adı %||% "(bilinmiyor)"),
    sprintf("Toplam satır: %s", satir %||% "(bilinmiyor)"),
    sprintf("Toplam sütun: %s", sutun %||% "(bilinmiyor)")
  )

  if (length(cols)) {
    lines <- c(lines, sprintf("Sütunlar (%d): %s", length(cols), paste(cols, collapse = ", ")))
  }
  if (length(nums)) {
    lines <- c(lines, sprintf("Sayısal sütunlar: %s", paste(nums, collapse = ", ")))
  }

  paste(lines, collapse = "\n")
}

mcp_excel_tool_fallback <- function(session_obj) {
  if (!exists("helpers_mcp_tools", inherits = TRUE) ||
      !is.function(helpers_mcp_tools$analyze_uploaded_file)) {
    return(NULL)
  }
  candidates <- get_mcp_excel_candidates(session_obj)
  if (!length(candidates)) return(NULL)

  for (disp in candidates) {
    res <- try(helpers_mcp_tools$analyze_uploaded_file(disp, session_obj), silent = TRUE)
    if (!inherits(res, "try-error") && is.list(res) && is.null(res$error)) {
      text <- build_mcp_excel_summary(res, disp)
      if (!is.null(text)) {
        return(list(text = text, citation = disp))
      }
    }
  }
  NULL
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
  
	# mcp_excel seçiliyse araçları her durumda etkinleştir
    if (identical(settings$tool_family, "mcp_excel")) {
      enable_tools <- TRUE
    }
	
  cat("[LLM CALL] tool_family=", settings$tool_family %||% "NULL", " enable_tools=", enable_tools, "\n", sep="")
  
  tryCatch({
    selected_model <- settings$model_selection %||% "mergen-local-model"
    
    # NEW — resolve the OpenAI tool schema once per call
    session_obj <- settings$shiny_session %||% NULL
    registry_snapshot <- settings$mcp_registry_snapshot %||% NULL
    if (!is.null(registry_snapshot)) {
      needs_stub <- is.null(session_obj) ||
        is.null(session_obj$userData) ||
        is.null(session_obj$userData$current_session_files) ||
        length(session_obj$userData$current_session_files) == 0
      if (needs_stub && length(registry_snapshot) > 0) {
        session_stub <- session_obj
        if (is.null(session_stub) || !is.environment(session_stub)) {
          session_stub <- new.env(parent = emptyenv())
        }
        if (is.null(session_stub$userData) || !is.environment(session_stub$userData)) {
          session_stub$userData <- new.env(parent = emptyenv())
        }
        session_stub$userData$current_session_files <- registry_snapshot
        if (is.null(session_stub$userData$user_id) && !is.null(settings$current_user_id)) {
          session_stub$userData$user_id <- settings$current_user_id
        }
        session_obj <- session_stub
      }
    }
	
	tool_family <- settings$tool_family %||% if (isTRUE(settings$enable_mcp_tools)) "mcp_excel" else "none"

	base_tools <- list(tools = list())
	if (isTRUE(enable_tools) && identical(tool_family, "mcp_excel")) {
	  if (exists("helpers_mcp_tools", inherits = TRUE) &&
		  is.function(helpers_mcp_tools$get_openai_tools)) {
		base_tools <- helpers_mcp_tools$get_openai_tools(session_obj)
	  }
	}

	mcp_spec <- base_tools

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
	
	# --- Grafik niyeti algılayıcı + zorunlu yedek oluşturucu --------------------
	# Türkçe yorum: Son kullanıcı mesajında grafik isteği var mı?
	detect_chart_type_from_text <- function(text) {
	  if (!is.character(text) || length(text) == 0 || !nzchar(text[1])) return("auto")
	  txt <- tolower(text[1])
	  if (grepl("\\b(histogram|histogramı|histogramını|dağılım grafiği)\\b", txt, perl = TRUE)) return("hist")
	  if (grepl("\\b(çizgi|line|trend|zaman serisi|time series|eğilim)\\b", txt, perl = TRUE)) return("line")
	  if (grepl("\\b(bar|çubuk|sütun|column|karşılaştır)\\b", txt, perl = TRUE)) return("bar")
	  if (grepl("\\b(pie|pasta|dilim|pay)\\b", txt, perl = TRUE)) return("pie")
	  if (grepl("\\b(donut|halka)\\b", txt, perl = TRUE)) return("donut")
	  if (grepl("\\b(area|alan)\\b", txt, perl = TRUE)) return("area")
	  if (grepl("\\b(pareto)\\b", txt, perl = TRUE)) return("pareto")
	  if (grepl("\\b(scatter|saçılım|nokta|dağılım|serpilme)\\b", txt, perl = TRUE)) return("scatter")
	  "auto"
	}

	chart_intent_flag <- FALSE
		try({
		  last_user_txt <- NULL
	  if (length(chat_history) > 0) {
		for (i in seq_along(chat_history)) {
		  msg <- chat_history[[i]]
		  role_val <- tolower(as.character(msg$type %||% msg$role %||% ""))
		  if (identical(role_val, "user")) {
			last_user_txt <- as.character(msg$content %||% msg$message %||% "")  # son user içeriği
		  }
		}
	  }
	  if (is.character(last_user_txt) && length(last_user_txt) > 0 && nzchar(last_user_txt[1])) {
		chart_intent_flag <- grepl(
		  "(?i)\\b(grafik|grafikleri|grafiğini|görselleştir|gorsellestir|görselleştirme|gorsellestirme|plot|chart|chartlab|figure|graph|viz|visualize|visualise|çiz|çizelge|histogram|bar|çubuk|line|çizgi|trend|dağılım|scatter|pie|pasta|donut|pareto|area|spline|boxplot)\\b",
		  last_user_txt[1],
		  perl = TRUE
		)
	  }
	}, silent = TRUE)
	
	# Türkçe yorum: Grafiklerin toplanacağı depo (erken başlat)
	charts_to_store <- list()

	# Türkçe yorum: Fallback grafik mekanizması KALDIRILDI.
	# Model, talep edilen grafik sayısını tam olarak üretmelidir.
	# Otomatik ekleme mekanizması kaldırıldı çünkü:
	# 1) Kullanıcı 1 grafik istediğinde 3 grafik üretiliyordu
	# 2) Model yanlış eksen seçimi yapıyordu
	# 3) İstenmeyen histogram/bar/line kombinasyonları oluşuyordu
	add_fallback_chart <- function(original_text) {
	  # Türkçe yorum: Fallback devre dışı — orijinal metni olduğu gibi döndür
	  return(original_text %||% "")
	}
    
	# --- Seçilen aileye göre araç yönergesi enjekte et ---
	if (isTRUE(enable_tools)) {
	  tool_prompt <- NULL

		if (identical(tool_family, "mcp_excel") &&
			exists("helpers_mcp_tools", inherits = TRUE) &&
			is.function(helpers_mcp_tools$get_mcp_tools_prompt)) {

		  # Türkçe: Dosya şemasını çıkar ve prompt'a ekle
		  file_schema <- NULL
		  try({
			if (!is.null(session_obj) && !is.null(session_obj$userData$current_session_files)) {
			  # Session'daki ilk dosyanın şemasını al
			  files <- session_obj$userData$current_session_files
			  if (length(files) > 0) {
				first_file <- files[[1]]
				file_name <- first_file$name %||% names(files)[1]
				if (!is.null(file_name) && nzchar(file_name)) {
				  cat("[MCP_SCHEMA] Dosya şeması çıkarılıyor: ", file_name, "\n")
				  file_schema <- helpers_mcp_tools$extract_mcp_file_schema(file_name, session_obj)
				  if (!is.null(file_schema)) {
					cat("[MCP_SCHEMA] Şema başarıyla çıkarıldı (", nchar(file_schema), " karakter)\n")
				  }
				}
			  }
			}
		  }, silent = TRUE)

		  # Türkçe: Dosya şemasını prompt'a dahil et
		  tool_prompt <- paste0(
			helpers_mcp_tools$get_mcp_tools_prompt(file_schema),
			"\n\n### EK BİLGİ:",
			"\n- SQL sorguları için: sql_query_uploaded_file (tablo adı: t)",
			"\n- Dosya özeti için: analyze_uploaded_file (opsiyonel)",
			"\n"
		  )

		  # Türkçe: Tool prompt'u mesajların başına sistem mesajı olarak ekle
		  if (!is.null(tool_prompt) && nzchar(tool_prompt)) {
			cat("[MCP] Tool prompt ekleniyor (", nchar(tool_prompt), " karakter)\n", sep = "")
			tool_system_msg <- list(role = "system", content = tool_prompt)
			messages_payload <- c(list(tool_system_msg), messages_payload)
		  }
		}
	}

    temp_value <- if (!is.null(settings$temperature)) settings$temperature else 0.4

    body <- list(
      model = selected_model, 
      messages = messages_payload, 
      stream = FALSE,
      temperature = temp_value
    )

	  # YENİ — Tüm uçlar OpenAI uyumlu: araç şemasını her zaman ekle
	  if (mcp_enabled_now) {
		# Türkçe: İstisnai olarak devre dışı bırakmak isterseniz DISABLE_TOOL_SCHEMA=TRUE ayarlayın
		attach_tool_schema <- !isTRUE(as.logical(Sys.getenv("DISABLE_TOOL_SCHEMA", "FALSE")))

		cat("[TOOLS] attach_tool_schema=", attach_tool_schema, " (family=", tool_family, ")\n", sep = "")

		if (attach_tool_schema) {
		  body$tools <- mcp_spec$tools
		  body$tool_choice <- "auto"
		}
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
      timeout(300)
    )

	status <- httr::status_code(response)

	if (status != 200) {
	  resp_txt_raw <- try(httr::content(response, "text", encoding = "UTF-8"), silent = TRUE)
	  resp_txt <- if (!inherits(resp_txt_raw, "try-error") && is.character(resp_txt_raw) && length(resp_txt_raw) > 0) resp_txt_raw[[1]] else ""

	  # Türkçe: Ollama 'tools' desteklemiyorsa 400 döner — tool şeması olmadan otomatik tekrar dene
	  if (status == 400 && mcp_enabled_now && isTRUE(attach_tool_schema) &&
		  grepl("does not support tools|tool", tolower(resp_txt))) {
		cat("[RETRY] 400 & tools not supported → retrying without tool schema...\n")
		body$tools <- NULL
		body$tool_choice <- NULL
		response <- httr::POST(
		  api_endpoint,
		  do.call(httr::add_headers, hdrs),
		  body = jsonlite::toJSON(body, auto_unbox = TRUE),
		  encode = "raw",
		  timeout(300)
		)
		status <- httr::status_code(response)
		resp_txt_raw <- try(httr::content(response, "text", encoding = "UTF-8"), silent = TRUE)
		resp_txt <- if (!inherits(resp_txt_raw, "try-error") && is.character(resp_txt_raw) && length(resp_txt_raw) > 0) resp_txt_raw[[1]] else ""
	  }

	  if (status != 200) {
		msg_tail <- if (nzchar(resp_txt)) paste0(" — ", substr(resp_txt, 1, 500)) else ""
		if (status == 429)      stop("RATE_LIMIT: Çok fazla istek gönderildi.", call. = FALSE)
		else if (status %in% c(401,403)) stop("AUTH_ERROR: Kimlik doğrulama hatası.", call. = FALSE)
		else if (status >= 500) stop(sprintf("SERVER_ERROR: Sunucu hatası (Kod: %d)%s", status, msg_tail), call. = FALSE)
		else                    stop(sprintf("API_ERROR: API hatası (Kod: %d)%s", status, msg_tail), call. = FALSE)
	  }
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
		
    # Parse for tool calls if MCP enabled
    if (enable_tools) {
      tool_calls <- list()
    
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
      } else if (identical(tool_family, "mcp_excel") &&
                 exists("helpers_mcp_tools", inherits = TRUE) &&
                 is.function(helpers_mcp_tools$parse_tool_calls_from_text)) {
        tool_calls <- helpers_mcp_tools$parse_tool_calls_from_text(ai_content %||% "")
      }
	  
      if (length(tool_calls) == 0 && identical(tool_family, "mcp_excel") && recursion_depth == 0) {
        fb <- try(mcp_excel_tool_fallback(session_obj), silent = TRUE)
        if (!inherits(fb, "try-error") && is.list(fb) && !is.null(fb$text)) {
          text_out <- fb$text
          cite <- fb$citation %||% ""
          if (nzchar(cite)) {
            text_out <- paste0(text_out, "\n\nKaynakça:\n1) ", cite)
          }
          return(list(
            content = text_out,
            duration = as.numeric(difftime(Sys.time(), worker_start_time, units = "secs")),
            chart_store = charts_to_store
          ))
        }
      }
    
      if (length(tool_calls) > 0) {
        cat("\n========================================\n")
        cat("[MCP SUCCESS] Parsed", length(tool_calls), "tool call(s)\n")
        cat("========================================\n")
    
        # Get session for resolvers
        current_session <- if (!is.null(settings$shiny_session)) settings$shiny_session else NULL
    
		cat("[MCP] Executing tools...\n")

		exec_fun <- NULL

		if (identical(tool_family, "mcp_excel") &&
			exists("helpers_mcp_tools", inherits = TRUE) &&
			is.function(helpers_mcp_tools$execute_parsed_tool)) {

		  exec_fun <- function(tc) {
			cat("[MCP] Executing (Excel):", tc$function_name, "\n")
			helpers_mcp_tools$execute_parsed_tool(tc, session = current_session)
		  }

		} else {
		  exec_fun <- function(tc) {
			list(error = "Uygun araç yürütücüsü bulunamadı (MCP seçimi kontrol edin).")
		  }
		}

		cat("[MCP] tool_calls parsed (names):", paste(vapply(tool_calls, function(t) t$function_name %||% "", ""), collapse = ", "), "\n")
		tool_results_raw <- lapply(tool_calls, exec_fun)
		
		# --- NEW: collect any chart specs to be injected back into the chat (as fenced blocks) ---
		# IMPORTANT: we're in a worker. Do NOT touch the Shiny session here.
		chart_blocks_text <- ""
		try({
				# __mcp_plot şartını kaldır — chart alanı olan tüm sonuçlar geçerlidir
				chart_specs <- Filter(function(x) is.list(x) && !is.null(x[["chart"]]), tool_results_raw)
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

		build_chart_summary <- function(raw_chart) {
		  chart <- raw_chart$chart %||% raw_chart
		  if (is.null(chart) || !is.list(chart)) {
			return("Grafik hazırlandı; veri kısa süreli özetlendi.")
		  }

		  desc_parts <- c()
		  chart_type <- chart$type %||% chart$chart_type %||% ""
		  if (nzchar(chart_type)) desc_parts <- c(desc_parts, paste0("Tür: ", chart_type))

		  mapping <- chart$mapping %||% list()
		  axes <- c()
		  if (nzchar(mapping$x %||% "")) axes <- c(axes, paste0("X=", mapping$x))
		  if (nzchar(mapping$y %||% "")) axes <- c(axes, paste0("Y=", mapping$y))
		  if (nzchar(mapping$group %||% "")) axes <- c(axes, paste0("Gruplama=", mapping$group))
		  if (length(axes)) desc_parts <- c(desc_parts, paste(axes, collapse = ", "))

		  df <- chart$data
		  row_hint <- chart$n %||% if (is.data.frame(df)) nrow(df) else NULL
		  if (is.finite(row_hint)) desc_parts <- c(desc_parts, paste0("Örnek satır sayısı: ", row_hint))

		  summary_line <- if (length(desc_parts)) paste(desc_parts, collapse = " | ") else "Dosyadaki verilerden üretildi"

		  # Hızlı içgörü: sayısal eksen varsa dağılımı özetle
		  quick_observation <- NULL
		  if (is.data.frame(df)) {
			num_candidate <- NULL
			if (nzchar(mapping$y %||% "") && is.numeric(df[[mapping$y]])) num_candidate <- df[[mapping$y]]
			if (is.null(num_candidate) && nzchar(mapping$x %||% "") && is.numeric(df[[mapping$x]])) num_candidate <- df[[mapping$x]]

			if (!is.null(num_candidate)) {
			  num_candidate <- suppressWarnings(as.numeric(num_candidate))
			  num_candidate <- num_candidate[is.finite(num_candidate)]
			  if (length(num_candidate)) {
                        med_val <- stats::median(num_candidate)
                        q1 <- stats::quantile(num_candidate, 0.25, na.rm = TRUE)
                        q3 <- stats::quantile(num_candidate, 0.75, na.rm = TRUE)
                        mn <- min(num_candidate)
                        mx <- max(num_candidate)
                        iqr_span <- q3 - q1
                        tail_hint <- if (med_val > mean(c(q1, q3))) "üst" else "alt"
                        quick_observation <- paste(
                          sprintf("Ortanca %.2f (Q1=%.2f, Q3=%.2f), min %.2f, max %.2f.", med_val, q1, q3, mn, mx),
                          sprintf("Değerler %s kuyrukta yoğunlaşıyor; dışa taşan uçlar için kutu yaylarını inceleyebilirsin.", tail_hint),
                          sprintf("IQR %.2f olduğundan veri yayılımı %s; bu aralık grafik üzerinde renk/yoğunluk olarak hissedilir.", iqr_span, if (iqr_span > 0) "belirgin" else "düşük")
				)
			  }
			} else if (nzchar(mapping$x %||% "") && !is.numeric(df[[mapping$x]])) {
			  top_levels <- sort(table(df[[mapping$x]]), decreasing = TRUE)
			  top_levels <- head(top_levels, 3)
			  top_share <- round(as.numeric(top_levels) / sum(top_levels) * 100, 1)
			  quick_observation <- paste0(
				"En sık kategoriler: ",
				paste(sprintf("%s (%d, %s%%)", names(top_levels), as.integer(top_levels), format(top_share, nsmall = 1)), collapse = ", "),
				". Yoğunluğun bu gruplarda toplandığını vurgula; kalan uzun kuyruğu da kısaca hatırlat."
			  )
			}
		  }

		  base_line <- paste0("Grafik hazırlandı: ", summary_line, ".")
		  if (nzchar(quick_observation)) {
			paste(base_line, quick_observation, "Eksenlerdeki deseni iki cümleyle anlat ve kullanıcının aklında net bir tablo oluşmasını sağla.")
		  } else {
			paste(base_line, "Veri dağılımını ve olası uç değerleri kısaca betimleyip okuyucuya yol gösterici bir paragraf ekle.")
		  }
		}

		build_auto_insight <- function(raw_results) {
		  # 1) Grafik varsa öne al
		  chart_pick <- Filter(function(x) is.list(x) && (!is.null(x[["chart"]]) || isTRUE(x[["__mcp_plot"]])), raw_results)
		  if (length(chart_pick)) {
			return(build_chart_summary(chart_pick[[1]]))
		  }

		  # 2) DataFrame önizlemesi varsa kısa özet çıkar
		  for (rr in raw_results) {
			df <- rr$`sonuç_önizleme` %||% rr$preview
			if (is.data.frame(df) && nrow(df) > 0) {
			  num_cols <- names(df)[vapply(df, is.numeric, logical(1))]
			  if (length(num_cols)) {
				vals <- suppressWarnings(as.numeric(df[[num_cols[1]]]))
				vals <- vals[is.finite(vals)]
				if (length(vals)) {
				  avg  <- mean(vals)
				  med  <- stats::median(vals)
				  mn   <- min(vals)
				  mx   <- max(vals)
				  sdv  <- stats::sd(vals)
				  return(sprintf(
					paste(
					  "İçgörü: %d satırın %s sütunu min %.2f, medyan %.2f, ortalama %.2f, max %.2f.",
					  "Standart sapma %.2f; dağılımın genişliği ve olası uç noktalar üzerine birkaç cümle kur.",
					  "Kısa, öğretici bir paragrafla kullanıcının görebileceği trendleri ve aksiyon önerilerini anlat."
					),
					nrow(df), num_cols[1], mn, med, avg, mx, sdv
				  ))
				}
			  }

			  head_cols <- paste(head(colnames(df), 3), collapse = ", ")
			  return(sprintf(
				paste(
				  "İçgörü: İlk %d satırda öne çıkan sütunlar %s; satır örneklerini kullanarak eğilimleri anlat.",
				  "Okuyucuya rehberlik edecek 4-5 cümlelik bir paragraf yaz; hangi kolonların dikkat çektiğini ve neden önemli olabileceğini açıkla."
				),
				nrow(df), head_cols
			  ))
			}
		  }

		  "İçgörü: Sonuçlar yukarıda; dağılımı, beklenmedik değerleri ve olası aksiyonları birkaç cümleyle rehber gibi açıkla."
		}
            
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
		
		# Türkçe: Ham araç sonuçlarını detaylı logla
        cat("\n========== [GLOBAL] HAM ARAÇ SONUÇLARI ==========\n")
        for (i in seq_along(tool_results_raw)) {
          raw <- tool_results_raw[[i]]
          cat("\n[GLOBAL] Araç #", i, "\n")
          cat("[GLOBAL] Class:", class(raw), "\n")
          cat("[GLOBAL] Names:", paste(names(raw), collapse=", "), "\n")
          
          if (is.list(raw)) {
            if (!is.null(raw$error)) {
              cat("[GLOBAL] *** HATA VAR ***: ", raw$error, "\n")
            }
            
            df <- raw$`sonuç_önizleme` %||% raw$preview
            if (is.data.frame(df)) {
              cat("[GLOBAL] DataFrame bulundu - Satır:", nrow(df), " Sütun:", ncol(df), "\n")
              if (nrow(df) > 0) {
                cat("[GLOBAL] İlk satır:\n")
                print(df[1, , drop=FALSE])
              }
            } else {
              cat("[GLOBAL] DataFrame YOK veya geçersiz!\n")
            }
          }
        }
        cat("========== [GLOBAL] HAM SONUÇLAR BİTİŞ ==========\n\n")
        
# Türkçe: Araç sonuçlarını LLM için okunabilir formata çevir
        cat("\n╔════════════════════════════════════════════════════╗\n")
        cat("║  [GLOBAL] ARAÇ SONUÇLARINI FORMATLAMAYA BAŞLIYOR  ║\n")
        cat("╚════════════════════════════════════════════════════╝\n\n")
        
        tool_results <- lapply(seq_along(tool_calls), function(i) {
          raw <- tool_results_raw[[i]]
          tool_name <- tool_calls[[i]]$function_name
          
          cat("\n========== [GLOBAL] Araç #", i, " Formatlanıyor ==========\n")
          cat("[GLOBAL] Araç adı:", tool_name, "\n")
          cat("[GLOBAL] raw değişkeni class:", class(raw), "\n")
          cat("[GLOBAL] raw değişkeni names:", paste(names(raw), collapse=", "), "\n")
          
          # Türkçe: sonuç_önizleme veya preview'i bul
          df <- NULL
          if (!is.null(raw$`sonuç_önizleme`)) {
            cat("[GLOBAL] sonuç_önizleme bulundu\n")
            df <- raw$`sonuç_önizleme`
          } else if (!is.null(raw$preview)) {
            cat("[GLOBAL] preview bulundu\n")
            df <- raw$preview
          } else {
            cat("[GLOBAL] *** UYARI: Ne sonuç_önizleme ne de preview bulundu! ***\n")
          }
          
          cat("[GLOBAL] df class:", class(df), "\n")
          cat("[GLOBAL] df is.data.frame:", is.data.frame(df), "\n") 

          if (is.list(raw) && (!is.null(raw$chart) || isTRUE(raw$`__mcp_plot`))) {
            cat("[GLOBAL] Grafik sonucu algılandı; JSON yerine özet kullanılacak.\n")
            result_text <- build_chart_summary(raw)

          } else if (is.data.frame(df)) {
            cat("[GLOBAL] DataFrame boyutu: ", nrow(df), " satır x ", ncol(df), " sütun\n")
            cat("[GLOBAL] Sütun isimleri:", paste(colnames(df), collapse=", "), "\n")
            
            if (nrow(df) > 0) {
              # Ensure UTF-8 headers/cells so Turkish characters render correctly
              df <- as.data.frame(df, stringsAsFactors = FALSE)
              df[] <- lapply(df, function(col) tryCatch(enc2utf8(as.character(col)), error = function(e) col))
              colnames(df) <- tryCatch(enc2utf8(colnames(df)), error = function(e) colnames(df))
			  
              cat("[GLOBAL] ✓ VERİ VAR - İLK SATIR:\n")
              print(df[1, , drop=FALSE])
              
              # Türkçe: DataFrame'i markdown tablo olarak formatla
              header <- paste0("| ", paste(colnames(df), collapse = " | "), " |")
              separator <- paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|")
              rows <- apply(df, 1, function(row) {
                paste0("| ", paste(row, collapse = " | "), " |")
              })
              table_md <- paste(c(header, separator, rows), collapse = "\n")
              
			  source_table_values <- raw$source_table_values
              if ((is.null(source_table_values) || !length(source_table_values)) && "source_table" %in% names(df)) {
                st_vals <- unique(df$source_table)
                st_vals <- st_vals[!is.na(st_vals)]
                source_table_values <- sort(as.character(st_vals))
              }
              source_table_line <- if (!is.null(source_table_values) && length(source_table_values)) {
                paste0("source_table değerleri: ", paste(source_table_values, collapse = ", "))
              } else {
                "UYARI: Bu sonuç source_table sütununu içermiyor. Lütfen sorgunuza ekleyin."
              }

              dropped_cols <- raw$dropped_all_na_columns
              dropped_line <- if (!is.null(dropped_cols) && length(dropped_cols)) {
                paste0("Tamamen NA olduğu için gizlenen sütunlar: ", paste(dropped_cols, collapse = ", "))
              } else {
                ""
              }
			  
              result_text <- paste0(
                "╔════════════════════════════════════════╗\n",
                "║  VERİTABANINDAN GELEN GERÇEK VERİ      ║\n",
                "╚════════════════════════════════════════╝\n\n",
                "SQL Sorgusu: ", raw$sql_effective %||% "N/A", "\n",
                "Dönen Toplam Satır: ", nrow(df), "\n",
                "Dönen Toplam Sütun: ", ncol(df), "\n",
                source_table_line, "\n",
                if (nzchar(dropped_line)) paste0(dropped_line, "\n") else "",
                "\n",
                "⬇️ AŞAĞIDA ", nrow(df), " SATIR GERÇEK VERİ VAR ⬇️\n",
                "BU SAYILARI AYNEN KULLAN - UYDURMA!\n\n",
                table_md, "\n\n",
                "⬆️ YUKARDA ", nrow(df), " SATIR GERÇEK VERİ VAR ⬆️\n",
                "BU TABLODAKİ SAYILARI BİREBİR KOPYALA!"
              )
              
              cat("\n[GLOBAL] ✓ Markdown tablo oluşturuldu\n")
              cat("[GLOBAL] Tablo uzunluğu:", nchar(table_md), "karakter\n")
              cat("[GLOBAL] Tablo ilk 500 karakteri:\n")
              cat(substr(table_md, 1, 500), "\n...\n")
              
            } else {
              cat("[GLOBAL] *** UYARI: DataFrame BOŞ (0 satır) ***\n")
              result_text <- "UYARI: Sorgu sonucu boş döndü."
            }
          } else if (is.list(raw) && !is.null(raw$result) && is.character(raw$result)) {
            cat("[GLOBAL] ✓ Liste içindeki result metni kullanılacak\n")
            result_text <- paste(raw$result, collapse = "\n\n")
          } else if (is.character(raw) && length(raw)) {
            cat("[GLOBAL] ✓ Ham karakter vektörü kullanılacak\n")
            result_text <- paste(raw, collapse = "\n\n")
          } else {
            cat("[GLOBAL] *** UYARI: df DataFrame değil! JSON formatında dönecek ***\n")
            result_text <- jsonlite::toJSON(raw, auto_unbox = TRUE, pretty = TRUE)
          }
          
          cat("[GLOBAL] result_text uzunluğu:", nchar(result_text), "karakter\n")
          cat("[GLOBAL] result_text ilk 300 karakteri:\n")
          cat(substr(result_text, 1, 300), "\n...\n")
          cat("========================================\n\n")
          
          list(tool = tool_name, result = result_text)
        })
        
        cat("\n╔════════════════════════════════════════════════════╗\n")
        cat("║  [GLOBAL] TÜM ARAÇLAR FORMATLANDI                  ║\n")
        cat("╚════════════════════════════════════════════════════╝\n\n")
        
		# Türkçe: Araç sonuçlarını log'a yaz
        for (i in seq_along(tool_results)) {
          tr <- tool_results[[i]]
          cat("\n========== ARAÇ SONUCU ", i, " ==========\n")
          cat("Araç Adı: ", tr$tool, "\n")
          cat("Sonuç Uzunluğu: ", nchar(tr$result), " karakter\n")
          cat("İlk 1000 karakter:\n", substr(tr$result, 1, 1000), "\n")
          cat("========================================\n\n")
        }
        
        # Türkçe: LLM için sonuç mesajı oluştur
        results_text <- paste(
          vapply(tool_results, function(tr) trimws(tr$result), character(1)),
          collapse = "\n\n"
        )
		
        # Yalnızca GERÇEK VERİ tablosunu döndür, ikinci LLM geçişini atla
        if (isTRUE(getOption("mergen.ai.strict_data_only", FALSE))) {
		  insight_txt <- build_auto_insight(tool_results_raw)
		  final_txt <- results_text
		  # Araçlar grafik ürettiyse ekle
		  if (exists("chart_blocks_text") && is.character(chart_blocks_text) && nzchar(chart_blocks_text)) {
				final_txt <- paste0(final_txt, "\n\n", chart_blocks_text)
		  }
		  if (nzchar(insight_txt)) {
				final_txt <- paste(final_txt, insight_txt, sep = "\n\n")
		  }
		  return(list(
				content     = final_txt,
				duration    = as.numeric(difftime(Sys.time(), worker_start_time, units = "secs")),
			chart_store = charts_to_store
		  ))
		}
        
        # Türkçe: Tam sonuç metnini log'a yaz (LLM'e ne gönderildiğini görmek için)
        cat("\n========== LLM'E GÖNDERİLEN TAM SONUÇ METNİ ==========\n")
        cat(results_text, "\n")
        cat("========================================\n\n")
		
		# Türkçe: Chat history'nin son elemanını (AI'a gönderilecek mesajı) detaylı logla
        cat("\n╔═══════════════════════════════════════════════════════════╗\n")
        cat("║  [GLOBAL] AI'A GÖNDERİLECEK MESAJIN SON HALİ              ║\n")
        cat("╚═══════════════════════════════════════════════════════════╝\n\n")
        
        last_msg <- chat_history[[length(chat_history)]]
        cat("[GLOBAL] Son mesaj role:", last_msg$role, "\n")
        cat("[GLOBAL] Son mesaj uzunluğu:", nchar(last_msg$content), "karakter\n")
        cat("\n[GLOBAL] SON MESAJIN TAM İÇERİĞİ:\n")
        cat("════════════════════════════════════════════════════════════\n")
        cat(last_msg$content)
        cat("\n════════════════════════════════════════════════════════════\n\n")
        
        # Türkçe: Markdown tablo var mı kontrol et
        if (grepl("\\|.*\\|.*\\|", last_msg$content)) {
          cat("[GLOBAL] ✓ Mesajda markdown tablo BULUNDU\n")
          # Türkçe: Kaç satır tablo var?
          table_lines <- length(gregexpr("\n", last_msg$content)[[1]])
          cat("[GLOBAL] Tabloda yaklaşık", table_lines, "satır var\n")
        } else {
          cat("[GLOBAL] *** UYARI: Mesajda markdown tablo BULUNAMADI! ***\n")
        }
        
        # Add to history - IMPORTANT: Don't include raw tool call text
        chat_history <- append(chat_history, list(
          list(role = "assistant", content = "[Araçlar kullanıldı]")
        ))
		chat_history <- append(chat_history, list(
          list(role = "user", content = paste0(
            "Araç sonuçları:\n\n",
            results_text,
            "\n\n╔═══════════════════════════════════════════════════════╗\n",
            "║  MUTLAK KURAL - ASLA İHLAL ETME                      ║\n",
            "╚═══════════════════════════════════════════════════════╝\n\n",
            "Yukarıdaki tablo GERÇEK VERİDİR. Bu veritabanından geldi.\n\n",
            "SEN BİR VERİ RAPORLAYICI ROBOTSUN - VERİ ÜRETME!\n\n",
            "YAPMAN GEREKENLER:\n",
            "✓ Yukarıdaki tabloda gördüğün TAM sayıları kopyala\n",
            "✓ Hiçbir değeri yuvarlaMA, değiştirME\n",
            "✓ Tablodaki her satırı kullan\n",
            "✓ ProjeAdi ve sayıları BİREBİR kopyala\n\n",
            "✓ Yanıtı TEK SEFERDE tamamla; ek deneme veya ikinci tur bekleme.\n",
            "✓ Sonuçları yorumla: trend, uç değer ve dağılımı en az 4-5 cümlelik öğretici bir paragrafla açıkla; kullanıcının hangi desene odaklanması gerektiğini belirt.\n",
            "✓ Grafik varsa, eksenler ve göze çarpan deseni 1-2 cümlede özetle.\n\n",
            "ASLA YAPMA:\n",
            "✗ 'Örnek Çıktı' yazma\n",
            "✗ Sahte sayılar üretme\n",
            "✗ Tahmin etme\n",
            "✗ Benzer değerler uydurma\n",
            "✗ '...' kullanma\n\n",
            "Eğer yukarıdaki tabloda veri YOKSA:\n",
            "→ 'Sonuç bulunamadı' de ve DUR\n\n",
            "Eğer yukarıdaki tabloda veri VARSA:\n",
            "→ O sayıları AYNEN yaz\n\n",
            "ŞİMDİ: Yukarıdaki GERÇEK tabloyu kullanarak kullanıcının sorusunu cevapla."
          ))
        ))
        
        cat("\n========================================\n")
        cat("[MCP] Calling LLM again with tool results\n")
        cat("========================================\n")
		
		# Türkçe: Sistem mesajını ÖNCELİKLE ekle - AI'ın rolünü tanımla
        system_msg_anti_hallucination <- list(
          role = "system",
          content = paste0(
            "SEN BİR VERİ ANALİZCİSİSİN - VERİ OLUŞTURMAYAN!\n\n",
            "Kullanıcı sana araç sonuçları verdiğinde:\n",
            "- O sonuçlardaki EXACT rakamları kullan\n",
            "- Hiçbir şeyi uydurma\n",
            "- 'Örnek' deme\n",
            "- Eğer veri yoksa 'Sonuç yok' de\n\n",
            "BU MUTLAK BİR KURALDIR."
          )
        )
        
        # Türkçe: Sistem mesajını chat_history'nin başına ekle
        chat_history <- c(list(system_msg_anti_hallucination), chat_history)
		
		# Türkçe: DEBUG - Tüm chat_history'yi dosyaya yaz
        tryCatch({
          debug_file <- file.path(tempdir(), sprintf("chat_debug_%s.txt", format(Sys.time(), "%Y%m%d_%H%M%S")))
          writeLines(
            c(
              "═══════════════════════════════════════════════",
              "CHAT HISTORY - AI'A GÖNDERİLEN TÜM MESAJLAR",
              "═══════════════════════════════════════════════",
              "",
              sapply(seq_along(chat_history), function(i) {
                msg <- chat_history[[i]]
                paste0(
                  "\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n",
                  "MESAJ #", i, " - Role: ", msg$role, "\n",
                  "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n",
                  msg$content
                )
              })
            ),
            debug_file
          )
          cat("\n[GLOBAL] ✓ Chat history dosyaya yazıldı:", debug_file, "\n")
          cat("[GLOBAL] Bu dosyayı inceleyerek AI'a tam olarak ne gönderildiğini görebilirsiniz\n\n")
        }, error = function(e) {
          cat("[GLOBAL] Dosya yazma hatası:", e$message, "\n")
        })
        
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
          timeout(300)
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
		  # Türkçe yorum: Eğer grafik hâlâ yoksa zorunlu yedek grafiği ekle
		  fb <- add_fallback_chart(fb)

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
		  # Türkçe yorum: Eğer grafik hâlâ yoksa zorunlu yedek grafiği ekle
		  fb <- add_fallback_chart(fb)

		  return(list(
			content  = fb,
			duration = as.numeric(difftime(Sys.time(), worker_start_time, units = "secs")),
			chart_store = charts_to_store
		  ))
		}
        
		ai2 <- strip_planner_text(ai2)

		# Türkçe yorum: Eğer araçlardan gelen grafik bloğu varsa ekle
		if (is.character(chart_blocks_text) && nzchar(chart_blocks_text)) {
		  ai2 <- paste0(ai2, "\n\n", chart_blocks_text)
		}

		# Türkçe yorum: Hâlâ grafik yoksa (model araç çağırmış olsa bile veri görselleştirmemişse) yedek grafik ekle
		ai2 <- add_fallback_chart(ai2)

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

	# Türkçe yorum: Model araç çağırmadıysa ve grafik niyeti varsa yedek grafik bloğu ekle
	ai_content <- add_fallback_chart(ai_content)

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
    
    creds <- resolve_local_llm_credentials(selected_model)
    api_url <- creds$endpoint
    if (!nzchar(api_url)) {
	  stop("API endpoint not found in configuration")
	}
    
	default_api_key <- creds$default_api_key %||% ""
	allow_user_key <- isTRUE(creds$allow_user_key)
	# Türkçe yorum: Önce ilgili uç için kullanıcı anahtarı kullanılabilir mi bak
	api_key <- ""
	if (allow_user_key) {
	  api_key <- as.character(current_settings$api_key %||% current_settings$api_key_override %||% "")
	  if (!nzchar(api_key)) {
		sess <- current_settings$shiny_session %||% NULL
		if (!is.null(sess) && !is.null(sess$userData$ai_api_key)) {
			  api_key <- as.character(sess$userData$ai_api_key)[1]
		}
	  }
	} else {
	  api_key <- as.character(current_settings$api_key_override %||% "")
	}
	if (!nzchar(api_key) && nzchar(default_api_key)) {
	  api_key <- as.character(default_api_key)[1]
	}
	# Türkçe: Yerel uçlar (Ollama/LM Studio vb.) için anahtar zorunlu değil
	is_local_noauth <- grepl("(?i)(localhost|127\\.0\\.0\\.1|ollama)", api_url)
	if (!nzchar(api_key) && !is_local_noauth) {
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
	
	max_tokens_val <- current_settings$max_output_tokens %||% 2048
    
    body <- list(
      model = selected_model,
      messages = messages_payload,
      stream = FALSE,
      temperature = temp_value,
      max_tokens = max_tokens_val
    )
    
	# Türkçe: Yerel uçlarda boş Authorization başlığını GÖNDERME
	hds <- list(`Content-Type` = "application/json")
	if (nzchar(api_key)) hds$Authorization <- paste("Bearer", api_key)

	  response <- tryCatch({
		httr::POST(
		  url = api_url,
		  body = body,
		  encode = "json",
		  do.call(httr::add_headers, hds),
		  httr::timeout(300)
		)
	  }, error = function(e) {
		stop(sprintf("API_CONNECTION_ERROR: %s", conditionMessage(e)))
	  })
	  
	  if (httr::status_code(response) >= 400) {
		error_content <- try(httr::content(response, "text", encoding = "UTF-8"), silent = TRUE)
		stop(sprintf("API_HTTP_ERROR_%d: %s", 
					 httr::status_code(response), 
					 if(!inherits(error_content, "try-error")) substr(error_content, 1, 200) else ""))
	  }
	  
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
        id = "mergen",
        label = "Mergen",
        display_name = "MERGEN",
        subtitle = "Standart",
        avatar = "characters/avatar/Mergen_avatar_original.png",
        image = "characters/resim/Mergen_resim_original.png",
        accent = "#7C4DFF",
        accent_hover = "#8E66FF",
        accent_active = "#6A3BE6",
        selection_card_tr = "\"Zihin Yayından Çıkan Ok\" — hızlı, net, uygulanabilir",
        lore_tr = "Mergen, Türk ve Altay anlatılarında bilgeliğin ve keskin zekânın sembolüdür. Bazı kaynaklarda Kayra'nın oğlu olarak geçer. Oku ve yayı, isabetli düşünceyi ve doğru soruyu bulmayı temsil eder. Gök katlarının sessizliğinde düşünür, karmaşığı özüne indirir. Şaman inançlarında 'akıl veren' olarak bilinir; günümüz yorumunda ise veriyi süzer, gürültüyü susturur. Mergen'i seçtiğinizde fazla söze gerek kalmaz: hedef, nişan ve net sonuç.",
        style_tr = "Önce kısa özet, ardından adım adım plan ve küçük örnek",
        profile_metrics = list(
          list(label = "Analitik Keskinlik", value = 88L),
          list(label = "Planlama Disiplini", value = 84L),
          list(label = "Empatik Ton", value = 52L),
          list(label = "Risk Uyarısı", value = 47L)
        ),
        signature_moves = list(
          "2-3 cümlelik yönetici özeti",
          "Net yapılacaklar listesi",
          "Mini örnek veya çıktı ile pekiştirme"
        ),
        system_prompt_en = "Be a balanced, pragmatic assistant. First provide a 2–3 sentence executive summary, then a concise step-by-step plan, then a minimal example/output. Avoid rhetoric and hedging. Use precise, actionable language. Ask for missing constraints only if they block progress.",
		parameters = list(temperature = 0.4),
        tts_voice = "tr-male-1"
      ),
      list(
        id = "ulgen",
        label = "Ülgen",
        display_name = "ÜLGEN",
        subtitle = "Yapıcı Uzman",
        avatar = "characters/avatar/Ulgen_avatar_original.png",
        image = "characters/resim/Ulgen_resim_original.png",
        accent = "#2F6DF6",
        accent_hover = "#4C80F7",
        accent_active = "#1E59E0",
        selection_card_tr = "\"Göğün Işığı\" — moral yükseltir, yolu aydınlatır",
        lore_tr = "Ülgen, göğün aydınlık yüzüdür; iyilik, düzen ve üretkenliğin tanrısı olarak tanınır. Üst gök katlarında yaşadığına inanılır; insanlara ateşi, zanaatı ve doğru yolu öğreten bir rehberdir. Kozmik dengede karşıtı Erlik olsa da amacı çatışma değil, düzen kurmaktır. Eski törenlerde beyaz renklerle anılır; umut ve yeniden başlama duygusunu simgeler. Ülgen'i seçtiğinizde sis dağılır, seçenekler berraklaşır ve eylem planı ortaya çıkar.",
        style_tr = "Sorunu çerçevele; çözüm seçenekleri + artı/eksi; gerekçeli öneri; eylem listesi",
        profile_metrics = list(
          list(label = "İlham Verici Ton", value = 82L),
          list(label = "Seçenek Üretimi", value = 90L),
          list(label = "Empati", value = 64L),
          list(label = "Uygulama Netliği", value = 74L)
        ),
        signature_moves = list(
          "Sorunu berrak çerçeveleme",
          "2-3 alternatif yol ve kıyas",
          "Pozitif tonla eylem listesi"
        ),
        system_prompt_en = "Act like a constructive expert: quickly frame the problem; propose 2–3 viable solution paths with trade-offs; recommend one path with rationale; end with a checklist of next actions and acceptance criteria. Keep the tone positive and professional.",
		parameters = list(temperature = 0.5),
        tts_voice = "tr-male-1"
      ),
      list(
        id = "kayra",
        label = "Kayra",
        display_name = "KAYRA",
        subtitle = "Stratejist",
        avatar = "characters/avatar/Kayra_avatar_original.png",
        image = "characters/resim/Kayra_resim_original.png",
        accent = "#12A97B",
        accent_hover = "#26B790",
        accent_active = "#0C8C63",
        selection_card_tr = "\"Evrenin Haritacısı\" — büyük resmi kurar, yolu fazlara böler",
        lore_tr = "Kayra Han, bazı Sibirya ve Türk anlatılarında yaratıcı ve en yüce ilke olarak yer alır; kaosu ayırıp göğü, yeri ve suları düzene sokan güç olarak bilinir. Bazı varyantlarda Ülgen ve Erlik'in babası kabul edilir; kararları denge ve ilkelere dayanır. Onun sesi acele etmez; uzun vadeli görüş, sağlam kilometre taşları ve sorumluluk paylaşımı ister. Kayra'yı seçtiğinizde vizyon haritaya, harita da uygulanabilir bir yol planına dönüşür.",
        style_tr = "Amaçlar ve ilkeler → seçenekler/trade-off → karar matrisi → fazlı roadmap",
        profile_metrics = list(
          list(label = "Vizyoner Bakış", value = 91L),
          list(label = "Risk Yönetimi", value = 86L),
          list(label = "Uzun Vadeli Plan", value = 95L),
          list(label = "Ekip Koordinasyonu", value = 78L)
        ),
        signature_moves = list(
          "İlkelerden başlayan strateji çerçevesi",
          "Karar matrisi ile seçenek kıyası",
          "Fazlara ayrılmış yol haritası"
        ),
        system_prompt_en = "Operate as a strategist: state objectives and guiding principles; map alternatives with trade-offs; provide a decision matrix; outline a phased roadmap with milestones, owners, and risks; include governance/policy notes when relevant.",
		parameters = list(temperature = 0.3, long_form = TRUE),
        tts_voice = "tr-male-1"
      ),
      list(
        id = "erlik",
        label = "Erlik",
        display_name = "ERLİK",
        subtitle = "Eleştirel Eş",
        avatar = "characters/avatar/Erlik_avatar_original.png",
        image = "characters/resim/Erlik_resim_original.png",
        accent = "#B66A2C",
        accent_hover = "#C27A3D",
        accent_active = "#8F5321",
        selection_card_tr = "\"Varsayım Avcısı\" — kör noktayı görür, nazikçe dürtükler",
        lore_tr = "Erlik Han, yeraltı âleminin hükümdarı olarak tanınır; kozmik dengede eksikleri, kusurları ve sınavları görünür kılan karşıt güçtür. Amacı korkutmak değil, yanlışı düzeltmek için perdeyi aralamaktır; demir ve toprakla özdeşleşir. Anlatılarda hastalık ve kıtlık gibi riskleri hatırlatır; böylece tedbiri doğurur. Erlik'i seçtiğinizde keskin sorular gelir: 'Neye dayanıyor? Ne ters gidebilir?' ve planın zayıf halkaları güçlenir.",
        style_tr = "Varsayımlar → riskler & karşı örnekler → nazik sorgu → risk azaltma → kontrol listesi",
        profile_metrics = list(
          list(label = "Risk Uyarısı", value = 94L),
          list(label = "Varsayım Avcılığı", value = 92L),
          list(label = "Diplomatik Ton", value = 68L),
          list(label = "Kanıt Talebi", value = 88L)
        ),
        signature_moves = list(
          "Sessiz varsayımları çıkarma",
          "Nazik ama keskin sorgular",
          "Önleyici aksiyon listesi"
        ),
        system_prompt_en = "Be a respectful critical partner. Surface hidden assumptions; list risks and counterexamples; ask sharp but polite why/how questions; propose risk-mitigating alternatives; conclude with a concise pre-flight checklist. Keep language diplomatic, not scary.",
		parameters = list(temperature = 0.4),
        tts_voice = "tr-male-1"
      ),
      list(
        id = "umay",
        label = "Umay Ana",
        display_name = "UMAY ANA",
        subtitle = "Rehber",
        avatar = "characters/avatar/Umay_Ana_avatar_original.png",
        image = "characters/resim/Umay_Ana_resim_original.png",
        accent = "#E98686",
        accent_hover = "#EE9B9B",
        accent_active = "#D96F6F",
        selection_card_tr = "\"Nazik Öğretici\" — yeni başlayanların korkusunu alır",
        lore_tr = "Umay Ana, Türk dünyasında bereketin ve çocukların koruyucu ruhu olarak sevilir; turna kuşuyla, sıcaklık ve şefkatle anılır. Halk inançlarında annenin ve yuvanın hamisi kabul edilir; adı eski metinlerde de yaşar. Karmaşayı küçük lokmalara böler; telaşı sakinliğe, belirsizliği güvene çevirir. Umay'ı seçtiğinizde dil yumuşar; adımlar küçülür, ipuçları belirir ve yeni başlayanlar için kapı aralanır.",
        style_tr = "Basit dil; küçük numaralı adımlar; sık hata/ipuçları; kısa güvenlik notu; mini örnek",
        profile_metrics = list(
          list(label = "Empatik Rehberlik", value = 95L),
          list(label = "Adım Adım Açıklama", value = 88L),
          list(label = "Sabır Düzeyi", value = 92L),
          list(label = "Güvenlik Hatırlatması", value = 76L)
        ),
        signature_moves = list(
          "Sade dil ve benzetmeler",
          "Hata noktalarına dair ipuçları",
          "Mini örnekle pekiştirme"
        ),
        system_prompt_en = "Be an empathetic teacher for beginners. Explain in simple language; break tasks into small numbered steps; include common pitfalls and tips; add a short safety/ethics note if relevant; provide a minimal working example.",
		parameters = list(temperature = 0.6),
        tts_voice = "tr-female-1"
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
  for (p in cand) { if (path_exists_relaxed(p)) return(p) }
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
  if (!is.character(hint) || length(hint) == 0 || is.na(hint[1])) {
    return(NULL)
  }

  parts <- tryCatch(strsplit(as.character(hint[1]), "&&", fixed = TRUE)[[1]], error = function(e) character(0))
  parts <- trimws(parts)
  parts <- parts[nzchar(parts)]
  if (!length(parts)) return(NULL)
  last <- tail(parts, 1)
  idx <- .build_basename_index(base_path)
  cand <- idx$map[[tolower(basename(last))]]
  if (is.null(cand) || !length(cand)) return(NULL)

  left <- if (length(parts) > 1) parts[seq_len(length(parts) - 1)] else character(0)
  if (!length(left)) {
    for (p in cand) { if (path_exists_relaxed(p)) return(p) }
    return(NULL)
  }

  scores <- vapply(cand, .score_path_by_parts, integer(1), parts = left)
  ord <- order(scores, decreasing = TRUE, na.last = NA)
  for (i in ord) {
    p <- cand[[i]]
    if (path_exists_relaxed(p)) return(p)
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
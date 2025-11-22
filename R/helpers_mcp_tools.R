# R/helpers_mcp_tools.R

suppressWarnings({
  library(jsonlite)
  library(readxl)
  library(data.table)
  library(DBI)
})

# Null-coalescing helper
`%||%` <- function(a, b) if (is.null(a)) b else a

# Create a private env to avoid scoping problems (e.g., futures)
helpers_mcp_tools <- new.env(parent = globalenv())

# Ensure shared filesystem helpers exist inside this environment
if (exists("path_exists_relaxed", envir = globalenv(), inherits = TRUE)) {
  assign(
    "path_exists_relaxed",
    get("path_exists_relaxed", envir = globalenv(), inherits = TRUE),
    envir = helpers_mcp_tools
  )
}

if (!exists("path_exists_relaxed", envir = helpers_mcp_tools, inherits = FALSE)) {
  helpers_mcp_tools$path_exists_relaxed <- function(path) {
    if (is.null(path) || !length(path)) return(FALSE)
    candidate <- as.character(path[1])
    if (!nzchar(candidate)) return(FALSE)
    isTRUE(file.exists(candidate))
  }
}

# Pull helper utilities from the global env when available (workers inherit them)
if (exists("normalize_excel_path", envir = globalenv(), inherits = TRUE)) {
  assign(
    "normalize_excel_path",
    get("normalize_excel_path", envir = globalenv(), inherits = TRUE),
    envir = helpers_mcp_tools
  )
}

if (!exists("normalize_excel_path", envir = helpers_mcp_tools, inherits = FALSE)) {
  helpers_mcp_tools$normalize_excel_path <- function(path) {
    if (is.null(path) || !nzchar(path)) return(path)

    # [DEĞİŞİKLİK] Step 0 kaldırıldı. 
    # "Absolute Trust" bloğu, Türkçe karakterli yollarda readxl'in çökmesine neden oluyordu.
    # Dosya var olsa bile aşağıda ShortPath (8.3) formatına çevrilmesini istiyoruz.

    # Let the shared MCP normalizer clean early if available
    if (exists("normalize_mcp_path", envir = globalenv(), inherits = TRUE)) {
      try_norm <- try(get("normalize_mcp_path", envir = globalenv(), inherits = TRUE)(path, must_exist = FALSE), silent = TRUE)
      if (!inherits(try_norm, "try-error") && !is.null(try_norm) && nzchar(try_norm)) {
        path <- try_norm
      }
    }

    p_fixed <- gsub("\\\\", "/", path)

    # Helper: remove accidental leading duplication (e.g., /srv/share/srv/share/...) which
    # breaks existence checks for network paths.
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

    # 1. Aggressive UNC Repair
    # If it starts with / but not //, convert to // immediately (keeps network roots intact)
    if (grepl("^/[^/]", p_fixed)) {
      p_fixed <- paste0("/", p_fixed)
    }

    # If already UNC (//server/share), skip normalizePath entirely to avoid path doubling
    if (grepl("^//", p_fixed)) {
      # CHECK FOR EXISTENCE AND RETURN SHORT PATH IF POSSIBLE (Fixes encoding issues on UNC)
      if (.Platform$OS.type == "windows") {
        # Try to force ShortPathName immediately for UNC
        try_short <- tryCatch(utils::shortPathName(gsub("/", "\\\\", p_fixed, fixed = TRUE)), error = function(e) NULL)
        if (!is.null(try_short) && nzchar(try_short) && file.exists(try_short)) {
           return(gsub("\\\\", "/", try_short, fixed = TRUE))
        }
      }
      # Do NOT enc2utf8 here, it breaks readxl on Windows
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

    # 2. Try to resolve existence + Convert to ShortPath (8.3) on Windows
    if (.Platform$OS.type == "windows") {
      # Try candidates as-is first (System encoding), then UTF8
      candidates <- unique(c(p_fixed, tryCatch(enc2utf8(p_fixed), error = function(e) NULL)))

      for (cand in candidates) {
        if (!is.null(cand) && path_exists_check(cand)) {
          # Use ShortPathName to avoid encoding hell (e.g. "Geliştirme" -> "GEL~1")
          short_p <- tryCatch({
            raw_short <- utils::shortPathName(gsub("/", "\\\\", cand, fixed = TRUE))
            gsub("\\\\", "/", raw_short, fixed = TRUE)
          }, error = function(e) NULL)

          if (!is.null(short_p) && nzchar(short_p)) return(short_p)
          
          # If short path fails but file exists, return the candidate that WORKED
          # Do NOT re-encode it
          return(cand)
        }
      }
    } else {
      if (path_exists_check(p_fixed)) return(enc2utf8(p_fixed))
    }

    # 3. Last resort: lightweight normalization without altering UNC-style roots
    normalized <- tryCatch(normalizePath(p_fixed, winslash = "/", mustWork = FALSE), error = function(e) p_fixed)
    # Remove enc2utf8 to prevent readxl errors on Windows
    dedupe_leading_repeat(normalized)
  }
}

# Try to copy the global function into our tools env
if (exists("safe_read_excel_table", envir = globalenv(), inherits = TRUE)) {
  assign(
    "safe_read_excel_table",
    get("safe_read_excel_table", envir = globalenv(), inherits = TRUE),
    envir = helpers_mcp_tools
  )
}

if (!exists("safe_read_excel_table", envir = helpers_mcp_tools, inherits = FALSE)) {
  helpers_mcp_tools$safe_read_excel_table <- function(path, sheet = 1, n_max = Inf, min_header_cols = 2) {
    # [DEĞİŞİKLİK] Windows'ta her zaman normalize_excel_path kullan.
    # Eski kod: if(file.exists(path)) path else normalize_excel_path(path)
    # Bu durum "Geliştirme" gibi yolları ShortPath'e çevirmeden readxl'e yolluyor ve patlatıyordu.
    
    path_prepared <- helpers_mcp_tools$normalize_excel_path(path)
    
    # Final check before passing to readxl
    if (!file.exists(path_prepared) && !fs::file_exists(path_prepared)) {
        # Last ditch: check if original path works (maybe normalization broke it, unlikely on Windows)
        if (file.exists(path)) path_prepared <- path
        else stop(sprintf("Dosya bulunamadı (Path: %s)", path_prepared))
    }
    
    ext <- tolower(tools::file_ext(path_prepared))
    if (!ext %in% c("xlsx", "xls", "xlsm")) {
      stop(sprintf("Excel uzantısı bekleniyor, bulundu: .%s", ext))
    }
	
    # Read
    df <- tryCatch({
      readxl::read_excel(path_prepared, sheet = sheet, col_names = TRUE)
    }, error = function(e) {
      # Fallback: Try ShortPathName if not already tried (fix for Turkish chars)
      if (.Platform$OS.type == "windows") {
         short_p <- tryCatch(utils::shortPathName(gsub("/", "\\\\", path_prepared)), error=function(x) NULL)
         if (!is.null(short_p) && nzchar(short_p)) {
            return(readxl::read_excel(short_p, sheet = sheet, col_names = TRUE))
         }
      }
      stop(e)
    })

    if (is.finite(n_max)) df <- head(df, n_max)
    df <- as.data.frame(df, stringsAsFactors = FALSE)
    if (anyNA(names(df)) || any(names(df) == "")) {
      names(df) <- paste0("X", seq_along(df))
    }
    names(df) <- make.names(names(df), unique = TRUE, allow_ = TRUE)
    df
  }
}

# --- NEW: universal table reader (xlsx/xls/csv/rds/rdata) --------------------
helpers_mcp_tools$safe_read_table_generic <- function(path, sheet = 1, n_max = Inf) {
  # First normalize/fix the path using the robust helper
  path_fixed <- helpers_mcp_tools$normalize_excel_path(path)
  
  ext <- tolower(tools::file_ext(path_fixed))
  as_dt <- function(df) data.table::as.data.table(as.data.frame(df, stringsAsFactors = FALSE))

  # helper: sanitize names (never NA/empty)
  sanitize_names <- function(df) {
    nms <- names(df)
    if (anyNA(nms) || any(nms == "")) nms <- paste0("X", seq_along(nms))
    names(df) <- make.names(nms, unique = TRUE, allow_ = TRUE)
    df
  }

  if (ext %in% c("xlsx", "xls")) {
    df <- helpers_mcp_tools$safe_read_excel_table(path_fixed, sheet = sheet, n_max = n_max)
    return(as_dt(sanitize_names(df)))
  }

  if (ext %in% c("csv", "txt")) {
    df <- tryCatch(data.table::fread(path_fixed, nThread = 1), error = function(e) {
      # fallback for weird encodings
      read.csv(path_fixed, stringsAsFactors = FALSE, check.names = FALSE)
    })
    if (is.finite(n_max)) df <- head(df, n_max)
    return(as_dt(sanitize_names(df)))
  }

  if (ext %in% c("rds")) {
    obj <- readRDS(path_fixed)
    if (inherits(obj, c("data.frame","data.table","tbl_df"))) {
      df <- obj
    } else if (is.list(obj) && length(obj)) {
      # pick first data-frame-like thing
      ix <- which(vapply(obj, function(x) inherits(x, c("data.frame","data.table","tbl_df")), logical(1)))
      if (length(ix)) df <- obj[[ix[1]]] else stop("RDS has no data.frame-like object")
    } else {
      stop("RDS is not a data.frame-like object")
    }
    if (is.finite(n_max)) df <- head(df, n_max)
    return(as_dt(sanitize_names(df)))
  }

  if (ext %in% c("rdata","rda")) {
    e <- new.env(parent = emptyenv())
    nm <- load(path_fixed, envir = e)
    picks <- nm[vapply(nm, function(n) inherits(e[[n]], c("data.frame","data.table","tbl_df")), logical(1))]
    if (!length(picks)) stop("RData has no data.frame-like object")
    df <- e[[picks[1]]]
    if (is.finite(n_max)) df <- head(df, n_max)
    return(as_dt(sanitize_names(df)))
  }

  stop(sprintf("Unsupported file type: .%s", ext))
}

# ============================
# Session file registry helpers
# ============================
helpers_mcp_tools$ensure_session_file_registry <- function(session = NULL) {
  if (is.null(session)) return(invisible())
  if (is.null(session$userData$current_session_files)) {
    session$userData$current_session_files <- list()
  }
  invisible()
}

helpers_mcp_tools$reset_session_file_registry <- function(session = NULL) {
  if (!is.null(session)) session$userData$current_session_files <- list()
  invisible(TRUE)
}

helpers_mcp_tools$get_session_user_id <- function(session = NULL) {
  if (is.null(session)) return(NULL)
  session$userData$user_id %||%
    session$userData$current_session_files %||%
    session$userData$userId %||%
    session$userData$id %||%
    session$userData$userID %||%
    NULL
}

helpers_mcp_tools$update_session_file_path <- function(session = NULL, tokens = NULL, new_path = NULL) {
  if (is.null(session) || is.null(new_path) || !nzchar(new_path)) return(invisible(FALSE))
  helpers_mcp_tools$ensure_session_file_registry(session)
  token_set <- unique(as.character(tokens %||% character(0)))
  updated <- FALSE
  for (key in names(session$userData$current_session_files)) {
    obj <- session$userData$current_session_files[[key]]
    nm <- obj$name %||% key
    if (key %in% token_set || nm %in% token_set) {
      session$userData$current_session_files[[key]]$path <- new_path
      session$userData$current_session_files[[key]]$datapath <- new_path
      updated <- TRUE
    }
  }
  invisible(updated)
}

helpers_mcp_tools$register_uploaded_file <- function(session = NULL, token, abs_path, display_name = NULL) {
  helpers_mcp_tools$ensure_session_file_registry(session)
  if (is.null(token) || !nzchar(token)) return(invisible(FALSE))
  
  # Use robust normalization
  normalize_for_registry <- function(p) {
    if (exists("normalize_mcp_path", mode = "function")) {
      out <- try(normalize_mcp_path(p, must_exist = FALSE), silent = TRUE)
      if (!inherits(out, "try-error") && nzchar(out)) return(out)
    }
    out <- try(helpers_mcp_tools$normalize_excel_path(p), silent = TRUE)
    if (!inherits(out, "try-error") && !is.null(out) && nzchar(out)) return(out)
    p
  }
  
  normalized_path <- normalize_for_registry(abs_path)
  
  session$userData$current_session_files[[token]] <- list(
    path = normalized_path,
    name = display_name %||% basename(abs_path)
  )
  cat("[RESOLVE] registry token", token, "->", normalized_path, "\n")
  invisible(TRUE)
}

helpers_mcp_tools$get_default_file_name <- function(session = NULL) {
  helpers_mcp_tools$ensure_session_file_registry(session)
  files <- session$userData$current_session_files
  if (is.null(files) || !length(files)) return(NULL)

  # Extract human friendly names (deduplicate to ignore file_id aliases)
  names_vec <- vapply(files, function(obj) {
    nm <- obj$name %||% obj$display %||% obj$filename %||% ""
    if (!is.character(nm) || length(nm) == 0) nm <- ""
    as.character(nm[1])
  }, character(1))

  names_vec <- unique(names_vec[nzchar(names_vec)])
  if (length(names_vec) == 1) return(names_vec[1])
  NULL
}

helpers_mcp_tools$auto_file_name <- function(file_name, session = NULL) {
  if (!is.null(file_name) && nzchar(file_name)) return(file_name)
  helpers_mcp_tools$get_default_file_name(session)
}

helpers_mcp_tools$resolve_file_argument <- function(arg, session = NULL) {
  helpers_mcp_tools$ensure_session_file_registry(session)

  if (is.null(arg) || !nzchar(arg)) {
    return(list(ok = FALSE, error = "file_name parameter is empty"))
  }

  cat("[RESOLVE] Looking for:", arg, "\n")
  
  # Helper to check existence via base or fs
  path_ok_robust <- function(candidate) {
    if (is.null(candidate) || !nzchar(candidate)) return(FALSE)
    if (isTRUE(file.exists(candidate))) return(TRUE)
    if (requireNamespace("fs", quietly = TRUE) && fs::file_exists(candidate)) return(TRUE)
    FALSE
  }

  path_ok <- function(candidate) {
     path_ok_robust(candidate)
  }
  
  # --- NEW: 0) Absolute path fast-path -------------------------------
  # Accept "C:/.../file.xlsx" or "/var/tmp/file.xlsx" straight away.
  is_abs <- grepl("^([A-Za-z]:)?[\\/]", arg)
  if (is_abs) {
    # Use the robust normalizer immediately to handle UNC/Encoding
    p <- try(helpers_mcp_tools$normalize_excel_path(arg), silent = TRUE)
    if (!inherits(p, "try-error") && path_ok(p)) {
      cat("[RESOLVE] Absolute path exists ->", p, "\n")
      return(list(ok = TRUE, path = p, display = basename(p)))
    }
  }

  # --- 1) Session registry matches -----------------------------------
  all_files <- session$userData$current_session_files
  base_arg  <- basename(arg)  # NEW: support basename matching

  if (!is.null(all_files) && length(all_files) > 0) {
    cat("[RESOLVE] Checking", length(all_files), "files in session\n")

    rehydrate_missing_path <- function(preferred_tokens) {
      tokens <- unique(Filter(nzchar, as.character(preferred_tokens %||% character(0))))
      if (!length(tokens)) return(NULL)
      uid <- helpers_mcp_tools$get_session_user_id(session)

      if (exists("resolve_uploaded_file", mode = "function")) {
        for (tok in tokens) {
          recovered <- try(resolve_uploaded_file(tok, user_id = uid), silent = TRUE)
          if (!inherits(recovered, "try-error") && path_ok(recovered)) {
            cat("[RESOLVE] Missing path recovered via resolve_uploaded_file ->", recovered, "\n")
            return(recovered)
          }
        }
      }

      base_dir <- getOption("mergen.mcp_base_dir") %||% Sys.getenv("MCP_FILES_BASE", "")
      if (!is.null(uid) && nzchar(base_dir)) {
        user_dir <- file.path(base_dir, sprintf("user_%s", uid))
        for (tok in tokens) {
          candidate <- file.path(user_dir, basename(tok))
          if (path_ok(candidate)) {
            cat("[RESOLVE] Missing path recovered via MCP base dir ->", candidate, "\n")
            return(candidate)
          }
        }
      }

      NULL
    }
	
    for (key in names(all_files)) {
      file_obj <- all_files[[key]]
      path_to_check <- file_obj$path %||% file_obj$datapath
      nm <- file_obj$name %||% basename(path_to_check)
      path_base <- basename(path_to_check %||% "")

      matched <- any(c(
        identical(key, arg),
        identical(nm, arg),
        identical(path_base, arg),
        identical(key, base_arg),
        identical(nm, base_arg),
        identical(path_base, base_arg)
      ))
      if (!matched) next

      cat("[RESOLVE] Match ->", path_to_check, "Exists:", path_ok(path_to_check), "\n")
      resolved_path <- NULL

	  if (!is.null(path_to_check) && path_ok(path_to_check)) {
        # FOUND: Return as-is. Do NOT re-normalize, as it breaks UNC/Encoding on Windows.
        resolved_path <- path_to_check
      } else {
        cat("[RESOLVE] Stored path missing for", nm %||% key, "- attempting rehydrate\n")
        recovered <- rehydrate_missing_path(c(nm, key, arg, base_arg, path_base))
        if (!is.null(recovered) && path_ok(recovered)) {
          resolved_path <- helpers_mcp_tools$normalize_excel_path(recovered)
          helpers_mcp_tools$update_session_file_path(session, c(key, nm), resolved_path)
          file_obj$path <- resolved_path
          file_obj$datapath <- resolved_path
          all_files[[key]] <- file_obj
        } else {
          cat("[RESOLVE] Path rehydrate failed for", nm %||% key, "\n")
        }
      }

      if (!is.null(resolved_path)) {
        display_val <- nm %||% basename(resolved_path)
        return(list(ok = TRUE,
                    path = resolved_path,
                    display = display_val))
      }
    }
  } else {
    cat("[RESOLVE] No files in session registry!\n")
  }

  # --- 2) Global registry (per-user) ---------------------------------------
  # Look into the JSON index created by global_register_file()
  idx_path <- getOption("mergen.index_path")
  uid <- NULL
  if (!is.null(session) && !is.null(session$userData$user_id)) {
    uid <- as.character(session$userData$user_id)
  } else if (exists("current_user_id", envir = .GlobalEnv)) {
    # fallback if available in global env
    uid <- as.character(get("current_user_id", envir = .GlobalEnv))
  }

  if (!is.null(idx_path) && file.exists(idx_path)) {
    idx <- jsonlite::read_json(idx_path, simplifyVector = TRUE)

    # 2a) per-user bucket (preferred)
    if (!is.null(uid) && !is.null(idx[[uid]])) {
      p <- idx[[uid]][[tolower(base_arg)]]
      if (is.list(p) && !is.null(p$path)) p <- p$path   # NEW: unwrap {path, display}
      if (!is.null(p) && path_ok(p)) {
        resolved_path <- helpers_mcp_tools$normalize_excel_path(p)
        return(list(ok = TRUE, path = resolved_path, display = basename(p)))
      }
    }
    # 2b) legacy flat
    p2 <- idx[[tolower(base_arg)]]
    if (is.list(p2) && !is.null(p2$path)) p2 <- p2$path  # NEW
    if (!is.null(p2) && path_ok(p2)) {
      resolved_path <- helpers_mcp_tools$normalize_excel_path(p2)
      return(list(ok = TRUE, path = resolved_path, display = basename(p2)))
    }
    # 2c) cross-bucket (first match)
    if (length(idx)) {
      for (bucket_name in names(idx)) {
        bucket <- idx[[bucket_name]]
        if (is.list(bucket)) {
          p3 <- bucket[[tolower(base_arg)]]
          if (is.list(p3) && !is.null(p3$path)) p3 <- p3$path  # NEW
          if (!is.null(p3) && path_ok(p3)) {
            resolved_path <- helpers_mcp_tools$normalize_excel_path(p3)
            return(list(ok = TRUE, path = resolved_path, display = basename(p3)))
          }
        }
      }
    }
  }

  # --- 3) Fallback directories (only if arg does NOT contain a slash) ----
  # (renumbered since we inserted the global registry above)
  if (!grepl("[/\\\\]", arg)) {
    fb <- c(
      getOption("mergen.files_root"),
      getOption("mergen.mcp_base_dir")
    )
    fb <- fb[!is.null(fb) & nzchar(fb)]
    # also the per-user subfolder under the MCP base, if available
    if (!is.null(uid)) {
      mcp_base <- getOption("mergen.mcp_base_dir")
      if (!is.null(mcp_base) && nzchar(mcp_base)) {
        fb <- c(file.path(mcp_base, paste0("user_", uid)), fb)
      }
    }
	for (base_dir in unique(fb)) {
      candidate <- file.path(base_dir, base_arg)
      if (path_ok(candidate)) {
        resolved_path <- candidate # Return as-is
        return(list(ok = TRUE, path = resolved_path, display = basename(candidate)))
      }
    }
  }

  # --- 3) (Optional) global registry by basename ----------------------
  # If you have a global lookup, try it by basename without failing if absent.
  if (exists("global_lookup_file", mode = "function")) {
    p <- try(global_lookup_file(base_arg), silent = TRUE)
    if (!inherits(p, "try-error") && is.character(p) && nzchar(p) && path_ok(p)) {
      cat("[RESOLVE] Global registry hit ->", p, "\n")
      resolved_path <- helpers_mcp_tools$normalize_excel_path(p)
      return(list(ok = TRUE, path = resolved_path, display = basename(p)))
    }
  }

  # --- 4) Not found ----------------------------------------------------
  known <- if (!is.null(all_files)) {
    unique(vapply(all_files, function(x) x$name %||% "?", character(1)))
  } else character(0)

  cat("[RESOLVE] NOT FOUND! Available files:", paste(known, collapse = ", "), "\n")
  list(
    ok = FALSE,
    error = sprintf("Dosya '%s' bulunamadı.\nMevcut dosyalar: %s",
                    arg, if (length(known)) paste(known, collapse = ", ") else "(hiç dosya yok)")
  )
}

# ============================
# Dependency checks (DuckDB)
# ============================
helpers_mcp_tools$safe_has_duckdb <- function() {
  requireNamespace("duckdb", quietly = TRUE)
}

# ============================
# Argument normalizer
# ============================
helpers_mcp_tools$normalize_args <- function(args) {
  if (!is.list(args)) args <- list()

  # file name synonyms
  if (is.null(args$file_name)) {
    args$file_name <- args$filename %||% args$fileId %||% args$file %||% args$dosya
  }
  # column synonyms
  if (is.null(args$column)) {
    args$column <- args$col %||% args$field %||% args$kolon %||% args$column_name
  }
  # sql synonyms
  if (is.null(args$sql)) {
    args$sql <- args$query %||% args$sorgu
  }

  args
}

# Back-compat dotted alias (some earlier code may call this)
.normalize_args <- helpers_mcp_tools$normalize_args

# ============================
# Tool 1: analyze_uploaded_file
# ============================
helpers_mcp_tools$analyze_uploaded_file <- function(file_name, session = NULL) {
  file_name <- helpers_mcp_tools$auto_file_name(file_name, session)
  res <- helpers_mcp_tools$resolve_file_argument(file_name, session)
  if (!isTRUE(res$ok)) return(list(error = res$error))

  path <- res$path

  df <- tryCatch({
    data.table::as.data.table(helpers_mcp_tools$safe_read_excel_table(path))
  }, error = function(e) e)
  
  if (inherits(df, "error")) {
    return(list(error = sprintf("Excel dosyası okunamadı: %s — %s", basename(path), df$message)))
  }

  n_rows <- nrow(df)
  n_cols <- ncol(df)
  cols   <- names(df)

  types <- vapply(df, function(x) class(x)[1], character(1))

  num_cols <- names(df)[vapply(df, is.numeric, logical(1))]
  num_summary <- lapply(num_cols, function(cn) {
    vals <- df[[cn]]
    list(
      sütun    = cn,
      ortalama = mean(vals, na.rm = TRUE),
      medyan   = median(vals, na.rm = TRUE),
      minimum  = suppressWarnings(min(vals, na.rm = TRUE)),
      maksimum = suppressWarnings(max(vals, na.rm = TRUE)),
      toplam   = sum(vals, na.rm = TRUE),
      sayi     = sum(!is.na(vals))
    )
  })

  list(
    dosya_adı        = basename(path),
    satır_sayısı     = n_rows,
    sütun_sayısı     = n_cols,
    sütun_isimleri   = cols,
    sütun_tipleri    = unname(types),
    sayısal_sütunlar = num_cols,
    sayısal_özet     = num_summary
  )
}

# ==================================
# Tool 2: get_column_statistics
# ==================================
helpers_mcp_tools$get_column_statistics <- function(file_name, column, session = NULL) {
  file_name <- helpers_mcp_tools$auto_file_name(file_name, session)
  res <- helpers_mcp_tools$resolve_file_argument(file_name, session)
  if (!isTRUE(res$ok)) return(list(error = res$error))
  if (is.null(column) || !nzchar(column)) return(list(error = "column parametresi boş"))

  path <- res$path
  dt <- tryCatch({
    data.table::as.data.table(helpers_mcp_tools$safe_read_excel_table(path))
  }, error = function(e) e)
  
  if (inherits(dt, "error")) {
    return(list(error = sprintf("Excel dosyası okunamadı: %s — %s", basename(path), dt$message)))
  }

  if (!(column %in% names(dt))) {
    return(list(error = sprintf("Sütun bulunamadı: %s. Mevcut sütunlar: %s",
                                column, paste(names(dt), collapse = ", "))))
  }

  vec <- dt[[column]]

  if (is.numeric(vec)) {
    list(
      dosya_adı  = basename(path),
      sütun      = column,
      tür        = "numeric",
      sayi       = sum(!is.na(vec)),
      ortalama   = mean(vec, na.rm = TRUE),
      medyan     = median(vec, na.rm = TRUE),
      minimum    = suppressWarnings(min(vec, na.rm = TRUE)),
      maksimum   = suppressWarnings(max(vec, na.rm = TRUE)),
      toplam     = sum(vec, na.rm = TRUE),
      stdev      = sd(vec, na.rm = TRUE),
      null_sayısı = sum(is.na(vec))
    )
  } else {
    tb   <- sort(table(vec, useNA = "ifany"), decreasing = TRUE)
    top5 <- head(tb, 5)
    list(
      dosya_adı        = basename(path),
      sütun            = column,
      tür              = "categorical",
      benzersiz_deger  = length(unique(vec)),
      ilk_5_deger      = as.list(top5),
      null_sayısı      = sum(is.na(vec))
    )
  }
}

# ==================================
# Tool 3: sql_query_uploaded_file
# ==================================
helpers_mcp_tools$sql_query_uploaded_file <- function(file_name, sql, session = NULL) {
  if (!helpers_mcp_tools$safe_has_duckdb()) {
    return(list(error = "DuckDB yüklü değil. Lütfen install.packages('duckdb') çalıştırın."))
  }

  file_name <- helpers_mcp_tools$auto_file_name(file_name, session)
  res <- helpers_mcp_tools$resolve_file_argument(file_name, session)
  if (!isTRUE(res$ok)) return(list(error = res$error))
  if (is.null(sql) || !nzchar(sql)) return(list(error = "sql parametresi boş"))

  path <- res$path
  dt <- tryCatch({
    data.table::as.data.table(helpers_mcp_tools$safe_read_excel_table(path))
  }, error = function(e) e)
  
  if (inherits(dt, "error")) {
    return(list(error = sprintf("Excel dosyası okunamadı: %s — %s", basename(path), dt$message)))
  }

  # Normalize date/time as character so DuckDB doesn't choke on write
  for (nm in names(dt)) {
    if (inherits(dt[[nm]], "POSIXt") || inherits(dt[[nm]], "Date")) {
      dt[[nm]] <- as.character(dt[[nm]])
    }
  }

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)

  DBI::dbWriteTable(con, "t", as.data.frame(dt), temporary = TRUE, overwrite = TRUE)

  # Tolerate different quoting styles
  q <- sql
  q <- gsub("`", "\"", q, fixed = TRUE)
  q <- gsub("\\[", "\"", q)
  q <- gsub("\\]", "\"", q)

  ans <- tryCatch(DBI::dbGetQuery(con, q), error = function(e) e)
  if (inherits(ans, "error")) {
    return(list(
      error = sprintf("SQL çalıştırılamadı: %s", ans$message),
      hint  = "Tablo adı 't'. Sütun adlarını tam yazın; metinleri tek tırnakla yazın: Department = 'IT'."
    ))
  }

  preview <- ans
  if (nrow(preview) > 50) preview <- head(preview, 50)

  list(
    dosya_adı      = basename(path),
    satır_sayısı   = nrow(ans),
    sütun_sayısı   = ncol(ans),
    sonuç_önizleme = preview
  )
}

# ==================================
# Tool 4: prepare_chart_data  (NEW)
# ==================================
helpers_mcp_tools$prepare_chart_data <- function(
  file_name,
  chart_type,
  x = NULL,
  y = NULL,
  group = NULL,
  agg = NULL,
  bins = NULL,
  top_n = NULL,
  # --- new rendering options ---
  stack = NULL,
  donut = NULL,
  orientation = NULL,
  smooth = NULL,
  # ---------------------------------------------------
  filter_sql = NULL,
  limit = 5000,
  session = NULL
) {
  file_name <- helpers_mcp_tools$auto_file_name(file_name, session)
  # Normalize and hard-block box/boxplot (no longer supported)
  chart_type <- tolower(chart_type %||% "")
  if (chart_type %in% c("box","boxplot","box_plot","bx")) chart_type <- "hist"

  # 1) resolve file
  res <- helpers_mcp_tools$resolve_file_argument(file_name, session)
  if (!isTRUE(res$ok)) return(list(error = res$error, ok = FALSE))

  # 2) read
  dt <- tryCatch({
    helpers_mcp_tools$safe_read_table_generic(res$path)
  }, error = function(e) e)
  if (inherits(dt, "error")) {
    return(list(error = sprintf("Dosya okunamadı: %s — %s", basename(res$path), dt$message), ok = FALSE))
  }

  # --- ensure mappings for pie/donut: x must exist (categorical preferred) ---
  if (tolower(chart_type) %in% c("pie","donut") && (is.null(x) || !nzchar(x))) {
    cat_cols <- names(dt)[vapply(dt, function(v) is.character(v) || is.factor(v), logical(1))]
    if (length(cat_cols)) {
      x <- cat_cols[1]
    } else {
      # fallback: use first column
      x <- names(dt)[1]
    }
  }

  # 3) optional filter with DuckDB WHERE
  if (!is.null(filter_sql) && nzchar(filter_sql) && helpers_mcp_tools$safe_has_duckdb()) {
    con <- DBI::dbConnect(duckdb::duckdb(), dbdir=":memory:")
    on.exit(try(DBI::dbDisconnect(con, shutdown=TRUE), silent=TRUE), add=TRUE)
    DBI::dbWriteTable(con, "t", as.data.frame(dt), temporary = TRUE, overwrite = TRUE)

    q <- sprintf('SELECT * FROM t WHERE %s', filter_sql)
    q <- gsub("`", "\"", q, fixed = TRUE)
    q <- gsub("\\[", "\"", q); q <- gsub("\\]", "\"", q)

    filt <- tryCatch(DBI::dbGetQuery(con, q), error = function(e) e)
    if (!inherits(filt, "error")) dt <- data.table::as.data.table(filt)
  }

  # 4) thin to only needed columns
  cols <- unique(na.omit(c(x, y, group)))
  if (!length(cols)) {
    # let ChartLab decide mapping; send sample only
    subset_dt <- dt
  } else {
    missing <- setdiff(cols, names(dt))
    if (length(missing)) {
      return(list(
        error = sprintf("Sütun(lar) bulunamadı: %s. Mevcut: %s", paste(missing, collapse = ", "), paste(names(dt), collapse = ", ")),
        ok = FALSE
      ))
    }
    subset_dt <- dt[, ..cols]
  }

  # 5) limit rows and coerce time cols (ChartLab will format)
  if (is.finite(limit) && nrow(subset_dt) > limit) subset_dt <- head(subset_dt, limit)
  for (nm in names(subset_dt)) {
    if (inherits(subset_dt[[nm]], "POSIXt")) next
    if (inherits(subset_dt[[nm]], "Date")) next
    # leave as-is; ChartLab will handle coercions cautiously
  }

  schema <- vapply(subset_dt, function(z) class(z)[1], character(1))

  # 6) build chart spec payload
  list(
    ok = TRUE,
    `__mcp_plot` = TRUE,        # <--- GLUE FLAG (server will route to ChartLab)
    file = basename(res$path),
    chart = list(
      type = tolower(chart_type),             # "hist"|"bar"|"line"|"scatter"|"box"|"area"
      mapping = list(x = x, y = y, group = group),
      params = list(
        agg = agg, bins = bins, top_n = top_n,
        stack = stack, donut = donut, orientation = orientation, smooth = smooth
      ),
      data = as.data.frame(subset_dt),
      schema = as.list(schema),
      n = nrow(subset_dt)
    ),
    message = "Grafik verileri hazırlandı; ChartLab'a iletildi."
  )
}

# ============================
# Tool router
# ============================
helpers_mcp_tools$execute_parsed_tool <- function(tc, session = NULL) {
  fn   <- tc$function_name %||% tc$name %||% tc$tool %||% tc$action
  args <- helpers_mcp_tools$normalize_args(tc$arguments %||% tc$parameters %||% list())

  if (is.null(fn) || !nzchar(fn)) return(list(error = "Araç adı boş"))

	switch(tolower(fn),
	  "analyze_uploaded_file"   = helpers_mcp_tools$analyze_uploaded_file(args$file_name, session),
	  "get_column_statistics"   = helpers_mcp_tools$get_column_statistics(args$file_name, args$column, session),
	  "get_column_stats"        = helpers_mcp_tools$get_column_statistics(args$file_name, args$column, session), # alias
	  "sql_query_uploaded_file" = helpers_mcp_tools$sql_query_uploaded_file(args$file_name, args$sql, session),
	  "prepare_chart_data"      = helpers_mcp_tools$prepare_chart_data(
		file_name  = args$file_name,
		chart_type = args$chart_type,
		x          = args$x %||% args$xlabel %||% args$x_col,
		y          = args$y %||% args$ylabel %||% args$y_col,
		group      = args$group %||% args$color %||% args$hue,
		agg        = args$agg,
		bins       = args$bins,
		top_n      = args$top_n,
		filter_sql = args$filter_sql,
		limit      = args$limit %||% 5000,
		session    = session
	  ),
	  # --- RData Lake tool'ları ---
	  "rdata_search"  = if (exists("helpers_rdata_lake", inherits = TRUE))
						  helpers_rdata_lake$execute_tool("rdata_search", args) else list(error="RData Lake modülü yok."),
	  "rdata_sql"     = if (exists("helpers_rdata_lake", inherits = TRUE))
						  helpers_rdata_lake$execute_tool("rdata_sql", args) else list(error="RData Lake modülü yok."),
	  "rdata_metrics" = if (exists("helpers_rdata_lake", inherits = TRUE))
						  helpers_rdata_lake$execute_tool("rdata_metrics", args) else list(error="RData Lake modülü yok."),
	  {
		list(error = sprintf("Bilinmeyen araç: %s", fn))
	  }
	)
}

# ============================
# OpenAI tools schema
# ============================
helpers_mcp_tools$get_openai_tools <- function(session = NULL) {
  list(
    tools = list(
      list(
        type = "function",
        `function` = list(
          name = "analyze_uploaded_file",
          description = "Yüklü Excel dosyasının temel özetini çıkarır (satır, sütun, sütun adları, sayısal özet).",
          parameters = list(
            type = "object",
            properties = list(
              file_name = list(type = "string",
                               description = "Sohbetteki dosya jetonu (file_123...) veya gerçek dosya adı (dummy.xlsx).")
            ),
            required = list("file_name")
          )
        )
      ),
      list(
        type = "function",
        `function` = list(
          name = "get_column_statistics",
          description = "Belirli bir sütunun istatistiklerini döndürür (numeric: ort, medyan, min, max; categorical: frekans).",
          parameters = list(
            type = "object",
            properties = list(
              file_name = list(type = "string", description = "Dosya jetonu veya adı."),
              column    = list(type = "string", description = "İstatistikleri istenen sütun adı.")
            ),
            required = list("file_name", "column")
          )
        )
      ),
      list(
        type = "function",
        `function` = list(
          name = "sql_query_uploaded_file",
          description = "Karma/nested analizler için SQL çalıştırır. Tablo adı: t. Örnek: SELECT AVG(Salary) FROM t WHERE Department='IT';",
          parameters = list(
            type = "object",
            properties = list(
              file_name = list(type = "string", description = "Dosya jetonu veya adı."),
              sql       = list(type = "string", description = "DuckDB uyumlu SQL; tablo adı 't'.")
            ),
            required = list("file_name", "sql")
          )
        )
      ),
      list(
        type = "function",
        `function` = list(
          name = "prepare_chart_data",
          description = "Grafik için veriyi hazırlar ve bir 'chart spec' döndürür. Tablo adı: t. Excel/CSV/RDS/RData desteklenir.",
          parameters = list(
            type = "object",
            properties = list(
              file_name  = list(type = "string", description = "Dosya jetonu veya yolu/adı."),
              chart_type = list(type = "string",
					description = "One of: hist | bar | line | scatter | area | pie | donut | pareto. (bar supports orientation + stacking; line/area support smoothing)"),
              x          = list(type = "string", description = "X ekseni sütunu (opsiyonel)"),
              y          = list(type = "string", description = "Y ekseni sütunu (opsiyonel)"),
              group      = list(type = "string", description = "Renk/seri grubu (opsiyonel)"),
              agg        = list(type = "string", description = "sum|mean|median|min|max (opsiyonel)"),
              bins       = list(type = "integer", description = "Histogram için kutu sayısı (opsiyonel)"),
              top_n      = list(type = "integer", description = "Bar grafikte en çok görülen ilk N (opsiyonel)"),
			  stack       = list(type = "string",  description = "Stacking mode for bar/area: none|normal|percent (optional)"),
              donut       = list(type = "boolean", description = "If true with pie, renders a donut (optional)"),
              orientation = list(type = "string",  description = "Bar/pareto orientation: v|vertical|h|horizontal (optional)"),
              smooth      = list(type = "boolean", description = "If true, line→spline and area→areaspline (optional)"),
              filter_sql = list(type = "string", description = "WHERE klozu (opsiyonel). Ör: Department='IT' AND Salary>1000"),
              limit      = list(type = "integer", description = "Satır sınırı (varsayılan 5000)")
            ),
            required = list("file_name", "chart_type")
          )
        )
      )
    )
  )
}

# ============================
# Tool-use instruction prompt
# ============================
helpers_mcp_tools$get_mcp_tools_prompt <- function() {
  paste(
    "Aşağıdaki araçları çağırabilirsin. JSON ile **tek bir araç** çağır; ardından araç çıktısına göre Türkçe cevap ver.",
    "",
    "Araçlar:",
    "1) analyze_uploaded_file(file_name) — satır/sütun sayısı, sütun adları, sayısal özet.",
    "2) get_column_statistics(file_name, column) — tek sütun için istatistik.",
    "3) sql_query_uploaded_file(file_name, sql) — karma/nested mantık için SQL (filtrele → grupla → sırala → LIMIT → toplam/ortalama). Tablo adı 't'.",
	"4) prepare_chart_data(file_name, chart_type, x, y, group, agg, bins, top_n, filter_sql, limit) — grafik için veri ve tanım üretir.",
	"- chart_type: hist | bar | line | scatter | area | pie | donut | pareto; opsiyonlar: stack, donut, orientation, smooth",
    "",
    "Kurallar:",
    "- Sadece araç çağrısı gerekiyorsa başka açıklama yazma.",
    "- JSON örneği: {\"name\":\"sql_query_uploaded_file\",\"arguments\":{\"file_name\":\"dummy.xlsx\",\"sql\":\"SELECT AVG(Salary) FROM t\"}}",
    "- Sütun adlarını birebir kullan, metinlerde tek tırnak: Department='IT'.",
    "- Karma sorgularda her zaman **sql_query_uploaded_file** kullan.",
    "- Planlama/düşünme metni yazma (örn. 'We need to call…', 'We will call…').",
	"- Grafik/çizim gerektiğinde **prepare_chart_data** kullan; çıktı ChartLab tarafından çizilir.",
    sep = "\n"
  )
}

# ============================
# Parse textual tool calls
# ============================
helpers_mcp_tools$parse_tool_calls_from_text <- function(text) {
  if (is.null(text) || !nzchar(text)) return(list())
  out <- list()

  # 1) <tool_call> ... </tool_call>
  tc_blocks <- gregexpr("<tool_call>(.*?)</tool_call>", text, perl = TRUE)
  if (tc_blocks[[1]][1] != -1) {
    blocks <- regmatches(text, tc_blocks)[[1]]
    blocks <- gsub("^<tool_call>|</tool_call>$", "", blocks)
    for (blk in blocks) {
      try({
        obj  <- jsonlite::fromJSON(blk, simplifyVector = FALSE)
        fn   <- obj$name %||% obj$tool %||% obj$action
        args <- obj$arguments %||% obj$parameters %||% list()
        if (is.character(args)) {
          args <- tryCatch(jsonlite::fromJSON(args, simplifyVector = FALSE), error = function(e) list())
        }
        out[[length(out) + 1]] <- list(function_name = fn, arguments = args)
      }, silent = TRUE)
    }
  }

  # 2) Inline JSON {"name|tool|action": "...", "arguments|parameters": {...}}
  json_pat <- paste0(
    "\\{\\s*\"(tool|name|action)\"\\s*:\\s*\"[^\"]+\"[\\s\\S]*?",
    "\"(arguments|parameters)\"\\s*:\\s*\\{[\\s\\S]*?\\}\\s*\\}"
  )
  rgx <- gregexpr(json_pat, text, perl = TRUE)
  if (rgx[[1]][1] != -1) {
    objs <- regmatches(text, rgx)[[1]]
    for (o in objs) {
      try({
        obj  <- jsonlite::fromJSON(o, simplifyVector = FALSE)
        fn   <- obj$name %||% obj$tool %||% obj$action
        args <- obj$arguments %||% obj$parameters %||% list()
        if (is.character(args)) {
          args <- tryCatch(jsonlite::fromJSON(args, simplifyVector = FALSE), error = function(e) list())
        }
        out[[length(out) + 1]] <- list(function_name = fn, arguments = args)
      }, silent = TRUE)
    }
  }

  # 3) Whole message is JSON
  if (length(out) == 0) {
    try({
      obj <- jsonlite::fromJSON(text, simplifyVector = FALSE)
      if (is.list(obj) && (!is.null(obj$name) || !is.null(obj$tool) || !is.null(obj$action))) {
        fn   <- obj$name %||% obj$tool %||% obj$action
        args <- obj$arguments %||% obj$parameters %||% list()
        if (is.character(args)) {
          args <- tryCatch(jsonlite::fromJSON(args, simplifyVector = FALSE), error = function(e) list())
        }
        out[[length(out) + 1]] <- list(function_name = fn, arguments = args)
      }
    }, silent = TRUE)
  }

  out
}

# ============================
# Public wrappers (used by global.R)
# ============================
get_openai_tools              <- function(session = NULL) helpers_mcp_tools$get_openai_tools(session)
get_mcp_tools_prompt          <- function()               helpers_mcp_tools$get_mcp_tools_prompt()
parse_tool_calls_from_text    <- function(x)              helpers_mcp_tools$parse_tool_calls_from_text(x)
execute_parsed_tool           <- function(tc, session=NULL) helpers_mcp_tools$execute_parsed_tool(tc, session)
register_session_file         <- function(session, token, path, nm=NULL) helpers_mcp_tools$register_uploaded_file(session, token, path, nm)
reset_session_file_registry   <- function(session = NULL) helpers_mcp_tools$reset_session_file_registry(session)
environment(helpers_mcp_tools$analyze_uploaded_file)   <- helpers_mcp_tools
environment(helpers_mcp_tools$get_column_statistics)   <- helpers_mcp_tools
environment(helpers_mcp_tools$sql_query_uploaded_file) <- helpers_mcp_tools
environment(helpers_mcp_tools$prepare_chart_data)      <- helpers_mcp_tools
environment(helpers_mcp_tools$resolve_file_argument)   <- helpers_mcp_tools
environment(helpers_mcp_tools$normalize_excel_path)    <- helpers_mcp_tools
environment(helpers_mcp_tools$safe_read_excel_table)   <- helpers_mcp_tools
environment(helpers_mcp_tools$safe_read_table_generic) <- helpers_mcp_tools
environment(helpers_mcp_tools$get_default_file_name)   <- helpers_mcp_tools
environment(helpers_mcp_tools$auto_file_name)          <- helpers_mcp_tools
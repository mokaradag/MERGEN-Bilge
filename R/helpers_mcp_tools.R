# R/helpers_mcp_tools.R

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

# helpers_files.R'deki tanımı kullan (daha kapsamlı)
if (!exists("path_exists_relaxed", envir = helpers_mcp_tools, inherits = FALSE)) {
  # Global ortamdaki fonksiyonu kullan
  if (exists("path_exists_relaxed", envir = globalenv(), inherits = TRUE)) {
    assign(
      "path_exists_relaxed",
      get("path_exists_relaxed", envir = globalenv(), inherits = TRUE),
      envir = helpers_mcp_tools
    )
  }
}

# Araç yardımcıları bazı worker / ayrı yürütme bağlamlarında global ortama
# beklenen sırayla gelmeyebilir. Bu nedenle kritik yol yardımcıları için
# burada yerel ve kendine yeterli yedek tanımlar sağlanır.
if (!exists("path_exists_relaxed", envir = helpers_mcp_tools, inherits = FALSE)) {
  helpers_mcp_tools$path_exists_relaxed <- function(path) {
    if (is.null(path) || length(path) == 0) return(FALSE)

    candidate <- as.character(path[1])
    if (!nzchar(candidate)) return(FALSE)

    cand_slash <- gsub("\\\\", "/", candidate, fixed = TRUE)

    variants <- unique(trimws(Filter(nzchar, c(
      candidate,
      cand_slash,
      sub("^//\\?/UNC", "//", cand_slash, perl = TRUE),
      sub("^//\\?/", "//", cand_slash, perl = TRUE),
      if (grepl("^/[^/]", cand_slash)) paste0("/", cand_slash) else NULL,
      gsub("/", "\\\\", cand_slash, fixed = TRUE)
    ))))

    for (chk in variants) {
      if (tryCatch(isTRUE(file.exists(chk)), error = function(e) FALSE)) return(TRUE)
      if (tryCatch(isTRUE(fs::file_exists(chk)), error = function(e) FALSE)) return(TRUE)

      chk_utf8 <- tryCatch(enc2utf8(chk), error = function(e) chk)
      if (tryCatch(isTRUE(file.exists(chk_utf8)), error = function(e) FALSE)) return(TRUE)
      if (tryCatch(isTRUE(fs::file_exists(chk_utf8)), error = function(e) FALSE)) return(TRUE)
    }

    FALSE
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

if (exists("resolve_readable_path", envir = globalenv(), inherits = TRUE)) {
  assign(
    "resolve_readable_path",
    get("resolve_readable_path", envir = globalenv(), inherits = TRUE),
    envir = helpers_mcp_tools
  )
}

if (!exists("resolve_readable_path", envir = helpers_mcp_tools, inherits = FALSE)) {
  helpers_mcp_tools$resolve_readable_path <- function(path) {
    if (is.null(path) || !nzchar(path)) return(path)

    p <- as.character(path[1])

    if (tryCatch(isTRUE(file.exists(p)), error = function(e) FALSE)) return(p)

    p_bs <- gsub("/", "\\\\", p, fixed = TRUE)
    if (tryCatch(isTRUE(file.exists(p_bs)), error = function(e) FALSE)) return(p_bs)

    p_fwd <- gsub("\\\\", "/", p, fixed = TRUE)
    if (grepl("^/[^/]", p_fwd)) {
      p_unc <- paste0("/", p_fwd)
      if (tryCatch(isTRUE(file.exists(p_unc)), error = function(e) FALSE)) return(p_unc)

      p_unc_bs <- gsub("/", "\\\\", p_unc, fixed = TRUE)
      if (tryCatch(isTRUE(file.exists(p_unc_bs)), error = function(e) FALSE)) return(p_unc_bs)
    }

    p
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
      # [FIX] Libxls mismatch recovery
      if (grepl("libxls error", conditionMessage(e), ignore.case = TRUE)) {
         return(readxl::read_xlsx(path_prepared, sheet = sheet, col_names = TRUE))
      }

      # Fallback: Try ShortPathName if not already tried (fix for Turkish chars)
      if (.Platform$OS.type == "windows") {
         short_p <- tryCatch(utils::shortPathName(gsub("/", "\\\\", path_prepared)), error=function(x) NULL)
         if (!is.null(short_p) && nzchar(short_p)) {
            return(readxl::read_excel(short_p, sheet = sheet, col_names = TRUE))
         }
      }
	  
      # Linux/UTF-8 guard: re-encode path if translation failed
      if (grepl("unable to translate", conditionMessage(e), fixed = TRUE)) {
        utf8_path <- tryCatch(enc2utf8(path_prepared), error = function(x) path_prepared)
        if (!identical(utf8_path, path_prepared) && file.exists(utf8_path)) {
          return(readxl::read_excel(utf8_path, sheet = sheet, col_names = TRUE))
        }
      }
	  
      stop(e)
    })

    if (is.finite(n_max)) df <- head(df, n_max)
    df <- as.data.frame(df, stringsAsFactors = FALSE)
    if (anyNA(names(df)) || any(names(df) == "")) {
      names(df) <- paste0("X", seq_along(df))
    }
    names(df) <- make.unique(names(df), sep = "_")
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
    names(df) <- make.unique(nms, sep = "_")
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

helpers_mcp_tools$create_md_table <- function(df) {
  if (is.null(df) || nrow(df) == 0) return("_Veri yok_")
  
  # Ensure clean UTF-8 character data (prevents S\u00fc tun style escapes)
  safe_df <- as.data.frame(lapply(df, function(x) {
    if (is.numeric(x)) return(format(x, big.mark = ".", decimal.mark = ",", scientific = FALSE, trim = TRUE))
    if (is.logical(x)) return(ifelse(x, "TRUE", "FALSE"))
    if (inherits(x, "Date") || inherits(x, "POSIXt")) return(as.character(x))
    as.character(x)
  }), stringsAsFactors = FALSE)

  safe_df[] <- lapply(safe_df, function(col) tryCatch(enc2utf8(col), error = function(e) col))

  cols <- tryCatch(enc2utf8(names(safe_df)), error = function(e) names(safe_df))
  header <- paste0("| ", paste(cols, collapse = " | "), " |")
  sep    <- paste0("| ", paste(rep("---", length(cols)), collapse = " | "), " |")
  
  rows <- vapply(seq_len(nrow(safe_df)), function(i) {
    paste0("| ", paste(safe_df[i, ], collapse = " | "), " |")
  }, character(1))
  
  paste(c(header, sep, rows), collapse = "\n")
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
  
  if (!helpers_mcp_tools$path_exists_relaxed(normalized_path)) {
    cat("[RESOLVE] Skip registry; path missing ->", normalized_path, "\n")
    return(invisible(FALSE))
  }
  
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
  
  cat(
    "[RESOLVE][env] has_path_exists_relaxed=",
    exists("path_exists_relaxed", envir = helpers_mcp_tools, inherits = FALSE),
    " has_resolve_readable_path=",
    exists("resolve_readable_path", envir = helpers_mcp_tools, inherits = FALSE),
    "\n",
    sep = ""
  )

  resolve_existing_candidate <- function(candidate) {
    if (is.null(candidate) || !nzchar(candidate)) return(NULL)

    cand <- as.character(candidate[1])

    variants <- unique(Filter(nzchar, c(
      cand,
      tryCatch(enc2utf8(cand), error = function(e) cand),
      gsub("\\\\", "/", cand, fixed = TRUE),
      gsub("/", "\\\\", cand, fixed = TRUE)
    )))

    readable_variants <- unique(vapply(
      variants,
      function(v) {
        tryCatch(
          helpers_mcp_tools$resolve_readable_path(v),
          error = function(e) v
        )
      },
      character(1)
    ))
    variants <- unique(c(variants, readable_variants))

    for (v in variants) {
      relaxed_ok <- tryCatch(
        isTRUE(helpers_mcp_tools$path_exists_relaxed(v)),
        error = function(e) FALSE
      )

      if (!relaxed_ok) next

      v2 <- tryCatch(
        helpers_mcp_tools$resolve_readable_path(v),
        error = function(e) v
      )
      if (!is.null(v2) && nzchar(v2)) return(v2)

      return(v)
    }

    NULL
  }
  
  # Helper to check existence via base or fs
  path_ok_robust <- function(candidate) {
    !is.null(resolve_existing_candidate(candidate))
  }

  path_ok <- function(candidate) {
    path_ok_robust(candidate)
  }
  
  # --- NEW: 0) Absolute path fast-path -------------------------------
  # Accept "C:/.../file.xlsx" or "/var/tmp/file.xlsx" straight away.
  is_abs <- grepl("^([A-Za-z]:)?[\\/]", arg)
  if (is_abs) {
    # Use the robust normalizer immediately to handle UNC/Encoding
    p <- resolve_existing_candidate(arg)
    if (!is.null(p)) {
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

        user_files <- tryCatch(
          list.files(user_dir, full.names = TRUE, recursive = FALSE, include.dirs = FALSE),
          error = function(e) character(0)
        )

        if (length(user_files) > 0) {
          for (tok in tokens) {
            tok_base <- tolower(basename(tok))
            suffix_hits <- user_files[
              tolower(basename(user_files)) == tok_base |
              endsWith(tolower(basename(user_files)), paste0("_", tok_base))
            ]

            if (length(suffix_hits) > 0) {
              recovered <- suffix_hits[1]
              if (path_ok(recovered)) {
                cat("[RESOLVE] Missing path recovered via user_dir suffix match ->", recovered, "\n")
                return(recovered)
              }
            }
          }

          for (tok in tokens) {
            tok_ext <- tolower(tools::file_ext(tok))
            if (!nzchar(tok_ext)) next

            ext_hits <- user_files[tolower(tools::file_ext(user_files)) == tok_ext]

            if (length(ext_hits) == 1) {
              recovered <- ext_hits[1]
              if (path_ok(recovered)) {
                cat("[RESOLVE] Missing path recovered via unique extension match ->", recovered, "\n")
                return(recovered)
              }
            }
          }
        }
      }

      NULL
    }
	
    for (key in names(all_files)) {
      file_obj <- all_files[[key]]
      path_to_check <- file_obj$path %||% file_obj$datapath
      nm <- file_obj$name %||% file_obj$display %||% basename(path_to_check)
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

      existing_path <- resolve_existing_candidate(path_to_check)
      cat("[RESOLVE] Match ->", path_to_check, "Exists:", !is.null(existing_path), "\n")
      resolved_path <- NULL

      if (!is.null(existing_path)) {
        resolved_path <- existing_path
      } else {
        cat("[RESOLVE] Stored path missing for", nm %||% key, "- attempting rehydrate\n")
        recovered <- rehydrate_missing_path(c(nm, key, arg, base_arg, path_base))
        recovered_existing <- resolve_existing_candidate(recovered)
        if (!is.null(recovered_existing)) {
          resolved_path <- recovered_existing
          helpers_mcp_tools$update_session_file_path(session, c(key, nm), resolved_path)
          file_obj$path <- resolved_path
          file_obj$datapath <- resolved_path
          all_files[[key]] <- file_obj
        } else {
          cat("[RESOLVE] Path rehydrate failed for", nm %||% key, "\n")
        }
      }

      if (!is.null(resolved_path)) {
        display_val <- file_obj$display %||% nm %||% basename(resolved_path)
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
      entry <- idx[[uid]][[tolower(base_arg)]]
      p <- entry
      disp <- NULL
      if (is.list(entry)) {
        disp <- entry$display
        if (!is.null(entry$path)) p <- entry$path   # NEW: unwrap {path, display}
      }
      if (!is.null(p) && path_ok(p)) {
        resolved_path <- resolve_existing_candidate(p) %||% p
        display_val <- disp %||% basename(p)
        return(list(ok = TRUE, path = resolved_path, display = display_val))
      }
    }
    # 2b) legacy flat
    p2 <- idx[[tolower(base_arg)]]
    disp2 <- NULL
    if (is.list(p2)) {
      disp2 <- p2$display
      if (!is.null(p2$path)) p2 <- p2$path  # NEW
    }
    if (!is.null(p2) && path_ok(p2)) {
      resolved_path <- resolve_existing_candidate(p2) %||% p2
      return(list(ok = TRUE, path = resolved_path, display = disp2 %||% basename(p2)))
    }
    # 2c) cross-bucket (first match)
    if (length(idx)) {
      for (bucket_name in names(idx)) {
        bucket <- idx[[bucket_name]]
        if (is.list(bucket)) {
          p3 <- bucket[[tolower(base_arg)]]
          disp3 <- NULL
          if (is.list(p3)) {
            disp3 <- p3$display
            if (!is.null(p3$path)) p3 <- p3$path  # NEW
          }
          if (!is.null(p3) && path_ok(p3)) {
            resolved_path <- resolve_existing_candidate(p3) %||% p3
            return(list(ok = TRUE, path = resolved_path, display = disp3 %||% basename(p3)))
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
      resolved_path <- resolve_existing_candidate(p) %||% p
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
# Akıllı Sütun Eşleştirme ve Dosya Şeması
# ============================

# Dosya şemasını AI için okunabilir formatta çıkar
helpers_mcp_tools$extract_mcp_file_schema <- function(file_name, session = NULL) {
  file_name <- helpers_mcp_tools$auto_file_name(file_name, session)
  res <- helpers_mcp_tools$resolve_file_argument(file_name, session)
  if (!isTRUE(res$ok)) return(NULL)

  path <- res$path
  dt <- tryCatch({
    helpers_mcp_tools$safe_read_table_generic(path)
  }, error = function(e) NULL)

  if (is.null(dt) || nrow(dt) == 0) return(NULL)

  col_names <- names(dt)
  col_types <- vapply(dt, function(x) class(x)[1], character(1))

  # Her sütun için detaylı bilgi oluştur
  schema_lines <- vapply(seq_along(col_names), function(i) {
    cn <- col_names[i]
    ct <- col_types[i]
    vals <- dt[[cn]]

    type_tr <- switch(ct,
      "numeric" = "Sayısal",
      "integer" = "Tam Sayı",
      "character" = "Metin",
      "factor" = "Kategori",
      "Date" = "Tarih",
      "POSIXct" = "Tarih/Saat",
      "POSIXt" = "Tarih/Saat",
      "logical" = "Mantıksal",
      ct
    )

    if (ct %in% c("character", "factor")) {
      # Kategorik sütun: benzersiz değerleri göster
      unique_vals <- unique(as.character(vals))
      unique_vals <- unique_vals[!is.na(unique_vals)]
      unique_count <- length(unique_vals)

      if (unique_count <= 15) {
        sample_text <- paste(unique_vals, collapse = ", ")
      } else {
        sample_text <- paste0(paste(head(unique_vals, 10), collapse = ", "), " ... (toplam ", unique_count, " farklı değer)")
      }
      sprintf("  - **%s** (%s): Değerler = [%s]", cn, type_tr, sample_text)
    } else if (ct %in% c("numeric", "integer")) {
      # Sayısal sütun: istatistikler
      vals_num <- suppressWarnings(as.numeric(vals))
      vals_num <- vals_num[!is.na(vals_num)]
      if (length(vals_num) > 0) {
        mn <- round(min(vals_num), 2)
        mx <- round(max(vals_num), 2)
        avg <- round(mean(vals_num), 2)
        sprintf("  - **%s** (%s): Min=%s, Max=%s, Ort=%s", cn, type_tr, mn, mx, avg)
      } else {
        sprintf("  - **%s** (%s): Boş veya geçersiz", cn, type_tr)
      }
    } else {
      sprintf("  - **%s** (%s)", cn, type_tr)
    }
  }, character(1))

  display_name <- res$display %||% basename(path)

  paste0(
    "## DOSYA ŞEMASI: ", display_name, "\n",
    "**Toplam Satır:** ", nrow(dt), " | **Toplam Sütun:** ", ncol(dt), "\n\n",
    "### SÜTUNLAR (GERÇEK İSİMLER):\n",
    paste(schema_lines, collapse = "\n"),
    "\n\n**ÖNEMLİ:** Araç çağrılarında yukarıdaki GERÇEK sütun isimlerini kullan!"
  )
}

# Akıllı sütun eşleştirme: Türkçe prompt'tan İngilizce sütun adı bul
helpers_mcp_tools$find_matching_column <- function(search_term, available_columns, context = NULL) {
  if (is.null(search_term) || !nzchar(search_term)) return(NULL)
  if (is.null(available_columns) || length(available_columns) == 0) return(NULL)

  search_lower <- tolower(trimws(search_term))
  cols_lower <- tolower(available_columns)

  # 1. Tam eşleşme kontrolü
  exact_match <- which(cols_lower == search_lower)
  if (length(exact_match) > 0) return(available_columns[exact_match[1]])

  # 2. Kısmi eşleşme (sütun adı arama terimini içeriyor)
  partial_match <- which(grepl(search_lower, cols_lower, fixed = TRUE))
  if (length(partial_match) > 0) return(available_columns[partial_match[1]])

  # 3. Ters kısmi eşleşme (arama terimi sütun adını içeriyor)
  reverse_match <- which(vapply(cols_lower, function(c) grepl(c, search_lower, fixed = TRUE), logical(1)))
  if (length(reverse_match) > 0) return(available_columns[reverse_match[1]])

  # 4. Normalize edilmiş eşleşme (alt çizgi, tire, boşluk yok say)
  normalize <- function(s) {
    s <- tolower(s)
    s <- gsub("[_\\-\\s]+", "", s)
    s <- gsub("ı", "i", s)
    s <- gsub("ğ", "g", s)
    s <- gsub("ü", "u", s)
    s <- gsub("ş", "s", s)
    s <- gsub("ö", "o", s)
    s <- gsub("ç", "c", s)
    s
  }

  search_norm <- normalize(search_lower)
  cols_norm <- vapply(cols_lower, normalize, character(1))

  norm_match <- which(cols_norm == search_norm)
  if (length(norm_match) > 0) return(available_columns[norm_match[1]])

  # 5. Kelime kökü eşleştirme
  norm_partial <- which(grepl(search_norm, cols_norm, fixed = TRUE) |
                        vapply(cols_norm, function(c) grepl(c, search_norm, fixed = TRUE), logical(1)))
  if (length(norm_partial) > 0) return(available_columns[norm_partial[1]])

  # 6. Yaygın Türkçe-İngilizce eşleştirmeler (dinamik, hardcode değil)
  # AI'ın semantik anlayışına bırakıyoruz, burada sadece yaygın kısaltmalar
  common_patterns <- list(
    "dept|bolum|birim" = "department|dept|bolum|birim|unit",
    "maas|ucret|gelir|salary" = "salary|wage|income|pay|maas|ucret|gelir",
    "performans|perf|basari" = "performance|perf|score|rating|basari",
    "yas|age|yasi" = "age|yas|yasi|year",
    "isim|ad|name" = "name|isim|ad|adi",
    "tarih|date|gun" = "date|tarih|gun|day|time",
    "miktar|adet|sayi" = "count|amount|quantity|miktar|adet|sayi|number",
    "cinsiyet|gender" = "gender|sex|cinsiyet",
    "sure|saat|zaman|hour" = "hour|time|duration|sure|saat|zaman",
    "toplam|total|sum" = "total|sum|toplam"
  )

  for (pattern_group in names(common_patterns)) {
    if (grepl(pattern_group, search_norm, perl = TRUE)) {
      target_patterns <- unlist(strsplit(common_patterns[[pattern_group]], "\\|"))
      for (tp in target_patterns) {
        match_idx <- which(grepl(tp, cols_norm, fixed = TRUE))
        if (length(match_idx) > 0) return(available_columns[match_idx[1]])
      }
    }
  }

  # Eşleşme bulunamadı
  NULL
}

# Birden fazla sütun için akıllı eşleştirme
helpers_mcp_tools$find_columns_by_context <- function(dt, search_terms) {
  if (is.null(dt) || !is.data.frame(dt)) return(list())
  if (is.null(search_terms) || length(search_terms) == 0) return(list())

  available_columns <- names(dt)
  results <- list()

  for (term in search_terms) {
    found <- helpers_mcp_tools$find_matching_column(term, available_columns)
    if (!is.null(found)) {
      results[[term]] <- found
    }
  }

  results
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

helpers_mcp_tools$normalize_chart_type <- function(chart_type) {
  chart_type <- tolower(trimws(as.character(chart_type %||% "")))

  aliases <- list(
    line = c("line", "line graph", "line chart", "çizgi", "çizgi grafiği", "trend", "trend graph", "trend chart", "zaman serisi", "time series"),
    scatter = c("scatter", "scatter plot", "scatter graph", "saçılım", "saçılım grafiği"),
    area = c("area", "area graph", "area chart", "alan", "alan grafiği"),
    pareto = c("pareto", "pareto graph", "pareto chart", "pareto grafiği"),
    bar = c("bar", "bar graph", "bar chart", "column", "column chart", "çubuk", "çubuk grafiği", "sütun", "sütun grafiği"),
    pie = c("pie", "pie chart", "pie graph", "pasta", "pasta grafiği"),
    donut = c("donut", "doughnut", "donut chart", "doughnut chart", "halka", "halka grafiği"),
    hist = c("hist", "histogram", "histogram chart", "dağılım")
  )

  for (nm in names(aliases)) {
    if (chart_type %in% aliases[[nm]]) return(nm)
  }

  if (chart_type %in% c("box", "boxplot", "box_plot", "bx")) return("hist")

  chart_type
}

# Human-friendly column aliases for SQL outputs
helpers_mcp_tools$prettify_column_name <- function(nm) {
  if (is.null(nm) || length(nm) == 0) return("")
  raw <- as.character(nm[1])
  if (!nzchar(raw)) return("")

  # Strip wrapping quotes/brackets
  cleaned <- gsub("^[`\"\\[]|[`\"\\]]$", "", raw)
  cleaned <- gsub("_+", " ", cleaned)
  cleaned <- gsub("(?<=[a-z])(?=[A-Z])", " ", cleaned, perl = TRUE)
  cleaned <- trimws(cleaned)

  lower <- tolower(cleaned)
  if (grepl("^(avg|mean)", lower)) cleaned <- paste("Ortalama", trimws(sub("(?i)^(avg|mean)", "", cleaned)))
  if (grepl("^(sum|total)", lower)) cleaned <- paste("Toplam", trimws(sub("(?i)^(sum|total)", "", cleaned)))
  if (grepl("count", lower)) cleaned <- paste("Adet", trimws(sub("(?i)count", "", cleaned)))
  if (grepl("max", lower)) cleaned <- paste("Maksimum", trimws(sub("(?i)max", "", cleaned)))
  if (grepl("min", lower)) cleaned <- paste("Minimum", trimws(sub("(?i)min", "", cleaned)))

  cleaned <- trimws(cleaned)
  if (identical(cleaned, "")) cleaned <- raw

  tryCatch(enc2utf8(cleaned), error = function(e) cleaned)
}

helpers_mcp_tools$prettify_result_colnames <- function(df) {
  if (!is.data.frame(df)) return(df)
  colnames(df) <- vapply(colnames(df), helpers_mcp_tools$prettify_column_name, character(1))
  df
}

# Back-compat dotted alias (some earlier code may call this)
.normalize_args <- helpers_mcp_tools$normalize_args

# ============================
# Tool 1: analyze_uploaded_file
# ============================
helpers_mcp_tools$analyze_uploaded_file <- function(file_name, session = NULL) {
  file_name <- helpers_mcp_tools$auto_file_name(file_name, session)
  res <- helpers_mcp_tools$resolve_file_argument(file_name, session)
  # [FIX] Return list for error
  if (!isTRUE(res$ok)) return(list(error = res$error))

  path <- res$path
  df <- tryCatch({
    data.table::as.data.table(helpers_mcp_tools$safe_read_excel_table(path))
  }, error = function(e) e)
  
  # [FIX] Return list for error
  if (inherits(df, "error")) {
    return(list(error = sprintf("Excel dosyası okunamadı: %s \U2014 %s", basename(path), df$message)))
  }

  n_rows <- nrow(df)
  n_cols <- ncol(df)
  cols   <- names(df)

  # Numeric summary table
  num_cols <- names(df)[vapply(df, is.numeric, logical(1))]
  num_table_md <- ""
  
  if (length(num_cols) > 0) {
	summary_data <- do.call(rbind, lapply(num_cols, function(cn) {
      vals <- df[[cn]]
      d <- data.frame(
        cn,
        mean(vals, na.rm = TRUE),
        median(vals, na.rm = TRUE),
        suppressWarnings(min(vals, na.rm = TRUE)),
        suppressWarnings(max(vals, na.rm = TRUE)),
        sum(!is.na(vals)),
        stringsAsFactors = FALSE
      )
      names(d) <- c("Sütun", "Ortalama", "Medyan", "Min", "Max", "Dolu Kayıt")
      d
    }))
    num_table_md <- paste0("\n\n#### Sayısal Sütun Özeti\n", helpers_mcp_tools$create_md_table(summary_data))
  }

  display_name <- res$display %||% basename(path)
  display_name <- tryCatch(enc2utf8(display_name), error = function(e) display_name)
  
  list(result = sprintf(
    "### Dosya Özeti: %s\n\n- **Satır Sayısı:** %d\n- **Sütun Sayısı:** %d\n- **Sütunlar:** %s%s",
    display_name, n_rows, n_cols, paste(cols, collapse = ", "), num_table_md
  ))
}

# ==================================
# Tool 2: get_column_statistics
# ==================================
helpers_mcp_tools$get_column_statistics <- function(file_name, column, session = NULL) {
  file_name <- helpers_mcp_tools$auto_file_name(file_name, session)
  res <- helpers_mcp_tools$resolve_file_argument(file_name, session)
  # [FIX] Return list for error
  if (!isTRUE(res$ok)) return(list(error = res$error))
  if (is.null(column) || !nzchar(column)) return(list(error = "column parametresi boş"))

  path <- res$path
  dt <- tryCatch({
    data.table::as.data.table(helpers_mcp_tools$safe_read_excel_table(path))
  }, error = function(e) e)
  
  if (inherits(dt, "error")) {
    return(list(error = sprintf("Excel dosyası okunamadı: %s \U2014 %s", basename(path), dt$message)))
  }

  if (!(column %in% names(dt))) {
    return(list(error = sprintf("Sütun bulunamadı: **%s**. Mevcut sütunlar: %s", column, paste(names(dt), collapse = ", "))))
  }

  vec <- dt[[column]]
  
  header <- sprintf("### İstatistikler: %s (%s)", column, basename(path))

  output_md <- ""
  if (is.numeric(vec)) {
    stats_df <- data.frame(
      c("Kayıt Sayısı", "Ortalama", "Medyan", "Minimum", "Maksimum", "Toplam", "Standart Sapma", "Boş Değer"),
      c(
        sum(!is.na(vec)),
        mean(vec, na.rm = TRUE),
        median(vec, na.rm = TRUE),
        suppressWarnings(min(vec, na.rm = TRUE)),
        suppressWarnings(max(vec, na.rm = TRUE)),
        sum(vec, na.rm = TRUE),
        sd(vec, na.rm = TRUE),
        sum(is.na(vec))
      ),
      stringsAsFactors = FALSE
    )
    names(stats_df) <- c("Metrik", "Değer")
    output_md <- paste0(header, "\n\n", helpers_mcp_tools$create_md_table(stats_df))
    
  } else {
    # Categorical
    tb <- sort(table(vec, useNA = "ifany"), decreasing = TRUE)
    top5 <- head(tb, 10) 
    
    stats_df <- data.frame(
      Deger = names(top5),
      Adet = as.numeric(top5),
      Oran = sprintf("%.1f%%", 100 * as.numeric(top5) / length(vec)),
      stringsAsFactors = FALSE
    )
    names(stats_df) <- c("De\u011fer", "Adet", "Oran")
    
    summary_text <- sprintf(
      "- **Benzersiz Değer Sayısı:** %d\n- **Boş Değer Sayısı:** %d",
      length(unique(vec)), sum(is.na(vec))
    )
    
    output_md <- paste0(header, "\n", summary_text, "\n\n#### En Sık Görülen Değerler\n", helpers_mcp_tools$create_md_table(stats_df))
  }
  
  # [FIX] Wrap result in list
  list(result = output_md)
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
  # [FIX] Return list for error
  if (!isTRUE(res$ok)) return(list(error = res$error))
  if (is.null(sql) || !nzchar(sql)) return(list(error = "sql parametresi boş"))

  path <- res$path
  dt <- tryCatch({
    data.table::as.data.table(helpers_mcp_tools$safe_read_excel_table(path))
  }, error = function(e) e)
  
  if (inherits(dt, "error")) {
    return(list(error = sprintf("Excel dosyası okunamadı: %s \U2014 %s", basename(path), dt$message)))
  }

  # Normalize date/time as character
  for (nm in names(dt)) {
    if (inherits(dt[[nm]], "POSIXt") || inherits(dt[[nm]], "Date")) {
      dt[[nm]] <- as.character(dt[[nm]])
    }
  }

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)

  DBI::dbWriteTable(con, "t", as.data.frame(dt), temporary = TRUE, overwrite = TRUE)

  # Tolerate quoting styles
  q <- sql
  q <- gsub("`", "\"", q, fixed = TRUE)
  q <- gsub("\\[", "\"", q)
  q <- gsub("\\]", "\"", q)

  ans <- tryCatch(DBI::dbGetQuery(con, q), error = function(e) e)
  if (inherits(ans, "error")) {
    # [FIX] Return as 'result' so LLM sees the SQL error message nicely
    return(list(result = sprintf(
      "**SQL Hatası:** %s\n\n_İpucu: Tablo adı 't' olmalıdır. Stringler tek tırnak ile yazılmalıdır._", 
      ans$message
    )))
  }

  ans <- helpers_mcp_tools$prettify_result_colnames(ans)
	
  preview <- ans
  limit_msg <- ""
  if (nrow(preview) > 20) {
    preview <- head(preview, 20)
    limit_msg <- sprintf("\n_(İlk 20 satır gösteriliyor. Toplam sonuç: %d satır)_", nrow(ans))
  }

  display_name <- res$display %||% basename(path)
  display_name <- tryCatch(enc2utf8(display_name), error = function(e) display_name)

  list(result = paste0(
    "### Sorgu Sonucu\n**Dosya:** ", display_name, "\n**SQL:** `", sql, "`\n\n",
    helpers_mcp_tools$create_md_table(preview),
    limit_msg
  ))
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
  chart_type <- helpers_mcp_tools$normalize_chart_type(chart_type)

  # 1) resolve file
  res <- helpers_mcp_tools$resolve_file_argument(file_name, session)
  if (!isTRUE(res$ok)) return(list(error = res$error, ok = FALSE))

  # 2) read
  dt <- tryCatch({
    helpers_mcp_tools$safe_read_table_generic(res$path)
  }, error = function(e) e)
  if (inherits(dt, "error")) {
    return(list(error = sprintf("Dosya okunamadı: %s \U2014 %s", basename(res$path), dt$message), ok = FALSE))
  }
  
  # --- Türkçe yorum: Sütun doğrulama ve akıllı eşleştirme ---
  # Model geçersiz sütun adı verdiyse, önce akıllı eşleştirme dene, bulamazsa otomatik seçime bırak
  available_cols <- names(dt)

  # Türkçe: Akıllı sütun eşleştirme fonksiyonu
  smart_match_column <- function(col_name, col_type = "any") {
    if (is.null(col_name) || !nzchar(col_name)) return(NULL)
    if (col_name %in% available_cols) return(col_name)

    # Akıllı eşleştirme dene
    matched <- helpers_mcp_tools$find_matching_column(col_name, available_cols)
    if (!is.null(matched)) {
      cat("[CHART_SMART_MATCH] '", col_name, "' -> '", matched, "'\n", sep = "")
      return(matched)
    }
    NULL
  }

  # Türkçe yorum: x parametresini akıllı eşleştir
  if (!is.null(x) && nzchar(x) && !(x %in% available_cols)) {
    matched_x <- smart_match_column(x)
    if (!is.null(matched_x)) {
      x <- matched_x
    } else {
      cat("[CHART] x='", x, "' sütunu bulunamadı, otomatik seçilecek\n", sep = "")
      x <- NULL
    }
  }

  # Türkçe yorum: y parametresini akıllı eşleştir (virgüllü çoklu y'yi de kontrol et)
  if (!is.null(y) && nzchar(y)) {
    y_parts <- trimws(strsplit(as.character(y), ",")[[1]])
    resolved_y <- vapply(y_parts, function(yp) {
      if (yp %in% available_cols) return(yp)
      matched <- smart_match_column(yp)
      if (!is.null(matched)) return(matched)
      return("")
    }, character(1))
    resolved_y <- resolved_y[nzchar(resolved_y)]

    if (length(resolved_y) > 0) {
      y <- paste(resolved_y, collapse = ", ")
    } else {
      cat("[CHART] y sütunları bulunamadı: ", paste(y_parts, collapse = ", "), ", otomatik seçilecek\n", sep = "")
      y <- NULL
    }
  }

  # Türkçe yorum: group parametresini akıllı eşleştir
  if (!is.null(group) && nzchar(group) && !(group %in% available_cols)) {
    matched_group <- smart_match_column(group)
    if (!is.null(matched_group)) {
      group <- matched_group
    } else {
      cat("[CHART] group='", group, "' sütunu bulunamadı, otomatik seçilecek\n", sep = "")
      group <- NULL
    }
  }

  # --- Türkçe yorum: Pie/Donut için zorunlu ayarlamalar ---
  # X ekseni, agg ve top_n parametreleri otomatik olarak ayarlanır
  if (tolower(chart_type) %in% c("pie","donut")) {
    # Türkçe yorum: X ekseni yoksa kategorik sütun seç
    if (is.null(x) || !nzchar(x)) {
      cat_cols <- names(dt)[vapply(dt, function(v) is.character(v) || is.factor(v), logical(1))]
      if (length(cat_cols)) {
        x <- cat_cols[1]
      } else {
        # Türkçe yorum: Kategorik sütun yoksa ilk sütunu kullan
        x <- names(dt)[1]
      }
    }
 
    # Türkçe yorum: Y ekseni yoksa ilk sayısal sütunu seç
    if (is.null(y) || !nzchar(y)) {
      num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
      num_cols <- setdiff(num_cols, x)  # X'den farklı olmalı
      if (length(num_cols)) {
        y <- num_cols[1]
      }
    }
 
    # Türkçe yorum: Pie/Donut için agg parametresi ZORUNLU - yoksa otomatik ekle
    if (is.null(agg) || !nzchar(agg)) {
      agg <- "sum"  # Varsayılan olarak toplam kullan
    }
 
    # Türkçe yorum: Pie/Donut için top_n parametresi ZORUNLU - yoksa otomatik ekle
    # Bu, sonsuz dilim oluşturulmasını engeller
    if (is.null(top_n) || is.na(top_n) || !is.numeric(top_n)) {
      top_n <- 10  # Maksimum 10 dilim göster
    } else if (top_n > 20) {
      top_n <- 20  # 20'den fazla dilim mantıksız, sınırla
    }
  }
  
  # --- Türkçe yorum: Diğer grafik türleri için akıllı eksen seçimi ---
  # Kullanıcı veya model x/y belirtmemişse, veri yapısına göre otomatik seç
 
  # Türkçe yorum: Yardımcı fonksiyonlar
  is_date_col <- function(v) inherits(v, c("Date", "POSIXct", "POSIXt"))
  is_numeric_col <- function(v) is.numeric(v)
  is_cat_col <- function(v) is.character(v) || is.factor(v)
 
  # Türkçe yorum: Sütun kategorilerini belirle
  date_cols <- names(dt)[vapply(dt, is_date_col, logical(1))]
  num_cols <- names(dt)[vapply(dt, is_numeric_col, logical(1))]
  cat_cols <- names(dt)[vapply(dt, is_cat_col, logical(1))]
 
  # Türkçe yorum: String formatındaki tarih sütunlarını yakala
  if (length(date_cols) == 0 && length(cat_cols) > 0) {
    date_pattern <- "date|tarih|zaman|time|yil|year|month|ay|period|donem"
    date_candidates <- grep(date_pattern, tolower(cat_cols), value = TRUE)
    if (length(date_candidates) > 0) {
      date_cols <- date_candidates
      cat_cols <- setdiff(cat_cols, date_candidates)
    }
  }
 
  first_or_null <- function(vec) if (length(vec)) vec[1] else NULL
 
  # Türkçe yorum: Line/Area grafikleri için akıllı eksen seçimi
  if (tolower(chart_type) %in% c("line", "area")) {
    if (is.null(x) || !nzchar(x)) {
      # Türkçe yorum: Önce tarih sütunu, yoksa ilk sayısal sütun
      x <- first_or_null(date_cols)
      if (is.null(x)) x <- first_or_null(num_cols)
    }
    if (is.null(y) || !nzchar(y)) {
      # Türkçe yorum: X'den farklı ilk sayısal sütun
      y <- first_or_null(setdiff(num_cols, x))
    }
    if (is.null(group) && length(cat_cols) > 0) {
      # Türkçe yorum: Kategorik sütun varsa gruplama için kullan
      group <- first_or_null(cat_cols)
    }
  }
 
  # Türkçe yorum: Bar/Column grafikleri için akıllı eksen seçimi
  if (tolower(chart_type) %in% c("bar", "column")) {
    if (is.null(x) || !nzchar(x)) {
      # Türkçe yorum: Önce kategorik sütun, yoksa tarih sütunu
      x <- first_or_null(cat_cols)
      if (is.null(x)) x <- first_or_null(date_cols)
    }
    if (is.null(y) || !nzchar(y)) {
      # Türkçe yorum: İlk sayısal sütun
      y <- first_or_null(num_cols)
    }
  }
 
  # Türkçe yorum: Scatter grafikleri için akıllı eksen seçimi
  if (tolower(chart_type) == "scatter") {
    if (is.null(x) || !nzchar(x)) {
      x <- first_or_null(num_cols)
    }
    if (is.null(y) || !nzchar(y)) {
      y <- first_or_null(setdiff(num_cols, x))
    }
    if (is.null(group) && length(cat_cols) > 0) {
      group <- first_or_null(cat_cols)
    }
  }
 
  # Türkçe yorum: Histogram için akıllı eksen seçimi
  if (tolower(chart_type) == "hist") {
    if (is.null(x) || !nzchar(x)) {
      x <- first_or_null(num_cols)
    }
    # Türkçe yorum: Histogram için y ekseni her zaman NULL olmalı
    y <- NULL
  }
 
  # Türkçe yorum: Pareto grafikleri için akıllı eksen seçimi
  if (tolower(chart_type) == "pareto") {
    if (is.null(x) || !nzchar(x)) {
      x <- first_or_null(cat_cols)
    }
    if (is.null(y) || !nzchar(y)) {
      y <- first_or_null(num_cols)
    }
    # Türkçe yorum: Pareto için agregasyon gerekli
    if (is.null(agg) || !nzchar(agg)) {
      agg <- "sum"
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

  # 4) thin to only needed columns & Handle Multi-Y (Wide-to-Long)
  # Çoklu Y sütunlarını güvenli şekilde ayıkla
  if (is.null(y)) {
    y_candidates <- NULL
  } else if (is.character(y) || is.list(y)) {
    # Liste veya vektör gelirse düzleştir
    raw_y <- unlist(y, use.names = FALSE)
    if (length(raw_y) > 1) {
      y_candidates <- trimws(raw_y)
    } else {
      # Virgülle ayrılmış string gelirse parçala
      y_candidates <- trimws(strsplit(as.character(raw_y), ",")[[1]])
    }
  } else {
    y_candidates <- NULL
  }
  
  # Pie ve Donut grafikleri için otomatik agregasyon kontrolü
  # Eğer kullanıcı agg belirtmemişse ve veri çoksa, sistemi korumak için otomatik topla.
  if (tolower(chart_type) %in% c("pie", "donut", "bar", "column") && is.null(agg)) {
    row_limit_for_raw <- 20
    if (nrow(dt) > row_limit_for_raw) {
      if (!is.null(y_candidates) && length(y_candidates) > 0) {
        agg <- "sum" # Sayısal sütun varsa topla
      } else {
        agg <- "count" # Sayısal sütun yoksa satırları say
      }
    }
  }
  
  if (length(y_candidates) > 1) {
    # Check if all exist
    missing <- setdiff(c(x, y_candidates, group), names(dt))
    if (length(missing)) {
      return(list(error = sprintf("Sütun(lar) bulunamadı: %s", paste(missing, collapse=", ")), ok=FALSE))
    }
    
    # Reshape (Melt)
    measure_vars <- y_candidates
    id_vars <- c(x, group) # keep existing group if any
    id_vars <- id_vars[!is.null(id_vars)]
    
    subset_dt <- data.table::melt(dt, id.vars = id_vars, measure.vars = measure_vars,
                                  variable.name = "Variable", value.name = "Value")
    
    # Update mapping
    y <- "Value"
    # If there was a group, we might need a composite group, but usually multi-Y implies the variable IS the group
    if (is.null(group)) {
      group <- "Variable"
    } else {
      # If both group and multi-Y exist, usually we prioritize the multi-Y as the legend group
      # or we'd need a faceted plot (not supported yet). Let's swap group to Variable.
      group <- "Variable" 
    }
    
  } else {
    # Standard single Y logic
    cols <- unique(na.omit(c(x, y, group)))
    if (!length(cols)) {
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

# ==================================
# Tool 5: analyze_and_visualize (YENİ - R-First Yaklaşımı)
# ==================================
# Türkçe: Bu araç, filtrelenmiş/gruplandırılmış sorguları GERÇEK veriyle yanıtlar.
# AI değer uyduramaz çünkü R hesaplama yapar, AI sadece sonucu gösterir.
helpers_mcp_tools$analyze_and_visualize <- function(
  file_name,
  analysis_type = "summary",  # summary, filtered_stats, grouped_stats, chart
  filter_column = NULL,
  filter_value = NULL,
  group_column = NULL,
  stat_column = NULL,
  stat_function = "mean",  # mean, sum, count, median, min, max
  chart_type = NULL,  # Türkçe: Grafik istenirse: bar, pie, line, hist, scatter
  session = NULL
) {
  file_name <- helpers_mcp_tools$auto_file_name(file_name, session)
  res <- helpers_mcp_tools$resolve_file_argument(file_name, session)
  if (!isTRUE(res$ok)) return(list(error = res$error, ok = FALSE))
 
  # Türkçe: Dosyayı oku
  dt <- tryCatch({
    helpers_mcp_tools$safe_read_table_generic(res$path)
  }, error = function(e) e)
 
  if (inherits(dt, "error")) {
    return(list(error = sprintf("Dosya okunamadı: %s", dt$message), ok = FALSE))
  }
 
  display_name <- res$display %||% basename(res$path)
  result_text <- ""
  chart_data <- NULL

  # Türkçe: Sütun doğrulama
  available_cols <- names(dt)

  # --- AKILLI SÜTUN EŞLEŞTİRME ---
  # Türkçe: AI yanlış/eksik sütun adı verdiyse, akıllı eşleştirme ile düzelt
  smart_resolve_column <- function(col_name, col_type_hint = "any") {
    if (is.null(col_name) || !nzchar(col_name)) return(NULL)

    # Direkt eşleşme varsa kullan
    if (col_name %in% available_cols) return(col_name)

    # Akıllı eşleştirme dene
    matched <- helpers_mcp_tools$find_matching_column(col_name, available_cols)
    if (!is.null(matched)) {
      cat("[SMART_MATCH] '", col_name, "' -> '", matched, "'\n", sep = "")
      return(matched)
    }

    # Tip ipucu ile eşleştirme (örn: sayısal sütun gerekiyorsa)
    if (col_type_hint == "numeric") {
      num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
      if (length(num_cols) > 0) {
        # Sütun adında arama terimi var mı kontrol et
        for (nc in num_cols) {
          if (grepl(tolower(col_name), tolower(nc), fixed = TRUE) ||
              grepl(tolower(nc), tolower(col_name), fixed = TRUE)) {
            cat("[SMART_MATCH] Sayısal tip eşleşmesi: '", col_name, "' -> '", nc, "'\n", sep = "")
            return(nc)
          }
        }
      }
    } else if (col_type_hint == "categorical") {
      cat_cols <- names(dt)[vapply(dt, function(x) is.character(x) || is.factor(x), logical(1))]
      if (length(cat_cols) > 0) {
        for (cc in cat_cols) {
          if (grepl(tolower(col_name), tolower(cc), fixed = TRUE) ||
              grepl(tolower(cc), tolower(col_name), fixed = TRUE)) {
            cat("[SMART_MATCH] Kategorik tip eşleşmesi: '", col_name, "' -> '", cc, "'\n", sep = "")
            return(cc)
          }
        }
      }
    }

    NULL
  }

  # --- 1. FİLTRELEME (filter_column ve filter_value varsa) ---
  if (!is.null(filter_column) && nzchar(filter_column) &&
      !is.null(filter_value) && nzchar(filter_value)) {

    # Akıllı sütun eşleştirme
    resolved_filter_column <- smart_resolve_column(filter_column, "categorical")

    if (is.null(resolved_filter_column)) {
      # Sütun bulunamadı - mevcut sütunları ve değerlerini göster
      col_info <- vapply(available_cols, function(cn) {
        if (is.character(dt[[cn]]) || is.factor(dt[[cn]])) {
          unique_vals <- head(unique(as.character(dt[[cn]])), 5)
          sprintf("'%s' (değerler: %s)", cn, paste(unique_vals, collapse = ", "))
        } else {
          sprintf("'%s' (sayısal)", cn)
        }
      }, character(1))

      return(list(
        error = sprintf(
          "Filtre sütunu '%s' bulunamadı.\n\nMevcut sütunlar ve örnek değerler:\n%s\n\nLütfen yukarıdaki GERÇEK sütun isimlerinden birini kullanın.",
          filter_column, paste(col_info, collapse = "\n")
        ),
        ok = FALSE
      ))
    }

    # Çözülen sütun adını kullan
    filter_column <- resolved_filter_column
 
    # Türkçe: Büyük/küçük harf duyarsız filtreleme
    col_vals <- dt[[filter_column]]
    if (is.character(col_vals) || is.factor(col_vals)) {
      filter_mask <- grepl(filter_value, as.character(col_vals), ignore.case = TRUE)
    } else {
      # Türkçe: Sayısal sütun için tam eşleşme
      filter_val_num <- suppressWarnings(as.numeric(filter_value))
      if (!is.na(filter_val_num)) {
        filter_mask <- col_vals == filter_val_num
      } else {
        filter_mask <- rep(FALSE, nrow(dt))
      }
    }
 
    dt <- dt[filter_mask, ]
 
    if (nrow(dt) == 0) {
      return(list(
        result = sprintf("### Sonuç Yok\n'%s' sütununda '%s' değeri bulunamadı.",
                         filter_column, filter_value),
        ok = TRUE
      ))
    }
 
    result_text <- sprintf("**Filtre:** %s = '%s' (%d kayıt)\n\n",
                           filter_column, filter_value, nrow(dt))
  }
 
  # --- 2. İSTATİSTİK HESAPLAMA (R yapıyor, AI değil!) ---
  stat_fun <- switch(tolower(stat_function %||% "mean"),
    "mean" = function(x) mean(x, na.rm = TRUE),
    "sum" = function(x) sum(x, na.rm = TRUE),
    "count" = function(x) sum(!is.na(x)),
    "median" = function(x) median(x, na.rm = TRUE),
    "min" = function(x) min(x, na.rm = TRUE),
    "max" = function(x) max(x, na.rm = TRUE),
    function(x) mean(x, na.rm = TRUE)
  )
 
  stat_label <- switch(tolower(stat_function %||% "mean"),
    "mean" = "Ortalama",
    "sum" = "Toplam",
    "count" = "Adet",
    "median" = "Medyan",
    "min" = "Minimum",
    "max" = "Maksimum",
    "Ortalama"
  )
 
  # --- 3. ANALİZ TİPİNE GÖRE İŞLEM ---
  analysis_type <- tolower(analysis_type %||% "summary")
 
  if (analysis_type == "summary") {
    # Türkçe: Genel özet
    num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
 
    if (length(num_cols) > 0) {
      summary_rows <- lapply(num_cols, function(cn) {
        vals <- dt[[cn]]
        data.frame(
          Sutun = cn,
          Ortalama = round(mean(vals, na.rm = TRUE), 2),
          Medyan = round(median(vals, na.rm = TRUE), 2),
          Min = round(min(vals, na.rm = TRUE), 2),
          Max = round(max(vals, na.rm = TRUE), 2),
          Toplam = round(sum(vals, na.rm = TRUE), 2),
          stringsAsFactors = FALSE
        )
      })
      summary_df <- do.call(rbind, summary_rows)
      names(summary_df)[1] <- "S\u00fctun"
      result_text <- paste0(result_text,
        sprintf("### Dosya Özeti: %s\n", display_name),
        sprintf("- **Toplam Satır:** %d\n", nrow(dt)),
        sprintf("- **Toplam Sütun:** %d\n\n", ncol(dt)),
        "#### Sayısal Sütun İstatistikleri (R tarafından hesaplandı)\n",
        helpers_mcp_tools$create_md_table(summary_df)
      )
      chart_data <- summary_df
    } else {
      result_text <- paste0(result_text,
        sprintf("### Dosya Özeti: %s\n", display_name),
        sprintf("- **Toplam Satır:** %d\n", nrow(dt)),
        sprintf("- **Toplam Sütun:** %d\n", ncol(dt)),
        sprintf("- **Sütunlar:** %s\n", paste(available_cols, collapse = ", "))
      )
    }
 
  } else if (analysis_type == "filtered_stats") {
    # Türkçe: Filtrelenmiş veri üzerinde istatistik
    if (is.null(stat_column) || !nzchar(stat_column)) {
      # Türkçe: stat_column belirtilmemişse ilk sayısal sütunu kullan
      num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
      if (length(num_cols) > 0) {
        stat_column <- num_cols[1]
      } else {
        return(list(error = "Sayısal sütun bulunamadı.", ok = FALSE))
      }
    } else {
      # Akıllı sütun eşleştirme
      resolved_stat_column <- smart_resolve_column(stat_column, "numeric")
      if (!is.null(resolved_stat_column)) {
        stat_column <- resolved_stat_column
      }
    }

    if (!(stat_column %in% available_cols)) {
      num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
      return(list(
        error = sprintf("İstatistik sütunu '%s' bulunamadı.\nMevcut sayısal sütunlar: %s",
                        stat_column, paste(num_cols, collapse = ", ")),
        ok = FALSE
      ))
    }

    vals <- dt[[stat_column]]
    if (!is.numeric(vals)) {
      return(list(error = sprintf("'%s' sütunu sayısal değil.", stat_column), ok = FALSE))
    }

    stat_value <- stat_fun(vals)

    result_text <- paste0(result_text,
      sprintf("### %s: %s\n\n", stat_label, stat_column),
      sprintf("**Sonuç:** %.2f\n\n", stat_value),
      sprintf("_(Bu değer R tarafından %d kayıt üzerinden hesaplandı)_", nrow(dt))
    )

    chart_data <- data.frame(
      Metrik = stat_label,
      Deger = stat_value,
      stringsAsFactors = FALSE
    )
    names(chart_data)[2] <- "De\u011fer"

  } else if (analysis_type == "grouped_stats") {
    # Türkçe: Gruplandırılmış istatistik (örn: departman bazında ortalama)
    if (is.null(group_column) || !nzchar(group_column)) {
      # Kategorik sütun yoksa hata ver
      cat_cols <- names(dt)[vapply(dt, function(x) is.character(x) || is.factor(x), logical(1))]
      if (length(cat_cols) > 0) {
        return(list(
          error = sprintf("group_column parametresi gerekli.\nMevcut kategorik sütunlar: %s", paste(cat_cols, collapse = ", ")),
          ok = FALSE
        ))
      } else {
        return(list(error = "group_column parametresi gerekli ve kategorik sütun bulunamadı.", ok = FALSE))
      }
    }

    # Akıllı sütun eşleştirme - group_column
    resolved_group_column <- smart_resolve_column(group_column, "categorical")
    if (!is.null(resolved_group_column)) {
      group_column <- resolved_group_column
    }

    if (!(group_column %in% available_cols)) {
      cat_cols <- names(dt)[vapply(dt, function(x) is.character(x) || is.factor(x), logical(1))]
      return(list(
        error = sprintf("Gruplama sütunu '%s' bulunamadı.\nMevcut kategorik sütunlar: %s",
                        group_column, paste(cat_cols, collapse = ", ")),
        ok = FALSE
      ))
    }

    if (is.null(stat_column) || !nzchar(stat_column)) {
      num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
      if (length(num_cols) > 0) {
        stat_column <- num_cols[1]
      } else {
        return(list(error = "Sayısal sütun bulunamadı.", ok = FALSE))
      }
    } else {
      # Akıllı sütun eşleştirme - stat_column
      resolved_stat_column <- smart_resolve_column(stat_column, "numeric")
      if (!is.null(resolved_stat_column)) {
        stat_column <- resolved_stat_column
      }
    }

    if (!(stat_column %in% available_cols)) {
      num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
      return(list(
        error = sprintf("İstatistik sütunu '%s' bulunamadı.\nMevcut sayısal sütunlar: %s",
                        stat_column, paste(num_cols, collapse = ", ")),
        ok = FALSE
      ))
    }
 
    # Türkçe: R ile gruplandırılmış hesaplama
    grouped_result <- aggregate(
      dt[[stat_column]],
      by = list(Grup = dt[[group_column]]),
      FUN = stat_fun
    )
    names(grouped_result) <- c(group_column, paste0(stat_label, "_", stat_column))
 
    # Türkçe: Sırala (büyükten küçüğe)
    grouped_result <- grouped_result[order(grouped_result[[2]], decreasing = TRUE), ]
 
    result_text <- paste0(result_text,
      sprintf("### %s Bazında %s: %s\n\n", group_column, stat_label, stat_column),
      helpers_mcp_tools$create_md_table(grouped_result),
      sprintf("\n\n_(Bu değerler R tarafından %d kayıt üzerinden hesaplandı)_", nrow(dt))
    )
 
    chart_data <- grouped_result
 
  } else if (analysis_type == "chart") {
    # Türkçe: Sadece grafik isteniyor
    # prepare_chart_data'ya yönlendir
    return(helpers_mcp_tools$prepare_chart_data(
      file_name = file_name,
      chart_type = chart_type %||% "bar",
      x = group_column,
      y = stat_column,
      filter_sql = if (!is.null(filter_column) && !is.null(filter_value)) {
        sprintf("\"%s\" = '%s'", filter_column, filter_value)
      } else NULL,
      agg = stat_function,
      session = session
    ))
  }
 
  # --- 4. GRAFİK EKLENSİN Mİ? ---
  chart_spec <- NULL
  if (!is.null(chart_type) && nzchar(chart_type) && !is.null(chart_data) && nrow(chart_data) > 0) {
    # Türkçe: Grafik oluştur
    chart_spec <- list(
      type = helpers_mcp_tools$normalize_chart_type(chart_type),
      mapping = list(
        x = names(chart_data)[1],
        y = names(chart_data)[2]
      ),
      params = list(agg = NULL),  # Türkçe: Zaten agregasyon yapıldı
      data = as.data.frame(chart_data),
      schema = as.list(vapply(chart_data, function(z) class(z)[1], character(1))),
      n = nrow(chart_data)
    )
  }
 
  # --- 5. SONUÇ ---
  if (!is.null(chart_spec)) {
    return(list(
      ok = TRUE,
      `__mcp_plot` = TRUE,
      result = result_text,
      chart = chart_spec,
      message = "Analiz ve grafik hazırlandı."
    ))
  } else {
    return(list(
      ok = TRUE,
      result = result_text
    ))
  }
}
 
# ==================================
# Tool 6: get_distinct_values
# ==================================
helpers_mcp_tools$get_distinct_values <- function(file_name, column, limit = 50, session = NULL) {
  file_name <- helpers_mcp_tools$auto_file_name(file_name, session)
  res <- helpers_mcp_tools$resolve_file_argument(file_name, session)
  if (!isTRUE(res$ok)) return(list(error = res$error))
  
  if (is.null(column) || !nzchar(column)) return(list(error = "column parametresi boş"))

  path <- res$path
  dt <- tryCatch({
    data.table::as.data.table(helpers_mcp_tools$safe_read_excel_table(path))
  }, error = function(e) e)
  
  if (inherits(dt, "error")) return(list(error = sprintf("Dosya okunamadı: %s", dt$message)))

  if (!(column %in% names(dt))) {
    return(list(error = sprintf("Sütun '%s' bulunamadı. Mevcut: %s", column, paste(names(dt), collapse=", "))))
  }

  vals <- unique(dt[[column]])
  vals <- vals[!is.na(vals)]
  count <- length(vals)
  
  # Return top N
  shown_vals <- head(sort(vals), limit)
  
  display_name <- res$display %||% basename(path)
  
  msg <- paste0(
    "### Benzersiz Değerler: ", column, " (", display_name, ")\n",
    "- **Toplam Benzersiz Sayı:** ", count, "\n",
    "- **Listelenen (İlk ", length(shown_vals), "):** ", paste(shown_vals, collapse = ", ")
  )
  
  if (count > limit) {
    msg <- paste0(msg, "\n\n_(Liste çok uzun olduğu için ilk ", limit, " kayıt gösterildi. Tam liste için SQL kullanabilirsiniz.)_")
  }
  
  list(result = msg)
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
	  "get_distinct_values"     = helpers_mcp_tools$get_distinct_values(args$file_name, args$column, args$limit %||% 50, session),
	  "get_column_stats"        = helpers_mcp_tools$get_column_statistics(args$file_name, args$column, session),
	  "sql_query_uploaded_file" = helpers_mcp_tools$sql_query_uploaded_file(args$file_name, args$sql, session),
	  "analyze_and_visualize"   = helpers_mcp_tools$analyze_and_visualize(
		file_name      = args$file_name,
		analysis_type  = args$analysis_type %||% "summary",
		filter_column  = args$filter_column,
		filter_value   = args$filter_value,
		group_column   = args$group_column,
		stat_column    = args$stat_column,
		stat_function  = args$stat_function %||% "mean",
		chart_type     = args$chart_type,
		session        = session
	  ),
	  "prepare_chart_data"      = helpers_mcp_tools$prepare_chart_data(
		file_name   = args$file_name,
		chart_type  = args$chart_type,
		x           = args$x %||% args$xlabel %||% args$x_col,
		y           = args$y %||% args$ylabel %||% args$y_col,
		group       = args$group %||% args$color %||% args$hue,
		agg         = args$agg,
		bins        = args$bins,
		top_n       = args$top_n,
		stack       = args$stack,        # Türkçe yorum: Yığınlama modu (normal/percent)
		donut       = args$donut,        # Türkçe yorum: Pasta grafiğini halka yap
		orientation = args$orientation,  # Türkçe yorum: Bar grafiği yönü (v/h)
		smooth      = args$smooth,       # Türkçe yorum: Çizgi yumuşatma
		filter_sql  = args$filter_sql,
		limit       = args$limit %||% 5000,
		session     = session
	  ),
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
          description = "SQL ile filtreleme, sıralama, gruplama ve 'Top N' listeleme yapar. Sıralama (ORDER BY) ve listeleme soruları için bunu kullan. Tablo adı: t.",
          parameters = list(
            type = "object",
            properties = list(
              file_name = list(type = "string", description = "Dosya jetonu veya adı."),
              sql       = list(type = "string", description = "DuckDB uyumlu SQL; tablo adı 't'. Örnek: SELECT * FROM t ORDER BY Age DESC LIMIT 10")
            ),
            required = list("file_name", "sql")
          )
        )
      ),
	  list(
        type = "function",
        `function` = list(
          name = "get_distinct_values",
          description = "Bir sütundaki benzersiz (unique) değerleri listeler. Filtreleme yapmadan önce kategori isimlerini öğrenmek için kullan.",
          parameters = list(
            type = "object",
            properties = list(
              file_name = list(type = "string", description = "Dosya adı."),
              column    = list(type = "string", description = "Benzersiz değerleri istenen sütun."),
              limit     = list(type = "integer", description = "Maksimum kaç değer dönsün (varsayılan 50).")
            ),
            required = list("file_name", "column")
          )
        )
      ),
      # Türkçe: YENİ - R-First yaklaşımı ile filtrelenmiş analiz ve grafik
      list(
        type = "function",
        `function` = list(
          name = "analyze_and_visualize",
          description = paste0(
            "FİLTRELENMİŞ İSTATİSTİK VE GRAFİK için bu aracı kullan! ",
            "Kullanıcı belirli bir gruba/kategoriye göre ortalama, toplam vb. istiyorsa bu araç ZORUNLU. ",
            "Örnek: 'IT departmanının ortalama maaşı', 'Erkeklerin çalışma saati toplamı'. ",
            "R tarafından GERÇEK hesaplama yapılır, AI değer UYDURAMAZ!"
          ),
          parameters = list(
            type = "object",
            properties = list(
              file_name = list(type = "string", description = "Dosya adı"),
              analysis_type = list(
                type = "string",
                description = paste0(
                  "Analiz tipi: ",
                  "'summary' (genel özet), ",
                  "'filtered_stats' (filtrelenmiş tek istatistik), ",
                  "'grouped_stats' (gruplandırılmış istatistik), ",
                  "'chart' (sadece grafik)"
                )
              ),
              filter_column = list(type = "string", description = "Filtreleme yapılacak sütun (örn: 'Departman', 'Cinsiyet')"),
              filter_value = list(type = "string", description = "Filtreleme değeri (örn: 'IT', 'Erkek')"),
              group_column = list(type = "string", description = "Gruplama sütunu (grouped_stats için). Örn: 'Departman'"),
              stat_column = list(type = "string", description = "İstatistik hesaplanacak sayısal sütun (örn: 'Maas', 'CalismaSaati')"),
              stat_function = list(type = "string", description = "İstatistik fonksiyonu: 'mean', 'sum', 'count', 'median', 'min', 'max'"),
              chart_type = list(type = "string", description = "Grafik eklensin mi? 'bar', 'pie', 'line', 'area', 'scatter', 'pareto', 'hist'. Boş bırakırsan grafik çizilmez.")
            ),
            required = list("file_name", "analysis_type")
          )
        )
      ),
	  list(
        type = "function",
        `function` = list(
          name = "prepare_chart_data",
          description = paste0(
            "GENEL GRAFİK ÇİZER (filtresiz). Dosyanın TAMAMINI görselleştirir. ",
            "Eksenleri OTOMATİK seçer. Sadece file_name ve chart_type ver. ",
            "NOT: Filtrelenmiş grafik istiyorsan analyze_and_visualize kullan!"
          ),
          parameters = list(
            type = "object",
            properties = list(
              file_name  = list(type = "string", description = "Dosya adı (örn: 'veri.xlsx')"),
              chart_type = list(type = "string", description = "Grafik türü: 'hist', 'bar', 'pie', 'donut', 'line', 'area', 'scatter', 'pareto'"),
              x          = list(type = "string", description = "X ekseni sütunu (OPSİYONEL - boş bırakırsan otomatik seçilir)"),
              y          = list(type = "string", description = "Y ekseni sütunu (OPSİYONEL). Çoklu seri için: 'Col1,Col2'"),
              group      = list(type = "string", description = "Gruplama sütunu (OPSİYONEL)"),
              agg        = list(type = "string", description = "Agregasyon: 'sum', 'mean', 'count' (OPSİYONEL - pie/bar için otomatik eklenir)"),
              bins       = list(type = "integer", description = "Histogram kutu sayısı (OPSİYONEL)"),
              top_n      = list(type = "integer", description = "En yüksek N kayıt (OPSİYONEL - pie için otomatik 10)"),
              stack      = list(type = "string", description = "Yığınlama: 'normal' veya 'percent' (OPSİYONEL)"),
              donut      = list(type = "boolean", description = "Pasta yerine halka (OPSİYONEL)"),
              orientation = list(type = "string", description = "Bar yönü: 'v' veya 'h' (OPSİYONEL)"),
              smooth     = list(type = "boolean", description = "Çizgi yumuşatma (OPSİYONEL)"),
              filter_sql = list(type = "string", description = "SQL WHERE filtresi (OPSİYONEL, tercih: analyze_and_visualize kullan)"),
              limit      = list(type = "integer", description = "Maksimum satır (OPSİYONEL)")
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
# Türkçe: Bu prompt TÜM modellere gönderilir. Açık ve model-agnostik olmalı.
# file_schema parametresi ile dosya şeması da eklenebilir.
helpers_mcp_tools$get_mcp_tools_prompt <- function(file_schema = NULL) {
  # Dosya şeması varsa başta ekle
  schema_section <- ""
  if (!is.null(file_schema) && nzchar(file_schema)) {
    schema_section <- paste0(
      "# \U0001F4CA YÜKLÜ DOSYA BİLGİSİ\n\n",
      file_schema, "\n\n",
      "---\n\n",
      "**ÖNEMLİ:** Yukarıdaki şemada gördüğün GERÇEK sütun isimlerini kullan!\n",
      "Kullanıcı Türkçe terim kullanırsa, şemadaki İngilizce karşılığını bul.\n",
      "Örnek: Kullanıcı 'departman' derse \U2192 şemada 'Department' sütununu kullan.\n\n",
      "---\n\n"
    )
  }

  paste0(
    schema_section,
    "# VERİ ANALİZİ VE GRAFİK ARAÇLARI KULLANIM KILAVUZU\n\n",

    "Sen bir Excel/CSV veri analisti asistanısın. Araçları ZORUNLU olarak kullanmalısın.\n",
    "ASLA kendi başına istatistik HESAPLAMA veya değer UYDURMA! Tüm hesaplamalar R tarafından yapılır.\n\n",

    "## \U000026A0\U0000FE0F SÜTUN İSİMLERİ İÇİN KRİTİK KURAL:\n",
    "1. Yukarıdaki dosya şemasında GERÇEK sütun isimlerini gör\n",
    "2. Kullanıcının Türkçe terimi ile şemadaki İngilizce sütunu eşleştir\n",
    "3. Araç çağrılarında SADECE şemadaki gerçek sütun isimlerini kullan\n",
    "4. Şemada olmayan sütun ismi KULLANMA - hata alırsın!\n\n",

    "## KRİTİK KURAL: HANGİ ARACI NE ZAMAN KULLAN?\n\n",

    "### \U00000031\U0000FE0F\U000020E3 FİLTRELENMİŞ İSTATİSTİK İSTENİYORSA \U2192 `analyze_and_visualize`\n",
    "Kullanıcı belirli bir kategoriye göre ortalama, toplam, sayı istiyorsa BU ARACI KULLAN!\n\n",

    "**Örnekler:**\n",
    "- 'IT departmanının ortalama maaşı' \U2192 analyze_and_visualize(filter_column='Department', filter_value='IT', stat_function='mean')\n",
    "- 'Erkeklerin toplam çalışma saati' \U2192 analyze_and_visualize(filter_column='Gender', filter_value='Male', stat_function='sum')\n",
    "- 'Departman bazında ortalama maaş' \U2192 analyze_and_visualize(analysis_type='grouped_stats', group_column='Departman', stat_function='mean')\n",
    "- 'Satış ekibinin performans grafiği' \U2192 analyze_and_visualize(filter_column='Departman', filter_value='Satış', chart_type='bar')\n\n",
 
    "### \U00000032\U0000FE0F\U000020E3 GENEL GRAFİK İSTENİYORSA (filtresiz) \U2192 `prepare_chart_data`\n",
    "Tüm veriyi görselleştirmek için bu aracı kullan. Eksenler OTOMATİK seçilir.\n\n",
 
    "**Örnekler:**\n",
    "- 'histogram çiz' \U2192 prepare_chart_data(chart_type='hist')\n",
    "- 'bar grafiği' \U2192 prepare_chart_data(chart_type='bar')\n",
    "- 'pasta grafiği' \U2192 prepare_chart_data(chart_type='pie')\n",
    "- 'çizgi grafiği' \U2192 prepare_chart_data(chart_type='line')\n",
    "- 'scatter plot' \U2192 prepare_chart_data(chart_type='scatter')\n\n",
 
    "### \U00000033\U0000FE0F\U000020E3 SQL SORGUSU GEREKİYORSA \U2192 `sql_query_uploaded_file`\n",
    "Karmaşık filtreleme, sıralama, gruplama için SQL kullan. Tablo adı: 't'\n\n",
 
    "**Örnekler:**\n",
    "- 'En yüksek maaşlı 10 kişi' \U2192 sql_query_uploaded_file(sql='SELECT * FROM t ORDER BY Maas DESC LIMIT 10')\n",
    "- '2023 yılı kayıtları' \U2192 sql_query_uploaded_file(sql=\"SELECT * FROM t WHERE Yil = 2023\")\n\n",
 
    "### \U00000034\U0000FE0F\U000020E3 SÜTUN DEĞERLERİNİ ÖĞRENMEK İÇİN \U2192 `get_distinct_values`\n",
    "Hangi kategoriler var bilmiyorsan önce bu aracı çağır.\n\n",
 
    "## GRAFİK TÜRLERİ SÖZLÜĞÜ:\n",
    "| Kullanıcı Terimi | chart_type |\n",
    "|------------------|------------|\n",
    "| histogram, dağılım | 'hist' |\n",
    "| bar, çubuk, sütun | 'bar' |\n",
    "| pasta, pie | 'pie' |\n",
    "| halka, donut | 'donut' |\n",
    "| çizgi, line, trend | 'line' |\n",
    "| alan, area | 'area' |\n",
    "| scatter, saçılım | 'scatter' |\n",
    "| pareto | 'pareto' |\n\n",

    "## GRAFİK TÜRÜ SEÇİMİ İÇİN EK KURALLAR:\n",
    "- Kullanıcı 'çizgi grafiği' diyorsa ASLA 'scatter' seçme; chart_type='line' kullan.\n",
    "- 'scatter' sadece iki sayısal sütun arasındaki ilişki/korelasyon için kullanılmalı.\n",
    "- Kullanıcı 'alan grafiği' diyorsa chart_type='area' kullan.\n",
    "- Kullanıcı 'pareto' diyorsa chart_type='pareto' kullan.\n\n",

    "## ZORUNLU KURALLAR:\n",
    "1. \U0000274C ASLA kendi başına değer UYDURMA! Araç kullan.\n",
    "2. \U0000274C ASLA sütun adı TAHMIN ETME! Araç otomatik seçer veya get_distinct_values ile öğren.\n",
    "3. \U00002705 Filtrelenmiş istatistik = analyze_and_visualize\n",
    "4. \U00002705 Genel grafik = prepare_chart_data\n",
    "5. \U00002705 Her grafik isteği için EN AZ BİR araç çağır\n",
    "6. \U00002705 Birden fazla grafik istenirse birden fazla araç çağır\n\n",
 
    "## ARAÇ ÇAĞIRMA FORMATI:\n",
    "Her araç çağrısı şu formatta olmalı:\n",
    "```json\n",
    "{\"name\": \"araç_adı\", \"arguments\": {\"param1\": \"değer1\", \"param2\": \"değer2\"}}\n",
    "```\n\n",
 
    "ŞİMDİ kullanıcının talebine göre UYGUN ARACI ÇAĞıR!"
  )
}

# Lightweight SQL extractor (so plain SELECT blocks are still executed)
helpers_mcp_tools$extract_sql_from_text <- function(text) {
  if (is.null(text) || !nzchar(text)) return(NULL)

  # Prefer fenced sql blocks
  block_rgx <- "```sql\\s*([\\s\\S]*?)```"
  m <- regexpr(block_rgx, text, perl = TRUE)
  if (m[1] != -1) {
    sql <- regmatches(text, m)[1]
    sql <- gsub("^```sql", "", sql)
    sql <- gsub("```$", "", sql)
    return(trimws(sql))
  }

  # Fallback: first SELECT ... pattern
  plain_sel <- regexpr("(?is)select\\s+[\\s\\S]+?($|;)", text, perl = TRUE)
  if (plain_sel[1] != -1) {
    sql <- regmatches(text, plain_sel)[1]
    sql <- sub(";+$", "", sql)
    return(trimws(sql))
  }

  NULL
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

  # 4) Plain SQL without explicit tool markup
  if (length(out) == 0) {
    sql_candidate <- helpers_mcp_tools$extract_sql_from_text(text)
    if (!is.null(sql_candidate) && nzchar(sql_candidate)) {
      out[[length(out) + 1]] <- list(
        function_name = "sql_query_uploaded_file",
        arguments = list(sql = sql_candidate)
      )
    }
  }
  
  out
}

# ============================
# Public wrappers (used by global.R)
# ============================
get_openai_tools              <- function(session = NULL) helpers_mcp_tools$get_openai_tools(session)
get_mcp_tools_prompt          <- function(file_schema = NULL) helpers_mcp_tools$get_mcp_tools_prompt(file_schema)
extract_mcp_file_schema       <- function(file_name, session = NULL) helpers_mcp_tools$extract_mcp_file_schema(file_name, session)
find_matching_column          <- function(search_term, available_columns, context = NULL) helpers_mcp_tools$find_matching_column(search_term, available_columns, context)
parse_tool_calls_from_text    <- function(x)              helpers_mcp_tools$parse_tool_calls_from_text(x)
execute_parsed_tool           <- function(tc, session=NULL) helpers_mcp_tools$execute_parsed_tool(tc, session)
register_session_file         <- function(session, token, path, nm=NULL) helpers_mcp_tools$register_uploaded_file(session, token, path, nm)
reset_session_file_registry   <- function(session = NULL) helpers_mcp_tools$reset_session_file_registry(session)
environment(helpers_mcp_tools$analyze_uploaded_file)   <- helpers_mcp_tools
environment(helpers_mcp_tools$get_column_statistics)   <- helpers_mcp_tools
environment(helpers_mcp_tools$sql_query_uploaded_file) <- helpers_mcp_tools
environment(helpers_mcp_tools$prepare_chart_data)      <- helpers_mcp_tools
environment(helpers_mcp_tools$analyze_and_visualize)   <- helpers_mcp_tools
environment(helpers_mcp_tools$resolve_file_argument)   <- helpers_mcp_tools
environment(helpers_mcp_tools$normalize_excel_path)    <- helpers_mcp_tools
environment(helpers_mcp_tools$safe_read_excel_table)   <- helpers_mcp_tools
environment(helpers_mcp_tools$safe_read_table_generic) <- helpers_mcp_tools
environment(helpers_mcp_tools$get_default_file_name)   <- helpers_mcp_tools
environment(helpers_mcp_tools$auto_file_name)          <- helpers_mcp_tools
environment(helpers_mcp_tools$extract_mcp_file_schema) <- helpers_mcp_tools
environment(helpers_mcp_tools$find_matching_column)    <- helpers_mcp_tools
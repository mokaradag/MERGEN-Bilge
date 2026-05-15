# ==============================================================================
# Dosya Yolu: R/helpers_mcp_file_resolver.R
# Açıklama: MCP oturum dosya kayıt defteri ve dosya adı/yol çözümleme
#           yardımcılarını helpers_mcp_tools monolitinden ayırır.
# ==============================================================================

if (!exists("helpers_mcp_tools", envir = globalenv(), inherits = FALSE) ||
    !is.environment(get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE))) {

  .mcp_resolver_context_path <- file.path("R", "helpers_mcp_context.R")

  if (!file.exists(.mcp_resolver_context_path)) {
    stop(
      "R/helpers_mcp_context.R bulunamadı; helpers_mcp_file_resolver.R yüklenemiyor.",
      call. = FALSE
    )
  }

  source(.mcp_resolver_context_path, encoding = "UTF-8", local = globalenv())
}

helpers_mcp_tools <- get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)

.mcp_file_resolver_missing <- c(
  "path_exists_relaxed",
  "resolve_readable_path",
  "normalize_excel_path",
  "mcp_debug_log",
  "get_session_user_id"
)

.mcp_file_resolver_missing <- .mcp_file_resolver_missing[
  !vapply(
    .mcp_file_resolver_missing,
    function(x) exists(x, envir = helpers_mcp_tools, inherits = FALSE),
    logical(1)
  )
]

if (length(.mcp_file_resolver_missing) > 0L) {
  stop(
    sprintf(
      "MCP dosya çözümleyici için eksik helper(lar): %s. Önce R/helpers_mcp_tools.R yüklenmelidir.",
      paste(.mcp_file_resolver_missing, collapse = ", ")
    ),
    call. = FALSE
  )
}

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
    helpers_mcp_tools$mcp_debug_log(
      "[RESOLVE] Skip registry; path missing -> ",
      normalized_path
    )
    return(invisible(FALSE))
  }

  session$userData$current_session_files[[token]] <- list(
    path = normalized_path,
    name = display_name %||% basename(abs_path)
  )

  helpers_mcp_tools$mcp_debug_log(
    "[RESOLVE] registry token ",
    token,
    " -> ",
    normalized_path
  )

  invisible(TRUE)
}

helpers_mcp_tools$get_default_file_name <- function(session = NULL) {
  helpers_mcp_tools$ensure_session_file_registry(session)

  files <- session$userData$current_session_files
  if (is.null(files) || !length(files)) return(NULL)

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

  helpers_mcp_tools$mcp_debug_log("[RESOLVE] Looking for: ", arg)

  helpers_mcp_tools$mcp_debug_log(
    "[RESOLVE][env] has_path_exists_relaxed=",
    exists("path_exists_relaxed", envir = helpers_mcp_tools, inherits = FALSE),
    " has_resolve_readable_path=",
    exists("resolve_readable_path", envir = helpers_mcp_tools, inherits = FALSE)
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

  path_ok_robust <- function(candidate) {
    !is.null(resolve_existing_candidate(candidate))
  }

  path_ok <- function(candidate) {
    path_ok_robust(candidate)
  }

	is_abs <- grepl("^([A-Za-z]:)?[\\/]", arg)
	if (is_abs) {
	  helpers_mcp_tools$mcp_debug_log(
		"[RESOLVE] Absolute path argument rejected; use selected file name or file token."
	  )

	  return(list(
		ok = FALSE,
		error = "Mutlak dosya yolu kabul edilmez. Lütfen Dosya Yönetimi'nde seçili dosya adını veya dosya jetonunu kullanın."
	  ))
	}

	all_files <- session$userData$current_session_files
	base_arg <- basename(arg)

  if (!is.null(all_files) && length(all_files) > 0) {
    helpers_mcp_tools$mcp_debug_log("[RESOLVE] Checking ", length(all_files), " files in session")

    rehydrate_missing_path <- function(preferred_tokens) {
      tokens <- unique(Filter(nzchar, as.character(preferred_tokens %||% character(0))))
      if (!length(tokens)) return(NULL)

      uid <- helpers_mcp_tools$get_session_user_id(session)

      if (exists("resolve_uploaded_file", mode = "function")) {
        for (tok in tokens) {
			recovered <- try(
			  resolve_uploaded_file(
				tok,
				user_id = uid
			  ),
			  silent = TRUE
			)

          if (!inherits(recovered, "try-error") && path_ok(recovered)) {
            helpers_mcp_tools$mcp_debug_log(
              "[RESOLVE] Missing path recovered via resolve_uploaded_file -> ",
              recovered
            )
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
            helpers_mcp_tools$mcp_debug_log(
              "[RESOLVE] Missing path recovered via MCP base dir -> ",
              candidate
            )
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
                helpers_mcp_tools$mcp_debug_log(
                  "[RESOLVE] Missing path recovered via user_dir suffix match -> ",
                  recovered
                )
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
                helpers_mcp_tools$mcp_debug_log(
                  "[RESOLVE] Missing path recovered via unique extension match -> ",
                  recovered
                )
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

      helpers_mcp_tools$mcp_debug_log(
        "[RESOLVE] Match -> ",
        path_to_check,
        " Exists: ",
        !is.null(existing_path)
      )

      resolved_path <- NULL

      if (!is.null(existing_path)) {
        resolved_path <- existing_path
      } else {
        helpers_mcp_tools$mcp_debug_log(
          "[RESOLVE] Stored path missing for ",
          nm %||% key,
          " - attempting rehydrate"
        )

        recovered <- rehydrate_missing_path(c(nm, key, arg, base_arg, path_base))
        recovered_existing <- resolve_existing_candidate(recovered)

        if (!is.null(recovered_existing)) {
          resolved_path <- recovered_existing
          helpers_mcp_tools$update_session_file_path(session, c(key, nm), resolved_path)
          file_obj$path <- resolved_path
          file_obj$datapath <- resolved_path
          all_files[[key]] <- file_obj
        } else {
          helpers_mcp_tools$mcp_debug_log(
            "[RESOLVE] Path rehydrate failed for ",
            nm %||% key
          )
        }
      }

      if (!is.null(resolved_path)) {
        display_val <- file_obj$display %||% nm %||% basename(resolved_path)

        return(list(
          ok = TRUE,
          path = resolved_path,
          display = display_val
        ))
      }
    }
  } else {
    helpers_mcp_tools$mcp_debug_log("[RESOLVE] No files in session registry!")
  }

	idx_path <- getOption("mergen.index_path")
	uid <- helpers_mcp_tools$get_session_user_id(session)
	uid_key <- if (!is.null(uid) && length(uid) > 0L) as.character(uid[1]) else NULL

	allow_cross_bucket_lookup <- isTRUE(getOption("mergen.mcp.allow_cross_bucket_lookup", FALSE)) ||
	  tolower(trimws(Sys.getenv("MERGEN_MCP_ALLOW_CROSS_BUCKET_LOOKUP", "false"))) %in%
		c("1", "true", "t", "yes", "y", "on")

	if (!is.null(idx_path) && file.exists(idx_path)) {
	  idx <- jsonlite::read_json(idx_path, simplifyVector = TRUE)

    if (isTRUE(allow_cross_bucket_lookup)) {
      p2 <- idx[[tolower(base_arg)]]
      disp2 <- NULL

      if (is.list(p2)) {
        disp2 <- p2$display
        if (!is.null(p2$path)) p2 <- p2$path
      }

      if (!is.null(p2) && path_ok(p2)) {
        resolved_path <- resolve_existing_candidate(p2) %||% p2
        return(list(ok = TRUE, path = resolved_path, display = disp2 %||% basename(p2)))
      }
    }

    if (isTRUE(allow_cross_bucket_lookup) && length(idx)) {
      for (bucket_name in names(idx)) {
        bucket <- idx[[bucket_name]]

        if (is.list(bucket)) {
          p3 <- bucket[[tolower(base_arg)]]
          disp3 <- NULL

          if (is.list(p3)) {
            disp3 <- p3$display
            if (!is.null(p3$path)) p3 <- p3$path
          }

          if (!is.null(p3) && path_ok(p3)) {
            resolved_path <- resolve_existing_candidate(p3) %||% p3
            return(list(ok = TRUE, path = resolved_path, display = disp3 %||% basename(p3)))
          }
        }
      }
    } else {
      helpers_mcp_tools$mcp_debug_log(
        "[RESOLVE] Cross-bucket index lookup skipped; explicit opt-in is disabled."
      )
    }
  }

	if (!grepl("[/\\\\]", arg)) {
	  fb <- character(0)

	  if (!is.null(uid_key) && nzchar(uid_key)) {
		mcp_base <- getOption("mergen.mcp_base_dir")
		if (!is.null(mcp_base) && nzchar(mcp_base)) {
		  fb <- c(fb, file.path(mcp_base, paste0("user_", uid_key)))
		}
	  }

	  if (isTRUE(allow_cross_bucket_lookup)) {
		fb <- c(
		  fb,
		  getOption("mergen.files_root"),
		  getOption("mergen.mcp_base_dir")
		)
	  }

	  fb <- fb[!is.null(fb) & nzchar(fb)]

    for (base_dir in unique(fb)) {
      candidate <- file.path(base_dir, base_arg)

      if (path_ok(candidate)) {
        resolved_path <- candidate
        return(list(ok = TRUE, path = resolved_path, display = basename(candidate)))
      }
    }
  }

if (isTRUE(allow_cross_bucket_lookup) &&
    exists("global_lookup_file", mode = "function")) {
  p <- try(global_lookup_file(base_arg), silent = TRUE)

    if (!inherits(p, "try-error") && is.character(p) && nzchar(p) && path_ok(p)) {
      helpers_mcp_tools$mcp_debug_log(
        "[RESOLVE] Global registry hit -> ",
        p
      )

      resolved_path <- resolve_existing_candidate(p) %||% p
      return(list(ok = TRUE, path = resolved_path, display = basename(p)))
    }
  }

  known <- if (!is.null(all_files)) {
    unique(vapply(all_files, function(x) x$name %||% "?", character(1)))
  } else {
    character(0)
  }

  helpers_mcp_tools$mcp_debug_log(
    "[RESOLVE] NOT FOUND! Available files: ",
    paste(known, collapse = ", ")
  )

  list(
    ok = FALSE,
    error = sprintf(
      "Dosya '%s' bulunamadı.\nMevcut dosyalar: %s",
      arg,
      if (length(known)) paste(known, collapse = ", ") else "(hiç dosya yok)"
    )
  )
}

.mcp_file_resolver_fns <- c(
  "ensure_session_file_registry",
  "reset_session_file_registry",
  "update_session_file_path",
  "register_uploaded_file",
  "get_default_file_name",
  "auto_file_name",
  "resolve_file_argument"
)

for (.mcp_file_resolver_fn in .mcp_file_resolver_fns) {
  .mcp_file_resolver_fun <- get(
    .mcp_file_resolver_fn,
    envir = helpers_mcp_tools,
    inherits = FALSE
  )
  environment(.mcp_file_resolver_fun) <- helpers_mcp_tools
  assign(.mcp_file_resolver_fn, .mcp_file_resolver_fun, envir = helpers_mcp_tools)
}

rm(.mcp_file_resolver_missing)
rm(.mcp_file_resolver_fns)
rm(.mcp_file_resolver_fn)
rm(.mcp_file_resolver_fun)

if (exists(".mcp_resolver_context_path", inherits = FALSE)) {
  rm(.mcp_resolver_context_path)
}
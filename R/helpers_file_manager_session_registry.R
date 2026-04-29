# ==============================================================================
# Dosya Yolu: R/helpers_file_manager_session_registry.R
# Açıklama: Dosya Yönetimi oturum dosya kayıt defteri yardımcıları.
# ==============================================================================

.fm_registry_chr <- function(value, default = "") {
  if (is.null(value) || length(value) == 0L || is.na(value[1])) {
    return(default)
  }

  value_chr <- trimws(as.character(value[1]))
  if (!nzchar(value_chr)) {
    return(default)
  }

  value_chr
}

fm_normalize_session_registry_path <- function(fpath,
                                               path_exists_fn = NULL,
                                               normalize_path_fn = NULL) {
  path_chr <- .fm_registry_chr(fpath)
  if (!nzchar(path_chr)) {
    return("")
  }

  if (is.null(path_exists_fn)) {
    path_exists_fn <- if (exists("path_exists_relaxed", mode = "function", inherits = TRUE)) {
      path_exists_relaxed
    } else {
      file.exists
    }
  }

  if (is.null(normalize_path_fn)) {
    normalize_path_fn <- if (exists("normalize_mcp_path", mode = "function", inherits = TRUE)) {
      function(path) normalize_mcp_path(path, must_exist = FALSE)
    } else {
      function(path) normalizePath(path, winslash = "/", mustWork = FALSE)
    }
  }

  exists_now <- tryCatch(
    isTRUE(path_exists_fn(path_chr)),
    error = function(e) FALSE
  )

  norm_path <- if (isTRUE(exists_now)) {
    path_chr
  } else {
    tryCatch(
      .fm_registry_chr(normalize_path_fn(path_chr), default = path_chr),
      error = function(e) path_chr
    )
  }

  gsub("\\\\", "/", norm_path)
}

fm_session_registry_entry <- function(filename, fpath) {
  fname <- .fm_registry_chr(filename)
  path_chr <- .fm_registry_chr(fpath)

  if (!nzchar(fname) || !nzchar(path_chr)) {
    return(NULL)
  }

  list(
    name = fname,
    datapath = path_chr,
    path = path_chr,
    persisted_path = path_chr
  )
}

fm_ensure_session_registry <- function(session) {
  if (is.null(session) || is.null(session$userData)) {
    return(invisible(FALSE))
  }

  if (is.null(session$userData$current_session_files) ||
      !is.list(session$userData$current_session_files)) {
    session$userData$current_session_files <- list()
    return(invisible(TRUE))
  }

  invisible(FALSE)
}

fm_register_session_file <- function(session,
                                     filename,
                                     fpath,
                                     path_exists_fn = NULL,
                                     normalize_path_fn = NULL) {
  if (is.null(session) || is.null(session$userData)) {
    return(invisible(FALSE))
  }

  fname <- .fm_registry_chr(filename)
  if (!nzchar(fname)) {
    return(invisible(FALSE))
  }

  norm_path <- fm_normalize_session_registry_path(
    fpath = fpath,
    path_exists_fn = path_exists_fn,
    normalize_path_fn = normalize_path_fn
  )

  entry <- fm_session_registry_entry(fname, norm_path)
  if (is.null(entry)) {
    return(invisible(FALSE))
  }

  fm_ensure_session_registry(session)
  session$userData$current_session_files[[fname]] <- entry

  invisible(TRUE)
}

fm_unregister_session_file <- function(session, filename) {
  if (is.null(session) || is.null(session$userData)) {
    return(invisible(FALSE))
  }

  fname <- .fm_registry_chr(filename)
  if (!nzchar(fname)) {
    return(invisible(FALSE))
  }

  fm_ensure_session_registry(session)
  session$userData$current_session_files[[fname]] <- NULL

  invisible(TRUE)
}
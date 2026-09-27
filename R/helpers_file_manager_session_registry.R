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

# Oturum sahibi değişince (A -> B) ya da kimlik düşünce Dosya Yönetimi'nin
# önbellekteki satırları/içerik yolları, bağlam seçimi, geçici dosyaları ve
# uçuştaki yükleme partisi temizlenir; önceki kullanıcının dosyası indirilemez
# ya da yeni sahibin durumuna yazılamaz. Sahip değişiminde yalnız yeni sahibin
# envanteri yeniden yüklenir.
fm_register_owner_reset <- function(session, ns, module_values_provider, controller,
                                    scan_pending, refresh_fn, is_auth_ready) {
  if (!exists("mergen_session_on_owner_change", mode = "function")) return(invisible(NULL))
  sahip_nesli <- shiny::reactiveVal(0L)
  mergen_session_on_owner_change(session, function(neden) {
    mv <- module_values_provider()
    try(file_ingestion_cancel_controller(controller), silent = TRUE)
    for (p in session$userData$temp_files) try(unlink(p), silent = TRUE)
    session$userData$temp_files <- list()
    ids <- names(shiny::isolate(mv$files_in_context))
    mv$files <- shiny::isolate(mv$files)[0, , drop = FALSE]
    mv$file_contents <- list()
    mv$files_in_context <- list()
    mv$file_id_to_delete <- NULL
    scan_pending(TRUE)
    if (length(ids)) try(session$sendCustomMessage(ns("setAttachState"), list(ids = ids, checked = FALSE)), silent = TRUE)
    if (identical(neden, "sahip_degisti")) sahip_nesli(shiny::isolate(sahip_nesli()) + 1L)
  })
  shiny::observeEvent(sahip_nesli(), {
    if (!isTRUE(is_auth_ready())) return(invisible(NULL))
    scan_pending(FALSE)
    refresh_fn("owner_change")
  }, ignoreInit = TRUE)
  invisible(NULL)
}

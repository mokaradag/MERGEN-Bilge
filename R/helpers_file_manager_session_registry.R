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

# Oturum kimlik nesli: sahip değişiminde ve kimlik kaybında artar. Onay
# pencereleri açıldıkları nesle bağlanır (eski onay yeni sahibe işlem yapmaz).
fm_owner_generation <- function(session) {
  as.integer(tryCatch(session$userData$kimlik_nesli, error = function(e) NULL) %||% 0L)[1]
}

# Oturum sahibi değişince (A -> B) ya da kimlik düşünce Dosya Yönetimi'nin
# önbellekteki satırları/içerik yolları, bağlam seçimi, geçici dosyaları ve
# uçuştaki yükleme partisi temizlenir; önceki kullanıcının dosyası indirilemez
# ya da yeni sahibin durumuna yazılamaz. Kayıtlı dosyalar üst oturumun istem
# bağlamından da çıkarılır. Kimlik yeniden hazır olunca (yeni sahip ya da aynı
# kullanıcının yeniden girişi) yalnız o kullanıcının envanteri yüklenir.
fm_register_owner_reset <- function(session, ns, module_values_provider, controller,
                                    scan_pending, refresh_fn, is_auth_ready, detach_in_parent = NULL) {
  if (!exists("mergen_session_on_owner_change", mode = "function")) return(invisible(NULL))
  sahip_nesli <- shiny::reactiveVal(0L)
  kimlik_sinyali <- if (exists("mergen_session_identity_signal", mode = "function")) {
    mergen_session_identity_signal(session)
  } else {
    sahip_nesli
  }
  yeniden_yukle <- FALSE
  mergen_session_on_owner_change(session, function(neden) {
    mv <- module_values_provider()
    try(file_ingestion_cancel_controller(controller), silent = TRUE)
    for (p in session$userData$temp_files) try(unlink(p), silent = TRUE)
    session$userData$temp_files <- list()
    ids <- names(shiny::isolate(mv$files_in_context))
    if (is.function(detach_in_parent)) {
      icerik <- shiny::isolate(mv$file_contents)
      adlar <- unique(c(names(session$userData$current_session_files),
                        unlist(lapply(icerik[intersect(ids, names(icerik))], `[[`, "name"))))
      for (ad in adlar) try(detach_in_parent(ad), silent = TRUE)
    }
    session$userData$current_session_files <- list()
    mv$files <- shiny::isolate(mv$files)[0, , drop = FALSE]
    mv$file_contents <- list()
    mv$files_in_context <- list()
    mv$file_id_to_delete <- NULL
    # Önceki sahibin açık onay pencereleri (tek dosya/tümünü sil) kapatılır.
    try(shiny::removeModal(session = session), silent = TRUE)
    scan_pending(TRUE)
    if (length(ids)) try(session$sendCustomMessage(ns("setAttachState"), list(ids = ids, checked = FALSE)), silent = TRUE)
    yeniden_yukle <<- TRUE
    if (identical(neden, "sahip_degisti")) sahip_nesli(shiny::isolate(sahip_nesli()) + 1L)
  })
  shiny::observe({
    sahip_nesli()
    kimlik_sinyali()
    if (!isTRUE(yeniden_yukle) || !isTRUE(is_auth_ready())) return(invisible(NULL))
    yeniden_yukle <<- FALSE
    scan_pending(FALSE)
    shiny::isolate(refresh_fn("owner_change"))
  })
  invisible(NULL)
}

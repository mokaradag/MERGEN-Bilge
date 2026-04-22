# ==============================================================================
# Dosya Yolu: R/helpers_send_message_core.R
# Açıklama: send_message hattındaki yönlendirme, cleanup ve MCP hazırlık
# yardımcılarını tek yerde toplar. Amaç davranışı değiştirmeden
# server_send_message.R dosyasındaki merkezi baskıyı azaltmaktır.
# ==============================================================================

mergen_determine_tool_family <- function(settings_data, uploaded_count, skip_mcp_once, current_settings) {
  cfg_excel_on <- isTRUE(settings_data$enable_mcp_tools)
  cfg_sql_analysis_on <- isTRUE(settings_data$enable_rdata_tools)
  cfg_summarization_on <- isTRUE(settings_data$enable_summarization_tools)
  cfg_coding_on <- isTRUE(settings_data$enable_coding_tools)

  excel_allowed <- cfg_excel_on && uploaded_count > 0

  if (isTRUE(skip_mcp_once)) {
    tool_family <- "none"
  } else if (cfg_sql_analysis_on) {
    tool_family <- "sql_analysis"
    current_settings$max_output_tokens <- 4096
  } else if (excel_allowed) {
    tool_family <- "mcp_excel"
  } else if (cfg_summarization_on) {
    tool_family <- "summarization"
  } else if (cfg_coding_on) {
    tool_family <- "coding"
    current_settings$max_output_tokens <- 4096
  } else if (isTRUE(settings_data$enable_process_tools)) {
    tool_family <- "process"
  } else if (isTRUE(settings_data$enable_app_expert_tools)) {
    tool_family <- "app_expert"
  } else if (isTRUE(settings_data$enable_image_tools)) {
    tool_family <- "image"
  } else {
    tool_family <- "none"
  }

  list(
    tool_family = tool_family,
    current_settings = current_settings,
    cfg_excel_on = cfg_excel_on,
    cfg_sql_analysis_on = cfg_sql_analysis_on,
    cfg_summarization_on = cfg_summarization_on,
    cfg_coding_on = cfg_coding_on,
    excel_allowed = excel_allowed
  )
}

mergen_build_stream_profile <- function(tool_family, uploaded_count, settings_data, force_non_streaming_sql = FALSE) {
  stream_profile <- list(
    label = "standard",
    use_delta_transport = FALSE,
    poll_interval_ms = 50L
  )

  if ((identical(tool_family, "none") || identical(tool_family, "coding")) &&
      uploaded_count == 0 &&
      !isTRUE(settings_data$enable_tts_audio) &&
      !isTRUE(force_non_streaming_sql)) {
    stream_profile$label <- if (identical(tool_family, "coding")) "coding_fast" else "plain_fast"
    stream_profile$use_delta_transport <- TRUE
    stream_profile$poll_interval_ms <- 15L
  }

  stream_profile
}

mergen_cleanup_send_message <- function(values, reset_chat_state_fn, remove_typing_wrapper = TRUE) {
  if (isTRUE(remove_typing_wrapper)) {
    try(removeUI(selector = "#typing-animation-wrapper", immediate = TRUE), silent = TRUE)
  }

  values$typing <- FALSE
  reset_chat_state_fn()
  invisible(NULL)
}

mergen_abort_send_message <- function(
  session,
  values,
  reset_chat_state_fn,
  toast_message = NULL,
  toast_type = "warning",
  remove_typing_wrapper = TRUE
) {
  mergen_cleanup_send_message(
    values = values,
    reset_chat_state_fn = reset_chat_state_fn,
    remove_typing_wrapper = remove_typing_wrapper
  )

  msg <- tryCatch(as.character(toast_message %||% "")[1], error = function(e) "")
  if (nzchar(msg)) {
    showToast(session, msg, toast_type)
  }

  invisible(NULL)
}

mergen_prepare_mcp_session_files <- function(
  session,
  file_manager_data,
  uploaded_names,
  effective_user_id,
  current_settings,
  cache_mcp_file_locally_fn,
  update_mcp_registry_snapshot_fn,
  tool_family
) {
  if (!(identical(tool_family, "mcp_excel") && length(uploaded_names) > 0)) {
    session$userData$current_session_files <- list()
    return(list(
      current_session_files = list(),
      mcp_snapshot = update_mcp_registry_snapshot_fn(list())
    ))
  }

  fm_files <- file_manager_data$file_contents()

  resolve_from_manager <- function(target_name) {
    if (!length(fm_files)) return(NULL)

    for (fid in names(fm_files)) {
      obj <- fm_files[[fid]]
      nm  <- obj$name %||% basename(obj$datapath %||% obj$path %||% "")
      if (identical(nm, target_name)) {
        return(list(info = obj, id = fid))
      }
    }

    NULL
  }

  pick_existing_path <- function(info) {
    candidates <- c(info$persisted_path, info$path, info$datapath)
    candidates <- candidates[
      !vapply(candidates, function(x) is.null(x) || !nzchar(as.character(x)[1]), logical(1))
    ]

    for (cand in candidates) {
      c0 <- as.character(cand)[1]
      if (nzchar(c0) && path_exists_relaxed(c0)) return(c0)
    }

    NULL
  }

  csf <- list()

  for (fname in uploaded_names) {
    fm_hit <- resolve_from_manager(fname)
    finfo  <- fm_hit$info %||% list(name = fname)
    fid    <- fm_hit$id %||% NULL

    path_now <- pick_existing_path(finfo)
    if (is.null(path_now) || !nzchar(path_now)) {
      resolved <- try(resolve_uploaded_file(fname, effective_user_id), silent = TRUE)
      if (!inherits(resolved, "try-error") && nzchar(resolved) && path_exists_relaxed(resolved)) {
        path_now <- resolved
      }
    }

    if (is.null(path_now) || !nzchar(path_now) || !path_exists_relaxed(path_now)) {
      log_debug("[FILE STORE] {fname} için yol bulunamadı — atlanıyor")
      next
    }

    path_now <- tryCatch(
      normalizePath(path_now, winslash = "/", mustWork = TRUE),
      error = function(e) path_now
    )

    if (!grepl("^//[^/]+/[^/]+", gsub("\\\\", "/", path_now, fixed = TRUE))) {
      path_now <- safe_windows_short_path(path_now, must_exist = path_exists_relaxed(path_now))
    } else {
      path_now <- paste0("//", sub("^/+", "", gsub("\\\\", "/", path_now, fixed = TRUE)))
    }

    path_original <- path_now
    tryCatch({
      if (!is_under_mcp_base(path_now) && isTRUE(current_settings$enable_mcp_tools)) {
        copied <- copy_to_mcp_base(list(name = fname, datapath = path_now), effective_user_id)
        if (nzchar(copied) && path_exists_relaxed(copied)) path_now <- copied
      }
    }, error = function(e) {
      log_warn("[FILE STORE] copy_to_mcp_base başarısız: {e$message}")
    })

    cached_path <- cache_mcp_file_locally_fn(path_now)
    if (is.null(cached_path) || !nzchar(cached_path)) {
      cached_path <- path_now
    } else if (!identical(cached_path, path_now)) {
      log_debug("[FILE STORE] Yerel MCP önbelleği hazırlandı: {cached_path}")
    }
	
    if (!grepl("^//[^/]+/[^/]+", gsub("\\\\", "/", cached_path, fixed = TRUE))) {
      cached_path <- safe_windows_short_path(cached_path, must_exist = path_exists_relaxed(cached_path))
    } else {
      cached_path <- paste0("//", sub("^/+", "", gsub("\\\\", "/", cached_path, fixed = TRUE)))
    }

    file_obj <- list(
      name = fname,
      datapath = cached_path,
      path = cached_path,
      source_path = path_original
    )

    csf[[fname]] <- file_obj
    if (!is.null(fid)) csf[[fid]] <- file_obj
  }

  session$userData$current_session_files <- csf
  mcp_snapshot <- update_mcp_registry_snapshot_fn(csf)

  if (
    exists("helpers_mcp_tools", inherits = TRUE) &&
    is.function(helpers_mcp_tools$reset_session_file_registry) &&
    is.function(helpers_mcp_tools$register_uploaded_file)
  ) {
    helpers_mcp_tools$reset_session_file_registry(session)
    registered_keys <- character()

    for (key in names(csf)) {
      obj <- csf[[key]]
      if (!is.list(obj)) next

      path_reg <- obj$path %||% obj$datapath
      if (is.null(path_reg) || !nzchar(path_reg) || !path_exists_relaxed(path_reg)) next

      display <- obj$name %||% key
      tokens <- unique(c(key, display))

      for (tk in tokens) {
        if (!nzchar(tk) || tk %in% registered_keys) next

        try(
          helpers_mcp_tools$register_uploaded_file(
            session = session,
            token = tk,
            abs_path = path_reg,
            display_name = display
          ),
          silent = TRUE
        )

        registered_keys <- c(registered_keys, tk)
      }
    }
  }

  if (length(csf)) {
    unique_names <- unique(vapply(csf, function(x) x$name %||% "", character(1)))
    log_debug("[FILE STORE] MCP dosyaları (seçili): {paste(unique_names[nzchar(unique_names)], collapse = ', ')}")
  } else {
    log_debug("[FILE STORE] Filtreleme sonrasında geçerli MCP dosyası yok")
  }

  list(
    current_session_files = csf,
    mcp_snapshot = mcp_snapshot
  )
}
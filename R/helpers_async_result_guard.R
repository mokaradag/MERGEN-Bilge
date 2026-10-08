# Oturum sahibi ve istek sınırlarını koruyan asenkron sonuç yardımcıları.

# Sahip geri dönse bile önceki kimlik neslinin işi uygulanmaz.
mergen_session_owner_guard <- function(session) {
  ud <- session$userData
  owner <- ud$user_id
  generation <- ud$kimlik_nesli %||% 0L
  function() {
    tryCatch(
      !isTRUE(if (is.function(session$isClosed)) session$isClosed() else FALSE) &&
        identical(ud$user_id, owner) &&
        identical(ud$kimlik_nesli %||% 0L, generation),
      error = function(e) FALSE
    )
  }
}

mergen_chat_owner_guard <- function(session, values) {
  owner_guard <- mergen_session_owner_guard(session)
  chat_id <- shiny::isolate(values$current_chat_id)
  epoch <- session$userData$pk_unsaved_chat_epoch %||% 0L
  function() isTRUE(owner_guard()) &&
    identical(shiny::isolate(values$current_chat_id), chat_id) &&
    identical(session$userData$pk_unsaved_chat_epoch %||% 0L, epoch)
}

mergen_request_owner_guard <- function(session) {
  owner_guard <- mergen_session_owner_guard(session)
  request_owner <- session$userData$llm_request_owner
  function() isTRUE(owner_guard()) &&
    identical(session$userData$llm_request_owner, request_owner)
}

mergen_stream_request_current <- function(ctx, stream_env, completed = FALSE) {
  if (!isTRUE(stream_env$owner_guard())) return(FALSE)
  if (!identical(ctx$session$userData$llm_request_owner, stream_env$req_id)) return(FALSE)
  if (!identical(shiny::isolate(ctx$values$current_chat_id), stream_env$chat_id)) return(FALSE)
  if (!identical(ctx$session$userData$pk_unsaved_chat_epoch %||% 0L,
                 stream_env$chat_epoch)) return(FALSE)
  if (isTRUE(completed)) return(TRUE)
  mergen_is_current_request(ctx$active_request_id, stream_env$req_id, ctx$stop_generation)
}

mergen_stream_bind_cleanup <- function(ctx, stream_env) {
  cleanup <- function(...) {
    stream_env$finalized <- TRUE
    if (!is.null(ctx$values)) chat_discard_stream_placeholder(ctx$session, ctx$values, stream_env$msg_id)
    if (!is.null(stream_env$poll_observer)) {
      try(stream_env$poll_observer$destroy(), silent = TRUE)
      stream_env$poll_observer <- NULL
    }
    if (isTRUE(stream_env$settled)) {
      unlink(c(stream_env$stream_file, stream_env$stop_file), force = TRUE)
    } else if (!file.exists(stream_env$stop_file)) {
      file.create(stream_env$stop_file)
    }
    if (is.function(stream_env$remove_owner_hook)) stream_env$remove_owner_hook()
    if (is.function(stream_env$remove_end_hook)) stream_env$remove_end_hook()
    stream_env$remove_owner_hook <- stream_env$remove_end_hook <- NULL
    if (isTRUE(stream_env$owner_guard()) &&
        identical(.mergen_request_state_read(ctx$active_request_id), stream_env$req_id)) {
      ctx$active_request_id(NULL)
      shiny::withReactiveDomain(ctx$session, shiny::isolate(ctx$reset_chat_state_fn()))
    }
    invisible(NULL)
  }
  owner_cleanup <- function(...) {
    if (identical(.mergen_request_state_read(ctx$active_request_id), stream_env$req_id)) {
      ctx$active_request_id(NULL)
      shiny::withReactiveDomain(ctx$session, shiny::isolate(ctx$reset_chat_state_fn()))
    }
    cleanup()
  }
  if (exists("mergen_session_on_owner_change", mode = "function")) {
    stream_env$remove_owner_hook <- mergen_session_on_owner_change(ctx$session, owner_cleanup)
  }
  if (is.function(ctx$session$onSessionEnded)) {
    stream_env$remove_end_hook <- ctx$session$onSessionEnded(cleanup)
  }
  cleanup
}

mergen_bind_request_owner_cleanup <- function(session, active_request_id, req_id, reset_fn,
                                              values = NULL, stop_generation = NULL) {
  owner_guard <- if (is.null(values)) mergen_session_owner_guard(session) else
    mergen_chat_owner_guard(session, values)
  current <- function() isTRUE(owner_guard()) &&
    identical(.mergen_request_state_read(active_request_id), req_id) &&
    !isTRUE(if (is.function(stop_generation)) .mergen_request_state_read(stop_generation) else FALSE)
  session$userData$llm_worker_guard <- current
  remove_owner <- remove_end <- function() NULL
  remove <- function() {
    remove_owner()
    remove_end()
    if (identical(session$userData$llm_worker_guard, current)) session$userData$llm_worker_guard <- NULL
  }
  cleanup <- function(...) {
    remove()
    if (identical(.mergen_request_state_read(active_request_id), req_id)) {
      shiny::withReactiveDomain(session, shiny::isolate(reset_fn()))
      active_request_id(NULL)
    }
  }
  remove_owner <- mergen_session_on_owner_change(session, cleanup)
  if (is.function(session$onSessionEnded)) remove_end <- session$onSessionEnded(cleanup)
  remove
}

mergen_finish_request_owner_cleanup <- function(session, active_request_id, req_id,
                                                remove, reset_fn, owner_guard) {
  remove()
  if (isTRUE(owner_guard()) && identical(.mergen_request_state_read(active_request_id), req_id) &&
      identical(session$userData$llm_request_owner, req_id)) {
    reset_fn()
    active_request_id(NULL)
  }
  invisible(NULL)
}


mergen_dispatch_docx_preview <- function(path, session_token, cached = NULL,
                                         name = NULL, user_id = NULL, cancel_check = NULL) {
  globals <- list(docx_path = path, docx_name = name, docx_user_id = user_id,
                  docx_cached = cached, resolve_readable_path = resolve_readable_path)
  if (is.null(path)) {
    globals$resolve_uploaded_file <- resolve_uploaded_file
    globals <- c(globals, worker_monitor_expand_function_globals(globals))
  }
  globals$index_options <- options()[intersect(names(options()),
    c("mergen.mcp_base_dir", "mergen.index_path", "mergen.files_root"))]
  tracked_future_promise(
    task_fn = function() {
      old_options <- options(index_options)
      on.exit(options(old_options), add = TRUE)
      path <- docx_path
      if (is.null(path)) path <- resolve_uploaded_file(docx_name, user_id = docx_user_id)
      if (is.null(path) || !nzchar(path)) stop("Dosya bulunamadı veya erişilemiyor.")
      path <- resolve_readable_path(path)
      info <- file.info(path)
      if (is.na(info$size[1])) stop("Dosya bulunamadı veya erişilemiyor.")
      key <- paste(path, info$size[1], as.numeric(info$mtime[1]), sep = "||")
      b64 <- if (identical(key, docx_cached$key)) docx_cached$base64 else base64enc::base64encode(path)
      structure(b64, cache_key = key, resolved_path = path)
    },
    task_type = "file_preview_docx",
    cancel_check = cancel_check,
    session_token = session_token,
    dependency_mode = "explicit",
    globals = globals,
    packages = "base64enc"
  )
}

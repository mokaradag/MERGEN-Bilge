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
    if (!is.null(stream_env$poll_observer)) {
      try(stream_env$poll_observer$destroy(), silent = TRUE)
      stream_env$poll_observer <- NULL
    }
    if (isTRUE(stream_env$settled)) {
      unlink(c(stream_env$stream_file, stream_env$stop_file), force = TRUE)
      if (is.function(stream_env$remove_owner_hook)) stream_env$remove_owner_hook()
      if (is.function(stream_env$remove_end_hook)) stream_env$remove_end_hook()
    } else if (!file.exists(stream_env$stop_file)) {
      file.create(stream_env$stop_file)
    }
    if (isTRUE(stream_env$owner_guard()) &&
        identical(.mergen_request_state_read(ctx$active_request_id), stream_env$req_id)) {
      ctx$active_request_id(NULL)
    }
    invisible(NULL)
  }
  if (exists("mergen_session_on_owner_change", mode = "function")) {
    stream_env$remove_owner_hook <- mergen_session_on_owner_change(ctx$session, cleanup)
  }
  if (is.function(ctx$session$onSessionEnded)) {
    stream_env$remove_end_hook <- ctx$session$onSessionEnded(cleanup)
  }
  cleanup
}


mergen_dispatch_docx_preview <- function(path, session_token) {
  tracked_future_promise(
    task_fn = function() base64enc::base64encode(docx_path),
    task_type = "file_preview_docx",
    session_token = session_token,
    dependency_mode = "explicit",
    globals = list(docx_path = path),
    packages = "base64enc"
  )
}

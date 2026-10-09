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
  active <- .mergen_request_state_read(ctx$active_request_id)
  identical(active, stream_env$req_id) ||
    (isTRUE(.mergen_request_state_read(ctx$stop_generation)) &&
      is.character(active) && length(active) == 1L && startsWith(active, "cancelled_"))
}

mergen_stream_worker_guard <- function(ctx, stream_env) {
  function() !isTRUE(stream_env$finalized) && mergen_stream_request_current(ctx, stream_env) &&
    !isTRUE(.mergen_request_state_read(ctx$stop_generation))
}

mergen_stream_dispatch_error <- function(ctx, stream_env, cleanup) {
  function(error) {
    stream_env$settled <- TRUE
    cleanup()
    try(showToast(ctx$session, "Akış başlatılamadı. Lütfen yeniden deneyin.", "error"), silent = TRUE)
    promises::promise_reject(error)
  }
}

mergen_stream_bind_cleanup <- function(ctx, stream_env) {
  cleanup <- function(...) {
    stream_env$finalized <- TRUE
    if (!is.null(ctx$values)) try(chat_discard_stream_placeholder(ctx$session, ctx$values, stream_env$msg_id), silent = TRUE)
    if (!is.null(stream_env$poll_observer)) {
      try(stream_env$poll_observer$destroy(), silent = TRUE)
      stream_env$poll_observer <- NULL
    }
    if (isTRUE(stream_env$settled)) {
      unlink(c(stream_env$stream_file, stream_env$stop_file), force = TRUE)
    } else if (!file.exists(stream_env$stop_file)) {
      file.create(stream_env$stop_file)
    }
    if (is.function(stream_env$remove_owner_hook)) try(stream_env$remove_owner_hook(), silent = TRUE)
    if (is.function(stream_env$remove_end_hook)) try(stream_env$remove_end_hook(), silent = TRUE)
    stream_env$remove_owner_hook <- stream_env$remove_end_hook <- NULL
    if (isTRUE(stream_env$owner_guard())) mergen_clear_request_state(ctx$session,
      ctx$active_request_id, stream_env$req_id, ctx$reset_chat_state_fn, ctx$values)

    invisible(NULL)
  }
  owner_cleanup <- function(...) {
    cleanup()
    mergen_clear_request_state(ctx$session, ctx$active_request_id,
      stream_env$req_id, ctx$reset_chat_state_fn, ctx$values)
  }
  if (exists("mergen_session_on_owner_change", mode = "function")) {
    stream_env$remove_owner_hook <- mergen_session_on_owner_change(ctx$session, owner_cleanup)
  }
  if (is.function(ctx$session$onSessionEnded)) {
    stream_env$remove_end_hook <- ctx$session$onSessionEnded(owner_cleanup)
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
  lifecycle_observer <- NULL
  remove <- function() {
    try(remove_owner(), silent = TRUE)
    try(remove_end(), silent = TRUE)
    if (!is.null(lifecycle_observer)) lifecycle_observer$destroy()
    lifecycle_observer <<- NULL
    if (identical(session$userData$llm_worker_guard, current)) session$userData$llm_worker_guard <- NULL
  }
  cleanup <- function(...) {
    remove()
    mergen_clear_request_state(session, active_request_id, req_id, reset_fn, values)
  }
  if (is.function(session$onSessionEnded) && is.function(session$isClosed)) lifecycle_observer <- shiny::observe({
    shiny::invalidateLater(50, session)
    if (!isTRUE(current())) cleanup()
  }, domain = session)
  remove_owner <- mergen_session_on_owner_change(session, cleanup)
  if (is.function(session$onSessionEnded)) remove_end <- session$onSessionEnded(cleanup)
  remove
}

mergen_finish_request_owner_cleanup <- function(session, active_request_id, req_id,
                                                remove, reset_fn, owner_guard, values = NULL) {
  try(remove(), silent = TRUE)
  if (isTRUE(owner_guard()) && identical(session$userData$llm_request_owner, req_id)) {
    mergen_clear_request_state(session, active_request_id, req_id, reset_fn, values)
  }
  invisible(NULL)
}

mergen_clear_request_state <- function(session, active_request_id, req_id, reset_fn, values = NULL) {
  active <- .mergen_request_state_read(active_request_id)
  owns <- identical(active, req_id) ||
    (identical(session$userData$llm_request_owner, req_id) &&
      is.character(active) && length(active) == 1L && startsWith(active, "cancelled_"))
  if (!owns) return(invisible(FALSE))
  active_request_id(NULL)
  if (!is.null(values)) {
    try(mergen_send_message_release_values_token(values, req_id), silent = TRUE)
  }
  domain <- if (is.function(session$ns)) session else NULL
  try(shiny::withReactiveDomain(domain,
    shiny::removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)), silent = TRUE)
  reset <- try(shiny::withReactiveDomain(domain, shiny::isolate(reset_fn())), silent = TRUE)
  if (inherits(reset, "try-error") && !is.null(values))
    try(shiny::isolate({ values$is_sending <- FALSE; values$typing <- FALSE }), silent = TRUE)
  invisible(TRUE)
}


mergen_dispatch_docx_preview <- function(path, session_token, cached = NULL,
                                         name = NULL, user_id = NULL, cancel_check = NULL) {
  globals <- list(docx_path = path, docx_name = name, docx_user_id = user_id,
                  docx_cache_key = cached$key, resolve_readable_path = resolve_readable_path)
  if (is.null(path)) {
    globals$resolve_uploaded_file <- resolve_uploaded_file
    globals <- c(globals, worker_monitor_expand_function_globals(globals))
  }
  globals$index_options <- options()[intersect(names(options()),
    c("mergen.mcp_base_dir", "mergen.index_path", "mergen.files_root"))]
  promise <- tracked_future_promise(
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
      if (identical(key, docx_cache_key)) return(structure("", cache_key = key, resolved_path = path, cache_hit = TRUE))
      structure(base64enc::base64encode(path), cache_key = key, resolved_path = path)
    },
    task_type = "file_preview_docx",
    cancel_check = cancel_check,
    session_token = session_token,
    dependency_mode = "explicit",
    globals = globals,
    packages = "base64enc"
  )
  apply_cache <- function(value) {
    if (isTRUE(attr(value, "cache_hit"))) {
      return(structure(cached$base64, cache_key = attr(value, "cache_key"), resolved_path = attr(value, "resolved_path")))
    }
    value
  }
  if (promises::is.promise(promise)) promises::then(promise, apply_cache) else apply_cache(promise)
}

mergen_cancellable_tts_engine <- function(engine, current) {
  function(text, voice) engine(text, voice, cancel_check = current)
}

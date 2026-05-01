# ==============================================================================
# Dosya Yolu: R/server_runtime_context.R
# Açıklama: server.R erken başlatma nesneleri için küçük, açık sözleşmeli
#           çalışma zamanı bağlamı. Amaç server.R içindeki gevşek değişken
#           yayılımını azaltmak ve eksik/yanlış init sırasını erken yakalamaktır.
# ==============================================================================

is_server_runtime_context <- function(ctx) {
  is.environment(ctx) && inherits(ctx, "mergen_server_runtime_context")
}

.server_runtime_stop <- function(message) {
  stop(message, call. = FALSE)
}

.server_runtime_require_context <- function(ctx) {
  if (!is_server_runtime_context(ctx)) {
    .server_runtime_stop(
      "server_runtime_context: Geçerli bir mergen_server_runtime_context bekleniyor."
    )
  }

  invisible(TRUE)
}

.server_runtime_require_values <- function(x, names, owner) {
  missing <- names[vapply(
    names,
    function(nm) is.null(x[[nm]]),
    logical(1)
  )]

  if (length(missing) > 0L) {
    .server_runtime_stop(sprintf(
      "%s eksik zorunlu alan(lar): %s",
      owner,
      paste(missing, collapse = ", ")
    ))
  }

  invisible(TRUE)
}

.server_runtime_require_functions <- function(x, names, owner) {
  missing <- names[!vapply(
    names,
    function(nm) is.function(x[[nm]]),
    logical(1)
  )]

  if (length(missing) > 0L) {
    .server_runtime_stop(sprintf(
      "%s eksik zorunlu fonksiyon(lar): %s",
      owner,
      paste(missing, collapse = ", ")
    ))
  }

  invisible(TRUE)
}

serverRuntimeContextInit <- function(session,
                                     session_cache,
                                     sso_state,
                                     user_session) {
  if (is.null(session) || is.null(session$userData)) {
    .server_runtime_stop(
      "serverRuntimeContextInit: session$userData bulunamadı."
    )
  }

  .server_runtime_require_values(
    session_cache,
    c("mcp_saved_path"),
    "session_cache"
  )

  .server_runtime_require_functions(
    session_cache,
    c(
      "setup_user_session",
      "cache_mcp_file_locally",
      "update_mcp_registry_snapshot",
      "get_cache_dir"
    ),
    "session_cache"
  )

  .server_runtime_require_values(
    user_session,
    c("user_config_rv"),
    "user_session"
  )

  .server_runtime_require_functions(
    user_session,
    c(
      "resolve_current_user_id",
      "current_user_id_provider",
      "is_auth_ready",
      "get_current_user_id_snapshot",
      "get_cache_dir"
    ),
    "user_session"
  )

  ctx <- new.env(parent = emptyenv())
  class(ctx) <- c("mergen_server_runtime_context", "environment")

  ctx$session <- session
  ctx$sso_state <- sso_state

  ctx$cache <- list(
    mcp_saved_path = session_cache$mcp_saved_path,
    cache_root = session_cache$cache_root,
    setup_user_session = session_cache$setup_user_session,
    cache_mcp_file_locally = session_cache$cache_mcp_file_locally,
    update_mcp_registry_snapshot = session_cache$update_mcp_registry_snapshot,
    get_cache_dir = session_cache$get_cache_dir
  )

  ctx$identity <- list(
    user_config_rv = user_session$user_config_rv,
    resolve_current_user_id = user_session$resolve_current_user_id,
    current_user_id_provider = user_session$current_user_id_provider,
    is_auth_ready = user_session$is_auth_ready,
    get_current_user_id_snapshot = user_session$get_current_user_id_snapshot,
    get_cache_dir = user_session$get_cache_dir
  )

  ctx$refs <- NULL
  ctx$state <- NULL
  ctx$chat <- NULL
  ctx$modules <- list()

  ctx
}

serverRuntimeAttachForwardRefs <- function(ctx, forward_refs) {
  .server_runtime_require_context(ctx)

  .server_runtime_require_values(
    forward_refs,
    c("welcome_fns", "send_message_fns"),
    "forward_refs"
  )

  .server_runtime_require_functions(
    forward_refs,
    c("render_welcome_screen", "start_new_chat", "send_message"),
    "forward_refs"
  )

  ctx$refs <- forward_refs

  invisible(ctx)
}

serverRuntimeAttachState <- function(ctx, state_bundle) {
  .server_runtime_require_context(ctx)

  .server_runtime_require_values(
    state_bundle,
    c("values"),
    "state_bundle"
  )

  .server_runtime_require_functions(
    state_bundle,
    c(
      "stop_generation",
      "file_to_add",
      "session_files",
      "active_request_id",
      "quick_action_skip_mcp",
      "sync_feedback_from_db"
    ),
    "state_bundle"
  )

  ctx$state <- state_bundle

  invisible(ctx)
}

serverRuntimeAttachChat <- function(ctx, chat_runtime) {
  .server_runtime_require_context(ctx)

  .server_runtime_require_functions(
    chat_runtime,
    c(
      "reset_chat_state",
      "add_message",
      "generate_title_from_prompt",
      "simulate_streaming_stoppable"
    ),
    "chat_runtime"
  )

  ctx$chat <- chat_runtime

  invisible(ctx)
}

serverRuntimeAttachModule <- function(ctx,
                                      name,
                                      value,
                                      required_functions = character(0)) {
  .server_runtime_require_context(ctx)

  if (is.null(name) || length(name) != 1L || !nzchar(name)) {
    .server_runtime_stop(
      "serverRuntimeAttachModule: Geçerli bir modül adı bekleniyor."
    )
  }

  if (length(required_functions) > 0L) {
    .server_runtime_require_functions(
      value,
      required_functions,
      sprintf("runtime module '%s'", name)
    )
  }

  ctx$modules[[name]] <- value

  invisible(ctx)
}
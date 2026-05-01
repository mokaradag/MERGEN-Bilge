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
      "is_sso_active",
      "get_auth_source",
      "get_user_config",
      "get_first_name",
      "get_display_name",
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
    is_sso_active = user_session$is_sso_active,
    get_auth_source = user_session$get_auth_source,
    get_user_config = user_session$get_user_config,
    get_first_name = user_session$get_first_name,
    get_display_name = user_session$get_display_name,
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

serverRuntimeGetModule <- function(ctx,
                                   name,
                                   required_functions = character(0)) {
  .server_runtime_require_context(ctx)

  if (is.null(name) || length(name) != 1L || !nzchar(as.character(name))) {
    .server_runtime_stop(
      "serverRuntimeGetModule: Geçerli bir modül adı bekleniyor."
    )
  }

  name <- as.character(name)
  module_value <- ctx$modules[[name]]

  if (is.null(module_value)) {
    .server_runtime_stop(sprintf(
      "serverRuntimeGetModule: '%s' modülü runtime context içinde kayıtlı değil.",
      name
    ))
  }

  if (length(required_functions) > 0L) {
    .server_runtime_require_functions(
      module_value,
      required_functions,
      sprintf("runtime module '%s'", name)
    )
  }

  module_value
}

serverRuntimeExposeSessionData <- function(ctx,
                                           key,
                                           value,
                                           overwrite = TRUE) {
  .server_runtime_require_context(ctx)

  if (is.null(key) || length(key) != 1L || !nzchar(as.character(key))) {
    .server_runtime_stop(
      "serverRuntimeExposeSessionData: Geçerli bir oturum anahtarı bekleniyor."
    )
  }

  if (is.null(ctx$session) || is.null(ctx$session$userData)) {
    .server_runtime_stop(
      "serverRuntimeExposeSessionData: session$userData bulunamadı."
    )
  }

  key <- as.character(key)
  already_exists <- exists(key, envir = ctx$session$userData, inherits = FALSE)

  if (isTRUE(already_exists) && !isTRUE(overwrite)) {
    .server_runtime_stop(sprintf(
      "serverRuntimeExposeSessionData: '%s' oturum verisi zaten mevcut.",
      key
    ))
  }

  ctx$session$userData[[key]] <- value

  invisible(ctx)
}

serverRuntimeOnSsoAuthReady <- function(ctx,
                                        callback,
                                        label = "auth_ready",
                                        once = TRUE,
                                        ignore_init = TRUE,
                                        observe_event_fn = shiny::observeEvent,
                                        req_fn = shiny::req) {
  .server_runtime_require_context(ctx)

  if (is.null(label) || length(label) != 1L || !nzchar(as.character(label))) {
    label <- "auth_ready"
  }
  label <- as.character(label)

  if (!is.function(callback)) {
    .server_runtime_stop(sprintf(
      "serverRuntimeOnSsoAuthReady[%s]: callback fonksiyon olmalıdır.",
      label
    ))
  }

  .server_runtime_require_functions(
    ctx$identity,
    c("is_sso_active", "is_auth_ready"),
    "runtime identity"
  )

  # Yerel modda mevcut başlangıç akışını değiştirme; bu yardımcı yalnızca SSO sonrası işler içindir.
  if (!isTRUE(ctx$identity$is_sso_active())) {
    return(invisible(FALSE))
  }

  if (is.null(ctx$sso_state)) {
    .server_runtime_stop(sprintf(
      "serverRuntimeOnSsoAuthReady[%s]: SSO modunda sso_state gereklidir.",
      label
    ))
  }

  observer <- observe_event_fn(ctx$sso_state$authenticated, {
    req_fn(
      isTRUE(ctx$sso_state$authenticated),
      isTRUE(ctx$identity$is_auth_ready())
    )

    callback(ctx)
  }, ignoreInit = ignore_init, once = once)

  invisible(observer)
}

serverRuntimeRefreshModuleOnSsoAuthReady <- function(ctx,
                                                     module_name,
                                                     refresh_function,
                                                     refresh_args = list(),
                                                     label = NULL,
                                                     once = TRUE,
                                                     ignore_init = TRUE,
                                                     observe_event_fn = shiny::observeEvent,
                                                     req_fn = shiny::req) {
  .server_runtime_require_context(ctx)

  if (is.null(module_name) ||
      length(module_name) != 1L ||
      !nzchar(as.character(module_name))) {
    .server_runtime_stop(
      "serverRuntimeRefreshModuleOnSsoAuthReady: Geçerli bir modül adı bekleniyor."
    )
  }

  if (is.null(refresh_function) ||
      length(refresh_function) != 1L ||
      !nzchar(as.character(refresh_function))) {
    .server_runtime_stop(
      "serverRuntimeRefreshModuleOnSsoAuthReady: Geçerli bir yenileme fonksiyonu adı bekleniyor."
    )
  }

  if (!is.list(refresh_args)) {
    .server_runtime_stop(
      "serverRuntimeRefreshModuleOnSsoAuthReady: refresh_args liste olmalıdır."
    )
  }

  module_name <- as.character(module_name)
  refresh_function <- as.character(refresh_function)

  if (is.null(label) || length(label) != 1L || !nzchar(as.character(label))) {
    label <- paste0(module_name, "_", refresh_function, "_auth_ready")
  }

  # SSO modunda eksik modül/fonksiyon sözleşmesini observer çalışmadan önce yakala.
  if (isTRUE(ctx$identity$is_sso_active())) {
    serverRuntimeGetModule(
      ctx,
      module_name,
      required_functions = refresh_function
    )
  }

  serverRuntimeOnSsoAuthReady(
    ctx = ctx,
    label = label,
    once = once,
    ignore_init = ignore_init,
    observe_event_fn = observe_event_fn,
    req_fn = req_fn,
    callback = function(ctx) {
      module_value <- serverRuntimeGetModule(
        ctx,
        module_name,
        required_functions = refresh_function
      )

      do.call(module_value[[refresh_function]], refresh_args)
    }
  )
}

serverRuntimeAttachRefreshableModule <- function(ctx,
                                                 name,
                                                 value,
                                                 required_functions = character(0),
                                                 refresh_function = NULL,
                                                 refresh_args = list(),
                                                 label = NULL,
                                                 expose_session_key = NULL,
                                                 overwrite_session_key = TRUE,
                                                 once = TRUE,
                                                 ignore_init = TRUE,
                                                 observe_event_fn = shiny::observeEvent,
                                                 req_fn = shiny::req) {
  .server_runtime_require_context(ctx)

  if (!is.list(refresh_args)) {
    .server_runtime_stop(
      "serverRuntimeAttachRefreshableModule: refresh_args liste olmalıdır."
    )
  }

  ctx <- serverRuntimeAttachModule(
    ctx = ctx,
    name = name,
    value = value,
    required_functions = required_functions
  )

  if (!is.null(expose_session_key)) {
    ctx <- serverRuntimeExposeSessionData(
      ctx = ctx,
      key = expose_session_key,
      value = value,
      overwrite = overwrite_session_key
    )
  }

  if (!is.null(refresh_function)) {
    serverRuntimeRefreshModuleOnSsoAuthReady(
      ctx = ctx,
      module_name = name,
      refresh_function = refresh_function,
      refresh_args = refresh_args,
      label = label,
      once = once,
      ignore_init = ignore_init,
      observe_event_fn = observe_event_fn,
      req_fn = req_fn
    )
  }

  invisible(ctx)
}
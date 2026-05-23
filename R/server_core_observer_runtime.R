# ==============================================================================
# Dosya Yolu: R/server_core_observer_runtime.R
# Açıklama: serverBindCoreInteractionRuntime içindeki çekirdek gözlemci,
#           boot-readiness ve Dosya Yönetimi bağlama sorumluluklarını küçük,
#           açık sözleşmeli bir runtime yardımcıda toplar.
# ==============================================================================

.server_core_observer_stop <- function(message) {
  .server_runtime_stop(message)
}

.server_core_observer_require_context <- function(runtime_ctx) {
  if (!is_server_runtime_context(runtime_ctx)) {
    .server_core_observer_stop(
      "serverBindCoreObserverRuntime: Geçerli bir server runtime context bekleniyor."
    )
  }

  invisible(TRUE)
}

.server_core_observer_require_functions <- function(named_functions) {
  .server_runtime_require_named_functions(
    named_functions,
    "serverBindCoreObserverRuntime"
  )

  invisible(TRUE)
}

.server_core_observer_require_bundle <- function(core_bundle) {
  if (!is.list(core_bundle)) {
    .server_core_observer_stop(
      "serverBindCoreObserverRuntime: core_bundle liste olmalıdır."
    )
  }

  .server_runtime_require_values(
    core_bundle,
    c(
      "settings_data",
      "api_config",
      "media_modules",
      "render_welcome_screen",
      "start_new_chat",
      "send_message"
    ),
    "serverBindCoreObserverRuntime core_bundle"
  )

  if (!is.list(core_bundle$media_modules)) {
    .server_core_observer_stop(
      "serverBindCoreObserverRuntime: core_bundle$media_modules liste olmalıdır."
    )
  }

  .server_runtime_require_values(
    core_bundle$media_modules,
    c("ai_expert", "tts_processor"),
    "serverBindCoreObserverRuntime core_bundle$media_modules"
  )

  .server_core_observer_require_functions(list(
    render_welcome_screen = core_bundle$render_welcome_screen,
    start_new_chat = core_bundle$start_new_chat,
    send_message = core_bundle$send_message
  ))

  invisible(TRUE)
}

.server_core_observer_call_with_optional_boot_ready <- function(fn,
                                                                args,
                                                                boot_ready) {
  fn_formals <- names(formals(fn))
  accepts_dots <- "..." %in% fn_formals

  if (!is.null(boot_ready) &&
      ("boot_ready" %in% fn_formals || accepts_dots)) {
    args$boot_ready <- boot_ready
  }

  do.call(fn, args)
}

serverBindCoreObserverRuntime <- function(input,
                                          output,
                                          session,
                                          runtime_ctx,
                                          core_bundle,
                                          chat_rebind_all_charts_fn = chat_rebind_all_charts,
                                          chat_export_init_fn = chatExportInit,
                                          quick_actions_init_fn = quickActionsInit,
                                          settings_observers_init_fn = settingsObserversInit,
                                          session_timeout_server_fn = sessionTimeoutServer,
                                          file_manager_runtime_fn = serverBindFileManagerRuntime,
                                          chat_ui_observers_init_fn = chatUIObserversInit,
                                          navigation_observers_init_fn = navigationObserversInit,
                                          startup_observers_init_fn = startupObserversInit,
                                          startup_screen_observers_init_fn = startupScreenObserversInit,
                                          ai_expert_handlers_init_fn = aiExpertHandlersInit,
                                          storage_observers_init_fn = storageObserversInit,
                                          file_observers_init_fn = fileObserversInit,
                                          file_click_observers_init_fn = fileClickObserversInit,
                                          reactive_fn = shiny::reactive,
                                          boot_readiness_init_fn = bootReadinessInit) {
  .server_core_observer_require_context(runtime_ctx)
  .server_core_observer_require_bundle(core_bundle)

  settings_data <- core_bundle$settings_data
  api_config <- core_bundle$api_config
  media_modules <- core_bundle$media_modules
  render_welcome_screen <- core_bundle$render_welcome_screen
  start_new_chat <- core_bundle$start_new_chat
  send_message <- core_bundle$send_message

  state <- serverRuntimeRequireState(
    runtime_ctx,
    required_values = c("values"),
    required_functions = c(
      "file_to_add",
      "session_files",
      "quick_action_skip_mcp"
    ),
    owner = "serverBindCoreObserverRuntime state"
  )

  identity <- serverRuntimeRequireIdentity(
    runtime_ctx,
    required_functions = c(
      "current_user_id_provider",
      "get_display_name"
    ),
    owner = "serverBindCoreObserverRuntime identity"
  )

  .server_core_observer_require_functions(list(
    current_user_id_provider = identity$current_user_id_provider,
    current_user_display_name = identity$get_display_name,
    file_to_add = state$file_to_add,
    session_files = state$session_files,
    quick_action_skip_mcp = state$quick_action_skip_mcp,
    chat_rebind_all_charts_fn = chat_rebind_all_charts_fn,
    chat_export_init_fn = chat_export_init_fn,
    quick_actions_init_fn = quick_actions_init_fn,
    settings_observers_init_fn = settings_observers_init_fn,
    session_timeout_server_fn = session_timeout_server_fn,
    file_manager_runtime_fn = file_manager_runtime_fn,
    chat_ui_observers_init_fn = chat_ui_observers_init_fn,
    navigation_observers_init_fn = navigation_observers_init_fn,
    startup_observers_init_fn = startup_observers_init_fn,
    startup_screen_observers_init_fn = startup_screen_observers_init_fn,
    ai_expert_handlers_init_fn = ai_expert_handlers_init_fn,
    storage_observers_init_fn = storage_observers_init_fn,
    file_observers_init_fn = file_observers_init_fn,
    file_click_observers_init_fn = file_click_observers_init_fn,
    reactive_fn = reactive_fn,
    boot_readiness_init_fn = boot_readiness_init_fn
  ))

  values <- state$values
  boot_ready <- boot_readiness_init_fn(session)
  runtime_ctx$modules$boot_ready <- boot_ready

  file_runtime <- serverRuntimeRequireFileRuntime(
    runtime_ctx,
    require_prelude = TRUE,
    require_manager = FALSE
  )

  chat_export_init_fn(
    input,
    output,
    session,
    values,
    user_display_name = function() {
      identity$get_display_name(default = "Kullanıcı")
    }
  )

  quick_actions_init_fn(
    input = input,
    session = session,
    values = values,
    settings_data = settings_data,
    session_files = state$session_files,
    quick_action_skip_mcp = state$quick_action_skip_mcp,
    output = output,
    current_user_id = identity$current_user_id_provider,
    send_message_fn = send_message
  )

  settings_observers_init_fn(input, session, values, settings_data)

  session_timeout_server_fn(
    "session_timeout",
    idle_minutes    = 30,
    activity_inputs = c("user_input", "send_stop_btn", "send_prompt_from_js")
  )

  file_manager_runtime <- file_manager_runtime_fn(
    runtime_ctx = runtime_ctx,
    new_file_trigger = reactive_fn({ state$file_to_add() }),
    session_files_reactive = state$session_files,
    mcp_enabled_reactive = reactive_fn({
      isTRUE(settings_data$enable_mcp_tools)
    }),
    settings_data = settings_data,
    user_id_provider = identity$current_user_id_provider
  )

  runtime_ctx <- file_manager_runtime$runtime_ctx

  file_runtime <- serverRuntimeRequireFileRuntime(
    runtime_ctx,
    require_prelude = TRUE,
    require_manager = TRUE
  )

  file_manager_data <- file_runtime$file_manager_data

  chat_ui_observers_init_fn(
    input,
    session,
    values,
    start_new_chat,
    send_message,
    render_welcome_screen,
    settings_data
  )

  navigation_observers_init_fn(
    input,
    session,
    values,
    render_welcome_screen
  )

  .server_core_observer_call_with_optional_boot_ready(
    fn = startup_observers_init_fn,
    args = list(
      input = input,
      session = session,
      values = values,
      render_welcome_screen = render_welcome_screen,
      current_user_id = identity$current_user_id_provider,
      sso_state = runtime_ctx$sso_state
    ),
    boot_ready = boot_ready
  )

  .server_core_observer_call_with_optional_boot_ready(
    fn = startup_screen_observers_init_fn,
    args = list(
      input = input,
      session = session,
      settings_data = settings_data
    ),
    boot_ready = boot_ready
  )

  ai_expert_handlers_init_fn(
    input,
    session,
    values,
    settings_data,
    media_modules$ai_expert,
    media_modules$tts_processor,
    identity$current_user_id_provider,
    chat_history_rv = reactive_fn(values$messages)
  )

  storage_observers_init_fn(
    input,
    session,
    output,
    values,
    settings_data,
    chat_rebind_all_charts_fn
  )

  file_observers_init_fn(
    input,
    session,
    settings_data,
    state$session_files,
    file_manager_data,
    identity$current_user_id_provider
  )

  file_click_observers_init_fn(
    input,
    session,
    settings_data,
    api_config,
    file_runtime$filePreview,
    file_manager_data,
    state$session_files
  )

  list(
    runtime_ctx = runtime_ctx,
    file_runtime = file_runtime,
    file_manager_data = file_manager_data,
    filePreview = file_runtime$filePreview,
    fallback_followup_tool = file_runtime$fallback_followup_tool,
    followup_tools = file_runtime$followup_tools
  )
}
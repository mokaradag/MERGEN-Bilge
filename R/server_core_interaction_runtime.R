# ==============================================================================
# Dosya Yolu: R/server_core_interaction_runtime.R
# Açıklama: server.R içindeki çekirdek etkileşim gözlemcileri, dosya yöneticisi
#           ve sohbet kalıcılığı bağlama sırasını açık sözleşmeli tek yardımcıda
#           toplar. Amaç server.R orkestrasyon yükünü azaltmaktır.
# ==============================================================================

.server_core_interaction_stop <- function(message) {
  stop(message, call. = FALSE)
}

.server_core_interaction_require_context <- function(runtime_ctx) {
  if (!is_server_runtime_context(runtime_ctx)) {
    .server_core_interaction_stop(
      "serverBindCoreInteractionRuntime: Geçerli bir server runtime context bekleniyor."
    )
  }

  invisible(TRUE)
}

.server_core_interaction_require_functions <- function(named_functions) {
  missing <- names(named_functions)[!vapply(
    named_functions,
    is.function,
    logical(1)
  )]

  if (length(missing) > 0L) {
    .server_core_interaction_stop(sprintf(
      "serverBindCoreInteractionRuntime eksik/geçersiz fonksiyon(lar): %s",
      paste(missing, collapse = ", ")
    ))
  }

  invisible(TRUE)
}

.server_core_interaction_require_values <- function(x, names, owner) {
  missing <- names[vapply(
    names,
    function(nm) is.null(x[[nm]]),
    logical(1)
  )]

  if (length(missing) > 0L) {
    .server_core_interaction_stop(sprintf(
      "%s eksik zorunlu alan(lar): %s",
      owner,
      paste(missing, collapse = ", ")
    ))
  }

  invisible(TRUE)
}

serverBindCoreInteractionRuntime <- function(input,
                                             output,
                                             session,
                                             runtime_ctx,
                                             settings_data,
                                             api_config,
                                             media_modules,
                                             render_welcome_screen,
                                             start_new_chat,
                                             send_message,
                                             load_chat_in_progress,
                                             welcome_fns,
                                             user_config_provider,
                                             user_first_name_fn,
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
                                             chat_persistence_modules_fn = serverBindChatPersistenceModules,
                                             reactive_fn = shiny::reactive) {
  .server_core_interaction_require_context(runtime_ctx)

  if (is.null(runtime_ctx$state)) {
    .server_core_interaction_stop(
      "serverBindCoreInteractionRuntime: runtime_ctx$state henüz kurulmadı."
    )
  }

  if (!is.environment(welcome_fns)) {
    .server_core_interaction_stop(
      "serverBindCoreInteractionRuntime: welcome_fns ortam olmalıdır."
    )
  }

  state <- runtime_ctx$state
  identity <- runtime_ctx$identity
  values <- state$values

  .server_core_interaction_require_values(
    state,
    c(
      "values",
      "file_to_add",
      "session_files",
      "quick_action_skip_mcp"
    ),
    "runtime_ctx$state"
  )

  .server_core_interaction_require_values(
    media_modules,
    c(
      "ai_expert",
      "tts_processor"
    ),
    "media_modules"
  )

  .server_core_interaction_require_functions(list(
    current_user_id_provider = identity$current_user_id_provider,
    current_user_display_name = identity$get_display_name,
    render_welcome_screen = render_welcome_screen,
    start_new_chat = start_new_chat,
    send_message = send_message,
    user_config_provider = user_config_provider,
    user_first_name_fn = user_first_name_fn,
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
    chat_persistence_modules_fn = chat_persistence_modules_fn,
    reactive_fn = reactive_fn
  ))

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
    activity_inputs = c("user_input", "send_btn", "send_prompt_from_js")
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

  startup_observers_init_fn(
    input = input,
    session = session,
    values = values,
    render_welcome_screen = render_welcome_screen,
    current_user_id = identity$current_user_id_provider,
    sso_state = runtime_ctx$sso_state
  )

  startup_screen_observers_init_fn(input, session, settings_data)

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

  chat_persistence <- chat_persistence_modules_fn(
    input = input,
    output = output,
    session = session,
    runtime_ctx = runtime_ctx,
    values = values,
    settings_data = settings_data,
    load_chat_in_progress = load_chat_in_progress,
    session_files = state$session_files,
    filePreview = file_runtime$filePreview,
    file_manager_data = file_manager_data,
    current_user_id_provider = identity$current_user_id_provider,
    user_config_provider = user_config_provider,
    user_first_name_fn = user_first_name_fn,
    welcome_fns = welcome_fns
  )

  runtime_ctx <- chat_persistence$runtime_ctx

  list(
    runtime_ctx = runtime_ctx,
    saved_chats_data = chat_persistence$saved_chats_data,
    file_manager_data = file_manager_data,
    filePreview = file_runtime$filePreview,
    fallback_followup_tool = file_runtime$fallback_followup_tool,
    followup_tools = file_runtime$followup_tools
  )
}
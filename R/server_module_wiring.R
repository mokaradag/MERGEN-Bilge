# ==============================================================================
# Dosya Yolu: R/server_module_wiring.R
# Açıklama: server.R içindeki orta seviye modül bağlama bloklarını küçük,
#           açık sözleşmeli yardımcılar altında toplar.
# ==============================================================================

.server_wiring_stop <- function(message) {
  stop(message, call. = FALSE)
}

.server_wiring_require_function <- function(fn, name) {
  if (!is.function(fn)) {
    .server_wiring_stop(sprintf(
      "server_module_wiring: '%s' fonksiyon olmalıdır.",
      name
    ))
  }

  invisible(TRUE)
}

.server_wiring_require_functions <- function(named_functions) {
  invisible(lapply(names(named_functions), function(name) {
    .server_wiring_require_function(named_functions[[name]], name)
  }))
}

.server_wiring_require_context <- function(ctx, owner) {
  if (!is_server_runtime_context(ctx)) {
    .server_wiring_stop(sprintf(
      "%s: Geçerli bir server runtime context bekleniyor.",
      owner
    ))
  }

  invisible(TRUE)
}

serverBindServiceModules <- function(current_user_id_provider,
                                     performance_stats_server_fn = performanceStatsServer,
                                     health_server_fn = healthServer,
                                     destek_server_fn = destekServer) {
  .server_wiring_require_functions(list(
    current_user_id_provider = current_user_id_provider,
    performance_stats_server_fn = performance_stats_server_fn,
    health_server_fn = health_server_fn,
    destek_server_fn = destek_server_fn
  ))

  perf_tracker <- performance_stats_server_fn(
    "perf_stats",
    current_user_id_provider
  )

  health_server_fn(
    "health_module",
    perf_tracker = perf_tracker
  )

  destek_server_fn(
    "destek_module",
    current_user_id = current_user_id_provider
  )

  list(
    perf_tracker = perf_tracker
  )
}

serverBindSettingsAndRefs <- function(input,
                                      output,
                                      session,
                                      runtime_ctx,
                                      current_user_id_provider,
                                      user_first_name_fn,
                                      settings_init_fn = settingsInit,
                                      forward_refs_init_fn = serverInitForwardRefs,
                                      claude_code_server_fn = claudeCodeServer,
                                      visual_settings_sync_init_fn = visualSettingsSyncInit,
                                      chat_outputs_init_fn = chatOutputsInit,
                                      reactive_val_fn = shiny::reactiveVal) {
  .server_wiring_require_context(runtime_ctx, "serverBindSettingsAndRefs")

  .server_wiring_require_functions(list(
    current_user_id_provider = current_user_id_provider,
    user_first_name_fn = user_first_name_fn,
    settings_init_fn = settings_init_fn,
    forward_refs_init_fn = forward_refs_init_fn,
    claude_code_server_fn = claude_code_server_fn,
    visual_settings_sync_init_fn = visual_settings_sync_init_fn,
    chat_outputs_init_fn = chat_outputs_init_fn,
    reactive_val_fn = reactive_val_fn
  ))

  settings_data <- settings_init_fn(
    session = session,
    parent_session = session
  )

  runtime_ctx <- serverRuntimeAttachForwardRefs(
    runtime_ctx,
    forward_refs_init_fn(session)
  )

  claude_code_server_fn(
    "claude_code_module",
    current_user_id = current_user_id_provider,
    settings_data = settings_data,
    user_first_name = function() {
      user_first_name_fn(default = "")
    }
  )

  visual_settings_sync_init_fn(input, settings_data)

  load_chat_in_progress <- reactive_val_fn(FALSE)

  chat_outputs_init_fn(output, settings_data)

  list(
    settings_data = settings_data,
    runtime_ctx = runtime_ctx,
    welcome_fns = runtime_ctx$refs$welcome_fns,
    render_welcome_screen = runtime_ctx$refs$render_welcome_screen,
    start_new_chat = runtime_ctx$refs$start_new_chat,
    send_message_fns = runtime_ctx$refs$send_message_fns,
    send_message = runtime_ctx$refs$send_message,
    load_chat_in_progress = load_chat_in_progress
  )
}

serverBindMediaModules <- function(input,
                                   session,
                                   settings_data,
                                   current_user_id_provider,
                                   feedback_server_fn = feedbackServer,
                                   ai_processing_server_fn = aiProcessingServer,
                                   tts_processing_server_fn = ttsProcessingServer,
                                   tts_visualizer_server_fn = ttsVisualizerServer,
                                   music_handlers_init_fn = musicHandlersInit,
                                   ai_expert_server_fn = aiExpertServer,
                                   stt_server_fn = sttServer) {
  .server_wiring_require_functions(list(
    current_user_id_provider = current_user_id_provider,
    feedback_server_fn = feedback_server_fn,
    ai_processing_server_fn = ai_processing_server_fn,
    tts_processing_server_fn = tts_processing_server_fn,
    tts_visualizer_server_fn = tts_visualizer_server_fn,
    music_handlers_init_fn = music_handlers_init_fn,
    ai_expert_server_fn = ai_expert_server_fn,
    stt_server_fn = stt_server_fn
  ))

  feedback_modal <- feedback_server_fn(
    "feedback_module",
    current_user_id_provider
  )

  ai_processor <- ai_processing_server_fn("ai_proc")
  tts_processor <- tts_processing_server_fn("tts_proc")
  tts_visualizer <- tts_visualizer_server_fn("tts_viz", settings_data)

  music_handlers_init_fn(input, session, settings_data)

  ai_expert <- ai_expert_server_fn(
    "ai_expert_module",
    settings_data,
    tts_processor,
    tts_visualizer
  )

  stt_data <- stt_server_fn(
    "stt_module",
    parent_session = session,
    settings = settings_data
  )

  list(
    feedback_modal = feedback_modal,
    ai_processor = ai_processor,
    tts_processor = tts_processor,
    tts_visualizer = tts_visualizer,
    ai_expert = ai_expert,
    stt_data = stt_data
  )
}

serverBindFilePreludeModules <- function(session,
                                         runtime_ctx = NULL,
                                         file_preview_server_fn = filePreviewServer,
                                         create_followup_tool_fn = create_followup_suggestions_tool,
                                         followup_suggestions_server_fn = followupSuggestionsServer,
                                         init_docx_preview_js_fn = init_docx_preview_js) {
  .server_wiring_require_functions(list(
    file_preview_server_fn = file_preview_server_fn,
    create_followup_tool_fn = create_followup_tool_fn,
    followup_suggestions_server_fn = followup_suggestions_server_fn,
    init_docx_preview_js_fn = init_docx_preview_js_fn
  ))

  filePreview <- file_preview_server_fn("file_preview")

  fallback_followup_tool <- create_followup_tool_fn()
  followup_tools <- followup_suggestions_server_fn("followup_module")

  if (is.null(followup_tools) || is.null(followup_tools$generate)) {
    followup_tools <- fallback_followup_tool
  }

  init_docx_preview_js_fn(session)

  result <- list(
    filePreview = filePreview,
    fallback_followup_tool = fallback_followup_tool,
    followup_tools = followup_tools
  )

  if (!is.null(runtime_ctx)) {
    .server_wiring_require_context(
      runtime_ctx,
      "serverBindFilePreludeModules"
    )

    result$runtime_ctx <- serverRuntimeAttachFilePrelude(
      runtime_ctx,
      result
    )
  }

  result
}

serverBindFileManagerRuntime <- function(runtime_ctx,
                                         new_file_trigger,
                                         session_files_reactive,
                                         mcp_enabled_reactive,
                                         settings_data,
                                         user_id_provider,
                                         file_manager_server_fn = fileManagerServer,
                                         observe_event_fn = shiny::observeEvent,
                                         req_fn = shiny::req) {
  .server_wiring_require_context(runtime_ctx, "serverBindFileManagerRuntime")

  .server_wiring_require_functions(list(
    new_file_trigger = new_file_trigger,
    session_files_reactive = session_files_reactive,
    mcp_enabled_reactive = mcp_enabled_reactive,
    user_id_provider = user_id_provider,
    file_manager_server_fn = file_manager_server_fn
  ))

  identity <- serverRuntimeRequireIdentity(
    runtime_ctx,
    required_functions = c("is_auth_ready"),
    owner = "serverBindFileManagerRuntime identity"
  )

  file_manager_data <- file_manager_server_fn(
    "file_manager_module",
    new_file_trigger = new_file_trigger,
    session_files_reactive = session_files_reactive,
    mcp_enabled_reactive = mcp_enabled_reactive,
    user_id = user_id_provider,
    settings_data = settings_data,
    auth_ready_provider = identity$is_auth_ready
  )

  runtime_ctx <- serverRuntimeAttachRefreshableModule(
    ctx = runtime_ctx,
    name = "file_manager",
    value = file_manager_data,
    required_functions = c("refresh_persisted_files", "file_contents"),
    refresh_function = "refresh_persisted_files",
    refresh_args = list("auth_ready"),
    label = "file_manager_refresh",
    expose_session_key = "file_manager_data",
    observe_event_fn = observe_event_fn,
    req_fn = req_fn
  )

  runtime_ctx <- serverRuntimeAttachFileManager(
    ctx = runtime_ctx,
    file_manager_data = file_manager_data
  )

  list(
    runtime_ctx = runtime_ctx,
    file_manager_data = file_manager_data
  )
}

serverBindImageGalleryRuntime <- function(runtime_ctx,
                                          current_user_id_provider,
                                          image_gallery_server_fn = imageGalleryServer,
                                          observe_event_fn = shiny::observeEvent,
                                          req_fn = shiny::req) {
  .server_wiring_require_context(runtime_ctx, "serverBindImageGalleryRuntime")

  .server_wiring_require_functions(list(
    current_user_id_provider = current_user_id_provider,
    image_gallery_server_fn = image_gallery_server_fn
  ))

  gallery_data <- image_gallery_server_fn(
    "image_gallery_module",
    current_user_id_provider
  )

  runtime_ctx <- serverRuntimeAttachRefreshableModule(
    ctx = runtime_ctx,
    name = "image_gallery",
    value = gallery_data,
    required_functions = "refresh",
    refresh_function = "refresh",
    label = "image_gallery_refresh",
    observe_event_fn = observe_event_fn,
    req_fn = req_fn
  )

  list(
    runtime_ctx = runtime_ctx,
    gallery_data = gallery_data
  )
}

serverBindChatPersistenceModules <- function(input,
                                             output,
                                             session,
                                             runtime_ctx,
                                             values,
                                             settings_data,
                                             load_chat_in_progress,
                                             session_files,
                                             filePreview,
                                             file_manager_data,
                                             current_user_id_provider,
                                             user_config_provider,
                                             user_first_name_fn,
                                             welcome_fns,
                                             saved_chats_server_fn = savedChatsServer,
                                             saved_chats_observers_init_fn = savedChatsObserversInit,
                                             chat_search_init_fn = chatSearchInit,
                                             image_gallery_runtime_fn = serverBindImageGalleryRuntime,
                                             image_gallery_observers_init_fn = imageGalleryObserversInit,
                                             welcome_handlers_init_fn = welcomeHandlersInit,
                                             download_outputs_init_fn = downloadOutputsInit,
                                             history_server_fn = historyServer,
                                             message_search_init_fn = messageSearchInit,
                                             reactive_fn = shiny::reactive,
                                             js_run_fn = shinyjs::runjs) {
  .server_wiring_require_context(runtime_ctx, "serverBindChatPersistenceModules")

  .server_wiring_require_functions(list(
    current_user_id_provider = current_user_id_provider,
    user_config_provider = user_config_provider,
    user_first_name_fn = user_first_name_fn,
    saved_chats_server_fn = saved_chats_server_fn,
    saved_chats_observers_init_fn = saved_chats_observers_init_fn,
    chat_search_init_fn = chat_search_init_fn,
    image_gallery_runtime_fn = image_gallery_runtime_fn,
    image_gallery_observers_init_fn = image_gallery_observers_init_fn,
    welcome_handlers_init_fn = welcome_handlers_init_fn,
    download_outputs_init_fn = download_outputs_init_fn,
    history_server_fn = history_server_fn,
    message_search_init_fn = message_search_init_fn,
    reactive_fn = reactive_fn,
    js_run_fn = js_run_fn
  ))

  .server_wiring_require_functions(list(
    file_manager_refresh_persisted_files = file_manager_data$refresh_persisted_files,
    file_manager_file_contents = file_manager_data$file_contents
  ))

  if (!is.environment(welcome_fns)) {
    .server_wiring_stop(
      "serverBindChatPersistenceModules: welcome_fns ortam olmalıdır."
    )
  }

  saved_chats_data <- saved_chats_server_fn(
    "saved_chats_module",
    saved_chats = reactive_fn(values$saved_chats)
  )

  saved_chats_observers_init_fn(
    input,
    output,
    session,
    values,
    settings_data,
    saved_chats_data,
    current_user_id_provider,
    load_chat_in_progress,
    user_config_provider = user_config_provider,
    user_first_name_fn = user_first_name_fn
  )

  chat_search_init_fn(input, session, current_user_id_provider, function(chat_id) {
    js_run_fn(sprintf(
      "Shiny.setInputValue('welcome_load_chat_id', '%s', {priority: 'event'});",
      chat_id
    ))
  })

  gallery_runtime <- image_gallery_runtime_fn(
    runtime_ctx = runtime_ctx,
    current_user_id_provider = current_user_id_provider
  )

  runtime_ctx <- gallery_runtime$runtime_ctx
  gallery_data <- gallery_runtime$gallery_data

  image_gallery_observers_init_fn(
    input,
    session,
    values,
    settings_data,
    gallery_data,
    saved_chats_data,
    current_user_id_provider,
    load_chat_in_progress
  )

  welcome_handlers <- welcome_handlers_init_fn(
    session,
    values,
    saved_chats_data,
    session_files,
    filePreview,
    current_user_id_provider,
    file_manager_data,
    user_first_name = function() {
      user_first_name_fn(default = "")
    }
  )

  welcome_fns$render_welcome_screen <- welcome_handlers$render_welcome_screen
  welcome_fns$start_new_chat <- welcome_handlers$start_new_chat

  download_outputs_init_fn(
    output,
    session,
    session_files,
    current_user_id_provider
  )

  history_server_fn(
    "history_module",
    all_messages = reactive_fn(values$saved_chats),
    current_user_id = current_user_id_provider
  )

  message_search_init_fn(
    input,
    session,
    values,
    reactive_fn(values$messages)
  )

  list(
    runtime_ctx = runtime_ctx,
    saved_chats_data = saved_chats_data,
    gallery_data = gallery_data,
    welcome_handlers = welcome_handlers
  )
}

serverBindChatEngineRuntime <- function(input,
                                        output,
                                        session,
                                        runtime_ctx,
                                        settings_data,
                                        api_key,
                                        user_config_rv,
                                        perf_tracker,
                                        ai_processor,
                                        tts_processor,
                                        tts_visualizer,
                                        stt_data,
                                        saved_chats_data,
                                        feedback_modal = NULL,
                                        send_message_fns,
                                        send_message_proxy,
                                        api_config,
                                        admin_pool = NULL,
                                        chat_runtime_init_fn = serverInitChatRuntime,
                                        llm_response_handlers_init_fn = llmResponseHandlersInit,
                                        chat_input_observers_init_fn = chatInputObserversInit,
                                        misc_observers_init_fn = miscObserversInit,
                                        chat_actions_init_fn = chatActionsInit,
                                        tts_handlers_init_fn = ttsHandlersInit,
                                        send_message_init_fn = sendMessageInit) {
  .server_wiring_require_context(runtime_ctx, "serverBindChatEngineRuntime")

  if (!is.environment(send_message_fns)) {
    .server_wiring_stop(
      "serverBindChatEngineRuntime: send_message_fns ortam olmalıdır."
    )
  }

  state <- serverRuntimeRequireState(
    runtime_ctx,
    required_values = c("values"),
    required_functions = c(
      "stop_generation",
      "file_to_add",
      "session_files",
      "active_request_id",
      "quick_action_skip_mcp"
    ),
    owner = "serverBindChatEngineRuntime state"
  )

  identity <- serverRuntimeRequireIdentity(
    runtime_ctx,
    required_functions = c(
      "resolve_current_user_id",
      "current_user_id_provider"
    ),
    owner = "serverBindChatEngineRuntime identity"
  )

  cache <- serverRuntimeRequireCache(
    runtime_ctx,
    required_functions = c(
      "cache_mcp_file_locally",
      "update_mcp_registry_snapshot"
    ),
    owner = "serverBindChatEngineRuntime cache"
  )

  file_runtime <- serverRuntimeRequireFileRuntime(
    runtime_ctx,
    require_prelude = TRUE,
    require_manager = TRUE
  )

  .server_wiring_require_functions(list(
    resolve_current_user_id = identity$resolve_current_user_id,
    current_user_id_provider = identity$current_user_id_provider,
    stop_generation = state$stop_generation,
    file_to_add = state$file_to_add,
    session_files = state$session_files,
    active_request_id = state$active_request_id,
    quick_action_skip_mcp = state$quick_action_skip_mcp,
    cache_mcp_file_locally_fn = cache$cache_mcp_file_locally,
    update_mcp_registry_snapshot_fn = cache$update_mcp_registry_snapshot,
    send_message_proxy = send_message_proxy,
    chat_runtime_init_fn = chat_runtime_init_fn,
    llm_response_handlers_init_fn = llm_response_handlers_init_fn,
    chat_input_observers_init_fn = chat_input_observers_init_fn,
    misc_observers_init_fn = misc_observers_init_fn,
    chat_actions_init_fn = chat_actions_init_fn,
    tts_handlers_init_fn = tts_handlers_init_fn,
    send_message_init_fn = send_message_init_fn
  ))

  .server_wiring_require_functions(list(
    perf_tracker_track_error = perf_tracker$track_error,
    perf_tracker_track_request = perf_tracker$track_request,
    ai_processor_call_llm_non_streaming = ai_processor$call_llm_non_streaming,
    file_manager_refresh_persisted_files = file_runtime$file_manager_data$refresh_persisted_files,
    file_manager_file_contents = file_runtime$file_manager_data$file_contents
  ))

  values <- state$values

  chat_runtime <- chat_runtime_init_fn(
    session = session,
    values = values,
    settings_data = settings_data,
    output = output,
    resolve_current_user_id = identity$resolve_current_user_id,
    stop_generation = state$stop_generation
  )

  runtime_ctx <- serverRuntimeAttachChat(runtime_ctx, chat_runtime)

  reset_chat_state <- runtime_ctx$chat$reset_chat_state
  add_message <- runtime_ctx$chat$add_message
  generate_title_from_prompt <- runtime_ctx$chat$generate_title_from_prompt
  simulate_streaming_stoppable <- runtime_ctx$chat$simulate_streaming_stoppable

  tts_trigger_slot <- serverRuntimeCreateFunctionSlot(
    "trigger_tts_for_message"
  )

  llm_handlers <- llm_response_handlers_init_fn(
    session = session,
    values = values,
    settings_data = settings_data,
    ai_processor = ai_processor,
    perf_tracker = perf_tracker,
    active_request_id = state$active_request_id,
    stop_generation = state$stop_generation,
    reset_chat_state_fn = reset_chat_state,
    add_message_fn = add_message,
    trigger_tts_fn = tts_trigger_slot$call,
    followup_tools = file_runtime$followup_tools,
    fallback_followup_tool = file_runtime$fallback_followup_tool,
    api_config = api_config
  )

  .server_wiring_require_functions(list(
    generate_non_streaming_stoppable = llm_handlers$generate_non_streaming_stoppable
  ))

  chat_input_observers_init_fn(
    input,
    session,
    values,
    settings_data,
    state$stop_generation,
    state$active_request_id,
    reset_chat_state,
    send_message_proxy,
    identity$current_user_id_provider,
    file_runtime$file_manager_data,
    state$session_files,
    state$file_to_add,
    stt_data
  )

  misc_observers_init_fn(
    input,
    output,
    session,
    values,
    file_runtime$file_manager_data,
    file_runtime$filePreview,
    add_message,
    api_key,
    user_config_rv,
    admin_pool
  )

  chat_actions_init_fn(
    input,
    session,
    values,
    current_user_id = identity$current_user_id_provider,
    send_message_fn = send_message_proxy,
    stop_generation = state$stop_generation,
    reset_chat_state = reset_chat_state,
    feedback_modal = feedback_modal
  )

  tts_handlers <- tts_handlers_init_fn(
    session,
    values,
    settings_data,
    tts_processor,
    tts_visualizer,
    state$stop_generation
  )

  .server_wiring_require_functions(list(
    trigger_tts_for_message = tts_handlers$trigger_tts_for_message,
    attach_tts_audio = tts_handlers$attach_tts_audio
  ))

  tts_trigger_slot$set(tts_handlers$trigger_tts_for_message)

  send_message_handlers <- send_message_init_fn(
    session = session,
    input = input,
    output = output,
    values = values,
    settings_data = settings_data,
    session_files = state$session_files,
    file_manager_data = file_runtime$file_manager_data,
    current_user_id = identity$current_user_id_provider,
    stop_generation = state$stop_generation,
    active_request_id = state$active_request_id,
    quick_action_skip_mcp = state$quick_action_skip_mcp,
    perf_tracker = perf_tracker,
    ai_processor = ai_processor,
    tts_processor = tts_processor,
    followup_tools = file_runtime$followup_tools,
    fallback_followup_tool = file_runtime$fallback_followup_tool,
    api_config = api_config,
    add_message_fn = add_message,
    reset_chat_state_fn = reset_chat_state,
    simulate_streaming_stoppable_fn = simulate_streaming_stoppable,
    cache_mcp_file_locally_fn = cache$cache_mcp_file_locally,
    update_mcp_registry_snapshot_fn = cache$update_mcp_registry_snapshot,
    saved_chats_data = saved_chats_data,
    generate_non_streaming_stoppable_fn = llm_handlers$generate_non_streaming_stoppable
  )

  .server_wiring_require_functions(list(
    send_message = send_message_handlers$send_message
  ))

  send_message_fns$send_message <- send_message_handlers$send_message

  chat_engine <- list(
    chat_runtime = chat_runtime,
    llm_handlers = llm_handlers,
    tts_handlers = tts_handlers,
    send_message_handlers = send_message_handlers,
    tts_trigger_slot = tts_trigger_slot,
    reset_chat_state = reset_chat_state,
    add_message = add_message,
    generate_title_from_prompt = generate_title_from_prompt,
    simulate_streaming_stoppable = simulate_streaming_stoppable,
    trigger_tts_for_message = tts_trigger_slot$call,
    send_message = send_message_handlers$send_message
  )

  runtime_ctx <- serverRuntimeAttachModule(
    ctx = runtime_ctx,
    name = "chat_engine",
    value = chat_engine,
    required_functions = c(
      "reset_chat_state",
      "add_message",
      "trigger_tts_for_message",
      "send_message"
    )
  )

  list(
    runtime_ctx = runtime_ctx,
    chat_engine = chat_engine,
    reset_chat_state = reset_chat_state,
    add_message = add_message,
    generate_title_from_prompt = generate_title_from_prompt,
    simulate_streaming_stoppable = simulate_streaming_stoppable,
    trigger_tts_for_message = tts_trigger_slot$call,
    attach_tts_audio = tts_handlers$attach_tts_audio,
    send_message = send_message_handlers$send_message
  )
}
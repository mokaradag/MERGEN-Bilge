# ==============================================================================
# Dosya Yolu: R/server_chat_engine_runtime.R
# Açıklama: Sohbet motoru runtime bağlamasını server_module_wiring.R dışına alır.
#           Amaç server_module_wiring.R satır/fonksiyon bütçesini korumaktır.
# ==============================================================================

serverBindChatEngineRuntime <- function(input,
                                        output,
                                        session,
                                        runtime_ctx,
                                        chat_engine_deps = NULL,
                                        settings_data = NULL,
                                        api_key = NULL,
                                        user_config_rv = NULL,
                                        perf_tracker = NULL,
                                        media_modules = NULL,
                                        ai_processor = NULL,
                                        tts_processor = NULL,
                                        tts_visualizer = NULL,
                                        stt_data = NULL,
                                        saved_chats_data = NULL,
                                        feedback_modal = NULL,
                                        send_message_fns = NULL,
                                        send_message_proxy = NULL,
                                        api_config = NULL,
                                        admin_pool = NULL,
                                        chat_runtime_init_fn = serverInitChatRuntime,
                                        llm_response_handlers_init_fn = llmResponseHandlersInit,
                                        chat_input_observers_init_fn = chatInputObserversInit,
                                        misc_observers_init_fn = miscObserversInit,
                                        chat_actions_init_fn = chatActionsInit,
                                        tts_handlers_init_fn = ttsHandlersInit,
                                        send_message_init_fn = sendMessageInit) {
  .server_wiring_require_context(runtime_ctx, "serverBindChatEngineRuntime")

  chat_engine_deps <- .server_wiring_resolve_chat_engine_deps(
    chat_engine_deps = chat_engine_deps,
    settings_data = settings_data,
    api_key = api_key,
    user_config_rv = user_config_rv,
    perf_tracker = perf_tracker,
    saved_chats_data = saved_chats_data,
    send_message_fns = send_message_fns,
    send_message_proxy = send_message_proxy,
    api_config = api_config,
    media_modules = media_modules,
    ai_processor = ai_processor,
    tts_processor = tts_processor,
    tts_visualizer = tts_visualizer,
    stt_data = stt_data,
    admin_pool = admin_pool,
    feedback_modal = feedback_modal
  )

  settings_data <- chat_engine_deps$settings_data
  api_key <- chat_engine_deps$api_key
  user_config_rv <- chat_engine_deps$user_config_rv
  perf_tracker <- chat_engine_deps$perf_tracker
  ai_processor <- chat_engine_deps$ai_processor
  tts_processor <- chat_engine_deps$tts_processor
  tts_visualizer <- chat_engine_deps$tts_visualizer
  stt_data <- chat_engine_deps$stt_data
  saved_chats_data <- chat_engine_deps$saved_chats_data
  send_message_fns <- chat_engine_deps$send_message_fns
  send_message_proxy <- chat_engine_deps$send_message_proxy
  api_config <- chat_engine_deps$api_config
  admin_pool <- chat_engine_deps$admin_pool
  feedback_modal <- chat_engine_deps$feedback_modal

  .server_wiring_require_environment(
    send_message_fns,
    "serverBindChatEngineRuntime: send_message_fns"
  )

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
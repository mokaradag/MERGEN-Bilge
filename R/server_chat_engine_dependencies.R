# ==============================================================================
# Dosya Yolu: R/server_chat_engine_dependencies.R
# Açıklama: Sohbet motoru için server.R ile server_module_wiring.R arasında
#           taşınan dış bağımlılıkları küçük ve doğrulanabilir bir bundle altında
#           toplar. Runtime state/cache/file/chat bağlamı runtime_ctx içinde kalır.
# ==============================================================================

.server_wiring_require_chat_engine_deps <- function(chat_engine_deps) {
  if (!is.list(chat_engine_deps)) {
    .server_wiring_stop(
      "chat_engine_deps liste olmalıdır."
    )
  }

  .server_runtime_require_values(
    chat_engine_deps,
    c(
      "settings_data",
      "api_key",
      "user_config_rv",
      "perf_tracker",
      "ai_processor",
      "tts_processor",
      "tts_visualizer",
      "stt_data",
      "saved_chats_data",
      "send_message_fns",
      "send_message_proxy",
      "api_config"
    ),
    "chat_engine_deps"
  )

  .server_wiring_require_environment(
    chat_engine_deps$send_message_fns,
    "chat_engine_deps$send_message_fns"
  )

  .server_wiring_require_functions(list(
    send_message_proxy = chat_engine_deps$send_message_proxy,
    perf_tracker_track_error = chat_engine_deps$perf_tracker$track_error,
    perf_tracker_track_request = chat_engine_deps$perf_tracker$track_request,
    ai_processor_call_llm_non_streaming = chat_engine_deps$ai_processor$call_llm_non_streaming
  ))

  invisible(TRUE)
}

serverBuildChatEngineDependencyBundle <- function(settings_data,
                                                  api_key,
                                                  user_config_rv,
                                                  perf_tracker,
                                                  saved_chats_data,
                                                  send_message_fns,
                                                  send_message_proxy,
                                                  api_config,
                                                  media_modules = NULL,
                                                  ai_processor = NULL,
                                                  tts_processor = NULL,
                                                  tts_visualizer = NULL,
                                                  stt_data = NULL,
                                                  admin_pool = NULL,
                                                  feedback_modal = NULL) {
  if (!is.null(media_modules)) {
    if (is.null(ai_processor)) {
      ai_processor <- media_modules$ai_processor
    }

    if (is.null(tts_processor)) {
      tts_processor <- media_modules$tts_processor
    }

    if (is.null(tts_visualizer)) {
      tts_visualizer <- media_modules$tts_visualizer
    }

    if (is.null(stt_data)) {
      stt_data <- media_modules$stt_data
    }

    if (is.null(feedback_modal)) {
      feedback_modal <- media_modules$feedback_modal
    }
  }

  chat_engine_deps <- list(
    settings_data = settings_data,
    api_key = api_key,
    user_config_rv = user_config_rv,
    perf_tracker = perf_tracker,
    ai_processor = ai_processor,
    tts_processor = tts_processor,
    tts_visualizer = tts_visualizer,
    stt_data = stt_data,
    saved_chats_data = saved_chats_data,
    send_message_fns = send_message_fns,
    send_message_proxy = send_message_proxy,
    api_config = api_config,
    admin_pool = admin_pool,
    feedback_modal = feedback_modal
  )

  .server_wiring_require_chat_engine_deps(chat_engine_deps)

  class(chat_engine_deps) <- c(
    "mergen_chat_engine_dependency_bundle",
    "list"
  )

  chat_engine_deps
}

.server_wiring_resolve_chat_engine_deps <- function(chat_engine_deps,
                                                    settings_data,
                                                    api_key,
                                                    user_config_rv,
                                                    perf_tracker,
                                                    saved_chats_data,
                                                    send_message_fns,
                                                    send_message_proxy,
                                                    api_config,
                                                    media_modules = NULL,
                                                    ai_processor = NULL,
                                                    tts_processor = NULL,
                                                    tts_visualizer = NULL,
                                                    stt_data = NULL,
                                                    admin_pool = NULL,
                                                    feedback_modal = NULL) {
  if (!is.null(chat_engine_deps)) {
    .server_wiring_require_chat_engine_deps(chat_engine_deps)
    return(chat_engine_deps)
  }

  serverBuildChatEngineDependencyBundle(
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
}
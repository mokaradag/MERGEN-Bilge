# ==============================================================================
# Dosya Yolu: R/server_handler_streaming_tts.R
# Açıklama: TTS (Yanıtları Seslendir) açıkken streaming AI yanıtını işleyen
#           sunucu tarafı işleyici. Promise zinciri ile tam yanıtı alır, takip
#           sorularını üretir ve sesli oynatma için simulate_streaming çağırır.
#           TTS kapalı gerçek SSE yolundan (handle_true_streaming_mode) ayrıdır;
#           davranış send_message içindeki eski satır içi daldan birebir taşındı.
# ==============================================================================
# TTS açık streaming modunu işler. send_message üç terminal LLM dalını (gerçek
# SSE / TTS streaming / non-streaming) ctx tabanlı işleyicilere yönlendirir; bu
# dosya TTS streaming dalını üstlenir. Stale-istek/durdurma kararları
# mergen_send_message_request_state(...) üzerinden istek kimliği kapsamlı kalır.
handle_streaming_tts_mode <- function(ctx) {
  session <- ctx$session
  values <- ctx$values
  settings_data <- ctx$settings_data
  stop_generation <- ctx$stop_generation
  active_request_id <- ctx$active_request_id
  perf_tracker <- ctx$perf_tracker
  api_config <- ctx$api_config
  ai_processor <- ctx$ai_processor
  tts_processor <- ctx$tts_processor
  followup_tools <- ctx$followup_tools
  fallback_followup_tool <- ctx$fallback_followup_tool
  simulate_streaming_stoppable_fn <- ctx$simulate_streaming_stoppable_fn
  cleanup_send_message <- ctx$cleanup_send_message
  abort_send_message <- ctx$abort_send_message
  current_settings <- ctx$current_settings
  model_selected <- ctx$model_selected
  messages_to_process <- ctx$messages_to_process
  user_message_text <- ctx$user_message_text
  user_prompt_msg <- ctx$user_prompt_msg
  chat_id_val <- ctx$chat_id_val
  effective_user_id <- ctx$current_user_id
  req_id <- ctx$request_id
  # TTS açıkken mevcut davranışı koru
  start_time <- Sys.time()
  active_request_id(req_id)
  session_guard <- mergen_session_owner_guard(session)
  owner_guard <- mergen_chat_owner_guard(session, values)
  session$userData$llm_request_owner <- req_id
  remove_owner_cleanup <- mergen_bind_request_owner_cleanup(
    session, active_request_id, req_id, cleanup_send_message, values, stop_generation
  )
  handed_off <- FALSE
  on.exit(if (!handed_off) mergen_finish_request_owner_cleanup(session, active_request_id,
    req_id, remove_owner_cleanup, cleanup_send_message, session_guard, values), add = TRUE)
  log_debug("[MONITORING] AI isteği başlatılıyor (STREAMING modu)")
  simulated <- FALSE
  stop_generation(FALSE)
  values$is_sending <- TRUE
  # Kritik yol dostu: varsayılan yalnızca hafif sayım/boyut özeti; tam istem/ayar
  # dökümü yalnızca açık tanılama bayrağıyla (MERGEN_LLM_REQUEST_DEBUG/MERGEN_DEBUG).
  mergen_log_llm_request_debug("LLM_REQUEST_STREAMING", model_selected, messages_to_process, current_settings)
  p <- tryCatch(
    ai_processor$call_llm_streaming(messages_to_process, current_settings, model_selected),
    error = function(e) promises::promise_reject(e)
  )
  p <- promises::then(p, onFulfilled = function(result) {
    result$req_id <- req_id
    result
  })
  p <- promises::then(
    p,
    onFulfilled = function(res) {
      if (!isTRUE(owner_guard())) return(invisible(NULL))
      request_state <- mergen_send_message_request_state(active_request_id, res$req_id, stop_generation)
      if (!identical(request_state, "current")) {
        try(log_ai_usage(chat_id_val, user_prompt_msg$db_id, effective_user_id,
                         model_selected, res$duration, FALSE), silent = TRUE)
        if (identical(request_state, "stopped")) {
          mergen_clear_request_state(session, active_request_id, req_id, cleanup_send_message, values)
        }
        return(invisible(NULL))
      }
      if (!res$success) {
        log_warn("[AI MODULE] Streaming isteği başarısız")
        perf_tracker$track_error()
        # 401/403/AUTH hatasında gönderim anahtarı önbelleği geçersiz kılınır.
        mb_api_key_invalidate_send_cache_on_auth_error(session, res$error %||% "")
        mergen_clear_request_state(session, active_request_id, req_id,
          function() abort_send_message(message = res$error, type = "error"), values)
        return(invisible(NULL))
      }
      log_debug("[MONITORING] Streaming isteği tamamlandı")
      dbg_dump("LLM_RESPONSE_STREAMING", list(
        success = res$success, duration = res$duration,
        content_preview = substr(res$content %||% "", 1, 800)
      ))
      perf_tracker$track_request(res$duration)
      try(log_ai_usage(chat_id_val, user_prompt_msg$db_id, effective_user_id,
                       model_selected, res$duration, TRUE), silent = TRUE)
      if (is.list(res$chart_store) && length(res$chart_store) > 0) {
        if (is.null(session$userData$chart_store) || !is.list(session$userData$chart_store)) {
          session$userData$chart_store <- list()
        }
        session$userData$chart_store <- utils::modifyList(session$userData$chart_store, res$chart_store)
      }
      local_char_id <- normalize_character_id(current_settings$selected_character)
      # Kilitli referans modunda ses kimliği persona kimliğidir; sentez katmanı
      # onaylı referansı fail-closed çözer. legacy_alias modunda eski karakter
      # tts_voice etiketi korunur.
      resolved_voice <- if (identical(mergen_speech_voice_mode(), "legacy_alias")) {
        local_chars_data <- get_characters_data()
        local_char_def <- if (!is.null(local_chars_data)) Find(function(x) x$id == local_char_id, local_chars_data$styles) else NULL
        if (!is.null(local_char_def) && !is.null(local_char_def$tts_voice)) local_char_def$tts_voice else local_char_id
      } else {
        local_char_id
      }
      tts_engine_param <- NULL
      tts_voice_param <- NULL
      if (isTRUE(settings_data$enable_tts_audio)) {
        tts_engine_param <- tts_processor$synthesize_speech
        tts_voice_param <- resolved_voice
      }
      simulate_streaming_stoppable_fn(
        res$content,
        followups = NULL,
        request_id = req_id,
        tts_engine = tts_engine_param,
        tts_voice = tts_voice_param,
        on_start = NULL,
        on_complete = function(msg) {
          mergen_finish_request_owner_cleanup(session, active_request_id, req_id,
            remove_owner_cleanup, cleanup_send_message, session_guard, values)
          if (!isTRUE(owner_guard()) ||
              !identical(session$userData$llm_request_owner, req_id) ||
              isTRUE(.mergen_request_state_read(stop_generation)) || is.null(msg$id)) return(NULL)
          mergen_stream_dispatch_followups(
            session, msg$id, user_message_text, msg$content, settings_data,
            api_config, followup_tools, fallback_followup_tool,
            apply_guard = function() isTRUE(owner_guard()) &&
              identical(session$userData$llm_request_owner, req_id)
          )
        }
      )
      simulated <<- TRUE
      invisible(NULL)
    },
    onRejected = function(err) {
      if (!isTRUE(owner_guard())) return(invisible(NULL))
      log_warn("[MONITORING] Streaming isteği BAŞARISIZ")
      perf_tracker$track_error()
      duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
      try(log_ai_usage(chat_id_val, user_prompt_msg$db_id, effective_user_id,
                       model_selected, duration, FALSE), silent = TRUE)
      request_state <- mergen_send_message_request_state(active_request_id, req_id, stop_generation)
      if (identical(request_state, "current")) {
        msg <- as.character(conditionMessage(err))
        msg <- sub("^[A-Z_]+:\\s*", "", msg)
        if (!nzchar(msg)) msg <- "Beklenmeyen bir hata oluştu."
        mergen_clear_request_state(session, active_request_id, req_id,
          function() abort_send_message(message = msg, type = "error"), values)
        return(invisible(NULL))
      }
      if (identical(request_state, "stopped")) {
        mergen_clear_request_state(session, active_request_id, req_id, cleanup_send_message, values)
      }
      invisible(NULL)
    }
  )
  p <- p %...!% (function(e) {
    if (!isTRUE(owner_guard())) return(invisible(NULL))
    log_warn("[STREAM_CHAIN] Hata yakalandı: {conditionMessage(e)}")
    perf_tracker$track_error()
    request_state <- mergen_send_message_request_state(active_request_id, req_id, stop_generation)
    if (identical(request_state, "current")) {
      mergen_clear_request_state(session, active_request_id, req_id,
        function() abort_send_message(message = "Beklenmeyen bir hata oluştu.", type = "error"), values)
      return(invisible(NULL))
    }
    if (identical(request_state, "stopped")) {
      mergen_clear_request_state(session, active_request_id, req_id, cleanup_send_message, values)
    }
    invisible(NULL)
  })
  promises::finally(p, onFinally = function() {
    if (!simulated) mergen_finish_request_owner_cleanup(session, active_request_id, req_id,
      remove_owner_cleanup, cleanup_send_message, session_guard, values)
  })
  handed_off <- TRUE
  invisible(NULL)
}

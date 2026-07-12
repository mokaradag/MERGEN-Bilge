# ============================================================================== 
# Dosya Yolu: R/helpers_send_message_request_lifecycle.R
# Aciklama: send_message istek yasam dongusu, prompt snapshot ve stale request
#           korumalarini tek yerde toplar. Runtime davranisini degistirmeden
#           R/server_send_message.R uzerindeki merkezi baskiyi azaltir.
# ==============================================================================

mergen_new_send_message_request_id <- function(prefix = "req") {
  paste0(prefix, "_", format(Sys.time(), "%Y%m%d%H%M%OS3"), "_", sample(1000:9999, 1))
}

mergen_send_message_request_state <- function(active_request_id, req_id, stop_generation = NULL) {
  if (!is.function(active_request_id) || is.null(req_id) || !nzchar(as.character(req_id)[1])) {
    return("stale")
  }

  current_id <- tryCatch(active_request_id(), error = function(e) NULL)
  if (!identical(current_id, req_id)) {
    return("stale")
  }

  if (is.function(stop_generation) && isTRUE(tryCatch(stop_generation(), error = function(e) FALSE))) {
    return("stopped")
  }

  "current"
}

mergen_is_current_request <- function(active_request_id, req_id, stop_generation = NULL) {
  identical(
    mergen_send_message_request_state(active_request_id, req_id, stop_generation),
    "current"
  )
}

mergen_remove_typing_wrapper_if_safe <- function(active_request_id = NULL,
                                                 req_id = NULL,
                                                 remove_ui_fn = removeUI) {
  if (!is.function(remove_ui_fn)) {
    return(invisible(FALSE))
  }

  if (!is.null(req_id) &&
      length(req_id) > 0L &&
      nzchar(as.character(req_id)[1]) &&
      is.function(active_request_id)) {
    request_id <- as.character(req_id)[1]
    current_id <- tryCatch(active_request_id(), error = function(e) NULL)

    if (!identical(current_id, request_id)) {
      return(invisible(FALSE))
    }
  }

  try(
    remove_ui_fn(
      selector = "#typing-animation-wrapper",
      immediate = TRUE
    ),
    silent = TRUE
  )

  invisible(TRUE)
}

mergen_should_run_deferred_stream_persist <- function(active_request_id, req_id, stream_env) {
  if (is.null(stream_env) || isTRUE(stream_env$finalized)) {
    return(FALSE)
  }

  mergen_is_current_request(active_request_id, req_id)
}

mergen_build_send_message_prompt_snapshot <- function(prompt_text, session_files) {
  if (is.list(prompt_text) && !is.null(prompt_text$text)) {
    prompt_text <- prompt_text$text
  }

  user_message_text <- trimws(prompt_text %||% "")
  current_session_files <- session_files()
  uploaded_names <- if (length(current_session_files) > 0) names(current_session_files) else character(0)
  uploaded_count <- length(uploaded_names)

  list(
    user_message_text = user_message_text,
    current_session_files = current_session_files,
    uploaded_names = uploaded_names,
    uploaded_count = uploaded_count
  )
}

mergen_should_defer_chat_creation <- function(tool_family, uploaded_count, current_settings, settings_data) {
  (tool_family %in% c("none", "coding")) &&
    uploaded_count == 0 &&
    isTRUE(current_settings$enable_streaming) &&
    !isTRUE(settings_data$enable_tts_audio)
}

mergen_prepare_send_message_chat <- function(session,
                                             values,
                                             user_message_text,
                                             tool_family,
                                             effective_user_id,
                                             request_start_time,
                                             defer_chat_creation,
                                             generate_title_from_prompt) {
  # Opsiyonel performans ölçümü (yalnızca MERGEN_PERF_LOG açıkken aktiftir).
  .perf_start <- if (exists("mergen_perf_now", mode = "function", inherits = TRUE)) mergen_perf_now() else NULL
  if (!is.null(.perf_start)) on.exit(mergen_perf_log("send_message.prepare_chat", .perf_start), add = TRUE)

  if (!is.null(values$current_chat_id)) {
    return(list(ok = TRUE, pending_chat_title = NULL))
  }

  title_prompt <- if (nchar(user_message_text) > 0) user_message_text else "Dosya Analizi"
  chat_title <- generate_title_from_prompt(title_prompt, max_len = 60)

  if (isTRUE(defer_chat_creation)) {
    log_info(sprintf(
      "[CHAT PERF] Yeni sohbet kaydı ertelendi - araç=%s, gecen=%.3f sn",
      tool_family,
      as.numeric(difftime(Sys.time(), request_start_time, units = "secs"))
    ))

    return(list(ok = TRUE, pending_chat_title = chat_title))
  }

  new_chat_id <- tryCatch({
    create_new_chat_in_db(effective_user_id, initial_title = chat_title)
  }, error = function(e) {
    showToast(session, paste("Yeni sohbet oluşturulamadı:", e$message), "error")
    NULL
  })

  if (is.null(new_chat_id)) {
    return(list(ok = FALSE, pending_chat_title = NULL))
  }

  values$current_chat_id <- new_chat_id

  log_info(sprintf(
    "[CHAT PERF] Yeni sohbet kaydı oluşturuldu - gecen=%.3f sn",
    as.numeric(difftime(Sys.time(), request_start_time, units = "secs"))
  ))

  list(ok = TRUE, pending_chat_title = NULL)
}

mergen_clear_welcome_for_send_message <- function(session, values) {
  if (!isTRUE(values$show_welcome)) {
    return(invisible(FALSE))
  }

  values$show_welcome <- FALSE
  shinyjs::runjs("
    $('#welcome_fullscreen_container').addClass('hidden').empty();
    $('#chat_content_container').show();
    if(window.WelcomeVideoPlayer && window.WelcomeVideoPlayer.destroy) {
      window.WelcomeVideoPlayer.destroy();
    }
    if(window.WelcomeNeuralNetwork && window.WelcomeNeuralNetwork.destroy) {
      window.WelcomeNeuralNetwork.destroy();
    }
    if(window.WelcomeGreeting && window.WelcomeGreeting.destroy) {
      window.WelcomeGreeting.destroy();
    }
    if(window.WelcomePersonalGreeting && window.WelcomePersonalGreeting.destroy) {
      window.WelcomePersonalGreeting.destroy();
    }
  ")
  removeUI(selector = "#welcome_fullscreen_container > *", multiple = TRUE, immediate = TRUE)

  invisible(TRUE)
}

mergen_build_thinking_panel_plan <- function(tool_family,
                                             settings_data,
                                             resolved_model_id = NULL,
                                             reasoning_will_stream_override = NULL,
                                             force_simulated_panel = FALSE) {
  # Langflow gibi yerel modeli olmayan araçlar: model etiketi göstermeden,
  # her zaman simüle edilmiş (fazlı) düşünme paneli gösterilir. Akış non-streaming
  # olduğundan gerçek reasoning akmaz; panel yanıt gelene kadar canlı kalır.
  if (isTRUE(force_simulated_panel)) {
    return(list(
      panel_model_id = "",
      thinking_model_active = FALSE,
      reasoning_will_stream = FALSE,
      classic_indicator_requested = isTRUE(settings_data$enable_typing_indicator),
      panel_simulated = TRUE,
      show_thinking_wrapper = TRUE
    ))
  }

  panel_model_id <- tryCatch({
    supplied_model <- as.character(resolved_model_id %||% "")[1]

    if (!is.na(supplied_model) && nzchar(supplied_model)) {
      supplied_model
    } else {
      resolve_tool_model_for_family(
        tool_family,
        fallback_model = settings_data$model_selection
      )
    }
  }, error = function(e) {
    settings_data$model_selection
  })

  panel_model_id <- tryCatch(as.character(panel_model_id %||% "")[1], error = function(e) "")
  if (is.na(panel_model_id)) panel_model_id <- ""

  thinking_model_active <- tryCatch(
    is_thinking_model(panel_model_id),
    error = function(e) FALSE
  )

  reasoning_will_stream <- if (!is.null(reasoning_will_stream_override)) {
    isTRUE(reasoning_will_stream_override)
  } else {
    isTRUE(settings_data$enable_streaming) &&
      !identical(tool_family, "mcp_excel") &&
      !identical(tool_family, "sql_analysis") &&
      !identical(tool_family, "image") &&
      !identical(tool_family, "summarization") &&
      !isTRUE(settings_data$enable_tts_audio)
  }

  classic_indicator_requested <- isTRUE(settings_data$enable_typing_indicator)
  panel_simulated <- !isTRUE(thinking_model_active) || !isTRUE(reasoning_will_stream)
  show_thinking_wrapper <- thinking_model_active || classic_indicator_requested

  list(
    panel_model_id = panel_model_id,
    thinking_model_active = thinking_model_active,
    reasoning_will_stream = reasoning_will_stream,
    classic_indicator_requested = classic_indicator_requested,
    panel_simulated = panel_simulated,
    show_thinking_wrapper = show_thinking_wrapper
  )
}

mergen_show_send_message_thinking_wrapper <- function(session,
                                                      panel_plan,
                                                      request_id = NULL) {
  if (!isTRUE(panel_plan$show_thinking_wrapper)) {
    return(invisible(FALSE))
  }

  removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)

  insertUI(
    selector = "#chat_content_container",
    where = "beforeEnd",
    ui = div(
      id = "typing-animation-wrapper",
      class = "message-bubble",
      `data-panel-takeover` = "true",
      style = "display: flex; justify-content: center; padding: 20px;"
    ),
    immediate = TRUE
  )

  shinyjs::runjs("
    setTimeout(() => {
      window.smartScrollToBottom();
      $('#typing-animation-wrapper').show();
    }, 10);
  ")

  session$sendCustomMessage("premiumReasoningStart", list(
    model = panel_plan$panel_model_id,
    classicFallback = panel_plan$classic_indicator_requested,
    simulated = panel_plan$panel_simulated,
    requestId = request_id
  ))

  invisible(TRUE)
}
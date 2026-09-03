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
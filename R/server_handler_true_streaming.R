# ==============================================================================
# Dosya Yolu: R/server_handler_true_streaming.R
# Açıklama: TTS kapalıyken gerçek SSE akışı ile AI yanıtını istemciye
#           parça parça ileten sunucu tarafı işleyiciyi içerir.
#           TTS açık akış davranışına dokunmaz.
# ==============================================================================

handle_true_streaming_mode <- function(ctx) {
  session <- ctx$session
  output <- ctx$output
  values <- ctx$values
  settings_data <- ctx$settings_data
  stop_generation <- ctx$stop_generation
  active_request_id <- ctx$active_request_id
  perf_tracker <- ctx$perf_tracker

  baslangic_zamani <- Sys.time()
  req_id <- paste0("req_", format(Sys.time(), "%Y%m%d%H%M%OS3"), "_", sample(1000:9999, 1))

  active_request_id(req_id)
  stop_generation(FALSE)
  values$is_sending <- TRUE

  selected_char_id <- settings_data$selected_character %||% "mergen"
  chars_data <- get_characters_data()
  character_data <- if (!is.null(chars_data)) {
    Find(function(x) x$id == selected_char_id, chars_data$styles)
  } else {
    NULL
  }

  if (is.null(settings_data$user_config) && !is.null(session$userData$user_config)) {
    settings_data$user_config <- session$userData$user_config
  }

  stream_env <- new.env(parent = emptyenv())
  stream_env$req_id <- req_id
  stream_env$msg_id <- paste0("msg_", floor(as.numeric(Sys.time()) * 1000), "_", sample(1000:9999, 1))
  stream_env$timestamp <- format_timestamp()
  stream_env$stream_file <- tempfile(pattern = paste0("llm_sse_", req_id, "_"), fileext = ".jsonl")
  stream_env$stop_file <- tempfile(pattern = paste0("llm_sse_stop_", req_id, "_"), fileext = ".flag")
  stream_env$processed_line_count <- 0L
  stream_env$accumulated_text <- ""
  stream_env$result <- NULL
  stream_env$resolved <- FALSE
  stream_env$finalized <- FALSE
  stream_env$ui_started <- FALSE
  stream_env$poll_observer <- NULL

  find_message_index <- function() {
    which(vapply(values$messages, function(m) identical(m$id, stream_env$msg_id), logical(1)))
  }

  ensure_stream_ui_started <- function() {
    if (isTRUE(stream_env$ui_started)) {
      return(invisible(NULL))
    }

    stream_env$ui_started <- TRUE

    removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
    values$typing <- FALSE

    initial_msg <- list(
      id = stream_env$msg_id,
      db_id = NULL,
      content = "",
      html_content = '<div class="streaming-content" data-streaming="true"></div>',
      has_code = FALSE,
      type = "ai",
      timestamp = stream_env$timestamp,
      is_streaming = TRUE
    )

    values$messages <- append(values$messages, list(initial_msg))

    ui_to_insert <- render_message_bubble_ui(
      initial_msg,
      settings_data,
      is_last_user_message = FALSE,
      character_data = character_data,
      liked_ids = isolate(values$liked_messages),
      disliked_ids = isolate(values$disliked_messages)
    )

    insertUI(
      selector = "#chat_content_container",
      where = "beforeEnd",
      ui = ui_to_insert,
      immediate = TRUE
    )

    session$sendCustomMessage("initStreamingMessage", list(
      id = stream_env$msg_id,
      content = ""
    ))

    invisible(NULL)
  }

  cleanup_streaming_state <- function() {
    if (!is.null(stream_env$poll_observer)) {
      try(stream_env$poll_observer$destroy(), silent = TRUE)
      stream_env$poll_observer <- NULL
    }

    unlink(c(stream_env$stream_file, stream_env$stop_file), force = TRUE)

    if (identical(active_request_id(), stream_env$req_id)) {
      active_request_id(NULL)
    }
  }

  remove_placeholder_message <- function() {
    idx <- find_message_index()
    if (length(idx) > 0) {
      values$messages <- values$messages[-idx]
    }

    try(
      removeUI(
        selector = paste0("#message_wrapper_", stream_env$msg_id),
        multiple = FALSE,
        immediate = TRUE
      ),
      silent = TRUE
    )
  }

  finalize_stream_message <- function(final_text,
                                      followups = NULL,
                                      request_success = TRUE,
                                      duration_value = NULL) {
    if (isTRUE(stream_env$finalized)) {
      return(invisible(NULL))
    }

    stream_env$finalized <- TRUE

    ensure_stream_ui_started()

    idx <- find_message_index()
    if (length(idx) == 0) {
      cleanup_streaming_state()
      ctx$reset_chat_state_fn()
      return(invisible(NULL))
    }

    final_text <- enc2utf8(normalize_llm_scalar_content(final_text))

    chart_info <- build_chartlab_message(final_text, stream_env$msg_id, session)
    if (isTRUE(chart_info$found)) {
      final_html <- chart_info$html
      final_hascode <- FALSE
    } else {
      final_processed <- process_message_content(final_text, "ai")
      final_html <- final_processed$html
      final_hascode <- final_processed$has_code
    }

    values$messages[[idx]]$content <- final_text
    values$messages[[idx]]$html_content <- final_html
    values$messages[[idx]]$has_code <- final_hascode
    values$messages[[idx]]$is_streaming <- FALSE

    if (!is.null(followups) && length(followups) > 0) {
      values$messages[[idx]]$followups <- followups
    }

    session$sendCustomMessage("finalizeStreamingMessage", list(
      id = stream_env$msg_id,
      html = final_html,
      hasCode = final_hascode,
      enableActions = TRUE
    ))

    if (!is.null(followups) && length(followups) > 0) {
      push_followup_update(session, stream_env$msg_id, followups, pending = FALSE)
      try(
        shinyjs::runjs(sprintf(
          "(function(){var box=document.getElementById('followup_container_%s'); if(box){box.classList.remove('pending');}})();",
          stream_env$msg_id
        )),
        silent = TRUE
      )
    }

    if (isTRUE(chart_info$found) && length(chart_info$renderers)) {
      for (r in chart_info$renderers) {
        try(wire_chart_output(output, r$output_id, r$spec), silent = TRUE)
      }
    }

    sure_degeri <- duration_value %||% as.numeric(difftime(Sys.time(), baslangic_zamani, units = "secs"))

    try(
      log_ai_usage(
        ctx$chat_id_val,
        ctx$user_prompt_msg$db_id,
        ctx$current_user_id,
        ctx$model_selected,
        sure_degeri,
        request_success
      ),
      silent = TRUE
    )

    tryCatch({
      if (!is.null(values$current_chat_id)) {
        new_db_id <- save_message_to_db(values$current_chat_id, values$messages[[idx]])
        values$messages[[idx]]$db_id <- new_db_id
      }
      chat_store_message_in_saved_chats(values, values$messages[[idx]])
    }, error = function(e) {
      showToast(session, paste("Mesaj kaydedilemedi:", e$message), "error")
    })

    if (isTRUE(request_success)) {
      perf_tracker$track_request(sure_degeri)
    }

    cleanup_streaming_state()
    ctx$reset_chat_state_fn()
    invisible(NULL)
  }

  finalize_error_or_abort <- function(result) {
    if (isTRUE(stream_env$finalized)) {
      return(invisible(NULL))
    }

    sure_degeri <- result$duration %||% as.numeric(difftime(Sys.time(), baslangic_zamani, units = "secs"))
    kismi_metin <- enc2utf8(normalize_llm_scalar_content(stream_env$accumulated_text))

    if (nzchar(kismi_metin)) {
      finalize_stream_message(
        final_text = kismi_metin,
        followups = NULL,
        request_success = FALSE,
        duration_value = sure_degeri
      )

      if (!isTRUE(result$aborted) && nzchar(result$error %||% "")) {
        perf_tracker$track_error()
        showToast(session, result$error, "warning")
      }

      return(invisible(NULL))
    }

    remove_placeholder_message()

    if (!isTRUE(result$aborted) && nzchar(result$error %||% "")) {
      perf_tracker$track_error()
      showToast(session, result$error, "error")
    }

    cleanup_streaming_state()
    ctx$reset_chat_state_fn()
    invisible(NULL)
  }

  settings_for_sse <- ctx$current_settings
  settings_for_sse$model_selection <- ctx$model_selected

  sse_promise <- promises::future_promise({
    call_local_llm_sse_worker(
      chat_history = ctx$messages_to_process,
      current_settings = settings_for_sse,
      stream_file = stream_env$stream_file,
      stop_file = stream_env$stop_file
    )
  })

  sse_promise <- promises::then(
    sse_promise,
    onFulfilled = function(res) {
      stream_env$result <- res
      stream_env$resolved <- TRUE
      NULL
    },
    onRejected = function(err) {
      stream_env$result <- list(
        success = FALSE,
        aborted = FALSE,
        content = "",
        sources = NULL,
        duration = as.numeric(difftime(Sys.time(), baslangic_zamani, units = "secs")),
        error = conditionMessage(err)
      )
      stream_env$resolved <- TRUE
      NULL
    }
  )

  stream_env$poll_observer <- observe({
    req(!isTRUE(stream_env$finalized))
    invalidateLater(50, session)

    if (isTRUE(stop_generation()) && !file.exists(stream_env$stop_file)) {
      file.create(stream_env$stop_file)
    }

    if (file.exists(stream_env$stream_file)) {
      satirlar <- tryCatch(
        enc2utf8(readLines(stream_env$stream_file, warn = FALSE, encoding = "UTF-8")),
        error = function(e) character(0)
      )

      if (length(satirlar) > stream_env$processed_line_count) {
        yeni_satirlar <- satirlar[seq.int(stream_env$processed_line_count + 1L, length(satirlar))]
        stream_env$processed_line_count <- length(satirlar)

        for (satir in yeni_satirlar) {
          payload <- tryCatch(
            jsonlite::fromJSON(satir, simplifyVector = TRUE),
            error = function(e) NULL
          )

          if (is.null(payload)) {
            next
          }

          if (identical(payload$type %||% "", "delta")) {
            delta_text <- enc2utf8(as.character(payload$text %||% ""))
            if (!nzchar(delta_text)) {
              next
            }

            stream_env$accumulated_text <- paste0(stream_env$accumulated_text, delta_text)

            if (!isTRUE(stream_env$ui_started)) {
              ensure_stream_ui_started()
            }

            idx <- find_message_index()
            if (length(idx) > 0) {
              values$messages[[idx]]$content <- stream_env$accumulated_text
            }

            session$sendCustomMessage("streamingUpdate", list(
              id = stream_env$msg_id,
              text = stream_env$accumulated_text,
              isPartial = TRUE
            ))
          }
        }
      }
    }

    if (!isTRUE(stream_env$resolved)) {
      return(invisible(NULL))
    }

    result <- stream_env$result %||% list(
      success = FALSE,
      aborted = FALSE,
      content = "",
      sources = NULL,
      duration = as.numeric(difftime(Sys.time(), baslangic_zamani, units = "secs")),
      error = "Beklenmeyen bir hata oluştu."
    )

    if (!isTRUE(result$success)) {
      finalize_error_or_abort(result)
      return(invisible(NULL))
    }

    final_text <- enc2utf8(normalize_llm_scalar_content(result$content))
    final_text <- strip_planner_text(final_text)
    final_text <- append_clickable_sources(final_text, result$sources)

    followup_questions <- build_followup_suggestions(
      ctx$user_message_text,
      final_text,
      settings_data,
      session,
      ctx$api_config,
      ctx$followup_tools,
      ctx$fallback_followup_tool
    )

    finalize_stream_message(
      final_text = final_text,
      followups = followup_questions,
      request_success = TRUE,
      duration_value = result$duration
    )

    invisible(NULL)
  })

  invisible(NULL)
}
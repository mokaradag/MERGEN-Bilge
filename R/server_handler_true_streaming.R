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
  istek_baslangici <- ctx$request_start_time %||% baslangic_zamani
  stream_profile <- ctx$stream_profile %||% list()
  use_delta_transport <- isTRUE(stream_profile$use_delta_transport)
  poll_interval_ms <- mergen_stream_poll_interval_ms(stream_profile)

  req_id <- ctx$request_id %||% mergen_new_send_message_request_id()

  active_request_id(req_id)
  stop_generation(FALSE)
  values$is_sending <- TRUE

  selected_char_id <- normalize_character_id(settings_data$selected_character)
  chars_data <- get_characters_data()
  character_data <- if (!is.null(chars_data)) {
    Find(function(x) x$id == selected_char_id, chars_data$styles)
  } else {
    NULL
  }

  if (is.null(settings_data$user_config) && !is.null(session$userData$user_config)) {
    settings_data$user_config <- session$userData$user_config
  }

  log_info(sprintf(
    "[CHAT PERF] True streaming başladı - profil=%s, yoklama=%dms",
    stream_profile$label %||% "standard",
    poll_interval_ms
  ))

  stream_env <- new.env(parent = emptyenv())
  stream_env$req_id <- req_id
  stream_env$msg_id <- paste0("msg_", floor(as.numeric(Sys.time()) * 1000), "_", sample(1000:9999, 1))
  stream_env$timestamp <- format_timestamp()
  stream_env$stream_file <- tempfile(pattern = paste0("llm_sse_", req_id, "_"), fileext = ".jsonl")
  stream_env$stop_file <- tempfile(pattern = paste0("llm_sse_stop_", req_id, "_"), fileext = ".flag")
  stream_env$processed_line_count <- 0L
  stream_env$accumulated_text <- ""
  stream_env$accumulated_reasoning <- ""
  stream_env$reasoning_stream_started <- FALSE
  stream_env$result <- NULL
  stream_env$resolved <- FALSE
  stream_env$finalized <- FALSE
  stream_env$ui_started <- FALSE
  stream_env$poll_observer <- NULL
  stream_env$first_delta_logged <- FALSE
  stream_env$first_ui_logged <- FALSE
  stream_env$user_prompt_id <- ctx$user_prompt_msg$id %||% NULL
  stream_env$user_prompt_db_id <- ctx$user_prompt_msg$db_id %||% NULL
  stream_env$chat_persist_scheduled <- FALSE

  find_message_index <- function() {
    which(vapply(values$messages, function(m) identical(m$id, stream_env$msg_id), logical(1)))
  }

  ensure_chat_ready <- function() {
    if (is.null(values$current_chat_id) && nzchar(ctx$pending_chat_title %||% "")) {
      new_chat_id <- tryCatch({
        create_new_chat_in_db(ctx$current_user_id, initial_title = ctx$pending_chat_title)
      }, error = function(e) {
        log_warn("[CHAT PERF] Ertelenen sohbet kaydı oluşturulamadı: {e$message}")
        NULL
      })

      if (!is.null(new_chat_id)) {
        values$current_chat_id <- new_chat_id

        log_info(sprintf(
          "[CHAT PERF] Ertelenen sohbet kaydı oluşturuldu - %.3f sn",
          as.numeric(difftime(Sys.time(), istek_baslangici, units = "secs"))
        ))
      }
    }

    if (!is.null(values$current_chat_id) &&
        is.null(stream_env$user_prompt_db_id) &&
        !is.null(stream_env$user_prompt_id)) {
      user_idx <- which(vapply(values$messages, function(m) identical(m$id, stream_env$user_prompt_id), logical(1)))

      if (length(user_idx) > 0) {
        new_db_id <- tryCatch({
          save_message_safely(values$current_chat_id, values$messages[[user_idx]], ctx$current_user_id)
        }, error = function(e) {
          # Kullanıcı mesajının kalıcılaştırılması sessizce başarısız olmamalı;
          # yapılandırılmış [RUNTIME_ERROR] kaydı tanılama için bırakılır.
          if (exists("log_error_with_context", mode = "function")) {
            log_error_with_context(e, "TRUE_STREAM_SAVE_USER_MSG")
          }
          NULL
        })

        if (!is.null(new_db_id)) {
          values$messages[[user_idx]]$db_id <- new_db_id
          stream_env$user_prompt_db_id <- new_db_id
          chat_store_message_in_saved_chats(values, values$messages[[user_idx]])

          log_info(sprintf(
            "[CHAT PERF] Kullanıcı mesajı kalıcı kaydedildi - %.3f sn",
            as.numeric(difftime(Sys.time(), istek_baslangici, units = "secs"))
          ))
        }
      }
    }

    invisible(!is.null(values$current_chat_id) || !nzchar(ctx$pending_chat_title %||% ""))
  }

  schedule_chat_persist <- function() {
    if (isTRUE(stream_env$chat_persist_scheduled)) {
      return(invisible(NULL))
    }

    stream_env$chat_persist_scheduled <- TRUE

    persist_delay <- mergen_stream_persist_delay(stream_profile$label %||% "")

    later::later(function() {
      stream_env$chat_persist_scheduled <- FALSE

      if (!mergen_should_run_deferred_stream_persist(active_request_id, stream_env$req_id, stream_env)) {
        return(invisible(NULL))
      }

      try(ensure_chat_ready(), silent = TRUE)
    }, delay = persist_delay)
  }

  ensure_stream_ui_started <- function() {
    if (isTRUE(stream_env$ui_started)) {
      return(invisible(NULL))
    }

    stream_env$ui_started <- TRUE

    if (!isTRUE(stream_env$first_ui_logged)) {
      stream_env$first_ui_logged <- TRUE
      log_info(sprintf(
        "[CHAT PERF] İlk UI kabuğu gönderildi - %.3f sn",
        as.numeric(difftime(Sys.time(), istek_baslangici, units = "secs"))
      ))
    }

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

    # Premium akıl yürütme kartı aktifse sakin bir geçişle akış durumuna alınır.
    session$sendCustomMessage("premiumReasoningStreamStart", list(id = stream_env$msg_id, requestId = stream_env$req_id))
    session$sendCustomMessage("initStreamingMessage", list(id = stream_env$msg_id, content = "", requestId = stream_env$req_id))

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

    # Düşünen modeller için biriken akıl yürütme metni ayrı bir alan olarak
    # tutulur. Canlı panel istemci tarafında görünür kalır; DB'de ise ayrı
    # bir sütunda (MB_Messages.ReasoningContent) saklanır ve geçmişten
    # yüklenen mesajlarda <details> arşivi olarak geri üretilir.
    reasoning_trace <- stream_env$accumulated_reasoning %||% ""
    reasoning_trace_value <- if (nzchar(reasoning_trace)) reasoning_trace else NULL

    values$messages[[idx]]$content <- final_text
    values$messages[[idx]]$html_content <- final_html
    values$messages[[idx]]$has_code <- final_hascode
    values$messages[[idx]]$is_streaming <- FALSE
    values$messages[[idx]]$reasoning_trace <- reasoning_trace_value
    values$messages[[idx]]$reasoning_content <- reasoning_trace_value

    if (!is.null(followups) && length(followups) > 0) {
      values$messages[[idx]]$followups <- followups
    }

    session$sendCustomMessage("finalizeStreamingMessage", list(
      id = stream_env$msg_id,
      html = final_html,
      hasCode = final_hascode,
      enableActions = TRUE,
      requestId = stream_env$req_id
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

    ensure_chat_ready()

    chat_id_for_log <- values$current_chat_id %||% ctx$chat_id_val
    user_prompt_db_id_for_log <- stream_env$user_prompt_db_id %||% ctx$user_prompt_msg$db_id

    try(
      log_ai_usage(
        chat_id_for_log,
        user_prompt_db_id_for_log,
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

        if (!is.null(reasoning_trace_value) &&
            exists("update_message_reasoning_content", mode = "function", inherits = TRUE)) {
          try(update_message_reasoning_content(new_db_id, reasoning_trace_value), silent = TRUE)
        }
      }
      chat_store_message_in_saved_chats(values, values$messages[[idx]])
      try(ctx$saved_chats_data$refresh(), silent = TRUE)
    }, error = function(e) {
      showToast(session, paste("Mesaj kaydedilemedi:", e$message), "error")
    })

    if (isTRUE(request_success)) {
      perf_tracker$track_request(sure_degeri)
    }

    log_info(sprintf(
      "[CHAT PERF] Akış sonlandırıldı - basarili=%s, sure=%.3f sn",
      if (isTRUE(request_success)) "TRUE" else "FALSE",
      sure_degeri
    ))

    cleanup_streaming_state()
    ctx$reset_chat_state_fn()
    invisible(NULL)
  }

  finalize_error_or_abort <- function(result) {
    if (isTRUE(stream_env$finalized)) {
      return(invisible(NULL))
    }

    abort_plan <- mergen_stream_abort_cleanup_plan(
      accumulated_text = stream_env$accumulated_text,
      result = result,
      normalize_fn = normalize_llm_scalar_content
    )

    sure_degeri <- abort_plan$duration %||%
      as.numeric(difftime(Sys.time(), baslangic_zamani, units = "secs"))

    if (identical(abort_plan$action, "finalize_partial")) {
      finalize_stream_message(
        final_text = abort_plan$final_text,
        followups = NULL,
        request_success = abort_plan$request_success,
        duration_value = sure_degeri
      )

      if (isTRUE(abort_plan$track_error)) {
        perf_tracker$track_error()
        showToast(session, abort_plan$error, abort_plan$toast_type)
      }

      return(invisible(NULL))
    }

    remove_placeholder_message()

    if (isTRUE(abort_plan$track_error)) {
      perf_tracker$track_error()
      showToast(session, abort_plan$error, abort_plan$toast_type)
    }

    cleanup_streaming_state()
    ctx$reset_chat_state_fn()
    invisible(NULL)
  }

  chat_history_for_sse <- ctx$messages_to_process
  stream_file_for_sse <- stream_env$stream_file
  stop_file_for_sse <- stream_env$stop_file

  settings_for_sse <- ctx$current_settings
  settings_for_sse$model_selection <- ctx$model_selected
  settings_for_sse$shiny_session <- NULL
  settings_for_sse$request_start_unix <- as.numeric(istek_baslangici)

  future_submit_time <- Sys.time()
  settings_for_sse$future_submit_unix <- as.numeric(future_submit_time)

  log_info(sprintf(
    "[CHAT PERF] future_promise gönderiliyor - %.3f sn",
    as.numeric(difftime(future_submit_time, istek_baslangici, units = "secs"))
  ))

  sse_promise <- tracked_future_promise(
    task_fn = function() {
      call_local_llm_sse_worker(
        chat_history = chat_history_for_sse,
        current_settings = settings_for_sse,
        stream_file = stream_file_for_sse,
        stop_file = stop_file_for_sse
      )
    },
    task_type = "llm_true_streaming",
    session_token = session$token,
    meta = list(
      model = ctx$model_selected
    ),
    # Worker-export sözleşmesi (reasoning delta / stop-file / model request
    # override yardımcıları işçi tarafında görünür kalmalı) tek yerde toplanır.
    # Liste içeriği birebir korunur; yalnızca isteğe-özel 4 nesne argümandır.
    globals = mergen_true_streaming_worker_globals(
      chat_history_for_sse = chat_history_for_sse,
      settings_for_sse = settings_for_sse,
      stream_file_for_sse = stream_file_for_sse,
      stop_file_for_sse = stop_file_for_sse
    )
  )

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
    invalidateLater(poll_interval_ms, session)

    if (isTRUE(stop_generation()) && !file.exists(stream_env$stop_file)) {
      file.create(stream_env$stop_file)
    }

    if (file.exists(stream_env$stream_file)) {
      # Akış dosyası tek baytlı base64 JSON satırları içerir. Yine de Windows VM
      # ortamında readLines bazen geçersiz UTF-8 baytları gördüğünde hata atabilir;
      # bu yüzden tryCatch içine alıyoruz ve gerekirse byte modunda fallback yapıyoruz.
      satirlar <- tryCatch(
        suppressWarnings(readLines(stream_env$stream_file, warn = FALSE, encoding = "UTF-8")),
        error = function(e) {
          tryCatch(
            suppressWarnings(readLines(stream_env$stream_file, warn = FALSE)),
            error = function(e2) character(0)
          )
        }
      )

      if (length(satirlar) > stream_env$processed_line_count) {
        yeni_satirlar <- satirlar[seq.int(stream_env$processed_line_count + 1L, length(satirlar))]
        stream_env$processed_line_count <- length(satirlar)

        # Yeni JSONL satırları saf sınıflandırma yardımcısıyla delta /
        # akıl yürütme / debug gruplarına ayrılır; bozuk satırlar yardımcı
        # içinde sessizce atlanır.
        batches <- mergen_stream_classify_poll_lines(
          yeni_satirlar,
          decode_fn = decode_stream_delta_payload
        )

        for (debug_text in batches$debug_lines) {
          log_info(debug_text)
        }

        if (batches$delta_count > 0) {
          stream_env$accumulated_text <- paste0(stream_env$accumulated_text, batches$delta_text)

          if (!isTRUE(stream_env$first_delta_logged)) {
            stream_env$first_delta_logged <- TRUE
            ilk_delta_ms <- as.numeric(difftime(Sys.time(), istek_baslangici, units = "secs")) * 1000
            log_info(sprintf(
              "[CHAT PERF] İlk delta gözlendi - %.3f sn",
              ilk_delta_ms / 1000
            ))
            # Grep-dostu, sır-redakteli, varsayılan KAPALI perf işareti
            # (MERGEN_PERF_LOG=1): modelin ilk-token gecikmesini izler.
            mergen_perf_log("stream.first_delta", fields = list(
              request_id = stream_env$req_id,
              elapsed_ms = round(ilk_delta_ms, 1)
            ))
          }
        }

        # Düşünce akışı parçalarını ayrı kanalla istemciye ilet.
        if (batches$reasoning_count > 0) {
          stream_env$accumulated_reasoning <- paste0(stream_env$accumulated_reasoning, batches$reasoning_text)

          session$sendCustomMessage("streamingReasoningDelta", list(
            id = stream_env$msg_id,
            delta = batches$reasoning_text,
            started = !isTRUE(stream_env$reasoning_stream_started),
            requestId = stream_env$req_id
          ))
          stream_env$reasoning_stream_started <- TRUE
        }

        if (batches$delta_count > 0) {
          if (!isTRUE(stream_env$ui_started)) {
            ensure_stream_ui_started()
          }

          idx <- find_message_index()
          if (length(idx) > 0) {
            values$messages[[idx]]$content <- stream_env$accumulated_text
          }

          if (isTRUE(use_delta_transport)) {
            session$sendCustomMessage("streamingDelta", list(
              id = stream_env$msg_id,
              delta = batches$delta_text,
              requestId = stream_env$req_id
            ))
          } else {
            session$sendCustomMessage("streamingUpdate", list(
              id = stream_env$msg_id,
              text = stream_env$accumulated_text,
              isPartial = TRUE,
              requestId = stream_env$req_id
            ))
          }

          if (is.null(stream_env$user_prompt_db_id) || nzchar(ctx$pending_chat_title %||% "")) {
            schedule_chat_persist()
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

    # Worker dönüşünde reasoning alanı varsa ama polling sırasında stream_env'e
    # düşmemişse saf geri kazanım planıyla geri kazan. Bu özellikle reasoning'in
    # final chunk'ta geldiği veya <think> ayrıştırmasının worker tarafında
    # tamamlandığı uçlarda DB'de ReasoningContent'in NULL kalmasını engeller.
    recovery_plan <- mergen_stream_reasoning_recovery_plan(
      accumulated_reasoning = stream_env$accumulated_reasoning,
      result_reasoning = result$reasoning,
      stream_started = stream_env$reasoning_stream_started,
      normalize_fn = normalize_llm_scalar_content
    )

    if (!identical(recovery_plan$action, "none")) {
      stream_env$accumulated_reasoning <- recovery_plan$accumulated

      session$sendCustomMessage("streamingReasoningDelta", list(
        id = stream_env$msg_id,
        delta = recovery_plan$delta,
        started = recovery_plan$started_payload,
        requestId = stream_env$req_id
      ))

      if (isTRUE(recovery_plan$mark_stream_started)) {
        stream_env$reasoning_stream_started <- TRUE
      }
    }

    base_final_text <- enc2utf8(normalize_llm_scalar_content(result$content))
    base_final_text <- strip_planner_text(base_final_text)
    base_final_text <- append_clickable_sources(base_final_text, result$sources)

    final_text <- base_final_text
    if (nzchar(ctx$final_text_suffix %||% "")) {
      final_text <- paste0(final_text, ctx$final_text_suffix)
    }

    # Yanıtı HEMEN sonlandır: markdown render, aksiyon butonları ve DB kalıcılığı
    # takip (followup) önerisi üretimini BEKLEMEZ. build_followup_suggestions()
    # AI takip üreticisinde senkron bir LLM çağrısı (call_local_llm) yapabilir;
    # önceki sıralamada bu çağrı, akış görünür biçimde bittikten SONRA yanıt
    # baloncuğunu saniyelerce "akıyor" durumunda (aksiyon butonları gizli, kod
    # blokları ham) tutuyordu. Öneriler artık finalize flush'ından SONRA,
    # bloklamayan bir later() döngüsünde üretilip push edilir. Sözleşme: tarayıcı
    # followup_container'ı talep üzerine oluşturur (updateFollowupSuggestions),
    # bu yüzden baloncuk önerilerden önce sonlandırılabilir.
    finalize_stream_message(
      final_text = final_text,
      followups = NULL,
      request_success = TRUE,
      duration_value = result$duration
    )

    followup_msg_id <- stream_env$msg_id
    later::later(function() {
      followup_perf_start <- mergen_perf_now()
      followup_questions <- tryCatch(
        build_followup_suggestions(
          ctx$user_message_text, base_final_text, settings_data, session,
          ctx$api_config, ctx$followup_tools, ctx$fallback_followup_tool
        ),
        error = function(e) NULL
      )

      # Varsayılan KAPALI perf işareti: artık kritik yolun DIŞINDA olan takip
      # üretim süresini (saniyeler olabilir) ölçer.
      mergen_perf_log("stream.followups", start = followup_perf_start,
                      fields = list(count = length(followup_questions %||% character(0))))

      if (!is.null(followup_questions) && length(followup_questions) > 0) {
        try(
          push_followup_update(session, followup_msg_id, followup_questions, pending = FALSE),
          silent = TRUE
        )
      }
    }, delay = 0)

    invisible(NULL)
  })

  invisible(NULL)
}
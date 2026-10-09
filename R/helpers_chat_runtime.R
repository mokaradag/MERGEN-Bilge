
chat_reset_state <- function(session, values) {
  freezeReactiveValue(session$input, "send_stop_btn")
  values$is_sending <- FALSE
  values$typing <- FALSE

  shinyjs::runjs("if (window.PremiumReasoning && window.PremiumReasoning.isActive && window.PremiumReasoning.isActive()) { window.PremiumReasoning.onResetChatState(); }")

  removeUI(selector = "#typing-animation-wrapper")

  shinyjs::runjs("$('#send_stop_btn i').attr('class', 'fa-solid fa-paper-plane');")
  shinyjs::runjs("$('#send_stop_btn').removeClass('stop-mode');")
  shinyjs::runjs("$('#send_stop_btn').attr('title', 'Gönder (Enter)').attr('aria-label', 'Mesajı gönder');")
  shinyjs::runjs("const chatInput = $('.chat-input')[0]; if (chatInput) { window.adjustTextareaHeight(chatInput); }")
}

chat_generate_title_from_prompt <- function(prompt, max_len = 60) {
  if (is.null(prompt) || !nzchar(trimws(prompt))) return("Yeni Söyleşi")
  cleaned <- gsub("\\s+", " ", trimws(prompt))
  cleaned <- gsub("^[[:punct:]]+|[[:punct:]]+$", "", cleaned)
  if (nchar(cleaned) <= max_len) return(cleaned)
  cut_at <- regexpr("\\s", substr(cleaned, max_len - 10, max_len + 10))
  if (cut_at[1] > 0) {
    pos <- (max_len - 10) + cut_at[1] - 1
    title <- substr(cleaned, 1, pos)
  } else {
    title <- substr(cleaned, 1, max_len - 3)
  }
  title <- trimws(title)
  paste0(title, "...")
}

chat_add_message <- function(session, values, settings_data, output,
                             content, type = "user", html = NULL,
                             current_user_id,
                             followups = NULL, audio_src = NULL,
                             audio_voice = NULL,
                             persist_to_db = TRUE,
                             add_to_saved_chats = TRUE,
                             include_in_context = TRUE,
                             reasoning_content = NULL) {
  if (isTRUE(values$show_welcome)) {
    removeUI(selector = "#chat_content_container > *", multiple = TRUE, immediate = TRUE)
    values$show_welcome <- FALSE
  }

  timestamp <- format_timestamp()
  message_id <- paste0("msg_", floor(as.numeric(Sys.time()) * 1000), "_", sample(1000:9999, 1))

  chart_info <- NULL
  if (identical(type, "ai") && is.character(content) && length(content) > 0 &&
      grepl("```chartlab", content[1], fixed = TRUE)) {
    chart_info <- build_chartlab_message(content[1], message_id, session)
  }

  processed <- if (!is.null(html)) {
    list(html = html, has_code = grepl("code-container", html))
  } else if (!is.null(chart_info) && isTRUE(chart_info$found)) {
    list(html = chart_info$html, has_code = FALSE)
  } else {
    process_message_content(content, type)
  }

  new_message <- list(
    id = message_id, db_id = NULL, content = content,
    html_content = processed$html, has_code = processed$has_code,
    type = type, timestamp = timestamp,
    audio_src = audio_src, audio_voice = audio_voice,
    include_in_context = !isFALSE(include_in_context)
  )
  
  if (!is.null(followups) && length(followups) > 0) {
    new_message$followups <- followups
  }

  if (!is.null(reasoning_content)) {
    reasoning_txt <- tryCatch(as.character(reasoning_content)[1], error = function(e) "")
    if (is.character(reasoning_txt) && length(reasoning_txt) == 1 &&
        !is.na(reasoning_txt) && nzchar(reasoning_txt)) {
      new_message$reasoning_content <- reasoning_txt
      new_message$reasoning_trace <- reasoning_txt
    }
  }

  if (isTRUE(persist_to_db) && !is.null(values$current_chat_id)) {
    tryCatch({
      msg_to_persist <- new_message
      if (is.character(msg_to_persist$content) && nchar(msg_to_persist$content) > 19900) {
        msg_to_persist$content <- paste0(
          substr(msg_to_persist$content, 1, 19500),
          "\n\n[Not: Mesaj çok uzun olduğu için yalnızca veritabanına kaydedilen kısım kısaltıldı. Ekrandaki içerik tamdır.]"
        )
      }
		new_db_id <- save_message_safely(values$current_chat_id, msg_to_persist, current_user_id)
		new_message$db_id <- new_db_id
		new_message$id <- as.character(new_db_id)

		if (!is.null(new_message$reasoning_content) &&
			exists("update_message_reasoning_content", mode = "function", inherits = TRUE)) {
		  try(update_message_reasoning_content(new_db_id, new_message$reasoning_content), silent = TRUE)
		}
    }, error = function(e) {
      showToast(session, paste("Mesaj kaydedilemedi:", e$message), "error")
    })
  }

  values$messages <- append(values$messages, list(new_message))
  
  if (isTRUE(add_to_saved_chats) && !is.null(values$current_chat_id)) {
    chat_store_message_in_saved_chats(values, new_message)
  }

  is_last_user_msg <- (new_message$type == "user" && length(values$messages) > 0 &&
                         tail(values$messages, 1)[[1]]$id == new_message$id)

  selected_char_id <- normalize_character_id(isolate(settings_data$selected_character))
  character_data <- get_character_record(selected_char_id)

  settings_data$user_config <- session$userData$user_config

  ui_to_insert <- render_message_bubble_ui(
    new_message, settings_data,
    is_last_user_message = is_last_user_msg,
    character_data = character_data,
    liked_ids = values$liked_messages,
    disliked_ids = values$disliked_messages
  )

  insertUI(
    selector = "#chat_content_container", where = "beforeEnd",
    ui = ui_to_insert, immediate = TRUE
  )

  if (identical(type, "ai") || identical(type, "assistant")) {
    push_followup_update(session, new_message$id, followups, pending = FALSE)
  }
  
  if (!is.null(chart_info) && isTRUE(chart_info$found) && length(chart_info$renderers)) {
    for (r in chart_info$renderers) {
      local({
        local_r <- r
        session$onFlushed(function() {
          try(wire_chart_output(output, local_r$output_id, local_r$spec), silent = TRUE)
        }, once = TRUE)
      })
    }
  }

  wrapper_id <- paste0("message_wrapper_", new_message$id)
  if (isTRUE(new_message$has_code)) {
    shinyjs::runjs(sprintf("
      setTimeout(() => {
        if (window.initializeCodeMirrorInElement) {
          window.initializeCodeMirrorInElement('%s');
        }
        window.smartScrollToBottom();
      }, 100);
    ", wrapper_id))
  } else {
    shinyjs::runjs("setTimeout(() => { window.smartScrollToBottom(); }, 50);")
  }

  return(new_message)
}

chat_store_message_in_saved_chats <- function(values, message) {
  if (is.null(values$current_chat_id)) return(invisible(NULL))

  chat_key <- as.character(values$current_chat_id)
  saved_chats_copy <- values$saved_chats
  if (is.null(saved_chats_copy) || !is.list(saved_chats_copy)) {
    saved_chats_copy <- list()
  }

  entry <- saved_chats_copy[[chat_key]]
  if (is.null(entry)) {
    entry <- list(
      title = NULL,
      timestamp = Sys.time(),
      messages = list(),
      message_count = 0L
    )
  }

  existing_messages <- entry$messages
  if (is.null(existing_messages) || !is.list(existing_messages)) {
    existing_messages <- list()
  }

  entry$messages <- append(existing_messages, list(message))
  entry$message_count <- length(entry$messages)
  entry$last_message_timestamp <- Sys.time()

  if (is.null(entry$timestamp) || is.na(entry$timestamp)) {
    entry$timestamp <- Sys.time()
  }
  if (is.null(entry$title) || is.na(entry$title)) {
    entry$title <- "Yeni Söyleşi"
  }

  saved_chats_copy[[chat_key]] <- entry
  values$saved_chats <- saved_chats_copy

  invisible(NULL)
}

chat_simulate_streaming <- function(full_response, session, values, settings_data, output, stop_generation,
                                   followups = NULL, on_complete = NULL, on_start = NULL,
                                   tts_engine = NULL, tts_voice = NULL, request_id = NULL) {
  pk_request_id <- tryCatch({ rid <- as.character(request_id %||% "")[1]; if (is.na(rid) || !nzchar(rid)) rid <- as.character(pk_provenance_current_request_id(session) %||% "")[1]; if (is.na(rid) || !nzchar(rid)) NULL else rid }, error = function(e) NULL)  # -- 1. SETUP PREPARATION --
  .cr_kimlik_oku <- function() { if (!exists("mergen_pk_chat_identity", mode = "function", inherits = TRUE)) return(NULL); v <- try(mergen_pk_chat_identity(session, values), silent = TRUE); if (inherits(v, "try-error")) NULL else v }
  pk_chat_kimlik <- .cr_kimlik_oku()
  .cr_ayni_sohbet <- function() { if (is.null(pk_chat_kimlik)) return(TRUE); s <- .cr_kimlik_oku(); is.null(s) || identical(s, pk_chat_kimlik) }
  .cr_result_current <- mergen_request_owner_guard(session)
  msg_id <- paste0("msg_", floor(as.numeric(Sys.time()) * 1000), "_", sample(1000:9999, 1))
  timestamp <- format_timestamp()
  
  selected_char_id <- normalize_character_id(isolate(settings_data$selected_character))
  character_data <- get_character_record(selected_char_id)

  .cr_blok_aktif <- FALSE
  start_streaming_execution <- function(audio_result = NULL) {
    if (!.cr_result_current()) {
      if (is.function(on_complete)) try(on_complete(NULL), silent = TRUE)
      return(invisible(NULL))
    }
    if (!.cr_ayni_sohbet()) {
      if (!exists("pk_stale_callback_may_reset", mode = "function", inherits = TRUE) ||
          isTRUE(pk_stale_callback_may_reset(session, pk_request_id))) chat_reset_state(session, values)
      if (is.function(on_complete)) try(on_complete(NULL), silent = TRUE)
      return(invisible(NULL))
    }
    if (stop_generation()) {
        if (is.function(on_complete)) try(on_complete(NULL), silent = TRUE)
        removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
        values$typing <- FALSE
        chat_reset_state(session, values)
        return()
    }

    removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
    values$typing <- FALSE

    initial_msg <- list(
      id = msg_id,
      db_id = NULL,
      content = "",
      html_content = '<div class="streaming-content" data-streaming="true"></div>',
      has_code = FALSE,
      type = "ai",
      timestamp = timestamp,
      is_streaming = TRUE
    )
    
    if (!is.null(followups) && length(followups) > 0) {
      initial_msg$followups <- followups
    }
    values$messages <- append(values$messages, list(initial_msg))

    settings_data$user_config <- session$userData$user_config

    ui_to_insert <- render_message_bubble_ui(
      initial_msg, settings_data,
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
      id = msg_id,
      content = ""
    ))

    push_followup_update(session, msg_id, followups, pending = TRUE)
    
    if (!is.null(audio_result) && isTRUE(audio_result$success) && !is.null(audio_result$audio_src)) {
        session$sendCustomMessage("playAudioMessage", list(
            id = msg_id,
            src = audio_result$audio_src,
            chunkIndex = 0
        ))
        
        idx <- length(values$messages)
        values$messages[[idx]]$audio_src <- audio_result$audio_src
        values$messages[[idx]]$audio_voice <- audio_result$voice
    } else {
        if (is.function(on_start) && is.null(tts_engine)) {
            try(on_start(msg_id), silent = TRUE)
        }
    }
    
    words <- unlist(strsplit(full_response, "(?<=\\s)", perl = TRUE))
    if (length(words) == 0) words <- c(full_response)

    total_words <- length(words)
    chunk_size <- max(1, ceiling(total_words / 100))

    streaming_state <- shiny::reactiveValues(
      accumulated = "",
      current_index = 1,
      msg_id = msg_id
    )

    stream_observer <- shiny::observe({
      isolate({
        if (!.cr_result_current() || !.cr_ayni_sohbet()) {
          chat_discard_stream_placeholder(session, values, msg_id)
          if (is.function(on_complete)) try(on_complete(NULL), silent = TRUE)
          stream_observer$destroy()
          return(invisible(NULL))
        }
        if (stop_generation() || streaming_state$current_index > total_words) {
          completed_msg <- NULL
		  msg_index <- which(vapply(values$messages, function(m) identical(m$id, streaming_state$msg_id), logical(1)))
          if (isTRUE(stop_generation()) && !nzchar(streaming_state$accumulated)) {
            chat_discard_stream_placeholder(session, values, streaming_state$msg_id)
            msg_index <- integer()
          }
          if (length(msg_index) > 0) {
            final_text <- if (isTRUE(stop_generation()) || nzchar(streaming_state$accumulated)) streaming_state$accumulated else full_response
            semantic <- list(display = final_text, tts = if (stop_generation()) final_text else tts_metni,
              validated = !identical(blok$validated, FALSE))


            chart_info <- build_chartlab_message(final_text, streaming_state$msg_id, session)
            if (isTRUE(chart_info$found)) {
              final_html <- chart_info$html
              final_hascode <- FALSE
            } else {
              final_processed <- process_message_content(final_text, "ai")
              final_html <- final_processed$html
              final_hascode <- final_processed$has_code
            }

            values$messages[[msg_index]]$followup_content <- semantic$tts
            values$messages[[msg_index]]$followup_validated <- semantic$validated
            values$messages[[msg_index]]$content <- final_text
            values$messages[[msg_index]]$html_content <- final_html
            values$messages[[msg_index]]$has_code <- final_hascode
            values$messages[[msg_index]]$is_streaming <- FALSE
            if (!is.null(followups) && length(followups) > 0) {
              values$messages[[msg_index]]$followups <- followups
            }

            session$sendCustomMessage("finalizeStreamingMessage", list(
              id = streaming_state$msg_id,
              html = final_html,
              hasCode = final_hascode,
              enableActions = TRUE
            ))
            
            push_followup_update(session, streaming_state$msg_id, followups, pending = FALSE)
            try(shinyjs::runjs(sprintf("(function(){var box=document.getElementById('followup_container_%s'); if(box){box.classList.remove('pending');}})();", streaming_state$msg_id)), silent = TRUE)

            if (isTRUE(chart_info$found) && length(chart_info$renderers)) {
              for (r in chart_info$renderers) {
                try(wire_chart_output(output, r$output_id, r$spec), silent = TRUE)
              }
            }

            tryCatch({
              if (!is.null(values$current_chat_id)) {
                new_db_id <- save_message_to_db(values$current_chat_id, values$messages[[msg_index]])
                values$messages[[msg_index]]$db_id <- new_db_id
              }
              chat_store_message_in_saved_chats(values, values$messages[[msg_index]])
              completed_msg <- values$messages[[msg_index]]
            }, error = function(e) print(paste("Error saving message:", e$message)))
          }

          if (is.function(on_complete)) try(on_complete(completed_msg), silent = TRUE)

          chat_reset_state(session, values)
          stream_observer$destroy()
          return()
        }

        chunk_end <- min(streaming_state$current_index + chunk_size - 1, total_words)
        chunk_words <- words[streaming_state$current_index:chunk_end]
        chunk_text <- paste(chunk_words, collapse = "")

        streaming_state$accumulated <- paste0(streaming_state$accumulated, chunk_text)

		msg_index <- which(vapply(values$messages, function(m) m$id %||% "", character(1)) == streaming_state$msg_id)
        if (length(msg_index) > 0) {
          values$messages[[msg_index]]$content <- streaming_state$accumulated
        }

        session$sendCustomMessage("streamingUpdate", list(
          id = streaming_state$msg_id,
          text = streaming_state$accumulated,
          isPartial = TRUE
        ))

        streaming_state$current_index <- chunk_end + 1
      })

      shiny::invalidateLater(25)
    })
  }

  .cr_blok_aktif <- isTRUE(tryCatch(
    exists("pk_provenance_blocks_streaming", mode = "function", inherits = TRUE) &&
      isTRUE(pk_provenance_blocks_streaming(session, request_id = pk_request_id)),
    error = function(e) TRUE
  ))
  .cr_yedek_metin <- if (exists("pk_block_mode_fallback_text", mode = "function", inherits = TRUE)) pk_block_mode_fallback_text(.cr_blok_aktif, full_response) else if (.cr_blok_aktif && exists("PK_PROVENANCE_BLOCK_REFUSAL_TR", inherits = TRUE)) get("PK_PROVENANCE_BLOCK_REFUSAL_TR", inherits = TRUE) else full_response
  yedek_blok <- list(display = .cr_yedek_metin, tts = .cr_yedek_metin, validated = !.cr_blok_aktif)
  blok <- if (exists("mergen_pk_block_mode_texts", mode = "function", inherits = TRUE)) {
    tryCatch(
      if (exists("mergen_pk_stream_validated_text", mode = "function"))
        mergen_pk_stream_validated_text(full_response, session, pk_request_id, .cr_blok_aktif) else
        mergen_pk_block_mode_texts(full_response, session, request_id = pk_request_id),
      error = function(e) {
        cat(sprintf("[PK] block kipi metinleri hazırlanamadı: %s\n",
                    conditionMessage(e)))
        yedek_blok
      }
    )
  } else yedek_blok
  if (!is.list(blok)) blok <- yedek_blok

  .cr_metin <- function(x, yedek) {
    v <- suppressWarnings(as.character(x)[1])
    if (length(v) != 1L || is.na(v)) yedek else v
  }
  full_response <- .cr_metin(blok$display, yedek_blok$display)
  tts_metni <- .cr_metin(blok$tts, yedek_blok$tts)

  if (!is.null(tts_engine) && is.function(tts_engine) && nzchar(tts_metni)) {
      cat(sprintf("[TTS-STREAM] Seslendirme başlatılıyor (ses: %s, metin: %d karakter)\n",
                  tts_voice %||% "varsayılan", nchar(tts_metni)))
      promises::then(
          tryCatch(tts_engine(tts_metni, tts_voice), error = function(e) promises::promise_reject(e)),
          onFulfilled = function(result) {
              if (isTRUE(result$success)) {
                cat(sprintf("[TTS-STREAM] Seslendirme başarılı (süre: %.2fs)\n", result$duration %||% 0))
              } else {
                cat(sprintf("[TTS-STREAM] Seslendirme başarısız: %s\n", result$error %||% "bilinmeyen hata"))
              }
              start_streaming_execution(result)
          },
          onRejected = function(err) {
              cat(sprintf("[TTS-STREAM] Promise hatası: %s\n", conditionMessage(err)))
              start_streaming_execution(NULL)
          }
      )
  } else {
      start_streaming_execution(NULL)
  }
}

chat_start_new_chat <- function(session, values, saved_chats_data, session_files, filePreview, current_user_id, file_manager_data = NULL) {
  removeUI(selector = "#chat_content_container > *", multiple = TRUE)
  
  if (!is.null(file_manager_data) && is.function(file_manager_data$reset_attachment_state)) {
    file_manager_data$reset_attachment_state()
  }

  values$messages <- list()
  values$current_chat_id <- NULL
  values$show_welcome <- TRUE
  session_files(list())

  for (fn in c("pk_entity_context_clear", "mergen_pk_bump_chat_epoch",
               "mergen_pk_abandon_active_requests")) {
    if (exists(fn, mode = "function", inherits = TRUE)) {
      try(get(fn, mode = "function")(session), silent = TRUE)
    }
  }

  session_user_data_reset_lists(
    session,
    c("current_session_files", "file_summaries", "mcp_registry_snapshot")
  )

  if (exists("file_store", where = .GlobalEnv)) {
    file_store <<- list()
  }

  if (!is.null(values$temp_files)) {
    for (tf in values$temp_files) {
      try(unlink(tf), silent = TRUE)
    }
    values$temp_files <- list()
  }

  shinyjs::runjs("$('#scroll_to_bottom_container').removeClass('show');")

  showToast(session, "Yeni söyleşi başlatıldı.", "success")
}

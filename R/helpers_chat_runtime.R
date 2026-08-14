# R/helpers_chat_runtime.R
# Chat runtime helpers extracted from server.R (no logic changes)

chat_reset_state <- function(session, values) {
  freezeReactiveValue(session$input, "send_stop_btn")
  values$is_sending <- FALSE
  values$typing <- FALSE

  # Premium akıl yürütme kartı aktifse kendi iç durumuna göre temizlensin
  # (durduruldu / hata / tamamlandı). removeUI çağrısından önce tetiklenir ki
  # kart "kesildi" görünümünü kısaca gösterebilsin.
  shinyjs::runjs("if (window.PremiumReasoning && window.PremiumReasoning.isActive && window.PremiumReasoning.isActive()) { window.PremiumReasoning.onResetChatState(); }")

  removeUI(selector = "#typing-animation-wrapper")

  shinyjs::runjs("$('#send_stop_btn i').attr('class', 'fa-solid fa-paper-plane');")
  shinyjs::runjs("$('#send_stop_btn').removeClass('stop-mode');")
  # Erişilebilirlik: gönder moduna dönüşte ekran okuyucu etiketi de sıfırlanır.
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

push_followup_update <- function(session, message_id, followups, pending = FALSE) {
  if (is.null(session) || is.null(message_id)) {
    return(invisible(NULL))
  }

  cleaned <- followups %||% character(0)
  cleaned <- trimws(as.character(cleaned))
  cleaned <- cleaned[nzchar(cleaned)]
  if (!length(cleaned)) {
    return(invisible(NULL))
  }

	payload <- list(
	  id = message_id,
	  followups = unname(cleaned),
	  pending = isTRUE(pending)
	)

	cat(sprintf(
	  "[FOLLOWUPS][PUSH] message_id=%s count=%d pending=%s\n",
	  as.character(message_id),
	  length(cleaned),
	  isTRUE(pending)
	))

	try(session$sendCustomMessage("updateFollowupSuggestions", payload), silent = TRUE)
	invisible(NULL)
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

  # Akıl yürütme (reasoning) metnini mesaja iliştir; böylece veritabanındaki
  # MB_Messages.ReasoningContent sütununa düşünen modellerin dahili çıktısı
  # da yazılabilir (save_message_to_db zaten bu alanı okuyor).
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

  # Oturum-yerel user_config'i settings'e ekle (çoklu kullanıcı güvenliği)
  if (is.null(settings_data$user_config) && !is.null(session$userData$user_config)) {
    settings_data$user_config <- session$userData$user_config
  }

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
  
  # [FIX START] Closure bug fix for multiple charts
  if (!is.null(chart_info) && isTRUE(chart_info$found) && length(chart_info$renderers)) {
    for (r in chart_info$renderers) {
      # Wrap in local to ensure 'r' is captured correctly for each iteration
      local({
        local_r <- r
        session$onFlushed(function() {
          try(wire_chart_output(output, local_r$output_id, local_r$spec), silent = TRUE)
        }, once = TRUE)
      })
    }
  }
  # [FIX END]

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
  # Bayat kayit korumasi: kimlik GOZLEMCI KURULMADAN ONCE yakalanir (sonlandirici gecikmeli calisir; o anda okunan kimlik DAHA YENI bir isteğe ait olabilir).
  pk_request_id <- tryCatch({ rid <- as.character(request_id %||% "")[1]; if (is.na(rid) || !nzchar(rid)) rid <- as.character(pk_provenance_current_request_id(session) %||% "")[1]; if (is.na(rid) || !nzchar(rid)) NULL else rid }, error = function(e) NULL)  # -- 1. SETUP PREPARATION --
  msg_id <- paste0("msg_", floor(as.numeric(Sys.time()) * 1000), "_", sample(1000:9999, 1))
  timestamp <- format_timestamp()
  
  # Character and settings resolution
  selected_char_id <- normalize_character_id(isolate(settings_data$selected_character))
  character_data <- get_character_record(selected_char_id)

  # -- 2. CORE EXECUTION CLOSURE (UI Update & Streaming) --
  # This function runs ONLY when we are ready to show text (after audio is ready)
  start_streaming_execution <- function(audio_result = NULL) {
    if (stop_generation()) {
        removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
        values$typing <- FALSE
        chat_reset_state(session, values)
        return()
    }

    # SENKRONİZASYON NOKTASI: Düşünüyor animasyonunu tam burada kaldırıyoruz
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

    # Oturum-yerel user_config'i settings'e ekle (çoklu kullanıcı güvenliği)
    if (is.null(settings_data$user_config) && !is.null(session$userData$user_config)) {
      settings_data$user_config <- session$userData$user_config
    }

    # Render UI
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
    
    # -- 3. AUDIO TRIGGER (Concurrent with Text) --
    if (!is.null(audio_result) && isTRUE(audio_result$success) && !is.null(audio_result$audio_src)) {
        # Play audio immediately as text starts
        session$sendCustomMessage("playAudioMessage", list(
            id = msg_id,
            src = audio_result$audio_src,
            chunkIndex = 0
        ))
        
        # Attach to message for history
        idx <- length(values$messages)
        values$messages[[idx]]$audio_src <- audio_result$audio_src
        values$messages[[idx]]$audio_voice <- audio_result$voice
    } else {
        # Fallback for legacy on_start if no TTS engine passed
        if (is.function(on_start) && is.null(tts_engine)) {
            try(on_start(msg_id), silent = TRUE)
        }
    }
    
    # -- 4. TEXT STREAMING LOOP --
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
        if (stop_generation() || streaming_state$current_index > total_words) {
          # ... Finalization Logic ...
		  # vapply kullanarak tip güvenliği sağla ve performansı artır
		  msg_index <- which(vapply(values$messages, function(m) identical(m$id, streaming_state$msg_id), logical(1)))
          if (length(msg_index) > 0) {
            final_text <- if (nchar(streaming_state$accumulated) > 0) streaming_state$accumulated else full_response

            # Proje ve Kaynak Analizi köken alt bilgisi. TTS motoru yukarıda
            # `full_response` ile ÇOKTAN çağrıldığı için alt bilgi burada
            # eklendiğinde yalnızca ekrana/DB'ye gider, SESLENDİRİLMEZ.
            if (exists("pk_provenance_decorate", mode = "function", inherits = TRUE)) {
              final_text <- pk_provenance_decorate(final_text, session, request_id = pk_request_id)
            }

            chart_info <- build_chartlab_message(final_text, streaming_state$msg_id, session)
            if (isTRUE(chart_info$found)) {
              final_html <- chart_info$html
              final_hascode <- FALSE
            } else {
              final_processed <- process_message_content(final_text, "ai")
              final_html <- final_processed$html
              final_hascode <- final_processed$has_code
            }

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
              if (is.function(on_complete)) {
                try(on_complete(values$messages[[msg_index]]), silent = TRUE)
              }
            }, error = function(e) print(paste("Error saving message:", e$message)))
          }

          chat_reset_state(session, values)
          stream_observer$destroy()
          return()
        }

        chunk_end <- min(streaming_state$current_index + chunk_size - 1, total_words)
        chunk_words <- words[streaming_state$current_index:chunk_end]
        chunk_text <- paste(chunk_words, collapse = "")

        streaming_state$accumulated <- paste0(streaming_state$accumulated, chunk_text)

		# vapply kullanarak tip güvenliği sağla
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

  # -- 5. KARAR: TTS BEKLENSİN Mİ? --
  if (!is.null(tts_engine) && is.function(tts_engine) && nzchar(full_response)) {
      cat(sprintf("[TTS-STREAM] Seslendirme başlatılıyor (ses: %s, metin: %d karakter)\n",
                  tts_voice %||% "varsayılan", nchar(full_response)))
      # "Düşünüyor" animasyonu TTS hazır olana kadar görünür kalır
      promises::then(
          tts_engine(full_response, tts_voice),
          onFulfilled = function(result) {
              # TTS tamamlandı -> Metin akışı ve ses birlikte başlasın
              if (isTRUE(result$success)) {
                cat(sprintf("[TTS-STREAM] Seslendirme başarılı (süre: %.2fs)\n", result$duration %||% 0))
              } else {
                cat(sprintf("[TTS-STREAM] Seslendirme başarısız: %s\n", result$error %||% "bilinmeyen hata"))
              }
              start_streaming_execution(result)
          },
          onRejected = function(err) {
              # TTS başarısız -> Metin akışı yine de başlasın
              cat(sprintf("[TTS-STREAM] Promise hatası: %s\n", conditionMessage(err)))
              start_streaming_execution(NULL)
          }
      )
  } else {
      # TTS yok -> Hemen başla
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

  # Faz 6 (§5.10): kaydedilmemiş sohbetler `NULL` kimliği PAYLAŞIR; nesil sayacı olmadan ayırt edilemez ve tamamlanan bir PK işçisinin sonucu taze sohbete düşerdi.
  # D11 devralinan varlik baglami SOHBETE aittir: Yeni Soylesi'de dusurulmezse taze sohbet onceki sohbetin oznesini devralirdi.
  for (fn in c("pk_entity_context_clear", "mergen_pk_bump_chat_epoch",
               "mergen_pk_abandon_active_requests")) {
    if (exists(fn, mode = "function", inherits = TRUE)) {
      try(get(fn, mode = "function")(session), silent = TRUE)
    }
  }

  # Yeni söyleşide dosya bağlamı ve MCP anlık görüntüsü temiz başlar.
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

  # Karşılama ekranında "aşağı kaydır" butonunu gizle
  shinyjs::runjs("$('#scroll_to_bottom_container').removeClass('show');")

  # NOT: Eski sürüm karşılama ekranını burada #chat_content_container içine de
  # ekliyordu; hemen ardından start_new_chat() aynı ekranı
  # #welcome_fullscreen_container içinde TAM olarak yeniden render ettiği için
  # bu ilk ekleme boşa giden büyük bir HTML yüküydü (çift render + gecikme).
  # Karşılama render sorumluluğu tek yerde: render_welcome_screen().
  showToast(session, "Yeni söyleşi başlatıldı.", "success")
}

chat_rebind_all_charts <- function(session, output, messages) {
  if (length(messages) == 0) return(invisible(NULL))

  for (msg in messages) {
    if (!is.character(msg$content) ||
        length(msg$content) == 0 ||
        !grepl("```chartlab", msg$content[1], fixed = TRUE)) {
      next
    }

    chart_info <- build_chartlab_message(msg$content[1], msg$id, session)

    if (isTRUE(chart_info$found) && length(chart_info$renderers) > 0) {
      for (r in chart_info$renderers) {
        local({
          local_r <- r
          session$onFlushed(function() {
            try(wire_chart_output(output, local_r$output_id, local_r$spec), silent = TRUE)
          }, once = TRUE)
        })
      }
    }
  }

  invisible(NULL)
}
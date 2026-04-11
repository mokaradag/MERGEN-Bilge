# R/server_tts_handlers.R
# Dosya Yolu: R/server_tts_handlers.R
# Açıklama: Metin-konuşma (TTS) işlemleri için yardımcı fonksiyonlar ve observer'lar.
# Bu dosya server.R'den ayrılarak modülerlik sağlanmıştır.

#' TTS İşleyicilerini Başlat
#' @description TTS ile ilgili fonksiyonları ve observer'ları kurar
#' @param session Shiny session nesnesi
#' @param values Ana reaktif değerler
#' @param settings_data Ayarlar modülünden dönen reaktif ayarlar
#' @param tts_processor TTS işleme modülü
#' @param tts_visualizer TTS görselleştirici modülü
#' @param stop_generation Durdurma sinyali reactiveVal
#' @return TTS fonksiyonlarını içeren liste
ttsHandlersInit <- function(input, session, values, settings_data, tts_processor, tts_visualizer, stop_generation) {

  tts_warning_shown <- shiny::reactiveVal(FALSE)

  tts_request_generation <- shiny::reactiveVal(0L)

  advance_tts_generation <- function() {
    next_gen <- shiny::isolate(tts_request_generation()) + 1L
    tts_request_generation(next_gen)
    next_gen
  }

  is_current_tts_generation <- function(gen_id) {
    identical(shiny::isolate(tts_request_generation()), gen_id)
  }

  shiny::observeEvent(input$tts_stop_requested, {
    cancelled_gen <- advance_tts_generation()
    cat(sprintf(
      "[TTS] Kullanıcı seslendirmeyi durdurdu. Bekleyen parçalar iptal edildi (nesil=%d)\n",
      cancelled_gen
    ))
  }, ignoreInit = TRUE)

  tts_unavailable_reason <- function() {
    if (!isTRUE(shiny::isolate(settings_data$enable_tts_audio))) {
      return("AI yanıtlarını seslendirme ayarı kapalı.")
    }
    if (!is.list(tts_processor) || !is.function(tts_processor$tts_available)) {
      return("Seslendirme modülü yüklenemedi.")
    }
    avail <- FALSE
    try(avail <- isTRUE(tts_processor$tts_available()), silent = TRUE)
    if (!isTRUE(avail)) {
      return("Seslendirme uç noktası yapılandırılmadı.")
    }
    NULL
  }

  tts_enabled <- function() {
    is.null(tts_unavailable_reason())
  }

  shiny::observeEvent(settings_data$enable_tts_audio, {
    tts_warning_shown(FALSE)
  })

  attach_tts_audio <- function(message_id, audio_src, voice_used = NULL) {
    if (is.null(message_id) || !nzchar(audio_src)) return(invisible(NULL))

    idx <- which(vapply(values$messages, function(m) m$id == message_id, logical(1)))
    if (length(idx) == 1) {
      values$messages[[idx]]$audio_src <- audio_src
      values$messages[[idx]]$audio_voice <- voice_used
      if (!is.null(values$current_chat_id)) {
        chat_store_message_in_saved_chats(values, values$messages[[idx]])
      }
    }

    try(shiny::removeUI(selector = sprintf("#tts_audio_%s", message_id), immediate = TRUE), silent = TRUE)
    audio_ui <- build_tts_audio_ui(message_id, audio_src, voice_used)
    if (!is.null(audio_ui)) {
      shiny::insertUI(
        selector = sprintf("#message_wrapper_%s .ai-message", message_id),
        where = "beforeEnd",
        ui = audio_ui,
        immediate = TRUE
      )

      shinyjs::runjs(sprintf("
        setTimeout(() => {
          var audio = document.querySelector('#tts_audio_%s audio');
          if (audio) {
            audio.volume = 1.0;
            var playPromise = audio.play();
            if (playPromise !== undefined) {
              playPromise.catch(error => {
                console.log('Otomatik oynatma tarayıcı tarafından engellendi:', error);
              });
            }
          }
          window.smartScrollToBottom && window.smartScrollToBottom();
        }, 100);
      ", message_id))
    }
  }

  # Uzun metni cümle sınırlarında parçalara bölen yardımcı fonksiyon
  split_text_into_chunks <- function(text, max_chunk_chars = 350, min_chunk_chars = 120) {
    text <- trimws(as.character(text %||% ""))
    if (!nzchar(text)) return(list())
    if (nchar(text) <= max_chunk_chars) return(list(text))

    sentence_candidates <- unlist(strsplit(text, "(?<=[.!?…])\\s+", perl = TRUE))
    sentence_candidates <- trimws(sentence_candidates)
    sentence_candidates <- sentence_candidates[nzchar(sentence_candidates)]

    if (length(sentence_candidates) == 0) {
      sentence_candidates <- text
    }

    split_long_piece <- function(piece) {
      piece <- trimws(piece)
      if (!nzchar(piece)) return(character(0))
      if (nchar(piece) <= max_chunk_chars) return(piece)

      comma_parts <- unlist(strsplit(piece, "(?<=[,;:])\\s+", perl = TRUE))
      comma_parts <- trimws(comma_parts)
      comma_parts <- comma_parts[nzchar(comma_parts)]

      if (length(comma_parts) <= 1) {
        words <- unlist(strsplit(piece, "\\s+"))
        out <- character(0)
        current <- ""

        for (w in words) {
          candidate <- trimws(paste(current, w))
          if (!nzchar(current) || nchar(candidate) <= max_chunk_chars) {
            current <- candidate
          } else {
            out <- c(out, current)
            current <- w
          }
        }

        if (nzchar(current)) out <- c(out, current)
        return(out)
      }

      out <- character(0)
      current <- ""

      for (part in comma_parts) {
        candidate <- trimws(paste(current, part))
        if (!nzchar(current) || nchar(candidate) <= max_chunk_chars) {
          current <- candidate
        } else {
          out <- c(out, split_long_piece(current))
          current <- part
        }
      }

      if (nzchar(current)) out <- c(out, split_long_piece(current))
      out
    }

    chunks <- character(0)
    current <- ""

    for (sentence in sentence_candidates) {
      sentence_parts <- split_long_piece(sentence)

      for (part in sentence_parts) {
        candidate <- trimws(paste(current, part))
        if (!nzchar(current)) {
          current <- part
        } else if (nchar(candidate) <= max_chunk_chars) {
          current <- candidate
        } else if (nchar(current) < min_chunk_chars) {
          current <- candidate
        } else {
          chunks <- c(chunks, current)
          current <- part
        }
      }
    }

    if (nzchar(current)) chunks <- c(chunks, current)

    chunks <- trimws(chunks)
    chunks <- chunks[nzchar(chunks)]

    as.list(chunks)
  }

  trigger_tts_for_message <- function(msg_id, content) {
    if (!isTRUE(settings_data$enable_tts_audio)) return(invisible(NULL))

    full_text <- as.character(content)[1]
    if (!nzchar(full_text)) return(invisible(NULL))

    selected_char_id <- shiny::isolate(settings_data$selected_character) %||% "mergen"
    chars_data <- get_characters_data()
    character_data <- if (!is.null(chars_data)) {
      Find(function(x) x$id == selected_char_id, chars_data$styles)
    } else NULL

    voice_sel <- if (!is.null(character_data) && !is.null(character_data$tts_voice)) {
      character_data$tts_voice
    } else {
      "tr-male-1"
    }

    request_gen <- advance_tts_generation()

    send_chunk <- function(res, idx) {
      if (!is_current_tts_generation(request_gen)) return(invisible(NULL))
      if (isTRUE(stop_generation())) return(invisible(NULL))

      if (isTRUE(res$success) && nzchar(res$audio_src)) {
        cat(sprintf("[TTS] Parça %d gönderiliyor (Süre: %.2fs)\n", idx, res$duration))

        tts_visualizer$trigger(duration = res$duration)

        session$sendCustomMessage("playAudioMessage", list(
          id = msg_id,
          src = res$audio_src,
          chunkIndex = idx,
          timestamp = as.numeric(Sys.time())
        ))
      } else {
        cat(sprintf("[TTS] Parça %d başarısız oldu, atlanıyor.\n", idx))
      }

      invisible(NULL)
    }

    chunks <- split_text_into_chunks(full_text, max_chunk_chars = 350, min_chunk_chars = 120)

    cat(sprintf(
      "[TTS] Metin %d parçaya bölündü (toplam: %d karakter, nesil=%d)\n",
      length(chunks), nchar(full_text), request_gen
    ))

    play_next_chunk <- NULL
    play_next_chunk <- function(i) {
      if (!is_current_tts_generation(request_gen)) return(invisible(NULL))
      if (isTRUE(stop_generation())) return(invisible(NULL))
      if (i > length(chunks)) return(invisible(NULL))

      chunk_text <- chunks[[i]]
      chunk_idx <- i - 1L

      cat(sprintf(
        "[TTS] Parça %d/%d sentezleniyor (%d karakter)\n",
        i, length(chunks), nchar(chunk_text)
      ))

      tts_processor$synthesize_speech(chunk_text, voice = voice_sel) %...>%
        (function(res) {
          if (!is_current_tts_generation(request_gen)) return(invisible(NULL))
          if (isTRUE(stop_generation())) return(invisible(NULL))

          send_chunk(res, chunk_idx)

          if (is_current_tts_generation(request_gen) && !isTRUE(stop_generation())) {
            play_next_chunk(i + 1L)
          }

          invisible(NULL)
        }) %...!%
        (function(e) {
          if (!is_current_tts_generation(request_gen)) return(invisible(NULL))

          cat(sprintf("[TTS] Parça %d hatası: %s\n", chunk_idx, conditionMessage(e)))

          if (is_current_tts_generation(request_gen) && !isTRUE(stop_generation())) {
            play_next_chunk(i + 1L)
          }

          invisible(NULL)
        })

      invisible(NULL)
    }

    play_next_chunk(1L)

    invisible(NULL)
  }

  list(
    tts_warning_shown = tts_warning_shown,
    tts_unavailable_reason = tts_unavailable_reason,
    tts_enabled = tts_enabled,
    attach_tts_audio = attach_tts_audio,
    trigger_tts_for_message = trigger_tts_for_message
  )
}
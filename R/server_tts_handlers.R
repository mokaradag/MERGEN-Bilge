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
ttsHandlersInit <- function(session, values, settings_data, tts_processor, tts_visualizer, stop_generation) {

  tts_warning_shown <- shiny::reactiveVal(FALSE)

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

    send_chunk <- function(res, idx) {
      if (isTRUE(stop_generation())) return()

      if (isTRUE(res$success) && nzchar(res$audio_src)) {
        cat(sprintf("[TTS] Sending chunk %d (Duration: %.2fs)\n", idx, res$duration))

        tts_visualizer$trigger(duration = res$duration)

        session$sendCustomMessage("playAudioMessage", list(
          id = msg_id,
          src = res$audio_src,
          chunkIndex = idx,
          timestamp = as.numeric(Sys.time())
        ))
      }
    }

    if (nchar(full_text) > 15) {
      search_window <- substr(full_text, 1, 50)

      split_pos <- -1
      punct_match <- regexpr("[.,?!:;](?=\\s|$)", search_window, perl = TRUE)

      if (punct_match > 0) {
        split_pos <- punct_match + attr(punct_match, "match.length") - 1
      } else {
        spaces <- gregexpr("\\s", search_window)[[1]]
        valid_spaces <- spaces[spaces > 10]
        if (length(valid_spaces) > 0) {
          split_pos <- valid_spaces[1]
        } else if (length(spaces) > 0 && spaces[1] > 0) {
          split_pos <- tail(spaces, 1)
        }
      }

      if (split_pos > 2) {
        first_chunk <- substr(full_text, 1, split_pos)
        remainder   <- trimws(substr(full_text, split_pos + 1, nchar(full_text)))

        if (nzchar(remainder)) {
          cat("[TTS] Fast split active. Chunk 1:", nchar(first_chunk), "chars.\n")

          p1 <- tts_processor$synthesize_speech(first_chunk, voice = voice_sel)
          p2 <- tts_processor$synthesize_speech(remainder, voice = voice_sel)

          p1 %...>% (function(res) send_chunk(res, 0)) %...!% (function(e) warning("TTS C1 fail"))
          p2 %...>% (function(res) send_chunk(res, 1)) %...!% (function(e) warning("TTS C2 fail"))

          return(invisible(NULL))
        }
      }
    }

    tts_processor$synthesize_speech(full_text, voice = voice_sel) %...>%
      (function(res) send_chunk(res, 0)) %...!%
      (function(e) cat("[TTS] Error:", conditionMessage(e), "\n"))

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

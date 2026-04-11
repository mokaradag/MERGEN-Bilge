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

  # Uzun metni cümle sınırlarında parçalara bölen yardımcı fonksiyon
  split_text_into_chunks <- function(text, max_chunk_chars = 800) {
    if (nchar(text) <= max_chunk_chars) return(list(text))

    chunks <- list()
    remaining <- text

    while (nzchar(remaining)) {
      if (nchar(remaining) <= max_chunk_chars) {
        chunks <- c(chunks, list(remaining))
        break
      }

      # max_chunk_chars sınırı içinde son cümle sonu bul
      search_window <- substr(remaining, 1, max_chunk_chars)

      # Öncelik 1: Cümle sonu noktalama (.!?)
      split_pos <- -1
      punct_positions <- gregexpr("[.!?](?=\\s|$)", search_window, perl = TRUE)[[1]]
      if (punct_positions[1] > 0) {
        # En son cümle sonunu tercih et
        split_pos <- tail(punct_positions, 1)
      }

      # Öncelik 2: Virgül, noktalı virgül, iki nokta
      if (split_pos < 10) {
        secondary_punct <- gregexpr("[,;:](?=\\s)", search_window, perl = TRUE)[[1]]
        if (secondary_punct[1] > 0) {
          split_pos <- tail(secondary_punct, 1)
        }
      }

      # Öncelik 3: Kelime sınırı (boşluk)
      if (split_pos < 10) {
        spaces <- gregexpr("\\s", search_window)[[1]]
        if (spaces[1] > 0) {
          split_pos <- tail(spaces, 1)
        }
      }

      # Hiçbir bölünme noktası bulunamazsa zorla böl
      if (split_pos < 1) {
        split_pos <- max_chunk_chars
      }

      chunk <- trimws(substr(remaining, 1, split_pos))
      remaining <- trimws(substr(remaining, split_pos + 1, nchar(remaining)))

      if (nzchar(chunk)) {
        chunks <- c(chunks, list(chunk))
      }
    }

    chunks
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
        cat(sprintf("[TTS] Parça %d gönderiliyor (Süre: %.2fs)\n", idx, res$duration))

        tts_visualizer$trigger(duration = res$duration)

        session$sendCustomMessage("playAudioMessage", list(
          id = msg_id,
          src = res$audio_src,
          chunkIndex = idx,
          timestamp = as.numeric(Sys.time())
        ))
      }
    }

    # Metni parçalara böl (uzun metinler için çoklu parça desteği)
    chunks <- split_text_into_chunks(full_text, max_chunk_chars = 800)
    cat(sprintf("[TTS] Metin %d parçaya bölündü (toplam: %d karakter)\n", length(chunks), nchar(full_text)))

    # Her parça için TTS isteği oluştur
    for (i in seq_along(chunks)) {
      chunk_text <- chunks[[i]]
      chunk_idx <- i - 1L
      local({
        idx <- chunk_idx
        current_text <- chunk_text

        tts_processor$synthesize_speech(current_text, voice = voice_sel) %...>%
          (function(res) send_chunk(res, idx)) %...!%
          (function(e) cat(sprintf("[TTS] Parça %d hatası: %s\n", idx, conditionMessage(e))))
      })
    }

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
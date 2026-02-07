# Dosya Yolu: R/server_observers_image_gallery.R
# Gorsel galerisi observer fonksiyonlari - sohbete yonlendirme ve gorsel silme sonrasi reaktif guncellemeler

#' Gorsel Galerisi Gozlemcilerini Baslat
#' @param input Shiny input nesnesi
#' @param session Shiny session nesnesi
#' @param values Ana reaktif degerler
#' @param settings_data Ayarlar modulu reaktif verileri
#' @param gallery_data Galeri modulu reaktif verileri
#' @param saved_chats_data Kayitli sohbet modulu reaktif verileri
#' @param current_user_id Mevcut kullanici ID
#' @param load_chat_in_progress Sohbet yukleme kilidi
imageGalleryObserversInit <- function(input, session, values, settings_data,
                                      gallery_data, saved_chats_data,
                                      current_user_id, load_chat_in_progress) {

  observeEvent(gallery_data$navigate_to_chat(), {
    info <- gallery_data$navigate_to_chat()
    req(info)

    chat_id <- info$chat_id

    if (is.null(chat_id) || is.na(chat_id) || !nzchar(chat_id)) {
      showToast(session, "Bu g\u00f6rselin ait oldu\u011fu s\u00f6yle\u015fi bulunamad\u0131.", "error")
      return()
    }

    if (load_chat_in_progress()) {
      showToast(session, "Bir s\u00f6yle\u015fi y\u00fckleniyor, l\u00fctfen bekleyin.", "info")
      return()
    }

    load_chat_in_progress(TRUE)

    chat_to_load <- values$saved_chats[[chat_id]]

    if (is.null(chat_to_load)) {
      detail <- tryCatch(
        load_chat_messages_from_db(chat_id),
        error = function(e) {
          warning(sprintf("[IMAGE_GALLERY] Sohbet yuklenemedi %s: %s", chat_id, e$message))
          NULL
        }
      )
      if (!is.null(detail)) {
        chat_to_load <- detail
        saved_copy <- values$saved_chats
        saved_copy[[chat_id]] <- chat_to_load
        values$saved_chats <- saved_copy
      }
    }

    if (is.null(chat_to_load)) {
      showToast(session, "Bu s\u00f6yle\u015fi art\u0131k mevcut de\u011fil veya silinmi\u015f.", "error")
      load_chat_in_progress(FALSE)
      return()
    }

    shinyjs::runjs("
      if(window.WelcomeVideoPlayer && window.WelcomeVideoPlayer.destroy) {
        window.WelcomeVideoPlayer.destroy();
      }
      if(window.WelcomeNeuralNetwork && window.WelcomeNeuralNetwork.destroy) {
        window.WelcomeNeuralNetwork.destroy();
      }
      if(window.WelcomeGreeting && window.WelcomeGreeting.destroy) {
        window.WelcomeGreeting.destroy();
      }
      $('#welcome_fullscreen_container').addClass('hidden').empty();
      $('#chat_content_container').show().empty();
    ")

    removeUI(selector = "#welcome_fullscreen_container > *", multiple = TRUE, immediate = TRUE)
    removeUI(selector = "#chat_content_container > *", multiple = TRUE, immediate = TRUE)

    values$messages <- chat_to_load$messages %||% list()
    all_feedback <- load_feedback_from_db(current_user_id)
    values$liked_messages <- all_feedback$liked
    values$disliked_messages <- all_feedback$disliked
    values$current_chat_id <- chat_id
    values$show_welcome <- FALSE

    selected_char_id <- isolate(settings_data$selected_character) %||% "mergen"
    chars_data <- get_characters_data()
    character_data <- if (!is.null(chars_data)) {
      Find(function(x) x$id == selected_char_id, chars_data$styles)
    } else NULL

    for (i in seq_along(values$messages)) {
      msg <- values$messages[[i]]
      is_last_user_msg <- (msg$type == "user" && i == length(values$messages))

      ui_to_insert <- render_message_bubble_ui(
        msg, settings_data,
        is_last_user_message = is_last_user_msg,
        character_data = character_data,
        liked_ids = values$liked_messages,
        disliked_ids = values$disliked_messages
      )

      insertUI(selector = "#chat_content_container", where = "beforeEnd", ui = ui_to_insert)

      wrapper_id <- paste0("message_wrapper_", msg$id)
      if (isTRUE(msg$has_code)) {
        shinyjs::runjs(sprintf("
          setTimeout(function() {
            var wrapper = document.getElementById('%s');
            if (wrapper) {
              var editors = wrapper.querySelectorAll('.CodeMirror');
              editors.forEach(function(cm) {
                if (cm.CodeMirror) cm.CodeMirror.refresh();
              });
            }
          }, 200);
        ", wrapper_id))
      }

      if (msg$type == "ai" && grepl("data-chartlab-spec", msg$html_content %||% "", fixed = TRUE)) {
        shinyjs::delay(300, {
          shinyjs::runjs(sprintf(
            "window.renderSavedCharts && window.renderSavedCharts('%s');",
            wrapper_id
          ))
        })
      }
    }

    shinyjs::runjs("setTimeout(() => { scrollToBottom(false); }, 300);")

    updateTabItems(session, "tabs", "chat")
    chat_title <- chat_to_load$title %||% "S\u00f6yle\u015fi"
    showToast(session, paste("S\u00f6yle\u015fi y\u00fcklendi:", chat_title), "info")

    shinyjs::delay(500, {
      load_chat_in_progress(FALSE)
    })
  }, ignoreInit = TRUE)

  observeEvent(gallery_data$delete_image(), {
    info <- gallery_data$delete_image()
    req(info)

    chat_id <- info$chat_id
    if (!is.null(chat_id) && identical(as.character(values$current_chat_id), as.character(chat_id))) {
      cat("[IMAGE_GALLERY] Mevcut sohbetteki gorsel silindi, mesajlar yeniden yukleniyor\n")
    }
  }, ignoreInit = TRUE)

  invisible(NULL)
}

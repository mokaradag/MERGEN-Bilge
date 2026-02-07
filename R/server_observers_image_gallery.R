# Dosya Yolu: R/server_observers_image_gallery.R
# Görsel galerisi observer fonksiyonları - söyleşiye yönlendirme ve görsel silme sonrası reaktif güncellemeler

#' Görsel Galerisi Gözlemcilerini Başlat
#' @param input Shiny input nesnesi
#' @param session Shiny session nesnesi
#' @param values Ana reaktif değerler
#' @param settings_data Ayarlar modülü reaktif verileri
#' @param gallery_data Galeri modülü reaktif verileri
#' @param saved_chats_data Kayıtlı söyleşi modülü reaktif verileri
#' @param current_user_id Mevcut kullanıcı ID
#' @param load_chat_in_progress Söyleşi yükleme kilidi
imageGalleryObserversInit <- function(input, session, values, settings_data,
                                      gallery_data, saved_chats_data,
                                      current_user_id, load_chat_in_progress) {

  # Görsele tıklandığında ilgili söyleşiye yönlendir
  observeEvent(gallery_data$navigate_to_chat(), {
    info <- gallery_data$navigate_to_chat()
    req(info)

    chat_id_raw <- info$chat_id

    if (is.null(chat_id_raw) || is.na(chat_id_raw) || !nzchar(chat_id_raw)) {
      showToast(session, "Bu görselin ait olduğu söyleşi bulunamadı.", "error")
      return()
    }

    # chat_id'nin geçerli bir sayısal değer olduğunu doğrula
    chat_id_int <- suppressWarnings(as.integer(chat_id_raw))
    if (is.na(chat_id_int)) {
      showToast(session, "Geçersiz söyleşi kimliği.", "error")
      return()
    }

    # String olarak kullanılacak chat_id (values$saved_chats anahtarı için)
    chat_id <- as.character(chat_id_int)

    if (load_chat_in_progress()) {
      showToast(session, "Bir söyleşi yükleniyor, lütfen bekleyin.", "info")
      return()
    }

    load_chat_in_progress(TRUE)

    # Önce mevcut önbelleğe bak
    chat_to_load <- values$saved_chats[[chat_id]]

    # Önbellekte yoksa veritabanından yükle
    if (is.null(chat_to_load)) {
      detail <- tryCatch(
        load_chat_messages_from_db(chat_id_int),
        error = function(e) {
          warning(sprintf("[IMAGE_GALLERY] Söyleşi yüklenemedi (ChatID: %s): %s", chat_id, e$message))
          NULL
        }
      )
      if (!is.null(detail) && detail$message_count > 0) {
        chat_to_load <- detail
        saved_copy <- values$saved_chats
        saved_copy[[chat_id]] <- chat_to_load
        values$saved_chats <- saved_copy
      }
    }

    if (is.null(chat_to_load)) {
      showToast(session, "Bu söyleşi artık mevcut değil veya silinmiş.", "error")
      load_chat_in_progress(FALSE)
      return()
    }

    # Karşılama ekranını temizle
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

    # Mesajları ve durum bilgisini yükle
    values$messages <- chat_to_load$messages %||% list()
    all_feedback <- load_feedback_from_db(current_user_id)
    values$liked_messages <- all_feedback$liked
    values$disliked_messages <- all_feedback$disliked
    values$current_chat_id <- chat_id_int
    values$show_welcome <- FALSE

    selected_char_id <- isolate(settings_data$selected_character) %||% "mergen"
    chars_data <- get_characters_data()
    character_data <- if (!is.null(chars_data)) {
      Find(function(x) x$id == selected_char_id, chars_data$styles)
    } else NULL

    # Mesaj balonlarını sırayla ekle
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
    chat_title <- chat_to_load$title %||% "Söyleşi"
    showToast(session, paste("Söyleşi yüklendi:", chat_title), "info")

    shinyjs::delay(500, {
      load_chat_in_progress(FALSE)
    })
  }, ignoreInit = TRUE)

  # Tekil görsel silindikten sonra ilgili söyleşinin önbelleğini temizle
  observeEvent(gallery_data$delete_image(), {
    info <- gallery_data$delete_image()
    req(info)

    chat_id <- info$chat_id
    if (!is.null(chat_id) && !is.na(chat_id)) {
      chat_key <- as.character(chat_id)

      # Önbellekteki söyleşi verisini temizle (eski base64 görseller kalmaz)
      saved_copy <- values$saved_chats
      if (!is.null(saved_copy[[chat_key]])) {
        saved_copy[[chat_key]] <- NULL
        values$saved_chats <- saved_copy
        cat(sprintf("[IMAGE_GALLERY] Söyleşi önbelleği temizlendi (ChatID: %s)\n", chat_key))
      }

      # Eğer şu an o söyleşi aktifse, mesajları yeniden yükle
      if (identical(as.character(values$current_chat_id), chat_key)) {
        detail <- tryCatch(
          load_chat_messages_from_db(suppressWarnings(as.integer(chat_id))),
          error = function(e) NULL
        )
        if (!is.null(detail)) {
          values$messages <- detail$messages %||% list()
        }
      }
    }
  }, ignoreInit = TRUE)

  # Tüm görseller silindikten sonra tüm önbelleği temizle
  observeEvent(gallery_data$clear_all_images(), {
    # Tüm söyleşi önbelleğini temizle
    values$saved_chats <- list()
    cat("[IMAGE_GALLERY] Tüm söyleşi önbelleği temizlendi\n")

    # Aktif söyleşi varsa mesajları veritabanından yeniden yükle
    if (!is.null(values$current_chat_id)) {
      detail <- tryCatch(
        load_chat_messages_from_db(values$current_chat_id),
        error = function(e) NULL
      )
      if (!is.null(detail)) {
        values$messages <- detail$messages %||% list()
      }
    }
  }, ignoreInit = TRUE)

  invisible(NULL)
}

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

  resolve_runtime_user_id <- function() {
    uid <- if (is.function(current_user_id)) current_user_id() else current_user_id
    uid <- suppressWarnings(as.integer(session$userData$user_id %||% uid %||% 0L))
    if (is.na(uid) || uid < 0L) uid <- 0L
    uid
  }

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

    # Kullanıcıya anında geri bildirim ver: DB hidrasyonu veya uzun mesaj render'ı
    # bitmeden sohbet sekmesine geçip hafif bir yükleniyor durumunu göster.
    if (exists("updateTabItems", mode = "function", inherits = TRUE)) {
      updateTabItems(session, "tabs", "chat")
    } else if (requireNamespace("shinydashboard", quietly = TRUE)) {
      shinydashboard::updateTabItems(session, "tabs", "chat")
    }
    shinyjs::runjs("
      $('#welcome_fullscreen_container').addClass('hidden').empty();
      $('#chat_content_container')
        .show()
        .css('display','block')
        .html('<div class=\"chat-loading-state image-gallery-chat-loading\"><i class=\"fas fa-spinner fa-spin\"></i><span>Söyleşi yükleniyor...</span></div>');
    ")

    # Önce mevcut önbelleğe bak
    chat_to_load <- values$saved_chats[[chat_id]]

    # Mesajların gerçekten yüklenip yüklenmediğini kontrol et (hidrasyon kontrolü)
    needs_hydrate <- is.null(chat_to_load)
    if (!needs_hydrate) {
      msgs <- chat_to_load$messages
      stored_len <- if (is.list(msgs)) length(msgs) else 0L
      expected_len <- as.integer(chat_to_load$message_count %||% stored_len)
      needs_hydrate <- is.null(msgs) || !is.list(msgs) || stored_len == 0 ||
        (!is.na(expected_len) && expected_len > stored_len)
    }

    # Önbellekte yoksa veya mesajlar yüklenmemişse veritabanından yükle
    if (isTRUE(needs_hydrate)) {
      detail <- tryCatch(
        load_chat_messages_from_db(
          chat_id_int,
          user_id = resolve_runtime_user_id()
        ),
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

    # Mesajları ve durum bilgisini yükle
    values$messages <- chat_to_load$messages %||% list()
	all_feedback <- load_feedback_from_db(resolve_runtime_user_id())
    values$liked_messages <- all_feedback$liked
    values$disliked_messages <- all_feedback$disliked
    values$current_chat_id <- chat_id_int
    values$show_welcome <- FALSE

    selected_char_id <- normalize_character_id(isolate(settings_data$selected_character))
    chars_data <- get_characters_data()
    character_data <- if (!is.null(chars_data)) {
      Find(function(x) x$id == selected_char_id, chars_data$styles)
    } else NULL

    # Görsel Uzmanı modunu aktifleştir (galeriden yönlendirildiği için görsel söyleşisi)
    analysis_tools <- c(
      "enable_rdata_tools", "enable_mcp_tools", "enable_summarization_tools",
      "enable_coding_tools", "enable_process_tools", "enable_app_expert_tools",
      "enable_image_tools"
    )

    # Önce diğer tüm araçları devre dışı bırak
    for (tool in analysis_tools) {
      if (tool != "enable_image_tools") {
        settings_data[[tool]] <- FALSE
        updateCheckboxInput(session, paste0("settings_yapilandirma_module-", tool), value = FALSE)
      }
    }

    # Görsel Uzmanı aracını aktifleştir
    settings_data$enable_image_tools <- TRUE
    updateCheckboxInput(session, "settings_yapilandirma_module-enable_image_tools", value = TRUE)

    # Görsel modu için model ayarla ve UI kontrollerini güncelle
    image_model <- Sys.getenv("IMAGE_GEN_MODEL", "dall-e-3")
    settings_data$model_selection <- image_model
    session$sendCustomMessage("toggleImageMode", list(active = TRUE))
    session$sendCustomMessage("toggleSummaryMode", list(active = FALSE))
    session$sendCustomMessage("toggleProcessMode", list(active = FALSE))
    session$sendCustomMessage("saveSettings", list(
      enable_image_tools = TRUE,
      enable_rdata_tools = FALSE,
      enable_mcp_tools = FALSE,
      enable_summarization_tools = FALSE,
      enable_coding_tools = FALSE,
      enable_process_tools = FALSE,
      enable_app_expert_tools = FALSE,
      model_selection = image_model
    ))

    # Tıklanan görselin hangi mesajda olduğunu bul (kaydırma hedefi için)
    target_message_id <- NULL
    if (!is.null(info$file_path) && nzchar(info$file_path)) {
      target_filename <- basename(info$file_path)
      for (msg in values$messages) {
        if (grepl(target_filename, msg$content %||% "", fixed = TRUE)) {
          target_message_id <- msg$id
          break
        }
      }
    }

    chat_title <- chat_to_load$title %||% "Söyleşi"

    # Sekme geçişi sonrası mesajları tek DOM eklemesiyle yerleştir. Her mesaj için
    # ayrı insertUI çağırmak uzun görsel söyleşilerinde belirgin gecikme yaratıyordu.
    shinyjs::runjs("
      $('#welcome_fullscreen_container').addClass('hidden').empty();
      $('#chat_content_container').show().css('display','block').empty();
    ")

    message_ui <- tagList(lapply(seq_along(values$messages), function(i) {
      msg <- values$messages[[i]]
      is_last_user_msg <- (msg$type == "user" && i == length(values$messages))

      render_message_bubble_ui(
        msg, settings_data,
        is_last_user_message = is_last_user_msg,
        character_data = character_data,
        liked_ids = values$liked_messages,
        disliked_ids = values$disliked_messages
      )
    }))

    insertUI(selector = "#chat_content_container", where = "beforeEnd", ui = message_ui)

    code_wrapper_ids <- vapply(values$messages, function(msg) {
      if (isTRUE(msg$has_code)) paste0("message_wrapper_", msg$id) else NA_character_
    }, character(1))
    code_wrapper_ids <- code_wrapper_ids[!is.na(code_wrapper_ids)]

    if (length(code_wrapper_ids) > 0) {
      shinyjs::runjs(sprintf("
        setTimeout(function() {
          %s.forEach(function(id) {
            var wrapper = document.getElementById(id);
            if (!wrapper) return;
            var editors = wrapper.querySelectorAll('.CodeMirror');
            editors.forEach(function(cm) {
              if (cm.CodeMirror) cm.CodeMirror.refresh();
            });
          });
        }, 120);
      ", jsonlite::toJSON(code_wrapper_ids, auto_unbox = TRUE)))
    }

    if (any(vapply(values$messages, function(msg) {
      (msg$type %||% "") == "ai" && grepl("data-chartlab-spec", msg$html_content %||% "", fixed = TRUE)
    }, logical(1)))) {
      shinyjs::runjs("setTimeout(function() { window.renderSavedCharts && window.renderSavedCharts('chat_content_container'); }, 180);")
    }

    # Hedef görsele veya sohbet sonuna kaydır
    if (!is.null(target_message_id)) {
      shinyjs::runjs(sprintf("
        setTimeout(function() {
          var targetEl = document.getElementById('message_wrapper_%s');
          if (targetEl) {
            targetEl.scrollIntoView({behavior: 'auto', block: 'center'});
            // Görseli kısa süreliğine vurgula
            targetEl.style.transition = 'box-shadow 0.5s ease';
            targetEl.style.boxShadow = '0 0 0 3px rgba(255, 138, 0, 0.5)';
            setTimeout(function() { targetEl.style.boxShadow = ''; }, 2500);
          } else {
            scrollToBottom(false);
          }
        }, 80);
      ", target_message_id))
    } else {
      shinyjs::runjs("setTimeout(function() { scrollToBottom(false); }, 80);")
    }
    showToast(session, paste("Söyleşi yüklendi:", chat_title), "info")
    shinyjs::delay(120, { load_chat_in_progress(FALSE) })
  })

  # Tekil görsel silindikten sonra ilgili söyleşinin önbelleğini yenile
  observeEvent(gallery_data$delete_image(), {
    info <- gallery_data$delete_image()
    req(info)

    chat_id <- info$chat_id
    if (!is.null(chat_id) && !is.na(chat_id)) {
      chat_key <- as.character(chat_id)
      chat_id_int <- suppressWarnings(as.integer(chat_id))

      # Önbellekteki söyleşiyi silmek yerine veritabanından yeniden yükle
      if (!is.na(chat_id_int)) {
        refreshed <- tryCatch(
          load_chat_messages_from_db(
            chat_id_int,
            user_id = resolve_runtime_user_id()
          ),
          error = function(e) NULL
        )
        if (!is.null(refreshed)) {
          saved_copy <- values$saved_chats
          saved_copy[[chat_key]] <- refreshed
          values$saved_chats <- saved_copy
          cat(sprintf("[IMAGE_GALLERY] Söyleşi önbelleği yenilendi (ChatID: %s)\n", chat_key))
        }
      }

      # Eğer şu an o söyleşi aktifse, mesajları da yeniden yükle
      if (identical(as.character(values$current_chat_id), chat_key)) {
        detail <- tryCatch(
          load_chat_messages_from_db(
            chat_id_int,
            user_id = resolve_runtime_user_id()
          ),
          error = function(e) NULL
        )
        if (!is.null(detail)) {
          values$messages <- detail$messages %||% list()

          # Aktif söyleşinin DOM'unu yeniden oluştur
          shinyjs::runjs("$('#chat_content_container').empty();")
          selected_char_id <- normalize_character_id(isolate(settings_data$selected_character))
          chars_data <- get_characters_data()
          character_data <- if (!is.null(chars_data)) {
            Find(function(x) x$id == selected_char_id, chars_data$styles)
          } else NULL

          for (mi in seq_along(values$messages)) {
            msg <- values$messages[[mi]]
            is_last_user_msg <- (msg$type == "user" && mi == length(values$messages))
            ui_to_insert <- render_message_bubble_ui(
              msg, settings_data,
              is_last_user_message = is_last_user_msg,
              character_data = character_data,
              liked_ids = values$liked_messages,
              disliked_ids = values$disliked_messages
            )
            insertUI(selector = "#chat_content_container", where = "beforeEnd", ui = ui_to_insert)
          }
        }
      }
    }
  }, ignoreInit = TRUE)

  # Tüm görseller silindikten sonra etkilenen söyleşilerin önbelleğini yenile
  observeEvent(gallery_data$clear_all_images(), {
    # Etkilenen söyleşilerin önbelleğini veritabanından yeniden yükle (tümünü silmek yerine)
    saved_copy <- values$saved_chats
    needs_update <- FALSE

    for (chat_key in names(saved_copy)) {
      chat_data <- saved_copy[[chat_key]]
      if (!is.null(chat_data$messages)) {
        # Görsel mesajı içeren söyleşileri tespit et
        has_image <- any(sapply(chat_data$messages, function(msg) {
          grepl("^\\[GÖRSEL", msg$content %||% "", perl = TRUE)
        }))
        if (has_image) {
          # Sadece bu söyleşiyi veritabanından yeniden yükle
          chat_id_int <- suppressWarnings(as.integer(chat_key))
          if (!is.na(chat_id_int)) {
            refreshed <- tryCatch(
              load_chat_messages_from_db(
                chat_id_int,
                user_id = resolve_runtime_user_id()
              ),
              error = function(e) NULL
            )
            if (!is.null(refreshed)) {
              saved_copy[[chat_key]] <- refreshed
              needs_update <- TRUE
            }
          }
        }
      }
    }

    if (needs_update) {
      values$saved_chats <- saved_copy
    }
    cat("[IMAGE_GALLERY] Etkilenen söyleşi önbellekleri yenilendi\n")

    # Aktif söyleşi varsa mesajları veritabanından yeniden yükle
    if (!is.null(values$current_chat_id)) {
      detail <- tryCatch(
        load_chat_messages_from_db(
          values$current_chat_id,
          user_id = resolve_runtime_user_id()
        ),
        error = function(e) NULL
      )
      if (!is.null(detail)) {
        values$messages <- detail$messages %||% list()
      }
    }
  }, ignoreInit = TRUE)

  invisible(NULL)
}
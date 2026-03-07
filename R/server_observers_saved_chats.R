# R/server_observers_saved_chats.R
# Dosya Yolu: R/server_observers_saved_chats.R
# Açıklama: Kayıtlı söyleşilerin yüklenmesi, silinmesi ve temizlenmesi ile ilgili observer fonksiyonları.
# Bu dosya server.R'den ayrılarak modülerlik sağlanmıştır.

#' Kayıtlı Sohbet Gözlemcilerini Başlat
#' @description Kayıtlı söyleşi işlemleri için observer'ları kurar
#' @param input Shiny input nesnesi
#' @param output Shiny output nesnesi
#' @param session Shiny session nesnesi
#' @param values Ana reaktif değerler
#' @param settings_data Ayarlar modülünden dönen reaktif ayarlar
#' @param saved_chats_data Kayıtlı söyleşiler modül verisi
#' @param current_user_id Mevcut kullanıcı ID'si
#' @param load_chat_in_progress Sohbet yükleme kilit reaktif değeri
savedChatsObserversInit <- function(input, output, session, values, settings_data,
                                    saved_chats_data, current_user_id, 
                                    load_chat_in_progress) {
  
  # Son silinen sohbet ID'sini takip et (silme sonrası yanlış yüklemeyi engellemek için)
  last_deleted_chat_id <- reactiveVal(NULL)
  
  # -------------------------------------------------------------------------
  # Ortak Sohbet Yükleme Fonksiyonu
  # -------------------------------------------------------------------------
  do_load_chat <- function(chat_id) {
    # Boş veya NULL chat_id'yi yoksay
    if (is.null(chat_id) || !nzchar(chat_id)) {
      return()
    }
    
    # Son silinen sohbeti yüklemeye çalışıyorsa engelle
    if (identical(chat_id, last_deleted_chat_id())) {
      cat(sprintf("[SAVED_CHATS] Silinen sohbet yüklenmeye çalışıldı, engellendi: %s\n", chat_id))
      last_deleted_chat_id(NULL)  # Bayrağı sıfırla
      return()
    }
    
    # Çift yüklemeyi engelle
    if (load_chat_in_progress()) {
      return()
    }
    
    load_chat_in_progress(TRUE)
    
    chat_to_load <- values$saved_chats[[chat_id]]
    needs_hydrate <- is.null(chat_to_load)
    
    if (!needs_hydrate) {
      msgs <- chat_to_load$messages
      stored_len <- if (is.list(msgs)) length(msgs) else 0L
      expected_len <- as.integer(chat_to_load$message_count %||% stored_len)
      has_user <- stored_len > 0 && any(vapply(msgs, function(m) {
        identical(m$type %||% "", "user")
      }, logical(1)))
      has_ai <- stored_len > 0 && any(vapply(msgs, function(m) {
        m$type %||% "" %in% c("ai", "assistant")
      }, logical(1)))
      
      needs_hydrate <- is.null(msgs) || !is.list(msgs) || stored_len == 0 ||
        (!is.na(expected_len) && expected_len > stored_len) ||
        (has_user && !has_ai)
    }
    
    if (isTRUE(needs_hydrate)) {
      detail <- tryCatch(
        load_chat_messages_from_db(chat_id),
        error = function(e) {
          warning(sprintf("Failed to load chat %s messages: %s", chat_id, e$message))
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
    
    # Sohbet bulunamazsa çık
    if (is.null(chat_to_load)) {
      cat(sprintf("[SAVED_CHATS] Sohbet bulunamadı: %s\n", chat_id))
      load_chat_in_progress(FALSE)
      return()
    }
    
    # Welcome ekranını temizle ve aşağı kaydır butonunu gizle
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
      $('#scroll_to_bottom_container').removeClass('show');
    ")
    
    removeUI(selector = "#welcome_fullscreen_container > *", multiple = TRUE, immediate = TRUE)
    removeUI(selector = "#chat_content_container > *", multiple = TRUE, immediate = TRUE)
    
    values$messages <- chat_to_load$messages %||% list()
    all_feedback <- load_feedback_from_db(current_user_id)
    values$liked_messages <- all_feedback$liked
    values$disliked_messages <- all_feedback$disliked
    values$current_chat_id <- chat_id
    values$show_welcome <- FALSE

    # Mesaj iceriginden aktif araci tespit et ve etkinlestir
    # Not: Bazi isaretciler (source-link, kaynakca-entry) ham icerik yerine
    # HTML iceriginde bulunur, bu yuzden her iki alan da kontrol edilir.
    detected_tool <- NULL
    for (m in values$messages) {
      if (m$type %||% "" %in% c("ai", "assistant")) {
        msg_content <- m$content %||% ""
        msg_html <- m$html_content %||% ""
        combined_text <- paste(msg_content, msg_html)
        if (grepl("source-link|kaynakca-entry", combined_text, perl = TRUE)) {
          detected_tool <- "enable_process_tools"
        } else if (grepl("\\[GORSEL|\\[GÖRSEL|generated-image|image_gen_|dall-e|gorsel-sonuc", combined_text, ignore.case = TRUE, perl = TRUE)) {
          detected_tool <- "enable_image_tools"
        }
        if (!is.null(detected_tool)) break
      }
    }

    if (!is.null(detected_tool)) {
      # Tum analiz araclarini devre disi birak
      analysis_tools <- c(
        "enable_rdata_tools", "enable_mcp_tools", "enable_summarization_tools",
        "enable_coding_tools", "enable_process_tools", "enable_app_expert_tools",
        "enable_image_tools"
      )
      for (tool in analysis_tools) {
        isolate({ settings_data[[tool]] <- FALSE })
        updateCheckboxInput(session, paste0("settings_yapilandirma_module-", tool), value = FALSE)
      }
      # Tespit edilen araci etkinlestir
      isolate({ settings_data[[detected_tool]] <- TRUE })
      updateCheckboxInput(session, paste0("settings_yapilandirma_module-", detected_tool), value = TRUE)

      # istemci tarafini bilgilendir
      session$sendCustomMessage("saveSettings", stats::setNames(
        as.list(vapply(analysis_tools, function(t) identical(t, detected_tool), logical(1))),
        analysis_tools
      ))

      if (identical(detected_tool, "enable_image_tools")) {
        session$sendCustomMessage("toggleImageMode", list(active = TRUE))
      }

      cat(sprintf("[SAVED_CHATS] Arac tespit edildi ve etkinlestirildi: %s\n", detected_tool))
    }

    # Karakter verisini al
    selected_char_id <- isolate(settings_data$selected_character) %||% "mergen"
    chars_data <- get_characters_data()
    character_data <- if (!is.null(chars_data)) {
      Find(function(x) x$id == selected_char_id, chars_data$styles)
    } else NULL
    
    # Mesajları UI'ya ekle
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
      
      # Kod bloklarını initialize et (local ile closure sorununu önle)
      wrapper_id <- paste0("message_wrapper_", msg$id)
      if (isTRUE(msg$has_code)) {
        local({
          wid <- wrapper_id
          shinyjs::runjs(sprintf("
            setTimeout(function() {
              if (typeof window.initializeCodeMirrorInElement === 'function') {
                window.initializeCodeMirrorInElement('%s');
              }
            }, 200);
          ", wid))
        })
      }
    }

    # Tüm mesajlar eklendikten sonra grafikleri toplu olarak render et
    # 1) İstemci tarafında Highcharts ile statik grafikleri çiz (yeniden deneme mekanizmalı)
    shinyjs::runjs("
      setTimeout(function() {
        if (typeof window.renderSavedCharts === 'function') {
          window.renderSavedCharts('chat_content_container');
        }
      }, 600);
    ")
    # 2) Plotly/Highcharter çıktı bağlamalarını yeniden kur (sunucu taraflı grafikler)
    chat_rebind_all_charts(session, output, values$messages)

    shinyjs::runjs("setTimeout(function() { scrollToBottom(false); }, 400);")
    
    updateTabItems(session, "tabs", "chat")
    showToast(session, paste("Söyleşi yüklendi:", chat_to_load$title), "info")
    
    # Kilidi kısa bir gecikmeyle serbest bırak
    shinyjs::delay(500, {
      load_chat_in_progress(FALSE)
    })
  }
  
  # -------------------------------------------------------------------------
  # Sohbet Yükleme Observer'ları
  # -------------------------------------------------------------------------
  
  # Karşılama ekranından doğrudan gelen sohbet yükleme isteği
  # (eventReactive zincirini atlayarak ilk tıklama sorununu önler)
  observeEvent(input$welcome_load_chat_id, {
    do_load_chat(input$welcome_load_chat_id)
  }, ignoreInit = TRUE)
  
  # Kayıtlı Söyleşiler sayfasından gelen sohbet yükleme isteği (mevcut modül zinciri)
  observeEvent(saved_chats_data$load_chat_id(), {
    do_load_chat(saved_chats_data$load_chat_id())
  }, ignoreInit = TRUE)
  
  # -------------------------------------------------------------------------
  # Sohbet Silme ve Temizleme
  # -------------------------------------------------------------------------
  
  # Sohbet silme observer'ı
  observeEvent(saved_chats_data$delete_chat_id(), {
    chat_id <- saved_chats_data$delete_chat_id()
    req(chat_id)
    
    # Silinen sohbeti işaretle (yanlış yüklemeyi engellemek için)
    last_deleted_chat_id(chat_id)
    
    cat(sprintf("[SAVED_CHATS] Sohbet siliniyor: %s\n", chat_id))
    
    # Mevcut sohbet mi siliniyor kontrol et
    current_chat_deleted <- identical(as.character(values$current_chat_id), as.character(chat_id))
    
    delete_chat_from_db(chat_id, current_user_id)
    
    values$saved_chats <- load_chats_from_db(current_user_id, include_messages = FALSE)
    saved_chats_data$refresh()
    
    # Eğer mevcut sohbet silindiyse, Ana Söyleşi sayfasını sıfırla
    if (current_chat_deleted) {
      cat("[SAVED_CHATS] Mevcut sohbet silindi, welcome ekranına dönülüyor\n")
      
      # Sohbet durumunu sıfırla
      values$messages <- list()
      values$current_chat_id <- NULL
      values$show_welcome <- TRUE
      
      # Eski animasyonları temizle
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
        if(window.WelcomePersonalGreeting && window.WelcomePersonalGreeting.destroy) {
          window.WelcomePersonalGreeting.destroy();
        }
        
        // Mevcut sohbet içeriğini temizle
        $('#chat_content_container').empty().hide();
        
        // Welcome container'ı hazırla
        $('#welcome_fullscreen_container').empty().removeClass('hidden').show();
      ")
      
      removeUI(selector = "#chat_content_container > *", multiple = TRUE, immediate = TRUE)
      removeUI(selector = "#welcome_fullscreen_container > *", multiple = TRUE, immediate = TRUE)
      
      # Welcome ekranını yeniden render et ve animasyonları başlat
      shinyjs::delay(150, {
        # Welcome ekranı UI'ını ekle
        insertUI(
          selector = "#welcome_fullscreen_container",
          where = "beforeEnd",
          ui = createWelcomeScreen(values$saved_chats),
          immediate = TRUE
        )
        
        # Animasyonları başlat
        shinyjs::delay(100, {
          session$sendCustomMessage("initModernWelcome", list())
          
          # Kişiselleştirilmiş karşılama animasyonunu başlat
          shinyjs::delay(400, {
            session$sendCustomMessage("initPersonalGreeting", list(
              first_name = session$userData$user_first_name %||% ""
            ))
          })
        })
      })
    }
  }, ignoreInit = TRUE)
  
  # Tüm sohbetleri temizleme observer'ı
  observeEvent(saved_chats_data$clear_all_chats_trigger(), {
    if (saved_chats_data$clear_all_chats_trigger() > 0) {
      clear_all_chats_from_db(current_user_id)
      values$saved_chats <- list()
      saved_chats_data$refresh()
      showToast(session, "Tüm söyleşiler temizlendi.", "warning")
      
      # Mevcut sohbet varsa, Ana Söyleşi sayfasını sıfırla (tek silme ile aynı akış)
      if (!is.null(values$current_chat_id) || length(values$messages) > 0) {
        cat("[SAVED_CHATS] Tüm söyleşiler silindi, welcome ekranına dönülüyor\n")
        
        # Sohbet durumunu sıfırla
        values$messages <- list()
        values$current_chat_id <- NULL
        values$show_welcome <- TRUE
        
        # Eski animasyonları temizle
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
          if(window.WelcomePersonalGreeting && window.WelcomePersonalGreeting.destroy) {
            window.WelcomePersonalGreeting.destroy();
          }
          
          // Mevcut sohbet içeriğini temizle
          $('#chat_content_container').empty().hide();
          
          // Welcome container'ı hazırla
          $('#welcome_fullscreen_container').empty().removeClass('hidden').show();
        ")
        
        removeUI(selector = "#chat_content_container > *", multiple = TRUE, immediate = TRUE)
        removeUI(selector = "#welcome_fullscreen_container > *", multiple = TRUE, immediate = TRUE)
        
        # Welcome ekranını yeniden render et ve animasyonları başlat (boş liste ile)
        shinyjs::delay(150, {
          insertUI(
            selector = "#welcome_fullscreen_container",
            where = "beforeEnd",
            ui = createWelcomeScreen(list()),  # Boş liste - tüm sohbetler silindi
            immediate = TRUE
          )
          
          # Animasyonları başlat
          shinyjs::delay(100, {
            session$sendCustomMessage("initModernWelcome", list())
            
            # Kişiselleştirilmiş karşılama animasyonunu başlat
            shinyjs::delay(400, {
              session$sendCustomMessage("initPersonalGreeting", list(
                first_name = session$userData$user_first_name %||% ""
              ))
            })
          })
        })
      }
    }
  }, ignoreInit = TRUE)
  
  invisible(NULL)
}
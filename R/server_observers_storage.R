# R/server_observers_storage.R
# Dosya Yolu: R/server_observers_storage.R
# Açıklama: LocalStorage ve sohbet kalıcılığı ile ilgili observer fonksiyonları.
# Tarayıcı deposu senkronizasyonu ve sohbet geri yükleme işlemlerini yönetir.

#' Depolama Gözlemcilerini Başlat
#' @description LocalStorage senkronizasyonu ve sohbet yükleme observer'larını kurar
#' @param input Shiny input nesnesi
#' @param session Shiny session nesnesi
#' @param output Shiny output nesnesi
#' @param values Ana reaktif değerler
#' @param settings_data Ayarlar modülünden dönen reaktif ayarlar
#' @param chat_rebind_all_charts Grafikleri yeniden bağlama fonksiyonu
storageObserversInit <- function(input, session, output, values, settings_data, 
                                  chat_rebind_all_charts) {
  
 
  # Sekme değişikliğini takip et
  observeEvent(input$last_active_tab, {
    updateTabItems(session, "tabs", selected = input$last_active_tab)
  })
  
  # Mesajlar değiştiğinde localStorage'a kaydet
  observeEvent(values$messages, {
    if (length(values$messages) > 0) {
      session$sendCustomMessage("saveCurrentChat", values$messages)
    }
  }, ignoreNULL = FALSE, ignoreInit = TRUE)
  
  # localStorage'dan sohbet yükle
  observeEvent(input$load_chat_from_storage, {
    loaded_data <- input$load_chat_from_storage
    req(loaded_data)
    if (!is.list(loaded_data) || length(loaded_data) == 0) return(invisible(NULL))
    if (length(values$messages) == 0) {
      
      removeUI(selector = "#chat_content_container > *", multiple = TRUE)
      
      values$messages <- input$load_chat_from_storage
      values$show_welcome <- FALSE
      
      if (length(values$messages) > 0) {
        for (i in seq_along(values$messages)) {
          msg <- values$messages[[i]]
          is_last_user_msg <- (msg$type == "user" && i == length(values$messages))
          
          # Karakter verisini al
          selected_char_id <- isolate(settings_data$selected_character) %||% "mergen"
          chars_data <- get_characters_data()
          character_data <- if (!is.null(chars_data)) {
            Find(function(x) x$id == selected_char_id, chars_data$styles)
          } else NULL
          
          ui_to_insert <- render_message_bubble_ui(
            msg, settings_data,
            is_last_user_message = is_last_user_msg,
            character_data = character_data,
            liked_ids = values$liked_messages,
            disliked_ids = values$disliked_messages
          )
          
          insertUI(selector = "#chat_content_container", where = "beforeEnd", ui = ui_to_insert)
          
          if (isTRUE(msg$has_code)) {
            wrapper_id <- paste0("message_wrapper_", msg$id)
            shinyjs::runjs(sprintf("setTimeout(() => { window.initializeCodeMirrorInElement('%s'); }, 200);", wrapper_id))
          }
        }
        shinyjs::runjs("setTimeout(() => { scrollToBottom(false); }, 100);")
        
        # Geçmiş sohbet yüklendiğinde grafikleri yeniden bağla
        chat_rebind_all_charts(session, output, values$messages)
      }
      
      showToast(session, "Önceki sohbetiniz geri yüklendi.", "info")
    }
  }, ignoreInit = TRUE)
  
  invisible(NULL)
}
# R/server_observers_chat_input.R
# Dosya Yolu: R/server_observers_chat_input.R
# Açıklama: Ana sohbet giriş alanı observer'ları.
# Mesaj gönderme, durdurma butonu, dosya yükleme, sesli giriş ve STT entegrasyonu burada işlenir.

#' Sohbet Giriş Gözlemcilerini Başlat
#' @description Ana sohbet giriş alanı observer'larını kurar
#' @param input Shiny input nesnesi
#' @param session Shiny session nesnesi
#' @param values Ana reaktif değerler
#' @param settings_data Ayarlar modülünden dönen reaktif ayarlar
#' @param stop_generation Durdurma sinyali reaktif değeri
#' @param active_request_id Aktif istek ID reaktif değeri
#' @param reset_chat_state Sohbet durumunu sıfırlama fonksiyonu
#' @param send_message Mesaj gönderme fonksiyonu
#' @param current_user_id Mevcut kullanıcı ID'si
#' @param file_manager_data Dosya yöneticisi modül verisi
#' @param session_files Oturum dosyaları reaktif değeri
#' @param file_to_add Dosya ekleme reaktif değeri
#' @param stt_data STT modül verisi
chatInputObserversInit <- function(input, session, values, settings_data,
                                    stop_generation, active_request_id,
                                    reset_chat_state, send_message,
                                    current_user_id, file_manager_data,
                                    session_files, file_to_add, stt_data) {
  
  observeEvent(input$send_stop_btn, {
    if (isTRUE(values$is_sending) || isTRUE(values$typing)) {
      stop_generation(TRUE)
      active_request_id(paste0("cancelled_", as.integer(Sys.time())))
    }
  }, ignoreInit = TRUE)
  
  observeEvent(input$send_prompt_from_js, {
    req(input$send_prompt_from_js)
    
    if (!check_rate_limit(current_user_id)) {
      showToast(session, "Çok fazla istek gönderdiniz. Lütfen biraz bekleyin.", "warning")
      return()
    }
    
    global_check <- check_global_rate_limit()
    if (!global_check$allowed) {
      showToast(session, global_check$message, "warning")
      return()
    }
    
    user_text <- trimws(input$send_prompt_from_js$text)
    if (nchar(user_text) > 20000) {
      showToast(session, "Mesaj çok uzun. Lütfen 20.000 karakterle sınırlayın.", "warning")
      return()
    }
    
    send_message(input$send_prompt_from_js$text)
  })
  
  observeEvent(stop_generation(), {
    if (isTRUE(stop_generation()) && (isTRUE(values$is_sending) || isTRUE(values$typing))) {
      reset_chat_state()
      showToast(session, "Yanıt oluşturma durduruldu.", "warning")
    }
  }, ignoreInit = TRUE)
  
  observeEvent(input$file_upload, {
    req(input$file_upload)
    handle_file_upload_batch(
      uploads_df           = input$file_upload,
      current_user_id      = current_user_id,
      session              = session,
      settings_data        = settings_data,
      file_manager_data    = file_manager_data,
      session_files_reactive = session_files,
      file_to_add_reactive = file_to_add
    )
  }, ignoreInit = TRUE)
  
  observeEvent(input$voice_btn, {
    stt_data$start_session()
  }, ignoreInit = TRUE)
  
  observeEvent(stt_data$final_text(), {
    txt <- stt_data$final_text()
    if (nzchar(txt)) {
      send_message(txt)
    }
  })
  
  invisible(NULL)
}
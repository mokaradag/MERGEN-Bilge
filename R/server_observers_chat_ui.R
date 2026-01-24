# R/server_observers_chat_ui.R
# Dosya Yolu: R/server_observers_chat_ui.R
# Açıklama: Ana Söyleşi sayfası UI observer'ları.
# Yeni sohbet butonu, takip soruları ve benzeri UI etkileşimleri bu dosyadadır.

#' Sohbet UI Gözlemcilerini Başlat
#' @description Ana Söyleşi sayfasındaki UI observer'larını kurar
#' @param input Shiny input nesnesi
#' @param session Shiny session nesnesi
#' @param values Ana reaktif değerler
#' @param start_new_chat Yeni sohbet başlatma fonksiyonu
#' @param send_message Mesaj gönderme fonksiyonu
#' @param render_welcome_screen Karşılama ekranı render fonksiyonu
chatUIObserversInit <- function(input, session, values, start_new_chat, 
                                 send_message, render_welcome_screen) {
  
  # Yeni sohbet butonu observer'ı
  observeEvent(input$new_chat_btn, {
    # Önce mevcut animasyonları tamamen temizle
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
    ")
    
    start_new_chat()
    session$sendCustomMessage("switchMusicContext", list(type = "genel"))
    
    # Yeni welcome ekranı başlat
    shinyjs::delay(300, {
      render_welcome_screen(values$saved_chats, replace_existing = TRUE)
    })
  }, ignoreInit = TRUE)
  
  # Takip sorusu tıklama observer'ı
  observeEvent(input$followup_question_clicked, {
    req(is.list(input$followup_question_clicked))
    req(nzchar(input$followup_question_clicked$text %||% ""))
    send_message(input$followup_question_clicked)
  }, ignoreInit = TRUE)
  
  invisible(NULL)
}
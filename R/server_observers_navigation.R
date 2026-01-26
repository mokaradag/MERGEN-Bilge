# R/server_observers_navigation.R
# Dosya Yolu: R/server_observers_navigation.R
# Açıklama: Sekme değişikliği ve sayfa geçişleri ile ilgili observer fonksiyonları.
# Tabs observer, CodeMirror yenileme ve sayfa bazlı güncellemeleri yönetir.

#' Navigasyon Gözlemcilerini Başlat
#' @description Sekme/sayfa geçişlerini dinleyen observer'ları kurar
#' @param input Shiny input nesnesi
#' @param session Shiny session nesnesi
#' @param values Ana reaktif değerler
#' @param render_welcome_screen Karşılama ekranı render fonksiyonu
navigationObserversInit <- function(input, session, values, render_welcome_screen) {
  
  observeEvent(input$tabs, {
    
    if (input$tabs == "files") {
      shinyjs::delay(100, {
        shinyjs::runjs("
          document.querySelectorAll('.CodeMirror').forEach(function(cm) {
            if (cm.CodeMirror) {
              cm.CodeMirror.refresh();
            }
          });
        ")
      })
    }
    
    if (input$tabs == "history") {
      shinyjs::runjs(sprintf(
        "Shiny.setInputValue('history_module-external_refresh_trigger', %s, {priority: 'event'});",
        as.numeric(Sys.time())
      ))
    }
    
    if (input$tabs == "chat" && isTRUE(values$show_welcome)) {
      shinyjs::delay(100, {
        render_welcome_screen(values$saved_chats, replace_existing = TRUE)
      })
    }
  })
  
  invisible(NULL)
}
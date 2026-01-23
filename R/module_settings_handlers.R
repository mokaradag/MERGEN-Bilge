# R/module_settings_handlers.R
# Ayarlar modülü için reaktif olay işleyicileri

#' Ayarlar Değişikliklerini İzleyen Sunucu Fonksiyonu
#'
#' @description
#' Bu modül, kullanıcı ayarlarındaki değişiklikleri izler ve
#' UI'yi otomatik olarak günceller.
#'
#' @param id Modül ad alanı kimliği
#' @param settings_data Settings modülünden dönen reaktif değerler
#' @param values Ana server'daki reactiveValues objesi
#' @param session Shiny session objesi
#'
#' @return NULL (Yan etkiler için kullanılır)
#'
#' @export
settingsHandlersServer <- function(id = "settings_handlers", 
                                     settings_data, 
                                     values, 
                                     session) {
  moduleServer(id, function(input, output, session) {
    
    # Zaman damgası gösterimini aç/kapat
    observeEvent(settings_data$enable_timestamps, {
      session$sendCustomMessage("toggleAllTimestamps", 
        list(enabled = settings_data$enable_timestamps))
    }, ignoreNULL = FALSE)
    
    # Font boyutunu güncelle
    observeEvent(settings_data$font_size, {
      values$current_font_size <- settings_data$font_size
      session$sendCustomMessage("updateFontSize", 
        list(size = settings_data$font_size))
    })
    
    # Geniş ekran modunu aç/kapat
    observeEvent(settings_data$enable_widescreen, {
      enabled_val <- isTRUE(settings_data$enable_widescreen)
      session$sendCustomMessage("toggleWidescreen", 
        list(enabled = enabled_val))
    }, ignoreNULL = FALSE, ignoreInit = FALSE)
    
    # Hiçbir şey döndürmeye gerek yok (sadece yan etkiler)
    return(invisible(NULL))
  })
}
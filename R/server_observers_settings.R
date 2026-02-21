# R/server_observers_settings.R
# Dosya Yolu: R/server_observers_settings.R
# Açıklama: Ayarlar modülünden gelen değişikliklere tepki veren observer fonksiyonları.
# Bu dosya server.R'den ayrılarak modülerlik sağlanmıştır.

#' Ayar Gözlemcilerini Başlat
#' @description Ayarlar modülündeki değişiklikleri dinleyen observer'ları kurar
#' @param input Shiny input nesnesi
#' @param session Shiny session nesnesi
#' @param values Ana reaktif değerler
#' @param settings_data Ayarlar modülünden dönen reaktif ayarlar
settingsObserversInit <- function(input, session, values, settings_data) {
  

  # Zaman damgası görünürlüğü değiştiğinde
  observeEvent(settings_data$enable_timestamps, {
    session$sendCustomMessage("toggleAllTimestamps", list(enabled = settings_data$enable_timestamps))
  }, ignoreNULL = FALSE)
  
  # Yazı boyutu değiştiğinde
  observeEvent(settings_data$font_size, {
    values$current_font_size <- settings_data$font_size
    session$sendCustomMessage("updateFontSize", list(size = settings_data$font_size))
  })
  
  # Geniş ekran modu değiştiğinde
  observeEvent(settings_data$enable_widescreen, {
    enabled_val <- isTRUE(settings_data$enable_widescreen)
    session$sendCustomMessage("toggleWidescreen", list(enabled = enabled_val))
  }, ignoreNULL = FALSE, ignoreInit = FALSE)
  
  # Animasyonlar değiştiğinde
  observeEvent(settings_data$enable_animations, {
    shinyjs::toggleClass(
      selector = "body", 
      class = "animations-enabled", 
      condition = settings_data$enable_animations
    )
  }, ignoreNULL = FALSE)
  
  # Karakter değiştiğinde müzik bağlamını güncelle
  observeEvent(settings_data$selected_character, {
    if (isTRUE(settings_data$enable_background_music)) {
      session$sendCustomMessage("switchMusicContext", list(
        type = "karakter",
        character = settings_data$selected_character
      ))
    }
  }, ignoreInit = TRUE)
  
  # Ana sohbette mesaj eklendiğinde müzik modunu güncelle
  observeEvent(length(values$messages), {
    if (isTRUE(settings_data$enable_background_music)) {
      if (length(values$messages) > 0) {
        session$sendCustomMessage("switchMusicContext", list(
          type = "karakter",
          character = settings_data$selected_character %||% "mergen"
        ))
      } else {
        session$sendCustomMessage("switchMusicContext", list(type = "genel"))
      }
    }
  }, ignoreInit = TRUE)
  
  invisible(NULL)
}

#' Görsel Ayarları Senkronizasyonu Başlat (Sohbet → Ayarlar)
#' @description Ana sohbet arayüzündeki görsel ayar değişikliklerini ayarlar modülüne senkronize eder
#' @param input Shiny input nesnesi
#' @param settings_data Ayarlar modülünden dönen reaktif ayarlar
visualSettingsSyncInit <- function(input, settings_data) {
  
  observeEvent(input$chat_image_size, {
    if (!is.null(input$chat_image_size)) {
      settings_data$image_size <- input$chat_image_size
    }
  }, ignoreInit = TRUE)
  
  observeEvent(input$chat_image_quality_hd, {
    settings_data$image_quality_hd <- isTRUE(input$chat_image_quality_hd)
  }, ignoreInit = TRUE)

  # Özetleme ayarları senkronizasyonu (Sohbet → Ayarlar, anlık)
  observeEvent(input$chat_summary_detail, {
    if (!is.null(input$chat_summary_detail)) {
      settings_data$summary_detail_level <- input$chat_summary_detail
    }
  }, ignoreInit = TRUE)

  observeEvent(input$chat_summary_focus, {
    if (!is.null(input$chat_summary_focus)) {
      settings_data$summary_focus_mode <- input$chat_summary_focus
    }
  }, ignoreInit = TRUE)

  # Analiz ayarları senkronizasyonu (Sohbet → Ayarlar, anlık)
  observeEvent(input$chat_deep_thinking, {
    settings_data$analysis_deep_thinking <- isTRUE(input$chat_deep_thinking)
  }, ignoreInit = TRUE)

  observeEvent(input$chat_analysis_detail, {
    if (!is.null(input$chat_analysis_detail)) {
      settings_data$analysis_detail_level <- input$chat_analysis_detail
    }
  }, ignoreInit = TRUE)

  invisible(NULL)
}
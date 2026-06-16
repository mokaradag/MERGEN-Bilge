# ==============================================================================
# R/module_image_generation_ui.R
# Görsel oluşturma UI/HTML render katmanı: ayarlar paneli, sohbet içi kontroller
# ve oluşturulan/kaydedilmiş görsel kartı HTML üreticileri. Çalışma zamanı IO/
# üretim/çeviri yardımcıları R/module_image_generation.R içinde kalır; bu dosya
# yalnızca saf UI/HTML üretir (render_* yardımcıları get_image_web_url ve
# mergen_generated_image_card_html'i çağrı anında çözer).
# ==============================================================================

# ------------------------------------------------------------------------------
# UI YARDIMCI FONKSİYONLARI
# ------------------------------------------------------------------------------

#' Görsel ayarları UI bileşeni (Ayarlar sayfası için)
#' @param ns Namespace fonksiyonu
#' @return Shiny UI tagList
imageSettingsUI <- function(ns) {
 div(
   class = "settings-card image-settings-card",
   id = ns("image_settings_card"),
   h3("Görsel Oluşturma Ayarları", class = "settings-title"),
   p("DALL-E-3 ile görsel oluşturma ayarlarını yapılandırın.", 
     class = "setting-description"),
   
   fluidRow(
     column(
       width = 6,
       div(
         class = "setting-item",
         h4("Görsel Boyutu", class = "setting-subtitle"),
         selectInput(
           inputId = ns("image_size"),
           label = NULL,
           choices = IMAGE_SIZE_OPTIONS,
           selected = "1024x1024",
           width = "100%"
         )
       )
     ),
     column(
       width = 6,
       div(
         class = "setting-item",
         h4("Görsel Kalitesi", class = "setting-subtitle"),
         div(
           class = "quality-switch-container",
           tags$label(
             class = "quality-switch",
             tags$input(
               type = "checkbox",
               id = ns("image_quality_hd"),
               class = "quality-switch-input"
             ),
             tags$span(class = "quality-switch-slider"),
             tags$span(class = "quality-label-sd", "SD"),
             tags$span(class = "quality-label-hd", "HD")
           )
         )
       )
     )
   ),
   
   # Durum göstergesi
   div(
     class = "image-config-status",
     uiOutput(ns("image_config_status"))
   )
 )
}

#' Sohbet içi görsel kontrolleri UI
#' @param ns Namespace fonksiyonu (veya NULL ana UI için)
#' @return Shiny UI div
imageChatControlsUI <- function(ns = NULL) {
 # ns NULL ise identity fonksiyonu kullan
 ns_fn <- if (is.null(ns)) identity else ns
 
 div(
   id = "image_chat_controls",
   class = "image-chat-controls hidden",
   
   # Boyut dropdown
   div(
     class = "image-control-item",
     tags$select(
       id = ns_fn("chat_image_size"),
       class = "image-size-select",
       tags$option(value = "1024x1024", "Kare"),
       tags$option(value = "1792x1024", "Yatay"),
       tags$option(value = "1024x1792", "Dikey")
     )
   ),
   
   # Kalite switch
   div(
     class = "image-control-item",
     tags$label(
       class = "quality-mini-switch",
       title = "HD Kalite",
       tags$input(
         type = "checkbox",
         id = ns_fn("chat_image_quality_hd"),
         class = "quality-mini-input"
       ),
       tags$span(class = "quality-mini-slider"),
       tags$span(class = "quality-mini-label", "HD")
     )
   )
 )
}

#' Oluşturulan görsel için mesaj HTML'i
#' @param image_result generate_image() fonksiyonunun döndürdüğü sonuç
#' @param message_id Mesaj ID
#' @return HTML string
render_generated_image_html <- function(image_result, message_id) {
 if (!isTRUE(image_result$success)) {
   return(sprintf(
     '<div class="image-error-container">
        <i class="fas fa-exclamation-triangle"></i>
        <p>Görsel oluşturulamadı: %s</p>
      </div>',
     htmltools::htmlEscape(image_result$error %||% "Bilinmeyen hata")
   ))
 }
 
 # Görsel URL'sini belirle (yerel veya uzak)
 img_src <- if (!is.null(image_result$local_path) && file.exists(image_result$local_path)) {
   get_image_web_url(image_result$local_path)
 } else {
   image_result$image_url
 }

 # Kart işaretlemesi kanonik güvenli yardımcıdan üretilir (XSS sınırı tek yerde).
 mergen_generated_image_card_html(
   message_id = message_id,
   img_src = img_src,
   description = image_result$revised_prompt
 )
}

#' Kaydedilmiş görsel yolundan HTML oluştur (önceki sohbetleri yüklerken kullanılır)
#' @param image_path Yerel görsel dosyasının tam yolu
#' @param description Görsel açıklaması
#' @param message_id Mesaj ID
#' @return HTML string veya NULL (dosya bulunamazsa)
render_image_from_saved_path <- function(image_path, description, message_id) {
  # Boş yol kontrolü
  if (is.null(image_path) || !nzchar(image_path)) {
    cat("[IMAGE_GEN] Görsel yolu boş veya NULL\n")
    return(NULL)
  }

  # Dosya yolu çözümleme: önce doğrudan, sonra user_images göreli yol dene
  resolved_path <- image_path

  if (!file.exists(resolved_path)) {
    # user_images/ klasörünü içeren göreli yolu çıkarmayı dene
    # Örn: /eski/yol/user_images/1/123/resim.png -> user_images/1/123/resim.png
    user_images_match <- regmatches(image_path, regexec("(user_images/.+)$", image_path))[[1]]

    if (length(user_images_match) >= 2) {
      relative_path <- user_images_match[2]
      candidate_path <- file.path(getwd(), relative_path)

      if (file.exists(candidate_path)) {
        cat("[IMAGE_GEN] Görsel göreli yol ile bulundu:", candidate_path, "\n")
        resolved_path <- candidate_path
      }
    }
  }

  # Son kontrol: dosya hala bulunamadıysa NULL döndür
  if (!file.exists(resolved_path)) {
    cat("[IMAGE_GEN] Kaydedilmiş görsel bulunamadı:", image_path, "\n")
    cat("[IMAGE_GEN] Denenen çözümlenmiş yol:", resolved_path, "\n")
    return(NULL)
  }

  tryCatch({
    # Görseli base64'e çevir (çözümlenmiş yolu kullan)
    img_src <- get_image_web_url(resolved_path)

    # Kart işaretlemesi kanonik güvenli yardımcıdan üretilir (XSS sınırı tek yerde).
    mergen_generated_image_card_html(
      message_id = message_id,
      img_src = img_src,
      description = description
    )
  }, error = function(e) {
    cat("[IMAGE_GEN] Görsel HTML oluşturma hatası:", e$message, "\n")
    NULL
  })
}

# ==============================================================================
# R/module_image_generation.R
# Görsel oluşturma modülü - DALL-E-3 API entegrasyonu
# Türkçe prompt çevirisi, görsel oluşturma ve depolama işlemlerini yönetir
# ==============================================================================

# ------------------------------------------------------------------------------
# YAPILANDIRMA
# ------------------------------------------------------------------------------

# Görsel oluşturma yapılandırmasını yükle
image_gen_config <- list(
 endpoint = Sys.getenv("IMAGE_GEN_ENDPOINT", ""),
 model = Sys.getenv("IMAGE_GEN_MODEL", "dall-e-3"),
 translation_model = Sys.getenv("TRANSLATION_MODEL", ""),
 timeout = as.numeric(Sys.getenv("IMAGE_GEN_TIMEOUT", "180"))
)

# Görsel boyutu seçenekleri (Türkçe etiketler)
IMAGE_SIZE_OPTIONS <- c(
 "Kare (1024x1024)" = "1024x1024",
 "Yatay (1792x1024)" = "1792x1024",
 "Dikey (1024x1792)" = "1024x1792"
)

# Kalite seçenekleri
IMAGE_QUALITY_OPTIONS <- c(
 "standard" = "Standart",
 "hd" = "HD (Yüksek Detay)"
)

# ------------------------------------------------------------------------------
# GÖRSEL DEPOLAMA DİZİNİ
# ------------------------------------------------------------------------------

#' Kullanıcı görsel dizinini oluştur/al
#' @param user_id Kullanıcı ID
#' @param chat_id Sohbet ID (opsiyonel)
#' @return Dizin yolu
get_user_image_dir <- function(user_id, chat_id = NULL) {
 base_dir <- file.path(getwd(), "user_images", as.character(user_id))
 
 if (!is.null(chat_id)) {
   base_dir <- file.path(base_dir, as.character(chat_id))
 }
 
 if (!dir.exists(base_dir)) {
   dir.create(base_dir, recursive = TRUE, showWarnings = FALSE)
 }
 
 return(base_dir)
}

# ------------------------------------------------------------------------------
# TÜRKÇE -> İNGİLİZCE ÇEVİRİ
# ------------------------------------------------------------------------------

#' Türkçe promptu İngilizceye çevir
#' @param turkish_prompt Türkçe prompt metni
#' @param api_key API anahtarı
#' @return İngilizce çeviri veya orijinal metin (hata durumunda)
translate_prompt_to_english <- function(turkish_prompt, api_key) {
 # Çeviri modeli yapılandırılmamışsa orijinal metni döndür
 translation_model <- image_gen_config$translation_model
 if (!nzchar(translation_model)) {
   cat("[IMAGE_GEN] Çeviri modeli yapılandırılmamış, orijinal prompt kullanılıyor\n")
   return(turkish_prompt)
 }
 
 # Basit Türkçe tespiti - İngilizce ise çevirme
 turkish_chars <- grepl("[ğüşıöçĞÜŞİÖÇ]", turkish_prompt)
 turkish_words <- grepl("\\b(ve|ile|için|bir|bu|olan|gibi|kadar|daha|çok|nasıl|neden|ama|fakat|ancak)\\b", 
                        turkish_prompt, ignore.case = TRUE)
 
 if (!turkish_chars && !turkish_words) {
   cat("[IMAGE_GEN] Prompt zaten İngilizce görünüyor, çeviri atlanıyor\n")
   return(turkish_prompt)
 }
 
 cat("[IMAGE_GEN] Türkçe prompt tespit edildi, çeviriliyor...\n")
 
 # Çeviri endpoint'ini al
 translation_endpoint <- resolve_local_llm_endpoint(translation_model)
 
 tryCatch({
   translation_messages <- list(
     list(
       role = "system",
       content = paste0(
         "You are a translator. Translate the following Turkish text to English. ",
         "This text will be used as a prompt for DALL-E image generation. ",
         "Keep the artistic and descriptive elements intact. ",
         "Only respond with the English translation, nothing else."
       )
     ),
     list(
       role = "user",
       content = turkish_prompt
     )
   )
   
   body <- list(
     model = translation_model,
     messages = translation_messages,
     temperature = 0.3,
     max_tokens = 500
   )
   
   response <- httr::POST(
     url = translation_endpoint,
     httr::add_headers(
       "Authorization" = paste("Bearer", api_key),
       "Content-Type" = "application/json"
     ),
     body = jsonlite::toJSON(body, auto_unbox = TRUE),
     encode = "raw",
     httr::timeout(30)
   )
   
   if (httr::status_code(response) == 200) {
     result <- httr::content(response, "parsed")
     translated <- result$choices[[1]]$message$content
     cat("[IMAGE_GEN] Çeviri başarılı:", substr(translated, 1, 100), "...\n")
     return(trimws(translated))
   } else {
     cat("[IMAGE_GEN] Çeviri hatası, orijinal prompt kullanılıyor\n")
     return(turkish_prompt)
   }
 }, error = function(e) {
   cat("[IMAGE_GEN] Çeviri exception:", e$message, "\n")
   return(turkish_prompt)
 })
}

# ------------------------------------------------------------------------------
# İNGİLİZCE -> TÜRKÇE ÇEVİRİ (DALL-E YORUMU İÇİN)
# ------------------------------------------------------------------------------

#' DALL-E yorumunu detaylı bir açıklamaya dönüştür ve Türkçeye çevir
#' @param english_text İngilizce metin (DALL-E revised_prompt)
#' @param original_prompt Kullanıcının orijinal promptu
#' @param api_key API anahtarı
#' @return Detaylı Türkçe açıklama veya orijinal metin (hata durumunda)
translate_revised_prompt_to_turkish <- function(english_text, api_key, original_prompt = NULL) {
  # Çeviri modeli yapılandırılmamışsa orijinal metni döndür
  translation_model <- image_gen_config$translation_model
  if (!nzchar(translation_model)) {
    return(english_text)
  }
 
  translation_endpoint <- resolve_local_llm_endpoint(translation_model)
 
  tryCatch({
    # Kullanıcının orijinal dilini tespit et
    is_turkish_original <- FALSE
    if (!is.null(original_prompt) && nzchar(original_prompt)) {
      turkish_chars <- grepl("[ğüşıöçĞÜŞİÖÇ]", original_prompt)
      turkish_words <- grepl("\\b(ve|ile|için|bir|bu|olan|gibi|kadar|daha|çok|nasıl|neden|ama|fakat|ancak)\\b",
                             original_prompt, ignore.case = TRUE)
      is_turkish_original <- turkish_chars || turkish_words
    }
 
    # Detaylı açıklama oluşturma promptu
    system_prompt <- if (is_turkish_original) {
      paste0(
        "Sen bir sanat eleştirmenisin. Aşağıda DALL-E'nin oluşturduğu görselin açıklaması var. ",
        "Bu açıklamayı kullanarak, oluşturulan görsel hakkında TÜRKÇE olarak kısa ama detaylı ",
        "bir yorum yaz. Yorumunda şunlara değin:\n",
        "- Görselin ana öğeleri ve kompozisyonu\n",
        "- Kullanılan renkler ve atmosfer\n",
        "- Sanatsal stil ve teknik\n\n",
        "Yanıtını 2-3 cümle ile sınırlı tut. Sadece Türkçe yorum yaz, başka bir şey ekleme."
      )
    } else {
      paste0(
        "You are an art critic. Below is the description of an image generated by DALL-E. ",
        "Write a brief but detailed comment about the generated image. Include:\n",
        "- Main elements and composition\n",
        "- Colors and atmosphere\n",
        "- Artistic style and technique\n\n",
        "Keep your response to 2-3 sentences. Only write the comment, nothing else."
      )
    }
 
    translation_messages <- list(
      list(
        role = "system",
        content = system_prompt
      ),
      list(
        role = "user",
        content = english_text
      )
    )
 
    body <- list(
      model = translation_model,
      messages = translation_messages,
      temperature = 0.5,
      max_tokens = 300
    )
 
    response <- httr::POST(
      url = translation_endpoint,
      httr::add_headers(
        "Authorization" = paste("Bearer", api_key),
        "Content-Type" = "application/json"
      ),
      body = jsonlite::toJSON(body, auto_unbox = TRUE),
      encode = "raw",
      httr::timeout(30)
    )
 
    if (httr::status_code(response) == 200) {
      result <- httr::content(response, "parsed")
      translated <- result$choices[[1]]$message$content
      return(trimws(translated))
    } else {
      # Hata durumunda basit çeviri dene
      return(english_text)
    }
  }, error = function(e) {
    cat("[IMAGE_GEN] Açıklama oluşturma hatası:", e$message, "\n")
    return(english_text)
  })
}

# ------------------------------------------------------------------------------
# GÖRSEL OLUŞTURMA
# ------------------------------------------------------------------------------

#' DALL-E-3 ile görsel oluştur
#' @param prompt Görsel açıklaması (Türkçe veya İngilizce)
#' @param api_key API anahtarı
#' @param size Görsel boyutu (1024x1024, 1792x1024, 1024x1792)
#' @param quality Kalite (standard, hd)
#' @param user_id Kullanıcı ID (depolama için)
#' @param chat_id Sohbet ID (depolama için)
#' @return Liste: success, image_url, local_path, revised_prompt, error
generate_image <- function(prompt, api_key, size = "1024x1024", quality = "standard",
                          user_id = NULL, chat_id = NULL) {
 
 # Yapılandırma kontrolü
 if (!nzchar(image_gen_config$endpoint)) {
   return(list(
     success = FALSE,
     error = "Görsel oluşturma endpoint'i yapılandırılmamış. .Renviron dosyasını kontrol edin."
   ))
 }
 
 if (!nzchar(api_key)) {
   return(list(
     success = FALSE,
     error = "API anahtarı gerekli. Lütfen Ayarlar sayfasından API anahtarınızı girin."
   ))
 }
 
 # Türkçe promptu İngilizceye çevir
 english_prompt <- translate_prompt_to_english(prompt, api_key)
 
 # Çevrilen prompt'u direkt kullan (görsel içine imza ekleme - HTML watermark kullanılacak)
 final_prompt <- english_prompt
 
 cat(sprintf("[IMAGE_GEN] Görsel oluşturuluyor: size=%s, quality=%s\n", size, quality))
 cat(sprintf("[IMAGE_GEN] Final prompt: %s\n", substr(final_prompt, 1, 200)))
 
 tryCatch({
   body <- list(
     model = image_gen_config$model,
     prompt = final_prompt,
     n = 1,
     size = size,
     quality = quality
   )
   
   response <- httr::POST(
     url = image_gen_config$endpoint,
     httr::add_headers(
       "Authorization" = paste("Bearer", api_key),
       "Content-Type" = "application/json"
     ),
     body = jsonlite::toJSON(body, auto_unbox = TRUE),
     encode = "raw",
     httr::timeout(image_gen_config$timeout)
   )
   
   status <- httr::status_code(response)
   
   if (status != 200) {
     error_content <- httr::content(response, "text", encoding = "UTF-8")
     cat("[IMAGE_GEN] API hatası:", status, "-", error_content, "\n")
     return(list(
       success = FALSE,
       error = paste("API Hatası (", status, "): ", 
                    tryCatch(jsonlite::fromJSON(error_content)$error$message, 
                            error = function(e) error_content))
     ))
   }
   
   result <- httr::content(response, "parsed")
   
   if (!is.null(result$data) && length(result$data) > 0) {
     image_url <- result$data[[1]]$url
     revised_prompt <- result$data[[1]]$revised_prompt
     
     cat("[IMAGE_GEN] DALL-E API başarılı, görsel URL alındı\n")
 
     # Görseli yerel olarak kaydet
     local_path <- NULL
     if (!is.null(user_id)) {
       local_path <- save_image_locally(image_url, user_id, chat_id)
       if (is.null(local_path)) {
         cat("[IMAGE_GEN] UYARI: Görsel yerel olarak kaydedilemedi, URL kullanılacak\n")
       }
     }
 
    # DALL-E yorumunu detaylı açıklamaya dönüştür ve kullanıcının diline çevir
    translated_revised_prompt <- NULL
    if (!is.null(revised_prompt) && nzchar(revised_prompt)) {
      # Detaylı açıklama oluştur (orijinal prompt'u da geçir dil tespiti için)
      translated_revised_prompt <- translate_revised_prompt_to_turkish(
        revised_prompt,
        api_key,
        original_prompt = prompt
      )
    }
 
    cat("[IMAGE_GEN] Görsel başarıyla oluşturuldu\n")
    
    return(list(
      success = TRUE,
      image_url = image_url,
      local_path = local_path,
      revised_prompt = translated_revised_prompt,
      original_prompt = prompt,
      translated_prompt = english_prompt
    ))
   } else {
     return(list(
       success = FALSE,
       error = "API yanıtında görsel verisi bulunamadı"
     ))
   }
   
 }, error = function(e) {
   cat("[IMAGE_GEN] Exception:", e$message, "\n")
   return(list(
     success = FALSE,
     error = paste("Bağlantı hatası:", e$message)
   ))
 })
}

# ------------------------------------------------------------------------------
# GÖRSEL DEPOLAMA
# ------------------------------------------------------------------------------

#' Görseli URL'den indirip yerel olarak kaydet
#' @param image_url Görsel URL'si
#' @param user_id Kullanıcı ID
#' @param chat_id Sohbet ID
#' @return Yerel dosya yolu veya NULL
save_image_locally <- function(image_url, user_id, chat_id = NULL) {
  tryCatch({
    # URL kontrolü
    if (is.null(image_url) || !nzchar(image_url)) {
      cat("[IMAGE_GEN] Görsel URL'si boş veya geçersiz\n")
      return(NULL)
    }

    cat("[IMAGE_GEN] İndirilecek görsel URL'si:", substr(image_url, 1, 100), "...\n")

    # Dizini oluştur
    save_dir <- get_user_image_dir(user_id, chat_id)

    # Dizin oluşturulabildi mi kontrol et
    if (!dir.exists(save_dir)) {
      cat("[IMAGE_GEN] Dizin oluşturulamadı:", save_dir, "\n")
      return(NULL)
    }

    # Benzersiz dosya adı oluştur
    timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
    random_suffix <- paste0(sample(letters, 4), collapse = "")
    filename <- sprintf("dalle_%s_%s.png", timestamp, random_suffix)

    # Windows için forward slash kullan ve normalize et
    local_path <- file.path(save_dir, filename)
    local_path <- gsub("\\\\", "/", local_path)

    cat("[IMAGE_GEN] Görsel kaydedilmeye çalışılıyor:", local_path, "\n")

    # Base64 data URL kontrolü - download.file ve httr::GET bu formatı desteklemez
    if (grepl("^data:image/", image_url)) {
      cat("[IMAGE_GEN] Base64 data URL tespit edildi, doğrudan decode ediliyor...\n")
      
      tryCatch({
        # data:image/png;base64,... formatından base64 kısmını çıkar
        base64_data <- sub("^data:image/[^;]+;base64,", "", image_url)
        
        # Base64 decode et
        img_raw <- base64enc::base64decode(base64_data)
        
        if (length(img_raw) == 0) {
          cat("[IMAGE_GEN] Base64 decode sonucu boş\n")
          return(NULL)
        }
        
        cat("[IMAGE_GEN] Base64 decode başarılı, boyut:", length(img_raw), "byte\n")
        
        # Binary olarak dosyaya yaz
        con <- file(local_path, "wb")
        writeBin(img_raw, con)
        close(con)
        
        if (file.exists(local_path) && file.info(local_path)$size > 0) {
          cat("[IMAGE_GEN] Görsel başarıyla kaydedildi (base64):", local_path, "\n")
          return(local_path)
        } else {
          cat("[IMAGE_GEN] Base64 dosya oluşturuldu ama boş\n")
          return(NULL)
        }
      }, error = function(e) {
        cat("[IMAGE_GEN] Base64 kaydetme hatası:", e$message, "\n")
        return(NULL)
      })
    }

    # HTTP/HTTPS URL için normal indirme işlemi
    cat("[IMAGE_GEN] HTTP yanıtı alınıyor...\n")
    
    response <- tryCatch({
      httr::GET(
        image_url,
        httr::timeout(120),
        httr::config(
          ssl_verifypeer = TRUE,
          followlocation = TRUE,
          proxy = ""
        ),
        httr::user_agent("MERGEN-Bilge/1.0")
      )
    }, error = function(e) {
      cat("[IMAGE_GEN] HTTP GET hatası:", e$message, "\n")
      cat("[IMAGE_GEN] Alternatif indirme yöntemi deneniyor...\n")
      tryCatch({
        temp_file <- tempfile(fileext = ".png")
        download.file(image_url, temp_file, mode = "wb", quiet = TRUE, method = "auto")
        if (file.exists(temp_file) && file.info(temp_file)$size > 0) {
          return(list(status_code = 200, temp_file = temp_file))
        }
        return(NULL)
      }, error = function(e2) {
        cat("[IMAGE_GEN] Alternatif indirme de başarısız:", e2$message, "\n")
        return(NULL)
      })
    })

    # Alternatif yöntem kullanıldıysa
    if (is.list(response) && !is.null(response$temp_file)) {
      tryCatch({
        file.copy(response$temp_file, local_path, overwrite = TRUE)
        unlink(response$temp_file)
        if (file.exists(local_path) && file.info(local_path)$size > 0) {
          cat("[IMAGE_GEN] Görsel başarıyla kaydedildi (alternatif):", local_path, "\n")
          return(local_path)
        }
      }, error = function(e) {
        cat("[IMAGE_GEN] Alternatif kaydetme hatası:", e$message, "\n")
      })
      return(NULL)
    }

    # Normal httr response kontrolü
    if (is.null(response) || !inherits(response, "response")) {
      cat("[IMAGE_GEN] HTTP yanıtı alınamadı\n")
      return(NULL)
    }

    if (httr::status_code(response) != 200) {
      cat("[IMAGE_GEN] HTTP status:", httr::status_code(response), "\n")
      return(NULL)
    }

    # İçeriği al
    img_content <- httr::content(response, "raw")

    if (length(img_content) == 0) {
      cat("[IMAGE_GEN] Görsel içeriği boş\n")
      return(NULL)
    }

    cat("[IMAGE_GEN] Görsel içeriği alındı, boyut:", length(img_content), "byte\n")

    # Binary olarak dosyaya yaz
    tryCatch({
      con <- file(local_path, "wb")
      writeBin(img_content, con)
      close(con)

      if (file.exists(local_path) && file.info(local_path)$size > 0) {
        cat("[IMAGE_GEN] Görsel başarıyla kaydedildi:", local_path, "\n")
        return(local_path)
      } else {
        cat("[IMAGE_GEN] Dosya oluşturuldu ama boş\n")
        return(NULL)
      }
    }, error = function(write_err) {
      cat("[IMAGE_GEN] Dosya yazma hatası:", write_err$message, "\n")
      return(NULL)
    })

    return(NULL)
  }, error = function(e) {
    cat("[IMAGE_GEN] Genel hata:", e$message, "\n")
    return(NULL)
  })
}

#' Kaydedilmiş görseli web erişilebilir URL'ye dönüştür
#' @param local_path Yerel dosya yolu
#' @return Web URL'si
get_image_web_url <- function(local_path) {
 if (is.null(local_path) || !file.exists(local_path)) {
   return(NULL)
 }
 
 # Göreli yolu hesapla (www klasörüne göre)
 # user_images klasörü www altında değilse, farklı bir yöntem kullanılmalı
 # Burada doğrudan base64 encoding kullanacağız
 
 tryCatch({
   img_data <- base64enc::base64encode(local_path)
   paste0("data:image/png;base64,", img_data)
 }, error = function(e) {
   NULL
 })
}

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
 
  sprintf(
    '<div class="generated-image-container" data-message-id="%s">
       <div class="image-wrapper">
         <img src="%s" alt="Oluşturulan görsel" class="generated-image" loading="lazy" />
         <div class="image-watermark">MERGEN Bilge</div>
       </div>
       <div class="image-actions">
         <button class="image-action-btn-modern" onclick="window.downloadGeneratedImage(this)" title="İndir">
           <i class="fas fa-download"></i>
         </button>
         <button class="image-action-btn-modern" onclick="window.copyGeneratedImage(this)" title="Kopyala">
           <i class="fas fa-copy"></i>
         </button>
         <button class="image-action-btn-modern" onclick="window.printGeneratedImage(this)" title="Yazdır">
           <i class="fas fa-print"></i>
         </button>
       </div>
       %s
     </div>',
    message_id,
    img_src,
    if (!is.null(image_result$revised_prompt) && nzchar(image_result$revised_prompt)) {
      sprintf('<div class="image-description"><p>%s</p></div>',
              htmltools::htmlEscape(image_result$revised_prompt))
    } else ""
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

    # HTML oluştur
    sprintf(
      '<div class="generated-image-container" data-message-id="%s">
         <div class="image-wrapper">
           <img src="%s" alt="Oluşturulan görsel" class="generated-image" loading="lazy" />
           <div class="image-watermark">MERGEN Bilge</div>
         </div>
         <div class="image-actions">
           <button class="image-action-btn-modern" onclick="window.downloadGeneratedImage(this)" title="İndir">
             <i class="fas fa-download"></i>
           </button>
           <button class="image-action-btn-modern" onclick="window.copyGeneratedImage(this)" title="Kopyala">
             <i class="fas fa-copy"></i>
           </button>
           <button class="image-action-btn-modern" onclick="window.printGeneratedImage(this)" title="Yazdır">
             <i class="fas fa-print"></i>
           </button>
         </div>
         %s
       </div>',
      message_id,
      img_src,
      if (!is.null(description) && nzchar(description)) {
        sprintf('<div class="image-description"><p>%s</p></div>',
                htmltools::htmlEscape(description))
      } else ""
    )
  }, error = function(e) {
    cat("[IMAGE_GEN] Görsel HTML oluşturma hatası:", e$message, "\n")
    NULL
  })
}
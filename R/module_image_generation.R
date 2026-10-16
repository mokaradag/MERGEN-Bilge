# ==============================================================================
# R/module_image_generation.R
# Görsel oluşturma modülü - yapılandırılabilir görsel API entegrasyonu
# Türkçe prompt çevirisi, görsel oluşturma ve depolama işlemlerini yönetir
# ==============================================================================

# ------------------------------------------------------------------------------
# YAPILANDIRMA
# ------------------------------------------------------------------------------

# Görsel oluşturma yapılandırmasını yükle
image_gen_config <- list(
 endpoint = Sys.getenv("IMAGE_GEN_ENDPOINT", ""),
 model = Sys.getenv("IMAGE_GEN_MODEL", "FLUX.2-dev"),
 translation_model = Sys.getenv("TRANSLATION_MODEL", ""),
 timeout = as.numeric(Sys.getenv("IMAGE_GEN_TIMEOUT", "180"))
)

# Base64 yanıtlarına 32 MiB decoded ve karşılık gelen encoded sınır uygulanır.
IMAGE_GEN_MAX_DECODED_BYTES <- 32 * 1024^2
IMAGE_GEN_MAX_BASE64_ENCODED_BYTES <- ceiling(IMAGE_GEN_MAX_DECODED_BYTES * 4 / 3) + 4

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
         "This text will be used as a prompt for image generation. ",
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
# İNGİLİZCE -> TÜRKÇE ÇEVİRİ (GÖRSEL AÇIKLAMASI İÇİN)
# ------------------------------------------------------------------------------

#' Görsel yorumunu detaylı bir açıklamaya dönüştür ve Türkçeye çevir
#' @param english_text İngilizce metin (isteğe bağlı revised_prompt)
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
        "Sen bir sanat eleştirmenisin. Aşağıda oluşturulan görselin açıklaması var. ",
        "Bu açıklamayı kullanarak, oluşturulan görsel hakkında TÜRKÇE olarak kısa ama detaylı ",
        "bir yorum yaz. Yorumunda şunlara değin:\n",
        "- Görselin ana öğeleri ve kompozisyonu\n",
        "- Kullanılan renkler ve atmosfer\n",
        "- Sanatsal stil ve teknik\n\n",
        "Yanıtını 2-3 cümle ile sınırlı tut. Sadece Türkçe yorum yaz, başka bir şey ekleme."
      )
    } else {
      paste0(
        "You are an art critic. Below is the description of a generated image. ",
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

#' Yapılandırılan model ile görsel oluştur
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
   if (is.list(result$data) && length(result$data) > 0 && is.list(result$data[[1]])) {
     image_data <- result$data[[1]]
     valid_scalar_text <- function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
     image_url <- image_data$url
     is_base64 <- FALSE
     if (!valid_scalar_text(image_url)) {
       base64_data <- image_data$b64_json
       if (!valid_scalar_text(base64_data)) return(list(success = FALSE, error = "API yanıtında görsel verisi bulunamadı"))
       if (nchar(base64_data, type = "bytes") > IMAGE_GEN_MAX_BASE64_ENCODED_BYTES) {
         return(list(success = FALSE, error = "API yanıtındaki görsel verisi izin verilen boyutu aşıyor"))
       }
       base64_mime <- if (startsWith(base64_data, "/9j/")) "jpeg" else if (startsWith(base64_data, "R0lGOD")) "gif" else if (startsWith(base64_data, "UklGR")) "webp" else "png"
       image_url <- paste0("data:image/", base64_mime, ";base64,", base64_data)
       is_base64 <- TRUE
     }
     revised_prompt <- image_data$revised_prompt
     if (!valid_scalar_text(revised_prompt)) revised_prompt <- NULL
     cat("[IMAGE_GEN] Görsel API yanıtı başarılı\n")
     local_path <- NULL
     if (!is.null(user_id)) {
       local_path <- save_image_locally(image_url, user_id, chat_id)
       if (is.null(local_path)) {
         if (is_base64) return(list(success = FALSE, error = "Görsel verisi yerel olarak kaydedilemedi"))
         cat("[IMAGE_GEN] UYARI: Görsel yerel olarak kaydedilemedi, URL kullanılacak\n")
       } else if (is_base64) image_url <- NULL
     }
     translated_revised_prompt <- NULL
     if (!is.null(revised_prompt)) {
       translated_revised_prompt <- translate_revised_prompt_to_turkish(
         revised_prompt, api_key, original_prompt = prompt
       )
     }
     cat("[IMAGE_GEN] Görsel başarıyla oluşturuldu\n")
     return(list(
       success = TRUE, image_url = image_url, local_path = local_path,
       revised_prompt = translated_revised_prompt, original_prompt = prompt,
       translated_prompt = english_prompt
     ))
   }
   return(list(success = FALSE, error = "API yanıtında görsel verisi bulunamadı"))
 }, error = function(e) {
   cat("[IMAGE_GEN] Exception:", e$message, "\n")
   return(list(success = FALSE, error = paste("Bağlantı hatası:", e$message)))
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
    if (is.null(image_url) || !nzchar(image_url)) {
      cat("[IMAGE_GEN] Görsel URL'si boş veya geçersiz\n")
      return(NULL)
    }
    is_data_url <- grepl("^data:image/", image_url, ignore.case = TRUE)
    if (!is_data_url) {
      cat("[IMAGE_GEN] İndirilecek görsel URL'si:", substr(image_url, 1, 100), "...\n")
    }
    save_dir <- get_user_image_dir(user_id, chat_id)
    if (!dir.exists(save_dir)) {
      cat("[IMAGE_GEN] Dizin oluşturulamadı:", save_dir, "\n")
      return(NULL)
    }
    data_mime <- NULL
    file_ext <- ".png"
    if (is_data_url) {
      data_header <- sub(",.*$", "", image_url)
      if (!grepl("^data:image/[^;]+(;[^;,=]+=[^;,]*)*;base64$", data_header, ignore.case = TRUE)) {
        cat("[IMAGE_GEN] Base64 kayıt hatası: data-url\n"); return(NULL)
      }
      data_mime <- tolower(sub("^data:image/([^;]+);.*$", "\\1", data_header, ignore.case = TRUE))
      if (identical(data_mime, "jpg")) data_mime <- "jpeg"
      file_ext <- switch(data_mime, png = ".png", jpeg = ".jpg", gif = ".gif", webp = ".webp", NULL)
      if (is.null(file_ext)) { cat("[IMAGE_GEN] Base64 kayıt hatası: mime\n"); return(NULL) }
    }
    filename <- basename(tempfile(
      pattern = paste0("dalle_", format(Sys.time(), "%Y%m%d_%H%M%S"), "_"),
      tmpdir = save_dir, fileext = file_ext
    ))
    local_path <- gsub("\\\\", "/", file.path(save_dir, filename))
    cat("[IMAGE_GEN] Görsel kaydedilmeye çalışılıyor:", local_path, "\n")
    if (is_data_url) {
      base64_data <- sub("^[^,]+,", "", image_url)
      if (nchar(base64_data, type = "bytes") > IMAGE_GEN_MAX_BASE64_ENCODED_BYTES) {
        cat("[IMAGE_GEN] Base64 kayıt hatası: encoded-size\n"); return(NULL)
      }
      img_raw <- try(base64enc::base64decode(base64_data), silent = TRUE)
      if (inherits(img_raw, "try-error") || !length(img_raw)) {
        cat("[IMAGE_GEN] Base64 kayıt hatası: decode\n"); return(NULL)
      }
      if (length(img_raw) > IMAGE_GEN_MAX_DECODED_BYTES) {
        cat("[IMAGE_GEN] Base64 kayıt hatası: decoded-size\n"); return(NULL)
      }
      raw_len <- length(img_raw)
      iend_at <- if (identical(data_mime, "png")) grepRaw(as.raw(c(0, 0, 0, 0, 0x49, 0x45, 0x4e, 0x44)), img_raw, fixed = TRUE, all = TRUE) else integer()
      jpeg_scan <- if (identical(data_mime, "jpeg")) grepRaw(as.raw(c(0xff, 0xda)), img_raw, fixed = TRUE) else integer()
      gif_frame <- if (identical(data_mime, "gif")) grepRaw(as.raw(0x2c), img_raw, offset = 14L, fixed = TRUE) else integer()
      format_ok <- switch(data_mime,
        png = raw_len >= 45L &&
          identical(img_raw[1:8], as.raw(c(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a))) &&
          identical(img_raw[9:12], as.raw(c(0, 0, 0, 13))) &&
          identical(rawToChar(img_raw[13:16]), "IHDR") &&
          length(iend_at) > 0L && any(iend_at + 11L <= raw_len),
        jpeg = raw_len >= 32L && identical(img_raw[1:2], as.raw(c(0xff, 0xd8))) &&
          length(jpeg_scan) > 0L && jpeg_scan > 2L &&
          any(vapply(c(0xc0:0xc3, 0xc5:0xc7, 0xc9:0xcb, 0xcd:0xcf), function(marker)
            any(grepRaw(as.raw(c(0xff, marker)), img_raw, fixed = TRUE, all = TRUE) < jpeg_scan - 8L), logical(1))) &&
          any(grepRaw(as.raw(c(0xff, 0xd9)), img_raw, fixed = TRUE, all = TRUE) > jpeg_scan + 8L),
        gif = raw_len >= 29L && rawToChar(img_raw[1:6]) %in% c("GIF87a", "GIF89a") &&
          any(img_raw[7:8] != as.raw(0)) && any(img_raw[9:10] != as.raw(0)) &&
          length(gif_frame) > 0L && gif_frame > 13L &&
          any(grepRaw(as.raw(c(0, 0x3b)), img_raw, fixed = TRUE, all = TRUE) > gif_frame + 11L),
        webp = raw_len >= 26L && identical(rawToChar(img_raw[1:4]), "RIFF") &&
          identical(rawToChar(img_raw[9:12]), "WEBP") &&
          rawToChar(img_raw[13:16]) %in% c("VP8 ", "VP8L", "VP8X") &&
          sum(as.integer(img_raw[5:8]) * 256^(0:3)) + 8 <= raw_len &&
          sum(as.integer(img_raw[17:20]) * 256^(0:3)) > 0 && sum(as.integer(img_raw[17:20]) * 256^(0:3)) <= raw_len - 20L,
        FALSE
      )
      if (!isTRUE(format_ok)) { cat("[IMAGE_GEN] Base64 kayıt hatası: validate-", data_mime, "\n", sep = ""); return(NULL) }
      temp_path <- tempfile(pattern = ".mergen-image-", tmpdir = save_dir, fileext = ".tmp")
      con <- try(file(temp_path, "wb"), silent = TRUE)
      if (inherits(con, "try-error")) { cat("[IMAGE_GEN] Base64 kayıt hatası: file-open\n"); return(NULL) }
      closed <- FALSE
      on.exit({
        if (!closed) {
          retry_close <- try(close(con), silent = TRUE)
          if (!inherits(retry_close, "try-error")) closed <- TRUE
        }
        if (closed && file.exists(temp_path)) try(unlink(temp_path, force = TRUE), silent = TRUE)
      }, add = TRUE)
      write_result <- try(writeBin(img_raw, con), silent = TRUE)
      if (inherits(write_result, "try-error")) { cat("[IMAGE_GEN] Base64 kayıt hatası: write\n"); return(NULL) }
      close_result <- try(close(con), silent = TRUE)
      if (inherits(close_result, "try-error")) { cat("[IMAGE_GEN] Base64 kayıt hatası: close\n"); return(NULL) }
      closed <- TRUE
      temp_size <- suppressWarnings(file.info(temp_path)$size[1])
      if (is.na(temp_size) || temp_size != raw_len) { cat("[IMAGE_GEN] Base64 kayıt hatası: validate\n"); return(NULL) }
      if (!exists("mergen_promote_staged_file", mode = "function", inherits = TRUE)) {
        cat("[IMAGE_GEN] Base64 kayıt hatası: publish-helper\n"); return(NULL)
      }
      promotion <- NULL
      for (attempt in seq_len(3L)) {
        promotion <- mergen_promote_staged_file(temp_path, local_path, file.exists)
        if (isTRUE(promotion$promoted) || !isTRUE(promotion$yabanci) || attempt == 3L) break
        filename <- basename(tempfile(pattern = paste0("dalle_", format(Sys.time(), "%Y%m%d_%H%M%S"), "_"), tmpdir = save_dir, fileext = file_ext))
        local_path <- gsub("\\\\", "/", file.path(save_dir, filename))
      }
      if (!isTRUE(promotion$promoted)) {
        if (isTRUE(promotion$partial_owned)) try(unlink(local_path, force = TRUE), silent = TRUE)
        cat("[IMAGE_GEN] Base64 kayıt hatası: publish\n"); return(NULL)
      }
      if (!isTRUE(promotion$ok)) cat("[IMAGE_GEN] UYARI: Base64 görsel yayımlandı ancak hedef henüz görünmüyor\n")
      cat("[IMAGE_GEN] Görsel başarıyla kaydedildi (base64):", local_path, "\n")
      return(local_path)
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
      }
      cat("[IMAGE_GEN] Dosya oluşturuldu ama boş\n")
      return(NULL)
    }, error = function(write_err) {
      cat("[IMAGE_GEN] Dosya yazma hatası:", write_err$message, "\n")
      return(NULL)
    })
  }, error = function(e) {
    cat("[IMAGE_GEN] Genel hata:", e$message, "\n")
    return(NULL)
  })
}

#' Kaydedilmiş görseli web erişilebilir URL'ye dönüştür
#' @param local_path Yerel dosya yolu
#' @return Web URL'si
get_image_web_url <- function(local_path) {
 if (is.null(local_path) || !file.exists(local_path)) return(NULL)

 # Aktif oturum varsa görseli session-scoped URL ile sun (satır içi base64
 # şişmesini önler; tarayıcı görseli doğrudan/tembel çeker). Yardımcı yüklü
 # değilse veya oturum yoksa aşağıdaki base64 yoluna güvenli biçimde düşülür.
 if (exists("mergen_serve_image_data_url", mode = "function")) {
   served <- mergen_serve_image_data_url(local_path)
   if (!is.null(served) && nzchar(served)) return(served)
 }

 tryCatch({
   img_data <- base64enc::base64encode(local_path)
   ext <- tolower(tools::file_ext(local_path))
   mime <- switch(ext, jpg = "jpeg", jpeg = "jpeg", gif = "gif", webp = "webp", "png")
   paste0("data:image/", mime, ";base64,", img_data)
 }, error = function(e) NULL)
}

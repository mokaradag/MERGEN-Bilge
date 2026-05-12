# ==============================================================================
# Dosya Yolu: R/helpers_chat_message_formatting.R
# Açıklama: Veritabanından okunan sohbet mesajlarını uygulama içi mesaj nesnesine
#           dönüştüren yardımcıları içerir. Görsel mesajları, Chartlab blokları,
#           markdown HTML çıktısı, zaman damgası ve reasoning alanları burada
#           biçimlendirilir.
# ==============================================================================

# ------------------------------------------------------------------------------
# Görsel dosyasını base64 data-uri olarak hazırlar.
# ------------------------------------------------------------------------------
db_message_get_image_base64 <- function(file_path) {
  if (is.null(file_path) || length(file_path) != 1L || !nzchar(file_path)) {
    return(NULL)
  }

  if (!file.exists(file_path)) {
    return(NULL)
  }

  tryCatch({
    raw_data <- readBin(file_path, "raw", file.info(file_path)$size)
    base64_str <- base64enc::base64encode(raw_data)
    paste0("data:image/png;base64,", base64_str)
  }, error = function(e) {
    NULL
  })
}

# ------------------------------------------------------------------------------
# Veritabanında saklanan görsel yolunu gerçek dosya sisteminde çözmeye çalışır.
# ------------------------------------------------------------------------------
db_message_resolve_image_path <- function(image_path) {
  if (is.null(image_path) || length(image_path) != 1L || !nzchar(image_path)) {
    return(NULL)
  }

  image_path <- as.character(image_path[1])

  # 1. Doğrudan yolu dene.
  if (file.exists(image_path)) {
    return(image_path)
  }

  # 2. user_images/ içeren göreli yolu çıkarmayı dene.
  user_images_match <- regmatches(
    image_path,
    regexec("(user_images/.+)$", image_path)
  )[[1]]

  if (length(user_images_match) >= 2) {
    relative_path <- user_images_match[2]
    candidate_path <- file.path(getwd(), relative_path)

    if (file.exists(candidate_path)) {
      return(candidate_path)
    }
  }

  # 3. Sadece dosya adını al ve user_images altında ara.
  filename <- basename(image_path)
  search_pattern <- file.path(getwd(), "user_images", "*", "*", filename)
  found_files <- Sys.glob(search_pattern)

  if (length(found_files) > 0) {
    return(found_files[1])
  }

  NULL
}

# ------------------------------------------------------------------------------
# Görsel mesajı için HTML oluşturur.
# ------------------------------------------------------------------------------
db_message_render_image_html <- function(image_path, description, message_id) {
  resolved_path <- db_message_resolve_image_path(image_path)

  description_html <- if (!is.null(description) && nzchar(description)) {
    sprintf(
      '<div class="image-description"><p>%s</p></div>',
      htmltools::htmlEscape(description)
    )
  } else {
    ""
  }

  if (is.null(resolved_path)) {
    return(sprintf(
      '<div class="generated-image-container">
         <div class="image-placeholder" style="padding: 20px; background: linear-gradient(135deg, #667eea 0%%, #764ba2 100%%); border-radius: 12px; text-align: center; color: white;">
           <i class="fas fa-image" style="font-size: 48px; margin-bottom: 10px; opacity: 0.8;"></i>
           <p style="margin: 10px 0; font-weight: 500;">Görsel dosyası bulunamadı</p>
         </div>
         %s
       </div>',
      description_html
    ))
  }

  img_src <- db_message_get_image_base64(resolved_path)

  if (is.null(img_src)) {
    return(sprintf(
      '<div class="generated-image-container">
         <div class="image-placeholder" style="padding: 20px; background: #f0f0f0; border-radius: 12px; text-align: center;">
           <p>Görsel yüklenemedi</p>
         </div>
         %s
       </div>',
      description_html
    ))
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
    htmltools::htmlEscape(as.character(message_id)),
    img_src,
    description_html
  )
}

# ------------------------------------------------------------------------------
# Normal metin / Chartlab / markdown içeriğini HTML'e dönüştürür.
# ------------------------------------------------------------------------------
db_message_process_text_content <- function(content_text, msg_type, message_id) {
  has_chartlab <- grepl("```chartlab", content_text, fixed = TRUE)

  if (has_chartlab && msg_type %in% c("ai", "assistant")) {
    chart_fn <- tryCatch(
      get("build_chartlab_message_static", envir = globalenv(), mode = "function"),
      error = function(e) NULL
    )

    if (!is.null(chart_fn)) {
      chart_result <- tryCatch(
        chart_fn(content_text, as.character(message_id)),
        error = function(e) list(found = FALSE)
      )

      if (isTRUE(chart_result$found)) {
        return(list(html = chart_result$html, has_code = FALSE))
      }
    }
  }

  process_fn <- tryCatch(
    get("process_message_content", envir = globalenv(), mode = "function"),
    error = function(e) NULL
  )

  if (!is.null(process_fn)) {
    return(process_fn(content_text, msg_type))
  }

  list(
    html = commonmark::markdown_html(content_text, hardbreaks = TRUE),
    has_code = FALSE
  )
}

# ------------------------------------------------------------------------------
# Tek bir DB mesaj satırını uygulama mesaj nesnesine dönüştürür.
# ------------------------------------------------------------------------------
db_message_format_row <- function(row) {
  content_text <- row$MessageContent %||% ""
  msg_type <- row$MessageType %||% "user"

  if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
    content_text <- normalize_text_utf8(content_text, repair_mojibake = TRUE)
    msg_type <- normalize_text_utf8(msg_type, repair_mojibake = FALSE)
  }

  content_text <- trimws(content_text)

  is_image_message <- grepl("^\\[GÖRSEL", content_text, perl = TRUE)

  processed <- if (is_image_message && msg_type %in% c("ai", "assistant")) {
    image_match <- regmatches(
      content_text,
      regexec("^\\[GÖRSEL:([^\\]]+)\\]\\s*(.*)", content_text, perl = TRUE)
    )[[1]]

    if (length(image_match) == 3) {
      image_path <- image_match[2]
      image_description <- image_match[3]

      image_html <- db_message_render_image_html(
        image_path = image_path,
        description = image_description,
        message_id = as.character(row$MessageID)
      )

      list(html = image_html, has_code = FALSE)
    } else {
      old_match <- regmatches(
        content_text,
        regexec("^\\[GÖRSEL\\]\\s*(.*)", content_text, perl = TRUE)
      )[[1]]

      image_description <- if (length(old_match) == 2) {
        old_match[2]
      } else {
        content_text
      }

      styled_html <- sprintf(
        '<div class="generated-image-container">
           <div class="image-description"><p>%s</p></div>
         </div>',
        htmltools::htmlEscape(image_description)
      )

      list(html = styled_html, has_code = FALSE)
    }
  } else {
    db_message_process_text_content(
      content_text = content_text,
      msg_type = msg_type,
      message_id = as.character(row$MessageID)
    )
  }

  timestamp_val <- row$MessageTimestamp

  ts_tz <- attr(timestamp_val, "tzone")
  if (is.null(ts_tz) || !nzchar(ts_tz)) {
    ts_tz <- "UTC"
  }

  reasoning_text_saved <- NULL

  if ("ReasoningContent" %in% names(row)) {
    rc_val <- row$ReasoningContent

    if (!is.null(rc_val) &&
        length(rc_val) == 1 &&
        !is.na(rc_val) &&
        nzchar(rc_val)) {
      reasoning_text_saved <- if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
        normalize_text_utf8(as.character(rc_val), repair_mojibake = TRUE)
      } else {
        as.character(rc_val)
      }
    }
  }

  base_msg <- list(
    id = as.character(row$MessageID),
    db_id = as.integer(row$MessageID),
    content = content_text,
    html_content = processed$html,
    has_code = processed$has_code,
    type = msg_type,
    timestamp = format(timestamp_val, "%d.%m.%Y - %H:%M", tz = ts_tz)
  )

  if (!is.null(reasoning_text_saved)) {
    base_msg$reasoning_content <- reasoning_text_saved
    base_msg$reasoning_trace <- reasoning_text_saved
  }

  base_msg
}

# ------------------------------------------------------------------------------
# DB mesaj veri çerçevesini uygulama mesaj listesine dönüştürür.
# Bu fonksiyonun adı geriye dönük uyumluluk için korunur.
# ------------------------------------------------------------------------------
format_chat_messages <- function(chat_df) {
  if (is.null(chat_df) || nrow(chat_df) == 0) {
    return(list())
  }

  lapply(seq_len(nrow(chat_df)), function(i) {
    db_message_format_row(chat_df[i, , drop = FALSE])
  })
}
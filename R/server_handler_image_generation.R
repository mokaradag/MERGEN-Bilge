# ==============================================================================
# Dosya Yolu: R/server_handler_image_generation.R
# Açıklama: Görsel oluşturma modunun (DALL-E-3) işleyici fonksiyonu.
#           server_send_message.R'den ayrıştırılarak modülerlik artırılmıştır.
# ==============================================================================

# Görsel oluşturma modunu işle
# ctx: mesaj gönderme bağlamındaki tüm gerekli değişkenleri içeren liste
# Döndürür: TRUE (işlendi ve erken dönüş yapılmalı)
handle_image_generation_mode <- function(ctx) {

  log_debug("[IMAGE_MODE] Görsel Uzmanı modu aktif - görsel oluşturma başlatılıyor")

  chat_size <- ctx$input$chat_image_size
  chat_quality_hd <- isTRUE(ctx$input$chat_image_quality_hd)

  image_size <- if (!is.null(chat_size) && nzchar(chat_size)) {
    chat_size
  } else {
    ctx$settings_data$image_size %||% "1024x1024"
  }

  image_quality <- if (chat_quality_hd) "hd" else {
    if (isTRUE(ctx$settings_data$image_quality_hd)) "hd" else "standard"
  }

  api_key_for_image <- tryCatch(as.character(ctx$session$userData$ai_api_key)[1], error = function(e) "")

  if (!nzchar(api_key_for_image)) {
    removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
    ctx$values$typing <- FALSE
    ctx$add_message_fn("\U000026A0\U0000FE0F Görsel oluşturmak için API anahtarı gerekli. Lütfen Ayarlar sayfasından API anahtarınızı girin.", "ai")
    ctx$reset_chat_state_fn()
    return(TRUE)
  }

  # Yükleme göstergesi güncelle
  removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
  insertUI(
    selector = "#chat_content_container",
    where = "beforeEnd",
    ui = div(
      id = "typing-animation-wrapper",
      class = "message-bubble",
      style = "display: flex; justify-content: center; padding: 20px;",
      div(class = "image-generating",
        div(class = "image-generating-spinner"),
        div(class = "image-generating-text", "Görsel oluşturuluyor... Bu işlem 30 saniye ile 2 dakika arasında sürebilir.")
      )
    ),
    immediate = TRUE
  )
  shinyjs::runjs("window.smartScrollToBottom();")

  # Asenkron görsel oluşturma için değişkenleri yakala
  current_user_id_local <- ctx$current_user_id
  current_chat_id_local <- ctx$values$current_chat_id
  user_prompt_local <- ctx$user_message_text
  image_size_local <- image_size
  image_quality_local <- image_quality
  api_key_local <- api_key_for_image

	tracked_future_promise(
	  task_fn = function() {
		generate_image(
		  prompt = user_prompt_local,
		  api_key = api_key_local,
		  size = image_size_local,
		  quality = image_quality_local,
		  user_id = current_user_id_local,
		  chat_id = current_chat_id_local
		)
	  },
	  task_type = "image_generation",
	  session_token = ctx$session$token,
	  meta = list(
		size = image_size_local,
		quality = image_quality_local
	  )
	) %...>% (function(result) {
    removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
    ctx$values$typing <- FALSE

    if (isTRUE(result$success)) {
      image_html <- render_generated_image_html(result, paste0("img_", floor(as.numeric(Sys.time()) * 1000)))

      image_description <- result$revised_prompt %||% "[Görsel oluşturuldu]"
      image_path_marker <- if (!is.null(result$local_path) && nzchar(result$local_path)) {
        paste0("[GÖRSEL:", result$local_path, "]")
      } else {
        "[GÖRSEL]"
      }
      content_text <- paste0(image_path_marker, " ", image_description)

      ctx$add_message_fn(content_text, "ai", html = image_html)
      showToast(ctx$session, "Görsel oluşturuldu!", "success")
    } else {
      error_msg <- result$error %||% "Görsel oluşturulamadı"
      error_html <- render_generated_image_html(result, "error")
      ctx$add_message_fn(paste0("\U0000274C ", error_msg), "ai", html = error_html)
      showToast(ctx$session, error_msg, "error")
    }

    ctx$reset_chat_state_fn()
  }) %...!% (function(err) {
    removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
    ctx$values$typing <- FALSE
    ctx$add_message_fn(paste0("\U0000274C Görsel oluşturma hatası: ", err$message), "ai")
    showToast(ctx$session, paste("Hata:", err$message), "error")
    ctx$reset_chat_state_fn()
  })

  TRUE
}
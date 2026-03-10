# ==============================================================================
# Dosya Yolu: R/server_handler_summarization.R
# Açıklama: Dosya özetleme modunun işleyici fonksiyonu.
#           server_send_message.R'den ayrıştırılarak modülerlik artırılmıştır.
# ==============================================================================

# Dosya özetleme modunu işle
# ctx: mesaj gönderme bağlamındaki tüm gerekli değişkenleri içeren liste
# Döndürür: TRUE (işlendi ve erken dönüş yapılmalı) veya FALSE (işlenmedi)
handle_summarization_mode <- function(ctx) {

  if (ctx$uploaded_count == 0) {
    removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
    ctx$values$typing <- FALSE
    ctx$values$is_sending <- FALSE
    showToast(ctx$session, "Lütfen önce Dosya Yönetimi sayfasından dosya yükleyin ve 'Model Bağlamı' seçin.", "info")
    return(TRUE)
  }

  log_debug("[SUMMARIZATION] Dosya Özetleme modu aktif, özetleme başlatılıyor. Dosya sayısı: {ctx$uploaded_count}")

  if (!exists("process_summarization_request", mode = "function")) {
    source("R/module_summarization.R", encoding = "UTF-8", local = TRUE)
  }

  ctx$values$typing <- TRUE
  if (isTRUE(ctx$settings_data$enable_typing_indicator)) {
    removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
    insertUI(
      selector = "#chat_content_container",
      where = "beforeEnd",
      ui = div(
        id = "typing-animation-wrapper",
        class = "message-bubble",
        style = "display: flex; justify-content: center; padding: 20px;",
        div(class = "ring", "Belgeleriniz özetleniyor", span())
      ),
      immediate = TRUE
    )
  }

  if (nchar(ctx$user_message_text) > 0) {
    ctx$current_session_files$user_query <- ctx$user_message_text
    log_debug("[SUMMARIZATION] Kullanıcı sorgusu özetlemeye eklendi: {ctx$user_message_text}")
  }

  summary_detail <- ctx$input$chat_summary_detail %||% ctx$settings_data$summary_detail_level %||% "standard"
  summary_focus <- ctx$input$chat_summary_focus %||% ctx$settings_data$summary_focus_mode %||% "general"

  if (identical(summary_focus, "comparison") && ctx$uploaded_count == 1) {
    summary_focus <- "general"
    showToast(ctx$session, "Karşılaştırma modu için birden fazla dosya gereklidir. Genel moda geçildi.", "warning")
    ctx$session$sendCustomMessage("syncSummarySettingsToChat", list(
      detail_level = summary_detail,
      focus_mode = "general"
    ))
    ctx$session$sendCustomMessage("syncChatSummarySettingsToSettings", list(
      detail_level = summary_detail,
      focus_mode = "general"
    ))
    log_debug("[SUMMARIZATION] Tek dosya ile karşılaştırma modu seçildi, genel moda geçildi")
  }

  log_debug("[SUMMARIZATION] Mod parametreleri - Detay: {summary_detail}, Odak: {summary_focus}")

  # Promise ile özetleme
  p <- tryCatch(
    process_summarization_request(
      file_list = ctx$current_session_files,
      session = ctx$session,
      settings = ctx$settings_data,
      ai_processor = ctx$ai_processor,
      max_chars_per_file = if (grepl("256k|256K", ctx$settings_data$model_selection %||% "")) {
        200000
      } else {
        120000
      },
      detail_level = summary_detail,
      focus_mode = summary_focus
    ),
    error = function(e) {
      # Senkron hata durumunda promise olarak sar
      promises::promise_resolve(list(
        success = FALSE,
        message = paste("Özetleme başlatılamadı:", conditionMessage(e))
      ))
    }
  )

  promises::then(
    p,
    onFulfilled = function(result) {
      removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
      ctx$values$typing <- FALSE

      if (!result$success) {
        showToast(ctx$session, result$message, "error")
        ctx$reset_chat_state_fn()
        return(invisible(NULL))
      }

      ctx$add_message_fn(result$summary, "ai")

      showToast(ctx$session, paste(result$file_count, "dosya başarıyla özetlendi."), "success")

      ctx$reset_chat_state_fn()
    },
    onRejected = function(err) {
      removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
      ctx$values$typing <- FALSE
      showToast(ctx$session, paste("Özetleme hatası:", conditionMessage(err)), "error")
      ctx$reset_chat_state_fn()
    }
  )

  TRUE
}

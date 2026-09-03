# ==============================================================================
# Dosya Yolu: R/server_handler_summarization.R
# Açıklama: Dosya özetleme modunun işleyici fonksiyonu.
#           Hazırlık aşamasını yerel olarak yapar, ardından uygun ise
#           hızlı gerçek SSE akışına geçer.
# ==============================================================================

handle_summarization_mode <- function(ctx) {

  if (ctx$uploaded_count == 0) {
    removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
    ctx$values$typing <- FALSE
    ctx$values$is_sending <- FALSE
    showToast(ctx$session, "Lütfen önce Dosya Yönetimi sayfasından dosya yükleyin ve 'Model Bağlamı' seçin.", "info")
    return(TRUE)
  }

  log_debug("[SUMMARIZATION] Dosya Özetleme modu aktif, hazırlık başlatılıyor. Dosya sayısı: {ctx$uploaded_count}")

  if (!exists("prepare_summarization_request", mode = "function")) {
    safe_source("R/module_summarization.R", encoding = "UTF-8")
  }

  ctx$values$typing <- TRUE
  
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

  api_key_val <- tryCatch(
    mb_api_key_get_effective_key_value(
      session = ctx$session,
      require_auth = TRUE,
      allow_default = NULL,
      clear_on_mismatch = TRUE
    ),
    error = function(e) ""
  )

  if (!nzchar(api_key_val)) {
    removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
    ctx$values$typing <- FALSE
    showToast(
      ctx$session,
      "API anahtarı eksik. Ayarlar > Model Ayarları > API Anahtarı Güncelleme üzerinden girin.",
      "error"
    )
    ctx$reset_chat_state_fn()
    return(TRUE)
  }

  prep_result <- tryCatch(
    prepare_summarization_request(
      file_list = ctx$current_session_files,
      session = ctx$session,
      settings = ctx$settings_data,
      max_chars_per_file = if (grepl("256k|256K", ctx$settings_data$model_selection %||% "")) {
        200000
      } else {
        120000
      },
      detail_level = summary_detail,
      focus_mode = summary_focus
    ),
    error = function(e) {
      list(
        success = FALSE,
        message = paste("Özetleme hazırlığı başarısız:", conditionMessage(e))
      )
    }
  )

  if (!isTRUE(prep_result$success)) {
    removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
    ctx$values$typing <- FALSE
    showToast(ctx$session, prep_result$message, "error")
    ctx$reset_chat_state_fn()
    return(TRUE)
  }

  prep_result$current_settings$api_key_override <- api_key_val
  prep_result$current_settings$shiny_session <- ctx$session

  use_fast_stream <- isTRUE(prep_result$current_settings$enable_streaming) &&
    !isTRUE(ctx$settings_data$enable_tts_audio)

  if (isTRUE(use_fast_stream)) {
    log_info(sprintf(
      "[SUMMARIZATION PERF] Hızlı akış başlatılıyor - hazırlık=%.3f sn",
      prep_result$prep_duration %||% 0
    ))

    true_stream_ctx <- list(
      session = ctx$session,
      input = ctx$input,
      output = ctx$output,
      values = ctx$values,
      settings_data = ctx$settings_data,
      stop_generation = ctx$stop_generation,
      active_request_id = ctx$active_request_id,
      perf_tracker = ctx$perf_tracker,
      api_config = ctx$api_config,
      current_user_id = ctx$current_user_id,
      current_settings = prep_result$current_settings,
      model_selected = prep_result$selected_model,
      messages_to_process = prep_result$messages,
      user_message_text = ctx$user_message_text,
      user_prompt_msg = ctx$user_prompt_msg,
      chat_id_val = ctx$chat_id_val,
      pending_chat_title = NULL,
      saved_chats_data = ctx$saved_chats_data,
      add_message_fn = ctx$add_message_fn,
      reset_chat_state_fn = ctx$reset_chat_state_fn,
      followup_tools = ctx$followup_tools,
      fallback_followup_tool = ctx$fallback_followup_tool,
      request_start_time = ctx$request_start_time,
      stream_profile = list(
        label = "summarization_fast",
        use_delta_transport = TRUE,
        poll_interval_ms = 15L
      ),
      final_text_suffix = prep_result$metadata_block
    )

    handle_true_streaming_mode(true_stream_ctx)
    return(TRUE)
  }

  log_info("[SUMMARIZATION PERF] Non-streaming yedek yol kullanılıyor")

  # Yarış koruması: özetleme uzun sürebildiğinden, kullanıcı durdurup yeni bir
  # istek başlatırsa bu bayat geri çağrının yeni isteğin durumunu ezmemesi için
  # aktif istek kimliğini yakala.
  summary_active_request_id <- ctx$active_request_id
  summary_stop_generation <- ctx$stop_generation
  summary_req_id <- tryCatch(
    if (is.function(summary_active_request_id)) summary_active_request_id() else NULL,
    error = function(e) NULL
  )
  is_stale_summary_request <- function() {
    if (!is.function(summary_active_request_id) || is.null(summary_req_id)) {
      return(FALSE)
    }
    !mergen_is_current_request(summary_active_request_id, summary_req_id, summary_stop_generation)
  }

  p <- ctx$ai_processor$call_llm_non_streaming(
    prep_result$messages,
    prep_result$current_settings,
    prep_result$selected_model
  )

  promises::then(
    p,
    onFulfilled = function(result) {
      if (isTRUE(is_stale_summary_request())) {
        return(invisible(NULL))
      }

      removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
      ctx$values$typing <- FALSE

      if (!result$success) {
        showToast(ctx$session, paste("Özetleme başarısız:", result$error), "error")
        ctx$reset_chat_state_fn()
        return(invisible(NULL))
      }

      final_summary <- paste0(result$content, prep_result$metadata_block %||% "")
      ctx$add_message_fn(final_summary, "ai")

      showToast(ctx$session, paste(prep_result$file_count, "dosya başarıyla özetlendi."), "success")
      ctx$reset_chat_state_fn()
    },
    onRejected = function(err) {
      if (isTRUE(is_stale_summary_request())) {
        return(invisible(NULL))
      }

      removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
      ctx$values$typing <- FALSE
      showToast(ctx$session, paste("Özetleme hatası:", conditionMessage(err)), "error")
      ctx$reset_chat_state_fn()
    }
  )

  TRUE
}
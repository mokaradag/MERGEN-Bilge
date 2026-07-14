# ==============================================================================
# Dosya Yolu: R/helpers_send_message_thinking_panel.R
# Açıklama: send_message düşünme paneli planı ve panel kabuğu yerleştirme
#           yardımcıları. İstek yaşam döngüsü dosyasından (request_lifecycle)
#           tutarlı bir sorumluluk olarak ayrıldı; davranış birebir aynı.
#           premiumReasoningStart requestId sözleşmesinin sahibi bu dosyadır.
# ==============================================================================

mergen_build_thinking_panel_plan <- function(tool_family,
                                             settings_data,
                                             resolved_model_id = NULL,
                                             reasoning_will_stream_override = NULL,
                                             force_simulated_panel = FALSE) {
  # Langflow gibi yerel modeli olmayan araçlar: model etiketi göstermeden,
  # her zaman simüle edilmiş (fazlı) düşünme paneli gösterilir. Akış non-streaming
  # olduğundan gerçek reasoning akmaz; panel yanıt gelene kadar canlı kalır.
  if (isTRUE(force_simulated_panel)) {
    return(list(
      panel_model_id = "",
      thinking_model_active = FALSE,
      reasoning_will_stream = FALSE,
      classic_indicator_requested = isTRUE(settings_data$enable_typing_indicator),
      panel_simulated = TRUE,
      show_thinking_wrapper = TRUE
    ))
  }

  panel_model_id <- tryCatch({
    supplied_model <- as.character(resolved_model_id %||% "")[1]

    if (!is.na(supplied_model) && nzchar(supplied_model)) {
      supplied_model
    } else {
      resolve_tool_model_for_family(
        tool_family,
        fallback_model = settings_data$model_selection
      )
    }
  }, error = function(e) {
    settings_data$model_selection
  })

  panel_model_id <- tryCatch(as.character(panel_model_id %||% "")[1], error = function(e) "")
  if (is.na(panel_model_id)) panel_model_id <- ""

  thinking_model_active <- tryCatch(
    is_thinking_model(panel_model_id),
    error = function(e) FALSE
  )

  reasoning_will_stream <- if (!is.null(reasoning_will_stream_override)) {
    isTRUE(reasoning_will_stream_override)
  } else {
    isTRUE(settings_data$enable_streaming) &&
      !identical(tool_family, "mcp_excel") &&
      !identical(tool_family, "sql_analysis") &&
      !identical(tool_family, "image") &&
      !identical(tool_family, "summarization") &&
      !isTRUE(settings_data$enable_tts_audio)
  }

  classic_indicator_requested <- isTRUE(settings_data$enable_typing_indicator)
  panel_simulated <- !isTRUE(thinking_model_active) || !isTRUE(reasoning_will_stream)
  show_thinking_wrapper <- thinking_model_active || classic_indicator_requested

  list(
    panel_model_id = panel_model_id,
    thinking_model_active = thinking_model_active,
    reasoning_will_stream = reasoning_will_stream,
    classic_indicator_requested = classic_indicator_requested,
    panel_simulated = panel_simulated,
    show_thinking_wrapper = show_thinking_wrapper
  )
}

mergen_show_send_message_thinking_wrapper <- function(session,
                                                      panel_plan,
                                                      request_id = NULL) {
  if (!isTRUE(panel_plan$show_thinking_wrapper)) {
    return(invisible(FALSE))
  }

  removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)

  insertUI(
    selector = "#chat_content_container",
    where = "beforeEnd",
    ui = div(
      id = "typing-animation-wrapper",
      class = "message-bubble",
      `data-panel-takeover` = "true",
      style = "display: flex; justify-content: center; padding: 20px;"
    ),
    immediate = TRUE
  )

  shinyjs::runjs("
    setTimeout(() => {
      window.smartScrollToBottom();
      $('#typing-animation-wrapper').show();
    }, 10);
  ")

  session$sendCustomMessage("premiumReasoningStart", list(
    model = panel_plan$panel_model_id,
    classicFallback = panel_plan$classic_indicator_requested,
    simulated = panel_plan$panel_simulated,
    requestId = request_id
  ))

  invisible(TRUE)
}
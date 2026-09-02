# ==============================================================================
# Dosya Yolu: R/helpers_send_message_model_runtime.R
# Açıklama:   Mesaj gönderimi sırasında istek-bağımlı yaşam döngüsü callback'leri,
#             runtime model çözümleme ve MCP canlı Düşünce Akışı hazırlığını yapar.
# ==============================================================================

mergen_build_send_message_request_callbacks <- function(session,
                                                        values,
                                                        reset_chat_state_fn,
                                                        active_request_id,
                                                        req_id) {
  request_id <- req_id

  # Proje ve Kaynak Analizi köken alt bilgisi istek kapsamlıdır. Bu kurucu her
  # istek başında tam bir kez çalıştığı için bekleyen alt bilgi burada
  # temizlenir ve aktif istek kimliği yazılır; böylece bayat bir alt bilgi bir
  # sonraki yanıta iliştirilemez.
  #
  # DÖNÜŞ DEĞERİ YUTULMAZ (PR #705 incelemesi, P2): `pk_provenance_clear()`
  # oturum deposuna yazamazsa `FALSE` döner. Sonuç yok sayılırsa BAYAT bir
  # köken alt bilgisi bir sonraki yanıta iliştirilebilir ve bunun hiçbir izi
  # kalmazdı. Oturum YOKKEN (izole test/worker) `FALSE` beklenen ve sessiz
  # durumdur; uyarı yalnızca gerçek bir oturum varken üretilir. `tryCatch`:
  # yardımcı yüklü değilse (izole test) sessizce atlanır.
  koken_temizlendi <- tryCatch(
    isTRUE(pk_provenance_clear(session, request_id = request_id)),
    error = function(e) NA
  )
  if (!is.null(session) && !isTRUE(koken_temizlendi)) {
    # UYARI DEPO LOGGER'INA GİDER (PR #705 inceleme): `cat()` YALNIZCA stdout'a
    # yazar. Üretimde operatör log DOSYASINA bakar; bu satır oraya hiç
    # ulaşmıyordu, yani yukarıdaki gerekçenin ("bunun hiçbir izi kalmazdı")
    # kendisi geçerli kalıyordu. `log_warn()` yoksa (izole test/worker) `try()`
    # sessizce yutar ve davranış değişmez.
    try(log_warn(sprintf(
      "[PK_PROV] Koken alt bilgisi sifirlanamadi | istek=%s",
      as.character(request_id %||% "-")[1]
    )), silent = TRUE)
  }

  list(
    cleanup = function(remove_typing_wrapper = TRUE) {
      mergen_send_message_release_values_token(values = values, req_id = request_id)
      mergen_cleanup_send_message(
        values = values,
        reset_chat_state_fn = reset_chat_state_fn,
        remove_typing_wrapper = remove_typing_wrapper,
        active_request_id = active_request_id,
        req_id = request_id
      )
    },

    abort = function(message = NULL,
                     type = "warning",
                     remove_typing_wrapper = TRUE) {
      mergen_send_message_release_values_token(values = values, req_id = request_id)
      mergen_abort_send_message(
        session = session,
        values = values,
        reset_chat_state_fn = reset_chat_state_fn,
        toast_message = message,
        toast_type = type,
        remove_typing_wrapper = remove_typing_wrapper,
        active_request_id = active_request_id,
        req_id = request_id
      )
    }
  )
}

mergen_prepare_send_message_model_runtime <- function(input,
                                                      settings_data,
                                                      current_settings,
                                                      tool_family,
                                                      req_id) {
  excel_deep_on <- isTRUE(settings_data$excel_deep_thinking) ||
    isTRUE(shiny::isolate(input$chat_excel_deep_thinking))

  excel_deep_level <- settings_data$excel_deep_level %||%
    shiny::isolate(input$chat_excel_deep_level) %||%
    "low"

  coding_deep_on <- isTRUE(settings_data$coding_deep_thinking) ||
    isTRUE(shiny::isolate(input$chat_coding_deep_thinking))

  coding_deep_level <- settings_data$coding_deep_level %||%
    shiny::isolate(input$chat_coding_deep_level) %||%
    "low"

  model_selected <- resolve_runtime_model_for_request(
    tool_family = tool_family,
    fallback_model = current_settings$model_selection,
    excel_deep_on = excel_deep_on,
    excel_deep_level = excel_deep_level,
    coding_deep_on = coding_deep_on,
    coding_deep_level = coding_deep_level
  )

  log_info(sprintf(
    "[MODEL RESOLVE] arac=%s excel=%s/%s coding=%s/%s -> resolved_model=%s",
    tool_family,
    excel_deep_on,
    excel_deep_level,
    coding_deep_on,
    coding_deep_level,
    model_selected
  ))

  thinking_model_detected_early <- tryCatch(
    isTRUE(is_thinking_model(model_selected)),
    error = function(e) FALSE
  )

  mcp_reasoning_stream_on <- identical(tool_family, "mcp_excel") &&
    isTRUE(thinking_model_detected_early) &&
    isTRUE(current_settings$enable_streaming) &&
    !isTRUE(settings_data$enable_tts_audio)

  current_settings$enable_mcp_reasoning_stream <- mcp_reasoning_stream_on
  current_settings$mcp_reasoning_request_id <- req_id

  log_info(sprintf(
    "[MCP REASONING STREAM] enabled=%s tool=%s model=%s",
    mcp_reasoning_stream_on,
    tool_family,
    model_selected
  ))

  list(
    current_settings = current_settings,
    model_selected = model_selected,
    excel_deep_on = excel_deep_on,
    excel_deep_level = excel_deep_level,
    coding_deep_on = coding_deep_on,
    coding_deep_level = coding_deep_level,
    mcp_reasoning_stream_on = mcp_reasoning_stream_on
  )
}
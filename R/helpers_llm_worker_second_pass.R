# ==============================================================================
# Dosya Yolu: R/helpers_llm_worker_second_pass.R
# Açıklama:   MCP araç sonuçları alındıktan sonra yapılan ikinci LLM geçişini,
#             canlı Düşünce Akışı SSE yolunu ve güvenli non-streaming geri dönüşünü
#             helpers_llm_worker.R dışına taşır.
# ==============================================================================

llm_worker_second_pass_messages <- function(chat_history) {
  messages_payload <- llm_worker_chat_history_to_messages(chat_history)
  merge_system_messages_to_front(messages_payload)
}

llm_worker_second_pass_body <- function(selected_model,
                                        messages_payload,
                                        temp_value) {
  body <- list(
    model = selected_model,
    messages = messages_payload,
    stream = FALSE
  )

  if (!should_omit_temperature(selected_model)) {
    body$temperature <- temp_value
  }

  body
}

llm_worker_second_pass_headers <- function(api_key = NULL) {
  hdrs <- list(`Content-Type` = "application/json")

  if (!is.null(api_key) && nzchar(api_key)) {
    hdrs$Authorization <- paste("Bearer", api_key)
  }

  hdrs
}

llm_worker_second_pass_fallback_response <- function(tool_results_raw,
                                                     chart_blocks_text,
                                                     charts_to_store,
                                                     add_fallback_chart,
                                                     worker_start_time,
                                                     message = "Araç çıktıları alındı ancak yanıt üretilemedi.",
                                                     reasoning_content = NULL) {
  fb <- format_answer_from_tool_results(tool_results_raw)

  if (!(is.character(fb) && length(fb) > 0 && nzchar(trimws(fb[1])))) {
    fb <- message
  }

  if (is.character(chart_blocks_text) && nzchar(chart_blocks_text)) {
    fb <- paste0(fb, "\n\n", chart_blocks_text)
  }

  fb <- add_fallback_chart(fb)

  response <- list(
    content = fb,
    duration = as.numeric(difftime(Sys.time(), worker_start_time, units = "secs")),
    chart_store = charts_to_store
  )

  if (!is.null(reasoning_content)) {
    reasoning_txt <- as.character(reasoning_content %||% "")[1]
    if (!is.na(reasoning_txt) && nzchar(reasoning_txt)) {
      response$reasoning_content <- reasoning_txt
    }
  }

  response
}

llm_worker_call_second_pass_non_streaming <- function(api_endpoint,
                                                      hdrs,
                                                      body,
                                                      selected_model) {
  response <- httr::POST(
    api_endpoint,
    do.call(httr::add_headers, hdrs),
    body = jsonlite::toJSON(body, auto_unbox = TRUE),
    encode = "raw",
    httr::timeout(300)
  )

  status <- httr::status_code(response)

  if (status != 200) {
    resp_txt_raw <- try(
      httr::content(response, "text", encoding = "UTF-8"),
      silent = TRUE
    )

    resp_txt <- if (!inherits(resp_txt_raw, "try-error") &&
                    is.character(resp_txt_raw) &&
                    length(resp_txt_raw) > 0) {
      resp_txt_raw[[1]]
    } else {
      ""
    }

    return(list(
      success = FALSE,
      status = status,
      error_body = resp_txt,
      content = "",
      reasoning = ""
    ))
  }

  parsed <- httr::content(response, "parsed")

  separated <- extract_llm_content_and_sources(
    parsed,
    model_id = selected_model
  )

  list(
    success = TRUE,
    status = status,
    error_body = "",
    content = separated$content,
    reasoning = separated$reasoning %||% ""
  )
}

llm_worker_stream_content_looks_like_reasoning <- function(stream_content,
                                                           stream_reasoning) {
  stream_content <- as.character(stream_content %||% "")[1]
  stream_reasoning <- as.character(stream_reasoning %||% "")[1]

  if (is.na(stream_content)) stream_content <- ""
  if (is.na(stream_reasoning)) stream_reasoning <- ""

  nzchar(stream_content) && (
    identical(trimws(stream_content), trimws(stream_reasoning)) ||
      grepl(
        "^\\s*(Thinking Process:|\\*\\*Analyze the Request:|1\\.\\s*\\*\\*Analyze the Request|Okay, I will|Let's assemble|I will structure it)",
        stream_content,
        ignore.case = TRUE
      )
  )
}

llm_worker_run_mcp_second_pass <- function(chat_history,
                                           selected_model,
                                           settings,
                                           api_endpoint,
                                           api_key,
                                           temp_value,
                                           tool_results_raw,
                                           chart_blocks_text,
                                           charts_to_store,
                                           add_fallback_chart,
                                           worker_start_time) {
  messages_payload2 <- llm_worker_second_pass_messages(chat_history)

  body2 <- llm_worker_second_pass_body(
    selected_model = selected_model,
    messages_payload = messages_payload2,
    temp_value = temp_value
  )

  hdrs2 <- llm_worker_second_pass_headers(api_key)

  mcp_reasoning_stream_file <- as.character(settings$mcp_reasoning_stream_file %||% "")[1]
  if (is.na(mcp_reasoning_stream_file)) {
    mcp_reasoning_stream_file <- ""
  }

  mcp_reasoning_stream_enabled <- isTRUE(settings$enable_mcp_reasoning_stream) &&
    nzchar(mcp_reasoning_stream_file) &&
    exists("call_local_llm_sse_worker", mode = "function", inherits = TRUE)

  if (isTRUE(mcp_reasoning_stream_enabled)) {
    sse_settings <- settings
    sse_settings$model_selection <- selected_model
    sse_settings$enable_mcp_tools <- FALSE
    sse_settings$shiny_session <- NULL
    sse_settings$api_key_override <- api_key %||% settings$api_key_override %||% ""

    # MCP Excel ikinci geçişinde reasoning canlı panelde gösterilir.
    # Reasoning boş cevap durumunda asıl yanıt gövdesi olarak kullanılmaz.
    sse_settings$allow_reasoning_fallback_override <- FALSE

    log_info(sprintf(
      "[MCP REASONING STREAM] second_pass=SSE model=%s stream_file=%s",
      selected_model,
      mcp_reasoning_stream_file
    ))

    sse_roles <- vapply(messages_payload2, function(m) {
      as.character(m$role %||% "user")[1]
    }, character(1))

    log_info(sprintf(
      "[MCP REASONING STREAM] second_pass=SSE normalized_messages=%d roles=%s",
      length(messages_payload2),
      paste(sse_roles, collapse = " > ")
    ))

    stream_res2 <- call_local_llm_sse_worker(
      chat_history = messages_payload2,
      current_settings = sse_settings,
      stream_file = mcp_reasoning_stream_file,
      stop_file = NULL
    )

    stream_content <- as.character(stream_res2$content %||% "")[1]
    if (is.na(stream_content)) stream_content <- ""

    stream_reasoning <- as.character(stream_res2$reasoning %||% "")[1]
    if (is.na(stream_reasoning)) stream_reasoning <- ""

    if (isTRUE(stream_res2$success) &&
        nzchar(stream_content) &&
        !isTRUE(llm_worker_stream_content_looks_like_reasoning(stream_content, stream_reasoning))) {
      return(list(
        ok = TRUE,
        ai2 = stream_content,
        reasoning2 = stream_res2$reasoning %||% ""
      ))
    }

    log_warn(sprintf(
      "[MCP REASONING STREAM] second_pass=SSE failed_or_empty; retrying non-streaming. success=%s error=%s content_chars=%d reasoning_chars=%d",
      isTRUE(stream_res2$success),
      as.character(stream_res2$error %||% ""),
      nchar(stream_content %||% ""),
      nchar(as.character(stream_res2$reasoning %||% "")[1])
    ))

    non_stream <- llm_worker_call_second_pass_non_streaming(
      api_endpoint = api_endpoint,
      hdrs = hdrs2,
      body = body2,
      selected_model = selected_model
    )

    if (!isTRUE(non_stream$success)) {
      log_warn(sprintf(
        "[MCP REASONING STREAM] non-streaming retry also failed status=%s body=%s",
        non_stream$status,
        substr(non_stream$error_body %||% "", 1, 500)
      ))

      return(list(
        ok = FALSE,
        response = llm_worker_second_pass_fallback_response(
          tool_results_raw = tool_results_raw,
          chart_blocks_text = chart_blocks_text,
          charts_to_store = charts_to_store,
          add_fallback_chart = add_fallback_chart,
          worker_start_time = worker_start_time,
          reasoning_content = stream_res2$reasoning %||% NULL
        )
      ))
    }

    return(list(
      ok = TRUE,
      ai2 = non_stream$content,
      reasoning2 = non_stream$reasoning %||% stream_res2$reasoning %||% ""
    ))
  }

  non_stream <- llm_worker_call_second_pass_non_streaming(
    api_endpoint = api_endpoint,
    hdrs = hdrs2,
    body = body2,
    selected_model = selected_model
  )

  if (!isTRUE(non_stream$success)) {
    return(list(
      ok = FALSE,
      response = llm_worker_second_pass_fallback_response(
        tool_results_raw = tool_results_raw,
        chart_blocks_text = chart_blocks_text,
        charts_to_store = charts_to_store,
        add_fallback_chart = add_fallback_chart,
        worker_start_time = worker_start_time
      )
    ))
  }

  list(
    ok = TRUE,
    ai2 = non_stream$content,
    reasoning2 = non_stream$reasoning %||% ""
  )
}
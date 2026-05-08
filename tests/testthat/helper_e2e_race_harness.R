# ==============================================================================
# Dosya Yolu: tests/testthat/helper_e2e_race_harness.R
# Açıklama: E2E/race-condition regresyon testleri için gerçek servis
#           gerektirmeyen deterministik state harness yardımcıları.
# ==============================================================================

e2e_regression_config <- function() {
  list(
    local_models = c(
      "Process" = "technical name 1",
      "Summary" = "technical name 2",
      "Reasoning SQL" = "technical name 3",
      "Reasoning Excel" = "technical name 4",
      "Coding" = "technical name 5",
      "Expert" = "technical name 6"
    ),
    local_model_capabilities = list(
      "technical name 1" = list(thinking = FALSE, stream_reasoning = FALSE),
      "technical name 2" = list(thinking = FALSE, stream_reasoning = FALSE),
      "technical name 3" = list(thinking = TRUE, stream_reasoning = TRUE),
      "technical name 4" = list(thinking = TRUE, stream_reasoning = TRUE),
      "technical name 5" = list(thinking = FALSE, stream_reasoning = FALSE),
      "technical name 6" = list(thinking = FALSE, stream_reasoning = FALSE)
    ),
    tool_mode_config = list(
      process = list(
        family = "process",
        setting_flag = "enable_process_tools",
        quick_action_id = "project-process",
        title = "Süreç Yönetimi Sistemi",
        message = "Kurumsal süreç ve dokümantasyon konusunda yardıma ihtiyacım var.",
        description = "Şirket içi süreç, izleç, rehber ve şablon dokümanları.",
        icon_name = "briefcase",
        themeColor = "#3b82f6",
        model_id = "technical name 1",
        real_tool = FALSE
      ),
      app_expert = list(
        family = "app_expert",
        setting_flag = "enable_app_expert_tools",
        quick_action_id = "app-expert",
        title = "Uygulama Uzmanı",
        message = "Primavera P6 konusunda uzman desteğine ihtiyacım var.",
        description = "Kurumsal uygulamalar hakkında destek.",
        icon_name = "window-maximize",
        themeColor = "#8b5cf6",
        model_id = "technical name 6",
        real_tool = FALSE
      ),
      sql_analysis = list(
        family = "sql_analysis",
        setting_flag = "enable_rdata_tools",
        quick_action_id = "resource-analysis",
        title = "Proje ve Kaynak Analizi",
        message = "Kaynak kullanımını analiz etmem konusunda yardıma ihtiyacım var.",
        description = "Primavera P6 ve SAP verileri üzerinden analiz.",
        icon_name = "chart-bar",
        themeColor = "#06b6d4",
        model_id = "technical name 3",
        real_tool = TRUE
      ),
      mcp_excel = list(
        family = "mcp_excel",
        setting_flag = "enable_mcp_tools",
        quick_action_id = "excel-analysis",
        title = "Excel Analizi",
        message = "Excel dosyamı analiz etmem için yardım eder misin?",
        description = "MCP Excel aracı ile veri analizi.",
        icon_name = "file-excel",
        themeColor = "#10b981",
        model_id = "technical name 4",
        real_tool = TRUE
      ),
      image = list(
        family = "image",
        setting_flag = "enable_image_tools",
        quick_action_id = "image-creation",
        title = "Görsel Oluşturma",
        message = "Yapay zeka ile görsel oluşturmak istiyorum.",
        description = "Metinden görsel oluşturma.",
        icon_name = "image",
        themeColor = "#ec4899",
        model_id = "dall-e-3",
        real_tool = TRUE
      ),
      coding = list(
        family = "coding",
        setting_flag = "enable_coding_tools",
        quick_action_id = "coding-support",
        title = "Kodlama Desteği",
        message = "Yazılım geliştirme konusunda yardıma ihtiyacım var.",
        description = "Kodlama, hata ayıklama ve refaktör desteği.",
        icon_name = "code",
        themeColor = "#f59e0b",
        model_id = "technical name 5",
        real_tool = FALSE
      ),
      summarization = list(
        family = "summarization",
        setting_flag = "enable_summarization_tools",
        quick_action_id = "summarization",
        title = "Özetleme Desteği",
        message = "__SUMMARIZATION_REQUEST__",
        description = "Belgeleri kapsamlı şekilde özetleme.",
        icon_name = "file-alt",
        themeColor = "#6366f1",
        model_id = "technical name 2",
        real_tool = TRUE
      )
    )
  )
}

e2e_tool_flags <- function() {
  c(
    "enable_rdata_tools",
    "enable_mcp_tools",
    "enable_summarization_tools",
    "enable_coding_tools",
    "enable_process_tools",
    "enable_app_expert_tools",
    "enable_image_tools"
  )
}

e2e_new_quick_action_state <- function(config = e2e_regression_config()) {
  flags <- e2e_tool_flags()
  settings <- as.list(stats::setNames(rep(FALSE, length(flags)), flags))
  settings$model_selection <- as.character(config$local_models[[1]])

  list(
    config = config,
    values = list(
      show_welcome = TRUE,
      messages = list()
    ),
    settings = settings,
    llm_calls = 0L,
    saved_chat_updates = 0L
  )
}

e2e_active_flags <- function(state) {
  flags <- e2e_tool_flags()
  flags[vapply(flags, function(flag) isTRUE(state$settings[[flag]]), logical(1))]
}

e2e_apply_quick_action <- function(state, action_id, user_name = "Ayşe") {
  cfg <- get_tool_mode_config(
    action_id,
    by = "quick_action_id",
    config = state$config
  )

  if (!is.list(cfg)) {
    stop(sprintf("Bilinmeyen hızlı işlem: %s", action_id), call. = FALSE)
  }

  for (flag in e2e_tool_flags()) {
    state$settings[[flag]] <- FALSE
  }

  state$settings[[cfg$setting_flag]] <- TRUE
  state$settings$model_selection <- as.character(cfg$model_id)[1]
  state$values$show_welcome <- FALSE

  intro_text <- build_quick_action_intro_message(
    action_id = action_id,
    user_name = user_name,
    config = state$config
  )

  state$values$messages <- append(
    state$values$messages,
    list(list(
      id = sprintf("intro_%03d", length(state$values$messages) + 1L),
      type = "ai",
      content = intro_text,
      quick_action_id = action_id,
      persist_to_db = FALSE,
      add_to_saved_chats = FALSE,
      include_in_context = FALSE
    ))
  )

  state
}

e2e_send_prompt_after_quick_action <- function(state, prompt) {
  state$llm_calls <- state$llm_calls + 1L

  state$values$messages <- append(
    state$values$messages,
    list(list(
      id = sprintf("user_%03d", length(state$values$messages) + 1L),
      type = "user",
      content = enc2utf8(prompt),
      include_in_context = TRUE
    ))
  )

  state
}

e2e_new_quick_action_client_guard <- function(debounce_ms = 600L) {
  list(
    debounce_ms = as.numeric(debounce_ms),
    last_signature = "",
    last_at = -Inf,
    forwarded = list(),
    suppressed = 0L
  )
}

e2e_record_quick_action_client_click <- function(guard,
                                                 action_id,
                                                 model = "",
                                                 timestamp_ms = 0L) {
  action_id <- enc2utf8(as.character(action_id %||% "")[1])
  model <- enc2utf8(as.character(model %||% "")[1])
  timestamp_ms <- as.numeric(timestamp_ms)

  if (!nzchar(action_id)) {
    guard$suppressed <- guard$suppressed + 1L
    return(guard)
  }

  signature <- paste(action_id, model, sep = "|")
  elapsed <- timestamp_ms - guard$last_at

  if (identical(guard$last_signature, signature) &&
      is.finite(elapsed) &&
      elapsed < guard$debounce_ms) {
    guard$suppressed <- guard$suppressed + 1L
    return(guard)
  }

  guard$last_signature <- signature
  guard$last_at <- timestamp_ms
  guard$forwarded <- append(
    guard$forwarded,
    list(list(
      action_id = action_id,
      model = model,
      timestamp_ms = timestamp_ms
    ))
  )

  guard
}

e2e_collect_stream_payloads <- function(stream_file) {
  raw_lines <- readLines(stream_file, warn = FALSE, encoding = "UTF-8")

  payloads <- lapply(raw_lines, function(line) {
    jsonlite::fromJSON(line, simplifyVector = FALSE)
  })

  collect_type <- function(payload_type) {
    selected <- Filter(function(payload) identical(payload$type, payload_type), payloads)

    paste0(
      vapply(
        selected,
        decode_stream_delta_payload,
        character(1)
      ),
      collapse = ""
    )
  }

  list(
    payloads = payloads,
    visible = collect_type("delta"),
    reasoning = collect_type("reasoning_delta")
  )
}

e2e_new_stream_state <- function(req_id, msg_id = "msg_test") {
  list(
    req_id = req_id,
    msg_id = msg_id,
    finalized = FALSE,
    finalize_count = 0L,
    visible = "",
    reasoning = NULL,
    saved_chat_updates = 0L,
    final_messages = list(),
    last_skip_reason = NULL
  )
}

e2e_apply_stream_result_once <- function(stream_state,
                                         active_request_id,
                                         req_id,
                                         content,
                                         reasoning = NULL,
                                         stop_generation = function() FALSE) {
  request_state <- mergen_send_message_request_state(
    active_request_id = active_request_id,
    req_id = req_id,
    stop_generation = stop_generation
  )

  if (!identical(request_state, "current")) {
    stream_state$last_skip_reason <- request_state
    return(stream_state)
  }

  if (isTRUE(stream_state$finalized)) {
    stream_state$last_skip_reason <- "already_finalized"
    return(stream_state)
  }

  stream_state$finalized <- TRUE
  stream_state$finalize_count <- stream_state$finalize_count + 1L
  stream_state$visible <- enc2utf8(content)
  stream_state$reasoning <- e2e_persisted_reasoning_or_null(reasoning, simulated = FALSE)
  stream_state$saved_chat_updates <- stream_state$saved_chat_updates + 1L
  stream_state$last_skip_reason <- "finalized"

  stream_state$final_messages <- append(
    stream_state$final_messages,
    list(list(
      id = stream_state$msg_id,
      content = stream_state$visible,
      reasoning_content = stream_state$reasoning
    ))
  )

  stream_state
}

e2e_persisted_reasoning_or_null <- function(reasoning, simulated = FALSE) {
  if (isTRUE(simulated) || is.null(reasoning)) {
    return(NULL)
  }

  reasoning <- enc2utf8(as.character(reasoning)[1])
  if (!nzchar(reasoning)) {
    return(NULL)
  }

  reasoning
}
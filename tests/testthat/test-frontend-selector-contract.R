# ==============================================================================
# Dosya Yolu: tests/testthat/test-frontend-selector-contract.R
# Açıklama: Ön yüz JS seçicilerinin güncel UI ID/class sözleşmeleriyle hizalı
#           kaldığını doğrular.
# ==============================================================================

.read_repo_text_frontend_selector_contract <- function(path) {
  full_path <- file.path(resolve_repo_root_for_tests(), path)

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

.frontend_selector_has_text <- function(text, needle) {
  isTRUE(suppressWarnings(grepl(
    needle,
    text,
    fixed = TRUE,
    useBytes = TRUE
  )))
}

.frontend_selector_lacks_text <- function(text, needle) {
  !.frontend_selector_has_text(text, needle)
}

test_that("ön yüz seçici sözleşmeleri güncel UI ile hizalı kalır", {
  ui_text <- .read_repo_text_frontend_selector_contract("ui.R")
  input_js <- .read_repo_text_frontend_selector_contract("www/js/input_handlers.js")
  app_core_js <- .read_repo_text_frontend_selector_contract("www/js/app_core.js")
  shiny_handlers_js <- .read_repo_text_frontend_selector_contract("www/js/shiny_message_handlers.js")
  file_handlers_js <- .read_repo_text_frontend_selector_contract("www/js/file_handlers.js")
  chart_renderer_js <- .read_repo_text_frontend_selector_contract("www/js/chart_renderer.js")
  neural_welcome_js <- .read_repo_text_frontend_selector_contract("www/js/neural_welcome.js")
  server_core_interaction_runtime_r <- .read_repo_text_frontend_selector_contract("R/server_core_interaction_runtime.R")
  file_manager_table_r <- .read_repo_text_frontend_selector_contract("R/helpers_file_manager_table.R")
  file_manager_module_r <- .read_repo_text_frontend_selector_contract("R/module_file_manager.R")
  file_manager_attach_client_r <- .read_repo_text_frontend_selector_contract("R/helpers_file_manager_attach_client.R")
  stt_module_r <- .read_repo_text_frontend_selector_contract("R/module_stt.R")
  stt_client_js <- .read_repo_text_frontend_selector_contract("www/js/stt_client.js")
  tts_visualizer_r <- .read_repo_text_frontend_selector_contract("R/module_tts_visualizer.R")
  tts_visualizer_js <- .read_repo_text_frontend_selector_contract("www/js/tts_visualizer.js")
  welcome_modern_r <- .read_repo_text_frontend_selector_contract("R/welcome_screen_modern.R")
  claude_ui_r <- .read_repo_text_frontend_selector_contract("R/module_claude_code_ui.R")
  claude_js <- .read_repo_text_frontend_selector_contract("www/js/claude_code.js")
  claude_streaming_js <- .read_repo_text_frontend_selector_contract("www/js/claude_code_streaming.js")

  js_paths <- list.files(
    file.path(resolve_repo_root_for_tests(), "www", "js"),
    pattern = "\\.js$",
    full.names = FALSE
  )
  js_text <- paste(
    vapply(
      file.path("www/js", js_paths),
      .read_repo_text_frontend_selector_contract,
      character(1)
    ),
    collapse = "\n"
  )

  expect_true(.frontend_selector_has_text(ui_text, 'id = "user_input"'))
  expect_true(.frontend_selector_lacks_text(js_text, "message_input"))
  expect_true(.frontend_selector_lacks_text(input_js, "message_input"))
  expect_true(.frontend_selector_has_text(input_js, "#user_input, .chat-input"))
  expect_true(.frontend_selector_has_text(input_js, "window.MERGEN_CHAT_INPUT_SELECTOR"))
  expect_true(.frontend_selector_has_text(input_js, "window.getMergenChatInputElement"))
  expect_true(.frontend_selector_has_text(app_core_js, "function getCapabilityChatInput()"))
  expect_true(.frontend_selector_has_text(app_core_js, "window.getMergenChatInputElement"))
  expect_true(.frontend_selector_has_text(ui_text, 'inputId = "send_stop_btn"'))
  expect_true(.frontend_selector_has_text(input_js, "#send_stop_btn"))
  expect_true(.frontend_selector_has_text(server_core_interaction_runtime_r, 'activity_inputs = c("user_input", "send_stop_btn", "send_prompt_from_js")'))
  expect_true(.frontend_selector_lacks_text(server_core_interaction_runtime_r, '"send_btn"'))

  expect_true(.frontend_selector_has_text(ui_text, 'id = "welcome_fullscreen_container"'))
  expect_true(.frontend_selector_has_text(shiny_handlers_js, "#welcome_fullscreen_container"))
  expect_true(.frontend_selector_has_text(welcome_modern_r, 'class = "modern-welcome-action-btn"'))
  expect_true(.frontend_selector_has_text(welcome_modern_r, '`data-action-id` = action_data$id'))
  expect_true(.frontend_selector_has_text(welcome_modern_r, 'onclick = "window._handleQuickAction(this); return false;"'))
  expect_true(.frontend_selector_has_text(shiny_handlers_js, "window._handleQuickAction = function(btn)"))
  expect_true(.frontend_selector_has_text(shiny_handlers_js, "Shiny.setInputValue('quick_template'"))
  expect_true(.frontend_selector_has_text(shiny_handlers_js, "Shiny.addCustomMessageHandler('showNeuralAnimation'"))
  expect_true(.frontend_selector_has_text(neural_welcome_js, "window.startNeuralWelcomeAnimation"))
  expect_true(.frontend_selector_lacks_text(neural_welcome_js, "Shiny.addCustomMessageHandler('showNeuralAnimation'"))
  expect_true(.frontend_selector_has_text(ui_text, 'id = "chat_content_container"'))
  expect_true(.frontend_selector_has_text(app_core_js, "#chat_content_container"))
  expect_true(.frontend_selector_has_text(chart_renderer_js, "chat_content_container"))
  expect_true(.frontend_selector_has_text(chart_renderer_js, "chat-container"))
  expect_true(.frontend_selector_lacks_text(js_text, "chat_content_wrapper"))
  expect_true(.frontend_selector_lacks_text(app_core_js, "#_content_container"))
  expect_true(.frontend_selector_has_text(app_core_js, "function attachMessageObserver("))
  expect_true(.frontend_selector_has_text(app_core_js, "attachMessageObserver(true)"))
  expect_true(.frontend_selector_has_text(app_core_js, "codeMirrorObserver.disconnect()"))
  expect_true(.frontend_selector_has_text(app_core_js, "globalMessageObserver.disconnect()"))
  expect_true(.frontend_selector_has_text(chart_renderer_js, "function getChartRenderRoot(wrapperId)"))
  expect_true(.frontend_selector_lacks_text(chart_renderer_js, "document.body"))
  expect_true(.frontend_selector_lacks_text(chart_renderer_js, "querySelector('.' + wrapperId)"))

  expect_true(.frontend_selector_has_text(ui_text, 'id = "chat_input_wrapper"'))
  expect_true(.frontend_selector_has_text(file_handlers_js, "#chat_input_wrapper"))
  expect_true(.frontend_selector_has_text(file_handlers_js, "getChatWrapper()"))
  expect_true(.frontend_selector_has_text(ui_text, 'id = "drop_zone"'))
  expect_true(.frontend_selector_has_text(file_handlers_js, "#drop_zone"))
  expect_true(.frontend_selector_has_text(ui_text, 'fileInput("file_upload"'))
  expect_true(.frontend_selector_has_text(file_handlers_js, "document.getElementById('file_upload')"))
  expect_true(.frontend_selector_has_text(ui_text, 'id = "file_btn_container"'))
  expect_true(.frontend_selector_has_text(file_handlers_js, "#file_btn_container"))
  expect_true(.frontend_selector_has_text(file_handlers_js, "getFileManagerDropZone()"))

  expect_true(.frontend_selector_has_text(file_manager_table_r, 'class = "attach-checkbox"'))
  expect_true(.frontend_selector_has_text(file_manager_module_r, "input$attach_toggled"))
  expect_true(.frontend_selector_has_text(file_manager_module_r, "change.attach"))
  expect_true(.frontend_selector_has_text(file_manager_module_r, "drawCallback"))
  expect_true(.frontend_selector_has_text(file_manager_module_r, "fm_register_attach_state_client_handler(session = session, ns = ns)"))
  expect_true(.frontend_selector_lacks_text(file_manager_module_r, "Shiny.addCustomMessageHandler(nsPrefix + 'setAttachState'"))
  expect_true(.frontend_selector_has_text(file_manager_attach_client_r, "Shiny.addCustomMessageHandler(nsPrefix + 'setAttachState'"))
  expect_true(.frontend_selector_has_text(shiny_handlers_js, "input.attach-checkbox[data-filename]"))

  expect_true(.frontend_selector_has_text(stt_module_r, 'canvasId = ns("visualizer_canvas")'))
  expect_true(.frontend_selector_has_text(stt_module_r, 'timerId = ns("stt_timer")'))
  expect_true(.frontend_selector_has_text(stt_module_r, 'dbId = ns("stt_db_indicator")'))
  expect_true(.frontend_selector_has_text(stt_client_js, "document.getElementById(canvasId)"))
  expect_true(.frontend_selector_has_text(stt_client_js, "document.getElementById(timerId)"))
  expect_true(.frontend_selector_has_text(stt_client_js, "document.getElementById(dbId)"))
  expect_true(.frontend_selector_has_text(stt_client_js, 'nsPrefix + "-audio_chunk"'))

  expect_true(.frontend_selector_has_text(ui_text, 'id = "tts_visualizer_floating"'))
  expect_true(.frontend_selector_has_text(tts_visualizer_js, "#tts_visualizer_floating"))
  expect_true(.frontend_selector_has_text(tts_visualizer_r, 'tags$canvas(id = "tts_canvas"'))
  expect_true(.frontend_selector_has_text(tts_visualizer_js, "new SonicPulseVisualizer('tts_canvas'"))
  expect_true(.frontend_selector_has_text(tts_visualizer_js, "if (!visualizer || !window.ttsVisualizerState) return;"))

  expect_true(.frontend_selector_has_text(claude_ui_r, 'id = ns("prompt_input")'))
  expect_true(.frontend_selector_has_text(claude_ui_r, 'class = "cc-prompt-input"'))
  expect_true(.frontend_selector_has_text(claude_js, "prompt_input"))
  expect_true(.frontend_selector_has_text(claude_js, ".cc-prompt-input"))
  expect_true(.frontend_selector_has_text(claude_ui_r, 'id = ns("output_area")'))
  expect_true(.frontend_selector_has_text(claude_streaming_js, "cc-stream-chunk"))
  expect_true(.frontend_selector_has_text(claude_streaming_js, "document.getElementById(data.target)"))
  expect_true(.frontend_selector_has_text(claude_ui_r, 'id = ns("welcome_screen")'))
  expect_true(.frontend_selector_has_text(claude_streaming_js, "data.welcomeId"))
  expect_true(.frontend_selector_has_text(claude_streaming_js, "function findToolBlockById(target, toolId)"))
  expect_true(.frontend_selector_has_text(claude_streaming_js, "findToolBlockById(target, aracId)"))
  expect_true(.frontend_selector_lacks_text(claude_streaming_js, ".cc-tool-block[data-tool-id=\"' + aracId + '\"]"))
  expect_true(.frontend_selector_has_text(claude_ui_r, 'ns("run_command")'))
  expect_true(.frontend_selector_has_text(claude_ui_r, 'ns("stop_command")'))
})
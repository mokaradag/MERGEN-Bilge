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
  shiny_handlers_js <- .read_repo_text_frontend_selector_contract("www/js/shiny_message_handlers.js")
  file_handlers_js <- .read_repo_text_frontend_selector_contract("www/js/file_handlers.js")
  file_manager_table_r <- .read_repo_text_frontend_selector_contract("R/helpers_file_manager_table.R")
  file_manager_module_r <- .read_repo_text_frontend_selector_contract("R/module_file_manager.R")
  stt_module_r <- .read_repo_text_frontend_selector_contract("R/module_stt.R")
  claude_ui_r <- .read_repo_text_frontend_selector_contract("R/module_claude_code_ui.R")
  claude_js <- .read_repo_text_frontend_selector_contract("www/js/claude_code.js")
  claude_streaming_js <- .read_repo_text_frontend_selector_contract("www/js/claude_code_streaming.js")

  expect_true(.frontend_selector_has_text(ui_text, 'id = "user_input"'))
  expect_true(.frontend_selector_lacks_text(input_js, "message_input"))
  expect_true(.frontend_selector_has_text(input_js, "#user_input, .chat-input"))
  expect_true(.frontend_selector_has_text(ui_text, 'inputId = "send_stop_btn"'))
  expect_true(.frontend_selector_has_text(input_js, "#send_stop_btn"))

  expect_true(.frontend_selector_has_text(ui_text, 'id = "welcome_fullscreen_container"'))
  expect_true(.frontend_selector_has_text(shiny_handlers_js, "#welcome_fullscreen_container"))
  expect_true(.frontend_selector_has_text(ui_text, 'id = "chat_content_container"'))

  expect_true(.frontend_selector_has_text(ui_text, 'id = "chat_input_wrapper"'))
  expect_true(.frontend_selector_has_text(file_handlers_js, "#chat_input_wrapper"))
  expect_true(.frontend_selector_has_text(ui_text, 'id = "drop_zone"'))
  expect_true(.frontend_selector_has_text(file_handlers_js, "#drop_zone"))
  expect_true(.frontend_selector_has_text(ui_text, 'fileInput("file_upload"'))
  expect_true(.frontend_selector_has_text(file_handlers_js, "document.getElementById('file_upload')"))
  expect_true(.frontend_selector_has_text(ui_text, 'id = "file_btn_container"'))
  expect_true(.frontend_selector_has_text(file_handlers_js, "#file_btn_container"))

  expect_true(.frontend_selector_has_text(file_manager_table_r, 'class = "attach-checkbox"'))
  expect_true(.frontend_selector_has_text(file_manager_module_r, "input$attach_toggled"))
  expect_true(.frontend_selector_has_text(file_manager_module_r, "change.attach"))
  expect_true(.frontend_selector_has_text(file_manager_module_r, "drawCallback"))
  expect_true(.frontend_selector_has_text(shiny_handlers_js, "input.attach-checkbox[data-filename]"))

  expect_true(.frontend_selector_has_text(stt_module_r, 'canvasId = ns("visualizer_canvas")'))
  expect_true(.frontend_selector_has_text(stt_module_r, 'timerId = ns("stt_timer")'))
  expect_true(.frontend_selector_has_text(stt_module_r, 'dbId = ns("stt_db_indicator")'))

  expect_true(.frontend_selector_has_text(claude_ui_r, 'id = ns("prompt_input")'))
  expect_true(.frontend_selector_has_text(claude_js, "prompt_input"))
  expect_true(.frontend_selector_has_text(claude_ui_r, 'id = ns("output_area")'))
  expect_true(.frontend_selector_has_text(claude_streaming_js, "cc-stream-chunk"))
  expect_true(.frontend_selector_has_text(claude_streaming_js, "document.getElementById(data.target)"))
  expect_true(.frontend_selector_has_text(claude_ui_r, 'id = ns("welcome_screen")'))
  expect_true(.frontend_selector_has_text(claude_streaming_js, "data.welcomeId"))
  expect_true(.frontend_selector_has_text(claude_ui_r, 'ns("run_command")'))
  expect_true(.frontend_selector_has_text(claude_ui_r, 'ns("stop_command")'))
})
# ==============================================================================
# Dosya Yolu: tests/testthat/test-frontend-selector-contract.R
# Açıklama: Ön yüz JS seçicilerinin güncel UI ID/class sözleşmeleriyle hizalı
#           kaldığını doğrular.
# ==============================================================================

.read_repo_text_frontend_selector_contract <- function(path) {
  full_path <- file.path(resolve_repo_root_for_tests(), path)
  paste(readLines(full_path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
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

  expect_true(grepl('id = "user_input"', ui_text, fixed = TRUE))
  expect_false(grepl("message_input", input_js, fixed = TRUE))
  expect_true(grepl("#user_input, .chat-input", input_js, fixed = TRUE))
  expect_true(grepl('inputId = "send_stop_btn"', ui_text, fixed = TRUE))
  expect_true(grepl("#send_stop_btn", input_js, fixed = TRUE))

  expect_true(grepl('id = "welcome_fullscreen_container"', ui_text, fixed = TRUE))
  expect_true(grepl("#welcome_fullscreen_container", shiny_handlers_js, fixed = TRUE))
  expect_true(grepl('id = "chat_content_container"', ui_text, fixed = TRUE))

  expect_true(grepl('id = "chat_input_wrapper"', ui_text, fixed = TRUE))
  expect_true(grepl("#chat_input_wrapper", file_handlers_js, fixed = TRUE))
  expect_true(grepl('id = "drop_zone"', ui_text, fixed = TRUE))
  expect_true(grepl("#drop_zone", file_handlers_js, fixed = TRUE))
  expect_true(grepl('fileInput("file_upload"', ui_text, fixed = TRUE))
  expect_true(grepl("#file_upload", file_handlers_js, fixed = TRUE))
  expect_true(grepl('id = "file_btn_container"', ui_text, fixed = TRUE))
  expect_true(grepl("#file_btn_container", file_handlers_js, fixed = TRUE))

  expect_true(grepl('class = "attach-checkbox"', file_manager_table_r, fixed = TRUE))
  expect_true(grepl("input$attach_toggled", file_manager_module_r, fixed = TRUE))
  expect_true(grepl("change.attach", file_manager_module_r, fixed = TRUE))
  expect_true(grepl("drawCallback", file_manager_module_r, fixed = TRUE))
  expect_true(grepl("input.attach-checkbox[data-filename]", shiny_handlers_js, fixed = TRUE))

  expect_true(grepl('canvasId = ns("visualizer_canvas")', stt_module_r, fixed = TRUE))
  expect_true(grepl('timerId = ns("stt_timer")', stt_module_r, fixed = TRUE))
  expect_true(grepl('dbId = ns("stt_db_indicator")', stt_module_r, fixed = TRUE))

  expect_true(grepl('id = ns("prompt_input")', claude_ui_r, fixed = TRUE))
  expect_true(grepl("prompt_input", claude_js, fixed = TRUE))
  expect_true(grepl('id = ns("output_area")', claude_ui_r, fixed = TRUE))
  expect_true(grepl("cc-stream-chunk", claude_streaming_js, fixed = TRUE))
  expect_true(grepl("document.getElementById(data.target)", claude_streaming_js, fixed = TRUE))
  expect_true(grepl('id = ns("welcome_screen")', claude_ui_r, fixed = TRUE))
  expect_true(grepl("data.welcomeId", claude_streaming_js, fixed = TRUE))
  expect_true(grepl('ns("run_command")', claude_ui_r, fixed = TRUE))
  expect_true(grepl('ns("stop_command")', claude_ui_r, fixed = TRUE))
})
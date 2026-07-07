# Dosya Yolu: tests/testthat/test-ai-expert-frontend-split-contract.R
# Açıklama: AI Uzman frontend yöneticisi ile Shiny mesaj bağlayıcılarının
#           ayrı dosyalarda kaldığını ve yükleme sırasının korunmasını doğrular.


.read_static_utf8_lines <- function(path) {
  if (!exists("read_text_lines_utf8", mode = "function", inherits = TRUE)) {
    source(file.path(resolve_repo_root_for_tests(), "R", "utils_text_encoding.R"), encoding = "UTF-8")
  }
  read_text_lines_utf8(path)
}

.read_ai_expert_frontend_file <- function(path) {
  .read_static_utf8_lines(file.path(resolve_repo_root_for_tests(), path))
}

test_that("AI Expert manager runtime state machine owns no Shiny handler registrations", {
  manager <- paste(.read_ai_expert_frontend_file("www/js/ai_expert_manager.js"), collapse = "\n")
  handlers <- paste(.read_ai_expert_frontend_file("www/js/ai_expert_handlers.js"), collapse = "\n")

  expect_match(manager, "window\\.AIExpertManager = AIExpertManager")
  expect_false(grepl("Shiny\\.addCustomMessageHandler", manager))
  expect_false(grepl("\\$\\(document\\)\\.on\\('click', '\\.ai-expert-stop-btn'", manager))

  expected_handlers <- c(
    "aiExpertStartWithAudio",
    "aiExpertStartSubtitle",
    "aiExpertQueueAudioChunk",
    "aiExpertPlayAudio",
    "aiExpertNoAudioFallback",
    "aiExpertStopSubtitle",
    "aiExpertVisualizerVisibility",
    "aiExpertSetPage"
  )

  for (handler_name in expected_handlers) {
    expect_match(handlers, sprintf("Shiny\\.addCustomMessageHandler\\('%s'", handler_name))
  }
  expect_match(handlers, "getManager\\(\\)\\.stopSubtitle")
})

test_that("AI Expert handler asset loads immediately after manager and shares media ownership zone", {
  asset_env <- new.env(parent = baseenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "config_ui_assets.R"), local = asset_env, encoding = "UTF-8")
  source(file.path(resolve_repo_root_for_tests(), "R", "config_ui_asset_zones.R"), local = asset_env, encoding = "UTF-8")

  js_paths <- asset_env$ui_asset_flatten_groups(asset_env$ui_asset_js_groups)
  manager_pos <- match("js/ai_expert_manager.js", js_paths)
  handlers_pos <- match("js/ai_expert_handlers.js", js_paths)

  expect_false(is.na(manager_pos))
  expect_false(is.na(handlers_pos))
  expect_identical(handlers_pos, manager_pos + 1L)
  expect_true("js/ai_expert_handlers.js" %in% asset_env$ui_asset_ownership_zones$ses_yasam_dongusu$js)
})

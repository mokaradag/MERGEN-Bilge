# ==============================================================================
# Dosya Yolu: tests/testthat/test-modern-welcome-handler-split-contract.R
# Açıklama: Modern welcome Shiny handler/lifecycle sınırının merkezi mesaj
#           köprüsünden ayrı, manifest/zone kapsamında yüklendiğini doğrular.
# ==============================================================================

source(test_path("helper_bootstrap.R"), encoding = "UTF-8")

.load_modern_welcome_asset_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  source(file.path(repo_root, "R", "config_ui_assets.R"), encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "config_ui_asset_validators.R"), encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "config_ui_asset_zones.R"), encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "config_ui_asset_zone_validators.R"), encoding = "UTF-8", local = env)
  env
}

.read_modern_welcome_split_text <- function(...) {
  readChar(
    file.path(resolve_repo_root_for_tests(), ...),
    nchars = file.info(file.path(resolve_repo_root_for_tests(), ...))$size,
    useBytes = TRUE
  )
}

test_that("modern welcome handler is an ordered owned frontend asset", {
  env <- .load_modern_welcome_asset_env()
  js_assets <- env$ui_asset_all_js()

  modern_pos <- match("js/modern_welcome_handler.js", js_assets)
  shiny_pos <- match("js/shiny_message_handlers.js", js_assets)
  ui_init_pos <- match("js/ui_init.js", js_assets)
  neural_pos <- match("js/neural_welcome.js", js_assets)
  video_pos <- match("js/welcome_video_player.js", js_assets)

  expect_false(is.na(modern_pos))
  expect_lt(shiny_pos, modern_pos)
  expect_lt(modern_pos, ui_init_pos)
  expect_lt(modern_pos, neural_pos)
  expect_lt(modern_pos, video_pos)

  owner_zone <- env$ui_asset_zone_get("shiny_mesaj_koprusu", env$ui_asset_ownership_zones)
  expect_true("js/modern_welcome_handler.js" %in% env$ui_asset_zone_js_paths(owner_zone, env$ui_asset_js_groups))

  other_zone_ids <- setdiff(names(env$ui_asset_ownership_zones), "shiny_mesaj_koprusu")
  other_zone_assets <- unlist(lapply(other_zone_ids, function(id) {
    env$ui_asset_zone_js_paths(env$ui_asset_ownership_zones[[id]], env$ui_asset_js_groups)
  }), use.names = FALSE)
  expect_false("js/modern_welcome_handler.js" %in% other_zone_assets)
})

test_that("initModernWelcome lifecycle moved out of generic Shiny message bridge", {
  shiny_handlers <- .read_modern_welcome_split_text("www", "js", "shiny_message_handlers.js")
  modern_handler <- .read_modern_welcome_split_text("www", "js", "modern_welcome_handler.js")

  expect_false(grepl("initModernWelcome", shiny_handlers, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("Shiny.addCustomMessageHandler('initModernWelcome'", modern_handler, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("clearModernWelcomeBootTimer();", modern_handler, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("MAX_ATTEMPTS = 80", modern_handler, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("WelcomeVideoPlayer.init(videoContainer)", modern_handler, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("MERGEN_SAVED_CHARACTER_ACCENT", modern_handler, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("WelcomeNeuralNetwork.init(neuralCanvas, accentColor)", modern_handler, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("WelcomeGreeting.init(greetingText)", modern_handler, fixed = TRUE, useBytes = TRUE))

  expect_true(grepl("Shiny.addCustomMessageHandler('showToast'", shiny_handlers, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("Shiny.addCustomMessageHandler('showNeuralAnimation'", shiny_handlers, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("window._handleQuickAction = function(btn)", shiny_handlers, fixed = TRUE, useBytes = TRUE))
})

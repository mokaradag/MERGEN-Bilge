# Dosya Yolu: tests/testthat/test-deep-space-frontend-lifecycle-contract.R
# Açıklama: Deep Space giriş animasyonunda zamanlayıcı/rAF yaşam döngüsü
#           sınırının ayrı varlıkta kaldığını ve stale callback temizliğinin
#           statik sözleşmeyle korunduğunu doğrular.

.read_deep_space_frontend_file <- function(path) {
  readLines(file.path(resolve_repo_root_for_tests(), path), encoding = "UTF-8", warn = FALSE)
}

test_that("Deep Space lifecycle helper owns timer, rAF and auto-init boundaries", {
  lifecycle <- paste(.read_deep_space_frontend_file("www/js/deep_space_intro_lifecycle.js"), collapse = "\n")

  expect_match(lifecycle, "window\\.DeepSpaceIntroLifecycle")
  expect_match(lifecycle, "createTimers: createTimers")
  expect_match(lifecycle, "trackTimeout: trackTimeout")
  expect_match(lifecycle, "clearTrackedTimeout: clearTrackedTimeout")
  expect_match(lifecycle, "trackRaf: trackRaf")
  expect_match(lifecycle, "cancelTrackedRaf: cancelTrackedRaf")
  expect_match(lifecycle, "cancelAll: cancelAll")
  expect_match(lifecycle, "shouldSkipIntro: shouldSkipIntro")
  expect_match(lifecycle, "bindAutoInit: bindAutoInit")
  expect_match(lifecycle, "DOMContentLoaded', callback, \\{ once: true \\}")
  expect_match(lifecycle, "settings\\.skip_intro === true")
})

test_that("Deep Space scene module delegates lifecycle cleanup to helper", {
  scene <- paste(.read_deep_space_frontend_file("www/js/deep_space_intro.js"), collapse = "\n")

  expect_match(scene, "window\\.DeepSpaceIntro = \\(function\\(\\)")
  expect_match(scene, "window\\.DeepSpaceIntroLifecycle\\.createTimers\\(\\)")
  expect_match(scene, "_lifecycleTimers\\.trackTimeout")
  expect_match(scene, "_lifecycleTimers\\.trackRaf")
  expect_match(scene, "_lifecycleTimers\\.clearTrackedTimeout")
  expect_match(scene, "_lifecycleTimers\\.cancelTrackedRaf")
  expect_match(scene, "_lifecycleTimers\\.cancelAll\\(\\)")
  expect_match(scene, "window\\.DeepSpaceIntroLifecycle\\.bindAutoInit\\(\\)")

  expect_false(grepl("localStorage\\.getItem\\('mergen_settings'", scene))
  expect_false(grepl("addEventListener\\('DOMContentLoaded'", scene))
})

test_that("Deep Space lifecycle helper loads between solar setup and scene module", {
  asset_env <- new.env(parent = baseenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "config_ui_assets.R"), local = asset_env, encoding = "UTF-8")
  source(file.path(resolve_repo_root_for_tests(), "R", "config_ui_asset_zones.R"), local = asset_env, encoding = "UTF-8")

  js_paths <- asset_env$ui_asset_flatten_groups(asset_env$ui_asset_js_groups)
  solar_pos <- match("js/deep_space_intro_solar.js", js_paths)
  lifecycle_pos <- match("js/deep_space_intro_lifecycle.js", js_paths)
  scene_pos <- match("js/deep_space_intro.js", js_paths)

  expect_false(is.na(solar_pos))
  expect_false(is.na(lifecycle_pos))
  expect_false(is.na(scene_pos))
  expect_identical(lifecycle_pos, solar_pos + 1L)
  expect_identical(scene_pos, lifecycle_pos + 1L)
  expect_true("js/deep_space_intro_lifecycle.js" %in% asset_env$ui_asset_ownership_zones$karsilama_intro$js)
})

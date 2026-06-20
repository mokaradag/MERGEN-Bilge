# ==============================================================================
# Dosya Yolu: tests/testthat/test-ui-asset-tag-builders-behavior.R
# Açıklama: R/config_ui_assets.R etiket/inşa yardımcılarının davranış testleri:
#             ui_asset_css_tag, ui_asset_script_tag, ui_asset_flatten_groups,
#             ui_asset_css_tags, ui_asset_js_tags, ui_asset_validate_js_render_plan.
#           Bu fonksiyonlar daha önce doğrudan test edilmiyordu. Dosya sistemi
#           varlık kontrolü GEREKMEZ (etiket inşası saf htmltools üretimidir).
# ==============================================================================

testthat::local_edition(3)
if (requireNamespace("shiny", quietly = TRUE)) suppressMessages(library(shiny))

.source_ui_assets <- function() {
  env <- new.env(parent = globalenv())
  # VERİ + DOĞRULAYICI + RENDER üç dosyası birlikte yüklenir (etiket inşası
  # çözümleyiciyi, çözümleyici de veriyi çağrı anında çözer).
  for (asset_file in c(
    "R/config_ui_assets.R",
    "R/config_ui_asset_validators.R",
    "R/config_ui_asset_tags.R"
  )) {
    source(
      file.path(resolve_repo_root_for_tests(), asset_file),
      encoding = "UTF-8", local = env
    )
  }
  env
}

.tag_html <- function(t) paste(as.character(t), collapse = "\n")

testthat::test_that("ui_asset_css_tag normal CSS için type'lı link üretir", {
  env <- .source_ui_assets()
  html <- .tag_html(env$ui_asset_css_tag("css/app.css"))
  testthat::expect_true(grepl("<link", html, fixed = TRUE))
  testthat::expect_true(grepl("href=\"css/app.css\"", html, fixed = TRUE))
  testthat::expect_true(grepl("text/css", html, fixed = TRUE))
})

testthat::test_that("ui_asset_css_tag codemirror için type'sız link üretir", {
  env <- .source_ui_assets()
  html <- .tag_html(env$ui_asset_css_tag("codemirror/lib/codemirror.css"))
  testthat::expect_true(grepl("<link", html, fixed = TRUE))
  testthat::expect_false(grepl("text/css", html, fixed = TRUE))
})

testthat::test_that("ui_asset_script_tag defer bayrağını yansıtır", {
  env <- .source_ui_assets()
  html_plain <- .tag_html(env$ui_asset_script_tag("js/app.js"))
  testthat::expect_true(grepl("<script", html_plain, fixed = TRUE))
  testthat::expect_false(grepl("defer", html_plain, fixed = TRUE))

  html_defer <- .tag_html(env$ui_asset_script_tag("js/app.js", defer = TRUE))
  testthat::expect_true(grepl("defer", html_defer, fixed = TRUE))
})

testthat::test_that("ui_asset_flatten_groups iç içe grupları isimsiz düz vektöre indirir", {
  env <- .source_ui_assets()
  res <- env$ui_asset_flatten_groups(list(a = c("1", "2"), b = "3"))
  testthat::expect_identical(res, c("1", "2", "3"))
  testthat::expect_null(names(res))
})

testthat::test_that("ui_asset_css_tags manifestteki tüm CSS için link listesi üretir", {
  env <- .source_ui_assets()
  html <- .tag_html(env$ui_asset_css_tags())
  testthat::expect_true(grepl("<link", html, fixed = TRUE))
  # En az birkaç gerçek CSS yolu olmalı.
  testthat::expect_gt(length(gregexpr("<link", html, fixed = TRUE)[[1]]), 3L)
})

testthat::test_that("ui_asset_js_tags render planından script listesi üretir", {
  env <- .source_ui_assets()
  html <- .tag_html(env$ui_asset_js_tags())
  testthat::expect_true(grepl("<script", html, fixed = TRUE))
  testthat::expect_gt(length(gregexpr("<script", html, fixed = TRUE)[[1]]), 3L)
})

testthat::test_that("ui_asset_validate_js_render_plan gerçek manifestte hatasız geçer", {
  env <- .source_ui_assets()
  testthat::expect_silent(env$ui_asset_validate_js_render_plan())
})

testthat::test_that("ui_asset_validate_js_render_plan boş planı reddeder", {
  env <- .source_ui_assets()
  testthat::expect_error(
    env$ui_asset_validate_js_render_plan(render_plan = list()),
    "boş olamaz"
  )
})

testthat::test_that("ui_asset_validate_js_render_plan yinelenen grubu reddeder", {
  env <- .source_ui_assets()
  bozuk <- list(
    list(group = "g1", defer = FALSE),
    list(group = "g1", defer = TRUE)
  )
  testthat::expect_error(
    env$ui_asset_validate_js_render_plan(render_plan = bozuk, groups = list(g1 = "x.js")),
    "yinelenen grup"
  )
})

testthat::test_that("ui_asset_validate_js_render_plan eksik defer alanını reddeder", {
  env <- .source_ui_assets()
  bozuk <- list(list(group = "g1"))
  testthat::expect_error(
    env$ui_asset_validate_js_render_plan(render_plan = bozuk, groups = list(g1 = "x.js")),
    "group ve defer"
  )
})

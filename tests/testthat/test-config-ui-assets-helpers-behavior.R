# ==============================================================================
# Dosya Yolu: tests/testthat/test-config-ui-assets-helpers-behavior.R
# Açıklama: R/config_ui_assets.R saf varlık yardımcılarının davranışsal testleri.
#           CSS/script etiket üretimi, grup düzleştirme ve JS sıra doğrulamasının
#           gerçek manifesti onaylaması ile ters sırada hata vermesi doğrulanır.
# ==============================================================================

testthat::local_edition(3)

if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

.uia_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "config_ui_assets.R"),
  encoding = "UTF-8",
  local = .uia_env
)

.uia_html <- function(ui) paste(as.character(ui), collapse = "")

# -----------------------------------------------------------------------------
# ui_asset_css_tag
# -----------------------------------------------------------------------------

test_that("ui_asset_css_tag normal CSS'e type=text/css ekler, codemirror'a eklemez", {
  skip_if_not_installed("shiny")
  normal <- .uia_html(.uia_env$ui_asset_css_tag("css/app.css"))
  cm <- .uia_html(.uia_env$ui_asset_css_tag("codemirror/lib/cm.css"))

  expect_true(grepl('href="css/app.css"', normal, fixed = TRUE))
  expect_true(grepl('type="text/css"', normal, fixed = TRUE))
  # CodeMirror CSS'inde type belirtilmez.
  expect_true(grepl('href="codemirror/lib/cm.css"', cm, fixed = TRUE))
  expect_false(grepl('type="text/css"', cm, fixed = TRUE))
})

# -----------------------------------------------------------------------------
# ui_asset_script_tag
# -----------------------------------------------------------------------------

test_that("ui_asset_script_tag defer bayrağına göre defer özniteliği ekler", {
  skip_if_not_installed("shiny")
  normal <- .uia_html(.uia_env$ui_asset_script_tag("js/app.js"))
  ertelenmis <- .uia_html(.uia_env$ui_asset_script_tag("js/x.js", defer = TRUE))

  expect_true(grepl('src="js/app.js"', normal, fixed = TRUE))
  expect_false(grepl("defer", normal, fixed = TRUE))
  expect_true(grepl('src="js/x.js"', ertelenmis, fixed = TRUE))
  expect_true(grepl('defer="defer"', ertelenmis, fixed = TRUE))
})

# -----------------------------------------------------------------------------
# ui_asset_flatten_groups
# -----------------------------------------------------------------------------

test_that("ui_asset_flatten_groups gruplu listeyi adsız karakter vektörüne düzleştirir", {
  out <- .uia_env$ui_asset_flatten_groups(list(a = c("x", "y"), b = "z"))
  expect_identical(out, c("x", "y", "z"))
  expect_null(names(out))
})

# -----------------------------------------------------------------------------
# ui_asset_validate_js_order
# -----------------------------------------------------------------------------

test_that("ui_asset_validate_js_order gerçek manifesti hatasız doğrular", {
  expect_error(.uia_env$ui_asset_validate_js_order(), NA)
})

test_that("ui_asset_validate_js_order ters sıralı manifestte hata verir", {
  ters <- rev(.uia_env$ui_asset_all_js())
  expect_error(.uia_env$ui_asset_validate_js_order(ters))
})

test_that("ui_asset_validate_js_order kuraldaki dosya manifestte yoksa hata verir", {
  # İlk sıra kuralının dosyalarını içermeyen bir yol listesi.
  expect_error(.uia_env$ui_asset_validate_js_order(c("js/olmayan_dosya.js")))
})

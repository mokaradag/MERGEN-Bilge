# ==============================================================================
# Dosya Yolu: tests/testthat/test-quality-gate-entrypoint.R
# Açıklama: app.R ve tests/testthat.R icindeki kritik boot/test kontratlarini
# statik olarak korur.
# Onemli not: Windows VM encoding sorunlari nedeniyle bu test dosyasi kaynak
# dosyalari readLines ile okumaz; parse edip yorumlardan bagimsiz kod metni
# uzerinden kontrol yapar.
# ==============================================================================

parse_repo_code_text <- function(rel_path) {
  abs_path <- file.path(repo_root_for_tests, rel_path)

  if (!file.exists(abs_path)) {
    stop(sprintf("Dosya bulunamadi: %s", rel_path))
  }

  exprs <- parse(
    file = abs_path,
    keep.source = FALSE,
    encoding = "UTF-8"
  )

  paste(
    vapply(
      exprs,
      function(expr) paste(deparse(expr, width.cutoff = 500L), collapse = "\n"),
      character(1)
    ),
    collapse = "\n"
  )
}

test_that("app.R boot adimlarini isimlendirilmis boot_step ile sarar", {
  txt <- parse_repo_code_text("app.R")

  expect_true(grepl("boot_step <- function", txt, fixed = TRUE))
  expect_true(grepl('boot_step\\("global\\.R"', txt))
  expect_true(grepl('boot_step\\("ui\\.R"', txt))
  expect_true(grepl('boot_step\\("server\\.R"', txt))
})

test_that("app.R validate_boot_state UI kontratini korur", {
  txt <- parse_repo_code_text("app.R")

  expect_true(grepl("validate_boot_state <- function", txt, fixed = TRUE))
  expect_true(grepl('exists\\("safe_source"', txt))
  expect_true(grepl('exists\\("ui"', txt))
  expect_true(grepl('exists\\("server"', txt))
  expect_true(grepl('inherits\\(ui_obj, c\\("shiny.tag", "shiny.tag.list", "html"\\)\\)', txt))
})

test_that("tests/testthat.R repo koku guard ve summary reporter ile calisir", {
  txt <- parse_repo_code_text(file.path("tests", "testthat.R"))

  expect_true(grepl('normalizePath\\("\\."', txt))
  expect_true(grepl('file\\.exists\\(file\\.path\\(repo_root, "app\\.R"\\)\\)', txt))
  expect_true(grepl('dir\\.exists\\(file\\.path\\(repo_root, "tests", "testthat"\\)\\)', txt))
  expect_true(grepl('testthat::test_dir\\(', txt))
  expect_true(grepl('file\\.path\\("tests", "testthat"\\)', txt))
  expect_true(grepl('reporter = "summary"', txt, fixed = TRUE))
  expect_true(grepl("stop_on_warning = TRUE", txt, fixed = TRUE))
})
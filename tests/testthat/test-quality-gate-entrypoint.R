# ==============================================================================
# Dosya Yolu: tests/testthat/test-quality-gate-entrypoint.R
# Açıklama: app.R ve tests/testthat.R icindeki kritik boot/test kontratlarini
# statik olarak korur.
# ==============================================================================

read_repo_text <- function(rel_path) {
  paste(
    readLines(
      file.path(repo_root_for_tests, rel_path),
      warn = FALSE,
      encoding = "UTF-8"
    ),
    collapse = "\n"
  )
}

test_that("app.R boot adimlarini isimlendirilmis boot_step ile sarar", {
  txt <- read_repo_text("app.R")

  expect_true(grepl("boot_step <- function", txt, fixed = TRUE))
  expect_true(grepl('boot_step\\("global\\.R"', txt))
  expect_true(grepl('boot_step\\("ui\\.R"', txt))
  expect_true(grepl('boot_step\\("server\\.R"', txt))
})

test_that("app.R validate_boot_state UI kontratini korur", {
  txt <- read_repo_text("app.R")

  expect_true(grepl("validate_boot_state <- function", txt, fixed = TRUE))
  expect_true(grepl("ui nesnesi geçerli bir Shiny UI değil", txt, fixed = TRUE))
})

test_that("tests/testthat.R repo koku guard ve summary reporter ile calisir", {
  txt <- read_repo_text(file.path("tests", "testthat.R"))

  expect_true(grepl("repo kökünden çalıştırılmalıdır", txt, fixed = TRUE))
  expect_true(grepl('file\\.path\\("tests", "testthat"\\)', txt))
  expect_true(grepl('reporter = "summary"', txt, fixed = TRUE))
  expect_true(grepl("stop_on_warning = TRUE", txt, fixed = TRUE))
})
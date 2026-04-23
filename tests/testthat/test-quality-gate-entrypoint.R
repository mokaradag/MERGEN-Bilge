# ==============================================================================
# Dosya Yolu: tests/testthat/test-quality-gate-entrypoint.R
# Açıklama: app.R ve tests/testthat.R icindeki kritik boot/test kontratlarini
# statik olarak korur.
# Windows VM encoding farkliliklarina dayanikli kalmak icin dosyalar ham bayt
# olarak okunur, BOM temizlenir ve birden fazla encoding ile cozulmeye calisilir.
# ==============================================================================

read_repo_text_entrypoint <- function(rel_path) {
  abs_path <- file.path(repo_root_for_tests, rel_path)

  if (!file.exists(abs_path)) {
    stop(sprintf("Dosya bulunamadi: %s", rel_path))
  }

  boyut <- file.info(abs_path)$size
  if (is.na(boyut)) {
    stop(sprintf("Dosya boyutu okunamadi: %s", rel_path))
  }

  raw_bytes <- readBin(abs_path, what = "raw", n = boyut)

  if (length(raw_bytes) >= 3L &&
      identical(as.integer(raw_bytes[1:3]), c(239L, 187L, 191L))) {
    raw_bytes <- raw_bytes[-(1:3)]
  }

  tmp_file <- tempfile(fileext = ".txt")
  on.exit(unlink(tmp_file, force = TRUE), add = TRUE)
  writeBin(raw_bytes, tmp_file)

  for (enc in c("UTF-8", "WINDOWS-1254", "latin1")) {
    txt <- tryCatch(
      paste(readLines(tmp_file, warn = FALSE, encoding = enc), collapse = "\n"),
      error = function(e) NULL
    )

    if (!is.null(txt)) {
      return(enc2utf8(txt))
    }
  }

  stop(sprintf("Dosya okunamadi: %s", rel_path))
}

test_that("app.R boot adimlarini isimlendirilmis boot_step ile sarar", {
  txt <- read_repo_text_entrypoint("app.R")

  expect_true(grepl("boot_step <- function", txt, fixed = TRUE))
  expect_true(grepl('boot_step\\("global\\.R"', txt))
  expect_true(grepl('boot_step\\("ui\\.R"', txt))
  expect_true(grepl('boot_step\\("server\\.R"', txt))
})

test_that("app.R validate_boot_state UI kontratini korur", {
  txt <- read_repo_text_entrypoint("app.R")

  expect_true(grepl("validate_boot_state <- function", txt, fixed = TRUE))
  expect_true(grepl('inherits\\(ui_obj, c\\("shiny.tag", "shiny.tag.list", "html"\\)\\)', txt))
})

test_that("tests/testthat.R repo koku guard ve summary reporter ile calisir", {
  txt <- read_repo_text_entrypoint(file.path("tests", "testthat.R"))

  expect_true(grepl("repo kökünden çalıştırılmalıdır", txt, fixed = TRUE))
  expect_true(grepl('file\\.path\\("tests", "testthat"\\)', txt))
  expect_true(grepl('reporter = "summary"', txt, fixed = TRUE))
  expect_true(grepl("stop_on_warning = TRUE", txt, fixed = TRUE))
})
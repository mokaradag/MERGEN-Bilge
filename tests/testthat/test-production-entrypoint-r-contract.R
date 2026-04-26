# ==============================================================================
# Dosya Yolu: tests/testthat/test-production-entrypoint-r-contract.R
# Aciklama: run_mergen_prod.bat tarafindan cagrilan run_mergen_prod.R dosyasinin
#           gercekten R kodu oldugunu ve uretim boot fonksiyonlarini kullandigini
#           dogrular.
# ==============================================================================

.read_entrypoint_text <- function(path) {
  repo_root <- resolve_repo_root_for_tests()
  full_path <- file.path(repo_root, path)

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

  txt <- gsub("\r\n?|\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

test_that("production BAT calls an R entrypoint that exists", {
  repo_root <- resolve_repo_root_for_tests()

  expect_true(file.exists(file.path(repo_root, "run_mergen_prod.bat")))
  expect_true(file.exists(file.path(repo_root, "run_mergen_prod.R")))

  bat_text <- .read_entrypoint_text("run_mergen_prod.bat")
  expect_true(grepl("run_mergen_prod.R", bat_text, fixed = TRUE))
})

test_that("run_mergen_prod.R is R code, not a copied BAT file", {
  txt <- .read_entrypoint_text("run_mergen_prod.R")

  expect_false(grepl("^@echo off", txt))
  expect_false(grepl("^setlocal EnableExtensions", txt))
  expect_true(grepl('source("app.R"', txt, fixed = TRUE))
  expect_true(grepl("validate_boot_state()", txt, fixed = TRUE))
  expect_true(grepl("run_mergen_app(", txt, fixed = TRUE))
})

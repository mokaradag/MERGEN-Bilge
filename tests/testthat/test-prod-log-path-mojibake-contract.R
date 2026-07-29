testthat::local_edition(3)

test_that("üretim başlatıcısı mojibake log yolunu app logs dizinine yönlendirir", {
  script <- readLines(
    file.path(resolve_repo_root_for_tests(), "run_mergen_prod.R"),
    warn = FALSE,
    encoding = "UTF-8"
  )
  code <- paste(script, collapse = "\n")

  expect_match(code, "mojibake_markers <- intToUtf8", fixed = TRUE)
  expect_match(code, "shortPathName(local_log_dir)", fixed = TRUE)
  expect_match(code, "Sys.setenv(MERGEN_LOG_DIR = local_log_dir)", fixed = TRUE)

  repair_line <- grep(
    "Sys.setenv(MERGEN_LOG_DIR = local_log_dir)",
    script,
    fixed = TRUE
  )
  app_source_line <- grep('source("app.R"', script, fixed = TRUE)

  expect_length(repair_line, 1L)
  expect_length(app_source_line, 1L)
  expect_lt(repair_line, app_source_line)
})

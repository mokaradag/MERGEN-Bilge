# ==============================================================================
# Dosya Yolu: tests/testthat/test-quality-gate-scripts.R
# Açıklama: Repo kalite kapısı betiklerinin kritik sözleşmelerini korur.
# Bu testler uygulama davranışını değil, hardening akışının kendisini korur.
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

test_that("parse_sanity_check repo icindeki test ve script R dosyalarini da kapsar", {
  txt <- read_repo_text("tests/scripts/parse_sanity_check.R")

  expect_true(grepl('list_r_files\\("R"\\)', txt))
  expect_true(grepl('list_r_files\\("tests/testthat"\\)', txt))
  expect_true(grepl('list_r_files\\("tests/scripts"\\)', txt))
  expect_true(grepl('file.path\\("tests", "testthat.R"\\)', txt))
})

test_that("run_ci_local clean child sessioni vanilla modda ve log yakalayarak calistirir", {
  txt <- read_repo_text("tests/scripts/run_ci_local.R")

  expect_true(grepl("--vanilla", txt, fixed = TRUE))
  expect_true(grepl("child_stdout_log", txt, fixed = TRUE))
  expect_true(grepl("child_stderr_log", txt, fixed = TRUE))
  expect_true(grepl("source('tests/testthat.R', encoding = 'UTF-8')", txt, fixed = TRUE))
})

test_that("run_vm_preflight_real boot kontratini ve HEAD-GET fallbackini korur", {
  txt <- read_repo_text("tests/scripts/run_vm_preflight_real.R")

  expect_true(grepl("validate_boot_state()", txt, fixed = TRUE))
  expect_true(grepl('probe_llm_endpoint <- function', txt, fixed = TRUE))
  expect_true(grepl('customrequest = "HEAD"', txt, fixed = TRUE))
  expect_true(grepl('customrequest = "GET"', txt, fixed = TRUE))
})
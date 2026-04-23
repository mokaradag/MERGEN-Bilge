# ==============================================================================
# Dosya Yolu: tests/testthat/test-quality-gate-scripts.R
# Açıklama: Repo kalite kapisi betiklerinin kritik sozlesmelerini korur.
# Onemli not: Windows VM encoding sorunlari nedeniyle bu test dosyasi kaynak
# dosyalari readLines ile okumaz; parse edip yorumlardan bagimsiz kod metni
# uzerinden kontrol yapar.
# ==============================================================================

parse_repo_code_text_scripts <- function(rel_path) {
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

test_that("parse_sanity_check repo icindeki test ve script R dosyalarini da kapsar", {
  txt <- parse_repo_code_text_scripts("tests/scripts/parse_sanity_check.R")

  expect_true(grepl('list_r_files\\("R"\\)', txt))
  expect_true(grepl('list_r_files\\("tests/testthat"\\)', txt))
  expect_true(grepl('list_r_files\\("tests/scripts"\\)', txt))
  expect_true(grepl('file\\.path\\("tests", "testthat\\.R"\\)', txt))
})

test_that("run_ci_local clean child sessioni vanilla modda ve log yakalayarak calistirir", {
  txt <- parse_repo_code_text_scripts("tests/scripts/run_ci_local.R")

  expect_true(grepl("--vanilla", txt, fixed = TRUE))
  expect_true(grepl("child_stdout_log", txt, fixed = TRUE))
  expect_true(grepl("child_stderr_log", txt, fixed = TRUE))
  expect_true(grepl("source\\('tests/testthat\\.R', encoding = 'UTF-8'\\)", txt))
})

test_that("run_vm_preflight_real boot kontratini ve HEAD-GET fallbackini korur", {
  txt <- parse_repo_code_text_scripts("tests/scripts/run_vm_preflight_real.R")

  expect_true(grepl("validate_boot_state()", txt, fixed = TRUE))
  expect_true(grepl("probe_llm_endpoint <- function", txt, fixed = TRUE))
  expect_true(grepl('customrequest = "HEAD"', txt, fixed = TRUE))
  expect_true(grepl('customrequest = "GET"', txt, fixed = TRUE))
})
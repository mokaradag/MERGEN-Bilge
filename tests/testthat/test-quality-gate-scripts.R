# ==============================================================================
# Dosya Yolu: tests/testthat/test-quality-gate-scripts.R
# Açıklama: Repo kalite kapısı betiklerinin kritik sözleşmelerini korur.
# Bu testler uygulama davranışını değil, hardening akışının kendisini korur.
# Windows VM encoding farkliliklarina dayanikli kalmak icin dosyalar ham bayt
# olarak okunur, BOM temizlenir ve birden fazla encoding ile cozulmeye calisilir.
# ==============================================================================

read_repo_text_quality_gate <- function(rel_path) {
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

test_that("parse_sanity_check repo icindeki test ve script R dosyalarini da kapsar", {
  txt <- read_repo_text_quality_gate("tests/scripts/parse_sanity_check.R")

  expect_true(grepl('list_r_files\\("R"\\)', txt))
  expect_true(grepl('list_r_files\\("tests/testthat"\\)', txt))
  expect_true(grepl('list_r_files\\("tests/scripts"\\)', txt))
  expect_true(grepl('file.path\\("tests", "testthat.R"\\)', txt))
})

test_that("run_ci_local clean child sessioni vanilla modda ve log yakalayarak calistirir", {
  txt <- read_repo_text_quality_gate("tests/scripts/run_ci_local.R")

  expect_true(grepl("--vanilla", txt, fixed = TRUE))
  expect_true(grepl("child_stdout_log", txt, fixed = TRUE))
  expect_true(grepl("child_stderr_log", txt, fixed = TRUE))
  expect_true(grepl("source('tests/testthat.R', encoding = 'UTF-8')", txt, fixed = TRUE))
})

test_that("run_vm_preflight_real boot kontratini ve HEAD-GET fallbackini korur", {
  txt <- read_repo_text_quality_gate("tests/scripts/run_vm_preflight_real.R")

  expect_true(grepl("validate_boot_state()", txt, fixed = TRUE))
  expect_true(grepl("probe_llm_endpoint <- function", txt, fixed = TRUE))
  expect_true(grepl('customrequest = "HEAD"', txt, fixed = TRUE))
  expect_true(grepl('customrequest = "GET"', txt, fixed = TRUE))
})
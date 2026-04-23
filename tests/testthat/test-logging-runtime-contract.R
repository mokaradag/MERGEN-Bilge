# ==============================================================================
# Dosya Yolu: tests/testthat/test-logging-runtime-contract.R
# Açıklama: config_logging.R davranışını ayrı bir child R oturumunda kara-kutu
# sözleşme testi ile doğrular. Böylece logger'ın global durumunu test suite
# içine sızdırmadan aktif log dizini, redaction ve hata loglama davranışı
# korunur.
# ==============================================================================

resolve_rscript_for_tests <- function() {
  rscript_bin <- file.path(R.home("bin"), "Rscript")
  if (.Platform$OS.type == "windows") {
    rscript_bin <- paste0(rscript_bin, ".exe")
  }

  if (!file.exists(rscript_bin)) {
    stop(sprintf("Rscript bulunamadı: %s", rscript_bin))
  }

  rscript_bin
}

read_text_file_relaxed <- function(path) {
  if (!file.exists(path)) {
    return("")
  }

  lines <- suppressWarnings(
    readLines(path, warn = FALSE, encoding = "unknown")
  )

  paste(enc2utf8(lines), collapse = "\n")
}

run_logging_probe <- function(log_dir, log_threshold = "debug") {
  dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

  runner_file <- tempfile(pattern = "logging_probe_", fileext = ".R")
  child_stdout_log <- tempfile(pattern = "logging_probe_stdout_", fileext = ".log")
  child_stderr_log <- tempfile(pattern = "logging_probe_stderr_", fileext = ".log")

  on.exit(
    unlink(c(runner_file, child_stdout_log, child_stderr_log), force = TRUE),
    add = TRUE
  )

  normalized_repo <- normalizePath(repo_root_for_tests, winslash = "/", mustWork = TRUE)
  normalized_log_dir <- normalizePath(log_dir, winslash = "/", mustWork = FALSE)

  runner_lines <- c(
    sprintf("setwd(%s)", dQuote(normalized_repo)),
    "options(encoding = 'UTF-8')",
    sprintf(
      "Sys.setenv(MERGEN_LOG_DIR = %s, MERGEN_LOG_THRESHOLD = %s)",
      dQuote(normalized_log_dir),
      dQuote(log_threshold)
    ),
    "assign(",
    "  'redact_sensitive_text',",
    "  function(x) gsub('secret-[0-9]+', '[REDACTED]', x),",
    "  envir = .GlobalEnv",
    ")",
    "source('R/utils_safe_source.R', encoding = 'UTF-8')",
    "safe_source('R/config_logging.R', encoding = 'UTF-8')",
    "log_info('token={token}', token = 'secret-123')",
    "dbg_dump('probe', list(token = 'secret-999'))",
    "shiny_error_handler(simpleError('boom-321'))",
    "cat('OK: logging probe completed\\n')"
  )

  writeLines(enc2utf8(runner_lines), runner_file, useBytes = TRUE)

  exit_status <- system2(
    resolve_rscript_for_tests(),
    args = c("--vanilla", runner_file),
    stdout = child_stdout_log,
    stderr = child_stderr_log
  )

  list(
    status = exit_status,
    stdout = read_text_file_relaxed(child_stdout_log),
    stderr = read_text_file_relaxed(child_stderr_log),
    log_file = file.path(log_dir, sprintf("mergen_%s.log", format(Sys.Date(), "%Y%m%d"))),
    dbg_file = file.path(log_dir, sprintf("ai_debug_%s.log", format(Sys.Date(), "%Y%m%d")))
  )
}

test_that("config_logging child oturumunda aktif log dizinine ve dosyalara yazar", {
  log_dir <- withr::local_tempdir(pattern = "mergen-log-contract-")
  probe <- run_logging_probe(log_dir)

  expect_identical(probe$status, 0L, info = paste(probe$stdout, probe$stderr, sep = "\n"))
  expect_true(file.exists(probe$log_file))
  expect_true(file.exists(probe$dbg_file))
})

test_that("config_logging hassas degerleri redakte eder", {
  log_dir <- withr::local_tempdir(pattern = "mergen-log-redact-")
  probe <- run_logging_probe(log_dir)

  expect_identical(probe$status, 0L, info = paste(probe$stdout, probe$stderr, sep = "\n"))

  log_text <- read_text_file_relaxed(probe$log_file)
  dbg_text <- read_text_file_relaxed(probe$dbg_file)

  expect_false(grepl("secret-123", log_text, fixed = TRUE))
  expect_false(grepl("secret-999", dbg_text, fixed = TRUE))
  expect_true(grepl("\\[REDACTED\\]", log_text))
  expect_true(grepl("\\[REDACTED\\]", dbg_text))
})

test_that("config_logging global hata yakalayıcıyı dosya loguna düşürür", {
  log_dir <- withr::local_tempdir(pattern = "mergen-log-error-")
  probe <- run_logging_probe(log_dir)

  expect_identical(probe$status, 0L, info = paste(probe$stdout, probe$stderr, sep = "\n"))

  log_text <- read_text_file_relaxed(probe$log_file)
  expect_true(grepl("boom-321", log_text, fixed = TRUE))
})
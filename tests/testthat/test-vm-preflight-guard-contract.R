# ==============================================================================
# Dosya Yolu: tests/testthat/test-vm-preflight-guard-contract.R
# Açıklama: run_vm_preflight_real.R betiğinin zorunlu ortam değişkenleri eksik
# olduğunda gerçek DB/LLM adımlarına geçmeden hızlı ve net biçimde durduğunu
# child R oturumunda kara-kutu testi ile doğrular.
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

run_preflight_missing_env_probe <- function() {
  runner_file <- tempfile(pattern = "vm_preflight_probe_", fileext = ".R")
  child_stdout_log <- tempfile(pattern = "vm_preflight_stdout_", fileext = ".log")
  child_stderr_log <- tempfile(pattern = "vm_preflight_stderr_", fileext = ".log")

  on.exit(
    unlink(c(runner_file, child_stdout_log, child_stderr_log), force = TRUE),
    add = TRUE
  )

  normalized_repo <- normalizePath(repo_root_for_tests, winslash = "/", mustWork = TRUE)

  runner_lines <- c(
    sprintf("setwd(%s)", dQuote(normalized_repo)),
    "options(encoding = 'UTF-8')",
    "source('R/utils_safe_source.R', encoding = 'UTF-8')",
    "Sys.unsetenv(c('LOCAL_LLM_ENDPOINT', 'DB_DSN', 'AI_KEYS_MASTER'))",
    "safe_source('tests/scripts/run_vm_preflight_real.R', encoding = 'UTF-8')"
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
    stderr = read_text_file_relaxed(child_stderr_log)
  )
}

test_that("run_vm_preflight_real eksik zorunlu ortam değişkenlerinde hızlı ve net fail verir", {
  probe <- run_preflight_missing_env_probe()
  combined_output <- paste(probe$stdout, probe$stderr, sep = "\n")

  expect_false(identical(probe$status, 0L))
  expect_true(grepl("Eksik ortam değişkenleri", combined_output, fixed = TRUE))
})
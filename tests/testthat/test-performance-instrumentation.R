# ============================================================================== 
# Dosya Yolu: tests/testthat/test-performance-instrumentation.R
# Açıklama: Hafif performans ölçüm yardımcıları sözleşmesi.
# ============================================================================== 

source("../../R/helpers_performance_instrumentation.R")

test_that("performance logging defaults to disabled and can be enabled explicitly", {
  old_env <- Sys.getenv("MERGEN_PERF_LOG", unset = NA_character_)
  old_opt <- getOption("mergen.perf_log")
  on.exit({
    if (is.na(old_env)) Sys.unsetenv("MERGEN_PERF_LOG") else Sys.setenv(MERGEN_PERF_LOG = old_env)
    options(mergen.perf_log = old_opt)
  }, add = TRUE)

  Sys.unsetenv("MERGEN_PERF_LOG")
  options(mergen.perf_log = FALSE)
  expect_false(mergen_perf_enabled())

  Sys.setenv(MERGEN_PERF_LOG = "true")
  expect_true(mergen_perf_enabled())
})

test_that("performance timing returns values and redacts sensitive fields", {
  captured <- character()
  old_log_info <- if (exists("log_info", envir = .GlobalEnv, inherits = FALSE)) get("log_info", envir = .GlobalEnv) else NULL
  old_redact <- if (exists("redact_sensitive_text", envir = .GlobalEnv, inherits = FALSE)) get("redact_sensitive_text", envir = .GlobalEnv) else NULL
  assign("log_info", function(msg, ...) captured <<- c(captured, msg), envir = .GlobalEnv)
  assign("redact_sensitive_text", function(x) gsub("sk-test-secret", "[REDACTED]", x, fixed = TRUE), envir = .GlobalEnv)

  old_env <- Sys.getenv("MERGEN_PERF_LOG", unset = NA_character_)
  on.exit({
    if (is.na(old_env)) Sys.unsetenv("MERGEN_PERF_LOG") else Sys.setenv(MERGEN_PERF_LOG = old_env)
    if (is.null(old_log_info)) rm("log_info", envir = .GlobalEnv) else assign("log_info", old_log_info, envir = .GlobalEnv)
    if (is.null(old_redact)) rm("redact_sensitive_text", envir = .GlobalEnv) else assign("redact_sensitive_text", old_redact, envir = .GlobalEnv)
  }, add = TRUE)

  Sys.setenv(MERGEN_PERF_LOG = "1")
  result <- mergen_perf_time(
    "unit.test",
    { 42L },
    fields = list(api_key = "sk-test-secret", status = "ok")
  )

  expect_identical(result, 42L)
  expect_length(captured, 1L)
  expect_match(captured[[1]], "event=unit.test", fixed = TRUE)
  expect_match(captured[[1]], "elapsed_ms=")
  expect_match(captured[[1]], "api_key=\\[REDACTED\\]")
  expect_match(captured[[1]], "success=TRUE", fixed = TRUE)
})

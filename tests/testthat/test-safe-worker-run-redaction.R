# ==============================================================================
# Dosya Yolu: tests/testthat/test-safe-worker-run-redaction.R
# Aciklama: safe_worker_run() hata mesajinda hassas metni redakte eder.
# ==============================================================================

load_safe_worker_env_for_tests <- function() {
  worker_env <- new.env(parent = globalenv())

  source(
    file.path(repo_root_for_tests, "R", "utils_log_redact.R"),
    encoding = "UTF-8",
    local = worker_env
  )

  source(
    file.path(repo_root_for_tests, "R", "utils_safe_worker_run.R"),
    encoding = "UTF-8",
    local = worker_env
  )

  worker_env
}

test_that("safe_worker_run hassas hata metnini redakte eder", {
  old_ai_key <- Sys.getenv("AI_KEYS_MASTER", unset = NA_character_)

  withr::defer({
    if (is.na(old_ai_key)) {
      Sys.unsetenv("AI_KEYS_MASTER")
    } else {
      Sys.setenv(AI_KEYS_MASTER = old_ai_key)
    }
  })

  Sys.setenv(AI_KEYS_MASTER = "supersekretkey_abcdef1234")

  worker_env <- load_safe_worker_env_for_tests()

  sonuc <- worker_env$safe_worker_run(
    task_fn = function() {
      stop(sprintf(
        "AI anahtari sizdi: %s",
        Sys.getenv("AI_KEYS_MASTER")
      ))
    }
  )

  expect_false(sonuc$ok)
  expect_equal(sonuc$error_code, "worker_error")
  expect_false(grepl("supersekretkey_abcdef1234", sonuc$error_message, fixed = TRUE))
  expect_true(grepl("<AI_KEYS_MASTER:redacted>", sonuc$error_message, fixed = TRUE))
})
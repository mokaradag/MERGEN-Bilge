# ==============================================================================
# Dosya Yolu: tests/testthat/test-config-logging-redaction.R
# Açıklama: config_logging.R içindeki log sarmalayıcılarının ve dbg_dump()
# yardımcısının hassas metni dosyaya yazmadan önce redakte ettiğini doğrular.
# ==============================================================================

test_that("config_logging log sarmalayicilari ve dbg_dump hassas metni redakte eder", {
  tmp_root <- withr::local_tempdir(pattern = "mergen-log-redaction-")
  withr::local_dir(tmp_root)

  old_ai_key <- Sys.getenv("AI_KEYS_MASTER", unset = NA_character_)
  withr::defer({
    if (is.na(old_ai_key)) {
      Sys.unsetenv("AI_KEYS_MASTER")
    } else {
      Sys.setenv(AI_KEYS_MASTER = old_ai_key)
    }
  })

  Sys.setenv(AI_KEYS_MASTER = "supersekretkey_abcdef1234")

  log_env <- new.env(parent = globalenv())

  source(
    file.path(repo_root_for_tests, "R", "utils_log_redact.R"),
    encoding = "UTF-8",
    local = log_env
  )

  source(
    file.path(repo_root_for_tests, "R", "config_logging.R"),
    encoding = "UTF-8",
    local = log_env
  )

  expect_true(exists("log_info", envir = log_env, inherits = FALSE))
  expect_true(exists("log_error", envir = log_env, inherits = FALSE))
  expect_true(exists("dbg_dump", envir = log_env, inherits = FALSE))

  log_env$log_info("AI anahtari: {secret}", secret = "supersekretkey_abcdef1234")
  log_env$log_error("Authorization: Bearer abc123def456ghi789")
  log_env$dbg_dump(
    "ornek_debug",
    list(
      token = "supersekretkey_abcdef1234",
      url = "https://ornek.local/api?api_key=gizli_anahtar_123&x=1"
    )
  )

  expect_true(file.exists(log_env$log_file_path))
  expect_true(file.exists(log_env$dbg_log_path))

  log_text <- paste(
    readLines(log_env$log_file_path, warn = FALSE, encoding = "UTF-8"),
    collapse = "\n"
  )

  dbg_text <- paste(
    readLines(log_env$dbg_log_path, warn = FALSE, encoding = "UTF-8"),
    collapse = "\n"
  )

  expect_false(grepl("supersekretkey_abcdef1234", log_text, fixed = TRUE))
  expect_true(grepl("<AI_KEYS_MASTER:redacted>", log_text, fixed = TRUE))

  expect_false(grepl("abc123def456ghi789", log_text, fixed = TRUE))
  expect_true(grepl("Bearer <redacted>", log_text, fixed = TRUE))

  expect_false(grepl("supersekretkey_abcdef1234", dbg_text, fixed = TRUE))
  expect_true(grepl("<AI_KEYS_MASTER:redacted>", dbg_text, fixed = TRUE))
  expect_true(grepl("api_key=<redacted>", dbg_text, fixed = TRUE))
})
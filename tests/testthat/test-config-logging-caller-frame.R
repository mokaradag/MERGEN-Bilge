# ==============================================================================
# Dosya Yolu: tests/testthat/test-config-logging-caller-frame.R
# Açıklama: config_logging.R icindeki log sarmalayicilarinin glue ifadelerini
# cagirici frame'de cozmeye devam ettigini dogrular.
# ==============================================================================

load_logging_env_for_tests <- function() {
  tmp_root <- withr::local_tempdir(pattern = "mergen-log-caller-frame-")
  withr::local_dir(tmp_root)

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

  log_env
}

read_utf8_text <- function(path) {
  paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}

test_that("log sarmalayicisi cagirici frame degiskenini cozer", {
  log_env <- load_logging_env_for_tests()

  nested_log_call <- function() {
    ic_deger <- "caller-frame-ok"
    log_env$log_info("Deger={ic_deger}")
    invisible(NULL)
  }

  expect_no_error(nested_log_call())
  expect_true(file.exists(log_env$log_file_path))

  log_text <- read_utf8_text(log_env$log_file_path)

  expect_true(grepl("caller-frame-ok", log_text, fixed = TRUE))
  expect_false(grepl("\\{ic_deger\\}", log_text))
})

test_that("log sarmalayicisi wrapper fonksiyon parametresini de cozer", {
  log_env <- load_logging_env_for_tests()

  log_with_user <- function(user_id) {
    log_env$log_warn("Kullanici={user_id}")
    invisible(NULL)
  }

  expect_no_error(log_with_user(42L))
  expect_true(file.exists(log_env$log_file_path))

  log_text <- read_utf8_text(log_env$log_file_path)

  expect_true(grepl("Kullanici=42", log_text, fixed = TRUE))
  expect_false(grepl("\\{user_id\\}", log_text))
})
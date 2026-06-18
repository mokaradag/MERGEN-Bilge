# ==============================================================================
# Dosya Yolu: tests/testthat/test-config-logging-caller-frame.R
# Açıklama: config_logging.R icindeki log sarmalayicilarinin glue ifadelerini
# cagirici frame'de cozmeye devam ettigini dogrular.
# Onemli nokta: working directory degisikligi helper icinde degil, test scope'u
# icinde tutulur; boylece relative logs/ yolu test boyunca gecerli kalir.
# ==============================================================================

load_logging_env_for_tests <- function(log_dir) {
  log_env <- new.env(parent = globalenv())

  withr::local_envvar(c(
    MERGEN_LOG_DIR = log_dir,
    MERGEN_LOG_THRESHOLD = "info"
  ))

  dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

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
  tmp_root <- withr::local_tempdir(pattern = "mergen-log-caller-frame-")
  withr::local_dir(tmp_root)

  test_log_dir <- file.path(tmp_root, "logs-case-1")
  log_env <- load_logging_env_for_tests(test_log_dir)

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
  tmp_root <- withr::local_tempdir(pattern = "mergen-log-caller-frame-")
  withr::local_dir(tmp_root)

  test_log_dir <- file.path(tmp_root, "logs-case-2")
  log_env <- load_logging_env_for_tests(test_log_dir)

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

test_that("gunluk dosya appender'i uzun calisan surecte tarihi yeniden cozer", {
  tmp_root <- withr::local_tempdir(pattern = "mergen-log-daily-rollover-")
  withr::local_dir(tmp_root)

  test_log_dir <- file.path(tmp_root, "logs-case-rollover")
  current_date <- as.Date("2026-06-12")

  withr::local_options(list(
    mergen.log.date_provider = function() current_date
  ))

  log_env <- load_logging_env_for_tests(test_log_dir)

  log_env$log_info("ilk gun")
  first_log <- file.path(test_log_dir, "mergen_20260612.log")
  expect_true(file.exists(first_log))
  expect_true(grepl("ilk gun", read_utf8_text(first_log), fixed = TRUE))

  current_date <- as.Date("2026-06-17")
  log_env$log_info("ikinci gun")

  second_log <- file.path(test_log_dir, "mergen_20260617.log")
  expect_true(file.exists(second_log))
  expect_true(grepl("ikinci gun", read_utf8_text(second_log), fixed = TRUE))
})

# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-manager-state-runtime-contract.R
# Açıklama: Dosya Yönetimi state/refresh runtime extraction sözleşmesini doğrular.
# ==============================================================================

.read_repo_text_file_manager_state_runtime <- function(path) {
  repo_root <- resolve_repo_root_for_tests()
  full_path <- file.path(repo_root, path)

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\\r\\n?|\\r", "\\n", txt, perl = TRUE)
  enc2utf8(txt)
}

.load_file_manager_state_runtime_helpers <- function() {
  repo_root <- resolve_repo_root_for_tests()
  helper_env <- new.env(parent = globalenv())

  source(
    file.path(repo_root, "R", "helpers_file_manager_state_runtime.R"),
    encoding = "UTF-8",
    local = helper_env
  )

  helper_env
}

test_that("file manager state runtime helper factoryleri source edilebilir", {
  env <- .load_file_manager_state_runtime_helpers()

  expect_true(exists("fm_create_file_action_helpers", envir = env, mode = "function", inherits = FALSE))
  expect_true(exists("fm_create_refresh_from_user_folder", envir = env, mode = "function", inherits = FALSE))
})

test_that("file manager refresh ve state mutasyonları modülden helper dosyasına taşınır", {
  module_txt <- .read_repo_text_file_manager_state_runtime("R/module_file_manager.R")
  helper_txt <- .read_repo_text_file_manager_state_runtime("R/helpers_file_manager_state_runtime.R")

  expect_true(grepl("fm_create_file_action_helpers\\(", module_txt, perl = TRUE))
  expect_true(grepl("fm_create_refresh_from_user_folder\\(", module_txt, perl = TRUE))

  expect_true(grepl("fm_create_file_action_helpers <- function", helper_txt, fixed = TRUE))
  expect_true(grepl("fm_create_refresh_from_user_folder <- function", helper_txt, fixed = TRUE))
  expect_true(grepl("sync_file_to_context <- function", helper_txt, fixed = TRUE))
  expect_true(grepl("remove_file_by_name <- function", helper_txt, fixed = TRUE))
  expect_true(grepl("process_uploaded_file <- function", helper_txt, fixed = TRUE))

  expect_false(grepl("sync_file_to_context <- function", module_txt, fixed = TRUE))
  expect_false(grepl("remove_file_by_name <- function", module_txt, fixed = TRUE))
  expect_false(grepl("process_uploaded_file <- function", module_txt, fixed = TRUE))
  expect_false(grepl("refresh_from_user_folder <- function", module_txt, fixed = TRUE))
})

test_that("file manager refresh helper stale request guard sözleşmesini korur", {
  helper_txt <- .read_repo_text_file_manager_state_runtime("R/helpers_file_manager_state_runtime.R")

  expect_true(grepl("request_id <- refresh_guard\\$next_id\\(\\)", helper_txt, perl = TRUE))
  expect_true(grepl("!refresh_guard\\$is_latest\\(request_id\\)", helper_txt, perl = TRUE))
  expect_true(grepl("refresh_error_stale", helper_txt, fixed = TRUE))
  expect_true(grepl("session\\$userData\\$current_session_files <- previous_state\\$session_registry", helper_txt, perl = TRUE))
})

test_that("file manager upload observer SSO hazır olmadan kalıcı dosya state'i mutasyona uğratmaz", {
  module_txt <- .read_repo_text_file_manager_state_runtime("R/module_file_manager.R")

  expect_true(grepl("if \\(isTRUE\\(SSO_ENABLED\\) && !is_auth_ready\\(\\)\\)", module_txt, perl = TRUE))
  expect_true(grepl("Kimlik doğrulama tamamlanmadan dosya yüklenemez", module_txt, fixed = TRUE))
  expect_true(grepl("upload_skip", module_txt, fixed = TRUE))
})
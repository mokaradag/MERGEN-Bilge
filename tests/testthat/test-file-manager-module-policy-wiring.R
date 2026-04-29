# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-manager-module-policy-wiring.R
# Açıklama: Dosya Yönetimi modülünün policy helper ve refresh race guard
#           sözleşmesini statik olarak doğrular.
# ==============================================================================

.read_repo_text_file_manager_module <- function(path) {
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

  txt <- gsub("\r\n?|\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

test_that("file manager UI ve server upload limit kararını helper üzerinden alıyor", {
  ui_txt <- .read_repo_text_file_manager_module("R/module_file_manager_ui.R")
  server_txt <- .read_repo_text_file_manager_module("R/module_file_manager.R")

  expect_true(grepl("fm_upload_limit_mb\\(\\)", ui_txt, perl = TRUE))
  expect_true(grepl("fm_upload_limit_bytes\\(upload_limit_mb\\)", ui_txt, perl = TRUE))
  expect_true(grepl("max_mb <- fm_upload_limit_mb\\(\\)", server_txt, perl = TRUE))
})

test_that("file manager modülü attach ve uzantı policy kararlarını helper üzerinden alıyor", {
  txt <- .read_repo_text_file_manager_module("R/module_file_manager.R")

  expect_true(grepl("fm_attach_rule_hint_text\\(", txt, perl = TRUE))
  expect_true(grepl("fm_summarization_allowed_extensions\\(\\)", txt, perl = TRUE))
  expect_true(grepl("fm_normal_allowed_extensions\\(\\)", txt, perl = TRUE))
  expect_true(grepl("fm_resolve_allowed_extensions\\(", txt, perl = TRUE))

  expect_false(
    grepl(
      "build_attach_rule_hint_text[\\s\\S]*Seçim kuralı: MCP açıkken yalnızca 1 dosya eklenebilir\\.",
      txt,
      perl = TRUE
    )
  )
})

test_that("file manager kimlik ve saf biçimlendirme kararlarını helper üzerinden alıyor", {
  txt <- .read_repo_text_file_manager_module("R/module_file_manager.R")

  expect_true(grepl("resolve_effective_user_id\\(", txt, perl = TRUE))
  expect_true(grepl("fm_normalize_user_id\\(", txt, perl = TRUE))
  expect_true(grepl("fm_valid_user_id\\(uid\\)", txt, perl = TRUE))
  expect_true(grepl("fm_file_ext_icon_html\\(ext\\)", txt, perl = TRUE))
  expect_true(grepl("fm_format_file_timestamp\\(", txt, perl = TRUE))

  expect_false(grepl(
    "session_uid\\s+<-\\s+session\\$userData\\$user_id\\s*%\\|\\|%",
    txt,
    perl = TRUE
  ))
})

test_that("file manager tablo satırı üretimini helper dosyasına devreder", {
  txt <- .read_repo_text_file_manager_module("R/module_file_manager.R")

  expect_true(grepl("fm_empty_files_df\\(\\)", txt, perl = TRUE))
  expect_true(grepl("fm_build_file_table_row\\(", txt, perl = TRUE))
  expect_false(grepl("build_file_actions_html <- function", txt, fixed = TRUE))
  expect_false(grepl("build_attach_cell_html <- function", txt, fixed = TRUE))
  expect_false(grepl("Dosya_Adi = character\\(0\\)", txt, perl = TRUE))
})

test_that("file manager persisted refresh eski istekleri state'e uygulamıyor", {
  txt <- .read_repo_text_file_manager_module("R/module_file_manager.R")
  guard_txt <- .read_repo_text_file_manager_module("R/helpers_file_manager_refresh_guard.R")

  expect_true(grepl("fm_create_refresh_request_guard <- function", guard_txt, fixed = TRUE))
  expect_true(grepl("refresh_guard <- fm_create_refresh_request_guard\\(\\)", txt, perl = TRUE))
  expect_true(grepl("request_id <- refresh_guard\\$next_id\\(\\)", txt, perl = TRUE))
  expect_true(grepl("!refresh_guard\\$is_latest\\(request_id\\)", txt, perl = TRUE))
  expect_true(grepl("refresh_error_stale", txt, fixed = TRUE))

  expect_false(grepl("refresh_request_seq <- 0L", txt, fixed = TRUE))
  expect_false(grepl("next_refresh_request_id <- function", txt, fixed = TRUE))
  expect_false(grepl("is_latest_refresh_request <- function", txt, fixed = TRUE))
  expect_false(grepl("is_latest_refresh_request\\s*\\(", txt, perl = TRUE))
})
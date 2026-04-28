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

test_that("file manager modülü upload limit kararını helper üzerinden alıyor", {
  txt <- .read_repo_text_file_manager_module("R/module_file_manager.R")

  expect_true(grepl("fm_upload_limit_mb\\(\\)", txt, perl = TRUE))
  expect_true(grepl("fm_upload_limit_bytes\\(upload_limit_mb\\)", txt, perl = TRUE))
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

test_that("file manager persisted refresh eski istekleri state'e uygulamıyor", {
  txt <- .read_repo_text_file_manager_module("R/module_file_manager.R")

  expect_true(grepl("refresh_request_seq <- 0L", txt, fixed = TRUE))
  expect_true(grepl("next_refresh_request_id <- function", txt, fixed = TRUE))
  expect_true(grepl("is_latest_refresh_request <- function", txt, fixed = TRUE))
  expect_true(grepl("request_id <- next_refresh_request_id\\(\\)", txt, perl = TRUE))
  expect_true(grepl("!is_latest_refresh_request\\(request_id\\)", txt, perl = TRUE))
  expect_true(grepl("refresh_error_stale", txt, fixed = TRUE))
})
# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-manager-ui-refactor-contract.R
# Açıklama: Dosya Yönetimi UI tanımının server modülünden ayrı tutulduğunu
#           ve public fileManagerUI sözleşmesinin korunduğunu doğrular.
# ==============================================================================

.read_repo_text_file_manager_ui_refactor <- function(path) {
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

test_that("fileManagerUI public fonksiyonu ayrı UI dosyasında tanımlıdır", {
  ui_text <- .read_repo_text_file_manager_ui_refactor("R/module_file_manager_ui.R")
  server_text <- .read_repo_text_file_manager_ui_refactor("R/module_file_manager.R")

  expect_true(grepl("fileManagerUI <- function\\(id\\)", ui_text, perl = TRUE))
  expect_true(grepl("fileManagerServer <- function\\(", server_text, perl = TRUE))
  expect_false(grepl("fileManagerUI <- function\\(id\\)", server_text, perl = TRUE))
})

test_that("file manager UI upload limit helper sözleşmesini kullanır", {
  ui_text <- .read_repo_text_file_manager_ui_refactor("R/module_file_manager_ui.R")

  expect_true(grepl("fm_upload_limit_mb\\(\\)", ui_text, perl = TRUE))
  expect_true(grepl("fm_upload_limit_bytes\\(upload_limit_mb\\)", ui_text, perl = TRUE))
  expect_true(grepl("change\\.mergenUploadLimit", ui_text, perl = TRUE))
  expect_true(grepl("bulk_upload_client_error", ui_text, fixed = TRUE))
})
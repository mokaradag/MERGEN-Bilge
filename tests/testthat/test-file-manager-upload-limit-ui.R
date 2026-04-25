# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-manager-upload-limit-ui.R
# Açıklama: Dosya Yönetimi UI tarafında büyük dosyaları Shiny upload başlamadan
# reddeden istemci tarafı sınır kontrolünün varlığını doğrular.
# ==============================================================================

.find_repo_root <- function() {
  adaylar <- unique(normalizePath(
    c(
      getwd(),
      file.path(getwd(), ".."),
      file.path(getwd(), "..", "..")
    ),
    winslash = "/",
    mustWork = FALSE
  ))

  for (aday in adaylar) {
    if (file.exists(file.path(aday, "app.R")) &&
        dir.exists(file.path(aday, "R"))) {
      return(aday)
    }
  }

  stop("Repo kökü bulunamadı.", call. = FALSE)
}

.repo_root <- .find_repo_root()

.read_utf8 <- function(path) {
  readLines(path, encoding = "UTF-8", warn = FALSE)
}

test_that("file manager UI istemci tarafı upload boyut kontrolü içeriyor", {
  path <- file.path(.repo_root, "R", "module_file_manager.R")
  txt <- paste(.read_utf8(path), collapse = "\n")

  expect_true(grepl("bulk_upload_client_error", txt, fixed = TRUE))
  expect_true(grepl("maxBytes", txt, fixed = TRUE))
  expect_true(grepl("files[i].size > maxBytes", txt, fixed = TRUE))
  expect_true(grepl("Dosya başına en fazla", txt, fixed = TRUE))
})
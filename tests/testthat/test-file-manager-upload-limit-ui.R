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

.read_text_quiet <- function(path) {
  size <- suppressWarnings(file.info(path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(path, open = "rb")
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

.has_text <- function(haystack, needle) {
  isTRUE(suppressWarnings(grepl(
    needle,
    haystack,
    fixed = TRUE,
    useBytes = TRUE
  )))
}

test_that("file manager UI istemci tarafı upload boyut kontrolü içeriyor", {
  path <- file.path(.repo_root, "R", "module_file_manager_ui.R")
  txt <- .read_text_quiet(path)

  expect_true(.has_text(txt, "bulk_upload_client_error"))
  expect_true(.has_text(txt, "maxBytes"))
  expect_true(.has_text(txt, "files[i].size > maxBytes"))
  expect_true(.has_text(txt, "Dosya başına en fazla"))
})
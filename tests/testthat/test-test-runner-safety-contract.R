# ==============================================================================
# Dosya Yolu: tests/testthat/test-test-runner-safety-contract.R
# Açıklama: tests/testthat.R giriş noktasının kendi başına güvenli olduğunu
# doğrular. Test koşumu Shiny app'i veya future cluster'ı başlatmamalıdır.
# ==============================================================================

.read_repo_file_bytes_for_runner_contract <- function(path) {
  repo_root <- resolve_repo_root_for_tests()
  full_path <- file.path(repo_root, path)

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  if (length(raw_data) >= 3L &&
      identical(as.integer(raw_data[1:3]), c(239L, 187L, 191L))) {
    raw_data <- raw_data[-(1:3)]
  }

  raw_data <- raw_data[raw_data != as.raw(0)]

  txt <- rawToChar(raw_data, multiple = FALSE)
  Encoding(txt) <- "bytes"

  txt <- gsub("\r\n", "\n", txt, fixed = TRUE, useBytes = TRUE)
  txt <- gsub("\r", "\n", txt, fixed = TRUE, useBytes = TRUE)

  txt
}

test_that("testthat.R app autorun ve future cluster bayraklarını kapatır", {
  txt <- .read_repo_file_bytes_for_runner_contract("tests/testthat.R")

  expect_true(
    grepl("Sys.setenv", txt, fixed = TRUE, useBytes = TRUE),
    info = "tests/testthat.R içinde Sys.setenv çağrısı bulunmalı."
  )

  expect_true(
    grepl("MERGEN_RUN_APP\\s*=\\s*['\"]false['\"]", txt, perl = TRUE, useBytes = TRUE),
    info = "tests/testthat.R içinde MERGEN_RUN_APP='false' açıkça ayarlanmalı."
  )

  expect_true(
    grepl("MERGEN_DISABLE_FUTURES\\s*=\\s*['\"]true['\"]", txt, perl = TRUE, useBytes = TRUE),
    info = "tests/testthat.R içinde MERGEN_DISABLE_FUTURES='true' açıkça ayarlanmalı."
  )
})
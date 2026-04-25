# ==============================================================================
# Dosya Yolu: tests/testthat/test-production-env-policy-contract.R
# Açıklama: Üretim VM için kritik environment policy sözleşmelerini doğrular.
# Uygulamayı başlatmaz; app.R/global.R metin sözleşmelerini statik inceler.
# ==============================================================================

.read_repo_file_bytes_for_env_policy <- function(path) {
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

test_that("app.R MERGEN_RUN_APP için açık truthy/falsy parser kullanır", {
  txt <- .read_repo_file_bytes_for_env_policy("app.R")

  expect_true(
    grepl(".env_flag_is_true <- function", txt, fixed = TRUE, useBytes = TRUE),
    info = "app.R içinde .env_flag_is_true helper'ı korunmalı."
  )

  expect_true(
    grepl('c("1", "true", "t", "yes", "y", "on")', txt, fixed = TRUE, useBytes = TRUE),
    info = "Truthy değer listesi açık olmalı."
  )

  expect_true(
    grepl('c("0", "false", "f", "no", "n", "off")', txt, fixed = TRUE, useBytes = TRUE),
    info = "Falsy değer listesi açık olmalı."
  )

  expect_true(
    grepl("auto_run <- .env_flag_is_true", txt, fixed = TRUE, useBytes = TRUE),
    info = "MERGEN_RUN_APP doğrudan as.logical ile değil .env_flag_is_true ile yorumlanmalı."
  )
})

test_that("global.R upload limitini üretim profilinde 25 MB üstüne çıkarmaz", {
  txt <- .read_repo_file_bytes_for_env_policy("global.R")

  expect_true(
    grepl('Sys.getenv("MERGEN_UPLOAD_MAX_MB", "25")', txt, fixed = TRUE, useBytes = TRUE),
    info = "Varsayılan upload limiti 25 MB olmalı."
  )

  expect_true(
    grepl("mergen_upload_max_mb <- min(mergen_upload_max_mb, 25L)", txt, fixed = TRUE, useBytes = TRUE),
    info = "Üretim profili MERGEN_UPLOAD_MAX_MB değerini 25 MB üstüne çıkarmamalı."
  )

  expect_true(
    grepl("shiny.maxRequestSize", txt, fixed = TRUE, useBytes = TRUE),
    info = "Shiny HTTP upload seviyesi de merkezi upload limitiyle ayarlanmalı."
  )

  expect_true(
    grepl("mergen.upload_max_mb", txt, fixed = TRUE, useBytes = TRUE),
    info = "Uygulama içi doğrulama için mergen.upload_max_mb option'ı korunmalı."
  )
})
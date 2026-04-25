# ==============================================================================
# Dosya Yolu: tests/testthat/test-global-source-manifest-contract.R
# Açıklama: global.R source manifestinin kritik üretim yardımcılarını doğru sırada
# yüklediğini doğrular. Uygulamayı başlatmaz; statik ve warning-safe çalışır.
# ==============================================================================

.read_repo_file_bytes_for_manifest_contract <- function(path) {
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

.byte_pos <- function(pattern, txt) {
  pos <- regexpr(pattern, txt, fixed = TRUE, useBytes = TRUE)[1]
  if (is.na(pos) || pos < 0L) NA_integer_ else as.integer(pos)
}

test_that("global.R kritik helper'ları beklenen sırada source eder", {
  txt <- .read_repo_file_bytes_for_manifest_contract("global.R")

  expected_order <- c(
    'safe_source("R/config_packages.R"',
    'safe_source("R/utils_common.R"',
    'safe_source("R/config_logging.R"',
    'safe_source("R/utils_rate_limiter.R"',
    'safe_source("R/helpers_worker_monitor.R"',
    'safe_source("R/utils_path_helpers.R"',
    'safe_source("R/utils_safe_path.R"',
    'safe_source("R/utils_atomic_write.R"',
    'safe_source("R/utils_upload_validator.R"',
    'safe_source("R/utils_log_redact.R"',
    'safe_source("R/utils_session_cleanup.R"',
    'safe_source("R/utils_safe_worker_run.R"',
    'safe_source("R/utils_file_index.R"',
    'safe_source("R/utils_excel_reader.R"'
  )

  positions <- vapply(expected_order, .byte_pos, integer(1), txt = txt)

  expect_false(
    any(is.na(positions)),
    info = paste(
      "global.R içinde eksik source kayıtları:",
      paste(expected_order[is.na(positions)], collapse = ", ")
    )
  )

  expect_true(
    all(diff(positions) > 0L),
    info = paste(
      "global.R kritik helper source sırası bozulmuş görünüyor:",
      paste(expected_order, collapse = " -> ")
    )
  )
})

test_that("global.R future cluster test modunda başlatılmaz sözleşmesini korur", {
  txt <- .read_repo_file_bytes_for_manifest_contract("global.R")

  expect_true(
    grepl("MERGEN_DISABLE_FUTURES", txt, fixed = TRUE, useBytes = TRUE),
    info = "global.R test/bootstrap koşumunda MERGEN_DISABLE_FUTURES bayrağını dikkate almalı."
  )

  expect_true(
    grepl("future::plan(future::sequential)", txt, fixed = TRUE, useBytes = TRUE),
    info = "MERGEN_DISABLE_FUTURES aktifken future sequential plana düşmeli."
  )

  expect_true(
    grepl("init_future_cluster()", txt, fixed = TRUE, useBytes = TRUE),
    info = "Üretim koşumunda future cluster başlatma yolu korunmalı."
  )
})
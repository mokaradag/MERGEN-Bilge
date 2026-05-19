# ==============================================================================
# Dosya Yolu: tests/testthat/test-global-source-manifest-contract.R
# Açıklama: global.R boot sözleşmesini ve manifest tabanlı kritik kaynak sırasını
#           doğrular. Uygulamayı başlatmaz; statik ve warning-safe çalışır.
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

test_that("global.R manifest bootstrap ve güvenli yükleme kapısını korur", {
  txt <- .read_repo_file_bytes_for_manifest_contract("global.R")

  expected_tokens <- c(
    'safe_source("R/bootstrap_source_manifest.R", encoding = "UTF-8")',
    'paths = "R/config_source_manifest.R"',
    'safe_source("R/config_source_manifest.R", encoding = "UTF-8")',
    "source_manifest_validate_config_objects()",
    "source_manifest_current_paths <- source_manifest_get_runtime_paths()",
    "source_manifest_validate(",
    "source_manifest_load(source_manifest_group_1_paths)",
    "source_manifest_load(source_manifest_after_future_paths)"
  )

  found <- vapply(
    expected_tokens,
    function(token) grepl(token, txt, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )

  expect_true(
    all(found),
    info = paste(
      "global.R manifest boot/yükleme sözleşmesi eksik:",
      paste(expected_tokens[!found], collapse = ", ")
    )
  )
})

test_that("runtime manifest kritik helper'ları beklenen sırada içerir", {
  expected_order <- c(
    "R/config_packages.R",
    "R/utils_common.R",
    "R/utils_text_encoding.R",
    "R/config_logging.R",
    "R/utils_rate_limiter.R",
    "R/helpers_worker_monitor.R",,
    "R/utils_path_helpers.R",
    "R/utils_safe_path.R",
    "R/utils_atomic_write.R",
    "R/utils_upload_validator.R",
    "R/utils_log_redact.R",
    "R/utils_session_cleanup.R",
    "R/utils_safe_worker_run.R",
    "R/utils_file_index.R",
    "R/utils_excel_reader.R"
  )

  expect_source_manifest_order_for_tests(
    expected_order,
    label = "Runtime manifest kritik helper source sırası bozulmuş:"
  )
})

test_that("runtime manifest file store helper sırasını korur", {
  expect_source_manifest_order_for_tests(
    c(
      "R/config_file_store.R",
      "R/config_file_store_index_mutation.R",
      "R/config_file_store_listing_helpers.R",
      "R/config_file_store_registry.R"
    ),
    label = "File store manifest source sırası bozulmuş:"
  )
})

test_that("runtime manifest MCP bootstrap doğrulamasını destek helper'larından sonra çalıştırır", {
  expect_source_manifest_order_for_tests(
    c(
      "R/helpers_mcp_context.R",
      "R/helpers_mcp_table_readers.R",
      "R/helpers_mcp_file_resolver.R",
      "R/helpers_mcp_schema_helpers.R",
      "R/helpers_mcp_basic_tools.R",
      "R/helpers_mcp_chart_tools.R",
      "R/helpers_mcp_analyze_visualize.R",
      "R/helpers_mcp_bootstrap.R",
      "R/helpers_mcp_tools.R"
    ),
    label = "MCP manifest source sırası bozulmuş:"
  )
})

test_that("runtime manifest welcome ekranı kaynaklarını server_welcome_handlers öncesinde içerir", {
  expect_source_manifest_order_for_tests(
    c(
      "R/welcome_screen_modern.R",
      "welcome_screen.R",
      "R/server_welcome_handlers.R"
    ),
    label = "Welcome screen kaynak sırası bozulmuş:"
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
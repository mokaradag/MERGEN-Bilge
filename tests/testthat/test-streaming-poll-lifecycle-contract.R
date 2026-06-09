# ==============================================================================
# Dosya Yolu: tests/testthat/test-streaming-poll-lifecycle-contract.R
# Açıklama: True streaming yoklama döngüsü saf karar yardımcılarının
#           (R/helpers_streaming_poll_lifecycle.R) handler'dan ayrıldığını,
#           kaynak sırasını ve handler'ın artık satır sınıflandırma /
#           reasoning geri kazanım mantığını inline taşımadığını doğrular.
# ==============================================================================

.read_repo_text_stream_poll <- function(rel_path) {
  abs_path <- file.path(repo_root_for_tests, rel_path)

  if (!file.exists(abs_path)) {
    stop(sprintf("Dosya bulunamadı: %s", rel_path), call. = FALSE)
  }

  size <- suppressWarnings(file.info(abs_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(abs_path, open = "rb")
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

.source_stream_poll_env <- function() {
  poll_env <- new.env(parent = globalenv())

  poll_env$`%||%` <- function(x, y) {
    if (is.null(x) || length(x) == 0) y else x
  }

  source(
    file.path(repo_root_for_tests, "R", "helpers_streaming_poll_lifecycle.R"),
    encoding = "UTF-8",
    local = poll_env
  )

  poll_env
}

test_that("helpers_streaming_poll_lifecycle.R exists and exposes extracted helpers", {
  helper_path <- file.path(
    repo_root_for_tests, "R", "helpers_streaming_poll_lifecycle.R"
  )

  expect_true(
    file.exists(helper_path),
    info = "R/helpers_streaming_poll_lifecycle.R dosyası eklenmelidir."
  )

  poll_env <- .source_stream_poll_env()

  expected_functions <- c(
    "mergen_stream_poll_interval_ms",
    "mergen_stream_persist_delay",
    "mergen_stream_classify_poll_lines",
    "mergen_stream_reasoning_recovery_plan"
  )

  for (fn in expected_functions) {
    expect_true(
      exists(fn, envir = poll_env, mode = "function", inherits = FALSE),
      info = sprintf("Eksik streaming poll lifecycle helper: %s", fn)
    )
  }
})

test_that("runtime manifest sources poll lifecycle helper after abort helper, before handler", {
  expect_source_manifest_order_for_tests(
    c(
      "R/helpers_streaming_abort_lifecycle.R",
      "R/helpers_streaming_poll_lifecycle.R",
      "R/server_handler_true_streaming.R"
    ),
    label = "Kaynak sırası abort -> poll -> true_streaming handler olmalıdır:"
  )
})

test_that("true streaming handler delegates poll decisions to pure helpers", {
  handler_txt <- .read_repo_text_stream_poll("R/server_handler_true_streaming.R")

  required_delegations <- c(
    "mergen_stream_poll_interval_ms(",
    "mergen_stream_persist_delay(",
    "mergen_stream_classify_poll_lines(",
    "mergen_stream_reasoning_recovery_plan(",
    "decode_fn = decode_stream_delta_payload",
    "normalize_fn = normalize_llm_scalar_content"
  )

  for (pattern in required_delegations) {
    expect_true(
      grepl(pattern, handler_txt, fixed = TRUE),
      info = sprintf(
        "server_handler_true_streaming.R saf poll helper delegasyonunu korumalıdır: %s",
        pattern
      )
    )
  }
})

test_that("true streaming handler no longer owns inline poll classification/recovery logic", {
  handler_txt <- .read_repo_text_stream_poll("R/server_handler_true_streaming.R")

  forbidden_inline_logic <- c(
    "delta_batch <- c(delta_batch",
    "reasoning_batch <- c(reasoning_batch",
    "payload_type <- as.character(payload$type",
    "startsWith(result_reasoning",
    "mergen_stream_poll_interval_ms <- function",
    "mergen_stream_persist_delay <- function",
    "mergen_stream_classify_poll_lines <- function",
    "mergen_stream_reasoning_recovery_plan <- function"
  )

  for (pattern in forbidden_inline_logic) {
    expect_false(
      grepl(pattern, handler_txt, fixed = TRUE),
      info = sprintf(
        "Bu mantık artık R/helpers_streaming_poll_lifecycle.R içinde olmalıdır: %s",
        pattern
      )
    )
  }
})

test_that("helpers_streaming_poll_lifecycle.R remains side-effect-free", {
  txt <- .read_repo_text_stream_poll("R/helpers_streaming_poll_lifecycle.R")

  expect_false(
    grepl("observeEvent\\s*\\(|renderUI\\s*\\(|shiny::runApp|sendCustomMessage", txt, perl = TRUE),
    info = "Streaming poll helper dosyası Shiny observer/render/mesaj içermemelidir."
  )

  expect_false(
    grepl("dbConnect\\s*\\(|odbc::", txt, perl = TRUE),
    info = "Streaming poll helper dosyası canlı DB bağlantısı açmamalıdır."
  )

  expect_false(
    grepl("file\\.create\\s*\\(|unlink\\s*\\(|readLines\\s*\\(|writeLines\\s*\\(", txt, perl = TRUE),
    info = "Streaming poll helper dosyası dosya sistemi yan etkisi içermemelidir."
  )

  expect_false(
    grepl("future_promise|tracked_future_promise|future::", txt, perl = TRUE),
    info = "Streaming poll helper dosyası worker/promise başlatmamalıdır."
  )
})

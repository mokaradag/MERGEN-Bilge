# ==============================================================================
# Dosya Yolu: tests/testthat/test-sse-worker-export-contract.R
# Açıklama: Gerçek SSE işçi akışı için global.R ön-ısıtma export listesi ile
#           tracked_future_promise globals sözleşmesinin aynı kritik yardımcıları
#           taşıdığını doğrular. Uygulamayı başlatmaz.
# ==============================================================================

.read_repo_text_for_sse_contract <- function(path) {
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
  Encoding(txt) <- "UTF-8"
  txt <- enc2utf8(txt)
  txt <- gsub("\r\n?|\r", "\n", txt, perl = TRUE)

  txt
}

.expect_text_contains_all <- function(text, expected, context_label) {
  found <- vapply(
    expected,
    function(item) grepl(item, text, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )

  expect_true(
    all(found),
    info = paste(
      context_label,
      "Eksik kayıtlar:",
      paste(expected[!found], collapse = ", ")
    )
  )
}

test_that("global.R SSE worker prewarm export listesi reasoning/stop/override helper'larını içerir", {
  global_text <- .read_repo_text_for_sse_contract("global.R")

  expected_exports <- c(
    '"append_stream_delta_line"',
    '"append_stream_reasoning_line"',
    '"streaming_should_stop"',
    '"apply_model_request_overrides"',
    '"merge_named_list_deep"',
    '"call_local_llm_sse_worker"'
  )

  .expect_text_contains_all(
    global_text,
    expected_exports,
    "global.R clusterExport varlist sözleşmesi bozuldu."
  )
})

test_that("true streaming tracked_future globals aynı kritik SSE helper sözleşmesini taşır", {
  streaming_text <- .read_repo_text_for_sse_contract("R/server_handler_true_streaming.R")

  expected_globals <- c(
    "call_local_llm_sse_worker = call_local_llm_sse_worker",
    "apply_model_request_overrides = apply_model_request_overrides",
    "append_stream_delta_line = append_stream_delta_line",
    "append_stream_reasoning_line = append_stream_reasoning_line",
    "extract_llm_delta_bundle = extract_llm_delta_bundle",
    "parse_llm_sse_event = parse_llm_sse_event"
  )

  .expect_text_contains_all(
    streaming_text,
    expected_globals,
    "server_handler_true_streaming.R tracked_future globals sözleşmesi bozuldu."
  )
})
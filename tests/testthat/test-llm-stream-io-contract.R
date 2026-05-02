# ==============================================================================
# Dosya Yolu: tests/testthat/test-llm-stream-io-contract.R
# Açıklama: SSE akış dosyası satır protokolü yardımcılarının davranışını korur.
# ==============================================================================

local({
  if (!exists("append_stream_delta_line", envir = globalenv(), inherits = FALSE) ||
      !exists("decode_stream_delta_payload", envir = globalenv(), inherits = FALSE)) {
    source(
      file.path(repo_root_for_tests, "R", "helpers_llm_stream_io.R"),
      encoding = "UTF-8",
      local = globalenv()
    )
  }
})

.read_stream_lines <- function(path) {
  raw_lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  lapply(raw_lines, function(line) {
    jsonlite::fromJSON(line, simplifyVector = FALSE)
  })
}

test_that("append_stream_delta_line UTF-8 metni base64 satırına yazar", {
  stream_path <- tempfile("stream_io_delta_", fileext = ".jsonl")
  on.exit(try(unlink(stream_path, force = TRUE), silent = TRUE), add = TRUE)

  append_stream_delta_line(stream_path, "Merhaba İğdır")

  payloads <- .read_stream_lines(stream_path)

  expect_length(payloads, 1L)
  expect_identical(payloads[[1]]$type, "delta")
  expect_identical(decode_stream_delta_payload(payloads[[1]]), "Merhaba İğdır")
})

test_that("append_stream_reasoning_line reasoning satır tipini korur", {
  stream_path <- tempfile("stream_io_reasoning_", fileext = ".jsonl")
  on.exit(try(unlink(stream_path, force = TRUE), silent = TRUE), add = TRUE)

  append_stream_reasoning_line(stream_path, "Önce düşünüyorum.")

  payloads <- .read_stream_lines(stream_path)

  expect_length(payloads, 1L)
  expect_identical(payloads[[1]]$type, "reasoning_delta")
  expect_identical(decode_stream_delta_payload(payloads[[1]]), "Önce düşünüyorum.")
})

test_that("stream satırı açık bağlantıda flush edilerek eklenir", {
  stream_path <- tempfile("stream_io_con_", fileext = ".jsonl")
  on.exit(try(unlink(stream_path, force = TRUE), silent = TRUE), add = TRUE)

  con <- file(stream_path, open = "ab")
  on.exit({
    if (isTRUE(try(isOpen(con), silent = TRUE))) {
      try(close(con), silent = TRUE)
    }
  }, add = TRUE)

  append_stream_delta_line(stream_file = "", text_value = "ilk", stream_con = con)
  append_stream_reasoning_line(stream_file = "", text_value = "ikinci", stream_con = con)
  close(con)

  payloads <- .read_stream_lines(stream_path)

  expect_length(payloads, 2L)
  expect_identical(
    vapply(payloads, `[[`, character(1), "type"),
    c("delta", "reasoning_delta")
  )
  expect_identical(
    vapply(payloads, decode_stream_delta_payload, character(1)),
    c("ilk", "ikinci")
  )
})

test_that("boş metin stream dosyası oluşturmaz", {
  stream_path <- tempfile("stream_io_empty_", fileext = ".jsonl")

  append_stream_delta_line(stream_path, "")

  expect_false(file.exists(stream_path))
})
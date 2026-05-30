# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-stream-chunk-behavior.R
# Açıklama: parse_streaming_chunk() davranışsal testleri. Bilge Yolaç stream-json
#           satırlarının (text/result/tool_result) ayrıştırılması, bilinmeyen
#           tipte NULL dönüşü ve geçersiz JSON'da raw_text fallback doğrulanır.
#           Alt-ayrıştırıcı gerektiren tipler (stream_event/tool_use/assistant)
#           kapsam dışıdır. DB/LLM/tarayıcı gerekmez.
# ==============================================================================

.cc_stream_chunk_source_once <- function() {
  if (exists("parse_streaming_chunk", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }

  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_streaming.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  invisible(TRUE)
}

testthat::test_that("parse_streaming_chunk text bloğunu ayrıştırır", {
  .cc_stream_chunk_source_once()
  testthat::skip_if_not_installed("jsonlite")

  out <- parse_streaming_chunk('{"type":"text","content":"merhaba"}')
  testthat::expect_identical(out$tip, "text")
  testthat::expect_identical(out$icerik, "merhaba")
})

testthat::test_that("parse_streaming_chunk result ve tool_result bloklarını ayrıştırır", {
  .cc_stream_chunk_source_once()
  testthat::skip_if_not_installed("jsonlite")

  res <- parse_streaming_chunk('{"type":"result","result":"tamamlandi","session_id":"s1"}')
  testthat::expect_identical(res$tip, "result")
  testthat::expect_identical(res$icerik, "tamamlandi")
  testthat::expect_identical(res$session_id, "s1")

  tr <- parse_streaming_chunk('{"type":"tool_result","tool_use_id":"t1","content":"sonuc"}')
  testthat::expect_identical(tr$tip, "tool_result")
  testthat::expect_identical(tr$arac_id, "t1")
  testthat::expect_identical(tr$icerik, "sonuc")
})

testthat::test_that("parse_streaming_chunk bilinmeyen tipte NULL döner", {
  .cc_stream_chunk_source_once()
  testthat::skip_if_not_installed("jsonlite")

  testthat::expect_null(parse_streaming_chunk('{"type":"bilinmeyen_tip"}'))
})

testthat::test_that("parse_streaming_chunk geçersiz JSON'da raw_text fallback döner", {
  .cc_stream_chunk_source_once()
  testthat::skip_if_not_installed("jsonlite")

  out <- parse_streaming_chunk("gecersiz json {")
  testthat::expect_identical(out$tip, "raw_text")
  testthat::expect_true(grepl("gecersiz json", out$icerik, fixed = TRUE))
})

# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-stream-html-safety-contract.R
# Açıklama: Bilge Yolaç streaming/tool-use HTML kaçış sözleşmesini korur.
# ==============================================================================

.source_cc_stream_html_safety_for_test <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())

  env$`%||%` <- function(x, y) {
    if (is.null(x)) y else x
  }

  source(
    file.path(repo_root, "R", "helpers_claude_code_formatters.R"),
    encoding = "UTF-8",
    local = env
  )

  env
}

test_that("streaming tool-use HTML escapes malicious tool input", {
  env <- .source_cc_stream_html_safety_for_test()

  parca <- list(
    tip = "tool_use",
    arac_id = "tool\"><script>alert(1)</script>",
    arac_adi = "Write",
    arac_turu = "file_write",
    girdi = list(),
    komut = "",
    dosya_yolu = "<img src=x onerror=alert(1)>",
    dosya_icerigi = "<script>alert(2)</script>\nnormal"
  )

  html <- env$format_streaming_chunk_html(parca)$html

  expect_false(grepl("<script", html, fixed = TRUE))
  expect_false(grepl("<img", html, fixed = TRUE))
  expect_true(grepl("&lt;script", html, fixed = TRUE))
  expect_true(grepl("&lt;img", html, fixed = TRUE))
})

test_that("tool result HTML escapes malicious output", {
  env <- .source_cc_stream_html_safety_for_test()

  html <- env$format_tool_result_snippet("<svg onload=alert(1)>")

  expect_false(grepl("<svg", html, fixed = TRUE))
  expect_true(grepl("&lt;svg", html, fixed = TRUE))
})
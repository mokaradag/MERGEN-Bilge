# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-stream-finalize-contract.R
# Açıklama: Bilge Yolaç streaming finalization durum temizleme sözleşmesini korur.
# ==============================================================================

.read_repo_text_cc_stream_finalize_contract <- function(path) {
  repo_root <- resolve_repo_root_for_tests()
  full_path <- file.path(repo_root, path)

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

test_that("Claude Code streaming finalization poll state temizler", {
  txt <- .read_repo_text_cc_stream_finalize_contract(
    "R/module_claude_code_akis.R"
  )

  m <- regexpr(
    "finalize_streaming\\s*<-\\s*function\\s*\\([^)]*\\)\\s*\\{[\\s\\S]+?invisible\\(TRUE\\)",
    txt,
    perl = TRUE
  )

  expect_true(
    m[1] > 0,
    info = "finalize_streaming() bloğu bulunmalıdır."
  )

  block <- regmatches(txt, m)[[1]]

  expect_true(
    grepl("!isTRUE\\(rv\\$is_running\\)", block, perl = TRUE),
    info = "finalize_streaming() idempotent erken dönüş korumasını korumalıdır."
  )

  expect_true(
    grepl("rv\\$active_process\\s*<-\\s*NULL", block, perl = TRUE),
    info = "finalize_streaming() active_process temizlemelidir."
  )

  expect_true(
    grepl("rv\\$poll_state\\s*<-\\s*NULL", block, perl = TRUE),
    info = "finalize_streaming() stale poll_state sızıntısını önlemelidir."
  )

  expect_true(
    grepl("rv\\$stream_env\\s*<-\\s*NULL", block, perl = TRUE),
    info = "finalize_streaming() stream_env temizlemelidir."
  )
})
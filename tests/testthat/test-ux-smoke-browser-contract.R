# ==============================================================================
# Dosya Yolu: tests/testthat/test-ux-smoke-browser-contract.R
# Açıklama: www/smoke/ux-smoke.html manuel browser smoke kapsamını korur.
# ==============================================================================

test_that("UX smoke keeps media lifecycle and saved-chat TTS probes", {
  repo_root <- resolve_repo_root_for_tests()
  smoke_path <- file.path(repo_root, "www", "smoke", "ux-smoke.html")

  expect_true(file.exists(smoke_path))

  smoke <- paste(readLines(smoke_path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  required_tokens <- c(
    "UX_SMOKE_DONE:PASS",
    "testMediaAndSavedChat",
    "MusicManager global API var",
    "TTS global API var",
    "STT global API var",
    "duckForSTT()",
    "unduckAfterSTT()",
    "TTS/play olayı müziği duck eder",
    "STT cleanup müziği restore eder",
    "load_chat_from_storage",
    "historicalMessages",
    "kayıtlı sohbet yüklenince tarihsel TTS autoplay başlamaz"
  )

  missing <- required_tokens[!vapply(
    required_tokens,
    function(token) grepl(token, smoke, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  expect_equal(
    missing,
    character(0),
    info = paste("UX smoke kapsamı eksik:", paste(missing, collapse = ", "))
  )
})
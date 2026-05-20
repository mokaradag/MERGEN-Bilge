# ==============================================================================
# Dosya Yolu: tests/testthat/test-saved-chat-reload-no-tts-contract.R
# Açıklama: Kayıtlı sohbet reload yolunun tarihsel AI mesajları için TTS
#           autoplay başlatmadığını yapısal olarak doğrular.
# ==============================================================================

.read_saved_chat_contract_text <- function(path) {
  repo_root <- resolve_repo_root_for_tests()
  full_path <- file.path(repo_root, path)

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) return("")

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) txt <- ""
  enc2utf8(gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE))
}

.extract_load_chat_from_storage_block <- function(text) {
  marker <- "observeEvent(input$load_chat_from_storage"
  start <- regexpr(marker, text, fixed = TRUE, useBytes = TRUE)[[1]]
  testthat::expect_true(start > 0L, info = "load_chat_from_storage observer bulunamadı")

  tail <- substr(text, start, nchar(text))
  end_marker <- "}, ignoreInit = TRUE)"
  end <- regexpr(end_marker, tail, fixed = TRUE, useBytes = TRUE)[[1]]
  testthat::expect_true(end > 0L, info = "load_chat_from_storage observer sonu bulunamadı")

  substr(tail, 1L, end + nchar(end_marker) - 1L)
}

testthat::test_that("saved chat reload renders history without starting TTS playback", {
  storage_text <- .read_saved_chat_contract_text("R/server_observers_storage.R")
  reload_block <- .extract_load_chat_from_storage_block(storage_text)

  testthat::expect_true(
    grepl("render_message_bubble_ui", reload_block, fixed = TRUE),
    info = "Reload yolu tarihsel mesajları render etmelidir."
  )

  forbidden <- c(
    "playAudioMessage",
    "synthesize_speech",
    "synthesize_speech(",
    "sendCustomMessage(\"playAudioMessage\"",
    "sendCustomMessage('playAudioMessage'"
  )

  missing_guard <- forbidden[vapply(
    forbidden,
    function(token) grepl(token, reload_block, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  testthat::expect_equal(
    missing_guard,
    character(0),
    info = paste("Reload observer TTS autoplay tetikleyebilir:", paste(missing_guard, collapse = ", "))
  )
})
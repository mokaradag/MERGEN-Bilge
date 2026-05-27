# ==============================================================================
# Dosya Yolu: tests/testthat/test-ux-smoke-browser-contract.R
# Açıklama: www/smoke/ux-smoke.html manuel browser smoke kapsamını korur.
# ==============================================================================

.ux_smoke_browser_read_text <- function(...) {
  full_path <- file.path(resolve_repo_root_for_tests(), ...)

  if (!file.exists(full_path)) {
    stop(sprintf("Beklenen dosya bulunamadı: %s", full_path), call. = FALSE)
  }

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

test_that("UX smoke keeps media lifecycle and saved-chat TTS probes", {
  repo_root <- resolve_repo_root_for_tests()
  smoke_path <- file.path(repo_root, "www", "smoke", "ux-smoke.html")
  smoke_probe_path <- file.path(repo_root, "www", "smoke", "ux-smoke-probes.js")

  expect_true(file.exists(smoke_path))
  expect_true(file.exists(smoke_probe_path))

  smoke <- paste(
    c(
      .ux_smoke_browser_read_text("www", "smoke", "ux-smoke.html"),
      .ux_smoke_browser_read_text("www", "smoke", "ux-smoke-probes.js")
    ),
    collapse = "\n"
  )

  required_tokens <- c(
    "UX_SMOKE_DONE:PASS",
    "ux-smoke-probes.js",
    "testMediaAndSavedChat",
    "testNavigationAndFileManagerSmoke",
    "MergenUxSmokeProbes",
    "runNavigationAndFileManagerSmoke",
    "MusicManager global API var",
    "TTS global API var",
    "STT global API var",
    "Audio lifecycle smoke API var",

    # TTS/media duck probe: use ASCII structural anchors instead of Turkish
    # assertion text so Windows native encoding cannot break the contract.
    "ttsAudio.dispatchEvent(new win.Event(\"play\"",
    "win.MusicManager.state.isDucked === true",
    "win.MergenAudioLifecycle.activeDuckOwners()",
    "win.MergenAudioLifecycle.releaseAll(\"ux-smoke-start\")",
    "tek background music source aktif kalır",

    # Overlapping owner probe: TTS release must not restore while STT owns duck.
    "win.MusicManager.duck(\"tts\")",
    "win.MusicManager.duckForSTT();",
    "owners.indexOf(\"tts\") >= 0",
    "owners.indexOf(\"stt\") >= 0",
    "win.MusicManager.unduck(\"tts\")",
    "activeDuckOwners().length === 0",

    # STT cleanup/restore probe.
    "win.MusicManager.unduckAfterSTT();",
    "win.MusicManager.state._sttActive === false",
    "win.MusicManager.state.isDucked === false",

    # Streaming lifecycle + finalize probe.
    "testStreamingLifecycle",
    "MergenStreamingSmoke",
    "streaming delta görünür içeriğe işlendi",
    "stale requestId delta yoksayılır",
    "followup_container_ux_stream_ai",
    "class='followup-container pending'",
    "stream finalize follow-up pending state temizlenir",
    "stream action butonları geri açılır",
    "stream finalize duplicate mesaj üretmez",

    # Saved-chat historical TTS non-autoplay probe.
    "load_chat_from_storage",
    "historicalMessages",
    "win.mergenTTS.queue.length === 0",
    "win.mergenTTS.isPlaying !== true",
    "!win.mergenTTS.currentAudio",

    # Navigation / video lifecycle / File Manager display-name probe.
    "Navigation/File Manager smoke probe tamamlandı",
    "WelcomeVideoPlayer smoke state API var",
    "Bilge Yolaç sekme linki tıklanabilir",
    "Ana Söyleşi dönüşü welcome video gereksiz reinit etmez",
    "File Manager synthetic refresh sonrası Türkçe adı korur",
    "Türkçe_çalışma_özeti_İstanbul.pdf"
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
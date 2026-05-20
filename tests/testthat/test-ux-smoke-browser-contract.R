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

    # TTS/media duck probe: use ASCII structural anchors instead of Turkish
    # assertion text so Windows native encoding cannot break the contract.
    "ttsAudio.dispatchEvent(new win.Event(\"play\"",
    "win.MusicManager.state.isDucked === true",
    "win.MergenAudioLifecycle.activeDuckOwners()",
    "win.MergenAudioLifecycle.releaseAll(\"ux-smoke-start\")",

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

    # Saved-chat historical TTS non-autoplay probe.
    "load_chat_from_storage",
    "historicalMessages",
    "win.mergenTTS.queue.length === 0",
    "win.mergenTTS.isPlaying !== true",
    "!win.mergenTTS.currentAudio"
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
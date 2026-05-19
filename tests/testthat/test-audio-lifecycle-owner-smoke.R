# ==============================================================================
# Dosya Yolu: tests/testthat/test-audio-lifecycle-owner-smoke.R
# Açıklama: TTS/STT/müzik sahiplik tabanlı yaşam döngüsü sözleşmesini
#           tarayıcı başlatmadan doğrular.
# ==============================================================================

.find_audio_owner_repo_root <- function() {
  candidates <- unique(normalizePath(
    c(getwd(), file.path(getwd(), ".."), file.path(getwd(), "..", "..")),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "www", "js"))) {
      return(candidate)
    }
  }

  stop("Audio lifecycle smoke repo kökünü bulamadı.", call. = FALSE)
}

.audio_owner_read_text <- function(...) {
  path <- file.path(.find_audio_owner_repo_root(), ...)
  if (!file.exists(path)) {
    stop(sprintf("Beklenen dosya bulunamadı: %s", path), call. = FALSE)
  }

  size <- suppressWarnings(file.info(path)$size[1])
  if (is.na(size) || size <= 0) return("")

  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) txt <- ""
  enc2utf8(gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE))
}

.audio_owner_expect_all <- function(text, tokens, label) {
  missing <- tokens[!vapply(
    tokens,
    function(token) grepl(token, text, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  testthat::expect_equal(
    missing,
    character(0),
    info = paste(label, paste(missing, collapse = ", "))
  )
}

testthat::test_that("TTS audio is explicitly marked with tts owner before playback", {
  tts_js <- .audio_owner_read_text("www", "js", "tts_manager.js")

  .audio_owner_expect_all(
    tts_js,
    c(
      "window.MergenAudioLifecycle.markAudio(audio, 'tts')",
      "audio.dataset.mergenAudioOwner = 'tts'",
      "MusicManager.duck('tts')",
      "MusicManager.unduck('tts')",
      "window.mergenTTS.stop()",
      "notifyTTSPlaying(false)"
    ),
    "TTS owner/cleanup sözleşmesi eksik:"
  )

  mark_pos <- regexpr(
    "window.MergenAudioLifecycle.markAudio(audio, 'tts')",
    tts_js,
    fixed = TRUE,
    useBytes = TRUE
  )[[1]]

  play_pos <- regexpr(
    "const playPromise = audio.play();",
    tts_js,
    fixed = TRUE,
    useBytes = TRUE
  )[[1]]

  testthat::expect_true(mark_pos > 0L)
  testthat::expect_true(play_pos > 0L)
  testthat::expect_true(
    mark_pos < play_pos,
    info = "TTS audio owner etiketi audio.play() öncesinde atanmalıdır."
  )
})

testthat::test_that("audio lifecycle guard keeps owner based duck/release contract", {
  guard_js <- .audio_owner_read_text("www", "js", "audio_lifecycle_guard.js")

  .audio_owner_expect_all(
    guard_js,
    c(
      "var duckOwners = {};",
      "function ownerList()",
      "function applyMusicDuckState()",
      "function duck(owner)",
      "function release(owner)",
      "function releaseMany(owners, reason)",
      "function releaseAll(reason)",
      "markAudio: markAudio",
      "getAudioOwner: getAudioOwner",
      "cleanupTransient: cleanupTransient",
      "'tts', 'ai_expert', 'stt', 'external_audio', 'tts_manual'"
    ),
    "Audio lifecycle owner sözleşmesi eksik:"
  )
})

testthat::test_that("STT and music manager use lifecycle owners for duck recovery", {
  stt_js <- .audio_owner_read_text("www", "js", "stt_client.js")
  music_js <- .audio_owner_read_text("www", "js", "music_manager.js")

  .audio_owner_expect_all(
    stt_js,
    c(
      "window.MusicManager.duckForSTT()",
      "restoreMusicAfterSTT()",
      "window.MusicManager.unduckAfterSTT()",
      "stopAndCleanup(nsPrefix",
      "hidden.bs.modal.mergenSttCleanup"
    ),
    "STT duck/recovery sözleşmesi eksik:"
  )

  .audio_owner_expect_all(
    music_js,
    c(
      "window.MergenAudioLifecycle.duck(owner || 'external_audio')",
      "window.MergenAudioLifecycle.release(owner || 'external_audio')",
      "window.MergenAudioLifecycle.duck('stt')",
      "window.MergenAudioLifecycle.release('stt')",
      "_pendingRequestId",
      "_stopAudio: function()"
    ),
    "MusicManager lifecycle sözleşmesi eksik:"
  )
})
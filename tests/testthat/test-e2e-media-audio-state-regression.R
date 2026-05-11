# ==============================================================================
# Dosya Yolu: tests/testthat/test-e2e-media-audio-state-regression.R
# Açıklama: TTS/STT/arka plan müziği için deterministik E2E benzeri yarış
#           durumu regresyon testleri. Gerçek tarayıcı, mikrofon, ses dosyası,
#           TTS/STT endpoint'i veya public internet gerektirmez.
# ==============================================================================

.find_media_e2e_repo_root <- function() {
  candidates <- unique(normalizePath(
    c(
      getwd(),
      file.path(getwd(), ".."),
      file.path(getwd(), "..", "..")
    ),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "tests", "testthat"))) {
      return(candidate)
    }
  }

  stop("Media E2E test repo kökünü bulamadı. Testi repo kökünden çalıştırın.", call. = FALSE)
}

repo_root_media_e2e <- .find_media_e2e_repo_root()

if (!exists("resolve_repo_root_for_tests", envir = globalenv(), inherits = FALSE)) {
  source(
    file.path(repo_root_media_e2e, "tests", "testthat", "helper_bootstrap.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
}

repo_root_media_e2e <- resolve_repo_root_for_tests()

if (!exists("e2e_media_new_music_state", envir = globalenv(), inherits = FALSE)) {
  source(
    file.path(repo_root_media_e2e, "tests", "testthat", "helper_e2e_media_audio_harness.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
}

.e2e_media_read_text <- function(...) {
  path <- file.path(repo_root_media_e2e, ...)
  if (!file.exists(path)) {
    stop(sprintf("Beklenen dosya bulunamadı: %s", path), call. = FALSE)
  }

  size <- suppressWarnings(file.info(path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  # Windows VM üzerinde bazı JS dosyalarındaki Türkçe yorumlar native/ANSI
  # olarak okunabiliyor. Bu test yalnızca ASCII hook isimlerini aradığı için
  # non-ASCII baytları boşluğa çevirerek grepl'in UTF-8 uyarılarını önler.
  raw_data[raw_data == as.raw(0L)] <- as.raw(0x20)
  raw_data[as.integer(raw_data) > 127L] <- as.raw(0x20)

  txt <- rawToChar(raw_data)
  Encoding(txt) <- "UTF-8"
  txt
}

test_that("media JS contracts expose offline-safe audio state hooks", {
  expect_true(file.exists(file.path(repo_root_media_e2e, "app.R")))
  expect_true(dir.exists(file.path(repo_root_media_e2e, "www", "js")))

  music_js <- .e2e_media_read_text("www", "js", "music_manager.js")
  tts_js <- .e2e_media_read_text("www", "js", "tts_manager.js")
  stt_js <- .e2e_media_read_text("www", "js", "stt_client.js")
  reasoning_js <- .e2e_media_read_text("www", "js", "premium_reasoning.js")

  has_regex <- function(text, pattern) {
    grepl(pattern, text, perl = TRUE)
  }

  expect_true(has_regex(music_js, "\\bMusicManager\\s*=\\s*\\{"))
  expect_true(has_regex(music_js, "_audio\\s*:\\s*null"))
  expect_true(has_regex(music_js, "_pendingRequestId\\s*:\\s*0"))
  expect_true(has_regex(music_js, "_pendingRequestType\\s*:\\s*null"))
  expect_true(has_regex(music_js, "anaTemaBekleniyor"))
  expect_true(has_regex(music_js, "requestId[^\\n]+<\\s*this\\._pendingRequestId"))
  expect_true(has_regex(music_js, "duckForSTT\\s*:\\s*function\\s*\\("))
  expect_true(has_regex(music_js, "unduckAfterSTT\\s*:\\s*function\\s*\\("))

  expect_true(has_regex(tts_js, "window\\.mergenTTS"))
  expect_true(has_regex(tts_js, "queue\\.sort\\s*\\("))
  expect_true(has_regex(tts_js, "MusicManager\\.duck\\s*\\("))
  expect_true(has_regex(tts_js, "MusicManager\\.unduck\\s*\\("))
  expect_true(has_regex(tts_js, "tts_is_playing"))

  expect_true(has_regex(stt_js, "window\\.STT_Client"))
  expect_true(has_regex(stt_js, "MusicManager\\.duckForSTT\\s*\\("))
  expect_true(has_regex(stt_js, "MusicManager\\.unduckAfterSTT\\s*\\("))

  expect_true(has_regex(reasoning_js, "PremiumReasoning"))
  expect_true(has_regex(reasoning_js, "simulatedMode"))
  expect_true(has_regex(reasoning_js, "fadeOutAndRemove\\s*\\(\\s*panel\\s*\\)"))
})

test_that("duplicate startup toggle does not skip main theme while theme playlist is pending", {
  music <- e2e_media_new_music_state()

  # Başlangıçta MusicManager initMusicManager ile kapalı gelir.
  music <- e2e_music_init(
    music,
    enabled = FALSE,
    volume = 0.4,
    character = "mergen"
  )

  expect_false(music$enabled)
  expect_identical(music$pending_request_id, 0L)
  expect_null(music$pending_request_type)
  expect_length(music$requests, 0L)

  # Dinamik/Bütünleşik mod seçimi sonrası ilk toggle:
  # Ana Tema playlist'i istenmeli.
  music <- e2e_music_toggle(music, TRUE, character = "mergen")

  expect_true(music$enabled)
  expect_identical(music$phase, "idle")
  expect_identical(music$pending_request_id, 1L)
  expect_identical(music$pending_request_type, "tema")
  expect_length(music$requests, 1L)
  expect_identical(music$requests[[1]]$type, "tema")
  expect_identical(e2e_media_current_track_count(music), 0L)

  # Regresyonun özü:
  # Ana Tema playlist yanıtı henüz gelmeden ikinci toggleMusic(TRUE) gelirse
  # karakter playlist'i istenmemeli, request_id artmamalı, Ana Tema beklenmeli.
  music <- e2e_music_toggle(music, TRUE, character = "mergen")

  expect_identical(music$phase, "idle")
  expect_identical(music$pending_request_id, 1L)
  expect_identical(music$pending_request_type, "tema")
  expect_length(music$requests, 1L)
  expect_false(any(vapply(
    music$requests,
    function(req) identical(req$type, "karakter"),
    logical(1)
  )))
  expect_true(any(grepl(
    "duplicate_toggle_ignored:theme_pending",
    music$events,
    fixed = TRUE
  )))
  expect_identical(e2e_media_current_track_count(music), 0L)

  # Ana Tema yanıtı artık stale sayılmamalı; doğrudan çalmaya başlamalı.
  music <- e2e_music_receive_playlist(
    music,
    type = "tema",
    files = "ana_tema_1.mp3",
    request_id = 1L
  )

  expect_identical(music$phase, "theme")
  expect_true(music$theme_played_once)
  expect_identical(music$track_src, "ana_tema_1.mp3")
  expect_identical(e2e_media_current_track_count(music), 1L)
  expect_null(music$pending_request_type)
  expect_false(any(grepl(
    "playlist_ignored:stale:1",
    music$events,
    fixed = TRUE
  )))
})

test_that("music playlist races keep exactly one active background track", {
  music <- e2e_media_new_music_state()
  music <- e2e_music_init(
    music,
    enabled = TRUE,
    volume = 0.4,
    character = "mergen"
  )

  expect_identical(music$pending_request_id, 1L)
  expect_identical(e2e_media_current_track_count(music), 0L)

  music <- e2e_music_receive_playlist(
    music,
    type = "tema",
    files = "tema_eski.mp3",
    request_id = 0L
  )

  expect_identical(e2e_media_current_track_count(music), 0L)
  expect_true(any(grepl("playlist_ignored:stale", music$events, fixed = TRUE)))

  music <- e2e_music_receive_playlist(
    music,
    type = "tema",
    files = "tema_1.mp3",
    request_id = 1L
  )

  first_audio_token <- music$audio_token

  expect_identical(music$phase, "theme")
  expect_identical(music$track_src, "tema_1.mp3")
  expect_identical(e2e_media_current_track_count(music), 1L)

  music <- e2e_music_receive_playlist(
    music,
    type = "karakter",
    files = "mergen_1.mp3",
    request_id = 1L
  )
  music <- e2e_music_handle_track_ended(music)

  expect_identical(music$phase, "character")
  expect_identical(music$track_src, "mergen_1.mp3")
  expect_false(identical(first_audio_token, music$audio_token))
  expect_identical(e2e_media_current_track_count(music), 1L)

  music <- e2e_music_toggle(music, TRUE, character = "umay")

  expect_identical(music$character, "umay")
  expect_identical(music$phase, "waiting_character")
  expect_null(music$audio_token)
  expect_identical(music$pending_request_id, 2L)

  music <- e2e_music_receive_playlist(
    music,
    type = "karakter",
    files = "stale_mergen.mp3",
    request_id = 1L
  )

  expect_null(music$audio_token)
  expect_false(identical(music$track_src, "stale_mergen.mp3"))

  music <- e2e_music_receive_playlist(
    music,
    type = "karakter",
    files = "umay_1.mp3",
    request_id = 2L
  )

  expect_identical(music$phase, "character")
  expect_identical(music$track_src, "umay_1.mp3")
  expect_identical(e2e_media_current_track_count(music), 1L)
})

test_that("TTS ducks music until ordered queue drains and stop restores state", {
  music <- e2e_media_new_music_state()
  music <- e2e_music_init(music, enabled = TRUE, volume = 0.5)
  music <- e2e_music_receive_playlist(
    music,
    type = "tema",
    files = "tema_1.mp3",
    request_id = 1L
  )

  tts <- e2e_tts_new_state()
  tts <- e2e_tts_enqueue(tts, id = "tts_2", src = "chunk_2.mp3", chunk_index = 2)
  tts <- e2e_tts_enqueue(tts, id = "tts_1", src = "chunk_1.mp3", chunk_index = 1)

  out <- e2e_tts_process_next(tts, music)
  tts <- out$tts
  music <- out$music

  expect_true(tts$is_playing)
  expect_identical(tts$current_audio$id, "tts_1")
  expect_true(music$is_ducked)
  expect_equal(music$effective_volume, 0.075)

  out <- e2e_tts_finish_current(tts, music)
  tts <- out$tts
  music <- out$music

  expect_true(tts$is_playing)
  expect_identical(tts$current_audio$id, "tts_2")
  expect_true(music$is_ducked)

  out <- e2e_tts_finish_current(tts, music)
  tts <- out$tts
  music <- out$music

  expect_false(tts$is_playing)
  expect_false(tts$reported_playing)
  expect_length(tts$queue, 0L)
  expect_false(music$is_ducked)
  expect_equal(music$effective_volume, 0.5)

  tts <- e2e_tts_enqueue(tts, id = "tts_stop", src = "stop_me.mp3", chunk_index = 1)
  out <- e2e_tts_process_next(tts, music)
  out <- e2e_tts_stop(out$tts, out$music)

  expect_false(out$tts$is_playing)
  expect_false(out$tts$reported_playing)
  expect_length(out$tts$queue, 0L)
  expect_false(out$music$is_ducked)
})

test_that("STT full duck blocks premature TTS/music unduck until modal cleanup", {
  music <- e2e_media_new_music_state()
  music <- e2e_music_init(music, enabled = TRUE, volume = 0.6)
  music <- e2e_music_receive_playlist(
    music,
    type = "tema",
    files = "tema_1.mp3",
    request_id = 1L
  )

  music <- e2e_music_duck_for_stt(music)

  expect_true(music$stt_active)
  expect_true(music$is_ducked)
  expect_equal(music$effective_volume, 0)

  music <- e2e_music_unduck(music)

  expect_true(music$stt_active)
  expect_true(music$is_ducked)
  expect_equal(music$effective_volume, 0)
  expect_true(any(grepl("music_unduck_blocked_by_stt", music$events, fixed = TRUE)))

  music <- e2e_music_unduck_after_stt(music)

  expect_false(music$stt_active)
  expect_false(music$is_ducked)
  expect_equal(music$effective_volume, 0.6)
})

test_that("navigation cleanup leaves no stale TTS, STT, or music state", {
  music <- e2e_media_new_music_state()
  music <- e2e_music_init(music, enabled = TRUE, volume = 0.3)
  music <- e2e_music_receive_playlist(
    music,
    type = "tema",
    files = "tema_1.mp3",
    request_id = 1L
  )

  tts <- e2e_tts_new_state()
  tts <- e2e_tts_enqueue(tts, id = "tts_active", src = "active.mp3", chunk_index = 1)

  out <- e2e_tts_process_next(tts, music)
  tts <- out$tts
  music <- e2e_music_duck_for_stt(out$music)

  cleanup <- e2e_media_navigation_cleanup(tts, music)

  expect_false(cleanup$tts$is_playing)
  expect_false(cleanup$tts$reported_playing)
  expect_null(cleanup$tts$current_audio)
  expect_length(cleanup$tts$queue, 0L)

  expect_false(cleanup$music$enabled)
  expect_identical(cleanup$music$phase, "idle")
  expect_false(cleanup$music$stt_active)
  expect_false(cleanup$music$is_ducked)
  expect_null(cleanup$music$audio_token)
  expect_equal(cleanup$music$effective_volume, 0)
})
# ==============================================================================
# Dosya Yolu: tests/testthat/helper_e2e_media_audio_harness.R
# Açıklama: TTS/STT/arka plan müziği E2E ve yarış durumu regresyon testleri için
#           gerçek tarayıcı Audio, mikrofon, TTS endpoint'i veya Shiny oturumu
#           gerektirmeyen deterministik medya durum makinesi.
# ==============================================================================

e2e_media_first <- function(value, default = "") {
  if (is.null(value) || length(value) == 0L) {
    return(default)
  }

  value <- value[1]
  if (is.na(value)) {
    return(default)
  }

  value
}

e2e_media_log <- function(state, event) {
  state$events <- c(state$events, enc2utf8(as.character(event)[1]))
  state
}

e2e_media_new_music_state <- function() {
  list(
    enabled = FALSE,
    character = "mergen",
    phase = "idle",
    normal_volume = 0.3,
    effective_volume = 0,
    is_ducked = FALSE,
    stt_active = FALSE,
    audio_token = NULL,
    track_src = NULL,
    pending_request_id = 0L,
    theme_playlist = character(),
    character_playlist = character(),
    theme_played_once = FALSE,
    requests = list(),
    events = character()
  )
}

e2e_music_stop_audio <- function(state) {
  if (!is.null(state$audio_token)) {
    state <- e2e_media_log(state, paste0("audio_stop:", state$audio_token))
  }

  state$audio_token <- NULL
  state$track_src <- NULL
  state$effective_volume <- 0
  state
}

e2e_music_request_playlist <- function(state, type) {
  state$pending_request_id <- as.integer(state$pending_request_id) + 1L

  state$requests <- append(
    state$requests,
    list(list(
      type = enc2utf8(as.character(type)[1]),
      character = enc2utf8(as.character(state$character)[1]),
      request_id = state$pending_request_id
    ))
  )

  e2e_media_log(
    state,
    sprintf("playlist_request:%s:%d", type, state$pending_request_id)
  )
}

e2e_music_effective_volume <- function(state) {
  if (!isTRUE(state$enabled) || is.null(state$audio_token)) {
    return(0)
  }

  if (isTRUE(state$stt_active)) {
    return(0)
  }

  if (isTRUE(state$is_ducked)) {
    return(max(0.02, state$normal_volume * 0.15))
  }

  state$normal_volume
}

e2e_music_play_track <- function(state, src) {
  state <- e2e_music_stop_audio(state)

  if (!isTRUE(state$enabled)) {
    return(state)
  }

  src <- enc2utf8(as.character(src)[1])
  state$audio_token <- sprintf("audio_%03d", length(state$events) + 1L)
  state$track_src <- src
  state$effective_volume <- e2e_music_effective_volume(state)

  e2e_media_log(state, paste0("audio_play:", src))
}

e2e_music_start_from_beginning <- function(state) {
  state <- e2e_music_stop_audio(state)
  state$phase <- "idle"
  state$theme_playlist <- character()
  state$character_playlist <- character()

  if (isTRUE(state$theme_played_once)) {
    e2e_music_request_playlist(state, "karakter")
  } else {
    e2e_music_request_playlist(state, "tema")
  }
}

e2e_music_init <- function(state,
                           enabled = FALSE,
                           volume = 0.3,
                           character = "mergen") {
  volume <- suppressWarnings(as.numeric(volume)[1])
  if (is.na(volume)) {
    volume <- 0.3
  }

  state$enabled <- isTRUE(enabled)
  state$normal_volume <- volume
  state$character <- enc2utf8(as.character(character)[1])

  state <- e2e_media_log(
    state,
    sprintf("music_init:%s:%s", state$enabled, state$character)
  )

  if (isTRUE(state$enabled)) {
    state <- e2e_music_start_from_beginning(state)
  }

  state
}

e2e_music_toggle <- function(state, enabled, character = NULL) {
  enabled <- isTRUE(enabled)
  next_character <- enc2utf8(as.character(e2e_media_first(character, state$character))[1])
  character_changed <- nzchar(next_character) && !identical(next_character, state$character)

  if (nzchar(next_character)) {
    state$character <- next_character
  }

  if (identical(isTRUE(state$enabled), enabled)) {
    if (enabled &&
        character_changed &&
        state$phase %in% c("character", "waiting_character")) {
      state <- e2e_music_stop_audio(state)
      state$character_playlist <- character()
      state$phase <- "waiting_character"
      return(e2e_music_request_playlist(state, "karakter"))
    }

    if (enabled &&
        (is.null(state$audio_token) || identical(state$phase, "idle"))) {
      state$phase <- "waiting_character"
      return(e2e_music_request_playlist(state, "karakter"))
    }

    return(state)
  }

  state$enabled <- enabled

  if (enabled) {
    state <- e2e_music_start_from_beginning(state)
  } else {
    state <- e2e_music_stop_audio(state)
    state$phase <- "idle"
    state$theme_playlist <- character()
    state$character_playlist <- character()
    state$pending_request_id <- as.integer(state$pending_request_id) + 1L
    state <- e2e_media_log(state, "music_disabled")
  }

  state
}

e2e_music_receive_playlist <- function(state, type, files, request_id) {
  type <- enc2utf8(as.character(type)[1])
  request_id <- suppressWarnings(as.integer(request_id)[1])
  if (is.na(request_id)) {
    request_id <- 0L
  }

  if (!isTRUE(state$enabled)) {
    return(e2e_media_log(state, "playlist_ignored:disabled"))
  }

  if (request_id < as.integer(state$pending_request_id)) {
    return(e2e_media_log(
      state,
      sprintf("playlist_ignored:stale:%d", request_id)
    ))
  }

  if (is.null(files)) {
    files <- character()
  }
  files <- enc2utf8(as.character(files))

  if (identical(type, "tema")) {
    state$theme_playlist <- files

    if (length(files) > 0L && identical(state$phase, "idle")) {
      state$phase <- "theme"
      state$theme_played_once <- TRUE
      state <- e2e_music_play_track(state, files[1])
    } else {
      state <- e2e_music_request_playlist(state, "karakter")
    }

    return(state)
  }

  if (identical(type, "karakter")) {
    state$character_playlist <- files

    if (length(files) > 0L &&
        state$phase %in% c("idle", "waiting_character")) {
      state$phase <- "character"
      state <- e2e_music_play_track(state, files[1])
    }

    return(state)
  }

  e2e_media_log(state, paste0("playlist_ignored:unknown_type:", type))
}

e2e_music_handle_track_ended <- function(state) {
  if (!isTRUE(state$enabled)) {
    return(state)
  }

  if (identical(state$phase, "theme")) {
    state$phase <- "waiting_character"

    if (length(state$character_playlist) > 0L) {
      state$phase <- "character"
      return(e2e_music_play_track(state, state$character_playlist[1]))
    }

    return(e2e_music_request_playlist(state, "karakter"))
  }

  if (identical(state$phase, "character") &&
      length(state$character_playlist) > 0L) {
    return(e2e_music_play_track(state, state$character_playlist[1]))
  }

  state
}

e2e_music_duck <- function(state) {
  if (isTRUE(state$is_ducked)) {
    return(state)
  }

  state$is_ducked <- TRUE
  state$effective_volume <- e2e_music_effective_volume(state)
  e2e_media_log(state, "music_duck")
}

e2e_music_unduck <- function(state) {
  if (isTRUE(state$stt_active)) {
    return(e2e_media_log(state, "music_unduck_blocked_by_stt"))
  }

  if (!isTRUE(state$is_ducked)) {
    return(state)
  }

  state$is_ducked <- FALSE
  state$effective_volume <- e2e_music_effective_volume(state)
  e2e_media_log(state, "music_unduck")
}

e2e_music_duck_for_stt <- function(state) {
  if (isTRUE(state$stt_active)) {
    return(state)
  }

  state$stt_active <- TRUE
  state$is_ducked <- TRUE
  state$effective_volume <- 0
  e2e_media_log(state, "music_duck_for_stt")
}

e2e_music_unduck_after_stt <- function(state) {
  state$stt_active <- FALSE
  state$is_ducked <- FALSE
  state$effective_volume <- e2e_music_effective_volume(state)
  e2e_media_log(state, "music_unduck_after_stt")
}

e2e_tts_new_state <- function() {
  list(
    queue = list(),
    is_playing = FALSE,
    current_audio = NULL,
    reported_playing = FALSE,
    events = character()
  )
}

e2e_tts_enqueue <- function(tts, id, src, chunk_index = 0) {
  chunk_index <- suppressWarnings(as.numeric(chunk_index)[1])
  if (is.na(chunk_index)) {
    chunk_index <- length(tts$queue)
  }

  tts$queue <- append(
    tts$queue,
    list(list(
      id = enc2utf8(as.character(id)[1]),
      src = enc2utf8(as.character(src)[1]),
      index = chunk_index
    ))
  )

  if (length(tts$queue) > 1L) {
    ord <- order(vapply(tts$queue, function(item) item$index, numeric(1)))
    tts$queue <- tts$queue[ord]
  }

  e2e_media_log(tts, paste0("tts_enqueue:", id))
}

e2e_tts_process_next <- function(tts, music) {
  if (isTRUE(tts$is_playing) || length(tts$queue) == 0L) {
    return(list(tts = tts, music = music))
  }

  item <- tts$queue[[1]]
  tts$queue <- if (length(tts$queue) > 1L) tts$queue[-1] else list()
  tts$is_playing <- TRUE
  tts$reported_playing <- TRUE
  tts$current_audio <- item

  music <- e2e_music_duck(music)
  tts <- e2e_media_log(tts, paste0("tts_play:", item$id))

  list(tts = tts, music = music)
}

e2e_tts_finish_current <- function(tts, music, status = "ended") {
  if (!isTRUE(tts$is_playing)) {
    return(list(tts = tts, music = music))
  }

  current_id <- tts$current_audio$id %||% "unknown"
  tts$is_playing <- FALSE
  tts$current_audio <- NULL
  tts <- e2e_media_log(tts, paste0("tts_", status, ":", current_id))

  if (length(tts$queue) == 0L) {
    music <- e2e_music_unduck(music)
    tts$reported_playing <- FALSE
    return(list(tts = tts, music = music))
  }

  e2e_tts_process_next(tts, music)
}

e2e_tts_stop <- function(tts, music) {
  tts$queue <- list()
  tts$is_playing <- FALSE
  tts$current_audio <- NULL
  tts$reported_playing <- FALSE
  tts <- e2e_media_log(tts, "tts_stop")

  music <- e2e_music_unduck(music)

  list(tts = tts, music = music)
}

e2e_media_navigation_cleanup <- function(tts, music) {
  stt_was_active <- isTRUE(music$stt_active)

  stopped <- e2e_tts_stop(tts, music)
  tts <- stopped$tts
  music <- stopped$music

  if (stt_was_active || isTRUE(music$stt_active)) {
    music <- e2e_music_unduck_after_stt(music)
  }

  music <- e2e_music_toggle(music, FALSE)

  list(tts = tts, music = music)
}

e2e_media_current_track_count <- function(state) {
  as.integer(!is.null(state$audio_token))
}
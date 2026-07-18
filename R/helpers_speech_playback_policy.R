# R/helpers_speech_playback_policy.R
# Konuşma oynatma politikası: sayfa rehberliği kararı, oturum kapsamlı karışık
# torba (shuffle bag) çeşit seçimi, konuşma önceliği matrisi, oturum konuşma
# durumu (tek yetkili token sahibi) ve deterministik kişisel karşılama öneki.
# Saf karar mantığıdır; ağ/DB çağrısı yapmaz.

#' Sayfa rehberliği politikası: "guided" / "silent" / "unknown".
mergen_speech_guidance_policy <- function(page) {
  page <- tryCatch(as.character(page)[1], error = function(e) NA_character_)
  if (is.na(page) || !nzchar(page)) return("unknown")
  if (page %in% names(mergen_speech_guided_pages())) return("guided")
  if (page %in% mergen_speech_silent_pages()) return("silent")
  "unknown"
}

#' Konuşma türü öncelik sırası (küçük sayı = yüksek öncelik).
mergen_speech_priority <- function(kind) {
  switch(
    as.character(kind),
    "response_tts"  = 1L,
    "welcome"       = 2L,
    "page_guidance" = 3L,
    "idle"          = 4L,
    99L
  )
}

#' Öncelik kararı: yeni tür aktif türü kesebilir mi?
#' - response_tts (kullanıcı isteği) her şeyi keser; otomatik konuşmalar onu kesemez.
#' - page_guidance kullanıcı gezinme eylemidir: karşılamayı ve eski rehberliği keser.
#' - idle en düşüktür; hiçbir aktif konuşmayı kesmez.
#'
#' @return list(allow, stop_active)
mergen_speech_priority_decision <- function(active_kind, new_kind) {
  if (is.null(active_kind) || is.na(active_kind) || !nzchar(as.character(active_kind))) {
    return(list(allow = TRUE, stop_active = FALSE))
  }

  active <- as.character(active_kind)
  new <- as.character(new_kind)

  if (identical(new, "response_tts")) {
    return(list(allow = TRUE, stop_active = TRUE))
  }
  if (identical(active, "response_tts")) {
    return(list(allow = FALSE, stop_active = FALSE))
  }

  if (identical(new, "welcome")) {
    allow <- active %in% c("page_guidance", "idle")
    return(list(allow = allow, stop_active = allow))
  }

  if (identical(new, "page_guidance")) {
    return(list(allow = TRUE, stop_active = TRUE))
  }

  if (identical(new, "idle")) {
    return(list(allow = FALSE, stop_active = FALSE))
  }

  list(allow = FALSE, stop_active = FALSE)
}

#' Karışık torba durumu oluştur (env tabanlı, oturum kapsamlı).
mergen_speech_shuffle_bag_env <- function() {
  new.env(parent = emptyenv())
}

.speech_bag_slot <- function(bag_env, key) {
  slot <- get0(key, envir = bag_env, ifnotfound = NULL)
  if (is.null(slot)) slot <- list(remaining = integer(0), last = NA_integer_)
  slot
}

.speech_bag_refill <- function(slot, n) {
  order <- sample.int(n)
  # Yeniden karma sonrası ilk çeşit son oynatılanla aynı olmasın
  if (!is.na(slot$last) && n > 1L && order[1] == slot$last) {
    swap_idx <- sample(2:n, 1L)
    tmp <- order[1]; order[1] <- order[swap_idx]; order[swap_idx] <- tmp
  }
  slot$remaining <- order
  slot
}

#' Torbadan sıradaki çeşidi TÜKETEREK çek. 10 çeşidin tamamı bitmeden tekrar
#' olmaz; yeniden doldurmada hemen tekrar engellenir.
mergen_speech_shuffle_bag_draw <- function(bag_env, key, n = mergen_speech_variant_count()) {
  n <- as.integer(n)
  slot <- .speech_bag_slot(bag_env, key)
  if (length(slot$remaining) == 0) slot <- .speech_bag_refill(slot, n)

  variant <- slot$remaining[1]
  slot$remaining <- slot$remaining[-1]
  slot$last <- variant
  assign(key, slot, envir = bag_env)
  variant
}

#' Torbanın sıradaki çeşidini TÜKETMEDEN gör (önden yükleme için).
mergen_speech_shuffle_bag_peek <- function(bag_env, key, n = mergen_speech_variant_count()) {
  n <- as.integer(n)
  slot <- .speech_bag_slot(bag_env, key)
  if (length(slot$remaining) == 0) {
    slot <- .speech_bag_refill(slot, n)
    assign(key, slot, envir = bag_env)
  }
  slot$remaining[1]
}

#' Oturum konuşma durumu: tek yetkili, tekdüze artan token sahibi.
#' session$userData altında yaşar; sahte oturumlarla test edilebilir.
mergen_speech_state <- function(session) {
  ud <- session$userData
  state <- get0("mergen_speech_state", envir = ud, ifnotfound = NULL)
  if (is.null(state)) {
    state <- new.env(parent = emptyenv())
    state$token <- 0L
    state$active_kind <- NULL
    state$active_token <- 0L
    state$bags <- mergen_speech_shuffle_bag_env()
    assign("mergen_speech_state", state, envir = ud)
  }
  state
}

#' Yeni konuşma isteği başlat: öncelik kararını uygula, izin varsa yeni token
#' üret ve aktif konuşmayı bu tür/token yap.
#'
#' @return list(allow, token, stop_active)
mergen_speech_begin <- function(session, kind) {
  state <- mergen_speech_state(session)
  decision <- mergen_speech_priority_decision(state$active_kind, kind)

  if (!isTRUE(decision$allow)) {
    return(list(allow = FALSE, token = NA_integer_, stop_active = FALSE))
  }

  state$token <- state$token + 1L
  state$active_kind <- as.character(kind)
  state$active_token <- state$token

  list(allow = TRUE, token = state$token, stop_active = decision$stop_active)
}

#' Konuşma bitti/durduruldu: yalnızca hâlâ aktif olan token durumu temizler.
#' Bayat (eski) bir bitiş çağrısı yeni konuşmanın durumunu bozamaz.
mergen_speech_end <- function(session, token = NULL) {
  state <- mergen_speech_state(session)
  if (!is.null(token) && !is.na(token) && !identical(as.integer(token), state$active_token)) {
    return(invisible(FALSE))
  }
  state$active_kind <- NULL
  state$active_token <- 0L
  invisible(TRUE)
}

#' Aktif konuşma türünü oku (yoksa NULL).
mergen_speech_active_kind <- function(session) {
  state <- mergen_speech_state(session)
  state$active_kind
}

#' Aktif konuşma token'ını oku (yoksa 0L). İstemciden gelen "konuşma bitti"
#' yankılarının HANGİ konuşmaya ait olduğunu doğrulamak için kullanılır.
mergen_speech_active_token <- function(session) {
  state <- mergen_speech_state(session)
  state$active_token %||% 0L
}

#' Sonraki TTS parçalarını başlangıç mesajına kadar tutan gönderici.
mergen_speech_chunk_dispatcher <- function(session, token, is_speaking) {
  state <- new.env(parent = emptyenv())
  state$started <- FALSE
  state$claimed <- FALSE
  state$pending <- list()

  is_current <- function() {
    isTRUE(is_speaking()) && identical(
      as.integer(token), as.integer(mergen_speech_active_token(session))
    )
  }

  claim_synthesis <- function() {
    if (isTRUE(state$claimed) || !is_current()) return(FALSE)
    state$claimed <- TRUE
    TRUE
  }

  queue <- function(payload) {
    if (!is_current()) return(invisible(FALSE))
    if (isTRUE(state$started)) {
      session$sendCustomMessage("aiExpertQueueAudioChunk", payload)
      return(invisible(TRUE))
    }
    state$pending[[as.character(payload$index)]] <- payload
    invisible(TRUE)
  }

  start <- function() {
    if (!is_current()) return(invisible(FALSE))
    state$started <- TRUE
    if (length(state$pending) > 0L) {
      indexes <- sort(as.integer(names(state$pending)))
      for (index in indexes) {
        session$sendCustomMessage("aiExpertQueueAudioChunk", state$pending[[as.character(index)]])
      }
      state$pending <- list()
    }
    invisible(TRUE)
  }

  list(is_current = is_current, claim_synthesis = claim_synthesis,
       queue = queue, start = start)
}

#' Kişisel önek için konu metnini temizle: satır sonlarını at, kelime
#' sınırında kısalt. Hassas/uzun içerik konuşmaya taşınmaz.
mergen_speech_prefix_topic_clean <- function(topic, max_chars = 48L) {
  topic <- tryCatch(as.character(topic)[1], error = function(e) "")
  if (is.na(topic) || !nzchar(topic)) return("")

  topic <- gsub("[\r\n\t]+", " ", topic)
  topic <- gsub("\\s+", " ", trimws(topic))
  if (!nzchar(topic)) return("")

  if (nchar(topic) > max_chars) {
    cut <- substr(topic, 1, max_chars)
    space_pos <- regexpr("\\s[^\\s]*$", cut)
    if (space_pos > 10) cut <- substr(cut, 1, space_pos - 1)
    topic <- trimws(cut)
  }
  topic
}

#' Deterministik kişisel karşılama öneki. LLM ÇAĞRILMAZ; yalnızca eldeki
#' ad/son konu değerlerinden kurulur. Uygun değer yoksa boş döner (önek
#' isteğe bağlıdır ve statik karşılamayı asla geciktirmez).
mergen_speech_build_welcome_prefix <- function(first_name = "", recent_topics = NULL) {
  name <- tryCatch(trimws(as.character(first_name)[1]), error = function(e) "")
  if (is.na(name)) name <- ""

  topic <- ""
  if (!is.null(recent_topics) && length(recent_topics) > 0) {
    topic <- mergen_speech_prefix_topic_clean(recent_topics[[1]])
  }

  if (nzchar(name) && nzchar(topic)) {
    return(sprintf("Merhaba %s. En son %s konusu üzerine çalışmıştık.", name, topic))
  }
  if (nzchar(name)) {
    return(sprintf("Merhaba %s, yeniden hoş geldiniz.", name))
  }
  ""
}

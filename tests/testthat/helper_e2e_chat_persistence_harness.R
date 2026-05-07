# ==============================================================================
# Dosya Yolu: tests/testthat/helper_e2e_chat_persistence_harness.R
# Açıklama: Kayıtlı söyleşi, geçmiş ve galeri yarış durumları için gerçek DB,
#           tarayıcı veya servis gerektirmeyen deterministik E2E test harness'ı.
# ==============================================================================

e2e_cp_parse_time <- function(value) {
  if (inherits(value, "POSIXt")) {
    return(as.POSIXct(value, tz = "UTC"))
  }

  if (is.numeric(value)) {
    return(as.POSIXct(value, origin = "1970-01-01", tz = "UTC"))
  }

  parsed <- suppressWarnings(as.POSIXct(
    as.character(value)[1],
    tz = "UTC"
  ))

  if (is.na(parsed)) {
    parsed <- suppressWarnings(as.POSIXct(
      as.character(value)[1],
      format = "%d.%m.%Y - %H:%M",
      tz = "UTC"
    ))
  }

  if (is.na(parsed)) {
    return(as.POSIXct("1970-01-01 00:00:00", tz = "UTC"))
  }

  parsed
}

e2e_cp_make_message <- function(type,
                                content,
                                id = NULL,
                                timestamp = "2026-05-07 09:00:00",
                                reasoning_content = NULL) {
  list(
    id = id %||% paste0(type, "_", as.integer(stats::runif(1, 1, 999999))),
    type = type,
    content = enc2utf8(content),
    timestamp = timestamp,
    reasoning_content = reasoning_content
  )
}

e2e_cp_make_chat <- function(title,
                             timestamp,
                             messages = list(),
                             message_count = NULL) {
  list(
    title = enc2utf8(title),
    timestamp = timestamp,
    last_message_timestamp = timestamp,
    messages = messages,
    message_count = as.integer(message_count %||% length(messages))
  )
}

e2e_cp_saved_chat_meta <- function(chats) {
  if (is.null(chats) || length(chats) == 0L) {
    return(data.frame(
      chat_id = character(),
      title = character(),
      timestamp = as.POSIXct(character()),
      message_count = integer(),
      stringsAsFactors = FALSE
    ))
  }

  ids <- names(chats)
  timestamps <- vapply(chats, function(chat) {
    as.numeric(e2e_cp_parse_time(
      chat$last_message_timestamp %||% chat$timestamp
    ))
  }, numeric(1))

  meta <- data.frame(
    chat_id = ids,
    title = vapply(chats, function(chat) chat$title %||% "Söyleşi", character(1)),
    timestamp = as.POSIXct(timestamps, origin = "1970-01-01", tz = "UTC"),
    message_count = vapply(chats, function(chat) {
      as.integer(chat$message_count %||% length(chat$messages %||% list()))
    }, integer(1)),
    stringsAsFactors = FALSE
  )

  meta <- meta[order(meta$timestamp, decreasing = TRUE), , drop = FALSE]
  rownames(meta) <- NULL
  meta
}

e2e_cp_saved_chat_order <- function(chats) {
  e2e_cp_saved_chat_meta(chats)$chat_id
}

e2e_cp_new_state <- function(chats = list(),
                             current_chat_id = NULL,
                             current_messages = list()) {
  list(
    saved_chats = chats,
    current_chat_id = current_chat_id,
    messages = current_messages,
    show_welcome = length(current_messages) == 0L,
    finalized_requests = character(),
    saved_chat_updates = 0L,
    saved_chat_refreshes = 0L,
    history_refreshes = 0L,
    history_skips = 0L,
    history_cache = data.frame(
      Chat_ID = character(),
      Tarih = character(),
      Soru = character(),
      Cevap = character(),
      stringsAsFactors = FALSE
    ),
    gallery_refreshes = 0L,
    gallery_skips = 0L,
    gallery_cache = data.frame(
      file_path = character(),
      filename = character(),
      user_id = integer(),
      stringsAsFactors = FALSE
    ),
    tts_calls = 0L,
    load_chat_count = 0L,
    load_chat_in_progress = FALSE,
    last_deleted_chat_id = NULL,
    last_skip_reason = NULL,
    welcome_render_count = 0L,
    toasts = character()
  )
}

e2e_cp_valid_user_id <- function(user_id) {
  uid <- suppressWarnings(as.integer(user_id %||% 0L))
  !is.na(uid) && uid > 0L
}

e2e_cp_append_toast <- function(state, message) {
  state$toasts <- c(state$toasts, enc2utf8(message))
  state
}

e2e_cp_finalize_answer_once <- function(state,
                                        request_id,
                                        chat_id,
                                        title,
                                        user_text,
                                        ai_text,
                                        timestamp = "2026-05-07 10:00:00") {
  request_id <- as.character(request_id)
  chat_id <- as.character(chat_id)

  if (request_id %in% state$finalized_requests) {
    state$last_skip_reason <- "already_finalized"
    return(state)
  }

  user_msg <- e2e_cp_make_message(
    type = "user",
    content = user_text,
    id = paste0(request_id, "_user"),
    timestamp = timestamp
  )

  ai_msg <- e2e_cp_make_message(
    type = "ai",
    content = ai_text,
    id = paste0(request_id, "_ai"),
    timestamp = timestamp
  )

  messages <- c(state$messages, list(user_msg, ai_msg))

  state$messages <- messages
  state$current_chat_id <- chat_id
  state$show_welcome <- FALSE
  state$saved_chats[[chat_id]] <- e2e_cp_make_chat(
    title = title,
    timestamp = timestamp,
    messages = messages
  )
  state$finalized_requests <- c(state$finalized_requests, request_id)
  state$saved_chat_updates <- state$saved_chat_updates + 1L
  state$saved_chat_refreshes <- state$saved_chat_refreshes + 1L
  state$last_skip_reason <- "finalized"
  state
}

e2e_cp_load_chat <- function(state, chat_id) {
  chat_id <- as.character(chat_id %||% "")

  if (!nzchar(chat_id)) {
    state$last_skip_reason <- "empty_chat_id"
    return(state)
  }

  if (identical(chat_id, state$last_deleted_chat_id)) {
    state$last_deleted_chat_id <- NULL
    state$last_skip_reason <- "deleted_chat"
    return(state)
  }

  if (isTRUE(state$load_chat_in_progress)) {
    state$last_skip_reason <- "load_in_progress"
    return(state)
  }

  chat <- state$saved_chats[[chat_id]]
  if (is.null(chat)) {
    state$last_skip_reason <- "missing_chat"
    return(state)
  }

  state$load_chat_in_progress <- TRUE
  state$messages <- chat$messages %||% list()
  state$current_chat_id <- chat_id
  state$show_welcome <- FALSE
  state$load_chat_count <- state$load_chat_count + 1L
  state$last_skip_reason <- "loaded"
  state$load_chat_in_progress <- FALSE

  e2e_cp_append_toast(
    state,
    paste("Söyleşi yüklendi:", chat$title %||% "Söyleşi")
  )
}

e2e_cp_delete_chat <- function(state, chat_id) {
  chat_id <- as.character(chat_id %||% "")
  if (!nzchar(chat_id)) {
    state$last_skip_reason <- "empty_delete_id"
    return(state)
  }

  state$last_deleted_chat_id <- chat_id
  current_deleted <- identical(
    as.character(state$current_chat_id %||% ""),
    chat_id
  )

  state$saved_chats[[chat_id]] <- NULL
  state$saved_chat_refreshes <- state$saved_chat_refreshes + 1L
  state <- e2e_cp_append_toast(state, "Söyleşi silindi.")

  if (isTRUE(current_deleted)) {
    state$messages <- list()
    state$current_chat_id <- NULL
    state$show_welcome <- TRUE
    state$welcome_render_count <- state$welcome_render_count + 1L
  }

  state$last_skip_reason <- "deleted"
  state
}

e2e_cp_build_history_rows <- function(chats) {
  rows <- list()

  for (chat_id in names(chats)) {
    messages <- chats[[chat_id]]$messages %||% list()
    user_messages <- Filter(function(msg) identical(msg$type, "user"), messages)
    ai_messages <- Filter(function(msg) msg$type %in% c("ai", "assistant"), messages)
    pair_count <- min(length(user_messages), length(ai_messages))

    if (pair_count == 0L) {
      next
    }

    for (idx in seq_len(pair_count)) {
      rows[[length(rows) + 1L]] <- data.frame(
        Chat_ID = chats[[chat_id]]$title %||% chat_id,
        Tarih = user_messages[[idx]]$timestamp %||% "",
        Soru = substr(user_messages[[idx]]$content %||% "", 1, 100),
        Cevap = substr(ai_messages[[idx]]$content %||% "", 1, 100),
        stringsAsFactors = FALSE
      )
    }
  }

  if (length(rows) == 0L) {
    return(data.frame(
      Chat_ID = character(),
      Tarih = character(),
      Soru = character(),
      Cevap = character(),
      stringsAsFactors = FALSE
    ))
  }

  do.call(rbind, rows)
}

e2e_cp_refresh_history <- function(state, user_id) {
  if (!e2e_cp_valid_user_id(user_id)) {
    state$history_skips <- state$history_skips + 1L
    state$last_skip_reason <- "invalid_history_user"
    return(state)
  }

  state$history_cache <- e2e_cp_build_history_rows(state$saved_chats)
  state$history_refreshes <- state$history_refreshes + 1L
  state$last_skip_reason <- "history_refreshed"
  state
}

e2e_cp_refresh_gallery <- function(state, user_id, images_by_user) {
  if (!e2e_cp_valid_user_id(user_id)) {
    state$gallery_skips <- state$gallery_skips + 1L
    state$last_skip_reason <- "invalid_gallery_user"
    return(state)
  }

  key <- as.character(as.integer(user_id))
  images <- images_by_user[[key]] %||% data.frame(
    file_path = character(),
    filename = character(),
    user_id = integer(),
    stringsAsFactors = FALSE
  )

  state$gallery_cache <- images
  state$gallery_refreshes <- state$gallery_refreshes + 1L
  state$last_skip_reason <- "gallery_refreshed"
  state
}

e2e_cp_read_repo_text <- function(path) {
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
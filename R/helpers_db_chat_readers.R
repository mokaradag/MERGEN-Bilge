# ==============================================================================
# Dosya Yolu: R/helpers_db_chat_readers.R
# Açıklama: MERGEN Bilge sohbet listeleme, mesaj hidratasyonu ve geçmiş okuma
#           veritabanı yardımcılarını içerir.
#
# Not:
# - Bağlantı yardımcıları R/helpers_db_connection.R içindedir.
# - Mesaj satırı biçimlendirme R/helpers_chat_message_formatting.R içindedir.
# - Yazma/mutasyon işlemleri R/helpers_db_chat_mutations.R içindedir.
# ==============================================================================

.db_chat_valid_user_id <- function(user_id) {
  if (is.null(user_id) || length(user_id) == 0L) {
    return(FALSE)
  }

  safe_user_id <- suppressWarnings(as.integer(user_id[1]))
  !is.na(safe_user_id) && safe_user_id > 0L
}

.db_chat_timestamp_missing <- function(value) {
  is.null(value) || length(value) == 0L || is.na(value[1])
}

.db_chat_as_numeric_timestamp <- function(value) {
  if (.db_chat_timestamp_missing(value)) {
    return(0)
  }

  value <- value[1]

  if (inherits(value, "POSIXt")) {
    return(as.numeric(value))
  }

  if (inherits(value, "Date")) {
    return(as.numeric(as.POSIXct(value, tz = "UTC")))
  }

  # as.POSIXct ayrıştırılamayan string'lerde uyarı değil HATA fırlatır; tryCatch ile
  # NA'ya indirgeyerek aşağıdaki 0 geri dönüşünü (tasarlanan güvenli varsayılan) koru.
  parsed <- tryCatch(
    suppressWarnings(as.POSIXct(as.character(value), tz = "UTC")),
    error = function(e) NA
  )
  if (length(parsed) == 0L || is.na(parsed[1])) {
    return(0)
  }

  as.numeric(parsed[1])
}

# Load chats and their messages for a user (returns list)
# process_message_content() fallback is provided if missing.
load_chats_preview_from_db <- function(user_id, limit = 30L) {
  stopifnot(!is.null(user_id))

  if (!.db_chat_valid_user_id(user_id)) {
    return(list())
  }

  safe_user_id <- suppressWarnings(as.integer(user_id[1]))

  safe_limit <- suppressWarnings(as.integer(limit))
  if (is.na(safe_limit) || safe_limit <= 0) {
    safe_limit <- 30L
  }

  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- db_chat_preview_query_sql(safe_limit)

  preview_data <- dbGetQuery(
    conn,
    query,
    params = normalize_db_params(list(safe_user_id))
  )

  if (exists("normalize_db_read_visible_frame", mode = "function", inherits = TRUE)) {
    preview_data <- normalize_db_read_visible_frame(preview_data, repair_mojibake = TRUE)
  } else if (exists("normalize_text_frame_utf8", mode = "function", inherits = TRUE)) {
    preview_data <- normalize_text_frame_utf8(preview_data, repair_mojibake = TRUE)
  }

  if (nrow(preview_data) == 0) return(list())

  chat_ids <- as.character(preview_data$ChatID)
  formatted <- lapply(seq_len(nrow(preview_data)), function(i) {
    row <- preview_data[i, ]

    last_ts <- row$LastMessageTimestamp
    if (.db_chat_timestamp_missing(last_ts)) {
      last_ts <- row$CreateTimestamp
    }

    msg_count <- row$MessageCount %||% 0L
    msg_count <- suppressWarnings(as.integer(msg_count[1]))
    if (is.na(msg_count)) {
      msg_count <- 0L
    }

    list(
      title = row$ChatTitle,
      messages = NULL,
      timestamp = row$CreateTimestamp,
      last_message_timestamp = last_ts,
      message_count = msg_count
    )
  })

  names(formatted) <- chat_ids
  formatted[chat_ids]
}

load_chats_from_db <- function(user_id, include_messages = TRUE) {
  stopifnot(!is.null(user_id))

  if (!.db_chat_valid_user_id(user_id)) {
    return(list())
  }

  safe_user_id <- suppressWarnings(as.integer(user_id[1]))

  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  if (!isTRUE(include_messages)) {
    query <- db_chat_list_summary_query_sql()

    summary_data <- dbGetQuery(
      conn,
      query,
      params = normalize_db_params(list(safe_user_id))
    )

    if (exists("normalize_db_read_visible_frame", mode = "function", inherits = TRUE)) {
      summary_data <- normalize_db_read_visible_frame(summary_data, repair_mojibake = TRUE)
    } else if (exists("normalize_text_frame_utf8", mode = "function", inherits = TRUE)) {
      summary_data <- normalize_text_frame_utf8(summary_data, repair_mojibake = TRUE)
    }

    if (nrow(summary_data) == 0) return(list())

    unique_chat_ids <- as.character(summary_data$ChatID)

    formatted <- lapply(seq_len(nrow(summary_data)), function(i) {
      row <- summary_data[i, ]

      msg_count <- ifelse(is.na(row$MessageCount), 0L, row$MessageCount)

      last_ts <- row$LastMessageTimestamp
      if (.db_chat_timestamp_missing(last_ts)) {
        last_ts <- row$CreateTimestamp
      }

      list(
        title = row$ChatTitle,
        messages = NULL,
        timestamp = row$CreateTimestamp,
        last_message_timestamp = last_ts,
        message_count = as.integer(msg_count)
      )
    })

    names(formatted) <- unique_chat_ids
    formatted <- formatted[unique_chat_ids]
    return(formatted)
  }

  query_with_reasoning <- db_chat_list_full_query_sql(with_reasoning = TRUE)

  query_legacy <- db_chat_list_full_query_sql(with_reasoning = FALSE)

  all_data <- safe_select_messages_with_reasoning(
    conn,
    query_with_reasoning,
    query_legacy,
    params = normalize_db_params(list(safe_user_id))
  )

  if (exists("normalize_db_read_visible_frame", mode = "function", inherits = TRUE)) {
    all_data <- normalize_db_read_visible_frame(all_data, repair_mojibake = TRUE)
  } else if (exists("normalize_text_frame_utf8", mode = "function", inherits = TRUE)) {
    all_data <- normalize_text_frame_utf8(all_data, repair_mojibake = TRUE)
  }

  if (nrow(all_data) == 0) return(list())

  unique_chat_ids <- unique(all_data$ChatID)

  chat_list <- split(all_data, all_data$ChatID)

  formatted_chats <- lapply(chat_list, function(chat_df) {
    messages <- format_chat_messages(chat_df)

    last_msg_time <- if (nrow(chat_df) > 0 &&
                         "MessageTimestamp" %in% names(chat_df) &&
                         any(!is.na(chat_df$MessageTimestamp))) {
      max(chat_df$MessageTimestamp, na.rm = TRUE)
    } else {
      chat_df$CreateTimestamp[1]
    }

    list(
      title = chat_df$ChatTitle[1],
      messages = messages,
      timestamp = chat_df$CreateTimestamp[1],
      last_message_timestamp = last_msg_time,
      message_count = length(messages)
    )
  })

  formatted_chats <- formatted_chats[as.character(unique_chat_ids)]
  formatted_chats
}

# Düşünen modeller için ReasoningContent sütununu içeren SELECT'i dener;
# sütun şemaya henüz eklenmemişse sessizce eski sütun kümesine düşer.
# query_with_reasoning: ReasoningContent içeren tam SELECT
# query_legacy:        Eski (ReasoningContent'sız) SELECT
safe_select_messages_with_reasoning <- function(conn, query_with_reasoning, query_legacy, params = list()) {
  tryCatch({
    dbGetQuery(conn, query_with_reasoning, params = params)
  }, error = function(e) {
    hata <- conditionMessage(e)

    yalnizca_sema_uyumsuzlugu <- grepl(
      "ReasoningContent|Invalid column name|unknown column|no such column",
      hata,
      ignore.case = TRUE
    )

    if (!isTRUE(yalnizca_sema_uyumsuzlugu)) {
      stop(e)
    }

    log_warn("ReasoningContent sütunu bulunamadı; legacy sorguya düşülüyor.")
    dbGetQuery(conn, query_legacy, params = params)
  })
}

load_chat_messages_from_db <- function(chat_id, user_id = NULL) {
  stopifnot(!is.null(chat_id))

  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  chat_param <- suppressWarnings(as.integer(chat_id))
  if (is.na(chat_param)) {
    chat_param <- chat_id
  }

  if (is.null(user_id)) {
    query_with_reasoning <- db_chat_messages_query_sql(with_reasoning = TRUE, scoped = FALSE)

    query_legacy <- db_chat_messages_query_sql(with_reasoning = FALSE, scoped = FALSE)

    query_params <- normalize_db_params(list(chat_param))
  } else {
    if (!.db_chat_valid_user_id(user_id)) {
      stop("Geçersiz user_id ile sohbet yükleme denendi.")
    }

    safe_user_id <- suppressWarnings(as.integer(user_id[1]))

    query_with_reasoning <- db_chat_messages_query_sql(with_reasoning = TRUE, scoped = TRUE)

    query_legacy <- db_chat_messages_query_sql(with_reasoning = FALSE, scoped = TRUE)

    query_params <- normalize_db_params(list(chat_param, safe_user_id))
  }

  chat_df <- safe_select_messages_with_reasoning(
    conn,
    query_with_reasoning,
    query_legacy,
    params = query_params
  )

  if (exists("normalize_db_read_visible_frame", mode = "function", inherits = TRUE)) {
    chat_df <- normalize_db_read_visible_frame(chat_df, repair_mojibake = TRUE)
  } else if (exists("normalize_text_frame_utf8", mode = "function", inherits = TRUE)) {
    chat_df <- normalize_text_frame_utf8(chat_df, repair_mojibake = TRUE)
  }

  if (nrow(chat_df) == 0) {
    return(list(title = NULL, timestamp = NULL, messages = list(), message_count = 0L))
  }

  messages_df <- chat_df[!is.na(chat_df$MessageID), , drop = FALSE]
  messages <- if (nrow(messages_df) > 0) format_chat_messages(messages_df) else list()

  list(
    title = chat_df$ChatTitle[1],
    timestamp = chat_df$CreateTimestamp[1],
    messages = messages,
    message_count = length(messages)
  )
}

load_chat_messages_batch <- function(chat_ids, user_id = NULL) {
  if (is.null(chat_ids) || length(chat_ids) == 0) {
    return(list())
  }

  ids <- unique(as.character(chat_ids))
  ids <- ids[nzchar(ids)]
  if (length(ids) == 0) {
    return(list())
  }

  placeholder <- paste(rep("?", length(ids)), collapse = ", ")

  param_values <- lapply(ids, function(id) {
    numeric_id <- suppressWarnings(as.integer(id))
    if (!is.na(numeric_id)) {
      numeric_id
    } else {
      id
    }
  })

  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  if (is.null(user_id)) {
    query_with_reasoning <- db_chat_messages_batch_query_sql(placeholder, with_reasoning = TRUE, scoped = FALSE)

    query_legacy <- db_chat_messages_batch_query_sql(placeholder, with_reasoning = FALSE, scoped = FALSE)
  } else {
    if (!.db_chat_valid_user_id(user_id)) {
      stop("Geçersiz user_id ile toplu sohbet yükleme denendi.")
    }

    safe_user_id <- suppressWarnings(as.integer(user_id[1]))

    query_with_reasoning <- db_chat_messages_batch_query_sql(placeholder, with_reasoning = TRUE, scoped = TRUE)

    query_legacy <- db_chat_messages_batch_query_sql(placeholder, with_reasoning = FALSE, scoped = TRUE)

    param_values <- c(param_values, list(safe_user_id))
  }

  result <- safe_select_messages_with_reasoning(
    conn,
    query_with_reasoning,
    query_legacy,
    params = normalize_db_params(param_values)
  )

  if (exists("normalize_db_read_visible_frame", mode = "function", inherits = TRUE)) {
    result <- normalize_db_read_visible_frame(result, repair_mojibake = TRUE)
  } else if (exists("normalize_text_frame_utf8", mode = "function", inherits = TRUE)) {
    result <- normalize_text_frame_utf8(result, repair_mojibake = TRUE)
  }

  if (nrow(result) == 0) {
    empty <- stats::setNames(vector("list", length(ids)), ids)
    return(lapply(empty, function(...) {
      list(
        title = NULL,
        timestamp = NULL,
        messages = list(),
        message_count = 0L,
        last_message_timestamp = NULL
      )
    }))
  }

  split_rows <- split(result, result$ChatID)
  names(split_rows) <- as.character(names(split_rows))

  formatted <- lapply(split_rows, function(chat_df) {
    messages_df <- chat_df[!is.na(chat_df$MessageID), , drop = FALSE]
    messages <- if (nrow(messages_df) > 0) format_chat_messages(messages_df) else list()

    last_ts <- if (nrow(messages_df) > 0 &&
                   "MessageTimestamp" %in% names(messages_df) &&
                   any(!is.na(messages_df$MessageTimestamp))) {
      max(messages_df$MessageTimestamp, na.rm = TRUE)
    } else {
      chat_df$CreateTimestamp[1]
    }

    list(
      title = chat_df$ChatTitle[1],
      timestamp = chat_df$CreateTimestamp[1],
      messages = messages,
      message_count = length(messages),
      last_message_timestamp = last_ts
    )
  })

  names(formatted) <- as.character(names(formatted))

  # Etkinlik zamanına göre sırala (en yeni önce)
  if (length(formatted) > 1) {
    timestamps <- vapply(formatted, function(chat) {
      .db_chat_as_numeric_timestamp(chat$last_message_timestamp %||% chat$timestamp)
    }, numeric(1))

    sorted_order <- order(timestamps, decreasing = TRUE)
    formatted <- formatted[sorted_order]
  }

  missing_ids <- setdiff(ids, names(formatted))
  if (length(missing_ids) > 0) {
    for (mid in missing_ids) {
      formatted[[mid]] <- list(
        title = NULL,
        timestamp = NULL,
        messages = list(),
        message_count = 0L,
        last_message_timestamp = NULL
      )
    }
  }

  formatted
}

# Lightweight history fetch: return paired user/assistant rows per chat
load_history_rows_batch <- function(chat_ids, user_id = NULL) {
  if (is.null(chat_ids) || length(chat_ids) == 0) {
    return(list())
  }

  ids <- unique(as.character(chat_ids))
  ids <- ids[nzchar(ids)]
  if (length(ids) == 0) {
    return(list())
  }

  placeholder <- paste(rep("?", length(ids)), collapse = ", ")

  param_values <- lapply(ids, function(id) {
    numeric_id <- suppressWarnings(as.integer(id))
    if (!is.na(numeric_id)) numeric_id else id
  })

  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  if (is.null(user_id)) {
    query <- db_history_rows_query_sql(placeholder, scoped = FALSE)
  } else {
    if (!.db_chat_valid_user_id(user_id)) {
      stop("Geçersiz user_id ile geçmiş yükleme denendi.")
    }

    safe_user_id <- suppressWarnings(as.integer(user_id[1]))

    query <- db_history_rows_query_sql(placeholder, scoped = TRUE)

    param_values <- c(param_values, list(safe_user_id))
  }

  result <- dbGetQuery(
    conn,
    query,
    params = normalize_db_params(param_values)
  )

  if (exists("normalize_db_read_visible_frame", mode = "function", inherits = TRUE)) {
    result <- normalize_db_read_visible_frame(result, repair_mojibake = TRUE)
  } else if (exists("normalize_text_frame_utf8", mode = "function", inherits = TRUE)) {
    result <- normalize_text_frame_utf8(result, repair_mojibake = TRUE)
  }

  if (nrow(result) == 0) {
    empty <- stats::setNames(vector("list", length(ids)), ids)
    return(lapply(empty, function(...) list()))
  }

  format_history_timestamp <- function(value) {
    if (inherits(value, "POSIXt")) {
      return(format(value, "%d.%m.%Y - %H:%M", tz = attr(value, "tzone") %||% "UTC"))
    }

    parsed <- suppressWarnings(as.POSIXct(value, tz = "UTC"))
    if (!is.na(parsed)) {
      return(format(parsed, "%d.%m.%Y - %H:%M", tz = attr(parsed, "tzone") %||% "UTC"))
    }

    as.character(value %||% "")
  }

  safe_chr <- function(value) {
    if (is.null(value) || length(value) == 0 || is.na(value[1])) {
      return("")
    }
    as.character(value[1])
  }

  split_rows <- split(result, as.character(result$ChatID))
  names(split_rows) <- as.character(names(split_rows))

  formatted <- lapply(ids, function(chat_id) {
    chat_df <- split_rows[[chat_id]]
    if (is.null(chat_df) || nrow(chat_df) == 0) {
      return(list())
    }

    lapply(seq_len(nrow(chat_df)), function(i) {
      list(
        Chat_ID = safe_chr(chat_df$ChatTitle[i]),
        Tarih = format_history_timestamp(chat_df$MessageTimestamp[i]),
        Soru = safe_chr(chat_df$Soru[i]),
        Cevap = safe_chr(chat_df$Cevap[i])
      )
    })
  })

  names(formatted) <- ids
  formatted
}
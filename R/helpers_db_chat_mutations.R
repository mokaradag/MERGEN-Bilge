# ==============================================================================
# Dosya Yolu: R/helpers_db_chat_mutations.R
# Açıklama: MERGEN Bilge sohbet ve mesaj yazma/mutasyon veritabanı yardımcıları.
#
# Not:
# - Bağlantı yardımcıları R/helpers_db_connection.R içindedir.
# - Doğrulama yardımcıları R/helpers_db_validation.R içindedir.
# - Sohbet okuma/listeleme yardımcıları R/helpers_db_chat_readers.R içindedir.
# - Kullanıcı, geri bildirim ve kullanım log işlemleri R/helpers_database.R
#   içinde kalır.
# ==============================================================================

# Create new chat, return ChatID integer (UPDATED with validation)
create_new_chat_in_db <- function(user_id, initial_title = "Yeni Söyleşi") {
  stopifnot(!is.null(user_id))
  
  # ADDED: Input validation
  validate_chat_title(initial_title)

  initial_title <- normalize_db_visible_value(initial_title)
  
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "INSERT INTO MB_Chats (UserID, ChatTitle) OUTPUT INSERTED.ChatID AS ChatID VALUES (?, ?)"
  res <- dbGetQuery(conn, query, params = normalize_db_params(list(user_id, initial_title)))
  if (nrow(res) == 0) stop("Failed to create new chat session in DB.")
  return(as.integer(res$ChatID[1]))
}

sanitize_input <- function(text) {
  warning("sanitize_input() is deprecated when using parameterized queries")
  return(text)
}

# ------------------------------------------------------------------------------
# MESAJ REASONINGCONTENT GÜNCELLEME YARDIMCISI
# ------------------------------------------------------------------------------
# Not: save_message_to_db() eski şemalarla uyumlu kalabilir. Bu yardımcı,
# ReasoningContent sütunu varsa kaydı güvenli şekilde sonradan günceller.
update_message_reasoning_content <- function(message_id, reasoning_content) {
  if (is.null(message_id) || is.na(message_id)) {
    return(invisible(FALSE))
  }

  reasoning_text <- tryCatch({
    value <- as.character(reasoning_content %||% "")[1]
	normalize_db_visible_value(value)
  }, error = function(e) "")

  if (!nzchar(reasoning_text)) {
    return(invisible(FALSE))
  }

  conn_info <- NULL

  tryCatch({
    conn_info <- get_connection()
    conn <- conn_info$conn

    has_column <- tryCatch({
      cols <- DBI::dbGetQuery(
        conn,
        "
        SELECT COLUMN_NAME
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'MB_Messages'
          AND COLUMN_NAME = 'ReasoningContent'
        "
      )
      nrow(cols) > 0
    }, error = function(e) {
      FALSE
    })

    if (!isTRUE(has_column)) {
      log_warn("MB_Messages.ReasoningContent sütunu bulunamadı; reasoning kaydı atlandı.")
      return(invisible(FALSE))
    }

    DBI::dbExecute(
      conn,
      "
      UPDATE MB_Messages
      SET ReasoningContent = ?
      WHERE MessageID = ?
      ",
	  params = normalize_db_params(
	    list(reasoning_text, message_id)
	  )
    )

    invisible(TRUE)
  }, error = function(e) {
    log_warn("ReasoningContent güncellenemedi (MessageID={message_id}): {conditionMessage(e)}")
    invisible(FALSE)
  }, finally = {
    release_connection(conn_info)
  })
}

# Save message (synchronous/main process or worker-safe if get_connection created a worker conn)
# msg is a list: list(content=..., type="user"/"assistant", timestamp=POSIXct or formatted string)
save_message_to_db <- function(chat_id, msg) {
  stopifnot(!is.null(chat_id))
  stopifnot(is.list(msg) && !is.null(msg$content) && !is.null(msg$type))

  # Validate message content
  validate_message_content(msg$content)

  msg$content <- normalize_db_visible_value(msg$content)
  msg$type <- normalize_db_technical_value(msg$type)

  # İşlem-güvenli bağlantı: havuz aktifse gerçek bağlantı ödünç alınır (havuz
  # nesnesi DEĞİL); havuz katmanı yoksa (izole test) doğrudan bağlantıya düşülür.
  use_pool_tx <- exists("db_acquire_tx_connection", mode = "function", inherits = TRUE)
  conn_info <- if (use_pool_tx) db_acquire_tx_connection("primary") else get_connection()
  conn <- conn_info$conn
  on.exit(if (use_pool_tx) db_release_tx_connection(conn_info) else release_connection(conn_info))

  # Düşünen modeller için biriken akıl yürütme metni, ReasoningContent
  # sütununda saklanır. Sütun yoksa (eski şema) sessizce yalnızca eski
  # alanlar yazılır; böylece geriye dönük uyumluluk korunur.
  reasoning_content <- msg$reasoning_content %||% msg$reasoning_trace
  if (!is.null(reasoning_content)) {
    reasoning_content <- normalize_db_visible_value(reasoning_content)
  }
  if (is.null(reasoning_content) || !nzchar(reasoning_content)) {
    reasoning_content <- NA_character_
  }

  ts <- format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "Europe/Istanbul")

  next_order_query <- "
    SELECT ISNULL(MAX(MessageOrder), 0) + 1 AS next_order
    FROM MB_Messages WITH (UPDLOCK, HOLDLOCK)
    WHERE ChatID = ?
  "

  DBI::dbBegin(conn)
  committed <- FALSE
  # after = FALSE: rollback, bağlantı iadesinden (yukarıdaki on.exit) ÖNCE
  # çalışır; havuzlu bağlantı açık işlemle iade edilmez.
  on.exit({
    if (!committed) {
      try(DBI::dbRollback(conn), silent = TRUE)
    }
  }, add = TRUE, after = FALSE)

  next_order <- dbGetQuery(conn, next_order_query, params = list(chat_id))$next_order[1]
  next_order <- as.integer(next_order %||% 1L)

  query_with_reasoning <- "
    INSERT INTO MB_Messages (ChatID, MessageContent, MessageType, MessageTimestamp, MessageOrder, ReasoningContent)
    OUTPUT INSERTED.MessageID AS MessageID
    VALUES (?, ?, ?, ?, ?, ?)
  "
  query_legacy <- "
    INSERT INTO MB_Messages (ChatID, MessageContent, MessageType, MessageTimestamp, MessageOrder)
    OUTPUT INSERTED.MessageID AS MessageID
    VALUES (?, ?, ?, ?, ?)
  "

  res <- tryCatch({
    dbGetQuery(
      conn,
      query_with_reasoning,
	  params = normalize_db_params(
	    list(chat_id, msg$content, msg$type, ts, next_order, reasoning_content)
	  )
    )
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

    log_warn("ReasoningContent sütunu bulunamadı; legacy mesaj kaydına düşülüyor.")

    dbGetQuery(
      conn,
      query_legacy,
	  params = normalize_db_params(
	    list(chat_id, msg$content, msg$type, ts, next_order)
	  )
    )
  })

	if (nrow(res) == 0) stop("Failed to save message to DB.")

	message_id <- as.integer(res$MessageID[1])

	if (exists("assert_mb_message_visible_encoding_clean", mode = "function", inherits = TRUE)) {
	  assert_mb_message_visible_encoding_clean(conn, message_id)
	}

	DBI::dbCommit(conn)
	committed <- TRUE

	return(message_id)
}

# Safe message saving with fallback logging
save_message_safely <- function(chat_id, message, user_id = NULL) {
  tryCatch({
    save_message_to_db(chat_id, message)
  }, error = function(e) {
    # Log failed messages to file for recovery
    log_file <- file.path(tempdir(), paste0("failed_messages_", Sys.Date(), ".log"))
    log_entry <- list(
      timestamp = Sys.time(),
      chat_id = chat_id,
      message = message,
      user_id = user_id,
      error = e$message
    )
    log_json <- as.character(jsonlite::toJSON(log_entry, auto_unbox = TRUE))
    if (exists("normalize_text_for_log", mode = "function", inherits = TRUE)) {
      log_json <- normalize_text_for_log(log_json)
    }
    if (exists("redact_sensitive_text", mode = "function", inherits = TRUE)) {
      log_json <- redact_sensitive_text(log_json)
    }

    cat(log_json, "\n", file = log_file, append = TRUE, useBytes = TRUE)
    warning(paste("Message save failed, logged to:", log_file))
    return(NULL)
  })
}                          

# Update an existing message's content in the database
update_message_content_in_db <- function(message_id, new_content) {
  stopifnot(!is.null(message_id), is.character(new_content))
  
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))
  
  new_content <- normalize_db_visible_value(new_content)

  query <- "UPDATE MB_Messages SET MessageContent = ? WHERE MessageID = ?"
  
  # Execute the update statement
  dbExecute(
    conn,
    query,
	params = normalize_db_params(
	  list(new_content, as.integer(message_id))
	)
  )
}

update_chat_title_in_db <- function(chat_id, new_title) {
  stopifnot(!is.null(chat_id))
  
  # ADDED: Input validation
  validate_chat_title(new_title)
  
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  new_title <- normalize_db_visible_value(new_title)

  query <- "UPDATE MB_Chats SET ChatTitle = ? WHERE ChatID = ?"
  dbExecute(
    conn,
    query,
    params = normalize_db_params(list(new_title, chat_id))
  )
}

# Chat deletion
delete_chat_from_db <- function(chat_id, user_id) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  # Önce sohbetin görsel klasörünü sil (varsa)
  tryCatch({
    image_dir <- file.path("user_images", as.character(user_id), as.character(chat_id))
    if (dir.exists(image_dir)) {
      # Klasördeki tüm dosyaları ve klasörün kendisini sil
      unlink(image_dir, recursive = TRUE)
      cat("[DATABASE] Görsel klasörü silindi:", image_dir, "\n")
    }
  }, error = function(e) {
    cat("[DATABASE] Görsel klasörü silinirken hata:", e$message, "\n")
  })

  # Sohbeti silinmiş olarak işaretle
  query <- "UPDATE MB_Chats SET IsDeleted = 1 WHERE ChatID = ? AND UserID = ?"
  dbExecute(conn, query, params = list(chat_id, user_id))
}

clear_all_chats_from_db <- function(user_id) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  # Önce kullanıcının tüm görsel klasörlerini sil
  tryCatch({
    user_image_dir <- file.path("user_images", as.character(user_id))
    if (dir.exists(user_image_dir)) {
      # Kullanıcının tüm görsel klasörlerini sil
      unlink(user_image_dir, recursive = TRUE)
      cat("[DATABASE] Kullanıcının tüm görsel klasörleri silindi:", user_image_dir, "\n")
    }
  }, error = function(e) {
    cat("[DATABASE] Görsel klasörleri silinirken hata:", e$message, "\n")
  })

  # Tüm sohbetleri silinmiş olarak işaretle
  query <- "UPDATE MB_Chats SET IsDeleted = 1 WHERE UserID = ?"
  dbExecute(conn, query, params = list(user_id))
}

# -------------------------
# Worker-safe convenience
# -------------------------
# Use inside future / worker. Do NOT reference Shiny reactives here.
# Example usage inside future:
#   future({
#     worker_save_assistant_response(chat_id = chat_id_val, response_text = resp, model_used = "<local-llm>", user_id = user_id)
#   })
worker_save_assistant_response <- function(chat_id, response_text,
                                           message_type = "assistant",
                                           timestamp = Sys.time(),
                                           log_usage = TRUE,
                                           user_id = NULL,
                                           model_used = "<local-llm>",
                                           duration = 0.0) {
  response_text <- normalize_db_visible_value(response_text)
  message_type <- normalize_db_technical_value(message_type)
  model_used <- normalize_db_technical_value(model_used)

  conn <- worker_db_connect()
  committed <- FALSE

  on.exit({
    if (!committed) {
      try(DBI::dbRollback(conn), silent = TRUE)
    }
    tryCatch({
      if (DBI::dbIsValid(conn)) {
        DBI::dbDisconnect(conn)
      }
    }, error = function(e) NULL)
  }, add = TRUE)

  next_order_q <- "
    SELECT ISNULL(MAX(MessageOrder), 0) + 1 AS next_order
    FROM MB_Messages WITH (UPDLOCK, HOLDLOCK)
    WHERE ChatID = ?
  "

  DBI::dbBegin(conn)

  next_order <- tryCatch(
    DBI::dbGetQuery(conn, next_order_q, params = list(chat_id))$next_order[1],
    error = function(e) NA_integer_
  )
  if (is.na(next_order)) next_order <- 1L
  next_order <- as.integer(next_order)

  timestamp_gmt3 <- format(timestamp, "%Y-%m-%d %H:%M:%S", tz = "Europe/Istanbul")

  insert_q <- "
    INSERT INTO MB_Messages (ChatID, MessageContent, MessageType, MessageTimestamp, MessageOrder)
    OUTPUT INSERTED.MessageID AS MessageID
    VALUES (?, ?, ?, ?, ?)
  "

  res <- DBI::dbGetQuery(
    conn,
    insert_q,
	params = normalize_db_params(
	  list(chat_id, response_text, message_type, timestamp_gmt3, next_order)
	)
  )

	response_message_id <- if (nrow(res) > 0) as.integer(res$MessageID[1]) else NA_integer_

	if (!is.na(response_message_id) &&
		exists("assert_mb_message_visible_encoding_clean", mode = "function", inherits = TRUE)) {
	  assert_mb_message_visible_encoding_clean(conn, response_message_id)
	}

	DBI::dbCommit(conn)
	committed <- TRUE

  if (isTRUE(log_usage) && !is.na(response_message_id)) {
    tryCatch({
      log_q <- "
        INSERT INTO MB_Usage_Log
          (ChatID, MessageID, UserID, ModelUsed, ResponseDuration, ResponseSuccess)
        VALUES (?, ?, ?, ?, ?, ?)
      "
      DBI::dbExecute(
        conn,
        log_q,
        params = normalize_db_params(list(
          chat_id, response_message_id, user_id, model_used, duration, 1
        ))
      )
    }, error = function(e) {
      log_warn("Worker usage log yazılamadı: {e$message}")
    })
  }

  response_message_id
}
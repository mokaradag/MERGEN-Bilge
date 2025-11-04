# helpers_database.R
# Complete, corrected helpers for DB access and worker-safe operations.
# - Never serialize pool/DBI external pointers into workers.
# - Worker functions create their own DB connections (no 'pool' needed).
# - These functions DO NOT access Shiny reactives; always pass plain R values
#   (e.g. chat_id, user_id, prompt_text) into futures/workers. Capture reactives
#   in the main Shiny reactive context BEFORE starting background work.
#
# Usage:
# 1) In main process: source("helpers_database.R"); call init_db_pool(dsn) if you want a pool.
# 2) In server code: capture reactive values (e.g. chat_id <- isolate(rv$current_chat_id)) and
#    pass those primitives into futures.
# 3) In workers (future blocks) call worker_save_assistant_response(...) which will create
#    a fresh DB connection inside the worker.
#
# NOTE: This file assumes a SQL Server-like OUTPUT ... INSERTED.MessageID behavior.
#       If your DB differs, adjust the INSERT returning syntax accordingly.

library(DBI)
library(odbc)
library(pool)

# --- Configuration ---
.DEFAULT_DSN <- Sys.getenv("DB_DSN", "TestConnection")

# Global pool (created by init_db_pool). May be NULL if not created.
pool <- NULL

# Get pool statistics
get_pool_info <- function() {
  return(list(
    valid = TRUE,
    mode = "Direct Connections",
    note = "Doğrudan bağlantı modu kullanılıyor (havuz devre dışı)"
  ))
}

# Get connection - returns the pool or connection object directly
# The pool library automatically handles checkout/return when you use it directly
get_connection <- function() {
  # Use pool directly if available - pool handles checkout/return automatically
  if (exists("pool", envir = .GlobalEnv)) {
    pool_obj <- get("pool", envir = .GlobalEnv)
    if (!is.null(pool_obj) && inherits(pool_obj, "Pool")) {
      return(list(conn = pool_obj, pooled = TRUE, pool = pool_obj))
    }
  }

  # Fallback: create direct DBI connection for workers
  if (!requireNamespace("odbc", quietly = TRUE) || !requireNamespace("DBI", quietly = TRUE)) {
    stop("Worker/process requires 'odbc' and 'DBI' packages installed.")
  }
  
  conn <- DBI::dbConnect(odbc::odbc(), dsn = Sys.getenv("DB_DSN", .DEFAULT_DSN))
  return(list(conn = conn, pooled = FALSE, pool = NULL))
}

# Release connection - only disconnect if it's NOT a pool
release_connection <- function(conn_info) {
  if (is.null(conn_info)) return(invisible(NULL))
  
  # If it's a pool, do nothing - pool manages its own connections
  if (isTRUE(conn_info$pooled)) {
    return(invisible(NULL))
  }
  
  # Only disconnect direct connections (non-pooled)
  tryCatch({
    DBI::dbDisconnect(conn_info$conn)
  }, error = function(e) {
    # ignore
  })
  
  invisible(NULL)
}

# Release connection returned by get_connection()
release_connection <- function(conn_info) {
  if (is.null(conn_info)) return(invisible(NULL))
  if (isTRUE(conn_info$pooled)) {
    tryCatch({
      poolReturn(conn_info$conn)
    }, error = function(e) {
      # ignore
    })
  } else {
    tryCatch({
      DBI::dbDisconnect(conn_info$conn)
    }, error = function(e) {
      # ignore
    })
  }
  invisible(NULL)
}

# Worker-side helper: create a fresh DBI connection in the worker with retry logic
worker_db_connect <- function(max_retries = 3, retry_delay = 1) {
  for (i in 1:max_retries) {
    tryCatch({
      if (!requireNamespace("odbc", quietly = TRUE) || !requireNamespace("DBI", quietly = TRUE)) {
        stop("Worker needs 'odbc' and 'DBI' packages installed.")
      }
      conn <- DBI::dbConnect(odbc::odbc(), dsn = Sys.getenv("DB_DSN", .DEFAULT_DSN))
      return(conn)
    }, error = function(e) {
      if (i == max_retries) {
        stop(paste("Failed to connect to database after", max_retries, "attempts:", e$message))
      }
      Sys.sleep(retry_delay * i)  # Exponential backoff
    })
  }
}

# -------------------------
# Input Validation Helper (NEW - Suggestion #2)
# -------------------------
validate_username <- function(username) {
  # Only allow alphanumeric, underscore, dot, and hyphen
  if (!grepl("^[a-zA-Z0-9_.-]+$", username)) {
    stop("Invalid username format. Only alphanumeric characters, underscore, dot, and hyphen are allowed.")
  }
  
  # Check length constraints
  if (nchar(username) < 3 || nchar(username) > 50) {
    stop("Username must be between 3 and 50 characters.")
  }
  
  return(TRUE)
}

validate_chat_title <- function(title) {
  # Length constraint
  if (nchar(title) > 200) {
    stop("Chat title must be less than 200 characters.")
  }
  
  if (nchar(title) < 1) {
    stop("Chat title cannot be empty.")
  }
  
  # Block potential SQL injection patterns (defense in depth)
  # Even with parameterized queries, we reject suspicious patterns
  dangerous_patterns <- c(
    "';",           # SQL statement terminator
    "--",           # SQL comment
    "/\\*", "\\*/", # SQL block comment
    "xp_", "sp_",   # SQL Server extended/stored procedures
    "\\bEXEC\\b", "\\bEXECUTE\\b",
    "\\bSELECT\\b.*\\bFROM\\b",
    "\\bINSERT\\b.*\\bINTO\\b",
    "\\bUPDATE\\b.*\\bSET\\b",
    "\\bDELETE\\b.*\\bFROM\\b",
    "\\bDROP\\b.*\\bTABLE\\b",
    "\\bCREATE\\b.*\\bTABLE\\b",
    "\\bALTER\\b.*\\bTABLE\\b",
    "\\bUNION\\b.*\\bSELECT\\b"
  )
  
  for (pattern in dangerous_patterns) {
    if (grepl(pattern, title, ignore.case = TRUE)) {
      stop("Chat title contains invalid SQL patterns.")
    }
  }
  
  return(TRUE)
}

validate_message_content <- function(content) {
  # Length constraint (adjusted to 20000)
  if (nchar(content) > 20000) {
    stop("Message content exceeds maximum length of 20,000 characters.")
  }
  
  if (nchar(content) < 1) {
    stop("Message content cannot be empty.")
  }
  
  return(TRUE)
}

# -------------------------
# Database operation helpers
# -------------------------

# Get or create user; returns integer UserID (UPDATED with validation)
get_or_create_user <- function(username) {
  stopifnot(is.character(username) && length(username) == 1)
  
  # ADDED: Input validation (Suggestion #2)
  validate_username(username)
  
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  user_details_query <- "SELECT KaynakAdi FROM DC01_user_base WHERE KullaniciAdi = ?"
  user_details <- dbGetQuery(conn, user_details_query, params = list(username))
  kaynak_adi <- if (nrow(user_details) > 0) user_details$KaynakAdi[1] else username

  user_id_query <- "SELECT UserID FROM MB_Users WHERE KullaniciAdi = ?"
  user_id_result <- dbGetQuery(conn, user_id_query, params = list(username))

  if (nrow(user_id_result) > 0) {
    user_id <- as.integer(user_id_result$UserID[1])
    update_query <- "UPDATE MB_Users SET KaynakAdi = ?, LastLoginDate = GETDATE() WHERE UserID = ?"
    dbExecute(conn, update_query, params = list(kaynak_adi, user_id))
    return(user_id)
  } else {
    insert_query <- "INSERT INTO MB_Users (KullaniciAdi, KaynakAdi, LastLoginDate) OUTPUT INSERTED.UserID AS UserID VALUES (?, ?, GETDATE())"
    res <- dbGetQuery(conn, insert_query, params = list(username, kaynak_adi))
    if (nrow(res) == 0) stop("Failed to retrieve new UserID after insert.")
    return(as.integer(res$UserID[1]))
  }
}

# Load chats and their messages for a user (returns list)
# process_message_content() fallback is provided if missing.
load_chats_from_db <- function(user_id) {
  stopifnot(!is.null(user_id))
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "
    SELECT c.ChatID, c.ChatTitle, c.CreateTimestamp, 
           m.MessageID, m.MessageContent, m.MessageType, m.MessageTimestamp, m.MessageOrder
    FROM MB_Chats c
    JOIN MB_Messages m ON c.ChatID = m.ChatID
    WHERE c.UserID = ? AND c.IsDeleted = 0
    ORDER BY c.CreateTimestamp DESC, m.MessageOrder ASC
  "
  all_data <- dbGetQuery(conn, query, params = list(user_id))
  if (nrow(all_data) == 0) return(list())

  chat_list <- split(all_data, all_data$ChatID)

  formatted_chats <- lapply(chat_list, function(chat_df) {
    messages <- lapply(seq_len(nrow(chat_df)), function(i) {
      row <- chat_df[i, ]
      processed <- if (exists("process_message_content", mode = "function")) {
        process_message_content(row$MessageContent, row$MessageType)
      } else {
        list(html = row$MessageContent, has_code = FALSE)
      }
      
      # Convert timestamp to GMT+3 (Turkey Time)
      timestamp_gmt3 <- row$MessageTimestamp
      attr(timestamp_gmt3, "tzone") <- "Europe/Istanbul"  # This ensures GMT+3 for Turkey
      
      list(
        id = as.character(row$MessageID),
        db_id = as.integer(row$MessageID),
        content = row$MessageContent,
        html_content = processed$html,
        has_code = processed$has_code,
        type = row$MessageType,
        timestamp = format(timestamp_gmt3, "%d.%m.%Y - %H:%M", tz = "Europe/Istanbul")
      )
    })
    list(
      title = chat_df$ChatTitle[1],
      messages = messages,
      timestamp = chat_df$CreateTimestamp[1],
      message_count = length(messages)
    )
  })
  names(formatted_chats) <- names(chat_list)
  return(formatted_chats)
}

# Create new chat, return ChatID integer (UPDATED with validation)
create_new_chat_in_db <- function(user_id, initial_title = "Yeni Söyleşi") {
  stopifnot(!is.null(user_id))
  
  # ADDED: Input validation
  validate_chat_title(initial_title)
  
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "INSERT INTO MB_Chats (UserID, ChatTitle) OUTPUT INSERTED.ChatID AS ChatID VALUES (?, ?)"
  res <- dbGetQuery(conn, query, params = list(user_id, initial_title))
  if (nrow(res) == 0) stop("Failed to create new chat session in DB.")
  return(as.integer(res$ChatID[1]))
}

sanitize_input <- function(text) {
  warning("sanitize_input() is deprecated when using parameterized queries")
  return(text)
}

# Save message (synchronous/main process or worker-safe if get_connection created a worker conn)
# msg is a list: list(content=..., type="user"/"assistant", timestamp=POSIXct or formatted string)
save_message_to_db <- function(chat_id, msg) {
  stopifnot(!is.null(chat_id))
  stopifnot(is.list(msg) && !is.null(msg$content) && !is.null(msg$type))

  # Validate message content
  validate_message_content(msg$content)

  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "
    INSERT INTO MB_Messages (ChatID, MessageContent, MessageType, MessageTimestamp, MessageOrder)
    OUTPUT INSERTED.MessageID AS MessageID
    VALUES (?, ?, ?, ?, ?)
  "
  
  # FIX: Get current time with GMT+3 offset for Turkey
  ts <- if (!is.null(msg$timestamp)) {
    if (inherits(msg$timestamp, "POSIXt")) {
      # Add 3 hours to existing timestamp
      msg$timestamp + 3*60*60
    } else {
      # Parse and add 3 hours
      parsed_time <- as.POSIXct(msg$timestamp, format = "%d.%m.%Y - %H:%M")
      if (is.na(parsed_time)) {
        Sys.time() + 3*60*60
      } else {
        parsed_time + 3*60*60
      }
    }
  } else {
    # Add 3 hours to current system time for GMT+3
    Sys.time() + 3*60*60
  }
  
  if (is.na(ts)) {
    ts <- Sys.time() + 3*60*60
  }

  max_order_query <- "SELECT MAX(MessageOrder) AS maxord FROM MB_Messages WHERE ChatID = ?"
  max_order <- dbGetQuery(conn, max_order_query, params = list(chat_id))$maxord[1]
  next_order <- if (is.na(max_order)) 1L else as.integer(max_order) + 1L

  res <- dbGetQuery(conn, query, params = list(chat_id, msg$content, msg$type, ts, next_order))
  if (nrow(res) == 0) stop("Failed to save message to DB.")
  return(as.integer(res$MessageID[1]))
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
    cat(jsonlite::toJSON(log_entry, auto_unbox = TRUE), 
        "\n", 
        file = log_file, 
        append = TRUE)
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
  
  query <- "UPDATE MB_Messages SET MessageContent = ? WHERE MessageID = ?"
  
  # Execute the update statement
  dbExecute(conn, query, params = list(new_content, as.integer(message_id)))
}

update_chat_title_in_db <- function(chat_id, new_title) {
  stopifnot(!is.null(chat_id))
  
  # ADDED: Input validation
  validate_chat_title(new_title)
  
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "UPDATE MB_Chats SET ChatTitle = ? WHERE ChatID = ?"
  dbExecute(conn, query, params = list(new_title, chat_id))
}

# Feedback functions
save_feedback_to_db <- function(user_id, message_id, feedback_type) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "
    MERGE MB_Feedback AS target
    USING (SELECT ? AS UserID, ? AS MessageID, ? AS FeedbackType) AS source
    ON (target.UserID = source.UserID AND target.MessageID = source.MessageID)
    WHEN MATCHED THEN UPDATE SET FeedbackType = source.FeedbackType
    WHEN NOT MATCHED BY TARGET THEN INSERT (UserID, MessageID, FeedbackType) VALUES (source.UserID, source.MessageID, source.FeedbackType);
  "
  dbExecute(conn, query, params = list(user_id, as.integer(message_id), feedback_type))
}

remove_feedback_from_db <- function(user_id, message_id) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "DELETE FROM MB_Feedback WHERE UserID = ? AND MessageID = ?"
  dbExecute(conn, query, params = list(user_id, as.integer(message_id)))
}

load_feedback_from_db <- function(user_id) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "SELECT MessageID, FeedbackType FROM MB_Feedback WHERE UserID = ?"
  feedback_data <- dbGetQuery(conn, query, params = list(user_id))
  if (nrow(feedback_data) == 0) return(list(liked = character(0), disliked = character(0)))
  list(
    liked = as.character(feedback_data$MessageID[feedback_data$FeedbackType == 'like']),
    disliked = as.character(feedback_data$MessageID[feedback_data$FeedbackType == 'dislike'])
  )
}

# Log usage
log_ai_usage <- function(chat_id, message_id, user_id, model_used, duration, success) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "
    INSERT INTO MB_Usage_Log (ChatID, MessageID, UserID, ModelUsed, ResponseDuration, ResponseSuccess)
    VALUES (?, ?, ?, ?, ?, ?)
  "
  dbExecute(conn, query, params = list(chat_id, message_id, user_id, model_used, duration, success))
}

# Chat deletion
delete_chat_from_db <- function(chat_id, user_id) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "UPDATE MB_Chats SET IsDeleted = 1 WHERE ChatID = ? AND UserID = ?"
  dbExecute(conn, query, params = list(chat_id, user_id))
}

clear_all_chats_from_db <- function(user_id) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

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
  # create fresh worker connection
  conn <- worker_db_connect()
  on.exit({
    tryCatch(DBI::dbDisconnect(conn), error = function(e) NULL)
  })

  # compute next order safely
  max_order_q <- "SELECT MAX(MessageOrder) AS maxord FROM MB_Messages WHERE ChatID = ?"
  max_order <- tryCatch(DBI::dbGetQuery(conn, max_order_q, params = list(chat_id))$maxord[1],
                        error = function(e) NA)
  next_order <- if (is.na(max_order)) 1L else as.integer(max_order) + 1L

  # FIX: Add 3 hours to timestamp for GMT+3
  timestamp_gmt3 <- timestamp + 3*60*60

  insert_q <- "
    INSERT INTO MB_Messages (ChatID, MessageContent, MessageType, MessageTimestamp, MessageOrder)
    OUTPUT INSERTED.MessageID AS MessageID
    VALUES (?, ?, ?, ?, ?)
  "
  res <- DBI::dbGetQuery(conn, insert_q, params = list(chat_id, response_text, message_type, timestamp_gmt3, next_order))
  response_message_id <- if (nrow(res) > 0) as.integer(res$MessageID[1]) else NA_integer_

  if (isTRUE(log_usage)) {
    tryCatch({
      log_q <- "INSERT INTO MB_Usage_Log (ChatID, MessageID, UserID, ModelUsed, ResponseDuration, ResponseSuccess) VALUES (?, ?, ?, ?, ?, ?)"
      DBI::dbExecute(conn, log_q, params = list(chat_id, response_message_id, user_id, model_used, duration, 1))
    }, error = function(e) {
      # ignore logging errors
    })
  }

  return(response_message_id)
}

# End of helpers_database.R

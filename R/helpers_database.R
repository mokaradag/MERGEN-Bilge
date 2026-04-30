# ==============================================================================
# Dosya Yolu: R/helpers_database.R
# Açıklama: MERGEN Bilge sohbet, kullanıcı, mesaj ve kalıcı kayıt veritabanı
#           işlemlerini içerir.
#
# Not:
# - Bağlantı yardımcıları R/helpers_db_connection.R içindedir.
# - Doğrulama yardımcıları R/helpers_db_validation.R içindedir.
# - Worker içinde pool/DBI external pointer taşınmamalıdır.
# ==============================================================================

# -------------------------
# Database operation helpers
# -------------------------

# Kullanıcı al veya oluştur; tam sayı UserID döndürür
# sso_claims: SSO aktifken Keycloak'tan gelen ek bilgiler (opsiyonel)
get_or_create_user <- function(username, sso_claims = NULL) {
  stopifnot(is.character(username) && length(username) == 1)

  # Girdi doğrulama
  validate_username(username)

  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  # KaynakAdi'nı belirle: önce SSO claim, sonra DC01_user_base, en son username
  kaynak_adi <- username
  if (!is.null(sso_claims$full_name) && nzchar(sso_claims$full_name)) {
    kaynak_adi <- sso_claims$full_name
  } else {
    user_details_query <- "SELECT KaynakAdi FROM DC01_user_base WHERE KullaniciAdi = ?"
    user_details <- dbGetQuery(conn, user_details_query, params = normalize_db_params(list(username)))
    if (nrow(user_details) > 0 && nzchar(user_details$KaynakAdi[1] %||% "")) {
      kaynak_adi <- user_details$KaynakAdi[1]
    }
  }

  user_id_query <- "SELECT UserID FROM MB_Users WHERE KullaniciAdi = ?"
  user_id_result <- dbGetQuery(conn, user_id_query, params = normalize_db_params(list(username)))

  if (nrow(user_id_result) > 0) {
    user_id <- as.integer(user_id_result$UserID[1])
    update_query <- "UPDATE MB_Users SET KaynakAdi = ?, LastLoginDate = GETDATE() WHERE UserID = ?"
    dbExecute(conn, update_query, params = normalize_db_params(list(kaynak_adi, user_id)))

    # SSO ek alanlarını güncelle (tablo destekliyorsa)
    if (!is.null(sso_claims)) {
      update_sso_fields(conn, user_id, sso_claims)
    }

    return(user_id)
  } else {
    insert_query <- "INSERT INTO MB_Users (KullaniciAdi, KaynakAdi, LastLoginDate) OUTPUT INSERTED.UserID AS UserID VALUES (?, ?, GETDATE())"
    res <- dbGetQuery(conn, insert_query, params = normalize_db_params(list(username, kaynak_adi)))
    if (nrow(res) == 0) stop("Yeni kullanıcı oluşturulduktan sonra UserID alınamadı.")
    user_id <- as.integer(res$UserID[1])

    # SSO ek alanlarını kaydet
    if (!is.null(sso_claims)) {
      update_sso_fields(conn, user_id, sso_claims)
    }

    return(user_id)
  }
}

# SSO ek alanlarını MB_Users tablosunda güncelle
# Tablo bu sütunlara sahip değilse sessizce atla
update_sso_fields <- function(conn, user_id, sso_claims) {
  tryCatch({
    # Tabloda SSO sütunlarının varlığını kontrol et
    cols_query <- "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'MB_Users' AND COLUMN_NAME IN ('Sicil', 'Email', 'Sektor', 'Departman', 'Mudurluk', 'MasrafYeriKodu', 'SonGirisKaynagi')"
    existing_cols <- dbGetQuery(conn, cols_query)$COLUMN_NAME

    if (length(existing_cols) == 0) {
      # SSO sütunları henüz eklenmemiş - sessizce atla
      return(invisible(NULL))
    }

    # Mevcut sütunlara göre dinamik UPDATE oluştur
    set_parts <- c()
    params <- list()

    if ("Sicil" %in% existing_cols && !is.null(sso_claims$sicil)) {
      set_parts <- c(set_parts, "Sicil = ?")
      params <- c(params, list(sso_claims$sicil))
    }
    if ("Email" %in% existing_cols && !is.null(sso_claims$email)) {
      set_parts <- c(set_parts, "Email = ?")
      params <- c(params, list(sso_claims$email))
    }
    if ("Sektor" %in% existing_cols && !is.null(sso_claims$sektor)) {
      set_parts <- c(set_parts, "Sektor = ?")
      params <- c(params, list(sso_claims$sektor))
    }
    if ("Departman" %in% existing_cols && !is.null(sso_claims$department)) {
      set_parts <- c(set_parts, "Departman = ?")
      params <- c(params, list(sso_claims$department))
    }
    if ("Mudurluk" %in% existing_cols && !is.null(sso_claims$mudurluk)) {
      set_parts <- c(set_parts, "Mudurluk = ?")
      params <- c(params, list(sso_claims$mudurluk))
    }
    if ("MasrafYeriKodu" %in% existing_cols && !is.null(sso_claims$masraf_yeri_kodu)) {
      set_parts <- c(set_parts, "MasrafYeriKodu = ?")
      params <- c(params, list(sso_claims$masraf_yeri_kodu))
    }
    if ("SonGirisKaynagi" %in% existing_cols) {
      set_parts <- c(set_parts, "SonGirisKaynagi = ?")
      params <- c(params, list("keycloak"))
    }

    if (length(set_parts) > 0) {
      query <- paste0("UPDATE MB_Users SET ", paste(set_parts, collapse = ", "), " WHERE UserID = ?")
      params <- c(params, list(user_id))
      dbExecute(conn, query, params = normalize_db_params(params))
    }
  }, error = function(e) {
    # SSO alanları güncellenemedi - kritik değil, sessizce devam et
    log_warn("SSO alanları güncellenemedi (UserID={user_id}): {e$message}")
  })
  invisible(NULL)
}

# Sohbet listeleme, mesaj hidratasyonu ve geçmiş okuma yardımcıları
# R/helpers_db_chat_readers.R içine taşındı.

# Create new chat, return ChatID integer (UPDATED with validation)
create_new_chat_in_db <- function(user_id, initial_title = "Yeni Söyleşi") {
  stopifnot(!is.null(user_id))
  
  # ADDED: Input validation
  validate_chat_title(initial_title)
  
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

  reasoning_text <- tryCatch(
    enc2utf8(as.character(reasoning_content %||% "")[1]),
    error = function(e) ""
  )

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
      params = normalize_db_params(list(reasoning_text, message_id))
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

  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  # Düşünen modeller için biriken akıl yürütme metni, ReasoningContent
  # sütununda saklanır. Sütun yoksa (eski şema) sessizce yalnızca eski
  # alanlar yazılır; böylece geriye dönük uyumluluk korunur.
  reasoning_content <- msg$reasoning_content %||% msg$reasoning_trace
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
  on.exit({
    if (!committed) {
      try(DBI::dbRollback(conn), silent = TRUE)
    }
  }, add = TRUE)

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
      params = normalize_db_params(list(
        chat_id, msg$content, msg$type, ts, next_order, reasoning_content
      ))
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
      params = normalize_db_params(list(
        chat_id, msg$content, msg$type, ts, next_order
      ))
    )
  })

  if (nrow(res) == 0) stop("Failed to save message to DB.")

  DBI::dbCommit(conn)
  committed <- TRUE

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
  dbExecute(conn, query, params = normalize_db_params(list(new_content, as.integer(message_id))))
}

update_chat_title_in_db <- function(chat_id, new_title) {
  stopifnot(!is.null(chat_id))
  
  # ADDED: Input validation
  validate_chat_title(new_title)
  
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "UPDATE MB_Chats SET ChatTitle = ? WHERE ChatID = ?"
  dbExecute(conn, query, params = normalize_db_params(list(new_title, chat_id)))
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
  dbExecute(conn, query, params = normalize_db_params(list(user_id, as.integer(message_id), feedback_type)))
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
  dbExecute(conn, query, params = normalize_db_params(list(chat_id, message_id, user_id, model_used, duration, success)))
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
    params = normalize_db_params(list(
      chat_id, response_text, message_type, timestamp_gmt3, next_order
    ))
  )

  response_message_id <- if (nrow(res) > 0) as.integer(res$MessageID[1]) else NA_integer_

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

# Genişletilmiş geri bildirim kaydetme
save_feedback_to_db_extended <- function(user_id, message_id, feedback_type, tags = NULL, comment = NULL) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  # NULL degerleri SQL NULL (NA) olarak isle
  safe_tags <- if (is.null(tags) || length(tags) == 0) NA_character_ else as.character(tags)
  safe_comment <- if (is.null(comment) || length(comment) == 0) NA_character_ else as.character(comment)

  query <- "
    MERGE MB_Feedback AS target
    USING (SELECT ? AS UserID, ? AS MessageID, ? AS FeedbackType, ? AS FeedbackTags, ? AS FeedbackComment) AS source
    ON (target.UserID = source.UserID AND target.MessageID = source.MessageID)
	WHEN MATCHED THEN 
      UPDATE SET 
        FeedbackType = source.FeedbackType,
        FeedbackTags = source.FeedbackTags,
        FeedbackComment = source.FeedbackComment,
        FeedbackTimestamp = CAST(GETDATE() AS datetime2(0))
    WHEN NOT MATCHED BY TARGET THEN 
      INSERT (UserID, MessageID, FeedbackType, FeedbackTags, FeedbackComment, FeedbackTimestamp) 
      VALUES (source.UserID, source.MessageID, source.FeedbackType, source.FeedbackTags, source.FeedbackComment, CAST(GETDATE() AS datetime2(0)));
  "
  
  dbExecute(conn, query, params = normalize_db_params(list(
    user_id, 
    as.integer(message_id), 
    feedback_type,
    safe_tags,
    safe_comment
  )))
}

# Geri bildirim detaylarını yükleme
load_feedback_details_from_db <- function(user_id, message_id) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "SELECT FeedbackType, FeedbackTags, FeedbackComment, FeedbackTimestamp FROM MB_Feedback WHERE UserID = ? AND MessageID = ?"
  result <- dbGetQuery(conn, query, params = list(user_id, as.integer(message_id)))
  
  if (nrow(result) == 0) return(NULL)
  as.list(result[1, ])
}
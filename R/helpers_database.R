# ==============================================================================
# Dosya Yolu: R/helpers_database.R
# Açıklama: MERGEN Bilge kullanıcı, geri bildirim, kullanım logu ve kalıcı kayıt
#           veritabanı işlemlerini içerir.
#
# Not:
# - Bağlantı yardımcıları R/helpers_db_connection.R içindedir.
# - SSO/MB_Users kodlama ayrımı R/helpers_db_user_encoding.R içindedir.
# - Doğrulama yardımcıları R/helpers_db_validation.R içindedir.
# - Sohbet okuma yardımcıları R/helpers_db_chat_readers.R içindedir.
# - Sohbet/mesaj yazma yardımcıları R/helpers_db_chat_mutations.R içindedir.
# - Worker içinde pool/DBI external pointer taşınmamalıdır.
# ==============================================================================

# -------------------------
# Database operation helpers
# -------------------------

get_or_create_user <- function(username, sso_claims = NULL) {
  stopifnot(is.character(username) && length(username) == 1)
  validate_username(username)

  username <- normalize_db_technical_value(username)
  sso_claims <- normalize_sso_claims_for_db(sso_claims)

  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  kaynak_adi <- username

  if (!is.null(sso_claims$full_name) && nzchar(sso_claims$full_name)) {
    kaynak_adi <- sso_claims$full_name
  } else {
    user_details <- dbGetQuery(
      conn,
      "SELECT KaynakAdi FROM DC01_user_base WHERE KullaniciAdi = ?",
      params = normalize_db_params(list(username))
    )

    if (exists("normalize_text_frame_utf8", mode = "function", inherits = TRUE)) {
      user_details <- normalize_text_frame_utf8(user_details, repair_mojibake = TRUE)
    }

    if (nrow(user_details) > 0 && nzchar(user_details$KaynakAdi[1] %||% "")) {
      kaynak_adi <- user_details$KaynakAdi[1]
    }
  }

  kaynak_adi <- normalize_db_visible_value(kaynak_adi)

  user_id_result <- dbGetQuery(
    conn,
    "SELECT UserID FROM MB_Users WHERE KullaniciAdi = ?",
    params = normalize_db_params(list(username))
  )

  if (nrow(user_id_result) > 0) {
    user_id <- as.integer(user_id_result$UserID[1])

    dbExecute(
      conn,
      "UPDATE MB_Users SET KaynakAdi = ?, LastLoginDate = GETDATE() WHERE UserID = ?",
      params = normalize_db_params(list(kaynak_adi, user_id))
    )

    if (!is.null(sso_claims)) update_sso_fields(conn, user_id, sso_claims)
    return(user_id)
  }

  res <- dbGetQuery(
    conn,
    paste(
      "INSERT INTO MB_Users (KullaniciAdi, KaynakAdi, LastLoginDate)",
      "OUTPUT INSERTED.UserID AS UserID",
      "VALUES (?, ?, GETDATE())"
    ),
    params = normalize_db_params(list(username, kaynak_adi))
  )

  if (nrow(res) == 0) {
    stop("Yeni kullanıcı oluşturulduktan sonra UserID alınamadı.")
  }

  user_id <- as.integer(res$UserID[1])
  if (!is.null(sso_claims)) update_sso_fields(conn, user_id, sso_claims)
  user_id
}

get_user_profile_from_db <- function(user_id = NULL, username = NULL) {
  uid <- suppressWarnings(as.integer(user_id %||% NA_integer_))
  uname <- normalize_db_technical_value(username %||% "")

  if ((is.na(uid) || uid <= 0L) && !nzchar(uname)) {
    return(NULL)
  }

  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info), add = TRUE)

  if (!is.na(uid) && uid > 0L) {
    where_clause <- "WHERE UserID = ?"
    params <- list(uid)
  } else {
    where_clause <- "WHERE LOWER(KullaniciAdi) = LOWER(?)"
    params <- list(uname)
  }

  result <- dbGetQuery(
    conn,
    paste(
      "SELECT TOP (1)",
      "UserID, KullaniciAdi, KaynakAdi, LastLoginDate,",
      "Sicil, Email, Sektor, Departman, Mudurluk,",
      "MasrafYeriKodu, SonGirisKaynagi",
      "FROM MB_Users",
      where_clause
    ),
    params = normalize_db_params(params)
  )

  if (exists("normalize_text_frame_utf8", mode = "function", inherits = TRUE)) {
    result <- normalize_text_frame_utf8(result, repair_mojibake = TRUE)
  }

  if (nrow(result) == 0L) {
    return(NULL)
  }

  row <- as.list(result[1, , drop = FALSE])

  visible_fields <- intersect(
    c("KaynakAdi", "Sektor", "Departman", "Mudurluk"),
    names(row)
  )

  for (field_name in visible_fields) {
    row[[field_name]] <- normalize_db_visible_value(row[[field_name]])
  }

  technical_fields <- intersect(
    c("KullaniciAdi", "Sicil", "Email", "MasrafYeriKodu", "SonGirisKaynagi"),
    names(row)
  )

  for (field_name in technical_fields) {
    row[[field_name]] <- normalize_db_technical_value(row[[field_name]])
  }

  row$user_id <- suppressWarnings(as.integer(row$UserID %||% uid))
  row
}

# Sohbet listeleme, mesaj hidratasyonu ve geçmiş okuma yardımcıları
# R/helpers_db_chat_readers.R içine taşındı.

# Sohbet ve mesaj yazma/mutasyon yardımcıları
# R/helpers_db_chat_mutations.R içine taşındı.

save_feedback_to_db <- function(user_id, message_id, feedback_type) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  feedback_type <- normalize_db_technical_value(feedback_type)

  query <- "
    MERGE MB_Feedback AS target
    USING (SELECT ? AS UserID, ? AS MessageID, ? AS FeedbackType) AS source
    ON (target.UserID = source.UserID AND target.MessageID = source.MessageID)
    WHEN MATCHED THEN UPDATE SET FeedbackType = source.FeedbackType
    WHEN NOT MATCHED BY TARGET THEN
      INSERT (UserID, MessageID, FeedbackType)
      VALUES (source.UserID, source.MessageID, source.FeedbackType);
  "

  dbExecute(
    conn,
    query,
    params = normalize_db_params(
      list(user_id, as.integer(message_id), feedback_type)
    )
  )
}

remove_feedback_from_db <- function(user_id, message_id) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  dbExecute(
    conn,
    "DELETE FROM MB_Feedback WHERE UserID = ? AND MessageID = ?",
    params = list(user_id, as.integer(message_id))
  )
}

load_feedback_from_db <- function(user_id) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  feedback_data <- dbGetQuery(
    conn,
    "SELECT MessageID, FeedbackType FROM MB_Feedback WHERE UserID = ?",
    params = list(user_id)
  )

  if (exists("normalize_text_frame_utf8", mode = "function", inherits = TRUE)) {
    feedback_data <- normalize_text_frame_utf8(feedback_data, repair_mojibake = TRUE)
  }

  if (nrow(feedback_data) == 0) {
    return(list(liked = character(0), disliked = character(0)))
  }

  list(
    liked = as.character(feedback_data$MessageID[feedback_data$FeedbackType == "like"]),
    disliked = as.character(feedback_data$MessageID[feedback_data$FeedbackType == "dislike"])
  )
}

log_ai_usage <- function(chat_id, message_id, user_id, model_used, duration, success) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  model_used <- normalize_db_technical_value(model_used)

  dbExecute(
    conn,
    paste(
      "INSERT INTO MB_Usage_Log",
      "(ChatID, MessageID, UserID, ModelUsed, ResponseDuration, ResponseSuccess)",
      "VALUES (?, ?, ?, ?, ?, ?)"
    ),
    params = normalize_db_params(
      list(chat_id, message_id, user_id, model_used, duration, success)
    )
  )
}

# Sohbet silme ve worker-safe mesaj yazma yardımcıları
# R/helpers_db_chat_mutations.R içine taşındı.

save_feedback_to_db_extended <- function(user_id,
                                         message_id,
                                         feedback_type,
                                         tags = NULL,
                                         comment = NULL) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  safe_tags <- if (is.null(tags) || length(tags) == 0) NA_character_ else as.character(tags)
  safe_comment <- if (is.null(comment) || length(comment) == 0) NA_character_ else as.character(comment)

  safe_tags <- normalize_db_visible_value(safe_tags)
  safe_comment <- normalize_db_visible_value(safe_comment)
  feedback_type <- normalize_db_technical_value(feedback_type)

  query <- "
    MERGE MB_Feedback AS target
    USING (
      SELECT
        ? AS UserID,
        ? AS MessageID,
        ? AS FeedbackType,
        ? AS FeedbackTags,
        ? AS FeedbackComment
    ) AS source
    ON (target.UserID = source.UserID AND target.MessageID = source.MessageID)
    WHEN MATCHED THEN
      UPDATE SET
        FeedbackType = source.FeedbackType,
        FeedbackTags = source.FeedbackTags,
        FeedbackComment = source.FeedbackComment,
        FeedbackTimestamp = CAST(GETDATE() AS datetime2(0))
    WHEN NOT MATCHED BY TARGET THEN
      INSERT (
        UserID,
        MessageID,
        FeedbackType,
        FeedbackTags,
        FeedbackComment,
        FeedbackTimestamp
      )
      VALUES (
        source.UserID,
        source.MessageID,
        source.FeedbackType,
        source.FeedbackTags,
        source.FeedbackComment,
        CAST(GETDATE() AS datetime2(0))
      );
  "

  dbExecute(
    conn,
    query,
    params = normalize_db_params(
      list(
        user_id,
        as.integer(message_id),
        feedback_type,
        safe_tags,
        safe_comment
      )
    )
  )
}

load_feedback_details_from_db <- function(user_id, message_id) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  result <- dbGetQuery(
    conn,
    paste(
      "SELECT FeedbackType, FeedbackTags, FeedbackComment, FeedbackTimestamp",
      "FROM MB_Feedback",
      "WHERE UserID = ? AND MessageID = ?"
    ),
    params = list(user_id, as.integer(message_id))
  )

  if (exists("normalize_text_frame_utf8", mode = "function", inherits = TRUE)) {
    result <- normalize_text_frame_utf8(result, repair_mojibake = TRUE)
  }

  if (nrow(result) == 0) return(NULL)
  as.list(result[1, ])
}
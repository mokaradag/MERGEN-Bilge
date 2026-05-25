# ==============================================================================
# Dosya Yolu: R/helpers_db_feedback.R
# Açıklama: MERGEN Bilge geri bildirim ve AI kullanım logu veritabanı
#           işlemlerini içerir.
#
# Not:
# - Bağlantı yardımcıları R/helpers_db_connection.R içindedir.
# - Kodlama/parametre normalizasyonu R/helpers_db_user_encoding.R ve
#   R/helpers_db_encoding.R üzerinden sağlanır.
# - Bu dosya R/helpers_database.R dosyasından ayrılmıştır; fonksiyon adları
#   geriye uyumluluk için aynen korunmuştur.
# ==============================================================================

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
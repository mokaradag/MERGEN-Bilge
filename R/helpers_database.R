# ==============================================================================
# Dosya Yolu: R/helpers_database.R
# Açıklama: MERGEN Bilge kullanıcı, geri bildirim, kullanım logu ve kalıcı kayıt
#           veritabanı işlemlerini içerir.
#
# Not:
# - Bağlantı yardımcıları R/helpers_db_connection.R içindedir.
# - Doğrulama yardımcıları R/helpers_db_validation.R içindedir.
# - Sohbet okuma yardımcıları R/helpers_db_chat_readers.R içindedir.
# - Sohbet/mesaj yazma yardımcıları R/helpers_db_chat_mutations.R içindedir.
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

  if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
    username <- normalize_text_utf8(username, repair_mojibake = TRUE)
  }

  if (!is.null(sso_claims) &&
      exists("normalize_text_tree_utf8", mode = "function", inherits = TRUE)) {
    sso_claims <- normalize_text_tree_utf8(sso_claims, repair_mojibake = TRUE)
  }

  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  # KaynakAdi'nı belirle: önce SSO claim, sonra DC01_user_base, en son username
  kaynak_adi <- username
  if (!is.null(sso_claims$full_name) && nzchar(sso_claims$full_name)) {
    kaynak_adi <- sso_claims$full_name
  } else {
    user_details_query <- "SELECT KaynakAdi FROM DC01_user_base WHERE KullaniciAdi = ?"
    user_details <- dbGetQuery(
      conn,
      user_details_query,
      params = normalize_db_params(list(username), repair_mojibake = TRUE)
    )

    if (exists("normalize_text_frame_utf8", mode = "function", inherits = TRUE)) {
      user_details <- normalize_text_frame_utf8(user_details, repair_mojibake = TRUE)
    }

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
  if (!is.null(sso_claims) &&
      exists("normalize_text_tree_utf8", mode = "function", inherits = TRUE)) {
    sso_claims <- normalize_text_tree_utf8(sso_claims, repair_mojibake = TRUE)
  }

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

# Sohbet ve mesaj yazma/mutasyon yardımcıları
# R/helpers_db_chat_mutations.R içine taşındı.

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

# Sohbet silme ve worker-safe mesaj yazma yardımcıları
# R/helpers_db_chat_mutations.R içine taşındı.

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
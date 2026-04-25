# ==============================================================================
# Dosya Yolu: R/helpers_db_validation.R
# Açıklama: Veritabanına yazılmadan önce kullanılan kullanıcı adı, sohbet başlığı
#           ve mesaj içeriği doğrulama yardımcılarını içerir.
# ==============================================================================

validate_username <- function(username) {
  if (is.null(username) || length(username) != 1L || is.na(username) || !nzchar(username)) {
    stop("Kullanıcı adı boş olamaz.", call. = FALSE)
  }

  if (!grepl("^[a-zA-Z0-9_.-]+$", username)) {
    stop(
      "Geçersiz kullanıcı adı formatı. Sadece harf, rakam, alt çizgi, nokta ve tire kullanılabilir.",
      call. = FALSE
    )
  }

  if (nchar(username) < 3 || nchar(username) > 50) {
    stop("Kullanıcı adı 3-50 karakter arasında olmalıdır.", call. = FALSE)
  }

  TRUE
}

validate_chat_title <- function(title) {
  if (is.null(title) || length(title) != 1L || is.na(title)) {
    stop("Chat title cannot be empty.", call. = FALSE)
  }

  title <- as.character(title)

  if (nchar(title) > 200) {
    stop("Chat title must be less than 200 characters.", call. = FALSE)
  }

  if (nchar(title) < 1) {
    stop("Chat title cannot be empty.", call. = FALSE)
  }

  dangerous_patterns <- c(
    "';",
    "--",
    "/\\*", "\\*/",
    "xp_", "sp_",
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
    if (grepl(pattern, title, ignore.case = TRUE, perl = TRUE)) {
      stop("Chat title contains invalid SQL patterns.", call. = FALSE)
    }
  }

  TRUE
}

validate_message_content <- function(content) {
  if (is.null(content) || length(content) != 1L || is.na(content)) {
    stop("Message content cannot be empty.", call. = FALSE)
  }

  content <- as.character(content)

  if (nchar(content) > 20000) {
    stop("Message content exceeds maximum length of 20,000 characters.", call. = FALSE)
  }

  if (nchar(content) < 1) {
    stop("Message content cannot be empty.", call. = FALSE)
  }

  TRUE
}
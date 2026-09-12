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

# MessageContent NVARCHAR(MAX)'tır; bu yalnızca kaçak içeriğe karşı güvenlik
# tavanıdır. Eski 20.000 sınırı uzun kod içeren yanıtların kaydını engelliyordu.
mergen_max_message_chars <- function() {
  raw_val <- Sys.getenv("MERGEN_MAX_MESSAGE_CHARS", "")
  parsed <- suppressWarnings(as.numeric(raw_val))
  if (length(parsed) != 1L ||
      is.na(parsed) ||
      !is.finite(parsed) ||
      parsed < 1000 ||
      parsed > .Machine$integer.max) {
    return(1000000L)
  }
  as.integer(parsed)
}

validate_message_content <- function(content) {
  if (is.null(content) || length(content) != 1L || is.na(content)) {
    stop("Message content cannot be empty.", call. = FALSE)
  }

  content <- as.character(content)

  max_chars <- mergen_max_message_chars()
  # Geçersiz çok baytlı içerikte nchar() hata fırlatmasın: bayt uzunluğuna düşülür.
  n_chars <- suppressWarnings(nchar(content, type = "chars", allowNA = TRUE))
  if (is.na(n_chars)) {
    n_chars <- nchar(content, type = "bytes")
  }
  if (n_chars > max_chars) {
    stop(
      sprintf("Message content exceeds maximum length of %d characters.", max_chars),
      call. = FALSE
    )
  }

  if (n_chars < 1) {
    stop("Message content cannot be empty.", call. = FALSE)
  }

  TRUE
}
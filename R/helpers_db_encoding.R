# ==============================================================================
# Dosya Yolu: R/helpers_db_encoding.R
# Açıklama: DB istemci kodlaması, kullanıcıya görünen DB metni normalizasyonu
#           ve MB_Messages yazım sonrası kodlama koruma yardımcıları.
# ==============================================================================

resolve_db_client_encoding <- function() {
  # DB istemci kodlaması üretim VM üzerinde .Renviron ile yönetilir.
  # Ortam değişkeni yoksa test/local varsayılanı korunur.
  env_encoding <- Sys.getenv("DB_CLIENT_ENCODING", unset = NA_character_)

  if (!is.na(env_encoding) && nzchar(trimws(env_encoding))) {
    return(trimws(as.character(env_encoding)[1]))
  }

  option_encoding <- getOption("mergen.db.client_encoding", "UTF-8")
  option_encoding <- as.character(option_encoding)[1]

  if (is.na(option_encoding) || !nzchar(trimws(option_encoding))) {
    return("UTF-8")
  }

  trimws(option_encoding)
}

resolve_db_name_encoding <- function(client_encoding = resolve_db_client_encoding()) {
  # Sütun/tablo adı kodlaması ayrı verilmemişse istemci kodlamasıyla aynı tutulur.
  env_encoding <- Sys.getenv("DB_NAME_ENCODING", unset = NA_character_)

  if (!is.na(env_encoding) && nzchar(trimws(env_encoding))) {
    return(trimws(as.character(env_encoding)[1]))
  }

  option_encoding <- getOption("mergen.db.name_encoding", client_encoding)
  option_encoding <- as.character(option_encoding)[1]

  if (is.na(option_encoding) || !nzchar(trimws(option_encoding))) {
    return(client_encoding)
  }

  trimws(option_encoding)
}

db_client_encoding_is_utf8 <- function(encoding_name) {
  encoding_name <- toupper(gsub("[_-]", "", as.character(encoding_name %||% "")[1]))
  identical(encoding_name, "UTF8")
}

.DEFAULT_DB_CLIENT_ENCODING <- resolve_db_client_encoding()
.DEFAULT_DB_NAME_ENCODING <- resolve_db_name_encoding(.DEFAULT_DB_CLIENT_ENCODING)

normalize_db_value <- function(x, repair_mojibake = FALSE) {
  # DBI parametreleri çoğunlukla skaler gelir; yine de bu yardımcı vektör,
  # NA ve boş karakter girdilerinde uyarı üretmemelidir. Strict test runner
  # stop_on_warning = TRUE kullandığı için burada warning-free davranış kritiktir.
  if (is.null(x) || !is.character(x)) {
    return(x)
  }

  if (length(x) == 0L) {
    return(x)
  }

  repair_mojibake <- isTRUE(repair_mojibake)

  out_utf8 <- if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
    normalize_text_utf8(x, repair_mojibake = repair_mojibake)
  } else {
    tryCatch(
      enc2utf8(x),
      error = function(e) x
    )
  }

  out_utf8[is.na(x)] <- NA_character_

  client_encoding <- resolve_db_client_encoding()
  client_is_utf8 <- db_client_encoding_is_utf8(client_encoding)

  if (isTRUE(client_is_utf8) && isTRUE(l10n_info()[["UTF-8"]])) {
    return(out_utf8)
  }

  if (!isTRUE(client_is_utf8)) {
    out_client <- tryCatch(
      iconv(out_utf8, from = "UTF-8", to = client_encoding, sub = NA_character_),
      error = function(e) rep(NA_character_, length(out_utf8))
    )

    failed <- is.na(out_client) & !is.na(out_utf8)

    # WINDOWS-1254 Türkçe karakterleri temsil eder; ancak bazı Unicode sembolleri
    # temsil edemez. Böyle bir karakter tüm string için iconv sonucunu NA yaparsa,
    # ham UTF-8'e düşmek yerine temsil edilemeyen karakterleri DB sınırında çıkarırız.
    # Bu, MB_Messages yazımında Türkçe metnin mojibake olmasını engeller.
    if (any(failed)) {
      stripped_values <- tryCatch(
        iconv(out_utf8[failed], from = "UTF-8", to = client_encoding, sub = ""),
        error = function(e) rep("", sum(failed))
      )

      stripped_values[is.na(stripped_values)] <- ""
      out_client[failed] <- stripped_values
    }

    if (any(!is.na(out_client))) {
      Encoding(out_client[!is.na(out_client)]) <- "unknown"
    }

    out_client[is.na(x)] <- NA_character_
    return(out_client)
  }

  out_native <- tryCatch(
    enc2native(out_utf8),
    error = function(e) out_utf8
  )

  out_native[is.na(x)] <- NA_character_

  roundtrip_utf8 <- tryCatch(
    enc2utf8(out_native),
    error = function(e) out_utf8
  )
  roundtrip_utf8[is.na(x)] <- NA_character_

  if (!identical(unname(roundtrip_utf8), unname(out_utf8))) {
    return(out_utf8)
  }

  out_native
}

normalize_db_visible_value <- function(x) {
  # Kullanıcıya görünen metinler DB parametre sınırına gelmeden onarılır.
  # Teknik kimlik, enum, bayrak ve yol alanları bu yardımcıdan geçirilmemelidir.
  if (is.null(x) || !is.character(x)) {
    return(x)
  }

  if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
    return(normalize_text_utf8(x, repair_mojibake = TRUE))
  }

  enc2utf8(x)
}

normalize_db_technical_value <- function(x) {
  # Teknik karakter alanları UTF-8 olarak işaretlenir; mojibake onarımı yapılmaz.
  if (is.null(x) || !is.character(x)) {
    return(x)
  }

  if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
    return(normalize_text_utf8(x, repair_mojibake = FALSE))
  }

  enc2utf8(x)
}

db_visible_text_has_mojibake <- function(value) {
  if (is.null(value) || length(value) == 0L) {
    return(FALSE)
  }

  text <- paste(enc2utf8(as.character(value)), collapse = "\n")

  if (!nzchar(text)) {
    return(FALSE)
  }

  mojibake_tokens <- c(
    "\u00C3\u00A7",
    "\u00C3\u00B6",
    "\u00C3\u00BC",
    "\u00C4\u00B1",
    "\u00C4\u00B0",
    "\u00C4\u0178",
    "\u00C5\u0178",
    "\u00C3\u2021",
    "\u00C3\u2013",
    "\u00C3\u0153",
    "\u00C4\u017E",
    "\u00C5\u017E",
    "T\u00C3\u00BCrkiye",
    "Nas\u00C4\u00B1l",
    "yard\u00C4\u00B1mc\u00C4\u00B1",
    "ba\u00C5\u0178kent",
    "te\u00C5\u0178ekk\u00C3\u00BCr"
  )

  any(vapply(
    mojibake_tokens,
    function(token) grepl(token, text, fixed = TRUE),
    logical(1)
  ))
}

assert_mb_message_visible_encoding_clean <- function(conn, message_id) {
  if (is.null(conn) || is.null(message_id) || is.na(message_id)) {
    return(invisible(TRUE))
  }

  has_reasoning_content <- tryCatch({
    cols <- DBI::dbGetQuery(
      conn,
      "
        SELECT COLUMN_NAME
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'MB_Messages'
          AND COLUMN_NAME = 'ReasoningContent'
      "
    )
    nrow(cols) > 0L
  }, error = function(e) {
    FALSE
  })

  query <- if (isTRUE(has_reasoning_content)) {
    "
      SELECT MessageContent, ReasoningContent
      FROM MB_Messages
      WHERE MessageID = ?
    "
  } else {
    "
      SELECT
        MessageContent,
        CAST(NULL AS NVARCHAR(MAX)) AS ReasoningContent
      FROM MB_Messages
      WHERE MessageID = ?
    "
  }

  row <- DBI::dbGetQuery(
    conn,
    query,
    params = normalize_db_params(list(as.integer(message_id)))
  )

  if (nrow(row) == 0L) {
    return(invisible(TRUE))
  }

  if (db_visible_text_has_mojibake(row$MessageContent) ||
      db_visible_text_has_mojibake(row$ReasoningContent)) {
    stop(
      sprintf(
        "MB_Messages encoding guard failed after insert. MessageID=%s. Transaction will be rolled back.",
        as.character(message_id)
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

normalize_db_params <- function(params, repair_mojibake = FALSE) {
  lapply(params, normalize_db_value, repair_mojibake = repair_mojibake)
}
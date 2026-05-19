# ==============================================================================
# Dosya Yolu: R/helpers_db_unicode_escape.R
# Açıklama: DB istemci kodlamasında temsil edilemeyen Unicode karakterleri
#           ASCII kaçış belirteçlerine dönüştürür ve UI okuma sınırında geri açar.
# ==============================================================================

db_unicode_escape_token <- function(codepoint) {
  sprintf("[[MERGEN-U+%X]]", as.integer(codepoint))
}

db_unicode_codepoint_supported_by_encoding <- function(codepoint, encoding_name) {
  if (is.na(codepoint)) {
    return(FALSE)
  }

  char_value <- tryCatch(
    intToUtf8(as.integer(codepoint)),
    error = function(e) NA_character_
  )

  if (is.na(char_value) || !nzchar(char_value)) {
    return(FALSE)
  }

  converted <- tryCatch(
    iconv(char_value, from = "UTF-8", to = encoding_name, sub = NA_character_),
    error = function(e) NA_character_
  )

  !is.na(converted)
}

db_unicode_escape_scalar_for_encoding <- function(value, encoding_name) {
  if (is.na(value) || !nzchar(value)) {
    return(value)
  }

  value_utf8 <- enc2utf8(as.character(value)[1])

  codepoints <- tryCatch(
    utf8ToInt(value_utf8),
    error = function(e) integer(0)
  )

  if (!length(codepoints)) {
    return(value_utf8)
  }

  paste0(vapply(codepoints, function(codepoint) {
    if (db_unicode_codepoint_supported_by_encoding(codepoint, encoding_name)) {
      return(intToUtf8(as.integer(codepoint)))
    }

    db_unicode_escape_token(codepoint)
  }, character(1), USE.NAMES = FALSE), collapse = "")
}

db_unicode_escape_for_client_encoding <- function(x, encoding_name) {
  if (is.null(x) || !is.character(x)) {
    return(x)
  }

  if (!length(x)) {
    return(x)
  }

  encoding_name <- as.character(encoding_name %||% "")[1]

  if (!nzchar(encoding_name)) {
    return(x)
  }

  if (exists("db_client_encoding_is_utf8", mode = "function", inherits = TRUE) &&
      isTRUE(db_client_encoding_is_utf8(encoding_name))) {
    return(x)
  }

  out <- vapply(x, function(value) {
    if (is.na(value)) {
      return(NA_character_)
    }

    db_unicode_escape_scalar_for_encoding(value, encoding_name)
  }, character(1), USE.NAMES = FALSE)

  out[is.na(x)] <- NA_character_
  out
}

db_unicode_restore_escapes <- function(x) {
  if (is.null(x) || !is.character(x)) {
    return(x)
  }

  if (!length(x)) {
    return(x)
  }

  pattern <- "\\[\\[MERGEN-U\\+([0-9A-Fa-f]{2,8})\\]\\]"

  vapply(x, function(value) {
    if (is.na(value) || !nzchar(value)) {
      return(value)
    }

    current <- enc2utf8(as.character(value)[1])
    matches <- gregexpr(pattern, current, perl = TRUE)[[1]]

    if (length(matches) == 1L && matches[1] < 0L) {
      return(current)
    }

    parts <- regmatches(current, gregexpr(pattern, current, perl = TRUE))[[1]]

    for (token in parts) {
      hex <- sub(pattern, "\\1", token, perl = TRUE)
      codepoint <- suppressWarnings(strtoi(hex, base = 16L))

      restored <- tryCatch(
        intToUtf8(as.integer(codepoint)),
        error = function(e) token
      )

      if (is.na(restored) || !nzchar(restored)) {
        restored <- token
      }

      current <- sub(
        gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", token, perl = TRUE),
        restored,
        current,
        perl = TRUE
      )
    }

    enc2utf8(current)
  }, character(1), USE.NAMES = FALSE)
}

normalize_db_read_visible_value <- function(x, repair_mojibake = TRUE) {
  if (is.null(x) || !is.character(x)) {
    return(x)
  }

  out <- if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
    normalize_text_utf8(x, repair_mojibake = isTRUE(repair_mojibake))
  } else {
    enc2utf8(x)
  }

  db_unicode_restore_escapes(out)
}

normalize_db_read_visible_frame <- function(df, repair_mojibake = TRUE) {
  if (!is.data.frame(df)) {
    return(df)
  }

  for (nm in names(df)) {
    if (is.character(df[[nm]])) {
      df[[nm]] <- normalize_db_read_visible_value(
        df[[nm]],
        repair_mojibake = repair_mojibake
      )
    }
  }

  df
}
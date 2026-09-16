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

  # Hızlı yol: metnin tamamı hedef kodlamaya dönüşüyorsa kaçış gerekmez.
  tam_donusum <- tryCatch(
    iconv(value_utf8, from = "UTF-8", to = encoding_name, sub = NA_character_),
    error = function(e) NA_character_
  )
  if (length(tam_donusum) == 1L && !is.na(tam_donusum)) {
    return(value_utf8)
  }

  codepoints <- tryCatch(
    utf8ToInt(value_utf8),
    error = function(e) integer(0)
  )

  if (!length(codepoints)) {
    return(value_utf8)
  }

  # Kod noktası başına iconv yalnızca BENZERSİZ kod noktaları için çalışır.
  benzersiz <- unique(codepoints)
  karsilik <- vapply(benzersiz, function(codepoint) {
    if (db_unicode_codepoint_supported_by_encoding(codepoint, encoding_name)) {
      return(intToUtf8(as.integer(codepoint)))
    }

    db_unicode_escape_token(codepoint)
  }, character(1), USE.NAMES = FALSE)

  paste0(karsilik[match(codepoints, benzersiz)], collapse = "")
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
    eslesmeler <- gregexpr(pattern, current, perl = TRUE)

    if (length(eslesmeler[[1]]) == 1L && eslesmeler[[1]][1] < 0L) {
      return(current)
    }

    # Tek geçişli geri açma: belirteçler yerinde değiştirilir (O(n)); sub()
    # tabanlı belirteç-başına tarama ve değiştirme-metni kaçış sorunları kalkar.
    parts <- regmatches(current, eslesmeler)[[1]]
    hex <- sub(pattern, "\\1", parts, perl = TRUE)
    codepoints <- suppressWarnings(strtoi(hex, base = 16L))

    restored <- vapply(seq_along(parts), function(i) {
      cp <- codepoints[i]
      if (is.na(cp)) {
        return(parts[i])
      }
      karakter <- tryCatch(intToUtf8(as.integer(cp)), error = function(e) NA_character_)
      if (is.na(karakter) || !nzchar(karakter)) parts[i] else karakter
    }, character(1), USE.NAMES = FALSE)

    regmatches(current, eslesmeler) <- list(restored)

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
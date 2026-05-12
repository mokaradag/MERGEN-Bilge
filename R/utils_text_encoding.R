# ==============================================================================
# Dosya Yolu: R/utils_text_encoding.R
# Açıklama: Kullanıcıya görünen metinler, süreç çıktıları, JSON/DB sınırı ve
#           loglama için ortak UTF-8 normalizasyon yardımcıları.
# ==============================================================================

.text_encoding_win1252_reverse <- local({
  special <- c(
    0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
    0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
    0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178
  )
  stats::setNames(0x80:0x9F, as.character(special))
})

unicode_to_win1252_byte <- function(codepoint) {
  if (is.na(codepoint)) return(-1L)
  if (codepoint < 0x80L) return(as.integer(codepoint))
  if (codepoint >= 0xA0L && codepoint <= 0xFFL) return(as.integer(codepoint))

  key <- as.character(as.integer(codepoint))

  if (!key %in% names(.text_encoding_win1252_reverse)) {
    return(-1L)
  }

  mapped <- unname(.text_encoding_win1252_reverse[key])
  if (length(mapped) == 1L && !is.na(mapped)) {
    return(as.integer(mapped))
  }

  -1L
}

decode_win1252_mojibake_once <- function(text) {
  if (!is.character(text) || length(text) != 1L || is.na(text) || !nzchar(text)) {
    return(text)
  }

  codepoints <- tryCatch(
    utf8ToInt(text),
    error = function(e) integer(0)
  )

  if (!length(codepoints)) {
    return(text)
  }

  bytes <- vapply(codepoints, unicode_to_win1252_byte, integer(1), USE.NAMES = FALSE)

  if (any(bytes < 0L) || !any(bytes >= 0x80L)) {
    return(text)
  }

  decoded <- tryCatch(
    iconv(list(as.raw(bytes)), from = "UTF-8", to = "UTF-8", sub = NA_character_)[[1]],
    error = function(e) NA_character_
  )

  if (is.na(decoded) || !nzchar(decoded) || identical(decoded, text)) {
    return(text)
  }

  enc2utf8(decoded)
}

repair_text_mojibake <- function(x, max_passes = 2L) {
  if (is.null(x) || !is.character(x)) return(x)
  if (!length(x)) return(x)

  max_passes <- suppressWarnings(as.integer(max_passes))
  if (is.na(max_passes) || max_passes < 1L) {
    max_passes <- 1L
  }

  vapply(x, function(value) {
    if (is.na(value)) return(NA_character_)

    current <- tryCatch(enc2utf8(value), error = function(e) value)

    for (i in seq_len(max_passes)) {
      next_value <- decode_win1252_mojibake_once(current)
      if (identical(next_value, current)) {
        break
      }
      current <- next_value
    }

    enc2utf8(current)
  }, character(1), USE.NAMES = FALSE)
}

strip_ansi_sequences <- function(x) {
  if (is.null(x) || !is.character(x)) return(x)
  if (!length(x)) return(x)

  out <- x

  # CSI renk/biçim dizilerini temizle: ESC [ ... final-byte
  out <- gsub("\033\\[[0-9;?]*[ -/]*[@-~]", "", out, perl = TRUE)

  # OSC başlık/link dizilerini temizle: ESC ] ... BEL veya ESC \
  out <- gsub("\033\\][^\007]*(\007|\033\\\\)", "", out, perl = TRUE)

  out
}

normalize_text_utf8 <- function(x,
                                repair_mojibake = FALSE,
                                strip_ansi = FALSE) {
  if (is.null(x) || !is.character(x)) return(x)
  if (!length(x)) return(x)

  original_na <- is.na(x)
  out <- as.character(x)

  out <- vapply(out, function(value) {
    if (is.na(value)) return(NA_character_)

    converted <- tryCatch({
      valid_utf8 <- iconv(value, from = "UTF-8", to = "UTF-8", sub = NA_character_)
      if (!is.na(valid_utf8)) {
        Encoding(value) <- "UTF-8"
        value
      } else {
        enc2utf8(value)
      }
    }, error = function(e) {
      tryCatch(enc2utf8(value), error = function(e2) value)
    })

    converted <- enc2utf8(converted)

    if (isTRUE(repair_mojibake)) {
      converted <- repair_text_mojibake(converted)
    }

    if (isTRUE(strip_ansi)) {
      converted <- strip_ansi_sequences(converted)
    }

    converted
  }, character(1), USE.NAMES = FALSE)

  out[original_na] <- NA_character_
  out
}

mark_text_utf8 <- function(x) {
  if (is.null(x) || !is.character(x)) return(x)
  if (!length(x)) return(x)

  out <- x
  Encoding(out[!is.na(out)]) <- "UTF-8"
  out
}

normalize_text_frame_utf8 <- function(df,
                                      repair_mojibake = FALSE,
                                      strip_ansi = FALSE) {
  if (!is.data.frame(df)) return(df)

  for (nm in names(df)) {
    if (is.character(df[[nm]])) {
      df[[nm]] <- normalize_text_utf8(
        df[[nm]],
        repair_mojibake = repair_mojibake,
        strip_ansi = strip_ansi
      )
    } else if (is.factor(df[[nm]])) {
      levels(df[[nm]]) <- normalize_text_utf8(
        levels(df[[nm]]),
        repair_mojibake = repair_mojibake,
        strip_ansi = strip_ansi
      )
    } else if (is.list(df[[nm]])) {
      df[[nm]] <- normalize_text_tree_utf8(
        df[[nm]],
        repair_mojibake = repair_mojibake,
        strip_ansi = strip_ansi
      )
    }
  }

  df
}

normalize_text_tree_utf8 <- function(x,
                                     repair_mojibake = FALSE,
                                     strip_ansi = FALSE) {
  if (is.character(x)) {
    return(normalize_text_utf8(
      x,
      repair_mojibake = repair_mojibake,
      strip_ansi = strip_ansi
    ))
  }

  if (is.factor(x)) {
    levels(x) <- normalize_text_utf8(
      levels(x),
      repair_mojibake = repair_mojibake,
      strip_ansi = strip_ansi
    )
    return(x)
  }

  if (is.data.frame(x)) {
    return(normalize_text_frame_utf8(
      x,
      repair_mojibake = repair_mojibake,
      strip_ansi = strip_ansi
    ))
  }

  if (is.list(x)) {
    return(lapply(
      x,
      normalize_text_tree_utf8,
      repair_mojibake = repair_mojibake,
      strip_ansi = strip_ansi
    ))
  }

  x
}

mark_text_tree_utf8 <- function(x) {
  if (is.character(x)) {
    return(mark_text_utf8(x))
  }

  if (is.factor(x)) {
    levels(x) <- mark_text_utf8(levels(x))
    return(x)
  }

  if (is.data.frame(x)) {
    for (nm in names(x)) {
      if (is.character(x[[nm]])) {
        x[[nm]] <- mark_text_utf8(x[[nm]])
      } else if (is.factor(x[[nm]])) {
        levels(x[[nm]]) <- mark_text_utf8(levels(x[[nm]]))
      } else if (is.list(x[[nm]])) {
        x[[nm]] <- mark_text_tree_utf8(x[[nm]])
      }
    }
    return(x)
  }

  if (is.list(x)) {
    return(lapply(x, mark_text_tree_utf8))
  }

  x
}

normalize_text_for_log <- function(x) {
  normalize_text_utf8(
    x,
    repair_mojibake = TRUE,
    strip_ansi = TRUE
  )
}

read_text_lines_utf8 <- function(path,
                                 encodings = c("UTF-8", "WINDOWS-1254", "CP1254", "latin1"),
                                 repair_mojibake = FALSE) {
  if (!file.exists(path)) {
    return(character(0))
  }

  raw_size <- suppressWarnings(file.info(path)$size[1])
  if (is.na(raw_size) || raw_size <= 0) {
    return(character(0))
  }

  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_content <- readBin(con, what = "raw", n = raw_size)

  for (encoding_name in encodings) {
    txt <- tryCatch(
      iconv(list(raw_content), from = encoding_name, to = "UTF-8", sub = NA_character_)[[1]],
      error = function(e) NA_character_
    )

    if (is.na(txt) || !nzchar(txt)) {
      next
    }

    bom <- intToUtf8(0xFEFF)
    if (startsWith(txt, bom)) {
      txt <- substring(txt, 2L)
    }

    txt <- normalize_text_utf8(txt, repair_mojibake = repair_mojibake)

    lines <- strsplit(txt, "\\r\\n|\\n|\\r", perl = TRUE)[[1]]
    return(normalize_text_utf8(lines, repair_mojibake = repair_mojibake))
  }

  character(0)
}
# ==============================================================================
# Dosya Yolu: R/bootstrap_log_path.R
# Açıklama: MERGEN_LOG_DIR için ortak, erken ve Windows/UNC güvenli onarım katmanı.
# ==============================================================================

.mergen_log_path_pass_has_strong_mojibake <- function(text, byte_mapper) {
  if (!is.character(text) || length(text) != 1L || is.na(text) || !nzchar(text)) {
    return(FALSE)
  }

  codepoints <- tryCatch(
    utf8ToInt(enc2utf8(text)),
    error = function(e) integer(0)
  )
  if (!length(codepoints)) {
    return(FALSE)
  }

  bytes <- vapply(codepoints, byte_mapper, integer(1), USE.NAMES = FALSE)
  index <- 1L

  while (index <= length(codepoints)) {
    lead <- bytes[[index]]
    width <- if (lead >= 0xC2L && lead <= 0xDFL) {
      2L
    } else if (lead >= 0xE0L && lead <= 0xEFL) {
      3L
    } else if (lead >= 0xF0L && lead <= 0xF4L) {
      4L
    } else {
      0L
    }

    end_index <- index + width - 1L
    if (width > 0L && end_index <= length(bytes)) {
      candidate_bytes <- bytes[index:end_index]
      continuations <- candidate_bytes[-1L]
      valid_continuations <- all(
        continuations >= 0x80L & continuations <= 0xBFL
      )

      if (isTRUE(valid_continuations)) {
        decoded <- tryCatch(
          iconv(
            list(as.raw(candidate_bytes)),
            from = "UTF-8",
            to = "UTF-8",
            sub = NA_character_
          )[[1]],
          error = function(e) NA_character_
        )
        original_codepoints <- codepoints[index:end_index]
        original <- intToUtf8(original_codepoints)
        should_decode <- .should_decode_mojibake_candidate(
          original_codepoints,
          decoded
        )

        if (!is.na(decoded) &&
            nzchar(decoded) &&
            !identical(decoded, original) &&
            isTRUE(should_decode)) {
          # C3/C4/C5 yalnızca gerçekten çözülen adayın öncüsü olduğunda güçlü
          # kanıttır. Yolun başka bir yerindeki geçerli Å/Ã/Ä karakteri, belirsiz
          # bir C2 dizisini (örn. Â©) yanlışlıkla güçlü kanıta dönüştürmemelidir.
          if (original_codepoints[[1]] %in% c(0x00C3L, 0x00C4L, 0x00C5L)) {
            return(TRUE)
          }

          index <- end_index + 1L
          next
        }
      }
    }

    index <- index + 1L
  }

  FALSE
}

mergen_log_path_has_strong_mojibake <- function(path,
                                                 repaired = NULL,
                                                 max_passes = 2L) {
  if (is.null(path) || !length(path)) {
    return(FALSE)
  }

  path <- enc2utf8(as.character(path[[1]]))
  if (is.na(path) || !nzchar(path)) {
    return(FALSE)
  }

  if (!is.null(repaired) && identical(enc2utf8(as.character(repaired[[1]])), path)) {
    return(FALSE)
  }

  required_helpers <- c(
    "decode_win1252_mojibake_once",
    "decode_latin1_mojibake_once",
    "unicode_to_win1252_byte",
    "unicode_to_latin1_byte",
    ".should_decode_mojibake_candidate"
  )
  missing_helpers <- required_helpers[!vapply(
    required_helpers,
    exists,
    logical(1),
    mode = "function",
    inherits = TRUE
  )]
  if (length(missing_helpers)) {
    stop(
      sprintf(
        "MERGEN_LOG_DIR güçlü mojibake denetimi için yardımcılar eksik: %s",
        paste(missing_helpers, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  max_passes <- suppressWarnings(as.integer(max_passes[[1]]))
  if (is.na(max_passes) || max_passes < 1L) {
    max_passes <- 1L
  }

  current <- path

  for (i in seq_len(max_passes)) {
    if (.mergen_log_path_pass_has_strong_mojibake(
      current,
      unicode_to_win1252_byte
    )) {
      return(TRUE)
    }

    after_win1252 <- decode_win1252_mojibake_once(current)

    if (.mergen_log_path_pass_has_strong_mojibake(
      after_win1252,
      unicode_to_latin1_byte
    )) {
      return(TRUE)
    }

    next_value <- decode_latin1_mojibake_once(after_win1252)
    if (identical(next_value, current)) {
      break
    }

    current <- next_value
  }

  FALSE
}

repair_mergen_log_dir <- function(path, max_passes = 2L) {
  if (is.null(path) || !length(path)) {
    return("")
  }

  path <- enc2utf8(trimws(as.character(path[[1]])))
  if (is.na(path) || !nzchar(path)) {
    return(path)
  }

  if (!exists("repair_text_mojibake", mode = "function", inherits = TRUE) ||
      !exists("text_has_mojibake", mode = "function", inherits = TRUE)) {
    stop(
      "MERGEN_LOG_DIR onarımı için R/utils_text_encoding.R önce yüklenmelidir.",
      call. = FALSE
    )
  }

  max_passes <- suppressWarnings(as.integer(max_passes[[1]]))
  if (is.na(max_passes) || max_passes < 1L) {
    max_passes <- 1L
  }

  repaired <- repair_text_mojibake(path, max_passes = max_passes)
  if (any(text_has_mojibake(repaired))) {
    stop(
      sprintf("MERGEN_LOG_DIR %d geçişte onarılamadı.", max_passes),
      call. = FALSE
    )
  }

  if (identical(repaired, path)) {
    return(path)
  }

  original_exists <- dir.exists(path)
  repaired_exists <- dir.exists(repaired)
  strong_evidence <- mergen_log_path_has_strong_mojibake(
    path,
    repaired,
    max_passes = max_passes
  )

  # Güçlü kanıt varsa, önceki sürüm bozuk klasörü daha önce oluşturmuş olsa bile
  # doğru hedefe geç. Belirsiz tek C2 dizilerinde ise yalnızca onarılmış hedef
  # zaten mevcutsa yön değiştir; ilk çalıştırmada geçerli bir klasör adını bozma.
  if (isTRUE(strong_evidence) || (!isTRUE(original_exists) && isTRUE(repaired_exists))) {
    return(enc2utf8(repaired))
  }

  path
}

normalize_mergen_log_dir_env <- function(max_passes = 2L) {
  configured <- Sys.getenv("MERGEN_LOG_DIR", "")
  repaired <- repair_mergen_log_dir(configured, max_passes = max_passes)

  if (!identical(repaired, trimws(configured))) {
    Sys.setenv(MERGEN_LOG_DIR = repaired)
  }

  invisible(repaired)
}

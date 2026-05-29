# ==============================================================================
# Dosya Yolu: R/helpers_mailto_encoding.R
# Açıklama:   Mailto bağlantılarındaki konu ve gövde alanları için UTF-8 güvenli
#             percent-encoding yardımcıları.
#             Windows/VM yerel kod sayfasına bağlı URLencode davranışını önler.
# ==============================================================================

# ==============================================================================
# MAILTO METİN NORMALİZASYONU
# ==============================================================================

mergen_mailto_normalize_text <- function(x) {
  if (is.null(x) || length(x) == 0L) {
    return("")
  }

  x <- as.character(x)
  x[is.na(x)] <- ""
  x <- paste(x, collapse = "\n")

  if (exists("normalize_text_utf8", mode = "function")) {
    x <- normalize_text_utf8(
      x,
      repair_mojibake = FALSE,
      strip_ansi = FALSE
    )
  } else {
    x <- enc2utf8(x)
  }

  x <- enc2utf8(x)
  Encoding(x) <- "UTF-8"
  x
}

# ==============================================================================
# UTF-8 BAYT TEMELLİ PERCENT-ENCODING
# ==============================================================================

mergen_mailto_percent_encode <- function(x) {
  x <- mergen_mailto_normalize_text(x)

  if (!nzchar(x)) {
    return("")
  }

  bytes <- as.integer(charToRaw(x))

  encoded_parts <- vapply(bytes, function(byte_value) {
    is_unreserved <-
      (byte_value >= 0x41L && byte_value <= 0x5AL) || # A-Z
      (byte_value >= 0x61L && byte_value <= 0x7AL) || # a-z
      (byte_value >= 0x30L && byte_value <= 0x39L) || # 0-9
      byte_value %in% c(0x2DL, 0x2EL, 0x5FL, 0x7EL)  # - . _ ~

    if (is_unreserved) {
      rawToChar(as.raw(byte_value))
    } else {
      sprintf("%%%02X", byte_value)
    }
  }, character(1), USE.NAMES = FALSE)

  paste0(encoded_parts, collapse = "")
}

# ==============================================================================
# MAILTO HREF OLUŞTURMA
# ==============================================================================

mergen_mailto_href <- function(to, subject = NULL, body = NULL) {
  to <- trimws(mergen_mailto_normalize_text(to))

  query_parts <- character(0)

  if (!is.null(subject)) {
    query_parts <- c(
      query_parts,
      paste0("subject=", mergen_mailto_percent_encode(subject))
    )
  }

  if (!is.null(body)) {
    query_parts <- c(
      query_parts,
      paste0("body=", mergen_mailto_percent_encode(body))
    )
  }

  href <- paste0("mailto:", to)

  if (length(query_parts) > 0L) {
    href <- paste0(href, "?", paste(query_parts, collapse = "&"))
  }

  href
}
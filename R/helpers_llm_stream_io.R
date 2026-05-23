# ==============================================================================
# Dosya Yolu: R/helpers_llm_stream_io.R
# Açıklama: LLM SSE akış dosyası satır protokolü yardımcıları.
# ==============================================================================

# ------------------------------------------------------------------------------
# UTF-8 SINIR TARAYICISI
# ------------------------------------------------------------------------------
# SSE parçaları çoklu baytlı UTF-8 karakterlerin ortasında bölünebilir.
# Bu yardımcı, verilen ham bayt dizisinin sonunda kaç byte'a kadar TAM bir
# UTF-8 karakter olduğunu döndürür. Yarım kalan baytlar bir sonraki parçanın
# başına aktarılabilir; böylece "input string 1 is invalid UTF-8" hatası
# akış sırasında oluşmaz.
find_last_utf8_boundary <- function(bytes) {
  n <- length(bytes)
  if (n == 0L) return(0L)

  last_byte <- as.integer(bytes[n])
  # ASCII (0xxxxxxx): tek baytlı tam karakter
  if (bitwAnd(last_byte, 0x80L) == 0L) {
    return(n)
  }

  # Son bayt continuation veya lead - en fazla 4 bayt geriye tara
  scan_start <- max(1L, n - 3L)
  for (i in n:scan_start) {
    byte <- as.integer(bytes[i])

    # Continuation byte (10xxxxxx): geriye devam et
    if (bitwAnd(byte, 0xC0L) == 0x80L) {
      next
    }

    # ASCII (0xxxxxxx): geriye doğru ASCII bulunduysa devam eden continuation
    # baytları geçersiz; lead byte beklenirdi. Yine de iconv ile temizlenir.
    if (bitwAnd(byte, 0x80L) == 0L) {
      return(n)
    }

    # Lead byte tipini belirle
    needed <- if (bitwAnd(byte, 0xF8L) == 0xF0L) 4L
              else if (bitwAnd(byte, 0xF0L) == 0xE0L) 3L
              else if (bitwAnd(byte, 0xE0L) == 0xC0L) 2L
              else 0L

    if (needed == 0L) {
      # Geçersiz lead byte - hepsini gönder, iconv temizler
      return(n)
    }

    have <- n - i + 1L
    if (have >= needed) {
      # Multi-byte karakter tamamlanmış
      return(n)
    }
    # Yarım kalan karakter - lead byte'tan önceki son tam karakterde kes
    return(i - 1L)
  }

  # 4 bayt continuation - veri muhtemelen bozuk, iconv ile temizleyelim
  return(n)
}

# ------------------------------------------------------------------------------
# DURUMLU UTF-8 PARÇA ÇÖZÜCÜ
# ------------------------------------------------------------------------------
# SSE callback'i çağrıları arasında yarım UTF-8 baytlarını buffer'lar.
# Her çağrıda yalnızca tam karakterler içeren metni döndürür.
create_utf8_stream_decoder <- function() {
  partial_buffer <- raw(0)

  decode <- function(raw_chunk) {
    if (length(raw_chunk) == 0L) return("")

    combined <- if (length(partial_buffer) > 0L) c(partial_buffer, raw_chunk) else raw_chunk

    cut_at <- find_last_utf8_boundary(combined)

    if (cut_at < length(combined)) {
      partial_buffer <<- combined[(cut_at + 1L):length(combined)]
    } else {
      partial_buffer <<- raw(0)
    }

    if (cut_at == 0L) return("")

    complete_bytes <- combined[seq_len(cut_at)]
    txt <- tryCatch(rawToChar(complete_bytes), error = function(e) "")
    Encoding(txt) <- "UTF-8"

    # Geçersiz UTF-8 baytları (örn. eksik continuation) güvenle temizlenir
    sanitized <- tryCatch(
      iconv(txt, from = "UTF-8", to = "UTF-8", sub = ""),
      error = function(e) ""
    )
    if (is.na(sanitized)) "" else sanitized
  }

  reset <- function() {
    partial_buffer <<- raw(0)
  }

  flush <- function() {
    if (length(partial_buffer) == 0L) return("")
    txt <- tryCatch(rawToChar(partial_buffer), error = function(e) "")
    partial_buffer <<- raw(0)
    if (!nzchar(txt)) return("")
    Encoding(txt) <- "UTF-8"
    sanitized <- tryCatch(
      iconv(txt, from = "UTF-8", to = "UTF-8", sub = ""),
      error = function(e) ""
    )
    if (is.na(sanitized)) "" else sanitized
  }

  list(decode = decode, reset = reset, flush = flush)
}

# ------------------------------------------------------------------------------
# AKIŞ SATIRI YAZICI FABRİKASI
# ------------------------------------------------------------------------------

create_stream_line_appender <- function(line_type) {
  line_type <- as.character(line_type %||% "")[1]

  if (!line_type %in% c("delta", "reasoning_delta")) {
    stop(sprintf("Geçersiz stream satır tipi: %s", line_type), call. = FALSE)
  }

  force(line_type)

  function(stream_file, text_value, stream_con = NULL) {
    if ((!nzchar(stream_file %||% "")) && is.null(stream_con)) {
      return(invisible(NULL))
    }

    if (!nzchar(text_value %||% "")) {
      return(invisible(NULL))
    }

    text_utf8 <- enc2utf8(as.character(text_value)[1])
    text_b64 <- base64enc::base64encode(charToRaw(text_utf8))

    payload <- jsonlite::toJSON(
      list(type = line_type, text_b64 = text_b64),
      auto_unbox = TRUE,
      null = "null"
    )

    payload_line <- paste0(payload, "\n")

    if (!is.null(stream_con)) {
      writeBin(charToRaw(payload_line), stream_con)
      flush(stream_con)
      return(invisible(NULL))
    }

    con <- file(stream_file, open = "ab")
    on.exit(close(con), add = TRUE)

    writeBin(charToRaw(payload_line), con)
    flush(con)
    invisible(NULL)
  }
}

append_stream_delta_line <- create_stream_line_appender("delta")

append_stream_reasoning_line <- create_stream_line_appender("reasoning_delta")

decode_stream_delta_payload <- function(payload) {
  if (is.null(payload)) {
    return("")
  }

  if (!is.null(payload$text_b64) && nzchar(as.character(payload$text_b64 %||% ""))) {
    decoded_raw <- tryCatch(
      base64enc::base64decode(as.character(payload$text_b64)[1]),
      error = function(e) NULL
    )

    if (!is.null(decoded_raw) && length(decoded_raw) > 0) {
      decoded_text <- tryCatch(rawToChar(decoded_raw), error = function(e) "")
      Encoding(decoded_text) <- "UTF-8"
      return(enc2utf8(decoded_text))
    }
  }

  if (!is.null(payload$text)) {
    return(enc2utf8(as.character(payload$text %||% "")))
  }

  ""
}

# ------------------------------------------------------------------------------
# KULLANICI DURDURMA SİNYALİ KONTROLÜ
# ------------------------------------------------------------------------------
# Akış sırasında kullanıcı "Durdur" butonuna bastığında ilgili stop_file dosyası
# oluşturulur. Klasör veya geçersiz yol stop sinyali sayılmaz.

streaming_should_stop <- function(stop_file) {
  if (is.null(stop_file)) return(FALSE)

  candidate <- tryCatch(as.character(stop_file)[1], error = function(e) "")
  if (!nzchar(candidate) || is.na(candidate)) return(FALSE)
  if (!isTRUE(file.exists(candidate))) return(FALSE)

  info <- suppressWarnings(file.info(candidate))
  is_regular_file <- is.data.frame(info) &&
    nrow(info) >= 1L &&
    isFALSE(isTRUE(info$isdir[1]))

  isTRUE(is_regular_file)
}
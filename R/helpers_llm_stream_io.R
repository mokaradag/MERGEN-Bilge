# ==============================================================================
# Dosya Yolu: R/helpers_llm_stream_io.R
# Açıklama: LLM SSE akış dosyası satır protokolü yardımcıları.
# ==============================================================================

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
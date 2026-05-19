# ==============================================================================
# Dosya Yolu: R/helpers_streaming_abort_lifecycle.R
# Açıklama: True streaming abort/cancel sonuçları için saf karar yardımcısı.
#           Shiny, DB, dosya veya LLM çağrısı içermez.
# ==============================================================================

mergen_stream_abort_cleanup_plan <- function(accumulated_text,
                                             result = list(),
                                             normalize_fn = NULL) {
  if (!is.function(normalize_fn)) {
    normalize_fn <- function(x) {
      if (is.null(x)) return("")
      value <- as.character(x)[1]
      if (is.na(value)) "" else value
    }
  }

  partial_text <- tryCatch(
    enc2utf8(normalize_fn(accumulated_text %||% "")),
    error = function(e) ""
  )

  if (is.na(partial_text)) {
    partial_text <- ""
  }

  error_text <- tryCatch(
    enc2utf8(as.character(result$error %||% "")[1]),
    error = function(e) ""
  )

  if (is.na(error_text)) {
    error_text <- ""
  }

  aborted <- isTRUE(result$aborted)
  has_error <- !aborted && nzchar(error_text)
  has_partial <- nzchar(partial_text)

  list(
    action = if (has_partial) "finalize_partial" else "remove_placeholder",
    final_text = partial_text,
    request_success = FALSE,
    duration = result$duration %||% NULL,
    aborted = aborted,
    error = error_text,
    track_error = has_error,
    show_toast = has_error,
    toast_type = if (has_partial) "warning" else "error"
  )
}
# Sohbetin takip önerisi ve grafik yayın yardımcıları.

chat_discard_stream_placeholder <- function(session, values, message_id) {
  if (is.null(message_id)) return(invisible(NULL))
  removed <- shiny::isolate({
    idx <- which(vapply(values$messages, function(m) {
      identical(m$id, message_id) && isTRUE(m$is_streaming)
    }, logical(1)))
    if (length(idx)) values$messages <- values$messages[-idx]
    length(idx) > 0L
  })
  if (removed) try(shiny::withReactiveDomain(session, shiny::removeUI(
    selector = paste0("#message_wrapper_", message_id),
    multiple = FALSE, immediate = TRUE
  )), silent = TRUE)
  invisible(NULL)
}

push_followup_update <- function(session, message_id, followups, pending = FALSE) {
  if (is.null(session) || is.null(message_id)) {
    return(invisible(NULL))
  }

  cleaned <- followups %||% character(0)
  cleaned <- trimws(as.character(cleaned))
  cleaned <- cleaned[nzchar(cleaned)]
  if (!length(cleaned)) {
    return(invisible(NULL))
  }

	payload <- list(
	  id = message_id,
	  followups = unname(cleaned),
	  pending = isTRUE(pending)
	)

	cat(sprintf(
	  "[FOLLOWUPS][PUSH] message_id=%s count=%d pending=%s\n",
	  as.character(message_id),
	  length(cleaned),
	  isTRUE(pending)
	))

	try(session$sendCustomMessage("updateFollowupSuggestions", payload), silent = TRUE)
	invisible(NULL)
}

chat_rebind_all_charts <- function(session, output, messages) {
  if (length(messages) == 0) return(invisible(NULL))

  for (msg in messages) {
    if (!is.character(msg$content) ||
        length(msg$content) == 0 ||
        !grepl("```chartlab", msg$content[1], fixed = TRUE)) {
      next
    }

    chart_info <- build_chartlab_message(msg$content[1], msg$id, session)

    if (isTRUE(chart_info$found) && length(chart_info$renderers) > 0) {
      for (r in chart_info$renderers) {
        local({
          local_r <- r
          session$onFlushed(function() {
            try(wire_chart_output(output, local_r$output_id, local_r$spec), silent = TRUE)
          }, once = TRUE)
        })
      }
    }
  }

  invisible(NULL)
}

# ==============================================================================
# Dosya Yolu: R/helpers_ai_expert_lifecycle.R
# Açıklama: Otomatik AI Uzman konuşmaları için saf nesil-belirteci, iptal yüklemi
#           ve içerik taşımayan performans izi yardımcıları.
# ==============================================================================

if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
}

MERGEN_AI_EXPERT_TRACE_STAGES <- c(
  "navigation_trigger", "greeting_trigger", "llm_request_start", "llm_complete",
  "prewarm_lookup", "tts_queue_submit", "tts_worker_start", "tts_worker_complete",
  "audio_dispatch", "browser_playing", "browser_ended", "browser_error",
  "guidance_invalidated"
)

mergen_ai_expert_next_generation <- function(current) {
  value <- suppressWarnings(as.integer(current)[1])
  if (is.na(value) || value < 0L || value >= .Machine$integer.max) return(1L)
  value + 1L
}

mergen_ai_expert_generation_is_current <- function(expected_generation,
                                                   current_generation,
                                                   expected_page,
                                                   current_page) {
  expected <- suppressWarnings(as.integer(expected_generation)[1])
  current <- suppressWarnings(as.integer(current_generation)[1])
  !is.na(expected) && !is.na(current) && identical(expected, current) &&
    identical(as.character(expected_page %||% "")[1], as.character(current_page %||% "")[1])
}

mergen_ai_expert_cancel_predicate <- function(expected_generation, expected_page,
                                              generation_getter, page_getter,
                                              read = identity) {
  force(expected_generation); force(expected_page)
  force(generation_getter); force(page_getter); force(read)
  function() {
    !mergen_ai_expert_generation_is_current(
      expected_generation, read(generation_getter()), expected_page, read(page_getter())
    )
  }
}

mergen_ai_expert_trace_line <- function(stage, sequence_id = NULL,
                                        generation_id = NULL, page_id = NULL,
                                        chunk_index = NULL, duration_ms = NULL,
                                        at = Sys.time()) {
  stage <- as.character(stage %||% "")[1]
  if (!(stage %in% MERGEN_AI_EXPERT_TRACE_STAGES)) {
    stop("Bilinmeyen AI Uzman iz aşaması.", call. = FALSE)
  }
  fields <- c(
    sprintf("at=%s", format(as.POSIXct(at), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")),
    sprintf("stage=%s", stage)
  )
  add_integer <- function(name, value) {
    parsed <- suppressWarnings(as.integer(value)[1])
    if (!is.na(parsed)) sprintf("%s=%d", name, parsed) else character(0)
  }
  fields <- c(fields, add_integer("seq", sequence_id), add_integer("generation", generation_id))
  if (!is.null(page_id)) {
    safe_page <- gsub("[^[:alnum:]_-]", "_", substr(as.character(page_id)[1], 1L, 80L))
    if (nzchar(safe_page)) fields <- c(fields, sprintf("page=%s", safe_page))
  }
  fields <- c(fields, add_integer("chunk", chunk_index))
  duration <- suppressWarnings(as.numeric(duration_ms)[1])
  if (!is.na(duration) && is.finite(duration) && duration >= 0) {
    fields <- c(fields, sprintf("duration_ms=%.0f", duration))
  }
  paste("[AI_EXPERT_TRACE]", paste(fields, collapse = " "))
}

mergen_ai_expert_trace_context_line <- function(stage, context = NULL,
                                                 duration_ms = NULL, at = Sys.time()) {
  if (!is.list(context)) return(NULL)
  mergen_ai_expert_trace_line(
    stage, sequence_id = context$sequence_id, generation_id = context$generation_id,
    page_id = context$page_id, chunk_index = context$chunk_index,
    duration_ms = duration_ms, at = at
  )
}

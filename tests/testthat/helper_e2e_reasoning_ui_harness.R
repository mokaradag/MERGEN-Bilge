# ==============================================================================
# Dosya Yolu: tests/testthat/helper_e2e_reasoning_ui_harness.R
# Açıklama: Premium reasoning / thinking UI yaşam döngüsü için gerçek tarayıcı,
#           gerçek LLM veya gerçek SSE gerektirmeyen deterministik E2E harness.
# ==============================================================================

e2e_reasoning_new_state <- function() {
  list(
    status = "idle",
    active_req_id = NULL,
    msg_id = NULL,
    model_label = "",
    simulated = FALSE,
    reasoning_buffer = "",
    visible_answer = "",
    persisted_reasoning = NULL,
    live_panels = list(),
    archived_panels = list(),
    finalized_req_ids = character(0),
    events = character(0)
  )
}

e2e_reasoning_add_event <- function(state, event) {
  state$events <- c(state$events, enc2utf8(as.character(event)[1]))
  state
}

e2e_reasoning_is_current <- function(state, req_id) {
  !is.null(req_id) &&
    nzchar(as.character(req_id)[1]) &&
    identical(state$active_req_id, as.character(req_id)[1])
}

e2e_reasoning_sanitize_model_label <- function(value) {
  if (is.null(value)) {
    return("")
  }

  if (is.character(value)) {
    value <- trimws(value[1])
    if (!nzchar(value) || identical(value, "[object Object]")) {
      return("")
    }
    return(value)
  }

  if (is.list(value)) {
    for (field in c("name", "label", "value", "id")) {
      if (!is.null(value[[field]])) {
        label <- e2e_reasoning_sanitize_model_label(value[[field]])
        if (nzchar(label)) {
          return(label)
        }
      }
    }
    return("")
  }

  coerced <- tryCatch(as.character(value)[1], error = function(e) "")
  if (!nzchar(coerced) || identical(coerced, "[object Object]")) {
    return("")
  }

  coerced
}

e2e_reasoning_count_live_panels <- function(state) {
  length(state$live_panels)
}

e2e_reasoning_count_archived_panels <- function(state) {
  length(state$archived_panels)
}

e2e_reasoning_update_live_panels <- function(state) {
  state$live_panels <- lapply(state$live_panels, function(panel) {
    panel$content <- state$reasoning_buffer
    panel
  })

  state
}

e2e_reasoning_cleanup_active <- function(state, keep_buffer = FALSE) {
  if (length(state$live_panels) > 0L) {
    state <- e2e_reasoning_add_event(state, "cleanup_active_reasoning_panel")
  }

  state$live_panels <- list()
  state$status <- "idle"
  state$msg_id <- NULL
  state$simulated <- FALSE

  if (!isTRUE(keep_buffer)) {
    state$reasoning_buffer <- ""
  }

  state
}

e2e_reasoning_start <- function(state, req_id, model = "", simulated = FALSE) {
  req_id <- as.character(req_id)[1]
  if (!nzchar(req_id)) {
    stop("req_id boş olamaz.", call. = FALSE)
  }

  state <- e2e_reasoning_cleanup_active(state, keep_buffer = FALSE)

  state$status <- "preparing"
  state$active_req_id <- req_id
  state$model_label <- e2e_reasoning_sanitize_model_label(model)
  state$simulated <- isTRUE(simulated)
  state$reasoning_buffer <- ""
  state$persisted_reasoning <- NULL

  state$live_panels <- list(list(
    req_id = req_id,
    msg_id = NULL,
    kind = "shell",
    data_state = "live",
    content = ""
  ))

  if (isTRUE(state$simulated)) {
    state$reasoning_buffer <- "simulated_phase:question_analysis"
    state <- e2e_reasoning_update_live_panels(state)
  }

  state
}

e2e_reasoning_delta <- function(state, req_id, delta) {
  req_id <- as.character(req_id)[1]

  if (!e2e_reasoning_is_current(state, req_id)) {
    return(e2e_reasoning_add_event(
      state,
      paste0("reasoning_delta_ignored:stale:", req_id)
    ))
  }

  if (identical(state$status, "idle")) {
    return(e2e_reasoning_add_event(state, "reasoning_delta_ignored:idle"))
  }

  text <- enc2utf8(as.character(delta %||% "")[1])
  if (!nzchar(text)) {
    return(state)
  }

  state$reasoning_buffer <- paste0(state$reasoning_buffer, text)

  if (identical(state$status, "preparing")) {
    state$status <- "live"
  }

  e2e_reasoning_update_live_panels(state)
}

e2e_reasoning_stream_start <- function(state, req_id, msg_id) {
  req_id <- as.character(req_id)[1]
  msg_id <- as.character(msg_id)[1]

  if (!e2e_reasoning_is_current(state, req_id)) {
    return(e2e_reasoning_add_event(
      state,
      paste0("stream_start_ignored:stale:", req_id)
    ))
  }

  if (isTRUE(state$simulated)) {
    state <- e2e_reasoning_cleanup_active(state, keep_buffer = FALSE)
    state$active_req_id <- NULL
    state <- e2e_reasoning_add_event(state, "simulated_reasoning_removed_on_stream_start")
    return(state)
  }

  state$status <- "streaming"
  state$msg_id <- msg_id

  if (length(state$live_panels) == 0L) {
    state$live_panels <- list(list(
      req_id = req_id,
      msg_id = msg_id,
      kind = "bubble",
      data_state = "streaming",
      content = state$reasoning_buffer
    ))
  } else {
    state$live_panels <- list(list(
      req_id = req_id,
      msg_id = msg_id,
      kind = "bubble",
      data_state = "streaming",
      content = state$reasoning_buffer
    ))
  }

  state
}

e2e_reasoning_visible_delta <- function(state, req_id, delta) {
  req_id <- as.character(req_id)[1]

  if (!e2e_reasoning_is_current(state, req_id)) {
    return(e2e_reasoning_add_event(
      state,
      paste0("visible_delta_ignored:stale:", req_id)
    ))
  }

  text <- enc2utf8(as.character(delta %||% "")[1])
  if (nzchar(text)) {
    state$visible_answer <- paste0(state$visible_answer, text)
  }

  state
}

e2e_reasoning_reset <- function(state, req_id, outcome = "completed") {
  req_id <- as.character(req_id)[1]

  if (req_id %in% state$finalized_req_ids) {
    return(e2e_reasoning_add_event(
      state,
      paste0("reasoning_reset_ignored:already_finalized:", req_id)
    ))
  }

  if (!e2e_reasoning_is_current(state, req_id)) {
    return(e2e_reasoning_add_event(
      state,
      paste0("reasoning_reset_ignored:stale:", req_id)
    ))
  }

  state$finalized_req_ids <- c(state$finalized_req_ids, req_id)

  if (isTRUE(state$simulated)) {
    state <- e2e_reasoning_cleanup_active(state, keep_buffer = FALSE)
    state$active_req_id <- NULL
    state$persisted_reasoning <- NULL
    return(state)
  }

  reasoning <- enc2utf8(state$reasoning_buffer %||% "")
  if (nzchar(reasoning)) {
    archived <- list(
      req_id = req_id,
      msg_id = state$msg_id %||% req_id,
      data_state = outcome,
      content = reasoning
    )

    state$archived_panels <- append(state$archived_panels, list(archived))
    state$persisted_reasoning <- reasoning
  }

  state <- e2e_reasoning_cleanup_active(state, keep_buffer = FALSE)
  state$active_req_id <- NULL
  state$status <- "idle"
  state
}
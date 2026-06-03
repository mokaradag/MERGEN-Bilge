# R/module_message_search.R
# Lightweight init that wires the existing search box + prev/next buttons.
# No UI changes; uses the SAME input ids: message_search, prev_match, next_match.

messageSearchInit <- function(input, session, values, messages_reactive) {
  state <- shiny::reactiveValues(matches = list(), total = 0, current = 0, term = "")

  # Main search
  shiny::observeEvent(input$message_search, {
    term <- trimws(input$message_search %||% "")
    state$term <- term

    if (!nzchar(term)) {
      session$sendCustomMessage("clearHighlights", list())
      shinyjs::runjs("$('#search_nav_controls').hide(); $('#search_counter').text('0/0');")
      state$matches <- list(); state$total <- 0; state$current <- 0
      return()
    }

    msgs <- messages_reactive() %||% list()
    all <- list()
    for (msg in msgs) {
      txt <- msg$content %||% ""
      if (is.character(txt) && length(txt) > 0 && nzchar(txt[1])) {
        # Not: fixed = TRUE iken R, ignore.case argümanını sessizce yok sayar ve
        # her aramada "argument 'ignore.case = TRUE' will be ignored" uyarısı
        # üretir. Argüman zaten etkisiz olduğundan kaldırıldı; eşleşme konumları
        # birebir aynı kalır (davranış değişmez), yalnızca sahte uyarı giderilir.
        pos <- gregexpr(term, txt[1], fixed = TRUE)[[1]]
        if (!is.na(pos[1]) && pos[1] != -1) {
          for (p in pos) all <- append(all, list(list(msg_id = msg$id, position = p)))
        }
      }
    }

    state$matches <- all
    state$total   <- length(all)
    state$current <- if (state$total > 0) 1 else 0

    unique_ids <- unique(vapply(all, function(x) x$msg_id, "", USE.NAMES = FALSE))
    session$sendCustomMessage("highlightAllOccurrences", list(
      searchTerm  = term,
      messageIds  = unique_ids,
      totalCount  = state$total,
      currentIndex= state$current
    ))

    shinyjs::runjs(sprintf("
      $('#search_nav_controls').css('display', 'flex');
      $('#search_counter').text('%d/%d');
    ", state$current, state$total))

    # Also reflect on the two arrow button labels (if present)
    updateActionButton(session, "prev_match",
      label = sprintf('\U2190 (%d/%d)', state$current, state$total))
    updateActionButton(session, "next_match",
      label = sprintf('(%d/%d) \U2192', state$current, state$total))
  }, ignoreInit = TRUE)

  # Prev
  shiny::observeEvent(input$prev_match, {
    if (state$total <= 0) return()
    state$current <- if (state$current > 1) state$current - 1 else state$total

    session$sendCustomMessage("highlightMessages", list(
      searchTerm  = state$term,
      matches     = state$matches,
      currentIndex= state$current
    ))
    shinyjs::runjs(sprintf("$('#search_counter').text('%d/%d');", state$current, state$total))
    updateActionButton(session, "prev_match",
      label = sprintf('\U2190 (%d/%d)', state$current, state$total))
    updateActionButton(session, "next_match",
      label = sprintf('(%d/%d) \U2192', state$current, state$total))
  }, ignoreInit = TRUE)

  # Next
  shiny::observeEvent(input$next_match, {
    if (state$total <= 0) return()
    state$current <- if (state$current < state$total) state$current + 1 else 1

    session$sendCustomMessage("highlightMessages", list(
      searchTerm  = state$term,
      matches     = state$matches,
      currentIndex= state$current
    ))
    shinyjs::runjs(sprintf("$('#search_counter').text('%d/%d');", state$current, state$total))
    updateActionButton(session, "prev_match",
      label = sprintf('\U2190 (%d/%d)', state$current, state$total))
    updateActionButton(session, "next_match",
      label = sprintf('(%d/%d) \U2192', state$current, state$total))
  }, ignoreInit = TRUE)
}
# Uzak veya belirsiz süreç sahipliği ölüm kanıtı sayılmaz.
mergen_pid_status <- function(pid, host) {
  pid <- suppressWarnings(as.integer(pid)[1])
  if (length(pid) != 1L || is.na(pid) || pid <= 0L ||
      !identical(host, unname(Sys.info()[["nodename"]]))) return(NA)
  tryCatch(pid %in% ps::ps_pids(), error = function(e) NA)
}

mergen_lock_owner_dead <- function(marker, token = NULL) {
  lines <- suppressWarnings(tryCatch(readLines(marker, warn = FALSE), error = function(e) character()))
  host <- sub("^host=", "", lines[startsWith(lines, "host=")])
  pid <- if (is.null(token)) sub("^pid=", "", lines[startsWith(lines, "pid=")]) else sub("-.*$", "", token)
  length(host) == 1L && length(pid) == 1L && identical(mergen_pid_status(pid, host), FALSE)
}

mergen_cancellable_worker_available <- function() {
  requireNamespace("callr", quietly = TRUE) && requireNamespace("promises", quietly = TRUE) &&
    requireNamespace("later", quietly = TRUE) &&
    exists("mergen_cancellable_worker_promise", mode = "function", inherits = TRUE)
}

cc_run_state_reference <- function(rv) {
  ref <- shiny::isolate(rv$run_state_ref)
  if (!is.environment(ref)) {
    ref <- new.env(parent = emptyenv())
    ref$rv <- rv
    rv$run_state_ref <- ref
  }
  ref
}

cc_detach_run_state <- function(ref, session) {
  rv <- ref$rv
  if (shiny::is.reactivevalues(rv))
    rv <- list2env(shiny::isolate(shiny::reactiveValuesToList(rv, all.names = TRUE)), parent = emptyenv())
  ud <- session$userData
  owner <- ud$user_id
  generation <- ud$kimlik_nesli %||% 0L
  rv$run_owner_guard <- function() identical(ud$user_id, owner) &&
    identical(ud$kimlik_nesli %||% 0L, generation)
  ref$rv <- rv
  invisible(rv)
}

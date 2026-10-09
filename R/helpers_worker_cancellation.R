# İptal edilebilir işler ortak future havuzundan bağımsız ve sınırlıdır.
.MERGEN_CANCELLABLE_WORKERS <- new.env(parent = emptyenv())

mergen_process_status <- function(process) {
  tryCatch(isTRUE(process$is_alive()), error = function(e) NA)
}

mergen_process_alive <- function(process) isTRUE(mergen_process_status(process))

mergen_process_stop <- function(process) {
  if (identical(mergen_process_status(process), FALSE)) return(TRUE)
  try(process$kill_tree(), silent = TRUE)
  try(process$kill(grace = 0), silent = TRUE)
  !isTRUE(mergen_process_status(process))
}

mergen_retire_process <- function(process, release) {
  released <- FALSE
  poll <- function() {
    if (released) return(invisible(NULL))
    if (mergen_process_stop(process)) {
      released <<- TRUE
      try(release(), silent = TRUE)
    } else {
      mergen_cancellable_worker_schedule(poll, delay = 0.5)
    }
    invisible(NULL)
  }
  poll()
}

mergen_cancellable_worker_capacity <- function() {
  configured <- getOption("mergen.cancellable_workers", NULL)
  if (is.null(configured)) configured <- tryCatch(future::nbrOfWorkers(), error = function(e) 1L)
  value <- suppressWarnings(as.integer(configured)[1])
  if (length(value) != 1L || is.na(value) || value < 1L) 1L else value
}

mergen_cancellable_worker_settle <- function(job, error = NULL) {
  if (isTRUE(job$finished)) return(invisible(NULL))
  job$finished <- TRUE
  if (!is.null(error)) try(job$reject(error), silent = TRUE) else
    tryCatch(job$resolve(job$process$get_result()), error = function(e) try(job$reject(e), silent = TRUE))
  invisible(NULL)
}

mergen_cancellable_worker_tick <- function() {
  state <- .MERGEN_CANCELLABLE_WORKERS
  state$scheduled <- FALSE
  keep <- list()
  for (job in state$jobs) {
    if (isTRUE(job$finished)) next
    expired <- !is.null(job$started) &&
      as.numeric(difftime(Sys.time(), job$started, units = "secs")) > job$timeout
    job$cancelled <- isTRUE(job$cancelled) || expired ||
      !isTRUE(tryCatch(job$current(), error = function(e) FALSE))
    status <- if (is.null(job$process)) FALSE else mergen_process_status(job$process)
    if (is.na(status)) {
      job$status_errors <- (job$status_errors %||% 0L) + 1L
      if (job$status_errors < 3L) { keep[[length(keep) + 1L]] <- job; next }
      job$cancelled <- TRUE
    } else job$status_errors <- 0L
    alive <- if (!is.null(job$process) && job$cancelled)
      !mergen_process_stop(job$process) else isTRUE(status)
    if (!is.null(job$process) && alive) {
      keep[[length(keep) + 1L]] <- job
      next
    }
    if (job$cancelled) {
      mergen_cancellable_worker_settle(job, simpleError("Arka plan işi iptal edildi."))
    } else if (!is.null(job$process)) {
      mergen_cancellable_worker_settle(job)
    } else {
      keep[[length(keep) + 1L]] <- job
    }
  }
  keep <- keep[order(vapply(keep, function(job) job$priority, integer(1)))]
  state$jobs <- keep
  running <- sum(vapply(keep, function(job) !is.null(job$process), logical(1)))
  for (job in keep) {
    if (!is.null(job$process) || running >= mergen_cancellable_worker_capacity()) next
    started <- tryCatch({
      job$process <- mergen_cancellable_worker_launch(job$payload)
      job$started <- Sys.time()
      TRUE
    }, error = function(e) { mergen_cancellable_worker_settle(job, e); FALSE })
    if (started) running <- running + 1L
  }
  state$jobs <- Filter(function(job) !isTRUE(job$finished), state$jobs)
  if (length(state$jobs) && !isTRUE(state$scheduled)) {
    state$scheduled <- TRUE
    mergen_cancellable_worker_schedule(mergen_cancellable_worker_tick, delay = 0.1)
  }
  invisible(NULL)
}

mergen_cancellable_worker_launch <- function(payload) {
  callr::r_bg(function(payload) {
    for (pkg in attr(payload, "mergen_packages")) library(pkg, character.only = TRUE)
    fn <- unserialize(payload)
    list2env(as.list(environment(fn), all.names = TRUE), envir = globalenv())
    fn()
  }, args = list(payload = payload), supervise = TRUE,
  stdout = NULL, stderr = NULL, user_profile = FALSE, system_profile = FALSE)
}

mergen_cancellable_worker_promise <- function(payload, current, timeout = 1800, priority = 0L) {
  state <- .MERGEN_CANCELLABLE_WORKERS
  if (is.null(state$jobs)) state$jobs <- list()
  if (length(state$jobs) >= if (priority > 1L) 32L else 34L) {
    return(promises::promise_reject(simpleError("Arka plan iş kuyruğu dolu.")))
  }
  promises::promise(function(resolve, reject) {
    job <- new.env(parent = emptyenv())
    job$payload <- payload
    job$current <- current
    job$process <- NULL
    job$cancelled <- job$finished <- FALSE
    job$created <- Sys.time()
    job$started <- NULL
    job$timeout <- timeout
    job$priority <- as.integer(priority)
    job$resolve <- resolve
    job$reject <- reject
    state$jobs[[length(state$jobs) + 1L]] <- job
    if (!isTRUE(state$scheduled)) {
      state$scheduled <- TRUE
      mergen_cancellable_worker_schedule(mergen_cancellable_worker_tick, delay = 0)
    }
  })
}

mergen_cancellable_worker_schedule <- function(callback, delay) later::later(callback, delay = delay)

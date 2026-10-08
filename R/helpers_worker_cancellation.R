# İptal edilebilir işler ortak future havuzundan bağımsız ve sınırlıdır.
.MERGEN_CANCELLABLE_WORKERS <- new.env(parent = emptyenv())

mergen_process_alive <- function(process) {
  isTRUE(tryCatch(process$is_alive(), error = function(e) TRUE))
}

mergen_process_stop <- function(process) {
  if (!mergen_process_alive(process)) return(TRUE)
  try(process$kill_tree(), silent = TRUE)
  try(process$kill(grace = 0), silent = TRUE)
  !mergen_process_alive(process)
}

# Sonlanması doğrulanamayan süreç ve kira, yeniden deneme boyunca saklanır.
mergen_retire_process <- function(process, release) {
  poll <- function() {
    if (mergen_process_stop(process)) {
      release()
    } else {
      mergen_cancellable_worker_schedule(poll, delay = 0.5)
    }
    invisible(NULL)
  }
  poll()
}

mergen_cancellable_worker_tick <- function() {
  state <- .MERGEN_CANCELLABLE_WORKERS
  state$scheduled <- FALSE
  keep <- list()
  for (job in state$jobs) {
    cancelled <- isTRUE(job$cancelled) || !isTRUE(tryCatch(job$current(), error = function(e) FALSE)) ||
      as.numeric(difftime(Sys.time(), job$created, units = "secs")) > job$timeout
    job$cancelled <- cancelled
    if (!is.null(job$process) && cancelled) mergen_process_stop(job$process)
    if (!is.null(job$process) && mergen_process_alive(job$process)) {
      keep[[length(keep) + 1L]] <- job
      next
    }
    if (cancelled) {
      job$reject(simpleError("Arka plan işi iptal edildi."))
    } else if (!is.null(job$process)) {
      tryCatch(job$resolve(job$process$get_result()), error = job$reject)
    } else {
      keep[[length(keep) + 1L]] <- job
    }
  }
  keep <- keep[order(vapply(keep, function(job) job$priority, integer(1)))]
  state$jobs <- keep
  running <- sum(vapply(keep, function(job) !is.null(job$process), logical(1)))
  for (job in keep) {
    if (!is.null(job$process) || running >= 2L) next
    started <- tryCatch({
      job$process <- mergen_cancellable_worker_launch(job$payload)
      TRUE
    }, error = function(e) { job$reject(e); job$current <- function() FALSE; FALSE })
    if (started) running <- running + 1L
  }
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
  user_profile = FALSE, system_profile = FALSE)
}

mergen_cancellable_worker_promise <- function(payload, current, timeout = 1800, priority = 0L) {
  state <- .MERGEN_CANCELLABLE_WORKERS
  if (is.null(state$jobs)) state$jobs <- list()
  if (length(state$jobs) >= if (priority > 1L) 32L else 34L) stop("Arka plan iş kuyruğu dolu.")
  promises::promise(function(resolve, reject) {
    job <- new.env(parent = emptyenv())
    job$payload <- payload
    job$current <- current
    job$process <- NULL
    job$cancelled <- FALSE
    job$created <- Sys.time()
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

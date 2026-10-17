# İptal edilebilir işler ortak future havuzundan bağımsız ve sınırlıdır.
.MERGEN_CANCELLABLE_WORKERS <- new.env(parent = emptyenv())

# Tanıtıcı sorgulanamazsa PID düzeyine düşülür; o da bilinmiyorsa NA kalır.
mergen_process_status <- function(process) {
  status <- tryCatch(process$is_alive(), error = function(e) NA)
  if (identical(status, TRUE) || identical(status, FALSE)) return(status)
  if (!exists("mergen_pid_status", mode = "function", inherits = TRUE)) return(NA)
  pid <- tryCatch(process$get_pid(), error = function(e) NA_integer_)
  baslangic <- tryCatch(as.numeric(process$get_start_time()), error = function(e) NULL)
  pid_durum <- tryCatch(mergen_pid_status(pid, unname(Sys.info()[["nodename"]]),
    since = baslangic, slack = 2), error = function(e) NA)
  if (identical(pid_durum, TRUE) || identical(pid_durum, FALSE)) pid_durum else NA
}

mergen_process_alive <- function(process) isTRUE(mergen_process_status(process))

# Kök ölse de torunlar yaşayabilir: ağaç her durdurmada temizlenir. Başarı
# yalnızca kök için açık FALSE gözlenince bildirilir.
mergen_process_stop <- function(process) {
  try(process$kill_tree(), silent = TRUE)
  if (identical(mergen_process_status(process), FALSE)) return(TRUE)
  try(process$kill(grace = 0), silent = TRUE)
  identical(mergen_process_status(process), FALSE)
}

# Kaynak yalnız ölüm doğrulanınca bırakılır. Doğrulanamayan süreç karantinaya
# alınır: `on_uncertain` bir kez çağrılır (UI/işlem terminale geçebilir) ama
# kaynak sahibi süreç ölmeden serbest kalmaz; yoklama seyrekleşerek sürer.
mergen_retire_process <- function(process, release, on_uncertain = NULL) {
  released <- FALSE
  uncertain <- FALSE
  attempts <- 0L
  poll <- function() {
    if (released) return(invisible(NULL))
    if (mergen_process_stop(process)) {
      released <<- TRUE
      try(release(), silent = TRUE)
    } else {
      attempts <<- attempts + 1L
      if (attempts >= 3L && !uncertain) {
        uncertain <<- TRUE
        if (is.function(on_uncertain)) try(on_uncertain(), silent = TRUE)
      }
      mergen_cancellable_worker_schedule(poll, delay = min(30, 0.5 * attempts))
    }
    invisible(NULL)
  }
  poll()
}

# Yapılandırılan değer havuzun FİZİKSEL toplam süreç sınırıdır; şeritler onu
# bölüşür, çoğaltmaz. Kalıcı işler (alım, Yolaç hazırlık/çıktı/özet) en fazla
# yarısını kullanır, sohbet tüm boş yuvaları kullanabilir. `lane = NULL` toplamdır.
mergen_cancellable_worker_capacity <- function(lane = NULL) {
  configured <- getOption("mergen.cancellable_workers", NULL)
  if (is.null(configured)) configured <- if (exists("resolve_mergen_worker_count", mode = "function")) resolve_mergen_worker_count() else 2L
  value <- suppressWarnings(as.integer(configured)[1])
  total <- if (length(value) != 1L || is.na(value) || value < 1L) 1L else value
  if (identical(lane, "durable")) max(1L, total %/% 2L) else total
}

# Sözü sonuçlanmamış işler (bekleyen + çalışan) şeridin kuyruk yerini tüketir.
.mergen_cancellable_live_jobs <- function(lane = NULL) {
  Filter(function(job) !isTRUE(job$finished) && (is.null(lane) || identical(job$lane %||% "interactive", lane)),
         .MERGEN_CANCELLABLE_WORKERS$jobs %||% list())
}

# Ölümü kanıtlanmamış her süreç (karantinadaki dahil) fiziksel yuva tutar.
.mergen_cancellable_running <- function(jobs, lane = NULL) {
  sum(vapply(jobs, function(job) !is.null(job$process) &&
    (is.null(lane) || identical(job$lane %||% "interactive", lane)), logical(1)))
}

.mergen_cancellable_has_room <- function(jobs, lane) {
  .mergen_cancellable_running(jobs, lane) < mergen_cancellable_worker_capacity(lane) &&
    .mergen_cancellable_running(jobs) < mergen_cancellable_worker_capacity()
}

.mergen_cancellable_queue_limit <- function(priority) if (priority > 1L) 32L else 34L

# Kuyruk sınırı şerit başınadır: bir şeridin birikmesi diğerini reddetmez.
mergen_cancellable_worker_admissible <- function(lane = "interactive", priority = 0L) {
  jobs <- .MERGEN_CANCELLABLE_WORKERS$jobs %||% list()
  canli <- .mergen_cancellable_live_jobs(lane)
  bekleyen <- Filter(function(job) is.null(job$process), canli)
  length(canli) < .mergen_cancellable_queue_limit(priority) && !length(bekleyen) &&
    .mergen_cancellable_has_room(jobs, lane)
}

# Kullanıcı iptali, yürütme/kuyruk zaman aşımı ve belirsiz süreç ayrı bildirilir.
.MERGEN_CANCELLABLE_END_MESSAGES <- c(
  cancelled = "Arka plan işi iptal edildi.",
  timeout = "TIMEOUT: Arka plan işi zaman aşımına uğradı.",
  queue_timeout = "Arka plan iş kuyruğu yoğun; iş zamanında başlatılamadı.",
  unknown = "Arka plan işinin durumu doğrulanamadı; iş durduruldu.",
  uncertain = "Arka plan işi sonlandırılamadı; süreç karantinada.")

mergen_cancellable_worker_settle <- function(job, error = NULL) {
  if (isTRUE(job$finished)) return(invisible(NULL))
  job$finished <- TRUE
  unwrap <- function(e) {
    for (i in seq_len(16L)) {
      if (!inherits(e, "callr_error") || !inherits(e$parent, "condition")) break
      e <- e$parent
    }
    e
  }
  if (!is.null(error)) try(job$reject(unwrap(error)), silent = TRUE) else
    tryCatch(job$resolve(job$process$get_result()), error = function(e) try(job$reject(unwrap(e)), silent = TRUE))
  invisible(NULL)
}

mergen_cancellable_worker_tick <- function() {
  state <- .MERGEN_CANCELLABLE_WORKERS
  state$scheduled <- FALSE
  keep <- list()
  for (job in state$jobs) {
    # Sonuçlanmış iş yalnız süreci ölümü kanıtlanmadıysa (karantina) izlenir.
    if (isTRUE(job$finished) && !isTRUE(job$quarantined)) next
    if (!is.null(job$next_probe) && Sys.time() < job$next_probe) {
      keep[[length(keep) + 1L]] <- job
      next
    }
    if (!isTRUE(job$cancelled)) {
      reason <- if (!is.null(job$started) &&
                    as.numeric(difftime(Sys.time(), job$started, units = "secs")) > job$timeout) "timeout"
        else if (is.null(job$started) &&
                 as.numeric(difftime(Sys.time(), job$created, units = "secs")) > (job$queue_timeout %||% job$timeout)) "queue_timeout"
        else if (!isTRUE(tryCatch(job$current(), error = function(e) FALSE))) "cancelled"
      if (!is.null(reason)) {
        job$cancelled <- TRUE
        job$end_reason <- reason
      }
    }
    status <- if (is.null(job$process)) FALSE else mergen_process_status(job$process)
    if (is.na(status)) {
      job$status_errors <- (job$status_errors %||% 0L) + 1L
      if (job$status_errors < 3L) { keep[[length(keep) + 1L]] <- job; next }
      if (!isTRUE(job$cancelled)) {
        job$cancelled <- TRUE
        job$end_reason <- "unknown"
      }
    } else job$status_errors <- 0L
    alive <- if (!is.null(job$process) && job$cancelled)
      !mergen_process_stop(job$process) else isTRUE(status)
    if (!is.null(job$process) && alive) {
      if (job$cancelled) job$termination_attempts <- (job$termination_attempts %||% 0L) + 1L
      if (job$status_errors >= 3L || (job$termination_attempts %||% 0L) >= 3L) {
        # Ölümü kanıtlanamayan süreç yuvasını tutar; çağıran bir kez bilgilendirilir.
        if (!isTRUE(job$quarantined)) {
          job$quarantined <- TRUE
          mergen_cancellable_worker_settle(job, simpleError(.MERGEN_CANCELLABLE_END_MESSAGES[["uncertain"]]))
        }
        job$next_probe <- Sys.time() + 5
      }
      keep[[length(keep) + 1L]] <- job
      next
    }
    if (job$cancelled) {
      mergen_cancellable_worker_settle(job, simpleError(.MERGEN_CANCELLABLE_END_MESSAGES[[job$end_reason %||% "cancelled"]]))
    } else if (!is.null(job$process)) {
      mergen_cancellable_worker_settle(job)
    } else {
      keep[[length(keep) + 1L]] <- job
    }
  }
  keep <- keep[order(vapply(keep, function(job) job$priority, integer(1)))]
  state$jobs <- keep
  for (job in keep) {
    if (!is.null(job$process) || isTRUE(job$finished) ||
        !.mergen_cancellable_has_room(keep, job$lane %||% "interactive")) next
    tryCatch({
      job$process <- mergen_cancellable_worker_launch(job$payload)
      job$started <- Sys.time()
      job$payload <- NULL
    }, error = function(e) mergen_cancellable_worker_settle(job, e))
  }
  state$jobs <- Filter(function(job) !isTRUE(job$finished) || isTRUE(job$quarantined), state$jobs)
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

mergen_cancellable_worker_promise <- function(payload, current, timeout = 1800, priority = 0L,
                                              queue_timeout = min(timeout, 300), lane = "interactive") {
  if (!is.finite(timeout) || timeout <= 0 || !is.finite(queue_timeout) || queue_timeout <= 0)
    stop("İşçi son tarihleri sonlu ve pozitif olmalıdır.")
  state <- .MERGEN_CANCELLABLE_WORKERS
  if (is.null(state$jobs)) state$jobs <- list()
  if (length(.mergen_cancellable_live_jobs(lane)) >= .mergen_cancellable_queue_limit(priority)) {
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
    job$queue_timeout <- queue_timeout
    job$priority <- as.integer(priority)
    job$lane <- lane
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

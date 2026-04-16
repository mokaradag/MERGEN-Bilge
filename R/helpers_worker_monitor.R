# ==============================================================================
# Dosya Yolu: R/helpers_worker_monitor.R
# Açıklama: Future tabanlı asenkron işleri izlemek için merkezi işçi/iş defteri.
#           Toplam işçi sayısını cluster'dan alır; aktif işleri uygulama düzeyinde
#           takip ederek sağlık ekranında kullanılabilecek metrikler üretir.
# ==============================================================================

# İşçi izleme defterini başlat
init_worker_monitor <- function() {
  if (!exists(".mergen_worker_monitor", envir = .GlobalEnv, inherits = FALSE)) {
    monitor_env <- new.env(parent = emptyenv())
    monitor_env$tasks <- new.env(parent = emptyenv())
    monitor_env$started_at <- Sys.time()

    assign(".mergen_worker_monitor", monitor_env, envir = .GlobalEnv)
  }

  get(".mergen_worker_monitor", envir = .GlobalEnv)
}

# Tekil görev kimliği üret
create_worker_task_id <- function(task_type = "generic") {
  paste0(
    task_type, "_",
    format(Sys.time(), "%Y%m%d%H%M%OS3"),
    "_",
    sample(1000:9999, 1)
  )
}

# Yeni bir asenkron işi kaydet
register_worker_task <- function(task_id,
                                 task_type = "generic",
                                 session_token = NULL,
                                 meta = list()) {
  monitor_env <- init_worker_monitor()

  monitor_env$tasks[[task_id]] <- list(
    task_id = task_id,
    task_type = task_type,
    session_token = session_token %||% NA_character_,
    status = "running",
    started_at = Sys.time(),
    meta = meta
  )

  invisible(task_id)
}

# Bir işi tamamlandı olarak işaretle ve defterden kaldır
finish_worker_task <- function(task_id) {
  monitor_env <- init_worker_monitor()

  if (exists(task_id, envir = monitor_env$tasks, inherits = FALSE)) {
    rm(list = task_id, envir = monitor_env$tasks)
  }

  invisible(NULL)
}

# Eski veya bozulmuş kayıtları temizle
cleanup_worker_tasks <- function(max_age_secs = 86400) {
  monitor_env <- init_worker_monitor()
  current_time <- Sys.time()
  task_ids <- ls(envir = monitor_env$tasks)

  if (!length(task_ids)) {
    return(invisible(NULL))
  }

  for (task_id in task_ids) {
    item <- tryCatch(monitor_env$tasks[[task_id]], error = function(e) NULL)

    if (is.null(item) || is.null(item$started_at)) {
      try(rm(list = task_id, envir = monitor_env$tasks), silent = TRUE)
      next
    }

    age_secs <- as.numeric(difftime(current_time, item$started_at, units = "secs"))
    if (is.na(age_secs) || age_secs > max_age_secs) {
      try(rm(list = task_id, envir = monitor_env$tasks), silent = TRUE)
    }
  }

  invisible(NULL)
}

# Görev tiplerine göre özet çıkar
summarize_worker_tasks_by_type <- function() {
  monitor_env <- init_worker_monitor()
  cleanup_worker_tasks()

  task_ids <- ls(envir = monitor_env$tasks)
  if (!length(task_ids)) {
    return(list())
  }

  task_types <- vapply(task_ids, function(task_id) {
    item <- tryCatch(monitor_env$tasks[[task_id]], error = function(e) NULL)
    as.character(item$task_type %||% "generic")
  }, character(1))

  counts <- table(task_types)
  as.list(as.integer(counts)) |>
    stats::setNames(names(counts))
}

# Sağlık ekranı için izleme bilgisi üret
get_worker_monitor_info <- function() {
  cleanup_worker_tasks()

  total_workers <- tryCatch({
    as.integer(future::nbrOfWorkers())
  }, error = function(e) {
    NA_integer_
  })

  if (is.na(total_workers) || total_workers < 1) {
    total_workers <- 1L
  }

  monitor_env <- init_worker_monitor()
  task_ids <- ls(envir = monitor_env$tasks)
  active_jobs <- length(task_ids)

  active_workers <- min(active_jobs, total_workers)
  free_workers <- max(total_workers - active_workers, 0L)
  queued_jobs <- max(active_jobs - total_workers, 0L)
  usage_pct <- if (total_workers > 0) round((active_workers / total_workers) * 100, 1) else 0

  list(
    total_workers = total_workers,
    active_jobs = as.integer(active_jobs),
    active_workers = as.integer(active_workers),
    free_workers = as.integer(free_workers),
    queued_jobs = as.integer(queued_jobs),
    usage_pct = usage_pct,
    task_type_breakdown = summarize_worker_tasks_by_type(),
    note = paste(
      "Bu metrikler, uygulamanın future_promise ile başlattığı asenkron işleri izler.",
      "Doğrudan cluster içi düşük seviye worker telemetrisi değil, uygulama düzeyi iş yükü görünümüdür."
    )
  )
}

# Future promise çağrısını izlemeli şekilde sarmala
tracked_future_promise <- function(task_fn,
                                   task_type = "generic",
                                   session_token = NULL,
                                   meta = list(),
                                   globals = NULL) {
  if (!is.function(task_fn)) {
    stop("tracked_future_promise() için 'task_fn' bir fonksiyon olmalıdır.")
  }

  task_id <- create_worker_task_id(task_type = task_type)

  register_worker_task(
    task_id = task_id,
    task_type = task_type,
    session_token = session_token,
    meta = meta
  )

  promise_globals <- globals %||% list()
  promise_globals$task_fn <- task_fn

  p <- tryCatch({
    promises::future_promise(
      {
        task_fn()
      },
      globals = promise_globals
    )
  }, error = function(e) {
    finish_worker_task(task_id)
    stop(e)
  })

  promises::then(
    p,
    onFulfilled = function(value) {
      finish_worker_task(task_id)
      value
    },
    onRejected = function(error) {
      finish_worker_task(task_id)
      stop(error)
    }
  )
}
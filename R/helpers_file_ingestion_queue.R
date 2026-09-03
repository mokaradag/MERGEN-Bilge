# ==============================================================================
# Dosya Yolu: R/helpers_file_ingestion_queue.R
# Açıklama: Dosya alım hattının sınırlı eşzamanlılık (bounded concurrency) ve
#           kuyruk/backpressure katmanı. Süreç kapsamlıdır: her PARTİ tek bir
#           worker görevi olarak çalışır, dosya başına sınırsız future üretilmez.
#           Eşzamanlı parti sayısı sınırlanarak LLM/akış/TTS/STT görevlerinin
#           worker havuzunu tüketmesi engellenir.
#           R/helpers_file_ingestion_worker.R dosyasından sonra source edilir.
# ==============================================================================

.file_ingestion_queue_env <- new.env(parent = emptyenv())

.file_ingestion_state <- function() {
  if (is.null(.file_ingestion_queue_env$active)) {
    .file_ingestion_queue_env$active <- 0L
    .file_ingestion_queue_env$pending <- list()
    .file_ingestion_queue_env$pump_scheduled <- FALSE
    .file_ingestion_queue_env$rejected_total <- 0L
    .file_ingestion_queue_env$completed_total <- 0L
  }

  .file_ingestion_queue_env
}

# Ortam değişkeni + R option ile ayarlanabilen tamsayı yapılandırması.
file_ingestion_int_setting <- function(env_name, option_name, default_value) {
  raw <- Sys.getenv(env_name, "")
  if (!nzchar(raw)) {
    raw <- getOption(option_name, default_value)
  }

  value <- suppressWarnings(as.integer(raw)[1])
  if (is.na(value) || value < 1L) default_value else value
}

file_ingestion_max_concurrent <- function() {
  file_ingestion_int_setting(
    "MERGEN_FILE_INGESTION_MAX_CONCURRENT",
    "mergen.file_ingestion.max_concurrent",
    2L
  )
}

file_ingestion_max_queue <- function() {
  file_ingestion_int_setting(
    "MERGEN_FILE_INGESTION_MAX_QUEUE",
    "mergen.file_ingestion.max_queue",
    32L
  )
}

file_ingestion_metrics_enabled <- function() {
  raw <- Sys.getenv("MERGEN_FILE_INGESTION_METRICS", "")
  if (!nzchar(raw)) {
    return(isTRUE(getOption("mergen.file_ingestion.metrics", FALSE)))
  }

  tolower(raw) %in% c("true", "1", "yes", "on", "evet", "acik")
}

# Worker havuzunda boş kapasite kalmadıysa alım görevi gönderilmez; böylece
# yükleme trafiği sohbet/akış görevlerini aç bırakmaz.
file_ingestion_pool_has_capacity <- function() {
  free <- tryCatch(as.integer(future::nbrOfFreeWorkers()), error = function(e) NA_integer_)
  if (is.na(free)) return(TRUE)
  free > 0L
}

file_ingestion_try_acquire_slot <- function() {
  state <- .file_ingestion_state()
  if (state$active >= file_ingestion_max_concurrent()) return(FALSE)
  if (!file_ingestion_pool_has_capacity()) return(FALSE)

  state$active <- state$active + 1L
  TRUE
}

file_ingestion_release_slot <- function() {
  state <- .file_ingestion_state()
  state$active <- max(state$active - 1L, 0L)
  state$completed_total <- state$completed_total + 1L
  invisible(state$active)
}

# Kuyruk doluysa iş SESSİZCE düşürülmez; çağırana açık bir red bilgisi döner.
file_ingestion_enqueue <- function(job) {
  state <- .file_ingestion_state()

  if (length(state$pending) >= file_ingestion_max_queue()) {
    state$rejected_total <- state$rejected_total + 1L
    return(FALSE)
  }

  state$pending[[length(state$pending) + 1L]] <- job
  TRUE
}

file_ingestion_take_next_job <- function() {
  state <- .file_ingestion_state()
  if (!length(state$pending)) return(NULL)

  job <- state$pending[[1L]]
  state$pending <- state$pending[-1L]
  job
}

# Kapanan oturumun bekleyen işlerini kuyruktan düşürür.
file_ingestion_cancel_session_jobs <- function(session_token) {
  token <- as.character(session_token %||% "")[1]
  if (!nzchar(token)) return(invisible(0L))

  state <- .file_ingestion_state()
  if (!length(state$pending)) return(invisible(0L))

  keep <- vapply(state$pending, function(job) {
    !identical(as.character(job$session_token %||% "")[1], token)
  }, logical(1))

  removed <- sum(!keep)
  state$pending <- state$pending[keep]
  invisible(as.integer(removed))
}

file_ingestion_queue_status <- function() {
  state <- .file_ingestion_state()

  list(
    active_batches = as.integer(state$active),
    queued_batches = as.integer(length(state$pending)),
    max_concurrent = file_ingestion_max_concurrent(),
    max_queue = file_ingestion_max_queue(),
    rejected_total = as.integer(state$rejected_total),
    completed_total = as.integer(state$completed_total)
  )
}

# Kuyruğu boşaltmayı dener. Slot ya da worker kapasitesi yoksa kısa gecikmeli
# tek bir yeniden deneme planlanır; bekleyen iş kalıcı olarak asılı kalmaz.
file_ingestion_pump <- function() {
  state <- .file_ingestion_state()

  while (length(state$pending) > 0L) {
    if (!file_ingestion_try_acquire_slot()) break

    job <- file_ingestion_take_next_job()
    if (is.null(job)) {
      state$active <- max(state$active - 1L, 0L)
      break
    }

    started <- tryCatch({
      job$run(job)
      TRUE
    }, error = function(e) FALSE)

    if (!isTRUE(started)) {
      state$active <- max(state$active - 1L, 0L)
    }
  }

  if (length(state$pending) > 0L && !isTRUE(state$pump_scheduled)) {
    state$pump_scheduled <- TRUE
    tryCatch(
      later::later(function() {
        state$pump_scheduled <- FALSE
        file_ingestion_pump()
      }, delay = 0.5),
      error = function(e) {
        state$pump_scheduled <- FALSE
      }
    )
  }

  invisible(NULL)
}

file_ingestion_reset_state <- function() {
  state <- .file_ingestion_state()
  state$active <- 0L
  state$pending <- list()
  state$pump_scheduled <- FALSE
  state$rejected_total <- 0L
  state$completed_total <- 0L
  invisible(TRUE)
}

# Metrik satırı yalnızca açıkça etkinleştirildiğinde ya da parti gerçekten
# yavaşladığında yazılır. Dosya adı/yolu ve gizli değer içermez.
file_ingestion_log_metrics <- function(line, total_ms = 0) {
  if (!file_ingestion_metrics_enabled() && !(is.finite(total_ms) && total_ms > 5000)) {
    return(invisible(FALSE))
  }

  cat(line, "\n", sep = "")
  invisible(TRUE)
}

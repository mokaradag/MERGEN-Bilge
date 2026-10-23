# ==============================================================================
# Dosya Yolu: R/helpers_file_ingestion_runtime.R
# Açıklama: Dosya alımının ana süreç orkestrasyonu; worker'a yalnız düz görev gider.
# R/helpers_file_ingestion_queue.R dosyasından sonra source edilir.
# ==============================================================================

# Parti gönderimi ve iptal durumunu taşıyan hafif denetleyici.
file_ingestion_create_controller <- function(session = NULL, debug_fn = NULL) {
  controller <- new.env(parent = emptyenv())
  controller$epoch <- 0L
  controller$active <- TRUE
  controller$debug <- debug_fn
  controller$clear_notification <- function(id, uncertain = FALSE) {
    if (!is.null(session)) try(
      if (uncertain) shiny::showNotification("Dosya alımının sonucu henüz doğrulanamadı. İşlem tamamlanana kadar yeniden yüklemeyin.",
        id = id, duration = NULL, type = "warning", session = session) else shiny::removeNotification(id, session = session), silent = TRUE)
  }
  controller$session_token <- tryCatch(as.character(session$token %||% "")[1], error = function(e) "")

  if (!is.null(session) && exists("mergen_session_on_owner_change", mode = "function")) {
    mergen_session_on_owner_change(session, function(...) file_ingestion_cancel_controller(controller))
  }

  # Tarayıcı kapanışı kabul edilmiş işi iptal etmez; yalnız UI geri çağrıları susar.
  if (!is.null(session) && is.function(session$onSessionEnded)) {
    try(session$onSessionEnded(function() {
      controller$active <- FALSE
    }), silent = TRUE)
  }

  controller
}

# Oturum başına tek denetleyici.
file_ingestion_session_controller <- function(session) {
  if (is.null(session) || !is.environment(session$userData)) {
    return(file_ingestion_create_controller(session))
  }

  mevcut <- session$userData$file_ingestion_controller
  if (is.environment(mevcut)) return(mevcut)

  controller <- file_ingestion_create_controller(session)
  session$userData$file_ingestion_controller <- controller
  controller
}

# Devam eden partilerin ana süreç tarafını geçersiz kılar.
file_ingestion_cancel_controller <- function(controller) {
  if (is.null(controller)) return(invisible(FALSE))
  controller$epoch <- controller$epoch + 1L
  file_ingestion_drop_controller_jobs(controller)
  invisible(TRUE)
}

# Yalnız bu denetleyicinin bekleyen işleri kuyruktan düşürür.
file_ingestion_drop_controller_jobs <- function(controller) {
  state <- .file_ingestion_state()
  if (!length(state$pending)) return(invisible(0L))
  dropped <- vapply(state$pending, function(job) identical(job$controller, controller), logical(1))
  removed <- state$pending[dropped]
  state$pending <- state$pending[!dropped]
  for (job in removed) {
    if (is.environment(job$lease)) job$lease$slot_acquired <- FALSE
    file_ingestion_release_job(job)
    if (is.function(job$on_failure)) try(job$on_failure("Dosya alımı iptal edildi.", list()), silent = TRUE)
  }
  invisible(as.integer(length(removed)))
}

file_ingestion_controller_debug <- function(controller, tag, message) {
  if (is.null(controller) || !is.function(controller$debug)) return(invisible(FALSE))
  try(controller$debug(tag, message), silent = TRUE)
  invisible(TRUE)
}

# Kuyruktan çıkan işi gerçek worker görevine dönüştürür.
file_ingestion_run_job <- function(job) {
  if (is.environment(job$lease)) job$lease$released <- FALSE
  if (is.environment(job$lease)) job$lease$slot_acquired <- TRUE
  gorevler <- job$tasks
  bekleme_ms <- as.numeric(difftime(Sys.time(), job$queued_at, units = "secs")) * 1000

  journals <- vapply(gorevler, function(task) tempfile("ingest_result_", fileext = ".rds"), character(1))
  gorevler <- Map(function(task, journal) {
    task$result_journal <- journal
    task$transaction <- list(id = basename(journal), journal = journal)
    task
  }, gorevler, journals)
  worker_globals <- file_ingestion_worker_globals()
  worker_globals$tasks <- gorevler

  promise <- tracked_future_promise(
    task_fn = function() file_ingestion_execute_batch(tasks),
    task_type = "file_ingestion",
    on_uncertain = function(error) file_ingestion_fail_job(job, error, uncertain = TRUE),
    cancel_check = function() identical(job$controller$epoch, job$epoch),
    session_token = job$session_token,
    meta = list(batch_id = job$id, files = length(gorevler)),
    dependency_mode = "explicit",
    globals = worker_globals,
    packages = c("fs", "digest")
  )

  promises::then(
    promise,
    # Günlük commit ya da geri alım kalıcılaşana dek yaşar.
    onFulfilled = function(results) {
      file_ingestion_finish_job(job, results, bekleme_ms, journals = journals)
    },
    onRejected = function(error) {
      results <- lapply(journals, function(path) suppressWarnings(tryCatch(readRDS(path), error = function(e) NULL)))
      file_ingestion_rollback_job(job, Filter(Negate(is.null), results), error, journals)
    }
  )

  invisible(TRUE)
}

# Yalnız korunan tamamlanma üstverisini ana süreçte uygular.
file_ingestion_apply_commit <- function(job, results, index_result, queue_wait_ms = 0) {
  released <- FALSE
  on.exit({
    if (!released) file_ingestion_release_job(job)
    try(file_ingestion_pump(), silent = TRUE)
  }, add = TRUE)
  if (!is.null(index_result$accepted) || !is.null(index_result$committed)) {
    position <- 0L
    results <- lapply(results, function(r) {
      if (!isTRUE(r$ok)) return(r)
      position <<- position + 1L
      accepted <- if (!is.null(index_result$accepted)) isTRUE(index_result$accepted[[position]]) else
        is.null(r$artifact_id) || isTRUE(r$artifact_id %in% index_result$committed)
      if (!accepted) {
        r$ok <- FALSE
        r$code <- "index_declined"
        r$error <- "Dosya indekse kaydedilmedi; aynı adlı yükleme veya sahiplik çakışması oluştu."
      }
      r
    })
  }
  if (is.environment(job$lease)) job$lease$committed_sources <- vapply(results,
    function(r) if (isTRUE(r$ok)) r$source_path %||% "" else "", character(1))
  file_ingestion_release_job(job)
  released <- TRUE
  controller <- job$controller
  commit_started <- Sys.time()

  ozet <- file_ingestion_summarize_results(results)

  if (isTRUE(controller$active) && identical(controller$epoch, job$epoch) &&
      is.function(job$on_complete)) {
    try(job$on_complete(results, list(
      batch_id = job$id,
      indexed = index_result$indexed,
      summary = ozet
    )), silent = FALSE)
  } else if (isTRUE(controller$active) && !identical(controller$epoch, job$epoch)) {
    # Commit kalıcıdır; eski UI yalnız ilerleme bildirimini kapatır.
    controller$clear_notification(job$id)
  }

  durum <- file_ingestion_queue_status()
  commit_ms <- as.numeric(difftime(Sys.time(), commit_started, units = "secs")) * 1000

  file_ingestion_log_metrics(
    file_ingestion_metrics_line(
      batch_id = job$id,
      summary = ozet,
      queue_wait_ms = queue_wait_ms,
      commit_ms = commit_ms,
      index_ms = index_result$ms,
      queued_batches = durum$queued_batches,
      active_batches = durum$active_batches
    ),
    total_ms = ozet$total_ms + queue_wait_ms
  )

  invisible(NULL)
}

# Worker görevinin tamamen başarısız olduğu dal.
file_ingestion_fail_job <- function(job, error, uncertain = FALSE) {
  notify <- !isTRUE(job$lease$uncertain_notified)
  if (uncertain) job$lease$uncertain_notified <- TRUE else file_ingestion_release_job(job)
  on.exit(if (!uncertain) try(file_ingestion_pump(), silent = TRUE), add = TRUE)
  controller <- job$controller
  mesaj <- tryCatch(conditionMessage(error), error = function(e) "bilinmeyen hata")
  file_ingestion_controller_debug(controller, "ingest_error", sprintf("batch=%s worker hatasi: %s", job$id, mesaj))

  if (uncertain && notify && isTRUE(controller$active))
    controller$clear_notification(job$id, uncertain = identical(controller$epoch, job$epoch))
  if (!uncertain && isTRUE(controller$active) && is.function(job$on_failure)) {
    current <- identical(controller$epoch, job$epoch)
    try(job$on_failure(if (current) mesaj else "Dosya alımı iptal edildi.", if (current) job$tasks else list()), silent = TRUE)
  }

  invisible(NULL)
}

# Partiyi kuyruğa alır ve kapasite varsa hemen başlatır.
file_ingestion_submit_batch <- function(controller,
                                        tasks,
                                        user_id,
                                        on_complete = NULL,
                                        on_failure = NULL,
                                        batch_id = NULL) {
  tasks <- tasks %||% list()
  batch_id <- batch_id %||% file_ingestion_new_batch_id("ingest")

  if (!length(tasks)) {
    return(list(status = "empty", batch_id = batch_id, queued = 0L))
  }

  if (mergen_cancellable_worker_capacity("durable") == 0L)
    return(list(status = "rejected", batch_id = batch_id, queued = 0L))

  lease <- new.env(parent = emptyenv())
  lease$released <- FALSE
  lease$slot_acquired <- FALSE
  job <- list(
    lease = lease,
    id = batch_id,
    tasks = tasks,
    user_id = as.character(user_id %||% "")[1],
    controller = controller,
    epoch = controller$epoch,
    session_token = controller$session_token,
    on_complete = on_complete,
    on_failure = on_failure,
    queued_at = Sys.time(),
    run = file_ingestion_run_job
  )

  job <- file_ingestion_bind_sources(job)

  if (file_ingestion_try_acquire_slot()) {
    basladi <- tryCatch({
      lease$slot_acquired <- TRUE
      file_ingestion_run_job(job)
      TRUE
    }, error = function(e) {
      file_ingestion_release_job(job)
      file_ingestion_controller_debug(controller, "ingest_dispatch_error", conditionMessage(e))
      FALSE
    })

    if (isTRUE(basladi)) {
      return(list(status = "started", batch_id = batch_id, queued = 0L))
    }
    return(list(status = "rejected", batch_id = batch_id, queued = 0L))
  }

  if (!file_ingestion_enqueue(job)) {
    file_ingestion_release_job(job)
    return(list(status = "rejected", batch_id = batch_id, queued = 0L))
  }

  file_ingestion_pump()
  list(
    status = "queued",
    batch_id = batch_id,
    queued = file_ingestion_queue_status()$queued_batches
  )
}

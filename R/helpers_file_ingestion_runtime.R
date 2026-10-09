# ==============================================================================
# Dosya Yolu: R/helpers_file_ingestion_runtime.R
# Açıklama: Dosya alım hattının ANA SÜREÇ orkestrasyonu. Parti gönderimi,
#           oturum/iptal koruması, kalıcı indeks yazımı (tek toplu mutasyon) ve
#           tamamlanma geri çağrısı burada yaşar. Worker'a canlı Shiny oturumu
#           veya reaktif değer taşınmaz; yalnızca düz görev listeleri gider.
#           R/helpers_file_ingestion_queue.R dosyasından sonra source edilir.
# ==============================================================================

# Parti gönderimi ve iptal durumunu taşıyan hafif denetleyici.
file_ingestion_create_controller <- function(session = NULL, debug_fn = NULL) {
  controller <- new.env(parent = emptyenv())
  controller$epoch <- 0L
  controller$active <- TRUE
  controller$debug <- debug_fn
  controller$session_token <- tryCatch(as.character(session$token %||% "")[1], error = function(e) "")

  if (!is.null(session) && exists("mergen_session_on_owner_change", mode = "function")) {
    mergen_session_on_owner_change(session, function(...) file_ingestion_cancel_controller(controller))
  }

  if (!is.null(session) && is.function(session$onSessionEnded)) {
    try(session$onSessionEnded(function() {
      controller$active <- FALSE
      file_ingestion_cancel_controller(controller)
    }), silent = TRUE)
  }

  controller
}

# Oturum başına tek denetleyici; Ana Söyleşi ve diğer yükleme girişleri aynı
# oturum/iptal korumasını paylaşır.
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

# Devam eden partilerin ana süreç tarafını geçersiz kılar (örn. "Tümünü Temizle").
# Uçuştaki partinin kopyaladığı dosyalar temizlenir, indekse yazılmaz.
file_ingestion_cancel_controller <- function(controller) {
  if (is.null(controller)) return(invisible(FALSE))
  controller$epoch <- controller$epoch + 1L
  file_ingestion_cancel_session_jobs(controller$session_token)
  invisible(TRUE)
}

file_ingestion_controller_debug <- function(controller, tag, message) {
  if (is.null(controller) || !is.function(controller$debug)) return(invisible(FALSE))
  try(controller$debug(tag, message), silent = TRUE)
  invisible(TRUE)
}

# Kuyruktan çıkan işi gerçek worker görevine dönüştürür. Bu fonksiyon yalnızca
# ana süreçte çalışır; worker'a düz görev listesi ve önbelleğe alınmış global
# paketi taşınır.
file_ingestion_run_job <- function(job) {
  if (is.environment(job$lease)) job$lease$released <- FALSE
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
    cancel_check = function() isTRUE(job$controller$active) && identical(job$controller$epoch, job$epoch),
    session_token = job$session_token,
    meta = list(batch_id = job$id, files = length(gorevler)),
    dependency_mode = "explicit",
    globals = worker_globals,
    packages = c("fs", "digest")
  )

  promises::then(
    promise,
    onFulfilled = function(results) {
      unlink(journals, force = TRUE)
      file_ingestion_finish_job(job, results, bekleme_ms)
    },
    onRejected = function(error) {
      results <- lapply(journals, function(path) suppressWarnings(tryCatch(readRDS(path), error = function(e) NULL)))
      unlink(journals, force = TRUE)
      file_ingestion_rollback_job(job, Filter(Negate(is.null), results), error)
    }
  )

  invisible(TRUE)
}

# Yalnızca korunan tamamlanma üstverisi ana süreçte uygulanır.
file_ingestion_apply_commit <- function(job, results, index_result, queue_wait_ms = 0) {
  file_ingestion_release_job(job)
  on.exit(try(file_ingestion_pump(), silent = TRUE), add = TRUE)
  if (!is.null(index_result$committed)) {
    results <- lapply(results, function(r) {
      if (isTRUE(r$ok) && !is.null(r$artifact_id) && !isTRUE(r$artifact_id %in% index_result$committed)) {
        r$ok <- FALSE
        r$code <- "dest_missing"
        r$error <- "Kopyalanan dosya artık mevcut değil."
      }
      r
    })
  }
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

# Worker görevinin tamamen başarısız olduğu dal (dispatch/serialization hatası).
file_ingestion_fail_job <- function(job, error) {
  file_ingestion_release_job(job)
  on.exit(try(file_ingestion_pump(), silent = TRUE), add = TRUE)
  controller <- job$controller
  mesaj <- tryCatch(conditionMessage(error), error = function(e) "bilinmeyen hata")

  file_ingestion_controller_debug(controller, "ingest_error", sprintf(
    "batch=%s worker hatasi: %s", job$id, mesaj
  ))

  if (isTRUE(controller$active) && identical(controller$epoch, job$epoch) &&
      is.function(job$on_failure)) {
    try(job$on_failure(mesaj, job$tasks), silent = TRUE)
  }

  invisible(NULL)
}

# Partiyi kuyruğa alır ve kapasite varsa hemen başlatır. Ana süreçte yalnızca
# düz liste hazırlığı yapıldığı için olay döngüsü bloklanmaz.
# Dönüş: list(status = "started"|"queued"|"rejected"|"empty", batch_id = ...)
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

  lease <- new.env(parent = emptyenv())
  lease$released <- FALSE
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

  if (file_ingestion_try_acquire_slot()) {
    basladi <- tryCatch({
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
  }

  if (!file_ingestion_enqueue(job)) {
    return(list(status = "rejected", batch_id = batch_id, queued = 0L))
  }

  file_ingestion_pump()
  list(
    status = "queued",
    batch_id = batch_id,
    queued = file_ingestion_queue_status()$queued_batches
  )
}

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

  if (!is.null(session) && is.function(session$onSessionEnded)) {
    try(session$onSessionEnded(function() {
      controller$active <- FALSE
      file_ingestion_cancel_session_jobs(controller$session_token)
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

# Başarıyla kopyalanan dosyaları TEK indeks mutasyonunda kaydeder. Dosya başına
# ayrı kilit/indeks yazımı yapılmaz; kilit tutma süresi parti başına sabittir.
file_ingestion_commit_index <- function(results, user_id) {
  succeeded <- Filter(function(r) isTRUE(r$ok), results %||% list())
  if (!length(succeeded)) return(list(indexed = character(), ms = 0))

  entries <- lapply(succeeded, function(r) list(path = r$dest, display = r$name))

  started <- Sys.time()
  indexed <- tryCatch(
    mergen_index_persisted_files(entries, user_id = user_id),
    error = function(e) {
      log_warn("[FILE INGEST] Indeks yazimi basarisiz: {conditionMessage(e)}")
      character()
    }
  )

  list(
    indexed = indexed,
    ms = as.numeric(difftime(Sys.time(), started, units = "secs")) * 1000
  )
}

# İptal edilen partinin kopyaladığı hedefleri temizler.
file_ingestion_discard_results <- function(results) {
  for (r in results %||% list()) {
    if (isTRUE(r$ok)) file_ingestion_discard_dest(r$dest, r$source_path)
  }
  invisible(TRUE)
}

# Kuyruktan çıkan işi gerçek worker görevine dönüştürür. Bu fonksiyon yalnızca
# ana süreçte çalışır; worker'a düz görev listesi ve önbelleğe alınmış global
# paketi taşınır.
file_ingestion_run_job <- function(job) {
  gorevler <- job$tasks
  bekleme_ms <- as.numeric(difftime(Sys.time(), job$queued_at, units = "secs")) * 1000

  worker_globals <- file_ingestion_worker_globals()
  worker_globals$tasks <- gorevler

  promise <- tracked_future_promise(
    task_fn = function() file_ingestion_execute_batch(tasks),
    task_type = "file_ingestion",
    session_token = job$session_token,
    meta = list(batch_id = job$id, files = length(gorevler)),
    dependency_mode = "explicit",
    globals = worker_globals,
    packages = c("fs", "digest")
  )

  promises::then(
    promise,
    onFulfilled = function(results) file_ingestion_finish_job(job, results, bekleme_ms),
    onRejected = function(error) file_ingestion_fail_job(job, error)
  )

  invisible(TRUE)
}

# Worker tamamlandığında ana süreçte çalışır: indeks yazımı + UI geri çağrısı.
file_ingestion_finish_job <- function(job, results, queue_wait_ms = 0) {
  file_ingestion_release_slot()
  controller <- job$controller
  commit_started <- Sys.time()

  iptal_edildi <- !identical(controller$epoch, job$epoch)

  if (iptal_edildi) {
    file_ingestion_discard_results(results)
    file_ingestion_controller_debug(controller, "ingest_cancelled", sprintf(
      "batch=%s iptal edildigi icin kopyalar temizlendi", job$id
    ))
    file_ingestion_pump()
    return(invisible(NULL))
  }

  index_result <- file_ingestion_commit_index(results, job$user_id)
  ozet <- file_ingestion_summarize_results(results)

  if (isTRUE(controller$active) && is.function(job$on_complete)) {
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

  file_ingestion_pump()
  invisible(NULL)
}

# Worker görevinin tamamen başarısız olduğu dal (dispatch/serialization hatası).
file_ingestion_fail_job <- function(job, error) {
  file_ingestion_release_slot()
  controller <- job$controller
  mesaj <- tryCatch(conditionMessage(error), error = function(e) "bilinmeyen hata")

  file_ingestion_controller_debug(controller, "ingest_error", sprintf(
    "batch=%s worker hatasi: %s", job$id, mesaj
  ))

  if (isTRUE(controller$active) && identical(controller$epoch, job$epoch) &&
      is.function(job$on_failure)) {
    try(job$on_failure(mesaj, job$tasks), silent = FALSE)
  }

  file_ingestion_pump()
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

  job <- list(
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
      file_ingestion_release_slot()
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

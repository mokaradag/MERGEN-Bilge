# Dosya alımının kilit bekleme ve indeks yazımı işçi sınırı.

# Başarıyla kopyalanan dosyaları TEK indeks mutasyonunda kaydeder. Dosya başına
# ayrı kilit/indeks yazımı yapılmaz; kilit tutma süresi parti başına sabittir.
file_ingestion_commit_index <- function(results, user_id) {
  succeeded <- Filter(function(r) isTRUE(r$ok), results %||% list())
  if (!length(succeeded)) return(list(indexed = character(), ms = 0))

  entries <- lapply(succeeded, function(r) list(path = r$dest, display = r$name))

  started <- Sys.time()
  indexed <- mergen_index_persisted_files(entries, user_id = user_id)

  list(
    indexed = indexed,
    ms = as.numeric(difftime(Sys.time(), started, units = "secs")) * 1000
  )
}

# İptal edilen partinin kopyaladığı hedefleri temizler.
file_ingestion_discard_results <- function(results, user_id = NULL) {
  on.exit({
    for (r in results %||% list()) {
      if (isTRUE(r$ok)) file_ingestion_discard_dest(r$dest, r$source_path)
    }
  }, add = TRUE)
  if (!is.null(user_id)) {
    .file_store_mutate_index(function(idx) {
      uid <- as.character(user_id)
      for (r in results %||% list()) {
        if (!isTRUE(r$ok)) next
        entry <- .file_store_index_entry(r$dest, r$name)
        key <- entry$key
        if (identical(idx[[uid]][[key]]$path, entry$path)) idx[[uid]][[key]] <- NULL
      }
      idx
    })
  }
  invisible(TRUE)
}


file_ingestion_finish_job <- function(job, results, queue_wait_ms = 0, discard = FALSE) {
  discard <- isTRUE(discard) || !identical(job$controller$epoch, job$epoch)
  tryCatch({
    globals <- file_ingestion_worker_globals()
    globals$results <- results
    globals$user_id <- job$user_id
    globals$discard <- discard
    globals$index_options <- options()[intersect(names(options()),
      c("mergen.mcp_base_dir", "mergen.index_path", "mergen.files_root"))]
    tracked_future_promise(
      task_fn = function() {
        old_options <- options(index_options)
        on.exit(options(old_options), add = TRUE)
        if (discard) {
          file_ingestion_discard_results(results, user_id)
          return(NULL)
        }
        tryCatch(file_ingestion_commit_index(results, user_id), error = function(e) {
          try(file_ingestion_discard_results(results, user_id), silent = TRUE)
          stop(e)
        })
      },
      task_type = "file_ingestion_index",
      session_token = job$session_token,
      dependency_mode = "explicit",
      globals = globals,
      packages = c("fs", "digest", "jsonlite")
    ) |>
      promises::then(function(index_result) {
        if (!discard && !identical(job$controller$epoch, job$epoch)) {
          file_ingestion_finish_job(job, results, queue_wait_ms, discard = TRUE)
        } else if (discard) {
          file_ingestion_release_slot()
          file_ingestion_pump()
        } else {
          file_ingestion_apply_commit(job, results, index_result, queue_wait_ms)
        }
        NULL
      }) |>
      promises::catch(function(error) {
        file_ingestion_rollback_job(job, results, error)
        NULL
      })
  }, error = function(error) file_ingestion_rollback_job(job, results, error))
  invisible(NULL)
}

# Havuz arızasında geri alma bağımsız işçide yürür; indeks kilidi UI'ı tutmaz.
file_ingestion_rollback_job <- function(job, results, error) {
  task_id <- NULL
  tryCatch({
    globals <- file_ingestion_worker_globals()
    globals$results <- results
    globals$user_id <- job$user_id
    globals$index_options <- options()[intersect(names(options()),
      c("mergen.mcp_base_dir", "mergen.index_path", "mergen.files_root"))]
    task <- function() {
      options(index_options)
      file_ingestion_discard_results(results, user_id)
    }
    task_id <- create_worker_task_id("file_ingestion_rollback")
    register_worker_task(task_id, "file_ingestion_rollback", job$session_token)
    payload <- worker_monitor_serialize_explicit_task(task, globals, c("fs", "digest", "jsonlite"))
    process <- callr::r_bg(function(payload) {
      fn <- unserialize(payload)
      list2env(as.list(environment(fn), all.names = TRUE), envir = globalenv())
      assign(".FILE_STORE_LOCK_STATE", new.env(parent = emptyenv()), envir = globalenv())
      fn()
    },
      args = list(payload = payload), supervise = FALSE, user_profile = FALSE, system_profile = FALSE)
    poll <- function() {
      if (isTRUE(process$is_alive())) {
        later::later(poll, delay = 0.1)
        return(invisible(NULL))
      }
      cleanup_error <- tryCatch({ process$get_result(); NULL }, error = function(e) e)
      if (!is.null(cleanup_error)) {
        log_warn(paste("[FILE INGEST] Geri alma işçisi başarısız:", conditionMessage(cleanup_error)))
      }
      finish_worker_task(task_id)
      file_ingestion_fail_job(job, error)
    }
    later::later(poll, delay = 0.1)
  }, error = function(cleanup_error) {
    if (!is.null(task_id)) finish_worker_task(task_id)
    file_ingestion_fail_job(job, cleanup_error)
  })
  invisible(NULL)
}

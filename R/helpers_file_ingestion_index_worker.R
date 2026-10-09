# Dosya alımının kilit bekleme ve indeks yazımı işçi sınırı.

# Başarıyla kopyalanan dosyaları TEK indeks mutasyonunda kaydeder. Dosya başına
# ayrı kilit/indeks yazımı yapılmaz; kilit tutma süresi parti başına sabittir.
file_ingestion_commit_index <- function(results, user_id) {
  succeeded <- Filter(function(r) isTRUE(r$ok), results %||% list())
  if (!length(succeeded)) return(list(indexed = character(), ms = 0))

  entries <- lapply(succeeded, function(r) list(path = r$dest, display = r$name,
                                               artifact_id = r$artifact_id))
  started <- Sys.time()
  indexed <- mergen_index_persisted_files(entries, user_id = user_id)
  committed <- attr(indexed, "artifact_ids")

  list(
    indexed = indexed,
    committed = committed,
    ms = as.numeric(difftime(Sys.time(), started, units = "secs")) * 1000
  )
}

# İptal edilen partinin kopyaladığı hedefleri temizler.
file_ingestion_discard_results <- function(results, user_id = NULL, lock_timeout_sec = 5) {
  .file_store_with_index_lock({
    idx <- .load_index()
    owned <- Filter(file_ingestion_artifact_owned, results %||% list())
    uid <- if (is.null(user_id)) NULL else as.character(user_id)
    for (r in owned) {
      entry <- .file_store_index_entry(r$dest, r$name)
      node <- if (is.null(uid)) idx[[entry$key]] else idx[[uid]][[entry$key]]
      node_path <- if (is.list(node)) node$path else node
      node_id <- if (is.list(node)) node$artifact_id else NULL
      if (identical(node_path, entry$path) && (is.null(node_id) || identical(node_id, r$artifact_id))) {
        if (is.null(uid)) idx[[entry$key]] <- NULL else idx[[uid]][[entry$key]] <- NULL
      }
    }
    .save_index(idx)
    for (r in owned) {
      if (!file_ingestion_artifact_owned(r)) next
      file_ingestion_discard_dest(r$dest, r$source_path)
      if (isTRUE(r$transaction_pending)) file_ingestion_discard_dest(r$staging, r$source_path)
      if (file.exists(r$dest) || (!is.null(r$staging) && file.exists(r$staging)))
        stop("Sahip olunan kopya silinemedi.")
      if (!file.exists(r$dest) && (is.null(r$staging) || !file.exists(r$staging)))
        unlink(c(file_ingestion_owner_path(r$dest), paste0(file_ingestion_owner_path(r$dest), ".identity")), force = TRUE)
    }
  }, timeout_sec = lock_timeout_sec, require_lock = TRUE)
  for (r in results %||% list()) {
    if (identical(r$code, "claim_failed") && !is.null(r$identity))
      file_ingestion_discard_unclaimed(r$dest, r$source_path, r$identity)
  }
  invisible(TRUE)
}



file_ingestion_finish_job <- function(job, results, queue_wait_ms = 0, discard = FALSE) {
  discard <- isTRUE(discard) || !isTRUE(job$controller$active) ||
    !identical(job$controller$epoch, job$epoch)
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
        tryCatch({
          failed <- Filter(function(r) !isTRUE(r$ok), results)
          if (length(failed)) file_ingestion_discard_results(failed, user_id)
          file_ingestion_commit_index(results, user_id)
        }, error = function(e) {
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
      promises::then(
        onFulfilled = function(index_result) {
          tryCatch({
            if (!discard && (!isTRUE(job$controller$active) ||
                             !identical(job$controller$epoch, job$epoch))) {
              file_ingestion_finish_job(job, results, queue_wait_ms, discard = TRUE)
            } else if (discard) {
              file_ingestion_release_job(job)
              file_ingestion_pump()
            } else {
              file_ingestion_apply_commit(job, results, index_result, queue_wait_ms)
            }
          }, error = function(e) log_warn(paste("[FILE INGEST] Commit sonrası hata:", conditionMessage(e))))
          NULL
        },
        onRejected = function(error) {
          file_ingestion_rollback_job(job, results, error)
          NULL
        })
  }, error = function(error) file_ingestion_rollback_job(job, results, error))
  invisible(NULL)
}

# Havuz arızasında geri alma bağımsız işçide yürür; indeks kilidi UI'ı tutmaz.
file_ingestion_rollback_job <- function(job, results, error) {
  if (is.environment(job$lease) && isTRUE(job$lease$released)) return(invisible(NULL))
  attempt <- 0L
  terminal <- FALSE
  task_id <- create_worker_task_id("file_ingestion_rollback")
  registered <- FALSE
  finish <- function(failure) {
    if (terminal) return(invisible(NULL))
    terminal <<- TRUE
    try(finish_worker_task(task_id), silent = TRUE)
    file_ingestion_fail_job(job, failure)
    invisible(NULL)
  }
  launch <- function() {
    attempt <<- attempt + 1L
    process <- NULL
    failure <- tryCatch({
      globals <- file_ingestion_worker_globals()
      globals$results <- results
      globals$user_id <- job$user_id
      globals$index_options <- options()[intersect(names(options()),
        c("mergen.mcp_base_dir", "mergen.index_path", "mergen.files_root"))]
      task <- function() {
        options(index_options)
        file_ingestion_discard_results(results, user_id)
      }
      if (!registered) {
        register_worker_task(task_id, "file_ingestion_rollback", job$session_token,
                             execution_pool = "callr_cleanup")
        registered <<- TRUE
      }
      payload <- tryCatch(worker_monitor_serialize_explicit_task(task, globals, c("fs", "digest", "jsonlite")),
        error = function(e) {
          environment(task) <- list2env(globals, parent = baseenv())
          serialize(task, NULL)
        })
      process <- callr::r_bg(function(payload) {
        fn <- unserialize(payload)
        list2env(as.list(environment(fn), all.names = TRUE), envir = globalenv())
        assign(".FILE_STORE_LOCK_STATE", new.env(parent = emptyenv()), envir = globalenv())
        fn()
      }, args = list(payload = payload), stdout = NULL, stderr = NULL,
      supervise = FALSE, user_profile = FALSE, system_profile = FALSE)
      NULL
    }, error = identity)
    retry <- function(failure) {
      if (attempt < 3L) later::later(launch, delay = 0.25 * attempt) else finish(failure)
      invisible(NULL)
    }
    if (!is.null(failure)) return(retry(failure))
    started <- Sys.time()
    status_errors <- 0L
    poll <- function() {
      alive <- tryCatch(isTRUE(process$is_alive()), error = function(e) NA)
      if (is.na(alive)) status_errors <<- status_errors + 1L else status_errors <<- 0L
      expired <- as.numeric(difftime(Sys.time(), started, units = "secs")) > 30
      if (status_errors >= 3L || expired) {
        try(process$kill_tree(), silent = TRUE)
        try(process$kill(grace = 0), silent = TRUE)
        return(retry(simpleError("Geri alma işçisi sonlandırıldı.")))
      }
      if (is.na(alive) || alive) {
        later::later(poll, delay = 0.1)
        return(invisible(NULL))
      }
      failure <- tryCatch({ process$get_result(); NULL }, error = identity)
      if (!is.null(failure)) return(retry(failure))
      finish(error)
    }
    later::later(poll, delay = 0.1)
  }
  launch()
  invisible(NULL)
}

file_ingestion_release_job <- function(job) {
  if (is.environment(job$lease)) {
    if (isTRUE(job$lease$released)) return(invisible(FALSE))
    job$lease$released <- TRUE
  }
  file_ingestion_release_slot()
  invisible(TRUE)
}

# Dosya alımının kilit bekleme ve indeks yazımı işçi sınırı.

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
file_ingestion_discard_results <- function(results, user_id = NULL) {
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
  for (r in results %||% list()) {
    if (isTRUE(r$ok)) file_ingestion_discard_dest(r$dest, r$source_path)
  }
  invisible(TRUE)
}


file_ingestion_finish_job <- function(job, results, queue_wait_ms = 0, discard = FALSE) {
  discard <- isTRUE(discard) || !identical(job$controller$epoch, job$epoch)
  globals <- file_ingestion_worker_globals()
  globals$results <- results
  globals$user_id <- job$user_id
  globals$discard <- discard
  globals$index_options <- options()[intersect(names(options()),
    c("mergen.mcp_base_dir", "mergen.index_path", "mergen.files_root"))]
  tryCatch({
    tracked_future_promise(
      task_fn = function() {
        old_options <- options(index_options)
        on.exit(options(old_options), add = TRUE)
        if (discard) {
          file_ingestion_discard_results(results, user_id)
          return(NULL)
        }
        file_ingestion_commit_index(results, user_id)
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
        file_ingestion_fail_job(job, error)
        NULL
      })
  }, error = function(error) file_ingestion_fail_job(job, error))
  invisible(NULL)
}

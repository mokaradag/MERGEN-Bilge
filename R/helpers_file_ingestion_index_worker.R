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

# İptal edilen partinin kopyaladığı hedefleri temizler. COMMIT TEK YÖNLÜDÜR:
# indekste bu yapıtla eşleşen kayıt kalıcı başarıdır ve hiçbir geç temizlik
# (geri alma, reddedilen kardeş, oturum kapanışı) onu silmez.
file_ingestion_discard_results <- function(results, user_id = NULL, lock_timeout_sec = 5) {
  owned <- Filter(function(r) file_ingestion_artifact_owned(r, allow_deleting = TRUE), results %||% list())
  pending <- Filter(function(r) {
    owner <- file_ingestion_read_owner(r$dest)
    isTRUE(r$transaction_pending) && identical(owner$id, r$artifact_id) &&
      identical(owner$staging, r$staging) && identical(owner$state, "copying")
  }, results %||% list())
  committed <- character()
  .file_store_with_index_lock({
    idx <- .load_index()
    uid <- if (is.null(user_id)) NULL else as.character(user_id)
    for (r in owned) {
      owner <- file_ingestion_read_owner(r$dest)
      if (!identical(owner$id, r$artifact_id)) next
      entry <- .file_store_index_entry(r$dest, r$name)
      node <- if (is.null(uid)) idx[[entry$key]] else idx[[uid]][[entry$key]]
      node_path <- if (is.list(node)) node$path else node
      node_id <- if (is.list(node)) node$artifact_id else NULL
      if (identical(node_path, entry$path) && (is.null(node_id) || identical(node_id, r$artifact_id))) {
        committed <- c(committed, r$artifact_id)
        next
      }
      owner$state <- "deleting"
      owner$pid <- Sys.getpid()
      owner$host <- unname(Sys.info()[["nodename"]])
      file_ingestion_write_owner(owner, file_ingestion_owner_path(r$dest))
    }
  }, timeout_sec = lock_timeout_sec, require_lock = TRUE)
  # Sahiplik kanıtı yalnız işlemin kendi kopyası kalmadığında bırakılır. Görünen
  # hedefin kimliği okunamıyorsa yabancı olduğu da kanıtlanamaz: silinmez ve
  # işaretleriyle sonraki temizliğe kalır. Kimliği okunup eşleşmeyen hedef
  # yabancıdır, ona dokunulmaz. Bir yapıtın hatası diğerlerini durdurmaz.
  hatalar <- character()
  for (r in c(owned, pending)) {
    if (isTRUE(r$artifact_id %in% committed)) next
    owner <- file_ingestion_read_owner(r$dest)
    if (!identical(owner$id, r$artifact_id)) next
    if (file_ingestion_artifact_owned(r, allow_deleting = TRUE))
      file_ingestion_discard_dest(r$dest, r$source_path)
    if (isTRUE(r$transaction_pending) && identical(owner$staging, r$staging))
      file_ingestion_discard_dest(r$staging, r$source_path)
    hedef_var <- path_exists_relaxed(r$dest)
    if ((hedef_var && (!identical(owner$state, "copying") || is.null(file_ingestion_physical_identity(r$dest)))) ||
        (!is.null(r$staging) && path_exists_relaxed(r$staging))) {
      hatalar <- c(hatalar, "Sahip olunan kopya silinemedi ya da doğrulanamadı; sahiplik korunuyor.")
      next
    }
    if (identical(owner$state, "copying") && !hedef_var &&
        file_ingestion_promotion_pending(r$dest, r$artifact_id)) {
      hatalar <- c(hatalar, "Terfi edilen kopya henüz doğrulanamadı; sahiplik korunuyor.")
      next
    }
    if (identical(file_ingestion_read_owner(r$dest)$id, r$artifact_id))
      unlink(c(file_ingestion_owner_path(r$dest), paste0(file_ingestion_owner_path(r$dest), ".identity")), force = TRUE)
  }
  for (r in results %||% list()) {
    if (identical(r$code, "claim_failed") && !is.null(r$identity))
      file_ingestion_discard_unclaimed(r$dest, r$source_path, r$identity)
  }
  if (length(hatalar)) stop(hatalar[[1]])
  invisible(TRUE)
}

# Parti yalnız kendi neslinde (epoch) indekslenir. Tarayıcı kapanışı iptal
# değildir; UI geri çağrıları ayrıca susturulur. Commit sonrası hiçbir hata
# partiyi geri almaz; işlem günlükleri kalıcı sonuç bilinene dek tutulur.
file_ingestion_finish_job <- function(job, results, queue_wait_ms = 0, discard = FALSE,
                                      journals = character()) {
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
        committed <- tryCatch({
          failed <- Filter(function(r) !isTRUE(r$ok), results)
          if (length(failed)) file_ingestion_discard_results(failed, user_id)
          file_ingestion_commit_index(results, user_id)
        }, error = function(e) {
          try(file_ingestion_discard_results(results, user_id), silent = TRUE)
          stop(e)
        })
        # Reddedilen kardeşin temizlik hatası commit edilmiş yapıtı geri almaz.
        # Kimlik listesi yoksa (kimliksiz indeks) red yoktur; ana süreç de böyle sayar.
        declined <- if (is.null(committed$committed)) list() else
          Filter(function(r) isTRUE(r$ok) && !is.null(r$artifact_id) &&
            !r$artifact_id %in% committed$committed, results)
        if (length(declined)) try(file_ingestion_discard_results(declined, user_id), silent = TRUE)
        committed
      },
      task_type = "file_ingestion_index",
      # Commit'ten önceki iptal (nesil değişimi) işçiyi durdurur ve geri alma
      # yoluna düşer; commit edilmiş yapıt geri alınmaz. Temizlik koşusu iptal edilmez.
      cancel_check = if (discard) function() TRUE else
        function() identical(job$controller$epoch, job$epoch),
      session_token = job$session_token,
      dependency_mode = "explicit",
      globals = globals,
      packages = c("fs", "digest", "jsonlite")
    ) |>
      promises::then(
        onFulfilled = function(index_result) {
          unlink(journals, force = TRUE)
          tryCatch({
            if (discard) {
              file_ingestion_release_job(job)
              file_ingestion_pump()
            } else {
              file_ingestion_apply_commit(job, results, index_result, queue_wait_ms)
            }
          }, error = function(e) log_warn(paste("[FILE INGEST] Commit sonrası hata:", conditionMessage(e))))
          NULL
        },
        onRejected = function(error) {
          file_ingestion_rollback_job(job, results, error, journals)
          NULL
        })
  }, error = function(error) file_ingestion_rollback_job(job, results, error, journals))
  invisible(NULL)
}

# Havuz arızasında geri alma bağımsız işçide yürür; indeks kilidi UI'ı tutmaz.
file_ingestion_rollback_job <- function(job, results, error, journals = character()) {
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
      alive <- mergen_process_status(process)
      if (is.na(alive)) status_errors <<- status_errors + 1L else status_errors <<- 0L
      expired <- as.numeric(difftime(Sys.time(), started, units = "secs")) > 30
      if (status_errors >= 3L || expired) {
        mergen_retire_process(process, function()
          retry(simpleError("Geri alma işçisi sonlandırıldı.")))
        return(invisible(NULL))
      }
      if (is.na(alive) || alive) {
        later::later(poll, delay = 0.1)
        return(invisible(NULL))
      }
      failure <- tryCatch({ process$get_result(); NULL }, error = identity)
      if (!is.null(failure)) return(retry(failure))
      # Geri alma kalıcı olarak tamamlandı; günlük artık gereksiz.
      unlink(journals, force = TRUE)
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
    if (!is.null(job$lease$sources)) unlink(job$lease$sources, recursive = TRUE, force = TRUE)
  }
  file_ingestion_release_slot()
  invisible(TRUE)
}

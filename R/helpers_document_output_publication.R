# Özet terfisi, kaynak yazısını olay döngüsünden ve eski sahipten korur.
cc_publish_document_summary_async <- function(result, target_dir, output_dir, session, rv, request_id) {
  if (!isTRUE(result$success)) return(promises::promise_resolve(result))
  guard <- tempfile("summary-sync-", tmpdir = output_dir)
  if (!isTRUE(file.create(guard))) stop("Özet aktarım koruması oluşturulamadı.")
  rv$summary_sync_guard <- guard
  current <- function() {
    valid <- !isTRUE(session$isClosed()) && cc_is_active_run(rv, request_id) &&
      isTRUE(shiny::isolate(rv$is_running))
    if (!valid) unlink(guard, force = TRUE)
    valid
  }
  remove_owner <- mergen_session_on_owner_change(session, function(...) unlink(guard, force = TRUE))
  globals <- c(list(summary_source = result$generated_summary_path,
    summary_dest = file.path(target_dir, "dosya_aciklamalari.txt"), summary_guard = guard),
    cc_run_output_worker_globals())
  promise <- tryCatch(tracked_future_promise(
    task_fn = function() {
      if (!file.exists(summary_guard)) stop("Özet aktarımı iptal edildi.")
      plan <- list(items = list(list(source_path = summary_source, dest_path = summary_dest,
        size = file.info(summary_source)$size)), source_workdir = dirname(summary_dest),
        output_root = dirname(summary_source))
      applied <- cc_apply_output_sync_plan(plan, active_guard = summary_guard)
      if (length(applied) != 1L || !isTRUE(applied[[1L]]$success)) stop("Özet dosyası güvenli biçimde aktarılamadı.")
      normalizePath(summary_dest, winslash = "/", mustWork = TRUE)
    }, task_type = "claude_code_summary_publish", session_token = session$token,
    execution_timeout = 180, queue_timeout = 30, cancel_check = current,
    dependency_mode = "explicit", globals = globals, packages = c("tools", "utils")),
    error = function(e) promises::promise_reject(e))
  promises::finally(promises::then(promise, function(path) {
    result$generated_summary_path <- path
    result
  }), function() {
    remove_owner()
    unlink(guard, force = TRUE)
    if (!isTRUE(session$isClosed()) && identical(shiny::isolate(rv$summary_sync_guard), guard))
      rv$summary_sync_guard <- NULL
  })
}

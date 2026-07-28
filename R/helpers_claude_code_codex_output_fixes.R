# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_codex_output_fixes.R
# Açıklama: PR #672 Codex incelemesinde kalan snapshot, çıktı staging/sync,
#           tarama hata-yayılımı ve deadline bulgularını düzeltir. Runtime
#           hardening dosyasından sonra yüklenmelidir.
# ==============================================================================

if (!exists(".cc_codex_original_cc_process_run_outputs", inherits = TRUE)) {
  stop("Codex runtime hardening katmanı yüklenmeden output hardening yüklenemez.", call. = FALSE)
}

# Snapshot exceptions and scanner failures propagate; keys fold only on Windows.
snapshot_claude_code_workdir_files <- function(workdir,
                                                recursive = TRUE,
                                                max_files = NULL,
                                                exclude_dirs = cc_scan_default_excluded_dirs(),
                                                exclude_rel_paths = character(0),
                                                max_depth = NULL,
                                                limits = NULL) {
  if (is.null(workdir) || !nzchar(workdir) || !dir.exists(workdir)) return(list())
  max_files <- if (is.null(max_files)) cc_runtime_limit("output_scan_max_files", 1000, limits) else as.numeric(max_files[1])
  max_depth <- if (is.null(max_depth)) cc_runtime_limit("output_scan_max_depth", 8, limits) else as.numeric(max_depth[1])
  if (!isTRUE(recursive)) max_depth <- 0

  scan <- cc_scan_directory_bounded(
    root = workdir,
    max_files = max_files,
    max_dirs = cc_runtime_limit("scan_max_dirs", 500, limits),
    max_depth = max_depth,
    max_total_bytes = Inf,
    max_elapsed_ms = cc_runtime_limit("scan_timeout_ms", 4000, limits),
    max_file_bytes = Inf,
    exclude_dirs = exclude_dirs,
    exclude_rel_paths = c(cc_scan_default_excluded_rel_paths(), as.character(exclude_rel_paths %||% character(0)))
  )
  if (!is.list(scan) || !isTRUE(scan$ok)) {
    stop(paste(c("Çıktı anlık görüntüsü alınamadı.", scan$errors %||% character(0)), collapse = " "), call. = FALSE)
  }
  if (!length(scan$files %||% character(0))) return(structure(list(), scan = scan))

  paths <- as.character(scan$files)
  info <- file.info(paths)
  result <- list()
  use_signature <- length(paths) <= cc_runtime_limit("output_diff_content_check_budget", 200, limits)
  for (i in seq_along(paths)) {
    normalized <- canonicalize_claude_code_file_path(paths[i])
    if (!nzchar(normalized)) next
    mtime <- suppressWarnings(as.numeric(info$mtime[i]))
    size <- suppressWarnings(as.numeric(info$size[i]))
    if (!is.finite(size)) stop(paste0("Çıktı dosyası boyutu belirlenemedi: ", paths[i]), call. = FALSE)
    key <- .cc_codex_path_key(normalized)
    result[[key]] <- list(
      path = normalized,
      mtime = if (is.finite(mtime)) mtime else NA_real_,
      size = size,
      signature = if (isTRUE(use_signature)) .cc_scan_content_signature(paths[i], size) else NA_character_
    )
  }
  structure(result, scan = scan)
}

cc_snapshot_run_output_area <- function(runtime_workdir, mirrored = FALSE, limits = NULL) {
  snapshot_claude_code_workdir_files(
    workdir = runtime_workdir,
    recursive = TRUE,
    exclude_dirs = if (isTRUE(mirrored)) character(0) else cc_scan_default_excluded_dirs(),
    exclude_rel_paths = if (isTRUE(mirrored)) cc_scan_runtime_excluded_dirs() else character(0),
    limits = limits
  )
}

# Unknown-size outputs are rejected before staging or synchronization.
cc_filter_download_candidates <- function(paths, layout = NULL, limits = NULL) {
  paths <- unique(as.character(paths %||% character(0)))
  paths <- paths[nzchar(paths)]
  max_file <- cc_runtime_limit("max_output_file_bytes", 100 * 1024^2, limits)
  max_total <- cc_runtime_limit("max_output_total_bytes", 400 * 1024^2, limits)
  accepted <- rejected_zone <- rejected_size <- character(0)
  total <- 0
  for (path in paths) {
    if (is.list(layout) && nzchar(as.character(layout$root %||% "")[1])) {
      zone <- cc_runtime_zone_of_path(path, layout)
      if (nzchar(zone) && !identical(zone, "output")) {
        rejected_zone <- c(rejected_zone, path)
        next
      }
    }
    size <- suppressWarnings(as.numeric(file.info(path)$size[1]))
    if (!is.finite(size) || size > max_file || total + size > max_total) {
      rejected_size <- c(rejected_size, path)
      next
    }
    accepted <- c(accepted, path)
    total <- total + size
  }
  list(paths = accepted, rejected_zone = unique(rejected_zone), rejected_size = unique(rejected_size))
}

cc_plan_output_sync <- function(changed_files, layout, source_workdir, limits = NULL) {
  paths <- unique(as.character(changed_files %||% character(0)))
  unknown <- paths[vapply(paths, function(path) {
    identical(cc_runtime_zone_of_path(path, layout), "output") &&
      isTRUE(file.exists(path)) &&
      !is.finite(suppressWarnings(as.numeric(file.info(path)$size[1])))
  }, logical(1))]
  plan <- .cc_codex_original_cc_plan_output_sync(
    changed_files = setdiff(paths, unknown),
    layout = layout,
    source_workdir = source_workdir,
    limits = limits
  )
  if (length(unknown)) {
    plan$skipped <- unique(c(as.character(plan$skipped %||% character(0)), unknown))
    plan$skipped_approved <- c(plan$skipped_approved %||% list(), lapply(unknown, function(path) {
      list(source_path = path, size = NA_real_, reason = "unknown_output_size")
    }))
  }
  plan
}

# Preserve cancellation through promotion. Existing destinations are first moved
# to a same-directory backup, so the original implementation never needs its
# non-atomic overwrite-copy fallback. A post-copy guard check restores backup.
cc_apply_output_sync_plan <- function(plan, active_guard = NULL) {
  skipped <- cc_output_sync_skipped_results(plan)
  if (!is.list(plan) || !length(plan$items %||% list())) return(skipped)

  guard_ok <- function() {
    !nzchar(active_guard %||% "") || isTRUE(file.exists(active_guard))
  }
  # Onayli kok ile cozulmus ata AYNI cozumleme semantigiyle hesaplanir;
  # aksi halde Windows 8.3 kisa adi uzun adla karsilastirilir (bkz.
  # cc_output_sync_canonical_root).
  approved_root <- cc_output_sync_canonical_root(as.character(plan$source_workdir %||% "")[1])
  approved_key <- .cc_scan_key(approved_root)
  results <- skipped

  for (item in plan$items) {
    dest <- as.character(item$dest_path %||% "")[1]
    src <- as.character(item$source_path %||% "")[1]
    size <- item$size %||% NA_real_
    fail <- function(message) {
      results[[length(results) + 1L]] <<- list(
        source_path = src, dest_path = dest, success = FALSE,
        size = size, error = message
      )
      invisible(NULL)
    }

    if (!guard_ok()) {
      fail("Çalıştırma durduruldu; çıktı aktarılmadı")
      next
    }
    if (!nzchar(src) || !file.exists(src) || dir.exists(src)) {
      fail("Çıktı kaynağı artık erişilemiyor")
      next
    }
    source_size <- suppressWarnings(as.numeric(file.info(src)$size[1]))
    if (!is.finite(source_size)) {
      fail("Çıktı dosyası boyutu belirlenemedi")
      next
    }

    parent <- dirname(dest)
    ancestor <- parent
    while (!dir.exists(ancestor) && !identical(dirname(ancestor), ancestor)) {
      ancestor <- dirname(ancestor)
    }
    resolved_ancestor <- tryCatch(
      .cc_scan_norm(normalizePath(ancestor, winslash = "/", mustWork = TRUE)),
      error = function(e) ""
    )
    ancestor_key <- .cc_scan_key(resolved_ancestor)
    if (!nzchar(approved_root) || !nzchar(resolved_ancestor) || !(
      identical(ancestor_key, approved_key) || startsWith(ancestor_key, paste0(approved_key, "/"))
    )) {
      fail("Hedef üst dizini onaylı kaynak kökün dışında")
      next
    }
    if (!dir.exists(parent) && !dir.create(parent, recursive = TRUE, showWarnings = FALSE)) {
      fail("Hedef dizin oluşturulamadı")
      next
    }

    had_dest <- isTRUE(file.exists(dest)) || isTRUE(dir.exists(dest))
    if (had_dest) {
      # Sys.readlink() Windows'ta HER ZAMAN NA döner ve nzchar(NA) TRUE'dur;
      # tek başına kullanıldığında var olan her hedefi bağlantı sanıp aynı
      # dosyanın yeniden üretildiği her çalıştırmayı bloke ederdi. Bağlantı
      # tespiti bu yüzden çözülmüş yolun sözlüksel konumdan sapmasıyla
      # yapılır: symlink/junction her iki platformda da başka yere çözülür.
      resolved_parent <- cc_output_sync_canonical_root(parent)
      expected_dest <- if (nzchar(resolved_parent)) {
        paste0(resolved_parent, "/", basename(.cc_scan_norm(dest)))
      } else {
        .cc_scan_norm(dest)
      }
      resolved_dest <- tryCatch(
        .cc_scan_norm(normalizePath(dest, winslash = "/", mustWork = TRUE)),
        error = function(e) ""
      )
      resolved_key <- .cc_scan_key(resolved_dest)
      linked <- !nzchar(resolved_dest) ||
        !identical(resolved_key, .cc_scan_key(expected_dest)) ||
        isTRUE(.cc_scan_is_link(dest))
      dest_safe <- nzchar(resolved_dest) && (
        identical(resolved_key, approved_key) || startsWith(resolved_key, paste0(approved_key, "/"))
      )
      if (isTRUE(linked) || !isTRUE(dest_safe) || isTRUE(dir.exists(dest))) {
        fail("Hedef dosya bağlantı/reparse-point, dizin veya onaylı kökün dışında")
        next
      }
    }

    token <- paste0(Sys.getpid(), "-", sprintf("%08d", sample.int(1e8, 1L)))
    staging <- file.path(parent, paste0(".cc-output-stage-", token))
    backup <- file.path(parent, paste0(".cc-output-backup-", token))
    unlink(c(staging, backup), recursive = TRUE, force = TRUE)

    staged <- isTRUE(tryCatch(
      file.copy(src, staging, overwrite = FALSE, copy.mode = TRUE, copy.date = TRUE),
      error = function(e) FALSE
    )) && isTRUE(file.exists(staging))
    if (!staged) {
      unlink(staging, force = TRUE)
      fail("Çıktı staging dosyasına kopyalanamadı")
      next
    }
    staged_size <- suppressWarnings(as.numeric(file.info(staging)$size[1]))
    if (!is.finite(staged_size) || !identical(staged_size, source_size)) {
      unlink(staging, force = TRUE)
      fail("Çıktı staging doğrulaması başarısız")
      next
    }
    if (!guard_ok()) {
      unlink(staging, force = TRUE)
      fail("Çalıştırma durduruldu; çıktı terfi ettirilmedi")
      next
    }

    if (had_dest && !isTRUE(file.rename(dest, backup))) {
      unlink(staging, force = TRUE)
      fail("Hedef dosya atomik terfi için yedeklenemedi")
      next
    }

    promoted <- isTRUE(tryCatch(file.rename(staging, dest), error = function(e) FALSE))
    post_guard <- guard_ok()
    if (!promoted || !post_guard) {
      unlink(staging, force = TRUE)
      unlink(dest, force = TRUE)
      restored <- !had_dest || (file.exists(backup) && isTRUE(file.rename(backup, dest)))
      fail(if (!post_guard) {
        if (restored) "Çalıştırma durduruldu; çıktı terfisi geri alındı" else
          "Çalıştırma durduruldu ve önceki hedef geri yüklenemedi"
      } else if (restored) {
        "Çıktı atomik olarak terfi ettirilemedi"
      } else {
        "Çıktı terfi edemedi ve önceki hedef geri yüklenemedi"
      })
      next
    }

    unlink(backup, force = TRUE)
    results[[length(results) + 1L]] <- list(
      source_path = src, dest_path = dest, success = TRUE,
      size = source_size, error = ""
    )
  }
  results
}

cc_process_run_outputs <- function(request) {
  runtime <- as.character(request$runtime_workdir %||% "")[1]
  if (!nzchar(runtime) || !dir.exists(runtime)) {
    stop("Çalıştırma runtime dizini çıktı işlenmeden önce kayboldu veya erişilemez oldu.", call. = FALSE)
  }
  .cc_codex_original_cc_process_run_outputs(request)
}

# Report partial synchronization failures without discarding successful model
# text, downloads or successfully synchronized sibling files.
cc_report_output_sync_failure <- function(ctx, outputs) {
  failures <- cc_output_sync_failures(outputs)
  if (!length(failures)) return(FALSE)
  names <- unique(vapply(failures, function(x) basename(x$dest_path %||% x$source_path %||% "dosya"), character(1)))
  message <- paste0(
    "Çalıştırma tamamlandı; ancak ", length(failures),
    " çıktı kaynak klasöre aktarılamadı: ", paste(names, collapse = ", ")
  )
  ctx$session$sendCustomMessage("cc-add-message", list(
    target = ctx$ns("output_area"), type = "warning",
    content = htmltools::htmlEscape(message), timestamp = format(Sys.time(), "%H:%M:%S")
  ))
  FALSE
}

# Independent output deadline with explicit cancellation, plus synchronous
# dispatch cleanup of both the guard and runtime lease.
cc_dispatch_run_output_processing <- function(ctx) {
  guard <- file.path(
    ctx$env$runtime_layout$metadata %||% tempdir(),
    paste0("output-sync-", gsub("[^A-Za-z0-9_.-]", "_", ctx$env$request_id %||% "run"), ".active")
  )
  dir.create(dirname(guard), recursive = TRUE, showWarnings = FALSE)
  if (!isTRUE(tryCatch(file.create(guard), error = function(e) FALSE)) || !file.exists(guard)) {
    cc_report_output_processing_failure(ctx, simpleError("Çıktı aktarım koruma dosyası oluşturulamadı."))
    return(invisible(TRUE))
  }
  ctx$env$output_sync_guard <- guard
  request <- cc_build_run_output_request(ctx$env, ctx$ayristirma$tool_uses %||% list())
  cc_send_run_stage(ctx$session, ctx$ns, "cikti")

  timeout_sec <- cc_runtime_limit("output_process_timeout_sec", 180, request$limits)
  deadline <- new.env(parent = emptyenv())
  deadline$pending <- TRUE
  deadline$cancel <- later::later(function() {
    if (isTRUE(deadline$pending) && cc_is_active_run(ctx$rv, ctx$env$request_id)) {
      deadline$pending <- FALSE
      unlink(request$active_guard, force = TRUE)
      unlink(ctx$env$runtime_lease %||% "", force = TRUE)
      cc_report_output_processing_failure(ctx, simpleError(sprintf(
        "Çıktı işleme zaman aşımına uğradı (%.0f saniye).", timeout_sec
      )))
    }
  }, delay = timeout_sec)
  cancel_deadline <- function() {
    deadline$pending <- FALSE
    cancel <- deadline$cancel
    if (is.function(cancel)) tryCatch(cancel(), error = function(e) NULL)
    deadline$cancel <- NULL
    invisible(NULL)
  }
  cleanup <- function() {
    unlink(request$active_guard, force = TRUE)
    unlink(ctx$env$runtime_lease %||% "", force = TRUE)
    invisible(NULL)
  }

  dispatch_error <- tryCatch({
    tracked_future_promise(
      task_fn = function() cc_process_run_outputs(request),
      task_type = "claude_code_run_outputs",
      session_token = ctx$session$token,
      dependency_mode = "explicit",
      globals = c(list(request = request), cc_run_output_worker_globals()),
      packages = c("tools", "utils")
    ) |>
      promises::then(function(outputs) {
        cancel_deadline()
        if (!cc_is_active_run(ctx$rv, ctx$env$request_id)) {
          cleanup()
          return(NULL)
        }
        if (length(outputs$sync_results %||% list())) cc_send_run_stage(ctx$session, ctx$ns, "aktarim")
        if (cc_report_output_scan_truncation(ctx, outputs)) {
          cleanup()
          return(NULL)
        }
        cc_report_output_sync_failure(ctx, outputs)
        cc_finish_streaming_run(ctx, outputs)
        cleanup()
        NULL
      }) |>
      promises::catch(function(e) {
        cancel_deadline()
        cleanup()
        if (cc_is_active_run(ctx$rv, ctx$env$request_id)) {
          cc_report_output_processing_failure(ctx, e)
        }
        NULL
      })
    NULL
  }, error = function(e) e)

  if (!is.null(dispatch_error)) {
    cancel_deadline()
    cleanup()
    if (cc_is_active_run(ctx$rv, ctx$env$request_id)) {
      cc_report_output_processing_failure(ctx, dispatch_error)
    }
  }
  invisible(TRUE)
}

# Explicit future bundles carry only the late-loaded functions used by that
# worker. Keeping this list narrow avoids reintroducing expensive global scans.
.cc_codex_add_named_worker_globals <- function(bundle, names, envir = globalenv()) {
  for (name in unique(names)) {
    value <- get0(name, envir = envir, inherits = TRUE)
    if (!is.null(value)) bundle[[name]] <- value
  }
  bundle
}

.cc_codex_prepare_worker_names <- c(
  ".cc_codex_original_mirror_directory_to_local_workspace",
  ".cc_codex_original_cc_select_input_files",
  ".cc_codex_original_cc_scan_directory_bounded",
  ".cc_codex_original_prepare_claude_code_document_context",
  ".cc_codex_original_cc_prepare_run_workspace",
  ".cc_codex_path_key", ".cc_codex_guard_check", ".cc_codex_acquire_dir_lock",
  "cc_scan_directory_bounded", "cc_select_input_files",
  "mirror_directory_to_local_workspace", "prepare_claude_runtime_workdir",
  "cc_claim_runtime_ownership", "cc_runtime_ownership_is",
  "cc_scan_runtime_excluded_dirs", "deduplicate_claude_code_file_paths",
  "cc_select_documents_for_request", "prepare_claude_code_document_context",
  "cc_prepare_run_workspace", "snapshot_claude_code_workdir_files",
  "cc_snapshot_run_output_area"
)

.cc_codex_output_worker_names <- c(
  ".cc_codex_original_cc_scan_directory_bounded",
  ".cc_codex_original_cc_plan_output_sync",
  ".cc_codex_original_cc_process_run_outputs",
  ".cc_codex_path_key",
  "cc_scan_directory_bounded", "cc_scan_runtime_excluded_dirs",
  "deduplicate_claude_code_file_paths", "snapshot_claude_code_workdir_files",
  "cc_snapshot_run_output_area", "cc_filter_download_candidates",
  "cc_plan_output_sync", "cc_apply_output_sync_plan", "cc_process_run_outputs"
)

# Süreç başına ÖNBELLEK sözleşmesi korunur. Sertleştirme katmanı yalnızca
# yüklenirken önbelleği geçersiz kılar (aşağıdaki NULL atamaları); sonraki
# gönderimler `refresh = FALSE` ile önbellekten okur.
#
# REGRESYON: Bu sarmalayıcılar önceden koşulsuz `refresh = TRUE` çağırıyordu.
# Böylece her Bilge Yolaç çalıştırması, future gönderilmeden ÖNCE ana Shiny
# olay döngüsünde `worker_monitor_expand_function_globals()` /
# `codetools::findGlobals()` özyinelemesini baştan çalıştırıyor ve açık worker
# globals'ının önlemek için var olduğu oturumlar arası donmayı geri
# getiriyordu.
cc_run_prepare_worker_globals <- function(refresh = FALSE, envir = globalenv()) {
  if (!isTRUE(refresh) && !is.null(.cc_prepare_worker_cache$globals)) {
    return(.cc_prepare_worker_cache$globals)
  }

  bundle <- .cc_codex_original_cc_run_prepare_worker_globals(refresh = TRUE, envir = envir)
  bundle <- .cc_codex_add_named_worker_globals(
    bundle, .cc_codex_prepare_worker_names, envir
  )
  .cc_prepare_worker_cache$globals <- bundle
  bundle
}

cc_run_output_worker_globals <- function(refresh = FALSE, envir = globalenv()) {
  if (!isTRUE(refresh) && !is.null(.cc_completion_worker_cache$globals)) {
    return(.cc_completion_worker_cache$globals)
  }

  bundle <- .cc_codex_original_cc_run_output_worker_globals(refresh = TRUE, envir = envir)
  bundle <- .cc_codex_add_named_worker_globals(
    bundle, .cc_codex_output_worker_names, envir
  )
  .cc_completion_worker_cache$globals <- bundle
  bundle
}

# Geç yüklenen sertleştirme sürümleri, temel katman tarafından önceden
# doldurulmuş paketleri geçersiz kılar; ilk gönderim paketi bir kez yeniden
# kurar ve sonraki gönderimler önbelleği kullanır.
.cc_prepare_worker_cache$globals <- NULL
.cc_completion_worker_cache$globals <- NULL

# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_codex_runtime_fixes.R
# Açıklama: PR #672 Codex incelemesinde kalan yarış, sınır ve hata-yayılımı
#           bulgularının runtime/input/sahiplik/doküman bölümünü düzeltir.
#           Çıktı ve deadline düzeltmeleri ayrı output hardening dosyasındadır.
# ==============================================================================

.cc_codex_original_mirror_directory_to_local_workspace <- mirror_directory_to_local_workspace
.cc_codex_original_cc_select_input_files <- cc_select_input_files
.cc_codex_original_cc_scan_directory_bounded <- cc_scan_directory_bounded
.cc_codex_original_cc_plan_output_sync <- cc_plan_output_sync
.cc_codex_original_cc_apply_output_sync_plan <- cc_apply_output_sync_plan
.cc_codex_original_cc_process_run_outputs <- cc_process_run_outputs
.cc_codex_original_cc_prepare_run_workspace <- cc_prepare_run_workspace
.cc_codex_original_cc_dispatch_run_preparation <- cc_dispatch_run_preparation
.cc_codex_original_cc_run_prepare_worker_globals <- cc_run_prepare_worker_globals
.cc_codex_original_cc_run_output_worker_globals <- cc_run_output_worker_globals
.cc_codex_original_prepare_claude_code_document_context <- prepare_claude_code_document_context

.cc_codex_path_key <- function(path) {
  path <- as.character(path %||% character(0))
  if (.Platform$OS.type == "windows") tolower(path) else path
}

.cc_codex_guard_check <- function(guard) {
  if (is.function(guard)) guard()
  invisible(TRUE)
}

.cc_codex_acquire_dir_lock <- function(lock_dir, guard = NULL, attempts = 200L) {
  attempts <- max(1L, suppressWarnings(as.integer(attempts[1])))
  for (i in seq_len(attempts)) {
    .cc_codex_guard_check(guard)
    if (isTRUE(tryCatch(dir.create(lock_dir, showWarnings = FALSE), error = function(e) FALSE))) {
      return(TRUE)
    }
    Sys.sleep(0.05)
  }
  FALSE
}

# Unknown sizes must fail closed. This protects preflight, input limits and output
# scans on flaky UNC shares where file.info() can return NA.
cc_scan_directory_bounded <- function(...) {
  sonuc <- .cc_codex_original_cc_scan_directory_bounded(...)
  if (!is.list(sonuc) || !length(sonuc$files %||% character(0))) return(sonuc)

  boyutlar <- tryCatch(
    suppressWarnings(as.numeric(file.info(sonuc$files)$size)),
    error = function(e) rep(NA_real_, length(sonuc$files))
  )
  bilinmeyen <- !is.finite(boyutlar)
  if (any(bilinmeyen)) {
    yollar <- as.character(sonuc$files[bilinmeyen])
    sonuc$ok <- FALSE
    sonuc$errors <- unique(c(
      as.character(sonuc$errors %||% character(0)),
      paste0("Dosya boyutu belirlenemedi: ", yollar)
    ))
    sonuc$skipped <- unique(c(as.character(sonuc$skipped %||% character(0)), yollar))
  }
  sonuc
}

# Requested inputs with unknown sizes are never counted as zero or silently
# replaced by an automatic subset.
cc_select_input_files <- function(prompt,
                                  files,
                                  file_sizes = NULL,
                                  root = "",
                                  explicit_files = character(0),
                                  limits = NULL) {
  files <- as.character(files %||% character(0))
  relatives <- if (length(files)) cc_scan_relative_paths(files, root) else character(0)
  sizes <- suppressWarnings(as.numeric(file_sizes %||% rep(NA_real_, length(files))))
  if (length(sizes) != length(files)) sizes <- rep(NA_real_, length(files))

  required_keys <- unique(c(
    basename(as.character(explicit_files %||% character(0))),
    gsub("\\", "/", as.character(explicit_files %||% character(0)), fixed = TRUE),
    cc_extract_prompt_file_mentions(prompt)
  ))
  required_keys <- required_keys[nzchar(required_keys)]
  unknown_required <- character(0)
  if (length(files) && length(required_keys)) {
    unknown_required <- relatives[
      !is.finite(sizes) & .cc_prepare_mention_matches(files, relatives, required_keys)
    ]
  }

  sonuc <- .cc_codex_original_cc_select_input_files(
    prompt = prompt,
    files = files,
    file_sizes = file_sizes,
    root = root,
    explicit_files = explicit_files,
    limits = limits
  )

  selected <- as.character(sonuc$files %||% character(0))
  if (length(selected)) {
    selected_sizes <- tryCatch(
      suppressWarnings(as.numeric(file.info(selected)$size)),
      error = function(e) rep(NA_real_, length(selected))
    )
    max_file_bytes <- suppressWarnings(as.numeric(
      cc_runtime_limit("max_input_file_bytes", 25 * 1024^2, limits)
    )[1])
    max_total_bytes <- suppressWarnings(as.numeric(
      cc_runtime_limit("max_input_total_bytes", 100 * 1024^2, limits)
    )[1])
    running_total <- 0
    bad <- !is.finite(selected_sizes) | selected_sizes > max_file_bytes
    for (i in seq_along(selected_sizes)) {
      if (!bad[i] && running_total + selected_sizes[i] <= max_total_bytes) {
        running_total <- running_total + selected_sizes[i]
      } else {
        bad[i] <- TRUE
      }
    }
    if (any(bad)) {
      bad_rel <- as.character(sonuc$relatives %||% basename(selected))[bad]
      sonuc$files <- selected[!bad]
      sonuc$relatives <- as.character(sonuc$relatives %||% basename(selected))[!bad]
      sonuc$skipped <- unique(c(as.character(sonuc$skipped %||% character(0)), bad_rel))
      if (!identical(sonuc$selection_mode %||% "auto", "auto")) {
        sonuc$required_skipped <- unique(c(
          as.character(sonuc$required_skipped %||% character(0)), bad_rel
        ))
      }
      sonuc$truncated <- TRUE
    }
  }

  if (length(unknown_required)) {
    sonuc$skipped <- unique(c(as.character(sonuc$skipped %||% character(0)), unknown_required))
    sonuc$required_skipped <- unique(c(
      as.character(sonuc$required_skipped %||% character(0)), unknown_required
    ))
    sonuc$truncated <- TRUE
  }

  final_sizes <- if (length(sonuc$files %||% character(0))) {
    suppressWarnings(as.numeric(file.info(sonuc$files)$size))
  } else numeric(0)
  sonuc$total_bytes <- if (length(final_sizes) && all(is.finite(final_sizes))) sum(final_sizes) else 0
  sonuc
}

# Copy each request into a private input tree, then atomically swap the entire
# tree under an ownership-aware lock. This clears stale inputs and prevents an
# older worker from interleaving bytes with a newer request.
mirror_directory_to_local_workspace <- function(source_dir,
                                                target_dir,
                                                prompt = NULL,
                                                explicit_files = character(0),
                                                limits = NULL,
                                                scan = NULL,
                                                ownership_guard = NULL) {
  parent <- dirname(target_dir)
  dir.create(parent, recursive = TRUE, showWarnings = FALSE)
  token <- paste0(Sys.getpid(), "-", sprintf("%08d", sample.int(1e8, 1L)))
  staging <- file.path(parent, paste0(".input-stage-", token))
  backup <- file.path(parent, paste0(".input-backup-", token))
  lock_dir <- file.path(parent, ".input-promote.lock")
  unlink(c(staging, backup), recursive = TRUE, force = TRUE)

  sonuc <- .cc_codex_original_mirror_directory_to_local_workspace(
    source_dir = source_dir,
    target_dir = staging,
    prompt = prompt,
    explicit_files = explicit_files,
    limits = limits,
    scan = scan,
    ownership_guard = ownership_guard
  )
  if (!isTRUE(sonuc$ok)) {
    unlink(staging, recursive = TRUE, force = TRUE)
    return(sonuc)
  }

  # The source may grow while it is copied. Validate the bytes that actually
  # reached the private staging tree before that tree can replace active input.
  staged_files <- as.character(sonuc$copy$copied %||% character(0))
  staged_sizes <- suppressWarnings(as.numeric(file.info(staged_files)$size))
  max_file_bytes <- suppressWarnings(as.numeric(
    cc_runtime_limit("max_input_file_bytes", 25 * 1024^2, limits)
  )[1])
  max_total_bytes <- suppressWarnings(as.numeric(
    cc_runtime_limit("max_input_total_bytes", 100 * 1024^2, limits)
  )[1])
  staging_invalid <- length(staged_sizes) != length(staged_files) ||
    any(!is.finite(staged_sizes)) || any(staged_sizes > max_file_bytes) ||
    sum(staged_sizes) > max_total_bytes
  if (isTRUE(staging_invalid)) {
    unlink(staging, recursive = TRUE, force = TRUE)
    stop("Kopyalanan runtime girdileri güvenli dosya boyutu sınırlarını aşıyor.", call. = FALSE)
  }

  .cc_codex_guard_check(ownership_guard)
  if (!.cc_codex_acquire_dir_lock(lock_dir, ownership_guard)) {
    unlink(staging, recursive = TRUE, force = TRUE)
    stop("Runtime input terfi kilidi alınamadı.", call. = FALSE)
  }
  on.exit(unlink(lock_dir, recursive = TRUE, force = TRUE), add = TRUE)

  .cc_codex_guard_check(ownership_guard)
  had_target <- dir.exists(target_dir)
  if (had_target && !isTRUE(file.rename(target_dir, backup))) {
    unlink(staging, recursive = TRUE, force = TRUE)
    stop("Eski runtime input alanı güvenli biçimde yedeklenemedi.", call. = FALSE)
  }

  restore <- function() {
    unlink(target_dir, recursive = TRUE, force = TRUE)
    if (dir.exists(backup)) file.rename(backup, target_dir)
    invisible(NULL)
  }

  promoted <- FALSE
  err <- tryCatch({
    .cc_codex_guard_check(ownership_guard)
    if (!isTRUE(file.rename(staging, target_dir))) {
      stop("Yeni runtime input alanı atomik olarak terfi ettirilemedi.", call. = FALSE)
    }
    promoted <- TRUE
    .cc_codex_guard_check(ownership_guard)
    NULL
  }, error = function(e) e)

  if (!is.null(err)) {
    if (promoted || had_target) restore()
    unlink(staging, recursive = TRUE, force = TRUE)
    stop(conditionMessage(err), call. = FALSE)
  }
  unlink(backup, recursive = TRUE, force = TRUE)

  old_prefix <- paste0(normalizePath(staging, winslash = "/", mustWork = FALSE), "/")
  new_prefix <- paste0(normalizePath(target_dir, winslash = "/", mustWork = FALSE), "/")
  remap <- function(x) {
    x <- gsub("\\", "/", as.character(x %||% character(0)), fixed = TRUE)
    vapply(x, function(path) {
      if (startsWith(path, old_prefix)) {
        paste0(new_prefix, substring(path, nchar(old_prefix) + 1L))
      } else {
        path
      }
    }, character(1), USE.NAMES = FALSE)
  }
  sonuc$copy$copied <- remap(sonuc$copy$copied)
  if (length(sonuc$copy$results %||% list())) {
    sonuc$copy$results <- lapply(sonuc$copy$results, function(x) {
      x$dest_path <- remap(x$dest_path)
      x
    })
  }
  sonuc
}

# All selected directories now use the isolated input/output layout. A source
# path that cannot be resolved is rejected before the CLI is launched.
prepare_claude_runtime_workdir <- function(workdir,
                                           user_id = NULL,
                                           runtime_token = NULL,
                                           existing_runtime_workdir = NULL,
                                           prompt = NULL,
                                           explicit_files = character(0),
                                           limits = NULL,
                                           ownership_guard = NULL) {
  if (is.null(workdir) || !nzchar(workdir)) return(.cc_runtime_prepare_result(workdir))

  original_workdir <- as.character(workdir %||% "")[1]
  source_dir <- resolve_claude_runtime_source_dir(original_workdir)
  if (!nzchar(source_dir) || !dir.exists(source_dir)) {
    stop(paste0(
      "Seçilen çalışma dizini çözülemedi veya erişilemiyor: ", original_workdir
    ), call. = FALSE)
  }

  scan <- cc_scan_source_workdir(source_dir, limits = limits)
  preflight <- cc_evaluate_workdir_preflight(scan, limits = limits)
  if (isTRUE(preflight$blocked)) {
    stop(preflight$message %||% "Kaynak klasör taraması başarısız oldu.", call. = FALSE)
  }

  reuse <- isTRUE(.cc_runtime_workdir_reusable(existing_runtime_workdir, user_id))
  runtime_root <- if (reuse) {
    normalizePath(existing_runtime_workdir, winslash = "/", mustWork = FALSE)
  } else {
    candidate <- file.path(cc_runtime_user_dir(user_id), .cc_runtime_workdir_token(runtime_token))
    if (!dir.exists(candidate) && !dir.create(candidate, recursive = TRUE, showWarnings = FALSE)) {
      stop("İzole runtime çalışma alanı oluşturulamadı.", call. = FALSE)
    }
    normalizePath(candidate, winslash = "/", mustWork = FALSE)
  }

  layout <- cc_runtime_ensure_layout(list(
    root = runtime_root,
    input = file.path(runtime_root, "input"),
    output = file.path(runtime_root, "output"),
    metadata = file.path(runtime_root, "metadata"),
    document_support = file.path(runtime_root, "document_support")
  ))

  transfer <- mirror_directory_to_local_workspace(
    source_dir = source_dir,
    target_dir = layout$input,
    prompt = prompt,
    explicit_files = explicit_files,
    limits = limits,
    scan = scan,
    ownership_guard = ownership_guard
  )
  if (!isTRUE(transfer$ok)) {
    stop(transfer$message %||% "Gerekli girdi dosyaları runtime alanına kopyalanamadı.", call. = FALSE)
  }

  .cc_runtime_prepare_result(
    workdir = layout$root,
    source_dir = source_dir,
    mirrored = TRUE,
    reused = reuse,
    layout = layout,
    selection = transfer$selection,
    preflight = preflight,
    scan = scan
  )
}

# Ownership marker updates are serialized, atomically promoted, and fail closed.
cc_claim_runtime_ownership <- function(runtime_workdir, request_id) {
  owner <- cc_runtime_owner_file(runtime_workdir)
  request_id <- as.character(request_id %||% "")[1]
  if (!nzchar(owner) || !nzchar(request_id)) return("")
  dir.create(dirname(owner), recursive = TRUE, showWarnings = FALSE)
  lock_dir <- paste0(owner, ".lock")
  if (!.cc_codex_acquire_dir_lock(lock_dir, attempts = 100L)) return("")
  on.exit(unlink(lock_dir, recursive = TRUE, force = TRUE), add = TRUE)

  tmp <- paste0(owner, ".", Sys.getpid(), ".tmp")
  ok <- tryCatch({
    writeLines(request_id, tmp, useBytes = TRUE)
    if (file.exists(owner) && !isTRUE(unlink(owner, force = TRUE) == 0L)) stop("owner unlink")
    if (!isTRUE(file.rename(tmp, owner))) stop("owner promote")
    identical(readLines(owner, warn = FALSE, n = 1L), request_id)
  }, error = function(e) FALSE)
  unlink(tmp, force = TRUE)
  if (isTRUE(ok)) owner else ""
}

cc_runtime_ownership_is <- function(runtime_workdir, request_id) {
  owner <- cc_runtime_owner_file(runtime_workdir)
  request_id <- as.character(request_id %||% "")[1]
  if (!nzchar(owner) || !nzchar(request_id) || !file.exists(owner)) return(FALSE)
  value <- tryCatch(readLines(owner, warn = FALSE, n = 1L), error = function(e) character(0))
  length(value) == 1L && nzchar(value[1]) && identical(value[1], request_id)
}

# Claim reuse ownership before the original dispatcher schedules any worker.
cc_dispatch_run_preparation <- function(ctx) {
  existing <- NULL
  if (!is.null(ctx$rv$active_runtime_source) &&
      !is.null(ctx$rv$active_runtime_workdir) &&
      identical(as.character(ctx$rv$active_runtime_source), as.character(ctx$workdir))) {
    existing <- as.character(ctx$rv$active_runtime_workdir)[1]
  }
  if (!is.null(existing) && nzchar(existing)) {
    claim <- cc_claim_runtime_ownership(existing, ctx$run_request_id)
    if (!nzchar(claim)) {
      cc_fail_run_preparation(
        ctx,
        "Yeniden kullanılan çalışma alanının sahipliği güvenli biçimde alınamadı; çalışma başlatılmadı."
      )
      return(invisible(FALSE))
    }
  }
  .cc_codex_original_cc_dispatch_run_preparation(ctx)
}

cc_scan_runtime_excluded_dirs <- function() c("input", "metadata", "document_support")

# Platform-aware path deduplication preserves distinct case-sensitive files.
deduplicate_claude_code_file_paths <- function(paths) {
  paths <- Filter(nzchar, as.character(paths %||% character(0)))
  if (!length(paths)) return(character(0))
  canonical <- vapply(paths, canonicalize_claude_code_file_path, character(1), USE.NAMES = FALSE)
  canonical <- canonical[nzchar(canonical)]
  canonical[!duplicated(.cc_codex_path_key(canonical))]
}

# Match requested documents by basename or relative-path suffix using platform
# case rules; explicitly requested omissions fail closed instead of disappearing.
cc_select_documents_for_request <- function(prompt,
                                            documents,
                                            explicit_files = character(0),
                                            limits = NULL) {
  documents <- unique(as.character(documents %||% character(0)))
  requested <- unique(c(
    basename(as.character(explicit_files %||% character(0))),
    gsub("\\", "/", as.character(explicit_files %||% character(0)), fixed = TRUE),
    cc_extract_prompt_file_mentions(prompt)
  ))
  requested <- requested[nzchar(requested)]
  requested_documents <- requested[
    tolower(tools::file_ext(requested)) %in% tolower(get_claude_code_binary_doc_extensions())
  ]
  if (!length(documents)) {
    if (length(requested_documents)) {
      stop(paste0(
        "Açıkça istenen dokümanlar seçilen klasörde bulunamadı: ",
        paste(unique(basename(requested_documents)), collapse = ", ")
      ), call. = FALSE)
    }
    return(list(files = character(0), selection_mode = "none", skipped = character(0), truncated = FALSE))
  }

  max_docs <- suppressWarnings(as.integer(cc_runtime_limit("max_documents", 10, limits))[1])
  if (is.na(max_docs) || max_docs < 1L) max_docs <- 1L
  max_doc_bytes <- suppressWarnings(as.numeric(
    cc_runtime_limit("max_document_bytes", 25 * 1024^2, limits)
  )[1])
  if (!is.finite(max_doc_bytes) || max_doc_bytes < 0) max_doc_bytes <- 25 * 1024^2
  max_total_bytes <- suppressWarnings(as.numeric(
    cc_runtime_limit("max_documents_total_bytes", 80 * 1024^2, limits)
  )[1])
  if (!is.finite(max_total_bytes) || max_total_bytes < 0) max_total_bytes <- 80 * 1024^2
  normalized <- gsub("\\", "/", documents, fixed = TRUE)
  candidate_key <- .cc_codex_path_key(normalized)
  base_key <- .cc_codex_path_key(basename(normalized))
  request_key <- .cc_codex_path_key(requested)

  selected_idx <- integer(0)
  mode <- "auto"
  if (length(request_key)) {
    selected_idx <- which(vapply(seq_along(documents), function(i) {
      any(vapply(request_key, function(key) {
        identical(base_key[i], key) || identical(candidate_key[i], key) || endsWith(candidate_key[i], paste0("/", key))
      }, logical(1)))
    }, logical(1)))
    if (length(selected_idx)) mode <- "prompt"
  }

  # Kullanıcı AÇIKÇA bir doküman adı verdiyse ve o ad keşfedilen dokümanların
  # hiçbiriyle eşleşmiyorsa (ör. "missing.pdf" istendi, klasörde yalnızca
  # "other.pdf" var), otomatik sıralı aday kümesine düşmek YANLIŞTIR:
  # hazırlık hiç istenmemiş bir dokümanı çıkarır ve çalıştırma kullanıcının
  # sormadığı içerik için "başarılı" görünür. Bu durum kapalı biçimde
  # reddedilir.
  #
  # Aşırı engellemeyi önlemek için yalnızca GERÇEK doküman uzantısı taşıyan
  # anmalar dikkate alınır; sıradan düzyazıdaki "3.5", "v1.2" gibi noktalı
  # belirteçler bir çalıştırmayı bloke edemez.
  if (length(requested)) {
    dokuman_extleri <- tolower(get_claude_code_binary_doc_extensions())
    istenen_dokuman <- requested[
      tolower(tools::file_ext(requested)) %in% dokuman_extleri
    ]

    if (length(istenen_dokuman)) {
      istenen_anahtar <- .cc_codex_path_key(istenen_dokuman)
      eslesti <- vapply(istenen_anahtar, function(key) {
        any(base_key == key | candidate_key == key |
              endsWith(candidate_key, paste0("/", key)))
      }, logical(1))
      eksik_dokuman <- istenen_dokuman[!eslesti]

      if (length(eksik_dokuman)) {
        stop(paste0(
          "Açıkça istenen dokümanlar seçilen klasörde bulunamadı: ",
          paste(unique(basename(eksik_dokuman)), collapse = ", ")
        ), call. = FALSE)
      }
    }
  }

  if (!length(selected_idx)) selected_idx <- order(candidate_key)

  sizes <- suppressWarnings(as.numeric(file.info(documents)$size))
  chosen <- character(0)
  skipped <- character(0)
  total <- 0
  truncated <- FALSE
  for (pos in seq_along(selected_idx)) {
    i <- selected_idx[pos]
    if (length(chosen) >= max_docs) {
      skipped <- c(skipped, documents[selected_idx[pos:length(selected_idx)]])
      truncated <- TRUE
      break
    }
    if (!is.finite(sizes[i]) || sizes[i] > max_doc_bytes) {
      skipped <- c(skipped, documents[i])
      if (!is.finite(sizes[i])) truncated <- TRUE
      next
    }
    if (total + sizes[i] > max_total_bytes) {
      skipped <- c(skipped, documents[selected_idx[pos:length(selected_idx)]])
      truncated <- TRUE
      break
    }
    chosen <- c(chosen, documents[i])
    total <- total + sizes[i]
  }
  if (!identical(mode, "auto") && length(skipped)) {
    stop(paste0(
      "Açıkça istenen dokümanların tümü güvenli sınırlar içinde hazırlanamadı: ",
      paste(basename(unique(skipped)), collapse = ", ")
    ), call. = FALSE)
  }

  list(files = chosen, selection_mode = mode, skipped = unique(skipped), truncated = truncated)
}

prepare_claude_code_document_context <- function(...) {
  args <- list(...)
  prompt <- as.character(args$prompt %||% "")[1]
  explicit_files <- as.character(args$explicit_files %||% character(0))
  requested <- unique(c(explicit_files, cc_extract_prompt_file_mentions(prompt)))
  requested_documents <- requested[
    tolower(tools::file_ext(requested)) %in% tolower(get_claude_code_binary_doc_extensions())
  ]
  if (length(requested_documents)) {
    runtime <- as.character(args$runtime_workdir %||% "")[1]
    source <- as.character(args$source_workdir %||% "")[1]
    has_candidates <- any(vapply(c(runtime, source), function(path) {
      nzchar(path) && dir.exists(path) && isTRUE(workdir_has_binary_documents(path))
    }, logical(1)))
    if (!has_candidates) {
      cc_select_documents_for_request(prompt, character(0), explicit_files, args$limits)
    }
  }
  result <- do.call(.cc_codex_original_prepare_claude_code_document_context, args)
  selection <- result$document_selection %||% list()
  if (!identical(selection$selection_mode %||% "auto", "auto") &&
      (isTRUE(selection$truncated) || length(selection$skipped %||% character(0)))) {
    stop(paste0(
      "Açıkça istenen dokümanların tümü güvenli sınırlar içinde hazırlanamadı: ",
      paste(basename(selection$skipped %||% character(0)), collapse = ", ")
    ), call. = FALSE)
  }
  result
}

# The worker deliberately catches document preparation exceptions so ordinary
# extractor failures can degrade gracefully. Explicitly requested omissions are
# different: convert that captured error into a blocked preparation result.
cc_prepare_run_workspace <- function(request) {
  result <- .cc_codex_original_cc_prepare_run_workspace(request)
  errors <- paste(
    as.character(result$document_context$extraction_errors %||% character(0)),
    collapse = " | "
  )
  # Ortak önek iki fail-closed durumu da kapsar: istenen doküman sınırlar
  # içinde hazırlanamadı VEYA klasörde hiç bulunamadı.
  if (grepl("Açıkça istenen doküman", errors, fixed = TRUE)) {
    result$ok <- FALSE
    result$blocked <- TRUE
    result$message <- errors
  }
  result
}

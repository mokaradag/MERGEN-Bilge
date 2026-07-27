# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-codex-review-fixes.R
# Açıklama: PR #672 üzerinde Codex tarafından bildirilen son runtime/output
#           yarış ve fail-closed bulgularının gerileme testleri.
# ==============================================================================

.cc_codex_review_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x)) y else x

  captured <- c(
    "mirror_directory_to_local_workspace",
    "cc_select_input_files",
    "cc_scan_directory_bounded",
    "cc_plan_output_sync",
    "cc_apply_output_sync_plan",
    "cc_process_run_outputs",
    "cc_prepare_run_workspace",
    "cc_dispatch_run_preparation",
    "cc_run_prepare_worker_globals",
    "cc_run_output_worker_globals",
    "prepare_claude_code_document_context"
  )
  for (name in captured) env[[name]] <- function(...) list()

  env$.cc_prepare_worker_cache <- new.env(parent = emptyenv())
  env$.cc_completion_worker_cache <- new.env(parent = emptyenv())

  source(
    file.path(repo_root, "R", "helpers_claude_code_codex_runtime_fixes.R"),
    encoding = "UTF-8",
    local = env
  )
  source(
    file.path(repo_root, "R", "helpers_claude_code_codex_output_fixes.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

test_that("Codex hardening files parse and loader references both layers", {
  repo_root <- resolve_repo_root_for_tests()
  files <- c(
    file.path(repo_root, "R", "helpers_claude_code_codex_runtime_fixes.R"),
    file.path(repo_root, "R", "helpers_claude_code_codex_output_fixes.R")
  )
  expect_silent(lapply(files, parse))

  loader <- paste(readLines(
    file.path(repo_root, "R", "server_observers_misc.R"), warn = FALSE
  ), collapse = "\n")
  expect_match(loader, "helpers_claude_code_codex_runtime_fixes\\.R")
  expect_match(loader, "helpers_claude_code_codex_output_fixes\\.R")
  expect_match(loader, "load_claude_code_codex_review_fixes\\(\\)")
})

test_that("ordinary local workdirs are always isolated and unresolved paths fail", {
  env <- .cc_codex_review_env()
  source_dir <- withr::local_tempdir()
  runtime_base <- withr::local_tempdir()

  env$resolve_claude_runtime_source_dir <- function(path) normalizePath(path, winslash = "/")
  env$cc_scan_source_workdir <- function(source_dir, limits = NULL) {
    list(ok = TRUE, root = source_dir, files = character(0), file_sizes = numeric(0))
  }
  env$cc_evaluate_workdir_preflight <- function(...) list(blocked = FALSE, limited = FALSE)
  env$.cc_runtime_workdir_reusable <- function(...) FALSE
  env$cc_runtime_user_dir <- function(user_id = NULL) runtime_base
  env$.cc_runtime_workdir_token <- function(runtime_token = NULL) "run-test"
  env$cc_runtime_ensure_layout <- function(layout) {
    invisible(lapply(layout, dir.create, recursive = TRUE, showWarnings = FALSE))
    layout
  }
  env$mirror_directory_to_local_workspace <- function(...) {
    list(ok = TRUE, selection = list(files = character(0)), copy = list())
  }
  env$.cc_runtime_prepare_result <- function(workdir, source_dir = NULL,
                                             mirrored = FALSE, reused = FALSE,
                                             layout = NULL, selection = NULL,
                                             preflight = NULL, scan = NULL) {
    list(runtime_workdir = workdir, source_workdir = source_dir,
         mirrored = mirrored, reused = reused, layout = layout,
         selection = selection, preflight = preflight, scan = scan)
  }

  result <- env$prepare_claude_runtime_workdir(source_dir, user_id = 7L)
  expect_true(isTRUE(result$mirrored))
  expect_false(identical(
    normalizePath(result$runtime_workdir, winslash = "/", mustWork = FALSE),
    normalizePath(source_dir, winslash = "/", mustWork = FALSE)
  ))

  env$resolve_claude_runtime_source_dir <- function(path) ""
  expect_error(
    env$prepare_claude_runtime_workdir(source_dir, user_id = 7L),
    "çözülemedi|erişilemiyor"
  )
})

test_that("reused input promotion removes stale files as one tree swap", {
  env <- .cc_codex_review_env()
  source_dir <- withr::local_tempdir()
  runtime <- withr::local_tempdir()
  target <- file.path(runtime, "input")
  dir.create(target)
  writeLines("stale", file.path(target, "stale.txt"), useBytes = TRUE)

  env$.cc_codex_original_mirror_directory_to_local_workspace <- function(
      source_dir, target_dir, ...) {
    dir.create(target_dir, recursive = TRUE, showWarnings = FALSE)
    fresh <- file.path(target_dir, "fresh.txt")
    writeLines("fresh", fresh, useBytes = TRUE)
    list(
      ok = TRUE,
      selection = list(files = "fresh.txt"),
      copy = list(
        copied = fresh,
        results = list(list(dest_path = fresh, success = TRUE))
      )
    )
  }

  result <- env$mirror_directory_to_local_workspace(
    source_dir, target, ownership_guard = function() invisible(TRUE)
  )
  expect_true(isTRUE(result$ok))
  expect_true(file.exists(file.path(target, "fresh.txt")))
  expect_false(file.exists(file.path(target, "stale.txt")))
  expect_true(all(startsWith(result$copy$copied, normalizePath(target, winslash = "/"))))
})

test_that("runtime ownership marker is atomic and missing markers fail closed", {
  env <- .cc_codex_review_env()
  runtime <- withr::local_tempdir()
  env$cc_runtime_owner_file <- function(runtime_workdir) {
    file.path(runtime_workdir, "metadata", "runtime-owner")
  }

  marker <- env$cc_claim_runtime_ownership(runtime, "request-a")
  expect_true(nzchar(marker))
  expect_true(env$cc_runtime_ownership_is(runtime, "request-a"))
  expect_false(env$cc_runtime_ownership_is(runtime, "request-b"))

  unlink(marker, force = TRUE)
  expect_false(env$cc_runtime_ownership_is(runtime, "request-a"))
})

test_that("dispatch refuses reused runtime when ownership cannot be claimed", {
  env <- .cc_codex_review_env()
  called <- FALSE
  failed <- FALSE
  env$.cc_codex_original_cc_dispatch_run_preparation <- function(ctx) {
    called <<- TRUE
    TRUE
  }
  env$cc_claim_runtime_ownership <- function(...) ""
  env$cc_fail_run_preparation <- function(...) {
    failed <<- TRUE
    TRUE
  }
  rv <- new.env(parent = emptyenv())
  rv$active_runtime_source <- "source"
  rv$active_runtime_workdir <- "runtime"

  result <- env$cc_dispatch_run_preparation(list(
    rv = rv, workdir = "source", run_request_id = "request-a"
  ))
  expect_false(isTRUE(result))
  expect_true(failed)
  expect_false(called)
})

test_that("unknown input sizes fail closed for scans and requested files", {
  env <- .cc_codex_review_env()
  env$.cc_codex_original_cc_scan_directory_bounded <- function(...) {
    list(ok = TRUE, files = "unknown.bin", errors = character(0), skipped = character(0))
  }
  env$file.info <- function(...) data.frame(size = NA_real_)

  scan <- env$cc_scan_directory_bounded("unused")
  expect_false(isTRUE(scan$ok))
  expect_match(paste(scan$errors, collapse = " "), "boyutu belirlenemedi")

  env$cc_scan_relative_paths <- function(files, root) basename(files)
  env$cc_extract_prompt_file_mentions <- function(prompt) "unknown.bin"
  env$.cc_prepare_mention_matches <- function(files, relatives, mentions) {
    basename(files) %in% basename(mentions)
  }
  env$.cc_codex_original_cc_select_input_files <- function(...) {
    list(
      files = "unknown.bin", relatives = "unknown.bin", total_bytes = 0,
      selection_mode = "prompt", skipped = character(0),
      required_skipped = character(0), truncated = FALSE
    )
  }
  selected <- env$cc_select_input_files(
    prompt = "unknown.bin dosyasını kullan",
    files = "unknown.bin",
    file_sizes = NA_real_,
    root = "."
  )
  expect_length(selected$files, 0L)
  expect_true("unknown.bin" %in% selected$required_skipped)
})

test_that("case-sensitive snapshots and document relative paths are preserved", {
  env <- .cc_codex_review_env()
  paths <- c("/tmp/Report.txt", "/tmp/report.txt")
  env$canonicalize_claude_code_file_path <- identity
  deduped <- env$deduplicate_claude_code_file_paths(paths)
  expect_length(deduped, if (.Platform$OS.type == "windows") 1L else 2L)

  root <- withr::local_tempdir()
  dir.create(file.path(root, "reports"))
  a <- file.path(root, "reports", "Q1.pdf")
  b <- file.path(root, "reports", "Q2.pdf")
  writeLines("a", a, useBytes = TRUE)
  writeLines("b", b, useBytes = TRUE)
  env$cc_runtime_limit <- function(name, default, limits = NULL) {
    value <- if (is.list(limits)) limits[[name]] else NULL
    if (is.null(value)) default else value
  }
  env$cc_extract_prompt_file_mentions <- function(prompt) c("reports/Q1.pdf", "reports/Q2.pdf")

  selection <- env$cc_select_documents_for_request(
    prompt = "iki raporu oku",
    documents = c(a, b),
    limits = list(max_documents = 2L)
  )
  expect_identical(selection$selection_mode, "prompt")
  expect_setequal(selection$files, c(a, b))

  expect_error(
    env$cc_select_documents_for_request(
      prompt = "iki raporu oku",
      documents = c(a, b),
      limits = list(max_documents = 1L)
    ),
    "Açıkça istenen dokümanların tümü"
  )
})

test_that("snapshot failures propagate and mirrored scans exclude input", {
  env <- .cc_codex_review_env()
  root <- withr::local_tempdir()
  seen_excludes <- NULL
  env$cc_runtime_limit <- function(name, default, limits = NULL) default
  env$cc_scan_default_excluded_dirs <- function() character(0)
  env$cc_scan_default_excluded_rel_paths <- function() character(0)
  env$cc_scan_directory_bounded <- function(..., exclude_rel_paths = character(0)) {
    seen_excludes <<- exclude_rel_paths
    list(ok = FALSE, files = character(0), errors = "scanner failed")
  }
  expect_error(
    env$cc_snapshot_run_output_area(root, mirrored = TRUE),
    "scanner failed|anlık görüntüsü"
  )
  expect_true("input" %in% seen_excludes)
})

test_that("unknown outputs are rejected and missing runtime roots abort processing", {
  env <- .cc_codex_review_env()
  env$cc_runtime_limit <- function(name, default, limits = NULL) default
  filtered <- env$cc_filter_download_candidates(file.path(tempdir(), "missing-output.bin"))
  expect_length(filtered$paths, 0L)
  expect_length(filtered$rejected_size, 1L)

  expect_error(
    env$cc_process_run_outputs(list(runtime_workdir = file.path(tempdir(), "missing-runtime"))),
    "runtime dizini"
  )
})

test_that("output promotion rolls back when cancellation arrives during staging", {
  env <- .cc_codex_review_env()
  source_root <- withr::local_tempdir()
  runtime <- withr::local_tempdir()
  src <- file.path(runtime, "new.txt")
  dest <- file.path(source_root, "new.txt")
  guard <- file.path(runtime, "active.guard")
  writeLines("new", src, useBytes = TRUE)
  writeLines("old", dest, useBytes = TRUE)
  file.create(guard)

  env$cc_output_sync_skipped_results <- function(plan) list()
  env$.cc_scan_norm <- function(path) normalizePath(path, winslash = "/", mustWork = FALSE)
  env$.cc_scan_key <- function(path) if (.Platform$OS.type == "windows") tolower(path) else path
  env$file.copy <- function(from, to, ...) {
    ok <- base::file.copy(from, to, ...)
    unlink(guard, force = TRUE)
    ok
  }

  result <- env$cc_apply_output_sync_plan(list(
    source_workdir = source_root,
    skipped_approved = list(),
    items = list(list(source_path = src, dest_path = dest, size = file.info(src)$size))
  ), active_guard = guard)

  expect_false(isTRUE(result[[1]]$success))
  expect_identical(readLines(dest, warn = FALSE), "old")
})

test_that("partial sync failures remain warnings and output deadline has cleanup", {
  env <- .cc_codex_review_env()
  env$cc_output_sync_failures <- function(outputs) outputs$sync_results
  messages <- list()
  session <- new.env(parent = emptyenv())
  session$sendCustomMessage <- function(type, message) {
    messages[[length(messages) + 1L]] <<- list(type = type, message = message)
  }
  ctx <- list(session = session, ns = identity)
  result <- env$cc_report_output_sync_failure(ctx, list(sync_results = list(list(
    success = FALSE, dest_path = "missing.txt"
  ))))
  expect_false(isTRUE(result))
  expect_length(messages, 1L)
  expect_identical(messages[[1]]$message$type, "warning")

  dispatch_body <- paste(deparse(body(env$cc_dispatch_run_output_processing)), collapse = "\n")
  expect_match(dispatch_body, "cancel_deadline")
  expect_match(dispatch_body, "dispatch_error <- tryCatch", fixed = TRUE)
  expect_match(dispatch_body, "runtime_lease", fixed = TRUE)
})

# Yeniden kullanılan runtime hazırlık boyunca stale temizliğinden korunmalıdır.
test_that("yeniden kullanılan runtime hazırlık başlamadan önce lease alır", {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x)) y else x
  env$log_info <- env$log_warn <- env$log_error <- function(...) invisible(NULL)
  env$CLAUDE_CODE_LOG_PREFIX <- "[TEST]"
  env$normalize_mcp_path <- function(path, must_exist = FALSE) {
    normalizePath(path, winslash = "/", mustWork = must_exist)
  }

  for (dosya in c(
    "config_claude_code.R",
    "helpers_claude_code_bounded_scan.R",
    "helpers_claude_code_runtime_prepare.R",
    "helpers_claude_code_output_sync.R",
    "helpers_claude_code_runtime_resolver.R",
    "helpers_claude_code_runtime_workdir.R",
    "helpers_claude_code_run_prepare_task.R"
  )) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = env)
  }

  runtime_dir <- file.path(tempdir(), "claude_code_runtime", "user_7", "run_onceki")
  layout <- env$cc_runtime_ensure_layout(list(
    root = runtime_dir,
    input = file.path(runtime_dir, "input"),
    output = file.path(runtime_dir, "output"),
    metadata = file.path(runtime_dir, "metadata"),
    document_support = file.path(runtime_dir, "document_support")
  ))
  source_dir <- withr::local_tempdir()
  writeLines("veri", file.path(source_dir, "girdi.txt"), useBytes = TRUE)
  lease_copy_sirasinda_vardi <- FALSE

  env$prepare_claude_runtime_workdir <- function(...) {
    leases <- list.files(
      layout$metadata,
      pattern = "^active-run-.*\\.lease$",
      full.names = TRUE
    )
    lease_copy_sirasinda_vardi <<- length(leases) == 1L
    list(
      mirrored = TRUE, reused = TRUE, layout = layout,
      source_workdir = source_dir, runtime_workdir = layout$root,
      selection = list(files = character(0), total_bytes = 0),
      preflight = list(limited = FALSE, message = ""), scan_metrics = list()
    )
  }
  env$prepare_claude_code_document_context <- function(...) list(
    prompt = "incele", text_sidecars_ready = FALSE, support_dir = ""
  )
  env$cc_snapshot_run_output_area <- function(...) list()
  env$cc_cleanup_stale_runtime_dirs <- function(...) invisible(0L)
  env$cc_cleanup_stale_document_support_dirs <- function(...) invisible(0L)

  sonuc <- env$cc_prepare_run_workspace(list(
    workdir = source_dir, user_id = 7L, request_id = "req-reuse",
    existing_runtime_workdir = layout$root, prompt = "incele",
    explicit_files = character(0), limits = list()
  ))

  expect_true(lease_copy_sirasinda_vardi)
  expect_true(file.exists(sonuc$runtime_lease))
  unlink(sonuc$runtime_lease, force = TRUE)
})

test_that("yeniden kullanılan runtime snapshot hatasında çalıştırmayı durdurur", {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x)) y else x
  env$log_info <- env$log_warn <- env$log_error <- function(...) invisible(NULL)
  env$CLAUDE_CODE_LOG_PREFIX <- "[TEST]"
  env$normalize_mcp_path <- function(path, must_exist = FALSE) {
    normalizePath(path, winslash = "/", mustWork = must_exist)
  }

  for (dosya in c(
    "config_claude_code.R",
    "helpers_claude_code_bounded_scan.R",
    "helpers_claude_code_runtime_prepare.R",
    "helpers_claude_code_output_sync.R",
    "helpers_claude_code_runtime_resolver.R",
    "helpers_claude_code_runtime_workdir.R",
    "helpers_claude_code_run_prepare_task.R"
  )) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = env)
  }

  runtime_dir <- file.path(tempdir(), "claude_code_runtime", "user_8", "run_onceki")
  layout <- env$cc_runtime_ensure_layout(list(
    root = runtime_dir,
    input = file.path(runtime_dir, "input"),
    output = file.path(runtime_dir, "output"),
    metadata = file.path(runtime_dir, "metadata"),
    document_support = file.path(runtime_dir, "document_support")
  ))
  source_dir <- withr::local_tempdir()

  env$prepare_claude_runtime_workdir <- function(...) list(
    mirrored = TRUE, reused = TRUE, layout = layout,
    source_workdir = source_dir, runtime_workdir = layout$root,
    selection = list(files = character(0), total_bytes = 0),
    preflight = list(limited = FALSE, message = ""), scan_metrics = list()
  )
  env$prepare_claude_code_document_context <- function(...) list(
    prompt = "incele", text_sidecars_ready = FALSE, support_dir = ""
  )
  env$cc_snapshot_run_output_area <- function(...) {
    stop("snapshot okunamadı", call. = FALSE)
  }

  expect_error(
    env$cc_prepare_run_workspace(list(
      workdir = source_dir, user_id = 8L, request_id = "req-snapshot-hata",
      existing_runtime_workdir = layout$root, prompt = "incele",
      explicit_files = character(0), limits = list()
    )),
    "snapshot okunamadı",
    fixed = TRUE
  )

  leases <- list.files(layout$metadata, pattern = "^active-run-.*\\.lease$")
  expect_length(leases, 0L)
})

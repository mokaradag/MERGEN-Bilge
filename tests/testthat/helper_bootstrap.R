Sys.setenv(
  MERGEN_DISABLE_FUTURES = "true",
  MERGEN_RUN_APP = "false"
)

if (!exists("%||%")) {
  `%||%` <- function(x, y) {
    if (is.null(x)) y else x
  }
}

if (!exists("log_info"))  log_info  <- function(...) invisible(NULL)
if (!exists("log_warn"))  log_warn  <- function(...) invisible(NULL)
if (!exists("log_error")) log_error <- function(...) invisible(NULL)

if (!exists("path_exists_relaxed")) {
  path_exists_relaxed <- function(path) {
    isTRUE(file.exists(path)) || isTRUE(dir.exists(path))
  }
}

resolve_repo_root_for_tests <- function() {
  candidates <- c(".", "..", "../..")

  for (cand in candidates) {
    app_path <- file.path(cand, "app.R")
    r_dir <- file.path(cand, "R")

    if (file.exists(app_path) && dir.exists(r_dir)) {
      return(normalizePath(cand, winslash = "/", mustWork = TRUE))
    }
  }

  stop("Test helper repo kökünü bulamadı. Çalışma dizinini kontrol edin.")
}

.repo_root <- resolve_repo_root_for_tests()

source(file.path(.repo_root, "R", "utils_safe_source.R"), encoding = "UTF-8", local = globalenv())
source(file.path(.repo_root, "R", "helpers_worker_monitor.R"), encoding = "UTF-8", local = globalenv())
source(file.path(.repo_root, "R", "helpers_database.R"), encoding = "UTF-8", local = globalenv())
source(file.path(.repo_root, "R", "utils_file_index.R"), encoding = "UTF-8", local = globalenv())
source(file.path(.repo_root, "R", "utils_rate_limiter.R"), encoding = "UTF-8", local = globalenv())
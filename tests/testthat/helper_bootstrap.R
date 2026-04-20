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

source("R/utils_safe_source.R", encoding = "UTF-8", local = globalenv())
source("R/helpers_worker_monitor.R", encoding = "UTF-8", local = globalenv())
source("R/helpers_database.R", encoding = "UTF-8", local = globalenv())
source("R/utils_file_index.R", encoding = "UTF-8", local = globalenv())
source("R/utils_rate_limiter.R", encoding = "UTF-8", local = globalenv())
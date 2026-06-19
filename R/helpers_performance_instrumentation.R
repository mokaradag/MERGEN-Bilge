# ==============================================================================
# Dosya Yolu: R/helpers_performance_instrumentation.R
# Açıklama: Hafif, sır-redakteli performans ölçüm yardımcıları.
# ==============================================================================

mergen_perf_enabled <- function() {
  value <- Sys.getenv("MERGEN_PERF_LOG", unset = "")
  if (!nzchar(value)) {
    return(isTRUE(getOption("mergen.perf_log", FALSE)))
  }

  tolower(trimws(value)) %in% c("1", "true", "t", "yes", "y", "on")
}

mergen_perf_now <- function() {
  proc.time()[["elapsed"]]
}

mergen_perf_elapsed_ms <- function(start) {
  elapsed <- (mergen_perf_now() - as.numeric(start)[1]) * 1000
  if (!is.finite(elapsed) || elapsed < 0) elapsed <- NA_real_
  round(elapsed, 1)
}

mergen_perf_safe_field <- function(x, max_chars = 80L) {
  if (is.null(x) || length(x) == 0L) return("")
  value <- as.character(x)[1]
  if (is.na(value)) return("")
  value <- gsub("[\r\n\t]+", " ", value, perl = TRUE)
  value <- substr(value, 1L, max_chars)
  if (exists("redact_sensitive_text", mode = "function", inherits = TRUE)) {
    value <- redact_sensitive_text(value)
  }
  value
}

mergen_perf_log <- function(event, start = NULL, fields = list(), level = "info") {
  if (!mergen_perf_enabled()) return(invisible(NULL))

  elapsed_part <- ""
  if (!is.null(start)) {
    elapsed_part <- sprintf(" elapsed_ms=%s", as.character(mergen_perf_elapsed_ms(start)))
  }

  field_part <- ""
  if (length(fields) > 0L) {
    keys <- names(fields)
    if (is.null(keys)) keys <- rep("field", length(fields))
    safe_pairs <- vapply(seq_along(fields), function(i) {
      key <- gsub("[^A-Za-z0-9_.-]", "_", as.character(keys[[i]]))
      sprintf("%s=%s", key, mergen_perf_safe_field(fields[[i]]))
    }, character(1))
    field_part <- paste0(" ", paste(safe_pairs, collapse = " "))
  }

  msg <- sprintf(
    "[PERF] event=%s%s%s",
    mergen_perf_safe_field(event, max_chars = 60L),
    elapsed_part,
    field_part
  )

  log_fun <- if (identical(level, "warn")) log_warn else log_info
  try(log_fun(msg), silent = TRUE)
  invisible(NULL)
}

mergen_perf_time <- function(event, expr, fields = list(), level = "info") {
  start <- mergen_perf_now()
  ok <- FALSE
  on.exit({
    extra <- fields
    extra$success <- ok
    mergen_perf_log(event, start = start, fields = extra, level = level)
  }, add = TRUE)

  value <- force(expr)
  ok <- TRUE
  value
}

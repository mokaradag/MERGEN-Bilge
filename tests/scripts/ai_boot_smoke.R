#!/usr/bin/env Rscript

# ==============================================================================
# Dosya Yolu: tests/scripts/ai_boot_smoke.R
# Açıklama:
#   Shiny uygulamasını geçici bir portta başlatır ve HTTP üzerinden temel boot
#   smoke testi yapar. Ağ, gerçek LLM veya gerçek DB çağrısı yapmayı hedeflemez.
# ==============================================================================

options(warn = 1)

args <- commandArgs(trailingOnly = TRUE)

arg_value <- function(name, default = NULL) {
  prefix <- paste0(name, "=")
  direct <- args[startsWith(args, prefix)]
  if (length(direct) > 0L) return(sub(prefix, "", direct[[1]], fixed = TRUE))

  pos <- match(name, args)
  if (!is.na(pos) && pos < length(args)) return(args[[pos + 1L]])

  default
}

find_repo_root <- function() {
  candidates <- c(".", "..", "../..", "../../..")
  for (cand in candidates) {
    if (file.exists(file.path(cand, "app.R")) &&
        dir.exists(file.path(cand, "R"))) {
      return(normalizePath(cand, winslash = "/", mustWork = TRUE))
    }
  }
  stop("Repo root bulunamadı.", call. = FALSE)
}

repo_root <- find_repo_root()
setwd(repo_root)

rscript <- Sys.which("Rscript")
if (!nzchar(rscript)) {
  stop("Rscript bulunamadı.", call. = FALSE)
}

port <- suppressWarnings(as.integer(arg_value("--port", NA)))
if (is.na(port) || port < 1024L || port > 65535L) {
  set.seed(as.integer(Sys.time()) %% 100000L)
  port <- sample(18000:24000, 1L)
}

timeout_seconds <- suppressWarnings(as.integer(arg_value("--timeout", "90")))
if (is.na(timeout_seconds) || timeout_seconds < 10L) {
  timeout_seconds <- 90L
}

artifact_dir <- arg_value("--artifact-dir", file.path("artifacts", "ai-validation", "boot-smoke"))
dir.create(artifact_dir, recursive = TRUE, showWarnings = FALSE)

log_file <- file.path(artifact_dir, sprintf("shiny-boot-%s.log", port))
url <- sprintf("http://127.0.0.1:%d", port)

cat("== MERGEN Shiny boot smoke ==\n")
cat(sprintf("Repo root: %s\n", repo_root))
cat(sprintf("Port: %d\n", port))
cat(sprintf("URL: %s\n", url))
cat(sprintf("Timeout: %ds\n", timeout_seconds))
cat(sprintf("Log: %s\n", log_file))

if (!requireNamespace("processx", quietly = TRUE)) {
  stop(
    "processx paketi gerekli. Önce Rscript tests/scripts/ci_install_packages.R çalıştırın.",
    call. = FALSE
  )
}

expr <- paste(
  "Sys.setenv(",
  "MERGEN_RUN_APP='false',",
  "MERGEN_DISABLE_FUTURES='true',",
  "TZ='UTC',",
  "LOCAL_LLM_ENDPOINT=ifelse(nzchar(Sys.getenv('LOCAL_LLM_ENDPOINT')), Sys.getenv('LOCAL_LLM_ENDPOINT'), 'http://test.local/v1'),",
  "DB_DSN=ifelse(nzchar(Sys.getenv('DB_DSN')), Sys.getenv('DB_DSN'), 'test-dsn'),",
  "AI_KEYS_MASTER=ifelse(nzchar(Sys.getenv('AI_KEYS_MASTER')), Sys.getenv('AI_KEYS_MASTER'), 'test-master-key-0123456789')",
  ");",
  "source('app.R', encoding='UTF-8');",
  sprintf(
    "run_mergen_app(host='127.0.0.1', port=%dL, launch.browser=FALSE, quiet=FALSE)",
    port
  )
)

px <- processx::process$new(
  command = rscript,
  args = c("-e", expr),
  stdout = log_file,
  stderr = log_file,
  supervise = TRUE
)

cleanup <- function() {
  if (!is.null(px) && px$is_alive()) {
    try(px$kill_tree(), silent = TRUE)
  }
}
on.exit(cleanup(), add = TRUE)

read_url <- function(target) {
  con <- NULL
  tryCatch(
    {
      con <- url(target, open = "rb", blocking = TRUE)
      raw <- readBin(con, what = "raw", n = 256 * 1024)
      if (length(raw) == 0L) return("")
      txt <- rawToChar(raw)
      enc2utf8(txt)
    },
    error = function(e) {
      ""
    },
    finally = {
      if (!is.null(con)) try(close(con), silent = TRUE)
    }
  )
}

tail_log <- function(n = 120L) {
  if (!file.exists(log_file)) return(character(0))
  lines <- readLines(log_file, warn = FALSE, encoding = "UTF-8")
  tail(lines, n)
}

start <- Sys.time()
ok <- FALSE
last_body <- ""

repeat {
  elapsed <- as.numeric(difftime(Sys.time(), start, units = "secs"))

  if (!px$is_alive()) {
    status <- px$get_exit_status()
    cat(sprintf("Shiny process exited early with status: %s\n", as.character(status)))
    cat("\n--- log tail ---\n")
    cat(paste(tail_log(), collapse = "\n"))
    cat("\n--- end log tail ---\n")
    quit(status = 1)
  }

  body <- read_url(url)
  if (nzchar(body)) {
    last_body <- body

    looks_like_html <- grepl("<html|<!DOCTYPE|shiny|MERGEN|Bilge", body, ignore.case = TRUE)

    if (isTRUE(looks_like_html)) {
      ok <- TRUE
      break
    }
  }

  if (elapsed > timeout_seconds) {
    break
  }

  Sys.sleep(1)
}

if (!isTRUE(ok)) {
  body_file <- file.path(artifact_dir, sprintf("last-http-body-%s.html", port))
  writeLines(last_body, body_file, useBytes = TRUE)

  cat(sprintf("Boot smoke failed after %ds.\n", timeout_seconds))
  cat(sprintf("Last HTTP body written to: %s\n", body_file))
  cat("\n--- log tail ---\n")
  cat(paste(tail_log(), collapse = "\n"))
  cat("\n--- end log tail ---\n")
  quit(status = 1)
}

cat("OK: Shiny app responded over HTTP and looked like a valid app page.\n")
quit(status = 0)
#!/usr/bin/env Rscript

# ==============================================================================
# Dosya Yolu: tests/scripts/ai_browser_ux_smoke.R
# Açıklama:
#   MERGEN UX smoke harness'ını gerçek bir headless tarayıcıda çalıştırır.
#   Chrome/Chromium/Edge yoksa varsayılan olarak SKIP olur; --require-browser
#   veya MERGEN_REQUIRE_BROWSER_UX_SMOKE=true ile bloklayıcı yapılabilir.
#
#   Sıkılaştırılmış uygulama kuralı: MERGEN_BROWSER_BIN açıkça verilmişse
#   ortam tarayıcı desteği BİLDİRMİŞ sayılır; bu durumda sessiz SKIP devre
#   dışı kalır (require modu otomatik açılır) ve kullanılamayan bir
#   MERGEN_BROWSER_BIN yolu geç processx hatası yerine erken ve açık bir
#   hata ile bloklar.
#
# Not:
#   CDN, runtime download, chromote, Selenium, Playwright veya npm kullanmaz.
#   Yalnızca yerelde zaten kurulu bir tarayıcı binary'sini processx ile çağırır.
# ==============================================================================

options(warn = 1)

args <- commandArgs(trailingOnly = TRUE)

arg_value <- function(name, default = NULL) {
  prefix <- paste0(name, "=")
  direct <- args[startsWith(args, prefix)]
  if (length(direct) > 0L) {
    return(sub(prefix, "", direct[[1]], fixed = TRUE))
  }

  pos <- match(name, args)
  if (!is.na(pos) && pos < length(args)) {
    return(args[[pos + 1L]])
  }

  default
}

has_flag <- function(name) {
  name %in% args
}

env_flag_true <- function(name) {
  identical(tolower(Sys.getenv(name, unset = "false")), "true")
}

find_repo_root <- function() {
  candidates <- c(".", "..", "../..", "../../..")

  for (cand in candidates) {
    if (file.exists(file.path(cand, "app.R")) &&
        dir.exists(file.path(cand, "R")) &&
        dir.exists(file.path(cand, "www", "smoke"))) {
      return(normalizePath(cand, winslash = "/", mustWork = TRUE))
    }
  }

  stop("Repo root bulunamadı. Bu betiği repo içinde çalıştırın.", call. = FALSE)
}

repo_root <- find_repo_root()
setwd(repo_root)

rscript <- file.path(R.home("bin"), "Rscript")
if (.Platform$OS.type == "windows") {
  rscript <- paste0(rscript, ".exe")
}

if (!file.exists(rscript)) {
  rscript <- Sys.which("Rscript")
}

if (!nzchar(rscript) || !file.exists(rscript)) {
  stop("Rscript bulunamadı.", call. = FALSE)
}

# MERGEN_BROWSER_BIN açıkça ayarlanmışsa ortam tarayıcı desteği bildirmiştir;
# sessiz SKIP bu durumda bir yanlış-yapılandırma tuzağı olur. Bu yüzden
# explicit binary yapılandırması require modunu otomatik etkinleştirir.
browser_bin_env <- Sys.getenv("MERGEN_BROWSER_BIN", unset = "")
browser_bin_explicit <- nzchar(browser_bin_env)

require_browser <- has_flag("--require-browser") ||
  env_flag_true("MERGEN_REQUIRE_BROWSER_UX_SMOKE") ||
  browser_bin_explicit

port <- suppressWarnings(as.integer(arg_value("--port", NA)))
if (is.na(port) || port < 1024L || port > 65535L) {
  set.seed(as.integer(Sys.time()) %% 100000L)
  port <- sample(24001:29000, 1L)
}

timeout_seconds <- suppressWarnings(as.integer(arg_value("--timeout", "150")))
if (is.na(timeout_seconds) || timeout_seconds < 30L) {
  timeout_seconds <- 150L
}

virtual_time_budget_ms <- suppressWarnings(as.integer(
  arg_value("--virtual-time-budget-ms", Sys.getenv("MERGEN_BROWSER_UX_VIRTUAL_TIME_MS", "120000"))
))
if (is.na(virtual_time_budget_ms) || virtual_time_budget_ms < 10000L) {
  virtual_time_budget_ms <- 120000L
}

browser_timeout_seconds <- suppressWarnings(as.integer(
  arg_value("--browser-timeout", as.character(max(90L, ceiling(virtual_time_budget_ms / 1000) + 45L)))
))
if (is.na(browser_timeout_seconds) || browser_timeout_seconds < 30L) {
  browser_timeout_seconds <- max(90L, ceiling(virtual_time_budget_ms / 1000) + 45L)
}

artifact_dir <- arg_value(
  "--artifact-dir",
  file.path("artifacts", "ai-validation", "browser-ux-smoke")
)
dir.create(artifact_dir, recursive = TRUE, showWarnings = FALSE)

log_file <- file.path(artifact_dir, sprintf("shiny-browser-ux-%s.log", port))
dom_file <- file.path(artifact_dir, sprintf("browser-ux-dom-%s.html", port))
stderr_file <- file.path(artifact_dir, sprintf("browser-ux-stderr-%s.log", port))

url <- sprintf("http://127.0.0.1:%d", port)

external_base_url <- trimws(Sys.getenv("MERGEN_BROWSER_UX_BASE_URL", unset = ""))
use_external_app <- nzchar(external_base_url)

if (isTRUE(use_external_app)) {
  url <- sub("/+$", "", external_base_url)
}

smoke_url <- sprintf("%s/smoke/ux-smoke.html", url)

cat("== MERGEN browser UX smoke ==\n")
cat(sprintf("Repo root: %s\n", repo_root))
cat(sprintf("Port: %d\n", port))
cat(sprintf("Smoke URL: %s\n", smoke_url))
cat(sprintf("Timeout: %ds\n", timeout_seconds))
cat(sprintf("Browser timeout: %ds\n", browser_timeout_seconds))
cat(sprintf("Virtual time budget: %dms\n", virtual_time_budget_ms))
cat(sprintf("Log: %s\n", log_file))
cat(sprintf("DOM artifact: %s\n", dom_file))
cat(sprintf("Require browser: %s\n", require_browser))
cat(sprintf("Explicit MERGEN_BROWSER_BIN: %s\n", browser_bin_explicit))

if (!requireNamespace("processx", quietly = TRUE)) {
  stop(
    "processx paketi gerekli. Önce Rscript tests/scripts/ci_install_packages.R çalıştırın.",
    call. = FALSE
  )
}

find_browser_bin <- function() {
  env_bin <- Sys.getenv("MERGEN_BROWSER_BIN", unset = "")
  if (nzchar(env_bin)) {
    # Açık yapılandırma doğrulanır: var olmayan/erişilemeyen bir binary geç
    # ve kafa karıştırıcı bir processx hatası yerine erken ve net bloklar.
    resolved_bin <- env_bin

    if (!file.exists(resolved_bin)) {
      resolved_bin <- unname(Sys.which(env_bin))
    }

    if (!nzchar(resolved_bin) || !file.exists(resolved_bin)) {
      stop(
        sprintf(
          "MERGEN_BROWSER_BIN kullanılamıyor (dosya veya PATH komutu bulunamadı): %s",
          env_bin
        ),
        call. = FALSE
      )
    }

    return(resolved_bin)
  }

  path_candidates <- c(
    "google-chrome",
    "google-chrome-stable",
    "chromium",
    "chromium-browser",
    "microsoft-edge",
    "microsoft-edge-stable",
    "msedge",
    "chrome",
    "brave-browser"
  )

  found <- Sys.which(path_candidates)
  found <- unname(found[nzchar(found)])
  if (length(found) > 0L) {
    return(found[[1]])
  }

  if (.Platform$OS.type == "windows") {
    win_candidates <- c(
      file.path(Sys.getenv("PROGRAMFILES"), "Google", "Chrome", "Application", "chrome.exe"),
      file.path(Sys.getenv("PROGRAMFILES(X86)"), "Google", "Chrome", "Application", "chrome.exe"),
      file.path(Sys.getenv("LOCALAPPDATA"), "Google", "Chrome", "Application", "chrome.exe"),
      file.path(Sys.getenv("PROGRAMFILES"), "Microsoft", "Edge", "Application", "msedge.exe"),
      file.path(Sys.getenv("PROGRAMFILES(X86)"), "Microsoft", "Edge", "Application", "msedge.exe"),
      file.path(Sys.getenv("LOCALAPPDATA"), "Microsoft", "Edge", "Application", "msedge.exe")
    )

    win_candidates <- win_candidates[nzchar(win_candidates)]
    hit <- win_candidates[file.exists(win_candidates)]
    if (length(hit) > 0L) {
      return(normalizePath(hit[[1]], winslash = "/", mustWork = TRUE))
    }
  }

  ""
}

browser_bin <- find_browser_bin()

if (!nzchar(browser_bin)) {
  msg <- paste(
    "SKIP: Chrome/Chromium/Edge binary bulunamadı.",
    "MERGEN_BROWSER_BIN ile tarayıcı yolu verilebilir.",
    "Bu skip yalnızca gerçek browser UX smoke içindir; statik contract testleri çalışmaya devam eder."
  )

  cat(msg, "\n")

  if (isTRUE(require_browser)) {
    stop(msg, call. = FALSE)
  }

  quit(status = 0)
}

cat(sprintf("Browser: %s\n", browser_bin))

px <- NULL

if (!isTRUE(use_external_app)) {
  expr <- paste(
    "Sys.setenv(",
    "MERGEN_RUN_APP='false',",
    "MERGEN_DISABLE_FUTURES='true',",
    "TZ='UTC',",
    "LOCAL_LLM_ENDPOINT=ifelse(nzchar(Sys.getenv('LOCAL_LLM_ENDPOINT')), Sys.getenv('LOCAL_LLM_ENDPOINT'), 'http://test.local/v1'),",
    "DB_DSN=ifelse(nzchar(Sys.getenv('DB_DSN')), Sys.getenv('DB_DSN'), 'test-dsn'),",
    "AI_KEYS_MASTER=ifelse(nzchar(Sys.getenv('AI_KEYS_MASTER')), Sys.getenv('AI_KEYS_MASTER'), 'test-master-key-0123456789')",
    ");",
    "cat('SHINY_UX_RUNNER_START\\n');",
    "source('app.R', encoding='UTF-8');",
    "cat('SHINY_UX_RUNNER_BOOT_OK\\n');",
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
} else {
  cat(sprintf("Using externally running app: %s\n", url))
}

read_url <- function(target) {
  con <- NULL

  tryCatch(
    {
      con <- url(target, open = "rb", blocking = TRUE)
      raw <- readBin(con, what = "raw", n = 256 * 1024)
      if (length(raw) == 0L) {
        return("")
      }
      enc2utf8(rawToChar(raw))
    },
    error = function(e) {
      ""
    },
    finally = {
      if (!is.null(con)) {
        try(close(con), silent = TRUE)
      }
    }
  )
}

tail_log <- function(n = 120L) {
  if (!file.exists(log_file)) {
    return(character(0))
  }

  lines <- readLines(log_file, warn = FALSE, encoding = "UTF-8")
  tail(lines, n)
}

skip_or_fail_app_boot <- function(reason, status = NA_integer_) {
  prefix <- if (isTRUE(require_browser)) {
    "FAILED: Browser UX smoke uygulama HTTP boot aşamasında çalıştırılamadı."
  } else {
    "SKIP: Browser UX smoke uygulama HTTP boot aşamasında çalıştırılamadı."
  }

  suffix <- if (isTRUE(require_browser)) {
    "MERGEN_REQUIRE_BROWSER_UX_SMOKE=true olduğu için bu adım bloklayıcıdır."
  } else {
    "MERGEN_REQUIRE_BROWSER_UX_SMOKE=true değil; bu adım kanıt üretmeden atlanıyor."
  }

  msg <- paste(
    prefix,
    reason,
    if (!is.na(status)) sprintf("Shiny exit status: %s.", as.character(status)) else "",
    suffix
  )

  cat(msg, "\n")
  cat("\n--- log tail ---\n")
  cat(paste(tail_log(), collapse = "\n"))
  cat("\n--- end log tail ---\n")

  if (isTRUE(require_browser)) {
    quit(status = 1)
  }

  quit(status = 0)
}

wait_for_app <- function() {
  started <- Sys.time()
  last_body <- ""

  repeat {
    elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))

	if (!isTRUE(use_external_app) && !px$is_alive()) {
	  status <- px$get_exit_status()
	  cat(sprintf("Shiny process exited early with status: %s\n", as.character(status)))

	  skip_or_fail_app_boot(
		reason = "Shiny child process exited before the smoke page became reachable.",
		status = status
	  )
	}

    body <- read_url(url)
    if (nzchar(body)) {
      last_body <<- body

      if (grepl("<html|<!DOCTYPE|shiny|MERGEN|Bilge", body, ignore.case = TRUE)) {
        return(TRUE)
      }
    }

	if (elapsed > timeout_seconds) {
	  body_file <- file.path(artifact_dir, sprintf("last-http-body-%s.html", port))
	  writeLines(last_body, body_file, useBytes = TRUE)

	  cat(sprintf("App boot wait failed after %ds.\n", timeout_seconds))
	  cat(sprintf("Last HTTP body written to: %s\n", body_file))

	  skip_or_fail_app_boot(
		reason = sprintf("Shiny app did not respond within %ds.", timeout_seconds),
		status = NA_integer_
	  )
	}

    Sys.sleep(1)
  }
}

if (!wait_for_app()) {
  quit(status = 1)
}

profile_dir <- tempfile("mergen-browser-profile-")
dir.create(profile_dir, recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(profile_dir, recursive = TRUE, force = TRUE), add = TRUE)

run_browser_dump <- function(headless_arg) {
  browser_args <- c(
    headless_arg,
    "--disable-gpu",
    "--disable-dev-shm-usage",
    "--no-first-run",
    "--no-default-browser-check",
    "--autoplay-policy=no-user-gesture-required",
    paste0("--user-data-dir=", profile_dir),
    paste0("--virtual-time-budget=", virtual_time_budget_ms),
    "--dump-dom",
    smoke_url
  )

  cat(sprintf("Running browser with %s\n", headless_arg))

  result <- tryCatch(
    processx::run(
      command = browser_bin,
      args = browser_args,
      echo = FALSE,
      error_on_status = FALSE,
      timeout = browser_timeout_seconds
    ),
    error = function(e) {
      list(
        status = 124L,
        stdout = "",
        stderr = conditionMessage(e)
      )
    }
  )

  stdout <- result$stdout %||% ""
  stderr <- result$stderr %||% ""

  writeLines(stdout, con = dom_file, useBytes = TRUE)
  writeLines(stderr, con = stderr_file, useBytes = TRUE)

  list(
    status = as.integer(result$status %||% 0L),
    stdout = stdout,
    stderr = stderr,
    args = browser_args
  )
}

`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

result <- run_browser_dump("--headless=new")

if (!identical(result$status, 0L) &&
    grepl("headless=new|unknown|invalid|unrecognized", result$stderr, ignore.case = TRUE)) {
  cat("Retrying browser with legacy --headless flag.\n")
  result <- run_browser_dump("--headless")
}

combined_output <- paste(result$stdout, result$stderr, collapse = "\n")

if (grepl("UX_SMOKE_DONE:PASS", combined_output, fixed = TRUE)) {
  cat("OK: UX_SMOKE_DONE:PASS found in headless browser DOM output.\n")
  quit(status = 0)
}

if (grepl("UX_SMOKE_DONE:FAIL", combined_output, fixed = TRUE)) {
  cat("FAILED: UX_SMOKE_DONE:FAIL found in headless browser DOM output.\n")
} else {
  cat("FAILED: Browser ran but UX_SMOKE_DONE:PASS marker was not found.\n")
}

cat(sprintf("Browser status: %d\n", result$status))
cat(sprintf("DOM artifact: %s\n", dom_file))
cat(sprintf("Browser stderr artifact: %s\n", stderr_file))
cat("\n--- browser stderr tail ---\n")
stderr_lines <- strsplit(result$stderr %||% "", "\n", fixed = TRUE)[[1]]
cat(paste(tail(stderr_lines, 80L), collapse = "\n"))
cat("\n--- shiny log tail ---\n")
cat(paste(tail_log(), collapse = "\n"))
cat("\n--- end tails ---\n")

quit(status = 1)
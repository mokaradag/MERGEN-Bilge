#!/usr/bin/env Rscript

# ==============================================================================
# Dosya Yolu: tests/scripts/ai_browser_ux_smoke.R
# Description:
#   Runs the MERGEN UX smoke harness in a real headless browser.
#   Missing Chrome/Chromium/Edge defaults to SKIP; --require-browser
#   or MERGEN_REQUIRE_BROWSER_UX_SMOKE=true makes the check required.
#
#   An explicit MERGEN_BROWSER_BIN declares browser support:
#   silent SKIP is disabled, require mode is enabled automatically,
#   and an unavailable binary fails early with a clear error
#   instead of a late processx failure for MERGEN_BROWSER_BIN.
#   hata ile bloklar.
#
# Not:
#   CDN, runtime download, chromote, Selenium, Playwright veya npm kullanmaz.
#   Uses processx to invoke an already installed local browser binary.
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
        dir.exists(file.path(cand, "tests", "smoke"))) {
      return(normalizePath(cand, winslash = "/", mustWork = TRUE))
    }
  }

  stop("Repo root bulunamad\u0131. Bu beti\u011fi repo i\u00e7inde \u00e7al\u0131\u015ft\u0131r\u0131n.", call. = FALSE)
}

repo_root <- find_repo_root()
setwd(repo_root)
source("tests/scripts/helpers_browser_ux_profile.R", local = TRUE, encoding = "UTF-8")
source("R/utils_log_redact.R", local = TRUE, encoding = "UTF-8")

rscript <- file.path(R.home("bin"), "Rscript")
if (.Platform$OS.type == "windows") {
  rscript <- paste0(rscript, ".exe")
}

if (!file.exists(rscript)) {
  rscript <- Sys.which("Rscript")
}

if (!nzchar(rscript) || !file.exists(rscript)) {
  stop("Rscript bulunamad\u0131.", call. = FALSE)
}

# An explicit MERGEN_BROWSER_BIN declares browser support;
# silent SKIP would hide a configuration error, so explicit
# binary configuration enables require mode automatically.
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

# Shiny/WebSocket work uses server wall time, not virtual time.
browser_timeout_seconds <- suppressWarnings(as.integer(
  arg_value("--browser-timeout", "165")
))
if (is.na(browser_timeout_seconds) || browser_timeout_seconds < 30L) {
  browser_timeout_seconds <- 165L
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

ux_smoke_redact_external_url <- function(text, base_url = external_base_url) {
  text <- ux_smoke_redact_profile(redact_sensitive_text(text))
  if (!nzchar(base_url) || length(text) == 0L) return(text)

  clean_base_url <- sub("/+$", "", base_url)
  origin <- sub("^(https?://[^/]+).*$", "\\1", clean_base_url)
  hostname <- sub(":[0-9]+$", "", sub("^https?://", "", origin))
  out <- as.character(text)
  for (value in unique(c(clean_base_url, origin, hostname,
                         utils::URLencode(clean_base_url, reserved = TRUE)))) {
    out <- gsub(value, "<MERGEN_BROWSER_UX_BASE_URL>", out, fixed = TRUE)
  }
  # Redirect/SSO addresses and the run prefix stay out of artifacts.
  out <- gsub("https?://[^[:space:]<>\"']+|https?%3[Aa]%2[Ff]%2[Ff][^[:space:]<>\"']+",
              "<URL>", out, perl = TRUE)
  gsub("__mergen_ux_[0-9a-f]{48}", "<UX_SMOKE_PATH>", out)
}

# Local runs keep /smoke compatibility; the VM wrapper supplies a random prefix.
smoke_prefix <- if (use_external_app) Sys.getenv("MERGEN_UX_SMOKE_PATH", "") else ""
if (!nzchar(smoke_prefix)) smoke_prefix <- "smoke"
if (!identical(smoke_prefix, "smoke") && !grepl("^__mergen_ux_[0-9a-f]{48}$", smoke_prefix)) {
  stop("Invalid MERGEN_UX_SMOKE_PATH.", call. = FALSE)
}
smoke_url <- sprintf("%s/%s/ux-smoke.html?autostart=1", url, smoke_prefix)
# Local preflight is not a bind requirement; 0.0.0.0:8009 is reachable via localhost.
preflight_base_url <- if (use_external_app && env_flag_true("MERGEN_ALLOW_NETWORK_UX_SMOKE")) {
  "http://127.0.0.1:8009"
} else url
preflight_smoke_url <- sprintf("%s/%s/ux-smoke.html", preflight_base_url, smoke_prefix)
display_smoke_url <- if (use_external_app) "<MERGEN_BROWSER_UX_BASE_URL>/<UX_SMOKE_PATH>/ux-smoke.html?autostart=1" else smoke_url

cat("== MERGEN browser UX smoke ==\n")
cat(sprintf("Repo root: %s\n", repo_root))
cat(sprintf("Port: %d\n", port))
cat(sprintf("Smoke URL: %s\n", display_smoke_url))
cat(sprintf("Timeout: %ds\n", timeout_seconds))
cat(sprintf("Browser timeout: %ds\n", browser_timeout_seconds))
cat(sprintf("Log: %s\n", log_file))
cat(sprintf("DOM artifact: %s\n", dom_file))
cat(sprintf("Require browser: %s\n", require_browser))
cat(sprintf("Explicit MERGEN_BROWSER_BIN: %s\n", browser_bin_explicit))

if (!requireNamespace("processx", quietly = TRUE)) {
  stop(
    "processx paketi gerekli. \u00d6nce Rscript tests/scripts/ci_install_packages.R \u00e7al\u0131\u015ft\u0131r\u0131n.",
    call. = FALSE
  )
}

find_browser_bin <- function() {
  env_bin <- Sys.getenv("MERGEN_BROWSER_BIN", unset = "")
  if (nzchar(env_bin)) {
    # Validate explicit configuration: missing or inaccessible binaries fail
    # early and clearly instead of causing a confusing late processx error.
    resolved_bin <- env_bin

    if (!file.exists(resolved_bin)) {
      resolved_bin <- unname(Sys.which(env_bin))
    }

    if (!nzchar(resolved_bin) || !file.exists(resolved_bin)) {
      stop(
        sprintf(
          "MERGEN_BROWSER_BIN kullan\u0131lam\u0131yor (dosya veya PATH komutu bulunamad\u0131): %s",
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
    "SKIP: Chrome/Chromium/Edge binary bulunamad\u0131.",
    "MERGEN_BROWSER_BIN ile taray\u0131c\u0131 yolu verilebilir.",
    "Bu skip yaln\u0131zca ger\u00e7ek browser UX smoke i\u00e7indir; statik contract testleri \u00e7al\u0131\u015fmaya devam eder."
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
    "MERGEN_ENABLE_UX_SMOKE='true',",
    "TZ='UTC',",
    "LOCAL_LLM_ENDPOINT=ifelse(nzchar(Sys.getenv('LOCAL_LLM_ENDPOINT')), Sys.getenv('LOCAL_LLM_ENDPOINT'), 'http://test.local/v1'),",
    "DB_DSN=ifelse(nzchar(Sys.getenv('DB_DSN')), Sys.getenv('DB_DSN'), 'test-dsn'),",
    "AI_KEYS_MASTER=ifelse(nzchar(Sys.getenv('AI_KEYS_MASTER')), Sys.getenv('AI_KEYS_MASTER'), 'test-master-key-0123456789')",
    ");",
    "cat('SHINY_UX_RUNNER_START\\n');",
    "source('app.R', encoding='UTF-8');",
    "Sys.setenv(MERGEN_ENABLE_UX_SMOKE='true', MERGEN_UX_SMOKE_PATH='', MERGEN_ALLOW_NETWORK_UX_SMOKE='false');",
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
  cat("Using externally running app: <MERGEN_BROWSER_UX_BASE_URL>\n")
  cat(paste(
    "NOTE: The approved browser-facing URL may be a reverse-proxy URL.",
    "For VM/network SSO use run_vm_browser_ux_smoke.R and its --start-app mode.\n"
  ))
}

read_url <- function(target) {
  con <- NULL

  tryCatch(
    {
      con <- suppressWarnings(url(target, open = "rb", blocking = TRUE))
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
    "FAILED: Browser UX smoke uygulama HTTP boot a\u015famas\u0131nda \u00e7al\u0131\u015ft\u0131r\u0131lamad\u0131."
  } else {
    "SKIP: Browser UX smoke uygulama HTTP boot a\u015famas\u0131nda \u00e7al\u0131\u015ft\u0131r\u0131lamad\u0131."
  }

  suffix <- if (isTRUE(require_browser)) {
    "MERGEN_REQUIRE_BROWSER_UX_SMOKE=true oldu\u011fu i\u00e7in bu ad\u0131m bloklay\u0131c\u0131d\u0131r."
  } else {
    "MERGEN_REQUIRE_BROWSER_UX_SMOKE=true de\u011fil; bu ad\u0131m kan\u0131t \u00fcretmeden atlan\u0131yor."
  }

  msg <- paste(
    prefix,
    reason,
    if (!is.na(status)) sprintf("Shiny exit status: %s.", as.character(status)) else "",
    suffix
  )

  cat(msg, "\n")
  cat("\n--- log tail ---\n")
  cat(paste(ux_smoke_redact_external_url(tail_log()), collapse = "\n"))
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

    body <- read_url(preflight_base_url)
    if (nzchar(body)) {
      last_body <<- body

      if (grepl("<html|<!DOCTYPE|shiny|MERGEN|Bilge", body, ignore.case = TRUE)) {
        return(TRUE)
      }
    }

	if (elapsed > timeout_seconds) {
	  body_file <- file.path(artifact_dir, sprintf("last-http-body-%s.html", port))
	  writeLines("HTTP response omitted: no browser evidence.", body_file, useBytes = TRUE)

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

# An available home page does not prove that the gated /smoke/ route is served.
# Verify the real harness before launching; do not change the app exposure gate.
ux_smoke_check_harness <- function() {
  body <- read_url(preflight_smoke_url)
  if (grepl("<title>MERGEN UX Smoke</title>", body, fixed = TRUE) &&
      nzchar(ux_smoke_rendered_status(body))) {
    return(invisible(TRUE))
  }

  stop(paste(
    "FAILED: UX smoke harness is unavailable at", display_smoke_url,
    "Start/restart the target Shiny app with MERGEN_ENABLE_UX_SMOKE=true after source('app.R')",
    "For an already running app on the VM, restart with run_vm_browser_ux_smoke.R --start-app.",
    "That mode keeps 0.0.0.0:8009 and shares the per-run prefix locally."
  ), call. = FALSE)
}

# Read only rendered #status text: harness source and logs also contain
# the UX_SMOKE_DONE:PASS literal; an unstarted or failed page must not
# pass merely because that literal exists in its source.
ux_smoke_rendered_status <- function(dom) {
  m <- regmatches(dom, regexec("<div id=\"status\"[^>]*>([^<]*)</div>", dom, perl = TRUE))[[1]]
  if (length(m) >= 2L) trimws(m[[2]]) else ""
}

ux_smoke_check_harness()

# SSO may use only a session prepared by normal operator sign-in in a
# dedicated profile. The default stays temporary; tokens are never read/copied.
ux_smoke_browser_profile <- function(requested = "", external_app = FALSE) {
  persistent <- nzchar(trimws(requested))
  if (persistent && !isTRUE(external_app)) {
    stop("A prepared browser profile requires MERGEN_BROWSER_UX_BASE_URL.", call. = FALSE)
  }
  if (persistent && !dir.exists(requested)) {
    stop("Prepared browser profile must be an existing directory outside the repository and artifacts.", call. = FALSE)
  }
  path <- if (persistent) requested else tempfile("mergen-browser-profile-")
  if (!persistent && !dir.create(path, recursive = TRUE, showWarnings = FALSE)) {
    stop("Browser UX smoke profile directory could not be created.", call. = FALSE)
  }
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  if (persistent) {
    path <- ux_smoke_profile_path(path, c(repo_root, artifact_dir,
                                        Sys.getenv("MERGEN_EVIDENCE_ARTIFACT_DIR", "")))
  }
  list(path = path, temporary = !persistent)
}

ux_smoke_cleanup_profile <- function(profile) {
  if (isTRUE(profile$temporary)) unlink(profile$path, recursive = TRUE, force = TRUE)
  invisible(NULL)
}

ux_smoke_run_browser <- function() {
browser_profile <- ux_smoke_browser_profile(
  arg_value("--profile-dir", Sys.getenv("MERGEN_BROWSER_UX_PROFILE_DIR", "")),
  external_app = use_external_app
)
profile_dir <- browser_profile$path
if (!is.null(px)) on.exit(cleanup(), add = TRUE)
on.exit(ux_smoke_cleanup_profile(browser_profile), add = TRUE)
if (grepl("^msedge([.]exe)?$", basename(browser_bin), ignore.case = TRUE)) ux_smoke_check_edge_policy()
if (!browser_profile$temporary) {
  cat("Using operator-prepared smoke profile. Close its interactive browser windows before this run.\n")
}

run_browser_dump <- function(headless_arg) {
  browser_args <- c(
    headless_arg,
    "--disable-gpu",
    "--disable-dev-shm-usage",
    "--no-first-run",
    "--no-default-browser-check",
    "--autoplay-policy=no-user-gesture-required",
    paste0("--user-data-dir=", profile_dir),
    paste0("--timeout=", (browser_timeout_seconds - 5L) * 1000L),
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
  stderr <- ux_smoke_redact_profile(result$stderr %||% "", profile_dir)

  # Ham DOM SSO formu/oturum verisi tasiyabilir; yalniz sonuc ozeti saklanir.
  status <- ux_smoke_rendered_status(stdout)
  evidence_status <- if (identical(status, "UX_SMOKE_DONE:PASS")) status else "UX_SMOKE_NOT_PASSED"
  writeLines(paste0('<div id="status">', evidence_status, "</div>"), con = dom_file, useBytes = TRUE)
  writeLines(ux_smoke_redact_external_url(stderr), con = stderr_file, useBytes = TRUE)

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

smoke_status <- ux_smoke_rendered_status(result$stdout)

if (identical(smoke_status, "UX_SMOKE_DONE:PASS")) {
  cat("OK: rendered #status is UX_SMOKE_DONE:PASS.\n")
  return(0L)
}

display_status <- if (startsWith(smoke_status, "UX_SMOKE_DONE:FAIL")) "UX_SMOKE_DONE:FAIL" else "UX_SMOKE_NOT_PASSED"
if (startsWith(smoke_status, "UX_SMOKE_DONE:FAIL")) {
  cat(sprintf("FAILED: rendered #status is '%s'.\n", display_status))
} else {
  cat(sprintf("FAILED: rendered #status did not reach UX_SMOKE_DONE:PASS ('%s').\n", display_status))
}

cat(sprintf("Browser status: %d\n", result$status))
cat(sprintf("DOM artifact: %s\n", dom_file))
cat(sprintf("Browser stderr artifact: %s\n", stderr_file))
cat("\n--- browser stderr tail ---\n")
stderr_lines <- strsplit(ux_smoke_redact_external_url(result$stderr %||% ""), "\n", fixed = TRUE)[[1]]
cat(paste(tail(stderr_lines, 80L), collapse = "\n"))
cat("\n--- shiny log tail ---\n")
cat(paste(ux_smoke_redact_external_url(tail_log()), collapse = "\n"))
cat("\n--- end tails ---\n")

1L
}

quit(status = ux_smoke_run_browser())

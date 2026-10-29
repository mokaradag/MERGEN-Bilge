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
        dir.exists(file.path(cand, "tests", "smoke"))) {
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

ux_smoke_redact_external_url <- function(text, base_url = external_base_url) {
  if (!nzchar(base_url) || length(text) == 0L) {
    return(text)
  }

  clean_base_url <- sub("/+$", "", base_url)
  origin <- sub("^(https?://[^/]+).*$", "\\1", clean_base_url)
  hostname <- sub(":[0-9]+$", "", sub("^https?://", "", origin))
  out <- as.character(text)
  for (value in unique(c(clean_base_url, origin, hostname,
                         utils::URLencode(clean_base_url, reserved = TRUE)))) {
    out <- gsub(value, "<MERGEN_BROWSER_UX_BASE_URL>", out, fixed = TRUE)
  }
  # Yönlendirme/SSO adresleri ve koşu öneki de artifact'a sızmaz.
  out <- gsub("https?://[^[:space:]<>\"']+|https?%3[Aa]%2[Ff]%2[Ff][^[:space:]<>\"']+",
              "<URL>", out, perl = TRUE)
  gsub("__mergen_ux_[0-9a-f]{48}", "<UX_SMOKE_PATH>", out)
}

# Yerel koşucu /smoke uyumluluğunu korur; VM sarmalayıcısı rastgele öneki verir.
smoke_prefix <- if (use_external_app) Sys.getenv("MERGEN_UX_SMOKE_PATH", "") else ""
if (!nzchar(smoke_prefix)) smoke_prefix <- "smoke"
if (!identical(smoke_prefix, "smoke") && !grepl("^__mergen_ux_[0-9a-f]{48}$", smoke_prefix)) {
  stop("Invalid MERGEN_UX_SMOKE_PATH.", call. = FALSE)
}
smoke_url <- sprintf("%s/%s/ux-smoke.html?autostart=1", url, smoke_prefix)
# Bu yerel ön kontrol bind zorunluluğu değildir; 0.0.0.0:8009 localhost'tan erişilir.
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
	  writeLines(ux_smoke_redact_external_url(last_body), body_file, useBytes = TRUE)

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

# Ana sayfanın açılması kapılı /smoke/ yolunun sunulduğunu kanıtlamaz.
# Tarayıcı başlamadan gerçek harness'ı doğrula; uygulamanın kapısını değiştirme.
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

# Sonuç yalnızca işlenmiş #status metninden okunur: harness betiğinin kaynağı
# ve günlük satırları da UX_SMOKE_DONE:PASS sabitini taşır; başlamamış ya da
# FAIL ile biten sayfa bu sabit yüzünden geçmiş sayılmamalıdır.
ux_smoke_rendered_status <- function(dom) {
  m <- regmatches(dom, regexec("<div id=\"status\"[^>]*>([^<]*)</div>", dom, perl = TRUE))[[1]]
  if (length(m) >= 2L) trimws(m[[2]]) else ""
}

ux_smoke_check_harness()

# SSO için yalnız bakımcının ayrı profilde normal girişle hazırladığı oturum
# kullanılabilir. Varsayılan profil hâlâ geçicidir; token okunmaz/kopyalanmaz.
ux_smoke_browser_profile <- function(requested = "", external_app = FALSE) {
  persistent <- nzchar(trimws(requested))
  if (persistent && !isTRUE(external_app)) {
    stop("A prepared browser profile requires MERGEN_BROWSER_UX_BASE_URL.", call. = FALSE)
  }
  path <- if (persistent) requested else tempfile("mergen-browser-profile-")
  if (!dir.exists(path) && !dir.create(path, recursive = TRUE, showWarnings = FALSE)) {
    stop("Browser UX smoke profile directory could not be created.", call. = FALSE)
  }
  list(path = normalizePath(path, winslash = "/", mustWork = TRUE), temporary = !persistent)
}

ux_smoke_cleanup_profile <- function(profile) {
  if (isTRUE(profile$temporary)) unlink(profile$path, recursive = TRUE, force = TRUE)
  invisible(NULL)
}

browser_profile <- ux_smoke_browser_profile(
  arg_value("--profile-dir", Sys.getenv("MERGEN_BROWSER_UX_PROFILE_DIR", "")),
  external_app = use_external_app
)
profile_dir <- browser_profile$path
on.exit(ux_smoke_cleanup_profile(browser_profile), add = TRUE)
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

  writeLines(ux_smoke_redact_external_url(stdout), con = dom_file, useBytes = TRUE)
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
  quit(status = 0)
}

if (startsWith(smoke_status, "UX_SMOKE_DONE:FAIL")) {
  cat(sprintf("FAILED: rendered #status is '%s'.\n", ux_smoke_redact_external_url(smoke_status)))
} else {
  cat(sprintf("FAILED: rendered #status did not reach UX_SMOKE_DONE:PASS ('%s').\n", ux_smoke_redact_external_url(smoke_status)))
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

quit(status = 1)

#!/usr/bin/env Rscript
# Windows VM: normal 0.0.0.0:8009 + onayli SSO URL + kosuya ozel test yolu.
# --start-app once ayri pencerede; varsayilan mod yalniz browser smoke calistirir.
# ASCII: Windows source/Rscript yerel kod sayfasi ile de guvenli giris noktasi.

vm_ux_prefix_valid <- function(value) {
  is.character(value) && length(value) == 1L && !is.na(value) && nchar(value, type = "bytes") == 60L &&
    grepl("^__mergen_ux_[0-9a-f]{48}$", value)
}

vm_ux_new_prefix <- function() {
  paste0("__mergen_ux_", paste(sprintf("%02x", as.integer(openssl::rand_bytes(24L))), collapse = ""))
}

vm_ux_base_url <- function(value) {
  # Yalniz HTTP(S) origin + yol; kimlik bilgisi, sorgu, fragment kabul edilmez.
  if (length(value) != 1L || is.na(value) ||
      !grepl("^https?://[A-Za-z0-9.-]+(:[0-9]{1,5})?(/[^?#[:space:]\\\\]*)?$", value) ||
      grepl("[[:cntrl:]]", value)) {
    stop("MERGEN_BROWSER_UX_BASE_URL must be the approved HTTP(S) application base URL (no credentials/query/fragment).", call. = FALSE)
  }
  if (startsWith(value, "http://") &&
      !grepl("^http://(127[.]0[.]0[.]1|localhost)(:[0-9]{1,5})?(/|$)", value)) {
    stop("MERGEN_BROWSER_UX_BASE_URL requires HTTPS for network VM smoke.", call. = FALSE)
  }
  sub("/+$", "", value)
}

vm_ux_smoke_url <- function(base, prefix) {
  if (!vm_ux_prefix_valid(prefix)) stop("Invalid per-run UX smoke prefix.", call. = FALSE)
  paste0(vm_ux_base_url(base), "/", prefix, "/ux-smoke.html?autostart=1")
}

vm_ux_runtime_dir <- function() {
  local_app <- Sys.getenv("LOCALAPPDATA", "")
  if (!nzchar(local_app)) stop("LOCALAPPDATA is required for the VM smoke handshake.", call. = FALSE)
  file.path(local_app, "MERGEN", "BrowserUxSmokeRun")
}

vm_ux_read_prefix <- function(runtime_dir) {
  path <- file.path(runtime_dir, "prefix")
  if (!file.exists(path) || is.na(file.info(path)$size) || file.info(path)$size > 80L) {
    stop("No active smoke startup. Stop the normal app, then run this script with --start-app in Window 1.", call. = FALSE)
  }
  value <- readLines(path, warn = FALSE, n = 2L)
  if (!vm_ux_prefix_valid(value)) stop("Invalid VM smoke handshake; restart --start-app.", call. = FALSE)
  value
}

vm_ux_start_app <- function(runtime_dir) {
  # Normal launcher gibi ortam app.R'dan ONCE yuklenir; yerel auth'a dusulmez.
  if (file.exists(".Renviron") && !isTRUE(readRenviron(".Renviron"))) {
    stop("VM smoke configuration could not be loaded from .Renviron.", call. = FALSE)
  }
  sso <- chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", trimws(Sys.getenv("SSO_ENABLED", "")))
  if (!sso %in% c("true", "t", "1", "yes", "on")) {
    stop("Network VM smoke requires SSO_ENABLED=TRUE in the normal VM configuration.", call. = FALSE)
  }
  # Kilit dizini atomik olusturulur; baska bir kosunun oneki ezilmez.
  dir.create(dirname(runtime_dir), recursive = TRUE, showWarnings = FALSE)
  if (!dir.create(runtime_dir, mode = "0700", showWarnings = FALSE)) {
    stop("Smoke runtime directory already exists. Stop Window 1; remove only the stale BrowserUxSmokeRun directory, then retry.", call. = FALSE)
  }
  on.exit(unlink(runtime_dir, recursive = TRUE, force = TRUE), add = TRUE)
  prefix <- vm_ux_new_prefix()
  Sys.setenv(MERGEN_RUN_APP = "false")
  source("app.R", encoding = "UTF-8", local = globalenv())
  if (!isTRUE(SSO_ENABLED)) stop("Network VM smoke requires active application SSO.", call. = FALSE)
  # .Renviron yuklendikten sonra gecici opt-in; kalici dosyaya YAZILMAZ.
  Sys.setenv(MERGEN_ENABLE_UX_SMOKE = "true", MERGEN_ALLOW_NETWORK_UX_SMOKE = "true",
             MERGEN_UX_SMOKE_PATH = prefix, MERGEN_HOST = "0.0.0.0", MERGEN_PORT = "8009")
  writeLines(prefix, file.path(runtime_dir, "prefix"), useBytes = TRUE)
  Sys.chmod(file.path(runtime_dir, "prefix"), mode = "0600")
  cat("Temporary smoke app: 0.0.0.0:8009. Keep this window open; run browser smoke in Window 2.\n")
  run_mergen_app(host = "0.0.0.0", port = 8009L, launch.browser = FALSE, quiet = FALSE)
}

vm_ux_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  if (!file.exists("app.R")) stop("Run from the repository root.", call. = FALSE)
  if (length(setdiff(args, "--start-app"))) stop("Only --start-app or no arguments are supported.", call. = FALSE)
  runtime_dir <- vm_ux_runtime_dir()
  env_names <- c("MERGEN_RUN_APP", "MERGEN_ENABLE_UX_SMOKE", "MERGEN_ALLOW_NETWORK_UX_SMOKE",
                 "MERGEN_UX_SMOKE_PATH", "MERGEN_HOST", "MERGEN_PORT", "MERGEN_BROWSER_UX_BASE_URL", "MERGEN_BROWSER_BIN")
  old <- Sys.getenv(env_names, unset = NA_character_)
  on.exit({
    for (name in env_names) {
      if (is.na(old[[name]])) Sys.unsetenv(name) else do.call(Sys.setenv, setNames(list(old[[name]]), name))
    }
  }, add = TRUE)
  if ("--start-app" %in% args) return(vm_ux_start_app(runtime_dir))

  base <- vm_ux_base_url(Sys.getenv("MERGEN_BROWSER_UX_BASE_URL", ""))
  prefix <- vm_ux_read_prefix(runtime_dir)
  # URL kurulumu baslamadan dogrulanir; gercek URL/onek komut satirina yazilmaz.
  invisible(vm_ux_smoke_url(base, prefix))
  profile <- Sys.getenv("MERGEN_BROWSER_UX_PROFILE_DIR", "")
  if (!nzchar(profile) || !dir.exists(profile)) {
    stop("Prepare a dedicated Edge profile outside the repository; set MERGEN_BROWSER_UX_PROFILE_DIR and close its browser windows.", call. = FALSE)
  }
  source("tests/scripts/helpers_browser_ux_profile.R", local = TRUE, encoding = "UTF-8")
  artifact_root <- Sys.getenv("MERGEN_EVIDENCE_ARTIFACT_DIR", "artifacts/ai-validation")
  profile <- ux_smoke_profile_path(profile, c(".", artifact_root))
  # Hazir Edge profilini varsayilan Chrome ile acmaya calisma.
  if (.Platform$OS.type == "windows" && !nzchar(Sys.getenv("MERGEN_BROWSER_BIN", ""))) {
    edge <- file.path(c(Sys.getenv("PROGRAMFILES(X86)"), Sys.getenv("PROGRAMFILES"),
                        Sys.getenv("LOCALAPPDATA")), "Microsoft", "Edge", "Application", "msedge.exe")
    edge <- edge[file.exists(edge)]
    if (!length(edge)) stop("Microsoft Edge not found; set MERGEN_BROWSER_BIN explicitly.", call. = FALSE)
    Sys.setenv(MERGEN_BROWSER_BIN = edge[[1]])
  }
  Sys.setenv(MERGEN_UX_SMOKE_PATH = prefix, MERGEN_ALLOW_NETWORK_UX_SMOKE = "true",
             MERGEN_BROWSER_UX_BASE_URL = base)
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  artifact_dir <- file.path(artifact_root, "browser-ux-smoke")
  # Ortam zaten yuklendi; gecici onek/opt-in .Renviron ile ezilmez, .Rprofile acik kalir.
  result <- processx::run(rscript, c("--no-environ", "tests/scripts/ai_browser_ux_smoke.R",
                                    "--require-browser", "--port", "8009", "--artifact-dir", artifact_dir),
                          echo = FALSE, error_on_status = FALSE, timeout = 420)
  lines <- trimws(strsplit(result$stdout, "\n", fixed = TRUE)[[1]])
  if (!identical(result$status, 0L) || !"OK: rendered #status is UX_SMOKE_DONE:PASS." %in% lines) {
    stop("VM browser UX smoke failed; rendered UX_SMOKE_DONE:PASS is required.", call. = FALSE)
  }
  # Cocuk baslangic/tani ciktisi profil veya sir tasiyabilir; yalniz kanit satiri aktarilir.
  cat("OK: rendered #status is UX_SMOKE_DONE:PASS.\n")
  invisible(TRUE)
}

vm_ux_main()

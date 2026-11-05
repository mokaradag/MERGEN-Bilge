# Windows'ta ozel job, diger sistemlerde processx agaci; kalici profil silinmez.
ux_smoke_owned_browser_stages <- c("language_mode", "input", "compile", "create_job", "job_limits",
                                   "std_handles", "create_process", "assign", "resume", "wait",
                                   "cleanup", "terminate", "cleanup_wait", "exit_code",
                                   "cleanup_watchdog", "launch", "unknown")
ux_smoke_owned_browser_cleanup_stages <- c("cleanup", "terminate", "cleanup_wait", "exit_code", "cleanup_watchdog")
# Adaptorun dogrulanmis temizlik butcesi (ms); PowerShell ayni degeri kullanir.
ux_smoke_owned_browser_cleanup_ms <- 5000L

# Adaptor stderr'inden yalniz izinli asama/Win32 kodu alinir; diger metin tasinmaz.
ux_smoke_owned_browser_stage <- function(stderr, status) {
  if (identical(status, 126L)) {
    return(list(stage = "language_mode", win32 = NA_character_, active = NA_character_, ms = NA_character_))
  }
  m <- regmatches(stderr, regexec(paste0("MERGEN_OWNED_BROWSER_STAGE=([a-z_]+)(?: win32=(-?[0-9]{1,10}))?",
                                         "(?: active=([0-9]{1,6}) ms=([0-9]{1,9}))?"), stderr, perl = TRUE))[[1]]
  stage <- if (length(m) >= 2L && m[[2]] %in% ux_smoke_owned_browser_stages) m[[2]] else "unknown"
  field <- function(i) if (length(m) >= i && nzchar(m[[i]])) m[[i]] else NA_character_
  list(stage = stage, win32 = field(3L), active = field(4L), ms = field(5L))
}

# Sinif ve alanlar sabit sozluktendir; ust kosucu bunlari guvenle raporlar.
# dom yalniz isleme sonucunu siniflandirmak icindir; ham olarak yazdirilmaz.
ux_smoke_owned_browser_error <- function(message, failure, stage = NA_character_, win32 = NA_character_,
                                         active = NA_character_, ms = NA_character_, dom = "") {
  structure(class = c("ux_smoke_owned_browser_error", "error", "condition"),
            list(message = message, call = NULL, failure = failure, stage = stage, win32 = win32,
                 active = active, ms = ms, dom = dom))
}

# PowerShell girdisi UTF-8 okunur. CP1254 gibi yerel kod sayfasindaki getwd()
# dizgeleri (or. "Gelistirme" icindeki s-cedilla) jsonlite tarafindan donusturulmeden
# UTF-8 diye isaretlenir; bu nedenle tum alanlar once UTF-8'e cevrilir ve
# processx'in yerel kodlama donusumunden kacinmak icin ham bayt yazilir.
ux_smoke_owned_browser_payload <- function(command, args, wd, timeout) {
  json <- jsonlite::toJSON(list(
    executable = enc2utf8(command), args = as.list(enc2utf8(unname(as.character(args)))),
    cwd = enc2utf8(wd), timeoutMs = timeout * 1000, cleanupMs = ux_smoke_owned_browser_cleanup_ms,
    jobSource = enc2utf8(file.path(wd, "tests/scripts/helpers_browser_job.cs"))), auto_unbox = TRUE)
  c(charToRaw(json), as.raw(10L))
}

ux_smoke_owned_browser_run <- function(command, args, timeout, wd = getwd(),
                                       windows = .Platform$OS.type == "windows",
                                       spawn = processx::process$new) {
  if (!windows) return(processx::run(command, args, wd = wd, echo = FALSE,
    error_on_status = FALSE, timeout = timeout, cleanup_tree = TRUE))
  launch <- command
  launch_args <- args
  if (windows) {
    launch <- "powershell.exe"
    launch_args <- c("-NoProfile", "-NonInteractive", "-Command",
      paste(readLines(file.path(wd, "tests/scripts/run_owned_browser.ps1"), warn = FALSE), collapse = "\n"))
  }
  child <- spawn(launch, launch_args, wd = wd,
    stdin = if (windows) "|" else NULL, stdout = "|", stderr = "|",
    cleanup_tree = TRUE, windows_hide_window = TRUE)
  done <- FALSE
  on.exit(if (!done) try(child$kill_tree(), silent = TRUE), add = TRUE)
  if (windows) child$write_input(ux_smoke_owned_browser_payload(command, args, wd, timeout))
  stdout <- stderr <- ""
  started <- proc.time()[["elapsed"]]
  stopping <- FALSE
  timed_out <- FALSE
  repeat {
    child$poll_io(20L)
    stdout <- paste0(stdout, child$read_output())
    stderr <- paste0(stderr, child$read_error())
    alive <- child$is_alive()
    complete <- grepl("</body>\\s*</html>\\s*$", stdout, perl = TRUE) &&
      grepl("<html[\\s>]", stdout, perl = TRUE)
    elapsed <- proc.time()[["elapsed"]] - started
    if (!stopping && (complete || elapsed >= timeout)) {
      timed_out <- !complete
      stopping <- TRUE
      stopped_at <- elapsed
      if (windows && alive) {
        tryCatch(child$write_input("stop\n"), error = function(e) {
          if (child$is_alive()) stop(ux_smoke_owned_browser_error(
            "Owned browser control failed.", "browser_cleanup_failed", "wait", dom = stdout))
        })
      } else if (!windows) child$kill_tree()
    }
    if (!alive) break
    # Denetleyici, adaptorun kendi dogrulama butcesini kesmez: butce + PowerShell cikis payi.
    if (stopping && elapsed - stopped_at >= ux_smoke_owned_browser_cleanup_ms / 1000 + 10) {
      stop(ux_smoke_owned_browser_error("Owned browser cleanup timed out.", "browser_cleanup_failed",
                                        "cleanup_watchdog", ms = as.character(round((elapsed - stopped_at) * 1000)),
                                        dom = stdout))
    }
  }
  stdout <- paste0(stdout, child$read_all_output())
  stderr <- paste0(stderr, child$read_all_error())
  status <- child$get_exit_status()
  # Job dogrulamasi basarisizsa DOM'daki PASS kullanilamaz.
  if (windows && (is.na(status) || status %in% c(124L, 125L, 126L))) {
    if (timed_out || identical(status, 124L)) {
      stop(ux_smoke_owned_browser_error("Owned browser timed out.", "browser_timeout", dom = stdout))
    }
    info <- ux_smoke_owned_browser_stage(stderr, status)
    failure <- if (info$stage %in% ux_smoke_owned_browser_cleanup_stages) "browser_cleanup_failed" else "browser_launch_failed"
    stop(ux_smoke_owned_browser_error(
      sprintf("Owned browser launch or cleanup failed (stage=%s%s%s).", info$stage,
              if (is.na(info$win32)) "" else paste0(", win32=", info$win32),
              if (is.na(info$active)) "" else paste0(", active=", info$active, ", ms=", info$ms)),
      failure, info$stage, info$win32, info$active, info$ms, dom = stdout))
  }
  if (timed_out) stop(ux_smoke_owned_browser_error("Owned browser timed out.", "browser_timeout", dom = stdout))
  done <- TRUE
  list(status = status, stdout = stdout, stderr = stderr)
}

# Uretim durmadan once: PowerShell dil modu, C# derleme, job olusturma/atama,
# devam ettirme, stdout ve dogrulanmis temizlik zararsiz bir R alt sureciyle
# denenir. Tarayici acilmaz, profil/URL kullanilmaz.
ux_smoke_owned_browser_preflight <- function(wd = getwd(), run = ux_smoke_owned_browser_run) {
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  probe <- "cat('<html><body><div id=\"status\">OWNED_BROWSER_ADAPTER_OK</div></body></html>\\n')"
  result <- tryCatch(run(rscript, c("--vanilla", "-e", probe), timeout = 60, wd = wd),
                     ux_smoke_owned_browser_error = function(e) {
                       stop(paste("Owned browser adapter pre-stop check FAILED:", conditionMessage(e)), call. = FALSE)
                     })
  if (!identical(result$status, 0L) ||
      !grepl('<div id="status">OWNED_BROWSER_ADAPTER_OK</div>', result$stdout, fixed = TRUE)) {
    stop("Owned browser adapter pre-stop check FAILED: probe output was not captured.", call. = FALSE)
  }
  cat("OK: owned browser adapter verified.\n")
  invisible(TRUE)
}

# Uretim durmadan once gercek Edge cok-surecli yasam dongusu ayni job yolundan
# denenir: gecici profil ve yerel dosya sayfasi; ag, SSO ve hazir profil
# kullanilmaz. DOM yakalanmali, job temizligi dogrulanmali ve gecici profil
# silinebilmelidir (kalan Edge sureci profili kilitli tutardi).
ux_smoke_owned_browser_edge_preflight <- function(edge = "", wd = getwd(), run = ux_smoke_owned_browser_run,
                                                  check_policy = function() ux_smoke_check_edge_policy()) {
  fail <- function(reason) stop(paste("Owned Edge pre-stop check FAILED:", reason), call. = FALSE)
  if (!nzchar(edge)) {
    candidates <- file.path(c(Sys.getenv("PROGRAMFILES(X86)"), Sys.getenv("PROGRAMFILES"), Sys.getenv("LOCALAPPDATA")),
                            "Microsoft", "Edge", "Application", "msedge.exe")
    candidates <- candidates[nzchar(Sys.getenv(c("PROGRAMFILES(X86)", "PROGRAMFILES", "LOCALAPPDATA"))) &
                               file.exists(candidates)]
    if (!length(candidates)) fail("Microsoft Edge not found.")
    edge <- candidates[[1]]
  }
  # Zorunlu UserDataDir ilkesi gecici profili ezip gercek profili acardi.
  check_policy()
  root <- tempfile("mergen-edge-preflight-")
  profile <- file.path(root, "profile")
  dir.create(profile, recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
  page <- file.path(root, "probe.html")
  writeLines('<html><body><div id="status">OWNED_EDGE_OK</div></body></html>', page, useBytes = TRUE)
  url <- paste0("file:///", sub("^/+", "", utils::URLencode(enc2utf8(normalizePath(page, winslash = "/")))))
  args <- c("--headless=new", "--disable-gpu", "--no-first-run", "--no-default-browser-check",
            paste0("--user-data-dir=", normalizePath(profile, winslash = "/")), "--timeout=20000", "--dump-dom", url)
  result <- tryCatch(run(edge, args, timeout = 60, wd = wd),
                     ux_smoke_owned_browser_error = function(e) fail(conditionMessage(e)))
  if (!identical(result$status, 0L) ||
      !grepl('<div id="status">OWNED_EDGE_OK</div>', result$stdout, fixed = TRUE)) {
    fail(sprintf("Edge DOM was not captured (exit=%s).", as.character(result$status)))
  }
  unlink(root, recursive = TRUE, force = TRUE)
  if (dir.exists(root)) fail("temporary Edge profile is still in use after job cleanup.")
  cat("OK: owned Edge lifecycle verified.\n")
  invisible(TRUE)
}

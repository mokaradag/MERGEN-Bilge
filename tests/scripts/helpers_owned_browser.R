# Windows'ta ozel job, diger sistemlerde processx agaci; kalici profil silinmez.
ux_smoke_owned_browser_stages <- c("language_mode", "input", "compile", "create_job", "job_limits",
                                   "std_handles", "create_process", "assign", "resume", "wait",
                                   "cleanup", "launch", "unknown")

# Adaptor stderr'inden yalniz izinli asama/Win32 kodu alinir; diger metin tasinmaz.
ux_smoke_owned_browser_stage <- function(stderr, status) {
  if (identical(status, 126L)) return(list(stage = "language_mode", win32 = NA_character_))
  m <- regmatches(stderr, regexec("MERGEN_OWNED_BROWSER_STAGE=([a-z_]+)(?: win32=(-?[0-9]{1,10}))?",
                                  stderr, perl = TRUE))[[1]]
  stage <- if (length(m) >= 2L && m[[2]] %in% ux_smoke_owned_browser_stages) m[[2]] else "unknown"
  win32 <- if (length(m) >= 3L && nzchar(m[[3]])) m[[3]] else NA_character_
  list(stage = stage, win32 = win32)
}

# Sinif ve alanlar sabit sozluktendir; ust kosucu bunlari guvenle raporlar.
ux_smoke_owned_browser_error <- function(message, failure, stage = NA_character_, win32 = NA_character_) {
  structure(class = c("ux_smoke_owned_browser_error", "error", "condition"),
            list(message = message, call = NULL, failure = failure, stage = stage, win32 = win32))
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
  if (windows) child$write_input(paste0(jsonlite::toJSON(
    list(executable = command, args = unname(as.list(args)), cwd = wd,
         timeoutMs = timeout * 1000,
         jobSource = file.path(wd, "tests/scripts/helpers_browser_job.cs")), auto_unbox = TRUE), "\n"))
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
            "Owned browser control failed.", "browser_cleanup_failed", "wait"))
        })
      } else if (!windows) child$kill_tree()
    }
    if (!alive) break
    if (stopping && elapsed - stopped_at >= 5) {
      stop(ux_smoke_owned_browser_error("Owned browser cleanup timed out.", "browser_cleanup_failed", "cleanup"))
    }
  }
  stdout <- paste0(stdout, child$read_all_output())
  stderr <- paste0(stderr, child$read_all_error())
  status <- child$get_exit_status()
  # Job dogrulamasi basarisizsa DOM'daki PASS kullanilamaz.
  if (windows && (is.na(status) || status %in% c(124L, 125L, 126L))) {
    if (timed_out || identical(status, 124L)) {
      stop(ux_smoke_owned_browser_error("Owned browser timed out.", "browser_timeout"))
    }
    info <- ux_smoke_owned_browser_stage(stderr, status)
    failure <- if (identical(info$stage, "cleanup")) "browser_cleanup_failed" else "browser_launch_failed"
    stop(ux_smoke_owned_browser_error(
      sprintf("Owned browser launch or cleanup failed (stage=%s%s).", info$stage,
              if (is.na(info$win32)) "" else paste0(", win32=", info$win32)),
      failure, info$stage, info$win32))
  }
  if (timed_out) stop(ux_smoke_owned_browser_error("Owned browser timed out.", "browser_timeout"))
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

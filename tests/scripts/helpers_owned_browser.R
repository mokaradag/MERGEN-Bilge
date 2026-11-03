# Windows'ta ozel job, diger sistemlerde processx agaci; kalici profil silinmez.
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
          if (child$is_alive()) stop("Owned browser control failed.", call. = FALSE)
        })
      } else if (!windows) child$kill_tree()
    }
    if (!alive) break
    if (stopping && elapsed - stopped_at >= 5) {
      stop("Owned browser cleanup timed out.", call. = FALSE)
    }
  }
  stdout <- paste0(stdout, child$read_all_output())
  stderr <- paste0(stderr, child$read_all_error())
  status <- child$get_exit_status()
  # Job dogrulamasi basarisizsa DOM'daki PASS kullanilamaz.
  if (windows && (is.na(status) || status %in% c(124L, 125L))) {
    stop(if (timed_out || identical(status, 124L)) "Owned browser timed out."
         else "Owned browser launch or cleanup failed.", call. = FALSE)
  }
  if (timed_out) stop("Owned browser timed out.", call. = FALSE)
  done <- TRUE
  list(status = status, stdout = stdout, stderr = stderr)
}

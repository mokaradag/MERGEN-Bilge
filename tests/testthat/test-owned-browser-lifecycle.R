.owned_browser_env <- function() {
  root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  source(file.path(root, "tests/scripts/helpers_owned_browser.R"), local = env,
         encoding = "UTF-8")
  env
}

test_that("job verification failure rejects a rendered PASS and cleans the launcher", {
  env <- .owned_browser_env()
  for (status in c(124L, 125L, NA_integer_)) {
    killed <- FALSE
    child <- list(poll_io = function(...) NULL,
      read_output = function() '<html><body><div id="status">UX_SMOKE_DONE:PASS</div></body></html>',
      read_error = function() "", is_alive = function() FALSE,
      read_all_output = function() "", read_all_error = function() "",
      write_input = function(...) NULL, get_exit_status = function() status,
      kill_tree = function() { killed <<- TRUE })
    expect_error(env$ux_smoke_owned_browser_run("edge", character(), 10,
      windows = TRUE, spawn = function(...) child), "Owned browser")
    expect_true(killed)
  }
})

test_that("inspection errors retain the primary error when emergency cleanup fails", {
  env <- .owned_browser_env()
  child <- list(write_input = function(...) NULL,
    poll_io = function(...) stop("primary poll error"),
    kill_tree = function() stop("secondary cleanup error"))
  expect_error(env$ux_smoke_owned_browser_run("edge", character(), 10,
    windows = TRUE, spawn = function(...) child), "primary poll error")
})

test_that("verified browser errors retain stderr for a clean legacy retry", {
  env <- .owned_browser_env()
  child <- list(poll_io = function(...) NULL, read_output = function() "",
    read_error = function() "unknown --headless=new", is_alive = function() FALSE,
    read_all_output = function() "", read_all_error = function() "",
    write_input = function(...) NULL, get_exit_status = function() 1L)
  result <- env$ux_smoke_owned_browser_run("edge", character(), 10,
    windows = TRUE, spawn = function(...) child)
  expect_identical(result$status, 1L)
  expect_match(result$stderr, "unknown --headless=new", fixed = TRUE)
})

test_that("production runner withholds PASS artifacts until profile cleanup succeeds", {
  root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  expressions <- parse(file.path(root, "tests/scripts/ai_browser_ux_smoke.R"), encoding = "UTF-8")
  for (e in expressions) {
    if (is.call(e) && identical(e[[1]], as.name("<-")) && is.call(e[[3]]) &&
        identical(e[[3]][[1]], as.name("function"))) eval(e, env)
  }
  env$px <- NULL
  env$dom_file <- withr::local_tempfile()
  env$stderr_file <- withr::local_tempfile()
  env$browser_bin <- "browser"
  env$browser_timeout_seconds <- 30L
  env$smoke_url <- "https://app.example.invalid/smoke"
  env$use_external_app <- TRUE
  env$arg_value <- function(name, default) default
  env$ux_smoke_browser_profile <- function(...) list(path = "prepared", temporary = FALSE)
  env$ux_smoke_redact_profile <- env$ux_smoke_redact_external_url <- function(text, ...) text
  env$ux_smoke_owned_browser_run <- function(...) list(status = 0L,
    stdout = '<html><body><div id="status">UX_SMOKE_DONE:PASS</div></body></html>', stderr = "")
  env$ux_smoke_cleanup_profile <- function(...) stop("required cleanup failed")
  writeLines('<div id="status">UX_SMOKE_DONE:PASS</div>', env$dom_file)
  expect_error(env$ux_smoke_run_browser(), "required cleanup failed")
  expect_match(readLines(env$dom_file), "UX_SMOKE_NOT_PASSED", fixed = TRUE)
  env$ux_smoke_cleanup_profile <- function(...) invisible(NULL)
  expect_output(expect_identical(env$ux_smoke_run_browser(), 0L), "OK: rendered #status")
  expect_match(readLines(env$dom_file), "UX_SMOKE_DONE:PASS", fixed = TRUE)
})

test_that("Windows job contains orphan writers and preserves unrelated processes and profiles", {
  skip_if(.Platform$OS.type != "windows", "Windows job object davranisi")
  env <- .owned_browser_env()
  root <- resolve_repo_root_for_tests()
  temp <- withr::local_tempdir()
  profile <- file.path(temp, intToUtf8(c(0x011f, 0x00fc, 0x015f)), "profile space")
  dir.create(profile, recursive = TRUE)
  marker <- file.path(profile, "prepared-profile")
  writeLines("retained", marker)
  heartbeat <- file.path(profile, "heartbeat")
  writer <- file.path(temp, "writer.R")
  parent <- file.path(temp, "parent.R")
  writeLines(c('args <- commandArgs(TRUE)',
    'repeat { writeLines(as.character(Sys.time()), args[[1]]); Sys.sleep(0.02) }'), writer)
  writeLines(c('args <- commandArgs(TRUE)',
    'p <- processx::process$new(args[[1]], c("--vanilla", args[[2]], args[[3]]), cleanup = FALSE)',
    'while (!file.exists(args[[3]])) Sys.sleep(0.02)',
    'cat("<html><body><div id=\\"status\\">UX_SMOKE_DONE:PASS</div></body></html>\\n")',
    'flush.console()',
    'if (args[[4]] == "natural") quit(status = 0L)',
    'if (args[[4]] == "error") quit(status = 7L)',
    'Sys.sleep(300)'), parent)
  rscript <- file.path(R.home("bin"), "Rscript.exe")
  unrelated <- processx::process$new(rscript, c("--vanilla", "-e", "Sys.sleep(300)"))
  on.exit(unrelated$kill(), add = TRUE)
  for (mode in c("natural", "live", "natural")) {
    unlink(heartbeat)
    result <- env$ux_smoke_owned_browser_run(rscript,
      c("--vanilla", parent, rscript, writer, heartbeat, mode), 20, wd = root)
    expect_identical(result$status, 0L)
    expect_match(result$stdout, "UX_SMOKE_DONE:PASS", fixed = TRUE)
    before <- readLines(heartbeat)
    Sys.sleep(0.2)
    expect_identical(readLines(heartbeat), before)
    expect_identical(readLines(marker), "retained")
    expect_true(unrelated$is_alive())
  }
  # Timeout temizligi ve sonraki kosum ayni hazir profille calisabilmeli.
  timeout_script <- file.path(temp, "timeout.R")
  writeLines(c('args <- commandArgs(TRUE)',
    'p <- processx::process$new(args[[1]], c("--vanilla", args[[2]], args[[3]]), cleanup = FALSE)',
    'Sys.sleep(300)'), timeout_script)
  unlink(heartbeat)
  expect_error(env$ux_smoke_owned_browser_run(rscript,
    c("--vanilla", timeout_script, rscript, writer, heartbeat), 5, wd = root), "timed out")
  before <- readLines(heartbeat)
  Sys.sleep(0.2)
  expect_identical(readLines(heartbeat), before)
  expect_true(unrelated$is_alive())
  expect_identical(readLines(marker), "retained")
})

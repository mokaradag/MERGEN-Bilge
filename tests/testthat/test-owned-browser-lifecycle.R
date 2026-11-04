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
      wd = resolve_repo_root_for_tests(), windows = TRUE, spawn = function(...) child), "Owned browser")
    expect_true(killed)
  }
})

test_that("adaptor hatasi yalniz izinli asama ve Win32 koduyla siniflandirilir", {
  env <- .owned_browser_env()
  run_with <- function(status, stderr) {
    child <- list(poll_io = function(...) NULL, read_output = function() "",
      read_error = function() stderr, is_alive = function() FALSE,
      read_all_output = function() "", read_all_error = function() "",
      write_input = function(...) NULL, get_exit_status = function() status,
      kill_tree = function() NULL)
    tryCatch(env$ux_smoke_owned_browser_run("edge", character(), 10,
      wd = resolve_repo_root_for_tests(), windows = TRUE, spawn = function(...) child),
      ux_smoke_owned_browser_error = identity)
  }
  e <- run_with(125L, "Owned browser launch or cleanup could not be verified.\r\nMERGEN_OWNED_BROWSER_STAGE=assign win32=5\r\n")
  expect_s3_class(e, "ux_smoke_owned_browser_error")
  expect_identical(c(e$failure, e$stage, e$win32), c("browser_launch_failed", "assign", "5"))
  expect_match(conditionMessage(e), "(stage=assign, win32=5)", fixed = TRUE)
  e <- run_with(125L, "MERGEN_OWNED_BROWSER_STAGE=cleanup\n")
  expect_identical(c(e$failure, e$stage), c("browser_cleanup_failed", "cleanup"))
  expect_true(is.na(e$win32))
  # Kisitli PowerShell dil modu ayri cikis koduyla bildirilir.
  e <- run_with(126L, "")
  expect_identical(c(e$failure, e$stage), c("browser_launch_failed", "language_mode"))
  # Sozluk disi metin tasinmaz.
  for (stderr in c("MERGEN_OWNED_BROWSER_STAGE=https://private.example.invalid", "D:/gizli-profil/BrowserUxSmoke", "")) {
    e <- run_with(125L, stderr)
    expect_identical(e$stage, "unknown")
    expect_false(grepl("private|gizli", conditionMessage(e)))
  }
  e <- run_with(124L, "MERGEN_OWNED_BROWSER_STAGE=wait")
  expect_identical(e$failure, "browser_timeout")
})

test_that("inspection errors retain the primary error when emergency cleanup fails", {
  env <- .owned_browser_env()
  child <- list(write_input = function(...) NULL,
    poll_io = function(...) stop("primary poll error"),
    kill_tree = function() stop("secondary cleanup error"))
  expect_error(env$ux_smoke_owned_browser_run("edge", character(), 10,
    wd = resolve_repo_root_for_tests(), windows = TRUE, spawn = function(...) child), "primary poll error")
})

test_that("verified browser errors retain stderr for a clean legacy retry", {
  env <- .owned_browser_env()
  child <- list(poll_io = function(...) NULL, read_output = function() "",
    read_error = function() "unknown --headless=new", is_alive = function() FALSE,
    read_all_output = function() "", read_all_error = function() "",
    write_input = function(...) NULL, get_exit_status = function() 1L)
  result <- env$ux_smoke_owned_browser_run("edge", character(), 10,
    wd = resolve_repo_root_for_tests(), windows = TRUE, spawn = function(...) child)
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

test_that("tarayici basarisizligi izinli tek asama satiriyla siniflandirilir, PASS uretmez", {
  root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  expressions <- parse(file.path(root, "tests/scripts/ai_browser_ux_smoke.R"), encoding = "UTF-8")
  for (e in expressions) {
    if (is.call(e) && identical(e[[1]], as.name("<-")) && is.call(e[[3]]) &&
        identical(e[[3]][[1]], as.name("function"))) eval(e, env)
  }
  source(file.path(root, "tests/scripts/helpers_owned_browser.R"), local = env, encoding = "UTF-8")
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
  env$ux_smoke_cleanup_profile <- function(...) invisible(NULL)
  env$tail_log <- function(...) character()
  calls <- 0L
  outcome <- NULL
  env$ux_smoke_owned_browser_run <- function(...) {
    calls <<- calls + 1L
    if (is.function(outcome)) outcome() else outcome
  }
  page <- function(status) paste0('<html><body><div id="status">', status, '</div></body></html>')
  classify <- function() {
    calls <<- 0L
    out <- capture.output(result <- env$ux_smoke_run_browser())
    expect_identical(result, 1L)
    expect_false(any(grepl("^OK: rendered", out)))
    expect_match(readLines(env$dom_file), "UX_SMOKE_NOT_PASSED", fixed = TRUE)
    grep("^UX_SMOKE_FAILURE: ", out, value = TRUE)
  }
  # Adaptor asamasi korunur; "unknown" iceren hata eski headless denemesini tetiklemez.
  outcome <- function() stop(env$ux_smoke_owned_browser_error(
    "Owned browser launch or cleanup failed (stage=unknown).", "browser_launch_failed", "assign", "5"))
  expect_identical(classify(), "UX_SMOKE_FAILURE: browser_launch_failed rendered=empty exit=124 adapter=assign win32=5")
  expect_identical(calls, 1L)
  outcome <- function() stop(env$ux_smoke_owned_browser_error("Owned browser cleanup timed out.", "browser_cleanup_failed", "cleanup"))
  expect_identical(classify(), "UX_SMOKE_FAILURE: browser_cleanup_failed rendered=empty exit=124 adapter=cleanup")
  outcome <- function() stop(env$ux_smoke_owned_browser_error("Owned browser timed out.", "browser_timeout"))
  expect_identical(classify(), "UX_SMOKE_FAILURE: browser_timeout rendered=empty exit=124")
  # Tam PASS DOM'u olsa bile sifir-disi tarayici cikisi kabul edilmez.
  outcome <- list(status = 3L, stdout = page("UX_SMOKE_DONE:PASS"), stderr = "")
  expect_identical(classify(), "UX_SMOKE_FAILURE: browser_exit_nonzero rendered=pass exit=3")
  outcome <- list(status = 0L, stdout = page("UX_SMOKE_DONE:FAIL quick action"), stderr = "")
  expect_identical(classify(), "UX_SMOKE_FAILURE: rendered_status_fail rendered=fail exit=0")
  outcome <- list(status = 0L, stdout = page("Yükleniyor: navigation"), stderr = "")
  expect_identical(classify(), "UX_SMOKE_FAILURE: rendered_status_incomplete rendered=incomplete exit=0")
  # SSO/proxy sayfasi gibi harness disi DOM ayri siniflanir.
  outcome <- list(status = 0L, stdout = "<html><body><form id=\"kc-form-login\"></form></body></html>", stderr = "")
  expect_identical(classify(), "UX_SMOKE_FAILURE: rendered_status_missing rendered=missing exit=0")
  # Tarayicinin kendi bayrak hatasi eski headless denemesini korur.
  outcome <- function() if (calls == 1L) list(status = 1L, stdout = "", stderr = "unknown --headless=new") else
    list(status = 0L, stdout = page("UX_SMOKE_DONE:PASS"), stderr = "")
  calls <- 0L
  expect_output(expect_identical(env$ux_smoke_run_browser(), 0L), "OK: rendered #status")
  expect_identical(calls, 2L)
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

test_that("Windows adaptoru Turkce ve bosluklu calisma dizininde DOM yakalar ve dogrulanmis temizlik yapar", {
  skip_if(.Platform$OS.type != "windows", "Windows job object davranisi")
  env <- .owned_browser_env()
  root <- resolve_repo_root_for_tests()
  # Gercek VM deposu gibi: ASCII disi karakter ve bosluk iceren calisma dizini.
  wd <- file.path(withr::local_tempdir(), paste0("04 - Geli", intToUtf8(0x015f), "tirme"), "MERGEN Bilge")
  dir.create(file.path(wd, "tests/scripts"), recursive = TRUE)
  for (file in c("run_owned_browser.ps1", "helpers_browser_job.cs")) {
    expect_true(file.copy(file.path(root, "tests/scripts", file), file.path(wd, "tests/scripts")))
  }
  rscript <- file.path(R.home("bin"), "Rscript.exe")
  # Cocuk surec Unicode cwd icinde baslamissa goreli dosyayi bulur; cikti ASCII kalir.
  probe <- paste0("cat(paste0('<html><body><div id=\"status\">', ",
                  "if (file.exists('tests/scripts/helpers_browser_job.cs')) 'CWD_OK' else 'CWD_WRONG', ",
                  "'</div></body></html>\\n'))")
  result <- env$ux_smoke_owned_browser_run(rscript, c("--vanilla", "-e", probe), 30, wd = wd)
  expect_identical(result$status, 0L, info = result$stderr)
  expect_match(result$stdout, '<div id="status">CWD_OK</div>', fixed = TRUE)
  withr::local_dir(wd)
  expect_output(env$ux_smoke_owned_browser_preflight(wd = wd), "OK: owned browser adapter verified.", fixed = TRUE)
})

test_that("Windows adaptoru kisitli PowerShell dil modunu tarayici acmadan ayri asama olarak bildirir", {
  skip_if(.Platform$OS.type != "windows", "PowerShell dil modu davranisi")
  env <- .owned_browser_env()
  root <- resolve_repo_root_for_tests()
  launched <- file.path(withr::local_tempdir(), "launched")
  rscript <- file.path(R.home("bin"), "Rscript.exe")
  # AppLocker/WDAC'in uyguladigi kisitli modu ayni betigin onunde ayarla.
  constrained <- function(command, args, ...) {
    args[[length(args)]] <- paste0("$ExecutionContext.SessionState.LanguageMode = 'ConstrainedLanguage'\n",
                                   args[[length(args)]])
    processx::process$new(command, args, ...)
  }
  e <- tryCatch(env$ux_smoke_owned_browser_run(rscript,
    c("--vanilla", "-e", sprintf("writeLines('x', '%s')", chartr("\\", "/", launched))), 30,
    wd = root, spawn = constrained), ux_smoke_owned_browser_error = identity)
  expect_s3_class(e, "ux_smoke_owned_browser_error")
  expect_identical(c(e$failure, e$stage), c("browser_launch_failed", "language_mode"))
  expect_false(file.exists(launched))
  expect_error(env$ux_smoke_owned_browser_preflight(wd = root, run = function(...)
    env$ux_smoke_owned_browser_run(..., spawn = constrained)), "stage=language_mode", fixed = TRUE)
})

test_that("CP1254 benzeri yerel kod sayfasinda Turkce yol PowerShell adaptorune gecerli UTF-8 olarak gider", {
  # Gercek VM: R yerel kodlamasi CP1254 (s-cedilla = 0xFE). Windows R alt sureci bu
  # kodlamaya zorlanamaz; ayni bayt duzenine sahip Latin-5 locale'de R kosturulur.
  skip_if(.Platform$OS.type == "windows", "Yerel kod sayfasi alt surecte Linux locale ile modellenir")
  skip_if(!nzchar(Sys.which("localedef")), "localedef yok")
  root <- resolve_repo_root_for_tests()
  temp <- withr::local_tempdir()
  locales <- file.path(temp, "locales")
  dir.create(locales)
  built <- processx::run("localedef", c("-i", "tr_TR", "-f", "ISO-8859-9", file.path(locales, "tr_TR.ISO-8859-9")),
                         error_on_status = FALSE)
  skip_if(!identical(built$status, 0L), "Latin-5 Turkce locale olusturulamadi")
  out <- file.path(temp, "stdin.bin")
  child <- file.path(temp, "child.R")
  writeLines(c(
    'args <- commandArgs(TRUE)',
    'stopifnot(!isTRUE(l10n_info()[["UTF-8"]]))',
    'source(file.path(args[[1]], "tests/scripts/helpers_owned_browser.R"))',
    '# getwd() gibi yerel (isaretsiz) kodlu yol ve profil argumani',
    'wd <- file.path(args[[2]], iconv("04 - Geli\\u015ftirme", "UTF-8", ""), "MERGEN Bilge")',
    'stopifnot(Encoding(wd) == "unknown", as.raw(0xfe) %in% charToRaw(wd))',
    'dir.create(file.path(wd, "tests/scripts"), recursive = TRUE)',
    'file.copy(file.path(args[[1]], "tests/scripts/run_owned_browser.ps1"), file.path(wd, "tests/scripts"))',
    'profile <- paste0("--user-data-dir=", iconv("C:/Kullan\\u0131c\\u0131/BrowserUxSmoke", "UTF-8", ""))',
    'sent <- NULL',
    'fake <- list(write_input = function(x) sent <<- x, poll_io = function(...) NULL,',
    '  read_output = function() "<html><body></body></html>", read_error = function() "",',
    '  is_alive = function() FALSE, read_all_output = function() "", read_all_error = function() "",',
    '  get_exit_status = function() 0L, kill_tree = function() NULL)',
    'res <- ux_smoke_owned_browser_run("C:/Edge/msedge.exe", c("--headless=new", profile), 10,',
    '  wd = wd, windows = TRUE, spawn = function(...) fake)',
    '# processx write_input ile ayni bayt donusumu (varsayilan yerel kodlama).',
    'if (is.character(sent)) sent <- iconv(paste(sent, collapse = "\\n"), "", "", toRaw = TRUE)[[1]]',
    'stopifnot(identical(res$status, 0L), is.raw(sent))',
    'writeBin(sent, args[[3]])'), child)
  result <- withr::with_envvar(c(LOCPATH = locales, LANG = "tr_TR.ISO-8859-9", LC_ALL = "tr_TR.ISO-8859-9"),
    processx::run(file.path(R.home("bin"), "Rscript"), c("--vanilla", child, root, temp, out),
                  error_on_status = FALSE))
  expect_identical(result$status, 0L, info = paste(result$stdout, result$stderr))
  bytes <- readBin(out, "raw", file.info(out)$size)
  json <- rawToChar(bytes)
  Encoding(json) <- "UTF-8"
  # PowerShell [Text.UTF8Encoding] ile ayni: gecersiz bayt U+FFFD olur ve yol bozulur.
  expect_true(validUTF8(json))
  expect_false(as.raw(0xfe) %in% bytes)
  expect_identical(tail(bytes, 1L), as.raw(10L))
  config <- jsonlite::fromJSON(json)
  turkish <- paste0("04 - Geli", intToUtf8(0x015f), "tirme/MERGEN Bilge")
  expect_true(endsWith(config$cwd, turkish))
  expect_true(endsWith(config$jobSource, paste0(turkish, "/tests/scripts/helpers_browser_job.cs")))
  expect_identical(config$args[[2]], paste0("--user-data-dir=C:/Kullan", intToUtf8(0x0131), "c", intToUtf8(0x0131), "/BrowserUxSmoke"))
  expect_identical(config$executable, "C:/Edge/msedge.exe")
})

test_that("Windows adaptoru gecersiz UTF-8 girdiyi derlemeden once input asamasinda reddeder", {
  skip_if(.Platform$OS.type != "windows", "PowerShell UTF-8 girdi davranisi")
  root <- resolve_repo_root_for_tests()
  temp <- withr::local_tempdir()
  launched <- file.path(temp, "launched")
  # VM'deki bozuk yuk: CP1254 s-cedilla (0xFE) UTF-8 akisina ham olarak girmis.
  payload <- c(charToRaw('{"executable":"C:/Windows/System32/cmd.exe","args":["/d","/c","type nul > '),
               charToRaw(chartr("/", "\\", launched)), charToRaw('"],"cwd":"C:/Geli'), as.raw(0xfe),
               charToRaw('tirme","timeoutMs":10000,"jobSource":"C:/Geli'), as.raw(0xfe),
               charToRaw('tirme/helpers_browser_job.cs"}'), as.raw(10L))
  input <- file.path(temp, "stdin.bin")
  writeBin(payload, input)
  script <- paste(readLines(file.path(root, "tests/scripts/run_owned_browser.ps1"), warn = FALSE), collapse = "\n")
  result <- processx::run("powershell.exe", c("-NoProfile", "-NonInteractive", "-Command", script),
                          stdin = input, error_on_status = FALSE, timeout = 60)
  expect_identical(result$status, 125L, info = result$stderr)
  expect_match(result$stderr, "MERGEN_OWNED_BROWSER_STAGE=input", fixed = TRUE)
  expect_false(grepl("Geli", result$stderr, fixed = TRUE))
  expect_false(file.exists(launched))
})

test_that("Windows job durdurmasi dogal hata cikisini korur, yalniz kendi sonlandirmasini Stopped sayar", {
  skip_if(.Platform$OS.type != "windows", "Windows job object davranisi")
  root <- resolve_repo_root_for_tests()
  source <- chartr("/", "\\", file.path(root, "tests/scripts/helpers_browser_job.cs"))
  cmd <- file.path(Sys.getenv("SystemRoot"), "System32", "cmd.exe")
  script <- paste(
    "$ErrorActionPreference='Stop'",
    sprintf("Add-Type -LiteralPath '%s'", source),
    # Kok dogal olarak 7 ile cikar; sonra Stop cagrilir.
    sprintf("$a=[MergenBrowserJob]::new('%s', [string[]]@('/d','/c','exit 7'), $env:TEMP)", cmd),
    "while ($null -eq $a.ExitCode) { Start-Sleep -Milliseconds 10 }",
    "$a.Stop(5000); Write-Output ('natural ' + $a.Stopped + ' ' + $a.ExitCode); $a.Dispose()",
    # Canli kok job tarafindan sonlandirilir.
    sprintf("$b=[MergenBrowserJob]::new('%s', [string[]]@('/d','/c','ping -n 30 127.0.0.1 > nul'), $env:TEMP)", cmd),
    "Start-Sleep -Milliseconds 300",
    "$b.Stop(5000); Write-Output ('live ' + $b.Stopped + ' ' + ($b.ExitCode -eq [int][MergenBrowserJob]::OwnedStopCode)); $b.Dispose()",
    sep = "\n")
  result <- processx::run("powershell.exe", c("-NoProfile", "-NonInteractive", "-Command", script),
                          error_on_status = FALSE, timeout = 60)
  expect_identical(result$status, 0L, info = result$stderr)
  lines <- trimws(strsplit(result$stdout, "\n", fixed = TRUE)[[1]])
  expect_true("natural False 7" %in% lines, info = result$stdout)
  expect_true("live True True" %in% lines, info = result$stdout)
})

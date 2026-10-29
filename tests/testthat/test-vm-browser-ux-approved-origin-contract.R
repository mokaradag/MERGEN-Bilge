# Windows VM: bind adresi / SSO origin / kosuya ozel kaynak yolu sozlesmesi.
.vm_ux_functions <- function(path = "tests/scripts/run_vm_browser_ux_smoke.R") {
  env <- new.env(parent = globalenv())
  for (e in parse_r_file_utf8(file.path(resolve_repo_root_for_tests(), path))) {
    if (is.call(e) && identical(e[[1]], as.name("<-")) && is.call(e[[3]]) &&
        identical(e[[3]][[1]], as.name("function"))) eval(e, env)
  }
  env
}

test_that("VM startup her kosuda yeni 192-bit onek uretir, URL guvenli kurulur", {
  env <- .vm_ux_functions()
  prefixes <- replicate(20, env$vm_ux_new_prefix())
  expect_true(all(vapply(prefixes, env$vm_ux_prefix_valid, logical(1))))
  expect_equal(length(unique(prefixes)), 20L)
  for (base in c("https://app.example.invalid/base", "https://app.example.invalid/base/")) {
    expect_identical(env$vm_ux_smoke_url(base, prefixes[[1]]),
                     paste0("https://app.example.invalid/base/", prefixes[[1]], "/ux-smoke.html?autostart=1"))
  }
  for (bad in c("", "/", "smoke", "www", "../", paste0(prefixes[[1]], "/"),
                paste0(prefixes[[1]], "\n"), paste(rep("f", 1000), collapse = ""))) {
    expect_false(env$vm_ux_prefix_valid(bad))
    expect_error(env$vm_ux_smoke_url("https://app.example.invalid", bad), "Invalid per-run")
  }
  for (bad in c("", "file:///tmp", "https://user:secret@app.example.invalid/base",
                "https://app.example.invalid/base?token=x", "https://app.example.invalid/base#x",
                "https://app.example.invalid/base\n", "https://app.example.invalid\\base")) {
    expect_error(env$vm_ux_base_url(bad), "MERGEN_BROWSER_UX_BASE_URL")
  }
})

test_that("VM startup ayni 0.0.0.0:8009 topolojisini ve gercek ortam aktarimini korur", {
  env <- .vm_ux_functions()
  withr::local_envvar(MERGEN_ENABLE_UX_SMOKE = NA, MERGEN_ALLOW_NETWORK_UX_SMOKE = NA,
                     MERGEN_UX_SMOKE_PATH = NA, MERGEN_HOST = NA, MERGEN_PORT = NA,
                     MERGEN_RUN_APP = NA)
  runtime <- file.path(withr::local_tempdir(), "run")
  first <- NULL
  # source sonrasi .Renviron override'ina ragmen gecici opt-in sonradan verilir.
  env$source <- function(...) Sys.setenv(MERGEN_ENABLE_UX_SMOKE = "false")
  env$run_mergen_app <- function(host, port, ...) {
    expect_identical(host, "0.0.0.0")
    expect_identical(port, 8009L)
    first <<- env$vm_ux_read_prefix(runtime)
    expect_identical(Sys.getenv("MERGEN_UX_SMOKE_PATH"), first)
    expect_identical(Sys.getenv("MERGEN_ENABLE_UX_SMOKE"), "true")
    expect_identical(Sys.getenv("MERGEN_ALLOW_NETWORK_UX_SMOKE"), "true")
    expect_error(env$vm_ux_start_app(runtime), "already exists")
  }
  env$vm_ux_start_app(runtime)
  expect_false(dir.exists(runtime))
  expect_error(env$vm_ux_read_prefix(runtime), "No active smoke startup")
  env$run_mergen_app <- function(...) {
    expect_false(identical(env$vm_ux_read_prefix(runtime), first))
    stop("simulated bind/boot failure")
  }
  expect_error(env$vm_ux_start_app(runtime), "simulated bind/boot failure")
  expect_false(dir.exists(runtime))
  dir.create(runtime)
  writeLines("../www", file.path(runtime, "prefix"))
  expect_error(env$vm_ux_read_prefix(runtime), "Invalid VM smoke handshake")
})

test_that("VM wrapper PASS icin rendered sonucu ister ve gecici env degerlerini geri alir", {
  env <- .vm_ux_functions()
  withr::local_dir(resolve_repo_root_for_tests())
  runtime <- withr::local_tempdir()
  prefix <- env$vm_ux_new_prefix()
  writeLines(prefix, file.path(runtime, "prefix"))
  env$vm_ux_runtime_dir <- function() runtime
  profile <- withr::local_tempdir()
  withr::local_envvar(MERGEN_BROWSER_UX_BASE_URL = "https://app.example.invalid/base",
                     MERGEN_BROWSER_UX_PROFILE_DIR = profile, MERGEN_UX_SMOKE_PATH = NA,
                     MERGEN_ALLOW_NETWORK_UX_SMOKE = NA)
  answer <- "OK: rendered #status is UX_SMOKE_DONE:PASS.\n"
  status <- 0L
  testthat::local_mocked_bindings(run = function(command, args, ...) {
    expect_identical(Sys.getenv("MERGEN_UX_SMOKE_PATH"), prefix)
    expect_identical(Sys.getenv("MERGEN_ALLOW_NETWORK_UX_SMOKE"), "true")
    expect_false(any(grepl("app.example.invalid|__mergen_ux_", args)))
    expect_true("--require-browser" %in% args)
    list(status = status, stdout = answer, stderr = "")
  }, .package = "processx")
  expect_true(env$vm_ux_main(character()))
  expect_identical(Sys.getenv("MERGEN_UX_SMOKE_PATH", unset = "unset"), "unset")
  expect_identical(Sys.getenv("MERGEN_ALLOW_NETWORK_UX_SMOKE", unset = "unset"), "unset")
  for (wrong in c("", "HTTP 200", "UX_SMOKE_DONE:PASS", "SKIP", "<script>UX_SMOKE_DONE:PASS</script>")) {
    answer <- wrong
    expect_error(env$vm_ux_main(character()), "rendered UX_SMOKE_DONE:PASS is required")
  }
  answer <- "OK: rendered #status is UX_SMOKE_DONE:PASS.\n"
  status <- 1L
  expect_error(env$vm_ux_main(character()), "rendered UX_SMOKE_DONE:PASS is required")
})

test_that("generic browser VM akisinda yerel preflight ve dis URL ayri kullanilir; artifact redakte edilir", {
  withr::local_dir(resolve_repo_root_for_tests())
  env <- new.env(parent = globalenv())
  prefix <- .vm_ux_functions()$vm_ux_new_prefix()
  profile <- withr::local_tempdir()
  artifact <- withr::local_tempdir()
  binary <- tempfile(); writeLines("mock browser", binary)
  withr::defer(unlink(binary))
  base <- "https://private.example.invalid/base"
  withr::local_envvar(MERGEN_BROWSER_UX_BASE_URL = base, MERGEN_UX_SMOKE_PATH = prefix,
                     MERGEN_ALLOW_NETWORK_UX_SMOKE = "true", MERGEN_BROWSER_BIN = binary,
                     MERGEN_BROWSER_UX_PROFILE_DIR = profile)
  env$commandArgs <- function(...) c("--artifact-dir", artifact, "--port", "8009")
  env$quit <- function(status) stop(structure(list(message = "runner exit", status = status), class = c("runner_exit", "error", "condition")))
  requests <- character()
  browser_url <- NULL
  testthat::local_mocked_bindings(run = function(command, args, ...) {
    browser_url <<- tail(args, 1)
    list(status = 0L, stdout = paste0('<div id="status">UX_SMOKE_DONE:PASS</div><a href="', base,
         '/', prefix, '/x">x</a> https://private.example.invalid/redirect https://sso.example.invalid/auth'),
         stderr = paste(base, utils::URLencode(base, reserved = TRUE), prefix))
  }, .package = "processx")
  expressions <- parse_r_file_utf8("tests/scripts/ai_browser_ux_smoke.R")
  run <- function() {
    for (e in expressions) {
      if (is.call(e) && identical(e[[1]], as.name("<-")) && identical(e[[2]], as.name("read_url"))) {
        env$read_url <- function(target) {
          requests <<- c(requests, target)
          '<title>MERGEN UX Smoke</title><div id="status">Ready</div>'
        }
      } else eval(e, env)
    }
  }
  result <- tryCatch(run(), runner_exit = function(e) e)
  expect_identical(result$status, 0)
  expect_identical(browser_url, paste0(base, "/", prefix, "/ux-smoke.html?autostart=1"))
  expect_identical(requests, c("http://127.0.0.1:8009", paste0("http://127.0.0.1:8009/", prefix, "/ux-smoke.html")))
  logs <- paste(vapply(list.files(artifact, full.names = TRUE), read_source_text_utf8, character(1)), collapse = "\n")
  expect_false(grepl("private.example.invalid|sso.example.invalid|__mergen_ux_[0-9a-f]{48}", logs))
  expect_match(logs, "<MERGEN_BROWSER_UX_BASE_URL>", fixed = TRUE)
})

test_that("VM belge ve kaynaklarda onayli URL runtime girdisidir, sabit ag smoke yolu yoktur", {
  root <- resolve_repo_root_for_tests()
  doc <- read_source_text_utf8(file.path(root, "docs/vm-browser-ux-smoke.md"))
  runner <- read_source_text_utf8(file.path(root, "tests/scripts/run_vm_browser_ux_smoke.R"))
  expect_match(doc, "0.0.0.0:8009", fixed = TRUE)
  expect_match(doc, "Read-Host", fixed = TRUE)
  expect_match(doc, "app.example.invalid", fixed = TRUE)
  expect_match(doc, "--start-app", fixed = TRUE)
  expect_false(grepl("/smoke/ux-smoke.html", runner, fixed = TRUE))
  expect_false(grepl("readRenviron|write.*Renviron", runner))
  for (url in regmatches(doc, gregexpr("https://[^`[:space:]]+", doc))[[1]]) {
    expect_match(url, "https://app.example.invalid", fixed = TRUE)
  }
})

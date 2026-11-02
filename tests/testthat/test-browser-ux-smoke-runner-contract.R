# ==============================================================================
# Dosya Yolu: tests/testthat/test-browser-ux-smoke-runner-contract.R
# Açıklama: Headless browser UX smoke runner'ın opsiyonel, bağımlılık-hafif
#           ve --boot-smoke akışına bağlı kalmasını korur.
# ==============================================================================

.browser_runner_repo_root <- function() {
  candidates <- unique(normalizePath(
    c(getwd(), file.path(getwd(), ".."), file.path(getwd(), "..", "..")),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "tests", "scripts")) &&
        dir.exists(file.path(candidate, "tests", "smoke"))) {
      return(candidate)
    }
  }

  stop("Browser UX smoke runner contract repo kökü bulunamadı.", call. = FALSE)
}

.browser_runner_read_text <- function(...) {
  path <- file.path(.browser_runner_repo_root(), ...)

  if (!file.exists(path)) {
    stop(sprintf("Beklenen dosya bulunamadı: %s", path), call. = FALSE)
  }

  size <- suppressWarnings(file.info(path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  enc2utf8(gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE))
}

.browser_runner_expect_all <- function(text, tokens, label) {
  missing <- tokens[!vapply(
    tokens,
    function(token) grepl(token, text, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  testthat::expect_equal(
    missing,
    character(0),
    info = paste(label, paste(missing, collapse = ", "))
  )
}

testthat::test_that("Windows browser scripts keep ASCII source and parse under local encodings", {
  for (script in c("ai_browser_ux_smoke.R", "diagnose_browser_ux_fixture.R", "run_vm_browser_ux_smoke.R")) {
    path <- file.path(.browser_runner_repo_root(), "tests", "scripts", script)
    raw <- readBin(path, what = "raw", n = file.info(path)$size)
    testthat::expect_true(all(as.integer(raw) <= 127L), info = script)
    for (encoding in c("UTF-8", "WINDOWS-1254")) {
      connection <- file(path, open = "rt", encoding = encoding)
      tryCatch(testthat::expect_no_warning(parse(file = connection)),
               finally = close(connection))
    }
  }
})

testthat::test_that("browser UX smoke runner is optional and dependency-light", {
  runner <- .browser_runner_read_text("tests", "scripts", "ai_browser_ux_smoke.R")

  .browser_runner_expect_all(
    runner,
    c(
      "Dosya Yolu: tests/scripts/ai_browser_ux_smoke.R",
      "%s/%s/ux-smoke.html?autostart=1",
      "MERGEN_BROWSER_BIN",
      "MERGEN_REQUIRE_BROWSER_UX_SMOKE",
      "--require-browser",
      "browser_bin_explicit",
      "MERGEN_BROWSER_BIN kullan\\u0131lam\\u0131yor",
      "processx::process$new",
      "processx::run",
      "google-chrome",
      "chromium",
      "microsoft-edge",
      "msedge",
      "--headless=new",
      "--headless",
      "--dump-dom",
      "--timeout=",
      "--autoplay-policy=no-user-gesture-required",
      "UX_SMOKE_DONE:PASS",
      "UX_SMOKE_DONE:FAIL",
      "SKIP: Chrome/Chromium/Edge binary bulunamad\\u0131",
      "run_mergen_app(host='127.0.0.1'",
      "MERGEN_RUN_APP='false'",
      "MERGEN_DISABLE_FUTURES='true'"
    ),
    "Headless browser UX smoke runner sözleşmesi eksik:"
  )

  # Yasak bağımlılık taraması yorum satırlarını değil, çalıştırılabilir kodu
  # hedeflemelidir. Aksi halde "npm kullanmaz" gibi güvenli açıklama yorumları
  # yanlış pozitif üretir.
  runner_code <- gsub("(?m)^\\s*#.*$", "", runner, perl = TRUE)

  forbidden <- c(
    "chromote::",
    "RSelenium",
    "selenium",
    "playwright",
    "npm ",
    "npx ",
    "yarn ",
    "install.packages(",
    "download.file("
  )

  found_forbidden <- forbidden[vapply(
    forbidden,
    function(token) grepl(token, runner_code, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  testthat::expect_equal(
    found_forbidden,
    character(0),
    info = "Browser UX smoke runner ağır/harici otomasyon veya runtime download getirmemelidir."
  )
})

testthat::test_that("browser UX smoke runner is wired only through boot-smoke validation", {
  repo_check <- .browser_runner_read_text("tests", "scripts", "ai_repo_check.R")

  .browser_runner_expect_all(
    repo_check,
    c(
      "tests/testthat/test-browser-ux-smoke-runner-contract.R",
      "if (isTRUE(boot_smoke))",
      "\"shiny boot smoke\"",
      "tests/scripts/ai_boot_smoke.R",
      "\"browser UX smoke\"",
      "tests/scripts/ai_browser_ux_smoke.R"
    ),
    "ai_repo_check browser UX smoke entegrasyonu eksik:"
  )

  boot_pos <- regexpr(
    "if (isTRUE(boot_smoke))",
    repo_check,
    fixed = TRUE,
    useBytes = TRUE
  )[[1]]

  browser_pos <- regexpr(
    "tests/scripts/ai_browser_ux_smoke.R",
    repo_check,
    fixed = TRUE,
    useBytes = TRUE
  )[[1]]

  testthat::expect_true(boot_pos > 0L)
  testthat::expect_true(
    browser_pos > boot_pos,
    info = "Browser UX smoke yalnızca --boot-smoke bloğunda çalıştırılmalıdır."
  )
})

testthat::test_that("tanılama açık tarayıcı seçimini ve Node hata durumunu korur", {
  root <- .browser_runner_repo_root()
  withr::local_dir(root)
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  browser <- withr::local_tempfile(fileext = if (.Platform$OS.type == "windows") ".exe" else "")
  file.copy(rscript, browser)
  Sys.chmod(browser, mode = "0700")
  discovery <- withr::local_tempdir()
  withr::local_envvar(c(MERGEN_BROWSER_BIN = browser, PROGRAMFILES = discovery, "PROGRAMFILES(X86)" = discovery))
  expressions <- parse_r_file_utf8(file.path(root, "tests/scripts/diagnose_browser_ux_fixture.R"))
  env <- new.env(parent = globalenv())
  env$Sys.which <- function(x) {
    if (identical(x, "node")) "mock-node" else if (length(x) > 1L) rep(browser, length(x)) else ""
  }
  env$ux_smoke_check_edge_policy <- function(...) invisible(TRUE)
  status <- 0L
  calls <- 0L
  env$system2 <- function(command, args, ...) {
    calls <<- calls + 1L
    testthat::expect_identical(command, "mock-node")
    testthat::expect_true(shQuote(normalizePath(browser, winslash = "/")) %in% args)
    if (status == 0L) "node ok" else structure("node failed", status = status)
  }
  testthat::expect_output(eval(expressions, env), "Node diagnostic exit status: 0", fixed = TRUE)
  Sys.unsetenv("MERGEN_BROWSER_BIN")
  testthat::expect_output(eval(expressions, env), "Node diagnostic exit status: 0", fixed = TRUE)
  Sys.setenv(MERGEN_BROWSER_BIN = browser)
  status <- 17L
  testthat::expect_error(eval(expressions, env), "Node browser diagnostic failed", fixed = TRUE)
  before <- calls
  Sys.setenv(MERGEN_BROWSER_BIN = paste0(browser, "-missing"))
  testthat::expect_error(eval(expressions, env), "MERGEN_BROWSER_BIN", fixed = TRUE)
  testthat::expect_identical(calls, before)
  Sys.setenv(MERGEN_BROWSER_BIN = dirname(browser))
  testthat::expect_error(eval(expressions, env), "MERGEN_BROWSER_BIN", fixed = TRUE)

  # Gerçek dış Rscript hata kodu, Node başarısızlığını çağırana taşır.
  Sys.setenv(MERGEN_BROWSER_BIN = browser)
  expression <- paste0(
    "env <- new.env(parent=globalenv()); ",
    "env$Sys.which <- function(x) 'mock-node'; ",
    "env$system2 <- function(...) structure('node failed', status=17L); ",
    "sys.source('tests/scripts/diagnose_browser_ux_fixture.R', envir=env)"
  )
  result <- processx::run(rscript, c("--vanilla", "-e", expression), wd = root, error_on_status = FALSE)
  testthat::expect_gt(result$status, 0L)
  testthat::expect_match(result$stdout, "Node diagnostic exit status: 17", fixed = TRUE)
  testthat::expect_match(result$stderr, "Node browser diagnostic failed", fixed = TRUE)
})

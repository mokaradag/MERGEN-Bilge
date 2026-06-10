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
        dir.exists(file.path(candidate, "www", "smoke"))) {
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

testthat::test_that("browser UX smoke runner is optional and dependency-light", {
  runner <- .browser_runner_read_text("tests", "scripts", "ai_browser_ux_smoke.R")

  .browser_runner_expect_all(
    runner,
    c(
      "Dosya Yolu: tests/scripts/ai_browser_ux_smoke.R",
      "/smoke/ux-smoke.html",
      "MERGEN_BROWSER_BIN",
      "MERGEN_REQUIRE_BROWSER_UX_SMOKE",
      "--require-browser",
      "browser_bin_explicit",
      "MERGEN_BROWSER_BIN kullanılamıyor",
      "processx::process$new",
      "processx::run",
      "google-chrome",
      "chromium",
      "microsoft-edge",
      "msedge",
      "--headless=new",
      "--headless",
      "--dump-dom",
      "--virtual-time-budget",
      "--autoplay-policy=no-user-gesture-required",
      "UX_SMOKE_DONE:PASS",
      "UX_SMOKE_DONE:FAIL",
      "SKIP: Chrome/Chromium/Edge binary bulunamadı",
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
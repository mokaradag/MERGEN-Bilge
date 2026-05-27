# ==============================================================================
# Dosya Yolu: tests/testthat/test-ai-package-bootstrap-contract.R
# Açıklama: AI bootstrap paket kurulumu sözleşmesini korur.
# ==============================================================================

.ai_bootstrap_repo_root <- function() {
  candidates <- unique(normalizePath(
    c(getwd(), file.path(getwd(), ".."), file.path(getwd(), "..", "..")),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "tests", "scripts")) &&
        dir.exists(file.path(candidate, "tools"))) {
      return(candidate)
    }
  }

  stop("AI bootstrap contract repo kökü bulunamadı.", call. = FALSE)
}

.ai_bootstrap_read_text <- function(...) {
  path <- file.path(.ai_bootstrap_repo_root(), ...)
  testthat::expect_true(file.exists(path), info = paste("Eksik dosya:", path))

  txt <- readLines(path, warn = FALSE, encoding = "UTF-8")
  enc2utf8(paste(txt, collapse = "\n"))
}

.ai_bootstrap_expect_all <- function(text, tokens, label) {
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

testthat::test_that("ci installer defaults to Linux-safe source pkg type while keeping override", {
  installer <- .ai_bootstrap_read_text("tests", "scripts", "ci_install_packages.R")

  .ai_bootstrap_expect_all(
    installer,
    c(
      "default_pkg_type <- \"source\"",
      "MERGEN_AI_R_PKG_TYPE",
      "pkg_type_env %in% c(\"source\", \"binary\")",
      "Package type override from MERGEN_AI_R_PKG_TYPE"
    ),
    "CI installer package type sözleşmesi eksik:"
  )

  testthat::expect_false(
    grepl('default_pkg_type\\s*<-\\s*\"binary\"', installer, perl = TRUE, useBytes = TRUE),
    info = "Varsayılan package type Linux'ta desteklenmeyen binary olmamalıdır."
  )

  testthat::expect_true(
    grepl("type 'binary' is not supported on this platform", installer, fixed = TRUE, useBytes = TRUE),
    info = "Linux/RSPM package type notu korunmalıdır."
  )
})

testthat::test_that("setup script keeps noble/jammy RSPM wiring and no browser smoke deps in bootstrap", {
  setup_script <- .ai_bootstrap_read_text("tools", "setup_ai_r_environment.sh")
  installer <- .ai_bootstrap_read_text("tests", "scripts", "ci_install_packages.R")

  .ai_bootstrap_expect_all(
    setup_script,
    c(
      "__linux__/noble/latest",
      "__linux__/jammy/latest",
      "https://packagemanager.posit.co/cran/__linux__/"
    ),
    "setup_ai_r_environment RSPM sözleşmesi eksik:"
  )

  forbidden <- c(
    "playwright",
    "selenium",
    "chromote",
    "RSelenium",
    "npm",
    "npx",
    "download.file("
  )

  found_forbidden <- forbidden[vapply(
    forbidden,
    function(token) grepl(token, installer, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  testthat::expect_equal(
    found_forbidden,
    character(0),
    info = "Paket bootstrap akışına browser otomasyon bağımlılığı eklenmemelidir."
  )
})

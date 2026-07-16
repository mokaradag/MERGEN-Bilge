# Bilge Yolaç zaman aşımı varsayılanı ve UI sınırı için hafif sözleşme testi.

testthat::test_that("Bilge Yolaç timeout defaults to four hours", {
  find_root <- function() {
    candidates <- c(".", "..", "../..", "../../..")
    for (candidate in candidates) {
      if (file.exists(file.path(candidate, "R", "config_claude_code.R"))) {
        return(normalizePath(candidate, winslash = "/", mustWork = TRUE))
      }
    }
    stop("Depo kökü bulunamadı.")
  }

  root <- find_root()
  read_repo <- function(...) {
    paste(
      readLines(file.path(root, ...), warn = FALSE, encoding = "UTF-8"),
      collapse = "\n"
    )
  }

  config_text <- read_repo("R", "config_claude_code.R")
  ui_text <- read_repo("R", "module_settings_yapilandirma_ui.R")
  env_text <- read_repo(".Renviron.example")
  docs_text <- read_repo("docs", "technical-reference.md")

  testthat::expect_match(
    config_text,
    'Sys.getenv\\("CLAUDE_CODE_TIMEOUT", "14400"\\)',
    perl = TRUE
  )
  testthat::expect_match(ui_text, "max = 14400", fixed = TRUE)
  testthat::expect_match(ui_text, "step = 300", fixed = TRUE)
  testthat::expect_match(ui_text, "en fazla 4 saat", fixed = TRUE)
  testthat::expect_match(env_text, "CLAUDE_CODE_TIMEOUT=14400", fixed = TRUE)
  testthat::expect_match(docs_text, "CLAUDE_CODE_TIMEOUT=14400", fixed = TRUE)
  testthat::expect_false(grepl("CLAUDE_CODE_TIMEOUT=600", docs_text, fixed = TRUE))
})

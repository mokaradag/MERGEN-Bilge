# ==============================================================================
# Dosya Yolu: tests/testthat/test-logging-console-color-policy.R
# Açıklama: Windows VM üretim loglarında ANSI renk kodlarının varsayılan olarak
#           kapalı kalmasını statik sözleşme ile korur.
# ==============================================================================

.read_repo_text_quiet_logging <- function(path) {
  repo_root <- if (exists("resolve_repo_root_for_tests", mode = "function")) {
    resolve_repo_root_for_tests()
  } else {
    normalizePath(".", winslash = "/", mustWork = TRUE)
  }

  full_path <- file.path(repo_root, path)
  size <- suppressWarnings(file.info(full_path)$size[1])

  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  if (length(raw_data) >= 3L &&
      identical(as.integer(raw_data[1:3]), c(239L, 187L, 191L))) {
    raw_data <- raw_data[-(1:3)]
  }

  raw_data <- raw_data[raw_data != as.raw(0)]
  txt <- rawToChar(raw_data, multiple = FALSE)
  Encoding(txt) <- "UTF-8"
  txt <- enc2utf8(txt)
  gsub("\\r\\n?|\\r", "\\n", txt, perl = TRUE)
}

test_that("konsol renkli loglama üretimde opt-in yapılır", {
  txt <- .read_repo_text_quiet_logging("R/config_logging.R")

  beklenenler <- c(
    "MERGEN_LOG_CONSOLE_COLORS",
    "use_console_colors <-",
    "if (isTRUE(use_console_colors))",
    "log_layout(layout_glue_colors, index = 2)",
    "log_layout(layout_glue, index = 2)"
  )

  bulunanlar <- vapply(
    beklenenler,
    function(x) grepl(x, txt, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )

  expect_true(
    all(bulunanlar),
    info = paste("Eksik log renk politikası kayıtları:", paste(beklenenler[!bulunanlar], collapse = ", "))
  )
})

test_that("konsol renkleri varsayılan açık değildir", {
  txt <- .read_repo_text_quiet_logging("R/config_logging.R")

  expect_false(
    grepl(
      'Sys.getenv("MERGEN_LOG_CONSOLE_COLORS", "true")',
      txt,
      fixed = TRUE,
      useBytes = TRUE
    ),
    info = "MERGEN_LOG_CONSOLE_COLORS varsayılanı true olmamalıdır."
  )
})
# ==============================================================================
# Dosya Yolu: tests/testthat/test-prod-log-path-mojibake-review-regressions.R
# Açıklama: Codex incelemesindeki yalıtılmış ortam ve karma kanıt regresyonları.
# ==============================================================================

testthat::local_edition(3)

codex_log_review_read_utf8 <- function(path) {
  size <- suppressWarnings(file.info(path)$size[[1]])
  testthat::expect_false(is.na(size))

  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_content <- readBin(con, what = "raw", n = size)
  text <- iconv(
    list(raw_content),
    from = "UTF-8",
    to = "UTF-8",
    sub = "byte"
  )[[1]]

  testthat::expect_false(is.na(text))
  text <- gsub("\r\n?|\r", "\n", text, perl = TRUE)
  Encoding(text) <- "UTF-8"
  text
}

codex_log_review_load_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = baseenv())
  files <- c(
    file.path(repo_root, "R", "utils_text_encoding.R"),
    file.path(repo_root, "R", "bootstrap_log_path.R")
  )

  for (path in files) {
    expressions <- parse(
      text = codex_log_review_read_utf8(path),
      encoding = "UTF-8",
      keep.source = FALSE
    )
    for (expr in expressions) {
      eval(expr, envir = env)
    }
  }

  env
}

codex_log_review_u <- function(...) {
  intToUtf8(as.integer(c(...)))
}

test_that("yalıtılmış launcher ortamı yardımcıları kendi sözlüksel ortamından çözer", {
  env <- codex_log_review_load_env()
  corrupt <- paste0(
    "//server/Geli",
    codex_log_review_u(0x00C5, 0x0178),
    "tirme/logs"
  )
  expected <- paste0(
    "//server/Geli",
    codex_log_review_u(0x015F),
    "tirme/logs"
  )

  expect_true(env$mergen_log_path_has_strong_mojibake(corrupt))
  expect_identical(env$repair_mergen_log_dir(corrupt), expected)
})

test_that("güçlü onarım aynı yoldaki belirsiz bileşeni değiştirmez", {
  env <- codex_log_review_load_env()
  root <- tempfile(pattern = "mergen-codex-log-")
  corrupt_segment <- paste0(
    "Geli",
    codex_log_review_u(0x00C5, 0x0178),
    "tirme"
  )
  repaired_segment <- paste0(
    "Geli",
    codex_log_review_u(0x015F),
    "tirme"
  )
  ambiguous_segment <- codex_log_review_u(0x00C2, 0x00A9)
  input <- file.path(root, corrupt_segment, ambiguous_segment, "logs")
  expected <- file.path(root, repaired_segment, ambiguous_segment, "logs")

  expect_true(dir.create(input, recursive = TRUE))
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)

  expect_identical(
    env$repair_mergen_log_dir(input),
    enc2utf8(expected)
  )
})

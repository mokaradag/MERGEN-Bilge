# ==============================================================================
# Dosya Yolu: tests/testthat/test-text-encoding-utils.R
# Açıklama: UTF-8, Türkçe karakter, emoji ve mojibake sözleşmelerini korur.
# ==============================================================================

.source_text_encoding_utils_for_test <- function() {
  repo_root <- resolve_repo_root_for_tests()
  test_env <- new.env(parent = globalenv())

  source(
    file.path(repo_root, "R", "utils_text_encoding.R"),
    encoding = "UTF-8",
    local = test_env
  )

  test_env
}

.mojibake_from_utf8_for_test <- function(text) {
  win1252 <- c(
    0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
    0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
    0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178
  )

  raw_bytes <- as.integer(charToRaw(enc2utf8(text)))

  paste0(vapply(raw_bytes, function(byte) {
    if (byte < 0x80L || byte >= 0xA0L) {
      return(intToUtf8(byte))
    }
    intToUtf8(win1252[byte - 0x7FL])
  }, character(1), USE.NAMES = FALSE), collapse = "")
}

test_that("normalize_text_utf8 Türkçe karakter ve emojiyi korur", {
  env <- .source_text_encoding_utils_for_test()

  sample_text <- "ç ğ ı İ ö ş ü Ç Ğ I Ö Ş Ü — “tırnak” • ✅ 🚀"

  expect_equal(
    env$normalize_text_utf8(sample_text, repair_mojibake = TRUE),
    sample_text
  )
})

test_that("normalize_text_utf8 yaygın Windows mojibake bozulmasını onarır", {
  env <- .source_text_encoding_utils_for_test()

  sample_text <- "ç ğ ı İ ö ş ü Ç Ğ I Ö Ş Ü — “tırnak” • ✅ 🚀"
  mojibake <- .mojibake_from_utf8_for_test(sample_text)

  expect_false(identical(mojibake, sample_text))
  expect_equal(
    env$normalize_text_utf8(mojibake, repair_mojibake = TRUE),
    sample_text
  )
})

test_that("normalize_text_for_log ANSI dizilerini temizler ve metni okunur tutar", {
  env <- .source_text_encoding_utils_for_test()

  mojibake <- .mojibake_from_utf8_for_test("çalışıyor ✅")
  colored <- paste0("\033[1m", mojibake, "\033[0m")

  expect_equal(env$normalize_text_for_log(colored), "çalışıyor ✅")
})

test_that("read_text_lines_utf8 UTF-8 markdown satırlarını güvenli okur", {
  env <- .source_text_encoding_utils_for_test()

  sample_lines <- c(
    "## v1.0 | 2026-05-12 | Türkçe Sürüm",
    "- ç ğ ı İ ö ş ü Ç Ğ I Ö Ş Ü — “tırnak” • ✅ 🚀"
  )

  tmp <- tempfile(fileext = ".md")
  con <- file(tmp, open = "wb")
  on.exit({
    try(close(con), silent = TRUE)
    unlink(tmp, force = TRUE)
  }, add = TRUE)

  writeBin(charToRaw(enc2utf8(paste(sample_lines, collapse = "\n"))), con)
  close(con)

  expect_equal(
    env$read_text_lines_utf8(tmp, repair_mojibake = TRUE),
    sample_lines
  )
})

test_that("client encoding helper manifest ve Bilge Yolaç sözleşmesi korunur", {
  repo_root <- resolve_repo_root_for_tests()

  encoding_js <- paste(
    readLines(
      file.path(repo_root, "www", "js", "encoding_utils.js"),
      warn = FALSE,
      encoding = "UTF-8"
    ),
    collapse = "\n"
  )

  streaming_js <- paste(
    readLines(
      file.path(repo_root, "www", "js", "claude_code_streaming.js"),
      warn = FALSE,
      encoding = "UTF-8"
    ),
    collapse = "\n"
  )

  ui_manifest <- paste(
    readLines(
      file.path(repo_root, "R", "config_ui_assets.R"),
      warn = FALSE,
      encoding = "UTF-8"
    ),
    collapse = "\n"
  )

  expect_match(encoding_js, "window\\.MergenEncoding")
  expect_match(encoding_js, "window\\.ccFixMojibake")
  expect_match(streaming_js, "MergenEncoding")
  expect_false(
    grepl("var MOJIBAKE_MAP", streaming_js, fixed = TRUE),
    info = "Büyük mojibake haritası Bilge Yolaç streaming dosyasına geri dönmemelidir."
  )
  expect_match(ui_manifest, '"js/encoding_utils.js"')
})
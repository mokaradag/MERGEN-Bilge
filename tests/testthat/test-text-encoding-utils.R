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

.read_repo_text_utf8_safe <- function(path) {
  repo_root <- resolve_repo_root_for_tests()
  full_path <- file.path(repo_root, path)

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\r\n?|\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
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

.turkish_emoji_sample_for_test <- function() {
  paste0(
    "\u00e7 \u011f \u0131 \u0130 \u00f6 \u015f \u00fc ",
    "\u00c7 \u011e I \u00d6 \u015e \u00dc",
    " \u2014 \u201ct\u0131rnak\u201d \u2022 ",
    intToUtf8(0x2705),
    " ",
    intToUtf8(0x1F680)
  )
}

test_that("normalize_text_utf8 Türkçe karakter ve emojiyi korur", {
  env <- .source_text_encoding_utils_for_test()

  sample_text <- .turkish_emoji_sample_for_test()

  expect_equal(
    env$normalize_text_utf8(sample_text, repair_mojibake = TRUE),
    sample_text
  )
})

test_that("normalize_text_utf8 yaygın Windows mojibake bozulmasını onarır", {
  env <- .source_text_encoding_utils_for_test()

  sample_text <- .turkish_emoji_sample_for_test()
  mojibake <- .mojibake_from_utf8_for_test(sample_text)

  expect_false(identical(mojibake, sample_text))
  expect_equal(
    env$normalize_text_utf8(mojibake, repair_mojibake = TRUE),
    sample_text
  )
})

test_that("normalize_text_tree_utf8 iç içe payload metinlerini onarır", {
  env <- .source_text_encoding_utils_for_test()

  payload <- list(
    title = "Ã‡alÄ±ÅŸma Ã¶zeti",
    nested = list(
      file = "ÅŸablon_gÃ¼ncelleme.pdf",
      emoji = intToUtf8(0x1F680)
    )
  )

  repaired <- env$normalize_text_tree_utf8(payload, repair_mojibake = TRUE)

  expect_equal(repaired$title, "Çalışma özeti")
  expect_equal(repaired$nested$file, "şablon_güncelleme.pdf")
  expect_equal(repaired$nested$emoji, intToUtf8(0x1F680))
})

test_that("normalize_text_for_log ANSI dizilerini temizler ve metni okunur tutar", {
  env <- .source_text_encoding_utils_for_test()

  mojibake <- .mojibake_from_utf8_for_test(paste0("çalışıyor ", intToUtf8(0x2705)))
  colored <- paste0("\033[1m", mojibake, "\033[0m")

  expect_equal(env$normalize_text_for_log(colored), paste0("çalışıyor ", intToUtf8(0x2705)))
})

test_that("read_text_lines_utf8 UTF-8 markdown satırlarını güvenli okur", {
  env <- .source_text_encoding_utils_for_test()

  sample_lines <- c(
    "## v1.0 | 2026-05-12 | T\u00fcrk\u00e7e S\u00fcr\u00fcm",
    paste0("- ", .turkish_emoji_sample_for_test())
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

  encoding_js <- .read_repo_text_utf8_safe("www/js/encoding_utils.js")
  streaming_js <- .read_repo_text_utf8_safe("www/js/claude_code_streaming.js")
  ui_manifest <- .read_repo_text_utf8_safe("R/config_ui_assets.R")

  expect_match(encoding_js, "window\\.MergenEncoding")
  expect_match(encoding_js, "window\\.ccFixMojibake")
  expect_match(encoding_js, "normalizeHtmlElement")
  expect_match(streaming_js, "MergenEncoding")
  expect_false(
    grepl("var MOJIBAKE_MAP", streaming_js, fixed = TRUE),
    info = "Büyük mojibake haritası Bilge Yolaç streaming dosyasına geri dönmemelidir."
  )
  expect_match(ui_manifest, '"js/encoding_utils.js"')
})


# Regresyon: kesilmiş okumada kırpma faz sırası. Kırpma aday BAŞINA satır içi
# yapıldığında, kesik bir CP1254 dosyasının son GEÇERLİ baytı (0xFE = ş)
# düşürülüp metin UTF-8 sayılıyor ve WINDOWS-1254 adayı hiç denenmiyordu.
test_that("read_text_lines_utf8 kesilmis CP1254 okumasinda son gecerli bayti kaybetmez", {
  env <- .source_text_encoding_utils_for_test()

  tmp <- withr::local_tempfile(fileext = ".log")
  # "abc" + 0xFE (CP1254 'ş') + devam eden bayt. max_bytes son 0xFE baytinda keser.
  writeBin(as.raw(c(0x61, 0x62, 0x63, 0xFE, 0x64, 0x65)), tmp)

  satirlar <- env$read_text_lines_utf8(tmp, max_bytes = 4)

  expect_length(satirlar, 1L)
  expect_identical(satirlar[1], "abc\u015f")
})

# Regresyon: max_bytes UTF-8 dosyayi cok baytli karakterin ORTASINDAN kestiginde
# kirpmasiz UTF-8 basarisiz oluyor ve akis hemen WINDOWS-1254/latin1'e dusuyordu;
# bu tek baytli kodlamalar genelde basarili oldugu icin SAKLANAN ONEKIN TAMAMI
# yanlis cozuluyordu.
test_that("kesik UTF-8 okumasinda onek tek baytli kodlamayla bozulmaz", {
  f <- tempfile()
  on.exit(unlink(f), add = TRUE)
  writeBin(charToRaw(enc2utf8("Türkçe metin şş")), f)

  n <- file.info(f)$size
  # Son baytin kesilmesi son 's' karakterini yarim birakir.
  metin <- read_text_lines_utf8(f, max_bytes = n - 1L)

  expect_true(validUTF8(metin))
  expect_true(grepl("Türkçe metin", metin, fixed = TRUE))
  # Mojibake yok: CP1254 ile cozulse "TÃ¼rkÃ§e" olurdu.
  expect_false(grepl("Ã", metin, fixed = TRUE))
})

# Ters yon korunur: kesik CP1254 dosyasinin son GECERLI bayti (0xFE = s) kor
# kirpmayla dusurulup metin UTF-8 sayilmamalidir.
test_that("kesik CP1254 okumasinda son gecerli bayt dusurulmez", {
  f <- tempfile()
  on.exit(unlink(f), add = TRUE)
  writeBin(c(charToRaw("Turkce "), as.raw(0xFE)), f)

  metin <- read_text_lines_utf8(
    f, max_bytes = 8L, encodings = c("UTF-8", "WINDOWS-1254")
  )
  expect_true(validUTF8(metin))
  expect_true(grepl("ş", metin, fixed = TRUE))
})

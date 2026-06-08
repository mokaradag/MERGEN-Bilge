# ==============================================================================
# Dosya Yolu: tests/testthat/test-source-manifest-read-parse-behavior.R
# Açıklama: R/bootstrap_source_manifest.R içindeki dosya okuma/parse yardımcıları
#            için DAVRANIŞ testleri:
#              - source_manifest_read_file_with_encoding (BOM ayıklama,
#                CRLF/CR -> LF normalizasyonu, kodlama yedeği, UTF-8 bütünlüğü)
#              - source_manifest_try_parse_file (geçerli -> TRUE, sözdizimi
#                hatası -> stop)
#            CRLF normalizasyonu sözleşmesi kritiktir: satır sonları gerçek LF
#            karakterine çevrilmeli, ASLA literal "n" karakterine dönüşmemelidir
#            (aksi halde geçerli R dosyaları parse edilemez).
#            Tümüyle çevrimdışı ve deterministiktir; ek paket gerektirmez.
# ==============================================================================

.source_manifest_io_env <- function() {
  root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  source(file.path(root, "R", "bootstrap_source_manifest.R"),
         encoding = "UTF-8", local = env)
  env
}

# Belirli baytları geçici dosyaya yazar (CRLF/BOM kontrolü için kesin baytlar).
.write_raw_temp <- function(raw_bytes) {
  path <- tempfile(fileext = ".R")
  con <- file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  writeBin(raw_bytes, con)
  path
}

testthat::test_that("CRLF satır sonları gerçek LF'e çevrilir (literal 'n' olmaz)", {
  env <- .source_manifest_io_env()
  path <- .write_raw_temp(charToRaw("x <- 1\r\nif (x < 2) y <- 3\r\n"))
  on.exit(unlink(path), add = TRUE)

  txt <- env$source_manifest_read_file_with_encoding(path, "UTF-8")
  testthat::expect_false(grepl("\r", txt, fixed = TRUE))
  testthat::expect_true(grepl("\n", txt, fixed = TRUE))
  # Satır sonu literal "n"e dönüşmemeli: "1ny" gibi bir bozulma OLMAMALI
  testthat::expect_false(grepl("1nif", txt, fixed = TRUE))
  # Sonuç gerçekten parse edilebilmeli
  testthat::expect_silent(parse(text = txt))
  lines <- strsplit(txt, "\n", fixed = TRUE)[[1]]
  testthat::expect_identical(lines[1], "x <- 1")
})

testthat::test_that("eski Mac CR satır sonları da LF'e çevrilir", {
  env <- .source_manifest_io_env()
  path <- .write_raw_temp(charToRaw("a <- 1\rb <- 2\r"))
  on.exit(unlink(path), add = TRUE)

  txt <- env$source_manifest_read_file_with_encoding(path, "UTF-8")
  testthat::expect_false(grepl("\r", txt, fixed = TRUE))
  testthat::expect_silent(parse(text = txt))
  testthat::expect_true(grepl("a <- 1", txt, fixed = TRUE))
  testthat::expect_true(grepl("b <- 2", txt, fixed = TRUE))
})

testthat::test_that("UTF-8 BOM ayıklanır ve içerik parse edilir", {
  env <- .source_manifest_io_env()
  bom <- as.raw(c(0xEF, 0xBB, 0xBF))
  path <- .write_raw_temp(c(bom, charToRaw("z <- 42\n")))
  on.exit(unlink(path), add = TRUE)

  txt <- env$source_manifest_read_file_with_encoding(path, "UTF-8")
  # BOM karakteri (U+FEFF) baştan ayıklanmış olmalı
  testthat::expect_false(startsWith(txt, intToUtf8(0xFEFF)))
  testthat::expect_true(startsWith(txt, "z <- 42"))
  testthat::expect_silent(parse(text = txt))
})

testthat::test_that("Türkçe UTF-8 içerik bütünlüğü korunur", {
  env <- .source_manifest_io_env()
  # Türkçe yorum içeren ASCII kod (deterministik UTF-8 baytlar)
  turkce <- paste0("# A", intToUtf8(0x00E7), intToUtf8(0x0131),
                   "klama\r\nx <- 1\r\n")  # "Açıklama"
  path <- .write_raw_temp(charToRaw(enc2utf8(turkce)))
  on.exit(unlink(path), add = TRUE)

  txt <- env$source_manifest_read_file_with_encoding(path, "UTF-8")
  testthat::expect_identical(Encoding(txt), "UTF-8")
  testthat::expect_true(grepl(intToUtf8(0x00E7), txt, fixed = TRUE))   # ç korunur
  testthat::expect_false(grepl("\r", txt, fixed = TRUE))
  testthat::expect_silent(parse(text = txt))
})

testthat::test_that("boş dosya boş metin döndürür", {
  env <- .source_manifest_io_env()
  path <- .write_raw_temp(raw(0))
  on.exit(unlink(path), add = TRUE)
  testthat::expect_identical(env$source_manifest_read_file_with_encoding(path, "UTF-8"), "")
})

testthat::test_that("source_manifest_try_parse_file geçerli dosyada TRUE döner", {
  env <- .source_manifest_io_env()
  # CRLF'li geçerli dosya: normalizasyon doğruysa parse edilir
  path <- .write_raw_temp(charToRaw("f <- function(a) {\r\n  a + 1\r\n}\r\n"))
  on.exit(unlink(path), add = TRUE)
  testthat::expect_true(isTRUE(env$source_manifest_try_parse_file(path)))
})

testthat::test_that("source_manifest_try_parse_file sözdizimi hatasında durur", {
  env <- .source_manifest_io_env()
  path <- .write_raw_temp(charToRaw("f <- function(a) {\n  a +\n"))
  on.exit(unlink(path), add = TRUE)
  testthat::expect_error(
    env$source_manifest_try_parse_file(path),
    "parse edilemedi"
  )
})

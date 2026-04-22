# ==============================================================================
# Dosya Yolu: tests/testthat/test-safe-source.R
# Aciklama: safe_source yardimcisinin UTF-8 dosya yukleme ve eksik dosya
# senaryolarindaki davranisini dogrulayan testleri icerir.
# NOT:
# - Bu test dosyasi bilerek ASCII-guvenli tutulur.
# - Turkce karakterli veri dogrudan literal yerine \\u kacis dizileri ile yazilir.
# ==============================================================================

# UTF-8 icerigi deterministik bicimde diske yazar.
write_utf8_r_file <- function(path, text, with_bom = FALSE) {
  con <- file(path, open = "wb")
  on.exit(close(con), add = TRUE)

  if (isTRUE(with_bom)) {
    writeBin(as.raw(c(0xEF, 0xBB, 0xBF)), con)
  }

  writeBin(charToRaw(enc2utf8(text)), con)
  invisible(path)
}

test_that("safe_source UTF-8 dosyayi hedef environment icine yukler", {
  temp_file <- tempfile(fileext = ".R")

  file_text <- paste0(
    "ornek_metin <- '\\u0130stanbul'\n",
    "ornek_sayi <- 42L\n"
  )
  write_utf8_r_file(temp_file, file_text, with_bom = FALSE)

  target_env <- new.env(parent = baseenv())
  safe_source(temp_file, envir = target_env)

  expect_equal(target_env$ornek_sayi, 42L)
  expect_equal(enc2utf8(target_env$ornek_metin), enc2utf8("\u0130stanbul"))
})

test_that("safe_source eksik dosyada hata verir", {
  expect_error(
    safe_source("olmayan_dosya_12345.R"),
    "bulunamad[ıi]"
  )
})

test_that("safe_source BOM isaretli UTF-8 dosyayi yukler", {
  temp_file <- tempfile(fileext = ".R")

  file_text <- "bomlu_deger <- '\\u0130zmir'\n"
  write_utf8_r_file(temp_file, file_text, with_bom = TRUE)

  target_env <- new.env(parent = baseenv())
  safe_source(temp_file, envir = target_env)

  expect_equal(enc2utf8(target_env$bomlu_deger), enc2utf8("\u0130zmir"))
})
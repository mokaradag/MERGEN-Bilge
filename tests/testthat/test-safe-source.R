# ==============================================================================
# Dosya Yolu: tests/testthat/test-safe-source.R
# Açıklama: safe_source yardımcı fonksiyonunun UTF-8 dosya yükleme ve hatalı
# dosya yolu senaryolarındaki davranışını doğrulayan testleri içerir.
# ==============================================================================

# UTF-8 içerik üreten bir R dosyasının hedef environment'a yüklendiğini doğrular.
test_that("safe_source UTF-8 dosyayı hedef environment içine yükler", {
  temp_file <- tempfile(fileext = ".R")
  writeLines(
    c(
      "ornek_metin <- 'İstanbul'",
      "ornek_sayi <- 42L"
    ),
    temp_file,
    useBytes = TRUE
  )

  target_env <- new.env(parent = baseenv())
  safe_source(temp_file, envir = target_env)

  expect_equal(target_env$ornek_sayi, 42L)
  expect_equal(enc2utf8(target_env$ornek_metin), "İstanbul")
})

# Mevcut olmayan dosya verildiğinde anlamlı bir hata üretildiğini doğrular.
test_that("safe_source eksik dosyada hata verir", {
  expect_error(
    safe_source("olmayan_dosya_12345.R"),
    "bulunamadı"
  )
})

# BOM işaretli UTF-8 dosyası da sorunsuz yüklenmelidir. Windows ortamında
# bazı editörler BOM yazabilir; safe_source bu duruma dayanıklı olmalıdır.
test_that("safe_source BOM işaretli UTF-8 dosyayı yükler", {
  temp_file <- tempfile(fileext = ".R")
  # UTF-8 BOM: EF BB BF
  bom <- as.raw(c(0xEF, 0xBB, 0xBF))
  icerik <- "bomlu_deger <- 'İzmir'\n"
  con <- file(temp_file, open = "wb")
  writeBin(bom, con)
  writeBin(charToRaw(enc2utf8(icerik)), con)
  close(con)

  target_env <- new.env(parent = baseenv())
  safe_source(temp_file, envir = target_env)

  expect_equal(enc2utf8(target_env$bomlu_deger), "İzmir")
})
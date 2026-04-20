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

  target_env <- new.env(parent = emptyenv())
  safe_source(temp_file, envir = target_env)

  expect_equal(target_env$ornek_sayi, 42L)
  expect_equal(enc2utf8(target_env$ornek_metin), "İstanbul")
})

test_that("safe_source eksik dosyada hata verir", {
  expect_error(
    safe_source("olmayan_dosya_12345.R"),
    "bulunamadı"
  )
})
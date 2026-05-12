# ==============================================================================
# Dosya Yolu: tests/testthat/test-db-normalization-contract.R
# Açıklama: DB parametre normalizasyonunun NA, vektör, Türkçe karakter ve
#           karakter dışı girdilerde uyarısız ve kayıpsız çalıştığını doğrular.
# ==============================================================================

test_that("normalize_db_value karakter dışı girdileri değiştirmeden döndürür", {
  expect_identical(normalize_db_value(NULL), NULL)
  expect_identical(normalize_db_value(123L), 123L)
  expect_identical(normalize_db_value(TRUE), TRUE)

  tarih <- as.Date("2026-04-25")
  expect_identical(normalize_db_value(tarih), tarih)
})

test_that("normalize_db_value boş karakter vektörünü uyarısız korur", {
  expect_warning(
    sonuc <- normalize_db_value(character(0)),
    regexp = NA
  )

  expect_identical(sonuc, character(0))
})

test_that("normalize_db_value NA karakter değerini uyarısız korur", {
  expect_warning(
    sonuc <- normalize_db_value(NA_character_),
    regexp = NA
  )

  expect_true(is.character(sonuc))
  expect_length(sonuc, 1L)
  expect_true(is.na(sonuc))
})

test_that("normalize_db_value karakter vektörlerinde uzunluğu ve NA konumunu korur", {
  girdi <- c("İstanbul", "Ankara", NA_character_, "Çalışma")

  expect_warning(
    sonuc <- normalize_db_value(girdi),
    regexp = NA
  )

  expect_true(is.character(sonuc))
  expect_length(sonuc, length(girdi))
  expect_true(is.na(sonuc[3]))
  expect_false(any(is.na(sonuc[-3])))

  # UTF-8 oturumlarında Türkçe karakterler bozulmamalıdır.
  if (isTRUE(l10n_info()[["UTF-8"]])) {
    expect_identical(sonuc[1], "İstanbul")
    expect_identical(sonuc[4], "Çalışma")
  }
})

test_that("normalize_db_value isteğe bağlı mojibake onarımı yapar", {
  mojibake <- "Ã‡alÄ±ÅŸma Ã¶zeti ðŸš€"

  expect_equal(
    normalize_db_value(mojibake, repair_mojibake = TRUE),
    "Çalışma özeti 🚀"
  )

  expect_identical(
    normalize_db_value(mojibake, repair_mojibake = FALSE),
    mojibake
  )
})

test_that("normalize_db_params liste yapısını ve sıra bilgisini korur", {
  params <- list(
    "İstanbul",
    42L,
    NA_character_,
    c("A", "B")
  )

  expect_warning(
    sonuc <- normalize_db_params(params),
    regexp = NA
  )

  expect_true(is.list(sonuc))
  expect_length(sonuc, length(params))
  expect_identical(sonuc[[2]], 42L)
  expect_true(is.na(sonuc[[3]]))
  expect_length(sonuc[[4]], 2L)
})
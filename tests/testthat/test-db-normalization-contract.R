# ==============================================================================
# Dosya Yolu: tests/testthat/test-db-normalization-contract.R
# Açıklama: DB parametre normalizasyonunun NA, vektör, Türkçe karakter ve
#           karakter dışı girdilerde uyarısız ve kayıpsız çalıştığını doğrular.
# ==============================================================================

.db_mojibake_from_utf8_for_test <- function(text) {
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

test_that("DB okuma/yazma sınırı yaygın Türkçe mojibake örneklerini onarır", {
  samples <- c(
    "NasÄ±l yardÄ±mcÄ± olabilirim?",
    "TÃ¼rkiye'nin baÅŸkenti Ankara'dÄ±r.",
    "AÃ§Ä±klama ve Ã¶zet gÃ¶rÃ¼ÅŸÃ¼ hazÄ±rlandÄ±.",
    "Ã‡alÄ±ÅŸma, Ã–lÃ§Ã¼m ve Ä°zleme"
  )

  expected <- c(
    "Nasıl yardımcı olabilirim?",
    "Türkiye'nin başkenti Ankara'dır.",
    "Açıklama ve özet görüşü hazırlandı.",
    "Çalışma, Ölçüm ve İzleme"
  )

  repaired <- normalize_db_value(samples, repair_mojibake = TRUE)

  expect_equal(repaired, expected)
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

test_that("DB client encoding ortam değişkeninden okunur", {
  repo_root <- resolve_repo_root_for_tests()
  test_env <- new.env(parent = globalenv())

  test_env$normalize_text_utf8 <- normalize_text_utf8
  test_env$l10n_info <- function() stats::setNames(list(FALSE), "UTF-8")

  withr::local_envvar(c(
    DB_CLIENT_ENCODING = "WINDOWS-1254",
    DB_NAME_ENCODING = "WINDOWS-1254"
  ))

  source(
    file.path(repo_root, "R", "helpers_db_connection.R"),
    encoding = "UTF-8",
    local = test_env
  )

  expect_identical(test_env$resolve_db_client_encoding(), "WINDOWS-1254")
  expect_identical(test_env$resolve_db_name_encoding(), "WINDOWS-1254")
  expect_identical(test_env$.DEFAULT_DB_CLIENT_ENCODING, "WINDOWS-1254")
  expect_identical(test_env$.DEFAULT_DB_NAME_ENCODING, "WINDOWS-1254")
})

test_that("WINDOWS-1254 DB client encoding Türkçe metni UTF-8 olarak bırakmaz", {
  repo_root <- resolve_repo_root_for_tests()
  test_env <- new.env(parent = globalenv())

  test_env$normalize_text_utf8 <- normalize_text_utf8
  test_env$l10n_info <- function() stats::setNames(list(TRUE), "UTF-8")

  withr::local_envvar(c(
    DB_CLIENT_ENCODING = "WINDOWS-1254",
    DB_NAME_ENCODING = "WINDOWS-1254"
  ))

  source(
    file.path(repo_root, "R", "helpers_db_connection.R"),
    encoding = "UTF-8",
    local = test_env
  )

  sample_text <- "Türkçe test: ç ğ ı İ ö ş ü Ç Ğ I Ö Ş Ü"
  sonuc <- test_env$normalize_db_value(sample_text, repair_mojibake = TRUE)

  expected_raw <- charToRaw(iconv(sample_text, from = "UTF-8", to = "WINDOWS-1254"))
  expect_identical(charToRaw(sonuc), expected_raw)

  expect_equal(
    iconv(sonuc, from = "WINDOWS-1254", to = "UTF-8"),
    sample_text
  )
})

test_that("WINDOWS-1254 DB client encoding temsil edilemeyen Unicode sembollerini DB sınırında çıkarır", {
  repo_root <- resolve_repo_root_for_tests()
  test_env <- new.env(parent = globalenv())

  test_env$normalize_text_utf8 <- normalize_text_utf8
  test_env$l10n_info <- function() stats::setNames(list(TRUE), "UTF-8")

  withr::local_envvar(c(
    DB_CLIENT_ENCODING = "WINDOWS-1254",
    DB_NAME_ENCODING = "WINDOWS-1254"
  ))

  source(
    file.path(repo_root, "R", "helpers_db_connection.R"),
    encoding = "UTF-8",
    local = test_env
  )

  sample_text <- paste0(
    "Durum: çalışıyor ",
    intToUtf8(0x1F680),
    " Türkiye"
  )
  expected_text <- "Durum: çalışıyor  Türkiye"

  sonuc <- test_env$normalize_db_value(sample_text, repair_mojibake = TRUE)

  expected_raw <- charToRaw(
    iconv(expected_text, from = "UTF-8", to = "WINDOWS-1254")
  )

  expect_identical(charToRaw(sonuc), expected_raw)

  expect_equal(
    iconv(sonuc, from = "WINDOWS-1254", to = "UTF-8"),
    expected_text
  )
})

test_that("normalize_db_params kullanıcıya görünen DB metnini repair bayrağıyla onarır", {
  expected <- c(
    "Çalışma özeti",
    paste0("Yönetici görüşü ", intToUtf8(0x1F680))
  )

  mojibake <- vapply(
    expected,
    .db_mojibake_from_utf8_for_test,
    character(1),
    USE.NAMES = FALSE
  )

  params <- normalize_db_params(
    list(mojibake[1], 42L, mojibake[2]),
    repair_mojibake = TRUE
  )

  expect_equal(params[[1]], expected[1])
  expect_identical(params[[2]], 42L)
  expect_equal(params[[3]], expected[2])
})
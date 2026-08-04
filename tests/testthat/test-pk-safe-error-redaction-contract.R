# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-safe-error-redaction-contract.R
# Açıklama: D22 — ham ODBC/sürücü/DSN tanılamasının sohbete sızmaması.
#           Tümü çevrimdışı ve deterministiktir; gerçek DB/DSN/sır KULLANILMAZ.
#           Fixture'lardaki bağlantı metinleri tamamen SENTETİKTİR.
# ==============================================================================

.pk_safe_err_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x
  source(file.path(repo_root, "R", "helpers_pk_safe_errors.R"),
         encoding = "UTF-8", local = env)
  env
}

.pk_safe_err_code_only <- function(rel_path) {
  full <- file.path(resolve_repo_root_for_tests(), rel_path)
  size <- suppressWarnings(file.info(full)$size[1])
  if (is.na(size) || size <= 0) return("")
  con <- file(full, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]])
  if (is.na(txt)) return("")
  satirlar <- strsplit(enc2utf8(txt), "\n", fixed = TRUE)[[1]]
  satirlar <- satirlar[!grepl("^\\s*#", satirlar, perl = TRUE, useBytes = TRUE)]
  paste(satirlar, collapse = "\n")
}

test_that("ham ODBC/surucu tanilamasi kullaniciya gosterilmez", {
  env <- .pk_safe_err_env()

  # Tamamen sentetik hata metinleri.
  ham_ornekler <- c(
    "nanodbc/nanodbc.cpp:1655: 42S02: [Microsoft][ODBC Driver 17 for SQL Server]Invalid object name 'SentetikTablo'.",
    "08001: [Microsoft][ODBC Driver]Login timeout expired",
    "Error in dbGetQuery(conn, sql): could not connect",
    "DSN=SentetikDsn;Uid=sentetik_kullanici;Pwd=sentetik-parola",
    "Incorrect syntax near 'SELECT'."
  )

  for (ham in ham_ornekler) {
    guvenli <- env$pk_safe_error_message(ham)
    expect_identical(guvenli, env$PK_GENERIC_DB_ERROR_MESSAGE, info = substr(ham, 1, 40))
  }

  # Genel mesaj hicbir ic ayrinti tasimaz.
  for (sizinti in c("nanodbc", "ODBC", "DSN", "SQLSTATE", "SentetikTablo",
                    "sentetik-parola", "42S02")) {
    expect_false(
      grepl(sizinti, env$PK_GENERIC_DB_ERROR_MESSAGE, fixed = TRUE),
      info = sprintf("Genel mesaj sizinti iceriyor: %s", sizinti)
    )
  }
})

test_that("bizim urettigimiz Turkce dogrulama mesajlari oldugu gibi kalir", {
  env <- .pk_safe_err_env()

  metin <- "Sorgu için SQL kodu bulunamadı."
  expect_identical(env$pk_safe_error_message(metin), metin)
})

test_that("bos/NA girdi genel mesaja duser", {
  env <- .pk_safe_err_env()

  for (girdi in list(NULL, NA_character_, "", "   ")) {
    expect_identical(env$pk_safe_error_message(girdi), env$PK_GENERIC_DB_ERROR_MESSAGE)
  }
})

test_that("pk_report_db_error ayrintiyi loga yazar, kullaniciya genel mesaj doner", {
  env <- .pk_safe_err_env()

  ham <- "nanodbc: 42S02 Invalid object name 'GizliSentetikTablo'."
  log_ciktisi <- utils::capture.output(
    kullanici <- env$pk_report_db_error(ham, context_label = "TEST"),
    type = "output"
  )

  expect_identical(kullanici, env$PK_GENERIC_DB_ERROR_MESSAGE)
  # Ayrinti KAYBOLMAZ; yalnizca yer degistirir.
  expect_true(any(grepl("GizliSentetikTablo", log_ciktisi, fixed = TRUE)))
  expect_false(grepl("GizliSentetikTablo", kullanici, fixed = TRUE))
})

test_that("pk_user_error_text kullanici metnini her kosulda ISARETLER", {
  env <- .pk_safe_err_env()

  # Redaksiyon bilerek gecirgendir; bu yuzden modulun "veri mi hata mi"
  # ayrimini yaptigi ortak isaret ayri bir katmanda garanti edilir.
  isaretsiz <- "Bos SQL metni gonderilemez."
  isaretli <- env$pk_user_error_text(isaretsiz)
  expect_true(startsWith(isaretli, env$PK_USER_ERROR_PREFIX))
  expect_true(grepl(isaretsiz, isaretli, fixed = TRUE))

  # Zaten isaretli metin IKI KEZ isaretlenmez.
  expect_identical(
    env$pk_user_error_text(env$PK_GENERIC_DB_ERROR_MESSAGE),
    env$PK_GENERIC_DB_ERROR_MESSAGE
  )

  # Bos/NA girdi genel mesaja duser.
  for (girdi in list(NULL, NA_character_, "", "   ")) {
    expect_identical(env$pk_user_error_text(girdi), env$PK_GENERIC_DB_ERROR_MESSAGE)
  }

  # Isaretleme redaksiyonu ZAYIFLATMAZ: ham ODBC metni yine genel mesaja duser.
  ham <- "nanodbc/nanodbc.cpp:1655: 42S02: [Microsoft][ODBC Driver]Invalid object name 'GizliTablo'."
  utils::capture.output(
    kullanici <- env$pk_user_error_text(env$pk_report_db_error(ham, context_label = "TEST")),
    type = "output"
  )
  expect_identical(kullanici, env$PK_GENERIC_DB_ERROR_MESSAGE)
  expect_false(grepl("GizliTablo", kullanici, fixed = TRUE))
})

test_that("PK SQL hata yolu ham conditionMessage() gommez", {
  modul <- .pk_safe_err_code_only("R/module_proje_kaynak_analizi.R")

  expect_true(
    grepl("pk_report_db_error(", modul, fixed = TRUE, useBytes = TRUE),
    info = "SQL hata isleyicisi redaksiyon yardimcisini kullanmalidir."
  )

  # Eski kalip: err_msg dogrudan kullaniciya donen metne yapistiriliyordu.
  expect_false(
    grepl('"`",\n\t\terr_msg', modul, fixed = TRUE, useBytes = TRUE),
    info = "Ham hata metni kullaniciya gosterilen mesaja gommelenmemelidir."
  )
  expect_false(
    grepl("err_msg <- conditionMessage(e)", modul, fixed = TRUE, useBytes = TRUE),
    info = "Ham hata metni artik kullanici mesajina tasinmamalidir."
  )
})

test_that("redaksiyon MERGEN_PK_ENGINE bayragindan BAGIMSIZDIR", {
  metin <- .pk_safe_err_code_only("R/helpers_pk_safe_errors.R")

  expect_false(grepl("MERGEN_PK_ENGINE", metin, fixed = TRUE, useBytes = TRUE))
  expect_false(grepl("pk_engine_is_v2", metin, fixed = TRUE, useBytes = TRUE))
})

# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-safe-error-redaction-contract.R
# Açıklama: D22 — ham ODBC/sürücü/DSN tanılamasının sohbete sızmaması.
#           Tümü çevrimdışı ve deterministiktir; gerçek DB/DSN/sır KULLANILMAZ.
#           Fixture'lardaki bağlantı metinleri tamamen SENTETİKTİR.
# ==============================================================================

.pk_safe_err_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x)) y else x
  # REDAKTÖRLER DE YÜKLENİR. `pk_report_db_error()` log sınırında hem
  # `redact_sensitive_text()` hem `redact_connection_identifiers()` bekler ve
  # ikisi de yoksa KAPALI BAŞARISIZ olur (ham metin diske yazılmaz). Üretimde
  # her ikisi de kaynak manifestinde çok daha erken yüklenir; onlarsız test
  # etmek üretimde HİÇ oluşmayan bir yapılandırmayı ölçerdi.
  source(file.path(repo_root, "R", "utils_log_redact.R"),
         encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "helpers_pk_safe_errors.R"),
         encoding = "UTF-8", local = env)
  env
}

.pk_safe_err_code_only <- function(rel_path) {
  full <- file.path(resolve_repo_root_for_tests(), rel_path)
  size <- suppressWarnings(file.info(full)$size[1])
  if (is.na(size) || size <= 0) {
    # BOŞ DOSYA DA VACUOUS GEÇİRİR: bu dosyalardaki taramaların çoğu
    # `expect_false(grepl(...))` biçimindedir ve boş dize hepsini karşılar.
    stop(sprintf("Kaynak dosya BOŞ ya da okunamıyor: %s", full), call. = FALSE)
  }
  con <- file(full, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]])
  # KAPALI BAŞARISIZ: çözülemeyen içerik `""` dönerse bu dosyadaki olumsuz
  # `grepl()` iddiaları KENDİLİĞİNDEN geçer ve ratchet hiçbir şey doğrulamaz.
  # `sub = "byte"` zaten geçersiz baytları değiştirdiği için `NA` ancak TAM
  # çözümleme başarısızlığı demektir.
  if (is.na(txt)) {
    stop(sprintf("Kaynak dosya UTF-8 olarak çözülemedi: %s", full), call. = FALSE)
  }
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

test_that("pk_report_db_error baglanti KIMLIKLERINI de loga yazmaz", {
  env <- .pk_safe_err_env()

  # `redact_sensitive_text()` yalnizca parola/anahtar bicimli degerleri maskeler;
  # DSN/UID/Server gibi baglanti KIMLIKLERI icin ikinci redaktor zorunludur.
  ham <- paste0("nanodbc baglanti hatasi: DSN=", "UretimSunucusu",
                ";UID=", "servis_hesabi", ";Server=", "10.20.30.40")
  log_ciktisi <- utils::capture.output(
    kullanici <- env$pk_report_db_error(ham, context_label = "TEST"),
    type = "output"
  )
  birlesik <- paste(log_ciktisi, collapse = "\n")

  expect_identical(kullanici, env$PK_GENERIC_DB_ERROR_MESSAGE)
  for (gizli in c("UretimSunucusu", "servis_hesabi", "10.20.30.40")) {
    expect_false(grepl(gizli, birlesik, fixed = TRUE))
  }
  # Tanilama TAMAMEN kaybolmaz: hata sinifi loga yazilmaya devam eder.
  expect_true(grepl("nanodbc", birlesik, fixed = TRUE))
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

  # SEMBOL DEGIL, BIRLESTIRME ARANIR.
  #
  # Eski surum `err_msg` SEMBOLUNU yasakliyordu; oysa uyumlu bir uygulama
  # `err_msg <- conditionMessage(e)` baglayip onu YALNIZCA
  # `pk_report_db_error()` cagrisina verebilir -- bu tam da 154. satirda
  # onaylanan redaksiyon yoludur. O durumda kullaniciya donen metin redakte
  # kalir ama test BASARISIZ raporlardi (yanlis pozitif). Ikinci iddia da
  # birincisi tarafindan ima ediliyordu, yani hicbir zaman bagimsiz duşemezdi.
  #
  # Sozlesme: ham hata metnini TASIYAN her satir ya `pk_report_db_error()`
  # cagrisi olmalidir ya da hic olmamalidir.
  err_satirlari <- grep("err_msg", strsplit(modul, "\n", fixed = TRUE)[[1]],
                        fixed = TRUE, value = TRUE)
  # BAGLAMA SATIRI DA MESRUDUR (PR #705 incelemesi, P3): yukarida ONAYLANAN
  # bicim `err_msg <- conditionMessage(e)` baglayip degeri YALNIZCA
  # `pk_report_db_error()` cagrisina vermektir. Baglama satiri `err_msg`
  # icerir ama CAGRI icermez, dolayisiyla eski yuklem onu `onaysiz` sayiyor ve
  # UYUMLU bir uygulamada test DUSUYORDU. Bugun gecmesinin tek nedeni boyle bir
  # satirin henuz bulunmamasidir, yani sozlesme hicbir sey dogrulamiyordu.
  onaysiz <- err_satirlari[
    !grepl("pk_report_db_error\\([^)]*err_msg", err_satirlari, perl = TRUE) &
      !grepl("^\\s*err_msg\\s*<-\\s*conditionMessage\\(", err_satirlari, perl = TRUE)
  ]
  expect_equal(
    onaysiz, character(0),
    info = paste(
      "Ham hata metni kullaniciya gosterilen mesaja gommelenmemelidir.",
      "Onaysiz satirlar:", paste(onaysiz, collapse = " | ")
    )
  )
})

test_that("redaksiyon MERGEN_PK_ENGINE bayragindan BAGIMSIZDIR", {
  metin <- .pk_safe_err_code_only("R/helpers_pk_safe_errors.R")

  # BOŞ İÇERİK NEGATİF İDDİALARI KENDİLİĞİNDEN GEÇİRİR. Okuyucu dosya yoksa
  # ya da okunamazsa `""` döner ve `grepl("", ...)` FALSE'tur; dosya yeniden
  # adlandırıldığında/taşındığında test BAŞARILI raporlardı.
  expect_true(nzchar(metin), info = "helpers_pk_safe_errors.R okunamadı.")

  expect_false(grepl("MERGEN_PK_ENGINE", metin, fixed = TRUE, useBytes = TRUE))
  expect_false(grepl("pk_engine_is_v2", metin, fixed = TRUE, useBytes = TRUE))
})

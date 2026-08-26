# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-entity-alias-regressions.R
# Açıklama: Faz 4 (§5.4, Katman 2) — onaylı alias kayıt defteri indeksi ve
#           arama sözleşmesinin gerileme testleri. `R/helpers_pk_entity_alias.R`
#           dosyasının ÜÇ kapalı başarısızlık kuralını ve kayıplı/kayıpsız
#           anahtar sırasını doğrudan doğrular.
#
#           Bu dosya eskiden adını taşıdığı konuyu HİÇ test etmiyordu; içerik
#           `test-ui-validation-regressions.R` dosyasına taşındı ve
#           gerçek alias kapsamı buraya yazıldı.
#
#           Tamamen çevrimdışı ve belirlenimcidir: DB, LLM, tarayıcı, SSO, ağ
#           veya gizli değer GEREKMEZ.
# ==============================================================================

pk_entity_source_chain_for_tests()

test_that("alias indeksi katlanmış anahtarı kanonik hedefe eşler", {
  index <- pk_entity_alias_index(c("ANKA" = "ANKA İHA", "akıncı" = "AKINCI"))

  expect_true(index$valid)
  expect_length(index$errors, 0L)
  expect_identical(unname(index$fold[[pk_tr_fold("ANKA")]]), "ANKA İHA")
  expect_identical(unname(index$fold[[pk_tr_fold("akıncı")]]), "AKINCI")
  expect_true(all(c("ANKA İHA", "AKINCI") %in% index$targets))
})

test_that("aynı katlanmış anahtar farklı hedeflere işaret ederse KAPALI başarısız olunur", {
  # Türkçe `I/İ` katlaması iki yazımı AYNI anahtara indirger; hedefler farklıysa
  # `match()` ile ilki sessizce seçilmemelidir.
  index <- pk_entity_alias_index(c("ANKA" = "ANKA İHA", "anka" = "ANKA-2"))

  expect_false(index$valid)
  expect_true(length(index$errors) >= 1L)
  expect_true(any(grepl("birden fazla kanonik", index$errors, fixed = TRUE)))
  expect_false(pk_tr_fold("ANKA") %in% names(index$fold))
})

test_that("boş/adsız kayıt defteri güvenli boş indeks döndürür", {
  expect_true(pk_entity_alias_index(NULL)$valid)
  expect_length(pk_entity_alias_index(NULL)$fold, 0L)
  expect_length(pk_entity_alias_index(character(0))$fold, 0L)

  adsiz <- pk_entity_alias_index(c("ANKA İHA"))
  expect_false(adsiz$valid)
  expect_true(any(grepl("adlandırılmış", adsiz$errors, fixed = TRUE)))
})

test_that("kesin katlanmış anahtar KAYIPSIZ eşleşir", {
  # `pk_entity_normalize()` `stringi` gerektirir; kardeş varlık test
  # dosyalarıyla AYNI korumadır: paket yoksa hata değil ATLAMA üretilir.
  testthat::skip_if_not_installed("stringi")
  index <- pk_entity_alias_index(c("ANKA" = "ANKA İHA"))
  sonuc <- pk_entity_alias_lookup(index, pk_entity_normalize("anka"))

  expect_identical(sonuc$target, "ANKA İHA")
  expect_false(sonuc$lossy)
  expect_false(sonuc$ambiguous)
})

test_that("ASCII yedek anahtarı Türkçe harfsiz yazımı bulur ve KAYIPLI işaretlenir", {
  # `pk_entity_normalize()` `stringi` gerektirir; kardeş varlık test
  # dosyalarıyla AYNI korumadır: paket yoksa hata değil ATLAMA üretilir.
  testthat::skip_if_not_installed("stringi")
  index <- pk_entity_alias_index(c("ŞAHİN" = "ŞAHİN PROJESİ"))
  sonuc <- pk_entity_alias_lookup(index, pk_entity_normalize("sahin"))

  expect_identical(sonuc$target, "ŞAHİN PROJESİ")
  expect_true(sonuc$lossy)
  expect_false(sonuc$ambiguous)
})

test_that("ASCII yedek anahtarı çakışırsa hedef seçilmez, netleştirme istenir", {
  # `pk_entity_normalize()` `stringi` gerektirir; kardeş varlık test
  # dosyalarıyla AYNI korumadır: paket yoksa hata değil ATLAMA üretilir.
  testthat::skip_if_not_installed("stringi")
  index <- pk_entity_alias_index(c("ŞAHİN" = "ŞAHİN PROJESİ", "SAHIN" = "SAHIN A.Ş."))
  sonuc <- pk_entity_alias_lookup(index, pk_entity_normalize("sahin"))

  expect_true(sonuc$ambiguous)
  expect_null(sonuc$target)
  expect_true(length(sonuc$targets) >= 2L)
})

test_that("boş ifade ve boş indeks için alias katmanı hiçbir hedef döndürmez", {
  # `pk_entity_normalize()` `stringi` gerektirir; kardeş varlık test
  # dosyalarıyla AYNI korumadır: paket yoksa hata değil ATLAMA üretilir.
  testthat::skip_if_not_installed("stringi")
  index <- pk_entity_alias_index(c("ANKA" = "ANKA İHA"))

  expect_null(pk_entity_alias_lookup(index, pk_entity_normalize("   "))$target)
  expect_null(pk_entity_alias_lookup(NULL, pk_entity_normalize("anka"))$target)
  expect_null(pk_entity_alias_lookup(index, pk_entity_normalize("bilinmeyen"))$target)
})

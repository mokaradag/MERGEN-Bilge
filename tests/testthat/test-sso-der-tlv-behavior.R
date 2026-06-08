# ==============================================================================
# Dosya Yolu: tests/testthat/test-sso-der-tlv-behavior.R
# Açıklama: R/helpers_sso_signature.R DER kodlama yardımcılarının davranış
#           testleri: .sso_der_length (kısa/uzun form uzunluk), .sso_der_tlv
#           (tag-length-value yerleşimi) ve .sso_der_integer (baştaki sıfır
#           temizleme + işaret biti için 0x00 ekleme). RSA SPKI üretiminin temel
#           taşları olan bu kodlayıcılar tamamen deterministiktir; ağ/openssl
#           anahtarı gerektirmez.
# ==============================================================================

testthat::local_edition(3)

.derenv <- new.env(parent = globalenv())
suppressMessages(source(
  file.path(resolve_repo_root_for_tests(), "R", "helpers_sso_signature.R"),
  encoding = "UTF-8", local = .derenv
))

test_that(".sso_der_length: 128'den küçük uzunluklar tek bayt kısa formdur", {
  expect_identical(.derenv$.sso_der_length(0), as.raw(0))
  expect_identical(.derenv$.sso_der_length(5), as.raw(5))
  expect_identical(.derenv$.sso_der_length(127), as.raw(127))
})

test_that(".sso_der_length: 128 ve üzeri uzunluklar uzun form (0x81/0x82 önekli)", {
  # 128..255 -> 0x81 <bayt>
  expect_identical(.derenv$.sso_der_length(128), as.raw(c(0x81, 0x80)))
  expect_identical(.derenv$.sso_der_length(255), as.raw(c(0x81, 0xFF)))
  # 256 -> 0x82 0x01 0x00 (iki baytlık uzunluk)
  expect_identical(.derenv$.sso_der_length(256), as.raw(c(0x82, 0x01, 0x00)))
})

test_that(".sso_der_length: negatif uzunluk Türkçe hata fırlatır", {
  expect_error(.derenv$.sso_der_length(-1), "negatif")
})

test_that(".sso_der_tlv: tag + uzunluk + içerik sırasıyla dizilir (kısa form)", {
  out <- .derenv$.sso_der_tlv(0x02, as.raw(c(1, 2, 3)))
  expect_identical(out, as.raw(c(0x02, 0x03, 0x01, 0x02, 0x03)))
})

test_that(".sso_der_tlv: boş içerik uzunluk sıfır olarak kodlanır", {
  out <- .derenv$.sso_der_tlv(0x04, raw(0))
  expect_identical(out, as.raw(c(0x04, 0x00)))
})

test_that(".sso_der_tlv: uzun içerik uzun-form uzunluk önekiyle kodlanır", {
  out <- .derenv$.sso_der_tlv(0x03, as.raw(rep(0xAA, 200)))
  # tag(1) + uzunluk(0x81 0xC8 = 2) + içerik(200) = 203 bayt
  expect_identical(length(out), 203L)
  expect_identical(out[1], as.raw(0x03))
  expect_identical(out[2], as.raw(0x81))
  expect_identical(out[3], as.raw(0xC8))
})

test_that(".sso_der_integer: baştaki gereksiz sıfır baytları temizlenir", {
  out <- .derenv$.sso_der_integer(c(0L, 0L, 5L))
  expect_identical(out, as.raw(c(0x02, 0x01, 0x05)))
})

test_that(".sso_der_integer: en yüksek baytın MSB'si setse pozitif işaret için 0x00 eklenir", {
  out <- .derenv$.sso_der_integer(c(0x80L))
  # 0x80'in MSB'si set -> başına 0x00; INTEGER içerik 0x00 0x80 olur.
  expect_identical(out, as.raw(c(0x02, 0x02, 0x00, 0x80)))
})

test_that(".sso_der_integer: tamamı sıfır olan magnitude tek 0x00 içerik üretir", {
  out <- .derenv$.sso_der_integer(c(0L, 0L))
  expect_identical(out, as.raw(c(0x02, 0x01, 0x00)))
})

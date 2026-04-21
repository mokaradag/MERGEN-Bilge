# ==============================================================================
# Dosya Yolu: tests/testthat/test-db-validation.R
# Açıklama: Veritabanı katmanındaki kullanıcı adı, sohbet başlığı ve mesaj
# içeriği doğrulama kurallarını sınayan birim testlerini içerir.
# ==============================================================================

# Kullanıcı adında izin verilen güvenli karakter setini doğrular.
test_that("validate_username güvenli biçimi kabul eder", {
  expect_true(validate_username("mehmet_onur.karadag"))
})

# Kullanıcı adı için yasaklı karakterlerin hata ürettiğini doğrular.
test_that("validate_username güvensiz karakterleri reddeder", {
  expect_error(validate_username("mehmet onur"))
  expect_error(validate_username("mehmet;drop"))
})

# Sohbet başlığında boş ve aşırı uzun değerlerin reddedildiğini doğrular.
test_that("validate_chat_title boş ve aşırı uzun başlığı reddeder", {
  expect_error(validate_chat_title(""))
  expect_error(validate_chat_title(strrep("a", 201)))
})

# Mesaj içeriğinde boş ve limit aşımı durumlarının hata verdiğini doğrular.
test_that("validate_message_content boş ve aşırı uzun içeriği reddeder", {
  expect_error(validate_message_content(""))
  expect_error(validate_message_content(strrep("x", 20001)))
})

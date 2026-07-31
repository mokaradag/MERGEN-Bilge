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

# Varsayılan güvenlik tavanını dağıtım ortamından yalıtarak doğrular.
test_that("validate_message_content boş ve aşırı uzun içeriği reddeder", {
  withr::with_envvar(c(MERGEN_MAX_MESSAGE_CHARS = "1000000"), {
    expect_error(validate_message_content(""))
    expect_error(validate_message_content(strrep("x", 1000001L)))
  })
})

# Uzun kod bloğu içeren yanıtlar (eski 20.000 karakter sınırının üzerinde)
# artık kaydedilebilmelidir; kolon NVARCHAR(MAX). Test, üretim override'ından
# bağımsız olarak belgelenen varsayılan tavanı kullanır.
test_that("validate_message_content uzun kod bloklarını kabul eder", {
  withr::with_envvar(c(MERGEN_MAX_MESSAGE_CHARS = "1000000"), {
    expect_true(validate_message_content(strrep("x", 20001)))
    expect_true(validate_message_content(strrep("x", 200000)))
  })
})

# Güvenlik tavanı MERGEN_MAX_MESSAGE_CHARS ile ayarlanabilir olmalıdır.
test_that("mergen_max_message_chars ortam değişkenini onurlandırır", {
  withr::with_envvar(c(MERGEN_MAX_MESSAGE_CHARS = ""), {
    expect_equal(mergen_max_message_chars(), 1000000L)
  })
  withr::with_envvar(c(MERGEN_MAX_MESSAGE_CHARS = "50000"), {
    expect_equal(mergen_max_message_chars(), 50000L)
  })
  # Geçersiz/çok küçük değerler güvenli varsayılana düşer.
  withr::with_envvar(c(MERGEN_MAX_MESSAGE_CHARS = "abc"), {
    expect_equal(mergen_max_message_chars(), 1000000L)
  })
  withr::with_envvar(c(MERGEN_MAX_MESSAGE_CHARS = "10"), {
    expect_equal(mergen_max_message_chars(), 1000000L)
  })
})

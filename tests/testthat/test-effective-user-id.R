# ==============================================================================
# Dosya Yolu: tests/testthat/test-effective-user-id.R
# Açıklama: resolve_effective_user_id() yardımcısının oturum kimliği önceliği,
# fallback fonksiyon desteği ve geçersiz değer dayanıklılığını doğrulayan
# testleri içerir. Bu helper SSO akışında başlangıç kimlik regresyonlarını
# engellemek için projede canonical olarak kullanılmaktadır (CLAUDE.md §7A).
# ==============================================================================

# session$userData$user_id varsa onun önceliği olmalı.
test_that("resolve_effective_user_id session.userData.user_id kullanır", {
  sahte_session <- list(userData = list(user_id = 42L))
  sonuc <- resolve_effective_user_id(
    session = sahte_session,
    current_user_id = 99L
  )
  expect_equal(sonuc, 42L)
})

# session yoksa fallback değeri kullanılır.
test_that("resolve_effective_user_id session yoksa fallback değerini döndürür", {
  sonuc <- resolve_effective_user_id(
    session = NULL,
    current_user_id = 17L
  )
  expect_equal(sonuc, 17L)
})

# Fallback parametresi fonksiyon ise çağrılıp değeri alınır.
test_that("resolve_effective_user_id fonksiyonel fallback destekler", {
  fallback_fn <- function() 33L
  sonuc <- resolve_effective_user_id(
    session = NULL,
    current_user_id = fallback_fn
  )
  expect_equal(sonuc, 33L)
})

# Her iki kaynak da NULL/0 ise 0 dönmelidir.
test_that("resolve_effective_user_id tanımsız kimliklerde 0 döner", {
  sonuc <- resolve_effective_user_id(
    session = list(userData = list()),
    current_user_id = NULL
  )
  expect_equal(sonuc, 0L)
})

# NA benzeri dönüşümler çökme üretmez, 0'a düşer.
test_that("resolve_effective_user_id NA/char değerlerde güvenli fallback yapar", {
  sonuc <- resolve_effective_user_id(
    session = list(userData = list(user_id = "metin_degil_sayi")),
    current_user_id = NULL
  )
  expect_equal(sonuc, 0L)
})

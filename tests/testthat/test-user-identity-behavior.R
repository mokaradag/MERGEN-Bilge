# ==============================================================================
# Dosya Yolu: tests/testthat/test-user-identity-behavior.R
# Açıklama: R/module_user_identity.R kimlik yardımcılarının davranışsal testleri.
#           Türkçe büyük/küçük harf dönüşümü, baş harf büyütme, ilk isim çıkarımı
#           ve SSO modunda resolveUserIdentity claim eşlemesi doğrulanır.
#           Locale'e duyarlı i/ı belirsizliği yerine kesin ç/ş/ğ/ü/ö örnekleri
#           ve İ->i (chartr) gibi deterministik dönüşümler kullanılır.
# ==============================================================================

testthat::local_edition(3)

.uid_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "module_user_identity.R"),
  encoding = "UTF-8",
  local = .uid_env
)

# -----------------------------------------------------------------------------
# turkish_toupper / turkish_tolower
# -----------------------------------------------------------------------------

test_that("turkish_toupper Türkçe ç/ş/ğ/ü/ö harflerini doğru büyütür", {
  expect_equal(.uid_env$turkish_toupper("çöküş güç öğe"), "ÇÖKÜŞ GÜÇ ÖĞE")
  expect_equal(.uid_env$turkish_toupper("ğ"), "Ğ")
  expect_equal(.uid_env$turkish_toupper("ABC"), "ABC")
})

test_that("turkish_tolower Türkçe Ç/Ş/Ğ/Ü/Ö ve İ harflerini doğru küçültür", {
  expect_equal(.uid_env$turkish_tolower("ÇÖKÜŞ GÜÇ ÖĞE"), "çöküş güç öğe")
  # İ -> i dönüşümü chartr ile deterministiktir.
  expect_equal(.uid_env$turkish_tolower("İSTANBUL"), "istanbul")
  expect_equal(.uid_env$turkish_tolower("abc"), "abc")
})

# -----------------------------------------------------------------------------
# capitalizeFirst
# -----------------------------------------------------------------------------

test_that("capitalizeFirst baş harfi büyük, kalanı küçük yapar (Türkçe güvenli örnekler)", {
  expect_equal(.uid_env$capitalizeFirst("şirket"), "Şirket")
  expect_equal(.uid_env$capitalizeFirst("çınar"), "Çınar")
  expect_equal(.uid_env$capitalizeFirst("MEHMET"), "Mehmet")
  expect_equal(.uid_env$capitalizeFirst("güçlü"), "Güçlü")
})

test_that("capitalizeFirst boş/NULL girdide boş string döndürür", {
  expect_equal(.uid_env$capitalizeFirst(""), "")
  expect_equal(.uid_env$capitalizeFirst(NULL), "")
})

# -----------------------------------------------------------------------------
# extractFirstName
# -----------------------------------------------------------------------------

test_that("extractFirstName tam isimden baş harfi büyük ilk ismi çıkarır", {
  expect_equal(.uid_env$extractFirstName("AHMET YILMAZ KARA"), "Ahmet")
  expect_equal(.uid_env$extractFirstName("  Mehmet   Ali  "), "Mehmet")
  expect_equal(.uid_env$extractFirstName(""), "")
  expect_equal(.uid_env$extractFirstName(NULL), "")
})

# -----------------------------------------------------------------------------
# resolveUserIdentity (SSO modu - DB gerektirmez)
# -----------------------------------------------------------------------------

test_that("resolveUserIdentity SSO modunda claim'leri kimlik listesine eşler", {
  # SSO açık + claim sağlanmış -> Keycloak yolu (DB sorgusu yok).
  .uid_env$SSO_ENABLED <- TRUE
  withr::defer(rm("SSO_ENABLED", envir = .uid_env))

  kimlik <- .uid_env$resolveUserIdentity(list(
    username = "ayilmaz",
    full_name = "AHMET YILMAZ",
    sicil = "12345",
    email = "a@x.com",
    yetki = "ADMIN"
  ))

  expect_equal(kimlik$username, "ayilmaz")
  # full_name boş olmadığından first_name oradan türetilip baş harfi büyütülür.
  expect_equal(kimlik$first_name, "Ahmet")
  expect_equal(kimlik$full_name, "AHMET YILMAZ")
  expect_equal(kimlik$sicil, "12345")
  expect_equal(kimlik$email, "a@x.com")
  expect_equal(kimlik$auth_level, "ADMIN")
  expect_equal(kimlik$auth_source, "keycloak")
})

test_that("resolveUserIdentity SSO modunda yetki yoksa USER'a düşer ve full_name yoksa kullanıcı adından türetir", {
  .uid_env$SSO_ENABLED <- TRUE
  withr::defer(rm("SSO_ENABLED", envir = .uid_env))

  kimlik <- .uid_env$resolveUserIdentity(list(username = "deneme"))

  expect_equal(kimlik$auth_level, "USER")
  # full_name boş -> capitalizeFirst(username)
  expect_equal(kimlik$full_name, "Deneme")
  expect_equal(kimlik$auth_source, "keycloak")
})

test_that("SSO etkinken claim yoksa yerel ADMIN yedeğine DÜŞÜLMEZ (kapalı-başarısız)", {
  .uid_env$SSO_ENABLED <- TRUE
  withr::defer(rm("SSO_ENABLED", envir = .uid_env))

  # Yerel yol DB'ye gitmeye çalışırsa test bunu görsün: çağrılmamalı.
  cagrildi <- FALSE
  .uid_env$get_connection <- function() {
    cagrildi <<- TRUE
    stop("yerel yol SSO etkinken çalışmamalı")
  }
  withr::defer(rm("get_connection", envir = .uid_env))

  kimlik <- .uid_env$resolveUserIdentity(sso_claims = NULL)

  expect_false(cagrildi)
  expect_identical(kimlik$username, "")
  expect_identical(kimlik$auth_level, "NONE")
  expect_identical(kimlik$auth_source, "unauthenticated")
  # İşletim sistemi hesabı asla sızmamalıdır.
  expect_false(identical(kimlik$username, unname(Sys.info()["user"])))
})

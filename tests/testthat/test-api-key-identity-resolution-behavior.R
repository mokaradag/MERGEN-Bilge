# ==============================================================================
# Dosya Yolu: tests/testthat/test-api-key-identity-resolution-behavior.R
# Açıklama: R/helpers_api_key_identity.R oturum/anahtar sahipliği yardımcılarının
#           DAVRANIŞSAL testleri. Kişisel API anahtarları yalnızca kimliği
#           doğrulanmış kullanıcıya bağlanır ve varsayılan kurumsal anahtar
#           yalnızca açık çevre değişkenleriyle izinli olur. Gerçek üretim
#           fonksiyonları çağrılır; Shiny/DB/ağ GEREKMEZ. Sentetik bir oturum
#           (environment tabanlı userData) kullanılır.
# ==============================================================================

.apikeyid_source_once <- function() {
  if (exists("mb_api_key_default_allowed", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_api_key_identity.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

# Sahte oturum: userData environment olmalı çünkü helper'lar exists()/get()/rm()
# ile environment üzerinde çalışır.
.apikeyid_fake_session <- function(...) {
  ud <- new.env(parent = emptyenv())
  vals <- list(...)
  for (nm in names(vals)) assign(nm, vals[[nm]], envir = ud)
  list(userData = ud)
}

# ------------------------------------------------------------------------------
# .mb_api_key_user_data
# ------------------------------------------------------------------------------
testthat::test_that(".mb_api_key_user_data NULL oturum/NULL userData için NULL döner", {
  .apikeyid_source_once()
  testthat::expect_null(.mb_api_key_user_data(NULL))
  testthat::expect_null(.mb_api_key_user_data(list(userData = NULL)))

  ud <- new.env(parent = emptyenv())
  sess <- list(userData = ud)
  # Var olan userData aynen (kimlik olarak) döndürülür.
  testthat::expect_true(identical(.mb_api_key_user_data(sess), ud))
})

# ------------------------------------------------------------------------------
# .mb_api_key_get_user_data_value
# ------------------------------------------------------------------------------
testthat::test_that(".mb_api_key_get_user_data_value yok/boş/NULL durumlarında default döner", {
  .apikeyid_source_once()
  sess <- .apikeyid_fake_session(user_id = 42L, ai_api_key = "cfg-personal-fake")

  # Oturum yoksa default.
  testthat::expect_identical(.mb_api_key_get_user_data_value(NULL, "user_id", "D"), "D")
  # Boş anahtar adı default.
  testthat::expect_identical(.mb_api_key_get_user_data_value(sess, "", "D"), "D")
  # Mevcut olmayan anahtar default (varsayılan default NULL).
  testthat::expect_null(.mb_api_key_get_user_data_value(sess, "yok_boyle_key"))
  testthat::expect_identical(.mb_api_key_get_user_data_value(sess, "yok_boyle_key", "D"), "D")
  # Mevcut anahtar değeri döner.
  testthat::expect_identical(.mb_api_key_get_user_data_value(sess, "user_id"), 42L)
  testthat::expect_identical(.mb_api_key_get_user_data_value(sess, "ai_api_key"), "cfg-personal-fake")
})

testthat::test_that(".mb_api_key_get_user_data_value değer NULL ise default'a düşer", {
  .apikeyid_source_once()
  # Anahtar var ama değeri NULL: exists() TRUE, get() NULL -> default.
  sess <- .apikeyid_fake_session(bos_alan = NULL)
  testthat::expect_identical(.mb_api_key_get_user_data_value(sess, "bos_alan", "D"), "D")
  # Anahtar adının yalnızca ilk elemanı kullanılır (skalar daraltma).
  testthat::expect_identical(
    .mb_api_key_get_user_data_value(sess, c("yok1", "yok2"), "D"), "D"
  )
})

# ------------------------------------------------------------------------------
# .mb_api_key_first_non_empty
# ------------------------------------------------------------------------------
testthat::test_that(".mb_api_key_first_non_empty ilk boş-olmayan trimlenmiş değeri döner", {
  .apikeyid_source_once()
  testthat::expect_identical(.mb_api_key_first_non_empty(NULL, "", "  ", "val"), "val")
  testthat::expect_identical(.mb_api_key_first_non_empty(NULL, NA, "x"), "x")
  testthat::expect_identical(.mb_api_key_first_non_empty("  spaced  "), "spaced")
  testthat::expect_identical(.mb_api_key_first_non_empty(123), "123")
  # Hiç değer yoksa veya hepsi boşsa "" döner.
  testthat::expect_identical(.mb_api_key_first_non_empty(), "")
  testthat::expect_identical(.mb_api_key_first_non_empty(NULL, "", "   "), "")
  # Vektör verilirse yalnızca ilk eleman değerlendirilir.
  testthat::expect_identical(.mb_api_key_first_non_empty(c("a", "b")), "a")
})

# ------------------------------------------------------------------------------
# mb_api_key_clear_session_key
# ------------------------------------------------------------------------------
testthat::test_that("mb_api_key_clear_session_key anahtar ve owner alanlarını siler", {
  .apikeyid_source_once()
  sess <- .apikeyid_fake_session(
    ai_api_key = "cfg-personal-fake",
    ai_api_key_owner = "alice",
    other_field = "kalmali"
  )
  ud <- sess$userData

  res <- mb_api_key_clear_session_key(sess)
  testthat::expect_null(res)
  testthat::expect_false(exists("ai_api_key", envir = ud, inherits = FALSE))
  testthat::expect_false(exists("ai_api_key_owner", envir = ud, inherits = FALSE))
  # İlgisiz alan korunur.
  testthat::expect_true(exists("other_field", envir = ud, inherits = FALSE))
})

testthat::test_that("mb_api_key_clear_session_key kısmi/eksik anahtarlarda güvenli çalışır", {
  .apikeyid_source_once()
  # Yalnızca biri mevcut.
  sess1 <- .apikeyid_fake_session(ai_api_key = "cfg-personal-fake")
  testthat::expect_null(mb_api_key_clear_session_key(sess1))
  testthat::expect_false(exists("ai_api_key", envir = sess1$userData, inherits = FALSE))

  # Hiçbiri mevcut değil: hata yok.
  sess2 <- .apikeyid_fake_session(foo = "bar")
  testthat::expect_null(mb_api_key_clear_session_key(sess2))

  # NULL oturum: hata yok, NULL döner.
  testthat::expect_null(mb_api_key_clear_session_key(NULL))
})

# ------------------------------------------------------------------------------
# mb_api_key_default_allowed (çevre değişkeni güdümlü)
# ------------------------------------------------------------------------------
testthat::test_that("mb_api_key_default_allowed yalnızca izin açık + kişisel zorunlu değilse TRUE döner", {
  .apikeyid_source_once()

  # İzin açık, kişisel zorunluluk yok -> TRUE.
  Sys.setenv(MERGEN_ALLOW_DEFAULT_API_KEY = "TRUE")
  Sys.unsetenv("MERGEN_REQUIRE_PERSONAL_API_KEY")
  testthat::expect_true(mb_api_key_default_allowed())

  # İzin açık ama kişisel anahtar zorunlu -> FALSE.
  Sys.setenv(MERGEN_REQUIRE_PERSONAL_API_KEY = "TRUE")
  testthat::expect_false(mb_api_key_default_allowed())
  Sys.unsetenv("MERGEN_REQUIRE_PERSONAL_API_KEY")

  # İzin kapalı -> FALSE.
  Sys.setenv(MERGEN_ALLOW_DEFAULT_API_KEY = "FALSE")
  testthat::expect_false(mb_api_key_default_allowed())

  # İzin tanımsız -> FALSE (varsayılan "FALSE").
  Sys.unsetenv("MERGEN_ALLOW_DEFAULT_API_KEY")
  testthat::expect_false(mb_api_key_default_allowed())

  # Temizlik.
  Sys.unsetenv(c("MERGEN_ALLOW_DEFAULT_API_KEY", "MERGEN_REQUIRE_PERSONAL_API_KEY"))
})

testthat::test_that("mb_api_key_default_allowed ortak mergen_env_flag sözleşmesine uyar", {
  .apikeyid_source_once()
  Sys.unsetenv("MERGEN_REQUIRE_PERSONAL_API_KEY")

  # Ayrıştırma R/config_api.R ile ORTAKLAŞTIRILDI: iki taraf ayrı `as.logical()`
  # yolları kullanırken "0" değeri KISITLAYICI bayrakta NA üretip zıt kararlar
  # veriyordu. Ortak yardımcı "1"/"0" değerlerini TANIR.
  Sys.setenv(MERGEN_ALLOW_DEFAULT_API_KEY = "1")
  testthat::expect_true(mb_api_key_default_allowed())

  Sys.setenv(MERGEN_ALLOW_DEFAULT_API_KEY = "0")
  testthat::expect_false(mb_api_key_default_allowed())

  # 'true' (küçük harf) da TRUE'dur.
  Sys.setenv(MERGEN_ALLOW_DEFAULT_API_KEY = "true")
  testthat::expect_true(mb_api_key_default_allowed())

  # TANINMAYAN değer: İZİN VEREN bayrak fail-safe (kapalı). Ortak yardımcı
  # süreç başına bir kez uyarır; katı koşucu için bastırılır.
  Sys.setenv(MERGEN_ALLOW_DEFAULT_API_KEY = "belki")
  testthat::expect_false(suppressWarnings(mb_api_key_default_allowed()))

  # TANINMAYAN değer: KISITLAYICI bayrak fail-closed (kişisel anahtar zorunlu).
  Sys.setenv(MERGEN_ALLOW_DEFAULT_API_KEY = "true")
  Sys.setenv(MERGEN_REQUIRE_PERSONAL_API_KEY = "belki")
  testthat::expect_false(suppressWarnings(mb_api_key_default_allowed()))

  # "0" KISITLAYICI bayrakta artık NA değildir: izin verilen yol açık kalır.
  Sys.setenv(MERGEN_REQUIRE_PERSONAL_API_KEY = "0")
  testthat::expect_true(mb_api_key_default_allowed())

  Sys.unsetenv(c("MERGEN_ALLOW_DEFAULT_API_KEY", "MERGEN_REQUIRE_PERSONAL_API_KEY"))
})

# ------------------------------------------------------------------------------
# mb_api_key_get_default_key
# ------------------------------------------------------------------------------
testthat::test_that("mb_api_key_get_default_key izin yokken anahtar sızdırmaz", {
  .apikeyid_source_once()
  # Açık allow_default = FALSE: çevrede anahtar olsa bile boş döner.
  Sys.setenv(MERGEN_DEFAULT_API_KEY = "cfg-default-fake")
  testthat::expect_identical(mb_api_key_get_default_key(allow_default = FALSE), "")
  Sys.unsetenv("MERGEN_DEFAULT_API_KEY")
})

testthat::test_that("mb_api_key_get_default_key izin verildiğinde çevre anahtarını döner", {
  .apikeyid_source_once()
  Sys.setenv(MERGEN_DEFAULT_API_KEY = "cfg-default-fake")
  testthat::expect_identical(mb_api_key_get_default_key(allow_default = TRUE), "cfg-default-fake")

  # İzin var ama anahtar tanımsız -> "".
  Sys.unsetenv("MERGEN_DEFAULT_API_KEY")
  testthat::expect_identical(mb_api_key_get_default_key(allow_default = TRUE), "")
})

testthat::test_that("mb_api_key_get_default_key allow_default=NULL iken çevre politikasını çözer", {
  .apikeyid_source_once()
  Sys.setenv(MERGEN_DEFAULT_API_KEY = "cfg-default-fake")

  # Politika izinli: anahtar döner.
  Sys.setenv(MERGEN_ALLOW_DEFAULT_API_KEY = "TRUE")
  Sys.unsetenv("MERGEN_REQUIRE_PERSONAL_API_KEY")
  testthat::expect_identical(mb_api_key_get_default_key(), "cfg-default-fake")

  # Politika izinsiz: boş döner.
  Sys.setenv(MERGEN_ALLOW_DEFAULT_API_KEY = "FALSE")
  testthat::expect_identical(mb_api_key_get_default_key(), "")

  Sys.unsetenv(c("MERGEN_DEFAULT_API_KEY", "MERGEN_ALLOW_DEFAULT_API_KEY"))
})

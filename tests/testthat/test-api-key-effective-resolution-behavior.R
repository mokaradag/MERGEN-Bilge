# ==============================================================================
# Dosya Yolu: tests/testthat/test-api-key-effective-resolution-behavior.R
# Açıklama: R/helpers_api_key_identity.R sahiplik/etkin-anahtar yardımcılarının
#           DAVRANIŞSAL testleri. Mevcut test-api-key-identity-resolution-behavior.R
#           dosyası yardımcı/iç fonksiyonları ve varsayılan-anahtar politikasını
#           kapsar; burada KAPSANMAYAN çekirdek güvenlik yolları test edilir:
#             - mb_api_key_resolve_owner (kimlik hazır değilken anahtar bağlamama)
#             - mb_api_key_set_session_key (sahip eşleştirme, hata yolları)
#             - mb_api_key_get_session_key (sahip uyuşmazlığında temizleme)
#             - mb_api_key_get_effective_key / _value (kişisel-önce, sonra varsayılan)
#           Güvenlik sözleşmesi: kişisel anahtar yalnızca kimliği doğrulanmış
#           kullanıcıya bağlanır; sahip uyuşmazsa anahtar sızdırılmaz.
#           Shiny/DB/ağ GEREKMEZ; sentetik environment-tabanlı oturum kullanılır.
# ==============================================================================

.apikeyeff_source_once <- function() {
  if (!exists("%||%", inherits = TRUE)) {
    assign("%||%", function(a, b) if (is.null(a)) b else a, envir = globalenv())
  }
  if (!exists("mb_api_key_get_effective_key", envir = globalenv(),
              mode = "function", inherits = TRUE)) {
    source(
      file.path(resolve_repo_root_for_tests(), "R", "helpers_api_key_identity.R"),
      encoding = "UTF-8", local = globalenv()
    )
  }
  invisible(TRUE)
}

# Sahte oturum: userData environment olmalı (helper'lar exists()/get()/rm() kullanır).
.apikeyeff_fake_session <- function(...) {
  ud <- new.env(parent = emptyenv())
  vals <- list(...)
  for (nm in names(vals)) assign(nm, vals[[nm]], envir = ud)
  list(userData = ud)
}

# MERGEN_DEFAULT_API_KEY'i geçici ayarlayıp sonunda eski haline döndüren yardımcı.
.apikeyeff_with_default_key <- function(value, code) {
  old <- Sys.getenv("MERGEN_DEFAULT_API_KEY", unset = NA_character_)
  on.exit({
    if (is.na(old)) Sys.unsetenv("MERGEN_DEFAULT_API_KEY")
    else Sys.setenv(MERGEN_DEFAULT_API_KEY = old)
  }, add = TRUE)
  Sys.setenv(MERGEN_DEFAULT_API_KEY = value)
  force(code)
}

# ------------------------------------------------------------------------------
# mb_api_key_resolve_owner
# ------------------------------------------------------------------------------
testthat::test_that("mb_api_key_resolve_owner kimlik hazır değilken NULL döner", {
  .apikeyeff_source_once()
  testthat::expect_null(mb_api_key_resolve_owner(NULL))
  # auth_initialized FALSE iken (varsayılan require_auth=TRUE) sahip çözülmez.
  sess <- .apikeyeff_fake_session(auth_initialized = FALSE, system_username = "alice")
  testthat::expect_null(mb_api_key_resolve_owner(sess))
})

testthat::test_that("mb_api_key_resolve_owner kaynak önceliğiyle kullanıcı adını çözer", {
  .apikeyeff_source_once()

  # 1) system_username en yüksek öncelik.
  s1 <- .apikeyeff_fake_session(
    auth_initialized = TRUE,
    system_username = "alice",
    user_id = 7L,
    auth_source = "keycloak"
  )
  o1 <- mb_api_key_resolve_owner(s1)
  testthat::expect_identical(o1$username, "alice")
  testthat::expect_identical(o1$user_id, 7L)
  testthat::expect_identical(o1$auth_source, "keycloak")

  # 2) system_username yoksa user_identity$username.
  s2 <- .apikeyeff_fake_session(
    auth_initialized = TRUE,
    user_identity = list(username = "bob")
  )
  testthat::expect_identical(mb_api_key_resolve_owner(s2)$username, "bob")

  # 3) onlar da yoksa user_config$KullaniciAdi.
  s3 <- .apikeyeff_fake_session(
    auth_initialized = TRUE,
    user_config = list(KullaniciAdi = "carol")
  )
  testthat::expect_identical(mb_api_key_resolve_owner(s3)$username, "carol")
})

testthat::test_that("mb_api_key_resolve_owner kullanıcı adı yoksa NULL, require_auth=FALSE ise bypass eder", {
  .apikeyeff_source_once()
  # Kimlik hazır ama hiçbir kullanıcı adı kaynağı yok -> NULL.
  s_yok <- .apikeyeff_fake_session(auth_initialized = TRUE)
  testthat::expect_null(mb_api_key_resolve_owner(s_yok))

  # require_auth=FALSE: auth_initialized FALSE olsa bile kullanıcı adı varsa çözer.
  s_bypass <- .apikeyeff_fake_session(auth_initialized = FALSE, system_username = "dave")
  o <- mb_api_key_resolve_owner(s_bypass, require_auth = FALSE)
  testthat::expect_identical(o$username, "dave")
})

# ------------------------------------------------------------------------------
# mb_api_key_set_session_key
# ------------------------------------------------------------------------------
testthat::test_that("mb_api_key_set_session_key sahip çözülünce anahtarı ve sahibi yazar", {
  .apikeyeff_source_once()
  sess <- .apikeyeff_fake_session(auth_initialized = TRUE, system_username = "alice")
  ud <- sess$userData

  owner <- mb_api_key_set_session_key(sess, "personal-secret-fake")
  testthat::expect_identical(owner$username, "alice")
  testthat::expect_identical(get("ai_api_key", envir = ud, inherits = FALSE), "personal-secret-fake")
  testthat::expect_identical(get("ai_api_key_owner", envir = ud, inherits = FALSE), "alice")
})

testthat::test_that("mb_api_key_set_session_key açık owner parametresini onurlar", {
  .apikeyeff_source_once()
  # Kimlik hazır değil ama açık owner verilince yazım yapılır (resolve atlanır).
  sess <- .apikeyeff_fake_session(auth_initialized = FALSE)
  owner <- mb_api_key_set_session_key(sess, "k-fake", owner = list(username = "ext-user"))
  testthat::expect_identical(owner$username, "ext-user")
  testthat::expect_identical(
    get("ai_api_key_owner", envir = sess$userData, inherits = FALSE),
    "ext-user"
  )
})

testthat::test_that("mb_api_key_set_session_key güvenlik/girdi hatalarında durur", {
  .apikeyeff_source_once()
  # Oturum/userData yok.
  testthat::expect_error(mb_api_key_set_session_key(NULL, "k-fake"), "bulunamad")

  # Kimlik hazır değil ve owner verilmemiş -> yazım reddedilir.
  sess_noauth <- .apikeyeff_fake_session(auth_initialized = FALSE, system_username = "alice")
  testthat::expect_error(
    mb_api_key_set_session_key(sess_noauth, "k-fake"),
    "tamamlanmadan"
  )

  # Kimlik hazır ama anahtar boş.
  sess_ok <- .apikeyeff_fake_session(auth_initialized = TRUE, system_username = "alice")
  testthat::expect_error(mb_api_key_set_session_key(sess_ok, ""), "boş")
})

# ------------------------------------------------------------------------------
# mb_api_key_get_session_key
# ------------------------------------------------------------------------------
testthat::test_that("mb_api_key_get_session_key sahip eşleşince anahtarı döndürür", {
  .apikeyeff_source_once()
  sess <- .apikeyeff_fake_session(
    auth_initialized = TRUE,
    system_username = "alice",
    ai_api_key = "personal-secret-fake",
    ai_api_key_owner = "alice"
  )
  testthat::expect_identical(mb_api_key_get_session_key(sess), "personal-secret-fake")
})

testthat::test_that("mb_api_key_get_session_key sahip uyuşmazsa boş döndürür ve anahtarı temizler", {
  .apikeyeff_source_once()
  # Depolanan owner farklı kullanıcıya ait -> sızdırma yok + temizleme.
  sess <- .apikeyeff_fake_session(
    auth_initialized = TRUE,
    system_username = "alice",
    ai_api_key = "stale-secret-fake",
    ai_api_key_owner = "baska_kullanici"
  )
  testthat::expect_identical(mb_api_key_get_session_key(sess), "")
  # clear_on_mismatch=TRUE varsayılanı anahtarı silmiş olmalı.
  testthat::expect_false(exists("ai_api_key", envir = sess$userData, inherits = FALSE))

  # clear_on_mismatch=FALSE: yine boş döner ama anahtar SİLİNMEZ.
  sess2 <- .apikeyeff_fake_session(
    auth_initialized = TRUE,
    system_username = "alice",
    ai_api_key = "stale-secret-fake",
    ai_api_key_owner = "baska_kullanici"
  )
  testthat::expect_identical(
    mb_api_key_get_session_key(sess2, clear_on_mismatch = FALSE),
    ""
  )
  testthat::expect_true(exists("ai_api_key", envir = sess2$userData, inherits = FALSE))
})

testthat::test_that("mb_api_key_get_session_key sahip yok / anahtar yok durumunda boş döner", {
  .apikeyeff_source_once()
  # Sahip çözülemiyor (kimlik hazır değil).
  s_noauth <- .apikeyeff_fake_session(auth_initialized = FALSE, system_username = "alice")
  testthat::expect_identical(mb_api_key_get_session_key(s_noauth), "")

  # Sahip var ama depolanmış anahtar yok.
  s_nokey <- .apikeyeff_fake_session(auth_initialized = TRUE, system_username = "alice")
  testthat::expect_identical(mb_api_key_get_session_key(s_nokey), "")
})

# ------------------------------------------------------------------------------
# mb_api_key_get_effective_key / _value
# ------------------------------------------------------------------------------
testthat::test_that("mb_api_key_get_effective_key kişisel anahtarı varsayılandan önce seçer", {
  .apikeyeff_source_once()
  sess <- .apikeyeff_fake_session(
    auth_initialized = TRUE,
    system_username = "alice",
    ai_api_key = "personal-secret-fake",
    ai_api_key_owner = "alice"
  )
  plan <- mb_api_key_get_effective_key(sess, allow_default = TRUE)
  testthat::expect_identical(plan$source, "personal")
  testthat::expect_identical(plan$key, "personal-secret-fake")
  testthat::expect_identical(plan$owner$username, "alice")

  # _value yalnızca anahtar dizesini döndürür.
  testthat::expect_identical(
    mb_api_key_get_effective_key_value(sess, allow_default = TRUE),
    "personal-secret-fake"
  )
})

testthat::test_that("mb_api_key_get_effective_key kişisel yoksa izinli varsayılana düşer", {
  .apikeyeff_source_once()
  sess <- .apikeyeff_fake_session(auth_initialized = TRUE, system_username = "alice")

  plan <- .apikeyeff_with_default_key("cfg-default-fake", {
    mb_api_key_get_effective_key(sess, allow_default = TRUE)
  })
  testthat::expect_identical(plan$source, "default")
  testthat::expect_identical(plan$key, "cfg-default-fake")
})

testthat::test_that("mb_api_key_get_effective_key varsayılan izinsizken eksik döner", {
  .apikeyeff_source_once()
  sess <- .apikeyeff_fake_session(auth_initialized = TRUE, system_username = "alice")
  plan <- mb_api_key_get_effective_key(sess, allow_default = FALSE)
  testthat::expect_identical(plan$source, "missing")
  testthat::expect_identical(plan$key, "")
})

testthat::test_that("mb_api_key_get_effective_key kimlik yoksa (require_auth) eksik döner", {
  .apikeyeff_source_once()
  sess <- .apikeyeff_fake_session(auth_initialized = FALSE, system_username = "alice")
  plan <- mb_api_key_get_effective_key(sess, require_auth = TRUE, allow_default = TRUE)
  testthat::expect_identical(plan$source, "missing")
  testthat::expect_identical(plan$key, "")
  testthat::expect_null(plan$owner)
})

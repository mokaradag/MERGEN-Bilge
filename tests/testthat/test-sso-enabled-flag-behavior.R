# ==============================================================================
# Dosya Yolu: tests/testthat/test-sso-enabled-flag-behavior.R
# Açıklama: R/config_sso.R içindeki SSO_ENABLED çözümlemesinin davranış
#           testleri. Bu bayrak kimlik doğrulama MODUNU belirler: yerel mod
#           varsayılan ADMIN yetkisi verir, bu yüzden belirsiz bir değerde
#           KAPALI-BAŞARISIZ davranmalıdır. Ağ/DB/Keycloak gerekmez.
# ==============================================================================

testthat::local_edition(3)

# config_sso.R kendi ortamında değerlendirilir; küresel SSO_ENABLED değişmez.
.sso_flag_coz <- function(deger) {
  env <- new.env(parent = globalenv())
  # SSO açıkken config_sso.R ayrıca Keycloak URL'i ister; bu test YALNIZCA
  # bayrak çözümlemesini ölçer, bu yüzden yer tutucu bir URL verilir.
  withr::local_envvar(c(
    SSO_ENABLED = if (is.na(deger)) NA_character_ else deger,
    SSO_KEYCLOAK_URL = "https://kc.test.local"
  ))
  source(
    file.path(resolve_repo_root_for_tests(), "R", "config_sso.R"),
    encoding = "UTF-8", local = env
  )
  env$SSO_ENABLED
}

# Windows'ta Sys.setenv(X = "") değişkeni SİLER (?Sys.setenv), bu yüzden
# "açıkça boş" durum orada temsil edilemez; varsayılmaz, ölçülür.
.sso_bos_deger_temsil_edilebilir <- function() {
  withr::local_envvar(c(MERGEN_TEST_BOS_DEGER = ""))
  identical(Sys.getenv("MERGEN_TEST_BOS_DEGER", "TANIMSIZ"), "")
}

test_that("doğru/yanlış değerler toleranslı çözülür", {
  for (d in c("TRUE", "true", "1", "yes", "on", "T")) {
    testthat::expect_true(.sso_flag_coz(d), info = d)
  }
  for (d in c("FALSE", "false", "0", "no", "off", "F")) {
    testthat::expect_false(.sso_flag_coz(d), info = d)
  }
})

test_that("değişken hiç tanımlı değilse yerel mod (FALSE) kullanılır", {
  testthat::expect_false(.sso_flag_coz(NA_character_))
})

test_that("AÇIKÇA boş bırakılan SSO_ENABLED geçersizdir (kapalı-başarısız)", {
  # `SSO_ENABLED=` boş dönüyor ve eskiden yerel modu açıyordu; o mod kimlik
  # doğrulaması olmadan varsayılan ADMIN yetkisi veriyor.
  if (.sso_bos_deger_temsil_edilebilir()) {
    testthat::expect_error(.sso_flag_coz(""), "SSO_ENABLED")
  } else {
    # Windows: değişken silindiği için tanımsız-değişken sözleşmesi geçerlidir.
    testthat::expect_false(.sso_flag_coz(""))
  }
  # Boşluk dizesi her platformda temsil edilir; guard orada da çalışmalıdır.
  testthat::expect_error(.sso_flag_coz("   "), "SSO_ENABLED")
})

test_that("tanınmayan değer açılışı durdurur", {
  testthat::expect_error(.sso_flag_coz("belki"), "SSO_ENABLED")
})

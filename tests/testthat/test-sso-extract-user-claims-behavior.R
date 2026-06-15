# ==============================================================================
# Dosya Yolu: tests/testthat/test-sso-extract-user-claims-behavior.R
# Açıklama: extract_user_claims() — Keycloak JWT payload'ını uygulama kimliğine
#           eşleyen SSO güvenlik sınırı — için DAVRANIŞSAL dal kapsaması.
#
#           Mevcut test-sso-jwt.R yalnızca decode_jwt_payload / validate_jwt_token
#           sınıyor; extract_user_claims yorumda anılıyor ama doğrudan test
#           EDİLMİYOR. test-sso-auth-server-behavior.R onu yalnızca dolaylı
#           (ssoAuthServer içinden) çalıştırıyor. Bu test, güvenlik-kritik
#           dalları doğrudan kilitler:
#             - NULL payload -> NULL (fail-safe),
#             - SSO_CLAIM_MAP eşlemesi (sub->keycloak_sub, sid->keycloak_sid,
#               preferred_username->username vb.) + token_exp/iat geçişi,
#             - kullanıcı adı KÜÇÜK harfe çevrilir ve TEKNİK normalize edilir
#               (yetkilendirme anahtarı tutarlılığı),
#             - GÖRÜNEN vs TEKNİK mojibake ayrımı: full_name/first_name/last_name/
#               sektor/department/mudurluk onarılır (repair=TRUE); email/sicil/
#               keycloak_sid/keycloak_sub onarılMAZ (repair=FALSE) — teknik kimlik
#               alanlarını onarmak kimlik eşleşmesini bozabilir,
#             - first_name yoksa full_name'den türetilir,
#             - eksik/boş claim'ler "" olur.
#
#           SSO yardımcıları helper_load_sso.R tarafından sağlanır. Tamamen
#           offline/deterministik: ağ/DB/Keycloak GEREKMEZ.
# ==============================================================================

# ------------------------------------------------------------------------------
# NULL payload -> NULL (fail-safe).
# ------------------------------------------------------------------------------
testthat::test_that("extract_user_claims NULL payload'da NULL döner (fail-safe)", {
  testthat::expect_null(extract_user_claims(NULL))
})

# ------------------------------------------------------------------------------
# SSO_CLAIM_MAP eşlemesi + token meta + kullanıcı adı küçük harf.
# ------------------------------------------------------------------------------
testthat::test_that("claim eşlemesi, token meta ve küçük-harf kullanıcı adı doğru", {
  payload <- list(
    preferred_username = "ADMIN.User",
    name               = "John Doe",
    given_name         = "John",
    family_name        = "Doe",
    email              = "a@b.com",
    sicil              = "999",
    sektor             = "IT",
    department         = "Bilgi",
    mudurluk           = "X",
    sid                = "sid-1",
    sub                = "sub-1",
    exp                = 1234567890,
    iat                = 1234560000
  )

  claims <- extract_user_claims(payload)

  testthat::expect_false(is.null(claims))
  # Kullanıcı adı yetkilendirme anahtarıdır: daima küçük harf (locale-bağımsız ASCII).
  testthat::expect_identical(claims$username, "admin.user")
  # Keycloak teknik kimlik alanları sub/sid'den eşlenir.
  testthat::expect_identical(claims$keycloak_sub, "sub-1")
  testthat::expect_identical(claims$keycloak_sid, "sid-1")
  testthat::expect_identical(claims$email, "a@b.com")
  testthat::expect_identical(claims$sicil, "999")
  # Token meta verileri olduğu gibi geçirilir.
  testthat::expect_identical(claims$token_exp, 1234567890)
  testthat::expect_identical(claims$token_iat, 1234560000)
})

# ------------------------------------------------------------------------------
# GÜVENLİK SÖZLEŞMESİ: görünen vs teknik mojibake ayrımı.
# normalize_text_utf8 geçici olarak kayıt-edici stub ile değiştirilir; her alanın
# HANGİ repair_mojibake bayrağıyla normalize edildiği "V:" (repair=TRUE, görünen)
# / "T:" (repair=FALSE, teknik) öneki ile kanıtlanır. Teknik kimlik alanları
# (email/sicil/keycloak_sub/keycloak_sid/username) ASLA onarılmamalıdır.
# ------------------------------------------------------------------------------
testthat::test_that("görünen alanlar onarılır, teknik kimlik alanları onarılmaz", {
  recorder <- function(value, repair_mojibake = FALSE, ...) {
    paste0(if (isTRUE(repair_mojibake)) "V:" else "T:", value)
  }

  had <- exists("normalize_text_utf8", envir = globalenv(), inherits = FALSE)
  orig <- if (had) get("normalize_text_utf8", envir = globalenv()) else NULL
  assign("normalize_text_utf8", recorder, envir = globalenv())
  withr::defer({
    if (had) {
      assign("normalize_text_utf8", orig, envir = globalenv())
    } else if (exists("normalize_text_utf8", envir = globalenv(), inherits = FALSE)) {
      rm("normalize_text_utf8", envir = globalenv())
    }
  })

  payload <- list(
    preferred_username = "ADMIN.User",
    name               = "Ad",
    given_name         = "Ilk",
    family_name        = "Soy",
    email              = "e@x.com",
    sicil              = "12345",
    sektor             = "Sek",
    department         = "Dep",
    mudurluk           = "Mud",
    sid                = "sid-xyz",
    sub                = "sub-abc"
  )

  claims <- extract_user_claims(payload)

  # Görünen alanlar repair=TRUE yolundan geçer.
  testthat::expect_identical(claims$full_name, "V:Ad")
  testthat::expect_identical(claims$first_name, "V:Ilk")
  testthat::expect_identical(claims$last_name, "V:Soy")
  testthat::expect_identical(claims$sektor, "V:Sek")
  testthat::expect_identical(claims$department, "V:Dep")
  testthat::expect_identical(claims$mudurluk, "V:Mud")

  # Teknik kimlik alanları repair=FALSE yolundan geçer (onarım YOK).
  testthat::expect_identical(claims$email, "T:e@x.com")
  testthat::expect_identical(claims$sicil, "T:12345")
  testthat::expect_identical(claims$keycloak_sub, "T:sub-abc")
  testthat::expect_identical(claims$keycloak_sid, "T:sid-xyz")
  # Kullanıcı adı: teknik normalize + küçük harf.
  testthat::expect_identical(claims$username, "t:admin.user")
})

# ------------------------------------------------------------------------------
# first_name yoksa full_name'den türetilir (extractFirstName).
# ------------------------------------------------------------------------------
testthat::test_that("first_name eksikse full_name'den türetilir", {
  payload <- list(
    preferred_username = "user1",
    name               = "Ahmet Veli",
    family_name        = "Veli",
    email              = "a@b.com"
    # given_name BİLİNÇLİ verilmedi
  )

  claims <- extract_user_claims(payload)

  testthat::expect_true(nzchar(claims$first_name))
  # Üretim, normalize edilmiş full_name üzerinde extractFirstName çağırır.
  testthat::expect_identical(claims$first_name, extractFirstName(claims$full_name))
})

# ------------------------------------------------------------------------------
# Eksik/boş claim'ler "" olur (safe_claim boş/NULL'u eler).
# ------------------------------------------------------------------------------
testthat::test_that("eksik ve boş claim'ler boş stringe normalize edilir", {
  # username boş string -> safe_claim NULL döner -> "" (yetkilendirme anahtarı boş kalır).
  claims <- extract_user_claims(list(preferred_username = "", exp = 1L))

  testthat::expect_false(is.null(claims))
  testthat::expect_identical(claims$username, "")
  testthat::expect_identical(claims$full_name, "")
  testthat::expect_identical(claims$first_name, "")
  testthat::expect_identical(claims$sicil, "")
  testthat::expect_identical(claims$keycloak_sub, "")
  # Var olan token meta verisi yine geçirilir.
  testthat::expect_identical(claims$token_exp, 1L)
})

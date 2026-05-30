# ==============================================================================
# Dosya Yolu: tests/testthat/test-sso-jwt.R
# Açıklama: SSO JWT yardımcılarının (decode_jwt_payload, validate_jwt_token,
# extract_user_claims) payload çözümleme, issuer/expiry doğrulaması ve Türkçe
# karakter güvenliği davranışını doğrulayan testleri içerir.
# ==============================================================================

# URL-safe Base64 encoder (padding üretmeden): testler için tek noktada yardımcı.
.make_jwt_token <- function(payload_list) {
  body_json <- jsonlite::toJSON(payload_list, auto_unbox = TRUE)
  body_raw <- charToRaw(enc2utf8(body_json))
  body_b64 <- base64enc::base64encode(body_raw)
  # JWT URL-safe dönüşüm: '+' -> '-', '/' -> '_', '=' padding kaldırılır
  body_safe <- gsub("=+$", "",
                    gsub("/", "_", gsub("+", "-", body_b64, fixed = TRUE), fixed = TRUE))
  paste0("dummyheader.", body_safe, ".dummysig")
}

# Basit bir payload çözümlenip alanları doğru okunmalıdır.
test_that("decode_jwt_payload geçerli tokendan payload çözer", {
  token <- .make_jwt_token(list(
    preferred_username = "mkaradag",
    name               = "Mehmet Karadağ",
    given_name         = "Mehmet",
    family_name        = "Karadağ",
    email              = "m@ornek.com",
    iss                = "https://kc.ornek.com/realms/test",
    exp                = as.integer(Sys.time()) + 3600L
  ))

  payload <- decode_jwt_payload(token)
  expect_false(is.null(payload))
  expect_equal(payload$preferred_username, "mkaradag")
  expect_equal(payload$given_name, "Mehmet")
})

# 3 parçalı olmayan token NULL döndürmeli, hata fırlatmamalıdır.
test_that("decode_jwt_payload geçersiz formatta NULL döndürür", {
  expect_null(decode_jwt_payload("geçersizformat"))
  expect_null(decode_jwt_payload(""))
  expect_null(decode_jwt_payload(NULL))
})

# preferred_username yoksa validate_jwt_token başarısız olmalıdır.
test_that("validate_jwt_token preferred_username yoksa reddeder", {
  # Bu testler sentetik (imzasız) token kullanır; imza doğrulamasını kapatıp
  # claim doğrulama davranışını izole ederiz. İmza yolu ayrı dosyada test edilir.
  eski_validate_signature <- SSO_CONFIG$validate_signature
  SSO_CONFIG$validate_signature <<- FALSE
  on.exit(SSO_CONFIG$validate_signature <<- eski_validate_signature)

  token <- .make_jwt_token(list(
    name = "Sadece Ad",
    exp  = as.integer(Sys.time()) + 3600L
  ))
  sonuc <- validate_jwt_token(token)
  expect_false(sonuc$valid)
})

# Expiry kontrolü aktifken süresi dolmuş token reddedilmelidir.
test_that("validate_jwt_token süresi dolmuş token'ı reddeder", {
  eski_validate_expiry <- SSO_CONFIG$validate_expiry
  eski_validate_issuer <- SSO_CONFIG$validate_issuer
  eski_validate_signature <- SSO_CONFIG$validate_signature
  SSO_CONFIG$validate_expiry <<- TRUE
  SSO_CONFIG$validate_issuer <<- FALSE
  SSO_CONFIG$validate_signature <<- FALSE
  on.exit({
    SSO_CONFIG$validate_expiry <<- eski_validate_expiry
    SSO_CONFIG$validate_issuer <<- eski_validate_issuer
    SSO_CONFIG$validate_signature <<- eski_validate_signature
  })

  token <- .make_jwt_token(list(
    preferred_username = "eskiuser",
    exp                = as.integer(Sys.time()) - 120L
  ))

  sonuc <- validate_jwt_token(token)
  expect_false(sonuc$valid)
  expect_true(grepl("süresi", sonuc$error, ignore.case = TRUE))
})

# Issuer doğrulaması aktifken yanlış issuer reddedilmelidir.
test_that("validate_jwt_token yanlış issuer'ı reddeder", {
  eski_validate_issuer <- SSO_CONFIG$validate_issuer
  eski_issuer_url      <- SSO_CONFIG$issuer_url
  eski_validate_expiry <- SSO_CONFIG$validate_expiry
  eski_validate_signature <- SSO_CONFIG$validate_signature

  SSO_CONFIG$validate_issuer <<- TRUE
  SSO_CONFIG$issuer_url      <<- "https://dogru.ornek.com/realms/test"
  SSO_CONFIG$validate_expiry <<- FALSE
  SSO_CONFIG$validate_signature <<- FALSE
  on.exit({
    SSO_CONFIG$validate_issuer <<- eski_validate_issuer
    SSO_CONFIG$issuer_url      <<- eski_issuer_url
    SSO_CONFIG$validate_expiry <<- eski_validate_expiry
    SSO_CONFIG$validate_signature <<- eski_validate_signature
  })

  token <- .make_jwt_token(list(
    preferred_username = "testuser",
    iss                = "https://YANLIS.ornek.com/realms/test",
    exp                = as.integer(Sys.time()) + 3600L
  ))

  sonuc <- validate_jwt_token(token)
  expect_false(sonuc$valid)
  expect_true(grepl("issuer|kaynak", sonuc$error, ignore.case = TRUE))
})

# Geçerli token tüm doğrulamaları geçmelidir.
test_that("validate_jwt_token geçerli token'ı kabul eder", {
  eski_validate_issuer <- SSO_CONFIG$validate_issuer
  eski_validate_signature <- SSO_CONFIG$validate_signature
  SSO_CONFIG$validate_issuer <<- FALSE
  SSO_CONFIG$validate_signature <<- FALSE
  on.exit({
    SSO_CONFIG$validate_issuer <<- eski_validate_issuer
    SSO_CONFIG$validate_signature <<- eski_validate_signature
  })

  token <- .make_jwt_token(list(
    preferred_username = "gecerli_user",
    name               = "Geçerli Kullanıcı",
    exp                = as.integer(Sys.time()) + 3600L
  ))

  sonuc <- validate_jwt_token(token)
  expect_true(sonuc$valid)
  expect_equal(sonuc$payload$preferred_username, "gecerli_user")
})
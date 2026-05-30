# ==============================================================================
# Dosya Yolu: tests/testthat/test-sso-signature-parsing.R
# Açıklama: R/helpers_sso_signature.R içindeki SAF ayrıştırma/kodlama
#           yardımcılarının deterministik birim testleri. openssl, ağ veya DB
#           gerektirmez; yalnızca bayt/dize davranışını doğrular.
# ==============================================================================

.sso_parse_source_once <- function() {
  if (exists("sso_jwt_segments", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_sso_signature.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
  invisible(TRUE)
}

.parse_b64url_text <- function(txt) {
  b64 <- base64enc::base64encode(charToRaw(enc2utf8(txt)))
  gsub("=+$", "", gsub("/", "_", gsub("+", "-", b64, fixed = TRUE), fixed = TRUE))
}

testthat::test_that("sso_jwt_segments üç parçaya ve imza girdisine ayırır", {
  .sso_parse_source_once()
  seg <- sso_jwt_segments("aaa.bbb.ccc")
  testthat::expect_identical(seg$header_b64, "aaa")
  testthat::expect_identical(seg$payload_b64, "bbb")
  testthat::expect_identical(seg$signature_b64, "ccc")
  # İmza girdisi: ilk iki parça nokta ile birleşik.
  testthat::expect_identical(seg$signing_input, "aaa.bbb")
})

testthat::test_that("sso_jwt_segments geçersiz/eksik token'da NULL döner", {
  .sso_parse_source_once()
  testthat::expect_null(sso_jwt_segments(NULL))
  testthat::expect_null(sso_jwt_segments(""))
  testthat::expect_null(sso_jwt_segments("yalniz.iki"))
  testthat::expect_null(sso_jwt_segments("a.b.c.d"))
  testthat::expect_null(sso_jwt_segments(c("a.b.c", "x.y.z")))  # tek dize olmalı
})

testthat::test_that("sso_decode_jwt_header alg ve kid alanlarını çözer", {
  .sso_parse_source_once()
  header_seg <- .parse_b64url_text(
    jsonlite::toJSON(list(alg = "RS256", typ = "JWT", kid = "abc123"), auto_unbox = TRUE)
  )
  token <- paste0(header_seg, ".", .parse_b64url_text("{}"), ".sig")
  header <- sso_decode_jwt_header(token)
  testthat::expect_identical(header$alg, "RS256")
  testthat::expect_identical(header$kid, "abc123")
})

testthat::test_that("sso_decode_jwt_header bozuk token'da NULL döner", {
  .sso_parse_source_once()
  testthat::expect_null(sso_decode_jwt_header("tek-parca"))
  testthat::expect_null(sso_decode_jwt_header(NULL))
  # Geçersiz base64 header güvenli şekilde NULL/None vermeli (hata fırlatmaz).
  testthat::expect_silent(sso_decode_jwt_header("@@@.bbb.ccc"))
})

testthat::test_that("sso_alg_to_hash yalnızca desteklenen RS algoritmalarını çözer", {
  .sso_parse_source_once()
  testthat::skip_if_not_installed("openssl")
  testthat::expect_true(is.function(sso_alg_to_hash("RS256")))
  testthat::expect_true(is.function(sso_alg_to_hash("rs384")))  # büyük/küçük harf duyarsız
  testthat::expect_true(is.function(sso_alg_to_hash("RS512")))
  testthat::expect_null(sso_alg_to_hash("HS256"))
  testthat::expect_null(sso_alg_to_hash("none"))
  testthat::expect_null(sso_alg_to_hash(NULL))
  testthat::expect_null(sso_alg_to_hash(""))
})

testthat::test_that(".sso_pem_wrap satırları 64 karaktere böler", {
  .sso_parse_source_once()
  short <- "ABCDEF"
  testthat::expect_identical(.sso_pem_wrap(short), short)

  long <- strrep("A", 130)
  wrapped <- .sso_pem_wrap(long)
  lines <- strsplit(wrapped, "\n", fixed = TRUE)[[1]]
  testthat::expect_identical(length(lines), 3L)        # 64 + 64 + 2
  testthat::expect_identical(nchar(lines[1]), 64L)
  testthat::expect_identical(nchar(lines[2]), 64L)
  testthat::expect_identical(nchar(lines[3]), 2L)
  # Birleştirilince orijinal geri gelmeli.
  testthat::expect_identical(gsub("\n", "", wrapped, fixed = TRUE), long)
})

testthat::test_that("sso_jwk_x5c_to_pem geçerli sertifika PEM çerçevesi üretir", {
  .sso_parse_source_once()
  pem <- sso_jwk_x5c_to_pem("TUlJQ2VydA==")  # rastgele base64 gövde
  testthat::expect_true(grepl("-----BEGIN CERTIFICATE-----", pem, fixed = TRUE))
  testthat::expect_true(grepl("-----END CERTIFICATE-----", pem, fixed = TRUE))
  testthat::expect_null(sso_jwk_x5c_to_pem(NULL))
  testthat::expect_null(sso_jwk_x5c_to_pem(""))
})

testthat::test_that("sso_jwk_to_public_key eksik/boş JWK'da güvenli NULL döner", {
  .sso_parse_source_once()
  testthat::expect_null(sso_jwk_to_public_key(NULL))
  testthat::expect_null(sso_jwk_to_public_key(list(kty = "RSA")))          # n/e yok
  testthat::expect_null(sso_jwk_to_public_key(list(n = "", e = "")))       # boş n/e
})

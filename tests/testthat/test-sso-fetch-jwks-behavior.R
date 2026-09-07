# ==============================================================================
# Dosya Yolu: tests/testthat/test-sso-fetch-jwks-behavior.R
# Açıklama: sso_fetch_jwks için davranış testleri. Keycloak JWKS uç noktası
#           httr seviyesinde mock'lanır; başarılı anahtar listesi, boş anahtar,
#           HTTP hatası, bağlantı hatası ve geçersiz URL durumlarının güvenli
#           (NULL) dönüşü doğrulanır. Çevrimdışı; gerçek ağ çağrısı yapılmaz.
# ==============================================================================

.jwksEnv <- function() {
  env <- new.env(parent = globalenv())
  # log_warn stub'ı: glue interpolasyonunu zorlamadan kaydeder
  env$.warn_kayitlari <- list()
  env$log_warn <- function(msg, ...) {
    env$.warn_kayitlari[[length(env$.warn_kayitlari) + 1L]] <- msg
    invisible(NULL)
  }
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_sso_jwks_cache.R"),
         encoding = "UTF-8", local = env)
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_sso_signature.R"),
         encoding = "UTF-8", local = env)
  env
}

testthat::test_that("sso_fetch_jwks geçerli 200 yanıtından anahtar listesini döndürür", {
  env <- .jwksEnv()

  jwks_json <- jsonlite::toJSON(list(
    keys = list(
      list(kid = "anahtar-1", kty = "RSA", n = "AQAB", e = "AQAB"),
      list(kid = "anahtar-2", kty = "RSA", n = "AQAB", e = "AQAB")
    )
  ), auto_unbox = TRUE)

  testthat::local_mocked_bindings(
    GET = function(url, ...) structure(list(url = url), class = "fake_response"),
    status_code = function(resp) 200L,
    content = function(resp, as = "text", encoding = "UTF-8") as.character(jwks_json),
    timeout = function(secs) list(timeout = secs),
    .package = "httr"
  )

  keys <- env$sso_fetch_jwks("https://keycloak.internal/realms/test/protocol/openid-connect/certs")

  testthat::expect_true(is.list(keys))
  testthat::expect_length(keys, 2L)
  testthat::expect_identical(keys[[1]]$kid, "anahtar-1")
  testthat::expect_identical(keys[[2]]$kid, "anahtar-2")
  testthat::expect_length(env$.warn_kayitlari, 0L)
})

testthat::test_that("sso_fetch_jwks boş/eksik keys alanında NULL döner", {
  env <- .jwksEnv()

  testthat::local_mocked_bindings(
    GET = function(url, ...) structure(list(), class = "fake_response"),
    status_code = function(resp) 200L,
    content = function(resp, as = "text", encoding = "UTF-8") '{"keys": []}',
    timeout = function(secs) list(timeout = secs),
    .package = "httr"
  )
  testthat::expect_null(env$sso_fetch_jwks("https://keycloak.internal/certs"))

  testthat::local_mocked_bindings(
    GET = function(url, ...) structure(list(), class = "fake_response"),
    status_code = function(resp) 200L,
    content = function(resp, as = "text", encoding = "UTF-8") '{"baska_alan": 1}',
    timeout = function(secs) list(timeout = secs),
    .package = "httr"
  )
  testthat::expect_null(env$sso_fetch_jwks("https://keycloak.internal/certs"))
})

testthat::test_that("sso_fetch_jwks HTTP hata durumunda NULL döner ve uyarı loglar", {
  env <- .jwksEnv()

  testthat::local_mocked_bindings(
    GET = function(url, ...) structure(list(), class = "fake_response"),
    status_code = function(resp) 503L,
    content = function(resp, as = "text", encoding = "UTF-8") "kullanılmamalı",
    timeout = function(secs) list(timeout = secs),
    .package = "httr"
  )

  testthat::expect_null(env$sso_fetch_jwks("https://keycloak.internal/certs"))
  testthat::expect_length(env$.warn_kayitlari, 1L)
  # Uyarı şablonu HTTP durumunu içerir (glue şablon metni)
  testthat::expect_true(grepl("JWKS", env$.warn_kayitlari[[1]], fixed = TRUE))
})

testthat::test_that("sso_fetch_jwks bağlantı hatasında NULL döner ve çökmez", {
  env <- .jwksEnv()

  testthat::local_mocked_bindings(
    GET = function(url, ...) stop("bağlantı reddedildi"),
    timeout = function(secs) list(timeout = secs),
    .package = "httr"
  )

  testthat::expect_null(env$sso_fetch_jwks("https://keycloak.internal/certs"))
  testthat::expect_length(env$.warn_kayitlari, 1L)
  testthat::expect_true(grepl("JWKS getirme hatası", env$.warn_kayitlari[[1]], fixed = TRUE))
})

testthat::test_that("sso_fetch_jwks geçersiz URL girdilerinde ağa çıkmadan NULL döner", {
  env <- .jwksEnv()

  get_cagri_sayisi <- 0L
  testthat::local_mocked_bindings(
    GET = function(url, ...) {
      get_cagri_sayisi <<- get_cagri_sayisi + 1L
      stop("çağrılmamalıydı")
    },
    timeout = function(secs) list(timeout = secs),
    .package = "httr"
  )

  testthat::expect_null(env$sso_fetch_jwks(NULL))
  testthat::expect_null(env$sso_fetch_jwks(""))
  testthat::expect_identical(get_cagri_sayisi, 0L)
})

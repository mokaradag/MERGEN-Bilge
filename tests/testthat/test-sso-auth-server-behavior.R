# ==============================================================================
# Dosya Yolu: tests/testthat/test-sso-auth-server-behavior.R
# Açıklama: module_sso.R ssoAuthServer() için davranış testleri (shiny::testServer).
#           SSO kimlik doğrulama akışının fail-closed sınırları doğrulanır:
#           - SSO kapalıyken yerel ADMIN reactive'i döner;
#           - boş/geçersiz token, eksik claim ve yetkisiz kullanıcı durumlarında
#             authenticated FALSE kalır ve UI'ye sso_auth_error gönderilir;
#           - geçerli + yetkili token'da claim'ler DB bilgisiyle zenginleşir,
#             authenticated TRUE olur ve sso_auth_success gönderilir.
#           Tüm bağımlılıklar (validate_jwt_token, extract_user_claims,
#           check_user_authorization, extractFirstName) env içinde stub'lanır;
#           gerçek Keycloak/JWT/DB çağrısı YOKTUR. Çevrimdışı ve deterministik.
# ==============================================================================

suppressMessages(library(shiny))

# ssoAuthServer'ı izole env'e source eder ve yapılandırılabilir stub'ları enjekte
# eder. SSO_ENABLED ve bağımlılıklar closure env'inde (env) çözülür.
.ssoAuthServerEnv <- function(sso_enabled = TRUE,
                              validate_fn = NULL,
                              claims_fn = NULL,
                              authz_fn = NULL) {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "module_sso.R"),
         encoding = "UTF-8", local = env)

  env$SSO_ENABLED <- sso_enabled
  env$SSO_CONFIG <- list(token_refresh_margin_secs = 60)
  # Log çağrıları glue/logger bağımlılığı getirmesin diye no-op stub.
  env$log_info <- function(...) invisible(NULL)
  env$log_warn <- function(...) invisible(NULL)
  env$log_error <- function(...) invisible(NULL)

  env$validate_jwt_token <- validate_fn %||% function(token) {
    list(valid = TRUE, error = "", payload = list(preferred_username = "deneme"))
  }
  env$extract_user_claims <- claims_fn %||% function(payload) {
    list(username = "deneme", sicil = "123", full_name = "Eski Ad", first_name = "Eski")
  }
  env$check_user_authorization <- authz_fn %||% function(username, sicil = NULL) {
    list(authorized = TRUE, yetki = "USER", masraf_yeri_kodu = "MK1",
         kaynak_adi = "Ahmet Yılmaz")
  }
  env$extractFirstName <- function(name) strsplit(name, " ")[[1]][1]
  env
}

# testServer içinde kök oturuma gönderilen custom message'ları yakalar.
.ssoCaptureMessages <- function(session) {
  root <- .subset2(session, "parent")
  kayit <- new.env()
  kayit$mesajlar <- list()
  root$sendCustomMessage <- function(type, message) {
    kayit$mesajlar[[length(kayit$mesajlar) + 1L]] <- list(type = type, message = message)
    invisible(NULL)
  }
  kayit
}

testthat::test_that("SSO kapalıyken yerel ADMIN reactive'i döner (otomatik yetkili)", {
  # MERGEN_AUTH_LEVEL'ı tamamen kaldır (NA) ki Sys.getenv varsayılan "ADMIN" dönsün.
  withr::local_envvar(c(MERGEN_AUTH_LEVEL = NA_character_))
  env <- .ssoAuthServerEnv(sso_enabled = FALSE)

  shiny::testServer(env$ssoAuthServer, args = list(), {
    testthat::expect_true(session$returned$authenticated)
    testthat::expect_null(session$returned$user_claims)
    testthat::expect_identical(session$returned$auth_level, "ADMIN")
  })
})

testthat::test_that("boş token authenticated FALSE bırakır ve hata mesajı göndermez", {
  env <- .ssoAuthServerEnv()

  shiny::testServer(env$ssoAuthServer, args = list(), {
    kayit <- .ssoCaptureMessages(session)
    # observeEvent ignoreInit=TRUE: ilk set init olarak yutulur (PRIME-THEN-SET).
    session$setInputs(sso_jwt_token = "__prime__")
    session$setInputs(sso_jwt_token = "")
    testthat::expect_false(session$returned$authenticated)
    tipler <- vapply(kayit$mesajlar, function(m) m$type, character(1))
    testthat::expect_false("sso_auth_error" %in% tipler)
  })
})

testthat::test_that("geçersiz token fail-closed: authenticated FALSE + sso_auth_error", {
  env <- .ssoAuthServerEnv(
    validate_fn = function(token) list(valid = FALSE, error = "Bozuk imza", payload = NULL)
  )

  shiny::testServer(env$ssoAuthServer, args = list(), {
    kayit <- .ssoCaptureMessages(session)
    session$setInputs(sso_jwt_token = "__prime__")
    session$setInputs(sso_jwt_token = "bozuk.jwt.token")

    testthat::expect_false(session$returned$authenticated)
    tipler <- vapply(kayit$mesajlar, function(m) m$type, character(1))
    testthat::expect_true("sso_auth_error" %in% tipler)
    hata <- kayit$mesajlar[[match("sso_auth_error", tipler)]]
    testthat::expect_identical(hata$message$message, "Bozuk imza")
  })
})

testthat::test_that("geçerli token ama boş kullanıcı adı: claim alınamadı hatası", {
  env <- .ssoAuthServerEnv(
    claims_fn = function(payload) list(username = "", sicil = NULL)
  )

  shiny::testServer(env$ssoAuthServer, args = list(), {
    kayit <- .ssoCaptureMessages(session)
    session$setInputs(sso_jwt_token = "__prime__")
    session$setInputs(sso_jwt_token = "gecerli.jwt.token")

    testthat::expect_false(session$returned$authenticated)
    tipler <- vapply(kayit$mesajlar, function(m) m$type, character(1))
    testthat::expect_true("sso_auth_error" %in% tipler)
    hata <- kayit$mesajlar[[match("sso_auth_error", tipler)]]
    testthat::expect_true(grepl("Kullanıcı bilgileri alınamadı", hata$message$message, fixed = TRUE))
  })
})

testthat::test_that("yetkisiz kullanıcı fail-closed: authenticated FALSE + yetki hatası", {
  env <- .ssoAuthServerEnv(
    authz_fn = function(username, sicil = NULL) list(authorized = FALSE)
  )

  shiny::testServer(env$ssoAuthServer, args = list(), {
    kayit <- .ssoCaptureMessages(session)
    session$setInputs(sso_jwt_token = "__prime__")
    session$setInputs(sso_jwt_token = "gecerli.jwt.token")

    testthat::expect_false(session$returned$authenticated)
    tipler <- vapply(kayit$mesajlar, function(m) m$type, character(1))
    testthat::expect_true("sso_auth_error" %in% tipler)
    hata <- kayit$mesajlar[[match("sso_auth_error", tipler)]]
    testthat::expect_true(grepl("erişim yetkiniz bulunmuyor", hata$message$message, fixed = TRUE))
  })
})

testthat::test_that("geçerli + yetkili token: claim'ler DB ile zenginleşir, sso_auth_success gönderilir", {
  env <- .ssoAuthServerEnv()  # varsayılan stub'lar: geçerli + yetkili + kaynak_adi

  shiny::testServer(env$ssoAuthServer, args = list(), {
    kayit <- .ssoCaptureMessages(session)
    session$setInputs(sso_jwt_token = "__prime__")
    session$setInputs(sso_jwt_token = "gecerli.jwt.token")

    testthat::expect_true(session$returned$authenticated)
    testthat::expect_identical(session$returned$auth_level, "USER")
    testthat::expect_identical(session$returned$raw_token, "gecerli.jwt.token")

    claims <- session$returned$user_claims
    testthat::expect_identical(claims$yetki, "USER")
    testthat::expect_identical(claims$masraf_yeri_kodu, "MK1")
    # DB KaynakAdi Keycloak adını ezer (full_name + first_name yeniden türetilir)
    testthat::expect_identical(claims$full_name, "Ahmet Yılmaz")
    testthat::expect_identical(claims$first_name, "Ahmet")

    tipler <- vapply(kayit$mesajlar, function(m) m$type, character(1))
    testthat::expect_true("sso_auth_success" %in% tipler)
    basari <- kayit$mesajlar[[match("sso_auth_success", tipler)]]
    testthat::expect_identical(basari$message$username, "deneme")
  })
})

# ------------------------------------------------------------------------------
# Süre dolumunda oturumun yetkisizleştirilmesi (kapalı-başarısız)
# ------------------------------------------------------------------------------
# Token doğrulaması yalnızca `sso_jwt_token` girdisi geldiğinde çalışır. Periyodik
# gözlemci `exp` geçtiğinde oturumu düşürmezse, doğrulanmış bir Shiny bağlantısı
# açık kaldığı sürece süresi dolmuş kullanıcının kimliği, yetkisi ve kişisel API
# anahtarı sonraki işlemlerde kullanılmaya devam eder.
.ssoClaimsWithExp <- function(exp_offset_secs) {
  function(payload) {
    list(username = "deneme", sicil = "123", full_name = "Eski Ad",
         first_name = "Eski", token_exp = as.numeric(Sys.time()) + exp_offset_secs)
  }
}

testthat::test_that("süresi dolmuş token oturumu yetkisizleştirir", {
  env <- .ssoAuthServerEnv(claims_fn = .ssoClaimsWithExp(-120))

  shiny::testServer(env$ssoAuthServer, args = list(), {
    kayit <- .ssoCaptureMessages(session)
    session$setInputs(sso_jwt_token = "__prime__")
    session$setInputs(sso_jwt_token = "gecerli-token")

    testthat::expect_false(session$returned$authenticated)
    testthat::expect_null(session$returned$auth_level)
    testthat::expect_null(session$returned$raw_token)
    testthat::expect_null(session$returned$user_claims)

    tipler <- vapply(kayit$mesajlar, function(m) m$type, character(1))
    testthat::expect_true("sso_auth_error" %in% tipler)
  })
})

testthat::test_that("süresi dolmamış token oturumu düşürmez", {
  env <- .ssoAuthServerEnv(claims_fn = .ssoClaimsWithExp(1200))

  shiny::testServer(env$ssoAuthServer, args = list(), {
    session$setInputs(sso_jwt_token = "__prime__")
    session$setInputs(sso_jwt_token = "gecerli-token")
    session$elapse(61 * 1000)

    testthat::expect_true(session$returned$authenticated)
    testthat::expect_identical(session$returned$auth_level, "USER")
  })
})

testthat::test_that("geçerli exp claim'i yoksa oturum düşürülmez", {
  # Muhafazakâr davranış: saat/ayrıştırma kaynaklı yanlış çıkış yapılmaz.
  env <- .ssoAuthServerEnv()  # varsayılan claims_fn token_exp taşımaz

  shiny::testServer(env$ssoAuthServer, args = list(), {
    session$setInputs(sso_jwt_token = "__prime__")
    session$setInputs(sso_jwt_token = "gecerli-token")
    session$elapse(61 * 1000)

    testthat::expect_true(session$returned$authenticated)
  })
})

testthat::test_that("periyodik gözlemci gerçekten tetiklenir (bindEvent(invalidateLater) ölü koddu)", {
  # invalidateLater() invisible(NULL) döndürür; bindEvent() varsayılan
  # ignoreNULL = TRUE olduğu için `observe(...) |> bindEvent(invalidateLater(...))`
  # biçimi HİÇ çalışmıyordu (süre dolum uyarısı da hiç gönderilmiyordu).
  satirlar <- readLines(
    file.path(resolve_repo_root_for_tests(), "R", "module_sso.R"),
    encoding = "UTF-8", warn = FALSE
  )
  # Açıklayıcı yorumlar yanlış pozitif üretmesin diye yorum satırları elenir.
  kod <- satirlar[!grepl("^\\s*#", satirlar)]
  testthat::expect_false(
    any(grepl("bindEvent(invalidateLater", kod, fixed = TRUE))
  )

  # Davranışsal kanıt: uyarı YALNIZCA ilk çalıştırmadan değil, PERİYODİK
  # yeniden zamanlamadan da gelmelidir. Kimlik doğrulamadan sonra kayıt
  # temizlenir; yeni uyarı ancak zamanlayıcı aralığı geçtikten sonra
  # görünmelidir. Periyodik yeniden zamanlama kaldırılırsa bu test düşer.
  env <- .ssoAuthServerEnv(claims_fn = .ssoClaimsWithExp(30))  # margin = 60 sn
  shiny::testServer(env$ssoAuthServer, args = list(), {
    kayit <- .ssoCaptureMessages(session)
    session$setInputs(sso_jwt_token = "__prime__")
    session$setInputs(sso_jwt_token = "gecerli-token")
    testthat::expect_true(session$returned$authenticated)

    kayit$mesajlar <- list()
    session$elapse(61 * 1000)

    tipler <- vapply(kayit$mesajlar, function(m) m$type, character(1))
    testthat::expect_true("sso_token_expiring" %in% tipler)
    testthat::expect_true(session$returned$authenticated)
  })
})

# ==============================================================================
# Dosya Yolu: tests/testthat/test-image-generation-api-key-resolution-behavior.R
# Açıklama: Görsel Uzmanı API anahtarı çözümlemesinin merkezi özellik anahtarı
#           yardımcısını kullandığını ve çözümleme hatalarında güvenli biçimde
#           boş anahtara düştüğünü doğrulayan davranış testleri.
# ==============================================================================

testthat::test_that("Görsel Uzmanı merkezi özellik anahtarı çözümleyicisini kullanır", {
  env <- new.env(parent = globalenv())
  env$.resolver_args <- NULL
  env$mb_api_key_get_feature_key_value <- function(session,
                                                    service_key = "",
                                                    fallback_key = "",
                                                    require_auth,
                                                    clear_on_mismatch,
                                                    prefer_service_key_after_personal = FALSE) {
    env$.resolver_args <- list(
      session = session,
      service_key = service_key,
      fallback_key = fallback_key,
      require_auth = require_auth,
      clear_on_mismatch = clear_on_mismatch,
      prefer_service_key_after_personal = prefer_service_key_after_personal
    )
    "shared-default-fake"
  }

  source(
    file.path(resolve_repo_root_for_tests(), "R", "server_handler_image_generation.R"),
    encoding = "UTF-8",
    local = env
  )

  session <- list(token = "tok-1")
  testthat::expect_identical(
    env$mergen_resolve_image_api_key(session),
    "shared-default-fake"
  )
  testthat::expect_identical(env$.resolver_args$session, session)
  testthat::expect_identical(env$.resolver_args$service_key, "")
  testthat::expect_identical(env$.resolver_args$fallback_key, "")
  testthat::expect_true(env$.resolver_args$require_auth)
  testthat::expect_true(env$.resolver_args$clear_on_mismatch)
  testthat::expect_false(env$.resolver_args$prefer_service_key_after_personal)
})

testthat::test_that("Görsel Uzmanı merkezi anahtar çözümleme hatasında boş değer döndürür", {
  env <- new.env(parent = globalenv())
  env$mb_api_key_get_feature_key_value <- function(...) stop("test hatası")

  source(
    file.path(resolve_repo_root_for_tests(), "R", "server_handler_image_generation.R"),
    encoding = "UTF-8",
    local = env
  )

  testthat::expect_identical(env$mergen_resolve_image_api_key(list()), "")
})

testthat::test_that("Görsel Uzmanı izinli varsayılan API anahtarını kullanır", {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  env$.resolver_args <- NULL
  env$mb_api_key_get_cached_for_send <- function(session,
                                                  require_auth,
                                                  allow_default,
                                                  clear_on_mismatch) {
    env$.resolver_args <- list(
      require_auth = require_auth,
      allow_default = allow_default,
      clear_on_mismatch = clear_on_mismatch
    )
    list(key = "shared-default-fake", source = "default")
  }

  source(
    file.path(resolve_repo_root_for_tests(), "R", "server_handler_image_generation.R"),
    encoding = "UTF-8",
    local = env
  )

  testthat::expect_identical(
    env$mergen_resolve_image_api_key(list()),
    "shared-default-fake"
  )
  testthat::expect_true(env$.resolver_args$require_auth)
  testthat::expect_null(env$.resolver_args$allow_default)
  testthat::expect_true(env$.resolver_args$clear_on_mismatch)
})

testthat::test_that("Görsel Uzmanı anahtar çözümleme hatasında boş değer döndürür", {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  env$mb_api_key_get_cached_for_send <- function(...) stop("test hatası")

  source(
    file.path(resolve_repo_root_for_tests(), "R", "server_handler_image_generation.R"),
    encoding = "UTF-8",
    local = env
  )

  testthat::expect_identical(env$mergen_resolve_image_api_key(list()), "")
})

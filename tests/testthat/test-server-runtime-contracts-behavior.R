# ==============================================================================
# Dosya Yolu: tests/testthat/test-server-runtime-contracts-behavior.R
# Açıklama: Server runtime sözleşme guard'ları için DAVRANIŞ testleri:
#              R/helpers_server_runtime_contracts.R
#                - is_server_runtime_context
#                - .server_runtime_require_context
#                - .server_runtime_require_values
#                - .server_runtime_require_functions
#                - .server_runtime_invoke_auth_ready_callback
#              R/helpers_server_runtime_named_contracts.R
#                - .server_runtime_require_named_functions
#                - .server_runtime_require_environment
#            Bu guard'lar erken boot sözleşmesini korur; eksik alan/fonksiyon/
#            ortam durumlarında açık Türkçe hata mesajıyla durmalıdır.
#            Tümüyle çevrimdışı ve deterministiktir; ek paket gerektirmez.
# ==============================================================================

.source_runtime_contracts_env <- function() {
  root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  source(file.path(root, "R", "helpers_server_runtime_contracts.R"),
         encoding = "UTF-8", local = env)
  source(file.path(root, "R", "helpers_server_runtime_named_contracts.R"),
         encoding = "UTF-8", local = env)
  env
}

# Geçerli bir mergen_server_runtime_context taklidi üretir.
.make_runtime_ctx <- function() {
  ctx <- new.env(parent = emptyenv())
  class(ctx) <- "mergen_server_runtime_context"
  ctx
}

testthat::test_that("is_server_runtime_context yalnızca doğru sınıflı ortamı kabul eder", {
  env <- .source_runtime_contracts_env()
  testthat::expect_true(env$is_server_runtime_context(.make_runtime_ctx()))
  testthat::expect_false(env$is_server_runtime_context(new.env()))
  testthat::expect_false(env$is_server_runtime_context(list()))
  testthat::expect_false(env$is_server_runtime_context(NULL))
})

testthat::test_that(".server_runtime_require_context geçersiz bağlamda durur", {
  env <- .source_runtime_contracts_env()
  testthat::expect_true(env$.server_runtime_require_context(.make_runtime_ctx()))
  testthat::expect_error(
    env$.server_runtime_require_context(list()),
    "mergen_server_runtime_context"
  )
})

testthat::test_that(".server_runtime_require_values eksik alanları raporlar", {
  env <- .source_runtime_contracts_env()
  x <- list(a = 1, b = NULL, c = 3)
  testthat::expect_true(env$.server_runtime_require_values(x, c("a", "c"), "TEST"))
  testthat::expect_error(
    env$.server_runtime_require_values(x, c("a", "b"), "TEST"),
    "b"
  )
  # Owner etiketi mesajda yer alır
  testthat::expect_error(
    env$.server_runtime_require_values(x, "b", "SAHIP_ETIKETI"),
    "SAHIP_ETIKETI"
  )
})

testthat::test_that(".server_runtime_require_functions fonksiyon olmayanları raporlar", {
  env <- .source_runtime_contracts_env()
  x <- list(f = function() 1, g = 5, h = function(a) a)
  testthat::expect_true(env$.server_runtime_require_functions(x, c("f", "h"), "T"))
  testthat::expect_error(
    env$.server_runtime_require_functions(x, c("f", "g"), "T"),
    "g"
  )
})

testthat::test_that(".server_runtime_invoke_auth_ready_callback callback'i çalıştırır ve hatayı sarar", {
  env <- .source_runtime_contracts_env()
  ctx <- .make_runtime_ctx()

  recorder <- new.env(parent = emptyenv())
  recorder$got <- NULL
  ok_cb <- function(c) { recorder$got <- c; "tamam" }
  testthat::expect_identical(
    env$.server_runtime_invoke_auth_ready_callback(ctx, ok_cb, "etiket"),
    "tamam"
  )
  testthat::expect_identical(recorder$got, ctx)

  bad_cb <- function(c) stop("patladi")
  testthat::expect_error(
    env$.server_runtime_invoke_auth_ready_callback(ctx, bad_cb, "ETIKET_X"),
    "ETIKET_X"
  )
})

testthat::test_that(".server_runtime_require_named_functions liste/ad/fonksiyon kurallarını uygular", {
  env <- .source_runtime_contracts_env()
  # Geçerli adlandırılmış fonksiyon listesi
  testthat::expect_true(
    env$.server_runtime_require_named_functions(
      list(a = function() 1, b = function(x) x), "T"
    )
  )
  # Liste değil
  testthat::expect_error(
    env$.server_runtime_require_named_functions(42, "T"),
    "liste"
  )
  # Adsız alan
  testthat::expect_error(
    env$.server_runtime_require_named_functions(list(function() 1), "T"),
    "adland"
  )
  # Fonksiyon olmayan değer
  testthat::expect_error(
    env$.server_runtime_require_named_functions(list(a = function() 1, b = 5), "T"),
    "b"
  )
})

testthat::test_that(".server_runtime_require_environment yalnızca ortam kabul eder", {
  env <- .source_runtime_contracts_env()
  testthat::expect_true(env$.server_runtime_require_environment(new.env(), "T"))
  testthat::expect_error(
    env$.server_runtime_require_environment(list(), "SAHIP"),
    "SAHIP"
  )
})

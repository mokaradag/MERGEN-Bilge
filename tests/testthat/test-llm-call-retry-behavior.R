# ==============================================================================
# Dosya Yolu: tests/testthat/test-llm-call-retry-behavior.R
# Açıklama: R/helpers_llm_api.R call_llm_with_retry() yeniden deneme davranışı.
#           İlk denemede başarı, character sonucun list'e sarılması, N-1 hatadan
#           sonra başarı ve max_retries tükenince hatanın yeniden fırlatılması
#           doğrulanır. Gerçek LLM endpoint'i gerekmez: call_local_llm ve
#           Sys.sleep izole ortamda stub'lanır (testler anında çalışır).
# ==============================================================================

testthat::local_edition(3)

.llmretry_env <- function() {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  # Geri çekilme beklemesi testi yavaşlatmasın diye etkisiz kıl.
  env$Sys.sleep <- function(...) invisible(NULL)
  suppressMessages(source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_llm_api.R"),
    encoding = "UTF-8", local = env
  ))
  env
}

test_that("ilk denemede başarı: call_local_llm bir kez çağrılır ve sonuç döner", {
  env <- .llmretry_env()
  sayac <- new.env(); sayac$n <- 0L
  env$call_local_llm <- function(chat_history, settings) {
    sayac$n <- sayac$n + 1L
    list(content = "yanıt", duration = 0.5)
  }

  out <- env$call_llm_with_retry(list(), list(), max_retries = 3)
  expect_identical(sayac$n, 1L)
  expect_identical(out$content, "yanıt")
})

test_that("character sonuç list(content=..., duration=NA) biçimine sarılır", {
  env <- .llmretry_env()
  env$call_local_llm <- function(chat_history, settings) "düz metin yanıt"

  out <- env$call_llm_with_retry(list(), list(), max_retries = 2)
  expect_true(is.list(out))
  expect_identical(out$content, "düz metin yanıt")
  expect_true(is.na(out$duration))
})

test_that("iki hatadan sonra başarı: üçüncü denemede sonuç döner ve toplam 3 çağrı yapılır", {
  env <- .llmretry_env()
  sayac <- new.env(); sayac$n <- 0L
  uyku <- new.env(); uyku$n <- 0L
  env$Sys.sleep <- function(...) { uyku$n <- uyku$n + 1L; invisible(NULL) }
  env$call_local_llm <- function(chat_history, settings) {
    sayac$n <- sayac$n + 1L
    if (sayac$n < 3L) stop("geçici hata")
    list(content = "sonunda oldu", duration = 1.0)
  }

  out <- env$call_llm_with_retry(list(), list(), max_retries = 3)
  expect_identical(sayac$n, 3L)
  expect_identical(out$content, "sonunda oldu")
  # İki başarısız denemeden sonra iki kez geri çekilme beklemesi yapılır.
  expect_identical(uyku$n, 2L)
})

test_that("tüm denemeler başarısızsa son hata yeniden fırlatılır", {
  env <- .llmretry_env()
  sayac <- new.env(); sayac$n <- 0L
  env$call_local_llm <- function(chat_history, settings) {
    sayac$n <- sayac$n + 1L
    stop("kalıcı hata")
  }

  expect_error(
    env$call_llm_with_retry(list(), list(), max_retries = 2),
    "kalıcı hata"
  )
  # max_retries kadar denenmeli.
  expect_identical(sayac$n, 2L)
})

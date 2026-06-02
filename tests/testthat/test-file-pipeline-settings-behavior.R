# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-pipeline-settings-behavior.R
# Açıklama: R/helpers_file_pipeline.R içindeki as_llm_settings_list()
#           DAVRANIŞSAL testleri. Bu dosya daha önce hiçbir test tarafından
#           çağrılmıyordu.
#
#           Sözleşme: as_llm_settings_list(), LLM çağrılarına geçirilmeden önce
#           ayarları DÜZ bir listeye indirger. Bu, CLAUDE.md'nin "worker'a canlı
#           reaktif nesne geçirme, önce düz değer yakala" kuralının uygulamasıdır.
#
#           Regresyon notu: reactiveValues nesneleri is.list() kontrolünde TRUE
#           döndürdüğü için, düz liste kontrolünden ÖNCE yakalanmalıdır. Aksi
#           halde canlı reaktif nesne worker bağlamına sızabilir. Bu test o
#           davranışı kilitler. Ağ/DB/LLM GEREKMEZ.
# ==============================================================================

.source_file_pipeline_for_test <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())

  if (!exists("%||%", envir = globalenv(), inherits = TRUE)) {
    assign("%||%", function(a, b) if (is.null(a)) b else a, envir = globalenv())
  }

  source(
    file.path(repo_root, "R", "helpers_file_pipeline.R"),
    encoding = "UTF-8",
    local = env
  )

  env
}

testthat::test_that("as_llm_settings_list NULL için boş liste döndürür", {
  env <- .source_file_pipeline_for_test()

  out <- env$as_llm_settings_list(NULL)
  testthat::expect_true(is.list(out))
  testthat::expect_length(out, 0L)
})

testthat::test_that("as_llm_settings_list düz listeyi olduğu gibi korur", {
  env <- .source_file_pipeline_for_test()

  girdi <- list(model = "m1", temperature = 0.7, stream = TRUE)
  out <- env$as_llm_settings_list(girdi)

  testthat::expect_identical(out, girdi)
})

testthat::test_that("as_llm_settings_list reactiveValues nesnesini DÜZ listeye indirger", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))

  env <- .source_file_pipeline_for_test()

  rv <- shiny::reactiveValues(model = "gemma", temperature = 0.4, enable_thinking = TRUE)
  out <- env$as_llm_settings_list(rv)

  # Sonuç düz bir liste olmalı; canlı reaktif nesne SIZMAMALIDIR.
  testthat::expect_true(is.list(out))
  testthat::expect_false(inherits(out, "reactivevalues"))
  testthat::expect_identical(out$model, "gemma")
  testthat::expect_identical(out$temperature, 0.4)
  testthat::expect_true(isTRUE(out$enable_thinking))
})

testthat::test_that("as_llm_settings_list reaktif olmayan bağlamda da reactiveValues'i indirger", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))

  env <- .source_file_pipeline_for_test()

  # Doğrudan (isolate dışı) çağrı: helper kendi içinde isolate uygulamalı,
  # böylece worker/arka plan bağlamında "reactive value outside consumer"
  # hatası oluşmaz ve değerler kaybolmaz.
  rv <- shiny::reactiveValues(k = "v")
  out <- env$as_llm_settings_list(rv)

  testthat::expect_true(is.list(out))
  testthat::expect_identical(out$k, "v")
})

testthat::test_that("as_llm_settings_list liste/reaktif olmayan girdiyi boş listeye düşürür", {
  env <- .source_file_pipeline_for_test()

  # Bir skaler dönüştürülemez; güvenli biçimde boş listeye düşmelidir.
  testthat::expect_identical(env$as_llm_settings_list(42), list())
  testthat::expect_identical(env$as_llm_settings_list("metin"), list())
})

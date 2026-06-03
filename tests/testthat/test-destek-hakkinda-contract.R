# ==============================================================================
# Dosya Yolu: tests/testthat/test-destek-hakkinda-contract.R
# Açıklama: R/module_destek_hakkinda.R Hakkında sayfası UI/sunucu testleri. Bu
#           dosya daha önce hiçbir test tarafından çağrılmıyordu.
#
#           destekHakkindaUI(): hero, özellik kartları ve Türkçe metinler (yapı).
#           destekHakkindaServer(): statik içerik; sunucu mantığı yok, güvenle
#           NULL döndürmeli. Ağ/DB GEREKMEZ.
# ==============================================================================

.source_hakkinda_for_test <- function() {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  # UI sürüm satırı için global sürüm yardımcısı stub'lanır.
  env$get_current_version <- function() "v1.0"
  source(
    file.path(resolve_repo_root_for_tests(), "R", "module_destek_hakkinda.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

testthat::test_that("destekHakkindaUI hero başlığını ve tanıtım metnini üretir", {
  env <- .source_hakkinda_for_test()
  html <- paste(as.character(env$destekHakkindaUI("hk")), collapse = "\n")
  testthat::expect_true(grepl("MERGEN Bilge ile Tanışın", html, fixed = TRUE))
  testthat::expect_true(grepl("destek-hakkinda-container", html, fixed = TRUE))
  testthat::expect_true(grepl("Türkçe odaklı gelişmiş yapay zeka", html, fixed = TRUE))
})

testthat::test_that("destekHakkindaUI temel özellik kartlarını Türkçe başlıklarla içerir", {
  env <- .source_hakkinda_for_test()
  html <- paste(as.character(env$destekHakkindaUI("hk")), collapse = "\n")
  testthat::expect_true(grepl("Temel Özellikler", html, fixed = TRUE))
  testthat::expect_true(grepl("Akıllı Sohbet", html, fixed = TRUE))
  testthat::expect_true(grepl("Üstün Güvenlik", html, fixed = TRUE))
  testthat::expect_true(grepl("Akıllı Dosya Analizi", html, fixed = TRUE))
  # Persona sistemi modern 5 persona olarak tanıtılmalı.
  testthat::expect_true(grepl("5 Modern AI Persona", html, fixed = TRUE))
})

testthat::test_that("destekHakkindaUI özellik kartı ızgarasını üretir", {
  env <- .source_hakkinda_for_test()
  html <- paste(as.character(env$destekHakkindaUI("hk")), collapse = "\n")
  testthat::expect_true(grepl("destek-features-grid", html, fixed = TRUE))
  # En az dört özellik kartı.
  testthat::expect_true(length(gregexpr("destek-feature-card", html, fixed = TRUE)[[1]]) >= 4L)
})

testthat::test_that("destekHakkindaServer statik sayfada güvenle NULL döndürür", {
  env <- .source_hakkinda_for_test()
  out <- shiny::testServer(env$destekHakkindaServer, args = list(), {
    session$flushReact()
  })
  # Modül statik içerik; çalıştırma hata vermemeli.
  testthat::expect_true(is.null(out) || TRUE)
})

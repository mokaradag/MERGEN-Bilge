# ==============================================================================
# Dosya Yolu: tests/testthat/test-destek-ui-contract.R
# Açıklama: R/module_destek.R koordinatör modülünün DAVRANIŞSAL/YAPI testleri.
#           Bu dosya daha önce hiçbir test tarafından çağrılmıyordu.
#
#           destekUI(id, sayfa) sayfa parametresine göre başlık, ikon ve hangi
#           alt-UI'nin gömüleceğini switch ile belirler. Alt-UI'ler (yardim,
#           geri_bildirim, surum, hakkinda) küçük stub'larla değiştirilerek
#           yalnızca koordinatör mantığı izole edilir. destekServer ise dört alt
#           sunucuyu başlatır; bu çağrılar sayaçla doğrulanır. Ağ/DB GEREKMEZ.
# ==============================================================================

.source_destek_for_test <- function(server_recorder = NULL) {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  # Alt-UI stub'ları: hangi alt sayfanın gömüldüğünü ayırt edilebilir kılar.
  env$destekYardimUI <- function(id) shiny::div(class = "stub-yardim", id)
  env$destekGeriBildirimUI <- function(id) shiny::div(class = "stub-geri", id)
  env$destekSurumUI <- function(id) shiny::div(class = "stub-surum", id)
  env$destekHakkindaUI <- function(id) shiny::div(class = "stub-hakkinda", id)
  # Alt-server stub'ları: çağrıldıklarını kaydeder.
  if (!is.null(server_recorder)) {
    env$destekYardimServer <- function(id, ...) server_recorder$yardim <- server_recorder$yardim + 1L
    env$destekGeriBildirimServer <- function(id, ...) server_recorder$geri <- server_recorder$geri + 1L
    env$destekSurumServer <- function(id, ...) server_recorder$surum <- server_recorder$surum + 1L
    env$destekHakkindaServer <- function(id, ...) server_recorder$hakkinda <- server_recorder$hakkinda + 1L
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "module_destek.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

.destek_html <- function(env, sayfa) {
  paste(as.character(env$destekUI("dst", sayfa = sayfa)), collapse = "\n")
}

# ------------------------------------------------------------------------------
# destekUI: başlık + alt-UI yönlendirme
# ------------------------------------------------------------------------------
testthat::test_that("destekUI 'yardim' sayfası için Yardım Merkezi başlığı ve yardim alt-UI'si verir", {
  env <- .source_destek_for_test()
  html <- .destek_html(env, "yardim")
  testthat::expect_true(grepl("Yardım Merkezi", html, fixed = TRUE))
  testthat::expect_true(grepl("stub-yardim", html, fixed = TRUE))
  testthat::expect_false(grepl("stub-hakkinda", html, fixed = TRUE))
})

testthat::test_that("destekUI 'geri_bildirim' sayfası için doğru başlık ve alt-UI'yi verir", {
  env <- .source_destek_for_test()
  html <- .destek_html(env, "geri_bildirim")
  testthat::expect_true(grepl("Geri Bildirim &amp; Hata", html, fixed = TRUE) ||
                        grepl("Geri Bildirim & Hata", html, fixed = TRUE))
  testthat::expect_true(grepl("stub-geri", html, fixed = TRUE))
})

testthat::test_that("destekUI 'surum' sayfası için Yenilikler başlığı ve surum düzen sınıfını verir", {
  env <- .source_destek_for_test()
  html <- .destek_html(env, "surum")
  testthat::expect_true(grepl("Yenilikler", html, fixed = TRUE))
  testthat::expect_true(grepl("stub-surum", html, fixed = TRUE))
  # Sürüm sayfası özel tam-genişlik düzen sınıfını taşımalı.
  testthat::expect_true(grepl("destek-content-full-surum", html, fixed = TRUE))
})

testthat::test_that("destekUI 'hakkinda' sayfası için Hakkında başlığı ve alt-UI'yi verir", {
  env <- .source_destek_for_test()
  html <- .destek_html(env, "hakkinda")
  testthat::expect_true(grepl("Hakkında", html, fixed = TRUE))
  testthat::expect_true(grepl("stub-hakkinda", html, fixed = TRUE))
})

testthat::test_that("destekUI bilinmeyen sayfada 'Destek' başlığına düşer ve içerik gömmez", {
  env <- .source_destek_for_test()
  html <- .destek_html(env, "bilinmeyen_sayfa")
  testthat::expect_true(grepl("Destek", html, fixed = TRUE))
  # Hiçbir alt-UI stub'ı eşleşmemeli (switch varsayılanı içerik üretmez).
  testthat::expect_false(grepl("stub-yardim", html, fixed = TRUE))
  testthat::expect_false(grepl("stub-surum", html, fixed = TRUE))
})

testthat::test_that("destekUI varsayılan sayfa parametresi 'yardim'dir", {
  env <- .source_destek_for_test()
  html <- paste(as.character(env$destekUI("dst")), collapse = "\n")  # sayfa verilmedi
  testthat::expect_true(grepl("Yardım Merkezi", html, fixed = TRUE))
  testthat::expect_true(grepl("stub-yardim", html, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# destekServer: alt sunucuların başlatılması
# ------------------------------------------------------------------------------
testthat::test_that("destekServer dört alt sunucuyu da tam bir kez başlatır", {
  rec <- new.env()
  rec$yardim <- 0L; rec$geri <- 0L; rec$surum <- 0L; rec$hakkinda <- 0L
  env <- .source_destek_for_test(server_recorder = rec)

  shiny::testServer(env$destekServer, args = list(current_user_id = 5L), {
    session$flushReact()
  })

  testthat::expect_identical(rec$yardim, 1L)
  testthat::expect_identical(rec$geri, 1L)
  testthat::expect_identical(rec$surum, 1L)
  testthat::expect_identical(rec$hakkinda, 1L)
})

# ==============================================================================
# Dosya Yolu: tests/testthat/test-image-gallery-lazy-activation-behavior.R
# Açıklama: Görsel Galerisi'nin TEMBEL etkinleşme sözleşmesi: modül açılışta
#           (oturum başlarken) görsel taraması ve açıklama DB sorguları
#           ÇALIŞTIRMAZ; tarama ancak kullanıcı galeri sayfasını ilk açtığında
#           (refresh_gallery girdisi) yapılır. Auth-sonrası refreshable-module
#           tetikleri de etkinleşmeden önce güvenle atlanır.
#           Gerçek DB/dosya sistemi/tarayıcı GEREKMEZ; scan_user_images stub'lanır.
# ==============================================================================

testthat::local_edition(3)

if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

.lazy_gallery_env <- function(scan_recorder) {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  env$resolve_effective_user_id <- function(session, current_user_id) {
    if (is.function(current_user_id)) current_user_id() else current_user_id
  }
  env$showToast <- function(...) invisible(TRUE)
  env$scan_user_images <- function(uid) {
    scan_recorder$count <- scan_recorder$count + 1L
    data.frame(
      file_path = character(), chat_id = character(), filename = character(),
      created_at = as.POSIXct(character()), file_size = numeric(),
      month_key = character(), month_label = character(),
      description = character(), chat_title = character(),
      stringsAsFactors = FALSE
    )
  }
  kok <- resolve_repo_root_for_tests()
  source(file.path(kok, "R", "module_image_gallery.R"), encoding = "UTF-8", local = env)
  env
}

testthat::test_that("galeri açılışta taranmaz; ilk sayfa açılışında bir kez taranır", {
  testthat::skip_if_not_installed("shiny")

  scan_recorder <- new.env(parent = emptyenv())
  scan_recorder$count <- 0L
  env <- .lazy_gallery_env(scan_recorder)
  loop <- later::create_loop(parent = NULL)
  on.exit(later::destroy_loop(loop), add = TRUE)

  later::with_loop(loop, shiny::testServer(
    env$imageGalleryServer,
    args = list(id = "ig", current_user_id = function() 7L),
    {
      complete_scan <- function(expected) {
        for (i in seq_len(10L)) {
          later::run_now(timeoutSecs = 0.1, loop = loop)
          session$flushReact()
          if (scan_recorder$count >= expected) break
        }
      }

      # Oturum başlangıcı: init observer çalışır ama galeri etkin değil -> tarama YOK.
      session$flushReact()
      later::run_now(timeoutSecs = 0.1, loop = loop)
      testthat::expect_identical(scan_recorder$count, 0L)

      # Auth-sonrası refreshable-module tetiği (refresh() eşdeğeri): hâlâ tarama YOK.
      session$getReturned()$refresh()
      session$flushReact()
      later::run_now(timeoutSecs = 0.1, loop = loop)
      testthat::expect_identical(scan_recorder$count, 0L)

      # Kullanıcı galeri sayfasını açar (navigasyon zaman damgası gönderir).
      session$setInputs(refresh_gallery = as.numeric(Sys.time()))
      session$flushReact()
      complete_scan(1L)
      testthat::expect_identical(scan_recorder$count, 1L)

      # Sonraki sekme geçişi yeniden tarar (mevcut davranış) ama etkinleşme
      # bayrağı sayesinde önbellek karşılaştırması korunur; sayaç artışı
      # kontrollü kalır.
      session$setInputs(refresh_gallery = as.numeric(Sys.time()) + 5)
      session$flushReact()
      complete_scan(2L)
      testthat::expect_identical(scan_recorder$count, 2L)
    }
  ))
})

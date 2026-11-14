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
  # Sahip değişimi kancası (mergen_session_on_owner_change) fikstürde açıkça
  # yüklenir: test, önceki dosyaların globalenv'e bıraktığı yardımcılara
  # dayanmaz; tek başına çalıştırıldığında da aynı sonucu verir.
  source(file.path(kok, "R", "helpers_user_session_identity.R"), encoding = "UTF-8", local = env)
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

testthat::test_that("galeri sayfası açılınca tarama hatası kontrol noktasını kısmen bildirir", {
  testthat::skip_if_not_installed("shiny")

  scan_recorder <- new.env(parent = emptyenv())
  scan_recorder$count <- 0L
  env <- .lazy_gallery_env(scan_recorder)
  env$scan_user_images <- function(uid) {
    scan_recorder$count <- scan_recorder$count + 1L
    stop("görsel klasörü okunamadı (test)")
  }
  isaretler <- list()
  loop <- later::create_loop(parent = NULL)
  on.exit(later::destroy_loop(loop), add = TRUE)

  later::with_loop(loop, shiny::testServer(
    env$imageGalleryServer,
    args = list(id = "ig", current_user_id = function() 7L),
    {
      session$userData$mergen_yonetim_hazir <- function(key, label = key, detail = NULL, ...) {
        isaretler[[length(isaretler) + 1L]] <<- list(key = key, detail = detail)
      }
      session$flushReact()
      # Navigasyon gözlemcisiyle aynı: zaman damgası, kullanıcı tıklaması yok.
      session$setInputs(refresh_gallery = as.numeric(Sys.time()))
      for (i in seq_len(10L)) {
        later::run_now(timeoutSecs = 0.1, loop = loop)
        session$flushReact()
        if (length(isaretler)) break
      }
      testthat::expect_identical(scan_recorder$count, 1L)
      testthat::expect_length(isaretler, 1L)
      testthat::expect_identical(isaretler[[1]]$key, "gallery_index_ready")
      testthat::expect_true(isTRUE(isaretler[[1]]$detail$degraded),
                            info = "başarısız tarama açılışı bekletmemeli ama 'hazır' da sayılmamalı")
    }
  ))
})

testthat::test_that("oturum sahibi değişince önceki sahibin galeri satırları yeni sahibe gösterilmez", {
  testthat::skip_if_not_installed("shiny")

  scan_recorder <- new.env(parent = emptyenv())
  scan_recorder$count <- 0L
  env <- .lazy_gallery_env(scan_recorder)
  sahip <- new.env(parent = emptyenv())
  sahip$uid <- 7L
  env$scan_user_images <- function(uid) {
    scan_recorder$count <- scan_recorder$count + 1L
    if (!identical(uid, 7L)) stop("yeni sahibin klasörü okunamadı (test)")
    data.frame(
      file_path = "/gorseller/7/a.png", chat_id = "1", filename = "a.png",
      created_at = as.POSIXct("2026-07-01 10:00:00", tz = "UTC"), file_size = 10,
      month_key = "2026-07", month_label = "Temmuz 2026",
      description = "", chat_title = "Söyleşi", stringsAsFactors = FALSE
    )
  }
  loop <- later::create_loop(parent = NULL)
  on.exit(later::destroy_loop(loop), add = TRUE)

  later::with_loop(loop, shiny::testServer(
    env$imageGalleryServer,
    args = list(id = "ig", current_user_id = function() sahip$uid),
    {
      tara <- function(beklenen) {
        for (i in seq_len(20L)) {
          later::run_now(timeoutSecs = 0.1, loop = loop)
          session$flushReact()
          if (scan_recorder$count >= beklenen && !isTRUE(gallery_loading())) break
        }
      }
      session$flushReact()
      session$setInputs(refresh_gallery = as.numeric(Sys.time()))
      tara(1L)
      testthat::expect_identical(nrow(filtered_images()), 1L)

      # Aynı oturum B'ye geçti, henüz tarama yok: yeniden hesaplanan liste
      # A'nın satırlarını çizmez (oturum kapsamlı URL B'ye bağlanamaz).
      sahip$uid <- 9L
      gallery_revision(shiny::isolate(gallery_revision()) + 1)
      testthat::expect_identical(nrow(filtered_images()), 0L)

      # B için tarama başarısız olsa da A'nın satırları önbellekte kalmaz.
      session$setInputs(refresh_gallery = as.numeric(Sys.time()) + 5)
      tara(2L)
      testthat::expect_identical(scan_recorder$count, 2L)
      testthat::expect_identical(nrow(shiny::isolate(cached_images())), 0L)

      # Sahip değişimi kancası önbelleği hemen boşaltır.
      sahip$uid <- 7L
      session$setInputs(refresh_gallery = as.numeric(Sys.time()) + 10)
      tara(3L)
      testthat::expect_identical(nrow(shiny::isolate(cached_images())), 1L)
      kancalar <- as.list(session$userData$kimlik_kancalari, all.names = TRUE)
      testthat::expect_true(length(kancalar) >= 1L)
      for (fn in kancalar) fn("sahip_degisti")
      testthat::expect_identical(nrow(shiny::isolate(cached_images())), 0L)
    }
  ))
})

testthat::test_that("oturum kimliği galeri çizildikten sonra yayımlanınca kartlar yeniden çizilir ve URL yeni sahiple kaydedilir", {
  testthat::skip_if_not_installed("shiny")

  scan_recorder <- new.env(parent = emptyenv())
  scan_recorder$count <- 0L
  env <- .lazy_gallery_env(scan_recorder)
  env$scan_user_images <- function(uid) {
    scan_recorder$count <- scan_recorder$count + 1L
    data.frame(
      file_path = "/gorseller/7/a.png", chat_id = "1", filename = "a.png",
      created_at = as.POSIXct("2026-07-01 10:00:00", tz = "UTC"), file_size = 10,
      month_key = "2026-07", month_label = "Temmuz 2026",
      description = "", chat_title = "Söyleşi", stringsAsFactors = FALSE
    )
  }
  # URL kaydı, kayıt anındaki OTURUM kimliğine bağlanır (gerçek yardımcıdaki
  # .mergen_image_session_owner gibi); geri dönüş kimliği sahip sayılmaz.
  kayitlar <- character()
  env$mergen_serve_image_data_url <- function(local_path, session) {
    sahip <- suppressWarnings(as.integer(session$userData$user_id %||% NA_integer_))
    kayitlar <<- c(kayitlar, if (is.na(sahip) || sahip <= 0L) "NA" else as.character(sahip))
    paste0("session/test/dataobj/mergen_img_", length(kayitlar))
  }
  loop <- later::create_loop(parent = NULL)
  on.exit(later::destroy_loop(loop), add = TRUE)

  later::with_loop(loop, shiny::testServer(
    env$imageGalleryServer,
    args = list(id = "ig", current_user_id = function() 7L),
    {
      session$flushReact()
      session$setInputs(refresh_gallery = as.numeric(Sys.time()))
      for (i in seq_len(20L)) {
        later::run_now(timeoutSecs = 0.1, loop = loop)
        session$flushReact()
        if (scan_recorder$count >= 1L && !isTRUE(gallery_loading())) break
      }
      ilk <- output$gallery_content
      testthat::expect_true(grepl("mergen_img_", ilk$html, fixed = TRUE))
      # Oturum kimliği henüz yayımlanmadı: kayıt sahipsiz (sunucu 403 döner).
      testthat::expect_identical(utils::tail(kayitlar, 1L), "NA")

      # Kimlik yayımlanır (write_identity ile aynı geçiş: 0 -> 7, sinyal artar).
      session$userData$user_id <- 7L
      mergen_session_owner_transition(session$userData, 0L, 7L)
      session$flushReact()
      sonraki <- output$gallery_content
      testthat::expect_identical(utils::tail(kayitlar, 1L), "7")
      testthat::expect_false(identical(sonraki$html, ilk$html))
      # Yayımlama yeniden tarama gerektirmez; yalnızca kartlar yeniden kaydedilir.
      testthat::expect_identical(scan_recorder$count, 1L)
    }
  ))
})

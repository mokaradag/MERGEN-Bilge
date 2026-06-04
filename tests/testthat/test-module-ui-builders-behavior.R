# ==============================================================================
# Dosya Yolu: tests/testthat/test-module-ui-builders-behavior.R
# Açıklama: Şimdiye dek davranışsal testi olmayan Shiny modül UI üreticilerinin
#           (historyUI, savedChatsUI, imageGalleryUI, sttUI, chartLabUI,
#           destekHataBildirUI, settingsKisiselUI, healthUI) ad-uzayı (namespace)
#           kimliklerini, Türkçe etiketlerini ve erişilebilirlik sözleşmesini
#           doğrular. Ayrıca history_accessible_date_range_input erişilebilirlik
#           düzeltmesi ve health_source_optional sözleşmesi test edilir.
#           DB/LLM/tarayıcı/ağ GEREKMEZ; yalnızca UI iskeleti üretilir.
# ==============================================================================

# UI üreticileri shiny div/tagList/uiOutput'u niteliksiz çağırır; DTOutput DT'den.
suppressMessages(library(shiny))
suppressMessages(library(DT))

# Modülü izole bir env'e ek bağımlılıklarıyla birlikte yükler.
.ui_src <- function(module_file, deps = character(0)) {
  env <- new.env(parent = globalenv())
  for (d in deps) {
    source(file.path(resolve_repo_root_for_tests(), "R", d), encoding = "UTF-8", local = env)
  }
  source(file.path(resolve_repo_root_for_tests(), "R", module_file), encoding = "UTF-8", local = env)
  env
}

.ui_text <- function(ui) paste(as.character(ui), collapse = "\n")

testthat::test_that("historyUI ad-uzayı kimliklerini ve Türkçe başlığı üretir", {
  env <- .ui_src("module_chat_history.R")
  txt <- .ui_text(env$historyUI("h"))

  testthat::expect_true(grepl('id="h-refresh_history"', txt, fixed = TRUE))
  testthat::expect_true(grepl('id="h-date_range"', txt, fixed = TRUE))
  testthat::expect_true(grepl('id="h-export_history"', txt, fixed = TRUE))
  # DataTable çıktısı mevcut olmalı.
  testthat::expect_true(grepl("h-history_table", txt, fixed = TRUE))
})

testthat::test_that("history_accessible_date_range_input erişilebilirlik sözleşmesini korur", {
  env <- .ui_src("module_chat_history.R")
  txt <- .ui_text(env$history_accessible_date_range_input(NS("h")))

  # Chrome Issues düzeltmesi: label[for=wrapper] yerine aria-labelledby kullanılır.
  testthat::expect_true(grepl('aria-labelledby="h-date_range-label"', txt, fixed = TRUE))
  testthat::expect_true(grepl('id="h-date_range-label"', txt, fixed = TRUE))
  # Native tarih giriş alanları ve Türkçe etiket korunur.
  testthat::expect_true(grepl("Tarih Aralığı", txt, fixed = TRUE))
  testthat::expect_true(grepl("h-date_range_start", txt, fixed = TRUE))
  testthat::expect_true(grepl("h-date_range_end", txt, fixed = TRUE))
})

testthat::test_that("savedChatsUI yenile/temizle/arama kimliklerini üretir", {
  env <- .ui_src("module_saved_chats.R")
  txt <- .ui_text(env$savedChatsUI("s"))

  testthat::expect_true(grepl('id="s-refresh_saved_chats"', txt, fixed = TRUE))
  testthat::expect_true(grepl('id="s-clear_all_chats"', txt, fixed = TRUE))
  testthat::expect_true(grepl('id="s-search_chats"', txt, fixed = TRUE))
})

testthat::test_that("imageGalleryUI galeri yenile/temizle/arama kimliklerini üretir", {
  env <- .ui_src("module_image_gallery.R")
  txt <- .ui_text(env$imageGalleryUI("g"))

  testthat::expect_true(grepl('id="g-refresh_gallery"', txt, fixed = TRUE))
  testthat::expect_true(grepl('id="g-clear_all_images"', txt, fixed = TRUE))
  testthat::expect_true(grepl('id="g-search_images"', txt, fixed = TRUE))
})

testthat::test_that("sttUI modal kapsayıcı uiOutput'u üretir", {
  env <- .ui_src("module_stt.R")
  txt <- .ui_text(env$sttUI("t"))

  testthat::expect_true(grepl("t-stt_modal_container", txt, fixed = TRUE))
})

testthat::test_that("chartLabUI grafik kapsayıcısını üretir", {
  env <- .ui_src("module_chartlab.R")
  txt <- .ui_text(env$chartLabUI("c"))

  testthat::expect_true(grepl('id="c-charts_container"', txt, fixed = TRUE))
})

testthat::test_that("destekHataBildirUI hata bildirim form kimliklerini üretir", {
  env <- .ui_src("module_destek_hata_bildir.R")
  txt <- .ui_text(env$destekHataBildirUI("d"))

  testthat::expect_true(grepl('id="d-konular_container"', txt, fixed = TRUE))
  testthat::expect_true(grepl('id="d-konu_ekle_btn"', txt, fixed = TRUE))
  testthat::expect_true(grepl('id="d-kategori_container"', txt, fixed = TRUE))
})

testthat::test_that("settingsKisiselUI kişiselleştirme kimlikleri ve karakter video alanını içerir", {
  env <- .ui_src("module_settings_kisisel.R", deps = c("module_character_video.R"))
  txt <- .ui_text(env$settingsKisiselUI("k"))

  testthat::expect_true(grepl('id="k-save_settings"', txt, fixed = TRUE))
  testthat::expect_true(grepl('id="k-character_buttons"', txt, fixed = TRUE))
  # Karakter video modülü gömülü olmalı.
  testthat::expect_true(grepl("k-character_video-video_container", txt, fixed = TRUE))
})

testthat::test_that("healthUI sağlık paneli kimliklerini ve sekme yapısını üretir", {
  env <- .ui_src("module_health.R", deps = c("helpers_admin_analytics.R"))
  txt <- .ui_text(env$healthUI("hl"))

  testthat::expect_true(grepl('id="hl-refresh_health"', txt, fixed = TRUE))
  testthat::expect_true(grepl("hl-health_tabs", txt, fixed = TRUE))
  testthat::expect_true(grepl("hl-last_update_time", txt, fixed = TRUE))
})

testthat::test_that("health_source_optional eksik dosyada FALSE, var olan dosyada TRUE döner", {
  env <- .ui_src("module_health.R", deps = c("helpers_admin_analytics.R"))

  # Eksik dosya: yan etki olmadan FALSE.
  testthat::expect_false(env$health_source_optional(file.path(tempdir(), "yok_boyle_bir_dosya_12345.R")))

  # Var olan dosya: kaynaklanır ve TRUE döner.
  tmp <- tempfile(fileext = ".R")
  marker <- paste0(".health_src_marker_", as.integer(runif(1, 1, 1e6)))
  writeLines(sprintf("%s <- 42L", marker), tmp)
  on.exit({
    if (exists(marker, envir = globalenv(), inherits = FALSE)) {
      rm(list = marker, envir = globalenv())
    }
    unlink(tmp)
  }, add = TRUE)

  testthat::expect_true(env$health_source_optional(tmp))
  testthat::expect_true(exists(marker, inherits = TRUE))
})

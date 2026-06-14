# ==============================================================================
# Dosya Yolu: tests/testthat/test-admin-ha-show-modal-behavior.R
# Açıklama: helpers_admin_hata_detail_runtime.R içindeki admin_ha_show_modal
#           davranışını doğrular. Bu yardımcı, namespace'lenmiş modalı body'ye
#           taşıyıp gösteren JS'i shinyjs::runjs ile üretir. shinyjs::runjs
#           mock'lanır; gerçek tarayıcı/JS yoktur. Üretilen JS'in ns'lenmiş id'yi,
#           body'ye taşıma + tekrar-taşıma koruması ve modal göster çağrısını
#           içerdiği doğrulanır. Çevrimdışı ve deterministik.
# ==============================================================================

# Türkçe yorum: detay runtime yardımcılarını yalıtılmış ortama yükler.
.adminHaModalEnv <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  source(file.path(kok, "R", "helpers_admin_hata_detail_runtime.R"), encoding = "UTF-8", local = env)
  env
}

test_that("admin_ha_show_modal ns'lenmiş modal id ile göster JS'i üretir", {
  env <- .adminHaModalEnv()
  yakalanan <- new.env(parent = emptyenv())
  testthat::local_mocked_bindings(
    runjs = function(code) { yakalanan$code <- code; invisible(NULL) },
    .package = "shinyjs"
  )
  env$admin_ha_show_modal(ns = function(x) paste0("ns-", x), modal_id = "ek_dosya_modal")

  js <- yakalanan$code
  expect_true(is.character(js) && nzchar(js))
  # Türkçe yorum: ns ile genişletilmiş id JS içinde geçmeli
  expect_true(grepl("#ns-ek_dosya_modal", js, fixed = TRUE))
  # Türkçe yorum: body'ye taşıma + tekrar taşımayı önleyen işaret
  expect_true(grepl("appendTo('body')", js, fixed = TRUE))
  expect_true(grepl("moved-to-body", js, fixed = TRUE))
  # Türkçe yorum: bootstrap modal göster çağrısı
  expect_true(grepl("modal('show')", js, fixed = TRUE))
})

test_that("admin_ha_show_modal farklı modal id'sini doğru genişletir", {
  env <- .adminHaModalEnv()
  yakalanan <- new.env(parent = emptyenv())
  testthat::local_mocked_bindings(
    runjs = function(code) { yakalanan$code <- code; invisible(NULL) },
    .package = "shinyjs"
  )
  env$admin_ha_show_modal(ns = function(x) paste0("admin-", x), modal_id = "durum_modal")
  expect_true(grepl("#admin-durum_modal", yakalanan$code, fixed = TRUE))
})

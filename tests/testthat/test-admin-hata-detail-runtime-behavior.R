# ==============================================================================
# Dosya Yolu: tests/testthat/test-admin-hata-detail-runtime-behavior.R
# Açıklama: R/helpers_admin_hata_detail_runtime.R ek dosya/DT inşa yardımcılarının
#           davranışsal testleri. Public yol türetme, indirme butonu, dosya türüne
#           göre önizleme (görsel/video/diğer) ve detay DT tablosu doğrulanır.
# ==============================================================================

testthat::local_edition(3)

if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

.dhr_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "helpers_admin_hata_detail_runtime.R"),
  encoding = "UTF-8", local = .dhr_env
)
.dhr_env$admin_turkish_dt_language <- list(emptyTable = "Kayıt yok")
.dhr_env$admin_dt_header_callback <- htmlwidgets::JS("function(thead) {}")

.dhr_html <- function(ui) paste(as.character(ui), collapse = "")

# -----------------------------------------------------------------------------
# admin_ha_attachment_public_path
# -----------------------------------------------------------------------------

test_that("admin_ha_attachment_public_path destek_uploads önekini akıllı uygular", {
  expect_identical(.dhr_env$admin_ha_attachment_public_path("destek_uploads/x.png"), "/destek_uploads/x.png")
  expect_identical(.dhr_env$admin_ha_attachment_public_path("abc.png"), "/destek_uploads/abc.png")
})

# -----------------------------------------------------------------------------
# admin_ha_attachment_download_button
# -----------------------------------------------------------------------------

test_that("admin_ha_attachment_download_button href, download ve dosya adı içeren bağlantı üretir", {
  skip_if_not_installed("shiny")
  btn <- .dhr_html(.dhr_env$admin_ha_attachment_download_button("/destek_uploads/x.png", "x.png"))
  expect_true(grepl('href="/destek_uploads/x.png"', btn, fixed = TRUE))
  expect_true(grepl('download="x.png"', btn, fixed = TRUE))
  expect_true(grepl("fa-download", btn, fixed = TRUE))
  expect_true(grepl("x.png", btn, fixed = TRUE))
})

# -----------------------------------------------------------------------------
# admin_ha_attachment_item (dosya türüne göre önizleme)
# -----------------------------------------------------------------------------

test_that("admin_ha_attachment_item görsel uzantıda img + zoom kapsayıcı üretir", {
  skip_if_not_installed("shiny")
  html <- .dhr_html(.dhr_env$admin_ha_attachment_item("destek_uploads/foto.png"))
  expect_true(grepl("<img", html, fixed = TRUE))
  expect_true(grepl("admin-attachment-zoom-container", html, fixed = TRUE))
})

test_that("admin_ha_attachment_item mp4 uzantıda video etiketi üretir", {
  skip_if_not_installed("shiny")
  html <- .dhr_html(.dhr_env$admin_ha_attachment_item("destek_uploads/film.mp4"))
  expect_true(grepl("<video", html, fixed = TRUE))
  expect_false(grepl("<img", html, fixed = TRUE))
})

test_that("admin_ha_attachment_item önizlenemeyen türde uyarı metni gösterir", {
  skip_if_not_installed("shiny")
  html <- .dhr_html(.dhr_env$admin_ha_attachment_item("destek_uploads/belge.pdf"))
  expect_true(grepl("önizlenemez", html, fixed = TRUE))
  expect_false(grepl("<img", html, fixed = TRUE))
})

# -----------------------------------------------------------------------------
# admin_ha_attachment_content
# -----------------------------------------------------------------------------

test_that("admin_ha_attachment_content birden çok dosya için tüm önizlemeleri birleştirir", {
  skip_if_not_installed("shiny")
  html <- .dhr_html(.dhr_env$admin_ha_attachment_content(
    c("destek_uploads/a.png", "destek_uploads/b.mp4")
  ))
  expect_true(grepl("<img", html, fixed = TRUE))
  expect_true(grepl("<video", html, fixed = TRUE))
})

# -----------------------------------------------------------------------------
# admin_ha_detail_datatable
# -----------------------------------------------------------------------------

test_that("admin_ha_detail_datatable boş/NULL veride boş tablo döner", {
  skip_if_not_installed("DT")
  expect_error(.dhr_env$admin_ha_detail_datatable(NULL), NA)
  expect_error(.dhr_env$admin_ha_detail_datatable(data.frame()), NA)
})

test_that("admin_ha_detail_datatable veriyle admin-datatable sınıflı DT üretir", {
  skip_if_not_installed("DT")
  html <- .dhr_html(.dhr_env$admin_ha_detail_datatable(
    data.frame(A = 1, B = "x", stringsAsFactors = FALSE)
  ))
  expect_true(grepl("admin-datatable", html, fixed = TRUE))
})

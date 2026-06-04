# ==============================================================================
# Dosya Yolu: tests/testthat/test-admin-hata-helpers-ui-behavior.R
# Açıklama: R/helpers_admin_hata_analizi.R sekme UI inşacılarının davranış
#           testleri (admin_ha_overview_ui, admin_ha_oncelik_ui, admin_ha_detay_ui,
#           admin_ha_zaman_ui). Bu inşacılar daha önce doğrudan test edilmiyordu.
#           Gerçek DB/tarayıcı GEREKMEZ; ns sahte, admin_create_info_button stub.
# ==============================================================================

testthat::local_edition(3)
if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

.source_admin_ha_helpers <- function() {
  env <- new.env(parent = globalenv())
  env$admin_create_info_button <- function(...) shiny::span(class = "info-btn-stub")
  # Metric kartı stub'ı: başlık + (UTF-8 olası) değeri görünür HTML'e basar ki
  # overview testleri hesaplanan sayıları doğrulayabilsin.
  env$admin_create_metric_card <- function(title, value, icon = NULL, color = NULL, tooltip = NULL) {
    shiny::div(class = "metric-card-stub", shiny::span(title), shiny::span(as.character(value)))
  }
  env$admin_format_number <- function(x) as.character(x)
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_admin_hata_analizi.R"),
    encoding = "UTF-8", local = env
  )
  env
}

.ns <- function(x) paste0("hata-", x)

.html_of <- function(ui) paste(as.character(ui), collapse = "\n")

.overview_data <- function() {
  list(
    toplam = data.frame(cnt = 42L),
    bugun = data.frame(cnt = 3L),
    bu_hafta = data.frame(cnt = 9L),
    ekli_bildirim = data.frame(cnt = 5L),
    durum_dagilim = data.frame(
      Durum = c("acik", "cozuldu", "kapandi"),
      cnt = c(10L, 7L, 4L),
      stringsAsFactors = FALSE
    ),
    oncelik_dagilim = data.frame(
      Oncelik = c("kritik", "yuksek"),
      cnt = c(6L, 8L),
      stringsAsFactors = FALSE
    )
  )
}

testthat::test_that("admin_ha_overview_ui toplam/bugün/hafta sayılarını HTML'e basar", {
  env <- .source_admin_ha_helpers()
  ui <- env$admin_ha_overview_ui(.ns, .overview_data())
  html <- .html_of(ui)
  testthat::expect_true(grepl("42", html, fixed = TRUE))   # toplam
  testthat::expect_true(grepl("3", html, fixed = TRUE))    # bugün
  testthat::expect_true(grepl("9", html, fixed = TRUE))    # bu hafta
})

testthat::test_that("admin_ha_overview_ui durum/öncelik özetlerini hesaplar (açık/çözüldü/kritik)", {
  env <- .source_admin_ha_helpers()
  ui <- env$admin_ha_overview_ui(.ns, .overview_data())
  html <- .html_of(ui)
  # cozuldu(7) + kapandi(4) = 11 çözülen
  testthat::expect_true(grepl("11", html, fixed = TRUE))
  # kritik = 6
  testthat::expect_true(grepl(">6<|[^0-9]6[^0-9]", html))
})

testthat::test_that("admin_ha_overview_ui boş veride çökmiyor ve sıfırları gösteriyor", {
  env <- .source_admin_ha_helpers()
  bos <- list(
    toplam = data.frame(cnt = integer(0)),
    bugun = data.frame(cnt = integer(0)),
    bu_hafta = data.frame(cnt = integer(0)),
    ekli_bildirim = data.frame(cnt = integer(0)),
    durum_dagilim = data.frame(Durum = character(0), cnt = integer(0)),
    oncelik_dagilim = data.frame(Oncelik = character(0), cnt = integer(0))
  )
  ui <- env$admin_ha_overview_ui(.ns, bos)
  html <- .html_of(ui)
  testthat::expect_true(nzchar(html))
  testthat::expect_true(grepl("0", html, fixed = TRUE))
})

testthat::test_that("admin_ha_oncelik_ui grafik çıktı id'lerini ve Türkçe başlığı içerir", {
  env <- .source_admin_ha_helpers()
  html <- .html_of(env$admin_ha_oncelik_ui(.ns))
  testthat::expect_true(grepl("hata-ha_oncelik_chart", html, fixed = TRUE))
  testthat::expect_true(grepl("Öncelik Dağılımı", html, fixed = TRUE))
})

testthat::test_that("admin_ha_detay_ui DT tablo çıktısını ve başlığı içerir", {
  env <- .source_admin_ha_helpers()
  html <- .html_of(env$admin_ha_detay_ui(.ns))
  testthat::expect_true(grepl("hata-ha_detay_tablo", html, fixed = TRUE))
  testthat::expect_true(grepl("Tüm Hata Bildirimleri", html, fixed = TRUE))
})

testthat::test_that("admin_ha_zaman_ui haftalık trend grafiğini içerir", {
  env <- .source_admin_ha_helpers()
  html <- .html_of(env$admin_ha_zaman_ui(.ns))
  testthat::expect_true(grepl("hata-ha_haftalik_trend_chart", html, fixed = TRUE))
  testthat::expect_true(grepl("Haftalık Hata Bildirim Trendi", html, fixed = TRUE))
})

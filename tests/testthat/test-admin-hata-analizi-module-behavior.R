# ==============================================================================
# Dosya Yolu: tests/testthat/test-admin-hata-analizi-module-behavior.R
# Açıklama: R/module_admin_hata_analizi.R Hata Analizi modülünün davranışsal
#           testleri. UI sekme yapısı ile highcharter render fonksiyonlarındaki
#           durum/öncelik etiket+renk eşlemesi ve boş-veri koruması doğrulanır.
#           Gerçek DB/tarayıcı yoktur; tüm admin yardımcıları stub'lanır.
# ==============================================================================

testthat::local_edition(3)

if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

.admin_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "module_admin_hata_analizi.R"),
  encoding = "UTF-8",
  local = .admin_env
)

# Modülün bare kullandığı %>% ve JS yardımcılarını ortama getir.
.admin_env[["%>%"]] <- magrittr::`%>%`
.admin_env$JS <- htmlwidgets::JS

# --- Admin yardımcı stub'ları (DB/Shiny coupling olmadan) ---
.admin_env$admin_refresh_setup <- function(input, session) list(trigger = function() invisible(NULL))
.admin_env$admin_init_tooltips <- function(session) invisible(NULL)
.admin_env$admin_format_turkish_date <- function(x) as.character(x)
.admin_env$admin_ha_category_labels <- function() c(arayuz = "Arayüz / Tasarım", cokme = "Çökme / Hata")
.admin_env$admin_ha_priority_labels <- function() {
  c(dusuk = "Düşük", orta = "Orta", yuksek = "Yüksek", kritik = "Kritik", belirtilmedi = "Belirtilmedi")
}
.admin_env$admin_ha_status_labels <- function() {
  c(acik = "Açık", inceleme = "İncelemede", cozuldu = "Çözüldü", kapandi = "Kapandı", reddedildi = "Reddedildi")
}
.admin_env$admin_ha_count_categories <- function(ham, kategori_cevirisi) {
  data.frame(kategori_tr = c("Arayüz / Tasarım", "Çökme / Hata"), cnt = c(2, 1), stringsAsFactors = FALSE)
}
.admin_env$admin_ha_tab_ui <- function(tab, ns, data_provider) {
  shiny::div(class = "ha-stub-tab", paste0("tab:", tab))
}
.admin_env$admin_ha_prepare_heatmap_data <- function(data, kategori_cevirisi, oncelik_cevirisi) {
  list(
    kategoriler = c("Arayüz / Tasarım", "Çökme / Hata"),
    oncelikler = c("Düşük", "Kritik"),
    heatmap_data = list(list(0, 0, 1), list(1, 1, 3))
  )
}
.admin_env$admin_ha_register_detail_runtime <- function(...) invisible(NULL)
.admin_env$admin_turkish_dt_language <- list(emptyTable = "Kayıt yok")
.admin_env$admin_dt_header_callback <- htmlwidgets::JS("function(thead, data, start, end, display) {}")

# Dolu örnek veri seti (tüm grafiklerin gerçek veri yolunu çalıştırır).
.ha_full <- function() {
  list(
    gunluk_trend = data.frame(tarih = c("2026-01-01", "2026-01-02"), cnt = c(3, 5), stringsAsFactors = FALSE),
    durum_dagilim = data.frame(Durum = c("acik", "cozuldu", "xyz"), cnt = c(5, 3, 1), stringsAsFactors = FALSE),
    oncelik_dagilim = data.frame(Oncelik = c("dusuk", "kritik"), cnt = c(2, 4), stringsAsFactors = FALSE),
    oncelik_kategori = data.frame(Oncelik = c("dusuk", "kritik"), Kategori = c("arayuz", "cokme"),
                                  cnt = c(1, 3), stringsAsFactors = FALSE),
    oncelik_trend = data.frame(tarih = c("2026-01-01", "2026-01-02"),
                               Oncelik = c("dusuk", "kritik"), cnt = c(2, 4), stringsAsFactors = FALSE),
    haftalik_trend = data.frame(yil = c(2026, 2026), hafta = c(1, 2),
                                hafta_basi = c("2026-01-01", "2026-01-08"), cnt = c(4, 6), stringsAsFactors = FALSE),
    saatlik_dagilim = data.frame(saat = c(0, 1, 2), cnt = c(1, 2, 3)),
    kullanici_bildirim = data.frame(
      KullaniciAdi = c("ali", "veli"), bildirim_sayisi = c(3, 5), kritik_sayisi = c(1, 2),
      son_bildirim = c("2026-01-01 10:00:00", "2026-01-02 11:00:00"), stringsAsFactors = FALSE
    ),
    kategoriler_ham = c("arayuz", "cokme", "arayuz")
  )
}

# Boş veri seti (her grafik için nrow == 0 koruma dalını tetikler).
.ha_empty <- function() {
  bos <- data.frame()
  list(
    gunluk_trend = bos, durum_dagilim = bos, oncelik_dagilim = bos, oncelik_kategori = bos,
    oncelik_trend = bos, haftalik_trend = bos, saatlik_dagilim = bos, kullanici_bildirim = bos,
    kategoriler_ham = character(0)
  )
}

# highchart çıktısını JSON ayrıştırarak ilk serinin nokta listesini döndürür.
.seri_noktalari <- function(output_value) {
  parsed <- jsonlite::fromJSON(as.character(output_value), simplifyVector = FALSE)
  parsed$x$hc_opts$series[[1]]$data
}

# -----------------------------------------------------------------------------
# UI
# -----------------------------------------------------------------------------

test_that("adminHataAnaliziUI sayfa başlığını, ikonunu ve dört sekmeyi doğru değerlerle üretir", {
  skip_if_not_installed("shiny")

  withr::defer(.admin_env$admin_page_layout <- .apl_orig)
  .apl_orig <- if (exists("admin_page_layout", envir = .admin_env, inherits = FALSE)) {
    .admin_env$admin_page_layout
  } else NULL

  # admin_page_layout'u argümanları görünür kılacak biçimde stub'la.
  .admin_env$admin_page_layout <- function(ns, page_title, page_icon, tab_panels) {
    shiny::tagList(
      shiny::h1(page_title),
      shiny::tags$div(`data-page-icon` = page_icon),
      tab_panels
    )
  }

  html <- paste(as.character(.admin_env$adminHataAnaliziUI("ha")), collapse = "\n")

  expect_true(grepl("Hata Analizi", html, fixed = TRUE))
  expect_true(grepl("data-page-icon=\"bug\"", html, fixed = TRUE))

  # Sekme değerleri (data-value).
  expect_true(grepl("ha_overview", html, fixed = TRUE))
  expect_true(grepl("ha_oncelik", html, fixed = TRUE))
  expect_true(grepl("ha_detay", html, fixed = TRUE))
  expect_true(grepl("ha_zaman", html, fixed = TRUE))

  # Sekme Türkçe başlıkları (& içerenler kaçışlandığı için tek kelime aranır).
  expect_true(grepl("Genel Bakış", html, fixed = TRUE))
  expect_true(grepl("Detaylı Bildirimler", html, fixed = TRUE))
  expect_true(grepl("Zaman Analizi", html, fixed = TRUE))
  expect_true(grepl("Öncelik", html, fixed = TRUE))
})

# -----------------------------------------------------------------------------
# Server: durum/öncelik etiket + renk eşlemesi
# -----------------------------------------------------------------------------

test_that("durum pasta grafiği durum kodlarını Türkçe etikete ve renge çevirir, bilinmeyeni korur", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  withr::defer(.admin_env$admin_ha_fetch_data <- .fd_orig)
  .fd_orig <- if (exists("admin_ha_fetch_data", envir = .admin_env, inherits = FALSE)) .admin_env$admin_ha_fetch_data else NULL
  .admin_env$admin_ha_fetch_data <- .ha_full

  shiny::testServer(.admin_env$adminHataAnaliziServer, args = list(id = "ha"), {
    noktalar <- .seri_noktalari(output$ha_durum_pie_chart)
    isimler <- vapply(noktalar, function(p) p$name, character(1))
    renkler <- vapply(noktalar, function(p) p$color, character(1))

    # acik -> Açık, cozuldu -> Çözüldü çevrilmeli; xyz bilinmeyen olarak korunmalı.
    expect_true("Açık" %in% isimler)
    expect_true("Çözüldü" %in% isimler)
    expect_true("xyz" %in% isimler)
    # Renk eşlemesi: acik=#f59e0b, cozuldu=#10b981, bilinmeyen=#94a3b8.
    expect_true("#f59e0b" %in% renkler)
    expect_true("#10b981" %in% renkler)
    expect_true("#94a3b8" %in% renkler)
  })
})

test_that("öncelik pasta grafiği öncelik kodlarını Türkçe etikete ve renge çevirir", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  withr::defer(.admin_env$admin_ha_fetch_data <- .fd_orig)
  .fd_orig <- if (exists("admin_ha_fetch_data", envir = .admin_env, inherits = FALSE)) .admin_env$admin_ha_fetch_data else NULL
  .admin_env$admin_ha_fetch_data <- .ha_full

  shiny::testServer(.admin_env$adminHataAnaliziServer, args = list(id = "ha"), {
    noktalar <- .seri_noktalari(output$ha_oncelik_chart)
    isimler <- vapply(noktalar, function(p) p$name, character(1))
    renkler <- vapply(noktalar, function(p) p$color, character(1))

    expect_true("Düşük" %in% isimler)
    expect_true("Kritik" %in% isimler)
    expect_true("#3b82f6" %in% renkler)  # dusuk
    expect_true("#ef4444" %in% renkler)  # kritik
  })
})

# -----------------------------------------------------------------------------
# Server: tüm grafikler dolu veriyle hatasız render edilir
# -----------------------------------------------------------------------------

test_that("dolu veri ile tüm Hata Analizi grafikleri ve kullanıcı tablosu hatasız render edilir", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")
  skip_if_not_installed("DT")

  withr::defer(.admin_env$admin_ha_fetch_data <- .fd_orig)
  .fd_orig <- if (exists("admin_ha_fetch_data", envir = .admin_env, inherits = FALSE)) .admin_env$admin_ha_fetch_data else NULL
  .admin_env$admin_ha_fetch_data <- .ha_full

  shiny::testServer(.admin_env$adminHataAnaliziServer, args = list(id = "ha"), {
    expect_error(force(output$ha_gunluk_trend_chart), NA)
    expect_error(force(output$ha_kategori_treemap_chart), NA)
    expect_error(force(output$ha_heatmap_chart), NA)
    expect_error(force(output$ha_oncelik_trend_chart), NA)
    expect_error(force(output$ha_haftalik_trend_chart), NA)
    expect_error(force(output$ha_saatlik_chart), NA)
    expect_error(force(output$ha_kullanici_tablo), NA)
  })
})

# -----------------------------------------------------------------------------
# Server: boş veri koruması
# -----------------------------------------------------------------------------

test_that("boş veri tüm grafiklerde nrow==0 korumasını tetikler ve hata vermez", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  withr::defer(.admin_env$admin_ha_fetch_data <- .fd_orig)
  withr::defer(.admin_env$admin_ha_count_categories <- .cc_orig)
  .fd_orig <- .admin_env$admin_ha_fetch_data
  .cc_orig <- .admin_env$admin_ha_count_categories
  .admin_env$admin_ha_fetch_data <- .ha_empty
  .admin_env$admin_ha_count_categories <- function(ham, kategori_cevirisi) data.frame()

  shiny::testServer(.admin_env$adminHataAnaliziServer, args = list(id = "ha"), {
    expect_error(force(output$ha_durum_pie_chart), NA)
    expect_error(force(output$ha_oncelik_chart), NA)
    expect_error(force(output$ha_gunluk_trend_chart), NA)
    expect_error(force(output$ha_kategori_treemap_chart), NA)
    expect_error(force(output$ha_heatmap_chart), NA)
    expect_error(force(output$ha_saatlik_chart), NA)
  })
})

# -----------------------------------------------------------------------------
# Server: sekme içerik yönlendirici
# -----------------------------------------------------------------------------

test_that("tab_content_area seçili sekme için admin_ha_tab_ui çıktısını üretir", {
  skip_if_not_installed("shiny")

  withr::defer(.admin_env$admin_ha_fetch_data <- .fd_orig)
  .fd_orig <- .admin_env$admin_ha_fetch_data
  .admin_env$admin_ha_fetch_data <- .ha_full

  shiny::testServer(.admin_env$adminHataAnaliziServer, args = list(id = "ha"), {
    # input$admin_tabs NULL -> varsayılan ha_overview kullanılmalı.
    html0 <- paste(as.character(output$tab_content_area), collapse = "")
    expect_true(grepl("tab:ha_overview", html0, fixed = TRUE))

    session$setInputs(admin_tabs = "ha_zaman")
    html1 <- paste(as.character(output$tab_content_area), collapse = "")
    expect_true(grepl("tab:ha_zaman", html1, fixed = TRUE))
  })
})

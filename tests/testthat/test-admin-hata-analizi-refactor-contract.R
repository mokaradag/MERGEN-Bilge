# ==============================================================================
# Dosya Yolu: tests/testthat/test-admin-hata-analizi-refactor-contract.R
# Açıklama: Hata Analizi modülü helper extraction sözleşmesini doğrular.
# ==============================================================================

.source_admin_hata_helper_for_test <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())

  # Bu test helper dosyasını izole environment içinde source eder.
  # Runtime'da bu fonksiyonlar global.R üzerinden admin ortak helperlarından gelir;
  # testte ise UI router sözleşmesini DB/ana admin bağımlılıklarından bağımsız
  # doğrulamak için küçük stub'lar sağlanır.
  env$admin_format_number <- function(x) {
    as.character(x)
  }

  env$admin_create_metric_card <- function(title, value, icon_name, color, tooltip = NULL) {
    shiny::div(
      class = paste("metric-card", color),
      title = tooltip %||% "",
      shiny::span(class = "metric-title", title),
      shiny::span(class = "metric-value", value),
      shiny::span(class = "metric-icon", icon_name)
    )
  }

  env$admin_create_info_button <- function(text) {
    shiny::span(
      class = "admin-info-button",
      title = text,
      "i"
    )
  }

  source(
    file.path(repo_root, "R", "helpers_admin_hata_analizi.R"),
    encoding = "UTF-8",
    local = env
  )

  source(
    file.path(repo_root, "R", "helpers_admin_hata_heatmap_data.R"),
    encoding = "UTF-8",
    local = env
  )

  source(
    file.path(repo_root, "R", "helpers_admin_hata_detail_runtime.R"),
    encoding = "UTF-8",
    local = env
  )

  env
}

test_that("admin hata kategori sayımı Türkçe etiketleri ve boş girdileri korur", {
  env <- .source_admin_hata_helper_for_test()

  ham <- data.frame(
    Kategoriler = c(
      "arayuz, performans",
      "cokme",
      "arayuz, diger",
      "",
      NA_character_
    ),
    stringsAsFactors = FALSE
  )

  out <- env$admin_ha_count_categories(ham)

  expect_true(is.data.frame(out))
  expect_true(all(c("kategori", "cnt", "kategori_tr") %in% names(out)))

  counts <- setNames(out$cnt, out$kategori)

  expect_equal(counts[["arayuz"]], 2L)
  expect_equal(counts[["performans"]], 1L)
  expect_equal(counts[["cokme"]], 1L)
  expect_equal(counts[["diger"]], 1L)

  expect_equal(
    out$kategori_tr[out$kategori == "arayuz"],
    "Arayüz / Tasarım"
  )

  expect_equal(
    out$kategori_tr[out$kategori == "cokme"],
    "Çökme / Hata"
  )
})

test_that("admin hata heatmap helper kategori ve öncelik matrisini korur", {
  env <- .source_admin_hata_helper_for_test()

  data <- data.frame(
    Oncelik = c("kritik", "dusuk", "kritik"),
    Kategoriler = c("arayuz, performans", "cokme", "arayuz"),
    cnt = c(2L, 1L, 3L),
    stringsAsFactors = FALSE
  )

  out <- env$admin_ha_prepare_heatmap_data(
    data = data,
    kategori_cevirisi = env$admin_ha_category_labels(),
    oncelik_cevirisi = env$admin_ha_priority_labels()
  )

  expect_equal(out$kategoriler, c("Arayüz / Tasarım", "Çökme / Hata"))
  expect_equal(out$oncelikler, c("Düşük", "Kritik"))
  expect_equal(
    out$heatmap_data,
    list(
      list(0, 0, 0),
      list(0, 1, 5L),
      list(1, 0, 1L),
      list(1, 1, 0)
    )
  )
})

test_that("admin hata detay tablo helperı isim alanı, Türkçe etiket ve aksiyon HTML sözleşmesini korur", {
  testthat::skip_if_not_installed("shiny")

  env <- .source_admin_hata_helper_for_test()
  ns <- shiny::NS("admin_hata_test")

  detail_data <- data.frame(
    HataBildirimID = 42L,
    KullaniciAdi = "Ayşe Yılmaz",
    Konular = "Giriş sorunu",
    Kategoriler = "arayuz, cokme",
    Oncelik = "kritik",
    Durum = "acik",
    Aciklama = paste(rep("A", 120), collapse = ""),
    EkDosyaYollari = "destek_uploads/ekran.png,rapor.pdf",
    OlusturmaTarihi = as.POSIXct("2026-05-22 10:30:00", tz = "UTC"),
    stringsAsFactors = FALSE
  )

  out <- env$admin_ha_prepare_detail_table_data(
    data = detail_data,
    ns = ns,
    kategori_cevirisi = env$admin_ha_category_labels(),
    oncelik_cevirisi = env$admin_ha_priority_labels(),
    durum_cevirisi = env$admin_ha_status_labels()
  )

  expect_equal(
    names(out),
    c("#", "Kullanıcı", "Konular", "Kategori", "Öncelik", "Durum",
      "Açıklama", "Dosyalar", "İşlem", "Tarih", "tarih_sort")
  )

  expect_equal(out$Kullanıcı[1], "Ayşe Yılmaz")
  expect_true(grepl("Arayüz / Tasarım", out$Kategori[1], fixed = TRUE))
  expect_true(grepl("Çökme / Hata", out$Kategori[1], fixed = TRUE))
  expect_true(grepl("Kritik", out$Öncelik[1], fixed = TRUE))
  expect_true(grepl("Açık", out$Durum[1], fixed = TRUE))
  expect_true(grepl("admin_hata_test-dosya_goster", out$Dosyalar[1], fixed = TRUE))
  expect_true(grepl("admin_hata_test-durum_guncelle", out$İşlem[1], fixed = TRUE))
  expect_true(nchar(out$Açıklama[1]) <= 103L)
})

test_that("admin hata ek dosya helperı destek_uploads yolunu ve indirme kartını korur", {
  testthat::skip_if_not_installed("shiny")

  env <- .source_admin_hata_helper_for_test()

  item <- env$admin_ha_attachment_item("destek_uploads/ekran.png")
  html <- paste(as.character(item), collapse = "")

  expect_true(grepl("admin-attachment-item", html, fixed = TRUE))
  expect_true(grepl("src=\"/destek_uploads/ekran.png\"", html, fixed = TRUE))
  expect_true(grepl("download=\"ekran.png\"", html, fixed = TRUE))
})

test_that("admin hata veri sorgu helperı beklenen sorgu alanlarını üretir", {
  env <- .source_admin_hata_helper_for_test()

  calls <- character(0)

  fake_query <- function(sql) {
    calls <<- c(calls, sql)
    data.frame(cnt = integer(0), stringsAsFactors = FALSE)
  }

  out <- env$admin_ha_fetch_data(query_fn = fake_query)

  expected_names <- c(
    "tumu",
    "toplam",
    "durum_dagilim",
    "oncelik_dagilim",
    "bugun",
    "bu_hafta",
    "gunluk_trend",
    "oncelik_trend",
    "kategoriler_ham",
    "ekli_bildirim",
    "kullanici_bildirim",
    "saatlik_dagilim",
    "haftalik_trend",
    "oncelik_kategori"
  )

  expect_equal(names(out), expected_names)
  expect_equal(length(calls), length(expected_names))
  expect_true(any(grepl("MB_Destek_Hata_Bildir", calls, fixed = TRUE)))
})

test_that("admin hata tab UI router helperları Shiny tag listesi üretir", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("highcharter")
  testthat::skip_if_not_installed("DT")

  env <- .source_admin_hata_helper_for_test()

  ns <- shiny::NS("admin_hata_test")

  fake_data_provider <- function() {
    list(
      toplam = data.frame(cnt = 0L),
      bugun = data.frame(cnt = 0L),
      bu_hafta = data.frame(cnt = 0L),
      ekli_bildirim = data.frame(cnt = 0L),
      durum_dagilim = data.frame(Durum = character(0), cnt = integer(0)),
      oncelik_dagilim = data.frame(Oncelik = character(0), cnt = integer(0))
    )
  }

  expect_s3_class(
    env$admin_ha_tab_ui("ha_overview", ns, fake_data_provider),
    "shiny.tag.list"
  )

  expect_s3_class(
    env$admin_ha_tab_ui("ha_oncelik", ns, fake_data_provider),
    "shiny.tag.list"
  )

  expect_s3_class(
    env$admin_ha_tab_ui("ha_detay", ns, fake_data_provider),
    "shiny.tag.list"
  )

  expect_s3_class(
    env$admin_ha_tab_ui("ha_zaman", ns, fake_data_provider),
    "shiny.tag.list"
  )
})
# ==============================================================================
# Dosya Yolu: tests/testthat/test-admin-hata-heatmap-data-behavior.R
# Açıklama: R/helpers_admin_hata_heatmap_data.R içindeki saf
#           admin_ha_prepare_heatmap_data fonksiyonunun KENAR davranışlarını
#           kapsar. Mevcut test-admin-hata-analizi-refactor-contract.R yalnızca
#           tek bir mutlu yolu doğrular; burada KAPSANMAYAN durumlar test edilir:
#             - NULL / boş / data.frame-olmayan / eksik sütun -> boş sonuç
#             - çoklu kategori "a, b" -> yalnızca ilk segment
#             - tekrarlı kategori+öncelik hücrelerinin toplanması
#             - bilinmeyen kategori kodu ham kalır; bilinmeyen öncelik kanonik
#               sıra filtresiyle dışlanır
#             - NA/boş kategori veya öncelik satırları elenir
#             - öncelik kanonik sıralaması (Düşük, Orta, Yüksek, Kritik, Belirtilmedi)
#           Saf fonksiyon; çeviri haritaları argüman olarak verilir. Shiny/DB/
#           highcharter GEREKMEZ; yalnızca base R.
# ==============================================================================

.hahmap_source_once <- function() {
  if (exists("admin_ha_prepare_heatmap_data", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_admin_hata_heatmap_data.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

# Sentetik kategori/öncelik çeviri haritaları (gerçek modül helper'larından bağımsız).
.hahmap_kat <- function() {
  c(arayuz = "Arayüz / Tasarım", cokme = "Çökme / Hata", performans = "Performans")
}
.hahmap_onc <- function() {
  c(dusuk = "Düşük", orta = "Orta", yuksek = "Yüksek",
    kritik = "Kritik", belirtilmedi = "Belirtilmedi")
}

# Sonucun "boş" olup olmadığını kontrol eden yardımcı.
.hahmap_is_empty <- function(out) {
  length(out$kategoriler) == 0L &&
    length(out$oncelikler) == 0L &&
    length(out$heatmap_data) == 0L
}

# ------------------------------------------------------------------------------
# Geçersiz / eksik girdiler -> boş sonuç
# ------------------------------------------------------------------------------
testthat::test_that("admin_ha_prepare_heatmap_data NULL/boş/df-olmayan/eksik-sütun için boş sonuç döner", {
  .hahmap_source_once()
  KAT <- .hahmap_kat(); ONC <- .hahmap_onc()

  testthat::expect_true(.hahmap_is_empty(admin_ha_prepare_heatmap_data(NULL, KAT, ONC)))
  testthat::expect_true(.hahmap_is_empty(admin_ha_prepare_heatmap_data(data.frame(), KAT, ONC)))
  testthat::expect_true(.hahmap_is_empty(admin_ha_prepare_heatmap_data(list(a = 1), KAT, ONC)))

  # Zorunlu sütunlar (Kategoriler, Oncelik, cnt) eksik
  eksik <- data.frame(Oncelik = "kritik", cnt = 1L, stringsAsFactors = FALSE)
  testthat::expect_true(.hahmap_is_empty(admin_ha_prepare_heatmap_data(eksik, KAT, ONC)))
})

# ------------------------------------------------------------------------------
# Çoklu kategori + toplama
# ------------------------------------------------------------------------------
testthat::test_that("admin_ha_prepare_heatmap_data çoklu kategoride ilk segmenti alır ve hücreleri toplar", {
  .hahmap_source_once()
  data <- data.frame(
    Oncelik = c("kritik", "kritik"),
    Kategoriler = c("arayuz, performans", "arayuz"),
    cnt = c(2L, 3L),
    stringsAsFactors = FALSE
  )
  out <- admin_ha_prepare_heatmap_data(data, .hahmap_kat(), .hahmap_onc())

  # "arayuz, performans" -> yalnızca "arayuz" -> "Arayüz / Tasarım"
  testthat::expect_identical(out$kategoriler, "Arayüz / Tasarım")
  testthat::expect_identical(out$oncelikler, "Kritik")
  # Aynı kategori+öncelik hücresi toplanır: 2 + 3 = 5
  testthat::expect_length(out$heatmap_data, 1L)
  testthat::expect_equal(out$heatmap_data[[1]][[3]], 5L)
  # Koordinatlar 0-indeksli
  testthat::expect_equal(out$heatmap_data[[1]][[1]], 0)
  testthat::expect_equal(out$heatmap_data[[1]][[2]], 0)
})

# ------------------------------------------------------------------------------
# Bilinmeyen kodlar
# ------------------------------------------------------------------------------
testthat::test_that("admin_ha_prepare_heatmap_data bilinmeyen kategoriyi ham bırakır, bilinmeyen önceliği dışlar", {
  .hahmap_source_once()
  data <- data.frame(
    Oncelik = "bilinmeyen_onc",
    Kategoriler = "bilinmeyen_kat",
    cnt = 4L,
    stringsAsFactors = FALSE
  )
  out <- admin_ha_prepare_heatmap_data(data, .hahmap_kat(), .hahmap_onc())

  # Haritada olmayan kategori kodu ham haliyle korunur
  testthat::expect_identical(out$kategoriler, "bilinmeyen_kat")
  # Kanonik sıra filtresi bilinmeyen önceliği dışlar -> öncelik ve heatmap boş
  testthat::expect_length(out$oncelikler, 0L)
  testthat::expect_length(out$heatmap_data, 0L)
})

# ------------------------------------------------------------------------------
# NA / boş eleme
# ------------------------------------------------------------------------------
testthat::test_that("admin_ha_prepare_heatmap_data NA/boş kategori veya öncelik satırlarını eler", {
  .hahmap_source_once()
  data <- data.frame(
    Oncelik = c("kritik", NA, "kritik"),
    Kategoriler = c("arayuz", "cokme", ""),
    cnt = c(1L, 2L, 3L),
    stringsAsFactors = FALSE
  )
  out <- admin_ha_prepare_heatmap_data(data, .hahmap_kat(), .hahmap_onc())
  # Yalnızca ilk satır (arayuz/kritik) geçerli
  testthat::expect_identical(out$kategoriler, "Arayüz / Tasarım")
  testthat::expect_identical(out$oncelikler, "Kritik")
  testthat::expect_equal(out$heatmap_data[[1]][[3]], 1L)

  # Tüm satırlar geçersizse boş sonuç
  hep_na <- data.frame(
    Oncelik = NA_character_, Kategoriler = NA_character_, cnt = 1L,
    stringsAsFactors = FALSE
  )
  testthat::expect_true(.hahmap_is_empty(admin_ha_prepare_heatmap_data(hep_na, .hahmap_kat(), .hahmap_onc())))
})

# ------------------------------------------------------------------------------
# Öncelik kanonik sıralaması
# ------------------------------------------------------------------------------
testthat::test_that("admin_ha_prepare_heatmap_data öncelikleri kanonik sırada tutar (mevcut alt küme)", {
  .hahmap_source_once()
  # Girdi sırası karışık: kritik, dusuk, orta -> kanonik: Düşük, Orta, Kritik
  data <- data.frame(
    Oncelik = c("kritik", "dusuk", "orta"),
    Kategoriler = c("arayuz", "arayuz", "arayuz"),
    cnt = c(1L, 1L, 1L),
    stringsAsFactors = FALSE
  )
  out <- admin_ha_prepare_heatmap_data(data, .hahmap_kat(), .hahmap_onc())
  testthat::expect_identical(out$oncelikler, c("Düşük", "Orta", "Kritik"))
})

# ------------------------------------------------------------------------------
# Tam 2x2 ızgara yapısı
# ------------------------------------------------------------------------------
testthat::test_that("admin_ha_prepare_heatmap_data 2x2 ızgarada tüm hücreleri 0-indeksli üretir", {
  .hahmap_source_once()
  data <- data.frame(
    Oncelik = c("dusuk", "kritik"),
    Kategoriler = c("arayuz", "cokme"),
    cnt = c(7L, 9L),
    stringsAsFactors = FALSE
  )
  out <- admin_ha_prepare_heatmap_data(data, .hahmap_kat(), .hahmap_onc())
  testthat::expect_identical(out$kategoriler, c("Arayüz / Tasarım", "Çökme / Hata"))
  testthat::expect_identical(out$oncelikler, c("Düşük", "Kritik"))
  # 2 kategori x 2 öncelik = 4 hücre; köşegen dolu, diğerleri 0
  testthat::expect_length(out$heatmap_data, 4L)
  testthat::expect_equal(
    out$heatmap_data,
    list(
      list(0, 0, 7L),
      list(0, 1, 0L),
      list(1, 0, 0L),
      list(1, 1, 9L)
    )
  )
})

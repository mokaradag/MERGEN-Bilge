# ==============================================================================
# Dosya Yolu: tests/testthat/test-admin-geri-bildirim-output-tables-behavior.R
# Açıklama: Geri Bildirim Analizi DT tablo veri hazırlama yardımcılarının
#           renderer/Shiny olmadan davranışını doğrular.
# ==============================================================================

testthat::local_edition(3)

.gbot_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "helpers_admin_geri_bildirim_output_tables.R"),
  encoding = "UTF-8",
  local = .gbot_env
)

test_that("kullanıcı tablosu Türkçe başlıkları ve yuvarlatılmış değerleri üretir", {
  veri <- data.frame(
    KullaniciAdi = "Ayşe",
    bildirim_sayisi = 3,
    ort_memnuniyet = 4.34,
    ort_nps = 8.56,
    son_bildirim = "2026-01-03 10:05:00",
    stringsAsFactors = FALSE
  )

  sonuc <- .gbot_env$admin_gb_prepare_kullanici_table_data(veri)

  expect_identical(
    names(sonuc),
    c("#", "Kullanıcı", "Bildirim", "Ort. Memnuniyet", "Ort. NPS", "Son Bildirim")
  )
  expect_equal(sonuc[["Ort. Memnuniyet"]][1], 4.3)
  expect_equal(sonuc[["Ort. NPS"]][1], 8.6)
  expect_identical(sonuc[["Son Bildirim"]][1], "03.01.2026 10:05")
})

test_that("detay tablosu sıralama sütunlarını, iletişim iznini ve mail ikonunu hazırlar", {
  veri <- data.frame(
    GeriBildirimID = c(42, 43),
    KullaniciAdi = c("Ayşe", ""),
    Memnuniyet = c(5, NA),
    NPS_Puan = c(10, 6),
    Etiketler = c("tasarım", ""),
    EnCokSevilen = c("Hız", NA),
    Gelistirme = c("", "Daha iyi filtre"),
    IletisimIzni = c(1, 0),
    EmailAddress = c("ayse@example.com", "veli@example.com"),
    OlusturmaTarihi = c("2026-01-03 10:05:00", "2026-01-04 11:00:00"),
    stringsAsFactors = FALSE
  )

  sonuc <- .gbot_env$admin_gb_prepare_detay_table_data(veri)

  expect_identical(
    names(sonuc),
    c("#", "Kullanıcı", "Memnuniyet", "memn_sort", "NPS", "nps_sort",
      "Etiketler", "En Çok Sevilen", "Geliştirilecek", "İletişim İzni", "\U0001F4E7", "Tarih")
  )
  expect_match(sonuc[["Memnuniyet"]][1], "5/5", fixed = TRUE)
  expect_equal(sonuc$memn_sort, c(5, 0))
  expect_match(sonuc[["NPS"]][1], "#10b981", fixed = TRUE)
  expect_match(sonuc[["NPS"]][2], "#ef4444", fixed = TRUE)
  expect_equal(sonuc$nps_sort, c(10, 6))
  expect_identical(sonuc[["Kullanıcı"]], c("Ayşe", "-"))
  expect_identical(sonuc[["Etiketler"]], c("tasarım", "-"))
  expect_identical(sonuc[["En Çok Sevilen"]], c("Hız", "-"))
  expect_identical(sonuc[["Geliştirilecek"]], c("-", "Daha iyi filtre"))
  expect_match(sonuc[["İletişim İzni"]][1], "Evet", fixed = TRUE)
  expect_match(sonuc[["İletişim İzni"]][2], "Hayır", fixed = TRUE)
  expect_match(sonuc[["\U0001F4E7"]][1], "mailto:ayse@example.com", fixed = TRUE)
  expect_identical(sonuc[["\U0001F4E7"]][2], "")
  expect_identical(sonuc[["Tarih"]][1], "03.01.2026 10:05")
})

test_that("detay tablosu kullanıcı kontrollü metinleri HTML olarak kaçırır", {
  # Tablo DT tarafında escape = FALSE ile render edildiği için, kullanıcı
  # kontrollü serbest metinlerin veri hazırlama katmanında kaçırılması gerekir.
  zararli <- "<img src=x onerror=alert(1)>"

  veri <- data.frame(
    GeriBildirimID = 1,
    KullaniciAdi = zararli,
    Memnuniyet = 3,
    NPS_Puan = 7,
    Etiketler = zararli,
    EnCokSevilen = zararli,
    Gelistirme = zararli,
    IletisimIzni = 0,
    EmailAddress = "",
    OlusturmaTarihi = "2026-01-03 10:05:00",
    stringsAsFactors = FALSE
  )

  sonuc <- .gbot_env$admin_gb_prepare_detay_table_data(veri)

  for (sutun in c("Kullanıcı", "Etiketler", "En Çok Sevilen", "Geliştirilecek")) {
    deger <- sonuc[[sutun]][1]
    expect_false(grepl("<img", deger, fixed = TRUE), info = sutun)
    expect_true(grepl("&lt;img", deger, fixed = TRUE), info = sutun)
  }

  # Uygulama üretimi rozet HTML'i kaçırılmadan kalmalı (escape = FALSE bunun içindir).
  expect_match(sonuc[["İletişim İzni"]][1], "<span", fixed = TRUE)
})

# ==============================================================================
# Dosya Yolu: tests/testthat/test-ortak-oturum-permissions-behavior.R
# Açıklama: Ortak Oturumlar SAF karar katmanının davranış testleri: Türkçe iş
#           kuralı sabitleri, rol/yetki matrisi, içerik erişimi, mesaj
#           yönlendirme planı, canlı durum sınıflandırması, liste görünürlüğü
#           ve e-posta taslağı güvenliği. Çevrimdışı ve deterministiktir; DB,
#           LLM, tarayıcı veya ağ GEREKMEZ.
# ==============================================================================

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }

  if (!exists("ortak_rol_yetkileri", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_ortak_oturum_permissions.R"),
           encoding = "UTF-8", local = globalenv())
  }

  if (!exists("ortak_davet_eposta_metni", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_ortak_oturum_email.R"),
           encoding = "UTF-8", local = globalenv())
  }
})

# Parser-güvenli Türkçe sabit kurucular (Windows VM konsol/kod sayfası riskine
# karşı deterministik Unicode kurulumu).
.oo_tr <- function(...) {
  paste0(vapply(list(...), function(p) {
    if (is.numeric(p)) intToUtf8(as.integer(p)) else as.character(p)
  }, character(1)), collapse = "")
}

.oo_sahip <- "Sahip"
.oo_yonetici <- .oo_tr("OturumY", 0xF6, "neticisi")
.oo_katilimci <- .oo_tr("Kat", 0x131, "l", 0x131, "mc", 0x131)
.oo_izleyici <- .oo_tr(0x130, "zleyici")
.oo_katildi <- .oo_tr("Kat", 0x131, "ld", 0x131)
.oo_davet_edildi <- "DavetEdildi"
.oo_oda_mesaji <- .oo_tr("OdaMesaj", 0x131)
.oo_yz_sorusu <- "YapayZekaSorusu"
.oo_yz_yaniti <- .oo_tr("YapayZekaYan", 0x131, "t", 0x131)
.oo_cevrimici <- .oo_tr(0xC7, "evrim", 0x130, "çi")
.oo_bosta <- .oo_tr("Bo", 0x15F, "ta")
.oo_cevrimdisi <- .oo_tr(0xC7, "evrimD", 0x131, 0x15F, 0x131)

test_that("Türkçe iş kuralı sabitleri İngilizce durum değeri içermez", {
  tum_sabitler <- c(
    ortak_oturum_kaynak_turleri(),
    ortak_oturum_durumlari(),
    ortak_oturum_rolleri(),
    ortak_katilim_durumlari(),
    ortak_gorunum_durumlari(),
    ortak_mesaj_turleri(),
    ortak_mesaj_hedefleri(),
    ortak_davet_durumlari(),
    ortak_davet_yontemleri(),
    ortak_canli_durumlar(),
    ortak_dosya_kopya_durumlari()
  )

  yasakli_ingilizce <- c(
    "owner", "editor", "viewer", "pending", "accepted", "completed",
    "failed", "archived", "user", "assistant", "active", "closed"
  )

  for (yasak in yasakli_ingilizce) {
    expect_false(
      any(tolower(tum_sabitler) == yasak),
      info = sprintf("İngilizce durum değeri sabitlere sızmış: %s", yasak)
    )
  }
})

test_that("rol yetki matrisi: Sahip yönetir, İzleyici yazamaz ve soramaz", {
  sahip <- ortak_rol_yetkileri(.oo_sahip)
  expect_true(sahip$oda_yaz)
  expect_true(sahip$yapay_zeka_sor)
  expect_true(sahip$davet_et)
  expect_true(sahip$katilimci_yonet)
  expect_true(sahip$rol_degistir)
  expect_true(sahip$oturum_kapat)

  yonetici <- ortak_rol_yetkileri(.oo_yonetici)
  expect_true(yonetici$davet_et)
  expect_true(yonetici$katilimci_yonet)
  expect_false(yonetici$rol_degistir)
  expect_false(yonetici$oturum_kapat)

  katilimci <- ortak_rol_yetkileri(.oo_katilimci)
  expect_true(katilimci$oda_yaz)
  expect_true(katilimci$yapay_zeka_sor)
  expect_false(katilimci$davet_et)
  expect_false(katilimci$katilimci_yonet)

  izleyici <- ortak_rol_yetkileri(.oo_izleyici)
  expect_true(izleyici$oku)
  expect_false(izleyici$oda_yaz)
  expect_false(izleyici$yapay_zeka_sor)
})

test_that("bilinmeyen rol fail-closed davranır (hiçbir yetki verilmez)", {
  bilinmeyen <- ortak_rol_yetkileri("owner")
  expect_false(any(unlist(bilinmeyen)))

  expect_false(ortak_yetki_var_mi(NULL, "oku"))
  expect_false(ortak_yetki_var_mi(NA_character_, "oda_yaz"))
})

test_that("içerik erişimi yalnızca Katıldı durumunda verilir", {
  expect_true(ortak_icerik_erisimi_var_mi(.oo_katildi))
  expect_false(ortak_icerik_erisimi_var_mi(.oo_davet_edildi))
  expect_false(ortak_icerik_erisimi_var_mi("Reddetti"))
  expect_false(ortak_icerik_erisimi_var_mi(NULL))
})

test_that("Sahip başka katılımcı tarafından yönetilemez", {
  expect_false(ortak_katilimci_yonetilebilir_mi(.oo_yonetici, .oo_sahip))
  expect_false(ortak_katilimci_yonetilebilir_mi(.oo_sahip, .oo_sahip))
  expect_true(ortak_katilimci_yonetilebilir_mi(.oo_sahip, .oo_katilimci))
  expect_true(ortak_katilimci_yonetilebilir_mi(.oo_yonetici, .oo_izleyici))
  expect_false(ortak_katilimci_yonetilebilir_mi(.oo_katilimci, .oo_izleyici))
})

test_that("mesaj yönlendirme: yalnızca YapayZekaSorusu LLM tetikler", {
  oda <- ortak_mesaj_yonlendirme_plani(.oo_oda_mesaji)
  expect_true(oda$gecerli)
  expect_false(oda$llm_tetikler)
  expect_identical(oda$hedef, ortak_mesaj_hedefleri()[1])

  soru <- ortak_mesaj_yonlendirme_plani(.oo_yz_sorusu)
  expect_true(soru$gecerli)
  expect_true(soru$llm_tetikler)
  expect_identical(soru$hedef, "YapayZeka")

  yanit <- ortak_mesaj_yonlendirme_plani(.oo_yz_yaniti)
  expect_false(yanit$llm_tetikler)

  gecersiz <- ortak_mesaj_yonlendirme_plani("chat_message")
  expect_false(gecersiz$gecerli)
  expect_false(gecersiz$llm_tetikler)
})

test_that("canlı durum sınıflandırması eşiklere göre Türkçe değer döner", {
  simdi <- as.POSIXct("2026-07-05 12:00:00", tz = "UTC")

  taze <- format(simdi - 30, "%Y-%m-%d %H:%M:%S")
  expect_identical(ortak_sunum_durumu(taze, simdi = simdi), .oo_cevrimici)

  orta <- format(simdi - 200, "%Y-%m-%d %H:%M:%S")
  expect_identical(ortak_sunum_durumu(orta, simdi = simdi), .oo_bosta)

  eski <- format(simdi - 3600, "%Y-%m-%d %H:%M:%S")
  expect_identical(ortak_sunum_durumu(eski, simdi = simdi), .oo_cevrimdisi)

  expect_identical(ortak_sunum_durumu(NA, simdi = simdi), .oo_cevrimdisi)
  expect_identical(ortak_sunum_durumu("gecersiz-zaman", simdi = simdi), .oo_cevrimdisi)
})

test_that("liste görünürlüğü: kullanıcı arşivi kişiseldir, oda arşivi ortaktır", {
  gorunuyor <- ortak_gorunum_durumlari()[1]
  kullanici_arsivi <- ortak_gorunum_durumlari()[2]

  # Normal görünüm: aktif + görünür satır listelenir.
  expect_true(ortak_liste_gorunur_mu(.oo_katildi, gorunuyor, "Aktif"))

  # Kullanıcı arşivledi: normal listede görünmez, arşiv görünümünde görünür.
  expect_false(ortak_liste_gorunur_mu(.oo_katildi, kullanici_arsivi, "Aktif"))
  expect_true(ortak_liste_gorunur_mu(.oo_katildi, kullanici_arsivi, "Aktif", arsiv_gorunumu = TRUE))

  # Oda arşivlendi (herkes): normal listede görünmez, arşiv görünümünde görünür.
  oda_arsiv <- ortak_oturum_durumlari()[2]
  expect_false(ortak_liste_gorunur_mu(.oo_katildi, gorunuyor, oda_arsiv))
  expect_true(ortak_liste_gorunur_mu(.oo_katildi, gorunuyor, oda_arsiv, arsiv_gorunumu = TRUE))

  # Çıkarılmış/ayrılmış kullanıcı hiçbir görünümde satır görmez.
  expect_false(ortak_liste_gorunur_mu("Ayrıldı", gorunuyor, "Aktif"))
  expect_false(ortak_liste_gorunur_mu("Çıkarıldı", gorunuyor, "Aktif", arsiv_gorunumu = TRUE))
})

test_that("davet e-posta taslağı içerik sızdırmaz ve Türkçe kalır", {
  metin <- ortak_davet_eposta_metni("Mehmet Onur Karadağ", "Bütçe Analizi")

  expect_true(grepl("Mehmet Onur Karadağ", metin$govde, fixed = TRUE))
  expect_true(grepl("Bütçe Analizi", metin$govde, fixed = TRUE))
  expect_true(grepl("Ortak Çalışmalarım > Davetlerim", metin$govde, fixed = TRUE))

  # Güvenlik: taslak URL, dosya yolu, token veya içerik bloğu içermez.
  expect_true(ortak_davet_eposta_guvenli_mi(metin$govde))
  expect_false(ortak_davet_eposta_guvenli_mi("Yanıt: https://ornek/oda/42"))
  expect_false(ortak_davet_eposta_guvenli_mi("token=abc123 ile giriş yapın"))
  expect_false(ortak_davet_eposta_guvenli_mi(""))

  href <- ortak_davet_eposta_taslak_href("kisi@example.com", "Ali", "Deneme")
  expect_true(startsWith(href, "mailto:kisi@example.com"))
  expect_true(grepl("subject=", href, fixed = TRUE))
  expect_true(grepl("body=", href, fixed = TRUE))

  expect_identical(ortak_davet_eposta_taslak_href("", "Ali", "Deneme"), "")
})

test_that("paylaşım başlangıç tipleri kaynak türüne göre güvenli varsayılanla döner", {
  normal <- ortak_paylasim_baslangic_tipleri("NormalSohbet")
  expect_identical(normal[1], "SadeceBundanSonrası")
  expect_length(normal, 3L)

  by <- ortak_paylasim_baslangic_tipleri("BilgeYolaç")
  expect_identical(by[1], "SadeceYeniÇalıştırmalar")
  expect_length(by, 3L)
})

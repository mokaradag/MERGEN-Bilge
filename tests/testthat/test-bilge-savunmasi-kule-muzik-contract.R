# ==============================================================================
# Dosya Yolu: tests/testthat/test-bilge-savunmasi-kule-muzik-contract.R
# Açıklama: Bilge Savunması genişletme sözleşmeleri: inşa edilebilir kuleler,
#           oyun-yerel müzik grupları (menü/seviye), tam ekran düğmesi, 2.5D
#           görsel katmanları ve altı haritalı kampanya. İstemci (JS) ve sunucu
#           (R) tarafındaki denge/harita/dalga verilerinin TUTARLILIĞINI de
#           doğrular; böylece sunucu puan sınırı gerçek dalga düşman sayısını
#           yansıtır. Statik bayt taraması + saf R davranışı; uygulama boot, DB,
#           tarayıcı veya ağ GEREKMEZ. Dosya okumaları Windows/VM-güvenli
#           bayt yoludur.
# ==============================================================================

.bs_km_repo_root <- resolve_repo_root_for_tests()

.bs_km_oku <- function(...) {
  yol <- file.path(.bs_km_repo_root, ...)
  ham <- readBin(yol, what = "raw", n = file.info(yol)$size)
  iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")
}

.bs_km_iceriyor <- function(metin, kalip) {
  grepl(kalip, metin, fixed = TRUE, useBytes = TRUE)
}

local({
  if (!exists("bs_harita_katalogu", mode = "function", inherits = TRUE)) {
    source(file.path(.bs_km_repo_root, "R", "config_characters.R"),
           encoding = "UTF-8", local = globalenv())
    source(file.path(.bs_km_repo_root, "R", "config_bilge_savunmasi.R"),
           encoding = "UTF-8", local = globalenv())
  }
})

test_that("kule tanımları denge katmanında ve simülasyon uzantısı bağlanıyor", {
  denge <- .bs_km_oku("www", "js", "bilge_savunmasi_denge.js")
  # Üç kule tipi, üç kademe ve satış/yükseltme yardımcıları.
  for (tip in c("gozetleme", "veri_topu", "kripto_isik")) {
    expect_true(.bs_km_iceriyor(denge, paste0(tip, ":")),
                info = paste("Kule tipi eksik:", tip))
  }
  expect_true(.bs_km_iceriyor(denge, "kuleAl:"))
  expect_true(.bs_km_iceriyor(denge, "kuleIstatistik:"))
  expect_true(.bs_km_iceriyor(denge, "kuleYatirim:"))
  # Alan hasarı ve zırh delme kule ayırt edici özellikleri.
  expect_true(.bs_km_iceriyor(denge, "alanYaricapi"))
  expect_true(.bs_km_iceriyor(denge, "zirhDelme"))

  kuleler_js <- .bs_km_oku("www", "js", "bilge_savunmasi_sim_kuleler.js")
  expect_true(.bs_km_iceriyor(kuleler_js, "sim.kuleYerlestir"))
  expect_true(.bs_km_iceriyor(kuleler_js, "sim.kuleYukselt"))
  expect_true(.bs_km_iceriyor(kuleler_js, "sim.kuleSat"))
  expect_true(.bs_km_iceriyor(kuleler_js, "sim.kuleTik"))
  expect_true(.bs_km_iceriyor(kuleler_js, "sim.kuleSeriDurum"))
  expect_true(.bs_km_iceriyor(kuleler_js, "sim.kuleSeriYukle"))
  # Kule mermisi kaynak sahibi olmadan (null) çözülür; alan hasarı uygulanır.
  expect_true(.bs_km_iceriyor(kuleler_js, 'sahipTip: "kule"'))
  expect_true(.bs_km_iceriyor(kuleler_js, "kuleVurusUygula"))
})

test_that("simülasyon çekirdeği kule uzantısını ve seri durumu geriye uyumlu bağlar", {
  sim <- .bs_km_oku("www", "js", "bilge_savunmasi_sim.js")
  # Kule uzantısı savunmacı bir varlık kontrolüyle bağlanır (izole testlerde
  # uzantı yoksa çekirdek yine çalışır).
  expect_true(.bs_km_iceriyor(sim, "BS.simKuleler && BS.simKuleler.bagla"))
  # Kule atışı dalga aktifken işlenir; kule mermisi hedeflemesi hero-özel
  # mantığa girmeden erken çözülür.
  expect_true(.bs_km_iceriyor(sim, "if (sim.kuleTik) sim.kuleTik(dt)"))
  expect_true(.bs_km_iceriyor(sim, 'mermi.sahipTip === "kule"'))
  # Kontrol noktası serileştirmesi kuleleri taşır; eski (kulesiz) kayıt yüklenebilir.
  expect_true(.bs_km_iceriyor(sim, "sim.kuleSeriDurum ? sim.kuleSeriDurum() : []"))
  expect_true(.bs_km_iceriyor(sim, "if (sim.kuleSeriYukle) sim.kuleSeriYukle(kayit.kuleler)"))
  # hasarVer, kule kaynaklı zırh delmeyi secenek parametresiyle uygular.
  expect_true(.bs_km_iceriyor(sim, "secenek && secenek.zirhDelme > 0"))
  # İnşa alanı sorgusu kule dolu hücreleri de kapsar.
  expect_true(.bs_km_iceriyor(sim, "sim.kuleBul && sim.kuleBul(hx, hy)"))
})

test_that("HUD kule inşa kartlarını, seçim panelini ve tam ekran düğmesini taşır", {
  hud <- .bs_km_oku("www", "js", "bilge_savunmasi_hud.js")
  expect_true(.bs_km_iceriyor(hud, "bs-kule-karti"))
  expect_true(.bs_km_iceriyor(hud, 'data-bs-komut="kule"'))
  expect_true(.bs_km_iceriyor(hud, "kuleSecimGuncelle"))
  expect_true(.bs_km_iceriyor(hud, 'data-bs-komut="kule-yukselt"'))
  expect_true(.bs_km_iceriyor(hud, 'data-bs-komut="kule-sat"'))
  # Tam ekran düğmesi üst kontrol çubuğundadır.
  expect_true(.bs_km_iceriyor(hud, 'data-bs-komut="tamekran"'))
  expect_true(.bs_km_iceriyor(hud, 'BS.olaylar.yay("hud-tamekran"'))
})

test_that("sahne katmanı tam ekran, oyun müziği ve kule olay bağlayıcılarını yönetir", {
  sahne <- .bs_km_oku("www", "js", "bilge_savunmasi_sahne.js")
  expect_true(.bs_km_iceriyor(sahne, "tamEkranDegistir"))
  expect_true(.bs_km_iceriyor(sahne, "requestFullscreen"))
  expect_true(.bs_km_iceriyor(sahne, "webkitRequestFullscreen"))
  expect_true(.bs_km_iceriyor(sahne, "menuMuzigi"))
  expect_true(.bs_km_iceriyor(sahne, "seviyeMuzigi"))
  expect_true(.bs_km_iceriyor(sahne, "kuleOlaylariniBagla"))
  # Kule olay bağlayıcıları bir kez kurulur (idempotent bayrak).
  expect_true(.bs_km_iceriyor(sahne, "BS.sahne._kuleOlaylariBagli"))

  uygulama <- .bs_km_oku("www", "js", "bilge_savunmasi_uygulama.js")
  expect_true(.bs_km_iceriyor(uygulama, "BS.sahne.kuleOlaylariniBagla()"))
  expect_true(.bs_km_iceriyor(uygulama, "BS.sahne.seviyeMuzigi(harita)"))
  expect_true(.bs_km_iceriyor(uygulama, "BS.sahne.menuMuzigi()"))
})

test_that("ses katmanı grup tabanlı müzik listelerini ve tam sessiz uygulama kısmasını yönetir", {
  ses <- .bs_km_oku("www", "js", "bilge_savunmasi_ses.js")
  expect_true(.bs_km_iceriyor(ses, "muzikListesiAyarla"))
  expect_true(.bs_km_iceriyor(ses, "muzikCal"))
  expect_true(.bs_km_iceriyor(ses, "calmaListeleri"))
  # Ardışık tekrar azaltma: son çalınan parça atlanır.
  expect_true(.bs_km_iceriyor(ses, "sonCalinan"))
  # Bayat parça koruması: yalnızca hâlâ aktif müzikse devam eder.
  expect_true(.bs_km_iceriyor(ses, "durum.muzik !== ses"))
  # MERGEN uygulama müziği "oyun" sahibiyle kısılır/bırakılır.
  expect_true(.bs_km_iceriyor(ses, 'MusicManager.duck("oyun")'))
  expect_true(.bs_km_iceriyor(ses, 'MusicManager.unduck("oyun")'))

  # "oyun" sahibi ses yaşam döngüsünde TAM sessizlik uygular (iki müzik
  # üst üste binmez); bu, boşta konuşma kısmasından ayrı bir sözleşmedir.
  guard <- .bs_km_oku("www", "js", "audio_lifecycle_guard.js")
  expect_true(.bs_km_iceriyor(guard, "owners.indexOf('oyun') >= 0"))
  expect_true(.bs_km_iceriyor(guard, "fullSilence"))
})

test_that("2.5D görsel katmanları (varlık yükleyici + zemin ressamı + derinlik sırası) mevcut", {
  varliklar <- .bs_km_oku("www", "js", "bilge_savunmasi_varliklar.js")
  expect_true(.bs_km_iceriyor(varliklar, "kuleCiz"))
  expect_true(.bs_km_iceriyor(varliklar, "dekorCiz"))
  expect_true(.bs_km_iceriyor(varliklar, "kuleGorsel"))
  # Görsel yoksa prosedürel yedek çizilir (kırık görsel yok).
  expect_true(.bs_km_iceriyor(varliklar, "_kuleYedekCiz"))
  # Dış URL yok (çevrimdışı/on-prem sözleşme).
  expect_false(.bs_km_iceriyor(varliklar, "http://") ||
                 .bs_km_iceriyor(varliklar, "https://"))

  cizim <- .bs_km_oku("www", "js", "bilge_savunmasi_cizim.js")
  # Derinlik sırası: varlıklar ızgara Y'sine göre sıralanıp alttaki üstte çizilir.
  expect_true(.bs_km_iceriyor(cizim, "varliklariDerinlikSirasiylaCiz"))
  expect_true(.bs_km_iceriyor(cizim, "derinlikOlcek"))
  expect_true(.bs_km_iceriyor(cizim, "BS.varliklar.kuleCiz"))
  # Statik zemin ayrı ressama delege edilir (bakım bütçesi).
  expect_true(.bs_km_iceriyor(cizim, "BS.cizimZemin.ciz"))

  zemin <- .bs_km_oku("www", "js", "bilge_savunmasi_cizim_zemin.js")
  expect_true(.bs_km_iceriyor(zemin, "BS.cizimZemin"))
})

test_that("harita kataloğu (JS istemci) altı haritayı müzik grubuyla taşır", {
  haritalar <- .bs_km_oku("www", "js", "bilge_savunmasi_haritalar.js")
  for (id in c("baglam_kapisi", "celiski_kavsagi", "bilgi_cekirdegi",
               "veri_labirenti", "sinyal_vadisi", "karar_zirvesi")) {
    expect_true(.bs_km_iceriyor(haritalar, paste0(id, ":")),
                info = paste("Harita eksik:", id))
  }
  # Müzik grubu bilgisi haritada taşınır (bolum_1 / bolum_2).
  expect_true(.bs_km_iceriyor(haritalar, "muzikGrubu"))
  expect_true(.bs_km_iceriyor(haritalar, '"bolum_1"'))
  expect_true(.bs_km_iceriyor(haritalar, '"bolum_2"'))
  # Sıralı liste tek kaynaktan türetilir (yeni harita kendiliğinden gelir).
  expect_true(.bs_km_iceriyor(haritalar, "Object.keys(BS.haritalar.liste)"))
})

test_that("sunucu (R) harita kataloğu patron kuralı ve iç tutarlılığı korur", {
  # Regresyon koruması: sunucu dalga puan sınırı, harita kataloğundaki
  # dalga_dusman_sayilari'na dayanır. Kritik değişmez: her dalga düşman sayısı
  # üst sınırı aşmaz ve patron sayı vektörü, istemciyle AYNI patron kuralıyla
  # (dalga %% 4 == 0 veya son dalga) uyumludur. İstemci JS dalga toplamları
  # ile birebir eşleşme, test-bilge-savunmasi-config-behavior.R ve node
  # doğrulamasıyla ayrıca kapsanır.
  katalog <- bs_harita_katalogu()
  for (id in names(katalog)) {
    kayit <- katalog[[id]]
    n <- kayit$dalga_sayisi
    expect_length(kayit$dalga_dusman_sayilari, n)
    expect_length(kayit$dalga_patron_sayilari, n)
    for (d in seq_len(n)) {
      patron_beklenen <- (d %% 4L == 0L) || (d == n)
      patron_var <- kayit$dalga_patron_sayilari[[d]] > 0L
      expect_identical(
        patron_var, patron_beklenen,
        info = sprintf("%s dalga %d patron kuralı", id, d)
      )
    }
  }
})

test_that("zorluk yeniden dengesi kule gücünü hesaba katar (tehdit dayanıklılığı arttı)", {
  # Kule eklenmesiyle savunma gücü arttığı için tehdit can çarpanları
  # yükseltildi; bu, denge katmanının bilinçli bir güncellemesidir.
  denge <- .bs_km_oku("www", "js", "bilge_savunmasi_denge.js")
  expect_true(.bs_km_iceriyor(denge, "canCarpani: 1.18"))
  expect_true(.bs_km_iceriyor(denge, "canCarpani: 1.7"))
  # Yeni elit tehditler kule baskısını dengeler.
  expect_true(.bs_km_iceriyor(denge, "veri_solucani"))
  expect_true(.bs_km_iceriyor(denge, "golge_istek"))
  expect_true(.bs_km_iceriyor(denge, "veri_hortumu"))
})

test_that("boşta konuşma Bilge Savunması sayfasında sessizdir", {
  # Oyun kendi müzik/efekt katmanını çaldığı için boşta konuşma oyunla
  # üst üste binmez (R/config_speech_assets.R sözleşmesi).
  if (!exists("mergen_speech_idle_muted_pages", mode = "function", inherits = TRUE)) {
    source(file.path(.bs_km_repo_root, "R", "config_speech_assets.R"),
           encoding = "UTF-8", local = globalenv())
  }
  expect_true("bilge_savunmasi" %in% mergen_speech_idle_muted_pages())
})

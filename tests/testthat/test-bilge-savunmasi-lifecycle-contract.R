# ==============================================================================
# Dosya Yolu: tests/testthat/test-bilge-savunmasi-lifecycle-contract.R
# Açıklama: Bilge Savunması yaşam döngüsü ve kablolama sözleşmeleri:
#           - başlangıç/karşılama ekranı OYUN BAŞLATMAZ (tembel başlatma),
#           - eski Bilge Yolaç mini oyunu tamamen emekli edildi,
#           - varlık manifesti/bölge/kaynak-manifesti kabloları doğru,
#           - oyun dosyaları dış ağ bağımlılığı içermez,
#           - MERGEN müziği oyun sayfasında owner tabanlı kısılır.
#           Statik sözleşme taramalarıdır; uygulama boot, DB, tarayıcı veya
#           ağ GEREKMEZ. Dosya okumaları Windows/VM-güvenli bayt yoludur.
# ==============================================================================

.bs_lc_repo_root <- resolve_repo_root_for_tests()

.bs_lc_oku <- function(...) {
  yol <- file.path(.bs_lc_repo_root, ...)
  ham <- readBin(yol, what = "raw", n = file.info(yol)$size)
  metin <- rawToChar(ham)
  iconv(metin, from = "UTF-8", to = "UTF-8", sub = "byte")
}

.bs_lc_iceriyor <- function(metin, kalip) {
  grepl(kalip, metin, fixed = TRUE, useBytes = TRUE)
}

.bs_lc_oyun_js <- c(
  "bilge_savunmasi_cekirdek.js", "bilge_savunmasi_denge.js",
  "bilge_savunmasi_haritalar.js", "bilge_savunmasi_dalga.js",
  "bilge_savunmasi_sim_kuleler.js", "bilge_savunmasi_sim.js",
  "bilge_savunmasi_varliklar.js", "bilge_savunmasi_cizim_zemin.js",
  "bilge_savunmasi_cizim.js",
  "bilge_savunmasi_efekt.js", "bilge_savunmasi_girdi.js",
  "bilge_savunmasi_hud.js", "bilge_savunmasi_ses.js",
  "bilge_savunmasi_sahne.js",
  "bilge_savunmasi_kopru.js", "bilge_savunmasi_menu.js",
  "bilge_savunmasi_sonuc.js", "bilge_savunmasi_dogrulama.js",
  "bilge_savunmasi_uygulama.js"
)

test_that("eski Bilge Yolaç mini oyunu tamamen emekli edildi", {
  eski_dosyalar <- c(
    "bilge_yolac_motor.js", "bilge_yolac_fizik.js", "bilge_yolac_varliklar.js",
    "bilge_yolac_seviye.js", "bilge_yolac_dunya.js", "bilge_yolac_karakterler.js",
    "bilge_yolac_cephanelik.js", "bilge_yolac_dusmanlar.js",
    "bilge_yolac_efektler.js", "bilge_yolac_arayuz.js",
    "bilge_yolac_etkilesim.js", "bilge_yolac_oyun.js", "bilge_yolac_kopru.js"
  )
  for (dosya in eski_dosyalar) {
    expect_false(
      file.exists(file.path(.bs_lc_repo_root, "www", "js", dosya)),
      info = paste0("Eski oyun dosyası kaldırılmış olmalı: ", dosya)
    )
  }

  # Eski oyun API'sine hiçbir çalışma zamanı dosyası başvurmaz.
  js_dosyalari <- list.files(file.path(.bs_lc_repo_root, "www", "js"),
                             pattern = "\\.js$", full.names = TRUE)
  for (yol in js_dosyalari) {
    icerik <- .bs_lc_oku("www", "js", basename(yol))
    for (eski_api in c("ccStartWelcome", "ccStopWelcome",
                       "ccUpdateWelcomeTheme", "window.BilgeYolac")) {
      expect_false(
        .bs_lc_iceriyor(icerik, eski_api),
        info = paste0(basename(yol), " eski oyun API'sini içermemeli: ", eski_api)
      )
    }
  }
})

test_that("yeni oyun dosyaları mevcut ve dış ağ bağımlılığı içermiyor", {
  for (dosya in .bs_lc_oyun_js) {
    yol <- file.path(.bs_lc_repo_root, "www", "js", dosya)
    expect_true(file.exists(yol), info = paste0("Oyun dosyası eksik: ", dosya))
    icerik <- .bs_lc_oku("www", "js", dosya)
    expect_false(
      .bs_lc_iceriyor(icerik, "http://") || .bs_lc_iceriyor(icerik, "https://"),
      info = paste0(dosya, " dış URL içermemeli (çevrimdışı/on-prem sözleşme)")
    )
  }
  expect_true(file.exists(file.path(
    .bs_lc_repo_root, "www", "css", "bilge_savunmasi.css"
  )))
})

test_that("varlık manifesti oyun grubunu, bölge sahipliğini ve sırayı taşır", {
  env <- new.env(parent = globalenv())
  sys.source(file.path(.bs_lc_repo_root, "R", "utils_safe_source.R"), envir = env)
  sys.source(file.path(.bs_lc_repo_root, "R", "config_ui_assets.R"), envir = env)
  sys.source(file.path(.bs_lc_repo_root, "R", "config_ui_asset_zones.R"), envir = env)

  grup <- env$ui_asset_js_groups$bilge_savunmasi
  expect_identical(basename(grup), .bs_lc_oyun_js)
  expect_true("bilge_savunmasi" %in% env$ui_asset_deferred_js_groups)
  expect_false("bilge_yolac" %in% names(env$ui_asset_js_groups))

  plan_gruplari <- vapply(env$ui_asset_js_render_plan,
                          function(x) x$group, character(1))
  expect_true("bilge_savunmasi" %in% plan_gruplari)

  # Kritik sıra: çekirdek her şeyden önce, orkestratör en sonda.
  kurallar <- env$ui_asset_js_order_rules
  ilkler <- vapply(kurallar, function(k) k[1], character(1))
  expect_true("js/bilge_savunmasi_cekirdek.js" %in% ilkler)
  sonlar <- vapply(kurallar, function(k) k[2], character(1))
  expect_true("js/bilge_savunmasi_uygulama.js" %in% sonlar)
  # Retro karşılama sahnesi piksel veri dosyasından sonra yüklenir.
  expect_true(any(ilkler == "js/claude_code_pixel_chars.js" &
                    sonlar == "js/bilge_yolac_karsilama.js"))

  bolge <- env$ui_asset_ownership_zones$bilge_yolac_oyun
  expect_identical(bolge$owner_seam, "bilge_yolac")
  expect_true("bilge_savunmasi" %in% bolge$js_groups)
  expect_true("css/bilge_savunmasi.css" %in% bolge$css)
  expect_true("js/bilge_yolac_karsilama.js" %in% bolge$js)
})

test_that("kaynak manifesti bilge_savunmasi bölümünü doğru sırayla taşır", {
  env <- new.env(parent = globalenv())
  sys.source(file.path(.bs_lc_repo_root, "R", "config_source_manifest.R"),
             envir = env)

  bolum <- env$source_manifest_sections$bilge_savunmasi
  expect_identical(bolum, c(
    "R/config_bilge_savunmasi.R",
    "R/helpers_bilge_savunmasi_validation.R",
    "R/helpers_db_bilge_savunmasi_cekirdek.R",
    "R/helpers_db_bilge_savunmasi_kosu.R",
    "R/helpers_db_bilge_savunmasi_topluluk.R",
    "R/module_bilge_savunmasi_ui.R",
    "R/module_bilge_savunmasi.R"
  ))
})

test_that("sayfa kablolaması tembel başlatma sözleşmesini korur", {
  # Navigasyon gözlemcisi yalnızca sekme açılınca page_opened gönderir.
  nav <- .bs_lc_oku("R", "server_observers_navigation.R")
  expect_true(.bs_lc_iceriyor(nav, "bilge_savunmasi_module-page_opened"))

  # Sunucu modülü page_opened olayını dinler; motor init'i buna bağlıdır.
  server_mod <- .bs_lc_oku("R", "module_bilge_savunmasi.R")
  expect_true(.bs_lc_iceriyor(server_mod, "input$page_opened"))
  expect_true(.bs_lc_iceriyor(server_mod, "bs-init"))
  expect_true(.bs_lc_iceriyor(server_mod, "bs_db_finalize_run"))

  # Orkestratör sunucu init olayını bekler; sekmeden ayrılınca durdurur.
  uygulama <- .bs_lc_oku("www", "js", "bilge_savunmasi_uygulama.js")
  expect_true(.bs_lc_iceriyor(uygulama, '"sunucu-init"'))
  expect_true(.bs_lc_iceriyor(uygulama, "cancelAnimationFrame"))
  expect_true(.bs_lc_iceriyor(uygulama, "shiny:inputchanged"))
  expect_true(.bs_lc_iceriyor(uygulama, "visibilitychange"))

  # MERGEN arka fon müziği owner tabanlı kısılır ve bırakılır: duck çağrısı
  # ses katmanındadır; orkestratör sayfa giriş/çıkışında ona delege eder.
  ses <- .bs_lc_oku("www", "js", "bilge_savunmasi_ses.js")
  expect_true(.bs_lc_iceriyor(ses, 'MusicManager.duck("oyun")'))
  expect_true(.bs_lc_iceriyor(ses, 'MusicManager.unduck("oyun")'))
  expect_true(.bs_lc_iceriyor(uygulama, "uygulamaMuzigiKis"))
  expect_true(.bs_lc_iceriyor(uygulama, "uygulamaMuzigiBirak"))

  # Öncü Uzman seçim ekranı koşu isteğinden önce gelir.
  expect_true(.bs_lc_iceriyor(uygulama, "secimEkraniAc"))
  menu <- .bs_lc_oku("www", "js", "bilge_savunmasi_menu.js")
  expect_true(.bs_lc_iceriyor(menu, "secimEkraniHtml"))
  expect_true(.bs_lc_iceriyor(menu, "data-bs-oncu"))

  # ui.R sekme ve menü kablosu (bayrak kapalıyken menüde görünmez).
  ui_icerik <- .bs_lc_oku("ui.R")
  expect_true(.bs_lc_iceriyor(ui_icerik, 'tabName = "bilge_savunmasi"'))
  expect_true(.bs_lc_iceriyor(ui_icerik, "bilge_savunmasi_enabled()"))

  # Sunucu kablosu bayrak korumalıdır.
  wiring <- .bs_lc_oku("R", "server_module_wiring.R")
  expect_true(.bs_lc_iceriyor(wiring, "bilge_savunmasi_server_fn"))
  expect_true(.bs_lc_iceriyor(wiring, "bilge_savunmasi_enabled()"))
})


test_that("DB koşu başlatma hatası kalıcılıksız oyunu engellemez", {
  # Regresyon: tablolar/kullanıcı mevcutken bs_db_start_run() NULL dönerse
  # oyun tamamen engellenmemeli; mevcut kalıcılıksız/serbest oyun yolu
  # korunmalı ve istemciye kalici = FALSE ile bs-kosu-basladi gitmelidir.
  server_mod <- .bs_lc_oku("R", "module_bilge_savunmasi.R")
  baslangic <- regexpr("input$bs_kosu_baslat", server_mod, fixed = TRUE)
  expect_true(baslangic > 0)
  # Pencere, haftalık değiştirici çözümleme bloğunu (bkz. "bs_db_get_season_by_id"
  # regresyon testi) de kapsayacak kadar geniştir.
  govde <- substr(server_mod, baslangic, baslangic + 2600L)

  expect_true(.bs_lc_iceriyor(govde, "bs_db_start_run("))
  expect_true(.bs_lc_iceriyor(govde, "bs-kosu-basladi"))
  expect_true(.bs_lc_iceriyor(govde, "kalici = !is.null(kosu)"))
  expect_false(.bs_lc_iceriyor(govde, "neden = \"kosu_kaydi\""))
})

test_that("retro karşılama sahnesi dekoratiftir ve oyun başlatmaz", {
  karsilama <- .bs_lc_oku("www", "js", "bilge_yolac_karsilama.js")

  # Görünürlük kapıları ve temiz durdurma zorunludur.
  expect_true(.bs_lc_iceriyor(karsilama, "cc-welcome-active"))
  expect_true(.bs_lc_iceriyor(karsilama, "cancelAnimationFrame"))
  expect_true(.bs_lc_iceriyor(karsilama, "prefers-reduced-motion"))
  expect_true(.bs_lc_iceriyor(karsilama, "MergenClaudeCodePixelCharsMini"))

  # Dekoratif sahne Shiny girdisi göndermez, oyun simülasyonuna dokunmaz.
  expect_false(.bs_lc_iceriyor(karsilama, "Shiny.setInputValue"))
  expect_false(.bs_lc_iceriyor(karsilama, "BilgeSavunmasi.sim"))

  # Çalışma Alanı karşılaması retro iskeleti ve oyun geçiş satırını taşır.
  cc_ui <- .bs_lc_oku("R", "module_claude_code_ui.R")
  expect_true(.bs_lc_iceriyor(cc_ui, "cc-welcome-retro"))
  expect_true(.bs_lc_iceriyor(cc_ui, "karsilama_sahne"))
  expect_true(.bs_lc_iceriyor(cc_ui, "data-bs-ac"))
  expect_true(.bs_lc_iceriyor(cc_ui, "cli_ipucu"))
})

test_that("oyun modülü UI iskeleti bayrak kapalıyken sakin karta düşer", {
  env <- new.env(parent = globalenv())
  sys.source(file.path(.bs_lc_repo_root, "R", "config_characters.R"), envir = env)
  sys.source(file.path(.bs_lc_repo_root, "R", "config_bilge_savunmasi.R"),
             envir = env)
  sys.source(file.path(.bs_lc_repo_root, "R", "module_bilge_savunmasi_ui.R"),
             envir = env)

  eski_opt <- getOption("mergen.bilge_savunmasi.enabled", default = NULL)
  on.exit(options(mergen.bilge_savunmasi.enabled = eski_opt), add = TRUE)

  options(mergen.bilge_savunmasi.enabled = TRUE)
  acik_html <- as.character(env$bilgeSavunmasiUI("bilge_savunmasi_module"))
  expect_true(grepl("bilge_savunmasi_module-canvas_kabi", acik_html, fixed = TRUE))
  expect_true(grepl("bilge_savunmasi_module-menu_gorunumu", acik_html, fixed = TRUE))
  expect_true(grepl("Bilgi Çekirdeği", acik_html, fixed = TRUE))
  # İskelet hiçbir satır içi script/oyun başlatma içermez.
  expect_false(grepl("<script", acik_html, fixed = TRUE))

  options(mergen.bilge_savunmasi.enabled = FALSE)
  kapali_html <- as.character(env$bilgeSavunmasiUI("bilge_savunmasi_module"))
  expect_true(grepl("bs-sayfa-kapali", kapali_html, fixed = TRUE))
  expect_false(grepl("canvas_kabi", kapali_html, fixed = TRUE))
})

test_that("Devam Et isteği harita/zorluk/plan_id alanlarını istek.devam altından düzleştirir", {
  # Regresyon: kosuIstegiGonder() yalnızca üst seviye istek.harita/
  # istek.zorluk/istek.plan_id okursa, "Devam Et" akışı (istek.devam altında
  # taşınan alanlar) sunucuya boş harita/zorluk/plan kimliği gönderir; sunucu
  # istek çözücüsü bunu harita_zorluk/plan_kimligi ile reddeder ya da
  # (haftalık modda) sessizce yeni bir koşu başlatır.
  uygulama <- .bs_lc_oku("www", "js", "bilge_savunmasi_uygulama.js")
  expect_true(.bs_lc_iceriyor(uygulama, "function kosuIstegiGonder"))
  expect_true(.bs_lc_iceriyor(uygulama, "var devam = istek.devam"))
  expect_true(.bs_lc_iceriyor(uygulama, "devam.harita"))
  expect_true(.bs_lc_iceriyor(uygulama, "devam.zorluk"))
  expect_true(.bs_lc_iceriyor(uygulama, "devam.plan_id"))

  # Düzleştirilecek sezon_id/plan_id sunucu tarafında da mevcut olmalı;
  # aksi halde istemcinin düzleştirebileceği bir plan_id hiç gelmez.
  kosu_helper <- .bs_lc_oku("R", "helpers_db_bilge_savunmasi_kosu.R")
  expect_true(.bs_lc_iceriyor(kosu_helper, "bs_db_active_run"))
  expect_true(.bs_lc_iceriyor(kosu_helper, "BlueprintID"))
})

test_that("sekmeden ayrılınca belge düzeyindeki klavye dinleyicisi çözülür ve dönüşte yeniden bağlanır", {
  # Regresyon: BS.girdi.bagla() belge (document) düzeyinde bir "keydown"
  # dinleyicisi kurar (Boşluk/F/Esc/1-5, e.preventDefault() ile). Oyun
  # sekmesinden ayrılınca yalnızca RAF döngüsü durdurulursa bu dinleyici
  # etkin kalır ve diğer uygulama sayfalarında normal klavye davranışını
  # bozar. sayfadanAyrildi() kosu.girdi.coz() çağırmalı; sayfayaDonuldu()
  # aynı canvas/sim/arayuz ile yeniden BS.girdi.bagla() çağırmalıdır.
  uygulama <- .bs_lc_oku("www", "js", "bilge_savunmasi_uygulama.js")

  ayrildi_baslangic <- regexpr("function sayfadanAyrildi", uygulama, fixed = TRUE)
  expect_true(ayrildi_baslangic > 0)
  donuldu_baslangic <- regexpr("function sayfayaDonuldu", uygulama, fixed = TRUE)
  expect_true(donuldu_baslangic > 0)

  ayrildi_govdesi <- substr(uygulama, ayrildi_baslangic,
                            ayrildi_baslangic + 700L)
  # Pencere, sayfayaDonuldu başına eklenen oyun-müziği sürdürme satırını da
  # kapsayacak kadar geniştir (BS.ses.muzikSurdur() + açıklama).
  donuldu_govdesi <- substr(uygulama, donuldu_baslangic,
                            donuldu_baslangic + 600L)

  expect_true(.bs_lc_iceriyor(ayrildi_govdesi, "kosu.girdi.coz()"))
  expect_true(.bs_lc_iceriyor(ayrildi_govdesi, "kosu.girdi = null"))
  expect_true(.bs_lc_iceriyor(donuldu_govdesi, "BS.girdi.bagla("))
})

test_that("menüye dönüş ilerlemeyi (profil/kampanya/kahraman/başarım) tam sayfa init beklemeden tazeler", {
  # Regresyon: kalıcı bir kampanya koşusu sonuçlandıktan sonra menüye
  # dönüşte yalnızca liderlik/topluluk isteniyordu; profil/kampanya/
  # kahraman/başarım verisi BS.veri.init'te BAYAT kalıyor ve bir sonraki
  # harita ya da gelişmiş zorluk sekme yeniden açılana kadar kilitli
  # görünebiliyordu.
  server_mod <- .bs_lc_oku("R", "module_bilge_savunmasi.R")
  expect_true(.bs_lc_iceriyor(server_mod, "input$bs_profil_yenile"))
  expect_true(.bs_lc_iceriyor(server_mod, "bs-profil"))
  expect_true(.bs_lc_iceriyor(server_mod, ".bs_srv_profil_yuku"))

  kopru <- .bs_lc_oku("www", "js", "bilge_savunmasi_kopru.js")
  expect_true(.bs_lc_iceriyor(kopru, "profilYenileIste"))
  expect_true(.bs_lc_iceriyor(kopru, '["bs-profil", "sunucu-profil"]'))

  uygulama <- .bs_lc_oku("www", "js", "bilge_savunmasi_uygulama.js")
  expect_true(.bs_lc_iceriyor(uygulama, '"sunucu-profil"'))
  expect_true(.bs_lc_iceriyor(uygulama, "function menuyeDonVeTazele"))

  menuyedon_baslangic <- regexpr("function menuyeDonVeTazele", uygulama, fixed = TRUE)
  expect_true(menuyedon_baslangic > 0)
  menuyedon_govdesi <- substr(uygulama, menuyedon_baslangic, menuyedon_baslangic + 400L)
  expect_true(.bs_lc_iceriyor(menuyedon_govdesi, "BS.kopru.liderlikIste()"))
  expect_true(.bs_lc_iceriyor(menuyedon_govdesi, "BS.kopru.toplulukIste()"))
  expect_true(.bs_lc_iceriyor(menuyedon_govdesi, "BS.kopru.profilYenileIste()"))
})

test_that("haftalık koşuda değiştirici KOŞUNUN KENDİ sezonundan çözülür, istemcinin şimdiki haftasından değil", {
  # Regresyon: hafta dönümünden sonra devam edilen eski bir haftalık koşu,
  # istemcinin BS.veri.init.haftalik.degistirici (şimdiki hafta) alanına
  # bakıldığı için yanlış (yeni haftanın) değiştiricisiyle oynanabiliyordu.
  server_mod <- .bs_lc_oku("R", "module_bilge_savunmasi.R")
  baslangic <- regexpr("input$bs_kosu_baslat", server_mod, fixed = TRUE)
  expect_true(baslangic > 0)
  govde <- substr(server_mod, baslangic, baslangic + 3200L)
  expect_true(.bs_lc_iceriyor(govde, "bs_db_get_season_by_id(etkin_sezon_id)"))
  expect_true(.bs_lc_iceriyor(govde, "degistirici = degistirici"))

  topluluk_helper <- .bs_lc_oku("R", "helpers_db_bilge_savunmasi_topluluk.R")
  expect_true(.bs_lc_iceriyor(topluluk_helper, "degistirici = yapilandirma$degistirici"))

  uygulama <- .bs_lc_oku("www", "js", "bilge_savunmasi_uygulama.js")
  expect_true(.bs_lc_iceriyor(uygulama, "veri.degistirici.id"))
  expect_false(.bs_lc_iceriyor(uygulama, "BS.veri.init.haftalik.degistirici.id"))
})

test_that("Devam Et tüketildiğinde bayat devam bandı her zaman temizlenir (kontrol noktası olsun ya da olmasın)", {
  # Regresyon: kontrol noktası olmayan bir devam tüketildiğinde
  # BS.veri.init.devam null'lanmıyor, .bs-devam-karti DOM'da kalıyordu; bu
  # bayat kart menüye dönüşte yeniden görünür ve tıklanınca BS.veri.init.
  # devam.mod'a boş referansla çöker ya da kapalı bir jetonu yeniden
  # kullanmayı dener.
  uygulama <- .bs_lc_oku("www", "js", "bilge_savunmasi_uygulama.js")

  expect_false(.bs_lc_iceriyor(
    uygulama, "if (istek.devam && istek.devam.kontrol_durum) {"
  ))

  baslangic <- regexpr("if (istek.devam) {", uygulama, fixed = TRUE)
  expect_true(baslangic > 0)
  govde <- substr(uygulama, baslangic, baslangic + 600L)
  expect_true(.bs_lc_iceriyor(govde, "istek.devam.kontrol_durum"))
  expect_true(.bs_lc_iceriyor(govde, "BS.veri.init.devam = null"))
  expect_true(.bs_lc_iceriyor(govde, "bs-devam-karti"))
  expect_true(.bs_lc_iceriyor(govde, "devamKarti.remove()"))

  kontrol_konumu <- regexpr("istek.devam.kontrol_durum", govde, fixed = TRUE)
  temizlik_konumu <- regexpr("BS.veri.init.devam = null", govde, fixed = TRUE)
  expect_true(kontrol_konumu > 0 && temizlik_konumu > 0)
  expect_true(kontrol_konumu < temizlik_konumu)
})

test_that("koşu bitmeden çıkışta (cikis-evet) aktif koşu bırakılmaz; kontrol noktası devam edilebilir kalır", {
  # Regresyon: "Koşudan çıkılsın mı? Kaydedilen son kontrol noktasından
  # devam edebilirsin." onayından sonra sunucuya kosuBirak() gönderiliyordu;
  # bu, koşuyu Bırakıldı yapıyor ve bs_db_active_run() artık onu
  # döndürmediği için onay metnindeki devam vaadini kırıyordu.
  uygulama <- .bs_lc_oku("www", "js", "bilge_savunmasi_uygulama.js")

  cikis_baslangic <- regexpr('komut === "cikis-evet"', uygulama, fixed = TRUE)
  expect_true(cikis_baslangic > 0)
  menudon_baslangic <- regexpr('komut === "menu-don"', uygulama, fixed = TRUE)
  expect_true(menudon_baslangic > 0)
  expect_true(cikis_baslangic < menudon_baslangic)

  cikis_govdesi <- substr(uygulama, cikis_baslangic, menudon_baslangic)
  expect_false(.bs_lc_iceriyor(cikis_govdesi, "BS.kopru.kosuBirak"))
  expect_true(.bs_lc_iceriyor(cikis_govdesi, "menuyeDonVeTazele()"))

  menudon_govdesi <- substr(uygulama, menudon_baslangic, menudon_baslangic + 200L)
  expect_true(.bs_lc_iceriyor(menudon_govdesi, "BS.kopru.kosuBirak(kosu.kosuId)"))
  expect_true(.bs_lc_iceriyor(menudon_govdesi, "menuyeDonVeTazele()"))
})

test_that("plan modunda devam isteği plan silindiğinde bile aktif koşudan çözülür (sunucu koruması)", {
  # Regresyon: plan sahibi bir denemeyi sürerken planı silerse, hâlâ etkin
  # ve kontrol noktalı devam isteği plan_bulunamadi ile reddediliyordu.
  server_mod <- .bs_lc_oku("R", "module_bilge_savunmasi.R")
  plan_baslangic <- regexpr('identical(mod, "plan")', server_mod, fixed = TRUE)
  expect_true(plan_baslangic > 0)
  govde <- substr(server_mod, plan_baslangic, plan_baslangic + 1400L)
  expect_true(.bs_lc_iceriyor(govde, "bs_db_active_run(uid)"))
  expect_true(.bs_lc_iceriyor(govde, "identical(aktif$kosu_id, istek_kosu_id)"))

  koruma_konumu <- regexpr("bs_db_active_run(uid)", govde, fixed = TRUE)
  plan_bulunamadi_konumu <- regexpr('"plan_bulunamadi"', govde, fixed = TRUE)
  expect_true(koruma_konumu > 0 && plan_bulunamadi_konumu > 0)
  expect_true(koruma_konumu < plan_bulunamadi_konumu)
})

test_that("sonuçlandırma UPDATE'leri Status = Aktif koşuluyla korunur (atomik iddia)", {
  # Regresyon: eşzamanlı iki sonuçlandırma isteği aynı Aktif satırı görüp
  # ikisi de koşulsuz UPDATE ile eşleşebiliyor, kampanya/kahraman/profil/
  # başarım ödülleri İKİNCİ KEZ uygulanabiliyordu.
  kosu_helper <- .bs_lc_oku("R", "helpers_db_bilge_savunmasi_kosu.R")
  expect_true(.bs_lc_iceriyor(kosu_helper, "AND Status = ?"))
  expect_true(.bs_lc_iceriyor(kosu_helper, "guncellenen == 0L"))
  expect_true(.bs_lc_iceriyor(kosu_helper, "guncellenen_red == 0L"))
})

test_that("sekmeye dönüşte bitmiş koşunun sonuç kaplaması duraklatma ile üzerine yazılmaz", {
  # Regresyon: sekmeden ayrılıp bitmiş bir koşuya (sonuç kaplaması açıkken)
  # dönüldüğünde sayfayaDonuldu() her zaman duraklatGoster() çağırıyor,
  # "Menüye Dön"/"Planı Yayınla" gibi doğrulanmış sonuç eylemlerini
  # gizliyordu.
  uygulama <- .bs_lc_oku("www", "js", "bilge_savunmasi_uygulama.js")
  baslangic <- regexpr("function sayfayaDonuldu", uygulama, fixed = TRUE)
  expect_true(baslangic > 0)
  govde <- substr(uygulama, baslangic, baslangic + 900L)
  expect_true(.bs_lc_iceriyor(govde, "kosu.sim.durum.bitti"))
  expect_true(.bs_lc_iceriyor(govde, "kosu.hud.duraklatGoster()"))

  koruma_konumu <- regexpr("!kosu.sim.durum.bitti", govde, fixed = TRUE)
  duraklat_konumu <- regexpr("kosu.hud.duraklatGoster()", govde, fixed = TRUE)
  expect_true(koruma_konumu > 0 && duraklat_konumu > 0)
  expect_true(koruma_konumu < duraklat_konumu)
})

test_that("sekme aktif değilken gelen koşu başlatma yanıtı oyun kaynağı oluşturmaz", {
  # Regresyon: kullanıcı koşu başlattıktan hemen sonra başka bir sekmeye
  # geçerse, sunucunun asenkron "sunucu-kosu-basladi" yanıtı sekme zaten
  # pasifken gelebilir. Bu durumda canvas/klavye dinleyicisi/geri sayım/
  # müzik OLUŞTURULMAMALI; kalıcı bir koşu açıldıysa hemen bırakılmalıdır.
  uygulama <- .bs_lc_oku("www", "js", "bilge_savunmasi_uygulama.js")

  baslangic <- regexpr('BS.olaylar.ekle("sunucu-kosu-basladi"', uygulama, fixed = TRUE)
  expect_true(baslangic > 0)
  # Canvas/girdi bağlama satırlarını da kapsayacak kadar geniş bir pencere
  # (bu olay kaydı, koşu nesnesini kurana kadar yaklaşık 3000 karakter sürer;
  # haftalık değiştirici çözümleme ve devam bandı temizleme blokları da bu
  # aralıktadır).
  govde <- substr(uygulama, baslangic, baslangic + 3200L)

  expect_true(.bs_lc_iceriyor(govde, "!uygulama.sayfadaMi"))
  expect_true(.bs_lc_iceriyor(govde, "BS.kopru.kosuBirak(veri.kosu_id)"))

  # Koruma, canvas/girdi oluşturmadan (BS.cizim.olustur / BS.girdi.bagla)
  # ÖNCE gelmelidir.
  koruma_konumu <- regexpr("!uygulama.sayfadaMi", govde, fixed = TRUE)
  cizim_konumu <- regexpr("BS.cizim.olustur(kap", govde, fixed = TRUE)
  girdi_konumu <- regexpr("BS.girdi.bagla(cizici", govde, fixed = TRUE)
  expect_true(koruma_konumu > 0 && cizim_konumu > 0 && girdi_konumu > 0)
  expect_true(koruma_konumu < cizim_konumu)
  expect_true(koruma_konumu < girdi_konumu)
})

test_that("sonuç doğrulaması sınırlı zaman aşımı, tekrar deneme ve bayat yanıt korumasıyla çalışır", {
  # Regresyon: "Zafer! Sonuç sunucuda doğrulanıyor..." kaplaması, sunucu
  # yanıtı hiç gelmezse süresiz asılı kalıyordu. Doğrulama artık sınırlı bir
  # zamanlayıcıyla bekler, zaman aşımında idempotent "Tekrar Dene" sunar,
  # geç/yinelenen yanıtları yok sayar ve koşu kimliği eşleşmeyen bayat
  # yanıtların yeni koşuyu ezmesini engeller.
  dogrulama <- .bs_lc_oku("www", "js", "bilge_savunmasi_dogrulama.js")
  uygulama <- .bs_lc_oku("www", "js", "bilge_savunmasi_uygulama.js")

  expect_true(.bs_lc_iceriyor(dogrulama, "ZAMAN_ASIMI_MS"))
  expect_true(.bs_lc_iceriyor(dogrulama, 'data-bs-komut="dogrulama-tekrar"'))
  expect_true(.bs_lc_iceriyor(uygulama, 'komut === "dogrulama-tekrar"'))
  expect_true(.bs_lc_iceriyor(uygulama, "BS.dogrulama.gonder(kosu)"))

  # Zaman aşımı geri çağrısı koşu değişimini ve geç yanıtı denetler.
  zaman_baslangic <- regexpr("kosu.dogrulamaZamanlayici = setTimeout",
                             dogrulama, fixed = TRUE)
  expect_true(zaman_baslangic > 0)
  zaman_govde <- substr(dogrulama, zaman_baslangic, zaman_baslangic + 900L)
  expect_true(.bs_lc_iceriyor(zaman_govde, "BS.uygulama.kosu !== kosu"))
  expect_true(.bs_lc_iceriyor(zaman_govde, "kosu.sonSonuc"))

  # Sonuç işleyicisi: bayat kimlik + yinelenen yanıt korumaları, zamanlayıcı
  # temizliğinden ve gösterimden ÖNCE gelir. Kimliksiz (null) sonuc.kosu_id de
  # aktif koşunun bilinen bir kosuId'si varken bayat sayılıp reddedilmelidir
  # (Codex PR #636 P2 2. tur: "Reject result messages that lack the active
  # run id"); ayrıntılı davranış test-bilge-savunmasi-dogrulama-behavior.R'de.
  sonuc_baslangic <- regexpr('BS.olaylar.ekle("sunucu-kosu-sonuc"',
                             dogrulama, fixed = TRUE)
  expect_true(sonuc_baslangic > 0)
  sonuc_govde <- substr(dogrulama, sonuc_baslangic, sonuc_baslangic + 1100L)
  expect_true(.bs_lc_iceriyor(sonuc_govde, "kosu.kosuId != null"))
  expect_true(.bs_lc_iceriyor(sonuc_govde, "sonuc.kosu_id == null"))
  expect_true(.bs_lc_iceriyor(sonuc_govde, "Number(sonuc.kosu_id) !== Number(kosu.kosuId)"))
  expect_true(.bs_lc_iceriyor(sonuc_govde, "if (kosu.sonSonuc) return;"))
  expect_true(.bs_lc_iceriyor(sonuc_govde, "zamanlayiciDurdur(kosu)"))
  kimlik_konumu <- regexpr("kosu.kosuId != null", sonuc_govde, fixed = TRUE)
  goster_konumu <- regexpr("BS.sonuc.goster", sonuc_govde, fixed = TRUE)
  expect_true(kimlik_konumu > 0 && goster_konumu > 0)
  expect_true(kimlik_konumu < goster_konumu)

  # Koşu yok edilirken (yeniden başlatma/menüye dönüş/gezinme) doğrulama
  # zamanlayıcısı da temizlenir.
  yoket_baslangic <- regexpr("function kosuYokEt()", uygulama, fixed = TRUE)
  expect_true(yoket_baslangic > 0)
  yoket_govde <- substr(uygulama, yoket_baslangic, yoket_baslangic + 600L)
  expect_true(.bs_lc_iceriyor(yoket_govde, "BS.dogrulama.zamanlayiciDurdur(kosu)"))

  # Sunucu, sonuca koşu kimliğini ekler (istemci bayat yanıt eşleştirmesi).
  server_mod <- .bs_lc_oku("R", "module_bilge_savunmasi.R")
  expect_true(.bs_lc_iceriyor(server_mod, "sonuc$kosu_id <- kosu_id"))
})

test_that("bilgi balonu (öğretici/patron) sahneyi karartmaz ve kapanınca kaplamayı serbest bırakır", {
  # Regresyon: patron bilgi balonu bs-kaplama-acik sınıfını ekliyor, balon
  # kaldırılınca sınıf kalıyordu; sahne patron ölene kadar karartılmış ve
  # tıklamaya kapalı kalıyordu. Balon artık saydam kaplama modunda gösterilir
  # ve panel yokken kapanışta kaplamayı tamamen serbest bırakır.
  hud <- .bs_lc_oku("www", "js", "bilge_savunmasi_hud.js")

  ogretici_baslangic <- regexpr("hud.ogreticiGoster = function",
                                hud, fixed = TRUE)
  expect_true(ogretici_baslangic > 0)
  ogretici_govde <- substr(hud, ogretici_baslangic, ogretici_baslangic + 1400L)
  expect_true(.bs_lc_iceriyor(ogretici_govde, "bs-kaplama-saydam"))
  expect_true(.bs_lc_iceriyor(ogretici_govde, "bs-kaplama-panel"))
  expect_true(.bs_lc_iceriyor(ogretici_govde, 'data-bs-komut="ogretici-kapat"'))

  # Gerçek panel açılışı saydam modu sıfırlar; kapanış her iki sınıfı da siler.
  expect_true(.bs_lc_iceriyor(hud, '"bs-kaplama-saydam");'))

  css <- .bs_lc_oku("www", "css", "bilge_savunmasi.css")
  expect_true(.bs_lc_iceriyor(css, ".bs-oyun-kaplama.bs-kaplama-saydam"))
  expect_true(.bs_lc_iceriyor(css, "pointer-events: none;"))

  uygulama <- .bs_lc_oku("www", "js", "bilge_savunmasi_uygulama.js")
  expect_true(.bs_lc_iceriyor(uygulama, 'komut === "ogretici-kapat"'))
})

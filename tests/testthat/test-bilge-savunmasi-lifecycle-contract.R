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
  "bilge_savunmasi_sim.js", "bilge_savunmasi_cizim.js",
  "bilge_savunmasi_efekt.js", "bilge_savunmasi_girdi.js",
  "bilge_savunmasi_hud.js", "bilge_savunmasi_ses.js",
  "bilge_savunmasi_kopru.js", "bilge_savunmasi_menu.js",
  "bilge_savunmasi_sonuc.js", "bilge_savunmasi_uygulama.js"
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
  govde <- substr(server_mod, baslangic, baslangic + 2200L)

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
  donuldu_govdesi <- substr(uygulama, donuldu_baslangic,
                            donuldu_baslangic + 400L)

  expect_true(.bs_lc_iceriyor(ayrildi_govdesi, "kosu.girdi.coz()"))
  expect_true(.bs_lc_iceriyor(ayrildi_govdesi, "kosu.girdi = null"))
  expect_true(.bs_lc_iceriyor(donuldu_govdesi, "BS.girdi.bagla("))
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
  # (bu olay kaydı, koşu nesnesini kurana kadar yaklaşık 2000 karakter sürer).
  govde <- substr(uygulama, baslangic, baslangic + 2200L)

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

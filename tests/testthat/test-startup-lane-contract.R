# ==============================================================================
# Dosya Yolu: tests/testthat/test-startup-lane-contract.R
# Açıklama: Başlangıç deneyimi şeridi (Hızlı Başlangıç / Zengin Deneyim)
#           statik sözleşme testleri. İki şerit modelinin parçalarını korur:
#
#           1) İlk açılış şerit seçicisi: koyu, iki kartlı, medyasız
#           2) Hızlı şerit: sohbet-kabuğu hazır-olma sözleşmesi; intro/medya/
#              müzik atlanır; hiçbir özellik silinmez
#           3) Zengin şerit: mevcut sinematik akış korunur; ilerleme ekranı
#              alt-ilerleme/etkin-aşama metni kazanır
#           4) Sinematik başlangıç yüzeyleri HER ZAMAN koyu (tema kilidi)
#           5) Ayarlar entegrasyonu: Yapılandırma kartı + Kişiselleştirme notu
#
#           Testler statiktir: tarayıcı/DB/LLM/ağ GEREKMEZ. Dosyalar Windows
#           VM güvenli bayt-okuma deseniyle taranır.
# ==============================================================================

.startup_lane_repo_root <- function() {
  resolve_repo_root_for_tests()
}

.read_repo_text_startup_lane <- function(rel_path) {
  full_path <- file.path(.startup_lane_repo_root(), rel_path)
  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    # BOŞ DOSYA DA VACUOUS GEÇİRİR: bu dosyalardaki taramaların çoğu
    # `expect_false(grepl(...))` biçimindedir ve boş dize hepsini karşılar.
    stop(sprintf("Kaynak dosya BOŞ ya da okunamıyor: %s", full_path), call. = FALSE)
  }
  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )
  if (is.na(txt)) txt <- ""
  enc2utf8(gsub("\r\n?|\r", "\n", txt, perl = TRUE))
}

.startup_lane_has <- function(txt, pattern) {
  grepl(pattern, txt, fixed = TRUE, useBytes = TRUE)
}

# ------------------------------------------------------------------------------
# 1) İlk açılış şerit seçicisi
# ------------------------------------------------------------------------------

testthat::test_that("appLoadingUI ilk açılış şerit seçicisini iki kartla üretir", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("jsonlite")
  suppressMessages(library(shiny))

  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  source(
    file.path(.startup_lane_repo_root(), "R", "module_app_loading.R"),
    encoding = "UTF-8",
    local = env
  )

  ui <- withr::with_dir(.startup_lane_repo_root(), env$appLoadingUI())
  html <- paste(as.character(ui), collapse = "\n")

  # Seçici kökü: varsayılan gizli, erişilebilir diyalog
  testthat::expect_true(grepl('id="mergen-lane-select"', html, fixed = TRUE))
  testthat::expect_true(grepl('hidden="hidden"', html, fixed = TRUE))
  testthat::expect_true(grepl('role="dialog"', html, fixed = TRUE))

  # Tam olarak iki birincil kart: Hızlı Başlangıç + Zengin Deneyim
  kart_sayisi <- length(gregexpr('class="mlane-card"', html, fixed = TRUE)[[1]])
  testthat::expect_identical(kart_sayisi, 2L)
  testthat::expect_true(grepl('data-lane="fast_lane"', html, fixed = TRUE))
  testthat::expect_true(grepl('data-lane="rich_lane"', html, fixed = TRUE))
  testthat::expect_true(grepl("Hızlı Başlangıç", html, fixed = TRUE))
  testthat::expect_true(grepl("Zengin Deneyim", html, fixed = TRUE))

  # Kart açıklamaları (ürün metni)
  testthat::expect_true(grepl("Doğrudan Ana Söyleşi'ye geç", html, fixed = TRUE))
  testthat::expect_true(grepl("sinematik açılışını", html, fixed = TRUE))

  # Klavye erişimi: kartlar buton rolü ve tabindex taşır
  testthat::expect_true(grepl('role="button"', html, fixed = TRUE))
  testthat::expect_true(grepl('tabindex="0"', html, fixed = TRUE))

  # Ortam varsayılanı istemciye gömülür
  testthat::expect_true(grepl("__mergenStartupLaneEnvDefault", html, fixed = TRUE))
})

testthat::test_that("şerit seçicisi ağır medya bağımlılığı içermez", {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  source(
    file.path(.startup_lane_repo_root(), "R", "module_app_loading.R"),
    encoding = "UTF-8",
    local = env
  )

  selector_html <- paste(as.character(env$app_loading_lane_selector_ui()), collapse = "\n")

  # Seçici işaretlemesi video/Three.js/persona medyası REFERANSI içermez;
  # ikonlar satır içi hafif SVG'dir.
  testthat::expect_false(grepl("<video", selector_html, fixed = TRUE))
  testthat::expect_false(grepl("three", tolower(selector_html), fixed = TRUE))
  testthat::expect_false(grepl(".mp4", selector_html, fixed = TRUE))
  testthat::expect_false(grepl("characters/", selector_html, fixed = TRUE))
  testthat::expect_true(grepl("<svg", selector_html, fixed = TRUE))

  # Şerit çözümleyici betik, ilerleme denetleyicisinden ÖNCE gömülür.
  module_txt <- .read_repo_text_startup_lane("R/module_app_loading.R")
  lane_pos <- regexpr('js/app_loading_lane.js', module_txt, fixed = TRUE)
  main_pos <- regexpr('app_loading_asset("js/app_loading.js")', module_txt, fixed = TRUE)
  testthat::expect_true(lane_pos > 0 && main_pos > 0 && lane_pos < main_pos)
})

testthat::test_that("app_loading_lane.js şerit çözümleme sözleşmesini uygular", {
  txt <- .read_repo_text_startup_lane("www/js/app_loading_lane.js")
  testthat::expect_true(nzchar(txt))

  # Kalıcılık: mergen_settings.startup_lane anahtarı
  testthat::expect_true(.startup_lane_has(txt, "mergen_settings"))
  testthat::expect_true(.startup_lane_has(txt, "settings.startup_lane"))

  # Öncelik: kayıtlı tercih > ortam varsayılanı > seçici
  testthat::expect_true(.startup_lane_has(txt, "readStoredLane"))
  testthat::expect_true(.startup_lane_has(txt, "__mergenStartupLaneEnvDefault"))
  testthat::expect_true(.startup_lane_has(txt, "showSelector"))

  # Seçim kalıcıdır ve Shiny'e bildirilir
  testthat::expect_true(.startup_lane_has(txt, "persist: true"))
  testthat::expect_true(.startup_lane_has(txt, "startup_lane_resolved"))

  # Hızlı şeritte intro atlama sınıfları erken uygulanır; zengin şeride
  # dönüldüğünde skip-intro yalnızca gerçek kullanıcı tercihi varsa korunur.
  testthat::expect_true(.startup_lane_has(txt, "mergen-fast-lane"))
  testthat::expect_true(.startup_lane_has(txt, "mergen-skip-intro"))
  testthat::expect_true(.startup_lane_has(txt, "settingsSkipIntroEnabled"))
  testthat::expect_true(.startup_lane_has(txt, "settings.skip_intro === true"))
  testthat::expect_true(.startup_lane_has(txt, 'html.classList.remove("mergen-skip-intro")'))

  # Dış API yüzeyi
  testthat::expect_true(.startup_lane_has(txt, "window.MergenStartupLane"))
  testthat::expect_true(.startup_lane_has(txt, "whenResolved"))
  testthat::expect_true(.startup_lane_has(txt, "isSelectorOpen"))

  # Ayarlardan canlı şerit uygulama köprüsü
  testthat::expect_true(.startup_lane_has(txt, "applyStartupLane"))

  # Çözüm kaynağı protokolü: dağıtım varsayılanı kullanıcı tercihi olarak
  # sunucuya "stored/selector" gibi bildirilmez (Codex P2: env varsayılanının
  # kalıcılaşması). Seçici seçimi "selector", kayıtlı tercih "stored",
  # ortam varsayılanı "env_default" kaynağıyla gönderilir.
  testthat::expect_true(.startup_lane_has(txt, 'source: "selector"'))
  testthat::expect_true(.startup_lane_has(txt, 'source: "stored"'))
  testthat::expect_true(.startup_lane_has(txt, 'source: "env_default"'))

  # Seçici/çözümleyici video-Three.js ön yüklemesi başlatmaz
  testthat::expect_false(.startup_lane_has(txt, "createElement(\"video\")"))
  testthat::expect_false(.startup_lane_has(txt, "THREE."))
})

# ------------------------------------------------------------------------------
# 2) Hızlı şerit boot sözleşmesi
# ------------------------------------------------------------------------------

testthat::test_that("app_loading.js hızlı ve zengin şerit ilerleme sözleşmelerini ayırır", {
  txt <- .read_repo_text_startup_lane("www/js/app_loading.js")

  # Hızlı şerit kapanış anahtarları R yardımcının kümesiyle aynı olmalı
  # (mergen_fast_lane_required_boot_keys ile hizalı üç anahtar).
  testthat::expect_true(.startup_lane_has(txt, "FAST_LANE_REQUIRED"))
  testthat::expect_true(.startup_lane_has(
    txt, '["connect", "auth_ready", "welcome_client_ready"]'
  ))

  # Hızlı şerit yüzde planı ve kapanış kontrolü
  testthat::expect_true(.startup_lane_has(txt, "FAST_LANE_PCT"))
  testthat::expect_true(.startup_lane_has(txt, "maybeFinishFastLane"))
  testthat::expect_true(.startup_lane_has(txt, "isFastLane"))

  # Hızlı şeritte medya bandı ilerleme sözleşmesine dahil değildir
  testthat::expect_true(.startup_lane_has(txt, "if (isFastLane()) return;"))

  # Hızlı şeritte plan dışı kontrol noktaları (örn. ertelenen
  # character_media_ready) yüzde/etiket ilerletemez; çubuk zengin medya
  # bandına sıçrayamaz ve sohbet kabuğu aşamaları gölgelenemez (Codex P2).
  testthat::expect_true(.startup_lane_has(
    txt, 'if (isFastLane() && typeof FAST_LANE_PCT[key] !== "number")'
  ))

  # Zengin şerit alt-ilerleme sayaçları (ör. "4 / 12") ve etkin-aşama metni
  testthat::expect_true(.startup_lane_has(txt, "reportMediaProgress(fraction, done, total)"))
  testthat::expect_true(.startup_lane_has(txt, '" / "'))
  testthat::expect_true(.startup_lane_has(txt, "sürüyor"))

  # Seçici açıkken yalnızca boot-ready kapanışı ertelenir; ready=true
  # seçimi atlayıp kabuğu açamaz, ancak SSO/disconnect/watchdog emniyet
  # yolları gerektiğinde katmanı kapatabilir.
  testthat::expect_true(.startup_lane_has(txt, "laneSelectorOpen"))
  testthat::expect_true(.startup_lane_has(txt, "laneNeedsSelection"))
  testthat::expect_true(.startup_lane_has(txt, "pendingFinishUntilLaneResolved"))
  testthat::expect_true(.startup_lane_has(txt, "finish({ deferForLane: true })"))
  testthat::expect_true(.startup_lane_has(
    txt, "if (opts.deferForLane === true && !finished && (laneSelectorOpen() || laneNeedsSelection()))"
  ))
})

testthat::test_that("app_loading_media.js hızlı şeritte ön yüklemeyi erteler, zengin şeridi korur", {
  txt <- .read_repo_text_startup_lane("www/js/app_loading_media.js")

  # Şerit çözümüne göre başlatma
  testthat::expect_true(.startup_lane_has(txt, "startForLane"))
  testthat::expect_true(.startup_lane_has(txt, "whenResolved"))
  testthat::expect_true(.startup_lane_has(txt, "fast_lane_deferred"))

  # Zengin şerit davranışı korunur: seri tam-tampon + tek yetkili handler
  testthat::expect_true(.startup_lane_has(txt, "canplaythrough"))
  testthat::expect_true(.startup_lane_has(txt, "loadExploreAllCharVideos"))
  handler_kayit_sayisi <- length(gregexpr(
    'addCustomMessageHandler("loadExploreAllCharVideos"', txt, fixed = TRUE
  )[[1]])
  testthat::expect_identical(handler_kayit_sayisi, 1L)

  # Alt-ilerleme sayaçları ilerleme çubuğuna iletilir
  testthat::expect_true(.startup_lane_has(txt, "reportMediaProgress(frac, bufferedCount, totalKnown)"))
})

testthat::test_that("başlangıç şeridi sunucu gözlemcisi çözümü işler ve hızlı şeritte medyayı erteler", {
  lane_txt <- .read_repo_text_startup_lane("R/module_startup_lane.R")

  # Şerit gözlemcisi ve oturum durumu
  testthat::expect_true(.startup_lane_has(lane_txt, "input$startup_lane_resolved"))
  testthat::expect_true(.startup_lane_has(lane_txt, "session$userData$startup_lane"))
  testthat::expect_true(.startup_lane_has(lane_txt, "mergen_normalize_startup_lane"))

  # Hızlı şeritte character_media_ready 'ertelendi' olarak işaretlenir
  testthat::expect_true(.startup_lane_has(lane_txt, '"character_media_ready"'))
  testthat::expect_true(.startup_lane_has(lane_txt, "deferred = TRUE"))

  # Yalnızca gerçek kullanıcı tercihleri (stored/selector) ayar durumuna
  # yazılır; env_default kalıcılaştırılmaz (Codex P2). Sunucu köprüsü de
  # kaynağı (getSource) taşımalıdır; aksi halde kaynaksız yeniden gönderim
  # env varsayılanını kullanıcı tercihi gibi gösterirdi.
  testthat::expect_true(.startup_lane_has(lane_txt, 'c("stored", "selector")'))
  testthat::expect_true(.startup_lane_has(lane_txt, "user_choice"))
  testthat::expect_true(.startup_lane_has(lane_txt, "getSource"))
  lane_js <- .read_repo_text_startup_lane("www/js/app_loading_lane.js")
  testthat::expect_true(.startup_lane_has(lane_js, "getSource"))
  testthat::expect_true(.startup_lane_has(lane_js, "resolvedSource"))
  testthat::expect_true(.startup_lane_has(lane_js, 'resolvedSource = opts.source || "stored"'))

  # Şerit çözülmeden intro kararı gönderilmez; hızlı şerit intro'yu atlar
  testthat::expect_true(.startup_lane_has(lane_txt, "window.MergenStartupLane"))
  testthat::expect_true(.startup_lane_has(lane_txt, "lane === 'fast_lane' ? true"))

  # Başlangıç ekranı modülü şerit gözlemcilerini delege eder ve hızlı
  # şeritte açılış müziğini başlatmaz (katı varsayılan).
  screen_txt <- .read_repo_text_startup_lane("R/module_startup_screen.R")
  testthat::expect_true(.startup_lane_has(screen_txt, "startupLaneObserversInit(input, session, settings_data"))
  testthat::expect_true(.startup_lane_has(screen_txt, "fast_lane_active"))
  testthat::expect_true(.startup_lane_has(screen_txt, "if (!fast_lane_active)"))

  # Şerit kaynaklı atlama, kalıcı "Bir daha gösterme" (skip_intro/
  # show_intro_animation) tercihine dönüştürülmez (Codex P2): eski onay
  # kutusu senkronizasyonu yalnızca hızlı şerit AKTİF DEĞİLKEN yapılır.
  guard_pos <- regexpr("if (!fast_lane_active) {", screen_txt, fixed = TRUE)
  chk_pos <- regexpr('updateCheckboxInput(session, "settings_yapilandirma_module-show_intro_animation", value = FALSE)', screen_txt, fixed = TRUE)
  testthat::expect_true(guard_pos > 0 && chk_pos > 0 && guard_pos < chk_pos)
})

testthat::test_that("kayıtlı sohbet açılış yüklemesi şerit çözümüne kilitlidir", {
  startup_txt <- .read_repo_text_startup_lane("R/server_observers_startup.R")

  # Yarış düzeltmesi: karar şerit payload'ından verilir; erken auth/init
  # tetiklemesi şerit çözülmeden DB yüklemesi başlatamaz.
  testthat::expect_true(.startup_lane_has(startup_txt, "shiny::isolate(input$startup_lane_resolved)"))
  testthat::expect_true(.startup_lane_has(startup_txt, "lane_wait_registered"))
  # Eski yarışlı okuma geri gelmemeli: session$userData$startup_lane şerit
  # kararının kaynağı olamaz (istemci round-trip'i auth'tan geç kalabilir).
  testthat::expect_false(.startup_lane_has(
    startup_txt, "mergen_startup_lane_is_fast(session$userData$startup_lane)"
  ))

  # Hızlı şeritte ön izleme worker sarmalayıcısı ile kritik yol dışındadır;
  # tam liste açılışta değil tembel tetikleyici ile yüklenir.
  testthat::expect_true(.startup_lane_has(startup_txt, '"startup_saved_chats_preview"'))
  testthat::expect_true(.startup_lane_has(startup_txt, "saved_chats_full_pending"))

  # Tembel tam yükleme kimliği çalıştırma anında tekrar çözer.
  testthat::expect_true(.startup_lane_has(startup_txt, "run_user_id <- resolve_current_user_id()"))

  # Şerit API'si olmayan istemcide sunucu köprüsü kapıyı kilitlemez:
  # legacy rich_lane bildirimi her durumda gönderilir.
  lane_txt <- .read_repo_text_startup_lane("R/module_startup_lane.R")
  testthat::expect_true(.startup_lane_has(lane_txt, "legacy_no_api"))
})

testthat::test_that("hızlı şeritte karşılama hazır-olma kontrolü video beklemez", {
  txt <- .read_repo_text_startup_lane("R/server_welcome_handlers.R")
  testthat::expect_true(.startup_lane_has(txt, "mergen-fast-lane"))
  testthat::expect_true(.startup_lane_has(txt, "(fastLane || bgPlaying)"))
  # Zengin şeritte video-oynuyor koşulu korunur
  testthat::expect_true(.startup_lane_has(txt, "bgPlaying"))
  testthat::expect_true(.startup_lane_has(txt, "welcome_client_ready"))

  # Şerit seçici açıkken 12 sn backstop welcome_client_ready'yi erken
  # gönderemez: sayaç seçici kapanana dek bekletilir (Codex P2).
  testthat::expect_true(.startup_lane_has(txt, "needsSelection"))
  guard_pos <- regexpr("needsSelection", txt, fixed = TRUE)
  attempts_pos <- regexpr("attempts += 1;", txt, fixed = TRUE)
  testthat::expect_true(guard_pos > 0 && attempts_pos > 0 && guard_pos < attempts_pos)
})

testthat::test_that("hızlı şeritte modern karşılama video/neural başlatmaz ama selamlamayı korur", {
  txt <- .read_repo_text_startup_lane("www/js/modern_welcome_handler.js")
  testthat::expect_true(.startup_lane_has(txt, "mergen-fast-lane"))
  testthat::expect_true(.startup_lane_has(txt, "fastLaneWelcome"))

  # Şerit seçici açıkken (çözülmemiş şerit) ağır karşılama medyası
  # başlatılmaz; boot şerit çözüldüğünde yeniden denenir (Codex P2).
  testthat::expect_true(.startup_lane_has(txt, "needsSelection"))
  testthat::expect_true(.startup_lane_has(txt, "whenResolved"))
  testthat::expect_true(.startup_lane_has(txt, "laneDeferredBootPending"))
  # Hızlı dalda selamlama yine başlatılır (karşılama + hızlı eylemler kalır)
  testthat::expect_true(.startup_lane_has(txt, "window.WelcomeGreeting.init(greetingText)"))

  # CSS: statik premium koyu zemin + gizlenen video/neural
  css <- .read_repo_text_startup_lane("www/css/welcome_modern.css")
  testthat::expect_true(.startup_lane_has(css, "html.mergen-fast-lane .modern-welcome-video-container video"))
  testthat::expect_true(.startup_lane_has(css, "html.mergen-fast-lane .modern-welcome-neural-canvas"))

  # Derin uzay sahnesi hızlı şeritte hiç görünmez
  loading_css <- .read_repo_text_startup_lane("www/css/app_loading.css")
  testthat::expect_true(.startup_lane_has(loading_css, "html.mergen-fast-lane #deep-space-container"))
})

# ------------------------------------------------------------------------------
# 3) Zengin şerit korunumu (non-regression çapaları)
# ------------------------------------------------------------------------------

testthat::test_that("zengin şerit sinematik akışı eksiksiz kalır", {
  ui_txt <- .read_repo_text_startup_lane("R/module_startup_screen_ui.R")

  # Keşfet butonu, skip-intro onay kutusu, sürüm rozeti/modali
  testthat::expect_true(.startup_lane_has(ui_txt, '"explore-btn"'))
  testthat::expect_true(.startup_lane_has(ui_txt, "KEŞFET"))
  testthat::expect_true(.startup_lane_has(ui_txt, "skip-intro-checkbox"))
  testthat::expect_true(.startup_lane_has(ui_txt, "Bir daha gösterme"))
  testthat::expect_true(.startup_lane_has(ui_txt, "surum-modal-overlay"))

  # Üç deneyim modu kartı (Odak / Dinamik / Bütünleşik) ve karakter adımı
  testthat::expect_true(.startup_lane_has(ui_txt, '"Odak"'))
  testthat::expect_true(.startup_lane_has(ui_txt, '"Dinamik"'))
  testthat::expect_true(.startup_lane_has(ui_txt, '"Bütünleşik"'))
  testthat::expect_true(.startup_lane_has(ui_txt, "cinematic-character-step"))

  # Giriş müziği veri etiketi korunur
  testthat::expect_true(.startup_lane_has(ui_txt, "intro-music-data"))
})

# ------------------------------------------------------------------------------
# 4) Sinematik başlangıç koyu-tema kilidi
# ------------------------------------------------------------------------------

testthat::test_that("theme_manager.js sinematik koyu-tema kilidini uygular", {
  txt <- .read_repo_text_startup_lane("www/js/theme_manager.js")
  testthat::expect_true(.startup_lane_has(txt, "holdCinematicDark"))
  testthat::expect_true(.startup_lane_has(txt, "releaseCinematicDark"))
  testthat::expect_true(.startup_lane_has(txt, "isCinematicDarkHeld"))
  # Yaşam döngüsü sinyalleri body sınıflarından izlenir
  testthat::expect_true(.startup_lane_has(txt, "deep-space-active"))
  testthat::expect_true(.startup_lane_has(txt, "app-ready"))
  # Kilit bırakılınca kullanıcı teması geri uygulanır (pendingTheme)
  testthat::expect_true(.startup_lane_has(txt, "pendingTheme"))
  # get() kilit sırasında GÖRSEL 'dark' yerine kullanıcı temasını raporlar;
  # aksi halde mergen_theme_initial 'dark' bildirir ve sonraki kaydetme
  # açık tema tercihini kaybederdi (Codex P2).
  testthat::expect_true(.startup_lane_has(txt, "if (cinematicDarkHold && isValidTheme(pendingTheme))"))
})

testthat::test_that("sinematik başlangıç yüzeylerinde açık tema override'ı kalmaz", {
  # Başlangıç mod seçim modalı: theme_light_* zincirinde light kuralı olmamalı
  theme_files <- c(
    "www/css/theme_light_core.css",
    "www/css/theme_light_welcome.css",
    "www/css/theme_light_chat.css",
    "www/css/theme_light_modals.css",
    "www/css/theme_light_bilge_yolac.css",
    "www/css/theme_light_personalization.css",
    "www/css/theme_light_pages.css"
  )
  for (f in theme_files) {
    txt <- .read_repo_text_startup_lane(f)
    testthat::expect_false(
      .startup_lane_has(txt, 'html[data-theme="light"] .cinematic-modal'),
      info = paste0(f, " sinematik başlangıç modalına light override uygulayamaz.")
    )
    testthat::expect_false(
      .startup_lane_has(txt, 'html[data-theme="light"] .surum-modal-container'),
      info = paste0(f, " başlangıç Yenilikler modalına light override uygulayamaz.")
    )
  }

  # Bileşen CSS'i: başlangıç rozeti/modalının açık tema kabuğu kaldırıldı
  surum_txt <- .read_repo_text_startup_lane("www/css/surum_bilgilendirme.css")
  testthat::expect_false(
    .startup_lane_has(surum_txt, 'html[data-theme="light"] .surum-modal-container')
  )
  testthat::expect_false(
    .startup_lane_has(surum_txt, 'html[data-theme="light"] .deep-space-version-badge {')
  )
  testthat::expect_false(
    .startup_lane_has(surum_txt, 'html[data-theme="light"] #surum-modal-content')
  )
  # Destek > Yenilikler SAYFASI rozetleri açık temada okunur kalmaya devam eder
  # (CLAUDE.md 1E sözleşmesi): .destek-surum-tab light kuralları korunur.
  testthat::expect_true(
    .startup_lane_has(surum_txt, 'html[data-theme="light"] .destek-surum-tab')
  )
})

# ------------------------------------------------------------------------------
# 5) Ayarlar entegrasyonu
# ------------------------------------------------------------------------------

testthat::test_that("Yapılandırma Başlangıç Deneyimi kartını ve gözlemcisini içerir", {
  # Kompozitör kartı çağırır; kartın kendisi gelişmiş kart dosyasındadır.
  ui_txt <- .read_repo_text_startup_lane("R/module_settings_yapilandirma_ui.R")
  testthat::expect_true(.startup_lane_has(ui_txt, ".syap_startup_lane_card(ns)"))

  adv_txt <- .read_repo_text_startup_lane("R/module_settings_yapilandirma_advanced_ui.R")
  testthat::expect_true(.startup_lane_has(adv_txt, ".syap_startup_lane_card"))
  testthat::expect_true(.startup_lane_has(adv_txt, '"Başlangıç Deneyimi"'))
  testthat::expect_true(.startup_lane_has(adv_txt, "startup_experience_lane"))
  testthat::expect_true(.startup_lane_has(adv_txt, '"fast_lane"'))
  testthat::expect_true(.startup_lane_has(adv_txt, '"rich_lane"'))

  srv_txt <- .read_repo_text_startup_lane("R/module_settings_yapilandirma.R")
  testthat::expect_true(.startup_lane_has(srv_txt, "input$startup_experience_lane"))
  # BEKLEYEN-DURUM SÖZLEŞMESİ: radyo seçimi yalnızca temp_startup_lane'i
  # günceller; kalıcılaştırma/uygulama "Ayarları Kaydet" akışına aittir.
  # Anında saveSettings/applyStartupLane gönderimi geri GELMEMELİDİR.
  testthat::expect_true(.startup_lane_has(srv_txt, "temp_startup_lane"))
  testthat::expect_false(.startup_lane_has(srv_txt, 'saveSettings", list(startup_lane = lane)'))
  testthat::expect_false(.startup_lane_has(srv_txt, '"applyStartupLane"'))

  # Kaydetme uygulaması: yardımcı module_startup_lane.R içindedir ve koordinatör
  # save_all_settings akışından bekleyen değerle çağrılır.
  lane_srv_txt <- .read_repo_text_startup_lane("R/module_startup_lane.R")
  testthat::expect_true(.startup_lane_has(lane_srv_txt, "mergen_apply_saved_startup_lane"))
  testthat::expect_true(.startup_lane_has(lane_srv_txt, '"applyStartupLane"'))

  coord_txt <- .read_repo_text_startup_lane("R/module_settings.R")
  testthat::expect_true(.startup_lane_has(
    coord_txt,
    "mergen_apply_saved_startup_lane(session, settings, yapilandirma$temp_startup_lane())"
  ))
})

testthat::test_that("ayarlar koordinatörü şerit varsayılanını, yüklemeyi ve sıfırlamayı yönetir", {
  txt <- .read_repo_text_startup_lane("R/module_settings.R")
  # Varsayılan ask_once (ilk açılışta seçici)
  testthat::expect_true(.startup_lane_has(txt, 'startup_lane            = "ask_once"'))
  # localStorage'tan geri yükleme yalnızca kesin şeritleri kabul eder
  testthat::expect_true(.startup_lane_has(txt, 'loaded$startup_lane'))
  testthat::expect_true(.startup_lane_has(txt, 'c("fast_lane", "rich_lane")'))
  # Sıfırlama: kalıcı tercih ask_once kalır; radyo görünür varsayılana
  # (Zengin Deneyim) çekilir; seçimsiz radyo grubu belirsiz durum üretiyordu.
  testthat::expect_true(.startup_lane_has(txt, 'settings$startup_lane             <- "ask_once"'))
  testthat::expect_true(.startup_lane_has(txt, '"startup_experience_lane"), selected = "rich_lane"'))
  testthat::expect_true(.startup_lane_has(txt, 'applyStartupLane", list(lane = "rich_lane")'))
})

testthat::test_that("Kişiselleştirme hızlı şeritte Deneyim Modu kartlarını gizler, zengin şeritte gösterir", {
  kisisel_txt <- .read_repo_text_startup_lane("R/module_settings_kisisel.R")
  testthat::expect_true(.startup_lane_has(kisisel_txt, "fast-lane-mode-note"))
  testthat::expect_true(.startup_lane_has(kisisel_txt, "Hızlı Başlangıç etkin"))
  # Kartların kendisi silinmez (Zengin Deneyim'de görünür)
  testthat::expect_true(.startup_lane_has(kisisel_txt, "settings-mode-container"))

  css_txt <- .read_repo_text_startup_lane("www/css/settings_page.css")
  testthat::expect_true(.startup_lane_has(css_txt, "html.mergen-fast-lane .settings-mode-container"))
  testthat::expect_true(.startup_lane_has(css_txt, "html.mergen-fast-lane .fast-lane-mode-note"))
})

# ------------------------------------------------------------------------------
# 6) Manifest / varlık sahipliği
# ------------------------------------------------------------------------------

testthat::test_that("şerit yardımcıları manifest ve varlık sahipliğinde kayıtlıdır", {
  manifest_txt <- .read_repo_text_startup_lane("R/config_source_manifest.R")
  testthat::expect_true(.startup_lane_has(manifest_txt, '"R/helpers_startup_lane.R"'))
  testthat::expect_true(.startup_lane_has(manifest_txt, '"R/module_startup_lane.R"'))
  # Yardımcı, appLoadingUI'den önce yüklenmelidir
  helper_pos <- regexpr('"R/helpers_startup_lane.R"', manifest_txt, fixed = TRUE)
  loading_pos <- regexpr('"R/module_app_loading.R"', manifest_txt, fixed = TRUE)
  testthat::expect_true(helper_pos > 0 && loading_pos > 0 && helper_pos < loading_pos)

  zones_txt <- .read_repo_text_startup_lane("R/config_ui_asset_zones.R")
  testthat::expect_true(.startup_lane_has(zones_txt, '"js/app_loading_lane.js"'))

  report_txt <- .read_repo_text_startup_lane("tests/scripts/frontend_maintainability_report.R")
  testthat::expect_true(.startup_lane_has(report_txt, '"www/js/app_loading_lane.js"'))
})

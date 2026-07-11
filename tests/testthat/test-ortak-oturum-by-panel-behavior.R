# ==============================================================================
# Dosya Yolu: tests/testthat/test-ortak-oturum-by-panel-behavior.R
# Açıklama: Ortak Bilge Yolaç çalışma alanı panelinin davranış ve sözleşme
#           testleri. DB, LLM, tarayıcı veya ağ GEREKMEZ; saf yardımcılar
#           geçici dizinler ve stub'larla test edilir.
#
# Kapsanan sözleşmeler:
#   - Özel proje dizini izolasyon kapısı: yönetilen dosya kökleri (başka oda /
#     kişisel kova) reddedilir; odanın kendi kökü ve dış proje dizinleri geçer.
#   - Etkin çalışma dizini çözümü: geçerli özel dizin öncelikli, yoksa
#     paylaşılan otomatik oda klasörü.
#   - Panel iskeleti: varsayılan KAPALI sınıfı, kart/çıktı yuvaları, görünür
#     ve kullanılabilir Proje Dizini girdisi (yazma yetkisine göre) ve XSS
#     escape.
#   - Aç/kapa tercihinin korunması: iskelet yoklamaya bağlı DEĞİLDİR; JS
#     köprüsü tercihi sessionStorage'da saklar ve geri uygular.
#   - Uygulama geneli yerleşim sözleşmesi: oo-oda-acik-kok sınıfı SEKMEYE
#     DUYARLI merkez güncelleyiciyle yönetilir (başka sayfalar daralmaz).
#   - BilgeYolaç odalarında araç/belge bağlam kapıları (P2-C / P2-D).
# ==============================================================================

testthat::skip_if_not_installed("shiny")

suppressPackageStartupMessages(library(shiny))

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }

  source(file.path(repo_root, "R", "helpers_ortak_oturum_by_calisma_alani.R"),
         encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "module_ortak_oturum_belge_paneli.R"),
         encoding = "UTF-8", local = globalenv())
})

.oo_by_test_html <- function(tag) {
  paste(format(tag), collapse = "\n")
}

.oo_by_test_oku <- function(yol) {
  baytlar <- readBin(yol, what = "raw", n = file.info(yol)$size)
  iconv(rawToChar(baytlar), from = "UTF-8", to = "UTF-8", sub = "byte")
}

test_that("özel proje dizini kapısı yönetilen kökleri reddeder, oda kökünü ve dış dizinleri geçirir", {
  kok <- file.path(tempdir(), sprintf("oo_by_kok_%d", sample.int(99999L, 1L)))
  yukleme <- file.path(kok, "yuklemeler")
  oda_42 <- file.path(kok, "ortak_oturumlar", "oturum_42")
  oda_99 <- file.path(kok, "ortak_oturumlar", "oturum_99")
  dis_proje <- file.path(tempdir(), sprintf("oo_by_proje_%d", sample.int(99999L, 1L)))

  for (d in c(yukleme, file.path(oda_42, "calisma_alani"), oda_99, dis_proje)) {
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
  }
  on.exit(unlink(c(kok, dis_proje), recursive = TRUE, force = TRUE), add = TRUE)

  kokler <- c(kok, yukleme)

  # Boş yol reddedilir.
  expect_true(is.character(ortak_by_ozel_dizin_engeli("", 42L, yonetilen_kokler = kokler)))

  # Başka odanın çalışma alanı reddedilir (oda izolasyonu).
  engel_baska_oda <- ortak_by_ozel_dizin_engeli(
    oda_99, 42L,
    yonetilen_kokler = kokler, oda_koku = oda_42
  )
  expect_true(is.character(engel_baska_oda))
  expect_true(grepl("işaret edemez", engel_baska_oda, fixed = TRUE))

  # Kişisel yükleme kovası reddedilir.
  expect_true(is.character(ortak_by_ozel_dizin_engeli(
    file.path(yukleme, "user_7"), 42L,
    yonetilen_kokler = kokler, oda_koku = oda_42
  )))

  # Yönetilen kökün üst dizini de reddedilir: aksi halde proje ağacı başka oda
  # veya kullanıcı kovalarını kapsayıp Dizin İçeriği/ajan okumasına açabilir.
  engel_ust_kok <- ortak_by_ozel_dizin_engeli(
    dirname(kok), 42L,
    yonetilen_kokler = kokler, oda_koku = oda_42
  )
  expect_true(is.character(engel_ust_kok))
  expect_true(grepl("kapsayamaz", engel_ust_kok, fixed = TRUE))

  # Odanın kendi kökü altındaki yol serbesttir.
  expect_null(ortak_by_ozel_dizin_engeli(
    file.path(oda_42, "calisma_alani"), 42L,
    yonetilen_kokler = kokler, oda_koku = oda_42
  ))

  # Yönetilen kökler dışındaki gerçek proje dizini serbesttir.
  expect_null(ortak_by_ozel_dizin_engeli(
    dis_proje, 42L,
    yonetilen_kokler = kokler, oda_koku = oda_42
  ))
})

test_that("özel dizin doğrulaması merkezi çalışma dizini politikasına delege eder", {
  onceki <- if (exists("cc_policy_validate_workdir", inherits = TRUE)) {
    get("cc_policy_validate_workdir", inherits = TRUE)
  } else {
    NULL
  }
  on.exit({
    if (is.null(onceki)) {
      suppressWarnings(rm("cc_policy_validate_workdir", envir = globalenv()))
    } else {
      assign("cc_policy_validate_workdir", onceki, envir = globalenv())
    }
  }, add = TRUE)

  yakalanan <- new.env(parent = emptyenv())
  assign("cc_policy_validate_workdir", function(workdir, user_id = NULL,
                                                extra_allowed_roots = character(0),
                                                allow_system_temp = FALSE,
                                                allow_selected_workdir = FALSE) {
    yakalanan$workdir <- workdir
    yakalanan$allow_selected <- allow_selected_workdir
    list(ok = TRUE, path = workdir, error = "")
  }, envir = globalenv())

  dis_proje <- file.path(tempdir(), sprintf("oo_by_politika_%d", sample.int(99999L, 1L)))
  dir.create(dis_proje, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(dis_proje, recursive = TRUE, force = TRUE), add = TRUE)

  sonuc <- ortak_by_ozel_dizin_dogrula(dis_proje, 42L, user_id = 7L)
  expect_true(isTRUE(sonuc$ok))
  expect_identical(yakalanan$workdir, dis_proje)
  # Kullanıcı seçimli dizin izni politika katmanına açıkça aktarılır.
  expect_true(is.logical(yakalanan$allow_selected))

  # İzolasyon kapısı politika çağrısından ÖNCE keser: yönetilen kök içi yol
  # politika stub'ına hiç ulaşmaz. helper_bootstrap dosya köklerini sandbox'a
  # aldığı için yönetilen kök, ortam değişkeni yerine seçenek üzerinden sabitlenir.
  yakalanan$workdir <- NULL
  eski_opt <- getOption("mergen.files_root", NULL)
  options(mergen.files_root = tempdir())
  on.exit(options(mergen.files_root = eski_opt), add = TRUE)

  ic_yol <- file.path(tempdir(), "ortak_oturumlar", "oturum_777")
  dir.create(ic_yol, recursive = TRUE, showWarnings = FALSE)
  sonuc_ic <- ortak_by_ozel_dizin_dogrula(ic_yol, 42L, user_id = 7L)
  expect_false(isTRUE(sonuc_ic$ok))
  expect_null(yakalanan$workdir)
})

test_that("etkin çalışma dizini: geçerli özel dizin öncelikli, yoksa paylaşılan klasör", {
  ozel <- file.path(tempdir(), sprintf("oo_by_ozel_%d", sample.int(99999L, 1L)))
  dir.create(ozel, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(ozel, recursive = TRUE, force = TRUE), add = TRUE)

  otomatik_cagrildi <- new.env(parent = emptyenv())
  otomatik_fn <- function(oturum_id) {
    otomatik_cagrildi$oturum <- oturum_id
    "/tmp/paylasilan"
  }

  # Geçerli özel dizin: otomatik üretici hiç çağrılmaz.
  bilgi <- ortak_by_etkin_calisma_dizini(ozel, 42L, otomatik_fn = otomatik_fn)
  expect_identical(bilgi$yol, ozel)
  expect_true(isTRUE(bilgi$ozel))
  expect_null(otomatik_cagrildi$oturum)

  # Boş kayıt: paylaşılan otomatik klasöre düşer.
  bilgi_bos <- ortak_by_etkin_calisma_dizini("", 42L, otomatik_fn = otomatik_fn)
  expect_identical(bilgi_bos$yol, "/tmp/paylasilan")
  expect_false(isTRUE(bilgi_bos$ozel))
  expect_identical(otomatik_cagrildi$oturum, 42L)

  # Var olmayan özel dizin: güvenli düşüş.
  bilgi_yok <- ortak_by_etkin_calisma_dizini(
    file.path(tempdir(), "boyle_bir_dizin_yok_9999"), 42L, otomatik_fn = otomatik_fn
  )
  expect_false(isTRUE(bilgi_yok$ozel))
})

test_that("panel iskeleti varsayılan KAPALI gelir ve kart yuvalarını taşır", {
  ns <- shiny::NS("ortak_calismalar_module-oda")
  senaryolar <- list(list(id = "kod_inceleme", ikon = "magnifying-glass",
                          baslik = "Kod İnceleme", aciklama = "Kodu incele", sablon = "x"))

  html <- .oo_by_test_html(oo_by_panel_iskeleti_html(ns, senaryolar = senaryolar))

  expect_true(grepl("oo-by-panel oo-by-panel-kapali", html, fixed = TRUE))
  expect_true(grepl("data-oo-by-panel", html, fixed = TRUE))
  expect_true(grepl("data-oo-toggle-by", html, fixed = TRUE))

  # Kart/çıktı yuvaları: proje dizini, model, dizin içeriği, dosya eylemleri,
  # eklentiler, çalıştırma geçmişi ve CLI durum rozeti.
  for (yuva in c("by_proje_dizini_karti", "by_model_karti", "by_dizin_icerigi",
                 "by_dizin_yolu_alani", "by_dosya_eylem_karti", "by_eklentiler",
                 "by_calistirma_gecmisi", "by_durum_rozeti")) {
    expect_true(
      grepl(paste0("ortak_calismalar_module-oda-", yuva), html, fixed = TRUE),
      info = sprintf("Panel iskeletinde %s yuvası bulunamadı.", yuva)
    )
  }

  expect_true(grepl("ortak_calismalar_module-oda-by_senaryo_kod_inceleme", html, fixed = TRUE))
  expect_true(grepl("oo-by-kart-grid", html, fixed = TRUE))
})

test_that("Proje Dizini kartı: yazma yetkisine göre düzenlenebilir girdi ve XSS escape", {
  ns <- shiny::NS("oda")

  yazilabilir <- .oo_by_test_html(oo_by_proje_dizini_govde_html(
    girdi_id = ns("by_workdir_girdisi"),
    uygula_id = ns("by_workdir_uygula"),
    sifirla_id = ns("by_workdir_sifirla"),
    yol = "//rehisds/uygulamalar/Proje",
    ozel = TRUE,
    yazabilir = TRUE
  ))

  # Görünür ve kullanılabilir yol girdisi + uygula/sıfırla eylemleri.
  expect_true(grepl('id="oda-by_workdir_girdisi"', yazilabilir, fixed = TRUE))
  expect_true(grepl('type="text"', yazilabilir, fixed = TRUE))
  expect_true(grepl("Proje klasör yolunu girin", yazilabilir, fixed = TRUE))
  expect_true(grepl("oda-by_workdir_uygula", yazilabilir, fixed = TRUE))
  expect_true(grepl("oda-by_workdir_sifirla", yazilabilir, fixed = TRUE))
  expect_true(grepl("Özel proje dizini", yazilabilir, fixed = TRUE))

  salt_okunur <- .oo_by_test_html(oo_by_proje_dizini_govde_html(
    girdi_id = ns("by_workdir_girdisi"),
    uygula_id = ns("by_workdir_uygula"),
    sifirla_id = ns("by_workdir_sifirla"),
    yol = "/veri/oda",
    ozel = FALSE,
    yazabilir = FALSE
  ))
  expect_false(grepl('id="oda-by_workdir_girdisi"', salt_okunur, fixed = TRUE))
  expect_true(grepl("Paylaşılan oda klasörü", salt_okunur, fixed = TRUE))

  # XSS sınırı: yol metni escape edilir.
  saldiri <- .oo_by_test_html(oo_by_proje_dizini_govde_html(
    girdi_id = ns("g"), uygula_id = ns("u"), sifirla_id = ns("s"),
    yol = "<script>alert(1)</script>",
    ozel = FALSE,
    yazabilir = FALSE
  ))
  expect_false(grepl("<script>alert(1)</script>", saldiri, fixed = TRUE))
  expect_true(grepl("&lt;script&gt;", saldiri, fixed = TRUE))
})

test_that("model kartı katman düğmelerini delege JS sözleşmesiyle üretir", {
  katmanlar <- list(
    list(deger = "model-hizli", etiket = "Hızlı", ikon = "bolt", aciklama = "Hızlı model"),
    list(deger = "model-guclu", etiket = "Güçlü", ikon = "brain", aciklama = "Güçlü model")
  )

  html <- .oo_by_test_html(oo_by_model_govde_html(katmanlar, "model-guclu", "oda-by_model_sec"))

  expect_true(grepl('data-oo-model-deger="model-hizli"', html, fixed = TRUE))
  expect_true(grepl('data-oo-hedef-input="oda-by_model_sec"', html, fixed = TRUE))
  # Seçili katman aktif işaretlenir; seçim boşken ilk katman aktif olur.
  expect_true(grepl("oo-by-model-aktif", html, fixed = TRUE))

  bos_secim <- .oo_by_test_html(oo_by_model_govde_html(katmanlar, "", "oda-by_model_sec"))
  ilk_konum <- regexpr("oo-by-model-aktif", bos_secim, fixed = TRUE)
  hizli_konum <- regexpr("model-hizli", bos_secim, fixed = TRUE)
  expect_true(ilk_konum > 0 && hizli_konum > 0 && ilk_konum < hizli_konum)

  expect_true(grepl(
    "Model katmanı bulunamadı",
    .oo_by_test_html(oo_by_model_govde_html(list(), "", "x")),
    fixed = TRUE
  ))
})

test_that("iskelet yoklamadan bağımsızdır; aç/kapa tercihi JS köprüsünde korunur", {
  repo_root <- resolve_repo_root_for_tests()
  modul <- .oo_by_test_oku(file.path(repo_root, "R", "module_ortak_oturum_bilge_yolac.R"))

  # İskelet render'ı saf üreticiye delege eder ve kompakt sinyalleri kullanır.
  expect_true(grepl("oo_by_panel_iskeleti_html(ns", modul, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("by_odasi_sinyali", modul, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("by_erisim_sinyali", modul, fixed = TRUE, useBytes = TRUE))

  # İskelet bloğu yoklama tetikleyicilerine bağlanmaz (panel her yoklamada
  # yeniden çizilip aç/kapa tercihi sıfırlanmasın).
  baslangic <- regexpr("output$by_alani <- renderUI({", modul, fixed = TRUE)
  bitis <- regexpr("output$by_durum_rozeti", modul, fixed = TRUE)
  expect_true(baslangic > 0 && bitis > baslangic)
  iskelet_blogu <- substr(modul, baslangic, bitis)
  expect_false(grepl("by_tetik(", iskelet_blogu, fixed = TRUE))
  expect_false(grepl("yenile_sayaci", iskelet_blogu, fixed = TRUE))
  expect_false(grepl("dizin_yenile(", iskelet_blogu, fixed = TRUE))

  # Varsayılan KAPALI sınıfı iskelet üreticisindedir.
  yardimci <- .oo_by_test_oku(file.path(repo_root, "R", "helpers_ortak_oturum_by_calisma_alani.R"))
  expect_true(grepl("oo-by-panel oo-by-panel-kapali", yardimci, fixed = TRUE, useBytes = TRUE))

  # JS köprüsü: tercih sessionStorage'da saklanır ve render sonrası geri uygulanır.
  js <- .oo_by_test_oku(file.path(repo_root, "www", "js", "ortak_oturumlar.js"))
  expect_true(grepl("oo_by_panel_acik", js, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("ooByPanelTercihiniUygula", js, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("by_alani", js, fixed = TRUE, useBytes = TRUE))

  # CSS: gövde kendi içinde kayar (panel sohbeti ele geçirmez) ve kapalıyken gizlenir.
  css <- .oo_by_test_oku(file.path(repo_root, "www", "css", "ortak_oturumlar_bilge_yolac.css"))
  expect_true(grepl(".oo-by-panel.oo-by-panel-kapali .oo-by-govde", css, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("max-height", css, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl(".oo-by-kart-grid", css, fixed = TRUE, useBytes = TRUE))
})

test_that("oo-oda-acik-kok sınıfı sekmeye duyarlı merkez güncelleyiciyle yönetilir", {
  repo_root <- resolve_repo_root_for_tests()

  js <- .oo_by_test_oku(file.path(repo_root, "www", "js", "ortak_oturumlar.js"))
  # Merkez güncelleyici: oda açık + hub sekmesi görünür değilse sınıf kalkar.
  expect_true(grepl("ooKokSinifiniGuncelle", js, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("MergenOrtakOturum", js, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("closest('.tab-pane')", js, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("classList.contains('active')", js, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("shown.bs.tab", js, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("hashchange", js, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("oo-oda-acik-kok", js, fixed = TRUE, useBytes = TRUE))

  # Hub sunucusu doğrudan kalıcı sınıf bırakmak yerine merkez güncelleyiciyi çağırır.
  hub <- .oo_by_test_oku(file.path(repo_root, "R", "module_ortak_calismalar.R"))
  expect_true(grepl("MergenOrtakOturum", hub, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("kokGuncelle", hub, fixed = TRUE, useBytes = TRUE))
})

test_that("BilgeYolaç odalarında araç/belge bağlam kapıları dürüsttür (P2-C / P2-D)", {
  repo_root <- resolve_repo_root_for_tests()

  # Araç seçici VE aktif araç rozeti BY odasında çizilmez.
  arac <- .oo_by_test_oku(file.path(repo_root, "R", "module_ortak_oturum_arac.R"))
  arac_gate_sayisi <- gregexpr(enc2utf8('"BilgeYolaç"'), arac, fixed = TRUE, useBytes = TRUE)[[1]]
  expect_true(length(arac_gate_sayisi) >= 2 && arac_gate_sayisi[1] > 0)

  # Belge paneli: BY odasında dürüst not + bağlam seçimi kapalı belge listesi.
  belge <- .oo_by_test_oku(file.path(repo_root, "R", "module_ortak_oturum_belge_paneli.R"))
  expect_true(grepl("oo-belge-by-notu", belge, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("baglam_secimi = !by_odasi", belge, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl(enc2utf8("bağlamına eklenmez"), belge, fixed = TRUE, useBytes = TRUE))

  # Soru metadata'sı yardımcıdan hazırlanır (BY odasında araç/belge yazılmaz).
  yz <- .oo_by_test_oku(file.path(repo_root, "R", "module_ortak_oturum_yz.R"))
  expect_true(grepl("oo_arac_soru_meta_hazirla", yz, fixed = TRUE, useBytes = TRUE))
})

test_that("belge kartı baglam_secimi=FALSE iken bağlam iması taşımaz", {
  onceki_meta <- if (exists("ortak_belge_meta", inherits = TRUE)) {
    get("ortak_belge_meta", inherits = TRUE)
  } else {
    NULL
  }
  on.exit({
    if (is.null(onceki_meta)) {
      suppressWarnings(rm("ortak_belge_meta", envir = globalenv()))
    } else {
      assign("ortak_belge_meta", onceki_meta, envir = globalenv())
    }
  }, add = TRUE)

  # Belge SEÇİLİ görünse bile BY odasında kart bağlam iması taşımamalıdır.
  assign("ortak_belge_meta", function(meta_json) {
    list(kaynak = "KatilimciYuklemesi", secili = TRUE)
  }, envir = globalenv())

  satir <- data.frame(
    OrtakDosyaID = 5L,
    DosyaAdi = "rapor.docx",
    UretenAdi = "Mehmet",
    OlusturmaZamani = "2026-07-10 10:00",
    KopyalamaDurumu = "",
    DosyaBoyutu = 2048,
    MetaJson = "{}",
    stringsAsFactors = FALSE
  )

  by_karti <- .oo_by_test_html(oo_dosya_karti_html(
    satir,
    kopyala_input_id = "oda-belge_kopyala",
    secim_input_id = NULL,
    sil_input_id = "oda-belge_sil",
    yetkili = TRUE,
    baglam_secimi = FALSE
  ))
  expect_false(grepl("oo-belge-secim-kutu", by_karti, fixed = TRUE))
  expect_false(grepl("Bağlamda", by_karti, fixed = TRUE))
  expect_false(grepl("oo-belge-secili", by_karti, fixed = TRUE))
  # İndirme/kaldırma eylemleri korunur (üretilen dosyalar erişilebilir kalır).
  expect_true(grepl("Kendi Dosyalarıma Kaydet", by_karti, fixed = TRUE))
  expect_true(grepl("oda-belge_sil", by_karti, fixed = TRUE))

  # Normal odada aynı satır bağlam seçim kutusunu taşır.
  normal_kart <- .oo_by_test_html(oo_dosya_karti_html(
    satir,
    kopyala_input_id = "oda-belge_kopyala",
    secim_input_id = "oda-belge_secim",
    sil_input_id = "oda-belge_sil",
    yetkili = TRUE,
    baglam_secimi = TRUE
  ))
  expect_true(grepl("oo-belge-secim-kutu", normal_kart, fixed = TRUE))
  expect_true(grepl("oo-belge-secili", normal_kart, fixed = TRUE))
})

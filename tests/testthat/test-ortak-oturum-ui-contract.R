# ==============================================================================
# Dosya Yolu: tests/testthat/test-ortak-oturum-ui-contract.R
# Açıklama: Ortak Oturumlar UI/wiring sözleşmesi: "Odaya Yaz" ile "Yapay
#           Zekâya Sor" ayrımı, davet paneli eylemleri, "Kendi Dosyalarıma
#           Kaydet", tema token kullanımı, XSS escape sınırı, seçici
#           güvenliği, varlık manifesti/bölge üyeliği, navigasyon sekmeleri
#           ve kaynak manifesti bölüm sırası. Uygulamayı başlatmaz.
# ==============================================================================

# Windows/Türkçe yerel ayar güvenli bayt okuyucu (repo kuralı).
.oo_ui_oku <- function(yol) {
  baytlar <- readBin(yol, what = "raw", n = file.info(yol)$size)
  iconv(rawToChar(baytlar), from = "UTF-8", to = "UTF-8", sub = "byte")
}

test_that("oda yazma ve yapay zekâ sorma eylemleri ayrı ve açıklamalıdır", {
  repo_root <- resolve_repo_root_for_tests()
  ui_kaynak <- .oo_ui_oku(file.path(repo_root, "R", "module_ortak_oturum_room_ui.R"))

  expect_true(grepl(enc2utf8("Odaya Yaz"), ui_kaynak, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl(enc2utf8("Yapay Zekâya Sor"), ui_kaynak, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("odaya_yaz", ui_kaynak, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("yapay_zekaya_sor", ui_kaynak, fixed = TRUE, useBytes = TRUE))

  # Yapay zekâ uyarı metni: yanıtın tüm katılımcılara görüneceği açıkça yazılır.
  expect_true(grepl(
    enc2utf8("yanıt tüm katılımcılar tarafından görülecek"),
    ui_kaynak, fixed = TRUE, useBytes = TRUE
  ))

  # Sunucu tarafında yapay zekâ sorusu ayrı üretim motoruna (motor$soru_gonder)
  # devredilir; LLM üretim mantığı R/module_ortak_oturum_yz.R içindedir.
  oda_sunucu <- .oo_ui_oku(file.path(repo_root, "R", "module_ortak_oturum_room.R"))
  yz_motor <- .oo_ui_oku(file.path(repo_root, "R", "module_ortak_oturum_yz.R"))

  expect_true(grepl("motor$soru_gonder", oda_sunucu, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("YapayZekaSorusu", yz_motor, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("ortak_db_uretim_kilidi_al", yz_motor, fixed = TRUE, useBytes = TRUE))
  # Kilit doluyken soru kaybolmaz, kalıcı kuyruğa eklenir.
  expect_true(grepl("ortak_db_kuyruk_ekle", yz_motor, fixed = TRUE, useBytes = TRUE))

  # OdaMesajı gözlemcisi LLM üretimini ÇAĞIRMAZ: odaya_yaz bloğu içinde
  # yapay zekâ üretim motoru (motor$soru_gonder / YapayZekaSorusu) geçmez.
  odaya_yaz_blok <- regmatches(
    oda_sunucu,
    regexpr("observeEvent\\(input\\$odaya_yaz[\\s\\S]*?\\n    \\}\\)", oda_sunucu, perl = TRUE)
  )
  expect_length(odaya_yaz_blok, 1L)
  expect_false(grepl("motor$soru_gonder", odaya_yaz_blok, fixed = TRUE, useBytes = TRUE))
  expect_false(grepl("YapayZekaSorusu", odaya_yaz_blok, fixed = TRUE, useBytes = TRUE))
})

test_that("davet paneli ve belge eylemleri sözleşmeli metinleri taşır", {
  repo_root <- resolve_repo_root_for_tests()

  oda_ui <- .oo_ui_oku(file.path(repo_root, "R", "module_ortak_oturum_room_ui.R"))
  davetler <- .oo_ui_oku(file.path(repo_root, "R", "module_ortak_oturum_invites.R"))
  belge_paneli <- .oo_ui_oku(file.path(repo_root, "R", "module_ortak_oturum_belge_paneli.R"))

  expect_true(grepl(enc2utf8("Katılımcı Çağır"), oda_ui, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl(enc2utf8("Mergen İçinden Çağır"), oda_ui, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl(enc2utf8("E-posta Taslağı Hazırla"), oda_ui, fixed = TRUE, useBytes = TRUE))
  # Belge kartı üreticisi (Kendi Dosyalarıma Kaydet + bağlam seçimi + kaldırma)
  # belge paneli bağlayıcısına taşındı.
  expect_true(grepl(enc2utf8("Kendi Dosyalarıma Kaydet"), belge_paneli, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl(enc2utf8("Bağlama dahil et"), belge_paneli, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("Belge Yükle", belge_paneli, fixed = TRUE, useBytes = TRUE))

  # Davet paneli sekmeleri ve hız sınırı.
  expect_true(grepl(enc2utf8("Çevrim İçi Kullanıcılar"), davetler, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl(enc2utf8("Tüm Kullanıcılar"), davetler, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("Davet Edilenler", davetler, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("oo_davet_hiz_siniri_asildi_mi", davetler, fixed = TRUE, useBytes = TRUE))

  # E-posta otomatik gönderilmez; taslak modalı vardır.
  expect_true(grepl(enc2utf8("E-posta Taslağını Aç"), davetler, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("ortak_davet_eposta_taslak_href", davetler, fixed = TRUE, useBytes = TRUE))
})

test_that("saf HTML üreticileri kullanıcı metnini escape eder (XSS sınırı)", {
  repo_root <- resolve_repo_root_for_tests()

  ui_kaynak <- .oo_ui_oku(file.path(repo_root, "R", "module_ortak_oturum_room_ui.R"))
  hub_kaynak <- .oo_ui_oku(file.path(repo_root, "R", "module_ortak_calismalar.R"))

  expect_true(grepl("htmltools::htmlEscape", ui_kaynak, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("htmltools::htmlEscape", hub_kaynak, fixed = TRUE, useBytes = TRUE))

  # Yapay zekâ yanıtı ham HTML olarak DEĞİL, güvenli markdown yolundan render edilir.
  expect_true(grepl("render_safe_markdown_html", ui_kaynak, fixed = TRUE, useBytes = TRUE))

  # Davranış doğrulaması: kötü niyetli başlık escape edilir. UI üreticileri
  # bağımsız çalıştırılırken shiny etkileşimli eklenir (repo test deseni).
  testthat::skip_if_not_installed("shiny")
  suppressPackageStartupMessages(library(shiny))

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }
  source(file.path(repo_root, "R", "module_ortak_oturum_room_ui.R"),
         encoding = "UTF-8", local = globalenv())

  satir <- data.frame(
    MesajTuru = "OdaMesajı",
    MesajMetni = "<script>alert(1)</script>",
    GonderenAdi = "<img src=x onerror=alert(1)>",
    GonderenKullaniciID = 7L,
    OlusturmaZamani = "2026-07-05 10:00:00",
    stringsAsFactors = FALSE
  )

  html <- as.character(oo_mesaj_html(satir))

  # Ham etiket DOM'a giremez; escape edilmiş biçim inert metin olarak kalır.
  expect_false(grepl("<script>", html, fixed = TRUE))
  expect_false(grepl("<img src=x", html, fixed = TRUE))
  expect_true(grepl("&lt;script&gt;", html, fixed = TRUE))
  expect_true(grepl("&lt;img src=x", html, fixed = TRUE))
})

test_that("JS köprüsü seçici enterpolasyonu yapmaz ve kalp atışı sözleşmesini taşır", {
  repo_root <- resolve_repo_root_for_tests()
  js <- .oo_ui_oku(file.path(repo_root, "www", "js", "ortak_oturumlar.js"))

  expect_true(grepl("data-oo-hedef-input", js, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("Shiny.setInputValue", js, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("Shiny.onInputChange", js, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("ortak_calismalar_module-canli_kalp_atisi", js, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("shiny:connected", js, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("shiny:disconnected", js, fixed = TRUE, useBytes = TRUE))

  # Kimlik değerleri CSS seçicisine gömülmez: querySelector('[data-... + id]')
  # kalıbı yoktur; dataset üzerinden düz okuma vardır.
  expect_false(grepl('querySelector("[data-oo-oturum-id=', js, fixed = TRUE, useBytes = TRUE))
  expect_false(grepl("querySelector('[data-oo-oturum-id=", js, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("getAttribute('data-oo-hedef-input')", js, fixed = TRUE, useBytes = TRUE))

  # Eski/yanlış girdi kimlikleri kullanılmaz.
  expect_false(grepl("message_input", js, fixed = TRUE, useBytes = TRUE))
  expect_false(grepl("chat_content_wrapper", js, fixed = TRUE, useBytes = TRUE))
})

test_that("CSS tema token'larını kullanır ve açık tema kapsamı doğrudur", {
  repo_root <- resolve_repo_root_for_tests()
  css <- .oo_ui_oku(file.path(repo_root, "www", "css", "ortak_oturumlar.css"))

  expect_true(grepl("var(--color-surface)", css, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("var(--color-text)", css, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl('html[data-theme="light"]', css, fixed = TRUE, useBytes = TRUE))

  # Responsive: dar ekran kuralı ve yan panelin dikey akışa inmesi.
  expect_true(grepl("@media (max-width: 900px)", css, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("flex-direction: column", css, fixed = TRUE, useBytes = TRUE))

  # Canlı durum yalnızca renge dayanmaz: rozet metinleri R tarafında vardır.
  ui_kaynak <- .oo_ui_oku(file.path(repo_root, "R", "module_ortak_oturum_room_ui.R"))
  expect_true(grepl("aria-label", ui_kaynak, fixed = TRUE, useBytes = TRUE))
})

test_that("varlıklar manifest + bölge sahipliğinde; navigasyon sekmeleri bağlı", {
  repo_root <- resolve_repo_root_for_tests()

  manifest <- .oo_ui_oku(file.path(repo_root, "R", "config_ui_assets.R"))
  expect_true(grepl("css/ortak_oturumlar.css", manifest, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("js/ortak_oturumlar.js", manifest, fixed = TRUE, useBytes = TRUE))

  bolgeler <- .oo_ui_oku(file.path(repo_root, "R", "config_ui_asset_zones.R"))
  expect_true(grepl("css/ortak_oturumlar.css", bolgeler, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("js/ortak_oturumlar.js", bolgeler, fixed = TRUE, useBytes = TRUE))

  ui_r <- .oo_ui_oku(file.path(repo_root, "ui.R"))
  expect_true(grepl('tabName = "ortak_calismalar"', ui_r, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl('tabName = "ortak_sohbetler"', ui_r, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl('tabName = "ortak_bilge_yolac"', ui_r, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl(enc2utf8("Ortak Çalışmalarım"), ui_r, fixed = TRUE, useBytes = TRUE))

  # Kişisel geçmiş sekmeleri değişmeden durur (ayrık zihinsel model).
  expect_true(grepl('tabName = "history"', ui_r, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl('tabName = "saved_chats"', ui_r, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl('tabName = "claude_code_sessions"', ui_r, fixed = TRUE, useBytes = TRUE))

  # Sunucu wiring: canlı kullanıcı kimliği SAĞLAYICISI ile bağlanır.
  wiring <- .oo_ui_oku(file.path(repo_root, "R", "server_module_wiring.R"))
  expect_true(grepl("ortak_calismalar_server_fn", wiring, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl('"ortak_calismalar_module"', wiring, fixed = TRUE, useBytes = TRUE))
})

test_that("kaynak manifesti ortak_oturumlar bölümünü bağımlılık sırasıyla taşır", {
  beklenen_sira <- c(
    "R/helpers_ortak_oturum_permissions.R",
    "R/helpers_ortak_oturum_sunum.R",
    "R/helpers_ortak_oturum_email.R",
    "R/helpers_ortak_oturum_db.R",
    "R/helpers_ortak_oturum_db_katilim.R",
    "R/helpers_ortak_oturum_db_davet.R",
    "R/helpers_ortak_oturum_db_mesajlar.R",
    "R/helpers_ortak_oturum_db_bilge_yolac.R",
    "R/helpers_ortak_oturum_db_kuyruk.R",
    "R/helpers_ortak_oturum_files.R",
    "R/helpers_ortak_oturum_belgeler.R",
    "R/helpers_ortak_oturum_arac.R",
    "R/helpers_ortak_oturum_bakim.R",
    "R/module_ortak_oturum_room_ui.R",
    "R/module_ortak_oturum_belge_paneli.R",
    "R/module_ortak_oturum_arac.R",
    "R/module_ortak_oturum_invites.R",
    "R/module_ortak_oturum_yz.R",
    "R/module_ortak_oturum_bilge_yolac.R",
    "R/module_ortak_oturum_room.R",
    "R/module_ortak_calismalar.R"
  )

  repo_root <- resolve_repo_root_for_tests()
  manifest_env <- new.env(parent = globalenv())
  source(file.path(repo_root, "R", "config_source_manifest.R"),
         encoding = "UTF-8", local = manifest_env)

  bolum <- manifest_env$source_manifest_sections$ortak_oturumlar
  expect_identical(bolum, beklenen_sira)

  # Seam sahipliği: ortak_oturumlar bölümü sohbet_llm_akis seam'ine aittir.
  seam_env <- new.env(parent = globalenv())
  source(file.path(repo_root, "R", "config_seam_registry.R"),
         encoding = "UTF-8", local = seam_env)
  kayit <- seam_env$mergen_seam_registry()
  expect_true("ortak_oturumlar" %in% kayit$sohbet_llm_akis$manifest_sections)
})

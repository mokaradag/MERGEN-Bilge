# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-sessions-browser-smoke-contract.R
# Açıklama: Bilge Yolaç "Oturumlar" (kalıcı oturum) sayfası için tarayıcı
#           seviyesindeki UX smoke kapsamını korur. Bu sözleşme testi, gerçek
#           bir tarayıcı çalıştırmaz; www/smoke/ux-smoke.html ve
#           www/smoke/ux-smoke-probes.js içindeki Oturumlar probe'unun VAR OLDUĞUNU
#           ve ana smoke dizisine BAĞLANDIĞINI, ayrıca korunan değişmezleri
#           (Durum/Model filtresinde "Tümü" kalıcılığı, aktif ↔ arşiv kart eylem
#           yüzeyi, detay modalı kaydırma/max-height sözleşmesi, çift DOM id
#           yokluğu) doğrular. Böylece gelecekte probe yanlışlıkla kaldırılamaz.
#
#           Sentetik fixture'ın gerçek UI ile hizalı kalması için gerçek
#           R/module_claude_code_sessions_ui.R yüzeyi de (yerel select, durum
#           seçenekleri, kart eylem sınıfları) çapraz doğrulanır. Uygulamayı
#           başlatmaz; DB/ağ gerektirmez.
# ==============================================================================

# Windows VM'de geçersiz UTF-8 byte'larına dayanıklı byte-güvenli okuyucu.
.ccs_smoke_read_text <- function(...) {
  full_path <- file.path(resolve_repo_root_for_tests(), ...)

  if (!file.exists(full_path)) {
    stop(sprintf("Beklenen dosya bulunamadı: %s", full_path), call. = FALSE)
  }

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

.ccs_smoke_expect_all <- function(text, tokens, label) {
  missing <- tokens[!vapply(
    tokens,
    function(token) grepl(token, text, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  testthat::expect_equal(
    missing,
    character(0),
    info = paste(label, paste(missing, collapse = ", "))
  )
}

# ------------------------------------------------------------------------------
test_that("ux-smoke.html Oturumlar probe'unu tanımlar ve ana diziye bağlar", {
  smoke_html <- .ccs_smoke_read_text("www", "smoke", "ux-smoke.html")

  .ccs_smoke_expect_all(
    smoke_html,
    c(
      # Probe delegasyon fonksiyonu tanımlıdır.
      "async function testBilgeYolacSessionsSurface(app)",
      "window.MergenUxSmokeProbes.runBilgeYolacSessionsSurfaceSmoke(app, {",
      # Ana smoke dizisinden gerçekten çağrılır (kanıt üretir).
      "await testBilgeYolacSessionsSurface(app);"
    ),
    "ux-smoke.html Oturumlar probe entegrasyonu eksik:"
  )

  # Probe, PASS akışının parçası olmalı: testConsoleNoise'tan ÖNCE çağrılmalı.
  probe_pos <- regexpr(
    "await testBilgeYolacSessionsSurface(app);",
    smoke_html,
    fixed = TRUE,
    useBytes = TRUE
  )[[1]]
  console_pos <- regexpr(
    "testConsoleNoise();",
    smoke_html,
    fixed = TRUE,
    useBytes = TRUE
  )[[1]]

  expect_true(probe_pos > 0L)
  expect_true(console_pos > 0L)
  expect_true(
    probe_pos < console_pos,
    info = "Oturumlar probe'u konsol sağlık kontrolünden önce çalışmalıdır."
  )
})

test_that("ux-smoke-probes.js Oturumlar filtre değişmezlerini gerçek tarayıcıda korur", {
  probes_js <- .ccs_smoke_read_text("www", "smoke", "ux-smoke-probes.js")

  .ccs_smoke_expect_all(
    probes_js,
    c(
      "async function runBilgeYolacSessionsSurfaceSmoke(app, helpers)",
      "runBilgeYolacSessionsSurfaceSmoke: runBilgeYolacSessionsSurfaceSmoke",

      # Gerçek modül namespace'i ve iki filtre select'i okunur.
      "claude_code_sessions_module",
      "filter_status",
      "filter_model",

      # Yerel select tespiti (selectize placeholder regresyonunun panzehri).
      "ccsIsNativeSelect",
      "selectized",
      ".selectize-control",
      "Oturumlar Durum filtresi yerel <select> öğesidir (selectize değil)",
      "Oturumlar Model filtresi yerel <select> öğesidir (selectize değil)",

      # Durum filtresi tüm seçenekleri ve Türkçe etiketleri.
      "Oturumlar Durum filtresi tüm durum seçeneklerini içerir",
      "Oturumlar Durum filtresi Türkçe etiketleri içerir",

      # "Tümü" kalıcılığı: hem Durum hem Model filtresinde seçim sonrası korunur.
      "Oturumlar Durum filtresinde seçim sonrası 'Tümü' seçeneği kaybolmaz",
      "Oturumlar Durum filtresinde seçim sonrası 'Tümü' yeniden seçilebilir",
      "Oturumlar Model filtresi 'Tümü' seçeneğini içerir",
      "Oturumlar Model filtresinde model seçimi sonrası 'Tümü' seçeneği kaybolmaz",
      "Oturumlar Model filtresinde model seçimi sonrası 'Tümü' yeniden seçilebilir"
    ),
    "ux-smoke-probes.js Oturumlar filtre kapsamı eksik:"
  )
})

test_that("ux-smoke-probes.js aktif ↔ arşiv kart eylem yüzeyini ve modalı korur", {
  probes_js <- .ccs_smoke_read_text("www", "smoke", "ux-smoke-probes.js")

  .ccs_smoke_expect_all(
    probes_js,
    c(
      # Kart eylem sınıfları (gerçek UI ile aynı).
      "ccs-open-btn",
      "ccs-resume-btn",
      "ccs-archive-btn",
      "ccs-restore-btn",
      "ccs-delete-btn",

      # Aktif kart eylemleri gösterir, arşiv-özel eylemleri göstermez.
      "Aktif oturum kartı Aç / Devam Et / Arşivle eylemlerini gösterir",
      "Aktif oturum kartı arşiv-özel (Geri Yükle / Kalıcı Sil) eylemleri göstermez",

      # Arşiv kartı eylemleri gösterir, aktif-özel eylemleri göstermez.
      "Arşivlenmiş oturum kartı Aç / Geri Yükle / Kalıcı Sil eylemlerini gösterir",
      "Arşivlenmiş oturum kartı aktif-özel (Devam Et / Arşivle) eylemleri göstermez",

      # Detay modalı kaydırma / max-height sözleşmesi.
      "modal-body",
      "ccs-detail-modal-content",
      "ccs-run-timeline",
      "getComputedStyle",
      "Oturum detay modalı içeriği görünüm-yüksekliğine bağlı max-height taşır",
      "Oturum detay modalı içeriği kaydırılabilir overflow sözleşmesi taşır",
      "Oturum detay modalı uzun geçmişte kendi içinde kayar (cimri/taşkın değil)",

      # Çift DOM id koruması.
      "Oturumlar modül id yüzeyinde çift DOM id üretilmez"
    ),
    "ux-smoke-probes.js Oturumlar kart/modal kapsamı eksik:"
  )
})

test_that("Oturumlar detay modalı CSS'i içerik alanı kaydırma/max-height sözleşmesi taşır", {
  css_metin <- .ccs_smoke_read_text("www", "css", "claude_code_sessions.css")

  # Detay modalı içeriği: taban yükseklik (cimri değil) + görünüm-yüksekliğine
  # bağlı üst sınır + kendi içinde kaydırma (uzun geçmiş taşmaz). Üst sınır
  # global .modal-body (60vh) altında kalarak çift kaydırma çubuğunu önler.
  .ccs_smoke_expect_all(
    css_metin,
    c(
      ".ccs-detail-modal-content",
      "min-height: 46vh;",
      "max-height: 56vh;",
      "overflow-y: auto;"
    ),
    "Oturumlar detay modalı CSS kaydırma sözleşmesi eksik:"
  )
})

test_that("sentetik Oturumlar fixture'ı gerçek modül UI yüzeyiyle hizalıdır", {
  ui_metin <- .ccs_smoke_read_text("R", "module_claude_code_sessions_ui.R")

  # Probe'un sentetik fixture'ı gerçek kart eylem sınıflarını ve durum
  # seçeneklerini yeniden kullanır; bu değerler gerçek UI'da gerçekten
  # üretilmelidir (fixture ↔ gerçek UI drift koruması).
  .ccs_smoke_expect_all(
    ui_metin,
    c(
      "ccs-open-btn",
      "ccs-resume-btn",
      "ccs-archive-btn",
      "ccs-restore-btn",
      "ccs-delete-btn",
      '"resumable"',
      '"completed"',
      '"failed"',
      '"stopped"',
      '"archived"',
      # Detay modalı zaman çizelgesi gerçek UI üreticisinde (ccs_session_detail_content).
      "ccs-run-timeline"
    ),
    "Gerçek Oturumlar UI yüzeyi sentetik fixture ile hizalı değil:"
  )

  # Detay modalı içerik sarmalayıcısı (.ccs-detail-modal-content) sunucu
  # modülünde showModal içinde üretilir; sentetik fixture bununla aynı sınıfı
  # kullanır (drift koruması).
  server_metin <- .ccs_smoke_read_text("R", "module_claude_code_sessions.R")
  expect_true(
    grepl("ccs-detail-modal-content", server_metin, fixed = TRUE, useBytes = TRUE),
    info = "Detay modalı sarmalayıcı sınıfı sunucu modülünde bulunmalıdır."
  )

  # Durum ve Model filtresi yerel <select> (selectize = FALSE) kullanır: probe'un
  # native-select doğrulaması gerçek UI sözleşmesine dayanır.
  expect_gte(
    lengths(regmatches(
      ui_metin,
      gregexpr("selectize = FALSE", ui_metin, fixed = TRUE)
    )),
    2L
  )
})

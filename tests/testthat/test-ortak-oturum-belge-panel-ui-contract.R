# ==============================================================================
# Dosya Yolu: tests/testthat/test-ortak-oturum-belge-panel-ui-contract.R
# Açıklama: Ortak Belgeler paneli yükleme yüzeyi + boş durum UI sözleşmeleri:
#           - Kompakt sürükle-bırak yüzeyi ("Belgeleri buraya sürükleyin" +
#             "Belge Seç") gerçek fileInput'a bağlıdır; bırakılan dosyalar JS
#             köprüsüyle mevcut doğrulanmış sunucu yolundan geçer.
#           - Boş durum panel alanını doldurur, metni kırpılmaz ve gereksiz
#             kaydırma çubuğu üretmez.
#           - Ortak Çalışmalarım kartları birbirine değmez (uiOutput ızgara
#             sarmalayıcı düzeltmesi).
#           Testler render tabanlı + statiktir: tarayıcı/DB/LLM/ağ GEREKMEZ.
# ==============================================================================

testthat::skip_if_not_installed("shiny")

suppressPackageStartupMessages(library(shiny))

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }

  source(file.path(repo_root, "R", "module_ortak_oturum_belge_paneli.R"),
         encoding = "UTF-8", local = globalenv())
})

.oo_belge_ui_html <- function(tag) {
  paste(format(tag), collapse = "\n")
}

.oo_belge_ui_oku <- function(rel_path) {
  yol <- file.path(resolve_repo_root_for_tests(), rel_path)
  baytlar <- readBin(yol, what = "raw", n = file.info(yol)$size)
  iconv(rawToChar(baytlar), from = "UTF-8", to = "UTF-8", sub = "byte")
}

test_that("belge yükleme yüzeyi sürükle-bırak hedefi + Belge Seç eylemi + kural ipucu taşır", {
  html <- .oo_belge_ui_html(oo_belge_yukleme_alani_html(
    yukle_input_id = "oda-belge_dosya_yukle",
    izinli_uzantilar = c("pdf", "docx", "xlsx", "txt", "csv", "png"),
    limit_mb = 25L
  ))

  # Gerçek bırakma hedefi: delege JS köprüsünün aradığı işaret + erişilebilirlik.
  expect_true(grepl("data-oo-belge-drop", html, fixed = TRUE))
  expect_true(grepl('role="button"', html, fixed = TRUE))
  expect_true(grepl('tabindex="0"', html, fixed = TRUE))

  # Eylem dili: sürükle VEYA belge seç.
  expect_true(grepl("Belgeleri buraya sürükleyin", html, fixed = TRUE))
  expect_true(grepl("veya", html, fixed = TRUE))
  expect_true(grepl("Belge Seç", html, fixed = TRUE))

  # Yükleme ikonu + gerçek fileInput (çoklu + uzantı filtresi) yüzeyin içindedir.
  expect_true(grepl("cloud-arrow-up", html, fixed = TRUE))
  expect_true(grepl('id="oda-belge_dosya_yukle"', html, fixed = TRUE))
  expect_true(grepl('multiple="multiple"', html, fixed = TRUE))
  expect_true(grepl(".pdf,.docx,.xlsx", html, fixed = TRUE))

  # Boyut + tür rehberi görünür.
  expect_true(grepl("En fazla 25 MB", html, fixed = TRUE))
  expect_true(grepl("PDF, DOCX, XLSX", html, fixed = TRUE))
})

test_that("bırakma köprüsü dosyaları gizli girdiye atar ve change tetikler", {
  js <- .oo_belge_ui_oku("www/js/ortak_oturumlar.js")

  expect_true(grepl("data-oo-belge-drop", js, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("'dragover'", js, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("'drop'", js, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("new DataTransfer()", js, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("input.files = dt.files", js, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("dispatchEvent(new Event('change', { bubbles: true }))", js, fixed = TRUE, useBytes = TRUE))

  # Kimlik CSS seçicisine gömülmez; girdi yüzeyin İÇİNDEN bulunur.
  expect_true(grepl("querySelector('input[type=\"file\"]')", js, fixed = TRUE, useBytes = TRUE))

  # Klavye erişimi: Enter/Space dosya seçiciyi açar.
  expect_true(grepl("ev.key !== 'Enter' && ev.key !== ' '", js, fixed = TRUE, useBytes = TRUE))
})

test_that("boş durum başlık + tam metin taşır; kırpma sözleşmesi yoktur", {
  panel_txt <- .oo_belge_ui_oku("R/module_ortak_oturum_belge_paneli.R")

  expect_true(grepl("oo-bos-belge-baslik", panel_txt, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("oo-bos-belge-metin", panel_txt, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl(enc2utf8("Henüz ortak belge yok"), panel_txt, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl(
    enc2utf8("Yüklediğiniz belgeler tüm katılımcılarla paylaşılır; seçilenler yapay zekâ bağlamına eklenir."),
    panel_txt, fixed = TRUE, useBytes = TRUE
  ))

  css <- .oo_belge_ui_oku("www/css/ortak_oturumlar_room.css")

  # Boş durum panel alanını doldurur (renderUI sarmalayıcısı esnek zincirde).
  expect_true(grepl(".oo-belgeler-listesi > .shiny-html-output", css, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl(".oo-belgeler-listesi .oo-bos-belge", css, fixed = TRUE, useBytes = TRUE))

  # Metin tam sarılır; kırpma yok. Konum + substr KARAKTER tabanlıdır
  # (useBytes bayt ofsetleri Türkçe metinle kayar; repo test kuralı).
  expect_true(grepl("overflow-wrap: anywhere;", css, fixed = TRUE, useBytes = TRUE))
  bos_blok_baslangic <- regexpr(".oo-bos-belge .oo-bos-belge-metin", css, fixed = TRUE)
  expect_true(bos_blok_baslangic > 0)
  bos_blok <- substr(css, bos_blok_baslangic, bos_blok_baslangic + 400L)
  expect_false(grepl("text-overflow", bos_blok, fixed = TRUE))
  expect_false(grepl("line-clamp", bos_blok, fixed = TRUE))
})

test_that("Ortak Çalışmalarım kartları uiOutput sarmalayıcısında da ızgara boşluğu alır", {
  css <- .oo_belge_ui_oku("www/css/ortak_oturumlar.css")

  # Kartların gerçek ebeveyni (renderUI çıktı düğümü) ızgara + boşluk taşır;
  # kartlar birbirine değmez. Konum + substr KARAKTER tabanlıdır.
  expect_true(grepl(".oo-oturum-listesi > .shiny-html-output", css, fixed = TRUE, useBytes = TRUE))
  wrapper_pos <- regexpr(".oo-oturum-listesi > .shiny-html-output", css, fixed = TRUE)
  wrapper_blok <- substr(css, wrapper_pos, wrapper_pos + 300L)
  expect_true(grepl("display: grid;", wrapper_blok, fixed = TRUE))
  expect_true(grepl("gap: 16px;", wrapper_blok, fixed = TRUE))
})

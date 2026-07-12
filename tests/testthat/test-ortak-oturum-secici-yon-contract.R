# ==============================================================================
# Dosya Yolu: tests/testthat/test-ortak-oturum-secici-yon-contract.R
# Açıklama: Ortak Söyleşi kompozer seçicileri (Model / Persona / Araç) YUKARI
#           açılma sözleşmesi. Seçiciler görünüm alanının en altındadır; menü
#           bileşenin desteklediği dropup yoluyla (shinyWidgets up=TRUE ->
#           sw-dropup-content) yukarı açılır ve panel içi kaydırma sınırıyla
#           yakınlaştırılmış/dar görünümlerde de ekran içinde kalır.
#           Testler render tabanlı + statiktir: tarayıcı/DB/LLM/ağ GEREKMEZ.
# ==============================================================================

testthat::skip_if_not_installed("shiny")
testthat::skip_if_not_installed("shinyWidgets")

suppressPackageStartupMessages(library(shiny))

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }

  source(file.path(repo_root, "R", "helpers_ortak_oturum_permissions.R"),
         encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "helpers_ortak_oturum_sunum.R"),
         encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "helpers_ortak_oturum_arac.R"),
         encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "module_ortak_oturum_room_ui.R"),
         encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "module_ortak_oturum_arac.R"),
         encoding = "UTF-8", local = globalenv())
})

.oo_secici_html <- function(tag) {
  paste(format(tag), collapse = "\n")
}

.oo_secici_oku <- function(rel_path) {
  yol <- file.path(resolve_repo_root_for_tests(), rel_path)
  baytlar <- readBin(yol, what = "raw", n = file.info(yol)$size)
  iconv(rawToChar(baytlar), from = "UTF-8", to = "UTF-8", sub = "byte")
}

test_that("model seçici menüsü yukarı açılır (sw-dropup-content)", {
  html <- .oo_secici_html(oo_model_secici_html(
    modeller = c("model-a", "model-b"),
    adlar = c("Model A", "Model B"),
    aciklamalar = list("model-a" = "A modeli"),
    secili = "model-a",
    dropdown_id = "oda-oda_model_dropdown",
    secim_input_id = "oda-oda_model_secimi"
  ))

  expect_true(grepl("sw-dropup-content", html, fixed = TRUE))
  # Aşağı açılan içerik sınıfı TEK başına kalmaz (dropup sınıfı yanında).
  expect_true(grepl("sw-dropdown-content animated sw-dropup-content", html, fixed = TRUE))
})

test_that("persona seçici menüsü yukarı açılır (yetkili görünüm)", {
  html <- .oo_secici_html(oo_persona_secici_html(
    "selin", yetkili = TRUE,
    dropdown_id = "oda-oda_persona_dropdown",
    secim_input_id = "oda-oda_persona_secimi"
  ))

  expect_true(grepl("sw-dropup-content", html, fixed = TRUE))

  # Yetkisiz görünüm salt-okunur rozettir; açılır menü içermez.
  rozet <- .oo_secici_html(oo_persona_secici_html(
    "selin", yetkili = FALSE,
    dropdown_id = "oda-oda_persona_dropdown",
    secim_input_id = "oda-oda_persona_secimi"
  ))
  expect_false(grepl("sw-dropdown", rozet, fixed = TRUE))
})

test_that("araç seçici menüsü yukarı açılır ve ayar blokları menü içinde kalır", {
  ayarlar <- oo_arac_varsayilan_ayarlar()
  html <- .oo_secici_html(oo_arac_secici_html(
    katalog = list(list(
      family = "sql_analysis", baslik = "Proje ve Kaynak Analizi",
      aciklama = "Kurumsal veri analizi", ikon = "chart-line",
      renk = "#3b82f6", destekleniyor = TRUE
    )),
    ayarlar = ayarlar,
    dropdown_id = "oda-oda_arac_dropdown",
    secim_input_id = "oda-oda_arac_secimi",
    ayar_input_id = "oda-oda_arac_ayari"
  ))

  expect_true(grepl("sw-dropup-content", html, fixed = TRUE))
})

test_that("seçici kaynak dosyalarında aşağı açılan (up = FALSE) seçici kalmaz", {
  ui_txt <- .oo_secici_oku("R/module_ortak_oturum_room_ui.R")
  arac_txt <- .oo_secici_oku("R/module_ortak_oturum_arac.R")

  expect_false(grepl("up = FALSE", ui_txt, fixed = TRUE, useBytes = TRUE))
  expect_false(grepl("up = FALSE", arac_txt, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("up = TRUE", ui_txt, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("up = TRUE", arac_txt, fixed = TRUE, useBytes = TRUE))
})

test_that("dropup paneli için boşluk ve panel içi kaydırma sınırı tanımlıdır", {
  css <- .oo_secici_oku("www/css/ortak_oturumlar_room.css")

  # Yukarı açılan panel butonla arasında boşluk bırakır ve mesaj akışının
  # üzerinde kalır (kırpılma/altında kalma yok).
  expect_true(grepl('.oo-secici .sw-dropup-content[id^="sw-content-"]', css, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("bottom: calc(100% + 8px);", css, fixed = TRUE, useBytes = TRUE))

  # Uzun kataloglar panel İÇİNDE kayar; tüm sayfa kaydırılmaz (125-150% yakınlaştırma).
  expect_true(grepl("max-height: min(56vh, 460px);", css, fixed = TRUE, useBytes = TRUE))
})

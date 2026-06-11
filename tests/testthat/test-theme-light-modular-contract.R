# ==============================================================================
# Dosya Yolu: tests/testthat/test-theme-light-modular-contract.R
# Açıklama: Açık tema (light theme) ALAN-ODAKLI mimari sözleşmesi.
#
#           Eski mimari, 13 dosyalık bir override/patch zinciriydi
#           (theme_light + extras + refinements + 6 modül + polish +
#           overhaul + overhaul_phase2 + user_polish + user_polish_v2) ve
#           aynı seçici 5-8 kez yeniden tanımlanıyordu. Bu zincir, kaskad
#           sonucu bire bir korunarak 7 alan dosyasına konsolide edildi.
#
#           Bu test üç şeyi kalıcı olarak engeller:
#             1. Yeni bir "override/patch katmanı" tema dosyası eklenmesi
#                (kanonik dosya kümesi donduruldu).
#             2. Eski patch-zinciri dosyalarının geri gelmesi (tombstone).
#             3. Aynı seçicinin birden fazla tema dosyasında yeniden
#                tanımlanması (tek-tanım sözleşmesi) — patch zincirinin
#                imzası buydu.
#
#           Ayrıca açık tema kurallarının html[data-theme="light"] kapsamı
#           ve alan dosyalarının gerçek (DOM'da var olan) seçicilere
#           bağlandığı çapalarla korunur. (Eski test, DOM'da hiç var
#           olmamış hayalet seçicilere çapalanmıştı; bu test yalnızca
#           runtime kaynaklarında doğrulanmış seçiciler kullanır.)
#
# Kapsam: ağır Shiny runtime istemez; yalnızca dosya/manifest denetimi.
# ==============================================================================

.repo_root_theme_light <- function() {
  candidates <- unique(normalizePath(
    c(getwd(),
      file.path(getwd(), ".."),
      file.path(getwd(), "..", "..")),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "R")) &&
        dir.exists(file.path(candidate, "tests", "testthat"))) {
      return(candidate)
    }
  }

  stop("Repo kökü bulunamadı.", call. = FALSE)
}

.read_repo_text_theme_light <- function(rel_path) {
  full_path <- file.path(.repo_root_theme_light(), rel_path)
  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) return("")
  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )
  if (is.na(txt)) txt <- ""
  txt <- gsub("\r\n?|\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

# CSS seçici çıkarımı (yorumlar temizlenir; @media gövdesine iner;
# @keyframes/@font-face gövdeleri seçici sayılmaz).
.theme_light_extract_selectors <- function(css_text) {
  css <- gsub("/\\*[\\s\\S]*?\\*/", "", css_text, perl = TRUE)
  # @keyframes bloklarını tamamen kaldır (yüzde adımları seçici değildir).
  css <- gsub("@keyframes[^{]*\\{[^{}]*(\\{[^{}]*\\}[^{}]*)*\\}", "", css, perl = TRUE)
  matches <- gregexpr("([^{}]+)\\{", css, perl = TRUE)[[1]]
  if (identical(matches[1], -1L)) return(character(0))
  raw <- regmatches(css, list(matches))[[1]]
  raw <- sub("\\{$", "", raw)
  raw <- unlist(strsplit(raw, ",", fixed = TRUE), use.names = FALSE)
  raw <- trimws(gsub("\\s+", " ", raw, perl = TRUE))
  raw <- raw[nzchar(raw)]
  raw <- raw[!grepl("^(@|from$|to$|[0-9.]+%)", raw, perl = TRUE)]
  raw
}

# Kanonik açık tema alan dosyaları (yükleme sırasına göre).
.theme_light_canonical_files <- c(
  "www/css/theme_light_core.css",
  "www/css/theme_light_welcome.css",
  "www/css/theme_light_chat.css",
  "www/css/theme_light_modals.css",
  "www/css/theme_light_bilge_yolac.css",
  "www/css/theme_light_personalization.css",
  "www/css/theme_light_pages.css"
)

# Kaldırılan eski patch-zinciri dosyaları: geri getirilemez (tombstone).
.theme_light_tombstoned_files <- c(
  "www/css/theme_light.css",
  "www/css/theme_light_extras.css",
  "www/css/theme_light_refinements.css",
  "www/css/theme_light_polish.css",
  "www/css/theme_light_overhaul.css",
  "www/css/theme_light_overhaul_phase2.css",
  "www/css/theme_light_user_polish.css",
  "www/css/theme_light_user_polish_v2.css"
)

# Bilinçli tema-bağımsız (her iki temada geçerli) seçici aileleri.
# Bunlar dışında her tema kuralı html[data-theme="light"] kapsamında olmalı.
.theme_light_unscoped_allowlist_patterns <- c(
  "^\\.highcharts-grid-line",
  "^\\.stt-modal(-header)? \\.modal-title",
  "^\\.(month-group|gallery-month-group|saved-chats-month-group|image-gallery-month-group)",
  "^\\.(saved-chats-month-count|month-count-badge)",
  "^\\.modern-welcome-bg-grid",
  "^\\.modern-welcome-action-btn"
)

.theme_light_selector_is_allowed_unscoped <- function(selector) {
  any(vapply(
    .theme_light_unscoped_allowlist_patterns,
    function(p) grepl(p, selector, perl = TRUE),
    logical(1)
  ))
}

test_that("kanonik açık tema dosya kümesi donmuştur: ekleme/eksilme bilinçli olmalı", {
  root <- .repo_root_theme_light()

  for (rel in .theme_light_canonical_files) {
    expect_true(
      file.exists(file.path(root, rel)),
      info = sprintf("%s diskte bulunmalı.", rel)
    )
  }

  # www/css altında theme_light_*.css deseniyle YALNIZCA kanonik dosyalar
  # bulunabilir. Yeni bir tema katmanı dosyası eklemek bu listeyi ve
  # manifesti birlikte güncellemeyi gerektirir; "bir override dosyası daha"
  # deseni bilinçli olarak engellenir.
  on_disk <- list.files(
    file.path(root, "www", "css"),
    pattern = "^theme_light_.*\\.css$"
  )

  expect_setequal(
    file.path("www/css", on_disk),
    .theme_light_canonical_files
  )
})

test_that("eski patch-zinciri tema dosyaları geri getirilemez (tombstone)", {
  root <- .repo_root_theme_light()
  manifest_txt <- .read_repo_text_theme_light("R/config_ui_assets.R")

  for (rel in .theme_light_tombstoned_files) {
    expect_false(
      file.exists(file.path(root, rel)),
      info = sprintf(
        "%s eski patch zincirinin parçasıydı ve kaldırıldı; geri eklemek yerine ilgili alan dosyasındaki kuralı genişletin.",
        rel
      )
    )

    manifest_ref <- sub("^www/", "", rel)
    expect_false(
      grepl(paste0('"', manifest_ref, '"'), manifest_txt, fixed = TRUE),
      info = sprintf("%s manifestte referans edilmemeli.", manifest_ref)
    )
  }
})

test_that("UI varlık manifesti tema alan dosyalarını doğru sırayla yükler", {
  manifest_txt <- .read_repo_text_theme_light("R/config_ui_assets.R")
  expect_true(nzchar(manifest_txt), info = "R/config_ui_assets.R okunamadı.")

  position_of <- function(needle) {
    idx <- regexpr(needle, manifest_txt, fixed = TRUE, useBytes = TRUE)
    if (idx[1] < 1) NA_integer_ else as.integer(idx[1])
  }

  pos_tokens <- position_of('"css/theme_tokens.css"')
  pos_core <- position_of('"css/theme_light_core.css"')
  pos_welcome <- position_of('"css/theme_light_welcome.css"')
  pos_chat <- position_of('"css/theme_light_chat.css"')
  pos_modals <- position_of('"css/theme_light_modals.css"')
  pos_bilge <- position_of('"css/theme_light_bilge_yolac.css"')
  pos_personal <- position_of('"css/theme_light_personalization.css"')
  pos_pages <- position_of('"css/theme_light_pages.css"')
  pos_animations <- position_of('"css/animations.css"')

  for (item in list(
    list(name = "theme_tokens", v = pos_tokens),
    list(name = "theme_light_core", v = pos_core),
    list(name = "theme_light_welcome", v = pos_welcome),
    list(name = "theme_light_chat", v = pos_chat),
    list(name = "theme_light_modals", v = pos_modals),
    list(name = "theme_light_bilge_yolac", v = pos_bilge),
    list(name = "theme_light_personalization", v = pos_personal),
    list(name = "theme_light_pages", v = pos_pages)
  )) {
    expect_false(
      is.na(item$v),
      info = sprintf("%s manifest içinde bulunmalı.", item$name)
    )
  }

  expect_true(pos_tokens < pos_core,
              info = "tokens core'dan önce yüklenmeli.")
  expect_true(pos_core < pos_welcome,
              info = "core welcome'dan önce yüklenmeli.")
  expect_true(pos_welcome < pos_chat,
              info = "welcome chat'ten önce yüklenmeli.")
  expect_true(pos_chat < pos_modals,
              info = "chat modals'tan önce yüklenmeli.")
  expect_true(pos_modals < pos_bilge,
              info = "modals bilge_yolac'tan önce yüklenmeli.")
  expect_true(pos_bilge < pos_personal,
              info = "bilge_yolac personalization'dan önce yüklenmeli.")
  expect_true(pos_personal < pos_pages,
              info = "personalization pages'ten önce yüklenmeli.")
  expect_true(pos_pages < pos_animations,
              info = "pages animations.css'ten önce yüklenmeli.")
})

test_that("tek-tanım sözleşmesi: aynı seçici birden fazla tema dosyasında tanımlanamaz", {
  selector_files <- list()

  for (rel in .theme_light_canonical_files) {
    txt <- .read_repo_text_theme_light(rel)
    expect_true(nzchar(txt), info = sprintf("%s okunamadı.", rel))

    selectors <- unique(.theme_light_extract_selectors(txt))
    for (sel in selectors) {
      selector_files[[sel]] <- c(selector_files[[sel]], rel)
    }
  }

  duplicated_selectors <- names(selector_files)[
    vapply(selector_files, length, integer(1)) > 1
  ]

  expect_equal(
    length(duplicated_selectors),
    0L,
    info = paste(
      "Aynı seçici birden fazla açık tema dosyasında tanımlanmış.",
      "Eski override-zinciri desenine geri dönmeyin; kuralı tek sahibi olan",
      "alan dosyasında genişletin. Tekrarlananlar:",
      paste(utils::head(duplicated_selectors, 12), collapse = " | ")
    )
  )
})

test_that("açık tema kuralları light kapsamındadır; tema-bağımsız istisnalar bilinçlidir", {
  for (rel in .theme_light_canonical_files) {
    txt <- .read_repo_text_theme_light(rel)
    selectors <- .theme_light_extract_selectors(txt)

    unscoped <- selectors[!grepl('[data-theme="light"]', selectors, fixed = TRUE)]
    unexpected <- unscoped[!vapply(
      unscoped,
      .theme_light_selector_is_allowed_unscoped,
      logical(1)
    )]

    expect_equal(
      length(unexpected),
      0L,
      info = paste(
        sprintf("%s içinde kapsamsız (light dışı) seçici bulundu:", rel),
        paste(utils::head(unexpected, 10), collapse = " | "),
        "Tema-bağımsız bir taban kural gerekiyorsa allowlist'i bilinçli güncelleyin.",
        sep = "\n"
      )
    )
  }
})

test_that("alan dosyaları gerçek (runtime'da var olan) seçici çapalarını taşır", {
  # Çapalar runtime kaynaklarıyla doğrulanmış GERÇEK sınıflardır:
  #   .modern-welcome-card     -> R/welcome_screen_modern.R
  #   .input-wrapper           -> chat giriş alanı
  #   .message-actions         -> R mesaj eylem butonları
  #   .tag-like                -> geri bildirim modal etiketleri
  #   .cc-badge / .cc-character-badge -> R/module_claude_code_ui.R + server setup
  #   .mode-card               -> deneyim modu kartları
  #   .destek-nps-btn          -> R/module_destek_geri_bildirim.R (NPS 0-10)
  #   .month-group             -> kayıtlı söyleşi/galeri ay grupları
  core_txt <- .read_repo_text_theme_light("www/css/theme_light_core.css")
  expect_true(grepl(".sidebar-menu", core_txt, fixed = TRUE),
              info = "core kenar çubuğu kurallarını taşımalı.")

  welcome_txt <- .read_repo_text_theme_light("www/css/theme_light_welcome.css")
  expect_true(grepl(".modern-welcome-card", welcome_txt, fixed = TRUE),
              info = "welcome cam karşılama kartı kuralını taşımalı.")
  expect_true(
    grepl("rgba(255, 255, 255, 0.22)", welcome_txt, fixed = TRUE) ||
      grepl("rgba(255,255,255,0.22)", welcome_txt, fixed = TRUE),
    info = "Welcome cam yüzeyi şeffaflığı (~0.22 alpha) korunmalı."
  )
  # Not: Eski testteki blur(18px) çapası ölü metindi; kaskadın gerçek
  # kazananı blur(10px) saturate(132%) idi (sonraki polish katmanı ezmişti).
  # Konsolide dosya yalnızca etkin değeri taşır.
  expect_true(grepl("backdrop-filter: blur(10px) saturate(132%)", welcome_txt, fixed = TRUE),
              info = "Welcome cam yüzeyi etkin blur değeri korunmalı.")

  chat_txt <- .read_repo_text_theme_light("www/css/theme_light_chat.css")
  expect_true(grepl(".input-wrapper", chat_txt, fixed = TRUE),
              info = ".input-wrapper kuralı chat dosyasında olmalı.")
  expect_true(
    grepl("border: 1px solid transparent", chat_txt, fixed = TRUE),
    info = "Chat input gri kenarlık temizliği korunmalı."
  )
  expect_true(grepl(".message-actions", chat_txt, fixed = TRUE),
              info = "Mesaj eylem butonları chat dosyasında olmalı.")
  expect_true(grepl("#chat_content_container", chat_txt, fixed = TRUE),
              info = "Söyleşi konteyneri kuralı chat dosyasında olmalı.")

  modals_txt <- .read_repo_text_theme_light("www/css/theme_light_modals.css")
  expect_true(grepl(".tag-like.active", modals_txt, fixed = TRUE),
              info = "tag-like.active kuralı (pozitif feedback) olmalı.")
  expect_true(
    grepl("22, 163, 74", modals_txt, fixed = TRUE) ||
      grepl("#15803d", modals_txt, fixed = TRUE),
    info = "Pozitif feedback aktif etiketi yeşil ton kullanmalı."
  )

  bilge_txt <- .read_repo_text_theme_light("www/css/theme_light_bilge_yolac.css")
  expect_true(grepl(".cc-badge", bilge_txt, fixed = TRUE),
              info = "AJAN rozeti (.cc-badge) kuralı olmalı.")
  expect_true(grepl(".cc-character-badge", bilge_txt, fixed = TRUE),
              info = "Karakter rozeti kuralı olmalı.")
  expect_true(grepl("--char-accent", bilge_txt, fixed = TRUE),
              info = "Karakter rozeti --char-accent kimliğini taşımalı.")
  expect_true(grepl(".cc-tool-block", bilge_txt, fixed = TRUE),
              info = "Bilge Yolaç tool blok kuralı olmalı.")

  personal_txt <- .read_repo_text_theme_light("www/css/theme_light_personalization.css")
  expect_true(grepl("--char-accent", personal_txt, fixed = TRUE),
              info = "Karakter renk kimliği --char-accent korunmalı.")
  expect_true(grepl(".mode-card", personal_txt, fixed = TRUE),
              info = "Deneyim modu kart kuralı olmalı.")
  expect_true(grepl(".character-info-container", personal_txt, fixed = TRUE),
              info = "Karakter bilgi konteyneri kuralı olmalı.")

  pages_txt <- .read_repo_text_theme_light("www/css/theme_light_pages.css")
  expect_true(grepl(".destek-nps-btn", pages_txt, fixed = TRUE),
              info = "NPS 0-10 buton kuralı pages dosyasında olmalı.")
  expect_true(grepl(".month-group", pages_txt, fixed = TRUE),
              info = "Ay grubu kuralları pages dosyasında olmalı.")
  expect_true(grepl(".health-tooltip", pages_txt, fixed = TRUE),
              info = "Sistem Durumu tooltip kuralı pages dosyasında olmalı.")
})

test_that("theme_tokens.css koyu varsayılan + açık tema token bloklarını taşır", {
  tokens_txt <- .read_repo_text_theme_light("www/css/theme_tokens.css")
  expect_true(nzchar(tokens_txt), info = "theme_tokens.css okunamadı.")

  expect_true(grepl("--mb-brand-primary", tokens_txt, fixed = TRUE),
              info = "Kurumsal marka tokenları tanımlı olmalı.")
  expect_true(grepl(":root", tokens_txt, fixed = TRUE),
              info = "Koyu tema varsayılan token bloğu olmalı.")
  expect_true(grepl('html[data-theme="light"]', tokens_txt, fixed = TRUE),
              info = "Açık tema token override bloğu olmalı.")
})

test_that("açık tema dosyaları CDN/dış kaynak referansı içermez", {
  for (rel in c(.theme_light_canonical_files, "www/css/theme_tokens.css")) {
    txt <- .read_repo_text_theme_light(rel)

    expect_false(
      grepl("@import\\s+url\\(['\"]https?://", txt, perl = TRUE,
            useBytes = TRUE),
      info = sprintf("%s dosyası @import ile dış kaynağa bağlanmamalıdır.", rel)
    )

    no_comments <- gsub("/\\*[\\s\\S]*?\\*/", "", txt, perl = TRUE)

    expect_false(
      grepl("url\\(\\s*['\"]?https?://", no_comments, perl = TRUE,
            useBytes = TRUE),
      info = sprintf("%s dosyası url() ile internete bağlanmamalıdır.", rel)
    )
  }
})

# ==============================================================================
# Dosya Yolu: tests/testthat/test-theme-light-modular-contract.R
# Açıklama: Açık tema (light theme) cilası için odaklı yardımcı CSS
#           dosyalarının manifest sırasını ve içeriklerini korur. Bu
#           dosyalar maintainability ratchet limitlerini aşmadan light
#           tema sözleşmesini taşımak için bilinçle birden çok dosyaya
#           bölünmüştür.
#
# Kapsam (heavy Shiny runtime istemez):
#   1. www/css/theme_light_welcome.css var ve manifest içinde.
#   2. www/css/theme_light_chat.css var ve manifest içinde.
#   3. www/css/theme_light_modals.css var ve manifest içinde.
#   4. www/css/theme_light_bilge_yolac.css var ve manifest içinde.
#   5. www/css/theme_light_personalization.css var ve manifest içinde.
#   6. www/css/theme_light_polish.css var ve manifest içinde.
#   7. Manifest yükleme sırası: theme_light_refinements.css öncesinde,
#      welcome -> chat -> modals -> bilge_yolac -> personalization ->
#      polish şeklinde gelir; animations.css'ten önce yer alır.
#   8. theme_light_welcome.css welcome cam yüzeyi şeffaflığını taşır
#      (rgba 0.22 / blur 18px tonlu yeni ayarlar).
#   9. theme_light_modals.css feedback modal pozitif tag yeşil
#      yapılandırmasını içerir.
#  10. theme_light_chat.css chat input gri kenarlık temizliği yapar.
#  11. theme_light_bilge_yolac.css "Ajan" rozetini kurumsal mavi yüzeye
#      çeker ve karakter rozetini --char-accent kimliği ile dolu tutar.
#  12. theme_light_personalization.css karakter buton aktif renk
#      kimliğini --char-accent üzerinden taşır.
#  13. theme_light_polish.css admin tooltip tek katman ve hero başlık
#      kurumsal mavi şerit sözleşmesini içerir.
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

.theme_light_new_files <- c(
  "www/css/theme_light_welcome.css",
  "www/css/theme_light_chat.css",
  "www/css/theme_light_modals.css",
  "www/css/theme_light_bilge_yolac.css",
  "www/css/theme_light_personalization.css",
  "www/css/theme_light_polish.css"
)

test_that("yeni açık tema odaklı CSS dosyaları diskte mevcut", {
  for (rel in .theme_light_new_files) {
    full_path <- file.path(.repo_root_theme_light(), rel)
    expect_true(
      file.exists(full_path),
      info = sprintf("%s dosyası diskte bulunmalı.", rel)
    )
  }
})

test_that("UI varlık manifesti yeni açık tema dosyalarını sıralı yükler", {
  manifest_txt <- .read_repo_text_theme_light("R/config_ui_assets.R")
  expect_true(nzchar(manifest_txt), info = "R/config_ui_assets.R okunamadı.")

  position_of <- function(needle) {
    idx <- regexpr(needle, manifest_txt, fixed = TRUE, useBytes = TRUE)
    if (idx[1] < 1) NA_integer_ else as.integer(idx[1])
  }

  pos_refinements <- position_of('"css/theme_light_refinements.css"')
  pos_welcome <- position_of('"css/theme_light_welcome.css"')
  pos_chat <- position_of('"css/theme_light_chat.css"')
  pos_modals <- position_of('"css/theme_light_modals.css"')
  pos_bilge <- position_of('"css/theme_light_bilge_yolac.css"')
  pos_personal <- position_of('"css/theme_light_personalization.css"')
  pos_polish <- position_of('"css/theme_light_polish.css"')
  pos_animations <- position_of('"css/animations.css"')

  for (item in list(
    list(name = "theme_light_welcome", v = pos_welcome),
    list(name = "theme_light_chat", v = pos_chat),
    list(name = "theme_light_modals", v = pos_modals),
    list(name = "theme_light_bilge_yolac", v = pos_bilge),
    list(name = "theme_light_personalization", v = pos_personal),
    list(name = "theme_light_polish", v = pos_polish)
  )) {
    expect_false(
      is.na(item$v),
      info = sprintf("%s manifest içinde bulunmalı.", item$name)
    )
  }

  # Hepsi refinements'ten sonra ama animations'tan önce gelmeli
  expect_true(pos_refinements < pos_welcome,
              info = "welcome refinements'tan sonra yüklenmeli.")
  expect_true(pos_welcome < pos_chat,
              info = "welcome chat'ten önce yüklenmeli.")
  expect_true(pos_chat < pos_modals,
              info = "chat modals'tan önce yüklenmeli.")
  expect_true(pos_modals < pos_bilge,
              info = "modals bilge_yolac'tan önce yüklenmeli.")
  expect_true(pos_bilge < pos_personal,
              info = "bilge_yolac personalization'dan önce yüklenmeli.")
  expect_true(pos_personal < pos_polish,
              info = "personalization polish'ten önce yüklenmeli.")
  expect_true(pos_polish < pos_animations,
              info = "polish animations.css'ten önce yüklenmeli.")
})

test_that("theme_light_welcome.css cam yüzeyi daha şeffaf yapar (premium glass)", {
  txt <- .read_repo_text_theme_light("www/css/theme_light_welcome.css")
  expect_true(nzchar(txt), info = "theme_light_welcome.css okunamadı.")

  # Daha şeffaf welcome card arka planı (önceki 0.34/0.26 yerine ~0.22/0.16)
  expect_true(
    grepl("rgba(255, 255, 255, 0.22)", txt, fixed = TRUE) ||
      grepl("rgba(255,255,255,0.22)", txt, fixed = TRUE),
    info = "Welcome cam yüzeyi şeffaflığı düşürülmeli (~0.22 alpha)."
  )

  # Blur daha makul (18px) - önceki 26px yerine
  expect_true(
    grepl("blur(18px)", txt, fixed = TRUE),
    info = "Welcome cam yüzeyi blur miktarı 18px olarak ayarlanmalı."
  )

  # Son Konuşmalar ikon kutusunda beyaz solid kenarlık olmamalı
  expect_true(
    grepl("modern-welcome-preview-icon-box", txt, fixed = TRUE),
    info = "Son Konuşmalar ikon kutusu kuralı bulunmalı."
  )
})

test_that("theme_light_modals.css pozitif feedback aktif tag YEŞİL kullanır", {
  txt <- .read_repo_text_theme_light("www/css/theme_light_modals.css")
  expect_true(nzchar(txt), info = "theme_light_modals.css okunamadı.")

  expect_true(
    grepl("tag-like.active", txt, fixed = TRUE),
    info = "tag-like.active kuralı yer almalı (pozitif feedback)."
  )

  # Yeşil tonlama (rgba(22, 163, 74) veya #15803d kullanımı bekleniyor)
  expect_true(
    grepl("22, 163, 74", txt, fixed = TRUE) ||
      grepl("22,163,74", txt, fixed = TRUE) ||
      grepl("#15803d", txt, fixed = TRUE),
    info = "Pozitif feedback aktif etiketi yeşil renk tonu kullanmalı."
  )

  # Dosya Önizleme başlığı kurumsal mavi
  expect_true(
    grepl("file-preview-modal", txt, fixed = TRUE) &&
      grepl("mb-brand-primary", txt, fixed = TRUE),
    info = "Dosya Önizleme modal başlığı kurumsal mavi tasarımlı olmalı."
  )

  # Ay grubu sayaç rozeti turuncu
  expect_true(
    grepl("month-group", txt, fixed = TRUE) &&
      grepl("mb-brand-accent", txt, fixed = TRUE),
    info = "Ay grubu sayaç rozeti turuncu vurgu kullanmalı."
  )
})

test_that("theme_light_chat.css chat input gri kenarlığı temizler", {
  txt <- .read_repo_text_theme_light("www/css/theme_light_chat.css")
  expect_true(nzchar(txt), info = "theme_light_chat.css okunamadı.")

  expect_true(
    grepl(".input-wrapper", txt, fixed = TRUE),
    info = ".input-wrapper kuralı bulunmalı."
  )

  # border transparent veya none olmalı
  expect_true(
    grepl("border: 1px solid transparent", txt, fixed = TRUE) ||
      grepl("border:1px solid transparent", txt, fixed = TRUE),
    info = "Chat input gri kenarlık temizlenmelidir."
  )

  # AI mesaj başlığı kurumsal mavi olmalı
  expect_true(
    grepl(".message-bubble.ai-message .message-header", txt, fixed = TRUE) ||
      grepl(".ai-message .message-header", txt, fixed = TRUE),
    info = "AI mesaj başlığı kuralı bulunmalı."
  )

  # Kullanıcı mesaj başlığı destek teal/yeşil-mavi olmalı
  expect_true(
    grepl(".user-message .message-header", txt, fixed = TRUE) ||
      grepl(".message-bubble.user-message .message-header", txt, fixed = TRUE),
    info = "Kullanıcı mesaj başlığı kuralı bulunmalı."
  )

  # Mesaj eylem butonları varsayılan görünür
  expect_true(
    grepl(".message-actions", txt, fixed = TRUE) &&
      grepl("opacity: 1", txt, fixed = TRUE),
    info = "Mesaj eylem butonları varsayılan görünür opacity:1 olmalı."
  )

  # "Tümünü Temizle" pronounced kırmızı
  expect_true(
    grepl(".tumunu-temizle-btn", txt, fixed = TRUE) ||
      grepl(".clear-all-btn", txt, fixed = TRUE),
    info = "Tümünü Temizle buton kuralı bulunmalı."
  )
})

test_that("theme_light_bilge_yolac.css Ajan ve karakter rozetlerini düzgün tasarlar", {
  txt <- .read_repo_text_theme_light("www/css/theme_light_bilge_yolac.css")
  expect_true(nzchar(txt), info = "theme_light_bilge_yolac.css okunamadı.")

  # Ajan rozeti kurumsal mavi gradient
  expect_true(
    grepl(".cc-badge", txt, fixed = TRUE) ||
      grepl(".cc-agent-badge", txt, fixed = TRUE) ||
      grepl(".ajan-badge", txt, fixed = TRUE),
    info = "Ajan rozeti kuralı bulunmalı."
  )

  expect_true(
    grepl("mb-brand-primary", txt, fixed = TRUE),
    info = "Bilge Yolaç light tema kurumsal mavi tonlama kullanmalı."
  )

  # Karakter rozeti --char-accent kimliğini taşımalı
  expect_true(
    grepl(".cc-character-badge", txt, fixed = TRUE),
    info = "Karakter rozeti kuralı bulunmalı."
  )

  expect_true(
    grepl("--char-accent", txt, fixed = TRUE),
    info = "Karakter rozeti --char-accent değişkenini kullanmalı."
  )

  # Bilge Yolaç chat alanı light yüzey
  expect_true(
    grepl(".cc-output-wrapper", txt, fixed = TRUE) ||
      grepl(".cc-chat-area", txt, fixed = TRUE),
    info = "Bilge Yolaç chat akış konteyner kuralı bulunmalı."
  )
})

test_that("theme_light_personalization.css karakter renk kimliğini korur", {
  txt <- .read_repo_text_theme_light("www/css/theme_light_personalization.css")
  expect_true(nzchar(txt), info = "theme_light_personalization.css okunamadı.")

  expect_true(
    grepl("--char-accent", txt, fixed = TRUE),
    info = "Karakter butonları --char-accent değişkeni kullanmalı."
  )

  # Hover'da torch/glow halkası
  expect_true(
    grepl(".character-tab:hover", txt, fixed = TRUE) ||
      grepl(".character-selector-card:hover", txt, fixed = TRUE),
    info = "Karakter butonu hover kuralı bulunmalı."
  )

  # Karakter Bilgi konteyneri light yüzeye geçer
  expect_true(
    grepl(".character-info-container", txt, fixed = TRUE),
    info = "Karakter Bilgi konteyneri kuralı bulunmalı."
  )

  # Karakter Stil Kartı light yüzey
  expect_true(
    grepl(".character-style-card", txt, fixed = TRUE),
    info = "Karakter Stil Kartı kuralı bulunmalı."
  )

  # Deneyim Modu kartları
  expect_true(
    grepl(".mode-card", txt, fixed = TRUE),
    info = "Deneyim Modu kart kuralı bulunmalı."
  )
})

test_that("theme_light_polish.css admin tooltip tek katman ve hero başlık kurumsal mavi", {
  txt <- .read_repo_text_theme_light("www/css/theme_light_polish.css")
  expect_true(nzchar(txt), info = "theme_light_polish.css okunamadı.")

  # Bootstrap tooltip tek katman düzeltmesi
  expect_true(
    grepl(".tooltip .tooltip-inner", txt, fixed = TRUE),
    info = "Bootstrap tooltip tek katman kuralı bulunmalı."
  )

  expect_true(
    grepl("border: none", txt, fixed = TRUE) ||
      grepl("border:none", txt, fixed = TRUE),
    info = "Tooltip çift kenarlık temizliği için border: none uygulanmalı."
  )

  # Yönetici nav bar kurumsal mavi
  expect_true(
    grepl(".admin-tabs", txt, fixed = TRUE) ||
      grepl(".admin-nav", txt, fixed = TRUE),
    info = "Yönetici nav bar kuralı bulunmalı."
  )

  # Sayfa hero başlık
  expect_true(
    grepl(".page-hero", txt, fixed = TRUE) ||
      grepl(".page-header-hero", txt, fixed = TRUE) ||
      grepl(".destek-page-header", txt, fixed = TRUE),
    info = "Sayfa hero/başlık kuralı bulunmalı."
  )

  # Dosya Yönetimi drop zone
  expect_true(
    grepl(".fm-drop-zone", txt, fixed = TRUE) ||
      grepl(".file-drop-zone", txt, fixed = TRUE),
    info = "Dosya Yönetimi drop zone kuralı bulunmalı."
  )

  # Yenilikler bullet
  expect_true(
    grepl(".yenilikler-page ul li", txt, fixed = TRUE) ||
      grepl(".release-notes ul li", txt, fixed = TRUE),
    info = "Yenilikler bullet kuralı bulunmalı."
  )

  # Logout button light kontrastı
  expect_true(
    grepl(".mb-sidebar-logout-btn", txt, fixed = TRUE),
    info = "Sidebar logout butonu light kuralı bulunmalı."
  )
})

test_that("yeni açık tema dosyaları yalnızca light bağlamında etkilidir", {
  # Her dosya en az bir tane html[data-theme="light"] selector içermeli
  for (rel in .theme_light_new_files) {
    txt <- .read_repo_text_theme_light(rel)
    expect_true(
      grepl('html[data-theme="light"]', txt, fixed = TRUE),
      info = sprintf(
        "%s dosyası yalnızca light tema seçici altında çalışmalı.",
        rel
      )
    )
  }
})

test_that("yeni açık tema dosyaları CDN/dış kaynak referansı içermez", {
  for (rel in .theme_light_new_files) {
    txt <- .read_repo_text_theme_light(rel)

    # @import url('https://...') gibi dış kaynak yok
    expect_false(
      grepl("@import\\s+url\\(['\"]https?://", txt, perl = TRUE,
            useBytes = TRUE),
      info = sprintf(
        "%s dosyası @import ile dış kaynağa bağlanmamalıdır.",
        rel
      )
    )

    # http://veya https://ile başlayan url() yok (yorumlar hariç değil; tüm
    # text taranır; satırlarda /*...*/ yorumlarda da hassas davran).
    # Yorumları tamamen kaldıralım
    no_comments <- gsub("/\\*[\\s\\S]*?\\*/", "", txt, perl = TRUE)

    expect_false(
      grepl("url\\(\\s*['\"]?https?://", no_comments, perl = TRUE,
            useBytes = TRUE),
      info = sprintf(
        "%s dosyası url() ile internete bağlanmamalıdır.",
        rel
      )
    )
  }
})

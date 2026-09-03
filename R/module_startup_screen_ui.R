# R/module_startup_screen_ui.R
# Dosya Yolu: R/module_startup_screen_ui.R
# Açıklama: Derin uzay giriş ekranının UI tanımı. createStartupScreenUI() ince
#            bir kompozitördür; her bölüm (sürüm rozeti/modalı, Keşfet butonu,
#            mod seçim modalı, karakter adımı) odaklı saf bir .startup_*()
#            yapıcısına bölünmüştür. Üç deneyim-modu kartı, tekrarı önlemek için
#            tek bir veri-odaklı .startup_mode_card() üzerinden üretilir.
#            Sunucu mantığı R/module_startup_screen.R içinde kalır.
#            Üretilen tag ağacı birebir korunur
#            (bkz. tests/testthat/test-startup-screen-ui-refactor-contract.R).

#' Giriş Ekranı UI Oluşturma
#' @description Derin uzay giriş ekranının HTML yapısını oluşturur
#' @return HTML tagList nesnesi
createStartupScreenUI <- function() {
  tagList(
    # Giriş müzik verisi (istemci tarafında hemen erişilebilir)
    .startup_intro_music_tag(),

    # Ana konteyner
    tags$div(
      id = "deep-space-container",

      # Film tanecikli katman
      tags$div(class = "deep-space-overlay"),

      # Yükleme göstergesi
      tags$div(id = "deep-space-loading", "SİSTEM BAŞLATILIYOR..."),

      # Three.js tuval konteyneri
      tags$div(id = "deep-space-canvas"),

      # Şirket logosu (sol üst köşe)
      .startup_company_logo(),

      # Sürüm bilgilendirme rozeti (sağ üst köşe)
      .startup_version_badge(),

      # Sürüm bilgilendirme modalı
      .startup_version_modal(),

      # MERGEN BİLGE yazısı (sağ alt köşe)
      .startup_branding(),

      # Sinematik Keşfet butonu (alt orta)
      .startup_explore_button(),

      # Animasyonu bir daha gösterme onay kutusu (sol alt köşe)
      .startup_skip_checkbox(),

      # Sinematik mod seçim modalı
      .startup_mode_modal()
    )
  )
}

#' Giriş müziği veri etiketini üret
#' @description www/music/intro altındaki .mp3 dosyalarını istemciye taşıyan
#'   JSON script etiketini üretir; dosya yoksa NULL döner (tagList'te düşürülür).
#' @return tags$script veya NULL
.startup_intro_music_tag <- function() {
  # Giriş müzik dosyalarını ön yükle (sunucu mesajını beklemeden çalabilmesi için)
  intro_music_urls <- character(0)
  intro_dir <- file.path("www", "music", "intro")
  if (dir.exists(intro_dir)) {
    intro_files <- list.files(intro_dir, pattern = "\\.mp3$", full.names = FALSE, ignore.case = TRUE)
    if (length(intro_files) > 0) {
      intro_music_urls <- vapply(intro_files, function(f) {
        utils::URLencode(paste0("music/intro/", f))
      }, character(1), USE.NAMES = FALSE)
    }
  }

  if (length(intro_music_urls) > 0) {
    tags$script(type = "application/json", id = "intro-music-data",
      jsonlite::toJSON(list(files = intro_music_urls, volume = 0.25), auto_unbox = TRUE)
    )
  } else {
    NULL
  }
}

#' Şirket logosu (sol üst köşe)
#' @return tags$div
.startup_company_logo <- function() {
  tags$div(
    class = "deep-space-company-logo",
    tags$img(src = "img/company_logo.svg", alt = "Şirket Logosu")
  )
}

#' Sürüm bilgilendirme rozeti (sağ üst köşe)
#' @return tags$div
.startup_version_badge <- function() {
  tags$div(
    class = "deep-space-version-badge",
    tags$div(class = "version-badge-dot"),
    tags$i(class = "fas fa-bell version-badge-icon"),
    tags$span(class = "version-badge-text",
      paste0("v", get_current_version(), " - Yeni!")
    )
  )
}

#' Sürüm bilgilendirme modalı
#' @return tags$div
.startup_version_modal <- function() {
  tags$div(
    id = "surum-modal-overlay",
    class = "surum-modal-overlay",
    tags$div(
      class = "surum-modal-container",
      tags$div(
        class = "surum-modal-header",
        tags$div(
          class = "surum-modal-title-area",
          tags$div(class = "surum-modal-icon",
            tags$i(class = "fas fa-rocket")
          ),
          tags$h3(class = "surum-modal-title", "Yenilikler")
        ),
        tags$button(
          class = "surum-modal-close",
          tags$i(class = "fas fa-times")
        )
      ),
      tags$div(id = "surum-modal-content")
    )
  )
}

#' MERGEN Bilge markalaması (sağ alt köşe)
#' @return tags$div
.startup_branding <- function() {
  tags$div(
    class = "deep-space-branding",
    tags$div(
      class = "deep-space-branding-inner",
      # Modern welcome ile aynı yazım: "MERGEN" + "Bilge"
      # (BİLGE değil, "Bilge" - büyük/küçük harf modern welcome ile eşleşir).
      tags$h1(class = "deep-space-title", "MERGEN"),
      tags$h2(class = "deep-space-subtitle", "Bilge")
    )
  )
}

#' Sinematik Keşfet butonu (alt orta)
#' @return tags$div
.startup_explore_button <- function() {
  tags$div(
    class = "deep-space-explore-btn",
    tags$button(
      id = "explore-btn",
      class = "explore-cinematic-btn hover-glass-trigger",
      # Cam yansıması katmanı
      tags$div(class = "explore-glass-wrap",
        tags$div(class = "explore-glass-reflection")
      ),
      # SVG yılan izi animasyonu
      tags$svg(
        class = "explore-snake-svg",
        overflow = "visible",
        tags$defs(
          tags$linearGradient(
            id = "snake-gradient", x1 = "0%", y1 = "0%", x2 = "100%", y2 = "100%",
            tags$stop(offset = "0%", `stop-color` = "#818cf8"),
            tags$stop(offset = "100%", `stop-color` = "#34d399")
          )
        ),
        tags$rect(
          class = "explore-snake-trail",
          x = "0", y = "0", width = "100%", height = "100%",
          rx = "31", ry = "31",
          fill = "none",
          stroke = "url(#snake-gradient)",
          `stroke-width` = "4",
          `stroke-dasharray` = "30 70",
          `stroke-linecap` = "round",
          `pathLength` = "100"
        )
      ),
      # Buton içeriği
      tags$i(class = "fas fa-compass explore-btn-icon"),
      tags$span(class = "explore-btn-text", "KEŞFET"),
      tags$i(class = "fas fa-chevron-right explore-btn-arrow")
    )
  )
}

#' Animasyonu bir daha gösterme onay kutusu (sol alt köşe)
#' @return tags$div
.startup_skip_checkbox <- function() {
  tags$div(
    class = "deep-space-skip-checkbox",
    tags$label(
      tags$input(type = "checkbox", id = "skip-intro-checkbox"),
      tags$span(class = "skip-checkbox-text", "Bir daha gösterme")
    )
  )
}

#' Deneyim-modu kartlarının özellik göstergesi tanımları
#' @description Beş özellik göstergesinin sabit sırası ve açık/kapalı ikonları.
#'   tts/sound/character açık-kapalı için farklı ikon kullanır; followup/music
#'   ise aynı ikonu (yalnızca durum sınıfı/ipucu değişir).
#' @return Liste (her biri key/label/icon_off/icon_on)
.startup_mode_feature_defs <- function() {
  list(
    list(key = "tts",       label = "Sesli Yanıt",       icon_off = "fa-volume-mute", icon_on = "fa-volume-up"),
    list(key = "followup",  label = "Takip Soruları",    icon_off = "fa-comments",    icon_on = "fa-comments"),
    list(key = "music",     label = "Arka Plan Müziği",  icon_off = "fa-music",       icon_on = "fa-music"),
    list(key = "sound",     label = "Ses Efektleri",     icon_off = "fa-bell-slash",  icon_on = "fa-bell"),
    list(key = "character", label = "Asistan Karakteri", icon_off = "fa-user-slash",  icon_on = "fa-user-astronaut")
  )
}

#' Üç deneyim modu kartının veri tanımları
#' @description odak/denge/kesif kartlarının başlık, ikon, mikro-animasyon ve
#'   beş özelliğin açık/kapalı durumlarını tutar (özellik sırası feature_defs
#'   ile aynıdır).
#' @return Liste (her biri mode/title/short/icon/micro/states)
.startup_mode_card_defs <- function() {
  list(
    list(
      mode = "odak", title = "Odak", short = "Maksimum hız, mutlak sadelik.",
      icon = "fa-bolt", micro = "micro-anim-odak",
      states = c(tts = FALSE, followup = FALSE, music = FALSE, sound = FALSE, character = FALSE)
    ),
    list(
      mode = "denge", title = "Dinamik", short = "Akıllı asistan desteği.",
      icon = "fa-wand-magic-sparkles", micro = "micro-anim-denge",
      states = c(tts = FALSE, followup = TRUE, music = TRUE, sound = TRUE, character = FALSE)
    ),
    list(
      mode = "kesif", title = "Bütünleşik", short = "Tüm sistemlerin kilidini açın.",
      icon = "fa-microchip", micro = "micro-anim-kesif",
      states = c(tts = TRUE, followup = TRUE, music = TRUE, sound = TRUE, character = TRUE)
    )
  )
}

#' Tek bir özellik göstergesi (ikon) üret
#' @param feature feature_defs öğesi (key/label/icon_off/icon_on)
#' @param on Özelliğin açık olup olmadığı
#' @return tags$div
.startup_mode_feature_icon <- function(feature, on) {
  state_class <- if (isTRUE(on)) "on" else "off"
  state_word <- if (isTRUE(on)) "Aktif" else "Kapalı"
  icon_class <- if (isTRUE(on)) feature$icon_on else feature$icon_off

  tags$div(class = paste("cinematic-feature-icon", state_class), `data-feature` = feature$key,
    `data-tooltip` = paste0(feature$label, ": ", state_word),
    tags$i(class = paste("fas", icon_class))
  )
}

#' Tek bir deneyim modu kartı üret (veri-odaklı)
#' @param def mode_card_defs öğesi
#' @return tags$div
.startup_mode_card <- function(def) {
  feature_defs <- .startup_mode_feature_defs()
  indicators <- lapply(feature_defs, function(f) {
    .startup_mode_feature_icon(f, isTRUE(def$states[[f$key]]))
  })

  tags$div(
    class = "cinematic-mode-card spotlight-card",
    `data-mode` = def$mode,
    tags$div(
      class = "cinematic-card-inner",
      # Özellik göstergeleri (sağ üst köşe - ikonlu)
      tags$div(
        class = "cinematic-feature-indicators",
        indicators
      ),
      # İkon kutusu
      tags$div(
        class = "cinematic-card-icon-box",
        tags$div(class = paste("micro-anim", def$micro)),
        tags$i(class = paste("fas", def$icon, "cinematic-card-icon"))
      ),
      tags$h3(class = "cinematic-card-title", def$title),
      tags$p(class = "cinematic-card-short", def$short),
      tags$div(class = "cinematic-card-desc-area",
        tags$div(class = "cinematic-card-desc")
      ),
      tags$div(class = "cinematic-card-arrow",
        tags$i(class = "fas fa-chevron-right")
      )
    )
  )
}

#' Karakter seçim adımı (2. adım) - sadece Bütünleşik mod için
#' @return tags$div
.startup_character_step <- function() {
  tags$div(
    id = "cinematic-character-step",
    class = "cinematic-character-step",
    # Başlık satırı - karakter butonları sağ tarafta
    tags$div(
      class = "cinematic-char-step-header",
      tags$div(
        tags$h2(class = "cinematic-char-step-title", "Asistanınızı Seçin"),
        tags$p(class = "cinematic-char-step-subtitle", "HER ASİSTANIN FARKLI BİR ÇALIŞMA TARZI VARDIR")
      ),
      # Karakter butonları - başlık satırının sağ tarafında
      tags$div(
        class = "cinematic-char-buttons",
        id = "cinematic-char-buttons-row"
      ),
      tags$button(
        class = "cinematic-char-close-btn",
        title = "Kapat (Esc)",
        tags$i(class = "fas fa-times")
      )
    ),
    # Karakter içerik alanı (görsel + bilgi) - Kişiselleştirme sayfası ile aynı düzen
    tags$div(
      class = "cinematic-character-layout",
      # Sol: Görsel (video + statik resim)
      tags$div(
        class = "cinematic-char-visual",
        tags$div(
          class = "cinematic-char-image-wrapper",
          # Video oynatıcı (giriş ekranı karakter seçimi için)
          tags$video(
            id = "explore-char-video",
            class = "explore-char-video-player",
            autoplay = FALSE,
            playsinline = TRUE,
            muted = TRUE,
            preload = "auto",
            style = "display: none;"
          ),
          tags$img(
            id = "cinematic-char-preview-img",
            src = "characters/resim/emre/portrait.png",
            alt = "Asistan"
          )
        )
      ),
      # Sağ: Bilgi (isim ve alt başlık üst kısımda, hikaye yazma efektiyle)
      tags$div(
        class = "cinematic-char-info",
        tags$h3(class = "cinematic-char-display-name", "EMRE ONAT"),
        tags$p(class = "cinematic-char-subtitle-text", "Ana Asistan"),
        tags$div(class = "cinematic-char-lore"),
        tags$div(class = "cinematic-char-metrics"),
        tags$div(class = "cinematic-char-signatures")
      )
    ),
    # Alt butonlar
    tags$div(
      class = "cinematic-char-actions",
      tags$button(
        class = "cinematic-char-back-btn",
        tags$i(class = "fas fa-chevron-left"),
        tags$span("Geri")
      ),
      tags$button(
        class = "cinematic-char-select-btn",
        tags$span("Başlayalım"),
        tags$i(class = "fas fa-rocket")
      )
    )
  )
}

#' Sinematik mod seçim modalı
#' @return tags$div
.startup_mode_modal <- function() {
  tags$div(
    id = "mode-modal-overlay",
    class = "cinematic-modal-overlay",
    tags$div(
      class = "cinematic-modal-container",
      # Adım gösterge çubuğu (mod seçimi + karakter seçimi)
      tags$div(
        class = "cinematic-step-indicator",
        tags$div(class = "cinematic-step-dot active"),
        tags$div(class = "cinematic-step-line"),
        tags$div(class = "cinematic-step-dot")
      ),
      # Başlık ve kapatma butonu
      tags$div(
        class = "cinematic-modal-header",
        tags$div(
          tags$h2(class = "cinematic-modal-title", "Deneyim Seviyenizi Seçin"),
          tags$p(class = "cinematic-modal-subtitle", "ÇALIŞMA TARZINIZA UYGUN MODU BELİRLEYİN")
        ),
        tags$button(
          class = "cinematic-modal-close",
          title = "Kapat (Esc)",
          tags$i(class = "fas fa-times")
        )
      ),
      # Mod kartları (3 sütun) - 1. adım (veri-odaklı üretim)
      tags$div(
        class = "cinematic-cards-grid",
        lapply(.startup_mode_card_defs(), .startup_mode_card)
      ),
      # Karakter seçim adımı (2. adım) - sadece Bütünleşik mod için
      .startup_character_step()
    )
  )
}

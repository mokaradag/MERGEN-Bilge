# R/module_startup_screen.R
# Dosya Yolu: R/module_startup_screen.R
# Açıklama: Derin uzay giriş ekranı modülü. Tam ekran Three.js animasyonu,
# Keşfet butonu, mod seçim modalı ve animasyonu atlama seçeneğini yönetir.

#' Giriş Ekranı UI Oluşturma
#' @description Derin uzay giriş ekranının HTML yapısını oluşturur
#' @return HTML tagList nesnesi
createStartupScreenUI <- function() {
  tagList(
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
      tags$div(
        class = "deep-space-company-logo",
        tags$img(src = "company_logo.png", alt = "Şirket Logosu")
      ),

      # Surum bilgilendirme rozeti (sag ust kose)
      tags$div(
        class = "deep-space-version-badge",
        tags$div(class = "version-badge-dot"),
        tags$i(class = "fas fa-bell version-badge-icon"),
        tags$span(class = "version-badge-text",
          paste0("v", get_current_version(), " - Yeni!")
        )
      ),

      # Surum bilgilendirme modali
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
      ),

      # MERGEN BİLGE yazısı (sağ alt köşe)
      tags$div(
        class = "deep-space-branding",
        tags$div(
          class = "deep-space-branding-inner",
          tags$h1(class = "deep-space-title", "MERGEN"),
          tags$h2(class = "deep-space-subtitle", "BİLGE")
        )
      ),

      # Sinematik Keşfet butonu (alt orta)
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
      ),

      # Animasyonu bir daha gösterme onay kutusu (sol alt köşe)
      tags$div(
        class = "deep-space-skip-checkbox",
        tags$label(
          tags$input(type = "checkbox", id = "skip-intro-checkbox"),
          tags$span(class = "skip-checkbox-text", "Bir daha gösterme")
        )
      ),

      # Sinematik mod seçim modalı
      tags$div(
        id = "mode-modal-overlay",
        class = "cinematic-modal-overlay",
        tags$div(
          class = "cinematic-modal-container",
          # Adim gosterge cubugu (mod secimi + karakter secimi)
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
          # Mod kartları (3 sütun) - 1. adim
          tags$div(
            class = "cinematic-cards-grid",
            # Odak Modu
            tags$div(
              class = "cinematic-mode-card spotlight-card",
              `data-mode` = "odak",
              tags$div(
                class = "cinematic-card-inner",
                # İkon kutusu
                tags$div(
                  class = "cinematic-card-icon-box",
                  # Odak mikro animasyonu (dalga/ripple)
                  tags$div(class = "micro-anim micro-anim-odak"),
                  tags$i(class = "fas fa-bolt cinematic-card-icon")
                ),
                tags$h3(class = "cinematic-card-title", "Odak"),
                tags$p(class = "cinematic-card-short", "Maksimum hız, mutlak sadelik."),
                tags$div(class = "cinematic-card-desc-area",
                  tags$div(class = "cinematic-card-desc")
                ),
                tags$div(class = "cinematic-card-arrow",
                  tags$i(class = "fas fa-chevron-right")
                )
              )
            ),
            # Dinamik Modu
            tags$div(
              class = "cinematic-mode-card spotlight-card",
              `data-mode` = "denge",
              tags$div(
                class = "cinematic-card-inner",
                # Dinamik mikro animasyonu (uçuşan zerreler)
                tags$div(
                  class = "cinematic-card-icon-box",
                  tags$div(class = "micro-anim micro-anim-denge"),
                  tags$i(class = "fas fa-wand-magic-sparkles cinematic-card-icon")
                ),
                tags$h3(class = "cinematic-card-title", "Dinamik"),
                tags$p(class = "cinematic-card-short", "Akıllı asistan desteği."),
                tags$div(class = "cinematic-card-desc-area",
                  tags$div(class = "cinematic-card-desc")
                ),
                tags$div(class = "cinematic-card-arrow",
                  tags$i(class = "fas fa-chevron-right")
                )
              )
            ),
            # Bütünleşik Modu
            tags$div(
              class = "cinematic-mode-card spotlight-card",
              `data-mode` = "kesif",
              tags$div(
                class = "cinematic-card-inner",
                # Bütünleşik mikro animasyonu (lazer tarayıcı)
                tags$div(
                  class = "cinematic-card-icon-box",
                  tags$div(class = "micro-anim micro-anim-kesif"),
                  tags$i(class = "fas fa-microchip cinematic-card-icon")
                ),
                tags$h3(class = "cinematic-card-title", "Bütünleşik"),
                tags$p(class = "cinematic-card-short", "Tüm sistemlerin kilidini açın."),
                tags$div(class = "cinematic-card-desc-area",
                  tags$div(class = "cinematic-card-desc")
                ),
                tags$div(class = "cinematic-card-arrow",
                  tags$i(class = "fas fa-chevron-right")
                )
              )
            )
          ),
          # Karakter secim adimi (2. adim) - sadece Butunlesik mod icin
          tags$div(
            id = "cinematic-character-step",
            class = "cinematic-character-step",
            # Baslik
            tags$div(
              class = "cinematic-char-step-header",
              tags$h2(class = "cinematic-char-step-title", "Asistanınızı Seçin"),
              tags$p(class = "cinematic-char-step-subtitle", "HER KARAKTERİN BENZERSİZ BİR KİŞİLİĞİ VARDIR")
            ),
            # Karakter butonlari satiri
            tags$div(
              class = "cinematic-char-buttons",
              id = "cinematic-char-buttons-row"
            ),
            # Karakter icerik alani (gorsel + bilgi)
            tags$div(
              class = "cinematic-character-layout",
              # Sol: Gorsel
              tags$div(
                class = "cinematic-char-visual",
                tags$div(
                  class = "cinematic-char-image-wrapper",
                  tags$img(
                    id = "cinematic-char-preview-img",
                    src = "characters/resim/Mergen_resim_original.png",
                    alt = "Karakter"
                  ),
                  tags$div(
                    class = "cinematic-char-name-overlay",
                    tags$h3(class = "cinematic-char-display-name", "MERGEN"),
                    tags$p(class = "cinematic-char-subtitle", "Standart")
                  )
                )
              ),
              # Sag: Bilgi
              tags$div(
                class = "cinematic-char-info",
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
        )
      )
    )
  )
}

#' Giriş Ekranı Gözlemcilerini Başlat
#' @description Giriş ekranı ile ilgili server-side observer'ları kurar
#' @param input Shiny input nesnesi
#' @param session Shiny session nesnesi
#' @param settings_data Ayarlar modülünden dönen reaktif ayarlar
startupScreenObserversInit <- function(input, session, settings_data) {

  # Giriş ekranını başlat (Shiny bağlantısı kurulduğunda)
  session$onFlushed(function() {
    # localStorage'dan atlama tercihini kontrol et
    shinyjs::runjs("
      (function() {
        try {
          var raw = localStorage.getItem('mergen_settings');
          if (raw) {
            var s = JSON.parse(raw);
            if (s.skip_intro === true) {
              Shiny.setInputValue('startup_skip_intro', true, {priority: 'event'});
              return;
            }
          }
        } catch(e) {}
        Shiny.setInputValue('startup_skip_intro', false, {priority: 'event'});
      })();
    ")
  }, once = TRUE)

  # Atlama tercihine göre giriş ekranını göster veya tamamen atla
  observeEvent(input$startup_skip_intro, {
    skip <- isTRUE(input$startup_skip_intro)

    if (skip) {
      # Giriş ekranını tamamen atla - DOM'dan kaldır ve uygulamayı göster
      shinyjs::runjs("
        (function() {
          var ds = document.getElementById('deep-space-container');
          if (ds && ds.parentNode) ds.parentNode.removeChild(ds);
          document.body.classList.remove('deep-space-active');
          document.body.classList.add('app-ready');
        })();
      ")
      # Ayarlar sayfasındaki onay kutusunu da senkronize et
      updateCheckboxInput(session, "settings_yapilandirma_module-show_intro_animation", value = FALSE)
    } else {
      # Three.js sahnesini başlat
      session$sendCustomMessage("initDeepSpace", list(
        texturePath = "lib/threejs/textures/"
      ))
    }
  }, once = TRUE)

  # Giris ekrani acildiginda karakter verilerini istemciye gonder
  session$onFlushed(function() {
    chars_data <- get_characters_data()
    if (!is.null(chars_data) && !is.null(chars_data$styles)) {
      char_list <- lapply(chars_data$styles, function(ch) {
        list(
          id = ch$id,
          label = ch$label,
          display_name = ch$display_name,
          subtitle = ch$subtitle,
          image = ch$image,
          accent = ch$accent,
          accent_hover = ch$accent_hover,
          accent_active = ch$accent_active,
          lore_tr = ch$lore_tr,
          selection_card_tr = ch$selection_card_tr,
          style_tr = ch$style_tr,
          profile_metrics = ch$profile_metrics,
          signature_moves = ch$signature_moves
        )
      })
      session$sendCustomMessage("loadCinematicCharacters", list(characters = char_list))

      # Karakter butonlarini olustur (istemci tarafinda)
      buttons_js <- paste0(
        "(function() {",
        "  var row = document.getElementById('cinematic-char-buttons-row');",
        "  if (!row) return;",
        "  row.innerHTML = '';",
        "  var chars = ", jsonlite::toJSON(lapply(char_list, function(ch) {
          list(id = ch$id, label = ch$label, accent = ch$accent)
        }), auto_unbox = TRUE), ";",
        "  chars.forEach(function(ch, i) {",
        "    var btn = document.createElement('button');",
        "    btn.className = 'cinematic-char-btn' + (i === 0 ? ' active' : '');",
        "    btn.setAttribute('data-character', ch.id);",
        "    btn.textContent = ch.label;",
        "    row.appendChild(btn);",
        "  });",
        "})();"
      )
      shinyjs::runjs(buttons_js)
    }

    # Surum bilgilendirme verilerini modala gonder
    version_data <- get_version_history()
    if (!is.null(version_data)) {
      session$sendCustomMessage("initVersionModal", list(
        versions = version_data$versions,
        current_version = version_data$current_version
      ))
    }
  }, once = TRUE)

  # Mod seçimi (giriş ekranından)
  observeEvent(input$selected_experience_mode, {
    req(input$selected_experience_mode)
    mode_data <- input$selected_experience_mode

    mode <- mode_data$mode
    if (is.null(mode) || !mode %in% c("odak", "denge", "kesif")) return()

    # Mod ayarlarını uygula
    apply_experience_mode(session, settings_data, mode)

    # Ayarlar sayfasındaki mod kartlarını güncelle
    session$sendCustomMessage("updateSettingsMode", list(mode = mode))

    # Karakter secimi de geldiyse (Butunlesik mod 2. adimdan)
    char_id <- mode_data$character
    if (!is.null(char_id) && nzchar(char_id)) {
      cat(sprintf("[STARTUP] Karakter secildi (giris ekranindan): %s\n", char_id))

      # Karakter ayarlarini guncelle
      settings_data$selected_character <- char_id

      # Karakter verilerini al
      chars_data <- get_characters_data()
      char <- if (!is.null(chars_data)) {
        Find(function(x) x$id == char_id, chars_data$styles)
      } else NULL

      if (!is.null(char)) {
        # Yapilandirma sayfasindaki karakter butonlarini guncelle
        session$sendCustomMessage("updateCharacterButtons", list(
          character = char_id,
          accent = char$accent,
          accent_active = char$accent_active,
          accent_hover = char$accent_hover
        ))

        # Hosgeldin ekranindaki neural network rengini guncelle
        session$sendCustomMessage("updateNeuralColor", list(
          accent = char$accent
        ))

        # Muzik karakterini guncelle
        session$sendCustomMessage("toggleMusic", list(
          enabled = TRUE,
          character = char_id
        ))

        # localStorage'a kaydet
        shinyjs::runjs(sprintf(
          "try { var s = JSON.parse(localStorage.getItem('mergen_settings') || '{}'); s.selected_character = '%s'; localStorage.setItem('mergen_settings', JSON.stringify(s)); } catch(e) {}",
          char_id
        ))
      }
    }
  }, ignoreInit = TRUE)

  # Animasyonu atlama onay kutusu değişikliği (giriş ekranındaki checkbox)
  observeEvent(input$skip_intro_changed, {
    req(input$skip_intro_changed)
    skip <- isTRUE(input$skip_intro_changed$skip)

    # Ayarlar sayfasındaki onay kutusunu güncelle (skip = TRUE ise show = FALSE)
    updateCheckboxInput(session, "settings_yapilandirma_module-show_intro_animation", value = !skip)

    # settings_data reaktif değerini de güncelle
    if (!is.null(settings_data)) {
      settings_data$show_intro_animation <- !skip
    }
  }, ignoreInit = TRUE)

  invisible(NULL)
}

#' Deneyim Modunu Uygula
#' @description Seçilen moda göre ayarları günceller
#' @param session Shiny session nesnesi
#' @param settings_data Ayarlar reaktif değerleri
#' @param mode Seçilen mod (odak, denge, kesif)
apply_experience_mode <- function(session, settings_data, mode) {
  # Mod tanımları
  mode_settings <- list(
    odak = list(
      enable_tts_audio = FALSE,
      enable_followups = FALSE,
      enable_background_music = FALSE,
      enable_ai_expert = FALSE
    ),
    denge = list(
      enable_tts_audio = FALSE,
      enable_followups = TRUE,
      enable_background_music = TRUE,
      enable_ai_expert = FALSE
    ),
    kesif = list(
      enable_tts_audio = TRUE,
      enable_followups = TRUE,
      enable_background_music = TRUE,
      enable_ai_expert = TRUE
    )
  )

  s <- mode_settings[[mode]]
  if (is.null(s)) return()

  # Mod adını da güncelle (giriş ekranından seçildiğinde senkronizasyon için)
  settings_data$experience_mode <- mode

  # Reaktif değerleri güncelle
  settings_data$enable_tts_audio <- s$enable_tts_audio
  settings_data$enable_followups <- s$enable_followups
  settings_data$enable_background_music <- s$enable_background_music
  settings_data$enable_ai_expert <- s$enable_ai_expert

  # UI onay kutularını güncelle
  updateCheckboxInput(session, "settings_yapilandirma_module-enable_tts_audio", value = s$enable_tts_audio)
  updateCheckboxInput(session, "settings_yapilandirma_module-enable_followups", value = s$enable_followups)
  updateCheckboxInput(session, "settings_yapilandirma_module-enable_background_music", value = s$enable_background_music)
  updateCheckboxInput(session, "settings_yapilandirma_module-enable_ai_expert", value = s$enable_ai_expert)

  # Müzik durumunu güncelle (karakter bilgisiyle birlikte)
  session$sendCustomMessage("toggleMusic", list(
    enabled = s$enable_background_music,
    character = shiny::isolate(settings_data$selected_character) %||% "mergen"
  ))

  # Mod tercihini localStorage'a kaydet
  shinyjs::runjs(sprintf(
    "try { var s = JSON.parse(localStorage.getItem('mergen_settings') || '{}'); s.experience_mode = '%s'; s.enable_tts_audio = %s; s.enable_followups = %s; s.enable_background_music = %s; s.enable_ai_expert = %s; localStorage.setItem('mergen_settings', JSON.stringify(s)); } catch(e) {}",
    mode,
    tolower(as.character(s$enable_tts_audio)),
    tolower(as.character(s$enable_followups)),
    tolower(as.character(s$enable_background_music)),
    tolower(as.character(s$enable_ai_expert))
  ))
}
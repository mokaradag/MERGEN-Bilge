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

      # MERGEN BİLGE yazısı (sağ alt köşe)
      tags$div(
        class = "deep-space-branding",
        tags$div(
          class = "deep-space-branding-inner",
          tags$h1(class = "deep-space-title", "MERGEN"),
          tags$h2(class = "deep-space-subtitle", "BİLGE")
        )
      ),

      # Keşfet butonu (alt orta)
      tags$div(
        class = "deep-space-explore-btn",
        tags$button(id = "explore-btn", "KEŞFET")
      ),

      # Animasyonu bir daha gösterme onay kutusu (sol alt köşe)
      tags$div(
        class = "deep-space-skip-checkbox",
        tags$label(
          tags$input(type = "checkbox", id = "skip-intro-checkbox"),
          "Başlangıçta gösterme"
        )
      ),

      # Mod seçim modalı
      tags$div(
        id = "mode-modal-overlay",
        class = "mode-modal-overlay",
        tags$div(
          class = "mode-modal-box",
          # Kapatma butonu
          tags$button(
            class = "mode-modal-close",
            title = "Kapat (Esc)",
            tags$i(class = "fas fa-times")
          ),
          # Modal başlık
          tags$div(
            class = "mode-modal-header",
            tags$h3("Deneyim Modu"),
            tags$p("Çalışma tarzınıza uygun modu seçin")
          ),
          # Mod kartları
          tags$div(
            class = "mode-cards-container",
            # Odak Modu
            tags$div(
              class = "mode-card",
              `data-mode` = "odak",
              tags$div(class = "mode-card-icon", tags$i(class = "fas fa-bolt")),
              tags$div(class = "mode-card-title", "Odak"),
              tags$div(class = "mode-card-desc")
            ),
            # Denge Modu
            tags$div(
              class = "mode-card",
              `data-mode` = "denge",
              tags$div(class = "mode-card-icon", tags$i(class = "fas fa-compass")),
              tags$div(class = "mode-card-title", "Denge"),
              tags$div(class = "mode-card-desc")
            ),
            # Tam Donanım Modu
            tags$div(
              class = "mode-card",
              `data-mode` = "kesif",
              tags$div(class = "mode-card-icon", tags$i(class = "fas fa-rocket")),
              tags$div(class = "mode-card-title", "Tam Donanım"),
              tags$div(class = "mode-card-desc")
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

  # Atlama tercibine göre giriş ekranını göster veya atla
  observeEvent(input$startup_skip_intro, {
    skip <- isTRUE(input$startup_skip_intro)

    if (skip) {
      # Giriş ekranını atla, doğrudan uygulamaya geç
      shinyjs::runjs("
        var ds = document.getElementById('deep-space-container');
        if (ds && ds.parentNode) ds.parentNode.removeChild(ds);
        document.body.classList.remove('deep-space-active');
        document.body.classList.add('app-ready');
      ")
    } else {
      # Three.js sahnesini başlat
      session$sendCustomMessage("initDeepSpace", list(
        texturePath = "lib/threejs/textures/"
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
  }, ignoreInit = TRUE)

  # Animasyonu atlama onay kutusu değişikliği
  observeEvent(input$skip_intro_changed, {
    req(input$skip_intro_changed)
    skip <- isTRUE(input$skip_intro_changed$skip)

    # Ayarlar sayfasındaki onay kutusunu güncelle
    updateCheckboxInput(session, "settings_module-skip_intro_animation", value = skip)
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
      enable_background_music = FALSE
    ),
    denge = list(
      enable_tts_audio = FALSE,
      enable_followups = TRUE,
      enable_background_music = TRUE
    ),
    kesif = list(
      enable_tts_audio = TRUE,
      enable_followups = TRUE,
      enable_background_music = TRUE
    )
  )

  s <- mode_settings[[mode]]
  if (is.null(s)) return()

  # Reaktif değerleri güncelle
  settings_data$enable_tts_audio <- s$enable_tts_audio
  settings_data$enable_followups <- s$enable_followups
  settings_data$enable_background_music <- s$enable_background_music

  # UI onay kutularını güncelle
  updateCheckboxInput(session, "settings_module-enable_tts_audio", value = s$enable_tts_audio)
  updateCheckboxInput(session, "settings_module-enable_followups", value = s$enable_followups)
  updateCheckboxInput(session, "settings_module-enable_background_music", value = s$enable_background_music)

  # Müzik durumunu güncelle
  session$sendCustomMessage("toggleMusic", s$enable_background_music)

  # Mod tercihini localStorage'a kaydet
  shinyjs::runjs(sprintf(
    "try { var s = JSON.parse(localStorage.getItem('mergen_settings') || '{}'); s.experience_mode = '%s'; s.enable_tts_audio = %s; s.enable_followups = %s; s.enable_background_music = %s; localStorage.setItem('mergen_settings', JSON.stringify(s)); } catch(e) {}",
    mode,
    tolower(as.character(s$enable_tts_audio)),
    tolower(as.character(s$enable_followups)),
    tolower(as.character(s$enable_background_music))
  ))
}
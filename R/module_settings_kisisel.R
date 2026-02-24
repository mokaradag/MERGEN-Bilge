# R/module_settings_kisisel.R
# Dosya Yolu: R/module_settings_kisisel.R
# Açıklama: Ayarlar sayfasının "Kişiselleştirme" alt sekmesi.
#            Deneyim modu seçimi ve karakter seçimi kartlarını içerir.
#            Kullanıcı deneyimini şekillendiren ayarları bir araya getirir.

#' Kişiselleştirme Alt Sekmesi UI
#'
#' @param id Modül ad alanı kimliği
#' @return Kişiselleştirme sekmesi için UI tanımı
settingsKisiselUI <- function(id) {
  ns <- NS(id)

  tagList(
    div(
      class = "settings-container",
      # Üst başlık çubuğu (Kaydet / Sıfırla butonları)
      fluidRow(
        id = ns("settings_header"),
        column(
          width = 12,
          div(
            class = "chat-header settings-header-fixed",
            div(
              class = "chat-header-left",
              h4("Kişiselleştirme", class = "page-title")
            ),
            div(
              class = "chat-header-right",
              actionButton(ns("save_settings"), label = tagList(icon("save"), "Ayarları Kaydet"), class = "btn-modern btn-primary"),
              actionButton(ns("reset_settings"), label = tagList(icon("undo"), "Varsayılana Dön"), class = "btn-modern btn-secondary")
            )
          )
        )
      ),
      # Kaydırılabilir içerik
      div(
        class = "settings-scrollable-content",
        fluidRow(
          column(
            width = 12,
            # Deneyim Modu Seçim Kartı
            div(
              class = "settings-card settings-mode-card",
              h3("Deneyim Modu", class = "settings-title"),
              p("Çalışma tarzınıza uygun modu seçin. Mod değişiklikleri ilgili ayarları otomatik günceller.",
                class = "setting-description", style = "margin-bottom: 10px;"),
              div(
                class = "settings-mode-container",
                # Odak Modu
                div(
                  class = "mode-card selected",
                  `data-mode` = "odak",
                  div(class = "mode-card-inner",
                    div(class = "mode-card-icon", tags$i(class = "fas fa-bolt")),
                    div(class = "mode-card-title", "Odak"),
                    div(class = "mode-card-desc")
                  )
                ),
                # Dinamik Modu
                div(
                  class = "mode-card",
                  `data-mode` = "denge",
                  div(class = "mode-card-inner",
                    div(class = "mode-card-icon", tags$i(class = "fas fa-wand-magic-sparkles")),
                    div(class = "mode-card-title", "Dinamik"),
                    div(class = "mode-card-desc")
                  )
                ),
                # Bütünleşik Modu
                div(
                  class = "mode-card",
                  `data-mode` = "kesif",
                  div(class = "mode-card-inner",
                    div(class = "mode-card-icon", tags$i(class = "fas fa-microchip")),
                    div(class = "mode-card-title", "Bütünleşik"),
                    div(class = "mode-card-desc")
                  )
                )
              )
            ),
            # Karakter Seçim Kartı
            div(
              class = "settings-card character-selector-card",
              h3("Karakter", class = "settings-title"),
              div(
                class = "character-selector-buttons",
                id = ns("character_buttons")
              ),
              div(
                class = "character-display-area",
                div(
                  class = "character-image-container",
                  id = ns("character_image_area"),
                  # Video modülü UI
                  characterVideoUI(ns("character_video"))
                ),
                div(
                  class = "character-info-container",
                  id = ns("character_info_area"),
                  div(class = "character-info-placeholder", "Karakter bilgisi yükleniyor...")
                )
              )
            )
          )
        )
      )
    )
  )
}

#' Kişiselleştirme Alt Sekmesi Sunucu
#'
#' @param id Modül ad alanı kimliği
#' @param settings Merkezi ayarlar reaktif değerleri (paylaşımlı)
#' @param parent_session Üst oturum nesnesi
#' @return Koordinatörün kullanacağı reaktif değerleri içeren liste
settingsKisiselServer <- function(id, settings, parent_session = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Kaydet/Sıfırla tetikleyicileri (koordinatör tarafından dinlenir)
    save_trigger <- reactiveVal(0)
    reset_trigger <- reactiveVal(0)

    observeEvent(input$save_settings, {
      save_trigger(isolate(save_trigger()) + 1)
    }, ignoreInit = TRUE)

    observeEvent(input$reset_settings, {
      reset_trigger(isolate(reset_trigger()) + 1)
    }, ignoreInit = TRUE)

    # Geçici karakter seçimi (kaydedilene kadar uygulanmaz)
    temp_selected_character <- reactiveVal("mergen")

    # Karakter verileri
    characters_data <- reactive(get_characters_data())

    # Karakter UI başlatma (bir kez çalışır)
    observeEvent(TRUE, {
      chars <- characters_data()
      if (is.null(chars)) return()

      # Karakter butonları oluştur
      buttons_html <- lapply(chars$styles, function(char) {
        tags$button(
          class = paste0("character-btn", if(char$id == settings$selected_character) " active" else ""),
          id = paste0("char_", char$id),
          `data-character` = char$id,
          `data-accent` = char$accent,
          `data-accent-hover` = char$accent_hover,
          `data-accent-active` = char$accent_active,
          onclick = sprintf("Shiny.setInputValue('%s', '%s', {priority: 'event'})",
                           session$ns("character_clicked"), char$id),
          char$label
        )
      })

      removeUI(selector = paste0("#", session$ns("character_buttons"), " > *"), immediate = TRUE)
      insertUI(
        selector = paste0("#", session$ns("character_buttons")),
        where = "beforeEnd",
        ui = tagList(buttons_html),
        immediate = TRUE
      )

      # Varsayılan karakteri göster
      update_character_display(settings$selected_character)
    }, once = TRUE, ignoreInit = FALSE)

    # Karakter görüntüsünü güncelleme fonksiyonu
    update_character_display <- function(char_id) {
      chars <- characters_data()
      if (is.null(chars)) return()

      char <- Find(function(x) x$id == char_id, chars$styles)
      if (is.null(char)) return()

      # Buton durumlarını güncelle
      session$sendCustomMessage("updateCharacterButtons", list(
        character = char_id,
        accent = char$accent,
        accent_active = char$accent_active,
        accent_hover  = char$accent_hover
      ))

      # Karakter resim dosya isimlerini belirle
      img_filename <- switch(char_id,
         "mergen" = "Mergen_resim_original.png",
         "ulgen" = "Ulgen_resim_original.png",
         "kayra" = "Kayra_resim_original.png",
         "erlik" = "Erlik_resim_original.png",
         "umay" = "Umay_Ana_resim_original.png",
         paste0(tools::toTitleCase(char_id), "_resim_original.png")
      )

      full_img_path <- file.path("characters", "resim", img_filename)

      # Resim geçişi
      session$sendCustomMessage("transitionCharacterImage", list(
        imageUrl = full_img_path,
        displayName = char$display_name,
        containerId = session$ns("character_image_area")
      ))

      # Karakter bilgisi yazma efekti
      session$sendCustomMessage("updateCharacterInfoTyping", list(
        title = char$selection_card_tr,
        lore = char$lore_tr,
        accentColor = char$accent,
        style = char$style_tr,
        metrics = char$profile_metrics,
        signatureMoves = char$signature_moves,
        infoAreaId = session$ns("character_info_area")
      ))
    }

    # Karakter tıklama (geçici, kaydedilmez)
    observeEvent(input$character_clicked, {
      req(input$character_clicked)
      char_id <- input$character_clicked

      cat(sprintf("[SETTINGS-KISISEL] Karakter tıklandı: %s\n", char_id))

      temp_selected_character(char_id)
      update_character_display(char_id)

      Sys.sleep(0.05)

      session$sendCustomMessage("updateCharacterVideo", list(
        data = get_character_video_data(char_id),
        trigger = "click",
        timestamp = as.numeric(Sys.time())
      ))
    })

    # Deneyim modu değişikliği
    observeEvent(input$experience_mode_changed, {
      req(input$experience_mode_changed)
      mode <- input$experience_mode_changed$mode
      if (is.null(mode) || !mode %in% c("odak", "denge", "kesif")) return()

      settings$experience_mode <- mode

      # Mod ayarlarını uygula
      target_session <- parent_session %||% session
      apply_experience_mode(target_session, settings, mode)
    }, ignoreInit = TRUE)

    # Karakter video modülünü başlat
    characterVideoServer("character_video", reactive({
      char <- temp_selected_character()
      cat(sprintf("[SETTINGS-KISISEL] Video modülüne gönderilen karakter: %s\n", char))
      char
    }))

    # Koordinatöre döndürülecek değerler
    return(list(
      save_trigger = save_trigger,
      reset_trigger = reset_trigger,
      temp_selected_character = temp_selected_character,
      update_character_display = update_character_display
    ))
  })
}

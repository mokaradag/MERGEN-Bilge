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
            # Not: Hızlı Başlangıç şeridinde mod kartları gizlenir ve yerine
            # bilgilendirme notu gösterilir (html.mergen-fast-lane CSS kuralı,
            # www/css/settings_page.css). Zengin Deneyim'de kartlar normaldir.
            div(
              class = "settings-card settings-mode-card",
              h3("Deneyim Modu", class = "settings-title"),
              p("Çalışma tarzınıza uygun modu seçin. Mod değişiklikleri ilgili ayarları otomatik günceller.",
                class = "setting-description", style = "margin-bottom: 10px;"),
              div(
                class = "fast-lane-mode-note",
                tags$i(class = "fas fa-bolt", `aria-hidden` = "true"),
                tags$span(
                  paste(
                    "Hızlı Başlangıç etkin: Deneyim Modu kartları Zengin Deneyim'de",
                    "kullanılabilir. Başlangıç deneyimini Yapılandırma sayfasındaki",
                    "\"Başlangıç Deneyimi\" kartından değiştirebilirsiniz."
                  )
                )
              ),
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

    # Geçici seçimler (kaydedilene kadar uygulanmaz)
    temp_selected_character <- reactiveVal(CHARACTER_DEFAULT_ID)
    temp_experience_mode <- reactiveVal("odak")
    # Kullanıcı mod kartına tıkladı mı (aynı mod tekrar seçildiğinde uygulama için)
    mode_was_clicked <- reactiveVal(FALSE)

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

      # Varsayılan karakteri göster (DOM'a eklendikten sonra)
      # insertUI asenkron olduğu için kısa gecikme ile buton stillerini güncelle
      # onFlushed reaktif bağlam değildir, isolate() ile sarmalanmalıdır.
      secili_karakter <- isolate(settings$selected_character)
      shiny::onFlushed(function() {
        update_character_display(secili_karakter)
      }, once = TRUE, session = session)
    }, once = TRUE, ignoreInit = FALSE)

    # Karakter görüntüsünü güncelleme fonksiyonu
    # Not: Bu fonksiyon hem reaktif bağlamdan (observeEvent) hem de reaktif
    # olmayan bağlamdan (onFlushed) çağrılabilir. get_characters_data() düz
    # bir fonksiyondur (reaktif değil), bu yüzden her iki bağlamda da güvenlidir.
    update_character_display <- function(char_id, committed = TRUE) {
      # Eski kimlikler de güvenle çözülsün diye normalleştir
      char_id <- normalize_character_id(char_id)
      char <- get_character_record(char_id)
      if (is.null(char)) return()

      # Buton durumlarını güncelle.
      # committed = FALSE ise bu sadece Yapılandırma/Kişiselleştirme sayfasındaki
      # geçici önizlemedir; Ana Söyleşi neural rengi kesinlikle değiştirilmemelidir.
      session$sendCustomMessage("updateCharacterButtons", list(
        character = char_id,
        accent = char$accent,
        accent_active = char$accent_active,
        accent_hover  = char$accent_hover,
        committed = isTRUE(committed)
      ))

      # Persona görseli config'ten gelir; modül kendi dosya adı switch'ini yazmaz
      full_img_path <- char$image

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

      # Yalnızca geçici önizleme: Ana Söyleşi neural rengi değişmemeli.
      # Gerçek uygulama sadece "Ayarları Kaydet" ile yapılır.
      update_character_display(char_id, committed = FALSE)

      # Not: WebSocket mesajları sıralı iletilir; UI iş parçacığını bloklayan
      # eski Sys.sleep(0.05) beklemesi kaldırıldı.
      session$sendCustomMessage("updateCharacterVideo", list(
        data = get_character_video_data(char_id),
        trigger = "click",
        timestamp = as.numeric(Sys.time())
      ))
    })

    # Deneyim modu değişikliği - sadece geçici olarak kaydet, "Ayarları Kaydet" ile uygulanır
    observeEvent(input$experience_mode_changed, {
      req(input$experience_mode_changed)
      mode <- input$experience_mode_changed$mode
      if (is.null(mode) || !mode %in% c("odak", "denge", "kesif")) return()

      cat(sprintf("[SETTINGS-KISISEL] Mod geçici olarak seçildi: %s (kaydet ile uygulanacak)\n", mode))
      temp_experience_mode(mode)
      mode_was_clicked(TRUE)
    }, ignoreInit = TRUE)

	# Giriş ekranından mod değiştiğinde temp_experience_mode'u senkronize et
	observeEvent(settings$experience_mode, {
	  current <- temp_experience_mode()
	  if (!identical(settings$experience_mode, current)) {
		temp_experience_mode(settings$experience_mode)
		# Mod kartlarını JS tarafında da güncelle
		session$sendCustomMessage("updateSettingsMode", list(mode = settings$experience_mode))
	  }
	}, ignoreInit = TRUE)

	# Giriş ekranı veya dış akışlardan gelen karakter değişimini senkronize et
	observeEvent(settings$selected_character, {
	  # Dış akışlardan gelen kimliği yeni persona kimliğine normalleştir
	  char_id <- normalize_character_id(settings$selected_character)

	  current <- temp_selected_character()

	  if (!identical(char_id, current)) {
		cat(sprintf("[SETTINGS-KISISEL] Dış karakter senkronizasyonu: %s\n", char_id))
		temp_selected_character(char_id)
	  }

	  update_character_display(char_id)

	  session$sendCustomMessage("updateCharacterVideo", list(
		data = get_character_video_data(char_id),
		trigger = "external_sync",
		timestamp = as.numeric(Sys.time())
	  ))
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
      temp_experience_mode = temp_experience_mode,
      mode_was_clicked = mode_was_clicked,
      update_character_display = update_character_display
    ))
  })
}
# R/module_settings.R

#' Settings UI Module (Local Models Only)
#'
#' @param id A character string, the namespace ID for the module.
#'
#' @return A UI definition for the settings tab.
settingsUI <- function(id) {
  ns <- NS(id)
  
  tagList(
    div(
      class = "settings-container",
      fluidRow(
        id = ns("settings_header"),
        column(
          width = 12,
          div(
            class = "chat-header settings-header-fixed",
            div(
              class = "chat-header-left",
              h4("Ayarlar", class = "page-title")
            ),
            div(
              class = "chat-header-right",
              actionButton(ns("save_settings"), label = tagList(icon("save"), "Ayarları Kaydet"), class = "btn-modern btn-primary"),
              actionButton(ns("reset_settings"), label = tagList(icon("undo"), "Varsayılana Dön"), class = "btn-modern btn-secondary")
            )
          )
        )
      ),
      div(
        class = "settings-scrollable-content",
        fluidRow(
          column(
            width = 12,
            # Character Selection Card
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
					# Video modülü UI'ı
					characterVideoUI(ns("character_video"))
				  ),
                div(
                  class = "character-info-container",
                  id = ns("character_info_area"),
                  div(class = "character-info-placeholder", "Karakter bilgisi yükleniyor...")
                )
              )
            ),
			# Model Ayarları Kartı (4/12 + 4/12 + 4/12)
			div(
			  class = "settings-card",
			  h3("Model Ayarları", class = "settings-title"),
			  fluidRow(
				# 4/12 — Model Seçimi
				column(
				  width = 4,
				  h4("Model Seçimi", class = "setting-subtitle"),
				  p("Kullanmak istediğiniz modeli seçin.", class = "setting-description", style = "margin-top:4px;"),
				  div(
					class = "setting-item",
					style = "max-width: 250px;",
					selectInput(
					  inputId = ns("model_selection"),
					  label   = NULL,
					  choices = api_config$local_models,
					  selected = api_config$local_models[1],
					  width = "100%"
					),
					uiOutput(ns("model_description_text"))
				  )
				), # Column 1 kapanış

				# 4/12 — Yanıt Sonrası Öneriler
				column(
				  width = 4,
				  div(
					class = "setting-item followup-toggle",
					h4("Yanıt Sonrası Öneriler", class = "setting-subtitle"),
					p("Model yanıtlarının sonunda otomatik takip soruları görüntüleyin.", class = "setting-description", style = "margin-top:4px;"),
					div(
					  class = "checkbox-item followup-checkbox",
					  checkboxInput(
						inputId = ns("enable_followups"),
						label = tags$span("Takip sorusu önerilerini göster"),
						value = FALSE
					  )
					)
				  )
				), # Column 2 kapanış

				# 4/12 — API Anahtarını Güncelle
				column(
				  width = 4,
				  h4("API Anahtarını Güncelle", class = "setting-subtitle"),
				  # DÜZELTME: p() etiketi içindeki hatalı div yapısı çıkarıldı
				  p("LLM erişimi için kişisel API anahtarınızı yönetin.", class = "setting-description"),
				  div(
					class = "setting-item",
					div(
					  style = "display:flex; flex-direction:column; gap:10px; align-items:flex-start;",
					  actionButton(
						ns("update_api_key_btn"),
						label = tagList(icon("key"), "API Anahtarını Güncelle"),
						class = "btn-modern btn-warning"
					  ),
					  tags$a(
						href   = getOption(
						  "mergen.rate_limit_url",
						  Sys.getenv("SERVICE_DESK_RATE_LIMIT_URL", "https://service-desk.example.com/rate-limit")
						),
						target = "_blank",
						class  = "btn-modern btn-rate",
						tagList(icon("gauge-high"), span("Rate Limit Artışı"))
					  )
					)
				  )
				)
			  )
			),
			# Analiz Araçları Kartı
			div(
			  class = "settings-card tool-selector-card",
			  h3("Analiz Araçları", class = "settings-title"),
			  # Gizli checkbox'lar (mevcut Shiny mantığı korunuyor)
			  div(
				style = "display:none;",
				checkboxInput(ns("enable_rdata_tools"), "rData", value = FALSE),
				checkboxInput(ns("enable_mcp_tools"), "MCP Excel", value = FALSE),
				checkboxInput(ns("enable_summarization_tools"), "Özetleme", value = FALSE),
				checkboxInput(ns("enable_coding_tools"), "Kodlama", value = FALSE),
				checkboxInput(ns("enable_process_tools"), "Süreç", value = FALSE),
				checkboxInput(ns("enable_app_expert_tools"), "Uygulama", value = FALSE),
				checkboxInput(ns("enable_image_tools"), "Görsel", value = FALSE)
			  ),
			  # Buton seçici (JS tarafından doldurulur)
			  div(
				class = "tool-selector-buttons",
				id = ns("tool_buttons")
			  ),
			  # Açıklama alanı
			  div(
				class = "tool-description-area",
				p(
				  class = "tool-desc-subtext",
				  "Analiz araçları, yapay zeka modelinin harici veri kaynakları ve uzman yetenekleri ile etkileşime girmesini sağlar. Aynı anda yalnızca bir araç aktif olabilir."
				),
				p(class = "tool-desc-detail", id = ns("tool_desc_text"))
			  )
			),
            # New layout: Interface Settings (9) + Shortcuts (3)
            fluidRow(
              column(
                width = 9,
                # Interface Settings Card
                div(
                  class = "settings-card",
                  style = "min-height: 425px;",
                  h3("Arayüz Ayarları", class = "settings-title"),
                  div(
                    class = "settings-grid",
                    div(
                      class = "setting-column",
                      h4("Görünüm", class = "setting-subtitle"),
					  div(
						class = "toggle-group",
						div(class = "checkbox-item", checkboxInput(ns("enable_timestamps"), "Zaman Damgaları", value = TRUE)),
						div(class = "checkbox-item", checkboxInput(ns("enable_typing_indicator"), "Yazma Göstergesi", value = TRUE)),
						div(class = "checkbox-item", checkboxInput(ns("enable_animations"), "Animasyonlar", value = TRUE)),
						div(class = "checkbox-item", checkboxInput(ns("enable_widescreen"), "Geniş Ekran", value = TRUE)),
						div(class = "checkbox-item", checkboxInput(ns("enable_streaming"), "Akış Modu", value = TRUE))
					  )
                    ),
                    div(
                      class = "setting-column",
                      div(
                        class = "setting-item",
                        style = "max-width: 250px;",
                        selectInput(
                          inputId = ns("font_size"),
                          label = "Yazı Tipi Boyutu:",
                          choices = list("Küçük (14px)" = "small", "Orta (16px)" = "medium", "Büyük (18px)" = "large", "Çok Büyük (20px)" = "xlarge"),
                          selected = "medium",
                          width = "100%"
                        ),
                        p("Mesajların yazı tipi boyutunu ayarlayın", class = "setting-description")
                      )
                    )
                  )
                )
              ),
              column(
                width = 3,
                # Shortcuts Card
                div(
                  class = "settings-card",
                  style = "min-height: 425px;",
                  h3("Kısayollar", class = "settings-title", style = "margin-bottom: 16px;"),
                  div(
                    class = "shortcut-list",
                    div(class = "shortcut-item", tags$kbd("Enter"), " - Mesaj gönder"),
                    div(class = "shortcut-item", tags$kbd("Shift + Enter"), " - Yeni satır"),
                    div(class = "shortcut-item", tags$kbd("Ctrl + U"), " - Dosya yükle"),
                    div(class = "shortcut-item", tags$kbd("Ctrl + N"), " - Yeni sohbet"),
                    div(class = "shortcut-item", tags$kbd("Page Up/Down"), " - Sayfa kaydır")
                  )
                )
              )
            ),
			# Ses Ayarları Kartı
			div(
			  class = "settings-card",
			  h3("Ses Ayarları", class = "settings-title"),
			  fluidRow(
				# Sesli Yanıt (1/3)
				column(
				  width = 4,
				  h4("Sesli Yanıt", class = "setting-subtitle"),
				  div(
					class = "checkbox-item",
					style = "margin-top: 8px;",
					checkboxInput(
					  inputId = ns("enable_tts_audio"),
					  label = tags$span("Yanıtları Seslendir"),
					  value = FALSE
					)
				  ),
				  p("AI yanıtlarını otomatik seslendir.", class = "setting-description", style = "margin-top: 4px;")
				),
				
				# Müzik (1/3)
				column(
				  width = 4,
				  h4("Müzik", class = "setting-subtitle"),
				  div(
					class = "checkbox-item",
					style = "margin-top: 8px;",
					checkboxInput(
					  inputId = ns("enable_background_music"),
					  label = tags$span("Arka Fon Müziği"),
					  value = FALSE
					)
				  ),
				  p("Uygulama genelinde arka plan müziği çal.", class = "setting-description", style = "margin-top: 4px;")
				),
				
				# Ses Seviyesi (1/3)
				column(
				  width = 4,
				  h4("Ses Seviyesi", class = "setting-subtitle"),
				  div(
					style = "margin-top: 8px;",
					sliderInput(
					  inputId = ns("music_volume"),
					  label = NULL,
					  min = 0,
					  max = 1,
					  value = 0.3,
					  step = 0.05,
					  width = "100%"
					)
				  ),
				  p("Müzik ses seviyesi (anlık uygulanır).", class = "setting-description", style = "margin-top: 4px;")
				)
			  )
            ),
            
            # Görsel Oluşturma Ayarları Kartı
            div(
              class = "settings-card image-settings-card",
              id = ns("image_settings_card"),
              h3("Görsel Oluşturma Ayarları", class = "settings-title"),
              p("DALL-E-3 ile görsel oluşturma ayarlarını yapılandırın. Bu ayarlar yalnızca 'Görsel Uzmanı' modu aktifken geçerlidir.",
                class = "setting-description"),

              fluidRow(
                column(
                  width = 6,
                  div(
                    class = "setting-item",
                    h4("Görsel Boyutu", class = "setting-subtitle"),
                    selectInput(
                      inputId = ns("image_size"),
                      label = NULL,
                      choices = c(
                        "Kare (1024x1024)" = "1024x1024",
                        "Yatay (1792x1024)" = "1792x1024",
                        "Dikey (1024x1792)" = "1024x1792"
                      ),
                      selected = "1024x1024",
                      width = "100%"
                    )
                  )
                ),
                column(
                  width = 6,
                  div(
                    class = "setting-item",
                    h4("Görsel Kalitesi", class = "setting-subtitle"),
                    div(
                      class = "quality-switch-container",
                      tags$label(
                        class = "quality-switch",
                        tags$input(
                          type = "checkbox",
                          id = ns("image_quality_hd"),
                          class = "quality-switch-input"
                        ),
                        tags$span(class = "quality-switch-slider"),
                        tags$span(class = "quality-label-sd", "Standart"),
                        tags$span(class = "quality-label-hd", "HD")
                      )
                    )
                  )
                )
              )
            ),

            # Özetleme Ayarları Kartı
            div(
              class = "settings-card summarization-settings-card",
              id = ns("summarization_settings_card"),
              h3("Özetleme Ayarları", class = "settings-title"),
              p("Dosya özetleme modunun davranışını yapılandırın. Bu ayarlar 'Dosya Özetleme' modu aktifken geçerlidir.",
                class = "setting-description"),

              fluidRow(
                column(
                  width = 6,
                  div(
                    class = "setting-item",
                    h4("Detay Seviyesi", class = "setting-subtitle"),
                    p("Özetin ne kadar ayrıntılı olacağını belirler.", class = "setting-description", style = "margin-top:4px;"),
                    selectInput(
                      inputId = ns("summary_detail_level"),
                      label = NULL,
                      choices = c(
                        "Kısa Özet" = "brief",
                        "Standart" = "standard",
                        "Detaylı" = "detailed"
                      ),
                      selected = "standard",
                      width = "100%"
                    )
                  )
                ),
                column(
                  width = 6,
                  div(
                    class = "setting-item",
                    h4("Odak Modu", class = "setting-subtitle"),
                    p("Özetin hangi konulara ağırlık vereceğini belirler.", class = "setting-description", style = "margin-top:4px;"),
                    selectInput(
                      inputId = ns("summary_focus_mode"),
                      label = NULL,
                      choices = c(
                        "Genel" = "general",
                        "Sayısal Veri" = "numerical",
                        "Karar & Öneri" = "decisions",
                        "Karşılaştırma" = "comparison"
                      ),
                      selected = "general",
                      width = "100%"
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  )
}

#' Settings Server Module
#'
#' @param id A character string, the namespace ID for the module.
#'
#' @return A reactive list of the current settings, which the main server can use.
settingsServer <- function(id, parent_session = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
	
	# Model açıklamasını dinamik göster
    output$model_description_text <- renderUI({
      req(input$model_selection)
      descriptions <- api_config$local_model_descriptions %||% list()
      desc <- descriptions[[input$model_selection]]
      if (!is.null(desc) && nzchar(desc)) {
        tags$p(
          class = "setting-description",
          style = "margin-top: 4px; font-size: 12px; color: #999; font-style: italic;",
          desc
        )
      } else {
        NULL
      }
    })
    
    # Reactive values for settings
	settings <- reactiveValues(
	  model_selection         = api_config$local_models[1],
	  selected_character      = "mergen",
	  enable_animations       = TRUE,
	  enable_timestamps       = TRUE,
	  enable_typing_indicator = TRUE,
	  enable_streaming        = TRUE,
	  enable_widescreen       = TRUE,
	  enable_tts_audio        = FALSE,
	  enable_rdata_tools      = FALSE,
	  enable_mcp_tools        = FALSE,
	  enable_summarization_tools = FALSE,
	  enable_coding_tools = FALSE,
	  enable_process_tools = FALSE,
	  enable_app_expert_tools = FALSE,
      enable_image_tools = FALSE,
      image_size = "1024x1024",
      image_quality_hd = FALSE,
      summary_detail_level = "standard",
      summary_focus_mode = "general",
	  enable_followups        = FALSE,
	  font_size               = "medium",
	  enable_background_music = FALSE,
	  music_volume = 0.3
	)
    
    observeEvent(input$update_api_key_btn, {
      showModal(modalDialog(
        title = "API Anahtarı Güncelleme",
        easyClose = TRUE, size = "m",
        passwordInput(ns("api_key_plain_input"), label = "Yeni API Anahtarı", width = "100%"),
        footer = tagList(
          tags$button("Kapat", class = "btn-modern btn-secondary", `data-dismiss` = "modal"),
          actionButton(ns("api_key_save_btn"), "Kaydet", class = "btn-modern btn-primary")
        )
      ))
    }, ignoreInit = TRUE)

    observeEvent(input$api_key_save_btn, {
      req(input$api_key_plain_input)
      key_plain <- trimws(input$api_key_plain_input)
      if (!nzchar(key_plain)) {
        showToast(session, "Anahtar boş olamaz.", "warning"); return()
      }

      target <- determine_api_key_validation_target(isolate(settings$model_selection), api_config)
      if (!isTRUE(target$allow_user_key) || !nzchar(target$endpoint)) {
            showToast(session, "Bu model için kullanıcı tarafından yönetilen bir API anahtarı yok.", "error")
            return()
      }

      if (isTRUE(target$fallback_used)) {
            showToast(session, "Seçili model sabit anahtar kullanıyor; doğrulama birincil uç nokta ile yapılacak.", "info")
      }

      vres <- try(
            validate_api_key(
              key_plain,
              model_id = target$model_id,
              endpoint = target$endpoint,
              timeout_seconds = 6
            ),
            silent = TRUE
      )
      if (inherits(vres, "try-error") || !is.list(vres)) {
            err_msg <- tryCatch(conditionMessage(attr(vres, "condition")), error = function(e) "Bilinmeyen hata")
            showToast(session, paste("Anahtar doğrulaması başarısız:", err_msg), "error")
            return()
      }
      if (identical(vres$valid, FALSE)) {
            showToast(session, paste("API anahtarı geçersiz:", vres$message %||% ""), "error")
            return()  # kaydetme!
      }
      if (!isTRUE(vres$valid)) {
            showToast(session, paste("Anahtar doğrulanamadı (kaydedilmedi):", vres$message %||% "Doğrulama başarısız."), "error")
            return()
      }

        # 2) Kaydet + oturuma yaz (hata güvenli)
        tryCatch({
          system_username <- session$userData$system_username %||% Sys.info()[["user"]]
          save_user_api_key(system_username, key_plain)
          session$userData$ai_api_key <- key_plain
          removeModal()
          success_msg <- vres$message %||% "API anahtarı güncellendi."
          if (isTRUE(target$fallback_used)) {
            success_msg <- paste(success_msg, "Not: Doğrulama birincil uç nokta ile tamamlandı.")
          }
          if (!nzchar(success_msg)) {
            success_msg <- "API anahtarı güncellendi."
          } else if (!grepl("API anahtarı", success_msg, fixed = TRUE)) {
            success_msg <- paste("API anahtarı güncellendi —", success_msg)
          }
          showToast(session, success_msg, "success")
        }, error = function(e) {
          showToast(session, paste("API anahtarı kaydedilemedi:", conditionMessage(e)), "error")
        })
    }, ignoreInit = TRUE)
	
	# Müzik ayarları için observers
	observeEvent(input$enable_background_music, {
	  settings$enable_background_music <- input$enable_background_music
	  
	  session$sendCustomMessage("toggleMusic", input$enable_background_music)
	}, ignoreInit = TRUE)

	observeEvent(input$music_volume, {
	  settings$music_volume <- input$music_volume
	  
	  session$sendCustomMessage("setMusicVolume", input$music_volume)
	}, ignoreInit = TRUE)

    # Temporary character selection (not saved until user clicks save)
    temp_selected_character <- reactiveVal("mergen")

    # Load character data
    characters_data <- reactive(get_characters_data())
    
    # Initialize character UI (run once)
    observeEvent(TRUE, {
      chars <- characters_data()
      if (is.null(chars)) return()
      
      # Create character buttons
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
      
      # Display default character
        update_character_display(settings$selected_character)
      }, once = TRUE, ignoreInit = FALSE)
      
      # Character display update function
      update_character_display <- function(char_id) {
        chars <- characters_data()
        if (is.null(chars)) return()
        
        char <- Find(function(x) x$id == char_id, chars$styles)
        if (is.null(char)) return()
        
        # Update button states
        session$sendCustomMessage("updateCharacterButtons", list(
          character = char_id,
          accent = char$accent,
          accent_active = char$accent_active,
          accent_hover  = char$accent_hover
        ))
        
        # DÜZELTME: Karakter resim dosya isimlerini manuel olarak belirle
        # Çünkü video geçişlerinde resmin arkada görünmesi kritik
        img_filename <- switch(char_id,
           "mergen" = "Mergen_resim_original.png",
           "ulgen" = "Ulgen_resim_original.png",
           "kayra" = "Kayra_resim_original.png",
           "erlik" = "Erlik_resim_original.png",
           "umay" = "Umay_Ana_resim_original.png",
           paste0(tools::toTitleCase(char_id), "_resim_original.png") # Fallback
        )
        
        full_img_path <- file.path("characters", "resim", img_filename)

        # Smooth image transition with fade out/in
        session$sendCustomMessage("transitionCharacterImage", list(
          imageUrl = full_img_path,
          displayName = char$display_name,
          containerId = session$ns("character_image_area")
        ))
        
        # Update text info with typing effect
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
    
    # Handle character selection (temporary, not saved)
	observeEvent(input$character_clicked, {
	  req(input$character_clicked)
	  char_id <- input$character_clicked
	  
	  cat(sprintf("[SETTINGS] Karakter tıklandı: %s\n", char_id))
	  
	  temp_selected_character(char_id)
	  update_character_display(char_id)
	  
	  Sys.sleep(0.05)
	  
	  session$sendCustomMessage("updateCharacterVideo", list(
		data = get_character_video_data(char_id),
		trigger = "click",
		timestamp = as.numeric(Sys.time())
	  ))
	})
       
    # 1. Geçici Değişken: Kullanıcı Ayarlar sayfasında seçim yapınca bu değişir, sistem hemen etkilenmez.
    temp_model_selection <- reactiveVal(api_config$local_models[1])

    # 2. Ayarlar sayfasındaki dropdown değiştiğinde sadece geçici değişkeni güncelle
    observeEvent(input$model_selection, {
      temp_model_selection(input$model_selection)
    }, ignoreInit = TRUE)

    # 3. Eğer Ana Söyleşi sayfasından (Hızlı Eylem) model değiştirilirse,
    # Ayarlar sayfasındaki seçimi de güncelle ki senkronize olsunlar.
    observeEvent(settings$model_selection, {
      req(settings$model_selection)
      # Ana ayar değiştiyse, geçiciyi de eşle
      if (settings$model_selection != temp_model_selection()) {
        temp_model_selection(settings$model_selection)
        updateSelectInput(session, "model_selection", selected = settings$model_selection)
      }
    })
    
    # Load saved settings on initialization (run once)
    observeEvent(TRUE, {
      session$sendCustomMessage("loadSettings", list())
    }, once = TRUE)
    
    # Handle loaded settings from localStorage
    observeEvent(input$loaded_settings, {
      req(input$loaded_settings)
      loaded <- input$loaded_settings
      
      if (!is.null(loaded$model_selection) && loaded$model_selection %in% api_config$local_models) {
        settings$model_selection <- loaded$model_selection
        updateSelectInput(session, "model_selection", selected = loaded$model_selection)
      }
      if (!is.null(loaded$selected_character)) {
        settings$selected_character <- loaded$selected_character
        temp_selected_character(loaded$selected_character)
        update_character_display(loaded$selected_character)
      }
      if (!is.null(loaded$enable_animations)) {
        settings$enable_animations <- loaded$enable_animations
        updateCheckboxInput(session, "enable_animations", value = loaded$enable_animations)
      }
      if (!is.null(loaded$enable_timestamps)) {
        settings$enable_timestamps <- loaded$enable_timestamps
        updateCheckboxInput(session, "enable_timestamps", value = loaded$enable_timestamps)
      }
      if (!is.null(loaded$enable_typing_indicator)) {
        settings$enable_typing_indicator <- loaded$enable_typing_indicator
        updateCheckboxInput(session, "enable_typing_indicator", value = loaded$enable_typing_indicator)
      }
      if (!is.null(loaded$enable_streaming)) {
        settings$enable_streaming <- loaded$enable_streaming
        updateCheckboxInput(session, "enable_streaming", value = loaded$enable_streaming)
      }
      if (!is.null(loaded$enable_widescreen)) {
        settings$enable_widescreen <- loaded$enable_widescreen
        updateCheckboxInput(session, "enable_widescreen", value = loaded$enable_widescreen)
      }
      if (!is.null(loaded$enable_tts_audio)) {
        settings$enable_tts_audio <- isTRUE(loaded$enable_tts_audio)
        updateCheckboxInput(session, "enable_tts_audio", value = settings$enable_tts_audio)
      }
		if (!is.null(loaded$enable_background_music)) {
		  settings$enable_background_music <- loaded$enable_background_music
		  updateCheckboxInput(session, "enable_background_music", value = loaded$enable_background_music)
		}
		if (!is.null(loaded$music_volume)) {
		  settings$music_volume <- loaded$music_volume
		  updateSliderInput(session, "music_volume", value = loaded$music_volume)
		}
      if (!is.null(loaded$enable_followups)) {
        settings$enable_followups <- isTRUE(loaded$enable_followups)
        updateCheckboxInput(session, "enable_followups", value = settings$enable_followups)
      }
        if (!is.null(loaded$enable_rdata_tools)) {
          settings$enable_rdata_tools <- isTRUE(loaded$enable_rdata_tools)
          updateCheckboxInput(session, "enable_rdata_tools", value = settings$enable_rdata_tools)
        } else {
          # Eski kayıtlar için varsayılanı koru
          settings$enable_rdata_tools <- FALSE
          updateCheckboxInput(session, "enable_rdata_tools", value = FALSE)
        }
		
		if (!is.null(loaded$enable_summarization_tools)) {
		  settings$enable_summarization_tools <- isTRUE(loaded$enable_summarization_tools)
		  updateCheckboxInput(session, "enable_summarization_tools", value = settings$enable_summarization_tools)
		}
		
		if (!is.null(loaded$enable_coding_tools)) {
		  settings$enable_coding_tools <- isTRUE(loaded$enable_coding_tools)
		  updateCheckboxInput(session, "enable_coding_tools", value = settings$enable_coding_tools)
		}
		
		if (!is.null(loaded$enable_process_tools)) {
		  settings$enable_process_tools <- isTRUE(loaded$enable_process_tools)
		  updateCheckboxInput(session, "enable_process_tools", value = settings$enable_process_tools)
		}
		
		if (!is.null(loaded$enable_app_expert_tools)) {
		  settings$enable_app_expert_tools <- isTRUE(loaded$enable_app_expert_tools)
		  updateCheckboxInput(session, "enable_app_expert_tools", value = settings$enable_app_expert_tools)
		}
		
		if (!is.null(loaded$enable_image_tools)) {
		  settings$enable_image_tools <- isTRUE(loaded$enable_image_tools)
		  updateCheckboxInput(session, "enable_image_tools", value = settings$enable_image_tools)
		}
		
		# Görsel ayarlarını yükle
		if (!is.null(loaded$image_size) && loaded$image_size %in% c("1024x1024", "1792x1024", "1024x1792")) {
		  settings$image_size <- loaded$image_size
		  temp_image_size(loaded$image_size)
		  updateSelectInput(session, "image_size", selected = loaded$image_size)
		}
		if (!is.null(loaded$image_quality_hd)) {
		  settings$image_quality_hd <- isTRUE(loaded$image_quality_hd)
		  temp_image_quality_hd(isTRUE(loaded$image_quality_hd))
		  if (isTRUE(loaded$image_quality_hd)) {
		    shinyjs::runjs(sprintf("$('#%s').prop('checked', true);", ns("image_quality_hd")))
		  }
		}

        if (!is.null(loaded$enable_mcp_tools)) {
          settings$enable_mcp_tools <- isTRUE(loaded$enable_mcp_tools)
          updateCheckboxInput(session, "enable_mcp_tools", value = settings$enable_mcp_tools)
        }

		active_tools <- Filter(function(t) isTRUE(settings[[t]]), ANALYSIS_TOOLS)
		if (length(active_tools) > 1) {
		  for (tool in active_tools[-1]) {
			settings[[tool]] <- FALSE
			updateCheckboxInput(session, tool, value = FALSE)
		  }
		}

      if (!is.null(loaded$font_size)) {
        settings$font_size <- loaded$font_size
        updateSelectInput(session, "font_size", selected = loaded$font_size)
      }

      # Özetleme ayarlarını yükle
      if (!is.null(loaded$summary_detail_level) && loaded$summary_detail_level %in% c("brief", "standard", "detailed")) {
        settings$summary_detail_level <- loaded$summary_detail_level
        temp_summary_detail_level(loaded$summary_detail_level)
        updateSelectInput(session, "summary_detail_level", selected = loaded$summary_detail_level)
      }
      if (!is.null(loaded$summary_focus_mode) && loaded$summary_focus_mode %in% c("general", "numerical", "decisions", "comparison")) {
        settings$summary_focus_mode <- loaded$summary_focus_mode
        temp_summary_focus_mode(loaded$summary_focus_mode)
        updateSelectInput(session, "summary_focus_mode", selected = loaded$summary_focus_mode)
      }

      loaded_settings <- loaded
      if (!is.null(loaded_settings$enable_mcp_tools)) {
        updateCheckboxInput(session, "enable_mcp_tools", value = loaded_settings$enable_mcp_tools)
      }
    }, ignoreInit = TRUE)
	
  # Görsel ayarları için geçici değişkenler (kaydet butonuna basılana kadar uygulanmaz)
  temp_image_size <- reactiveVal("1024x1024")
  temp_image_quality_hd <- reactiveVal(FALSE)

  # Özetleme ayarları için geçici değişkenler (kaydet butonuna basılana kadar uygulanmaz)
  temp_summary_detail_level <- reactiveVal("standard")
  temp_summary_focus_mode <- reactiveVal("general")
 
  # Görsel ayarları değişiklik observer'ı - sadece geçici değişkeni güncelle
  # NOT: Ayarlar sayfasındaki değişiklikler SADECE "Ayarları Kaydet" butonuna
  # basıldığında Ana Söyleşi sayfasına yansıtılır
  observeEvent(input$image_size, {
    temp_image_size(input$image_size)
    # Hemen senkronize ETME - kaydet butonunda yapılacak
  }, ignoreInit = TRUE)
 
  observeEvent(input$image_quality_hd, {
    temp_image_quality_hd(isTRUE(input$image_quality_hd))
    # Hemen senkronize ETME - kaydet butonunda yapılacak
  }, ignoreInit = TRUE)

  # Özetleme ayarları değişiklik observer'ları - sadece geçici değişkenleri güncelle
  observeEvent(input$summary_detail_level, {
    temp_summary_detail_level(input$summary_detail_level)
  }, ignoreInit = TRUE)

  observeEvent(input$summary_focus_mode, {
    temp_summary_focus_mode(input$summary_focus_mode)
  }, ignoreInit = TRUE)
 
  # Ana Söyleşi'den gelen değişiklikleri Ayarlar sayfasına yansıt
  # (Sadece settings reaktif değerleri değişirse UI'ı güncelle)
  observeEvent(settings$image_size, {
    current_temp <- temp_image_size()
    if (!identical(settings$image_size, current_temp)) {
      temp_image_size(settings$image_size)
      updateSelectInput(session, "image_size", selected = settings$image_size)
    }
  }, ignoreInit = TRUE)
 
  observeEvent(settings$image_quality_hd, {
    current_temp <- temp_image_quality_hd()
    if (!identical(settings$image_quality_hd, current_temp)) {
      temp_image_quality_hd(settings$image_quality_hd)
      # Checkbox için JavaScript ile güncelle
      if (isTRUE(settings$image_quality_hd)) {
        shinyjs::runjs(sprintf("$('#%s').prop('checked', true);", ns("image_quality_hd")))
      } else {
        shinyjs::runjs(sprintf("$('#%s').prop('checked', false);", ns("image_quality_hd")))
      }
    }
  }, ignoreInit = TRUE)

  # Ana Söyleşi'den gelen özetleme ayarı değişikliklerini Ayarlar sayfasına yansıt
  observeEvent(settings$summary_detail_level, {
    current_temp <- temp_summary_detail_level()
    if (!identical(settings$summary_detail_level, current_temp)) {
      temp_summary_detail_level(settings$summary_detail_level)
      updateSelectInput(session, "summary_detail_level", selected = settings$summary_detail_level)
    }
  }, ignoreInit = TRUE)

  observeEvent(settings$summary_focus_mode, {
    current_temp <- temp_summary_focus_mode()
    if (!identical(settings$summary_focus_mode, current_temp)) {
      temp_summary_focus_mode(settings$summary_focus_mode)
      updateSelectInput(session, "summary_focus_mode", selected = settings$summary_focus_mode)
    }
  }, ignoreInit = TRUE)
    
    # Update internal state when inputs change
    observeEvent(input$font_size,               { settings$font_size               <- input$font_size })
    observeEvent(input$enable_animations,       { settings$enable_animations       <- input$enable_animations })
    observeEvent(input$enable_timestamps,       { settings$enable_timestamps       <- input$enable_timestamps })
    observeEvent(input$enable_typing_indicator, { settings$enable_typing_indicator <- input$enable_typing_indicator })
    observeEvent(input$enable_streaming,  { settings$enable_streaming  <- input$enable_streaming })
    observeEvent(input$enable_widescreen, { settings$enable_widescreen <- input$enable_widescreen })
    observeEvent(input$enable_tts_audio,  { settings$enable_tts_audio  <- isTRUE(input$enable_tts_audio) })
    observeEvent(input$enable_followups,  { settings$enable_followups  <- isTRUE(input$enable_followups) })

	ANALYSIS_TOOLS <- c(
	  "enable_rdata_tools",
	  "enable_mcp_tools",
	  "enable_summarization_tools",
	  "enable_coding_tools",
	  "enable_process_tools",
	  "enable_app_expert_tools",
	  "enable_image_tools"
	)
	
	lapply(ANALYSIS_TOOLS, function(tool_name) {
	  observeEvent(input[[tool_name]], {
		settings[[tool_name]] <- isTRUE(input[[tool_name]])
		
		if (isTRUE(input[[tool_name]])) {
		  other_tools <- setdiff(ANALYSIS_TOOLS, tool_name)
		  for (other in other_tools) {
			if (isTRUE(input[[other]])) {
			  updateCheckboxInput(session, other, value = FALSE)
			  settings[[other]] <- FALSE
			}
		  }
		  
		  # Görsel Uzmanı aktifleştirildiğinde otomatik model ayarla
		  if (tool_name == "enable_image_tools") {
		    image_model <- Sys.getenv("IMAGE_GEN_MODEL", "dall-e-3")
		    settings$model_selection <- image_model
		    temp_model_selection(image_model)
		    session$sendCustomMessage("toggleImageMode", list(active = TRUE))
		    session$sendCustomMessage("toggleSummaryMode", list(active = FALSE))
		  }

		  # Dosya Özetleme aktifleştirildiğinde kontrolleri göster
		  if (tool_name == "enable_summarization_tools") {
		    session$sendCustomMessage("toggleSummaryMode", list(active = TRUE))
		    session$sendCustomMessage("toggleImageMode", list(active = FALSE))
		  }
		} else {
		  # Görsel Uzmanı devre dışı bırakıldığında varsayılan modele dön
		  if (tool_name == "enable_image_tools") {
		    default_model <- api_config$local_models[1]
		    settings$model_selection <- default_model
		    temp_model_selection(default_model)
		    updateSelectInput(session, "model_selection", selected = default_model)
		    session$sendCustomMessage("saveSettings", list(model_selection = default_model))
		    session$sendCustomMessage("toggleImageMode", list(active = FALSE))
		  }

		  # Dosya Özetleme devre dışı bırakıldığında kontrolleri gizle
		  if (tool_name == "enable_summarization_tools") {
		    session$sendCustomMessage("toggleSummaryMode", list(active = FALSE))
		  }
		}
	  }, ignoreInit = TRUE)
	})
    
    # Save settings button
	observeEvent(input$save_settings, {
      # Karakteri kaydet
      settings$selected_character <- temp_selected_character()
      
      settings$model_selection <- temp_model_selection()
 
      # Görsel ayarlarını geçici değişkenlerden uygula ve senkronize et
      settings$image_size <- temp_image_size()
      settings$image_quality_hd <- temp_image_quality_hd()

      # Özetleme ayarlarını geçici değişkenlerden uygula ve senkronize et
      settings$summary_detail_level <- temp_summary_detail_level()
      settings$summary_focus_mode <- temp_summary_focus_mode()

      cat(sprintf("[SETTINGS] Ayarlar kaydediliyor. Model: %s, Karakter: %s, Görsel Boyutu: %s, HD: %s, Özet Detay: %s, Özet Odak: %s\n",
                  settings$model_selection, settings$selected_character,
                  settings$image_size, settings$image_quality_hd,
                  settings$summary_detail_level, settings$summary_focus_mode))
 
      Sys.sleep(0.1)
 
	  session$sendCustomMessage("triggerVideoSelection", list(
		character = settings$selected_character,
		timestamp = as.numeric(Sys.time())
	  ))
 
	  # Görsel ayarlarını Ana Söyleşi sayfasına senkronize et
	  session$sendCustomMessage("syncImageSettingsToChat", list(
	    size = settings$image_size,
	    quality_hd = isTRUE(settings$image_quality_hd)
	  ))

	  # Özetleme ayarlarını Ana Söyleşi sayfasına senkronize et
	  session$sendCustomMessage("syncSummarySettingsToChat", list(
	    detail_level = settings$summary_detail_level,
	    focus_mode = settings$summary_focus_mode
	  ))

	  to_save <- reactiveValuesToList(settings)
	  to_save$enable_rdata_tools <- isTRUE(input$enable_rdata_tools)
      to_save$enable_mcp_tools   <- isTRUE(input$enable_mcp_tools)
      to_save$enable_tts_audio   <- isTRUE(input$enable_tts_audio)
      to_save$image_size             <- settings$image_size
      to_save$image_quality_hd       <- settings$image_quality_hd
      to_save$summary_detail_level   <- settings$summary_detail_level
      to_save$summary_focus_mode     <- settings$summary_focus_mode
      session$sendCustomMessage("saveSettings", to_save)
      
      showToast(session, "Ayarlar kaydedildi!", "success")
    })
    
	# Reset settings button
	observeEvent(input$reset_settings, {
	  default_model <- api_config$local_models[1]
	  
	  settings$model_selection          <- default_model
	  # Geçici değişkeni de sıfırla
	  temp_model_selection(default_model)
 
	  settings$selected_character       <- "mergen"
	  temp_selected_character("mergen")
	  settings$enable_animations       <- TRUE
	  settings$enable_timestamps       <- TRUE
	  settings$enable_typing_indicator <- TRUE
	  settings$enable_streaming        <- TRUE
	  settings$enable_widescreen       <- TRUE
	  settings$enable_tts_audio        <- TRUE
	  settings$enable_rdata_tools      <- FALSE
	  settings$enable_mcp_tools        <- FALSE
	  settings$enable_summarization_tools <- FALSE
	  settings$enable_coding_tools <- FALSE
	  settings$enable_process_tools <- FALSE
	  settings$enable_app_expert_tools <- FALSE
	  settings$enable_image_tools <- FALSE
	  settings$enable_followups        <- TRUE
	  settings$font_size               <- "medium"
	  settings$enable_background_music <- FALSE
	  settings$music_volume <- 0.3
 
	  # Görsel ayarlarını sıfırla
	  settings$image_size <- "1024x1024"
	  settings$image_quality_hd <- FALSE
	  temp_image_size("1024x1024")
	  temp_image_quality_hd(FALSE)

	  # Özetleme ayarlarını sıfırla
	  settings$summary_detail_level <- "standard"
	  settings$summary_focus_mode <- "general"
	  temp_summary_detail_level("standard")
	  temp_summary_focus_mode("general")
	  
	  updateSelectInput(session, "model_selection", selected = settings$model_selection)
	  update_character_display(settings$selected_character)
	  updateSelectInput(session, "font_size", selected = settings$font_size)
	  updateCheckboxInput(session, "enable_animations",       value = settings$enable_animations)
	  updateCheckboxInput(session, "enable_timestamps",       value = settings$enable_timestamps)
	  updateCheckboxInput(session, "enable_typing_indicator", value = settings$enable_typing_indicator)
	  updateCheckboxInput(session, "enable_streaming",        value = settings$enable_streaming)
	  updateCheckboxInput(session, "enable_widescreen",       value = settings$enable_widescreen)
	  updateCheckboxInput(session, "enable_tts_audio",        value = settings$enable_tts_audio)
	  updateCheckboxInput(session, "enable_rdata_tools",      value = settings$enable_rdata_tools)
	  updateCheckboxInput(session, "enable_mcp_tools",        value = settings$enable_mcp_tools)
	  updateCheckboxInput(session, "enable_summarization_tools", value = FALSE)
	  updateCheckboxInput(session, "enable_coding_tools", value = FALSE)
	  updateCheckboxInput(session, "enable_followups",        value = settings$enable_followups)
	  updateCheckboxInput(session, "enable_background_music", value = FALSE)
	  updateSliderInput(session, "music_volume", value = 0.3)
	  
	  # Görsel ayarları UI'ını güncelle
	  updateSelectInput(session, "image_size", selected = "1024x1024")
	  shinyjs::runjs(sprintf("$('#%s').prop('checked', false);", ns("image_quality_hd")))
 
	  # Ana Söyleşi'deki görsel kontrollerini de sıfırla
	  session$sendCustomMessage("syncImageSettingsToChat", list(
	    size = "1024x1024",
	    quality_hd = FALSE
	  ))

	  # Özetleme ayarları UI'ını güncelle
	  updateSelectInput(session, "summary_detail_level", selected = "standard")
	  updateSelectInput(session, "summary_focus_mode", selected = "general")

	  # Ana Söyleşi'deki özetleme kontrollerini de sıfırla
	  session$sendCustomMessage("syncSummarySettingsToChat", list(
	    detail_level = "standard",
	    focus_mode = "general"
	  ))

	  session$sendCustomMessage("clearSettings", list())
	  showToast(session, "Ayarlar sıfırlandı!", "info")
	})
    
    # Karakter video modülünü başlat
	characterVideoServer("character_video", reactive({
	  char <- temp_selected_character()
	  cat(sprintf("[SETTINGS] Video modülüne gönderilen karakter: %s\n", char))
	  char
	}))
	  
	return(settings)
  })
}
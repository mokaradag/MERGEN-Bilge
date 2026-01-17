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
			# Model Settings Card (3/12 + 1/12 + 4/12 + 1/12 + 3/12)
			div(
			  class = "settings-card",
			  h3("Model Ayarları", class = "settings-title"),
			  fluidRow(
				# 1) 3/12 — Model Seçimi
				column(
				  width = 3,
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
                    # Model açıklaması alt yazı olarak
                    uiOutput(ns("model_description_text"))
                  ),
				  div(
					class = "setting-item followup-toggle",
					h4("Yanıt Sonrası Öneriler", class = "setting-subtitle"),
					p(
					  "Model yanıtlarının sonunda otomatik takip soruları görüntüleyin.",
					  class = "setting-description",
					  style = "margin-top:4px;"
					),
					div(
					  class = "checkbox-item followup-checkbox",
					  checkboxInput(
						inputId = ns("enable_followups"),
						label = tags$span("Takip sorusu önerilerini göster"),
						value = TRUE
					  )
					)
				  )
				),

				# 1/12 — Spacer
				column(width = 1, HTML("&nbsp;")),

				# 4/12 — Analiz Araçları
				column(
				  width = 4,
				  h4("Analiz Araçları", class = "setting-subtitle"),
				  p(
					"Analiz modunu seçin: rData (kurumsal veri gölü) veya MCP: Excel (yüklenen dosya). ",
					"Aynı anda yalnızca biri aktif olabilir; isterseniz ikisini de kapatabilirsiniz.",
					class = "setting-description", style = "margin-top:4px;"
				  ),
				  div(
					class = "setting-item",
					# Yeni: rData odaklı analiz seçeneği (varsayılan açık)
					div(
					  class = "checkbox-item",
					  checkboxInput(
						inputId = ns("enable_rdata_tools"),
						label = tags$span("Proje ve Kaynak Analizi", style = "white-space: nowrap;"),
						value = FALSE
					  )
					),
					# Mevcut: MCP Excel analizi
					div(
					  class = "checkbox-item",
					  checkboxInput(
						inputId = ns("enable_mcp_tools"),
						label = tags$span("Model Context Protocol (MCP): Excel", style = "white-space: nowrap;"),
						value = FALSE
					  )
					),
					# YENİ: Dosya Özetleme modu
					div(
					  class = "checkbox-item",
					  checkboxInput(
						inputId = ns("enable_summarization_tools"),
						label = tags$span("Dosya Özetleme", style = "white-space: nowrap;"),
						value = FALSE
					  )
					)
				  )
				),

				# 1/12 — Spacer
				column(width = 1, HTML("&nbsp;")),

				# 3/12 — API Anahtarını Güncelle
				column(
				  width = 3,
				  h4("API Anahtarını Güncelle", class = "setting-subtitle"),
				  p("LLM erişimi için kişisel API anahtarınızı yönetin.", class = "setting-description", style = "margin-top:4px;"),
				  div(
					class = "setting-item",
					div(
					  style = "display:flex; flex-direction:column; gap:10px; align-items:flex-start;",
					  # Güncelle (modal açar)
					  actionButton(
						ns("update_api_key_btn"),
						label = tagList(icon("key"), "API Anahtarını Güncelle"),
						class = "btn-modern btn-warning"
					  ),
					  # Rate limit artışı — aynı stil, farklı koyu renk
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
					  value = TRUE
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
	  enable_tts_audio        = TRUE,
	  enable_rdata_tools      = FALSE,
	  enable_mcp_tools        = FALSE,
	  enable_summarization_tools = FALSE,
	  enable_followups        = TRUE,
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
          showToast(session, success_m  sg, "success")
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

        if (!is.null(loaded$enable_mcp_tools)) {
          settings$enable_mcp_tools <- isTRUE(loaded$enable_mcp_tools)
          updateCheckboxInput(session, "enable_mcp_tools", value = settings$enable_mcp_tools)
        }

        # Karşılıklı dışlama: ikisi aynı anda açık ise MCP'yi kapat
        if (isTRUE(settings$enable_rdata_tools) && isTRUE(settings$enable_mcp_tools)) {
          settings$enable_mcp_tools <- FALSE
          updateCheckboxInput(session, "enable_mcp_tools", value = FALSE)
        }
      if (!is.null(loaded$font_size)) {
        settings$font_size <- loaded$font_size
        updateSelectInput(session, "font_size", selected = loaded$font_size)
      }
      
      loaded_settings <- loaded
      if (!is.null(loaded_settings$enable_mcp_tools)) {
        updateCheckboxInput(session, "enable_mcp_tools", value = loaded_settings$enable_mcp_tools)
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

	# Karşılıklı dışlama mantığı - 3 checkbox için
	observeEvent(input$enable_rdata_tools, {
	  settings$enable_rdata_tools <- isTRUE(input$enable_rdata_tools)
	  # Eğer rData açıldıysa diğerlerini kapat
	  if (isTRUE(input$enable_rdata_tools)) {
		if (isTRUE(input$enable_mcp_tools)) {
		  updateCheckboxInput(session, "enable_mcp_tools", value = FALSE)
		  settings$enable_mcp_tools <- FALSE
		}
		if (isTRUE(input$enable_summarization_tools)) {
		  updateCheckboxInput(session, "enable_summarization_tools", value = FALSE)
		  settings$enable_summarization_tools <- FALSE
		}
	  }
	}, ignoreInit = TRUE)

	observeEvent(input$enable_mcp_tools, {
	  settings$enable_mcp_tools <- isTRUE(input$enable_mcp_tools)
	  # Eğer MCP açıldıysa diğerlerini kapat
	  if (isTRUE(input$enable_mcp_tools)) {
		if (isTRUE(input$enable_rdata_tools)) {
		  updateCheckboxInput(session, "enable_rdata_tools", value = FALSE)
		  settings$enable_rdata_tools <- FALSE
		}
		if (isTRUE(input$enable_summarization_tools)) {
		  updateCheckboxInput(session, "enable_summarization_tools", value = FALSE)
		  settings$enable_summarization_tools <- FALSE
		}
	  }
	}, ignoreInit = TRUE)

	# YENİ: Dosya Özetleme için karşılıklı dışlama
	observeEvent(input$enable_summarization_tools, {
	  settings$enable_summarization_tools <- isTRUE(input$enable_summarization_tools)
	  # Eğer Özetleme açıldıysa diğerlerini kapat
	  if (isTRUE(input$enable_summarization_tools)) {
		if (isTRUE(input$enable_rdata_tools)) {
		  updateCheckboxInput(session, "enable_rdata_tools", value = FALSE)
		  settings$enable_rdata_tools <- FALSE
		}
		if (isTRUE(input$enable_mcp_tools)) {
		  updateCheckboxInput(session, "enable_mcp_tools", value = FALSE)
		  settings$enable_mcp_tools <- FALSE
		}
	  }
	}, ignoreInit = TRUE)
    
    # Save settings button
	observeEvent(input$save_settings, {
      # Karakteri kaydet
      settings$selected_character <- temp_selected_character()
      
      settings$model_selection <- temp_model_selection()
      
      cat(sprintf("[SETTINGS] Ayarlar kaydediliyor. Model: %s, Karakter: %s\n", 
                  settings$model_selection, settings$selected_character))
      
      Sys.sleep(0.1)
	  
	  session$sendCustomMessage("triggerVideoSelection", list(
		character = settings$selected_character,
		timestamp = as.numeric(Sys.time())
	  ))
	  
	  to_save <- reactiveValuesToList(settings)
	  to_save$enable_rdata_tools <- isTRUE(input$enable_rdata_tools)
      to_save$enable_mcp_tools   <- isTRUE(input$enable_mcp_tools)
      to_save$enable_tts_audio   <- isTRUE(input$enable_tts_audio)
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
	  settings$enable_summarization_tools <- FALSE # YENİ
	  settings$enable_followups        <- TRUE
	  settings$font_size               <- "medium"
	  settings$enable_background_music <- FALSE
	  settings$music_volume <- 0.3
	  
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
	  updateCheckboxInput(session, "enable_summarization_tools", value = FALSE) # YENİ
	  updateCheckboxInput(session, "enable_followups",        value = settings$enable_followups)
	  updateCheckboxInput(session, "enable_background_music", value = FALSE)
	  updateSliderInput(session, "music_volume", value = 0.3)
	  
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
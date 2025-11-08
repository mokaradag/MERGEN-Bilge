# R/module_settings.R

#' Settings UI Module (Local Models Only)
#'
#' @param id A character string, the namespace ID for the module.
#'
#' @return A UI definition for the settings tab.
settingsUI <- function(id) {
  ns <- NS(id)
  
  tagList(
    tags$head(
      tags$style(HTML("
        /* Character selector styles */
        .character-selector-card {
          background: var(--background-light);
          border: 1px solid var(--border-color);
          border-radius: 12px;
          padding: 24px;
          margin-bottom: 24px;
        }
        
        .character-selector-buttons {
          display: flex;
          gap: 8px;
          margin-bottom: 24px;
          background: var(--background-dark);
          padding: 6px;
          border-radius: 10px;
        }
        
        .character-btn {
          flex: 1;
          padding: 12px 16px;
          border: none;
          border-radius: 6px;
          background: transparent;
          color: var(--text-secondary);
          font-size: 14px;
          font-weight: 600;
          cursor: pointer;
          transition: all 0.3s ease;
          position: relative;
        }
        
        .character-btn:hover {
          color: var(--text-primary);
        }
        
        .character-btn.active {
          color: white !important;
        }
        
        .character-display-area {
          display: grid;
          grid-template-columns: 3fr 9fr;
          gap: 24px;
          min-height: 280px;
        }
        
        .character-image-container {
          display: flex;
          align-items: center;
          justify-content: center;
          background: var(--background-dark);
          border-radius: 12px;
          padding: 16px;
          overflow: hidden;
          position: relative;
        }
        
        .character-image {
          max-width: 100%;
          max-height: 100%;
          object-fit: contain;
          opacity: 0;
          animation: fadeInImage 0.8s ease forwards;
        }
        
        @keyframes fadeInImage {
          to { opacity: 1; }
        }
        
        .character-info-container {
          display: flex;
          flex-direction: column;
          justify-content: center;
          background: #000000;
          border-radius: 12px;
          padding: 24px;
        }
        
        .character-title {
          font-size: 18px;
          font-weight: 700;
          margin-bottom: 16px;
          opacity: 0;
          animation: fadeIn 0.6s ease 0.2s forwards;
        }
        
        .character-lore {
          font-size: 15px;
          line-height: 1.7;
          color: var(--text-secondary);
          opacity: 0;
          animation: typingFade 1s ease 0.5s forwards;
        }
        
        @keyframes fadeIn {
          to { opacity: 1; }
        }
        
        @keyframes typingFade {
          to { opacity: 1; }
        }
		
		/* ----- Modal close button shape harmonization ----- */
		.modal-footer .btn-default,
		.modal-footer .btn-secondary,
		.modal-footer button,
		.modal-footer .modalButton {
		  border-radius: 9999px !important;   /* pill shape */
		  padding: 8px 14px !important;
		}

		/* Make anchor buttons look like .btn-modern as well */
		a.btn-modern {
		  display: inline-flex;
		  align-items: center;
		  gap: 8px;
		  text-decoration: none !important;
		}
		
		/* Dark-friendly accent for Rate Limit Artışı */
		.btn-modern.btn-rate {
		  background: #334155;          /* slate-700 */
		  border: 1px solid #475569;     /* slate-600 */
		  color: #e5e7eb;                /* slate-200 */
		}
		.btn-modern.btn-rate:hover {
		  background: #1f2937;           /* gray-800 */
		  border-color: #64748b;         /* slate-500 */
		  color: #ffffff;
		}
      "))
    ),
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
                div(class = "character-image-container", id = ns("character_image_area")),
                div(
                  class = "character-info-container",
                  id = ns("character_info_area"),
                  uiOutput(ns("character_info_display"))
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
					selectInput(
					  inputId = ns("model_selection"),
					  label   = NULL,
					  choices = api_config$local_models,
					  selected = api_config$local_models[1],
					  width = "100%"
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
						value = TRUE
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
    
    # Reactive values for settings
	settings <- reactiveValues(
	  model_selection         = api_config$local_models[1],
	  selected_character      = "mergen",
	  enable_animations       = TRUE,
	  enable_timestamps       = TRUE,
	  enable_typing_indicator = TRUE,
	  enable_streaming        = TRUE,
	  enable_widescreen       = TRUE,
	  enable_rdata_tools      = TRUE,
	  enable_mcp_tools        = FALSE,
	  font_size               = "medium"
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

	  # 1) Doğrula (seçili modeli kullanarak; yoksa ilkini)
	  model_id <- isolate(settings$model_selection) %||% as.character(api_config$local_models[1])
	  if (!nzchar(model_id)) model_id <- as.character(api_config$local_models[1])
	  model_id <- as.character(model_id)
	  api_url  <- resolve_local_llm_endpoint(model_id)

	  vres <- try(validate_api_key(key_plain, model_id = model_id, endpoint = api_url, timeout_seconds = 6), silent = TRUE)
	  if (!inherits(vres, "try-error") && is.list(vres)) {
		if (identical(vres$valid, FALSE)) {
		  showToast(session, paste("API anahtarı geçersiz:", vres$message %||% ""), "error")
		  return()  # kaydetme!
		}
		if (isTRUE(vres$valid)) {
		  # Başarılı doğrulamada ayrı bir toast göstermiyoruz; kaydetme başarılı olursa tek bir toast çıkacak.
		} else {
		  showToast(session, paste("Anahtar doğrulanamadı:", vres$message %||% "Bilinmiyor"), "warning")
		  # doğrulanamadı ama yine de kaydetmeye izin veriyoruz
		}
	  }

		# 2) Kaydet + oturuma yaz (hata güvenli)
		tryCatch({
		  save_user_api_key(session$userData$system_username, key_plain)
		  session$userData$ai_api_key <- key_plain
		  removeModal()
		  showToast(session, "API anahtarı güncellendi.", "success")
		}, error = function(e) {
		  showToast(session, paste("API anahtarı kaydedilemedi:", conditionMessage(e)), "error")
		})
	}, ignoreInit = TRUE)

    # Temporary character selection (not saved until user clicks save)
    temp_selected_character <- reactiveVal("mergen")

    # Load character data
    characters_data <- reactive({
      list(
        title = "Yanıt Stili — Karakter Seçimi",
        default_style = "mergen",
        styles = list(
          list(
            id = "mergen",
            label = "Mergen",
            display_name = "MERGEN",
            subtitle = "Standart",
            avatar = "characters/avatar/Mergen_avatar_original.png",
            image = "characters/resim/Mergen_resim_original.png",
            accent = "#7C4DFF",
            accent_hover = "#8E66FF",
            accent_active = "#6A3BE6",
            selection_card_tr = "\"Zihin Yayından Çıkan Ok\" — hızlı, net, uygulanabilir",
            lore_tr = "Mergen, Türk ve Altay anlatılarında bilgeliğin ve keskin zekânın sembolüdür. Bazı kaynaklarda Kayra'nın oğlu olarak geçer. Oku ve yayı, isabetli düşünceyi ve doğru soruyu bulmayı temsil eder. Gök katlarının sessizliğinde düşünür, karmaşığı özüne indirir. Şaman inançlarında 'akıl veren' olarak bilinir; günümüz yorumunda ise veriyi süzer, gürültüyü susturur. Mergen'i seçtiğinizde fazla söze gerek kalmaz: hedef, nişan ve net sonuç.",
            style_tr = "Önce kısa özet, ardından adım adım plan ve küçük örnek",
            system_prompt_en = "Be a balanced, pragmatic assistant. First provide a 2–3 sentence executive summary, then a concise step-by-step plan, then a minimal example/output. Avoid rhetoric and hedging. Use precise, actionable language. Ask for missing constraints only if they block progress.",
            parameters = list(temperature = 0.4)
          ),
          list(
            id = "ulgen",
            label = "Ülgen",
            display_name = "ÜLGEN",
            subtitle = "Yapıcı Uzman",
            avatar = "characters/avatar/Ulgen_avatar_original.png",
            image = "characters/resim/Ulgen_resim_original.png",
            accent = "#2F6DF6",
            accent_hover = "#4C80F7",
            accent_active = "#1E59E0",
            selection_card_tr = "\"Göğün Işığı\" — moral yükseltir, yolu aydınlatır",
            lore_tr = "Ülgen, göğün aydınlık yüzüdür; iyilik, düzen ve üretkenliğin tanrısı olarak tanınır. Üst gök katlarında yaşadığına inanılır; insanlara ateşi, zanaatı ve doğru yolu öğreten bir rehberdir. Kozmik dengede karşıtı Erlik olsa da amacı çatışma değil, düzen kurmaktır. Eski törenlerde beyaz renklerle anılır; umut ve yeniden başlama duygusunu simgeler. Ülgen'i seçtiğinizde sis dağılır, seçenekler berraklaşır ve eylem planı ortaya çıkar.",
            style_tr = "Sorunu çerçevele; çözüm seçenekleri + artı/eksi; gerekçeli öneri; eylem listesi",
            system_prompt_en = "Act like a constructive expert: quickly frame the problem; propose 2–3 viable solution paths with trade-offs; recommend one path with rationale; end with a checklist of next actions and acceptance criteria. Keep the tone positive and professional.",
            parameters = list(temperature = 0.5)
          ),
          list(
            id = "kayra",
            label = "Kayra",
            display_name = "KAYRA",
            subtitle = "Stratejist",
            avatar = "characters/avatar/Kayra_avatar_original.png",
            image = "characters/resim/Kayra_resim_original.png",
            accent = "#12A97B",
            accent_hover = "#26B790",
            accent_active = "#0C8C63",
            selection_card_tr = "\"Evrenin Haritacısı\" — büyük resmi kurar, yolu fazlara böler",
            lore_tr = "Kayra Han, bazı Sibirya ve Türk anlatılarında yaratıcı ve en yüce ilke olarak yer alır; kaosu ayırıp göğü, yeri ve suları düzene sokan güç olarak bilinir. Bazı varyantlarda Ülgen ve Erlik'in babası kabul edilir; kararları denge ve ilkelere dayanır. Onun sesi acele etmez; uzun vadeli görüş, sağlam kilometre taşları ve sorumluluk paylaşımı ister. Kayra'yı seçtiğinizde vizyon haritaya, harita da uygulanabilir bir yol planına dönüşür.",
            style_tr = "Amaçlar ve ilkeler → seçenekler/trade-off → karar matrisi → fazlı roadmap",
            system_prompt_en = "Operate as a strategist: state objectives and guiding principles; map alternatives with trade-offs; provide a decision matrix; outline a phased roadmap with milestones, owners, and risks; include governance/policy notes when relevant.",
            parameters = list(temperature = 0.3, long_form = TRUE)
          ),
          list(
            id = "erlik",
            label = "Erlik",
            display_name = "ERLİK",
            subtitle = "Eleştirel Eş",
            avatar = "characters/avatar/Erlik_avatar_original.png",
            image = "characters/resim/Erlik_resim_original.png",
            accent = "#B66A2C",
            accent_hover = "#C27A3D",
            accent_active = "#8F5321",
            selection_card_tr = "\"Varsayım Avcısı\" — kör noktayı görür, nazikçe dürtükler",
            lore_tr = "Erlik Han, yeraltı âleminin hükümdarı olarak tanınır; kozmik dengede eksikleri, kusurları ve sınavları görünür kılan karşıt güçtür. Amacı korkutmak değil, yanlışı düzeltmek için perdeyi aralamaktır; demir ve toprakla özdeşleşir. Anlatılarda hastalık ve kıtlık gibi riskleri hatırlatır; böylece tedbiri doğurur. Erlik'i seçtiğinizde keskin sorular gelir: 'Neye dayanıyor? Ne ters gidebilir?' ve planın zayıf halkaları güçlenir.",
            style_tr = "Varsayımlar → riskler & karşı örnekler → nazik sorgu → risk azaltma → kontrol listesi",
            system_prompt_en = "Be a respectful critical partner. Surface hidden assumptions; list risks and counterexamples; ask sharp but polite why/how questions; propose risk-mitigating alternatives; conclude with a concise pre-flight checklist. Keep language diplomatic, not scary.",
            parameters = list(temperature = 0.4)
          ),
          list(
            id = "umay",
            label = "Umay Ana",
            display_name = "UMAY ANA",
            subtitle = "Rehber",
            avatar = "characters/avatar/Umay_Ana_avatar_original.png",
            image = "characters/resim/Umay_Ana_resim_original.png",
            accent = "#E98686",
            accent_hover = "#EE9B9B",
            accent_active = "#D96F6F",
            selection_card_tr = "\"Nazik Öğretici\" — yeni başlayanların korkusunu alır",
            lore_tr = "Umay Ana, Türk dünyasında bereketin ve çocukların koruyucu ruhu olarak sevilir; turna kuşuyla, sıcaklık ve şefkatle anılır. Halk inançlarında annenin ve yuvanın hamisi kabul edilir; adı eski metinlerde de yaşar. Karmaşayı küçük lokmalara böler; telaşı sakinliğe, belirsizliği güvene çevirir. Umay'ı seçtiğinizde dil yumuşar; adımlar küçülür, ipuçları belirir ve yeni başlayanlar için kapı aralanır.",
            style_tr = "Basit dil; küçük numaralı adımlar; sık hata/ipuçları; kısa güvenlik notu; mini örnek",
            system_prompt_en = "Be an empathetic teacher for beginners. Explain in simple language; break tasks into small numbered steps; include common pitfalls and tips; add a short safety/ethics note if relevant; provide a minimal working example.",
            parameters = list(temperature = 0.6)
          )
        )
      )
    })
    
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
          accent_active = char$accent_active
        ))
        
        # Smooth image transition with fade out/in
        session$sendCustomMessage("transitionCharacterImage", list(
          imageUrl = char$image,
          displayName = char$display_name,
          containerId = session$ns("character_image_area")
        ))
        
        # Update text info with typing effect
        session$sendCustomMessage("updateCharacterInfoTyping", list(
          title = char$selection_card_tr,
          lore = char$lore_tr,
          accentColor = char$accent,
          infoAreaId = session$ns("character_info_area")
        ))
      }

    # Render character info
    output$character_info_display <- renderUI({
      char_id <- temp_selected_character()
      chars <- characters_data()
      if (is.null(chars)) return(NULL)
      
      char <- Find(function(x) x$id == char_id, chars$styles)
      if (is.null(char)) return(NULL)
      
      tagList(
        div(class = "character-title character-title-animate", 
            style = paste0("color: ", char$accent), 
            char$selection_card_tr),
        div(class = "character-lore character-lore-animate", 
            char$lore_tr)
      )
    })
    
    # Handle character selection (temporary, not saved)
    observeEvent(input$character_clicked, {
      req(input$character_clicked)
      temp_selected_character(input$character_clicked)
      update_character_display(input$character_clicked)
    })
    
    # IMPORTANT: Add observer for external model changes
    observe({
      if (!is.null(input$model_selection)) {
        if (input$model_selection != settings$model_selection) {
          settings$model_selection <- input$model_selection
        }
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
		if (!is.null(loaded$enable_rdata_tools)) {
		  settings$enable_rdata_tools <- isTRUE(loaded$enable_rdata_tools)
		  updateCheckboxInput(session, "enable_rdata_tools", value = settings$enable_rdata_tools)
		} else {
		  # Eski kayıtlar için varsayılanı koru
		  settings$enable_rdata_tools <- TRUE
		  updateCheckboxInput(session, "enable_rdata_tools", value = TRUE)
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

      # ---- ADDED per instruction (load path using `loaded_settings`) ----
      loaded_settings <- loaded
      if (!is.null(loaded_settings$enable_mcp_tools)) {
        updateCheckboxInput(session, "enable_mcp_tools", value = loaded_settings$enable_mcp_tools)
      }
      # -------------------------------------------------------------------
    }, ignoreInit = TRUE)
    
    # Update internal state when inputs change
    observeEvent(input$model_selection,         { settings$model_selection         <- input$model_selection })
    observeEvent(input$font_size,               { settings$font_size               <- input$font_size })
    observeEvent(input$enable_animations,       { settings$enable_animations       <- input$enable_animations })
    observeEvent(input$enable_timestamps,       { settings$enable_timestamps       <- input$enable_timestamps })
    observeEvent(input$enable_typing_indicator, { settings$enable_typing_indicator <- input$enable_typing_indicator })
	observeEvent(input$enable_streaming,  { settings$enable_streaming  <- input$enable_streaming })
	observeEvent(input$enable_widescreen, { settings$enable_widescreen <- input$enable_widescreen })

	# Karşılıklı dışlama mantığı
	observeEvent(input$enable_rdata_tools, {
	  settings$enable_rdata_tools <- isTRUE(input$enable_rdata_tools)
	  # Eğer rData açıldıysa MCP'yi kapat
	  if (isTRUE(input$enable_rdata_tools) && isTRUE(input$enable_mcp_tools)) {
		updateCheckboxInput(session, "enable_mcp_tools", value = FALSE)
		settings$enable_mcp_tools <- FALSE
	  }
	}, ignoreInit = TRUE)

	observeEvent(input$enable_mcp_tools, {
	  settings$enable_mcp_tools <- isTRUE(input$enable_mcp_tools)
	  # Eğer MCP açıldıysa rData'yı kapat
	  if (isTRUE(input$enable_mcp_tools) && isTRUE(input$enable_rdata_tools)) {
		updateCheckboxInput(session, "enable_rdata_tools", value = FALSE)
		settings$enable_rdata_tools <- FALSE
	  }
	}, ignoreInit = TRUE)
    
    # Save settings button
    observeEvent(input$save_settings, {
      # Save the temporary character selection
      settings$selected_character <- temp_selected_character()
      
      # ---- ADDED per instruction (save path) ----
		to_save <- reactiveValuesToList(settings)
		to_save$enable_rdata_tools <- isTRUE(input$enable_rdata_tools)
		to_save$enable_mcp_tools   <- isTRUE(input$enable_mcp_tools)
		session$sendCustomMessage("saveSettings", to_save)
      # -------------------------------------------
      
      showToast(session, "Ayarlar kaydedildi!", "success")
    })
    
    # Reset settings button
    observeEvent(input$reset_settings, {
      settings$model_selection         <- api_config$local_models[1]
      settings$selected_character      <- "mergen"
      temp_selected_character("mergen")
      settings$enable_animations       <- TRUE
      settings$enable_timestamps       <- TRUE
      settings$enable_typing_indicator <- TRUE
      settings$enable_streaming        <- TRUE
	  settings$enable_widescreen       <- TRUE
	  settings$enable_rdata_tools      <- TRUE
	  settings$enable_mcp_tools        <- FALSE
      settings$font_size               <- "medium"
      
      updateSelectInput(session, "model_selection", selected = settings$model_selection)
      update_character_display(settings$selected_character)
      updateSelectInput(session, "font_size", selected = settings$font_size)
      updateCheckboxInput(session, "enable_animations",       value = settings$enable_animations)
      updateCheckboxInput(session, "enable_timestamps",       value = settings$enable_timestamps)
      updateCheckboxInput(session, "enable_typing_indicator", value = settings$enable_typing_indicator)
      updateCheckboxInput(session, "enable_streaming",        value = settings$enable_streaming)
      updateCheckboxInput(session, "enable_widescreen",       value = settings$enable_widescreen)
	  updateCheckboxInput(session, "enable_rdata_tools",      value = settings$enable_rdata_tools)
      updateCheckboxInput(session, "enable_mcp_tools",        value = settings$enable_mcp_tools)
      
      session$sendCustomMessage("clearSettings", list())
      showToast(session, "Ayarlar sıfırlandı!", "info")
    })
    
    # IMPORTANT: Return the settings reactive values directly
    return(settings)
  })
}

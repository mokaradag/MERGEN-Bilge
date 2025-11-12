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
          border-radius: 16px;
          padding: 28px;
          margin-bottom: 32px;
          box-shadow: 0 18px 40px rgba(0, 0, 0, 0.3);
        }
        
        .character-selector-buttons {
          display: flex;
          gap: 12px;
          margin-bottom: 28px;
          background: rgba(12, 13, 24, 0.9);
          padding: 10px;
          border-radius: 14px;
          box-shadow: inset 0 2px 6px rgba(0, 0, 0, 0.35);
        }
        
        .character-btn {
          flex: 1;
          padding: 16px 20px;
          border: 1px solid transparent;
          border-radius: 10px;
          background: linear-gradient(145deg, rgba(32, 33, 52, 0.95), rgba(18, 19, 34, 0.92));
          color: var(--text-secondary);
          font-size: 15px;
          font-weight: 600;
          cursor: pointer;
          transition: all 0.3s ease;
          position: relative;
		  box-shadow: 0 2px 5px rgba(0, 0, 0, 0.3);
        }
        
        .character-btn:hover {
		  transform: translateY(-2px);
          box-shadow: 0 6px 14px rgba(0, 0, 0, 0.35);
          color: var(--text-primary);
        }
        
        .character-btn.active {
          color: #ffffff !important;
          transform: translateY(-1px);
          box-shadow: 0 6px 16px rgba(0, 0, 0, 0.45), 0 0 12px currentColor;
          border-color: currentColor;
        }
        
        .character-display-area {
          display: grid;
          grid-template-columns: minmax(380px, 0.85fr) minmax(0, 1.15fr);
          column-gap: 0;
          row-gap: 24px;
          align-items: stretch;
          min-height: 600px;
        }
        
        .character-image-container {
		  position: relative;
          display: flex;
          align-items: center;
          justify-content: center;
          overflow: hidden;
          min-height: 600px;
          border-radius: 18px;
          background: radial-gradient(circle at 20% 20%, rgba(124, 77, 255, 0.25), transparent 55%),
                      radial-gradient(circle at 80% 30%, rgba(58, 171, 255, 0.2), transparent 60%),
                      rgba(8, 9, 18, 0.95);
          box-shadow: inset 0 0 40px rgba(0, 0, 0, 0.35), 0 18px 45px rgba(0, 0, 0, 0.45);
        }
        
		.character-image {
		  position: absolute;
		  top: 50% !important;
		  left: 50% !important;
		  transform: translate(-50%, -50%) !important;
		  height: 100% !important;
		  width: auto !important;
		  max-width: none !important;
		  object-fit: contain !important;
		  opacity: 0;
		  transition: opacity .55s ease, filter .6s ease !important;
		  filter: blur(3px) saturate(110%) brightness(1.02) !important;
		  will-change: opacity, filter;
		}

		.character-image.is-visible {
		  opacity: 1;
		  filter: blur(0) saturate(106%) brightness(1) !important;
		}

		.character-image.is-exiting {
		  opacity: 0;
		  filter: blur(5px) saturate(95%) brightness(.96) !important;
		}
        
        .character-info-container {
          display: flex;
          flex-direction: column;
          justify-content: center;
		  min-height: 600px;
          background: linear-gradient(160deg, rgba(8, 9, 18, 0.96), rgba(8, 11, 26, 0.9));
          border-radius: 18px;
          padding: 32px clamp(22px, 2.4vw, 28px) 32px clamp(10px, 1.2vw, 16px);
          box-shadow: inset 0 0 24px rgba(0, 0, 0, 0.35);
		  margin-left: -250px;
        }
        
        .character-title {
		  font-size: 20px;
          font-weight: 700;
          margin-bottom: 18px;
          opacity: 0;
          animation: fadeIn 0.6s ease 0.2s forwards;
        }
        
        .character-lore {
          font-size: 16px;
          line-height: 1.8;
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

        @media (max-width: 1280px) {
          .character-display-area {
            grid-template-columns: 1fr;
            column-gap: 0;
            row-gap: 24px;
            min-height: 480px;
          }
          .character-image-container,
          .character-info-container {
            min-height: 480px;
          }
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
	  enable_rdata_tools      = FALSE,
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
		  showToast(session, success_m	sg, "success")
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
          accent_active = char$accent_active,
		  accent_hover  = char$accent_hover
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
		  settings$enable_rdata_tools <- FALSE
		  updateCheckboxInput(session, "enable_rdata_tools", value = FALSE)
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
	  settings$enable_rdata_tools      <- FALSE
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

# ui.R
# Dosya Yolu: ui.R
# Açıklama: MERGEN AI uygulamasının ana Kullanıcı Arayüzü (UI) tanımı.
#           shinydashboard kullanılarak başlık (header), yan menü (sidebar)
#           ve ana gövde (body) yapısı oluşturulmuştur. (Mesaj arama çubuğu güncellenmiştir)

ui <- dashboardPage(
  
  # --- Başlık (Header) ---
  dashboardHeader(
    titleWidth = 250,
    title = tags$span(
      class = "navbar-brand",
      span(class = "brand-logo", 
        tags$img(
          src = "img/mergen_avatar.png",
          alt = "MERGEN",
          style = "width: 100%; height: 100%; object-fit: cover; border-radius: 10px;"
        )
      ),
      span(class = "brand-text",
        span("MERGEN", class = "brand-text-primary"),
        span("Bilge", class = "brand-text-secondary")
      )
    )
  ),
  
  # --- Yan Menü (Sidebar) ---
  dashboardSidebar(
    width = 250,
    sidebarMenu(
      id = "tabs",
      # Her bir menuItem, ana gövdedeki bir sekmeye (tab) karşılık gelir.
      menuItem("Ana Söyleşi", tabName = "chat", icon = icon("comments")),
      menuItem("Söyleşi Yönetimi", icon = icon("folder-open"), startExpanded = FALSE,
        menuSubItem("Söyleşi Geçmişi", tabName = "history", icon = icon("history")),
        menuSubItem("Kayıtlı Söyleşiler", tabName = "saved_chats", icon = icon("bookmark")),
        menuSubItem("Görsel Galerisi", tabName = "image_gallery", icon = icon("images"))
      ),
      menuItem("Bilge Yolaç", tabName = "claude_code", icon = icon("terminal")),
      menuItem("Dosya Yönetimi", tabName = "files", icon = icon("folder")),
      menuItem("Ayarlar", icon = icon("cog"), startExpanded = FALSE,
        menuSubItem("Kişiselleştirme", tabName = "settings_kisisel", icon = icon("palette")),
        menuSubItem("Yapılandırma", tabName = "settings_yapilandirma", icon = icon("sliders-h"))
      ),
      menuItem("Destek", icon = icon("life-ring"), startExpanded = FALSE,
        menuSubItem("Yardım Merkezi", tabName = "destek_yardim", icon = icon("circle-question")),
        menuSubItem("Geri Bildirim & Hata", tabName = "destek_geri_bildirim", icon = icon("comment-dots")),
        menuSubItem("Yenilikler", tabName = "destek_surum", icon = icon("rocket")),
        menuSubItem("Hakkında", tabName = "destek_hakkinda", icon = icon("info-circle"))
      ),
      menuItemOutput("admin_menu_item")
    ),
    # Yan menünün alt kısmındaki kullanıcı paneli + tema anahtarı + sürüm.
    # Görünür sürüm etiketi ve kullanıcı bilgileri merkezi helper'lardan gelir;
    # buraya doğrudan sabit sürüm/kullanıcı bilgisi yazılmamalıdır.
    mb_sidebar_user_panel_ui("sidebar_user_panel")
  ),
  
  # --- Ana Gövde (Body) ---
  dashboardBody(
    useShinyjs(), # shinyjs'i başlat (JavaScript etkileşimleri için)

    # Modern çok aşamalı açılış yükleme ekranı (tüm boot süresince ekranı kaplar)
    appLoadingUI(),

    sttUI("stt_module"),
    
    # --- Gizli widget bağımlılık yükleyicileri (Metin olarak eklenen çıktılar için kritik) ---
    tags$div(
    style = "position:absolute; left:-9999px; width:1px; height:1px; overflow:hidden;",
    if (requireNamespace("highcharter", quietly = TRUE))
      highcharter::highchartOutput("deps_hc", height = "1px"),
    if (requireNamespace("plotly", quietly = TRUE) && requireNamespace("ggplot2", quietly = TRUE))
      plotly::plotlyOutput("deps_pl", height = "1px")
    ),

    # --- Başlık İçeriği (Head Content) ---
  tags$head(
    tags$script(HTML("document.documentElement.lang = 'tr'")),
    # Tema önyüklemesi: tema_manager.js'den önce çalışır, FOUC azaltır.
    # localStorage'da kayıtlı tema varsa hemen <html data-theme="..."> uygulanır;
    # aksi halde varsayılan koyu tema korunur.
    tags$script(HTML(paste(
      "(function(){try{",
      "var raw=localStorage.getItem('mergen_settings');",
      "var t=null;",
      "if(raw){var s=JSON.parse(raw); if(s && (s.theme==='light'||s.theme==='dark')){t=s.theme;}}",
      "if(!t){var legacy=localStorage.getItem('mergen_theme');",
      "if(legacy==='light'||legacy==='dark'){t=legacy;}}",
      "if(!t){t='dark';}",
      "document.documentElement.setAttribute('data-theme', t);",
      "document.documentElement.classList.add('theme-'+t);",
      "}catch(e){document.documentElement.setAttribute('data-theme','dark');",
      "document.documentElement.classList.add('theme-dark');}})();",
      sep = ""
    ))),
    tags$meta(charset = "UTF-8"),
    tags$meta(name = "viewport", content = "width=device-width, initial-scale=1.0"),
	tags$link(rel = "icon", type = "image/png", href = "img/mergen_avatar.png"),

	# SSO ön kapısı: Geçerli token yoksa Shiny istemcisi ve açılış yükleme
	# katmanı başlamadan önce Keycloak'a gider. Bu, SSO dönüşünde 0% -> 6%
	# -> tekrar 0% görünen çift başlangıcı engeller.
	ssoPreflightScriptUI(),

	# --- Yerel UI varlıkları ---
	ui_asset_tags(),

	tags$div(id = "toast-container", class = "toast-container")
  ),
      
    # SSO kimlik doğrulama katmanı (SSO_ENABLED=TRUE ise görünür)
    ssoAuthUI("sso_module"),

    # Derin uzay giriş ekranı
    createStartupScreenUI(),
    
    # Geri bildirim modalı
    feedbackUI("feedback_module"),

    # AI Uzman altyazı seridi (tüm sayfalarda sabit konumlu)
    aiExpertSubtitleUI("ai_expert_module"),

    # --- TTS Görselleştirici (tüm sayfalarda sabit konumlu) ---
    # AI Uzman konuşması veya TTS seslendirmesi sırasında animasyon gösterir
    tags$div(
      id = "tts_visualizer_floating",
      class = "tts-visualizer-floating-wrapper",
      ttsVisualizerUI("tts_viz")
    ),

    # --- Sekme İçerikleri (Tab Content) ---
    # Yan menüde tanımlanan her bir sekme için gösterilecek içerikler.
    tabItems(
      # Ana Söyleşi Sekmesi (Çekirdek UI, modül değil)
      tabItem(
        tabName = "chat",
        div(
          id = "chat_main_wrapper",
          # Araç bağlamlı arka plan animasyon katmanı (heptagon + parçacık).
          # İstemci tarafı (www/js/tool_backgrounds.js) içeriği yönetir;
          # araç aktifken görünür, aksi halde gizli kalır. pointer-events yok.
          div(class = "tool-bg-layer", `aria-hidden` = "true"),
          div(id = "welcome_fullscreen_container", class = "welcome-fullscreen-wrapper"),
          div(
            class = "chat-header",
            div(
              class = "chat-header-left",
              h4("Söyleşi", class = "page-title"),
              # MCP modu göstergesi (Excel veya RData aktifse gösterilir) - sola taşındı
              uiOutput("mcp_mode_indicator"),
              conditionalPanel(
                condition = "!output.show_welcome_screen",
                # Karakter avatarı, karakter adı ve model adını göster
                uiOutput("current_model_display")
              ),
              conditionalPanel(
                condition = "!output.show_welcome_screen",
                div(
                  class = "chat-stats",
                  tags$span(
                    class = "stat-item",
                    tags$i(class = "fas fa-comment-dots"),
                    textOutput("message_count", inline = TRUE)
                  )
                )
              )
            ),

            div(
              class = "chat-header-right chat-actions",
              actionButton(
                "new_chat_btn",
                label = tagList(icon("plus"), span("Yeni Söyleşi", class = "btn-text")),
                class = "btn-modern btn-primary"
              ),
              conditionalPanel(
                condition = "!output.show_welcome_screen",
                actionButton(
                  "copy_chat_btn",
                  label = tagList(icon("clipboard"), span("Sohbeti Kopyala", class = "btn-text")),
                  class = "btn-modern btn-info"
                )
              ),
              conditionalPanel(
                condition = "!output.show_welcome_screen",
                downloadButton("export_current_chat_txt", "Sohbeti Dışa Aktar", class = "btn-modern btn-success")
              )
            )
          ),
          div(id = "chat_content_container", class = "chat-container"),
          div(class = "floating-actions", div(id = "scroll_to_bottom_container", actionButton(inputId = "scroll_to_bottom", label = "", icon = icon("angles-down"), class = "fab-button scroll-btn"))),
          div(
            class = "input-container",
            uiOutput("file_prompt_indicator_ui"),
            div(
              class = "input-area",
              div(
                id = "chat_input_wrapper",
                class = "input-wrapper",
                div(id = "drop_zone", class = "drop-zone hidden", tags$i(class = "fas fa-cloud-upload-alt fa-3x"), p("Dosyaları buraya sürükleyin")),
                tags$textarea(id = "user_input", class = "chat-input", placeholder = "MERGEN'e bir mesaj yazın... (Dosya yüklemek için sürükleyip bırakın veya ataç simgesine tıklayın.)", rows = 1, autofocus = "autofocus"),
                div(
                  class = "input-actions",
                  # Görsel oluşturma kontrolleri (Görsel Uzmanı aktifken görünür)
                  div(
                    id = "image_chat_controls",
                    class = "image-chat-controls hidden",
                    div(
                      class = "image-control-item",
                      tags$select(
                        id = "chat_image_size",
                        class = "image-size-select",
                        title = "Görsel Boyutu",
                        tags$option(value = "1024x1024", "Kare"),
                        tags$option(value = "1792x1024", "Yatay"),
                        tags$option(value = "1024x1792", "Dikey")
                      )
                    ),
                    div(
                      class = "image-control-item",
                      tags$label(
                        class = "quality-mini-switch",
                        title = "HD Kalite",
                        tags$input(
                          type = "checkbox",
                          id = "chat_image_quality_hd",
                          class = "quality-mini-input"
                        ),
                        tags$span(class = "quality-mini-slider"),
                        tags$span(class = "quality-mini-label", "HD")
                      )
                    )
                  ),
                  # Özetleme kontrolleri (Dosya Özetleme aktifken görünür)
                  div(
                    id = "summary_chat_controls",
                    class = "summary-chat-controls hidden",
                    div(
                      class = "summary-control-item",
                      tags$select(
                        id = "chat_summary_detail",
                        class = "summary-detail-select",
                        title = "Detay Seviyesi: Özetin ne kadar ayrıntılı olacağını belirler",
                        tags$option(value = "brief", "Kısa Özet"),
                        tags$option(value = "standard", selected = "selected", "Standart"),
                        tags$option(value = "detailed", "Detaylı")
                      )
                    ),
                    div(class = "summary-control-separator"),
                    div(
                      class = "summary-control-item",
                      tags$select(
                        id = "chat_summary_focus",
                        class = "summary-focus-select",
                        title = "Odak Modu: Özetin hangi konulara ağırlık vereceğini belirler",
                        tags$option(value = "general", selected = "selected", "Genel"),
                        tags$option(value = "numerical", "Sayısal Veri"),
                        tags$option(value = "decisions", "Karar & Öneri"),
                        tags$option(value = "comparison", "Karşılaştırma")
                      )
                    )
                  ),
                  # Analiz kontrolleri (Proje ve Kaynak Analizi aktifken görünür)
                  div(
                    id = "analysis_chat_controls",
                    class = "analysis-chat-controls hidden",
                    div(
                      class = "analysis-control-item",
                      tags$button(
                        id = "chat_deep_thinking_toggle",
                        class = "deep-thinking-toggle",
                        type = "button",
                        title = "Derin Düşünme: Pasif - Tek sorgu analizi yapılacak",
                        tags$i(class = "fas fa-brain toggle-icon"),
                        tags$span(class = "toggle-label", "Derin Düşünme")
                      )
                    ),
                    div(class = "analysis-control-separator"),
                    div(
                      class = "analysis-control-item",
                      tags$select(
                        id = "chat_analysis_detail",
                        class = "analysis-detail-select",
                        title = "Detay Seviyesi: Yanıtın ne kadar ayrıntılı olacağını belirler",
                        disabled = "disabled",
                        tags$option(value = "ozet", "Özet"),
                        tags$option(value = "standart", selected = "selected", "Standart"),
                        tags$option(value = "detayli", "Detaylı")
                      )
                    )
                  ),
                  # Excel Analizi: Derin Düşünme düğmesi + Düşük/Yüksek seviye dropdown
                  div(
                    id = "excel_chat_controls",
                    class = "excel-chat-controls hidden",
                    div(
                      class = "excel-control-item",
                      tags$button(
                        id = "chat_excel_deep_thinking_toggle",
                        class = "deep-thinking-toggle excel-deep-thinking-toggle",
                        type = "button",
                        title = "Derin Düşünme: Pasif - Excel için temel düşünen modeli kullan",
                        tags$i(class = "fas fa-brain toggle-icon"),
                        tags$span(class = "toggle-label", "Derin Düşünme")
                      )
                    ),
                    div(class = "excel-control-separator"),
                    div(
                      class = "excel-control-item",
                      tags$select(
                        id = "chat_excel_deep_level",
                        class = "deep-thinking-level-select",
                        title = "Derin Düşünme Seviyesi: Düşük/Yüksek alternatif düşünen modeli seçer",
                        disabled = "disabled",
                        tags$option(value = "low", selected = "selected", "Düşük"),
                        tags$option(value = "high", "Yüksek")
                      )
                    )
                  ),
                  # Kod Uzmanı: Derin Düşünme düğmesi + Düşük/Yüksek seviye dropdown
                  div(
                    id = "coding_chat_controls",
                    class = "coding-chat-controls hidden",
                    div(
                      class = "coding-control-item",
                      tags$button(
                        id = "chat_coding_deep_thinking_toggle",
                        class = "deep-thinking-toggle coding-deep-thinking-toggle",
                        type = "button",
                        title = "Derin Düşünme: Pasif - Kod için temel düşünen modeli kullan",
                        tags$i(class = "fas fa-brain toggle-icon"),
                        tags$span(class = "toggle-label", "Derin Düşünme")
                      )
                    ),
                    div(class = "coding-control-separator"),
                    div(
                      class = "coding-control-item",
                      tags$select(
                        id = "chat_coding_deep_level",
                        class = "deep-thinking-level-select",
                        title = "Derin Düşünme Seviyesi: Düşük/Yüksek alternatif düşünen modeli seçer",
                        disabled = "disabled",
                        tags$option(value = "low", selected = "selected", "Düşük"),
                        tags$option(value = "high", "Yüksek")
                      )
                    )
                  ),
                  div(class = "model-selector-wrapper",
                      uiOutput("chat_model_selector_ui", style = "display:inline-block;")
                  ),
				  div(id = "file_btn_container", class = "action-btn file-btn", title = "Dosya Ekle (Ctrl+Alt+U)", tags$label(`for` = "file_upload", tags$i(class = "fas fa-paperclip"))),
                  actionButton(inputId = "voice_btn", label = "", icon = icon("microphone"), class = "action-btn voice-btn", title = "Sesli Giriş"),
                  actionButton(
                    inputId = "send_stop_btn",
                    label = "",
                    icon = icon("paper-plane"),
                    class = "send-button",
                    title = "Gönder (Enter)"
                  )
                ),
                div(style = "display: none;", fileInput("file_upload", label = NULL, multiple = FALSE))
              )
            ),
            div(
              class = "char-counter-wrapper",
              tags$span(id = "char_counter", "0 / 10000")
            )
          )
        )
      ),
      
      # --- Modül UI Çağrıları ---
      
      # Geçmiş Sekmesi
      tabItem(tabName = "history", historyUI("history_module")),
      
      # Kaydedilmiş Söyleşiler Sekmesi
      tabItem(tabName = "saved_chats", savedChatsUI("saved_chats_module")),

      # Görsel Galerisi Sekmesi
      tabItem(tabName = "image_gallery", imageGalleryUI("image_gallery_module")),
      
      # Claude Code Sekmesi
      tabItem(tabName = "claude_code", claudeCodeUI("claude_code_module")),

      # Dosya Yönetimi Sekmesi
      tabItem(tabName = "files", fileManagerUI("file_manager_module")),
      
      # Ayarlar Alt Sekmeleri
      tabItem(tabName = "settings_kisisel", settingsKisiselUI("settings_kisisel_module")),
      tabItem(tabName = "settings_yapilandirma", settingsYapilandirmaUI("settings_yapilandirma_module")),

      # Destek Sayfaları
      tabItem(tabName = "destek_yardim", destekUI("destek_module", sayfa = "yardim")),
      tabItem(tabName = "destek_geri_bildirim", destekUI("destek_module", sayfa = "geri_bildirim")),
      tabItem(tabName = "destek_surum", destekUI("destek_module", sayfa = "surum")),
      tabItem(tabName = "destek_hakkinda", destekUI("destek_module", sayfa = "hakkinda")),

      # Yönetici Paneli Alt Sekmeleri (Sadece yöneticiler için)
      tabItem(tabName = "admin_analytics", adminAnalyticsUI("admin_analytics_module")),
      tabItem(tabName = "admin_geri_bildirim", adminGeriBildirimUI("admin_geri_bildirim_module")),
      tabItem(tabName = "admin_hata_analizi", adminHataAnaliziUI("admin_hata_analizi_module")),
      tabItem(tabName = "admin_yanit_analizi", adminYanitAnaliziUI("admin_yanit_analizi_module")),

      # Sistem Durumu Sekmesi (Yönetici paneli altında)
      tabItem(tabName = "health", healthUI("health_module"))
    ),
    
    # JavaScript iletişimi için gizli girdiler (Hidden inputs)
    tags$div(
      style = "display: none;",
      textInput("keyboard_nav", ""),
      textInput("quick_template", ""),
      textInput("loaded_settings", "")
    ),

    # Bağlantı kesilme durumu için kaplama (overlay) ekranı
    tags$div(
      id = "disconnect-overlay",
      class = "disconnect-overlay",
      div(
        class = "disconnect-message",
        h3("Bağlantı Kesildi"),
        p("Sunucu ile bağlantı koptu. Lütfen sayfayı yeniden yükleyin."),
        tags$button("Sayfayı Yeniden Yükle", class = "btn-modern btn-primary", onClick = "window.location.reload();")
      )
    )
  )
)
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
          src = "mergen_avatar.png",
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
      menuItem("Claude Code", tabName = "claude_code", icon = icon("terminal")),
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
    # Yan menünün alt kısmındaki sabit altbilgi (footer).
    div(
      class = "sidebar-footer",
      p("MERGEN AI v0.9", class = "sidebar-version"),
      p(sprintf("© %s Tüm hakları saklıdır", format(Sys.Date(), "%Y")), class = "sidebar-copyright")
    )
  ),
  
  # --- Ana Gövde (Body) ---
  dashboardBody(
    useShinyjs(), # shinyjs'i başlat (JavaScript etkileşimleri için)
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
    tags$meta(charset = "UTF-8"),
    tags$meta(name = "viewport", content = "width=device-width, initial-scale=1.0"),
    tags$link(rel = "icon", type = "image/png", href = "mergen_avatar.png"),
    
    # --- Yerel CSS Dosyaları ---
    tags$link(rel = "stylesheet", type = "text/css", href = "css/fonts.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/welcome_modern.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/welcome_greeting_personal.css"),    
    tags$link(rel = "stylesheet", type = "text/css", href = "css/all.min.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/model_selector.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/codemirror-custom.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/character-selector.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/character_video.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/typing-indicator.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/tts_visualizer.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/stt.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/music_slider.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/variables.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/animations.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/layout.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/components.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/code_highlighting.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/welcome_screen.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/datatables.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/chat_messages.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/chat_input.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/date_picker.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/cinematic_intro.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/deep_space_intro.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/mode_selection.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/explore_cinematic.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/mcp_indicator.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/file_manager.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/history_saved_chats.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/settings_page.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/health_check.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/disconnect_overlay.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/chat_header.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/quick_templates.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/capabilities.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/custom_buttons.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/utilities.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/responsive.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/accessibility.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/layout_overrides.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/pagination_custom.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/modals_custom.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/welcome_styles.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/recent_chats_custom.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/empty_state.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/animations_extra.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/message_actions.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/feedback_modal.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/image_tools.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/image_gallery.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/summarization_tools.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/code_collapse.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/chat_search_modal.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/settings_tools.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/analysis_tools.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/citation_styles.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/ai_expert_subtitle.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/destek_page.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/destek_yardim_chatbot.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/admin_destek_analytics.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/admin_yanit_analizi.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/explore_character_step.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/surum_bilgilendirme.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/sso_auth.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/claude_code.css"),

    # --- Yerel CodeMirror CSS Dosyaları ---
    tags$link(rel = "stylesheet", href = "codemirror/codemirror.min.css"),
    tags$link(rel = "stylesheet", href = "codemirror/theme/material-darker.min.css"),
    tags$link(rel = "stylesheet", href = "codemirror/addon/fold/foldgutter.min.css"),

    # --- Yerel JavaScript Dosyaları ---
    # Çekirdek CodeMirror
    tags$script(src = "codemirror/codemirror.min.js"),
    
    # Dil Modları (Kapsamlı Liste)
    tags$script(src = "codemirror/mode/r.min.js"),
    tags$script(src = "codemirror/mode/python.min.js"),
    tags$script(src = "codemirror/mode/javascript.min.js"),
    tags$script(src = "codemirror/mode/sql.min.js"),
    tags$script(src = "codemirror/mode/shell.min.js"),
    tags$script(src = "codemirror/mode/css.min.js"),
    tags$script(src = "codemirror/mode/xml.min.js"),
    tags$script(src = "codemirror/mode/htmlmixed.min.js"),
    tags$script(src = "codemirror/mode/clike.min.js"),
    tags$script(src = "codemirror/mode/php.min.js"),
    tags$script(src = "codemirror/mode/ruby.min.js"),
    tags$script(src = "codemirror/mode/go.min.js"),
    tags$script(src = "codemirror/mode/swift.min.js"),
    tags$script(src = "codemirror/mode/powershell.min.js"),
    tags$script(src = "codemirror/mode/commonlisp.min.js"),
    tags$script(src = "codemirror/mode/vb.min.js"),
    tags$script(src = "codemirror/mode/fortran.min.js"),
    tags$script(src = "codemirror/mode/octave.min.js"),
    tags$script(src = "codemirror/mode/julia.min.js"),

    # Eklentiler (Addons)
    tags$script(src = "codemirror/addon/comment/comment.min.js"),
    tags$script(src = "codemirror/addon/fold/foldcode.min.js"),
    tags$script(src = "codemirror/addon/fold/foldgutter.min.js"),
    tags$script(src = "codemirror/addon/fold/brace-fold.min.js"),
    tags$script(src = "codemirror/addon/fold/comment-fold.min.js"),
    tags$script(src = "codemirror/addon/fold/indent-fold.min.js"),
    tags$script(src = "codemirror/addon/fold/xml-fold.js"),
    
    # --- Three.js Kütüphanesi (ertelenmiş yükleme - giriş animasyonu için) ---
    tags$script(src = "lib/threejs/three.min.js", defer = "defer"),
    tags$script(src = "lib/threejs/OrbitControls.js", defer = "defer"),
    tags$script(src = "lib/threejs/CopyShader.js", defer = "defer"),
    tags$script(src = "lib/threejs/LuminosityHighPassShader.js", defer = "defer"),
    tags$script(src = "lib/threejs/ShaderPass.js", defer = "defer"),
    tags$script(src = "lib/threejs/EffectComposer.js", defer = "defer"),
    tags$script(src = "lib/threejs/RenderPass.js", defer = "defer"),
    tags$script(src = "lib/threejs/UnrealBloomPass.js", defer = "defer"),
    tags$script(src = "lib/threejs/Lensflare.js", defer = "defer"),

    # --- SSO Kimlik Doğrulama Betiği (senkron - diğer betiklerden önce yüklenmeli) ---
    tags$script(src = "js/sso_auth.js"),

    # --- Kritik JavaScript Betikleri (senkron yüklenir, sayfa işlevselliği için gerekli) ---
    tags$script(src = "js/utils.js"),
    tags$script(src = "js/shiny_message_handlers.js"),
    tags$script(src = "js/ui_init.js"),
    tags$script(src = "js/input_handlers.js"),
    tags$script(src = "js/interaction_handlers.js"),
    tags$script(src = "js/app_core.js"),
    tags$script(src = "js/streaming_manager.js"),
    tags$script(src = "js/toast.js"),
    tags$script(src = "js/markdown-parser.js"),
    tags$script(src = "js/layout-manager.js"),

    # --- Ertelenmiş JavaScript Betikleri (ilk sayfa yüklemesini engellemez) ---
    tags$script(src = "js/code-collapse.js", defer = "defer"),
    tags$script(src = "js/file_handlers.js", defer = "defer"),
    tags$script(src = "js/chart_renderer.js", defer = "defer"),
    tags$script(src = "js/table_scroll_handler.js", defer = "defer"),
    tags$script(src = "js/codemirror-manager.js", defer = "defer"),
    tags$script(src = "js/cinematic_video.js", defer = "defer"),
    tags$script(src = "js/character_typing.js", defer = "defer"),
    tags$script(src = "js/tts_visualizer.js", defer = "defer"),
    tags$script(src = "js/stt_client.js", defer = "defer"),
    tags$script(src = "js/intro_animation.js", defer = "defer"),
    tags$script(src = "js/typing_animation.js", defer = "defer"),
    tags$script(src = "js/neural_welcome.js", defer = "defer"),
    tags$script(src = "js/welcome_video_player.js", defer = "defer"),
    tags$script(src = "js/welcome_neural_modern.js", defer = "defer"),
    tags$script(src = "js/welcome_greeting.js", defer = "defer"),
    tags$script(src = "js/welcome_greeting_personal.js", defer = "defer"),
    tags$script(src = "js/tts_manager.js", defer = "defer"),
    tags$script(src = "js/character_manager.js", defer = "defer"),
    tags$script(src = "js/shortcuts_manager.js", defer = "defer"),
    tags$script(src = "js/feedback_modal.js", defer = "defer"),
    tags$script(src = "js/music_manager.js", defer = "defer"),
    tags$script(src = "js/image_tools.js", defer = "defer"),
    tags$script(src = "js/image_gallery.js", defer = "defer"),
    tags$script(src = "js/summarization_tools.js", defer = "defer"),
    tags$script(src = "js/chat_search_modal.js", defer = "defer"),
    tags$script(src = "js/deep_space_intro.js", defer = "defer"),
    tags$script(src = "js/mode_selection.js", defer = "defer"),
    tags$script(src = "js/explore_cinematic.js", defer = "defer"),
    tags$script(src = "js/settings_tools.js", defer = "defer"),
    tags$script(src = "js/analysis_tools.js", defer = "defer"),
    tags$script(src = "js/citation_handler.js", defer = "defer"),
    tags$script(src = "js/ai_expert_manager.js", defer = "defer"),
    tags$script(src = "js/destek_form.js", defer = "defer"),
    tags$script(src = "js/destek_yardim_chatbot.js", defer = "defer"),
    tags$script(src = "js/space_intro_music.js", defer = "defer"),
    tags$script(src = "js/explore_character_video.js", defer = "defer"),
    tags$script(src = "js/explore_character_step.js", defer = "defer"),
    tags$script(src = "js/surum_bilgilendirme.js", defer = "defer"),
    tags$script(src = "js/claude_code.js", defer = "defer"),

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
                  div(class = "model-selector-wrapper",
                      uiOutput("chat_model_selector_ui", style = "display:inline-block;")
                  ),
                  div(id = "file_btn_container", class = "action-btn file-btn", title = "Dosya Ekle (Ctrl+U)", tags$label(`for` = "file_upload", tags$i(class = "fas fa-paperclip"))),
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
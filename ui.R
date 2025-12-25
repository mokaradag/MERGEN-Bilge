# ui.R (Updated with message search bar)

# The main UI is defined using shinydashboard's dashboardPage.
# This structure provides the header, sidebar, and body of the application.
ui <- dashboardPage(
  
  # --- Header ---
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
  
  # --- Sidebar ---
  dashboardSidebar(
    width = 250,
    sidebarMenu(
      id = "tabs",
      # Each menuItem corresponds to a tab in the main body.
      menuItem("Ana Söyleşi", tabName = "chat", icon = icon("comments")),
      menuItem("Söyleşi Yönetimi", icon = icon("folder-open"), startExpanded = FALSE,
        menuSubItem("Söyleşi Geçmişi", tabName = "history", icon = icon("history")),
        menuSubItem("Kayıtlı Söyleşiler", tabName = "saved_chats", icon = icon("bookmark"))
      ),
      menuItem("Dosya Yönetimi", tabName = "files", icon = icon("folder")),
	  menuItem("Ayarlar", tabName = "settings", icon = icon("cog")),
      menuItemOutput("admin_menu_item"),
      menuItem("Sistem Durumu", tabName = "health", icon = icon("heartbeat"))
    ),
    # A static footer at the bottom of the sidebar.
    div(
      class = "sidebar-footer",
      p("MERGEN AI v2.0", class = "sidebar-version"),
      p("© 2025 Tüm hakları saklıdır", class = "sidebar-copyright")
    )
  ),
  
  # --- Body ---
  dashboardBody(
    useShinyjs(), # Initialize shinyjs
	sttUI("stt_module"),
	
	# --- Hidden widget dependency loaders (critical for string-injected outputs) ---
	tags$div(
	style = "position:absolute; left:-9999px; width:1px; height:1px; overflow:hidden;",
	if (requireNamespace("highcharter", quietly = TRUE))
	  highcharter::highchartOutput("deps_hc", height = "1px"),
	if (requireNamespace("plotly", quietly = TRUE) && requireNamespace("ggplot2", quietly = TRUE))
	  plotly::plotlyOutput("deps_pl", height = "1px")
	),

    # --- Head Content ---
  tags$head(
    tags$script(HTML("document.documentElement.lang = 'tr'")),
    tags$meta(charset = "UTF-8"),
    tags$meta(name = "viewport", content = "width=device-width, initial-scale=1.0"),
    tags$link(rel = "icon", type = "image/png", href = "mergen_avatar.png"),
    
    # --- Local CSS Files ---
	tags$link(rel = "stylesheet", type = "text/css", href = "css/fonts.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/all.min.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/model_selector.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/tts_visualizer.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "css/stt.css"),
    
    # --- Local CodeMirror CSS ---
    tags$link(rel = "stylesheet", href = "codemirror/codemirror.min.css"),
    tags$link(rel = "stylesheet", href = "codemirror/theme/material-darker.min.css"),
    tags$link(rel = "stylesheet", href = "codemirror/addon/fold/foldgutter.min.css"),

    tags$link(rel = "stylesheet", type = "text/css", href = "custom.css"),
	tags$link(rel = "stylesheet", type = "text/css", href = "css/character_video.css"),

    # --- Local JavaScript Files ---
    # Core CodeMirror
    tags$script(src = "codemirror/codemirror.min.js"),
    
    # Language Modes (Comprehensive List)
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

    # Addons
    tags$script(src = "codemirror/addon/comment/comment.min.js"),
    tags$script(src = "codemirror/addon/fold/foldcode.min.js"),
    tags$script(src = "codemirror/addon/fold/foldgutter.min.js"),
    tags$script(src = "codemirror/addon/fold/brace-fold.min.js"),
    tags$script(src = "codemirror/addon/fold/comment-fold.min.js"),
    tags$script(src = "codemirror/addon/fold/indent-fold.min.js"),
    tags$script(src = "codemirror/addon/fold/xml-fold.js"),
    # Note: r-fold.js is intentionally removed as it does not exist.
    
    # Your Custom Script
	tags$script(src = "script.js"),
    tags$script(src = "js/cinematic_video.js"),
    tags$script(src = "character_typing.js"),
    tags$script(src = "js/tts_visualizer.js"),
    tags$script(src = "js/stt_client.js"),
    
    tags$div(id = "toast-container", class = "toast-container")
  ),
      
    # Cinematic intro screen that fades out on load
    tags$div(
      id = "intro-container",
      class = "intro-container",
      tags$canvas(id = "neural-canvas", class = "neural-canvas"),
      tags$div(
        class = "intro-logo",
        tags$span("MERGEN", class = "intro-text-primary"),
        tags$span("Bilge", class = "intro-text-secondary")
      )
    ),
    
    # --- Tab Content ---
    # The content for each tab defined in the sidebar.
    tabItems(
      # Main Chat Tab (Core UI, not a module)
      tabItem(
        tabName = "chat",
        div(
          class = "chat-header",
          div(
            class = "chat-header-left",
            h4("Söyleşi", class = "page-title"),
            # MCP modu göstergesi (Excel veya RData aktifse gösterilir) - moved to left
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
		  
		  # --- TTS Visualizer Module UI ---
          ttsVisualizerUI("tts_viz"),
		  
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
        # This is now a static container for all message bubbles
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
              div(style = "display: none;", fileInput("file_upload", label = NULL, multiple = FALSE)) # Single file upload for chat context
            )
          ),
          div(
            class = "char-counter-wrapper",
            tags$span(id = "char_counter", "0 / 10000")
          )
        )
      ),
      
      # --- Module UI Calls ---
      # Each tabItem now simply calls the UI function from its corresponding module file.
      # This makes the main UI file clean and easy to navigate.
      
      # History Tab
      tabItem(tabName = "history", historyUI("history_module")),
      
      # Saved Chats Tab
      tabItem(tabName = "saved_chats", savedChatsUI("saved_chats_module")),
      
      # Files Tab
      tabItem(tabName = "files", fileManagerUI("file_manager_module")),
      
      # Settings Tab
      tabItem(tabName = "settings", settingsUI("settings_module")),

	  # Admin Analytics Tab (ADMIN only)
      tabItem(tabName = "admin_analytics", adminAnalyticsUI("admin_analytics_module")),

      # Health Check Tab (modularized)
      tabItem(tabName = "health", healthUI("health_module"))
    ),
    
    # Hidden inputs for JavaScript communication
    tags$div(
      style = "display: none;",
      textInput("keyboard_nav", ""),
      textInput("quick_template", ""),
      textInput("loaded_settings", "")
    ),

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
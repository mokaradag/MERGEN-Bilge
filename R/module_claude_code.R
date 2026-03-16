# ==============================================================================
# Dosya Yolu: R/module_claude_code.R
# Açıklama: Claude Code entegrasyon modülü. Kullanıcılara web arayüzü üzerinden
#           Claude Code CLI yeteneklerini sunar. Dosya okuma/yazma, terminal
#           komutları, araç kullanımı gibi tam ajan yetenekleri desteklenir.
#           Karakter temalı 8-bit animasyonlar, araç kullanımı görüntüleme,
#           retro karşılama ekranı ve Türkçe düşünme mesajları içerir.
# ==============================================================================

# ==============================================================================
# CLAUDE CODE UI
# ==============================================================================

claudeCodeUI <- function(id) {
  ns <- NS(id)

  # settings.json'dan model listesini oku ve katman etiketleriyle eşleştir
  ayarlar <- read_claude_settings_json()
  model_secenekleri <- ayarlar$models
  varsayilan_model <- ayarlar$default_model

  # Model katmanlarını oluştur
  katmanlar <- build_model_tier_choices(model_secenekleri)
  # Etiketleri hizalı ikon ve metin ile oluştur
  model_degerleri <- setNames(
    sapply(katmanlar, function(k) k$deger),
    sapply(katmanlar, function(k) {
      # Sabit genişlikte metin etiketi (hizalama için)
      paste0("[", substr(toupper(k$etiket), 1, 1), "] ", k$etiket, " - ", k$aciklama)
    })
  )

  tagList(
    div(
      class = "claude-code-container",
      # Karakter teması için veri özniteliği (JavaScript tarafından güncellenir)
      `data-character` = "mergen",

      # --- Sayfa Başlığı ---
      div(
        class = "chat-header settings-header-fixed",
        div(
          class = "chat-header-left",
          h4("Claude Code", class = "page-title"),
          tags$span(class = "cc-badge", "AJAN")
        ),
        div(
          class = "chat-header-right",
          # Bağlantı durum göstergesi
          uiOutput(ns("connection_status_badge"))
        )
      ),

      # --- Ana İçerik (sabit düzen) ---
      div(
        class = "cc-main-content",

        # --- Sol Panel: Ayarlar ve Senaryolar ---
        div(
          class = "cc-sidebar-panel",

          # Proje Dizini Kartı
          div(
            class = "cc-settings-card",
            h5(class = "cc-card-title", icon("folder-open"), "Proje Dizini"),

            # Proje dizini giriş alanı + klasör tarayıcı düğmesi
            div(
              class = "cc-workdir-row",
              textInput(
                ns("workdir"),
                label = NULL,
                value = claude_code_config$default_workdir,
                placeholder = "Proje klasör yolunu girin..."
              ),
              # Sunucu taraflı klasör tarayıcı düğmesi
              actionButton(
                ns("open_folder_browser"),
                label = NULL,
                icon = icon("folder-open"),
                class = "cc-browse-btn",
                title = "Klasör seç"
              )
            ),

            # Model Seçimi (katmanlı dropdown)
            div(
              class = "cc-model-select-wrapper",
              tags$label(class = "cc-select-label", "Model"),
              selectInput(
                ns("model"),
                label = NULL,
                choices = model_degerleri,
                selected = if (nzchar(varsayilan_model)) varsayilan_model else NULL
              )
            )
          ),

          # Ön Tanımlı Senaryolar
          div(
            class = "cc-settings-card cc-scenarios-card",
            h5(class = "cc-card-title", icon("bolt"), "Hazır Senaryolar"),
            div(
              class = "cc-scenario-grid",
              lapply(claude_code_scenarios, function(senaryo) {
                actionButton(
                  ns(paste0("scenario_", senaryo$id)),
                  label = tagList(
                    icon(senaryo$ikon),
                    span(senaryo$baslik)
                  ),
                  class = "cc-scenario-btn",
                  title = senaryo$aciklama
                )
              })
            )
          ),

          # Dizin İçerik Paneli
          div(
            class = "cc-settings-card cc-dir-card",
            h5(class = "cc-card-title", icon("folder-tree"), "Dizin İçeriği"),
            # Üst gezinti çubuğu (geri düğmesi + mevcut dizin)
            div(
              class = "cc-dir-nav",
              actionButton(
                ns("dir_go_up"),
                label = NULL,
                icon = icon("arrow-up"),
                class = "btn-sm cc-dir-up-btn",
                title = "Üst dizine git"
              ),
              span(id = ns("dir_current_path"), class = "cc-dir-current-path"),
              actionButton(
                ns("refresh_dir"),
                label = NULL,
                icon = icon("sync"),
                class = "btn-sm cc-refresh-btn",
                title = "Yenile"
              )
            ),
            uiOutput(ns("dir_contents_ui"))
          )
        ),

        # --- Sağ Panel: Terminal / Sohbet Alanı ---
        div(
          class = "cc-terminal-panel",

          # Çıktı / Sonuç Alanı (kaydırılabilir, esnek yükseklik)
          div(
            class = "cc-output-wrapper",
            # Retro karşılama ekranı (çıktı alanı boşken görünür)
            div(
              id = ns("welcome_screen"),
              class = "cc-welcome-screen cc-welcome-active"
              # İçerik JavaScript tarafından oluşturulur
            ),
            div(
              id = ns("output_area"),
              class = "cc-output-area"
              # İçerik JavaScript tarafından yönetilir
            )
          ),

          # 8-bit düşünme animasyonu (küçültülmüş, köşede)
          div(
            id = ns("thinking_overlay"),
            class = "cc-thinking-mini cc-hidden",
            tags$canvas(
              id = ns("pixel_canvas"),
              class = "cc-pixel-canvas-mini",
              width = "48",
              height = "48"
            ),
            div(
              id = ns("thinking_text"),
              class = "cc-thinking-text-mini"
            )
          ),

          # Komut Giriş Alanı (sabit konumda, altta)
          div(
            class = "cc-input-area",
            div(
              class = "cc-input-wrapper",
              tags$textarea(
                id = ns("prompt_input"),
                class = "cc-prompt-input",
                placeholder = "Claude Code'a bir komut yazın...",
                rows = 3
              ),
              div(
                class = "cc-input-actions",
                # Karakter Göstergesi
                uiOutput(ns("active_character_indicator")),
                # Temizle Düğmesi
                actionButton(
                  ns("clear_output"),
                  label = NULL,
                  icon = icon("eraser"),
                  class = "cc-action-btn cc-clear-btn",
                  title = "Çıktıyı Temizle"
                ),
                # Durdur Düğmesi (çalışırken görünür)
                actionButton(
                  ns("stop_command"),
                  label = tagList(icon("stop"), "Durdur"),
                  class = "cc-stop-btn cc-hidden",
                  title = "İşlemi durdur"
                ),
                # Çalıştır Düğmesi
                actionButton(
                  ns("run_command"),
                  label = tagList(icon("play"), "Çalıştır"),
                  class = "cc-run-btn"
                )
              )
            ),
            # Durum Çubuğu
            div(
              class = "cc-status-bar",
              span(id = ns("status_text"), class = "cc-status-text"),
              span(id = ns("duration_text"), class = "cc-duration-text")
            )
          )
        )
      )
    )
  )
}

# ==============================================================================
# CLAUDE CODE SERVER
# ==============================================================================

claudeCodeServer <- function(id, current_user_id, settings_data = NULL,
                              user_first_name = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Reaktif değerler
    rv <- reactiveValues(
      is_running = FALSE,
      output_history = list(),
      last_result = NULL,
      connection_ok = NULL,
      cli_path_resolved = NULL,
      has_messages = FALSE,
      conversation_context = list(),  # Bağlam koruma için konuşma geçmişi
      stop_requested = FALSE,         # Durdurma isteği bayrağı
      cli_session_id = NULL,          # Claude Code CLI oturum kimliği (--resume için)
      current_model = NULL,           # Model değişim takibi
      active_process = NULL           # Aktif processx süreci (durdurma için)
    )

    # --- Uygulama başladığında CLI yolunu otomatik tespit et ---
    observe({
      yol <- resolve_claude_cli_path(claude_code_config$cli_path)
      rv$cli_path_resolved <- yol
    }, priority = 100)

    # --- Otomatik bağlantı testi (sayfa görüntülendiğinde, başlangıçta değil) ---
    # Uygulama başlangıcını yavaşlatmamak için sadece CLI durumunu kontrol et,
    # tam bağlantı testini kullanıcı sayfayı görüntülediğinde çalıştır.
    observe({
      req(is.null(rv$connection_ok))
      cli_yolu <- rv$cli_path_resolved
      if (is.null(cli_yolu)) {
        rv$connection_ok <- FALSE
        return()
      }
      # Sadece CLI erişilebilirliğini kontrol et (hızlı, --version ile)
      durum <- tryCatch({
        check_claude_code_status(cli_yolu)
      }, error = function(e) {
        list(installed = FALSE)
      })
      if (durum$installed) {
        rv$connection_ok <- TRUE
        log_info(paste(CLAUDE_CODE_LOG_PREFIX, "CLI erişilebilir:", durum$version))
      } else {
        rv$connection_ok <- FALSE
        temiz_hata <- gsub("[{}]", "", durum$error %||% "")
        log_warn(paste(CLAUDE_CODE_LOG_PREFIX, "CLI erişilemez:", temiz_hata))
      }
    }, priority = 50)

    # --- Yapılandırma sayfasından bağlantı testi sonucunu dinle ---
    observe({
      req(!is.null(settings_data))
      # Yapılandırma sayfasında test başarılı olduysa güncelle
      zaman_asimi <- settings_data$claude_code_timeout
      if (!is.null(zaman_asimi)) {
        # Zaman aşımı ayarı değiştiğinde not al (iletişim aktif)
      }
    })

    # --- Yapılandırma sayfasından bağlantı testi sonucu geldiğinde güncelle ---
    observe({
      req(!is.null(settings_data))
      yapilandirma_sonucu <- settings_data$claude_code_connection_ok
      if (!is.null(yapilandirma_sonucu)) {
        rv$connection_ok <- yapilandirma_sonucu
      }
    })

    # --- Aktif karakter bilgisini al ---
    get_active_character <- reactive({
      karakter_id <- "mergen"
      if (!is.null(settings_data) && !is.null(settings_data$selected_character)) {
        secili <- settings_data$selected_character
        if (!is.null(secili) && nzchar(secili)) {
          karakter_id <- secili
        }
      }

      # Karakter verilerinden renk bilgisini al
      karakterler <- get_characters_data()
      secili <- NULL
      for (s in karakterler$styles) {
        if (s$id == karakter_id) {
          secili <- s
          break
        }
      }
      if (is.null(secili)) secili <- karakterler$styles[[1]]
      secili
    })

    # --- Karakter değiştiğinde temayı güncelle ---
    observe({
      karakter <- get_active_character()
      session$sendCustomMessage(
        type = "cc-update-theme",
        message = list(
          characterId = karakter$id,
          accentColor = karakter$accent,
          accentHover = karakter$accent_hover %||% karakter$accent,
          displayName = karakter$display_name
        )
      )
    })

    # --- Kullanıcı adını belirle ---
    kullanici_adi <- reactive({
      # Önce parametre olarak gelen adı dene
      if (!is.null(user_first_name)) {
        ad <- if (is.reactive(user_first_name)) user_first_name() else user_first_name
        if (!is.null(ad) && nzchar(ad)) return(ad)
      }
      # session$userData'dan dene
      ad <- session$userData$user_first_name
      if (!is.null(ad) && nzchar(ad)) return(ad)
      # user_config'den dene
      uc <- session$userData$user_config
      if (!is.null(uc) && !is.null(uc$first_name) && nzchar(uc$first_name)) return(uc$first_name)
      if (!is.null(uc) && !is.null(uc$name) && nzchar(uc$name)) return(uc$name)
      # Varsayılan
      "Siz"
    })

    # --- Bağlantı Durumu Rozeti ---
    output$connection_status_badge <- renderUI({
      durum <- rv$connection_ok
      if (is.null(durum)) {
        tags$span(class = "cc-status-badge cc-status-checking",
                  icon("spinner", class = "fa-spin"), "Kontrol ediliyor...")
      } else if (isTRUE(durum)) {
        tags$span(class = "cc-status-badge cc-status-ok",
                  icon("check-circle"), "Bağlı")
      } else {
        tags$span(class = "cc-status-badge cc-status-error",
                  icon("times-circle"), "Bağlantı Yok")
      }
    })

    # --- Aktif Karakter Göstergesi ---
    output$active_character_indicator <- renderUI({
      karakter <- get_active_character()
      tags$span(
        class = "cc-character-badge",
        style = paste0("background-color: ", karakter$accent, ";"),
        karakter$display_name
      )
    })

    # --- Sunucu taraflı klasör tarayıcı ---
    rv_browser <- reactiveValues(
      current_path = NULL,
      history = list()
    )

    observeEvent(input$open_folder_browser, {
      # Mevcut çalışma dizininden başla veya ana dizinden
      baslangic <- input$workdir
      if (is.null(baslangic) || !nzchar(baslangic) || !dir.exists(baslangic)) {
        baslangic <- if (.Platform$OS.type == "windows") {
          Sys.getenv("USERPROFILE", "C:/")
        } else {
          Sys.getenv("HOME", "/")
        }
      }
      rv_browser$current_path <- normalizePath(baslangic, winslash = "/", mustWork = FALSE)

      showModal(modalDialog(
        title = tagList(icon("folder-tree"), "Klasör Seçici"),
        size = "m",
        easyClose = TRUE,
        div(
          class = "cc-folder-browser",
          # Mevcut yol göstergesi
          div(
            class = "cc-fb-path-bar",
            actionButton(ns("fb_go_up"), label = NULL, icon = icon("arrow-up"),
                        class = "btn-sm", title = "Üst dizine git"),
            tags$span(id = ns("fb_current_path"), class = "cc-fb-path-text")
          ),
          # Klasör listesi
          div(class = "cc-fb-list-container",
            uiOutput(ns("fb_folder_list"))
          )
        ),
        footer = tagList(
          actionButton(ns("fb_select"), "Bu Klasörü Seç",
                      class = "btn-primary", icon = icon("check")),
          modalButton("İptal")
        )
      ))
    })

    # Klasör tarayıcı yol göstergesini ve listeyi güncelle
    observe({
      req(rv_browser$current_path)
      yol <- rv_browser$current_path

      # Yol göstergesini güncelle
      shinyjs::runjs(sprintf(
        "var el = document.getElementById('%s'); if(el) el.textContent = '%s';",
        ns("fb_current_path"),
        gsub("\\\\", "\\\\\\\\", gsub("'", "\\\\'", yol))
      ))

      # Klasörleri listele
      output$fb_folder_list <- renderUI({
        if (!dir.exists(yol)) {
          return(tags$p(class = "cc-dir-error", paste0("Dizin bulunamadı: ", yol)))
        }
        dosyalar <- tryCatch({
          list.dirs(yol, full.names = TRUE, recursive = FALSE)
        }, error = function(e) character(0))

        if (length(dosyalar) == 0) {
          return(tags$p(class = "cc-dir-empty", "Alt klasör bulunamadı."))
        }

        # En fazla 100 klasör göster
        dosyalar <- head(dosyalar, 100)

        tags$div(
          class = "cc-fb-folder-list",
          lapply(dosyalar, function(d) {
            klasor_adi <- basename(d)
            tam_yol <- normalizePath(d, winslash = "/", mustWork = FALSE)
            tags$div(
              class = "cc-dir-item cc-dir-klasor cc-dir-clickable",
              onclick = sprintf(
                "Shiny.setInputValue('%s', '%s', {priority: 'event'});",
                ns("fb_navigate"),
                gsub("'", "\\\\'", tam_yol)
              ),
              icon("folder"),
              tags$span(class = "cc-dir-name", klasor_adi)
            )
          })
        )
      })
    })

    # Klasör tarayıcıda gezinme
    observeEvent(input$fb_navigate, {
      req(input$fb_navigate)
      yeni_yol <- input$fb_navigate
      if (dir.exists(yeni_yol)) {
        rv_browser$current_path <- normalizePath(yeni_yol, winslash = "/", mustWork = FALSE)
      }
    })

    # Üst dizine git
    observeEvent(input$fb_go_up, {
      req(rv_browser$current_path)
      ust <- dirname(rv_browser$current_path)
      if (dir.exists(ust) && ust != rv_browser$current_path) {
        rv_browser$current_path <- normalizePath(ust, winslash = "/", mustWork = FALSE)
      }
    })

    # Seçimi onayla
    observeEvent(input$fb_select, {
      req(rv_browser$current_path)
      updateTextInput(session, "workdir", value = rv_browser$current_path)
      removeModal()
    })

    # --- Model değiştiğinde oturumu sıfırla ---
    # Farklı bir modele geçildiğinde önceki oturumun bağlamı geçersiz olur.
    # Yeni model ile temiz bir oturum başlatılmalıdır.
    observeEvent(input$model, {
      if (!is.null(rv$current_model) && !identical(rv$current_model, input$model)) {
        rv$cli_session_id <- NULL
        rv$conversation_context <- list()
        log_info(paste(CLAUDE_CODE_LOG_PREFIX,
                       "Model değişti, oturum sıfırlandı. Yeni model:", input$model))
      }
      rv$current_model <- input$model
    }, ignoreInit = TRUE)

    # --- Senaryo Düğmeleri ---
    lapply(claude_code_scenarios, function(senaryo) {
      observeEvent(input[[paste0("scenario_", senaryo$id)]], {
        if (nzchar(senaryo$sablon)) {
          # textarea güncelleme (JavaScript ile)
          shinyjs::runjs(sprintf(
            "var el = document.getElementById('%s'); if(el) { el.value = %s; el.focus(); }",
            ns("prompt_input"),
            jsonlite::toJSON(senaryo$sablon, auto_unbox = TRUE)
          ))
        }
      })
    })

    # --- Dizin İçeriğini Göster (tıklanabilir klasörlerle) ---
    observe_dir_contents <- function() {
      yol <- input$workdir
      if (is.null(yol) || !nzchar(yol)) {
        output$dir_contents_ui <- renderUI({
          tags$p(class = "cc-dir-empty", "Proje dizini belirtilmedi.")
        })
        return()
      }

      icerik <- list_directory_contents(yol)

      # Mevcut dizin yolunu güncelle
      shinyjs::runjs(sprintf(
        "var el = document.getElementById('%s'); if(el) el.textContent = '%s';",
        ns("dir_current_path"),
        gsub("\\\\", "\\\\\\\\", gsub("'", "\\\\'", yol))
      ))

      output$dir_contents_ui <- renderUI({
        if (!icerik$success) {
          tags$p(class = "cc-dir-error", icerik$error)
        } else if (length(icerik$items) == 0) {
          tags$p(class = "cc-dir-empty", "Dizin boş.")
        } else {
          tags$div(
            class = "cc-dir-list",
            if (icerik$toplam > length(icerik$items)) {
              tags$small(class = "cc-dir-count",
                         paste0(icerik$toplam, " ögeden ilk ",
                                length(icerik$items), " tanesi"))
            },
            lapply(icerik$items, function(oge) {
              ikon <- if (oge$tip == "klasor") "folder" else "file"
              boyut_text <- if (!is.na(oge$boyut)) {
                if (oge$boyut < 1024) paste0(oge$boyut, " B")
                else if (oge$boyut < 1048576) paste0(round(oge$boyut / 1024, 1), " KB")
                else paste0(round(oge$boyut / 1048576, 1), " MB")
              } else ""

              # Klasörlere tıklanabilirlik ekle
              ek_sinif <- if (oge$tip == "klasor") " cc-dir-clickable" else ""
              ek_olay <- if (oge$tip == "klasor") {
                sprintf(
                  "Shiny.setInputValue('%s', '%s', {priority: 'event'});",
                  ns("dir_navigate"),
                  gsub("'", "\\\\'", oge$yol)
                )
              } else NULL

              tags$div(
                class = paste0("cc-dir-item cc-dir-", oge$tip, ek_sinif),
                onclick = ek_olay,
                icon(ikon),
                tags$span(class = "cc-dir-name", oge$ad),
                tags$span(class = "cc-dir-size", boyut_text)
              )
            })
          )
        }
      })
    }

    # Dizin gezgini: klasöre tıklama
    observeEvent(input$dir_navigate, {
      req(input$dir_navigate)
      yeni_yol <- input$dir_navigate
      if (dir.exists(yeni_yol)) {
        updateTextInput(session, "workdir",
                        value = normalizePath(yeni_yol, winslash = "/", mustWork = FALSE))
      }
    })

    # Üst dizine git düğmesi
    observeEvent(input$dir_go_up, {
      yol <- input$workdir
      if (!is.null(yol) && nzchar(yol)) {
        ust <- dirname(yol)
        if (dir.exists(ust) && ust != yol) {
          updateTextInput(session, "workdir",
                          value = normalizePath(ust, winslash = "/", mustWork = FALSE))
        }
      }
    })

    observeEvent(input$refresh_dir, {
      observe_dir_contents()
    })

    observeEvent(input$workdir, {
      # Çalışma dizini değiştiğinde oturumu sıfırla
      rv$cli_session_id <- NULL
      rv$conversation_context <- list()
      observe_dir_contents()
    }, ignoreInit = TRUE)

    # --- Çıktıyı Temizle ---
    observeEvent(input$clear_output, {
      rv$output_history <- list()
      rv$has_messages <- FALSE
      rv$conversation_context <- list()
      rv$cli_session_id <- NULL
      session$sendCustomMessage(
        type = "cc-clear-output",
        message = list(
          target = ns("output_area"),
          welcomeId = ns("welcome_screen")
        )
      )
    })

    # --- Düşünme mesajı güncelleme ---
    observeEvent(input$thinking_tick, {
      karakter <- get_active_character()
      yeni_mesaj <- get_thinking_message(karakter$id)
      session$sendCustomMessage(
        type = "cc-update-thinking-text",
        message = list(
          textId = ns("thinking_text"),
          message = yeni_mesaj
        )
      )
    })

    # --- Ana Komut Çalıştırma (Canlı Akış Destekli) ---
    observeEvent(input$run_command, {
      prompt <- NULL

      # JavaScript'ten gelen prompt değerini oku
      prompt_from_js <- input$prompt_value
      if (!is.null(prompt_from_js) && nzchar(trimws(prompt_from_js))) {
        prompt <- trimws(prompt_from_js)
      }

      # Boş kontrolü
      if (is.null(prompt) || !nzchar(prompt)) return()

      # Çift tıklama koruması
      if (isTRUE(rv$is_running)) return()
      rv$is_running <- TRUE

      # Ayarları al
      cli_yolu <- rv$cli_path_resolved
      calisma_dizini <- input$workdir
      model <- input$model
      zaman_asimi <- isolate({
        if (!is.null(settings_data) && !is.null(settings_data$claude_code_timeout)) {
          settings_data$claude_code_timeout
        } else {
          claude_code_config$timeout_seconds
        }
      })

      # CLI yolu yoksa hata ver
      if (is.null(cli_yolu)) {
        rv$is_running <- FALSE
        session$sendCustomMessage(
          type = "cc-add-message",
          message = list(
            target = ns("output_area"),
            type = "error",
            content = "Claude Code CLI bulunamadı. Lütfen npm ile kurulu olduğundan emin olun.",
            timestamp = format(Sys.time(), "%H:%M:%S"),
            welcomeId = ns("welcome_screen")
          )
        )
        return()
      }

      # Çalışma dizini yoksa geçici alan kullan
      if (is.null(calisma_dizini) || !nzchar(calisma_dizini)) {
        calisma_dizini <- get_user_workspace(current_user_id)
      }

      # Karakter bilgisini al
      karakter <- get_active_character()
      karakter_id <- karakter$id
      karakter_renk <- karakter$accent

      # Düşünme mesajını seç
      dusunme_mesaji <- get_thinking_message(karakter_id)

      # Kullanıcı adını al
      ad <- kullanici_adi()

      # Karşılama ekranını gizle, mesaj alanı aktif
      rv$has_messages <- TRUE

      # Konuşma bağlamına ekle
      rv$conversation_context <- c(rv$conversation_context, list(
        list(role = "user", content = prompt)
      ))

      # Oturum kimliğini yakala
      oturum_id <- rv$cli_session_id

      # Kullanıcı komutunu çıktıya ekle
      session$sendCustomMessage(
        type = "cc-add-message",
        message = list(
          target = ns("output_area"),
          type = "user",
          content = htmltools::htmlEscape(prompt),
          timestamp = format(Sys.time(), "%H:%M:%S"),
          senderName = ad,
          welcomeId = ns("welcome_screen")
        )
      )

      # Düşünme animasyonunu başlat
      session$sendCustomMessage(
        type = "cc-thinking-start",
        message = list(
          overlayId = ns("thinking_overlay"),
          textId = ns("thinking_text"),
          canvasId = ns("pixel_canvas"),
          statusId = ns("status_text"),
          message = dusunme_mesaji,
          characterId = karakter_id,
          accentColor = karakter_renk
        )
      )

      # Prompt giriş alanını temizle
      shinyjs::runjs(sprintf(
        "var el = document.getElementById('%s'); if(el) el.value = '';",
        ns("prompt_input")
      ))
      shinyjs::disable("run_command")
      rv$stop_requested <- FALSE
      shinyjs::runjs(sprintf(
        "document.getElementById('%s').classList.remove('cc-hidden');",
        ns("stop_command")
      ))

      # Zaman damgası (akış mesajları için)
      zaman_damgasi <- format(Sys.time(), "%H:%M:%S")

      # -----------------------------------------------------------------------
      # CANLI AKIŞ: processx süreci ana R sürecinde başlat,
      # later::later ile yoklama yaparak parçaları anlık gönder
      # -----------------------------------------------------------------------
      baslangic_zamani <- Sys.time()

      # CLI argümanlarını oluştur
      cli_args <- c(
        "--print",
        "--output-format", "json",
        "--dangerously-skip-permissions"
      )
      if (!is.null(model) && nzchar(model)) {
        cli_args <- c(cli_args, "--model", model)
      }
      if (!is.null(oturum_id) && nzchar(oturum_id)) {
        cli_args <- c(cli_args, "--resume", oturum_id)
      }
      cli_args <- c(cli_args, prompt)

      # Süreci başlat
      tryCatch({
        log_info(paste(CLAUDE_CODE_LOG_PREFIX, "Canlı akış başlatılıyor"))

        proc <- processx::process$new(
          command = cli_yolu,
          args = cli_args,
          wd = calisma_dizini,
          stdout = "|",
          stderr = "|",
          cleanup = TRUE,
          cleanup_tree = TRUE
        )

        # Süreç referansını sakla (durdurma için)
        rv$active_process <- proc

        # Metin biriktiricisi
        tum_satirlar <- character(0)

        # Yoklama fonksiyonu: süreç çalışırken tekrar tekrar çağrılır
        poll_process <- function() {
          # Durdurma isteği kontrolü
          if (isTRUE(rv$stop_requested)) {
            tryCatch(proc$kill(), error = function(e) NULL)
            finalize_streaming("Durduruldu", "stop-circle", "#FFB74D")
            return()
          }

          # Zaman aşımı kontrolü
          gecen_sure <- as.numeric(difftime(Sys.time(), baslangic_zamani, units = "secs"))
          if (gecen_sure > zaman_asimi) {
            tryCatch(proc$kill(), error = function(e) NULL)
            log_error(paste(CLAUDE_CODE_LOG_PREFIX, "Akış zaman aşımı:", zaman_asimi, "sn"))
            session$sendCustomMessage(
              type = "cc-add-message",
              message = list(
                target = ns("output_area"),
                type = "error",
                content = paste0("İşlem zaman aşımına uğradı (", zaman_asimi, " saniye)."),
                timestamp = format(Sys.time(), "%H:%M:%S"),
                welcomeId = ns("welcome_screen")
              )
            )
            finalize_streaming("Zaman Aşımı", "clock", "#FFB74D")
            return()
          }

          # stdout'tan oku
          tryCatch({
            proc$poll_io(0)  # Beklemesiz kontrol
            yeni_satirlar <- tryCatch(proc$read_output_lines(), error = function(e) character(0))

            if (length(yeni_satirlar) > 0) {
              for (satir in yeni_satirlar) {
                satir <- trimws(satir)
                if (!nzchar(satir)) next

                tum_satirlar <<- c(tum_satirlar, satir)

                # Parçayı ayrıştır ve istemciye gönder
                parca <- parse_streaming_chunk(satir)
                if (!is.null(parca)) {
                  bicimlenmis <- format_streaming_chunk_html(parca)
                  if (!is.null(bicimlenmis)) {
                    session$sendCustomMessage(
                      type = "cc-stream-chunk",
                      message = list(
                        target = ns("output_area"),
                        welcomeId = ns("welcome_screen"),
                        chunkType = bicimlenmis$tip,
                        html = bicimlenmis$html,
                        toolId = bicimlenmis$arac_id %||% "",
                        accentColor = karakter_renk,
                        characterName = karakter$display_name,
                        timestamp = zaman_damgasi
                      )
                    )
                  }
                }
              }
            }
          }, error = function(e) {
            log_warn(paste(CLAUDE_CODE_LOG_PREFIX, "Akış okuma hatası:",
                           conditionMessage(e)))
          })

          # Süreç hala çalışıyorsa tekrar yokla
          if (proc$is_alive()) {
            later::later(poll_process, delay = 0.2)
          } else {
            # Süreç bitti - kalan çıktıyı oku
            tryCatch({
              kalan <- proc$read_all_output()
              if (nzchar(kalan)) {
                kalan_satirlar <- strsplit(kalan, "\n")[[1]]
                for (satir in kalan_satirlar) {
                  satir <- trimws(satir)
                  if (!nzchar(satir)) next
                  tum_satirlar <<- c(tum_satirlar, satir)

                  parca <- parse_streaming_chunk(satir)
                  if (!is.null(parca)) {
                    bicimlenmis <- format_streaming_chunk_html(parca)
                    if (!is.null(bicimlenmis)) {
                      session$sendCustomMessage(
                        type = "cc-stream-chunk",
                        message = list(
                          target = ns("output_area"),
                          welcomeId = ns("welcome_screen"),
                          chunkType = bicimlenmis$tip,
                          html = bicimlenmis$html,
                          toolId = bicimlenmis$arac_id %||% "",
                          accentColor = karakter_renk,
                          characterName = karakter$display_name,
                          timestamp = zaman_damgasi
                        )
                      )
                    }
                  }
                }
              }
            }, error = function(e) NULL)

            # Tam çıktıyı ayrıştır
            tam_cikti <- paste(tum_satirlar, collapse = "\n")
            ayristirma <- parse_claude_code_json_output(tam_cikti)
            cikis_kodu <- proc$get_exit_status()
            sure <- round(as.numeric(difftime(Sys.time(), baslangic_zamani, units = "secs")), 1)

            if (identical(cikis_kodu, 0L)) {
              log_info(paste(CLAUDE_CODE_LOG_PREFIX, "Akış tamamlandı - Süre:", sure, "sn"))

              # Oturum kimliğini kaydet
              if (!is.null(ayristirma$session_id) && nzchar(ayristirma$session_id %||% "")) {
                rv$cli_session_id <- ayristirma$session_id
              }

              # Konuşma bağlamına ekle
              rv$conversation_context <- c(rv$conversation_context, list(
                list(role = "assistant", content = ayristirma$text_output)
              ))

              # Son içeriği HTML olarak biçimlendir
              son_icerik <- format_claude_code_output(ayristirma$text_output)

              # Akış mesajını sonlandır
              session$sendCustomMessage(
                type = "cc-stream-end",
                message = list(
                  target = ns("output_area"),
                  duration = sure,
                  finalContent = son_icerik
                )
              )

              # Sonucu sakla
              rv$last_result <- list(
                success = TRUE, output = ayristirma$text_output,
                error = "", duration = sure,
                tool_uses = ayristirma$tool_uses,
                session_id = ayristirma$session_id
              )

              finalize_streaming("Tamamlandı", "check-circle", "#81C784", sure)
            } else {
              # Hata durumu
              stderr_metin <- tryCatch(proc$read_all_error(), error = function(e) "")
              hata_mesaji <- if (nzchar(stderr_metin)) stderr_metin else tam_cikti
              temiz_log <- gsub("[{}]", "", substr(hata_mesaji, 1, 200))
              log_warn(paste(CLAUDE_CODE_LOG_PREFIX, "Akış hata kodu:", cikis_kodu,
                             "- Mesaj:", temiz_log))

              session$sendCustomMessage(
                type = "cc-stream-end",
                message = list(target = ns("output_area"))
              )

              session$sendCustomMessage(
                type = "cc-add-message",
                message = list(
                  target = ns("output_area"),
                  type = "error",
                  content = htmltools::htmlEscape(hata_mesaji),
                  timestamp = format(Sys.time(), "%H:%M:%S"),
                  welcomeId = ns("welcome_screen")
                )
              )

              finalize_streaming("Hata", "exclamation-triangle", "#E57373", sure)
            }

            # Geçmişe ekle
            rv$output_history <- c(rv$output_history, list(list(
              prompt = prompt,
              result = rv$last_result,
              timestamp = Sys.time(),
              character = karakter_id
            )))

            # Dizin içeriğini güncelle
            observe_dir_contents()
          }
        }

        # Akış sonlandırma yardımcı fonksiyonu
        finalize_streaming <- function(durum_metin, durum_ikon, durum_renk, sure = NULL) {
          rv$is_running <- FALSE
          rv$active_process <- NULL
          shinyjs::enable("run_command")
          shinyjs::runjs(sprintf(
            "document.getElementById('%s').classList.add('cc-hidden');",
            ns("stop_command")
          ))

          # Düşünme animasyonunu durdur
          session$sendCustomMessage(
            type = "cc-thinking-stop",
            message = list(
              overlayId = ns("thinking_overlay"),
              statusId = ns("status_text"),
              durationId = ns("duration_text")
            )
          )

          # Durum çubuğunu güncelle
          session$sendCustomMessage(
            type = "cc-update-status",
            message = list(
              statusId = ns("status_text"),
              durationId = ns("duration_text"),
              status = durum_metin,
              statusIcon = durum_ikon,
              statusColor = durum_renk,
              duration = if (!is.null(sure)) paste0(sure, " sn") else ""
            )
          )
        }

        # Yoklamayı başlat
        later::later(poll_process, delay = 0.2)

      }, error = function(e) {
        rv$is_running <- FALSE
        shinyjs::enable("run_command")
        shinyjs::runjs(sprintf(
          "document.getElementById('%s').classList.add('cc-hidden');",
          ns("stop_command")
        ))

        session$sendCustomMessage(
          type = "cc-thinking-stop",
          message = list(
            overlayId = ns("thinking_overlay"),
            statusId = ns("status_text"),
            durationId = ns("duration_text")
          )
        )

        hata_metni <- conditionMessage(e)
        temiz_hata <- gsub("[{}]", "", hata_metni)
        log_error(paste(CLAUDE_CODE_LOG_PREFIX, "Akış başlatma hatası:", temiz_hata))

        session$sendCustomMessage(
          type = "cc-add-message",
          message = list(
            target = ns("output_area"),
            type = "error",
            content = paste0("Beklenmeyen hata: ", htmltools::htmlEscape(hata_metni)),
            timestamp = format(Sys.time(), "%H:%M:%S"),
            welcomeId = ns("welcome_screen")
          )
        )

        session$sendCustomMessage(
          type = "cc-update-status",
          message = list(
            statusId = ns("status_text"),
            durationId = ns("duration_text"),
            status = "Hata",
            statusIcon = "exclamation-triangle",
            statusColor = "#E57373",
            duration = ""
          )
        )
      })
    })

    # --- Durdur düğmesi ---
    observeEvent(input$stop_command, {
      if (isTRUE(rv$is_running)) {
        rv$stop_requested <- TRUE

        # Aktif süreci sonlandır
        if (!is.null(rv$active_process)) {
          tryCatch({
            rv$active_process$kill()
            log_info(paste(CLAUDE_CODE_LOG_PREFIX, "Süreç kullanıcı tarafından durduruldu"))
          }, error = function(e) NULL)
          rv$active_process <- NULL
        }
      }
    })

    # --- Klavye Kısayolu: Enter ile gönderme ---
    observeEvent(input$prompt_submit_key, {
      # JavaScript tarafından tetiklenir (Ctrl+Enter veya Shift+Enter)
      if (!isTRUE(rv$is_running)) {
        shinyjs::click("run_command")
      }
    })

    invisible(NULL)
  })
}
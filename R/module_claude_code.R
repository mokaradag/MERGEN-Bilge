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
  model_degerleri <- setNames(
    sapply(katmanlar, function(k) k$deger),
    sapply(katmanlar, function(k) k$etiket)
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

            # Proje dizini giriş alanı + klasör seçim düğmesi
            div(
              class = "cc-workdir-row",
              textInput(
                ns("workdir"),
                label = NULL,
                value = claude_code_config$default_workdir,
                placeholder = "Proje klasör yolunu girin..."
              ),
              actionButton(
                ns("browse_folder"),
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

          # Retro karşılama ekranı (çıktı alanı boşken görünür)
          div(
            id = ns("welcome_screen"),
            class = "cc-welcome-screen"
            # İçerik JavaScript tarafından oluşturulur
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

          # Çıktı / Sonuç Alanı (sabit yükseklik, kaydırılabilir)
          div(
            class = "cc-output-wrapper",
            div(
              id = ns("output_area"),
              class = "cc-output-area"
              # İçerik JavaScript tarafından yönetilir
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
      dir_browse_path = NULL  # Dizin gezgini için mevcut yol
    )

    # --- Uygulama başladığında CLI yolunu otomatik tespit et ---
    observe({
      yol <- resolve_claude_cli_path(claude_code_config$cli_path)
      rv$cli_path_resolved <- yol
    }, priority = 100)

    # --- Sayfa yüklendiğinde otomatik bağlantı testi (gereksinim 15) ---
    observe({
      # Bir kerelik çalışsın
      req(is.null(rv$connection_ok))
      cli_yolu <- rv$cli_path_resolved
      if (is.null(cli_yolu)) {
        rv$connection_ok <- FALSE
        return()
      }

      model <- isolate(input$model)

      future_promise({
        test_claude_code_connection(
          cli_path = cli_yolu,
          model = if (!is.null(model) && nzchar(model)) model else NULL,
          workdir = tempdir()
        )
      }) %...>% (function(sonuc) {
        rv$connection_ok <- sonuc$success
        log_info(paste(CLAUDE_CODE_LOG_PREFIX, "Otomatik bağlantı testi:",
                       if (sonuc$success) "Başarılı" else "Başarısız"))
      }) %...!% (function(hata) {
        rv$connection_ok <- FALSE
        log_warn(paste(CLAUDE_CODE_LOG_PREFIX, "Otomatik bağlantı testi hatası:",
                       conditionMessage(hata)))
      })
    }, priority = 50)

    # --- Aktif karakter bilgisini al ---
    get_active_character <- reactive({
      karakter_id <- "mergen"
      if (!is.null(settings_data) && !is.null(settings_data$selected_character)) {
        karakter_id <- settings_data$selected_character
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

    # --- Karakter değiştiğinde temayı güncelle (gereksinim 13) ---
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

    # --- Kullanıcı adını belirle (gereksinim 7) ---
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

    # --- Klasör Seçim Diyaloğu (gereksinim 2) ---
    observeEvent(input$browse_folder, {
      mevcut_yol <- input$workdir
      if (is.null(mevcut_yol) || !nzchar(mevcut_yol)) {
        # Varsayılan başlangıç dizini
        if (.Platform$OS.type == "windows") {
          mevcut_yol <- Sys.getenv("USERPROFILE", "C:/")
        } else {
          mevcut_yol <- Sys.getenv("HOME", "/")
        }
      }

      # Dizini listele ve modalda göster
      showModal(modalDialog(
        title = tagList(icon("folder-open"), "Klasör Seç"),
        size = "m",
        easyClose = TRUE,
        div(
          class = "cc-folder-browser",
          # Mevcut yol göstergesi
          div(
            class = "cc-folder-path-bar",
            actionButton(ns("folder_go_up"), label = NULL, icon = icon("arrow-up"),
                         class = "btn-sm cc-folder-nav-btn", title = "Üst dizin"),
            tags$input(
              type = "text",
              id = ns("folder_current_path"),
              class = "cc-folder-path-input",
              value = mevcut_yol
            )
          ),
          # Dizin listesi
          uiOutput(ns("folder_browser_list"))
        ),
        footer = tagList(
          tags$button("İptal", class = "btn-modern btn-secondary", `data-dismiss` = "modal"),
          actionButton(ns("folder_select_confirm"), "Bu Klasörü Seç",
                       class = "btn-modern btn-primary", icon = icon("check"))
        )
      ))

      # Başlangıç dizinini ayarla
      rv$dir_browse_path <- mevcut_yol
    })

    # Klasör tarayıcı listesi güncelleme
    observe({
      req(rv$dir_browse_path)
      yol <- rv$dir_browse_path

      output$folder_browser_list <- renderUI({
        if (!dir.exists(yol)) {
          return(tags$p(class = "cc-dir-error", "Dizin bulunamadı."))
        }

        icerik <- list_directory_contents(yol, max_items = 50L)

        if (!icerik$success) {
          return(tags$p(class = "cc-dir-error", icerik$error))
        }

        # Sadece klasörleri göster
        klasorler <- Filter(function(x) x$tip == "klasor", icerik$items)

        if (length(klasorler) == 0) {
          return(tags$p(class = "cc-dir-empty", "Bu dizinde alt klasör yok."))
        }

        tags$div(
          class = "cc-folder-list",
          lapply(klasorler, function(k) {
            tags$div(
              class = "cc-folder-item",
              onclick = sprintf(
                "Shiny.setInputValue('%s', '%s', {priority: 'event'});",
                ns("folder_navigate"),
                gsub("'", "\\\\'", k$yol)
              ),
              icon("folder"),
              tags$span(k$ad)
            )
          })
        )
      })

      # Yol göstergesini güncelle
      shinyjs::runjs(sprintf(
        "var el = document.getElementById('%s'); if(el) el.value = '%s';",
        ns("folder_current_path"),
        gsub("\\\\", "\\\\\\\\", gsub("'", "\\\\'", yol))
      ))
    })

    # Klasöre tıklanınca gezin
    observeEvent(input$folder_navigate, {
      req(input$folder_navigate)
      yeni_yol <- input$folder_navigate
      if (dir.exists(yeni_yol)) {
        rv$dir_browse_path <- normalizePath(yeni_yol, winslash = "/", mustWork = FALSE)
      }
    })

    # Üst dizine git
    observeEvent(input$folder_go_up, {
      req(rv$dir_browse_path)
      ust <- dirname(rv$dir_browse_path)
      if (dir.exists(ust)) {
        rv$dir_browse_path <- normalizePath(ust, winslash = "/", mustWork = FALSE)
      }
    })

    # Klasör seçimini onayla
    observeEvent(input$folder_select_confirm, {
      req(rv$dir_browse_path)
      updateTextInput(session, "workdir", value = rv$dir_browse_path)
      removeModal()
    })

    # --- Senaryo Düğmeleri ---
    lapply(claude_code_scenarios, function(senaryo) {
      observeEvent(input[[paste0("scenario_", senaryo$id)]], {
        if (nzchar(senaryo$sablon)) {
          updateTextAreaInput(session, "prompt_input", value = senaryo$sablon)
        }
      })
    })

    # --- Dizin İçeriğini Göster (tıklanabilir klasörlerle - gereksinim 16) ---
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
      observe_dir_contents()
    }, ignoreInit = TRUE)

    # --- Çıktıyı Temizle ---
    observeEvent(input$clear_output, {
      rv$output_history <- list()
      rv$has_messages <- FALSE
      session$sendCustomMessage(
        type = "cc-clear-output",
        message = list(
          target = ns("output_area"),
          welcomeId = ns("welcome_screen")
        )
      )
    })

    # --- Düşünme mesajı güncelleme (gereksinim 12) ---
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

    # --- Ana Komut Çalıştırma ---
    observeEvent(input$run_command, {
      prompt <- input$prompt_input
      if (is.null(prompt) || !nzchar(trimws(prompt))) return()

      # Çift tıklama koruması
      if (isTRUE(rv$is_running)) return()
      rv$is_running <- TRUE

      # Ayarları al
      cli_yolu <- rv$cli_path_resolved
      calisma_dizini <- input$workdir
      model <- input$model
      zaman_asimi <- isolate({
        # Yapılandırma sayfasından zaman aşımı değerini al
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

      # Düşünme animasyonunu başlat (küçük, köşede)
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

      # Giriş alanını temizle ve devre dışı bırak
      updateTextAreaInput(session, "prompt_input", value = "")
      shinyjs::disable("run_command")

      # Arka planda çalıştır
      future_promise({
        run_claude_code(
          prompt = prompt,
          workdir = calisma_dizini,
          model = if (!is.null(model) && nzchar(model)) model else NULL,
          timeout_sec = zaman_asimi,
          cli_path = cli_yolu
        )
      }) %...>% (function(sonuc) {
        rv$last_result <- sonuc
        rv$is_running <- FALSE

        # Düşünme animasyonunu durdur
        session$sendCustomMessage(
          type = "cc-thinking-stop",
          message = list(
            overlayId = ns("thinking_overlay"),
            statusId = ns("status_text"),
            durationId = ns("duration_text")
          )
        )

        # Sonucu çıktı alanına ekle
        if (sonuc$success) {
          cikti_html <- format_claude_code_output(sonuc$output)
          arac_html <- format_tool_uses_html(sonuc$tool_uses)

          session$sendCustomMessage(
            type = "cc-add-message",
            message = list(
              target = ns("output_area"),
              type = "assistant",
              content = cikti_html,
              toolContent = arac_html,
              timestamp = format(Sys.time(), "%H:%M:%S"),
              duration = sonuc$duration,
              accentColor = karakter_renk,
              characterName = karakter$display_name,
              welcomeId = ns("welcome_screen")
            )
          )

          # Durum çubuğunu güncelle
          session$sendCustomMessage(
            type = "cc-update-status",
            message = list(
              statusId = ns("status_text"),
              durationId = ns("duration_text"),
              status = "Tamamlandı",
              statusIcon = "check-circle",
              statusColor = "#81C784",
              duration = paste0(sonuc$duration, " sn")
            )
          )
        } else {
          # Hata mesajı
          session$sendCustomMessage(
            type = "cc-add-message",
            message = list(
              target = ns("output_area"),
              type = "error",
              content = htmltools::htmlEscape(sonuc$error),
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
              duration = paste0(sonuc$duration, " sn")
            )
          )
        }

        # Giriş alanını ve düğmeyi tekrar etkinleştir
        shinyjs::enable("run_command")

        # Çıktı geçmişine ekle
        rv$output_history <- c(rv$output_history, list(list(
          prompt = prompt,
          result = sonuc,
          timestamp = Sys.time(),
          character = karakter_id
        )))

        # Dizin içeriğini güncelle (dosya değişmiş olabilir)
        observe_dir_contents()

      }) %...!% (function(hata) {
        rv$is_running <- FALSE
        shinyjs::enable("run_command")

        # Düşünme animasyonunu durdur
        session$sendCustomMessage(
          type = "cc-thinking-stop",
          message = list(
            overlayId = ns("thinking_overlay"),
            statusId = ns("status_text"),
            durationId = ns("duration_text")
          )
        )

        session$sendCustomMessage(
          type = "cc-add-message",
          message = list(
            target = ns("output_area"),
            type = "error",
            content = paste0("Beklenmeyen hata: ",
                             htmltools::htmlEscape(conditionMessage(hata))),
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
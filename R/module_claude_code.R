# ==============================================================================
# Dosya Yolu: R/module_claude_code.R
# Aciklama: Claude Code entegrasyon modulu. Kullanicilara web arayuzu uzerinden
#           Claude Code CLI yeteneklerini sunar. Dosya okuma/yazma, terminal
#           komutlari, arac kullanimi gibi tam ajan yetenekleri desteklenir.
#           Karakter temali 8-bit animasyonlar ve Turkce dusunme mesajlari icerir.
# ==============================================================================

# ==============================================================================
# CLAUDE CODE UI
# ==============================================================================

claudeCodeUI <- function(id) {
  ns <- NS(id)

  # Baslangicta settings.json'dan model listesini oku
  ayarlar <- read_claude_settings_json()
  model_secenekleri <- ayarlar$models
  varsayilan_model <- ayarlar$default_model

  # Model seceneklerini olustur (dropdown icin)
  if (length(model_secenekleri) > 0) {
    # Etiketli liste: "OPUS - GLM-5-FP8" gibi
    model_etiketleri <- paste0(names(model_secenekleri), " - ", unname(model_secenekleri))
    model_degerleri <- setNames(unname(model_secenekleri), model_etiketleri)
  } else {
    # settings.json bulunamadiysa veya model yoksa
    model_degerleri <- c("Varsayilan (settings.json)" = "")
    varsayilan_model <- ""
  }

  tagList(
    div(
      class = "claude-code-container",

      # --- Sayfa Basligi ---
      div(
        class = "chat-header settings-header-fixed",
        div(
          class = "chat-header-left",
          h4("Claude Code", class = "page-title"),
          tags$span(class = "cc-badge", "AJAN")
        ),
        div(
          class = "chat-header-right",
          # Durum gostergesi
          uiOutput(ns("connection_status_badge"))
        )
      ),

      # --- Ana Icerik ---
      div(
        class = "cc-main-content",

        # --- Sol Panel: Ayarlar ve Senaryolar ---
        div(
          class = "cc-sidebar-panel",

          # Baglanti Ayarlari
          div(
            class = "cc-settings-card",
            h5(class = "cc-card-title", icon("plug"), "Baglanti Ayarlari"),

            # CLI Durumu (otomatik tespit gostergesi)
            uiOutput(ns("cli_status_info")),

            # Proje Dizini
            textInput(
              ns("workdir"),
              label = "Proje Dizini",
              value = claude_code_config$default_workdir,
              placeholder = "Ornek: C:/Users/kullanici/projeler/benim-projem"
            ),
            tags$small(
              class = "cc-help-text",
              "Projenizin klasor yolunu yazin. Claude Code bu dizinde calisacak."
            ),

            # Model Secimi (dropdown)
            selectInput(
              ns("model"),
              label = "Model Secimi",
              choices = model_degerleri,
              selected = if (nzchar(varsayilan_model)) varsayilan_model else NULL
            ),

            # Zaman Asimi
            numericInput(
              ns("timeout"),
              label = "Zaman Asimi (saniye)",
              value = claude_code_config$timeout_seconds,
              min = 30,
              max = 600,
              step = 30
            ),

            # Baglanti Test Dugmesi
            div(
              class = "cc-test-row",
              actionButton(
                ns("test_connection"),
                label = tagList(icon("satellite-dish"), "Baglanti Testi"),
                class = "btn-modern btn-primary cc-test-btn"
              ),
              uiOutput(ns("test_result_ui"))
            )
          ),

          # On Tanimli Senaryolar
          div(
            class = "cc-settings-card cc-scenarios-card",
            h5(class = "cc-card-title", icon("bolt"), "Hazir Senaryolar"),
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

          # Dizin Icerik Paneli
          div(
            class = "cc-settings-card cc-dir-card",
            h5(class = "cc-card-title", icon("folder-tree"), "Dizin Icerigi"),
            actionButton(
              ns("refresh_dir"),
              label = tagList(icon("sync"), "Yenile"),
              class = "btn-sm cc-refresh-btn"
            ),
            uiOutput(ns("dir_contents_ui"))
          )
        ),

        # --- Sag Panel: Terminal / Sohbet Alani ---
        div(
          class = "cc-terminal-panel",

          # 8-bit Karakter Animasyonu ve Dusunme Mesaji
          div(
            id = ns("thinking_overlay"),
            class = "cc-thinking-overlay cc-hidden",
            div(
              class = "cc-pixel-character-container",
              # 8-bit karakter animasyonu (JavaScript ile yonetilir)
              tags$canvas(
                id = ns("pixel_canvas"),
                class = "cc-pixel-canvas",
                width = "64",
                height = "64"
              )
            ),
            div(
              id = ns("thinking_text"),
              class = "cc-thinking-text"
            )
          ),

          # Cikti / Sonuc Alani
          div(
            class = "cc-output-wrapper",
            div(
              id = ns("output_area"),
              class = "cc-output-area"
              # Icerik JavaScript tarafindan yonetilir
            )
          ),

          # Komut Giris Alani
          div(
            class = "cc-input-area",
            div(
              class = "cc-input-wrapper",
              tags$textarea(
                id = ns("prompt_input"),
                class = "cc-prompt-input",
                placeholder = "Claude Code'a bir komut yazin...",
                rows = 3
              ),
              div(
                class = "cc-input-actions",
                # Karakter Gostergesi
                uiOutput(ns("active_character_indicator")),
                # Temizle Dugmesi
                actionButton(
                  ns("clear_output"),
                  label = NULL,
                  icon = icon("eraser"),
                  class = "cc-action-btn cc-clear-btn",
                  title = "Ciktiyi Temizle"
                ),
                # Calistir Dugmesi
                actionButton(
                  ns("run_command"),
                  label = tagList(icon("play"), "Calistir"),
                  class = "cc-run-btn"
                )
              )
            ),
            # Durum Cubugu
            div(
              class = "cc-status-bar",
              span(id = ns("status_text"), class = "cc-status-text", "Hazir"),
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

claudeCodeServer <- function(id, current_user_id, settings_data = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Reaktif degerler
    rv <- reactiveValues(
      is_running = FALSE,
      output_history = list(),
      last_result = NULL,
      connection_ok = NULL,
      cli_path_resolved = NULL
    )

    # --- Uygulama basladiginda CLI yolunu otomatik tespit et ---
    observe({
      yol <- resolve_claude_cli_path(claude_code_config$cli_path)
      rv$cli_path_resolved <- yol
    }, priority = 100)

    # --- CLI Durum Bilgisi ---
    output$cli_status_info <- renderUI({
      yol <- rv$cli_path_resolved

      if (!is.null(yol)) {
        tags$div(
          class = "cc-cli-status cc-cli-found",
          icon("check-circle"),
          tags$span("CLI bulundu:"),
          tags$code(yol)
        )
      } else {
        tags$div(
          class = "cc-cli-status cc-cli-missing",
          icon("exclamation-triangle"),
          tags$span("CLI otomatik tespit edilemedi."),
          tags$br(),
          tags$small("npm ile Claude Code kurulu oldugundan emin olun.")
        )
      }
    })

    # --- Aktif karakter bilgisini al ---
    get_active_character <- reactive({
      # settings_data icindeki dogru alan adi: selected_character
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

    # --- Baglanti Durumu Rozeti ---
    output$connection_status_badge <- renderUI({
      durum <- rv$connection_ok
      if (is.null(durum)) {
        tags$span(class = "cc-status-badge cc-status-unknown",
                  icon("question-circle"), "Kontrol Edilmedi")
      } else if (isTRUE(durum)) {
        tags$span(class = "cc-status-badge cc-status-ok",
                  icon("check-circle"), "Bagli")
      } else {
        tags$span(class = "cc-status-badge cc-status-error",
                  icon("times-circle"), "Baglanti Yok")
      }
    })

    # --- Aktif Karakter Gostergesi ---
    output$active_character_indicator <- renderUI({
      karakter <- get_active_character()
      tags$span(
        class = "cc-character-badge",
        style = paste0("background-color: ", karakter$accent, ";"),
        karakter$display_name
      )
    })

    # --- Baglanti Testi ---
    observeEvent(input$test_connection, {
      cli_yolu <- rv$cli_path_resolved
      model <- input$model

      # UI geri bildirimini goster
      shinyjs::disable("test_connection")

      output$test_result_ui <- renderUI({
        tags$span(class = "cc-test-loading", icon("spinner", class = "fa-spin"),
                  "Test ediliyor...")
      })

      # Arka planda test et
      future_promise({
        test_claude_code_connection(
          cli_path = cli_yolu,
          model = if (!is.null(model) && nzchar(model)) model else NULL,
          workdir = tempdir()
        )
      }) %...>% (function(sonuc) {
        rv$connection_ok <- sonuc$success

        output$test_result_ui <- renderUI({
          if (sonuc$success) {
            tags$div(
              class = "cc-test-success",
              icon("check-circle"),
              tags$span(sonuc$message),
              tags$small(sonuc$details)
            )
          } else {
            tags$div(
              class = "cc-test-error",
              icon("exclamation-triangle"),
              tags$span(sonuc$message),
              tags$small(sonuc$details)
            )
          }
        })
        shinyjs::enable("test_connection")
      }) %...!% (function(hata) {
        output$test_result_ui <- renderUI({
          tags$div(
            class = "cc-test-error",
            icon("exclamation-triangle"),
            tags$span("Test sirasinda beklenmeyen hata olustu."),
            tags$small(conditionMessage(hata))
          )
        })
        shinyjs::enable("test_connection")
      })
    })

    # --- Senaryo Dugmeleri ---
    lapply(claude_code_scenarios, function(senaryo) {
      observeEvent(input[[paste0("scenario_", senaryo$id)]], {
        if (nzchar(senaryo$sablon)) {
          updateTextAreaInput(session, "prompt_input", value = senaryo$sablon)
        }
      })
    })

    # --- Dizin Icerigini Goster ---
    observe_dir_contents <- function() {
      yol <- input$workdir
      if (is.null(yol) || !nzchar(yol)) {
        output$dir_contents_ui <- renderUI({
          tags$p(class = "cc-dir-empty", "Proje dizini belirtilmedi.")
        })
        return()
      }

      icerik <- list_directory_contents(yol)

      output$dir_contents_ui <- renderUI({
        if (!icerik$success) {
          tags$p(class = "cc-dir-error", icerik$error)
        } else if (length(icerik$items) == 0) {
          tags$p(class = "cc-dir-empty", "Dizin bos.")
        } else {
          tags$div(
            class = "cc-dir-list",
            if (icerik$toplam > length(icerik$items)) {
              tags$small(class = "cc-dir-count",
                         paste0(icerik$toplam, " ogeden ilk ",
                                length(icerik$items), " tanesi"))
            },
            lapply(icerik$items, function(oge) {
              ikon <- if (oge$tip == "klasor") "folder" else "file"
              boyut_text <- if (!is.na(oge$boyut)) {
                if (oge$boyut < 1024) paste0(oge$boyut, " B")
                else if (oge$boyut < 1048576) paste0(round(oge$boyut / 1024, 1), " KB")
                else paste0(round(oge$boyut / 1048576, 1), " MB")
              } else ""

              tags$div(
                class = paste0("cc-dir-item cc-dir-", oge$tip),
                icon(ikon),
                tags$span(class = "cc-dir-name", oge$ad),
                tags$span(class = "cc-dir-size", boyut_text)
              )
            })
          )
        }
      })
    }

    observeEvent(input$refresh_dir, {
      observe_dir_contents()
    })

    observeEvent(input$workdir, {
      observe_dir_contents()
    }, ignoreInit = TRUE)

    # --- Ciktiyi Temizle ---
    observeEvent(input$clear_output, {
      rv$output_history <- list()
      session$sendCustomMessage(
        type = "cc-clear-output",
        message = list(target = ns("output_area"))
      )
    })

    # --- Ana Komut Calistirma ---
    observeEvent(input$run_command, {
      prompt <- input$prompt_input
      if (is.null(prompt) || !nzchar(trimws(prompt))) return()

      # Cift tiklama korumasi
      if (isTRUE(rv$is_running)) return()
      rv$is_running <- TRUE

      # Ayarlari al
      cli_yolu <- rv$cli_path_resolved
      calisma_dizini <- input$workdir
      model <- input$model
      zaman_asimi <- input$timeout %||% 300L

      # CLI yolu yoksa hata ver
      if (is.null(cli_yolu)) {
        rv$is_running <- FALSE
        session$sendCustomMessage(
          type = "cc-add-message",
          message = list(
            target = ns("output_area"),
            type = "error",
            content = "Claude Code CLI bulunamadi. Lutfen npm ile kurulu oldugundan emin olun.",
            timestamp = format(Sys.time(), "%H:%M:%S")
          )
        )
        return()
      }

      # Calisma dizini yoksa gecici alan kullan
      if (is.null(calisma_dizini) || !nzchar(calisma_dizini)) {
        calisma_dizini <- get_user_workspace(current_user_id)
      }

      # Karakter bilgisini al
      karakter <- get_active_character()
      karakter_id <- karakter$id
      karakter_renk <- karakter$accent

      # Dusunme mesajini sec
      dusunme_mesaji <- get_thinking_message(karakter_id)

      # Kullanici komutunu ciktiya ekle
      session$sendCustomMessage(
        type = "cc-add-message",
        message = list(
          target = ns("output_area"),
          type = "user",
          content = htmltools::htmlEscape(prompt),
          timestamp = format(Sys.time(), "%H:%M:%S")
        )
      )

      # Dusunme animasyonunu baslat
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

      # Giris alanini temizle ve devre disi birak
      updateTextAreaInput(session, "prompt_input", value = "")
      shinyjs::disable("run_command")

      # Arka planda calistir
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

        # Dusunme animasyonunu durdur
        session$sendCustomMessage(
          type = "cc-thinking-stop",
          message = list(
            overlayId = ns("thinking_overlay"),
            statusId = ns("status_text"),
            durationId = ns("duration_text")
          )
        )

        # Sonucu cikti alanina ekle
        if (sonuc$success) {
          cikti_html <- format_claude_code_output(sonuc$output)

          session$sendCustomMessage(
            type = "cc-add-message",
            message = list(
              target = ns("output_area"),
              type = "assistant",
              content = cikti_html,
              timestamp = format(Sys.time(), "%H:%M:%S"),
              duration = sonuc$duration,
              accentColor = karakter_renk,
              characterName = karakter$display_name
            )
          )

          # Durum cubugunu guncelle
          session$sendCustomMessage(
            type = "cc-update-status",
            message = list(
              statusId = ns("status_text"),
              durationId = ns("duration_text"),
              status = "Tamamlandi",
              duration = paste0(sonuc$duration, " sn")
            )
          )
        } else {
          # Hata mesaji
          session$sendCustomMessage(
            type = "cc-add-message",
            message = list(
              target = ns("output_area"),
              type = "error",
              content = htmltools::htmlEscape(sonuc$error),
              timestamp = format(Sys.time(), "%H:%M:%S")
            )
          )

          session$sendCustomMessage(
            type = "cc-update-status",
            message = list(
              statusId = ns("status_text"),
              durationId = ns("duration_text"),
              status = "Hata",
              duration = paste0(sonuc$duration, " sn")
            )
          )
        }

        # Giris alanini ve dugmeyi tekrar etkinlestir
        shinyjs::enable("run_command")

        # Cikti gecmisine ekle
        rv$output_history <- c(rv$output_history, list(list(
          prompt = prompt,
          result = sonuc,
          timestamp = Sys.time(),
          character = karakter_id
        )))

        # Dizin icerigini guncelle (dosya degismis olabilir)
        observe_dir_contents()

      }) %...!% (function(hata) {
        rv$is_running <- FALSE
        shinyjs::enable("run_command")

        # Dusunme animasyonunu durdur
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
            timestamp = format(Sys.time(), "%H:%M:%S")
          )
        )

        session$sendCustomMessage(
          type = "cc-update-status",
          message = list(
            statusId = ns("status_text"),
            durationId = ns("duration_text"),
            status = "Hata",
            duration = ""
          )
        )
      })
    })

    # --- Klavye Kisayolu: Enter ile gonderme ---
    observeEvent(input$prompt_submit_key, {
      # JavaScript tarafindan tetiklenir (Ctrl+Enter veya Shift+Enter)
      if (!isTRUE(rv$is_running)) {
        shinyjs::click("run_command")
      }
    })

    invisible(NULL)
  })
}

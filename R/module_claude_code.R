# ==============================================================================
# Dosya Yolu: R/module_claude_code.R
# Açıklama: Claude Code entegrasyon modülü. Kullanıcılara web arayüzü üzerinden
#           Claude Code CLI yeteneklerini sunar. Dosya okuma/yazma, terminal
#           komutları, araç kullanımı gibi tam ajan yetenekleri desteklenir.
#           Karakter temalı 8-bit animasyonlar ve Türkçe düşünme mesajları içerir.
# ==============================================================================

# ==============================================================================
# CLAUDE CODE UI
# ==============================================================================

claudeCodeUI <- function(id) {
  ns <- NS(id)

  # Başlangıçta settings.json'dan model listesini oku
  ayarlar <- read_claude_settings_json()
  model_secenekleri <- ayarlar$models
  varsayilan_model <- ayarlar$default_model

  # Model seçeneklerini oluştur (dropdown için)
  if (length(model_secenekleri) > 0) {
    # Etiketli liste: "OPUS - GLM-5-FP8" gibi
    model_etiketleri <- paste0(names(model_secenekleri), " - ", unname(model_secenekleri))
    model_degerleri <- setNames(unname(model_secenekleri), model_etiketleri)
  } else {
    # settings.json bulunamadıysa veya model yoksa
    model_degerleri <- c("Varsayılan (settings.json)" = "")
    varsayilan_model <- ""
  }

  tagList(
    div(
      class = "claude-code-container",

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
          # Durum göstergesi
          uiOutput(ns("connection_status_badge"))
        )
      ),

      # --- Ana İçerik ---
      div(
        class = "cc-main-content",

        # --- Sol Panel: Ayarlar ve Senaryolar ---
        div(
          class = "cc-sidebar-panel",

          # Bağlantı Ayarları
          div(
            class = "cc-settings-card",
            h5(class = "cc-card-title", icon("plug"), "Bağlantı Ayarları"),

            # CLI Durumu (otomatik tespit göstergesi)
            uiOutput(ns("cli_status_info")),

            # Proje Dizini
            textInput(
              ns("workdir"),
              label = "Proje Dizini",
              value = claude_code_config$default_workdir,
              placeholder = "Örnek: C:/Users/kullanıcı/projeler/benim-projem"
            ),
            tags$small(
              class = "cc-help-text",
              "Projenizin klasör yolunu yazın. Claude Code bu dizinde çalışacak."
            ),

            # Model Seçimi (dropdown)
            selectInput(
              ns("model"),
              label = "Model Seçimi",
              choices = model_degerleri,
              selected = if (nzchar(varsayilan_model)) varsayilan_model else NULL
            ),

            # Zaman Aşımı
            numericInput(
              ns("timeout"),
              label = "Zaman Aşımı (saniye)",
              value = claude_code_config$timeout_seconds,
              min = 30,
              max = 600,
              step = 30
            ),

            # Bağlantı Test Düğmesi
            div(
              class = "cc-test-row",
              actionButton(
                ns("test_connection"),
                label = tagList(icon("satellite-dish"), "Bağlantı Testi"),
                class = "btn-modern btn-primary cc-test-btn"
              ),
              uiOutput(ns("test_result_ui"))
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
            actionButton(
              ns("refresh_dir"),
              label = tagList(icon("sync"), "Yenile"),
              class = "btn-sm cc-refresh-btn"
            ),
            uiOutput(ns("dir_contents_ui"))
          )
        ),

        # --- Sağ Panel: Terminal / Sohbet Alanı ---
        div(
          class = "cc-terminal-panel",

          # 8-bit Karakter Animasyonu ve Düşünme Mesajı
          div(
            id = ns("thinking_overlay"),
            class = "cc-thinking-overlay cc-hidden",
            div(
              class = "cc-pixel-character-container",
              # 8-bit karakter animasyonu (JavaScript ile yönetilir)
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

          # Çıktı / Sonuç Alanı
          div(
            class = "cc-output-wrapper",
            div(
              id = ns("output_area"),
              class = "cc-output-area"
              # İçerik JavaScript tarafından yönetilir
            )
          ),

          # Komut Giriş Alanı
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
                # Temizle Dugmesi
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
            # Durum Cubugu
            div(
              class = "cc-status-bar",
              span(id = ns("status_text"), class = "cc-status-text", "Hazır"),
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
          tags$small("npm ile Claude Code kurulu olduğundan emin olun.")
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

    # --- Bağlantı Durumu Rozeti ---
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

    # --- Bağlantı Testi ---
    observeEvent(input$test_connection, {
      cli_yolu <- rv$cli_path_resolved
      model <- input$model

      # UI geri bildirimini göster
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
            tags$span("Test sırasında beklenmeyen hata oluştu."),
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

    # --- Dizin İçeriğini Göster ---
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

    # --- Çıktıyı Temizle ---
    observeEvent(input$clear_output, {
      rv$output_history <- list()
      session$sendCustomMessage(
        type = "cc-clear-output",
        message = list(target = ns("output_area"))
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
      zaman_asimi <- input$timeout %||% 300L

      # CLI yolu yoksa hata ver
      if (is.null(cli_yolu)) {
        rv$is_running <- FALSE
        session$sendCustomMessage(
          type = "cc-add-message",
          message = list(
            target = ns("output_area"),
            type = "error",
            content = "Claude Code CLI bulunamadı. Lütfen npm ile kurulu olduğundan emin olun.",
            timestamp = format(Sys.time(), "%H:%M:%S")
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

      # Kullanıcı komutunu çıktıya ekle
      session$sendCustomMessage(
        type = "cc-add-message",
        message = list(
          target = ns("output_area"),
          type = "user",
          content = htmltools::htmlEscape(prompt),
          timestamp = format(Sys.time(), "%H:%M:%S")
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

          # Durum çubuğunu güncelle
          session$sendCustomMessage(
            type = "cc-update-status",
            message = list(
              statusId = ns("status_text"),
              durationId = ns("duration_text"),
              status = "Tamamlandı",
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

    # --- Klavye Kısayolu: Enter ile gönderme ---
    observeEvent(input$prompt_submit_key, {
      # JavaScript tarafindan tetiklenir (Ctrl+Enter veya Shift+Enter)
      if (!isTRUE(rv$is_running)) {
        shinyjs::click("run_command")
      }
    })

    invisible(NULL)
  })
}

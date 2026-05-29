# R/module_settings_yapilandirma.R
# Dosya Yolu: R/module_settings_yapilandirma.R
# Açıklama: Ayarlar sayfasının "Yapılandırma" alt sekmesi sunucu mantığı.
#            UI tanımı R/module_settings_yapilandirma_ui.R içinde tutulur.
#            Bu dosya geçici ayar state'i, kaydet/sıfırla tetikleri ve runtime
#            çıktılarını yönetir.

#' Yapılandırma Alt Sekmesi UI
#'
#' @param id Modül ad alanı kimliği
#' @return Yapılandırma sekmesi için UI tanımı
settingsYapilandirmaUI <- function(id) {
  if (!exists("settingsYapilandirmaUIImpl", mode = "function", inherits = TRUE)) {
    stop(
      "settingsYapilandirmaUIImpl yüklenmedi; R/module_settings_yapilandirma_ui.R global.R içinde önce source edilmelidir.",
      call. = FALSE
    )
  }

  settingsYapilandirmaUIImpl(id)
}

#' Yapılandırma Alt Sekmesi Sunucu
#'
#' @param id Modül ad alanı kimliği
#' @param settings Merkezi ayarlar reaktif değerleri (paylaşımlı)
#' @param parent_session Üst oturum nesnesi
#' @return Koordinatörün kullanacağı reaktif değerleri içeren liste
settingsYapilandirmaServer <- function(id, settings, parent_session = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Kaydet/Sıfırla tetikleyicileri (koordinatör tarafından dinlenir)
    save_trigger <- reactiveVal(0)
    reset_trigger <- reactiveVal(0)

    observeEvent(input$save_settings, {
      save_trigger(isolate(save_trigger()) + 1)
    }, ignoreInit = TRUE)

    observeEvent(input$reset_settings, {
      reset_trigger(isolate(reset_trigger()) + 1)
    }, ignoreInit = TRUE)

    # Model açıklaması artık JS tarafından yönetiliyor (settings_model_info.js)
    # Eski renderUI kaldırıldı; bilgi paneli istemci tarafında güncellenir.

    # Geçici değişkenler (kaydet butonuna basılana kadar uygulanmaz)
    temp_model_selection <- reactiveVal(api_config$local_models[1])
    temp_image_size <- reactiveVal("1024x1024")
    temp_image_quality_hd <- reactiveVal(FALSE)
    temp_summary_detail_level <- reactiveVal("standard")
    temp_summary_focus_mode <- reactiveVal("general")
    temp_analysis_deep_thinking <- reactiveVal(FALSE)
    temp_analysis_detail_level <- reactiveVal("standart")

    # Model seçimi geçici değişken
    observeEvent(input$model_selection, {
      temp_model_selection(input$model_selection)
    }, ignoreInit = TRUE)

    # Ana Söyleşi'den model değiştirilirse Yapılandırma'yı da güncelle
    observeEvent(settings$model_selection, {
      req(settings$model_selection)
      if (settings$model_selection != temp_model_selection()) {
        temp_model_selection(settings$model_selection)
        updateSelectInput(session, "model_selection", selected = settings$model_selection)
      }
    })

    # API Anahtarı güncelleme modalı
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
        return()
      }
      if (!isTRUE(vres$valid)) {
        showToast(session, paste("Anahtar doğrulanamadı (kaydedilmedi):", vres$message %||% "Doğrulama başarısız."), "error")
        return()
      }

      # Kaydet + oturuma yaz
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
          success_msg <- paste("API anahtarı güncellendi \U2014", success_msg)
        }
        showToast(session, success_msg, "success")
      }, error = function(e) {
        showToast(session, paste("API anahtarı kaydedilemedi:", conditionMessage(e)), "error")
      })
    }, ignoreInit = TRUE)

    # Müzik ayarları observer'ları
    # Checkbox değişikliği müziği hemen başlatmaz/durdurmaz.
    # Müzik durumu yalnızca "Ayarları Kaydet" butonuna basıldığında uygulanır.
    # Bu sayede yarış durumları ve üst üste çalma engellenir.
    observeEvent(input$enable_background_music, {
      cat(sprintf("[MUSIC] Checkbox değişti: %s (kaydedilmeden uygulanmayacak)\n", isTRUE(input$enable_background_music)))
    }, ignoreInit = TRUE)

    observeEvent(input$music_volume, {
      settings$music_volume <- input$music_volume
      session$sendCustomMessage("setMusicVolume", input$music_volume)
    }, ignoreInit = TRUE)

    # Giriş animasyonu ayarı
    observeEvent(input$show_intro_animation, {
      settings$show_intro_animation <- isTRUE(input$show_intro_animation)
      shinyjs::runjs(sprintf(
        "try { var s = JSON.parse(localStorage.getItem('mergen_settings') || '{}'); s.skip_intro = %s; localStorage.setItem('mergen_settings', JSON.stringify(s)); } catch(e) {}",
        tolower(as.character(!isTRUE(input$show_intro_animation)))
      ))
    }, ignoreInit = TRUE)

    # Görsel ayarları değişiklik observer'ları - sadece geçici değişkenleri güncelle
    observeEvent(input$image_size, {
      temp_image_size(input$image_size)
    }, ignoreInit = TRUE)

    observeEvent(input$image_quality_hd, {
      temp_image_quality_hd(isTRUE(input$image_quality_hd))
    }, ignoreInit = TRUE)

    # Özetleme ayarları değişiklik observer'ları
    observeEvent(input$summary_detail_level, {
      temp_summary_detail_level(input$summary_detail_level)
    }, ignoreInit = TRUE)

    observeEvent(input$summary_focus_mode, {
      temp_summary_focus_mode(input$summary_focus_mode)
    }, ignoreInit = TRUE)

    # Analiz ayarları değişiklik observer'ları
    observeEvent(input$analysis_deep_thinking, {
      temp_analysis_deep_thinking(isTRUE(input$analysis_deep_thinking))
    }, ignoreInit = TRUE)

    observeEvent(input$analysis_detail_level, {
      temp_analysis_detail_level(input$analysis_detail_level)
    }, ignoreInit = TRUE)

    # Excel/Kod Derin Düşünme observer'ları, sohbet ekranındaki input'lar
    # üst Shiny oturumuna ait olduğu için R/server_observers_settings.R
    # içinde, normal chat_* dinleyicileri ile birlikte tanımlıdır.

    # Ana Söyleşi'den gelen değişiklikleri Yapılandırma sayfasına yansıt
    observeEvent(settings$image_size, {
      current_temp <- temp_image_size()
      if (!identical(settings$image_size, current_temp)) {
        temp_image_size(settings$image_size)
        updateSelectInput(session, "image_size", selected = settings$image_size)
      }
    }, ignoreInit = TRUE)

    observeEvent(settings$image_quality_hd, {
      current_temp <- temp_image_quality_hd()
      if (!identical(settings$image_quality_hd, current_temp)) {
        temp_image_quality_hd(settings$image_quality_hd)
        if (isTRUE(settings$image_quality_hd)) {
          shinyjs::runjs(sprintf("$('#%s').prop('checked', true);", ns("image_quality_hd")))
        } else {
          shinyjs::runjs(sprintf("$('#%s').prop('checked', false);", ns("image_quality_hd")))
        }
      }
    }, ignoreInit = TRUE)

    observeEvent(settings$summary_detail_level, {
      current_temp <- temp_summary_detail_level()
      if (!identical(settings$summary_detail_level, current_temp)) {
        temp_summary_detail_level(settings$summary_detail_level)
        updateSelectInput(session, "summary_detail_level", selected = settings$summary_detail_level)
      }
    }, ignoreInit = TRUE)

    observeEvent(settings$summary_focus_mode, {
      current_temp <- temp_summary_focus_mode()
      if (!identical(settings$summary_focus_mode, current_temp)) {
        temp_summary_focus_mode(settings$summary_focus_mode)
        updateSelectInput(session, "summary_focus_mode", selected = settings$summary_focus_mode)
      }
    }, ignoreInit = TRUE)

    observeEvent(settings$analysis_deep_thinking, {
      current_temp <- temp_analysis_deep_thinking()
      if (!identical(settings$analysis_deep_thinking, current_temp)) {
        temp_analysis_deep_thinking(settings$analysis_deep_thinking)
        if (isTRUE(settings$analysis_deep_thinking)) {
          shinyjs::runjs(sprintf("$('#%s').prop('checked', true);", ns("analysis_deep_thinking")))
        } else {
          shinyjs::runjs(sprintf("$('#%s').prop('checked', false);", ns("analysis_deep_thinking")))
        }
      }
    }, ignoreInit = TRUE)

    observeEvent(settings$analysis_detail_level, {
      current_temp <- temp_analysis_detail_level()
      if (!identical(settings$analysis_detail_level, current_temp)) {
        temp_analysis_detail_level(settings$analysis_detail_level)
        updateSelectInput(session, "analysis_detail_level", selected = settings$analysis_detail_level)
      }
    }, ignoreInit = TRUE)

    # Arayüz ayarları - anlık güncelleme
    observeEvent(input$font_size,               { settings$font_size               <- input$font_size })
    observeEvent(input$enable_animations,       { settings$enable_animations       <- input$enable_animations })
    observeEvent(input$enable_timestamps,       { settings$enable_timestamps       <- input$enable_timestamps })
    observeEvent(input$enable_typing_indicator, { settings$enable_typing_indicator <- input$enable_typing_indicator })
    observeEvent(input$enable_streaming,        { settings$enable_streaming        <- input$enable_streaming })
    observeEvent(input$enable_widescreen,       { settings$enable_widescreen       <- input$enable_widescreen })
    observeEvent(input$enable_tts_audio,        { settings$enable_tts_audio        <- isTRUE(input$enable_tts_audio) })
    observeEvent(input$enable_ai_expert,        { settings$enable_ai_expert        <- isTRUE(input$enable_ai_expert) })
    observeEvent(input$enable_followups,        { settings$enable_followups        <- isTRUE(input$enable_followups) })

    # Araç arka plan animasyonları: anlık güncelleme + istemciye uygula.
    # Kullanıcı checkbox'ı değiştirdiğinde sohbet ekranındaki heptagon ve
    # parçacık katmanı kayıt aşamasını beklemeden açılır/kapatılır.
    observeEvent(input$enable_tool_backgrounds, {
      flag <- mb_tool_bg_coerce_enabled(input$enable_tool_backgrounds)
      settings$enable_tool_backgrounds <- flag
      mb_tool_bg_apply_to_client(session, flag)
    }, ignoreInit = TRUE)

    # AI Uzman konuşma ayarları - anlık güncelleme
    observeEvent(input$ai_expert_talk_length,   { settings$ai_expert_talk_length   <- input$ai_expert_talk_length })
    observeEvent(input$ai_expert_talk_frequency, { settings$ai_expert_talk_frequency <- input$ai_expert_talk_frequency })
    observeEvent(input$ai_expert_talk_style,    { settings$ai_expert_talk_style    <- input$ai_expert_talk_style })

    # Analiz araçları - karşılıklı dışlama mantığı
    ANALYSIS_TOOLS <- c(
      "enable_rdata_tools",
      "enable_mcp_tools",
      "enable_summarization_tools",
      "enable_coding_tools",
      "enable_process_tools",
      "enable_app_expert_tools",
      "enable_image_tools"
    )

    lapply(ANALYSIS_TOOLS, function(tool_name) {
      observeEvent(input[[tool_name]], {
        settings[[tool_name]] <- isTRUE(input[[tool_name]])

        if (isTRUE(input[[tool_name]])) {
          # Diğer araçları devre dışı bırak
          other_tools <- setdiff(ANALYSIS_TOOLS, tool_name)
          for (other in other_tools) {
            if (isTRUE(input[[other]])) {
              updateCheckboxInput(session, other, value = FALSE)
              settings[[other]] <- FALSE
            }
          }

          # Aktif araca bağlı modeli merkezi kayıttan çöz ve uygula
          resolved_tool_model <- resolve_tool_model_for_flag(
            tool_name,
            fallback_model = isolate(settings$model_selection)
          )

          if (!is.null(resolved_tool_model) && nzchar(resolved_tool_model)) {
            settings$model_selection <- resolved_tool_model
            temp_model_selection(resolved_tool_model)
            updateSelectInput(session, "model_selection", selected = resolved_tool_model)
            session$sendCustomMessage("saveSettings", list(model_selection = resolved_tool_model))
          }

          # Süreç / Uygulama Uzmanı gibi sohbet paneli OLMAYAN araçlar için model
          # seçim kilidi sunucudan bildirilir; panelli araçlar (Görsel, Özetleme,
          # Analiz, Excel, Kod) DOM tespitiyle kilitlendiği için burada serbest
          # bırakılır (tools_model_lock.js).
          if (tool_name %in% c("enable_process_tools", "enable_app_expert_tools")) {
            lock_cfg <- get_tool_mode_config(tool_name, by = "setting_flag")
            session$sendCustomMessage("setToolModelLock", list(
              active = TRUE,
              label = lock_cfg$title %||% "Bu araç"
            ))
          } else {
            session$sendCustomMessage("setToolModelLock", list(active = FALSE))
          }

          # Görsel Uzmanı aktifleştirildiğinde otomatik model ayarla
          if (tool_name == "enable_image_tools") {
            image_model <- Sys.getenv("IMAGE_GEN_MODEL", "dall-e-3")
            settings$model_selection <- image_model
            temp_model_selection(image_model)
            session$sendCustomMessage("toggleImageMode", list(active = TRUE))
            session$sendCustomMessage("toggleSummaryMode", list(active = FALSE))
            session$sendCustomMessage("toggleAnalysisMode", list(active = FALSE))
          }

          # Dosya Özetleme aktifleştirildiğinde kontrolleri göster
          if (tool_name == "enable_summarization_tools") {
            session$sendCustomMessage("toggleSummaryMode", list(active = TRUE))
            session$sendCustomMessage("toggleImageMode", list(active = FALSE))
            session$sendCustomMessage("toggleAnalysisMode", list(active = FALSE))
          }

          # Proje ve Kaynak Analizi aktifleştirildiğinde kontrolleri göster
          if (tool_name == "enable_rdata_tools") {
            session$sendCustomMessage("toggleAnalysisMode", list(active = TRUE))
            session$sendCustomMessage("toggleImageMode", list(active = FALSE))
            session$sendCustomMessage("toggleSummaryMode", list(active = FALSE))
            session$sendCustomMessage("syncAnalysisSettingsToChat", list(
              deep_thinking = isTRUE(settings$analysis_deep_thinking),
              detail_level = settings$analysis_detail_level %||% "standart"
            ))
          }

          # Excel Analizi aktifleştirildiğinde sohbet kontrolleri (Derin Düşünme + seviye)
          if (tool_name == "enable_mcp_tools") {
            session$sendCustomMessage("toggleExcelMode", list(active = TRUE))
            session$sendCustomMessage("toggleCodingMode", list(active = FALSE))
            session$sendCustomMessage("syncExcelDeepThinkingToChat", list(
              deep_thinking = isTRUE(settings$excel_deep_thinking),
              level = settings$excel_deep_level %||% "low"
            ))
          }

          # Kod Uzmanı aktifleştirildiğinde sohbet kontrolleri
          if (tool_name == "enable_coding_tools") {
            session$sendCustomMessage("toggleCodingMode", list(active = TRUE))
            session$sendCustomMessage("toggleExcelMode", list(active = FALSE))
            session$sendCustomMessage("syncCodingDeepThinkingToChat", list(
              deep_thinking = isTRUE(settings$coding_deep_thinking),
              level = settings$coding_deep_level %||% "low"
            ))
          }

          # Diğer araçlar aktifken kontrolleri gizle
          if (!tool_name %in% c("enable_rdata_tools", "enable_image_tools", "enable_summarization_tools", "enable_mcp_tools", "enable_coding_tools")) {
            session$sendCustomMessage("toggleAnalysisMode", list(active = FALSE))
            session$sendCustomMessage("toggleImageMode", list(active = FALSE))
            session$sendCustomMessage("toggleSummaryMode", list(active = FALSE))
            session$sendCustomMessage("toggleExcelMode", list(active = FALSE))
            session$sendCustomMessage("toggleCodingMode", list(active = FALSE))
          } else if (tool_name %in% c("enable_rdata_tools", "enable_image_tools", "enable_summarization_tools")) {
            # Bu üç araç aktifken Excel/Kod kontrolleri kapanır
            session$sendCustomMessage("toggleExcelMode", list(active = FALSE))
            session$sendCustomMessage("toggleCodingMode", list(active = FALSE))
          }
        } else {
          # Görsel Uzmanı devre dışı bırakıldığında varsayılan modele dön
          if (tool_name == "enable_image_tools") {
            session$sendCustomMessage("toggleImageMode", list(active = FALSE))
          }

          if (tool_name == "enable_summarization_tools") {
            session$sendCustomMessage("toggleSummaryMode", list(active = FALSE))
          }

          if (tool_name == "enable_rdata_tools") {
            session$sendCustomMessage("toggleAnalysisMode", list(active = FALSE))
          }

          if (tool_name == "enable_mcp_tools") {
            session$sendCustomMessage("toggleExcelMode", list(active = FALSE))
          }

          if (tool_name == "enable_coding_tools") {
            session$sendCustomMessage("toggleCodingMode", list(active = FALSE))
          }

          # Süreç/Uygulama Uzmanı pasifleştirildiğinde model seçim kilidini serbest bırak.
          if (tool_name %in% c("enable_process_tools", "enable_app_expert_tools")) {
            session$sendCustomMessage("setToolModelLock", list(active = FALSE))
          }
        }
      }, ignoreInit = TRUE)
    })

    # --- Claude Code Yapılandırma Kartı ---

    # CLI durumunu göster
    output$cc_cli_status_info <- renderUI({
      yol <- resolve_claude_cli_path(claude_code_config$cli_path)

      if (!is.null(yol)) {
        tags$div(
          style = "padding: 8px 10px; border-radius: 8px; font-size: 12px; background: rgba(76,175,80,0.1); color: #81C784; border: 1px solid rgba(76,175,80,0.2);",
          icon("check-circle"),
          tags$span("CLI bulundu:"),
          tags$br(),
          tags$code(style = "font-size: 11px; word-break: break-all; background: rgba(0,0,0,0.2); padding: 1px 4px; border-radius: 3px;", yol)
        )
      } else {
        tags$div(
          style = "padding: 8px 10px; border-radius: 8px; font-size: 12px; background: rgba(255,152,0,0.1); color: #FFB74D; border: 1px solid rgba(255,152,0,0.2);",
          icon("exclamation-triangle"),
          tags$span("CLI otomatik tespit edilemedi."),
          tags$br(),
          tags$small("npm ile Claude Code kurulu olduğundan emin olun.")
        )
      }
    })

    # Bağlantı testi
    observeEvent(input$cc_test_connection, {
      cli_yolu <- resolve_claude_cli_path(claude_code_config$cli_path)

      shinyjs::disable("cc_test_connection")
      output$cc_test_result_ui <- renderUI({
        tags$span(style = "font-size: 12px; color: #64B5F6;",
                  icon("spinner", class = "fa-spin"), "Test ediliyor...")
      })

      # Worker tarafına bağımlılık aktarımı ve sağlık metrikleri için
      # doğrudan future_promise yerine tracked_future_promise kullanılır.
      tracked_future_promise(
        task_fn = function() {
          test_claude_code_connection(
            cli_path = cli_yolu,
            workdir = tempdir()
          )
        },
        task_type = "claude_code_connection_test",
        session_token = session$token
      ) %...>% (function(sonuc) {
        # Sonucu Claude Code sayfasına da ilet
        settings$claude_code_connection_ok <- sonuc$success

        output$cc_test_result_ui <- renderUI({
          if (sonuc$success) {
            tags$div(
              style = "font-size: 12px; color: #81C784; margin-top: 8px;",
              icon("check-circle"),
              tags$span(sonuc$message),
              tags$br(),
              tags$small(style = "opacity: 0.8;", sonuc$details)
            )
          } else {
            tags$div(
              style = "font-size: 12px; color: #E57373; margin-top: 8px;",
              icon("exclamation-triangle"),
              tags$span(sonuc$message),
              tags$br(),
              tags$small(style = "opacity: 0.8;", sonuc$details)
            )
          }
        })
        shinyjs::enable("cc_test_connection")
      }) %...!% (function(hata) {
        settings$claude_code_connection_ok <- FALSE
        # Süslü parantezleri temizle (glue formatter çakışmasını önle)
        temiz_hata <- gsub("[{}]", "", conditionMessage(hata))
        output$cc_test_result_ui <- renderUI({
          tags$div(
            style = "font-size: 12px; color: #E57373; margin-top: 8px;",
            icon("exclamation-triangle"),
            tags$span("Test sırasında beklenmeyen hata."),
            tags$small(temiz_hata)
          )
        })
        shinyjs::enable("cc_test_connection")
      })
    }, ignoreInit = TRUE)

    # Zaman aşımı değerini settings'e aktar
    observeEvent(input$claude_code_timeout, {
      settings$claude_code_timeout <- input$claude_code_timeout
    }, ignoreInit = TRUE)

    # Koordinatöre döndürülecek değerler
    return(list(
      save_trigger = save_trigger,
      reset_trigger = reset_trigger,
      temp_model_selection = temp_model_selection,
      temp_image_size = temp_image_size,
      temp_image_quality_hd = temp_image_quality_hd,
      temp_summary_detail_level = temp_summary_detail_level,
      temp_summary_focus_mode = temp_summary_focus_mode,
      temp_analysis_deep_thinking = temp_analysis_deep_thinking,
      temp_analysis_detail_level = temp_analysis_detail_level
    ))
  })
}
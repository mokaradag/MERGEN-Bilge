# R/module_settings.R
# Dosya Yolu: R/module_settings.R
# Açıklama: Ayarlar koordinatör modülü.
#            Kişiselleştirme ve Yapılandırma alt sekmelerini yönetir.
#            Merkezi ayar reaktif değerlerini oluşturur, her iki alt modülün
#            kaydet/sıfırla/yükle işlemlerini koordine eder.

#' Ayarlar Koordinatörü
#'
#' @description Tüm ayarların merkezi reaktif değerlerini oluşturur,
#'              alt modülleri başlatır ve kaydet/sıfırla/yükle mantığını yönetir.
#' @param session Ana Shiny oturum nesnesi
#' @param parent_session Üst oturum (genellikle session ile aynı)
#' @return Uygulama genelinde kullanılan settings reaktif değerleri
settingsInit <- function(session, parent_session = NULL) {

  # Tüm ayarların merkezi reaktif değerleri
  settings <- reactiveValues(
    model_selection         = api_config$local_models[1],
    selected_character      = "mergen",
    enable_animations       = TRUE,
    enable_timestamps       = TRUE,
    enable_typing_indicator = TRUE,
    enable_streaming        = TRUE,
    enable_widescreen       = TRUE,
    enable_tts_audio        = FALSE,
    enable_rdata_tools      = FALSE,
    enable_mcp_tools        = FALSE,
    enable_summarization_tools = FALSE,
    enable_coding_tools     = FALSE,
    enable_process_tools    = FALSE,
    enable_app_expert_tools = FALSE,
    enable_image_tools      = FALSE,
    image_size              = "1024x1024",
    image_quality_hd        = FALSE,
    summary_detail_level    = "standard",
    summary_focus_mode      = "general",
    analysis_deep_thinking  = FALSE,
    analysis_detail_level   = "standart",
    enable_followups        = FALSE,
    font_size               = "medium",
    enable_background_music = FALSE,
    music_volume            = 0.3,
    experience_mode         = "odak",
    show_intro_animation    = TRUE
  )

  # ---- Alt modülleri başlat ----
  kisisel <- settingsKisiselServer(
    "settings_kisisel_module", settings, parent_session %||% session
  )
  yapilandirma <- settingsYapilandirmaServer(
    "settings_yapilandirma_module", settings, parent_session %||% session
  )

  # ---- localStorage'dan ayarları yükle (başlangıçta bir kez) ----
  observeEvent(TRUE, {
    session$sendCustomMessage("loadSettings", list())
  }, once = TRUE)

  # ---- Yüklenen ayarları işle ----
  observeEvent(session$input$loaded_settings, {
    req(session$input$loaded_settings)
    loaded <- session$input$loaded_settings

    # --- Kişiselleştirme ayarlarını yükle ---
    if (!is.null(loaded$selected_character)) {
      settings$selected_character <- loaded$selected_character
      kisisel$temp_selected_character(loaded$selected_character)
      kisisel$update_character_display(loaded$selected_character)
    }

    if (!is.null(loaded$experience_mode) && loaded$experience_mode %in% c("odak", "denge", "kesif")) {
      settings$experience_mode <- loaded$experience_mode
      session$sendCustomMessage("updateSettingsMode", list(mode = loaded$experience_mode))
    }

    # --- Yapılandırma ayarlarını yükle ---
    if (!is.null(loaded$model_selection) && loaded$model_selection %in% api_config$local_models) {
      settings$model_selection <- loaded$model_selection
    }
    if (!is.null(loaded$enable_animations)) {
      settings$enable_animations <- loaded$enable_animations
    }
    if (!is.null(loaded$enable_timestamps)) {
      settings$enable_timestamps <- loaded$enable_timestamps
    }
    if (!is.null(loaded$enable_typing_indicator)) {
      settings$enable_typing_indicator <- loaded$enable_typing_indicator
    }
    if (!is.null(loaded$enable_streaming)) {
      settings$enable_streaming <- loaded$enable_streaming
    }
    if (!is.null(loaded$enable_widescreen)) {
      settings$enable_widescreen <- loaded$enable_widescreen
    }
    if (!is.null(loaded$enable_tts_audio)) {
      settings$enable_tts_audio <- isTRUE(loaded$enable_tts_audio)
    }
    if (!is.null(loaded$enable_background_music)) {
      settings$enable_background_music <- loaded$enable_background_music
    }
    if (!is.null(loaded$music_volume)) {
      settings$music_volume <- loaded$music_volume
    }
    if (!is.null(loaded$enable_followups)) {
      settings$enable_followups <- isTRUE(loaded$enable_followups)
    }
    if (!is.null(loaded$font_size)) {
      settings$font_size <- loaded$font_size
    }

    # Araç ayarları
    if (!is.null(loaded$enable_rdata_tools)) {
      settings$enable_rdata_tools <- isTRUE(loaded$enable_rdata_tools)
    } else {
      settings$enable_rdata_tools <- FALSE
    }
    if (!is.null(loaded$enable_mcp_tools)) {
      settings$enable_mcp_tools <- isTRUE(loaded$enable_mcp_tools)
    }
    if (!is.null(loaded$enable_summarization_tools)) {
      settings$enable_summarization_tools <- isTRUE(loaded$enable_summarization_tools)
    }
    if (!is.null(loaded$enable_coding_tools)) {
      settings$enable_coding_tools <- isTRUE(loaded$enable_coding_tools)
    }
    if (!is.null(loaded$enable_process_tools)) {
      settings$enable_process_tools <- isTRUE(loaded$enable_process_tools)
    }
    if (!is.null(loaded$enable_app_expert_tools)) {
      settings$enable_app_expert_tools <- isTRUE(loaded$enable_app_expert_tools)
    }
    if (!is.null(loaded$enable_image_tools)) {
      settings$enable_image_tools <- isTRUE(loaded$enable_image_tools)
    }

    # Aynı anda birden fazla aracın aktif olmasını engelle
    ANALYSIS_TOOLS <- c(
      "enable_rdata_tools", "enable_mcp_tools", "enable_summarization_tools",
      "enable_coding_tools", "enable_process_tools", "enable_app_expert_tools",
      "enable_image_tools"
    )
    active_tools <- Filter(function(t) isTRUE(settings[[t]]), ANALYSIS_TOOLS)
    if (length(active_tools) > 1) {
      for (tool in active_tools[-1]) {
        settings[[tool]] <- FALSE
      }
    }

    # Görsel ayarları
    if (!is.null(loaded$image_size) && loaded$image_size %in% c("1024x1024", "1792x1024", "1024x1792")) {
      settings$image_size <- loaded$image_size
      yapilandirma$temp_image_size(loaded$image_size)
    }
    if (!is.null(loaded$image_quality_hd)) {
      settings$image_quality_hd <- isTRUE(loaded$image_quality_hd)
      yapilandirma$temp_image_quality_hd(isTRUE(loaded$image_quality_hd))
    }

    # Özetleme ayarları
    if (!is.null(loaded$summary_detail_level) && loaded$summary_detail_level %in% c("brief", "standard", "detailed")) {
      settings$summary_detail_level <- loaded$summary_detail_level
      yapilandirma$temp_summary_detail_level(loaded$summary_detail_level)
    }
    if (!is.null(loaded$summary_focus_mode) && loaded$summary_focus_mode %in% c("general", "numerical", "decisions", "comparison")) {
      settings$summary_focus_mode <- loaded$summary_focus_mode
      yapilandirma$temp_summary_focus_mode(loaded$summary_focus_mode)
    }

    # Analiz ayarları
    if (!is.null(loaded$analysis_deep_thinking)) {
      settings$analysis_deep_thinking <- isTRUE(loaded$analysis_deep_thinking)
      yapilandirma$temp_analysis_deep_thinking(isTRUE(loaded$analysis_deep_thinking))
    }
    if (!is.null(loaded$analysis_detail_level) && loaded$analysis_detail_level %in% c("ozet", "standart", "detayli")) {
      settings$analysis_detail_level <- loaded$analysis_detail_level
      yapilandirma$temp_analysis_detail_level(loaded$analysis_detail_level)
    }

    # Giriş animasyonu ayarı
    if (!is.null(loaded$skip_intro)) {
      settings$show_intro_animation <- !isTRUE(loaded$skip_intro)
    }
  }, ignoreInit = TRUE)

  # ---- Kaydet (her iki alt sekmeden tetiklenebilir) ----
  save_all_settings <- function() {
    # Kişiselleştirme geçici değerlerini uygula
    settings$selected_character <- kisisel$temp_selected_character()

    # Yapılandırma geçici değerlerini uygula
    settings$model_selection <- yapilandirma$temp_model_selection()
    settings$image_size <- yapilandirma$temp_image_size()
    settings$image_quality_hd <- yapilandirma$temp_image_quality_hd()
    settings$summary_detail_level <- yapilandirma$temp_summary_detail_level()
    settings$summary_focus_mode <- yapilandirma$temp_summary_focus_mode()
    settings$analysis_deep_thinking <- yapilandirma$temp_analysis_deep_thinking()
    settings$analysis_detail_level <- yapilandirma$temp_analysis_detail_level()

    cat(sprintf("[SETTINGS] Ayarlar kaydediliyor. Model: %s, Karakter: %s, Görsel Boyutu: %s, HD: %s, Özet Detay: %s, Özet Odak: %s, Analiz Derin: %s, Analiz Detay: %s\n",
                settings$model_selection, settings$selected_character,
                settings$image_size, settings$image_quality_hd,
                settings$summary_detail_level, settings$summary_focus_mode,
                settings$analysis_deep_thinking, settings$analysis_detail_level))

    Sys.sleep(0.1)

    # Karakter video geçişini tetikle
    session$sendCustomMessage("triggerVideoSelection", list(
      character = settings$selected_character,
      timestamp = as.numeric(Sys.time())
    ))

    # Görsel ayarlarını Ana Söyleşi sayfasına senkronize et
    session$sendCustomMessage("syncImageSettingsToChat", list(
      size = settings$image_size,
      quality_hd = isTRUE(settings$image_quality_hd)
    ))

    # Özetleme ayarlarını Ana Söyleşi sayfasına senkronize et
    session$sendCustomMessage("syncSummarySettingsToChat", list(
      detail_level = settings$summary_detail_level,
      focus_mode = settings$summary_focus_mode
    ))

    # Analiz ayarlarını Ana Söyleşi sayfasına senkronize et
    session$sendCustomMessage("syncAnalysisSettingsToChat", list(
      deep_thinking = isTRUE(settings$analysis_deep_thinking),
      detail_level = settings$analysis_detail_level
    ))

    # localStorage'a kaydet
    to_save <- reactiveValuesToList(settings)
    to_save$experience_mode        <- settings$experience_mode
    to_save$skip_intro             <- !isTRUE(settings$show_intro_animation)
    session$sendCustomMessage("saveSettings", to_save)

    showToast(session, "Ayarlar kaydedildi!", "success")
  }

  observeEvent(kisisel$save_trigger(), {
    save_all_settings()
  }, ignoreInit = TRUE)

  observeEvent(yapilandirma$save_trigger(), {
    save_all_settings()
  }, ignoreInit = TRUE)

  # ---- Sıfırla (her iki alt sekmeden tetiklenebilir) ----
  reset_all_settings <- function() {
    default_model <- api_config$local_models[1]

    # Tüm ayarları varsayılana döndür
    settings$model_selection          <- default_model
    settings$selected_character       <- "mergen"
    settings$enable_animations        <- TRUE
    settings$enable_timestamps        <- TRUE
    settings$enable_typing_indicator  <- TRUE
    settings$enable_streaming         <- TRUE
    settings$enable_widescreen        <- TRUE
    settings$enable_tts_audio         <- TRUE
    settings$enable_rdata_tools       <- FALSE
    settings$enable_mcp_tools         <- FALSE
    settings$enable_summarization_tools <- FALSE
    settings$enable_coding_tools      <- FALSE
    settings$enable_process_tools     <- FALSE
    settings$enable_app_expert_tools  <- FALSE
    settings$enable_image_tools       <- FALSE
    settings$enable_followups         <- TRUE
    settings$font_size                <- "medium"
    settings$enable_background_music  <- FALSE
    settings$music_volume             <- 0.3
    settings$experience_mode          <- "odak"
    settings$show_intro_animation     <- TRUE
    settings$image_size               <- "1024x1024"
    settings$image_quality_hd         <- FALSE
    settings$summary_detail_level     <- "standard"
    settings$summary_focus_mode       <- "general"
    settings$analysis_deep_thinking   <- FALSE
    settings$analysis_detail_level    <- "standart"

    # Kişiselleştirme geçici değerlerini sıfırla
    kisisel$temp_selected_character("mergen")
    kisisel$update_character_display("mergen")
    session$sendCustomMessage("updateSettingsMode", list(mode = "odak"))

    # Yapılandırma geçici değerlerini sıfırla
    yapilandirma$temp_model_selection(default_model)
    yapilandirma$temp_image_size("1024x1024")
    yapilandirma$temp_image_quality_hd(FALSE)
    yapilandirma$temp_summary_detail_level("standard")
    yapilandirma$temp_summary_focus_mode("general")
    yapilandirma$temp_analysis_deep_thinking(FALSE)
    yapilandirma$temp_analysis_detail_level("standart")

    # Ana Söyleşi'deki kontrolleri sıfırla
    session$sendCustomMessage("syncImageSettingsToChat", list(
      size = "1024x1024",
      quality_hd = FALSE
    ))
    session$sendCustomMessage("syncSummarySettingsToChat", list(
      detail_level = "standard",
      focus_mode = "general"
    ))
    session$sendCustomMessage("syncAnalysisSettingsToChat", list(
      deep_thinking = FALSE,
      detail_level = "standart"
    ))
    session$sendCustomMessage("toggleAnalysisMode", list(active = FALSE))

    # localStorage'ı temizle
    session$sendCustomMessage("clearSettings", list())
    showToast(session, "Ayarlar sıfırlandı!", "info")
  }

  observeEvent(kisisel$reset_trigger(), {
    reset_all_settings()
  }, ignoreInit = TRUE)

  observeEvent(yapilandirma$reset_trigger(), {
    reset_all_settings()
  }, ignoreInit = TRUE)

  return(settings)
}

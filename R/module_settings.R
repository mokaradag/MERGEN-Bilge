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
  # Not: settings$theme istemci tarafı (theme_manager.js) ile aktif olarak
  # senkronize edilir. Aşağıdaki iki observer (mergen_theme_changed ve
  # mergen_theme_initial) settings$theme'i istemci durumuna eşitler. Bu
  # save_all_settings()'in eski bir tema değerini yanlışlıkla localStorage'a
  # geri yazmasını engeller.
  settings <- reactiveValues(
    model_selection         = api_config$local_models[1],
    selected_character      = CHARACTER_DEFAULT_ID,
    theme                   = "dark",
    enable_animations       = TRUE,
    enable_timestamps       = TRUE,
    enable_typing_indicator = TRUE,
    enable_streaming        = TRUE,
    enable_widescreen       = TRUE,
    enable_tool_backgrounds = TRUE,
    enable_tts_audio        = FALSE,
    enable_rdata_tools      = FALSE,
    enable_mcp_tools        = FALSE,
    enable_summarization_tools = FALSE,
    enable_coding_tools     = FALSE,
    enable_process_tools    = FALSE,
    enable_app_expert_tools = FALSE,
    enable_image_tools      = FALSE,
    # Süreç Yönetimi'nde son seçilen akış anahtarı (flow_1/flow_2/...). Sohbet
    # içi akış seçici değiştikçe kaydedilir; yenilemeden sonra seçim geri
    # yüklenir, böylece gönderimler varsayılan ilk akışa sessizce düşmez.
    process_flow_selection  = "",
    image_size              = "1024x1024",
    image_quality_hd        = FALSE,
    summary_detail_level    = "standard",
    summary_focus_mode      = "general",
    analysis_deep_thinking  = FALSE,
    analysis_detail_level   = "standart",
    # Excel Analizi / Kod Uzmanı için Derin Düşünme durumu ve seviyesi
    excel_deep_thinking     = FALSE,
    excel_deep_level        = "low",
    coding_deep_thinking    = FALSE,
    coding_deep_level       = "low",
    enable_followups        = FALSE,
    font_size               = "medium",
    enable_background_music = FALSE,
    enable_ai_expert        = FALSE,
    ai_expert_talk_length   = "orta",
    ai_expert_talk_frequency = "orta",
    ai_expert_talk_style    = "profesyonel",
    music_volume            = 0.3,
    experience_mode         = "odak",
    show_intro_animation    = TRUE,
    # Başlangıç şeridi: fast_lane/rich_lane/ask_once (ask_once = seçici sor)
    startup_lane            = "ask_once",
    claude_code_timeout     = claude_code_config$timeout_seconds,
    claude_code_connection_ok = NULL
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
    # Eski kayıtlı persona tercihi (örn. "mergen") yeni kimliğe normalleştirilir
    if (!is.null(loaded$selected_character)) {
      normalized_char <- normalize_character_id(loaded$selected_character)
      settings$selected_character <- normalized_char
      kisisel$temp_selected_character(normalized_char)
      kisisel$update_character_display(normalized_char)
    }

    if (!is.null(loaded$experience_mode) && loaded$experience_mode %in% c("odak", "denge", "kesif")) {
      settings$experience_mode <- loaded$experience_mode
      kisisel$temp_experience_mode(loaded$experience_mode)
      session$sendCustomMessage("updateSettingsMode", list(mode = loaded$experience_mode))
    }

    # Başlangıç şeridi: yalnızca kesin şeritler geri yüklenir; radyo/pending
    # senkronu yapilandirma modülündeki settings$startup_lane gözlemcisindedir.
    lane_loaded <- as.character(loaded$startup_lane %||% "")[1]
    if (!is.na(lane_loaded) && lane_loaded %in% c("fast_lane", "rich_lane")) {
      settings$startup_lane <- lane_loaded
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
    # Araç arka plan animasyonları tercihi: varsayılan açık.
    # Yüklenen değer yoksa veya geçersizse helper varsayılana düşer.
    {
      tool_bg_loaded <- mb_tool_bg_coerce_enabled(
        loaded$enable_tool_backgrounds,
        default = mb_tool_bg_default_enabled()
      )
      settings$enable_tool_backgrounds <- tool_bg_loaded
      mb_tool_bg_apply_to_client(session, tool_bg_loaded)
    }
    # Tema tercihi: varsayılan koyu. Geçerli değerler: "dark" / "light".
    if (!is.null(loaded$theme) && loaded$theme %in% c("dark", "light")) {
      settings$theme <- loaded$theme
    } else if (is.null(loaded$theme)) {
      # localStorage'da hiç tema yoksa koyu kalır; istemci tarafı zaten
      # data-theme="dark" uygular.
      settings$theme <- "dark"
    }
    if (!is.null(loaded$enable_tts_audio)) {
      settings$enable_tts_audio <- isTRUE(loaded$enable_tts_audio)
    }
    if (!is.null(loaded$enable_background_music)) {
      settings$enable_background_music <- loaded$enable_background_music
    }
    if (!is.null(loaded$enable_ai_expert)) {
      settings$enable_ai_expert <- isTRUE(loaded$enable_ai_expert)
    }
    if (!is.null(loaded$ai_expert_talk_length) && loaded$ai_expert_talk_length %in% c("kisa", "orta", "uzun")) {
      settings$ai_expert_talk_length <- loaded$ai_expert_talk_length
    }
    if (!is.null(loaded$ai_expert_talk_frequency) && loaded$ai_expert_talk_frequency %in% c("az", "orta", "sik")) {
      settings$ai_expert_talk_frequency <- loaded$ai_expert_talk_frequency
    }
    if (!is.null(loaded$ai_expert_talk_style) && loaded$ai_expert_talk_style %in% c("profesyonel", "samimi", "motivasyonel", "bilimsel")) {
      settings$ai_expert_talk_style <- loaded$ai_expert_talk_style
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
    if (!is.null(loaded$process_flow_selection)) {
      pf_restored <- as.character(loaded$process_flow_selection)[1]
      if (!is.na(pf_restored) && nzchar(pf_restored)) {
        settings$process_flow_selection <- pf_restored
        # Süreç modu şu an KAPALI olsa bile gizli DOM akış seçicisini kalıcı
        # seçime hizala. Aksi halde seçici varsayılan (flow_1) konumunda kalır;
        # kullanıcı sonradan Süreç modunu (ayarlar/hızlı işlem) etkinleştirince
        # toggleProcessMode(active=TRUE) işleyicisi bu senkronsuz varsayılanı
        # yayınlar ve chat_process_flow gözlemcisi onu hemen kalıcılaştırarak
        # kayıtlı akış seçimini ezerdi. Önceden hizalanınca her etkinleştirme
        # yayını doğru akışı bildirir. Bildirilen değer kalıcı seçimle aynı
        # olduğundan gözlemci no-op yapar (döngü/ezme olmaz).
        session$sendCustomMessage("syncProcessFlowToChat", list(flow_key = pf_restored))
      }
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

    # Kalıcı olarak aktif gelen araç panelsiz bir Langflow aracıysa (Süreç
    # Yönetimi / Uygulama Uzmanı), model kilidi DOM tespitiyle değil sunucudan
    # bildirilir (tools_model_lock.js serverLockLabel). Sayfa yenilemesinden sonra
    # bu kilit yeniden gönderilmezse model seçici düzenlenebilir kalır ama
    # gönderimler Langflow'a yönlenip yerel model yok sayılır. Süreç Yönetimi
    # ayrıca sohbet içi akış seçicisini de görünür kılar (yalnızca JS `hidden`
    # sınıfıyla gizlendiğinden yenilemeden sonra tekrar gösterilmelidir).
    langflow_flags <- if (exists("mergen_langflow_setting_flags", mode = "function")) {
      mergen_langflow_setting_flags()
    } else {
      c("enable_process_tools", "enable_app_expert_tools")
    }
    active_langflow_flag <- Filter(function(f) isTRUE(settings[[f]]), langflow_flags)
    if (length(active_langflow_flag) > 0) {
      lf_flag <- active_langflow_flag[[1]]
      lf_label <- "Bu araç"
      if (exists("get_tool_mode_config", mode = "function")) {
        lf_cfg <- get_tool_mode_config(lf_flag, by = "setting_flag")
        lf_label <- lf_cfg$title %||% "Bu araç"
      }
      session$sendCustomMessage("setToolModelLock", list(active = TRUE, label = lf_label))
      if (identical(lf_flag, "enable_process_tools")) {
        # Akış seçici görünür kılınır. DOM seçicisi yukarıda kalıcı seçime zaten
        # hizalandığından, toggle işleyicisinin yeniden yayınladığı değer doğru
        # akıştır; burada ayrıca senkronlamaya gerek yoktur.
        session$sendCustomMessage("toggleProcessMode", list(active = TRUE))
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

    # Excel/Kod Derin Düşünme ayarları
    if (!is.null(loaded$excel_deep_thinking)) {
      settings$excel_deep_thinking <- isTRUE(loaded$excel_deep_thinking)
    }
    if (!is.null(loaded$excel_deep_level) && loaded$excel_deep_level %in% c("low", "high")) {
      settings$excel_deep_level <- loaded$excel_deep_level
    }
    if (!is.null(loaded$coding_deep_thinking)) {
      settings$coding_deep_thinking <- isTRUE(loaded$coding_deep_thinking)
    }
    if (!is.null(loaded$coding_deep_level) && loaded$coding_deep_level %in% c("low", "high")) {
      settings$coding_deep_level <- loaded$coding_deep_level
    }

    # Giriş animasyonu ayarı
    if (!is.null(loaded$skip_intro)) {
      settings$show_intro_animation <- !isTRUE(loaded$skip_intro)
    }
  }, ignoreInit = TRUE)

  # ---- Süreç Yönetimi akış seçimi kalıcılığı ----
  # Kullanıcı sohbet içi süreç akışı seçicisini (input$chat_process_flow)
  # değiştirdiğinde seçim reaktif ayara yazılır ve kısmi saveSettings ile
  # localStorage'a birleştirilerek anında kaydedilir. Böylece sayfa
  # yenilemesinden sonra önceki akış seçimi geri yüklenir; aksi halde Süreç
  # Yönetimi gönderimleri varsayılan ilk akışa sessizce düşerdi.
  observeEvent(session$input$chat_process_flow, {
    flow_key <- session$input$chat_process_flow
    if (is.null(flow_key)) return(invisible(NULL))
    flow_key <- as.character(flow_key)[1]
    if (is.na(flow_key) || !nzchar(flow_key)) return(invisible(NULL))
    if (!identical(isolate(settings$process_flow_selection), flow_key)) {
      settings$process_flow_selection <- flow_key
      session$sendCustomMessage("saveSettings", list(process_flow_selection = flow_key))
    }
  }, ignoreInit = TRUE)

  # ---- İstemci tarafı tema değişikliği ile senkronizasyon ----
  # theme_manager.js her toggle/set çağrısında Shiny'e
  # input$mergen_theme_changed = list(theme = "dark"/"light", ts = ...)
  # gönderir. Bu observer settings$theme'i istemci durumuna eşitler. Aksi
  # halde save_all_settings() reactiveValuesToList() ile eski "dark"
  # değerini saveSettings içine yazıp light tercihi localStorage'da
  # silebilir.
  observeEvent(session$input$mergen_theme_changed, {
    payload <- session$input$mergen_theme_changed
    if (is.null(payload)) return(invisible(NULL))
    new_theme <- payload$theme
    if (is.null(new_theme) || !nzchar(as.character(new_theme)[1])) {
      return(invisible(NULL))
    }
    new_theme <- as.character(new_theme)[1]
    if (!new_theme %in% c("dark", "light")) {
      return(invisible(NULL))
    }
    if (!identical(isolate(settings$theme), new_theme)) {
      settings$theme <- new_theme
    }
  }, ignoreInit = TRUE)

  # Tarayıcı bağlandığında theme_manager.js başlangıç temasını da gönderir.
  # Bu özellikle SSO + sayfa yenilemesi senaryosunda settings$theme'i doğru
  # başlangıç değerine getirir, böylece ilk save işleminde stale "dark"
  # değeri persistlenmez.
  observeEvent(session$input$mergen_theme_initial, {
    payload <- session$input$mergen_theme_initial
    if (is.null(payload)) return(invisible(NULL))
    initial_theme <- payload$theme
    if (is.null(initial_theme) || !nzchar(as.character(initial_theme)[1])) {
      return(invisible(NULL))
    }
    initial_theme <- as.character(initial_theme)[1]
    if (!initial_theme %in% c("dark", "light")) {
      return(invisible(NULL))
    }
    if (!identical(isolate(settings$theme), initial_theme)) {
      settings$theme <- initial_theme
    }
  }, ignoreInit = TRUE)

  # ---- Kaydet (her iki alt sekmeden tetiklenebilir) ----
  save_all_settings <- function() {
    # Kişiselleştirme geçici değerlerini uygula
    settings$selected_character <- kisisel$temp_selected_character()

    # Karakter rengi/görseli artık gerçekten kaydedildi.
    # Bu çağrı committed = TRUE olduğu için Ana Söyleşi neural rengi şimdi güncellenebilir.
    kisisel$update_character_display(settings$selected_character, committed = TRUE)

    # Deneyim modu değişikliği varsa uygula (sadece kaydet butonunda)
    # Kullanıcı mod kartına tıkladıysa aynı mod olsa bile tekrar uygula
    mode_changed <- FALSE
    new_mode <- kisisel$temp_experience_mode()
    explicitly_clicked <- isTRUE(kisisel$mode_was_clicked())
    if (!is.null(new_mode) && (new_mode != isolate(settings$experience_mode) || explicitly_clicked)) {
      settings$experience_mode <- new_mode
      apply_experience_mode(session, settings, new_mode)
      mode_changed <- TRUE
      # Tıklama bayrağını sıfırla
      kisisel$mode_was_clicked(FALSE)
      cat(sprintf("[SETTINGS] Deneyim modu uygulandı: %s (açık tıklama: %s)\n", new_mode, explicitly_clicked))
    }

    # Yapılandırma geçici değerlerini uygula
    settings$model_selection <- yapilandirma$temp_model_selection()
    settings$image_size <- yapilandirma$temp_image_size()
    settings$image_quality_hd <- yapilandirma$temp_image_quality_hd()
    settings$summary_detail_level <- yapilandirma$temp_summary_detail_level()
    settings$summary_focus_mode <- yapilandirma$temp_summary_focus_mode()
    settings$analysis_deep_thinking <- yapilandirma$temp_analysis_deep_thinking()
    settings$analysis_detail_level <- yapilandirma$temp_analysis_detail_level()
    mergen_apply_saved_startup_lane(session, settings, yapilandirma$temp_startup_lane())

    # Müzik durumunu checkbox'tan oku ve uygula (sadece kaydet anında)
    # Mod değişikliği olduysa müzik zaten apply_experience_mode tarafından ayarlandı,
    # checkbox değerini tekrar okumayı atla (yarış durumu koruması)
    if (!mode_changed) {
      music_checkbox_val <- isTRUE(session$input[["settings_yapilandirma_module-enable_background_music"]])
      if (!identical(music_checkbox_val, isolate(settings$enable_background_music))) {
        settings$enable_background_music <- music_checkbox_val
        session$sendCustomMessage("toggleMusic", list(
          enabled = music_checkbox_val,
          character = normalize_character_id(settings$selected_character)
        ))
        cat(sprintf("[MUSIC] Müzik durumu kaydedildi: %s\n", music_checkbox_val))
      }
    }

    # AI Uzman checkbox durumunu oku ve uygula
    ai_expert_val <- isTRUE(session$input[["settings_yapilandirma_module-enable_ai_expert"]])
    settings$enable_ai_expert <- ai_expert_val

    # AI Uzman konuşma ayarlarını oku ve uygula
    talk_length <- session$input[["settings_yapilandirma_module-ai_expert_talk_length"]]
    if (!is.null(talk_length) && talk_length %in% c("kisa", "orta", "uzun")) {
      settings$ai_expert_talk_length <- talk_length
    }
    talk_freq <- session$input[["settings_yapilandirma_module-ai_expert_talk_frequency"]]
    if (!is.null(talk_freq) && talk_freq %in% c("az", "orta", "sik")) {
      settings$ai_expert_talk_frequency <- talk_freq
    }
    talk_style <- session$input[["settings_yapilandirma_module-ai_expert_talk_style"]]
    if (!is.null(talk_style) && talk_style %in% c("profesyonel", "samimi", "motivasyonel", "bilimsel")) {
      settings$ai_expert_talk_style <- talk_style
    }

    # Karakter değişikliği müzik yöneticisine bildir
    session$sendCustomMessage("setMusicCharacter", list(
      character = normalize_character_id(settings$selected_character)
    ))

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
    # Tema: settings$theme istemci olaylarıyla zaten senkronize. Yine de
    # geçersiz değerleri ayıklayıp saveSettings içine yalnızca onaylı
    # değerleri yaz. Belirsiz/eksik durumda anahtarı tamamen atla; bu
    # halde theme_manager.js'in yazdığı mevcut localStorage tercihi
    # korunur (Codex review #1 senaryosu).
    current_theme <- isolate(settings$theme)
    if (is.character(current_theme) && length(current_theme) == 1L &&
        current_theme %in% c("dark", "light")) {
      to_save$theme <- current_theme
    } else {
      to_save$theme <- NULL
    }
    session$sendCustomMessage("saveSettings", to_save)

    showToast(session, "Ayarlar kaydedildi!", "success")
  }

  # Not: Bu gözlemciler öncelikli (priority > 0) OLMAMALI. Bir ayar değişip
  # hemen ardından Kaydet'e tıklandığında, değişen input ve kaydetme tıklaması
  # aynı Shiny flush'ında işlenebilir; alt modüllerdeki input->settings kopya
  # gözlemcileri varsayılan (0) öncelikte ve bu dosyadan önce oluşturulduğu
  # için eşit öncelikte önce çalışır. Buradaki gözlemcilere daha yüksek öncelik
  # verilirse, henüz kopyalanmamış input değeri kaydedilirken başarı toast'ı
  # gösterilebilir (Codex PR #636 P2 incelemesi).
  observeEvent(kisisel$save_trigger(), {
    mergen_perf_time("settings_save_kisisel", save_all_settings())
  }, ignoreInit = TRUE)

  observeEvent(yapilandirma$save_trigger(), {
    mergen_perf_time("settings_save_yapilandirma", save_all_settings())
  }, ignoreInit = TRUE)

  # ---- Sıfırla (her iki alt sekmeden tetiklenebilir) ----
  reset_all_settings <- function() {
    default_model <- api_config$local_models[1]

    # Tüm ayarları varsayılana döndür
    settings$model_selection          <- default_model
    settings$selected_character       <- CHARACTER_DEFAULT_ID
    # Tema varsayılanı: koyu (mevcut görünüm korunur)
    settings$theme                    <- "dark"
    settings$enable_animations        <- TRUE
    settings$enable_timestamps        <- TRUE
    settings$enable_typing_indicator  <- TRUE
    settings$enable_streaming         <- TRUE
    settings$enable_widescreen        <- TRUE
    settings$enable_tool_backgrounds  <- mb_tool_bg_default_enabled()
    # Varsayılan: Yanıtları Seslendir KAPALI olmalı. Aksi halde sıfırlamada
    # TTS görselleştirici, hiçbir konuşma seçeneği seçili olmadan görünüyordu.
    settings$enable_tts_audio         <- FALSE
    settings$enable_rdata_tools       <- FALSE
    settings$enable_mcp_tools         <- FALSE
    settings$enable_summarization_tools <- FALSE
    settings$enable_coding_tools      <- FALSE
    settings$enable_process_tools     <- FALSE
    settings$enable_app_expert_tools  <- FALSE
    settings$enable_image_tools       <- FALSE
    settings$process_flow_selection   <- ""
    settings$enable_followups         <- TRUE
    settings$font_size                <- "medium"
    settings$enable_background_music  <- FALSE
    settings$enable_ai_expert         <- FALSE
    settings$ai_expert_talk_length    <- "orta"
    settings$ai_expert_talk_frequency <- "orta"
    settings$ai_expert_talk_style     <- "profesyonel"
    settings$music_volume             <- 0.3
    settings$experience_mode          <- "odak"
    settings$show_intro_animation     <- TRUE
    # Şerit ask_once'a döner; sonraki açılışta seçici yeniden sorulur.
    settings$startup_lane             <- "ask_once"
    settings$image_size               <- "1024x1024"
    settings$image_quality_hd         <- FALSE
    settings$summary_detail_level     <- "standard"
    settings$summary_focus_mode       <- "general"
    settings$analysis_deep_thinking   <- FALSE
    settings$analysis_detail_level    <- "standart"
    settings$claude_code_timeout      <- claude_code_config$timeout_seconds
    # Excel/Kod Derin Düşünme durum ve seviyelerini de varsayılana çek
    settings$excel_deep_thinking      <- FALSE
    settings$excel_deep_level         <- "low"
    settings$coding_deep_thinking     <- FALSE
    settings$coding_deep_level        <- "low"

    # Kişiselleştirme geçici değerlerini sıfırla
    kisisel$temp_selected_character(CHARACTER_DEFAULT_ID)
    kisisel$temp_experience_mode("odak")
    kisisel$update_character_display(CHARACTER_DEFAULT_ID)
    session$sendCustomMessage("updateSettingsMode", list(mode = "odak"))

    # Yapılandırma geçici değerlerini sıfırla
    yapilandirma$temp_model_selection(default_model)
    yapilandirma$temp_image_size("1024x1024")
    yapilandirma$temp_image_quality_hd(FALSE)
    yapilandirma$temp_summary_detail_level("standard")
    yapilandirma$temp_summary_focus_mode("general")
    yapilandirma$temp_analysis_deep_thinking(FALSE)
    yapilandirma$temp_analysis_detail_level("standart")

    # Müziği durdur (varsayılan: odak modu, müzik kapalı)
    session$sendCustomMessage("toggleMusic", list(enabled = FALSE))

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
    # Diğer tüm araç modlarını da kapat ki sohbet içi kontroller (Excel/Kod
    # Derin Düşünme, özetleme, görsel) ve merkezi model seçim kilidi serbest kalsın.
    session$sendCustomMessage("toggleSummaryMode", list(active = FALSE))
    session$sendCustomMessage("toggleImageMode", list(active = FALSE))
    session$sendCustomMessage("toggleExcelMode", list(active = FALSE))
    session$sendCustomMessage("toggleCodingMode", list(active = FALSE))
    session$sendCustomMessage("toggleProcessMode", list(active = FALSE))
    # Gizli DOM akış seçicisini de varsayılana döndür ve bayat
    # input$chat_process_flow değerini boş değerle ez. Aksi halde sıfırlama
    # yalnızca sunucu/localStorage değerini temizler; bir sonraki
    # toggleProcessMode(active=TRUE) yayını eski akışı yeniden kalıcılaştırırdı.
    session$sendCustomMessage("resetProcessFlowSelect", list())
    session$sendCustomMessage("syncExcelDeepThinkingToChat", list(deep_thinking = FALSE, level = "low"))
    session$sendCustomMessage("syncCodingDeepThinkingToChat", list(deep_thinking = FALSE, level = "low"))
    # Tüm araçlar pasif olduğundan model seçim kilidini serbest bırak.
    session$sendCustomMessage("setToolModelLock", list(active = FALSE))

    # Yapılandırma sayfasındaki girdi bileşenlerini varsayılana çek; aksi halde
    # sıfırlama sonrası görünür seçimler bayat kalır ve sonraki "Ayarları Kaydet"
    # ile eski değerler yeniden uygulanır (görünür/uygulanan durum uyumsuzluğu).
    ycfg_ns <- "settings_yapilandirma_module-"
    updateSelectInput(session, paste0(ycfg_ns, "model_selection"), selected = unname(default_model))
    updateSelectInput(session, paste0(ycfg_ns, "font_size"), selected = "medium")
    updateSelectInput(session, paste0(ycfg_ns, "ai_expert_talk_length"), selected = "orta")
    updateSelectInput(session, paste0(ycfg_ns, "ai_expert_talk_frequency"), selected = "orta")
    updateSelectInput(session, paste0(ycfg_ns, "ai_expert_talk_style"), selected = "profesyonel")
    updateSelectInput(session, paste0(ycfg_ns, "image_size"), selected = "1024x1024")
    updateSelectInput(session, paste0(ycfg_ns, "summary_detail_level"), selected = "standard")
    updateSelectInput(session, paste0(ycfg_ns, "summary_focus_mode"), selected = "general")
    updateSelectInput(session, paste0(ycfg_ns, "analysis_detail_level"), selected = "standart")
    updateNumericInput(session, paste0(ycfg_ns, "claude_code_timeout"), value = claude_code_config$timeout_seconds)
    updateSliderInput(session, paste0(ycfg_ns, "music_volume"), value = 0.3)
    # Şerit radyosu görünür varsayılana (Zengin Deneyim) çekilir; seçimsiz
    # bırakmak radyo grubunu belirsiz duruma düşürüyordu. Kalıcı tercih
    # ask_once kalır; kullanıcı kaydederse görünen seçim kalıcılaşır.
    yapilandirma$temp_startup_lane("rich_lane")
    updateRadioButtons(session, paste0(ycfg_ns, "startup_experience_lane"), selected = "rich_lane")
    session$sendCustomMessage("applyStartupLane", list(lane = "rich_lane"))

    reset_true_checkboxes <- c(
      "enable_timestamps",
      "enable_typing_indicator",
      "enable_animations",
      "enable_widescreen",
      "enable_streaming",
      "enable_tool_backgrounds",
      "enable_followups",
      "show_intro_animation"
    )
    for (input_id in reset_true_checkboxes) {
      updateCheckboxInput(session, paste0(ycfg_ns, input_id), value = TRUE)
    }

    reset_false_checkboxes <- c(
      "enable_tts_audio",
      "enable_background_music",
      "enable_ai_expert",
      "enable_rdata_tools",
      "enable_mcp_tools",
      "enable_summarization_tools",
      "enable_coding_tools",
      "enable_process_tools",
      "enable_app_expert_tools",
      "enable_image_tools"
    )
    for (input_id in reset_false_checkboxes) {
      updateCheckboxInput(session, paste0(ycfg_ns, input_id), value = FALSE)
    }

    # Bu iki özel switch plain HTML <input type="checkbox"> olarak çizilir;
    # updateCheckboxInput() yalnızca Shiny checkboxInput() bağları için yeterlidir.
    shinyjs::runjs(sprintf("$('#%s').prop('checked', false).trigger('change');", paste0(ycfg_ns, "image_quality_hd")))
    shinyjs::runjs(sprintf("$('#%s').prop('checked', false).trigger('change');", paste0(ycfg_ns, "analysis_deep_thinking")))

    # localStorage'ı önce temizle. Aşağıdaki tema ve araç arka plan ayarları
    # varsayılana çekilirken yeniden persist edilir; sıralama korunmalıdır.
    session$sendCustomMessage("clearSettings", list())

    # Temayı koyu varsayılana döndür (istemci tarafı animasyon ile uygular)
    session$sendCustomMessage("setMergenTheme", list(theme = "dark"))

    # Araç arka plan animasyonlarını varsayılana (açık) döndür ve uygula
    mb_tool_bg_apply_to_client(session, mb_tool_bg_default_enabled())

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
# ==============================================================================
# Dosya Adı: server.R
# Açıklama:  Shiny uygulamasının ana sunucu (server) fonksiyonu.
#            Kullanıcı oturumlarını başlatır, kimlik doğrulama işlemlerini yönetir,
#            tüm modülleri (sohbet, dosyalar, ayarlar, TTS/STT, vb.) bağlar ve
#            uygulamanın reaktif durumunu (values) yönetir.
# ==============================================================================

server <- function(input, output, session) {

  # ============================================================================
  # BÖLÜM 1: OTURUM ÖN BELLEKLEME VE ALTYAPI
  # ============================================================================
  session_cache <- sessionCacheInit(session)
  user_config_rv <- reactiveVal(NULL)
  mcp_saved_path <- session_cache$mcp_saved_path
  cache_mcp_file_locally <- session_cache$cache_mcp_file_locally
  update_mcp_registry_snapshot <- session_cache$update_mcp_registry_snapshot

  # Widget bağımlılık çıktılarını başlat (modüler)
  widgetDependencyOutputsInit(output)

  # ============================================================================
  # BÖLÜM 2: KİMLİK DOĞRULAMA VE KULLANICI OTURUMU (SSO DESTEKLİ)
  # ============================================================================

  # SSO modülünü başlat (SSO_ENABLED=FALSE ise otomatik geçiş yapar)
  sso_state <- ssoAuthServer("sso_module")

  # --- Kimlik çözümleme ve oturum kurulumu ---
  # SSO kapalı (yerel geliştirme): Senkron akış, mevcut davranış korunur
  # SSO aktif (Keycloak): Token doğrulandıktan sonra observer ile güncellenir
  if (!isTRUE(SSO_ENABLED)) {
    # ===== YEREL GELİŞTİRME MODU =====
    user_identity <- resolveUserIdentity()
    system_username <- user_identity$username
    current_user_id <- get_or_create_user(system_username)

    session$userData$user_identity   <- user_identity
    session$userData$user_first_name <- user_identity$first_name
    session$userData$system_username  <- system_username
    session$userData$user_id         <- current_user_id
    session$userData$sso_active      <- FALSE
    session$userData$auth_source     <- "local"
    session$userData$auth_initialized <- TRUE

    session$userData$user_config <- list(
      name             = user_identity$full_name,
      icon             = user_config$icon,
      userId           = as.character(current_user_id),
      auth_level       = user_config$auth_level,
      sicil            = NULL, email = NULL, first_name = user_identity$first_name,
      last_name        = NULL, sektor = NULL, department = NULL,
      mudurluk         = NULL, masraf_yeri_kodu = NULL
    )
    user_config_rv(session$userData$user_config)

    cache_dir <- session_cache$setup_user_session(current_user_id)
  } else {
    # ===== SSO (KEYCLOAK) MODU =====
    # Geçici değerler: Modüller bu değerlerle başlatılır,
    # token doğrulandığında observer gerçek değerlerle günceller
    current_user_id <- 0L
    session$userData$auth_initialized <- FALSE
    session$userData$sso_active <- TRUE

    # Token doğrulandığında oturum bilgilerini kur
    observeEvent(sso_state$authenticated, {
      req(isTRUE(sso_state$authenticated))
      claims <- sso_state$user_claims

      ui <- resolveUserIdentity(sso_claims = claims)
      uname <- ui$username
      uid <- get_or_create_user(uname, sso_claims = claims)

      session$userData$user_identity   <- ui
      session$userData$user_first_name <- ui$first_name
      session$userData$system_username  <- uname
      session$userData$user_id         <- uid
      session$userData$auth_source     <- "keycloak"

      session$userData$user_config <- list(
        name             = ui$full_name,
        icon             = user_config$icon,
        userId           = ui$sicil %||% as.character(uid),
        auth_level       = ui$auth_level %||% user_config$auth_level,
        sicil            = ui$sicil, email = ui$email,
        first_name       = ui$first_name, last_name = ui$last_name,
        sektor           = ui$sektor, department = ui$department,
        mudurluk         = ui$mudurluk, masraf_yeri_kodu = ui$masraf_yeri_kodu
      )
      user_config_rv(session$userData$user_config)

      session_cache$setup_user_session(uid)
      session$userData$auth_initialized <- TRUE

      log_info("SSO oturum kuruldu: kullanıcı={uname}, id={uid}, yetki={ui$auth_level}")
    }, ignoreInit = TRUE, once = TRUE)
  }

  # Etkin kullanıcı kimliğini her kullanım anında oturumdan çöz.
  # SSO akışında başlangıçta 0L gelebilir; doğrulama tamamlanınca
  # session$userData$user_id gerçek değeri taşır.
  resolve_current_user_id <- function() {
    resolve_effective_user_id(
      session = session,
      current_user_id = current_user_id
    )
  }

  current_user_id_provider <- function() {
    resolve_current_user_id()
  }

  # API anahtarı modülünü bağla
  api_key <- apiKeyServer("api_key", serviceDesk = SERVICE_DESK, api_config = api_config)

  # ============================================================================
  # BÖLÜM 3: PERFORMANS, SAĞLIK VE DESTEK MODÜLLERİ
  # ============================================================================
  perf_tracker <- performanceStatsServer("perf_stats", current_user_id)
  healthServer("health_module", perf_tracker = perf_tracker)
  destekServer("destek_module", current_user_id = current_user_id_provider)

  # ============================================================================
  # BÖLÜM 4: AYARLAR VE İLERİ REFERANSLAR
  # ============================================================================
  settings_data <- settingsInit(session = session, parent_session = session)

  # İleri referanslar: Bu fonksiyonlar daha sonra tanımlanacak ama şimdiden observer'lara geçirilmeli
  # Sarmalayıcılar kullanarak gecikmeli bağlama sağlanır
  welcome_fns <- new.env(parent = emptyenv())
  render_welcome_screen <- function(...) {
    fn <- welcome_fns$render_welcome_screen
    if (is.function(fn)) fn(...) else invisible(NULL)
  }
  start_new_chat <- function(...) {
    fn <- welcome_fns$start_new_chat
    if (is.function(fn)) fn(...) else invisible(NULL)
  }

  # send_message için ileri referans (R/server_send_message.R modülünden atanacak)
  send_message_fns <- new.env(parent = emptyenv())
  send_message <- function(...) send_message_fns$send_message(...)
    
  # Claude Code modülü (settings_data hazır olduktan sonra başlatılır)
  claudeCodeServer("claude_code_module",
                   current_user_id = current_user_id,
                   settings_data = settings_data,
                   user_first_name = session$userData$user_first_name)

  # Görsel ayarları senkronizasyonunu başlat (Sohbet → Ayarlar, modüler)
  visualSettingsSyncInit(input, settings_data)
  
  # load_chat_in_progress tanımı burada kalabilir
  load_chat_in_progress <- reactiveVal(FALSE)
  
  # Sohbet header çıktılarını başlat (modüler) - sadece settings_data kullanıyor
  chatOutputsInit(output, settings_data)
  
  # ============================================================================
  # BÖLÜM 5: MEDYA MODÜLLERİ (YZ İŞLEME, TTS, STT, MÜZİK)
  # ============================================================================
  feedback_modal <- feedbackServer("feedback_module", current_user_id)
  ai_processor <- aiProcessingServer("ai_proc")
  tts_processor <- ttsProcessingServer("tts_proc")
  tts_visualizer <- ttsVisualizerServer("tts_viz", settings_data)
  musicHandlersInit(input, session, settings_data)
  ai_expert <- aiExpertServer("ai_expert_module", settings_data, tts_processor, tts_visualizer)
  stt_data <- sttServer("stt_module", parent_session = session, settings = settings_data)

  # ============================================================================
  # BÖLÜM 6: DOSYA YÖNETİMİ VE ÖNİZLEME
  # ============================================================================
  filePreview <- filePreviewServer("file_preview")

  # Hafif sıklet takip sorusu önerisi oluşturucu
  fallback_followup_tool <- create_followup_suggestions_tool()
  followup_tools <- followupSuggestionsServer("followup_module")
  if (is.null(followup_tools) || is.null(followup_tools$generate)) {
    followup_tools <- fallback_followup_tool
  }
  
  init_docx_preview_js(session)
  
  # SSO akışında gerçek kullanıcı kimliği başlangıçta hazır olmayabilir.
  # Bu yüzden ilk değerleri boş başlatıp kimlik doğrulama tamamlanınca yükle.
  initial_feedback <- list(
    liked = character(0),
    disliked = character(0)
  )
  
  # ============================================================================
  # BÖLÜM 7: ÇEKİRDEK REAKTİF DEĞERLER VE DURUM YÖNETİMİ
  # ============================================================================
    values <- reactiveValues(
      messages = list(),
      saved_chats = list(),
      show_welcome = TRUE,
      current_chat_id = NULL,
      last_request_time = NULL,
      is_sending = FALSE,
      typing = FALSE,
      liked_messages = initial_feedback$liked,
      disliked_messages = initial_feedback$disliked,
      current_font_size = "medium",
      temp_files = list()
    )

    session$userData$welcome_screen_attached <- FALSE

    # Geri bildirimleri gerçek kullanıcı kimliği ile yeniden yükle.
    sync_feedback_from_db <- function() {
      effective_user_id <- resolve_current_user_id()
      if (effective_user_id <= 0) {
        return(invisible(NULL))
      }

      all_feedback <- load_feedback_from_db(effective_user_id)
      values$liked_messages <- all_feedback$liked
      values$disliked_messages <- all_feedback$disliked
      invisible(NULL)
    }

    if (isTRUE(SSO_ENABLED)) {
      observeEvent(sso_state$authenticated, {
        req(isTRUE(sso_state$authenticated), isTRUE(session$userData$auth_initialized))
        sync_feedback_from_db()
      }, ignoreInit = TRUE, once = TRUE)
    } else {
      sync_feedback_from_db()
    }
        
    # Sohbet dışa aktarma bağlantıları (kopyala & dışa aktar)
    chatExportInit(input, output, session, values, user_display_name = session$userData$user_config$name)

    # Chartlab referanslarını çözümlemek için grafik deposu
    if (is.null(session$userData$chart_store)) session$userData$chart_store <- list()
      
  stop_generation <- reactiveVal(FALSE)
  file_to_add <- reactiveVal(NULL)
  session_files <- reactiveVal(list())
  active_request_id <- reactiveVal(NULL)
  quick_action_skip_mcp <- reactiveVal(FALSE)
  
  # ============================================================================
  # BÖLÜM 8: GÖZLEMCİLER VE UI BAĞLANTILARI
  # ============================================================================
  quickActionsInit(
    input = input,
    session = session,
    values = values,
    settings_data = settings_data,
    session_files = session_files,
    quick_action_skip_mcp = quick_action_skip_mcp,
    output = output,
    current_user_id = current_user_id
  )
  
  settingsObserversInit(input, session, values, settings_data)

    sessionTimeoutServer(
      "session_timeout",
      idle_minutes    = 30,
      activity_inputs = c("user_input", "send_btn", "send_prompt_from_js")
    )
                
    # Geçici dosya (temp_files) erişimi için 'values' reaktif nesnesini dosya yöneticisine ilet
    file_manager_data <- fileManagerServer(
      "file_manager_module",
      new_file_trigger = reactive({ file_to_add() }),
      session_files_reactive = session_files,
      mcp_enabled_reactive = reactive({ isTRUE(settings_data$enable_mcp_tools) }),
      user_id = current_user_id,
      settings_data = settings_data
    )

    # SSO doğrulaması tamamlandığında kullanıcı dosyalarını tek sefer yükle
    observeEvent(sso_state$authenticated, {
      req(isTRUE(sso_state$authenticated))
      if (is.function(file_manager_data$refresh_persisted_files)) {
        file_manager_data$refresh_persisted_files("auth_ready")
      }
    }, ignoreInit = TRUE, once = TRUE)
    
  # Özetleme modülü erişimi için dosya yöneticisi verilerini oturumda sakla
  session$userData$file_manager_data <- file_manager_data
  
  # Sohbet UI gözlemcilerini başlat (values artık mevcut)
  chatUIObserversInit(input, session, values, start_new_chat, send_message, render_welcome_screen, settings_data)
  
  # Navigasyon/sekme değişikliği gözlemcilerini başlat (modüler)
  navigationObserversInit(input, session, values, render_welcome_screen)
  
  # Başlangıç ve oturum ilk yükleme gözlemcilerini başlat (modüler)
  startupObserversInit(input, session, values, render_welcome_screen, current_user_id)

  # Derin uzay giriş ekranı gözlemcilerini başlat (modüler)
  startupScreenObserversInit(input, session, settings_data)

  # AI Uzman işleyicilerini başlat (karşılama, sayfa rehberliği, boşta konuşma)
  aiExpertHandlersInit(input, session, values, settings_data,
                        ai_expert, tts_processor, current_user_id,
                        chat_history_rv = reactive(values$messages))
  
  # Depolama/localStorage gözlemcilerini başlat (modüler)
  storageObserversInit(input, session, output, values, settings_data, chat_rebind_all_charts)
  
  # Dosya gözlemcilerini başlat (modüler) - session_files ve file_manager_data artık mevcut
  fileObserversInit(input, session, settings_data, session_files, file_manager_data, current_user_id)
  
  # Dosya tıklama gözlemcilerini başlat (kaynak, analiz, önizleme)
  fileClickObserversInit(input, session, settings_data, api_config, filePreview, file_manager_data, session_files)
    
  # Uygulamada görünen dosyaları (+ özetleri) saklamak için merkezi yer
  if (is.null(session$userData$file_summaries)) session$userData$file_summaries <- list()
  
  saved_chats_data <- savedChatsServer("saved_chats_module", saved_chats = reactive(values$saved_chats))

  # Kayıtlı sohbet gözlemcilerini başlat (saved_chats_data artık mevcut)
  savedChatsObserversInit(input, output, session, values, settings_data,
                           saved_chats_data, current_user_id, load_chat_in_progress)

  # Söyleşi içerik arama modülünü başlat
  chatSearchInit(input, session, current_user_id_provider, function(chat_id) {
    shinyjs::runjs(sprintf(
      "Shiny.setInputValue('welcome_load_chat_id', '%s', {priority: 'event'});",
      chat_id
    ))
  })

  # Görsel galerisi modülünü başlat
  gallery_data <- imageGalleryServer("image_gallery_module", current_user_id_provider)
  
  observeEvent(sso_state$authenticated, {
    req(isTRUE(sso_state$authenticated))

    if (is.function(gallery_data$refresh)) {
      gallery_data$refresh()
    }
  }, ignoreInit = TRUE, once = TRUE)

  # Görsel galerisi gözlemcilerini başlat
  imageGalleryObserversInit(input, session, values, settings_data,
                             gallery_data, saved_chats_data,
                             current_user_id, load_chat_in_progress)

  # Hoş geldin ekranı işleyicilerini başlat (modüler)
  # Gerçek fonksiyonlar welcome_fns ortamına atanır, sarmalayıcılar bunları çağırır
  welcome_handlers <- welcomeHandlersInit(
    session, values, saved_chats_data, session_files,
    filePreview, current_user_id, file_manager_data,
    user_first_name = session$userData$user_first_name
  )
  welcome_fns$render_welcome_screen <- welcome_handlers$render_welcome_screen
  welcome_fns$start_new_chat <- welcome_handlers$start_new_chat

  # İndirme ve dosya gösterge çıktılarını başlat (modüler)
  downloadOutputsInit(output, session, session_files, current_user_id)
  
  historyServer("history_module", all_messages = reactive(values$saved_chats))
    
  # Mesaj arama bağlantıları
  messageSearchInit(input, session, values, reactive(values$messages))
                
    # ==========================================================================
    # BÖLÜM 9: SOHBET MOTORU VE LLM ENTEGRASYONU
    # ==========================================================================
    reset_chat_state <- function() chat_reset_state(session, values)
 
    add_message <- function(content, type = "user", html = NULL, followups = NULL,
                            audio_src = NULL, audio_voice = NULL) {
      effective_user_id <- resolve_current_user_id()

      chat_add_message(
            session, values, settings_data, output,
            content, type, html, effective_user_id,
            followups = followups,
            audio_src = audio_src,
            audio_voice = audio_voice
      )
    }
    
    # LLM yanıt işleyicilerini başlat (modüler)
    llm_handlers <- llmResponseHandlersInit(
      session = session,
      values = values,
      settings_data = settings_data,
      ai_processor = ai_processor,
      perf_tracker = perf_tracker,
      active_request_id = active_request_id,
      stop_generation = stop_generation,
      reset_chat_state_fn = reset_chat_state,
      add_message_fn = add_message,
      trigger_tts_fn = trigger_tts_for_message,
      followup_tools = followup_tools,
      fallback_followup_tool = fallback_followup_tool,
      api_config = api_config
    )
    generate_non_streaming_stoppable <- llm_handlers$generate_non_streaming_stoppable
    
  # Sohbet giriş observer'larını başlat (modüler)
  chatInputObserversInit(
    input, session, values, settings_data,
    stop_generation, active_request_id,
    reset_chat_state, send_message,
    current_user_id, file_manager_data,
    session_files, file_to_add, stt_data
  )
  
  # Çeşitli UI observer'larını başlat (modüler)
  miscObserversInit(
    input, output, session, values,
    file_manager_data, filePreview, add_message,
    api_key, user_config_rv, pool
  )
  
  # Sohbet eylemi bağlantıları (beğen/beğenme/yeniden oluştur/düzenle)
  chatActionsInit(
    input, session, values,
    current_user_id      = current_user_id,
    send_message_fn      = send_message,
    stop_generation      = stop_generation,
    reset_chat_state     = reset_chat_state,
    feedback_modal       = feedback_modal
  )
                                                     
    generate_title_from_prompt <- function(prompt, max_len = 60) {
      chat_generate_title_from_prompt(prompt, max_len)
    }
 
    simulate_streaming_stoppable <- function(full_response, followups = NULL, on_complete = NULL, on_start = NULL, tts_engine = NULL, tts_voice = NULL) {
      chat_simulate_streaming(
        full_response,
        session,
        values,
        settings_data,
        output,
        stop_generation,
        followups = followups,
        on_complete = on_complete,
        on_start = on_start,
        tts_engine = tts_engine,
        tts_voice = tts_voice
      )
    }
 
    # TTS işleyicilerini başlat (modüler)
    tts_handlers <- ttsHandlersInit(session, values, settings_data, tts_processor, tts_visualizer, stop_generation)
    trigger_tts_for_message <- tts_handlers$trigger_tts_for_message
    attach_tts_audio <- tts_handlers$attach_tts_audio
 
    send_message_handlers <- sendMessageInit(
      session = session,
      input = input,
      output = output,
      values = values,
      settings_data = settings_data,
      session_files = session_files,
      file_manager_data = file_manager_data,
      current_user_id = current_user_id,
      stop_generation = stop_generation,
      active_request_id = active_request_id,
      quick_action_skip_mcp = quick_action_skip_mcp,
      perf_tracker = perf_tracker,
      ai_processor = ai_processor,
      tts_processor = tts_processor,
      followup_tools = followup_tools,
      fallback_followup_tool = fallback_followup_tool,
      api_config = api_config,
      add_message_fn = add_message,
      reset_chat_state_fn = reset_chat_state,
      simulate_streaming_stoppable_fn = simulate_streaming_stoppable,
      cache_mcp_file_locally_fn = cache_mcp_file_locally,
      update_mcp_registry_snapshot_fn = update_mcp_registry_snapshot,
      saved_chats_data = saved_chats_data,
      generate_non_streaming_stoppable_fn = generate_non_streaming_stoppable
    )
 
    # send_message fonksiyonunu modülden al ve ortama ata
    send_message_fns$send_message <- send_message_handlers$send_message
}
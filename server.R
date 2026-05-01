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

	# Kullanıcı kimliği, user_config_rv ve canlı current_user_id provider tek
	# initialization object üzerinden kurulur. Böylece server.R doğrudan
	# session$userData kimlik alanlarını elle yönetmez.
	user_session <- serverInitUserSession(
	  session = session,
	  session_cache = session_cache,
	  sso_state = sso_state,
	  base_user_config = user_config,
	  sso_enabled = SSO_ENABLED,
	  touch_session_fn = function(uid) {
		if (exists("perf_tracker", inherits = FALSE) &&
			is.list(perf_tracker) &&
			is.function(perf_tracker$touch_session)) {
		  perf_tracker$touch_session(uid)
		}
	  }
	)

	user_config_rv <- user_session$user_config_rv
	resolve_current_user_id <- user_session$resolve_current_user_id
	current_user_id_provider <- user_session$current_user_id_provider

  # API anahtarı modülünü bağla
  api_key <- apiKeyServer("api_key", serviceDesk = SERVICE_DESK, api_config = api_config)

  # ============================================================================
  # BÖLÜM 3: PERFORMANS, SAĞLIK VE DESTEK MODÜLLERİ
  # ============================================================================
  perf_tracker <- performanceStatsServer("perf_stats", current_user_id_provider)
  healthServer("health_module", perf_tracker = perf_tracker)
  destekServer("destek_module", current_user_id = current_user_id_provider)

  # ============================================================================
  # BÖLÜM 4: AYARLAR VE İLERİ REFERANSLAR
  # ============================================================================
  settings_data <- settingsInit(session = session, parent_session = session)

  # İleri referans sarmalayıcılarını başlat
  forward_refs <- serverInitForwardRefs(session)

  welcome_fns <- forward_refs$welcome_fns
  render_welcome_screen <- forward_refs$render_welcome_screen
  start_new_chat <- forward_refs$start_new_chat
  send_message_fns <- forward_refs$send_message_fns
  send_message <- forward_refs$send_message
    
  # Claude Code modülü (settings_data hazır olduktan sonra başlatılır)
	claudeCodeServer(
	  "claude_code_module",
	  current_user_id = current_user_id_provider,
	  settings_data = settings_data,
	  user_first_name = function() {
		session$userData$user_first_name %||%
		  session$userData$user_config$first_name %||%
		  ""
	  }
	)

  # Görsel ayarları senkronizasyonunu başlat (Sohbet → Ayarlar, modüler)
  visualSettingsSyncInit(input, settings_data)
  
  # load_chat_in_progress tanımı burada kalabilir
  load_chat_in_progress <- reactiveVal(FALSE)
  
  # Sohbet header çıktılarını başlat (modüler) - sadece settings_data kullanıyor
  chatOutputsInit(output, settings_data)
  
  # ============================================================================
  # BÖLÜM 5: MEDYA MODÜLLERİ (YZ İŞLEME, TTS, STT, MÜZİK)
  # ============================================================================
  feedback_modal <- feedbackServer("feedback_module", current_user_id_provider)
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
  
  # ============================================================================
  # BÖLÜM 7: ÇEKİRDEK REAKTİF DEĞERLER VE DURUM YÖNETİMİ
  # ============================================================================
  state_bundle <- serverInitSessionState(
    session = session,
    resolve_current_user_id = resolve_current_user_id,
    sso_state = sso_state
  )

  values <- state_bundle$values
  stop_generation <- state_bundle$stop_generation
  file_to_add <- state_bundle$file_to_add
  session_files <- state_bundle$session_files
  active_request_id <- state_bundle$active_request_id
  quick_action_skip_mcp <- state_bundle$quick_action_skip_mcp
  
	session$onEnded(function() {
	  try(stop_generation(TRUE), silent = TRUE)
	  try(cleanup_worker_tasks_for_session(session$token), silent = TRUE)
	})

  # Sohbet dışa aktarma bağlantıları (kopyala & dışa aktar)
	chatExportInit(
	  input,
	  output,
	  session,
	  values,
	  user_display_name = function() {
		session$userData$user_config$name %||%
		  session$userData$user_first_name %||%
		  "Kullanıcı"
	  }
	)

  # Chartlab referanslarını çözümlemek için grafik deposu
  if (is.null(session$userData$chart_store)) session$userData$chart_store <- list()
  
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
	  current_user_id = current_user_id_provider,
	  send_message_fn = send_message
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
	  user_id = current_user_id_provider,
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
	startupObserversInit(
	  input = input,
	  session = session,
	  values = values,
	  render_welcome_screen = render_welcome_screen,
	  current_user_id = current_user_id_provider,
	  sso_state = sso_state
	)

  # Derin uzay giriş ekranı gözlemcilerini başlat (modüler)
  startupScreenObserversInit(input, session, settings_data)

  # AI Uzman işleyicilerini başlat (karşılama, sayfa rehberliği, boşta konuşma)
  aiExpertHandlersInit(input, session, values, settings_data,
                      ai_expert, tts_processor, current_user_id_provider,
                      chat_history_rv = reactive(values$messages))
  
  # Depolama/localStorage gözlemcilerini başlat (modüler)
  storageObserversInit(input, session, output, values, settings_data, chat_rebind_all_charts)
  
  # Dosya gözlemcilerini başlat (modüler) - session_files ve file_manager_data artık mevcut
  fileObserversInit(input, session, settings_data, session_files, file_manager_data, current_user_id_provider)
  
  # Dosya tıklama gözlemcilerini başlat (kaynak, analiz, önizleme)
  fileClickObserversInit(input, session, settings_data, api_config, filePreview, file_manager_data, session_files)
    
  # Uygulamada görünen dosyaları (+ özetleri) saklamak için merkezi yer
  if (is.null(session$userData$file_summaries)) session$userData$file_summaries <- list()
  
  saved_chats_data <- savedChatsServer("saved_chats_module", saved_chats = reactive(values$saved_chats))

  # Kayıtlı sohbet gözlemcilerini başlat (saved_chats_data artık mevcut)
	savedChatsObserversInit(
	  input,
	  output,
	  session,
	  values,
	  settings_data,
	  saved_chats_data,
	  current_user_id_provider,
	  load_chat_in_progress
	)

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
                           current_user_id_provider, load_chat_in_progress)

  # Hoş geldin ekranı işleyicilerini başlat (modüler)
  # Gerçek fonksiyonlar welcome_fns ortamına atanır, sarmalayıcılar bunları çağırır
welcome_handlers <- welcomeHandlersInit(
  session, values, saved_chats_data, session_files,
  filePreview, current_user_id_provider, file_manager_data,
  user_first_name = function() {
    session$userData$user_first_name %||%
    session$userData$user_config$first_name %||%
    ""
  }
)

  welcome_fns$render_welcome_screen <- welcome_handlers$render_welcome_screen
  welcome_fns$start_new_chat <- welcome_handlers$start_new_chat

  # İndirme ve dosya gösterge çıktılarını başlat (modüler)
  downloadOutputsInit(output, session, session_files, current_user_id_provider)
  
	historyServer(
	  "history_module",
	  all_messages = reactive(values$saved_chats),
	  current_user_id = function() {
		resolve_current_user_id()
	  }
	)
    
  # Mesaj arama bağlantıları
  messageSearchInit(input, session, values, reactive(values$messages))
                
    # ==========================================================================
    # BÖLÜM 9: SOHBET MOTORU VE LLM ENTEGRASYONU
    # ==========================================================================
    chat_runtime <- serverInitChatRuntime(
      session = session,
      values = values,
      settings_data = settings_data,
      output = output,
      resolve_current_user_id = resolve_current_user_id,
      stop_generation = stop_generation
    )

    reset_chat_state <- chat_runtime$reset_chat_state
    add_message <- chat_runtime$add_message

    # TTS işleyicisi gerçek fonksiyon atanmadan önce güvenli bir yer tutucu tanımla.
    # Böylece gelecekte llmResponseHandlersInit içinde erken zorlama olursa kırılma yaşanmaz.
    trigger_tts_for_message <- function(...) invisible(NULL)
    
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
	  current_user_id_provider, file_manager_data,
	  session_files, file_to_add, stt_data
	)
  
  # Çeşitli UI observer'larını başlat (modüler) 
  admin_pool <- if (exists("pool", envir = .GlobalEnv, inherits = FALSE)) {
    get("pool", envir = .GlobalEnv, inherits = FALSE)
  } else {
    NULL
  }
  
  miscObserversInit(
    input, output, session, values,
    file_manager_data, filePreview, add_message,
    api_key, user_config_rv, admin_pool
  )
  
  # Sohbet eylemi bağlantıları (beğen/beğenme/yeniden oluştur/düzenle)
	chatActionsInit(
	  input, session, values,
	  current_user_id      = current_user_id_provider,
	  send_message_fn      = send_message,
	  stop_generation      = stop_generation,
	  reset_chat_state     = reset_chat_state,
	  feedback_modal       = feedback_modal
	)
                                                     
    generate_title_from_prompt <- chat_runtime$generate_title_from_prompt
    simulate_streaming_stoppable <- chat_runtime$simulate_streaming_stoppable
 
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
	  current_user_id = current_user_id_provider,
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
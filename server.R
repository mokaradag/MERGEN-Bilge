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

	runtime_ctx <- serverRuntimeContextInit(
	  session = session,
	  session_cache = session_cache,
	  sso_state = sso_state,
	  user_session = user_session
	)

	identity <- runtime_ctx$identity

	user_config_rv <- identity$user_config_rv
	resolve_current_user_id <- identity$resolve_current_user_id
	current_user_id_provider <- identity$current_user_id_provider
	current_user_first_name <- identity$get_first_name
	current_user_display_name <- identity$get_display_name

  # API anahtarı modülünü bağla
  api_key <- apiKeyServer("api_key", serviceDesk = SERVICE_DESK, api_config = api_config)

  # ============================================================================
  # BÖLÜM 3: PERFORMANS, SAĞLIK VE DESTEK MODÜLLERİ
  # ============================================================================
  service_modules <- serverBindServiceModules(
    current_user_id_provider = current_user_id_provider
  )

  perf_tracker <- service_modules$perf_tracker

  # ============================================================================
  # BÖLÜM 4: AYARLAR VE İLERİ REFERANSLAR
  # ============================================================================
  settings_bundle <- serverBindSettingsAndRefs(
    input = input,
    output = output,
    session = session,
    runtime_ctx = runtime_ctx,
    current_user_id_provider = current_user_id_provider,
    user_first_name_fn = function(default = "") {
      current_user_first_name(default = default)
    }
  )

  runtime_ctx <- settings_bundle$runtime_ctx
  settings_data <- settings_bundle$settings_data
  welcome_fns <- settings_bundle$welcome_fns
  render_welcome_screen <- settings_bundle$render_welcome_screen
  start_new_chat <- settings_bundle$start_new_chat
  send_message_fns <- settings_bundle$send_message_fns
  send_message <- settings_bundle$send_message
  load_chat_in_progress <- settings_bundle$load_chat_in_progress
  
  # ============================================================================
  # BÖLÜM 5: MEDYA MODÜLLERİ (YZ İŞLEME, TTS, STT, MÜZİK)
  # ============================================================================
  media_modules <- serverBindMediaModules(
    input = input,
    session = session,
    settings_data = settings_data,
    current_user_id_provider = current_user_id_provider
  )

  feedback_modal <- media_modules$feedback_modal
  ai_processor <- media_modules$ai_processor
  tts_processor <- media_modules$tts_processor
  tts_visualizer <- media_modules$tts_visualizer
  ai_expert <- media_modules$ai_expert
  stt_data <- media_modules$stt_data

  # ============================================================================
  # BÖLÜM 6: DOSYA YÖNETİMİ VE ÖNİZLEME
  # ============================================================================
  file_prelude_modules <- serverBindFilePreludeModules(
    session = session,
    runtime_ctx = runtime_ctx
  )

  runtime_ctx <- file_prelude_modules$runtime_ctx

  file_runtime <- serverRuntimeRequireFileRuntime(
    runtime_ctx,
    require_prelude = TRUE,
    require_manager = FALSE
  )

  filePreview <- file_runtime$filePreview
  fallback_followup_tool <- file_runtime$fallback_followup_tool
  followup_tools <- file_runtime$followup_tools
  
  # ============================================================================
  # BÖLÜM 7: ÇEKİRDEK REAKTİF DEĞERLER VE DURUM YÖNETİMİ
  # ============================================================================
	runtime_ctx <- serverRuntimeAttachState(
	  runtime_ctx,
	  serverInitSessionState(
		session = session,
		identity = runtime_ctx$identity,
		sso_state = sso_state
	  )
	)

	values <- runtime_ctx$state$values
	stop_generation <- runtime_ctx$state$stop_generation
	file_to_add <- runtime_ctx$state$file_to_add
	session_files <- runtime_ctx$state$session_files
	active_request_id <- runtime_ctx$state$active_request_id
	quick_action_skip_mcp <- runtime_ctx$state$quick_action_skip_mcp
  
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
		current_user_display_name(default = "Kullanıcı")
	  }
	)

  # Chartlab deposu serverInitSessionState içinde merkezi olarak hazırlanır.
  
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
                
	file_manager_runtime <- serverBindFileManagerRuntime(
	  runtime_ctx = runtime_ctx,
	  new_file_trigger = reactive({ file_to_add() }),
	  session_files_reactive = session_files,
	  mcp_enabled_reactive = reactive({ isTRUE(settings_data$enable_mcp_tools) }),
	  settings_data = settings_data,
	  user_id_provider = current_user_id_provider
	)

	runtime_ctx <- file_manager_runtime$runtime_ctx

	file_runtime <- serverRuntimeRequireFileRuntime(
	  runtime_ctx,
	  require_prelude = TRUE,
	  require_manager = TRUE
	)

	file_manager_data <- file_runtime$file_manager_data
  
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
    
  # Dosya özet deposu serverInitSessionState içinde merkezi olarak hazırlanır.
  
  chat_persistence <- serverBindChatPersistenceModules(
    input = input,
    output = output,
    session = session,
    runtime_ctx = runtime_ctx,
    values = values,
    settings_data = settings_data,
    load_chat_in_progress = load_chat_in_progress,
    session_files = session_files,
    filePreview = filePreview,
    file_manager_data = file_manager_data,
    current_user_id_provider = current_user_id_provider,
    user_config_provider = function(default = NULL) {
      runtime_ctx$identity$get_user_config(default = default)
    },
    user_first_name_fn = function(default = "") {
      current_user_first_name(default = default)
    },
    welcome_fns = welcome_fns
  )

  runtime_ctx <- chat_persistence$runtime_ctx
  saved_chats_data <- chat_persistence$saved_chats_data
                
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

	runtime_ctx <- serverRuntimeAttachChat(runtime_ctx, chat_runtime)

	reset_chat_state <- runtime_ctx$chat$reset_chat_state
	add_message <- runtime_ctx$chat$add_message

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
	  cache_mcp_file_locally_fn = runtime_ctx$cache$cache_mcp_file_locally,
	  update_mcp_registry_snapshot_fn = runtime_ctx$cache$update_mcp_registry_snapshot,
	  saved_chats_data = saved_chats_data,
	  generate_non_streaming_stoppable_fn = generate_non_streaming_stoppable
	)
 
    # send_message fonksiyonunu modülden al ve ortama ata
    send_message_fns$send_message <- send_message_handlers$send_message
}
# server.R

server <- function(input, output, session) {

  # ==========================================================================
  # OTURUM ÖNBELLEK VE MCP KAYIT DEFTERİ MODÜLÜNÜ BAŞLAT (R/server_session_cache.R)
  # ==========================================================================
  session_cache <- sessionCacheInit(session)
  mcp_saved_path <- session_cache$mcp_saved_path
  cache_mcp_file_locally <- session_cache$cache_mcp_file_locally
  update_mcp_registry_snapshot <- session_cache$update_mcp_registry_snapshot
  
  # Widget bağımlılık çıktılarını başlat (modüler)
  widgetDependencyOutputsInit(output)
  
  # ---- Kullanıcı ve oturum başlatma ------------------------------------------

	# Sistemdeki kullanıcı adını al
	system_username <- Sys.info()["user"]

	# Veritabanından kalıcı kullanıcı kimliğini al veya oluştur
	current_user_id <- get_or_create_user(system_username)

	# Kullanıcı oturumu için önbellek dizinini yapılandır
	cache_dir <- session_cache$setup_user_session(current_user_id)

	# Expose username & (later) api key to this session
	session$userData$system_username <- system_username
	
	# Mount API key module (replaces old inline modal/handlers)
	api_key <- apiKeyServer("api_key", serviceDesk = SERVICE_DESK, api_config = api_config)
	
  # Expose user id to tools/resolvers
  session$userData$user_id <- current_user_id   

  # Initialize performance tracking module
  perf_tracker <- performanceStatsServer("perf_stats", current_user_id)
  
  # Mount health module
  healthServer("health_module", perf_tracker = perf_tracker)

  # --- Module Server Initialization (Yukarı Taşındı) ---
  settings_data <- settingsServer("settings_module", parent_session = session)

  # İleri referanslar: Bu fonksiyonlar daha sonra tanımlanacak ama şimdiden observer'lara geçirilmeli
  # Sarmalayıcılar kullanarak gecikmeli bağlama sağlanır
  welcome_fns <- new.env(parent = emptyenv())
  render_welcome_screen <- function(...) welcome_fns$render_welcome_screen(...)
  start_new_chat <- function(...) welcome_fns$start_new_chat(...)

  # send_message için ileri referans (R/server_send_message.R modülünden atanacak)
  send_message_fns <- new.env(parent = emptyenv())
  send_message <- function(...) send_message_fns$send_message(...)
  
  # NOT: quickActionsInit, settingsObserversInit, visualSettingsSyncInit, 
  # ve savedChatsObserversInit çağrıları values, session_files ve saved_chats_data
  # tanımlandıktan SONRA yapılmalıdır. Bu satırlar aşağıda uygun yere taşınmıştır.
  
  # Görsel ayarları senkronizasyonunu başlat (Sohbet → Ayarlar, modüler)
  # Bu, settings_data'ya bağımlı, values'a değil - burada kalabilir
  visualSettingsSyncInit(input, settings_data)
  
  # load_chat_in_progress tanımı burada kalabilir
  load_chat_in_progress <- reactiveVal(FALSE)
  
  # Sohbet UI gözlemcilerini başlat
  chatUIObserversInit(input, session, values, start_new_chat, send_message, render_welcome_screen, settings_data)
  
  # Navigasyon/sekme değişikliği gözlemcilerini başlat (modüler)
  navigationObserversInit(input, session, values, render_welcome_screen)
  
  # Başlangıç ve oturum ilk yükleme gözlemcilerini başlat (modüler)
  startupObserversInit(input, session, values, render_welcome_screen, current_user_id)
  
  # Depolama/localStorage gözlemcilerini başlat (modüler)
  storageObserversInit(input, session, output, values, settings_data, chat_rebind_all_charts)
  
  # Sohbet header çıktılarını başlat (modüler)
  chatOutputsInit(output, settings_data)
  
  # Dosya gözlemcilerini başlat (modüler)
  fileObserversInit(input, session, settings_data, session_files, file_manager_data, current_user_id)
  
  # Dosya tıklama gözlemcilerini başlat (kaynak, analiz, önizleme)
  fileClickObserversInit(input, session, settings_data, api_config, filePreview, file_manager_data, session_files)
  
  # Geri bildirim modülü
  feedback_modal <- feedbackServer("feedback_module", current_user_id)
        
  # Initialize AI processing module
  ai_processor <- aiProcessingServer("ai_proc")
  
  # Initialize TTS processing module
  tts_processor <- ttsProcessingServer("tts_proc")
  
  # Initialize TTS Visualizer
  tts_visualizer <- ttsVisualizerServer("tts_viz", settings_data)
  
  # Müzik yöneticisini başlat (modüler)
  musicHandlersInit(input, session, settings_data)
  
  # Initialize Speech-to-Text Module
  stt_data <- sttServer("stt_module", parent_session = session, settings = settings_data)
  
  # Initialize File Preview module (replaces preview outputs + modal helpers)
  filePreview <- filePreviewServer("file_preview")
  
  # Lightweight follow-up suggestion generator
  fallback_followup_tool <- create_followup_suggestions_tool()
  followup_tools <- followupSuggestionsServer("followup_module")
  if (is.null(followup_tools) || is.null(followup_tools$generate)) {
    followup_tools <- fallback_followup_tool
  }
  
  init_docx_preview_js(session)
  
  # Load existing feedback when the app starts
  initial_feedback <- load_feedback_from_db(current_user_id)
  
  # --- Core Reactive Values for the Application ---
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
		
	# chat export wiring (copy & export)
	chatExportInit(input, output, session, values, user_display_name = user_config$name)

	# chart store for resolving ```chartlab``` refs
	if (is.null(session$userData$chart_store)) session$userData$chart_store <- list()
	  
  chat_list_trigger <- reactiveVal(0)
  stop_generation <- reactiveVal(FALSE)
  file_to_add <- reactiveVal(NULL)
  session_files <- reactiveVal(list())
  last_activity <- reactiveVal(Sys.time())
  session_active <- reactiveVal(TRUE)
  processing_request <- reactiveVal(FALSE)
  active_request_id <- reactiveVal(NULL)
  quick_action_skip_mcp <- reactiveVal(FALSE)
  
  # ========================================================================
  # DEĞİŞKENLER TANIMLANDI - ŞİMDİ OBSERVER'LARI BAŞLATABİLİRİZ

  # ========================================================================
  
  # Hızlı eylem şablonları modülünü başlat (values ve session_files artık mevcut)
  quickActionsInit(input, session, values, settings_data,
                   session_files, send_message, quick_action_skip_mcp)
  
  # Ayar gözlemcilerini başlat (modüler)
  settingsObserversInit(input, session, values, settings_data)
  
	# Session timeout management (modulerized)
	sessionTimeoutServer(
	  "session_timeout",
	  idle_minutes    = 30,
	  activity_inputs = c("user_input", "send_btn", "send_prompt_from_js")
	)
	    		  
	# Pass values reactive to file manager for temp_files access
	file_manager_data <- fileManagerServer(
	  "file_manager_module",
	  new_file_trigger = reactive({ file_to_add() }),
	  session_files_reactive = session_files,
	  mcp_enabled_reactive = reactive({ isTRUE(settings_data$enable_mcp_tools) }),
	  user_id = current_user_id,
	  settings_data = settings_data  # YENİ: Settings modülünü ilet
	)
	
	# Store file manager data in session for summarization module access
	session$userData$file_manager_data <- file_manager_data
	
  # One place to store app-visible files (+ summaries)
  if (is.null(session$userData$file_summaries)) session$userData$file_summaries <- list()
  
  saved_chats_data <- savedChatsServer("saved_chats_module", saved_chats = reactive(values$saved_chats))

  # Kayıtlı sohbet gözlemcilerini başlat (saved_chats_data artık mevcut)
  savedChatsObserversInit(input, output, session, values, settings_data,
                           saved_chats_data, current_user_id, load_chat_in_progress)

  # Hoş geldin ekranı işleyicilerini başlat (modüler)
  # Gerçek fonksiyonlar welcome_fns ortamına atanır, sarmalayıcılar bunları çağırır
  welcome_handlers <- welcomeHandlersInit(
    session, values, saved_chats_data, session_files,
    filePreview, current_user_id, file_manager_data
  )
  welcome_fns$render_welcome_screen <- welcome_handlers$render_welcome_screen
  welcome_fns$start_new_chat <- welcome_handlers$start_new_chat

  # İndirme ve dosya gösterge çıktılarını başlat (modüler)
  downloadOutputsInit(output, session, session_files, current_user_id)
  
  historyServer("history_module", all_messages = reactive({
	all <- values$saved_chats
	if (length(values$messages) > 0) {
	  all$current_chat <- list(
		title = "Mevcut Söyleşi",
		messages = values$messages,
		timestamp = Sys.time(),
		message_count = length(values$messages)
	  )
	}
	return(all)
  }))
    
  # message search wiring
  messageSearchInit(input, session, values, reactive(values$messages))
	    		
	# LLM yanıt işleyicilerini başlat (modüler)
	# Bu modül non-streaming AI yanıtlarını işler
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
    api_key, user_config, pool
  )
  
  # chat action wiring (like/dislike/regenerate/edit)
  chatActionsInit(
	input, session, values,
	current_user_id      = current_user_id,
	send_message_fn      = send_message,
	stop_generation      = stop_generation,
	reset_chat_state     = reset_chat_state,
	feedback_modal       = feedback_modal
  )
  	  							     							         	  
	# --- Temel Sohbet Fonksiyonları (yardımcı fonksiyonlara sarmalanmış) ---
	reset_chat_state <- function() chat_reset_state(session, values)
 
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
 
	add_message <- function(content, type = "user", html = NULL, followups = NULL,
							audio_src = NULL, audio_voice = NULL) {
	  chat_add_message(
			session, values, settings_data, output,
			content, type, html, current_user_id,
			followups = followups,
			audio_src = audio_src,
			audio_voice = audio_voice
	  )
	}
 
	# TTS işleyicilerini başlat (modüler)
	tts_handlers <- ttsHandlersInit(session, values, settings_data, tts_processor, tts_visualizer, stop_generation)
	trigger_tts_for_message <- tts_handlers$trigger_tts_for_message
	attach_tts_audio <- tts_handlers$attach_tts_audio
 
	# ==========================================================================
	# MESAJ GÖNDERME MODÜLÜNÜ BAŞLAT (R/server_send_message.R)
	# Tüm bağımlılıklar tanımlandıktan sonra çağrılır
	# ==========================================================================
	send_message_handlers <- sendMessageInit(
	  session = session,
	  input = input,
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
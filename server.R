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

	identity <- serverRuntimeRequireIdentity(
	  runtime_ctx,
	  required_values = c("user_config_rv"),
	  required_functions = c(
	    "resolve_current_user_id",
	    "current_user_id_provider",
	    "get_first_name",
	    "get_display_name"
	  ),
	  owner = "server.R identity"
	)

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
  
  media_modules <- serverBindMediaModules(
    input = input,
    session = session,
    settings_data = settings_data,
    current_user_id_provider = current_user_id_provider
  )

  # Medya çıktıları chat engine bağımlılık bundle'ında doğrulanır.

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
		identity = identity,
		sso_state = sso_state
	  )
	)

	state <- serverRuntimeRequireState(
	  runtime_ctx,
	  required_values = c("values"),
	  required_functions = c(
	    "stop_generation",
	    "file_to_add",
	    "session_files",
	    "active_request_id",
	    "quick_action_skip_mcp"
	  ),
	  owner = "server.R state"
	)

	values <- state$values
	stop_generation <- state$stop_generation
	file_to_add <- state$file_to_add
	session_files <- state$session_files
	active_request_id <- state$active_request_id
	quick_action_skip_mcp <- state$quick_action_skip_mcp
  
	session$onEnded(function() {
	  try(stop_generation(TRUE), silent = TRUE)
	  try(cleanup_worker_tasks_for_session(session$token), silent = TRUE)
	})

  # Chartlab deposu serverInitSessionState içinde merkezi olarak hazırlanır.
  # Dosya özet deposu serverInitSessionState içinde merkezi olarak hazırlanır.
  
  # ============================================================================
  # BÖLÜM 8: GÖZLEMCİLER, DOSYA YÖNETİMİ VE SOHBET KALICILIĞI
  # ============================================================================
  core_runtime_bundle <- serverBuildCoreInteractionBundle(
    settings_data = settings_data,
    api_config = api_config,
    media_modules = media_modules,
    render_welcome_screen = render_welcome_screen,
    start_new_chat = start_new_chat,
    send_message = send_message,
    load_chat_in_progress = load_chat_in_progress,
    welcome_fns = welcome_fns,
    user_config_provider = function(default = NULL) {
      runtime_ctx$identity$get_user_config(default = default)
    },
    user_first_name_fn = function(default = "") {
      current_user_first_name(default = default)
    }
  )

  core_interaction <- serverBindCoreInteractionRuntime(
    input = input,
    output = output,
    session = session,
    runtime_ctx = runtime_ctx,
    core_bundle = core_runtime_bundle
  )

  runtime_ctx <- core_interaction$runtime_ctx
  saved_chats_data <- core_interaction$saved_chats_data
  file_manager_data <- core_interaction$file_manager_data
  filePreview <- core_interaction$filePreview

  admin_pool_ref <- if (exists("admin_pool", inherits = TRUE)) {
    get("admin_pool", inherits = TRUE)
  } else {
    NULL
  }

  chat_engine_deps <- serverBuildChatEngineDependencyBundle(
    settings_data = settings_data,
    api_key = api_key,
    user_config_rv = user_config_rv,
    perf_tracker = perf_tracker,
    saved_chats_data = saved_chats_data,
    send_message_fns = send_message_fns,
    send_message_proxy = send_message,
    api_config = api_config,
    media_modules = media_modules,
    admin_pool = admin_pool_ref
  )

  chat_engine <- serverBindChatEngineRuntime(
    input = input,
    output = output,
    session = session,
    runtime_ctx = runtime_ctx,
    chat_engine_deps = chat_engine_deps
  )

  runtime_ctx <- chat_engine$runtime_ctx
}
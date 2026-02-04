# server.R

server <- function(input, output, session) {

  # ==== FIX: copy uploads to MCP base immediately ====
  mcp_saved_path <- reactiveVal(NULL)
  
  # per-session MCP cache (stores read-ready copies on the local disk)
  cache_root <- getOption(
    "mergen.session_cache_dir",
    normalizePath(file.path(tempdir(), "mergen_session_cache"), winslash = "/", mustWork = FALSE)
  )
  dir.create(cache_root, recursive = TRUE, showWarnings = FALSE)
  cache_root <- safe_windows_short_path(cache_root, must_exist = dir.exists(cache_root))

  cache_session_token <- function(tok) {
    if (is.null(tok) || !nzchar(tok)) {
      return(sprintf("sess_%s", format(Sys.time(), "%Y%m%d%H%M%S")))
    }
    gsub("[^A-Za-z0-9_-]", "_", tok)
  }

  cache_mcp_file_locally <- function(src_path) {
    src_path_chr <- as.character(src_path %||% "")
    if (!nzchar(src_path_chr) || !path_exists_relaxed(src_path_chr)) {
      return(NULL)
    }
    dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
    dest <- file.path(cache_dir, basename(src_path_chr))
    src_for_copy <- try(normalize_excel_path(src_path_chr), silent = TRUE)
    if (inherits(src_for_copy, "try-error") || is.null(src_for_copy) || !nzchar(src_for_copy)) {
      src_for_copy <- src_path_chr
    }
    copied <- FALSE
    try({
      copied <- isTRUE(file.copy(src_for_copy, dest, overwrite = TRUE))
    }, silent = TRUE)
    if (!copied && !path_exists_relaxed(dest)) {
      return(NULL)
    }
    dest_norm <- tryCatch(normalizePath(dest, winslash = "/", mustWork = FALSE), error = function(e) dest)
    if (path_exists_relaxed(dest_norm)) {
      dest_norm <- safe_windows_short_path(dest_norm, must_exist = TRUE)
    }
    dest_norm
  }
  
  # Widget bağımlılık çıktılarını başlat (modüler)
  widgetDependencyOutputsInit(output)
  
  # ---- small helpers ---------------------------------------------------------

	# Get the current user's system username
	system_username <- Sys.info()["user"]

	# Get their permanent UserID from our database
	current_user_id <- get_or_create_user(system_username)

    cache_dir <- file.path(cache_root, paste0("user_", current_user_id), cache_session_token(session$token %||% "anon"))
	dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
	
	# Oturum sonlandığında cache dizinini temizle
	session$onSessionEnded(function() {
	  try(unlink(cache_dir, recursive = TRUE, force = TRUE), silent = TRUE)
	})
	
  # Minimal snapshot that can be serialized and shipped to AI workers
  update_mcp_registry_snapshot <- function(files_snapshot = NULL) {
    if (is.null(files_snapshot)) {
      files_snapshot <- session$userData$current_session_files %||% list()
    }
    session$userData$mcp_registry_snapshot <- files_snapshot %||% list()
    session$userData$mcp_registry_snapshot
  }
  
  # Make sure we always have a snapshot object on session start
  if (is.null(session$userData$mcp_registry_snapshot)) {
    session$userData$mcp_registry_snapshot <- session$userData$current_session_files %||% list()
  }

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
  
  # Hızlı eylem şablonları modülünü başlat
  quickActionsInit(input, session, values, settings_data,
                   session_files, send_message, quick_action_skip_mcp)
				   
  # ==========================================================================
  # GÖRSEL AYARLARI SENKRONİZASYONU (Sohbet → Ayarlar)
  # ==========================================================================
  # NOT: Ana Söyleşi'deki değişiklikler settings reaktif değerlerini günceller,
  # ancak Ayarlar sayfası UI'ını doğrudan güncellemez. Ayarlar sayfası kendi
  # geçici değişkenlerini kullanır ve bunlar yalnızca "Ayarları Kaydet"
  # butonuna basıldığında uygulanır.
  observeEvent(input$chat_image_size, {
    if (!is.null(input$chat_image_size)) {
      settings_data$image_size <- input$chat_image_size
      # Ayarlar sayfasına senkronize ETME - ayarlar sayfası kendi temp değişkenlerini kullanır
      # ve sadece kaydet butonunda uygulanır
    }
  }, ignoreInit = TRUE)
 
  observeEvent(input$chat_image_quality_hd, {
    settings_data$image_quality_hd <- isTRUE(input$chat_image_quality_hd)
    # Ayarlar sayfasına senkronize ETME
  }, ignoreInit = TRUE)
  
  # Ayar gözlemcilerini başlat (modüler)
  settingsObserversInit(input, session, values, settings_data)
  
  # Kayıtlı sohbet gözlemcilerini başlat
  load_chat_in_progress <- reactiveVal(FALSE)
  savedChatsObserversInit(input, output, session, values, settings_data,
                           saved_chats_data, current_user_id, load_chat_in_progress)
  
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
  request_queue <- reactiveVal(list())
  processing_request <- reactiveVal(FALSE)
  active_request_id <- reactiveVal(NULL)
  quick_action_skip_mcp <- reactiveVal(FALSE)
  
  process_queue <- function() {
	if (processing_request() || length(request_queue()) == 0) {
	  return()
	}
	
	processing_request(TRUE)
	current_request <- request_queue()[[1]]
	request_queue(request_queue()[-1])
	
	# Process the request
	tryCatch({
	  current_request$handler()
	}, finally = {
	  processing_request(FALSE)
	  # Process next in queue
	  invalidateLater(100)
	  process_queue()
	})
  }

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
  rv_session_files <- reactiveVal(list())
  
  saved_chats_data <- savedChatsServer("saved_chats_module", saved_chats = reactive(values$saved_chats))

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
	    		
  # Simplified - uses AI module
  generate_non_streaming_stoppable <- function(chat_history, current_settings, user_prompt_msg,
                                             chat_id_val, model_selected, last_user_text = NULL) {
	
	req_id <- paste0("req_", format(Sys.time(), "%Y%m%d%H%M%OS3"), "_", sample(1000:9999, 1))
	active_request_id(req_id)
	
	safe_settings <- current_settings; safe_settings$shiny_session <- NULL
	dbg_dump("LLM_REQUEST_NONSTREAM", list(model = model_selected, messages = chat_history, settings = safe_settings))
	
	p <- ai_processor$call_llm_non_streaming(chat_history, current_settings, model_selected)
	
	# Chain onto the returned promise and use that going forward
	p2 <- promises::then(
	  p,
	  onFulfilled = function(result) {
		if (isTRUE(stop_generation()) || !identical(active_request_id(), req_id)) {
		  perf_tracker$track_error()
		  removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
		  values$typing <- FALSE
		  reset_chat_state()
		  return(invisible(NULL))
		}
		
		dbg_dump("LLM_RESPONSE_NONSTREAM", list(
		  success = result$success, duration = result$duration %||% NA_real_,
		  content_preview = substr(result$content %||% "", 1, 800),
		  error = result$error %||% NULL
		))
		if (result$success) {
		  # DEBUG: cevabın tipi/uzunluğu
		  cat("[AI_RESP] success=TRUE; class=", paste(class(result$content), collapse=","), 
			  " length=", if (is.null(result$content)) NA_integer_ else length(result$content),
			  ' preview="', substr(as.character(result$content)[1], 1, 120), '"\n', sep="")

		  perf_tracker$track_request(result$duration)
		  removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
		  values$typing <- FALSE

		  # NEW: make chart specs available to the message renderer
		  if (is.list(result$chart_store) && length(result$chart_store) > 0) {
			if (is.null(session$userData$chart_store) || !is.list(session$userData$chart_store)) {
			  session$userData$chart_store <- list()
			}
			session$userData$chart_store <- utils::modifyList(session$userData$chart_store, result$chart_store)
		  }
		  
		    # --- ChartLab fallback: model metin döndürdüyse zorla en az 1 grafik ekle ---
			  # Türkçe yorum: Yalnızca MCP Excel modunda ve kullanıcı grafik istediğinde çalıştır
			  if (identical(current_settings$tool_family, "mcp_excel")) {
				# Türkçe yorum: Yanıtta zaten chartlab bloğu var mı?
				has_chart_block <- is.character(result$content) && length(result$content) > 0 &&
								   grepl("```chartlab", result$content, fixed = TRUE)

				# Türkçe yorum: Kullanıcı isteğinde grafik niyeti var mı?
				# Not: user_prompt_msg$content son kullanıcı mesajını içerir (bağlam ekleriyle birlikte)
				wants_chart <- is.character(user_prompt_msg$content) && length(user_prompt_msg$content) > 0 &&
							   grepl("(?i)\\b(grafik|grafikleri|grafiğini|görselleştir|gorsellestir|görselleştirme|gorsellestirme|plot|chart|chartlab|figure|graph|viz|visualize|visualise|çiz|çizelge|histogram|bar|çubuk|line|çizgi|trend|dağılım|scatter|pie|pasta|donut|pareto|area|spline|boxplot)\\b",
									 user_prompt_msg$content[1], perl = TRUE)

				if (!has_chart_block && wants_chart) {
				  # Türkçe yorum: İlk dosya yolunu seç
				  fp <- NULL
				  if (is.list(current_settings$file_paths) && length(current_settings$file_paths) > 0) {
					fp <- as.character(current_settings$file_paths[[1]])
				  }

				  # Türkçe yorum: prepare_chart_data ile otomatik grafik üret ve yanıta ekle
				  if (!is.null(fp) && nzchar(fp) && path_exists_relaxed(fp) &&
						  exists("helpers_mcp_tools", inherits = TRUE) &&
						  is.function(helpers_mcp_tools$prepare_chart_data)) {

					  detected_type <- if (exists("detect_chart_type_from_text", mode = "function")) {
					  detect_chart_type_from_text(user_prompt_msg$content[1])
					} else { "auto" }
					fb <- try(helpers_mcp_tools$prepare_chart_data(
					  file_name  = fp,
					  chart_type = detected_type,
					  limit      = 4000,
					  session    = session
					), silent = TRUE)

					if (!inherits(fb, "try-error") && is.list(fb) && isTRUE(fb$ok) && !is.null(fb$chart)) {
					  # Türkçe yorum: Referans üret ve store'a kaydet
					  ref_id <- paste0("cl_", format(Sys.time(), "%Y%m%d%H%M%OS3"), "_",
									   sprintf("%04d", sample(0:9999, 1)))
					  if (is.null(session$userData$chart_store) || !is.list(session$userData$chart_store)) {
						session$userData$chart_store <- list()
					  }
					  session$userData$chart_store[[ref_id]] <- fb$chart

					  # Türkçe yorum: Veriyle birlikte inline chartlab bloğunu göm
					  inline <- fb$chart
					  inline$ref <- ref_id
					  block <- paste0(
						"\n\n```chartlab\n",
						jsonlite::toJSON(inline, auto_unbox = TRUE, null = "null", digits = 12),
						"\n```"
					  )
					  result$content <- paste0(if (is.character(result$content)) result$content[1] else "", block)
					}
				  }
				}
			  }
			  # --- /ChartLab fallback ---

		  # Takip soruları oluştur (helpers_followup_questions.R)
		  followup_questions <- build_followup_suggestions(
		    last_user_text, result$content, settings_data, session,
		    api_config, followup_tools, fallback_followup_tool
		  )

		  tryCatch({
						ai_msg <- add_message(result$content, "ai", followups = followup_questions)
		  }, error = function(e) {
						cat("[AI_RESP][ADD_MESSAGE_ERROR] ", conditionMessage(e), "\n", sep="")
						cat("[AI_RESP][ADD_MESSAGE_ERROR] dput(content)= "); dput(result$content); cat("\n")
						showToast(session, "Render hatası: içerik boş/uygunsuz. Günlüğe yazıldı.", "error")
						# Sohbet akışını bozmamak için placeholder
						ai_msg <- add_message("⚠️ Model boş bir yanıt döndürdü (loglandı).", "ai")
		  })

		  if (!is.null(ai_msg) && !isTRUE(stop_generation())) {
			trigger_tts_for_message(ai_msg$id, result$content)
		  }

		  tryCatch({
			log_ai_usage(chat_id_val, user_prompt_msg$db_id, current_user_id, 
						 model_selected, result$duration, TRUE)
		  }, error = function(e) {
			print(paste("Logging error:", e$message))
		  })
		  		  
		  reset_chat_state()
		} else {
		  # Track error
		  perf_tracker$track_error()
		  
		  # Remove typing indicator
		  removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
		  values$typing <- FALSE
		  
		  # Log failure
		  tryCatch({
			log_ai_usage(chat_id_val, user_prompt_msg$db_id, current_user_id,
						 model_selected, result$duration, FALSE)
		  }, error = function(e) {
			print(paste("Logging error:", e$message))
		  })
		  
		  # Show error
		  showToast(session, result$error, "error")
		  reset_chat_state()
		}
	},
	  onRejected = function(err) {
		# Always handle rejections so they don't become "Unhandled promise error"
		perf_tracker$track_error()
		removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
		values$typing <- FALSE

		# Show a friendly message
		msg <- as.character(conditionMessage(err))
		msg <- sub("^[A-Z_]+:\\s*", "", msg)  # strip any error code prefix
		if (!nzchar(msg)) msg <- "Beklenmeyen bir hata oluştu."
		showToast(session, msg, "error")

		reset_chat_state()
		invisible(NULL)
	  }
	)
	
	promises::finally(p2, onFinally = function() {
	  reset_chat_state()
	})
	
	return(p2)
  }
  
  # send_message: main entrypoint
	send_message <- function(prompt_text, is_summarization_request = FALSE) {
	  
	  # Welcome ekranını tamamen temizle ve chat içeriğini göster
	  if (isTRUE(values$show_welcome)) {
		values$show_welcome <- FALSE
		shinyjs::runjs("
		  $('#welcome_fullscreen_container').addClass('hidden').empty();
		  $('#chat_content_container').show();
		  if(window.WelcomeVideoPlayer && window.WelcomeVideoPlayer.destroy) {
			window.WelcomeVideoPlayer.destroy();
		  }
		  if(window.WelcomeNeuralNetwork && window.WelcomeNeuralNetwork.destroy) {
			window.WelcomeNeuralNetwork.destroy();
		  }
		  if(window.WelcomeGreeting && window.WelcomeGreeting.destroy) {
			window.WelcomeGreeting.destroy();
		  }
		")
		removeUI(selector = "#welcome_fullscreen_container > *", multiple = TRUE, immediate = TRUE)
	  }
	  
	  # Track request start time for performance monitoring
	  request_start_time <- Sys.time()

	  # Debounce rapid requests
	  if (values$is_sending) {
		showToast(session, "Lütfen önceki isteğin tamamlanmasını bekleyin.", "warning")
		return()
	  }
	  
	  # EĞER DOSYA ÖZETLEME MODU AKTİFSE VE KULLANICI MESAJI VARSA, 
	  # MESAJI DOSYA ÖZETLEME BAĞLAMINDA İŞLE
	  if (isTRUE(settings_data$enable_summarization_tools) && 
		  length(isolate(session_files())) > 0 &&
		  !is.null(prompt_text) && nzchar(trimws(as.character(prompt_text)))) {
		
		# Summarization modunda olduğumuzu belirle
		skip_mcp_once <- FALSE
		current_settings <- reactiveValuesToList(settings_data)
		current_settings$enable_summarization_tools <- TRUE
		current_settings$enable_rdata_tools <- FALSE
		current_settings$enable_mcp_tools <- FALSE
		
		# Summarization modunda işle
		handle_summarization_mode <- TRUE
	  } else {
		handle_summarization_mode <- FALSE
	  }
	
	# Check last request time (prevent rapid fire)
	if (!is.null(values$last_request_time)) {
	  time_since_last <- as.numeric(difftime(Sys.time(), values$last_request_time, units = "secs"))
	  if (time_since_last < 1) {  # Minimum 1 second between requests
		showToast(session, "Çok hızlı istek gönderiyorsunuz.", "warning")
		return()
	  }
	}
	values$last_request_time <- Sys.time()
	
	# Handle both object and string inputs
	if (is.list(prompt_text) && !is.null(prompt_text$text)) {
	  prompt_text <- prompt_text$text
	}
	
	user_message_text <- trimws(prompt_text %||% "")
	
	fm_files <- file_manager_data$file_contents()
	uploaded_names <- if (length(fm_files)) vapply(fm_files, `[[`, "", "name") else character(0)
	uploaded_count <- length(uploaded_names)
	
	if (nchar(user_message_text) == 0 && uploaded_count == 0) {
	  return()
	}
	
	current_settings <- reactiveValuesToList(settings_data)
	
	cfg_excel_on <- isTRUE(settings_data$enable_mcp_tools)
	cfg_sql_analysis_on <- isTRUE(settings_data$enable_rdata_tools)

	skip_mcp_once <- isTRUE(quick_action_skip_mcp())
	if (skip_mcp_once) quick_action_skip_mcp(FALSE)

	excel_allowed <- cfg_excel_on && uploaded_count > 0
	cfg_summarization_on <- isTRUE(settings_data$enable_summarization_tools)

	  if (skip_mcp_once) {
		tool_family <- "none"
	  } else if (cfg_sql_analysis_on) {
		tool_family <- "sql_analysis"
		current_settings$max_output_tokens <- 4096
	  } else if (excel_allowed) {
		tool_family <- "mcp_excel"
	  } else if (cfg_summarization_on) {
		tool_family <- "summarization"
	  } else if (isTRUE(settings_data$enable_coding_tools)) {
		tool_family <- "coding"
	  } else if (isTRUE(settings_data$enable_process_tools)) {
		tool_family <- "process"
	  } else if (isTRUE(settings_data$enable_app_expert_tools)) {
		tool_family <- "app_expert"
	  } else if (isTRUE(settings_data$enable_image_tools)) {
		tool_family <- "image"
	  } else {
		tool_family <- "none"
	  }

	if (is.null(values$current_chat_id)) {
	  title_prompt <- if (nchar(user_message_text) > 0) user_message_text else "Dosya Analizi"
	  chat_title <- generate_title_from_prompt(title_prompt, max_len = 60)
	  tryCatch({
		new_id <- create_new_chat_in_db(current_user_id, initial_title = chat_title)
		values$current_chat_id <- new_id
		values$saved_chats <- load_chats_from_db(current_user_id, include_messages = FALSE)
		saved_chats_data$refresh()
	  }, error = function(e) {
		showToast(session, paste("Yeni sohbet oluşturulamadı:", e$message), "error")
		return()
	  })
	}
	
	# Don't append style to user message - just use it for display
    display_text <- if (nchar(user_message_text) > 0) user_message_text else "Seçili dosyaların özeti istendi."
    user_prompt_msg <- add_message(display_text, "user")
    
    values$typing <- TRUE
	  if (isTRUE(settings_data$enable_typing_indicator)) {
		removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
		
		insertUI(
		  selector = "#chat_content_container", 
		  where = "beforeEnd",
		  ui = div(
			id = "typing-animation-wrapper", 
			class = "message-bubble", 
			style = "display: flex; justify-content: center; padding: 20px;",
			div(class = "ring", "Düşünüyorum", span())
		  ),
		  immediate = TRUE
		)
		
		shinyjs::runjs("
		  setTimeout(() => { 
			window.smartScrollToBottom();
			$('#typing-animation-wrapper').show();
		  }, 10);
		")
	  }
	  
	  shinyjs::runjs("$('#send_stop_btn i').attr('class', 'fa-solid fa-stop');")
	  shinyjs::runjs("$('#send_stop_btn').addClass('stop-mode');")
	  shinyjs::runjs("$('#send_stop_btn').attr('title', 'Durdur');")
	  
	  values$is_sending <- TRUE
	  stop_generation(FALSE)
	  
	  recent_messages <- tail(isolate(values$messages), 5)
	recent_messages <- Filter(function(m) {
	  is.null(m$content) || !grepl("[ Toplam Dosya Sayısı:", m$content, fixed = TRUE)
	}, recent_messages)
	
	# Get CURRENT file state
	current_session_files <- isolate(session_files())
	uploaded_names <- if (length(current_session_files) > 0) names(current_session_files) else character(0)
	uploaded_count <- length(uploaded_names)
	
	cat(sprintf("[FILE CONTEXT] Current files in session: %d - %s\n", 
				uploaded_count, 
				paste(uploaded_names, collapse = ", ")))
	
	messages_to_process <- recent_messages
	
	if (identical(tool_family, "sql_analysis")) {
       cat("[SERVER] 'Proje ve Kaynak Analizi' secildi. Modul cagiriliyor...\n")
       
       if (isTRUE(stop_generation())) {
         removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
         values$typing <- FALSE
         reset_chat_state()
         return(invisible(NULL))
       }
       
       analiz_result <- tryCatch({
         pk_analiz_process_request(user_message_text, messages_to_process, session, stop_check = stop_generation)
       }, error = function(e) {
         paste0("⚠️ Analiz modülü hatası: ", e$message)
       })
       
       # 2. Sonucu kontrol et
       if (is.character(analiz_result)) {
         # Eger string donerse (Hata mesaji veya 'Sorgu bulunamadi'), akisi durdur ve kullaniciya goster
         removeUI(selector = "#typing-animation-wrapper")
         values$typing <- FALSE
         
         add_message(analiz_result, "ai")
         # Log activity and exit
         return()
         
       } else if (is.list(analiz_result)) {
         # Basarili! LLM'e giden mesaji SQL verisi ile zenginlestir
         cat("[SERVER] SQL Analizi basarili. Veriler LLM baglamina ekleniyor...\n")
         
         # A) Kullanicinin son mesajini (Soru + JSON Veri) ile degistir
         # messages_to_process bir listedir, son elemani kullanicinin promptudur
         last_idx <- length(messages_to_process)
         if (last_idx > 0) {
           messages_to_process[[last_idx]]$content <- analiz_result$user_context
         }
         
         # B) Sistem Promptunu ekle (Sorgu aciklamasi vb.)
         # Listenin en basina bir 'system' mesaji ekliyoruz
         sys_msg <- list(
           role = "system",
           content = analiz_result$prompt_context,
           type = "system"
         )
         messages_to_process <- append(list(sys_msg), messages_to_process)
       }
    }

	# Get character data for system prompt
	selected_char_id <- settings_data$selected_character %||% "mergen"
	chars_data <- get_characters_data()
	character_data <- if (!is.null(chars_data)) {
	  Find(function(x) x$id == selected_char_id, chars_data$styles)
	} else NULL

	# Use character's system prompt or fallback
	base_instruction <- if (!is.null(character_data)) {
	  character_data$system_prompt_en
	} else {
	  "Be a balanced, pragmatic assistant. Provide clear, actionable responses."
	}
	
	# Add mandatory citation requirement WITH file-specific instructions
	citation_instruction <- if (uploaded_count > 0) {
	  paste0(
		"\n\nMANDATORY CITATION RULE: ",
		"Your response MUST end with a 'Kaynakça:' section listing the source filenames. ",
		"This is REQUIRED and NON-NEGOTIABLE. ",
		"Do NOT add any other 'Sources' sections. ",
		"Do NOT use inline [Source: ...] citations. ",
		"Example:\nKaynakça:\n1) document.docx\n2) file.pdf"
	  )
	} else {
	  paste0(
		"\n\nCRITICAL CITATION REQUIREMENT: ",
		"If you reference any sources, include a 'Kaynakça:' section at the end. ",
		"Do NOT use inline [Source: ...] citations. "
	  )
	}

	# SUMMARIZATION MODE: Use existing summarization prompts from helpers_summarization_prompts.R
	if (identical(tool_family, "summarization") && uploaded_count > 0) {
	  style_instruction <- build_summarization_system_prompt(
		file_count = uploaded_count,
		total_chars = 0
	  )
	} else if (isTRUE(settings_data$enable_coding_tools)) {
	  coding_system_prompt <- paste0(
		base_instruction,
		"\n\nKODLAMA UZMANI MODU AKTİF:\n",
		"You are an expert software development assistant specializing in code optimization, debugging, and best practices.\n\n",
		"YOUR CAPABILITIES:\n",
		"- Code review and optimization across multiple languages (Python, R, JavaScript, Java, C++, Go, etc.)\n",
		"- Algorithm design and complexity analysis\n",
		"- Debugging and error resolution\n",
		"- Performance optimization and refactoring\n",
		"- Best practices and design patterns\n",
		"- Unit testing and test-driven development\n",
		"- Code documentation and maintainability\n\n",
		"YOUR APPROACH:\n",
		"- Provide clean, efficient, production-ready code\n",
		"- Explain your reasoning and trade-offs\n",
		"- Suggest multiple solutions when applicable\n",
		"- Follow language-specific conventions and style guides\n",
		"- Prioritize readability, maintainability, and performance\n",
		"- Include inline comments for complex logic\n",
		"- Consider edge cases and error handling\n\n",
		"RESPONSE FORMAT:\n",
		"- Use proper markdown code blocks with language specification\n",
		"- Provide clear explanations before and after code\n",
		"- Highlight key improvements or changes\n",
		"- Suggest testing strategies when relevant",
		citation_instruction
	  )
	  style_instruction <- coding_system_prompt
	} else if (isTRUE(settings_data$enable_image_tools)) {
	  # Görsel oluşturma modu - sadece style_instruction ayarla
	  # Gerçek görsel oluşturma tool_family == "image" bloğunda yapılacak
	  style_instruction <- paste0(
	    base_instruction,
	    "\n\nGÖRSEL OLUŞTURMA MODU:\n",
	    "Kullanıcının isteğine göre görsel oluşturulacak.",
	    citation_instruction
	  )
	} else {
	  style_instruction <- paste0(base_instruction, citation_instruction)
	}
	
	# Get temperature from character
	temperature_value <- if (!is.null(character_data) && !is.null(character_data$parameters$temperature)) {
	  character_data$parameters$temperature
	} else {
	  0.4
	}
	
	# Always add style instruction
	system_msg <- list(type = "system", content = style_instruction)
	messages_to_process <- c(list(system_msg), messages_to_process)
	
	cat(sprintf("[STYLE] Using character: %s (temp: %.2f)\n", selected_char_id, temperature_value))
	
	  # DOSYA ÖZETLEME MODU: Mevcut özetleme altyapısını kullan
	  if (identical(tool_family, "summarization")) {
		
		# Eğer dosya yoksa kullanıcıya bilgi ver
		if (uploaded_count == 0) {
		  removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
		  values$typing <- FALSE
		  values$is_sending <- FALSE
		  showToast(session, "Lütfen önce Dosya Yönetimi sayfasından dosya yükleyin ve 'Model Bağlamı' seçin.", "info")
		  return(invisible(NULL))
		}
		
		# DOSYA ÖZETLEME MODU AKTİFSE, HER ZAMAN process_summarization_request ÇAĞIR
		cat("[SUMMARIZATION] Dosya Özetleme modu aktif, özetleme başlatılıyor. Dosya sayısı:", uploaded_count, "\n")
		
		# Modülü sadece ilk kez yükle (her istekte yeniden okumayı önle)
		if (!exists("process_summarization_request", mode = "function")) {
		  source("R/module_summarization.R", encoding = "UTF-8", local = TRUE)
		}
		
		# Özetleme işlemini başlat
		values$typing <- TRUE
		if (isTRUE(settings_data$enable_typing_indicator)) {
		  removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
		  insertUI(
			selector = "#chat_content_container", 
			where = "beforeEnd",
			ui = div(
			  id = "typing-animation-wrapper", 
			  class = "message-bubble", 
			  style = "display: flex; justify-content: center; padding: 20px;",
			  div(class = "ring", "Belgeleriniz özetleniyor", span())
			),
			immediate = TRUE
		  )
		}
		
		# Kullanıcının orijinal mesajını kaydet (eğer varsa)
		if (nchar(user_message_text) > 0) {
		  # Kullanıcı mesajını içeriğe ekleyelim
		  current_session_files$user_query <- user_message_text
		  cat("[SUMMARIZATION] Kullanıcı sorgusu özetlemeye eklendi:", user_message_text, "\n")
		}
		
		# Promise ile özetleme
		p <- process_summarization_request(
		  file_list = current_session_files,
		  session = session,
		  settings = settings_data,
		  ai_processor = ai_processor,
		  max_chars_per_file = if (grepl("256k|256K", settings_data$model_selection %||% "")) {
			200000
		  } else {
			120000
		  }
		)
		
		promises::then(
		  p,
		  onFulfilled = function(result) {
			removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
			values$typing <- FALSE
			
			if (!result$success) {
			  showToast(session, result$message, "error")
			  values$is_sending <- FALSE
			  return(invisible(NULL))
			}
			
			# AI yanıtını ekle
			add_message(result$summary, "ai")
			
			showToast(session, paste(result$file_count, "dosya başarıyla özetlendi."), "success")
			
			reset_chat_state()
		  },
		  onRejected = function(err) {
			removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
			values$typing <- FALSE
			showToast(session, paste("Özetleme hatası:", conditionMessage(err)), "error")
			reset_chat_state()
		  }
		)
		
		# Fonksiyonu burada sonlandır (promise işlenecek)
		return(invisible(NULL))
	  } else if (identical(tool_family, "image")) {
	    # ========================================================================
	    # GÖRSEL OLUŞTURMA MODU - DALL-E-3 API
	    # ========================================================================
	    cat("[IMAGE_MODE] Görsel Uzmanı modu aktif - görsel oluşturma başlatılıyor\n")
	    
		# Görsel ayarlarını al (sohbet kontrollerinden öncelikli)
	    chat_size <- input$chat_image_size
	    chat_quality_hd <- isTRUE(input$chat_image_quality_hd)
	    
	    image_size <- if (!is.null(chat_size) && nzchar(chat_size)) {
	      chat_size
	    } else {
	      settings_data$image_size %||% "1024x1024"
	    }
	    
	    image_quality <- if (chat_quality_hd) "hd" else {
	      if (isTRUE(settings_data$image_quality_hd)) "hd" else "standard"
	    }
	    
	    # Kullanıcının API anahtarını al
	    api_key_for_image <- tryCatch(as.character(session$userData$ai_api_key)[1], error = function(e) "")
	    
	    if (!nzchar(api_key_for_image)) {
	      removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
	      values$typing <- FALSE
	      add_message("⚠️ Görsel oluşturmak için API anahtarı gerekli. Lütfen Ayarlar sayfasından API anahtarınızı girin.", "ai")
	      reset_chat_state()
	      return(invisible(NULL))
	    }
	    
	    # Yükleme göstergesi güncelle
	    removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
	    insertUI(
	      selector = "#chat_content_container",
	      where = "beforeEnd",
	      ui = div(
	        id = "typing-animation-wrapper",
	        class = "message-bubble",
	        style = "display: flex; justify-content: center; padding: 20px;",
	        div(class = "image-generating",
	          div(class = "image-generating-spinner"),
	          div(class = "image-generating-text", "Görsel oluşturuluyor... Bu işlem 30 saniye ile 2 dakika arasında sürebilir.")
	        )
	      ),
	      immediate = TRUE
	    )
	    shinyjs::runjs("window.smartScrollToBottom();")
	    
		# Asenkron görsel oluşturma için değişkenleri yakala
	    current_user_id_local <- current_user_id
	    current_chat_id_local <- values$current_chat_id
	    user_prompt_local <- user_message_text
	    image_size_local <- image_size
	    image_quality_local <- image_quality
	    api_key_local <- api_key_for_image
	    
	    future_promise({
	      generate_image(
	        prompt = user_prompt_local,
	        api_key = api_key_local,
	        size = image_size_local,
	        quality = image_quality_local,
	        user_id = current_user_id_local,
	        chat_id = current_chat_id_local
	      )
	    }) %...>% (function(result) {
	      # Typing animasyonunu kaldır
	      removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
	      values$typing <- FALSE
	      
	      # Sonucu işle
		if (isTRUE(result$success)) {
			# Başarılı - sadece görseli göster (gereksiz metin yok)
			image_html <- render_generated_image_html(result, paste0("img_", floor(as.numeric(Sys.time()) * 1000)))
 
			# ÖNEMLİ: Base64 veriyi LLM bağlamına göndermemek için içerik olarak
			# sadece metin açıklama kullan, HTML'i ayrı tut
			# Bu sayede görsel araçları kapatıldığında context patlaması olmaz
			# NOT: Görsel yolunu da kaydet ki önceki sohbetler yüklendiğinde görsel tekrar gösterilebilsin
			image_description <- result$revised_prompt %||% "[Görsel oluşturuldu]"
			# Format: [GÖRSEL:path] description - path önceki sohbetlerde görseli bulmak için gerekli
			image_path_marker <- if (!is.null(result$local_path) && nzchar(result$local_path)) {
			  paste0("[GÖRSEL:", result$local_path, "]")
			} else {
			  "[GÖRSEL]"
			}
			content_text <- paste0(image_path_marker, " ", image_description)
 
			add_message(content_text, "ai", html = image_html)
			showToast(session, "Görsel oluşturuldu!", "success")
	      } else {
	        # Hata - mesaj göster
	        error_msg <- result$error %||% "Görsel oluşturulamadı"
	        error_html <- render_generated_image_html(result, "error")
	        add_message(paste0("❌ ", error_msg), "ai", html = error_html)
	        showToast(session, error_msg, "error")
	      }
	      
	      reset_chat_state()
	    }) %...!% (function(err) {
	      # Promise hatası
	      removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
	      values$typing <- FALSE
	      add_message(paste0("❌ Görsel oluşturma hatası: ", err$message), "ai")
	      showToast(session, paste("Hata:", err$message), "error")
	      reset_chat_state()
	    })
	    
	    # Fonksiyonu burada sonlandır (promise işlenecek)
	    return(invisible(NULL))
	    
	  } else if (identical(tool_family, "mcp_excel") && uploaded_count > 0) {
	  file_list_text <- paste0(
		"\n\nDOSYA BİLGİSİ:\n",
		"Toplam ", uploaded_count, " dosya yüklü:\n",
		paste(paste0("- ", uploaded_names), collapse = "\n"),
		"\n\nÖNEMLİ: Bu dosyaları analiz etmek için MUTLAKA 'analyze_uploaded_file' veya 'get_column_statistics' veya 'sql_query_uploaded_file' araçlarını kullan. ",
		"Dosya içeriğini TAHMİN ETME, araçları kullan!"
	  )

	  user_question <- tail(recent_messages, 1)[[1]]$content
	  citation_files_list <- paste(sapply(seq_along(uploaded_names), function(i) paste0(i, ") ", uploaded_names[i])), collapse = "\n")

	  final_context_prompt <- list(
		type = "user",
		content = paste0(
		  "Aşağıdaki dosya bağlamını kullanarak soruyu yanıtla.\n\n",
		  "[ Toplam Dosya Sayısı: ", uploaded_count, " ]\n",
		  file_list_text,
		  "\n\n--- BAĞLAM SONU ---\n\n",
		  "ZORUNLU TALİMAT: Yanıtının EN SONUNDA aşağıdaki formatı AYNEN kullan:\n\n",
		  "Kaynakça:\n",
		  citation_files_list,
		  "\n\nSoru: ", user_question
		)
	  )

	  messages_to_process <- c(list(system_msg), head(recent_messages, -1), list(final_context_prompt))

	} else if (identical(tool_family, "none") && uploaded_count > 0) {
	  # Türkçe yorum: MCP kapalı → seçili dosyaların özetini/alıntısını doğrudan bağlama ekle
	  file_blocks <- character(0)
	  total_budget <- 120000  # toplam bağlam bütçesi (karakter)
	  per_file_cap <- max(4000, floor(total_budget / max(1, uploaded_count)))

	  for (fname in uploaded_names) {
		# 1) Varsa hazır özet metni kullan
		sumtxt <- session$userData$file_summaries[[fname]] %||% ""
		if (!is.character(sumtxt) || !nzchar(sumtxt[1])) {
		  # 2) Yoksa ham içerikten kısa bir alıntı hazırla
		  fobj <- session$userData$current_session_files[[fname]] %||% NULL
		  if (is.list(fobj)) {
			fpath <- fobj$datapath %||% fobj$path %||% ""
			if (nzchar(fpath) && path_exists_relaxed(fpath)) {
			  rawtxt <- readFileContentToString(list(
					name = fname,
					datapath = fpath,
					size = file.info(fpath)$size
			  ))
			  sumtxt <- substr(rawtxt %||% "", 1, per_file_cap)
			}
		  }
		} else {
		  sumtxt <- as.character(sumtxt[1])
		  if (nchar(sumtxt) > per_file_cap) sumtxt <- substr(sumtxt, 1, per_file_cap)
		}

		block <- paste0("### ", fname, "\n", sumtxt)
		file_blocks <- c(file_blocks, block)
	  }

	  citation_files_list <- paste(sapply(seq_along(uploaded_names), function(i) paste0(i, ") ", uploaded_names[i])), collapse = "\n")
	  user_question <- tail(recent_messages, 1)[[1]]$content

	  final_context_prompt <- list(
		type = "user",
		content = paste0(
		  "Aşağıdaki dosya özetlerini ve/veya alıntılarını kullanarak isteği yanıtla. Araç KULLANILMAYACAKTIR (MCP kapalı).\n\n",
		  paste(file_blocks, collapse = "\n\n"),
		  "\n\nSoru: ", user_question, 
		  "\n\nKaynakça:\n", citation_files_list
		)
	  )

	  messages_to_process <- c(list(system_msg), head(recent_messages, -1), list(final_context_prompt))

	} else {
	  # --- Proje ve Kaynak Analizi (SQL) Modu ---
	  if (identical(tool_family, "sql_analysis")) {
	     # messages_to_process hazir oldugu icin burasi bos birakiliyor.
	  } else {
	    # --- Standart Sohbet Modu ---
		messages_to_process <- c(list(system_msg), recent_messages)
	  }
	}
	
	{
	  api_key_val <- tryCatch(as.character(session$userData$ai_api_key)[1], error = function(e) "")
	  if (!nzchar(api_key_val)) {
		removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
		values$typing <- FALSE
		showToast(session,
		  "API anahtarı eksik. Ayarlar > Model Ayarları > API Anahtarı Güncelleme üzerinden girin.",
		  "error"
		)
		return(invisible(NULL))
	  }
	}
	
	chat_id_val <- isolate(values$current_chat_id)
	
	if (!is.null(input$quick_action_model_change)) {
	  Sys.sleep(0.1) # Small delay to ensure settings are updated
	}
	
	# === NEW: Read the model selection from settings_data via reactiveValuesToList ===
	model_selected <- current_settings$model_selection
	
	# Ensure we have a snapshot handy before any per-request changes
	mcp_snapshot <- session$userData$mcp_registry_snapshot %||% (session$userData$current_session_files %||% list())
		
	current_settings$current_user_id <- current_user_id
    current_settings$mcp_registry_snapshot <- mcp_snapshot

	# Bu isteğin araç ailesini ilet
	current_settings$tool_family <- tool_family  # mcp_excel | rdata | none

	# Araçları bu istekte etkinleştir (none hariç)
	current_settings$enable_mcp_tools <- !identical(tool_family, "none")

	# Sıcaklık, dosya listesi ve oturum
	current_settings$temperature     <- temperature_value
	current_settings$uploaded_files  <- uploaded_names
	current_settings$shiny_session   <- session
	
	cat("\n========== ANALYSIS MODE ==========\n")
	cat("[MODE] tool_family:", tool_family, "\n")
	cat("[SQL_ANALYSIS] enabled:", cfg_sql_analysis_on, "\n")
	cat("[EXCEL_MCP] enabled:", cfg_excel_on, "\n")
	cat("===================================\n\n")
	
	if (!is.null(session$userData$current_session_files) && length(session$userData$current_session_files) > 0) {
	  cat("[MCP] Files available:", length(session$userData$current_session_files), "\n")

	  # DEBUG: Show what's actually stored
	  if (!is.null(session$userData$current_session_files)) {
		for (key in names(session$userData$current_session_files)) {
		  obj <- session$userData$current_session_files[[key]]
		  cat("[MCP DEBUG] Key:", key, "| Name:", obj$name %||% "?", "| Path:", obj$path %||% obj$datapath %||% "?", "\n")
		}
	  }
	  
	  for (fname in names(session$userData$current_session_files)) {
			fobj <- session$userData$current_session_files[[fname]]
			if (is.list(fobj)) {
			  fpath <- fobj$datapath %||% fobj$path
			  cat("[MCP]   -", fname, "->", fpath, "(exists:", path_exists_relaxed(fpath), ")\n")
			}
	  }
	} else {
	  cat("[MCP] NO FILES STORED - MCP will not work!\n")
	}
	cat("================================\n\n")
	
	# Yalnızca Excel modunda seçili dosyaları MCP tabanına koy
	if (identical(tool_family, "mcp_excel") && length(uploaded_names) > 0) {
	  resolve_from_manager <- function(target_name) {
		if (!length(fm_files)) return(NULL)
		for (fid in names(fm_files)) {
		  obj <- fm_files[[fid]]
		  nm  <- obj$name %||% basename(obj$datapath %||% obj$path %||% "")
		  if (identical(nm, target_name)) {
			return(list(info = obj, id = fid))
		  }
		}
		NULL
	  }

	  pick_existing_path <- function(info) {
			candidates <- c(info$persisted_path, info$path, info$datapath)
			candidates <- candidates[!vapply(candidates, function(x) is.null(x) || !nzchar(as.character(x)[1]), logical(1))]
			for (cand in candidates) {
			  c0 <- as.character(cand)[1]
			  if (nzchar(c0) && path_exists_relaxed(c0)) return(c0)
			}
			NULL
	  }

	  csf <- list()
	  for (fname in uploaded_names) {
		fm_hit <- resolve_from_manager(fname)
		finfo  <- fm_hit$info %||% list(name = fname)
		fid    <- fm_hit$id %||% NULL

		path_now <- pick_existing_path(finfo)
		if (is.null(path_now) || !nzchar(path_now)) {
		  resolved <- try(resolve_uploaded_file(fname, current_user_id), silent = TRUE)
		  if (!inherits(resolved, "try-error") && nzchar(resolved) && path_exists_relaxed(resolved)) {
				path_now <- resolved
		  }
		}

		if (is.null(path_now) || !nzchar(path_now) || !path_exists_relaxed(path_now)) {
		  cat("[FILE STORE] Path missing for", fname, "- skipping\n")
		  next
		}

		path_now <- tryCatch(normalizePath(path_now, winslash = "/", mustWork = TRUE), error = function(e) path_now)
		path_now <- safe_windows_short_path(path_now, must_exist = path_exists_relaxed(path_now))

		path_original <- path_now
		tryCatch({
		  if (!is_under_mcp_base(path_now) && isTRUE(current_settings$enable_mcp_tools)) {
						copied <- copy_to_mcp_base(list(name = fname, datapath = path_now), current_user_id)
						if (nzchar(copied) && path_exists_relaxed(copied)) path_now <- copied
		  }
		}, error = function(e) {
		  cat("[FILE STORE] copy_to_mcp_base failed:", e$message, "\n")
		})

		cached_path <- cache_mcp_file_locally(path_now)
		if (is.null(cached_path) || !nzchar(cached_path)) {
		  cached_path <- path_now
		} else if (!identical(cached_path, path_now)) {
		  cat("[FILE STORE] Local MCP cache prepared:", cached_path, "\n")
		}
		cached_path <- safe_windows_short_path(cached_path, must_exist = path_exists_relaxed(cached_path))

		file_obj <- list(
		  name = fname,
		  datapath = cached_path,
		  path = cached_path,
		  source_path = path_original
		)
		csf[[fname]] <- file_obj
		if (!is.null(fid)) csf[[fid]] <- file_obj
  }

	  session$userData$current_session_files <- csf
      mcp_snapshot <- update_mcp_registry_snapshot(csf)
	  if (
		exists("helpers_mcp_tools", inherits = TRUE) &&
		is.function(helpers_mcp_tools$reset_session_file_registry) &&
		is.function(helpers_mcp_tools$register_uploaded_file)
	  ) {
			helpers_mcp_tools$reset_session_file_registry(session)
			registered_keys <- character()
			for (key in names(csf)) {
			  obj <- csf[[key]]
			  if (!is.list(obj)) next
			  path_reg <- obj$path %||% obj$datapath
			  if (is.null(path_reg) || !nzchar(path_reg) || !path_exists_relaxed(path_reg)) next
			  display <- obj$name %||% key
			  tokens <- unique(c(key, display))
			  for (tk in tokens) {
					if (!nzchar(tk) || tk %in% registered_keys) next
					try(helpers_mcp_tools$register_uploaded_file(
					  session = session,
					  token = tk,
					  abs_path = path_reg,
					  display_name = display
					), silent = TRUE)
					registered_keys <- c(registered_keys, tk)
			  }
			}
	  }
	  if (length(csf)) {
			unique_names <- unique(vapply(csf, function(x) x$name %||% "", character(1)))
		cat("[FILE STORE] MCP files (selected): ", paste(unique_names[nzchar(unique_names)], collapse = ", "), "\n", sep = "")
	  } else {
		cat("[FILE STORE] No valid MCP files after filtering.\n")
	  }
	} else {
	  session$userData$current_session_files <- list()
	  mcp_snapshot <- update_mcp_registry_snapshot(list())
	}

	if (!exists("mcp_snapshot", inherits = FALSE)) {
	  mcp_snapshot <- update_mcp_registry_snapshot()
	}

	# DOSYA yollarını yalnızca Excel modunda ilet
	current_settings$file_paths <- list()
	if (identical(tool_family, "mcp_excel") && length(uploaded_names) > 0) {
	  registry_paths <- session$userData$current_session_files %||% list()
	  for (fname in uploaded_names) {
		file_obj <- registry_paths[[fname]]
		if (!is.list(file_obj)) next

		full_path <- file_obj$path %||% file_obj$datapath
		if (is.null(full_path) || !nzchar(full_path)) next

		current_settings$file_paths[[fname]] <- as.character(full_path)
		cat("[FILE PATH ADDED]", fname, "->", full_path, "\n")
	  }
	}
	
	# If no model selected, use the first one as default
	if (is.null(model_selected) || model_selected == "") {
	  model_selected <- api_config$local_models[1]
	}
	
	print(paste("Send message using model:", model_selected))
	# ================================================================================
  
if (isTRUE(current_settings$enable_streaming) && !isTRUE(current_settings$enable_mcp_tools)) {
	  # --- NEW: background the LLM call and make it cancellable (by ignoring late results) ---
	  start_time <- Sys.time()
	  
	  cat("[MONITORING] Starting AI request (STREAMING mode)\n")
	
	  # Make sure model is set
	  settings_for_llm <- current_settings
	  settings_for_llm$model_selection <- model_selected
	
	  # Create a unique id for this request and remember it
	  req_id <- paste0("req_", format(Sys.time(), "%Y%m%d%H%M%OS3"), "_", sample(1000:9999, 1))
	  active_request_id(req_id)
	  stop_generation(FALSE)
	  values$is_sending <- TRUE
	
	  # DEBUG: snapshot request
	  safe_settings <- current_settings; safe_settings$shiny_session <- NULL
	  dbg_dump("LLM_REQUEST_STREAMING", list(model = model_selected, messages = messages_to_process, settings = safe_settings))
	  
		p <- ai_processor$call_llm_streaming(messages_to_process, current_settings, model_selected)

		# Tag with req_id
		p <- promises::then(p, onFulfilled = function(result) {
		  result$req_id <- req_id
		  result
		})

		# Handle success/failure AND make sure any error here is caught
		p <- promises::then(
		  p,
		  onFulfilled = function(res) {
			if (!res$success) {
			  cat("[AI MODULE] Streaming request failed\n")
			  perf_tracker$track_error()
			  removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
			  values$typing <- FALSE
			  showToast(session, res$error, "error")
			  reset_chat_state()
			  return(invisible(NULL))
			}

			cat("[MONITORING] Streaming request completed\n")
			dbg_dump("LLM_RESPONSE_STREAMING", list(
			  success = res$success, duration = res$duration,
			  content_preview = substr(res$content %||% "", 1, 800)
			))

            perf_tracker$track_request(res$duration)

			if (isTRUE(stop_generation()) || !identical(active_request_id(), res$req_id)) {
			  try(log_ai_usage(chat_id_val, user_prompt_msg$db_id, current_user_id,
							   model_selected, res$duration, FALSE), silent = TRUE)
			  removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
			  values$typing <- FALSE
			  reset_chat_state()
			  return(invisible(NULL))
			}

			try(log_ai_usage(chat_id_val, user_prompt_msg$db_id, current_user_id,
											 model_selected, res$duration, TRUE), silent = TRUE)

            # NEW: make chart specs available to the message renderer (streaming path)
			if (is.list(res$chart_store) && length(res$chart_store) > 0) {
			  if (is.null(session$userData$chart_store) || !is.list(session$userData$chart_store)) {
				session$userData$chart_store <- list()
			  }
			  session$userData$chart_store <- utils::modifyList(session$userData$chart_store, res$chart_store)
			}

			# Takip soruları oluştur (helpers_followup_questions.R)
			followup_questions <- build_followup_suggestions(
			  user_message_text, res$content, settings_data, session,
			  api_config, followup_tools, fallback_followup_tool
			)
			
			local_char_id <- current_settings$selected_character %||% "mergen"
			local_chars_data <- get_characters_data()
			local_char_def <- if (!is.null(local_chars_data)) Find(function(x) x$id == local_char_id, local_chars_data$styles) else NULL
			resolved_voice <- if (!is.null(local_char_def) && !is.null(local_char_def$tts_voice)) local_char_def$tts_voice else "tr-male-1"

			tts_engine_param <- NULL
			tts_voice_param <- NULL
			if (isTRUE(settings_data$enable_tts_audio)) {
			  tts_engine_param <- tts_processor$synthesize_speech
			  tts_voice_param <- resolved_voice
			}

			simulate_streaming_stoppable(
			  res$content,
			  followups = followup_questions,
			  tts_engine = tts_engine_param,
			  tts_voice = tts_voice_param,
			  on_start = NULL,
			  on_complete = function(msg) {
			  }
			)
			invisible(NULL)
		  },
		  onRejected = function(err) {
			cat("[MONITORING] Streaming request FAILED\n")
			perf_tracker$track_error()
			removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
			values$typing <- FALSE

			duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
			try(log_ai_usage(chat_id_val, user_prompt_msg$db_id, current_user_id,
							 model_selected, duration, FALSE), silent = TRUE)

			if (!isTRUE(stop_generation())) {
			  msg <- as.character(conditionMessage(err))
			  msg <- sub("^[A-Z_]+:\\s*", "", msg)
			  if (!nzchar(msg)) msg <- "Beklenmeyen bir hata oluştu."
			  showToast(session, msg, "error")
			}
			reset_chat_state()
			invisible(NULL)
		  }
		)

		# ⬇️ NEW: hard catch for anything thrown inside onFulfilled/onRejected above
		p <- p %...!% (function(e) {
		  cat("[STREAM_CHAIN][CATCH] ", conditionMessage(e), "\n", sep = "")
		  perf_tracker$track_error()
		  removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
		  values$typing <- FALSE
		  if (!isTRUE(stop_generation())) {
			showToast(session, "Beklenmeyen bir hata oluştu.", "error")
		  }
		  reset_chat_state()
		  invisible(NULL)
		})

		# Ensure cleanup always runs
		promises::finally(p, onFinally = function() {
		  # nothing; state resets already done defensively
		})
	
	} else {
	  cat("[MONITORING] Starting AI request (NON-STREAMING mode)\n")
	  # Use the non-streaming version
	  generate_non_streaming_stoppable(
		messages_to_process,
		current_settings,
		user_prompt_msg,
		chat_id_val,
		model_selected,
		last_user_text = user_message_text
	  )
	}
	
	invisible(NULL)
  }
  
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
  	  							     							         	  
	# --- Core Chat Functions (wrapped to helpers) ---
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
}
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

  cache_dir <- file.path(cache_root, cache_session_token(session$token %||% "anon"))
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  cache_dir <- safe_windows_short_path(cache_dir, must_exist = dir.exists(cache_dir))

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

  session$onSessionEnded(function() {
    try(unlink(cache_dir, recursive = TRUE, force = TRUE), silent = TRUE)
  })
  
  # One-time widget deps (enables charts rendered into string-inserted containers)
  if (requireNamespace("highcharter", quietly = TRUE)) {
	output$deps_hc <- highcharter::renderHighchart({ highcharter::highchart() })
  }
  if (requireNamespace("plotly", quietly = TRUE) && requireNamespace("ggplot2", quietly = TRUE)) {
	# preload with an explicit trace to suppress startup warnings
	output$deps_pl <- plotly::renderPlotly({
	  plotly::plotly_empty(type = "scatter", mode = "markers")
	})
	# Eski kodların başvurduğu 'plotly_html' çıktısı için gizli yer tutucu
	output$plotly_html <- plotly::renderPlotly({
	  plotly::plotly_empty(type = "scatter", mode = "markers")
	})
  } else {
	# Plotly yoksa bile bu çıktıları tanımla (hata/uyarı önleme)
	output$deps_pl <- renderUI(NULL)
	output$plotly_html <- renderUI(NULL)
  }

  # ---- small helpers ---------------------------------------------------------

	# Get the current user's system username
	system_username <- Sys.info()["user"]

	# Get their permanent UserID from our database
	current_user_id <- get_or_create_user(system_username)

    cache_dir <- file.path(cache_root, paste0("user_", current_user_id), cache_session_token(session$token %||% "anon"))
	dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
	
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
    
  observeEvent(input$`settings_module-open_api_key_modal`, {
    api_key$open("API Anahtarı Güncelleme")
  }, ignoreInit = TRUE)
  
  output$show_admin_menu <- reactive({
    isTRUE(user_config$auth_level == "ADMIN")
  })
  outputOptions(output, "show_admin_menu", suspendWhenHidden = FALSE)
  
  output$admin_menu_item <- renderMenu({
    if (isTRUE(user_config$auth_level == "ADMIN")) {
      menuItem("Yönetici Paneli", tabName = "admin_analytics", icon = icon("chart-bar"))
    }
  })
  
  if (isTRUE(user_config$auth_level == "ADMIN")) {
    adminAnalyticsServer("admin_analytics_module", pool = pool)
  }
  
  # Initialize AI processing module
  ai_processor <- aiProcessingServer("ai_proc")
  
  # Initialize TTS processing module
  tts_processor <- ttsProcessingServer("tts_proc")
  
  # Initialize TTS Visualizer
  tts_visualizer <- ttsVisualizerServer("tts_viz", settings_data)
  
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

	render_welcome_screen <- function(saved_chats, replace_existing = FALSE) {
	  if (!isTRUE(shiny::isolate(values$show_welcome))) {
		return(invisible(NULL))
	  }

	  if (isTRUE(replace_existing) && isTRUE(session$userData$welcome_screen_attached)) {
		shinyjs::runjs("$('#chat_content_container .welcome-container').remove();")
	  }

	  insertUI(
		selector = "#chat_content_container",
		where = "beforeEnd",
		ui = createWelcomeScreen(saved_chats),
		immediate = TRUE
	  )

	  session$userData$welcome_screen_attached <- TRUE

	  session$onFlushed(function() {
		session$sendCustomMessage("showNeuralAnimation", list())
	  }, once = TRUE)
	}

	session$userData$initial_saved_chats_promise <- promises::then(
	  promises::future_promise({
		load_chats_from_db(current_user_id, include_messages = FALSE)
	  }),
	  onFulfilled = function(chats) {
		chats <- chats %||% list()
		values$saved_chats <- chats

		if (length(chats) > 0) {
		  render_welcome_screen(chats, replace_existing = TRUE)
		}
		NULL
	  },
	  onRejected = function(err) {
		warning(sprintf("[SERVER] Initial saved chat load failed: %s", conditionMessage(err)))
		NULL
	  }
	)
	
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
  
  # Aynı dosya adına ilişkin art arda iki tıklamayı (çok kısa süre içinde) yutmak için
	last_source_click <- reactiveVal(list(name = NULL, t = 0))  # yeni

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
	
  # Fix CodeMirror rendering when switching tabs
  observeEvent(input$tabs, {
	if (input$tabs == "chat") {
	  shinyjs::delay(200, {
		shinyjs::runjs("
		  if (typeof window.initializeCodeMirror === 'function') {
			window.initializeCodeMirror();
		  }
		  // Force refresh all CodeMirror instances
		  document.querySelectorAll('.CodeMirror').forEach(function(cm) {
			if (cm.CodeMirror) {
			  cm.CodeMirror.refresh();
			}
		  });
		")
	  })
	}
  })
  
	# Kaynakça tıklamalarını Shiny input'a köprüle (her sayfada bir kere kur)
	session$onFlushed(function(){
	  shinyjs::runjs("
		if (!window.__srcLinkBound) {
		  window.__srcLinkBound = true;
			document.addEventListener('click', function(e){
			  var t = e.target;
			  if (t && t.classList && t.classList.contains('source-link')) {
				e.preventDefault();
				e.stopPropagation(); // çift tetiklemeyi önle
				var fn = t.getAttribute('data-filename') || (t.textContent || '').trim();
				Shiny.setInputValue('source_file_clicked', { filename: fn, nonce: Math.random() }, { priority: 'event' });
			  }
			}, true);
		}
	  ");
	}, once = TRUE)
		
	# Sadece Model adını Ana Söyleşi başlığında göster (Avatar ve Karakter Adı kaldırıldı)
	output$current_model_display <- renderUI({
	  # Model bilgisini al
	  selected_model_id <- settings_data$model_selection %||% api_config$local_models[1]
	  display_name <- names(api_config$local_models)[api_config$local_models == selected_model_id]
	  if (length(display_name) == 0) display_name <- selected_model_id
	  
      # Varsayılan stil renkleri
	  bg_color <- "rgba(255, 255, 255, 0.05)"
	  border_color <- "rgba(255, 255, 255, 0.1)"
	  
	  div(
		class = "header-stat-item",
		title = paste0("Model: ", display_name),
		style = paste0(
		  "background: ", bg_color, "; ",
		  "border-color: ", border_color, ";"
		),
        # Avatar ve Karakter adı kaldırıldı, sadece Model adı
		span(
		  style = "font-weight: 500; color: #b0b0b0;",
		  paste0("Model: ", display_name)
		)
	  )
	})
  
  # MCP modu göstergesi için reaktif çıktı (Ana Söyleşi başlığında kullanılır)
	output$mcp_mode_indicator <- renderUI({
	  excel_active <- isTRUE(settings_data$enable_mcp_tools)
	  sql_analysis_active <- isTRUE(settings_data$enable_rdata_tools)
	  
	  if (excel_active) {
		div(
		  class = "mcp-indicator excel-active",
		  tags$i(class = "fas fa-file-excel"),
		  span("Excel MCP")
		)
	  } else if (sql_analysis_active) {
		div(
		  class = "mcp-indicator rdata-active",
		  tags$i(class = "fas fa-database"),
		  span("SQL Analiz")
		)
	  } else {
		NULL
	  }
	})

  # Pass values reactive to file manager for temp_files access
	file_manager_data <- fileManagerServer(
	  "file_manager_module",
	  new_file_trigger = reactive({ file_to_add() }),
	  session_files_reactive = session_files,
	  mcp_enabled_reactive = reactive({ isTRUE(settings_data$enable_mcp_tools) }),
	  user_id = current_user_id
	)
	
	observeEvent(settings_data$enable_mcp_tools, {
	  if (isTRUE(settings_data$enable_mcp_tools)) {
		# If multiple are attached already, keep the first, uncheck the rest
		cur <- names(session_files())
		if (length(cur) > 1) {
		  keep <- cur[1]
		  to_uncheck <- cur[-1]
		  sf <- session_files()
		  for (nm in to_uncheck) sf[[nm]] <- NULL
		  session_files(sf)
		  # Reflect on the File Manager checkboxes
		  if (!is.null(file_manager_data$set_attachment_checked)) {
			lapply(to_uncheck, function(nm) file_manager_data$set_attachment_checked(nm, FALSE))
		  }
		  showToast(session, "MCP açıkken yalnızca 1 dosya eklenebilir. Fazla seçimler kaldırıldı.", "warning")
		}
	  }
	})

  # One place to store app-visible files (+ summaries)
  if (is.null(session$userData$file_summaries)) session$userData$file_summaries <- list()
  rv_session_files <- reactiveVal(list())
  
  # ⛔️ Removed duplicate module initialization & its observers (Problem 1)
  # (fm <- fileManagerServer(...) + BULK ADD observer block was here)

  saved_chats_data <- savedChatsServer("saved_chats_module", saved_chats = reactive(values$saved_chats))
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
  
  # --- Top-Level Outputs for Modals ---
  # Renders the file indicator badge UI for ALL attached files
  output$file_prompt_indicator_ui <- renderUI({
	files_list <- names(session_files())
	req(length(files_list) > 0)

	div(class = "file-indicator-wrapper",
	  tags$p(
		class = "file-indicator-title",
		sprintf("Ekli Dosyalar (%d):", length(files_list))
	  ),
	  div(
		class = "file-indicator-scroll-container",
		lapply(files_list, function(filename) {
		  div(class = "file-indicator",
			  tagList(
				icon("paperclip"),
				span(class = "file-indicator-name", filename),
				tags$button(
				  icon("times"),
				  class = "file-indicator-close action-button",
				  onclick = sprintf("Shiny.setInputValue('remove_file_from_prompt', { name: '%s', nonce: Math.random() }, {priority: 'event'})", filename)
				)
			  )
		  )
		})
	  )
	)
  })
  
  # message search wiring
messageSearchInit(input, session, values, reactive(values$messages))
  
  # Remove a SPECIFIC file from the prompt context
	observeEvent(input$remove_file_from_prompt, {
	  filename_to_remove <- input$remove_file_from_prompt$name
	  req(filename_to_remove)

	  # 1) Remove from AI context
	  current_files <- session_files()
	  current_files[[filename_to_remove]] <- NULL
	  session_files(current_files)

	  # 2) Just UNCHECK in file manager (do NOT delete row)
	  if (!is.null(file_manager_data$set_attachment_checked)) {
		file_manager_data$set_attachment_checked(filename_to_remove, FALSE)
	  }

	  showToast(session, paste("Dosya AI bağlamından kaldırıldı:", filename_to_remove), "info")
})
  
# Handle source file clicks from Kaynakça
observeEvent(input$source_file_clicked, {
  req(input$source_file_clicked)

  # --- Normalize + debounce ---
  ev <- input$source_file_clicked
  raw_name <- if (is.character(ev)) ev[1] else (ev$filename %||% ev$name %||% "")
  raw_name <- as.character(raw_name %||% "")
  raw_name <- sub("^\\s*\\d+\\)\\s*", "", raw_name)  # numaralı önekleri temizle

  # Çift tıklama yutma (500ms) — tam ipucu bazlı
  now  <- as.numeric(Sys.time())
  last <- last_source_click()
  if (is.list(last) && identical(last$name, raw_name) && (now - (last$t %||% 0)) < 0.5) {
	return(invisible(NULL))
  }
  last_source_click(list(name = raw_name, t = now))

  # not: 'raw_name' tıklanan TAM ipucu değeridir; 'fname' artık kullanılmıyor
  if (!nzchar(raw_name)) {
	showToast(session, "Geçersiz kaynak bağlantısı: dosya adı yok.", "error")
	return(invisible(NULL))
  }

  # Günlük: tıklanan kaynak
  log_info("[SRC_CLICK] tıklanan kaynak: '{raw_name}'")

  # Tüm çözümleme/önizleme işini tek bir yerde topla
  handle_source_file_click(ev, settings_data, api_config, session, filePreview)
}, ignoreInit = TRUE)

observeEvent(input$analysis_file_clicked, {
  req(input$analysis_file_clicked)
  
  filepath_raw <- input$analysis_file_clicked$filepath
  if (is.null(filepath_raw) || !nzchar(filepath_raw)) {
    showToast(session, "Geçersiz dosya yolu.", "error")
    return(invisible(NULL))
  }
  
  filepath_clean <- trimws(as.character(filepath_raw))
  
  full_path <- NULL
  if (startsWith(filepath_clean, "www/")) {
    full_path <- file.path(getwd(), filepath_clean)
  } else if (startsWith(filepath_clean, "/") || grepl("^[A-Za-z]:", filepath_clean)) {
    full_path <- filepath_clean
  } else {
    full_path <- file.path(getwd(), "www", filepath_clean)
  }
  
  full_path <- normalize_mcp_path(full_path, must_exist = FALSE)
  
  if (!path_exists_relaxed(full_path)) {
    showToast(session, paste("Dosya bulunamadı:", basename(filepath_clean)), "error")
    log_error("[ANALYSIS_FILE] Dosya mevcut değil: {full_path}")
    return(invisible(NULL))
  }
  
  file_info <- list(
    name = basename(full_path),
    datapath = full_path,
    size = suppressWarnings(file.info(full_path)$size)
  )
  
  log_info("[ANALYSIS_FILE] Önizleme açılıyor: {full_path}")
  openAnyPreview(file_info, session, filePreview)
  
}, ignoreInit = TRUE)
  
  # Connect file manager uploads/removals to AI context
  observeEvent(file_manager_data$file_removed(), {
	removed_file <- file_manager_data$file_removed()
	if (!is.null(removed_file)) {
	  current_files <- session_files()
	  if (!is.null(removed_file$name) && removed_file$name %in% names(current_files)) {
		current_files[[removed_file$name]] <- NULL
		session_files(current_files)
		showToast(session, paste("Dosya AI bağlamından kaldırıldı:", removed_file$name), "info")
  
		session$userData$file_summaries[[removed_file$name]] <- NULL
	  }
	}
  }, ignoreInit = TRUE)

  # 3. Add this new observer for clear all files:
  observeEvent(file_manager_data$all_files_cleared(), {
	if (isTRUE(file_manager_data$all_files_cleared())) {
	  # Clear all files from session
	  session_files(list())
	  session$userData$file_summaries <- list()
	  showToast(session, "Tüm dosyalar AI bağlamından temizlendi.", "warning")
	}
  }, ignoreInit = TRUE)
	
  # Process files added through file manager
  observeEvent(file_manager_data$files_added_to_context(), {
	files_to_add <- file_manager_data$files_added_to_context()
	req(files_to_add)
  
	processed_count <- 0
	for (file_info in files_to_add) {
	  if (!(file_info$name %in% names(session_files()))) {
		processAndSummarizeFile(
		  file_info,
		  current_user_id = current_user_id,
		  session = session,
		  settings = settings_data,
		  file_manager_data = file_manager_data,
		  session_files_reactive = session_files,
		  update_manager_ui = FALSE,
		  show_toast = FALSE,
		  auto_attach = FALSE
		)
		processed_count <- processed_count + 1
	  }
	}
  
	if (processed_count > 0) {
	  showToast(session, paste(processed_count, "dosya AI bağlamına eklendi."), "success")
	}
  }, ignoreInit = TRUE)

  # Settings observers
  observeEvent(settings_data$enable_timestamps, {
	session$sendCustomMessage("toggleAllTimestamps", list(enabled = settings_data$enable_timestamps))
  }, ignoreNULL = FALSE)
  
  observeEvent(settings_data$font_size, {
	values$current_font_size <- settings_data$font_size
	session$sendCustomMessage("updateFontSize", list(size = settings_data$font_size))
  })
  
  observeEvent(settings_data$enable_widescreen, {
	session$sendCustomMessage("toggleWidescreen", list(enabled = settings_data$enable_widescreen))
  })
	
  output$download_logs <- downloadHandler(
	filename = function() {
	  paste0("chat_logs_", format(Sys.Date(), "%Y%m%d"), ".csv")
	},
	content = function(file) {
	  logs_df <- fetch_user_activity_logs(current_user_id)
	  write.csv(logs_df, file, row.names = FALSE, fileEncoding = "UTF-8")
	}
  )
	
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

		  # Hata yutulmasın diye sarmalıyoruz
		  followup_questions <- build_followup_suggestions(last_user_text, result$content)

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
  send_message <- function(prompt_text) {
	
	# Track request start time for performance monitoring
	request_start_time <- Sys.time()
  
	# Debounce rapid requests
	if (values$is_sending) {
	  showToast(session, "Lütfen önceki isteğin tamamlanmasını bekleyin.", "warning")
	  return()
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

	if (skip_mcp_once) {
	  tool_family <- "none"
	} else if (cfg_sql_analysis_on) {
	  tool_family <- "sql_analysis"
	} else if (excel_allowed) {
	  tool_family <- "mcp_excel"
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
	display_text <- if (nchar(user_message_text) > 0) user_message_text else "Dosya(lar) hakkında soru soruldu."
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
	  is.null(m$content) || !grepl("\\[ Toplam Dosya Sayısı:", m$content, fixed = TRUE)
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
		"Example:\nKaynakça:\n1) document.docx\n2) file.pdf"
	  )
	} else {
	  paste0(
		"\n\nCRITICAL CITATION REQUIREMENT: ",
		"You MUST cite sources explicitly for every claim. ",
		"Use inline format: [Source: Name] or [Source: Name, URL]. ",
		"At the end of your response, always include a 'Sources' section listing all references with full details (name, URL, date if available). ",
		"Never provide factual information without explicit attribution."
	  )
	}
	
	style_instruction <- paste0(base_instruction, citation_instruction)
	
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
	
	# Türkçe yorum: MCP Excel'de araçları kullan; MCP kapalıyken özet/alıntı metinlerini enjekte et
	if (identical(tool_family, "mcp_excel") && uploaded_count > 0) {
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
	    
	    # 1. Analiz Modülünü Çalıştır (Sorgu Seç -> Çalıştır -> RLS Uygula)
	    analysis_result <- pk_analiz_process_request(user_message_text, recent_messages, session)
	    
		if (is.list(analysis_result) && identical(analysis_result$type, "data_analysis")) {
			  custom_system_msg <- list(type = "system", content = analysis_result$prompt_context)
			  custom_user_msg <- list(type = "user", content = analysis_result$user_context)
			  messages_to_process <- list(custom_system_msg, custom_user_msg)
			  
			  if (!is.null(analysis_result$max_tokens)) {
				current_settings$max_output_tokens <- analysis_result$max_tokens
			  }
	      
	    } else {
	      # 3. Hata veya Bilgi Mesajı
	      err_msg <- as.character(analysis_result)
	      messages_to_process <- list(
	        system_msg, 
	        list(type = "user", content = paste0(
	          "Kullanıcı sorusu: ", user_message_text, "\n\n",
	          "Sistem Analiz Raporu: ", err_msg, "\n\n",
	          "Bu durumu kullanıcıya açıkla."
	        ))
	      )
	    }
	    
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

			followup_questions <- build_followup_suggestions(user_message_text, res$content)
			
			local_char_id <- current_settings$selected_character %||% "mergen"
			local_chars_data <- get_characters_data()
			local_char_def <- if (!is.null(local_chars_data)) Find(function(x) x$id == local_char_id, local_chars_data$styles) else NULL
			resolved_voice <- if (!is.null(local_char_def) && !is.null(local_char_def$tts_voice)) local_char_def$tts_voice else "tr-male-1"

			simulate_streaming_stoppable(
			  res$content,
			  followups = followup_questions,
			  tts_engine = tts_processor$synthesize_speech,
			  tts_voice = resolved_voice,
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
  
  # chat action wiring (like/dislike/regenerate/edit)
  chatActionsInit(
	input, session, values,
	current_user_id      = current_user_id,
	send_message_fn      = send_message,
	stop_generation      = stop_generation,
	reset_chat_state     = reset_chat_state
  )

  observeEvent(input$quick_action_model_change, {
    req(input$quick_action_model_change)
    new_model_id <- input$quick_action_model_change

    # Hızlı eylem → bir sonraki istekte MCP kapalı (Toolsiyonel)
    quick_action_skip_mcp(TRUE)
    
    # Ayarlar modülündeki reaktif değeri güncelle (Ana Söyleşi'den yapılan değişiklik anında uygulanır)
    # Not: Ayarlar sayfasından yapılan değişiklikler ise "Kaydet" ile uygulanır.
    isolate({
      settings_data$model_selection <- new_model_id
    })
    
    # Ayarlar sayfasındaki dropdown'ı da senkronize et
    updateSelectInput(session, "settings_module-model_selection", selected = new_model_id)

    # Modelin Görünen Adını (Display Name) bul
    # api_config$local_models listesinden ismini çekiyoruz
    all_models <- api_config$local_models
    display_name <- names(all_models)[match(new_model_id, all_models)]
    
    if (is.na(display_name) || is.null(display_name) || display_name == "") {
      display_name <- new_model_id
    }

    # Kullanıcıya bilgi ver (Toast Mesajı)
    showToast(session, paste("Model değiştirildi:", display_name), "info")
    
    log_info(paste("[MAIN_CHAT] Hızlı model değişimi:", new_model_id))
  }, ignoreInit = TRUE)
	
  # 1. Model Seçici Dropdown (Ana Söyleşi Ekranı için)
  output$chat_model_selector_ui <- renderUI({
    current_val <- settings_data$model_selection
    models <- api_config$local_models
    descriptions <- api_config$local_model_descriptions %||% list()
    
    if (is.null(names(models))) names(models) <- models
    
    # Dropdown içeriğini oluştur
	menu_items <- lapply(seq_along(models), function(i) {
      m_name <- names(models)[i]
      m_id   <- models[[i]]
      is_active <- identical(as.character(m_id), as.character(current_val))
      desc <- descriptions[[m_id]] %||% m_name  # EKLENDI
      
      tags$li(
        tags$a(
          class = paste0("dropdown-item model-option", if(is_active) " active" else ""),
          href = "#",
          title = desc, 
          onclick = sprintf("Shiny.setInputValue('quick_action_model_change', '%s', {priority: 'event'}); return false;", m_id),
          div(
            class = "model-item-content",
            span(class = "model-name", m_name),
            if(is_active) icon("check", class = "selected-icon") else NULL
          )
        )
      )
    })

    div(
      title = "Model Değiştir", 
      shinyWidgets::dropdown(
        inputId = "chat_model_dropdown_container",
        style = "minimal",
        icon = icon("microchip"), 
        status = "default",  
        right = TRUE,        
        up = TRUE,           
        width = "250px",     
        
		div(
          class = "dropdown-menu-header",
          style = "padding: 8px 12px; border-bottom: 1px solid #4d4d4f; margin-bottom: 4px;",
          icon("layer-group"),
          tags$span(
            style = "font-weight: 600; font-size: 13px; text-transform: uppercase; letter-spacing: 0.5px;",
            "Model Kataloğu"
          )
        ),
        tags$ul(
          class = "dropdown-menu-custom-list",
          style = "list-style: none; padding: 0; margin: 0;",
          menu_items
        )
      )
    )
  })
  							 
  observeEvent(input$view_file_from_chat, {
	req(input$view_file_from_chat)
	file_id <- input$view_file_from_chat
	
	if (exists("file_store") && !is.null(file_store[[file_id]])) {
	  file_info <- file_store[[file_id]]
	  filePreview$open(file_info)
	} else {
	  showToast(session, "Dosya bulunamadı.", "error")
	}
  })
  
  # --- Observers for Main Chat UI ---
  observeEvent(input$send_stop_btn, {
	if (values$is_sending == TRUE) {
	  stop_generation(TRUE)
	  # Invalidate the active request (so any late future results are ignored)
	  active_request_id(paste0("cancelled_", as.integer(Sys.time())))
	  reset_chat_state()
	}
  }, ignoreInit = TRUE)

  observeEvent(input$send_prompt_from_js, {
	req(input$send_prompt_from_js)

	# Track request start time
	request_start <- Sys.time()
	
	# Per-user rate limiting check
	if (!check_rate_limit(current_user_id)) {
	  showToast(session, "Çok fazla istek gönderdiniz. Lütfen biraz bekleyin.", "warning")
	  return()
	}
	
	# Global rate limiting check (NEW)
	global_check <- check_global_rate_limit()
	if (!global_check$allowed) {
	  showToast(session, global_check$message, "warning")
	  return()
	}
	
	# Input validation
	user_text <- trimws(input$send_prompt_from_js$text)
	if (nchar(user_text) > 20000) {  # Max message length
	  showToast(session, "Mesaj çok uzun. Lütfen 20.000 karakterle sınırlayın.", "warning")
	  return()
	}
	
	# Continue with existing code
	send_message(input$send_prompt_from_js$text)
  })

  observeEvent(stop_generation(), {
	if (stop_generation() == TRUE) {
	  reset_chat_state()
	  showToast(session, "Yanıt oluşturma durduruldu.", "warning")
	}
  }, ignoreInit = TRUE)
  
	observeEvent(input$quick_template, {
	  # Hızlı eylem mesajı → MCP devre dışı (tek seferlik)
	  quick_action_skip_mcp(TRUE)
	  if (is.list(input$quick_template)) {
		send_message(input$quick_template$text)
	  } else {
		send_message(input$quick_template)
	  }
	}, ignoreInit = TRUE)
							   
	observeEvent(input$file_upload, {
	  req(input$file_upload)
	  handle_file_upload_batch(
		uploads_df           = input$file_upload,
		current_user_id      = current_user_id,
		session              = session,
		settings_data        = settings_data,
		file_manager_data    = file_manager_data,
		session_files_reactive = session_files,
		file_to_add_reactive = file_to_add
	  )
	}, ignoreInit = TRUE)
  
  observeEvent(input$voice_btn, {
    stt_data$start_session()
  }, ignoreInit = TRUE)
  
  observeEvent(stt_data$final_text(), {
    txt <- stt_data$final_text()
    if (nzchar(txt)) {
      send_message(txt)
    }
  })

  observeEvent(settings_data$enable_animations, {
	shinyjs::toggleClass(selector = "body", class = "animations-enabled", condition = settings_data$enable_animations)
  }, ignoreNULL = FALSE)
	  
  # This observer runs only once at startup to show the welcome screen
	observeEvent(TRUE, {
	  if (isTRUE(values$show_welcome)) {
					render_welcome_screen(values$saved_chats)
	  }

	  # ✅ Preload htmlwidget dependencies once (hidden)
	  if (requireNamespace("highcharter", quietly = TRUE)) {
		insertUI(
		  selector = "body", where = "beforeEnd",
		  ui = tags$div(
			style = "width:1px;height:1px;overflow:hidden;position:absolute;left:-9999px;top:-9999px;",
			highcharter::highchartOutput("deps_hc", width = "1px", height = "1px")
		  ),
		  immediate = TRUE
		)
	  }
	  if (requireNamespace("plotly", quietly = TRUE) && requireNamespace("ggplot2", quietly = TRUE)) {
		insertUI(
		  selector = "body", where = "beforeEnd",
		  ui = tags$div(
			style = "width:1px;height:1px;overflow:hidden;position:absolute;left:-9999px;top:-9999px;",
			tagList(
			  plotly::plotlyOutput("deps_pl", width = "1px", height = "1px"),
			  # Bazı bileşenler 'plotly_html' isminde çıktıyı bekleyebiliyor
			  plotly::plotlyOutput("plotly_html", width = "1px", height = "1px")
			)
		  ),
		  immediate = TRUE
		)
	  }
	}, once = TRUE)

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
	
	tts_warning_shown <- reactiveVal(FALSE)

	tts_unavailable_reason <- function() {
	  if (!isTRUE(isolate(settings_data$enable_tts_audio))) {
		return("AI yanıtlarını seslendirme ayarı kapalı.")
	  }
	  if (!is.list(tts_processor) || !is.function(tts_processor$tts_available)) {
		return("Seslendirme modülü yüklenemedi.")
	  }
	  avail <- FALSE
	  try(avail <- isTRUE(tts_processor$tts_available()), silent = TRUE)
	  if (!isTRUE(avail)) {
		return("Seslendirme uç noktası yapılandırılmadı.")
	  }
	  NULL
	}

	tts_enabled <- function() {
	  is.null(tts_unavailable_reason())
	}
	
	observeEvent(settings_data$enable_tts_audio, {
	  tts_warning_shown(FALSE)
	})

	attach_tts_audio <- function(message_id, audio_src, voice_used = NULL) {
	  if (is.null(message_id) || !nzchar(audio_src)) return(invisible(NULL))

	  # ... (mesaj güncelleme kısmı aynı kalıyor) ...
	  idx <- which(vapply(values$messages, function(m) m$id == message_id, logical(1)))
	  if (length(idx) == 1) {
		values$messages[[idx]]$audio_src <- audio_src
		values$messages[[idx]]$audio_voice <- voice_used
		if (!is.null(values$current_chat_id)) {
		  chat_store_message_in_saved_chats(values, values$messages[[idx]])
		}
	  }

	  try(removeUI(selector = sprintf("#tts_audio_%s", message_id), immediate = TRUE), silent = TRUE)
	  audio_ui <- build_tts_audio_ui(message_id, audio_src, voice_used)
	  if (!is.null(audio_ui)) {
		insertUI(
		  selector = sprintf("#message_wrapper_%s .ai-message", message_id),
		  where = "beforeEnd",
		  ui = audio_ui,
		  immediate = TRUE
		)
		
		# Türkçe: Sesi JS ile zorla oynat (Autoplay bazen browser tarafından engellenir, bu daha garantidir)
		shinyjs::runjs(sprintf("
		  setTimeout(() => {
			var audio = document.querySelector('#tts_audio_%s audio');
			if (audio) {
			  audio.volume = 1.0;
			  var playPromise = audio.play();
			  if (playPromise !== undefined) {
				playPromise.catch(error => {
				  console.log('Otomatik oynatma tarayıcı tarafından engellendi:', error);
				});
			  }
			}
			window.smartScrollToBottom && window.smartScrollToBottom();
		  }, 100);
		", message_id))
	  }
	}

# TTS Tetikleyici Fonksiyon (Modified for Low Latency)
	  trigger_tts_for_message <- function(msg_id, content) {
		if (!isTRUE(settings_data$enable_tts_audio)) return(invisible(NULL))
		
		full_text <- as.character(content)[1]
		if (!nzchar(full_text)) return(invisible(NULL))
		
		selected_char_id <- isolate(settings_data$selected_character) %||% "mergen"
		chars_data <- get_characters_data()
		character_data <- if (!is.null(chars_data)) {
		  Find(function(x) x$id == selected_char_id, chars_data$styles)
		} else NULL
		voice_sel <- if (!is.null(character_data) && !is.null(character_data$tts_voice)) {
		  character_data$tts_voice
		} else {
		  "tr-male-1"
		}
		
		# Helper: Send chunk to client
		send_chunk <- function(res, idx) {
		  if (isTRUE(stop_generation())) return()
		  
		  if (isTRUE(res$success) && nzchar(res$audio_src)) {
			cat(sprintf("[TTS] Sending chunk %d (Duration: %.2fs)\n", idx, res$duration))
			
			# Trigger the header visualizer
			tts_visualizer$trigger(duration = res$duration) # <--- ADDED
			
			session$sendCustomMessage("playAudioMessage", list(
			  id = msg_id,
			  src = res$audio_src,
			  chunkIndex = idx,
			  timestamp = as.numeric(Sys.time())
			))
		  }
		}
		
# 2. Optimized Split Logic:
		# Türkçe: İlk sesin çok hızlı gelmesi için eşiği düşürdük (15 karakter).
		# Virgül (,) dahil edilerek ilk nefes payında bölme yapılır.
		if (nchar(full_text) > 15) {
		  # İlk 50 karaktere bak (pencere küçültüldü)
		  search_window <- substr(full_text, 1, 50)
		  
		  # Noktalama işaretlerini ara (Virgül eklendi!)
		  split_pos <- -1
		  punct_match <- regexpr("[.,?!:;](?=\\s|$)", search_window, perl = TRUE)
		  
		  if (punct_match > 0) {
            # İlk bulunan noktalama işaretinden böl
			split_pos <- punct_match + attr(punct_match, "match.length") - 1
		  } else {
			# Noktalama yoksa, 10. karakterden sonraki ilk boşluğu bul (Fallback)
			spaces <- gregexpr("\\s", search_window)[[1]]
            valid_spaces <- spaces[spaces > 10]
			if (length(valid_spaces) > 0) {
              # İlk uygun boşluktan böl (erken yanıt için)
			  split_pos <- valid_spaces[1]
			} else if (length(spaces) > 0 && spaces[1] > 0) {
              # Hiç uygun yoksa penceredeki son boşluğu al
              split_pos <- tail(spaces, 1)
            }
		  }

		  if (split_pos > 2) { # En az 2 harflik anlamlı bir parça olsun
			first_chunk <- substr(full_text, 1, split_pos)
			remainder   <- trimws(substr(full_text, split_pos + 1, nchar(full_text)))
			
			if (nzchar(remainder)) {
			  cat("[TTS] Fast split active. Chunk 1:", nchar(first_chunk), "chars.\n")
			  
			  # Critical: Fire Chunk 1 immediately
			  p1 <- tts_processor$synthesize_speech(first_chunk, voice = voice_sel)
			  
			  # Fire Chunk 2 (remainder) in parallel
			  p2 <- tts_processor$synthesize_speech(remainder, voice = voice_sel)
			  
			  p1 %...>% (function(res) send_chunk(res, 0)) %...!% (function(e) warning("TTS C1 fail"))
			  p2 %...>% (function(res) send_chunk(res, 1)) %...!% (function(e) warning("TTS C2 fail"))
			  
			  return(invisible(NULL))
			}
		  }
		}
		
		# Fallback: Single request (Short text or split failed)
		tts_processor$synthesize_speech(full_text, voice = voice_sel) %...>% 
		  (function(res) send_chunk(res, 0)) %...!% 
		  (function(e) cat("[TTS] Error:", conditionMessage(e), "\n"))
		
		invisible(NULL)
	  }

	start_new_chat <- function() {
	  chat_start_new_chat(session, values, saved_chats_data, session_files, filePreview, current_user_id, file_manager_data)
	}

	# Çok temel bir perspektif düzeltici (fazla agresif olmasın)
	ensure_user_perspective <- function(texts) {
	  if (is.null(texts) || !length(texts)) return(texts)
	  out <- texts

	  # Örnek: "Programın çıktısını değiştirmek istiyor musunuz?"
	  #  → "Programın çıktısını değiştirmek istiyorum, nasıl yapabilirim?"
	  out <- gsub(
		"istiyor musunuz\\?$",
		"istiyorum, nasıl yapabilirim?",
		out,
		ignore.case = TRUE
	  )

	  # Örnek: "X yapmak ister misiniz?" → "X yapmak istiyorum, nasıl yapabilirim?"
	  out <- gsub(
		"ister misiniz\\?$",
		"istiyorum, nasıl yapabilirim?",
		out,
		ignore.case = TRUE
	  )

	  out
	}

	normalize_followup_texts <- function(items, limit = 3L) {
	  if (is.null(items) || !length(items)) return(NULL)
	  texts <- trimws(as.character(items))
	  texts <- texts[nzchar(texts)]
	  if (!length(texts)) return(NULL)
	  texts <- texts[!duplicated(texts)]
	  if (!length(texts)) return(NULL)

	  texts <- texts[nchar(texts) > 3]
	  texts <- substr(texts, 1, 220)

	  texts <- ensure_user_perspective(texts)

	  needs_q <- !grepl("\\?$", texts, perl = TRUE)
	  texts[needs_q] <- paste0(texts[needs_q], "?")

	  max_items <- max(1L, as.integer(limit %||% 3L))
	  head(texts, max_items)
	}

	strip_code_fences <- function(payload) {
	  cleaned <- gsub("^```[a-zA-Z0-9_-]*\\s*", "", payload)
	  cleaned <- gsub("\\s*```$", "", cleaned)
	  cleaned <- gsub("```json", "", cleaned, ignore.case = TRUE)
	  cleaned <- gsub("```", "", cleaned)
	  trimws(cleaned)
	}

	parse_followup_payload <- function(payload) {
	  if (!is.character(payload) || length(payload) == 0) return(NULL)
	  text <- trimws(payload[1] %||% "")
	  if (!nzchar(text)) return(NULL)

	  cleaned <- strip_code_fences(text)
	  parsed <- tryCatch(jsonlite::fromJSON(cleaned), error = function(e) NULL)
	  if (is.null(parsed)) {
		return(NULL)
	  }

	  if (is.list(parsed) && !is.null(parsed$followups)) {
		as.character(parsed$followups)
	  } else if (is.list(parsed) && !is.null(parsed$questions)) {
		as.character(parsed$questions)
	  } else if (is.list(parsed) && !is.null(parsed$sorular)) {
		as.character(parsed$sorular)
	  } else if (is.character(parsed)) {
		parsed
	  } else if (is.vector(parsed) && !is.list(parsed)) {
		as.character(parsed)
	  } else {
		NULL
	  }
	}

	truncate_followup_context <- function(text, limit = 2000L) {
	  if (!is.character(text) || length(text) == 0) return("")
	  val <- text[1] %||% ""
	  if (!nzchar(val)) return("")
	  if (nchar(val) <= limit) return(val)
	  paste0(substr(val, 1, limit), " …")
	}

	generate_ai_followups <- function(user_text, ai_text) {
	  combined <- paste(user_text %||% "", ai_text %||% "")
	  if (!nzchar(trimws(combined))) {
		return(NULL)
	  }

	  selected_model <- settings_data$model_selection %||% as.character(api_config$local_models[1])
	  request_settings <- list(
		model_selection = selected_model,
		temperature = 0.55,
		enable_mcp_tools = FALSE,
		tool_family = "none",
		shiny_session = session
	  )
	  api_override <- session$userData$ai_api_key %||% NULL
	  if (!is.null(api_override) && nzchar(api_override)) {
		request_settings$api_key_override <- api_override
	  }

	  system_prompt <- paste(
		"Sen MERGEN Bilge arayüzünde takip soruları oluşturan yardımcı bir modülsün.",
		"Yalnızca JSON olarak yanıt ver ve formatı bozma.",
		"Şema: {\"followups\": [\"soru1\", \"soru2\", \"soru3\"]}.",
		"Her soru Türkçe olmalı, 6-18 kelime arası olmalı ve '?' ile bitmeli.",
		"SORULARI KULLANICININ AĞZINDAN YAZ: Bunlar, kullanıcının bir sonraki turda asistanla konuşurken soracağı sorular olsun.",
		"Kullanıcıya hitap eden biçimler (\"istiyor musunuz\", \"ister misiniz\", \"ister miydiniz\" vb.) KULLANMA.",
		"Bunun yerine birinci tekil kişi kullan: örn. \"... nasıl yapabilirim?\", \"... bana gösterebilir misin?\", \"... hakkında daha ayrıntılı anlatır mısın?\"",
		"Örnek yanlış: \"Programın çıktısını nasıl değiştirmek istersiniz?\"",
		"Örnek doğru:  \"Programın çıktısını nasıl değiştirebilirim?\"",
		"Ek açıklama, markdown veya düz yazı ekleme."
	  )

	  context_prompt <- paste(
		"Kullanıcının sorusu:", truncate_followup_context(user_text %||% ""),
		"\n\nAsistanın yanıtı:", truncate_followup_context(ai_text %||% ""),
		"\n\nTalimat: Bu yanıtı okuyan KULLANICININ, bir sonraki turda asistan'a sorabileceği 3 kısa takip sorusu öner.",
		"Soruları mutlaka kullanıcının bakış açısından yaz (\"Ben\", \"bana\", \"nasıl ... yapabilirim?\" gibi)."
	  )

	  messages <- list(
		list(type = "system", content = system_prompt),
		list(type = "user", content = context_prompt)
	  )

	  ai_response <- tryCatch({
		call_local_llm(messages, request_settings)
	  }, error = function(err) {
		cat("[FOLLOWUPS][AI] generation failed:", conditionMessage(err), "\n")
		NULL
	  })

	  if (is.null(ai_response)) {
		return(NULL)
	  }

	  payload <- ai_response$content %||% ""
	  payload <- as.character(payload)[1]
	  parsed <- parse_followup_payload(payload)
	  normalize_followup_texts(parsed, limit = 3L)
	}
		
	build_followup_suggestions <- function(user_text, ai_text) {
          enabled_flag <- settings_data$enable_followups
          if (is.null(enabled_flag)) {
            enabled_flag <- TRUE
          }
          if (!isTRUE(enabled_flag)) {
		return(NULL)
	  }

      generator <- followup_tools$generate
          if (!is.function(generator)) {
            generator <- fallback_followup_tool$generate
	  }
	  
	  ai_suggestions <- generate_ai_followups(user_text, ai_text)
	  if (!is.null(ai_suggestions) && length(ai_suggestions) >= 2) {
		return(ai_suggestions)
	  }

	  safe_generate <- function(fn) {
		if (!is.function(fn)) return(NULL)
		tryCatch(
		  fn(user_text %||% "", ai_text %||% "",
			 min_questions = 2L, max_questions = 3L),
		  error = function(e) NULL
		)
	  }

	  suggestions <- safe_generate(generator)
	  if (is.null(suggestions) || !length(suggestions)) {
		suggestions <- safe_generate(fallback_followup_tool$generate)
	  }

	  if (is.null(suggestions) || !length(suggestions)) {
		return(NULL)
	  }

	  suggestions <- unique(trimws(as.character(suggestions)))
	  suggestions <- suggestions[nzchar(suggestions)]
	  if (!length(suggestions)) {
		return(NULL)
	  }

	  head(suggestions, 3L)
	}

  # Load saved chat observer with debouncing
  load_chat_in_progress <- reactiveVal(FALSE)
  
  observeEvent(saved_chats_data$load_chat_id(), {
	chat_id <- saved_chats_data$load_chat_id()

	# Prevent duplicate loads
	if (load_chat_in_progress()) {
	  return()
	}

	load_chat_in_progress(TRUE)

	chat_to_load <- values$saved_chats[[chat_id]]
	needs_hydrate <- is.null(chat_to_load)

	if (!needs_hydrate) {
	  msgs <- chat_to_load$messages
	  stored_len <- if (is.list(msgs)) length(msgs) else 0L
	  expected_len <- as.integer(chat_to_load$message_count %||% stored_len)
	  has_user <- stored_len > 0 && any(vapply(msgs, function(m) {
		identical(m$type %||% "", "user")
	  }, logical(1)))
	  has_ai <- stored_len > 0 && any(vapply(msgs, function(m) {
		m$type %||% "" %in% c("ai", "assistant")
	  }, logical(1)))

	  needs_hydrate <- is.null(msgs) || !is.list(msgs) || stored_len == 0 ||
		(!is.na(expected_len) && expected_len > stored_len) ||
		(has_user && !has_ai)
	}

	if (isTRUE(needs_hydrate)) {
	  detail <- tryCatch(
			load_chat_messages_from_db(chat_id),
			error = function(e) {
			  warning(sprintf("Failed to load chat %s messages: %s", chat_id, e$message))
			  NULL
			}
	  )
	  if (!is.null(detail)) {
			chat_to_load <- detail
			saved_copy <- values$saved_chats
			saved_copy[[chat_id]] <- chat_to_load
			values$saved_chats <- saved_copy
	  }
	}

	if (!is.null(chat_to_load)) {
	  removeUI(selector = "#chat_content_container > *", multiple = TRUE)

	  values$messages <- chat_to_load$messages %||% list()
	  all_feedback <- load_feedback_from_db(current_user_id)
	  values$liked_messages <- all_feedback$liked
	  values$disliked_messages <- all_feedback$disliked
	  values$current_chat_id <- chat_id
	  values$show_welcome <- FALSE
	  
	if (length(values$messages) > 0) {
	  for (i in seq_along(values$messages)) {
		msg <- values$messages[[i]]
		is_last_user_msg <- (msg$type == "user" && i == length(values$messages))
		
		# Get character data for this message
		selected_char_id <- isolate(settings_data$selected_character) %||% "mergen"
		chars_data <- get_characters_data()
		character_data <- if (!is.null(chars_data)) {
		  Find(function(x) x$id == selected_char_id, chars_data$styles)
		} else NULL
		
		ui_to_insert <- render_message_bubble_ui(
		  msg, settings_data,
		  is_last_user_message = is_last_user_msg,
		  character_data = character_data,
		  liked_ids = values$liked_messages,
		  disliked_ids = values$disliked_messages
		)
		
		insertUI(
		  selector = "#chat_content_container",
		  where = "beforeEnd",
		  ui = ui_to_insert
		)
		
		wrapper_id <- paste0("message_wrapper_", msg$id)
		
		if (isTRUE(msg$has_code)) {
		  shinyjs::runjs(sprintf("
			setTimeout(() => { 
			  if (window.initializeCodeMirrorInElement) {
				window.initializeCodeMirrorInElement('%s');
			  }
			  const wrapper = document.getElementById('%s');
			  if (wrapper) {
				const cmInstances = wrapper.querySelectorAll('.CodeMirror');
				cmInstances.forEach(cm => {
				  if (cm.CodeMirror) cm.CodeMirror.refresh();
				});
			  }
			}, 200);
		  ", wrapper_id, wrapper_id))
		}
		
		if (msg$type == "ai" && grepl("data-chartlab-spec", msg$html_content %||% "", fixed = TRUE)) {
		  shinyjs::delay(300, {
			shinyjs::runjs(sprintf(
			  "window.renderSavedCharts && window.renderSavedCharts('%s');",
			  wrapper_id
			))
		  })
		}
	  }
	  
	  shinyjs::runjs("setTimeout(() => { scrollToBottom(false); }, 300);")
	}
	  
	  updateTabItems(session, "tabs", "chat")
	  showToast(session, paste("Söyleşi yüklendi:", chat_to_load$title), "info")
	}
	
	# Reset flag after a delay
	shinyjs::delay(1000, {
	  load_chat_in_progress(FALSE)
	})
  }, ignoreInit = TRUE)
  
  # Rest of observers...
  observeEvent(file_manager_data$message_trigger(), {
	req(file_manager_data$message_trigger() > 0)

	msg <- file_manager_data$get_message()

	if (!is.null(msg)) {
	  if (identical(msg$type, "view_file")) {
			file_id <- msg$content
			file_info <- file_manager_data$file_contents()[[file_id]]
			if (!is.null(file_info)) {
			  openAnyPreview(file_info, session, filePreview)
			}
	  } else {
			add_message(msg$content, type = "system", html = msg$html)
	  }
	}
  }, ignoreInit = TRUE)
	
  observeEvent(saved_chats_data$delete_chat_id(), {
	chat_id <- saved_chats_data$delete_chat_id()
	req(chat_id)
	delete_chat_from_db(chat_id, current_user_id)

	values$saved_chats <- load_chats_from_db(current_user_id, include_messages = FALSE)
	saved_chats_data$refresh()
  
  }, ignoreInit = TRUE)
  
  observeEvent(saved_chats_data$clear_all_chats_trigger(), {
	if(saved_chats_data$clear_all_chats_trigger() > 0) {
	  clear_all_chats_from_db(current_user_id)
	  values$saved_chats <- list()
	  saved_chats_data$refresh()
	  showToast(session, "Tüm söyleşiler temizlendi.", "warning")
	}
  }, ignoreInit = TRUE)
  
  # Other event observers (like, dislike, regenerate, etc.) remain the same...
  # [Keep all these as they were]

  observeEvent(input$new_chat_btn, {
        start_new_chat()
  }, ignoreInit = TRUE)

  observeEvent(input$followup_question_clicked, {
        req(is.list(input$followup_question_clicked))
        req(nzchar(input$followup_question_clicked$text %||% ""))
        send_message(input$followup_question_clicked)
  }, ignoreInit = TRUE)
						  
  output$message_count <- renderText({ length(values$messages) })
  output$show_welcome_screen <- reactive({ values$show_welcome })
  outputOptions(output, "show_welcome_screen", suspendWhenHidden = FALSE)
																							  
  observeEvent(input$last_active_tab, {
	updateTabItems(session, "tabs", selected = input$last_active_tab)
  })
		  
  observeEvent(values$messages, {
	if (length(values$messages) > 0) {
	  session$sendCustomMessage("saveCurrentChat", values$messages)
	}
  }, ignoreNULL = FALSE, ignoreInit = TRUE)
  
  observeEvent(input$load_chat_from_storage, {
	req(input$load_chat_from_storage)
	if (length(values$messages) == 0 && !is.null(input$load_chat_from_storage)) {
	  
	  removeUI(selector = "#chat_content_container > *", multiple = TRUE)
	  
	  values$messages <- input$load_chat_from_storage
	  values$show_welcome <- FALSE
	  
	  if (length(values$messages) > 0) {
		for (i in seq_along(values$messages)) {
		  msg <- values$messages[[i]]
		  is_last_user_msg <- (msg$type == "user" && i == length(values$messages))
		  
		  # Get character data
		  selected_char_id <- isolate(settings_data$selected_character) %||% "mergen"
		  chars_data <- get_characters_data()
		  character_data <- if (!is.null(chars_data)) {
			Find(function(x) x$id == selected_char_id, chars_data$styles)
		  } else NULL
		  
		  ui_to_insert <- render_message_bubble_ui(
			msg, settings_data,
			is_last_user_message = is_last_user_msg,
			character_data = character_data,
			liked_ids = values$liked_messages,
			disliked_ids = values$disliked_messages
		  )

		  insertUI(selector = "#chat_content_container", where = "beforeEnd", ui = ui_to_insert)
		  
		  if(isTRUE(msg$has_code)) {
			 wrapper_id <- paste0("message_wrapper_", msg$id)
			 shinyjs::runjs(sprintf("setTimeout(() => { window.initializeCodeMirrorInElement('%s'); }, 200);", wrapper_id))
		  }
		}
		shinyjs::runjs("setTimeout(() => { scrollToBottom(false); }, 100);")
		
		# [MODIFICATION] Restore charts for the loaded messages
		# Geçmiş sohbet yüklendiğinde grafikleri (output slotlarını) yeniden bağla
		chat_rebind_all_charts(session, output, values$messages)
	  }
	  
	  showToast(session, "Önceki sohbetiniz geri yüklendi.", "info")
	}
  }, ignoreInit = TRUE)
}
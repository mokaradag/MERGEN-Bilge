# server.R

# ---- RData Lake sınırları (tam analiz için yüksek değerler) ----
# Not: Bu sınırlar ilk yenilemede tüm metrikleri/varlıkları kapsayacak kadar büyük tutulur.
options(
  # Türkçe yorum: Inf veya <=0 ⇒ SINIRSIZ (tam analiz)
  mergen.rdata.max_entity_aggs     = Inf,
  mergen.rdata.max_metrics         = Inf,
  mergen.rdata.max_metrics_profile = Inf,
  mergen.rdata.profile_batch_size  = 50,   # profil için parti boyutu (çok yüksek tutmayın)
  mergen.rdata.preview_metrics     = 3,    # sadece fallback listede gösterim
  mergen.rdata.force_preview_limit = FALSE,# SELECT'e otomatik LIMIT ekleme (analizde kapalı)
  mergen.duckdb.threads = parallel::detectCores(),
  mergen.duckdb.memory_limit = "16GB"
)

## Hızlı test modunda:
# options(
#   mergen.rdata.max_entity_aggs     = 5,     # Testte az sayıda varlık
#   mergen.rdata.max_metrics         = 100,   # Testte en çok 100 metrik
#   mergen.rdata.max_metrics_profile = 50,    # Profil açılırsa 50 ile sınırla
#   mergen.rdata.profile_batch_size  = 25,    # Küçük partiler → bellek/IO yükü azalır
#   mergen.rdata.preview_metrics     = 3,
#   mergen.rdata.force_preview_limit = TRUE,  # SELECT'lere otomatik LIMIT ekle (güvenli)
#   mergen.duckdb.threads            = max(1L, parallel::detectCores() %/% 2L), # CPU'nun yarısı
#   mergen.duckdb.memory_limit       = "8GB"  # RAM tavanını düşür
# )

# ---- Uygulama açılışında lake motoru ve ağır işler ----
try({
  helpers_rdata_lake$rdata_engine_init()   # Türkçe: Doğru isim alanından çağır
  cat("[SERVER] RData engine initialized\n")
  if (isTRUE(getOption("mergen.rdata.refresh_on_boot", FALSE))) {
    helpers_rdata_lake$rdata_refresh_all() # Türkçe: Ağır yenilemeyi seçenek açıkken çalıştır
  }
}, silent = FALSE)

server <- function(input, output, session) {

  # ==== FIX: copy uploads to MCP base immediately ====
  mcp_saved_path <- reactiveVal(NULL)
  
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
  
  # RData admin: JS ile input$rdata_admin-refresh_now tetiklenebilir
  rdataAdminServer("rdata_admin")

  # Initialize AI processing module
  ai_processor <- aiProcessingServer("ai_proc")
  
  # Initialize File Preview module (replaces preview outputs + modal helpers)
  filePreview <- filePreviewServer("file_preview")
  
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
  
  # --- Module Server Initialization ---
  settings_data <- settingsServer("settings_module", parent_session = session)
  
	observeEvent(input$`settings_module-open_api_key_modal`, {
		api_key$open("API Anahtarı Güncelleme")
	  }, ignoreInit = TRUE)
	
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
		
	# Karakter avatarı, karakter adı ve model adını Ana Söyleşi başlığında göster
	output$current_model_display <- renderUI({
	  # Model bilgisini al
	  selected_model_id <- settings_data$model_selection %||% api_config$local_models[1]
	  display_name <- names(api_config$local_models)[api_config$local_models == selected_model_id]
	  if (length(display_name) == 0) display_name <- selected_model_id
	  
	  # Karakter bilgisini al
	  selected_char_id <- settings_data$selected_character %||% "mergen"
	  chars_data <- get_characters_data()
	  char_info <- Find(function(x) x$id == selected_char_id, chars_data$styles)
	  
	  # Varsayılan değerler (karakter bulunamazsa)
	  if (is.null(char_info)) {
		char_info <- list(
		  display_name = "MERGEN",
		  avatar = "characters/avatar/Mergen_avatar_original.png",
		  accent = "#7C4DFF"
		)
	  }
	  
	  # Arka plan rengini karakter vurgu rengine göre ayarla (şeffaflıkla)
	  bg_color <- paste0(char_info$accent, "26")  # %15 opaklık için hex alpha değeri
	  border_color <- paste0(char_info$accent, "40")  # %25 opaklık
	  
	  # UI elemanını oluştur: <avatar> <karakter adı> ": " <model adı>
	  div(
		class = "header-stat-item",
		title = paste0("Karakter: ", char_info$display_name, " | Model: ", display_name),
		style = paste0(
		  "background: ", bg_color, "; ",
		  "border-color: ", border_color, ";"
		),
		tags$img(
		  src = char_info$avatar,
		  alt = char_info$display_name,
		  style = "width: 20px; height: 20px; border-radius: 50%; object-fit: cover; margin-right: 6px;"
		),
		span(
		  style = "font-weight: 600; color: #e5e5e5;",  # Açık gri renk - arka planla iyi kontrast sağlar
		  paste0(char_info$display_name, ": ", display_name)
		)
	  )
	})
  
  # MCP modu göstergesi için reaktif çıktı (Ana Söyleşi başlığında kullanılır)
  output$mcp_mode_indicator <- renderUI({
    excel_active <- isTRUE(settings_data$enable_mcp_tools)
    rdata_active <- isTRUE(settings_data$enable_rdata_tools)
    
    if (excel_active) {
      # Excel MCP aktif - yeşil gösterge
      div(
        class = "mcp-indicator excel-active",
        tags$i(class = "fas fa-file-excel"),
        span("Excel MCP")
      )
    } else if (rdata_active) {
      # RData aktif - mavi gösterge
      div(
        class = "mcp-indicator rdata-active",
        tags$i(class = "fas fa-database"),
        span("RData MCP")
      )
    } else {
      # Hiçbiri aktif değil - gösterge yok
      NULL
    }
  })

  # Pass values reactive to file manager for temp_files access
	file_manager_data <- fileManagerServer(
	  "file_manager_module",
	  new_file_trigger = reactive({ file_to_add() }),
	  session_files_reactive = session_files,
	  mcp_enabled_reactive = reactive({ isTRUE(settings_data$enable_mcp_tools) })
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
  generate_non_streaming_stoppable <- function(chat_history, current_settings, user_prompt_msg, chat_id_val, model_selected) {
	
	# DEBUG: snapshot request (non-streaming)
	safe_settings <- current_settings; safe_settings$shiny_session <- NULL
	dbg_dump("LLM_REQUEST_NONSTREAM", list(model = model_selected, messages = chat_history, settings = safe_settings))
	
	# Call AI module
	p <- ai_processor$call_llm_non_streaming(chat_history, current_settings, model_selected)
	
	# Chain onto the returned promise and use that going forward
	p2 <- promises::then(
	  p,
	  onFulfilled = function(result) {
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
				  if (!is.null(fp) && nzchar(fp) && file.exists(fp) &&
					  exists("helpers_mcp_tools", inherits = TRUE) &&
					  is.function(helpers_mcp_tools$prepare_chart_data)) {

					fb <- try(helpers_mcp_tools$prepare_chart_data(
					  file_name  = fp,
					  chart_type = "auto",
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
		  tryCatch({
			ai_msg <- add_message(result$content, "ai")
		  }, error = function(e) {
			cat("[AI_RESP][ADD_MESSAGE_ERROR] ", conditionMessage(e), "\n", sep="")
			cat("[AI_RESP][ADD_MESSAGE_ERROR] dput(content)= "); dput(result$content); cat("\n")
			showToast(session, "Render hatası: içerik boş/uygunsuz. Günlüğe yazıldı.", "error")
			# Sohbet akışını bozmamak için placeholder
			ai_msg <- add_message("⚠️ Model boş bir yanıt döndürdü (loglandı).", "ai")
		  })

		  tryCatch({
			log_ai_usage(chat_id_val, user_prompt_msg$db_id, current_user_id, 
						 model_selected, result$duration, TRUE)
		  }, error = function(e) {
			print(paste("Logging error:", e$message))
		  })
		  
			# Yanıt sonrası rData durumunu yalnızca bu istekte gerçekten rData kullanıldıysa temizle
			tf <- current_settings$tool_family %||% "none"
			if (identical(tf, "rdata")) {
			  try(helpers_rdata_lake$rdata_reset_state("after_response"), silent = TRUE)
			}
		  
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
	
	# --- Bu istek için araç ailesini belirle (mcp_excel | rdata | none) ---
	# Basit niyet bulucu: proje/kaynak/işçilik vb. rData konusudur
	is_rdata_intent <- function(txt) {
	  grepl("(proje|kaynak|işçilik|iscilik|wbs|p6|direktörlük|müdürlük|aktivite)",
			tolower(txt %||% ""), perl = TRUE)
	}

	# Kullanıcı ayarları: her iki kutu
	cfg_excel_on  <- isTRUE(settings_data$enable_mcp_tools)
	cfg_rdata_on  <- isTRUE(settings_data$enable_rdata_tools)

	# Hızlı eylemden geliyorsa MCP'yi tek seferlik kapat
	skip_mcp_once <- isTRUE(quick_action_skip_mcp())
	if (skip_mcp_once) quick_action_skip_mcp(FALSE)

	# Öncelikli kural: Hızlı eylem → araç yok
	rdata_allowed <- isTRUE(cfg_rdata_on)
	excel_allowed <- isTRUE(cfg_excel_on) && uploaded_count > 0

	if (skip_mcp_once) {
	  tool_family <- "none"
	} else if (rdata_allowed && is_rdata_intent(user_message_text)) {
	  tool_family <- "rdata"
	} else if (excel_allowed) {
	  tool_family <- "mcp_excel"
	} else if (rdata_allowed) {
	  tool_family <- "rdata"
	} else {
	  tool_family <- "none"
	}
	
	# Türkçe yorum: rData kullanılacaksa her zaman durumu sıfırla
	if (identical(tool_family, "rdata")) {
	  try(helpers_rdata_lake$rdata_reset_state("new_rdata_request"), silent = TRUE)
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
			if (nzchar(fpath) && file.exists(fpath)) {
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
	  # Türkçe yorum: rdata ise sade mesaj; aksi halde normal bağlam
	  if (identical(tool_family, "rdata")) {
		messages_to_process <- list(system_msg, list(type = "user", content = user_message_text))
	  } else {
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
	
	shinyjs::runjs("$('#send_stop_btn i').attr('class', 'fa-solid fa-stop');")
	shinyjs::runjs("$('#send_stop_btn').addClass('stop-mode');")
	shinyjs::runjs("$('#send_stop_btn').attr('title', 'Durdur');")
	
	values$is_sending <- TRUE
	stop_generation(FALSE)
	
	chat_id_val <- isolate(values$current_chat_id)
	
	if (!is.null(input$quick_action_model_change)) {
	  Sys.sleep(0.1) # Small delay to ensure settings are updated
	}
	
	# === NEW: Read the model selection from settings_data via reactiveValuesToList ===
	current_settings <- reactiveValuesToList(settings_data)
	model_selected <- current_settings$model_selection

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
	cat("[TOOLS] enabled:", current_settings$enable_mcp_tools, "\n")
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
		  cat("[MCP]   -", fname, "->", fpath, "(exists:", file.exists(fpath), ")\n")
		}
	  }
	} else {
	  cat("[MCP] NO FILES STORED - MCP will not work!\n")
	}
	cat("================================\n\n")
	
	# Yalnızca Excel modunda dosyaları MCP tabanına koy
	if (identical(tool_family, "mcp_excel") && length(fm_files) > 0) {
	  csf <- session$userData$current_session_files %||% list()
	  for (fid in names(fm_files)) {
		finfo <- fm_files[[fid]]
		file_obj <- list(
		  name     = finfo$name,
		  datapath = finfo$datapath %||% finfo$path,
		  path     = finfo$datapath %||% finfo$path
		)
		# Store by BOTH filename and token
		csf[[finfo$name]] <- file_obj
		csf[[fid]] <- file_obj

		# Persist ONLY if MCP tools are enabled; keep temp flow otherwise
		tryCatch({
			if (isTRUE(current_settings$enable_mcp_tools)) {
			  path_now <- file_obj$path
			  if (!is_under_mcp_base(path_now)) {
				path_now <- copy_to_mcp_base(list(name = finfo$name, datapath = path_now), current_user_id)
				file_obj$path <- path_now
				file_obj$datapath <- path_now
				csf[[finfo$name]] <- file_obj
				csf[[fid]] <- file_obj
			  }
			  # NOTE: registration now happens only in processAndSummarizeFile(), to avoid duplicates
			}
		}, error = function(e) {
		  cat("[GLOBAL REGISTRY] Failed:", e$message, "\n")
		})
	  }
	  session$userData$current_session_files <- csf
	  cat("[FILE STORE] MCP files (by filename): ",
		  paste(names(csf), collapse = ", "), "\n", sep = "")
	}

	# DOSYA yollarını yalnızca Excel modunda ilet
	current_settings$file_paths <- list()
	if (identical(tool_family, "mcp_excel") && length(current_session_files) > 0) {
	  for (fname in uploaded_names) {
		file_obj <- current_session_files[[fname]]
		
		# Try multiple path sources
		full_path <- NULL
		if (is.list(file_obj)) {
		  full_path <- file_obj$datapath %||% file_obj$path %||% file_obj$name
		} else if (is.character(file_obj)) {
		  full_path <- file_obj
		}
		
		if (!is.null(full_path)) {
		  current_settings$file_paths[[fname]] <- as.character(full_path)
		  cat("[FILE PATH ADDED]", fname, "->", full_path, "\n")
		}
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

			removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
			values$typing <- FALSE

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

			simulate_streaming_stoppable(res$content)
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
	  generate_non_streaming_stoppable(messages_to_process, current_settings, user_prompt_msg, chat_id_val, model_selected)
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
	  new_model <- input$quick_action_model_change

	  # Hızlı eylem → bir sonraki istekte MCP kapalı
	  quick_action_skip_mcp(TRUE)
	  
	  print(paste("Quick action model change requested:", new_model))
	  
	  # Update the settings module's dropdown
	  updateSelectInput(session, "settings_module-model_selection", selected = new_model)
	  
	  # IMPORTANT: Directly update the settings_data reactive values
	  isolate({
		settings_data$model_selection <- new_model
	  })
		  
	  print(paste("Model updated to:", new_model))
	}, ignoreInit = TRUE)
							 
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
	showToast(session, "Sesli giriş yakında eklenecek", "info")
  }, ignoreInit = TRUE)

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

	simulate_streaming_stoppable <- function(full_response) {
	  chat_simulate_streaming(full_response, session, values, settings_data, output, stop_generation)
	}

	add_message <- function(content, type = "user", html = NULL) {
	  chat_add_message(session, values, settings_data, output, content, type, html, current_user_id)
	}

	start_new_chat <- function() {
	  chat_start_new_chat(session, values, saved_chats_data, session_files, filePreview, current_user_id)
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
	if (!is.null(chat_to_load) && (is.null(chat_to_load$messages) || length(chat_to_load$messages) == 0)) {
	  detail <- tryCatch(
		load_chat_messages_from_db(chat_id),
		error = function(e) {
		  warning(sprintf("Failed to load chat %s messages: %s", chat_id, e$message))
		  NULL
		}
	  )
	  if (!is.null(detail)) {
		if (!is.null(detail$title) && !is.na(detail$title)) {
		  chat_to_load$title <- detail$title
		}
		if (!is.null(detail$timestamp) && !is.na(detail$timestamp)) {
		  chat_to_load$timestamp <- detail$timestamp
		}
		chat_to_load$messages <- detail$messages
		chat_to_load$message_count <- detail$message_count
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
		  
		  insertUI(selector = "#chat_content_container", where = "beforeEnd", ui = ui_to_insert)
		  
		  if(isTRUE(msg$has_code)) {
			wrapper_id <- paste0("message_wrapper_", msg$id)
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
	  }
	  
	  showToast(session, "Önceki sohbetiniz geri yüklendi.", "info")
	}
  }, ignoreInit = TRUE)
}	
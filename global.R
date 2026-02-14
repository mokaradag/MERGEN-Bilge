# global.R

# Force UTF-8 encoding globally
options(encoding = "UTF-8")
options(future.rng.onMisuse = "ignore")
try(suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8")), silent = TRUE)

# Limit suppression to only this locale call
try(suppressWarnings(Sys.setlocale("LC_CTYPE", "Turkish_Turkey.UTF-8")), silent = TRUE)

# ------------------------------------------------------------------------------
# VERİTABANI HEDEF TANIMLARI (DATABASE TARGET CONSTANTS)
# ------------------------------------------------------------------------------
# Uygulama genelinde hangi veritabanına gidileceğini belirten standart etiketler.
# 'library_queries.R' içindeki sorgularda bu etiketleri kullanacağız.
DB_TARGETS <- list(
  PRIMARY   = "primary",   # Ana veritabanı (Varsayılan) -> .Renviron: DB_DSN
  SECONDARY = "secondary", # İkincil veritabanı          -> .Renviron: DB_DSN_2
  TERTIARY  = "tertiary"   # Üçüncül veritabanı          -> .Renviron: DB_DSN_3
)

# Yorumlu yanıtlara izin ver (LLM'in ikinci yazım geçişi açık kalsın)
options(mergen.ai.strict_data_only = FALSE)

# ==============================================================================
# MODÜLERLEŞTİRİLMİŞ YAPILANDIRMA DOSYALARI
# ==============================================================================
source("R/config_packages.R",    encoding = "UTF-8")  # Paket yüklemeleri
source("R/utils_common.R",       encoding = "UTF-8")  # Ortak yardımcı fonksiyonlar (%||%, safe_nzchar, vb.)
source("R/config_logging.R",     encoding = "UTF-8")  # Loglama altyapısı
source("R/utils_rate_limiter.R", encoding = "UTF-8")  # Hız sınırlama + işçi havuzu
source("R/utils_path_helpers.R", encoding = "UTF-8")  # Yol normalizasyon yardımcıları
source("R/utils_file_index.R",  encoding = "UTF-8")   # Önbellekli dosya indeks mekanizması
source("R/config_file_store.R",  encoding = "UTF-8")  # Dosya deposu altyapısı
source("R/utils_excel_reader.R", encoding = "UTF-8")  # Excel okuyucu yardımcıları

# --- SOURCE MODULES AND HELPERS ---
# Using standard relative paths is the most robust and conventional method for Shiny apps.
source("R/config_characters.R", encoding = "UTF-8")
source("welcome_screen.R",     encoding = "UTF-8")
source("R/helpers_database.R", encoding ="UTF-8")
source("R/helpers_language.R", encoding ="UTF-8")
source("R/helpers_messaging.R", encoding ="UTF-8")
source("R/helpers_mcp_tools.R", encoding ="UTF-8")
source("R/helpers_chartlab.R",    encoding = "UTF-8")
source("R/helpers_image_gallery.R", encoding = "UTF-8")
source("R/helpers_preview.R",     encoding = "UTF-8")
source("R/helpers_file_pipeline.R", encoding = "UTF-8")
source("R/helpers_files.R",     encoding = "UTF-8")
source("R/helpers_chat_runtime.R", encoding = "UTF-8")
source("R/helpers_summarization_modes.R", encoding = "UTF-8")
source("R/helpers_summarization_prompts.R", encoding = "UTF-8")
source("R/helpers_followup_questions.R", encoding = "UTF-8")
source("R/library_queries.R", encoding = "UTF-8")
source("R/config_sql_loader.R",  encoding = "UTF-8")
source("R/module_summarization.R", encoding = "UTF-8")
source("R/module_proje_kaynak_analizi.R", encoding = "UTF-8")
source("R/module_chat_history.R", encoding ="UTF-8")
source("R/module_file_manager.R", encoding ="UTF-8")
source("R/module_saved_chats.R", encoding ="UTF-8")
source("R/module_settings.R", encoding ="UTF-8")
source("R/module_character_video.R", encoding ="UTF-8")
source("R/module_performance.R", encoding ="UTF-8")
source("R/module_ai_processing.R", encoding ="UTF-8")
source("R/module_tts.R", encoding ="UTF-8")
source("R/module_stt.R", encoding = "UTF-8")
source("R/module_session_timeout.R", encoding = "UTF-8")
source("R/module_file_preview.R", encoding = "UTF-8")
source("R/module_api_key.R", encoding = "UTF-8")
source("R/module_message_search.R", encoding = "UTF-8")
source("R/module_followup_questions.R", encoding = "UTF-8")
source("R/module_chat_actions.R",  encoding = "UTF-8")
source("R/module_chat_export.R",   encoding = "UTF-8")
source("R/module_admin_analytics.R", encoding = "UTF-8")
source("R/module_feedback.R", encoding = "UTF-8")
source("R/module_quick_actions.R", encoding = "UTF-8")
source("R/module_image_generation.R", encoding = "UTF-8")
source("R/module_image_gallery.R", encoding = "UTF-8")
source("R/module_user_identity.R", encoding = "UTF-8")
source("R/server_session_cache.R", encoding = "UTF-8")
source("R/server_observers_settings.R", encoding = "UTF-8")
source("R/server_observers_storage.R", encoding = "UTF-8")
source("R/server_outputs_chat.R", encoding = "UTF-8")
source("R/server_observers_files.R", encoding = "UTF-8")
source("R/server_observers_saved_chats.R", encoding = "UTF-8")
source("R/server_observers_image_gallery.R", encoding = "UTF-8")
source("R/server_observers_chat_ui.R", encoding = "UTF-8")
source("R/server_observers_navigation.R", encoding = "UTF-8")
source("R/server_observers_file_clicks.R", encoding = "UTF-8")
source("R/server_observers_startup.R", encoding = "UTF-8")
source("R/server_observers_chat_input.R", encoding = "UTF-8")
source("R/server_observers_misc.R", encoding = "UTF-8")
source("R/server_outputs_downloads.R", encoding = "UTF-8")
source("R/server_tts_handlers.R", encoding = "UTF-8")
source("R/server_music_handlers.R", encoding = "UTF-8")
source("R/server_welcome_handlers.R", encoding = "UTF-8")
source("R/server_llm_response_handlers.R", encoding = "UTF-8")
source("R/server_send_message.R", encoding = "UTF-8")
source("R/config_api.R",         encoding = "UTF-8")

# Optional DOCX -> PDF conversion with LibreOffice (used only if options(mergen.word_preview_mode) == "pdf")
convert_docx_to_pdf <- function(docx_path) {
  if (!file.exists(docx_path)) stop("Path not found: ", docx_path)
  cmd <- Sys.which("soffice")
  if (!nzchar(cmd)) stop("LibreOffice ('soffice') not found in PATH. Install it or set options(mergen.word_preview_mode = 'html').")
  outdir <- dirname(docx_path)
  # Do the conversion
  res <- try(
    system2(cmd,
      args = c("--headless", "--norestore", "--convert-to", "pdf", "--outdir", shQuote(outdir), shQuote(docx_path)),
      stdout = TRUE, stderr = TRUE
    ),
    silent = TRUE
  )
  pdf_path <- sub("\\.docx$", ".pdf", docx_path, ignore.case = TRUE)
  if (!file.exists(pdf_path)) stop("PDF not produced. LibreOffice output: ", paste(res, collapse = "\n"))
  normalizePath(pdf_path, winslash = "/", mustWork = TRUE)
}

# --- Build a concise Turkish answer directly from raw tool results (TR + EN keys) ---
format_answer_from_tool_results <- function(tool_results_raw) {
  if (length(tool_results_raw) == 0) return(NULL)
  tr <- tool_results_raw[[1]]
  if (is.null(tr)) return(NULL)

  get2 <- function(x, k1, k2 = NULL) {
    if (!is.null(x[[k1]])) return(x[[k1]])
    if (!is.null(k2) && !is.null(x[[k2]])) return(x[[k2]])
    NULL
  }

  # sql_query_uploaded_file: result preview (single cell)
  df <- get2(tr, "sonuç_önizleme", "result_preview")
  if (is.data.frame(df) && nrow(df) >= 1 && ncol(df) >= 1) {
    cname <- colnames(df)[1]
    v <- df[1, 1]
    if (is.numeric(v)) {
      val <- as.numeric(v)
      lc <- tolower(cname)
      if (grepl("avg|mean|average", lc))       return(sprintf("Ortalama: %.2f", val))
      if (grepl("max", lc))                    return(sprintf("En yüksek değer: %.2f", val))
      if (grepl("min", lc))                    return(sprintf("En düşük değer: %.2f", val))
      if (grepl("count|distinct", lc))         return(sprintf("Sayı: %d", as.integer(round(val))))
      return(sprintf("%s: %s", cname, format(val, trim = TRUE, scientific = FALSE)))
    } else {
      return(sprintf("%s: %s", cname, as.character(v)))
    }
  }

  # get_column_statistics (numeric)
  typ <- get2(tr, "tür", "type")
  if (identical(typ, "numeric")) {
    col   <- get2(tr, "sütun", "column")
    meanv <- get2(tr, "ortalama", "mean")
    med   <- get2(tr, "medyan", "median")
    minv  <- get2(tr, "minimum", "min")
    maxv  <- get2(tr, "maksimum", "max")
    return(sprintf(
      "%s sütunu — Ortalama: %.2f, Medyan: %.2f, Min: %.2f, Max: %.2f",
      col %||% "Seçilen", meanv %||% NA_real_, med %||% NA_real_, minv %||% NA_real_, maxv %||% NA_real_
    ))
  }

  # analyze_uploaded_file
  rows <- get2(tr, "satır_sayısı", "row_count")
  cols <- get2(tr, "sütun_sayısı", "column_count")
  if (!is.null(rows) && !is.null(cols)) {
    return(sprintf("Dosyada %d satır ve %d sütun var.", rows, cols))
  }

  NULL
}

# --- FAST EXCEL PROFILE (used by server + MCP tools) ---
fast_profile <- function(df, top_levels = 12) {
  dt <- data.table::as.data.table(df)
  n  <- nrow(dt)

  types <- vapply(dt, function(x) class(x)[1], character(1))
  miss  <- vapply(dt, function(x) mean(is.na(x)), numeric(1))

  num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
  cat_cols <- names(dt)[vapply(dt, function(x) is.character(x) || is.factor(x), logical(1))]

  num_stats <- if (length(num_cols)) {
    data.table::rbindlist(lapply(num_cols, function(cn) {
      x <- dt[[cn]]
      data.table::data.table(
        column = cn,
        min    = suppressWarnings(min(x, na.rm = TRUE)),
        p25    = suppressWarnings(as.numeric(stats::quantile(x, 0.25, na.rm = TRUE))),
        median = suppressWarnings(stats::median(x, na.rm = TRUE)),
        mean   = suppressWarnings(mean(x, na.rm = TRUE)),
        p75    = suppressWarnings(as.numeric(stats::quantile(x, 0.75, na.rm = TRUE))),
        max    = suppressWarnings(max(x, na.rm = TRUE)),
        sd     = suppressWarnings(stats::sd(x,  na.rm = TRUE))
      )
    }), fill = TRUE, use.names = TRUE)
  } else data.table::data.table()

  cat_top <- if (length(cat_cols)) {
    data.table::rbindlist(lapply(cat_cols, function(cn) {
      tbl <- sort(table(dt[[cn]]), decreasing = TRUE)
      head_tbl <- head(tbl, top_levels)
      data.table::data.table(column = cn, level = names(head_tbl), n = as.integer(head_tbl))
    }), fill = TRUE, use.names = TRUE)
  } else data.table::data.table()

  list(
    shape     = list(rows = n, cols = ncol(dt)),
    col_types = as.list(types),
    missing   = as.list(miss),
    numeric   = num_stats,
    categories= cat_top
  )
}

build_excel_digest_json <- function(path, top_levels = 12) {
  df <- safe_read_excel_table(path)
  prof <- fast_profile(df, top_levels = top_levels)
  jsonlite::toJSON(prof, dataframe = "rows", na = "string", auto_unbox = TRUE)
}

# --- MCP Excel fallback helpers -------------------------------------------------
get_mcp_excel_candidates <- function(session_obj) {
  if (is.null(session_obj)) return(character())
  files <- session_obj$userData$current_session_files
  if (is.null(files) || !length(files)) return(character())
  display_names <- vapply(files, function(obj) {
    nm <- obj$name %||% obj$display %||% ""
    if (!is.character(nm) || length(nm) == 0) nm <- ""
    as.character(nm[1])
  }, character(1))
  display_names <- unique(display_names[nzchar(display_names)])
  if (!length(display_names)) {
    display_names <- unique(names(files))
    display_names <- display_names[nzchar(display_names)]
  }
  display_names
}

build_mcp_excel_summary <- function(analysis_result, display_name) {
  if (is.null(analysis_result) || !is.list(analysis_result)) return(NULL)
  satir <- analysis_result$satır_sayısı %||% analysis_result$row_count
  sutun <- analysis_result$sütun_sayısı %||% analysis_result$column_count
  cols  <- analysis_result$sütun_isimleri %||% analysis_result$columns
  nums  <- analysis_result$sayısal_sütunlar %||% analysis_result$numeric_columns

  lines <- c(
    sprintf("Dosya: %s", display_name %||% analysis_result$dosya_adı %||% "(bilinmiyor)"),
    sprintf("Toplam satır: %s", satir %||% "(bilinmiyor)"),
    sprintf("Toplam sütun: %s", sutun %||% "(bilinmiyor)")
  )

  if (length(cols)) {
    lines <- c(lines, sprintf("Sütunlar (%d): %s", length(cols), paste(cols, collapse = ", ")))
  }
  if (length(nums)) {
    lines <- c(lines, sprintf("Sayısal sütunlar: %s", paste(nums, collapse = ", ")))
  }

  paste(lines, collapse = "\n")
}

mcp_excel_tool_fallback <- function(session_obj) {
  if (!exists("helpers_mcp_tools", inherits = TRUE) ||
      !is.function(helpers_mcp_tools$analyze_uploaded_file)) {
    return(NULL)
  }
  candidates <- get_mcp_excel_candidates(session_obj)
  if (!length(candidates)) return(NULL)

  for (disp in candidates) {
    res <- try(helpers_mcp_tools$analyze_uploaded_file(disp, session_obj), silent = TRUE)
    if (!inherits(res, "try-error") && is.list(res) && is.null(res$error)) {
      text <- build_mcp_excel_summary(res, disp)
      if (!is.null(text)) {
        return(list(text = text, citation = disp))
      }
    }
  }
  NULL
}

# Allow the model to do multiple tool/LLM rounds when tools are enabled
MAX_MCP_RECURSION <- 4

# Shared LLM worker function with prompt-based MCP support
call_llm_worker <- function(chat_history, settings, api_endpoint, api_key = NULL, enable_tools = NULL, recursion_depth = 0) {
  worker_start_time <- Sys.time()      # <— add this line
  # Prevent infinite recursion

  if (recursion_depth > 5) {
    cat("[MCP] Max recursion depth reached\n")
    enable_tools <- FALSE
  }
  
  # Check if tools should be enabled
  if (is.null(enable_tools)) {
    enable_tools <- settings$enable_mcp_tools %||% FALSE
  }
  
	# mcp_excel seçiliyse araçları her durumda etkinleştir
    if (identical(settings$tool_family, "mcp_excel")) {
      enable_tools <- TRUE
    }
	
  cat("[LLM CALL] tool_family=", settings$tool_family %||% "NULL", " enable_tools=", enable_tools, "\n", sep="")
  
  tryCatch({
    selected_model <- settings$model_selection %||% "mergen-local-model"
    
    # NEW — resolve the OpenAI tool schema once per call
    session_obj <- settings$shiny_session %||% NULL
    registry_snapshot <- settings$mcp_registry_snapshot %||% NULL
    if (!is.null(registry_snapshot)) {
      needs_stub <- is.null(session_obj) ||
        is.null(session_obj$userData) ||
        is.null(session_obj$userData$current_session_files) ||
        length(session_obj$userData$current_session_files) == 0
      if (needs_stub && length(registry_snapshot) > 0) {
        session_stub <- session_obj
        if (is.null(session_stub) || !is.environment(session_stub)) {
          session_stub <- new.env(parent = emptyenv())
        }
        if (is.null(session_stub$userData) || !is.environment(session_stub$userData)) {
          session_stub$userData <- new.env(parent = emptyenv())
        }
        session_stub$userData$current_session_files <- registry_snapshot
        if (is.null(session_stub$userData$user_id) && !is.null(settings$current_user_id)) {
          session_stub$userData$user_id <- settings$current_user_id
        }
        session_obj <- session_stub
      }
    }
	
	tool_family <- settings$tool_family %||% if (isTRUE(settings$enable_mcp_tools)) "mcp_excel" else "none"

	base_tools <- list(tools = list())
	if (isTRUE(enable_tools) && identical(tool_family, "mcp_excel")) {
	  if (exists("helpers_mcp_tools", inherits = TRUE) &&
		  is.function(helpers_mcp_tools$get_openai_tools)) {
		base_tools <- helpers_mcp_tools$get_openai_tools(session_obj)
	  }
	}

	mcp_spec <- base_tools

	# Define the flag once and reuse it everywhere
	mcp_enabled_now <- isTRUE(enable_tools) &&
					   is.list(mcp_spec$tools) &&
					   length(mcp_spec$tools) > 0

	# --- DEFENSIVE PATCH: ensure parameters.required is always a JSON array ---
	if (mcp_enabled_now) {
	  mcp_spec$tools <- lapply(mcp_spec$tools, function(tdef) {
		if (!is.null(tdef$`function`) && !is.null(tdef$`function`$parameters)) {
		  req <- tdef$`function`$parameters$required
		  # Some servers incorrectly serialize this as a string; normalize to array
		  if (is.character(req) && length(req) == 1) {
			tdef$`function`$parameters$required <- list(req)
		  }
		}
		tdef
	  })
	}

    cat("\n========================================\n")
    cat("[LLM CALL] Model:", selected_model, "\n")
    cat("[LLM CALL] MCP Enabled:", if (mcp_enabled_now) "TRUE" else "FALSE", "\n")
    cat("[LLM CALL] Recursion depth:", recursion_depth, "\n")
    cat("========================================\n")
    
    messages_payload <- lapply(chat_history, function(msg) {
      role_val <- if (!is.null(msg$type)) {
        if (identical(msg$type, "user")) "user"
        else if (identical(msg$type, "system")) "system"
        else "assistant"
      } else if (!is.null(msg$role)) {
        tolower(as.character(msg$role))
      } else {
        "user"
      }
      
      content_val <- msg$content %||% msg$message %||% as.character(msg)
      list(role = role_val, content = content_val)
    })
	
	# --- Grafik niyeti algılayıcı + zorunlu yedek oluşturucu --------------------
	# Türkçe yorum: Son kullanıcı mesajında grafik isteği var mı?
	detect_chart_type_from_text <- function(text) {
	  if (!is.character(text) || length(text) == 0 || !nzchar(text[1])) return("auto")
	  txt <- tolower(text[1])
	  if (grepl("\\b(histogram|histogramı|histogramını|dağılım grafiği)\\b", txt, perl = TRUE)) return("hist")
	  if (grepl("\\b(çizgi|line|trend|zaman serisi|time series|eğilim)\\b", txt, perl = TRUE)) return("line")
	  if (grepl("\\b(bar|çubuk|sütun|column|karşılaştır)\\b", txt, perl = TRUE)) return("bar")
	  if (grepl("\\b(pie|pasta|dilim|pay)\\b", txt, perl = TRUE)) return("pie")
	  if (grepl("\\b(donut|halka)\\b", txt, perl = TRUE)) return("donut")
	  if (grepl("\\b(area|alan)\\b", txt, perl = TRUE)) return("area")
	  if (grepl("\\b(pareto)\\b", txt, perl = TRUE)) return("pareto")
	  if (grepl("\\b(scatter|saçılım|nokta|dağılım|serpilme)\\b", txt, perl = TRUE)) return("scatter")
	  "auto"
	}

	chart_intent_flag <- FALSE
		try({
		  last_user_txt <- NULL
	  if (length(chat_history) > 0) {
		for (i in seq_along(chat_history)) {
		  msg <- chat_history[[i]]
		  role_val <- tolower(as.character(msg$type %||% msg$role %||% ""))
		  if (identical(role_val, "user")) {
			last_user_txt <- as.character(msg$content %||% msg$message %||% "")  # son user içeriği
		  }
		}
	  }
	  if (is.character(last_user_txt) && length(last_user_txt) > 0 && nzchar(last_user_txt[1])) {
		chart_intent_flag <- grepl(
		  "(?i)\\b(grafik|grafikleri|grafiğini|görselleştir|gorsellestir|görselleştirme|gorsellestirme|plot|chart|chartlab|figure|graph|viz|visualize|visualise|çiz|çizelge|histogram|bar|çubuk|line|çizgi|trend|dağılım|scatter|pie|pasta|donut|pareto|area|spline|boxplot)\\b",
		  last_user_txt[1],
		  perl = TRUE
		)
	  }
	}, silent = TRUE)
	
	# Türkçe yorum: Grafiklerin toplanacağı depo (erken başlat)
	charts_to_store <- list()

	# Türkçe yorum: Fallback grafik mekanizması KALDIRILDI.
	# Model, talep edilen grafik sayısını tam olarak üretmelidir.
	# Otomatik ekleme mekanizması kaldırıldı çünkü:
	# 1) Kullanıcı 1 grafik istediğinde 3 grafik üretiliyordu
	# 2) Model yanlış eksen seçimi yapıyordu
	# 3) İstenmeyen histogram/bar/line kombinasyonları oluşuyordu
	add_fallback_chart <- function(original_text) {
	  # Türkçe yorum: Fallback devre dışı — orijinal metni olduğu gibi döndür
	  return(original_text %||% "")
	}
    
	# --- Seçilen aileye göre araç yönergesi enjekte et ---
	if (isTRUE(enable_tools)) {
	  tool_prompt <- NULL

		if (identical(tool_family, "mcp_excel") &&
			exists("helpers_mcp_tools", inherits = TRUE) &&
			is.function(helpers_mcp_tools$get_mcp_tools_prompt)) {

		  # Türkçe: Dosya şemasını çıkar ve prompt'a ekle
		  file_schema <- NULL
		  try({
			if (!is.null(session_obj) && !is.null(session_obj$userData$current_session_files)) {
			  # Session'daki ilk dosyanın şemasını al
			  files <- session_obj$userData$current_session_files
			  if (length(files) > 0) {
				first_file <- files[[1]]
				file_name <- first_file$name %||% names(files)[1]
				if (!is.null(file_name) && nzchar(file_name)) {
				  cat("[MCP_SCHEMA] Dosya şeması çıkarılıyor: ", file_name, "\n")
				  file_schema <- helpers_mcp_tools$extract_mcp_file_schema(file_name, session_obj)
				  if (!is.null(file_schema)) {
					cat("[MCP_SCHEMA] Şema başarıyla çıkarıldı (", nchar(file_schema), " karakter)\n")
				  }
				}
			  }
			}
		  }, silent = TRUE)

		  # Türkçe: Dosya şemasını prompt'a dahil et
		  tool_prompt <- paste0(
			helpers_mcp_tools$get_mcp_tools_prompt(file_schema),
			"\n\n### EK BİLGİ:",
			"\n- SQL sorguları için: sql_query_uploaded_file (tablo adı: t)",
			"\n- Dosya özeti için: analyze_uploaded_file (opsiyonel)",
			"\n"
		  )

		  # Türkçe: Tool prompt'u mesajların başına sistem mesajı olarak ekle
		  if (!is.null(tool_prompt) && nzchar(tool_prompt)) {
			cat("[MCP] Tool prompt ekleniyor (", nchar(tool_prompt), " karakter)\n", sep = "")
			tool_system_msg <- list(role = "system", content = tool_prompt)
			messages_payload <- c(list(tool_system_msg), messages_payload)
		  }
		}
	}

    temp_value <- if (!is.null(settings$temperature)) settings$temperature else 0.4

    body <- list(
      model = selected_model, 
      messages = messages_payload, 
      stream = FALSE,
      temperature = temp_value
    )

	  # YENİ — Tüm uçlar OpenAI uyumlu: araç şemasını her zaman ekle
	  if (mcp_enabled_now) {
		# Türkçe: İstisnai olarak devre dışı bırakmak isterseniz DISABLE_TOOL_SCHEMA=TRUE ayarlayın
		attach_tool_schema <- !isTRUE(as.logical(Sys.getenv("DISABLE_TOOL_SCHEMA", "FALSE")))

		cat("[TOOLS] attach_tool_schema=", attach_tool_schema, " (family=", tool_family, ")\n", sep = "")

		if (attach_tool_schema) {
		  body$tools <- mcp_spec$tools
		  body$tool_choice <- "auto"
		}
	  }
    
    hdrs <- list(`Content-Type` = "application/json")
    if (!is.null(api_key) && nzchar(api_key)) {
      hdrs$Authorization <- paste("Bearer", api_key)
    }
    
	response <- httr::POST(
	  api_endpoint,
	  do.call(httr::add_headers, hdrs),
	  body = jsonlite::toJSON(body, auto_unbox = TRUE),
      encode = "raw",
      timeout(300)
    )

	status <- httr::status_code(response)

	if (status != 200) {
	  resp_txt_raw <- try(httr::content(response, "text", encoding = "UTF-8"), silent = TRUE)
	  resp_txt <- if (!inherits(resp_txt_raw, "try-error") && is.character(resp_txt_raw) && length(resp_txt_raw) > 0) resp_txt_raw[[1]] else ""

	  # Türkçe: Ollama 'tools' desteklemiyorsa 400 döner — tool şeması olmadan otomatik tekrar dene
	  if (status == 400 && mcp_enabled_now && isTRUE(attach_tool_schema) &&
		  grepl("does not support tools|tool", tolower(resp_txt))) {
		cat("[RETRY] 400 & tools not supported → retrying without tool schema...\n")
		body$tools <- NULL
		body$tool_choice <- NULL
		response <- httr::POST(
		  api_endpoint,
		  do.call(httr::add_headers, hdrs),
		  body = jsonlite::toJSON(body, auto_unbox = TRUE),
		  encode = "raw",
		  timeout(300)
		)
		status <- httr::status_code(response)
		resp_txt_raw <- try(httr::content(response, "text", encoding = "UTF-8"), silent = TRUE)
		resp_txt <- if (!inherits(resp_txt_raw, "try-error") && is.character(resp_txt_raw) && length(resp_txt_raw) > 0) resp_txt_raw[[1]] else ""
	  }

	  if (status != 200) {
		msg_tail <- if (nzchar(resp_txt)) paste0(" — ", substr(resp_txt, 1, 500)) else ""
		if (status == 429)      stop("RATE_LIMIT: Çok fazla istek gönderildi.", call. = FALSE)
		else if (status %in% c(401,403)) stop("AUTH_ERROR: Kimlik doğrulama hatası.", call. = FALSE)
		else if (status >= 500) stop(sprintf("SERVER_ERROR: Sunucu hatası (Kod: %d)%s", status, msg_tail), call. = FALSE)
		else                    stop(sprintf("API_ERROR: API hatası (Kod: %d)%s", status, msg_tail), call. = FALSE)
	  }
	}
    
	# Türkçe: text/event-stream dahil tüm yanıt formatlarını güvenli ayrıştır
    response_content <- safe_parse_llm_response(response)
    
    ai_content <- NULL
    tool_calls_struct <- NULL
    
    if (is.list(response_content) &&
        !is.null(response_content$choices) &&
        length(response_content$choices) > 0) {
      first_choice <- response_content$choices[[1]]
      if (is.list(first_choice) && !is.null(first_choice$message)) {
        ai_content <- first_choice$message$content %||% ""
        # NEW: capture structured tool calls from the API
        if (!is.null(first_choice$message$tool_calls) && length(first_choice$message$tool_calls) > 0) {
          tool_calls_struct <- first_choice$message$tool_calls
        }
      }
    }
    
	# Only error if neither content nor structured tool calls exist (length-safe)
	has_content <- is.character(ai_content) && length(ai_content) > 0 && nzchar(ai_content[1])
	if (!has_content && (is.null(tool_calls_struct) || length(tool_calls_struct) == 0)) {
	  stop("EMPTY_RESPONSE: AI'dan geçerli bir yanıt alınamadı.")
	}

	# Türkçe: Model tool_calls döndürdü ama MCP kapalıysa, araç kullanmadan tekrar iste.
	# Bu durum RAG modellerin arama sorgusu döndürmesinde oluşur (ör. query_knowledge_files).
	if (!has_content && !is.null(tool_calls_struct) && length(tool_calls_struct) > 0 && !mcp_enabled_now) {
	  tc_names <- paste(sapply(tool_calls_struct, function(tc) tc$`function`$name %||% "?"), collapse = ", ")
	  cat("[RETRY] Model tool_calls döndürdü (", tc_names, ") ama MCP kapalı — tool_choice='none' ile tekrar deneniyor\n")

	  # Türkçe: Mesaj listesinin sonuna araç kullanmama talimatı ekle.
	  # Qwen/RAG modelleri tool_choice='none' olsa bile metin olarak araç çağrısı yazabiliyor.
	  retry_messages <- c(messages_payload, list(
	    list(role = "system", content = paste0(
	      "ÖNEMLİ: Herhangi bir araç veya fonksiyon çağrısı KULLANMA. ",
	      "<function=...>, <tool_call>, query_knowledge_files gibi hiçbir araç söz dizimi yazma. ",
	      "Soruyu doğrudan, kendi bilginle ve düz metin olarak yanıtla."
	    ))
	  ))

	  retry_body <- list(
	    model = selected_model,
	    messages = retry_messages,
	    stream = FALSE,
	    temperature = temp_value,
	    tool_choice = "none"
	  )
	  
	  retry_response <- tryCatch({
	    httr::POST(
	      api_endpoint,
	      do.call(httr::add_headers, hdrs),
	      body = jsonlite::toJSON(retry_body, auto_unbox = TRUE),
	      encode = "raw",
	      httr::timeout(300)
	    )
	  }, error = function(e) {
	    cat("[RETRY] Tekrar istek hatası:", e$message, "\n")
	    NULL
	  })
	  
	  if (!is.null(retry_response) && httr::status_code(retry_response) == 200) {
	    retry_content <- safe_parse_llm_response(retry_response)
	    
	    if (is.list(retry_content) && !is.null(retry_content$choices) && length(retry_content$choices) > 0) {
	      retry_msg <- retry_content$choices[[1]]$message
	      retry_text <- retry_msg$content %||% ""
	      if (is.character(retry_text) && nzchar(retry_text)) {
	        # Türkçe: Yanıttaki metin-tabanlı araç çağrılarını temizle
	        retry_text <- strip_planner_text(retry_text)
	        cat("[RETRY] Temizlenmiş içerik: content_nchar=", nchar(retry_text), "\n")

	        # Türkçe: Temizleme sonrası anlamlı içerik kaldı mı kontrol et
	        if (nzchar(retry_text) && nchar(retry_text) >= 10) {
	          ai_content <- retry_text
	          tool_calls_struct <- NULL
	          has_content <- TRUE
	          cat("[RETRY] Başarılı: content_nchar=", nchar(ai_content), "\n")
	          # Türkçe: Retry yanıtından kaynakları da al
	          if (!is.null(retry_msg$sources)) {
	            sources_list <- retry_msg$sources
	          } else if (!is.null(retry_content$sources)) {
	            sources_list <- retry_content$sources
	          }
	        } else {
	          cat("[RETRY] Temizleme sonrası anlamlı içerik kalmadı (nchar=", nchar(retry_text), ")\n")
	        }
	      }
	    }
	    
	    # Türkçe: Retry de başarısızsa hata ver
	    if (!has_content) {
	      cat("[RETRY] tool_choice='none' ile de içerik alınamadı\n")
	      stop("EMPTY_RESPONSE: Model araç çağrısı döndürdü ancak doğrudan yanıt alınamadı.")
	    }
	  } else {
	    status_code <- if (!is.null(retry_response)) httr::status_code(retry_response) else "NULL"
	    cat("[RETRY] Tekrar istek başarısız, HTTP:", status_code, "\n")
	    stop("EMPTY_RESPONSE: Model araç çağrısı döndürdü, tekrar istek başarısız.")
	  }
	}
    
	cat("[RESPONSE] Content length:", if (has_content) nchar(ai_content[1]) else 0, "chars\n")
	cat("[RESPONSE] Preview:", if (has_content) substr(ai_content[1], 1, 200) else "", "...\n")
		
    # Parse for tool calls if MCP enabled
    if (enable_tools) {
      tool_calls <- list()
    
	  if (!is.null(tool_calls_struct) && length(tool_calls_struct) > 0) {
        cat("[MCP] Structured tool_calls detected from API:", length(tool_calls_struct), "\n")
        tool_calls <- lapply(tool_calls_struct, function(tc) {
          fn <- try(tc$`function`$name, silent = TRUE)
          arg_raw <- try(tc$`function`$arguments, silent = TRUE)
          args <- list()
          if (!inherits(arg_raw, "try-error") && is.character(arg_raw) && nzchar(arg_raw)) {
            args <- tryCatch(jsonlite::fromJSON(arg_raw, simplifyVector = FALSE), error = function(e) list())
          } else if (is.list(arg_raw)) {
            args <- arg_raw
          }
          list(function_name = fn %||% "", arguments = args %||% list())
        })
      } else if (identical(tool_family, "mcp_excel") &&
                 exists("helpers_mcp_tools", inherits = TRUE) &&
                 is.function(helpers_mcp_tools$parse_tool_calls_from_text)) {
        tool_calls <- helpers_mcp_tools$parse_tool_calls_from_text(ai_content %||% "")
      }
	  
      if (length(tool_calls) == 0 && identical(tool_family, "mcp_excel") && recursion_depth == 0) {
        fb <- try(mcp_excel_tool_fallback(session_obj), silent = TRUE)
        if (!inherits(fb, "try-error") && is.list(fb) && !is.null(fb$text)) {
          text_out <- fb$text
          cite <- fb$citation %||% ""
          if (nzchar(cite)) {
            text_out <- paste0(text_out, "\n\nKaynakça:\n1) ", cite)
          }
          return(list(
            content = text_out,
            duration = as.numeric(difftime(Sys.time(), worker_start_time, units = "secs")),
            chart_store = charts_to_store
          ))
        }
      }
    
      if (length(tool_calls) > 0) {
        cat("\n========================================\n")
        cat("[MCP SUCCESS] Parsed", length(tool_calls), "tool call(s)\n")
        cat("========================================\n")
    
        # Get session for resolvers
        current_session <- if (!is.null(settings$shiny_session)) settings$shiny_session else NULL
    
		cat("[MCP] Executing tools...\n")

		exec_fun <- NULL

		if (identical(tool_family, "mcp_excel") &&
			exists("helpers_mcp_tools", inherits = TRUE) &&
			is.function(helpers_mcp_tools$execute_parsed_tool)) {

		  exec_fun <- function(tc) {
			cat("[MCP] Executing (Excel):", tc$function_name, "\n")
			helpers_mcp_tools$execute_parsed_tool(tc, session = current_session)
		  }

		} else {
		  exec_fun <- function(tc) {
			list(error = "Uygun araç yürütücüsü bulunamadı (MCP seçimi kontrol edin).")
		  }
		}

		cat("[MCP] tool_calls parsed (names):", paste(vapply(tool_calls, function(t) t$function_name %||% "", ""), collapse = ", "), "\n")
		tool_results_raw <- lapply(tool_calls, exec_fun)
		
		# --- NEW: collect any chart specs to be injected back into the chat (as fenced blocks) ---
		# IMPORTANT: we're in a worker. Do NOT touch the Shiny session here.
		chart_blocks_text <- ""
		try({
				# __mcp_plot şartını kaldır — chart alanı olan tüm sonuçlar geçerlidir
				chart_specs <- Filter(function(x) is.list(x) && !is.null(x[["chart"]]), tool_results_raw)
		  if (length(chart_specs)) {

			parts <- vapply(seq_along(chart_specs), function(i) {
			  cs <- chart_specs[[i]]
			  full <- cs$chart

				# unique ref id
				ref_id <- paste0(
				  "cl_", format(Sys.time(), "%Y%m%d%H%M%OS3"), "_", sprintf("%04d", sample(0:9999, 1))
				)

				# store full spec in the chart store (for backwards-compat / reuse)
				charts_to_store[[ref_id]] <<- full

				# IMPORTANT: KEEP data inline to avoid any race with chart_store resolution
				inline <- full
				inline$ref <- ref_id  # we still add ref, but we do NOT drop data anymore

				jsonlite::toJSON(inline, auto_unbox = TRUE, null = "null", digits = 12)
			}, character(1))

			chart_blocks_text <- paste0(
			  paste0("\n\n```chartlab\n", parts, "\n```"),
			  collapse = ""
			)
		  }
		}, silent = TRUE)

		build_chart_summary <- function(raw_chart) {
		  chart <- raw_chart$chart %||% raw_chart
		  if (is.null(chart) || !is.list(chart)) {
			return("Grafik hazırlandı; veri kısa süreli özetlendi.")
		  }

		  desc_parts <- c()
		  chart_type <- chart$type %||% chart$chart_type %||% ""
		  if (nzchar(chart_type)) desc_parts <- c(desc_parts, paste0("Tür: ", chart_type))

		  mapping <- chart$mapping %||% list()
		  axes <- c()
		  if (nzchar(mapping$x %||% "")) axes <- c(axes, paste0("X=", mapping$x))
		  if (nzchar(mapping$y %||% "")) axes <- c(axes, paste0("Y=", mapping$y))
		  if (nzchar(mapping$group %||% "")) axes <- c(axes, paste0("Gruplama=", mapping$group))
		  if (length(axes)) desc_parts <- c(desc_parts, paste(axes, collapse = ", "))

		  df <- chart$data
		  row_hint <- chart$n %||% if (is.data.frame(df)) nrow(df) else NULL
		  if (is.finite(row_hint)) desc_parts <- c(desc_parts, paste0("Örnek satır sayısı: ", row_hint))

		  summary_line <- if (length(desc_parts)) paste(desc_parts, collapse = " | ") else "Dosyadaki verilerden üretildi"

		  # Hızlı içgörü: sayısal eksen varsa dağılımı özetle
		  quick_observation <- NULL
		  if (is.data.frame(df)) {
			num_candidate <- NULL
			if (nzchar(mapping$y %||% "") && is.numeric(df[[mapping$y]])) num_candidate <- df[[mapping$y]]
			if (is.null(num_candidate) && nzchar(mapping$x %||% "") && is.numeric(df[[mapping$x]])) num_candidate <- df[[mapping$x]]

			if (!is.null(num_candidate)) {
			  num_candidate <- suppressWarnings(as.numeric(num_candidate))
			  num_candidate <- num_candidate[is.finite(num_candidate)]
			  if (length(num_candidate)) {
                        med_val <- stats::median(num_candidate)
                        q1 <- stats::quantile(num_candidate, 0.25, na.rm = TRUE)
                        q3 <- stats::quantile(num_candidate, 0.75, na.rm = TRUE)
                        mn <- min(num_candidate)
                        mx <- max(num_candidate)
                        iqr_span <- q3 - q1
                        tail_hint <- if (med_val > mean(c(q1, q3))) "üst" else "alt"
                        quick_observation <- paste(
                          sprintf("Ortanca %.2f (Q1=%.2f, Q3=%.2f), min %.2f, max %.2f.", med_val, q1, q3, mn, mx),
                          sprintf("Değerler %s kuyrukta yoğunlaşıyor; dışa taşan uçlar için kutu yaylarını inceleyebilirsin.", tail_hint),
                          sprintf("IQR %.2f olduğundan veri yayılımı %s; bu aralık grafik üzerinde renk/yoğunluk olarak hissedilir.", iqr_span, if (iqr_span > 0) "belirgin" else "düşük")
				)
			  }
			} else if (nzchar(mapping$x %||% "") && !is.numeric(df[[mapping$x]])) {
			  top_levels <- sort(table(df[[mapping$x]]), decreasing = TRUE)
			  top_levels <- head(top_levels, 3)
			  top_share <- round(as.numeric(top_levels) / sum(top_levels) * 100, 1)
			  quick_observation <- paste0(
				"En sık kategoriler: ",
				paste(sprintf("%s (%d, %s%%)", names(top_levels), as.integer(top_levels), format(top_share, nsmall = 1)), collapse = ", "),
				". Yoğunluğun bu gruplarda toplandığını vurgula; kalan uzun kuyruğu da kısaca hatırlat."
			  )
			}
		  }

		  base_line <- paste0("Grafik hazırlandı: ", summary_line, ".")
		  if (nzchar(quick_observation)) {
			paste(base_line, quick_observation, "Eksenlerdeki deseni iki cümleyle anlat ve kullanıcının aklında net bir tablo oluşmasını sağla.")
		  } else {
			paste(base_line, "Veri dağılımını ve olası uç değerleri kısaca betimleyip okuyucuya yol gösterici bir paragraf ekle.")
		  }
		}

		build_auto_insight <- function(raw_results) {
		  # 1) Grafik varsa öne al
		  chart_pick <- Filter(function(x) is.list(x) && (!is.null(x[["chart"]]) || isTRUE(x[["__mcp_plot"]])), raw_results)
		  if (length(chart_pick)) {
			return(build_chart_summary(chart_pick[[1]]))
		  }

		  # 2) DataFrame önizlemesi varsa kısa özet çıkar
		  for (rr in raw_results) {
			df <- rr$`sonuç_önizleme` %||% rr$preview
			if (is.data.frame(df) && nrow(df) > 0) {
			  num_cols <- names(df)[vapply(df, is.numeric, logical(1))]
			  if (length(num_cols)) {
				vals <- suppressWarnings(as.numeric(df[[num_cols[1]]]))
				vals <- vals[is.finite(vals)]
				if (length(vals)) {
				  avg  <- mean(vals)
				  med  <- stats::median(vals)
				  mn   <- min(vals)
				  mx   <- max(vals)
				  sdv  <- stats::sd(vals)
				  return(sprintf(
					paste(
					  "İçgörü: %d satırın %s sütunu min %.2f, medyan %.2f, ortalama %.2f, max %.2f.",
					  "Standart sapma %.2f; dağılımın genişliği ve olası uç noktalar üzerine birkaç cümle kur.",
					  "Kısa, öğretici bir paragrafla kullanıcının görebileceği trendleri ve aksiyon önerilerini anlat."
					),
					nrow(df), num_cols[1], mn, med, avg, mx, sdv
				  ))
				}
			  }

			  head_cols <- paste(head(colnames(df), 3), collapse = ", ")
			  return(sprintf(
				paste(
				  "İçgörü: İlk %d satırda öne çıkan sütunlar %s; satır örneklerini kullanarak eğilimleri anlat.",
				  "Okuyucuya rehberlik edecek 4-5 cümlelik bir paragraf yaz; hangi kolonların dikkat çektiğini ve neden önemli olabileceğini açıkla."
				),
				nrow(df), head_cols
			  ))
			}
		  }

		  "İçgörü: Sonuçlar yukarıda; dağılımı, beklenmedik değerleri ve olası aksiyonları birkaç cümleyle rehber gibi açıkla."
		}
            
        # If any tool returned error, aggregate and short-circuit
        errs <- vapply(tool_results_raw, function(r) if (is.list(r) && !is.null(r$error)) r$error else "", "")
        if (any(nzchar(errs))) {
          err_text <- paste(errs[nzchar(errs)], collapse = "\n")
			return(list(
			  content  = paste("Araç hatası:\n", err_text),
			  duration = as.numeric(difftime(Sys.time(), worker_start_time, units = "secs")),
			  chart_store = charts_to_store
			))
        }
		
		# Türkçe: Ham araç sonuçlarını detaylı logla
        cat("\n========== [GLOBAL] HAM ARAÇ SONUÇLARI ==========\n")
        for (i in seq_along(tool_results_raw)) {
          raw <- tool_results_raw[[i]]
          cat("\n[GLOBAL] Araç #", i, "\n")
          cat("[GLOBAL] Class:", class(raw), "\n")
          cat("[GLOBAL] Names:", paste(names(raw), collapse=", "), "\n")
          
          if (is.list(raw)) {
            if (!is.null(raw$error)) {
              cat("[GLOBAL] *** HATA VAR ***: ", raw$error, "\n")
            }
            
            df <- raw$`sonuç_önizleme` %||% raw$preview
            if (is.data.frame(df)) {
              cat("[GLOBAL] DataFrame bulundu - Satır:", nrow(df), " Sütun:", ncol(df), "\n")
              if (nrow(df) > 0) {
                cat("[GLOBAL] İlk satır:\n")
                print(df[1, , drop=FALSE])
              }
            } else {
              cat("[GLOBAL] DataFrame YOK veya geçersiz!\n")
            }
          }
        }
        cat("========== [GLOBAL] HAM SONUÇLAR BİTİŞ ==========\n\n")
        
# Türkçe: Araç sonuçlarını LLM için okunabilir formata çevir
        cat("\n╔════════════════════════════════════════════════════╗\n")
        cat("║  [GLOBAL] ARAÇ SONUÇLARINI FORMATLAMAYA BAŞLIYOR  ║\n")
        cat("╚════════════════════════════════════════════════════╝\n\n")
        
        tool_results <- lapply(seq_along(tool_calls), function(i) {
          raw <- tool_results_raw[[i]]
          tool_name <- tool_calls[[i]]$function_name
          
          cat("\n========== [GLOBAL] Araç #", i, " Formatlanıyor ==========\n")
          cat("[GLOBAL] Araç adı:", tool_name, "\n")
          cat("[GLOBAL] raw değişkeni class:", class(raw), "\n")
          cat("[GLOBAL] raw değişkeni names:", paste(names(raw), collapse=", "), "\n")
          
          # Türkçe: sonuç_önizleme veya preview'i bul
          df <- NULL
          if (!is.null(raw$`sonuç_önizleme`)) {
            cat("[GLOBAL] sonuç_önizleme bulundu\n")
            df <- raw$`sonuç_önizleme`
          } else if (!is.null(raw$preview)) {
            cat("[GLOBAL] preview bulundu\n")
            df <- raw$preview
          } else {
            cat("[GLOBAL] *** UYARI: Ne sonuç_önizleme ne de preview bulundu! ***\n")
          }
          
          cat("[GLOBAL] df class:", class(df), "\n")
          cat("[GLOBAL] df is.data.frame:", is.data.frame(df), "\n") 

          if (is.list(raw) && (!is.null(raw$chart) || isTRUE(raw$`__mcp_plot`))) {
            cat("[GLOBAL] Grafik sonucu algılandı; JSON yerine özet kullanılacak.\n")
            result_text <- build_chart_summary(raw)

          } else if (is.data.frame(df)) {
            cat("[GLOBAL] DataFrame boyutu: ", nrow(df), " satır x ", ncol(df), " sütun\n")
            cat("[GLOBAL] Sütun isimleri:", paste(colnames(df), collapse=", "), "\n")
            
            if (nrow(df) > 0) {
              # Ensure UTF-8 headers/cells so Turkish characters render correctly
              df <- as.data.frame(df, stringsAsFactors = FALSE)
              df[] <- lapply(df, function(col) tryCatch(enc2utf8(as.character(col)), error = function(e) col))
              colnames(df) <- tryCatch(enc2utf8(colnames(df)), error = function(e) colnames(df))
			  
              cat("[GLOBAL] ✓ VERİ VAR - İLK SATIR:\n")
              print(df[1, , drop=FALSE])
              
              # Türkçe: DataFrame'i markdown tablo olarak formatla
              header <- paste0("| ", paste(colnames(df), collapse = " | "), " |")
              separator <- paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|")
              rows <- apply(df, 1, function(row) {
                paste0("| ", paste(row, collapse = " | "), " |")
              })
              table_md <- paste(c(header, separator, rows), collapse = "\n")
              
			  source_table_values <- raw$source_table_values
              if ((is.null(source_table_values) || !length(source_table_values)) && "source_table" %in% names(df)) {
                st_vals <- unique(df$source_table)
                st_vals <- st_vals[!is.na(st_vals)]
                source_table_values <- sort(as.character(st_vals))
              }
              source_table_line <- if (!is.null(source_table_values) && length(source_table_values)) {
                paste0("source_table değerleri: ", paste(source_table_values, collapse = ", "))
              } else {
                "UYARI: Bu sonuç source_table sütununu içermiyor. Lütfen sorgunuza ekleyin."
              }

              dropped_cols <- raw$dropped_all_na_columns
              dropped_line <- if (!is.null(dropped_cols) && length(dropped_cols)) {
                paste0("Tamamen NA olduğu için gizlenen sütunlar: ", paste(dropped_cols, collapse = ", "))
              } else {
                ""
              }
			  
              result_text <- paste0(
                "╔════════════════════════════════════════╗\n",
                "║  VERİTABANINDAN GELEN GERÇEK VERİ      ║\n",
                "╚════════════════════════════════════════╝\n\n",
                "SQL Sorgusu: ", raw$sql_effective %||% "N/A", "\n",
                "Dönen Toplam Satır: ", nrow(df), "\n",
                "Dönen Toplam Sütun: ", ncol(df), "\n",
                source_table_line, "\n",
                if (nzchar(dropped_line)) paste0(dropped_line, "\n") else "",
                "\n",
                "⬇️ AŞAĞIDA ", nrow(df), " SATIR GERÇEK VERİ VAR ⬇️\n",
                "BU SAYILARI AYNEN KULLAN - UYDURMA!\n\n",
                table_md, "\n\n",
                "⬆️ YUKARDA ", nrow(df), " SATIR GERÇEK VERİ VAR ⬆️\n",
                "BU TABLODAKİ SAYILARI BİREBİR KOPYALA!"
              )
              
              cat("\n[GLOBAL] ✓ Markdown tablo oluşturuldu\n")
              cat("[GLOBAL] Tablo uzunluğu:", nchar(table_md), "karakter\n")
              cat("[GLOBAL] Tablo ilk 500 karakteri:\n")
              cat(substr(table_md, 1, 500), "\n...\n")
              
            } else {
              cat("[GLOBAL] *** UYARI: DataFrame BOŞ (0 satır) ***\n")
              result_text <- "UYARI: Sorgu sonucu boş döndü."
            }
          } else if (is.list(raw) && !is.null(raw$result) && is.character(raw$result)) {
            cat("[GLOBAL] ✓ Liste içindeki result metni kullanılacak\n")
            result_text <- paste(raw$result, collapse = "\n\n")
          } else if (is.character(raw) && length(raw)) {
            cat("[GLOBAL] ✓ Ham karakter vektörü kullanılacak\n")
            result_text <- paste(raw, collapse = "\n\n")
          } else {
            cat("[GLOBAL] *** UYARI: df DataFrame değil! JSON formatında dönecek ***\n")
            result_text <- jsonlite::toJSON(raw, auto_unbox = TRUE, pretty = TRUE)
          }
          
          cat("[GLOBAL] result_text uzunluğu:", nchar(result_text), "karakter\n")
          cat("[GLOBAL] result_text ilk 300 karakteri:\n")
          cat(substr(result_text, 1, 300), "\n...\n")
          cat("========================================\n\n")
          
          list(tool = tool_name, result = result_text)
        })
        
        cat("\n╔════════════════════════════════════════════════════╗\n")
        cat("║  [GLOBAL] TÜM ARAÇLAR FORMATLANDI                  ║\n")
        cat("╚════════════════════════════════════════════════════╝\n\n")
        
		# Türkçe: Araç sonuçlarını log'a yaz
        for (i in seq_along(tool_results)) {
          tr <- tool_results[[i]]
          cat("\n========== ARAÇ SONUCU ", i, " ==========\n")
          cat("Araç Adı: ", tr$tool, "\n")
          cat("Sonuç Uzunluğu: ", nchar(tr$result), " karakter\n")
          cat("İlk 1000 karakter:\n", substr(tr$result, 1, 1000), "\n")
          cat("========================================\n\n")
        }
        
        # Türkçe: LLM için sonuç mesajı oluştur
        results_text <- paste(
          vapply(tool_results, function(tr) trimws(tr$result), character(1)),
          collapse = "\n\n"
        )
		
        # Yalnızca GERÇEK VERİ tablosunu döndür, ikinci LLM geçişini atla
        if (isTRUE(getOption("mergen.ai.strict_data_only", FALSE))) {
		  insight_txt <- build_auto_insight(tool_results_raw)
		  final_txt <- results_text
		  # Araçlar grafik ürettiyse ekle
		  if (exists("chart_blocks_text") && is.character(chart_blocks_text) && nzchar(chart_blocks_text)) {
				final_txt <- paste0(final_txt, "\n\n", chart_blocks_text)
		  }
		  if (nzchar(insight_txt)) {
				final_txt <- paste(final_txt, insight_txt, sep = "\n\n")
		  }
		  return(list(
				content     = final_txt,
				duration    = as.numeric(difftime(Sys.time(), worker_start_time, units = "secs")),
			chart_store = charts_to_store
		  ))
		}
        
        # Türkçe: Tam sonuç metnini log'a yaz (LLM'e ne gönderildiğini görmek için)
        cat("\n========== LLM'E GÖNDERİLEN TAM SONUÇ METNİ ==========\n")
        cat(results_text, "\n")
        cat("========================================\n\n")
		
		# Türkçe: Chat history'nin son elemanını (AI'a gönderilecek mesajı) detaylı logla
        cat("\n╔═══════════════════════════════════════════════════════════╗\n")
        cat("║  [GLOBAL] AI'A GÖNDERİLECEK MESAJIN SON HALİ              ║\n")
        cat("╚═══════════════════════════════════════════════════════════╝\n\n")
        
        last_msg <- chat_history[[length(chat_history)]]
        cat("[GLOBAL] Son mesaj role:", last_msg$role, "\n")
        cat("[GLOBAL] Son mesaj uzunluğu:", nchar(last_msg$content), "karakter\n")
        cat("\n[GLOBAL] SON MESAJIN TAM İÇERİĞİ:\n")
        cat("════════════════════════════════════════════════════════════\n")
        cat(last_msg$content)
        cat("\n════════════════════════════════════════════════════════════\n\n")
        
        # Türkçe: Markdown tablo var mı kontrol et
        if (grepl("\\|.*\\|.*\\|", last_msg$content)) {
          cat("[GLOBAL] ✓ Mesajda markdown tablo BULUNDU\n")
          # Türkçe: Kaç satır tablo var?
          table_lines <- length(gregexpr("\n", last_msg$content)[[1]])
          cat("[GLOBAL] Tabloda yaklaşık", table_lines, "satır var\n")
        } else {
          cat("[GLOBAL] *** UYARI: Mesajda markdown tablo BULUNAMADI! ***\n")
        }
        
        # Add to history - IMPORTANT: Don't include raw tool call text
        chat_history <- append(chat_history, list(
          list(role = "assistant", content = "[Araçlar kullanıldı]")
        ))
		chat_history <- append(chat_history, list(
          list(role = "user", content = paste0(
            "Araç sonuçları:\n\n",
            results_text,
            "\n\n╔═══════════════════════════════════════════════════════╗\n",
            "║  MUTLAK KURAL - ASLA İHLAL ETME                      ║\n",
            "╚═══════════════════════════════════════════════════════╝\n\n",
            "Yukarıdaki tablo GERÇEK VERİDİR. Bu veritabanından geldi.\n\n",
            "SEN BİR VERİ RAPORLAYICI ROBOTSUN - VERİ ÜRETME!\n\n",
            "YAPMAN GEREKENLER:\n",
            "✓ Yukarıdaki tabloda gördüğün TAM sayıları kopyala\n",
            "✓ Hiçbir değeri yuvarlaMA, değiştirME\n",
            "✓ Tablodaki her satırı kullan\n",
            "✓ ProjeAdi ve sayıları BİREBİR kopyala\n\n",
            "✓ Yanıtı TEK SEFERDE tamamla; ek deneme veya ikinci tur bekleme.\n",
            "✓ Sonuçları yorumla: trend, uç değer ve dağılımı en az 4-5 cümlelik öğretici bir paragrafla açıkla; kullanıcının hangi desene odaklanması gerektiğini belirt.\n",
            "✓ Grafik varsa, eksenler ve göze çarpan deseni 1-2 cümlede özetle.\n\n",
            "ASLA YAPMA:\n",
            "✗ 'Örnek Çıktı' yazma\n",
            "✗ Sahte sayılar üretme\n",
            "✗ Tahmin etme\n",
            "✗ Benzer değerler uydurma\n",
            "✗ '...' kullanma\n\n",
            "Eğer yukarıdaki tabloda veri YOKSA:\n",
            "→ 'Sonuç bulunamadı' de ve DUR\n\n",
            "Eğer yukarıdaki tabloda veri VARSA:\n",
            "→ O sayıları AYNEN yaz\n\n",
            "ŞİMDİ: Yukarıdaki GERÇEK tabloyu kullanarak kullanıcının sorusunu cevapla."
          ))
        ))
        
        cat("\n========================================\n")
        cat("[MCP] Calling LLM again with tool results\n")
        cat("========================================\n")
		
		# Türkçe: Sistem mesajını ÖNCELİKLE ekle - AI'ın rolünü tanımla
        system_msg_anti_hallucination <- list(
          role = "system",
          content = paste0(
            "SEN BİR VERİ ANALİZCİSİSİN - VERİ OLUŞTURMAYAN!\n\n",
            "Kullanıcı sana araç sonuçları verdiğinde:\n",
            "- O sonuçlardaki EXACT rakamları kullan\n",
            "- Hiçbir şeyi uydurma\n",
            "- 'Örnek' deme\n",
            "- Eğer veri yoksa 'Sonuç yok' de\n\n",
            "BU MUTLAK BİR KURALDIR."
          )
        )
        
        # Türkçe: Sistem mesajını chat_history'nin başına ekle
        chat_history <- c(list(system_msg_anti_hallucination), chat_history)
		
		# Türkçe: DEBUG - Tüm chat_history'yi dosyaya yaz
        tryCatch({
          debug_file <- file.path(tempdir(), sprintf("chat_debug_%s.txt", format(Sys.time(), "%Y%m%d_%H%M%S")))
          writeLines(
            c(
              "═══════════════════════════════════════════════",
              "CHAT HISTORY - AI'A GÖNDERİLEN TÜM MESAJLAR",
              "═══════════════════════════════════════════════",
              "",
              sapply(seq_along(chat_history), function(i) {
                msg <- chat_history[[i]]
                paste0(
                  "\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n",
                  "MESAJ #", i, " - Role: ", msg$role, "\n",
                  "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n",
                  msg$content
                )
              })
            ),
            debug_file
          )
          cat("\n[GLOBAL] ✓ Chat history dosyaya yazıldı:", debug_file, "\n")
          cat("[GLOBAL] Bu dosyayı inceleyerek AI'a tam olarak ne gönderildiğini görebilirsiniz\n\n")
        }, error = function(e) {
          cat("[GLOBAL] Dosya yazma hatası:", e$message, "\n")
        })
        
        # SECOND PASS: ask the model to write the final answer from tool results (tools OFF)
        messages_payload2 <- lapply(chat_history, function(msg) {
          role_val <- if (!is.null(msg$type)) {
            if (identical(msg$type, "user")) "user"
            else if (identical(msg$type, "system")) "system"
            else "assistant"
          } else if (!is.null(msg$role)) {
            tolower(as.character(msg$role))
          } else {
            "user"
          }
          content_val <- msg$content %||% msg$message %||% as.character(msg)
          list(role = role_val, content = content_val)
        })
        
        body2 <- list(
          model = selected_model,
          messages = messages_payload2,
          stream = FALSE,
          temperature = temp_value
        )
        
        hdrs2 <- list(`Content-Type` = "application/json")
        if (!is.null(api_key) && nzchar(api_key)) {
          hdrs2$Authorization <- paste("Bearer", api_key)
        }
        
        response2 <- httr::POST(
          api_endpoint,
          do.call(httr::add_headers, hdrs2),
          body = jsonlite::toJSON(body2, auto_unbox = TRUE),
          encode = "raw",
          timeout(300)
        )
        
		status2 <- httr::status_code(response2)
		if (status2 != 200) {
		  fb <- format_answer_from_tool_results(tool_results_raw)
		  if (!(is.character(fb) && length(fb) > 0 && nzchar(trimws(fb[1])))) {
			fb <- "Araç çıktıları alındı ancak yanıt üretilemedi."
		  }
		  if (is.character(chart_blocks_text) && nzchar(chart_blocks_text)) {
			fb <- paste0(fb, "\n\n", chart_blocks_text)
		  }
		  # Türkçe yorum: Eğer grafik hâlâ yoksa zorunlu yedek grafiği ekle
		  fb <- add_fallback_chart(fb)

		  return(list(
			content  = fb,
			duration = as.numeric(difftime(Sys.time(), worker_start_time, units = "secs")),
			chart_store = charts_to_store
		  ))
		}

		# Türkçe: İkinci geçiş yanıtını da güvenli ayrıştır
		rc2 <- safe_parse_llm_response(response2)
        ai2 <- NULL
        if (is.list(rc2) && !is.null(rc2$choices) && length(rc2$choices) > 0) {
          first_choice2 <- rc2$choices[[1]]
          if (is.list(first_choice2) && !is.null(first_choice2$message)) {
            ai2 <- first_choice2$message$content
          }
        }
        
		if (!(is.character(ai2) && length(ai2) > 0 && nzchar(ai2[1]))) {
		  fb <- format_answer_from_tool_results(tool_results_raw)
		  if (!(is.character(fb) && length(fb) > 0 && nzchar(trimws(fb[1])))) {
			fb <- "Araç çıktıları alındı ancak modelden içerik gelmedi."
		  }
		  if (is.character(chart_blocks_text) && nzchar(chart_blocks_text)) {
			fb <- paste0(fb, "\n\n", chart_blocks_text)
		  }
		  # Türkçe yorum: Eğer grafik hâlâ yoksa zorunlu yedek grafiği ekle
		  fb <- add_fallback_chart(fb)

		  return(list(
			content  = fb,
			duration = as.numeric(difftime(Sys.time(), worker_start_time, units = "secs")),
			chart_store = charts_to_store
		  ))
		}
        
		ai2 <- strip_planner_text(ai2)

		# Türkçe yorum: Eğer araçlardan gelen grafik bloğu varsa ekle
		if (is.character(chart_blocks_text) && nzchar(chart_blocks_text)) {
		  ai2 <- paste0(ai2, "\n\n", chart_blocks_text)
		}

		# Türkçe yorum: Hâlâ grafik yoksa (model araç çağırmış olsa bile veri görselleştirmemişse) yedek grafik ekle
		ai2 <- add_fallback_chart(ai2)

		return(list(
		  content  = ai2,
		  duration = as.numeric(difftime(Sys.time(), worker_start_time, units = "secs")),
		  chart_store = charts_to_store
		))

	  } else {
		cat("[MCP] No tool calls detected (structured or textual)\n")
      }
    }
    
    cat("[SUCCESS] Returning response\n")
    cat("========================================\n\n")

	ai_content <- strip_planner_text(ai_content)

	# Türkçe: Yapısal kaynak yoksa düz metin Kaynakça'yı tıklanabilir yap
	ai_content <- convert_plain_kaynakca_to_clickable(ai_content)

	# Türkçe yorum: Model araç çağırmadıysa ve grafik niyeti varsa yedek grafik bloğu ekle
	ai_content <- add_fallback_chart(ai_content)

	return(list(
	  content = ai_content,
	  duration = as.numeric(difftime(Sys.time(), worker_start_time, units = "secs")),
	  chart_store = charts_to_store
	))
    
  }, error = function(e) {
    error_msg <- as.character(e$message)
    cat("[ERROR]", error_msg, "\n")
    
    if (grepl("^RATE_LIMIT:|^AUTH_ERROR:|^SERVER_ERROR:|^API_ERROR:|^EMPTY_RESPONSE:", error_msg)) {
      stop(error_msg)
    } else if (grepl("Timeout", error_msg, ignore.case = TRUE)) {
      stop("TIMEOUT: İstek zaman aşımına uğradı.")
    } else {
      stop(sprintf("UNKNOWN_ERROR: %s", error_msg))
    }
  })
}

  # =============================================================================
  # Türkçe: API yanıtını güvenli şekilde ayrıştır.
  # text/event-stream gibi beklenmeyen Content-Type durumlarını yönetir.
  # =============================================================================
  safe_parse_llm_response <- function(response) {
    ct <- httr::headers(response)[["content-type"]] %||% ""
    
    # Türkçe: Eğer content-type text/event-stream ise, httr::content("parsed") çöker.
    # Bu durumda ham metin olarak oku ve SSE veya JSON olarak ayrıştır.
    if (grepl("text/event-stream", ct, fixed = TRUE)) {
      cat("[PARSE] Content-Type text/event-stream algılandı, manuel ayrıştırma yapılıyor\n")
      raw_text <- httr::content(response, "text", encoding = "UTF-8")
      
      # DEBUG: Ham yanıtın ilk 500 karakterini logla
      cat("[PARSE] Ham yanıt uzunluğu:", nchar(raw_text), "karakter\n")
      cat("[PARSE] İlk 500 karakter: ", substr(raw_text, 1, 500), "\n")
      
      # Türkçe: ÖNCE düz JSON olarak ayrıştırmayı dene.
      # Bazı API'ler text/event-stream başlığı ile düz JSON döndürür.
      json_result <- tryCatch({
        parsed <- jsonlite::fromJSON(raw_text, simplifyVector = FALSE)
        # Türkçe: Geçerli OpenAI uyumlu yapı mı kontrol et
        if (is.list(parsed) && !is.null(parsed$choices) && length(parsed$choices) > 0) {
          cat("[PARSE] Düz JSON olarak başarıyla ayrıştırıldı (choices mevcut)\n")
          return(parsed)
        }
        NULL
      }, error = function(e) NULL)
      
      if (!is.null(json_result)) return(json_result)
      
      # Türkçe: Düz JSON değilse SSE formatını dene (data: {...} satırları)
      lines <- strsplit(raw_text, "\n")[[1]]
      data_lines <- grep("^data:\\s*", lines, value = TRUE)
      
      cat("[PARSE] Toplam satır:", length(lines), "- SSE data satırı:", length(data_lines), "\n")
      
      if (length(data_lines) > 0) {
        # Türkçe: SSE satırlarından JSON kısmını çıkar
        data_lines <- sub("^data:\\s*", "", data_lines)
        data_lines <- data_lines[!grepl("^\\[DONE\\]", trimws(data_lines))]
        data_lines <- data_lines[nzchar(trimws(data_lines))]
        
	  cat("[PARSE] Filtrelenmiş data satırı:", length(data_lines), "\n")
        if (length(data_lines) > 0) {
          cat("[PARSE] İlk data satırı: ", substr(data_lines[1], 1, 300), "\n")
        }
        
        if (length(data_lines) == 0) {
          stop("EMPTY_RESPONSE: SSE yanıtında geçerli veri satırı bulunamadı.")
        }
        
        # Türkçe: Streaming delta'ları birleştir
        full_content <- ""
        sources_collected <- NULL
        tool_calls_map <- list()
        
        for (dl in data_lines) {
          parsed <- tryCatch(jsonlite::fromJSON(dl, simplifyVector = FALSE), error = function(e) {
            cat("[PARSE] JSON ayrıştırma hatası: ", substr(dl, 1, 100), " -> ", e$message, "\n")
            NULL
          })
          if (is.null(parsed)) next
          
          if (!is.null(parsed$choices) && length(parsed$choices) > 0) {
            ch <- parsed$choices[[1]]
            
            # Streaming format: delta.content
            dc <- ch$delta$content
            if (is.character(dc) && nzchar(dc)) {
              full_content <- paste0(full_content, dc)
            }
            
            # Non-streaming format: message.content (tam yanıt tek parçada)
            mc <- ch$message$content
            if (is.character(mc) && nzchar(mc)) {
              full_content <- mc
            }
            
            # Türkçe: Streaming tool_calls delta parçalarını birleştir
            tc_list <- ch$delta$tool_calls %||% ch$message$tool_calls
            if (is.list(tc_list) && length(tc_list) > 0) {
              for (tc in tc_list) {
                tc_idx <- as.character(tc$index %||% "0")
                if (is.null(tool_calls_map[[tc_idx]])) {
                  tool_calls_map[[tc_idx]] <- list(name = "", arguments = "")
                }
                if (!is.null(tc$`function`$name) && nzchar(tc$`function`$name)) {
                  tool_calls_map[[tc_idx]]$name <- tc$`function`$name
                }
                if (!is.null(tc$`function`$arguments)) {
                  tool_calls_map[[tc_idx]]$arguments <- paste0(
                    tool_calls_map[[tc_idx]]$arguments,
                    tc$`function`$arguments
                  )
                }
              }
            }
            
            # Kaynakları topla
            sc <- ch$message$sources %||% ch$delta$sources
            if (!is.null(sc)) sources_collected <- sc
          }
          # Üst düzey kaynaklar
          if (!is.null(parsed$sources)) sources_collected <- parsed$sources
        }
        
		# Türkçe: Tool call'ları yapısal olarak koru, argümanları içerik olarak ÇIKARMA.
        # Model arama sorgusu (ör. query_knowledge_files) döndürebilir — bu yanıt değil.
        assembled_tool_calls <- NULL
        if (length(tool_calls_map) > 0) {
          cat("[PARSE] Tool calls algılandı (", length(tool_calls_map), " adet)\n")
          assembled_tool_calls <- lapply(names(tool_calls_map), function(tc_key) {
            tc_info <- tool_calls_map[[tc_key]]
            cat("[PARSE] Tool call [", tc_key, "]: name=", tc_info$name, 
                " args_len=", nchar(tc_info$arguments), "\n")
            list(
              id = paste0("call_sse_", tc_key),
              type = "function",
              `function` = list(
                name = tc_info$name,
                arguments = tc_info$arguments
              )
            )
          })
        }
        
        cat("[PARSE] SSE birleştirme sonucu: content_nchar=", nchar(full_content), 
            " tool_calls=", length(tool_calls_map), "\n")
        
		# Türkçe: Standart OpenAI uyumlu yapı oluştur (tool_calls dahil)
        msg <- list(content = full_content, role = "assistant")
        if (!is.null(assembled_tool_calls)) {
          msg$tool_calls <- assembled_tool_calls
        }
        if (!is.null(sources_collected)) {
          msg$sources <- sources_collected
        }
        result <- list(choices = list(list(message = msg)))
        return(result)
        
      } else {
        # Türkçe: Ne düz JSON ne SSE — ham metin varsa onu doğrudan içerik olarak dön
        raw_trimmed <- trimws(raw_text)
        if (nzchar(raw_trimmed)) {
          cat("[PARSE] SSE/JSON ayrıştırılamadı, ham metin içerik olarak kullanılıyor\n")
          return(list(
            choices = list(list(
              message = list(content = raw_trimmed, role = "assistant")
            ))
          ))
        }
        stop("EMPTY_RESPONSE: text/event-stream yanıtı boş.")
      }
      
    } else {
      # Türkçe: Normal content-type — httr'nin kendi ayrıştırıcısını kullan,
      # hata alırsa ham metin + jsonlite'a düş
      tryCatch(
        httr::content(response, "parsed"),
        error = function(e) {
          cat("[PARSE] httr::content('parsed') başarısız, ham metin deneniyor:", e$message, "\n")
          raw_text <- httr::content(response, "text", encoding = "UTF-8")
          tryCatch(
            jsonlite::fromJSON(raw_text, simplifyVector = FALSE),
            error = function(e2) {
              stop(paste0("PARSE_ERROR: Yanıt ayrıştırılamadı: ", e2$message))
            }
          )
        }
      )
    }
  }
  
  # =============================================================================
  # Türkçe: Düz metin Kaynakça satırlarını tıklanabilir HTML span'lara dönüştür.
  # Yapısal sources verisi olmadığında yedek olarak çalışır.
  # =============================================================================
  convert_plain_kaynakca_to_clickable <- function(content_text) {
    if (!is.character(content_text) || !nzchar(content_text)) return(content_text)
    
    # Türkçe: Zaten tıklanabilir source-link span'ları varsa dokunma
    if (grepl("class='source-link'", content_text, fixed = TRUE) ||
        grepl('class="source-link"', content_text, fixed = TRUE)) {
      return(content_text)
    }
    
    # Türkçe: Kaynakça bölümü var mı kontrol et
    kaynakca_pos <- regexpr("Kaynak[çc]a\\s*:", content_text, perl = TRUE)
    if (kaynakca_pos < 0) return(content_text)
    
    # Türkçe: Kaynakça bölümünü ve öncesini ayır
    before_part <- substr(content_text, 1, kaynakca_pos - 1)
    kaynakca_part <- substr(content_text, kaynakca_pos, nchar(content_text))
    
    # Türkçe: Numaralı satırları bul (ör: "1) dosya.docx", "2. rapor.pdf")
    # Ayrıca "- dosya.docx" formatını da yakala
    lines <- strsplit(kaynakca_part, "\n")[[1]]
    
    converted_lines <- vapply(lines, function(line) {
      # Türkçe: Numaralı kaynak satırını tespit et
      m <- regmatches(line, regexec("^\\s*(\\d+)[)\\.]\\s*(.+)$", line))[[1]]
      if (length(m) < 3) return(line)
      
      num <- m[2]
      raw_filename <- trimws(m[3])
      
      # Türkçe: Markdown kalıntılarını temizle
      raw_filename <- gsub("\\*\\*", "", raw_filename)
      raw_filename <- trimws(raw_filename)
      
      if (!nzchar(raw_filename)) return(line)
      
      # Türkçe: Benzersiz source id oluştur
      source_id <- paste0("source_", num, "_", gsub("[^a-z0-9]", "", tolower(raw_filename)))
      
      # Türkçe: Dosya uzantısına göre ikon seç
      file_ext <- tolower(tools::file_ext(raw_filename))
      icon_html <- if (file_ext %in% c("doc", "docx")) {
        "<i class='fa-regular fa-file-word' style='margin-right:6px;color:#2b579a'></i>"
      } else if (identical(file_ext, "pdf")) {
        "<i class='fa-regular fa-file-pdf' style='margin-right:6px;color:#c00'></i>"
      } else if (file_ext %in% c("xls", "xlsx")) {
        "<i class='fa-regular fa-file-excel' style='margin-right:6px;color:#1d6f42'></i>"
      } else {
        "<i class='fa-regular fa-file' style='margin-right:6px;'></i>"
      }
      
      # Türkçe: Tıklanabilir HTML span oluştur
      clickable_html <- paste0(
        "<span class='source-link' data-source-id='", source_id,
        "' data-filename='", htmltools::htmlEscape(raw_filename, attribute = TRUE),
        "' style='color:#007bff; cursor:pointer; text-decoration:underline;'>",
        htmltools::htmlEscape(raw_filename),
        "</span>"
      )
      
      paste0(num, ") ", icon_html, clickable_html)
    }, character(1), USE.NAMES = FALSE)
    
    new_kaynakca <- paste(converted_lines, collapse = "\n")
    paste0(before_part, new_kaynakca)
  }

  # Worker-safe LLM call - RESTORED FROM ORIGINAL WORKING VERSION
  call_local_llm <- function(chat_history, current_settings) {
	llm_start_time <- Sys.time()
    selected_model <- current_settings$model_selection
    
    creds <- resolve_local_llm_credentials(selected_model)
    api_url <- creds$endpoint
    if (!nzchar(api_url)) {
	  stop("API endpoint not found in configuration")
	}
    
	default_api_key <- creds$default_api_key %||% ""
	allow_user_key <- isTRUE(creds$allow_user_key)
	# Türkçe yorum: Önce ilgili uç için kullanıcı anahtarı kullanılabilir mi bak
	api_key <- ""
	if (allow_user_key) {
	  api_key <- as.character(current_settings$api_key %||% current_settings$api_key_override %||% "")
	  if (!nzchar(api_key)) {
		sess <- current_settings$shiny_session %||% NULL
		if (!is.null(sess) && !is.null(sess$userData$ai_api_key)) {
			  api_key <- as.character(sess$userData$ai_api_key)[1]
		}
	  }
	} else {
	  api_key <- as.character(current_settings$api_key_override %||% "")
	}
	if (!nzchar(api_key) && nzchar(default_api_key)) {
	  api_key <- as.character(default_api_key)[1]
	}
	# Türkçe: Yerel uçlar (Ollama/LM Studio vb.) için anahtar zorunlu değil
	is_local_noauth <- grepl("(?i)(localhost|127\\.0\\.0\\.1|ollama)", api_url)
	if (!nzchar(api_key) && !is_local_noauth) {
	  stop("AUTH_MISSING_KEY: Kullanıcı API anahtarı bulunamadı. Lütfen Ayarlar > Model Ayarları > API Anahtarı Güncelleme üzerinden girin.")
	}
    
    messages_payload <- lapply(chat_history, function(msg) {
      role_val <- NULL
		if (!is.null(msg$type)) {
		  role_val <- if (identical(msg$type, "user")) "user"
			else if (identical(msg$type, "system")) "system"
			else "assistant"
		} else if (!is.null(msg$role)) {
        role_val <- tolower(as.character(msg$role))
        if (!(role_val %in% c("user", "assistant", "system"))) {
          role_val <- "user"
        }
      } else {
        role_val <- "user"
      }
    
      content_val <- NULL
      if (!is.null(msg$content)) {
        content_val <- msg$content
      } else if (!is.null(msg$message)) {
        content_val <- msg$message
      } else {
        content_val <- as.character(msg)
      }
    
      list(role = role_val, content = content_val)
    })
  
    # Get temperature from settings if available
    temp_value <- if (!is.null(current_settings$temperature)) current_settings$temperature else 0.4
	
	max_tokens_val <- current_settings$max_output_tokens %||% 2048
    
    body <- list(
      model = selected_model,
      messages = messages_payload,
      stream = FALSE,
      temperature = temp_value,
      max_tokens = max_tokens_val
    )
    
	# Türkçe: Yerel uçlarda boş Authorization başlığını GÖNDERME
	hds <- list(`Content-Type` = "application/json")
	if (nzchar(api_key)) hds$Authorization <- paste("Bearer", api_key)

	  response <- tryCatch({
		httr::POST(
		  url = api_url,
		  body = body,
		  encode = "json",
		  do.call(httr::add_headers, hds),
		  httr::timeout(300)
		)
	  }, error = function(e) {
		stop(sprintf("API_CONNECTION_ERROR: %s", conditionMessage(e)))
	  })
	  
	  if (httr::status_code(response) >= 400) {
		error_content <- try(httr::content(response, "text", encoding = "UTF-8"), silent = TRUE)
		stop(sprintf("API_HTTP_ERROR_%d: %s", 
					 httr::status_code(response), 
					 if(!inherits(error_content, "try-error")) substr(error_content, 1, 200) else ""))
	  }
	  
	# Türkçe: text/event-stream dahil tüm yanıt formatlarını güvenli ayrıştır
    response_content <- safe_parse_llm_response(response)
    
    # Extract content and sources
    ai_content <- NULL
    sources_list <- NULL
    
    if (is.list(response_content) && 
        !is.null(response_content$choices) && 
        length(response_content$choices) > 0) {
      first_choice <- response_content$choices[[1]]
      if (is.list(first_choice) && 
          !is.null(first_choice$message) && 
          !is.null(first_choice$message$content)) {
        content_obj <- first_choice$message$content
		if (is.character(content_obj) && length(content_obj) > 0) {
		  ai_content <- trimws(content_obj[1])
		} else {
		  ai_content <- ""
		}
        
        # Extract sources if present
        if (!is.null(first_choice$message$sources)) {
          sources_list <- first_choice$message$sources
        }
      }
    }
	
	# DEBUG LOG: içerik çıkarımından hemen sonra
    cat("[LOCAL_LLM] parsed content length=",
        if (is.null(ai_content)) NA_integer_ else length(ai_content),
        " class=", paste(class(ai_content), collapse = ","),
        " nzchar1=",
        if (is.character(ai_content) && length(ai_content) > 0) nzchar(ai_content[1]) else NA,
        ' preview="', substr(as.character(ai_content)[1], 1, 120), '"\n',
        sep = "")
    
    # Check for sources at different levels
    if (is.null(sources_list) && !is.null(response_content$sources)) {
      sources_list <- response_content$sources
    }
    if (is.null(sources_list) && !is.null(response_content$message$sources)) {
      sources_list <- response_content$message$sources
    }
    
    # If sources found, extract filenames from metadata
    if (!is.null(sources_list) && length(sources_list) > 0) {
      cat("\n========== SOURCES PROCESSING ==========\n")
      
      extracted_sources <- list()
      seen_filenames <- character(0)
      
      for (i in seq_along(sources_list)) {
        src <- sources_list[[i]]
        
        if (is.list(src) && !is.null(src[["metadata"]])) {
          metadata_array <- src[["metadata"]]
          
          for (j in seq_along(metadata_array)) {
            doc <- metadata_array[[j]]
            
            # Extract filename from "name" or "source"
            filename <- doc[["name"]] %||% doc[["source"]]
            
            if (!is.null(filename) && is.character(filename)) {
              filename <- as.character(filename)[1]
              
              # Check for duplicate
              if (filename %in% seen_filenames) {
                cat("[DOCUMENT ", j, "] DUPLICATE - skipping: <", filename, ">\n\n", sep = "")
                next
              }
              
              cat("[DOCUMENT ", j, "] Extracted: <", filename, ">\n", sep = "")
              seen_filenames <- c(seen_filenames, filename)
              
              # Parse filename: extract process number and actual filename
              process_match <- regexpr("^[a-z]+_[0-9]+_[0-9]+_", filename, ignore.case = TRUE)
              
              process_num <- ""
              actual_filename <- filename
              
              if (process_match > 0) {
                match_length <- attr(process_match, "match.length")
                process_part <- substr(filename, 1, match_length - 1)
                actual_filename <- substr(filename, match_length + 1, nchar(filename))
                
                # Format process number: replace underscores AND dashes with spaces, uppercase
                process_num <- toupper(process_part)
                process_num <- gsub("_", " ", process_num)
                process_num <- gsub("-", " ", process_num)
                
                cat("[DOCUMENT ", j, "] Process: <", process_num, ">\n", sep = "")
                cat("[DOCUMENT ", j, "] Filename: <", actual_filename, ">\n", sep = "")
              }
              
              # Format actual filename
              file_ext <- tools::file_ext(actual_filename)
              file_base <- tools::file_path_sans_ext(actual_filename)
              file_base <- gsub("_", " ", file_base)
              file_base <- gsub("-", " ", file_base)
              file_base <- tools::toTitleCase(file_base)
              formatted_filename <- paste0(file_base, ".", file_ext)
              
              extracted_sources[[length(extracted_sources) + 1]] <- list(
                process = process_num,
                filename = formatted_filename,
                original_filename = filename
              )
              
              cat("[DOCUMENT ", j, "] Final: ", process_num, ": ", formatted_filename, "\n\n", sep = "")
            }
          }
        }
      }
      
      cat("[SUMMARY] Total unique sources:", length(extracted_sources), "\n")
      
		# Append Kaynakça section with clickable links
		if (length(extracted_sources) > 0) {
		  sources_text <- "\n\nKaynakça:\n"
		  
		  for (i in seq_along(extracted_sources)) {
			src_info <- extracted_sources[[i]]
			
			# Unique id for this source
			source_id <- paste0("source_", i, "_", gsub("[^a-z0-9]", "", tolower(src_info$filename)))
			
			# Always use the ORIGINAL filename as-is for opening
			original_filename <- src_info$original_filename
			file_ext <- tolower(tools::file_ext(original_filename))
			
			# Pick an icon by extension (Word/PDF, fallback generic)
			icon_html <- if (file_ext %in% c("doc","docx")) {
			  "<i class='fa-regular fa-file-word' style='margin-right:6px;color:#2b579a'></i>"
			} else if (identical(file_ext, "pdf")) {
			  "<i class='fa-regular fa-file-pdf' style='margin-right:6px;color:#c00'></i>"
			} else {
			  "<i class='fa-regular fa-file' style='margin-right:6px;'></i>"
			}
			
			# Görüntüde sadece son parçayı göster; ancak tıklama için TAM dosya adını taşı
			parts_raw <- strsplit(original_filename, "&&", fixed = TRUE)[[1]]
			
			# Label prefix (process info if present)
			label_prefix <- if (nchar(src_info$process) > 0) paste0(src_info$process, ": ") else ""
			
			if (length(parts_raw) > 1) {
			  parts <- trimws(parts_raw)
			  left_parts <- if (length(parts) > 1) parts[seq_len(length(parts) - 1)] else character(0)
			  right_part <- parts[length(parts)]
			  
			  left_html <- if (length(left_parts)) {
				paste(
				  vapply(left_parts, function(p) {
					paste0("<span class='source-chunk'>", htmltools::htmlEscape(p), "</span>")
				  }, character(1)),
				  collapse = " - "
				)
			  } else ""
			  
				clickable_html <- paste0(
				  "<span class='source-link' data-source-id='", source_id,
				  # tıklama için tam dosya adını (&& dahil) gönder
				  "' data-filename='", htmltools::htmlEscape(original_filename, attribute = TRUE),  # düzeltme: tam ad
				  "' style='color:#007bff; cursor:pointer; text-decoration:underline;'>",
				  htmltools::htmlEscape(trimws(right_part)),
				  "</span>"
				)
			  
			  # Compose the line:
			  #   i) [process:] [icon] [left - chunks] - [CLICKABLE last chunk]
			  line <- paste0(
				i, ") ", label_prefix, icon_html,
				if (nzchar(left_html)) paste0(left_html, " - ") else "",
				clickable_html, "\n"
			  )
			  
			} else {
			  # No "&&" — keep whole display clickable (as before), but keep the icon
			  clickable_html <- paste0(
				"<span class='source-link' data-source-id='", source_id,
				"' data-filename='", htmltools::htmlEscape(original_filename, attribute = TRUE),
				"' style='color:#007bff; cursor:pointer; text-decoration:underline;'>",
				htmltools::htmlEscape(src_info$filename),
				"</span>"
			  )
			  line <- paste0(i, ") ", label_prefix, icon_html, clickable_html, "\n")
			}
			
			sources_text <- paste0(sources_text, line)
		  }
		  
		  ai_content <- paste0(ai_content, sources_text)
		  cat("[SUCCESS] Kaynakça appended with", length(extracted_sources), "unique sources\n")
		}
      
      cat("========================================\n\n")
    }
    
	if (!(is.character(ai_content) && length(ai_content) > 0 && nzchar(ai_content[1]))) {
	  stop("EMPTY_RESPONSE: AI yanıtı boş veya geçersiz (content yok).")
	}

	ai_content <- strip_planner_text(ai_content)

	# Türkçe: Yapısal kaynak yoksa düz metin Kaynakça'yı tıklanabilir yap
	ai_content <- convert_plain_kaynakca_to_clickable(ai_content)

	# --- SAĞLAMLAŞTIRMA: her zaman scalar string döndür ---
	if (!is.character(ai_content) || length(ai_content) == 0 || is.na(ai_content[1])) {
	  ai_content <- ""
	} else {
	  ai_content <- as.character(ai_content)[1]
	}
	if (!nzchar(ai_content)) ai_content <- ""

	# DEBUG: dönüş özeti
	cat("[LOCAL_LLM] returning shape=list content_nchar=", nchar(ai_content),
		" duration_s=", as.numeric(difftime(Sys.time(), llm_start_time, units = "secs")),
		"\n", sep = "")

	return(list(
	  content  = ai_content,
	  duration = as.numeric(difftime(Sys.time(), llm_start_time, units = "secs"))
	))
  }

  # Retry logic for API calls (available in main R session)
  call_llm_with_retry <- function(chat_history, settings, max_retries = 3) {
    for (i in 1:max_retries) {
      tryCatch({
        res <- call_local_llm(chat_history, settings)
		# Back-compat: if any older call expects a character, wrap it
		if (is.character(res)) {
		  res <- list(content = as.character(res)[1] %||% "", duration = NA_real_)
		}
		return(res)
      }, error = function(e) {
        if (i == max_retries) {
          stop(e)
        }
        Sys.sleep(2^i)
      })
    }
  }
# ============================================================================== 
# Dosya Yolu: R/server_send_message.R
# Açıklama: Ana mesaj gönderme fonksiyonunu içerir. Kullanıcı mesajlarını işler,
#           araç ailesini belirler (özetleme, görsel, MCP Excel, SQL analizi),
#           LLM API çağrılarını yönetir ve yanıtları işler.
# ==============================================================================

# Mesaj gönderme fonksiyonunu oluşturur
# Tüm bağımlılıkları parametre olarak alır ve send_message fonksiyonunu döndürür
sendMessageInit <- function(
  session,
  input,
  output,
  values,
  settings_data,
  session_files,
  file_manager_data,
  current_user_id,
  stop_generation,
  active_request_id,
  quick_action_skip_mcp,
  perf_tracker,
  ai_processor,
  tts_processor,
  followup_tools,
  fallback_followup_tool,
  api_config,
  add_message_fn,
  reset_chat_state_fn,
  simulate_streaming_stoppable_fn,
  cache_mcp_file_locally_fn,
  update_mcp_registry_snapshot_fn,
  saved_chats_data,
  generate_non_streaming_stoppable_fn
) {
	resolve_current_user_id <- function() {
	  uid <- resolve_effective_user_id(
		session = session,
		current_user_id = current_user_id
	  )
	  if (is.na(uid)) uid <- 0L
	  uid
	}

	cleanup_send_message <- function(remove_typing_wrapper = TRUE) {
	  mergen_cleanup_send_message(
		values = values,
		reset_chat_state_fn = reset_chat_state_fn,
		remove_typing_wrapper = remove_typing_wrapper
	  )
	}

	abort_send_message <- function(message = NULL, type = "warning", remove_typing_wrapper = TRUE) {
	  mergen_abort_send_message(
		session = session,
		values = values,
		reset_chat_state_fn = reset_chat_state_fn,
		toast_message = message,
		toast_type = type,
		remove_typing_wrapper = remove_typing_wrapper
	  )
	}

  # Ana mesaj gönderme fonksiyonu
  send_message <- function(prompt_text, is_summarization_request = FALSE) {
    if (isTRUE(SSO_ENABLED) && !isTRUE(session$userData$auth_initialized)) {
      showToast(session, "Kimlik doğrulama tamamlanmadan mesaj gönderilemez.", "warning")
      return(invisible(NULL))
    }

    effective_user_id <- resolve_current_user_id()
    if (effective_user_id <= 0) {
      showToast(session, "Kullanıcı kimliği alınamadı. Lütfen sayfayı yenileyin.", "error")
      return(invisible(NULL))
    }

    mergen_clear_welcome_for_send_message(session, values)

    # Performans izleme için istek başlangıç zamanını kaydet
    request_start_time <- Sys.time()
    log_info(sprintf("[CHAT PERF] send_message giriş yaptı - %.3f sn", 0))

    # Hızlı istekleri engelle
    if (values$is_sending) {
      showToast(session, "Lütfen önceki isteğin tamamlanmasını bekleyin.", "warning")
      return()
    }

    # Son istek zamanı kontrolü
    if (!is.null(values$last_request_time)) {
      time_since_last <- as.numeric(difftime(Sys.time(), values$last_request_time, units = "secs"))
      if (time_since_last < 1) {
        showToast(session, "Çok hızlı istek gönderiyorsunuz.", "warning")
        return()
      }
    }
    values$last_request_time <- Sys.time()

    prompt_snapshot <- mergen_build_send_message_prompt_snapshot(
      prompt_text = prompt_text,
      session_files = function() isolate(session_files())
    )

    user_message_text <- prompt_snapshot$user_message_text
    current_session_files <- prompt_snapshot$current_session_files
    uploaded_names <- prompt_snapshot$uploaded_names
    uploaded_count <- prompt_snapshot$uploaded_count

    if (nchar(user_message_text) == 0 && uploaded_count == 0) {
      showToast(session, "Lütfen bir mesaj yazın.", "warning")
      return()
    }

    current_settings <- reactiveValuesToList(settings_data)

    skip_mcp_once <- isTRUE(quick_action_skip_mcp())
    if (skip_mcp_once) quick_action_skip_mcp(FALSE)

    routing_info <- mergen_determine_tool_family(
      settings_data = settings_data,
      uploaded_count = uploaded_count,
      skip_mcp_once = skip_mcp_once,
      current_settings = current_settings
    )

    tool_family <- routing_info$tool_family
    current_settings <- routing_info$current_settings
    cfg_excel_on <- routing_info$cfg_excel_on
    cfg_sql_analysis_on <- routing_info$cfg_sql_analysis_on

    log_info(sprintf(
      "[CHAT PERF] Yol seçildi - araç=%s, dosya=%d, gecen=%.3f sn",
      tool_family,
      uploaded_count,
      as.numeric(difftime(Sys.time(), request_start_time, units = "secs"))
    ))

    pending_chat_title <- NULL
    defer_chat_creation <- is.null(values$current_chat_id) &&
      mergen_should_defer_chat_creation(
        tool_family = tool_family,
        uploaded_count = uploaded_count,
        current_settings = current_settings,
        settings_data = settings_data
      )

    chat_prepare <- mergen_prepare_send_message_chat(
      session = session,
      values = values,
      user_message_text = user_message_text,
      tool_family = tool_family,
      effective_user_id = effective_user_id,
      request_start_time = request_start_time,
      defer_chat_creation = defer_chat_creation,
      generate_title_from_prompt = generate_title_from_prompt
    )

    if (!isTRUE(chat_prepare$ok)) {
      return(invisible(NULL))
    }

    pending_chat_title <- chat_prepare$pending_chat_title

    # Kullanıcı mesajını ekle
    display_text <- if (nchar(user_message_text) > 0) user_message_text else "Seçili dosyaların özeti istendi."
    user_prompt_msg <- add_message_fn(display_text, "user")

    values$typing <- TRUE
    thinking_panel_plan <- mergen_build_thinking_panel_plan(
      tool_family = tool_family,
      settings_data = settings_data
    )
    mergen_show_send_message_thinking_wrapper(session, thinking_panel_plan)

    # Durdur butonunu göster
    shinyjs::runjs("$('#send_stop_btn i').attr('class', 'fa-solid fa-stop');")
    shinyjs::runjs("$('#send_stop_btn').addClass('stop-mode');")
    shinyjs::runjs("$('#send_stop_btn').attr('title', 'Durdur');")

    values$is_sending <- TRUE
    stop_generation(FALSE)

    recent_history_limit <- if ((identical(tool_family, "none") || identical(tool_family, "coding")) &&
                                uploaded_count == 0) 3 else 5

    context_messages <- Filter(function(m) {
      !isFALSE(m$include_in_context %||% TRUE)
    }, isolate(values$messages))

    recent_messages <- tail(context_messages, recent_history_limit)
    recent_messages <- Filter(function(m) {
      is.null(m$content) || !grepl("[ Toplam Dosya Sayısı:", m$content, fixed = TRUE)
    }, recent_messages)

    log_debug("[FILE CONTEXT] Oturumdaki dosya sayısı: {uploaded_count} - {paste(uploaded_names, collapse = ', ')}")

    messages_to_process <- recent_messages

    # SQL Analizi modu işleme
    if (identical(tool_family, "sql_analysis")) {
      deep_thinking_active <- isTRUE(settings_data$analysis_deep_thinking)
      analysis_detail <- settings_data$analysis_detail_level %||% "standart"

      if (deep_thinking_active) {
        log_debug("[SERVER] Derin Düşünme modu aktif. Detay: {analysis_detail}. Çoklu sorgu analizi başlatılıyor...")
      } else {
        log_debug("[SERVER] Proje ve Kaynak Analizi seçildi (tekil mod). Modül çağırılıyor...")
      }

      if (isTRUE(stop_generation())) {
        cleanup_send_message()
        return(invisible(NULL))
      }

      analiz_result <- tryCatch({
        if (deep_thinking_active) {
          pk_deep_analysis_process(
            user_message_text, messages_to_process, session,
            detail_level = analysis_detail,
            stop_check = stop_generation
          )
        } else {
          pk_analiz_process_request(user_message_text, messages_to_process, session, stop_check = stop_generation)
        }
      }, error = function(e) {
        paste0("\U000026A0\U0000FE0F Analiz modülü hatası: ", e$message)
      })

      if (is.character(analiz_result)) {
        cleanup_send_message()
        add_message_fn(analiz_result, "ai")
        return(invisible(NULL))

      } else if (is.list(analiz_result)) {
        if (identical(analiz_result$type, "error_message")) {
          cleanup_send_message()
          add_message_fn(analiz_result$content, "ai")
          return(invisible(NULL))
        }

        log_debug("[SERVER] SQL Analizi başarılı. Veriler LLM bağlamına ekleniyor... (Derin: {deep_thinking_active})")

        if (!is.null(analiz_result$max_tokens)) {
          current_settings$max_output_tokens <- analiz_result$max_tokens
        }

        last_idx <- length(messages_to_process)
        if (last_idx > 0) {
          messages_to_process[[last_idx]]$content <- analiz_result$user_context
        }

        sys_msg <- list(
          role = "system",
          content = analiz_result$prompt_context,
          type = "system"
        )
        messages_to_process <- append(list(sys_msg), messages_to_process)
      }
    }

    # Karakter verilerini al
    selected_char_id <- settings_data$selected_character %||% "mergen"
    chars_data <- get_characters_data()
    character_data <- if (!is.null(chars_data)) {
      Find(function(x) x$id == selected_char_id, chars_data$styles)
    } else NULL

    # Karakter sistem promptunu kullan
    base_instruction <- if (!is.null(character_data)) {
      character_data$system_prompt_en
    } else {
      "Be a balanced, pragmatic assistant. Provide clear, actionable responses."
    }

    # Kaynak gösterimi zorunluluğu
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

    # Mod bazlı sistem promptu oluştur
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
      style_instruction <- paste0(
        base_instruction,
        "\n\nGÖRSEL OLUŞTURMA MODU:\n",
        "Kullanıcının isteğine göre görsel oluşturulacak.",
        citation_instruction
      )
    } else {
      style_instruction <- paste0(base_instruction, citation_instruction)
    }

    # Sıcaklık değerini karakterden al
    temperature_value <- if (!is.null(character_data) && !is.null(character_data$parameters$temperature)) {
      character_data$parameters$temperature
    } else {
      0.4
    }

    # SQL analizinde ikinci system mesajı üretme
    system_msg <- list(type = "system", content = style_instruction)

    if (identical(tool_family, "sql_analysis") &&
        length(messages_to_process) > 0 &&
        identical(
          tolower(as.character(messages_to_process[[1]]$role %||% messages_to_process[[1]]$type %||% "")),
          "system"
        )) {

      mevcut_system_icerik <- as.character(messages_to_process[[1]]$content %||% "")
      messages_to_process[[1]]$content <- paste0(style_instruction, "\n\n", mevcut_system_icerik)
      messages_to_process[[1]]$type <- "system"
      messages_to_process[[1]]$role <- "system"

    } else {
      messages_to_process <- c(list(system_msg), messages_to_process)
    }

    log_debug("[STYLE] Karakter: {selected_char_id} (sıcaklık: {sprintf('%.2f', temperature_value)})")

    # DOSYA ÖZETLEME MODU
    if (identical(tool_family, "summarization")) {
      summarization_ctx <- list(
        session = session,
        input = input,
        output = output,
        values = values,
        settings_data = settings_data,
        ai_processor = ai_processor,
        stop_generation = stop_generation,
        active_request_id = active_request_id,
        perf_tracker = perf_tracker,
        api_config = api_config,
        current_user_id = effective_user_id,
        uploaded_count = uploaded_count,
        user_message_text = user_message_text,
        current_session_files = current_session_files,
        user_prompt_msg = user_prompt_msg,
        chat_id_val = isolate(values$current_chat_id),
        saved_chats_data = saved_chats_data,
        followup_tools = followup_tools,
        fallback_followup_tool = fallback_followup_tool,
        request_start_time = request_start_time,
        add_message_fn = add_message_fn,
        reset_chat_state_fn = reset_chat_state_fn
      )
      handle_summarization_mode(summarization_ctx)
      return(invisible(NULL))

    # GÖRSEL OLUŞTURMA MODU
    } else if (identical(tool_family, "image")) {
      image_ctx <- list(
        session = session, input = input, values = values,
        settings_data = settings_data,
        user_message_text = user_message_text,
        current_user_id = effective_user_id,
        add_message_fn = add_message_fn, reset_chat_state_fn = reset_chat_state_fn
      )
      handle_image_generation_mode(image_ctx)
      return(invisible(NULL))

    } else if (identical(tool_family, "mcp_excel") && uploaded_count > 0) {
      # MCP EXCEL MODU
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
      # MCP kapalı ise seçili dosyaların özetini bağlama ekle
      file_blocks <- character(0)
      total_budget <- 120000
      per_file_cap <- max(4000, floor(total_budget / max(1, uploaded_count)))

      summary_store <- session_user_data_get_list(session, "file_summaries")
      current_file_store <- session_user_data_get_list(session, "current_session_files")

      for (fname in uploaded_names) {
        sumtxt <- summary_store[[fname]] %||% ""
        if (!is.character(sumtxt) || !nzchar(sumtxt[1])) {
          fobj <- current_file_store[[fname]] %||% NULL
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
      # Standart sohbet modu veya SQL analizi
      if (identical(tool_family, "sql_analysis")) {
        # messages_to_process zaten hazır
      } else {
        messages_to_process <- c(list(system_msg), recent_messages)
      }
    }

    # API anahtarı kontrolü
    {
      api_key_val <- tryCatch(as.character(session$userData$ai_api_key)[1], error = function(e) "")
      if (!nzchar(api_key_val)) {
        abort_send_message(
          message = "API anahtarı eksik. Ayarlar > Model Ayarları > API Anahtarı Güncelleme üzerinden girin.",
          type = "error"
        )
        return(invisible(NULL))
      }
    }

    chat_id_val <- isolate(values$current_chat_id)

    # Modeli araç ailesine göre server-side kesin olarak çöz
    model_selected <- resolve_tool_model_for_family(
      tool_family,
      fallback_model = current_settings$model_selection
    )

    current_settings$model_selection <- model_selected

    current_settings$current_user_id <- effective_user_id
    current_settings$tool_family <- tool_family

    # Yalnızca gerçek MCP araç çağrısı için MCP aktif edilir
    current_settings$enable_mcp_tools <- identical(tool_family, "mcp_excel")

    current_settings$temperature      <- temperature_value
    current_settings$uploaded_files   <- uploaded_names
    current_settings$shiny_session    <- session
    current_settings$api_key_override <- api_key_val

    mcp_registry_info <- mergen_prepare_mcp_session_files(
      session = session,
      file_manager_data = file_manager_data,
      uploaded_names = uploaded_names,
      effective_user_id = effective_user_id,
      current_settings = current_settings,
      cache_mcp_file_locally_fn = cache_mcp_file_locally_fn,
      update_mcp_registry_snapshot_fn = update_mcp_registry_snapshot_fn,
      tool_family = tool_family
    )

    mcp_snapshot <- mcp_registry_info$mcp_snapshot
    current_settings$mcp_registry_snapshot <- mcp_snapshot

    # Dosya yollarını Excel modunda ilet
    current_settings$file_paths <- list()
    if (identical(tool_family, "mcp_excel") && length(uploaded_names) > 0) {
      registry_paths <- session_user_data_get_list(session, "current_session_files")
      for (fname in uploaded_names) {
        file_obj <- registry_paths[[fname]]
        if (!is.list(file_obj)) next

        full_path <- file_obj$path %||% file_obj$datapath
        if (is.null(full_path) || !nzchar(full_path)) next

        current_settings$file_paths[[fname]] <- as.character(full_path)
        log_debug("[FILE PATH ADDED] {fname} -> {full_path}")
      }
    }

    # Model seçilmemişse varsayılanı kullan
    if (is.null(model_selected) || model_selected == "") {
      model_selected <- api_config$local_models[1]
    }

	# Düşünmeli modellerde SQL analizi akışını streaming yerine non-streaming çalıştır
	is_thinking_model <- grepl("(?i)(think|reason|qwen3\\.5)", model_selected, perl = TRUE)
	force_non_streaming_sql <- identical(tool_family, "sql_analysis") && is_thinking_model

    stream_profile <- mergen_build_stream_profile(
      tool_family = tool_family,
      uploaded_count = uploaded_count,
      settings_data = settings_data,
      force_non_streaming_sql = force_non_streaming_sql
    )

    log_debug("Mesaj gönderiliyor, model: {model_selected}")
	if (isTRUE(force_non_streaming_sql)) {
	  log_debug("[MONITORING] SQL analizi için düşünmeli model tespit edildi; streaming kapatılıp non-streaming kullanılacak")
	}

    log_info(sprintf(
      "[CHAT PERF] LLM isteği hazırlanıyor - yol=%s, profil=%s, gecen=%.3f sn",
      tool_family,
      stream_profile$label,
      as.numeric(difftime(Sys.time(), request_start_time, units = "secs"))
    ))

    # LLM çağrısı: Streaming veya Non-streaming
    if (isTRUE(current_settings$enable_streaming) &&
        !isTRUE(current_settings$enable_mcp_tools) &&
        !isTRUE(settings_data$enable_tts_audio) &&
        !isTRUE(force_non_streaming_sql)) {
      # GERÇEK SSE modu
      log_debug("[MONITORING] AI isteği başlatılıyor (GERÇEK SSE modu)")

      safe_settings <- current_settings
      safe_settings$shiny_session <- NULL
      dbg_dump("LLM_REQUEST_TRUE_STREAMING", list(
        model = model_selected,
        messages = messages_to_process,
        settings = safe_settings
      ))

      true_stream_ctx <- list(
        session = session,
        input = input,
        output = output,
        values = values,
        settings_data = settings_data,
        stop_generation = stop_generation,
        active_request_id = active_request_id,
        perf_tracker = perf_tracker,
        api_config = api_config,
        current_user_id = effective_user_id,
        current_settings = current_settings,
        model_selected = model_selected,
        messages_to_process = messages_to_process,
        user_message_text = user_message_text,
        user_prompt_msg = user_prompt_msg,
        chat_id_val = chat_id_val,
        pending_chat_title = pending_chat_title,
        saved_chats_data = saved_chats_data,
        add_message_fn = add_message_fn,
        reset_chat_state_fn = reset_chat_state_fn,
        followup_tools = followup_tools,
        fallback_followup_tool = fallback_followup_tool,
        request_start_time = request_start_time,
        stream_profile = stream_profile
      )

      handle_true_streaming_mode(true_stream_ctx)

    } else if (isTRUE(current_settings$enable_streaming) &&
               !isTRUE(current_settings$enable_mcp_tools) &&
               !isTRUE(force_non_streaming_sql)) {
      # TTS açıkken mevcut davranışı koru
      start_time <- Sys.time()

      log_debug("[MONITORING] AI isteği başlatılıyor (STREAMING modu)")

      settings_for_llm <- current_settings
      settings_for_llm$model_selection <- model_selected

      req_id <- mergen_new_send_message_request_id()
      active_request_id(req_id)
      stop_generation(FALSE)
      values$is_sending <- TRUE

      safe_settings <- current_settings
      safe_settings$shiny_session <- NULL
      dbg_dump("LLM_REQUEST_STREAMING", list(model = model_selected, messages = messages_to_process, settings = safe_settings))

      p <- ai_processor$call_llm_streaming(messages_to_process, current_settings, model_selected)

      p <- promises::then(p, onFulfilled = function(result) {
        result$req_id <- req_id
        result
      })

      p <- promises::then(
        p,
        onFulfilled = function(res) {
          request_state <- mergen_send_message_request_state(active_request_id, res$req_id, stop_generation)
          if (!identical(request_state, "current")) {
            try(log_ai_usage(chat_id_val, user_prompt_msg$db_id, effective_user_id,
                             model_selected, res$duration, FALSE), silent = TRUE)
            if (identical(request_state, "stopped")) {
              cleanup_send_message()
            }
            return(invisible(NULL))
          }

          if (!res$success) {
            log_warn("[AI MODULE] Streaming isteği başarısız")
            perf_tracker$track_error()
            abort_send_message(message = res$error, type = "error")
            return(invisible(NULL))
          }

          log_debug("[MONITORING] Streaming isteği tamamlandı")
          dbg_dump("LLM_RESPONSE_STREAMING", list(
            success = res$success, duration = res$duration,
            content_preview = substr(res$content %||% "", 1, 800)
          ))

          perf_tracker$track_request(res$duration)

          try(log_ai_usage(chat_id_val, user_prompt_msg$db_id, effective_user_id,
                           model_selected, res$duration, TRUE), silent = TRUE)

          if (is.list(res$chart_store) && length(res$chart_store) > 0) {
            if (is.null(session$userData$chart_store) || !is.list(session$userData$chart_store)) {
              session$userData$chart_store <- list()
            }
            session$userData$chart_store <- utils::modifyList(session$userData$chart_store, res$chart_store)
          }

          # Takip soruları oluştur
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

          simulate_streaming_stoppable_fn(
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
          log_warn("[MONITORING] Streaming isteği BAŞARISIZ")
          perf_tracker$track_error()

          duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
          try(log_ai_usage(chat_id_val, user_prompt_msg$db_id, effective_user_id,
                           model_selected, duration, FALSE), silent = TRUE)

          request_state <- mergen_send_message_request_state(active_request_id, req_id, stop_generation)
          if (identical(request_state, "current")) {
            msg <- as.character(conditionMessage(err))
            msg <- sub("^[A-Z_]+:\\s*", "", msg)
            if (!nzchar(msg)) msg <- "Beklenmeyen bir hata oluştu."
            abort_send_message(message = msg, type = "error")
            return(invisible(NULL))
          }

          if (identical(request_state, "stopped")) {
            cleanup_send_message()
          }
          invisible(NULL)
        }
      )

      p <- p %...!% (function(e) {
        log_warn("[STREAM_CHAIN] Hata yakalandı: {conditionMessage(e)}")
        perf_tracker$track_error()

        request_state <- mergen_send_message_request_state(active_request_id, req_id, stop_generation)
        if (identical(request_state, "current")) {
          abort_send_message(message = "Beklenmeyen bir hata oluştu.", type = "error")
          return(invisible(NULL))
        }

        if (identical(request_state, "stopped")) {
          cleanup_send_message()
        }
        invisible(NULL)
      })

      promises::finally(p, onFinally = function() {
      })

    } else {
      # NON-STREAMING modu
      log_debug("[MONITORING] AI isteği başlatılıyor (NON-STREAMING modu)")
      generate_non_streaming_stoppable_fn(
        messages_to_process,
        current_settings,
        user_prompt_msg,
        chat_id_val,
        model_selected,
        last_user_text = user_message_text,
        current_user_id = effective_user_id
      )
    }

    invisible(NULL)
  }

  # Başlık üretici yardımcı fonksiyonu
  generate_title_from_prompt <- function(prompt, max_len = 60) {
    chat_generate_title_from_prompt(prompt, max_len)
  }

  # Fonksiyonları döndür
  list(
    send_message = send_message
  )
}

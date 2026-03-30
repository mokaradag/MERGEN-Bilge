# ==============================================================================
# Dosya Yolu: R/server_send_message.R
# Açıklama: Ana mesaj gönderme fonksiyonunu içerir. Kullanıcı mesajlarını işler,
#           araç ailesini belirler (özetleme, görsel, MCP Excel, SQL analizi),
#           LLM API çağrılarını yönetir ve yanıtları işler.
# ==============================================================================
 
# sendMessageInit: Mesaj gönderme fonksiyonunu oluşturur
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
    session_uid <- session$userData$user_id %||% NULL
    uid <- suppressWarnings(as.integer(session_uid %||% current_user_id %||% 0L))
    if (is.na(uid)) uid <- 0L
    uid
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
 
    # Hoş geldin ekranını tamamen temizle ve sohbet içeriğini göster
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
        if(window.WelcomePersonalGreeting && window.WelcomePersonalGreeting.destroy) {
          window.WelcomePersonalGreeting.destroy();
        }
      ")
      removeUI(selector = "#welcome_fullscreen_container > *", multiple = TRUE, immediate = TRUE)
    }
 
    # Performans izleme için istek başlangıç zamanını kaydet
    request_start_time <- Sys.time()
 
    # Hızlı istekleri engelle (debounce)
    if (values$is_sending) {
      showToast(session, "Lütfen önceki isteğin tamamlanmasını bekleyin.", "warning")
      return()
    }
 
    # Dosya özetleme modu kontrolü
    if (isTRUE(settings_data$enable_summarization_tools) &&
        length(isolate(session_files())) > 0 &&
        !is.null(prompt_text) && nzchar(trimws(as.character(prompt_text)))) {
 
      skip_mcp_once <- FALSE
      current_settings <- reactiveValuesToList(settings_data)
      current_settings$enable_summarization_tools <- TRUE
      current_settings$enable_rdata_tools <- FALSE
      current_settings$enable_mcp_tools <- FALSE
 
      handle_summarization_mode <- TRUE
    } else {
      handle_summarization_mode <- FALSE
    }
 
    # Son istek zamanı kontrolü (hızlı arka arkaya istekleri engelle)
    if (!is.null(values$last_request_time)) {
      time_since_last <- as.numeric(difftime(Sys.time(), values$last_request_time, units = "secs"))
      if (time_since_last < 1) {
        showToast(session, "Çok hızlı istek gönderiyorsunuz.", "warning")
        return()
      }
    }
    values$last_request_time <- Sys.time()
 
    # Hem nesne hem de string girişlerini işle
    if (is.list(prompt_text) && !is.null(prompt_text$text)) {
      prompt_text <- prompt_text$text
    }
 
    user_message_text <- trimws(prompt_text %||% "")
 
    fm_files <- file_manager_data$file_contents()
    uploaded_names <- if (length(fm_files)) vapply(fm_files, `[[`, "", "name") else character(0)
    uploaded_count <- length(uploaded_names)
 
    if (nchar(user_message_text) == 0 && uploaded_count == 0) {
      showToast(session, "Lütfen bir mesaj yazın.", "warning")
      return()
    }
 
    current_settings <- reactiveValuesToList(settings_data)
 
    cfg_excel_on <- isTRUE(settings_data$enable_mcp_tools)
    cfg_sql_analysis_on <- isTRUE(settings_data$enable_rdata_tools)
 
    skip_mcp_once <- isTRUE(quick_action_skip_mcp())
    if (skip_mcp_once) quick_action_skip_mcp(FALSE)
 
    excel_allowed <- cfg_excel_on && uploaded_count > 0
    cfg_summarization_on <- isTRUE(settings_data$enable_summarization_tools)
 
    # Araç ailesini belirle
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
      current_settings$max_output_tokens <- 4096
    } else if (isTRUE(settings_data$enable_process_tools)) {
      tool_family <- "process"
    } else if (isTRUE(settings_data$enable_app_expert_tools)) {
      tool_family <- "app_expert"
    } else if (isTRUE(settings_data$enable_image_tools)) {
      tool_family <- "image"
    } else {
      tool_family <- "none"
    }
 
    # Yeni sohbet oluştur (eğer mevcut sohbet yoksa)
    if (is.null(values$current_chat_id)) {
      title_prompt <- if (nchar(user_message_text) > 0) user_message_text else "Dosya Analizi"
      chat_title <- generate_title_from_prompt(title_prompt, max_len = 60)
      tryCatch({
        new_id <- create_new_chat_in_db(effective_user_id, initial_title = chat_title)
        values$current_chat_id <- new_id
        values$saved_chats <- load_chats_from_db(effective_user_id, include_messages = FALSE)
        saved_chats_data$refresh()
      }, error = function(e) {
        showToast(session, paste("Yeni sohbet oluşturulamadı:", e$message), "error")
        return()
      })
    }
 
    # Kullanıcı mesajını ekle
    display_text <- if (nchar(user_message_text) > 0) user_message_text else "Seçili dosyaların özeti istendi."
    user_prompt_msg <- add_message_fn(display_text, "user")
 
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
 
    # Durdur butonunu göster
    shinyjs::runjs("$('#send_stop_btn i').attr('class', 'fa-solid fa-stop');")
    shinyjs::runjs("$('#send_stop_btn').addClass('stop-mode');")
    shinyjs::runjs("$('#send_stop_btn').attr('title', 'Durdur');")
 
    values$is_sending <- TRUE
    stop_generation(FALSE)
 
    recent_messages <- tail(isolate(values$messages), 5)
    recent_messages <- Filter(function(m) {
      is.null(m$content) || !grepl("[ Toplam Dosya Sayısı:", m$content, fixed = TRUE)
    }, recent_messages)
 
    # Mevcut dosya durumunu al
    current_session_files <- isolate(session_files())
    uploaded_names <- if (length(current_session_files) > 0) names(current_session_files) else character(0)
    uploaded_count <- length(uploaded_names)
 
    log_debug("[FILE CONTEXT] Oturumdaki dosya sayısı: {uploaded_count} - {paste(uploaded_names, collapse = ', ')}")
 
    messages_to_process <- recent_messages
 
    # SQL Analizi modu işleme
    # Derin düşünme aktifse pk_deep_analysis_process(), değilse pk_analiz_process_request() kullanılır.
    # Her iki fonksiyon da RAG bağlamını hazırlar ve LLM mesajlarına enjekte eder;
    # sonuç karakter dizesiyse doğrudan AI mesajı olarak gösterilir.
    if (identical(tool_family, "sql_analysis")) {
       # Derin düşünme modu kontrolü
       deep_thinking_active <- isTRUE(settings_data$analysis_deep_thinking)
       analysis_detail <- settings_data$analysis_detail_level %||% "standart"

       if (deep_thinking_active) {
         log_debug("[SERVER] Derin Düşünme modu aktif. Detay: {analysis_detail}. Çoklu sorgu analizi başlatılıyor...")
       } else {
         log_debug("[SERVER] Proje ve Kaynak Analizi seçildi (tekil mod). Modül çağırılıyor...")
       }

       if (isTRUE(stop_generation())) {
         removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
         values$typing <- FALSE
         reset_chat_state_fn()
         return(invisible(NULL))
       }

       analiz_result <- tryCatch({
         if (deep_thinking_active) {
           # Derin düşünme: çoklu sorgu analizi
           pk_deep_analysis_process(
             user_message_text, messages_to_process, session,
             detail_level = analysis_detail,
             stop_check = stop_generation
           )
         } else {
           # Standart: tekil sorgu analizi
           pk_analiz_process_request(user_message_text, messages_to_process, session, stop_check = stop_generation)
         }
       }, error = function(e) {
         paste0("\U000026A0\U0000FE0F Analiz modülü hatası: ", e$message)
       })

       if (is.character(analiz_result)) {
         removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
         values$typing <- FALSE
         add_message_fn(analiz_result, "ai")
         reset_chat_state_fn()
         return()

       } else if (is.list(analiz_result)) {
         # Hata mesajı döndüyse
         if (identical(analiz_result$type, "error_message")) {
           removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
           values$typing <- FALSE
           add_message_fn(analiz_result$content, "ai")
           reset_chat_state_fn()
           return()
         }

         log_debug("[SERVER] SQL Analizi başarılı. Veriler LLM bağlamına ekleniyor... (Derin: {deep_thinking_active})")

         # Derin düşünme modunda max_tokens güncelle
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
 
    # SQL analizinde ikinci system mesajı üretme; mevcut system mesajı ile birleştir
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
 
    # DOSYA ÖZETLEME MODU - ayrı dosyaya taşındı (server_handler_summarization.R)
    if (identical(tool_family, "summarization")) {
      summarization_ctx <- list(
        session = session, input = input, values = values,
        settings_data = settings_data, ai_processor = ai_processor,
        uploaded_count = uploaded_count, user_message_text = user_message_text,
        current_session_files = current_session_files,
        add_message_fn = add_message_fn, reset_chat_state_fn = reset_chat_state_fn
      )
      handle_summarization_mode(summarization_ctx)
      return(invisible(NULL))

    # GÖRSEL OLUŞTURMA MODU - ayrı dosyaya taşındı (server_handler_image_generation.R)
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
      # MCP kapalı -> seçili dosyaların özetini/alıntısını doğrudan bağlama ekle
      file_blocks <- character(0)
      total_budget <- 120000
      per_file_cap <- max(4000, floor(total_budget / max(1, uploaded_count)))
 
      for (fname in uploaded_names) {
        sumtxt <- session$userData$file_summaries[[fname]] %||% ""
        if (!is.character(sumtxt) || !nzchar(sumtxt[1])) {
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
      Sys.sleep(0.1)
    }
 
    # Model seçimini al
    model_selected <- current_settings$model_selection
 
    # MCP snapshot hazırla
    mcp_snapshot <- session$userData$mcp_registry_snapshot %||% (session$userData$current_session_files %||% list())
 
    current_settings$current_user_id <- effective_user_id
    current_settings$mcp_registry_snapshot <- mcp_snapshot
 
    current_settings$tool_family <- tool_family
 
    # Yalnızca gerçek MCP araç çağrısı (Excel analizi) için MCP aktif edilir.
    # process, coding, app_expert, sql_analysis gibi araçlar streaming yolunu kullanmalıdır;
    # aksi hâlde call_llm_worker() devreye girer ve API kaynak meta verilerini işleyemez,
    # bu da Kaynakça bölümündeki tıklanabilir linklerin kaybolmasına neden olur.
    current_settings$enable_mcp_tools <- identical(tool_family, "mcp_excel")
 
    current_settings$temperature     <- temperature_value
    current_settings$uploaded_files  <- uploaded_names
    current_settings$shiny_session   <- session
 
    log_debug("[MODE] Araç ailesi: {tool_family}, SQL Analizi: {cfg_sql_analysis_on}, Excel MCP: {cfg_excel_on}")
 
    if (!is.null(session$userData$current_session_files) && length(session$userData$current_session_files) > 0) {
      log_debug("[MCP] Mevcut dosya sayısı: {length(session$userData$current_session_files)}")
 
      if (!is.null(session$userData$current_session_files)) {
        for (key in names(session$userData$current_session_files)) {
          obj <- session$userData$current_session_files[[key]]
          log_debug("[MCP] Anahtar: {key} | Ad: {obj$name %||% '?'} | Yol: {obj$path %||% obj$datapath %||% '?'}")
        }
      }
 
      for (fname in names(session$userData$current_session_files)) {
            fobj <- session$userData$current_session_files[[fname]]
            if (is.list(fobj)) {
              fpath <- fobj$datapath %||% fobj$path
              log_debug("[MCP] {fname} -> {fpath} (mevcut: {path_exists_relaxed(fpath)})")
            }
      }
    } else {
      log_debug("[MCP] Oturumda dosya yok \U2014 MCP çalışmayacak")
    }
 
    # Excel modunda dosyaları MCP tabanına kopyala
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
          resolved <- try(resolve_uploaded_file(fname, effective_user_id), silent = TRUE)
          if (!inherits(resolved, "try-error") && nzchar(resolved) && path_exists_relaxed(resolved)) {
                path_now <- resolved
          }
        }
 
        if (is.null(path_now) || !nzchar(path_now) || !path_exists_relaxed(path_now)) {
          log_debug("[FILE STORE] {fname} için yol bulunamadı \U2014 atlanıyor")
          next
        }
 
        path_now <- tryCatch(normalizePath(path_now, winslash = "/", mustWork = TRUE), error = function(e) path_now)
        path_now <- safe_windows_short_path(path_now, must_exist = path_exists_relaxed(path_now))
 
        path_original <- path_now
        tryCatch({
          if (!is_under_mcp_base(path_now) && isTRUE(current_settings$enable_mcp_tools)) {
                        copied <- copy_to_mcp_base(list(name = fname, datapath = path_now), effective_user_id)
                        if (nzchar(copied) && path_exists_relaxed(copied)) path_now <- copied
          }
        }, error = function(e) {
          log_warn("[FILE STORE] copy_to_mcp_base başarısız: {e$message}")
        })
 
        cached_path <- cache_mcp_file_locally_fn(path_now)
        if (is.null(cached_path) || !nzchar(cached_path)) {
          cached_path <- path_now
        } else if (!identical(cached_path, path_now)) {
          log_debug("[FILE STORE] Yerel MCP önbelleği hazırlandı: {cached_path}")
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
      mcp_snapshot <- update_mcp_registry_snapshot_fn(csf)
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
        log_debug("[FILE STORE] MCP dosyaları (seçili): {paste(unique_names[nzchar(unique_names)], collapse = ', ')}")
      } else {
        log_debug("[FILE STORE] Filtreleme sonrasında geçerli MCP dosyası yok")
      }
    } else {
      session$userData$current_session_files <- list()
      mcp_snapshot <- update_mcp_registry_snapshot_fn(list())
    }
 
    if (!exists("mcp_snapshot", inherits = FALSE)) {
      mcp_snapshot <- update_mcp_registry_snapshot_fn()
    }

    # Dosya yeniden inşası sonrası snapshot'ı current_settings'e yansıt
    # (İlk atama satır 545'te yapılıyor ama mcp_excel rebuild sonrası güncellenmiyordu)
    current_settings$mcp_registry_snapshot <- mcp_snapshot

    # Dosya yollarını Excel modunda ilet
    current_settings$file_paths <- list()
    if (identical(tool_family, "mcp_excel") && length(uploaded_names) > 0) {
      registry_paths <- session$userData$current_session_files %||% list()
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

    log_debug("Mesaj gönderiliyor, model: {model_selected}")
    if (isTRUE(force_non_streaming_sql)) {
      log_debug("[MONITORING] SQL analizi için düşünmeli model tespit edildi; streaming kapatılıp non-streaming kullanılacak")
    }

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
        add_message_fn = add_message_fn,
        reset_chat_state_fn = reset_chat_state_fn,
        followup_tools = followup_tools,
        fallback_followup_tool = fallback_followup_tool
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

      req_id <- paste0("req_", format(Sys.time(), "%Y%m%d%H%M%OS3"), "_", sample(1000:9999, 1))
      active_request_id(req_id)
      stop_generation(FALSE)
      values$is_sending <- TRUE

      safe_settings <- current_settings; safe_settings$shiny_session <- NULL
      dbg_dump("LLM_REQUEST_STREAMING", list(model = model_selected, messages = messages_to_process, settings = safe_settings))

      p <- ai_processor$call_llm_streaming(messages_to_process, current_settings, model_selected)

      p <- promises::then(p, onFulfilled = function(result) {
        result$req_id <- req_id
        result
      })

      p <- promises::then(
        p,
        onFulfilled = function(res) {
          if (!res$success) {
            log_warn("[AI MODULE] Streaming isteği başarısız")
            perf_tracker$track_error()
            removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
            values$typing <- FALSE
            showToast(session, res$error, "error")
            reset_chat_state_fn()
            return(invisible(NULL))
          }

          log_debug("[MONITORING] Streaming isteği tamamlandı")
          dbg_dump("LLM_RESPONSE_STREAMING", list(
            success = res$success, duration = res$duration,
            content_preview = substr(res$content %||% "", 1, 800)
          ))

          perf_tracker$track_request(res$duration)

          if (isTRUE(stop_generation()) || !identical(active_request_id(), res$req_id)) {
            try(log_ai_usage(chat_id_val, user_prompt_msg$db_id, effective_user_id,
                             model_selected, res$duration, FALSE), silent = TRUE)
            removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
            values$typing <- FALSE
            reset_chat_state_fn()
            return(invisible(NULL))
          }

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
          removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
          values$typing <- FALSE

          duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
          try(log_ai_usage(chat_id_val, user_prompt_msg$db_id, effective_user_id,
                           model_selected, duration, FALSE), silent = TRUE)

          if (!isTRUE(stop_generation())) {
            msg <- as.character(conditionMessage(err))
            msg <- sub("^[A-Z_]+:\\s*", "", msg)
            if (!nzchar(msg)) msg <- "Beklenmeyen bir hata oluştu."
            showToast(session, msg, "error")
          }
          reset_chat_state_fn()
          invisible(NULL)
        }
      )

      p <- p %...!% (function(e) {
        log_warn("[STREAM_CHAIN] Hata yakalandı: {conditionMessage(e)}")
        perf_tracker$track_error()
        removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
        values$typing <- FALSE
        if (!isTRUE(stop_generation())) {
          showToast(session, "Beklenmeyen bir hata oluştu.", "error")
        }
        reset_chat_state_fn()
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
        last_user_text = user_message_text
      )
    }
 
    invisible(NULL)
  }
 
  # generate_title_from_prompt yardımcı fonksiyonu
  generate_title_from_prompt <- function(prompt, max_len = 60) {
    chat_generate_title_from_prompt(prompt, max_len)
  }
 
  # Fonksiyonları döndür
  list(
    send_message = send_message
  )
}
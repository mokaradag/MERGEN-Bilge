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
 
  # Ana mesaj gönderme fonksiyonu
  send_message <- function(prompt_text, is_summarization_request = FALSE) {
 
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
        new_id <- create_new_chat_in_db(current_user_id, initial_title = chat_title)
        values$current_chat_id <- new_id
        values$saved_chats <- load_chats_from_db(current_user_id, include_messages = FALSE)
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
 
    cat(sprintf("[FILE CONTEXT] Current files in session: %d - %s\n",
                uploaded_count,
                paste(uploaded_names, collapse = ", ")))
 
    messages_to_process <- recent_messages
 
    # SQL Analizi modu işleme
    if (identical(tool_family, "sql_analysis")) {
       cat("[SERVER] 'Proje ve Kaynak Analizi' secildi. Modul cagiriliyor...\n")
 
       if (isTRUE(stop_generation())) {
         removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
         values$typing <- FALSE
         reset_chat_state_fn()
         return(invisible(NULL))
       }
 
       analiz_result <- tryCatch({
         pk_analiz_process_request(user_message_text, messages_to_process, session, stop_check = stop_generation)
       }, error = function(e) {
         paste0("⚠️ Analiz modülü hatası: ", e$message)
       })
 
       if (is.character(analiz_result)) {
         removeUI(selector = "#typing-animation-wrapper")
         values$typing <- FALSE
 
         add_message_fn(analiz_result, "ai")
         return()
 
       } else if (is.list(analiz_result)) {
         cat("[SERVER] SQL Analizi basarili. Veriler LLM baglamina ekleniyor...\n")
 
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
 
    # Sistem talimatını ekle
    system_msg <- list(type = "system", content = style_instruction)
    messages_to_process <- c(list(system_msg), messages_to_process)
 
    cat(sprintf("[STYLE] Using character: %s (temp: %.2f)\n", selected_char_id, temperature_value))
 
    # DOSYA ÖZETLEME MODU
    if (identical(tool_family, "summarization")) {
 
      if (uploaded_count == 0) {
        removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
        values$typing <- FALSE
        values$is_sending <- FALSE
        showToast(session, "Lütfen önce Dosya Yönetimi sayfasından dosya yükleyin ve 'Model Bağlamı' seçin.", "info")
        return(invisible(NULL))
      }
 
      cat("[SUMMARIZATION] Dosya Özetleme modu aktif, özetleme başlatılıyor. Dosya sayısı:", uploaded_count, "\n")
 
      if (!exists("process_summarization_request", mode = "function")) {
        source("R/module_summarization.R", encoding = "UTF-8", local = TRUE)
      }
 
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
 
      if (nchar(user_message_text) > 0) {
        current_session_files$user_query <- user_message_text
        cat("[SUMMARIZATION] Kullanıcı sorgusu özetlemeye eklendi:", user_message_text, "\n")
      }
 
      summary_detail <- input$chat_summary_detail %||% settings_data$summary_detail_level %||% "standard"
      summary_focus <- input$chat_summary_focus %||% settings_data$summary_focus_mode %||% "general"

      if (identical(summary_focus, "comparison") && uploaded_count == 1) {
        summary_focus <- "general"
        showToast(session, "Karşılaştırma modu için birden fazla dosya gereklidir. Genel moda geçildi.", "warning")
        session$sendCustomMessage("syncSummarySettingsToChat", list(
          detail_level = summary_detail,
          focus_mode = "general"
        ))
        session$sendCustomMessage("syncChatSummarySettingsToSettings", list(
          detail_level = summary_detail,
          focus_mode = "general"
        ))
        cat("[SUMMARIZATION] Tek dosya ile karşılaştırma modu seçildi, genel moda geçildi\n")
      }

      cat("[SUMMARIZATION] Mod parametreleri - Detay:", summary_detail, "Odak:", summary_focus, "\n")

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
        },
        detail_level = summary_detail,
        focus_mode = summary_focus
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
 
          add_message_fn(result$summary, "ai")
 
          showToast(session, paste(result$file_count, "dosya başarıyla özetlendi."), "success")
 
          reset_chat_state_fn()
        },
        onRejected = function(err) {
          removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
          values$typing <- FALSE
          showToast(session, paste("Özetleme hatası:", conditionMessage(err)), "error")
          reset_chat_state_fn()
        }
      )
 
      return(invisible(NULL))
 
    } else if (identical(tool_family, "image")) {
      # GÖRSEL OLUŞTURMA MODU - DALL-E-3 API
      cat("[IMAGE_MODE] Görsel Uzmanı modu aktif - görsel oluşturma başlatılıyor\n")
 
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
 
      api_key_for_image <- tryCatch(as.character(session$userData$ai_api_key)[1], error = function(e) "")
 
      if (!nzchar(api_key_for_image)) {
        removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
        values$typing <- FALSE
        add_message_fn("⚠️ Görsel oluşturmak için API anahtarı gerekli. Lütfen Ayarlar sayfasından API anahtarınızı girin.", "ai")
        reset_chat_state_fn()
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
        removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
        values$typing <- FALSE
 
        if (isTRUE(result$success)) {
          image_html <- render_generated_image_html(result, paste0("img_", floor(as.numeric(Sys.time()) * 1000)))
 
          image_description <- result$revised_prompt %||% "[Görsel oluşturuldu]"
          image_path_marker <- if (!is.null(result$local_path) && nzchar(result$local_path)) {
            paste0("[GÖRSEL:", result$local_path, "]")
          } else {
            "[GÖRSEL]"
          }
          content_text <- paste0(image_path_marker, " ", image_description)
 
          add_message_fn(content_text, "ai", html = image_html)
          showToast(session, "Görsel oluşturuldu!", "success")
        } else {
          error_msg <- result$error %||% "Görsel oluşturulamadı"
          error_html <- render_generated_image_html(result, "error")
          add_message_fn(paste0("❌ ", error_msg), "ai", html = error_html)
          showToast(session, error_msg, "error")
        }
 
        reset_chat_state_fn()
      }) %...!% (function(err) {
        removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
        values$typing <- FALSE
        add_message_fn(paste0("❌ Görsel oluşturma hatası: ", err$message), "ai")
        showToast(session, paste("Hata:", err$message), "error")
        reset_chat_state_fn()
      })
 
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
      # MCP kapalı → seçili dosyaların özetini/alıntısını doğrudan bağlama ekle
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
 
    current_settings$current_user_id <- current_user_id
    current_settings$mcp_registry_snapshot <- mcp_snapshot
 
    current_settings$tool_family <- tool_family
 
    current_settings$enable_mcp_tools <- !identical(tool_family, "none")
 
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
 
        cached_path <- cache_mcp_file_locally_fn(path_now)
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
        cat("[FILE STORE] MCP files (selected): ", paste(unique_names[nzchar(unique_names)], collapse = ", "), "\n", sep = "")
      } else {
        cat("[FILE STORE] No valid MCP files after filtering.\n")
      }
    } else {
      session$userData$current_session_files <- list()
      mcp_snapshot <- update_mcp_registry_snapshot_fn(list())
    }
 
    if (!exists("mcp_snapshot", inherits = FALSE)) {
      mcp_snapshot <- update_mcp_registry_snapshot_fn()
    }
 
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
        cat("[FILE PATH ADDED]", fname, "->", full_path, "\n")
      }
    }
 
    # Model seçilmemişse varsayılanı kullan
    if (is.null(model_selected) || model_selected == "") {
      model_selected <- api_config$local_models[1]
    }
 
    print(paste("Send message using model:", model_selected))
 
    # LLM çağrısı: Streaming veya Non-streaming
    if (isTRUE(current_settings$enable_streaming) && !isTRUE(current_settings$enable_mcp_tools)) {
      # STREAMING modu
      start_time <- Sys.time()
 
      cat("[MONITORING] Starting AI request (STREAMING mode)\n")
 
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
            cat("[AI MODULE] Streaming request failed\n")
            perf_tracker$track_error()
            removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
            values$typing <- FALSE
            showToast(session, res$error, "error")
            reset_chat_state_fn()
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
            reset_chat_state_fn()
            return(invisible(NULL))
          }
 
          try(log_ai_usage(chat_id_val, user_prompt_msg$db_id, current_user_id,
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
          reset_chat_state_fn()
          invisible(NULL)
        }
      )
 
      p <- p %...!% (function(e) {
        cat("[STREAM_CHAIN][CATCH] ", conditionMessage(e), "\n", sep = "")
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
      cat("[MONITORING] Starting AI request (NON-STREAMING mode)\n")
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
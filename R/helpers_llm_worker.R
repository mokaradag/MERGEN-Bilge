# ==============================================================================
# Dosya Yolu: R/helpers_llm_worker.R
# Açıklama:   MCP araç destekli LLM işçi fonksiyonu (call_llm_worker).
#             Araç şeması çözümleme, API isteği, araç çağrısı yürütme,
#             grafik spesifikasyonu toplama, ikinci geçiş (second pass) mantığı
#             ve hata yönetimi bu dosyada yer alır.
#             global.R tarafından helpers_llm_api.R'den sonra source() ile çağrılır.
# ==============================================================================

# --- MCP ARAÇ ÇAĞRISI İÇİN MAKSİMUM ÖZYINELEME DERİNLİĞİ ---
MAX_MCP_RECURSION <- 4

# Paylaşılan LLM işçi fonksiyonu (MCP desteği ile)
call_llm_worker <- function(chat_history, settings, api_endpoint, api_key = NULL, enable_tools = NULL, recursion_depth = 0) {
  worker_start_time <- Sys.time()      # İşlem süresi takibi için başlangıç zamanı

  # Sonsuz döngüyü önlemek için derinlik kontrolü
  if (recursion_depth > 5) {
    mergen_debug_cat("[MCP] Maksimum özyineleme derinliğine ulaşıldı\n")
    enable_tools <- FALSE
  }
  
  # Araçların etkinleştirilip etkinleştirilmeyeceğini kontrol et
  if (is.null(enable_tools)) {
    enable_tools <- settings$enable_mcp_tools %||% FALSE
  }
  
  # mcp_excel seçiliyse araçları her durumda zorla
    if (identical(settings$tool_family, "mcp_excel")) {
      enable_tools <- TRUE
    }
  
  mergen_debug_cat("[LLM CALL] tool_family=", settings$tool_family %||% "NULL", " enable_tools=", enable_tools, "\n", sep="")
  
  tryCatch({
    selected_model <- settings$model_selection %||% "mergen-local-model"
    
    # OpenAI araç şemasını çağrı başına bir kez çözümle
    session_obj <- settings$shiny_session %||% NULL
    registry_snapshot <- settings$mcp_registry_snapshot %||% NULL
    
    if (!is.null(registry_snapshot)) {
      needs_stub <- is.null(session_obj) ||
        is.null(session_obj$userData) ||
        is.null(session_obj$userData$current_session_files) ||
        length(session_obj$userData$current_session_files) == 0
      
      # Oturum nesnesi yoksa veya dosya listesi boşsa, kayıt defteri anlık görüntüsünden geçici oturum oluştur
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
  # Seçilen aileye göre temel araç listesini al
  if (isTRUE(enable_tools) && identical(tool_family, "mcp_excel")) {
    if (exists("helpers_mcp_tools", inherits = TRUE) &&
      is.function(helpers_mcp_tools$get_openai_tools)) {
    base_tools <- helpers_mcp_tools$get_openai_tools(session_obj)
    }
  }

  mcp_spec <- base_tools

  # Bayrağı bir kez tanımla ve her yerde kullan
  mcp_enabled_now <- isTRUE(enable_tools) &&
             is.list(mcp_spec$tools) &&
             length(mcp_spec$tools) > 0

  # --- DEFANSİF YAMA: parameters.required alanının her zaman JSON dizisi olduğundan emin ol ---
  if (mcp_enabled_now) {
    mcp_spec$tools <- lapply(mcp_spec$tools, function(tdef) {
    if (!is.null(tdef$`function`) && !is.null(tdef$`function`$parameters)) {
      req <- tdef$`function`$parameters$required
      # Bazı sunucular bunu string olarak serileştiriyor; diziye normalize et
      if (is.character(req) && length(req) == 1) {
      tdef$`function`$parameters$required <- list(req)
      }
    }
    tdef
    })
  }

    mergen_debug_cat("\n========================================\n")
    mergen_debug_cat("[LLM CALL] Model:", selected_model, "\n")
    mergen_debug_cat("[LLM CALL] MCP Enabled:", if (mcp_enabled_now) "TRUE" else "FALSE", "\n")
    mergen_debug_cat("[LLM CALL] Recursion depth:", recursion_depth, "\n")
    mergen_debug_cat("========================================\n")
    
    # Sohbet geçmişini API formatına (role/content) dönüştür
    messages_payload <- llm_worker_chat_history_to_messages(chat_history)
  
  # --- Grafik niyeti algılayıcı + zorunlu yedek oluşturucu --------------------
  # Metin içinde grafik isteği türünü (bar, line, vb.) algıla
  detect_chart_type_from_text <- llm_worker_detect_chart_type_from_text
  chart_intent_flag <- llm_worker_has_chart_intent(chat_history)
  
  # Grafiklerin toplanacağı depo (erken başlat)
  charts_to_store <- list()

  # Fallback mekanizması devre dışı; model tam sayı üretmeli
  # Otomatik ekleme kaldırıldı çünkü:
  # 1) 1 grafik isteğine 3 grafik dönüyordu
  # 2) Yanlış eksen seçimleri
  # 3) İstenmeyen grafik kombinasyonları
  add_fallback_chart <- llm_worker_add_fallback_chart
    
  # --- Seçilen aileye göre araç yönergesi (prompt) enjekte et ---
  if (isTRUE(enable_tools)) {
    tool_prompt <- NULL

    if (identical(tool_family, "mcp_excel") &&
      exists("helpers_mcp_tools", inherits = TRUE) &&
      is.function(helpers_mcp_tools$get_mcp_tools_prompt)) {

      # Dosya şemasını oturumdan çıkar ve sistem mesajına ekle
      file_schema <- NULL
      try({
      if (!is.null(session_obj) && !is.null(session_obj$userData$current_session_files)) {
        # Session'daki ilk dosyanın şemasını al
        files <- session_obj$userData$current_session_files
        if (length(files) > 0) {
        first_file <- files[[1]]
        file_name <- first_file$name %||% names(files)[1]
        if (!is.null(file_name) && nzchar(file_name)) {
          mergen_debug_cat("[MCP_SCHEMA] Dosya şeması çıkarılıyor: ", file_name, "\n")
          file_schema <- helpers_mcp_tools$extract_mcp_file_schema(file_name, session_obj)
          if (!is.null(file_schema)) {
          mergen_debug_cat("[MCP_SCHEMA] Şema başarıyla çıkarıldı (", nchar(file_schema), " karakter)\n")
          }
        }
        }
      }
      }, silent = TRUE)

      # Dosya şemasını prompt'a dahil et
      tool_prompt <- paste0(
      helpers_mcp_tools$get_mcp_tools_prompt(file_schema),
      "\n\n### EK BİLGİ:",
      "\n- SQL sorguları için: sql_query_uploaded_file (tablo adı: t)",
      "\n- Dosya özeti için: analyze_uploaded_file (opsiyonel)",
      "\n"
      )

      # Araç yönergesini (prompt) sistem mesajı olarak en başa ekle
      if (!is.null(tool_prompt) && nzchar(tool_prompt)) {
      mergen_debug_cat("[MCP] Tool prompt ekleniyor (", nchar(tool_prompt), " karakter)\n", sep = "")
      tool_system_msg <- list(role = "system", content = tool_prompt)
      messages_payload <- c(list(tool_system_msg), messages_payload)
      }
    }
  }

    messages_payload <- llm_worker_merge_system_messages_to_front(messages_payload)

    temp_value <- if (!is.null(settings$temperature)) settings$temperature else 0.4
    # Varsayilan cikti token limiti yuksek tutulur; uzun kod bloklari/yanitlar
    # kesilmesin (bkz. helpers_llm_api.R / helpers_llm_sse.R ile aynı sözleşme).
    # Onceden bu worker yolu max_tokens'i hic serilestirmiyordu; SQL analizi/
    # Kodlama Uzmani gibi araclarin ayarladigi yuksek limit (32768) uc noktaya
    # hic ulasmiyor, varsayilan (genelde dusuk) limitte kaliyordu (issue #7).
    # MERGEN_MAX_OUTPUT_TOKENS ile ayarlanabilir; worker-guvenli base cagrilar.
    max_tokens_val <- settings$max_output_tokens
    if (is.null(max_tokens_val)) {
      max_tokens_val <- suppressWarnings(as.integer(Sys.getenv("MERGEN_MAX_OUTPUT_TOKENS", "")))
      if (is.na(max_tokens_val) || max_tokens_val < 256L) max_tokens_val <- 32768L
    }

	body <- list(
	  model = selected_model,
	  messages = messages_payload,
	  stream = FALSE,
	  max_tokens = max_tokens_val
	)

	if (!should_omit_temperature(selected_model)) {
	  body$temperature <- temp_value
	}

	# Model bazlı ek istek alanlarını uygula.
	# Streaming dışı yollarda da thinking davranışı tutarlı kalsın.
	if (exists("apply_model_request_overrides", mode = "function", inherits = TRUE)) {
	  body <- apply_model_request_overrides(body, selected_model)
	}

    # Tüm uç noktalar OpenAI uyumlu kabul edilir; araç şemasını ekle
    if (mcp_enabled_now) {
    # DISABLE_TOOL_SCHEMA=TRUE ile şema gönderimi istisnai olarak kapatılabilir
    attach_tool_schema <- !isTRUE(as.logical(Sys.getenv("DISABLE_TOOL_SCHEMA", "FALSE")))

    mergen_debug_cat("[TOOLS] attach_tool_schema=", attach_tool_schema, " (family=", tool_family, ")\n", sep = "")

    if (attach_tool_schema) {
      body$tools <- mcp_spec$tools
      body$tool_choice <- "auto"
    }
    }
    
    hdrs <- list(`Content-Type` = "application/json")
    if (!is.null(api_key) && nzchar(api_key)) {
      hdrs$Authorization <- paste("Bearer", api_key)
    }

    log_info(sprintf(
      "[LLM REQUEST FINAL] path=worker tool_family=%s stream=%s payload_model=%s endpoint=%s",
      tool_family %||% "none",
      as.character(body$stream %||% NA),
      as.character(body$model %||% ""),
      api_endpoint
    ))
    
  # İstek zaman aşımı yapılandırılabilir (worker-güvenli env). Yoğunluk altında
  # araç/ikinci-geçiş çağrıları uzun sürebildiği için varsayılan 1800 sn.
  worker_timeout_sec <- suppressWarnings(as.numeric(Sys.getenv("MERGEN_LLM_TIMEOUT_SEC", "1800")))
  if (is.na(worker_timeout_sec) || worker_timeout_sec <= 0) worker_timeout_sec <- 1800

  response <- httr::POST(
    api_endpoint,
    do.call(httr::add_headers, hdrs),
    body = jsonlite::toJSON(body, auto_unbox = TRUE),
    encode = "raw",
    httr::timeout(worker_timeout_sec)
  )

  status <- httr::status_code(response)

  if (status != 200) {
    resp_txt_raw <- try(httr::content(response, "text", encoding = "UTF-8"), silent = TRUE)
    resp_txt <- if (!inherits(resp_txt_raw, "try-error") && is.character(resp_txt_raw) && length(resp_txt_raw) > 0) resp_txt_raw[[1]] else ""

    # Ollama 'tools' desteklemiyorsa (400 hatası), şemasız tekrar dene
    if (status == 400 && mcp_enabled_now && isTRUE(attach_tool_schema) &&
      grepl("does not support tools|tool", tolower(resp_txt))) {
    mergen_debug_cat("[RETRY] 400 & tools not supported -> retrying without tool schema...\n")
    body$tools <- NULL
    body$tool_choice <- NULL

    log_info(sprintf(
      "[LLM REQUEST FINAL] path=worker_retry_no_tools tool_family=%s stream=%s payload_model=%s endpoint=%s",
      tool_family %||% "none",
      as.character(body$stream %||% NA),
      as.character(body$model %||% ""),
      api_endpoint
    ))

    response <- httr::POST(
      api_endpoint,
      do.call(httr::add_headers, hdrs),
      body = jsonlite::toJSON(body, auto_unbox = TRUE),
      encode = "raw",
      httr::timeout(worker_timeout_sec)
    )
    status <- httr::status_code(response)
    resp_txt_raw <- try(httr::content(response, "text", encoding = "UTF-8"), silent = TRUE)
    resp_txt <- if (!inherits(resp_txt_raw, "try-error") && is.character(resp_txt_raw) && length(resp_txt_raw) > 0) resp_txt_raw[[1]] else ""
    }

    # HTTP durum kodlarına göre hata fırlat
    if (status != 200) {
    msg_tail <- if (nzchar(resp_txt)) paste0(" \U2014 ", substr(resp_txt, 1, 500)) else ""
    if (status == 429)      stop("RATE_LIMIT: Çok fazla istek gönderildi.", call. = FALSE)
    else if (status %in% c(401,403)) stop("AUTH_ERROR: Kimlik doğrulama hatası.", call. = FALSE)
    else if (status >= 500) stop(sprintf("SERVER_ERROR: Sunucu hatası (Kod: %d)%s", status, msg_tail), call. = FALSE)
    else                    stop(sprintf("API_ERROR: API hatası (Kod: %d)%s", status, msg_tail), call. = FALSE)
    }
  }
    
    response_content <- httr::content(response, "parsed")
    
    ayristirilmis_yanit <- extract_llm_content_and_sources(
      response_content,
      model_id = selected_model
    )

    ai_content <- ayristirilmis_yanit$content
    tool_calls_struct <- NULL
    
    if (is.list(response_content) &&
        !is.null(response_content$choices) &&
        length(response_content$choices) > 0) {
      first_choice <- response_content$choices[[1]]
      if (is.list(first_choice) && !is.null(first_choice$message)) {
        if (!is.null(first_choice$message$tool_calls) &&
            length(first_choice$message$tool_calls) > 0) {
          tool_calls_struct <- first_choice$message$tool_calls
        }
      }
    }
    
  # İçerik veya yapısal araç çağrısı yoksa hata ver
  has_content <- is.character(ai_content) && length(ai_content) > 0 && nzchar(ai_content[1])
  if (!has_content && (is.null(tool_calls_struct) || length(tool_calls_struct) == 0)) {
    stop("EMPTY_RESPONSE: AI'dan geçerli bir yanıt alınamadı.")
  }
    
  mergen_debug_cat("[RESPONSE] Content length:", if (has_content) nchar(ai_content[1]) else 0, "chars\n")
  mergen_debug_cat("[RESPONSE] Preview:", if (has_content) substr(ai_content[1], 1, 200) else "", "...\n")
    
    # MCP etkinse araç çağrılarını çözümle
    if (enable_tools) {
      tool_calls <- list()
    
    if (!is.null(tool_calls_struct) && length(tool_calls_struct) > 0) {
        mergen_debug_cat("[MCP] Structured tool_calls detected from API:", length(tool_calls_struct), "\n")
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
        # Metin tabanlı araç çağrılarını çözümle (eski yöntem)
        tool_calls <- helpers_mcp_tools$parse_tool_calls_from_text(ai_content %||% "")
      }
    
      # Araç çağrısı yoksa ve mcp_excel ise varsayılan davranışı dene
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
        mergen_debug_cat("\n========================================\n")
        mergen_debug_cat("[MCP SUCCESS] Parsed", length(tool_calls), "tool call(s)\n")
        mergen_debug_cat("========================================\n")
    
        # Çözümleyiciler için oturum nesnesini al.
        # session_obj, üstte mcp_registry_snapshot ile güvenli şekilde
        # oluşturulmuş olabilir; async worker içinde tekrar canlı
        # settings$shiny_session'a dönmek snapshot korumasını boşa çıkarır.
        current_session <- session_obj
    
    mergen_debug_cat("[MCP] Executing tools...\n")

    exec_fun <- NULL

    if (identical(tool_family, "mcp_excel") &&
      exists("helpers_mcp_tools", inherits = TRUE) &&
      is.function(helpers_mcp_tools$execute_parsed_tool)) {

      exec_fun <- function(tc) {
      mergen_debug_cat("[MCP] Executing (Excel):", tc$function_name, "\n")
      helpers_mcp_tools$execute_parsed_tool(tc, session = current_session)
      }

    } else {
      exec_fun <- function(tc) {
      list(error = "Uygun araç yürütücüsü bulunamadı (MCP seçimi kontrol edin).")
      }
    }

    mergen_debug_cat("[MCP] tool_calls parsed (names):", paste(vapply(tool_calls, function(t) t$function_name %||% "", ""), collapse = ", "), "\n")
    # Ayrıştırılan araçları sırayla çalıştır
    tool_results_raw <- lapply(tool_calls, exec_fun)
    
    # --- YENİ: Grafik spesifikasyonlarını topla ve bloğa dönüştür ---
    # ÖNEMLİ: İşçi fonksiyonundayız, Shiny oturumuna doğrudan dokunma
    chart_blocks_text <- ""
    try({
        # __mcp_plot şartını kaldır - chart alanı olan tüm sonuçlar geçerlidir
        chart_specs <- Filter(function(x) is.list(x) && !is.null(x[["chart"]]), tool_results_raw)
      if (length(chart_specs)) {

      parts <- vapply(seq_along(chart_specs), function(i) {
        cs <- chart_specs[[i]]
        full <- cs$chart

        # unique ref id
        ref_id <- paste0(
          "cl_", format(Sys.time(), "%Y%m%d%H%M%OS3"), "_", sprintf("%04d", sample(0:9999, 1))
        )

        # Tüm spesifikasyonu grafik deposuna kaydet (geriye dönük uyumluluk için)
        charts_to_store[[ref_id]] <<- full

        # ÖNEMLİ: Veriyi inline olarak tut
        inline <- full
        inline$ref <- ref_id  # ref ekle ama veriyi atma

        jsonlite::toJSON(inline, auto_unbox = TRUE, null = "null", digits = 12)
      }, character(1))

      chart_blocks_text <- paste0(
        paste0("\n\n```chartlab\n", parts, "\n```"),
        collapse = ""
      )
      }
    }, silent = TRUE)

    # Grafik verisinden otomatik özet/içgörü metni oluştur
    build_chart_summary <- llm_worker_build_chart_summary

    # Sonuçlardan (tablo/grafik) hızlı içgörü üret
    build_auto_insight <- llm_worker_build_auto_insight
            
        # Herhangi bir araç hata döndürdüyse toparla ve işlemi kes
        errs <- vapply(tool_results_raw, function(r) if (is.list(r) && !is.null(r$error)) r$error else "", "")
        if (any(nzchar(errs))) {
          err_text <- paste(errs[nzchar(errs)], collapse = "\n")
      return(list(
        content  = paste("Araç hatası:\n", err_text),
        duration = as.numeric(difftime(Sys.time(), worker_start_time, units = "secs")),
        chart_store = charts_to_store
      ))
        }
    
        formatted_tool_results <- llm_worker_format_tool_results_for_prompt(
          tool_calls = tool_calls,
          tool_results_raw = tool_results_raw,
          chart_summary_fn = build_chart_summary
        )

        tool_results <- formatted_tool_results$tool_results
        results_text <- formatted_tool_results$results_text
    
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
        
        # Tam sonuç metnini log'a yaz (LLM'e ne gönderildiğini görmek için)
        mergen_debug_cat("\n========== LLM'E GÖNDERİLEN TAM SONUÇ METNİ ==========\n")
        mergen_debug_cat(results_text, "\n")
        mergen_debug_cat("========================================\n\n")
    
    # Chat history'nin son elemanını (AI'a gönderilecek mesajı) detaylı logla
        mergen_debug_cat("\n+===========================================================+\n")
        mergen_debug_cat("|  [GLOBAL] AI'A GÖNDERİLECEK MESAJIN SON HALİ              |\n")
        mergen_debug_cat("+===========================================================+\n\n")
        
        last_msg <- chat_history[[length(chat_history)]]
        mergen_debug_cat("[GLOBAL] Son mesaj role:", last_msg$role, "\n")
        mergen_debug_cat("[GLOBAL] Son mesaj uzunluğu:", nchar(last_msg$content), "karakter\n")
        mergen_debug_cat("\n[GLOBAL] SON MESAJIN TAM İÇERİĞİ:\n")
        mergen_debug_cat("============================================================\n")
        mergen_debug_cat(last_msg$content)
        mergen_debug_cat("\n============================================================\n\n")
        
        # Markdown tablo var mı kontrol et
        if (grepl("\\|.*\\|.*\\|", last_msg$content)) {
          mergen_debug_cat("[GLOBAL] \U00002713 Mesajda markdown tablo BULUNDU\n")
          # Kaç satır tablo var?
          table_lines <- length(gregexpr("\n", last_msg$content)[[1]])
          mergen_debug_cat("[GLOBAL] Tabloda yaklaşık", table_lines, "satır var\n")
        } else {
          mergen_debug_cat("[GLOBAL] *** UYARI: Mesajda markdown tablo BULUNAMADI! ***\n")
        }
        
        # Geçmişe ekle - ÖNEMLİ: Ham araç çağrı metnini dahil etme
        chat_history <- append(chat_history, list(
          list(role = "assistant", content = "[Araçlar kullanıldı]")
        ))
    chat_history <- append(chat_history, list(
          list(role = "user", content = paste0(
            "Araç sonuçları:\n\n",
            results_text,
            "\n\n+=======================================================+\n",
            "|  MUTLAK KURAL - ASLA İHLAL ETME                       |\n",
            "+=======================================================+\n\n",
            "Yukarıdaki tablo GERÇEK VERİDİR. Bu veritabanından geldi.\n\n",
            "SEN BİR VERİ RAPORLAYICI ROBOTSUN - VERİ ÜRETME!\n\n",
            "YAPMAN GEREKENLER:\n",
            "\U00002713 Yukarıdaki tabloda gördüğün TAM sayıları kopyala\n",
            "\U00002713 Hiçbir değeri yuvarlaMA, değiştirME\n",
            "\U00002713 Tablodaki her satırı kullan\n",
            "\U00002713 ProjeAdi ve sayıları BİREBİR kopyala\n\n",
            "\U00002713 Yanıtı TEK SEFERDE tamamla; ek deneme veya ikinci tur bekleme.\n",
            "\U00002713 Sonuçları yorumla: trend, uç değer ve dağılımı en az 4-5 cümlelik öğretici bir paragrafla açıkla; kullanıcının hangi desene odaklanması gerektiğini belirt.\n",
            "\U00002713 Grafik varsa, eksenler ve göze çarpan deseni 1-2 cümlede özetle.\n\n",
            "ASLA YAPMA:\n",
            "\U00002717 'Örnek Çıktı' yazma\n",
            "\U00002717 Sahte sayılar üretme\n",
            "\U00002717 Tahmin etme\n",
            "\U00002717 Benzer değerler uydurma\n",
            "\U00002717 '...' kullanma\n\n",
            "Eğer yukarıdaki tabloda veri YOKSA:\n",
            "-> 'Sonuç bulunamadı' de ve DUR\n\n",
            "Eğer yukarıdaki tabloda veri VARSA:\n",
            "-> O sayıları AYNEN yaz\n\n",
            "ŞİMDİ: Yukarıdaki GERÇEK tabloyu kullanarak kullanıcının sorusunu cevapla."
          ))
        ))
        
        mergen_debug_cat("\n========================================\n")
        mergen_debug_cat("[MCP] Calling LLM again with tool results\n")
        mergen_debug_cat("========================================\n")
    
    # Sistem mesajını ÖNCELİKLE ekle - AI'ın rolünü tanımla
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
        
        # Sistem mesajını chat_history'nin başına ekle
        chat_history <- c(list(system_msg_anti_hallucination), chat_history)
    
    # DEBUG - Tüm chat_history'yi dosyaya yaz (sadece debug modunda)
        if (isTRUE(getOption("mergen.debug", FALSE))) {
        tryCatch({
          debug_file <- file.path(tempdir(), sprintf("chat_debug_%s.txt", format(Sys.time(), "%Y%m%d_%H%M%S")))
          writeLines(
            c(
              "===============================================",
              "CHAT HISTORY - AI'A GÖNDERİLEN TÜM MESAJLAR",
              "===============================================",
              "",
              sapply(seq_along(chat_history), function(i) {
                msg <- chat_history[[i]]
                paste0(
                  "\n\n--------------------------------------------\n",
                  "MESAJ #", i, " - Role: ", msg$role, "\n",
                  "--------------------------------------------\n",
                  msg$content
                )
              })
            ),
            debug_file
          )
          mergen_debug_cat("\n[GLOBAL] \U00002713 Chat history dosyaya yazıldı:", debug_file, "\n")
          mergen_debug_cat("[GLOBAL] Bu dosyayı inceleyerek AI'a tam olarak ne gönderildiğini görebilirsiniz\n\n")
        }, error = function(e) {
          mergen_debug_cat("[GLOBAL] Dosya yazma hatası:", e$message, "\n")
        })
        }
        
        ikinci_gecis <- llm_worker_run_mcp_second_pass(
          chat_history = chat_history,
          selected_model = selected_model,
          settings = settings,
          api_endpoint = api_endpoint,
          api_key = api_key,
          temp_value = temp_value,
          tool_results_raw = tool_results_raw,
          chart_blocks_text = chart_blocks_text,
          charts_to_store = charts_to_store,
          add_fallback_chart = add_fallback_chart,
          worker_start_time = worker_start_time,
          timeout_sec = worker_timeout_sec
        )

        if (!isTRUE(ikinci_gecis$ok)) {
          return(ikinci_gecis$response)
        }

        ai2 <- ikinci_gecis$ai2
        reasoning2 <- ikinci_gecis$reasoning2
        
    if (!(is.character(ai2) && length(ai2) > 0 && nzchar(ai2[1]))) {
      fb <- format_answer_from_tool_results(tool_results_raw)
      if (!(is.character(fb) && length(fb) > 0 && nzchar(trimws(fb[1])))) {
      fb <- "Araç çıktıları alındı ancak modelden içerik gelmedi."
      }
      if (is.character(chart_blocks_text) && nzchar(chart_blocks_text)) {
      fb <- paste0(fb, "\n\n", chart_blocks_text)
      }
      # Eğer grafik hâlâ yoksa zorunlu yedek grafiği ekle
      fb <- add_fallback_chart(fb)

      return(list(
      content  = fb,
      duration = as.numeric(difftime(Sys.time(), worker_start_time, units = "secs")),
      chart_store = charts_to_store
      ))
    }
        
    ai2 <- strip_planner_text(ai2)

    # Eğer araçlardan gelen grafik bloğu varsa ekle
    if (is.character(chart_blocks_text) && nzchar(chart_blocks_text)) {
      ai2 <- paste0(ai2, "\n\n", chart_blocks_text)
    }

    # Hâlâ grafik yoksa (model araç çağırmış olsa bile veri görselleştirmemişse) yedek grafik ekle
    ai2 <- add_fallback_chart(ai2)

    return(list(
      content  = ai2,
      duration = as.numeric(difftime(Sys.time(), worker_start_time, units = "secs")),
      chart_store = charts_to_store,
      reasoning_content = if (nzchar(reasoning2)) reasoning2 else NULL
    ))

    } else {
    mergen_debug_cat("[MCP] No tool calls detected (structured or textual)\n")
      }
    }

    mergen_debug_cat("[SUCCESS] Returning response\n")
    mergen_debug_cat("========================================\n\n")

  ai_content <- strip_planner_text(ai_content)

  # Model araç çağırmadıysa ve grafik niyeti varsa yedek grafik bloğu ekle
  ai_content <- add_fallback_chart(ai_content)

  # Düşünen modellerin non-streaming yanıtlarında gelen akıl yürütme metnini
  # üst katmana aktar; Excel (MCP) gibi non-streaming yollarda bu metin
  # kayıt için MB_Messages.ReasoningContent sütununa yazılır.
  reasoning1 <- ayristirilmis_yanit$reasoning %||% ""

  return(list(
    content = ai_content,
    duration = as.numeric(difftime(Sys.time(), worker_start_time, units = "secs")),
    chart_store = charts_to_store,
    reasoning_content = if (nzchar(reasoning1)) reasoning1 else NULL
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
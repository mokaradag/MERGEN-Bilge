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
  # Metin içinde grafik isteği türünü (bar, line, vb.) algıla
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
    # Son kullanıcı mesajında grafik çizim niyeti var mı?
    if (is.character(last_user_txt) && length(last_user_txt) > 0 && nzchar(last_user_txt[1])) {
    chart_intent_flag <- grepl(
      "(?i)\\b(grafik|grafikleri|grafiğini|görselleştir|gorsellestir|görselleştirme|gorsellestirme|plot|chart|chartlab|figure|graph|viz|visualize|visualise|çiz|çizelge|histogram|bar|çubuk|line|çizgi|trend|dağılım|scatter|pie|pasta|donut|pareto|area|spline|boxplot)\\b",
      last_user_txt[1],
      perl = TRUE
    )
    }
  }, silent = TRUE)
  
  # Grafiklerin toplanacağı depo (erken başlat)
  charts_to_store <- list()

  # Fallback mekanizması devre dışı; model tam sayı üretmeli
  # Otomatik ekleme kaldırıldı çünkü:
  # 1) 1 grafik isteğine 3 grafik dönüyordu
  # 2) Yanlış eksen seçimleri
  # 3) İstenmeyen grafik kombinasyonları
  add_fallback_chart <- function(original_text) {
    # Fallback devre dışı — orijinal metni olduğu gibi döndür
    return(original_text %||% "")
  }
    
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

    temp_value <- if (!is.null(settings$temperature)) settings$temperature else 0.4

    body <- list(
      model = selected_model, 
      messages = messages_payload, 
      stream = FALSE,
      temperature = temp_value
    )

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

    # Ollama 'tools' desteklemiyorsa (400 hatası), şemasız tekrar dene
    if (status == 400 && mcp_enabled_now && isTRUE(attach_tool_schema) &&
      grepl("does not support tools|tool", tolower(resp_txt))) {
    mergen_debug_cat("[RETRY] 400 & tools not supported → retrying without tool schema...\n")
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

    # HTTP durum kodlarına göre hata fırlat
    if (status != 200) {
    msg_tail <- if (nzchar(resp_txt)) paste0(" — ", substr(resp_txt, 1, 500)) else ""
    if (status == 429)      stop("RATE_LIMIT: Çok fazla istek gönderildi.", call. = FALSE)
    else if (status %in% c(401,403)) stop("AUTH_ERROR: Kimlik doğrulama hatası.", call. = FALSE)
    else if (status >= 500) stop(sprintf("SERVER_ERROR: Sunucu hatası (Kod: %d)%s", status, msg_tail), call. = FALSE)
    else                    stop(sprintf("API_ERROR: API hatası (Kod: %d)%s", status, msg_tail), call. = FALSE)
    }
  }
    
    response_content <- httr::content(response, "parsed")
    
    ai_content <- NULL
    tool_calls_struct <- NULL
    
    if (is.list(response_content) &&
        !is.null(response_content$choices) &&
        length(response_content$choices) > 0) {
      first_choice <- response_content$choices[[1]]
      if (is.list(first_choice) && !is.null(first_choice$message)) {
        ai_content <- first_choice$message$content %||% ""
        # YENİ: API'den gelen yapısal araç çağrılarını yakala
        if (!is.null(first_choice$message$tool_calls) && length(first_choice$message$tool_calls) > 0) {
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
    
        # Çözümleyiciler için oturum nesnesini al
        current_session <- if (!is.null(settings$shiny_session)) settings$shiny_session else NULL
    
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

    # Sonuçlardan (tablo/grafik) hızlı içgörü üret
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
    
    # Ham araç çıktılarını detaylı logla
        mergen_debug_cat("\n========== [GLOBAL] HAM ARAÇ SONUÇLARI ==========\n")
        for (i in seq_along(tool_results_raw)) {
          raw <- tool_results_raw[[i]]
          mergen_debug_cat("\n[GLOBAL] Araç #", i, "\n")
          mergen_debug_cat("[GLOBAL] Class:", class(raw), "\n")
          mergen_debug_cat("[GLOBAL] Names:", paste(names(raw), collapse=", "), "\n")
          
          if (is.list(raw)) {
            if (!is.null(raw$error)) {
              mergen_debug_cat("[GLOBAL] *** HATA VAR ***: ", raw$error, "\n")
            }
            
            df <- raw$`sonuç_önizleme` %||% raw$preview
            if (is.data.frame(df)) {
              mergen_debug_cat("[GLOBAL] DataFrame bulundu - Satır:", nrow(df), " Sütun:", ncol(df), "\n")
              if (nrow(df) > 0) {
                mergen_debug_cat("[GLOBAL] İlk satır:\n")
                if (isTRUE(getOption("mergen.debug", FALSE))) {
                  print(df[1, , drop=FALSE])
                }
              }
            } else {
              mergen_debug_cat("[GLOBAL] DataFrame YOK veya geçersiz!\n")
            }
          }
        }
        mergen_debug_cat("========== [GLOBAL] HAM SONUÇLAR BİTİŞ ==========\n\n")
        
    # Araç sonuçlarını LLM için okunabilir formata çevir
        mergen_debug_cat("\n╔════════════════════════════════════════════════════╗\n")
        mergen_debug_cat("║  [GLOBAL] ARAÇ SONUÇLARINI FORMATLAMAYA BAŞLIYOR  ║\n")
        mergen_debug_cat("╚════════════════════════════════════════════════════╝\n\n")
        
        tool_results <- lapply(seq_along(tool_calls), function(i) {
          raw <- tool_results_raw[[i]]
          tool_name <- tool_calls[[i]]$function_name
          
          mergen_debug_cat("\n========== [GLOBAL] Araç #", i, " Formatlanıyor ==========\n")
          mergen_debug_cat("[GLOBAL] Araç adı:", tool_name, "\n")
          mergen_debug_cat("[GLOBAL] raw değişkeni class:", class(raw), "\n")
          mergen_debug_cat("[GLOBAL] raw değişkeni names:", paste(names(raw), collapse=", "), "\n")
          
          # sonuç_önizleme veya preview'i bul
          df <- NULL
          if (!is.null(raw$`sonuç_önizleme`)) {
            mergen_debug_cat("[GLOBAL] sonuç_önizleme bulundu\n")
            df <- raw$`sonuç_önizleme`
          } else if (!is.null(raw$preview)) {
            mergen_debug_cat("[GLOBAL] preview bulundu\n")
            df <- raw$preview
          } else {
            mergen_debug_cat("[GLOBAL] *** UYARI: Ne sonuç_önizleme ne de preview bulundu! ***\n")
          }
          
          mergen_debug_cat("[GLOBAL] df class:", class(df), "\n")
          mergen_debug_cat("[GLOBAL] df is.data.frame:", is.data.frame(df), "\n") 

          if (is.list(raw) && (!is.null(raw$chart) || isTRUE(raw$`__mcp_plot`))) {
            mergen_debug_cat("[GLOBAL] Grafik sonucu algılandı; JSON yerine özet kullanılacak.\n")
            result_text <- build_chart_summary(raw)

          } else if (is.data.frame(df)) {
            mergen_debug_cat("[GLOBAL] DataFrame boyutu: ", nrow(df), " satır x ", ncol(df), " sütun\n")
            mergen_debug_cat("[GLOBAL] Sütun isimleri:", paste(colnames(df), collapse=", "), "\n")
            
            if (nrow(df) > 0) {
              # Türkçe karakterlerin düzgün görünmesi için UTF-8 dönüşümü
              df <- as.data.frame(df, stringsAsFactors = FALSE)
              df[] <- lapply(df, function(col) tryCatch(enc2utf8(as.character(col)), error = function(e) col))
              colnames(df) <- tryCatch(enc2utf8(colnames(df)), error = function(e) colnames(df))
        
              mergen_debug_cat("[GLOBAL] \U00002713 VERİ VAR - İLK SATIR:\n")
              if (isTRUE(getOption("mergen.debug", FALSE))) {
                print(df[1, , drop=FALSE])
              }
              
              # DataFrame'i markdown tablo olarak formatla
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
                "\U00002B07\U0000FE0F AŞAĞIDA ", nrow(df), " SATIR GERÇEK VERİ VAR \U00002B07\U0000FE0F\n",
                "BU SAYILARI AYNEN KULLAN - UYDURMA!\n\n",
                table_md, "\n\n",
                "\U00002B06\U0000FE0F YUKARDA ", nrow(df), " SATIR GERÇEK VERİ VAR \U00002B06\U0000FE0F\n",
                "BU TABLODAKİ SAYILARI BİREBİR KOPYALA!"
              )
              
              mergen_debug_cat("\n[GLOBAL] \U00002713 Markdown tablo oluşturuldu\n")
              mergen_debug_cat("[GLOBAL] Tablo uzunluğu:", nchar(table_md), "karakter\n")
              mergen_debug_cat("[GLOBAL] Tablo ilk 500 karakteri:\n")
              mergen_debug_cat(substr(table_md, 1, 500), "\n...\n")
              
            } else {
              mergen_debug_cat("[GLOBAL] *** UYARI: DataFrame BOŞ (0 satır) ***\n")
              result_text <- "UYARI: Sorgu sonucu boş döndü."
            }
          } else if (is.list(raw) && !is.null(raw$result) && is.character(raw$result)) {
            mergen_debug_cat("[GLOBAL] \U00002713 Liste içindeki result metni kullanılacak\n")
            result_text <- paste(raw$result, collapse = "\n\n")
          } else if (is.character(raw) && length(raw)) {
            mergen_debug_cat("[GLOBAL] \U00002713 Ham karakter vektörü kullanılacak\n")
            result_text <- paste(raw, collapse = "\n\n")
          } else {
            mergen_debug_cat("[GLOBAL] *** UYARI: df DataFrame değil! JSON formatında dönecek ***\n")
            result_text <- jsonlite::toJSON(raw, auto_unbox = TRUE, pretty = TRUE)
          }
          
          mergen_debug_cat("[GLOBAL] result_text uzunluğu:", nchar(result_text), "karakter\n")
          mergen_debug_cat("[GLOBAL] result_text ilk 300 karakteri:\n")
          mergen_debug_cat(substr(result_text, 1, 300), "\n...\n")
          mergen_debug_cat("========================================\n\n")
          
          list(tool = tool_name, result = result_text)
        })
        
        mergen_debug_cat("\n╔════════════════════════════════════════════════════╗\n")
        mergen_debug_cat("║  [GLOBAL] TÜM ARAÇLAR FORMATLANDI                  ║\n")
        mergen_debug_cat("╚════════════════════════════════════════════════════╝\n\n")
        
    # Araç sonuçlarını log'a yaz
        for (i in seq_along(tool_results)) {
          tr <- tool_results[[i]]
          mergen_debug_cat("\n========== ARAÇ SONUCU ", i, " ==========\n")
          mergen_debug_cat("Araç Adı: ", tr$tool, "\n")
          mergen_debug_cat("Sonuç Uzunluğu: ", nchar(tr$result), " karakter\n")
          mergen_debug_cat("İlk 1000 karakter:\n", substr(tr$result, 1, 1000), "\n")
          mergen_debug_cat("========================================\n\n")
        }
        
        # LLM için sonuç mesajı oluştur
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
        
        # Tam sonuç metnini log'a yaz (LLM'e ne gönderildiğini görmek için)
        mergen_debug_cat("\n========== LLM'E GÖNDERİLEN TAM SONUÇ METNİ ==========\n")
        mergen_debug_cat(results_text, "\n")
        mergen_debug_cat("========================================\n\n")
    
    # Chat history'nin son elemanını (AI'a gönderilecek mesajı) detaylı logla
        mergen_debug_cat("\n╔═══════════════════════════════════════════════════════════╗\n")
        mergen_debug_cat("║  [GLOBAL] AI'A GÖNDERİLECEK MESAJIN SON HALİ              ║\n")
        mergen_debug_cat("╚═══════════════════════════════════════════════════════════╝\n\n")
        
        last_msg <- chat_history[[length(chat_history)]]
        mergen_debug_cat("[GLOBAL] Son mesaj role:", last_msg$role, "\n")
        mergen_debug_cat("[GLOBAL] Son mesaj uzunluğu:", nchar(last_msg$content), "karakter\n")
        mergen_debug_cat("\n[GLOBAL] SON MESAJIN TAM İÇERİĞİ:\n")
        mergen_debug_cat("════════════════════════════════════════════════════════════\n")
        mergen_debug_cat(last_msg$content)
        mergen_debug_cat("\n════════════════════════════════════════════════════════════\n\n")
        
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
            "\n\n╔═══════════════════════════════════════════════════════╗\n",
            "║  MUTLAK KURAL - ASLA İHLAL ETME                       ║\n",
            "╚═══════════════════════════════════════════════════════╝\n\n",
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
            "→ 'Sonuç bulunamadı' de ve DUR\n\n",
            "Eğer yukarıdaki tabloda veri VARSA:\n",
            "→ O sayıları AYNEN yaz\n\n",
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
          mergen_debug_cat("\n[GLOBAL] \U00002713 Chat history dosyaya yazıldı:", debug_file, "\n")
          mergen_debug_cat("[GLOBAL] Bu dosyayı inceleyerek AI'a tam olarak ne gönderildiğini görebilirsiniz\n\n")
        }, error = function(e) {
          mergen_debug_cat("[GLOBAL] Dosya yazma hatası:", e$message, "\n")
        })
        }
        
        # İKİNCİ GEÇİŞ: modeli araç sonuçlarıyla tekrar çağır (araçlar KAPALI)
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
      # Eğer grafik hâlâ yoksa zorunlu yedek grafiği ekle
      fb <- add_fallback_chart(fb)

      return(list(
      content  = fb,
      duration = as.numeric(difftime(Sys.time(), worker_start_time, units = "secs")),
      chart_store = charts_to_store
      ))
    }

    rc2 <- httr::content(response2, "parsed")
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
      chart_store = charts_to_store
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
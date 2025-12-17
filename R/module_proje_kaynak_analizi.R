# R/module_proje_kaynak_analizi.R

# ==============================================================================
# 0. AKıLLı FİLTRELEME MOTORü (AI-Guided Filtering Engine)
# ==============================================================================

extract_filter_criteria_from_prompt <- function(user_prompt, available_columns, conn) {
  cat(sprintf("[FILTER_AI] Prompt analiz ediliyor: '%s'\n", user_prompt))
  
  fallback_filter <- tryCatch({
    if (grepl("\\b([A-Z0-9]{4,})\\b", user_prompt, perl = TRUE)) {
      code_match <- regmatches(user_prompt, regexpr("\\b([A-Z0-9]{4,})\\b", user_prompt, perl = TRUE))
      if (length(code_match) > 0) {
        code <- code_match[1]
        
        potential_cols <- c("ProjeKodu", "Proje_Kodu", "EPS_Kodu", "EPSKodu", "MasrafYeriKodu")
        matched_col <- NULL
        for (pc in potential_cols) {
          if (pc %in% available_columns) {
            matched_col <- pc
            break
          }
        }
        
        if (!is.null(matched_col)) {
          cat(sprintf("[FILTER_AI] Regex fallback: sütun=%s, değer=%s\n", matched_col, code))
          return(list(
            filter_column = matched_col,
            filter_value = code,
            operation = "exact_match",
            aggregation = if (grepl("kaç|sayı|adet", user_prompt, ignore.case = TRUE)) "count" else "single_row"
          ))
        }
      }
    }
    NULL
  }, error = function(e) NULL)
  
  if (!is.null(fallback_filter)) {
    return(fallback_filter)
  }
  
  cols_json <- jsonlite::toJSON(available_columns, auto_unbox = TRUE)
  
  system_instruction <- paste0(
    "Sen bir SQL/Veri Filtreleme Asistanısın. Kullanıcının sorusundan hangi sütunun nasıl filtreleneceğini çıkar.\n\n",
    "Mevcut Sütunlar: ", cols_json, "\n\n",
    "ÇIKTI FORMATI (JSON):\n",
    "{\n",
    "  \"filter_column\": \"SütunAdı\" veya null,\n",
    "  \"filter_value\": \"AranacakDeğer\" veya null,\n",
    "  \"operation\": \"exact_match\" | \"contains\" | \"greater_than\" | \"less_than\" | \"between\" | null,\n",
    "  \"aggregation\": \"count\" | \"sum\" | \"list\" | \"single_row\" | \"top_n\" | null,\n",
    "  \"top_n\": sayı veya null\n",
    "}\n\n",
    "KURALLAR:\n",
    "1. Eğer soru 'kaç', 'toplam sayı' içeriyorsa: aggregation='count'\n",
    "2. Eğer soru belirli bir kod/ID içeriyorsa: operation='exact_match', filter_column=ilgili kod sütunu\n",
    "3. Eğer soru 'listele', 'göster' içeriyorsa: aggregation='list'\n",
    "4. Eğer soru 'en yüksek', 'en büyük' içeriyorsa: aggregation='top_n', top_n=5\n",
    "5. Proje kodları genelde 'ProjeKodu', 'Proje_Kodu' gibi sütunlardadır\n",
    "6. Eğer soruda 'özetle', 'detay', 'bilgi ver' varsa: aggregation='single_row'\n\n",
    "Sadece JSON çıktı ver, başka yorum yapma."
  )
  
  messages <- list(
    list(role = "system", content = system_instruction),
    list(role = "user", content = user_prompt)
  )
  
  api_endpoint <- Sys.getenv("LOCAL_LLM_ENDPOINT", "http://localhost:11434/api/generate")
  selected_model <- getOption("mergen.filter_model", "mergen-local-model")
  
  body <- list(
    model = selected_model,
    messages = messages,
    stream = FALSE,
    temperature = 0.1
  )
  
  tryCatch({
    response <- httr::POST(
      api_endpoint,
      httr::add_headers(`Content-Type` = "application/json"),
      body = jsonlite::toJSON(body, auto_unbox = TRUE),
      encode = "raw",
      httr::timeout(30)
    )
    
    if (httr::status_code(response) != 200) {
      cat("[FILTER_AI] API hatası, fallback kullanılacak\n")
      return(fallback_filter %||% list(filter_column = NULL, aggregation = NULL))
    }
    
    parsed <- httr::content(response, "parsed")
    ai_text <- parsed$choices[[1]]$message$content
    
    ai_text <- gsub("```json|```", "", ai_text)
    ai_text <- trimws(ai_text)
    
    result <- jsonlite::fromJSON(ai_text, simplifyVector = FALSE)
    
    cat(sprintf("[FILTER_AI] Sonuç: filter_column=%s, operation=%s, aggregation=%s\n",
                result$filter_column %||% "NULL",
                result$operation %||% "NULL",
                result$aggregation %||% "NULL"))
    
    return(result)
    
  }, error = function(e) {
    cat(sprintf("[FILTER_AI] Hata: %s, fallback kullanılıyor\n", e$message))
    return(fallback_filter %||% list(filter_column = NULL, aggregation = NULL))
  })
}

build_sql_where_clause <- function(filter_instructions) {
  if (is.null(filter_instructions) || 
      is.null(filter_instructions$filter_column) || 
      is.null(filter_instructions$filter_value)) {
    return("")
  }
  
  col <- filter_instructions$filter_column
  val <- filter_instructions$filter_value
  op <- filter_instructions$operation %||% "exact_match"
  
  where_clause <- switch(
    op,
    "exact_match" = sprintf("WHERE [%s] = '%s'", col, val),
    "contains" = sprintf("WHERE [%s] LIKE '%%%s%%'", col, val),
    "greater_than" = sprintf("WHERE [%s] > %s", col, val),
    "less_than" = sprintf("WHERE [%s] < %s", col, val),
    sprintf("WHERE [%s] = '%s'", col, val)
  )
  
  cat(sprintf("[SQL_FILTER] WHERE şartı oluşturuldu: %s\n", where_clause))
  return(where_clause)
}

apply_smart_filters <- function(data, filter_instructions, user_prompt) {
  cat(sprintf("[SMART_FILTER] Filtreleme uygulanıyor. Ham satır: %d\n", nrow(data)))
  
  if (is.null(filter_instructions) || nrow(data) == 0) {
    return(head(data, 100))
  }
  
  aggregation <- filter_instructions$aggregation
  
  if (!is.null(aggregation)) {
    if (aggregation == "count") {
      result <- data.frame(
        Metrik = "Toplam Kayıt Sayısı",
        Değer = nrow(data)
      )
      cat(sprintf("[SMART_FILTER] COUNT agregasyonu: %d\n", nrow(data)))
      return(result)
      
    } else if (aggregation == "top_n") {
      n <- filter_instructions$top_n %||% 10
      result <- head(data, n)
      cat(sprintf("[SMART_FILTER] TOP %d satır döndürülüyor\n", n))
      return(as.data.frame(result))
      
    } else if (aggregation == "list") {
      result <- head(data, 50)
      cat(sprintf("[SMART_FILTER] LIST: İlk 50 satır döndürülüyor\n"))
      return(as.data.frame(result))
      
    } else if (aggregation == "single_row") {
      result <- head(data, 10)
      cat(sprintf("[SMART_FILTER] SINGLE_ROW: İlk 10 satır döndürülüyor\n"))
      return(as.data.frame(result))
    }
  }
  
  result <- head(data, 100)
  cat(sprintf("[SMART_FILTER] Varsayılan: İlk 100 satır döndürülüyor\n"))
  return(as.data.frame(result))
}

# ==============================================================================
# 1. RLS ve YETKİ YÖNETİMİ (SECURITY ENGINE)
# ==============================================================================

get_user_rls_info <- function(username, conn) {
  cat(sprintf("[PK_ANALIZ] get_user_rls_info calistiriliyor. Kullanici: %s\n", username))
  
  # 1. DC01_user_base tablosundan temel yetkileri çek
  base_query <- "SELECT TOP 1 * FROM DC01_user_base WHERE KullaniciAdi = ?"
  user_base <- tryCatch({
    DBI::dbGetQuery(conn, base_query, params = list(username))
  }, error = function(e) {
    cat(sprintf("[PK_ANALIZ] HATA (DC01_user_base): %s\n", e$message))
    return(data.frame())
  })
  
  if (nrow(user_base) == 0) {
    cat("[PK_ANALIZ] Kullanici DC01 tablosunda bulunamadi.\n")
    return(list(authorized = FALSE, reason = "Kullanıcı DC01 tablosunda bulunamadı."))
  }
  
  info <- as.list(user_base[1, ])
  info$authorized <- TRUE
  cat(sprintf("[PK_ANALIZ] Yetki Tipi: %s, MasrafYeri: %s\n", info$Yetki, info$MasrafYeriKodu))
  
  # Masraf Yeri (Department) Parse Et
  if (!is.na(info$MasrafYeriKodu) && info$MasrafYeriKodu != "ADMIN") {
    info$allowed_depts <- trimws(unlist(strsplit(as.character(info$MasrafYeriKodu), ",")))
  } else {
    info$allowed_depts <- NULL # ADMIN veya hepsi
  }
  
  # 2. Yetki Tipine Göre Ek Kısıtlamaları (PY, KY-P, DIR-P) Çek
  info$allowed_projects <- NULL
  info$allowed_eps <- NULL
  
  if (info$Yetki == "PY") {
    cat("[PK_ANALIZ] PY yetkisi kontrol ediliyor...\n")
    py_res <- tryCatch(DBI::dbGetQuery(conn, sql_permission_py), error = function(e) NULL)
    if (!is.null(py_res)) {
      user_rows <- py_res[py_res$KullaniciAdi == username, ]
      if (nrow(user_rows) > 0) {
        all_projs <- paste(user_rows$ProjeKodu, collapse = ",")
        info$allowed_projects <- unique(trimws(unlist(strsplit(all_projs, ","))))
        cat(sprintf("[PK_ANALIZ] PY Projeleri: %s\n", paste(info$allowed_projects, collapse=",")))
      }
    }
  }
  
  if (info$Yetki %in% c("KY-P", "DIR-P")) {
    cat("[PK_ANALIZ] Program (EPS) yetkisi kontrol ediliyor...\n")
    eps_res <- tryCatch(DBI::dbGetQuery(conn, sql_permission_eps), error = function(e) NULL)
    if (!is.null(eps_res)) {
      user_rows <- eps_res[eps_res$KullaniciAdi == username, ]
      if (nrow(user_rows) > 0) {
        all_eps <- paste(user_rows$EPSKodu, collapse = ",")
        info$allowed_eps <- unique(trimws(unlist(strsplit(all_eps, ","))))
        cat(sprintf("[PK_ANALIZ] EPS Kodlari: %s\n", paste(info$allowed_eps, collapse=",")))
      }
    }
  }
  
  return(info)
}

apply_rls_to_data <- function(data, user_info, rls_cols) {
  if (nrow(data) == 0) return(data)
  
  cat(sprintf("[PK_ANALIZ] RLS Uygulaniyor. Ham satir sayisi: %d\n", nrow(data)))
  filtered_data <- data
  yetki <- user_info$Yetki
  
  if (yetki == "ADMIN") {
    cat("[PK_ANALIZ] Rol ADMIN -> Filtre uygulanmadi.\n")
    return(filtered_data)
  }
  
  # Masraf Yeri Filtresi
  if (!is.null(user_info$allowed_depts) && !is.null(rls_cols$masraf_yeri_col)) {
    col_name <- rls_cols$masraf_yeri_col
    if (col_name %in% names(filtered_data)) {
      filtered_data <- filtered_data[filtered_data[[col_name]] %in% user_info$allowed_depts, ]
      cat(sprintf("[PK_ANALIZ] Masraf Yeri Filtresi Sonrasi: %d satir\n", nrow(filtered_data)))
    }
  }
  
  # PY Filtresi
  if (yetki == "PY" && !is.null(user_info$allowed_projects) && !is.null(rls_cols$proje_kodu_col)) {
    col_name <- rls_cols$proje_kodu_col
    if (col_name %in% names(filtered_data)) {
      filtered_data <- filtered_data[filtered_data[[col_name]] %in% user_info$allowed_projects, ]
      cat(sprintf("[PK_ANALIZ] PY Filtresi Sonrasi: %d satir\n", nrow(filtered_data)))
    }
  }
  
  # EPS Filtresi
  if (yetki %in% c("KY-P", "DIR-P") && !is.null(user_info$allowed_eps) && !is.null(rls_cols$eps_kodu_col)) {
    col_name <- rls_cols$eps_kodu_col
    if (col_name %in% names(filtered_data)) {
      filtered_data <- filtered_data[filtered_data[[col_name]] %in% user_info$allowed_eps, ]
      cat(sprintf("[PK_ANALIZ] EPS Filtresi Sonrasi: %d satir\n", nrow(filtered_data)))
    }
  }
  
  return(filtered_data)
}

# ==============================================================================
# 2. SORGULAMA MOTORU (EXECUTION ENGINE)
# ==============================================================================

pk_analiz_process_request <- function(user_prompt, chat_history, session) {
  cat("\n[PK_ANALIZ] >>> pk_analiz_process_request BASLATILDI <<<\n")
  cat(sprintf("[PK_ANALIZ] Kullanici Prompt: '%s'\n", user_prompt))
  
  conn_list <- get_connection()
  conn <- conn_list$conn
  on.exit({
    cat("[PK_ANALIZ] DB Baglantisi serbest birakiliyor.\n")
    release_connection(conn_list)
  })
  
  username <- session$userData$system_username %||% "Unknown"
  
  rls_info <- get_user_rls_info(username, conn)
  if (!isTRUE(rls_info$authorized)) {
    cat("[PK_ANALIZ] Yetki Hatasi: Kullanici bulunamadi.\n")
    return("⚠️ **Yetki Hatası:** Sistemde kullanıcı kaydınız (DC01_user_base) bulunamadı. Lütfen yönetici ile iletişime geçin.")
  }
  
  cat("[PK_ANALIZ] Akilli sorgu secimi yapiliyor (select_smart_query)...\n")
  selected_query <- select_smart_query(user_prompt, query_library, chat_history)
  
  if (is.null(selected_query)) {
    cat("[PK_ANALIZ] UYARI: Uygun bir sorgu ESLESMESI BULUNAMADI.\n")
    return("🤔 Aradığınız bilgi mevcut analiz kütüphanesinde bulunamadı.")
  }
  
  cat(sprintf("[PK_ANALIZ] Secilen Sorgu: '%s'\n", selected_query$name))
  
  sql_query_text <- ""
  
  if (!is.null(selected_query$sql_file) && nzchar(selected_query$sql_file)) {
    fpath <- selected_query$sql_file
    
    if (file.exists(fpath)) {
      cat(sprintf("[PK_ANALIZ] SQL dosyadan okunuyor: %s\n", fpath))
      
      f_con <- file(fpath, open = "rb")
      f_size <- file.info(fpath)$size
      if (is.na(f_size)) f_size <- 0
      raw_content <- readBin(f_con, "raw", n = f_size)
      close(f_con)
      
      sql_query_text <- ""
      
      if (length(raw_content) > 0) {
        has_bom_le <- length(raw_content) >= 2 && raw_content[1] == as.raw(0xff) && raw_content[2] == as.raw(0xfe)
        has_bom_be <- length(raw_content) >= 2 && raw_content[1] == as.raw(0xfe) && raw_content[2] == as.raw(0xff)
        has_nulls <- any(raw_content == as.raw(0))
        
        if (has_bom_le) {
          sql_query_text <- iconv(list(raw_content), from = "UTF-16LE", to = "UTF-8")[[1]]
        } else if (has_bom_be) {
          sql_query_text <- iconv(list(raw_content), from = "UTF-16BE", to = "UTF-8")[[1]]
        } else if (has_nulls) {
          if (length(raw_content) >= 2 && raw_content[1] == as.raw(0) && raw_content[2] != as.raw(0)) {
            cat("[PK_ANALIZ] Dosya NULL byte içeriyor (BE tespiti), UTF-16BE deneniyor...\n")
            sql_query_text <- iconv(list(raw_content), from = "UTF-16BE", to = "UTF-8")[[1]]
          } else {
            cat("[PK_ANALIZ] Dosya NULL byte içeriyor, UTF-16LE deneniyor...\n")
            sql_query_text <- iconv(list(raw_content), from = "UTF-16LE", to = "UTF-8")[[1]]
          }
        } else {
          text_utf8 <- iconv(list(raw_content), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
          
          if (grepl("<[0-9a-fA-F]{2}>", text_utf8)) {
            cat("[PK_ANALIZ] Dosya UTF-8 değil (TR karakterler). WINDOWS-1254 kullanılıyor...\n")
            converted <- iconv(list(raw_content), from = "WINDOWS-1254", to = "UTF-8")
            sql_query_text <- if (length(converted) > 0 && !is.na(converted[[1]])) converted[[1]] else text_utf8
          } else {
            sql_query_text <- text_utf8
          }
        }
      }
      
      sql_query_text <- gsub("^\ufeff", "", sql_query_text)
      
      cat(sprintf("[PK_ANALIZ] Okunan SQL uzunlugu: %d karakter\n", nchar(sql_query_text)))
      
    } else {
      cat(sprintf("[PK_ANALIZ] HATA: SQL dosyasi bulunamadi: %s\n", fpath))
      return(paste0("⚠️ **Yapılandırma Hatası:** SQL dosyası bulunamadı: ", fpath))
    }
  }
  
  if (!nzchar(sql_query_text) && !is.null(selected_query$sql)) {
    sql_query_text <- selected_query$sql
  }
  
  if (!nzchar(sql_query_text)) {
    cat("[PK_ANALIZ] HATA: Ne sql_file ne de sql metni gecerli!\n")
    return("⚠️ **Yapılandırma Hatası:** Sorgu için SQL kodu bulunamadı.")
  }
  
  if (grepl("^[a-zA-Z]:[\\\\/]|^[\\\\/]{2}|^\\./|^\\.\\./|^[^/\\\\]+[\\\\/]", sql_query_text)) {
    cat(sprintf("[PK_ANALIZ] KRITIK HATA: sql_query_text dosya yolu iceriyor!\n"))
    return("⚠️ **Sistem Hatası:** SQL sorgusu yüklenemedi.")
  }
  
  if (nchar(sql_query_text) < 10 || !grepl("SELECT|INSERT|UPDATE|DELETE|EXEC", sql_query_text, ignore.case = TRUE)) {
    cat(sprintf("[PK_ANALIZ] HATA: Gecersiz SQL icerigi!\n"))
    return("⚠️ **Sistem Hatası:** Geçersiz SQL sorgusu yüklendi.")
  }
  
  target_db <- selected_query$db_target
  
  if (!is.null(target_db) && target_db != "primary") {
    cat(sprintf("[PK_ANALIZ] Hedef DB 'primary' degil (%s). Baglanti degistiriliyor...\n", target_db))
    release_connection(conn_list)
    conn_list <- get_connection(target = target_db)
    conn <- conn_list$conn
  }
  
  temp_query_result <- tryCatch({
    if (grepl("\\b(DELETE|DROP|TRUNCATE|ALTER)\\b", toupper(sql_query_text))) {
      stop("Guvenlik ihlali: Yasakli SQL komutu.")
    }
    DBI::dbGetQuery(conn, sql_query_text)
  }, error = function(e) {
    cat(sprintf("[PK_ANALIZ] SQL HATASI: %s\n", e$message))
    return(NULL)
  })
  
  if (is.null(temp_query_result) || !is.data.frame(temp_query_result)) {
    return("⚠️ **Veritabanı Hatası:** Sorgu çalıştırılırken hata oluştu.")
  }
  
  available_columns <- names(temp_query_result)
  cat(sprintf("[PK_ANALIZ] Sorgu sutunlari: %s\n", paste(available_columns, collapse = ", ")))
  
  cat("[PK_ANALIZ] Filtre kriterleri cikartiliyor...\n")
  filter_criteria <- extract_filter_criteria_from_prompt(
    user_prompt,
    available_columns = available_columns,
    conn = conn
  )
  
  where_clause <- build_sql_where_clause(filter_criteria)
  
  if (nzchar(where_clause)) {
    if (grepl("WHERE", toupper(sql_query_text))) {
      final_sql <- gsub("WHERE", paste("WHERE", sub("^WHERE\\s+", "", where_clause), "AND"), sql_query_text, ignore.case = TRUE)
    } else {
      final_sql <- paste(sql_query_text, where_clause)
    }
  } else {
    final_sql <- sql_query_text
  }
  
  final_sql <- trimws(final_sql)
  
  cat(sprintf("[PK_ANALIZ] Filtrelenmis SQL calistiriliyor...\n"))
  cat(sprintf("[PK_ANALIZ] SQL (ilk 200 kar.): %s...\n", substr(final_sql, 1, 200)))
  
  raw_data <- tryCatch({
    if (grepl("\\b(DELETE|DROP|TRUNCATE|ALTER)\\b", toupper(final_sql))) {
      stop("Guvenlik ihlali: Yasakli SQL komutu.")
    }
    DBI::dbGetQuery(conn, final_sql)
  }, error = function(e) {
    cat(sprintf("[PK_ANALIZ] FILTRELI SQL HATASI: %s\n", e$message))
    return(paste0("⚠️ **Veritabanı Hatası:** Filtrelenmiş sorgu çalıştırılırken hata oluştu.\n`", e$message, "`"))
  })
  
  if (is.character(raw_data) && startsWith(raw_data, "⚠️")) return(raw_data)
  
  cat(sprintf("[PK_ANALIZ] Filtreli SQL Basarili. Dönen Satir: %d\n", nrow(raw_data)))
  
  secure_data <- apply_rls_to_data(raw_data, rls_info, selected_query$rls_columns)
  cat(sprintf("[PK_ANALIZ] RLS sonrasi güvenli satir sayisi: %d\n", nrow(secure_data)))
  
  if (nrow(secure_data) == 0) {
    return(paste0("🔍 **Sonuç:** '", selected_query$name, "' sorgusu çalıştırıldı ancak yetkiniz dahilinde görüntülenecek veri bulunamadı."))
  }
  
  filtered_data <- apply_smart_filters(secure_data, filter_criteria, user_prompt)
  
  cat(sprintf("[PK_ANALIZ] Akıllı filtreleme sonrası: %d satır\n", nrow(filtered_data)))
  
  if (nrow(filtered_data) == 0) {
    return(paste0("🔍 **Sonuç:** Filtreleme sonrası veri bulunamadı. Sorgunuz: '", user_prompt, "'"))
  }
  
  data_preview <- filtered_data
  
  if (nrow(data_preview) > 200) {
    data_preview <- head(data_preview, 200)
    cat("[PK_ANALIZ] UYARI: Sonuç 200 satıra kırpıldı\n")
  }
  
  data_str <- jsonlite::toJSON(data_preview, auto_unbox = TRUE, pretty = TRUE)
  
  if (nrow(secure_data) > nrow(data_preview)) {
    msg <- sprintf("\n\n(Not: Toplam %d satır var. Filtreleme sonucu %d satır gösteriliyor.)", 
                   nrow(secure_data), nrow(data_preview))
    data_str <- paste0(data_str, msg)
  }
  
  system_prompt <- paste0(
    "Sen MERGEN Bilge analiz asistanısın. Sağlanan veriyi analiz ederek kullanıcının sorusuna cevap ver.\n",
    "Kullanılan Sorgu: ", selected_query$name, "\n",
    "Sorgu Açıklaması: ", selected_query$description, "\n\n",
    "ÖNEMLİ: Sana gönderilen veri ZATEN FİLTRELENMİŞTİR.\n",
    "Bu veri kullanıcının sorusuna doğrudan yanıt verecek satırları içerir.\n\n",
    "GÖREVLER:\n",
    "1. JSON verisini incele.\n",
    "2. Kullanıcının sorusuna DOĞRUDAN, NET ve TÜRKÇE cevap ver.\n",
    "3. Veri tek satırsa, o satırı kullan.\n",
    "4. Veri agregasyonsa (count sonucu), o sayıyı kullan.\n",
    "5. Cevabını Markdown formatında ver.\n",
    "6. VERİYE DAYANMAYAN BİLGİ UYDURMA.\n"
  )
  
  user_msg <- paste0("Soru: ", user_prompt, "\n\nVeri Seti:\n", data_str)
  
  cat("[PK_ANALIZ] AI baglami hazirlandi. List donduruluyor.\n")
  
  return(list(
    type = "data_analysis",
    data = secure_data,
    prompt_context = system_prompt,
    user_context = user_msg,
    query_name = selected_query$name
  ))
}

# ==============================================================================
# 3. AKILLI SORGU SEÇİMİ (HEURISTIC)
# ==============================================================================

select_smart_query <- function(prompt, library, history) {
  cat("[PK_ANALIZ] Sorgu kütüphanesi taranıyor...\n")
  
  scores <- sapply(library, function(q) {
    desc_words <- unlist(strsplit(tolower(q$description), "\\W+"))
    prompt_words <- unlist(strsplit(tolower(prompt), "\\W+"))
    name_words <- unlist(strsplit(tolower(q$name), "\\W+"))
    
    # Basit eşleşme skoru
    match_count <- sum(prompt_words %in% c(desc_words, name_words))
    return(match_count)
  })
  
  # Skorları yazdır (Debugging)
  for(i in seq_along(library)) {
    if(scores[i] > 0) {
      cat(sprintf("   - Aday: %s | Skor: %d\n", library[[i]]$name, scores[i]))
    }
  }
  
  best_idx <- which.max(scores)
  
  if (length(best_idx) > 0 && scores[best_idx] > 0) {
    cat(sprintf("[PK_ANALIZ] EN IYI ESLESME: %s (Skor: %d)\n", library[[best_idx]]$name, scores[best_idx]))
    return(library[[best_idx]])
  }
  
  cat("[PK_ANALIZ] Hicbir sorgu ile eslesme saglanamadi.\n")
  return(NULL)
}
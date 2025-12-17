# R/module_proje_kaynak_analizi.R

# ==============================================================================
# 0. AKıLLı FİLTRELEME MOTORü (AI-Guided Filtering Engine)
# ==============================================================================

extract_filter_criteria_from_prompt <- function(user_prompt, available_columns, conn) {
  cat(sprintf("[FILTER_AI] Prompt analiz ediliyor: '%s'\n", user_prompt))
  
  cols_str <- paste(available_columns, collapse = ", ")
  
  system_instruction <- paste0(
    "Sen veri filtreleme yönergeleri veren bir asistansın. Kullanıcının sorusunu analiz et.\n\n",
    "MEVCUT SÜTUNLAR: ", cols_str, "\n\n",
    "ÇIKTI FORMATI (JSON):\n",
    "{\n",
    "  \"filter_column\": \"SütunAdı\",\n",
    "  \"filter_value\": \"AranacakDeğer\",\n",
    "  \"operation\": \"exact_match\" | \"contains\" | \"greater_than\" | \"less_than\",\n",
    "  \"aggregation\": null | \"count\" | \"sum\" | \"list\" | \"group_by\",\n",
    "  \"group_column\": null veya gruplamak için sütun adı\n",
    "}\n\n",
    "KURALLAR:\n",
    "1. 'kaç', 'toplam', 'sayı' → aggregation='count'\n",
    "2. Kod/ID varsa (örn: P1111) → operation='exact_match', filter_column en uygun kod sütunu\n",
    "3. 'listele', 'göster', 'özetle' → aggregation='list'\n",
    "4. 'grupla', 'kırılımında' → aggregation='group_by', group_column belirt\n",
    "5. Proje kodları genelde 'ProjeKodu', 'Proje_Kodu' sütunlarındadır\n",
    "6. Sadece JSON döndür, yorum yapma."
  )
  
  messages <- list(
    list(role = "system", content = system_instruction),
    list(role = "user", content = user_prompt)
  )
  
  tryCatch({
    result <- call_local_llm(messages, list(
      model_selection = getOption("mergen.filter_model", api_config$local_models[1]),
      temperature = 0.1,
      enable_mcp_tools = FALSE,
      shiny_session = NULL
    ))
    
    if (is.null(result) || is.null(result$content)) {
      cat("[FILTER_AI] AI yanıt vermedi, fallback kullanılacak\n")
      return(list(filter_column = NULL, aggregation = NULL))
    }
    
    ai_text <- result$content
    ai_text <- gsub("```json|```", "", ai_text)
    ai_text <- trimws(ai_text)
    
    parsed <- jsonlite::fromJSON(ai_text, simplifyVector = FALSE)
    
    cat(sprintf("[FILTER_AI] Sonuç: filter_column=%s, operation=%s, aggregation=%s\n",
                parsed$filter_column %||% "NULL",
                parsed$operation %||% "NULL",
                parsed$aggregation %||% "NULL"))
    
    return(parsed)
    
  }, error = function(e) {
    cat(sprintf("[FILTER_AI] Hata: %s, fallback kullanılacak\n", e$message))
    return(list(filter_column = NULL, aggregation = NULL))
  })
}

apply_smart_filters <- function(data, filter_instructions, user_prompt) {
  cat(sprintf("[SMART_FILTER] Filtreleme uygulanıyor. Ham satır: %d\n", nrow(data)))
  
  if (nrow(data) == 0) return(data.frame())
  
  dt <- data.table::as.data.table(data)
  
  filter_col <- filter_instructions$filter_column %||% NULL
  filter_val <- filter_instructions$filter_value
  operation <- filter_instructions$operation
  aggregation <- filter_instructions$aggregation
  group_col <- filter_instructions$group_column
  
  if (is.null(filter_col)) {
    cat("[SMART_FILTER] AI filtresi yok, keyword fallback aktif\n")
    
    matches <- regmatches(user_prompt, gregexpr("\\b[A-Za-z0-9-]{3,}\\b", user_prompt))
    search_terms <- unique(unlist(matches))
    
    filtered_terms <- c()
    for (term in search_terms) {
      if ((grepl("[A-Za-z]", term) && grepl("[0-9]", term)) || 
          (nchar(term) >= 5 && grepl("^[A-Z0-9-]+$", toupper(term)))) {
        filtered_terms <- c(filtered_terms, term)
      }
    }
    
    if (!length(filtered_terms)) {
      cat("[SMART_FILTER] Anahtar kelime bulunamadı, ilk 100 satır\n")
      return(head(as.data.frame(data), 100))
    }
    
    cat(sprintf("[SMART_FILTER] Aranan: %s\n", paste(filtered_terms, collapse=", ")))
    
    match_rows <- apply(data, 1, function(row) {
      any(sapply(filtered_terms, function(term) {
        any(grepl(term, row, ignore.case = TRUE))
      }))
    })
    
    filtered <- data[match_rows, ]
    
    if (nrow(filtered) == 0) {
      cat("[SMART_FILTER] Eşleşme yok, ilk 100 satır\n")
      return(head(as.data.frame(data), 100))
    }
    
    cat(sprintf("[SMART_FILTER] Keyword sonuç: %d satır\n", nrow(filtered)))
    return(as.data.frame(head(filtered, 500)))
  }
  
  if (!filter_col %in% names(dt)) {
    cat(sprintf("[SMART_FILTER] Sütun '%s' yok, fallback\n", filter_col))
    return(as.data.frame(head(data, 100)))
  }
  
  cat(sprintf("[SMART_FILTER] Sütun '%s' filtreleniyor, işlem: %s\n", 
              filter_col, operation %||% "exact_match"))
  
  if (operation == "exact_match" || is.null(operation)) {
    dt <- dt[get(filter_col) == filter_val]
  } else if (operation == "contains") {
    dt <- dt[grepl(filter_val, get(filter_col), ignore.case = TRUE)]
  } else if (operation == "greater_than") {
    dt <- dt[get(filter_col) > as.numeric(filter_val)]
  } else if (operation == "less_than") {
    dt <- dt[get(filter_col) < as.numeric(filter_val)]
  }
  
  cat(sprintf("[SMART_FILTER] Filtreleme sonrası: %d satır\n", nrow(dt)))
  
  if (nrow(dt) == 0) {
    cat("[SMART_FILTER] Sonuç boş\n")
    return(data.frame())
  }
  
  if (!is.null(aggregation)) {
    if (aggregation == "count") {
      if (!is.null(group_col) && group_col %in% names(dt)) {
        result <- dt[, .N, by = group_col]
        setnames(result, "N", "Adet")
      } else {
        result <- data.frame(
          Metrik = "Toplam Kayıt Sayısı",
          Değer = nrow(dt)
        )
      }
      cat(sprintf("[SMART_FILTER] COUNT sonuç: %d satır\n", nrow(result)))
      return(as.data.frame(result))
    } else if (aggregation == "group_by" && !is.null(group_col) && group_col %in% names(dt)) {
      num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
      if (length(num_cols) > 0) {
        agg_expr <- lapply(num_cols, function(col) {
          list(sum(get(col), na.rm = TRUE))
        })
        names(agg_expr) <- paste0("Toplam_", num_cols)
        result <- dt[, c(.N, agg_expr), by = group_col]
        setnames(result, "N", "Kayıt_Sayısı")
      } else {
        result <- dt[, .N, by = group_col]
        setnames(result, "N", "Kayıt_Sayısı")
      }
      cat(sprintf("[SMART_FILTER] GROUP_BY sonuç: %d grup\n", nrow(result)))
      return(as.data.frame(result))
    } else if (aggregation == "list") {
      result <- head(dt, 500)
      cat(sprintf("[SMART_FILTER] LIST: %d satır\n", nrow(result)))
      return(as.data.frame(result))
    }
  }
  
  result <- head(dt, 500)
  cat(sprintf("[SMART_FILTER] Varsayılan: %d satır\n", nrow(result)))
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
  
  # A. Bağlantı Kur
  cat("[PK_ANALIZ] DB Baglantisi aliniyor...\n")
  conn_list <- get_connection()
  conn <- conn_list$conn
  on.exit({
    cat("[PK_ANALIZ] DB Baglantisi serbest birakiliyor.\n")
    release_connection(conn_list)
  })
  
  username <- session$userData$system_username %||% "Unknown"
  
  # B. Kullanıcı RLS Bilgisini Çek
  rls_info <- get_user_rls_info(username, conn)
  if (!isTRUE(rls_info$authorized)) {
    cat("[PK_ANALIZ] Yetki Hatasi: Kullanici bulunamadi.\n")
    return("⚠️ **Yetki Hatası:** Sistemde kullanıcı kaydınız (DC01_user_base) bulunamadı. Lütfen yönetici ile iletişime geçin.")
  }
  
  # C. Doğru Sorguyu Seç
  cat("[PK_ANALIZ] Akilli sorgu secimi yapiliyor (select_smart_query)...\n")
  selected_query <- select_smart_query(user_prompt, query_library, chat_history)
  
  if (is.null(selected_query)) {
    cat("[PK_ANALIZ] UYARI: Uygun bir sorgu ESLESMESI BULUNAMADI.\n")
    return("🤔 Aradığınız bilgi mevcut analiz kütüphanesinde bulunamadı. (Sorgu kütüphanesinde eşleşen anahtar kelime yok).")
  }
  
  cat(sprintf("[PK_ANALIZ] Secilen Sorgu: '%s' (Table: %s)\n", selected_query$name, selected_query$description))
   
  # 1. SQL İçeriğini Belirle (sql string veya sql_file dosyasından)
  sql_query_text <- ""

  # Oncelik: sql_file (Dosyadan oku)
  # Eger sql_file tanimliysa, sql metni yerine dosya icerigini kullanmayi zorla.
  if (!is.null(selected_query$sql_file) && nzchar(selected_query$sql_file)) {
    fpath <- selected_query$sql_file
    
    if (file.exists(fpath)) {
      cat(sprintf("[PK_ANALIZ] SQL dosyadan okunuyor: %s\n", fpath))
      
# Dosya içeriğini Binary (Raw) olarak oku
      f_con <- file(fpath, open = "rb")
      f_size <- file.info(fpath)$size
      if (is.na(f_size)) f_size <- 0
      raw_content <- readBin(f_con, "raw", n = f_size)
      close(f_con)
      
      sql_query_text <- ""
      
      if (length(raw_content) > 0) {
        # BOM Kontrolü (UTF-16 LE/BE)
        has_bom_le <- length(raw_content) >= 2 && raw_content[1] == as.raw(0xff) && raw_content[2] == as.raw(0xfe)
        has_bom_be <- length(raw_content) >= 2 && raw_content[1] == as.raw(0xfe) && raw_content[2] == as.raw(0xff)
        
        # Null Byte Varlığı (UTF-16 tespiti için)
        has_nulls <- any(raw_content == as.raw(0))
        
        if (has_bom_le) {
           sql_query_text <- iconv(list(raw_content), from = "UTF-16LE", to = "UTF-8")[[1]]
        } else if (has_bom_be) {
           sql_query_text <- iconv(list(raw_content), from = "UTF-16BE", to = "UTF-8")[[1]]
        } else if (has_nulls) {
           # BOM yok ama NULL var -> UTF-16. LE mi BE mi tahmini:
           # Eğer ilk byte NULL ise (ve ikincisi değilse) bu Big Endian (00 XX) yapısıdır.
           if (length(raw_content) >= 2 && raw_content[1] == as.raw(0) && raw_content[2] != as.raw(0)) {
              cat("[PK_ANALIZ] Dosya NULL byte içeriyor (BE tespiti), UTF-16BE deneniyor...\n")
              sql_query_text <- iconv(list(raw_content), from = "UTF-16BE", to = "UTF-8")[[1]]
           } else {
              cat("[PK_ANALIZ] Dosya NULL byte içeriyor, UTF-16LE deneniyor...\n")
              sql_query_text <- iconv(list(raw_content), from = "UTF-16LE", to = "UTF-8")[[1]]
           }
        } else {
           # UTF-8 veya WINDOWS-1254 (Türkçe) Kontrolü
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
      
      # Sadece UTF-8 BOM temizliği (Null temizliği kaldırıldı)
      sql_query_text <- gsub("^\ufeff", "", sql_query_text)
      
      cat(sprintf("[PK_ANALIZ] Okunan SQL uzunlugu: %d karakter\n", nchar(sql_query_text)))
      cat(sprintf("[PK_ANALIZ] SQL baslangici:\n%s\n[...]\n", substr(sql_query_text, 1, 200)))
      
    } else {
      cat(sprintf("[PK_ANALIZ] HATA: Belirtilen SQL dosyasi bulunamadi: %s\n", fpath))
      return(paste0("⚠️ **Yapılandırma Hatası:** SQL dosyası bulunamadı: ", fpath))
    }
  } 
  
  # Alternatif: sql (Direkt metin) - Sadece dosya tanimi yoksa ve metin bos ise buraya bak
  if (!nzchar(sql_query_text) && !is.null(selected_query$sql)) {
    sql_query_text <- selected_query$sql
  }

  # Hata Kontrolü: İçerik hala boş mu?
  if (!nzchar(sql_query_text)) {
    cat("[PK_ANALIZ] HATA: Ne sql_file ne de sql metni gecerli!\n")
    return("⚠️ **Yapılandırma Hatası:** Sorgu için SQL kodu bulunamadı.")
  }

	if (grepl("^[a-zA-Z]:[\\\\/]|^[\\\\/]{2}|^\\./|^\\.\\./|^[^/\\\\]+[\\\\/]", sql_query_text)) {
	  cat(sprintf("[PK_ANALIZ] KRITIK HATA: sql_query_text dosya yolu iceriyor!\n"))
	  cat(sprintf("[PK_ANALIZ] Icerik: %s\n", substr(sql_query_text, 1, 300)))
	  return("⚠️ **Sistem Hatası:** SQL sorgusu yüklenemedi (dosya yolu algılandı).")
	}

	if (nchar(sql_query_text) < 10 || !grepl("SELECT|INSERT|UPDATE|DELETE|EXEC", sql_query_text, ignore.case = TRUE)) {
	  cat(sprintf("[PK_ANALIZ] HATA: Gecersiz SQL icerigi!\n"))
	  cat(sprintf("[PK_ANALIZ] Icerik: %s\n", substr(sql_query_text, 1, 200)))
	  return("⚠️ **Sistem Hatası:** Geçersiz SQL sorgusu yüklendi.")
	}

	target_db <- selected_query$db_target

	if (!is.null(target_db) && target_db != "primary") {
	   cat(sprintf("[PK_ANALIZ] Hedef DB 'primary' degil (%s). Baglanti degistiriliyor...\n", target_db))
	   
	   release_connection(conn_list)
	   
	   conn_list <- get_connection(target = target_db)
	   conn <- conn_list$conn
	}

	final_sql <- trimws(sql_query_text)

	cat(sprintf("[PK_ANALIZ] SQL DB'ye gonderiliyor (Ilk 100 kar.):\n--> %s...\n", substr(final_sql, 1, 100)))

  raw_data <- tryCatch({
    # Güvenlik Kontrolü
    if (grepl("\\b(DELETE|DROP|TRUNCATE|ALTER)\\b", toupper(final_sql))) {
      stop("Guvenlik ihlali: Yasakli SQL komutu.")
    }
    
    # Sorguyu Çalıştır
    DBI::dbGetQuery(conn, final_sql)
    
  }, error = function(e) {
    cat(sprintf("[PK_ANALIZ] SQL HATASI: %s\n", e$message))
    return(paste0("⚠️ **Veritabanı Hatası:** Sorgu çalıştırılırken hata oluştu.\n`", e$message, "`"))
  })
  
  if (is.character(raw_data) && startsWith(raw_data, "⚠️")) return(raw_data)
  
  cat(sprintf("[PK_ANALIZ] SQL Basarili. Dönen Satir: %d\n", nrow(raw_data)))
  
  # E. RLS Uygula
  secure_data <- apply_rls_to_data(raw_data, rls_info, selected_query$rls_columns)
  cat(sprintf("[PK_ANALIZ] RLS sonrasi güvenli satir sayisi: %d\n", nrow(secure_data)))
  
  if (nrow(secure_data) == 0) {
    return(paste0("🔍 **Sonuç:** '", selected_query$name, "' sorgusu çalıştırıldı ancak yetkiniz dahilinde görüntülenecek veri bulunamadı."))
  }
  
  # F. YENİ: AKıLLı FİLTRELEME (AI-Guided)
  filter_criteria <- extract_filter_criteria_from_prompt(
    user_prompt,
    available_columns = names(secure_data),
    conn = conn
  )
  
  filtered_data <- apply_smart_filters(secure_data, filter_criteria, user_prompt)
  
  cat(sprintf("[PK_ANALIZ] Akıllı filtreleme sonrası: %d satır (Orjinal: %d)\n", 
              nrow(filtered_data), nrow(secure_data)))
  
  if (nrow(filtered_data) == 0) {
    return(paste0("🔍 **Sonuç:** Filtreleme sonrası veri bulunamadı. Sorgunuz: '", user_prompt, "'"))
  }
  
  # G. AI Analizi Hazırlığı
  data_preview <- filtered_data
  
  if (nrow(data_preview) > 200) {
    data_preview <- head(data_preview, 200)
    cat("[PK_ANALIZ] UYARI: Sonuç 200 satıra kırpıldı (context koruma)\n")
  }
  
  # JSON'a çevir
  data_str <- jsonlite::toJSON(data_preview, auto_unbox = TRUE, pretty = TRUE)
  
  # LLM'e not ekle
  if (nrow(secure_data) > nrow(data_preview)) {
    msg <- sprintf("\n\n(Not: Veri seti toplam %d satırdır. Kullanıcı sorusuyla eşleşen satırlar ve örnek veri olmak üzere %d satır analiz için seçilmiştir.)", 
                   nrow(secure_data), nrow(data_preview))
    data_str <- paste0(data_str, msg)
  }
  
  system_prompt <- paste0(
    "Sen MERGEN Bilge analiz asistanısın. Kullanıcının sorusuna, sağlanan veriyi analiz ederek cevap ver.\n",
    "Kullanılan Sorgu: ", selected_query$name, "\n",
    "Sorgu Açıklaması: ", selected_query$description, "\n\n",
    "ÖNEMLİ: Sana GÖNDERİLEN VERİ ZATEN FİLTRELENMİŞTİR. Yani bu veri kullanıcının sorusuna tam olarak uygun satırları içerir.\n",
    "Örnek: Eğer 'Kaç proje var?' diye sorulduysa, sana gönderilen veri toplam sayıyı içerir.\n",
    "Örnek: Eğer 'P4578 projesinin adı ne?' diye sorulduysa, sana SADECE o proje satırı gelir.\n\n",
    "GÖREVLER:\n",
    "1. Verilen JSON verisini incele.\n",
    "2. Kullanıcının sorusuna DOĞRUDAN, NET ve TÜRKÇE cevap ver.\n",
    "3. Eğer veri tek satırsa (örn: proje adı sorusu), o satırı kullan.\n",
    "4. Eğer veri agregasyonsa (örn: count sonucu), o sayıyı kullan.\n",
    "5. Cevabını Markdown formatında ver.\n",
    "6. VERİYE DAYANMAYAN BİLGİ UYDURMA. Sadece gördüğün veriyi kullan.\n"
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
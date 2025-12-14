# R/module_proje_kaynak_analizi.R

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
  
  # D. Sorguyu Çalıştır
  cat("[PK_ANALIZ] SQL calistiriliyor...\n")
  raw_data <- tryCatch({
    if (grepl("\\b(DELETE|DROP|TRUNCATE|ALTER)\\b", toupper(selected_query$sql))) {
      stop("Guvenlik ihlali: Yasakli SQL komutu.")
    }
    DBI::dbGetQuery(conn, selected_query$sql)
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
  
  # F. AI Analizi Hazırlığı
  
  # 1. Akıllı Filtreleme: Kullanıcının sorusundaki anahtar kelimeleri veri setinde arayalım.
  # Bu sayede 2000+ satırı LLM'e göndermek yerine, sadece alakalı satırları seçeriz.
  
  search_terms <- unlist(strsplit(user_prompt, "\\s+"))
  # Temizlik: Noktalama işaretlerini kaldır, küçük harfe çevir
  search_terms <- tolower(gsub("[[:punct:]]", "", search_terms))
  # Çok kısa kelimeleri (ve, ile, vb.) filtrele, ancak sayıları (ID) koru
  search_terms <- search_terms[nchar(search_terms) >= 2]
  
  # Filtreleme Mantığı
  if (nrow(secure_data) > 0 && length(search_terms) > 0) {
    # Performans için geçici bir text tablosu oluştur
    data_txt <- as.data.frame(lapply(secure_data, function(x) tolower(as.character(x))), stringsAsFactors = FALSE)
    
    matched_indices <- c()
    
    # Her bir arama terimi için sütunları tara
    for (term in search_terms) {
      for (col in names(data_txt)) {
        # 'fixed = TRUE' ile tam metin araması (Regex değil, hız için)
        matches <- which(grepl(term, data_txt[[col]], fixed = TRUE))
        matched_indices <- c(matched_indices, matches)
      }
    }
    
    # Tekrar edenleri temizle
    matched_indices <- unique(matched_indices)
    
    # LLM'e gönderilecek satırları belirle:
    # 1. İlk 5 satır (Tablo yapısını anlaması için her zaman gerekli)
    # 2. Eşleşen satırlar (Sorunun cevabını içerenler)
    rows_to_keep <- unique(c(1:min(5, nrow(secure_data)), matched_indices))
    rows_to_keep <- sort(rows_to_keep)
    
    # Güvenlik Limiti: Eğer çok fazla eşleşme varsa LLM context'ini patlatma (Max 150 satır)
    MAX_AI_ROWS <- 150
    if (length(rows_to_keep) > MAX_AI_ROWS) {
      rows_to_keep <- head(rows_to_keep, MAX_AI_ROWS)
    }
    
    data_preview <- secure_data[rows_to_keep, , drop = FALSE]
    
  } else {
    # Arama terimi yoksa veya veri boşsa varsayılan ilk 50 satırı al
    data_preview <- head(secure_data, 50)
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
    "Sorgu Açıklaması: ", selected_query$description, "\n",
    "GÖREVLER:\n",
    "1. Verilen JSON verisini incele.\n",
    "2. Kullanıcının sorusuna doğrudan, net ve Türkçe cevap ver.\n",
    "3. Veri üzerinden içgörüler (insight) çıkar.\n",
    "4. Cevabını Markdown formatında ver. Tablo gerekiyorsa Markdown tablosu oluştur.\n",
    "5. Veriye dayanmayan bilgi uydurma.\n"
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
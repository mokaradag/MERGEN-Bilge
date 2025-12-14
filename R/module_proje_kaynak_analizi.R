# R/module_proje_kaynak_analizi.R

# ==============================================================================
# 1. RLS ve YETKİ YÖNETİMİ (SECURITY ENGINE)
# ==============================================================================

get_user_rls_info <- function(username, conn) {
  # 1. DC01_user_base tablosundan temel yetkileri çek
  # Columns: KullaniciAdi, KaynakAdi, MasrafYeriKodu, Yetki
  base_query <- "SELECT TOP 1 * FROM DC01_user_base WHERE KullaniciAdi = ?"
  user_base <- DBI::dbGetQuery(conn, base_query, params = list(username))
  
  if (nrow(user_base) == 0) {
    return(list(authorized = FALSE, reason = "Kullanıcı DC01 tablosunda bulunamadı."))
  }
  
  info <- as.list(user_base[1, ])
  info$authorized <- TRUE
  
  # Masraf Yeri (Department) Parse Et (Virgülle ayrılmış olabilir)
  if (!is.na(info$MasrafYeriKodu) && info$MasrafYeriKodu != "ADMIN") {
    info$allowed_depts <- trimws(unlist(strsplit(as.character(info$MasrafYeriKodu), ",")))
  } else {
    info$allowed_depts <- NULL # ADMIN veya hepsi
  }
  
  # 2. Yetki Tipine Göre Ek Kısıtlamaları (PY, KY-P, DIR-P) Çek
  info$allowed_projects <- NULL
  info$allowed_eps <- NULL
  
  # PY (Proje Yöneticisi) ise Proje Listesini Çek
  if (info$Yetki == "PY") {
    # library_queries.R içindeki sql_permission_py kullanılır
    py_res <- tryCatch(DBI::dbGetQuery(conn, sql_permission_py), error = function(e) NULL)
    if (!is.null(py_res)) {
      # İlgili kullanıcıyı bul
      user_rows <- py_res[py_res$KullaniciAdi == username, ]
      if (nrow(user_rows) > 0) {
        # ProjeKodu virgülle ayrılmış olabilir, hepsini birleştir ve temizle
        all_projs <- paste(user_rows$ProjeKodu, collapse = ",")
        info$allowed_projects <- unique(trimws(unlist(strsplit(all_projs, ","))))
      }
    }
  }
  
  # KY-P veya DIR-P ise EPS Listesini Çek
  if (info$Yetki %in% c("KY-P", "DIR-P")) {
    # library_queries.R içindeki sql_permission_eps kullanılır
    eps_res <- tryCatch(DBI::dbGetQuery(conn, sql_permission_eps), error = function(e) NULL)
    if (!is.null(eps_res)) {
      user_rows <- eps_res[eps_res$KullaniciAdi == username, ]
      if (nrow(user_rows) > 0) {
        all_eps <- paste(user_rows$EPSKodu, collapse = ",")
        info$allowed_eps <- unique(trimws(unlist(strsplit(all_eps, ","))))
      }
    }
  }
  
  return(info)
}

apply_rls_to_data <- function(data, user_info, rls_cols) {
  # Veri boşsa direkt dön
  if (nrow(data) == 0) return(data)
  
  filtered_data <- data
  yetki <- user_info$Yetki
  
  # 1. ADMIN: Kısıtlama yok
  if (yetki == "ADMIN") {
    return(filtered_data)
  }
  
  # 2. Masraf Yeri Filtresi (Tüm roller için MasrafYeriKodu varsa uygulanır)
  # Eğer kullanıcıda MasrafYeriKodu tanımlıysa ve sorguda ilgili sütun varsa
  if (!is.null(user_info$allowed_depts) && !is.null(rls_cols$masraf_yeri_col)) {
    col_name <- rls_cols$masraf_yeri_col
    if (col_name %in% names(filtered_data)) {
      # Virgülle ayrılmış çoklu değer desteği için %in% kullanılır
      filtered_data <- filtered_data[filtered_data[[col_name]] %in% user_info$allowed_depts, ]
    }
  }
  
  # 3. PY (Proje Yöneticisi) Filtresi
  if (yetki == "PY" && !is.null(user_info$allowed_projects) && !is.null(rls_cols$proje_kodu_col)) {
    col_name <- rls_cols$proje_kodu_col
    if (col_name %in% names(filtered_data)) {
      filtered_data <- filtered_data[filtered_data[[col_name]] %in% user_info$allowed_projects, ]
    }
  }
  
  # 4. KY-P / DIR-P (Program) Filtresi
  if (yetki %in% c("KY-P", "DIR-P") && !is.null(user_info$allowed_eps) && !is.null(rls_cols$eps_kodu_col)) {
    col_name <- rls_cols$eps_kodu_col
    if (col_name %in% names(filtered_data)) {
      filtered_data <- filtered_data[filtered_data[[col_name]] %in% user_info$allowed_eps, ]
    }
  }
  
  return(filtered_data)
}

# ==============================================================================
# 2. SORGULAMA MOTORU (EXECUTION ENGINE)
# ==============================================================================

pk_analiz_process_request <- function(user_prompt, chat_history, session) {
  
  # A. Bağlantı Kur
  conn_list <- get_connection()
  conn <- conn_list$conn
  on.exit(release_connection(conn_list))
  
  username <- session$userData$system_username %||% "Unknown"
  
  # B. Kullanıcı RLS Bilgisini Çek
  rls_info <- get_user_rls_info(username, conn)
  if (!isTRUE(rls_info$authorized)) {
    return("⚠️ **Yetki Hatası:** Sistemde kullanıcı kaydınız (DC01_user_base) bulunamadı. Lütfen yönetici ile iletişime geçin.")
  }
  
  # C. Doğru Sorguyu Seç (Akıllı Seçim)
  selected_query <- select_smart_query(user_prompt, query_library, chat_history)
  
  if (is.null(selected_query)) {
    # Fallback: MindsDB (Şimdilik yer tutucu)
    return("🤔 Aradığınız bilgi mevcut analiz kütüphanesinde bulunamadı. (MindsDB entegrasyonu gelecek güncellemede eklenecektir).")
  }
  
  # D. Sorguyu Çalıştır (Tüm veri gelir)
  raw_data <- tryCatch({
    # UPDATE/DELETE gibi tehlikeli işlemleri basitçe kontrol et (Basit güvenlik)
    if (grepl("\\b(DELETE|DROP|TRUNCATE|ALTER)\\b", toupper(selected_query$sql))) {
      stop("Güvenlik ihlali: İzin verilmeyen sorgu tipi.")
    }
    DBI::dbGetQuery(conn, selected_query$sql)
  }, error = function(e) {
    return(paste0("⚠️ **Veritabanı Hatası:** Sorgu çalıştırılırken hata oluştu.\n`", e$message, "`"))
  })
  
  if (is.character(raw_data) && startsWith(raw_data, "⚠️")) return(raw_data) # Hata durumu
  
  # E. RLS Uygula (Veriyi süz)
  secure_data <- apply_rls_to_data(raw_data, rls_info, selected_query$rls_columns)
  
  if (nrow(secure_data) == 0) {
    return(paste0("🔍 **Sonuç:** '", selected_query$name, "' sorgusu çalıştırıldı ancak yetkiniz dahilinde görüntülenecek veri bulunamadı."))
  }
  
  # F. AI Analizi ve Yanıt Üretme
  # Veriyi JSON veya Markdown tablo formatına çevirip LLM'e yorumlatacağız
  
  # Çok büyük veriyi AI'a göndermemek için ilk N satırı veya özetini alalım
  # (Kullanıcı 'tüm kolonları' sordu mu? AI karar versin diye tüm kolonları veriyoruz ama satır limiti koyuyoruz)
  row_limit <- 100 
  data_preview <- head(secure_data, row_limit)
  
  data_str <- jsonlite::toJSON(data_preview, auto_unbox = TRUE, pretty = TRUE)
  if (nrow(secure_data) > row_limit) {
    data_str <- paste0(data_str, "\n\n(Not: Toplam ", nrow(secure_data), " satır var, sadece ilk ", row_limit, " satır analiz için gönderildi.)")
  }
  
  system_prompt <- paste0(
    "Sen MERGEN Bilge analiz asistanısın. Kullanıcının sorusuna, sağlanan veriyi analiz ederek cevap ver.\n",
    "Kullanılan Sorgu: ", selected_query$name, "\n",
    "Sorgu Açıklaması: ", selected_query$description, "\n",
    "GÖREVLER:\n",
    "1. Verilen JSON verisini incele.\n",
    "2. Kullanıcının sorusuna doğrudan, net ve Türkçe cevap ver.\n",
    "3. Veri üzerinden içgörüler (insight) çıkar. (Örn: 'X projesi bütçeyi aşmış görünüyor' gibi).\n",
    "4. Cevabını Markdown formatında ver. Tablo gerekiyorsa Markdown tablosu oluştur.\n",
    "5. Eğer veri boşsa veya soruyla alakasızsa bunu belirt.\n"
  )
  
  user_msg <- paste0("Soru: ", user_prompt, "\n\nVeri Seti:\n", data_str)
  
  # LLM Çağrısı (aiProcessingServer modülündeki fonksiyonları kullanamıyoruz çünkü burası server tarafı değil,
  # ama helper fonksiyonlarını doğrudan çağırabiliriz veya global'deki call_llm_worker benzeri bir yapı kullanabiliriz.
  # Basitlik adına burada doğrudan server.R içinden erişilen bir yapıyı simüle edeceğiz veya 'call_llm_worker' kullanacağız.)
  
  # Not: Bu fonksiyon bir 'future' (arkaplan işlemi) içinde çalıştırılmalıdır.
  # Ancak modüler yapı gereği sonucu string olarak döndürüyoruz.
  # LLM çağrısını burada simüle ediyoruz (Gerçek implementasyonda global 'call_llm_worker' kullanılır).
  
  return(list(
    type = "data_analysis",
    data = secure_data, # İleride tablo çizdirmek için ham veri
    prompt_context = system_prompt,
    user_context = user_msg,
    query_name = selected_query$name
  ))
}

# ==============================================================================
# 3. AKILLI SORGU SEÇİMİ (HEURISTIC + AI)
# ==============================================================================

select_smart_query <- function(prompt, library, history) {
  # Basit Heuristik: Kullanıcı promptu içindeki kelimeler ile sorgu description'larını eşleştir
  # (İleride burası LLM tabanlı bir 'Routing' mekanizmasına dönüşebilir)
  
  # Şimdilik: LLM'e sormak maliyetli olabilir, basit kelime eşleşmesi (puanlama) yapalım.
  # VEYA Kullanıcı isteğine göre: "I think it is better for ai to decide"
  # O zaman LLM Routing yapalım.
  
  scores <- sapply(library, function(q) {
    # Basit bir metin benzerliği (Jaccard veya string contains)
    desc_words <- unlist(strsplit(tolower(q$description), "\\W+"))
    prompt_words <- unlist(strsplit(tolower(prompt), "\\W+"))
    name_words <- unlist(strsplit(tolower(q$name), "\\W+"))
    
    match_count <- sum(prompt_words %in% c(desc_words, name_words))
    return(match_count)
  })
  
  best_idx <- which.max(scores)
  
  if (scores[best_idx] > 0) {
    # En az bir kelime eşleştiyse
    return(library[[best_idx]])
  }
  
  return(NULL) # Eşleşme yok
}
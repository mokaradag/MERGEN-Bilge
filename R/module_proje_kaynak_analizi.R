# R/module_proje_kaynak_analizi.R

# ==============================================================================
# 0. AKıLLı FİLTRELEME MOTORü (AI-Guided Filtering Engine)
# ==============================================================================

extract_filter_criteria_from_prompt <- function(user_prompt, available_columns, conn) {
  cat(sprintf("[FILTER_AI] Prompt analiz ediliyor: '%s'\n", user_prompt))
  
  cols_str <- paste(available_columns, collapse = ", ")
  
  system_instruction <- paste0(
    "Sen Primavera P6 proje yönetim sisteminde veri filtreleme uzmanısın.\n\n",
    "MEVCUT SÜTUNLAR: ", cols_str, "\n\n",
    "ÇIKTI FORMATI (SADECE JSON, HİÇBİR EK AÇIKLAMA YOK):\n",
    "{\n",
    "  \"filter_column\": \"SütunAdı\",\n",
    "  \"filter_value\": \"AranacakDeğer\",\n",
    "  \"operation\": \"exact_match\",\n",
    "  \"aggregation\": \"count\",\n",
    "  \"group_column\": null\n",
    "}\n\n",
    "SÜTUN SEÇİMİ KURALLARI:\n",
    "- Proje kodu (P1111, PRJ-001): ProjeKodu, Proje_Kodu, ProjectCode, project_id\n",
    "- Proje adı: ProjeAdi, Proje_Adi, ProjeIsmi, ProjectName, project_name\n",
    "- Kaynak kodu/adı: KaynakKodu, Kaynak_Kodu, KaynakAdi, ResourceCode, resource_name\n",
    "- Faaliyet kodu/adı: FaaliyetKodu, Faaliyet_Kodu, ActivityCode, task_name\n",
    "- Departman: Departman, Department, Birim\n",
    "- Durum: Durum, Status, ProjectStatus, proje_durumu\n",
    "- Bütçe: Butce, Budget, BütçeTutarı, budget_amount\n",
    "- Tarih: BaslangicTarihi, BitisTarihi, StartDate, FinishDate\n",
    "- Yönetici: ProjeYoneticisi, Yönetici, ProjectManager, manager_name\n",
    "- WBS: WBSKodu, WBS_Kodu, WBSAdi\n",
    "\n",
    "OPERATION SEÇİMİ:\n",
    "- Kod/ID eşleşmesi (P1111, RES-001): exact_match\n",
    "- Ad/metin araması (içeren): contains\n",
    "- Sayısal karşılaştırma (büyük/küçük): greater_than, less_than\n",
    "\n",
    "AGGREGATION SEÇİMİ:\n",
    "- 'kaç', 'toplam sayı', 'adet': count\n",
    "- 'listele', 'göster', 'özetle': list\n",
    "- 'topla', 'sum', 'toplam tutar': sum\n",
    "- 'grupla', 'kırılımında', 'dağılımı': group_by (group_column belirt)\n",
    "- 'ortalama': mean\n",
    "\n",
    "GROUP_COLUMN SEÇİMİ (aggregation='group_by' ise):\n",
    "- 'departman bazında': Departman\n",
    "- 'durum bazında': Durum\n",
    "- 'yönetici bazında': ProjeYoneticisi\n",
    "- 'kaynak bazında': KaynakAdi\n",
    "\n",
    "ÖRNEKLER:\n",
    "Soru: 'P1111 proje kodlu projeyi özetle'\n",
    "→ {\"filter_column\":\"ProjeKodu\",\"filter_value\":\"P1111\",\"operation\":\"exact_match\",\"aggregation\":\"list\",\"group_column\":null}\n\n",
    "Soru: 'Kaç proje aktif durumda?'\n",
    "→ {\"filter_column\":\"Durum\",\"filter_value\":\"Aktif\",\"operation\":\"exact_match\",\"aggregation\":\"count\",\"group_column\":null}\n\n",
    "Soru: 'Ali Veli isimli kaynak hangi projelerde çalışıyor?'\n",
    "→ {\"filter_column\":\"KaynakAdi\",\"filter_value\":\"Ali Veli\",\"operation\":\"contains\",\"aggregation\":\"list\",\"group_column\":null}\n\n",
    "Soru: 'Departman bazında toplam bütçe nedir?'\n",
    "→ {\"filter_column\":null,\"filter_value\":null,\"operation\":\"exact_match\",\"aggregation\":\"group_by\",\"group_column\":\"Departman\"}\n\n",
    "Soru: 'İnşaat kelimesini içeren projeleri listele'\n",
    "→ {\"filter_column\":\"ProjeAdi\",\"filter_value\":\"İnşaat\",\"operation\":\"contains\",\"aggregation\":\"list\",\"group_column\":null}\n\n",
    "SADECE JSON DÖNDÜR, BAŞKA HİÇBİR ŞEY YAZMA."
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
    
    if (is.null(result)) {
      cat("[FILTER_AI] result NULL, fallback\n")
      return(list(filter_column = NULL, aggregation = NULL))
    }
    
    ai_content <- if (is.list(result)) result$content else result
    
    if (is.null(ai_content) || !is.character(ai_content) || length(ai_content) == 0) {
      cat("[FILTER_AI] content NULL veya invalid, fallback\n")
      return(list(filter_column = NULL, aggregation = NULL))
    }
    
    ai_text <- as.character(ai_content)[1]
    ai_text <- gsub("```json|```", "", ai_text)
    ai_text <- trimws(ai_text)
    
    if (!nzchar(ai_text)) {
      cat("[FILTER_AI] AI boş yanıt verdi, fallback\n")
      return(list(filter_column = NULL, aggregation = NULL))
    }
    
    cat(sprintf("[FILTER_AI] AI yanıtı: %s\n", substr(ai_text, 1, 200)))
    
    parsed <- tryCatch(
      jsonlite::fromJSON(ai_text, simplifyVector = FALSE),
      error = function(e) {
        cat(sprintf("[FILTER_AI] JSON parse hatası: %s\n", e$message))
        NULL
      }
    )
    
    if (is.null(parsed) || !is.list(parsed)) {
      cat("[FILTER_AI] parsed NULL veya list degil, fallback\n")
      return(list(filter_column = NULL, aggregation = NULL))
    }
    
    fc <- parsed$filter_column
    fv <- parsed$filter_value
    op <- parsed$operation
    ag <- parsed$aggregation
    gc <- parsed$group_column
    
    if (!is.null(fc) && is.character(fc) && length(fc) > 0) {
      fc <- as.character(fc)[1]
    } else {
      fc <- NULL
    }
    
    if (!is.null(fv) && length(fv) > 0) {
      fv <- as.character(fv)[1]
    } else {
      fv <- NULL
    }
    
    if (!is.null(op) && is.character(op) && length(op) > 0) {
      op <- as.character(op)[1]
    } else {
      op <- "exact_match"
    }
    
    if (!is.null(ag) && is.character(ag) && length(ag) > 0) {
      ag <- as.character(ag)[1]
    } else {
      ag <- NULL
    }
    
    if (!is.null(gc) && is.character(gc) && length(gc) > 0) {
      gc <- as.character(gc)[1]
    } else {
      gc <- NULL
    }
    
    result_list <- list(
      filter_column = fc,
      filter_value = fv,
      operation = op,
      aggregation = ag,
      group_column = gc
    )
    
    cat(sprintf("[FILTER_AI] Başarılı: filter_column=%s, value=%s, op=%s, agg=%s\n",
                fc %||% "NULL", fv %||% "NULL", op %||% "NULL", ag %||% "NULL"))
    
    return(result_list)
    
  }, error = function(e) {
    cat(sprintf("[FILTER_AI] Genel hata: %s\n", e$message))
    cat(sprintf("[FILTER_AI] Stack trace:\n"))
    print(sys.calls())
    return(list(filter_column = NULL, aggregation = NULL))
  })
}

apply_smart_filters <- function(data, filter_instructions, user_prompt) {
  cat(sprintf("[SMART_FILTER] Başlangıç satır: %d\n", nrow(data)))
  
  if (nrow(data) == 0) return(data.frame())
  
  dt <- data.table::as.data.table(data)
  
  filter_col <- filter_instructions$filter_column
  filter_val <- filter_instructions$filter_value
  operation <- filter_instructions$operation %||% "exact_match"
  aggregation <- filter_instructions$aggregation
  group_col <- filter_instructions$group_column
  
  if (is.null(filter_col) || !nzchar(as.character(filter_col)[1])) {
    cat("[SMART_FILTER] AI filtresi yok, keyword fallback\n")
    
    matches <- regmatches(user_prompt, gregexpr("\\b[A-Za-z0-9-]{3,}\\b", user_prompt))
    search_terms <- unique(unlist(matches))
    
    filtered_terms <- c()
    for (term in search_terms) {
      if ((grepl("[A-Za-z]", term) && grepl("[0-9]", term)) || 
          (nchar(term) >= 4 && grepl("^[A-Z0-9-]+$", toupper(term)))) {
        filtered_terms <- c(filtered_terms, term)
      }
    }
    
    if (!length(filtered_terms)) {
      cat("[SMART_FILTER] Keyword bulunamadı, tüm veri döndürülüyor\n")
      return(as.data.frame(head(dt, 500)))
    }
    
    cat(sprintf("[SMART_FILTER] Aranan: %s\n", paste(filtered_terms, collapse = ", ")))
    
    match_rows <- apply(dt, 1, function(row) {
      any(sapply(filtered_terms, function(term) {
        any(grepl(term, row, ignore.case = TRUE))
      }))
    })
    
    filtered <- dt[match_rows, ]
    
    if (nrow(filtered) == 0) {
      cat("[SMART_FILTER] Eşleşme yok, ilk 100 satır\n")
      return(as.data.frame(head(dt, 100)))
    }
    
    cat(sprintf("[SMART_FILTER] Keyword sonuç: %d satır\n", nrow(filtered)))
    return(as.data.frame(head(filtered, 500)))
  }
  
  filter_col_str <- as.character(filter_col)[1]
  
  if (!filter_col_str %in% names(dt)) {
    cat(sprintf("[SMART_FILTER] '%s' sütunu yok, tüm sütunlarda ara\n", filter_col_str))
    
    if (!is.null(filter_val) && nzchar(as.character(filter_val)[1])) {
      fv_str <- as.character(filter_val)[1]
      match_rows <- apply(dt, 1, function(row) {
        any(grepl(fv_str, row, ignore.case = TRUE))
      })
      dt <- dt[match_rows, ]
      cat(sprintf("[SMART_FILTER] Tüm sütunlarda '%s' arandı: %d satır\n", fv_str, nrow(dt)))
    }
    
    if (nrow(dt) == 0) {
      return(data.frame())
    }
  } else {
    if (!is.null(filter_val) && nzchar(as.character(filter_val)[1])) {
      fv_str <- as.character(filter_val)[1]
      
      cat(sprintf("[SMART_FILTER] '%s' sütununda '%s' aranıyor (op: %s)\n", 
                  filter_col_str, fv_str, operation))
      
      if (operation == "exact_match") {
        dt <- dt[get(filter_col_str) == fv_str]
      } else if (operation == "contains") {
        dt <- dt[grepl(fv_str, get(filter_col_str), ignore.case = TRUE)]
      } else if (operation == "greater_than") {
        dt <- dt[get(filter_col_str) > as.numeric(fv_str)]
      } else if (operation == "less_than") {
        dt <- dt[get(filter_col_str) < as.numeric(fv_str)]
      } else {
        dt <- dt[grepl(fv_str, get(filter_col_str), ignore.case = TRUE)]
      }
      
      cat(sprintf("[SMART_FILTER] Filtreleme sonrası: %d satır\n", nrow(dt)))
    }
  }
  
  if (nrow(dt) == 0) {
    cat("[SMART_FILTER] Filtre sonucu boş\n")
    return(data.frame())
  }
  
  if (!is.null(aggregation) && nzchar(as.character(aggregation)[1])) {
    agg_str <- as.character(aggregation)[1]
    
    if (agg_str == "count") {
      if (!is.null(group_col) && nzchar(as.character(group_col)[1]) && 
          as.character(group_col)[1] %in% names(dt)) {
        gc_str <- as.character(group_col)[1]
        result <- dt[, .N, by = gc_str]
        setnames(result, "N", "Adet")
        cat(sprintf("[SMART_FILTER] COUNT+GROUP: %d grup\n", nrow(result)))
        return(as.data.frame(result))
      } else {
        result <- data.frame(
          Metrik = "Toplam Kayıt Sayısı",
          Değer = nrow(dt)
        )
        cat(sprintf("[SMART_FILTER] COUNT: %d kayıt\n", nrow(dt)))
        return(result)
      }
    } else if (agg_str == "group_by" && !is.null(group_col) && 
               nzchar(as.character(group_col)[1]) && 
               as.character(group_col)[1] %in% names(dt)) {
      gc_str <- as.character(group_col)[1]
      num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
      
      if (length(num_cols) > 0) {
        agg_expr <- lapply(num_cols, function(col) {
          list(sum(get(col), na.rm = TRUE))
        })
        names(agg_expr) <- paste0("Toplam_", num_cols)
        result <- dt[, c(.N, agg_expr), by = gc_str]
        setnames(result, "N", "Kayıt_Sayısı")
      } else {
        result <- dt[, .N, by = gc_str]
        setnames(result, "N", "Kayıt_Sayısı")
      }
      
      cat(sprintf("[SMART_FILTER] GROUP_BY: %d grup\n", nrow(result)))
      return(as.data.frame(result))
    }
  }
  
  result <- head(dt, 500)
  cat(sprintf("[SMART_FILTER] Sonuç: %d satır (limit: 500)\n", nrow(result)))
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
  
  secure_data <- apply_rls_to_data(raw_data, rls_info, selected_query$rls_columns)
  cat(sprintf("[PK_ANALIZ] RLS sonrası: %d satır\n", nrow(secure_data)))
  
  if (nrow(secure_data) == 0) {
    return(paste0("🔍 **Sonuç:** Sorgu çalıştırıldı ancak yetkiniz dahilinde veri bulunamadı."))
  }
  
  filter_criteria <- extract_filter_criteria_from_prompt(
    user_prompt,
    available_columns = names(secure_data),
    conn = conn
  )
  
  filtered_data <- apply_smart_filters(secure_data, filter_criteria, user_prompt)
  
  cat(sprintf("[PK_ANALIZ] Filtreleme sonrası: %d satır (Orijinal: %d)\n", 
              nrow(filtered_data), nrow(secure_data)))
  
  if (nrow(filtered_data) == 0) {
    return(paste0("🔍 **Sonuç:** Filtreleme sonrası veri bulunamadı."))
  }
  
  data_preview <- filtered_data
  original_row_count <- nrow(filtered_data)
  
  if (nrow(data_preview) > 100) {
    num_cols <- names(data_preview)[vapply(data_preview, is.numeric, logical(1))]
    char_cols <- names(data_preview)[vapply(data_preview, function(x) is.character(x) || is.factor(x), logical(1))]
    
    stats_summary <- NULL
    
    if (length(num_cols) > 0) {
      stats_list <- lapply(num_cols, function(col) {
        vals <- data_preview[[col]]
        data.frame(
          Sütun = col,
          Ortalama = mean(vals, na.rm = TRUE),
          Medyan = median(vals, na.rm = TRUE),
          Min = suppressWarnings(min(vals, na.rm = TRUE)),
          Max = suppressWarnings(max(vals, na.rm = TRUE)),
          Toplam = sum(vals, na.rm = TRUE),
          Kayıt_Sayısı = sum(!is.na(vals)),
          stringsAsFactors = FALSE
        )
      })
      stats_summary <- do.call(rbind, stats_list)
    }
    
    cat_summary <- NULL
    if (length(char_cols) > 0) {
      cat_list <- lapply(char_cols[1:min(3, length(char_cols))], function(col) {
        tbl <- sort(table(data_preview[[col]]), decreasing = TRUE)
        top5 <- head(tbl, 5)
        data.frame(
          Sütun = col,
          En_Sık_Değer = names(top5)[1],
          Adet = as.integer(top5[1]),
          Benzersiz_Sayı = length(unique(data_preview[[col]])),
          stringsAsFactors = FALSE
        )
      })
      cat_summary <- do.call(rbind, cat_list)
    }
    
    top_rows <- head(data_preview, 20)
    
    summary_text <- paste0(
      "VERİ ÖZETİ (Toplam ", original_row_count, " satır):\n\n"
    )
    
    if (!is.null(stats_summary)) {
      summary_text <- paste0(summary_text, "SAYISAL SÜTUN İSTATİSTİKLERİ:\n",
                             paste(capture.output(print(stats_summary, row.names = FALSE)), collapse = "\n"),
                             "\n\n")
    }
    
    if (!is.null(cat_summary)) {
      summary_text <- paste0(summary_text, "KATEGORİK SÜTUN ÖZETİ:\n",
                             paste(capture.output(print(cat_summary, row.names = FALSE)), collapse = "\n"),
                             "\n\n")
    }
    
    summary_text <- paste0(summary_text, "İLK 20 SATIR:\n",
                           paste(capture.output(print(top_rows, row.names = FALSE)), collapse = "\n"))
    
    data_str <- summary_text
    cat("[PK_ANALIZ] Veri çok büyük, istatistiksel özet gönderildi\n")
    
  } else {
    data_str <- jsonlite::toJSON(data_preview, auto_unbox = TRUE, pretty = TRUE)
    cat(sprintf("[PK_ANALIZ] %d satır JSON olarak gönderiliyor\n", nrow(data_preview)))
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
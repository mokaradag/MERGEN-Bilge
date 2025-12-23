# R/module_proje_kaynak_analizi.R

# ==============================================================================
# 0. AKıLLı FİLTRELEME MOTORü (AI-Guided Filtering Engine)
# ==============================================================================

# AI icin sutun ozetleri olusturan yardimci fonksiyon
summarize_columns_for_ai <- function(df) {
  if (is.null(df) || nrow(df) == 0) return("")
  
  summary_list <- lapply(names(df), function(col) {
    vals <- df[[col]]
    if (all(is.na(vals))) return(sprintf("- %s: (Hepsi NULL)", col))
    
    if (is.numeric(vals)) {
      # Sayisal degerler: istatistiksel özet
      valid_vals <- vals[!is.na(vals)]
      if (length(valid_vals) == 0) return(sprintf("- %s: (Sayısal, veri yok)", col))
      
      return(sprintf("- %s: (Sayısal, Min: %s, Maks: %s, Ort: %.2f, Kayıt: %d)", 
                     col, 
                     min(valid_vals), 
                     max(valid_vals),
                     mean(valid_vals),
                     length(valid_vals)))
    } else if (inherits(vals, "Date") || inherits(vals, "POSIXt")) {
      # Tarih degerleri icin aralik
      return(sprintf("- %s: (Tarih, Aralık: %s - %s)", col, min(vals, na.rm=TRUE), max(vals, na.rm=TRUE)))
    } else {
      # Kategorik degerler icin unique listesi
      u_vals <- unique(na.omit(as.character(vals)))
      # Okunabilirlik icin sirala
      u_vals <- sort(u_vals)
      if (length(u_vals) <= 20) {
        return(sprintf("- %s: [%s]", col, paste(u_vals, collapse = ", ")))
      } else {
        return(sprintf("- %s: [%s, ... (+%d deger daha)]", col, paste(head(u_vals, 15), collapse = ", "), length(u_vals) - 15))
      }
    }
  })
  paste(unlist(summary_list), collapse = "\n")
}

extract_filter_criteria_from_prompt <- function(user_prompt, data_context, available_columns, conn, session = NULL) {
  
  # Veri baglamini olustur (AI'in dogru degerleri gormesi icin)
  cols_summary <- summarize_columns_for_ai(data_context)
  
	system_instruction <- paste0(
	  "Sen Primavera P6 ve SAP Project System verileri konusunda uzman, kıdemli bir veri analistisin. ",
	  "Kullanıcının Türkçe sorduğu doğal dil sorularını analiz ederek yapılandırılmış bir JSON filtreleme sorgusuna dönüştürmekle görevlisin.\n\n",
	  
	  "### KRİTİK: GENEL SORULAR VS SPESİFİK FİLTRELER\n",
	  "❗❗❗ ÇOĞU SORGU ZATEN BELİRLİ BİR KONUYA ÖZELDIR - GEREKSİZ FİLTRE EKLEME!\n",
	  "Örnek: 'Rolden kaynağa çevrilmemiş aktiviteler' sorgusu zaten bu konuya özgüdür. 'çevrilmemiş' kelimesini filtre olarak kullanma!\n",
	  "Örnek: 'Bütçesi aşan projeler' sorgusu zaten bütçe aşımı içerir. 'aşan' kelimesini filtre olarak kullanma!\n\n",
	  
	  "❗ Kullanıcı GENEL bir analiz istiyorsa (tüm projeler, tüm kaynaklar, özet istatistikler), FİLTRE KULLANMA!\n",
	  "✅ Sadece kullanıcı BELİRLİ bir VARLIK belirtirse filtre ekle:\n",
	  "   - Proje kodu: 'P1234', 'PROJE-001'\n",
	  "   - Proje adı: 'Malzeme Üretim Projesi', 'Elektronik Tasarım'\n",
	  "   - Kişi adı: 'Ahmet Yılmaz', 'Mehmet'\n",
	  "   - Departman: 'Elektronik Tasarım Müdürlüğü', 'PGRM'\n",
	  "   - Masraf yeri kodu: '12345678'\n",
	  "   - Tarih aralığı: '2024', 'Ocak', 'son 3 ay'\n\n",
	  
	  "❌ FİLTRE YAPILMAMASI GEREKEN DURUMLAR:\n",
	  "- Kullanıcı sorgu konusunu tekrar ediyor: 'aktiviteler', 'kaynaklar', 'projeler' gibi genel terimler\n",
	  "- Kullanıcı analiz türü belirtiyor: 'özetle', 'listele', 'kaç tane', 'var mı'\n",
	  "- Kullanıcı sorgu kriterini tekrar ediyor: Sorgu zaten 'çevrilmemiş aktiviteler'i getiriyorsa, 'çevrilmemiş' filtresiz bırak\n\n",
	  
	  "**GENEL SORU ÖRNEKLERİ (FİLTRE YOK):**\n",
	  "- 'Kaç proje var?', 'Toplam kaç kaynak?', 'Hangi departmanlarda çalışma var?'\n",
	  "- 'Projelerin dağılımı nedir?', 'En büyük projeler hangileri?', 'Aktif proje sayısı?'\n",
	  "- 'Yıllara göre proje dağılımı', 'Departman bazında kaynak analizi'\n",
	  "- 'Ortalama proje süresi', 'Toplam bütçe', 'Maliyet özeti'\n\n",
	  
	  "**SPESİFİK SORU ÖRNEKLERİ (FİLTRE EKLE):**\n",
	  "- 'P1234 projesinin durumu nedir?' → filter: ProjeKodu='P1234'\n",
  	  "- 'Malzeme Üretim projesinin durumu nedir?' → filter: ProjeAdi='Malzeme Üretim'\n",
	  "- 'Ahmet Yılmaz hangi projelerde?' → filter: KaynakAdi contains 'Ahmet Yılmaz'\n",
	  "- 'PGRM program müdürlüğündeki projeler' → filter: ProgMdlKodu='4_PGRM'\n",	  
	  "- 'Elektronik Tasarım Müdürlüğündeki çalışanlar' → filter: MasrafYeri='Elektronik Tasarım Müdürlüğü'\n",	 	  
	  "- '12345678 masraf yerindeki çalışanlar' → filter: MasrafYeriKodu='12345678'\n",
	  "- 'Aktif durumdaki projeler' → filter: Durum='1'\n\n",
	  
	  "### ANALİZ EVRENİ VE TERMİNOLOJİ\n",
	  "**Proje Yönetimi Terimleri:**\n",
	  "- **Projeler:** Proje Kodu, Proje Adı, Durum, EPS, Program Müdürlüğü, Program Direktörlüğü, İDA, İş Dağılım Ağacı, WBS\n",
	  "- **Kaynaklar:** Kaynak Adı, Kaynak Kodu, Çalışan, Personel, Rol, Unvan, Sicil Numarası, Sicil No\n",
	  "- **Organizasyon:** Masraf Yeri, Masraf Yeri Kodu, Bölüm, Müdürlük, Direktörlük, Birim\n",
	  "- **Finansal:** Bütçe, Gerçekleşen, Kalan, Maliyet Merkezi\n",
	  "- **Zaman:** Başlangıç/Bitiş Tarihleri, Süre, Planlanan/Gerçekleşen\n",
	  "- **Durum Kodları:** 1=Aktif, 0=Pasif\n\n",
    
    "### MEVCUT SÜTUNLAR VE DEĞER ÖZETLERİ (Filtre degerlerini buradaki gercek verilere gore sec):\n",
    cols_summary, "\n\n",
    
	"### GÖREV KURALLARI:\n",
	"1. **GENEL SORULARDA FİLTRE KULLANMA:** \n",
	"   - Kullanıcı 'kaç proje var', 'toplam', 'tüm', 'hepsi', 'dağılım', 'liste' gibi kelimeler kullanıyorsa,\n",
	"   - VE spesifik bir kod/isim BELİRTMİYORSA,\n",
	"   - → filters: [] (BOŞ DİZİ döndür)\n",
	"   - Aggregation olarak 'count' veya 'group_by' kullanabilirsin.\n\n",

	"2. **SPESİFİK SORULARDA FİLTRE EKLE:**\n",
	"   - Proje kodu (P123), masraf yeri (M1), kişi adı (Ahmet Yılmaz) gibi BELİRLİ varlıklar belirtilmişse,\n",
	"   - → Bu varlıkları filters dizisine ekle.\n\n",

	"3. **Çoklu Filtreleme:** Kullanıcı birden fazla koşul belirtirse (örn: 'M1 masraf yerinde unvanı mühendis olanlar'), bunların hepsini 'filters' listesine ekle.\n",

	"4. **Esnek Eşleştirme:** Kullanıcının 'Mühendisler' dediği şeyi veride 'Mühendis' veya 'Engineer' olarak bulabilirsin. 'operation' alanını buna göre seç.\n",

	"5. **Büyük/Küçük Harf Duyarsız:** Filtre değerlerini olduğu gibi al, kod tarafında case-insensitive arama yapılacaktır.\n",
    
    "### ÇIKTI FORMATI (JSON):\n",
    "{\n",
    "  \"filters\": [\n",
    "    {\"column\": \"SütunAdı\", \"value\": \"Değer\", \"operation\": \"exact_match\"}\n",
    "  ],\n",
    "  \"aggregation\": \"count\",\n",
    "  \"group_column\": null\n",
    "}\n\n",
	
	"### ALAN DEĞERLERİ (DOMAIN MAPPINGS):\n",
    "Bazı alanlar sayısal veya kodlanmış değerler kullanır:\n",
    "- **AktifKaynak, Durum, Status**: 1 (aktif/yes), 0 (pasif/no)\n",
    "- **Onay, Approval**: 1 (onaylı), 0 (onaysız)\n",
    "Kullanıcı 'aktif', 'Y', 'yes' derse → value: '1' kullan.\n",
    "Kullanıcı 'pasif', 'N', 'no' derse → value: '0' kullan.\n\n",
    
    "### OPERATÖRLER ('operation'):\n",
    "- 'exact_match': Kodlar ve ID'ler için (örn: P101, M1).\n",
    "- 'contains': İsimler, açıklamalar ve metin aramaları için (örn: 'İnşaat içeren projeler').\n",
    "- 'greater_than', 'less_than': Sayısal değerler ve tarihler için (örn: 'Bütçesi 1000'den büyük').\n\n",
    
    "### AGGREGATION TİPLERİ ('aggregation'):\n",
    "- 'list': Kayıtları listele (Varsayılan).\n",
    "- 'count': Kayıt sayısını ver (Kaç adet?).\n",
    "- 'sum': Sayısal sütunu topla (Toplam bütçe).\n",
    "- 'group_by': Gruplayarak özetle (Departman bazında dağılım).\n\n",
    
    "### ÖRNEKLER:\n",
    "Soru: 'P1111 proje kodlu projeyi özetle'\n",
    "-> {\"filters\":[{\"column\":\"ProjeKodu\",\"value\":\"P1111\",\"operation\":\"exact_match\"}], \"aggregation\":\"list\", \"group_column\":null}\n\n",
    
    "Soru: 'M1 masraf yerinde unvanı mühendis olan çalışanları listele'\n",
    "-> {\"filters\":[{\"column\":\"MasrafYeri\",\"value\":\"M1\",\"operation\":\"exact_match\"}, {\"column\":\"Unvan\",\"value\":\"Mühendis\",\"operation\":\"contains\"}], \"aggregation\":\"list\", \"group_column\":null}\n\n",
    
    "Soru: 'Hangi departmanlarda kaç proje var?'\n",
    "-> {\"filters\":[], \"aggregation\":\"group_by\", \"group_column\":\"Departman\"}\n\n",
    
    "Soru: 'Ali Demir hangi projeleri yönetiyor?'\n",
    "-> {\"filters\":[{\"column\":\"ProjeYoneticisi\",\"value\":\"Ali Demir\",\"operation\":\"contains\"}], \"aggregation\":\"list\", \"group_column\":null}\n\n",
    
	"Soru: 'Aktif kaynakları göster'\n",
    "-> {\"filters\":[{\"column\":\"AktifKaynak\",\"value\":\"1\",\"operation\":\"exact_match\"}], \"aggregation\":\"list\", \"group_column\":null}\n\n",
    
    "Soru: 'Pasif projeleri listele'\n",
    "-> {\"filters\":[{\"column\":\"Durum\",\"value\":\"0\",\"operation\":\"exact_match\"}], \"aggregation\":\"list\", \"group_column\":null}\n\n",
	
    "SADECE GEÇERLİ JSON DÖNDÜR. YORUM EKLEME."
  )
  
  messages <- list(
    list(role = "system", content = system_instruction),
    list(role = "user", content = user_prompt)
  )
  
  tryCatch({
    filter_model <- getOption("mergen.filter_model", api_config$local_models[1])
    creds <- resolve_local_llm_credentials(filter_model)
    
    api_key_val <- NULL
    if (!is.null(session) && !is.null(session$userData$ai_api_key)) {
      api_key_val <- as.character(session$userData$ai_api_key)[1]
    }
    
    if (is.null(api_key_val) || !nzchar(api_key_val)) {
      default_key <- creds$default_api_key %||% ""
      if (nzchar(default_key)) {
        api_key_val <- as.character(default_key)[1]
      }
    }
    
	result <- call_local_llm(messages, list(
      model_selection = filter_model,
      temperature = 0.0, 
      max_output_tokens = 1500,
      enable_mcp_tools = FALSE,
      shiny_session = session,
      api_key_override = api_key_val
    ))
    
    if (is.null(result)) return(list(filters = list(), aggregation = NULL))
    
    ai_content <- if (is.list(result)) result$content else result
    if (is.null(ai_content) || length(ai_content) == 0) return(list(filters = list(), aggregation = NULL))
    
	ai_text <- as.character(ai_content)[1]
    ai_text <- gsub("```json|```", "", ai_text)
    ai_text <- trimws(ai_text)
    
    if (nchar(ai_text) < 50) {
      cat(sprintf("[FILTER_AI] Yanit cok kisa (%d karakter), iptal ediliyor.\n", nchar(ai_text)))
      return(list(filters = list(), aggregation = NULL))
    }
    
    if (!grepl("\\{.*\\}", ai_text)) {
      cat("[FILTER_AI] JSON format algilanamadi.\n")
      return(list(filters = list(), aggregation = NULL))
    }
    
    parsed <- tryCatch({
      temp_parse <- jsonlite::fromJSON(ai_text, simplifyVector = FALSE)
      if (is.null(temp_parse)) {
        ai_text_fixed <- paste0(ai_text, ']}')
        jsonlite::fromJSON(ai_text_fixed, simplifyVector = FALSE)
      } else {
        temp_parse
      }
    }, error = function(e) {
      cat(sprintf("[FILTER_AI] JSON parse hatasi: %s\n", e$message))
      NULL
    })
    
	if (is.null(parsed)) return(list(filters = list(), aggregation = NULL))
    
    filters <- parsed$filters
    if (is.null(filters) || !is.list(filters)) filters <- list()
	
	if (length(filters) > 0) {
      filters <- lapply(filters, function(f) {
        col_lower <- tolower(f$column %||% "")
        val_raw <- f$value %||% ""
        
        if (grepl("aktif|active|durum|status", col_lower, perl = TRUE)) {
          val_lower <- tolower(as.character(val_raw))
          if (val_lower %in% c("y", "yes", "evet", "aktif", "active", "1", "true")) {
            f$value <- "1"
            f$operation <- "exact_match"
          } else if (val_lower %in% c("n", "no", "hayır", "pasif", "passive", "inactive", "0", "false")) {
            f$value <- "0"
            f$operation <- "exact_match"
          }
        }
        
        return(f)
      })
    }
    
    if (!is.null(parsed$filter_column)) {
        filters <- list(list(
            column = parsed$filter_column,
            value = parsed$filter_value,
            operation = parsed$operation
        ))
    }
    
    if (length(filters) > 0) {
      valid_filters <- Filter(function(f) {
        !is.null(f$column) && nzchar(f$column) && !is.null(f$value)
      }, filters)
      
      if (length(valid_filters) == 0) {
        cat("[FILTER_AI] Tum filtreler gecersiz, iptal ediliyor.\n")
        return(list(filters = list(), aggregation = NULL))
      }
      
      cat(sprintf("[FILTER_AI] %d gecerli filtre algilandi.\n", length(valid_filters)))
      filters <- valid_filters
    }

    return(list(
      filters = filters,
      aggregation = parsed$aggregation,
      group_column = parsed$group_column
    ))
    
  }, error = function(e) {
    cat(sprintf("[FILTER_AI] Error: %s\n", e$message))
    return(list(filters = list(), aggregation = NULL))
  })
}

apply_smart_filters <- function(data, filter_instructions, user_prompt) {
  cat(sprintf("[SMART_FILTER] Baslangic satir: %d\n", nrow(data)))
  
  if (nrow(data) == 0) return(data.frame())
  
  dt <- data.table::as.data.table(data)
  
  filters <- filter_instructions$filters
  aggregation <- filter_instructions$aggregation
  group_col <- filter_instructions$group_column
  
  # Kullanıcı genel bir analiz/özet istiyor mu kontrol et
  genel_soru_kaliplari <- c(
    "kaç", "toplam", "sayı", "adet", "hangi", "dağılım", "özet", 
    "analiz", "liste", "göster", "tüm", "hepsi", "en fazla", 
    "en az", "ortalama", "maksimum", "minimum"
  )
  
  prompt_lower <- tolower(user_prompt)
  genel_soru_mu <- any(sapply(genel_soru_kaliplari, function(pattern) {
    grepl(pattern, prompt_lower, fixed = TRUE)
  }))
  
  # Spesifik varlık belirtilmiş mi? (kod, isim, departman)
  spesifik_varlık_var <- grepl("\\b[A-Z][0-9]{3,}\\b|\\b[A-Z]{1,3}[0-9]{1,}\\b", user_prompt, perl = TRUE) || # P123, M1 gibi kodlar
                          grepl("[A-ZÜĞIŞÖÇ][a-züğışöç]+ [A-ZÜĞIŞÖÇ][a-züğışöç]+", user_prompt, perl = TRUE) # İsim Soyisim
  
  # KARAR: Genel soruysa VE spesifik varlık yoksa, filtreleri GEÇERSİZ KIL
  if (genel_soru_mu && !spesifik_varlık_var && (is.null(filters) || length(filters) == 0)) {
    cat("[SMART_FILTER] GENEL SORU tespit edildi, filtre UYGULANMAYACAK.\n")
    filters <- list() # Filtreleri temizle
  }
  
  cat(sprintf("[SMART_FILTER] Filtre sayisi: %d (Genel soru: %s, Spesifik varlık: %s)\n", 
              length(filters %||% list()), genel_soru_mu, spesifik_varlık_var))
  
  cat(sprintf("[SMART_FILTER] Filtre sayisi: %d\n", length(filters %||% list())))
  if (length(filters) > 0) {
    for (i in seq_along(filters)) {
      f <- filters[[i]]
      cat(sprintf("[SMART_FILTER] Filtre #%d: sutun='%s', deger='%s', islem='%s'\n", 
                  i, f$column %||% "NULL", f$value %||% "NULL", f$operation %||% "NULL"))
    }
  }
  
  # --- 1. Filtreleri Uygula (Multiple & Case Insensitive) ---
  if (!is.null(filters) && length(filters) > 0) {
    for (f in filters) {
      col <- f$column
      val <- f$value
      op <- f$operation %||% "exact_match"
      
      if (!is.null(col) && nzchar(as.character(col)[1]) && col %in% names(dt)) {
        
        col_vals <- dt[[col]]
        val_str <- as.character(val)[1]
        
        # Case Insensitive Handling
		if (is.character(col_vals) || is.factor(col_vals)) {
			  # Escape special regex characters in the search value to treat it as a literal string
			  val_regex <- gsub("([.|()\\^{}+$*?]|\\[|\\])", "\\\\\\1", val_str)
			  col_vals_char <- as.character(col_vals)
			  
			  if (op == "exact_match") {
				# Use anchors ^ and $ for exact match, with ignore.case = TRUE
				dt <- dt[grepl(paste0("^", val_regex, "$"), col_vals_char, ignore.case = TRUE), ]
			  } else if (op == "contains") {
				# Standard contains with ignore.case = TRUE
				dt <- dt[grepl(val_regex, col_vals_char, ignore.case = TRUE), ]
			  } else {
				# Fallback to exact match
				dt <- dt[grepl(paste0("^", val_regex, "$"), col_vals_char, ignore.case = TRUE), ]
			  }
			} else if (is.numeric(col_vals)) {
            val_num <- suppressWarnings(as.numeric(val_str))
            if (!is.na(val_num)) {
                if (op == "greater_than") dt <- dt[col_vals > val_num, ]
                else if (op == "less_than") dt <- dt[col_vals < val_num, ]
                else dt <- dt[col_vals == val_num, ]
            }
        }
      }
    }
} else {
  # Filtre yok ve aggregation da yok
  if (is.null(aggregation) || !tolower(aggregation) %in% c("count", "sum", "group_by")) {
    cat("[SMART_FILTER] Ne filtre ne aggregation var. GENEL SORU olarak işleniyor - tüm veri döndürülecek.\n")
    # NOT: Gereksiz keyword fallback kaldırıldı - AI yeterince akıllı
    # Eğer kullanıcı genel bir soru sorduysa, tüm veri dönmeli
    # Max limit: 1000 satır (performans için)
    dt <- head(dt, 1000)
  } else {
    cat("[SMART_FILTER] Aggregation mevcut, filtre yok - tüm veri üzerinde aggregation yapılacak\n")
  }
}
  
# --- 2. Aggregation Logic ---
if (!is.null(aggregation)) {
  agg_str <- tolower(aggregation)
  
  if (agg_str == "count") {
    # GENEL SORULARDA: Tüm veriyi say
    # SPESİFİK SORULARDA: Filtre sonrasını say
    aciklama <- if (length(filters) > 0) "Filtrelenen Kayıt Sayısı" else "Toplam Kayıt Sayısı"
    return(data.frame(Sonuc = aciklama, Adet = nrow(dt)))
    } else if (agg_str == "sum") {
        num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
        if (length(num_cols) > 0) {
            sums <- lapply(num_cols, function(nc) sum(dt[[nc]], na.rm=TRUE))
            return(as.data.frame(sums))
        }
    } else if (agg_str == "group_by" && !is.null(group_col) && group_col %in% names(dt)) {
        return(as.data.frame(dt[, .N, by = group_col]))
    }
  }
  
  return(as.data.frame(dt))
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

generate_statistical_summary <- function(data, max_preview_rows = 20) {
  if (is.null(data) || nrow(data) == 0) {
    return(list(
      summary_text = "Veri yok.",
      row_count = 0,
      preview_data = NULL
    ))
  }
  
  total_rows <- nrow(data)
  total_cols <- ncol(data)
  col_names <- names(data)
  
  dt <- data.table::as.data.table(data)
  
  num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
  cat_cols <- names(dt)[vapply(dt, function(x) is.character(x) || is.factor(x), logical(1))]
  
  summary_parts <- list()
  summary_parts[[1]] <- sprintf("TOPLAM SATIR: %d | TOPLAM SUTUN: %d", total_rows, total_cols)
  
  if (length(num_cols) > 0) {
    num_summary_list <- lapply(num_cols, function(col) {
      vals <- dt[[col]]
      vals <- vals[!is.na(vals)]
      if (length(vals) == 0) return(NULL)
      
      data.frame(
        Sutun = col,
        Toplam = sum(vals, na.rm = TRUE),
        Ortalama = mean(vals, na.rm = TRUE),
        Medyan = median(vals, na.rm = TRUE),
        Min = min(vals, na.rm = TRUE),
        Max = max(vals, na.rm = TRUE),
        StdSapma = sd(vals, na.rm = TRUE),
        Kayit = length(vals),
        stringsAsFactors = FALSE
      )
    })
    
    num_summary_df <- do.call(rbind, Filter(Negate(is.null), num_summary_list))
    
    if (!is.null(num_summary_df) && nrow(num_summary_df) > 0) {
      summary_parts[[length(summary_parts) + 1]] <- "\n\nSAYISAL SUTUNLAR OZETI:"
      summary_parts[[length(summary_parts) + 1]] <- paste(capture.output(print(num_summary_df, row.names = FALSE)), collapse = "\n")
    }
  }
  
  if (length(cat_cols) > 0) {
	cat_summary_list <- lapply(head(cat_cols, 5), function(col) {
      tbl <- sort(table(dt[[col]], useNA = "no"), decreasing = TRUE)
      top5 <- head(tbl, 5)
      
      # FIX: If top5 is empty, return NULL to skip this column
      if (length(top5) == 0) {
        return(NULL)
      }
      
      # FIX: Handle potential NA in names explicitly
      top_name <- names(top5)[1]
      if (is.null(top_name) || is.na(top_name)) top_name <- "Yok"
      
      data.frame(
        Sutun = col,
        EnSikDeger = top_name,
        Adet = as.integer(top5[1]),
        BenzerSayi = length(unique(dt[[col]])),
        stringsAsFactors = FALSE
      )
    })
    
    # Remove NULL results before rbind (Prevents list of NULLs crashing rbind)
    cat_summary_list <- Filter(Negate(is.null), cat_summary_list)
    cat_summary_df <- do.call(rbind, cat_summary_list)
    
    if (!is.null(cat_summary_df) && nrow(cat_summary_df) > 0) {
      summary_parts[[length(summary_parts) + 1]] <- "\n\nKATEGORIK SUTUNLAR OZETI:"
      summary_parts[[length(summary_parts) + 1]] <- paste(capture.output(print(cat_summary_df, row.names = FALSE)), collapse = "\n")
    }
  }
  
  preview_data <- NULL
  if (total_rows > max_preview_rows) {
    preview_data <- head(data, max_preview_rows)
    summary_parts[[length(summary_parts) + 1]] <- sprintf("\n\n(İlk %d satir gosteriliyor; toplam %d satir mevcut)", max_preview_rows, total_rows)
  } else {
    preview_data <- data
  }
  
  summary_text <- paste(summary_parts, collapse = "\n")
  
  return(list(
    summary_text = summary_text,
    row_count = total_rows,
    preview_data = preview_data
  ))
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
  cat(sprintf("[PK_ANALIZ] RLS sonrasi: %d satir\n", nrow(secure_data)))
  
  if (nrow(secure_data) == 0) {
      return(paste0("🔍 **Sonuc:** Sorgu calistirildi ancak yetkiniz dahilinde veri bulunamadi."))
  }
    
  # AI fonksiyonuna veriyi de gonderiyoruz ki degerleri gorebilsin
  if (isTRUE(selected_query$disable_ai_filters)) {
    cat("[PK_ANALIZ] Ozel Sorgu Ayari: AI Filtreleme devre disi birakildi. Sadece RLS verisi kullaniliyor.\n")
    filter_criteria <- list(filters = list(), aggregation = NULL)
    filtered_data <- secure_data
  } else {
    filter_criteria <- extract_filter_criteria_from_prompt(user_prompt, secure_data, available_columns, conn, session)
  
    if (!is.null(filter_criteria$error)) {
      cat(sprintf("[PK_ANALIZ] AI filtreleme hatasi: %s\n", filter_criteria$error))
    }
  
    cat(sprintf("[PK_ANALIZ] AI Filter Sonucu -> column: %s, value: %s, operation: %s, aggregation: %s\n",
                filter_criteria$filter_column %||% "NULL",
                filter_criteria$filter_value %||% "NULL",
                filter_criteria$operation %||% "NULL",
                filter_criteria$aggregation %||% "NULL"))
  
    filtered_data <- apply_smart_filters(secure_data, filter_criteria, user_prompt)
  }
  
  cat(sprintf("[PK_ANALIZ] Filtreleme sonrası: %d satır (Orijinal: %d)\n", 
              nrow(filtered_data), nrow(secure_data)))
			  
	if (nrow(filtered_data) < nrow(secure_data) * 0.05 && nrow(secure_data) > 100) {
	  cat("[PK_ANALIZ] UYARI: Filtreleme sonucu çok az veri kaldı (<%5). Kullanıcı gereksiz filtre uygulanmış olabilir.\n")
	}
  
  if (nrow(filtered_data) == 0) {
    return(paste0("🔍 **Sonuç:** Filtreleme sonrası veri bulunamadı."))
  }
  
  stat_summary <- generate_statistical_summary(filtered_data, max_preview_rows = 15)
  
  cat(sprintf("[PK_ANALIZ] Istatistiksel ozet olusturuldu: %d satir, %d onizleme\n",
              stat_summary$row_count,
              if (!is.null(stat_summary$preview_data)) nrow(stat_summary$preview_data) else 0))
  
  preview_json <- if (!is.null(stat_summary$preview_data) && nrow(stat_summary$preview_data) > 0) {
    jsonlite::toJSON(stat_summary$preview_data, auto_unbox = TRUE, pretty = FALSE)
  } else {
    "{}"
  }
  
  data_str <- paste0(
    stat_summary$summary_text,
    "\n\n--- ORNEK SATIRLAR (JSON) ---\n",
    preview_json,
    "\n\n(Not: Yukaridaki istatistikler ", stat_summary$row_count, " satirdan olusturulmustur)"
  )
  
  if (nrow(secure_data) > nrow(filtered_data)) {
    data_str <- paste0(
      data_str,
      sprintf("\n\n(RLS ve filtreleme oncesi toplam %d satir vardi)", nrow(secure_data))
    )
  }
  
  system_prompt <- paste0(
    "Sen MERGEN Bilge veri analiz asistanisin. Kullanicinin sorusuna, R tarafindan hazirlanan ISTATISTIKSEL OZET'e dayanarak cevap ver.\n\n",
    "Kullanilan Sorgu: ", selected_query$name, "\n",
    "Sorgu Aciklamasi: ", selected_query$description, "\n\n",
    "KRITIK: Sana gonderilen veri R tarafindan ZATEN FILTRELENMIS ve ISTATISTIKSEL OLARAK OZETLENMISTIR.\n",
    "Bu ozet SAYISAL SUTUNLAR icin toplam/ortalama/min/max, KATEGORIK SUTUNLAR icin en sik degerleri icerir.\n\n",
    "GOREVLER:\n",
    "1. Istatistiksel ozeti incele (sayisal istatistikler, kategorik dagilimlar)\n",
    "2. Kullanicinin sorusuna DOGRUDAN, NET ve TURKCE cevap ver\n",
    "3. Sayilari ozetten AYNEN kullan (yuvarlama, tahminde bulunma)\n",
    "4. Trendleri ve onemlı bulgulari vurgula\n",
    "5. Markdown formatinda yaz\n",
    "6. SADECE OZETTEKI VERILERE DAYAN - baska bilgi uydurma\n",
    "7. Eger ornek satirlar varsa, bunlari destekleyici olarak kullan\n"
  )

	if (!is.null(selected_query$info_file) && nzchar(selected_query$info_file)) {
	  file_path_normalized <- gsub("\\\\", "/", selected_query$info_file)
	  system_prompt <- paste0(system_prompt, 
		"\n8. EK DOSYA: Kullaniciya su dosyayi incelemesini oner. Cevabinin en altina su HTML linkini ekle: <br><br>👉 <span class='analysis-file-link' data-filepath='", file_path_normalized, "' style='color:#007bff; cursor:pointer; text-decoration:underline; font-weight:bold;'>İlgili Dosyayı Görüntüle</span>\n")
	}

	if (!is.null(selected_query$info_url) && nzchar(selected_query$info_url)) {
	  system_prompt <- paste0(system_prompt, 
		"\n9. EK LINK: Kullaniciya su adresi incelemesini oner. Cevabinin en altina su HTML linkini ekle: <br><br>🌐 <a href='", selected_query$info_url, "' target='_blank' rel='noopener noreferrer'><b>Daha Fazla Bilgi</b></a>\n")
	}
  
  user_msg <- paste0(
    "KULLANICI SORUSU:\n",
    user_prompt,
    "\n\n--- R TARAFINDAN HAZIRLANAN ISTATISTIKSEL OZET ---\n",
    data_str,
    "\n\n--- OZET SONU ---\n\n",
    "Talımat: Yukaridaki istatistikleri kullanarak kullanicinin sorusuna DOGRUDAN cevap ver. ",
    "Sayilari AYNEN kullan. Trendleri ve onemli bulgulari vurgula."
  )
  
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
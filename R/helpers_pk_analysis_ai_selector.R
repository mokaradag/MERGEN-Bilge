# ==============================================================================
# Dosya Yolu: R/helpers_pk_analysis_ai_selector.R
# Açıklama: v1 (§10) AI TABANLI tekil sorgu seçicisi — `find_best_query_with_ai()`.
#
# NEDEN AYRI DOSYA: `R/module_proje_kaynak_analizi.R` bakım borcu ratchet'inin
# 800 satır tavanına dayandı. Bu fonksiyon modülün orkestrasyonuna ait değildir;
# kendi kendine yeten bir v1 seçicisidir ve YALNIZCA yeri değişmiştir.
#
# DAVRANIŞ BİREBİR KORUNUR (§10: "The v1 decision logic must remain unchanged").
# İstem metni, `match_id` yorumu, konum tabanlı `.matched_idx` sözleşmesi, güven
# alanı ve hata yolları DEĞİŞMEMİŞTİR. Faz 5 iki geçişli seçici bu dosyayı
# ÇAĞIRMAZ; `MERGEN_PK_ENGINE=v2` iken bu yol hiç çalışmaz.
#
# Konum kimliği (`ID: %d`) bilinçli olarak KORUNUR: D13'ü kapatan yol v2
# hattıdır ve v1 gövdesi bu fazda değiştirilmez.
# ==============================================================================

# AI Destekli Seçim Fonksiyonu
find_best_query_with_ai <- function(user_prompt, library, session) {
  cat("[PK_ANALIZ] AI tabanli sorgu secimi baslatiliyor...\n")
  
  # Kütüphane özetini hazırla
  library_context <- vapply(seq_along(library), function(i) {
    q <- library[[i]]
    sprintf("ID: %d | ISIM: %s | ACIKLAMA: %s", i, q$name, q$description)
  }, character(1))
  
  library_text <- paste(library_context, collapse = "\n")
  
  system_instruction <- paste0(
    "Sen bir Veritabani Sorgu Yonlendiricisisin. Kullanicinin Turkce sorusunu analiz edip EN UYGUN SQL sorgusunu sec.\n\n",
    
    "### MEVCUT SORGULAR:\n",
    library_text, "\n\n",
    
    "### ESLESTIRME KURALLARI:\n",
    "1. ANLAM ESLESMESI: Kelimelerin birebir eslesip eslesmedigine degil, kullanicinin NIYETINE bak.\n",
    "2. YAKIN KAVRAMLAR: 'butce', 'maliyet', 'harcama' gibi kavramlar birbirine yakindir.\n",
    "3. KISMI ESLESME: Sorgu tam olarak cevap vermese bile, KISMI olarak ilgiliyse sec ve confidence'i dusur.\n",
    "4. Hic alakali sorgu yoksa: match_id: null dondur.\n\n",
    
    "### ZORUNLU JSON CIKTISI:\n",
    "{\"match_id\": 1, \"confidence\": 85, \"reason\": \"Kisa aciklama\"}\n\n",
    "- match_id: Sorgu ID numarasi (1'den baslar) veya null\n",
    "- confidence: 0-100 arasi (100=mukemmel, 50=kismi, 0=alakasiz)\n",
    "- reason: Neden bu sorguyu sectin (tek cumle)\n\n",
    "ONEMLI: Sadece JSON dondur, baska hicbir sey yazma."
  )
  
  messages <- list(
    list(role = "system", content = system_instruction),
    list(role = "user", content = user_prompt)
  )
  
  tryCatch({
    # Model seçimi (Varsayılan model veya filter modeli kullanılabilir)
    model_name <- getOption("mergen.filter_model", api_config$local_models[1])
    creds <- resolve_local_llm_credentials(model_name)
    
    # API Key Yönetimi
    api_key_val <- NULL
    if (!is.null(session) && !is.null(session$userData$ai_api_key)) {
      api_key_val <- as.character(session$userData$ai_api_key)[1]
    }
    if (is.null(api_key_val) || !nzchar(api_key_val)) {
      api_key_val <- creds$default_api_key
    }

    # LLM Çağrısı. Async işçide mutlak istek son tarihi option üzerinden
    # taşınır; v1 seçicisi de bloklayan ağ çağrısını KALAN bütçeyle sınırlar.
    llm_config <- list(
      model_selection = model_name,
      temperature = 0.0,
      max_output_tokens = 200,
      enable_mcp_tools = FALSE,
      shiny_session = session,
      api_key_override = api_key_val
    )
    async_deadline <- getOption("mergen.pk.async.deadline_at", NULL)
    if (!is.null(async_deadline) &&
        exists("pk_sql_timeout_plan", mode = "function", inherits = TRUE) &&
        exists("pk_deadline_remaining_sec", mode = "function", inherits = TRUE)) {
      remaining_sec <- tryCatch(pk_deadline_remaining_sec(async_deadline), error = function(e) Inf)
      # `max(1L, floor(...))` saniyenin altındaki bir bakiyeyi TAZE bir saniyeye
      # yuvarlıyordu: 100 ms kalmışken bile neredeyse tam bir saniye daha
      # bloklanabiliyordu. `pk_sql_timeout_plan()` ile AYNI aritmetik kullanılır:
      # aşağı yuvarlama 0 üretiyorsa çağrı HİÇ gönderilmez.
      secim_plani <- pk_sql_timeout_plan(Inf, remaining_sec)
      if (!isTRUE(secim_plani$dispatch)) return(NULL)
      if (is.finite(remaining_sec)) {
        llm_config$request_timeout_sec <- as.integer(secim_plani$timeout_sec)
      }
    }

    # Durdur artık bloklayan HTTP çağrısına DA ULAŞIR: `call_local_llm()` PK
    # kapısı yayınlanmışken curl ilerleme geri çağrısını bağlar ve kapı
    # ateşlendiğinde aktarım ANINDA kesilir (bkz. helpers_pk_cancel_http.R).
    # Buradaki ön/son yoklamalar, iptal edilmiş bir seçim sonucunun
    # KULLANILMAMASINI garanti eder.
    # (`try()` kullanılır: ek anonim hata kapanışı bu dosyanın fonksiyon
    # bütçesini tüketirdi.)
    kapi_var <- exists("pk_active_stage_halt", mode = "function", inherits = TRUE)
    if (kapi_var && isTRUE(try(pk_active_stage_halt(), silent = TRUE))) return(NULL)

    result <- call_local_llm(messages, llm_config)
    if (kapi_var && isTRUE(try(pk_active_stage_halt(), silent = TRUE))) return(NULL)
    
    if (is.null(result)) return(NULL)
    
    content <- if (is.list(result)) result$content else result
    content <- gsub("```json|```", "", content)
    content <- trimws(content)
    
    parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)
    
	if (!is.null(parsed$match_id)) {
      idx <- as.integer(parsed$match_id)
	  if (idx > 0 && idx <= length(library)) {
        confidence <- as.numeric(parsed$confidence %||% 0)
        cat(sprintf("[PK_ANALIZ] AI Secimi: ID=%d (%s) | Guven: %.1f%% | Sebep: %s\n", 
                    idx, library[[idx]]$name, confidence, parsed$reason %||% ""))
        
        result <- library[[idx]]
        result$relevance_score <- confidence
        result$selection_method <- "ai"
        result$selection_reason <- parsed$reason %||% ""
        result$.matched_idx <- idx
        return(result)
      }
    }
    
    return(NULL)
    
  }, error = function(e) {
    cat(sprintf("[PK_ANALIZ] AI Secim Hatasi: %s\n", e$message))
    return(NULL)
  })
}
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
  cat("[PK_ANALIZ] AI tabanlı sorgu seçimi başlatılıyor...\n")
  
  # Kütüphane özetini hazırla
  library_context <- vapply(seq_along(library), function(i) {
    q <- library[[i]]
    # EKSİK ALAN `character(0)` ÜRETMEZ. `sprintf()` sıfır uzunluklu bir
    # argümanla `character(0)` döndürür ve `vapply(..., character(1))`
    # "values must be length 1" ile HATA fırlatırdı; `tryCatch` daha sonra
    # başladığı için seçici belgelenen `NULL` yedeğini döndüremezdi.
    # `.pk_meta_validate_query_library()` yalnızca `id`/`sql` doğrular.
    ad <- as.character(q$name %||% "")[1]
    aciklama <- as.character(q$description %||% "")[1]
    if (is.na(ad)) ad <- ""
    if (is.na(aciklama)) aciklama <- ""
    sprintf("ID: %d | İSİM: %s | AÇIKLAMA: %s", i, ad, aciklama)
  }, character(1))
  
  library_text <- paste(library_context, collapse = "\n")
  
  system_instruction <- paste0(
    "Sen bir Veritabanı Sorgu Yönlendiricisisin. Kullanıcının Türkçe sorusunu analiz edip EN UYGUN SQL sorgusunu seç.\n\n",
    
    "### MEVCUT SORGULAR:\n",
    library_text, "\n\n",
    
    "### EŞLEŞTİRME KURALLARI:\n",
    "1. ANLAM EŞLEŞMESİ: Kelimelerin birebir eşleşip eşleşmediğine değil, kullanıcının NİYETİNE bak.\n",
    "2. YAKIN KAVRAMLAR: 'bütçe', 'maliyet', 'harcama' gibi kavramlar birbirine yakındır.\n",
    "3. KISMİ EŞLEŞME: Sorgu tam olarak cevap vermese bile, KISMİ olarak ilgiliyse seç ve confidence'ı düşür.\n",
    "4. Hiç alakalı sorgu yoksa: match_id: null döndür.\n\n",
    
    "### ZORUNLU JSON ÇIKTISI:\n",
    "{\"match_id\": 1, \"confidence\": 85, \"reason\": \"Kısa açıklama\"}\n\n",
    "- match_id: Sorgu ID numarası (1'den başlar) veya null\n",
    "- confidence: 0-100 arası (100=mükemmel, 50=kısmi, 0=alakasız)\n",
    "- reason: Neden bu sorguyu seçtin (tek cümle)\n\n",
    "ÖNEMLİ: Sadece JSON döndür, başka hiçbir şey yazma."
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
    # SAHİPLİK DENETİMLİ ANAHTAR ÇÖZÜMLEMESİ (§1F).
    #
    # `session$userData$ai_api_key` DOĞRUDAN OKUNAMAZ: SSO kimlik değişimi
    # sonrasında o yuva BAŞKA bir uygulama kullanıcısının kişisel kimlik
    # bilgisini taşıyor olabilir ve bu çağrı onu kullanırdı. Merkezî yardımcı
    # sahibi doğrular, uyuşmazlıkta yuvayı temizler ve izinli kurumsal
    # varsayılana düşer. Yardımcı yoksa yalnızca varsayılan anahtar kullanılır.
    api_key_val <- if (exists("mb_api_key_get_feature_key_value", mode = "function", inherits = TRUE)) {
      tryCatch(
        mb_api_key_get_feature_key_value(
          session = session, fallback_key = creds$default_api_key %||% ""
        ),
        error = function(e) creds$default_api_key
      )
    } else {
      creds$default_api_key
    }
    if (length(api_key_val) != 1L || is.na(api_key_val) || !nzchar(as.character(api_key_val)[1])) {
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
    # TABAN zaman aşımı HER yolda uygulanır (bkz. helpers_pk_select_timeout.R):
    # son tarih yoksa da asılı bir uç nokta olay döngüsünü bloke edemez.
    secim_plani <- pk_select_effective_timeout()
    if (!isTRUE(secim_plani$dispatch)) return(NULL)
    llm_config$request_timeout_sec <- secim_plani$timeout_sec

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

    # `$` ATOMİK VEKTÖRDE HATA FIRLATIR: `fromJSON("5", simplifyVector = FALSE)` atomik bir değer, `fromJSON("[1,2]", ...)` ADSIZ liste döndürür; ilkinde `parsed$match_id` "$ operator is invalid for atomic vectors" ile düşer ve dıştaki işleyici bunu `AI Seçim Hatası` sayıp çağıranın AYNI çağrıyı yinelemesine yol açardı. Sözleşme ihlali HATA DEĞİLDİR: adlandırılmış liste olmayan yanıt "eşleşme yok" sayılır (`match_id`/`confidence` denetimleriyle aynı gerekçe).
    ham_eslesme <- if (is.list(parsed) && !is.null(names(parsed))) parsed[["match_id"]] else NULL

	if (!is.null(ham_eslesme)) {
      # SÖZLEŞME İHLALİ HATA DEĞİLDİR. Model sayı yerine metin ("birinci") ya da dizi döndürdüğünde `as.integer()` `NA` veya çok ögeli değer üretir; `if` o zaman "missing value where TRUE/FALSE needed" / "the condition has length > 1" fırlatır, dıştaki işleyici bunu `AI Seçim Hatası` olarak loglar ve çağıran döngü AYNI çağrıyı yineler. Geçersiz değer artık sessizce `NULL` (eşleşme yok) olarak raporlanır.
      # LİSTE DEĞERİ DÖNÜŞÜM ÖNCESİ REDDEDİLİR: `as.integer(list(...))` iç öge atomik değilse HATA fırlatır ve sözleşme ihlali yine istisnaya dönerdi.
      idx <- if (is.list(ham_eslesme) || !is.atomic(ham_eslesme)) {
        NA_integer_
      } else {
        suppressWarnings(as.integer(ham_eslesme)[1])
      }
	  if (length(idx) == 1L && !is.na(idx) && idx > 0 && idx <= length(library)) {
        # SÖZLEŞME İHLALİ HATA DEĞİLDİR: `match_id` ile AYNI atomik denetim.
        # `fromJSON(..., simplifyVector = FALSE)` `{"confidence": ["85"]}` için
        # LİSTE döndürür; `as.numeric(list("85"))` "(list) object cannot be
        # coerced" HATASI fırlatır, dıştaki işleyici bunu `AI Seçim Hatası`
        # olarak loglar ve çağıran AYNI çağrıyı yineler.
        ham_guven <- parsed[["confidence"]] %||% 0
        confidence <- if (is.list(ham_guven) || !is.atomic(ham_guven)) {
          NA_real_
        } else {
          suppressWarnings(as.numeric(ham_guven)[1])
        }
        if (length(confidence) != 1L || is.na(confidence)) confidence <- 0
        # `sprintf()` LİSTE argümanı kabul etmez; model `reason` alanını dizi olarak döndürdüğünde ("invalid format" / "cannot be coerced") sözleşme ihlali yine ISTISNAYA dönüşürdü. Ad ve sebep skalere indirgenir.
        skaler_metin <- function(x, yedek = "") {
          if (is.null(x) || is.list(x) || !is.atomic(x)) return(yedek)
          v <- as.character(x)
          if (!length(v) || is.na(v[1])) return(yedek)
          v[1]
        }
        sebep <- skaler_metin(parsed$reason)
        # MODEL ÜRETİMİ METİN LOGA REDAKTE EDİLEREK GİDER: `reason` tamamen LLM üretimidir ve istemde geçen bir bağlantı dizesini/anahtarı yankılayabilir; ham `cat()` bunu sunucu günlüğüne olduğu gibi yazıyordu.
        cat(sprintf("[PK_ANALIZ] AI Seçimi: ID=%d (%s) | Güven: %.1f%% | Sebep: %s\n",
                    idx, skaler_metin(library[[idx]]$name, "(isimsiz)"),
                    confidence, pk_safe_log_text(sebep)))
        
        result <- library[[idx]]
        result$relevance_score <- confidence
        result$selection_method <- "ai"
        result$selection_reason <- sebep
        result$.matched_idx <- idx
        return(result)
      }
    }
    
    return(NULL)
    
  }, error = function(e) {
    # Sürücü/LLM hata metni de ham basılmaz: aynı log sınırı geçerlidir.
    cat(sprintf("[PK_ANALIZ] AI Seçim Hatası: %s\n", pk_safe_log_text(conditionMessage(e))))
    return(NULL)
  })
}
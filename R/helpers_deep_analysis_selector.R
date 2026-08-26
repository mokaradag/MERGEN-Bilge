# ==============================================================================
# Dosya Yolu: R/helpers_deep_analysis_selector.R
# Açıklama: v1 (§10) AI TABANLI ÇOKLU sorgu seçicisi —
#           `find_multiple_queries_with_ai()`.
#
# NEDEN AYRI DOSYA: `R/helpers_deep_analysis.R` bakım ratchet bütçesine
# (659 satır) dayandı. Bu fonksiyon orkestrasyona ait değildir; kendi kendine
# yeten bir v1 seçicisidir ve v1 TEKİL seçicisinin (
# `R/helpers_pk_analysis_ai_selector.R`) tam karşılığıdır — ikisinin yan yana
# durması sınırı da netleştirir.
#
# DAVRANIŞ BİREBİR KORUNUR (§10: "The v1 decision logic must remain
# unchanged"): istem metni, konum kimliği (`ID: %d`), güven eşiği (30),
# tekrarlı seçim atlama ve sıralama DEĞİŞMEMİŞTİR. `MERGEN_PK_ENGINE=v2` iken
# bu yol HİÇ çalışmaz.
# ==============================================================================

# ------------------------------------------------------------------------------
# ÇOKLU SORGU SEÇİMİ (Derin Düşünme Modu)
# ------------------------------------------------------------------------------

#' AI ile birden fazla ilgili sorgu seç
#' @param user_prompt Kullanıcının sorusu
#' @param library Sorgu kütüphanesi (query_library)
#' @param session Shiny oturumu (API anahtarı çözümlemesi için)
#' @param max_queries Maksimum seçilecek sorgu sayısı
#' @return Seçilen sorgu listesi (her biri relevance_score ile)
find_multiple_queries_with_ai <- function(user_prompt, library, session,
                                          max_queries = pk_deep_max_queries(),
                                          timeout_sec = 12,
                                          stop_check = NULL) {
  cat("[DEEP_ANALYSIS] AI tabanlı çoklu sorgu seçimi başlatılıyor...\n")

  # Durdur bu seçiciye de ULAŞMALIDIR: `pk_deep_analysis_process()` DB
  # bağlantısını seçiciden ÖNCE açar, dolayısıyla iptal gözlenmezse hem işçi
  # hem DB bağlantısı çağrı dönene kadar meşgul kalırdı. Kapı hem çağrı
  # etrafında yoklanır hem de curl ilerleme geri çağrısı üzerinden aktarımı
  # ANINDA keser (bkz. helpers_pk_cancel_http.R).
  durduruldu <- function() {
    if (is.function(stop_check) && isTRUE(tryCatch(stop_check(), error = function(e) FALSE))) {
      return(TRUE)
    }
    exists("pk_active_stage_halt", mode = "function", inherits = TRUE) &&
      isTRUE(tryCatch(pk_active_stage_halt(), error = function(e) FALSE))
  }
  if (durduruldu()) {
    cat("[DEEP_ANALYSIS] Çoklu seçim iptal edildi (seçim başlamadı).\n")
    return(NULL)
  }

  # SKALER METİN ZORUNLU.
  #
  # `.pk_meta_validate_query_library()` yalnızca `id` ve `sql` alanlarını
  # doğrular; bir kütüphane girdisi `NULL` `name`/`description` taşıyabilir.
  # `sprintf()` o zaman `character(0)` döndürür ve `vapply(..., character(1))`
  # "values must be length 1" hatasıyla düşer. Bu blok aşağıdaki `tryCatch()`
  # sınırından ÖNCE çalıştığı için hata fonksiyondan KAÇAR ve tek sorguluk
  # yedek yol tamamen kaybolurdu.
  skaler <- function(x, yedek = "") {
    v <- as.character(x %||% yedek)
    if (!length(v) || is.na(v[1])) return(yedek)
    v[1]
  }

  library_context <- vapply(seq_along(library), function(i) {
    q <- library[[i]]
    sprintf("ID: %d | İSİM: %s | AÇIKLAMA: %s", i,
            skaler(q$name, "(isimsiz)"), skaler(q$description, "(açıklama yok)"))
  }, character(1))

  library_text <- paste(library_context, collapse = "\n")

  system_instruction <- paste0(
    "Sen bir Veritabanı Sorgu Yönlendiricisisin. Kullanıcının Türkçe sorusunu analiz edip ",
    "İLGİLİ TÜM SQL sorgularını seç. Birden fazla sorgu seçebilirsin.\n\n",
    "### MEVCUT SORGULAR:\n",
    library_text, "\n\n",
    "### KURALLLAR:\n",
    "1. Kullanıcının sorusuyla DOĞRUDAN veya DOLAYLI ilgili TÜM sorguları seç.\n",
    "2. En az 1, en fazla ", max_queries, " sorgu seç.\n",
    "3. Her sorgu için güven skoru belirt (0-100).\n",
    "4. Sadece gerçekten ilgili sorguları seç - alakasız sorgu ekleme.\n",
    "5. AYNI SORGUYU BİRDEN FAZLA SEÇME - her match_id benzersiz olmalı!\n",
    "6. Sorgular güven skoruna göre AZALAN sırada olmalı.\n\n",
    "### ZORUNLU JSON ÇIKTISI:\n",
    "{\"matches\": [{\"match_id\": 1, \"confidence\": 90, \"reason\": \"Kısa açıklama\"}, ...]}\n\n",
    "- match_id: Sorgu ID numarası (1'den başlar)\n",
    "- confidence: 0-100 arası güven skoru\n",
    "- reason: Neden bu sorguyu seçtin (tek cümle)\n\n",
    "Eğer hiç ilgili sorgu yoksa: {\"matches\": []}\n",
    "SADECE JSON döndür."
  )

  messages <- list(
    list(role = "system", content = system_instruction),
    list(role = "user", content = user_prompt)
  )

  tryCatch({
    model_name <- getOption("mergen.filter_model", api_config$local_models[1])
    creds <- resolve_local_llm_credentials(model_name)

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

    # Zaman aşımı artık KALAN analiz bütçesinden gelir (çağıran hesaplar);
    # sabit 12 saniye, birkaç saniye kalmış bir istekte mutlak son tarihi
    # aşmaya devam ederdi.
    etkin_timeout <- suppressWarnings(as.numeric(timeout_sec)[1])
    if (length(etkin_timeout) != 1L || is.na(etkin_timeout) || etkin_timeout <= 0) {
      etkin_timeout <- 12
    }

    # Türkçe yorum: R.utils::withTimeout() harici bir paket bağımlılığı
    # gerektirir ve `required_packages`/CI kurulum listesinde yer almaz; bu
    # da paket eksik olduğunda çağrının SESSİZCE her zaman NULL dönmesine
    # yol açar. Repo genelinde kullanılan `setTimeLimit()` deseniyle
    # (bkz. `helpers_pk_sql_execute.R::pk_sql_bounded_call()`) aynı
    # zaman-aşımı/hata davranışı, ek bağımlılık olmadan base R ile sağlanır.
    result <- tryCatch({
      setTimeLimit(cpu = Inf, elapsed = etkin_timeout, transient = TRUE)
      call_local_llm(messages, list(
        model_selection = model_name,
        temperature = 0.0,
        max_output_tokens = 500,
        enable_mcp_tools = FALSE,
        shiny_session = session,
        api_key_override = api_key_val,
        request_timeout_sec = etkin_timeout
      ))
    }, error = function(e) {
      cat(sprintf("[DEEP_ANALYSIS] AI çoklu seçim zaman aşımı/hata: %s\n", e$message))
      NULL
    }, finally = {
      try(setTimeLimit(cpu = Inf, elapsed = Inf, transient = TRUE), silent = TRUE)
    })

    if (durduruldu()) {
      cat("[DEEP_ANALYSIS] Çoklu seçim iptal edildi (sonuç kullanılmadı).\n")
      return(NULL)
    }

    if (is.null(result)) {
      cat("[DEEP_ANALYSIS] AI sonuç boş, tekil seçime düşülüyor.\n")
      return(NULL)
    }

    content <- if (is.list(result)) result$content else result
    content <- gsub("```json|```", "", content)
    content <- trimws(content)

    parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

    if (is.null(parsed$matches) || length(parsed$matches) == 0) {
      cat("[DEEP_ANALYSIS] AI eşleşme bulamadı.\n")
      return(NULL)
    }

    selected <- list()
    selected_indices <- integer(0)
    for (m in parsed$matches) {
      # BOZUK TEK KAYIT TÜM SEÇİMİ DÜŞÜRMEZ.
      #
      # `as.integer()` eksik alan için `integer(0)`, sayısal olmayan metin için
      # `NA_integer_` üretir; `idx > 0` her iki durumda da `&&` içinde HATA
      # fırlatır. Hata dıştaki `tryCatch`e ulaşır, fonksiyon `NULL` döner ve
      # GEÇERLİ tüm eşleşmeler kaybolarak derin analiz sessizce tek sorgu
      # seçimine düşerdi. Artık yalnızca bozuk kayıt atlanır.
      idx <- suppressWarnings(as.integer(m$match_id)[1])
      if (length(idx) == 1L && !is.na(idx) && idx > 0 && idx <= length(library)) {
        if (idx %in% selected_indices) {
          cat(sprintf("[DEEP_ANALYSIS] Tekrarlı sorgu atlandı: ID=%d ('%s')\n", idx, skaler(library[[idx]]$name, "(isimsiz)")))
          next
        }
        confidence <- suppressWarnings(as.numeric(m$confidence %||% 0)[1])
        if (length(confidence) != 1L || is.na(confidence)) next
        if (confidence >= 30) {
          q <- library[[idx]]
          q$relevance_score <- confidence
          q$selection_method <- "ai_deep"
          q$selection_reason <- m$reason %||% ""
          q$.matched_idx <- idx
          selected <- append(selected, list(q))
          selected_indices <- c(selected_indices, idx)
        }
      }
    }

    if (length(selected) == 0) return(NULL)

    scores <- vapply(selected, function(s) s$relevance_score, numeric(1))
    selected <- selected[order(scores, decreasing = TRUE)]

    if (length(selected) > max_queries) {
      selected <- selected[seq_len(max_queries)]
    }

    cat(sprintf("[DEEP_ANALYSIS] %d sorgu seçildi: %s\n",
                length(selected),
                paste(vapply(selected, function(s) skaler(s$name, "(isimsiz)"),
                             character(1)), collapse = ", ")))

    return(selected)

  }, error = function(e) {
    cat(sprintf("[DEEP_ANALYSIS] Çoklu sorgu seçim hatası: %s\n", e$message))
    return(NULL)
  })
}

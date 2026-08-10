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
                                          max_queries = pk_deep_max_queries()) {
  cat("[DEEP_ANALYSIS] AI tabanlı çoklu sorgu seçimi başlatılıyor...\n")

  library_context <- vapply(seq_along(library), function(i) {
    q <- library[[i]]
    sprintf("ID: %d | İSİM: %s | AÇIKLAMA: %s", i, q$name, q$description)
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

    api_key_val <- NULL
    if (!is.null(session) && !is.null(session$userData$ai_api_key)) {
      api_key_val <- as.character(session$userData$ai_api_key)[1]
    }
    if (is.null(api_key_val) || !nzchar(api_key_val)) {
      api_key_val <- creds$default_api_key
    }

    result <- tryCatch({
      R.utils::withTimeout({
        call_local_llm(messages, list(
          model_selection = model_name,
          temperature = 0.0,
          max_output_tokens = 500,
          enable_mcp_tools = FALSE,
          shiny_session = session,
          api_key_override = api_key_val
        ))
      }, timeout = 12, onTimeout = "silent")
    }, error = function(e) {
      cat(sprintf("[DEEP_ANALYSIS] AI çoklu seçim zaman aşımı/hata: %s\n", e$message))
      NULL
    })

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
      idx <- as.integer(m$match_id)
      if (!is.null(idx) && idx > 0 && idx <= length(library)) {
        if (idx %in% selected_indices) {
          cat(sprintf("[DEEP_ANALYSIS] Tekrarlı sorgu atlandı: ID=%d ('%s')\n", idx, library[[idx]]$name))
          next
        }
        confidence <- as.numeric(m$confidence %||% 0)
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
                paste(vapply(selected, function(s) s$name, character(1)), collapse = ", ")))

    return(selected)

  }, error = function(e) {
    cat(sprintf("[DEEP_ANALYSIS] Çoklu sorgu seçim hatası: %s\n", e$message))
    return(NULL)
  })
}

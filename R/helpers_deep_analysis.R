# ==============================================================================
# Dosya Yolu: R/helpers_deep_analysis.R
# Açıklama:   Derin Düşünme (Deep Thinking) modu için çoklu sorgu seçimi,
#              bireysel analiz ve toplu yorum oluşturma yardımcı fonksiyonları.
#              Proje ve Kaynak Analizi aracının gelişmiş analiz motoru.
# ==============================================================================

# ------------------------------------------------------------------------------
# SABİTLER
# ------------------------------------------------------------------------------

# Detay seviyesi tanımları
ANALYSIS_DETAIL_LEVELS <- list(
  ozet   = list(
    id    = "ozet",
    label = "Özet",
    description = "Kısa ve öz bulgular, temel istatistikler",
    max_tokens  = 1500,
    preview_rows = 10,
    instruction = paste0(
      "KISA VE ÖZ yanıt ver. Sadece EN ÖNEMLİ 2-3 bulguyu belirt. ",
      "Uzun açıklamalardan kaçın, madde işaretleri kullan. ",
      "Toplamda 5-8 cümleyi geçme."
    )
  ),
  standart = list(
    id    = "standart",
    label = "Standart",
    description = "Dengeli detay seviyesi, temel analiz ve öneriler",
    max_tokens  = 3000,
    preview_rows = 20,
    instruction = paste0(
      "DENGELİ bir analiz sun. Önemli bulguları, temel istatistikleri ve ",
      "kısa öneriler içer. Her sorgu için 1-2 paragraf yeterli. ",
      "Gereksiz detaylardan kaçın ama önemli noktaları atla."
    )
  ),
  detayli = list(
    id    = "detayli",
    label = "Detaylı",
    description = "Kapsamlı analiz, kök sebepler ve detaylı öneriler",
    max_tokens  = 4096,
    preview_rows = 50,
    instruction = paste0(
      "DERİNLEMESİNE analiz yap. Her sütunun hikayesini anlat, ",
      "dağılımları, anormallikleri ve eğilimleri detaylı incele. ",
      "Kök sebep analizi yap ve spesifik, uygulanabilir öneriler sun. ",
      "Tablolar ve karşılaştırmalar kullan."
    )
  )
)

#' Detay seviyesi yapılandırmasını döndür
#' @param level_id Seviye kimliği ("ozet", "standart", "detayli")
#' @return Detay seviyesi yapılandırma listesi
get_analysis_detail_config <- function(level_id) {
  config <- ANALYSIS_DETAIL_LEVELS[[level_id]]
  if (is.null(config)) {
    config <- ANALYSIS_DETAIL_LEVELS[["standart"]]
  }
  return(config)
}

#' Detay seviyesi talimatını döndür
#' @param level_id Seviye kimliği
#' @return Karakter dizisi olarak talimat metni
get_analysis_detail_instruction <- function(level_id) {
  config <- get_analysis_detail_config(level_id)
  return(config$instruction)
}

# ------------------------------------------------------------------------------
# ÇOKLU SORGU SEÇİMİ (Derin Düşünme Modu)
# ------------------------------------------------------------------------------

#' AI ile birden fazla ilgili sorgu seç
#' @param user_prompt Kullanıcının sorusu
#' @param library Sorgu kütüphanesi (query_library)
#' @param session Shiny oturumu (API anahtarı çözümlemesi için)
#' @param max_queries Maksimum seçilecek sorgu sayısı
#' @return Seçilen sorgu listesi (her biri relevance_score ile)
find_multiple_queries_with_ai <- function(user_prompt, library, session, max_queries = 5) {
  cat("[DEEP_ANALYSIS] AI tabanlı çoklu sorgu seçimi başlatılıyor...\n")

  # Kütüphane özetini hazırla
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

    # Eşleşmeleri işle (tekrarlı sorguları engelle)
    selected <- list()
    selected_indices <- integer(0)
    for (m in parsed$matches) {
      idx <- as.integer(m$match_id)
      if (!is.null(idx) && idx > 0 && idx <= length(library)) {
        # Aynı sorgu zaten seçildiyse atla
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

    # Güven skoruna göre sırala (azalan)
    scores <- vapply(selected, function(s) s$relevance_score, numeric(1))
    selected <- selected[order(scores, decreasing = TRUE)]

    # Maksimum sorgu sayısını uygula
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

# ------------------------------------------------------------------------------
# TEKİL SORGU İŞLEME (Bağımsız Bağlam Penceresi)
# ------------------------------------------------------------------------------

#' Tek bir sorguyu çalıştır ve istatistiksel özet oluştur
#' @param query Sorgu tanımı (library öğesi)
#' @param user_prompt Kullanıcı sorusu
#' @param session Shiny oturumu
#' @param rls_info Kullanıcının yetki bilgisi
#' @param detail_config Detay seviyesi yapılandırması
#' @param stop_check Durdurma kontrol fonksiyonu
#' @return İşlenmiş sorgu sonucu listesi veya NULL (hata durumunda)
execute_single_deep_query <- function(query, user_prompt, session, rls_info,
                                       detail_config, stop_check = NULL) {
  query_name <- query$name %||% "Bilinmeyen Sorgu"
  cat(sprintf("[DEEP_QUERY] İşleniyor: '%s'\n", query_name))

  if (is.function(stop_check) && isTRUE(stop_check())) {
    cat(sprintf("[DEEP_QUERY] '%s' - Durdurma talebi alındı.\n", query_name))
    return(NULL)
  }

  # 1. Bağlantı kur
  conn_list <- tryCatch(get_connection(target = query$db_target %||% "primary"), error = function(e) NULL)
  if (is.null(conn_list)) {
    cat(sprintf("[DEEP_QUERY] '%s' - DB bağlantısı kurulamadı.\n", query_name))
    return(list(
      query_name = query_name,
      success = FALSE,
      error_msg = "Veritabanı bağlantısı kurulamadı."
    ))
  }
  conn <- conn_list$conn
  on.exit(release_connection(conn_list), add = TRUE)

  # 2. SQL içeriğini belirle
  sql_query_text <- ""
  if (!is.null(query$sql_file) && nzchar(query$sql_file)) {
    fpath <- query$sql_file
    if (file.exists(fpath)) {
      # Dosyadan oku (basitleştirilmiş - ana modüldeki gibi kodlama kontrolü)
      sql_query_text <- tryCatch({
        f_con <- file(fpath, open = "rb")
        f_size <- file.info(fpath)$size
        if (is.na(f_size)) f_size <- 0
        raw_content <- readBin(f_con, "raw", n = f_size)
        close(f_con)

        has_bom_le <- length(raw_content) >= 2 && raw_content[1] == as.raw(0xff) && raw_content[2] == as.raw(0xfe)
        has_nulls <- any(raw_content == as.raw(0))

        if (has_bom_le || has_nulls) {
          iconv(list(raw_content), from = "UTF-16LE", to = "UTF-8")[[1]]
        } else {
          text_utf8 <- iconv(list(raw_content), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
          if (grepl("<[0-9a-fA-F]{2}>", text_utf8)) {
            converted <- iconv(list(raw_content), from = "WINDOWS-1254", to = "UTF-8")
            if (length(converted) > 0 && !is.na(converted[[1]])) converted[[1]] else text_utf8
          } else {
            text_utf8
          }
        }
      }, error = function(e) "")

      sql_query_text <- gsub("^\ufeff", "", sql_query_text)
    }
  }
  if (!nzchar(sql_query_text) && !is.null(query$sql)) {
    sql_query_text <- query$sql
  }

  if (!nzchar(sql_query_text)) {
    return(list(query_name = query_name, success = FALSE, error_msg = "SQL kodu bulunamadı."))
  }

  # Güvenlik kontrolü
  if (grepl("\\b(DELETE|DROP|TRUNCATE|ALTER)\\b", toupper(sql_query_text))) {
    return(list(query_name = query_name, success = FALSE, error_msg = "Güvenlik ihlali."))
  }

  # 3. Sorguyu çalıştır
  raw_data <- tryCatch(
    DBI::dbGetQuery(conn, trimws(sql_query_text)),
    error = function(e) {
      cat(sprintf("[DEEP_QUERY] '%s' - SQL hatası: %s\n", query_name, e$message))
      NULL
    }
  )

  if (is.null(raw_data) || nrow(raw_data) == 0) {
    return(list(query_name = query_name, success = FALSE, error_msg = "Sorgu sonucu boş."))
  }

  if (is.function(stop_check) && isTRUE(stop_check())) return(NULL)

  # 4. Tarih sütunlarını dönüştür
  if (!is.null(query$date_columns)) {
    raw_data <- convert_date_columns(raw_data, query$date_columns)
  }

  # 5. RLS uygula
  secure_data <- apply_rls_to_data(raw_data, rls_info, query$rls_columns)
  if (nrow(secure_data) == 0) {
    return(list(query_name = query_name, success = FALSE, error_msg = "Yetki dahilinde veri bulunamadı."))
  }

  # 6. Akıllı filtreleme (AI destekli)
  if (isTRUE(query$disable_ai_filters)) {
    filtered_data <- secure_data
    filter_criteria <- list(filters = list(), aggregation = NULL)
  } else {
    available_columns <- names(secure_data)
    filter_criteria <- extract_filter_criteria_from_prompt(
      user_prompt, secure_data, available_columns, conn, session, stop_check = stop_check
    )
    filtered_data <- apply_smart_filters(secure_data, filter_criteria, user_prompt)
  }

  if (nrow(filtered_data) == 0) {
    return(list(
      query_name = query_name,
      success = FALSE,
      error_msg = "Filtreleme sonrası veri bulunamadı."
    ))
  }

  if (is.function(stop_check) && isTRUE(stop_check())) return(NULL)

  # 7. İstatistiksel özet oluştur (detay seviyesine göre kısıtlı)
  preview_rows <- detail_config$preview_rows %||% 20
  stat_summary <- generate_statistical_summary(
    filtered_data,
    max_preview_rows = min(preview_rows, nrow(filtered_data)),
    mode = "summary",
    rls_total_rows = nrow(secure_data),
    user_filter_applied = (nrow(filtered_data) < nrow(secure_data)),
    pre_aggregated_columns = q$pre_aggregated_columns
  )

  # Önizleme JSON
  preview_json <- if (!is.null(stat_summary$preview_data) && nrow(stat_summary$preview_data) > 0) {
    jsonlite::toJSON(head(stat_summary$preview_data, min(10, nrow(stat_summary$preview_data))),
                     auto_unbox = TRUE, pretty = FALSE)
  } else {
    "{}"
  }

  cat(sprintf("[DEEP_QUERY] '%s' - Başarılı: %d satır, özet oluşturuldu.\n",
              query_name, stat_summary$row_count))

  return(list(
    query_name  = query_name,
    query_desc  = query$description %||% "",
    success     = TRUE,
    row_count   = stat_summary$row_count,
    summary_text = stat_summary$summary_text,
    preview_json = preview_json,
    relevance    = query$relevance_score %||% 0
  ))
}

# ------------------------------------------------------------------------------
# ÇOKLU SONUÇ BİRLEŞTİRME VE GENEL YORUM OLUŞTURMA
# ------------------------------------------------------------------------------

#' Bireysel sorgu sonuçlarını birleştirip LLM bağlamı oluştur
#' @param query_results execute_single_deep_query sonuçlarının listesi
#' @param user_prompt Kullanıcı sorusu
#' @param detail_config Detay seviyesi yapılandırması
#' @return LLM'e gönderilecek sistem promptu ve kullanıcı bağlamı
build_deep_analysis_context <- function(query_results, user_prompt, detail_config) {

  # Başarılı sonuçları filtrele
  successful <- Filter(function(r) isTRUE(r$success), query_results)
  failed <- Filter(function(r) !isTRUE(r$success), query_results)

  if (length(successful) == 0) {
    return(list(
      type = "error_message",
      content = paste0(
        "🔍 **Derin Analiz Sonucu:** Hiçbir sorgu başarılı sonuç döndürmedi.\n\n",
        if (length(failed) > 0) {
          paste0("Başarısız sorgular:\n",
                 paste(vapply(failed, function(f) {
                   sprintf("- **%s**: %s", f$query_name, f$error_msg %||% "Bilinmeyen hata")
                 }, character(1)), collapse = "\n"))
        } else ""
      )
    ))
  }

  detail_instruction <- detail_config$instruction %||% ""
  base_max_tokens <- detail_config$max_tokens %||% 3000
  query_count <- length(successful)

  # Çoklu sorgu varsa max_tokens'ı ölçekle - her ek sorgu için %30 artır
  # Aksi halde LLM tüm sorguları raporlayamadan kesebilir
  if (query_count > 1) {
    scale_factor <- 1 + (query_count - 1) * 0.3
    max_tokens <- min(as.integer(base_max_tokens * scale_factor), 8192)
  } else {
    max_tokens <- base_max_tokens
  }

  # Her sorgu sonucunu bağlam bloğuna dönüştür
  data_blocks <- vapply(seq_along(successful), function(i) {
    r <- successful[[i]]
    paste0(
      sprintf("\n\n══════════════════════════════════════════\n"),
      sprintf("📊 SORGU %d/%d: %s\n", i, query_count, r$query_name),
      sprintf("Açıklama: %s\n", r$query_desc),
      sprintf("Toplam Satır: %d | İlgililik: %.0f%%\n", r$row_count, r$relevance),
      sprintf("══════════════════════════════════════════\n"),
      r$summary_text,
      "\n\n--- ÖRNEK VERİ (JSON) ---\n",
      r$preview_json,
      sprintf("\n(Bu sorgu %d satırlık veri içermektedir)\n", r$row_count)
    )
  }, character(1))

  combined_data <- paste(data_blocks, collapse = "\n")

  # Sistem promptu oluştur
  system_prompt <- paste0(
    "Sen MERGEN'in kıdemli veri analisti asistanısın. Primavera P6 ve SAP PS konusunda 15+ yıl deneyimin var.\n\n",

    "### DERİN ANALİZ MODU\n",
    "Bu istekte ÇOKLU SORGU sonuçları sunulmuştur. Görevin:\n",
    "1. HER SORGUYU BİREYSEL olarak analiz et - kendi bölümünde\n",
    "2. Sorgular arası İLİŞKİLERİ ve ORTAK PATERNLERİ tespit et\n",
    "3. GENEL BİR DEĞERLENDİRME ile bitir\n\n",

    "### DETAY SEVİYESİ TALİMATI:\n",
    detail_instruction, "\n\n",

    "### ZORUNLU YAPI:\n",
    "Her sorgu için:\n",
    "## 📊 [Sorgu Adı]\n",
    "- Temel bulgular ve istatistikler\n",
    "- Dikkat çeken noktalar\n\n",

    "Son bölüm:\n",
    "## 🔗 Genel Değerlendirme\n",
    "- Sorgular arası bağlantılar ve çapraz bulgular\n",
    "- Bütünsel öneriler\n",
    "- Uyarılar ve riskler\n\n",

    "### KRİTİK KURALLAR:\n",
    "- Sayıları DOĞRUDAN kullan, tahmin veya varsayım YAPMA\n",
    "- Her yorum veriye dayalı olmalı\n",
    "- Profesyonel, güvenilir ve net Türkçe kullan\n",
    "- \"Muhtemelen\", \"belki\" gibi belirsizliklerden kaçın\n",
    "- Markdown tablo formatını listeleme/sıralama için kullan\n",
    "- FİLTRELEME UYARISI varsa, oran belirtirken dikkatli ol\n",
    "- Başarısız sorgular varsa, bunları da raporla (hangileri ve neden başarısız olduklarını kısaca belirt)\n",
    "- TÜM başarılı sorguları mutlaka raporla - hiçbirini atlama!\n"
  )

  # Başarısız sorgu bilgisi - LLM'e belirgin şekilde sun
  failed_note <- ""
  if (length(failed) > 0) {
    failed_note <- paste0(
      "\n\n══════════════════════════════════════════\n",
      sprintf("⚠️ BAŞARISIZ SORGULAR (%d adet)\n", length(failed)),
      "══════════════════════════════════════════\n",
      paste(vapply(failed, function(f) {
        sprintf("- **%s**: %s", f$query_name, f$error_msg %||% "Hata")
      }, character(1)), collapse = "\n"),
      "\n\nBu sorguları yanıtında kısaca belirt: hangi sorguların veri döndüremediğini ",
      "ve olası nedenlerini kullanıcıya bildir.\n"
    )
  }

  # Kullanıcı bağlamı
  user_context <- paste0(
    "KULLANICI SORUSU:\n",
    user_prompt,
    "\n\n--- R TARAFINDAN HAZIRLANAN ÇOKLU SORGU SONUÇLARI ---\n",
    sprintf("Toplam %d sorgu başarıyla çalıştırıldı.\n", query_count),
    combined_data,
    failed_note,
    "\n\n--- SONUÇLAR SONU ---\n\n",
    "Talimat: Yukarıdaki TÜM sorgu sonuçlarını bireysel ve bütünsel olarak analiz et. ",
    "Her sorguyu kendi bölümünde değerlendir, sonra genel bir sentez yap."
  )

  return(list(
    type = "data_analysis",
    prompt_context = system_prompt,
    user_context = user_context,
    query_count = query_count,
    max_tokens = max_tokens
  ))
}

# ------------------------------------------------------------------------------
# ANA DERİN ANALİZ ORKESTRATÖRÜ
# ------------------------------------------------------------------------------

#' Derin düşünme modunda çoklu sorgu analizi yap
#' @param user_prompt Kullanıcı sorusu
#' @param chat_history Sohbet geçmişi
#' @param session Shiny oturumu
#' @param detail_level Detay seviyesi ("ozet", "standart", "detayli")
#' @param stop_check Durdurma kontrol fonksiyonu
#' @return LLM bağlamı listesi veya hata mesajı
pk_deep_analysis_process <- function(user_prompt, chat_history, session,
                                      detail_level = "standart",
                                      stop_check = NULL) {
  cat("\n[DEEP_ANALYSIS] >>> DERİN ANALİZ BAŞLATILDI <<<\n")
  cat(sprintf("[DEEP_ANALYSIS] Detay Seviyesi: %s\n", detail_level))
  cat(sprintf("[DEEP_ANALYSIS] Kullanıcı Sorusu: '%s'\n", user_prompt))

  if (is.function(stop_check) && isTRUE(stop_check())) {
    return("⚠️ **İşlem Durduruldu:** Analiz kullanıcı tarafından iptal edildi.")
  }

  detail_config <- get_analysis_detail_config(detail_level)

  # A. DB Bağlantısı ve RLS kontrolü
  conn_list <- get_connection()
  conn <- conn_list$conn

  username <- session$userData$system_username %||% "Unknown"
  rls_info <- get_user_rls_info(username, conn)
  release_connection(conn_list)

  if (!isTRUE(rls_info$authorized)) {
    return("⚠️ **Yetki Hatası:** Sistemde kullanıcı kaydınız bulunamadı.")
  }

  if (is.function(stop_check) && isTRUE(stop_check())) {
    return("⚠️ **İşlem Durduruldu:** Analiz iptal edildi.")
  }

  # B. Çoklu sorgu seçimi (AI)
  selected_queries <- find_multiple_queries_with_ai(user_prompt, query_library, session, max_queries = 5)

  if (is.null(selected_queries) || length(selected_queries) == 0) {
    cat("[DEEP_ANALYSIS] Çoklu seçim başarısız, tekil seçime düşülüyor.\n")

    # Tekil seçime düş (mevcut select_smart_query kullan)
    single <- select_smart_query(user_prompt, query_library, chat_history)
    if (!is.null(single) && !is.null(single$id)) {
      selected_queries <- list(single)
    } else {
      return("🤔 Aradığınız bilgi mevcut analiz kütüphanesinde bulunamadı. Lütfen sorunuzu farklı kelimelerle deneyin.")
    }
  }

  cat(sprintf("[DEEP_ANALYSIS] %d sorgu işlenecek.\n", length(selected_queries)))

  if (is.function(stop_check) && isTRUE(stop_check())) {
    return("⚠️ **İşlem Durduruldu:** Analiz iptal edildi.")
  }

  # C. Her sorguyu bağımsız olarak çalıştır
  query_results <- list()
  for (i in seq_along(selected_queries)) {
    if (is.function(stop_check) && isTRUE(stop_check())) {
      cat(sprintf("[DEEP_ANALYSIS] Sorgu %d/%d - Durdurma talebi.\n", i, length(selected_queries)))
      break
    }

    cat(sprintf("[DEEP_ANALYSIS] Sorgu %d/%d işleniyor: '%s'\n",
                i, length(selected_queries), selected_queries[[i]]$name))

    result <- tryCatch(
      execute_single_deep_query(
        query = selected_queries[[i]],
        user_prompt = user_prompt,
        session = session,
        rls_info = rls_info,
        detail_config = detail_config,
        stop_check = stop_check
      ),
      error = function(e) {
        cat(sprintf("[DEEP_ANALYSIS] Sorgu hatası: %s\n", e$message))
        list(
          query_name = selected_queries[[i]]$name %||% "?",
          success = FALSE,
          error_msg = e$message
        )
      }
    )

    if (!is.null(result)) {
      query_results <- append(query_results, list(result))
    }
  }

  if (length(query_results) == 0) {
    return("⚠️ **Derin Analiz:** Hiçbir sorgu çalıştırılamadı. Lütfen tekrar deneyin.")
  }

  # D. Sonuçları birleştir
  successful_count <- sum(vapply(query_results, function(r) isTRUE(r$success), logical(1)))
  failed_count <- length(query_results) - successful_count
  cat(sprintf("[DEEP_ANALYSIS] %d sorgu tamamlandı (%d başarılı, %d başarısız), bağlam oluşturuluyor...\n",
              length(query_results), successful_count, failed_count))

  if (failed_count > 0) {
    failed_names <- vapply(
      Filter(function(r) !isTRUE(r$success), query_results),
      function(r) sprintf("%s (%s)", r$query_name, r$error_msg %||% "bilinmeyen hata"),
      character(1)
    )
    cat(sprintf("[DEEP_ANALYSIS] Başarısız sorgular: %s\n", paste(failed_names, collapse = "; ")))
  }

  context <- build_deep_analysis_context(query_results, user_prompt, detail_config)

  cat("[DEEP_ANALYSIS] >>> DERİN ANALİZ BAĞLAMI HAZIR <<<\n")
  return(context)
}
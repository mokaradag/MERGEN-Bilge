# ==============================================================================
# Dosya Yolu: R/helpers_deep_analysis.R
# Açıklama:   Derin Düşünme (Deep Thinking) modu için çoklu sorgu seçimi,
#              bireysel sorgu çalıştırma ve orkestrasyon.
#              Proje ve Kaynak Analizi aracının gelişmiş analiz motoru.
#
# BÖLÜNME NOTU (bakım borcu ratchet'i):
#   Bu dosya ratchet bütçesini (659 satır / 15 fonksiyon) aştığı için iki saf
#   yardımcıya bölünmüştür ve bunlar manifestte BU DOSYADAN ÖNCE yüklenir:
#     * R/helpers_deep_analysis_detail.R  -> detay seviyesi kataloğu ve
#       get_analysis_detail_config() / get_analysis_detail_instruction()
#     * R/helpers_deep_analysis_context.R -> build_deep_analysis_context()
#   Bu fonksiyonları buraya geri taşımayın; bütçe yeniden aşılır. Bu dosyayı
#   yalıtılmış olarak source eden testler, ihtiyaç duydukları yardımcının
#   dosyasını da source etmelidir.
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

# ------------------------------------------------------------------------------
# TEKİL SORGU İŞLEME (Bağımsız BağLAM PENCERESİ)
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
  query_started_at <- Sys.time()

  finish_result <- function(result,
                            filter_status = "not_reached",
                            filters = list(),
                            pre_rls_rows = NA_integer_,
                            authorized_rows = NA_integer_,
                            filtered_rows = NA_integer_,
                            outcome = NULL) {
    if (is.null(outcome)) {
      outcome <- if (isTRUE(result$success)) "Basarili" else "Hata"
    }

    result$pk_observation <- list(
      query_id = query$id,
      query_name = query_name,
      filter_status = filter_status,
      filters = filters %||% list(),
      pre_rls_rows = pre_rls_rows,
      authorized_rows = authorized_rows,
      filtered_rows = filtered_rows,
      outcome = outcome,
      duration_ms = as.numeric(difftime(Sys.time(), query_started_at, units = "secs")) * 1000
    )
    result
  }

  cat(sprintf("[DEEP_QUERY] İşleniyor: '%s'\n", query_name))

  if (is.function(stop_check) && isTRUE(stop_check())) {
    cat(sprintf("[DEEP_QUERY] '%s' - Durdurma talebi alındı.\n", query_name))
    return(NULL)
  }

  conn_list <- tryCatch(get_connection(target = query$db_target %||% "primary"), error = function(e) NULL)
  if (is.null(conn_list)) {
    cat(sprintf("[DEEP_QUERY] '%s' - DB bağlantısı kurulamadı.\n", query_name))
    return(finish_result(list(
      query_name = query_name,
      success = FALSE,
      error_msg = "Veritabanı bağlantısı kurulamadı."
    )))
  }
  conn <- conn_list$conn
  on.exit(release_connection(conn_list), add = TRUE)

  # D16: SQL kayna\u011f\u0131 ANA YOL ile ayn\u0131d\u0131r \u2014 startup'ta \u00f6ny\u00fcklenen `query$sql`
  # B\u0130R\u0130NC\u0130LD\u0130R. Eski kod dosyay\u0131 \u0130STEK ANINDA yeniden okuyordu; UNC'de yava\u015ft\u0131
  # ve tekil modun \u00e7al\u0131\u015ft\u0131rd\u0131\u011f\u0131 metinden sapabiliyordu.
  sql_source <- pk_deep_query_sql_text(query)
  sql_query_text <- sql_source$sql
  if (!identical(sql_source$source, "preloaded") && nzchar(sql_query_text)) {
    cat(sprintf("[DEEP_QUERY] '%s' - UYARI: onyuklu SQL bos, dosyaya dusuldu.\n", query_name))
  }

  if (!nzchar(sql_query_text)) {
    return(finish_result(list(
      query_name = query_name,
      success = FALSE,
      error_msg = "SQL kodu bulunamadı."
    )))
  }

  # D23 + D16: Derin mod da ANA YOL ile ayni salt-okunur kapisini kullanir.
  # Eski satir toupper() ile yerel bagimliydi (Turkce Windows'ta "I" sorunu) ve
  # yalnizca dort komutu engelleyen bir KARA LISTE idi.
  sql_gate <- pk_sql_readonly_guard(sql_query_text, context_label = "DEEP_QUERY")
  if (!isTRUE(sql_gate$allowed)) {
    return(finish_result(list(
      query_name = query_name,
      success = FALSE,
      error_msg = "Güvenlik ihlali: sorgu salt-okunur olarak doğrulanamadı."
    )))
  }

  # D16 + Faz 6 (§5.10): ANA YOL ile aynı Unicode parametre yolu (Türkçe/köşeli
  # parantezli sütun adları), ifade zaman aşımı, sınırlı parça getirimi ve
  # parçalar arasında iptal/son tarih yoklaması. Eski satır düz
  # `DBI::dbGetQuery()` idi ve iki mod Türkçe tanımlayıcılarda FARKLI davranıyordu.
  # Önbellek anahtarı YETKİ İMZASINI taşır; isabet hiçbir kapıyı atlamaz (aşağıda
  # gerçek-sütun doğrulaması ve RLS koşulsuz çalışır).
  sql_exec <- pk_deep_execute_sql(
    conn = conn, sql_text = sql_query_text,
    deadline_at = detail_config$pk_deadline_at,
    cancel_token = detail_config$pk_cancel_token,
    query_meta = query$meta,
    cache_key = pk_query_result_cache_key(query, rls_info, sql_query_text, engine = "deep")
  )

  if (identical(sql_exec$status, "cancelled")) return(NULL)

  if (!identical(sql_exec$status, "ok")) {
    cat(sprintf("[DEEP_QUERY] '%s' - SQL durumu: %s\n", query_name, sql_exec$status))
    return(finish_result(list(
      query_name = query_name,
      success = FALSE,
      error_msg = switch(
        sql_exec$status,
        deadline = "Analiz zaman aşımına uğradı; sorgu çalıştırılamadı.",
        too_large = "Sonuç kümesi güvenli bellek sınırını aşıyor.",
        "Sorgu çalıştırılamadı."
      )
    )))
  }

  raw_data <- sql_exec$data

  if (is.null(raw_data)) {
    return(finish_result(list(
      query_name = query_name,
      success = FALSE,
      error_msg = "Sorgu çalıştırılamadı."
    )))
  }

  if (nrow(raw_data) == 0) {
    return(finish_result(
      list(query_name = query_name, success = FALSE, error_msg = "Sorgu sonucu boş."),
      pre_rls_rows = 0L,
      authorized_rows = 0L,
      filtered_rows = 0L,
      outcome = "BosSonuc"
    ))
  }

  if (is.function(stop_check) && isTRUE(stop_check())) return(NULL)

  if (!is.null(query$date_columns)) {
    raw_data <- convert_date_columns(raw_data, query$date_columns)
  }

  # D6/D6b: RLS kapali basarisiz oldugunda derin modda TEK sorgu basarisiz olur;
  # calisma devam eder ve hata build_deep_analysis_context() ile raporlanir.
  meta_gate <- pk_meta_actual_column_gate(query, names(raw_data), FALSE)
  if (isTRUE(meta_gate$abort)) {
    return(finish_result(list(
      query_name = query_name,
      success = FALSE,
      error_msg = "Yetki sütunu doğrulanamadı; sorgu güvenli biçimde çalıştırılamadı."
    )))
  }

  secure_data <- tryCatch(
    apply_rls_to_data(raw_data, rls_info, query$rls_columns),
    pk_rls_error = function(e) NULL
  )
  if (is.null(secure_data)) {
    return(finish_result(list(
      query_name = query_name,
      success = FALSE,
      error_msg = "Satır düzeyi yetki kuralları uygulanamadı; sorgu atlandı."
    )))
  }
  if (nrow(secure_data) == 0) {
    return(finish_result(
      list(query_name = query_name, success = FALSE, error_msg = "Yetki dahilinde veri bulunamadı."),
      pre_rls_rows = nrow(raw_data),
      authorized_rows = 0L,
      filtered_rows = 0L,
      outcome = "BosSonuc"
    ))
  }

  if (isTRUE(query$disable_ai_filters)) {
    filtered_data <- secure_data
    filter_criteria <- list(filters = list(), aggregation = NULL, status = "disabled")
  } else {
    available_columns <- names(secure_data)
    filter_criteria <- extract_filter_criteria_from_prompt(
      user_prompt, secure_data, available_columns, conn, session, stop_check = stop_check
    )
    filtered_data <- apply_smart_filters(secure_data, filter_criteria, user_prompt)
  }

  filter_status <- filter_criteria$status %||% if (length(filter_criteria$filters %||% list()) > 0L) {
    "ok_filtered"
  } else {
    "ok_no_filter"
  }
  applied_filters <- filter_criteria$filters %||% list()

  if (nrow(filtered_data) == 0) {
    return(finish_result(
      list(
        query_name = query_name,
        success = FALSE,
        error_msg = "Filtreleme sonrası veri bulunamadı."
      ),
      filter_status = filter_status,
      filters = applied_filters,
      pre_rls_rows = nrow(raw_data),
      authorized_rows = nrow(secure_data),
      filtered_rows = 0L,
      outcome = "BosSonuc"
    ))
  }

  if (is.function(stop_check) && isTRUE(stop_check())) return(NULL)

  preview_rows <- detail_config$preview_rows %||% 20
  stat_summary <- generate_statistical_summary(
    filtered_data,
    max_preview_rows = min(preview_rows, nrow(filtered_data)),
    mode = "summary",
    rls_total_rows = nrow(secure_data),
    user_filter_applied = (nrow(filtered_data) < nrow(secure_data)),
    pre_aggregated_columns = query$pre_aggregated_columns
  )

  preview_json <- if (!is.null(stat_summary$preview_data) && nrow(stat_summary$preview_data) > 0) {
    jsonlite::toJSON(head(stat_summary$preview_data, min(10, nrow(stat_summary$preview_data))),
                     auto_unbox = TRUE, pretty = FALSE)
  } else {
    "{}"
  }

  cat(sprintf("[DEEP_QUERY] '%s' - Başarılı: %d satır, özet oluşturuldu.\n",
              query_name, stat_summary$row_count))

  finish_result(
    list(
      query_name = query_name,
      query_desc = query$description %||% "",
      success = TRUE,
      row_count = stat_summary$row_count,
      summary_text = stat_summary$summary_text,
      preview_json = preview_json,
      relevance = query$relevance_score %||% 0
    ),
    filter_status = filter_status,
    filters = applied_filters,
    pre_rls_rows = nrow(raw_data),
    authorized_rows = nrow(secure_data),
    filtered_rows = nrow(filtered_data),
    outcome = "Basarili"
  )
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

  pk_started_at <- Sys.time()
  pk_request_id <- if (exists("pk_provenance_current_request_id", mode = "function", inherits = TRUE)) {
    pk_provenance_current_request_id(session)
  } else {
    NULL
  }

  if (is.function(stop_check) && isTRUE(stop_check())) {
    return("\U000026A0\U0000FE0F **İşlem Durduruldu:** Analiz kullanıcı tarafından iptal edildi.")
  }

  detail_config <- get_analysis_detail_config(detail_level)

  # Faz 6 (§5.10): TÜM analizin duvar-saati son tarihi ve iptal jetonu, her
  # sorgunun SQL yürütmesine taşınır. Ardışık geçerli SQL zaman aşımlarının
  # toplamı bu bütçeyi AŞAMAZ; sonraki derin sorgu yalnızca KALAN bütçeyi alır.
  detail_config$pk_deadline_at <- pk_deadline_at(
    pk_started_at,
    tryCatch(pk_config_resolve("MERGEN_PK_ANALYSIS_DEADLINE_SEC"), error = function(e) 300L)
  )
  detail_config$pk_cancel_token <- if (nzchar(as.character(pk_request_id %||% "")[1])) {
    pk_cancel_token_path(pk_request_id)
  } else {
    NULL
  }

  # D16: kimlik ANA YOL ile AYNI kapıdan geçer. Eski satır
  # `session$userData$system_username %||% "Unknown"` idi ve SSO hazırlık
  # kapısını ATLIYORDU: derin mod RLS aramasını "Unknown" olarak yapabiliyordu.
  # Kimlik hazır değilse DB'ye HİÇ gidilmez.
  identity_state <- pk_deep_resolve_username(session)
  if (!isTRUE(identity_state$ready)) {
    cat(sprintf("[DEEP_ANALYSIS] Kimlik hazir degil. Sebep: %s\n", identity_state$reason))
    return(identity_state$message)
  }
  username <- identity_state$username

  conn_list <- get_connection()
  conn <- conn_list$conn
  on.exit(release_connection(conn_list), add = TRUE)

  # Gözlem + birleşik köken alt bilgisi kapanışları FABRİKADADIR
  # (R/helpers_deep_analysis_reconcile.R): orkestratör bakım ratchet bütçesinin
  # (659 satır) altında kalmalıdır. Davranış BİREBİR korunur.
  deep_observers <- pk_deep_observation_helpers(
    session = session, conn = conn, username = username,
    user_prompt = user_prompt, request_id = pk_request_id,
    started_at = pk_started_at
  )
  pk_observe_deep <- deep_observers$observe
  stash_deep_footer <- deep_observers$stash

  rls_info <- get_user_rls_info(username, conn)

  if (!isTRUE(rls_info$authorized)) {
    pk_observe_deep(list(
      query_name = "Derin analiz",
      filter_status = "not_reached",
      filters = list(),
      outcome = "Yetkisiz"
    ))
    return("\U000026A0\U0000FE0F **Yetki Hatası:** Sistemde kullanıcı kaydınız bulunamadı.")
  }

  if (is.function(stop_check) && isTRUE(stop_check())) {
    pk_observe_deep(list(
      query_name = "Derin analiz",
      filter_status = "stopped",
      filters = list(),
      outcome = "Durduruldu"
    ))
    return("\U000026A0\U0000FE0F **İşlem Durduruldu:** Analiz iptal edildi.")
  }

  # Faz 5 motor sınırı (§5.2 / §10): `MERGEN_PK_ENGINE=v2` iken Derin Düşünme de
  # kapılardan geçer. Eski akış `find_multiple_queries_with_ai()` kullanıyordu;
  # o seçici KONUM kimliğiyle çalışır ve kararlı kimlik/yetenek/güven/marj ile
  # reddetme kapılarının HİÇBİRİNİ uygulamaz — yani Derin Düşünme açıkken
  # v2'nin tüm güvenlik sözleşmesi sessizce devre dışı kalıyordu.
  pk_v2_secim <- exists("pk_engine_is_v2", mode = "function", inherits = TRUE) &&
    isTRUE(pk_engine_is_v2()) &&
    exists("pk_select_query_v2", mode = "function", inherits = TRUE)

  # Faz 6: sıralı-küme tavanı YAPILANDIRMADAN gelir (§9/§10); kodda sabit 5 kalmaz.
  deep_query_ceiling <- pk_deep_max_queries()

  selected_queries <- if (pk_v2_secim) NULL else {
    find_multiple_queries_with_ai(
      user_prompt, query_library, session, max_queries = deep_query_ceiling
    )
  }

  if (is.null(selected_queries) || length(selected_queries) == 0) {
    cat("[DEEP_ANALYSIS] Tekil secime dusuluyor.\n")
    single <- select_smart_query(
      user_prompt, query_library, chat_history,
      session = session, stop_check = stop_check
    )

    # v2 acikca "bilmiyorum" dediyse Derin Dusunme de calistirmaz.
    if (is.list(single) && is.null(single$id) && !is.null(single$refusal_message)) {
      pk_observe_deep(list(
        query_name = "Derin analiz", filter_status = "not_reached",
        filters = list(), outcome = "Reddedildi"
      ))
      return(as.character(single$refusal_message)[1])
    }

    if (!is.null(single) && !is.null(single$id)) {
      selected_queries <- list(single)
    } else {
      pk_observe_deep(list(
        query_name = "Derin analiz",
        filter_status = "not_reached",
        filters = list(),
        outcome = "EslesmeYok"
      ))
      return("\U0001F914 Aradığınız bilgi mevcut analiz kütüphanesinde bulunamadı. Lütfen sorunuzu farklı kelimelerle deneyin.")
    }
  }

  cat(sprintf("[DEEP_ANALYSIS] %d sorgu işlenecek.\n", length(selected_queries)))

  if (is.function(stop_check) && isTRUE(stop_check())) {
    pk_observe_deep(list(
      query_name = "Derin analiz",
      filter_status = "stopped",
      filters = list(),
      outcome = "Durduruldu"
    ))
    return("\U000026A0\U0000FE0F **İşlem Durduruldu:** Analiz iptal edildi.")
  }

  query_results <- list()
  for (i in seq_along(selected_queries)) {
    if (is.function(stop_check) && isTRUE(stop_check())) {
      cat(sprintf("[DEEP_ANALYSIS] Sorgu %d/%d - Durdurma talebi.\n", i, length(selected_queries)))
      break
    }

    # Faz 6: SORGULAR ARASINDA son tarih/iptal kapısı. Aksi hâlde bütçe dolmuş
    # olsa bile kalan sorgular sırayla çalışıp bağlantıyı tutmaya devam ederdi.
    deep_gate <- pk_async_stage_gate(
      detail_config$pk_cancel_token, detail_config$pk_deadline_at
    )
    if (isTRUE(deep_gate$halt)) {
      cat(sprintf(
        "[DEEP_ANALYSIS] Sorgu %d/%d - durum=%s; kalan sorgular calistirilmadi.\n",
        i, length(selected_queries), deep_gate$status
      ))
      break
    }

    selected_query <- selected_queries[[i]]
    cat(sprintf("[DEEP_ANALYSIS] Sorgu %d/%d işleniyor: '%s'\n",
                i, length(selected_queries), selected_query$name))

    result <- tryCatch(
      execute_single_deep_query(
        query = selected_query,
        user_prompt = user_prompt,
        session = session,
        rls_info = rls_info,
        detail_config = detail_config,
        stop_check = stop_check
      ),
      error = function(e) {
        cat(sprintf("[DEEP_ANALYSIS] Sorgu hatası: %s\n", e$message))
        list(
          query_name = selected_query$name %||% "?",
          success = FALSE,
          error_msg = e$message,
          pk_observation = list(
            query_id = selected_query$id,
            query_name = selected_query$name %||% "?",
            filter_status = "not_reached",
            filters = list(),
            outcome = "Hata"
          )
        )
      }
    )

    if (!is.null(result)) {
      if (is.null(result$pk_observation)) {
        result$pk_observation <- list(
          query_id = selected_query$id,
          query_name = result$query_name %||% selected_query$name,
          filter_status = "not_reached",
          filters = list(),
          outcome = if (isTRUE(result$success)) "Basarili" else "Hata"
        )
      }
      query_results <- append(query_results, list(result))
    }
  }

  if (length(query_results) == 0) {
    pk_observe_deep(list(
      query_name = "Derin analiz",
      filter_status = if (is.function(stop_check) && isTRUE(stop_check())) "stopped" else "not_reached",
      filters = list(),
      outcome = if (is.function(stop_check) && isTRUE(stop_check())) "Durduruldu" else "Hata"
    ))
    return("\U000026A0\U0000FE0F **Derin Analiz:** Hiçbir sorgu çalıştırılamadı. Lütfen tekrar deneyin.")
  }

  deep_footers <- vapply(query_results, function(result) {
    pk_observe_deep(result$pk_observation)
  }, character(1))
  stash_deep_footer(deep_footers)

  # Faz 6 (D16, §10): PAKET seviyesinde uzlaştırma. Her paket kendi kökenini
  # taşır; çapraz sorgu aritmetiği YASAKTIR ve kısıt istem bağlamına yazılır.
  reconciliation <- pk_deep_reconcile_packets(query_results)
  detail_config$pk_cross_query_instruction <- reconciliation$instruction

  successful_count <- reconciliation$successful
  failed_count <- reconciliation$failed
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

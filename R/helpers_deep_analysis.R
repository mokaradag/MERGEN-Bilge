# ==============================================================================
# R/helpers_deep_analysis.R
# Derin Düşünme modu için tekil sorgu çalıştırma ve orkestrasyon.
# Detay ve bağlam yardımcıları manifestte bu dosyadan önce yüklenir.
# ==============================================================================

#' Tek bir sorguyu çalıştır ve istatistiksel özet oluştur
#' @param query Sorgu tanımı (library öğesi)
#' @param user_prompt Kullanıcı sorusu
#' @param session Shiny oturumu
#' @param rls_info Kullanıcının yetki bilgisi
#' @param detail_config Detay seviyesi yapılandırması
#' @param stop_check Durdurma kontrol fonksiyonu
#' @return İşlenmiş sorgu sonucu listesi veya NULL (hata durumunda)
execute_single_deep_query <- function(query, user_prompt, session, rls_info,
                                      detail_config, stop_check = NULL,
                                      chat_history = NULL) {
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
    return(pk_deep_halt_result("cancelled"))
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

  sql_gate <- pk_sql_readonly_guard(sql_query_text, context_label = "DEEP_QUERY")
  if (!isTRUE(sql_gate$allowed)) {
    return(finish_result(list(
      query_name = query_name,
      success = FALSE,
      error_msg = "Güvenlik ihlali: sorgu salt-okunur olarak doğrulanamadı."
    )))
  }

  sql_exec <- pk_deep_execute_sql(
    conn = conn, sql_text = sql_query_text,
    deadline_at = detail_config$pk_deadline_at,
    cancel_token = detail_config$pk_cancel_token,
    query_meta = query$meta,
    cache_key = pk_query_result_cache_key(query, rls_info, sql_query_text, engine = "deep")
  )

  if (identical(sql_exec$status, "cancelled")) return(pk_deep_halt_result("cancelled"))
  if (identical(sql_exec$status, "deadline")) return(pk_deep_halt_result("deadline"))

  if (!identical(sql_exec$status, "ok")) {
    cat(sprintf("[DEEP_QUERY] '%s' - SQL durumu: %s\n", query_name, sql_exec$status))
    return(finish_result(list(
      query_name = query_name,
      success = FALSE,
      error_msg = switch(
        sql_exec$status,
        deadline = "Analiz zaman aşımına uğradı; sorgu çalıştırılamadı.",
        timeout = "Sorgu ayrılan sürede tamamlanamadı (SQL zaman aşımı).",
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

  if (is.function(stop_check) && isTRUE(stop_check())) return(pk_deep_halt_result("cancelled"))

  if (!is.null(query$date_columns)) {
    raw_data <- convert_date_columns(raw_data, query$date_columns)
  }

  # v2 METADATA KAPISI DERİN ANALİZDE DE UYGULANIR.
  #
  # Derin v2 seçim köprüsü çekirdek seçim davranışını v1 uyumlu tutmak için
  # çağrı ortamındaki `pk_engine_is_v2()` değerini bilinçli olarak FALSE yapar;
  # seçilen sorgular ise `pk_engine_v2=TRUE` işaretini taşır. Yürütücü bu
  # istek-yerel işareti motorun kanonik kaynağı olarak kabul etmezse v2 seçilen
  # sorgu tekrar legacy özet yoluna düşer. Standart `pk_engine_mode` işareti ve
  # normal yapılandırma çözümü de geriye dönük uyumluluk için desteklenir.
  deep_engine_v2 <- isTRUE(query$pk_engine_v2) ||
    identical(as.character(query$pk_engine_mode %||% "")[1], "v2") ||
    (exists("pk_engine_is_v2", mode = "function", inherits = TRUE) &&
       isTRUE(tryCatch(pk_engine_is_v2(query$meta), error = function(e) FALSE)))

  meta_gate <- pk_meta_actual_column_gate(query, names(raw_data), deep_engine_v2)
  if (length(meta_gate$warn) > 0) {
    cat(sprintf("[DEEP_ANALYSIS] METADATA SUTUN UYUSMAZLIGI | sorgu=%s | %s\n",
                query$id %||% "?", paste(meta_gate$warn, collapse = " ; ")))
  }
  if (isTRUE(meta_gate$abort)) {
    return(finish_result(list(
      query_name = query_name,
      success = FALSE,
      error_msg = "Yetki sütunu doğrulanamadı; sorgu güvenli biçimde çalıştırılamadı."
    )))
  }
  if (isTRUE(meta_gate$engine_abort)) {
    return(finish_result(list(
      query_name = query_name,
      success = FALSE,
      error_msg = paste0(
        "Sorgu sonucu, tanımlı sorgu metadatası ile uyuşmuyor; analiz güvenli ",
        "biçimde sürdürülemedi."
      )
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

  v2_karar <- NULL
  if (isTRUE(query$disable_ai_filters)) {
    filtered_data <- secure_data
    filter_criteria <- list(filters = list(), aggregation = NULL, status = "disabled")
  } else {
    available_columns <- names(secure_data)
    filter_criteria <- extract_filter_criteria_from_prompt(
      user_prompt, secure_data, available_columns, conn, session, stop_check = stop_check
    )

    bozuk_kapi <- pk_deep_filter_degraded_decision(filter_criteria$status)
    if (isTRUE(bozuk_kapi$refuse)) {
      return(finish_result(
        list(query_name = query_name, success = FALSE, error_msg = bozuk_kapi$message),
        filter_status = filter_criteria$status %||% "degraded", filters = list(),
        pre_rls_rows = nrow(raw_data), authorized_rows = nrow(secure_data),
        filtered_rows = 0L, outcome = "Hata"
      ))
    }

    # Derin analiz de AYNI baglami gorur (bkz. module_proje_kaynak_analizi.R).
    if (exists("pk_filter_instructions_with_context", mode = "function", inherits = TRUE)) {
      filter_criteria <- pk_filter_instructions_with_context(
        filter_criteria, chat_history = chat_history, session = session
      )
    }

    filtered_data <- apply_smart_filters(secure_data, filter_criteria, user_prompt)

    v2_karar <- .pk_deep_filter_v2_decision(filtered_data)
    if (identical(as.character(v2_karar$action %||% "")[1], "refuse")) {
      return(finish_result(
        list(query_name = query_name, success = FALSE,
             error_msg = as.character(v2_karar$refusal_message %||%
               "Filtre politikasi bu sorgu icin sonucu reddetti.")[1]),
        filter_status = filter_criteria$status %||% "refused", filters = list(),
        pre_rls_rows = nrow(raw_data), authorized_rows = nrow(secure_data),
        filtered_rows = 0L, outcome = "Reddedildi"
      ))
    }
  }

  deep_cap <- pk_row_cap_stage(filtered_data, query_meta = query$meta)
  if (identical(deep_cap$status, "too_large")) {
    return(finish_result(
      list(query_name = query_name, success = FALSE,
           error_msg = "Sonuç kümesi satır tavanını aşıyor; sorgu atlandı."),
      filter_status = filter_criteria$status %||% "ok",
      filters = filter_criteria$filters %||% list(),
      pre_rls_rows = nrow(raw_data),
      authorized_rows = nrow(secure_data),
      filtered_rows = nrow(filtered_data),
      outcome = "SonucCokBuyuk"
    ))
  }

  filter_status <- filter_criteria$status %||% if (length(filter_criteria$filters %||% list()) > 0L) {
    "ok_filtered"
  } else {
    "ok_no_filter"
  }
  applied_filters <- if (isTRUE(deep_engine_v2) &&
                         exists(".pk_result_effective_filters", mode = "function", inherits = TRUE)) {
    tryCatch(.pk_result_effective_filters(v2_karar, filter_criteria),
             error = function(e) filter_criteria$filters %||% list())
  } else {
    filter_criteria$filters %||% list()
  }

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

  if (is.function(stop_check) && isTRUE(stop_check())) return(pk_deep_halt_result("cancelled"))

  post_sql_gate <- pk_async_stage_gate(
    detail_config$pk_cancel_token, detail_config$pk_deadline_at
  )
  if (isTRUE(post_sql_gate$halt)) return(pk_deep_halt_result(post_sql_gate$status))

  # v2 DEEP THINKING: legacy istatistiksel özet oluşturulmadan ÖNCE aynı
  # kanonik analiz-paketi/olgu hattına girilir. `pk_packet_build()` grain,
  # additive/non-additive, weighted_mean, latest, unit/percent-scale ve kapsam
  # semantiğinin tek sahibidir; burada bunların ikinci bir uygulaması YOKTUR.
  if (isTRUE(deep_engine_v2)) {
    gerekli <- c("pk_packet_build", "pk_packet_render", "pk_packet_all_facts",
                 "pk_compose_facts_summary")
    eksik <- gerekli[!vapply(gerekli, exists, logical(1), mode = "function", inherits = TRUE)]
    if (length(eksik)) {
      return(finish_result(
        list(
          query_name = query_name,
          success = FALSE,
          error_msg = paste0(
            "Kanonik v2 analiz paketi bileşenleri yüklenmedi; legacy özete ",
            "güvenlik gereği geri düşülmedi."
          )
        ),
        filter_status = filter_status,
        filters = applied_filters,
        pre_rls_rows = nrow(raw_data),
        authorized_rows = nrow(secure_data),
        filtered_rows = nrow(filtered_data),
        outcome = "Hata"
      ))
    }

    sinirli_paket <- if (exists("pk_async_bounded_fs", mode = "function", inherits = TRUE)) {
      pk_async_bounded_fs
    } else {
      function(fn, deadline_at = NULL) list(ok = TRUE, value = fn())
    }

    paket_sonucu <- sinirli_paket(function() {
      pk_packet_build(filtered_data, query, list(
        authorized_rows = nrow(secure_data),
        filtered_rows = nrow(filtered_data),
        filters = applied_filters,
        filter_status = filter_status,
        degradations = if (exists("pk_degradations_from_filter_status", mode = "function",
                                  inherits = TRUE)) {
          pk_degradations_from_filter_status(filter_status)
        } else {
          list()
        },
        pre_aggregated_columns = query$pre_aggregated_columns
      ))
    }, detail_config$pk_deadline_at)

    if (!isTRUE(paket_sonucu$ok)) return(pk_deep_halt_result("deadline"))
    paket <- paket_sonucu$value

    post_packet_gate <- pk_async_stage_gate(
      detail_config$pk_cancel_token, detail_config$pk_deadline_at
    )
    if (isTRUE(post_packet_gate$halt)) return(pk_deep_halt_result(post_packet_gate$status))

    paket_yazi <- pk_packet_render(paket, query_meta = query$meta)
    if (isTRUE(paket_yazi$over_budget)) {
      return(finish_result(
        list(
          query_name = query_name,
          success = FALSE,
          error_msg = paste0(
            "Kanonik v2 analiz paketi güvenli istem bütçesine sığmadı; ",
            "legacy özete geri düşülmeden sorgu atlandı."
          )
        ),
        filter_status = filter_status,
        filters = applied_filters,
        pre_rls_rows = nrow(raw_data),
        authorized_rows = nrow(secure_data),
        filtered_rows = nrow(filtered_data),
        outcome = "Reddedildi"
      ))
    }

    post_render_gate <- pk_async_stage_gate(
      detail_config$pk_cancel_token, detail_config$pk_deadline_at
    )
    if (isTRUE(post_render_gate$halt)) return(pk_deep_halt_result(post_render_gate$status))

    tum_olgular <- pk_packet_all_facts(paket)
    yedek_metin <- pk_compose_facts_summary(paket$facts)

    cat(sprintf("[DEEP_QUERY] '%s' - Başarılı: %d satır, kanonik v2 paket oluşturuldu.\n",
                query_name, nrow(filtered_data)))

    return(finish_result(
      list(
        query_name = query_name,
        query_desc = query$description %||% "",
        query_id = query$id,
        query_meta = query$meta,
        success = TRUE,
        row_count = nrow(filtered_data),
        relevance = query$relevance_score %||% 0,
        pk_engine_mode = "v2",
        pk_packet = paket,
        pk_packet_text = paket_yazi$text,
        pk_packet_chars = paket_yazi$chars,
        pk_facts = tum_olgular,
        pk_fallback_text = yedek_metin,
        # D21 ile aynı sözleşme: modele sunulan veri RLS + kullanıcı filtresi
        # uygulanmış GERÇEK çerçevedir; secure_data/raw_data geri taşınmaz.
        data = filtered_data
      ),
      filter_status = filter_status,
      filters = applied_filters,
      pre_rls_rows = nrow(raw_data),
      authorized_rows = nrow(secure_data),
      filtered_rows = nrow(filtered_data),
      outcome = "Basarili"
    ))
  }

  # v1: legacy istatistiksel özet davranışı BİREBİR korunur.
  preview_rows <- detail_config$preview_rows %||% 20
  sinirli_ozet <- if (exists("pk_async_bounded_fs", mode = "function", inherits = TRUE)) {
    pk_async_bounded_fs
  } else {
    function(fn, deadline_at = NULL) list(ok = TRUE, value = fn())
  }
  ozet_sonucu <- sinirli_ozet(function() {
    generate_statistical_summary(
      filtered_data,
      max_preview_rows = min(preview_rows, nrow(filtered_data)),
      mode = "summary",
      rls_total_rows = nrow(secure_data),
      user_filter_applied = (nrow(filtered_data) < nrow(secure_data)),
      pre_aggregated_columns = query$pre_aggregated_columns
    )
  }, detail_config$pk_deadline_at)

  if (!isTRUE(ozet_sonucu$ok)) {
    return(pk_deep_halt_result("deadline"))
  }
  stat_summary <- ozet_sonucu$value

  post_stat_gate <- pk_async_stage_gate(
    detail_config$pk_cancel_token, detail_config$pk_deadline_at
  )
  if (isTRUE(post_stat_gate$halt)) return(pk_deep_halt_result(post_stat_gate$status))

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
  faz6 <- pk_deep_phase6_setup(detail_config, session, pk_request_id, pk_started_at)
  detail_config <- faz6$detail_config
  if (is.function(faz6$restore)) on.exit(faz6$restore(), add = TRUE)

  identity_state <- pk_deep_resolve_username(session)
  if (!isTRUE(identity_state$ready)) {
    cat(sprintf("[DEEP_ANALYSIS] Kimlik hazir degil. Sebep: %s\n", identity_state$reason))
    return(identity_state$message)
  }
  username <- identity_state$username

  conn_list <- get_connection()
  conn <- conn_list$conn
  on.exit(release_connection(conn_list), add = TRUE)

  deep_observers <- pk_deep_observation_helpers(
    session = session, conn = conn, username = username,
    user_prompt = user_prompt, request_id = pk_request_id,
    started_at = pk_started_at
  )
  pk_observe_deep <- deep_observers$observe
  stash_deep_footer <- deep_observers$stash

  rls_info <- get_user_rls_info(username, conn)

  if (isTRUE(rls_info$halted)) {
    pk_observe_deep(list(
      query_name = "Derin analiz",
      filter_status = "stopped",
      filters = list(),
      outcome = "Durduruldu"
    ))
    return(pk_rls_halt_message(rls_info))
  }

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

  pk_v2_secim <- exists("pk_engine_is_v2", mode = "function", inherits = TRUE) &&
    isTRUE(pk_engine_is_v2()) &&
    exists("pk_select_query_v2", mode = "function", inherits = TRUE)

  selected_queries <- if (pk_v2_secim) NULL else {
    pk_deep_select_multi_queries(user_prompt, query_library, session,
                                 detail_config, stop_check)
  }

  if (is.null(selected_queries) || length(selected_queries) == 0) {
    cat("[DEEP_ANALYSIS] Tekil secime dusuluyor.\n")
    single <- select_smart_query(
      user_prompt, query_library, chat_history,
      session = session, stop_check = stop_check
    )

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

  birincil_meta <- tryCatch(selected_queries[[1]]$meta, error = function(e) NULL)
  deep_query_ceiling <- pk_deep_max_queries(birincil_meta)
  if (length(selected_queries) > deep_query_ceiling) {
    cat(sprintf("[DEEP_ANALYSIS] Sorgu tavani (%d) uygulandi: %d -> %d.\n",
                deep_query_ceiling, length(selected_queries), deep_query_ceiling))
    selected_queries <- selected_queries[seq_len(deep_query_ceiling)]
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
  deep_halt_status <- NA_character_
  for (i in seq_along(selected_queries)) {
    if (is.function(stop_check) && isTRUE(stop_check())) {
      cat(sprintf("[DEEP_ANALYSIS] Sorgu %d/%d - Durdurma talebi.\n", i, length(selected_queries)))
      deep_halt_status <- "cancelled"
      break
    }

    deep_gate <- pk_async_stage_gate(
      detail_config$pk_cancel_token, detail_config$pk_deadline_at
    )
    if (isTRUE(deep_gate$halt)) {
      cat(sprintf(
        "[DEEP_ANALYSIS] Sorgu %d/%d - durum=%s; kalan sorgular calistirilmadi.\n",
        i, length(selected_queries), deep_gate$status
      ))
      deep_halt_status <- as.character(deep_gate$status)[1]
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
        stop_check = stop_check,
        chat_history = chat_history
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

    if (pk_deep_is_halt_result(result)) {
      deep_halt_status <- as.character(result$pk_halt_status)[1]
      cat(sprintf("[DEEP_ANALYSIS] Sorgu %d/%d - durum=%s (sorgu ici).\n",
                  i, length(selected_queries), deep_halt_status))
      break
    }

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
    if (!is.na(deep_halt_status)) return(pk_async_halt_message(deep_halt_status))
    return("\U000026A0\U0000FE0F **Derin Analiz:** Hiçbir sorgu çalıştırılamadı. Lütfen tekrar deneyin.")
  }

  detail_config <- pk_deep_apply_partial_halt(detail_config, deep_halt_status,
                                              length(query_results))

  deep_footers <- vapply(query_results, function(result) {
    pk_observe_deep(result$pk_observation)
  }, character(1))

  reconciliation <- pk_deep_reconcile_packets(query_results)
  detail_config$pk_cross_query_instruction <- reconciliation$instruction

  if (is.list(reconciliation$packets) && length(reconciliation$packets) > 0L) {
    query_results <- reconciliation$packets
  }

  # Numeric provenance kaydı UZLAŞTIRMA SONRASINDA oluşturulur. Böylece filtre
  # bozulması nedeniyle kanıt olmaktan çıkarılan bir v2 paketinin olguları
  # nihai yanıt için yetkili registry'ye girmez. v1'de `v2_results` boştur ve
  # stash eski footer-only davranışını aynen sürdürür.
  v2_results <- Filter(function(r) {
    isTRUE(r$success) && identical(as.character(r$pk_engine_mode %||% "")[1], "v2")
  }, query_results)

  deep_facts <- if (length(v2_results)) {
    unlist(lapply(v2_results, function(r) r$pk_facts %||% list()), recursive = FALSE)
  } else {
    NULL
  }

  fallback_parts <- if (length(v2_results)) {
    vapply(v2_results, function(r) {
      txt <- as.character(r$pk_fallback_text %||% "")[1]
      if (is.na(txt) || !nzchar(txt)) return("")
      paste0("### ", r$query_name %||% "Sorgu", "\n", txt)
    }, character(1))
  } else {
    character(0)
  }
  fallback_parts <- fallback_parts[nzchar(fallback_parts)]
  deep_fallback <- if (length(fallback_parts)) paste(fallback_parts, collapse = "\n\n") else NULL

  deep_query_ids <- if (length(v2_results)) {
    ids <- vapply(v2_results, function(r) {
      as.character(r$query_id %||% r$pk_observation$query_id %||% "")[1]
    }, character(1))
    ids <- ids[nzchar(ids)]
    if (length(ids)) paste(ids, collapse = ",") else NULL
  } else {
    NULL
  }

  deep_provenance_mode <- if (length(v2_results) &&
                              exists("pk_numeric_provenance_mode", mode = "function", inherits = TRUE)) {
    tryCatch(pk_numeric_provenance_mode(birincil_meta), error = function(e) NULL)
  } else {
    NULL
  }

  stash_deep_footer(
    deep_footers,
    facts = if (length(deep_facts %||% list())) deep_facts else NULL,
    fallback_text = deep_fallback,
    query_id = deep_query_ids,
    mode = deep_provenance_mode
  )

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

  if (is.list(context) && nzchar(as.character(detail_config$pk_partial_halt_status %||% "")[1])) {
    context$pk_partial_halt_status <- as.character(detail_config$pk_partial_halt_status)[1]
  }

  cat("[DEEP_ANALYSIS] >>> DERİN ANALİZ BAĞLAMI HAZIR <<<\n")
  return(context)
}

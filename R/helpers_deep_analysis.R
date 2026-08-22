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

  # DERİN YOL DA NORMAL YOLLA AYNI KANONİK ÇERÇEVEYİ GÖRMELİDİR.
  #
  # `pk_analiz_process_request()` SQL getiriminden hemen sonra
  # `normalize_pk_dataframe_utf8()` çağırır; derin yol ise doğrudan tarih
  # dönüşümüne ve metadata/RLS sütun kapısına giriyordu. Windows/ODBC kodlama
  # durumlarında AYNI sorgu normal analizde çalışıp derin analizde sütun
  # eşleşmesinden düşebiliyor (ya da farklı kodlanmış Türkçe değerleri
  # filtrelemeye taşıyabiliyor) idi.
  if (exists("normalize_pk_dataframe_utf8", mode = "function", inherits = TRUE)) {
    raw_data <- tryCatch(normalize_pk_dataframe_utf8(raw_data), error = function(e) raw_data)
  }

  if (!is.null(query$date_columns)) {
    raw_data <- convert_date_columns(raw_data, query$date_columns)
  }

  # v2 seçim köprüsünün per-query motor işareti de onurlandırılır.
  deep_engine_v2 <- pk_deep_query_is_v2(query)

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
  applied_filters <- pk_deep_effective_filters(v2_karar, filter_criteria, deep_engine_v2)

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

  if (deep_engine_v2) return(pk_deep_build_v2_packet_result(
    filtered_data, secure_data, query, filter_status, applied_filters,
    detail_config, finish_result, nrow(raw_data), stop_check
  ))

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
      pre_aggregated_columns = query$pre_aggregated_columns,
      # U45: ayni OLCU sozlesmesi derin yolda da gecerlidir.
      column_meta = if (is.list(query$meta)) query$meta$column_meta else NULL
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
  # BAĞLANTI RLS OKUMASINDAN HEMEN SONRA BIRAKILIR.
  #
  # Bu birincil bağlantı yalnızca yetki okuması için gerekir; eskiden TÜM derin
  # analiz boyunca (5 sorgu + LLM) açık kalıyordu ve her sorgu AYRICA kendi
  # hedef bağlantısını açıyordu. Ana süreçteki erken-bırakma sarmalayıcısı
  # (`server_chat_engine_dependencies.R`) worker bootstrap'ına DÂHİL DEĞİLDİR,
  # bu yüzden eşzamanlı asenkron derin işçiler kullanılmayan birincil
  # bağlantıları tutup SQL Server oturumlarını tüketebiliyordu. Bırakma
  # `conn_serbest` ile İDEMPOTENTTİR; hata yolları için `on.exit` korunur.
  birakici <- pk_deep_primary_connection_release(conn_list)
  birak_conn <- birakici$release
  on.exit(birak_conn(), add = TRUE)

  deep_observers <- pk_deep_observation_helpers(
    # `conn` BİLİNÇLİ OLARAK VERİLMEZ: birincil bağlantı aşağıda RLS
    # okumasından hemen sonra `birak_conn()` ile bırakılır. Gözlem katmanı
    # kendi kısa ömürlü bağlantısını `conn_provider` ile açar.
    session = session, conn = NULL, username = username,
    user_prompt = user_prompt, request_id = pk_request_id,
    started_at = pk_started_at,
    # Telemetri KENDİ kısa ömürlü bağlantısını açar; böylece birincil bağlantı
    # RLS okumasından sonra tutulmak zorunda kalmaz.
    conn_provider = pk_deep_short_lived_conn_provider()
  )
  pk_observe_deep <- deep_observers$observe
  stash_deep_footer <- deep_observers$stash

  rls_info <- get_user_rls_info(username, conn)
  # BİRİNCİL BAĞLANTI BURADA BIRAKILIR (bkz. `birak_conn` açıklaması).
  birak_conn()

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
    # PR #705: TİPLİ yetki reddi. Altyapı arızası ve mükerrer yetki kaydı,
    # "kullanıcı kaydınız bulunamadı" diye raporlanmaz.
    return(pk_rls_denied_message(rls_info))
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
        # HAM İSTİSNA METNİ KULLANICIYA/MODELE GİTMEZ.
        #
        # `build_deep_analysis_context()` bu metni ya tüm-sorgular-başarısız
        # yanıtında DOĞRUDAN gösterir ya da "başarısızlık nedenini bildir"
        # talimatıyla modele verir. Beklenmeyen bir istisna sürücü, DSN, dosya
        # yolu, SQL ya da iç uygulama ayrıntısı taşıyabilir; normal SQL hata
        # yolları bilerek genel metin döndürürken bu dal onları ATLIYORDU.
        # Ham metin SUNUCU LOG'una (redakte edilerek) yazılır.
        # MESAJ SABİTTİR; `pk_safe_error_message()` burada UYGUN DEĞİLDİR: onun
        # sözleşmesi "altyapı görünümlü metni genelleştir, aksi hâlde OLDUĞU
        # GİBİ geçir"dir. Buradaki girdi ise KEYFİ bir istisnadır; ODBC'ye
        # benzemeyen ama dosya yolu/iç ayrıntı taşıyan metin o süzgeçten
        # DEĞİŞMEDEN geçerdi. Ayrıca `exists()` kapısı kararı ÇALIŞMA BAĞLAMINA
        # bağlı kılıyordu (izole vs tam paket). Karar artık DETERMİNİSTİKtir.
        ham <- tryCatch(conditionMessage(e), error = function(x) "")
        guvenli <- paste0(
          "Bu analiz beklenmeyen bir hata nedeniyle tamamlanamadı; ",
          "ayrıntı sunucu günlüğüne yazıldı."
        )
        # KALICI sunucu log'u: baglanti TANIMLAYICILARI (DSN/UID/Server) da
        # maskelenir. Genel redaktor bunlari BILEREK korur, bu yuzden ona GERI
        # DUSULMEZ; baglantiya ozgu redaktor yoksa tani metni YAZILMAZ.
        kayit <- if (exists("redact_connection_identifiers", mode = "function", inherits = TRUE)) {
          tryCatch(redact_connection_identifiers(ham), error = function(x) "(redaksiyon uygulanamadi)")
        } else {
          "(redaktor yuklenmedi)"
        }
        cat(sprintf("[DEEP_ANALYSIS] Sorgu hatası: %s\n", kayit))
        list(
          query_name = selected_query$name %||% "?",
          success = FALSE,
          error_msg = guvenli,
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
    # `stop_check()` SAF DEĞİLDİR: işçide iptal jetonu dosyasını okur ve iki
    # çağrı arasında dönebilir. Tek kez okunur, aksi halde bildirilen
    # `filter_status` ile `outcome` çelişir ("stopped" + "Hata" gibi).
    durduruldu <- is.function(stop_check) && isTRUE(stop_check())
    pk_observe_deep(list(
      query_name = "Derin analiz",
      filter_status = if (durduruldu) "stopped" else "not_reached",
      filters = list(),
      outcome = if (durduruldu) "Durduruldu" else "Hata"
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

  do.call(stash_deep_footer, c(list(footers = deep_footers),
                               pk_deep_collect_v2_provenance(query_results, birincil_meta)))

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

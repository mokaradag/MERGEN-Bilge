# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_selection_deep.R
# Açıklama: Faz 5 (§5.2) — Derin Düşünme için güvenli çoklu v2 seçimi ve
#           derin-analiz çalışma zamanı köprüsü.
# ==============================================================================

.pk_select_deep_required_confidence <- function(min_confidence, disagree_penalty) {
  esik <- suppressWarnings(as.numeric(min_confidence)[1])
  ceza <- suppressWarnings(as.numeric(disagree_penalty)[1])
  if (!length(esik) || !length(ceza) || !is.finite(esik) || !is.finite(ceza)) {
    return(NA_real_)
  }

  gerekli <- esik + max(0, ceza)
  if (!is.finite(gerekli) || gerekli > 100) return(NA_real_)
  gerekli
}

# Tekil derin yürütücü v1 uyumluluğu için gerçek-sütun kapısına FALSE geçirir.
# v2 Derin Düşünme seçimi bu dosyada sorguya açık bir motor işareti taşır; kapı
# bu işareti v2 modu gibi değerlendirir. Böylece birincil ve alternatif sorgular
# beyan edilmiş non-RLS metadata sütunları SQL sonucunda yoksa fail-closed olur,
# v1 sorgularıysa eski davranışını korur.
if (!exists(".pk_select_actual_column_gate_base", inherits = FALSE) &&
    exists("pk_meta_actual_column_gate", mode = "function", inherits = TRUE)) {
  .pk_select_actual_column_gate_base <- get(
    "pk_meta_actual_column_gate", mode = "function", inherits = TRUE
  )
}
if (exists(".pk_select_actual_column_gate_base", inherits = FALSE)) {
  pk_meta_actual_column_gate <- function(query, actual_columns, engine_v2 = FALSE) {
    v2_derin <- is.list(query) && isTRUE(query$pk_engine_v2)
    .pk_select_actual_column_gate_base(
      query, actual_columns, isTRUE(engine_v2) || v2_derin
    )
  }
}

#' Derin Düşünme için v2'nin aynı iki geçişli kararından güvenli çoklu küme üret
pk_select_queries_v2 <- function(prompt, library, chat_history = NULL,
                                 session = NULL, llm_fn = NULL, cfg = NULL,
                                 stop_check = NULL,
                                 max_queries = pk_deep_max_queries()) {
  birincil <- pk_select_query_v2(
    prompt, library, chat_history,
    session = session, llm_fn = llm_fn, cfg = cfg, stop_check = stop_check
  )

  if (!is.list(birincil) || is.null(birincil$id)) {
    return(list(primary = birincil, queries = list()))
  }

  birincil$pk_engine_v2 <- TRUE
  sinir <- suppressWarnings(as.integer(max_queries)[1])
  if (!length(sinir) || is.na(sinir) || sinir < 1L) sinir <- 1L
  sinir <- min(sinir, 20L)
  sonuc <- list(birincil)
  if (sinir <= 1L) return(list(primary = birincil, queries = sonuc))

  karar <- birincil$pk_selection
  skorlar <- if (is.list(karar)) karar$alternate_scores %||% list() else list()
  if (!length(skorlar)) return(list(primary = birincil, queries = sonuc))

  temel_cfg <- pk_select_revalidate_config(cfg)
  if (!isTRUE(temel_cfg$valid)) return(list(primary = birincil, queries = sonuc))

  indeks <- pk_select_library_index(library)
  yetenekler <- pk_select_capability_ids()
  ids <- names(skorlar)
  puanlar <- vapply(ids, function(k) as.numeric(skorlar[[k]]), numeric(1), USE.NAMES = FALSE)
  sira <- order(-puanlar, ids, method = "radix")

  for (kimlik in ids[sira]) {
    if (length(sonuc) >= sinir) break
    if (identical(kimlik, birincil$id)) next

    sorgu <- indeks[[kimlik]]
    if (!is.list(sorgu)) next

    sorgu_cfg <- pk_select_config_for_query(temel_cfg, sorgu$meta)
    if (!isTRUE(sorgu_cfg$valid)) next

    guven <- suppressWarnings(as.numeric(skorlar[[kimlik]])[1])
    if (!length(guven) || !is.finite(guven)) next

    # Ek adayda sözlüksel sıralama yeniden hesaplanmadığından, aday ancak olası
    # en kötü uyuşmazlık cezasından SONRA da kendi güven eşiğini geçebiliyorsa
    # çalıştırılır. min_confidence + penalty > 100 ise bu kanıt matematiksel
    # olarak imkânsızdır; eşiği 100'e kırpmak güven kapısını zayıflatır.
    gerekli_guven <- .pk_select_deep_required_confidence(
      sorgu_cfg$min_confidence, sorgu_cfg$disagree_penalty
    )
    if (!is.finite(gerekli_guven) || guven < gerekli_guven) next

    yetenek <- pk_select_validate_requirements(
      sorgu, karar$requirements, yetenekler
    )
    if (!(yetenek$status %in% c("ok", "not_asserted"))) next

    sorgu$relevance_score <- guven
    sorgu$selection_method <- "ai_two_pass_deep"
    sorgu$selection_reason <- paste0(
      "Derin analiz ek adayı: Geçiş B güveni ve metadata yetenek kapıları geçti."
    )
    sorgu$pk_selection <- karar
    sorgu$pk_engine_v2 <- TRUE
    sonuc[[length(sonuc) + 1L]] <- sorgu
  }

  list(primary = birincil, queries = sonuc)
}

# Derin analiz çekirdeği bu helper'dan önce yüklenir. Köprü, çekirdeği v2 için
# istek-yerel seçim fonksiyonlarıyla çalıştırır; global fonksiyonları değiştirmez.
#
# ÖNEMLİ: server_chat_engine_dependencies.R daha sonra bu köprünün environment'ını
# kısa ömürlü bağlantı/telemetri override'larını içeren call_env ile değiştirir.
# Burada çekirdek ortamının ebeveyni CURRENT çağrı ortamıdır; böylece o daha
# sonraki resource wrapper'ları hem v1 hem v2 yollarında korunur.
if (!exists(".pk_deep_analysis_process_base", inherits = FALSE) &&
    exists("pk_deep_analysis_process", mode = "function", inherits = TRUE)) {
  .pk_deep_analysis_process_base <- get(
    "pk_deep_analysis_process", mode = "function", inherits = TRUE
  )
}

if (exists(".pk_deep_analysis_process_base", inherits = FALSE)) {
  pk_deep_analysis_process <- function(user_prompt, chat_history, session,
                                       detail_level = "standart",
                                       stop_check = NULL) {
    impl <- .pk_deep_analysis_process_base
    cagri_ortami <- environment()
    v2_aktif <- exists("pk_engine_is_v2", mode = "function", inherits = TRUE) &&
      isTRUE(pk_engine_is_v2()) &&
      exists("pk_select_queries_v2", mode = "function", inherits = TRUE)

    if (!isTRUE(v2_aktif)) {
      environment(impl) <- new.env(parent = cagri_ortami)
      return(impl(
        user_prompt, chat_history, session,
        detail_level = detail_level, stop_check = stop_check
      ))
    }

    yerel <- new.env(parent = cagri_ortami)
    durum <- new.env(parent = emptyenv())
    durum$multi <- NULL
    durum$committed <- FALSE

    # Çekirdeğin seçim uyumluluğu için motor bayrağını v1 göstermemiz gerekiyor,
    # fakat telemetri gerçek isteğin motorunu raporlamalıdır. call_env içindeki
    # güncel gözlem sarmalayıcısını yakalayıp yalnız `engine` alanını v2 olarak
    # düzeltiriz; bağlantı/telemetri kaynak sarmalayıcıları aynen korunur.
    if (exists("pk_analysis_observe", mode = "function", envir = yerel, inherits = TRUE)) {
      temel_observe <- get(
        "pk_analysis_observe", mode = "function", envir = yerel, inherits = TRUE
      )
      yerel$pk_analysis_observe <- local({
        observe_fn <- temel_observe
        function(session, conn, info, ...) {
          if (is.list(info)) info$engine <- "v2"
          observe_fn(session, conn, info, ...)
        }
      })
    }

    yerel$pk_engine_is_v2 <- function() FALSE
    yerel$find_multiple_queries_with_ai <- function(prompt, library, owner_session,
                                                    max_queries = pk_deep_max_queries()) {
      durum$multi <- pk_select_queries_v2(
        prompt, library, chat_history,
        session = owner_session, stop_check = stop_check,
        max_queries = max_queries
      )
      durum$multi$queries %||% list()
    }

    yerel$select_smart_query <- function(prompt, library, history, ...) {
      if (!is.list(durum$multi)) return(NULL)
      durum$multi$primary
    }

    temel_execute <- get(
      "execute_single_deep_query", mode = "function", envir = yerel, inherits = TRUE
    )
    yerel$execute_single_deep_query <- function(query, user_prompt, session, rls_info,
                                                detail_config, stop_check = NULL,
                                                chat_history = NULL) {
      # Tekil yürütücü de girişte aynı kapıyı uygular. Commit bu kapının ÖNÜNE
      # geçmemelidir: kullanıcı durdurduysa seçilmeyen sorgu takip durumuna
      # yazılmamalıdır. Shiny ana olay döngüsünde bu kontrol ile commit arasında
      # yield yoktur, dolayısıyla iptal durumu atomik olarak korunur.
      if (is.function(stop_check) && isTRUE(stop_check())) return(NULL)

      if (!isTRUE(durum$committed) && is.list(durum$multi) &&
          is.list(durum$multi$primary) && !is.null(durum$multi$primary$id)) {
        try(pk_select_commit_selection(durum$multi$primary, session), silent = TRUE)
        durum$committed <- TRUE
      }
      temel_execute(
        query, user_prompt, session, rls_info, detail_config,
        stop_check = stop_check, chat_history = chat_history
      )
    }

    environment(impl) <- yerel
    impl(
      user_prompt, chat_history, session,
      detail_level = detail_level, stop_check = stop_check
    )
  }
}

# ------------------------------------------------------------------------------
# Deep Thinking v2 paket/fact köprüsü
# ------------------------------------------------------------------------------
# Bu yardımcılar seçilmiş v2 sorgusunu standart PK paket/fact çekirdeğine bağlar.
# İstatistik/aggregation semantiği burada yeniden uygulanmaz.

pk_deep_query_is_v2 <- function(query) {
  if (isTRUE(query$pk_engine_v2) ||
      identical(as.character(query$pk_engine_mode %||% "")[1], "v2")) {
    return(TRUE)
  }
  if (!exists("pk_engine_is_v2", mode = "function", inherits = TRUE)) return(FALSE)
  durum <- try(pk_engine_is_v2(query$meta), silent = TRUE)
  !inherits(durum, "try-error") && isTRUE(durum)
}

pk_deep_effective_filters <- function(policy, filter_criteria, engine_v2 = FALSE) {
  if (isTRUE(engine_v2) &&
      exists(".pk_result_effective_filters", mode = "function", inherits = TRUE)) {
    sonuc <- try(.pk_result_effective_filters(policy, filter_criteria), silent = TRUE)
    if (!inherits(sonuc, "try-error")) return(sonuc)
  }
  filter_criteria$filters %||% list()
}

pk_deep_v2_halt_status <- function(detail_config, stop_check = NULL) {
  if (is.function(stop_check)) {
    durdur <- try(stop_check(), silent = TRUE)
    if (!inherits(durdur, "try-error") && isTRUE(durdur)) return("cancelled")
  }
  if (!exists("pk_async_stage_gate", mode = "function", inherits = TRUE)) return(NULL)
  kapi <- try(
    pk_async_stage_gate(detail_config$pk_cancel_token, detail_config$pk_deadline_at),
    silent = TRUE
  )
  if (!inherits(kapi, "try-error") && is.list(kapi) && isTRUE(kapi$halt)) {
    return(as.character(kapi$status)[1])
  }
  NULL
}

pk_deep_build_v2_packet_result <- function(filtered_data, secure_data, query,
                                           filter_status, applied_filters,
                                           detail_config, finish_result,
                                           pre_rls_rows, stop_check = NULL) {
  query_name <- query$name %||% "Bilinmeyen Sorgu"
  gerekli <- c("pk_packet_build", "pk_packet_render", "pk_packet_all_facts",
               "pk_compose_facts_summary")
  # `exists` DOGRUDAN `vapply` FUN'i olarak verilmemelidir: `exists()` icin
  # varsayilan `where = -1` CAGIRAN CERCEVEyi cozer ve `vapply` altinda bu
  # cerceve `namespace:base`e baglidir. Boylece `inherits = TRUE` bu fonksiyonun
  # LEKSIK ortamini ATLAR ve yalnizca arama yolunu/globalenv'i tarar. Uretimde
  # tum yardimcilar globalenv'de oldugu icin sorun gorunmezdi; izole ortamda
  # (test/worker bootstrap) ise TUM yardimcilar "yok" sayilip v2 hatti sessizce
  # devre disi kaliyordu. Anonim sarmalayici leksik kapsami korur.
  eksik_var <- any(!vapply(
    gerekli,
    function(ad) exists(ad, mode = "function", inherits = TRUE),
    logical(1)
  ))
  if (eksik_var) {
    return(finish_result(
      list(query_name = query_name, success = FALSE,
           error_msg = paste0("Kanonik v2 analiz paketi bileşenleri yüklenmedi; ",
                              "legacy özete güvenlik gereği geri düşülmedi.")),
      filter_status = filter_status, filters = applied_filters,
      pre_rls_rows = pre_rls_rows, authorized_rows = nrow(secure_data),
      filtered_rows = nrow(filtered_data), outcome = "Hata"
    ))
  }

  durdurma <- pk_deep_v2_halt_status(detail_config, stop_check)
  if (!is.null(durdurma)) return(pk_deep_halt_result(durdurma))

  packet_context <- list(
    authorized_rows = nrow(secure_data), filtered_rows = nrow(filtered_data),
    filters = applied_filters, filter_status = filter_status,
    degradations = if (exists("pk_degradations_from_filter_status", mode = "function",
                              inherits = TRUE)) {
      pk_degradations_from_filter_status(filter_status)
    } else list(),
    pre_aggregated_columns = query$pre_aggregated_columns
  )
  build_call <- function() pk_packet_build(filtered_data, query, packet_context)
  paket_sonucu <- if (exists("pk_async_bounded_fs", mode = "function", inherits = TRUE)) {
    pk_async_bounded_fs(build_call, detail_config$pk_deadline_at)
  } else {
    list(ok = TRUE, value = build_call())
  }
  if (!isTRUE(paket_sonucu$ok)) {
    durdurma <- pk_deep_v2_halt_status(detail_config, stop_check) %||% "deadline"
    return(pk_deep_halt_result(durdurma))
  }
  paket <- paket_sonucu$value

  durdurma <- pk_deep_v2_halt_status(detail_config, stop_check)
  if (!is.null(durdurma)) return(pk_deep_halt_result(durdurma))

  paket_yazi <- pk_packet_render(paket, query_meta = query$meta)
  if (isTRUE(paket_yazi$over_budget)) {
    return(finish_result(
      list(query_name = query_name, success = FALSE,
           error_msg = paste0("Kanonik v2 analiz paketi güvenli istem bütçesine sığmadı; ",
                              "legacy özete geri düşülmeden sorgu atlandı.")),
      filter_status = filter_status, filters = applied_filters,
      pre_rls_rows = pre_rls_rows, authorized_rows = nrow(secure_data),
      filtered_rows = nrow(filtered_data), outcome = "Reddedildi"
    ))
  }

  durdurma <- pk_deep_v2_halt_status(detail_config, stop_check)
  if (!is.null(durdurma)) return(pk_deep_halt_result(durdurma))

  cat(sprintf("[DEEP_QUERY] '%s' - Başarılı: %d satır, kanonik v2 paket oluşturuldu.\n",
              query_name, nrow(filtered_data)))
  finish_result(
    list(
      query_name = query_name, query_desc = query$description %||% "",
      query_id = query$id, query_meta = query$meta, success = TRUE,
      row_count = nrow(filtered_data), relevance = query$relevance_score %||% 0,
      pk_engine_mode = "v2", pk_packet = paket,
      pk_packet_text = paket_yazi$text, pk_packet_chars = paket_yazi$chars,
      pk_facts = pk_packet_all_facts(paket),
      pk_fallback_text = pk_compose_facts_summary(paket$facts), data = filtered_data
    ),
    filter_status = filter_status, filters = applied_filters,
    pre_rls_rows = pre_rls_rows, authorized_rows = nrow(secure_data),
    filtered_rows = nrow(filtered_data), outcome = "Basarili"
  )
}

# Uzlaştırma SONRASI yalnız başarılı v2 paketleri numeric provenance'a girer.
pk_deep_collect_v2_provenance <- function(query_results, primary_meta = NULL) {
  v2 <- list()
  for (sonuc in (query_results %||% list())) {
    if (is.list(sonuc) && isTRUE(sonuc$success) &&
        identical(as.character(sonuc$pk_engine_mode %||% "")[1], "v2")) {
      v2[[length(v2) + 1L]] <- sonuc
    }
  }
  if (!length(v2)) {
    return(list(facts = NULL, fallback_text = NULL, query_id = NULL, mode = NULL))
  }

  facts <- list()
  fallback <- character(0)
  ids <- character(0)
  for (sonuc in v2) {
    for (fact in (sonuc$pk_facts %||% list())) facts[[length(facts) + 1L]] <- fact
    metin <- as.character(sonuc$pk_fallback_text %||% "")[1]
    if (!is.na(metin) && nzchar(metin)) {
      fallback <- c(fallback, paste0("### ", sonuc$query_name %||% "Sorgu", "\n", metin))
    }
    kimlik <- as.character(sonuc$query_id %||% sonuc$pk_observation$query_id %||% "")[1]
    if (!is.na(kimlik) && nzchar(kimlik)) ids <- c(ids, kimlik)
  }

  mode <- NULL
  if (exists("pk_numeric_provenance_mode", mode = "function", inherits = TRUE)) {
    aday <- try(pk_numeric_provenance_mode(primary_meta), silent = TRUE)
    if (!inherits(aday, "try-error")) mode <- aday
  }

  list(
    facts = if (length(facts)) facts else NULL,
    fallback_text = if (length(fallback)) paste(fallback, collapse = "\n\n") else NULL,
    query_id = if (length(ids)) paste(ids, collapse = ",") else NULL,
    mode = mode
  )
}

# Baseline Deep gözlem fabrikasını değiştirmeden, v2 olgularını aynı birleşik
# footer ile request-scope provenance yuvasına taşıyan dar sarmalayıcı.
if (!exists(".pk_deep_observation_helpers_base", inherits = FALSE) &&
    exists("pk_deep_observation_helpers", mode = "function", inherits = TRUE)) {
  .pk_deep_observation_helpers_base <- get(
    "pk_deep_observation_helpers", mode = "function", inherits = TRUE
  )
}
if (exists(".pk_deep_observation_helpers_base", inherits = FALSE)) {
  pk_deep_observation_helpers <- function(session, conn, username, user_prompt,
                                          request_id, started_at) {
    helpers <- .pk_deep_observation_helpers_base(
      session, conn, username, user_prompt, request_id, started_at
    )
    base_stash <- helpers$stash
    helpers$stash <- function(footers, facts = NULL, fallback_text = NULL,
                              query_id = NULL, mode = NULL) {
      if (is.null(facts) && is.null(fallback_text) && is.null(query_id) && is.null(mode)) {
        return(base_stash(footers))
      }
      if (!exists("pk_provenance_stash", mode = "function", inherits = TRUE)) {
        return(invisible(FALSE))
      }
      footers <- as.character(footers)
      footers <- footers[!is.na(footers) & nzchar(footers)]
      if (!length(footers)) return(invisible(FALSE))

      standard_prefix <- "\n\n---\n**Analiz Kaynağı**\n"
      bodies <- character(length(footers))
      for (i in seq_along(footers)) {
        body <- if (startsWith(footers[i], standard_prefix)) {
          substring(footers[i], nchar(standard_prefix) + 1L)
        } else footers[i]
        bodies[i] <- sub("\n$", "", body)
      }
      combined_footer <- paste0(
        "\n\n---\n**Analiz Kaynağı (Derin Analiz)**\n",
        paste(bodies, collapse = "\n\n"), "\n"
      )
      pk_provenance_stash(
        session, combined_footer, request_id = request_id,
        facts = facts, fallback_text = fallback_text, query_id = query_id, mode = mode
      )
    }
    helpers
  }
}

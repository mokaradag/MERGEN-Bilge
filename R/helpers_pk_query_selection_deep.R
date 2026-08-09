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
                                 stop_check = NULL, max_queries = 5L) {
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

    yerel$pk_engine_is_v2 <- function() FALSE
    yerel$find_multiple_queries_with_ai <- function(prompt, library, owner_session,
                                                    max_queries = 5L) {
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
                                                detail_config, stop_check = NULL) {
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
        stop_check = stop_check
      )
    }

    environment(impl) <- yerel
    impl(
      user_prompt, chat_history, session,
      detail_level = detail_level, stop_check = stop_check
    )
  }
}

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

  # `not_for` OLUMSUZ KANITI EK ADAYLARA DA UYGULANIR.
  #
  # Birincil seçim `pk_retrieval_agreement()` üzerinden geçerken sorgunun kendi
  # `not_for` beyanı açık olumsuz kanıt olarak değerlendirilir. Ek Derin Düşünme
  # adayları bu kapıdan HİÇ geçmiyor, yalnızca güven + yetenek denetleniyordu;
  # "bu soru için DEĞİL" diye küratörlenmiş bir sorgu alternatif skoru yüksek
  # olduğu için çalıştırılıp derin analiz cevabına katılabiliyordu.
  # KAPI HESAPLANAMAZSA KAPALI KALIR.
  #
  # Hata durumunda boş dışlama kümesine düşmek, "bu soru için DEĞİL" diye
  # küratörlenmiş bir sorgunun ek aday olarak ÇALIŞMASINA ve derin analiz
  # cevabına KATILMASINA izin veriyordu. Dışlama hesaplanamıyorsa ek aday
  # eklenmez; birincil seçim kendi kapısından zaten geçmiştir.
  dislanan_ids <- character(0)
  dislama_hatasi <- FALSE
  if (exists("pk_retrieval_excluded_ids", mode = "function", inherits = TRUE)) {
    dislanan_ids <- tryCatch(
      as.character(pk_retrieval_excluded_ids(library, prompt) %||% character(0)),
      error = function(e) {
        cat(sprintf("[DEEP_SELECT] not_for dislama hesaplanamadi: %s\n",
                    conditionMessage(e)))
        dislama_hatasi <<- TRUE
        character(0)
      }
    )
  } else {
    # YARDIMCI YOKSA KAPI DA KAPANIR (hata dalıyla AYNI sonuç).
    #
    # Getirim yardımcısı yüklenmemiş bir işçide/izole test bootstrap'ında
    # `dislanan_ids` boş kalıyor ve aşağıdaki döngü HER ek adayı kabul
    # ediyordu: "bu soru için değil" diye küratörlenmiş bir sorgu güven ve
    # yetenek kapılarından geçip derin analiz cevabına katılabiliyordu.
    cat("[DEEP_SELECT] not_for dislama yardimcisi yok; ek aday EKLENMEZ.\n")
    dislama_hatasi <- TRUE
  }
  if (isTRUE(dislama_hatasi)) return(list(primary = birincil, queries = sonuc))
  ids <- names(skorlar)
  puanlar <- vapply(ids, function(k) as.numeric(skorlar[[k]]), numeric(1), USE.NAMES = FALSE)
  sira <- order(-puanlar, ids, method = "radix")

  for (kimlik in ids[sira]) {
    if (length(sonuc) >= sinir) break
    if (identical(kimlik, birincil$id)) next

    if (kimlik %in% dislanan_ids) next

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

    # DIŞ iptal kapısı, aşağıdaki köprünün KENDİ `stop_check` parametresi
    # tarafından gölgelenmeden önce yakalanır.
    dis_stop_check <- stop_check

    # İMZA ÇAĞIRANIN İMZASIYLA AYNI OLMALIDIR.
    #
    # `pk_deep_select_multi_queries()` seçiciyi `timeout_sec = <kalan bütçe>` ve
    # `stop_check = ...` ile çağırır. Köprü bunları KABUL etmezse çağrı "unused
    # argument" ile düşer; KULLANMAZSA da kalan bütçe sessizce yok sayılırdı.
    yerel$find_multiple_queries_with_ai <- function(prompt, library, owner_session,
                                                    max_queries = pk_deep_max_queries(),
                                                    timeout_sec = NULL,
                                                    stop_check = NULL) {
      kapi <- if (is.function(stop_check)) stop_check else dis_stop_check

      # KALAN BÜTÇE v2 seçicisine de UYGULANIR: yapılandırmanın kendi
      # `timeout_sec` değeri istek bütçesinden BÜYÜK olamaz.
      cfg <- tryCatch(pk_select_config(), error = function(e) NULL)
      if (is.list(cfg) && isTRUE(cfg$valid) && is.numeric(timeout_sec) &&
          length(timeout_sec) == 1L && is.finite(timeout_sec)) {
        cfg$timeout_sec <- max(1L, min(as.numeric(cfg$timeout_sec),
                                       floor(as.numeric(timeout_sec))))
      }

      durum$multi <- pk_select_queries_v2(
        prompt, library, chat_history,
        session = owner_session, stop_check = kapi, cfg = cfg,
        max_queries = max_queries
      )
      durum$multi$queries %||% list()
    }

    # `pk_deep_select_multi_queries()` AYRI bir üst düzey fonksiyondur ve KENDİ
    # sözcüksel ortamı `globalenv()`tir. Gövdesindeki `find_multiple_queries_with_ai`
    # bu yüzden yukarıdaki v2 köprüsünü DEĞİL küresel v1 seçicisini çözüyordu:
    # `durum$multi` hiç dolmuyor, v2 iki geçişli seçimi ve commit davranışı
    # ATLANIYORDU. Fonksiyonun bir KOPYASI `yerel`e bağlanır; bütçe/tavan
    # kararları AYNEN korunur.
    if (exists("pk_deep_select_multi_queries", mode = "function",
               envir = yerel, inherits = TRUE)) {
      coklu_secici <- get("pk_deep_select_multi_queries", mode = "function",
                          envir = yerel, inherits = TRUE)
      environment(coklu_secici) <- yerel
      yerel$pk_deep_select_multi_queries <- coklu_secici
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

# SINIRLI ÇALIŞTIRMA BAŞARISIZLIĞINI SINIFLANDIR (son tarih mi, GERÇEK hata mı?)
#
# `pk_async_bounded_fs()` YALNIZCA bütçe dolduğunda değil, sınırlı fonksiyonun
# içinde oluşan HER hatada `ok = FALSE` döndürür. Her başarısızlığı `deadline`
# saymak iki şeyi bozuyordu: (1) sıradan bir paket kurulum çökmesi kullanıcıya
# "süre doldu" diye raporlanıyor, gerçek kusur gizleniyordu; (2) bu eşleme
# üzerine yazılan testler sınıflandırmayı DEĞİL eşlemeyi doğruluyordu.
#
# `budget_exhausted` sentineli ve GERÇEKTEN dolmuş bir son tarih son tarih
# sayılır; `elapsed time limit` R'ın kendi `setTimeLimit()` kesmesidir ve o da
# bütçe aşımıdır. Bunların dışındaki her şey GERÇEK HATADIR ve `NULL` döner.
pk_deep_bounded_deadline_reason <- function(bounded_result, deadline_at = NULL) {
  if (isTRUE(bounded_result$ok)) return(NULL)

  hata <- tryCatch(as.character(bounded_result$error)[1], error = function(e) NA_character_)
  if (!is.na(hata) && nzchar(hata)) {
    if (identical(hata, "budget_exhausted")) return("deadline")
    # R'ın zaman sınırı kesmesi yerelleştirilebilir; ASCII çapa yeterlidir.
    if (grepl("elapsed time limit", hata, fixed = TRUE)) return("deadline")
    if (grepl("reached elapsed time limit", hata, fixed = TRUE)) return("deadline")
  }

  # Hata alanı YOKSA (enjekte edilmiş sade bir yedek) son tarihin gerçekten
  # dolup dolmadığına bakılır; dolmuşsa son tarihtir.
  if (!is.null(deadline_at) &&
      exists("pk_deadline_expired", mode = "function", inherits = TRUE)) {
    dolmus <- tryCatch(isTRUE(pk_deadline_expired(deadline_at)), error = function(e) FALSE)
    if (isTRUE(dolmus)) return("deadline")
  }

  NULL
}

# SINIRLI İSTATİSTİK ÖZETİ BAŞARISIZLIĞINI TİPLİ SONUCA ÇEVİR (v1 yolu)
#
# Karar `R/helpers_deep_analysis.R` içinde inline duruyordu ve o dosya bakım
# ratchet tavanındadır. Sınıflandırma burada, kararın ikizi olan v2 paket
# kurulum dalıyla AYNI dosyada tutulur: son tarih/iptal halt'i ile GERÇEK bir
# iç hata birbirinden ayrılır.
pk_deep_bounded_summary_failure <- function(bounded, detail_config, finish_result,
                                            query_name, filter_status,
                                            applied_filters, pre_rls_rows,
                                            authorized_rows, filtered_rows) {
  durdurma <- pk_deep_bounded_deadline_reason(bounded, detail_config$pk_deadline_at)
  if (!is.null(durdurma)) return(pk_deep_halt_result(durdurma))

  finish_result(
    list(query_name = query_name, success = FALSE,
         error_msg = "İstatistiksel özet üretilemedi (iç hata)."),
    filter_status = filter_status, filters = applied_filters,
    pre_rls_rows = pre_rls_rows, authorized_rows = authorized_rows,
    filtered_rows = filtered_rows, outcome = "Hata"
  )
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
    durdurma <- pk_deep_v2_halt_status(detail_config, stop_check) %||%
      pk_deep_bounded_deadline_reason(paket_sonucu, detail_config$pk_deadline_at)
    if (!is.null(durdurma)) return(pk_deep_halt_result(durdurma))
    # SON TARİH DEĞİL, GERÇEK HATA: kullanıcıya "süre doldu" denmez.
    return(finish_result(
      list(query_name = query_name, success = FALSE,
           error_msg = "Analiz paketi kurulamadı (iç hata); sonuç üretilmedi."),
      filter_status = filter_status, filters = applied_filters,
      pre_rls_rows = pre_rls_rows, authorized_rows = nrow(secure_data),
      filtered_rows = nrow(filtered_data), outcome = "Hata"
    ))
  }
  paket <- paket_sonucu$value

  durdurma <- pk_deep_v2_halt_status(detail_config, stop_check)
  if (!is.null(durdurma)) return(pk_deep_halt_result(durdurma))

  paket_yazi <- pk_packet_render(paket, query_meta = query$meta)
  # DERİN ANALİZDE OLGU KİMLİKLERİ SORGUYA GÖRE AD ALANINA ALINIR.
  #
  # Olgu kimliği yalnızca (yetenek/sütun + toplulaştırma + grup) üzerinden
  # üretilir; kapsam ya da sorgu kimliği İÇERMEZ. Aynı yeteneği FARKLI
  # değerlerle sunan iki başarılı v2 sorgusu bu yüzden AYNI kimliği üretiyor,
  # `pk_facts_index()` kimliği `ambiguous_fact_id` işaretliyor ve DOĞRU
  # alıntılanmış bir sayı bile geçersiz sayılıyordu (`block` kipinde tüm model
  # anlatısı düşerdi). Ad alanı hem BASILAN işarete hem TOPLANAN olguya AYNI
  # anda uygulanır; ikisi ayrışamaz.
  ad_alanli <- .pk_deep_namespace_facts(
    paket_yazi$text, pk_packet_all_facts(paket), query$id
  )
  # BÜTÇE AD ALANLAMA SONRASINDA YENİDEN ÖLÇÜLÜR.
  #
  # `pk_packet_render()` bütçeyi ad alanlamadan ÖNCEKİ metin üzerinde hesaplar.
  # Her `[fact:...]` işaretine eklenen `slug_hash__` öneki metni BÜYÜTÜR; bütçe
  # sınırına yakın ve çok işaretli bir paket, ölçülmüş `FALSE` değeriyle
  # BÜTÇEYİ AŞMIŞ hâlde "başarılı" dönüyordu. Bütçe bilinmiyorsa (ör. sahte
  # kurucu) eski karar korunur.
  butce <- suppressWarnings(as.numeric(paket_yazi$budget %||% NA_real_)[1])
  butce_asildi <- if (is.finite(butce)) {
    nchar(ad_alanli$text, type = "chars") > butce
  } else {
    isTRUE(paket_yazi$over_budget)
  }
  if (isTRUE(paket_yazi$over_budget) || isTRUE(butce_asildi)) {
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
      pk_packet_text = ad_alanli$text, pk_packet_chars = nchar(ad_alanli$text),
      pk_facts = ad_alanli$facts,
      pk_fallback_text = pk_compose_facts_summary(paket$facts), data = filtered_data
    ),
    filter_status = filter_status, filters = applied_filters,
    pre_rls_rows = pre_rls_rows, authorized_rows = nrow(secure_data),
    filtered_rows = nrow(filtered_data), outcome = "Basarili"
  )
}

#' Kısaltılmamış sorgu kimliği için deterministik ASCII sağlama
#'
#' `pk_fact_slug()` normalleştirir VE keser; bu yüzden tek başına bir ad alanı
#' anahtarı olamaz. Buradaki polinom karma dış bağımlılık kullanmaz, yerelden
#' bağımsızdır ve sonuç 8 haneli sabit ASCII hex'tir (olgu kimliği jetonu
#' `[A-Za-z0-9_.]` alfabesinde kalır). Kriptografik DEĞİLDİR; amaç yalnızca
#' kaza eseri çarpışmayı ayırmaktır.
.pk_deep_id_checksum <- function(x) {
  ham <- enc2utf8(as.character(x %||% "")[1])
  if (is.na(ham) || !nzchar(ham)) return("00000000")
  baytlar <- as.integer(charToRaw(ham))
  # `h` bir double'dır; en büyük ara değer ~5.6e11 olup 2^53 tam sayı
  # kesinliğinin çok altındadır, taşma olmaz.
  m <- 4294967291  # 2^32'den küçük en büyük asal
  h <- 2166136261
  for (b in baytlar) h <- (h * 131 + b) %% m
  haneler <- c(as.character(0:9), letters[1:6])
  out <- character(8L)
  v <- h
  for (i in 8:1) {
    out[i] <- haneler[(v %% 16) + 1L]
    v <- v %/% 16
  }
  paste0(out, collapse = "")
}

#' Bir v2 paketinin olgu kimliklerini SORGUYA göre ad alanına al
#'
#' Basılan `[fact:...]` işaretleri ile toplanan olgu kayıtları AYNI dönüşümden
#' geçer; aksi hâlde model doğru işareti alıntılar ama doğrulayıcı o kimliği
#' bulamazdı. Saf metin/veri dönüşümüdür.
.pk_deep_namespace_facts <- function(text, facts, query_id) {
  metin <- as.character(text %||% "")[1]
  if (is.na(metin)) metin <- ""
  olgular <- facts %||% list()

  slug <- if (exists("pk_fact_slug", mode = "function", inherits = TRUE)) {
    tryCatch(pk_fact_slug(query_id), error = function(e) "")
  } else {
    ""
  }
  slug <- as.character(slug %||% "")[1]
  if (is.na(slug) || !nzchar(slug)) return(list(text = metin, facts = olgular))

  # AD ALANI ÇARPIŞMAYA DAYANIKLI OLMALIDIR.
  #
  # `pk_fact_slug()` ASCII dışını `_` yapar ve 60 karakterde KESER. Bu yüzden
  # `A-B` ile `A B`, ya da ilk 60 karakteri aynı olan iki sorgu kimliği AYNI
  # slug'ı üretir. İki sorgu aynı olgu kimliğini yayarsa ad alanlı kimlikler de
  # çakışır, `pk_facts_index()` kimliği `ambiguous_fact_id` işaretler ve DOĞRU
  # bir sayısal ifade reddedilir/bloklanır. KISALTILMAMIŞ kimliğin sağlaması
  # eklenerek bu çarpışma kapatılır.
  onek <- paste0(slug, "_", .pk_deep_id_checksum(query_id), "__")

  yeni_olgular <- lapply(olgular, function(olgu) {
    # `NA_character_` bir olgu kimliği `!nzchar(NA)` -> `NA` üretir ve
    # `if (... || NA)` HATA fırlatırdı: tamamlanmış bir sorgu, sonuç
    # birleştirme sırasında çöküyordu.
    if (!is.list(olgu) || !is.character(olgu$fact_id) ||
        length(olgu$fact_id) != 1L || is.na(olgu$fact_id) ||
        !nzchar(olgu$fact_id)) {
      return(olgu)
    }
    olgu$fact_id <- paste0(onek, olgu$fact_id)
    olgu
  })

  yeni_metin <- gsub("\\[fact:([A-Za-z0-9_.]+)\\]",
                     paste0("[fact:", onek, "\\1]"), metin, perl = TRUE)

  list(text = yeni_metin, facts = yeni_olgular)
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

# NOT: v2 olgularını (`facts`/`fallback_text`/`query_id`/`mode`) provenance
# yuvasına taşıyan mantık ARTIK TEK YERDE, `helpers_deep_analysis_reconcile.R`
# içindeki `stash_deep_footer()` imzasında yaşar. Buradaki eski kaynak-zamanı
# sarmalayıcısı aynı birleştirme mantığını kopyalıyordu ve orkestratörün çağrı
# sözleşmesini, sarmalayıcının kurulmuş OLMASINA bağlı kılıyordu; sarmalayıcının
# yüklenmediği izole test/işçi bağlamlarında çağrı "unused arguments" ile
# düşerdi. Tek gövde bırakıldı; davranış aynıdır.

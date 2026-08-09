# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_selection_apply.R
# Açıklama: Faz 5 (§5.2) — iki geçişli seçim hattının ÇALIŞMA ZAMANINA
#           BAĞLANMASI.
#
# NEDEN AYRI DOSYA: Faz 4 incelemesinin en ağır bulgusu, çözümleyicinin
#   351 testi geçerken GERÇEK isteklerde hiç çağrılmamasıydı ("Phase 4 was dead
#   code"). Bu dosya, seçim hattının çağrı yerini AÇIKÇA sahiplenir.
#
# MOTOR SINIRI (§10): buradaki her şey YALNIZCA `MERGEN_PK_ENGINE=v2` iken
#   çalışır. v1'in karar mantığı (AI dalı, sezgisel dal, eşikler, düşük skor
#   geri dönüşü) BİT BİT korunur.
#
# KAPALI BAŞARISIZLIK SINIRI: v2 hattının İÇ hatası artık v1'e DÜŞMEZ. Bir
#   yardımcı eksik ya da nesne bozuksa, operatörün `MERGEN_PK_ENGINE=v2` ile
#   TAM OLARAK etkinleştirdiği güvenlik kapıları (güven, marj, ikinci aday,
#   yetenek) sessizce devre dışı kalırdı; eski davranışta bu, kapısız v1
#   seçicisinin bir sorguyu otomatik çalıştırması demekti.
# ==============================================================================

#' Karardan v1 uyumlu `all_scores` tablosu kur
#'
#' Tablo ŞEKLİ v1 ile aynıdır (`query_id`, `query_name`, `ai_score`,
#' `heuristic_score`, `final_score`), böylece `print_score_table()` ve modülün
#' aşağı akış kodu değişmeden çalışır. `heuristic_score` sütunu v2'de bilinçli
#' olarak 0 kalır: sezgisel skorlayıcı v2'de KARAR VERMEZ (D10).
#'
#' `final_score` SEÇİLEN satırda ETKİN güveni taşır. Karar sözlüksel uyuşmazlık
#' cezasından SONRAKİ değerle verilir; ham güveni "Final Skor" diye göstermek,
#' operatörün eşik ayarını gerçekte karar veren sayıdan farklı bir sayıya göre
#' yapmasına yol açıyordu.
pk_select_scores_table <- function(library, decision) {
  tablo <- if (exists("pk_init_query_score_table", mode = "function", inherits = TRUE)) {
    pk_init_query_score_table(library)
  } else {
    data.frame(
      query_id = character(0), query_name = character(0),
      ai_score = numeric(0), heuristic_score = numeric(0),
      final_score = numeric(0), stringsAsFactors = FALSE
    )
  }

  if (!nrow(tablo)) return(tablo)

  puanla <- function(kimlik, ham, etkin = NULL) {
    if (is.null(kimlik) || is.na(kimlik) || is.null(ham) || is.na(ham)) return(invisible(NULL))
    satir <- which(tablo$query_id == kimlik)
    if (!length(satir)) return(invisible(NULL))
    tablo$ai_score[satir] <<- as.numeric(ham)
    tablo$final_score[satir] <<- as.numeric(etkin %||% ham)
    invisible(NULL)
  }

  # Sıra ÖNEMLİDİR: en az özgül kaynaktan en özgüle doğru yazılır, böylece
  # seçilen satırın ETKİN güveni sonradan çipin HAM güveniyle ezilmez.
  for (cip in decision$chips %||% list()) {
    if (is.list(cip) && !is.null(cip$confidence)) puanla(cip$id, cip$confidence)
  }

  # HER doğrulanmış alternatif yazılır. Eskiden yalnızca ilk ikinci aday
  # yazılıyordu; geçerli skoru olan üçüncü aday tabloda 0 görünüyor ve
  # tanılama "model skor vermedi" diyordu.
  for (kimlik in names(decision$alternate_scores %||% list())) {
    puanla(kimlik, decision$alternate_scores[[kimlik]])
  }

  puanla(decision$query_id, decision$confidence, decision$effective_confidence)

  tablo
}

#' Reddetme/netleştirme mesajını kullanıcıya gösterilecek Türkçe metne çevir
#'
#' Seçenekler (chips) NUMARALI liste olarak eklenir; numara ve ad, kullanıcının
#' bir sonraki mesajında DETERMİNİSTİK olarak eşlenebilir (bkz.
#' `pk_select_resolve_user_choice()`).
pk_select_refusal_message <- function(decision) {
  ana <- decision$message_tr
  if (is.null(ana) || !length(ana) || is.na(ana[1]) || !nzchar(trimws(ana[1]))) {
    ana <- paste0(
      "Sorunuza hangi analizin cevap vereceği güvenle belirlenemedi; yanlış bir ",
      "analiz çalıştırmamak için işlem durduruldu."
    )
  }

  parcalar <- c(paste0("\U0001F914 **Analiz Seçimi Netleştirilmeli:** ", ana))

  cipler <- decision$chips %||% list()
  if (length(cipler)) {
    parcalar <- c(parcalar, "", "**Olası analizler:**")
    for (i in seq_along(cipler)) {
      cip <- cipler[[i]]
      ad <- as.character(cip$name %||% cip$id)[1]
      parcalar <- c(parcalar, sprintf("%d. %s", i, ad))
    }
    parcalar <- c(parcalar, "", paste0(
      "Numarasını ya da adını yazmanız yeterli; seçiminizi doğrudan uygularım."
    ))
  }

  paste(parcalar, collapse = "\n")
}

#' Satır tabanlı günlüğe girecek metni TEMİZLE
#'
#' `selection_reason` doğrudan Geçiş B JSON'undan gelir. İçindeki CR/LF, sahte
#' görünen `[PK_ANALIZ] ...` kayıtları üretip satır tabanlı tanılamayı
#' bozabilir.
.pk_select_log_safe <- function(text, max_chars = 300L) {
  if (is.null(text) || !length(text) || is.na(text[1])) return("")
  metin <- gsub("[[:cntrl:]]+", " ", as.character(text)[1], perl = TRUE)
  metin <- gsub("[[:space:]]+", " ", trimws(metin), perl = TRUE)
  if (nchar(metin) > max_chars) metin <- paste0(substr(metin, 1L, max_chars - 1L), "…")
  metin
}

#' Seçilen sorgunun TANILAMA satırlarını yaz
pk_select_log_selection <- function(selected_query) {
  if (!is.list(selected_query)) return(invisible(FALSE))

  ilgililik <- selected_query$relevance_score %||% 0
  yontem <- selected_query$selection_method %||% "unknown"
  gerekce <- .pk_select_log_safe(selected_query$selection_reason %||% "")

  cat(sprintf(
    "[PK_ANALIZ] Secilen Sorgu: '%s' | İlgililik: %.1f%% | Yontem: %s\n",
    .pk_select_log_safe(selected_query$name, 200L), ilgililik, yontem
  ))
  if (nchar(gerekce) > 0) {
    cat(sprintf("[PK_ANALIZ] Secim Nedeni: %s\n", gerekce))
  }

  invisible(TRUE)
}

#' v2 iç hatası için TİPLİ ret kararı
#'
#' `NULL` DÖNDÜRÜLMEZ: `NULL`, çağıranı v1 karar yoluna sokardı.
.pk_select_internal_failure <- function(library, message) {
  karar <- .pk_select_decision(
    PK_SELECT_STATUS_INTERNAL_ERROR,
    message_tr = paste0(
      "Sorgu seçimi iç bir hata nedeniyle tamamlanamadı; yanlış bir analiz ",
      "çalıştırmamak için işlem durduruldu. Operatöre bildirin."
    ),
    disclosures = .pk_select_log_safe(message)
  )

  list(
    all_scores = pk_select_scores_table(library, karar),
    refusal_message = pk_select_refusal_message(karar),
    pk_selection = karar
  )
}

#' v2 SEÇİM GİRİŞ NOKTASI — `select_smart_query()` bunu çağırır
#'
#' @param session İSTEĞİN SAHİBİ olan oturum. Çağıran açıkça geçirmelidir:
#'   Ortak Oturum köprüsü, soruyu soran kullanıcı için sentetik bir oturum
#'   kurar ve varsayılan reaktif alan adı BAŞKA bir kullanıcıya aittir.
#' @return `auto` kararında: seçilen kütüphane sorgusu + v1 uyumlu seçim
#'   alanları. Diğer her kararda: `id` alanı OLMAYAN, `refusal_message` ve
#'   yapısal `pk_selection` taşıyan liste.
pk_select_query_v2 <- function(prompt, library, chat_history = NULL,
                               session = NULL, llm_fn = NULL, cfg = NULL,
                               stop_check = NULL) {
  if (!is.list(library) || !length(library)) return(NULL)

  sohbet <- pk_select_chat_key(chat_history, session = session)

  karar <- tryCatch(
    .pk_select_decide_for_request(
      prompt, library, chat_history, session, llm_fn, cfg, stop_check, sohbet
    ),
    error = function(e) {
      cat(sprintf("[PK_SELECT] v2 secim hatti hata verdi: %s\n",
                  .pk_select_log_safe(conditionMessage(e))))
      structure(list(message = conditionMessage(e)), class = "pk_select_failure")
    }
  )

  if (inherits(karar, "pk_select_failure")) {
    return(.pk_select_internal_failure(library, karar$message))
  }

  tablo <- pk_select_scores_table(library, karar)

  cat(sprintf(
    "[PK_SELECT] v2 karar=%s | sorgu=%s | guven=%s | etkin=%s | marj=%s | yetenek=%s\n",
    karar$status,
    karar$query_id %||% "-",
    karar$confidence %||% "-",
    karar$effective_confidence %||% "-",
    karar$margin %||% "-",
    karar$capability_status %||% "-"
  ))

  if (!identical(karar$status, PK_SELECT_STATUS_AUTO)) {
    # Tamamlanmayan bir seçim, o söyleşideki "son başarılı seçim" iddiasını
    # GEÇERSİZ kılar: konu değişmiş olabilir ve sonraki eksiltili soru artık
    # eski analize ait değildir.
    pk_select_forget_query_id(session, sohbet)
    pk_select_remember_offer(session, karar$chips, sohbet)

    return(list(
      all_scores = tablo,
      refusal_message = pk_select_refusal_message(karar),
      pk_selection = karar,
      pk_chips = karar$chips %||% list()
    ))
  }

  indeks <- pk_select_library_index(library)
  secilen <- indeks[[karar$query_id]]
  if (is.null(secilen)) {
    return(.pk_select_internal_failure(
      library, sprintf("Secilen kimlik kutuphanede cozulemedi: %s", karar$query_id)
    ))
  }

  secilen$relevance_score <- as.numeric(karar$effective_confidence %||% karar$confidence)
  secilen$selection_method <- as.character(karar$selection_method %||% "ai_two_pass")[1]
  secilen$selection_reason <- {
    gerekce <- karar$reason
    if (is.null(gerekce) || is.na(gerekce)) {
      sprintf("İki geçişli seçim (marj: %s)", karar$margin %||% "-")
    } else {
      gerekce
    }
  }
  secilen$all_scores <- tablo
  secilen$pk_selection <- karar
  # Seçim, çağıran onu KABUL EDENE kadar kalıcılaştırılmaz (bkz.
  # `pk_select_commit_selection()`): hemen iptal edilen bir `auto`, sonraki
  # takip sorusunu kullanıcının durdurduğu analizle tohumlardı.
  secilen$pk_pending_chat_key <- sohbet
  secilen
}

#' Derin Düşünme için v2'nin AYNI iki geçişli kararından güvenli çoklu küme üret
#'
#' İlk sorgu normal `pk_select_query_v2()` yolunda tüm güven/marj/yetenek
#' kapılarından geçmek zorundadır. Ek sorgular YALNIZCA Geçiş B'nin kararlı
#' kimlikli alternatiflerinden seçilir; her biri kendi metadata eşiklerini ve
#' aynı requirements yetenek doğrulamasını ayrıca geçer. Sözlüksel uyuşmazlık
#' olasılığına karşı ek aday güveni `disagree_penalty` kadar baştan pay bırakır.
#' Böylece Derin Düşünme çoklu analiz özelliğini korurken legacy konum-kimliğine
#' dayalı `find_multiple_queries_with_ai()` v2'de yeniden devreye girmez.
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
    if (!length(guven) || is.na(guven)) next

    # Ek aday için doğrudan sözlüksel sıralama yeniden hesaplanmadığından,
    # olası en kötü cezanın ardından da güven kapısını geçeceği kanıtlanır.
    gerekli_guven <- min(100, as.numeric(sorgu_cfg$min_confidence) +
      max(0, as.numeric(sorgu_cfg$disagree_penalty)))
    if (guven < gerekli_guven) next

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
    sonuc[[length(sonuc) + 1L]] <- sorgu
  }

  list(primary = birincil, queries = sonuc)
}

#' Karar üretimi (hata sarmalayıcının içinde çalışır)
.pk_select_decide_for_request <- function(prompt, library, chat_history, session,
                                          llm_fn, cfg, stop_check, chat_key) {
  if (is.null(session)) {
    session <- tryCatch(shiny::getDefaultReactiveDomain(), error = function(e) NULL)
  }

  indeks <- pk_select_library_index(library)

  # Kullanıcı, önceki turda SUNULAN seçeneklerden birini açıkça adlandırdıysa
  # seçim LLM'siz ve deterministik biçimde tamamlanır. Aksi hâlde bozulma kipi
  # "birini söyleyin" deyip cevabı yine erişilemeyen seçiciye götürüyordu.
  onay <- pk_select_confirmed_decision(session, prompt, indeks, chat_key)
  if (!is.null(onay)) {
    onay$candidate_ids <- onay$query_id
    onay$pass_a_status <- NA_character_
    onay$pass_b_status <- NA_character_
    return(onay)
  }

  pk_select_run(
    user_prompt = prompt,
    library = library,
    chat_history = chat_history,
    prior_query_id = pk_select_prior_query_id(session, chat_key),
    session = session,
    llm_fn = llm_fn,
    cfg = cfg,
    stop_check = stop_check
  )
}

#' Seçimi KALICILAŞTIR — çağıran iptal kapısını geçtikten SONRA çağrılır
#'
#' `pk_analiz_process_request()` seçimden sonra bir `stop_check` daha uygular.
#' Kimlik o kapıdan ÖNCE yazılırsa, iptal edilen bir seçim sonraki eksiltili
#' soruyu tohumlar.
pk_select_commit_selection <- function(selected_query, session) {
  if (!is.list(selected_query) || is.null(selected_query$id)) return(invisible(FALSE))

  sohbet <- selected_query$pk_pending_chat_key
  if (is.null(sohbet) || !length(sohbet) || is.na(sohbet[1])) return(invisible(FALSE))

  pk_select_forget_offer(session, sohbet)
  pk_select_remember_query_id(session, selected_query$id, sohbet)
}

#' Seçim kararından yanıta/telemetriye taşınacak bozulma açıklamaları
#'
#' Plan kuralı: HER bozulma yanıtta görünmelidir. Sözlüksel güvenlik sinyali
#' güveni düşürdüğü hâlde seçim yine de çalıştıysa, kullanıcı bunu görmeden
#' sonucu okuyordu.
pk_select_disclosures <- function(selected_query) {
  if (!is.list(selected_query)) return(character(0))
  karar <- selected_query$pk_selection
  if (!is.list(karar)) return(character(0))

  aciklamalar <- as.character(karar$disclosures %||% character(0))
  aciklamalar[!is.na(aciklamalar) & nzchar(trimws(aciklamalar))]
}

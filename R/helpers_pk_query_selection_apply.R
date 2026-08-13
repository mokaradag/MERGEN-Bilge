# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_selection_apply.R
# Açıklama: Faz 5 (§5.2) — iki geçişli seçim hattının çalışma zamanına bağlanması.
#
# MOTOR SINIRI: v2 yolu yalnızca MERGEN_PK_ENGINE=v2 iken çalışır; iç hata v1'e
# sessizce düşmez. Derin-analiz çoklu seçim ve recall tohumu odaklı helper'lara
# ayrılmıştır; bu dosya seçim kararını uygulama/telemetri sınırında tutar.
# ==============================================================================

# İzole module_proje_kaynak_analizi.R yüklemesinde çıkarılmış v1 AI seçicisini
# gerekirse yükle. Normal manifestte zaten daha önce yüklenmiştir. İzole source()
# çağrıları süreç CWD'sine bağlı olmamalıdır: önce bu dosyanın gerçek konumunu,
# sonra açık repo kökünü, repo-root CWD'sini ve tests/testthat CWD'sini deneriz.
.pk_v1_selector_name <- "helpers_pk_analysis_ai_selector.R"
.pk_v1_source_file <- tryCatch({
  ofile <- sys.frame(1)$ofile
  if (is.null(ofile) || !length(ofile) || is.na(ofile[1]) || !nzchar(ofile[1])) {
    NA_character_
  } else {
    normalizePath(ofile[1], winslash = "/", mustWork = FALSE)
  }
}, error = function(e) NA_character_)
.pk_repo_root <- Sys.getenv("MERGEN_REPO_ROOT", unset = "")
.pk_v1_selector_candidates <- unique(c(
  if (!is.na(.pk_v1_source_file)) {
    file.path(dirname(.pk_v1_source_file), .pk_v1_selector_name)
  },
  if (nzchar(.pk_repo_root)) {
    file.path(.pk_repo_root, "R", .pk_v1_selector_name)
  },
  file.path("R", .pk_v1_selector_name),
  file.path("..", "..", "R", .pk_v1_selector_name)
))
.pk_v1_selector_candidates <- .pk_v1_selector_candidates[
  !is.na(.pk_v1_selector_candidates) & nzchar(.pk_v1_selector_candidates)
]
.pk_v1_selector_path <- .pk_v1_selector_candidates[
  file.exists(.pk_v1_selector_candidates)
]
if (!exists("find_best_query_with_ai", mode = "function", inherits = TRUE) &&
    length(.pk_v1_selector_path)) {
  source(.pk_v1_selector_path[[1]], encoding = "UTF-8", local = globalenv())
}
rm(
  .pk_v1_selector_name,
  .pk_v1_source_file,
  .pk_repo_root,
  .pk_v1_selector_candidates,
  .pk_v1_selector_path
)

#' Karardan v1 uyumlu all_scores tablosu kur
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
    if (is.null(kimlik) || is.na(kimlik) || is.null(ham) || is.na(ham)) {
      return(invisible(NULL))
    }
    satir <- which(tablo$query_id == kimlik)
    if (!length(satir)) return(invisible(NULL))
    tablo$ai_score[satir] <<- as.numeric(ham)
    tablo$final_score[satir] <<- as.numeric(etkin %||% ham)
    invisible(NULL)
  }

  for (cip in decision$chips %||% list()) {
    if (is.list(cip) && !is.null(cip$confidence)) puanla(cip$id, cip$confidence)
  }
  for (kimlik in names(decision$alternate_scores %||% list())) {
    puanla(kimlik, decision$alternate_scores[[kimlik]])
  }
  puanla(decision$query_id, decision$confidence, decision$effective_confidence)
  tablo
}

#' Reddetme/netleştirme mesajını kullanıcıya gösterilecek Türkçe metne çevir
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
    parcalar <- c(
      parcalar, "",
      "Numarasını ya da adını yazmanız yeterli; seçiminizi doğrudan uygularım."
    )
  }

  paste(parcalar, collapse = "\n")
}

#' Satır tabanlı günlüğe girecek metni temizle
.pk_select_log_safe <- function(text, max_chars = 300L) {
  if (is.null(text) || !length(text) || is.na(text[1])) return("")
  metin <- gsub("[[:cntrl:]]+", " ", as.character(text)[1], perl = TRUE)
  metin <- gsub("[[:space:]]+", " ", trimws(metin), perl = TRUE)
  if (nchar(metin) > max_chars) metin <- paste0(substr(metin, 1L, max_chars - 1L), "…")
  metin
}

#' Seçilen sorgunun tanılama satırlarını yaz
pk_select_log_selection <- function(selected_query) {
  if (!is.list(selected_query)) return(invisible(FALSE))

  ilgililik <- selected_query$relevance_score %||% 0
  yontem <- selected_query$selection_method %||% "unknown"
  gerekce <- .pk_select_log_safe(selected_query$selection_reason %||% "")

  cat(sprintf(
    "[PK_ANALIZ] Secilen Sorgu: '%s' | İlgililik: %.1f%% | Yontem: %s\n",
    .pk_select_log_safe(selected_query$name, 200L), ilgililik, yontem
  ))
  if (nchar(gerekce) > 0) cat(sprintf("[PK_ANALIZ] Secim Nedeni: %s\n", gerekce))
  invisible(TRUE)
}

#' v2 iç hatası için tipli ret kararı
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

#' v2 seçim giriş noktası — select_smart_query() bunu çağırır
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
    pk_select_forget_query_id(session, sohbet)
    pk_select_remember_offer(session, karar$chips, sohbet,
                             requirements = karar$requirements)
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
  secilen$pk_pending_chat_key <- sohbet
  secilen
}

#' Karar üretimi (hata sarmalayıcının içinde çalışır)
.pk_select_decide_for_request <- function(prompt, library, chat_history, session,
                                          llm_fn, cfg, stop_check, chat_key) {
  if (is.null(session)) {
    session <- tryCatch(shiny::getDefaultReactiveDomain(), error = function(e) NULL)
  }

  indeks <- pk_select_library_index(library)
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

#' Seçimi kalıcılaştır — çağıran iptal kapısını geçtikten sonra çağrılır
pk_select_commit_selection <- function(selected_query, session) {
  if (!is.list(selected_query) || is.null(selected_query$id)) return(invisible(FALSE))

  sohbet <- selected_query$pk_pending_chat_key
  if (is.null(sohbet) || !length(sohbet) || is.na(sohbet[1])) return(invisible(FALSE))

  pk_select_forget_offer(session, sohbet)
  pk_select_remember_query_id(session, selected_query$id, sohbet)
}

#' Seçim kararından yanıta/telemetriye taşınacak bozulma açıklamaları
pk_select_disclosures <- function(selected_query) {
  if (!is.list(selected_query)) return(character(0))
  karar <- selected_query$pk_selection
  if (!is.list(karar)) return(character(0))

  aciklamalar <- as.character(karar$disclosures %||% character(0))
  aciklamalar[!is.na(aciklamalar) & nzchar(trimws(aciklamalar))]
}

# Recall tohumu ve Derin Düşünme köprüsü manifestte bu dosyadan ÖNCE yüklenir;
# runtime bağlama katmanı çalışma dizinine göre ek kaynak yüklemez.

# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_selection_apply.R
# Açıklama: Faz 5 (§5.2) — iki geçişli seçim hattının ÇALIŞMA ZAMANINA
#           BAĞLANMASI.
#
# NEDEN AYRI DOSYA: Faz 4 incelemesinin en ağır bulgusu, çözümleyicinin
#   351 testi geçerken GERÇEK isteklerde hiç çağrılmamasıydı ("Phase 4 was dead
#   code"). Bu dosya, seçim hattının çağrı yerini AÇIKÇA sahiplenir ve
#   `tests/testthat/test-pk-query-selection-contract.R` içinde hem statik hem
#   davranışsal olarak çağrıldığı doğrulanır.
#
# MOTOR SINIRI (§10): buradaki her şey YALNIZCA `MERGEN_PK_ENGINE=v2` iken
#   çalışır. `select_smart_query()` içindeki dal, `apply_smart_filters()`
#   içindeki v2 dalıyla AYNI desendedir. v1'in karar mantığı (AI dalı,
#   sezgisel dal, eşikler, düşük skor geri dönüşü) BİT BİT korunur — plan §10
#   bunu açıkça şart koşar: "The v1 decision logic must remain unchanged".
#
# Bu yüzden `R/helpers_pk_analysis_query_selection.R` (v1 sezgiseli) bu fazda
# SİLİNMEZ, yalnızca v2'de KARAR VERİCİ OLMAKTAN ÇIKARILIR (D10). v2 yolu o
# dosyanın hiçbir skorlama fonksiyonunu çağırmaz; yerine sözlüksel getirim
# (`helpers_pk_query_retrieval.R`) yalnızca bozulma kipi ve uyuşmazlık sinyali
# için kullanılır.
# ==============================================================================

# Oturumda son BAŞARIYLA seçilmiş kararlı sorgu kimliğinin tutulduğu yuva.
.PK_SELECT_PRIOR_ID_SLOT <- "pk_last_selected_query_id"

#' Önceki kararlı sorgu kimliğini oku (eksiltili takip için)
#'
#' Oturum yoksa (worker/test bağlamı) sessizce `NULL` döner.
pk_select_prior_query_id <- function(session = NULL) {
  if (is.null(session)) return(NULL)

  deger <- tryCatch(session$userData[[.PK_SELECT_PRIOR_ID_SLOT]], error = function(e) NULL)
  if (is.null(deger) || !length(deger) || is.na(deger[1])) return(NULL)

  kimlik <- trimws(as.character(deger)[1])
  if (!nzchar(kimlik)) return(NULL)
  kimlik
}

#' Seçilen kararlı kimliği oturuma yaz
pk_select_remember_query_id <- function(session, query_id) {
  if (is.null(session) || is.null(query_id) || !length(query_id) || is.na(query_id[1])) {
    return(invisible(FALSE))
  }

  kimlik <- trimws(as.character(query_id)[1])
  if (!nzchar(kimlik)) return(invisible(FALSE))

  tryCatch({
    session$userData[[.PK_SELECT_PRIOR_ID_SLOT]] <- kimlik
    invisible(TRUE)
  }, error = function(e) invisible(FALSE))
}

#' Karardan v1 uyumlu `all_scores` tablosu kur
#'
#' Tablo ŞEKLİ v1 ile aynıdır (`query_id`, `query_name`, `ai_score`,
#' `heuristic_score`, `final_score`), böylece `print_score_table()` ve modülün
#' aşağı akış kodu değişmeden çalışır. `heuristic_score` sütunu v2'de bilinçli
#' olarak 0 kalır: sezgisel skorlayıcı v2'de KARAR VERMEZ (D10) ve onun
#' skorunu buraya yazmak, tabloyu okuyan birine hâlâ karar sürecinin parçasıymış
#' izlenimi verirdi.
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

  puanla <- function(kimlik, deger) {
    if (is.null(kimlik) || is.na(kimlik) || is.null(deger) || is.na(deger)) return(invisible(NULL))
    satir <- which(tablo$query_id == kimlik)
    if (!length(satir)) return(invisible(NULL))
    tablo$ai_score[satir] <<- as.numeric(deger)
    tablo$final_score[satir] <<- as.numeric(deger)
    invisible(NULL)
  }

  puanla(decision$query_id, decision$confidence)
  puanla(decision$runner_up_id, decision$runner_up_confidence)

  for (cip in decision$chips %||% list()) {
    if (is.list(cip) && !is.null(cip$confidence)) puanla(cip$id, cip$confidence)
  }

  tablo
}

#' Reddetme/netleştirme mesajını kullanıcıya gösterilecek Türkçe metne çevir
#'
#' Seçenekler (chips) NUMARALI liste olarak eklenir. Tıklanabilir çip
#' gösterimi tarayıcı katmanının işidir; bu katman veriyi ve metni üretir.
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
    parcalar <- c(parcalar, "", "Hangisini istediğinizi yazabilirsiniz.")
  }

  paste(parcalar, collapse = "\n")
}

#' Seçilen sorgunun TANILAMA satırlarını yaz
#'
#' Modülden çıkarıldı: yalnızca `cat()` tanılamasıdır, orkestrasyon değildir.
#' Davranış BİREBİR korunur (aynı metin, aynı koşul), yalnızca sahibi değişti.
#' Hem v1 hem v2 seçimleri için çalışır: alanlar v1 uyumludur.
pk_select_log_selection <- function(selected_query) {
  if (!is.list(selected_query)) return(invisible(FALSE))

  ilgililik <- selected_query$relevance_score %||% 0
  yontem <- selected_query$selection_method %||% "unknown"
  gerekce <- selected_query$selection_reason %||% ""

  cat(sprintf(
    "[PK_ANALIZ] Secilen Sorgu: '%s' | İlgililik: %.1f%% | Yontem: %s\n",
    selected_query$name, ilgililik, yontem
  ))
  if (nchar(gerekce) > 0) {
    cat(sprintf("[PK_ANALIZ] Secim Nedeni: %s\n", gerekce))
  }

  invisible(TRUE)
}

#' v2 SEÇİM GİRİŞ NOKTASI — `select_smart_query()` bunu çağırır
#'
#' @return `auto` kararında: seçilen kütüphane sorgusu + v1 uyumlu seçim
#'   alanları (`relevance_score`, `selection_method`, `selection_reason`,
#'   `all_scores`) ve tanılama için `pk_selection`.
#'   Diğer her kararda: `id` alanı OLMAYAN, `refusal_message` taşıyan liste —
#'   modül bunu kullanıcıya döndürür ve v1'in düşük eşik geri dönüşüne
#'   DÜŞMEZ (yanlış sorguyu çalıştırmaktansa sormak yeğdir).
#'   Hattın kendisi çalışamazsa `NULL` döner ve çağıran v1 gövdesine düşer.
pk_select_query_v2 <- function(prompt, library, chat_history = NULL,
                               session = NULL, llm_fn = NULL, cfg = NULL) {
  if (!is.list(library) || !length(library)) return(NULL)

  if (is.null(session)) {
    session <- tryCatch(shiny::getDefaultReactiveDomain(), error = function(e) NULL)
  }

  karar <- tryCatch(
    pk_select_run(
      user_prompt = prompt,
      library = library,
      chat_history = chat_history,
      prior_query_id = pk_select_prior_query_id(session),
      session = session,
      llm_fn = llm_fn,
      cfg = cfg
    ),
    error = function(e) {
      cat(sprintf("[PK_SELECT] v2 secim hatti hata verdi: %s\n", conditionMessage(e)))
      NULL
    }
  )

  # Hat hiç çalışamadıysa motor sınırı korunur: çağıran v1 gövdesine düşer.
  if (is.null(karar)) return(NULL)

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
    return(list(
      all_scores = tablo,
      refusal_message = pk_select_refusal_message(karar),
      pk_selection = karar
    ))
  }

  indeks <- pk_select_library_index(library)
  secilen <- indeks[[karar$query_id]]
  if (is.null(secilen)) return(NULL)

  pk_select_remember_query_id(session, karar$query_id)

  secilen$relevance_score <- as.numeric(karar$effective_confidence %||% karar$confidence)
  secilen$selection_method <- "ai_two_pass"
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
  secilen
}

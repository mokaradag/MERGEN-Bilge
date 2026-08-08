# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_selection_ai.R
# Açıklama: Faz 5 (§5.2) — iki geçişli LLM sorgu seçiminin ORKESTRASYONU.
#
#           Geçiş A (recall)    : TÜM kütüphane -> N aday KARARLI kimlik
#           Geçiş B (precision) : yalnızca o adaylar -> tek seçim + gerekçe +
#                                 kendi güvenli alternatifler + requirements
#
# D14 (zaman aşımı ve anlamsız yeniden deneme) BU DOSYADA KAPATILIR:
#   * her iki geçiş de `request_timeout_sec` ile çağrılır — v1'de HİÇ zaman
#     aşımı yoktu ve asılı bir uç nokta olay döngüsünü bloke ediyordu;
#   * yeniden deneme YALNIZCA bozuk/zaman aşımına uğramış çıktı içindir ve
#     AYNI istemi tekrarlamaz: doğrulama hatası isteme EKLENİR (onarım denemesi).
#     v1 ise `temperature = 0.0` ile birebir aynı çağrıyı iki kez yapıyordu.
#
# LLM çağrısı `llm_fn` üzerinden ENJEKTE EDİLEBİLİR; bu sayede tüm seçim hattı
# gerçek uç nokta olmadan, çevrimdışı ve deterministik biçimde test edilebilir.
# ==============================================================================

# Zaman aşımı sınıflandırması için aranan imzalar (v1 filtre hattıyla aynı ruh).
#
# DİKKAT — burada yalın `"connect"` KULLANILMAZ: "connection refused" bir zaman
# aşımı DEĞİL, anında reddedilmiş bir bağlantıdır ve ölçüldüğünde `timeout`
# olarak sınıflanıyordu. Gerçek zaman aşımı metinleri ("Connection timed out"
# dâhil) zaten "timed out" ile yakalanır. Yanlış sınıflama telemetriyi
# bozar ve operatörü asılı uç nokta aramaya yönlendirir.
.PK_SELECT_TIMEOUT_PATTERNS <- c(
  "timeout", "timed out", "zaman a", "operation was aborted",
  "resolving timed out"
)

.pk_select_classify_error <- function(message) {
  metin <- tolower(as.character(message)[1] %||% "")
  if (any(vapply(.PK_SELECT_TIMEOUT_PATTERNS, function(p) grepl(p, metin, fixed = TRUE), logical(1)))) {
    return(PK_SELECT_STATUS_TIMEOUT)
  }
  PK_SELECT_STATUS_LLM_UNAVAILABLE
}

#' Seçim için etkin API anahtarını çöz
#'
#' Anahtar DEĞERİ hiçbir yerde loglanmaz/dönmez; yalnızca çağrıya verilir.
.pk_select_api_key <- function(session, creds) {
  anahtar <- NULL
  if (!is.null(session) && !is.null(session$userData$ai_api_key)) {
    anahtar <- as.character(session$userData$ai_api_key)[1]
  }
  if (is.null(anahtar) || is.na(anahtar) || !nzchar(anahtar)) {
    varsayilan <- creds$default_api_key %||% ""
    if (nzchar(varsayilan)) anahtar <- as.character(varsayilan)[1]
  }
  anahtar
}

#' Tek bir seçim LLM çağrısı (zaman aşımlı)
#'
#' @param llm_fn `function(messages, settings)` — enjekte edilebilir. `NULL`
#'   ise gerçek `call_local_llm()` kullanılır.
#' @return `ok`, `text`, `status` alanlı liste. `ok = FALSE` iken `status`
#'   `timeout` veya `llm_unavailable`tır.
pk_select_llm_invoke <- function(messages, cfg, session = NULL, llm_fn = NULL,
                                 max_output_tokens = 400L) {
  if (is.null(llm_fn)) {
    if (!exists("call_local_llm", mode = "function", inherits = TRUE)) {
      return(list(ok = FALSE, text = NA_character_, status = PK_SELECT_STATUS_LLM_UNAVAILABLE))
    }
    llm_fn <- function(messages, settings) call_local_llm(messages, settings)
  }

  model <- tryCatch(
    getOption("mergen.filter_model", api_config$local_models[1]),
    error = function(e) NULL
  )
  creds <- tryCatch(
    if (exists("resolve_local_llm_credentials", mode = "function", inherits = TRUE)) {
      resolve_local_llm_credentials(model)
    } else {
      list()
    },
    error = function(e) list()
  )

  ayarlar <- list(
    model_selection = model,
    temperature = 0.0,
    max_output_tokens = as.integer(max_output_tokens),
    enable_mcp_tools = FALSE,
    shiny_session = session,
    api_key_override = .pk_select_api_key(session, creds),
    # D14: v1'de bu alan HİÇ YOKTU.
    request_timeout_sec = cfg$timeout_sec
  )

  sonuc <- tryCatch(
    llm_fn(messages, ayarlar),
    error = function(e) {
      structure(list(), class = "pk_select_llm_error", message = conditionMessage(e))
    }
  )

  if (inherits(sonuc, "pk_select_llm_error")) {
    return(list(
      ok = FALSE, text = NA_character_,
      status = .pk_select_classify_error(attr(sonuc, "message"))
    ))
  }

  if (is.null(sonuc)) {
    return(list(ok = FALSE, text = NA_character_, status = PK_SELECT_STATUS_LLM_UNAVAILABLE))
  }

  icerik <- if (is.list(sonuc)) sonuc$content else sonuc
  if (is.null(icerik) || !length(icerik) || is.na(icerik[1]) ||
      !nzchar(trimws(as.character(icerik)[1]))) {
    return(list(ok = FALSE, text = NA_character_, status = PK_SELECT_STATUS_MALFORMED))
  }

  list(ok = TRUE, text = as.character(icerik)[1], status = "ok")
}

#' Geçiş A: recall (TÜM kütüphane)
#'
#' Onarım denemesi YALNIZCA bozuk çıktıda yapılır ve doğrulama hatasını isteme
#' ekler. Zaman aşımında AYNI çağrı tekrarlanmaz: asılı bir uç noktayı ikinci
#' kez beklemek olay döngüsünü iki katı süre bloke eder ve hiçbir şeyi düzeltmez.
pk_select_run_pass_a <- function(user_prompt, payload, context, cfg,
                                 session = NULL, llm_fn = NULL) {
  onarim <- NULL

  for (deneme in seq_len(2L)) {
    mesajlar <- pk_select_pass_a_messages(user_prompt, payload, context, cfg, repair_error = onarim)
    cagri <- pk_select_llm_invoke(mesajlar, cfg, session, llm_fn)

    if (!isTRUE(cagri$ok)) {
      if (identical(cagri$status, PK_SELECT_STATUS_MALFORMED) && deneme < 2L) {
        onarim <- "Onceki cevap bos ya da metin degildi. Yalnizca gecerli JSON dondur."
        next
      }
      return(list(ok = FALSE, ids = character(0), status = cagri$status,
                  error = NA_character_, attempts = deneme))
    }

    ayrisik <- pk_select_parse_pass_a(cagri$text, payload$ids)
    if (isTRUE(ayrisik$ok) && length(ayrisik$ids)) {
      return(list(ok = TRUE, ids = ayrisik$ids, status = "ok",
                  unknown = ayrisik$unknown, error = NA_character_, attempts = deneme))
    }

    if (deneme < 2L) {
      onarim <- ayrisik$error %||% "Gecerli aday kimligi dondurulmedi."
      next
    }

    return(list(ok = FALSE, ids = character(0), status = PK_SELECT_STATUS_MALFORMED,
                error = ayrisik$error, attempts = deneme))
  }

  list(ok = FALSE, ids = character(0), status = PK_SELECT_STATUS_MALFORMED,
       error = NA_character_, attempts = 2L)
}

#' Geçiş B: precision (yalnızca çözümlenmiş adaylar)
pk_select_run_pass_b <- function(user_prompt, candidates, candidate_ids, context, cfg,
                                 session = NULL, llm_fn = NULL,
                                 capability_ids = character(0)) {
  onarim <- NULL

  for (deneme in seq_len(2L)) {
    mesajlar <- pk_select_pass_b_messages(
      user_prompt, candidates, context, cfg,
      capability_ids = capability_ids, repair_error = onarim
    )
    cagri <- pk_select_llm_invoke(mesajlar, cfg, session, llm_fn, max_output_tokens = 700L)

    if (!isTRUE(cagri$ok)) {
      if (identical(cagri$status, PK_SELECT_STATUS_MALFORMED) && deneme < 2L) {
        onarim <- "Onceki cevap bos ya da metin degildi. Yalnizca gecerli JSON dondur."
        next
      }
      return(list(ok = FALSE, id = NA_character_, confidence = NA_integer_,
                  alternates = list(), requirements = NULL,
                  missing_info = NA_character_, reason = NA_character_,
                  status = cagri$status, error = NA_character_, attempts = deneme))
    }

    ayrisik <- pk_select_parse_pass_b(cagri$text, candidate_ids)
    if (isTRUE(ayrisik$ok)) {
      ayrisik$status <- "ok"
      ayrisik$attempts <- deneme
      return(ayrisik)
    }

    if (deneme < 2L) {
      onarim <- ayrisik$error %||% "Cevap sozlesmeye uymuyor."
      next
    }

    ayrisik$status <- PK_SELECT_STATUS_MALFORMED
    ayrisik$attempts <- deneme
    return(ayrisik)
  }

  list(ok = FALSE, id = NA_character_, confidence = NA_integer_, alternates = list(),
       requirements = NULL, missing_info = NA_character_, reason = NA_character_,
       status = PK_SELECT_STATUS_MALFORMED, error = NA_character_, attempts = 2L)
}

#' Kütüphaneyi kararlı kimliğe göre indeksle (D13)
pk_select_library_index <- function(library) {
  indeks <- list()
  if (!is.list(library) || !length(library)) return(indeks)

  for (kayit in library) {
    kimlik <- pk_select_query_id(kayit)
    if (is.na(kimlik)) next
    # İlk kayıt kazanır; kopya kimlik startup doğrulamasının konusudur ve
    # burada sessizce ikincisiyle DEĞİŞTİRİLMEZ.
    if (is.null(indeks[[kimlik]])) indeks[[kimlik]] <- kayit
  }

  indeks
}

#' Geçiş A adaylarını, ÖNCEKİ kararlı sorgu kimliğiyle tohumla (§5.2)
#'
#' Eksiltili takip sorularında ("peki 2024 için?") soru metninde artık hiçbir
#' sorgu-taşıyıcı terim yoktur; Geçiş A doğru sorguyu bulamaz. Bu yüzden önceki
#' kararlı kimlik, recall SINIRI UYGULANMADAN ÖNCE kümeye eklenir ve yeni
#' bulunan kimliklerle TEKİLLEŞTİRİLİR. Geçiş B onu yine reddedebilir; ama
#' Geçiş A, konuşmayı inceleme şansı doğmadan tek sorgu-taşıyıcı bağlamı
#' ATMAMALIDIR.
pk_select_seed_candidates <- function(recalled_ids, prior_query_id, cfg) {
  aday <- as.character(recalled_ids)
  aday <- aday[!is.na(aday) & nzchar(aday)]

  if (!is.null(prior_query_id) && length(prior_query_id) &&
      !is.na(prior_query_id[1]) && nzchar(trimws(as.character(prior_query_id)[1]))) {
    onceki <- trimws(as.character(prior_query_id)[1])
    # Tohum ÖNCE, kırpma SONRA.
    aday <- unique(c(onceki, aday))
  } else {
    aday <- unique(aday)
  }

  utils::head(aday, cfg$recall_n)
}

#' Bozulma kipi kararı: LLM yok (§5.2)
#'
#' Sözlüksel ilk 3 aday KULLANICIYA seçenek olarak sunulur; hiçbir zaman
#' otomatik çalıştırılmaz. Bu, sözlüksel katmanın izin verilen tek "öne
#' çıkarma" rolüdür.
pk_select_degraded_decision <- function(status, index, prompt, library_index) {
  siralama <- if (is.null(index)) NULL else pk_retrieval_score(index, prompt)
  kimlikler <- if (is.null(siralama) || !nrow(siralama)) character(0) else siralama$query_id

  .pk_select_decision(
    status,
    message_tr = paste0(
      "Sorgu seçimi şu anda yapılamadı (yapay zekâ servisine ulaşılamıyor). ",
      "Aşağıdaki analizlerden hangisini istediğinizi belirtirseniz devam edebilirim."
    ),
    chips = pk_select_chips(kimlikler, library_index),
    disclosures = "Seçim sözlüksel getirime düşürüldü; otomatik çalıştırma yapılmadı."
  )
}

#' İKİ GEÇİŞLİ seçim — tam orkestrasyon (§5.2)
#'
#' @param prior_query_id Bu oturumda en son BAŞARIYLA seçilmiş kararlı sorgu
#'   kimliği (eksiltili takip soruları için tohum).
#' @param llm_fn Enjekte edilebilir LLM çağrısı (testler için).
#' @return `pk_select_decide()` karar nesnesi; ek olarak `candidate_ids`,
#'   `pass_a_status` ve `pass_b_status` alanları taşır.
pk_select_run <- function(user_prompt, library, chat_history = NULL,
                          prior_query_id = NULL, session = NULL,
                          llm_fn = NULL, cfg = NULL, index = NULL) {
  if (is.null(cfg)) cfg <- pk_select_config()
  library_index <- pk_select_library_index(library)

  if (!isTRUE(cfg$valid)) {
    karar <- pk_select_decide(NULL, character(0), library_index, cfg)
    karar$candidate_ids <- character(0)
    karar$pass_a_status <- NA_character_
    karar$pass_b_status <- NA_character_
    return(karar)
  }

  payload <- pk_select_pass_a_payload(library, cfg)
  if (!length(payload$ids)) {
    karar <- pk_select_decide(NULL, character(0), library_index, cfg)
    karar$candidate_ids <- character(0)
    karar$pass_a_status <- NA_character_
    karar$pass_b_status <- NA_character_
    return(karar)
  }

  if (is.null(index)) index <- pk_retrieval_build_index(library)
  baglam <- pk_select_follow_up_context(chat_history, prior_query_id, payload$ids, cfg)
  yetenekler <- pk_select_capability_ids()

  gecis_a <- pk_select_run_pass_a(user_prompt, payload, baglam, cfg, session, llm_fn)
  if (!isTRUE(gecis_a$ok)) {
    karar <- pk_select_degraded_decision(gecis_a$status, index, user_prompt, library_index)
    karar$candidate_ids <- character(0)
    karar$pass_a_status <- gecis_a$status
    karar$pass_b_status <- NA_character_
    return(karar)
  }

  aday_kimlikler <- pk_select_seed_candidates(gecis_a$ids, baglam$prior_query_id, cfg)
  adaylar <- lapply(aday_kimlikler, function(k) library_index[[k]])

  gecis_b <- pk_select_run_pass_b(
    user_prompt, adaylar, aday_kimlikler, baglam, cfg,
    session = session, llm_fn = llm_fn, capability_ids = yetenekler
  )

  if (!isTRUE(gecis_b$ok) &&
      gecis_b$status %in% c(PK_SELECT_STATUS_TIMEOUT, PK_SELECT_STATUS_LLM_UNAVAILABLE)) {
    karar <- pk_select_degraded_decision(gecis_b$status, index, user_prompt, library_index)
    karar$candidate_ids <- aday_kimlikler
    karar$pass_a_status <- gecis_a$status
    karar$pass_b_status <- gecis_b$status
    return(karar)
  }

  uyum <- pk_retrieval_agreement(index, user_prompt, gecis_b$id, cfg$recall_n)

  karar <- pk_select_decide(
    gecis_b, aday_kimlikler, library_index, cfg,
    lexical = uyum, capability_ids = yetenekler
  )
  karar$candidate_ids <- aday_kimlikler
  karar$pass_a_status <- gecis_a$status
  karar$pass_b_status <- gecis_b$status
  karar
}

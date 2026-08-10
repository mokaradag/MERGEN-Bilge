# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_selection_ai.R
# Açıklama: Faz 5 (§5.2) — iki geçişli LLM sorgu seçiminin ORKESTRASYONU.
#
#           Geçiş A (recall)    : TÜM kütüphane -> N aday KARARLI kimlik
#           Geçiş B (precision) : yalnızca o adaylar -> tek seçim + gerekçe +
#                                 HER adayın güveni + requirements
#
# D14 (zaman aşımı ve anlamsız yeniden deneme) BU DOSYADA KAPATILIR:
#   * her iki geçiş de `request_timeout_sec` ile çağrılır — v1'de HİÇ zaman
#     aşımı yoktu ve asılı bir uç nokta olay döngüsünü bloke ediyordu;
#   * yeniden deneme YALNIZCA bozuk çıktı içindir ve AYNI istemi tekrarlamaz:
#     doğrulama hatası ayrı bir VERİ mesajı olarak eklenir (onarım denemesi).
#     Zaman aşımı TEKRARLANMAZ: asılı bir uç noktayı ikinci kez beklemek olay
#     döngüsünü iki katı süre bloke eder ve hiçbir şeyi düzeltmez.
#
# LLM çağrısı `llm_fn` üzerinden ENJEKTE EDİLEBİLİR; bu sayede tüm seçim hattı
# gerçek uç nokta olmadan, çevrimdışı ve deterministik biçimde test edilebilir.
# ==============================================================================

# Geçiş B çıktı bütçesi aday sayısıyla ÖLÇEKLENİR: `alternates` artık
# SEÇİLMEYEN HER adayı taşımak zorundadır ve 20 adaylık bir yapılandırmada
# sözleşmeye UYAN bir cevap sabit 400 belirteci aşıp kırpılabilirdi (onarım
# denemesi de aynı tavanı kullandığı için kurtaramazdı).
.PK_SELECT_PASS_A_TOKENS <- 400L
.PK_SELECT_PASS_B_BASE_TOKENS <- 320L
.PK_SELECT_PASS_B_PER_CANDIDATE <- 60L
.PK_SELECT_PASS_B_MAX_TOKENS <- 2000L

.pk_select_pass_b_tokens <- function(candidate_n) {
  n <- suppressWarnings(as.integer(candidate_n)[1])
  if (!length(n) || is.na(n) || n < 1L) n <- 1L
  min(
    .PK_SELECT_PASS_B_MAX_TOKENS,
    .PK_SELECT_PASS_B_BASE_TOKENS + .PK_SELECT_PASS_B_PER_CANDIDATE * n
  )
}

#' Seçim için etkin API anahtarını çöz
#'
#' Anahtar DEĞERİ hiçbir yerde loglanmaz/dönmez; yalnızca çağrıya verilir.
#'
#' `session$userData$ai_api_key` DOĞRUDAN OKUNMAZ: o yuva, kimlik değiştiğinde
#' başka bir uygulama kullanıcısının kişisel kimlik bilgisini taşıyor olabilir.
#' Sahiplik denetimi ve uyuşmazlık temizliği merkezî yardımcıdadır (§1F).
.pk_select_api_key <- function(session, creds) {
  if (exists("mb_api_key_get_feature_key_value", mode = "function", inherits = TRUE)) {
    anahtar <- tryCatch(
      mb_api_key_get_feature_key_value(
        session = session,
        fallback_key = creds$default_api_key %||% ""
      ),
      error = function(e) NULL
    )
    if (!is.null(anahtar) && length(anahtar) && !is.na(anahtar[1]) &&
        nzchar(as.character(anahtar)[1])) {
      return(as.character(anahtar)[1])
    }
  }

  varsayilan <- creds$default_api_key %||% ""
  if (nzchar(varsayilan)) as.character(varsayilan)[1] else NULL
}

#' Tek bir seçim LLM çağrısı (zaman aşımlı)
#'
#' @param llm_fn `function(messages, settings)` — enjekte edilebilir. `NULL`
#'   ise gerçek `call_local_llm()` kullanılır.
#' @return `ok`, `text`, `status` alanlı liste.
pk_select_llm_invoke <- function(messages, cfg, session = NULL, llm_fn = NULL,
                                 max_output_tokens = .PK_SELECT_PASS_A_TOKENS) {
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

  # Faz 6 (§5.10): her geçiş KALAN analiz bütçesiyle de sınırlanır. Yalnızca
  # `cfg$timeout_sec` (120s'e kadar) kullanmak, kuyruk/bootstrap/RLS sonrası
  # birkaç saniye kalmış bir istekte işçiyi ve DB bağlantısını seçici zaman
  # aşımı dolana kadar meşgul ederdi.
  etkin_timeout <- cfg$timeout_sec
  .select_deadline <- getOption("mergen.pk.async.deadline_at", NULL)
  if (!is.null(.select_deadline) &&
      exists("pk_sql_timeout_plan", mode = "function", inherits = TRUE) &&
      exists("pk_deadline_remaining_sec", mode = "function", inherits = TRUE)) {
    .select_plan <- tryCatch(
      pk_sql_timeout_plan(cfg$timeout_sec, pk_deadline_remaining_sec(.select_deadline)),
      error = function(e) list(dispatch = TRUE, timeout_sec = cfg$timeout_sec)
    )
    if (!isTRUE(.select_plan$dispatch)) {
      return(structure(list(), class = "pk_select_llm_error",
                       message = "Kalan analiz butcesi yok; secim cagrisi gonderilmedi."))
    }
    etkin_timeout <- as.integer(.select_plan$timeout_sec)
  }

  ayarlar <- list(
    model_selection = model,
    temperature = 0.0,
    max_output_tokens = as.integer(max_output_tokens),
    enable_mcp_tools = FALSE,
    shiny_session = session,
    api_key_override = .pk_select_api_key(session, creds),
    # D14: v1'de bu alan HİÇ YOKTU.
    request_timeout_sec = etkin_timeout
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
#' Beklenen aday SAYISI zorunludur: eskiden boş olmayan HERHANGİ bir geçerli alt
#' küme başarı sayılıyordu. `recall_n = 5` iken iki kimlik döndüren bir cevap
#' "başarılı recall" oluyor, atlanan sorgu doğru olan olsa bile Geçiş B onu asla
#' geri getiremiyordu — tam olarak tam-kütüphane geçişinin önlemesi gereken
#' geri alınamaz sessiz başarısızlık.
pk_select_run_pass_a <- function(user_prompt, payload, context, cfg,
                                 session = NULL, llm_fn = NULL) {
  onarim <- NULL
  beklenen <- min(as.integer(cfg$recall_n), length(payload$ids))

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

    ayrisik <- pk_select_parse_pass_a(cagri$text, payload$ids, expected_n = beklenen)
    if (isTRUE(ayrisik$ok)) {
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
#'
#' ANLAMSAL doğrulama onarım DÖNGÜSÜNÜN İÇİNDEDİR: eskiden ayrıştırması geçerli
#' her cevap hemen dönüyor, uydurulmuş bir yetenek kimliği ancak karar
#' aşamasında fark ediliyordu — yani ilan edilen onarım denemesi bu hata için
#' HİÇ çalışmıyordu.
pk_select_run_pass_b <- function(user_prompt, candidates, candidate_ids, context, cfg,
                                 session = NULL, llm_fn = NULL,
                                 capability_ids = character(0),
                                 library_index = list()) {
  onarim <- NULL
  bloklar <- pk_select_pass_b_blocks(candidates, cfg)

  if (isTRUE(bloklar$truncated)) {
    return(list(ok = FALSE, id = NA_character_, confidence = NA_integer_,
                alternates = list(), requirements = NULL,
                missing_info = NA_character_, reason = NA_character_,
                status = PK_SELECT_STATUS_LIBRARY_ERROR, attempts = 0L,
                error = paste0(
                  "Aday metadata'si Gecis B istem butcesini asiyor; sessiz kirpma ",
                  "yerine secim durduruldu."
                )))
  }

  belirtec <- .pk_select_pass_b_tokens(length(candidate_ids))

  for (deneme in seq_len(2L)) {
    mesajlar <- pk_select_pass_b_messages(
      user_prompt, candidates, context, cfg,
      capability_ids = capability_ids, repair_error = onarim, blocks = bloklar
    )
    cagri <- pk_select_llm_invoke(mesajlar, cfg, session, llm_fn, max_output_tokens = belirtec)

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
      anlamsal <- .pk_select_repairable_semantic_error(
        ayrisik, library_index, capability_ids
      )
      if (is.na(anlamsal) || deneme >= 2L) {
        ayrisik$status <- "ok"
        ayrisik$attempts <- deneme
        return(ayrisik)
      }
      onarim <- anlamsal
      next
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

#' ONARILABİLİR anlamsal hata var mı?
#'
#' Yalnızca MODEL HATASI onarılabilir: kayıt defterinde olmayan bir yetenek
#' kimliği uydurulmuşsa ikinci deneme düzeltebilir. "Sorgu bu yeteneği
#' sunmuyor" ise bir metadata gerçeğidir; aynı istemi tekrarlamak onu
#' değiştirmez ve karar politikasına bırakılır.
.pk_select_repairable_semantic_error <- function(pass_b, library_index, capability_ids) {
  secilen <- library_index[[pass_b$id]]
  if (is.null(secilen)) return(NA_character_)

  kontrol <- pk_select_validate_requirements(secilen, pass_b$requirements, capability_ids)
  if (identical(kontrol$status, "unknown_capability")) {
    return(sprintf(
      "requirements icinde IZINLI OLMAYAN yetenek kimligi var: %s. Yalnizca izinli listedeki kimlikleri kullan.",
      paste(kontrol$unknown, collapse = ", ")
    ))
  }

  NA_character_
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

#' Kullanıcı SUNULAN seçeneklerden birini açıkça seçti mi?
#'
#' Bozulma kipinde "hangisini istersiniz?" diye sorup, cevabı yeniden aynı
#' erişilemeyen seçiciye götürmek kapalı bir döngüdür. Bu yol seçimi LLM'siz
#' ve DETERMİNİSTİK olarak tamamlar; aşağı akış güvenlik denetimleri (RLS,
#' salt-okunur SQL, satır tavanı) DEĞİŞMEDEN uygulanır.
pk_select_confirmed_decision <- function(session, prompt, library_index, chat_key) {
  kimlik <- pk_select_resolve_user_choice(session, prompt, chat_key)
  if (is.na(kimlik)) return(NULL)

  secilen <- library_index[[kimlik]]
  if (is.null(secilen)) return(NULL)

  .pk_select_decision(
    PK_SELECT_STATUS_AUTO,
    message_tr = NA_character_,
    query_id = kimlik,
    confidence = 100L,
    effective_confidence = 100L,
    reason = "Kullanici sunulan secenekler arasindan bu analizi acikca sectiler.",
    capability_status = "not_asserted",
    selection_method = "user_confirmed",
    disclosures = "Secim kullanicinin acik onayiyla yapildi; model secimi calistirilmadi."
  )
}

#' İKİ GEÇİŞLİ seçim — tam orkestrasyon (§5.2)
#'
#' @param prior_query_id Bu SÖYLEŞİDE en son BAŞARIYLA seçilmiş kararlı sorgu
#'   kimliği (eksiltili takip soruları için tohum).
#' @param stop_check İptal yüklemi; Geçiş B başlatılmadan ÖNCE denetlenir.
#' @param llm_fn Enjekte edilebilir LLM çağrısı (testler için).
#' @return `pk_select_decide()` karar nesnesi; ek olarak `candidate_ids`,
#'   `pass_a_status` ve `pass_b_status` alanları taşır.
pk_select_run <- function(user_prompt, library, chat_history = NULL,
                          prior_query_id = NULL, session = NULL,
                          llm_fn = NULL, cfg = NULL, index = NULL,
                          stop_check = NULL) {
  # Çağıranın `valid = TRUE` iddiasına GÜVENİLMEZ: enjekte edilen bir nesne
  # aralık dışı eşiklerle kapalı-başarısız sözleşmesini atlatabilirdi.
  cfg <- pk_select_revalidate_config(cfg)
  library_index <- pk_select_library_index(library)

  bitir <- function(karar, adaylar = character(0), a = NA_character_, b = NA_character_) {
    karar$candidate_ids <- adaylar
    karar$pass_a_status <- a
    karar$pass_b_status <- b
    karar
  }

  if (!isTRUE(cfg$valid)) {
    return(bitir(pk_select_decide(NULL, character(0), library_index, cfg)))
  }

  payload <- pk_select_pass_a_payload(library, cfg)
  if (!length(payload$ids)) {
    return(bitir(pk_select_decide(NULL, character(0), library_index, cfg)))
  }

  # Tam-kütüphane recall'ı EKSİK olamaz: serileştirilemeyen tek bir satır bile
  # o sorguyu geri alınamaz biçimde görünmez yapar ve seçici kalan kümeden
  # güvenle yanlış bir sorgu çalıştırabilir.
  if (length(payload$skipped)) {
    return(bitir(.pk_select_decision(
      PK_SELECT_STATUS_LIBRARY_ERROR,
      message_tr = paste0(
        "Analiz kütüphanesi eksik/kararsız kimlik taşıdığı için sorgu seçimi ",
        "güvenle yapılamadı. Bu bir yapılandırma sorunudur; operatöre bildirin."
      ),
      disclosures = sprintf(
        "Geçiş A yüküne alınamayan sorgular: %s",
        paste(utils::head(payload$skipped, 10L), collapse = ", ")
      )
    )))
  }

  if (is.null(index)) index <- pk_retrieval_build_index(library)
  baglam <- pk_select_follow_up_context(
    chat_history, prior_query_id, payload$ids, cfg, user_prompt = user_prompt
  )
  yetenekler <- pk_select_capability_ids()

  gecis_a <- pk_select_run_pass_a(user_prompt, payload, baglam, cfg, session, llm_fn)
  if (!isTRUE(gecis_a$ok)) {
    return(bitir(
      .pk_select_pass_failure_decision(
        gecis_a$status, index, user_prompt, library_index, baglam
      ),
      character(0), gecis_a$status
    ))
  }

  aday_kimlikler <- pk_select_seed_candidates(gecis_a$ids, baglam$prior_query_id, cfg)
  adaylar <- lapply(aday_kimlikler, function(k) library_index[[k]])

  # Geçiş A uçarken gelen bir durdurma isteği, ikinci bir LLM çağrısını
  # başlatıp bir zaman aşımı süresi daha bloke etmemelidir.
  if (is.function(stop_check) && isTRUE(tryCatch(stop_check(), error = function(e) FALSE))) {
    return(bitir(
      .pk_select_decision(
        PK_SELECT_STATUS_CLARIFY,
        message_tr = "Analiz kullanıcı tarafından iptal edildi.",
        disclosures = "Geçiş B, iptal isteği nedeniyle başlatılmadı."
      ),
      aday_kimlikler, gecis_a$status
    ))
  }

  gecis_b <- pk_select_run_pass_b(
    user_prompt, adaylar, aday_kimlikler, baglam, cfg,
    session = session, llm_fn = llm_fn, capability_ids = yetenekler,
    library_index = library_index
  )

  if (!isTRUE(gecis_b$ok) &&
      gecis_b$status %in% c(PK_SELECT_STATUS_TIMEOUT, PK_SELECT_STATUS_LLM_UNAVAILABLE,
                            PK_SELECT_STATUS_AUTH_ERROR, PK_SELECT_STATUS_LIBRARY_ERROR)) {
    return(bitir(
      .pk_select_pass_failure_decision(
        gecis_b$status, index, user_prompt, library_index, baglam,
        restrict_ids = aday_kimlikler, error = gecis_b$error
      ),
      aday_kimlikler, gecis_a$status, gecis_b$status
    ))
  }

  uyum <- pk_retrieval_agreement(
    index, .pk_select_agreement_text(user_prompt, baglam), gecis_b$id, cfg$recall_n,
    library = library
  )

  karar <- pk_select_decide(
    gecis_b, aday_kimlikler, library_index, cfg,
    lexical = uyum, capability_ids = yetenekler
  )
  bitir(karar, aday_kimlikler, gecis_a$status, gecis_b$status)
}

#' Sözlüksel uyum metni — takip bağlamını İÇERİR
#'
#' Seçim bağlam farkındadır ama uyum sinyali yalın soruyu puanlıyordu.
#' "peki 2024 için?" gibi bir devam sorusunda doğru sorgu bu jenerik ifadede
#' ilk-N dışına düşüyor, cezayı yiyor ve geçerli bir devam `low_confidence`e
#' dönüyordu.
.pk_select_agreement_text <- function(user_prompt, context) {
  parcalar <- as.character(user_prompt)[1]
  for (tur in context$turns %||% list()) {
    if (identical(tur$role, "user")) parcalar <- c(parcalar, tur$content)
  }
  paste(parcalar[!is.na(parcalar)], collapse = " ")
}

#' Geçiş başarısızlığını DOĞRU teşhisle karara çevir
#'
#' `malformed` bir KESİNTİ DEĞİLDİR: servis cevap verdi ama sözleşmeyi ihlal
#' etti. Bozulma kipi mesajı ("servise ulaşılamıyor") bu durumda operatörü
#' yanlış yere bakmaya iter ve istem/ayrıştırıcı gerilemesini gizler.
.pk_select_pass_failure_decision <- function(status, index, prompt, library_index,
                                             context, restrict_ids = NULL,
                                             error = NA_character_) {
  if (identical(status, PK_SELECT_STATUS_LIBRARY_ERROR)) {
    return(.pk_select_decision(
      PK_SELECT_STATUS_LIBRARY_ERROR,
      message_tr = paste0(
        "Analiz kütüphanesi metadata'sı seçim istemine sığmadığı için sorgu ",
        "seçimi yapılamadı. Operatöre bildirin."
      ),
      disclosures = if (is.na(error %||% NA_character_)) character(0) else as.character(error)
    ))
  }

  karar <- pk_select_degraded_decision(
    status, index, prompt, library_index,
    prior_query_id = context$prior_query_id,
    restrict_ids = restrict_ids
  )

  if (identical(status, PK_SELECT_STATUS_MALFORMED)) {
    karar$disclosures <- c(
      "Yapay zekâ servisi yanıt verdi ancak seçim sözleşmesine uymayan bir çıktı üretti.",
      karar$disclosures
    )
  }

  karar
}

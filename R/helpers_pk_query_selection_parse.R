# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_selection_parse.R
# Açıklama: Faz 5 (§5.2) — LLM çıktısının KATI AYRIŞTIRILMASI.
#
# Bu dosya modelin metnine değil, YALNIZCA doğrulanmış yapıya güvenir:
#   * kimlikler KARARLI olmalıdır ve aday kümesinde bulunmalıdır (D13),
#   * güven değerleri gerçek JSON TAM SAYISI ve 0..100 aralığında olmalıdır,
#   * `alternates` SEÇİLMEYEN HER ADAYI kendi güveniyle taşımalıdır; aksi hâlde
#     ikinci-aday marjı ölçtüğünü sanan bir kapıya dönüşür (§5.2),
#   * `requirements` ve `missing_info` ZORUNLUDUR; eksik alan "iddia yok" ya da
#     "eksik bilgi yok" ANLAMINA GELMEZ.
# TASARIM KARARI — SESSİZ NORMALLEŞTİRME YERİNE ONARIM:
#   Sözleşme dışı her şekil `malformed` üretir ve orkestrasyon katmanı TEK bir
#   onarım denemesi yapar. Eskiden bu şekiller sessizce düzeltiliyordu; bir
#   model hatası böylece "geçerli seçim"e dönüşüyor ve marj/yetenek kapıları
#   ölçtüklerini sandıkları şeyi ölçmüyorlardı.
#
# Karar POLİTİKASI `helpers_pk_query_selection_decide.R` içindedir.
# Dosya SAFTIR: Shiny/reactive/DB/LLM/ağ bağımlılığı yoktur, worker güvenlidir.
# ==============================================================================

# Karar durumları. `auto` DIŞINDAKİ her durum "çalıştırma, sor/reddet"
# anlamındadır; yanlış finansal sorguyu çalıştırmaktansa hiçbir şey
# çalıştırmamak yeğdir (§5.2).
PK_SELECT_STATUS_AUTO               <- "auto"
PK_SELECT_STATUS_CLARIFY            <- "clarify"
PK_SELECT_STATUS_LOW_CONFIDENCE     <- "low_confidence"
PK_SELECT_STATUS_CLOSE_MARGIN       <- "close_margin"
PK_SELECT_STATUS_NO_RUNNER_UP       <- "no_runner_up"
PK_SELECT_STATUS_NO_CANDIDATES      <- "no_candidates"
PK_SELECT_STATUS_CAPABILITY_MISSING <- "capability_missing"
PK_SELECT_STATUS_UNKNOWN_CAPABILITY <- "unknown_capability"
PK_SELECT_STATUS_UNSUPPORTED_REQ    <- "unsupported_requirement"
PK_SELECT_STATUS_VALIDATOR_ERROR    <- "validator_error"
PK_SELECT_STATUS_MISSING_INFO       <- "missing_info"
PK_SELECT_STATUS_MALFORMED          <- "malformed"
PK_SELECT_STATUS_TIMEOUT            <- "timeout"
PK_SELECT_STATUS_LLM_UNAVAILABLE    <- "llm_unavailable"
PK_SELECT_STATUS_AUTH_ERROR         <- "auth_error"
PK_SELECT_STATUS_LIBRARY_ERROR      <- "library_error"
PK_SELECT_STATUS_CONFIG_ERROR       <- "config_error"
PK_SELECT_STATUS_INTERNAL_ERROR     <- "internal_error"
PK_SELECT_STATUS_DISABLED           <- "disabled"
# İPTAL, NETLEŞTİRME DEĞİLDİR. Kullanıcı Durdur'a bastığında seçim bir
# "netleştirme" kararı üretiyordu; `pk_select_query_v2()` her AUTO-dışı kararı
# RED sayıp `pk_select_forget_query_id()` çağırdığı için ÖNCEKİ başarılı sorgu
# tohumu siliniyor ve sonraki eliptik takip sorusu bağlamını kaybediyordu.
PK_SELECT_STATUS_CANCELLED          <- "cancelled"

#' Geçiş A çıktısını KATI biçimde ayrıştır (§5.2)
#'
#' @param expected_n Beklenen GEÇERLİ aday sayısı; genellikle
#'   `min(cfg$recall_n, length(library_ids))`. `NULL` ise sayı denetlenmez.
#'
#' İki kritik katılık:
#'   * `candidates` DÜZ bir dize dizisi olmalıdır. `unlist()` iç içe nesneleri
#'     de düzleştiriyordu: `[{"id":"q001","reason":"q004"}]` iki adaya
#'     dönüşüyor ve model yalnızca gerekçe olarak andığı `q004` Geçiş B'ye
#'     giriyordu.
#'   * BİLİNMEYEN tek bir kimlik bile cevabı bozuk yapar. Eskiden düşürülüyordu;
#'     modelin EN OLASI gördüğü (ama var olmayan) kimlik sessizce atılıp geri
#'     kalanlar "başarılı recall" sayılıyordu.
pk_select_parse_pass_a <- function(text, library_ids, expected_n = NULL) {
  hata <- function(mesaj) {
    list(ok = FALSE, ids = character(0), unknown = character(0), error = mesaj)
  }

  ayrisik <- pk_select_parse_json(text)
  if (is.null(ayrisik)) {
    return(hata(paste0(
      "Geçiş A çıktısı tek bir geçerli JSON nesnesi değil (sarmalayıcı metin, ",
      "tekrar eden anahtar ya da bozuk JSON)."
    )))
  }

  # KATI ÜST DÜZEY ANAHTAR KÜMESİ (Geçiş B ile AYNI kural): ayrıştırıcı yalnızca aday takma adlarını okuyup diğer alanları SESSİZCE yok sayıyordu, bu yüzden `{"candidates":["q001"],"selected_id":"q009"}` gibi ŞEMA KAYMASI taşıyan yanıt onarım yoluna gitmeden geçebiliyordu.
  a_izinli <- c("candidates", "ids", "candidate_ids")
  a_fazla <- setdiff(names(ayrisik), a_izinli)
  if (length(a_fazla)) {
    return(hata(sprintf("Geçiş A çıktısı sözleşme dışı alan içeriyor: %s",
                        paste(sort(a_fazla), collapse = ", "))))
  }
  alan <- intersect(a_izinli, names(ayrisik))
  if (!length(alan)) {
    return(hata("Geçiş A çıktısında 'candidates' alanı yok."))
  }

  dizi <- pk_select_string_array(ayrisik[[alan[1]]])
  if (!isTRUE(dizi$ok)) {
    return(hata("'candidates' alanı DÜZ bir kararlı kimlik dizisi olmalıdır."))
  }

  # ÇELİŞKİLİ TAKMA ALANLAR REDDEDİLİR: birden fazla ad VARSA eskiden SESSİZCE
  # ilki kullanılıyordu (`{"candidates":["q001"],"ids":["q002"]}` gibi İKİ
  # FARKLI aday kümesi otomatik seçime ilerleyebiliyordu); sözleşme ihlali
  # onarım yoluna gönderilir.
  if (length(alan) > 1L) {
    for (ek in alan[-1L]) {
      ek_dizi <- pk_select_string_array(ayrisik[[ek]])
      if (!isTRUE(ek_dizi$ok) || !identical(ek_dizi$values, dizi$values)) {
        return(hata(sprintf(
          "Geçiş A çıktısı ÇELİŞKİLİ aday alanları içeriyor: %s",
          paste(alan, collapse = ", ")
        )))
      }
    }
  }

  ham <- dizi$values
  if (anyDuplicated(ham)) {
    return(hata(sprintf(
      "'candidates' içinde tekrar eden kimlik var: %s",
      paste(unique(ham[duplicated(ham)]), collapse = ", ")
    )))
  }

  bilinmeyen <- setdiff(ham, library_ids)
  if (length(bilinmeyen)) {
    return(list(ok = FALSE, ids = character(0), unknown = bilinmeyen, error = sprintf(
      "'candidates' kütüphanede olmayan kimlik içeriyor: %s",
      paste(bilinmeyen, collapse = ", ")
    )))
  }

  if (!length(ham)) return(hata("Geçiş A hiç aday kimliği döndürmedi."))

  if (!is.null(expected_n)) {
    beklenen <- as.integer(expected_n)[1]
    if (!is.na(beklenen) && length(ham) != beklenen) {
      return(hata(sprintf(
        "Geçiş A tam olarak %d aday kimliği döndürmelidir; %d döndürdü.",
        beklenen, length(ham)
      )))
    }
  }

  list(ok = TRUE, ids = ham, unknown = character(0), error = NA_character_)
}

.pk_select_pass_b_empty <- function(error = NA_character_, id = NA_character_) {
  list(ok = FALSE, id = id, confidence = NA_integer_,
       reason = NA_character_, alternates = list(),
       requirements = NULL, missing_info = NA_character_,
       error = error)
}

#' Geçiş B `alternates` dizisini KATI biçimde ayrıştır
#'
#' `alternates` MARJ KAPISININ tek veri kaynağıdır; bu yüzden en katı alandır:
#'   * her öğe skaler `id` + skaler tam sayı `confidence` taşımalıdır,
#'   * aday kümesinde OLMAYAN bir kimlik cevabı bozar (eskiden düşürülüyordu;
#'     model "var olmayan q999 daha iyi" derken q1 otomatik çalışabiliyordu),
#'   * tekrar eden ya da seçilen kimliği tekrarlayan bir öğe cevabı bozar
#'     (çelişkili iki skor sessizce ilkine indirgenip sahte marj üretiyordu),
#'   * SEÇİLMEYEN HER ADAY yer almalıdır (eksik bırakılan aday, ölçülmemiş bir
#'     rakip demektir).
.pk_select_parse_alternates <- function(raw, selected_id, candidate_ids) {
  if (is.null(raw)) {
    return(list(ok = FALSE, values = list(),
                error = "Geçiş B 'alternates' alanı zorunludur."))
  }
  # NESNE BİÇİMİ DE REDDEDİLİR: `simplifyVector = FALSE` JSON DİZİSİ için ADSIZ,
  # JSON NESNESİ için ADLI liste döndürür ve `is.list()` ikisinde de TRUE'dur.
  # Nesne biçimli yanıt eskiden geçerli sayılıp marj kapısı sözleşme dışı bir
  # şekle göre ölçülüyordu.
  if (!is.list(raw) || (length(raw) > 0L && !is.null(names(raw)))) {
    return(list(ok = FALSE, values = list(),
                error = "Geçiş B 'alternates' alanı bir dizi olmalıdır."))
  }

  alternatifler <- list()
  gorulen <- character(0)

  for (girdi in raw) {
    if (!is.list(girdi)) {
      return(list(ok = FALSE, values = list(),
                  error = "'alternates' ögeleri id ve confidence taşıyan nesneler olmalıdır."))
    }

    # KESİN ALAN ERİŞİMİ: `$` benzersiz ÖNEKLERİ de kabul eder.
    #
    # `{"ids":"q002","confidence_pct":60}` gibi sözleşme DIŞI bir öge
    # `girdi$id`/`girdi$confidence` ile geçerli sayılıyor, `malformed`
    # işaretlenmiyor ve marj kapısı sözleşme dışı alanlardan gelen değerlerle
    # hesaplanıyordu. Anahtar kümesi de `id`/`confidence` ile sınırlandırılır.
    anahtarlar <- names(girdi) %||% character(0)
    if (!all(anahtarlar %in% c("id", "confidence"))) {
      return(list(ok = FALSE, values = list(), error = paste0(
        "'alternates' ögesi yalnızca 'id' ve 'confidence' alanlarını taşıyabilir; ",
        "sözleşme dışı alan: ",
        paste(setdiff(anahtarlar, c("id", "confidence")), collapse = ", ")
      )))
    }

    alt_id <- pk_select_scalar_string(girdi[["id"]])
    if (is.na(alt_id)) {
      return(list(ok = FALSE, values = list(),
                  error = "'alternates[*].id' tek bir kararlı kimlik olmalıdır."))
    }

    alt_guven <- pk_select_scalar_integer(girdi[["confidence"]], min = 0L, max = 100L)
    if (is.na(alt_guven)) {
      return(list(ok = FALSE, values = list(), error = sprintf(
        "'alternates' ögesi '%s' için 0-100 arası TAM SAYI confidence taşımıyor.", alt_id
      )))
    }

    if (identical(alt_id, selected_id)) {
      return(list(ok = FALSE, values = list(), error = sprintf(
        "'alternates' seçilen kimliği (%s) tekrar ediyor.", alt_id
      )))
    }
    if (alt_id %in% gorulen) {
      return(list(ok = FALSE, values = list(), error = sprintf(
        "'alternates' içinde tekrar eden kimlik: %s", alt_id
      )))
    }
    if (!alt_id %in% candidate_ids) {
      return(list(ok = FALSE, values = list(), error = sprintf(
        "'alternates' aday kümesinde olmayan bir kimlik içeriyor: %s", alt_id
      )))
    }

    gorulen <- c(gorulen, alt_id)
    alternatifler[[length(alternatifler) + 1L]] <- list(id = alt_id, confidence = alt_guven)
  }

  eksik <- setdiff(setdiff(candidate_ids, selected_id), gorulen)
  if (length(eksik)) {
    return(list(ok = FALSE, values = list(), error = sprintf(
      "'alternates' şu adayların güvenini vermiyor: %s", paste(eksik, collapse = ", ")
    )))
  }

  # Kararlı sıralama: azalan güven, eşitlikte C-yerel kimlik sırası (E8).
  if (length(alternatifler) > 1L) {
    guvenler <- vapply(alternatifler, function(a) a$confidence, integer(1))
    kimlikler <- vapply(alternatifler, function(a) a$id, character(1))
    alternatifler <- alternatifler[order(-guvenler, kimlikler, method = "radix")]
  }

  list(ok = TRUE, values = alternatifler, error = NA_character_)
}

#' Geçiş B çıktısını KATI biçimde ayrıştır (§5.2)
pk_select_parse_pass_b <- function(text, candidate_ids) {
  ayrisik <- pk_select_parse_json(text)
  if (is.null(ayrisik)) {
    return(.pk_select_pass_b_empty(paste0(
      "Geçiş B çıktısı tek bir geçerli JSON nesnesi değil (sarmalayıcı metin, ",
      "tekrar eden anahtar ya da bozuk JSON)."
    )))
  }

  # KATI ÜST DÜZEY ANAHTAR KÜMESİ: ayrıştırıcı eskiden yalnızca beklenen adları
  # OKUYUP diğer alanları SESSİZCE yok sayıyordu, bu da şema kaymasında
  # ÇELİŞKİLİ bir seçimin otomatik çalışmasına yol açabiliyordu; sözleşme dışı
  # alan taşıyan çıktı onarım yoluna gönderilir.
  izinli_alanlar <- c("id", "confidence", "reason", "alternates",
                      "requirements", "missing_info")
  fazla <- setdiff(names(ayrisik), izinli_alanlar)
  if (length(fazla)) {
    return(.pk_select_pass_b_empty(sprintf(
      "Geçiş B çıktısı sözleşme dışı alan içeriyor: %s",
      paste(sort(fazla), collapse = ", ")
    )))
  }

  kimlik <- pk_select_scalar_string(ayrisik$id)
  if (is.na(kimlik)) {
    return(.pk_select_pass_b_empty(
      "Geçiş B çıktısında tek bir kararlı 'id' alanı yok."
    ))
  }
  if (!kimlik %in% candidate_ids) {
    return(.pk_select_pass_b_empty(sprintf(
      "Geçiş B aday kümesinde olmayan bir kimlik döndürdü: %s", kimlik
    )))
  }

  guven <- pk_select_scalar_integer(ayrisik$confidence, min = 0L, max = 100L)
  if (is.na(guven)) {
    return(.pk_select_pass_b_empty(
      "Geçiş B 'confidence' değeri 0-100 arası TAM SAYI değil.", id = kimlik
    ))
  }

  gerekce <- pk_select_scalar_string(ayrisik$reason)
  if (is.na(gerekce)) {
    return(.pk_select_pass_b_empty(
      "Geçiş B 'reason' alanı boş olmayan tek bir metin olmalıdır.", id = kimlik
    ))
  }

  alternatifler <- .pk_select_parse_alternates(ayrisik$alternates, kimlik, candidate_ids)
  if (!isTRUE(alternatifler$ok)) {
    return(.pk_select_pass_b_empty(alternatifler$error, id = kimlik))
  }

  gereksinim <- pk_select_normalize_requirements(ayrisik$requirements)
  if (!isTRUE(gereksinim$ok)) {
    return(.pk_select_pass_b_empty(gereksinim$error, id = kimlik))
  }

  # "Alan yok" ile "acikca null" AYNI SEY DEGILDIR: kirpilmis bir cevabin
  # eksik `missing_info` alani, eksik bilgi kapisini sessizce atlatiyordu.
  eksik <- pk_select_nullable_text(ayrisik, "missing_info")
  if (identical(eksik$state, "absent")) {
    return(.pk_select_pass_b_empty(
      "Geçiş B 'missing_info' alanı zorunludur (eksik bilgi yoksa null yaz).",
      id = kimlik
    ))
  }
  if (identical(eksik$state, "invalid")) {
    return(.pk_select_pass_b_empty(
      "Geçiş B 'missing_info' alanı metin ya da null olmalıdır.", id = kimlik
    ))
  }

  list(
    ok = TRUE,
    id = kimlik,
    confidence = guven,
    reason = gerekce,
    alternates = alternatifler$values,
    requirements = gereksinim$value,
    missing_info = eksik$value,
    error = NA_character_
  )
}

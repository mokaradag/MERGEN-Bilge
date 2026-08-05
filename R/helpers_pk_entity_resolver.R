# ==============================================================================
# Dosya Yolu: R/helpers_pk_entity_resolver.R
# Açıklama: Faz 4 — varlık çözümleme karar politikası (master plan §5.4).
#
#           Puanlama GÜVENLİK MEKANİZMASI DEĞİLDİR; kuralların SIRASI güvenlik
#           mekanizmasıdır. Kurallar sırayla denenir ve İLK eşleşen kazanır:
#
#             1  Kesin kod/kimlik eşleşmesi ............ otomatik filtrele
#             2  Tepe >= MIN ve #2'ye fark < MARGIN .... SOR (çipler)
#             3  İfade çoğul ve >= 2 aday >= MULTI ..... birleştirmeden ÖNCE SOR
#             4  Tekil, tepe >= AUTO, fark net ......... otomatik filtrele
#             5  MIN <= tepe < AUTO, fark net .......... ÖN SEÇİMLİ onay iste
#             6  Tepe < MIN ve varlık sorunun ÖZNESİ ... ANALİZ ETME
#             7  Tepe < MIN ve varlık ikincil daraltma . filtresiz + AÇIK uyarı
#
#           Kural 2'nin kural 3'ten, kural 3'ün kural 4'ten önce gelmesi
#           bilinçlidir: 92/81/76 puanlı çoğul bir istek, 92 otomatik eşiği
#           geçtiği için sessizce tek adaya ÇÖKEMEZ.
#
#           Her dal ÇÖZÜLMÜŞ yapılandırmayı okur. Karar kodunda hiçbir literal
#           40/85/70/10/5 değeri bulunmaz (§5.4 açık kuralı).
#
# Dosya saftır: Shiny/reactive/DB/ağ bağımlılığı yoktur, worker güvenlidir.
# ==============================================================================

# Eşik ilişkileri geçersizse otomatik çözümleme TAMAMEN kapatılır. Kısmen
# sıralı dalları değerlendirmek, operatörün sandığından farklı bir eşikle
# otomatik filtreleme yapabilir; bu yüzden kapalı başarısızlık seçilmiştir.
.PK_RESOLVE_KEYS <- c(
  "MERGEN_PK_RESOLVE_MIN_SCORE",
  "MERGEN_PK_RESOLVE_MULTI_SCORE",
  "MERGEN_PK_RESOLVE_AUTO_SCORE",
  "MERGEN_PK_RESOLVE_AMBIGUITY_MARGIN",
  "MERGEN_PK_RESOLVE_MAX_CANDIDATES"
)

.pk_resolve_is_score <- function(x) {
  is.numeric(x) && length(x) == 1L && !is.na(x) && is.finite(x) &&
    x >= 0 && x <= 100
}

#' Çözümleme eşiklerini çöz VE ilişkilerini doğrula (§5.4)
#'
#' Tek tek anahtarların aralığı `pk_config_spec` tarafından zaten korunur;
#' burada korunan şey anahtarlar ARASINDAKİ ilişkidir:
#' `MIN <= MULTI <= AUTO`. Bu ilişki tek anahtar doğrulamasıyla yakalanamaz —
#' örneğin `MIN_SCORE=90` ile `AUTO_SCORE=85` tek tek geçerli, birlikte
#' tutarsızdır.
#'
#' @return `valid`, `errors` ve çözülmüş beş değer. `valid = FALSE` ise çağıran
#'   otomatik çözümlemeyi DEVRE DIŞI bırakmalı ve operatöre açık hata
#'   göstermelidir.
pk_resolve_thresholds <- function(query_meta = NULL) {
  degerler <- list()
  hatalar <- character(0)

  for (anahtar in .PK_RESOLVE_KEYS) {
    degerler[[anahtar]] <- tryCatch(
      pk_config_resolve(anahtar, query_meta = query_meta),
      error = function(e) NULL
    )
  }

  min_score  <- degerler[["MERGEN_PK_RESOLVE_MIN_SCORE"]]
  multi_score <- degerler[["MERGEN_PK_RESOLVE_MULTI_SCORE"]]
  auto_score <- degerler[["MERGEN_PK_RESOLVE_AUTO_SCORE"]]
  margin     <- degerler[["MERGEN_PK_RESOLVE_AMBIGUITY_MARGIN"]]
  max_cand   <- degerler[["MERGEN_PK_RESOLVE_MAX_CANDIDATES"]]

  for (ad in c("MERGEN_PK_RESOLVE_MIN_SCORE", "MERGEN_PK_RESOLVE_MULTI_SCORE",
               "MERGEN_PK_RESOLVE_AUTO_SCORE", "MERGEN_PK_RESOLVE_AMBIGUITY_MARGIN")) {
    if (!.pk_resolve_is_score(degerler[[ad]])) {
      hatalar <- c(hatalar, sprintf(
        "%s sonlu ve 0..100 araliginda olmalidir.", ad
      ))
    }
  }

  if (!is.numeric(max_cand) || length(max_cand) != 1L || is.na(max_cand) ||
      !is.finite(max_cand) || max_cand < 1 || max_cand > 5) {
    hatalar <- c(hatalar, "MERGEN_PK_RESOLVE_MAX_CANDIDATES 1..5 araliginda olmalidir.")
  }

  if (!length(hatalar) && !(min_score <= multi_score && multi_score <= auto_score)) {
    hatalar <- c(hatalar, sprintf(
      paste0(
        "Esik iliskisi gecersiz: MIN_SCORE (%s) <= MULTI_SCORE (%s) <= ",
        "AUTO_SCORE (%s) olmalidir."
      ),
      format(min_score), format(multi_score), format(auto_score)
    ))
  }

  list(
    valid = !length(hatalar),
    errors = hatalar,
    min_score = min_score,
    multi_score = multi_score,
    auto_score = auto_score,
    ambiguity_margin = margin,
    max_candidates = if (is.numeric(max_cand) && length(max_cand) == 1L &&
                         !is.na(max_cand)) as.integer(max_cand) else NA_integer_
  )
}

#' Güçlü/eşit aday kümesinden netleştirme çipleri üret (§5.4)
#'
#' Taşma kuralı: çipler oluşturulmadan ÖNCE kümenin TAMAMI sayılır. Küme sınırı
#' aşarsa yalnızca ilk N gösterilir, "N aday daha var" uyarısı eklenir ve
#' "Tümü" seçeneği KAPATILIR — gizli adaylar asla "Tümü" arkasına saklanamaz.
pk_entity_clarification <- function(strong, max_candidates, preselect = NULL) {
  toplam <- length(strong)
  sinir <- if (is.na(max_candidates)) toplam else as.integer(max_candidates)

  tasma <- max(0L, toplam - sinir)
  gosterilen <- if (tasma > 0L) strong[seq_len(sinir)] else strong

  cipler <- lapply(gosterilen, function(kayit) {
    list(
      label = kayit$value,
      value = kayit$value,
      score = kayit$score,
      tier = kayit$tier,
      preselected = !is.null(preselect) && identical(kayit$value, preselect)
    )
  })

  list(
    chips = cipler,
    total = toplam,
    shown = length(cipler),
    overflow_count = tasma,
    # "Tümü" YALNIZCA tüm küme görünürken sunulur.
    offer_all = tasma == 0L && toplam > 1L,
    overflow_note = if (tasma > 0L) {
      sprintf("%d aday daha var. Lutfen sorunuzu daraltin veya secim yapin.", tasma)
    } else {
      NA_character_
    }
  )
}

# Karar kaydını tek yerden kurar; alan seti her dalda AYNI kalır.
.pk_entity_decision <- function(decision, rule = NA_integer_, values = character(0),
                                message_tr = NA_character_, scored = NULL,
                                clarification = NULL, thresholds = NULL, ...) {
  out <- list(
    decision = decision,
    rule = as.integer(rule),
    values = as.character(values),
    message_tr = message_tr,
    candidates = if (is.null(scored)) list() else scored$matches,
    top_score = if (is.null(scored) || !length(scored$matches)) 0L else scored$matches[[1]]$score,
    alias_target_missing = !is.null(scored) && isTRUE(scored$alias_target_missing),
    chips = if (is.null(clarification)) list() else clarification$chips,
    offer_all = !is.null(clarification) && isTRUE(clarification$offer_all),
    overflow_count = if (is.null(clarification)) 0L else clarification$overflow_count,
    total_strong = if (is.null(clarification)) 0L else clarification$total,
    overflow_note = if (is.null(clarification)) NA_character_ else clarification$overflow_note,
    thresholds = thresholds,
    inherited = FALSE
  )

  ek <- list(...)
  for (ad in names(ek)) out[[ad]] <- ek[[ad]]
  out
}

#' Kullanıcı ifadesini kapalı sözlüğe karşı çöz (§5.4 karar tablosu)
#'
#' @param phrase Kullanıcının yazdığı ifade.
#' @param candidates Sütunun GERÇEK ayrık değerleri (kapalı sözlük).
#' @param aliases Doğrulanmış alias haritası (katlanmış anahtar -> kanonik değer).
#' @param role Sütun rolü (`pk_meta_match_mode`/metadata'dan). "id" ise bulanık
#'   eşleştirme YAPILMAZ.
#' @param match_mode Sütun eşleştirme kipi. "exact" ise bulanık eşleştirme
#'   YAPILMAZ.
#' @param entity_role "subject" (sorunun öznesi) veya "refinement" (ikincil
#'   daraltma). Kural 6 ile 7 arasındaki farkı BU belirler.
#'
#' @return `.pk_entity_decision()` biçiminde karar kaydı.
pk_entity_resolve <- function(phrase, candidates, aliases = NULL,
                              role = NULL, match_mode = NULL,
                              entity_role = "subject",
                              query_meta = NULL, thresholds = NULL) {
  esikler <- if (is.null(thresholds)) pk_resolve_thresholds(query_meta) else thresholds

  # --- Kapalı başarısızlık: geçersiz eşik ilişkisi -------------------------
  if (!isTRUE(esikler$valid)) {
    return(.pk_entity_decision(
      "config_error",
      message_tr = paste0(
        "Varlik cozumleme yapilandirmasi gecersiz oldugu icin otomatik ",
        "cozumleme devre disi birakildi. Operatore bildirin: ",
        paste(esikler$errors, collapse = " ")
      ),
      thresholds = esikler
    ))
  }

  exact_only <- identical(role, "id") || identical(match_mode, "exact")

  puanlar <- pk_entity_score_candidates(
    phrase = phrase,
    candidates = candidates,
    aliases = aliases,
    exact_only = exact_only
  )

  # --- Geçersiz girdi: boş ifade sıfır puanlı kısayol DEĞİLDİR -------------
  if (!isTRUE(puanlar$valid)) {
    return(.pk_entity_decision(
      "invalid_input",
      message_tr = if (identical(puanlar$reason, "bos_ifade")) {
        "Cozumlenecek bir varlik ifadesi verilmedi."
      } else {
        "Bu sutun icin karsilastirilacak deger bulunamadi."
      },
      thresholds = esikler,
      reason = puanlar$reason
    ))
  }

  eslesmeler <- puanlar$matches
  tepe <- if (length(eslesmeler)) eslesmeler[[1]]$score else 0L
  ikinci <- if (length(eslesmeler) >= 2L) eslesmeler[[2]]$score else NA_integer_
  fark <- if (is.na(ikinci)) Inf else tepe - ikinci
  cogul <- pk_entity_phrase_is_plural(phrase)

  # --- Kural 1: kesin kod/kimlik eşleşmesi --------------------------------
  if (exact_only) {
    if (length(eslesmeler) == 1L) {
      return(.pk_entity_decision(
        "auto", rule = 1L, values = eslesmeler[[1]]$value,
        scored = puanlar, thresholds = esikler, plural = cogul, margin = fark
      ))
    }
    if (!length(eslesmeler)) {
      return(.pk_entity_decision(
        "unresolved", rule = 6L,
        message_tr = "Belirtilen kod/kimlik degeri bu sutunda bulunamadi.",
        scored = puanlar, thresholds = esikler, plural = cogul, margin = fark
      ))
    }
    # Birden çok kesin eşleşme yalnızca sözlük çakışmasında olur; sessizce
    # birini seçmek yerine netleştirilir.
    netlestirme <- pk_entity_clarification(eslesmeler, esikler$max_candidates)
    return(.pk_entity_decision(
      "clarify", rule = 2L,
      message_tr = "Birden fazla kesin eslesme bulundu. Hangisini kastettiniz?",
      scored = puanlar, clarification = netlestirme, thresholds = esikler,
      plural = cogul, margin = fark
    ))
  }

  # --- Kural 2: belirsizlik (kural 3 ve 4'ten ÖNCE) ------------------------
  if (tepe >= esikler$min_score && fark < esikler$ambiguity_margin) {
    guclu <- Filter(
      function(k) k$score >= esikler$min_score &&
        (tepe - k$score) < esikler$ambiguity_margin,
      eslesmeler
    )
    netlestirme <- pk_entity_clarification(guclu, esikler$max_candidates)
    return(.pk_entity_decision(
      "clarify", rule = 2L,
      message_tr = "Birden fazla yakin aday var. Hangisini kastettiniz?",
      scored = puanlar, clarification = netlestirme, thresholds = esikler,
      plural = cogul, margin = fark
    ))
  }

  # --- Kural 3: çoğul çoklu aday (kural 4'ten ÖNCE) ------------------------
  if (isTRUE(cogul)) {
    guclu <- Filter(function(k) k$score >= esikler$multi_score, eslesmeler)
    if (length(guclu) >= 2L) {
      netlestirme <- pk_entity_clarification(guclu, esikler$max_candidates)
      return(.pk_entity_decision(
        "clarify", rule = 3L,
        message_tr = "Coklu bir istek algilandi. Hangi degerleri dahil edelim?",
        scored = puanlar, clarification = netlestirme, thresholds = esikler,
        plural = cogul, margin = fark
      ))
    }
  }

  # --- Kural 4: tekil otomatik kabul --------------------------------------
  if (tepe >= esikler$auto_score && fark >= esikler$ambiguity_margin) {
    return(.pk_entity_decision(
      "auto", rule = 4L, values = eslesmeler[[1]]$value,
      scored = puanlar, thresholds = esikler, plural = cogul, margin = fark
    ))
  }

  # --- Kural 5: ön seçimli onay -------------------------------------------
  if (tepe >= esikler$min_score && tepe < esikler$auto_score &&
      fark >= esikler$ambiguity_margin) {
    aday <- eslesmeler[[1]]
    netlestirme <- pk_entity_clarification(
      list(aday), esikler$max_candidates, preselect = aday$value
    )
    return(.pk_entity_decision(
      "confirm", rule = 5L,
      message_tr = sprintf("Sunu mu kastettiniz: %s", aday$value),
      scored = puanlar, clarification = netlestirme, thresholds = esikler,
      plural = cogul, margin = fark
    ))
  }

  # --- Kural 6/7: eşik altı ------------------------------------------------
  en_yakin <- if (length(eslesmeler)) {
    utils::head(eslesmeler, if (is.na(esikler$max_candidates)) 3L else esikler$max_candidates)
  } else {
    list()
  }
  netlestirme <- pk_entity_clarification(en_yakin, esikler$max_candidates)

  if (identical(entity_role, "refinement")) {
    return(.pk_entity_decision(
      "unfiltered", rule = 7L,
      message_tr = paste0(
        "Ikincil daraltma ifadesi cozumlenemedi; analiz BU DARALTMA ",
        "UYGULANMADAN yapildi."
      ),
      scored = puanlar, clarification = netlestirme, thresholds = esikler,
      plural = cogul, margin = fark, disclose = TRUE
    ))
  }

  .pk_entity_decision(
    "unresolved", rule = 6L,
    message_tr = paste0(
      "Sorunun oznesi olan deger cozumlenemedi; yaniltici olmamak icin analiz ",
      "yapilmadi. En yakin adaylardan birini secebilirsiniz."
    ),
    scored = puanlar, clarification = netlestirme, thresholds = esikler,
    plural = cogul, margin = fark
  )
}

# ==============================================================================
# Dosya Yolu: R/helpers_pk_entity_resolver.R
# Açıklama: Faz 4 — varlık çözümleme karar politikası (master plan §5.4).
#
#           Puanlama GÜVENLİK MEKANİZMASI DEĞİLDİR; kuralların SIRASI güvenlik
#           mekanizmasıdır. Kurallar sırayla denenir ve İLK eşleşen kazanır:
#
#             1  Kesin kod/kimlik eşleşmesi ............ otomatik filtrele
#             2  Tepe >= MIN ve #2'ye fark < MARGIN .... SOR (çipler)
#             3  İfade çoğul ......................... birleştirmeden ÖNCE SOR
#             4  Tekil, tepe >= AUTO, fark net ......... otomatik filtrele
#             5  MIN <= tepe, fark net ................. ÖN SEÇİMLİ onay iste
#             6  Tepe < MIN ve varlık sorunun ÖZNESİ ... ANALİZ ETME
#             7  Tepe < MIN ve varlık ikincil daraltma . filtresiz + AÇIK uyarı
#
#           Kural 2'nin kural 3'ten, kural 3'ün kural 4'ten önce gelmesi
#           bilinçlidir: 92/81/76 puanlı çoğul bir istek, 92 otomatik eşiği
#           geçtiği için sessizce tek adaya ÇÖKEMEZ.
#
#           PUAN TEK BAŞINA YETMEZ. Kayıplı/sezgisel bir adıma bağlı her
#           eşleşme puanlayıcıda `low_confidence` bayrağı taşır (ASCII
#           katlaması, noktalama sadeleştirmesi, sözcük sırası değişimi, tek
#           genel belirteç, sözlükle doğrulanmamış gövde soyma, ifadeden
#           çıkarılmış anım). Kural 4 bayraklı eşleşmeyi ASLA otomatik kabul
#           etmez; onu kural 5'e (onay) düşürür.
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

# Metadata `match` kipleri (PK_META_MATCH_MODES ile aynı küme). Bulanık
# çözümleme YALNIZCA "resolve" kipine aittir.
.PK_RESOLVE_MODE_EXACT   <- "exact"
.PK_RESOLVE_MODE_RESOLVE <- "resolve"
.PK_RESOLVE_MODE_CONTAIN <- "contains"
.PK_RESOLVE_MODE_NONE    <- "none"

.pk_resolve_is_score <- function(x) {
  is.numeric(x) && length(x) == 1L && !is.na(x) && is.finite(x) &&
    identical(as.numeric(x), trunc(as.numeric(x))) && x >= 0 && x <= 100
}

#' Çözümleme eşiklerini çöz VE ilişkilerini doğrula (§5.4)
#'
#' Tek tek anahtarların aralığı `pk_config_spec` tarafından zaten korunur;
#' burada korunan iki şey vardır:
#'
#'   1) Anahtarlar ARASINDAKİ ilişki: `MIN <= MULTI <= AUTO`. Bu ilişki tek
#'      anahtar doğrulamasıyla yakalanamaz — `MIN_SCORE=90` ile
#'      `AUTO_SCORE=85` tek tek geçerli, birlikte tutarsızdır.
#'   2) GEÇERSİZ KAYNAK. `pk_config_resolve()` bozuk bir basamağı sessizce
#'      atlar; eşiklerde bu yanlıştır. `MERGEN_PK_RESOLVE_AUTO_SCORE=bogus`
#'      varsayılana düşerse operatör eşiği değiştirdiğini sanır. §5.4 bunun
#'      yerine otomatik çözümlemenin DEVRE DIŞI kalmasını ister.
#'
#' @return `valid`, `errors` ve çözülmüş beş değer. `valid = FALSE` ise çağıran
#'   otomatik çözümlemeyi DEVRE DIŞI bırakmalı ve operatöre açık hata
#'   göstermelidir.
pk_resolve_thresholds <- function(query_meta = NULL) {
  degerler <- list()
  hatalar <- character(0)

  for (anahtar in .PK_RESOLVE_KEYS) {
    sonda <- tryCatch(
      pk_config_probe(anahtar, query_meta = query_meta),
      error = function(e) NULL
    )

    if (is.null(sonda)) {
      hatalar <- c(hatalar, sprintf("%s çözümlenemedi.", anahtar))
      degerler[[anahtar]] <- NULL
      next
    }

    if (length(sonda$invalid_sources)) {
      hatalar <- c(hatalar, sprintf(
        "%s geçersiz bir değer taşıyor (kaynak: %s); sessizce varsayılana düşülmedi.",
        anahtar, paste(sonda$invalid_sources, collapse = ", ")
      ))
    }

    degerler[[anahtar]] <- sonda$value
  }

  esik <- list(
    min_score = degerler[["MERGEN_PK_RESOLVE_MIN_SCORE"]],
    multi_score = degerler[["MERGEN_PK_RESOLVE_MULTI_SCORE"]],
    auto_score = degerler[["MERGEN_PK_RESOLVE_AUTO_SCORE"]],
    ambiguity_margin = degerler[["MERGEN_PK_RESOLVE_AMBIGUITY_MARGIN"]],
    max_candidates = degerler[["MERGEN_PK_RESOLVE_MAX_CANDIDATES"]]
  )

  dogrulanmis <- pk_resolve_normalize_thresholds(esik)
  dogrulanmis$errors <- unique(c(hatalar, dogrulanmis$errors))
  dogrulanmis$valid <- !length(dogrulanmis$errors)
  dogrulanmis
}

#' Dışarıdan verilen eşik nesnesini NORMALLEŞTİR ve DOĞRULA (§5.4)
#'
#' `pk_entity_resolve()` isteğe bağlı bir `thresholds` argümanı kabul eder.
#' Çağıranın verdiği `valid = TRUE` bayrağına GÜVENİLMEZ: alanların varlığı,
#' tipi, aralığı, tam sayılığı ve ilişkileri burada yeniden denetlenir.
#' Aksi hâlde `min_score = 100` ile `auto_score = 0` taşıyan bir nesne
#' 90 puanlık bir eşleşmeyi beyan edilen asgarinin ALTINDA otomatik
#' filtreleyebilirdi.
pk_resolve_normalize_thresholds <- function(x) {
  hatalar <- character(0)
  al <- function(ad) if (is.list(x) && !is.null(x[[ad]])) x[[ad]] else NULL

  min_score <- al("min_score")
  multi_score <- al("multi_score")
  auto_score <- al("auto_score")
  margin <- al("ambiguity_margin")
  max_cand <- al("max_candidates")

  alanlar <- list(
    min_score = min_score, multi_score = multi_score,
    auto_score = auto_score, ambiguity_margin = margin
  )
  for (ad in names(alanlar)) {
    if (!.pk_resolve_is_score(alanlar[[ad]])) {
      hatalar <- c(hatalar, sprintf(
        "%s sonlu bir tam sayı ve 0..100 aralığında olmalıdır.", ad
      ))
    }
  }

  if (!is.numeric(max_cand) || length(max_cand) != 1L || is.na(max_cand) ||
      !is.finite(max_cand) ||
      !identical(as.numeric(max_cand), trunc(as.numeric(max_cand))) ||
      max_cand < 1 || max_cand > 5) {
    hatalar <- c(hatalar, "max_candidates 1..5 aralığında bir tam sayı olmalıdır.")
  }

  if (!length(hatalar) && !(min_score <= multi_score && multi_score <= auto_score)) {
    hatalar <- c(hatalar, sprintf(
      "Eşik ilişkisi geçersiz: MIN_SCORE (%s) <= MULTI_SCORE (%s) <= AUTO_SCORE (%s) olmalıdır.",
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
#'
#' @param allow_all "Tümü" seçeneğine İZİN VERİLİYOR mu. Kural 6/7'nin en
#'   yakın aday önerileri asgari puanı GEÇEMEMİŞ tahminlerdir; bunların
#'   toplu uygulanması teklif EDİLMEZ.
pk_entity_clarification <- function(strong, max_candidates, preselect = NULL,
                                    allow_all = TRUE) {
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
      low_confidence = kayit$low_confidence,
      preselected = !is.null(preselect) && identical(kayit$value, preselect)
    )
  })

  list(
    chips = cipler,
    total = toplam,
    shown = length(cipler),
    overflow_count = tasma,
    # "Tümü" YALNIZCA tüm küme görünürken VE toplu uygulama meşruyken sunulur.
    offer_all = isTRUE(allow_all) && tasma == 0L && toplam > 1L,
    overflow_note = if (tasma > 0L) {
      sprintf("%d aday daha var. Lütfen sorunuzu daraltın veya seçim yapın.", tasma)
    } else {
      NA_character_
    }
  )
}

# Karar kaydını tek yerden kurar; alan seti her dalda AYNI kalır.
#
# `candidates` alanı SINIRLIDIR: `proje` gibi genel bir belirteç binlerce
# kapalı sözlük değeriyle eşleşebilir ve tüm kümeyi karara kopyalamak, arayüz
# en fazla beş seçenek gösterirken oturum yükünü şişirir. Toplam sayı
# `candidate_count` alanında korunur.
.PK_ENTITY_DIAGNOSTIC_CANDIDATES <- 5L

.pk_entity_decision <- function(decision, rule = NA_integer_, values = character(0),
                                message_tr = NA_character_, scored = NULL,
                                clarification = NULL, thresholds = NULL, ...) {
  eslesmeler <- if (is.null(scored)) list() else scored$matches
  sinir <- .PK_ENTITY_DIAGNOSTIC_CANDIDATES
  if (!is.null(thresholds) && is.numeric(thresholds$max_candidates) &&
      !is.na(thresholds$max_candidates)) {
    sinir <- max(sinir, as.integer(thresholds$max_candidates))
  }

  out <- list(
    decision = decision,
    rule = as.integer(rule),
    values = as.character(values),
    message_tr = message_tr,
    candidates = utils::head(eslesmeler, sinir),
    candidate_count = length(eslesmeler),
    top_score = if (!length(eslesmeler)) 0L else eslesmeler[[1]]$score,
    alias_target_missing = !is.null(scored) && isTRUE(scored$alias_target_missing),
    scan_truncated = !is.null(scored) && isTRUE(scored$scan_truncated),
    phrase_truncated = !is.null(scored) && isTRUE(scored$phrase_truncated),
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

# Yazılan ifade kanonik bir değerle TAM eşleştiyse çoğul ipucu BASTIRILIR.
# `SOLAR`, `HER` ve `KAYNAK LİSTESİ` gibi kanonik adlar ipucu sözcükleriyle
# veya `-lar/-ler` bitişiyle çakışır; kullanıcı tam adı yazmışken çoklu
# birleşim sormak yanlıştır.
#
# YALNIZCA KULLANICININ YAZDIĞI TAM İFADE sayılır. İfadeden ÇIKARILMIŞ bir
# anımın kanonik değere denk gelmesi bastırma gerekçesi DEĞİLDİR: "tüm ANKA"
# isteğinde anım `ANKA`ya tam eşleşir, ama kullanıcı açıkça niceleyici
# yazmıştır ve çoğul niyet korunmalıdır.
.pk_entity_has_unique_exact <- function(eslesmeler) {
  kesinler <- Filter(
    function(k) identical(k$tier, "exact_fold") &&
      !("mention_derived" %in% k$low_confidence),
    eslesmeler
  )
  length(kesinler) == 1L
}

# Kullanıcı kanonik değeri TAM yazdıysa, aynı ifadeye bağlı alias kaydı
# belirsizlik üretmemelidir (100/95 ikilisi).
.pk_entity_drop_alias_when_exact <- function(eslesmeler) {
  if (!.pk_entity_has_unique_exact(eslesmeler)) return(eslesmeler)
  Filter(function(k) !identical(k$tier, "alias"), eslesmeler)
}

#' Kullanıcı ifadesini kapalı sözlüğe karşı çöz (§5.4 karar tablosu)
#'
#' @param phrase Kullanıcının yazdığı ifade.
#' @param candidates Sütunun GERÇEK ayrık değerleri (kapalı sözlük).
#' @param aliases Doğrulanmış alias haritası (katlanmış anahtar -> kanonik değer).
#' @param role Sütun rolü (`pk_meta_match_mode`/metadata'dan). "id" ise bulanık
#'   eşleştirme YAPILMAZ.
#' @param match_mode Sütun eşleştirme kipi. Bulanık şelale YALNIZCA "resolve"
#'   kipinde çalışır; "exact" kayıpsız kesin eşleşme, "contains" alt dizge
#'   filtresi, "none" ise çözümleme YOK demektir.
#' @param entity_role "subject" (sorunun öznesi) veya "refinement" (ikincil
#'   daraltma). Kural 6 ile 7 arasındaki farkı BU belirler.
#' @param entity_kinds Metadata'da bildirilen varlık türü belirteçleri.
#' @param plural_override Çağıran taraf çoğulluğu biliyorsa (devam sorusu
#'   devralması) buradan geçirilir; ifadeden çıkarım YAPILMAZ.
#'
#' @return `.pk_entity_decision()` biçiminde karar kaydı.
pk_entity_resolve <- function(phrase, candidates, aliases = NULL,
                              role = NULL, match_mode = NULL,
                              entity_role = "subject",
                              query_meta = NULL, thresholds = NULL,
                              entity_kinds = NULL, plural_override = NULL) {
  esikler <- if (is.null(thresholds)) {
    pk_resolve_thresholds(query_meta)
  } else {
    pk_resolve_normalize_thresholds(thresholds)
  }

  # --- Kapalı başarısızlık: geçersiz eşik ilişkisi/kaynağı ------------------
  if (!isTRUE(esikler$valid)) {
    return(.pk_entity_decision(
      "config_error",
      message_tr = paste0(
        "Varlık çözümleme yapılandırması geçersiz olduğu için otomatik ",
        "çözümleme devre dışı bırakıldı. Operatöre bildirin: ",
        paste(esikler$errors, collapse = " ")
      ),
      thresholds = esikler
    ))
  }

  kip <- .pk_entity_effective_mode(role, match_mode)

  # --- Kip kapısı: bulanık şelale YALNIZCA "resolve" kipine aittir ----------
  if (identical(kip, .PK_RESOLVE_MODE_NONE)) {
    return(.pk_entity_decision(
      "disabled",
      message_tr = paste0(
        "Bu sütun için varlık çözümleme tanımlı değil; değer olduğu gibi ",
        "kullanılır."
      ),
      thresholds = esikler
    ))
  }

  if (identical(kip, .PK_RESOLVE_MODE_CONTAIN)) {
    return(.pk_entity_decision(
      "not_applicable",
      message_tr = paste0(
        "Bu sütun alt dizge (contains) filtresi kullanır; kanonik değer ",
        "çözümlemesi uygulanmaz."
      ),
      thresholds = esikler
    ))
  }

  exact_only <- identical(kip, .PK_RESOLVE_MODE_EXACT)

  puanlar <- pk_entity_score_candidates(
    phrase = phrase,
    candidates = candidates,
    aliases = aliases,
    exact_only = exact_only,
    entity_kinds = entity_kinds,
    query_meta = query_meta
  )

  # --- Geçersiz girdi: boş ifade sıfır puanlı kısayol DEĞİLDİR -------------
  if (!isTRUE(puanlar$valid)) {
    return(.pk_entity_decision(
      "invalid_input",
      message_tr = if (identical(puanlar$reason, "bos_ifade")) {
        "Çözümlenecek bir varlık ifadesi verilmedi."
      } else {
        "Bu sütun için karşılaştırılacak geçerli bir değer bulunamadı."
      },
      thresholds = esikler,
      reason = puanlar$reason
    ))
  }

  # --- Alias kaydı tutarsızlıkları: KAPALI BAŞARISIZLIK --------------------
  alias_karar <- .pk_entity_alias_guard(puanlar, esikler)
  if (!is.null(alias_karar)) return(alias_karar)

  eslesmeler <- .pk_entity_drop_alias_when_exact(puanlar$matches)
  puanlar$matches <- eslesmeler

  tepe <- if (length(eslesmeler)) eslesmeler[[1]]$score else 0L
  ikinci <- if (length(eslesmeler) >= 2L) eslesmeler[[2]]$score else NA_integer_
  fark <- if (is.na(ikinci)) Inf else tepe - ikinci

  cogul <- if (!is.null(plural_override)) {
    isTRUE(plural_override)
  } else {
    pk_entity_phrase_is_plural(phrase) && !.pk_entity_has_unique_exact(eslesmeler)
  }

  # --- Kural 1: kesin kod/kimlik eşleşmesi --------------------------------
  if (exact_only) {
    return(.pk_entity_exact_decision(
      eslesmeler, puanlar, esikler, entity_role, cogul, fark
    ))
  }

  # --- KIRPILMIŞ TARAMADAN OTOMATİK ÇÖZÜMLEME YAPILMAZ ---------------------
  #
  # `MERGEN_PK_RESOLVE_MAX_SCAN_CANDIDATES` aşıldığında kısa liste PUANA göre
  # değil, karakter uzunluğu yakınlığına göre kırpılır ve `scan_truncated`
  # bayrağı kalkar. Bu durumda `fark` (tepe ile ikinci arasındaki marj)
  # ÖLÇÜLMEMİŞTİR: elenen bir aday tepe puanla eşit olabilir ve gerçekte
  # netleştirme gerekirdi. Tek aday kaldığında marj `Inf` görünür ve karar
  # sessizce `auto` olur. Ölçülmemiş marj üzerinden karar verilmez; SORULUR.
  # `phrase_truncated` aynı sınıftan bir kusurdur: ifade kırpıldıysa puanlama
  # kullanıcının SÖYLEDİĞİ metnin tamamı üzerinden yapılmamıştır.
  if ((isTRUE(puanlar$scan_truncated) || isTRUE(puanlar$phrase_truncated)) &&
      !.pk_entity_has_unique_exact(eslesmeler)) {
    # KIRPILMIŞ KISA LİSTE HİÇ ADAY TAŞIMAYABİLİR; netleştirme SIFIR seçenekle
    # üretilirdi. `.pk_entity_below_threshold_decision()` ile AYNI kurtarma
    # kümesi kullanılır ve eşiği geçmedikleri için "Tümü" kapalıdır.
    aday_kumesi <- if (length(eslesmeler)) eslesmeler else
      pk_entity_nearest_candidates(phrase, candidates, esikler$max_candidates,
                                   query_meta = query_meta)
    # KIRPILMIŞ TARAMADA "Tümü" SUNULMAZ.
    #
    # Bu dalda küme KANITLANMIŞ biçimde EKSİKTİR: kırpılan adaylar tam da
    # "Tümü"nün kapsadığını iddia ettiği kümededir. Kullanıcı, hiç görmediği
    # adayları dışarıda bırakan bir alt kümeyi "Tümü" sanarak seçebilirdi.
    netlestirme <- pk_entity_clarification(
      aday_kumesi, esikler$max_candidates, allow_all = FALSE
    )
    # İKİNCİL DARALTMADA KIRPILMA ANALİZİ DURDURMAZ.
    #
    # Bu kapı rol ayrımından ÖNCE çalışıyor ve HER ZAMAN `clarify` dönüyordu;
    # `.pk_entity_apply_leaf()` `clarify`ı her yaprakta HALT'a çeviriyor,
    # dolayısıyla yüksek kardinaliteli bir İKİNCİL daraltma isteğin tamamını
    # durduruyordu. Dosyanın kural 7 sözleşmesi bu durumda "filtresiz devam +
    # AÇIK ifşa" der; kırpılma bilgisi ifşaya eklenir.
    if (identical(entity_role, "refinement")) {
      return(.pk_entity_decision(
        "unfiltered", rule = 7L,
        message_tr = paste0(
          "İkincil daraltma ifadesi için adayların TAMAMI karşılaştırılamadı; ",
          "analiz BU DARALTMA UYGULANMADAN yapıldı."
        ),
        scored = puanlar, clarification = netlestirme, thresholds = esikler,
        plural = cogul, margin = fark, disclose = TRUE, suggestions_only = TRUE
      ))
    }
    return(.pk_entity_decision(
      "clarify", rule = 2L,
      message_tr = paste0(
        "Bu alanda çok sayıda benzer kayıt var ve adayların tamamı ",
        "karşılaştırılamadı. Hangisini kastettiniz?"
      ),
      scored = puanlar, clarification = netlestirme, thresholds = esikler,
      plural = cogul, margin = fark
    ))
  }

  # --- Boş eşleşme kümesi: eşik dallarından ÖNCE ---------------------------
  # `MIN_SCORE=0` / `AUTO_SCORE=0` desteklenen yapılandırmalardır; boş küme
  # denetimi olmadan kural 4/5 `eslesmeler[[1]]` diyerek "subscript out of
  # bounds" hatası verirdi.
  if (length(eslesmeler)) {
    karar <- .pk_entity_scored_decision(eslesmeler, puanlar, esikler, tepe, fark, cogul)
    if (!is.null(karar)) return(karar)
  }

  .pk_entity_below_threshold_decision(
    phrase, candidates, eslesmeler, puanlar, esikler, entity_role, cogul, fark
  )
}

# Rol + kip birleşiminden etkin kipi türetir.
.pk_entity_effective_mode <- function(role, match_mode) {
  if (identical(role, "id")) return(.PK_RESOLVE_MODE_EXACT)

  kip <- if (is.null(match_mode) || !length(match_mode)) {
    NA_character_
  } else {
    as.character(match_mode)[1]
  }

  # Kip BİLDİRİLMEMİŞSE çağıran metadata taşımıyordur ve yardımcıyı doğrudan
  # çözümleme için kullanıyordur. Bildirilmiş "none" ise sözleşme gereği
  # çözümleme YAPILMAZ.
  if (is.na(kip) || !nzchar(kip)) return(.PK_RESOLVE_MODE_RESOLVE)
  if (!(kip %in% c(.PK_RESOLVE_MODE_EXACT, .PK_RESOLVE_MODE_RESOLVE,
                   .PK_RESOLVE_MODE_CONTAIN, .PK_RESOLVE_MODE_NONE))) {
    return(.PK_RESOLVE_MODE_NONE)
  }
  kip
}

# Alias kaydı/hedefi tutarsızsa ilgisiz bulanık adaylarla DEVAM EDİLMEZ.
.pk_entity_alias_guard <- function(puanlar, esikler) {
  if (length(puanlar$alias_errors)) {
    return(.pk_entity_decision(
      "config_error",
      message_tr = paste0(
        "Alias kaydı tutarsız olduğu için çözümleme durduruldu. ",
        "Operatöre bildirin: ", paste(puanlar$alias_errors, collapse = " ")
      ),
      scored = puanlar, thresholds = esikler
    ))
  }

  if (isTRUE(puanlar$alias_ambiguous)) {
    return(.pk_entity_decision(
      "clarify", rule = 2L,
      message_tr = paste0(
        "Yazdığınız kısaltma birden fazla onaylı karşılığa denk geliyor. ",
        "Hangisini kastettiniz?"
      ),
      scored = puanlar, thresholds = esikler
    ))
  }

  if (isTRUE(puanlar$alias_target_missing)) {
    return(.pk_entity_decision(
      "unresolved", rule = 6L,
      message_tr = paste0(
        "Onaylı kısaltmanın işaret ettiği kanonik değer bu sütunda bulunamadı; ",
        "yanıltıcı olmamak için analiz yapılmadı. Operatöre bildirin."
      ),
      scored = puanlar, thresholds = esikler, config_error = TRUE
    ))
  }

  NULL
}

# Kesin (id/exact) kip kararı.
.pk_entity_exact_decision <- function(eslesmeler, puanlar, esikler, entity_role,
                                      cogul, fark) {
  # Kural 1 YALNIZCA kayıpsız kesin eşleşmeye aittir. 95 puanlık bir alias
  # "kesin kod eşleşmesi" DEĞİLDİR ve asgari eşiğin altında kalabilir.
  kesinler <- Filter(function(k) identical(k$tier, "exact_fold"), eslesmeler)

  if (length(kesinler) == 1L) {
    return(.pk_entity_decision(
      "auto", rule = 1L, values = kesinler[[1]]$value,
      scored = puanlar, thresholds = esikler, plural = cogul, margin = fark
    ))
  }

  if (length(kesinler) > 1L) {
    # Birden çok kesin eşleşme yalnızca sözlük çakışmasında olur; sessizce
    # birini seçmek yerine netleştirilir.
    netlestirme <- pk_entity_clarification(kesinler, esikler$max_candidates)
    return(.pk_entity_decision(
      "clarify", rule = 2L,
      message_tr = "Birden fazla kesin eşleşme bulundu. Hangisini kastettiniz?",
      scored = puanlar, clarification = netlestirme, thresholds = esikler,
      plural = cogul, margin = fark
    ))
  }

  # Kesin eşleşme yok ama onaylı alias var: alias kural 1'e değil, normal
  # eşik/onay yoluna tabidir.
  aliaslar <- Filter(function(k) identical(k$tier, "alias"), eslesmeler)
  if (length(aliaslar) == 1L && aliaslar[[1]]$score >= esikler$min_score) {
    aday <- aliaslar[[1]]
    netlestirme <- pk_entity_clarification(
      list(aday), esikler$max_candidates, preselect = aday$value
    )
    return(.pk_entity_decision(
      "confirm", rule = 5L,
      message_tr = sprintf("Şunu mu kastettiniz: %s", aday$value),
      scored = puanlar, clarification = netlestirme, thresholds = esikler,
      plural = cogul, margin = fark
    ))
  }

  # Kesin kod bulunamadı. İkincil daraltmalar analizi BLOKE ETMEZ; yalnızca
  # sorunun öznesi bloke eder (kural 6 / kural 7 ayrımı bulanık yoldakiyle
  # AYNIDIR).
  if (identical(entity_role, "refinement")) {
    return(.pk_entity_decision(
      "unfiltered", rule = 7L,
      message_tr = paste0(
        "Belirtilen kod/kimlik değeri bu sütunda bulunamadı; analiz BU ",
        "DARALTMA UYGULANMADAN yapıldı."
      ),
      scored = puanlar, thresholds = esikler, plural = cogul, margin = fark,
      disclose = TRUE
    ))
  }

  .pk_entity_decision(
    "unresolved", rule = 6L,
    message_tr = "Belirtilen kod/kimlik değeri bu sütunda bulunamadı.",
    scored = puanlar, thresholds = esikler, plural = cogul, margin = fark
  )
}

# Kural 2/3/4/5. Hiçbiri tutmazsa NULL döner ve çağıran kural 6/7'ye geçer.
.pk_entity_scored_decision <- function(eslesmeler, puanlar, esikler, tepe, fark,
                                       cogul) {
  # --- Kural 2: belirsizlik (kural 3 ve 4'ten ÖNCE) ------------------------
  # `AMBIGUITY_MARGIN=0` geçerli bir ayardır; o hâlde de KESİN BERABERLİK
  # belirsizdir. Aksi hâlde desteklenen bir ayar, çakışma güvenliği
  # sözleşmesini tamamen devre dışı bırakırdı.
  esit_tepe <- length(eslesmeler) >= 2L &&
    identical(as.integer(eslesmeler[[2]]$score), as.integer(tepe))

  if (tepe >= esikler$min_score &&
      (fark < esikler$ambiguity_margin || isTRUE(esit_tepe))) {
    # Belirsizliği TETİKLEYEN ikinci aday, asgari puanın altında kalsa bile
    # çiplere DÂHİLDİR; aksi hâlde kullanıcı "birden fazla yakın aday var"
    # diyaloğunda tek çip görür ve alternatifi seçemez.
    guclu <- Filter(
      function(k) (tepe - k$score) < esikler$ambiguity_margin ||
        identical(as.integer(k$score), as.integer(tepe)),
      eslesmeler
    )
    netlestirme <- pk_entity_clarification(guclu, esikler$max_candidates)
    return(.pk_entity_decision(
      "clarify", rule = 2L,
      message_tr = "Birden fazla yakın aday var. Hangisini kastettiniz?",
      scored = puanlar, clarification = netlestirme, thresholds = esikler,
      plural = cogul, margin = fark
    ))
  }

  # --- Kural 3: çoğul istek (kural 4 ve 5'ten ÖNCE) ------------------------
  # Çoğul bir istek TEK adaya sessizce çökemez: kural 4 açıkça TEKİL yoldur ve
  # kural 5 de tek değeri onaylatır. Bu yüzden çoğul istekte güçlü aday sayısı
  # ne olursa olsun SORULUR.
  if (isTRUE(cogul)) {
    guclu <- Filter(function(k) k$score >= esikler$multi_score, eslesmeler)
    if (length(guclu) >= 1L) {
      netlestirme <- pk_entity_clarification(guclu, esikler$max_candidates)
      return(.pk_entity_decision(
        "clarify", rule = 3L,
        message_tr = "Çoklu bir istek algılandı. Hangi değerleri dâhil edelim?",
        scored = puanlar, clarification = netlestirme, thresholds = esikler,
        plural = cogul, margin = fark
      ))
    }
    return(NULL)
  }

  aday <- eslesmeler[[1]]
  kayipli <- length(aday$low_confidence) > 0L

  # --- Kural 4: tekil otomatik kabul --------------------------------------
  if (!kayipli && tepe >= esikler$auto_score && fark >= esikler$ambiguity_margin) {
    return(.pk_entity_decision(
      "auto", rule = 4L, values = aday$value,
      scored = puanlar, thresholds = esikler, plural = cogul, margin = fark
    ))
  }

  # --- Kural 5: ön seçimli onay -------------------------------------------
  if (tepe >= esikler$min_score && fark >= esikler$ambiguity_margin) {
    netlestirme <- pk_entity_clarification(
      list(aday), esikler$max_candidates, preselect = aday$value
    )
    return(.pk_entity_decision(
      "confirm", rule = 5L,
      message_tr = sprintf("Şunu mu kastettiniz: %s", aday$value),
      scored = puanlar, clarification = netlestirme, thresholds = esikler,
      plural = cogul, margin = fark, low_confidence = aday$low_confidence
    ))
  }

  NULL
}

# Kural 6/7 — eşik altı.
.pk_entity_below_threshold_decision <- function(phrase, candidates, eslesmeler,
                                                puanlar, esikler, entity_role,
                                                cogul, fark) {
  # Katman eşiğini geçen aday YOKSA `eslesmeler` boştur ve kullanıcıya
  # "en yakın adaylardan birini seçebilirsiniz" demek anlamsız olurdu.
  # Bu yüzden katman DIŞI en yakın komşular ayrıca hesaplanır. Bunlar
  # FİLTRELEMEYE UYGUN DEĞİLDİR; yalnızca kurtarma seçenekleridir.
  en_yakin <- if (length(eslesmeler)) {
    eslesmeler
  } else {
    pk_entity_nearest_candidates(phrase, candidates, esikler$max_candidates)
  }

  # Küme TAMAMI sayıldıktan sonra kırpılır; gizli aday "tam küme" gibi
  # gösterilemez. "Tümü" seçeneği kapalıdır: bunlar asgari puanı GEÇEMEMİŞ
  # tahminlerdir, onaylanmış bir birleşim kümesi değildir.
  netlestirme <- pk_entity_clarification(
    en_yakin, esikler$max_candidates, allow_all = FALSE
  )

  if (identical(entity_role, "refinement")) {
    return(.pk_entity_decision(
      "unfiltered", rule = 7L,
      message_tr = paste0(
        "İkincil daraltma ifadesi çözümlenemedi; analiz BU DARALTMA ",
        "UYGULANMADAN yapıldı."
      ),
      scored = puanlar, clarification = netlestirme, thresholds = esikler,
      plural = cogul, margin = fark, disclose = TRUE, suggestions_only = TRUE
    ))
  }

  .pk_entity_decision(
    "unresolved", rule = 6L,
    message_tr = paste0(
      "Sorunun öznesi olan değer çözümlenemedi; yanıltıcı olmamak için analiz ",
      "yapılmadı. En yakın adaylardan birini seçebilirsiniz."
    ),
    scored = puanlar, clarification = netlestirme, thresholds = esikler,
    plural = cogul, margin = fark, suggestions_only = TRUE
  )
}

# ==============================================================================
# Dosya Yolu: R/helpers_pk_entity_scan.R
# Açıklama: Faz 4 — kapalı sözlük taraması (master plan §5.4).
#
#           R/helpers_pk_entity_score.R katman FORMÜLLERİNİ, bu dosya kapalı
#           sözlük üzerinde ADAY SEÇİMİNİ sahiplenir.
#
#           NEDEN AYRI BİR TARAMA KATMANI VAR: naif uygulama her istekte her
#           ayrık değeri baştan normalleştirir ve katman 1-5 ıskaladığında her
#           aday için iki Levenshtein hesabı yapar. 50 bin değerli bir
#           kişi/proje sütununda bu, tek bir soruda yaklaşık 100 bin O(m*n)
#           mesafe hesabı demektir ve PAYLAŞILAN Shiny sürecini kilitler.
#
#           Bu yüzden tarama iki aşamalıdır:
#             1) UCUZ aşama — tüm değerler üzerinde yalnızca vektörel katlama,
#                ASCII anahtarı ve soyulmamış belirteç ayrımı. Kesin/alias
#                katmanları BURADA karma (hash) araması ile çözülür.
#             2) PAHALI aşama — yalnızca KISA LİSTE tam normalleştirilir ve
#                belirteç/mesafe katmanlarına girer.
#
#           Kısa liste ELEMESİ DEĞİL, ÜST KÜMEDİR: paylaşılan belirteç içeren
#           her aday (katman 4/5 için gerekli koşul) ve uzunluk bandına giren
#           her aday (katman 6 için gerekli koşul) listeye alınır. Bu yüzden
#           hiçbir GERÇEK eşleşme kaybolmaz.
#
# Dosya saftır: Shiny/reactive/DB/ağ bağımlılığı yoktur, worker güvenlidir.
# ==============================================================================

.pk_entity_scan_limit <- function(key, fallback, query_meta = NULL) {
  if (!exists("pk_config_resolve", mode = "function")) return(fallback)
  deger <- tryCatch(
    pk_config_resolve(key, query_meta = query_meta),
    error = function(e) NULL
  )
  if (is.null(deger) || !is.numeric(deger) || !length(deger) || is.na(deger[1])) {
    return(fallback)
  }
  as.integer(deger[1])
}

# Kapalı sözlüğün UCUZ görünümü. Tam normalleştirme YAPILMAZ.
.pk_entity_coarse_view <- function(degerler) {
  katlanmis <- pk_tr_fold(degerler)

  kesin <- stringi::stri_replace_all_fixed(
    katlanmis, .PK_ENTITY_APOSTROPHES, rep("'", length(.PK_ENTITY_APOSTROPHES)),
    vectorize_all = FALSE
  )
  kesin <- trimws(stringi::stri_replace_all_regex(kesin, "\\s+", " "))

  sade <- pk_entity_collapse_punct(kesin)
  ascii <- pk_entity_ascii_key(sade)

  list(
    values = degerler,
    exact = kesin,
    fold = sade,
    ascii = ascii,
    compact = gsub(" ", "", sade, fixed = TRUE),
    ascii_compact = gsub(" ", "", ascii, fixed = TRUE),
    nchar = nchar(ascii)
  )
}

# Katman 1-3 anahtarları KARMA ARAMASI ile çözülür; kısa liste
# (belirteç/uzunluk) sezgiselleri onları KAÇIRABİLİR. Örnek: `F16` ile
# kanonik `F-16` ortak belirteç taşımaz ve uzunluk bandına girmez, ama
# boşluksuz ikincil anahtarları AYNIDIR.
.pk_entity_key_hits <- function(kaba, user_norm, exact_only) {
  if (isTRUE(exact_only)) return(which(kaba$exact == user_norm$exact))

  unique(c(
    which(kaba$exact == user_norm$clitic),
    which(kaba$fold == user_norm$fold),
    which(kaba$ascii == user_norm$ascii),
    which(kaba$compact == user_norm$compact),
    which(kaba$ascii_compact == user_norm$ascii_compact)
  ))
}

# Sözlükteki soyulmamış belirteçlerin kümesi. Sözlük farkındalı sonek soyma
# (İHAlar -> iha, kitabı -> kitap) bu kümeye karşı doğrulanır.
.pk_entity_vocab_tokens <- function(kaba) {
  parcalar <- strsplit(kaba$fold, " ", fixed = TRUE)
  belirtecler <- unlist(parcalar, use.names = FALSE)
  belirtecler <- belirtecler[!is.na(belirtecler) & nzchar(belirtecler)]
  unique(belirtecler)
}

# Katman 4/5/6 için ADAY ÜST KÜMESİ.
.pk_entity_shortlist <- function(kaba, user_norm, max_scan) {
  n <- length(kaba$values)
  if (!n) return(integer(0))

  secili <- rep(FALSE, n)

  # (a) Ortak belirteç taşıyanlar — katman 4/5 için GEREKLİ koşul.
  #     Alt dizge araması belirteç paylaşımının ÜST KÜMESİDİR; bu yüzden
  #     eleme yapmaz, yalnızca hızlandırır.
  probe <- unique(c(user_norm$tokens_ascii, user_norm$tokens))
  probe <- probe[!is.na(probe) & nzchar(probe)]
  for (tok in probe) {
    secili <- secili | stringi::stri_detect_fixed(kaba$ascii, tok)
  }

  # (b) Uzunluk bandı — katman 6 için GEREKLİ koşul:
  #     d <= 0.20  =>  |len(a) - len(b)| * 5 <= max(len(a), len(b))
  kullanici_n <- nchar(user_norm$ascii)
  if (!is.na(kullanici_n) && kullanici_n > 0L) {
    en_uzun <- pmax(kaba$nchar, kullanici_n)
    secili <- secili | (abs(kaba$nchar - kullanici_n) * 5L <= en_uzun)
  }

  secili[is.na(secili)] <- FALSE
  idx <- which(secili)
  if (length(idx) <= max_scan) return(list(idx = idx, truncated = FALSE))

  # Tavan aşıldı: en yakın uzunluklu adaylar önce gelir. Bu bir KIRPMADIR ve
  # çağıran tarafa `scan_truncated` ile AÇIKÇA bildirilir; sessizce
  # "eşleşme yok" denmez.
  fark <- abs(kaba$nchar[idx] - kullanici_n)
  list(
    idx = idx[order(fark, method = "radix")][seq_len(max_scan)],
    truncated = TRUE
  )
}

#' Kapalı sözlükteki her adayı puanla
#'
#' @param phrase Kullanıcı ifadesi (tek karakter değeri).
#' @param candidates Sütunun GERÇEK ayrık değerleri (kapalı sözlük).
#' @param aliases `pk_meta_fold_alias_map()` çıktısı: adları KATLANMIŞ alias
#'   anahtarı, değerleri kanonik hedef olan adlandırılmış karakter vektörü.
#' @param exact_only TRUE ise yalnızca KAYIPSIZ kesin katman çalışır.
#' @param entity_kinds Metadata'da bildirilen varlık türü belirteçleri.
#'
#' @return `list(valid, reason, alias_target, alias_target_missing,
#'   alias_ambiguous, alias_errors, matches, scan_truncated, phrase_truncated)`.
#'   `matches` puana göre AZALAN, eşitlikte kanonik değere göre ARTAN sırada
#'   kayıtlardan oluşur. Sıralama C yerelinde (radix) yapılır; böylece sonuç
#'   Türkçe Windows VM ile POSIX konteynerde AYNI olur ve hiçbir aday
#'   yineleme sırasına göre seçilmez (§5.4).
pk_entity_score_candidates <- function(phrase, candidates, aliases = NULL,
                                       exact_only = FALSE, entity_kinds = NULL,
                                       query_meta = NULL) {
  bos_sonuc <- function(reason) {
    list(
      valid = FALSE, reason = reason,
      alias_target = NULL, alias_target_missing = FALSE,
      alias_ambiguous = FALSE, alias_errors = character(0),
      matches = list(), scan_truncated = FALSE, phrase_truncated = FALSE
    )
  }

  .pk_entity_require_stringi()

  azami_karakter <- .pk_entity_scan_limit(
    "MERGEN_PK_RESOLVE_MAX_PHRASE_CHARS", 160L, query_meta
  )
  azami_tarama <- .pk_entity_scan_limit(
    "MERGEN_PK_RESOLVE_MAX_SCAN_CANDIDATES", 2000L, query_meta
  )

  ham_ifade <- if (is.null(phrase) || !length(phrase)) NA_character_ else as.character(phrase)[1]
  ifade_kirpildi <- FALSE
  if (!is.na(ham_ifade) && nchar(ham_ifade) > azami_karakter) {
    # Sınırsız ifade uzunluğu, mütevazı bir sözlükte bile paylaşılan süreci
    # meşgul edebilir (yapıştırılmış/kötü niyetli metin).
    ham_ifade <- substring(ham_ifade, 1L, azami_karakter)
    ifade_kirpildi <- TRUE
  }

  degerler <- as.character(candidates)
  degerler <- degerler[!is.na(degerler) & nzchar(trimws(degerler))]
  if (!length(degerler)) return(bos_sonuc("bos_sozluk"))

  kaba <- .pk_entity_coarse_view(degerler)

  # Normalleştirmeden SONRA boş kalan değerler ("---", "///") sessizce
  # atlanamaz: hepsi boşsa sözlük GEÇERSİZDİR.
  gecerli <- !is.na(kaba$fold) & nzchar(kaba$fold)
  if (!any(gecerli)) return(bos_sonuc("bos_sozluk"))

  # Kanonik anahtara göre tekilleştirme. `"ANKA"` ile `" ANKA "` aynı
  # varlıktır; iki ayrı 100 puanlık çip üretmeleri hatalı bir belirsizliktir.
  tut <- gecerli & !duplicated(kaba$exact)
  kaba <- lapply(kaba, function(x) x[tut])

  sozluk_belirtecleri <- .pk_entity_vocab_tokens(kaba)

  user_norm <- pk_entity_normalize(ham_ifade, vocab = sozluk_belirtecleri)
  if (isTRUE(user_norm$blank)) return(bos_sonuc("bos_ifade"))

  alias_index <- pk_entity_alias_index(aliases)
  alias_hit <- pk_entity_alias_lookup(alias_index, user_norm)

  # Alias hedefinin sözlükte VAR OLUP OLMADIĞI, hangi katmanın kazandığından
  # BAĞIMSIZ belirlenir. Aksi hâlde `anka -> ANKA` gibi geçerli bir kayıt,
  # katman 1 önce kazandığı için "hedef eksik" sayılırdı.
  alias_eksik <- FALSE
  if (!is.null(alias_hit$target)) {
    hedef_norm <- pk_entity_normalize(alias_hit$target)
    alias_eksik <- is.na(hedef_norm$exact) || !(hedef_norm$exact %in% kaba$exact)
  }

  kisa <- .pk_entity_shortlist(kaba, user_norm, azami_tarama)
  kisa_liste <- kisa$idx
  tarama_kirpildi <- !exact_only && isTRUE(kisa$truncated)

  # Kesin/ikincil anahtar/alias katmanları karma araması ile çözülür.
  kesin_idx <- .pk_entity_key_hits(kaba, user_norm, exact_only)
  alias_idx <- integer(0)
  if (!is.null(alias_hit$target) && !alias_eksik) {
    hedef_norm <- pk_entity_normalize(alias_hit$target)
    alias_idx <- which(kaba$exact == hedef_norm$exact)
  }

  incelenecek <- if (isTRUE(exact_only)) {
    unique(c(kesin_idx, alias_idx))
  } else {
    unique(c(kesin_idx, alias_idx, kisa_liste))
  }

  kayitlar <- .pk_entity_score_indices(
    incelenecek, kaba, user_norm, alias_hit, sozluk_belirtecleri, exact_only
  )

  # ANIM (mention) GEÇİŞİ — yalnızca tam ifade hiçbir KESİN/İKİNCİL katmana
  # ulaşamadığında çalışır. Böylece tür sözcüğü içeren kanonik adlar
  # ("KAYNAK LİSTESİ") bozulmaz, ama "ANKA ve AKINCI projeleri" /
  # "ANKA projesi" / "tüm ANKA" gibi istekler çözülebilir.
  guclu_katman <- c("exact_fold", "alias", "ascii_key", "punct_key", "compact_key")
  if (!exact_only &&
      !any(vapply(kayitlar, function(k) k$tier %in% guclu_katman, logical(1)))) {
    kayitlar <- .pk_entity_merge_mention_matches(
      kayitlar, ham_ifade, kaba, alias_hit, sozluk_belirtecleri,
      entity_kinds, azami_tarama
    )
  }

  if (length(kayitlar)) {
    puanlar <- vapply(kayitlar, function(k) k$score, integer(1))
    adlar   <- vapply(kayitlar, function(k) k$value, character(1))
    sira    <- order(-puanlar, adlar, method = "radix")
    kayitlar <- kayitlar[sira]
  }

  list(
    valid = TRUE,
    reason = NA_character_,
    alias_target = alias_hit$target,
    alias_target_missing = alias_eksik,
    alias_ambiguous = isTRUE(alias_hit$ambiguous),
    alias_errors = alias_index$errors,
    matches = kayitlar,
    scan_truncated = tarama_kirpildi,
    phrase_truncated = ifade_kirpildi
  )
}

#' Katman DIŞI en yakın komşular (kurtarma önerileri)
#'
#' Kural 6/7'de kullanıcıya "en yakın adaylardan birini seçebilirsiniz" denir.
#' Ancak `matches` yalnızca ALTI KATMANDAN BİRİNİ geçen adayları içerir ve
#' varsayılan `MIN_SCORE=40` ile her katman puanı en az 50'dir; yani gerçek
#' bir kural-6 durumunda küme BOŞTUR ve kullanıcı hiç çip görmez.
#'
#' Bu yardımcı o boşluğu doldurur. Döndürülen kayıtlar `tier = "suggestion"`
#' taşır ve FİLTRELEMEYE UYGUN DEĞİLDİR; yalnızca gösterilir.
pk_entity_nearest_candidates <- function(phrase, candidates, n = 3L,
                                         query_meta = NULL) {
  n <- suppressWarnings(as.integer(n)[1])
  if (is.na(n) || n < 1L) n <- 3L

  degerler <- as.character(candidates)
  degerler <- degerler[!is.na(degerler) & nzchar(trimws(degerler))]
  if (!length(degerler)) return(list())

  user_norm <- pk_entity_normalize(phrase)
  if (isTRUE(user_norm$blank)) return(list())

  .pk_entity_require_stringdist()

  # TARAMA TAVANI BURADA DA UYGULANIR — HEM DE NORMALLEŞTİRMEDEN ÖNCE. Eşik altı
  # kurtarma yolu bu yardımcıyı sütundaki HER ayrık değerle çağırır ve
  # `MERGEN_PK_RESOLVE_MAX_SCAN_CANDIDATES` tavanını YOK SAYIYORDU: yüksek
  # kardinaliteli bir sütunda tek yazım hatası on binlerce hesabı geri getirip
  # asenkron kapalıyken paylaşılan Shiny olay döngüsünü blokluyordu. Kırpma
  # `.pk_entity_coarse_view()` ÇAĞRILMADAN ÖNCE yapılır (baskın maliyet TÜM
  # değerler üzerindeki katlama/ASCII normalleştirmesidir); ön eleme
  # `.pk_entity_shortlist()` ile AYNI uzunluk bandını kullanır (ham `nchar`
  # ucuzdur, sıralama YOKTUR).
  azami_tarama <- .pk_entity_scan_limit(
    "MERGEN_PK_RESOLVE_MAX_SCAN_CANDIDATES", 2000L, query_meta
  )
  if (length(degerler) > azami_tarama) {
    kullanici_n <- nchar(user_norm$ascii)
    if (is.na(kullanici_n) || kullanici_n < 1L) kullanici_n <- 1L
    ham_n <- nchar(degerler)
    bant <- abs(ham_n - kullanici_n) * 5L <= pmax(ham_n, kullanici_n)
    bant[is.na(bant)] <- FALSE
    tut <- which(bant)
    # Bant hiçbir şey bırakmazsa ya da hâlâ tavanı aşıyorsa deterministik
    # biçimde ilk N aday alınır; bunlar zaten yalnızca GÖSTERİLEN önerilerdir
    # (`tier = "suggestion"`, filtrelemeye uygun DEĞİLDİR).
    if (!length(tut)) tut <- seq_along(degerler)
    if (length(tut) > azami_tarama) tut <- tut[seq_len(azami_tarama)]
    degerler <- degerler[tut]
  }

  kaba <- .pk_entity_coarse_view(degerler)
  gecerli <- !is.na(kaba$ascii) & nzchar(kaba$ascii)
  if (!any(gecerli)) return(list())

  kaba <- lapply(kaba, function(x) x[gecerli])

  mesafe <- stringdist::stringdist(user_norm$ascii, kaba$ascii, method = "lv")
  oran <- mesafe / pmax(nchar(kaba$ascii), nchar(user_norm$ascii), 1L)
  oran[is.na(oran)] <- 1

  sira <- order(oran, kaba$values, method = "radix")
  sira <- sira[seq_len(min(n, length(sira)))]

  lapply(sira, function(i) list(
    value = kaba$values[i],
    score = 0L,
    tier = "suggestion",
    low_confidence = "below_threshold"
  ))
}

# Seçili indeksleri tam normalleştirip puanlar.
.pk_entity_score_indices <- function(idx, kaba, user_norm, alias_hit, vocab,
                                     exact_only) {
  # Alias hedefi DONGU DISINDA normallestirilir (bkz. `.pk_entity_tier_of()`).
  if (!is.null(alias_hit) && !is.null(alias_hit$target) &&
      is.null(alias_hit$target_norm)) {
    alias_hit$target_norm <- pk_entity_normalize(alias_hit$target)
  }

  kayitlar <- list()
  for (i in idx) {
    deger <- kaba$values[i]
    cand_norm <- pk_entity_normalize(deger, vocab = vocab)
    if (isTRUE(cand_norm$blank)) next

    katman <- .pk_entity_tier_of(
      user_norm    = user_norm,
      cand_norm    = cand_norm,
      alias_hit    = alias_hit,
      cand_value   = deger,
      exact_only   = exact_only
    )
    if (is.null(katman)) next

    kayitlar[[length(kayitlar) + 1L]] <- list(
      value = deger,
      score = as.integer(katman$score),
      tier  = katman$tier,
      low_confidence = katman$low_confidence
    )
  }
  kayitlar
}

# Anım geçişinin sonuçlarını mevcut kayıtlarla birleştirir (aday başına EN
# YÜKSEK puan kazanır). Anımdan gelen kayıtlar `mention_derived` bayrağı
# taşır: bunlar kullanıcının yazdığı TAM ifadeden değil, ondan çıkarılan bir
# parçadan üretilmiştir.
.pk_entity_merge_mention_matches <- function(kayitlar, phrase, kaba, alias_hit,
                                             vocab, entity_kinds, max_scan) {
  animlar <- pk_entity_mentions(phrase, entity_kinds = entity_kinds)
  if (!length(animlar)) return(kayitlar)

  mevcut <- vapply(kayitlar, function(k) k$value, character(1))

  for (anim in animlar) {
    anim_norm <- pk_entity_normalize(anim, vocab = vocab)
    if (isTRUE(anim_norm$blank)) next

    idx <- unique(c(
      .pk_entity_key_hits(kaba, anim_norm, FALSE),
      .pk_entity_shortlist(kaba, anim_norm, max_scan)$idx
    ))

    yeni <- .pk_entity_score_indices(idx, kaba, anim_norm, alias_hit, vocab, FALSE)
    for (k in yeni) {
      k$low_confidence <- unique(c(k$low_confidence, "mention_derived"))
      k$mention <- anim

      konum <- match(k$value, mevcut)
      if (is.na(konum)) {
        kayitlar[[length(kayitlar) + 1L]] <- k
        mevcut <- c(mevcut, k$value)
      } else if (k$score > kayitlar[[konum]]$score) {
        kayitlar[[konum]] <- k
      }
    }
  }

  kayitlar
}

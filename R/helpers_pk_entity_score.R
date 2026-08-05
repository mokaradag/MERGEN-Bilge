# ==============================================================================
# Dosya Yolu: R/helpers_pk_entity_score.R
# Açıklama: Faz 4 — altı katmanlı puanlama şelalesi (master plan §5.4).
#
#           Katmanlar SIRAYLA denenir ve İLK eşleşen katman kazanır. Formüller
#           SÖZLEŞMEDİR, örnek aralık değildir:
#
#             1  Kesin Türkçe katlama eşleşmesi ........ 100
#             2  Doğrulanmış alias kaydından eşleşme ...  95
#             3  Kesin ASCII ikincil anahtar eşleşmesi .  90
#             4  Tüm kullanıcı belirteçleri kapsanıyor . min(89, 85 + floor(4*J))
#             5  0.60 <= J < 1 ......................... min(84, 60 + floor(25*(J-0.60)/0.40))
#             6  0 < d <= 0.20 ......................... max(50, 69 - floor(19*d/0.20))
#
#           J = |U ∩ C| / |U ∪ C| (katlanmış belirteç kümeleri)
#           d = Levenshtein(U, C) / max(nchar(U), nchar(C))
#
#           Boş belirteç ve sıfır uzunluk GEÇERSİZ GİRDİDİR; sıfır puanlı bir
#           kısayol değildir (§5.4).
#
# Dosya saftır: Shiny/reactive/DB/ağ bağımlılığı yoktur, worker güvenlidir.
# ==============================================================================

# Katman kimlikleri; tanılama ve testler bu adları kullanır.
PK_ENTITY_TIERS <- c(
  "exact_fold",   # 1
  "alias",        # 2
  "ascii_key",    # 3
  "token_subset", # 4
  "token_jaccard",# 5
  "edit_distance" # 6
)

# Katman 5/6 eşikleri. Formülün parçasıdır; yapılandırmayla DEĞİŞTİRİLEMEZ.
.PK_ENTITY_J_FLOOR <- 0.60
.PK_ENTITY_D_CEIL  <- 0.20

.pk_entity_require_stringdist <- function() {
  if (!requireNamespace("stringdist", quietly = TRUE)) {
    stop(
      paste0(
        "pk_entity_score: 'stringdist' paketi bulunamadi. Katman 6 (duzenleme ",
        "mesafesi) bu paket olmadan hesaplanamaz."
      ),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

#' Jaccard benzerliği (katlanmış belirteç kümeleri üzerinde)
#'
#' Her iki küme de boşsa sonuç 0'dır; boş girdi kararı çağıran katmana aittir.
pk_entity_jaccard <- function(user_tokens, cand_tokens) {
  u <- unique(user_tokens[!is.na(user_tokens) & nzchar(user_tokens)])
  c_ <- unique(cand_tokens[!is.na(cand_tokens) & nzchar(cand_tokens)])

  if (!length(u) || !length(c_)) return(0)

  kesisim <- length(intersect(u, c_))
  birlesim <- length(union(u, c_))
  if (birlesim <= 0L) return(0)

  kesisim / birlesim
}

#' Normalleştirilmiş Levenshtein mesafesi
#'
#' @return `d` = mesafe / daha uzun dizginin uzunluğu. Aralık [0, 1].
pk_entity_edit_ratio <- function(a, b) {
  if (is.na(a) || is.na(b)) return(1)
  if (!nzchar(a) || !nzchar(b)) return(1)

  .pk_entity_require_stringdist()

  en_uzun <- max(nchar(a), nchar(b))
  if (en_uzun <= 0L) return(1)

  mesafe <- stringdist::stringdist(a, b, method = "lv")
  if (!length(mesafe) || is.na(mesafe)) return(1)

  as.numeric(mesafe) / en_uzun
}

# --- Katman formülleri --------------------------------------------------------
# `max()`/`min()` kelepçeleri kayan nokta tozuna karşıdır; meşru bir girdi
# hiçbir zaman aralığın dışına çıkmaz (katman koşulu bunu zaten garanti eder).

.pk_entity_tier4_score <- function(j) {
  as.integer(max(85L, min(89L, 85L + floor(4 * j))))
}

.pk_entity_tier5_score <- function(j) {
  ham <- 60L + floor(25 * (j - .PK_ENTITY_J_FLOOR) / (1 - .PK_ENTITY_J_FLOOR))
  as.integer(max(60L, min(84L, ham)))
}

.pk_entity_tier6_score <- function(d) {
  ham <- 69L - floor(19 * d / .PK_ENTITY_D_CEIL)
  as.integer(max(50L, min(69L, ham)))
}

# Tek bir aday için katman/puan kararı. Eşleşme yoksa NULL döner.
#
# `exact_only` TRUE ise (rol = "id" veya match = "exact") YALNIZCA katman 1 ve 2
# çalışır: kodlar ve kimlikler ASLA bulanıklaştırılmaz (§5.4 kapanış kuralı).
.pk_entity_tier_of <- function(user_norm, cand_norm, alias_target = NULL,
                               cand_value = NA_character_, exact_only = FALSE) {
  # Katman 1 — kesin katlama eşleşmesi
  if (!is.na(user_norm$fold) && !is.na(cand_norm$fold) &&
      identical(user_norm$fold, cand_norm$fold)) {
    return(list(tier = "exact_fold", score = 100L))
  }

  # Katman 2 — doğrulanmış alias
  if (!is.null(alias_target) && !is.na(cand_value) &&
      identical(trimws(enc2utf8(cand_value)), alias_target)) {
    return(list(tier = "alias", score = 95L))
  }

  if (isTRUE(exact_only)) return(NULL)

  # Katman 3 — kesin ASCII ikincil anahtar
  if (!is.na(user_norm$ascii) && !is.na(cand_norm$ascii) &&
      identical(user_norm$ascii, cand_norm$ascii)) {
    return(list(tier = "ascii_key", score = 90L))
  }

  u <- user_norm$tokens
  c_ <- cand_norm$tokens
  if (!length(u) || !length(c_)) return(NULL)

  # ÖLÇÜLMÜŞ GEREKÇE (tasarım kararı E3) — belirteç katmanları ASCII
  # anahtarını da dikkate alır.
  #
  #   Türkçe katlama ASCII büyük `I` harfini NOKTASIZ `ı`ya çevirir. Kurumsal
  #   veritabanlarında yaygın olan TAMAMI BÜYÜK HARF ASCII değerler bu yüzden
  #   `ELEKTRONIK` -> `elektronık` olur; kullanıcının yazdığı `elektronik` ise
  #   NOKTALI `i` taşır. İkisi belirteç düzeyinde ASLA eşleşmez.
  #
  #   Katman 3 yalnızca TÜM DİZGİ kesin eşleşmesini kurtarır; kısmi ifadeyi
  #   ("elektronik harp" -> uzun proje adı) taşıyan katman 4/5 tamamen
  #   ıskalardı — ki bu, §8'in "uzun proje adları kısmi Türkçe ifadeden
  #   çözümlenir" kabul ölçütünün ta kendisidir.
  #
  #   Bu yüzden J iki gösterim üzerinden hesaplanır ve BÜYÜĞÜ alınır: puan
  #   yalnızca ARTABİLİR, hiçbir formül ve katman sırası değişmez. Katman 3
  #   (90) hâlâ katman 4'ten (tavan 89) ÖNCE denendiği için sıralama korunur.
  u_ascii <- user_norm$tokens_ascii
  c_ascii <- cand_norm$tokens_ascii

  j <- max(
    pk_entity_jaccard(u, c_),
    pk_entity_jaccard(u_ascii, c_ascii)
  )

  kapsama <- all(u %in% c_) ||
    (length(u_ascii) > 0L && length(c_ascii) > 0L && all(u_ascii %in% c_ascii))

  # Katman 4 — tüm kullanıcı belirteçleri adayda var (sırasız kapsama)
  if (isTRUE(kapsama)) {
    return(list(tier = "token_subset", score = .pk_entity_tier4_score(j)))
  }

  # Katman 5 — kısmi belirteç örtüşmesi
  if (j >= .PK_ENTITY_J_FLOOR && j < 1) {
    return(list(tier = "token_jaccard", score = .pk_entity_tier5_score(j)))
  }

  # Katman 6 — düzenleme mesafesi (aynı gerekçeyle aksan duyarsız: daha KÜÇÜK
  # mesafe daha iyi eşleşmedir, bu yüzden minimum alınır).
  d <- min(
    pk_entity_edit_ratio(user_norm$fold, cand_norm$fold),
    pk_entity_edit_ratio(user_norm$ascii, cand_norm$ascii)
  )
  if (d > 0 && d <= .PK_ENTITY_D_CEIL) {
    return(list(tier = "edit_distance", score = .pk_entity_tier6_score(d)))
  }

  NULL
}

#' Kapalı sözlükteki her adayı puanla
#'
#' @param phrase Kullanıcı ifadesi (tek karakter değeri).
#' @param candidates Sütunun GERÇEK ayrık değerleri (kapalı sözlük).
#' @param aliases `pk_meta_fold_alias_map()` çıktısı: adları KATLANMIŞ alias
#'   anahtarı, değerleri kanonik hedef olan adlandırılmış karakter vektörü.
#' @param exact_only TRUE ise yalnızca katman 1/2 çalışır (kod/kimlik sütunu).
#'
#' @return `list(valid, reason, alias_target, alias_target_missing, matches)`.
#'   `matches` puana göre AZALAN, eşitlikte kanonik değere göre ARTAN sırada
#'   kayıtlardan oluşur. Sıralama C yerelinde (radix) yapılır; böylece sonuç
#'   Türkçe Windows VM ile POSIX konteynerde AYNI olur ve hiçbir aday
#'   yineleme sırasına göre seçilmez (§5.4).
pk_entity_score_candidates <- function(phrase, candidates, aliases = NULL,
                                       exact_only = FALSE) {
  bos_sonuc <- function(reason) {
    list(
      valid = FALSE,
      reason = reason,
      alias_target = NULL,
      alias_target_missing = FALSE,
      matches = list()
    )
  }

  user_norm <- pk_entity_normalize(phrase)
  if (isTRUE(user_norm$blank)) return(bos_sonuc("bos_ifade"))

  degerler <- as.character(candidates)
  degerler <- degerler[!is.na(degerler) & nzchar(trimws(degerler))]
  degerler <- unique(degerler)
  if (!length(degerler)) return(bos_sonuc("bos_sozluk"))

  # Alias hedefi ifadeye göre BİR KEZ çözülür; aday döngüsünde tekrarlanmaz.
  alias_target <- NULL
  if (length(aliases) && !is.null(names(aliases))) {
    idx <- match(user_norm$fold, names(aliases))
    if (!is.na(idx)) alias_target <- unname(as.character(aliases)[idx])
  }

  kayitlar <- list()
  for (deger in degerler) {
    cand_norm <- pk_entity_normalize(deger)
    if (isTRUE(cand_norm$blank)) next

    katman <- .pk_entity_tier_of(
      user_norm    = user_norm,
      cand_norm    = cand_norm,
      alias_target = alias_target,
      cand_value   = deger,
      exact_only   = exact_only
    )
    if (is.null(katman)) next

    kayitlar[[length(kayitlar) + 1L]] <- list(
      value = deger,
      score = as.integer(katman$score),
      tier  = katman$tier
    )
  }

  alias_bulunamadi <- !is.null(alias_target) &&
    !any(vapply(kayitlar, function(k) identical(k$tier, "alias"), logical(1)))

  if (length(kayitlar)) {
    puanlar <- vapply(kayitlar, function(k) k$score, integer(1))
    adlar   <- vapply(kayitlar, function(k) k$value, character(1))
    sira    <- order(-puanlar, adlar, method = "radix")
    kayitlar <- kayitlar[sira]
  }

  list(
    valid = TRUE,
    reason = NA_character_,
    alias_target = alias_target,
    alias_target_missing = alias_bulunamadi,
    matches = kayitlar
  )
}

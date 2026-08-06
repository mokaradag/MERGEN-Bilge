# ==============================================================================
# Dosya Yolu: R/helpers_pk_entity_score.R
# Açıklama: Faz 4 — puanlama şelalesi (master plan §5.4).
#
#           Katmanlar SIRAYLA denenir ve İLK eşleşen katman kazanır. Formüller
#           SÖZLEŞMEDİR, örnek aralık değildir:
#
#             1  Kesin Türkçe katlama eşleşmesi ........ 100
#             2  Doğrulanmış alias kaydından eşleşme ...  95
#             3  Kesin ikincil anahtar eşleşmesi .......  90
#                  (ASCII / noktalama-sadeleştirilmiş / boşluksuz)
#             4  Tüm kullanıcı belirteçleri kapsanıyor . min(89, 85 + floor(4*J))
#             5  0.60 <= J < 1 ......................... min(84, 60 + floor(25*(J-0.60)/0.40))
#             6  0 < d <= 0.20 ......................... max(50, 69 - floor(19*d/0.20))
#
#           J = |U ∩ C| / |U ∪ C| (katlanmış belirteç kümeleri)
#           d = Levenshtein(U, C) / max(nchar(U), nchar(C))
#
#           TAM SAYI SÖZLEŞMESİ: 4/5/6 formülleri KESİRLİ ARA DEĞER ÜRETMEZ.
#           `floor(25 * (123/125 - 0.6) / 0.4)` ikili kayan noktada
#           23.999999999999996 verir ve sözleşmenin 84'ünü 83'e düşürür; aynı
#           şekilde `floor(19 * (1/95) / 0.20)` 0.9999999999999999 verip
#           sözleşmenin 68'ini 69'a çıkarır. Bu bir puan hatası değil, geçerli
#           bir yapılandırmada "onay iste" ile "otomatik filtrele" arasındaki
#           farktır. Bu yüzden formüller KESİŞİM/BİRLEŞİM ve MESAFE/UZUNLUK
#           TAM SAYILARINDAN yeniden türetilir; kayan nokta bölme yoktur.
#
#           GÜVEN BAYRAKLARI: bir eşleşme kayıplı/sezgisel bir adıma bağlıysa
#           `low_confidence` alanı doldurulur. Karar politikası bayraklı
#           eşleşmeyi ASLA otomatik kabul etmez; yalnızca onay ister. Puan
#           tek başına güvenlik mekanizması DEĞİLDİR.
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
  "punct_key",    # 3 (kayıplı)
  "compact_key",  # 3 (kayıplı)
  "token_subset", # 4
  "token_jaccard",# 5
  "edit_distance" # 6
)

# Kesin (100/95) sayılan katmanlar. Kural 1 YALNIZCA bunlardan birincisine
# aittir; alias ayrı bir politikaya tabidir.
PK_ENTITY_EXACT_TIERS <- c("exact_fold", "alias")

# Katman 5/6 eşikleri. Formülün parçasıdır; yapılandırmayla DEĞİŞTİRİLEMEZ.
.PK_ENTITY_J_FLOOR <- 0.60
.PK_ENTITY_D_CEIL  <- 0.20

# Katman 5/6 formüllerinin TAM SAYI biçimindeki karşılıkları.
#   25 * (i/u - 3/5) / (2/5) = (125*i - 75*u) / (2*u)
#   19 * (dist/len) / (1/5)  = (95*dist) / len
.PK_ENTITY_J_FLOOR_NUM <- 3L   # 0.60 = 3/5
.PK_ENTITY_J_FLOOR_DEN <- 5L

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

#' Jaccard benzerliği (katlanmış belirteç KÜMELERİ üzerinde)
#'
#' Formül küme tabanlıdır ve sözleşmedir. Belirteç ÇOKLUĞU ayrı bir denetimdir
#' (`.pk_entity_multiset_contains()`); burada kasıtlı olarak kullanılmaz.
pk_entity_jaccard <- function(user_tokens, cand_tokens) {
  sayilar <- .pk_entity_jaccard_counts(user_tokens, cand_tokens)
  if (sayilar$union <= 0L) return(0)
  sayilar$intersect / sayilar$union
}

.pk_entity_jaccard_counts <- function(user_tokens, cand_tokens) {
  u <- unique(user_tokens[!is.na(user_tokens) & nzchar(user_tokens)])
  c_ <- unique(cand_tokens[!is.na(cand_tokens) & nzchar(cand_tokens)])

  if (!length(u) || !length(c_)) return(list(intersect = 0L, union = 0L))

  list(
    intersect = length(intersect(u, c_)),
    union = length(union(u, c_))
  )
}

#' Normalleştirilmiş Levenshtein mesafesi
#'
#' @return `d` = mesafe / daha uzun dizginin uzunluğu. Aralık [0, 1].
pk_entity_edit_ratio <- function(a, b) {
  sayilar <- .pk_entity_edit_counts(a, b)
  if (is.null(sayilar)) return(1)
  sayilar$distance / sayilar$length
}

.pk_entity_edit_counts <- function(a, b) {
  if (is.na(a) || is.na(b)) return(NULL)
  if (!nzchar(a) || !nzchar(b)) return(NULL)

  .pk_entity_require_stringdist()

  en_uzun <- max(nchar(a), nchar(b))
  if (en_uzun <= 0L) return(NULL)

  mesafe <- stringdist::stringdist(a, b, method = "lv")
  if (!length(mesafe) || is.na(mesafe)) return(NULL)

  list(distance = as.integer(mesafe), length = as.integer(en_uzun))
}

# --- Katman formülleri --------------------------------------------------------
# `max()`/`min()` kelepçeleri kayan nokta tozuna karşıdır; meşru bir girdi
# hiçbir zaman aralığın dışına çıkmaz (katman koşulu bunu zaten garanti eder).

.pk_entity_tier4_score <- function(j) {
  as.integer(max(85L, min(89L, 85L + floor(4 * j))))
}

# TAM SAYI aritmetiği: i = kesişim, u = birleşim.
.pk_entity_tier5_score_counts <- function(i, u) {
  i <- as.integer(i)
  u <- as.integer(u)
  if (is.na(u) || u <= 0L) return(60L)

  ham <- 60L + (125L * i - 75L * u) %/% (2L * u)
  as.integer(max(60L, min(84L, ham)))
}

.pk_entity_tier5_score <- function(j) {
  # Geriye dönük uyumlu yüzey; oran verildiğinde en yakın tam sayı payda
  # bilinmediği için doğrudan formül kullanılır.
  ham <- 60L + floor(25 * (j - .PK_ENTITY_J_FLOOR) / (1 - .PK_ENTITY_J_FLOOR))
  as.integer(max(60L, min(84L, ham)))
}

# TAM SAYI aritmetiği: dist = düzenleme mesafesi, len = daha uzun dizgi.
.pk_entity_tier6_score_counts <- function(dist, len) {
  dist <- as.integer(dist)
  len <- as.integer(len)
  if (is.na(len) || len <= 0L) return(50L)

  ham <- 69L - (95L * dist) %/% len
  as.integer(max(50L, min(69L, ham)))
}

.pk_entity_tier6_score <- function(d) {
  ham <- 69L - floor(19 * d / .PK_ENTITY_D_CEIL)
  as.integer(max(50L, min(69L, ham)))
}

# Çokluk farkındalı kapsama: kullanıcı belirtecinin GEÇTİĞİ SAYI adayınkini
# aşmamalıdır. "BORA BORA" ile "BORA" farklı kanonik varlıklardır.
.pk_entity_multiset_contains <- function(u, c_) {
  if (!length(u)) return(FALSE)
  for (tok in unique(u)) {
    if (sum(u == tok) > sum(c_ == tok)) return(FALSE)
  }
  TRUE
}

# Sıra korunuyor mu? Varlık adlarında sözcük sırası anlamlıdır:
# "kara deniz" ile "deniz kara" aynı varlık DEĞİLDİR.
.pk_entity_ordered_subsequence <- function(u, c_) {
  i <- 1L
  for (tok in c_) {
    if (i > length(u)) break
    if (identical(tok, u[i])) i <- i + 1L
  }
  i > length(u)
}

# Belirteç katmanları için tek bir gösterim üzerinden karar.
.pk_entity_token_view <- function(u, c_) {
  list(
    contains = .pk_entity_multiset_contains(u, c_),
    ordered = .pk_entity_ordered_subsequence(u, c_),
    counts = .pk_entity_jaccard_counts(u, c_)
  )
}

# Tek bir aday için katman/puan kararı. Eşleşme yoksa NULL döner.
#
# `exact_only` TRUE ise (rol = "id" veya match = "exact") YALNIZCA KAYIPSIZ
# kesin katman çalışır: kodlar ve kimlikler ASLA bulanıklaştırılmaz ve
# noktalama SİLİNMEZ (§5.4 kapanış kuralı). `PRJ 001` ile `PRJ-001` bu yüzden
# eşleşmez.
.pk_entity_tier_of <- function(user_norm, cand_norm, alias_hit = NULL,
                               cand_value = NA_character_, exact_only = FALSE,
                               allow_edit = TRUE) {
  bayraklar <- character(0)

  # Katman 1 — kesin eşleşme.
  # Kesin/id kipinde noktalama KORUNAN anahtar; normal kipte Türkçe ekleri
  # soyulmuş (ama noktalaması korunan) anahtar kullanılır.
  kullanici_kesin <- if (isTRUE(exact_only)) user_norm$exact else user_norm$clitic
  aday_kesin <- if (isTRUE(exact_only)) cand_norm$exact else cand_norm$clitic

  if (!is.na(kullanici_kesin) && !is.na(aday_kesin) &&
      identical(kullanici_kesin, aday_kesin)) {
    return(list(tier = "exact_fold", score = 100L, low_confidence = character(0)))
  }

  # Katman 2 — doğrulanmış alias.
  if (!is.null(alias_hit) && !is.null(alias_hit$target) && !is.na(cand_value)) {
    hedef_norm <- pk_entity_normalize(alias_hit$target)
    if (!is.na(hedef_norm$exact) && identical(hedef_norm$exact, cand_norm$exact)) {
      return(list(
        tier = "alias", score = 95L,
        low_confidence = if (isTRUE(alias_hit$lossy)) "alias_lossy_key" else character(0)
      ))
    }
  }

  if (isTRUE(exact_only)) return(NULL)

  # Katman 3 — kesin ikincil anahtarlar (hepsi 90). Üçü de KAYIPLIDIR ve
  # koşullu olarak bayraklanır.
  #
  # SIRA ÖNEMLİDİR: noktalama denetimi ASCII denetiminden ÖNCE gelir. ASCII
  # anahtarı noktalaması SADELEŞTİRİLMİŞ metinden türetilir; önce ASCII
  # sorulursa `A+B` ile `A/B` ikilisi "yalnızca aksan farkı" gibi görünür ve
  # kayıplılık bayrağı DÜŞMEZ.
  if (!is.na(user_norm$fold) && !is.na(cand_norm$fold) &&
      identical(user_norm$fold, cand_norm$fold)) {
    # Buraya gelindiyse `clitic` anahtarları FARKLIDIR (aynı olsaydı katman 1
    # dönerdi); yani fark gerçekten noktalamadadır: `A+B` ile `A/B`.
    return(list(tier = "punct_key", score = 90L, low_confidence = "punct_lossy"))
  }

  if (!is.na(user_norm$ascii) && !is.na(cand_norm$ascii) &&
      identical(user_norm$ascii, cand_norm$ascii)) {
    # Kullanıcı Türkçe'ye özgü harf YAZDIYSA ASCII katlaması artık eksik
    # harfi tamamlamıyor, BİLGİ SİLİYOR: `KİR` ile `KIR` ayrı varlıklardır.
    if (isTRUE(user_norm$has_turkish)) bayraklar <- c(bayraklar, "ascii_lossy")
    return(list(tier = "ascii_key", score = 90L, low_confidence = bayraklar))
  }

  if (!is.na(user_norm$compact) && !is.na(cand_norm$compact) &&
      (identical(user_norm$compact, cand_norm$compact) ||
       identical(user_norm$ascii_compact, cand_norm$ascii_compact))) {
    # Ayırıcısı düşürülmüş yazım: `F16` <-> `F-16`, `AŞ` <-> `A.Ş.`.
    return(list(tier = "compact_key", score = 90L, low_confidence = "compact_lossy"))
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
  #   Bu yüzden görünüm iki gösterim üzerinden hesaplanır ve İYİSİ alınır:
  #   puan yalnızca ARTABİLİR, hiçbir formül ve katman sırası değişmez.
  gorunumler <- list(.pk_entity_token_view(u, c_))
  if (length(user_norm$tokens_ascii) && length(cand_norm$tokens_ascii)) {
    gorunumler[[2]] <- .pk_entity_token_view(
      user_norm$tokens_ascii, cand_norm$tokens_ascii
    )
  }

  kapsama <- any(vapply(gorunumler, function(g) isTRUE(g$contains), logical(1)))
  sirali <- any(vapply(
    gorunumler, function(g) isTRUE(g$contains) && isTRUE(g$ordered), logical(1)
  ))

  sayilar <- gorunumler[[1]]$counts
  for (g in gorunumler) {
    if (g$counts$union <= 0L) next
    if (sayilar$union <= 0L ||
        g$counts$intersect * sayilar$union > sayilar$intersect * g$counts$union) {
      sayilar <- g$counts
    }
  }
  j <- if (sayilar$union > 0L) sayilar$intersect / sayilar$union else 0

  # Belirteç katmanları SOYULMUŞ gövdelerle çalışır. Soyma olmasaydı eşleşme
  # KURULMAYACAKSA sonuç sezgisel bir adıma bağlıdır ve otomatik kabule uygun
  # DEĞİLDİR ("Mersin" -> "mers" ile "MERS Radar" 89 puana çıkıp AUTO'yu geçer).
  ham_kapsama <- .pk_entity_multiset_contains(user_norm$tokens_raw, cand_norm$tokens_raw)
  ham_j <- pk_entity_jaccard(user_norm$tokens_raw, cand_norm$tokens_raw)

  if (isTRUE(user_norm$has_turkish) &&
      !identical(user_norm$tokens, user_norm$tokens_ascii) &&
      !gorunumler[[1]]$contains && kapsama) {
    bayraklar <- c(bayraklar, "ascii_lossy")
  }

  # Katman 4 — tüm kullanıcı belirteçleri adayda var.
  if (isTRUE(kapsama)) {
    if (!isTRUE(sirali)) bayraklar <- c(bayraklar, "reordered")

    # Tek ve genel bir belirteç ("proje", "radar") kimliklendirici bilgi
    # TAŞIMAZ; kapalı sözlükte tesadüfen tek değerde geçmesi otomatik
    # filtreleme gerekçesi değildir.
    if (length(unique(u)) == 1L && length(unique(c_)) > 1L) {
      bayraklar <- c(bayraklar, "single_token")
    }

    if (!isTRUE(ham_kapsama)) bayraklar <- c(bayraklar, "stem_dependent")

    return(list(
      tier = "token_subset", score = .pk_entity_tier4_score(j),
      low_confidence = unique(bayraklar)
    ))
  }

  # Katman 5 — kısmi belirteç örtüşmesi.
  if (sayilar$union > 0L &&
      sayilar$intersect * .PK_ENTITY_J_FLOOR_DEN >=
        .PK_ENTITY_J_FLOOR_NUM * sayilar$union &&
      sayilar$intersect < sayilar$union) {
    if (ham_j < .PK_ENTITY_J_FLOOR) bayraklar <- c(bayraklar, "stem_dependent")
    return(list(
      tier = "token_jaccard",
      score = .pk_entity_tier5_score_counts(sayilar$intersect, sayilar$union),
      low_confidence = unique(bayraklar)
    ))
  }

  if (!isTRUE(allow_edit)) return(NULL)

  # Katman 6 — düzenleme mesafesi (aynı gerekçeyle aksan duyarsız: daha KÜÇÜK
  # oran daha iyi eşleşmedir, bu yüzden en iyisi alınır).
  adaylar <- list(
    .pk_entity_edit_counts(user_norm$fold, cand_norm$fold),
    .pk_entity_edit_counts(user_norm$ascii, cand_norm$ascii)
  )
  adaylar <- adaylar[!vapply(adaylar, is.null, logical(1))]
  if (!length(adaylar)) return(NULL)

  en_iyi <- adaylar[[1]]
  for (ad in adaylar) {
    if (ad$distance * en_iyi$length < en_iyi$distance * ad$length) en_iyi <- ad
  }

  # 0 < d <= 0.20  <=>  0 < 5*dist <= len
  if (en_iyi$distance > 0L &&
      en_iyi$distance * 5L <= en_iyi$length) {
    return(list(
      tier = "edit_distance",
      score = .pk_entity_tier6_score_counts(en_iyi$distance, en_iyi$length),
      low_confidence = unique(c(bayraklar, "edit_distance"))
    ))
  }

  NULL
}

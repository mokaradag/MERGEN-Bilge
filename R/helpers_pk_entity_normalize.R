# ==============================================================================
# Dosya Yolu: R/helpers_pk_entity_normalize.R
# Açıklama: Faz 4 — varlık çözümleme normalleştirme hattı (master plan §5.4).
#
#           Kullanıcı ifadesini ve kapalı sözlükteki kanonik değerleri AYNI
#           boru hattından geçirir:
#
#             pk_tr_fold() (NFC -> Türkçe küçük harf -> boşluk sadeleştirme)
#               -> kesme işareti ekleri ("ANKA'nın" -> "anka")
#               -> noktalama sadeleştirme
#               -> belirteç (token) kümesi
#               -> YALNIZCA eşleştirme için sonek soyma
#
#           Türkçe katlama TEK KAYNAKTAN gelir: R/helpers_pk_text_turkish.R
#           içindeki `pk_tr_fold()`. Bu dosya katlamayı ne kopyalar ne de
#           yeniden tanımlar (§5.4 açık kuralı).
#
# ÖLÇÜLMÜŞ UYARI — `chartr()` veya elle kod noktası eşlemesi KULLANILMAZ; her
#   ikisi de bu depoda denendi ve UTF-8 olmayan yerelde bayt bazlı çalışıp
#   mojibake ürettiği için reddedildi. ASCII ikincil anahtarı da bu yüzden
#   ICU tabanlı `stringi::stri_replace_all_fixed()` ile üretilir.
#
# Dosya saftır: Shiny/reactive/DB/ağ bağımlılığı yoktur, worker güvenlidir.
# ==============================================================================

# Türkçe'de özel adlara gelen ekler kesme işaretiyle ayrılır. Tüm yaygın
# kesme işareti biçimleri (düz, tipografik, harf-kesme, aksan) kapsanır.
.PK_ENTITY_APOSTROPHES <- c(
  "'",
  intToUtf8(0x2019L),  # tipografik sağ kesme
  intToUtf8(0x02BCL),  # harf olarak kesme
  intToUtf8(0x00B4L),  # aksan
  "`"
)

# ASCII ikincil anahtar eşlemesi (§5.4). Kullanıcılar Türkçe karakter
# yazmadan arama yapar: "kalip" -> "kalıp", "elektronik" -> "elektronİk".
# Katlama zaten küçük harfe indirdiği için yalnızca küçük harf biçimleri gerekir.
.PK_ENTITY_TR_CHARS   <- c("ı", "ş", "ğ", "ü", "ö", "ç")
.PK_ENTITY_ASCII_CHARS <- c("i",      "s",      "g",      "u",      "o",      "c")

# Eşleştirme amaçlı sonek listesi; UZUNDAN KISAYA sıralıdır ki "deki" soneki
# "de"den önce denensin.
#
# BİLEREK DIŞARIDA BIRAKILANLAR:
#   * tek harfli ekler (-i, -ı, -u, -ü, -a, -e): "proje" -> "proj" gibi
#     yıkıcı soymalara yol açar.
#   * iyelik -ım/-im/-um/-üm: "bakım", "onarım", "tasarım", "yatırım" gibi
#     yaygın adlarla çakışır.
# Bu dışarıda bırakmalar ölçülerek seçildi; listeyi genişletmeden önce
# tests/testthat/test-pk-entity-normalize-behavior.R içindeki yanlış-soyma
# vakalarını genişletin.
.PK_ENTITY_SUFFIXES <- c(
  "deki", "daki", "teki", "taki",
  "siyle", "sıyla", "suyla", "süyle",
  "nin", "nın", "nun", "nün",
  "den", "dan", "ten", "tan",
  "lar", "ler",
  "in", "ın", "un", "ün",
  "de", "da", "te", "ta",
  "si", "sı", "su", "sü",
  "ye", "ya", "le", "la"
)

# Soyma sonrası gövde bu uzunluğun altına düşerse sonek soyulmaz. "hatta" ->
# "hat" (3) ve "yolda" -> "yol" (3) gibi yıkıcı soymaları engeller.
.PK_ENTITY_MIN_STEM_NCHAR <- 4L

# Türkçe eklemeli bir dildir ("proje-ler-in-de"); tek geçiş yetmez. Üst sınır
# bilinçlidir: sınırsız soyma gövdeyi aşındırır.
.PK_ENTITY_MAX_STRIPS <- 3L

# Çoğulluk sinyali veren belirteçler (§5.4 kural 3). Yalnızca DAHA ÇOK SORMAYA
# yol açar; yani yanlış pozitif güvenli yöndedir.
.PK_ENTITY_PLURAL_WORDS <- c(
  "tüm", "tümü", "tümünü", "bütün",
  "hepsi", "hepsini", "her", "herhangi", "çeşitli", "farklı",
  "birden", "birkaç", "bazı", "list", "listele", "listesi"
)

.pk_entity_require_stringi <- function() {
  if (!requireNamespace("stringi", quietly = TRUE)) {
    stop(
      paste0(
        "pk_entity_normalize: 'stringi' paketi bulunamadi. Yerelden bagimsiz ",
        "normallestirme yalnizca stringi ile yapilabilir."
      ),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

#' Kesme işareti eklerini at ("ANKA'nın" -> "ANKA")
#'
#' Kesme işaretinden SONRAKİ harfler ekin kendisidir; kanonik ada dâhil
#' değildir. Kesme işareti ve ardından gelen harf dizisi birlikte silinir.
pk_entity_strip_clitics <- function(x) {
  if (is.null(x) || !length(x)) return(character(0))
  .pk_entity_require_stringi()

  metin <- enc2utf8(as.character(x))
  na_maskesi <- is.na(metin)
  metin[na_maskesi] <- ""

  kesme <- paste0("\\Q", .PK_ENTITY_APOSTROPHES, "\\E", collapse = "|")
  desen <- paste0("(", kesme, ")\\p{L}*")

  metin <- stringi::stri_replace_all_regex(metin, desen, "")
  metin[na_maskesi] <- NA_character_
  metin
}

#' Noktalama ve simgeleri tek boşluğa indir
#'
#' Unicode farkındalıdır: Türkçe harfler `\p{L}`, rakamlar `\p{N}` altında
#' korunur; ayırıcı, tire, parantez ve benzeri her şey boşluğa döner.
pk_entity_collapse_punct <- function(x) {
  if (is.null(x) || !length(x)) return(character(0))
  .pk_entity_require_stringi()

  metin <- enc2utf8(as.character(x))
  na_maskesi <- is.na(metin)
  metin[na_maskesi] <- ""

  metin <- stringi::stri_replace_all_regex(metin, "[^\\p{L}\\p{N}]+", " ")
  metin <- stringi::stri_replace_all_regex(metin, "\\s+", " ")
  metin <- trimws(metin)

  metin[na_maskesi] <- NA_character_
  metin
}

#' ASCII ikincil anahtar (§5.4)
#'
#' Girdi ZATEN katlanmış olmalıdır; bu fonksiyon yalnızca Türkçe'ye özgü altı
#' harfi ASCII karşılığına eşler. Tier 3 (90 puan) bu anahtar üzerinden çalışır.
pk_entity_ascii_key <- function(x) {
  if (is.null(x) || !length(x)) return(character(0))
  .pk_entity_require_stringi()

  metin <- enc2utf8(as.character(x))
  na_maskesi <- is.na(metin)
  metin[na_maskesi] <- ""

  metin <- stringi::stri_replace_all_fixed(
    metin,
    .PK_ENTITY_TR_CHARS,
    .PK_ENTITY_ASCII_CHARS,
    vectorize_all = FALSE
  )

  metin[na_maskesi] <- NA_character_
  metin
}

# Tek bir belirteçten en fazla .PK_ENTITY_MAX_STRIPS sonek soyar.
.pk_entity_stem_token <- function(token) {
  if (is.na(token) || !nzchar(token)) return(token)

  govde <- token
  for (tur in seq_len(.PK_ENTITY_MAX_STRIPS)) {
    soyuldu <- FALSE

    for (ek in .PK_ENTITY_SUFFIXES) {
      ek_n <- nchar(ek)
      if (nchar(govde) - ek_n < .PK_ENTITY_MIN_STEM_NCHAR) next
      if (!identical(substring(govde, nchar(govde) - ek_n + 1L), ek)) next

      govde <- substring(govde, 1L, nchar(govde) - ek_n)
      soyuldu <- TRUE
      break
    }

    if (!soyuldu) break
  }

  govde
}

#' Eşleştirme belirteç kümesi
#'
#' Sonek soyma HER İKİ tarafa da (kullanıcı ifadesi ve kanonik aday) aynı
#' şekilde uygulanır; asimetrik soyma sessiz kaçırmalara yol açar.
#'
#' @return Tekrarsız, boş olmayan belirteçlerden oluşan karakter vektörü.
pk_entity_tokens <- function(x, stem = TRUE) {
  if (is.null(x) || !length(x)) return(character(0))

  metin <- as.character(x)[1]
  if (is.na(metin) || !nzchar(metin)) return(character(0))

  parcalar <- strsplit(metin, " ", fixed = TRUE)[[1]]
  parcalar <- parcalar[!is.na(parcalar) & nzchar(parcalar)]
  if (!length(parcalar)) return(character(0))

  if (isTRUE(stem)) {
    parcalar <- vapply(parcalar, .pk_entity_stem_token, character(1), USE.NAMES = FALSE)
    parcalar <- parcalar[!is.na(parcalar) & nzchar(parcalar)]
  }

  unique(parcalar)
}

#' Tam normalleştirme kaydı
#'
#' @return `fold` (kesin anahtar, Tier 1), `ascii` (ikincil anahtar, Tier 3),
#'   `tokens` (soyulmuş belirteç kümesi, Tier 4/5), `raw` (değiştirilmemiş
#'   girdi) ve `blank` (geçersiz/boş girdi bayrağı).
#'
#' NOT — `fold` anahtarı sonek SOYMAZ. Sonek soyma sezgiseldir ve kayıplıdır;
#' 100 puanlık otomatik kabul yolunu sezgisel bir adıma bağlamak yanlış
#' olurdu. Soyma, puanı 89 ile sınırlı olan belirteç katmanlarında çalışır
#' (bkz. ilerleme dosyası, tasarım kararı E2).
pk_entity_normalize <- function(x) {
  ham <- if (is.null(x) || !length(x)) NA_character_ else as.character(x)[1]

  katlanmis <- pk_tr_fold(ham)
  katlanmis <- pk_entity_strip_clitics(katlanmis)
  katlanmis <- pk_entity_collapse_punct(katlanmis)

  if (!length(katlanmis)) katlanmis <- NA_character_
  bos <- is.na(katlanmis) || !nzchar(katlanmis)

  ascii <- if (bos) NA_character_ else pk_entity_ascii_key(katlanmis)

  list(
    raw          = ham,
    fold         = if (bos) NA_character_ else katlanmis,
    ascii        = ascii,
    tokens       = if (bos) character(0) else pk_entity_tokens(katlanmis),
    tokens_ascii = if (bos) character(0) else pk_entity_tokens(ascii),
    blank        = bos
  )
}

#' İfade açıkça çoğul mu? (§5.4 kural 3)
#'
#' Sezgiseldir ve BİLEREK güvenli yöndedir: yanlış pozitif yalnızca kullanıcıya
#' onay sorulmasına yol açar, sessiz bir birleşime değil.
pk_entity_phrase_is_plural <- function(x) {
  normal <- pk_entity_normalize(x)
  if (isTRUE(normal$blank)) return(FALSE)

  # Soyulmamış belirteçler gerekir: soyma "-ler/-lar" ekini zaten atar.
  ham_belirtecler <- pk_entity_tokens(normal$fold, stem = FALSE)
  if (!length(ham_belirtecler)) return(FALSE)

  if (any(ham_belirtecler %in% .PK_ENTITY_PLURAL_WORDS)) return(TRUE)

  cogul_eki <- vapply(
    ham_belirtecler,
    function(tok) {
      if (nchar(tok) < 5L) return(FALSE)
      son <- substring(tok, nchar(tok) - 2L)
      identical(son, "lar") || identical(son, "ler")
    },
    logical(1),
    USE.NAMES = FALSE
  )

  any(cogul_eki)
}

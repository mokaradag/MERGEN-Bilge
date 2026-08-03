# ==============================================================================
# Dosya Yolu: R/helpers_pk_text_turkish.R
# Açıklama: Proje ve Kaynak Analizi için asgari, yerelden BAĞIMSIZ ve NFC
#           normalize eden Türkçe metin katlama yardımcısı.
#
#           Faz 3a bu dosyayı yalnızca metadata/alias anahtarlarını
#           normalleştirmek için kullanır. Faz 4 (varlık çözümleme) aynı
#           `pk_tr_fold()` üzerine kurulacaktır; bu yüzden davranışı tek
#           kaynaktan gelmeli ve sessizce değiştirilmemelidir.
#
# ÖLÇÜLMÜŞ UYARI — burada `chartr()` veya elle kod noktası eşlemesi KULLANILMAZ.
#   Bu depoda her iki yaklaşım da denendi ve BAŞARISIZ bulundu: UTF-8 olmayan
#   bir yerelde (Windows/Türkçe VM veya POSIX/C konteyner) bayt bazlı çalışıp
#   mojibake üretiyor ya da İ/Ş/Ü/Ö/Ç'yi hiç katlamıyorlar. Doğrulanmış tek yol
#   ICU tabanlı `stringi::stri_trans_tolower(x, locale = "tr")`; çıktısının
#   C, C.UTF-8 ve tr_TR.UTF-8 yerellerinde BAYT ÖZDEŞ olduğu ölçülmüştür.
#
# Dosya saftır: Shiny/reactive/DB/ağ bağımlılığı yoktur, worker güvenlidir.
# ==============================================================================

# Türkçe noktalı I'nın ayrışık (decomposed) biçimindeki birleşik nokta.
# `İ` (U+0130) NFC ile yeniden birleşir, ancak KÜÇÜK `i` + U+0307 dizisinin
# önceden birleşmiş bir karşılığı yoktur; NFC onu olduğu gibi bırakır. Bu
# yüzden katlamadan sonra `i`yi takip eden bu işaret ayrıca temizlenir, aksi
# hâlde "İSTANBUL" ile zaten küçük harfe çevrilmiş ayrışık "i̇stanbul" farklı
# anahtarlar üretir ve alias eşleşmesi sessizce kaçar.
.PK_TR_COMBINING_DOT_ABOVE <- intToUtf8(0x0307L)

# stringi olmadan Türkçe katlama YAPILMAZ. Sessiz/yanlış bir yedek yol,
# alias anahtarlarını fark edilmeden bozar; bu da tam olarak planın
# yasakladığı "sessizce yanlış" davranıştır. stringi zaten
# R/config_packages.R içinde zorunlu paket olarak doğrulanır.
.pk_tr_require_stringi <- function() {
  if (!requireNamespace("stringi", quietly = TRUE)) {
    stop(
      paste0(
        "pk_tr_fold: 'stringi' paketi bulunamadi. Turkce katlama yerelden ",
        "bagimsiz olarak yalnizca stringi ile yapilabilir; sessiz bir yedek ",
        "yol alias anahtarlarini bozar."
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

#' Türkçe metni yerelden bağımsız biçimde katla (fold)
#'
#' Sıra bilinçlidir: NFC -> Türkçe küçük harf -> ayrışık nokta temizliği ->
#' boşluk sadeleştirme. NFC önce gelir ki ayrışık `I` + U+0307 dizisi `İ`
#' olarak birleşsin ve Türkçe küçük harf kuralı doğru uygulansın.
#'
#' @param x Karakter vektörü (veya karaktere çevrilebilir bir vektör).
#' @return Aynı uzunlukta, katlanmış karakter vektörü. `NA` girdiler `NA`
#'   olarak korunur.
pk_tr_fold <- function(x) {
  if (is.null(x) || length(x) == 0L) return(character(0))

  .pk_tr_require_stringi()

  metin <- enc2utf8(as.character(x))
  na_maskesi <- is.na(metin)
  metin[na_maskesi] <- ""

  metin <- stringi::stri_trans_nfc(metin)
  metin <- stringi::stri_trans_tolower(metin, locale = "tr")

  # `i` + birleşik nokta -> `i`
  metin <- gsub(
    paste0("i", .PK_TR_COMBINING_DOT_ABOVE),
    "i",
    metin,
    fixed = TRUE,
    useBytes = FALSE
  )

  # Baş/son boşluk ve iç boşluk dizilerini tek boşluğa indir.
  metin <- gsub("[[:space:]]+", " ", metin, perl = TRUE)
  metin <- trimws(metin)

  metin[na_maskesi] <- NA_character_
  enc2utf8(metin)
}

#' Katlanmış metnin boş olup olmadığını güvenli biçimde kontrol et
#'
#' Metadata doğrulamasında sık kullanılır: `NA`, `NULL` ve yalnızca boşluktan
#' oluşan anahtarların hepsi "boş" sayılır.
pk_tr_fold_is_blank <- function(x) {
  katlanmis <- pk_tr_fold(x)
  if (!length(katlanmis)) return(TRUE)
  is.na(katlanmis) | !nzchar(katlanmis)
}

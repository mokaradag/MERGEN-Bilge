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
# hâlde "İSTANBUL" ile zaten küçük harfe çevrilmiş ayrışık biçim ("i" + U+0307
# ile yazılmış "istanbul") farklı anahtarlar üretir ve alias eşleşmesi sessizce
# kaçar. (Ayrışık biçim burada BİLEREK harfi harfine yazılmaz: U+0307
# WINDOWS-1254'te temsil edilemez ve Windows VM'de dosyayı bozar.)
.PK_TR_COMBINING_DOT_ABOVE <- intToUtf8(0x0307L)

# stringi olmadan Türkçe katlama YAPILMAZ. Sessiz/yanlış bir yedek yol,
# alias anahtarlarını fark edilmeden bozar; bu da tam olarak planın
# yasakladığı "sessizce yanlış" davranıştır. stringi zaten
# R/config_packages.R içinde zorunlu paket olarak doğrulanır.
.pk_tr_require_stringi <- function() {
  if (!requireNamespace("stringi", quietly = TRUE)) {
    stop(
      paste0(
        "pk_tr_fold: 'stringi' paketi bulunamadı. Türkçe katlama yerelden ",
        "bağımsız olarak yalnızca stringi ile yapılabilir; sessiz bir yedek ",
        "yol alias anahtarlarını bozar."
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
  #
  # BOŞLUK SADELEŞTİRME DE ICU ÜZERİNDEN YAPILIR: `perl = TRUE` altında PCRE'nin
  # `[[:space:]]` sınıfı ASCII'dir ve U+00A0 gibi Unicode ayırıcıları KATLAMAZ.
  # Elektronik tablodan/web sayfasından yapıştırılan bir alias değeri bu yüzden
  # `pk_tr_fold("elektronik\u00A0harp")` ile `pk_tr_fold("elektronik harp")`
  # arasında SESSİZCE eşleşmiyordu -- bu yardımcının tam da engellediği durum.
  metin <- stringi::stri_replace_all_regex(metin, "[\\p{Z}\\s]+", " ")
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

# Türkçe CP1254 baytları Latin-1/CP1252 olarak çözüldüğünde ı/ş/ğ/İ/Ş/Ğ harfleri
# Latin-1 karşılıklarına (U+00FD/U+00FE/U+00F0/U+00DD/U+00DE/U+00D0) dönüşür
# (ör. Latin1 harmanlamalı sütunda saklanmış Türkçe metin NVARCHAR okunduğunda).
# Bu harfler İzlandaca/Faroece gibi dillerde gerçek harf olduğundan onarım
# SÜTUN düzeyinde kanıta bağlıdır (x tek sütun kabul edilir):
#   * Sütundaki her ASCII dışı harf, CP1254 Türkçe baytlarının Latin-1
#     görüntüsünde bulunabilen harflerdendir (ç ö ü â î û ve büyükleri ile altı
#     benzer harf). á/í/ó/ø/æ gibi başka harf ya da gerçek ı/ş/ğ görülürse sütun
#     doğru çözülmüştür ve DOKUNULMAZ.
#   * Türkçe kanıtı vardır: ı/İ karşılığı (U+00FD/U+00DD) ya da İzlandaca ve
#     Faroecede bulunmayan ç/ü (ve büyükleri).
# Dönüşüm ICU (stringi) ile yerelden bağımsızdır. ODBC'nin kayıplı en-yakın
# dönüşümü ("y"/"?") ONARILAMAZ.
repair_turkish_latin1_letters <- function(x) {
  if (is.null(x) || !is.character(x) || !length(x)) return(x)
  if (!requireNamespace("stringi", quietly = TRUE)) return(x)

  kaynak <- intToUtf8(c(0x00FDL, 0x00FEL, 0x00F0L, 0x00DDL, 0x00DEL, 0x00D0L))
  hedef <- intToUtf8(c(0x0131L, 0x015FL, 0x011FL, 0x0130L, 0x015EL, 0x011EL))
  ortak <- intToUtf8(c(0x00E7L, 0x00F6L, 0x00FCL, 0x00E2L, 0x00EEL, 0x00FBL,
                       0x00C7L, 0x00D6L, 0x00DCL, 0x00C2L, 0x00CEL, 0x00DBL))
  kanit <- intToUtf8(c(0x00FDL, 0x00DDL, 0x00E7L, 0x00C7L, 0x00FCL, 0x00DCL))
  utf8 <- enc2utf8(x)
  gecerli <- !is.na(utf8) & validUTF8(utf8)
  if (!any(gecerli)) return(x)
  sutun <- utf8[gecerli]

  aday <- stringi::stri_detect_regex(sutun, paste0("[", kaynak, "]"))
  if (!any(aday)) return(x)
  yabanci <- paste0("[[\\p{L}\\p{M}]--[\\x{00}-\\x{7F}", kaynak, ortak, "]]")
  if (any(stringi::stri_detect_regex(sutun, yabanci))) return(x)
  if (!any(stringi::stri_detect_regex(sutun, paste0("[", kanit, "]")))) return(x)

  onarilacak <- gecerli
  onarilacak[gecerli] <- aday
  x[onarilacak] <- stringi::stri_trans_char(utf8[onarilacak], kaynak, hedef)
  x
}

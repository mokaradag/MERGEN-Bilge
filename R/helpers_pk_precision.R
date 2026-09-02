# ==============================================================================
# Dosya Yolu: R/helpers_pk_precision.R
# Açıklama: integer64 KESİNLİK koruması (saf karar katmanı).
#
#           2^53 üstündeki tam sayılar `as.numeric()` ile TEMSİL EDİLEMEZ;
#           sessiz yuvarlama, kanonik bir olgunun YANLIŞ değer yayımlamasına
#           yol açar. Denetim bu yüzden TAM ONDALIK METİN üzerinde yapılır.
#
#           Dosya bilerek SAFTIR: Shiny/reaktif/DB/ağ/LLM bağımlılığı YOKTUR.
#           Yükleme sırası: `R/helpers_pk_packet_stats.R` dosyasından ÖNCE.
# ==============================================================================

# KESİNLİK DENETİMİ, DENETLEDİĞİ DÖNÜŞÜMÜ KENDİSİ YAPMAMALIDIR.
#
# `as.numeric(as.character(values))` 9007199254740993 değerini ZATEN tam olarak
# 2^53'e yuvarlar; ardından gelen `> 2^53` karşılaştırması FALSE döner ve
# kesinlik kaybı fark edilmeden 9007199254740992 kanonik olgu olarak
# yayımlanırdı. Karşılaştırma bu yüzden TAM ONDALIK METİN üzerinde yapılır:
# işaretsiz basamak sayısı ve sözlüksel karşılaştırma kayıpsızdır.
.PK_SAFE_INT_TEXT <- "9007199254740992"   # 2^53

.pk_int_text_exceeds_safe <- function(txt) {
  metin <- as.character(txt %||% "")
  metin <- trimws(metin)
  metin <- sub("^[+-]", "", metin)
  gecerli <- !is.na(metin) & grepl("^[0-9]+$", metin)
  if (!any(gecerli)) return(FALSE)

  metin <- sub("^0+(?=[0-9])", "", metin[gecerli], perl = TRUE)
  n <- nchar(metin)
  guvenli <- .PK_SAFE_INT_TEXT
  any(n > nchar(guvenli) | (n == nchar(guvenli) & metin > guvenli))
}

.pk_precision_loss <- function(values) {
  if (!inherits(values, "integer64")) return(FALSE)
  .pk_int_text_exceeds_safe(as.character(values))
}

# INTEGER64 FİLTRE KARŞILAŞTIRMASI.
#
# `is.numeric()` `bit64::integer64` için TRUE döner; bu yüzden bir `bigint`
# sütunu v1 filtresinin sayısal dalına düşüyor ve `as.numeric(val_str)` değeri
# 2^53'te YUVARLIYORDU. Filtre o zaman yanlış satırı tutuyor ya da hiç satır
# tutmuyor, analiz de boş/yanlış bir popülasyon yayımlıyordu. Karşılaştırma
# değeri bu yüzden `integer64` olarak üretilir; tam sayı OLMAYAN bir metin
# yaprağı DÜŞÜRÜR (sessizce yuvarlanmaz).
#
# @return `ok` (karşılaştırma yapılabilir mi) ve `value` alanlı liste.
pk_filter_numeric_operand <- function(col_vals, val_str) {
  metin <- trimws(as.character(val_str %||% "")[1])
  # EKSİK/BOŞ SKALER ÖNCE ELENİR: `NA_character_` ya da `character(0)` geldiğinde
  # `metin` `NA` olur, `grepl()` `NA` döner ve `if` "missing value where
  # TRUE/FALSE needed" ile PATLARDI.
  if (length(metin) != 1L || is.na(metin) || !nzchar(metin)) {
    return(list(ok = FALSE, value = NULL))
  }

  if (inherits(col_vals, "integer64") && requireNamespace("bit64", quietly = TRUE)) {
    if (!grepl("^[+-]?[0-9]+$", metin)) {
      return(list(ok = FALSE, value = NULL))
    }
    deger <- tryCatch(bit64::as.integer64(metin), error = function(e) NULL)
    if (is.null(deger) || is.na(deger)) return(list(ok = FALSE, value = NULL))
    return(list(ok = TRUE, value = deger))
  }

  deger <- suppressWarnings(as.numeric(metin))
  if (length(deger) != 1L || is.na(deger)) return(list(ok = FALSE, value = NULL))
  list(ok = TRUE, value = deger)
}

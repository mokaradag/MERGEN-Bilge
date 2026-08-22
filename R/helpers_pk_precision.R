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

# ==============================================================================
# Dosya Yolu: R/helpers_pk_ascii_tokens.R
# Açıklama: MAKİNE / PROTOKOL belirteçleri için yerelden BAĞIMSIZ ASCII katlama.
#
#           Bu dosya bilerek `R/helpers_pk_text_turkish.R`den AYRIDIR. O dosya
#           İNSAN metnini katlar (İ/Ş/Ü/Ö/Ç kuralları + boşluk sadeleştirme) ve
#           `chartr()` kullanımı orada ÖLÇÜLEREK başarısız bulunmuş, sözleşme
#           testiyle yasaklanmıştır. Buradaki belirteçler ise saf ASCII'dir
#           (işlem adı, motor kipi, şema tipi, yapılandırma bayrağı, hata
#           işareti) ve onlar için doğru araç `chartr()`dır.
#
#           `tolower()` NEDEN KULLANILAMAZ: Türkçe Windows yerelinde
#           `tolower("I")` noktasız `ı` üretir. `CONTAINS` sessizce `contaıns`,
#           `POSIXct` sessizce `posıxct` olur; hiçbir eşleşme listesiyle uyuşmaz
#           ve sonuç SESSİZ YANLIŞ davranıştır (yanlış filtre, yanlış şema rolü,
#           yanlış yapılandırma, VM ile CI arasında farklı olgu kimliği).
#
#           Dosya saftır: Shiny/reactive/DB/ağ bağımlılığı yoktur.
# ==============================================================================

#' ASCII A-Z aralığında yerelden bağımsız küçük harf.
pk_ascii_lower <- function(x) {
  if (is.null(x)) return(character(0))
  chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", as.character(x))
}

#' Makine belirtecini karşılaştırmaya hazırla: kırp + ASCII küçük harf.
pk_ascii_token <- function(x) {
  pk_ascii_lower(trimws(x))
}

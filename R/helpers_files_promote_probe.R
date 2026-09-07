# ==============================================================================
# Dosya Yolu: R/helpers_files_promote_probe.R
# Açıklama: Terfi adımının SAF görünürlük yoklama yardımcıları.
#
# NEDEN AYRI DOSYA: `R/helpers_files_promote_target.R` 130 satır / 6 fonksiyon
# bakım bütçesindedir. Terfi sonucunun `promoted` (hedefi bu çağrı oluşturdu mu)
# alanıyla ayrıştırılması ve yoklamaların hata güvenli hâle getirilmesi oraya
# sığmıyordu; bütçe gevşetmek yerine yoklama yardımcıları buraya alındı ve
# `R/helpers_files_promote_target.R` dosyasından ÖNCE yüklenir.
#
# SÖZLEŞME:
#   * Bu dosya Shiny, reactive state, DB veya ağ bağımlılığı İÇERMEZ.
#   * Yoklama HATA FIRLATMAZ: geçici bir UNC/izin hatası terfi sonrasında
#     istisna üretip dosyayı kayıtsız bırakıyordu.
# ==============================================================================

# Görünürlük deneme sayısını güvenli bir tam sayıya indirger (NA/Inf/metin ->
# varsayılan). `as.integer(NA)` sonrası `seq_len()` hata fırlatıyordu.
mergen_promote_attempt_count <- function(deger, varsayilan = 10L) {
  sayi <- suppressWarnings(as.integer(deger)[1])
  if (length(sayi) != 1L || is.na(sayi) || sayi < 1L) return(as.integer(varsayilan))
  sayi
}

# Yoklama HATA GÜVENLİDİR. `var_mi()` geçici bir UNC/izin hatasında istisna
# fırlatabilir; bu istisna terfi TAMAMLANDIKTAN sonra oluştuğunda fonksiyon
# `ok`/`yabanci` döndüremiyor ve terfi edilmiş dosya kayıtsız yetim kalıyordu.
mergen_promote_probe <- function(var_mi, path) {
  isTRUE(tryCatch(var_mi(path), error = function(e) FALSE))
}

# UNC/ağ paylaşımında yeni oluşan dosya bir süre görünmeyebilir. Yoklama
# SINIRLIDIR; görünürse TRUE, bütçe biterse son gözlem döner.
mergen_promote_wait_visible <- function(path, var_mi, denemeler = 10L) {
  denemeler <- mergen_promote_attempt_count(denemeler)
  for (i in seq_len(denemeler)) {
    if (mergen_promote_probe(var_mi, path)) return(TRUE)
    Sys.sleep(0.02)
  }
  mergen_promote_probe(var_mi, path)
}

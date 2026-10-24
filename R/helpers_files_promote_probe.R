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

# Windows yol sınırları UTF-16 birimleriyle, POSIX sınırları baytla ölçülür.
mergen_artifact_path_units <- function(path) {
  path <- enc2utf8(as.character(path)[1])
  if (.Platform$OS.type == "windows")
    length(iconv(path, "UTF-8", "UTF-16LE", toRaw = TRUE)[[1]]) / 2 else nchar(path, type = "bytes")
}

# Staging ve terfi rezervasyonu aynı adlandırmayı paylaşır; kalıcı ad değişmez.
mergen_upload_artifact_path <- function(final_dest, suffix, component_only = FALSE) {
  hedef <- as.character(final_dest)[1]
  ad <- enc2utf8(basename(hedef))
  uzunluk <- mergen_artifact_path_units(ad)
  if (uzunluk > 255L) stop("Hedef dosya adı dosya sistemi sınırını aşıyor.")
  original <- paste0(hedef, suffix)
  compact <- if (component_only) uzunluk + nchar(suffix) > 255L else
    nchar(ad, type = "bytes") > 180L ||
      (.Platform$OS.type == "windows" && mergen_artifact_path_units(original) > 240L)
  if (!compact) return(original)
  key <- if (.Platform$OS.type == "windows") tolower(ad) else ad
  candidate <- file.path(dirname(hedef), paste0(".mergen-",
    digest::digest(key, algo = "xxhash64", serialize = FALSE), suffix))
  if (mergen_artifact_path_units(candidate) < mergen_artifact_path_units(original)) candidate else original
}

# Değişebilir boyut/mtime yerine fiziksel dosya anahtarı; belirsizlikte yetki yok.
.mergen_promote_file_key <- function(path) {
  info <- tryCatch(fs::file_info(path), error = function(e) NULL)
  if (is.null(info) || NROW(info) != 1L || !isTRUE(is.finite(info$device_id)) ||
      !isTRUE(is.finite(info$inode) && info$inode > 0)) return(NULL)
  as.list(info[c("device_id", "inode")])
}

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

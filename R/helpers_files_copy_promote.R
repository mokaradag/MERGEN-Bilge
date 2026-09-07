# ==============================================================================
# Dosya Yolu: R/helpers_files_copy_promote.R
# Açıklama: Kalıcı kullanıcı klasörüne AŞAMALI (staging) kopyalama sınırı.
#
# NEDEN AYRI DOSYA: eksik/bozuk bir kopya KALICI adla diskte kaldığında sonraki
# dosya listelemesi onu geçerli bir yükleme gibi gösteriyordu. Kopya önce
# `.mergen-part` adına yapılır, boyut doğrulandıktan SONRA kalıcı ada terfi
# ettirilir; doğrulama geçmezse KALICI AD HİÇ OLUŞMAZ. R/helpers_files.R bakım
# borcu tavanındadır; bu yüzden aşamalama burada tutulur ve ondan ÖNCE yüklenir.
# ==============================================================================

# Staging dosyası kalıcı hedefle AYNI dizinde durur: aynı birim üzerinde
# `file.rename()` terfisi mümkün olur, yarım kopya başka bir kökte kalmaz.
MERGEN_UPLOAD_STAGING_SUFFIX <- ".mergen-part"

mergen_upload_staging_path <- function(final_dest) {
  paste0(as.character(final_dest)[1], MERGEN_UPLOAD_STAGING_SUFFIX)
}

# Kaynağı staging adına kopyalar, boyutu doğrular, kalıcı ada terfi ettirir.
# Başarıda kalıcı yolu döndürür; her hata yolunda staging temizlenip `stop()`.
mergen_copy_upload_staged <- function(datapath, final_dest, base_root,
                                      upload_name = "",
                                      exists_fn = path_exists_relaxed,
                                      gorunurluk_denemesi = 10L) {
  hedef <- as.character(final_dest)[1]
  staging <- mergen_upload_staging_path(hedef)
  var_mi <- function(p) isTRUE(tryCatch(exists_fn(p), error = function(e) FALSE))
  # Başarılı kopya Windows/UNC paylaşımında bir süre GÖRÜNMEYEBİLİR. Anında
  # yapılan `var_mi(staging)` denetimi bu durumda yeni bir kopya denemesi
  # başlatıyor ya da hata yoluna düşüyordu: yükleme başarısız oluyor ve
  # indekslenmemiş bir `.mergen-part` dosyası diskte kalabiliyordu.
  gorunur_mu <- function(p) {
    isTRUE(mergen_promote_wait_visible(p, var_mi, gorunurluk_denemesi))
  }

  temizle <- function(p) {
    # Kök DIŞINA silme yapılmaz: yol tabanlı `unlink()` ata bileşenlerini izler.
    if (!var_mi(p)) return(invisible(FALSE))
    if (!isTRUE(mergen_path_inside_root(p, base_root))) return(invisible(FALSE))
    try(unlink(p, force = TRUE), silent = TRUE)
    invisible(!var_mi(p))
  }

  # Üç kademeli kopya (fs -> base -> native kodlama) ayrı yardımcıdadır:
  # görünürlük yarışında İLK başarının korunması ve BENİMSENMEYEN native adayın
  # temizliği bu dosyanın bakım bütçesine sığmıyordu.
  kopya <- mergen_stage_upload_copy(
    datapath = datapath,
    hedef = hedef,
    staging = staging,
    var_mi = var_mi,
    gorunur_mu = gorunur_mu,
    temizle = temizle
  )
  staging <- kopya$staging
  hedef <- kopya$hedef

  if (!isTRUE(kopya$ok) || !var_mi(staging)) {
    temizle(staging)
    # MUTLAK YOL loglanmaz (CWE-532): sunucu dosya düzeni hata mesajına sızmasın
    # diye yalnızca dosya adı yazılır.
    stop(sprintf("Kopyalanamadı: %s (dosya oluşmadı)", basename(hedef)))
  }

  # Boyut DOĞRULANAMAZSA terfi edilmez: `file.info()$size` NA döndüğünde eski kod
  # denetimi atlayıp doğrulanmamış bir kopyayı kalıcı ada taşıyordu.
  kaynak_boyut <- suppressWarnings(file.info(datapath)$size)
  staging_boyut <- suppressWarnings(file.info(staging)$size)
  boyut_ok <- length(kaynak_boyut) == 1L && length(staging_boyut) == 1L &&
    is.finite(kaynak_boyut) && is.finite(staging_boyut) &&
    isTRUE(staging_boyut == kaynak_boyut)
  if (!boyut_ok) {
    if (!isTRUE(temizle(staging))) {
      cat("[copy_to_mcp_base] UYARI: Bozuk staging dosyası silinemedi\n")
    }
    stop(sprintf("Kopyalanan dosya eksik/bozuk (kaynak=%s bayt, hedef=%s bayt): %s",
                 format(kaynak_boyut), format(staging_boyut), upload_name))
  }

  # TERFİ, OLUŞTURMA anlamlıdır; DEĞİŞTİRME değil. `R/helpers_files.R` var OLMAYAN
  # bir aday seçer, ancak `tempfile()` adı SÜREÇLER ARASINDA rezerve etmez: iki
  # çağrı aynı boş `hedef` adını seçebilir. Terfi bu yüzden sahiplik kanıtlı
  # yardımcıya devredilir (`file.link()` -> rezervasyon -> `file.rename()`).
  if (var_mi(hedef)) {
    temizle(staging)
    stop(sprintf("Kalıcı hedef zaten var; üzerine yazılmadı: %s", basename(hedef)))
  }

  terfi_sonuc <- mergen_promote_staged_file(
    staging = staging,
    hedef = hedef,
    var_mi = var_mi,
    gorunurluk_denemesi = gorunurluk_denemesi
  )

  if (isTRUE(terfi_sonuc$promoted)) {
    # TERFİ TAMAMLANDI. `ok` yalnızca görünürlük yoklamasının sonucudur ve
    # yavaş bir UNC paylaşımında `FALSE` dönebilir; bu durumda hedefi silmek
    # BAŞARIYLA yüklenmiş dosyayı yok ediyordu (staging adı da düşürülmüştü,
    # yani yükleme geri alınamıyordu). Görünürlük gecikmesi yalnızca uyarıdır.
    if (!isTRUE(terfi_sonuc$ok)) {
      cat(sprintf(
        "[copy_to_mcp_base] UYARI: terfi tamamlandı, hedef henüz görünmüyor: %s\n",
        basename(hedef)
      ))
    }
    return(hedef)
  }

  if (!isTRUE(terfi_sonuc$ok)) {
    # Yarıda kalan hedefi YALNIZCA bu çağrı oluşturmuş olabilir; EŞZAMANLI
    # beliren hedef `yabanci` olarak işaretlenir ve DOKUNULMAZ.
    if (!isTRUE(terfi_sonuc$yabanci)) temizle(hedef)
    temizle(staging)
    stop(sprintf("Kopyalanan dosya kalıcı ada taşınamadı: %s", basename(hedef)))
  }

  hedef
}

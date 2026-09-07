# ==============================================================================
# Dosya Yolu: R/helpers_files_copy_promote.R
# Açıklama: Kalıcı kullanıcı klasörüne AŞAMALI (staging) kopyalama sınırı.
#
# NEDEN AYRI DOSYA: eksik/bozuk bir kopya KALICI adla diskte kaldığında sonraki
# dosya listelemesi onu geçerli bir yükleme gibi gösteriyordu (Windows'ta hedef
# kilitliyken `unlink()` başarısız olabilir ve eski kod yalnızca uyarı yazıp
# yarım dosyayı kalıcı adında bırakıyordu). Kopya önce `.mergen-part` adına
# yapılır, boyut doğrulandıktan SONRA kalıcı ada terfi ettirilir; doğrulama
# geçmezse KALICI AD HİÇ OLUŞMAZ.
#
# R/helpers_files.R bakım borcu tavanındadır; bu yüzden aşamalama mantığı burada
# tutulur ve o dosyadan ÖNCE yüklenir.
# ==============================================================================

# Staging dosyası kalıcı hedefle AYNI dizinde durur: aynı birim üzerinde
# `file.rename()` ile terfi mümkün olur ve yarım kopya başka bir kökte kalmaz.
MERGEN_UPLOAD_STAGING_SUFFIX <- ".mergen-part"

mergen_upload_staging_path <- function(final_dest) {
  paste0(as.character(final_dest)[1], MERGEN_UPLOAD_STAGING_SUFFIX)
}

# Kaynağı `final_dest` için staging adına kopyalar, boyutu doğrular ve kalıcı
# ada terfi ettirir. Başarıda kalıcı yolu döndürür; her hata yolunda staging
# temizlenir ve `stop()` çağrılır.
mergen_copy_upload_staged <- function(datapath,
                                      final_dest,
                                      base_root,
                                      upload_name = "",
                                      exists_fn = path_exists_relaxed) {
  hedef <- as.character(final_dest)[1]
  staging <- mergen_upload_staging_path(hedef)

  var_mi <- function(p) isTRUE(tryCatch(exists_fn(p), error = function(e) FALSE))

  temizle <- function(p) {
    # Kök DIŞINA silme yapılmaz: yol tabanlı `unlink()` ata bileşenlerini izler.
    if (!var_mi(p)) return(invisible(FALSE))
    if (!isTRUE(mergen_path_inside_root(p, base_root))) return(invisible(FALSE))
    try(unlink(p, force = TRUE), silent = TRUE)
    invisible(!var_mi(p))
  }

  # Önce fs::file_copy dene, başarısız olursa base::file.copy ile yedek deneme yap.
  kopya_ok <- tryCatch({
    fs::file_copy(datapath, staging, overwrite = TRUE)
    TRUE
  }, error = function(e) {
    cat(sprintf("[copy_to_mcp_base] fs::file_copy başarısız: %s\n", conditionMessage(e)))
    FALSE
  })

  if (!isTRUE(kopya_ok) || !var_mi(staging)) {
    cat(sprintf("[copy_to_mcp_base] Yedek yol: base::file.copy deneniyor: %s -> %s\n",
                datapath, staging))
    kopya_ok <- tryCatch(
      file.copy(datapath, staging, overwrite = TRUE),
      error = function(e) {
        cat(sprintf("[copy_to_mcp_base] base::file.copy de başarısız: %s\n", conditionMessage(e)))
        FALSE
      }
    )
  }

  if (!var_mi(staging)) {
    # Son çare: locale farklarından kaynaklı sorunlar için enc2native ile dene.
    staging_native <- tryCatch(enc2native(staging), error = function(e) staging)
    if (!identical(staging_native, staging)) {
      cat(sprintf("[copy_to_mcp_base] Native encoding ile yeniden deneniyor: %s\n", staging_native))
      tryCatch(file.copy(datapath, staging_native, overwrite = TRUE), error = function(e) NULL)
      if (var_mi(staging_native) && !var_mi(staging)) {
        staging <- staging_native
        hedef <- tryCatch(enc2native(hedef), error = function(e) hedef)
      }
    }
  }

  if (!var_mi(staging)) {
    temizle(staging)
    stop(sprintf("Kopyalanamadı: %s -> %s (dosya oluşmadı, fs=%s)",
                 datapath, hedef, as.character(kopya_ok)))
  }

  kaynak_boyut <- suppressWarnings(file.info(datapath)$size)
  staging_boyut <- suppressWarnings(file.info(staging)$size)
  if (!is.na(kaynak_boyut) && !is.na(staging_boyut) && staging_boyut != kaynak_boyut) {
    cat(sprintf("[copy_to_mcp_base] HATA: Boyut uyuşmazlığı! kaynak=%d, hedef=%d\n",
                kaynak_boyut, staging_boyut))
    if (!isTRUE(temizle(staging))) {
      cat("[copy_to_mcp_base] UYARI: Bozuk staging dosyası silinemedi\n")
    }
    stop(sprintf("Kopyalanan dosya eksik/bozuk (kaynak=%d bayt, hedef=%d bayt): %s",
                 kaynak_boyut, staging_boyut, upload_name))
  }

  # TERFİ: doğrulanmış staging dosyası kalıcı ada taşınır. `file.rename()`
  # Windows kilidinde ya da birim farkında başarısız olabilir; o durumda
  # kopyala + staging'i sil yoluna düşülür.
  terfi <- tryCatch(file.rename(staging, hedef), error = function(e) FALSE)
  if (!isTRUE(terfi) || !var_mi(hedef)) {
    terfi <- tryCatch(file.copy(staging, hedef, overwrite = TRUE), error = function(e) FALSE)
    if (isTRUE(terfi)) temizle(staging)
  }

  if (!isTRUE(terfi) || !var_mi(hedef)) {
    temizle(staging)
    stop(sprintf("Kopyalanan dosya kalıcı ada taşınamadı: %s", hedef))
  }

  hedef
}

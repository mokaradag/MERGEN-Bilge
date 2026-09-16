# ==============================================================================
# Dosya Yolu: R/helpers_files_staging_copy.R
# Açıklama: Yüklemenin AŞAMALI (staging) KOPYA adımı: `fs::file_copy()` ->
#           `base::file.copy()` -> native-kodlama yedeği.
#
# NEDEN AYRI DOSYA: `R/helpers_files_copy_promote.R` 130 satır bakım
# bütçesindedir. Üç kademeli kopya yedeği, görünürlük yarışında İLK başarının
# korunması ve BENİMSENMEYEN native adayın temizliği oraya sığmıyordu; bütçe
# gevşetmek yerine kopya adımı buraya alındı ve
# `R/helpers_files_copy_promote.R` dosyasından ÖNCE yüklenir.
#
# SÖZLEŞME:
#   * Dönen liste: ok, staging (benimsenen yol), hedef (native takasta güncellenir).
#   * İLK kopyanın başarısı YEDEK denemede KAYBEDİLMEZ: `fs::file_copy()`
#     başarılıyken yalnızca UNC görünürlüğü geciktiği için başlayan yedek deneme
#     `FALSE` döndüğünde, diskte görünür hâle gelen GEÇERLİ staging dosyası
#     "başarısız" sayılıp siliniyordu.
#   * BENİMSENMEYEN native aday TEMİZLENİR: aksi hâlde kalıcı kullanıcı
#     klasöründe her yeniden denemede indekslenmemiş bir `.mergen-part` yetimi
#     birikiyordu.
#   * Tanılama mesajları MUTLAK YOL taşımaz (CWE-532): sunucu dosya düzeni
#     loglara sızmasın diye yalnızca dosya ADI yazılır. Türkçe dosya adlarının
#     loglarda okunabilir kalması CLAUDE.md gereğidir ve korunur.
# ==============================================================================

mergen_stage_upload_copy <- function(datapath, hedef, staging, var_mi, gorunur_mu,
                                     temizle) {
  ad <- basename(as.character(staging)[1])

  kopya_ok <- tryCatch({
    fs::file_copy(datapath, staging, overwrite = TRUE)
    TRUE
  }, error = function(e) {
    cat(sprintf("[copy_to_mcp_base] fs::file_copy başarısız: %s\n", ad))
    FALSE
  })

  if (!isTRUE(kopya_ok) || !gorunur_mu(staging)) {
    cat(sprintf("[copy_to_mcp_base] Yedek yol: base::file.copy deneniyor: %s\n", ad))
    yedek_ok <- tryCatch(file.copy(datapath, staging, overwrite = TRUE),
                         error = function(e) {
                           cat(sprintf("[copy_to_mcp_base] base::file.copy de başarısız: %s\n", ad))
                           FALSE
                         })
    # İLK kopyanın başarısı korunur; yedek yalnızca EKLER.
    kopya_ok <- isTRUE(yedek_ok) || (isTRUE(kopya_ok) && gorunur_mu(staging))
  }

  if (!gorunur_mu(staging)) {
    # Son çare: locale farklarından kaynaklı sorunlar için enc2native ile dene.
    staging_native <- tryCatch(enc2native(staging), error = function(e) staging)
    if (!identical(staging_native, staging)) {
      cat(sprintf("[copy_to_mcp_base] Native encoding ile yeniden deneniyor: %s\n",
                  basename(staging_native)))
      native_ok <- tryCatch(file.copy(datapath, staging_native, overwrite = TRUE),
                            error = function(e) FALSE)
      if (isTRUE(native_ok) && gorunur_mu(staging_native) && !var_mi(staging)) {
        staging <- staging_native
        hedef <- tryCatch(enc2native(hedef), error = function(e) hedef)
        kopya_ok <- TRUE
      } else {
        # Aday BENİMSENMEDİ: bırakılırsa hiçbir kod yolu onu silmez.
        temizle(staging_native)
      }
    }
  }

  list(ok = isTRUE(kopya_ok), staging = staging, hedef = hedef)
}

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

# Doğrudan kopyalar da aynı sahip rezervasyonunu alır; farklı yazar staging'i ezemez.
mergen_copy_upload_direct <- function(datapath, hedef, base_root, upload_name,
                                      exists_fn, gorunurluk_denemesi) {
  journal <- tempfile("ingest_direct_")
  tx <- list(id = basename(journal), journal = journal, direct = TRUE)
  completed <- FALSE
  on.exit({
    cleanup <- try({
      result <- suppressWarnings(tryCatch(readRDS(journal), error = function(e) NULL))
      cleaned <- completed
      if (!completed && is.list(result) && identical(result$artifact_id, tx$id)) {
        cleaned <- isTRUE(tryCatch({
          if (!isTRUE(mergen_path_inside_root(result$dest, base_root)) ||
              !isTRUE(mergen_path_inside_root(result$staging, base_root))) stop("Kopya temizliği kök dışında.")
          file_ingestion_discard_results(list(result))
          TRUE
        }, error = function(e) FALSE))
      }
      if (cleaned && is.list(result) && identical(result$artifact_id, tx$id) && !path_exists_relaxed(result$staging)) {
        marker <- file_ingestion_owner_path(result$dest)
        if (identical(file_ingestion_read_owner(result$dest)$id, tx$id))
          unlink(c(marker, paste0(marker, ".identity")), force = TRUE)
        if (!identical(file_ingestion_read_owner(result$dest)$id, tx$id)) unlink(journal, force = TRUE)
      }
    }, silent = TRUE)
    if ((inherits(cleanup, "try-error") || path_exists_relaxed(journal)) && exists("log_warn", mode = "function"))
      try(log_warn("Doğrudan kopya temizliği tamamlanamadı; işlem günlüğü korunuyor."), silent = TRUE)
  }, add = TRUE)
  result <- mergen_copy_upload_staged(datapath, hedef, base_root, upload_name, exists_fn,
    gorunurluk_denemesi, transaction = tx)
  completed <- TRUE
  result
}

mergen_stage_upload_copy <- function(datapath, hedef, staging, var_mi, gorunur_mu,
                                     temizle, rebind = NULL) {
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
      if (is.function(rebind)) {
        temizle(staging)
        if (var_mi(staging)) stop("Önceki staging temizlenemedi; native kopya başlatılmadı.")
        kopya_ok <- FALSE
        rebind(tryCatch(enc2native(hedef), error = function(e) hedef), staging_native)
        staging <- staging_native
        hedef <- tryCatch(enc2native(hedef), error = function(e) hedef)
      }
      native_ok <- tryCatch(file.copy(datapath, staging_native, overwrite = TRUE),
                            error = function(e) FALSE)
      if (isTRUE(native_ok) && gorunur_mu(staging_native) && (identical(staging_native, staging) || !var_mi(staging))) {
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

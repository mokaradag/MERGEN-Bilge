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
# Kalıcı kanıt klasördeki sahip marker'ıdır (yeniden denemede geri kazanılır);
# oturum geçici günlüğü yalnız bu çağrının çalışma notudur ve her çıkışta silinir.
mergen_copy_upload_direct <- function(datapath, hedef, base_root, upload_name,
                                      exists_fn, gorunurluk_denemesi) {
  journal <- tempfile("ingest_direct_")
  tx <- list(id = basename(journal), journal = journal, direct = TRUE)
  completed <- FALSE
  on.exit({
    result <- suppressWarnings(tryCatch(readRDS(journal), error = function(e) NULL))
    ours <- is.list(result) && identical(result$artifact_id, tx$id)
    cleanup <- try(if (ours) {
      # Yayınlanan dosya sentetik işleme bağlı kalmaz; artık staging adı yayın kopyasıdır.
      if (!completed) {
        if (!isTRUE(mergen_path_inside_root(result$dest, base_root)) ||
            !isTRUE(mergen_path_inside_root(result$staging, base_root))) stop("Kopya temizliği kök dışında.")
        file_ingestion_discard_results(list(result))
      }
      if (identical(file_ingestion_read_owner(result$dest)$id, tx$id) &&
          (completed || !path_exists_relaxed(result$staging))) {
        marker <- file_ingestion_owner_path(result$dest)
        unlink(c(marker, paste0(marker, ".identity")), force = TRUE)
      }
    }, silent = TRUE)
    unlink(journal, force = TRUE)
    kalan <- ours && isTRUE(tryCatch(identical(file_ingestion_read_owner(result$dest)$id, tx$id),
      error = function(e) TRUE))
    kopya_adi <- basename(if (ours) result$dest else hedef)
    if ((inherits(cleanup, "try-error") || kalan) && exists("log_warn", mode = "function"))
      try(log_warn("Doğrudan kopya temizliği tamamlanamadı; sahiplik kanıtı korunuyor: {kopya_adi}"),
        silent = TRUE)
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

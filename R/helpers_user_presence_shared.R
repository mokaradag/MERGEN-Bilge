# ==============================================================================
# Dosya Yolu: R/helpers_user_presence_shared.R
# Açıklama: Çok-süreçli dağıtımda (tools/run_mergen_workers.R) varlık defterinin
#           süreçler arası paylaşımı. Her uygulama süreci kendi oturum satırlarını
#           paylaşılan dizine yayımlar; Çevrimiçi sekmesi tüm süreçleri birleştirir.
#           Tek süreçte (varsayılan) hiçbir dosya yazılmaz.
# ==============================================================================

# Paylaşılan dizin: MERGEN_PRESENCE_SHARED_DIR ya da çok-süreçli dağıtımda
# süreçlerin zaten ortak kullandığı günlük log dizini altındaki `presence`.
mb_presence_shared_dir <- function() {
  acik <- trimws(Sys.getenv("MERGEN_PRESENCE_SHARED_DIR", ""))
  if (nzchar(acik)) return(acik)
  n <- suppressWarnings(as.integer(Sys.getenv("MERGEN_APP_WORKER_COUNT", "1")))
  if (!isTRUE(n > 1L)) return("")
  kok <- get0("mergen_log_dir", envir = globalenv(), ifnotfound = "")
  if (!is.character(kok) || length(kok) != 1L || is.na(kok) || !nzchar(kok)) return("")
  file.path(kok, "presence")
}

mb_presence_process_id <- function() {
  gsub("[^A-Za-z0-9_.-]", "_", paste0(Sys.info()[["nodename"]], "_", Sys.getpid()))
}

# Bu sürecin oturum satırlarını atomik olarak yayımlar (en fazla `aralik`
# saniyede bir; nabız ve oturum sonu tetikler).
mb_presence_publish <- function(active_env = mb_presence_env(".mergen_active_sessions"),
                                history_env = mb_presence_env(".mergen_presence_history"),
                                now = Sys.time(), aralik = 30) {
  dizin <- mb_presence_shared_dir()
  if (!nzchar(dizin)) return(invisible(FALSE))
  durum <- mb_presence_env(".mergen_presence_publish")
  if (is.numeric(durum$son) && as.numeric(now) - durum$son < aralik) return(invisible(FALSE))
  durum$son <- as.numeric(now)
  sonuc <- tryCatch({
    dir.create(dizin, recursive = TRUE, showWarnings = FALSE)
    hedef <- file.path(dizin, paste0("presence_", mb_presence_process_id(), ".rds"))
    gecici <- paste0(hedef, ".", basename(tempfile("")), ".tmp")
    saveRDS(list(generated_at = as.numeric(now),
                 rows = mb_presence_session_rows(active_env, history_env, now)), gecici)
    # Windows'ta hedef varken yeniden adlandırma başarısızdır; önce kaldırılır.
    if (!file.rename(gecici, hedef)) {
      unlink(hedef)
      if (!file.rename(gecici, hedef)) unlink(gecici)
    }
    file.exists(hedef)
  }, error = function(e) FALSE)
  invisible(isTRUE(sonuc))
}

# Diğer süreçlerin yayımladığı satırlar. Durum güncel zamana göre yeniden
# hesaplanır; yayını `publish_stale` saniyeden eski süreç kapanmış sayılır ve
# açık oturumları son nabız anında "ayrıldı" olur. 24 saatten eski dosya silinir.
mb_presence_remote_rows <- function(now = Sys.time()) {
  dizin <- mb_presence_shared_dir()
  if (!nzchar(dizin) || !dir.exists(dizin)) return(NULL)
  pencere <- mb_presence_windows()
  simdi <- as.numeric(now)
  kendi <- paste0("presence_", mb_presence_process_id(), ".rds")
  dosyalar <- list.files(dizin, pattern = "^presence_.*\\.rds$", full.names = TRUE)
  satirlar <- lapply(dosyalar[basename(dosyalar) != kendi], function(yol) {
    kayit <- tryCatch(readRDS(yol), error = function(e) NULL)
    if (!is.list(kayit) || !is.data.frame(kayit$rows)) return(NULL)
    yas <- simdi - suppressWarnings(as.numeric(kayit$generated_at %||% NA))[1]
    if (!isTRUE(is.finite(yas))) return(NULL)
    if (yas > pencere$history) {
      try(unlink(yol), silent = TRUE)
      return(NULL)
    }
    r <- kayit$rows
    acik <- r$status != "ayrildi"
    nabiz <- simdi - r$last_seen
    r$status[acik] <- ifelse(yas > pencere$publish_stale | nabiz[acik] > pencere$stale, "ayrildi",
                             ifelse(nabiz[acik] <= pencere$online, "cevrimici", "sessiz"))
    r
  })
  satirlar <- Filter(Negate(is.null), satirlar)
  if (!length(satirlar)) NULL else do.call(rbind, satirlar)
}

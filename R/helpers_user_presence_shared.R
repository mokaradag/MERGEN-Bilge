# ==============================================================================
# Dosya Yolu: R/helpers_user_presence_shared.R
# Açıklama: Çok-süreçli dağıtımda (tools/run_mergen_workers.R) varlık defterinin
#           süreçler arası paylaşımı. Her uygulama süreci kendi oturum satırlarını
#           paylaşılan dizine yayımlar; Çevrimiçi sekmesi tüm süreçleri birleştirir.
#           Tek süreçte (varsayılan) hiçbir dosya yazılmaz.
# ==============================================================================

# Paylaşılan dizin: MERGEN_PRESENCE_SHARED_DIR ya da çok-süreçli dağıtımda
# makineye YEREL geçici dizin. Varlık dosyaları Shiny olay döngüsünde okunup
# yazıldığından varsayılan hedef UNC/ağ paylaşımı (log dizini) değildir; yavaş
# paylaşım tüm oturumları dondurmaz. Açık değer de yerel bir dizin olmalıdır.
mb_presence_shared_dir <- function() {
  acik <- trimws(Sys.getenv("MERGEN_PRESENCE_SHARED_DIR", ""))
  if (nzchar(acik)) return(acik)
  n <- suppressWarnings(as.integer(Sys.getenv("MERGEN_APP_WORKER_COUNT", "1")))
  if (!isTRUE(n > 1L)) return("")
  uygulama <- gsub("[^A-Za-z0-9_.-]", "_",
                   basename(normalizePath(getwd(), winslash = "/", mustWork = FALSE)))
  file.path(dirname(tempdir()), paste0("mergen_presence_", uygulama))
}

mb_presence_process_id <- function() {
  gsub("[^A-Za-z0-9_.-]", "_", paste0(Sys.info()[["nodename"]], "_", Sys.getpid()))
}

# Bu sürecin oturum satırlarını yayımlar. Olağan nabız en fazla `aralik`
# saniyede bir yazar; kimlik değişimi ve oturum sonu `zorla = TRUE` ile hemen
# yazar. Aralık yalnız BAŞARILI yayından sonra işler; başarısız yayın 5 sn
# sonra yeniden denenir. Yenileme başarısız olursa son sağlam anlık görüntü
# korunur ve geçici dosya bırakılmaz.
mb_presence_publish <- function(active_env = mb_presence_env(".mergen_active_sessions"),
                                history_env = mb_presence_env(".mergen_presence_history"),
                                now = Sys.time(), aralik = 30, zorla = FALSE) {
  dizin <- mb_presence_shared_dir()
  if (!nzchar(dizin)) return(invisible(FALSE))
  durum <- mb_presence_env(".mergen_presence_publish")
  simdi <- as.numeric(now)
  if (!isTRUE(zorla) && ((is.numeric(durum$son) && simdi - durum$son < aralik) ||
                         (is.numeric(durum$hata) && simdi - durum$hata < 5))) {
    return(invisible(FALSE))
  }
  hedef <- file.path(dizin, paste0("presence_", mb_presence_process_id(), ".rds"))
  gecici <- paste0(hedef, ".", basename(tempfile("")), ".tmp")
  eski <- paste0(hedef, ".bak")
  on.exit(unlink(gecici), add = TRUE)
  sonuc <- tryCatch(suppressWarnings({
    dir.create(dizin, recursive = TRUE, showWarnings = FALSE)
    saveRDS(list(generated_at = simdi,
                 rows = mb_presence_session_rows(active_env, history_env, now)), gecici)
    if (file.rename(gecici, hedef)) {
      TRUE
    } else {
      # Windows'ta hedef varken yeniden adlandırma başarısızdır: eski sürüm
      # kenara alınır, yeni dosya konamazsa geri yüklenir.
      unlink(eski)
      if (file.exists(hedef) && file.rename(hedef, eski)) {
        tamam <- file.rename(gecici, hedef)
        if (tamam) unlink(eski) else file.rename(eski, hedef)
        tamam
      } else {
        FALSE
      }
    }
  }), error = function(e) FALSE)
  if (isTRUE(sonuc)) durum$son <- simdi else durum$hata <- simdi
  invisible(isTRUE(sonuc))
}

.MB_PRESENCE_COLUMNS <- c("user_id", "status", "started_at", "last_seen", "full_name",
                          "username", "sicil", "department", "mudurluk")

# Tek bir uzak anlık görüntüyü okur ve doğrular. Şema dışı/bozuk dosya yalnız
# kendisi atlanır; saat kayması payından fazla gelecekteki yayın ya da satır
# çevrimiçi sayılmaz. 24 saatten eski dosya, okumadan beri değişmediyse silinir.
.mb_presence_read_snapshot <- function(yol, simdi, pencere) {
  once <- file.info(yol)[, c("size", "mtime")]
  kayit <- readRDS(yol)
  if (!is.list(kayit) || !is.data.frame(kayit$rows) ||
      !all(.MB_PRESENCE_COLUMNS %in% names(kayit$rows))) {
    return(NULL)
  }
  yas <- simdi - suppressWarnings(as.numeric(kayit$generated_at %||% NA))[1]
  if (!isTRUE(is.finite(yas)) || yas < -pencere$skew) return(NULL)
  if (yas > pencere$history) {
    if (identical(once, file.info(yol)[, c("size", "mtime")])) try(unlink(yol), silent = TRUE)
    return(NULL)
  }
  r <- kayit$rows[.MB_PRESENCE_COLUMNS]
  r$user_id <- vapply(as.list(r$user_id), mb_presence_uid, integer(1))
  for (alan in c("started_at", "last_seen")) r[[alan]] <- suppressWarnings(as.numeric(r[[alan]]))
  for (alan in setdiff(.MB_PRESENCE_COLUMNS, c("user_id", "started_at", "last_seen"))) {
    deger <- as.character(r[[alan]])
    deger[is.na(deger)] <- ""
    r[[alan]] <- deger
  }
  r <- r[is.finite(r$last_seen) & r$last_seen - simdi <= pencere$skew, , drop = FALSE]
  acik <- r$status != "ayrildi"
  nabiz <- simdi - r$last_seen
  r$status[acik] <- ifelse(yas > pencere$publish_stale | nabiz[acik] > pencere$stale, "ayrildi",
                           ifelse(nabiz[acik] <= pencere$online, "cevrimici", "sessiz"))
  r
}

# Diğer süreçlerin yayımladığı satırlar. Durum güncel zamana göre yeniden
# hesaplanır; yayını `publish_stale` saniyeden eski süreç kapanmış sayılır ve
# açık oturumları son nabız anında "ayrıldı" olur. Sonuç 10 sn önbelleklenir;
# her yeniden çizim dizini yeniden taramaz.
mb_presence_remote_rows <- function(now = Sys.time()) {
  dizin <- mb_presence_shared_dir()
  if (!nzchar(dizin) || !dir.exists(dizin)) return(NULL)
  simdi <- as.numeric(now)
  onbellek <- mb_presence_env(".mergen_presence_remote_cache")
  if (identical(onbellek$dizin, dizin) && is.numeric(onbellek$zaman) &&
      abs(simdi - onbellek$zaman) < 10) {
    return(onbellek$satirlar)
  }
  pencere <- mb_presence_windows()
  kendi <- paste0("presence_", mb_presence_process_id(), ".rds")
  dosyalar <- list.files(dizin, pattern = "^presence_.*\\.rds$", full.names = TRUE)
  satirlar <- lapply(dosyalar[basename(dosyalar) != kendi], function(yol) {
    tryCatch(.mb_presence_read_snapshot(yol, simdi, pencere), error = function(e) NULL)
  })
  satirlar <- Filter(function(r) is.data.frame(r) && nrow(r), satirlar)
  sonuc <- if (!length(satirlar)) NULL else do.call(rbind, satirlar)
  onbellek$dizin <- dizin
  onbellek$zaman <- simdi
  onbellek$satirlar <- sonuc
  sonuc
}

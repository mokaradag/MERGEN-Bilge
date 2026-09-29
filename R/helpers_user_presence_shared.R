# ==============================================================================
# Dosya Yolu: R/helpers_user_presence_shared.R
# Açıklama: Çok-süreçli dağıtımda (tools/run_mergen_workers.R) varlık defterinin
#           süreçler arası paylaşımı. Her uygulama süreci kendi oturum satırlarını
#           paylaşılan dizine yayımlar; Çevrimiçi sekmesi tüm süreçleri birleştirir.
#           Tek süreçte (varsayılan) hiçbir dosya yazılmaz.
# ==============================================================================

# Paylaşılan dizin: MERGEN_PRESENCE_SHARED_DIR ya da çok-süreçli dağıtımda
# makineye YEREL geçici dizin. Varlık dosyaları Shiny olay döngüsünde okunup
# yazıldığından hedef UNC/ağ paylaşımı olamaz (yavaş paylaşım tüm oturumları
# dondurur); UNC değeri reddedilir ve yerel varsayılan kullanılır. Varsayılan,
# uygulama kökünün tam yolunun özetiyle adlandırılır: bu makinede aynı kökten
# çalışan tüm başlatıcılar paylaşır, aynı klasör adlı başka dağıtım karışmaz.
# Çevrimiçi görünümü makine başınadır. Başlatıcıyla açılan her süreç (tek
# işçili başlatıcı dahil; MERGEN_APP_WORKER_INDEX) yayına katılır.
mb_presence_shared_dir <- function() {
  acik <- trimws(Sys.getenv("MERGEN_PRESENCE_SHARED_DIR", ""))
  if (nzchar(acik) && .mb_presence_local_dir(acik)) return(acik)
  n <- suppressWarnings(as.integer(Sys.getenv("MERGEN_APP_WORKER_COUNT", "1")))
  if (!isTRUE(n > 1L) && !nzchar(trimws(Sys.getenv("MERGEN_APP_WORKER_INDEX", "")))) return("")
  kok <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  # Büyük/küçük harf yalnız Windows'ta eşdeğerdir; POSIX'te farklı kökler ayrı kalır.
  if (.Platform$OS.type == "windows") kok <- tolower(kok)
  ozet <- if (requireNamespace("digest", quietly = TRUE)) {
    substr(digest::digest(kok, algo = "xxhash64", serialize = FALSE), 1L, 12L)
  } else {
    gsub("[^A-Za-z0-9]", "_", kok)
  }
  file.path(dirname(tempdir()),
            paste0("mergen_presence_", gsub("[^A-Za-z0-9_.-]", "_", basename(kok)), "_", ozet))
}

# Açık dizin yalnız yerel sürücüdeyse kabul edilir: UNC yazımı ve Windows'ta
# eşlenmiş ağ sürücüsü (ör. Z:) reddedilir. Sürücü türü süreç başına bir kez
# (yerelleştirilmemiş .NET DriveType ile) sorulur; sorulamazsa reddedilir.
.mb_presence_local_dir <- function(yol) {
  if (grepl("^(\\\\\\\\|//)", yol)) return(FALSE)
  if (.Platform$OS.type != "windows") return(TRUE)
  tam <- normalizePath(yol, winslash = "\\", mustWork = FALSE)
  surucu <- toupper(substr(tam, 1L, 2L))
  if (!grepl("^[A-Z]:$", surucu)) return(FALSE)
  turler <- mb_presence_env(".mergen_presence_drive_type")
  if (is.null(turler[[surucu]])) {
    cikti <- tryCatch(suppressWarnings(system2(
      "powershell", c("-NoProfile", "-NonInteractive", "-Command",
                      sprintf("[System.IO.DriveInfo]::new('%s').DriveType", surucu)),
      stdout = TRUE, stderr = FALSE, timeout = 10
    )), error = function(e) character(0))
    turler[[surucu]] <- identical(trimws(cikti[nzchar(trimws(cikti))])[1], "Fixed")
  }
  isTRUE(turler[[surucu]])
}

# Paylaşılan dizin yalnız süreç sahibince okunur (Unix 0700/0600); anlık
# görüntüler ad, sicil ve oturum bilgisi taşır. İzin kurulamazsa yayın yapılmaz.
.mb_presence_secure_dir <- function(dizin) {
  dir.create(dizin, recursive = TRUE, showWarnings = FALSE, mode = "0700")
  if (.Platform$OS.type == "windows") return(dir.exists(dizin))
  Sys.chmod(dizin, mode = "0700", use_umask = FALSE)
  isTRUE(format(file.info(dizin)$mode) == "700")
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
  eski_umask <- Sys.umask("077")
  on.exit(Sys.umask(eski_umask), add = TRUE)
  sonuc <- tryCatch(suppressWarnings({
    if (!.mb_presence_secure_dir(dizin)) stop("varlık dizini sahip-yalnız değil")
    saveRDS(list(generated_at = simdi,
                 rows = mb_presence_session_rows(active_env, history_env, now)), gecici)
    if (file.rename(gecici, hedef)) {
      unlink(eski)
      TRUE
    } else if (file.exists(hedef)) {
      # Windows'ta hedef varken yeniden adlandırma başarısızdır: eski sürüm
      # kenara alınır, yeni dosya konamazsa geri yüklenir.
      unlink(eski)
      if (file.rename(hedef, eski)) {
        tamam <- file.rename(gecici, hedef)
        if (tamam) unlink(eski) else file.rename(eski, hedef)
        tamam
      } else {
        FALSE
      }
    } else {
      # Hedef yokken kalan yedek son sağlam kopyadır: silinmez, geri yüklenir.
      if (file.exists(eski)) file.rename(eski, hedef)
      FALSE
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
  # Geçersiz başlangıç son nabza çekilir; kullanıcının süresi NA olmaz.
  bas_gecersiz <- !is.finite(r$started_at) | r$started_at > r$last_seen
  r$started_at[bas_gecersiz] <- r$last_seen[bas_gecersiz]
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
  dosyalar <- list.files(dizin, pattern = "^presence_.*\\.rds(\\.bak)?$", full.names = TRUE)
  # Windows değiştirme penceresinde ya da yayıncı bu arada çöktüyse asıl dosya
  # yoktur: son sağlam `.bak` okunur.
  yedek <- grepl("\\.bak$", dosyalar)
  dosyalar <- dosyalar[!yedek | !(sub("\\.bak$", "", dosyalar) %in% dosyalar[!yedek])]
  satirlar <- lapply(dosyalar[!sub("\\.bak$", "", basename(dosyalar)) %in% kendi], function(yol) {
    tryCatch(.mb_presence_read_snapshot(yol, simdi, pencere), error = function(e) NULL)
  })
  satirlar <- Filter(function(r) is.data.frame(r) && nrow(r), satirlar)
  sonuc <- if (!length(satirlar)) NULL else do.call(rbind, satirlar)
  onbellek$dizin <- dizin
  onbellek$zaman <- simdi
  onbellek$satirlar <- sonuc
  sonuc
}

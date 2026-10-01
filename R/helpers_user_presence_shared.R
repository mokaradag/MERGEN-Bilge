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
.MB_PRESENCE_DIRECTORY <- new.env(parent = emptyenv())
mb_presence_shared_dir <- function() {
  if (isTRUE(.MB_PRESENCE_DIRECTORY$ready)) return(.MB_PRESENCE_DIRECTORY$path)

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
  yol <- file.path(dirname(tempdir()),
            paste0("mergen_presence_", gsub("[^A-Za-z0-9_.-]", "_", basename(kok)), "_", ozet))
  if (.mb_presence_local_dir(yol)) yol else ""
}

# Açık dizin yalnız yerel sürücüdeyse kabul edilir: UNC yazımı ve Windows'ta
# eşlenmiş ağ sürücüsü (ör. Z:) reddedilir. Sürücü türü süreç başına bir kez
# (yerelleştirilmemiş .NET DriveType ile) sorulur; sorulamazsa reddedilir.
.mb_presence_local_dir <- function(yol) {
  if (grepl("^(\\\\\\\\|//)", yol)) return(FALSE)
  if (.Platform$OS.type != "windows") return(.mb_presence_posix_local(yol))
  if (!isTRUE(.MB_PRESENCE_DIRECTORY$initializing)) return(FALSE)
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
  if (.Platform$OS.type == "windows") {
    if (isTRUE(.MB_PRESENCE_DIRECTORY$ready)) {
      return(identical(dizin, .MB_PRESENCE_DIRECTORY$path) && nzchar(dizin) && dir.exists(dizin))
    }
    if (!isTRUE(.MB_PRESENCE_DIRECTORY$initializing)) return(FALSE)
    dir.create(dizin, recursive = TRUE, showWarnings = FALSE)
    return(.mb_presence_windows_acl(dizin))
  }
  if (!dir.exists(dizin)) dir.create(dizin, recursive = TRUE, showWarnings = FALSE, mode = "0700")
  ata <- normalizePath(dirname(dizin), winslash = "/", mustWork = TRUE)
  dogrudan <- file.path(ata, basename(dizin))
  if (!identical(normalizePath(dizin, winslash = "/", mustWork = TRUE), dogrudan) ||
      nzchar(Sys.readlink(dizin)) || !isTRUE(file.info(dizin)$uid == file.info(tempdir())$uid)) return(FALSE)
  Sys.chmod(dizin, mode = "0700", use_umask = FALSE)
  isTRUE(format(file.info(dizin)$mode) == "700")
}

# Ağ bağlama noktası en uzun yol eşleşmesiyle belirlenir; bilinmeyen tür reddedilir.
.mb_presence_posix_local <- function(yol, mounts = "/proc/self/mountinfo") {
  if (!file.exists(mounts)) return(FALSE)
  satirlar <- tryCatch(readLines(mounts, warn = FALSE), error = function(e) character(0))
  yerel <- function(tam) {
    bol <- strsplit(satirlar, " - ", fixed = TRUE)
    dizinler <- vapply(bol, function(x) {
      alan <- strsplit(x[1], " ", fixed = TRUE)[[1]]
      if (length(alan) < 5L) return("")
      y <- alan[5]
      for (kod in c("040", "011", "012", "134")) {
        y <- gsub(paste0(intToUtf8(92L), kod), intToUtf8(strtoi(kod, 8L)), y, fixed = TRUE)
      }
      y
    }, character(1))
    aday <- which(nzchar(dizinler) & (tam == dizinler | startsWith(tam, paste0(sub("/$", "", dizinler), "/"))))
    if (!length(aday)) return(FALSE)
    k <- aday[which.max(nchar(dizinler[aday]))]
    if (length(bol[[k]]) != 2L) return(FALSE)
    tur <- strsplit(bol[[k]][2], " ", fixed = TRUE)[[1]][1]
    tur %in% c("ext2", "ext3", "ext4", "xfs", "btrfs", "tmpfs", "ramfs", "overlay", "zfs")
  }
  tam <- if (startsWith(yol, "/")) yol else file.path(getwd(), yol)
  if (!yerel(tam)) return(FALSE)
  # Sembolik bağlantı ve .. hedefi de yerel olmalıdır; yalnız açılışta çalışır.
  ata <- tam
  while (!file.exists(ata) && !identical(dirname(ata), ata)) ata <- dirname(ata)
  yerel(normalizePath(ata, winslash = "/", mustWork = FALSE))
}

.mb_presence_windows_acl <- function(dizin) {
  yol <- gsub("'", "''", dizin, fixed = TRUE)
  komut <- paste0(
    "$ErrorActionPreference='Stop'; $p='", yol, "'; ",
    "$sid=[System.Security.Principal.WindowsIdentity]::GetCurrent().User; ",
    "$acl=Get-Acl -LiteralPath $p; $acl.SetOwner($sid); ",
    "$acl.SetAccessRuleProtection($true,$false); ",
    "@($acl.Access) | ForEach-Object { [void]$acl.RemoveAccessRuleSpecific($_) }; ",
    "$rule=New-Object System.Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow'); ",
    "$acl.AddAccessRule($rule); Set-Acl -LiteralPath $p -AclObject $acl; ",
    "$check=Get-Acl -LiteralPath $p; ",
    "if (!$check.AreAccessRulesProtected -or $check.GetOwner([System.Security.Principal.SecurityIdentifier]).Value -ne $sid.Value) { exit 1 }; ",
    "if (@($check.Access | Where-Object { $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value -ne $sid.Value }).Count -ne 0) { exit 1 }; ",
    "Write-Output 'secure'")
  sonuc <- tryCatch(suppressWarnings(system2("powershell",
    c("-NoProfile", "-NonInteractive", "-Command", shQuote(komut)),
    stdout = TRUE, stderr = FALSE, timeout = 10)), error = function(e) character(0))
  is.null(attr(sonuc, "status")) && identical(trimws(sonuc), "secure")
}

# Sürücü ve izin kontrolleri oturum kabulünden önce yapılır.
mb_presence_initialize <- function() {
  .MB_PRESENCE_DIRECTORY$ready <- FALSE
  .MB_PRESENCE_DIRECTORY$initializing <- TRUE
  on.exit({ .MB_PRESENCE_DIRECTORY$initializing <- FALSE }, add = TRUE)
  dizin <- tryCatch(mb_presence_shared_dir(), error = function(e) "")
  guvenli <- nzchar(dizin) && isTRUE(tryCatch(.mb_presence_secure_dir(dizin), error = function(e) FALSE))
  .MB_PRESENCE_DIRECTORY$path <- if (guvenli) dizin else ""
  .MB_PRESENCE_DIRECTORY$ready <- TRUE
  invisible(guvenli)
}

.MB_PRESENCE_BOOT_ID <- basename(tempfile("boot-"))
mb_presence_process_id <- function() {
  gsub("[^A-Za-z0-9_.-]", "_", paste0(Sys.info()[["nodename"]], "_", Sys.getpid(), "_", .MB_PRESENCE_BOOT_ID))
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

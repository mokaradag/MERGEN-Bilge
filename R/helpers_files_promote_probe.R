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
mergen_upload_artifact_key <- function(name) {
  name <- enc2utf8(name)
  if (.Platform$OS.type == "windows") tolower(name) else name
}

mergen_upload_artifact_path <- function(final_dest, suffix, component_only = FALSE) {
  hedef <- as.character(final_dest)[1]
  ad <- enc2utf8(basename(hedef))
  uzunluk <- mergen_artifact_path_units(ad)
  if (uzunluk > 255L) stop("Hedef dosya adı dosya sistemi sınırını aşıyor.")
  original <- paste0(hedef, suffix)
  # Var olan rezervasyon yeni bir hash adıyla atlanamaz; canlı sahip korunur.
  if (component_only && dir.exists(original)) return(original)
  fits <- function(path) {
    quarantine <- if (exists("mergen_reservation_quarantine_path", mode = "function", inherits = TRUE))
      mergen_reservation_quarantine_path(path, unique = FALSE) else paste0(path, ".q-q", strrep("0", 16L))
    max(mergen_artifact_path_units(basename(path)), mergen_artifact_path_units(basename(quarantine))) <= 255L &&
      (.Platform$OS.type != "windows" || max(mergen_artifact_path_units(file.path(path, "owner")),
        mergen_artifact_path_units(file.path(quarantine, "owner"))) <= 259L)
  }
  compact <- if (component_only) !fits(original) else
    nchar(ad, type = "bytes") > 180L ||
      (.Platform$OS.type == "windows" && mergen_artifact_path_units(original) > 240L)
  if (!compact) return(original)
  key <- mergen_upload_artifact_key(ad)
  candidate <- file.path(dirname(hedef), paste0(".mergen-",
    digest::digest(key, algo = "xxhash64", serialize = FALSE), suffix))
  selected <- if (mergen_artifact_path_units(candidate) < mergen_artifact_path_units(original)) candidate else original
  if (component_only && !fits(selected)) stop("Rezervasyon yolu dosya sistemi sınırını aşıyor.")
  selected
}

# Şerit kilitleri kullanıcı klasöründe değil, indeksin yanındaki iç dizindedir:
# listeleme/kova temizliği onları görmez, canlı kilit inode'u silinip bölünmez.
mergen_upload_lock_dir <- function() {
  dir <- as.character(getOption("mergen.upload_lock_dir", ""))[1]
  index <- if (exists("MERGEN_INDEX_PATH", inherits = TRUE)) as.character(MERGEN_INDEX_PATH)[1] else ""
  if (!nzchar(dir) && !is.na(index) && nzchar(index)) dir <- paste0(index, ".upload-locks")
  if (!nzchar(dir)) dir <- file.path(dirname(tempdir()),
    paste0("mergen-upload-locks-", gsub("[^A-Za-z0-9_-]", "_", Sys.info()[["user"]])))
  dir
}

# Bu yalnız geçici dışlama anahtarıdır; POSIX hedef/marker kimliği değişmez.
# Kanonik dizin + harf eşleri aynı şeride girer; en çok 4096 kalıcı kilit oluşur.
mergen_upload_mutex_path <- function(path) {
  dir <- tryCatch(normalizePath(dirname(path), winslash = "/", mustWork = TRUE),
    error = function(e) gsub("\\", "/", dirname(path), fixed = TRUE))
  # LC_CTYPE kilit kimliğini değiştiremez; katlama yalnız fazla dışlama üretir.
  key <- stringi::stri_trans_nfkc_casefold(enc2utf8(c(dir, basename(path))))
  key <- stringi::stri_trans_nfkc_casefold(stringi::stri_trans_toupper(key, locale = "en"))
  hash <- digest::digest(paste(key, collapse = "\n"), algo = "xxhash64", serialize = FALSE)
  file.path(mergen_upload_lock_dir(), paste0("lane-", substr(hash, 1L, 3L), ".lock"))
}

# Şerit çakışması hata değildir: canlı tutucu bütçe boyunca beklenir. Kilit
# dosyası açılamıyorsa ya da şerit boşken edinilemiyorsa beklenmeden reddedilir.
mergen_upload_lane_lock <- function(path, wait_sec = getOption("mergen.upload_lane_wait_sec", 120)) {
  lock <- mergen_upload_mutex_path(path)
  if (!dir.exists(dirname(lock))) dir.create(dirname(lock), recursive = TRUE, showWarnings = FALSE)
  deadline <- Sys.time() + wait_sec
  free <- 0L
  repeat {
    guard <- mergen_reclaim_mutex(lock, timeout = 5000)
    if (!is.null(guard) || Sys.time() >= deadline) return(guard)
    probe <- tryCatch(filelock::lock(lock, exclusive = FALSE, timeout = 0), error = function(e) e)
    if (inherits(probe, "error")) return(NULL)
    free <- if (is.null(probe)) 0L else free + 1L
    if (!is.null(probe)) filelock::unlock(probe)
    if (free >= 2L) return(NULL)
  }
}

.mergen_upload_unlock <- function(guard) {
  if (!is.null(guard)) filelock::unlock(guard)
  NULL
}

# Devralma, rezervasyon edinildikten sonra paylaşımlı korumayla dışlanır.
.mergen_promote_guard <- function(reservation, token) {
  guard <- mergen_reclaim_mutex(file.path(dirname(reservation), ".mergen-rsv.reclaim"),
    timeout = 5000, exclusive = FALSE)
  if (is.null(guard)) return(NULL)
  retained <- FALSE
  on.exit(if (!retained) .mergen_upload_unlock(guard), add = TRUE)
  for (attempt in 1:3) {
    owner <- mergen_reservation_owner(reservation)
    if (!is.na(owner)) break
    if (attempt < 3L) Sys.sleep(0.01)
  }
  retained <- identical(owner, token)
  if (retained) guard else NULL
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

# Eski hash ad alanı korunur; yalnız kayıpsız yerel/UTF-8 eşleri aranır.
file_ingestion_owner_paths <- function(path) {
  base <- basename(path)
  canonical <- file.path(dirname(path), mergen_upload_artifact_key(base))
  paths <- file_ingestion_owner_path(canonical, legacy = TRUE)
  compact <- file.path(dirname(path), paste0(".io-", digest::digest(mergen_upload_artifact_key(base),
    algo = "xxhash64", serialize = FALSE)))
  fits <- function(p) mergen_artifact_path_units(basename(paste0(p, ".identity"))) <= 255L &&
    (.Platform$OS.type != "windows" || mergen_artifact_path_units(paste0(p, ".identity")) <= 259L)
  if (!fits(paths)) {
    if (!fits(compact)) stop("Sahiplik yolu dosya sistemi sınırını aşıyor.")
    paths <- c(compact, paths)
  }
  for (name in list(base, enc2utf8(base), enc2native(base))) {
    if (!isTRUE(identical(enc2utf8(name), enc2utf8(base)))) next
    paths <- c(paths, file_ingestion_owner_path(file.path(dirname(path), name), legacy = TRUE))
  }
  if (.Platform$OS.type == "windows") paths <- paths[!duplicated(tolower(enc2utf8(paths)))]
  unique(c(paths, compact))
}

# Silme ya da sahiplik atlama yalnız inode/dosya kimliği içeren güçlü eşlikle yetkilenir.
file_ingestion_same_physical_file <- function(a, b) {
  is.list(a) && is.list(b) && !is.null(a$inode) && identical(a, b)
}

# İndeks talebi: Windows yolları harf duyarsız, POSIX yolları harf duyarlıdır.
.mergen_index_path_key <- function(path) {
  if (.Platform$OS.type == "windows") return(normalize_for_path_compare(path))
  key <- enc2utf8(as.character(path)[1])
  if (is.na(key)) "" else gsub("/+", "/", key)
}

# Eski staging yalnız terfi öncesi kaydedilmiş fiziksel kanıtla ya da terfisi hiç
# başlamamış sahibin birebir kaydettiği güncel staging olarak temizlenir.
file_ingestion_reclaim_stage <- function(path, staging, owner, marker) {
  old <- owner$staging
  if (length(old) != 1L || is.na(old)) return(invisible(NULL))
  old_key <- file_ingestion_physical_identity(old)
  candidates <- c(staging, paste0(path, MERGEN_UPLOAD_STAGING_SUFFIX))
  matched <- NULL
  for (candidate in candidates) {
    if (!path_exists_relaxed(candidate)) next
    # Boyut+mtime eşliği aynı dosya kanıtı değildir; yalnız inode/dosya kimliği eşler.
    if (file_ingestion_same_physical_file(old_key, file_ingestion_physical_identity(candidate)) ||
        identical(old, candidate)) {
      matched <- candidate
      break
    }
  }
  if (is.null(matched)) return(invisible(NULL))
  # Silme metadata yolunda değil, yalnız önceden türetilmiş staging adayında yapılır.
  old <- matched
  proof_path <- paste0(marker, ".identity")
  proof <- suppressWarnings(tryCatch(readRDS(proof_path), error = function(e) NULL))
  # Terfi kanıtı terfiden ÖNCE yazılır; hiç yoksa sahibin kaydettiği bu staging
  # yalnız yarım kopyadır (kanıt okunamıyorsa ya da başka aday eşleştiyse kapalı).
  abandoned <- identical(old, staging) && identical(owner$staging, staging) &&
    !file.exists(proof_path) && !isTRUE(path_exists_relaxed(proof_path))
  proven <- identical(owner$state, "copying") && (abandoned || (is.list(proof) &&
    identical(proof$id, owner$id) && identical(proof$state, "promoting") &&
    file_ingestion_same_physical_file(file_ingestion_physical_identity(old), proof$file_key)))
  # Başka kalıcı yapıtın marker'ı varsa eski terfi kanıtı silme yetkisi vermez.
  indexed <- .mergen_index_path_key(old) %in%
    vapply(as.list(unlist(.load_index(), use.names = FALSE)), .mergen_index_path_key, character(1))
  if (proven && !indexed && is.null(file_ingestion_read_owner(old))) {
    unlink(old, force = TRUE)
    if (path_exists_relaxed(old)) stop("Önceki staging temizlenemedi.")
  } else if (identical(old, staging)) stop("Önceki staging dosyasının kimliği doğrulanamadı.")
  invisible(NULL)
}

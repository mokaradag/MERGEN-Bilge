# Kopya kimliği yolun gösteriminden bağımsızdır.
file_ingestion_owner_path <- function(path, legacy = FALSE) {
  if (!legacy) {
    paths <- file_ingestion_owner_paths(path)
    existing <- paths[vapply(paths, path_exists_relaxed, logical(1))]
    if (length(existing) > 1L) stop("Çakışan sahiplik işaretleri doğrulanamadı.")
    return(if (length(existing)) existing[[1L]] else paths[[1L]])
  }
  ad <- basename(path)
  if (nchar(ad, type = "bytes") > 180L) {
    anahtar <- if (.Platform$OS.type == "windows") tolower(ad) else ad
    ad <- paste0("hash-", digest::digest(anahtar, algo = "xxhash64", serialize = FALSE))
  }
  file.path(dirname(path), paste0(".", ad, ".ingest-owner"))
}

file_ingestion_file_identity <- function(path, strong = FALSE) {
  if (is.null(path) || (!is.data.frame(path) &&
      (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)))) return(NULL)
  info <- if (is.data.frame(path)) path else {
    resolved <- if (exists("resolve_readable_path", mode = "function")) resolve_readable_path(path) else path
    file.info(resolved)[c("size", "mtime", "ctime")]
  }
  rownames(info) <- NULL
  if (!is.data.frame(path)) attr(info, "file_key") <- file_ingestion_physical_identity(resolved, strong = strong)
  info
}

file_ingestion_identity_matches <- function(actual, expected) {
  if (!is.data.frame(actual) || !is.data.frame(expected) || anyNA(actual) || anyNA(expected)) return(FALSE)
  expected_key <- attr(expected, "file_key")
  actual_key <- attr(actual, "file_key")
  attr(actual, "file_key") <- attr(expected, "file_key") <- NULL
  if (!identical(actual, expected)) return(FALSE)
  if (is.null(expected_key)) return(TRUE)
  guclu <- c("device_id", "inode")
  zayif <- c("size", "modification_time")
  expected_device <- is.list(expected_key) && all(guclu %in% names(expected_key))
  expected_hash <- is.list(expected_key) && is.character(expected_key$content_sha256) &&
    length(expected_key$content_sha256) == 1L && !is.na(expected_key$content_sha256) && nzchar(expected_key$content_sha256)
  if (expected_device) {
    return(is.list(actual_key) && all(guclu %in% names(actual_key)) && identical(actual_key, expected_key))
  }
  if (expected_hash) {
    return(is.list(actual_key) && identical(actual_key$content_sha256, expected_key$content_sha256) &&
      all(zayif %in% names(actual_key)) && identical(actual_key[zayif], expected_key[zayif]))
  }
  is.list(expected_key) && is.list(actual_key) &&
    all(zayif %in% names(expected_key)) && all(zayif %in% names(actual_key)) &&
    identical(actual_key[zayif], expected_key[zayif])
}

file_ingestion_artifact_owned <- function(result, allow_deleting = TRUE, require_strong = FALSE,
                                          actual_identity = NULL) {
  id <- result$artifact_id
  if (!is.character(id) || length(id) != 1L || is.na(id) || !nzchar(id)) return(FALSE)
  owner <- suppressWarnings(tryCatch(file_ingestion_read_owner(result$dest, identity = actual_identity),
                                     error = function(e) NULL))
  if (!is.list(owner) || !identical(owner$id, id)) return(FALSE)
  if (identical(owner$state, "copying") ||
      (identical(owner$state, "deleting") && !allow_deleting)) return(FALSE)
  expected <- file_ingestion_file_identity(owner$identity)
  expected_key <- attr(expected, "file_key")
  hash_owned <- is.list(expected_key) && is.character(expected_key$content_sha256) &&
    length(expected_key$content_sha256) == 1L && !is.na(expected_key$content_sha256) && nzchar(expected_key$content_sha256)
  needs_strong <- isTRUE(require_strong) || identical(owner$state, "deleting")
  actual <- if (is.data.frame(actual_identity)) file_ingestion_file_identity(actual_identity) else
    file_ingestion_file_identity(result$dest, strong = needs_strong)
  if (needs_strong) {
    actual_key <- attr(actual, "file_key")
    guclu <- c("device_id", "inode")
    device <- is.list(actual_key) && all(guclu %in% names(actual_key)) &&
      !anyNA(unlist(actual_key[guclu], use.names = FALSE))
    hashed <- is.list(actual_key) && is.character(actual_key$content_sha256) &&
      length(actual_key$content_sha256) == 1L && !is.na(actual_key$content_sha256) && nzchar(actual_key$content_sha256)
    if (!device && !hashed) return(FALSE)
  }
  if (hash_owned && !needs_strong) {
    weak_expected <- expected
    attr(weak_expected, "file_key") <- expected_key[c("size", "modification_time")]
    return(isTRUE(path_exists_relaxed(result$dest)) && file_ingestion_identity_matches(actual, weak_expected))
  }
  isTRUE(path_exists_relaxed(result$dest)) && file_ingestion_identity_matches(actual, expected)
}

# Marker yerinde yazılmaz: sert ölüm yarım RDS bırakıp tüm geri alımı kilitlerdi.
# fs/libuv aynı birimde Windows hedefini de atomik değiştirir; hata eski kanıtı korur.
file_ingestion_write_owner <- function(value, target) {
  tmp <- tempfile(".io-", tmpdir = dirname(target))
  on.exit(unlink(tmp, force = TRUE), add = TRUE)
  saveRDS(value, tmp)
  for (deneme in 1:5) {
    if (!inherits(try(fs::file_move(tmp, target), silent = TRUE), "try-error"))
      return(invisible(target))
    Sys.sleep(0.05 * deneme)
  }
  unlink(tmp, force = TRUE)
  stop("Sahiplik işareti yazılamadı.")
}

# Okunamayan marker sahiplik kanıtı değildir: boş liste + `unreadable` döner,
# böylece silme yolları kimlik eşleşmesi bulamaz, rezervasyon ise yalnız yaşla
# geri kazanılır. Önceden hesaplanmış güçlü kimlik verilirse paylaşılan indeks
# kilidi altında dosya yeniden hash'lenmez.
file_ingestion_read_owner <- function(path, identity = NULL) {
  marker <- file_ingestion_owner_path(path)
  owner <- if (path_exists_relaxed(marker)) {
    suppressWarnings(tryCatch(readRDS(marker), error = function(e) structure(list(), unreadable = TRUE)))
  } else NULL
  if (!is.null(owner) && !is.list(owner)) owner <- structure(list(), unreadable = TRUE)
  if (!is.list(owner) || !identical(owner$state, "copying")) return(owner)
  verified <- suppressWarnings(tryCatch(readRDS(paste0(marker, ".identity")), error = function(e) NULL))
  if (is.list(verified) && identical(verified$id, owner$id)) {
    if (identical(verified$state, "promoting")) {
      identity <- if (is.data.frame(identity)) file_ingestion_file_identity(identity) else
        file_ingestion_file_identity(path, strong = TRUE)
      key <- attr(identity, "file_key")
      proof <- verified$file_key
      guclu <- c("device_id", "inode")
      zayif <- c("size", "modification_time")
      key_device <- is.list(key) && all(guclu %in% names(key)) &&
        !anyNA(unlist(key[guclu], use.names = FALSE))
      key_hash <- is.list(key) && is.character(key$content_sha256) && length(key$content_sha256) == 1L &&
        !is.na(key$content_sha256) && nzchar(key$content_sha256)
      proof_device <- is.list(proof) && all(guclu %in% names(proof)) &&
        !anyNA(unlist(proof[guclu], use.names = FALSE))
      proof_hash <- is.list(proof) && is.character(proof$content_sha256) &&
        length(proof$content_sha256) == 1L && !is.na(proof$content_sha256) && nzchar(proof$content_sha256)
      same <- if (proof_device) {
        key_device && identical(key, proof)
      } else if (proof_hash) {
        key_hash && identical(key$content_sha256, proof$content_sha256) &&
          all(zayif %in% names(key)) && all(zayif %in% names(proof)) && identical(key[zayif], proof[zayif])
      } else FALSE
      # Zayıf eski terfi kanıtı kalıcı sahipliğe yükseltilmez. Yeni terfiler
      # device/inode ya da SHA-256 kanıtını yayınlamadan ÖNCE kaydeder.
      if (!is.data.frame(identity) || anyNA(identity) || (!key_device && !key_hash) || !same) return(owner)
      owner$identity <- identity
    } else owner$identity <- verified$identity
    owner$state <- "claimed"
  }
  owner
}

# Terfi denendi ama hedef henüz kanıtlanmadı (UNC görünürlük gecikmesi):
# sahiplik işaretleri hedef görünene ya da yokluğu kanıtlanana dek korunur.
file_ingestion_promotion_pending <- function(path, id) {
  verified <- suppressWarnings(tryCatch(readRDS(paste0(file_ingestion_owner_path(path), ".identity")),
                                        error = function(e) NULL))
  is.list(verified) && identical(verified$state, "promoting") && identical(verified$id, id)
}

# Yabancı rezervasyon yalnız ortak sahip kuralıyla geri kazanılır; okunamayan
# ya da uzak marker yalnız uzun bayatlık eşiğinden sonra (kopya tazelenmez).
file_ingestion_owner_reclaimable <- function(owner, marker, stale_sec = 3600) {
  mtime <- tryCatch(file.info(marker)$mtime[1], error = function(e) NA)
  yas <- if (length(mtime) == 1L && !is.na(mtime)) as.numeric(difftime(Sys.time(), mtime, units = "secs")) else NA_real_
  mergen_owner_reclaimable(owner$pid, owner$host, yas, stale_sec,
                           since = if (length(mtime) == 1L && !is.na(mtime)) mtime else NULL)
}

file_ingestion_begin_copy <- function(path, staging, source, transaction) {
  # Sahip edinimi yalnız adın harf eşlerini kilitler; indeks yazımı yapmaz.
  guard <- mergen_upload_lane_lock(path)
  if (is.null(guard)) stop("Kopya sahiplik muteksi alınamadı.")
  on.exit(filelock::unlock(guard), add = TRUE)
  {
    marker <- file_ingestion_owner_path(path)
    owner <- file_ingestion_read_owner(path)
    yabanci <- is.list(owner) && !identical(owner$id, transaction$id)
    if (yabanci && !file_ingestion_owner_reclaimable(owner, marker))
      stop("Kopya hedefi başka bir işlem tarafından ayrılmış.")
    # Eski staging'in indeks talebi ancak indeks kilidiyle dışlanabilir.
    if (yabanci) .file_store_with_index_lock(
      file_ingestion_reclaim_stage(path, staging, owner, marker), require_lock = TRUE)
    if (path_exists_relaxed(path) || path_exists_relaxed(staging)) stop("Kopya hedefi zaten var.")
    previous <- suppressWarnings(tryCatch(readRDS(transaction$journal), error = function(e) NULL))
    started_at <- if (is.list(previous) && identical(previous$artifact_id, transaction$id))
      previous$started_at else transaction$started_at
    yeni_nesil <- is.list(previous) && is.character(previous$artifact_id) && length(previous$artifact_id) == 1L &&
      !is.na(previous$artifact_id) && nzchar(previous$artifact_id) && !identical(previous$artifact_id, transaction$id)
    if (is.null(started_at) && (yeni_nesil || !path_exists_relaxed(transaction$journal))) started_at <- as.numeric(Sys.time())
    if (!is.numeric(started_at) || length(started_at) != 1L || !is.finite(started_at))
      stop("İşlemin ilk başlangıcı doğrulanamadı.")
    result <- list(ok = FALSE, dest = path, source_path = source, started_at = started_at,
      artifact_id = transaction$id, staging = staging, transaction_pending = TRUE)
    file_ingestion_write_owner(result, transaction$journal)
    unlink(paste0(marker, ".identity"), force = TRUE)
    # Benzersiz nesil, inode olmayan paylaşımda da marker takma adını kanıtlar.
    generation <- paste0(Sys.getpid(), "-", basename(tempfile("og")))
    file_ingestion_write_owner(list(id = transaction$id, state = "copying", staging = staging,
      pid = Sys.getpid(), host = unname(Sys.info()[["nodename"]]), started_at = started_at,
      generation = generation), marker)
    if (is.list(previous) && !identical(previous$dest, path)) {
      old_owner <- file_ingestion_read_owner(previous$dest)
      # Yerel kodlama aynı fiziksel marker'a çözülürse yeni rezervasyon silinmez.
      if (identical(old_owner$id, transaction$id) && identical(old_owner$state, "copying") &&
          identical(old_owner$staging, previous$staging) && !identical(old_owner$generation, generation) &&
          !path_exists_relaxed(previous$staging)) unlink(file_ingestion_owner_path(previous$dest), force = TRUE)
    }
  }
  invisible(NULL)
}

file_ingestion_claim_artifact <- function(path, expected = file_ingestion_file_identity(path, strong = TRUE), id = NULL,
                                          started_at = Sys.time()) {
  supplied_id <- id
  id <- id %||% paste0(Sys.getpid(), "-", basename(tempfile("ingest_")))
  # Ağ dosyasının tamamını okumak paylaşılan indeks kilidinin DIŞINDADIR.
  actual <- file_ingestion_file_identity(path, strong = TRUE)
  expected_identity <- if (missing(expected)) actual else file_ingestion_file_identity(expected)
  actual_key <- attr(actual, "file_key")
  expected_key <- attr(expected_identity, "file_key")
  guclu <- c("device_id", "inode")
  strong_key <- function(key) {
    device <- is.list(key) && all(guclu %in% names(key)) && !anyNA(unlist(key[guclu], use.names = FALSE))
    hashed <- is.list(key) && is.character(key$content_sha256) && length(key$content_sha256) == 1L &&
      !is.na(key$content_sha256) && nzchar(key$content_sha256)
    device || hashed
  }
  if (!strong_key(actual_key) || !strong_key(expected_key) ||
      !file_ingestion_identity_matches(actual, expected_identity))
    stop("Kopyalanan dosyanın sahipliği doğrulanamadı.")
  .file_store_with_index_lock({
    marker <- file_ingestion_owner_path(path)
    owner <- file_ingestion_read_owner(path, identity = actual)
    if ((!is.null(supplied_id) && (!is.list(owner) || !identical(owner$id, supplied_id) ||
          !identical(owner$state, "claimed") ||
          !file_ingestion_identity_matches(actual, file_ingestion_file_identity(owner$identity)))) ||
        !isTRUE(path_exists_relaxed(path)) ||
        (is.list(owner) && !identical(owner$id, supplied_id) &&
          (identical(owner$state, "copying") || file_ingestion_identity_matches(actual, file_ingestion_file_identity(owner$identity))))) {
      stop("Kopyalanan dosyanın sahipliği doğrulanamadı.")
    }
    if (is.null(supplied_id)) file_ingestion_write_owner(list(id = id, identity = actual, pid = Sys.getpid(),
      host = unname(Sys.info()[["nodename"]]), started_at = as.numeric(started_at)), marker) else
      file_ingestion_write_owner(list(id = id, identity = actual), paste0(marker, ".identity"))
  }, require_lock = TRUE)
  id
}

# Kopya yardımcısının tamamladığı talep kilitsiz doğrulanır; güçlü kanıt sidecar'a
# kalıcılaştırılır, böylece indeks kilidi altında dosya yeniden hash'lenmez.
file_ingestion_claimed_by <- function(path, id, expected) {
  if (!is.character(id) || length(id) != 1L || is.na(id) || !nzchar(id)) return(FALSE)
  actual <- file_ingestion_file_identity(path, strong = TRUE)
  expected_identity <- file_ingestion_file_identity(expected)
  owner <- file_ingestion_read_owner(path, identity = actual)
  valid <- is.list(owner) && identical(owner$id, id) && identical(owner$state, "claimed") &&
    file_ingestion_identity_matches(actual, file_ingestion_file_identity(owner$identity)) &&
    file_ingestion_identity_matches(actual, expected_identity)
  if (!isTRUE(valid)) return(FALSE)
  !inherits(try(file_ingestion_write_owner(list(id = id, identity = actual),
    paste0(file_ingestion_owner_path(path), ".identity")), silent = TRUE), "try-error")
}

# Diğer yapıt bu işlemin rezervasyonundan sonra mı talep edildi? Zaman kalıcı
# marker mtime'larından okunur; bilinmeyen zaman eşzamanlı sayılır (fail closed).
file_ingestion_claimed_since <- function(other_path, own_path) {
  zaman <- function(paths) {
    t <- suppressWarnings(tryCatch(file.info(paths)$mtime, error = function(e) NA))
    t <- t[!is.na(t)]
    if (length(t)) t[1] else NA
  }
  diger_marker <- file_ingestion_owner_path(other_path)
  diger <- zaman(c(paste0(diger_marker, ".identity"), diger_marker))
  kendi <- zaman(file_ingestion_owner_path(own_path))
  is.na(diger) || is.na(kendi) || diger >= kendi
}

file_ingestion_discard_unclaimed <- function(path, source, expected) {
  id <- paste0(Sys.getpid(), "-", basename(tempfile("discard_")))
  marker <- file_ingestion_owner_path(path)
  expected_identity <- file_ingestion_file_identity(expected)
  expected_key <- attr(expected_identity, "file_key")
  guclu <- c("device_id", "inode")
  expected_device <- is.list(expected_key) && all(guclu %in% names(expected_key)) &&
    !anyNA(unlist(expected_key[guclu], use.names = FALSE))
  expected_hash <- is.list(expected_key) && is.character(expected_key$content_sha256) &&
    length(expected_key$content_sha256) == 1L && !is.na(expected_key$content_sha256) && nzchar(expected_key$content_sha256)
  # Zayıf doğrulama sonradan görülen başka bir dosyanın güçlü kimliğine
  # yükseltilemez; silme yetkisi yalnız önceden yakalanmış güçlü kanıttan gelir.
  if (!expected_device && !expected_hash) return(invisible(NULL))
  actual <- file_ingestion_file_identity(path, strong = TRUE)
  if (!file_ingestion_identity_matches(actual, expected_identity)) return(invisible(NULL))
  reserved <- .file_store_with_index_lock({
    owner <- file_ingestion_read_owner(path, identity = actual)
    if (!identical(owner$state, "copying") && !isTRUE(attr(owner, "unreadable")) &&
        (is.null(owner) || !file_ingestion_identity_matches(file_ingestion_file_identity(owner$identity), expected_identity))) {
      file_ingestion_write_owner(list(id = id, identity = actual, state = "deleting",
        pid = Sys.getpid(), host = unname(Sys.info()[["nodename"]])), marker)
      TRUE
    } else FALSE
  }, require_lock = TRUE)
  result <- list(dest = path, artifact_id = id)
  if (reserved && file_ingestion_artifact_owned(result)) {
    file_ingestion_discard_dest(path, source)
    if (!path_exists_relaxed(path) && identical(file_ingestion_read_owner(path)$id, id))
      unlink(marker, force = TRUE)
  }
  invisible(NULL)
}

# Fiziksel anahtar yol YAZIMINDAN bağımsızdır. Normal akışta metadata ucuz
# tutulur. Güçlü kanıt istendiğinde inode sağlayan dosya sisteminde device+inode,
# inode sağlamayan paylaşımda ise SHA-256 içerik özeti silme/rollback kanıtıdır.
file_ingestion_physical_identity <- function(path, strong = FALSE) {
  p <- as.character(path %||% "")[1]
  if (is.na(p) || !nzchar(p)) return(NULL)
  logical <- if (.Platform$OS.type == "windows") mergen_logical_path(p) else p
  io <- mergen_io_path(logical)
  for (candidate in unique(c(logical, io))) {
    info <- try(fs::file_info(candidate), silent = TRUE)
    if (inherits(info, "try-error") || NROW(info) != 1L || is.na(info$size) || is.na(info$modification_time)) next
    if (is.finite(info$inode) && info$inode > 0)
      return(lapply(info[c("device_id", "inode", "size", "modification_time")], as.character))
    key <- lapply(info[c("size", "modification_time")], as.character)
    if (isTRUE(strong)) for (hash_path in unique(c(candidate, io))) {
      hash <- try(digest::digest(hash_path, algo = "sha256", serialize = FALSE, file = TRUE,
        errormode = "silent"), silent = TRUE)
      if (!inherits(hash, "try-error") && is.character(hash) && length(hash) == 1L && !is.na(hash) && nzchar(hash)) {
        key$content_sha256 <- hash
        break
      }
    }
    return(key)
  }
  info <- try(file.info(io), silent = TRUE)
  if (inherits(info, "try-error") || NROW(info) != 1L || is.na(info$size[1]) || is.na(info$mtime[1])) return(NULL)
  key <- list(size = as.character(info$size[1]), modification_time = as.character(info$mtime[1]))
  if (isTRUE(strong)) for (hash_path in unique(c(io, logical))) {
    hash <- try(digest::digest(hash_path, algo = "sha256", serialize = FALSE, file = TRUE,
      errormode = "silent"), silent = TRUE)
    if (!inherits(hash, "try-error") && is.character(hash) && length(hash) == 1L && !is.na(hash) && nzchar(hash)) {
      key$content_sha256 <- hash
      break
    }
  }
  key
}

file_ingestion_prepare_promotion <- function(staging, path, transaction) {
  # Staging kanıtı yayınlamadan ÖNCE güçlüdür; inode yoksa hash işçi üzerinde
  # hesaplanır. Böylece recovery zayıf metadata'yı replacement sahipliğine yükseltemez.
  key <- file_ingestion_physical_identity(staging, strong = TRUE)
  guclu <- c("device_id", "inode")
  device <- is.list(key) && all(guclu %in% names(key)) && !anyNA(unlist(key[guclu], use.names = FALSE))
  hashed <- is.list(key) && is.character(key$content_sha256) && length(key$content_sha256) == 1L &&
    !is.na(key$content_sha256) && nzchar(key$content_sha256)
  if (!device && !hashed) stop("Staging dosya kimliği güçlü biçimde doğrulanamadı.")
  file_ingestion_write_owner(list(id = transaction$id, state = "promoting", file_key = key),
    paste0(file_ingestion_owner_path(path), ".identity"))
}

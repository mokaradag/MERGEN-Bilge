# ==============================================================================
# Dosya Yolu: R/helpers_files_promote_target.R
# Açıklama: Aşamalı yükleme kopyasının kalıcı ada sahiplik kanıtlı terfisi.
# Terfi yalnız OLUŞTURUR; hiçbir koşulda mevcut hedefi DEĞİŞTİRMEZ.
# Saf yoklama yardımcıları R/helpers_files_promote_probe.R dosyasındadır.
# ==============================================================================

MERGEN_PROMOTE_RESERVATION_SUFFIX <- ".mergen-rsv"

# Özel oluşturma, başarısız kopyada silme yetkisini kanıtlar; yabancıya dokunulmaz.
.mergen_promote_copy_exclusive <- function(staging, hedef) {
  # Kimliksiz dosya sisteminde temizlenemeyecek kalıcı ad oluşturulmaz; aynı
  # dizindeki staging de kimliklenemiyorsa kalıcı ad hiç açılmaz.
  if (is.null(.mergen_promote_file_key(dirname(hedef))) || is.null(.mergen_promote_file_key(staging))) return(FALSE)
  input <- output <- owned <- NULL
  complete <- FALSE
  on.exit({
    if (!is.null(input)) try(close(input), silent = TRUE)
    if (!is.null(output)) try(close(output), silent = TRUE)
    if (!is.null(owned) && !complete && identical(.mergen_promote_file_key(hedef), owned))
      try(unlink(mergen_io_path(hedef), force = TRUE, expand = FALSE), silent = TRUE)
  }, add = TRUE)
  isTRUE(tryCatch({
    input <- file(mergen_io_path(staging), "rb")
    output <- file(mergen_io_path(hedef), "wxb")
    owned <- .mergen_promote_file_key(hedef)
    if (is.null(owned)) stop("Kopya dosyasının fiziksel kimliği doğrulanamadı.")
    # file.copy gibi: kip desteklenmeyen paylaşımda kopya yine tamamlanabilir.
    Sys.chmod(mergen_io_path(hedef), mode = file.info(mergen_io_path(staging))$mode[1], use_umask = FALSE)
    while (length(bytes <- readBin(input, "raw", n = 65536L)))
      writeBin(bytes, output)
    close(output)
    output <- NULL
    complete <- TRUE
    TRUE
  }, error = base::identity, warning = base::identity))
}

# Staging adı terfiden sonra düşürülür; silme hatası kalıcı hedefi geçersiz kılmaz.
.mergen_promote_drop_staging <- function(staging, var_mi) {
  try(unlink(mergen_io_path(staging), force = TRUE, expand = FALSE), silent = TRUE)
  if (!mergen_promote_probe(var_mi, staging)) return(invisible(TRUE))
  try(
    warning(sprintf(
      "mergen_promote_staged_file: staging adı silinemedi; terfi geçerli: %s",
      staging
    ), call. = FALSE),
    silent = TRUE
  )
  invisible(FALSE)
}

# Dönen liste: ok, yabanci, promoted ve gerekirse partial_owned.
mergen_promote_staged_file <- function(staging, hedef, var_mi,
                                       gorunurluk_denemesi = 10L, allow_copy = TRUE) {
  var_mi_guvenli <- function(p) mergen_promote_probe(var_mi, p)
  # Yayın kilidi yalnız aynı adın harf eşlerini dışlar; kalıcı ad değişmez.
  publish <- guard <- NULL
  on.exit({ .mergen_upload_unlock(guard); .mergen_upload_unlock(publish) }, add = TRUE)
  if (exists("mergen_reclaim_mutex", mode = "function") && exists("mergen_upload_lane_lock", mode = "function")) {
    publish <- mergen_upload_lane_lock(hedef)
    if (is.null(publish)) return(list(ok = FALSE, yabanci = TRUE, promoted = FALSE))
  }
  bagli <- isTRUE(try(suppressWarnings(file.link(mergen_io_path(staging), mergen_io_path(hedef))), silent = TRUE))
  if (bagli) {
    .mergen_promote_drop_staging(staging, var_mi_guvenli)
    publish <- .mergen_upload_unlock(publish)
    return(list(
      ok = mergen_promote_wait_visible(hedef, var_mi_guvenli, gorunurluk_denemesi),
      yabanci = FALSE,
      promoted = TRUE
    ))
  }
  # Bağlantı kurulamadıysa mevcut hedef yabancıdır.
  if (var_mi_guvenli(hedef)) return(list(ok = FALSE, yabanci = TRUE, promoted = FALSE))
  # Eski rezervasyon adları korunur; POSIX hedef adları küçük harfe çevrilmez.
  rezerv <- tryCatch(mergen_upload_artifact_path(hedef, MERGEN_PROMOTE_RESERVATION_SUFFIX, component_only = TRUE),
    error = function(e) NULL)
  if (is.null(rezerv))
    return(list(ok = FALSE, yabanci = var_mi_guvenli(hedef), promoted = FALSE))
  jeton <- if (exists("mergen_reservation_token", mode = "function", inherits = TRUE)) {
    mergen_reservation_token("uprsv")
  } else {
    ""
  }
  alindi <- nzchar(jeton) &&
    exists("mergen_reservation_acquire", mode = "function", inherits = TRUE) &&
    isTRUE(mergen_reservation_acquire(rezerv, jeton))
  if (!alindi && exists("mergen_reservation_takeover", mode = "function"))
    alindi <- isTRUE(mergen_reservation_takeover(rezerv, jeton))

  # Rezervasyon yoksa terfi denenmez; son hedef yoklaması yeniden ad denemeyi engeller.
  if (!alindi)
    return(list(ok = FALSE, yabanci = var_mi_guvenli(hedef), promoted = FALSE))

  sonuc <- tryCatch({
    if (isTRUE(dir.exists(mergen_io_path(rezerv)))) {
      guard <- .mergen_promote_guard(rezerv, jeton)
      if (is.null(guard)) return(list(ok = FALSE, yabanci = TRUE, promoted = FALSE))
    }

    # İki bağımsız okuma, yavaş paylaşımda tek yanlış negatifi daraltır.
    if (var_mi_guvenli(hedef) || var_mi_guvenli(hedef)) {
      list(ok = FALSE, yabanci = TRUE, promoted = FALSE)
    } else {
      tasindi <- isTRUE(tryCatch(file.rename(mergen_io_path(staging), mergen_io_path(hedef)), error = function(e) FALSE))
      if (!tasindi && isTRUE(allow_copy) && var_mi_guvenli(staging)) {
        tasindi <- .mergen_promote_copy_exclusive(staging, hedef)
        if (tasindi) .mergen_promote_drop_staging(staging, var_mi_guvenli)
      }
      guard <- .mergen_upload_unlock(guard)
      publish <- .mergen_upload_unlock(publish)
      if (tasindi) {
        list(
          ok = mergen_promote_wait_visible(hedef, var_mi_guvenli, gorunurluk_denemesi),
          yabanci = FALSE,
          promoted = TRUE
        )
      } else {
        # Görünürlük oluşturma kanıtı değildir; yarışan yabancı hedef silinemez.
        list(
          ok = FALSE,
          yabanci = TRUE,
          promoted = FALSE,
          partial_owned = FALSE
        )
      }
    }
  }, finally = {
    if (exists("mergen_reservation_release", mode = "function", inherits = TRUE))
      mergen_reservation_release(rezerv, jeton)
  })
  sonuc
}

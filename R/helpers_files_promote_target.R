# ==============================================================================
# Dosya Yolu: R/helpers_files_promote_target.R
# Açıklama: Aşamalı yükleme kopyasının kalıcı ada sahiplik kanıtlı terfisi.
# Terfi yalnız OLUŞTURUR; hiçbir koşulda mevcut hedefi DEĞİŞTİRMEZ.
# Saf yoklama yardımcıları R/helpers_files_promote_probe.R dosyasındadır.
# ==============================================================================

MERGEN_PROMOTE_RESERVATION_SUFFIX <- ".mergen-rsv"

# Özel oluşturma, başarısız kopyada silme yetkisini kanıtlar; yabancıya dokunulmaz.
.mergen_promote_copy_exclusive <- function(staging, hedef) {
  # Kimliksiz dosya sisteminde temizlenemeyecek kalıcı ad oluşturulmaz.
  if (is.null(.mergen_promote_file_key(dirname(hedef)))) return(FALSE)
  input <- output <- owned <- NULL
  complete <- FALSE
  on.exit({
    if (!is.null(input)) try(close(input), silent = TRUE)
    if (!is.null(output)) try(close(output), silent = TRUE)
    if (!is.null(owned) && !complete && identical(.mergen_promote_file_key(hedef), owned))
      try(unlink(hedef, force = TRUE), silent = TRUE)
  }, add = TRUE)
  isTRUE(tryCatch({
    input <- file(staging, "rb")
    output <- file(hedef, "wxb")
    owned <- .mergen_promote_file_key(hedef)
    if (is.null(owned)) stop("Kopya dosyasının fiziksel kimliği doğrulanamadı.")
    # file.copy gibi: kip desteklenmeyen paylaşımda kopya yine tamamlanabilir.
    Sys.chmod(hedef, mode = file.info(staging)$mode[1], use_umask = FALSE)
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
  try(unlink(staging, force = TRUE), silent = TRUE)
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

  # Atomik, üzerine-yazmayan terfi.
  bagli <- isTRUE(try(suppressWarnings(file.link(staging, hedef)), silent = TRUE))
  if (bagli) {
    .mergen_promote_drop_staging(staging, var_mi_guvenli)
    return(list(
      ok = mergen_promote_wait_visible(hedef, var_mi_guvenli, gorunurluk_denemesi),
      yabanci = FALSE,
      promoted = TRUE
    ))
  }

  # Bağlantı kurulamadıysa mevcut hedef yabancıdır.
  if (var_mi_guvenli(hedef)) return(list(ok = FALSE, yabanci = TRUE, promoted = FALSE))

  # Geçerli eski rezervasyon adları korunur; taşan bileşen ortak yardımcıyla kısalır.
  rezerv <- mergen_upload_artifact_path(hedef, MERGEN_PROMOTE_RESERVATION_SUFFIX, component_only = TRUE)
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

  guard <- NULL
  on.exit(if (!is.null(guard)) filelock::unlock(guard), add = TRUE)
  sonuc <- tryCatch({
    # Gerçek rezervasyonda devralmayı terfi bitene kadar dışla. İzole test
    # sahte acquire kullanabilir; üretim acquire her zaman rezerv dizinini kurar.
    if (isTRUE(dir.exists(rezerv))) {
      # Paylaşımlı terfiler birlikte ilerler; devralmanın özel kilidi dışlanır.
      guard <- mergen_reclaim_mutex(file.path(dirname(rezerv), ".mergen-rsv.reclaim"),
        timeout = 5000, exclusive = FALSE)
      if (is.null(guard)) return(list(ok = FALSE, yabanci = TRUE, promoted = FALSE))
      for (deneme in 1:3) {
        sahip <- mergen_reservation_owner(rezerv)
        if (!is.na(sahip)) break
        if (deneme < 3L) Sys.sleep(0.01)
      }
      if (!identical(sahip, jeton))
        return(list(ok = FALSE, yabanci = TRUE, promoted = FALSE))
    }

    # İki bağımsız okuma, yavaş paylaşımda tek yanlış negatifi daraltır.
    if (var_mi_guvenli(hedef) || var_mi_guvenli(hedef)) {
      list(ok = FALSE, yabanci = TRUE, promoted = FALSE)
    } else {
      tasindi <- isTRUE(tryCatch(file.rename(staging, hedef), error = function(e) FALSE))
      if (!tasindi && isTRUE(allow_copy) && var_mi_guvenli(staging)) {
        tasindi <- .mergen_promote_copy_exclusive(staging, hedef)
        if (tasindi) .mergen_promote_drop_staging(staging, var_mi_guvenli)
      }
      if (!is.null(guard)) {
        filelock::unlock(guard)
        guard <- NULL
      }
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

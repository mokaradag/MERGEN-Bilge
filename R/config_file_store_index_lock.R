# ==============================================================================
# R/config_file_store_index_lock.R
# Dosya deposu indeks kilidi: stale kilit kırma, kilit sahip marker'ı ve
# erişilebilirlik-öncelikli kilit edinme davranışı.
# R/config_file_store.R dosyasından sonra, R/config_file_store_index_mutation.R
# dosyasından önce source edilmelidir. Mutasyon yardımcıları bu kilidi
# .file_store_mutate_index üzerinden kullanır; kilit mantığını mutasyon
# dosyasına geri taşımayın (fonksiyon-yoğunluk bölme sözleşmesi).
# ==============================================================================

.file_store_with_index_lock <- function(expr, timeout_sec = 5, poll_sec = 0.05,
                                        stale_lock_sec = 60) {
  lock_dir <- paste0(MERGEN_INDEX_PATH, ".lock")
  lock_parent <- dirname(lock_dir)
  lock_marker <- file.path(lock_dir, "owner")
  start_time <- Sys.time()
  acquired <- FALSE

  if (!dir.exists(lock_parent)) {
    dir.create(lock_parent, recursive = TRUE, showWarnings = FALSE)
  }

  if (!dir.exists(lock_parent)) {
    try(
      log_warn("[INDEX] İndeks kilidi üst dizini oluşturulamadı; kilitsiz devam ediliyor: {lock_parent}"),
      silent = TRUE
    )
    return(force(expr))
  }

  .lock_mtime <- function() {
    marker_info <- tryCatch(file.info(lock_marker), error = function(e) NULL)
    if (!is.null(marker_info) && !is.na(marker_info$mtime[1])) {
      return(marker_info$mtime[1])
    }

    lock_info <- tryCatch(file.info(lock_dir), error = function(e) NULL)
    if (!is.null(lock_info) && !is.na(lock_info$mtime[1])) {
      return(lock_info$mtime[1])
    }

    as.POSIXct(NA_real_, origin = "1970-01-01")
  }

  .write_lock_marker <- function() {
    marker_text <- c(
      sprintf("pid=%s", Sys.getpid()),
      sprintf("time=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3%z"))
    )

    try(writeLines(enc2utf8(marker_text), lock_marker, useBytes = TRUE), silent = TRUE)
    try(Sys.setFileTime(lock_marker, Sys.time()), silent = TRUE)

    invisible(TRUE)
  }

  # Çökmüş bir süreç kilit dizinini sonsuza dek bırakabilir; bu durumda her
  # mutasyon timeout kadar bekleyip kilitsiz devam ederdi (kalıcı gecikme +
  # kalıcı kilitsiz mod). Eski (stale) kilitler yaşına bakılarak kırılır.
  # Windows/UNC dosya sistemlerinde dizin mtime güvenilir olmayabildiği için
  # varsa lock marker dosyasının mtime değeri esas alınır.
  .break_stale_lock_if_needed <- function() {
    lock_time <- .lock_mtime()

    if (is.na(lock_time)) {
      return(invisible(FALSE))
    }

    lock_age <- as.numeric(difftime(Sys.time(), lock_time, units = "secs"))

    if (is.finite(lock_age) && lock_age > stale_lock_sec) {
      try(
        log_warn("[INDEX] Eski indeks kilidi kırılıyor (yaş: {round(lock_age)} sn): {lock_dir}"),
        silent = TRUE
      )
      unlink(lock_dir, recursive = TRUE, force = TRUE)
      return(invisible(TRUE))
    }

    invisible(FALSE)
  }

  repeat {
    acquired <- tryCatch(
      dir.create(lock_dir, showWarnings = FALSE, recursive = FALSE),
      warning = function(w) FALSE,
      error = function(e) FALSE
    )

    if (isTRUE(acquired)) {
      .write_lock_marker()
      break
    }

    if (isTRUE(.break_stale_lock_if_needed())) {
      next
    }

    elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    if (!is.finite(elapsed) || elapsed >= timeout_sec) {
      break
    }

    Sys.sleep(poll_sec)
  }

  if (!isTRUE(acquired)) {
    try(
      log_warn("[INDEX] İndeks kilidi alınamadı; mevcut davranışı korumak için kilitsiz devam ediliyor: {lock_dir}"),
      silent = TRUE
    )
    return(force(expr))
  }

  on.exit(unlink(lock_dir, recursive = TRUE, force = TRUE), add = TRUE)

  force(expr)
}

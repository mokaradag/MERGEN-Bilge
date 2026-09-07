# ==============================================================================
# R/config_file_store_index_lock.R
# Dosya deposu indeks kilidi: stale kilit kırma, kilit sahip marker'ı ve
# erişilebilirlik-öncelikli kilit edinme davranışı.
# R/config_file_store.R dosyasından sonra, R/config_file_store_index_mutation.R
# dosyasından önce source edilmelidir. Mutasyon yardımcıları bu kilidi
# .file_store_mutate_index üzerinden kullanır; kilit mantığını mutasyon
# dosyasına geri taşımayın (fonksiyon-yoğunluk bölme sözleşmesi).
# ==============================================================================

# Kilit tutulurken uzun süren işlemlerin marker'ı tazelemesi için kayıt yeri.
# Sabit bayatlık eşiği, CANLI bir kilidi kırılabilir yapıyordu (büyük/yavaş UNC
# kovasında silme meşru olarak eşiği aşabilir).
.FILE_STORE_LOCK_STATE <- new.env(parent = emptyenv())

# Kilitli bölüm içinden çağrılır; kilit tutulmuyorsa sessiz no-op'tur.
file_store_index_lock_heartbeat <- function() {
  fn <- .FILE_STORE_LOCK_STATE$heartbeat
  if (is.function(fn)) try(fn(), silent = TRUE)
  invisible(NULL)
}

# require_lock = TRUE: sahiplik DOĞRULANAMAZSA ifade kilitsiz çalıştırılmaz,
# hata verilir. Kilitsiz mutasyon, eşzamanlı iki yazarın aynı anlık görüntüyü
# kaydedip birbirinin indeks güncellemesini silmesine (lost update) izin veriyordu.
.file_store_with_index_lock <- function(expr, timeout_sec = 5, poll_sec = 0.05,
                                        stale_lock_sec = 60, require_lock = FALSE) {
  lock_dir <- paste0(MERGEN_INDEX_PATH, ".lock")
  lock_parent <- dirname(lock_dir)
  lock_marker <- file.path(lock_dir, "owner")
  # Sahiplik jetonu: kilit yalnızca marker hâlâ bu jetonu taşıyorsa bırakılır
  # (eski kilit kırılıp yeni yazar tarafından alındıysa onun kilidi silinmez).
  lock_token <- paste0(Sys.getpid(), "-", basename(tempfile("lk")))
  start_time <- Sys.time()
  acquired <- FALSE

  if (!dir.exists(lock_parent)) {
    dir.create(lock_parent, recursive = TRUE, showWarnings = FALSE)
  }

  if (!dir.exists(lock_parent)) {
    if (isTRUE(require_lock)) {
      stop(sprintf(
        "[INDEX] İndeks kilidi üst dizini oluşturulamadı; işlem güvenli biçimde yapılamaz: %s",
        lock_parent
      ), call. = FALSE)
    }
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
      sprintf("token=%s", lock_token),
      sprintf("time=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3%z"))
    )

    try(writeLines(enc2utf8(marker_text), lock_marker, useBytes = TRUE), silent = TRUE)
    try(Sys.setFileTime(lock_marker, Sys.time()), silent = TRUE)

    invisible(TRUE)
  }

  # Heartbeat marker'ı YALNIZCA hâlâ sahipsek tazeler. Koşulsuz yazım, bayat
  # kilidi kıran YENİ sahibin marker'ını kendi jetonumuzla eziyor ve onun
  # kilidini bize silinebilir yapıyordu (lost update).
  # KALAN RİSK (kapatılamıyor): sahiplik denetimi ile marker yazımı AYRI
  # işlemlerdir; base R'de dosya sistemi için atomik karşılaştır-ve-değiştir
  # ilkeli yoktur (fsync sınırıyla aynı sınıf). Pencere, yazımdan SONRA jetonun
  # YENİDEN OKUNMASIYLA daraltılır: sahiplik kaybedildiyse çağıran `FALSE`
  # alır ve kilidi tuttuğunu varsaymaz.
  .refresh_lock_marker <- function() {
    if (!identical(.lock_owner_token(), lock_token)) return(invisible(FALSE))
    .write_lock_marker()
    invisible(identical(.lock_owner_token(), lock_token))
  }

  # Marker'daki sahiplik jetonu (okunamazsa NULL).
  .lock_owner_token <- function() {
    # `tryCatch(error=)` bağlantı açma UYARISINI yakalamaz; eksik marker'da
    # uyarı sızarsa katı test koşucusu düşer.
    if (!isTRUE(file.exists(lock_marker))) return(NULL)
    satirlar <- suppressWarnings(
      tryCatch(readLines(lock_marker, warn = FALSE), error = function(e) character(0))
    )
    jeton <- sub("^token=", "", satirlar[startsWith(satirlar, "token=")])
    if (length(jeton) && nzchar(jeton[1])) jeton[1] else NULL
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
      # Silme doğrulanmadan TRUE dönmek `next` ile sonsuz döngü üretirdi;
      # kırılamayan kilitte zaman aşımı/bekleme yoluna düşülür.
      if (!dir.exists(lock_dir)) {
        return(invisible(TRUE))
      }
      try(
        log_warn("[INDEX] Eski indeks kilidi kırılamadı; zaman aşımı yoluna düşülüyor: {lock_dir}"),
        silent = TRUE
      )
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
      # Dayanıklı marker kilidi tutmanın ÖN KOŞULUDUR: dizin mtime'ı sahiplik
      # kanıtı değildir (Windows/UNC'de yeniden oluşturulan dizin aynı değeri
      # taşıyabilir). Marker geri okunamıyorsa kilitsiz yola düşülür.
      if (identical(.lock_owner_token(), lock_token)) break

      if (is.null(.lock_owner_token())) {
        unlink(lock_dir, recursive = TRUE, force = TRUE)
      }
      acquired <- FALSE
      try(
        log_warn("[INDEX] Kilit sahiplik marker'ı doğrulanamadı; kilitsiz devam ediliyor: {lock_dir}"),
        silent = TRUE
      )
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
    if (isTRUE(require_lock)) {
      stop(sprintf(
        "[INDEX] İndeks kilidi alınamadı; işlem güvenli biçimde yapılamaz: %s",
        lock_dir
      ), call. = FALSE)
    }
    try(
      log_warn("[INDEX] İndeks kilidi alınamadı; mevcut davranışı korumak için kilitsiz devam ediliyor: {lock_dir}"),
      silent = TRUE
    )
    return(force(expr))
  }

  # Uzun süren kilitli işlem marker'ı tazeleyebilsin (bayatlık eşiği CANLI
  # kilidi kırmasın). Önceki kayıt geri yüklenir (iç içe kilit güvenliği).
  onceki_heartbeat <- .FILE_STORE_LOCK_STATE$heartbeat
  .FILE_STORE_LOCK_STATE$heartbeat <- .refresh_lock_marker
  on.exit({
    .FILE_STORE_LOCK_STATE$heartbeat <- onceki_heartbeat
  }, add = TRUE)

  # Kilit YALNIZCA marker hâlâ bizim jetonumuzu taşıyorsa bırakılır; başka
  # kanıt kabul edilmez (bayat kilit yeni sahibe geçtiyse lost update olurdu).
  on.exit({
    if (identical(.lock_owner_token(), lock_token)) {
      unlink(lock_dir, recursive = TRUE, force = TRUE)
    }
  }, add = TRUE)

  force(expr)
}

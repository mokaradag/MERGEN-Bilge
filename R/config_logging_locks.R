# Günlük dosyalarının işletim sistemi kilidi ve sahiplik yardımcıları.

.MERGEN_LOG_NATIVE_LOCKS <- new.env(parent = emptyenv())

# Süreçler arası dizin kilidi. Sahip jetonu kilit içinde tutulur; bayat kilit
# yalnızca tazelenmediğinde (yaş > stale_after) kaldırılır ve kritik adımdan
# önce sahiplik yeniden doğrulanır. Uzun işler kilidi `nabiz` ile tazeler.
.mergen_log_lock_acquire <- function(kilit, wait, stale_after) {
  yerel_kilit <- tryCatch(filelock::lock(paste0(kilit, ".mutex"),
                                        timeout = max(0, wait * 1000)), error = function(e) NULL)
  if (is.null(yerel_kilit)) return(NULL)
  alindi <- FALSE
  on.exit(if (!alindi) filelock::unlock(yerel_kilit), add = TRUE)
  jeton <- sprintf("%d-%s", Sys.getpid(), basename(tempfile("")))
  bitis <- Sys.time() + wait
  repeat {
    if (dir.create(kilit, showWarnings = FALSE)) {
      yazim <- suppressWarnings(try(writeLines(jeton, file.path(kilit, "sahip")), silent = TRUE))
      if (!inherits(yazim, "try-error")) {
        .MERGEN_LOG_NATIVE_LOCKS[[jeton]] <- yerel_kilit
        alindi <- TRUE
        return(jeton)
      }
      # Sahip dosyası yazılamadıysa yetim kilit bırakılmaz.
      unlink(kilit, recursive = TRUE)
      return(NULL)
    }
    zaman <- file.info(c(kilit, file.path(kilit, "sahip")))$mtime
    yas <- if (all(is.na(zaman))) NA_real_ else
      as.numeric(difftime(Sys.time(), max(zaman, na.rm = TRUE), units = "secs"))
    if (isTRUE(yas > stale_after)) {
      sahip <- suppressWarnings(tryCatch(readLines(file.path(kilit, "sahip"), warn = FALSE),
                                          error = function(e) character(0)))
      eski <- paste0(kilit, ".stale-", jeton)
      if (isTRUE(file.rename(kilit, eski))) {
        yeni_zaman <- file.info(c(eski, file.path(eski, "sahip")))$mtime
        yeni_sahip <- suppressWarnings(tryCatch(readLines(file.path(eski, "sahip"), warn = FALSE),
                                                error = function(e) character(0)))
        if (identical(sahip, yeni_sahip) && identical(zaman, yeni_zaman)) {
          unlink(eski, recursive = TRUE)
        } else {
          file.rename(eski, kilit)
        }
      }
    }
    if (Sys.time() > bitis) return(NULL)
    Sys.sleep(0.02)
  }
}

.mergen_log_lock_owned <- function(kilit, jeton) {
  sahip <- suppressWarnings(tryCatch(readLines(file.path(kilit, "sahip"), n = 1L, warn = FALSE),
                                     error = function(e) character(0)))
  identical(sahip, jeton)
}

.mergen_log_lock_release <- function(kilit, jeton) {
  if (.mergen_log_lock_owned(kilit, jeton)) unlink(kilit, recursive = TRUE)
  yerel_kilit <- .MERGEN_LOG_NATIVE_LOCKS[[jeton]]
  if (!is.null(yerel_kilit)) filelock::unlock(yerel_kilit)
  if (exists(jeton, envir = .MERGEN_LOG_NATIVE_LOCKS, inherits = FALSE)) {
    rm(list = jeton, envir = .MERGEN_LOG_NATIVE_LOCKS)
  }
  invisible(NULL)
}

# Nabız: fonksiyon(lar) ya da tazelenecek kilit dizinleri (sahip dosyasının mtime'ı).
.mergen_log_heartbeat <- function(nabiz) {
  if (is.function(nabiz)) nabiz <- list(nabiz)
  for (oge in nabiz) {
    if (is.function(oge)) {
      oge()
    } else if (is.character(oge)) {
      for (kilit in oge) try(Sys.setFileTime(file.path(kilit, "sahip"), Sys.time()), silent = TRUE)
    }
  }
  invisible(NULL)
}

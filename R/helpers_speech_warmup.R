# R/helpers_speech_warmup.R
# VoxCPM2 ısındırma (warmup) durum makinesi. Isındırma TTS servisi için R
# SÜRECİ başına EN FAZLA BİR kez koşar; Shiny oturumu başına tekrarlanmaz.
# Eşzamanlı oturumlar yinelenen ısındırma başlatamaz; başarısızlık sınırlı
# sayıda denemeyle sonlanır ve uygulamanın geri kalanını asla kırmaz.

if (!exists(".mergen_speech_warmup_env", inherits = FALSE)) {
  .mergen_speech_warmup_env <- new.env(parent = emptyenv())
  .mergen_speech_warmup_env$status <- "uninitialized"
  .mergen_speech_warmup_env$attempts <- 0L
  .mergen_speech_warmup_env$last_error <- NULL
  .mergen_speech_warmup_env$started_at <- NULL
  .mergen_speech_warmup_env$finished_at <- NULL
}

#' Isındırma etkin mi? (VOXCPM2_WARMUP_ENABLED, varsayılan TRUE)
mergen_speech_warmup_enabled <- function() {
  raw <- tolower(trimws(Sys.getenv("VOXCPM2_WARMUP_ENABLED", "TRUE")))
  !(raw %in% c("false", "f", "0", "no", "off", "hayır", "hayir", "kapalı", "kapali"))
}

#' İzin verilen en fazla ısındırma denemesi.
mergen_speech_warmup_max_attempts <- function() {
  n <- suppressWarnings(as.integer(Sys.getenv("VOXCPM2_WARMUP_MAX_RETRIES", "2")))
  if (is.na(n) || n < 0L) n <- 2L
  n + 1L
}

#' Isındırma zaman aşımı (saniye).
mergen_speech_warmup_timeout <- function() {
  t <- suppressWarnings(as.numeric(Sys.getenv("VOXCPM2_WARMUP_TIMEOUT", "30")))
  if (is.na(t) || t <= 0) t <- 30
  t
}

#' Güvenli (gizli değer içermeyen) ısındırma durumu anlık görüntüsü.
mergen_speech_warmup_state <- function() {
  env <- .mergen_speech_warmup_env
  list(
    status = env$status,
    attempts = env$attempts,
    last_error = env$last_error,
    started_at = env$started_at,
    finished_at = env$finished_at
  )
}

#' Durum makinesini sıfırla (yalnızca test yalıtımı için).
mergen_speech_warmup_reset <- function() {
  env <- .mergen_speech_warmup_env
  env$status <- "uninitialized"
  env$attempts <- 0L
  env$last_error <- NULL
  env$started_at <- NULL
  env$finished_at <- NULL
  invisible(NULL)
}

#' Yeni bir ısındırma denemesi başlatılmalı mı?
mergen_speech_warmup_should_start <- function() {
  if (!mergen_speech_warmup_enabled()) return(FALSE)
  env <- .mergen_speech_warmup_env
  if (identical(env$status, "ready") || identical(env$status, "warming")) return(FALSE)
  if (identical(env$status, "failed") &&
      env$attempts >= mergen_speech_warmup_max_attempts()) {
    return(FALSE)
  }
  TRUE
}

#' Isındırmayı süreçte bir kez başlat. Gerçek sentez işi `starter_fn` ile
#' enjekte edilir: `starter_fn(on_success, on_failure)` çağrılır ve asenkron
#' tamamlanınca ilgili geri çağrıyı çalıştırır. Eşzamanlı çağrılar tek
#' denemede birleşir.
#'
#' @return TRUE yeni deneme başladıysa; FALSE zaten hazır/koşuyor/tükenmişse.
mergen_speech_warmup_start_once <- function(starter_fn) {
  if (!mergen_speech_warmup_should_start()) return(invisible(FALSE))

  env <- .mergen_speech_warmup_env
  env$status <- "warming"
  env$attempts <- env$attempts + 1L
  env$started_at <- Sys.time()
  env$last_error <- NULL

  on_success <- function() {
    env$status <- "ready"
    env$finished_at <- Sys.time()
    cat("[SPEECH] VoxCPM2 ısındırma tamamlandı (süreç kapsamlı).\n")
    invisible(NULL)
  }

  on_failure <- function(error_text = "bilinmeyen hata") {
    env$status <- "failed"
    env$finished_at <- Sys.time()
    env$last_error <- as.character(error_text)[1]
    cat(sprintf(
      "[SPEECH] VoxCPM2 ısındırma başarısız (deneme %d/%d): %s\n",
      env$attempts, mergen_speech_warmup_max_attempts(), env$last_error
    ))
    invisible(NULL)
  }

  result <- tryCatch({
    starter_fn(on_success, on_failure)
    TRUE
  }, error = function(e) {
    on_failure(conditionMessage(e))
    FALSE
  })

  invisible(isTRUE(result))
}

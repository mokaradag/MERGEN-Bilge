# ==============================================================================
# Dosya Yolu: R/helpers_tts_queue.R
# Açıklama:   Sınırlı eşzamanlılık (bounded concurrency) TTS iş kuyruğu.
#             VoxCPM2 referans-ses istekleri sınırsız paralel gönderilmemelidir.
#             Bu kuyruk süreç kapsamında en fazla N işi aynı anda çalıştırır
#             (varsayılan 2, LOCAL_TTS_MAX_CONCURRENCY ile ayarlanır), kalanları
#             FIFO sırayla bekletir ve iptal-farkındalıdır (durdurulmuş bir istekten
#             sonra eskimiş parçalar başlatılmaz).
#
#             Oynatma sırası istemci tarafında chunkIndex/index ile korunduğundan
#             kuyruk çıktıyı yeniden sıralamaz; yalnızca eşzamanlılığı sınırlar.
#             Bir işin hatası kuyruğu kilitlemez; aktif sayaç her durumda azaltılır.
# ==============================================================================

if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
}

#' Sınırlı Eşzamanlılık Kuyruğu Oluştur
#'
#' @param max_concurrency Aynı anda çalışacak en fazla iş sayısı
#' @return Kuyruk ortamı: submit, active_count, pending_count, stats, set_max
mergen_tts_create_queue <- function(max_concurrency = 2L) {
  q <- new.env(parent = emptyenv())
  q$max <- max(1L, as.integer(max_concurrency %||% 2L))
  q$active <- 0L
  q$pending <- list()
  q$submitted <- 0L
  q$started <- 0L
  q$completed <- 0L
  q$cancelled <- 0L

  run_record <- function(rec) {
    cancelled <- FALSE
    if (is.function(rec$should_cancel)) {
      cancelled <- tryCatch(isTRUE(rec$should_cancel()), error = function(e) FALSE)
    }
    if (isTRUE(cancelled)) {
      q$cancelled <- q$cancelled + 1L
      rec$resolve(list(
        success = FALSE, audio_src = NULL, cancelled = TRUE,
        voice = NULL, duration = 0, error = "İstek durdurulduğu için parça atlandı."
      ))
      return(invisible(NULL))
    }

    q$active <- q$active + 1L
    q$started <- q$started + 1L

    task_promise <- tryCatch(
      rec$factory(),
      error = function(e) promises::promise_reject(e)
    )

    finish <- function() {
      q$active <- max(0L, q$active - 1L)
      q$completed <- q$completed + 1L
      pump()
    }

    promises::then(
      task_promise,
      onFulfilled = function(value) {
        finish()
        rec$resolve(value)
      },
      onRejected = function(err) {
        finish()
        rec$reject(err)
      }
    )
    invisible(NULL)
  }

  pump <- function() {
    while (q$active < q$max && length(q$pending) > 0L) {
      rec <- q$pending[[1L]]
      q$pending <- q$pending[-1L]
      run_record(rec)
    }
  }

  q$submit <- function(factory, should_cancel = NULL) {
    if (!is.function(factory)) stop("factory bir fonksiyon olmalıdır.", call. = FALSE)
    captured <- new.env(parent = emptyenv())
    p <- promises::promise(function(resolve, reject) {
      captured$resolve <- resolve
      captured$reject <- reject
    })
    rec <- list(
      factory = factory,
      should_cancel = should_cancel,
      resolve = captured$resolve,
      reject = captured$reject
    )
    q$submitted <- q$submitted + 1L
    q$pending[[length(q$pending) + 1L]] <- rec
    pump()
    p
  }

  q$active_count <- function() q$active
  q$pending_count <- function() length(q$pending)
  q$set_max <- function(n) {
    q$max <- max(1L, as.integer(n %||% q$max))
    pump()
    invisible(q$max)
  }
  q$stats <- function() {
    list(
      max = q$max, active = q$active, pending = length(q$pending),
      submitted = q$submitted, started = q$started,
      completed = q$completed, cancelled = q$cancelled
    )
  }

  q
}

#' Süreç Kapsamlı Varsayılan TTS Kuyruğu
#'
#' @description Yapılandırmadan (max_concurrency) tembel olarak oluşturulur ve
#'   options üzerinde saklanır; tüm oturumlar/parçalar aynı kuyruğu paylaşır.
#' @param config TTS yapılandırması
#' @return Kuyruk ortamı
mergen_tts_default_queue <- function(config = NULL) {
  q <- getOption("mergen.tts_default_queue", NULL)
  if (is.null(q) || !is.environment(q)) {
    if (is.null(config)) config <- if (exists("tts_config", inherits = TRUE)) get("tts_config", inherits = TRUE) else list()
    maxc <- suppressWarnings(as.integer(config$max_concurrency %||% 2L))
    if (is.na(maxc) || maxc < 1L) maxc <- 2L
    q <- mergen_tts_create_queue(maxc)
    options(mergen.tts_default_queue = q)
  }
  q
}

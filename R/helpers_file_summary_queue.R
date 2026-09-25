# ==============================================================================
# Dosya Yolu: R/helpers_file_summary_queue.R
# Açıklama: Yüklenen dosyaların LLM özet işleri için eşzamanlılık sınırlı kuyruk
#           (R/helpers_file_pipeline.R processAndSummarizeFile kullanır).
# ==============================================================================

# Dosya özetleri paylaşılan işçi havuzunu tüketmesin diye eşzamanlı özet işi
# sınırlanır (MERGEN_FILE_SUMMARY_MAX_CONCURRENT, varsayılan 2; havuzdan en az bir
# işçi etkileşimli işe ayrılır); kalanlar sırayla başlar. Toplu yüklemede tüm işçiler özetle doluyor, diğer kullanıcıların
# sohbet istekleri kuyrukta bekliyordu.
.FILE_SUMMARY_QUEUE <- new.env(parent = emptyenv())
.FILE_SUMMARY_QUEUE$active <- 0L
.FILE_SUMMARY_QUEUE$pending <- list()
.FILE_SUMMARY_QUEUE$rejected_total <- 0L
.FILE_SUMMARY_QUEUE$pump_scheduled <- FALSE

file_summary_int_setting <- function(env_name, default_value) {
  deger <- suppressWarnings(as.integer(Sys.getenv(env_name, as.character(default_value))))
  if (length(deger) != 1L || is.na(deger) || deger < 1L) default_value else deger
}

file_summary_max_concurrent <- function() {
  file_summary_int_setting("MERGEN_FILE_SUMMARY_MAX_CONCURRENT", 2L)
}

file_summary_pool_size <- function() {
  n <- tryCatch(suppressWarnings(as.integer(future::nbrOfWorkers())), error = function(e) NA_integer_)
  if (length(n) != 1L || is.na(n) || n < 1L) 1L else n
}

file_summary_free_workers <- function() {
  n <- tryCatch(suppressWarnings(as.integer(future::nbrOfFreeWorkers())), error = function(e) NA_integer_)
  if (length(n) != 1L) NA_integer_ else n
}

# Özetler paylaşılan havuzun tamamını tutamaz. En az iki işçili havuzda özet
# sınırı havuzdan bir eksiktir ve özet yalnız bir işçi etkileşimli işe (sohbet,
# LLM) boş kalacaksa başlar. Tek işçili havuz bölünemez: orada özet yalnız işçi
# boştayken ve tek tek çalışır (işçi sayısı çekirdek - 1 ile sınırlıdır; ayrık
# kapasite en az üç çekirdek ister).
file_summary_effective_limit <- function() {
  havuz <- file_summary_pool_size()
  if (havuz < 2L) return(1L)
  min(file_summary_max_concurrent(), havuz - 1L)
}

file_summary_has_capacity <- function() {
  if (.FILE_SUMMARY_QUEUE$active >= file_summary_effective_limit()) return(FALSE)
  bos <- file_summary_free_workers()
  if (is.na(bos)) return(TRUE)
  bos > (if (file_summary_pool_size() >= 2L) 1L else 0L)
}

# Bekleyen kuyruk da sınırlıdır (MERGEN_FILE_SUMMARY_MAX_QUEUE, varsayılan 64):
# her kayıt oturum ve dosya durumunu tuttuğundan sınırsız büyüyemez.
file_summary_max_queue <- function() {
  file_summary_int_setting("MERGEN_FILE_SUMMARY_MAX_QUEUE", 64L)
}

# Kuyruk doluysa iş sessizce düşürülmez: FALSE döner ve çağıran kullanıcıyı uyarır.
file_summary_schedule <- function(start_fn, session = NULL) {
  file_summary_prune_closed()
  if (length(.FILE_SUMMARY_QUEUE$pending) >= file_summary_max_queue()) {
    .FILE_SUMMARY_QUEUE$rejected_total <- .FILE_SUMMARY_QUEUE$rejected_total + 1L
    return(FALSE)
  }
  .FILE_SUMMARY_QUEUE$pending[[length(.FILE_SUMMARY_QUEUE$pending) + 1L]] <-
    list(start = start_fn, session = session)
  file_summary_pump()
  TRUE
}

file_summary_session_alive <- function(session) {
  if (is.null(session)) return(TRUE)
  kapali <- tryCatch(is.function(session$isClosed) && isTRUE(session$isClosed()),
                     error = function(e) TRUE)
  !isTRUE(kapali)
}

# Kapanan oturumların bekleyen kayıtları sıranın başına gelmeden bırakılır.
file_summary_prune_closed <- function() {
  bekleyen <- .FILE_SUMMARY_QUEUE$pending
  if (!length(bekleyen)) return(invisible(0L))
  canli <- vapply(bekleyen, function(kayit) file_summary_session_alive(kayit$session), logical(1))
  .FILE_SUMMARY_QUEUE$pending <- bekleyen[canli]
  invisible(sum(!canli))
}

file_summary_pump <- function() {
  file_summary_prune_closed()
  while (length(.FILE_SUMMARY_QUEUE$pending) > 0L && file_summary_has_capacity()) {
    kayit <- .FILE_SUMMARY_QUEUE$pending[[1L]]
    .FILE_SUMMARY_QUEUE$pending[[1L]] <- NULL
    # Kapanan oturumun kuyruktaki özeti başlatılmaz.
    if (!file_summary_session_alive(kayit$session)) next

    .FILE_SUMMARY_QUEUE$active <- .FILE_SUMMARY_QUEUE$active + 1L
    serbest <- local({
      birakildi <- FALSE
      function(...) {
        if (birakildi) return(invisible(NULL))
        birakildi <<- TRUE
        .FILE_SUMMARY_QUEUE$active <- max(0L, .FILE_SUMMARY_QUEUE$active - 1L)
        later::later(file_summary_pump, 0)
        invisible(NULL)
      }
    })
    # Başlatma hatası kuyruğu kilitlemez ama sessizce de yutulmaz.
    p <- tryCatch(kayit$start(), error = function(e) {
      cat("[FILE SUMMARY] Özet işi başlatılamadı:", conditionMessage(e), "\n")
      NULL
    })
    if (promises::is.promising(p)) {
      promises::then(promises::finally(p, serbest), onRejected = function(e) NULL)
    } else {
      serbest()
    }
  }
  # İşçiler etkileşimli işlerle doluysa kuyruk kısa aralıkla yeniden denenir.
  if (length(.FILE_SUMMARY_QUEUE$pending) > 0L &&
      .FILE_SUMMARY_QUEUE$active < file_summary_effective_limit() &&
      !isTRUE(.FILE_SUMMARY_QUEUE$pump_scheduled)) {
    .FILE_SUMMARY_QUEUE$pump_scheduled <- TRUE
    later::later(function() {
      .FILE_SUMMARY_QUEUE$pump_scheduled <- FALSE
      file_summary_pump()
    }, 1)
  }
  invisible(NULL)
}

# İlk dosya özetindeki bağımlılık taraması (büyük .GlobalEnv'de saniyeler) olay
# döngüsünü dondurmasın: tarama oturum kabul edilmeden önce bir kez yapılır
# (app.R onStart). Yalnız adlar önbelleğe girer; değerler her gönderimde tazedir.
file_summary_warm_dependencies <- function() {
  if (!exists("file_summary_task_fn", mode = "function") ||
      !exists("worker_monitor_auto_globals", mode = "function")) {
    return(invisible(FALSE))
  }
  sonuc <- try(worker_monitor_auto_globals("file_summary", file_summary_task_fn("", "", list())),
               silent = TRUE)
  invisible(!inherits(sonuc, "try-error"))
}

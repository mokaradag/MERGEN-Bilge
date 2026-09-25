# ==============================================================================
# Dosya Yolu: R/helpers_file_summary_queue.R
# Açıklama: Yüklenen dosyaların LLM özet işleri için eşzamanlılık sınırlı kuyruk
#           (R/helpers_file_pipeline.R processAndSummarizeFile kullanır).
# ==============================================================================

# Dosya özetleri paylaşılan işçi havuzunu tüketmesin diye eşzamanlı özet işi
# sınırlanır (MERGEN_FILE_SUMMARY_MAX_CONCURRENT, varsayılan 2); kalanlar sırayla
# başlar. Toplu yüklemede tüm işçiler özetle doluyor, diğer kullanıcıların
# sohbet istekleri kuyrukta bekliyordu.
.FILE_SUMMARY_QUEUE <- new.env(parent = emptyenv())
.FILE_SUMMARY_QUEUE$active <- 0L
.FILE_SUMMARY_QUEUE$pending <- list()

file_summary_max_concurrent <- function() {
  deger <- suppressWarnings(as.integer(Sys.getenv("MERGEN_FILE_SUMMARY_MAX_CONCURRENT", "2")))
  if (length(deger) != 1L || is.na(deger) || deger < 1L) 2L else deger
}

file_summary_schedule <- function(start_fn, session = NULL) {
  .FILE_SUMMARY_QUEUE$pending[[length(.FILE_SUMMARY_QUEUE$pending) + 1L]] <-
    list(start = start_fn, session = session)
  file_summary_pump()
}

file_summary_session_alive <- function(session) {
  if (is.null(session)) return(TRUE)
  kapali <- tryCatch(is.function(session$isClosed) && isTRUE(session$isClosed()),
                     error = function(e) TRUE)
  !isTRUE(kapali)
}

file_summary_pump <- function() {
  while (.FILE_SUMMARY_QUEUE$active < file_summary_max_concurrent() &&
         length(.FILE_SUMMARY_QUEUE$pending) > 0L) {
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
    p <- tryCatch(kayit$start(), error = function(e) NULL)
    if (promises::is.promising(p)) {
      promises::then(promises::finally(p, serbest), onRejected = function(e) NULL)
    } else {
      serbest()
    }
  }
  invisible(NULL)
}

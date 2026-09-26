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
.FILE_SUMMARY_QUEUE$active_by <- integer(0)
.FILE_SUMMARY_QUEUE$pending <- list()
.FILE_SUMMARY_QUEUE$served_seq <- 0L
.FILE_SUMMARY_QUEUE$last_served <- integer(0)
.FILE_SUMMARY_QUEUE$rejected_total <- 0L
.FILE_SUMMARY_QUEUE$pump_scheduled <- FALSE

file_summary_int_setting <- function(env_name, default_value) {
  deger <- suppressWarnings(as.integer(Sys.getenv(env_name, as.character(default_value))))
  if (length(deger) != 1L || is.na(deger) || deger < 1L) default_value else deger
}

file_summary_max_concurrent <- function() {
  file_summary_int_setting("MERGEN_FILE_SUMMARY_MAX_CONCURRENT", 2L)
}

# Eşzamansız olmayan planda (sequential: küme kurulamadı ya da futures kapalı)
# özet ana olay döngüsünde çalışıp tüm oturumları dondurur; kapasite 0 sayılır.
file_summary_pool_size <- function() {
  plan_sinifi <- tryCatch(class(future::plan("list")[[1]]), error = function(e) character(0))
  if (!length(plan_sinifi) || any(c("sequential", "uniprocess", "transparent") %in% plan_sinifi)) return(0L)
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
  if (havuz < 1L) return(0L)
  if (havuz < 2L) return(1L)
  min(file_summary_max_concurrent(), havuz - 1L)
}

# Boş işçi sayısı ölçülemezse özet başlamaz (kapalı-başarısız); kuyruk saniyede
# bir yeniden dener.
file_summary_has_capacity <- function() {
  sinir <- file_summary_effective_limit()
  if (sinir < 1L || .FILE_SUMMARY_QUEUE$active >= sinir) return(FALSE)
  bos <- file_summary_free_workers()
  if (is.na(bos)) return(FALSE)
  bos > (if (file_summary_pool_size() >= 2L) 1L else 0L)
}

# Bekleyen kuyruk da sınırlıdır (MERGEN_FILE_SUMMARY_MAX_QUEUE, varsayılan 64):
# her kayıt oturum ve dosya durumunu tuttuğundan sınırsız büyüyemez.
file_summary_max_queue <- function() {
  file_summary_int_setting("MERGEN_FILE_SUMMARY_MAX_QUEUE", 64L)
}

# Tek oturum ortak bekleme bütçesini tüketemez
# (MERGEN_FILE_SUMMARY_MAX_QUEUE_PER_SESSION, varsayılan 16).
file_summary_max_queue_per_session <- function() {
  min(file_summary_int_setting("MERGEN_FILE_SUMMARY_MAX_QUEUE_PER_SESSION", 16L),
      file_summary_max_queue())
}

file_summary_session_key <- function(session) {
  anahtar <- as.character(session$token %||% "")[1]
  if (length(anahtar) != 1L || is.na(anahtar)) "" else anahtar
}

# Kuyruk doluysa ya da arka plan işçisi yoksa iş sessizce düşürülmez: FALSE
# döner ve çağıran kullanıcıyı uyarır.
file_summary_schedule <- function(start_fn, session = NULL) {
  file_summary_prune_closed()
  anahtar <- file_summary_session_key(session)
  bekleyen <- .FILE_SUMMARY_QUEUE$pending
  ayni_oturum <- sum(vapply(bekleyen, function(k) identical(k$anahtar, anahtar), logical(1)))
  if (file_summary_effective_limit() < 1L || length(bekleyen) >= file_summary_max_queue() ||
      (nzchar(anahtar) && ayni_oturum >= file_summary_max_queue_per_session())) {
    .FILE_SUMMARY_QUEUE$rejected_total <- .FILE_SUMMARY_QUEUE$rejected_total + 1L
    return(FALSE)
  }
  .FILE_SUMMARY_QUEUE$pending[[length(bekleyen) + 1L]] <-
    list(start = start_fn, session = session, anahtar = anahtar)
  file_summary_pump()
  TRUE
}

file_summary_pending_count <- function() {
  as.integer(length(.FILE_SUMMARY_QUEUE$pending))
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
  # Bekleyen ya da çalışan işi kalmayan oturumun sıra kaydı tutulmaz.
  kullanilan <- c(vapply(.FILE_SUMMARY_QUEUE$pending, function(k) k$anahtar %||% "", character(1)),
                  names(.FILE_SUMMARY_QUEUE$active_by))
  son <- .FILE_SUMMARY_QUEUE$last_served
  .FILE_SUMMARY_QUEUE$last_served <- son[names(son) %in% kullanilan]
  invisible(sum(!canli))
}

# Sıradaki iş önce en az özeti çalışan, sonra en uzun süredir hizmet almamış
# oturumdan seçilir (eşitlikte FIFO). Tek yuvalı havuzda da sıra oturumlar
# arasında döner; bir oturumun toplu yüklemesi diğerlerini geciktirmez.
file_summary_next_index <- function() {
  deger <- function(v, k) {
    n <- if (nzchar(k)) v[k] else NA_integer_
    if (length(n) != 1L || is.na(n)) 0L else as.integer(n)
  }
  anahtarlar <- vapply(.FILE_SUMMARY_QUEUE$pending, function(k) k$anahtar %||% "", character(1))
  yuk <- vapply(anahtarlar, function(k) deger(.FILE_SUMMARY_QUEUE$active_by, k), integer(1))
  son <- vapply(anahtarlar, function(k) deger(.FILE_SUMMARY_QUEUE$last_served, k), integer(1))
  order(yuk, son, seq_along(anahtarlar))[1]
}

# Yuva yalnız iş (söz) gerçekten bittiğinde bırakılır: oturum kapansa da işçi
# LLM çağrısını sürdürebilir; erken bırakmak eşzamanlılık sınırını aşardı.
# Anahtar argüman olarak bağlanır; aynı pompada başlayan işler karışmaz.
file_summary_release_fn <- function(anahtar) {
  force(anahtar)
  birakildi <- FALSE
  function(...) {
    if (birakildi) return(invisible(NULL))
    birakildi <<- TRUE
    .FILE_SUMMARY_QUEUE$active <- max(0L, .FILE_SUMMARY_QUEUE$active - 1L)
    if (nzchar(anahtar) && !is.na(.FILE_SUMMARY_QUEUE$active_by[anahtar])) {
      kalan <- .FILE_SUMMARY_QUEUE$active_by[anahtar] - 1L
      .FILE_SUMMARY_QUEUE$active_by <- if (kalan > 0L) {
        replace(.FILE_SUMMARY_QUEUE$active_by, anahtar, kalan)
      } else {
        .FILE_SUMMARY_QUEUE$active_by[names(.FILE_SUMMARY_QUEUE$active_by) != anahtar]
      }
    }
    later::later(file_summary_pump, 0)
    invisible(NULL)
  }
}

file_summary_pump <- function() {
  file_summary_prune_closed()
  while (length(.FILE_SUMMARY_QUEUE$pending) > 0L && file_summary_has_capacity()) {
    sira <- file_summary_next_index()
    kayit <- .FILE_SUMMARY_QUEUE$pending[[sira]]
    .FILE_SUMMARY_QUEUE$pending[[sira]] <- NULL
    # Kapanan oturumun kuyruktaki özeti başlatılmaz.
    if (!file_summary_session_alive(kayit$session)) next

    anahtar <- kayit$anahtar %||% ""
    .FILE_SUMMARY_QUEUE$active <- .FILE_SUMMARY_QUEUE$active + 1L
    .FILE_SUMMARY_QUEUE$served_seq <- .FILE_SUMMARY_QUEUE$served_seq + 1L
    if (nzchar(anahtar)) {
      onceki <- .FILE_SUMMARY_QUEUE$active_by[anahtar]
      .FILE_SUMMARY_QUEUE$active_by[anahtar] <- if (is.na(onceki)) 1L else onceki + 1L
      .FILE_SUMMARY_QUEUE$last_served[anahtar] <- .FILE_SUMMARY_QUEUE$served_seq
    }
    # Oturum kapanınca işçi durdurma dosyasını (processAndSummarizeFile) görüp
    # LLM çağrısını atlar; yuva yine sözün kapanışında bırakılır.
    serbest <- file_summary_release_fn(anahtar)
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
# döngüsünü dondurmasın: tarama oturum kabul edilmeden önce yapılır (app.R
# onStart). Başarısız tarama önbelleğe girmez; bir kez yeniden denenir ve
# sonuç günlüğe yazılır. Yalnız adlar önbelleğe girer; değerler her gönderimde tazedir.
file_summary_warm_dependencies <- function(attempts = 2L) {
  if (!exists("file_summary_task_fn", mode = "function") ||
      !exists("worker_monitor_auto_globals", mode = "function")) {
    return(invisible(FALSE))
  }
  for (deneme in seq_len(max(1L, as.integer(attempts)))) {
    sonuc <- try(worker_monitor_auto_globals("file_summary", file_summary_task_fn("", "", list())),
                 silent = TRUE)
    if (!inherits(sonuc, "try-error") && isTRUE(sonuc$ok)) return(invisible(TRUE))
  }
  cat("[FILE SUMMARY] UYARI: Özet bağımlılık ısıtması başarısız; ilk özet taramayı yeniden yapacak.\n")
  invisible(FALSE)
}

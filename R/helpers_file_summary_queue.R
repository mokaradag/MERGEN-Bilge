# ==============================================================================
# Dosya Yolu: R/helpers_file_summary_queue.R
# Açıklama: Yüklenen dosyaların LLM özet işleri için eşzamanlılık sınırlı kuyruk
#           (R/helpers_file_pipeline.R processAndSummarizeFile kullanır).
#           Kapasite/sınır kararları R/helpers_file_summary_capacity.R'dedir.
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

# Kuyruk bütçesi ve adillik oturum (sekme) değil KULLANICI başınadır: kimliği
# doğrulanmış sahip varsa anahtar odur; yoksa oturum jetonu kullanılır.
file_summary_session_key <- function(session, sahip = NULL) {
  uid <- suppressWarnings(as.integer(sahip %||% NA_integer_))[1]
  if (length(uid) == 1L && !is.na(uid) && uid > 0L) return(paste0("u:", uid))
  anahtar <- as.character(session$token %||% "")[1]
  if (length(anahtar) != 1L || is.na(anahtar)) "" else anahtar
}

# Kuyruk doluysa ya da arka plan işçisi yoksa iş sessizce düşürülmez: FALSE
# döner (`neden` özniteliği: "isci_yok" ya da "kuyruk_dolu") ve çağıran
# kullanıcıyı uyarır. `sahip` kaydı yükleyen kullanıcıya bağlar; oturum başka
# kullanıcıya geçerse kayıt bırakılır. `on_drop` kayıt başlatılamadığında ya da
# bırakıldığında çağrılır (bildirim kapanır, kullanıcı uyarılır).
file_summary_schedule <- function(start_fn, session = NULL, sahip = NULL, on_drop = NULL) {
  file_summary_prune_closed()
  anahtar <- file_summary_session_key(session, sahip)
  bekleyen <- .FILE_SUMMARY_QUEUE$pending
  ayni_sahip <- sum(vapply(bekleyen, function(k) identical(k$anahtar, anahtar), logical(1)))
  neden <- if (file_summary_effective_limit() < 1L) {
    "isci_yok"
  } else if (length(bekleyen) >= file_summary_max_queue() ||
             (nzchar(anahtar) && ayni_sahip >= file_summary_max_queue_per_session())) {
    "kuyruk_dolu"
  } else {
    ""
  }
  if (nzchar(neden)) {
    .FILE_SUMMARY_QUEUE$rejected_total <- .FILE_SUMMARY_QUEUE$rejected_total + 1L
    return(structure(FALSE, neden = neden))
  }
  .FILE_SUMMARY_QUEUE$pending[[length(bekleyen) + 1L]] <-
    list(start = start_fn, session = session, anahtar = anahtar, sahip = sahip, on_drop = on_drop)
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

# Kayıt yalnız oturumu açık ve (sahibi varsa) oturumun canlı kimliği hâlâ o
# sahipse geçerlidir; A -> B geçişinde A'nın işleri B'nin bütçesini tüketmez.
file_summary_record_live <- function(kayit) {
  if (!file_summary_session_alive(kayit$session)) return(FALSE)
  sahip <- suppressWarnings(as.integer(kayit$sahip %||% NA_integer_))[1]
  if (length(sahip) != 1L || is.na(sahip) || sahip <= 0L) return(TRUE)
  canli <- tryCatch(kayit$session$userData$user_id, error = function(e) NULL)
  canli <- if (exists("mergen_canonical_user_id", mode = "function")) {
    mergen_canonical_user_id(canli %||% 0L)
  } else {
    suppressWarnings(as.integer(canli %||% 0L))[1]
  }
  identical(as.integer(canli), sahip)
}

# Geçersizleşen bekleyen kayıtlar sıranın başına gelmeden bırakılır; sahip
# değişimiyle bırakılan kayıt çağıranına bildirilir.
file_summary_prune_closed <- function() {
  bekleyen <- .FILE_SUMMARY_QUEUE$pending
  canli <- vapply(bekleyen, file_summary_record_live, logical(1))
  .FILE_SUMMARY_QUEUE$pending <- bekleyen[canli]
  for (kayit in bekleyen[!canli]) {
    if (is.function(kayit$on_drop) && file_summary_session_alive(kayit$session)) {
      try(kayit$on_drop(simpleError("Oturum kimliği değişti; özet iptal edildi.")), silent = TRUE)
    }
  }
  # Bekleyen ya da çalışan işi kalmayan anahtarın sıra kaydı tutulmaz (kuyruk
  # boşken de temizlenir; süreç boyunca büyümez).
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
    # Kapanan ya da sahibi değişen oturumun kuyruktaki özeti başlatılmaz.
    if (!file_summary_record_live(kayit)) next

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
    # Başlatma hatası kuyruğu kilitlemez ve sessizce de yutulmaz: çağıranın
    # hata yolu (bildirim kapatma, kullanıcı uyarısı) çalışır.
    p <- tryCatch(kayit$start(), error = function(e) {
      cat("[FILE SUMMARY] Özet işi başlatılamadı:", conditionMessage(e), "\n")
      if (is.function(kayit$on_drop)) try(kayit$on_drop(e), silent = TRUE)
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

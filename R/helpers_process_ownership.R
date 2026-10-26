# Süreç sahipliği: TRUE canlı, FALSE ölü (kanıtlı), NA bilinmiyor. Uzak veya
# belirsiz sahiplik ölüm kanıtı sayılmaz. `since` (marker mtime) verilirse o
# andan sonra doğan aynı PID yeniden kullanılmıştır; eski sahip ölmüştür. Saat
# kayması (UNC sunucusu) canlı sahibi ölü göstermesin diye varsayılan pay geniştir.
mergen_pid_status <- function(pid, host, since = NULL, slack = 300) {
  pid <- suppressWarnings(as.integer(pid)[1])
  if (length(pid) != 1L || is.na(pid) || pid <= 0L ||
      !identical(host, unname(Sys.info()[["nodename"]]))) return(NA)
  alive <- tryCatch(pid %in% ps::ps_pids(), error = function(e) NA)
  if (!isTRUE(alive) || is.null(since) || is.na(since)) return(alive)
  created <- tryCatch(as.numeric(ps::ps_create_time(ps::ps_handle(pid))), error = function(e) NA_real_)
  !(is.finite(created) && created > as.numeric(since) + slack)
}

# ORTAK SAHİP GERİ KAZANIM KURALI (kilit, rezervasyon, alım marker'ı, kira).
#  - yerel ve canlı sahip: asla (fail closed)
#  - kanıtlı ölü sahip: hemen
#  - doğrulanamayan sahip (eski/işaretsiz/bozuk marker, uzak host, sorgulanamayan
#    PID): yalnızca bayatlık eşiği aşılınca
# `self_reclaim`: kilidi yalnız eşzamanlı (senkron) kod tutar; aynı süreç
# marker'ı yeniden okuyorsa kritik bölümde değildir ve bırakma hatasından kalan
# kendi kilidi yaşla geri kazanılır. Diğer kaynaklarda canlı süreç canlıdır.
mergen_owner_reclaimable <- function(pid, host, age_sec, stale_sec, since = NULL,
                                     self_reclaim = FALSE) {
  pid <- suppressWarnings(as.integer(pid %||% NA_integer_)[1])
  host <- as.character(host %||% NA_character_)[1]
  yerel_ayni <- isTRUE(self_reclaim) && !is.na(pid) && identical(pid, as.integer(Sys.getpid())) &&
    identical(host, unname(Sys.info()[["nodename"]]))
  durum <- if (yerel_ayni) NA else mergen_pid_status(pid, host, since = since)
  if (isTRUE(durum)) return(FALSE)
  if (identical(durum, FALSE)) return(TRUE)
  age_sec <- suppressWarnings(as.numeric(age_sec)[1])
  stale_sec <- suppressWarnings(as.numeric(stale_sec)[1])
  isTRUE(is.finite(age_sec) && is.finite(stale_sec) && age_sec > stale_sec)
}

# Satır tabanlı sahip marker'ı (kilit, reaper, rezervasyon). Jeton "pid-..."
# biçimindedir; host satırı olmayan eski biçim doğrulanamayan sahip sayılır.
mergen_lock_owner_reclaimable <- function(marker, token = NULL, stale_sec = Inf,
                                          age_paths = c(marker, dirname(marker)),
                                          self_reclaim = FALSE) {
  lines <- suppressWarnings(tryCatch(readLines(marker, warn = FALSE), error = function(e) character()))
  host <- sub("^host=", "", lines[startsWith(lines, "host=")])
  pid <- if (is.null(token) || is.na(token)) sub("^pid=", "", lines[startsWith(lines, "pid=")]) else
    sub("-.*$", "", token)
  bilgi <- NULL
  for (yol in age_paths) {
    bilgi <- tryCatch(file.info(yol)$mtime[1], error = function(e) NA)
    if (length(bilgi) == 1L && !is.na(bilgi)) break
  }
  yas <- if (length(bilgi) == 1L && !is.na(bilgi)) as.numeric(difftime(Sys.time(), bilgi, units = "secs")) else NA_real_
  mergen_owner_reclaimable(if (length(pid) == 1L) pid else NA, if (length(host) == 1L) host else NA,
                           yas, stale_sec, since = if (length(bilgi) == 1L) bilgi else NULL,
                           self_reclaim = self_reclaim)
}

# Geri kazanım muteksi: edinme hatası "muteks yok" demektir, istisna değildir.
mergen_reclaim_mutex <- function(path, timeout = 0, exclusive = TRUE) {
  tryCatch({
    io <- if (exists("mergen_io_path", mode = "function", inherits = TRUE)) mergen_io_path(path) else path
    filelock::lock(io, timeout = timeout, exclusive = exclusive)
  }, error = function(e) NULL)
}

mergen_cancellable_worker_available <- function(lane = NULL, priority = 0L) {
  hazir <- requireNamespace("callr", quietly = TRUE) && requireNamespace("promises", quietly = TRUE) &&
    requireNamespace("later", quietly = TRUE) &&
    exists("mergen_cancellable_worker_promise", mode = "function", inherits = TRUE)
  if (!hazir || is.null(lane)) return(hazir)
  # Kabul edilebilir yer: kuyruk sınırı ve şeridin boş kapasitesi aynı kuralla.
  isTRUE(mergen_cancellable_worker_admissible(lane, priority))
}

# Bildirim sahiplik sonucundan ayrıdır; karantinada lease/geri alma bekler.
.mergen_worker_uncertain_notifier <- function(current) {
  domain <- shiny::getDefaultReactiveDomain()
  function(error) {
    log_warn("[WORKER] Arka plan işi karantinada; süreç ölümü bekleniyor.")
    if (!is.null(domain) && !isTRUE(domain$isClosed()) &&
        isTRUE(tryCatch(current(), error = function(e) FALSE)))
      shiny::showNotification(conditionMessage(error), type = "error", session = domain)
  }
}

cc_run_state_reference <- function(rv) {
  ref <- shiny::isolate(rv$run_state_ref)
  if (!is.environment(ref)) {
    ref <- new.env(parent = emptyenv())
    ref$rv <- rv
    rv$run_state_ref <- ref
  }
  ref
}

cc_detach_run_state <- function(ref, session) {
  rv <- ref$rv
  if (shiny::is.reactivevalues(rv))
    rv <- list2env(shiny::isolate(shiny::reactiveValuesToList(rv, all.names = TRUE)), parent = emptyenv())
  ud <- session$userData
  owner <- ud$user_id
  generation <- ud$kimlik_nesli %||% 0L
  rv$run_owner_guard <- function() identical(ud$user_id, owner) &&
    identical(ud$kimlik_nesli %||% 0L, generation)
  ref$rv <- rv
  invisible(rv)
}

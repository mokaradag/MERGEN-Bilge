# ==============================================================================
# R/utils_rate_limiter.R
# Hız sınırlama mekanizmaları (kullanıcı bazlı ve global) ve
# paralel işçi havuzu (worker pool) yapılandırması.
# global.R tarafından config_logging.R'den sonra source() ile çağrılır.
# ==============================================================================

# --- KULLANICI BAZLI HIZ SINIRLANDIRICI ---
rate_limiter <- list(
  max_requests_per_user = 10,
  window_size = 60,
  requests = new.env(),
  max_users_cache = 1000
)

# --- GLOBAL HIZ SINIRLANDIRICI (tüm kullanıcılar genelinde) ---
# Environment kullanarak daha verimli bellek yönetimi
global_rate_limiter <- new.env(parent = emptyenv())
global_rate_limiter$max_total_requests <- 100
global_rate_limiter$window_size <- 60
global_rate_limiter$max_buffer_size <- 200
global_rate_limiter$requests <- list()
global_rate_limiter$last_cleanup <- Sys.time()

# Global hız limiti kontrolü
check_global_rate_limit <- function() {
  current_time <- Sys.time()
  
  # Eski istekleri temizle
  global_rate_limiter$requests <- Filter(function(t) {
    difftime(current_time, t, units = "secs") < global_rate_limiter$window_size
  }, global_rate_limiter$requests)
  
  # Bellek taşması koruması: buffer çok büyükse agresif temizlik yap
  if (length(global_rate_limiter$requests) > global_rate_limiter$max_buffer_size) {
    half_window <- global_rate_limiter$window_size / 2
    global_rate_limiter$requests <- Filter(function(t) {
      difftime(current_time, t, units = "secs") < half_window
    }, global_rate_limiter$requests)
  }
  
  # Global limit aşıldı mı kontrol et
  if (length(global_rate_limiter$requests) >= global_rate_limiter$max_total_requests) {
    return(list(allowed = FALSE, message = "Sistem yoğunluğu nedeniyle geçici olarak hizmet verilemiyor. Lütfen birkaç saniye sonra tekrar deneyin."))
  }
  
  # Mevcut isteği ekle
  global_rate_limiter$requests <- c(global_rate_limiter$requests, list(current_time))
  
  return(list(allowed = TRUE, message = NULL))
}

# Kullanıcı bazlı hız limiti kontrolü
check_rate_limit <- function(user_id) {
  current_time <- Sys.time()
  user_key <- as.character(user_id)
  
  # Önbellek boyutu kontrolü - çok büyürse eski kullanıcıları temizle
  if (length(ls(envir = rate_limiter$requests)) > rate_limiter$max_users_cache) {
    rm(list = ls(envir = rate_limiter$requests), envir = rate_limiter$requests)
  }
  
  if (!exists(user_key, envir = rate_limiter$requests)) {
    rate_limiter$requests[[user_key]] <- list()
  }
  
  # Eski istekleri temizle
  rate_limiter$requests[[user_key]] <- Filter(function(t) {
    difftime(current_time, t, units = "secs") < rate_limiter$window_size
  }, rate_limiter$requests[[user_key]])
  
  # Limit aşıldı mı kontrol et
  if (length(rate_limiter$requests[[user_key]]) >= rate_limiter$max_requests_per_user) {
    return(FALSE)
  }
  
  # Mevcut isteği ekle
  rate_limiter$requests[[user_key]] <- c(
    rate_limiter$requests[[user_key]],
    list(current_time)
  )
  
  return(TRUE)
}

# --- PARALEL İŞÇİ HAVUZU YAPILANDIRMASI ---
# Sistem kapasitesine göre işçi sayısını belirle (en az 1, en fazla 10)
resolve_mergen_worker_count <- function() {
  configured <- suppressWarnings(as.integer(Sys.getenv("MERGEN_WORKERS", NA_character_)))
  auto_count <- max(1L, min(as.integer(parallelly::availableCores()) - 1L, 10L))

  if (is.na(configured) || configured < 1L) {
    return(auto_count)
  }

  min(configured, auto_count)
}

stop_future_cluster <- function() {
  if (!exists(".mergen_future_cluster", envir = .GlobalEnv, inherits = FALSE)) {
    return(invisible(NULL))
  }

  cluster <- get(".mergen_future_cluster", envir = .GlobalEnv, inherits = FALSE)
  try(parallel::stopCluster(cluster), silent = TRUE)
  rm(".mergen_future_cluster", envir = .GlobalEnv)

  future::plan(future::sequential)
  invisible(NULL)
}

init_future_cluster <- function(force = FALSE) {
  futures_disabled <- identical(
    tolower(Sys.getenv("MERGEN_DISABLE_FUTURES", "false")),
    "true"
  )

  if (isTRUE(futures_disabled)) {
    future::plan(future::sequential)
    return(invisible(NULL))
  }

  if (isTRUE(force)) {
    stop_future_cluster()
  }

  if (!exists(".mergen_future_cluster", envir = .GlobalEnv, inherits = FALSE)) {
    worker_count <- resolve_mergen_worker_count()

    cluster <- parallelly::makeClusterPSOCK(
      workers = worker_count,
      outfile = ""
    )

    assign(".mergen_future_cluster", cluster, envir = .GlobalEnv)
  }

  future::plan(
    future::cluster,
    workers = get(".mergen_future_cluster", envir = .GlobalEnv, inherits = FALSE),
    persistent = TRUE
  )

  invisible(get(".mergen_future_cluster", envir = .GlobalEnv, inherits = FALSE))
}

monitor_workers <- function() {
  get_worker_monitor_info()
}

# İşçileri (persistent PSOCK cluster) bir kez ÖN-ISITIR: ilk gerçek LLM/SSE
# isteği, ağır paketlerin (jsonlite/curl/httr/DBI) işçi tarafında ilk kez
# yüklenme maliyetini ödemesin diye her işçiye küçük bir görev gönderilir.
# İlk istem gönderiminde ölçülen "ilk token" gecikmesinin işçi soğuk başlangıcı
# bileşenini kaldırır. Kaynak yükleme sırasında güvenlidir:
#   - MERGEN_DISABLE_FUTURES=true iken no-op (test/bootstrap güvenliği),
#   - bir kez çalışır (start_gc_scheduler_once desenindeki tek-sefer bayrağı),
#   - dağıtımı bloklamaz; sonuç beklenmez ve hatalar sessizce yutulur.
prewarm_future_workers_once <- function() {
  if (isTRUE(getOption("mergen.workers_prewarmed", FALSE))) {
    return(invisible(FALSE))
  }

  if (isTRUE(as.logical(Sys.getenv("MERGEN_DISABLE_FUTURES", "false")))) {
    return(invisible(FALSE))
  }

  # tracked_future_promise foundation grubunda bu dosyadan SONRA yüklenir;
  # çağrı zamanı (global.R future kurulumundan sonra) mevcuttur. Yine de
  # izole test/kaynak bağlamları için savunmacı kontrol yapılır.
  if (!exists("tracked_future_promise", mode = "function", inherits = TRUE)) {
    return(invisible(FALSE))
  }

  options(mergen.workers_prewarmed = TRUE)

  worker_count <- tryCatch(resolve_mergen_worker_count(), error = function(e) 1L)
  prewarm_started <- Sys.time()

  for (i in seq_len(worker_count)) {
    tryCatch({
      prewarm_promise <- tracked_future_promise(
        task_fn = function() {
          # İşçi tarafında sık kullanılan paketleri belleğe al; dönüş değeri önemsiz.
          suppressWarnings({
            requireNamespace("jsonlite", quietly = TRUE)
            requireNamespace("curl", quietly = TRUE)
            requireNamespace("httr", quietly = TRUE)
            requireNamespace("DBI", quietly = TRUE)
          })
          TRUE
        },
        task_type = "worker_prewarm",
        session_token = NULL
      )
      # Reddedilen prewarm promise'i sessizce yutulur (uyarı gürültüsü olmasın).
      promises::catch(prewarm_promise, function(e) NULL)
    }, error = function(e) invisible(NULL))
  }

  cat(sprintf(
    "[STARTUP PERF] worker_prewarm dispatch=%d worker, %.0f ms\n",
    worker_count,
    as.numeric(difftime(Sys.time(), prewarm_started, units = "secs")) * 1000
  ))

  invisible(TRUE)
}
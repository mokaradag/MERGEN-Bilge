# ==============================================================================
# Dosya Yolu: tests/scripts/soak_metrics.R
# Aciklama:
#   Soak metrik biriktirme, yuzdelik (p50/p90/p95/p99), throughput, bellek ve
#   temp-dizin ornekleme yardimcilari. Saf, deterministik; dis servis gerektirmez.
#
#   Bu dosya BILEREK ASCII-guvenlidir (Turkce ozel karakter yok).
# ==============================================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || is.na(x[1])) y else x

# Metrik biriktiriciyi olusturur. Satirlar bir ortamda buyuyen vektorlerde
# tutulur (data.frame'e rbind etmekten cok daha hizli).
soak_metrics_new <- function() {
  env <- new.env(parent = emptyenv())
  env$n <- 0L
  env$cap <- 1024L
  env$ts <- numeric(env$cap)
  env$lane <- character(env$cap)
  env$scenario <- character(env$cap)
  env$latency_ms <- numeric(env$cap)
  env$status <- character(env$cap)        # ok | error | timeout
  env$http_code <- integer(env$cap)
  env$bytes <- numeric(env$cap)
  env$key_source <- character(env$cap)    # personal | default | missing | proxy-personal | n/a
  env$started_at <- Sys.time()
  env$load_seconds <- 0                    # yuk-penceresi suresi (throughput paydasi)
  env
}

# Yuk-penceresi suresi ekler (drain HARIC). Throughput paydasi olarak kullanilir;
# enjekte timeout istekleri (gec tamamlanan) throughput'u carpitmaz.
soak_metrics_add_load_seconds <- function(m, secs) {
  m$load_seconds <- (m$load_seconds %||% 0) + as.numeric(secs %||% 0)
  invisible(NULL)
}

.soak_metrics_grow <- function(m) {
  if (m$n < m$cap) return(invisible(NULL))
  new_cap <- m$cap * 2L
  m$ts <- c(m$ts, numeric(m$cap))
  m$lane <- c(m$lane, character(m$cap))
  m$scenario <- c(m$scenario, character(m$cap))
  m$latency_ms <- c(m$latency_ms, numeric(m$cap))
  m$status <- c(m$status, character(m$cap))
  m$http_code <- c(m$http_code, integer(m$cap))
  m$bytes <- c(m$bytes, numeric(m$cap))
  m$key_source <- c(m$key_source, character(m$cap))
  m$cap <- new_cap
  invisible(NULL)
}

# Tek bir operasyon kaydini ekler. Thread-safe degildir: yalniz ana surecten
# (curl multi done/fail callback'leri ana surecte calisir) cagrilmalidir.
soak_metrics_record <- function(m, lane, scenario, latency_ms, status,
                                http_code = NA_integer_, bytes = 0,
                                key_source = "n/a") {
  .soak_metrics_grow(m)
  i <- m$n + 1L
  m$ts[i] <- as.numeric(Sys.time())
  m$lane[i] <- as.character(lane %||% "")
  m$scenario[i] <- as.character(scenario %||% "")
  m$latency_ms[i] <- as.numeric(latency_ms %||% NA_real_)
  m$status[i] <- as.character(status %||% "")
  m$http_code[i] <- as.integer(http_code %||% NA_integer_)
  m$bytes[i] <- as.numeric(bytes %||% 0)
  m$key_source[i] <- as.character(key_source %||% "n/a")
  m$n <- i
  invisible(NULL)
}

# Kayitlari data.frame'e cevirir (metrics.csv icin).
soak_metrics_as_df <- function(m) {
  n <- m$n
  if (n == 0L) {
    return(data.frame(
      ts_epoch = numeric(0), lane = character(0), scenario = character(0),
      latency_ms = numeric(0), status = character(0), http_code = integer(0),
      bytes = numeric(0), key_source = character(0),
      stringsAsFactors = FALSE
    ))
  }
  idx <- seq_len(n)
  data.frame(
    ts_epoch = m$ts[idx],
    lane = m$lane[idx],
    scenario = m$scenario[idx],
    latency_ms = round(m$latency_ms[idx], 1),
    status = m$status[idx],
    http_code = m$http_code[idx],
    bytes = m$bytes[idx],
    key_source = m$key_source[idx],
    stringsAsFactors = FALSE
  )
}

# Sunucunun KASITLI enjekte ettigi fault sayisi (case_counts'tan).
# Client tarafinda status != ok ureten durumlar: http500, http429, timeout.
# (malformed/empty/interrupted HTTP 200 doner; client'ta "ok" sayilir.)
soak_injected_fault_count <- function(case_counts) {
  if (is.null(case_counts) || length(case_counts) == 0L) return(0L)
  fault_cases <- c("http500", "http429", "timeout")
  total <- 0L
  for (cc in fault_cases) {
    val <- case_counts[[cc]]
    if (!is.null(val) && length(val) >= 1L && is.finite(as.numeric(val[1]))) {
      total <- total + as.integer(val[1])
    }
  }
  as.integer(total)
}

# Kaydedilmis operasyon sayisi (kapasite egrisi dilim siniri icin).
soak_metrics_count <- function(m) m$n

# Belirli bir kayit araligi (from..to) icin ozet (kapasite egrisi adimlari).
# wall_seconds verilirse throughput paydasi olarak kullanilir (yuk-penceresi
# suresi); aksi halde tamamlanma zaman damgasi araligi kullanilir.
soak_metrics_slice_summary <- function(m, from_idx, to_idx = m$n, wall_seconds = NULL) {
  if (m$n == 0L || from_idx > to_idx) {
    return(list(requests = 0L, success_rate = NA_real_, p95_latency_ms = NA_real_,
                throughput_ops_per_min = 0))
  }
  idx <- seq.int(from_idx, to_idx)
  status <- m$status[idx]
  latency <- m$latency_ms[idx]
  ok_latency <- latency[status == "ok"]
  n <- length(idx)
  ts <- m$ts[idx]
  wall <- if (!is.null(wall_seconds) && is.finite(wall_seconds) && wall_seconds > 0) {
    wall_seconds
  } else {
    max(1e-6, max(ts) - min(ts))
  }
  list(
    requests = as.integer(n),
    success_rate = round(sum(status == "ok") / n, 4),
    p95_latency_ms = round(soak_percentile(ok_latency, 0.95), 1),
    throughput_ops_per_min = round(n / wall * 60, 1)
  )
}

# NA-guvenli type-7 yuzdelik.
soak_percentile <- function(x, p) {
  x <- x[is.finite(x)]
  if (length(x) == 0L) return(NA_real_)
  as.numeric(stats::quantile(x, probs = p, names = FALSE, type = 7, na.rm = TRUE))
}

# Toplu metrik ozeti.
soak_metrics_summary <- function(m) {
  n <- m$n
  if (n == 0L) {
    return(list(
      requests = 0L, success = 0L, errors = 0L, timeouts = 0L,
      success_rate = NA_real_,
      p50_latency_ms = NA_real_, p90_latency_ms = NA_real_,
      p95_latency_ms = NA_real_, p99_latency_ms = NA_real_,
      max_latency_ms = NA_real_, mean_latency_ms = NA_real_,
      throughput_ops_per_min = 0,
      http_code_counts = list(), status_counts = list(),
      key_sources = list(), scenario_counts = list(),
      wall_seconds = 0
    ))
  }

  idx <- seq_len(n)
  status <- m$status[idx]
  latency <- m$latency_ms[idx]
  ok_latency <- latency[status == "ok"]

  success <- sum(status == "ok")
  errors <- sum(status == "error")
  timeouts <- sum(status == "timeout")

  wall_seconds <- max(1e-6, max(m$ts[idx]) - as.numeric(m$started_at))
  # Throughput paydasi: yuk-penceresi suresi (drain/timeout kuyrugu haric).
  # Boylece gec tamamlanan enjekte-timeout istekleri throughput'u carpitmaz.
  throughput_wall <- if (!is.null(m$load_seconds) && m$load_seconds > 0) m$load_seconds else wall_seconds

  http_codes <- m$http_code[idx]
  http_tab <- table(http_codes[!is.na(http_codes)])
  status_tab <- table(status)
  key_tab <- table(m$key_source[idx])
  scen_tab <- table(m$scenario[idx])

  to_named_list <- function(tab) {
    if (length(tab) == 0L) return(list())
    as.list(stats::setNames(as.integer(tab), names(tab)))
  }

  list(
    requests = as.integer(n),
    success = as.integer(success),
    errors = as.integer(errors),
    timeouts = as.integer(timeouts),
    success_rate = round(success / n, 4),
    p50_latency_ms = round(soak_percentile(ok_latency, 0.50), 1),
    p90_latency_ms = round(soak_percentile(ok_latency, 0.90), 1),
    p95_latency_ms = round(soak_percentile(ok_latency, 0.95), 1),
    p99_latency_ms = round(soak_percentile(ok_latency, 0.99), 1),
    max_latency_ms = round(suppressWarnings(max(ok_latency, na.rm = TRUE)), 1),
    mean_latency_ms = round(suppressWarnings(mean(ok_latency, na.rm = TRUE)), 1),
    throughput_ops_per_min = round(n / throughput_wall * 60, 1),
    http_code_counts = to_named_list(http_tab),
    status_counts = to_named_list(status_tab),
    key_sources = to_named_list(key_tab),
    scenario_counts = to_named_list(scen_tab),
    wall_seconds = round(wall_seconds, 1)
  )
}

# ------------------------------------------------------------------------------
# Bellek ornekleme: en iyi caba. R duzeyi her zaman olculur; surec RSS
# Linux'ta /proc, Unix'te ps ile; Windows'ta cogunlukla olculemez (NA).
# ------------------------------------------------------------------------------

soak_sample_memory <- function(pid = Sys.getpid()) {
  r_used_mb <- tryCatch({
    g <- gc(verbose = FALSE)
    # gc() matrisinde "used (Mb)" sutunlarinin toplami.
    mb_cols <- grep("Mb", colnames(g))
    if (length(mb_cols) >= 1L) {
      sum(g[, mb_cols[1]], na.rm = TRUE)
    } else {
      NA_real_
    }
  }, error = function(e) NA_real_)

  rss_mb <- NA_real_
  os <- .Platform$OS.type
  if (identical(os, "unix")) {
    # Once Linux /proc, sonra ps.
    proc_path <- sprintf("/proc/%d/status", pid)
    if (file.exists(proc_path)) {
      rss_mb <- tryCatch({
        lines <- readLines(proc_path, warn = FALSE)
        vm <- grep("^VmRSS:", lines, value = TRUE)
        if (length(vm) >= 1L) {
          kb <- as.numeric(gsub("[^0-9]", "", vm[1]))
          if (is.finite(kb)) kb / 1024 else NA_real_
        } else {
          NA_real_
        }
      }, error = function(e) NA_real_)
    }
    if (is.na(rss_mb)) {
      rss_mb <- tryCatch({
        out <- suppressWarnings(system(sprintf("ps -o rss= -p %d", pid),
                                       intern = TRUE, ignore.stderr = TRUE))
        kb <- as.numeric(trimws(paste(out, collapse = "")))
        if (is.finite(kb)) kb / 1024 else NA_real_
      }, error = function(e) NA_real_)
    }
  }

  list(
    r_used_mb = if (is.finite(r_used_mb)) round(r_used_mb, 1) else NA_real_,
    process_rss_mb = if (is.finite(rss_mb)) round(rss_mb, 1) else NA_real_,
    measured_rss = is.finite(rss_mb)
  )
}

# Temp dizin(ler) icindeki dosya sayisi + toplam byte. En iyi caba.
soak_sample_tempdirs <- function(dirs) {
  dirs <- unique(dirs[nzchar(dirs)])
  total_files <- 0L
  total_bytes <- 0
  for (d in dirs) {
    if (!dir.exists(d)) next
    files <- tryCatch(
      list.files(d, recursive = TRUE, full.names = TRUE, all.files = TRUE, no.. = TRUE),
      error = function(e) character(0)
    )
    files <- files[!dir.exists(files)]
    if (length(files) == 0L) next
    sizes <- tryCatch(file.info(files)$size, error = function(e) rep(NA_real_, length(files)))
    total_files <- total_files + length(files)
    total_bytes <- total_bytes + sum(sizes, na.rm = TRUE)
  }
  list(
    file_count = as.integer(total_files),
    bytes = as.numeric(total_bytes),
    mb = round(total_bytes / (1024 * 1024), 2)
  )
}

# Iki bellek ornegi arasindaki buyume ozeti.
soak_memory_growth <- function(before, after) {
  growth <- function(a, b) {
    if (is.null(a) || is.null(b) || is.na(a) || is.na(b)) return(NA_real_)
    round(b - a, 1)
  }
  list(
    before = before,
    after = after,
    r_used_growth_mb = growth(before$r_used_mb, after$r_used_mb),
    process_rss_growth_mb = growth(before$process_rss_mb, after$process_rss_mb),
    rss_measured = isTRUE(before$measured_rss) && isTRUE(after$measured_rss)
  )
}

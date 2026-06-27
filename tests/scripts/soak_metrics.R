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
  env$timeout_class <- character(env$cap)  # hata atfi (timeout attribution) sinifi
  env$endpoint_kind <- character(env$cap)  # app | fake_llm | proxy_llm | real_llm | interactive | n/a
  env$connect_ms <- numeric(env$cap)       # curl connect fazi (ms); olculemezse NA
  env$ttfb_ms <- numeric(env$cap)          # curl ilk-byte/starttransfer (ms); olculemezse NA
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
  m$timeout_class <- c(m$timeout_class, character(m$cap))
  m$endpoint_kind <- c(m$endpoint_kind, character(m$cap))
  m$connect_ms <- c(m$connect_ms, numeric(m$cap))
  m$ttfb_ms <- c(m$ttfb_ms, numeric(m$cap))
  m$cap <- new_cap
  invisible(NULL)
}

# Tek bir operasyon kaydini ekler. Thread-safe degildir: yalniz ana surecten
# (curl multi done/fail callback'leri ana surecte calisir) cagrilmalidir.
soak_metrics_record <- function(m, lane, scenario, latency_ms, status,
                                http_code = NA_integer_, bytes = 0,
                                key_source = "n/a", timeout_class = "n/a",
                                endpoint_kind = "n/a",
                                connect_ms = NA_real_, ttfb_ms = NA_real_) {
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
  m$timeout_class[i] <- as.character(timeout_class %||% "n/a")
  m$endpoint_kind[i] <- as.character(endpoint_kind %||% "n/a")
  # curl zamanlama telemetrisi (yalniz tamamlanan istekler icin gelir; baglanti
  # timeout'unda fail callback zamanlama saglamaz -> NA). connect vs ttfb ayrimi
  # baglanti-fazi doygunlugunu (kabul/backlog) app-isleme gecikmesinden ayirir.
  m$connect_ms[i] <- suppressWarnings(as.numeric(connect_ms %||% NA_real_))
  m$ttfb_ms[i] <- suppressWarnings(as.numeric(ttfb_ms %||% NA_real_))
  m$n <- i
  invisible(NULL)
}

# ------------------------------------------------------------------------------
# Hata atfi (timeout attribution): saf siniflandirma. Geriye kararli bir sinif
# etiketi doner; ham hata mesaji ASLA saklanmaz (yalniz desen kontrolu).
#   status        : "ok" | "error" | "timeout"
#   http_code     : HTTP kodu (varsa) ya da NA
#   curl_msg      : transport hata mesaji (yalniz desen kontrolu icin)
#   endpoint_kind : app | fake_llm | proxy_llm | real_llm | interactive | n/a
# ------------------------------------------------------------------------------
soak_classify_failure <- function(status, http_code = NA_integer_, curl_msg = "",
                                  endpoint_kind = "app") {
  status <- as.character(status %||% "")
  ek <- as.character(endpoint_kind %||% "app")
  if (identical(status, "ok")) return("n/a")

  msg <- tolower(as.character(curl_msg %||% ""))
  is_connect_phase <- grepl("connect", msg) || grepl("could ?n.t connect", msg) ||
    grepl("couldn't connect", msg) || grepl("connection refused", msg)

  if (identical(status, "timeout")) {
    if (isTRUE(is_connect_phase)) return("connection_timeout")
    return(switch(ek,
                  fake_llm = "fake_llm_timeout",
                  proxy_llm = "proxy_llm_timeout",
                  real_llm = "real_llm_timeout",
                  app = "response_timeout",
                  "client_timeout"))
  }

  # status == "error"
  code <- suppressWarnings(as.integer(http_code))
  if (!is.na(code) && is.finite(code)) {
    if (identical(as.integer(code), 429L)) return("rate_limited")
    if (code >= 400L) {
      return(switch(ek,
                    fake_llm = "fake_llm_http_error",
                    proxy_llm = "proxy_llm_http_error",
                    real_llm = "real_llm_gateway_error",
                    "app_http_error"))
    }
    return("http_error")
  }

  # Kod yok (transport hatasi).
  if (isTRUE(is_connect_phase)) return("connection_error")
  if (grepl("tim(e|ed) ?out|timeout", msg)) return("unknown_timeout")
  "unknown_error"
}

# Bir hata sinifinin yeniden-denenebilir (retryable) olup olmadigi (kaba kural).
soak_failure_retryable <- function(timeout_class, http_code = NA_integer_) {
  tc <- as.character(timeout_class %||% "")
  if (grepl("timeout", tc, fixed = TRUE)) return(TRUE)
  if (identical(tc, "rate_limited")) return(TRUE)
  if (identical(tc, "connection_error")) return(TRUE)
  code <- suppressWarnings(as.integer(http_code))
  if (!is.na(code) && is.finite(code) && code >= 500L) return(TRUE)
  FALSE
}

# Kayitlari data.frame'e cevirir (metrics.csv icin).
soak_metrics_as_df <- function(m) {
  n <- m$n
  if (n == 0L) {
    return(data.frame(
      ts_epoch = numeric(0), lane = character(0), scenario = character(0),
      latency_ms = numeric(0), status = character(0), http_code = integer(0),
      bytes = numeric(0), key_source = character(0),
      timeout_class = character(0), endpoint_kind = character(0),
      connect_ms = numeric(0), ttfb_ms = numeric(0),
      stringsAsFactors = FALSE
    ))
  }
  idx <- seq_len(n)
  tc <- if (length(m$timeout_class) >= n) m$timeout_class[idx] else rep("n/a", n)
  ek <- if (length(m$endpoint_kind) >= n) m$endpoint_kind[idx] else rep("n/a", n)
  cm <- if (length(m$connect_ms) >= n) m$connect_ms[idx] else rep(NA_real_, n)
  tf <- if (length(m$ttfb_ms) >= n) m$ttfb_ms[idx] else rep(NA_real_, n)
  data.frame(
    ts_epoch = m$ts[idx],
    lane = m$lane[idx],
    scenario = m$scenario[idx],
    latency_ms = round(m$latency_ms[idx], 1),
    status = m$status[idx],
    http_code = m$http_code[idx],
    bytes = m$bytes[idx],
    key_source = m$key_source[idx],
    timeout_class = tc,
    endpoint_kind = ek,
    connect_ms = round(cm, 1),
    ttfb_ms = round(tf, 1),
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
soak_metrics_slice_summary <- function(m, from_idx, to_idx = m$n, wall_seconds = NULL,
                                       injected_faults = 0L) {
  if (m$n == 0L || from_idx > to_idx) {
    return(list(requests = 0L, success = 0L, errors = 0L, timeouts = 0L,
                injected_faults = 0L,
                success_rate = NA_real_, effective_success_rate = NA_real_,
                p50_latency_ms = NA_real_, p95_latency_ms = NA_real_,
                p99_latency_ms = NA_real_, throughput_ops_per_min = 0,
                connect_ms_p50 = NA_real_, connect_ms_p95 = NA_real_,
                ttfb_ms_p50 = NA_real_, ttfb_ms_p95 = NA_real_,
                dominant_timeout_class = NA_character_))
  }
  idx <- seq.int(from_idx, to_idx)
  status <- m$status[idx]
  latency <- m$latency_ms[idx]
  ok_latency <- latency[status == "ok"]
  connect_ok <- if (length(m$connect_ms) >= to_idx) m$connect_ms[idx][status == "ok"] else numeric(0)
  ttfb_ok <- if (length(m$ttfb_ms) >= to_idx) m$ttfb_ms[idx][status == "ok"] else numeric(0)
  n <- length(idx)
  success <- sum(status == "ok")
  errors <- sum(status == "error")
  timeouts <- sum(status == "timeout")
  ts <- m$ts[idx]
  wall <- if (!is.null(wall_seconds) && is.finite(wall_seconds) && wall_seconds > 0) {
    wall_seconds
  } else {
    max(1e-6, max(ts) - min(ts))
  }
  # Etkin oran (effective_success_rate): fake/proxy mock'unun KASITLI enjekte
  # ettigi faultlar (http500/http429/timeout) yuk fazinda SUREKLI kosar; bu
  # yuzden dilim icin effective == raw VARSAYIMI YANLISTI. Kasitli enjekte
  # faultlari dilim basari oranindan dus; yalnizca BEKLENMEYEN (gercek) faultlar
  # adim basarisini etkilemeli. Aksi halde varsayilan ~%3 sahte LLM faulti,
  # saglikli bir merdiveni stable_success_rate_min (varsayilan 0.98) altinda ilk
  # adimda FAIL ettirir. injected_faults bu dilimin sunucu case_counts
  # deltasindan gelir (yoksa 0 -> effective == raw, daha katidir). Bu mantik
  # genel soak_evidence etkin-oran hesabiyla AYNIDIR (gozlenen - enjekte).
  rate <- round(success / n, 4)
  observed_faults <- errors + timeouts
  inj <- max(0L, as.integer(injected_faults %||% 0L))
  unexpected_faults <- max(0L, observed_faults - inj)
  effective <- round((n - unexpected_faults) / n, 4)
  # Bu dilimdeki baskin hata sinifi (darbogaz tani ipucu icin). status != ok olan
  # kayitlarin timeout_class dagiliminda en yaygin sinif. Yoksa NA.
  dom_tc <- NA_character_
  bad_idx <- idx[status != "ok"]
  if (length(bad_idx) > 0L && length(m$timeout_class) >= max(bad_idx)) {
    tcv <- m$timeout_class[bad_idx]
    tcv[is.na(tcv) | tcv == "" | tcv == "n/a"] <- "unknown_error"
    tab <- sort(table(tcv), decreasing = TRUE)
    if (length(tab) > 0L) dom_tc <- names(tab)[1]
  }
  list(
    requests = as.integer(n),
    success = as.integer(success),
    errors = as.integer(errors),
    timeouts = as.integer(timeouts),
    injected_faults = inj,
    success_rate = rate,
    effective_success_rate = effective,
    p50_latency_ms = round(soak_percentile(ok_latency, 0.50), 1),
    p95_latency_ms = round(soak_percentile(ok_latency, 0.95), 1),
    p99_latency_ms = round(soak_percentile(ok_latency, 0.99), 1),
    throughput_ops_per_min = round(n / wall * 60, 1),
    connect_ms_p50 = round(soak_percentile(connect_ok, 0.50), 1),
    connect_ms_p95 = round(soak_percentile(connect_ok, 0.95), 1),
    ttfb_ms_p50 = round(soak_percentile(ttfb_ok, 0.50), 1),
    ttfb_ms_p95 = round(soak_percentile(ttfb_ok, 0.95), 1),
    dominant_timeout_class = dom_tc
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
  connect_ok <- if (length(m$connect_ms) >= n) m$connect_ms[idx][status == "ok"] else numeric(0)
  ttfb_ok <- if (length(m$ttfb_ms) >= n) m$ttfb_ms[idx][status == "ok"] else numeric(0)

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
    # curl zamanlama yuzdelikleri (yalniz basarili istekler; baglanti-fazi vs
    # app-isleme ayrimi). connect yuksek + ttfb dusuk -> baglanti/backlog
    # darbogazi; ttfb yuksek -> app/event-loop isleme darbogazi.
    connect_ms_p50 = round(soak_percentile(connect_ok, 0.50), 1),
    connect_ms_p95 = round(soak_percentile(connect_ok, 0.95), 1),
    ttfb_ms_p50 = round(soak_percentile(ttfb_ok, 0.50), 1),
    ttfb_ms_p95 = round(soak_percentile(ttfb_ok, 0.95), 1),
    http_code_counts = to_named_list(http_tab),
    status_counts = to_named_list(status_tab),
    key_sources = to_named_list(key_tab),
    scenario_counts = to_named_list(scen_tab),
    wall_seconds = round(wall_seconds, 1)
  )
}

# ------------------------------------------------------------------------------
# Hata atfi toplu ozeti (timeout attribution). soak_metrics_as_df() ciktisindan
# timeout_class dagilimini, en yaygin hata siniflarini ve en yavas senaryolari
# uretir. Ham hata mesaji ICERMEZ (yalniz sinif etiketleri + sayilar).
# ------------------------------------------------------------------------------
soak_timeout_attribution <- function(df, top_n = 5L) {
  empty <- list(
    total_failures = 0L,
    timeout_breakdown = list(),
    top_failure_classes = list(),
    top_slow_scenarios = list(),
    dominant_timeout_class = NA_character_
  )
  if (is.null(df) || nrow(df) == 0L) return(empty)
  if (!("status" %in% names(df))) return(empty)

  bad <- df[df$status != "ok", , drop = FALSE]
  tc_col <- if ("timeout_class" %in% names(bad)) bad$timeout_class else rep("unknown_error", nrow(bad))
  tc_col[is.na(tc_col) | tc_col == "" | tc_col == "n/a"] <- "unknown_error"

  breakdown <- list()
  top_classes <- list()
  dominant_tc <- NA_character_
  if (nrow(bad) > 0L) {
    tab <- sort(table(tc_col), decreasing = TRUE)
    breakdown <- as.list(stats::setNames(as.integer(tab), names(tab)))
    dominant_tc <- names(tab)[1]
    top <- head(tab, top_n)
    top_classes <- lapply(seq_along(top), function(i) {
      list(class = names(top)[i], count = as.integer(top[i]))
    })
  }

  # En yavas senaryolar: ok isteklerin p95 gecikmesine gore (darbogaz ipucu).
  slow <- list()
  ok <- df[df$status == "ok" & is.finite(df$latency_ms), , drop = FALSE]
  if (nrow(ok) > 0L && "scenario" %in% names(ok)) {
    scs <- unique(ok$scenario)
    rows <- lapply(scs, function(s) {
      lat <- ok$latency_ms[ok$scenario == s]
      list(scenario = s, count = length(lat),
           p95_latency_ms = round(soak_percentile(lat, 0.95), 1))
    })
    p95s <- vapply(rows, function(r) r$p95_latency_ms %||% NA_real_, numeric(1))
    ord <- order(p95s, decreasing = TRUE)
    slow <- rows[head(ord, top_n)]
  }

  list(
    total_failures = as.integer(nrow(bad)),
    timeout_breakdown = breakdown,
    top_failure_classes = top_classes,
    top_slow_scenarios = slow,
    dominant_timeout_class = dominant_tc
  )
}

# ------------------------------------------------------------------------------
# Yuk-uretici (load generator) doygunluk ipucu (SAF, deterministik). Yuk
# surucusunun istenen aktif-eszamanliligi gercekten surdurup surdurmedigini
# kaba bir sekilde siniflandirir. Bu bir esik DEGILDIR; yalnizca darbogazin
# istemci/loop tarafinda mi yoksa sunucu tarafinda mi olabilecegine dair tani
# ipucudur.
#   loadgen      : soak_http_load() donus listesi (max_inflight, max_loop_lag_ms)
#   target_users : adimin hedef aktif-eszamanli kullanici sayisi
# ------------------------------------------------------------------------------
soak_loadgen_saturation_hint <- function(loadgen, target_users) {
  if (is.null(loadgen) || !is.list(loadgen)) return("loadgen_unmeasured")
  target <- suppressWarnings(as.numeric(target_users))
  max_inflight <- suppressWarnings(as.numeric(loadgen$max_inflight %||% NA_real_))
  loop_lag <- suppressWarnings(as.numeric(loadgen$max_loop_lag_ms %||% NA_real_))
  if (!is.finite(target) || target <= 0 || !is.finite(max_inflight)) {
    return("loadgen_unmeasured")
  }
  # Hedef eszamanliligin belirgin altinda kaldiysa istemci/loop ureticisi
  # darbogaz olabilir (sunucu degil).
  if (max_inflight < 0.8 * target) return("loadgen_below_target_concurrency")
  if (is.finite(loop_lag) && loop_lag >= 1000) return("loadgen_loop_lag_high")
  "loadgen_sustained_target"
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

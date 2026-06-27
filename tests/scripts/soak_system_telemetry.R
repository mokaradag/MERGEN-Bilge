# ==============================================================================
# Dosya Yolu: tests/scripts/soak_system_telemetry.R
# Aciklama:
#   Operasyonel soak kosumlari sirasinda OPSIYONEL sistem telemetrisi ornekleme.
#   Amac: darbogazi (CPU saturasyonu / SQL Server / yuk-ureticisi / TCP) gercek
#   olcumle ayirt etmek. Hicbir SIR (DSN/anahtar/token/parola/UNC yolu) yazilmaz;
#   yalnizca sayisal metrikler ve sabit etiketler uretilir.
#
#   Calisma modeli: telemetri AYRI bir callr arka-surec icinde calisir (yuk
#   seridini bloklamaz, OS sayaclari okunamasa bile soak'u KIRMAZ). Arka surec
#   system_telemetry.csv dosyasina satir satir yazar. Ana surec sonunda CSV'yi
#   okuyup ozet uretir.
#
#   Windows: PowerShell (Get-CimInstance / Get-Process / netstat).
#   Unix/cloud: /proc + ps + ss/netstat. Olculemezse zarifce NA + uyari (FAIL degil).
#
#   Bu dosya BILEREK ASCII-guvenlidir (Turkce ozel karakter yok); operasyonel
#   giris noktasi olarak farkli locale'lerde source/Rscript edilir.
# ==============================================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || is.na(x[1])) y else x

soak_tel_env_flag <- function(name, default = FALSE) {
  raw <- tolower(trimws(Sys.getenv(name, unset = "")))
  if (!nzchar(raw)) return(isTRUE(default))
  if (raw %in% c("true", "t", "1", "yes", "y", "on", "evet")) return(TRUE)
  if (raw %in% c("false", "f", "0", "no", "n", "off", "hayir")) return(FALSE)
  isTRUE(default)
}

soak_tel_env_int <- function(name, default) {
  raw <- trimws(Sys.getenv(name, unset = ""))
  if (!nzchar(raw)) return(as.integer(default))
  val <- suppressWarnings(as.integer(raw))
  if (is.na(val)) as.integer(default) else val
}

# app URL'sinden port cikarir (varsayilan 8009 = uretim launcher portu).
soak_telemetry_port_from_url <- function(url = Sys.getenv("MERGEN_SOAK_APP_URL", unset = ""),
                                         default_port = 8009L) {
  url <- trimws(as.character(url %||% ""))
  if (!nzchar(url)) return(as.integer(default_port))
  m <- regmatches(url, regexpr(":[0-9]{2,5}", url))
  if (length(m) >= 1L && nzchar(m[1])) {
    p <- suppressWarnings(as.integer(sub(":", "", m[1], fixed = TRUE)))
    if (!is.na(p) && p > 0L) return(p)
  }
  as.integer(default_port)
}

soak_telemetry_config <- function() {
  list(
    enabled = soak_tel_env_flag("MERGEN_SOAK_TELEMETRY_ENABLED", TRUE),
    interval_sec = max(1L, soak_tel_env_int("MERGEN_SOAK_TELEMETRY_INTERVAL_SECONDS", 5L)),
    app_port = soak_telemetry_port_from_url()
  )
}

soak_telemetry_os <- function() {
  if (identical(.Platform$OS.type, "windows")) "windows" else "unix"
}

soak_telemetry_ncores <- function() {
  n <- tryCatch(parallel::detectCores(logical = TRUE), error = function(e) NA_integer_)
  if (is.na(n) || n < 1L) 1L else as.integer(n)
}

# ------------------------------------------------------------------------------
# Dusuk seviye: PowerShell calistir (yalniz Windows). Hata/eksiklikte "" doner.
# ------------------------------------------------------------------------------
.soak_tel_run_ps <- function(script) {
  out <- tryCatch(
    suppressWarnings(system2(
      "powershell",
      args = c("-NoProfile", "-NonInteractive", "-Command", script),
      stdout = TRUE, stderr = FALSE
    )),
    error = function(e) character(0)
  )
  if (length(out) == 0L) return("")
  trimws(paste(out, collapse = "\n"))
}

.soak_tel_num <- function(x) {
  v <- suppressWarnings(as.numeric(trimws(as.character(x %||% ""))))
  if (length(v) == 0L || is.na(v[1])) NA_real_ else v[1]
}

# Ham TCP durum etiketini normalize eder (Windows/ss/netstat farkli yazar):
# "Established"/"ESTAB"/"ESTABLISHED" -> "established", "SynSent"/"SYN-SENT" ->
# "syn_sent", "SynReceived"/"SYN-RECV" -> "syn_recv" vb. Taninmayan -> "other".
.soak_tel_normalize_tcp_state <- function(raw) {
  s <- gsub("[^a-z]", "", tolower(as.character(raw %||% "")))
  if (!nzchar(s)) return("other")
  # "estab" (ss kisa formu) ve "established" (Windows/netstat) ayni kova.
  if (startsWith(s, "estab")) return("established")
  if (identical(s, "synsent")) return("syn_sent")
  if (startsWith(s, "synrec")) return("syn_recv")
  if (identical(s, "timewait")) return("time_wait")
  if (identical(s, "closewait")) return("close_wait")
  if (startsWith(s, "listen")) return("listen")
  "other"
}

# Bir ham TCP-durum vektorunu normalize edilmis sayimlara dokumuller (SAF;
# OS gerektirmez, testlerde dogrudan dogrulanabilir). tcp_connections_to_app
# tum durumlarin toplamidir (other dahil). Bu, app-port backlog/established/
# time-wait dagilimini app darbogazindan ayirmak icin kullanilir.
soak_tcp_state_tally <- function(states) {
  out <- list(tcp_established = 0L, tcp_syn_sent = 0L, tcp_syn_recv = 0L,
              tcp_time_wait = 0L, tcp_close_wait = 0L, tcp_listen = 0L,
              tcp_connections_to_app = 0L)
  if (length(states) == 0L) return(out)
  total <- 0L
  for (raw in states) {
    raw <- trimws(as.character(raw %||% ""))
    if (!nzchar(raw)) next
    total <- total + 1L
    key <- paste0("tcp_", .soak_tel_normalize_tcp_state(raw))
    if (key %in% names(out)) out[[key]] <- out[[key]] + 1L
  }
  out$tcp_connections_to_app <- total
  out
}

# CSV/ozet icin TCP durum sutunlarinin sabit adlari.
soak_tcp_state_columns <- function() {
  c("tcp_connections_to_app", "tcp_established", "tcp_syn_sent", "tcp_syn_recv",
    "tcp_time_wait", "tcp_close_wait", "tcp_listen")
}

# ------------------------------------------------------------------------------
# Bos/baslangic ornegi sablonu (tum sutunlar mevcut, NA dolu).
# ------------------------------------------------------------------------------
.soak_tel_blank_row <- function() {
  list(
    ts_epoch = as.numeric(Sys.time()),
    ts_iso = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    elapsed_sec = NA_real_,
    total_cpu_percent = NA_real_,
    mem_total_mb = NA_real_,
    mem_used_mb = NA_real_,
    mem_free_mb = NA_real_,
    r_proc_count = NA_integer_,
    r_proc_cpu_percent = NA_real_,
    r_proc_mem_mb = NA_real_,
    sqlserver_proc_count = NA_integer_,
    sqlserver_cpu_percent = NA_real_,
    sqlserver_mem_mb = NA_real_,
    loadgen_mem_mb = NA_real_,
    tcp_connections_to_app = NA_integer_,
    tcp_established = NA_integer_,
    tcp_syn_sent = NA_integer_,
    tcp_syn_recv = NA_integer_,
    tcp_time_wait = NA_integer_,
    tcp_close_wait = NA_integer_,
    tcp_listen = NA_integer_,
    sample_ms = NA_real_
  )
}

soak_telemetry_columns <- function() names(.soak_tel_blank_row())

# ------------------------------------------------------------------------------
# Windows ornekleme. prev: onceki CPU saniye toplamlari (process CPU% delta icin).
# ------------------------------------------------------------------------------
.soak_tel_sample_windows <- function(prev, port, ncores, loadgen_pid) {
  row <- .soak_tel_blank_row()

  # Sistem CPU% (Win32_Processor.LoadPercentage ortalamasi).
  cpu_txt <- .soak_tel_run_ps(
    "(Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average"
  )
  row$total_cpu_percent <- .soak_tel_num(cpu_txt)

  # Bellek (Win32_OperatingSystem; KB cinsinden).
  mem_txt <- .soak_tel_run_ps(paste0(
    "$os=Get-CimInstance Win32_OperatingSystem; ",
    "'{0} {1}' -f $os.TotalVisibleMemorySize,$os.FreePhysicalMemory"
  ))
  mem_parts <- strsplit(mem_txt, "\\s+")[[1]]
  if (length(mem_parts) >= 2L) {
    total_kb <- .soak_tel_num(mem_parts[1]); free_kb <- .soak_tel_num(mem_parts[2])
    if (is.finite(total_kb)) row$mem_total_mb <- round(total_kb / 1024, 1)
    if (is.finite(free_kb)) row$mem_free_mb <- round(free_kb / 1024, 1)
    if (is.finite(total_kb) && is.finite(free_kb)) {
      row$mem_used_mb <- round((total_kb - free_kb) / 1024, 1)
    }
  }

  # Surec gruplari: R/Rscript ve sqlservr. Toplam WorkingSet (MB) + toplam CPU saniye.
  # Cikti formati: "<count> <mem_bytes> <cpu_seconds>" (eksikse 0).
  grp_ps <- function(names_csv) {
    paste0(
      "$p=Get-Process -Name ", names_csv, " -ErrorAction SilentlyContinue; ",
      "if($p){ $c=($p|Measure-Object).Count; ",
      "$m=($p|Measure-Object WorkingSet64 -Sum).Sum; ",
      "$cpu=($p|Measure-Object CPU -Sum).Sum; ",
      "'{0} {1} {2}' -f $c,$m,$cpu } else { '0 0 0' }"
    )
  }

  parse_grp <- function(txt, prev_cpu_key) {
    parts <- strsplit(trimws(txt), "\\s+")[[1]]
    cnt <- if (length(parts) >= 1L) as.integer(.soak_tel_num(parts[1])) else NA_integer_
    membytes <- if (length(parts) >= 2L) .soak_tel_num(parts[2]) else NA_real_
    cpusec <- if (length(parts) >= 3L) .soak_tel_num(parts[3]) else NA_real_
    mem_mb <- if (is.finite(membytes)) round(membytes / (1024 * 1024), 1) else NA_real_
    cpu_pct <- .soak_tel_cpu_delta_pct(prev, prev_cpu_key, cpusec, ncores)
    list(count = cnt, mem_mb = mem_mb, cpu_pct = cpu_pct, cpu_sec = cpusec)
  }

  rgrp <- parse_grp(.soak_tel_run_ps(grp_ps("Rscript,R,rsession")), "r")
  row$r_proc_count <- rgrp$count
  row$r_proc_mem_mb <- rgrp$mem_mb
  row$r_proc_cpu_percent <- rgrp$cpu_pct

  sgrp <- parse_grp(.soak_tel_run_ps(grp_ps("sqlservr")), "sql")
  row$sqlserver_proc_count <- sgrp$count
  row$sqlserver_mem_mb <- sgrp$mem_mb
  row$sqlserver_cpu_percent <- sgrp$cpu_pct

  # Yuk-uretici (gate ana sureci) bellegi.
  if (!is.null(loadgen_pid) && is.finite(loadgen_pid)) {
    lg_txt <- .soak_tel_run_ps(sprintf(
      "$p=Get-Process -Id %d -ErrorAction SilentlyContinue; if($p){$p.WorkingSet64}else{''}",
      as.integer(loadgen_pid)
    ))
    lg_bytes <- .soak_tel_num(lg_txt)
    if (is.finite(lg_bytes)) row$loadgen_mem_mb <- round(lg_bytes / (1024 * 1024), 1)
  }

  # Uygulama portuna TCP baglanti durum dagilimi (State bazli). Get-NetTCPConnection
  # -LocalPort yerel-port (sunucu tarafi) baglantilarini verir: Listen, Established,
  # TimeWait, CloseWait ve kabul-kuyrugu gostergesi SynReceived. Toplam, eski
  # Measure-Object sayimiyla AYNI -LocalPort filtresinden gelir (gecmis kiyas korunur).
  states_txt <- .soak_tel_run_ps(sprintf(
    "Get-NetTCPConnection -LocalPort %d -ErrorAction SilentlyContinue | ForEach-Object { $_.State }",
    as.integer(port)
  ))
  states <- if (nzchar(states_txt)) {
    trimws(strsplit(states_txt, "[\r\n]+")[[1]])
  } else {
    character(0)
  }
  states <- states[nzchar(states)]
  if (length(states) > 0L) {
    tally <- soak_tcp_state_tally(states)
    for (k in soak_tcp_state_columns()) row[[k]] <- as.integer(tally[[k]])
  } else {
    # netstat geri donus (Get-NetTCPConnection yoksa): yalniz toplam, durum yok.
    ns <- .soak_tel_run_ps(sprintf(
      "(netstat -ano | Select-String ':%d ' | Measure-Object).Count", as.integer(port)
    ))
    tcp_n <- .soak_tel_num(ns)
    if (is.finite(tcp_n)) row$tcp_connections_to_app <- as.integer(tcp_n)
  }

  row
}

# Surec CPU% deltasi: (cpu_now - cpu_prev) / (dt * ncores) * 100. prev ortaminda
# saklanan onceki cpu saniye ve zaman damgasini kullanir.
.soak_tel_cpu_delta_pct <- function(prev, key, cpu_sec_now, ncores) {
  if (is.null(prev) || !is.finite(cpu_sec_now)) return(NA_real_)
  now <- as.numeric(Sys.time())
  prev_cpu <- prev[[paste0("cpu_", key)]]
  prev_ts <- prev[[paste0("ts_", key)]]
  prev[[paste0("cpu_", key)]] <- cpu_sec_now
  prev[[paste0("ts_", key)]] <- now
  if (is.null(prev_cpu) || is.null(prev_ts) || !is.finite(prev_cpu) || !is.finite(prev_ts)) {
    return(NA_real_)
  }
  dt <- now - prev_ts
  if (dt <= 0) return(NA_real_)
  pct <- (cpu_sec_now - prev_cpu) / (dt * max(1L, ncores)) * 100
  if (!is.finite(pct) || pct < 0) NA_real_ else round(pct, 1)
}

# ------------------------------------------------------------------------------
# Unix/cloud ornekleme: /proc/stat (sistem CPU delta), /proc/meminfo, ps, ss/netstat.
# ------------------------------------------------------------------------------
.soak_tel_read_proc_stat <- function() {
  if (!file.exists("/proc/stat")) return(NULL)
  lines <- tryCatch(readLines("/proc/stat", n = 1L, warn = FALSE), error = function(e) character(0))
  if (length(lines) == 0L || !grepl("^cpu ", lines[1])) return(NULL)
  vals <- suppressWarnings(as.numeric(strsplit(trimws(sub("^cpu", "", lines[1])), "\\s+")[[1]]))
  vals <- vals[is.finite(vals)]
  if (length(vals) < 4L) return(NULL)
  idle <- vals[4] + (if (length(vals) >= 5L) vals[5] else 0)
  total <- sum(vals)
  list(idle = idle, total = total)
}

.soak_tel_sample_unix <- function(prev, port, ncores, loadgen_pid) {
  row <- .soak_tel_blank_row()

  # Sistem CPU% (/proc/stat idle/total delta). prev her zaman guncellenir;
  # delta yalniz onceki ornek varsa hesaplanir.
  st <- .soak_tel_read_proc_stat()
  if (!is.null(st)) {
    prev_idle <- prev[["sys_idle"]]; prev_total <- prev[["sys_total"]]
    prev[["sys_idle"]] <- st$idle; prev[["sys_total"]] <- st$total
    if (!is.null(prev_idle) && !is.null(prev_total) &&
        is.finite(prev_idle) && is.finite(prev_total)) {
      dt <- st$total - prev_total
      di <- st$idle - prev_idle
      if (dt > 0) row$total_cpu_percent <- round((1 - di / dt) * 100, 1)
    }
  }

  # Bellek (/proc/meminfo).
  if (file.exists("/proc/meminfo")) {
    mi <- tryCatch(readLines("/proc/meminfo", warn = FALSE), error = function(e) character(0))
    grab <- function(tag) {
      ln <- grep(paste0("^", tag, ":"), mi, value = TRUE)
      if (length(ln) == 0L) return(NA_real_)
      .soak_tel_num(gsub("[^0-9]", "", ln[1]))  # kB
    }
    total_kb <- grab("MemTotal"); avail_kb <- grab("MemAvailable")
    if (is.finite(total_kb)) row$mem_total_mb <- round(total_kb / 1024, 1)
    if (is.finite(avail_kb)) row$mem_free_mb <- round(avail_kb / 1024, 1)
    if (is.finite(total_kb) && is.finite(avail_kb)) {
      row$mem_used_mb <- round((total_kb - avail_kb) / 1024, 1)
    }
  }

  # Surec gruplari (ps): RSS (KB) + cputime saniye. R/Rscript ve sqlservr.
  grp_ps_unix <- function(pattern) {
    cmd <- sprintf("ps -e -o rss=,time=,comm= 2>/dev/null | grep -E '%s'", pattern)
    out <- tryCatch(suppressWarnings(system(cmd, intern = TRUE, ignore.stderr = TRUE)),
                    error = function(e) character(0))
    if (length(out) == 0L) return(list(count = 0L, mem_mb = 0, cpu_sec = 0))
    rss_kb <- 0; cpu_sec <- 0; cnt <- 0L
    for (ln in out) {
      parts <- strsplit(trimws(ln), "\\s+")[[1]]
      if (length(parts) < 2L) next
      cnt <- cnt + 1L
      rss_kb <- rss_kb + (.soak_tel_num(parts[1]) %||% 0)
      cpu_sec <- cpu_sec + .soak_tel_parse_etime(parts[2])
    }
    list(count = cnt, mem_mb = round(rss_kb / 1024, 1), cpu_sec = cpu_sec)
  }

  rgrp <- grp_ps_unix("(^|[[:space:]/])(R|Rscript|rsession)($|[[:space:]])")
  row$r_proc_count <- as.integer(rgrp$count)
  row$r_proc_mem_mb <- rgrp$mem_mb
  row$r_proc_cpu_percent <- .soak_tel_cpu_delta_pct(prev, "r", rgrp$cpu_sec, ncores)

  sgrp <- grp_ps_unix("sqlservr")
  row$sqlserver_proc_count <- as.integer(sgrp$count)
  row$sqlserver_mem_mb <- sgrp$mem_mb
  row$sqlserver_cpu_percent <- .soak_tel_cpu_delta_pct(prev, "sql", sgrp$cpu_sec, ncores)

  # Yuk-uretici PID bellegi (/proc/<pid>/status VmRSS).
  if (!is.null(loadgen_pid) && is.finite(loadgen_pid)) {
    sp <- sprintf("/proc/%d/status", as.integer(loadgen_pid))
    if (file.exists(sp)) {
      ln <- grep("^VmRSS:", tryCatch(readLines(sp, warn = FALSE), error = function(e) character(0)),
                 value = TRUE)
      if (length(ln) >= 1L) {
        kb <- .soak_tel_num(gsub("[^0-9]", "", ln[1]))
        if (is.finite(kb)) row$loadgen_mem_mb <- round(kb / 1024, 1)
      }
    }
  }

  # TCP baglanti durum dagilimi (ss veya netstat). Yerel-adres kolonu app portuyla
  # bitenleri sayar (sunucu tarafi; Windows -LocalPort ile ayni anlam). ss'de durum
  # 1. kolon, yerel adres 4. kolon; netstat'ta durum 6. kolon, yerel adres 4. kolon.
  states <- character(0)
  ss_cmd <- sprintf("ss -tan 2>/dev/null | awk 'NR>1 && $4 ~ /:%d$/ {print $1}'", as.integer(port))
  ss_out <- tryCatch(suppressWarnings(system(ss_cmd, intern = TRUE, ignore.stderr = TRUE)),
                     error = function(e) character(0))
  if (length(ss_out) >= 1L) states <- ss_out[nzchar(trimws(ss_out))]
  if (length(states) == 0L) {
    ns_cmd <- sprintf("netstat -tan 2>/dev/null | awk '$4 ~ /:%d$/ {print $6}'", as.integer(port))
    ns_out <- tryCatch(suppressWarnings(system(ns_cmd, intern = TRUE, ignore.stderr = TRUE)),
                       error = function(e) character(0))
    if (length(ns_out) >= 1L) states <- ns_out[nzchar(trimws(ns_out))]
  }
  if (length(states) > 0L) {
    tally <- soak_tcp_state_tally(states)
    for (k in soak_tcp_state_columns()) row[[k]] <- as.integer(tally[[k]])
  }

  row
}

# ps "time=" (etime/cputime) cikisini saniyeye cevirir: [[dd-]hh:]mm:ss.
.soak_tel_parse_etime <- function(x) {
  x <- trimws(as.character(x %||% ""))
  if (!nzchar(x)) return(0)
  days <- 0
  if (grepl("-", x, fixed = TRUE)) {
    dp <- strsplit(x, "-", fixed = TRUE)[[1]]
    days <- .soak_tel_num(dp[1]) %||% 0
    x <- dp[2]
  }
  parts <- suppressWarnings(as.numeric(strsplit(x, ":", fixed = TRUE)[[1]]))
  parts <- parts[is.finite(parts)]
  if (length(parts) == 0L) return(0)
  secs <- 0
  for (p in parts) secs <- secs * 60 + p
  secs + days * 86400
}

# ------------------------------------------------------------------------------
# Toplayici (collector): prev CPU durumu + ncores + baslangic zamani tutar.
# ------------------------------------------------------------------------------
soak_telemetry_collector_new <- function(port = 8009L, loadgen_pid = NULL) {
  prev <- new.env(parent = emptyenv())
  list(
    prev = prev,
    os = soak_telemetry_os(),
    ncores = soak_telemetry_ncores(),
    port = as.integer(port),
    loadgen_pid = if (is.null(loadgen_pid)) NA_real_ else as.numeric(loadgen_pid),
    started = as.numeric(Sys.time())
  )
}

soak_telemetry_sample <- function(collector) {
  t0 <- Sys.time()
  row <- if (identical(collector$os, "windows")) {
    .soak_tel_sample_windows(collector$prev, collector$port, collector$ncores, collector$loadgen_pid)
  } else {
    .soak_tel_sample_unix(collector$prev, collector$port, collector$ncores, collector$loadgen_pid)
  }
  row$elapsed_sec <- round(as.numeric(Sys.time()) - collector$started, 1)
  row$sample_ms <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")) * 1000, 1)
  row
}

# Bir satiri CSV'ye yazar (header zaten yazildi varsayilir).
.soak_tel_csv_line <- function(row, cols) {
  vals <- vapply(cols, function(c) {
    v <- row[[c]]
    if (is.null(v) || length(v) == 0L || (length(v) == 1L && is.na(v))) {
      "NA"
    } else if (is.character(v)) {
      paste0("\"", gsub("\"", "'", v, fixed = TRUE), "\"")
    } else {
      as.character(v)
    }
  }, character(1))
  paste(vals, collapse = ",")
}

# ------------------------------------------------------------------------------
# ARKA SUREC RUNNER: callr ile cagrilir. CSV'ye periyodik satir yazar; stop_path
# olusunca veya max_seconds gecince durur. OS sayaclari okunamasa bile CIKMAZ.
# ------------------------------------------------------------------------------
soak_telemetry_run <- function(csv_path, interval_sec = 5L, port = 8009L,
                               max_seconds = 7200, stop_path = NULL,
                               loadgen_pid = NULL) {
  cols <- soak_telemetry_columns()
  con <- tryCatch(file(csv_path, open = "wt", encoding = "UTF-8"), error = function(e) NULL)
  if (is.null(con)) return(invisible(FALSE))
  on.exit(try(close(con), silent = TRUE), add = TRUE)
  writeLines(paste(cols, collapse = ","), con); flush(con)

  collector <- soak_telemetry_collector_new(port = port, loadgen_pid = loadgen_pid)
  deadline <- Sys.time() + max_seconds

  repeat {
    row <- tryCatch(soak_telemetry_sample(collector),
                    error = function(e) .soak_tel_blank_row())
    tryCatch({ writeLines(.soak_tel_csv_line(row, cols), con); flush(con) },
             error = function(e) NULL)
    if (!is.null(stop_path) && file.exists(stop_path)) break
    if (Sys.time() >= deadline) break
    # Bekleme: stop_path'i sik kontrol et (uzun interval'da hizli durabilmek icin).
    waited <- 0
    while (waited < interval_sec) {
      Sys.sleep(min(0.5, interval_sec))
      waited <- waited + min(0.5, interval_sec)
      if (!is.null(stop_path) && file.exists(stop_path)) break
      if (Sys.time() >= deadline) break
    }
    if (!is.null(stop_path) && file.exists(stop_path)) break
    if (Sys.time() >= deadline) break
  }
  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# Ana surecten arka telemetri surecini baslatir. callr yoksa veya kapaliysa
# {available_intent=FALSE} doner (soak yine de calisir).
# ------------------------------------------------------------------------------
# Bu modulun (soak_system_telemetry.R) dosya yolunu calisma-dizininden BAGIMSIZ
# bulur. Gate repo kokunden, testthat ise tests/testthat'ten calisir.
.soak_telemetry_self_path <- function() {
  rel <- file.path("tests", "scripts", "soak_system_telemetry.R")
  cands <- c(Sys.getenv("MERGEN_REPO_ROOT", unset = ""), ".", "..", "../..", "../../..")
  for (base in cands) {
    if (!nzchar(base)) next
    p <- file.path(base, rel)
    if (file.exists(p)) return(normalizePath(p, winslash = "/", mustWork = FALSE))
  }
  normalizePath(rel, winslash = "/", mustWork = FALSE)  # son care
}

soak_telemetry_start <- function(artifact_dir, cfg_telemetry = soak_telemetry_config(),
                                 max_seconds = 7200, loadgen_pid = Sys.getpid()) {
  if (!isTRUE(cfg_telemetry$enabled)) {
    return(list(started = FALSE, reason = "telemetri kapali (MERGEN_SOAK_TELEMETRY_ENABLED=false)"))
  }
  if (!requireNamespace("callr", quietly = TRUE)) {
    return(list(started = FALSE, reason = "callr paketi yok"))
  }
  dir.create(artifact_dir, recursive = TRUE, showWarnings = FALSE)
  csv_path <- normalizePath(file.path(artifact_dir, "system_telemetry.csv"),
                            winslash = "/", mustWork = FALSE)
  stop_path <- normalizePath(file.path(artifact_dir, ".telemetry_stop"),
                             winslash = "/", mustWork = FALSE)
  if (file.exists(stop_path)) unlink(stop_path)

  this_file <- .soak_telemetry_self_path()
  if (!file.exists(this_file)) {
    return(list(started = FALSE, reason = "telemetri kaynak dosyasi bulunamadi"))
  }

  proc <- tryCatch(
    callr::r_bg(
      function(this_file, csv_path, interval_sec, port, max_seconds, stop_path, loadgen_pid) {
        for (loc in c("C.UTF-8", "en_US.UTF-8", "tr_TR.UTF-8")) {
          if (tryCatch(nzchar(Sys.setlocale("LC_CTYPE", loc)),
                       error = function(e) FALSE, warning = function(w) FALSE)) break
        }
        source(this_file, encoding = "UTF-8")
        soak_telemetry_run(csv_path = csv_path, interval_sec = interval_sec, port = port,
                           max_seconds = max_seconds, stop_path = stop_path,
                           loadgen_pid = loadgen_pid)
      },
      args = list(this_file, csv_path, as.integer(cfg_telemetry$interval_sec),
                  as.integer(cfg_telemetry$app_port), as.numeric(max_seconds), stop_path,
                  as.integer(loadgen_pid)),
      supervise = TRUE
    ),
    error = function(e) NULL
  )

  if (is.null(proc)) {
    return(list(started = FALSE, reason = "telemetri arka surec baslatilamadi"))
  }
  list(started = TRUE, proc = proc, csv_path = csv_path, stop_path = stop_path,
       interval_sec = cfg_telemetry$interval_sec, port = cfg_telemetry$app_port)
}

# Arka telemetri surecini durdurur (stop-file + kisa bekleme + kill).
soak_telemetry_stop <- function(handle) {
  if (is.null(handle) || !isTRUE(handle$started)) return(invisible(NULL))
  tryCatch(if (!is.null(handle$stop_path)) writeLines("stop", handle$stop_path),
           error = function(e) NULL)
  for (i in seq_len(20L)) {
    if (is.null(handle$proc) || !isTRUE(tryCatch(handle$proc$is_alive(), error = function(e) FALSE))) break
    Sys.sleep(0.1)
  }
  tryCatch(if (!is.null(handle$proc)) handle$proc$kill(), error = function(e) NULL)
  invisible(NULL)
}

# ------------------------------------------------------------------------------
# CSV'yi okuyup ozet uretir. telemetry_available: en az bir gercek metrik
# (total_cpu_percent veya mem_used_mb) olculmusse TRUE.
# ------------------------------------------------------------------------------
soak_telemetry_read_csv <- function(csv_path) {
  if (is.null(csv_path) || !file.exists(csv_path)) return(NULL)
  df <- tryCatch(
    utils::read.csv(csv_path, stringsAsFactors = FALSE, na.strings = c("NA", "")),
    error = function(e) NULL
  )
  if (is.null(df) || nrow(df) == 0L) return(NULL)
  df
}

.soak_tel_safe_max <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  x <- x[is.finite(x)]
  if (length(x) == 0L) return(NA_real_)
  round(max(x), 1)
}

# Bir telemetri data.frame'inden TCP durum kolonlarinin maksimumlarini cikarir.
# app_tcp_max_by_state olarak raporlanir: established/syn_sent/syn_recv/time_wait/
# close_wait/listen + toplam. CPU dusukken connection_timeout baskinsa bu dagilim
# darbogazin kabul/backlog/TIME_WAIT mi yoksa app mi oldugunu gosterir.
.soak_tel_tcp_state_maxes <- function(df) {
  out <- list()
  for (c in soak_tcp_state_columns()) {
    v <- if (!is.null(df) && c %in% names(df)) .soak_tel_safe_max(df[[c]]) else NA_real_
    out[[c]] <- if (is.finite(v)) as.integer(v) else NA_integer_
  }
  out
}

soak_telemetry_summarize <- function(csv_path, os_hint = soak_telemetry_os()) {
  df <- soak_telemetry_read_csv(csv_path)
  if (is.null(df)) {
    return(list(
      telemetry_available = FALSE,
      samples = 0L,
      os = os_hint,
      max_total_cpu_percent = NA_real_,
      max_mem_used_mb = NA_real_,
      max_r_process_memory_mb = NA_real_,
      max_r_process_cpu_percent = NA_real_,
      max_sqlserver_memory_mb = NA_real_,
      max_sqlserver_cpu_percent = NA_real_,
      max_loadgen_memory_mb = NA_real_,
      max_tcp_connections_to_app = NA_integer_,
      app_tcp_max_by_state = .soak_tel_tcp_state_maxes(NULL),
      telemetry_warnings = c("Telemetri CSV bulunamadi/bos; sistem sayaclari OLCULEMEDI (UNMEASURED).")
    ))
  }

  get <- function(col) if (col %in% names(df)) df[[col]] else rep(NA_real_, nrow(df))
  cpu_max <- .soak_tel_safe_max(get("total_cpu_percent"))
  mem_used_max <- .soak_tel_safe_max(get("mem_used_mb"))
  available <- is.finite(cpu_max) || is.finite(mem_used_max)

  warnings_vec <- character(0)
  if (!available) {
    warnings_vec <- c(warnings_vec,
      "Sistem CPU/bellek sayaclari okunamadi; telemetri UNMEASURED kabul edilir.")
  }
  if (!is.finite(.soak_tel_safe_max(get("tcp_connections_to_app")))) {
    warnings_vec <- c(warnings_vec, "TCP baglanti sayisi olculemedi (ss/netstat/Get-NetTCPConnection yok).")
  }
  if (!is.finite(.soak_tel_safe_max(get("sqlserver_mem_mb")))) {
    warnings_vec <- c(warnings_vec, "SQL Server sureci gorulemedi (sqlservr yok veya erisilemez).")
  }

  list(
    telemetry_available = isTRUE(available),
    samples = nrow(df),
    os = os_hint,
    max_total_cpu_percent = cpu_max,
    max_mem_used_mb = mem_used_max,
    max_r_process_memory_mb = .soak_tel_safe_max(get("r_proc_mem_mb")),
    max_r_process_cpu_percent = .soak_tel_safe_max(get("r_proc_cpu_percent")),
    max_sqlserver_memory_mb = .soak_tel_safe_max(get("sqlserver_mem_mb")),
    max_sqlserver_cpu_percent = .soak_tel_safe_max(get("sqlserver_cpu_percent")),
    max_loadgen_memory_mb = .soak_tel_safe_max(get("loadgen_mem_mb")),
    max_tcp_connections_to_app = {
      v <- .soak_tel_safe_max(get("tcp_connections_to_app"))
      if (is.finite(v)) as.integer(v) else NA_integer_
    },
    app_tcp_max_by_state = .soak_tel_tcp_state_maxes(df),
    telemetry_warnings = if (length(warnings_vec) == 0L) character(0) else warnings_vec
  )
}

# Belirli bir zaman penceresi (epoch saniye) icin ozet (kapasite merdiveni adimlari).
soak_telemetry_window_summary <- function(csv_path, t_start, t_end) {
  df <- soak_telemetry_read_csv(csv_path)
  if (is.null(df) || !("ts_epoch" %in% names(df))) {
    return(list(telemetry_available = FALSE, samples = 0L,
                max_total_cpu_percent = NA_real_, max_tcp_connections_to_app = NA_integer_,
                max_sqlserver_cpu_percent = NA_real_, max_loadgen_memory_mb = NA_real_))
  }
  ts <- suppressWarnings(as.numeric(df$ts_epoch))
  sel <- which(is.finite(ts) & ts >= (t_start - 1) & ts <= (t_end + 1))
  if (length(sel) == 0L) {
    return(list(telemetry_available = FALSE, samples = 0L,
                max_total_cpu_percent = NA_real_, max_tcp_connections_to_app = NA_integer_,
                max_sqlserver_cpu_percent = NA_real_, max_loadgen_memory_mb = NA_real_))
  }
  sub <- df[sel, , drop = FALSE]
  getc <- function(col) if (col %in% names(sub)) sub[[col]] else rep(NA_real_, nrow(sub))
  cpu_max <- .soak_tel_safe_max(getc("total_cpu_percent"))
  tcp_max <- .soak_tel_safe_max(getc("tcp_connections_to_app"))
  list(
    telemetry_available = is.finite(cpu_max) || is.finite(.soak_tel_safe_max(getc("mem_used_mb"))),
    samples = length(sel),
    max_total_cpu_percent = cpu_max,
    max_mem_used_mb = .soak_tel_safe_max(getc("mem_used_mb")),
    max_sqlserver_cpu_percent = .soak_tel_safe_max(getc("sqlserver_cpu_percent")),
    max_loadgen_memory_mb = .soak_tel_safe_max(getc("loadgen_mem_mb")),
    max_r_process_cpu_percent = .soak_tel_safe_max(getc("r_proc_cpu_percent")),
    max_tcp_connections_to_app = {
      if (is.finite(tcp_max)) as.integer(tcp_max) else NA_integer_
    },
    app_tcp_max_by_state = .soak_tel_tcp_state_maxes(sub)
  )
}

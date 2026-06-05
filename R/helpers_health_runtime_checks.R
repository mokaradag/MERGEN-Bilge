# ==============================================================================
# Dosya Yolu: R/helpers_health_runtime_checks.R
# Açıklama: Sistem Durumu paneli için runtime, SSO, paket ve Bilge Yolaç
#            sağlık kontrol fonksiyonlarını içerir.
# ==============================================================================

health_check_runtime_info <- function(perf_tracker = NULL) {
  start <- Sys.time()
  uptime <- difftime(Sys.time(), .health_app_start_time, units = "secs")
  session_count <- tryCatch({
    if (!is.null(perf_tracker) && is.function(perf_tracker$get_active_session_count)) perf_tracker$get_active_session_count() else NA_integer_
  }, error = function(e) NA_integer_)
  mem <- tryCatch({
    gc_info <- gc()
    used_mb <- sum(as.numeric(gc_info[, 2]), na.rm = TRUE)
    health_format_bytes(used_mb * 1024^2)
  }, error = function(e) "N/A")
  do.call(rbind, list(
    health_result("runtime.uptime", "Uygulama Uptime", "ok", paste(round(as.numeric(uptime) / 60, 1), "dk"), "Süreç başlangıcından beri geçen süre.", health_ms(start)),
    health_result("runtime.r_version", "R Sürümü", "ok", paste(R.version$major, R.version$minor, sep = "."), R.version$platform, health_ms(start)),
    health_result("runtime.memory", "R Bellek Kullanımı", if (identical(mem, "N/A")) "unknown" else "ok", mem, "Yaklaşık R bellek kullanımı.", health_ms(start)),
    health_result("runtime.sessions", "Aktif Oturum", if (is.na(session_count)) "unknown" else "ok", ifelse(is.na(session_count), "N/A", session_count), "Performans izleyiciden alınır.", health_ms(start))
  ))
}

health_check_worker_info <- function() {
  health_safe_check("runtime.workers", "İşçi Havuzu", {
    start <- Sys.time()
    if (!exists("get_worker_monitor_info", mode = "function")) {
      return(health_result("runtime.workers", "İşçi Havuzu", "unknown", "N/A", "get_worker_monitor_info bulunamadı.", health_ms(start), remediation = "helpers_worker_monitor.R yükleme sırasını kontrol edin."))
    }
    info <- get_worker_monitor_info()
    total <- info$total_workers %||% info$total %||% NA
    active <- info$active_workers %||% info$active %||% NA
    queued <- info$queued_jobs %||% info$queued %||% NA
    health_result("runtime.workers", "İşçi Havuzu", "ok", paste0("Toplam: ", total, " / Aktif: ", active, " / Kuyruk: ", queued), "Worker monitor bilgisi alındı.", health_ms(start))
  })
}

health_check_package_sanity <- function(pkgs = c("shiny", "DBI", "odbc", "pool", "jsonlite", "httr", "future", "promises", "DT")) {
  health_safe_check("runtime.packages", "Kritik Paketler", {
    start <- Sys.time()
    missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
    health_result("runtime.packages", "Kritik Paketler", if (length(missing)) "critical" else "ok",
                  if (length(missing)) paste(length(missing), "eksik") else "Hazır",
                  if (length(missing)) paste("Eksik:", paste(missing, collapse = ", ")) else "Kritik paketler yüklenebilir.",
                  health_ms(start), remediation = if (length(missing)) "Eksik paketleri offline paket deposundan kurun." else "")
  })
}

health_check_windows_info <- function() {
  start <- Sys.time()
  user <- Sys.info()[["user"]] %||% Sys.getenv("USERNAME", Sys.getenv("USER", ""))
  do.call(rbind, list(
    health_result("runtime.os", "İşletim Sistemi", "ok", Sys.info()[["sysname"]] %||% .Platform$OS.type, paste(Sys.info()[["release"]] %||% "", Sys.info()[["version"]] %||% ""), health_ms(start)),
    health_result("runtime.hostname", "Hostname", "ok", Sys.info()[["nodename"]] %||% Sys.getenv("COMPUTERNAME", ""), "R sürecinin çalıştığı makine.", health_ms(start)),
    health_result("runtime.process_user", "R Süreç Kullanıcısı", if (nzchar(user)) "ok" else "unknown", user, "Hassas olmayan süreç kullanıcı adı.", health_ms(start)),
    health_result("runtime.clock", "Sunucu Saati", "ok", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), paste("TZ:", Sys.timezone()), health_ms(start))
  ))
}

health_check_sso_mode <- function() {
  val <- Sys.getenv("SSO_ENABLED", "FALSE")
  enabled <- isTRUE(as.logical(val))
  health_result("security.sso", "SSO Modu", "ok", if (enabled) "SSO açık" else "Lokal/non-SSO", paste("SSO_ENABLED=", val), 0)
}

health_check_git_version <- function() {
  start <- Sys.time()
  # Tek doğru sürüm kaynağı: get_app_version_label() (config_version_history.R)
  # version_history.md "## v..." başlığı üzerinden çözer. Sidebar, Hakkında,
  # welcome ve Sistem Durumu hep aynı değeri göstermelidir.
  version <- tryCatch({
    if (exists("get_app_version_label", mode = "function", inherits = TRUE)) {
      get_app_version_label()
    } else {
      "v?"
    }
  }, error = function(e) "v?")

  if (!is.character(version) || length(version) != 1L || !nzchar(version)) {
    version <- "v?"
  }

  # Commit bilgisi opsiyonel ek detay; ortam değişkenlerinden okunur.
  commit_raw <- Sys.getenv("GIT_COMMIT", Sys.getenv("MERGEN_GIT_COMMIT", ""))
  commit_display <- if (!nzchar(commit_raw)) {
    "Commit bilgisi yok"
  } else {
    paste("Commit:", commit_raw)
  }

  health_result(
    "app.version",
    "Sürüm",
    "ok",
    version,
    commit_display,
    health_ms(start)
  )
}

health_check_bilge_yolac <- function() {
  health_safe_check("runtime.bilge_yolac", "Bilge Yolaç CLI/Workdir", {
    start <- Sys.time()
    cli <- Sys.getenv("CLAUDE_CODE_CLI_PATH", Sys.getenv("BILGE_YOLAC_CLI_PATH", ""))
    wd <- Sys.getenv("CLAUDE_CODE_DEFAULT_WORKDIR", Sys.getenv("BILGE_YOLAC_DEFAULT_WORKDIR", ""))

    if (nzchar(wd) && !dir.exists(wd)) {
      dir.create(wd, recursive = TRUE, showWarnings = FALSE)
    }

    cli_ok <- !nzchar(cli) || file.exists(cli)
    wd_ok <- !nzchar(wd) || (dir.exists(wd) && file.access(wd, 2) == 0)
    status <- if (!nzchar(cli) && !nzchar(wd)) "not_configured" else if (cli_ok && wd_ok) "ok" else "warning"
    health_result("runtime.bilge_yolac", "Bilge Yolaç CLI/Workdir", status,
                  if (status == "not_configured") "Tanımlı değil" else "Yapılandırılmış",
                  paste("CLI:", if (nzchar(cli)) cli else "—", "| Workdir:", if (nzchar(wd)) wd else "—"),
                  health_ms(start), remediation = if (status == "warning") "CLI yolu ve çalışma dizini izinlerini kontrol edin." else "")
  })
}
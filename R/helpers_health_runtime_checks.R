# ==============================================================================
# Dosya Yolu: R/helpers_health_runtime_checks.R
# Açıklama: Sistem Durumu paneli için depolama, runtime, SSO, paket ve Bilge Yolaç
#            sağlık kontrol fonksiyonlarını içerir.
# ==============================================================================

# --- DEPOLAMA KONTROLÜ ORTAK YARDIMCILARI ---
# UNC/Unicode Windows yollarında base R varlık/yazma API'leri yol FORMUNA çok
# duyarlıdır: aynı klasör forward-slash UNC (`//sunucu/pay/...`), backslash UNC
# (`\\sunucu\pay\...`), kodlaması onarılmış ya da mapped-drive (`M:\...`)
# biçiminde farklı davranabilir. Ayrıca config açılışta files_root'u
# normalizePath(mustWork=TRUE) ile `M:\sunucu\pay\...` gibi GEÇERSİZ bir
# mapped-drive dizesine bozabilir. Bu yüzden kontrol tek bir dizeye güvenmez;
# yolun tüm makul varyantlarını üretip her birini dener.

# Bir yolun denenecek makul varyantlarını üretir (temiz UNC onarımı dahil).
.health_path_variants <- function(path) {
  path <- as.character(path %||% "")[1]
  if (!nzchar(path)) {
    return(character(0))
  }
  variants <- c(
    path,
    chartr("\\", "/", path),  # forward-slash UNC biçimi
    chartr("/", "\\", path),  # backslash UNC biçimi (tek ters slash)
    suppressWarnings(enc2utf8(path))
  )
  # Opsiyonel onarıcılar (yoksa atlanır). normalize_mcp_path forward-slash UNC'yi
  # korur; normalize_utf8_path kodlamayı onarır (mustWork=FALSE olduğu için M:\...
  # bozulmasına yol açmaz, index yolunun çalışan biçimiyle aynıdır);
  # resolve_readable_path base R ile açılabilen biçimi bulur. Geçersiz bir
  # varyant üretilse bile yazma denemesi zararsızca başarısız olur.
  for (fn in c("repair_turkish_mojibake_path", "normalize_mcp_path", "normalize_utf8_path", "resolve_readable_path")) {
    if (exists(fn, mode = "function", inherits = TRUE)) {
      variants <- c(variants, tryCatch(get(fn)(path), error = function(e) NULL))
    }
  }
  unique(variants[nzchar(variants)])
}

# dir.exists()/file.exists() forward-slash UNC'de yanlış negatif dönebilir; yol
# varyantlarını ve birden çok yöntemi (file.info, list.files, fs, relaxed) dener.
# Yazma iznine bakmaz; yalnızca klasörün ERİŞİLEBİLİR olup olmadığını söyler.
.health_path_present <- function(path, is_dir = TRUE) {
  isTRUE(tryCatch({
    hit <- FALSE
    for (p in .health_path_variants(path)) {
      if (is_dir) {
        info_isdir <- suppressWarnings(file.info(p)$isdir)
        if (isTRUE(dir.exists(p)) || (length(info_isdir) == 1L && isTRUE(info_isdir))) {
          hit <- TRUE; break
        }
        # Erişilebilir dizin, içinde dosya varsa list.files ile hatasız listelenir.
        if (length(suppressWarnings(list.files(p, all.files = TRUE, no.. = TRUE))) > 0L) {
          hit <- TRUE; break
        }
        # Üst klasörü listele; hedefin adı orada mı? dir.exists(UNC) yanlış negatif
        # verse de üst klasör listelemesi çalışabilir.
        if (basename(p) %in% suppressWarnings(list.files(dirname(p), all.files = TRUE, no.. = TRUE))) {
          hit <- TRUE; break
        }
      } else if (isTRUE(file.exists(p))) {
        hit <- TRUE; break
      }
      if (requireNamespace("fs", quietly = TRUE) &&
          isTRUE(if (is_dir) fs::dir_exists(p) else fs::file_exists(p))) {
        hit <- TRUE; break
      }
      if (exists("path_exists_relaxed", mode = "function", inherits = TRUE) &&
          isTRUE(path_exists_relaxed(p))) {
        hit <- TRUE; break
      }
      # normalizePath(mustWork=TRUE) hata VERMEDEN dönerse yol GERÇEKTEN vardır.
      # config_file_store.R açılışta bu çağrıyı files_root için başarıyla yapar
      # (M:\... değeri buradan gelir); yani var olan UNC klasörünü kesin tespit eder.
      if (nzchar(suppressWarnings(tryCatch(normalizePath(p, mustWork = TRUE), error = function(e) "")))) {
        hit <- TRUE; break
      }
    }
    hit
  }, error = function(e) FALSE))
}

# Hedef dizinde gerçek yazma + silme denemesi. Varlık API'lerine güvenmeden
# yazılabilirliği kanıtlar; ok/hata mesajını birlikte döndürür.
.health_write_probe <- function(target_dir, pattern = ".health-", fileext = "") {
  probe_error <- ""
  probe <- tempfile(pattern = pattern, tmpdir = target_dir, fileext = fileext)
  ok <- tryCatch({
    suppressWarnings(writeLines("ok", probe, useBytes = TRUE))
    unlink(probe, force = TRUE) == 0
  }, error = function(e) {
    probe_error <<- conditionMessage(e)
    FALSE
  })
  list(ok = isTRUE(ok), error = probe_error)
}

health_check_path_writable <- function(id, label, path, create_if_missing = FALSE, expect_file = FALSE, require_write = TRUE) {
  health_safe_check(id, label, {
    start <- Sys.time()
    path <- as.character(path %||% "")[1]
    if (!nzchar(path)) {
      return(health_result(id, label, "not_configured", "Tanımlı değil", "Yol boş.", health_ms(start), remediation = "İlgili ortam değişkenini tanımlayın."))
    }

    raw_target <- if (expect_file) dirname(path) else path
    # Türkçe UNC yollarında .Renviron kodlaması yüzünden mojibake olabilir
    # (ör. "Geliştirme" -> "GeliÅŸtirme"); bu bozuk baytlarla dir.exists ve yazma
    # başarısız olur (Sys.getenv ham baytları döndürür). Onar ki gerçek klasör
    # bulunabilsin ve panelde temiz görünsün. config_file_store.R aynı onarımı yapar.
    if (exists("repair_turkish_mojibake_path", mode = "function", inherits = TRUE)) {
      raw_target <- repair_turkish_mojibake_path(raw_target)
    }
    candidates <- .health_path_variants(raw_target)

    # Windows'ta UNC yollarında tempfile+writeLines ve dir.exists/list.files, yol
    # o R oturumunda dir.create ile "canlandırılmadan" (SMB bağlantısı kurulmadan)
    # yanlış başarısız olabilir. mergen_uploads/logs create_if_missing=TRUE ile
    # bu canlandırmayı yaptığı için yazılabilir çıkıyor; files_root ise
    # create_if_missing=FALSE olduğu için canlandırılmadan "bulunamadı" veriyordu.
    # Bu yüzden hedefi her durumda dir.create ile canlandır (var olan dizinde
    # zararsız no-op). Ancak create_if_missing FALSE iken GERÇEKTEN eksik bir
    # klasörü otomatik oluşturup maskelememek için, yeni oluşturduysak geri al.
    created_new <- isTRUE(dir.create(candidates[1], recursive = TRUE, showWarnings = FALSE))
    if (created_new && !isTRUE(create_if_missing)) {
      unlink(candidates[1], recursive = TRUE, force = TRUE)
      return(health_result(
        id, label, "critical",
        normalizePath(raw_target, winslash = "/", mustWork = FALSE),
        "Klasör bulunamadı veya uygulamanın çalışma hesabından erişilemiyor.",
        health_ms(start),
        remediation = "UNC paylaşım erişimini, Windows klasör izinlerini ve uygulamanın çalışma hesabını kontrol edin."
      ))
    }

    # Asıl kanıt gerçek yazma+silme; yol formu (forward-slash UNC, mapped-drive,
    # kodlama) yazmayı engelleyebildiği için TÜM varyantlar denenir. Biri
    # yazılabilirse klasör sağlıklıdır.
    probe <- list(ok = FALSE, error = "")
    for (cand in candidates) {
      probe <- .health_write_probe(cand)
      if (probe$ok) {
        return(health_result(
          id, label, "ok",
          normalizePath(cand, winslash = "/", mustWork = FALSE),
          "Yazma testi başarılı.", health_ms(start), remediation = ""
        ))
      }
    }

    # Hiçbir varyant yazılamadı. Klasörün gerçekten var olup olmadığını sağlam
    # yöntemlerle belirle (bkz. .health_path_present -> normalizePath(mustWork=TRUE)).
    present <- .health_path_present(raw_target, is_dir = TRUE)

    if (present && !isTRUE(require_write)) {
      # Bu kök için KÖK yazması zorunlu değildir (asıl yazma hedefi index.json
      # ayrıca kontrol edilir). Klasör var ve erişilebilir -> sağlıklı.
      return(health_result(
        id, label, "ok",
        normalizePath(raw_target, winslash = "/", mustWork = FALSE),
        "Klasör mevcut ve erişilebilir.",
        health_ms(start),
        remediation = ""
      ))
    }

    if (present) {
      # Klasör ERİŞİLEBİLİR ama yazma kanıtlanamadı: kritik değil, uyarı.
      return(health_result(
        id, label, "warning",
        normalizePath(raw_target, winslash = "/", mustWork = FALSE),
        if (nzchar(probe$error)) paste("Klasör erişilebilir, yazma testi başarısız:", probe$error) else "Klasör erişilebilir ancak yazma testi doğrulanamadı.",
        health_ms(start),
        remediation = "Klasör mevcut; servis hesabının bu klasördeki YAZMA iznini ve UNC paylaşım erişimini kontrol edin."
      ))
    }

    health_result(
      id, label, "critical",
      normalizePath(raw_target, winslash = "/", mustWork = FALSE),
      "Klasör bulunamadı veya uygulamanın çalışma hesabından erişilemiyor.",
      health_ms(start),
      remediation = "UNC paylaşım erişimini, Windows klasör izinlerini ve uygulamanın çalışma hesabını kontrol edin."
    )
  })
}

health_check_index_json <- function(path = getOption("mergen.index_path", Sys.getenv("MERGEN_INDEX_PATH", ""))) {
  health_safe_check("storage.index_json", "Index JSON Okuma/Yazma", {
    start <- Sys.time()
    path <- as.character(path %||% "")[1]
    if (!nzchar(path)) {
      return(health_result("storage.index_json", "Index JSON Okuma/Yazma", "not_configured", "Tanımlı değil", "MERGEN_INDEX_PATH boş.", health_ms(start), remediation = "MERGEN_INDEX_PATH değerini tanımlayın."))
    }

    # Türkçe mojibake onarımı (bkz. health_check_path_writable): "GeliÅŸtirme"
    # gibi bozuk baytlar gerçek klasörü bulunamaz hale getirir.
    if (exists("repair_turkish_mojibake_path", mode = "function", inherits = TRUE)) {
      path <- repair_turkish_mojibake_path(path)
    }

    parent <- dirname(path)
    parent_candidates <- .health_path_variants(parent)

    # UNC canlandırma (bkz. health_check_path_writable). Üst klasör gerçekten
    # yoksa oluşturduğumuzu geri alıp kritik döneriz.
    created_new <- isTRUE(dir.create(parent_candidates[1], recursive = TRUE, showWarnings = FALSE))
    if (created_new) {
      unlink(parent_candidates[1], recursive = TRUE, force = TRUE)
      return(health_result(
        "storage.index_json", "Index JSON Okuma/Yazma", "critical", path,
        "Üst klasör bulunamadı veya uygulamanın çalışma hesabından erişilemiyor.",
        health_ms(start),
        remediation = "Index üst klasörünün UNC erişimini ve Windows izinlerini kontrol edin."
      ))
    }

    # index.json ilk dosya kaydına kadar oluşmayabilir. Üst klasörün gerçek
    # yazılabilirliğini varlık API'lerine güvenmeden, tüm yol varyantlarında ölç.
    probe <- list(ok = FALSE, error = "")
    for (cand in parent_candidates) {
      probe <- .health_write_probe(cand, pattern = ".index-health-", fileext = ".json")
      if (probe$ok) break
    }

    if (!probe$ok) {
      parent_present <- .health_path_present(parent, is_dir = TRUE)
      detail <- if (parent_present) {
        if (nzchar(probe$error)) paste("Üst klasörde yazma başarısız:", probe$error) else "Üst klasörde yazma doğrulanamadı."
      } else {
        "Üst klasör bulunamadı veya uygulamanın çalışma hesabından erişilemiyor."
      }
      return(health_result(
        "storage.index_json", "Index JSON Okuma/Yazma",
        if (parent_present) "warning" else "critical",
        path, detail, health_ms(start),
        remediation = "Index üst klasörünün UNC erişimini ve Windows izinlerini kontrol edin."
      ))
    }

    resolved_path <- file.path(parent, basename(path))
    index_exists <- .health_path_present(resolved_path, is_dir = FALSE)

    readable <- if (!index_exists) {
      TRUE
    } else {
      isTRUE(tryCatch({
        con <- file(resolved_path, open = "rb")
        on.exit(close(con), add = TRUE)
        readBin(con, what = "raw", n = 1L)
        TRUE
      }, error = function(e) FALSE))
    }

    status <- if (readable) "ok" else "critical"
    detail <- if (!index_exists) {
      "Index dosyası henüz oluşturulmamış; üst klasörde yazma uygun."
    } else if (readable) {
      "Okuma uygun. Yazma uygun."
    } else {
      "Okuma başarısız. Yazma uygun."
    }
    health_result("storage.index_json", "Index JSON Okuma/Yazma", status, path, detail, health_ms(start),
                  remediation = if (status == "ok") "" else "Index dosyası ve klasör izinlerini kontrol edin.")
  })
}

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

# Bilge Yolaç kalıcı oturum kaydı sağlık kontrolü: MB_ClaudeCode_Sessions /
# MB_ClaudeCode_Runs tabloları erişilebilir mi ve kaç oturum/çalıştırma
# saklanıyor? Tablolar yoksa (aşamalı devreye alma) "not_configured" döner ve
# hata fırlatmaz; sistem bellek-içi modda çalışmaya devam eder.
health_check_bilge_yolac_sessions <- function() {
  health_safe_check("runtime.bilge_yolac_sessions", "Bilge Yolaç Oturum Kaydı", {
    start <- Sys.time()

    if (!exists("get_connection", mode = "function") ||
        !exists("release_connection", mode = "function")) {
      return(health_result(
        "runtime.bilge_yolac_sessions", "Bilge Yolaç Oturum Kaydı", "unknown",
        "Bağlantı yardımcısı yok",
        "get_connection/release_connection bulunamadı.",
        health_ms(start),
        remediation = "helpers_database.R yükleme sırasını kontrol edin."
      ))
    }

    if (!nzchar(Sys.getenv("DB_DSN", ""))) {
      return(health_result(
        "runtime.bilge_yolac_sessions", "Bilge Yolaç Oturum Kaydı", "unknown",
        "Kontrol atlandı", "Ana veritabanı bağlantısı hazır değil.",
        health_ms(start),
        remediation = "Önce DB_DSN bağlantısını doğrulayın."
      ))
    }

    conn_info <- NULL
    tryCatch({
      conn_info <- get_connection("primary")

      tablolar_var <- isTRUE(DBI::dbExistsTable(conn_info$conn, "MB_ClaudeCode_Sessions")) &&
        isTRUE(DBI::dbExistsTable(conn_info$conn, "MB_ClaudeCode_Runs"))

      if (!tablolar_var) {
        return(health_result(
          "runtime.bilge_yolac_sessions", "Bilge Yolaç Oturum Kaydı",
          "not_configured", "Tablolar yok",
          paste("MB_ClaudeCode_Sessions / MB_ClaudeCode_Runs bulunamadı;",
                "Bilge Yolaç bellek-içi modda çalışır."),
          health_ms(start),
          remediation = "Kurulum: docs/sql/2026-07-bilge-yolac-sessions.sql (bkz. RUNBOOK.md)."
        ))
      }

      ozet <- DBI::dbGetQuery(
        conn_info$conn,
        "SELECT
           COUNT(*) AS toplam,
           SUM(CASE WHEN IsDeleted = 0 THEN 1 ELSE 0 END) AS aktif,
           SUM(CASE WHEN IsDeleted = 1 THEN 1 ELSE 0 END) AS arsiv,
           SUM(CASE WHEN ClaudeCliSessionID IS NOT NULL AND ClaudeCliSessionID <> ''
                    THEN 1 ELSE 0 END) AS devam
         FROM MB_ClaudeCode_Sessions"
      )
      run_sayisi <- DBI::dbGetQuery(
        conn_info$conn,
        "SELECT COUNT(*) AS n FROM MB_ClaudeCode_Runs"
      )$n[1]

      toplam <- as.integer(ozet$toplam[1] %||% 0L)
      aktif  <- as.integer(ozet$aktif[1] %||% 0L)
      arsiv  <- as.integer(ozet$arsiv[1] %||% 0L)
      devam  <- as.integer(ozet$devam[1] %||% 0L)
      run_sayisi <- as.integer(run_sayisi %||% 0L)

      health_result(
        "runtime.bilge_yolac_sessions", "Bilge Yolaç Oturum Kaydı", "ok",
        paste(toplam, "oturum"),
        paste0("Aktif: ", aktif, " | Arşiv: ", arsiv,
               " | Devam edilebilir: ", devam, " | Çalıştırma: ", run_sayisi),
        health_ms(start), remediation = ""
      )
    }, error = function(e) {
      health_result(
        "runtime.bilge_yolac_sessions", "Bilge Yolaç Oturum Kaydı", "unknown",
        "Kontrol başarısız", conditionMessage(e), health_ms(start),
        remediation = "MB_ClaudeCode_Sessions erişimini ve kullanıcı yetkisini kontrol edin."
      )
    }, finally = {
      try(release_connection(conn_info), silent = TRUE)
    })
  })
}

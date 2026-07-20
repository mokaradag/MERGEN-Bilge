# ==============================================================================
# Dosya Yolu: R/helpers_health_checks.R
# Açıklama: Sistem Durumu paneli için güvenli, yan etkisiz ve test edilebilir
#            sağlık kontrol fonksiyonlarını içerir.
# ==============================================================================

.health_app_start_time <- Sys.time()

health_check_app_boot <- function() {
  health_result(
    id = "app.boot",
    label = "Uygulama Başlangıcı",
    status = "ok",
    value = "Çalışıyor",
    detail = "Shiny süreci sağlık kontrolü üretebiliyor.",
    duration_ms = 0,
    remediation = "Başlangıç hatası varsa global.R ve son log kayıtlarını kontrol edin."
  )
}

health_check_env_var <- function(name, required = TRUE) {
  start <- Sys.time()
  value <- Sys.getenv(name, "")
  configured <- nzchar(value)
  status <- if (configured) "ok" else if (required) "critical" else "not_configured"
  health_result(
    id = paste0("env.", name),
    label = name,
    status = status,
    value = health_env_display_value(name, value),
    detail = if (configured) "Ortam değişkeni tanımlı." else "Ortam değişkeni tanımlı değil.",
    duration_ms = health_ms(start),
    remediation = if (!configured && required) paste0(".Renviron içinde ", name, " değerini tanımlayın.") else ""
  )
}

health_check_env_contract <- function(required = c("LOCAL_LLM_ENDPOINT", "DB_DSN", "AI_KEYS_MASTER"),
                                      optional = c("DB_DSN_2", "DB_DSN_3", "LOCAL_TTS_ENDPOINT", "LOCAL_STT_ENDPOINT",
                                                   "IMAGE_GEN_ENDPOINT", "MERGEN_FILES_ROOT", "MERGEN_UPLOADS_DIR",
                                                   "MERGEN_INDEX_PATH", "MERGEN_MCP_BASE_DIR")) {
  do.call(rbind, c(
    lapply(required, health_check_env_var, required = TRUE),
    lapply(optional, health_check_env_var, required = FALSE)
  ))
}

health_check_path_writable <- function(id, label, path, create_if_missing = FALSE, expect_file = FALSE) {
  health_safe_check(id, label, {
    start <- Sys.time()
    path <- as.character(path %||% "")[1]
    if (!nzchar(path)) {
      return(health_result(id, label, "not_configured", "Tanımlı değil", "Yol boş.", health_ms(start), remediation = "İlgili ortam değişkenini tanımlayın."))
    }

    target_dir <- if (expect_file) dirname(path) else path
    if (exists("resolve_readable_path", mode = "function", inherits = TRUE)) {
      target_dir <- tryCatch(resolve_readable_path(target_dir), error = function(e) target_dir)
    }

    if (isTRUE(create_if_missing)) {
      try(dir.create(target_dir, recursive = TRUE, showWarnings = FALSE), silent = TRUE)
    }

    # UNC/Unicode Windows yollarında dir.exists()/file.exists() yanlış negatif
    # dönebilir. Sağlık için asıl kanıt, hedef dizinde gerçek yazma + silme işlemidir.
    probe <- tempfile(pattern = ".health-", tmpdir = target_dir)
    probe_error <- ""
    ok <- tryCatch({
      suppressWarnings(writeLines("ok", probe, useBytes = TRUE))
      unlink(probe, force = TRUE) == 0
    }, error = function(e) {
      probe_error <<- conditionMessage(e)
      FALSE
    })

    if (ok) {
      return(health_result(
        id, label,
        status = "ok",
        value = normalizePath(path, winslash = "/", mustWork = FALSE),
        detail = "Yazma testi başarılı.",
        duration_ms = health_ms(start),
        remediation = ""
      ))
    }

    target_exists <- isTRUE(tryCatch(dir.exists(target_dir), error = function(e) FALSE))
    if (!target_exists && requireNamespace("fs", quietly = TRUE)) {
      target_exists <- isTRUE(tryCatch(fs::dir_exists(target_dir), error = function(e) FALSE))
    }
    if (!target_exists && exists("path_exists_relaxed", mode = "function", inherits = TRUE)) {
      target_exists <- isTRUE(tryCatch(path_exists_relaxed(target_dir), error = function(e) FALSE))
    }

    detail <- if (target_exists) {
      if (nzchar(probe_error)) paste("Yazma testi başarısız:", probe_error) else "Yazma testi başarısız."
    } else {
      "Klasör bulunamadı veya uygulamanın çalışma hesabından erişilemiyor."
    }

    health_result(
      id, label,
      status = "critical",
      value = normalizePath(path, winslash = "/", mustWork = FALSE),
      detail = detail,
      duration_ms = health_ms(start),
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

    parent <- dirname(path)
    if (exists("resolve_readable_path", mode = "function", inherits = TRUE)) {
      parent <- tryCatch(resolve_readable_path(parent), error = function(e) parent)
    }

    # index.json ilk dosya kaydına kadar oluşmayabilir. Üst klasörün gerçek
    # yazılabilirliğini, varlık API'lerine güvenmeden doğrudan geçici dosyayla ölç.
    probe <- tempfile(pattern = ".index-health-", tmpdir = parent, fileext = ".json")
    probe_error <- ""
    writable <- tryCatch({
      suppressWarnings(writeLines("{}", probe, useBytes = TRUE))
      unlink(probe, force = TRUE) == 0
    }, error = function(e) {
      probe_error <<- conditionMessage(e)
      FALSE
    })

    if (!writable) {
      parent_exists <- isTRUE(tryCatch(dir.exists(parent), error = function(e) FALSE))
      if (!parent_exists && requireNamespace("fs", quietly = TRUE)) {
        parent_exists <- isTRUE(tryCatch(fs::dir_exists(parent), error = function(e) FALSE))
      }
      if (!parent_exists && exists("path_exists_relaxed", mode = "function", inherits = TRUE)) {
        parent_exists <- isTRUE(tryCatch(path_exists_relaxed(parent), error = function(e) FALSE))
      }

      detail <- if (parent_exists) {
        if (nzchar(probe_error)) paste("Üst klasörde yazma başarısız:", probe_error) else "Üst klasörde yazma başarısız."
      } else {
        "Üst klasör bulunamadı veya uygulamanın çalışma hesabından erişilemiyor."
      }
      return(health_result(
        "storage.index_json", "Index JSON Okuma/Yazma", "critical", path, detail,
        health_ms(start),
        remediation = "Index üst klasörünün UNC erişimini ve Windows izinlerini kontrol edin."
      ))
    }

    resolved_path <- file.path(parent, basename(path))
    if (exists("resolve_readable_path", mode = "function", inherits = TRUE)) {
      resolved_path <- tryCatch(resolve_readable_path(resolved_path), error = function(e) resolved_path)
    }
    index_exists <- isTRUE(tryCatch(file.exists(resolved_path), error = function(e) FALSE))
    if (!index_exists && exists("path_exists_relaxed", mode = "function", inherits = TRUE)) {
      index_exists <- isTRUE(tryCatch(path_exists_relaxed(resolved_path), error = function(e) FALSE))
    }

    readable <- if (!index_exists) {
      TRUE
    } else {
      tryCatch({
        con <- file(resolved_path, open = "rb")
        on.exit(close(con), add = TRUE)
        readBin(con, what = "raw", n = 1L)
        TRUE
      }, error = function(e) FALSE)
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

health_check_disk_free <- function(path = getwd(), id = "storage.disk_free", label = "Disk Boş Alan") {
  health_safe_check(id, label, {
    start <- Sys.time()
    path <- normalizePath(path, winslash = "/", mustWork = FALSE)

    path_slash <- gsub("\\", "/", path, fixed = TRUE)
    is_unc_path <- grepl("^//[^/]+/[^/]+", path_slash)

    if (.Platform$OS.type == "windows" && is_unc_path) {
      return(health_result(
        id,
        label,
        "ok",
        "UNC paylaşım",
        "Ağ paylaşımı yazılabilir; boş alan bilgisi Windows WMIC ile okunmaz.",
        health_ms(start),
        remediation = ""
      ))
    }

    free_bytes <- NA_real_
    detail <- "Disk bilgisi alınamadı."

    if (.Platform$OS.type == "windows") {
      drive <- substr(path, 1, 2)
      cmd <- sprintf('wmic logicaldisk where "DeviceID=\'%s\'" get Size,FreeSpace /format:list', drive)
      out <- suppressWarnings(system(cmd, intern = TRUE, ignore.stderr = TRUE))
      free_bytes <- suppressWarnings(as.numeric(sub("FreeSpace=", "", grep("FreeSpace=", out, value = TRUE)[1])))
      total_bytes <- suppressWarnings(as.numeric(sub("Size=", "", grep("Size=", out, value = TRUE)[1])))
      if (!is.na(free_bytes) && !is.na(total_bytes)) detail <- paste("Toplam:", health_format_bytes(total_bytes))
    } else {
      out <- suppressWarnings(system(sprintf("df -k '%s' 2>/dev/null | tail -1", path), intern = TRUE))
      parts <- unlist(strsplit(trimws(out[1] %||% ""), "\\s+"))
      if (length(parts) >= 4) {
        free_bytes <- suppressWarnings(as.numeric(parts[4]) * 1024)
        total_bytes <- suppressWarnings(as.numeric(parts[2]) * 1024)
        detail <- paste("Toplam:", health_format_bytes(total_bytes))
      }
    }

    status <- if (is.na(free_bytes)) "unknown" else if (free_bytes < 1024^3) "warning" else "ok"
    health_result(id, label, status, health_format_bytes(free_bytes), detail, health_ms(start),
                  remediation = if (status == "warning") "Diskte en az birkaç GB boş alan bırakın." else "")
  })
}

health_check_db_connection <- function(target = "primary", env_name = "DB_DSN", label = "DB Primary") {
  health_safe_check(paste0("db.", target), label, {
    start <- Sys.time()
    dsn <- Sys.getenv(env_name, "")
    if (!nzchar(dsn)) {
      return(health_result(paste0("db.", target), label, "not_configured", env_name, "DSN tanımlı değil.", health_ms(start), remediation = paste0(env_name, " değerini .Renviron içinde tanımlayın.")))
    }
    if (!exists("get_connection", mode = "function") || !exists("release_connection", mode = "function")) {
      return(health_result(paste0("db.", target), label, "unknown", "Bağlantı yardımcısı yok", "get_connection/release_connection bulunamadı.", health_ms(start), remediation = "helpers_database.R yükleme sırasını kontrol edin."))
    }
    conn_info <- NULL
    tryCatch({
      conn_info <- get_connection(target)
      DBI::dbGetQuery(conn_info$conn, "SELECT 1 AS ok")
      health_result(paste0("db.", target), label, "ok", paste0(env_name, " configured"), "SELECT 1 başarılı.", health_ms(start), remediation = "")
    }, error = function(e) {
      health_result(paste0("db.", target), label, "critical", paste0(env_name, " configured"), conditionMessage(e), health_ms(start), remediation = "DSN, ODBC Driver 17 ve SQL Server erişimini kontrol edin.")
    }, finally = {
      try(release_connection(conn_info), silent = TRUE)
    })
  })
}

health_check_db_schema <- function() {
  health_safe_check("db.schema", "DB Şema Hazırlığı", {
    start <- Sys.time()
    if (!nzchar(Sys.getenv("DB_DSN", "")) || !exists("get_connection", mode = "function")) {
      return(health_result("db.schema", "DB Şema Hazırlığı", "unknown", "Kontrol atlandı", "Ana veritabanı bağlantısı hazır değil.", health_ms(start), remediation = "Önce DB_DSN bağlantısını doğrulayın."))
    }
    conn_info <- NULL
    tryCatch({
      conn_info <- get_connection("primary")
      required <- data.frame(
        table = c("MB_Users", "MB_Chats", "MB_Messages", "MB_Messages", "MB_Users", "MB_Chats"),
        column = c(NA, NA, NA, "ReasoningContent", "UserID", "IsDeleted"),
        stringsAsFactors = FALSE
      )
      missing <- character()
      for (i in seq_len(nrow(required))) {
        tbl <- required$table[i]
        col <- required$column[i]
        if (is.na(col)) {
          q <- "SELECT COUNT(*) AS n FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = ?"
          n <- DBI::dbGetQuery(conn_info$conn, q, params = list(tbl))$n[1]
          if (is.na(n) || n < 1) missing <- c(missing, tbl)
        } else {
          q <- "SELECT COUNT(*) AS n FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = ? AND COLUMN_NAME = ?"
          n <- DBI::dbGetQuery(conn_info$conn, q, params = list(tbl, col))$n[1]
          if (is.na(n) || n < 1) missing <- c(missing, paste0(tbl, ".", col))
        }
      }
      status <- if (length(missing)) "warning" else "ok"
      health_result("db.schema", "DB Şema Hazırlığı", status,
                    if (length(missing)) paste(length(missing), "eksik") else "Hazır",
                    if (length(missing)) paste("Eksik:", paste(missing, collapse = ", ")) else "Kritik tablo ve sütunlar mevcut.",
                    health_ms(start), remediation = if (length(missing)) "DB migration/DDL adımlarını kontrol edin." else "")
    }, error = function(e) {
      health_result("db.schema", "DB Şema Hazırlığı", "unknown", "Kontrol başarısız", conditionMessage(e), health_ms(start), remediation = "INFORMATION_SCHEMA erişimini ve kullanıcı yetkisini kontrol edin.")
    }, finally = {
      try(release_connection(conn_info), silent = TRUE)
    })
  })
}

health_derive_models_url <- function(endpoint) {
  endpoint <- sub("\\?.*$", "", as.character(endpoint %||% ""))
  endpoint <- sub("/+$", "", endpoint)
  if (!nzchar(endpoint)) return("")
  if (grepl("/v1/", endpoint, fixed = TRUE)) sub("(/v1/).*", "\\1models", endpoint) else paste0(endpoint, "/v1/models")
}

health_is_public_url <- function(url) {
  url <- tolower(as.character(url %||% ""))
  if (!grepl("^https?://", url)) return(FALSE)
  host <- sub("^https?://([^/:]+).*$", "\\1", url)
  !(host %in% c("localhost", "127.0.0.1", "::1") || grepl("^(10\\.|192\\.168\\.|172\\.(1[6-9]|2[0-9]|3[0-1])\\.)", host))
}

health_check_http_endpoint <- function(id, label, endpoint, configured_required = FALSE, timeout_sec = 2, expect_json = FALSE) {
  health_safe_check(id, label, {
    start <- Sys.time()
    endpoint <- as.character(endpoint %||% "")
    if (!nzchar(endpoint)) {
      status <- if (configured_required) "critical" else "not_configured"
      return(health_result(id, label, status, "Tanımlı değil", "Uç nokta yapılandırılmamış.", health_ms(start), remediation = "Gerekliyse ilgili LOCAL_*_ENDPOINT değerini tanımlayın."))
    }

    endpoint_host <- tolower(sub("^https?://([^/:]+).*$", "\\1", endpoint))
    if (grepl("\\.com\\.tr$", endpoint_host)) {
      return(health_result(id, label, "ok", "Atlandı", ".com.tr on-prem uç nokta tanımlı; canlı çağrı yapılmadan sağlıklı kabul edildi.", health_ms(start), remediation = ""))
    }

    if (health_is_public_url(endpoint)) {
      return(health_result(id, label, "warning", "Atlandı", "Genel internet adresi algılandı; offline sağlık sayfası public endpoint çağırmaz.", health_ms(start), remediation = "On-prem yerel uç nokta kullanın."))
    }
    if (!requireNamespace("httr", quietly = TRUE)) {
      return(health_result(id, label, "unknown", endpoint, "httr paketi yok.", health_ms(start), remediation = "httr paket kurulumunu kontrol edin."))
    }
    res <- try(httr::GET(endpoint, httr::timeout(timeout_sec)), silent = TRUE)
    if (inherits(res, "try-error")) {
      return(health_result(id, label, "warning", endpoint, "Uç noktaya erişilemedi veya timeout oluştu.", health_ms(start), remediation = "Servisin çalıştığını ve VM firewall ayarlarını kontrol edin."))
    }
    sc <- httr::status_code(res)
    status <- if (sc >= 200 && sc < 500) "ok" else "warning"
    health_result(id, label, status, paste("HTTP", sc), "Hafif erişim kontrolü tamamlandı.", health_ms(start), remediation = if (status == "ok") "" else "Servis loglarını kontrol edin.")
  })
}

health_check_llm_endpoint <- function() {
  endpoint <- ""
  model <- ""
  if (exists("api_config", inherits = TRUE)) {
    model <- as.character(api_config$local_models[1] %||% "")
    endpoint <- if (exists("resolve_local_llm_endpoint", mode = "function")) resolve_local_llm_endpoint(model) else api_config$local_llm_endpoint %||% ""
  } else {
    endpoint <- Sys.getenv("LOCAL_LLM_ENDPOINT", "")
  }
  health_check_http_endpoint("llm.endpoint", "LLM Endpoint", health_derive_models_url(endpoint), configured_required = TRUE, timeout_sec = 2)
}

health_check_reasoning_readiness <- function() {
  health_safe_check("llm.reasoning", "Reasoning Model Hazırlığı", {
    start <- Sys.time()
    if (!exists("apply_model_request_overrides", mode = "function")) {
      return(health_result("llm.reasoning", "Reasoning Model Hazırlığı", "critical", "Fonksiyon yok", "apply_model_request_overrides bulunamadı.", health_ms(start), remediation = "config_api.R yükleme sırasını kontrol edin."))
    }
    cfg <- if (exists("api_config", inherits = TRUE)) api_config else list(local_model_capabilities = list())
    caps <- cfg$local_model_capabilities %||% list()
    thinking <- names(caps)[vapply(caps, function(x) isTRUE(x$thinking), logical(1))]
    missing_override <- thinking[vapply(thinking, function(m) {
      x <- caps[[m]]$request_overrides$chat_template_kwargs$enable_thinking
      is.null(x) || !isTRUE(x)
    }, logical(1))]
    status <- if (length(thinking) == 0) "not_configured" else if (length(missing_override)) "warning" else "ok"
    detail <- if (length(thinking) == 0) "Thinking model tanımı yok." else if (length(missing_override)) paste("enable_thinking eksik olabilir:", paste(missing_override, collapse = ", ")) else "Thinking modellerde request_overrides uygun."
    health_result("llm.reasoning", "Reasoning Model Hazırlığı", status, paste(length(thinking), "thinking model"), detail, health_ms(start), remediation = if (status == "warning") "İlgili model capability request_overrides alanını kontrol edin." else "")
  })
}

# Runtime ve sistem seviyesi kontroller R/helpers_health_runtime_checks.R içinde tutulur.
# Bu dosya tekil source edildiğinde de health_collect_checks() sözleşmesi bozulmasın.
if (!exists("health_check_runtime_info", mode = "function")) {
  runtime_checks_path <- file.path("R", "helpers_health_runtime_checks.R")

  if (file.exists(runtime_checks_path)) {
    if (exists("safe_source", mode = "function")) {
      safe_source(runtime_checks_path, encoding = "UTF-8")
    } else {
      source(runtime_checks_path, encoding = "UTF-8", local = globalenv())
    }
  }
}

health_collect_checks <- function(perf_tracker = NULL, include_slow = TRUE) {
  # Sağlık paneli yapılandırılan UNC yolunu sınar. config_file_store tarafından
  # normalizePath ile oturuma özgü bir mapped-drive harfine çevrilen option,
  # servis hesabında bulunmayabilir ve yanlış kritik üretebilir.
  files_root <- Sys.getenv("MERGEN_FILES_ROOT", "")
  if (!nzchar(files_root)) {
    files_root <- getOption("mergen.files_root", getwd())
  }
  index_path <- getOption(
    "mergen.index_path",
    Sys.getenv("MERGEN_INDEX_PATH", "")
  )

  checks <- list(
    health_check_app_boot(),
    health_check_git_version(),
    health_check_sso_mode(),
    health_check_env_contract(),
    health_check_db_connection("primary", "DB_DSN", "DB Primary"),
    health_check_db_connection("secondary", "DB_DSN_2", "DB Secondary"),
    health_check_db_connection("tertiary", "DB_DSN_3", "DB Tertiary"),
    health_check_db_schema(),
    health_check_llm_endpoint(),
    health_check_reasoning_readiness(),
    health_check_http_endpoint("tts.endpoint", "TTS Endpoint", Sys.getenv("LOCAL_TTS_ENDPOINT", ""), FALSE, 2),
    health_check_http_endpoint("stt.endpoint", "STT Endpoint", Sys.getenv("LOCAL_STT_ENDPOINT", ""), FALSE, 2),
    health_check_http_endpoint("image.endpoint", "Görsel Üretim Endpoint", Sys.getenv("IMAGE_GEN_ENDPOINT", Sys.getenv("LOCAL_IMAGE_ENDPOINT", "")), FALSE, 2),
    health_check_path_writable("storage.files_root", "MERGEN_FILES_ROOT", files_root, FALSE),
    health_check_path_writable("storage.uploads_root", "MERGEN_UPLOADS_DIR", Sys.getenv("MERGEN_UPLOADS_DIR", file.path(getwd(), "mergen_uploads")), TRUE),
    health_check_path_writable("storage.log_dir", "Log Dizini", Sys.getenv("MERGEN_LOG_DIR", file.path(getwd(), "logs")), TRUE),
    health_check_path_writable("storage.mcp_base", "MERGEN_MCP_BASE_DIR", Sys.getenv("MERGEN_MCP_BASE_DIR", ""), FALSE),
    health_check_index_json(index_path),
    health_check_disk_free(getwd(), "storage.disk_free", "Uygulama Diski"),
    health_check_disk_free(Sys.getenv("MERGEN_UPLOADS_DIR", getwd()), "storage.upload_disk_free", "Upload Root Boş Alan"),
    health_check_worker_info(),
    health_check_runtime_info(perf_tracker),
    health_check_package_sanity(),
    health_check_windows_info(),
    health_check_bilge_yolac(),
    health_check_bilge_yolac_sessions()
  )
  out <- do.call(rbind, checks)
  rownames(out) <- NULL
  out
}

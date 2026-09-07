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

# Host çıkarımı köşeli parantezli IPv6 adresini korur: ":" üzerinden kesmek
# `http://[fd00::1]:8080` adresini `[fd00` yapıp yanlış sınıflandırıyordu.
health_url_host <- function(value) {
  host <- sub("^https?://", "", tolower(as.character(value %||% "")))
  # Yol/sorgu/fragment ATILIR; aksi hâlde yoldaki "@" userinfo sanılır.
  host <- sub("[/?#].*$", "", host)
  # `https://user:pass@public.example.com` için host "user" dönüyor ve
  # noktasız-host kuralı uç noktayı DAHİLİ sayıp genel isteği gönderiyordu.
  host <- sub("^.*@", "", host)
  host <- ifelse(
    grepl("^\\[", host),
    sub("^\\[([^]]*)\\].*$", "\\1", host),
    # Köşeli parantezsiz ÇIPLAK IPv6 (birden fazla ":") ilk iki nokta üstünde
    # kesiliyordu: `2001:db8::1` -> `2001`. Bu biçimde port ayrıştırılamaz.
    ifelse(
      lengths(regmatches(host, gregexpr(":", host, fixed = TRUE))) > 1L,
      host,
      sub(":.*$", "", host)
    )
  )
  sub("\\.$", "", host)  # sondaki DNS kök noktası dahili son ek testini düşürüyordu
}

# Operatörün AÇIKÇA on-prem ilan ettiği host kümesi. Kurumsal DNS adı taşıyan
# bir uç nokta (ör. https://tts.kurum.com.tr) literal RFC1918 adresi olmadığı
# için "genel internet" sayılıyor ve HİÇ denenmeden warning raporlanıyordu.
# Değer host ya da tam URL olabilir; ";", "," veya boşlukla ayrılır.
health_internal_hosts <- function() {
  ham <- Sys.getenv("MERGEN_HEALTH_INTERNAL_ENDPOINTS", "")
  if (!nzchar(ham)) return(character(0))
  parcalar <- unlist(strsplit(tolower(ham), "[;,[:space:]]+"))
  parcalar <- parcalar[nzchar(parcalar)]
  if (!length(parcalar)) return(character(0))
  hostlar <- health_url_host(parcalar)
  unique(hostlar[nzchar(hostlar)])
}

# Host'un DAHİLİ bir IP literali olup olmadığını söyler. NA => IP literali değil.
# Önek eşleşmesi tek başına yetmez: `10.example.com` geçerli bir genel DNS adıdır
# ve dört oktetli IPv4 doğrulaması yapılmadan "dahili" sayılıyordu.
health_ip_literal_internal <- function(host) {
  # Joker bağlama adresleri yerel dinleyicidir; `LOCAL_*_ENDPOINT` değeri
  # `http://0.0.0.0:...` / `http://[::]:...` iken kontrol hiç yapılmıyordu.
  if (identical(host, "0.0.0.0") || identical(host, "::")) return(TRUE)

  if (grepl(":", host, fixed = TRUE)) {
    # IPv4-EŞLEMELİ IPv6 (`::ffff:10.0.0.1`) gömülü IPv4 kuralıyla sınıflandırılır.
    esleme <- sub("^(0*:)*0*ffff:", "", tolower(host), perl = TRUE)
    if (!grepl(":", esleme, fixed = TRUE)) return(health_ip_literal_internal(esleme))
    # `0:0:0:0:0:0:0:1` gibi genişletilmiş loopback biçimleri de normalize edilir.
    parcalar <- strsplit(host, ":", fixed = TRUE)[[1]]
    parcalar <- parcalar[nzchar(parcalar)]
    # Boş hextet'ler ayıklandığı için `1::` ve `0:1::` de "son hextet 1" gibi
    # görünüyor ve GENEL adresler dahili sınıflanıyordu; kıyas ORİJİNAL host
    # üzerinde yapılır.
    if (length(parcalar) &&
        grepl("(^|:)0*1$", host, perl = TRUE) &&
        all(grepl("^0*1?$", parcalar)) &&
        sum(parcalar != "" & sub("^0+", "", parcalar) == "1") == 1L &&
        identical(sub("^0+", "", parcalar[length(parcalar)]), "1")) {
      return(TRUE)
    }
    # fc00::/7 benzersiz yerel adres aralığı ve bağlantı-yerel fe80::/10.
    if (grepl("^(f[cd][0-9a-f]{2}:|fe[89ab][0-9a-f]:)", host, perl = TRUE)) return(TRUE)
    return(NA)
  }
  if (!grepl("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", host, perl = TRUE)) return(NA)
  oktet <- suppressWarnings(as.integer(strsplit(host, ".", fixed = TRUE)[[1]]))
  if (anyNA(oktet) || any(oktet < 0L) || any(oktet > 255L)) return(NA)
  # 10/8, 172.16/12, 192.168/16, 127/8 (loopback), 169.254/16 (bağlantı-yerel).
  oktet[1] == 10L ||
    oktet[1] == 127L ||
    (oktet[1] == 172L && oktet[2] >= 16L && oktet[2] <= 31L) ||
    (oktet[1] == 192L && oktet[2] == 168L) ||
    (oktet[1] == 169L && oktet[2] == 254L)
}

health_is_public_url <- function(url) {
  url <- tolower(as.character(url %||% ""))
  if (!grepl("^https?://", url)) return(FALSE)
  host <- health_url_host(url)
  if (identical(host, "localhost")) return(FALSE)
  ip_dahili <- health_ip_literal_internal(host)
  if (!is.na(ip_dahili)) return(!isTRUE(ip_dahili) && !(host %in% health_internal_hosts()))
  # IPv6 adresi tek etiket gibi görünür; "nokta yok => dahili" kuralı buna
  # uygulanamaz (genel bir IPv6 adresi dahili sayılırdı).
  if (grepl(":", host, fixed = TRUE)) {
    return(!(host %in% health_internal_hosts()))
  }
  # Tek etiketli intranet adı (nokta yok) ve bilinen dahili son ekler.
  if (!grepl(".", host, fixed = TRUE)) return(FALSE)
  if (grepl("\\.(local|internal|intranet|lan|corp)$", host, perl = TRUE)) return(FALSE)
  # Operatörün açıkça on-prem ilan ettiği kurumsal DNS adları gerçekten denenir.
  if (host %in% health_internal_hosts()) return(FALSE)
  TRUE
}

health_check_http_endpoint <- function(id, label, endpoint, configured_required = FALSE, timeout_sec = 2, expect_json = FALSE) {
  health_safe_check(id, label, {
    start <- Sys.time()
    endpoint <- as.character(endpoint %||% "")
    if (!nzchar(endpoint)) {
      status <- if (configured_required) "critical" else "not_configured"
      return(health_result(id, label, status, "Tanımlı değil", "Uç nokta yapılandırılmamış.", health_ms(start), remediation = "Gerekliyse ilgili LOCAL_*_ENDPOINT değerini tanımlayın."))
    }

    # `.com.tr` uç noktası HİÇ denenmeden "ok" raporlanıyordu (fail-open):
    # kapalı bir servis sağlıklı görünüyordu. Bunlar on-prem kurumsal adresler
    # olduğundan gerçekten denenir; yalnızca genel internet adresleri atlanır.
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
  # files_root: config_file_store.R açılışta mergen.files_root seçeneğini
  # normalize_utf8_path(mustWork=TRUE) ile üretir; bu, UNC yollarında yolu
  # GEÇERSİZ bir mapped-drive dizesine (`M:\sunucu\pay\...`) bozabilir. Bu
  # yüzden files_root için önce HAM ortam değeri (temiz UNC) kullanılır; kontrol
  # ayrıca tüm yol varyantlarını dener. index_path seçeneği mustWork=FALSE ile
  # üretildiği için temiz kalır ve önce o kullanılır.
  files_root <- Sys.getenv("MERGEN_FILES_ROOT", "")
  if (!nzchar(files_root)) {
    files_root <- getOption("mergen.files_root", getwd())
  }
  index_path <- getOption("mergen.index_path", "")
  if (!nzchar(index_path)) {
    index_path <- Sys.getenv("MERGEN_INDEX_PATH", "")
  }

  # include_slow = FALSE iken atlanan kontroller için ortak "unknown" satırı.
  # DB (ODBC + INFORMATION_SCHEMA), LLM (HTTP) ve disk (zaman aşımsız system())
  # kontrolleri bayrağın DIŞINDA çalışıyor ve uç nokta/yol erişilemezken Shiny
  # sürecini bekletebiliyordu.
  atlandi <- function(id, label) {
    health_result(id, label, "unknown", "Atlandı",
                  "Yavaş kontroller devre dışı (include_slow = FALSE).", 0,
                  remediation = "")
  }
  yavas <- function(id, label, expr) {
    if (isTRUE(include_slow)) expr else atlandi(id, label)
  }

  checks <- list(
    health_check_app_boot(),
    health_check_git_version(),
    health_check_sso_mode(),
    health_check_env_contract(),
    yavas("db.primary", "DB Primary",
          health_check_db_connection("primary", "DB_DSN", "DB Primary")),
    yavas("db.secondary", "DB Secondary",
          health_check_db_connection("secondary", "DB_DSN_2", "DB Secondary")),
    yavas("db.tertiary", "DB Tertiary",
          health_check_db_connection("tertiary", "DB_DSN_3", "DB Tertiary")),
    yavas("db.schema", "DB Şema Hazırlığı", health_check_db_schema()),
    yavas("llm.endpoint", "LLM Endpoint", health_check_llm_endpoint()),
    health_check_reasoning_readiness(),
    # include_slow = FALSE: ağ probu gerektiren yavaş kontroller atlanır.
    # Parametre eskiden hiç kullanılmıyordu ve yavaş problar her zaman koşuyordu.
    yavas("tts.endpoint", "TTS Endpoint", health_check_http_endpoint(
      "tts.endpoint", "TTS Endpoint", Sys.getenv("LOCAL_TTS_ENDPOINT", ""), FALSE, 2)),
    yavas("stt.endpoint", "STT Endpoint", health_check_http_endpoint(
      "stt.endpoint", "STT Endpoint", Sys.getenv("LOCAL_STT_ENDPOINT", ""), FALSE, 2)),
    yavas("image.endpoint", "Görsel Üretim Endpoint", health_check_http_endpoint(
      "image.endpoint", "Görsel Üretim Endpoint",
      Sys.getenv("IMAGE_GEN_ENDPOINT", Sys.getenv("LOCAL_IMAGE_ENDPOINT", "")), FALSE, 2)),
    # files_root: KÖK yazması zorunlu değil (asıl yazma hedefi index.json ayrı
    # kontrol edilir). Var olan bir kök, yazma testi UNC/izin nedeniyle geçmese
    # bile "kritik/bulunamadı" gösterilmemeli; require_write = FALSE.
    health_check_path_writable("storage.files_root", "MERGEN_FILES_ROOT", files_root, FALSE, require_write = FALSE),
    health_check_path_writable("storage.uploads_root", "MERGEN_UPLOADS_DIR", Sys.getenv("MERGEN_UPLOADS_DIR", file.path(getwd(), "mergen_uploads")), TRUE),
    health_check_path_writable("storage.log_dir", "Log Dizini", Sys.getenv("MERGEN_LOG_DIR", file.path(getwd(), "logs")), TRUE),
    health_check_path_writable("storage.mcp_base", "MERGEN_MCP_BASE_DIR", Sys.getenv("MERGEN_MCP_BASE_DIR", ""), FALSE),
    health_check_index_json(index_path),
    yavas("storage.disk_free", "Uygulama Diski",
          health_check_disk_free(getwd(), "storage.disk_free", "Uygulama Diski")),
    yavas("storage.upload_disk_free", "Upload Root Boş Alan",
          health_check_disk_free(Sys.getenv("MERGEN_UPLOADS_DIR", getwd()),
                                 "storage.upload_disk_free", "Upload Root Boş Alan")),
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

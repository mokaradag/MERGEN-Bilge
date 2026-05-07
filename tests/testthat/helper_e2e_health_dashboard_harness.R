# ==============================================================================
# Dosya Yolu: tests/testthat/helper_e2e_health_dashboard_harness.R
# Açıklama: Sistem Durumu sayfası için gerçek servis gerektirmeyen deterministik
#           E2E/race-condition test harness yardımcıları.
# ==============================================================================

e2e_health_fixed_time <- function() {
  as.POSIXct("2026-05-07 09:00:00", tz = "UTC")
}

e2e_health_empty_checks <- function() {
  data.frame(
    id = character(),
    label = character(),
    status = character(),
    severity = integer(),
    value = character(),
    detail = character(),
    duration_ms = numeric(),
    checked_at = character(),
    remediation = character(),
    stringsAsFactors = FALSE
  )
}

e2e_health_result <- function(id, label, status, value = "", detail = "",
                              checked_at = e2e_health_fixed_time(),
                              duration_ms = 0, remediation = "") {
  if (exists("health_result", mode = "function", inherits = TRUE)) {
    return(health_result(
      id = id,
      label = label,
      status = status,
      value = value,
      detail = detail,
      duration_ms = duration_ms,
      checked_at = checked_at,
      remediation = remediation
    ))
  }

  ranks <- c(
    ok = 0L,
    not_configured = 1L,
    unknown = 2L,
    warning = 3L,
    critical = 4L
  )

  status <- as.character(status)[1]
  if (!status %in% names(ranks)) {
    status <- "unknown"
  }

  data.frame(
    id = as.character(id),
    label = as.character(label),
    status = status,
    severity = unname(ranks[[status]]),
    value = as.character(value),
    detail = as.character(detail),
    duration_ms = as.numeric(duration_ms),
    checked_at = format(checked_at, "%Y-%m-%d %H:%M:%S %Z"),
    remediation = as.character(remediation),
    stringsAsFactors = FALSE
  )
}

e2e_health_config <- function() {
  list(
    required_env = c(
      LOCAL_LLM_ENDPOINT = "http://127.0.0.1:8001/v1",
      DB_DSN = "test-dsn",
      AI_KEYS_MASTER = "super-secret-master-key"
    ),
    optional_env = c(
      LOCAL_TTS_ENDPOINT = "",
      LOCAL_STT_ENDPOINT = "",
      IMAGE_GEN_ENDPOINT = "https://example.com/image-api",
      MERGEN_FILES_ROOT = "C:/mergen/files"
    ),
    endpoints = list(
      llm = list(
        id = "endpoint.llm",
        label = "LLM Endpoint",
        url = "http://127.0.0.1:8001/v1/models",
        required = TRUE
      ),
      tts = list(
        id = "endpoint.tts",
        label = "TTS Endpoint",
        url = "",
        required = FALSE
      ),
      image = list(
        id = "endpoint.image",
        label = "Görsel Üretim Endpoint",
        url = "https://example.com/image-api",
        required = FALSE
      )
    )
  )
}

e2e_health_secret_texts <- function(config = e2e_health_config()) {
  values <- c(config$required_env, config$optional_env)
  secret_names <- grep(
    "KEY|TOKEN|SECRET|PASSWORD|PASS|PWD|CREDENTIAL",
    names(values),
    ignore.case = TRUE,
    value = TRUE
  )

  unname(values[secret_names])
}

e2e_health_env_display <- function(name, value) {
  if (exists("health_env_display_value", mode = "function", inherits = TRUE)) {
    return(health_env_display_value(name, value))
  }

  secret_name <- grepl(
    "KEY|TOKEN|SECRET|PASSWORD|PASS|PWD|CREDENTIAL",
    name,
    ignore.case = TRUE
  )

  if (isTRUE(secret_name)) {
    if (nzchar(value)) {
      return(sprintf("configured (%d karakter)", nchar(value)))
    }
    return("missing")
  }

  if (nzchar(value)) "configured" else "missing"
}

e2e_health_env_result <- function(name, value, required = TRUE) {
  configured <- nzchar(value)
  status <- if (configured) {
    "ok"
  } else if (isTRUE(required)) {
    "critical"
  } else {
    "not_configured"
  }

  e2e_health_result(
    id = paste0("env.", name),
    label = name,
    status = status,
    value = e2e_health_env_display(name, value),
    detail = if (configured) {
      "Ortam değişkeni tanımlı."
    } else {
      "Ortam değişkeni tanımlı değil."
    }
  )
}

e2e_health_is_public_url <- function(url) {
  if (exists("health_is_public_url", mode = "function", inherits = TRUE)) {
    return(health_is_public_url(url))
  }

  url <- tolower(as.character(url))
  if (!grepl("^https?://", url)) {
    return(FALSE)
  }

  host <- sub("^https?://([^/:]+).*$", "\\1", url)
  !(host %in% c("localhost", "127.0.0.1", "::1") ||
      grepl("^(10\\.|192\\.168\\.|172\\.(1[6-9]|2[0-9]|3[0-1])\\.)", host))
}

e2e_health_probe_recorder <- function() {
  calls <- character()

  list(
    probe = function(url) {
      calls <<- c(calls, url)
      list(ok = TRUE, code = 200L)
    },
    calls = function() {
      calls
    }
  )
}

e2e_health_endpoint_result <- function(endpoint_cfg, probe) {
  endpoint <- as.character(endpoint_cfg$url)
  required <- isTRUE(endpoint_cfg$required)

  if (!nzchar(endpoint)) {
    status <- if (required) "critical" else "not_configured"

    return(e2e_health_result(
      id = endpoint_cfg$id,
      label = endpoint_cfg$label,
      status = status,
      value = "Tanımlı değil",
      detail = "Uç nokta yapılandırılmamış."
    ))
  }

  if (e2e_health_is_public_url(endpoint)) {
    return(e2e_health_result(
      id = endpoint_cfg$id,
      label = endpoint_cfg$label,
      status = "warning",
      value = "Atlandı",
      detail = "Genel internet adresi algılandı; offline sağlık sayfası public endpoint çağırmaz."
    ))
  }

  probe_result <- probe(endpoint)
  ok <- isTRUE(probe_result$ok)
  code <- as.integer(probe_result$code)

  e2e_health_result(
    id = endpoint_cfg$id,
    label = endpoint_cfg$label,
    status = if (ok) "ok" else "warning",
    value = paste("HTTP", code),
    detail = "Yerel stub endpoint kontrolü tamamlandı."
  )
}

e2e_health_collect_snapshot <- function(config = e2e_health_config(),
                                        probe = e2e_health_probe_recorder()$probe) {
  rows <- list(e2e_health_result(
    id = "app.boot",
    label = "Uygulama Başlangıcı",
    status = "ok",
    value = "Çalışıyor",
    detail = "Test harness sağlık kontrolü üretebiliyor."
  ))

  required_names <- names(config$required_env)
  for (name in required_names) {
    rows <- append(rows, list(e2e_health_env_result(
      name = name,
      value = unname(config$required_env[[name]]),
      required = TRUE
    )))
  }

  optional_names <- names(config$optional_env)
  for (name in optional_names) {
    rows <- append(rows, list(e2e_health_env_result(
      name = name,
      value = unname(config$optional_env[[name]]),
      required = FALSE
    )))
  }

  endpoint_names <- names(config$endpoints)
  for (name in endpoint_names) {
    rows <- append(rows, list(e2e_health_endpoint_result(
      endpoint_cfg = config$endpoints[[name]],
      probe = probe
    )))
  }

  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

e2e_health_new_state <- function() {
  list(
    current_refresh_id = NULL,
    applied_refresh_ids = character(),
    checks = e2e_health_empty_checks(),
    update_count = 0L,
    last_update = "",
    last_skip_reason = NULL,
    messages = list()
  )
}

e2e_health_begin_refresh <- function(state, refresh_id) {
  state$current_refresh_id <- as.character(refresh_id)
  state$messages <- append(state$messages, list(list(
    type = "removeHealthTooltips",
    refresh_id = as.character(refresh_id)
  )))
  state
}

e2e_health_apply_refresh_result <- function(state, refresh_id, checks,
                                            checked_at = e2e_health_fixed_time()) {
  refresh_id <- as.character(refresh_id)

  if (!identical(state$current_refresh_id, refresh_id)) {
    state$last_skip_reason <- "stale_refresh"
    return(state)
  }

  if (refresh_id %in% state$applied_refresh_ids) {
    state$last_skip_reason <- "duplicate_refresh"
    return(state)
  }

  state$checks <- checks
  state$applied_refresh_ids <- c(state$applied_refresh_ids, refresh_id)
  state$update_count <- state$update_count + 1L
  state$last_update <- format(checked_at, "%d.%m.%Y %H:%M:%S")
  state$last_skip_reason <- "applied"

  state$messages <- append(state$messages, list(
    list(
      type = "updateHealthTimestamp",
      refresh_id = refresh_id,
      time = state$last_update
    ),
    list(
      type = "initHealthTooltips",
      refresh_id = refresh_id
    )
  ))

  state
}

e2e_health_tab_names <- function() {
  c("overview", "connectivity", "storage", "runtime", "security", "diagnostics")
}

e2e_health_tab_label <- function(tab) {
  switch(tab,
    overview = "Genel Bakış",
    connectivity = "Bağlantılar",
    storage = "Depolama",
    runtime = "Çalışma Zamanı",
    security = "Güvenlik & Yapılandırma",
    diagnostics = "Tanılama",
    "Genel Bakış"
  )
}

e2e_health_tab_filter <- function(checks, tab) {
  if (identical(tab, "diagnostics") || !nrow(checks)) {
    return(checks)
  }

  prefixes <- switch(tab,
    overview = c("app.", "endpoint.", "env."),
    connectivity = c("endpoint.", "db."),
    storage = c("storage."),
    runtime = c("runtime.", "worker.", "app."),
    security = c("env.", "sso.", "db.schema", "llm.reasoning"),
    character()
  )

  if (!length(prefixes)) {
    return(checks[0, , drop = FALSE])
  }

  keep <- Reduce(`|`, lapply(prefixes, function(prefix) {
    startsWith(checks$id, prefix)
  }))

  checks[keep, , drop = FALSE]
}

e2e_health_render_tab <- function(state, tab) {
  checks <- e2e_health_tab_filter(state$checks, tab)

  rows <- if (!nrow(checks)) {
    "Gösterilecek kontrol sonucu yok."
  } else {
    apply(checks, 1, function(row) {
      paste(
        row[["id"]],
        row[["label"]],
        row[["status"]],
        row[["value"]],
        row[["detail"]],
        sep = " | "
      )
    })
  }

  paste(
    c(
      "Sistem Durumu",
      e2e_health_tab_label(tab),
      paste0("Son Güncelleme: ", state$last_update),
      rows
    ),
    collapse = "\n"
  )
}

e2e_health_render_all_tabs <- function(state) {
  tabs <- e2e_health_tab_names()
  rendered <- lapply(tabs, function(tab) e2e_health_render_tab(state, tab))
  stats::setNames(rendered, tabs)
}

e2e_health_read_repo_text <- function(path) {
  repo_root <- if (exists("resolve_repo_root_for_tests", mode = "function", inherits = TRUE)) {
    resolve_repo_root_for_tests()
  } else {
    normalizePath(".", winslash = "/", mustWork = TRUE)
  }

  full_path <- file.path(repo_root, path)
  size <- suppressWarnings(file.info(full_path)$size[1])

  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]])

  if (is.na(txt)) {
    txt <- ""
  }

  enc2utf8(gsub("\r\n?|\r", "\n", txt, perl = TRUE))
}
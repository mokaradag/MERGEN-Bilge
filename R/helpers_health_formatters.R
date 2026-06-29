# ==============================================================================
# Dosya Yolu: R/helpers_health_formatters.R
# Açıklama: Sistem Durumu paneli için durum normalizasyonu, güvenli biçimlendirme
#            ve ortak HTML yardımcılarını içerir.
# ==============================================================================

health_status_levels <- c("ok", "warning", "critical", "unknown", "not_configured")
health_severity_rank <- c(ok = 0L, not_configured = 1L, unknown = 2L, warning = 3L, critical = 4L)

health_normalize_status <- function(status) {
  status <- as.character(status %||% "unknown")[1]
  if (is.na(status) || !nzchar(trimws(status))) {
    status <- "unknown"
  }

  status <- tolower(trimws(status))
  aliases <- c(
    healthy = "ok", success = "ok", pass = "ok", passed = "ok",
    warn = "warning", error = "critical", fail = "critical", failed = "critical",
    missing = "critical", unconfigured = "not_configured", disabled = "not_configured",
    na = "unknown", unavailable = "unknown"
  )

  # R'de named vector üzerinde [["olmayan_isim"]] hata fırlatır.
  # Bu nedenle önce isim varlığını kontrol ederiz; bilinmeyen değerler unknown'a düşer.
  if (status %in% names(aliases)) {
    status <- unname(aliases[status])
  }

  if (!status %in% health_status_levels) "unknown" else status
}

health_status_label <- function(status) {
  switch(health_normalize_status(status),
    ok = "Sağlıklı",
    warning = "Uyarı",
    critical = "Kritik",
    not_configured = "Tanımlı Değil",
    unknown = "Bilinmiyor"
  )
}

health_status_icon <- function(status) {
  switch(health_normalize_status(status),
    ok = "check-circle",
    warning = "exclamation-triangle",
    critical = "times-circle",
    not_configured = "minus-circle",
    unknown = "question-circle"
  )
}

health_status_class <- function(status) {
  paste0("health-status-", health_normalize_status(status))
}

health_status_severity <- function(status) {
  normalized <- health_normalize_status(status)
  unname(health_severity_rank[normalized])
}

health_escape <- function(x) {
  htmltools::htmlEscape(as.character(x %||% ""), attribute = FALSE)
}

health_safe_value <- function(x, empty = "—") {
  if (is.null(x) || length(x) == 0 || all(is.na(x))) return(empty)
  x <- as.character(x[1])
  if (!nzchar(x)) empty else x
}

health_redact_secret <- function(value, show_length = TRUE) {
  value <- as.character(value %||% "")
  if (!nzchar(value)) return("missing")
  if (isTRUE(show_length)) sprintf("configured (%d karakter)", nchar(value)) else "configured"
}

health_is_secret_name <- function(name) {
  grepl("KEY|TOKEN|SECRET|PASSWORD|PASS|PWD|CREDENTIAL", name, ignore.case = TRUE)
}

health_env_display_value <- function(name, value) {
  if (health_is_secret_name(name)) return(health_redact_secret(value))
  if (nzchar(value %||% "")) "configured" else "missing"
}

health_format_bytes <- function(bytes) {
  bytes <- suppressWarnings(as.numeric(bytes)[1])
  if (is.na(bytes) || bytes < 0) return("N/A")
  units <- c("B", "KB", "MB", "GB", "TB")
  idx <- 1L
  while (bytes >= 1024 && idx < length(units)) {
    bytes <- bytes / 1024
    idx <- idx + 1L
  }
  sprintf("%.1f %s", bytes, units[idx])
}

health_ms <- function(start_time) {
  round(as.numeric(difftime(Sys.time(), start_time, units = "secs")) * 1000)
}

health_result <- function(id, label, status = "unknown", value = "", detail = "",
                          duration_ms = NA_real_, checked_at = Sys.time(), remediation = "") {
  status <- health_normalize_status(status)
  data.frame(
    id = as.character(id),
    label = as.character(label),
    status = status,
    severity = health_status_severity(status),
    value = as.character(value %||% ""),
    detail = as.character(detail %||% ""),
    duration_ms = suppressWarnings(as.numeric(duration_ms)[1]),
    checked_at = format(checked_at, "%Y-%m-%d %H:%M:%S %Z"),
    remediation = as.character(remediation %||% ""),
    stringsAsFactors = FALSE
  )
}

health_safe_check <- function(id, label, expr, remediation = "Kontrol sırasında hata oluştu; logları inceleyin.") {
  start <- Sys.time()
  tryCatch({
    res <- force(expr)
    if (is.data.frame(res)) {
      if (!"duration_ms" %in% names(res) || is.na(res$duration_ms[1])) res$duration_ms <- health_ms(start)
      return(res)
    }
    health_result(id, label, "unknown", detail = "Kontrol beklenmeyen sonuç döndürdü.",
                  duration_ms = health_ms(start), remediation = remediation)
  }, error = function(e) {
    health_result(id, label, "unknown", detail = conditionMessage(e),
                  duration_ms = health_ms(start), remediation = remediation)
  })
}

health_overall_status <- function(checks) {
  if (is.null(checks) || !nrow(checks)) return("unknown")
  worst <- max(checks$severity %||% 2L, na.rm = TRUE)
  matched <- names(health_severity_rank)[match(worst, health_severity_rank)]
  if (length(matched) == 0 || is.na(matched[1]) || !nzchar(matched[1])) "unknown" else matched[1]
}

health_score <- function(checks) {
  if (is.null(checks) || !nrow(checks)) return(0L)
  actionable <- checks[!checks$status %in% c("not_configured"), , drop = FALSE]
  if (!nrow(actionable)) return(0L)
  penalty <- sum(pmax(0, actionable$severity), na.rm = TRUE)
  max_penalty <- nrow(actionable) * max(health_severity_rank)
  as.integer(max(0, round(100 - (penalty / max_penalty * 100))))
}

health_status_pill <- function(status, label = NULL) {
  status <- health_normalize_status(status)
  tags$span(
    class = paste("health-pill", health_status_class(status)),
    `data-health-tooltip` = paste("Durum:", health_status_label(status)),
    icon(health_status_icon(status)),
    label %||% health_status_label(status)
  )
}

health_is_storage_path_id <- function(id) {
  id <- as.character(id %||% "")[1]

  allowed_ids <- c(
    "storage.files_root", "storage.uploads_root", "storage.index_json",
    "storage.log_dir", "storage.mcp_base"
  )

  id %in% allowed_ids || startsWith(id, "storage.path.")
}

health_as_windows_explorer_path <- function(value) {
  value <- as.character(value %||% "")[1]
  if (!nzchar(value)) return(value)

  chartr("/", "\\", value)
}

health_is_copyable_path <- function(value, id = "") {
  value <- as.character(value %||% "")[1]
  id <- as.character(id %||% "")[1]

  if (!nzchar(value)) return(FALSE)
  if (tolower(value) %in% c("n/a", "na", "configured", "missing", "tanımlı değil")) return(FALSE)
  if (tolower(value) %in% health_status_levels) return(FALSE)
  if (!health_is_storage_path_id(id)) return(FALSE)

  normalized_path <- suppressWarnings(
    normalizePath(value, winslash = "\\", mustWork = FALSE)
  )

  isTRUE(file.exists(value)) ||
    isTRUE(dir.exists(value)) ||
    isTRUE(file.exists(normalized_path)) ||
    isTRUE(dir.exists(normalized_path))
}

health_render_value <- function(value, id = "") {
  value <- as.character(value %||% "")
  id <- as.character(id %||% "")
  normalized <- health_normalize_status(value)

  if (tolower(value) %in% health_status_levels) {
    return(health_status_pill(normalized))
  }

  is_storage_path <- health_is_storage_path_id(id)

  # Depolama yolları ortam değişkeninden gelir. Windows/.Renviron sınırında dize
  # geçerli UTF-8 baytları taşısa bile yanlış kodlama (latin1/unknown) ile
  # işaretlenebildiği için tarayıcıya serileştirilirken Türkçe karakterler
  # mojibake'e dönüşür (örn. "ş" -> "ÅŸ"). Metni yalnızca burada, kopyalanabilirlik
  # kontrolünden ve görüntülemeden ÖNCE UTF-8 olarak normalize edip onarırız.
  # Ana onarım yolu R/utils_text_encoding.R içindedir; yardımcı yoksa (izole test)
  # değer olduğu gibi kalır. normalize_text_utf8 kendi içinde tryCatch ile korunur.
  if (is_storage_path && nzchar(value) &&
      exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
    value <- normalize_text_utf8(value, repair_mojibake = TRUE)
  }

  display_value <- if (is_storage_path) {
    health_as_windows_explorer_path(value)
  } else {
    value
  }

  if (health_is_copyable_path(value, id)) {
    return(tags$button(
      type = "button",
      class = "health-path-copy-btn",
      `data-health-path` = display_value,
      `data-health-tooltip` = "Bu tam yolu panoya kopyala. Windows Dosya Gezgini adres çubuğuna yapıştırıp Enter'a basın.",
      icon("copy"),
      tags$span(health_escape(display_value))
    ))
  }

  health_escape(display_value)
}

health_metric_tile <- function(title, value, icon_name = "info-circle", status = "unknown", subtitle = NULL) {
  status <- health_normalize_status(status)
  raw_value <- as.character(value %||% "")
  display_value <- if (tolower(raw_value) %in% health_status_levels) health_status_label(raw_value) else health_safe_value(value)

  div(
    class = paste("health-metric-tile", health_status_class(status)),
    `data-health-tooltip` = subtitle %||% paste(title, "sağlık göstergesi"),
    div(class = "health-metric-icon", icon(icon_name)),
    div(class = "health-metric-body",
        span(class = "health-metric-value", display_value),
        span(class = "health-metric-title", title),
        if (!is.null(subtitle)) span(class = "health-metric-subtitle", subtitle))
  )
}

health_section_card <- function(title, icon_name, ..., class = NULL, tooltip = NULL) {
  div(
    class = paste("analytics-card health-section-card", class %||% ""),
    div(class = "card-title-row",
        h3(class = "card-title", icon(icon_name), title),
        if (!is.null(tooltip)) tags$span(
          class = "info-btn",
          `data-health-tooltip` = tooltip,
          icon("info-circle")
        )),
    ...
  )
}
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
  status <- aliases[[status]] %||% status
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
  unname(health_severity_rank[[health_normalize_status(status)]] %||% health_severity_rank[["unknown"]])
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
  names(health_severity_rank)[match(worst, health_severity_rank)] %||% "unknown"
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
    icon(health_status_icon(status)),
    label %||% health_status_label(status)
  )
}

health_metric_tile <- function(title, value, icon_name = "info-circle", status = "unknown", subtitle = NULL) {
  div(
    class = paste("health-metric-tile", health_status_class(status)),
    div(class = "health-metric-icon", icon(icon_name)),
    div(class = "health-metric-body",
        span(class = "health-metric-value", health_safe_value(value)),
        span(class = "health-metric-title", title),
        if (!is.null(subtitle)) span(class = "health-metric-subtitle", subtitle))
  )
}

health_section_card <- function(title, icon_name, ..., class = NULL) {
  div(
    class = paste("analytics-card health-section-card", class %||% ""),
    div(class = "card-title-row",
        h3(class = "card-title", icon(icon_name), title)),
    ...
  )
}

health_checks_table <- function(checks) {
  if (is.null(checks) || !nrow(checks)) {
    return(div(class = "health-empty", "Gösterilecek kontrol sonucu yok."))
  }
  rows <- lapply(seq_len(nrow(checks)), function(i) {
    row <- checks[i, ]
    tags$tr(
      tags$td(health_status_pill(row$status)),
      tags$td(strong(health_escape(row$label)), tags$div(class = "health-check-id", health_escape(row$id))),
      tags$td(health_escape(row$value)),
      tags$td(health_escape(row$detail)),
      tags$td(ifelse(is.na(row$duration_ms), "—", paste0(row$duration_ms, " ms"))),
      tags$td(health_escape(row$checked_at)),
      tags$td(health_escape(row$remediation))
    )
  })
  div(
    class = "health-table-wrap",
    tags$table(
      class = "health-table",
      tags$thead(tags$tr(
        tags$th("Durum"), tags$th("Kontrol"), tags$th("Değer"), tags$th("Detay"),
        tags$th("Süre"), tags$th("Zaman"), tags$th("Öneri")
      )),
      tags$tbody(rows)
    )
  )
}

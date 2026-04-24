# ==============================================================================
# Dosya Yolu: R/module_health_overview.R
# Açıklama: Sistem Durumu panelinin Genel Bakış sekmesi için UI yardımcıları.
# ==============================================================================

health_overview_ui <- function(checks, last_update) {
  overall <- health_overall_status(checks)
  score <- health_score(checks)
  critical_count <- sum(checks$status == "critical", na.rm = TRUE)
  warning_count <- sum(checks$status == "warning", na.rm = TRUE)
  unknown_count <- sum(checks$status %in% c("unknown", "not_configured"), na.rm = TRUE)
  sso <- checks[checks$id == "security.sso", , drop = FALSE]
  uptime <- checks[checks$id == "runtime.uptime", , drop = FALSE]
  version <- checks[checks$id == "app.version", , drop = FALSE]

  tagList(
    div(
      class = paste("health-hero", health_status_class(overall)),
      div(class = "health-score-ring", span(score), small("/100")),
      div(class = "health-hero-copy",
          h2("Sistem Durumu"),
          p("MERGEN Bilge on-prem çalışma ortamı için özet sağlık görünümü."),
          health_status_pill(overall)),
      div(class = "health-hero-meta",
          span(icon("clock"), paste("Son yenileme:", last_update %||% "—")),
          span(icon("server"), health_safe_value(if (nrow(sso)) sso$value[1] else "—")),
          span(icon("code-branch"), health_safe_value(if (nrow(version)) version$detail[1] else "—")))
    ),
    div(
      class = "health-metrics-grid",
      health_metric_tile("Kritik", critical_count, "times-circle", if (critical_count > 0) "critical" else "ok"),
      health_metric_tile("Uyarı", warning_count, "exclamation-triangle", if (warning_count > 0) "warning" else "ok"),
      health_metric_tile("Bilinmeyen/Tanımsız", unknown_count, "question-circle", if (unknown_count > 0) "unknown" else "ok"),
      health_metric_tile("Uptime", if (nrow(uptime)) uptime$value[1] else "N/A", "stopwatch", "ok"),
      health_metric_tile("Sürüm", if (nrow(version)) version$value[1] else "N/A", "tag", "ok")
    ),
    fluidRow(
      column(
        7,
        health_section_card(
          "Kritik Kontroller",
          "shield-alt",
          health_checks_table(checks[checks$status %in% c("critical", "warning"), , drop = FALSE])
        )
      ),
      column(
        5,
        health_section_card(
          "10 Saniyelik Özet",
          "tachometer-alt",
          div(class = "health-summary-list",
              div(strong("DB Primary:"), health_status_pill(checks$status[match("db.primary", checks$id)] %||% "unknown")),
              div(strong("LLM Endpoint:"), health_status_pill(checks$status[match("llm.endpoint", checks$id)] %||% "unknown")),
              div(strong("Upload Root:"), health_status_pill(checks$status[match("storage.uploads_root", checks$id)] %||% "unknown")),
              div(strong("Index JSON:"), health_status_pill(checks$status[match("storage.index_json", checks$id)] %||% "unknown")),
              div(strong("Worker:"), health_status_pill(checks$status[match("runtime.workers", checks$id)] %||% "unknown")))
        )
      )
    )
  )
}

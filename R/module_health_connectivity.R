# ==============================================================================
# Dosya Yolu: R/module_health_connectivity.R
# Açıklama: Sistem Durumu panelinin Bağlantılar sekmesi için UI yardımcıları.
# ==============================================================================

health_connectivity_ui <- function(checks) {
  ids <- c("db.primary", "db.secondary", "db.tertiary", "llm.endpoint", "tts.endpoint", "stt.endpoint", "image.endpoint", "llm.reasoning")
  subset <- checks[checks$id %in% ids, , drop = FALSE]

  tagList(
    div(
      class = "health-metrics-grid",
      health_metric_tile("DB Primary", subset$status[match("db.primary", subset$id)] %||% "unknown", "database", subset$status[match("db.primary", subset$id)] %||% "unknown"),
      health_metric_tile("DB Secondary", subset$status[match("db.secondary", subset$id)] %||% "unknown", "database", subset$status[match("db.secondary", subset$id)] %||% "unknown"),
      health_metric_tile("DB Tertiary", subset$status[match("db.tertiary", subset$id)] %||% "unknown", "database", subset$status[match("db.tertiary", subset$id)] %||% "unknown"),
      health_metric_tile("LLM", subset$status[match("llm.endpoint", subset$id)] %||% "unknown", "robot", subset$status[match("llm.endpoint", subset$id)] %||% "unknown")
    ),
    health_section_card("Bağlantı Kontrolleri", "plug", health_checks_table(subset))
  )
}

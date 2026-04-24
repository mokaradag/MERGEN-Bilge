# ==============================================================================
# Dosya Yolu: R/module_health_runtime.R
# Açıklama: Sistem Durumu panelinin Çalışma Zamanı sekmesi için UI yardımcıları.
# ==============================================================================

health_runtime_ui <- function(checks, worker_html = NULL) {
  ids <- c("runtime.workers", "runtime.uptime", "runtime.r_version", "runtime.memory", "runtime.sessions", "runtime.packages", "runtime.os", "runtime.hostname", "runtime.process_user", "runtime.clock", "runtime.bilge_yolac")
  subset <- checks[checks$id %in% ids, , drop = FALSE]
  tagList(
    div(
      class = "health-metrics-grid",
      health_metric_tile("Bellek", subset$value[match("runtime.memory", subset$id)] %||% "N/A", "memory", subset$status[match("runtime.memory", subset$id)] %||% "unknown"),
      health_metric_tile("Oturum", subset$value[match("runtime.sessions", subset$id)] %||% "N/A", "users", subset$status[match("runtime.sessions", subset$id)] %||% "unknown"),
      health_metric_tile("R Sürümü", subset$value[match("runtime.r_version", subset$id)] %||% "N/A", "r-project", "ok"),
      health_metric_tile("Paketler", subset$value[match("runtime.packages", subset$id)] %||% "N/A", "box", subset$status[match("runtime.packages", subset$id)] %||% "unknown")
    ),
    fluidRow(
      column(6, health_section_card("Worker Monitor", "cogs", worker_html %||% div(class = "health-empty", "Worker HTML bilgisi alınamadı."))),
      column(6, health_section_card("Runtime Detayları", "server", health_checks_table(subset)))
    )
  )
}

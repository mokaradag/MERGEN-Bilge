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
      health_metric_tile("Bellek", subset$value[match("runtime.memory", subset$id)] %||% "N/A", "memory", subset$status[match("runtime.memory", subset$id)] %||% "unknown", "R sürecinin yaklaşık bellek kullanımı"),
      health_metric_tile("Aktif Oturum", subset$value[match("runtime.sessions", subset$id)] %||% "N/A", "users", subset$status[match("runtime.sessions", subset$id)] %||% "unknown", "Performans izleyiciden gelen aktif oturum sayısı"),
      health_metric_tile("R Sürümü", subset$value[match("runtime.r_version", subset$id)] %||% "N/A", "r-project", "ok", "Çalışan R runtime sürümü"),
      health_metric_tile("Paketler", subset$value[match("runtime.packages", subset$id)] %||% "N/A", "box", subset$status[match("runtime.packages", subset$id)] %||% "unknown", "Kritik R paketlerinin yüklenebilirlik durumu")
    ),
    fluidRow(
      column(
        12,
        health_section_card(
          "İşçi İzleyici",
          "cogs",
          div(class = "health-worker-grid", worker_html %||% div(class = "health-empty", "Worker HTML bilgisi alınamadı.")),
          tooltip = "Arka plan işçi havuzu, aktif iş ve kuyruk durumu."
        )
      )
    ),
    fluidRow(
      column(
        12,
        health_section_card(
          "Çalışma Zamanı Detayları",
          "server",
          health_checks_table(subset, max_height = 380),
          tooltip = "R süreci, işletim sistemi, saat, paket ve Bilge Yolaç çalışma zamanı kontrolleri."
        )
      )
    )
  )
}

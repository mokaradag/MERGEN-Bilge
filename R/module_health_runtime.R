# ==============================================================================
# Dosya Yolu: R/module_health_runtime.R
# Açıklama: Sistem Durumu panelinin Çalışma Zamanı sekmesi için UI yardımcıları.
# ==============================================================================

health_pick_int <- function(values, index, fallback) {
  value <- suppressWarnings(as.integer(values[index]))
  if (length(value) == 0 || is.na(value)) fallback else value
}

health_parse_worker_counts <- function(worker_value) {
  worker_value <- as.character(worker_value %||% "")
  nums <- regmatches(worker_value, gregexpr("[0-9]+", worker_value))[[1]]
  nums <- suppressWarnings(as.integer(nums))
  nums <- nums[!is.na(nums)]

  detected_cores <- suppressWarnings(as.integer(parallel::detectCores(logical = TRUE)))
  if (length(detected_cores) == 0 || is.na(detected_cores) || detected_cores < 1L) {
    detected_cores <- 1L
  }

  total <- health_pick_int(nums, 1L, detected_cores)
  active <- health_pick_int(nums, 2L, 0L)
  queued <- health_pick_int(nums, 3L, 0L)

  total <- max(1L, as.integer(total), na.rm = TRUE)
  active <- max(0L, min(as.integer(active), total, na.rm = TRUE), na.rm = TRUE)
  queued <- max(0L, as.integer(queued), na.rm = TRUE)

  list(total = total, active = active, queued = queued)
}

health_worker_core_visual <- function(worker_value) {
  counts <- health_parse_worker_counts(worker_value)
  total <- counts$total
  active <- counts$active
  queued <- counts$queued
  pct <- round((active / total) * 100)

  core_nodes <- lapply(seq_len(total), function(i) {
    div(
      class = paste("health-core-node", if (i <= active) "active" else "idle"),
      `data-toggle` = "tooltip",
      title = if (i <= active) paste("Çekirdek", i, "aktif") else paste("Çekirdek", i, "boşta"),
      span(i)
    )
  })

  div(
    class = "health-worker-visual-card",
    div(
      class = "health-cpu-orb",
      div(class = "health-cpu-orb-ring"),
      div(class = "health-cpu-orb-inner", span(paste0(pct, "%")), tags$small("aktif kullanım"))
    ),
    div(
      class = "health-core-grid",
      core_nodes
    ),
    div(
      class = "health-worker-legend",
      span(class = "legend-active", icon("circle"), paste("Aktif:", active)),
      span(class = "legend-idle", icon("circle"), paste("Boşta:", total - active)),
      span(class = "legend-queued", icon("stream"), paste("Kuyruk:", queued))
    )
  )
}

health_runtime_ui <- function(checks, worker_html = NULL) {
  ids <- c("runtime.workers", "runtime.uptime", "runtime.r_version", "runtime.memory", "runtime.sessions", "runtime.packages", "runtime.os", "runtime.hostname", "runtime.process_user", "runtime.clock", "runtime.bilge_yolac")
  subset <- checks[checks$id %in% ids, , drop = FALSE]
  worker_value <- subset$value[match("runtime.workers", subset$id)] %||% ""

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
          div(
            class = "health-worker-grid",
            div(class = "health-worker-panel-left", worker_html %||% div(class = "health-empty", "Worker HTML bilgisi alınamadı.")),
            div(class = "health-worker-panel-right", health_worker_core_visual(worker_value))
          ),
          tooltip = "Arka plan işçi havuzu, aktif iş, kuyruk durumu ve VM sanal işlemci kullanım görselleştirmesi."
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

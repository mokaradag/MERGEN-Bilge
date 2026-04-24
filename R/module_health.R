# ==============================================================================
# Dosya Yolu: R/module_health.R
# Açıklama: Sistem Durumu sayfasının ana Shiny modülü; modüler sağlık kontrol
#            yardımcılarını sekmeli yönetici paneli olarak koordine eder.
# ==============================================================================

healthUI <- function(id) {
  ns <- NS(id)

  admin_page_layout(
    ns = ns,
    page_title = "Sistem Durumu",
    page_icon = "heartbeat",
    refresh_btn_id = "refresh_health",
    last_update_id = "last_update_time",
    tabs_id = "health_tabs",
    content_output_id = "health_tab_content",
    tab_panels = list(
      tabPanel(
        title = tags$span(title = "Genel sistem sağlık özeti", tagList(icon("tachometer-alt"), " Genel Bakış")),
        value = "overview"
      ),
      tabPanel(
        title = tags$span(title = "DB ve servis bağlantıları", tagList(icon("plug"), " Bağlantılar")),
        value = "connectivity"
      ),
      tabPanel(
        title = tags$span(title = "Dosya sistemi ve disk kontrolleri", tagList(icon("folder-open"), " Depolama")),
        value = "storage"
      ),
      tabPanel(
        title = tags$span(title = "Worker, bellek ve süreç bilgileri", tagList(icon("server"), " Çalışma Zamanı")),
        value = "runtime"
      ),
      tabPanel(
        title = tags$span(title = "SSO, ortam değişkenleri ve şema", tagList(icon("shield-alt"), " Güvenlik & Yapılandırma")),
        value = "security"
      ),
      tabPanel(
        title = tags$span(title = "Detaylı sağlık kayıtları", tagList(icon("clipboard-list"), " Tanılama")),
        value = "diagnostics"
      )
    )
  ) %>%
    tagAppendChildren(
      tags$head(
        tags$link(rel = "stylesheet", type = "text/css", href = "css/health_dashboard.css"),
        tags$script(src = "js/health_dashboard.js")
      )
    ) %>%
    tagAppendAttributes(class = "health-dashboard-container")
}

healthServer <- function(id, perf_tracker) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    health_refresh_trigger <- reactiveVal(0)
    health_last_update <- reactiveVal(format(Sys.time(), "%d.%m.%Y %H:%M:%S"))

    observe({
      invalidateLater(30000)
      isolate({
        health_refresh_trigger(health_refresh_trigger() + 1)
        health_last_update(format(Sys.time(), "%d.%m.%Y %H:%M:%S"))
        session$sendCustomMessage("updateHealthTimestamp", list(
          id = ns("last_update_time"),
          time = health_last_update()
        ))
      })
    })

    checks_data <- reactive({
      health_refresh_trigger()
      health_collect_checks(perf_tracker = perf_tracker, include_slow = TRUE)
    })

    worker_health_html <- reactive({
      health_refresh_trigger()
      tryCatch({
        if (exists("get_worker_monitor_info", mode = "function") &&
            exists("render_worker_health_html", mode = "function")) {
          render_worker_health_html(get_worker_monitor_info())
        } else {
          div(class = "health-empty", "Worker monitor yardımcıları bulunamadı.")
        }
      }, error = function(e) {
        div(class = "health-empty", paste("Worker bilgisi alınamadı:", conditionMessage(e)))
      })
    })

    output$health_tab_content <- renderUI({
      checks <- checks_data()
      tab <- input$health_tabs %||% "overview"
      admin_init_tooltips(session)

      switch(tab,
        overview = health_overview_ui(checks, health_last_update()),
        connectivity = health_connectivity_ui(checks),
        storage = health_storage_ui(checks),
        runtime = health_runtime_ui(checks, worker_health_html()),
        security = health_security_ui(checks),
        diagnostics = health_diagnostics_ui(checks),
        health_overview_ui(checks, health_last_update())
      )
    })

    observeEvent(input$refresh_health, {
      shinyjs::runjs("$('.tooltip').remove();")
      health_refresh_trigger(health_refresh_trigger() + 1)
      health_last_update(format(Sys.time(), "%d.%m.%Y %H:%M:%S"))
      session$sendCustomMessage("updateHealthTimestamp", list(
        id = ns("last_update_time"),
        time = health_last_update()
      ))
      showToast(session, "Sistem durumu güncellendi", "success")
    })
  })
}

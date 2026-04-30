# ==============================================================================
# Dosya Yolu: R/module_health.R
# Açıklama: Sistem Durumu sayfasının ana Shiny modülü; modüler sağlık kontrol
#            yardımcılarını sekmeli yönetici paneli olarak koordine eder.
# ==============================================================================

health_source_optional <- function(path) {
  if (!file.exists(path)) {
    return(invisible(FALSE))
  }

  if (exists("safe_source", mode = "function")) {
    safe_source(path, encoding = "UTF-8")
  } else {
    source(path, encoding = "UTF-8", local = globalenv())
  }

  invisible(TRUE)
}

# global.R kaynak sırası güncel değilse bile modül kendi bağımlılıklarını güvenli yükler.
if (!exists("health_collect_checks", mode = "function") ||
    !exists("health_status_pill", mode = "function") ||
    !exists("health_check_runtime_info", mode = "function")) {
  health_source_optional("R/helpers_health_formatters.R")
  health_source_optional("R/helpers_health_runtime_checks.R")
  health_source_optional("R/helpers_health_checks.R")
}

# Sekme yardımcıları R/module_health.R içinde büyük HTML blokları oluşmasını engeller.
health_source_optional("R/module_health_overview.R")
health_source_optional("R/module_health_connectivity.R")
health_source_optional("R/module_health_storage.R")
health_source_optional("R/module_health_runtime.R")
health_source_optional("R/module_health_security.R")
health_source_optional("R/module_health_diagnostics.R")

healthUI <- function(id) {
  ns <- NS(id)

  tagList(
    tags$head(
      tags$link(rel = "stylesheet", type = "text/css", href = "css/health_dashboard.css"),
      tags$script(src = "js/health_dashboard.js")
    ),
    div(
      class = "health-dashboard-container",
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
      )
    )
  )
}

healthServer <- function(id, perf_tracker) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    health_refresh_trigger <- reactiveVal(0)
    health_last_update <- reactiveVal(format(Sys.time(), "%d.%m.%Y %H:%M:%S"))

    send_health_timestamp <- function() {
      current_time <- isolate(health_last_update())
      payload <- list(id = ns("last_update_time"), time = current_time)
      session$sendCustomMessage("updateHealthTimestamp", payload)
      session$sendCustomMessage("updateAdminTimestamp", payload)
    }

    # İlk render tamamlandığında üst sağdaki zaman damgasını hemen doldur.
    # onFlushed callback'i reactive consumer değildir; reactiveVal okumaları isolate içinde yapılmalıdır.
    session$onFlushed(function() {
      send_health_timestamp()
      session$sendCustomMessage("initHealthTooltips", list())
    }, once = TRUE)

    observe({
      # Sağlık kontrolleri DB/endpoint probe içerebildiği için otomatik yenileme seyrek tutulur.
      invalidateLater(120000)
      isolate({
        health_refresh_trigger(health_refresh_trigger() + 1)
        health_last_update(format(Sys.time(), "%d.%m.%Y %H:%M:%S"))
        send_health_timestamp()
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
          div(class = "health-empty", "Worker izleyici yardımcıları bulunamadı.")
        }
      }, error = function(e) {
        div(class = "health-empty", paste("Worker bilgisi alınamadı:", conditionMessage(e)))
      })
    })

    output$health_tab_content <- renderUI({
      checks <- checks_data()
      tab <- input$health_tabs %||% "overview"

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

    observe({
      # Sekme değişimi veya manuel/otomatik yenileme sonrasında yeni DOM için tooltip'leri tekrar bağla.
      input$health_tabs
      health_refresh_trigger()
      session$onFlushed(function() {
        session$sendCustomMessage("removeHealthTooltips", list())
        session$sendCustomMessage("initHealthTooltips", list())
        send_health_timestamp()
      }, once = TRUE)
    })

    observeEvent(input$refresh_health, {
      session$sendCustomMessage("removeHealthTooltips", list())
      shinyjs::runjs("$('.tooltip').remove();")
      health_refresh_trigger(health_refresh_trigger() + 1)
      health_last_update(format(Sys.time(), "%d.%m.%Y %H:%M:%S"))
      send_health_timestamp()
      session$sendCustomMessage("initHealthTooltips", list())
      showToast(session, "Sistem durumu güncellendi", "success")
    })
  })
}
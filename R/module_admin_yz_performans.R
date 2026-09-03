# Dosya Yolu: R/module_admin_yz_performans.R
# Açıklama: Yönetici paneli - Genel Analiz modülünün "YZ Performansı" sekmesi.
#            Model performans karşılaştırması, hata oranları, en yavaş/hızlı
#            sorgu tabloları.

# ==============================================================================
# YZ PERFORMANSI SEKMESİ - UI VE GRAFİKLER
# ==============================================================================

#' YZ Performansı sekmesinin UI içeriğini oluşturur
admin_ai_perf_ui <- function(ns, create_info_button) {
  tagList(
    fluidRow(
      column(
        width = 6,
        div(
          class = "analytics-card",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("chart-bar"), " Model Performansı Karşılaştırması"),
            create_info_button("Her modelin ortalama yanıt süresini karşılaştırır.")
          ),
          highcharter::highchartOutput(ns("model_performance_chart"), height = "350px")
        )
      ),
      column(
        width = 6,
        div(
          class = "analytics-card",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("exclamation-circle"), " Model Hata Oranları"),
            create_info_button("Her modelin hata oranını gösterir (%).")
          ),
          highcharter::highchartOutput(ns("model_errors_chart"), height = "350px")
        )
      )
    ),
    fluidRow(
      column(
        width = 6,
        div(
          class = "analytics-card", style = "min-height: 480px;",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("hourglass-end"), " En Yavaş 20 Sorgu"),
            create_info_button("En uzun süren 20 YZ yanıtının listesi.")
          ),
          div(class = "table-container", DT::DTOutput(ns("slowest_queries_table")))
        )
      ),
      column(
        width = 6,
        div(
          class = "analytics-card", style = "min-height: 480px;",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("bolt"), " En Hızlı 20 Sorgu"),
            create_info_button("En kısa sürede yanıtlanan 20 YZ sorgusunun listesi.")
          ),
          div(class = "table-container", DT::DTOutput(ns("fastest_queries_table")))
        )
      )
    )
  )
}

#' YZ Performansı grafiklerini ve tablolarını kaydeder
admin_ai_perf_outputs <- function(output, analytics_data_fn, turkish_dt_language) {

  # Model performansı karşılaştırması (yatay çubuk)
  output$model_performance_chart <- highcharter::renderHighchart({
    data <- analytics_data_fn()$model_performance
    if (nrow(data) == 0) return(highcharter::highchart())

    data <- data[order(data$avg_duration), ]
    data$avg_duration <- round(data$avg_duration, 2)

    chart_data <- lapply(1:nrow(data), function(i) {
      list(y = data$avg_duration[i], total_count = data$total_count[i])
    })

    highcharter::highchart() %>%
      highcharter::hc_chart(type = "bar", backgroundColor = "transparent") %>%
      highcharter::hc_title(text = NULL) %>%
      highcharter::hc_xAxis(categories = data$ModelUsed, labels = list(style = list(color = "#999"))) %>%
      highcharter::hc_yAxis(
        title = list(text = "Ort. Yanıt Süresi (sn)", style = list(color = "#999")),
        labels = list(style = list(color = "#999")), gridLineColor = "#444"
      ) %>%
      highcharter::hc_plotOptions(bar = list(borderWidth = 0, colorByPoint = TRUE)) %>%
      highcharter::hc_add_series(
        name = "Süre", data = chart_data,
        colors = c("#10b981", "#22c55e", "#84cc16", "#f59e0b", "#f97316", "#ef4444")
      ) %>%
      highcharter::hc_tooltip(
        backgroundColor = "#1a1a1a", borderColor = "#333", style = list(color = "#fff"),
        formatter = JS("function() { return '<b>' + this.x + '</b><br/>Ort. Süre: ' + this.y + ' sn<br/>Toplam Yanıt: ' + this.point.total_count; }")
      ) %>%
      highcharter::hc_legend(enabled = FALSE) %>%
      highcharter::hc_credits(enabled = FALSE)
  })

  # Model hata oranları (yatay çubuk)
  output$model_errors_chart <- highcharter::renderHighchart({
    data <- analytics_data_fn()$model_errors
    if (nrow(data) == 0) return(highcharter::highchart())

    data <- data[order(data$error_rate), ]
    data$error_rate <- round(data$error_rate, 2)

    chart_data <- lapply(1:nrow(data), function(i) {
      list(y = data$error_rate[i], error_count = data$error_count[i], total_count = data$total_count[i])
    })

    highcharter::highchart() %>%
      highcharter::hc_chart(type = "bar", backgroundColor = "transparent") %>%
      highcharter::hc_title(text = NULL) %>%
      highcharter::hc_xAxis(categories = data$ModelUsed, labels = list(style = list(color = "#999"))) %>%
      highcharter::hc_yAxis(
        title = list(text = "Hata Oranı (%)", style = list(color = "#999")),
        labels = list(style = list(color = "#999")), gridLineColor = "#444"
      ) %>%
      highcharter::hc_plotOptions(bar = list(borderWidth = 0, colorByPoint = TRUE)) %>%
      highcharter::hc_add_series(
        name = "Hata Oranı", data = chart_data,
        colors = c("#10b981", "#22c55e", "#84cc16", "#f59e0b", "#f97316", "#ef4444")
      ) %>%
      highcharter::hc_tooltip(
        backgroundColor = "#1a1a1a", borderColor = "#333", style = list(color = "#fff"),
        formatter = JS("function() { return '<b>' + this.x + '</b><br/>Hata Oranı: %' + this.y + '<br/>Hata Sayısı: ' + this.point.error_count + ' / ' + this.point.total_count; }")
      ) %>%
      highcharter::hc_legend(enabled = FALSE) %>%
      highcharter::hc_credits(enabled = FALSE)
  })

  # Sorgu tablosu oluşturucu (tekrar eden kod için yardımcı)
  sorgu_tablosu_olustur <- function(data, turkish_dt_language) {
    if (nrow(data) == 0) return(DT::datatable(data.frame()))

    data$row_num <- 1:nrow(data)
    data$ResponseDuration <- round(data$ResponseDuration, 2)
    data$query_time <- format(as.POSIXct(data$query_time), "%d.%m.%Y %H:%M")
    display_data <- data[, c("row_num", "ModelUsed", "ResponseDuration", "query_preview", "query_time")]
    colnames(display_data) <- c("#", "Model", "Süre (sn)", "Sorgu Önizleme", "Tarih")

    DT::datatable(
      display_data,
      options = list(
        dom = 't', pageLength = 20,
        scrollY = "350px", scrollCollapse = TRUE,
        ordering = FALSE, language = turkish_dt_language,
        columnDefs = list(
          list(className = 'dt-center', targets = c(0, 2, 4)),
          list(className = 'row-number-col', targets = 0),
          list(width = '40px', targets = 0),
          list(width = '250px', targets = 3)
        ),
        headerCallback = admin_dt_header_callback
      ),
      class = "admin-datatable", rownames = FALSE
    )
  }

  # En yavaş sorgular tablosu
  output$slowest_queries_table <- DT::renderDT({
    sorgu_tablosu_olustur(analytics_data_fn()$slowest_queries, turkish_dt_language)
  })

  # En hızlı sorgular tablosu
  output$fastest_queries_table <- DT::renderDT({
    sorgu_tablosu_olustur(analytics_data_fn()$fastest_queries, turkish_dt_language)
  })
}
# Dosya Yolu: R/module_admin_zaman_analizi.R
# Açıklama: Yönetici paneli - Genel Analiz modülünün "Zaman Analizi" sekmesi.
#            Haftalık söyleşi trendi, yeni kullanıcı aktivasyonu ve aylık
#            büyüme grafiği.

# ==============================================================================
# ZAMAN ANALİZİ SEKMESİ - UI VE GRAFİKLER
# ==============================================================================

#' Zaman Analizi sekmesinin UI içeriğini oluşturur
admin_time_analysis_ui <- function(data, ns, create_metric_card, create_info_button, format_number) {

  peak_hour <- "N/A"
  if (nrow(data$peak_hours) >= 2) {
    h1 <- data$peak_hours$hour_num[1]
    h2 <- data$peak_hours$hour_num[2]
    peak_hour <- sprintf("%02d:00-%02d:00, %02d:00-%02d:00", h1, h1+1, h2, h2+1)
  } else if (nrow(data$peak_hours) == 1) {
    h1 <- data$peak_hours$hour_num[1]
    peak_hour <- sprintf("%02d:00-%02d:00", h1, h1+1)
  }

  weekly_users <- if (nrow(data$this_week_stats) > 0) data$this_week_stats$weekly_users[1] else 0
  weekly_chats <- if (nrow(data$this_week_stats) > 0) data$this_week_stats$weekly_chats[1] else 0

  monthly_growth_text <- "N/A"
  if (nrow(data$monthly_growth) >= 2) {
    mg <- data$monthly_growth
    mg <- mg[order(mg$year_num, mg$month_num), ]
    if (nrow(mg) >= 2) {
      prev <- mg$chat_count[nrow(mg) - 1]
      curr <- mg$chat_count[nrow(mg)]
      if (prev > 0) {
        growth <- ((curr - prev) / prev) * 100
        monthly_growth_text <- sprintf("%+.1f%%", growth)
      }
    }
  }

  tagList(
    div(
      class = "metrics-grid-3",
      create_metric_card("En Yoğun Saat Dilimleri", peak_hour, "clock", "orange",
        tooltip = "En fazla söyleşi başlatılan saat dilimleri."),
      create_metric_card("Haftalık Kullanıcı", format_number(weekly_users), "users", "blue",
        tooltip = "Son 7 günde aktif olan benzersiz kullanıcı sayısı."),
      create_metric_card("Aylık Büyüme", monthly_growth_text, "chart-line", "purple",
        tooltip = "Son ayın bir önceki aya göre söyleşi sayısı değişimi (%).")
    ),
    fluidRow(
      column(
        width = 12,
        div(
          class = "analytics-card",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("chart-line"), " Haftalık Eğilim (Son 24 Hafta)"),
            create_info_button("Son 24 haftadaki söyleşi sayısı trendi.")
          ),
          highcharter::highchartOutput(ns("weekly_trend_chart"), height = "300px")
        )
      )
    ),
    fluidRow(
      column(
        width = 6,
        div(
          class = "analytics-card", style = "min-height: 420px;",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("user-plus"), " Yeni Kullanıcı Aktivasyon Analizi"),
            create_info_button("Birden fazla söyleşi başlatan kullanıcıların aktivasyon analizi.")
          ),
          div(class = "table-container", style = "height: 320px; overflow-y: auto;",
            DT::dataTableOutput(ns("new_user_activation_table")))
        )
      ),
      column(
        width = 6,
        div(
          class = "analytics-card", style = "min-height: 420px;",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("chart-bar"), " Aylık Büyüme Grafiği"),
            create_info_button("Son 6 aydaki söyleşi sayısı ve benzersiz kullanıcı sayısı trendi.")
          ),
          highcharter::highchartOutput(ns("monthly_growth_chart"), height = "320px")
        )
      )
    )
  )
}

#' Zaman Analizi grafiklerini ve tablolarını kaydeder
admin_time_analysis_outputs <- function(output, analytics_data_fn, turkish_dt_language, turkish_months) {

  # Haftalık söyleşi trendi (areaspline grafik)
  output$weekly_trend_chart <- highcharter::renderHighchart({
    data <- analytics_data_fn()$weekly_trend
    if (nrow(data) == 0) return(highcharter::highchart())

    data <- data[order(data$year_num, data$week_num), ]

    # Tek değer olduğunda "Hafta 10" gibi kısa etiketler yerine tarih aralığı göster
    data$week_label <- if (nrow(data) <= 3) {
      paste0(format(as.Date(data$week_start), "%d.%m"), " - ", format(as.Date(data$week_end), "%d.%m.%Y"))
    } else {
      paste0("Hafta ", data$week_num)
    }
    data$week_range <- paste0(
      format(as.Date(data$week_start), "%d.%m"),
      " - ",
      format(as.Date(data$week_end), "%d.%m.%Y")
    )

    chart_data <- lapply(1:nrow(data), function(i) {
      list(
        y = data$cnt[i], week_num = data$week_num[i],
        year_num = data$year_num[i], week_range = data$week_range[i]
      )
    })

    highcharter::highchart() %>%
      highcharter::hc_chart(type = "areaspline", backgroundColor = "transparent") %>%
      highcharter::hc_title(text = NULL) %>%
      highcharter::hc_xAxis(
        categories = data$week_label,
        labels = list(style = list(color = "#999"), rotation = -45)
      ) %>%
      highcharter::hc_yAxis(
        title = list(text = "Söyleşi Sayısı", style = list(color = "#999")),
        labels = list(style = list(color = "#999")), gridLineColor = "#444"
      ) %>%
      highcharter::hc_plotOptions(
        areaspline = list(marker = list(enabled = TRUE, radius = 3), lineWidth = 2.5)
      ) %>%
      highcharter::hc_add_series(
        name = "Söyleşi", data = chart_data, color = "#22c55e",
        fillColor = list(
          linearGradient = list(x1 = 0, y1 = 0, x2 = 0, y2 = 1),
          stops = list(list(0, "rgba(34, 197, 94, 0.3)"), list(1, "rgba(34, 197, 94, 0)"))
        )
      ) %>%
      highcharter::hc_tooltip(
        backgroundColor = "#1a1a1a", borderColor = "#333", style = list(color = "#fff"),
        formatter = JS("function() { return '<b>Hafta ' + this.point.week_num + ' (' + this.point.year_num + ')</b><br/>' + this.point.week_range + '<br/>Söyleşi: ' + this.y; }")
      ) %>%
      highcharter::hc_legend(enabled = FALSE) %>%
      highcharter::hc_credits(enabled = FALSE)
  })

  # Yeni kullanıcı aktivasyon tablosu
  output$new_user_activation_table <- DT::renderDataTable({
    data <- analytics_data_fn()$new_user_activation
    if (nrow(data) == 0) return(DT::datatable(data.frame()))

    data$row_num <- 1:nrow(data)
    data$first_chat <- format(as.POSIXct(data$first_chat), "%d.%m.%Y")
    data$display_name <- ifelse(!is.na(data$full_name) & nzchar(data$full_name), data$full_name, data$user_name)
    display_data <- data[, c("row_num", "display_name", "first_chat", "chat_count", "active_days")]
    colnames(display_data) <- c("#", "Kullanıcı", "İlk Söyleşi", "Söyleşi Sayısı", "Aktif Gün")

    DT::datatable(
      display_data,
      options = list(
        dom = 't', pageLength = 20,
        scrollY = "280px", scrollCollapse = TRUE,
        ordering = TRUE, order = list(list(2, 'desc')),
        language = turkish_dt_language,
        columnDefs = list(
          list(className = 'dt-center', targets = c(0, 2, 3, 4)),
          list(className = 'row-number-col', targets = 0),
          list(width = '40px', targets = 0),
          list(orderable = FALSE, targets = 0)
        ),
        headerCallback = admin_dt_header_callback
      ),
      class = "admin-datatable", rownames = FALSE
    )
  })

  # Aylık büyüme grafiği (çift eksenli: sütun + çizgi)
  output$monthly_growth_chart <- highcharter::renderHighchart({
    data <- analytics_data_fn()$monthly_growth
    if (nrow(data) == 0) return(highcharter::highchart())

    data <- data[order(data$year_num, data$month_num), ]
    data$month_label <- paste0(turkish_months[data$month_num], " ", data$year_num)

    highcharter::highchart() %>%
      highcharter::hc_chart(type = "column", backgroundColor = "transparent") %>%
      highcharter::hc_title(text = NULL) %>%
      highcharter::hc_xAxis(categories = data$month_label, labels = list(style = list(color = "#999"))) %>%
      highcharter::hc_yAxis_multiples(
        list(
          title = list(text = "Söyleşi Sayısı", style = list(color = "#3b82f6")),
          labels = list(style = list(color = "#999")), gridLineColor = "#444", min = 0
        ),
        list(
          title = list(text = "Benzersiz Kullanıcı", style = list(color = "#f59e0b")),
          labels = list(style = list(color = "#999")), opposite = TRUE, gridLineWidth = 0, min = 0
        )
      ) %>%
      highcharter::hc_plotOptions(column = list(borderWidth = 0)) %>%
      highcharter::hc_add_series(name = "Söyleşi", data = data$chat_count, color = "#3b82f6", yAxis = 0) %>%
      highcharter::hc_add_series(
        name = "Benzersiz Kullanıcı", data = data$unique_users, color = "#f59e0b",
        type = "spline", yAxis = 1, marker = list(enabled = TRUE)
      ) %>%
      highcharter::hc_tooltip(
        backgroundColor = "#1a1a1a", borderColor = "#333",
        style = list(color = "#fff"), shared = TRUE
      ) %>%
      highcharter::hc_legend(itemStyle = list(color = "#999")) %>%
      highcharter::hc_credits(enabled = FALSE)
  })
}
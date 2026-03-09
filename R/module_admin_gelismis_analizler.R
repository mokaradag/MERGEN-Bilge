# Dosya Yolu: R/module_admin_gelismis_analizler.R
# Açıklama: Yönetici paneli - Genel Analiz modülünün "Gelişmiş Analizler" sekmesi.
#            İlk yanıt beğeni oranı, bugünkü istatistikler, model kullanım trendi,
#            saatlere göre yanıt süresi, söyleşi uzunluğu ve model dağılımı.

# ==============================================================================
# GELİŞMİŞ ANALİZLER SEKMESİ - UI VE GRAFİKLER
# ==============================================================================

#' Gelişmiş Analizler sekmesinin UI içeriğini oluşturur
admin_advanced_analytics_ui <- function(data, ns, create_metric_card, create_info_button, format_number) {

  first_response_like <- "-"
  if (nrow(data$first_response_success) > 0) {
    frs <- data$first_response_success
    total <- frs$first_likes[1] + frs$first_dislikes[1]
    if (total > 0) {
      first_response_like <- sprintf("%.1f%%", (frs$first_likes[1] / total) * 100)
    }
  }

  today_chats <- if (nrow(data$today_stats) > 0 && !is.na(data$today_stats$chats_today[1])) data$today_stats$chats_today[1] else 0
  today_ai <- if (nrow(data$today_stats) > 0 && !is.na(data$today_stats$ai_calls_today[1])) data$today_stats$ai_calls_today[1] else 0
  today_avg <- if (nrow(data$today_stats) > 0 && !is.na(data$today_stats$avg_response_today[1]))
    sprintf("%.1f sn", data$today_stats$avg_response_today[1]) else "-"

  tagList(
    div(
      class = "metrics-grid metrics-grid-small",
      create_metric_card("İlk Yanıt Beğeni Oranı", first_response_like, "check-circle", "green",
        tooltip = "Her söyleşideki ilk YZ yanıtının beğenilme oranı."),
      create_metric_card("Bugünkü Söyleşi", format_number(today_chats), "comments", "blue",
        tooltip = "Bugün oluşturulan söyleşi sayısı."),
      create_metric_card("Bugünkü YZ Çağrısı", format_number(today_ai), "robot", "purple",
        tooltip = "Bugün yapılan YZ API çağrısı sayısı."),
      create_metric_card("Bugünkü Ortalama Yanıt", today_avg, "stopwatch", "orange",
        tooltip = "Bugünkü ortalama YZ yanıt süresi.")
    ),
    fluidRow(
      column(
        width = 12,
        div(
          class = "analytics-card",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("layer-group"), " Model Kullanım Trendi (Son 14 Gün)"),
            create_info_button("Son 14 gündeki model kullanım dağılımı.")
          ),
          highcharter::highchartOutput(ns("model_usage_trend_chart"), height = "320px")
        )
      )
    ),
    fluidRow(
      column(
        width = 12,
        div(
          class = "analytics-card",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("clock"), " Saatlere Göre Ortalama Yanıt Süresi"),
            create_info_button("Günün saatlerine göre ortalama YZ yanıt süresi.")
          ),
          highcharter::highchartOutput(ns("avg_response_by_hour_chart"), height = "320px")
        )
      )
    ),
    fluidRow(
      column(
        width = 6,
        div(
          class = "analytics-card",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("th"), " Söyleşi Uzunluğu Dağılımı"),
            create_info_button("Söyleşilerin mesaj sayısına göre dağılımı.")
          ),
          highcharter::highchartOutput(ns("chat_length_dist_chart"), height = "320px")
        )
      ),
      column(
        width = 6,
        div(
          class = "analytics-card",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("pie-chart"), " Model Dağılımı"),
            create_info_button("Kullanılan modellerin dağılımı.")
          ),
          highcharter::highchartOutput(ns("model_distribution_chart"), height = "320px")
        )
      )
    )
  )
}

#' Gelişmiş Analizler grafiklerini kaydeder
admin_advanced_analytics_outputs <- function(output, analytics_data_fn, format_turkish_date) {

  # Model kullanım trendi (çizgi grafik, çoklu seri)
  output$model_usage_trend_chart <- highcharter::renderHighchart({
    data <- analytics_data_fn()$model_usage_trend
    if (nrow(data) == 0) return(highcharter::highchart())

    models <- unique(data$ModelUsed)
    dates <- sort(unique(data$usage_date))
    date_labels <- sapply(dates, format_turkish_date)

    model_colors <- c("#60a5fa", "#a78bfa", "#34d399", "#22d3ee", "#f472b6", "#fbbf24", "#c084fc", "#f97316")

    series_list <- lapply(seq_along(models), function(idx) {
      m <- models[idx]
      model_data <- data[data$ModelUsed == m, ]
      counts <- sapply(dates, function(d) {
        row <- model_data[model_data$usage_date == d, ]
        if (nrow(row) > 0) row$cnt[1] else 0
      })
      list(name = m, data = as.list(counts), color = model_colors[((idx - 1) %% length(model_colors)) + 1])
    })

    hc <- highcharter::highchart() %>%
      highcharter::hc_chart(type = "spline", backgroundColor = "transparent") %>%
      highcharter::hc_title(text = NULL) %>%
      highcharter::hc_xAxis(categories = date_labels, labels = list(style = list(color = "#999"))) %>%
      highcharter::hc_yAxis(
        title = list(text = "Kullanım Sayısı", style = list(color = "#999")),
        labels = list(style = list(color = "#999")), gridLineColor = "#444"
      ) %>%
      highcharter::hc_plotOptions(
        spline = list(
          marker = list(enabled = TRUE, radius = 4), lineWidth = 3,
          states = list(hover = list(lineWidth = 3.5))
        )
      ) %>%
      highcharter::hc_tooltip(
        backgroundColor = "#1a1a1a", borderColor = "#333",
        style = list(color = "#fff"), shared = TRUE
      ) %>%
      highcharter::hc_legend(itemStyle = list(color = "#999")) %>%
      highcharter::hc_credits(enabled = FALSE)

    for (s in series_list) {
      hc <- hc %>% highcharter::hc_add_series(name = s$name, data = s$data, color = s$color)
    }
    hc
  })

  # Saatlere göre ortalama yanıt süresi (alan grafik)
  output$avg_response_by_hour_chart <- highcharter::renderHighchart({
    data <- analytics_data_fn()$avg_response_by_hour
    if (nrow(data) == 0) return(highcharter::highchart())

    data <- data[order(data$hour_num), ]
    data$avg_duration <- round(data$avg_duration, 2)

    highcharter::highchart() %>%
      highcharter::hc_chart(type = "areaspline", backgroundColor = "transparent") %>%
      highcharter::hc_title(text = NULL) %>%
      highcharter::hc_xAxis(
        categories = sprintf("%02d:00", data$hour_num),
        labels = list(style = list(color = "#999"), step = 2)
      ) %>%
      highcharter::hc_yAxis(
        title = list(text = "Ort. Yanıt Süresi (sn)", style = list(color = "#999")),
        labels = list(style = list(color = "#999")), gridLineColor = "#444"
      ) %>%
      highcharter::hc_plotOptions(
        areaspline = list(marker = list(enabled = TRUE, radius = 3), lineWidth = 2.5)
      ) %>%
      highcharter::hc_add_series(
        name = "Ort. Süre", data = data$avg_duration, color = "#f59e0b",
        fillColor = list(
          linearGradient = list(x1 = 0, y1 = 0, x2 = 0, y2 = 1),
          stops = list(list(0, "rgba(245, 158, 11, 0.3)"), list(1, "rgba(245, 158, 11, 0)"))
        )
      ) %>%
      highcharter::hc_tooltip(
        backgroundColor = "#1a1a1a", borderColor = "#333",
        style = list(color = "#fff"), valueSuffix = " sn"
      ) %>%
      highcharter::hc_legend(enabled = FALSE) %>%
      highcharter::hc_credits(enabled = FALSE)
  })

  # Söyleşi uzunluğu dağılımı (halka grafik)
  output$chat_length_dist_chart <- highcharter::renderHighchart({
    data <- analytics_data_fn()$chat_length_distribution
    if (nrow(data) == 0) return(highcharter::highchart())

    bucket_order <- c("1-2 mesaj", "3-5 mesaj", "6-10 mesaj", "11-20 mesaj", "20+ mesaj")
    data$length_bucket <- factor(data$length_bucket, levels = bucket_order)
    data <- data[order(data$length_bucket), ]
    data <- data[!is.na(data$length_bucket), ]

    if (nrow(data) == 0) return(highcharter::highchart())

    pie_colors <- c("#6366f1", "#22d3ee", "#a78bfa", "#f59e0b", "#f472b6")

    chart_data <- lapply(1:nrow(data), function(i) {
      list(name = as.character(data$length_bucket[i]), y = data$chat_count[i], color = pie_colors[i])
    })

    highcharter::highchart() %>%
      highcharter::hc_chart(type = "pie", backgroundColor = "transparent") %>%
      highcharter::hc_title(text = NULL) %>%
      highcharter::hc_plotOptions(
        pie = list(
          innerSize = "50%", borderWidth = 0,
          dataLabels = list(
            enabled = TRUE, format = "<b>{point.name}</b>: {point.percentage:.1f}%",
            style = list(color = "#fff", textOutline = "none")
          )
        )
      ) %>%
      highcharter::hc_add_series(name = "Söyleşi", data = chart_data) %>%
      highcharter::hc_tooltip(
        backgroundColor = "#1a1a1a", borderColor = "#333", style = list(color = "#fff"),
        pointFormat = "<b>{point.y}</b> söyleşi ({point.percentage:.1f}%)"
      ) %>%
      highcharter::hc_credits(enabled = FALSE)
  })

  # Model dağılımı (halka grafik)
  output$model_distribution_chart <- highcharter::renderHighchart({
    data <- analytics_data_fn()$model_performance
    if (nrow(data) == 0) return(highcharter::highchart())

    model_colors <- c("#60a5fa", "#a78bfa", "#34d399", "#22d3ee", "#f472b6", "#fbbf24", "#c084fc", "#f97316")

    chart_data <- lapply(1:nrow(data), function(i) {
      list(name = data$ModelUsed[i], y = data$total_count[i],
        color = model_colors[((i - 1) %% length(model_colors)) + 1])
    })

    highcharter::highchart() %>%
      highcharter::hc_chart(type = "pie", backgroundColor = "transparent") %>%
      highcharter::hc_title(text = NULL) %>%
      highcharter::hc_plotOptions(
        pie = list(
          innerSize = "50%", borderWidth = 0,
          dataLabels = list(
            enabled = TRUE, format = "<b>{point.name}</b>: {point.percentage:.1f}%",
            style = list(color = "#fff", textOutline = "none")
          )
        )
      ) %>%
      highcharter::hc_add_series(name = "Kullanım", data = chart_data) %>%
      highcharter::hc_tooltip(
        backgroundColor = "#1a1a1a", borderColor = "#333", style = list(color = "#fff"),
        pointFormat = "<b>{point.y}</b> çağrı ({point.percentage:.1f}%)"
      ) %>%
      highcharter::hc_credits(enabled = FALSE)
  })
}

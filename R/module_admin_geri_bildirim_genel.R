# Dosya Yolu: R/module_admin_geri_bildirim_genel.R
# Açıklama: Yönetici paneli - Genel Analiz modülünün "Geri Bildirim" sekmesi.
#            Beğeni/beğenmeme istatistikleri, model bazlı geri bildirim tablosu,
#            geri bildirim trendi, yanıt uzunluğu ve süresi analizi.

# ==============================================================================
# GERİ BİLDİRİM SEKMESİ (GENEL ANALİZ İÇİNDEKİ) - UI VE GRAFİKLER
# ==============================================================================

#' Geri Bildirim sekmesinin UI içeriğini oluşturur
admin_feedback_ui <- function(data, ns, create_metric_card, create_info_button, format_number) {

  like_count <- 0
  dislike_count <- 0
  if (nrow(data$feedback_summary) > 0) {
    like_count <- sum(data$feedback_summary$cnt[data$feedback_summary$FeedbackType == "like"])
    dislike_count <- sum(data$feedback_summary$cnt[data$feedback_summary$FeedbackType == "dislike"])
  }

  satisfaction <- "N/A"
  total_fb <- like_count + dislike_count
  if (total_fb > 0) {
    satisfaction <- sprintf("%.1f%%", (like_count / total_fb) * 100)
  }

  tagList(
    div(
      class = "metrics-grid-3",
      create_metric_card("Beğeni Sayısı", format_number(like_count), "thumbs-up", "green"),
      create_metric_card("Beğenmeme Sayısı", format_number(dislike_count), "thumbs-down", "red"),
      create_metric_card("Memnuniyet Oranı", satisfaction, "smile", "yellow")
    ),
    fluidRow(
      column(
        width = 12,
        div(
          class = "analytics-card",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("robot"), " Modellere Göre Geri Bildirim"),
            create_info_button("Her model için beğeni, beğenmeme sayıları ve toplam yanıt sayısı.")
          ),
          div(class = "table-container", DT::dataTableOutput(ns("model_feedback_table")))
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
            h4(class = "card-title", icon("chart-line"), " Geri Bildirim Eğilimi (30 Gün)"),
            create_info_button("Son 30 gündeki günlük beğeni/beğenmeme trendi.")
          ),
          highcharter::highchartOutput(ns("feedback_trend_chart"), height = "300px")
        )
      ),
      column(
        width = 6,
        div(
          class = "analytics-card",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("text-height"), " Yanıt Uzunluğu ve Geri Bildirim"),
            create_info_button("Yanıt uzunluğuna göre geri bildirim dağılımı.")
          ),
          highcharter::highchartOutput(ns("response_length_feedback_chart"), height = "300px")
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
            h4(class = "card-title", icon("stopwatch"), " Yanıt Süresi ve Geri Bildirim İlişkisi"),
            create_info_button("Yanıt süresine göre geri bildirim dağılımı.")
          ),
          highcharter::highchartOutput(ns("response_time_feedback_chart"), height = "300px")
        )
      ),
      column(
        width = 6,
        div(
          class = "analytics-card",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("thumbs-up"), " Geri Bildirim Dağılımı"),
            create_info_button("Beğeni ve beğenmeme dağılımını gösterir.")
          ),
          highcharter::highchartOutput(ns("feedback_donut_chart"), height = "300px")
        )
      )
    )
  )
}

#' Geri Bildirim grafiklerini ve tablolarını kaydeder
admin_feedback_outputs <- function(output, analytics_data_fn, turkish_dt_language, format_turkish_date) {

  # Model geri bildirim tablosu
  output$model_feedback_table <- DT::renderDataTable({
    data <- analytics_data_fn()$model_feedback
    if (nrow(data) == 0) return(DT::datatable(data.frame()))

    data$row_num <- 1:nrow(data)
    data$like_rate <- round(ifelse(data$total_responses > 0, (data$likes / data$total_responses) * 100, 0), 1)
    data$dislike_rate <- round(ifelse(data$total_responses > 0, (data$dislikes / data$total_responses) * 100, 0), 1)
    display_data <- data[, c("row_num", "ModelUsed", "likes", "dislikes", "total_responses", "like_rate", "dislike_rate")]
    colnames(display_data) <- c("#", "Model", "Beğeni", "Beğenmeme", "Toplam Yanıt", "Beğeni Oranı (%)", "Beğenmeme Oranı (%)")

    DT::datatable(
      display_data,
      options = list(
        dom = 'ftp', pageLength = 10,
        ordering = TRUE, order = list(list(4, 'desc')),
        language = turkish_dt_language,
        columnDefs = list(
          list(className = 'dt-center', targets = c(0, 2, 3, 4, 5, 6)),
          list(className = 'row-number-col', targets = 0),
          list(width = '40px', targets = 0),
          list(orderable = FALSE, targets = 0)
        ),
        headerCallback = admin_dt_header_callback
      ),
      class = "admin-datatable", rownames = FALSE
    )
  })

  # Geri bildirim gruplu sütun grafik yardımcısı
  gruplu_sutun_grafik <- function(data, kategori_sutunu, bucket_order) {
    data[[kategori_sutunu]] <- factor(data[[kategori_sutunu]], levels = bucket_order)
    data <- data[order(data[[kategori_sutunu]]), ]
    data <- data[!is.na(data[[kategori_sutunu]]), ]
    if (nrow(data) == 0) return(highcharter::highchart())

    highcharter::highchart() %>%
      highcharter::hc_chart(type = "column", backgroundColor = "transparent") %>%
      highcharter::hc_title(text = NULL) %>%
      highcharter::hc_xAxis(
        categories = as.character(data[[kategori_sutunu]]),
        labels = list(style = list(color = "#999"))
      ) %>%
      highcharter::hc_yAxis(
        title = list(text = "Geri Bildirim Sayısı", style = list(color = "#999")),
        labels = list(style = list(color = "#999")), gridLineColor = "#444"
      ) %>%
      highcharter::hc_plotOptions(column = list(borderWidth = 0)) %>%
      highcharter::hc_add_series(name = "Beğeni", data = data$likes, color = "#10b981") %>%
      highcharter::hc_add_series(name = "Beğenmeme", data = data$dislikes, color = "#ef4444") %>%
      highcharter::hc_tooltip(
        backgroundColor = "#1a1a1a", borderColor = "#333",
        style = list(color = "#fff"), shared = TRUE
      ) %>%
      highcharter::hc_legend(itemStyle = list(color = "#999")) %>%
      highcharter::hc_credits(enabled = FALSE)
  }

  # Yanıt süresi ve geri bildirim ilişkisi
  output$response_time_feedback_chart <- highcharter::renderHighchart({
    data <- analytics_data_fn()$response_time_feedback
    if (nrow(data) == 0) return(highcharter::highchart())
    gruplu_sutun_grafik(data, "duration_bucket", c("0-5 sn", "5-10 sn", "10-20 sn", "20+ sn"))
  })

  # Yanıt uzunluğu ve geri bildirim
  output$response_length_feedback_chart <- highcharter::renderHighchart({
    data <- analytics_data_fn()$response_length_feedback
    if (nrow(data) == 0) return(highcharter::highchart())
    gruplu_sutun_grafik(data, "length_bucket", c("Kısa (< 500)", "Orta (500-1500)", "Uzun (1500-3000)", "Çok Uzun (> 3000)"))
  })

  # Geri bildirim eğilimi (30 gün, alan grafik)
  output$feedback_trend_chart <- highcharter::renderHighchart({
    data <- analytics_data_fn()$feedback_trend
    if (nrow(data) == 0) return(highcharter::highchart())

    data <- data[order(data$feedback_date), ]
    data$date_label <- sapply(data$feedback_date, format_turkish_date)

    highcharter::highchart() %>%
      highcharter::hc_chart(type = "areaspline", backgroundColor = "transparent") %>%
      highcharter::hc_title(text = NULL) %>%
      highcharter::hc_xAxis(categories = data$date_label, labels = list(style = list(color = "#999"))) %>%
      highcharter::hc_yAxis(
        title = list(text = "Geri Bildirim Sayısı", style = list(color = "#999")),
        labels = list(style = list(color = "#999")), gridLineColor = "#444"
      ) %>%
      highcharter::hc_plotOptions(areaspline = list(marker = list(enabled = FALSE), lineWidth = 2)) %>%
      highcharter::hc_add_series(
        name = "Beğeni", data = data$likes, color = "#10b981",
        fillColor = list(
          linearGradient = list(x1 = 0, y1 = 0, x2 = 0, y2 = 1),
          stops = list(list(0, "rgba(16, 185, 129, 0.2)"), list(1, "rgba(16, 185, 129, 0)"))
        )
      ) %>%
      highcharter::hc_add_series(
        name = "Beğenmeme", data = data$dislikes, color = "#ef4444",
        fillColor = list(
          linearGradient = list(x1 = 0, y1 = 0, x2 = 0, y2 = 1),
          stops = list(list(0, "rgba(239, 68, 68, 0.2)"), list(1, "rgba(239, 68, 68, 0)"))
        )
      ) %>%
      highcharter::hc_tooltip(
        backgroundColor = "#1a1a1a", borderColor = "#333",
        style = list(color = "#fff"), shared = TRUE
      ) %>%
      highcharter::hc_legend(itemStyle = list(color = "#999")) %>%
      highcharter::hc_credits(enabled = FALSE)
  })
}
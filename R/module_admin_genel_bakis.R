# Dosya Yolu: R/module_admin_genel_bakis.R
# Açıklama: Yönetici paneli - Genel Analiz modülünün "Genel Bakış" sekmesi.
#            Temel sistem metrikleri, günlük söyleşi trendi ve geri bildirim
#            dağılımı grafiklerini içerir.

# ==============================================================================
# GENEL BAKIŞ SEKMESİ - UI VE GRAFİKLER
# ==============================================================================

#' Genel Bakış sekmesinin UI içeriğini oluşturur
#' @param data analytics_data() reaktif verisinden gelen liste
#' @param ns Modül namespace fonksiyonu
#' @param create_metric_card Metrik kart oluşturucu fonksiyon
#' @param create_info_button Bilgi butonu oluşturucu fonksiyon
#' @param format_number Sayı formatlama fonksiyonu
admin_overview_ui <- function(data, ns, create_metric_card, create_info_button, format_number) {

  total_users <- if (nrow(data$total_users) > 0) data$total_users$cnt[1] else 0
  total_chats <- if (nrow(data$total_chats) > 0) data$total_chats$cnt[1] else 0
  total_messages <- if (nrow(data$total_messages) > 0) data$total_messages$cnt[1] else 0
  total_ai_calls <- if (nrow(data$total_ai_calls) > 0) data$total_ai_calls$cnt[1] else 0
  avg_response <- if (nrow(data$avg_response_time) > 0 && !is.na(data$avg_response_time$avg_dur[1]))
    sprintf("%.1f sn", data$avg_response_time$avg_dur[1]) else "N/A"
  error_rate <- if (nrow(data$error_rate) > 0 && !is.na(data$error_rate$rate[1]))
    sprintf("%.1f%%", data$error_rate$rate[1]) else "0%"
  active_today <- if (nrow(data$active_users_today) > 0) data$active_users_today$cnt[1] else 0
  avg_chat_len <- if (nrow(data$avg_chat_length) > 0 && !is.na(data$avg_chat_length$avg_len[1]))
    sprintf("%.1f", data$avg_chat_length$avg_len[1]) else "N/A"

  tagList(
    div(
      class = "metrics-grid",
      create_metric_card("Toplam Kullanıcı", format_number(total_users), "users", "blue",
        tooltip = "Sistemde kayıtlı olan tüm benzersiz kullanıcıların toplam sayısı."),
      create_metric_card("Bugün Aktif", format_number(active_today), "user-clock", "green",
        tooltip = "Bugün en az bir söyleşi başlatan veya YZ çağrısı yapan kullanıcı sayısı."),
      create_metric_card("Toplam Söyleşi", format_number(total_chats), "comments", "purple",
        tooltip = "Sistemde oluşturulan tüm söyleşi oturumlarının toplam sayısı."),
      create_metric_card("Toplam Mesaj", format_number(total_messages), "envelope", "orange",
        tooltip = "Kullanıcı ve YZ mesajları dahil tüm mesajların sayısı."),
      create_metric_card("YZ Çağrısı", format_number(total_ai_calls), "robot", "cyan",
        tooltip = "Yapay zeka API'sine yapılan toplam çağrı sayısı."),
      create_metric_card("Ortalama Yanıt Süresi", avg_response, "stopwatch", "yellow",
        tooltip = "Başarılı YZ yanıtlarının ortalama üretim süresi."),
      create_metric_card("Hata Oranı", error_rate, "exclamation-triangle", "red",
        tooltip = "Başarısız YZ çağrılarının toplam çağrılara oranı."),
      create_metric_card("Ortalama Mesaj/Söyleşi", avg_chat_len, "chart-bar", "teal",
        tooltip = "Her söyleşideki ortalama mesaj sayısı.")
    ),
    fluidRow(
      column(
        width = 8,
        div(
          class = "analytics-card",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("chart-area"), " Son 30 Günlük Söyleşi Eğilimi"),
            create_info_button("Son 30 gündeki günlük söyleşi sayılarının eğilimi.")
          ),
          highcharter::highchartOutput(ns("daily_trend_chart"), height = "300px")
        )
      ),
      column(
        width = 4,
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

#' Genel Bakış grafiklerini (output) kaydeder
#' @param output Shiny output nesnesi
#' @param analytics_data_fn analytics_data reaktif fonksiyonu
#' @param format_turkish_date Türkçe tarih formatlama fonksiyonu
admin_overview_outputs <- function(output, analytics_data_fn, format_turkish_date) {

  # Günlük söyleşi trendi (areaspline grafik)
  output$daily_trend_chart <- highcharter::renderHighchart({
    data <- analytics_data_fn()$daily_trend
    if (nrow(data) == 0) return(highcharter::highchart())

    data$date_label <- sapply(data$chat_date, format_turkish_date)

    highcharter::highchart() %>%
      highcharter::hc_chart(type = "areaspline", backgroundColor = "transparent") %>%
      highcharter::hc_title(text = NULL) %>%
      highcharter::hc_xAxis(
        categories = data$date_label,
        labels = list(style = list(color = "#999"))
      ) %>%
      highcharter::hc_yAxis(
        title = list(text = "Söyleşi Sayısı", style = list(color = "#999")),
        labels = list(style = list(color = "#999")),
        gridLineColor = "#444"
      ) %>%
      highcharter::hc_plotOptions(
        areaspline = list(marker = list(enabled = FALSE), lineWidth = 2.5)
      ) %>%
      highcharter::hc_add_series(
        name = "Söyleşi", data = data$chat_count, color = "#ff6b35",
        fillColor = list(
          linearGradient = list(x1 = 0, y1 = 0, x2 = 0, y2 = 1),
          stops = list(list(0, "rgba(255, 107, 53, 0.3)"), list(1, "rgba(255, 107, 53, 0)"))
        )
      ) %>%
      highcharter::hc_tooltip(backgroundColor = "#1a1a1a", borderColor = "#333", style = list(color = "#fff")) %>%
      highcharter::hc_legend(enabled = FALSE) %>%
      highcharter::hc_credits(enabled = FALSE)
  })

  # Geri bildirim dağılımı (halka grafik)
  output$feedback_donut_chart <- highcharter::renderHighchart({
    data <- analytics_data_fn()$feedback_summary
    if (nrow(data) == 0) return(highcharter::highchart())

    data$label <- ifelse(data$FeedbackType == "like", "Beğeni", "Beğenmeme")

    chart_data <- lapply(1:nrow(data), function(i) {
      list(
        name = data$label[i], y = data$cnt[i],
        color = if (data$FeedbackType[i] == "like") "#10b981" else "#ef4444"
      )
    })

    highcharter::highchart() %>%
      highcharter::hc_chart(type = "pie", backgroundColor = "transparent") %>%
      highcharter::hc_title(text = NULL) %>%
      highcharter::hc_plotOptions(
        pie = list(
          innerSize = "60%", borderWidth = 0,
          dataLabels = list(
            enabled = TRUE, format = "<b>{point.name}</b>: {point.y}",
            style = list(color = "#fff", textOutline = "none")
          )
        )
      ) %>%
      highcharter::hc_add_series(name = "Geri Bildirim", data = chart_data) %>%
      highcharter::hc_tooltip(backgroundColor = "#1a1a1a", borderColor = "#333", style = list(color = "#fff")) %>%
      highcharter::hc_credits(enabled = FALSE)
  })
}
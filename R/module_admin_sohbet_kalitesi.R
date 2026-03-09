# Dosya Yolu: R/module_admin_sohbet_kalitesi.R
# Açıklama: Yönetici paneli - Genel Analiz modülünün "Sohbet Kalitesi" sekmesi.
#            Hemen çıkma oranı, kullanıcı tutma oranı, kodlu/kodsuz yanıtlar,
#            en uzun söyleşiler ve yeniden oluşturulan yanıtlar analizi.

# ==============================================================================
# SOHBET KALİTESİ SEKMESİ - UI VE GRAFİKLER
# ==============================================================================

#' Sohbet Kalitesi sekmesinin UI içeriğini oluşturur
admin_chat_quality_ui <- function(data, ns, create_metric_card, create_info_button, format_number) {

  bounce_rate <- if (nrow(data$bounce_rate) > 0 && !is.na(data$bounce_rate$bounce_rate[1]))
    sprintf("%.1f%%", data$bounce_rate$bounce_rate[1]) else "N/A"

  avg_msg <- if (nrow(data$avg_messages_per_chat) > 0 && !is.na(data$avg_messages_per_chat$avg_msg[1]))
    sprintf("%.1f", data$avg_messages_per_chat$avg_msg[1]) else "N/A"

  retention_rate <- "N/A"
  if (nrow(data$user_retention) > 0) {
    ret <- data$user_retention
    if (!is.na(ret$returning_users[1]) && !is.na(ret$total_users[1]) && ret$total_users[1] > 0) {
      retention_rate <- sprintf("%.1f%%", (ret$returning_users[1] / ret$total_users[1]) * 100)
    }
  }

  avg_session <- if (nrow(data$avg_session_duration) > 0 && !is.na(data$avg_session_duration$avg_duration[1]))
    sprintf("%.0f dk", data$avg_session_duration$avg_duration[1]) else "N/A"

  total_feedback <- if (nrow(data$total_feedback_count) > 0) data$total_feedback_count$cnt[1] else 0

  tagList(
    div(
      class = "metrics-grid-5",
      create_metric_card("Hemen Çıkma Oranı", bounce_rate, "door-open", "red",
        tooltip = "2 veya daha az mesaj içeren söyleşilerin oranı."),
      create_metric_card("Ortalama Mesaj/Söyleşi", avg_msg, "comment-dots", "blue",
        tooltip = "Her söyleşideki ortalama mesaj sayısı."),
      create_metric_card("Kullanıcı Tutma Oranı", retention_rate, "user-check", "green",
        tooltip = "Birden fazla söyleşi başlatan kullanıcıların oranı."),
      create_metric_card("Ortalama Oturum Süresi", avg_session, "hourglass-half", "orange",
        tooltip = "Söyleşilerin ortalama süre uzunluğu."),
      create_metric_card("Toplam Geri Bildirim", format_number(total_feedback), "comments", "purple",
        tooltip = "Verilen tüm geri bildirimlerin sayısı.")
    ),
    fluidRow(
      class = "equal-height-row",
      column(
        width = 4,
        div(
          class = "analytics-card", style = "min-height: 420px;",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("code"), " Kodlu ve Kodsuz Yanıtlar"),
            create_info_button("YZ yanıtlarının kod içerip içermediğine göre dağılımı.")
          ),
          highcharter::highchartOutput(ns("code_ratio_chart"), height = "350px")
        )
      ),
      column(
        width = 8,
        div(
          class = "analytics-card", style = "min-height: 420px;",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("list-ol"), " En Uzun Söyleşiler"),
            create_info_button("En fazla mesaj içeren söyleşiler.")
          ),
          div(class = "table-container scrollable-table-equal", DT::dataTableOutput(ns("longest_chats_table")))
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
            h4(class = "card-title", icon("redo"), " En Çok Yeniden Oluşturulan Yanıtlar"),
            create_info_button("Birden fazla YZ yanıtı içeren söyleşiler (yeniden oluşturma göstergesi).")
          ),
          div(class = "table-container", DT::dataTableOutput(ns("regenerated_table")))
        )
      )
    )
  )
}

#' Sohbet Kalitesi grafiklerini ve tablolarını kaydeder
admin_chat_quality_outputs <- function(output, analytics_data_fn, turkish_dt_language) {

  # Kodlu/kodsuz yanıt dağılımı (halka grafik)
  output$code_ratio_chart <- highcharter::renderHighchart({
    data <- analytics_data_fn()$code_ratio
    if (nrow(data) == 0) return(highcharter::highchart())

    chart_data <- lapply(1:nrow(data), function(i) {
      list(name = data$has_code[i], y = data$cnt[i],
        color = if (data$has_code[i] == "Kodlu") "#8b5cf6" else "#64748b")
    })

    highcharter::highchart() %>%
      highcharter::hc_chart(type = "pie", backgroundColor = "transparent") %>%
      highcharter::hc_title(text = NULL) %>%
      highcharter::hc_plotOptions(
        pie = list(
          innerSize = "70%", borderWidth = 0,
          dataLabels = list(
            enabled = TRUE, format = "<b>{point.name}</b>: {point.percentage:.1f}%",
            style = list(color = "#fff", textOutline = "none")
          )
        )
      ) %>%
      highcharter::hc_add_series(name = "Yanıt", data = chart_data) %>%
      highcharter::hc_tooltip(
        backgroundColor = "#1a1a1a", borderColor = "#333", style = list(color = "#fff"),
        pointFormat = "<b>{point.y}</b> yanıt ({point.percentage:.1f}%)"
      ) %>%
      highcharter::hc_credits(enabled = FALSE)
  })

  # En uzun söyleşiler tablosu
  output$longest_chats_table <- DT::renderDataTable({
    data <- analytics_data_fn()$longest_chats
    if (nrow(data) == 0) return(DT::datatable(data.frame()))

    data$row_num <- 1:nrow(data)
    data$display_name <- ifelse(!is.na(data$full_name) & nzchar(data$full_name), data$full_name, data$user_name)
    display_data <- data[, c("row_num", "ChatTitle", "msg_count", "display_name")]
    colnames(display_data) <- c("#", "Söyleşi Başlığı", "Mesaj", "Kullanıcı")

    DT::datatable(
      display_data,
      options = list(
        dom = 't', pageLength = 20, scrollY = FALSE,
        ordering = TRUE, order = list(list(2, 'desc')),
        language = turkish_dt_language,
        columnDefs = list(
          list(className = 'dt-center', targets = c(0, 2)),
          list(className = 'row-number-col', targets = 0),
          list(width = '40px', targets = 0),
          list(orderable = FALSE, targets = 0)
        ),
        headerCallback = admin_dt_header_callback
      ),
      class = "admin-datatable", rownames = FALSE
    )
  })

  # Yeniden oluşturulan yanıtlar tablosu
  output$regenerated_table <- DT::renderDataTable({
    data <- analytics_data_fn()$regenerated_responses
    if (nrow(data) == 0) return(DT::datatable(data.frame()))

    data$regen_count <- pmax(data$ai_count - data$user_count, 0)
    data <- data[order(-data$regen_count), ]
    data <- head(data, 20)
    data$row_num <- 1:nrow(data)

    display_data <- data[, c("row_num", "ChatTitle", "user_name", "ai_count", "user_count", "regen_count")]
    colnames(display_data) <- c("#", "Söyleşi Başlığı", "Kullanıcı", "YZ Yanıt", "Kullanıcı Mesaj", "Yeniden Oluşturma")

    DT::datatable(
      display_data,
      options = list(
        dom = 't', pageLength = 20,
        scrollY = "250px", scrollCollapse = TRUE,
        ordering = TRUE, order = list(list(5, 'desc')),
        language = turkish_dt_language,
        columnDefs = list(
          list(className = 'dt-center', targets = c(0, 3, 4, 5)),
          list(className = 'row-number-col', targets = 0),
          list(width = '40px', targets = 0),
          list(orderable = FALSE, targets = 0)
        ),
        headerCallback = admin_dt_header_callback
      ),
      class = "admin-datatable", rownames = FALSE
    )
  })
}
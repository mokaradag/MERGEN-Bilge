# Dosya Yolu: R/module_admin_kullanici_analizi.R
# Açıklama: Yönetici paneli - Genel Analiz modülünün "Kullanıcı Analizi" sekmesi.
#            En aktif kullanıcılar, güçlü kullanıcılar, günlere/saatlere göre
#            kullanım dağılımı ve dosya yükleyenler analizi.

# ==============================================================================
# KULLANICI ANALİZİ SEKMESİ - UI VE GRAFİKLER
# ==============================================================================

#' Kullanıcı Analizi sekmesinin UI içeriğini oluşturur
admin_users_ui <- function(ns, create_info_button) {
  tagList(
    fluidRow(
      class = "equal-height-row",
      column(
        width = 4,
        div(
          class = "analytics-card", style = "min-height: 420px;",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("trophy"), " En Aktif Kullanıcılar"),
            create_info_button("En fazla mesaj gönderen kullanıcılar.")
          ),
          highcharter::highchartOutput(ns("top_users_chart"), height = "350px")
        )
      ),
      column(
        width = 8,
        div(
          class = "analytics-card", style = "min-height: 420px;",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("star"), " Güçlü Kullanıcılar"),
            create_info_button("En yoğun sistem kullanıcıları.")
          ),
          div(class = "table-container scrollable-table-equal", DT::DTOutput(ns("power_users_table")))
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
            h4(class = "card-title", icon("calendar-week"), " Günlere Göre Kullanım"),
            create_info_button("Haftanın günlerine göre söyleşi dağılımı (Pazartesi'den başlar).")
          ),
          highcharter::highchartOutput(ns("usage_by_day_chart"), height = "300px")
        )
      ),
      column(
        width = 6,
        div(
          class = "analytics-card",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("clock"), " Saatlere Göre Kullanım"),
            create_info_button("Günün saatlerine göre söyleşi dağılımı (00:00-23:00).")
          ),
          highcharter::highchartOutput(ns("usage_by_hour_chart"), height = "300px")
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
            h4(class = "card-title", icon("upload"), " Dosya Yükleyenler"),
            create_info_button("En fazla dosya yükleyen kullanıcıların listesi.")
          ),
          div(class = "table-container", DT::DTOutput(ns("file_uploaders_table")))
        )
      )
    )
  )
}

#' Kullanıcı Analizi grafiklerini ve tablolarını kaydeder
admin_users_outputs <- function(output, analytics_data_fn, turkish_dt_language, turkish_days) {

  # En aktif kullanıcılar (yatay çubuk grafik)
  output$top_users_chart <- highcharter::renderHighchart({
    data <- analytics_data_fn()$top_users
    if (nrow(data) == 0) return(highcharter::highchart())

    data <- data[order(-data$message_count), ]
    display_names <- data$user_name

    chart_data <- lapply(1:nrow(data), function(i) {
      list(
        y = data$message_count[i],
        full_name = if (!is.na(data$full_name[i]) && nzchar(data$full_name[i])) data$full_name[i] else data$user_name[i],
        user_name = data$user_name[i]
      )
    })

    highcharter::highchart() %>%
      highcharter::hc_chart(type = "bar", backgroundColor = "transparent") %>%
      highcharter::hc_title(text = NULL) %>%
      highcharter::hc_xAxis(
        categories = as.list(display_names),
        labels = list(style = list(color = "#999"), formatter = JS("function() { return this.value; }"))
      ) %>%
      highcharter::hc_yAxis(
        title = list(text = "Mesaj Sayısı", style = list(color = "#999")),
        labels = list(style = list(color = "#999")), gridLineColor = "#444"
      ) %>%
      highcharter::hc_plotOptions(bar = list(borderWidth = 0, colorByPoint = TRUE)) %>%
      highcharter::hc_add_series(
        name = "Mesaj", data = chart_data,
        colors = c("#6366f1", "#8b5cf6", "#a855f7", "#d946ef", "#ec4899",
                   "#f43f5e", "#ef4444", "#f97316", "#f59e0b", "#eab308")
      ) %>%
      highcharter::hc_tooltip(
        backgroundColor = "#1a1a1a", borderColor = "#333", style = list(color = "#fff"),
        formatter = JS("function() { return '<b>' + this.point.full_name + '</b><br/>Mesaj: ' + this.y; }")
      ) %>%
      highcharter::hc_legend(enabled = FALSE) %>%
      highcharter::hc_credits(enabled = FALSE)
  })

  # Güçlü kullanıcılar tablosu
  output$power_users_table <- DT::renderDT({
    data <- analytics_data_fn()$power_users
    if (nrow(data) == 0) return(DT::datatable(data.frame()))

    data$row_num <- 1:nrow(data)
    data$avg_chat_length <- round(data$avg_chat_length, 1)
    data$display_name <- ifelse(!is.na(data$full_name) & nzchar(data$full_name), data$full_name, data$user_name)
    display_data <- data[, c("row_num", "display_name", "chat_count", "total_messages", "avg_chat_length")]
    colnames(display_data) <- c("#", "Kullanıcı", "Söyleşi", "Mesaj", "Ort. Uzunluk")

    DT::datatable(
      display_data,
      options = list(
        dom = 't', pageLength = 20, scrollY = FALSE,
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

  # Günlere göre kullanım (sütun grafik)
  output$usage_by_day_chart <- highcharter::renderHighchart({
    data <- analytics_data_fn()$usage_by_day
    if (nrow(data) == 0) return(highcharter::highchart())

    day_mapping <- data.frame(sql_day = 1:7, monday_start = c(7, 1, 2, 3, 4, 5, 6), stringsAsFactors = FALSE)
    data <- merge(data, day_mapping, by.x = "day_num", by.y = "sql_day", all.x = TRUE)
    data <- data[order(data$monday_start), ]
    day_labels <- turkish_days[data$monday_start]

    highcharter::highchart() %>%
      highcharter::hc_chart(type = "column", backgroundColor = "transparent") %>%
      highcharter::hc_title(text = NULL) %>%
      highcharter::hc_xAxis(categories = day_labels, labels = list(style = list(color = "#999"))) %>%
      highcharter::hc_yAxis(
        title = list(text = "Söyleşi Sayısı", style = list(color = "#999")),
        labels = list(style = list(color = "#999")), gridLineColor = "#444"
      ) %>%
      highcharter::hc_plotOptions(column = list(borderWidth = 0, borderRadius = 4, colorByPoint = TRUE)) %>%
      highcharter::hc_add_series(
        name = "Söyleşi", data = data$cnt,
        colors = c("#6366f1", "#8b5cf6", "#a855f7", "#d946ef", "#ec4899", "#f43f5e", "#ef4444")
      ) %>%
      highcharter::hc_tooltip(backgroundColor = "#1a1a1a", borderColor = "#333", style = list(color = "#fff")) %>%
      highcharter::hc_legend(enabled = FALSE) %>%
      highcharter::hc_credits(enabled = FALSE)
  })

  # Saatlere göre kullanım (alan grafik)
  output$usage_by_hour_chart <- highcharter::renderHighchart({
    data <- analytics_data_fn()$usage_by_hour
    if (nrow(data) == 0) return(highcharter::highchart())

    data <- data[order(data$hour_num), ]

    highcharter::highchart() %>%
      highcharter::hc_chart(type = "areaspline", backgroundColor = "transparent") %>%
      highcharter::hc_title(text = NULL) %>%
      highcharter::hc_xAxis(
        categories = sprintf("%02d:00", data$hour_num),
        labels = list(style = list(color = "#999"), step = 2)
      ) %>%
      highcharter::hc_yAxis(
        title = list(text = "Söyleşi Sayısı", style = list(color = "#999")),
        labels = list(style = list(color = "#999")), gridLineColor = "#444"
      ) %>%
      highcharter::hc_plotOptions(areaspline = list(marker = list(enabled = FALSE), lineWidth = 2.5)) %>%
      highcharter::hc_add_series(
        name = "Söyleşi", data = data$cnt, color = "#06b6d4",
        fillColor = list(
          linearGradient = list(x1 = 0, y1 = 0, x2 = 0, y2 = 1),
          stops = list(list(0, "rgba(6, 182, 212, 0.3)"), list(1, "rgba(6, 182, 212, 0)"))
        )
      ) %>%
      highcharter::hc_tooltip(backgroundColor = "#1a1a1a", borderColor = "#333", style = list(color = "#fff")) %>%
      highcharter::hc_legend(enabled = FALSE) %>%
      highcharter::hc_credits(enabled = FALSE)
  })

  # Dosya yükleyenler tablosu
  output$file_uploaders_table <- DT::renderDT({
    data <- analytics_data_fn()$file_uploaders
    if (nrow(data) == 0) return(DT::datatable(data.frame()))

    data$row_num <- 1:nrow(data)
    data$last_upload <- format(as.POSIXct(data$last_upload), "%d.%m.%Y %H:%M")
    display_data <- data[, c("row_num", "user_name", "full_name", "file_count", "last_upload")]
    colnames(display_data) <- c("#", "Kullanıcı Adı", "Tam Ad", "Dosya Sayısı", "Son Yükleme")

    DT::datatable(
      display_data,
      options = list(
        dom = 'ftp', pageLength = 10,
        ordering = TRUE, order = list(list(3, 'desc')),
        language = turkish_dt_language,
        columnDefs = list(
          list(className = 'dt-center', targets = c(0, 3, 4)),
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
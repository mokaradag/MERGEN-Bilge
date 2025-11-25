# R/module_admin_analytics.R

adminAnalyticsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$head(
      tags$link(rel = "stylesheet", type = "text/css", href = "css/admin_analytics.css")
    ),
    div(
      class = "admin-analytics-container",
      fluidRow(
        column(
          width = 12,
          div(
            class = "chat-header settings-header-fixed",
            div(
              class = "chat-header-left",
              h4("Yönetici Paneli", class = "page-title"),
              span(class = "admin-badge", icon("shield-alt"), "ADMIN")
            ),
            div(
              class = "chat-header-right",
              span(id = ns("admin_last_update"),
                   style = "color: #999; margin-right: 15px; font-size: 14px;",
                   "Son Güncelleme: --"),
              actionButton(
                ns("refresh_analytics"),
                label = tagList(icon("sync-alt"), "Yenile"),
                class = "btn-modern btn-primary"
              )
            )
          )
        )
      ),
      div(
        class = "settings-scrollable-content admin-scrollable",
        div(
          class = "admin-tabs-container",
          tabsetPanel(
            id = ns("admin_tabs"),
            type = "pills",
            tabPanel(
              title = tagList(icon("chart-line"), " Genel Bakış"),
              value = "overview",
              div(class = "tab-content-wrapper", uiOutput(ns("overview_content")))
            ),
            tabPanel(
              title = tagList(icon("users"), " Kullanıcı Analizi"),
              value = "users",
              div(class = "tab-content-wrapper", uiOutput(ns("users_content")))
            ),
            tabPanel(
              title = tagList(icon("robot"), " YZ Performansı"),
              value = "ai_perf",
              div(class = "tab-content-wrapper", uiOutput(ns("ai_perf_content")))
            ),
            tabPanel(
              title = tagList(icon("thumbs-up"), " Geri Bildirim"),
              value = "feedback",
              div(class = "tab-content-wrapper", uiOutput(ns("feedback_content")))
            ),
            tabPanel(
              title = tagList(icon("comments"), " Sohbet Kalitesi"),
              value = "chat_quality",
              div(class = "tab-content-wrapper", uiOutput(ns("chat_quality_content")))
            ),
            tabPanel(
              title = tagList(icon("clock"), " Zaman Analizi"),
              value = "time_analysis",
              div(class = "tab-content-wrapper", uiOutput(ns("time_analysis_content")))
            )
          )
        )
      )
    )
  )
}

adminAnalyticsServer <- function(id, pool = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    
    analytics_refresh_trigger <- reactiveVal(0)
    analytics_last_update <- reactiveVal(format(Sys.time(), "%d.%m.%Y %H:%M:%S"))
    
    observe({
      invalidateLater(60000)
      isolate({
        analytics_refresh_trigger(analytics_refresh_trigger() + 1)
        analytics_last_update(format(Sys.time(), "%d.%m.%Y %H:%M:%S"))
        session$sendCustomMessage("updateAdminTimestamp", list(
          id = ns("admin_last_update"),
          time = analytics_last_update()
        ))
      })
    })
    
    observeEvent(input$refresh_analytics, {
      analytics_refresh_trigger(analytics_refresh_trigger() + 1)
      analytics_last_update(format(Sys.time(), "%d.%m.%Y %H:%M:%S"))
      session$sendCustomMessage("updateAdminTimestamp", list(
        id = ns("admin_last_update"),
        time = analytics_last_update()
      ))
      showToast(session, "Veriler güncellendi", "success")
    })
    
	safe_query <- function(query) {
      tryCatch({
        conn_info <- get_connection()
        on.exit(release_connection(conn_info))
        DBI::dbGetQuery(conn_info$conn, query)
      }, error = function(e) {
        log_error("[ADMIN] SQL Error: {conditionMessage(e)}")
        data.frame()
      })
    }
    
    analytics_data <- reactive({
      analytics_refresh_trigger()
      
      list(
        total_users = safe_query("SELECT COUNT(DISTINCT UserID) as cnt FROM MB_Users"),
        total_chats = safe_query("SELECT COUNT(*) as cnt FROM MB_Chats WHERE IsDeleted = 0"),
        total_messages = safe_query("SELECT COUNT(*) as cnt FROM MB_Messages"),
        total_ai_calls = safe_query("SELECT COUNT(*) as cnt FROM MB_Usage_Log"),
        avg_response_time = safe_query("SELECT AVG(ResponseDuration) as avg_dur FROM MB_Usage_Log WHERE ResponseSuccess = 1"),
        error_rate = safe_query("
          SELECT 
            CAST(SUM(CASE WHEN ResponseSuccess = 0 THEN 1 ELSE 0 END) AS FLOAT) / NULLIF(COUNT(*), 0) * 100 as rate
          FROM MB_Usage_Log
        "),
        feedback_summary = safe_query("
          SELECT FeedbackType, COUNT(*) as cnt 
          FROM MB_Feedback 
          GROUP BY FeedbackType
        "),
        active_users_today = safe_query("
          SELECT COUNT(DISTINCT UserID) as cnt 
          FROM MB_Chats 
          WHERE CAST(CreateTimestamp AS DATE) = CAST(GETDATE() AS DATE) AND IsDeleted = 0
        "),
        top_users = safe_query("
          SELECT TOP 10 
            u.KaynakAdi as user_name,
            COUNT(m.MessageID) as message_count
          FROM MB_Messages m
          JOIN MB_Chats c ON m.ChatID = c.ChatID
          JOIN MB_Users u ON c.UserID = u.UserID
          WHERE m.MessageType = 'user' AND c.IsDeleted = 0
          GROUP BY u.KaynakAdi
          ORDER BY message_count DESC
        "),
        avg_chat_length = safe_query("
          SELECT AVG(msg_count) as avg_len FROM (
            SELECT ChatID, COUNT(*) as msg_count 
            FROM MB_Messages 
            GROUP BY ChatID
          ) sub
        "),
        usage_by_day = safe_query("
          SELECT 
            DATENAME(WEEKDAY, CreateTimestamp) as day_name,
            DATEPART(WEEKDAY, CreateTimestamp) as day_num,
            COUNT(*) as cnt
          FROM MB_Chats
          WHERE IsDeleted = 0
          GROUP BY DATENAME(WEEKDAY, CreateTimestamp), DATEPART(WEEKDAY, CreateTimestamp)
          ORDER BY day_num
        "),
        usage_by_hour = safe_query("
          SELECT 
            DATEPART(HOUR, CreateTimestamp) as hour_num,
            COUNT(*) as cnt
          FROM MB_Chats
          WHERE IsDeleted = 0
          GROUP BY DATEPART(HOUR, CreateTimestamp)
          ORDER BY hour_num
        "),
        model_performance = safe_query("
          SELECT 
            ModelUsed,
            COUNT(*) as total_calls,
            AVG(ResponseDuration) as avg_duration,
            SUM(CASE WHEN ResponseSuccess = 1 THEN 1 ELSE 0 END) as success_count,
            SUM(CASE WHEN ResponseSuccess = 0 THEN 1 ELSE 0 END) as error_count
          FROM MB_Usage_Log
          GROUP BY ModelUsed
          ORDER BY total_calls DESC
        "),
        slowest_queries = safe_query("
          SELECT TOP 20
            u.LogID,
            u.ModelUsed,
            u.ResponseDuration,
            LEFT(m.MessageContent, 100) as query_preview,
            u.ResponseSuccess
          FROM MB_Usage_Log u
          JOIN MB_Messages m ON u.MessageID = m.MessageID
          WHERE u.ResponseSuccess = 1
          ORDER BY u.ResponseDuration DESC
        "),
        model_errors = safe_query("
          SELECT 
            ModelUsed,
            COUNT(*) as error_count,
            CAST(COUNT(*) AS FLOAT) / NULLIF((SELECT COUNT(*) FROM MB_Usage_Log ul2 WHERE ul2.ModelUsed = MB_Usage_Log.ModelUsed), 0) * 100 as error_rate
          FROM MB_Usage_Log
          WHERE ResponseSuccess = 0
          GROUP BY ModelUsed
          ORDER BY error_count DESC
        "),
        top_liked = safe_query("
          SELECT TOP 10
            f.MessageID,
            LEFT(m.MessageContent, 150) as content_preview,
            COUNT(*) as like_count
          FROM MB_Feedback f
          JOIN MB_Messages m ON f.MessageID = m.MessageID
          WHERE f.FeedbackType = 'like'
          GROUP BY f.MessageID, LEFT(m.MessageContent, 150)
          ORDER BY like_count DESC
        "),
        response_time_vs_feedback = safe_query("
          SELECT 
            CASE 
              WHEN u.ResponseDuration < 5 THEN '< 5 sn'
              WHEN u.ResponseDuration < 10 THEN '5-10 sn'
              WHEN u.ResponseDuration < 20 THEN '10-20 sn'
              ELSE '> 20 sn'
            END as duration_bucket,
            SUM(CASE WHEN f.FeedbackType = 'like' THEN 1 ELSE 0 END) as likes,
            SUM(CASE WHEN f.FeedbackType = 'dislike' THEN 1 ELSE 0 END) as dislikes
          FROM MB_Usage_Log u
          LEFT JOIN MB_Feedback f ON u.MessageID = f.MessageID
          GROUP BY 
            CASE 
              WHEN u.ResponseDuration < 5 THEN '< 5 sn'
              WHEN u.ResponseDuration < 10 THEN '5-10 sn'
              WHEN u.ResponseDuration < 20 THEN '10-20 sn'
              ELSE '> 20 sn'
            END
        "),
        bounce_rate = safe_query("
          SELECT 
            CAST(SUM(CASE WHEN msg_count <= 2 THEN 1 ELSE 0 END) AS FLOAT) / NULLIF(COUNT(*), 0) * 100 as bounce_rate
          FROM (
            SELECT ChatID, COUNT(*) as msg_count 
            FROM MB_Messages 
            GROUP BY ChatID
          ) sub
        "),
        regenerated_responses = safe_query("
          SELECT TOP 20
            c.ChatID,
            c.ChatTitle,
            COUNT(*) as regen_count
          FROM MB_Messages m
          JOIN MB_Chats c ON m.ChatID = c.ChatID
          WHERE m.MessageType = 'ai' AND c.IsDeleted = 0
          GROUP BY c.ChatID, c.ChatTitle
          HAVING COUNT(*) > (SELECT COUNT(*) FROM MB_Messages m2 WHERE m2.ChatID = c.ChatID AND m2.MessageType = 'user')
          ORDER BY regen_count DESC
        "),
        power_users = safe_query("
          SELECT TOP 10
            u.KaynakAdi as user_name,
            COUNT(DISTINCT c.ChatID) as chat_count,
            SUM(sub.msg_count) as total_messages,
            AVG(sub.msg_count) as avg_chat_length
          FROM MB_Users u
          JOIN MB_Chats c ON u.UserID = c.UserID
          JOIN (
            SELECT ChatID, COUNT(*) as msg_count FROM MB_Messages GROUP BY ChatID
          ) sub ON c.ChatID = sub.ChatID
          WHERE c.IsDeleted = 0
          GROUP BY u.KaynakAdi
          ORDER BY total_messages DESC
        "),
        file_uploaders = safe_query("
          SELECT TOP 10
            u.KaynakAdi as user_name,
            COUNT(*) as file_count
          FROM MB_Messages m
          JOIN MB_Chats c ON m.ChatID = c.ChatID
          JOIN MB_Users u ON c.UserID = u.UserID
          WHERE m.MessageContent LIKE '%[Dosya:%' AND c.IsDeleted = 0
          GROUP BY u.KaynakAdi
          ORDER BY file_count DESC
        "),
        response_length_feedback = safe_query("
          SELECT 
            CASE 
              WHEN LEN(m.MessageContent) < 500 THEN 'Kısa (< 500)'
              WHEN LEN(m.MessageContent) < 1500 THEN 'Orta (500-1500)'
              WHEN LEN(m.MessageContent) < 3000 THEN 'Uzun (1500-3000)'
              ELSE 'Çok Uzun (> 3000)'
            END as length_bucket,
            SUM(CASE WHEN f.FeedbackType = 'like' THEN 1 ELSE 0 END) as likes,
            SUM(CASE WHEN f.FeedbackType = 'dislike' THEN 1 ELSE 0 END) as dislikes,
            COUNT(f.MessageID) as total_feedback
          FROM MB_Messages m
          LEFT JOIN MB_Feedback f ON m.MessageID = f.MessageID
          WHERE m.MessageType = 'ai'
          GROUP BY 
            CASE 
              WHEN LEN(m.MessageContent) < 500 THEN 'Kısa (< 500)'
              WHEN LEN(m.MessageContent) < 1500 THEN 'Orta (500-1500)'
              WHEN LEN(m.MessageContent) < 3000 THEN 'Uzun (1500-3000)'
              ELSE 'Çok Uzun (> 3000)'
            END
        "),
        code_ratio = safe_query("
          SELECT 
            CASE WHEN MessageContent LIKE '%```%' THEN 'Kodlu' ELSE 'Kodsuz' END as has_code,
            COUNT(*) as cnt
          FROM MB_Messages
          WHERE MessageType = 'ai'
          GROUP BY CASE WHEN MessageContent LIKE '%```%' THEN 'Kodlu' ELSE 'Kodsuz' END
        "),
        user_activation = safe_query("
          SELECT 
            u.KaynakAdi as user_name,
            MIN(c.CreateTimestamp) as first_chat,
            COUNT(DISTINCT c.ChatID) as total_chats,
            DATEDIFF(DAY, MIN(c.CreateTimestamp), MAX(c.CreateTimestamp)) as active_days
          FROM MB_Users u
          JOIN MB_Chats c ON u.UserID = c.UserID
          WHERE c.IsDeleted = 0
          GROUP BY u.KaynakAdi
          HAVING COUNT(DISTINCT c.ChatID) > 1
          ORDER BY first_chat DESC
        "),
        daily_trend = safe_query("
          SELECT 
            CAST(CreateTimestamp AS DATE) as chat_date,
            COUNT(*) as chat_count
          FROM MB_Chats
          WHERE IsDeleted = 0 AND CreateTimestamp >= DATEADD(DAY, -30, GETDATE())
          GROUP BY CAST(CreateTimestamp AS DATE)
          ORDER BY chat_date
        ")
      )
    })
    
    create_metric_card <- function(title, value, icon_name, color_class = "primary", subtitle = NULL) {
      div(
        class = paste("metric-card", color_class),
        div(class = "metric-icon", icon(icon_name)),
        div(
          class = "metric-content",
          span(class = "metric-value", value),
          span(class = "metric-title", title),
          if (!is.null(subtitle)) span(class = "metric-subtitle", subtitle)
        )
      )
    }
    
    output$overview_content <- renderUI({
      data <- analytics_data()
      
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
      
      likes <- 0
      dislikes <- 0
      if (nrow(data$feedback_summary) > 0) {
        likes <- sum(data$feedback_summary$cnt[data$feedback_summary$FeedbackType == "like"], na.rm = TRUE)
        dislikes <- sum(data$feedback_summary$cnt[data$feedback_summary$FeedbackType == "dislike"], na.rm = TRUE)
      }
      
      tagList(
        div(
          class = "metrics-grid",
		  create_metric_card("Toplam Kullanıcı", format(total_users, big.mark = ".", decimal.mark = ","), "users", "blue"),
          create_metric_card("Bugün Aktif", active_today, "user-clock", "green"),
          create_metric_card("Toplam Sohbet", format(total_chats, big.mark = ".", decimal.mark = ","), "comments", "purple"),
          create_metric_card("Toplam Mesaj", format(total_messages, big.mark = ".", decimal.mark = ","), "envelope", "orange"),
          create_metric_card("YZ Çağrısı", format(total_ai_calls, big.mark = ".", decimal.mark = ","), "robot", "cyan"),
          create_metric_card("Ort. Yanıt Süresi", avg_response, "clock", "yellow"),
          create_metric_card("Hata Oranı", error_rate, "exclamation-triangle", "red"),
          create_metric_card("Ort. Sohbet Uzunluğu", paste(avg_chat_len, "mesaj"), "layer-group", "teal")
        ),
        fluidRow(
          column(
            width = 6,
            div(
              class = "analytics-card",
              h4(class = "card-title", icon("chart-area"), " Son 30 Gün Trend"),
              highcharter::highchartOutput(ns("daily_trend_chart"), height = "300px")
            )
          ),
          column(
            width = 6,
            div(
              class = "analytics-card",
              h4(class = "card-title", icon("thumbs-up"), " Geri Bildirim Özeti"),
              highcharter::highchartOutput(ns("feedback_donut"), height = "300px")
            )
          )
        )
      )
    })
    
    output$daily_trend_chart <- highcharter::renderHighchart({
      data <- analytics_data()$daily_trend
      if (nrow(data) == 0) return(highcharter::highchart())
      
      highcharter::highchart() %>%
        highcharter::hc_chart(type = "areaspline", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = format(as.Date(data$chat_date), "%d %b"),
          labels = list(style = list(color = "#999")),
          lineColor = "#333",
          tickColor = "#333"
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Sohbet Sayısı", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#333"
        ) %>%
        highcharter::hc_add_series(
          name = "Sohbet",
          data = data$chat_count,
          color = "#ff6b35",
          fillColor = list(
            linearGradient = list(x1 = 0, y1 = 0, x2 = 0, y2 = 1),
            stops = list(
              list(0, "rgba(255, 107, 53, 0.4)"),
              list(1, "rgba(255, 107, 53, 0)")
            )
          )
        ) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a",
          borderColor = "#333",
          style = list(color = "#fff"),
          shared = TRUE
        ) %>%
        highcharter::hc_legend(enabled = FALSE) %>%
        highcharter::hc_credits(enabled = FALSE)
    })
    
    output$feedback_donut <- highcharter::renderHighchart({
      data <- analytics_data()$feedback_summary
      if (nrow(data) == 0) return(highcharter::highchart())
      
      chart_data <- lapply(1:nrow(data), function(i) {
        list(
          name = if (data$FeedbackType[i] == "like") "Beğeni" else "Beğenmeme",
          y = data$cnt[i],
          color = if (data$FeedbackType[i] == "like") "#4ade80" else "#f87171"
        )
      })
      
      highcharter::highchart() %>%
        highcharter::hc_chart(type = "pie", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_plotOptions(
          pie = list(
            innerSize = "60%",
            dataLabels = list(
              enabled = TRUE,
              format = "<b>{point.name}</b>: {point.percentage:.1f}%",
              style = list(color = "#fff", textOutline = "none")
            )
          )
        ) %>%
        highcharter::hc_add_series(
          name = "Geri Bildirim",
          data = chart_data
        ) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a",
          borderColor = "#333",
          style = list(color = "#fff"),
          pointFormat = "<b>{point.y}</b> adet ({point.percentage:.1f}%)"
        ) %>%
        highcharter::hc_credits(enabled = FALSE)
    })
    
    output$users_content <- renderUI({
      data <- analytics_data()
      
      tagList(
        fluidRow(
          column(
            width = 6,
            div(
              class = "analytics-card",
              h4(class = "card-title", icon("trophy"), " En Aktif Kullanıcılar"),
              highcharter::highchartOutput(ns("top_users_chart"), height = "350px")
            )
          ),
          column(
            width = 6,
            div(
              class = "analytics-card",
              h4(class = "card-title", icon("star"), " Power Users"),
              div(class = "table-container", DT::dataTableOutput(ns("power_users_table")))
            )
          )
        ),
        fluidRow(
          column(
            width = 6,
            div(
              class = "analytics-card",
              h4(class = "card-title", icon("calendar-week"), " Günlere Göre Kullanım"),
              highcharter::highchartOutput(ns("usage_by_day_chart"), height = "300px")
            )
          ),
          column(
            width = 6,
            div(
              class = "analytics-card",
              h4(class = "card-title", icon("clock"), " Saatlere Göre Kullanım"),
              highcharter::highchartOutput(ns("usage_by_hour_chart"), height = "300px")
            )
          )
        ),
        fluidRow(
          column(
            width = 12,
            div(
              class = "analytics-card",
              h4(class = "card-title", icon("upload"), " Dosya Yükleyenler"),
              div(class = "table-container", DT::dataTableOutput(ns("file_uploaders_table")))
            )
          )
        )
      )
    })
    
    output$top_users_chart <- highcharter::renderHighchart({
      data <- analytics_data()$top_users
      if (nrow(data) == 0) return(highcharter::highchart())
      
      highcharter::highchart() %>%
        highcharter::hc_chart(type = "bar", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = data$user_name,
          labels = list(style = list(color = "#999"))
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Mesaj Sayısı", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#333"
        ) %>%
        highcharter::hc_add_series(
          name = "Mesaj",
          data = data$message_count,
          colorByPoint = TRUE,
          colors = c("#ff6b35", "#f7931e", "#fbbf24", "#4ade80", "#3b82f6", 
                     "#8b5cf6", "#ec4899", "#06b6d4", "#84cc16", "#f43f5e")
        ) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a",
          borderColor = "#333",
          style = list(color = "#fff")
        ) %>%
        highcharter::hc_legend(enabled = FALSE) %>%
        highcharter::hc_credits(enabled = FALSE)
    })
    
    output$power_users_table <- DT::renderDataTable({
      data <- analytics_data()$power_users
      if (nrow(data) == 0) return(DT::datatable(data.frame()))
      
      colnames(data) <- c("Kullanıcı", "Sohbet Sayısı", "Toplam Mesaj", "Ort. Sohbet Uzunluğu")
      data$`Ort. Sohbet Uzunluğu` <- round(data$`Ort. Sohbet Uzunluğu`, 1)
      
      DT::datatable(
        data,
        options = list(
          dom = 't',
          pageLength = 10,
          ordering = FALSE,
          language = list(url = "//cdn.datatables.net/plug-ins/1.10.25/i18n/Turkish.json")
        ),
        class = "admin-datatable",
        rownames = FALSE
      )
    })
    
    output$usage_by_day_chart <- highcharter::renderHighchart({
      data <- analytics_data()$usage_by_day
      if (nrow(data) == 0) return(highcharter::highchart())
      
      day_names_tr <- c("Pazar", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi")
      data$day_name_tr <- day_names_tr[data$day_num]
      
      highcharter::highchart() %>%
        highcharter::hc_chart(type = "column", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = data$day_name_tr,
          labels = list(style = list(color = "#999"))
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Sohbet Sayısı", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#333"
        ) %>%
        highcharter::hc_add_series(
          name = "Sohbet",
          data = data$cnt,
          color = "#8b5cf6"
        ) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a",
          borderColor = "#333",
          style = list(color = "#fff")
        ) %>%
        highcharter::hc_legend(enabled = FALSE) %>%
        highcharter::hc_credits(enabled = FALSE)
    })
    
    output$usage_by_hour_chart <- highcharter::renderHighchart({
      data <- analytics_data()$usage_by_hour
      if (nrow(data) == 0) return(highcharter::highchart())
      
      all_hours <- data.frame(hour_num = 0:23)
      data <- merge(all_hours, data, by = "hour_num", all.x = TRUE)
      data$cnt[is.na(data$cnt)] <- 0
      
      highcharter::highchart() %>%
        highcharter::hc_chart(type = "areaspline", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = sprintf("%02d:00", data$hour_num),
          labels = list(style = list(color = "#999"), step = 2)
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Sohbet Sayısı", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#333"
        ) %>%
        highcharter::hc_add_series(
          name = "Sohbet",
          data = data$cnt,
          color = "#06b6d4",
          fillColor = list(
            linearGradient = list(x1 = 0, y1 = 0, x2 = 0, y2 = 1),
            stops = list(
              list(0, "rgba(6, 182, 212, 0.4)"),
              list(1, "rgba(6, 182, 212, 0)")
            )
          )
        ) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a",
          borderColor = "#333",
          style = list(color = "#fff")
        ) %>%
        highcharter::hc_legend(enabled = FALSE) %>%
        highcharter::hc_credits(enabled = FALSE)
    })
    
    output$file_uploaders_table <- DT::renderDataTable({
      data <- analytics_data()$file_uploaders
      if (nrow(data) == 0) return(DT::datatable(data.frame()))
      
      colnames(data) <- c("Kullanıcı", "Yüklenen Dosya Sayısı")
      
      DT::datatable(
        data,
        options = list(
          dom = 't',
          pageLength = 10,
          ordering = FALSE,
          language = list(url = "//cdn.datatables.net/plug-ins/1.10.25/i18n/Turkish.json")
        ),
        class = "admin-datatable",
        rownames = FALSE
      )
    })
    
    output$ai_perf_content <- renderUI({
      data <- analytics_data()
      
      tagList(
        fluidRow(
          column(
            width = 12,
            div(
              class = "analytics-card",
              h4(class = "card-title", icon("microchip"), " Model Performans Karşılaştırması"),
              highcharter::highchartOutput(ns("model_perf_chart"), height = "350px")
            )
          )
        ),
        fluidRow(
          column(
            width = 6,
            div(
              class = "analytics-card",
              h4(class = "card-title", icon("exclamation-circle"), " Model Hata Oranları"),
              highcharter::highchartOutput(ns("model_errors_chart"), height = "300px")
            )
          ),
          column(
            width = 6,
            div(
              class = "analytics-card",
              h4(class = "card-title", icon("hourglass-half"), " En Yavaş 20 Sorgu"),
              div(class = "table-container scrollable-table", DT::dataTableOutput(ns("slowest_queries_table")))
            )
          )
        )
      )
    })
    
    output$model_perf_chart <- highcharter::renderHighchart({
      data <- analytics_data()$model_performance
      if (nrow(data) == 0) return(highcharter::highchart())
      
      highcharter::highchart() %>%
        highcharter::hc_chart(type = "column", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = data$ModelUsed,
          labels = list(style = list(color = "#999"))
        ) %>%
        highcharter::hc_yAxis_multiples(
          list(
            title = list(text = "Çağrı Sayısı", style = list(color = "#4ade80")),
            labels = list(style = list(color = "#999")),
            gridLineColor = "#333"
          ),
          list(
            title = list(text = "Ort. Süre (sn)", style = list(color = "#f7931e")),
            labels = list(style = list(color = "#999")),
            opposite = TRUE
          )
        ) %>%
        highcharter::hc_add_series(
          name = "Toplam Çağrı",
          data = data$total_calls,
          color = "#4ade80",
          yAxis = 0
        ) %>%
        highcharter::hc_add_series(
          name = "Ort. Yanıt Süresi",
          data = round(data$avg_duration, 2),
          type = "spline",
          color = "#f7931e",
          yAxis = 1
        ) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a",
          borderColor = "#333",
          style = list(color = "#fff"),
          shared = TRUE
        ) %>%
        highcharter::hc_legend(
          itemStyle = list(color = "#999")
        ) %>%
        highcharter::hc_credits(enabled = FALSE)
    })
    
    output$model_errors_chart <- highcharter::renderHighchart({
      data <- analytics_data()$model_errors
      if (nrow(data) == 0) return(highcharter::highchart())
      
      highcharter::highchart() %>%
        highcharter::hc_chart(type = "bar", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = data$ModelUsed,
          labels = list(style = list(color = "#999"))
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Hata Oranı (%)", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#333"
        ) %>%
        highcharter::hc_add_series(
          name = "Hata Oranı",
          data = round(data$error_rate, 2),
          color = "#f87171"
        ) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a",
          borderColor = "#333",
          style = list(color = "#fff"),
          valueSuffix = "%"
        ) %>%
        highcharter::hc_legend(enabled = FALSE) %>%
        highcharter::hc_credits(enabled = FALSE)
    })
    
    output$slowest_queries_table <- DT::renderDataTable({
      data <- analytics_data()$slowest_queries
      if (nrow(data) == 0) return(DT::datatable(data.frame()))
      
      data <- data[, c("ModelUsed", "ResponseDuration", "query_preview")]
      colnames(data) <- c("Model", "Süre (sn)", "Sorgu Önizleme")
      data$`Süre (sn)` <- round(data$`Süre (sn)`, 2)
      
      DT::datatable(
        data,
        options = list(
          dom = 't',
          pageLength = 20,
          scrollY = "250px",
          scrollCollapse = TRUE,
          ordering = FALSE,
          language = list(url = "//cdn.datatables.net/plug-ins/1.10.25/i18n/Turkish.json")
        ),
        class = "admin-datatable",
        rownames = FALSE
      )
    })
    
    output$feedback_content <- renderUI({
      data <- analytics_data()
      
      tagList(
        fluidRow(
          column(
            width = 6,
            div(
              class = "analytics-card",
              h4(class = "card-title", icon("heart"), " En Beğenilen Yanıtlar"),
              div(class = "table-container scrollable-table", DT::dataTableOutput(ns("top_liked_table")))
            )
          ),
          column(
            width = 6,
            div(
              class = "analytics-card",
              h4(class = "card-title", icon("stopwatch"), " Yanıt Süresi vs Geri Bildirim"),
              highcharter::highchartOutput(ns("response_time_feedback_chart"), height = "300px")
            )
          )
        ),
        fluidRow(
          column(
            width = 12,
            div(
              class = "analytics-card",
              h4(class = "card-title", icon("text-width"), " Yanıt Uzunluğu vs Geri Bildirim"),
              highcharter::highchartOutput(ns("response_length_feedback_chart"), height = "300px")
            )
          )
        )
      )
    })
    
    output$top_liked_table <- DT::renderDataTable({
      data <- analytics_data()$top_liked
      if (nrow(data) == 0) return(DT::datatable(data.frame()))
      
      data <- data[, c("content_preview", "like_count")]
      colnames(data) <- c("Yanıt Önizleme", "Beğeni Sayısı")
      
      DT::datatable(
        data,
        options = list(
          dom = 't',
          pageLength = 10,
          scrollY = "250px",
          scrollCollapse = TRUE,
          ordering = FALSE,
          language = list(url = "//cdn.datatables.net/plug-ins/1.10.25/i18n/Turkish.json")
        ),
        class = "admin-datatable",
        rownames = FALSE
      )
    })
    
    output$response_time_feedback_chart <- highcharter::renderHighchart({
      data <- analytics_data()$response_time_vs_feedback
      if (nrow(data) == 0) return(highcharter::highchart())
      
      bucket_order <- c("< 5 sn", "5-10 sn", "10-20 sn", "> 20 sn")
      data$duration_bucket <- factor(data$duration_bucket, levels = bucket_order)
      data <- data[order(data$duration_bucket), ]
      
      highcharter::highchart() %>%
        highcharter::hc_chart(type = "column", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = as.character(data$duration_bucket),
          labels = list(style = list(color = "#999"))
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Geri Bildirim Sayısı", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#333"
        ) %>%
        highcharter::hc_add_series(name = "Beğeni", data = data$likes, color = "#4ade80") %>%
        highcharter::hc_add_series(name = "Beğenmeme", data = data$dislikes, color = "#f87171") %>%
        highcharter::hc_plotOptions(column = list(grouping = TRUE)) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a",
          borderColor = "#333",
          style = list(color = "#fff"),
          shared = TRUE
        ) %>%
        highcharter::hc_legend(itemStyle = list(color = "#999")) %>%
        highcharter::hc_credits(enabled = FALSE)
    })
    
    output$response_length_feedback_chart <- highcharter::renderHighchart({
      data <- analytics_data()$response_length_feedback
      if (nrow(data) == 0) return(highcharter::highchart())
      
      bucket_order <- c("Kısa (< 500)", "Orta (500-1500)", "Uzun (1500-3000)", "Çok Uzun (> 3000)")
      data$length_bucket <- factor(data$length_bucket, levels = bucket_order)
      data <- data[order(data$length_bucket), ]
      
      highcharter::highchart() %>%
        highcharter::hc_chart(type = "bar", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = as.character(data$length_bucket),
          labels = list(style = list(color = "#999"))
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Geri Bildirim Sayısı", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#333"
        ) %>%
        highcharter::hc_plotOptions(bar = list(stacking = "normal")) %>%
        highcharter::hc_add_series(name = "Beğeni", data = data$likes, color = "#4ade80") %>%
        highcharter::hc_add_series(name = "Beğenmeme", data = data$dislikes, color = "#f87171") %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a",
          borderColor = "#333",
          style = list(color = "#fff"),
          shared = TRUE
        ) %>%
        highcharter::hc_legend(itemStyle = list(color = "#999")) %>%
        highcharter::hc_credits(enabled = FALSE)
    })
    
    output$chat_quality_content <- renderUI({
      data <- analytics_data()
      
      bounce_rate <- if (nrow(data$bounce_rate) > 0 && !is.na(data$bounce_rate$bounce_rate[1])) 
        sprintf("%.1f%%", data$bounce_rate$bounce_rate[1]) else "N/A"
      
      tagList(
        div(
          class = "metrics-grid metrics-grid-small",
          create_metric_card("Bounce Rate", bounce_rate, "door-open", "orange", "Tek yanıtlık sohbet oranı")
        ),
        fluidRow(
          column(
            width = 6,
            div(
              class = "analytics-card",
              h4(class = "card-title", icon("code"), " Kodlu vs Kodsuz Yanıtlar"),
              highcharter::highchartOutput(ns("code_ratio_chart"), height = "300px")
            )
          ),
          column(
            width = 6,
            div(
              class = "analytics-card",
              h4(class = "card-title", icon("redo"), " En Çok Yeniden Oluşturulan Yanıtlar"),
              div(class = "table-container scrollable-table", DT::dataTableOutput(ns("regenerated_table")))
            )
          )
        )
      )
    })
    
    output$code_ratio_chart <- highcharter::renderHighchart({
      data <- analytics_data()$code_ratio
      if (nrow(data) == 0) return(highcharter::highchart())
      
      chart_data <- lapply(1:nrow(data), function(i) {
        list(
          name = data$has_code[i],
          y = data$cnt[i],
          color = if (data$has_code[i] == "Kodlu") "#3b82f6" else "#8b5cf6"
        )
      })
      
      highcharter::highchart() %>%
        highcharter::hc_chart(type = "pie", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_plotOptions(
          pie = list(
            dataLabels = list(
              enabled = TRUE,
              format = "<b>{point.name}</b>: {point.percentage:.1f}%",
              style = list(color = "#fff", textOutline = "none")
            )
          )
        ) %>%
        highcharter::hc_add_series(name = "Yanıt Türü", data = chart_data) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a",
          borderColor = "#333",
          style = list(color = "#fff"),
          pointFormat = "<b>{point.y}</b> adet ({point.percentage:.1f}%)"
        ) %>%
        highcharter::hc_credits(enabled = FALSE)
    })
    
    output$regenerated_table <- DT::renderDataTable({
      data <- analytics_data()$regenerated_responses
      if (nrow(data) == 0) return(DT::datatable(data.frame()))
      
      data <- data[, c("ChatTitle", "regen_count")]
      colnames(data) <- c("Sohbet Başlığı", "Yeniden Oluşturma Sayısı")
      
      DT::datatable(
        data,
        options = list(
          dom = 't',
          pageLength = 20,
          scrollY = "250px",
          scrollCollapse = TRUE,
          ordering = FALSE,
          language = list(url = "//cdn.datatables.net/plug-ins/1.10.25/i18n/Turkish.json")
        ),
        class = "admin-datatable",
        rownames = FALSE
      )
    })
    
    output$time_analysis_content <- renderUI({
      data <- analytics_data()
      
      tagList(
        fluidRow(
          column(
            width = 12,
            div(
              class = "analytics-card",
              h4(class = "card-title", icon("user-plus"), " Yeni Kullanıcı Aktivasyon Analizi"),
              div(class = "table-container", DT::dataTableOutput(ns("activation_table")))
            )
          )
        )
      )
    })
    
    output$activation_table <- DT::renderDataTable({
      data <- analytics_data()$user_activation
      if (nrow(data) == 0) return(DT::datatable(data.frame()))
      
      data$first_chat <- format(as.POSIXct(data$first_chat), "%d.%m.%Y")
      colnames(data) <- c("Kullanıcı", "İlk Sohbet", "Toplam Sohbet", "Aktif Gün Aralığı")
      
      DT::datatable(
        data,
        options = list(
          dom = 'ftp',
          pageLength = 15,
          language = list(url = "//cdn.datatables.net/plug-ins/1.10.25/i18n/Turkish.json")
        ),
        class = "admin-datatable",
        rownames = FALSE
      )
    })
    
  })
}

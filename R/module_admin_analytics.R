# R/module_admin_analytics.R

adminAnalyticsUI <- function(id) {
  ns <- NS(id)
  
  turkish_dt_language <- list(
    processing = "İşleniyor...",
    search = "Ara:",
    lengthMenu = "_MENU_ kayıt göster",
    info = "_TOTAL_ kayıttan _START_ - _END_ arası gösteriliyor",
    infoEmpty = "Kayıt yok",
    infoFiltered = "(_MAX_ kayıt içinden filtrelendi)",
    infoPostFix = "",
    loadingRecords = "Yükleniyor...",
    zeroRecords = "Eşleşen kayıt bulunamadı",
    emptyTable = "Tabloda veri yok",
    paginate = list(
      first = "İlk",
      previous = "Önceki",
      `next` = "Sonraki",
      last = "Son"
    ),
    aria = list(
      sortAscending = ": artan sıralama",
      sortDescending = ": azalan sıralama"
    )
  )
  
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
        class = "admin-tabs-sticky-wrapper",
        div(
          class = "admin-tabs-container",
          tabsetPanel(
            id = ns("admin_tabs"),
            type = "pills",
            tabPanel(
              title = tags$span(title = "Genel sistem metrikleri ve özet istatistikler", tagList(icon("chart-line"), " Genel Bakış")),
              value = "overview",
              div(class = "tab-content-wrapper", uiOutput(ns("overview_content")))
            ),
            tabPanel(
              title = tags$span(title = "Kullanıcı aktiviteleri ve davranış analizi", tagList(icon("users"), " Kullanıcı Analizi")),
              value = "users",
              div(class = "tab-content-wrapper", uiOutput(ns("users_content")))
            ),
            tabPanel(
              title = tags$span(title = "Yapay zeka model performansı ve hata oranları", tagList(icon("robot"), " YZ Performansı")),
              value = "ai_perf",
              div(class = "tab-content-wrapper", uiOutput(ns("ai_perf_content")))
            ),
            tabPanel(
              title = tags$span(title = "Kullanıcı geri bildirimleri ve memnuniyet analizi", tagList(icon("thumbs-up"), " Geri Bildirim")),
              value = "feedback",
              div(class = "tab-content-wrapper", uiOutput(ns("feedback_content")))
            ),
            tabPanel(
              title = tags$span(title = "Söyleşi kalitesi ve içerik analizi", tagList(icon("comments"), " Söyleşi Kalitesi")),
              value = "chat_quality",
              div(class = "tab-content-wrapper", uiOutput(ns("chat_quality_content")))
            ),
            tabPanel(
              title = tags$span(title = "Zamana göre kullanım ve aktivite analizi", tagList(icon("clock"), " Zaman Analizi")),
              value = "time_analysis",
              div(class = "tab-content-wrapper", uiOutput(ns("time_analysis_content")))
            )
          )
        )
      ),
      div(
        class = "admin-scrollable-content",
        uiOutput(ns("tab_content_area"))
      )
    )
  )
}

adminAnalyticsServer <- function(id, pool = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    
    turkish_dt_language <- list(
      processing = "İşleniyor...",
      search = "Ara:",
      lengthMenu = "_MENU_ kayıt göster",
      info = "_TOTAL_ kayıttan _START_ - _END_ arası gösteriliyor",
      infoEmpty = "Kayıt yok",
      infoFiltered = "(_MAX_ kayıt içinden filtrelendi)",
      infoPostFix = "",
      loadingRecords = "Yükleniyor...",
      zeroRecords = "Eşleşen kayıt bulunamadı",
      emptyTable = "Tabloda veri yok",
      paginate = list(
        first = "İlk",
        previous = "Önceki",
        `next` = "Sonraki",
        last = "Son"
      ),
      aria = list(
        sortAscending = ": artan sıralama",
        sortDescending = ": azalan sıralama"
      )
    )
    
    turkish_months <- c("Oca", "Şub", "Mar", "Nis", "May", "Haz", "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara")
    
    format_turkish_date <- function(date_val) {
      if (is.na(date_val) || is.null(date_val)) return("")
      d <- as.Date(date_val)
      day_num <- format(d, "%d")
      month_num <- as.numeric(format(d, "%m"))
      paste0(day_num, " ", turkish_months[month_num])
    }
    
    analytics_refresh_trigger <- reactiveVal(0)
    analytics_last_update <- reactiveVal(format(Sys.time(), "%d.%m.%Y %H:%M:%S"))
    
    observe({
      invalidateLater(600000)
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
            m.MessageTimestamp as query_time
          FROM MB_Usage_Log u
          JOIN MB_Messages m ON u.MessageID = m.MessageID
          WHERE u.ResponseSuccess = 1
          ORDER BY u.ResponseDuration DESC
        "),
        fastest_queries = safe_query("
          SELECT TOP 20
            u.LogID,
            u.ModelUsed,
            u.ResponseDuration,
            LEFT(m.MessageContent, 100) as query_preview,
            m.MessageTimestamp as query_time
          FROM MB_Usage_Log u
          JOIN MB_Messages m ON u.MessageID = m.MessageID
          WHERE u.ResponseSuccess = 1 AND u.ResponseDuration > 0
          ORDER BY u.ResponseDuration ASC
        "),
        model_errors = safe_query("
          SELECT 
            ModelUsed,
            COUNT(*) as error_count,
            CAST(COUNT(*) AS FLOAT) / NULLIF((SELECT COUNT(*) FROM MB_Usage_Log ul2 WHERE ul2.ModelUsed = MB_Usage_Log.ModelUsed), 0) * 100 as error_rate
          FROM MB_Usage_Log
          WHERE ResponseSuccess = 0
          GROUP BY ModelUsed
          ORDER BY error_rate DESC
        "),
        model_feedback = safe_query("
          SELECT 
            u.ModelUsed,
            SUM(CASE WHEN f.FeedbackType = 'like' THEN 1 ELSE 0 END) as likes,
            SUM(CASE WHEN f.FeedbackType = 'dislike' THEN 1 ELSE 0 END) as dislikes,
            COUNT(DISTINCT u.LogID) as total_responses
          FROM MB_Usage_Log u
          LEFT JOIN MB_Feedback f ON u.MessageID = f.MessageID
          GROUP BY u.ModelUsed
          ORDER BY total_responses DESC
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
        bounce_rate = safe_query("
          SELECT 
            CAST(SUM(CASE WHEN msg_count <= 2 THEN 1 ELSE 0 END) AS FLOAT) / NULLIF(COUNT(*), 0) * 100 as bounce_rate
          FROM (
            SELECT ChatID, COUNT(*) as msg_count 
            FROM MB_Messages 
            GROUP BY ChatID
          ) sub
        "),
        code_ratio = safe_query("
          SELECT 
            CASE WHEN MessageContent LIKE '%```%' THEN 'Kodlu' ELSE 'Kodsuz' END as has_code,
            COUNT(*) as cnt
          FROM MB_Messages
          WHERE MessageType = 'ai'
          GROUP BY CASE WHEN MessageContent LIKE '%```%' THEN 'Kodlu' ELSE 'Kodsuz' END
        "),
        regenerated_responses = safe_query("
          SELECT TOP 20
            c.ChatID,
            c.ChatTitle,
            u.ModelUsed,
            COUNT(*) as regen_count
          FROM MB_Messages m
          JOIN MB_Chats c ON m.ChatID = c.ChatID
          LEFT JOIN MB_Usage_Log u ON m.MessageID = u.MessageID
          WHERE m.MessageType = 'ai' AND c.IsDeleted = 0
          GROUP BY c.ChatID, c.ChatTitle, u.ModelUsed
          HAVING COUNT(*) > (SELECT COUNT(*) FROM MB_Messages m2 WHERE m2.ChatID = c.ChatID AND m2.MessageType = 'user')
          ORDER BY regen_count DESC
        "),
        power_users = safe_query("
          SELECT TOP 10
            u.KaynakAdi as user_name,
            COUNT(DISTINCT c.ChatID) as chat_count,
            COUNT(m.MessageID) as total_messages,
            CAST(COUNT(m.MessageID) AS FLOAT) / NULLIF(COUNT(DISTINCT c.ChatID), 0) as avg_chat_length
          FROM MB_Users u
          JOIN MB_Chats c ON u.UserID = c.UserID
          JOIN MB_Messages m ON c.ChatID = m.ChatID
          WHERE c.IsDeleted = 0 AND m.MessageType = 'user'
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
        "),
        avg_messages_per_chat = safe_query("
          SELECT AVG(CAST(msg_count AS FLOAT)) as avg_msg FROM (
            SELECT c.ChatID, COUNT(m.MessageID) as msg_count 
            FROM MB_Chats c
            JOIN MB_Messages m ON c.ChatID = m.ChatID
            WHERE c.IsDeleted = 0
            GROUP BY c.ChatID
          ) sub
        "),
        longest_chats = safe_query("
          SELECT TOP 10
            c.ChatTitle,
            COUNT(m.MessageID) as message_count,
            u.KaynakAdi as user_name
          FROM MB_Chats c
          JOIN MB_Messages m ON c.ChatID = m.ChatID
          JOIN MB_Users u ON c.UserID = u.UserID
          WHERE c.IsDeleted = 0
          GROUP BY c.ChatID, c.ChatTitle, u.KaynakAdi
          ORDER BY message_count DESC
        "),
        weekly_trend = safe_query("
          SELECT 
            DATEPART(WEEK, CreateTimestamp) as week_num,
            DATEPART(YEAR, CreateTimestamp) as year_num,
            COUNT(*) as chat_count
          FROM MB_Chats
          WHERE IsDeleted = 0 AND CreateTimestamp >= DATEADD(WEEK, -12, GETDATE())
          GROUP BY DATEPART(WEEK, CreateTimestamp), DATEPART(YEAR, CreateTimestamp)
          ORDER BY year_num, week_num
        "),
        peak_hours = safe_query("
          SELECT TOP 5
            DATEPART(HOUR, CreateTimestamp) as hour_num,
            COUNT(*) as chat_count
          FROM MB_Chats
          WHERE IsDeleted = 0
          GROUP BY DATEPART(HOUR, CreateTimestamp)
          ORDER BY chat_count DESC
        "),
        total_feedback_count = safe_query("SELECT COUNT(*) as cnt FROM MB_Feedback")
      )
    })
    
    create_metric_card <- function(title, value, icon_name, color_class = "primary", subtitle = NULL, tooltip = NULL) {
      tooltip_attr <- if (!is.null(tooltip)) paste0('title="', tooltip, '"') else ""
      div(
        class = paste("metric-card", color_class),
        `data-toggle` = if (!is.null(tooltip)) "tooltip" else NULL,
        title = tooltip,
        div(class = "metric-icon", icon(icon_name)),
        div(
          class = "metric-content",
          span(class = "metric-value", value),
          span(class = "metric-title", title),
          if (!is.null(subtitle)) span(class = "metric-subtitle", subtitle)
        )
      )
    }
    
    create_info_button <- function(info_text) {
      tags$span(
        class = "info-btn",
        title = info_text,
        `data-toggle` = "tooltip",
        `data-placement` = "top",
        icon("info-circle")
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
          create_metric_card("Toplam Kullanıcı", format(total_users, big.mark = ".", decimal.mark = ","), "users", "blue", tooltip = "Sistemde kayıtlı olan tüm benzersiz kullanıcıların toplam sayısı. Her kullanıcı yalnızca bir kez sayılır."),
          create_metric_card("Bugün Aktif", active_today, "user-clock", "green", tooltip = "Bugün en az bir söyleşi başlatan veya mevcut söyleşilerine devam eden kullanıcı sayısı."),
          create_metric_card("Toplam Söyleşi", format(total_chats, big.mark = ".", decimal.mark = ","), "comments", "purple", tooltip = "Sistemde oluşturulan tüm söyleşi oturumlarının toplam sayısı. Silinen söyleşiler dahil değildir."),
          create_metric_card("Toplam Mesaj", format(total_messages, big.mark = ".", decimal.mark = ","), "envelope", "orange", tooltip = "Kullanıcılar ve YZ tarafından gönderilen tüm mesajların toplam sayısı."),
          create_metric_card("YZ Çağrısı", format(total_ai_calls, big.mark = ".", decimal.mark = ","), "robot", "cyan", tooltip = "Yapay zeka modeline yapılan toplam API çağrısı sayısı. Her kullanıcı mesajı için genellikle bir YZ çağrısı yapılır."),
          create_metric_card("Ortalama Yanıt Süresi", avg_response, "clock", "yellow", tooltip = "YZ modelinin başarılı yanıtlar için ortalama yanıt süresi (saniye cinsinden). MB_Usage_Log tablosundaki ResponseDuration değerlerinin ortalamasıdır."),
          create_metric_card("Hata Oranı", error_rate, "exclamation-triangle", "red", tooltip = "Başarısız YZ çağrılarının toplam çağrılara oranı (%). ResponseSuccess = 0 olan kayıtların yüzdesi hesaplanır."),
          create_metric_card("Ortalama Söyleşi Uzunluğu", avg_chat_len, "list-ol", "pink", tooltip = "Her söyleşideki ortalama mesaj sayısı. Kullanıcı etkileşim derinliğini gösterir.")
        ),
        fluidRow(
          column(
            width = 6,
            div(
              class = "analytics-card",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("chart-area"), " Son 30 Gün Eğilim"),
                create_info_button("Son 30 gündeki günlük söyleşi sayısını gösteren trend grafiği. X ekseni tarihleri Türkçe formatında gösterir (gün ay). Y ekseni söyleşi sayısını temsil eder.")
              ),
              highcharter::highchartOutput(ns("daily_trend_chart"), height = "300px")
            )
          ),
          column(
            width = 6,
            div(
              class = "analytics-card",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("chart-pie"), " Geri Bildirim Özeti"),
                create_info_button("Kullanıcıların YZ yanıtlarına verdikleri beğeni ve beğenmeme geri bildirimlerinin dağılımı. Yeşil: Beğeni, Kırmızı: Beğenmeme")
              ),
              highcharter::highchartOutput(ns("feedback_donut_chart"), height = "300px")
            )
          )
        )
      )
    })
    
    output$daily_trend_chart <- highcharter::renderHighchart({
      data <- analytics_data()$daily_trend
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
        highcharter::hc_add_series(
          name = "Söyleşi",
          data = data$chat_count,
          color = "#ff6b35",
          fillColor = list(
            linearGradient = list(x1 = 0, y1 = 0, x2 = 0, y2 = 1),
            stops = list(
              list(0, "rgba(255, 107, 53, 0.3)"),
              list(1, "rgba(255, 107, 53, 0)")
            )
          ),
          marker = list(enabled = FALSE),
          lineWidth = 2
        ) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a",
          borderColor = "#333",
          style = list(color = "#fff")
        ) %>%
        highcharter::hc_legend(enabled = FALSE) %>%
        highcharter::hc_credits(enabled = FALSE)
    })
    
    output$feedback_donut_chart <- highcharter::renderHighchart({
      data <- analytics_data()$feedback_summary
      if (nrow(data) == 0) return(highcharter::highchart())
      
      likes <- sum(data$cnt[data$FeedbackType == "like"], na.rm = TRUE)
      dislikes <- sum(data$cnt[data$FeedbackType == "dislike"], na.rm = TRUE)
      
      chart_data <- list(
        list(name = "Beğeni", y = likes, color = "#22c55e"),
        list(name = "Beğenmeme", y = dislikes, color = "#ef4444")
      )
      
      highcharter::highchart() %>%
        highcharter::hc_chart(type = "pie", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_plotOptions(
          pie = list(
            innerSize = "60%",
            borderWidth = 0,
            dataLabels = list(
              enabled = TRUE,
              format = "<b>{point.name}</b>: {point.y}",
              style = list(color = "#fff", textOutline = "none")
            )
          )
        ) %>%
        highcharter::hc_add_series(name = "Geri Bildirim", data = chart_data) %>%
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
              class = "analytics-card equal-height-card",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("trophy"), " En Aktif Kullanıcılar"),
                create_info_button("En fazla mesaj gönderen ilk 10 kullanıcının listesi. Bu grafik kullanıcı mesaj sayılarını gösterir ve en aktif kullanıcıları belirlemeye yardımcı olur.")
              ),
              highcharter::highchartOutput(ns("top_users_chart"), height = "350px")
            )
          ),
          column(
            width = 6,
            div(
              class = "analytics-card equal-height-card",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("star"), " Güçlü Kullanıcılar"),
                create_info_button("En yoğun sistem kullanıcıları. Söyleşi sayısı, toplam mesaj ve ortalama söyleşi uzunluğu metrikleri ile sıralanmıştır.")
              ),
              div(class = "table-container scrollable-table-fixed", DT::dataTableOutput(ns("power_users_table")))
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
                create_info_button("Haftanın günlerine göre söyleşi dağılımı. Hangi günlerde sistemin daha yoğun kullanıldığını gösterir. Tooltip'te günün toplama oranı da gösterilir.")
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
                create_info_button("Günün saatlerine göre söyleşi dağılımı (0-23). En yoğun saatleri ve kullanım kalıplarını belirlemeye yardımcı olur.")
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
                create_info_button("En fazla dosya yükleyen kullanıcıların listesi. [Dosya: şeklinde mesaj içeriği tespit edilir.")
              ),
              div(class = "table-container", DT::dataTableOutput(ns("file_uploaders_table")))
            )
          )
        )
      )
    })
    
    output$top_users_chart <- highcharter::renderHighchart({
      data <- analytics_data()$top_users
      if (nrow(data) == 0) return(highcharter::highchart())
      
      data <- head(data, 10)
      
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
          gridLineColor = "#444"
        ) %>%
        highcharter::hc_plotOptions(
          bar = list(
            borderWidth = 0,
            colorByPoint = TRUE
          )
        ) %>%
        highcharter::hc_add_series(
          name = "Mesaj",
          data = data$message_count,
          colors = c("#ff6b35", "#f7931e", "#fbbf24", "#22c55e", "#3b82f6", 
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
      
      data$avg_chat_length <- round(data$avg_chat_length, 1)
      colnames(data) <- c("Kullanıcı", "Söyleşi Sayısı", "Toplam Mesaj", "Ortalama Söyleşi Uzunluğu")
      
      DT::datatable(
        data,
        options = list(
          dom = 't',
          pageLength = 10,
          ordering = FALSE,
          scrollY = "280px",
          scrollCollapse = TRUE,
          language = turkish_dt_language,
          columnDefs = list(
            list(className = 'dt-center', targets = "_all")
          )
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
      total_chats <- sum(data$cnt, na.rm = TRUE)
      data$ratio <- round((data$cnt / total_chats) * 100, 1)
      
      highcharter::highchart() %>%
        highcharter::hc_chart(type = "column", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = data$day_name_tr,
          labels = list(style = list(color = "#999"))
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Söyleşi Sayısı", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#444"
        ) %>%
        highcharter::hc_plotOptions(
          column = list(borderWidth = 0)
        ) %>%
        highcharter::hc_add_series(
          name = "Söyleşi",
          data = lapply(1:nrow(data), function(i) {
            list(y = data$cnt[i], ratio = data$ratio[i])
          }),
          color = "#8b5cf6"
        ) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a",
          borderColor = "#333",
          style = list(color = "#fff"),
          pointFormat = "<b>{point.y}</b> söyleşi<br/>Oran: <b>{point.ratio}%</b>"
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
      data <- data[order(data$hour_num), ]
      
      highcharter::highchart() %>%
        highcharter::hc_chart(type = "area", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = sprintf("%02d:00", data$hour_num),
          labels = list(style = list(color = "#999"), step = 2)
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Söyleşi Sayısı", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#444"
        ) %>%
        highcharter::hc_plotOptions(
          area = list(
            marker = list(enabled = FALSE),
            lineWidth = 2,
            fillColor = list(
              linearGradient = list(x1 = 0, y1 = 0, x2 = 0, y2 = 1),
              stops = list(
                list(0, "rgba(6, 182, 212, 0.3)"),
                list(1, "rgba(6, 182, 212, 0)")
              )
            )
          )
        ) %>%
        highcharter::hc_add_series(
          name = "Söyleşi",
          data = data$cnt,
          color = "#06b6d4"
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
          dom = 'ftp',
          pageLength = 10,
          language = turkish_dt_language,
          columnDefs = list(
            list(className = 'dt-center', targets = "_all")
          )
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
            width = 6,
            div(
              class = "analytics-card",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("chart-bar"), " Model Performansı Karşılaştırması"),
                create_info_button("Her modelin ortalama yanıt süresini karşılaştırır. Düşük değerler daha hızlı yanıt anlamına gelir.")
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
                create_info_button("Her modelin hata oranını gösterir (%). Hata oranı = (Başarısız çağrılar / Toplam çağrılar) x 100. Düşük oranlar daha güvenilir modelleri gösterir.")
              ),
              highcharter::highchartOutput(ns("model_errors_chart"), height = "350px")
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
                h4(class = "card-title", icon("hourglass-end"), " En Yavaş 20 Sorgu"),
                create_info_button("En uzun süren 20 YZ yanıtının listesi. Model, süre, sorgu önizlemesi ve zaman damgası gösterilir.")
              ),
              div(class = "table-container scrollable-table", DT::dataTableOutput(ns("slowest_queries_table")))
            )
          ),
          column(
            width = 6,
            div(
              class = "analytics-card",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("bolt"), " En Hızlı 20 Sorgu"),
                create_info_button("En kısa sürede yanıtlanan 20 sorgunun listesi. Model, süre, sorgu önizlemesi ve zaman damgası gösterilir.")
              ),
              div(class = "table-container scrollable-table", DT::dataTableOutput(ns("fastest_queries_table")))
            )
          )
        )
      )
    })
    
    output$model_performance_chart <- highcharter::renderHighchart({
      data <- analytics_data()$model_performance
      if (nrow(data) == 0) return(highcharter::highchart())
      
      highcharter::highchart() %>%
        highcharter::hc_chart(type = "bar", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = data$ModelUsed,
          labels = list(style = list(color = "#999"))
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Ortalama Süre (sn)", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#444"
        ) %>%
        highcharter::hc_plotOptions(
          bar = list(borderWidth = 0)
        ) %>%
        highcharter::hc_add_series(
          name = "Ortalama Süre",
          data = lapply(1:nrow(data), function(i) {
            list(
              y = round(data$avg_duration[i], 2),
              total_calls = data$total_calls[i]
            )
          }),
          color = "#22c55e"
        ) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a",
          borderColor = "#333",
          style = list(color = "#fff"),
          pointFormat = "Ortalama: <b>{point.y} sn</b><br/>Toplam Yanıt: <b>{point.total_calls}</b>"
        ) %>%
        highcharter::hc_legend(enabled = FALSE) %>%
        highcharter::hc_credits(enabled = FALSE)
    })
    
    output$model_errors_chart <- highcharter::renderHighchart({
      data <- analytics_data()$model_errors
      if (nrow(data) == 0) return(highcharter::highchart())
      
      data <- data[order(-data$error_rate), ]
      
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
          gridLineColor = "#444"
        ) %>%
        highcharter::hc_plotOptions(
          bar = list(borderWidth = 0)
        ) %>%
        highcharter::hc_add_series(
          name = "Hata Oranı",
          data = lapply(1:nrow(data), function(i) {
            list(
              y = round(data$error_rate[i], 2),
              error_count = data$error_count[i]
            )
          }),
          color = "#ef4444"
        ) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a",
          borderColor = "#333",
          style = list(color = "#fff"),
          pointFormat = "Hata Oranı: <b>{point.y}%</b><br/>Hata Sayısı: <b>{point.error_count}</b>"
        ) %>%
        highcharter::hc_legend(enabled = FALSE) %>%
        highcharter::hc_credits(enabled = FALSE)
    })
    
    output$slowest_queries_table <- DT::renderDataTable({
      data <- analytics_data()$slowest_queries
      if (nrow(data) == 0) return(DT::datatable(data.frame()))
      
      data$row_num <- 1:nrow(data)
      data$ResponseDuration <- round(data$ResponseDuration, 2)
      data$query_time <- format(as.POSIXct(data$query_time), "%d.%m.%Y %H:%M")
      data <- data[, c("row_num", "ModelUsed", "ResponseDuration", "query_preview", "query_time")]
      colnames(data) <- c("#", "Model", "Süre (sn)", "Sorgu Önizleme", "Tarih")
      
      DT::datatable(
        data,
        options = list(
          dom = 't',
          pageLength = 20,
          scrollY = "300px",
          scrollCollapse = TRUE,
          ordering = FALSE,
          language = turkish_dt_language,
          columnDefs = list(
            list(className = 'dt-center', targets = c(0, 1, 2, 4)),
            list(className = 'row-number-col', targets = 0)
          )
        ),
        class = "admin-datatable",
        rownames = FALSE
      )
    })
    
    output$fastest_queries_table <- DT::renderDataTable({
      data <- analytics_data()$fastest_queries
      if (nrow(data) == 0) return(DT::datatable(data.frame()))
      
      data$row_num <- 1:nrow(data)
      data$ResponseDuration <- round(data$ResponseDuration, 2)
      data$query_time <- format(as.POSIXct(data$query_time), "%d.%m.%Y %H:%M")
      data <- data[, c("row_num", "ModelUsed", "ResponseDuration", "query_preview", "query_time")]
      colnames(data) <- c("#", "Model", "Süre (sn)", "Sorgu Önizleme", "Tarih")
      
      DT::datatable(
        data,
        options = list(
          dom = 't',
          pageLength = 20,
          scrollY = "300px",
          scrollCollapse = TRUE,
          ordering = FALSE,
          language = turkish_dt_language,
          columnDefs = list(
            list(className = 'dt-center', targets = c(0, 1, 2, 4)),
            list(className = 'row-number-col', targets = 0)
          )
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
            width = 12,
            div(
              class = "analytics-card",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("robot"), " Modellere Göre Geri Bildirim"),
                create_info_button("Her model için beğeni, beğenmeme sayıları ve toplam yanıt sayısı. Beğeni/beğenmeme oranları da hesaplanır.")
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
                h4(class = "card-title", icon("stopwatch"), " Yanıt Süresi ve Geri Bildirim İlişkisi"),
                create_info_button("Yanıt süresine göre geri bildirim dağılımı. Farklı süre aralıklarında kullanıcıların beğeni/beğenmeme davranışlarını gösterir.")
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
                h4(class = "card-title", icon("text-width"), " Yanıt Uzunluğu ve Geri Bildirim İlişkisi"),
                create_info_button("Yanıt karakter uzunluğuna göre geri bildirim dağılımı. Uzun veya kısa yanıtların kullanıcı memnuniyetini nasıl etkilediğini gösterir.")
              ),
              highcharter::highchartOutput(ns("response_length_feedback_chart"), height = "300px")
            )
          )
        )
      )
    })
    
    output$model_feedback_table <- DT::renderDataTable({
      data <- analytics_data()$model_feedback
      if (nrow(data) == 0) return(DT::datatable(data.frame()))
      
      data$like_ratio <- ifelse(data$total_responses > 0, round((data$likes / data$total_responses) * 100, 1), 0)
      data$dislike_ratio <- ifelse(data$total_responses > 0, round((data$dislikes / data$total_responses) * 100, 1), 0)
      
      data <- data[, c("ModelUsed", "likes", "dislikes", "total_responses", "like_ratio", "dislike_ratio")]
      colnames(data) <- c("Model", "Beğeni", "Beğenmeme", "Toplam Yanıt", "Beğeni Oranı (%)", "Beğenmeme Oranı (%)")
      
      DT::datatable(
        data,
        options = list(
          dom = 'ftp',
          pageLength = 15,
          language = turkish_dt_language,
          columnDefs = list(
            list(className = 'dt-center', targets = "_all")
          )
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
      data <- data[!is.na(data$duration_bucket), ]
      
      if (nrow(data) == 0) return(highcharter::highchart())
      
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
          gridLineColor = "#444"
        ) %>%
        highcharter::hc_plotOptions(
          column = list(borderWidth = 0)
        ) %>%
        highcharter::hc_add_series(name = "Beğeni", data = data$likes, color = "#22c55e") %>%
        highcharter::hc_add_series(name = "Beğenmeme", data = data$dislikes, color = "#ef4444") %>%
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
      data <- data[!is.na(data$length_bucket), ]
      
      if (nrow(data) == 0) return(highcharter::highchart())
      
      highcharter::highchart() %>%
        highcharter::hc_chart(type = "column", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = as.character(data$length_bucket),
          labels = list(style = list(color = "#999"))
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Geri Bildirim Sayısı", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#444"
        ) %>%
        highcharter::hc_plotOptions(
          column = list(borderWidth = 0)
        ) %>%
        highcharter::hc_add_series(name = "Beğeni", data = data$likes, color = "#22c55e") %>%
        highcharter::hc_add_series(name = "Beğenmeme", data = data$dislikes, color = "#ef4444") %>%
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
      
      avg_msg <- if (nrow(data$avg_messages_per_chat) > 0 && !is.na(data$avg_messages_per_chat$avg_msg[1])) 
        sprintf("%.1f", data$avg_messages_per_chat$avg_msg[1]) else "N/A"
      
      total_feedback <- if (nrow(data$total_feedback_count) > 0) data$total_feedback_count$cnt[1] else 0
      
      tagList(
        div(
          class = "metrics-grid metrics-grid-small",
          create_metric_card("Bounce Rate", bounce_rate, "door-open", "orange", tooltip = "Tek yanıtlık söyleşi oranı. Kullanıcının sadece bir soru sorup bıraktığı söyleşilerin yüzdesi. Düşük değerler daha iyi etkileşimi gösterir."),
          create_metric_card("Ortalama Mesaj/Söyleşi", avg_msg, "comments", "blue", tooltip = "Her söyleşideki ortalama mesaj sayısı. Söyleşilerin derinliğini ve kullanıcı etkileşimini gösterir."),
          create_metric_card("Toplam Geri Bildirim", format(total_feedback, big.mark = "."), "star", "purple", tooltip = "Kullanıcıların verdiği toplam geri bildirim sayısı (beğeni + beğenmeme).")
        ),
        fluidRow(
          column(
            width = 6,
            div(
              class = "analytics-card",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("code"), " Kodlu ve Kodsuz Yanıtlar"),
                create_info_button("YZ yanıtlarının kod içerip içermediğine göre dağılımı. ``` işareti tespit edilerek kodlu yanıtlar belirlenir.")
              ),
              highcharter::highchartOutput(ns("code_ratio_chart"), height = "300px")
            )
          ),
          column(
            width = 6,
            div(
              class = "analytics-card",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("list-ol"), " En Uzun Söyleşiler"),
                create_info_button("En fazla mesaj içeren söyleşilerin listesi. Kullanıcı ve söyleşi başlığı ile birlikte mesaj sayısı gösterilir.")
              ),
              div(class = "table-container scrollable-table", DT::dataTableOutput(ns("longest_chats_table")))
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
                create_info_button("Kullanıcıların en çok yeniden yanıt oluşturma isteğinde bulunduğu söyleşiler. Model bilgisi de dahildir.")
              ),
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
            borderWidth = 0,
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
    
    output$longest_chats_table <- DT::renderDataTable({
      data <- analytics_data()$longest_chats
      if (nrow(data) == 0) return(DT::datatable(data.frame()))
      
      colnames(data) <- c("Söyleşi Başlığı", "Mesaj Sayısı", "Kullanıcı")
      
      DT::datatable(
        data,
        options = list(
          dom = 't',
          pageLength = 10,
          scrollY = "250px",
          scrollCollapse = TRUE,
          ordering = FALSE,
          language = turkish_dt_language,
          columnDefs = list(
            list(className = 'dt-center', targets = c(1, 2))
          )
        ),
        class = "admin-datatable",
        rownames = FALSE
      )
    })
    
    output$regenerated_table <- DT::renderDataTable({
      data <- analytics_data()$regenerated_responses
      if (nrow(data) == 0) return(DT::datatable(data.frame()))
      
      data <- data[, c("ChatTitle", "ModelUsed", "regen_count")]
      colnames(data) <- c("Söyleşi Başlığı", "Model", "Yeniden Oluşturma Sayısı")
      
      DT::datatable(
        data,
        options = list(
          dom = 't',
          pageLength = 20,
          scrollY = "250px",
          scrollCollapse = TRUE,
          ordering = FALSE,
          language = turkish_dt_language,
          columnDefs = list(
            list(className = 'dt-center', targets = c(1, 2))
          )
        ),
        class = "admin-datatable",
        rownames = FALSE
      )
    })
    
    output$time_analysis_content <- renderUI({
      data <- analytics_data()
      
      peak_hours_text <- ""
      if (nrow(data$peak_hours) > 0) {
        peak_hours_text <- paste(sprintf("%02d:00", data$peak_hours$hour_num[1:min(3, nrow(data$peak_hours))]), collapse = ", ")
      }
      
      tagList(
        div(
          class = "metrics-grid metrics-grid-small",
          create_metric_card("En Yoğun Saatler", peak_hours_text, "clock", "cyan", tooltip = "Sistemin en yoğun kullanıldığı ilk 3 saat dilimi."),
          create_metric_card("Haftalık Trend", if (nrow(data$weekly_trend) > 0) paste0(nrow(data$weekly_trend), " hafta") else "N/A", "calendar-alt", "green", tooltip = "Son 12 haftadaki haftalık söyleşi trend verisi.")
        ),
        fluidRow(
          column(
            width = 12,
            div(
              class = "analytics-card",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("chart-line"), " Haftalık Eğilim (Son 12 Hafta)"),
                create_info_button("Son 12 haftadaki söyleşi sayısı trendi. Haftalık kullanım kalıplarını ve büyüme/düşüş eğilimlerini gösterir.")
              ),
              highcharter::highchartOutput(ns("weekly_trend_chart"), height = "300px")
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
                h4(class = "card-title", icon("user-plus"), " Yeni Kullanıcı Aktivasyon Analizi"),
                create_info_button("Birden fazla söyleşi başlatan kullanıcıların aktivasyon analizi. İlk söyleşi tarihi, toplam söyleşi sayısı ve aktif gün aralığı gösterilir.")
              ),
              div(class = "table-container", DT::dataTableOutput(ns("activation_table")))
            )
          )
        )
      )
    })
    
    output$weekly_trend_chart <- highcharter::renderHighchart({
      data <- analytics_data()$weekly_trend
      if (nrow(data) == 0) return(highcharter::highchart())
      
      data$week_label <- paste0("Hafta ", data$week_num)
      
      highcharter::highchart() %>%
        highcharter::hc_chart(type = "line", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = data$week_label,
          labels = list(style = list(color = "#999"))
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Söyleşi Sayısı", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#444"
        ) %>%
        highcharter::hc_add_series(
          name = "Söyleşi",
          data = data$chat_count,
          color = "#22c55e",
          marker = list(enabled = TRUE, radius = 4)
        ) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a",
          borderColor = "#333",
          style = list(color = "#fff")
        ) %>%
        highcharter::hc_legend(enabled = FALSE) %>%
        highcharter::hc_credits(enabled = FALSE)
    })
    
    output$activation_table <- DT::renderDataTable({
      data <- analytics_data()$user_activation
      if (nrow(data) == 0) return(DT::datatable(data.frame()))
      
      data$first_chat <- format(as.POSIXct(data$first_chat), "%d.%m.%Y")
      colnames(data) <- c("Kullanıcı", "İlk Söyleşi", "Toplam Söyleşi", "Aktif Gün Aralığı")
      
      DT::datatable(
        data,
        options = list(
          dom = 'ftp',
          pageLength = 15,
          language = turkish_dt_language,
          columnDefs = list(
            list(className = 'dt-right', targets = "_all")
          )
        ),
        class = "admin-datatable",
        rownames = FALSE
      )
    })
    
  })
}
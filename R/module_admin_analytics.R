# R/module_admin_analytics.R

adminAnalyticsUI <- function(id) {
  ns <- NS(id)
  
  tagList(
    tags$head(
      tags$link(rel = "stylesheet", type = "text/css", href = "css/admin_analytics.css")
    ),
    div(
      class = "admin-analytics-container",
      div(
        class = "admin-header-fixed",
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
                value = "overview"
              ),
              tabPanel(
                title = tags$span(title = "Kullanıcı aktiviteleri ve davranış analizi", tagList(icon("users"), " Kullanıcı Analizi")),
                value = "users"
              ),
              tabPanel(
                title = tags$span(title = "Yapay zeka model performansı ve hata oranları", tagList(icon("robot"), " YZ Performansı")),
                value = "ai_perf"
              ),
              tabPanel(
                title = tags$span(title = "Kullanıcı geri bildirimleri ve memnuniyet analizi", tagList(icon("thumbs-up"), " Geri Bildirim")),
                value = "feedback"
              ),
              tabPanel(
                title = tags$span(title = "Söyleşi kalitesi ve içerik analizi", tagList(icon("comments"), " Sohbet Kalitesi")),
                value = "chat_quality"
              ),
              tabPanel(
                title = tags$span(title = "Zamana göre kullanım ve aktivite analizi", tagList(icon("clock"), " Zaman Analizi")),
                value = "time_analysis"
              ),
              tabPanel(
                title = tags$span(title = "Gelişmiş sistem metrikleri ve detaylı analizler", tagList(icon("chart-area"), " Gelişmiş Analizler")),
                value = "advanced_analytics"
              )
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
    
    format_number <- function(x) {
      if (is.na(x) || is.null(x)) return("0")
      as.character(as.integer(x))
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
            CAST(SUM(CASE WHEN ResponseSuccess = 0 THEN 1 ELSE 0 END) AS FLOAT) / NULLIF(COUNT(*), 0) * 100 as rate,
            SUM(CASE WHEN ResponseSuccess = 0 THEN 1 ELSE 0 END) as error_count,
            COUNT(*) as total_count
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
            u.KullaniciAdi as user_name,
            u.KaynakAdi as full_name,
            COUNT(m.MessageID) as message_count
          FROM MB_Users u
          JOIN MB_Chats c ON u.UserID = c.UserID
          JOIN MB_Messages m ON c.ChatID = m.ChatID
          WHERE c.IsDeleted = 0 AND m.MessageType = 'user'
          GROUP BY u.KullaniciAdi, u.KaynakAdi
          ORDER BY message_count DESC
        "),
        daily_trend = safe_query("
          SELECT 
            CAST(CreateTimestamp AS DATE) as chat_date,
            COUNT(*) as chat_count
          FROM MB_Chats
          WHERE CreateTimestamp >= DATEADD(day, -30, GETDATE()) AND IsDeleted = 0
          GROUP BY CAST(CreateTimestamp AS DATE)
          ORDER BY chat_date
        "),
        avg_chat_length = safe_query("
          SELECT AVG(CAST(msg_count AS FLOAT)) as avg_len
          FROM (
            SELECT ChatID, COUNT(*) as msg_count 
            FROM MB_Messages 
            GROUP BY ChatID
          ) sub
        "),
        model_performance = safe_query("
          SELECT 
            ModelUsed,
            AVG(ResponseDuration) as avg_duration,
            COUNT(*) as total_count
          FROM MB_Usage_Log
          WHERE ResponseSuccess = 1 AND ResponseDuration > 0
          GROUP BY ModelUsed
          ORDER BY avg_duration ASC
        "),
        slowest_queries = safe_query("
          SELECT TOP 20
            u.ModelUsed,
            u.ResponseDuration,
            LEFT(m.MessageContent, 100) as query_preview,
            m.MessageTimestamp as query_time
          FROM MB_Usage_Log u
          JOIN MB_Messages m ON u.MessageID = m.MessageID
          WHERE u.ResponseSuccess = 1 AND u.ResponseDuration > 0
          ORDER BY u.ResponseDuration DESC
        "),
        fastest_queries = safe_query("
          SELECT TOP 20
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
            SUM(CASE WHEN ResponseSuccess = 0 THEN 1 ELSE 0 END) as error_count,
            COUNT(*) as total_count,
            CAST(SUM(CASE WHEN ResponseSuccess = 0 THEN 1 ELSE 0 END) AS FLOAT) / NULLIF(COUNT(*), 0) * 100 as error_rate
          FROM MB_Usage_Log
          GROUP BY ModelUsed
          ORDER BY error_rate ASC
        "),
        model_feedback = safe_query("
          SELECT 
            u.ModelUsed,
            SUM(CASE WHEN f.FeedbackType = 'like' THEN 1 ELSE 0 END) as likes,
            SUM(CASE WHEN f.FeedbackType = 'dislike' THEN 1 ELSE 0 END) as dislikes,
            COUNT(DISTINCT u.LogID) as total_responses
          FROM MB_Usage_Log u
          LEFT JOIN MB_Messages m ON u.MessageID = m.MessageID
          LEFT JOIN MB_Feedback f ON m.MessageID = f.MessageID
          GROUP BY u.ModelUsed
          ORDER BY total_responses DESC
        "),
        power_users = safe_query("
          SELECT TOP 15
            u.KullaniciAdi as user_name,
            u.KaynakAdi as full_name,
            COUNT(DISTINCT c.ChatID) as chat_count,
            COUNT(m.MessageID) as total_messages,
            CAST(COUNT(m.MessageID) AS FLOAT) / NULLIF(COUNT(DISTINCT c.ChatID), 0) as avg_chat_length
          FROM MB_Users u
          JOIN MB_Chats c ON u.UserID = c.UserID
          JOIN MB_Messages m ON c.ChatID = m.ChatID
          WHERE c.IsDeleted = 0
          GROUP BY u.UserID, u.KullaniciAdi, u.KaynakAdi
          ORDER BY total_messages DESC
        "),
        file_uploaders = safe_query("
          SELECT 
            u.KullaniciAdi as user_name,
            u.KaynakAdi as full_name,
            COUNT(CASE WHEN m.MessageContent LIKE '%[Dosya:%' THEN 1 END) as file_count,
            MAX(m.MessageTimestamp) as last_upload
          FROM MB_Messages m
          JOIN MB_Chats c ON m.ChatID = c.ChatID
          JOIN MB_Users u ON c.UserID = u.UserID
          WHERE m.MessageContent LIKE '%[Dosya:%' AND c.IsDeleted = 0
          GROUP BY u.KullaniciAdi, u.KaynakAdi
          ORDER BY file_count DESC
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
        longest_chats = safe_query("
          SELECT TOP 20
            c.ChatTitle,
            COUNT(m.MessageID) as msg_count,
            u.KullaniciAdi as user_name,
            u.KaynakAdi as full_name
          FROM MB_Chats c
          JOIN MB_Messages m ON c.ChatID = m.ChatID
          JOIN MB_Users u ON c.UserID = u.UserID
          WHERE c.IsDeleted = 0
          GROUP BY c.ChatID, c.ChatTitle, u.KullaniciAdi, u.KaynakAdi
          ORDER BY msg_count DESC
        "),
        weekly_trend = safe_query("
          SELECT TOP 24
            DATEPART(YEAR, CreateTimestamp) as year_num,
            DATEPART(WEEK, CreateTimestamp) as week_num,
            MIN(CAST(CreateTimestamp AS DATE)) as week_start,
            MAX(CAST(CreateTimestamp AS DATE)) as week_end,
            COUNT(*) as cnt
          FROM MB_Chats
          WHERE IsDeleted = 0 AND CreateTimestamp >= DATEADD(week, -24, GETDATE())
          GROUP BY DATEPART(YEAR, CreateTimestamp), DATEPART(WEEK, CreateTimestamp)
          ORDER BY year_num DESC, week_num DESC
        "),
        new_user_activation = safe_query("
          SELECT TOP 20
            u.KullaniciAdi as user_name,
            u.KaynakAdi as full_name,
            MIN(c.CreateTimestamp) as first_chat,
            COUNT(DISTINCT c.ChatID) as chat_count,
            DATEDIFF(day, MIN(c.CreateTimestamp), MAX(c.CreateTimestamp)) as active_days
          FROM MB_Users u
          JOIN MB_Chats c ON u.UserID = c.UserID
          WHERE c.IsDeleted = 0
          GROUP BY u.UserID, u.KullaniciAdi, u.KaynakAdi
          HAVING COUNT(DISTINCT c.ChatID) > 1
          ORDER BY first_chat DESC
        "),
        peak_hours = safe_query("
          SELECT TOP 5
            DATEPART(HOUR, CreateTimestamp) as hour_num,
            COUNT(*) as cnt
          FROM MB_Chats
          WHERE IsDeleted = 0
          GROUP BY DATEPART(HOUR, CreateTimestamp)
          ORDER BY cnt DESC
        "),
        total_feedback_count = safe_query("SELECT COUNT(*) as cnt FROM MB_Feedback"),
        avg_messages_per_chat = safe_query("
          SELECT AVG(CAST(msg_count AS FLOAT)) as avg_msg
          FROM (
            SELECT ChatID, COUNT(*) as msg_count
            FROM MB_Messages
            GROUP BY ChatID
          ) sub
        "),
        user_retention = safe_query("
          SELECT 
            COUNT(DISTINCT CASE WHEN chat_count > 1 THEN UserID END) as returning_users,
            COUNT(DISTINCT UserID) as total_users
          FROM (
            SELECT UserID, COUNT(*) as chat_count
            FROM MB_Chats
            WHERE IsDeleted = 0
            GROUP BY UserID
          ) sub
        "),
        monthly_growth = safe_query("
          SELECT 
            DATEPART(YEAR, CreateTimestamp) as year_num,
            DATEPART(MONTH, CreateTimestamp) as month_num,
            COUNT(*) as chat_count,
            COUNT(DISTINCT UserID) as unique_users
          FROM MB_Chats
          WHERE IsDeleted = 0 AND CreateTimestamp >= DATEADD(month, -6, GETDATE())
          GROUP BY DATEPART(YEAR, CreateTimestamp), DATEPART(MONTH, CreateTimestamp)
          ORDER BY year_num, month_num
        "),
        avg_session_duration = safe_query("
          SELECT AVG(duration_minutes) as avg_duration
          FROM (
            SELECT 
              ChatID,
              DATEDIFF(MINUTE, MIN(MessageTimestamp), MAX(MessageTimestamp)) as duration_minutes
            FROM MB_Messages
            GROUP BY ChatID
            HAVING COUNT(*) > 1
          ) sub
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
            c.ChatTitle,
            STUFF((
              SELECT ', ' + ul2.ModelUsed
              FROM MB_Usage_Log ul2
              WHERE ul2.ChatID = c.ChatID
              GROUP BY ul2.ModelUsed
              FOR XML PATH('')
            ), 1, 2, '') as ModelUsed,
            COUNT(DISTINCT ul.LogID) as regen_count
          FROM MB_Chats c
          JOIN MB_Usage_Log ul ON c.ChatID = ul.ChatID
          WHERE c.IsDeleted = 0
          GROUP BY c.ChatID, c.ChatTitle
          HAVING COUNT(DISTINCT ul.LogID) > (
            SELECT COUNT(*) FROM MB_Messages m2 WHERE m2.ChatID = c.ChatID AND m2.MessageType = 'user'
          )
          ORDER BY regen_count DESC
        "),
        response_time_feedback = safe_query("
          SELECT 
            CASE 
              WHEN u.ResponseDuration <= 5 THEN '0-5 sn'
              WHEN u.ResponseDuration <= 10 THEN '5-10 sn'
              WHEN u.ResponseDuration <= 20 THEN '10-20 sn'
              ELSE '20+ sn'
            END as duration_bucket,
            SUM(CASE WHEN f.FeedbackType = 'like' THEN 1 ELSE 0 END) as likes,
            SUM(CASE WHEN f.FeedbackType = 'dislike' THEN 1 ELSE 0 END) as dislikes
          FROM MB_Usage_Log u
          JOIN MB_Messages m ON u.MessageID = m.MessageID
          LEFT JOIN MB_Feedback f ON m.MessageID = f.MessageID
          WHERE u.ResponseSuccess = 1
          GROUP BY CASE 
            WHEN u.ResponseDuration <= 5 THEN '0-5 sn'
            WHEN u.ResponseDuration <= 10 THEN '5-10 sn'
            WHEN u.ResponseDuration <= 20 THEN '10-20 sn'
            ELSE '20+ sn'
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
            SUM(CASE WHEN f.FeedbackType = 'dislike' THEN 1 ELSE 0 END) as dislikes
          FROM MB_Messages m
          LEFT JOIN MB_Feedback f ON m.MessageID = f.MessageID
          WHERE m.MessageType = 'ai'
          GROUP BY CASE 
            WHEN LEN(m.MessageContent) < 500 THEN 'Kısa (< 500)'
            WHEN LEN(m.MessageContent) < 1500 THEN 'Orta (500-1500)'
            WHEN LEN(m.MessageContent) < 3000 THEN 'Uzun (1500-3000)'
            ELSE 'Çok Uzun (> 3000)'
          END
        "),
        model_usage_trend = safe_query("
          SELECT 
            CAST(u.LogTimestamp AS DATE) as usage_date,
            u.ModelUsed,
            COUNT(*) as cnt
          FROM MB_Usage_Log u
          WHERE u.LogTimestamp >= DATEADD(day, -14, GETDATE())
          GROUP BY CAST(u.LogTimestamp AS DATE), u.ModelUsed
          ORDER BY usage_date
        "),
        user_activity_heatmap = safe_query("
          SELECT 
            DATEPART(WEEKDAY, CreateTimestamp) as day_num,
            DATEPART(HOUR, CreateTimestamp) as hour_num,
            COUNT(*) as cnt
          FROM MB_Chats
          WHERE IsDeleted = 0 AND CreateTimestamp >= DATEADD(day, -30, GETDATE())
          GROUP BY DATEPART(WEEKDAY, CreateTimestamp), DATEPART(HOUR, CreateTimestamp)
        "),
        avg_response_by_hour = safe_query("
          SELECT 
            DATEPART(HOUR, LogTimestamp) as hour_num,
            AVG(ResponseDuration) as avg_duration
          FROM MB_Usage_Log
          WHERE ResponseSuccess = 1
          GROUP BY DATEPART(HOUR, LogTimestamp)
          ORDER BY hour_num
        "),
        chat_length_distribution = safe_query("
          SELECT 
            CASE 
              WHEN msg_count <= 2 THEN '1-2 mesaj'
              WHEN msg_count <= 5 THEN '3-5 mesaj'
              WHEN msg_count <= 10 THEN '6-10 mesaj'
              WHEN msg_count <= 20 THEN '11-20 mesaj'
              ELSE '20+ mesaj'
            END as length_bucket,
            COUNT(*) as chat_count
          FROM (
            SELECT ChatID, COUNT(*) as msg_count
            FROM MB_Messages
            GROUP BY ChatID
          ) sub
          GROUP BY CASE 
            WHEN msg_count <= 2 THEN '1-2 mesaj'
            WHEN msg_count <= 5 THEN '3-5 mesaj'
            WHEN msg_count <= 10 THEN '6-10 mesaj'
            WHEN msg_count <= 20 THEN '11-20 mesaj'
            ELSE '20+ mesaj'
          END
        "),
        first_response_success = safe_query("
          SELECT 
            SUM(CASE WHEN first_feedback = 'like' THEN 1 ELSE 0 END) as first_likes,
            SUM(CASE WHEN first_feedback = 'dislike' THEN 1 ELSE 0 END) as first_dislikes,
            COUNT(*) as total_first_responses
          FROM (
            SELECT 
              c.ChatID,
              (SELECT TOP 1 f.FeedbackType 
               FROM MB_Messages m 
               JOIN MB_Feedback f ON m.MessageID = f.MessageID 
               WHERE m.ChatID = c.ChatID AND m.MessageType = 'ai'
               ORDER BY m.MessageOrder) as first_feedback
            FROM MB_Chats c
            WHERE c.IsDeleted = 0
          ) sub
          WHERE first_feedback IS NOT NULL
        ")
      )
    })
    
    create_metric_card <- function(title, value, icon_name, color_class = "primary", subtitle = NULL, tooltip = NULL) {
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
    
    output$tab_content_area <- renderUI({
      tab <- input$admin_tabs
      if (is.null(tab)) tab <- "overview"
      
      switch(tab,
        "overview" = overview_ui(),
        "users" = users_ui(),
        "ai_perf" = ai_perf_ui(),
        "feedback" = feedback_ui(),
        "chat_quality" = chat_quality_ui(),
        "time_analysis" = time_analysis_ui(),
        "advanced_analytics" = advanced_analytics_ui(),
        overview_ui()
      )
    })
    
    overview_ui <- function() {
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
      
      tagList(
        div(
          class = "metrics-grid",
          create_metric_card("Toplam Kullanıcı", format_number(total_users), "users", "blue", 
            tooltip = "Sistemde kayıtlı olan tüm benzersiz kullanıcıların toplam sayısı."),
          create_metric_card("Bugün Aktif", format_number(active_today), "user-clock", "green", 
            tooltip = "Bugün en az bir söyleşi başlatan veya mevcut söyleşilerine devam eden kullanıcı sayısı."),
          create_metric_card("Toplam Söyleşi", format_number(total_chats), "comments", "purple", 
            tooltip = "Sistemde oluşturulan tüm söyleşi oturumlarının toplam sayısı."),
          create_metric_card("Toplam Mesaj", format_number(total_messages), "envelope", "cyan", 
            tooltip = "Tüm söyleşilerdeki kullanıcı ve YZ mesajlarının toplam sayısı."),
          create_metric_card("YZ Çağrısı", format_number(total_ai_calls), "robot", "orange", 
            tooltip = "Yapay zeka API'sine yapılan toplam istek sayısı."),
          create_metric_card("Ortalama Yanıt Süresi", avg_response, "clock", "green", 
            tooltip = "Başarılı YZ yanıtlarının ortalama süresi (saniye)."),
          create_metric_card("Hata Oranı", error_rate, "exclamation-triangle", "red", 
            tooltip = "Başarısız YZ çağrılarının oranı."),
          create_metric_card("Ort. Söyleşi Uzunluğu", avg_chat_len, "comment-dots", "blue", 
            tooltip = "Her söyleşideki ortalama mesaj sayısı.")
        ),
        fluidRow(
          column(
            width = 6,
            div(
              class = "analytics-card",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("chart-area"), " Günlük Söyleşi Trendi (Son 30 Gün)"),
                create_info_button("Son 30 gündeki günlük söyleşi sayısı trendi.")
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
                create_info_button("Kullanıcıların YZ yanıtlarına verdikleri beğeni ve beğenmeme geri bildirimlerinin dağılımı.")
              ),
              highcharter::highchartOutput(ns("feedback_donut_chart"), height = "300px")
            )
          )
        )
      )
    }
    
    users_ui <- function() {
      tagList(
        fluidRow(
          column(
            width = 6,
            div(
              class = "analytics-card",
              style = "min-height: 420px;",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("trophy"), " En Aktif Kullanıcılar"),
                create_info_button("En fazla mesaj gönderen ilk 10 kullanıcının listesi.")
              ),
              highcharter::highchartOutput(ns("top_users_chart"), height = "350px")
            )
          ),
          column(
            width = 6,
            div(
              class = "analytics-card",
              style = "min-height: 420px;",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("star"), " Güçlü Kullanıcılar"),
                create_info_button("En yoğun sistem kullanıcıları.")
              ),
              div(class = "table-container", style = "height: 320px; overflow-y: auto;", DT::dataTableOutput(ns("power_users_table")))
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
                create_info_button("Haftanın günlerine göre söyleşi dağılımı.")
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
              div(class = "table-container", DT::dataTableOutput(ns("file_uploaders_table")))
            )
          )
        )
      )
    }
    
    ai_perf_ui <- function() {
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
                create_info_button("Her modelin hata oranını gösterir (%). Tooltip'te hata sayısı ve toplam çağrı sayısı gösterilir.")
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
              style = "min-height: 480px;",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("hourglass-end"), " En Yavaş 20 Sorgu"),
                create_info_button("En uzun süren 20 YZ yanıtının listesi.")
              ),
              div(class = "table-container", DT::dataTableOutput(ns("slowest_queries_table")))
            )
          ),
          column(
            width = 6,
            div(
              class = "analytics-card",
              style = "min-height: 480px;",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("bolt"), " En Hızlı 20 Sorgu"),
                create_info_button("En kısa sürede yanıtlanan 20 YZ sorgusunun listesi.")
              ),
              div(class = "table-container", DT::dataTableOutput(ns("fastest_queries_table")))
            )
          )
        )
      )
    }
    
    feedback_ui <- function() {
      tagList(
        fluidRow(
          column(
            width = 12,
            div(
              class = "analytics-card",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("robot"), " Modellere Göre Geri Bildirim"),
                create_info_button("Her model için beğeni, beğenmeme sayıları ve toplam yanıt sayısı. Oranlar toplam yanıta göre hesaplanır.")
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
                h4(class = "card-title", icon("text-height"), " Yanıt Uzunluğu ve Geri Bildirim"),
                create_info_button("Yanıt uzunluğuna göre geri bildirim dağılımı.")
              ),
              highcharter::highchartOutput(ns("response_length_feedback_chart"), height = "300px")
            )
          )
        )
      )
    }
    
    chat_quality_ui <- function() {
      data <- analytics_data()
      
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
          class = "metrics-grid metrics-grid-small",
          create_metric_card("Hemen Çıkma Oranı", bounce_rate, "door-open", "red",
            tooltip = "2 veya daha az mesaj içeren söyleşilerin oranı."),
          create_metric_card("Ortalama Mesaj/Söyleşi", avg_msg, "comment-dots", "blue",
            tooltip = "Her söyleşideki ortalama mesaj sayısı."),
          create_metric_card("Kullanıcı Tutma Oranı", retention_rate, "user-check", "green",
            tooltip = "Birden fazla söyleşi başlatan kullanıcıların oranı."),
          create_metric_card("Ort. Oturum Süresi", avg_session, "hourglass-half", "purple",
            tooltip = "Söyleşilerin ortalama süresi (dakika)."),
          create_metric_card("Toplam Geri Bildirim", format_number(total_feedback), "thumbs-up", "cyan",
            tooltip = "Alınan toplam geri bildirim sayısı.")
        ),
        fluidRow(
          column(
            width = 6,
            div(
              class = "analytics-card",
              style = "min-height: 380px;",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("chart-pie"), " Kodlu ve Kodsuz Yanıtlar"),
                create_info_button("Kod içeren ve içermeyen YZ yanıtlarının dağılımı.")
              ),
              highcharter::highchartOutput(ns("code_ratio_chart"), height = "300px")
            )
          ),
          column(
            width = 6,
            div(
              class = "analytics-card",
              style = "min-height: 380px;",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("comments"), " En Uzun Söyleşiler"),
                create_info_button("En fazla mesaj içeren söyleşilerin listesi.")
              ),
              div(class = "table-container", style = "height: 280px; overflow-y: auto;", DT::dataTableOutput(ns("longest_chats_table")))
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
                create_info_button("YZ yanıtlarının kullanıcı mesajlarından fazla olduğu durumlar.")
              ),
              div(class = "table-container scrollable-table", DT::dataTableOutput(ns("regenerated_table")))
            )
          )
        )
      )
    }
    
    time_analysis_ui <- function() {
      data <- analytics_data()
      
      peak_hours_text <- ""
      if (nrow(data$peak_hours) > 0) {
        peak_hours_text <- paste(sprintf("%02d:00", data$peak_hours$hour_num[1:min(3, nrow(data$peak_hours))]), collapse = ", ")
      }
      
      weekly_count <- if (nrow(data$weekly_trend) > 0) nrow(data$weekly_trend) else 0
      
      monthly_growth_text <- "N/A"
      if (nrow(data$monthly_growth) >= 2) {
        last_month <- data$monthly_growth$chat_count[nrow(data$monthly_growth)]
        prev_month <- data$monthly_growth$chat_count[nrow(data$monthly_growth) - 1]
        if (prev_month > 0) {
          growth_pct <- ((last_month - prev_month) / prev_month) * 100
          monthly_growth_text <- sprintf("%+.1f%%", growth_pct)
        }
      }
      
      tagList(
        div(
          class = "metrics-grid metrics-grid-small",
          create_metric_card("En Yoğun Saatler", peak_hours_text, "clock", "cyan",
            tooltip = "Sistemin en yoğun kullanıldığı ilk 3 saat dilimi."),
          create_metric_card("Haftalık Veri", paste0(weekly_count, " hafta"), "calendar-alt", "green",
            tooltip = "Mevcut haftalık trend verisinin kapsadığı hafta sayısı."),
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
              class = "analytics-card",
              style = "min-height: 420px;",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("user-plus"), " Yeni Kullanıcı Aktivasyon Analizi"),
                create_info_button("Birden fazla söyleşi başlatan kullanıcıların aktivasyon analizi.")
              ),
              div(class = "table-container", style = "height: 320px; overflow-y: auto;", DT::dataTableOutput(ns("new_user_activation_table")))
            )
          ),
          column(
            width = 6,
            div(
              class = "analytics-card",
              style = "min-height: 420px;",
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
    
    advanced_analytics_ui <- function() {
      data <- analytics_data()
      
      first_response_like <- "N/A"
      if (nrow(data$first_response_success) > 0) {
        frs <- data$first_response_success
        total <- frs$first_likes[1] + frs$first_dislikes[1]
        if (total > 0) {
          first_response_like <- sprintf("%.1f%%", (frs$first_likes[1] / total) * 100)
        }
      }
      
      tagList(
        div(
          class = "metrics-grid metrics-grid-small",
          create_metric_card("İlk Yanıt Beğeni Oranı", first_response_like, "check-circle", "green",
            tooltip = "Her söyleşideki ilk YZ yanıtının beğenilme oranı.")
        ),
        fluidRow(
          column(
            width = 6,
            div(
              class = "analytics-card",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("layer-group"), " Model Kullanım Trendi (Son 14 Gün)"),
                create_info_button("Son 14 gündeki model kullanım dağılımı.")
              ),
              highcharter::highchartOutput(ns("model_usage_trend_chart"), height = "300px")
            )
          ),
          column(
            width = 6,
            div(
              class = "analytics-card",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("th"), " Söyleşi Uzunluğu Dağılımı"),
                create_info_button("Söyleşilerin mesaj sayısına göre dağılımı.")
              ),
              highcharter::highchartOutput(ns("chat_length_dist_chart"), height = "300px")
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
              highcharter::highchartOutput(ns("avg_response_by_hour_chart"), height = "300px")
            )
          )
        )
      )
    }
    
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
        highcharter::hc_plotOptions(
          areaspline = list(
            marker = list(enabled = FALSE),
            lineWidth = 2.5
          )
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
    
    output$feedback_donut_chart <- highcharter::renderHighchart({
      data <- analytics_data()$feedback_summary
      if (nrow(data) == 0) return(highcharter::highchart())
      
      likes <- sum(data$cnt[data$FeedbackType == "like"], na.rm = TRUE)
      dislikes <- sum(data$cnt[data$FeedbackType == "dislike"], na.rm = TRUE)
      
      chart_data <- list(
        list(name = "Beğeni", y = likes, color = "#10b981"),
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
    
    output$top_users_chart <- highcharter::renderHighchart({
      data <- analytics_data()$top_users
      if (nrow(data) == 0) return(highcharter::highchart())
      
      data <- head(data, 10)
      
      chart_data <- lapply(1:nrow(data), function(i) {
        list(
          y = data$message_count[i],
          name = data$user_name[i],
          full_name = if (!is.na(data$full_name[i]) && nzchar(data$full_name[i])) data$full_name[i] else data$user_name[i]
        )
      })
      
      display_names <- sapply(1:nrow(data), function(i) {
        if (!is.na(data$full_name[i]) && nzchar(data$full_name[i])) data$full_name[i] else data$user_name[i]
      })
      
      highcharter::highchart() %>%
        highcharter::hc_chart(type = "bar", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = display_names,
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
          data = chart_data,
          colors = c("#ff6b35", "#f7931e", "#fbbf24", "#22c55e", "#3b82f6", 
                     "#8b5cf6", "#ec4899", "#06b6d4", "#84cc16", "#f43f5e")
        ) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a",
          borderColor = "#333",
          style = list(color = "#fff"),
          formatter = JS("function() { return '<b>' + this.point.full_name + '</b><br/>Mesaj: ' + this.y; }")
        ) %>%
        highcharter::hc_legend(enabled = FALSE) %>%
        highcharter::hc_credits(enabled = FALSE)
    })
    
    output$power_users_table <- DT::renderDataTable({
      data <- analytics_data()$power_users
      if (nrow(data) == 0) return(DT::datatable(data.frame()))
      
      data$row_num <- 1:nrow(data)
      data$avg_chat_length <- round(data$avg_chat_length, 1)
      data$display_name <- ifelse(!is.na(data$full_name) & nzchar(data$full_name), data$full_name, data$user_name)
      display_data <- data[, c("row_num", "display_name", "chat_count", "total_messages", "avg_chat_length")]
      colnames(display_data) <- c("#", "Kullanıcı", "Söyleşi", "Mesaj", "Ort. Uzunluk")
      
      DT::datatable(
        display_data,
        options = list(
          dom = 't',
          pageLength = 15,
          scrollY = "280px",
          scrollCollapse = TRUE,
          ordering = TRUE,
          order = list(list(3, 'desc')),
          language = turkish_dt_language,
          columnDefs = list(
            list(className = 'dt-center', targets = c(0, 2, 3, 4)),
            list(className = 'row-number-col', targets = 0),
            list(width = '40px', targets = 0),
            list(orderable = FALSE, targets = 0)
          )
        ),
        class = "admin-datatable",
        rownames = FALSE
      )
    })
    
    output$usage_by_day_chart <- highcharter::renderHighchart({
      data <- analytics_data()$usage_by_day
      if (nrow(data) == 0) return(highcharter::highchart())
      
      turkish_days <- c("Pazar", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi")
      data$day_label <- turkish_days[data$day_num]
      data <- data[order(data$day_num), ]
      
      highcharter::highchart() %>%
        highcharter::hc_chart(type = "column", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = data$day_label,
          labels = list(style = list(color = "#999"))
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Söyleşi Sayısı", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#444"
        ) %>%
        highcharter::hc_plotOptions(
          column = list(
            borderWidth = 0,
            colorByPoint = TRUE
          )
        ) %>%
        highcharter::hc_add_series(
          name = "Söyleşi",
          data = data$cnt,
          colors = c("#f43f5e", "#ff6b35", "#f7931e", "#fbbf24", "#22c55e", "#3b82f6", "#8b5cf6")
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
          labels = list(style = list(color = "#999")),
          gridLineColor = "#444"
        ) %>%
        highcharter::hc_plotOptions(
          areaspline = list(
            marker = list(enabled = FALSE),
            lineWidth = 2.5
          )
        ) %>%
        highcharter::hc_add_series(
          name = "Söyleşi",
          data = data$cnt,
          color = "#06b6d4",
          fillColor = list(
            linearGradient = list(x1 = 0, y1 = 0, x2 = 0, y2 = 1),
            stops = list(
              list(0, "rgba(6, 182, 212, 0.3)"),
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
      
      data$row_num <- 1:nrow(data)
      data$last_upload <- format(as.POSIXct(data$last_upload), "%d.%m.%Y %H:%M")
      display_data <- data[, c("row_num", "user_name", "full_name", "file_count", "last_upload")]
      colnames(display_data) <- c("#", "Kullanıcı Adı", "Tam Ad", "Dosya Sayısı", "Son Yükleme")
      
      DT::datatable(
        display_data,
        options = list(
          dom = 'ftp',
          pageLength = 10,
          ordering = TRUE,
          order = list(list(3, 'desc')),
          language = turkish_dt_language,
          columnDefs = list(
            list(className = 'dt-center', targets = c(0, 3, 4)),
            list(className = 'row-number-col', targets = 0),
            list(width = '40px', targets = 0),
            list(orderable = FALSE, targets = 0)
          )
        ),
        class = "admin-datatable",
        rownames = FALSE
      )
    })
    
    output$model_performance_chart <- highcharter::renderHighchart({
      data <- analytics_data()$model_performance
      if (nrow(data) == 0) return(highcharter::highchart())
      
      data <- data[order(data$avg_duration), ]
      data$avg_duration <- round(data$avg_duration, 2)
      
      chart_data <- lapply(1:nrow(data), function(i) {
        list(
          y = data$avg_duration[i],
          total_count = data$total_count[i]
        )
      })
      
      highcharter::highchart() %>%
        highcharter::hc_chart(type = "bar", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = data$ModelUsed,
          labels = list(style = list(color = "#999"))
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Ort. Yanıt Süresi (sn)", style = list(color = "#999")),
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
          name = "Süre",
          data = chart_data,
          colors = c("#22c55e", "#84cc16", "#fbbf24", "#f7931e", "#ff6b35", "#ef4444")
        ) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a",
          borderColor = "#333",
          style = list(color = "#fff"),
          formatter = JS("function() { return '<b>' + this.x + '</b><br/>Ort. Süre: ' + this.y + ' sn<br/>Toplam Yanıt: ' + this.point.total_count; }")
        ) %>%
        highcharter::hc_legend(enabled = FALSE) %>%
        highcharter::hc_credits(enabled = FALSE)
    })
    
    output$model_errors_chart <- highcharter::renderHighchart({
      data <- analytics_data()$model_errors
      if (nrow(data) == 0) return(highcharter::highchart())
      
      data <- data[order(data$error_rate), ]
      data$error_rate <- round(data$error_rate, 2)
      
      chart_data <- lapply(1:nrow(data), function(i) {
        list(
          y = data$error_rate[i],
          error_count = data$error_count[i],
          total_count = data$total_count[i]
        )
      })
      
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
          bar = list(
            borderWidth = 0,
            colorByPoint = TRUE
          )
        ) %>%
        highcharter::hc_add_series(
          name = "Hata Oranı",
          data = chart_data,
          colors = c("#22c55e", "#84cc16", "#fbbf24", "#f7931e", "#ff6b35", "#ef4444")
        ) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a",
          borderColor = "#333",
          style = list(color = "#fff"),
          formatter = JS("function() { return '<b>' + this.x + '</b><br/>Hata Oranı: %' + this.y + '<br/>Hata Sayısı: ' + this.point.error_count + ' / ' + this.point.total_count; }")
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
      display_data <- data[, c("row_num", "ModelUsed", "ResponseDuration", "query_preview", "query_time")]
      colnames(display_data) <- c("#", "Model", "Süre (sn)", "Sorgu", "Tarih")
      
      DT::datatable(
        display_data,
        options = list(
          dom = 't',
          pageLength = 20,
          scrollY = "350px",
          scrollCollapse = TRUE,
          ordering = TRUE,
          order = list(list(2, 'desc')),
          language = turkish_dt_language,
          columnDefs = list(
            list(className = 'dt-center', targets = c(0, 1, 2, 4)),
            list(className = 'row-number-col', targets = 0),
            list(width = '40px', targets = 0),
            list(orderable = FALSE, targets = 0)
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
      display_data <- data[, c("row_num", "ModelUsed", "ResponseDuration", "query_preview", "query_time")]
      colnames(display_data) <- c("#", "Model", "Süre (sn)", "Sorgu", "Tarih")
      
      DT::datatable(
        display_data,
        options = list(
          dom = 't',
          pageLength = 20,
          scrollY = "350px",
          scrollCollapse = TRUE,
          ordering = TRUE,
          order = list(list(2, 'asc')),
          language = turkish_dt_language,
          columnDefs = list(
            list(className = 'dt-center', targets = c(0, 1, 2, 4)),
            list(className = 'row-number-col', targets = 0),
            list(width = '40px', targets = 0),
            list(orderable = FALSE, targets = 0)
          )
        ),
        class = "admin-datatable",
        rownames = FALSE
      )
    })
    
    output$model_feedback_table <- DT::renderDataTable({
      data <- analytics_data()$model_feedback
      if (nrow(data) == 0) return(DT::datatable(data.frame()))
      
      data$row_num <- 1:nrow(data)
      data$like_rate <- ifelse(data$total_responses > 0, round((data$likes / data$total_responses) * 100, 1), 0)
      data$dislike_rate <- ifelse(data$total_responses > 0, round((data$dislikes / data$total_responses) * 100, 1), 0)
      
      display_data <- data[, c("row_num", "ModelUsed", "likes", "dislikes", "total_responses", "like_rate", "dislike_rate")]
      colnames(display_data) <- c("#", "Model", "Beğeni", "Beğenmeme", "Toplam Yanıt", "Beğeni Oranı (%)", "Beğenmeme Oranı (%)")
      
      DT::datatable(
        display_data,
        options = list(
          dom = 'ftp',
          pageLength = 10,
          ordering = TRUE,
          order = list(list(4, 'desc')),
          language = turkish_dt_language,
          columnDefs = list(
            list(className = 'dt-center', targets = c(0, 2, 3, 4, 5, 6)),
            list(className = 'row-number-col', targets = 0),
            list(width = '40px', targets = 0),
            list(orderable = FALSE, targets = 0)
          )
        ),
        class = "admin-datatable",
        rownames = FALSE
      ) %>%
        DT::formatStyle(
          'Beğeni Oranı (%)',
          background = DT::styleColorBar(c(0, 100), '#10b981'),
          backgroundSize = '98% 88%',
          backgroundRepeat = 'no-repeat',
          backgroundPosition = 'center'
        ) %>%
        DT::formatStyle(
          'Beğenmeme Oranı (%)',
          background = DT::styleColorBar(c(0, 100), '#ef4444'),
          backgroundSize = '98% 88%',
          backgroundRepeat = 'no-repeat',
          backgroundPosition = 'center'
        )
    })
    
    output$response_time_feedback_chart <- highcharter::renderHighchart({
      data <- analytics_data()$response_time_feedback
      if (nrow(data) == 0) return(highcharter::highchart())
      
      bucket_order <- c("0-5 sn", "5-10 sn", "10-20 sn", "20+ sn")
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
        highcharter::hc_add_series(name = "Beğeni", data = data$likes, color = "#10b981") %>%
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
        highcharter::hc_add_series(name = "Beğeni", data = data$likes, color = "#10b981") %>%
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
    
    output$code_ratio_chart <- highcharter::renderHighchart({
      data <- analytics_data()$code_ratio
      if (nrow(data) == 0) return(highcharter::highchart())
      
      chart_data <- lapply(1:nrow(data), function(i) {
        list(
          name = data$has_code[i],
          y = data$cnt[i],
          color = if (data$has_code[i] == "Kodlu") "#60a5fa" else "#a78bfa"
        )
      })
      
      highcharter::highchart() %>%
        highcharter::hc_chart(type = "pie", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_plotOptions(
          pie = list(
            innerSize = "60%",
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
      
      data$row_num <- 1:nrow(data)
      display_data <- data[, c("row_num", "ChatTitle", "msg_count", "full_name")]
      colnames(display_data) <- c("#", "Söyleşi Başlığı", "Mesaj", "Kullanıcı")
      
      DT::datatable(
        display_data,
        options = list(
          dom = 't',
          pageLength = 20,
          scrollY = "240px",
          scrollCollapse = TRUE,
          ordering = TRUE,
          order = list(list(2, 'desc')),
          language = turkish_dt_language,
          columnDefs = list(
            list(className = 'dt-center', targets = c(0, 2, 3)),
            list(className = 'row-number-col', targets = 0),
            list(width = '40px', targets = 0),
            list(orderable = FALSE, targets = 0)
          )
        ),
        class = "admin-datatable",
        rownames = FALSE
      )
    })
    
    output$regenerated_table <- DT::renderDataTable({
      data <- analytics_data()$regenerated_responses
      if (nrow(data) == 0) return(DT::datatable(data.frame()))
      
      data$row_num <- 1:nrow(data)
      data$ModelUsed <- ifelse(is.na(data$ModelUsed) | !nzchar(data$ModelUsed), "Bilinmiyor", data$ModelUsed)
      display_data <- data[, c("row_num", "ChatTitle", "ModelUsed", "regen_count")]
      colnames(display_data) <- c("#", "Söyleşi Başlığı", "Model(ler)", "Yeniden Oluşturma")
      
      DT::datatable(
        display_data,
        options = list(
          dom = 't',
          pageLength = 20,
          scrollY = "250px",
          scrollCollapse = TRUE,
          ordering = TRUE,
          order = list(list(3, 'desc')),
          language = turkish_dt_language,
          columnDefs = list(
            list(className = 'dt-center', targets = c(0, 3)),
            list(className = 'row-number-col', targets = 0),
            list(width = '40px', targets = 0),
            list(orderable = FALSE, targets = 0)
          )
        ),
        class = "admin-datatable",
        rownames = FALSE
      )
    })
    
    output$weekly_trend_chart <- highcharter::renderHighchart({
      data <- analytics_data()$weekly_trend
      if (nrow(data) == 0) return(highcharter::highchart())
      
      data <- data[order(data$year_num, data$week_num), ]
      
      data$week_label <- paste0("Hafta ", data$week_num, " (", data$year_num, ")")
      data$week_range <- paste0(
        format(as.Date(data$week_start), "%d.%m"),
        " - ",
        format(as.Date(data$week_end), "%d.%m.%Y")
      )
      
      chart_data <- lapply(1:nrow(data), function(i) {
        list(
          y = data$cnt[i],
          week_num = data$week_num[i],
          year_num = data$year_num[i],
          week_range = data$week_range[i]
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
          labels = list(style = list(color = "#999")),
          gridLineColor = "#444"
        ) %>%
        highcharter::hc_plotOptions(
          areaspline = list(
            marker = list(enabled = TRUE, radius = 3),
            lineWidth = 2.5
          )
        ) %>%
        highcharter::hc_add_series(
          name = "Söyleşi",
          data = chart_data,
          color = "#22c55e",
          fillColor = list(
            linearGradient = list(x1 = 0, y1 = 0, x2 = 0, y2 = 1),
            stops = list(
              list(0, "rgba(34, 197, 94, 0.3)"),
              list(1, "rgba(34, 197, 94, 0)")
            )
          )
        ) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a",
          borderColor = "#333",
          style = list(color = "#fff"),
          formatter = JS("function() { return '<b>Hafta ' + this.point.week_num + ' (' + this.point.year_num + ')</b><br/>' + this.point.week_range + '<br/>Söyleşi: ' + this.y; }")
        ) %>%
        highcharter::hc_legend(enabled = FALSE) %>%
        highcharter::hc_credits(enabled = FALSE)
    })
    
    output$new_user_activation_table <- DT::renderDataTable({
      data <- analytics_data()$new_user_activation
      if (nrow(data) == 0) return(DT::datatable(data.frame()))
      
      data$row_num <- 1:nrow(data)
      data$first_chat <- format(as.POSIXct(data$first_chat), "%d.%m.%Y")
      display_data <- data[, c("row_num", "user_name", "full_name", "first_chat", "chat_count", "active_days")]
      colnames(display_data) <- c("#", "Kullanıcı Adı", "Tam Ad", "İlk Söyleşi", "Söyleşi Sayısı", "Aktif Gün")
      
      DT::datatable(
        display_data,
        options = list(
          dom = 't',
          pageLength = 20,
          scrollY = "280px",
          scrollCollapse = TRUE,
          ordering = TRUE,
          order = list(list(3, 'desc')),
          language = turkish_dt_language,
          columnDefs = list(
            list(className = 'dt-center', targets = c(0, 3, 4, 5)),
            list(className = 'dt-left', targets = c(1, 2)),
            list(className = 'row-number-col', targets = 0),
            list(width = '40px', targets = 0),
            list(orderable = FALSE, targets = 0)
          )
        ),
        class = "admin-datatable",
        rownames = FALSE
      )
    })
    
    output$monthly_growth_chart <- highcharter::renderHighchart({
      data <- analytics_data()$monthly_growth
      if (nrow(data) == 0) return(highcharter::highchart())
      
      data <- data[order(data$year_num, data$month_num), ]
      data$month_label <- paste0(turkish_months[data$month_num], " ", data$year_num)
      
      highcharter::highchart() %>%
        highcharter::hc_chart(type = "column", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = data$month_label,
          labels = list(style = list(color = "#999"))
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Sayı", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#444"
        ) %>%
        highcharter::hc_plotOptions(
          column = list(borderWidth = 0)
        ) %>%
        highcharter::hc_add_series(name = "Söyleşi", data = data$chat_count, color = "#3b82f6") %>%
        highcharter::hc_add_series(name = "Benzersiz Kullanıcı", data = data$unique_users, color = "#f59e0b") %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a",
          borderColor = "#333",
          style = list(color = "#fff"),
          shared = TRUE
        ) %>%
        highcharter::hc_legend(itemStyle = list(color = "#999")) %>%
        highcharter::hc_credits(enabled = FALSE)
    })
    
    output$model_usage_trend_chart <- highcharter::renderHighchart({
      data <- analytics_data()$model_usage_trend
      if (nrow(data) == 0) return(highcharter::highchart())
      
      models <- unique(data$ModelUsed)
      dates <- sort(unique(data$usage_date))
      date_labels <- sapply(dates, format_turkish_date)
      
      series_list <- lapply(models, function(m) {
        model_data <- data[data$ModelUsed == m, ]
        counts <- sapply(dates, function(d) {
          row <- model_data[model_data$usage_date == d, ]
          if (nrow(row) > 0) row$cnt[1] else 0
        })
        list(name = m, data = as.list(counts))
      })
      
      hc <- highcharter::highchart() %>%
        highcharter::hc_chart(type = "line", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = date_labels,
          labels = list(style = list(color = "#999"))
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Kullanım Sayısı", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#444"
        ) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a",
          borderColor = "#333",
          style = list(color = "#fff"),
          shared = TRUE
        ) %>%
        highcharter::hc_legend(itemStyle = list(color = "#999")) %>%
        highcharter::hc_credits(enabled = FALSE)
      
      for (s in series_list) {
        hc <- hc %>% highcharter::hc_add_series(name = s$name, data = s$data)
      }
      
      hc
    })
    
    output$chat_length_dist_chart <- highcharter::renderHighchart({
      data <- analytics_data()$chat_length_distribution
      if (nrow(data) == 0) return(highcharter::highchart())
      
      bucket_order <- c("1-2 mesaj", "3-5 mesaj", "6-10 mesaj", "11-20 mesaj", "20+ mesaj")
      data$length_bucket <- factor(data$length_bucket, levels = bucket_order)
      data <- data[order(data$length_bucket), ]
      data <- data[!is.na(data$length_bucket), ]
      
      if (nrow(data) == 0) return(highcharter::highchart())
      
      chart_data <- lapply(1:nrow(data), function(i) {
        list(
          name = as.character(data$length_bucket[i]),
          y = data$chat_count[i]
        )
      })
      
      highcharter::highchart() %>%
        highcharter::hc_chart(type = "pie", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_plotOptions(
          pie = list(
            innerSize = "50%",
            borderWidth = 0,
            dataLabels = list(
              enabled = TRUE,
              format = "<b>{point.name}</b>: {point.percentage:.1f}%",
              style = list(color = "#fff", textOutline = "none")
            )
          )
        ) %>%
        highcharter::hc_add_series(name = "Söyleşi", data = chart_data) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a",
          borderColor = "#333",
          style = list(color = "#fff"),
          pointFormat = "<b>{point.y}</b> söyleşi ({point.percentage:.1f}%)"
        ) %>%
        highcharter::hc_credits(enabled = FALSE)
    })
    
    output$avg_response_by_hour_chart <- highcharter::renderHighchart({
      data <- analytics_data()$avg_response_by_hour
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
          labels = list(style = list(color = "#999")),
          gridLineColor = "#444"
        ) %>%
        highcharter::hc_plotOptions(
          areaspline = list(
            marker = list(enabled = TRUE, radius = 3),
            lineWidth = 2.5
          )
        ) %>%
        highcharter::hc_add_series(
          name = "Ort. Süre",
          data = data$avg_duration,
          color = "#f59e0b",
          fillColor = list(
            linearGradient = list(x1 = 0, y1 = 0, x2 = 0, y2 = 1),
            stops = list(
              list(0, "rgba(245, 158, 11, 0.3)"),
              list(1, "rgba(245, 158, 11, 0)")
            )
          )
        ) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a",
          borderColor = "#333",
          style = list(color = "#fff"),
          pointFormat = "<b>{point.y}</b> saniye"
        ) %>%
        highcharter::hc_legend(enabled = FALSE) %>%
        highcharter::hc_credits(enabled = FALSE)
    })
    
  })
}
# R/module_admin_analytics.R

adminAnalyticsUI <- function(id) {
  ns <- NS(id)
  
  tagList(
    tags$head(
      tags$link(rel = "stylesheet", type = "text/css", href = "css/admin_analytics.css"),
	  tags$style(HTML("
        .admin-analytics-container {
          height: 100vh;
          display: flex;
          flex-direction: column;
          overflow: hidden;
          position: relative;
        }
        /* Hides the empty tab content divs generated automatically by tabsetPanel inside the header */
        .admin-tabs-container .tab-content {
          display: none !important;
        }
		.admin-header-fixed {
          position: relative;
          z-index: 1000;
          background: var(--background-light, #2a2a2a);
          flex-shrink: 0;
          border-radius: 0 16px 16px 0;
          height: 50px;
          min-height: 50px;
          box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
        }
        .admin-scrollable-content {
          flex: 1;
          overflow-y: auto;
          padding: 20px 25px 40px 25px;
        }
        .equal-height-row {
          display: flex;
          flex-wrap: wrap;
        }
        .equal-height-row > [class*='col-'] {
          display: flex;
          flex-direction: column;
        }
        .equal-height-row .analytics-card {
          flex: 1;
          display: flex;
          flex-direction: column;
        }
        .equal-height-row .analytics-card .table-container {
          flex: 1;
          display: flex;
          flex-direction: column;
        }
        .scrollable-table-equal {
          flex: 1;
          overflow-y: auto;
          max-height: 320px;
        }
        .metrics-grid-3 {
          display: grid;
          grid-template-columns: repeat(3, 1fr);
          gap: 20px;
          margin-bottom: 20px;
        }
        /* Assuming metrics-grid-5 is defined in css/admin_analytics.css or behaves similarly */
        .metrics-grid-5 {
          display: grid;
          grid-template-columns: repeat(5, 1fr);
          gap: 20px;
          margin-bottom: 20px;
        }
        @media (max-width: 1200px) {
           .metrics-grid-5 { grid-template-columns: repeat(3, 1fr); }
        }
        @media (max-width: 992px) {
          .metrics-grid-3 { grid-template-columns: repeat(2, 1fr); }
          .metrics-grid-5 { grid-template-columns: repeat(2, 1fr); }
        }
        @media (max-width: 576px) {
          .metrics-grid-3, .metrics-grid-5 { grid-template-columns: 1fr; }
        }
      "))
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
            span(
              id = ns("admin_last_update"),
              style = "color: #999; margin-right: 15px; font-size: 14px;",
              "Son Güncelleme: --"
            ),
            actionButton(
              ns("refresh_analytics"),
              label = tagList(icon("sync-alt"), "Yenile"),
              class = "btn-modern btn-primary"
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
              title = tags$span(
                title = "Genel sistem metrikleri ve özet istatistikler",
                tagList(icon("chart-line"), " Genel Bakış")
              ),
              value = "overview"
            ),
            tabPanel(
              title = tags$span(
                title = "Kullanıcı aktiviteleri ve davranış analizi",
                tagList(icon("users"), " Kullanıcı Analizi")
              ),
              value = "users"
            ),
            tabPanel(
              title = tags$span(
                title = "Yapay zeka model performansı ve hata oranları",
                tagList(icon("robot"), " YZ Performansı")
              ),
              value = "ai_perf"
            ),
            tabPanel(
              title = tags$span(
                title = "Kullanıcı geri bildirimleri ve memnuniyet analizi",
                tagList(icon("thumbs-up"), " Geri Bildirim")
              ),
              value = "feedback"
            ),
            tabPanel(
              title = tags$span(
                title = "Söyleşi kalitesi ve içerik analizi",
                tagList(icon("comments"), " Sohbet Kalitesi")
              ),
              value = "chat_quality"
            ),
            tabPanel(
              title = tags$span(
                title = "Zamana göre kullanım ve aktivite analizi",
                tagList(icon("clock"), " Zaman Analizi")
              ),
              value = "time_analysis"
            ),
            tabPanel(
              title = tags$span(
                title = "Gelişmiş sistem metrikleri ve detaylı analizler",
                tagList(icon("chart-area"), " Gelişmiş Analizler")
              ),
              value = "advanced_analytics"
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
    turkish_days <- c("Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar")
    
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
    
    modern_colors <- list(
      primary = c("#6366f1", "#8b5cf6", "#a855f7", "#d946ef", "#ec4899"),
      success = c("#10b981", "#22c55e", "#84cc16"),
      warning = c("#f59e0b", "#f97316", "#fbbf24"),
      danger = c("#ef4444", "#f43f5e", "#dc2626"),
      info = c("#06b6d4", "#0ea5e9", "#3b82f6"),
      neutral = c("#64748b", "#94a3b8", "#cbd5e1")
    )
    
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
      shinyjs::runjs("$('.tooltip').remove();")
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
          FROM (
            SELECT UserID FROM MB_Chats
            WHERE CAST(CreateTimestamp AS DATE) = CAST(GETDATE() AS DATE) AND IsDeleted = 0
            UNION
            SELECT UserID FROM MB_Usage_Log
            WHERE CAST(RequestTimestamp AS DATE) = CAST(GETDATE() AS DATE)
            UNION
            SELECT c.UserID 
            FROM MB_Messages m
            JOIN MB_Chats c ON m.ChatID = c.ChatID
            WHERE CAST(m.MessageTimestamp AS DATE) = CAST(GETDATE() AS DATE)
            UNION
            SELECT UserID FROM MB_Users
            WHERE CAST(LastLoginDate AS DATE) = CAST(GETDATE() AS DATE)
          ) combined
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
            ISNULL(SUM(CASE WHEN f.FeedbackType = 'like' THEN 1 ELSE 0 END), 0) as likes,
            ISNULL(SUM(CASE WHEN f.FeedbackType = 'dislike' THEN 1 ELSE 0 END), 0) as dislikes,
            COUNT(DISTINCT u.LogID) as total_responses
          FROM MB_Usage_Log u
          LEFT JOIN MB_Messages m_user ON u.MessageID = m_user.MessageID
          LEFT JOIN MB_Messages m_ai ON m_ai.ChatID = m_user.ChatID 
            AND m_ai.MessageType = 'ai' 
            AND m_ai.MessageOrder = m_user.MessageOrder + 1
          LEFT JOIN MB_Feedback f ON m_ai.MessageID = f.MessageID
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
            DATEPART(WEEKDAY, CreateTimestamp) as day_num,
            COUNT(*) as cnt
          FROM MB_Chats
          WHERE IsDeleted = 0
          GROUP BY DATEPART(WEEKDAY, CreateTimestamp)
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
            DATEPART(ISO_WEEK, CreateTimestamp) as week_num,
            MIN(CAST(CreateTimestamp AS DATE)) as week_start,
            MAX(CAST(CreateTimestamp AS DATE)) as week_end,
            COUNT(*) as cnt
          FROM MB_Chats
          WHERE IsDeleted = 0 AND CreateTimestamp >= DATEADD(week, -24, GETDATE())
          GROUP BY DATEPART(YEAR, CreateTimestamp), DATEPART(ISO_WEEK, CreateTimestamp)
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
            u.KullaniciAdi as user_name,
            (SELECT COUNT(*) FROM MB_Messages WHERE ChatID = c.ChatID AND MessageType = 'ai') as ai_count,
            (SELECT COUNT(*) FROM MB_Messages WHERE ChatID = c.ChatID AND MessageType = 'user') as user_count
          FROM MB_Chats c
          JOIN MB_Users u ON c.UserID = u.UserID
          WHERE c.IsDeleted = 0
          AND (SELECT COUNT(*) FROM MB_Messages WHERE ChatID = c.ChatID AND MessageType = 'ai') > 
              (SELECT COUNT(*) FROM MB_Messages WHERE ChatID = c.ChatID AND MessageType = 'user')
          ORDER BY ai_count DESC
        "),
		response_time_feedback = safe_query("
          SELECT 
            CASE 
              WHEN u.ResponseDuration <= 5 THEN '0-5 sn'
              WHEN u.ResponseDuration <= 10 THEN '5-10 sn'
              WHEN u.ResponseDuration <= 20 THEN '10-20 sn'
              ELSE '20+ sn'
            END as duration_bucket,
            ISNULL(SUM(CASE WHEN f.FeedbackType = 'like' THEN 1 ELSE 0 END), 0) as likes,
            ISNULL(SUM(CASE WHEN f.FeedbackType = 'dislike' THEN 1 ELSE 0 END), 0) as dislikes
          FROM MB_Usage_Log u
          LEFT JOIN MB_Messages m_user ON u.MessageID = m_user.MessageID
          LEFT JOIN MB_Messages m_ai ON m_ai.ChatID = m_user.ChatID 
            AND m_ai.MessageType = 'ai' 
            AND m_ai.MessageOrder = m_user.MessageOrder + 1
          LEFT JOIN MB_Feedback f ON m_ai.MessageID = f.MessageID
          WHERE u.ResponseSuccess = 1 AND u.ResponseDuration IS NOT NULL
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
            ISNULL(SUM(CASE WHEN f.FeedbackType = 'like' THEN 1 ELSE 0 END), 0) as likes,
            ISNULL(SUM(CASE WHEN f.FeedbackType = 'dislike' THEN 1 ELSE 0 END), 0) as dislikes
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
            CAST(u.RequestTimestamp AS DATE) as usage_date,
            u.ModelUsed,
            COUNT(*) as cnt
          FROM MB_Usage_Log u
          WHERE u.RequestTimestamp >= DATEADD(day, -14, GETDATE())
          GROUP BY CAST(u.RequestTimestamp AS DATE), u.ModelUsed
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
            DATEPART(HOUR, m.MessageTimestamp) as hour_num,
            AVG(u.ResponseDuration) as avg_duration
          FROM MB_Usage_Log u
          JOIN MB_Messages m ON u.MessageID = m.MessageID
          WHERE u.ResponseSuccess = 1
          GROUP BY DATEPART(HOUR, m.MessageTimestamp)
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
        "),
        today_stats = safe_query("
          SELECT 
            (SELECT COUNT(*) FROM MB_Chats WHERE CAST(CreateTimestamp AS DATE) = CAST(GETDATE() AS DATE) AND IsDeleted = 0) as chats_today,
            (SELECT COUNT(*) FROM MB_Messages WHERE CAST(MessageTimestamp AS DATE) = CAST(GETDATE() AS DATE)) as messages_today,
            (SELECT COUNT(*) FROM MB_Usage_Log WHERE CAST(RequestTimestamp AS DATE) = CAST(GETDATE() AS DATE)) as ai_calls_today,
            (SELECT AVG(ResponseDuration) FROM MB_Usage_Log WHERE CAST(RequestTimestamp AS DATE) = CAST(GETDATE() AS DATE) AND ResponseSuccess = 1) as avg_response_today
        "),
        this_week_stats = safe_query("
          SELECT 
            COUNT(DISTINCT UserID) as weekly_users,
            COUNT(*) as weekly_chats
          FROM MB_Chats 
          WHERE CreateTimestamp >= DATEADD(day, -7, GETDATE()) AND IsDeleted = 0
        "),
        feedback_trend = safe_query("
          SELECT 
            CAST(m.MessageTimestamp AS DATE) as feedback_date,
            SUM(CASE WHEN f.FeedbackType = 'like' THEN 1 ELSE 0 END) as likes,
            SUM(CASE WHEN f.FeedbackType = 'dislike' THEN 1 ELSE 0 END) as dislikes
          FROM MB_Feedback f
          JOIN MB_Messages m ON f.MessageID = m.MessageID
          WHERE m.MessageTimestamp >= DATEADD(day, -30, GETDATE())
          GROUP BY CAST(m.MessageTimestamp AS DATE)
          ORDER BY feedback_date
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

      # İçerik oluşturulduktan sonra Bootstrap tooltip'lerini yeniden başlat
      shinyjs::delay(100, {
        shinyjs::runjs("$('.admin-scrollable-content [data-toggle=\"tooltip\"]').tooltip({container: 'body', trigger: 'hover', delay: {show: 100, hide: 300}});")
      })

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
    
    users_ui <- function() {
      tagList(
        fluidRow(
          class = "equal-height-row",
          column(
            width = 4,
            div(
              class = "analytics-card",
              style = "min-height: 420px;",
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
              class = "analytics-card",
              style = "min-height: 420px;",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("star"), " Güçlü Kullanıcılar"),
                create_info_button("En yoğun sistem kullanıcıları.")
              ),
              div(class = "table-container scrollable-table-equal", DT::dataTableOutput(ns("power_users_table")))
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
      data <- analytics_data()

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
              class = "analytics-card",
              style = "min-height: 420px;",
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
              class = "analytics-card",
              style = "min-height: 420px;",
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
    
    time_analysis_ui <- function() {
      data <- analytics_data()
      
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
      
      data$label <- ifelse(data$FeedbackType == "like", "Beğeni", "Beğenmeme")
      
      chart_data <- lapply(1:nrow(data), function(i) {
        list(
          name = data$label[i],
          y = data$cnt[i],
          color = if (data$FeedbackType[i] == "like") "#10b981" else "#ef4444"
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
              format = "<b>{point.name}</b>: {point.y}",
              style = list(color = "#fff", textOutline = "none")
            )
          )
        ) %>%
        highcharter::hc_add_series(name = "Geri Bildirim", data = chart_data) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a",
          borderColor = "#333",
          style = list(color = "#fff")
        ) %>%
        highcharter::hc_credits(enabled = FALSE)
    })
    
    output$top_users_chart <- highcharter::renderHighchart({
      data <- analytics_data()$top_users
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
          labels = list(
            style = list(color = "#999"),
            formatter = JS("function() { return this.value; }")
          )
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
          colors = c("#6366f1", "#8b5cf6", "#a855f7", "#d946ef", "#ec4899", 
                     "#f43f5e", "#ef4444", "#f97316", "#f59e0b", "#eab308")
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
          pageLength = 20,
          scrollY = FALSE,
          ordering = TRUE,
          order = list(list(2, 'desc')),
          language = turkish_dt_language,
          columnDefs = list(
            list(className = 'dt-center', targets = c(0, 2, 3, 4)),
            list(className = 'row-number-col', targets = 0),
            list(width = '40px', targets = 0),
            list(orderable = FALSE, targets = 0)
          ),
          headerCallback = JS(
            "function(thead, data, start, end, display) {",
            "  var api = this.api();",
            "  api.columns().every(function(idx) {",
            "    var col = api.column(idx);",
            "    var th = $(col.header());",
            "    var td = $(col.nodes()).first();",
            "    if (td.hasClass('dt-center')) th.css('text-align', 'center');",
            "    else if (td.hasClass('dt-right')) th.css('text-align', 'right');",
            "    else th.css('text-align', 'left');",
            "    if (idx === 0) { th.css('font-size', '0'); }",
            "  });",
            "}"
          )
        ),
        class = "admin-datatable",
        rownames = FALSE
      )
    })
    
    output$usage_by_day_chart <- highcharter::renderHighchart({
      data <- analytics_data()$usage_by_day
      if (nrow(data) == 0) return(highcharter::highchart())
      
      day_mapping <- data.frame(
        sql_day = 1:7,
        monday_start = c(7, 1, 2, 3, 4, 5, 6),
        stringsAsFactors = FALSE
      )
      
      data <- merge(data, day_mapping, by.x = "day_num", by.y = "sql_day", all.x = TRUE)
      data <- data[order(data$monday_start), ]
      
      day_labels <- turkish_days[data$monday_start]
      
      highcharter::highchart() %>%
        highcharter::hc_chart(type = "column", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = day_labels,
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
            borderRadius = 4,
            colorByPoint = TRUE
          )
        ) %>%
        highcharter::hc_add_series(
          name = "Söyleşi",
          data = data$cnt,
          colors = c("#6366f1", "#8b5cf6", "#a855f7", "#d946ef", "#ec4899", "#f43f5e", "#ef4444")
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
          ),
		  headerCallback = JS(
            "function(thead, data, start, end, display) {",
            "  var api = this.api();",
            "  api.columns().every(function(idx) {",
            "    var col = api.column(idx);",
            "    var th = $(col.header());",
            "    var td = $(col.nodes()).first();",
            "    if (td.hasClass('dt-center')) th.css('text-align', 'center');",
            "    else if (td.hasClass('dt-right')) th.css('text-align', 'right');",
            "    else th.css('text-align', 'left');",
            "    if (idx === 0) { th.css('font-size', '0'); }",
            "  });",
            "}"
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
          colors = c("#10b981", "#22c55e", "#84cc16", "#f59e0b", "#f97316", "#ef4444")
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
          colors = c("#10b981", "#22c55e", "#84cc16", "#f59e0b", "#f97316", "#ef4444")
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
      colnames(display_data) <- c("#", "Model", "Süre (sn)", "Sorgu Önizleme", "Tarih")
      
      DT::datatable(
        display_data,
        options = list(
          dom = 't',
          pageLength = 20,
          scrollY = "350px",
          scrollCollapse = TRUE,
          ordering = FALSE,
          language = turkish_dt_language,
          columnDefs = list(
            list(className = 'dt-center', targets = c(0, 2, 4)),
            list(className = 'row-number-col', targets = 0),
            list(width = '40px', targets = 0),
            list(width = '250px', targets = 3)
          ),
		  headerCallback = JS(
            "function(thead, data, start, end, display) {",
            "  var api = this.api();",
            "  api.columns().every(function(idx) {",
            "    var col = api.column(idx);",
            "    var th = $(col.header());",
            "    var td = $(col.nodes()).first();",
            "    if (td.hasClass('dt-center')) th.css('text-align', 'center');",
            "    else if (td.hasClass('dt-right')) th.css('text-align', 'right');",
            "    else th.css('text-align', 'left');",
            "    if (idx === 0) { th.css('font-size', '0'); }",
            "  });",
            "}"
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
      colnames(display_data) <- c("#", "Model", "Süre (sn)", "Sorgu Önizleme", "Tarih")
      
      DT::datatable(
        display_data,
        options = list(
          dom = 't',
          pageLength = 20,
          scrollY = "350px",
          scrollCollapse = TRUE,
          ordering = FALSE,
          language = turkish_dt_language,
          columnDefs = list(
            list(className = 'dt-center', targets = c(0, 2, 4)),
            list(className = 'row-number-col', targets = 0),
            list(width = '40px', targets = 0),
            list(width = '250px', targets = 3)
          ),
		  headerCallback = JS(
            "function(thead, data, start, end, display) {",
            "  var api = this.api();",
            "  api.columns().every(function(idx) {",
            "    var col = api.column(idx);",
            "    var th = $(col.header());",
            "    var td = $(col.nodes()).first();",
            "    if (td.hasClass('dt-center')) th.css('text-align', 'center');",
            "    else if (td.hasClass('dt-right')) th.css('text-align', 'right');",
            "    else th.css('text-align', 'left');",
            "    if (idx === 0) { th.css('font-size', '0'); }",
            "  });",
            "}"
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
      data$like_rate <- round(ifelse(data$total_responses > 0, (data$likes / data$total_responses) * 100, 0), 1)
      data$dislike_rate <- round(ifelse(data$total_responses > 0, (data$dislikes / data$total_responses) * 100, 0), 1)
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
          ),
		  headerCallback = JS(
            "function(thead, data, start, end, display) {",
            "  var api = this.api();",
            "  api.columns().every(function(idx) {",
            "    var col = api.column(idx);",
            "    var th = $(col.header());",
            "    var td = $(col.nodes()).first();",
            "    if (td.hasClass('dt-center')) th.css('text-align', 'center');",
            "    else if (td.hasClass('dt-right')) th.css('text-align', 'right');",
            "    else th.css('text-align', 'left');",
            "    if (idx === 0) { th.css('font-size', '0'); }",
            "  });",
            "}"
          )
        ),
        class = "admin-datatable",
        rownames = FALSE
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
          color = if (data$has_code[i] == "Kodlu") "#8b5cf6" else "#64748b"
        )
      })
      
      highcharter::highchart() %>%
        highcharter::hc_chart(type = "pie", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_plotOptions(
          pie = list(
            innerSize = "70%",
            borderWidth = 0,
            dataLabels = list(
              enabled = TRUE,
              format = "<b>{point.name}</b>: {point.percentage:.1f}%",
              style = list(color = "#fff", textOutline = "none")
            )
          )
        ) %>%
        highcharter::hc_add_series(name = "Yanıt", data = chart_data) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a",
          borderColor = "#333",
          style = list(color = "#fff"),
          pointFormat = "<b>{point.y}</b> yanıt ({point.percentage:.1f}%)"
        ) %>%
        highcharter::hc_credits(enabled = FALSE)
    })
    
    output$longest_chats_table <- DT::renderDataTable({
      data <- analytics_data()$longest_chats
      if (nrow(data) == 0) return(DT::datatable(data.frame()))
      
      data$row_num <- 1:nrow(data)
      data$display_name <- ifelse(!is.na(data$full_name) & nzchar(data$full_name), data$full_name, data$user_name)
      display_data <- data[, c("row_num", "ChatTitle", "msg_count", "display_name")]
      colnames(display_data) <- c("#", "Söyleşi Başlığı", "Mesaj", "Kullanıcı")
      
      DT::datatable(
        display_data,
        options = list(
          dom = 't',
          pageLength = 20,
          scrollY = FALSE,
          ordering = TRUE,
          order = list(list(2, 'desc')),
          language = turkish_dt_language,
          columnDefs = list(
            list(className = 'dt-center', targets = c(0, 2)),
            list(className = 'row-number-col', targets = 0),
            list(width = '40px', targets = 0),
            list(orderable = FALSE, targets = 0)
          ),
		  headerCallback = JS(
            "function(thead, data, start, end, display) {",
            "  var api = this.api();",
            "  api.columns().every(function(idx) {",
            "    var col = api.column(idx);",
            "    var th = $(col.header());",
            "    var td = $(col.nodes()).first();",
            "    if (td.hasClass('dt-center')) th.css('text-align', 'center');",
            "    else if (td.hasClass('dt-right')) th.css('text-align', 'right');",
            "    else th.css('text-align', 'left');",
            "    if (idx === 0) { th.css('font-size', '0'); }",
            "  });",
            "}"
          )
        ),
        class = "admin-datatable",
        rownames = FALSE
      )
    })
    
    output$regenerated_table <- DT::renderDataTable({
      data <- analytics_data()$regenerated_responses
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
          dom = 't',
          pageLength = 20,
          scrollY = "250px",
          scrollCollapse = TRUE,
          ordering = TRUE,
          order = list(list(5, 'desc')),
          language = turkish_dt_language,
          columnDefs = list(
            list(className = 'dt-center', targets = c(0, 3, 4, 5)),
            list(className = 'row-number-col', targets = 0),
            list(width = '40px', targets = 0),
            list(orderable = FALSE, targets = 0)
          ),
		  headerCallback = JS(
            "function(thead, data, start, end, display) {",
            "  var api = this.api();",
            "  api.columns().every(function(idx) {",
            "    var col = api.column(idx);",
            "    var th = $(col.header());",
            "    var td = $(col.nodes()).first();",
            "    if (td.hasClass('dt-center')) th.css('text-align', 'center');",
            "    else if (td.hasClass('dt-right')) th.css('text-align', 'right');",
            "    else th.css('text-align', 'left');",
            "    if (idx === 0) { th.css('font-size', '0'); }",
            "  });",
            "}"
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
      
      data$week_label <- paste0("Hafta ", data$week_num)
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
      data$display_name <- ifelse(!is.na(data$full_name) & nzchar(data$full_name), data$full_name, data$user_name)
      display_data <- data[, c("row_num", "display_name", "first_chat", "chat_count", "active_days")]
      colnames(display_data) <- c("#", "Kullanıcı", "İlk Söyleşi", "Söyleşi Sayısı", "Aktif Gün")
      
      DT::datatable(
        display_data,
        options = list(
          dom = 't',
          pageLength = 20,
          scrollY = "280px",
          scrollCollapse = TRUE,
          ordering = TRUE,
          order = list(list(2, 'desc')),
          language = turkish_dt_language,
          columnDefs = list(
            list(className = 'dt-center', targets = c(0, 2, 3, 4)),
            list(className = 'row-number-col', targets = 0),
            list(width = '40px', targets = 0),
            list(orderable = FALSE, targets = 0)
          ),
		  headerCallback = JS(
            "function(thead, data, start, end, display) {",
            "  var api = this.api();",
            "  api.columns().every(function(idx) {",
            "    var col = api.column(idx);",
            "    var th = $(col.header());",
            "    var td = $(col.nodes()).first();",
            "    if (td.hasClass('dt-center')) th.css('text-align', 'center');",
            "    else if (td.hasClass('dt-right')) th.css('text-align', 'right');",
            "    else th.css('text-align', 'left');",
            "    if (idx === 0) { th.css('font-size', '0'); }",
            "  });",
            "}"
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
        highcharter::hc_yAxis_multiples(
          list(
            title = list(text = "Söyleşi Sayısı", style = list(color = "#3b82f6")),
            labels = list(style = list(color = "#999")),
            gridLineColor = "#444",
            min = 0
          ),
          list(
            title = list(text = "Benzersiz Kullanıcı", style = list(color = "#f59e0b")),
            labels = list(style = list(color = "#999")),
            opposite = TRUE,
            gridLineWidth = 0,
            min = 0
          )
        ) %>%
        highcharter::hc_plotOptions(
          column = list(borderWidth = 0)
        ) %>%
        highcharter::hc_add_series(name = "Söyleşi", data = data$chat_count, color = "#3b82f6", yAxis = 0) %>%
        highcharter::hc_add_series(name = "Benzersiz Kullanıcı", data = data$unique_users, color = "#f59e0b", type = "spline", yAxis = 1, marker = list(enabled = TRUE)) %>%
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
      
      model_colors <- c("#60a5fa", "#a78bfa", "#34d399", "#22d3ee", "#f472b6", "#fbbf24", "#c084fc", "#f97316")
      
      series_list <- lapply(seq_along(models), function(idx) {
        m <- models[idx]
        model_data <- data[data$ModelUsed == m, ]
        counts <- sapply(dates, function(d) {
          row <- model_data[model_data$usage_date == d, ]
          if (nrow(row) > 0) row$cnt[1] else 0
        })
        list(
          name = m, 
          data = as.list(counts),
          color = model_colors[((idx - 1) %% length(model_colors)) + 1]
        )
      })
      
      hc <- highcharter::highchart() %>%
        highcharter::hc_chart(type = "spline", backgroundColor = "transparent") %>%
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
        highcharter::hc_plotOptions(
          spline = list(
            marker = list(enabled = TRUE, radius = 4),
            lineWidth = 3,
            states = list(hover = list(lineWidth = 3.5))
          )
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
        hc <- hc %>% highcharter::hc_add_series(name = s$name, data = s$data, color = s$color)
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
      
      pie_colors <- c("#6366f1", "#22d3ee", "#a78bfa", "#f59e0b", "#f472b6")
      
      chart_data <- lapply(1:nrow(data), function(i) {
        list(
          name = as.character(data$length_bucket[i]),
          y = data$chat_count[i],
          color = pie_colors[i]
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
          valueSuffix = " sn"
        ) %>%
        highcharter::hc_legend(enabled = FALSE) %>%
        highcharter::hc_credits(enabled = FALSE)
    })
    
    output$feedback_trend_chart <- highcharter::renderHighchart({
      data <- analytics_data()$feedback_trend
      if (nrow(data) == 0) return(highcharter::highchart())
      
      data <- data[order(data$feedback_date), ]
      data$date_label <- sapply(data$feedback_date, format_turkish_date)
      
      highcharter::highchart() %>%
        highcharter::hc_chart(type = "areaspline", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = data$date_label,
          labels = list(style = list(color = "#999"))
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Geri Bildirim Sayısı", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#444"
        ) %>%
        highcharter::hc_plotOptions(
          areaspline = list(
            marker = list(enabled = FALSE),
            lineWidth = 2
          )
        ) %>%
        highcharter::hc_add_series(
          name = "Beğeni",
          data = data$likes,
          color = "#10b981",
          fillColor = list(
            linearGradient = list(x1 = 0, y1 = 0, x2 = 0, y2 = 1),
            stops = list(
              list(0, "rgba(16, 185, 129, 0.2)"),
              list(1, "rgba(16, 185, 129, 0)")
            )
          )
        ) %>%
        highcharter::hc_add_series(
          name = "Beğenmeme",
          data = data$dislikes,
          color = "#ef4444",
          fillColor = list(
            linearGradient = list(x1 = 0, y1 = 0, x2 = 0, y2 = 1),
            stops = list(
              list(0, "rgba(239, 68, 68, 0.2)"),
              list(1, "rgba(239, 68, 68, 0)")
            )
          )
        ) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a",
          borderColor = "#333",
          style = list(color = "#fff"),
          shared = TRUE
        ) %>%
        highcharter::hc_legend(itemStyle = list(color = "#999")) %>%
        highcharter::hc_credits(enabled = FALSE)
    })
    
    output$model_distribution_chart <- highcharter::renderHighchart({
      data <- analytics_data()$model_performance
      if (nrow(data) == 0) return(highcharter::highchart())
      
      model_colors <- c("#60a5fa", "#a78bfa", "#34d399", "#22d3ee", "#f472b6", "#fbbf24", "#c084fc", "#f97316")
      
      chart_data <- lapply(1:nrow(data), function(i) {
        list(
          name = data$ModelUsed[i],
          y = data$total_count[i],
          color = model_colors[((i - 1) %% length(model_colors)) + 1]
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
        highcharter::hc_add_series(name = "Kullanım", data = chart_data) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a",
          borderColor = "#333",
          style = list(color = "#fff"),
          pointFormat = "<b>{point.y}</b> çağrı ({point.percentage:.1f}%)"
        ) %>%
        highcharter::hc_credits(enabled = FALSE)
    })
    
  })
}
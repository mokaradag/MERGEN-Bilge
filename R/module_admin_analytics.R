# Dosya Yolu: R/module_admin_analytics.R
# Açıklama: Yönetici paneli ana analitik modülü (Genel Analiz) - Koordinatör.
#            Sistem metrikleri, kullanıcı analizi, YZ performansı, geri bildirim,
#            sohbet kalitesi, zaman analizi ve gelişmiş analizleri içerir.
#            Her sekmenin UI ve grafik mantığı ayrı dosyalarda modülerleştirilmiştir:
#              - R/module_admin_genel_bakis.R
#              - R/module_admin_kullanici_analizi.R
#              - R/module_admin_yz_performans.R
#              - R/module_admin_geri_bildirim_genel.R
#              - R/module_admin_sohbet_kalitesi.R
#              - R/module_admin_zaman_analizi.R
#              - R/module_admin_gelismis_analizler.R
#            Paylaşılan yardımcılar: R/helpers_admin_analytics.R

# ==============================================================================
# UI FONKSİYONU
# ==============================================================================

adminAnalyticsUI <- function(id) {
  ns <- NS(id)

  admin_page_layout(
    ns = ns,
    page_title = "Genel Analiz",
    page_icon = "chart-line",
    tab_panels = list(
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
}

# ==============================================================================
# SERVER FONKSİYONU
# ==============================================================================

adminAnalyticsServer <- function(id, pool = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Paylaşılan yardımcılara yerel kısayollar
    turkish_dt_language <- admin_turkish_dt_language
    turkish_months      <- admin_turkish_months
    turkish_days        <- admin_turkish_days
    format_turkish_date <- admin_format_turkish_date
    format_number       <- admin_format_number
    safe_query          <- admin_safe_query
    create_metric_card  <- admin_create_metric_card
    create_info_button  <- admin_create_info_button

    # Otomatik ve manuel yenileme altyapısı
    refresh <- admin_refresh_setup(input, session)

    # ==================================================================
    # VERİ ÇEKİMİ (tüm sekmeler için merkezi reaktif veri kaynağı)
    # ==================================================================
    analytics_data <- reactive({
      refresh$trigger()

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
            u.KullaniciAdi as user_name, u.KaynakAdi as full_name,
            COUNT(m.MessageID) as message_count
          FROM MB_Users u
          JOIN MB_Chats c ON u.UserID = c.UserID
          JOIN MB_Messages m ON c.ChatID = m.ChatID
          WHERE c.IsDeleted = 0 AND m.MessageType = 'user'
          GROUP BY u.KullaniciAdi, u.KaynakAdi
          ORDER BY message_count DESC
        "),
        daily_trend = safe_query("
          SELECT CAST(CreateTimestamp AS DATE) as chat_date, COUNT(*) as chat_count
          FROM MB_Chats
          WHERE CreateTimestamp >= DATEADD(day, -30, GETDATE()) AND IsDeleted = 0
          GROUP BY CAST(CreateTimestamp AS DATE)
          ORDER BY chat_date
        "),
        avg_chat_length = safe_query("
          SELECT AVG(CAST(msg_count AS FLOAT)) as avg_len
          FROM (SELECT ChatID, COUNT(*) as msg_count FROM MB_Messages GROUP BY ChatID) sub
        "),
        model_performance = safe_query("
          SELECT ModelUsed, AVG(ResponseDuration) as avg_duration, COUNT(*) as total_count
          FROM MB_Usage_Log
          WHERE ResponseSuccess = 1 AND ResponseDuration > 0
          GROUP BY ModelUsed ORDER BY avg_duration ASC
        "),
        slowest_queries = safe_query("
          SELECT TOP 20 u.ModelUsed, u.ResponseDuration,
            LEFT(m.MessageContent, 100) as query_preview, m.MessageTimestamp as query_time
          FROM MB_Usage_Log u JOIN MB_Messages m ON u.MessageID = m.MessageID
          WHERE u.ResponseSuccess = 1 AND u.ResponseDuration > 0
          ORDER BY u.ResponseDuration DESC
        "),
        fastest_queries = safe_query("
          SELECT TOP 20 u.ModelUsed, u.ResponseDuration,
            LEFT(m.MessageContent, 100) as query_preview, m.MessageTimestamp as query_time
          FROM MB_Usage_Log u JOIN MB_Messages m ON u.MessageID = m.MessageID
          WHERE u.ResponseSuccess = 1 AND u.ResponseDuration > 0
          ORDER BY u.ResponseDuration ASC
        "),
        model_errors = safe_query("
          SELECT ModelUsed,
            SUM(CASE WHEN ResponseSuccess = 0 THEN 1 ELSE 0 END) as error_count,
            COUNT(*) as total_count,
            CAST(SUM(CASE WHEN ResponseSuccess = 0 THEN 1 ELSE 0 END) AS FLOAT) / NULLIF(COUNT(*), 0) * 100 as error_rate
          FROM MB_Usage_Log GROUP BY ModelUsed ORDER BY error_rate ASC
        "),
        model_feedback = safe_query("
          SELECT u.ModelUsed,
            ISNULL(SUM(CASE WHEN f.FeedbackType = 'like' THEN 1 ELSE 0 END), 0) as likes,
            ISNULL(SUM(CASE WHEN f.FeedbackType = 'dislike' THEN 1 ELSE 0 END), 0) as dislikes,
            COUNT(DISTINCT u.LogID) as total_responses
          FROM MB_Usage_Log u
          LEFT JOIN MB_Messages m_user ON u.MessageID = m_user.MessageID
          LEFT JOIN MB_Messages m_ai ON m_ai.ChatID = m_user.ChatID
            AND m_ai.MessageType = 'ai' AND m_ai.MessageOrder = m_user.MessageOrder + 1
          LEFT JOIN MB_Feedback f ON m_ai.MessageID = f.MessageID
          GROUP BY u.ModelUsed ORDER BY total_responses DESC
        "),
        power_users = safe_query("
          SELECT TOP 15 u.KullaniciAdi as user_name, u.KaynakAdi as full_name,
            COUNT(DISTINCT c.ChatID) as chat_count, COUNT(m.MessageID) as total_messages,
            CAST(COUNT(m.MessageID) AS FLOAT) / NULLIF(COUNT(DISTINCT c.ChatID), 0) as avg_chat_length
          FROM MB_Users u JOIN MB_Chats c ON u.UserID = c.UserID
          JOIN MB_Messages m ON c.ChatID = m.ChatID WHERE c.IsDeleted = 0
          GROUP BY u.UserID, u.KullaniciAdi, u.KaynakAdi ORDER BY total_messages DESC
        "),
        file_uploaders = safe_query("
          SELECT u.KullaniciAdi as user_name, u.KaynakAdi as full_name,
            COUNT(CASE WHEN m.MessageContent LIKE '%[Dosya:%' THEN 1 END) as file_count,
            MAX(m.MessageTimestamp) as last_upload
          FROM MB_Messages m JOIN MB_Chats c ON m.ChatID = c.ChatID
          JOIN MB_Users u ON c.UserID = u.UserID
          WHERE m.MessageContent LIKE '%[Dosya:%' AND c.IsDeleted = 0
          GROUP BY u.KullaniciAdi, u.KaynakAdi ORDER BY file_count DESC
        "),
        usage_by_day = safe_query("
          SELECT DATEPART(WEEKDAY, CreateTimestamp) as day_num, COUNT(*) as cnt
          FROM MB_Chats WHERE IsDeleted = 0
          GROUP BY DATEPART(WEEKDAY, CreateTimestamp)
        "),
        usage_by_hour = safe_query("
          SELECT DATEPART(HOUR, CreateTimestamp) as hour_num, COUNT(*) as cnt
          FROM MB_Chats WHERE IsDeleted = 0
          GROUP BY DATEPART(HOUR, CreateTimestamp) ORDER BY hour_num
        "),
        longest_chats = safe_query("
          SELECT TOP 20 c.ChatTitle, COUNT(m.MessageID) as msg_count,
            u.KullaniciAdi as user_name, u.KaynakAdi as full_name
          FROM MB_Chats c JOIN MB_Messages m ON c.ChatID = m.ChatID
          JOIN MB_Users u ON c.UserID = u.UserID WHERE c.IsDeleted = 0
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
          FROM MB_Chats WHERE IsDeleted = 0 AND CreateTimestamp >= DATEADD(week, -24, GETDATE())
          GROUP BY DATEPART(YEAR, CreateTimestamp), DATEPART(ISO_WEEK, CreateTimestamp)
          ORDER BY year_num DESC, week_num DESC
        "),
        new_user_activation = safe_query("
          SELECT TOP 20 u.KullaniciAdi as user_name, u.KaynakAdi as full_name,
            MIN(c.CreateTimestamp) as first_chat, COUNT(DISTINCT c.ChatID) as chat_count,
            DATEDIFF(day, MIN(c.CreateTimestamp), MAX(c.CreateTimestamp)) as active_days
          FROM MB_Users u JOIN MB_Chats c ON u.UserID = c.UserID WHERE c.IsDeleted = 0
          GROUP BY u.UserID, u.KullaniciAdi, u.KaynakAdi
          HAVING COUNT(DISTINCT c.ChatID) > 1 ORDER BY first_chat DESC
        "),
        peak_hours = safe_query("
          SELECT TOP 5 DATEPART(HOUR, CreateTimestamp) as hour_num, COUNT(*) as cnt
          FROM MB_Chats WHERE IsDeleted = 0
          GROUP BY DATEPART(HOUR, CreateTimestamp) ORDER BY cnt DESC
        "),
        total_feedback_count = safe_query("SELECT COUNT(*) as cnt FROM MB_Feedback"),
        avg_messages_per_chat = safe_query("
          SELECT AVG(CAST(msg_count AS FLOAT)) as avg_msg
          FROM (SELECT ChatID, COUNT(*) as msg_count FROM MB_Messages GROUP BY ChatID) sub
        "),
        user_retention = safe_query("
          SELECT
            COUNT(DISTINCT CASE WHEN chat_count > 1 THEN UserID END) as returning_users,
            COUNT(DISTINCT UserID) as total_users
          FROM (SELECT UserID, COUNT(*) as chat_count FROM MB_Chats WHERE IsDeleted = 0 GROUP BY UserID) sub
        "),
        monthly_growth = safe_query("
          SELECT DATEPART(YEAR, CreateTimestamp) as year_num,
            DATEPART(MONTH, CreateTimestamp) as month_num,
            COUNT(*) as chat_count, COUNT(DISTINCT UserID) as unique_users
          FROM MB_Chats WHERE IsDeleted = 0 AND CreateTimestamp >= DATEADD(month, -6, GETDATE())
          GROUP BY DATEPART(YEAR, CreateTimestamp), DATEPART(MONTH, CreateTimestamp)
          ORDER BY year_num, month_num
        "),
        avg_session_duration = safe_query("
          SELECT AVG(duration_minutes) as avg_duration
          FROM (
            SELECT ChatID, DATEDIFF(MINUTE, MIN(MessageTimestamp), MAX(MessageTimestamp)) as duration_minutes
            FROM MB_Messages GROUP BY ChatID HAVING COUNT(*) > 1
          ) sub
        "),
        bounce_rate = safe_query("
          SELECT CAST(SUM(CASE WHEN msg_count <= 2 THEN 1 ELSE 0 END) AS FLOAT) / NULLIF(COUNT(*), 0) * 100 as bounce_rate
          FROM (SELECT ChatID, COUNT(*) as msg_count FROM MB_Messages GROUP BY ChatID) sub
        "),
        code_ratio = safe_query("
          SELECT CASE WHEN MessageContent LIKE '%```%' THEN 'Kodlu' ELSE 'Kodsuz' END as has_code, COUNT(*) as cnt
          FROM MB_Messages WHERE MessageType = 'ai'
          GROUP BY CASE WHEN MessageContent LIKE '%```%' THEN 'Kodlu' ELSE 'Kodsuz' END
        "),
        regenerated_responses = safe_query("
          SELECT TOP 20 c.ChatTitle, u.KullaniciAdi as user_name,
            (SELECT COUNT(*) FROM MB_Messages WHERE ChatID = c.ChatID AND MessageType = 'ai') as ai_count,
            (SELECT COUNT(*) FROM MB_Messages WHERE ChatID = c.ChatID AND MessageType = 'user') as user_count
          FROM MB_Chats c JOIN MB_Users u ON c.UserID = u.UserID
          WHERE c.IsDeleted = 0 AND
            (SELECT COUNT(*) FROM MB_Messages WHERE ChatID = c.ChatID AND MessageType = 'ai') >
            (SELECT COUNT(*) FROM MB_Messages WHERE ChatID = c.ChatID AND MessageType = 'user')
          ORDER BY ai_count DESC
        "),
        response_time_feedback = safe_query("
          SELECT
            CASE WHEN u.ResponseDuration <= 5 THEN '0-5 sn' WHEN u.ResponseDuration <= 10 THEN '5-10 sn'
              WHEN u.ResponseDuration <= 20 THEN '10-20 sn' ELSE '20+ sn' END as duration_bucket,
            ISNULL(SUM(CASE WHEN f.FeedbackType = 'like' THEN 1 ELSE 0 END), 0) as likes,
            ISNULL(SUM(CASE WHEN f.FeedbackType = 'dislike' THEN 1 ELSE 0 END), 0) as dislikes
          FROM MB_Usage_Log u
          LEFT JOIN MB_Messages m_user ON u.MessageID = m_user.MessageID
          LEFT JOIN MB_Messages m_ai ON m_ai.ChatID = m_user.ChatID
            AND m_ai.MessageType = 'ai' AND m_ai.MessageOrder = m_user.MessageOrder + 1
          LEFT JOIN MB_Feedback f ON m_ai.MessageID = f.MessageID
          WHERE u.ResponseSuccess = 1 AND u.ResponseDuration IS NOT NULL
          GROUP BY CASE WHEN u.ResponseDuration <= 5 THEN '0-5 sn' WHEN u.ResponseDuration <= 10 THEN '5-10 sn'
            WHEN u.ResponseDuration <= 20 THEN '10-20 sn' ELSE '20+ sn' END
        "),
        response_length_feedback = safe_query("
          SELECT
            CASE WHEN LEN(m.MessageContent) < 500 THEN 'Kısa (< 500)'
              WHEN LEN(m.MessageContent) < 1500 THEN 'Orta (500-1500)'
              WHEN LEN(m.MessageContent) < 3000 THEN 'Uzun (1500-3000)'
              ELSE 'Çok Uzun (> 3000)' END as length_bucket,
            ISNULL(SUM(CASE WHEN f.FeedbackType = 'like' THEN 1 ELSE 0 END), 0) as likes,
            ISNULL(SUM(CASE WHEN f.FeedbackType = 'dislike' THEN 1 ELSE 0 END), 0) as dislikes
          FROM MB_Messages m LEFT JOIN MB_Feedback f ON m.MessageID = f.MessageID
          WHERE m.MessageType = 'ai'
          GROUP BY CASE WHEN LEN(m.MessageContent) < 500 THEN 'Kısa (< 500)'
            WHEN LEN(m.MessageContent) < 1500 THEN 'Orta (500-1500)'
            WHEN LEN(m.MessageContent) < 3000 THEN 'Uzun (1500-3000)'
            ELSE 'Çok Uzun (> 3000)' END
        "),
        model_usage_trend = safe_query("
          SELECT CAST(u.RequestTimestamp AS DATE) as usage_date, u.ModelUsed, COUNT(*) as cnt
          FROM MB_Usage_Log u WHERE u.RequestTimestamp >= DATEADD(day, -14, GETDATE())
          GROUP BY CAST(u.RequestTimestamp AS DATE), u.ModelUsed ORDER BY usage_date
        "),
        user_activity_heatmap = safe_query("
          SELECT DATEPART(WEEKDAY, CreateTimestamp) as day_num,
            DATEPART(HOUR, CreateTimestamp) as hour_num, COUNT(*) as cnt
          FROM MB_Chats WHERE IsDeleted = 0 AND CreateTimestamp >= DATEADD(day, -30, GETDATE())
          GROUP BY DATEPART(WEEKDAY, CreateTimestamp), DATEPART(HOUR, CreateTimestamp)
        "),
        avg_response_by_hour = safe_query("
          SELECT DATEPART(HOUR, m.MessageTimestamp) as hour_num, AVG(u.ResponseDuration) as avg_duration
          FROM MB_Usage_Log u JOIN MB_Messages m ON u.MessageID = m.MessageID
          WHERE u.ResponseSuccess = 1
          GROUP BY DATEPART(HOUR, m.MessageTimestamp) ORDER BY hour_num
        "),
        chat_length_distribution = safe_query("
          SELECT
            CASE WHEN msg_count <= 2 THEN '1-2 mesaj' WHEN msg_count <= 5 THEN '3-5 mesaj'
              WHEN msg_count <= 10 THEN '6-10 mesaj' WHEN msg_count <= 20 THEN '11-20 mesaj'
              ELSE '20+ mesaj' END as length_bucket,
            COUNT(*) as chat_count
          FROM (SELECT ChatID, COUNT(*) as msg_count FROM MB_Messages GROUP BY ChatID) sub
          GROUP BY CASE WHEN msg_count <= 2 THEN '1-2 mesaj' WHEN msg_count <= 5 THEN '3-5 mesaj'
            WHEN msg_count <= 10 THEN '6-10 mesaj' WHEN msg_count <= 20 THEN '11-20 mesaj'
            ELSE '20+ mesaj' END
        "),
        first_response_success = safe_query("
          SELECT SUM(CASE WHEN first_feedback = 'like' THEN 1 ELSE 0 END) as first_likes,
            SUM(CASE WHEN first_feedback = 'dislike' THEN 1 ELSE 0 END) as first_dislikes,
            COUNT(*) as total_first_responses
          FROM (
            SELECT c.ChatID,
              (SELECT TOP 1 f.FeedbackType FROM MB_Messages m
               JOIN MB_Feedback f ON m.MessageID = f.MessageID
               WHERE m.ChatID = c.ChatID AND m.MessageType = 'ai'
               ORDER BY m.MessageOrder) as first_feedback
            FROM MB_Chats c WHERE c.IsDeleted = 0
          ) sub WHERE first_feedback IS NOT NULL
        "),
        today_stats = safe_query("
          SELECT
            (SELECT COUNT(*) FROM MB_Chats WHERE CAST(CreateTimestamp AS DATE) = CAST(GETDATE() AS DATE) AND IsDeleted = 0) as chats_today,
            (SELECT COUNT(*) FROM MB_Messages WHERE CAST(MessageTimestamp AS DATE) = CAST(GETDATE() AS DATE)) as messages_today,
            (SELECT COUNT(*) FROM MB_Usage_Log WHERE CAST(RequestTimestamp AS DATE) = CAST(GETDATE() AS DATE)) as ai_calls_today,
            (SELECT AVG(ResponseDuration) FROM MB_Usage_Log WHERE CAST(RequestTimestamp AS DATE) = CAST(GETDATE() AS DATE) AND ResponseSuccess = 1) as avg_response_today
        "),
        this_week_stats = safe_query("
          SELECT COUNT(DISTINCT UserID) as weekly_users, COUNT(*) as weekly_chats
          FROM MB_Chats WHERE CreateTimestamp >= DATEADD(day, -7, GETDATE()) AND IsDeleted = 0
        "),
        feedback_trend = safe_query("
          SELECT CAST(m.MessageTimestamp AS DATE) as feedback_date,
            SUM(CASE WHEN f.FeedbackType = 'like' THEN 1 ELSE 0 END) as likes,
            SUM(CASE WHEN f.FeedbackType = 'dislike' THEN 1 ELSE 0 END) as dislikes
          FROM MB_Feedback f JOIN MB_Messages m ON f.MessageID = m.MessageID
          WHERE m.MessageTimestamp >= DATEADD(day, -30, GETDATE())
          GROUP BY CAST(m.MessageTimestamp AS DATE) ORDER BY feedback_date
        ")
      )
    })

    # ==================================================================
    # SEKME İÇERİĞİ YÖNLENDİRİCİ
    # ==================================================================
    output$tab_content_area <- renderUI({
      tab <- input$admin_tabs
      if (is.null(tab)) tab <- "overview"

      # Bootstrap tooltip'lerini yeniden başlat
      admin_init_tooltips(session)

      switch(tab,
        "overview"           = admin_overview_ui(analytics_data(), ns, create_metric_card, create_info_button, format_number),
        "users"              = admin_users_ui(ns, create_info_button),
        "ai_perf"            = admin_ai_perf_ui(ns, create_info_button),
        "feedback"           = admin_feedback_ui(analytics_data(), ns, create_metric_card, create_info_button, format_number),
        "chat_quality"       = admin_chat_quality_ui(analytics_data(), ns, create_metric_card, create_info_button, format_number),
        "time_analysis"      = admin_time_analysis_ui(analytics_data(), ns, create_metric_card, create_info_button, format_number),
        "advanced_analytics" = admin_advanced_analytics_ui(analytics_data(), ns, create_metric_card, create_info_button, format_number),
        admin_overview_ui(analytics_data(), ns, create_metric_card, create_info_button, format_number)
      )
    })

    # ==================================================================
    # GRAFİK VE TABLO ÇIKTILARI (alt modüllerden)
    # ==================================================================
    admin_overview_outputs(output, analytics_data, format_turkish_date)
    admin_users_outputs(output, analytics_data, turkish_dt_language, turkish_days)
    admin_ai_perf_outputs(output, analytics_data, turkish_dt_language)
    admin_feedback_outputs(output, analytics_data, turkish_dt_language, format_turkish_date)
    admin_chat_quality_outputs(output, analytics_data, turkish_dt_language)
    admin_time_analysis_outputs(output, analytics_data, turkish_dt_language, turkish_months)
    admin_advanced_analytics_outputs(output, analytics_data, format_turkish_date)

  })
}

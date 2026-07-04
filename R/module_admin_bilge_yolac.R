# Dosya Yolu: R/module_admin_bilge_yolac.R
# Açıklama: Yönetici paneli - Genel Analiz modülünün "Bilge Yolaç" sekmesi.
#            Kalıcı Bilge Yolaç ajan oturum verisi (MB_ClaudeCode_Sessions /
#            MB_ClaudeCode_Runs) yönetici panelinde de değerli olduğundan burada
#            özet metrik kartları, günlük oturum eğilimi, durum dağılımı ve
#            en aktif kullanıcı / son oturum tabloları olarak sunulur.
#            Diğer admin sekme modülleriyle (module_admin_genel_bakis.R vb.)
#            aynı desende ayrı dosyadır; koordinatör module_admin_analytics.R
#            bu fonksiyonları çağırır.
#
#            Tüm sorgular güvenli çalışır: MB_ClaudeCode_* tabloları yoksa
#            admin_safe_query boş data.frame döner ve sekme sıfır/boş gösterir.

# ==============================================================================
# BİLGE YOLAÇ SEKMESİ (ajan oturum istatistikleri)
# ==============================================================================
# Bilge Yolaç admin sorgularını çalıştırır (saf; safe_query enjekte edilir).
admin_bilge_yolac_queries <- function(safe_query) {
  list(
    session_totals = safe_query("
      SELECT
        COUNT(*) as total,
        SUM(CASE WHEN IsDeleted = 0 THEN 1 ELSE 0 END) as active,
        SUM(CASE WHEN IsDeleted = 1 THEN 1 ELSE 0 END) as archived,
        SUM(CASE WHEN ClaudeCliSessionID IS NOT NULL AND ClaudeCliSessionID <> ''
                 THEN 1 ELSE 0 END) as resumable,
        COUNT(DISTINCT UserID) as users
      FROM MB_ClaudeCode_Sessions
    "),
    run_totals = safe_query("
      SELECT
        COUNT(*) as total_runs,
        SUM(CASE WHEN Status = 'failed' THEN 1 ELSE 0 END) as failed_runs,
        SUM(CASE WHEN GeneratedDownloadsJson IS NOT NULL
                  AND GeneratedDownloadsJson <> '' AND GeneratedDownloadsJson <> '[]'
                 THEN 1 ELSE 0 END) as runs_with_files,
        AVG(CAST(DurationSeconds AS FLOAT)) as avg_duration
      FROM MB_ClaudeCode_Runs
    "),
    daily_trend = safe_query("
      SELECT CAST(CreatedAt AS DATE) as session_date, COUNT(*) as cnt
      FROM MB_ClaudeCode_Sessions
      WHERE CreatedAt >= DATEADD(day, -30, GETDATE())
      GROUP BY CAST(CreatedAt AS DATE)
      ORDER BY session_date
    "),
    status_dist = safe_query("
      SELECT Status, COUNT(*) as cnt
      FROM MB_ClaudeCode_Sessions
      WHERE IsDeleted = 0
      GROUP BY Status
    "),
    top_users = safe_query("
      SELECT TOP 10 u.KullaniciAdi as user_name, u.KaynakAdi as full_name,
        COUNT(s.ClaudeSessionRecordID) as session_count
      FROM MB_ClaudeCode_Sessions s JOIN MB_Users u ON s.UserID = u.UserID
      GROUP BY u.KullaniciAdi, u.KaynakAdi
      ORDER BY session_count DESC
    "),
    recent_sessions = safe_query("
      SELECT TOP 15 s.SessionTitle, u.KullaniciAdi as user_name,
        ISNULL(NULLIF(s.RuntimeModel, ''), s.ModelUsed) as model_name,
        s.Status,
        (SELECT COUNT(*) FROM MB_ClaudeCode_Runs r
          WHERE r.ClaudeSessionRecordID = s.ClaudeSessionRecordID) as run_count,
        COALESCE(s.LastRunAt, s.CreatedAt) as last_activity
      FROM MB_ClaudeCode_Sessions s JOIN MB_Users u ON s.UserID = u.UserID
      WHERE s.IsDeleted = 0
      ORDER BY COALESCE(s.LastRunAt, s.CreatedAt) DESC
    ")
  )
}

#' Bilge Yolaç sekmesinin UI içeriğini üretir (mevcut admin görsel dilini kullanır).
admin_bilge_yolac_ui <- function(data, ns, create_metric_card, create_info_button, format_number) {
  st <- data$session_totals
  rt <- data$run_totals

  say <- function(df, kolon) {
    if (is.data.frame(df) && nrow(df) > 0 && !is.na(df[[kolon]][1])) df[[kolon]][1] else 0
  }

  toplam    <- say(st, "total")
  devam     <- say(st, "resumable")
  arsiv     <- say(st, "archived")
  kullanici <- say(st, "users")
  toplam_run <- say(rt, "total_runs")
  dosyali_run <- say(rt, "runs_with_files")
  ort_sure <- if (is.data.frame(rt) && nrow(rt) > 0 && !is.na(rt$avg_duration[1])) {
    sprintf("%.1f sn", rt$avg_duration[1])
  } else {
    "N/A"
  }

  tagList(
    div(
      class = "metrics-grid",
      create_metric_card("Toplam Oturum", format_number(toplam), "layer-group", "blue",
        tooltip = "Kaydedilmiş tüm Bilge Yolaç ajan oturumlarının sayısı."),
      create_metric_card("Devam Edilebilir", format_number(devam), "rotate-right", "green",
        tooltip = "CLI oturum kimliği bulunan ve devam ettirilebilen oturumlar."),
      create_metric_card("Arşivlenmiş", format_number(arsiv), "box-archive", "orange",
        tooltip = "Kullanıcı tarafından arşivlenen (yumuşak silinen) oturumlar."),
      create_metric_card("Kullanıcı Sayısı", format_number(kullanici), "users", "purple",
        tooltip = "En az bir Bilge Yolaç oturumu olan benzersiz kullanıcı sayısı."),
      create_metric_card("Toplam Çalıştırma", format_number(toplam_run), "bolt", "cyan",
        tooltip = "Tüm oturumlardaki toplam komut çalıştırma sayısı."),
      create_metric_card("Dosyalı Çalıştırma", format_number(dosyali_run), "file-arrow-down", "teal",
        tooltip = "Dosya üreten çalıştırmaların sayısı."),
      create_metric_card("Ort. Çalıştırma Süresi", ort_sure, "stopwatch", "yellow",
        tooltip = "Çalıştırmaların ortalama süresi (saniye).")
    ),
    fluidRow(
      column(
        width = 8,
        div(
          class = "analytics-card",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("chart-area"), " Son 30 Günlük Oturum Eğilimi"),
            create_info_button("Son 30 gündeki günlük Bilge Yolaç oturum sayıları.")
          ),
          highcharter::highchartOutput(ns("by_daily_trend_chart"), height = "300px")
        )
      ),
      column(
        width = 4,
        div(
          class = "analytics-card",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("chart-pie"), " Durum Dağılımı"),
            create_info_button("Aktif oturumların duruma göre dağılımı.")
          ),
          highcharter::highchartOutput(ns("by_status_chart"), height = "300px")
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
            h4(class = "card-title", icon("user-group"), " En Aktif Kullanıcılar"),
            create_info_button("En çok Bilge Yolaç oturumu olan kullanıcılar.")
          ),
          DT::dataTableOutput(ns("by_top_users_table"))
        )
      ),
      column(
        width = 6,
        div(
          class = "analytics-card",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("clock-rotate-left"), " Son Oturumlar"),
            create_info_button("En son etkinlik gösteren Bilge Yolaç oturumları.")
          ),
          DT::dataTableOutput(ns("by_recent_sessions_table"))
        )
      )
    )
  )
}

#' Bilge Yolaç sekmesi grafik ve tablolarını (output) kaydeder.
admin_bilge_yolac_outputs <- function(output, bilge_yolac_data_fn, turkish_dt_language) {

  output$by_daily_trend_chart <- highcharter::renderHighchart({
    data <- bilge_yolac_data_fn()$daily_trend
    if (!is.data.frame(data) || nrow(data) == 0) return(highcharter::highchart())

    highcharter::highchart() %>%
      highcharter::hc_chart(type = "areaspline", backgroundColor = "transparent") %>%
      highcharter::hc_title(text = NULL) %>%
      highcharter::hc_xAxis(categories = as.character(data$session_date),
                            labels = list(style = list(color = "#999"))) %>%
      highcharter::hc_yAxis(title = list(text = NULL),
                            labels = list(style = list(color = "#999")),
                            gridLineColor = "#333") %>%
      highcharter::hc_add_series(name = "Oturum", data = as.numeric(data$cnt),
                                 color = "#7C4DFF") %>%
      highcharter::hc_tooltip(backgroundColor = "#1a1a1a", borderColor = "#333",
                              style = list(color = "#fff")) %>%
      highcharter::hc_legend(enabled = FALSE) %>%
      highcharter::hc_credits(enabled = FALSE)
  })

  output$by_status_chart <- highcharter::renderHighchart({
    data <- bilge_yolac_data_fn()$status_dist
    if (!is.data.frame(data) || nrow(data) == 0) return(highcharter::highchart())

    etiketler <- c(
      "completed" = "Tamamlandı", "failed" = "Başarısız",
      "stopped" = "Durduruldu", "active" = "Aktif"
    )
    durum <- as.character(data$Status)
    ad <- ifelse(durum %in% names(etiketler), etiketler[durum], durum)

    highcharter::highchart() %>%
      highcharter::hc_chart(type = "pie", backgroundColor = "transparent") %>%
      highcharter::hc_title(text = NULL) %>%
      highcharter::hc_add_series(
        name = "Oturum",
        data = lapply(seq_len(nrow(data)), function(i) {
          list(name = ad[i], y = as.numeric(data$cnt[i]))
        })
      ) %>%
      highcharter::hc_tooltip(backgroundColor = "#1a1a1a", borderColor = "#333",
                              style = list(color = "#fff")) %>%
      highcharter::hc_credits(enabled = FALSE)
  })

  output$by_top_users_table <- DT::renderDataTable({
    data <- bilge_yolac_data_fn()$top_users
    if (!is.data.frame(data) || nrow(data) == 0) {
      return(DT::datatable(
        data.frame(Bilgi = "Kayıtlı oturum yok"),
        options = list(dom = "t", language = turkish_dt_language),
        rownames = FALSE
      ))
    }
    gosterim <- data.frame(
      Kullanici = ifelse(is.na(data$full_name) | data$full_name == "",
                         data$user_name, data$full_name),
      `Oturum Sayısı` = as.integer(data$session_count),
      check.names = FALSE, stringsAsFactors = FALSE
    )
    DT::datatable(
      gosterim,
      options = list(dom = "t", pageLength = 10, ordering = FALSE,
                     language = turkish_dt_language),
      rownames = FALSE
    )
  })

  output$by_recent_sessions_table <- DT::renderDataTable({
    data <- bilge_yolac_data_fn()$recent_sessions
    if (!is.data.frame(data) || nrow(data) == 0) {
      return(DT::datatable(
        data.frame(Bilgi = "Kayıtlı oturum yok"),
        options = list(dom = "t", language = turkish_dt_language),
        rownames = FALSE
      ))
    }
    gosterim <- data.frame(
      Baslik = as.character(data$SessionTitle),
      Kullanici = as.character(data$user_name),
      Model = as.character(data$model_name),
      `Çalıştırma` = as.integer(data$run_count),
      `Son Etkinlik` = as.character(data$last_activity),
      check.names = FALSE, stringsAsFactors = FALSE
    )
    DT::datatable(
      gosterim,
      options = list(dom = "tp", pageLength = 8, ordering = FALSE,
                     language = turkish_dt_language),
      rownames = FALSE
    )
  })
}
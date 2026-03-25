# Dosya Yolu: R/module_admin_yanit_analizi.R
# Açıklama: Yönetici paneli - Yanıt Geri Bildirimi Analizi modülü.
#            MB_Feedback tablosundaki kullanıcıların yapay zekâ yanıtlarına verdikleri
#            beğeni/beğenmeme geri bildirimlerini çok boyutlu olarak analiz eder.
#            Model performansı, kullanıcı davranışları, etiket analizi ve zaman bazlı
#            trendler için gelişmiş grafikler ve tablolar sunar.

# ==============================================================================
# UI FONKSİYONU
# ==============================================================================

adminYanitAnaliziUI <- function(id) {
  ns <- NS(id)

  admin_page_layout(
    ns = ns,
    page_title = "Yanıt Geri Bildirimi Analizi",
    page_icon = "thumbs-up",
    tab_panels = list(
      tabPanel(
        title = tags$span(
          title = "Genel geri bildirim metrikleri ve özet göstergeler",
          tagList(icon("chart-line"), " Genel Bakış")
        ),
        value = "ya_overview"
      ),
      tabPanel(
        title = tags$span(
          title = "Model bazlı performans karşılaştırması ve analiz",
          tagList(icon("robot"), " Model Performansı")
        ),
        value = "ya_model"
      ),
      tabPanel(
        title = tags$span(
          title = "Etiket dağılımı ve kullanıcı yorumları detaylı analiz",
          tagList(icon("tags"), " Etiket & Yorum Analizi")
        ),
        value = "ya_etiket"
      ),
      tabPanel(
        title = tags$span(
          title = "Zamana göre geri bildirim trendleri ve kullanıcı davranışları",
          tagList(icon("clock"), " Zaman & Kullanıcı Analizi")
        ),
        value = "ya_zaman"
      )
    )
  )
}

# ==============================================================================
# SERVER FONKSİYONU
# ==============================================================================

adminYanitAnaliziServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Yenileme altyapısı (paylaşılan yardımcı)
    refresh <- admin_refresh_setup(input, session)

    # ============================================================
    # VERİ ÇEKİMİ
    # ============================================================
    ya_data <- reactive({
      refresh$trigger()

      list(
        # Toplam geri bildirim sayısı
        toplam = admin_safe_query("
          SELECT COUNT(*) as cnt FROM MB_Feedback
        "),

        # Beğeni / beğenmeme dağılımı
        tip_dagilim = admin_safe_query("
          SELECT FeedbackType, COUNT(*) as cnt
          FROM MB_Feedback
          GROUP BY FeedbackType
        "),

        # Günlük trend (son 30 gün)
        gunluk_trend = admin_safe_query("
          SELECT
            CAST(ISNULL(f.FeedbackTimestamp, m.MessageTimestamp) AS DATE) as tarih,
            SUM(CASE WHEN f.FeedbackType = 'like' THEN 1 ELSE 0 END) as begeni,
            SUM(CASE WHEN f.FeedbackType = 'dislike' THEN 1 ELSE 0 END) as begenmeme,
            COUNT(*) as toplam
          FROM MB_Feedback f
          LEFT JOIN MB_Messages m ON f.MessageID = m.MessageID
          WHERE ISNULL(f.FeedbackTimestamp, m.MessageTimestamp) >= DATEADD(day, -30, GETDATE())
          GROUP BY CAST(ISNULL(f.FeedbackTimestamp, m.MessageTimestamp) AS DATE)
          ORDER BY tarih
        "),

        # Beğeni oranı (toplam)
        begeni_orani = admin_safe_query("
          SELECT
            SUM(CASE WHEN FeedbackType = 'like' THEN 1 ELSE 0 END) as begeni,
            SUM(CASE WHEN FeedbackType = 'dislike' THEN 1 ELSE 0 END) as begenmeme,
            COUNT(*) as toplam
          FROM MB_Feedback
        "),

        # Bugün gelen geri bildirimler
        bugun = admin_safe_query("
          SELECT
            SUM(CASE WHEN FeedbackType = 'like' THEN 1 ELSE 0 END) as begeni,
            SUM(CASE WHEN FeedbackType = 'dislike' THEN 1 ELSE 0 END) as begenmeme,
            COUNT(*) as toplam
          FROM MB_Feedback f
          LEFT JOIN MB_Messages m ON f.MessageID = m.MessageID
          WHERE CAST(ISNULL(f.FeedbackTimestamp, m.MessageTimestamp) AS DATE) = CAST(GETDATE() AS DATE)
        "),

        # Bu hafta gelen
        bu_hafta = admin_safe_query("
          SELECT COUNT(*) as cnt
          FROM MB_Feedback f
          LEFT JOIN MB_Messages m ON f.MessageID = m.MessageID
          WHERE ISNULL(f.FeedbackTimestamp, m.MessageTimestamp) >= DATEADD(day, -7, GETDATE())
        "),

        # Yorum içeren geri bildirim sayısı
        yorumlu = admin_safe_query("
          SELECT COUNT(*) as cnt
          FROM MB_Feedback
          WHERE FeedbackComment IS NOT NULL AND FeedbackComment <> ''
        "),

        # Model bazlı performans
        model_performans = admin_safe_query("
          SELECT
            u.ModelUsed,
            COUNT(*) as toplam_yanit,
            SUM(CASE WHEN f.FeedbackType = 'like' THEN 1 ELSE 0 END) as begeni,
            SUM(CASE WHEN f.FeedbackType = 'dislike' THEN 1 ELSE 0 END) as begenmeme,
            AVG(u.ResponseDuration) as ort_sure
          FROM MB_Usage_Log u
          JOIN MB_Messages m_ai ON u.MessageID = m_ai.MessageID AND m_ai.MessageType = 'ai'
          JOIN MB_Feedback f ON m_ai.MessageID = f.MessageID
          WHERE u.ModelUsed IS NOT NULL AND u.ModelUsed <> ''
          GROUP BY u.ModelUsed
          ORDER BY toplam_yanit DESC
        "),

        # Model bazlı beğeni oranı trendi (haftalık)
        model_haftalik_trend = admin_safe_query("
          SELECT
            DATEPART(ISO_WEEK, ISNULL(f.FeedbackTimestamp, m.MessageTimestamp)) as hafta,
            DATEPART(YEAR, ISNULL(f.FeedbackTimestamp, m.MessageTimestamp)) as yil,
            MIN(CAST(ISNULL(f.FeedbackTimestamp, m.MessageTimestamp) AS DATE)) as hafta_basi,
            SUM(CASE WHEN f.FeedbackType = 'like' THEN 1 ELSE 0 END) as begeni,
            SUM(CASE WHEN f.FeedbackType = 'dislike' THEN 1 ELSE 0 END) as begenmeme,
            COUNT(*) as toplam
          FROM MB_Feedback f
          LEFT JOIN MB_Messages m ON f.MessageID = m.MessageID
          WHERE ISNULL(f.FeedbackTimestamp, m.MessageTimestamp) >= DATEADD(week, -12, GETDATE())
          GROUP BY DATEPART(ISO_WEEK, ISNULL(f.FeedbackTimestamp, m.MessageTimestamp)),
                   DATEPART(YEAR, ISNULL(f.FeedbackTimestamp, m.MessageTimestamp))
          ORDER BY yil, hafta
        "),

        # Yanıt uzunluğuna göre beğeni dağılımı
        uzunluk_analiz = admin_safe_query("
          SELECT
            CASE
              WHEN LEN(m.MessageContent) < 500 THEN 'Kısa (< 500)'
              WHEN LEN(m.MessageContent) < 1500 THEN 'Orta (500-1500)'
              WHEN LEN(m.MessageContent) < 3000 THEN 'Uzun (1500-3000)'
              ELSE 'Çok Uzun (> 3000)'
            END as uzunluk_grubu,
            SUM(CASE WHEN f.FeedbackType = 'like' THEN 1 ELSE 0 END) as begeni,
            SUM(CASE WHEN f.FeedbackType = 'dislike' THEN 1 ELSE 0 END) as begenmeme,
            COUNT(*) as toplam
          FROM MB_Messages m
          JOIN MB_Feedback f ON m.MessageID = f.MessageID
          WHERE m.MessageType = 'ai'
          GROUP BY CASE
              WHEN LEN(m.MessageContent) < 500 THEN 'Kısa (< 500)'
              WHEN LEN(m.MessageContent) < 1500 THEN 'Orta (500-1500)'
              WHEN LEN(m.MessageContent) < 3000 THEN 'Uzun (1500-3000)'
              ELSE 'Çok Uzun (> 3000)'
            END
        "),

        # Yanıt süresine göre beğeni dağılımı
        sure_analiz = admin_safe_query("
          SELECT
            CASE
              WHEN u.ResponseDuration <= 5 THEN '0-5 sn'
              WHEN u.ResponseDuration <= 10 THEN '5-10 sn'
              WHEN u.ResponseDuration <= 20 THEN '10-20 sn'
              ELSE '20+ sn'
            END as sure_grubu,
            SUM(CASE WHEN f.FeedbackType = 'like' THEN 1 ELSE 0 END) as begeni,
            SUM(CASE WHEN f.FeedbackType = 'dislike' THEN 1 ELSE 0 END) as begenmeme,
            COUNT(*) as toplam
          FROM MB_Usage_Log u
          JOIN MB_Messages m ON u.MessageID = m.MessageID AND m.MessageType = 'ai'
          JOIN MB_Feedback f ON m.MessageID = f.MessageID
          WHERE u.ResponseDuration IS NOT NULL
          GROUP BY CASE
              WHEN u.ResponseDuration <= 5 THEN '0-5 sn'
              WHEN u.ResponseDuration <= 10 THEN '5-10 sn'
              WHEN u.ResponseDuration <= 20 THEN '10-20 sn'
              ELSE '20+ sn'
            END
        "),

        # Etiket dağılımı (FeedbackTags alanından)
        etiketler_ham = admin_safe_query("
          SELECT FeedbackTags, FeedbackType
          FROM MB_Feedback
          WHERE FeedbackTags IS NOT NULL AND FeedbackTags <> ''
        "),

        # En son yorumlar
        son_yorumlar = admin_safe_query("
          SELECT TOP 100
            f.FeedbackType, f.FeedbackTags, f.FeedbackComment, f.FeedbackTimestamp,
            f.MessageID, u.KaynakAdi AS KullaniciAdi,
            LEFT(m.MessageContent, 200) AS YanitOnizleme
          FROM MB_Feedback f
          LEFT JOIN MB_Users u ON f.UserID = u.UserID
          LEFT JOIN MB_Messages m ON f.MessageID = m.MessageID
          WHERE f.FeedbackComment IS NOT NULL AND f.FeedbackComment <> ''
          ORDER BY f.FeedbackTimestamp DESC
        "),

        # Kullanıcı bazlı geri bildirim özeti
        kullanici_ozet = admin_safe_query("
          SELECT
            u.KaynakAdi AS KullaniciAdi,
            COUNT(*) as toplam,
            SUM(CASE WHEN f.FeedbackType = 'like' THEN 1 ELSE 0 END) as begeni,
            SUM(CASE WHEN f.FeedbackType = 'dislike' THEN 1 ELSE 0 END) as begenmeme,
            MAX(ISNULL(f.FeedbackTimestamp, m.MessageTimestamp)) as son_bildirim
          FROM MB_Feedback f
          LEFT JOIN MB_Users u ON f.UserID = u.UserID
          LEFT JOIN MB_Messages m ON f.MessageID = m.MessageID
          GROUP BY f.UserID, u.KaynakAdi
          ORDER BY toplam DESC
        "),

        # Saatlik dağılım
        saatlik_dagilim = admin_safe_query("
          SELECT
            DATEPART(HOUR, ISNULL(f.FeedbackTimestamp, m.MessageTimestamp)) as saat,
            SUM(CASE WHEN f.FeedbackType = 'like' THEN 1 ELSE 0 END) as begeni,
            SUM(CASE WHEN f.FeedbackType = 'dislike' THEN 1 ELSE 0 END) as begenmeme,
            COUNT(*) as toplam
          FROM MB_Feedback f
          LEFT JOIN MB_Messages m ON f.MessageID = m.MessageID
          GROUP BY DATEPART(HOUR, ISNULL(f.FeedbackTimestamp, m.MessageTimestamp))
          ORDER BY saat
        "),

        # Gün bazlı dağılım (haftanın günleri)
        gunluk_dagilim = admin_safe_query("
          SELECT
            DATEPART(WEEKDAY, ISNULL(f.FeedbackTimestamp, m.MessageTimestamp)) as gun_no,
            SUM(CASE WHEN f.FeedbackType = 'like' THEN 1 ELSE 0 END) as begeni,
            SUM(CASE WHEN f.FeedbackType = 'dislike' THEN 1 ELSE 0 END) as begenmeme,
            COUNT(*) as toplam
          FROM MB_Feedback f
          LEFT JOIN MB_Messages m ON f.MessageID = m.MessageID
          GROUP BY DATEPART(WEEKDAY, ISNULL(f.FeedbackTimestamp, m.MessageTimestamp))
          ORDER BY gun_no
        "),

        # Tüm geri bildirimler (detaylı tablo için)
        tumu = admin_safe_query("
          SELECT TOP 500
            f.UserID, f.MessageID, f.FeedbackType,
            f.FeedbackTags, f.FeedbackComment, f.FeedbackTimestamp,
            u.KaynakAdi AS KullaniciAdi,
            ul.ModelUsed,
            LEFT(m.MessageContent, 300) AS YanitOnizleme
          FROM MB_Feedback f
          LEFT JOIN MB_Users u ON f.UserID = u.UserID
          LEFT JOIN MB_Messages m ON f.MessageID = m.MessageID
          LEFT JOIN MB_Usage_Log ul ON m.MessageID = ul.MessageID
          ORDER BY ISNULL(f.FeedbackTimestamp, m.MessageTimestamp) DESC
        ")
      )
    })

    # ============================================================
    # ETİKET ÇÖZÜMLEME
    # ============================================================
    etiket_sayilari <- reactive({
      ham <- ya_data()$etiketler_ham
      if (nrow(ham) == 0) return(data.frame(etiket = character(0), cnt = integer(0),
                                             tip = character(0), stringsAsFactors = FALSE))

      # Her satırdaki virgülle ayrılmış etiketleri çözümle
      sonuc <- do.call(rbind, lapply(seq_len(nrow(ham)), function(i) {
        etiketler <- trimws(unlist(strsplit(ham$FeedbackTags[i], ",")))
        etiketler <- etiketler[nzchar(etiketler)]
        if (length(etiketler) == 0) return(NULL)
        data.frame(etiket = etiketler, tip = ham$FeedbackType[i], stringsAsFactors = FALSE)
      }))

      if (is.null(sonuc) || nrow(sonuc) == 0)
        return(data.frame(etiket = character(0), cnt = integer(0),
                          tip = character(0), stringsAsFactors = FALSE))

      # Genel sayım
      genel <- as.data.frame(table(sonuc$etiket), stringsAsFactors = FALSE)
      colnames(genel) <- c("etiket", "cnt")

      # Tip bazlı sayım
      begeni_tbl <- as.data.frame(table(sonuc$etiket[sonuc$tip == "like"]), stringsAsFactors = FALSE)
      begenmeme_tbl <- as.data.frame(table(sonuc$etiket[sonuc$tip == "dislike"]), stringsAsFactors = FALSE)

      if (nrow(begeni_tbl) > 0) colnames(begeni_tbl) <- c("etiket", "begeni_cnt")
      else begeni_tbl <- data.frame(etiket = character(0), begeni_cnt = integer(0))

      if (nrow(begenmeme_tbl) > 0) colnames(begenmeme_tbl) <- c("etiket", "begenmeme_cnt")
      else begenmeme_tbl <- data.frame(etiket = character(0), begenmeme_cnt = integer(0))

      genel <- merge(genel, begeni_tbl, by = "etiket", all.x = TRUE)
      genel <- merge(genel, begenmeme_tbl, by = "etiket", all.x = TRUE)
      genel$begeni_cnt[is.na(genel$begeni_cnt)] <- 0
      genel$begenmeme_cnt[is.na(genel$begenmeme_cnt)] <- 0

      genel[order(-genel$cnt), ]
    })

    # ============================================================
    # SEKME İÇERİĞİ YÖNLENDİRİCİ
    # ============================================================
    output$tab_content_area <- renderUI({
      tab <- input$admin_tabs
      if (is.null(tab)) tab <- "ya_overview"

      admin_init_tooltips(session)

      switch(tab,
        "ya_overview" = ya_overview_ui(),
        "ya_model"    = ya_model_ui(),
        "ya_etiket"   = ya_etiket_ui(),
        "ya_zaman"    = ya_zaman_ui(),
        ya_overview_ui()
      )
    })

    # ============================================================
    # SEKME 1: GENEL BAKIŞ
    # ============================================================
    ya_overview_ui <- function() {
      data <- ya_data()

      toplam <- if (nrow(data$toplam) > 0) data$toplam$cnt[1] else 0

      # Beğeni oranı hesapla
      begeni_cnt <- 0; begenmeme_cnt <- 0
      if (nrow(data$begeni_orani) > 0) {
        begeni_cnt <- data$begeni_orani$begeni[1] %||% 0
        begenmeme_cnt <- data$begeni_orani$begenmeme[1] %||% 0
      }
      begeni_oran <- if (toplam > 0) sprintf("%.1f%%", (begeni_cnt / toplam) * 100) else "N/A"

      # Bugünkü veriler
      bugun_toplam <- if (nrow(data$bugun) > 0) data$bugun$toplam[1] %||% 0 else 0
      hafta_cnt <- if (nrow(data$bu_hafta) > 0) data$bu_hafta$cnt[1] else 0
      yorumlu_cnt <- if (nrow(data$yorumlu) > 0) data$yorumlu$cnt[1] else 0
      yorum_oran <- if (toplam > 0) sprintf("%.1f%%", (yorumlu_cnt / toplam) * 100) else "N/A"

      tagList(
        div(
          class = "metrics-grid",
          admin_create_metric_card("Toplam Geri Bildirim", admin_format_number(toplam), "comments", "blue",
            tooltip = "Kullanıcıların yapay zekâ yanıtlarına verdikleri toplam geri bildirim sayısı."),
          admin_create_metric_card("Beğeni Oranı", begeni_oran, "thumbs-up", "green",
            tooltip = "Toplam geri bildirimlerin içinde beğeni oranı."),
          admin_create_metric_card("Beğeni", admin_format_number(begeni_cnt), "heart", "green",
            tooltip = "Toplam beğeni sayısı."),
          admin_create_metric_card("Beğenmeme", admin_format_number(begenmeme_cnt), "thumbs-down", "red",
            tooltip = "Toplam beğenmeme sayısı."),
          admin_create_metric_card("Bugün Gelen", admin_format_number(bugun_toplam), "calendar-day", "orange",
            tooltip = "Bugün alınan geri bildirim sayısı."),
          admin_create_metric_card("Yorum İçeren", yorum_oran, "comment", "purple",
            tooltip = "Metin yorumu içeren geri bildirim oranı.")
        ),
        fluidRow(
          column(
            width = 8,
            div(
              class = "analytics-card",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("chart-area"), " Günlük Geri Bildirim Trendi (30 Gün)"),
                admin_create_info_button("Son 30 gündeki günlük beğeni ve beğenmeme sayıları.")
              ),
              highcharter::highchartOutput(ns("ya_gunluk_trend_chart"), height = "320px")
            )
          ),
          column(
            width = 4,
            div(
              class = "analytics-card",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("chart-pie"), " Beğeni / Beğenmeme Dağılımı"),
                admin_create_info_button("Tüm geri bildirimlerin beğeni ve beğenmeme olarak dağılımı.")
              ),
              highcharter::highchartOutput(ns("ya_tip_pie_chart"), height = "320px")
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
                h4(class = "card-title", icon("ruler-combined"), " Yanıt Uzunluğuna Göre Beğeni"),
                admin_create_info_button("Yapay zekâ yanıt uzunluğu ile beğeni/beğenmeme ilişkisi.")
              ),
              highcharter::highchartOutput(ns("ya_uzunluk_chart"), height = "320px")
            )
          ),
          column(
            width = 6,
            div(
              class = "analytics-card",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("stopwatch"), " Yanıt Süresine Göre Beğeni"),
                admin_create_info_button("Yanıt süresi ile kullanıcı memnuniyeti arasındaki ilişki.")
              ),
              highcharter::highchartOutput(ns("ya_sure_chart"), height = "320px")
            )
          )
        )
      )
    }

    # ============================================================
    # SEKME 2: MODEL PERFORMANSI
    # ============================================================
    ya_model_ui <- function() {
      tagList(
        fluidRow(
          column(
            width = 12,
            div(
              class = "analytics-card",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("robot"), " Model Bazlı Beğeni Performansı"),
                admin_create_info_button("Her modelin beğeni ve beğenmeme dağılımı. Oranlar, modelin kullanıcı memnuniyetini gösterir.")
              ),
              highcharter::highchartOutput(ns("ya_model_bar_chart"), height = "400px")
            )
          )
        ),
        fluidRow(
          column(
            width = 7,
            div(
              class = "analytics-card",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("chart-line"), " Haftalık Beğeni Oranı Trendi"),
                admin_create_info_button("Son 12 haftadaki beğeni oranı değişimi (beğeni / toplam \U00D7 100).")
              ),
              highcharter::highchartOutput(ns("ya_haftalik_oran_chart"), height = "380px")
            )
          ),
          column(
            width = 5,
            div(
              class = "analytics-card",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("table"), " Model Karşılaştırma Tablosu"),
                admin_create_info_button("Modellerin detaylı performans karşılaştırması: toplam yanıt, beğeni oranı ve ortalama yanıt süresi.")
              ),
              div(class = "table-container scrollable-table-equal",
                DT::DTOutput(ns("ya_model_tablo")))
            )
          )
        )
      )
    }

    # ============================================================
    # SEKME 3: ETİKET & YORUM ANALİZİ
    # ============================================================
    ya_etiket_ui <- function() {
      tagList(
        fluidRow(
          column(
            width = 6,
            div(
              class = "analytics-card",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("sitemap"), " Etiket Dağılımı (Ağaç Haritası)"),
                admin_create_info_button("Kullanıcıların geri bildirimde seçtiği etiketlerin görsel dağılımı.")
              ),
              highcharter::highchartOutput(ns("ya_etiket_treemap_chart"), height = "380px")
            )
          ),
          column(
            width = 6,
            div(
              class = "analytics-card",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("balance-scale"), " Etiket Bazlı Beğeni / Beğenmeme"),
                admin_create_info_button("Her etiketin beğeni ve beğenmeme olarak dağılımı. Hangi konuların daha çok beğenildiğini veya eleştirildiğini gösterir.")
              ),
              highcharter::highchartOutput(ns("ya_etiket_diverging_chart"), height = "380px")
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
                h4(class = "card-title", icon("comment-dots"), " Son Kullanıcı Yorumları"),
                admin_create_info_button("Kullanıcıların bıraktığı son metin yorumları. Yanıt önizlemesi ve geri bildirim tipi ile birlikte gösterilir.")
              ),
              div(class = "table-container", DT::DTOutput(ns("ya_yorum_tablo")))
            )
          )
        )
      )
    }

    # ============================================================
    # SEKME 4: ZAMAN & KULLANICI ANALİZİ
    # ============================================================
    ya_zaman_ui <- function() {
      tagList(
        fluidRow(
          column(
            width = 12,
            div(
              class = "analytics-card",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("th"), " Saat \U00D7 Gün Isı Haritası"),
                admin_create_info_button("Haftanın günleri ve günün saatlerine göre geri bildirim yoğunluğu.")
              ),
              highcharter::highchartOutput(ns("ya_saat_gun_heatmap"), height = "350px")
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
                h4(class = "card-title", icon("clock"), " Saatlere Göre Geri Bildirim"),
                admin_create_info_button("Günün hangi saatlerinde daha fazla geri bildirim verildiği.")
              ),
              highcharter::highchartOutput(ns("ya_saatlik_chart"), height = "320px")
            )
          ),
          column(
            width = 6,
            div(
              class = "analytics-card",
              style = "min-height: 400px;",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("users"), " Kullanıcı Bazlı Geri Bildirim"),
                admin_create_info_button("En çok geri bildirim veren kullanıcılar ve beğeni oranları.")
              ),
              div(class = "table-container scrollable-table-equal",
                DT::DTOutput(ns("ya_kullanici_tablo")))
            )
          )
        )
      )
    }

    # ============================================================
    # GRAFİKLER: GENEL BAKIŞ
    # ============================================================

    # Günlük trend (beğeni / beğenmeme yığılmış alan)
    output$ya_gunluk_trend_chart <- highcharter::renderHighchart({
      data <- ya_data()$gunluk_trend
      if (nrow(data) == 0) return(highcharter::highchart())

      data$tarih_label <- vapply(data$tarih, admin_format_turkish_date, character(1))

      highcharter::highchart() %>%
        highcharter::hc_chart(backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = data$tarih_label,
          labels = list(style = list(color = "#999"))
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Geri Bildirim Sayısı", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#444", min = 0
        ) %>%
        highcharter::hc_plotOptions(
          areaspline = list(
            stacking = "normal",
            marker = list(enabled = FALSE),
            lineWidth = 2
          )
        ) %>%
        highcharter::hc_add_series(
          name = "Beğeni", data = data$begeni, type = "areaspline",
          color = "#10b981",
          fillColor = list(
            linearGradient = list(x1 = 0, y1 = 0, x2 = 0, y2 = 1),
            stops = list(list(0, "rgba(16, 185, 129, 0.4)"), list(1, "rgba(16, 185, 129, 0.05)"))
          )
        ) %>%
        highcharter::hc_add_series(
          name = "Beğenmeme", data = data$begenmeme, type = "areaspline",
          color = "#ef4444",
          fillColor = list(
            linearGradient = list(x1 = 0, y1 = 0, x2 = 0, y2 = 1),
            stops = list(list(0, "rgba(239, 68, 68, 0.4)"), list(1, "rgba(239, 68, 68, 0.05)"))
          )
        ) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a", borderColor = "#333",
          style = list(color = "#fff"), shared = TRUE
        ) %>%
        highcharter::hc_legend(itemStyle = list(color = "#999")) %>%
        highcharter::hc_credits(enabled = FALSE)
    })

    # Beğeni / beğenmeme dağılım pastası
    output$ya_tip_pie_chart <- highcharter::renderHighchart({
      data <- ya_data()$tip_dagilim
      if (nrow(data) == 0) return(highcharter::highchart())

      tip_renkler <- c("like" = "#10b981", "dislike" = "#ef4444")
      tip_etiketler <- c("like" = "Beğeni", "dislike" = "Beğenmeme")

      chart_data <- lapply(1:nrow(data), function(i) {
        tip <- data$FeedbackType[i]
        list(
          name = ifelse(tip %in% names(tip_etiketler), tip_etiketler[tip], tip),
          y = data$cnt[i],
          color = ifelse(tip %in% names(tip_renkler), tip_renkler[tip], "#94a3b8")
        )
      })

      highcharter::highchart() %>%
        highcharter::hc_chart(type = "pie", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_plotOptions(
          pie = list(
            innerSize = "65%", borderWidth = 0,
            dataLabels = list(
              enabled = TRUE,
              format = "<b>{point.name}</b>: {point.percentage:.1f}%",
              style = list(color = "#fff", textOutline = "none")
            )
          )
        ) %>%
        highcharter::hc_add_series(name = "Geri Bildirim", data = chart_data) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a", borderColor = "#333",
          style = list(color = "#fff"),
          pointFormat = "<b>{point.y}</b> geri bildirim ({point.percentage:.1f}%)"
        ) %>%
        highcharter::hc_credits(enabled = FALSE)
    })

    # Yanıt uzunluğuna göre beğeni (yığılmış yatay çubuk)
    output$ya_uzunluk_chart <- highcharter::renderHighchart({
      data <- ya_data()$uzunluk_analiz
      if (nrow(data) == 0) return(highcharter::highchart())

      # Sıralama: Kısa -> Çok Uzun
      sira <- c("Kısa (< 500)", "Orta (500-1500)", "Uzun (1500-3000)", "Çok Uzun (> 3000)")
      data$uzunluk_grubu <- factor(data$uzunluk_grubu, levels = sira)
      data <- data[order(data$uzunluk_grubu), ]
      data <- data[!is.na(data$uzunluk_grubu), ]

      # Beğeni oranını hesapla
      data$begeni_oran <- ifelse(data$toplam > 0, round((data$begeni / data$toplam) * 100, 1), 0)

      highcharter::highchart() %>%
        highcharter::hc_chart(type = "bar", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = as.character(data$uzunluk_grubu),
          labels = list(style = list(color = "#ccc", fontSize = "12px"))
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Geri Bildirim Sayısı", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#444",
          stackLabels = list(enabled = TRUE, style = list(color = "#fff", textOutline = "none"))
        ) %>%
        highcharter::hc_plotOptions(
          bar = list(stacking = "normal", borderWidth = 0, borderRadius = 3)
        ) %>%
        highcharter::hc_add_series(name = "Beğeni", data = data$begeni, color = "#10b981") %>%
        highcharter::hc_add_series(name = "Beğenmeme", data = data$begenmeme, color = "#ef4444") %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a", borderColor = "#333",
          style = list(color = "#fff"), shared = TRUE
        ) %>%
        highcharter::hc_legend(itemStyle = list(color = "#999")) %>%
        highcharter::hc_credits(enabled = FALSE)
    })

    # Yanıt süresine göre beğeni (yığılmış yatay çubuk)
    output$ya_sure_chart <- highcharter::renderHighchart({
      data <- ya_data()$sure_analiz
      if (nrow(data) == 0) return(highcharter::highchart())

      sira <- c("0-5 sn", "5-10 sn", "10-20 sn", "20+ sn")
      data$sure_grubu <- factor(data$sure_grubu, levels = sira)
      data <- data[order(data$sure_grubu), ]
      data <- data[!is.na(data$sure_grubu), ]

      highcharter::highchart() %>%
        highcharter::hc_chart(type = "bar", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = as.character(data$sure_grubu),
          labels = list(style = list(color = "#ccc", fontSize = "12px"))
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Geri Bildirim Sayısı", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#444",
          stackLabels = list(enabled = TRUE, style = list(color = "#fff", textOutline = "none"))
        ) %>%
        highcharter::hc_plotOptions(
          bar = list(stacking = "normal", borderWidth = 0, borderRadius = 3)
        ) %>%
        highcharter::hc_add_series(name = "Beğeni", data = data$begeni, color = "#10b981") %>%
        highcharter::hc_add_series(name = "Beğenmeme", data = data$begenmeme, color = "#ef4444") %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a", borderColor = "#333",
          style = list(color = "#fff"), shared = TRUE
        ) %>%
        highcharter::hc_legend(itemStyle = list(color = "#999")) %>%
        highcharter::hc_credits(enabled = FALSE)
    })

    # ============================================================
    # GRAFİKLER: MODEL PERFORMANSI
    # ============================================================

    # Model bazlı beğeni performansı (diverging bar chart)
    output$ya_model_bar_chart <- highcharter::renderHighchart({
      data <- ya_data()$model_performans
      if (nrow(data) == 0) return(highcharter::highchart())

      data$begeni_oran <- ifelse(data$toplam_yanit > 0, round((data$begeni / data$toplam_yanit) * 100, 1), 0)
      data$begenmeme_oran <- ifelse(data$toplam_yanit > 0, round((data$begenmeme / data$toplam_yanit) * 100, 1), 0)
      data <- data[order(-data$begeni_oran), ]

      # Model isimlerini kısalt (çok uzunsa)
      data$model_kisa <- sapply(data$ModelUsed, function(m) {
        if (nchar(m) > 35) paste0(substr(m, 1, 32), "...") else m
      })

      highcharter::highchart() %>%
        highcharter::hc_chart(type = "bar", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = data$model_kisa,
          labels = list(style = list(color = "#ccc", fontSize = "12px"))
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Geri Bildirim Sayısı", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#444",
          stackLabels = list(enabled = TRUE, style = list(color = "#fff", textOutline = "none"))
        ) %>%
        highcharter::hc_plotOptions(
          bar = list(stacking = "normal", borderWidth = 0, borderRadius = 4)
        ) %>%
        highcharter::hc_add_series(name = "Beğeni", data = data$begeni, color = "#10b981") %>%
        highcharter::hc_add_series(name = "Beğenmeme", data = data$begenmeme, color = "#ef4444") %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a", borderColor = "#333",
          style = list(color = "#fff"), shared = TRUE,
          headerFormat = "<b>{point.key}</b><br/>",
          pointFormat = "{series.name}: <b>{point.y}</b><br/>"
        ) %>%
        highcharter::hc_legend(itemStyle = list(color = "#999")) %>%
        highcharter::hc_credits(enabled = FALSE)
    })

    # Haftalık beğeni oranı trendi (areaspline)
    output$ya_haftalik_oran_chart <- highcharter::renderHighchart({
      data <- ya_data()$model_haftalik_trend
      if (nrow(data) == 0) return(highcharter::highchart())

      data <- data[order(data$yil, data$hafta), ]
      data$oran <- ifelse(data$toplam > 0, round((data$begeni / data$toplam) * 100, 1), 0)

      data$label <- vapply(seq_len(nrow(data)), function(i) {
        if (nrow(data) <= 3) {
          tryCatch(format(as.Date(data$hafta_basi[i]), "%d.%m.%Y"), error = function(e) paste0("H", data$hafta[i]))
        } else {
          paste0("H", data$hafta[i])
        }
      }, character(1))

      chart_data <- lapply(seq_len(nrow(data)), function(i) {
        list(
          y = data$oran[i],
          begeni = data$begeni[i],
          begenmeme = data$begenmeme[i],
          toplam = data$toplam[i],
          hafta_basi = tryCatch(format(as.Date(data$hafta_basi[i]), "%d.%m.%Y"), error = function(e) "-")
        )
      })

      highcharter::highchart() %>%
        highcharter::hc_chart(type = "areaspline", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = as.list(data$label),
          labels = list(style = list(color = "#999"))
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Beğeni Oranı (%)", style = list(color = "#999")),
          labels = list(style = list(color = "#999"), format = "{value}%"),
          gridLineColor = "#444", min = 0, max = 100
        ) %>%
        highcharter::hc_plotOptions(
          areaspline = list(
            marker = list(enabled = TRUE, radius = 4),
            lineWidth = 3
          )
        ) %>%
        highcharter::hc_add_series(
          name = "Beğeni Oranı", data = chart_data,
          color = "#6366f1",
          fillColor = list(
            linearGradient = list(x1 = 0, y1 = 0, x2 = 0, y2 = 1),
            stops = list(
              list(0, "rgba(99, 102, 241, 0.3)"),
              list(1, "rgba(99, 102, 241, 0)")
            )
          )
        ) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a", borderColor = "#333",
          style = list(color = "#fff"),
          formatter = JS("function() {
            return '<b>Hafta başlangıcı:</b> ' + this.point.hafta_basi +
              '<br/><b>Beğeni Oranı:</b> ' + this.y + '%' +
              '<br/><b>Beğeni:</b> ' + this.point.begeni +
              '<br/><b>Beğenmeme:</b> ' + this.point.begenmeme +
              '<br/><b>Toplam:</b> ' + this.point.toplam;
          }")
        ) %>%
        highcharter::hc_legend(enabled = FALSE) %>%
        highcharter::hc_credits(enabled = FALSE)
    })

    # Model karşılaştırma tablosu
    output$ya_model_tablo <- DT::renderDT({
      data <- ya_data()$model_performans
      if (nrow(data) == 0) return(DT::datatable(data.frame()))

      data$row_num <- 1:nrow(data)
      data$begeni_oran <- ifelse(data$toplam_yanit > 0, round((data$begeni / data$toplam_yanit) * 100, 1), 0)
      data$ort_sure <- round(data$ort_sure, 1)

      # Beğeni oranı renkli gösterim
      data$oran_display <- sapply(data$begeni_oran, function(o) {
        renk <- if (o >= 80) "#10b981" else if (o >= 60) "#f59e0b" else "#ef4444"
        sprintf('<span style="color:%s; font-weight:bold;">%.1f%%</span>', renk, o)
      })

      display_data <- data[, c("row_num", "ModelUsed", "toplam_yanit", "begeni", "begenmeme", "oran_display", "ort_sure")]
      colnames(display_data) <- c("#", "Model", "Toplam", "Beğeni", "Beğenmeme", "Oran", "Ort. Süre (sn)")

      DT::datatable(
        display_data,
        escape = FALSE,
        options = list(
          dom = 't', pageLength = 20, scrollY = FALSE,
          ordering = TRUE, order = list(list(2, 'desc')),
          language = admin_turkish_dt_language,
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

    # ============================================================
    # GRAFİKLER: ETİKET & YORUM ANALİZİ
    # ============================================================

    # Etiket treemap
    output$ya_etiket_treemap_chart <- highcharter::renderHighchart({
      data <- etiket_sayilari()
      if (nrow(data) == 0) return(highcharter::highchart())

      treemap_renkler <- c("#6366f1", "#8b5cf6", "#06b6d4", "#f59e0b", "#ef4444", "#22c55e", "#ec4899")

      chart_data <- lapply(1:nrow(data), function(i) {
        list(
          name = data$etiket[i],
          value = data$cnt[i],
          color = treemap_renkler[((i - 1) %% length(treemap_renkler)) + 1]
        )
      })

      highcharter::highchart() %>%
        highcharter::hc_chart(type = "treemap", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_add_series(
          data = chart_data,
          layoutAlgorithm = "squarified",
          borderWidth = 2, borderColor = "#1a1a1a",
          dataLabels = list(
            enabled = TRUE,
            format = "<b>{point.name}</b><br/>{point.value}",
            style = list(color = "#fff", textOutline = "none", fontSize = "13px")
          )
        ) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a", borderColor = "#333",
          style = list(color = "#fff"),
          pointFormat = "<b>{point.name}</b>: {point.value} kez seçildi"
        ) %>%
        highcharter::hc_credits(enabled = FALSE)
    })

    # Etiket bazlı beğeni / beğenmeme (diverging bar chart)
    output$ya_etiket_diverging_chart <- highcharter::renderHighchart({
      data <- etiket_sayilari()
      if (nrow(data) == 0) return(highcharter::highchart())

      # En çok kullanılan 15 etiketi al
      data <- head(data, 15)

      highcharter::highchart() %>%
        highcharter::hc_chart(type = "bar", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = data$etiket,
          labels = list(style = list(color = "#ccc", fontSize = "12px"))
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Seçilme Sayısı", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#444",
          stackLabels = list(enabled = TRUE, style = list(color = "#fff", textOutline = "none"))
        ) %>%
        highcharter::hc_plotOptions(
          bar = list(stacking = "normal", borderWidth = 0, borderRadius = 3)
        ) %>%
        highcharter::hc_add_series(name = "Beğenide Seçilen", data = data$begeni_cnt, color = "#10b981") %>%
        highcharter::hc_add_series(name = "Beğenmemede Seçilen", data = data$begenmeme_cnt, color = "#ef4444") %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a", borderColor = "#333",
          style = list(color = "#fff"), shared = TRUE
        ) %>%
        highcharter::hc_legend(itemStyle = list(color = "#999")) %>%
        highcharter::hc_credits(enabled = FALSE)
    })

    # Son kullanıcı yorumları tablosu
    output$ya_yorum_tablo <- DT::renderDT({
      data <- ya_data()$son_yorumlar
      if (nrow(data) == 0) return(DT::datatable(data.frame()))

      data$row_num <- 1:nrow(data)

      # Geri bildirim tipi ikonu
      data$tip_display <- ifelse(
        data$FeedbackType == "like",
        '<span style="color:#10b981;"><i class="fas fa-thumbs-up"></i> Beğeni</span>',
        '<span style="color:#ef4444;"><i class="fas fa-thumbs-down"></i> Beğenmeme</span>'
      )

      data$tarih <- ifelse(
        !is.na(data$FeedbackTimestamp),
        format(as.POSIXct(data$FeedbackTimestamp), "%d.%m.%Y %H:%M"),
        "-"
      )
      data$kullanici <- ifelse(!is.na(data$KullaniciAdi) & nzchar(data$KullaniciAdi), data$KullaniciAdi, "-")
      data$etiketler <- ifelse(!is.na(data$FeedbackTags) & nzchar(data$FeedbackTags), data$FeedbackTags, "-")
      data$yorum <- ifelse(!is.na(data$FeedbackComment) & nzchar(data$FeedbackComment), data$FeedbackComment, "-")
      data$onizleme <- ifelse(!is.na(data$YanitOnizleme) & nzchar(data$YanitOnizleme),
        paste0(substr(data$YanitOnizleme, 1, 120), "..."), "-")

      display_data <- data[, c("row_num", "kullanici", "tip_display", "etiketler", "yorum", "onizleme", "tarih")]
      colnames(display_data) <- c("#", "Kullanıcı", "Tip", "Etiketler", "Yorum", "Yanıt Önizleme", "Tarih")

      DT::datatable(
        display_data,
        escape = FALSE,
        options = list(
          dom = 'frtip', pageLength = 15,
          ordering = TRUE, order = list(list(6, 'desc')),
          language = admin_turkish_dt_language,
          columnDefs = list(
            list(className = 'dt-center', targets = c(0, 2, 6)),
            list(className = 'row-number-col', targets = 0),
            list(width = '40px', targets = 0),
            list(width = '200px', targets = c(4, 5)),
            list(orderable = FALSE, targets = 0)
          ),
          headerCallback = admin_dt_header_callback
        ),
        class = "admin-datatable", rownames = FALSE
      )
    })

    # ============================================================
    # GRAFİKLER: ZAMAN & KULLANICI ANALİZİ
    # ============================================================

    # Saat \U00D7 Gün ısı haritası
    output$ya_saat_gun_heatmap <- highcharter::renderHighchart({
      # Yenile butonuna açık bağımlılık
      refresh$trigger()

      saatlik <- ya_data()$saatlik_dagilim
      gunluk <- ya_data()$gunluk_dagilim

      # Saatlik ve günlük verileri çapraz tablo için birleştir
      # SQL Server'da DATEPART(WEEKDAY, ...) 1=Pazar olarak döner
      # Saat \U00D7 gün ısı haritası için ayrı bir sorgu lazım
      # Mevcut verilerden oluşturabiliriz ancak ideal olan ayrı sorgu
      # Şimdilik saatlik veriyi kullan

      if (nrow(saatlik) == 0) return(highcharter::highchart())

      gun_isimleri <- admin_turkish_days
      saat_etiketleri <- sprintf("%02d:00", 0:23)

      # Basit saat bazlı polar grafik (beğeni vs beğenmeme)
      tam <- data.frame(saat = 0:23, begeni = 0, begenmeme = 0, toplam = 0)
      for (i in 1:nrow(saatlik)) {
        idx <- saatlik$saat[i] + 1
        if (idx >= 1 && idx <= 24) {
          tam$begeni[idx] <- saatlik$begeni[i]
          tam$begenmeme[idx] <- saatlik$begenmeme[i]
          tam$toplam[idx] <- saatlik$toplam[i]
        }
      }

      # Polar area chart (gül diyagramı)
      chart_data <- lapply(1:24, function(i) {
        list(
          y = tam$toplam[i],
          begeni = tam$begeni[i],
          begenmeme = tam$begenmeme[i],
          color = if (tam$toplam[i] == 0) "#333"
                  else if (tam$begeni[i] >= tam$begenmeme[i]) {
                    oran <- tam$begeni[i] / max(tam$toplam[i], 1)
                    sprintf("rgba(16, 185, 129, %.2f)", max(0.3, oran))
                  } else {
                    oran <- tam$begenmeme[i] / max(tam$toplam[i], 1)
                    sprintf("rgba(239, 68, 68, %.2f)", max(0.3, oran))
                  }
        )
      })

      highcharter::highchart() %>%
        highcharter::hc_chart(polar = TRUE, type = "column", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = saat_etiketleri,
          labels = list(style = list(color = "#999", fontSize = "10px")),
          tickmarkPlacement = "on", lineWidth = 0
        ) %>%
        highcharter::hc_yAxis(
          gridLineColor = "#333",
          labels = list(style = list(color = "#999")),
          min = 0
        ) %>%
        highcharter::hc_plotOptions(
          column = list(
            borderWidth = 0,
            pointPadding = 0,
            groupPadding = 0
          )
        ) %>%
        highcharter::hc_add_series(
          name = "Geri Bildirim", data = chart_data
        ) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a", borderColor = "#333",
          style = list(color = "#fff"),
          formatter = JS("function() {
            return '<b>' + this.x + '</b><br/>' +
              'Toplam: ' + this.y + '<br/>' +
              'Beğeni: ' + this.point.begeni + '<br/>' +
              'Beğenmeme: ' + this.point.begenmeme;
          }")
        ) %>%
        highcharter::hc_legend(enabled = FALSE) %>%
        highcharter::hc_credits(enabled = FALSE)
    })

    # Saatlik dağılım (çubuk grafik)
    output$ya_saatlik_chart <- highcharter::renderHighchart({
      refresh$trigger()
      data <- ya_data()$saatlik_dagilim
      if (nrow(data) == 0) return(highcharter::highchart())

      # 0-23 tüm saatleri doldur
      tam <- data.frame(saat = 0:23, begeni = 0, begenmeme = 0)
      for (i in 1:nrow(data)) {
        idx <- data$saat[i] + 1
        if (idx >= 1 && idx <= 24) {
          tam$begeni[idx] <- data$begeni[i]
          tam$begenmeme[idx] <- data$begenmeme[i]
        }
      }

      highcharter::highchart() %>%
        highcharter::hc_chart(type = "column", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = sprintf("%02d:00", 0:23),
          labels = list(style = list(color = "#999", fontSize = "10px"), rotation = -45)
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Sayı", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#444", min = 0,
          stackLabels = list(enabled = FALSE)
        ) %>%
        highcharter::hc_plotOptions(
          column = list(stacking = "normal", borderWidth = 0, borderRadius = 2)
        ) %>%
        highcharter::hc_add_series(name = "Beğeni", data = tam$begeni, color = "#10b981") %>%
        highcharter::hc_add_series(name = "Beğenmeme", data = tam$begenmeme, color = "#ef4444") %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a", borderColor = "#333",
          style = list(color = "#fff"), shared = TRUE
        ) %>%
        highcharter::hc_legend(itemStyle = list(color = "#999")) %>%
        highcharter::hc_credits(enabled = FALSE)
    })

    # Kullanıcı bazlı geri bildirim tablosu
    output$ya_kullanici_tablo <- DT::renderDT({
      data <- ya_data()$kullanici_ozet
      if (nrow(data) == 0) return(DT::datatable(data.frame()))

      data$row_num <- 1:nrow(data)
      data$begeni_oran <- ifelse(data$toplam > 0, round((data$begeni / data$toplam) * 100, 1), 0)
      data$son_bildirim <- format(as.POSIXct(data$son_bildirim), "%d.%m.%Y %H:%M")
      data$kullanici <- ifelse(!is.na(data$KullaniciAdi) & nzchar(data$KullaniciAdi), data$KullaniciAdi, "-")

      # Beğeni oranı renkli gösterim
      data$oran_display <- sapply(data$begeni_oran, function(o) {
        renk <- if (o >= 80) "#10b981" else if (o >= 60) "#f59e0b" else "#ef4444"
        sprintf('<span style="color:%s; font-weight:bold;">%.1f%%</span>', renk, o)
      })

      display_data <- data[, c("row_num", "kullanici", "toplam", "begeni", "begenmeme", "oran_display", "son_bildirim")]
      colnames(display_data) <- c("#", "Kullanıcı", "Toplam", "Beğeni", "Beğenmeme", "Oran", "Son Bildirim")

      DT::datatable(
        display_data,
        escape = FALSE,
        options = list(
          dom = 't', pageLength = 20, scrollY = FALSE,
          ordering = TRUE, order = list(list(2, 'desc')),
          language = admin_turkish_dt_language,
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

  })
}
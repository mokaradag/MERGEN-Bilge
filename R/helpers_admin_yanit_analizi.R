# ==============================================================================
# Dosya Yolu: R/helpers_admin_yanit_analizi.R
# Açıklama: Yönetici paneli - Yanıt Geri Bildirimi Analizi veri ve UI yardımcıları.
#            Public Shiny modül API'sini değiştirmeden sorgu paketi, etiket
#            çözümleme ve sekme UI düzenlerini ana modülden ayırır.
# ==============================================================================

admin_yanit_collect_data <- function(safe_query = admin_safe_query) {
  list(
    toplam = safe_query("
      SELECT COUNT(*) as cnt FROM MB_Feedback
    "),

    tip_dagilim = safe_query("
      SELECT FeedbackType, COUNT(*) as cnt
      FROM MB_Feedback
      GROUP BY FeedbackType
    "),

    gunluk_trend = safe_query("
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

    begeni_orani = safe_query("
      SELECT
        SUM(CASE WHEN FeedbackType = 'like' THEN 1 ELSE 0 END) as begeni,
        SUM(CASE WHEN FeedbackType = 'dislike' THEN 1 ELSE 0 END) as begenmeme,
        COUNT(*) as toplam
      FROM MB_Feedback
    "),

    bugun = safe_query("
      SELECT
        SUM(CASE WHEN FeedbackType = 'like' THEN 1 ELSE 0 END) as begeni,
        SUM(CASE WHEN FeedbackType = 'dislike' THEN 1 ELSE 0 END) as begenmeme,
        COUNT(*) as toplam
      FROM MB_Feedback f
      LEFT JOIN MB_Messages m ON f.MessageID = m.MessageID
      WHERE CAST(ISNULL(f.FeedbackTimestamp, m.MessageTimestamp) AS DATE) = CAST(GETDATE() AS DATE)
    "),

    bu_hafta = safe_query("
      SELECT COUNT(*) as cnt
      FROM MB_Feedback f
      LEFT JOIN MB_Messages m ON f.MessageID = m.MessageID
      WHERE ISNULL(f.FeedbackTimestamp, m.MessageTimestamp) >= DATEADD(day, -7, GETDATE())
    "),

    yorumlu = safe_query("
      SELECT COUNT(*) as cnt
      FROM MB_Feedback
      WHERE FeedbackComment IS NOT NULL AND FeedbackComment <> ''
    "),

    model_performans = safe_query("
      WITH usage_map AS (
        SELECT
          MessageID,
          MAX(ModelUsed) as ModelUsed,
          AVG(CAST(ResponseDuration AS FLOAT)) as ResponseDuration
        FROM MB_Usage_Log
        WHERE ModelUsed IS NOT NULL AND ModelUsed <> ''
        GROUP BY MessageID
      )
      SELECT
        um.ModelUsed,
        COUNT(*) as toplam_yanit,
        SUM(CASE WHEN f.FeedbackType = 'like' THEN 1 ELSE 0 END) as begeni,
        SUM(CASE WHEN f.FeedbackType = 'dislike' THEN 1 ELSE 0 END) as begenmeme,
        AVG(um.ResponseDuration) as ort_sure
      FROM usage_map um
      JOIN MB_Messages m_user ON um.MessageID = m_user.MessageID
      JOIN MB_Messages m_ai ON m_ai.ChatID = m_user.ChatID
        AND m_ai.MessageType = 'ai'
        AND m_ai.MessageOrder = m_user.MessageOrder + 1
      JOIN MB_Feedback f ON m_ai.MessageID = f.MessageID
      GROUP BY um.ModelUsed
      ORDER BY toplam_yanit DESC
    "),

    model_haftalik_trend = safe_query("
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

    uzunluk_analiz = safe_query("
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

    sure_analiz = safe_query("
      WITH usage_map AS (
        SELECT
          MessageID,
          AVG(CAST(ResponseDuration AS FLOAT)) as ResponseDuration
        FROM MB_Usage_Log
        WHERE ResponseDuration IS NOT NULL
        GROUP BY MessageID
      )
      SELECT
        CASE
          WHEN um.ResponseDuration <= 5 THEN '0-5 sn'
          WHEN um.ResponseDuration <= 10 THEN '5-10 sn'
          WHEN um.ResponseDuration <= 20 THEN '10-20 sn'
          ELSE '20+ sn'
        END as sure_grubu,
        SUM(CASE WHEN f.FeedbackType = 'like' THEN 1 ELSE 0 END) as begeni,
        SUM(CASE WHEN f.FeedbackType = 'dislike' THEN 1 ELSE 0 END) as begenmeme,
        COUNT(*) as toplam
      FROM usage_map um
      JOIN MB_Messages m_user ON um.MessageID = m_user.MessageID
      JOIN MB_Messages m_ai ON m_ai.ChatID = m_user.ChatID
        AND m_ai.MessageType = 'ai'
        AND m_ai.MessageOrder = m_user.MessageOrder + 1
      JOIN MB_Feedback f ON m_ai.MessageID = f.MessageID
      GROUP BY CASE
          WHEN um.ResponseDuration <= 5 THEN '0-5 sn'
          WHEN um.ResponseDuration <= 10 THEN '5-10 sn'
          WHEN um.ResponseDuration <= 20 THEN '10-20 sn'
          ELSE '20+ sn'
        END
    "),

    etiketler_ham = safe_query("
      SELECT FeedbackTags, FeedbackType
      FROM MB_Feedback
      WHERE FeedbackTags IS NOT NULL AND FeedbackTags <> ''
    "),

    son_yorumlar = safe_query("
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

    kullanici_ozet = safe_query("
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

    saatlik_dagilim = safe_query("
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

    gunluk_dagilim = safe_query("
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

    tumu = safe_query("
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
}

admin_yanit_tag_counts <- function(ham) {
  if (is.null(ham) || nrow(ham) == 0) {
    return(data.frame(
      etiket = character(0),
      cnt = integer(0),
      tip = character(0),
      stringsAsFactors = FALSE
    ))
  }

  sonuc <- do.call(rbind, lapply(seq_len(nrow(ham)), function(i) {
    raw_tags <- as.character(ham$FeedbackTags[i] %||% "")
    if (is.na(raw_tags) || !nzchar(raw_tags)) {
      return(NULL)
    }

    etiketler <- trimws(unlist(strsplit(raw_tags, ",")))
    etiketler <- etiketler[!is.na(etiketler) & nzchar(etiketler)]

    if (length(etiketler) == 0) {
      return(NULL)
    }

    data.frame(
      etiket = etiketler,
      tip = ham$FeedbackType[i],
      stringsAsFactors = FALSE
    )
  }))

  if (is.null(sonuc) || nrow(sonuc) == 0) {
    return(data.frame(
      etiket = character(0),
      cnt = integer(0),
      tip = character(0),
      stringsAsFactors = FALSE
    ))
  }

  genel <- as.data.frame(table(sonuc$etiket), stringsAsFactors = FALSE)
  colnames(genel) <- c("etiket", "cnt")

  begeni_tbl <- as.data.frame(table(sonuc$etiket[sonuc$tip == "like"]), stringsAsFactors = FALSE)
  begenmeme_tbl <- as.data.frame(table(sonuc$etiket[sonuc$tip == "dislike"]), stringsAsFactors = FALSE)

  if (nrow(begeni_tbl) > 0) {
    colnames(begeni_tbl) <- c("etiket", "begeni_cnt")
  } else {
    begeni_tbl <- data.frame(etiket = character(0), begeni_cnt = integer(0))
  }

  if (nrow(begenmeme_tbl) > 0) {
    colnames(begenmeme_tbl) <- c("etiket", "begenmeme_cnt")
  } else {
    begenmeme_tbl <- data.frame(etiket = character(0), begenmeme_cnt = integer(0))
  }

  genel <- merge(genel, begeni_tbl, by = "etiket", all.x = TRUE)
  genel <- merge(genel, begenmeme_tbl, by = "etiket", all.x = TRUE)
  genel$begeni_cnt[is.na(genel$begeni_cnt)] <- 0
  genel$begenmeme_cnt[is.na(genel$begenmeme_cnt)] <- 0

  genel[order(-genel$cnt), ]
}

admin_yanit_overview_ui <- function(data, ns) {
  toplam <- if (nrow(data$toplam) > 0) data$toplam$cnt[1] else 0

  begeni_cnt <- 0
  begenmeme_cnt <- 0

  if (nrow(data$begeni_orani) > 0) {
    begeni_cnt <- data$begeni_orani$begeni[1] %||% 0
    begenmeme_cnt <- data$begeni_orani$begenmeme[1] %||% 0
  }

  begeni_oran <- if (toplam > 0) {
    sprintf("%.1f%%", (begeni_cnt / toplam) * 100)
  } else {
    "N/A"
  }

  bugun_toplam <- if (nrow(data$bugun) > 0) data$bugun$toplam[1] %||% 0 else 0
  hafta_cnt <- if (nrow(data$bu_hafta) > 0) data$bu_hafta$cnt[1] else 0
  yorumlu_cnt <- if (nrow(data$yorumlu) > 0) data$yorumlu$cnt[1] else 0
  yorum_oran <- if (toplam > 0) sprintf("%.1f%%", (yorumlu_cnt / toplam) * 100) else "N/A"

  tagList(
    div(
      class = "metrics-grid",
      admin_create_metric_card(
        "Toplam Geri Bildirim",
        admin_format_number(toplam),
        "comments",
        "blue",
        tooltip = "Kullanıcıların yapay zekâ yanıtlarına verdikleri toplam geri bildirim sayısı."
      ),
      admin_create_metric_card(
        "Beğeni Oranı",
        begeni_oran,
        "thumbs-up",
        "green",
        tooltip = "Toplam geri bildirimlerin içinde beğeni oranı."
      ),
      admin_create_metric_card(
        "Beğeni",
        admin_format_number(begeni_cnt),
        "heart",
        "green",
        tooltip = "Toplam beğeni sayısı."
      ),
      admin_create_metric_card(
        "Beğenmeme",
        admin_format_number(begenmeme_cnt),
        "thumbs-down",
        "red",
        tooltip = "Toplam beğenmeme sayısı."
      ),
      admin_create_metric_card(
        "Bugün Gelen",
        admin_format_number(bugun_toplam),
        "calendar-day",
        "orange",
        tooltip = "Bugün alınan geri bildirim sayısı."
      ),
      admin_create_metric_card(
        "Yorum İçeren",
        yorum_oran,
        "comment",
        "purple",
        tooltip = "Metin yorumu içeren geri bildirim oranı."
      )
    ),
    fluidRow(
      column(
        width = 8,
        div(
          class = "analytics-card",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("chart-area"), " Günlük Geri Bildirim Eğilimi (30 Gün)"),
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

admin_yanit_model_ui <- function(ns) {
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
      class = "equal-height-row",
      column(
        width = 7,
        div(
          class = "analytics-card",
          style = "min-height: 460px;",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("chart-line"), " Haftalık Beğeni Oranı Eğilimi"),
            admin_create_info_button("Son 12 haftadaki beğeni oranı değişimi (beğeni / toplam × 100).")
          ),
          highcharter::highchartOutput(ns("ya_haftalik_oran_chart"), height = "380px")
        )
      ),
      column(
        width = 5,
        div(
          class = "analytics-card",
          style = "min-height: 460px;",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("table"), " Model Karşılaştırma Tablosu"),
            admin_create_info_button("Modellerin detaylı performans karşılaştırması: toplam yanıt, beğeni oranı ve ortalama yanıt süresi.")
          ),
          div(
            class = "table-container scrollable-table-equal",
            style = "max-height: 380px;",
            DT::DTOutput(ns("ya_model_tablo"))
          )
        )
      )
    )
  )
}

admin_yanit_etiket_ui <- function(ns) {
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

admin_yanit_zaman_ui <- function(ns) {
  tagList(
    fluidRow(
      column(
        width = 12,
        div(
          class = "analytics-card",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("th"), " Saat × Gün Isı Haritası"),
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
        div(
          class = "table-container scrollable-table-equal",
          DT::DTOutput(ns("ya_kullanici_tablo"))
        )
      )
    )
  )
}
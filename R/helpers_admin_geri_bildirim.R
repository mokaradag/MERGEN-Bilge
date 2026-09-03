# ==============================================================================
# Dosya Yolu: R/helpers_admin_geri_bildirim.R
# Açıklama: Yönetici geri bildirim analizi modülü için saf UI ve veri dönüştürme
#           yardımcıları. Yan etki, observer veya DB erişimi içermez.
# ==============================================================================

adminGeriBildirimUI <- function(id) {
  ns <- NS(id)

  admin_page_layout(
    ns = ns,
    page_title = "Geri Bildirim Analizi",
    page_icon = "comment-dots",
    tab_panels = list(
      tabPanel(
        title = tags$span(
          title = "Genel geri bildirim metrikleri ve özet göstergeler",
          tagList(icon("chart-line"), " Genel Bakış")
        ),
        value = "gb_overview"
      ),
      tabPanel(
        title = tags$span(
          title = "Memnuniyet puanı dağılımı ve trend analizi",
          tagList(icon("face-smile"), " Memnuniyet Analizi")
        ),
        value = "gb_memnuniyet"
      ),
      tabPanel(
        title = tags$span(
          title = "Net Promoter Score analizi ve segmentasyon",
          tagList(icon("gauge-high"), " NPS Analizi")
        ),
        value = "gb_nps"
      ),
      tabPanel(
        title = tags$span(
          title = "Etiket dağılımı ve kullanıcı yorumları detaylı analiz",
          tagList(icon("tags"), " Etiket & İçerik")
        ),
        value = "gb_icerik"
      )
    )
  )
}

admin_gb_count_tags <- function(ham) {
  if (is.null(ham) || !is.data.frame(ham) || nrow(ham) == 0) {
    return(data.frame(etiket = character(0), cnt = integer(0)))
  }

  if (!"Etiketler" %in% names(ham)) {
    return(data.frame(etiket = character(0), cnt = integer(0)))
  }

  tum_etiketler <- unlist(strsplit(as.character(ham$Etiketler), ","))
  tum_etiketler <- trimws(tum_etiketler)
  tum_etiketler <- tum_etiketler[nzchar(tum_etiketler)]

  if (length(tum_etiketler) == 0) {
    return(data.frame(etiket = character(0), cnt = integer(0)))
  }

  etiket_cevirisi <- c(
    "yeni_ozellik" = "Yeni Özellik",
    "tasarim"      = "Tasarım Önerisi",
    "sikayet"      = "Şikâyet",
    "performans"   = "Performans",
    "diger"        = "Diğer"
  )

  tablo <- as.data.frame(table(tum_etiketler), stringsAsFactors = FALSE)
  colnames(tablo) <- c("etiket", "cnt")

  tablo$etiket_tr <- ifelse(
    tablo$etiket %in% names(etiket_cevirisi),
    etiket_cevirisi[tablo$etiket],
    tablo$etiket
  )

  tablo[order(-tablo$cnt), , drop = FALSE]
}

admin_gb_tab_ui <- function(tab, ns, data_provider) {
  if (is.null(tab) || !nzchar(tab)) {
    tab <- "gb_overview"
  }

  switch(tab,
    "gb_overview"   = admin_gb_overview_ui(ns, data_provider()),
    "gb_memnuniyet" = admin_gb_memnuniyet_ui(ns),
    "gb_nps"        = admin_gb_nps_ui(ns, data_provider()),
    "gb_icerik"     = admin_gb_icerik_ui(ns),
    admin_gb_overview_ui(ns, data_provider())
  )
}

admin_gb_overview_ui <- function(ns, data) {
  toplam <- if (nrow(data$toplam) > 0) data$toplam$cnt[1] else 0
  ort_memn <- if (nrow(data$ort_memnuniyet) > 0 && !is.na(data$ort_memnuniyet$ort[1])) {
    sprintf("%.1f / 5", data$ort_memnuniyet$ort[1])
  } else {
    "N/A"
  }

  nps_skor <- "N/A"
  if (nrow(data$nps_dagilim) > 0 &&
      !is.na(data$nps_dagilim$toplam[1]) &&
      data$nps_dagilim$toplam[1] > 0) {
    t <- data$nps_dagilim
    nps_val <- ((t$promoter[1] - t$detractor[1]) / t$toplam[1]) * 100
    nps_skor <- sprintf("%+.0f", nps_val)
  }

  iletisim_oran <- "N/A"
  if (nrow(data$iletisim_izni) > 0 && data$iletisim_izni$toplam[1] > 0) {
    iletisim_oran <- sprintf(
      "%.0f%%",
      (data$iletisim_izni$izinli[1] / data$iletisim_izni$toplam[1]) * 100
    )
  }

  bugun_cnt <- if (nrow(data$bugun) > 0) data$bugun$cnt[1] else 0
  hafta_cnt <- if (nrow(data$bu_hafta) > 0) data$bu_hafta$cnt[1] else 0

  tagList(
    div(
      class = "metrics-grid",
      admin_create_metric_card(
        "Toplam Geri Bildirim",
        admin_format_number(toplam),
        "comment-dots",
        "blue",
        tooltip = "Kullanıcılardan gelen toplam geri bildirim sayısı."
      ),
      admin_create_metric_card(
        "Ortalama Memnuniyet",
        ort_memn,
        "face-smile",
        "green",
        tooltip = "Tüm geri bildirimlerin ortalama memnuniyet puanı (1-5)."
      ),
      admin_create_metric_card(
        "NPS Skoru",
        nps_skor,
        "gauge-high",
        "purple",
        tooltip = "Net Promoter Score (-100 ile +100 arası). 9-10: Promoter, 7-8: Pasif, 0-6: Detractor."
      ),
      admin_create_metric_card(
        "İletişim İzni",
        iletisim_oran,
        "envelope",
        "cyan",
        tooltip = "Geri bildirimle birlikte iletişim izni veren kullanıcıların oranı."
      ),
      admin_create_metric_card(
        "Bugün Gelen",
        admin_format_number(bugun_cnt),
        "calendar-day",
        "orange",
        tooltip = "Bugün alınan geri bildirim sayısı."
      ),
      admin_create_metric_card(
        "Bu Hafta",
        admin_format_number(hafta_cnt),
        "calendar-week",
        "yellow",
        tooltip = "Son 7 günde alınan geri bildirim sayısı."
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
            admin_create_info_button("Son 30 gündeki günlük geri bildirim sayısı ve ortalama memnuniyet eğilimi.")
          ),
          highcharter::highchartOutput(ns("gb_gunluk_trend_chart"), height = "320px")
        )
      ),
      column(
        width = 4,
        div(
          class = "analytics-card",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("face-smile"), " Memnuniyet Dağılımı"),
            admin_create_info_button("1-5 arası memnuniyet puanlarının genel dağılımı.")
          ),
          highcharter::highchartOutput(ns("gb_memnuniyet_polar_chart"), height = "320px")
        )
      )
    )
  )
}

admin_gb_memnuniyet_ui <- function(ns) {
  tagList(
    fluidRow(
      column(
        width = 6,
        div(
          class = "analytics-card",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("chart-column"), " Memnuniyet Puanı Dağılımı"),
            admin_create_info_button("Her memnuniyet puanı (1-5) için geri bildirim sayısı.")
          ),
          highcharter::highchartOutput(ns("gb_memnuniyet_column_chart"), height = "350px")
        )
      ),
      column(
        width = 6,
        div(
          class = "analytics-card",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("chart-line"), " Haftalık Memnuniyet Trendi"),
            admin_create_info_button("Son 12 haftadaki ortalama memnuniyet puanı değişimi.")
          ),
          highcharter::highchartOutput(ns("gb_memnuniyet_trend_chart"), height = "350px")
        )
      )
    ),
    fluidRow(
      column(
        width = 6,
        div(
          class = "analytics-card",
          style = "min-height: 460px;",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("arrow-right-arrow-left"), " Memnuniyet – NPS Korelasyonu"),
            admin_create_info_button("Memnuniyet puanına göre ortalama NPS puanı. Kabarcık büyüklüğü yanıt sayısını temsil eder.")
          ),
          highcharter::highchartOutput(ns("gb_korelasyon_chart"), height = "350px")
        )
      ),
      column(
        width = 6,
        div(
          class = "analytics-card",
          style = "min-height: 460px;",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("users"), " Kullanıcı Bazlı Memnuniyet"),
            admin_create_info_button("Her kullanıcının ortalama memnuniyet puanı ve bildirim sayısı.")
          ),
          div(
            class = "table-container scrollable-table-equal",
            DT::DTOutput(ns("gb_kullanici_tablo"))
          )
        )
      )
    )
  )
}

admin_gb_nps_ui <- function(ns, data) {
  nps_val <- NA
  promoter_pct <- passive_pct <- detractor_pct <- 0

  if (nrow(data$nps_dagilim) > 0 &&
      !is.na(data$nps_dagilim$toplam[1]) &&
      data$nps_dagilim$toplam[1] > 0) {
    t <- data$nps_dagilim
    promoter_pct  <- round((t$promoter[1] / t$toplam[1]) * 100, 1)
    passive_pct   <- round((t$passive[1] / t$toplam[1]) * 100, 1)
    detractor_pct <- round((t$detractor[1] / t$toplam[1]) * 100, 1)
    nps_val <- promoter_pct - detractor_pct
  }

  tagList(
    div(
      class = "metrics-grid-3",
      admin_create_metric_card(
        "Destekçiler (9-10)",
        sprintf("%.1f%%", promoter_pct),
        "face-grin-stars",
        "green",
        tooltip = "NPS 9 veya 10 puan verenlerin oranı. Markayı aktif olarak tavsiye ederler."
      ),
      admin_create_metric_card(
        "Pasifler (7-8)",
        sprintf("%.1f%%", passive_pct),
        "face-meh",
        "yellow",
        tooltip = "NPS 7 veya 8 puan verenler. Memnun ama coşkusuz kullanıcılar."
      ),
      admin_create_metric_card(
        "Eleştirmenler (0-6)",
        sprintf("%.1f%%", detractor_pct),
        "face-frown",
        "red",
        tooltip = "NPS 0-6 arası puan verenler. Memnuniyetsiz ve potansiyel olumsuz yayılım kaynağı."
      )
    ),
    fluidRow(
      column(
        width = 5,
        div(
          class = "analytics-card",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("gauge-high"), " NPS Skoru Göstergesi"),
            admin_create_info_button("Net Promoter Score: Destekçi (%) - Eleştirmen (%). -100 ile +100 arası.")
          ),
          highcharter::highchartOutput(ns("gb_nps_gauge_chart"), height = "350px")
        )
      ),
      column(
        width = 7,
        div(
          class = "analytics-card",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("chart-bar"), " NPS Puan Dağılımı (0-10)"),
            admin_create_info_button("Her NPS puanı (0-10) için verilen yanıt sayısı. Renkler: Yeşil=Destekçi, Sarı=Pasif, Kırmızı=Eleştirmen.")
          ),
          highcharter::highchartOutput(ns("gb_nps_dagilim_chart"), height = "350px")
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
            h4(class = "card-title", icon("chart-area"), " Haftalık NPS Trendi"),
            admin_create_info_button("Son 12 haftadaki NPS segmentlerinin değişimi (yığılmış alan grafik).")
          ),
          highcharter::highchartOutput(ns("gb_nps_trend_chart"), height = "350px")
        )
      ),
      column(
        width = 5,
        div(
          class = "analytics-card",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("chart-pie"), " NPS Segment Dağılımı"),
            admin_create_info_button("Destekçi, Pasif ve Eleştirmen gruplarının oransal dağılımı.")
          ),
          highcharter::highchartOutput(ns("gb_nps_pie_chart"), height = "350px")
        )
      )
    )
  )
}

admin_gb_icerik_ui <- function(ns) {
  tagList(
    fluidRow(
      column(
        width = 5,
        div(
          class = "analytics-card",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("sitemap"), " Etiket Dağılımı (Ağaç Haritası)"),
            admin_create_info_button("Kullanıcıların seçtiği etiketlerin görsel oransal dağılımı.")
          ),
          highcharter::highchartOutput(ns("gb_etiket_treemap_chart"), height = "400px")
        )
      ),
      column(
        width = 7,
        div(
          class = "analytics-card",
          div(
            class = "card-title-row",
            h4(class = "card-title", icon("chart-bar"), " Etiket Sıklığı"),
            admin_create_info_button("Her etiketin kaç kez seçildiğini gösteren çubuk grafik.")
          ),
          highcharter::highchartOutput(ns("gb_etiket_bar_chart"), height = "400px")
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
            h4(class = "card-title", icon("table"), " Tüm Geri Bildirimler (Detaylı)"),
            admin_create_info_button("Kullanıcılardan gelen tüm geri bildirimlerin detaylı listesi. Arama ve sıralama yapılabilir.")
          ),
          div(class = "table-container", DT::DTOutput(ns("gb_detay_tablo")))
        )
      )
    )
  )
}
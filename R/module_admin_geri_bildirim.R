# Dosya Yolu: R/module_admin_geri_bildirim.R
# Açıklama: Yönetici paneli - Geri Bildirim Analizi modülü.
#            MB_Destek_Geri_Bildirim tablosundaki kullanıcı geri bildirimlerini
#            çok boyutlu olarak analiz eder. Memnuniyet, NPS, etiket ve içerik
#            analizleri için gelişmiş grafikler ve tablolar sunar.

# ==============================================================================
# UI FONKSİYONU
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

# ==============================================================================
# SERVER FONKSİYONU
# ==============================================================================

adminGeriBildirimServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Yenileme altyapısı (paylaşılan yardımcı)
    refresh <- admin_refresh_setup(input, session)

    # ============================================================
    # VERİ ÇEKİMİ
    # ============================================================
    gb_data <- reactive({
      refresh$trigger()

      list(
        # Tüm geri bildirimler (DC01_userr ile e-posta adresi de çekilir)
        tumu = admin_safe_query("
          SELECT
            gb.GeriBildirimID, gb.UserID, u.KaynakAdi AS KullaniciAdi,
            gb.Memnuniyet, gb.NPS_Puan, gb.Etiketler,
            gb.EnCokSevilen, gb.Gelistirme, gb.IletisimIzni,
            gb.OlusturmaTarihi,
            dc.EmailAddress
          FROM MB_Destek_Geri_Bildirim gb
          LEFT JOIN MB_Users u ON gb.UserID = u.UserID
          LEFT JOIN DC01_userr dc ON u.KullaniciAdi = dc.Name
          ORDER BY gb.OlusturmaTarihi DESC
        "),

        # Toplam kayıt sayısı
        toplam = admin_safe_query("
          SELECT COUNT(*) as cnt FROM MB_Destek_Geri_Bildirim
        "),

        # Ortalama memnuniyet
        ort_memnuniyet = admin_safe_query("
          SELECT AVG(CAST(Memnuniyet AS FLOAT)) as ort
          FROM MB_Destek_Geri_Bildirim
        "),

        # Memnuniyet dağılımı (1-5)
        memnuniyet_dagilim = admin_safe_query("
          SELECT Memnuniyet, COUNT(*) as cnt
          FROM MB_Destek_Geri_Bildirim
          GROUP BY Memnuniyet
          ORDER BY Memnuniyet
        "),

        # NPS dağılımı (Promoter/Passive/Detractor)
        nps_dagilim = admin_safe_query("
          SELECT
            SUM(CASE WHEN NPS_Puan >= 9 THEN 1 ELSE 0 END) as promoter,
            SUM(CASE WHEN NPS_Puan >= 7 AND NPS_Puan <= 8 THEN 1 ELSE 0 END) as passive,
            SUM(CASE WHEN NPS_Puan <= 6 THEN 1 ELSE 0 END) as detractor,
            COUNT(NPS_Puan) as toplam
          FROM MB_Destek_Geri_Bildirim
          WHERE NPS_Puan IS NOT NULL
        "),

        # İletişim izni oranı
        iletisim_izni = admin_safe_query("
          SELECT
            SUM(CASE WHEN IletisimIzni = 1 THEN 1 ELSE 0 END) as izinli,
            COUNT(*) as toplam
          FROM MB_Destek_Geri_Bildirim
        "),

        # Günlük trend (son 30 gün)
        gunluk_trend = admin_safe_query("
          SELECT
            CAST(OlusturmaTarihi AS DATE) as tarih,
            COUNT(*) as cnt,
            AVG(CAST(Memnuniyet AS FLOAT)) as ort_memnuniyet
          FROM MB_Destek_Geri_Bildirim
          WHERE OlusturmaTarihi >= DATEADD(day, -30, GETDATE())
          GROUP BY CAST(OlusturmaTarihi AS DATE)
          ORDER BY tarih
        "),

        # Memnuniyet trendi (haftalık)
        memnuniyet_trend = admin_safe_query("
          SELECT
            DATEPART(ISO_WEEK, OlusturmaTarihi) as hafta,
            DATEPART(YEAR, OlusturmaTarihi) as yil,
            MIN(CAST(OlusturmaTarihi AS DATE)) as hafta_basi,
            AVG(CAST(Memnuniyet AS FLOAT)) as ort_memnuniyet,
            COUNT(*) as cnt
          FROM MB_Destek_Geri_Bildirim
          WHERE OlusturmaTarihi >= DATEADD(week, -12, GETDATE())
          GROUP BY DATEPART(ISO_WEEK, OlusturmaTarihi), DATEPART(YEAR, OlusturmaTarihi)
          ORDER BY yil, hafta
        "),

        # NPS trendi (haftalık)
        nps_trend = admin_safe_query("
          SELECT
            DATEPART(ISO_WEEK, OlusturmaTarihi) as hafta,
            DATEPART(YEAR, OlusturmaTarihi) as yil,
            MIN(CAST(OlusturmaTarihi AS DATE)) as hafta_basi,
            SUM(CASE WHEN NPS_Puan >= 9 THEN 1 ELSE 0 END) as promoter,
            SUM(CASE WHEN NPS_Puan >= 7 AND NPS_Puan <= 8 THEN 1 ELSE 0 END) as passive,
            SUM(CASE WHEN NPS_Puan <= 6 THEN 1 ELSE 0 END) as detractor,
            COUNT(NPS_Puan) as toplam
          FROM MB_Destek_Geri_Bildirim
          WHERE NPS_Puan IS NOT NULL AND OlusturmaTarihi >= DATEADD(week, -12, GETDATE())
          GROUP BY DATEPART(ISO_WEEK, OlusturmaTarihi), DATEPART(YEAR, OlusturmaTarihi)
          ORDER BY yil, hafta
        "),

        # Etiket bazlı dağılım (virgülle ayrılmış etiketler tek tek sayılır)
        etiketler_ham = admin_safe_query("
          SELECT Etiketler FROM MB_Destek_Geri_Bildirim
          WHERE Etiketler IS NOT NULL AND Etiketler <> ''
        "),

        # Bugün gelen
        bugun = admin_safe_query("
          SELECT COUNT(*) as cnt FROM MB_Destek_Geri_Bildirim
          WHERE CAST(OlusturmaTarihi AS DATE) = CAST(GETDATE() AS DATE)
        "),

        # Bu hafta gelen
        bu_hafta = admin_safe_query("
          SELECT COUNT(*) as cnt FROM MB_Destek_Geri_Bildirim
          WHERE OlusturmaTarihi >= DATEADD(day, -7, GETDATE())
        "),

        # Kullanıcı bazlı memnuniyet
        kullanici_memnuniyet = admin_safe_query("
          SELECT
            u.KaynakAdi AS KullaniciAdi,
            COUNT(*) as bildirim_sayisi,
            AVG(CAST(gb.Memnuniyet AS FLOAT)) as ort_memnuniyet,
            AVG(CAST(gb.NPS_Puan AS FLOAT)) as ort_nps,
            MAX(gb.OlusturmaTarihi) as son_bildirim
          FROM MB_Destek_Geri_Bildirim gb
          LEFT JOIN MB_Users u ON gb.UserID = u.UserID
          GROUP BY gb.UserID, u.KaynakAdi
          ORDER BY bildirim_sayisi DESC
        "),

        # NPS puan dağılımı (0-10 her puan için)
        nps_puan_dagilim = admin_safe_query("
          SELECT NPS_Puan, COUNT(*) as cnt
          FROM MB_Destek_Geri_Bildirim
          WHERE NPS_Puan IS NOT NULL
          GROUP BY NPS_Puan
          ORDER BY NPS_Puan
        "),

        # Memnuniyet - NPS korelasyonu
        memnuniyet_nps_korelasyon = admin_safe_query("
          SELECT Memnuniyet,
            AVG(CAST(NPS_Puan AS FLOAT)) as ort_nps,
            COUNT(*) as cnt
          FROM MB_Destek_Geri_Bildirim
          WHERE NPS_Puan IS NOT NULL
          GROUP BY Memnuniyet
          ORDER BY Memnuniyet
        ")
      )
    })

    # ============================================================
    # ETİKET ÇÖZÜMLEME (virgülle ayrılmış etiketleri sayma)
    # ============================================================
    etiket_sayilari <- reactive({
      ham <- gb_data()$etiketler_ham
      if (nrow(ham) == 0) return(data.frame(etiket = character(0), cnt = integer(0)))

      tum_etiketler <- unlist(strsplit(ham$Etiketler, ","))
      tum_etiketler <- trimws(tum_etiketler)
      tum_etiketler <- tum_etiketler[nzchar(tum_etiketler)]

      if (length(tum_etiketler) == 0) return(data.frame(etiket = character(0), cnt = integer(0)))

      # Etiket isimlerini Türkçe karşılıkları ile eşle
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
      tablo[order(-tablo$cnt), ]
    })

    # ============================================================
    # SEKME İÇERİĞİ YÖNLENDİRİCİ
    # ============================================================
    output$tab_content_area <- renderUI({
      tab <- input$admin_tabs
      if (is.null(tab)) tab <- "gb_overview"

      admin_init_tooltips(session)

      switch(tab,
        "gb_overview"   = gb_overview_ui(),
        "gb_memnuniyet" = gb_memnuniyet_ui(),
        "gb_nps"        = gb_nps_ui(),
        "gb_icerik"     = gb_icerik_ui(),
        gb_overview_ui()
      )
    })

    # ============================================================
    # SEKME 1: GENEL BAKIŞ
    # ============================================================
    gb_overview_ui <- function() {
      data <- gb_data()

      toplam <- if (nrow(data$toplam) > 0) data$toplam$cnt[1] else 0
      ort_memn <- if (nrow(data$ort_memnuniyet) > 0 && !is.na(data$ort_memnuniyet$ort[1]))
        sprintf("%.1f / 5", data$ort_memnuniyet$ort[1]) else "N/A"

      # NPS skoru hesapla
      nps_skor <- "N/A"
      if (nrow(data$nps_dagilim) > 0 && !is.na(data$nps_dagilim$toplam[1]) && data$nps_dagilim$toplam[1] > 0) {
        t <- data$nps_dagilim
        nps_val <- ((t$promoter[1] - t$detractor[1]) / t$toplam[1]) * 100
        nps_skor <- sprintf("%+.0f", nps_val)
      }

      # İletişim izni oranı
      iletisim_oran <- "N/A"
      if (nrow(data$iletisim_izni) > 0 && data$iletisim_izni$toplam[1] > 0) {
        iletisim_oran <- sprintf("%.0f%%", (data$iletisim_izni$izinli[1] / data$iletisim_izni$toplam[1]) * 100)
      }

      bugun_cnt <- if (nrow(data$bugun) > 0) data$bugun$cnt[1] else 0
      hafta_cnt <- if (nrow(data$bu_hafta) > 0) data$bu_hafta$cnt[1] else 0

      tagList(
        div(
          class = "metrics-grid",
          admin_create_metric_card("Toplam Geri Bildirim", admin_format_number(toplam), "comment-dots", "blue",
            tooltip = "Kullanıcılardan gelen toplam geri bildirim sayısı."),
          admin_create_metric_card("Ortalama Memnuniyet", ort_memn, "face-smile", "green",
            tooltip = "Tüm geri bildirimlerin ortalama memnuniyet puanı (1-5)."),
          admin_create_metric_card("NPS Skoru", nps_skor, "gauge-high", "purple",
            tooltip = "Net Promoter Score (-100 ile +100 arası). 9-10: Promoter, 7-8: Pasif, 0-6: Detractor."),
          admin_create_metric_card("İletişim İzni", iletisim_oran, "envelope", "cyan",
            tooltip = "Geri bildirimle birlikte iletişim izni veren kullanıcıların oranı."),
          admin_create_metric_card("Bugün Gelen", admin_format_number(bugun_cnt), "calendar-day", "orange",
            tooltip = "Bugün alınan geri bildirim sayısı."),
          admin_create_metric_card("Bu Hafta", admin_format_number(hafta_cnt), "calendar-week", "yellow",
            tooltip = "Son 7 günde alınan geri bildirim sayısı.")
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

    # ============================================================
    # SEKME 2: MEMNUNİYET ANALİZİ
    # ============================================================
    gb_memnuniyet_ui <- function() {
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
                h4(class = "card-title", icon("arrow-right-arrow-left"), " Memnuniyet \U2013 NPS Korelasyonu"),
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
              div(class = "table-container scrollable-table-equal",
                DT::DTOutput(ns("gb_kullanici_tablo")))
            )
          )
        )
      )
    }

    # ============================================================
    # SEKME 3: NPS ANALİZİ
    # ============================================================
    gb_nps_ui <- function() {
      data <- gb_data()

      # NPS hesaplama
      nps_val <- NA
      promoter_pct <- passive_pct <- detractor_pct <- 0
      if (nrow(data$nps_dagilim) > 0 && !is.na(data$nps_dagilim$toplam[1]) && data$nps_dagilim$toplam[1] > 0) {
        t <- data$nps_dagilim
        promoter_pct  <- round((t$promoter[1] / t$toplam[1]) * 100, 1)
        passive_pct   <- round((t$passive[1] / t$toplam[1]) * 100, 1)
        detractor_pct <- round((t$detractor[1] / t$toplam[1]) * 100, 1)
        nps_val <- promoter_pct - detractor_pct
      }

      nps_display <- if (!is.na(nps_val)) sprintf("%+.0f", nps_val) else "N/A"
      nps_color <- if (!is.na(nps_val)) {
        if (nps_val >= 50) "green" else if (nps_val >= 0) "yellow" else "red"
      } else "blue"

      tagList(
        div(
          class = "metrics-grid-3",
          admin_create_metric_card("Destekçiler (9-10)", sprintf("%.1f%%", promoter_pct), "face-grin-stars", "green",
            tooltip = "NPS 9 veya 10 puan verenlerin oranı. Markayı aktif olarak tavsiye ederler."),
          admin_create_metric_card("Pasifler (7-8)", sprintf("%.1f%%", passive_pct), "face-meh", "yellow",
            tooltip = "NPS 7 veya 8 puan verenler. Memnun ama coşkusuz kullanıcılar."),
          admin_create_metric_card("Eleştirmenler (0-6)", sprintf("%.1f%%", detractor_pct), "face-frown", "red",
            tooltip = "NPS 0-6 arası puan verenler. Memnuniyetsiz ve potansiyel olumsuz yayılım kaynağı.")
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

    # ============================================================
    # SEKME 4: ETİKET & İÇERİK ANALİZİ
    # ============================================================
    gb_icerik_ui <- function() {
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

    # ============================================================
    # GRAFİKLER: GENEL BAKIŞ
    # ============================================================

    # Günlük trend (çift eksenli: sayı + ortalama memnuniyet)
	output$gb_gunluk_trend_chart <- highcharter::renderHighchart({
	  data <- gb_data()$gunluk_trend
	  if (nrow(data) == 0) return(highcharter::highchart())

	  data$tarih <- as.Date(data$tarih)
	  data <- data[order(data$tarih), , drop = FALSE]
	  data$tarih_label <- unname(vapply(data$tarih, admin_format_turkish_date, character(1)))
	  data$cnt <- suppressWarnings(as.numeric(data$cnt))
	  data$ort_memnuniyet <- suppressWarnings(round(as.numeric(data$ort_memnuniyet), 2))

	  if (all(is.na(data$cnt)) && all(is.na(data$ort_memnuniyet))) {
		return(highcharter::highchart())
	  }

	  highcharter::highchart() %>%
		highcharter::hc_chart(backgroundColor = "transparent") %>%
		highcharter::hc_title(text = NULL) %>%
		highcharter::hc_xAxis(
		  type = "category",
		  categories = as.list(data$tarih_label),
		  labels = list(style = list(color = "#999"))
		) %>%
		highcharter::hc_yAxis_multiples(
		  list(
			title = list(text = "Bildirim Sayısı", style = list(color = "#06b6d4")),
			labels = list(style = list(color = "#999")),
			gridLineColor = "#444",
			min = 0
		  ),
		  list(
			title = list(text = "Ort. Memnuniyet", style = list(color = "#f59e0b")),
			labels = list(style = list(color = "#999")),
			opposite = TRUE,
			gridLineWidth = 0,
			min = 1,
			max = 5
		  )
		) %>%
		highcharter::hc_add_series(
		  name = "Bildirim Sayısı",
		  data = unname(data$cnt),
		  type = "column",
		  color = "#06b6d4",
		  yAxis = 0,
		  borderWidth = 0
		) %>%
		highcharter::hc_add_series(
		  name = "Ort. Memnuniyet",
		  data = unname(data$ort_memnuniyet),
		  type = "spline",
		  color = "#f59e0b",
		  yAxis = 1,
		  marker = list(enabled = TRUE, radius = 4),
		  lineWidth = 3
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

    # Memnuniyet polar/radar grafik
    output$gb_memnuniyet_polar_chart <- highcharter::renderHighchart({
      data <- gb_data()$memnuniyet_dagilim
      if (nrow(data) == 0) return(highcharter::highchart())

      etiketler <- c("Çok Kötü", "Kötü", "Orta", "İyi", "Çok İyi")
      renkler <- c("#ef4444", "#f97316", "#f59e0b", "#22c55e", "#10b981")

      # Tüm puanlar için değer oluştur (1-5)
      tam_data <- data.frame(Memnuniyet = 1:5, cnt = 0)
      for (i in 1:nrow(data)) {
        idx <- data$Memnuniyet[i]
        if (idx >= 1 && idx <= 5) tam_data$cnt[idx] <- data$cnt[i]
      }

      chart_data <- lapply(1:5, function(i) {
        list(name = etiketler[i], y = tam_data$cnt[i], color = renkler[i])
      })

      highcharter::highchart() %>%
        highcharter::hc_chart(type = "pie", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_plotOptions(
          pie = list(
            innerSize = "55%",
            borderWidth = 0,
            dataLabels = list(
              enabled = TRUE,
              format = "<b>{point.name}</b>: {point.y}",
              style = list(color = "#fff", textOutline = "none", fontSize = "11px")
            )
          )
        ) %>%
        highcharter::hc_add_series(name = "Memnuniyet", data = chart_data) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a", borderColor = "#333",
          style = list(color = "#fff"),
          pointFormat = "<b>{point.y}</b> bildirim ({point.percentage:.1f}%)"
        ) %>%
        highcharter::hc_credits(enabled = FALSE)
    })

    # ============================================================
    # GRAFİKLER: MEMNUNİYET ANALİZİ
    # ============================================================

    # Memnuniyet puanı dağılımı (gradyan sütun grafik)
    output$gb_memnuniyet_column_chart <- highcharter::renderHighchart({
      data <- gb_data()$memnuniyet_dagilim
      if (nrow(data) == 0) return(highcharter::highchart())

      etiketler <- c("1 - Çok Kötü", "2 - Kötü", "3 - Orta", "4 - İyi", "5 - Çok İyi")
      renkler <- c("#ef4444", "#f97316", "#f59e0b", "#22c55e", "#10b981")

      tam_data <- data.frame(Memnuniyet = 1:5, cnt = 0)
      for (i in 1:nrow(data)) {
        idx <- data$Memnuniyet[i]
        if (idx >= 1 && idx <= 5) tam_data$cnt[idx] <- data$cnt[i]
      }

      chart_data <- lapply(1:5, function(i) {
        list(y = tam_data$cnt[i], color = renkler[i])
      })

      highcharter::highchart() %>%
        highcharter::hc_chart(type = "column", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = etiketler,
          labels = list(style = list(color = "#999"))
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Bildirim Sayısı", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#444", min = 0
        ) %>%
        highcharter::hc_plotOptions(
          column = list(
            borderWidth = 0,
            borderRadius = 6,
            dataLabels = list(enabled = TRUE, color = "#fff",
              style = list(textOutline = "none", fontWeight = "bold"))
          )
        ) %>%
        highcharter::hc_add_series(name = "Bildirim", data = chart_data) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a", borderColor = "#333",
          style = list(color = "#fff")
        ) %>%
        highcharter::hc_legend(enabled = FALSE) %>%
        highcharter::hc_credits(enabled = FALSE)
    })

    # Haftalık memnuniyet trendi (areaspline)
    output$gb_memnuniyet_trend_chart <- highcharter::renderHighchart({
      data <- gb_data()$memnuniyet_trend
      if (nrow(data) == 0) return(highcharter::highchart())

      data <- data[order(data$yil, data$hafta), ]
      data$ort_memnuniyet <- round(data$ort_memnuniyet, 2)

      # Tek değer olduğunda "H10" gibi kısa etiketler yerine tarih aralığı göster
      data$label <- vapply(seq_len(nrow(data)), function(i) {
        if (nrow(data) <= 3) {
          tryCatch(format(as.Date(data$hafta_basi[i]), "%d.%m.%Y"), error = function(e) paste0("H", data$hafta[i]))
        } else {
          paste0("H", data$hafta[i])
        }
      }, character(1))

      chart_data <- lapply(seq_len(nrow(data)), function(i) {
        list(
          y = data$ort_memnuniyet[i],
          cnt = data$cnt[i],
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
          title = list(text = "Ortalama Memnuniyet", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#444", min = 1, max = 5
        ) %>%
        highcharter::hc_plotOptions(
          areaspline = list(
            marker = list(enabled = TRUE, radius = 4),
            lineWidth = 3
          )
        ) %>%
        highcharter::hc_add_series(
          name = "Memnuniyet", data = chart_data,
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
          backgroundColor = "#1a1a1a", borderColor = "#333",
          style = list(color = "#fff"),
          formatter = JS("function() { return '<b>Hafta başlangıcı:</b> ' + this.point.hafta_basi + '<br/><b>Ort. Memnuniyet:</b> ' + this.y + '<br/><b>Bildirim:</b> ' + this.point.cnt; }")
        ) %>%
        highcharter::hc_legend(enabled = FALSE) %>%
        highcharter::hc_credits(enabled = FALSE)
    })

    # Memnuniyet \U2014 NPS korelasyonu (bubble grafik)
	output$gb_korelasyon_chart <- highcharter::renderHighchart({
	  data <- gb_data()$memnuniyet_nps_korelasyon
	  if (nrow(data) == 0) return(highcharter::highchart())

	  data$Memnuniyet <- suppressWarnings(as.numeric(data$Memnuniyet))
	  data$ort_nps <- suppressWarnings(round(as.numeric(data$ort_nps), 1))
	  data$cnt <- suppressWarnings(as.numeric(data$cnt))
	  data <- data[!is.na(data$Memnuniyet) & !is.na(data$ort_nps), , drop = FALSE]
	  if (nrow(data) == 0) return(highcharter::highchart())

	  y_ust_limit <- max(10.8, max(data$ort_nps, na.rm = TRUE) + 0.8)

	  chart_data <- lapply(seq_len(nrow(data)), function(i) {
		list(
		  x = data$Memnuniyet[i],
		  y = data$ort_nps[i],
		  z = data$cnt[i],
		  name = paste0("Memnuniyet: ", data$Memnuniyet[i])
		)
	  })

	  highcharter::highchart() %>%
		highcharter::hc_chart(type = "bubble", backgroundColor = "transparent") %>%
		highcharter::hc_title(text = NULL) %>%
		highcharter::hc_xAxis(
		  title = list(text = "Memnuniyet Puanı (1-5)", style = list(color = "#999")),
		  labels = list(style = list(color = "#999")),
		  min = 0.5,
		  max = 5.5,
		  gridLineColor = "#444"
		) %>%
		highcharter::hc_yAxis(
		  title = list(text = "Ortalama NPS Puanı (0-10)", style = list(color = "#999")),
		  labels = list(style = list(color = "#999")),
		  gridLineColor = "#444",
		  min = 0,
		  max = y_ust_limit,
		  maxPadding = 0.18,
		  endOnTick = FALSE
		) %>%
		highcharter::hc_plotOptions(
		  bubble = list(
			minSize = 12,
			maxSize = 48
		  )
		) %>%
		highcharter::hc_add_series(
		  name = "Korelasyon",
		  data = chart_data,
		  color = "#8b5cf6",
		  marker = list(fillOpacity = 0.7)
		) %>%
		highcharter::hc_tooltip(
		  backgroundColor = "#1a1a1a",
		  borderColor = "#333",
		  style = list(color = "#fff"),
		  formatter = JS("function() { return '<b>' + this.point.name + '</b><br/>Ort. NPS: ' + this.y + '<br/>Yanıt Sayısı: ' + this.point.z; }")
		) %>%
		highcharter::hc_legend(enabled = FALSE) %>%
		highcharter::hc_credits(enabled = FALSE)
	})

    # Kullanıcı bazlı memnuniyet tablosu
    output$gb_kullanici_tablo <- DT::renderDT({
      data <- gb_data()$kullanici_memnuniyet
      if (nrow(data) == 0) return(DT::datatable(data.frame()))

      data$row_num <- 1:nrow(data)
      data$ort_memnuniyet <- round(data$ort_memnuniyet, 1)
      data$ort_nps <- round(data$ort_nps, 1)
      data$son_bildirim <- format(as.POSIXct(data$son_bildirim), "%d.%m.%Y %H:%M")

      display_data <- data[, c("row_num", "KullaniciAdi", "bildirim_sayisi", "ort_memnuniyet", "ort_nps", "son_bildirim")]
      colnames(display_data) <- c("#", "Kullanıcı", "Bildirim", "Ort. Memnuniyet", "Ort. NPS", "Son Bildirim")

      DT::datatable(
        display_data,
        options = list(
          dom = 't', pageLength = 20, scrollY = FALSE,
          ordering = TRUE, order = list(list(2, 'desc')),
          language = admin_turkish_dt_language,
          columnDefs = list(
            list(className = 'dt-center', targets = c(0, 2, 3, 4, 5)),
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
    # GRAFİKLER: NPS ANALİZİ
    # ============================================================

    # NPS Solid Gauge (gösterge)
    output$gb_nps_gauge_chart <- highcharter::renderHighchart({
      data <- gb_data()$nps_dagilim
      if (nrow(data) == 0 || is.na(data$toplam[1]) || data$toplam[1] == 0)
        return(highcharter::highchart())

      t <- data
      nps_val <- round(((t$promoter[1] - t$detractor[1]) / t$toplam[1]) * 100)

      # Renk belirleme
      gauge_color <- if (nps_val >= 50) "#10b981" else if (nps_val >= 0) "#f59e0b" else "#ef4444"

      highcharter::highchart() %>%
        highcharter::hc_chart(type = "solidgauge", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_pane(
          center = list("50%", "60%"),
          size = "100%",
          startAngle = -120,
          endAngle = 120,
          background = list(
            backgroundColor = "#333",
            innerRadius = "60%",
            outerRadius = "100%",
            shape = "arc",
            borderWidth = 0
          )
        ) %>%
        highcharter::hc_yAxis(
          min = -100, max = 100,
          lineWidth = 0,
          tickWidth = 0,
          minorTickInterval = NULL,
          labels = list(enabled = FALSE),
          stops = list(
            list(0, "#ef4444"),
            list(0.5, "#f59e0b"),
            list(0.75, "#22c55e"),
            list(1, "#10b981")
          )
        ) %>%
        highcharter::hc_plotOptions(
          solidgauge = list(
            dataLabels = list(
              enabled = TRUE,
              borderWidth = 0,
              y = -30,
              style = list(fontSize = "32px", color = gauge_color, textOutline = "none"),
              format = paste0('<span style="font-size:36px;color:', gauge_color, '">{y}</span>')
            ),
            rounded = TRUE
          )
        ) %>%
        highcharter::hc_add_series(
          name = "NPS",
          data = list(list(y = nps_val, color = gauge_color)),
          innerRadius = "60%"
        ) %>%
        highcharter::hc_tooltip(enabled = FALSE) %>%
        highcharter::hc_credits(enabled = FALSE)
    })

    # NPS puan dağılımı (0-10, renkli sütun)
    output$gb_nps_dagilim_chart <- highcharter::renderHighchart({
      data <- gb_data()$nps_puan_dagilim
      if (nrow(data) == 0) return(highcharter::highchart())

      # 0-10 arası tüm puanları doldur
      tam <- data.frame(NPS_Puan = 0:10, cnt = 0)
      for (i in 1:nrow(data)) {
        idx <- data$NPS_Puan[i] + 1
        if (idx >= 1 && idx <= 11) tam$cnt[idx] <- data$cnt[i]
      }

      # Renk: 0-6 kırmızı, 7-8 sarı, 9-10 yeşil
      renkler <- c(rep("#ef4444", 7), rep("#f59e0b", 2), rep("#10b981", 2))

      chart_data <- lapply(1:11, function(i) {
        list(y = tam$cnt[i], color = renkler[i])
      })

      highcharter::highchart() %>%
        highcharter::hc_chart(type = "column", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = as.character(0:10),
          labels = list(style = list(color = "#999")),
          title = list(text = "NPS Puanı", style = list(color = "#999"))
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Yanıt Sayısı", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#444", min = 0
        ) %>%
        highcharter::hc_plotOptions(
          column = list(
            borderWidth = 0, borderRadius = 4,
            dataLabels = list(enabled = TRUE, color = "#fff",
              style = list(textOutline = "none"))
          )
        ) %>%
        highcharter::hc_add_series(name = "Yanıt", data = chart_data) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a", borderColor = "#333",
          style = list(color = "#fff")
        ) %>%
        highcharter::hc_legend(enabled = FALSE) %>%
        highcharter::hc_credits(enabled = FALSE)
    })

    # NPS trend (yığılmış alan - haftalık)
    output$gb_nps_trend_chart <- highcharter::renderHighchart({
      data <- gb_data()$nps_trend
      if (nrow(data) == 0) return(highcharter::highchart())

      data <- data[order(data$yil, data$hafta), ]

      # Tek değer olduğunda "H10" gibi kısa etiketler yerine tarih aralığı göster
      data$label <- vapply(seq_len(nrow(data)), function(i) {
        if (nrow(data) <= 3) {
          tryCatch(format(as.Date(data$hafta_basi[i]), "%d.%m.%Y"), error = function(e) paste0("H", data$hafta[i]))
        } else {
          paste0("H", data$hafta[i])
        }
      }, character(1))

      highcharter::highchart() %>%
        highcharter::hc_chart(type = "areaspline", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = as.list(data$label),
          labels = list(style = list(color = "#999"))
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Yanıt Sayısı", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#444"
        ) %>%
        highcharter::hc_plotOptions(
          areaspline = list(
            stacking = "normal",
            marker = list(enabled = TRUE, radius = 3),
            lineWidth = 2
          )
        ) %>%
        highcharter::hc_add_series(
          name = "Destekçi (9-10)", data = data$promoter, color = "#10b981",
          fillColor = list(
            linearGradient = list(x1 = 0, y1 = 0, x2 = 0, y2 = 1),
            stops = list(list(0, "rgba(16, 185, 129, 0.4)"), list(1, "rgba(16, 185, 129, 0.05)"))
          )
        ) %>%
        highcharter::hc_add_series(
          name = "Pasif (7-8)", data = data$passive, color = "#f59e0b",
          fillColor = list(
            linearGradient = list(x1 = 0, y1 = 0, x2 = 0, y2 = 1),
            stops = list(list(0, "rgba(245, 158, 11, 0.4)"), list(1, "rgba(245, 158, 11, 0.05)"))
          )
        ) %>%
        highcharter::hc_add_series(
          name = "Eleştirmen (0-6)", data = data$detractor, color = "#ef4444",
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

    # NPS segment dağılımı (halka grafik)
    output$gb_nps_pie_chart <- highcharter::renderHighchart({
      data <- gb_data()$nps_dagilim
      if (nrow(data) == 0 || is.na(data$toplam[1]) || data$toplam[1] == 0)
        return(highcharter::highchart())

      t <- data
      chart_data <- list(
        list(name = "Destekçi (9-10)", y = t$promoter[1], color = "#10b981"),
        list(name = "Pasif (7-8)",     y = t$passive[1],  color = "#f59e0b"),
        list(name = "Eleştirmen (0-6)", y = t$detractor[1], color = "#ef4444")
      )

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
        highcharter::hc_add_series(name = "NPS Segment", data = chart_data) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a", borderColor = "#333",
          style = list(color = "#fff"),
          pointFormat = "<b>{point.y}</b> yanıt ({point.percentage:.1f}%)"
        ) %>%
        highcharter::hc_credits(enabled = FALSE)
    })

    # ============================================================
    # GRAFİKLER: ETİKET & İÇERİK
    # ============================================================

    # Etiket treemap
    output$gb_etiket_treemap_chart <- highcharter::renderHighchart({
      data <- etiket_sayilari()
      if (nrow(data) == 0) return(highcharter::highchart())

      treemap_renkler <- c("#6366f1", "#8b5cf6", "#06b6d4", "#f59e0b", "#ef4444", "#22c55e", "#ec4899")

      chart_data <- lapply(1:nrow(data), function(i) {
        list(
          name = data$etiket_tr[i],
          value = data$cnt[i],
          colorValue = i,
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

    # Etiket sıklığı (yatay çubuk)
    output$gb_etiket_bar_chart <- highcharter::renderHighchart({
      data <- etiket_sayilari()
      if (nrow(data) == 0) return(highcharter::highchart())

      data <- data[order(-data$cnt), ]
      renk_paleti <- c("#6366f1", "#8b5cf6", "#06b6d4", "#f59e0b", "#ef4444", "#22c55e", "#ec4899")

      chart_data <- lapply(1:nrow(data), function(i) {
        list(y = data$cnt[i], color = renk_paleti[((i - 1) %% length(renk_paleti)) + 1])
      })

      highcharter::highchart() %>%
        highcharter::hc_chart(type = "bar", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = data$etiket_tr,
          labels = list(style = list(color = "#ccc", fontSize = "13px"))
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Seçilme Sayısı", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#444", min = 0
        ) %>%
        highcharter::hc_plotOptions(
          bar = list(
            borderWidth = 0, borderRadius = 4,
            dataLabels = list(enabled = TRUE, color = "#fff",
              style = list(textOutline = "none", fontWeight = "bold"))
          )
        ) %>%
        highcharter::hc_add_series(name = "Seçilme", data = chart_data) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a", borderColor = "#333",
          style = list(color = "#fff")
        ) %>%
        highcharter::hc_legend(enabled = FALSE) %>%
        highcharter::hc_credits(enabled = FALSE)
    })

    # Detaylı geri bildirim tablosu
    output$gb_detay_tablo <- DT::renderDT({
      data <- gb_data()$tumu
      if (nrow(data) == 0) return(DT::datatable(data.frame()))

      data$row_num <- 1:nrow(data)

      # Memnuniyet emojisi (sıralama için gizli değer eklenir)
      memn_emoji <- c("\U0001F621", "\U0001F61E", "\U0001F610", "\U0001F60A", "\U0001F929")
      data$memn_display <- ifelse(
        !is.na(data$Memnuniyet) & data$Memnuniyet >= 1 & data$Memnuniyet <= 5,
        paste0(memn_emoji[data$Memnuniyet], " ", data$Memnuniyet, "/5"),
        "-"
      )
      # Sıralama için sayısal değer (gizli sütun)
      data$memn_sort <- ifelse(!is.na(data$Memnuniyet), data$Memnuniyet, 0)

      # NPS puanı renkli gösterim
      nps_renk <- function(puan) {
        if (is.na(puan)) return("-")
        renk <- if (puan >= 9) "#10b981" else if (puan >= 7) "#f59e0b" else "#ef4444"
        sprintf('<span style="color:%s; font-weight:bold;">%d</span>', renk, puan)
      }
      data$nps_display <- sapply(data$NPS_Puan, nps_renk)
      data$nps_sort <- ifelse(!is.na(data$NPS_Puan), data$NPS_Puan, -1)

      data$tarih <- format(as.POSIXct(data$OlusturmaTarihi), "%d.%m.%Y %H:%M")
      data$etiketler_display <- ifelse(!is.na(data$Etiketler) & nzchar(data$Etiketler), data$Etiketler, "-")
      data$sevilen_display <- ifelse(!is.na(data$EnCokSevilen) & nzchar(data$EnCokSevilen), data$EnCokSevilen, "-")
      data$gelistirme_display <- ifelse(!is.na(data$Gelistirme) & nzchar(data$Gelistirme), data$Gelistirme, "-")

      # İletişim izni ikonu ve renkli gösterim
      data$iletisim_display <- ifelse(
        data$IletisimIzni == 1,
        '<span style="color:#10b981;"><i class="fas fa-check-circle"></i> Evet</span>',
        '<span style="color:#ef4444;"><i class="fas fa-times-circle"></i> Hayır</span>'
      )

      # E-posta sütunu: İletişim izni varsa mailto ikonu göster
      data$eposta_display <- sapply(seq_len(nrow(data)), function(i) {
        if (isTRUE(data$IletisimIzni[i] == 1) && !is.na(data$EmailAddress[i]) && nzchar(data$EmailAddress[i])) {
          kullanici_adi <- ifelse(!is.na(data$KullaniciAdi[i]) && nzchar(data$KullaniciAdi[i]), data$KullaniciAdi[i], "Kullanıcı")
          konu <- utils::URLencode(paste0("MERGEN Bilge - Geri Bildirim #", data$GeriBildirimID[i]))
          govde <- utils::URLencode(paste0(
            "Sayın ", kullanici_adi, ",\n\n",
            "MERGEN Bilge uygulamasına bıraktığınız geri bildirim (", format(as.POSIXct(data$OlusturmaTarihi[i]), "%d.%m.%Y"), ") hakkında sizinle iletişime geçmek istiyoruz.\n\n",
            "Saygılarımızla,\nMERGEN Bilge Yönetim Ekibi"
          ))
          sprintf(
            '<a href="mailto:%s?subject=%s&body=%s" title="%s adresine e-posta gönder" class="admin-mail-icon"><i class="fas fa-envelope"></i></a>',
            htmltools::htmlEscape(data$EmailAddress[i]), konu, govde,
            htmltools::htmlEscape(data$EmailAddress[i])
          )
        } else {
          ""
        }
      })

      data$kullanici <- ifelse(!is.na(data$KullaniciAdi) & nzchar(data$KullaniciAdi), data$KullaniciAdi, "-")

      display_data <- data[, c("row_num", "kullanici", "memn_display", "memn_sort",
                                "nps_display", "nps_sort",
                                "etiketler_display", "sevilen_display", "gelistirme_display",
                                "iletisim_display", "eposta_display", "tarih")]
      colnames(display_data) <- c("#", "Kullanıcı", "Memnuniyet", "memn_sort",
                                   "NPS", "nps_sort",
                                   "Etiketler", "En Çok Sevilen", "Geliştirilecek",
                                   "İletişim İzni", "\U0001F4E7", "Tarih")

      DT::datatable(
        display_data,
        escape = FALSE,
        options = list(
          dom = 'frtip', pageLength = 15,
          ordering = TRUE, order = list(list(11, 'desc')),
          language = admin_turkish_dt_language,
          columnDefs = list(
            list(className = 'dt-center', targets = c(0, 2, 4, 9, 10, 11)),
            list(className = 'row-number-col', targets = 0),
            list(width = '40px', targets = c(0, 10)),
            list(width = '180px', targets = c(7, 8)),
            list(orderable = FALSE, targets = c(0, 10)),
            # Gizli sıralama sütunları
            list(visible = FALSE, targets = c(3, 5)),
            # Memnuniyet sütunu memn_sort'a göre sıralansın
            list(orderData = 3, targets = 2),
            # NPS sütunu nps_sort'a göre sıralansın
            list(orderData = 5, targets = 4)
          ),
          headerCallback = admin_dt_header_callback
        ),
        class = "admin-datatable", rownames = FALSE
      )
    })

  })
}
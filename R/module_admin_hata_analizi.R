# Dosya Yolu: R/module_admin_hata_analizi.R
# Açıklama: Yönetici paneli - Hata Bildirim Analizi modülü.
#            MB_Destek_Hata_Bildir tablosundaki hata bildirimlerini çok boyutlu
#            olarak analiz eder. Öncelik, kategori, durum takibi ve ek dosya
#            inceleme gibi gelişmiş özellikler sunar.

# ==============================================================================
# UI FONKSİYONU
# ==============================================================================

adminHataAnaliziUI <- function(id) {
  ns <- NS(id)

  admin_page_layout(
    ns = ns,
    page_title = "Hata Analizi",
    page_icon = "bug",
    tab_panels = list(
      tabPanel(
        title = tags$span(
          title = "Genel hata bildirim metrikleri ve özet göstergeler",
          tagList(icon("chart-line"), " Genel Bakış")
        ),
        value = "ha_overview"
      ),
      tabPanel(
        title = tags$span(
          title = "Öncelik seviyesi ve kategori bazlı detaylı analiz",
          tagList(icon("layer-group"), " Öncelik & Kategori")
        ),
        value = "ha_oncelik"
      ),
      tabPanel(
        title = tags$span(
          title = "Tüm hata bildirimleri, ek dosyalar ve durum yönetimi",
          tagList(icon("list-check"), " Detaylı Bildirimler")
        ),
        value = "ha_detay"
      ),
      tabPanel(
        title = tags$span(
          title = "Zamana göre hata bildirimi trend analizi",
          tagList(icon("clock"), " Zaman Analizi")
        ),
        value = "ha_zaman"
      )
    )
  )
}

# ==============================================================================
# SERVER FONKSİYONU
# ==============================================================================

adminHataAnaliziServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Yenileme altyapısı
    refresh <- admin_refresh_setup(input, session)

    # Kategori ve öncelik Türkçe karşılıkları
    kategori_cevirisi <- c(
      "arayuz"         = "Arayüz / Tasarım",
      "fonksiyonellik" = "İşlevsellik",
      "performans"     = "Performans",
      "cokme"          = "Çökme / Hata",
      "diger"          = "Diğer"
    )

    oncelik_cevirisi <- c(
      "dusuk"        = "Düşük",
      "orta"         = "Orta",
      "yuksek"       = "Yüksek",
      "kritik"       = "Kritik",
      "belirtilmedi" = "Belirtilmedi"
    )

    durum_cevirisi <- c(
      "acik"      = "Açık",
      "inceleme"  = "İncelemede",
      "cozuldu"   = "Çözüldü",
      "kapandi"   = "Kapandı",
      "reddedildi" = "Reddedildi"
    )

    # ============================================================
    # VERİ ÇEKİMİ
    # ============================================================
    ha_data <- reactive({
      refresh$trigger()

      list(
        # Tüm hata bildirimleri
        tumu = admin_safe_query("
          SELECT
            hb.HataBildirimID, hb.UserID, u.KaynakAdi AS KullaniciAdi,
            hb.Konular, hb.Kategoriler, hb.Oncelik, hb.Aciklama,
            hb.EkDosyaYollari, hb.Durum, hb.OlusturmaTarihi
          FROM MB_Destek_Hata_Bildir hb
          LEFT JOIN MB_Users u ON hb.UserID = u.UserID
          ORDER BY hb.OlusturmaTarihi DESC
        "),

        # Toplam
        toplam = admin_safe_query("SELECT COUNT(*) as cnt FROM MB_Destek_Hata_Bildir"),

        # Durum dağılımı
        durum_dagilim = admin_safe_query("
          SELECT Durum, COUNT(*) as cnt
          FROM MB_Destek_Hata_Bildir
          GROUP BY Durum
          ORDER BY cnt DESC
        "),

        # Öncelik dağılımı
        oncelik_dagilim = admin_safe_query("
          SELECT Oncelik, COUNT(*) as cnt
          FROM MB_Destek_Hata_Bildir
          GROUP BY Oncelik
          ORDER BY cnt DESC
        "),

        # Bugün gelen
        bugun = admin_safe_query("
          SELECT COUNT(*) as cnt FROM MB_Destek_Hata_Bildir
          WHERE CAST(OlusturmaTarihi AS DATE) = CAST(GETDATE() AS DATE)
        "),

        # Bu hafta gelen
        bu_hafta = admin_safe_query("
          SELECT COUNT(*) as cnt FROM MB_Destek_Hata_Bildir
          WHERE OlusturmaTarihi >= DATEADD(day, -7, GETDATE())
        "),

        # Günlük trend (son 30 gün)
        gunluk_trend = admin_safe_query("
          SELECT
            CAST(OlusturmaTarihi AS DATE) as tarih,
            COUNT(*) as cnt
          FROM MB_Destek_Hata_Bildir
          WHERE OlusturmaTarihi >= DATEADD(day, -30, GETDATE())
          GROUP BY CAST(OlusturmaTarihi AS DATE)
          ORDER BY tarih
        "),

        # Öncelik bazlı trend (son 30 gün)
        oncelik_trend = admin_safe_query("
          SELECT
            CAST(OlusturmaTarihi AS DATE) as tarih,
            Oncelik,
            COUNT(*) as cnt
          FROM MB_Destek_Hata_Bildir
          WHERE OlusturmaTarihi >= DATEADD(day, -30, GETDATE())
          GROUP BY CAST(OlusturmaTarihi AS DATE), Oncelik
          ORDER BY tarih
        "),

        # Kategoriler ham (virgülle ayrılmış)
        kategoriler_ham = admin_safe_query("
          SELECT Kategoriler FROM MB_Destek_Hata_Bildir
          WHERE Kategoriler IS NOT NULL AND Kategoriler <> ''
        "),

        # Ek dosya olan bildirim sayısı
        ekli_bildirim = admin_safe_query("
          SELECT COUNT(*) as cnt FROM MB_Destek_Hata_Bildir
          WHERE EkDosyaYollari IS NOT NULL AND EkDosyaYollari <> ''
        "),

        # Kullanıcı bazlı bildirim sayısı
        kullanici_bildirim = admin_safe_query("
          SELECT
            u.KaynakAdi AS KullaniciAdi,
            COUNT(*) as bildirim_sayisi,
            SUM(CASE WHEN hb.Oncelik = 'kritik' THEN 1 ELSE 0 END) as kritik_sayisi,
            MAX(hb.OlusturmaTarihi) as son_bildirim
          FROM MB_Destek_Hata_Bildir hb
          LEFT JOIN MB_Users u ON hb.UserID = u.UserID
          GROUP BY hb.UserID, u.KaynakAdi
          ORDER BY bildirim_sayisi DESC
        "),

        # Saatlik dağılım
        saatlik_dagilim = admin_safe_query("
          SELECT
            DATEPART(HOUR, OlusturmaTarihi) as saat,
            COUNT(*) as cnt
          FROM MB_Destek_Hata_Bildir
          GROUP BY DATEPART(HOUR, OlusturmaTarihi)
          ORDER BY saat
        "),

        # Haftalık trend
        haftalik_trend = admin_safe_query("
          SELECT
            DATEPART(ISO_WEEK, OlusturmaTarihi) as hafta,
            DATEPART(YEAR, OlusturmaTarihi) as yil,
            MIN(CAST(OlusturmaTarihi AS DATE)) as hafta_basi,
            COUNT(*) as cnt
          FROM MB_Destek_Hata_Bildir
          WHERE OlusturmaTarihi >= DATEADD(week, -12, GETDATE())
          GROUP BY DATEPART(ISO_WEEK, OlusturmaTarihi), DATEPART(YEAR, OlusturmaTarihi)
          ORDER BY yil, hafta
        "),

        # Öncelik × Kategori çapraz tablosu (ısı haritası için)
        oncelik_kategori = admin_safe_query("
          SELECT Oncelik, Kategoriler, COUNT(*) as cnt
          FROM MB_Destek_Hata_Bildir
          WHERE Kategoriler IS NOT NULL AND Kategoriler <> ''
          GROUP BY Oncelik, Kategoriler
        ")
      )
    })

    # ============================================================
    # KATEGORİ ÇÖZÜMLEME
    # ============================================================
    kategori_sayilari <- reactive({
      ham <- ha_data()$kategoriler_ham
      if (nrow(ham) == 0) return(data.frame(kategori = character(0), cnt = integer(0)))

      tum_kategoriler <- unlist(strsplit(ham$Kategoriler, ","))
      tum_kategoriler <- trimws(tum_kategoriler)
      tum_kategoriler <- tum_kategoriler[nzchar(tum_kategoriler)]

      if (length(tum_kategoriler) == 0) return(data.frame(kategori = character(0), cnt = integer(0)))

      tablo <- as.data.frame(table(tum_kategoriler), stringsAsFactors = FALSE)
      colnames(tablo) <- c("kategori", "cnt")
      tablo$kategori_tr <- ifelse(
        tablo$kategori %in% names(kategori_cevirisi),
        kategori_cevirisi[tablo$kategori],
        tablo$kategori
      )
      tablo[order(-tablo$cnt), ]
    })

    # ============================================================
    # SEKME İÇERİĞİ YÖNLENDİRİCİ
    # ============================================================
    output$tab_content_area <- renderUI({
      tab <- input$admin_tabs
      if (is.null(tab)) tab <- "ha_overview"

      admin_init_tooltips(session)

      switch(tab,
        "ha_overview" = ha_overview_ui(),
        "ha_oncelik"  = ha_oncelik_ui(),
        "ha_detay"    = ha_detay_ui(),
        "ha_zaman"    = ha_zaman_ui(),
        ha_overview_ui()
      )
    })

    # ============================================================
    # SEKME 1: GENEL BAKIŞ
    # ============================================================
    ha_overview_ui <- function() {
      data <- ha_data()

      toplam <- if (nrow(data$toplam) > 0) data$toplam$cnt[1] else 0
      bugun_cnt <- if (nrow(data$bugun) > 0) data$bugun$cnt[1] else 0
      hafta_cnt <- if (nrow(data$bu_hafta) > 0) data$bu_hafta$cnt[1] else 0
      ekli_cnt <- if (nrow(data$ekli_bildirim) > 0) data$ekli_bildirim$cnt[1] else 0

      # Durum sayıları
      acik_cnt <- 0
      cozuldu_cnt <- 0
      kritik_cnt <- 0
      if (nrow(data$durum_dagilim) > 0) {
        acik_cnt <- sum(data$durum_dagilim$cnt[data$durum_dagilim$Durum == "acik"])
      }
      if (nrow(data$durum_dagilim) > 0) {
        cozuldu_cnt <- sum(data$durum_dagilim$cnt[data$durum_dagilim$Durum %in% c("cozuldu", "kapandi")])
      }
      if (nrow(data$oncelik_dagilim) > 0) {
        kritik_cnt <- sum(data$oncelik_dagilim$cnt[data$oncelik_dagilim$Oncelik == "kritik"])
      }

      # Çözüm oranı
      cozum_oran <- if (toplam > 0) sprintf("%.0f%%", (cozuldu_cnt / toplam) * 100) else "N/A"

      tagList(
        div(
          class = "metrics-grid",
          admin_create_metric_card("Toplam Bildirim", admin_format_number(toplam), "bug", "blue",
            tooltip = "Kullanıcılardan gelen toplam hata bildirimi sayısı."),
          admin_create_metric_card("Açık Bildirimler", admin_format_number(acik_cnt), "exclamation-circle", "orange",
            tooltip = "Henüz çözülmemiş ve açık durumda olan hata bildirimleri."),
          admin_create_metric_card("Çözülmüş", admin_format_number(cozuldu_cnt), "check-circle", "green",
            tooltip = "Çözüldü veya kapandı olarak işaretlenmiş bildirimler."),
          admin_create_metric_card("Kritik Hatalar", admin_format_number(kritik_cnt), "fire", "red",
            tooltip = "Kritik öncelik seviyesindeki hata bildirimleri."),
          admin_create_metric_card("Çözüm Oranı", cozum_oran, "chart-pie", "purple",
            tooltip = "Çözülen ve kapanan bildirimlerin toplam bildirimlere oranı."),
          admin_create_metric_card("Ek Dosyalı", admin_format_number(ekli_cnt), "paperclip", "cyan",
            tooltip = "Ekran görüntüsü veya video eklenmiş bildirim sayısı."),
          admin_create_metric_card("Bugün Gelen", admin_format_number(bugun_cnt), "calendar-day", "yellow",
            tooltip = "Bugün alınan hata bildirimi sayısı."),
          admin_create_metric_card("Bu Hafta", admin_format_number(hafta_cnt), "calendar-week", "teal",
            tooltip = "Son 7 günde alınan hata bildirimi sayısı.")
        ),
        fluidRow(
          column(
            width = 8,
            div(
              class = "analytics-card",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("chart-area"), " Günlük Hata Bildirim Trendi (30 Gün)"),
                admin_create_info_button("Son 30 gündeki günlük hata bildirim sayısı eğilimi.")
              ),
              highcharter::highchartOutput(ns("ha_gunluk_trend_chart"), height = "320px")
            )
          ),
          column(
            width = 4,
            div(
              class = "analytics-card",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("chart-pie"), " Durum Dağılımı"),
                admin_create_info_button("Hata bildirimlerinin mevcut durum bazında dağılımı.")
              ),
              highcharter::highchartOutput(ns("ha_durum_pie_chart"), height = "320px")
            )
          )
        )
      )
    }

    # ============================================================
    # SEKME 2: ÖNCELİK & KATEGORİ
    # ============================================================
    ha_oncelik_ui <- function() {
      tagList(
        fluidRow(
          column(
            width = 5,
            div(
              class = "analytics-card",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("signal"), " Öncelik Dağılımı"),
                admin_create_info_button("Hata bildirimlerinin öncelik seviyesine göre dağılımı.")
              ),
              highcharter::highchartOutput(ns("ha_oncelik_chart"), height = "380px")
            )
          ),
          column(
            width = 7,
            div(
              class = "analytics-card",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("sitemap"), " Kategori Dağılımı (Ağaç Haritası)"),
                admin_create_info_button("Hata bildirimlerinin kategori bazında görsel oransal dağılımı.")
              ),
              highcharter::highchartOutput(ns("ha_kategori_treemap_chart"), height = "380px")
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
                h4(class = "card-title", icon("th"), " Öncelik × Kategori Isı Haritası"),
                admin_create_info_button("Her öncelik-kategori kombinasyonu için hata bildirim yoğunluğu. Koyu renkler daha fazla bildirimi temsil eder.")
              ),
              highcharter::highchartOutput(ns("ha_heatmap_chart"), height = "350px")
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
                h4(class = "card-title", icon("chart-area"), " Öncelik Bazlı Trend (30 Gün)"),
                admin_create_info_button("Son 30 günde her öncelik seviyesindeki hata bildirim trendi.")
              ),
              highcharter::highchartOutput(ns("ha_oncelik_trend_chart"), height = "350px")
            )
          )
        )
      )
    }

    # ============================================================
    # SEKME 3: DETAYLI BİLDİRİMLER
    # ============================================================
    ha_detay_ui <- function() {
      tagList(
        fluidRow(
          column(
            width = 12,
            div(
              class = "analytics-card",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("table"), " Tüm Hata Bildirimleri"),
                admin_create_info_button("Tüm hata bildirimlerinin detaylı listesi. Ek dosyaları görüntülemek için 'Dosyalar' sütunundaki bağlantılara tıklayın.")
              ),
              div(class = "table-container", DT::dataTableOutput(ns("ha_detay_tablo")))
            )
          )
        ),
        # Ek dosya önizleme modal'ı (genişletilmiş, yakınlaştırma ve indirme destekli)
        tags$div(
          id = ns("ek_dosya_modal"),
          class = "modal fade admin-attachment-modal",
          `data-backdrop` = "static", `data-keyboard` = "true",
          tabindex = "-1", role = "dialog",
          tags$div(
            class = "modal-dialog", role = "document",
            style = "max-width: 90vw; width: 1100px; margin: 30px auto;",
            tags$div(
              class = "modal-content",
              style = "background: #1a1a1a; border: 1px solid #333; border-radius: 12px;",
              tags$div(
                class = "modal-header",
                style = "border-bottom: 1px solid #333; padding: 15px 24px;",
                h4(class = "modal-title", style = "color: #fff;", icon("paperclip"), " Ek Dosyalar"),
                tags$button(type = "button", class = "close", `data-dismiss` = "modal",
                  style = "color: #999; opacity: 0.8;", tags$span(HTML("&times;")))
              ),
              tags$div(
                class = "modal-body",
                style = "padding: 24px; max-height: 85vh; overflow-y: auto;",
                uiOutput(ns("ek_dosya_content"))
              )
            )
          )
        ),
        # Durum güncelleme modal'ı
        # NOT: data-backdrop="static" ile modal'ın etkileşim sorununu önle
        tags$div(
          id = ns("durum_modal"),
          class = "modal fade",
          `data-backdrop` = "static", `data-keyboard` = "true",
          tabindex = "-1", role = "dialog",
          tags$div(
            class = "modal-dialog", role = "document",
            style = "max-width: 420px;",
            tags$div(
              class = "modal-content",
              style = "background: #1a1a1a; border: 1px solid #333; border-radius: 12px;",
              tags$div(
                class = "modal-header",
                style = "border-bottom: 1px solid #333; padding: 15px 20px;",
                h4(class = "modal-title", style = "color: #fff;", icon("edit"), " Durum Güncelle"),
                tags$button(type = "button", class = "close", `data-dismiss` = "modal",
                  style = "color: #999;", tags$span(HTML("&times;")))
              ),
              tags$div(
                class = "modal-body",
                style = "padding: 24px; min-height: 320px;",
                tags$input(type = "hidden", id = ns("durum_bildirim_id")),
                selectInput(ns("yeni_durum"), "Yeni Durum:",
                  choices = c(
                    "Açık" = "acik",
                    "İncelemede" = "inceleme",
                    "Çözüldü" = "cozuldu",
                    "Kapandı" = "kapandi",
                    "Reddedildi" = "reddedildi"
                  ),
                  selected = "acik"
                ),
                actionButton(ns("durum_kaydet"), "Kaydet",
                  class = "btn-modern btn-primary", style = "margin-top: 14px;")
              )
            )
          )
        )
      )
    }

    # ============================================================
    # SEKME 4: ZAMAN ANALİZİ
    # ============================================================
    ha_zaman_ui <- function() {
      tagList(
        fluidRow(
          column(
            width = 12,
            div(
              class = "analytics-card",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("chart-line"), " Haftalık Hata Bildirim Trendi (12 Hafta)"),
                admin_create_info_button("Son 12 haftadaki hata bildirim sayıları trendi.")
              ),
              highcharter::highchartOutput(ns("ha_haftalik_trend_chart"), height = "320px")
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
                h4(class = "card-title", icon("clock"), " Saatlere Göre Bildirim Dağılımı"),
                admin_create_info_button("Günün hangi saatlerinde daha fazla hata bildirimi yapıldığı.")
              ),
              highcharter::highchartOutput(ns("ha_saatlik_chart"), height = "320px")
            )
          ),
          column(
            width = 6,
            div(
              class = "analytics-card",
              style = "min-height: 400px;",
              div(
                class = "card-title-row",
                h4(class = "card-title", icon("users"), " Kullanıcı Bazlı Bildirimler"),
                admin_create_info_button("En çok hata bildirimi yapan kullanıcılar.")
              ),
              div(class = "table-container scrollable-table-equal",
                DT::dataTableOutput(ns("ha_kullanici_tablo")))
            )
          )
        )
      )
    }

    # ============================================================
    # GRAFİKLER: GENEL BAKIŞ
    # ============================================================

    # Günlük trend
    output$ha_gunluk_trend_chart <- highcharter::renderHighchart({
      data <- ha_data()$gunluk_trend
      if (nrow(data) == 0) return(highcharter::highchart())

      data$tarih_label <- vapply(data$tarih, admin_format_turkish_date, character(1))

      highcharter::highchart() %>%
        highcharter::hc_chart(type = "areaspline", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = as.list(data$tarih_label),
          labels = list(style = list(color = "#999"))
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Bildirim Sayısı", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#444", min = 0
        ) %>%
        highcharter::hc_plotOptions(
          areaspline = list(marker = list(enabled = TRUE, radius = 3), lineWidth = 2.5)
        ) %>%
        highcharter::hc_add_series(
          name = "Hata Bildirimi", data = data$cnt,
          color = "#ef4444",
          fillColor = list(
            linearGradient = list(x1 = 0, y1 = 0, x2 = 0, y2 = 1),
            stops = list(list(0, "rgba(239, 68, 68, 0.3)"), list(1, "rgba(239, 68, 68, 0)"))
          )
        ) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a", borderColor = "#333",
          style = list(color = "#fff")
        ) %>%
        highcharter::hc_legend(enabled = FALSE) %>%
        highcharter::hc_credits(enabled = FALSE)
    })

    # Durum pasta grafik
    output$ha_durum_pie_chart <- highcharter::renderHighchart({
      data <- ha_data()$durum_dagilim
      if (nrow(data) == 0) return(highcharter::highchart())

      durum_renkler <- c(
        "acik" = "#f59e0b", "inceleme" = "#3b82f6",
        "cozuldu" = "#10b981", "kapandi" = "#64748b",
        "reddedildi" = "#ef4444"
      )

      chart_data <- lapply(1:nrow(data), function(i) {
        d <- data$Durum[i]
        list(
          name = ifelse(d %in% names(durum_cevirisi), durum_cevirisi[d], d),
          y = data$cnt[i],
          color = ifelse(d %in% names(durum_renkler), durum_renkler[d], "#94a3b8")
        )
      })

      highcharter::highchart() %>%
        highcharter::hc_chart(type = "pie", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_plotOptions(
          pie = list(
            innerSize = "60%", borderWidth = 0,
            dataLabels = list(
              enabled = TRUE,
              format = "<b>{point.name}</b>: {point.y}",
              style = list(color = "#fff", textOutline = "none")
            )
          )
        ) %>%
        highcharter::hc_add_series(name = "Durum", data = chart_data) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a", borderColor = "#333",
          style = list(color = "#fff"),
          pointFormat = "<b>{point.y}</b> bildirim ({point.percentage:.1f}%)"
        ) %>%
        highcharter::hc_credits(enabled = FALSE)
    })

    # ============================================================
    # GRAFİKLER: ÖNCELİK & KATEGORİ
    # ============================================================

    # Öncelik dağılımı (polar alan grafik)
    output$ha_oncelik_chart <- highcharter::renderHighchart({
      data <- ha_data()$oncelik_dagilim
      if (nrow(data) == 0) return(highcharter::highchart())

      oncelik_renkler <- c(
        "dusuk" = "#3b82f6", "orta" = "#f59e0b",
        "yuksek" = "#f97316", "kritik" = "#ef4444",
        "belirtilmedi" = "#94a3b8"
      )

      chart_data <- lapply(1:nrow(data), function(i) {
        o <- data$Oncelik[i]
        list(
          name = ifelse(o %in% names(oncelik_cevirisi), oncelik_cevirisi[o], o),
          y = data$cnt[i],
          color = ifelse(o %in% names(oncelik_renkler), oncelik_renkler[o], "#94a3b8")
        )
      })

      highcharter::highchart() %>%
        highcharter::hc_chart(type = "pie", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_plotOptions(
          pie = list(
            innerSize = "70%", borderWidth = 0,
            dataLabels = list(
              enabled = TRUE,
              format = "<b>{point.name}</b>: {point.percentage:.1f}%",
              style = list(color = "#fff", textOutline = "none")
            )
          )
        ) %>%
        highcharter::hc_add_series(name = "Öncelik", data = chart_data) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a", borderColor = "#333",
          style = list(color = "#fff"),
          pointFormat = "<b>{point.y}</b> bildirim ({point.percentage:.1f}%)"
        ) %>%
        highcharter::hc_credits(enabled = FALSE)
    })

    # Kategori treemap
    output$ha_kategori_treemap_chart <- highcharter::renderHighchart({
      data <- kategori_sayilari()
      if (nrow(data) == 0) return(highcharter::highchart())

      treemap_renkler <- c("#6366f1", "#06b6d4", "#f59e0b", "#ef4444", "#22c55e", "#ec4899")

      chart_data <- lapply(1:nrow(data), function(i) {
        list(
          name = data$kategori_tr[i],
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
          pointFormat = "<b>{point.name}</b>: {point.value} bildirim"
        ) %>%
        highcharter::hc_credits(enabled = FALSE)
    })

    # Isı haritası (Öncelik × Kategori)
    output$ha_heatmap_chart <- highcharter::renderHighchart({
      data <- ha_data()$oncelik_kategori
      if (nrow(data) == 0) return(highcharter::highchart())

      # Kategorileri çözümle (ilk kategoriyi al, virgülle ayrılmışsa)
      data$ilk_kategori <- sapply(strsplit(data$Kategoriler, ","), function(x) trimws(x[1]))
      data$kategori_tr <- ifelse(
        data$ilk_kategori %in% names(kategori_cevirisi),
        kategori_cevirisi[data$ilk_kategori],
        data$ilk_kategori
      )
      data$oncelik_tr <- ifelse(
        data$Oncelik %in% names(oncelik_cevirisi),
        oncelik_cevirisi[data$Oncelik],
        data$Oncelik
      )

      # Benzersiz kategoriler ve öncelikler
      kategoriler <- unique(data$kategori_tr)
      oncelikler <- c("Düşük", "Orta", "Yüksek", "Kritik", "Belirtilmedi")
      oncelikler <- oncelikler[oncelikler %in% unique(data$oncelik_tr)]

      # Heatmap verisini oluştur
      heatmap_data <- list()
      for (i in seq_along(kategoriler)) {
        for (j in seq_along(oncelikler)) {
          val <- sum(data$cnt[data$kategori_tr == kategoriler[i] & data$oncelik_tr == oncelikler[j]])
          heatmap_data <- c(heatmap_data, list(list(i - 1, j - 1, val)))
        }
      }

      highcharter::highchart() %>%
        highcharter::hc_chart(type = "heatmap", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = kategoriler,
          labels = list(style = list(color = "#ccc")),
          title = list(text = NULL)
        ) %>%
        highcharter::hc_yAxis(
          categories = oncelikler,
          labels = list(style = list(color = "#ccc")),
          title = list(text = "Öncelik", style = list(color = "#999")),
          reversed = TRUE
        ) %>%
        highcharter::hc_colorAxis(
          min = 0,
          minColor = "#1a1a3a",
          maxColor = "#ef4444",
          stops = list(
            list(0, "#1a1a3a"),
            list(0.3, "#3b1a5a"),
            list(0.6, "#8b2252"),
            list(1, "#ef4444")
          )
        ) %>%
        highcharter::hc_add_series(
          name = "Bildirim", data = heatmap_data,
          borderWidth = 2, borderColor = "#1a1a1a",
          dataLabels = list(
            enabled = TRUE, color = "#fff",
            style = list(textOutline = "none", fontWeight = "bold", fontSize = "14px")
          )
        ) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a", borderColor = "#333",
          style = list(color = "#fff"),
          formatter = JS("function() { return '<b>' + this.series.xAxis.categories[this.point.x] + '</b> × <b>' + this.series.yAxis.categories[this.point.y] + '</b><br/>Bildirim: ' + this.point.value; }")
        ) %>%
        highcharter::hc_legend(
          align = "right", layout = "vertical", verticalAlign = "middle",
          symbolHeight = 200,
          title = list(text = "Bildirim<br/>Sayısı", style = list(color = "#999", fontSize = "11px")),
          itemStyle = list(color = "#999")
        ) %>%
        highcharter::hc_credits(enabled = FALSE)
    })

    # Öncelik bazlı trend (yığılmış alan)
    output$ha_oncelik_trend_chart <- highcharter::renderHighchart({
      data <- ha_data()$oncelik_trend
      if (nrow(data) == 0) return(highcharter::highchart())

      tarihler <- sort(unique(data$tarih))
      tarih_labels <- vapply(tarihler, admin_format_turkish_date, character(1))

      oncelik_renkler <- c(
        "dusuk" = "#3b82f6", "orta" = "#f59e0b",
        "yuksek" = "#f97316", "kritik" = "#ef4444",
        "belirtilmedi" = "#94a3b8"
      )

      oncelikler <- unique(data$Oncelik)

      hc <- highcharter::highchart() %>%
        highcharter::hc_chart(type = "areaspline", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = as.list(tarih_labels),
          labels = list(style = list(color = "#999"))
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Bildirim Sayısı", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#444"
        ) %>%
        highcharter::hc_plotOptions(
          areaspline = list(stacking = "normal", marker = list(enabled = FALSE), lineWidth = 2)
        ) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a", borderColor = "#333",
          style = list(color = "#fff"), shared = TRUE
        ) %>%
        highcharter::hc_legend(itemStyle = list(color = "#999")) %>%
        highcharter::hc_credits(enabled = FALSE)

      for (o in oncelikler) {
        o_data <- data[data$Oncelik == o, ]
        counts <- sapply(tarihler, function(t) {
          row <- o_data[o_data$tarih == t, ]
          if (nrow(row) > 0) row$cnt[1] else 0
        })
        o_label <- ifelse(o %in% names(oncelik_cevirisi), oncelik_cevirisi[o], o)
        o_renk <- ifelse(o %in% names(oncelik_renkler), oncelik_renkler[o], "#94a3b8")
        hc <- hc %>% highcharter::hc_add_series(name = o_label, data = as.list(counts), color = o_renk)
      }

      hc
    })

    # ============================================================
    # GRAFİKLER: ZAMAN ANALİZİ
    # ============================================================

    # Haftalık trend
    output$ha_haftalik_trend_chart <- highcharter::renderHighchart({
      data <- ha_data()$haftalik_trend
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

      chart_data <- lapply(seq_len(nrow(data)), function(i) {
        list(
          y = data$cnt[i],
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
          title = list(text = "Bildirim Sayısı", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#444", min = 0
        ) %>%
        highcharter::hc_plotOptions(
          areaspline = list(marker = list(enabled = TRUE, radius = 4), lineWidth = 3)
        ) %>%
        highcharter::hc_add_series(
          name = "Hata Bildirimi", data = chart_data,
          color = "#f97316",
          fillColor = list(
            linearGradient = list(x1 = 0, y1 = 0, x2 = 0, y2 = 1),
            stops = list(list(0, "rgba(249, 115, 22, 0.3)"), list(1, "rgba(249, 115, 22, 0)"))
          )
        ) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a", borderColor = "#333",
          style = list(color = "#fff"),
          formatter = JS("function() { return '<b>Hafta başlangıcı:</b> ' + this.point.hafta_basi + '<br/><b>Bildirim:</b> ' + this.y; }")
        ) %>%
        highcharter::hc_legend(enabled = FALSE) %>%
        highcharter::hc_credits(enabled = FALSE)
    })

    # Saatlik dağılım
    output$ha_saatlik_chart <- highcharter::renderHighchart({
      # Yenile butonuna açık bağımlılık (grafik yeniden çizilsin)
      refresh$trigger()
      data <- ha_data()$saatlik_dagilim
      if (nrow(data) == 0) return(highcharter::highchart())

      data <- data[order(data$saat), ]

      highcharter::highchart() %>%
        highcharter::hc_chart(type = "areaspline", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = sprintf("%02d:00", data$saat),
          labels = list(style = list(color = "#999"), step = 2)
        ) %>%
        highcharter::hc_yAxis(
          title = list(text = "Bildirim Sayısı", style = list(color = "#999")),
          labels = list(style = list(color = "#999")),
          gridLineColor = "#444", min = 0
        ) %>%
        highcharter::hc_plotOptions(
          areaspline = list(marker = list(enabled = FALSE), lineWidth = 2.5)
        ) %>%
        highcharter::hc_add_series(
          name = "Bildirim", data = data$cnt,
          color = "#8b5cf6",
          fillColor = list(
            linearGradient = list(x1 = 0, y1 = 0, x2 = 0, y2 = 1),
            stops = list(list(0, "rgba(139, 92, 246, 0.3)"), list(1, "rgba(139, 92, 246, 0)"))
          )
        ) %>%
        highcharter::hc_tooltip(
          backgroundColor = "#1a1a1a", borderColor = "#333",
          style = list(color = "#fff")
        ) %>%
        highcharter::hc_legend(enabled = FALSE) %>%
        highcharter::hc_credits(enabled = FALSE)
    })

    # Kullanıcı bazlı tablo
    output$ha_kullanici_tablo <- DT::renderDataTable({
      data <- ha_data()$kullanici_bildirim
      if (nrow(data) == 0) return(DT::datatable(data.frame()))

      data$row_num <- 1:nrow(data)
      data$son_bildirim <- format(as.POSIXct(data$son_bildirim), "%d.%m.%Y %H:%M")
      data$kullanici <- ifelse(!is.na(data$KullaniciAdi) & nzchar(data$KullaniciAdi), data$KullaniciAdi, "-")

      display_data <- data[, c("row_num", "kullanici", "bildirim_sayisi", "kritik_sayisi", "son_bildirim")]
      colnames(display_data) <- c("#", "Kullanıcı", "Bildirim", "Kritik", "Son Bildirim")

      DT::datatable(
        display_data,
        options = list(
          dom = 't', pageLength = 20, scrollY = FALSE,
          ordering = TRUE, order = list(list(2, 'desc')),
          language = admin_turkish_dt_language,
          columnDefs = list(
            list(className = 'dt-center', targets = c(0, 2, 3, 4)),
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
    # DETAYLI BİLDİRİMLER TABLOSU
    # ============================================================
    output$ha_detay_tablo <- DT::renderDataTable({
      data <- ha_data()$tumu
      if (nrow(data) == 0) return(DT::datatable(data.frame()))

      data$row_num <- 1:nrow(data)

      # Arka plan rengine göre okunabilir metin rengi seç (açık arka plan → koyu metin)
      badge_text_color <- function(bg_hex) {
        rgb_vals <- col2rgb(bg_hex)
        # Algısal parlaklık hesabı (WCAG formülü)
        parlaklik <- (0.299 * rgb_vals[1] + 0.587 * rgb_vals[2] + 0.114 * rgb_vals[3]) / 255
        if (parlaklik > 0.55) "#1a1a1a" else "#ffffff"
      }

      # Öncelik rozeti
      oncelik_badge <- function(o) {
        renk <- switch(o,
          "dusuk" = "#3b82f6", "orta" = "#f59e0b",
          "yuksek" = "#f97316", "kritik" = "#ef4444", "#94a3b8"
        )
        metin_renk <- badge_text_color(renk)
        label <- ifelse(o %in% names(oncelik_cevirisi), oncelik_cevirisi[o], o)
        sprintf('<span style="background:%s; color:%s; padding:2px 8px; border-radius:4px; font-size:11px; font-weight:600;">%s</span>', renk, metin_renk, label)
      }

      # Durum rozeti
      durum_badge <- function(d) {
        renk <- switch(d,
          "acik" = "#f59e0b", "inceleme" = "#3b82f6",
          "cozuldu" = "#10b981", "kapandi" = "#64748b",
          "reddedildi" = "#ef4444", "#94a3b8"
        )
        metin_renk <- badge_text_color(renk)
        label <- ifelse(d %in% names(durum_cevirisi), durum_cevirisi[d], d)
        sprintf('<span style="background:%s; color:%s; padding:2px 8px; border-radius:4px; font-size:11px; font-weight:600;">%s</span>', renk, metin_renk, label)
      }

      data$oncelik_display <- sapply(data$Oncelik, oncelik_badge)
      data$durum_display <- sapply(data$Durum, durum_badge)
      data$tarih <- format(as.POSIXct(data$OlusturmaTarihi), "%d.%m.%Y %H:%M")
      data$kullanici <- ifelse(!is.na(data$KullaniciAdi) & nzchar(data$KullaniciAdi), data$KullaniciAdi, "-")
      data$konular_display <- ifelse(nzchar(data$Konular), data$Konular, "-")

      # Kategori çevirisi
      data$kategori_display <- sapply(data$Kategoriler, function(k) {
        if (is.na(k) || !nzchar(k)) return("-")
        parcalar <- trimws(strsplit(k, ",")[[1]])
        paste(ifelse(parcalar %in% names(kategori_cevirisi), kategori_cevirisi[parcalar], parcalar), collapse = ", ")
      })

      data$aciklama_display <- ifelse(nchar(data$Aciklama) > 100,
        paste0(substr(data$Aciklama, 1, 100), "..."), data$Aciklama)

      # Ek dosya bağlantısı
      data$dosya_display <- sapply(seq_len(nrow(data)), function(i) {
        if (!is.na(data$EkDosyaYollari[i]) && nzchar(data$EkDosyaYollari[i])) {
          dosya_sayisi <- length(strsplit(data$EkDosyaYollari[i], ",")[[1]])
          sprintf('<a href="#" onclick="Shiny.setInputValue(\'%s\', %d, {priority: \'event\'}); return false;" style="color: #06b6d4; text-decoration: underline;">%d dosya</a>',
            ns("dosya_goster"), data$HataBildirimID[i], dosya_sayisi)
        } else {
          "-"
        }
      })

      # Durum güncelleme bağlantısı
      data$islem_display <- sapply(seq_len(nrow(data)), function(i) {
        sprintf('<a href="#" onclick="Shiny.setInputValue(\'%s\', %d, {priority: \'event\'}); return false;" style="color: #f59e0b;" title="Durum güncelle"><i class="fas fa-edit"></i></a>',
          ns("durum_guncelle"), data$HataBildirimID[i])
      })

      display_data <- data[, c("row_num", "kullanici", "konular_display", "kategori_display",
                                "oncelik_display", "durum_display", "aciklama_display",
                                "dosya_display", "islem_display", "tarih")]
      colnames(display_data) <- c("#", "Kullanıcı", "Konular", "Kategori", "Öncelik",
                                   "Durum", "Açıklama", "Dosyalar", "İşlem", "Tarih")

      DT::datatable(
        display_data,
        escape = FALSE,
        options = list(
          dom = 'frtip', pageLength = 15,
          ordering = TRUE, order = list(list(9, 'desc')),
          language = admin_turkish_dt_language,
          columnDefs = list(
            list(className = 'dt-center', targets = c(0, 4, 5, 7, 8, 9)),
            list(className = 'row-number-col', targets = 0),
            list(width = '40px', targets = 0),
            list(width = '120px', targets = c(4, 5)),
            list(width = '60px', targets = 8),
            list(orderable = FALSE, targets = c(0, 7, 8))
          ),
          headerCallback = admin_dt_header_callback
        ),
        class = "admin-datatable", rownames = FALSE
      )
    })

    # ============================================================
    # EK DOSYA GÖRÜNTÜLEYİCİ
    # ============================================================
    observeEvent(input$dosya_goster, {
      bildirim_id <- input$dosya_goster
      data <- ha_data()$tumu
      bildirim <- data[data$HataBildirimID == bildirim_id, ]

      if (nrow(bildirim) == 0) return()

      dosya_yollari <- bildirim$EkDosyaYollari[1]
      if (is.na(dosya_yollari) || !nzchar(dosya_yollari)) return()

      dosyalar <- trimws(strsplit(dosya_yollari, ",")[[1]])

      output$ek_dosya_content <- renderUI({
        # İndirme butonu oluşturma yardımcı fonksiyonu
        indir_btn <- function(gorsel_yol, dosya_adi) {
          tags$a(
            href = gorsel_yol, download = dosya_adi, target = "_blank",
            class = "btn btn-sm",
            style = paste(
              "display: inline-flex; align-items: center; gap: 6px;",
              "margin-top: 10px; padding: 6px 16px;",
              "background: linear-gradient(135deg, #06b6d4, #3b82f6);",
              "color: #fff; border: none; border-radius: 8px;",
              "font-size: 12px; font-weight: 600; text-decoration: none;",
              "transition: all 0.3s ease;"
            ),
            icon("download"), dosya_adi
          )
        }

        dosya_elements <- lapply(dosyalar, function(dosya_yolu) {
          # Dosya uzantısını belirle
          uzanti <- tolower(tools::file_ext(dosya_yolu))
          dosya_adi <- basename(dosya_yolu)

          # Dosya yolunu addResourcePath üzerinden erişilebilir URL'ye dönüştür
          gorsel_yol <- if (grepl("^destek_uploads/", dosya_yolu)) {
            paste0("/", dosya_yolu)
          } else {
            paste0("/destek_uploads/", dosya_yolu)
          }

          if (uzanti %in% c("png", "jpg", "jpeg", "gif")) {
            div(
              class = "admin-attachment-item",
              div(
                style = "display: flex; align-items: center; justify-content: space-between; margin-bottom: 10px;",
                h5(icon("image"), " ", dosya_adi, style = "color: #ccc; margin: 0;"),
                indir_btn(gorsel_yol, dosya_adi)
              ),
              # Yakınlaştırılabilir görsel konteyner
              div(
                class = "admin-attachment-zoom-container",
                style = "position: relative; overflow: hidden; border-radius: 8px; border: 1px solid #333; cursor: zoom-in;",
                onclick = "this.classList.toggle('zoomed'); this.style.cursor = this.classList.contains('zoomed') ? 'zoom-out' : 'zoom-in';",
                tags$img(
                  src = gorsel_yol,
                  style = "width: 100%; max-height: 70vh; object-fit: contain; border-radius: 8px; transition: transform 0.3s ease;",
                  alt = dosya_adi
                )
              )
            )
          } else if (uzanti == "mp4") {
            div(
              class = "admin-attachment-item",
              div(
                style = "display: flex; align-items: center; justify-content: space-between; margin-bottom: 10px;",
                h5(icon("video"), " ", dosya_adi, style = "color: #ccc; margin: 0;"),
                indir_btn(gorsel_yol, dosya_adi)
              ),
              tags$video(
                src = gorsel_yol,
                controls = "controls",
                style = "width: 100%; max-height: 70vh; border-radius: 8px; background: #000;",
                type = "video/mp4"
              )
            )
          } else {
            div(
              class = "admin-attachment-item",
              div(
                style = "display: flex; align-items: center; justify-content: space-between; margin-bottom: 10px;",
                h5(icon("file"), " ", dosya_adi, style = "color: #ccc; margin: 0;"),
                indir_btn(gorsel_yol, dosya_adi)
              ),
              p(style = "color: #999;", "Bu dosya türü önizlenemez.")
            )
          }
        })
        do.call(tagList, dosya_elements)
      })

      # Modal'ı body'ye taşı (Shiny modül namespace içindeki z-index sorunlarını önlemek için)
      # ve ardından göster
      shinyjs::runjs(sprintf("
        var modal = $('#%s');
        if (!modal.data('moved-to-body')) {
          modal.appendTo('body');
          modal.data('moved-to-body', true);
        }
        modal.modal('show');
      ", ns("ek_dosya_modal")))
    })

    # ============================================================
    # DURUM GÜNCELLEME
    # ============================================================
    observeEvent(input$durum_guncelle, {
      bildirim_id <- input$durum_guncelle
      data <- ha_data()$tumu
      bildirim <- data[data$HataBildirimID == bildirim_id, ]

      if (nrow(bildirim) == 0) return()

      # Mevcut durumu seç
      mevcut_durum <- bildirim$Durum[1]
      updateSelectInput(session, "yeni_durum", selected = mevcut_durum)

      # Bildirim ID'sini hidden input'a yaz
      shinyjs::runjs(sprintf("$('#%s').val(%d);", ns("durum_bildirim_id"), bildirim_id))

      # Modal'ı body'ye taşı ve göster
      shinyjs::runjs(sprintf("
        var modal = $('#%s');
        if (!modal.data('moved-to-body')) {
          modal.appendTo('body');
          modal.data('moved-to-body', true);
        }
        modal.modal('show');
      ", ns("durum_modal")))
    })

    observeEvent(input$durum_kaydet, {
      # Hidden input'tan bildirim ID'sini JavaScript ile oku ve Shiny'ye gönder
      shinyjs::runjs(sprintf(
        "Shiny.setInputValue('%s', parseInt($('#%s').val()), {priority: 'event'});",
        ns("durum_bildirim_id_val"), ns("durum_bildirim_id")
      ))
    })

    observeEvent(input$durum_bildirim_id_val, {
      req(input$durum_bildirim_id_val)
      bildirim_id <- as.integer(input$durum_bildirim_id_val)
      yeni_durum <- input$yeni_durum

      tryCatch({
        destek_hata_durum_guncelle(bildirim_id, yeni_durum)
        showToast(session, "Durum başarıyla güncellendi", "success")
        refresh$trigger(refresh$trigger() + 1)
        shinyjs::runjs(sprintf("$('#%s').modal('hide'); $('.modal-backdrop').remove();", ns("durum_modal")))
      }, error = function(e) {
        showToast(session, paste("Hata:", conditionMessage(e)), "error")
      })
    })

  })
}
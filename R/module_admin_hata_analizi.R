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

    # Kategori, öncelik ve durum Türkçe karşılıkları helper dosyasında tutulur.
    kategori_cevirisi <- admin_ha_category_labels()
    oncelik_cevirisi <- admin_ha_priority_labels()
    durum_cevirisi <- admin_ha_status_labels()

    # ============================================================
    # VERİ ÇEKİMİ
    # ============================================================
    ha_data <- reactive({
      refresh$trigger()
      admin_ha_fetch_data()
    })

    # ============================================================
    # KATEGORİ ÇÖZÜMLEME
    # ============================================================
    kategori_sayilari <- reactive({
      admin_ha_count_categories(
        ha_data()$kategoriler_ham,
        kategori_cevirisi = kategori_cevirisi
      )
    })

    # ============================================================
    # SEKME İÇERİĞİ YÖNLENDİRİCİ
    # ============================================================
    output$tab_content_area <- renderUI({
      tab <- input$admin_tabs
      if (is.null(tab)) tab <- "ha_overview"

      admin_init_tooltips(session)

      admin_ha_tab_ui(
        tab = tab,
        ns = ns,
        data_provider = ha_data
      )
    })

    # Sekme UI üretimi R/helpers_admin_hata_analizi.R içindeki helperlara taşındı.

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

    # Isı haritası (Öncelik \U00D7 Kategori)
    output$ha_heatmap_chart <- highcharter::renderHighchart({
      data <- ha_data()$oncelik_kategori
      if (nrow(data) == 0) return(highcharter::highchart())

      heatmap <- admin_ha_prepare_heatmap_data(
        data = data,
        kategori_cevirisi = kategori_cevirisi,
        oncelik_cevirisi = oncelik_cevirisi
      )

      kategoriler <- heatmap$kategoriler
      oncelikler <- heatmap$oncelikler
      heatmap_data <- heatmap$heatmap_data

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
          formatter = JS("function() { return '<b>' + this.series.xAxis.categories[this.point.x] + '</b> \U00D7 <b>' + this.series.yAxis.categories[this.point.y] + '</b><br/>Bildirim: ' + this.point.value; }")
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
    output$ha_kullanici_tablo <- DT::renderDT({
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
    # DETAYLI BİLDİRİMLER / EK DOSYA / DURUM RUNTIME
    # ============================================================
    admin_ha_register_detail_runtime(
      input = input,
      output = output,
      session = session,
      ha_data = ha_data,
      refresh = refresh,
      kategori_cevirisi = kategori_cevirisi,
      oncelik_cevirisi = oncelik_cevirisi,
      durum_cevirisi = durum_cevirisi
    )
  })
}
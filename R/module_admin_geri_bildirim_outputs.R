# Dosya Yolu: R/module_admin_geri_bildirim_outputs.R
# Açıklama: Yönetici paneli - Geri Bildirim Analizi modülünün grafik/tablo
#            çıktı (output) renderer'ları. Bakım bütçesini korumak için
#            R/module_admin_geri_bildirim.R server gövdesinden BİREBİR çıkarıldı
#            (davranış değişmedi). admin_gb_outputs(...) tüm highcharter ve DT
#            render fonksiyonlarını kaydeder; veri reaktifleri (gb_data,
#            etiket_sayilari) ile global admin yardımcıları (JS,
#            admin_turkish_dt_language, admin_dt_header_callback,
#            admin_format_turkish_date) çağrı anında çözülür.
#
#            Koruyan testler:
#              - tests/testthat/test-admin-geri-bildirim-outputs-behavior.R
#              - tests/testthat/test-admin-geri-bildirim-refactor-contract.R

#' Geri Bildirim Analizi grafiklerini ve tablolarını (output) kaydeder
#' @param output Shiny output nesnesi
#' @param gb_data Geri bildirim verisi reaktifi (admin_gb_fetch_data sonucu)
#' @param etiket_sayilari Etiket sayımı reaktifi (admin_gb_count_tags sonucu)
admin_gb_outputs <- function(output, gb_data, etiket_sayilari) {
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
      display_data <- admin_gb_prepare_kullanici_table_data(gb_data()$kullanici_memnuniyet)
      if (nrow(display_data) == 0) return(DT::datatable(data.frame()))

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
      display_data <- admin_gb_prepare_detay_table_data(gb_data()$tumu)
      if (nrow(display_data) == 0) return(DT::datatable(data.frame()))

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
}

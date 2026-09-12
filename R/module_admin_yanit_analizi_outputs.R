# Dosya Yolu: R/module_admin_yanit_analizi_outputs.R
# Açıklama: Yönetici paneli - Yanıt Geri Bildirimi Analizi modülünün grafik/tablo
#            çıktı (output) renderer'ları. Bakım bütçesini korumak için
#            R/module_admin_yanit_analizi.R server gövdesinden BİREBİR çıkarıldı
#            (davranış değişmedi). admin_yanit_outputs(...) tüm highcharter ve DT
#            render fonksiyonlarını kaydeder; veri reaktifleri (ya_data,
#            etiket_sayilari), refresh tetikleyicisi ve global admin yardımcıları
#            (JS, admin_turkish_dt_language, admin_dt_header_callback,
#            admin_format_turkish_date, admin_turkish_days) çağrı anında çözülür.
#            ya_saat_gun_heatmap ve ya_saatlik_chart, yenile butonuna açık
#            bağımlılık için refresh$trigger() çağırır.
#
#            Koruyan testler:
#              - tests/testthat/test-admin-yanit-analizi-outputs-behavior.R
#              - tests/testthat/test-admin-yanit-analizi-refactor-contract.R

#' Yanıt Geri Bildirimi Analizi grafiklerini ve tablolarını (output) kaydeder
#' @param output Shiny output nesnesi
#' @param ya_data Yanıt geri bildirim verisi reaktifi (admin_yanit_collect_data sonucu)
#' @param etiket_sayilari Etiket sayımı reaktifi (admin_yanit_tag_counts sonucu)
#' @param refresh admin_refresh_setup() sonucu; saat/saatlik grafikler trigger() çağırır
admin_yanit_outputs <- function(output, ya_data, etiket_sayilari, refresh) {
    # ============================================================
    # GRAFİKLER: GENEL BAKIŞ
    # ============================================================

    # Günlük trend (beğeni / beğenmeme yığılmış alan)
    output$ya_gunluk_trend_chart <- highcharter::renderHighchart({
      data <- ya_data()$gunluk_trend

      tum_gunler <- data.frame(
        tarih = seq(Sys.Date() - 29, Sys.Date(), by = "day")
      )

      if (nrow(data) > 0) {
        data$tarih <- as.Date(data$tarih)
        data$begeni <- as.numeric(data$begeni)
        data$begenmeme <- as.numeric(data$begenmeme)

        data <- merge(
          tum_gunler,
          data[, c("tarih", "begeni", "begenmeme")],
          by = "tarih",
          all.x = TRUE,
          sort = TRUE
        )
      } else {
        data <- tum_gunler
        data$begeni <- 0
        data$begenmeme <- 0
      }

      data$begeni[is.na(data$begeni)] <- 0
      data$begenmeme[is.na(data$begenmeme)] <- 0
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
          name = "Beğeni", data = as.list(data$begeni), type = "areaspline",
          color = "#10b981",
          fillColor = list(
            linearGradient = list(x1 = 0, y1 = 0, x2 = 0, y2 = 1),
            stops = list(list(0, "rgba(16, 185, 129, 0.4)"), list(1, "rgba(16, 185, 129, 0.05)"))
          )
        ) %>%
        highcharter::hc_add_series(
          name = "Beğenmeme", data = as.list(data$begenmeme), type = "areaspline",
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
        highcharter::hc_add_series(name = "Beğeni", data = as.list(as.numeric(data$begeni)), color = "#10b981") %>%
        highcharter::hc_add_series(name = "Beğenmeme", data = as.list(as.numeric(data$begenmeme)), color = "#ef4444") %>%
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
      sira <- c("0-5 sn", "5-10 sn", "10-20 sn", "20+ sn")

      tam <- data.frame(
        sure_grubu = sira,
        begeni = 0,
        begenmeme = 0,
        stringsAsFactors = FALSE
      )

      if (nrow(data) > 0) {
        data$sure_grubu <- as.character(data$sure_grubu)
        data$begeni <- as.numeric(data$begeni)
        data$begenmeme <- as.numeric(data$begenmeme)

        idx <- match(data$sure_grubu, tam$sure_grubu)
        gecerli <- !is.na(idx)

        tam$begeni[idx[gecerli]] <- data$begeni[gecerli]
        tam$begenmeme[idx[gecerli]] <- data$begenmeme[gecerli]
      }

      highcharter::highchart() %>%
        highcharter::hc_chart(type = "bar", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = tam$sure_grubu,
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
        highcharter::hc_add_series(name = "Beğeni", data = as.list(tam$begeni), color = "#10b981") %>%
        highcharter::hc_add_series(name = "Beğenmeme", data = as.list(tam$begenmeme), color = "#ef4444") %>%
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

      data$toplam_yanit <- as.numeric(data$toplam_yanit)
      data$begeni <- as.numeric(data$begeni)
      data$begenmeme <- as.numeric(data$begenmeme)
      data$begeni_oran <- ifelse(data$toplam_yanit > 0, round((data$begeni / data$toplam_yanit) * 100, 1), 0)
      data$begenmeme_oran <- ifelse(data$toplam_yanit > 0, round((data$begenmeme / data$toplam_yanit) * 100, 1), 0)
      data <- data[order(-data$begeni_oran), ]

      # Model isimlerini kısalt (çok uzunsa)
      data$model_kisa <- sapply(data$ModelUsed, function(m) {
        if (is.na(m) || nchar(m) > 35) paste0(substr(m, 1, 32), "...") else m
      })

      highcharter::highchart() %>%
        highcharter::hc_chart(type = "bar", backgroundColor = "transparent") %>%
        highcharter::hc_title(text = NULL) %>%
        highcharter::hc_xAxis(
          categories = as.list(data$model_kisa),
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
        highcharter::hc_add_series(name = "Beğeni", data = as.list(data$begeni), color = "#10b981") %>%
        highcharter::hc_add_series(name = "Beğenmeme", data = as.list(data$begenmeme), color = "#ef4444") %>%
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

      data$toplam_yanit <- as.numeric(data$toplam_yanit)
      data$begeni <- as.numeric(data$begeni)
      data$begenmeme <- as.numeric(data$begenmeme)
      data$ort_sure <- as.numeric(data$ort_sure)
      data$row_num <- 1:nrow(data)
      data$begeni_oran <- ifelse(data$toplam_yanit > 0, round((data$begeni / data$toplam_yanit) * 100, 1), 0)
      data$ort_sure <- round(data$ort_sure, 1)

      # Beğeni oranı renkli gösterim
      data$oran_display <- sapply(data$begeni_oran, function(o) {
        renk <- if (o >= 80) "#10b981" else if (o >= 60) "#f59e0b" else "#ef4444"
        sprintf('<span style="color:%s; font-weight:bold;">%.1f%%</span>', renk, o)
      })

      # Model adı yapılandırmadan gelir ama tabloya girmeden önce kaçırılır;
      # escape = FALSE yalnızca uygulama üretimi oran hücresi içindir.
      data$ModelUsed <- htmltools::htmlEscape(as.character(data$ModelUsed))

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

      # Tarih sütununu görünür Türkçe biçim + DT için sıralanabilir ISO data-order ile sar
      data$tarih <- ifelse(!is.na(data$FeedbackTimestamp),
        paste0("<span data-order='", format(as.POSIXct(data$FeedbackTimestamp), "%Y-%m-%d %H:%M:%S"), "'>", format(as.POSIXct(data$FeedbackTimestamp), "%d.%m.%Y %H:%M"), "</span>"),
        "-")
      # escape = FALSE yalnızca UYGULAMA ÜRETİMİ sütunlar (tip/tarih) içindir;
      # kullanıcı/LLM kontrollü metinler tabloya girmeden ÖNCE kaçırılır.
      data$kullanici <- htmltools::htmlEscape(
        ifelse(!is.na(data$KullaniciAdi) & nzchar(data$KullaniciAdi), data$KullaniciAdi, "-")
      )
      data$etiketler <- htmltools::htmlEscape(
        ifelse(!is.na(data$FeedbackTags) & nzchar(data$FeedbackTags), data$FeedbackTags, "-")
      )
      data$yorum <- htmltools::htmlEscape(
        ifelse(!is.na(data$FeedbackComment) & nzchar(data$FeedbackComment), data$FeedbackComment, "-")
      )
      data$onizleme <- htmltools::htmlEscape(ifelse(
        !is.na(data$YanitOnizleme) & nzchar(data$YanitOnizleme),
        paste0(substr(data$YanitOnizleme, 1, 120), "..."), "-"
      ))

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
            list(orderable = FALSE, targets = 0),
            list(targets = 6, render = DT::JS("function(d,t){if(t==='sort'||t==='type'){var m=d&&d.match?d.match(/data-order='([^']+)'/):null;return m?m[1]:d;}return d;}"))
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
      # Kullanıcı adı SSO/DB kaynaklıdır; escape = FALSE tablosunda kaçırılır.
      data$kullanici <- htmltools::htmlEscape(
        ifelse(!is.na(data$KullaniciAdi) & nzchar(data$KullaniciAdi), data$KullaniciAdi, "-")
      )

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
}

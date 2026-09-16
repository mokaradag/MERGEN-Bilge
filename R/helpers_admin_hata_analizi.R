# ==============================================================================
# Dosya Yolu: R/helpers_admin_hata_analizi.R
# Açıklama: Yönetici hata analizi modülü için sorgu, saf veri dönüştürme ve
#           UI yardımcıları. Observer veya Shiny reactive state mutasyonu içermez.
# ==============================================================================

admin_ha_category_labels <- function() {
  c(
    "arayuz"         = "Arayüz / Tasarım",
    "fonksiyonellik" = "İşlevsellik",
    "performans"     = "Performans",
    "cokme"          = "Çökme / Hata",
    "diger"          = "Diğer"
  )
}

admin_ha_priority_labels <- function() {
  c(
    "dusuk"        = "Düşük",
    "orta"         = "Orta",
    "yuksek"       = "Yüksek",
    "kritik"       = "Kritik",
    "belirtilmedi" = "Belirtilmedi"
  )
}

admin_ha_status_labels <- function() {
  c(
    "acik"       = "Açık",
    "inceleme"   = "İncelemede",
    "cozuldu"    = "Çözüldü",
    "kapandi"    = "Kapandı",
    "reddedildi" = "Reddedildi"
  )
}

admin_ha_fetch_data <- function(query_fn = admin_safe_query) {
  stopifnot(is.function(query_fn))

  list(
    tumu = query_fn("
      SELECT
        hb.HataBildirimID, hb.UserID, u.KaynakAdi AS KullaniciAdi,
        hb.Konular, hb.Kategoriler, hb.Oncelik, hb.Aciklama,
        hb.EkDosyaYollari, hb.Durum, hb.OlusturmaTarihi
      FROM MB_Destek_Hata_Bildir hb
      LEFT JOIN MB_Users u ON hb.UserID = u.UserID
      ORDER BY hb.OlusturmaTarihi DESC
    "),

    toplam = query_fn("SELECT COUNT(*) as cnt FROM MB_Destek_Hata_Bildir"),

    durum_dagilim = query_fn("
      SELECT Durum, COUNT(*) as cnt
      FROM MB_Destek_Hata_Bildir
      GROUP BY Durum
      ORDER BY cnt DESC
    "),

    oncelik_dagilim = query_fn("
      SELECT Oncelik, COUNT(*) as cnt
      FROM MB_Destek_Hata_Bildir
      GROUP BY Oncelik
      ORDER BY cnt DESC
    "),

    bugun = query_fn("
      SELECT COUNT(*) as cnt FROM MB_Destek_Hata_Bildir
      WHERE CAST(OlusturmaTarihi AS DATE) = CAST(GETDATE() AS DATE)
    "),

    bu_hafta = query_fn("
      SELECT COUNT(*) as cnt FROM MB_Destek_Hata_Bildir
      WHERE OlusturmaTarihi >= DATEADD(day, -7, GETDATE())
    "),

    gunluk_trend = query_fn("
      SELECT
        CAST(OlusturmaTarihi AS DATE) as tarih,
        COUNT(*) as cnt
      FROM MB_Destek_Hata_Bildir
      WHERE OlusturmaTarihi >= DATEADD(day, -30, GETDATE())
      GROUP BY CAST(OlusturmaTarihi AS DATE)
      ORDER BY tarih
    "),

    oncelik_trend = query_fn("
      SELECT
        CAST(OlusturmaTarihi AS DATE) as tarih,
        Oncelik,
        COUNT(*) as cnt
      FROM MB_Destek_Hata_Bildir
      WHERE OlusturmaTarihi >= DATEADD(day, -30, GETDATE())
      GROUP BY CAST(OlusturmaTarihi AS DATE), Oncelik
      ORDER BY tarih
    "),

    kategoriler_ham = query_fn("
      SELECT Kategoriler FROM MB_Destek_Hata_Bildir
      WHERE Kategoriler IS NOT NULL AND Kategoriler <> ''
    "),

    ekli_bildirim = query_fn("
      SELECT COUNT(*) as cnt FROM MB_Destek_Hata_Bildir
      WHERE EkDosyaYollari IS NOT NULL AND EkDosyaYollari <> ''
    "),

    kullanici_bildirim = query_fn("
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

    saatlik_dagilim = query_fn("
      SELECT
        DATEPART(HOUR, OlusturmaTarihi) as saat,
        COUNT(*) as cnt
      FROM MB_Destek_Hata_Bildir
      GROUP BY DATEPART(HOUR, OlusturmaTarihi)
      ORDER BY saat
    "),

    haftalik_trend = query_fn("
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

    oncelik_kategori = query_fn("
      SELECT Oncelik, Kategoriler, COUNT(*) as cnt
      FROM MB_Destek_Hata_Bildir
      WHERE Kategoriler IS NOT NULL AND Kategoriler <> ''
      GROUP BY Oncelik, Kategoriler
    ")
  )
}

admin_ha_count_categories <- function(
  ham,
  kategori_cevirisi = admin_ha_category_labels()
) {
  empty_result <- data.frame(
    kategori = character(0),
    cnt = integer(0),
    stringsAsFactors = FALSE
  )

  if (is.null(ham) || !is.data.frame(ham) || nrow(ham) == 0) {
    return(empty_result)
  }

  if (!"Kategoriler" %in% names(ham)) {
    return(empty_result)
  }

  tum_kategoriler <- unlist(strsplit(as.character(ham$Kategoriler), ","))
  tum_kategoriler <- trimws(tum_kategoriler)
  tum_kategoriler <- tum_kategoriler[!is.na(tum_kategoriler) & nzchar(tum_kategoriler)]

  if (length(tum_kategoriler) == 0) {
    return(empty_result)
  }

  tablo <- as.data.frame(table(tum_kategoriler), stringsAsFactors = FALSE)
  colnames(tablo) <- c("kategori", "cnt")

  tablo$kategori_tr <- ifelse(
    tablo$kategori %in% names(kategori_cevirisi),
    kategori_cevirisi[tablo$kategori],
    tablo$kategori
  )

  tablo[order(-tablo$cnt), , drop = FALSE]
}

admin_ha_tab_ui <- function(tab, ns, data_provider) {
  if (is.null(tab) || !nzchar(tab)) {
    tab <- "ha_overview"
  }

  switch(tab,
    "ha_overview" = admin_ha_overview_ui(ns, data_provider()),
    "ha_oncelik"  = admin_ha_oncelik_ui(ns),
    "ha_detay"    = admin_ha_detay_ui(ns),
    "ha_zaman"    = admin_ha_zaman_ui(ns),
    admin_ha_overview_ui(ns, data_provider())
  )
}

admin_ha_overview_ui <- function(ns, data) {
  toplam <- if (nrow(data$toplam) > 0) data$toplam$cnt[1] else 0
  bugun_cnt <- if (nrow(data$bugun) > 0) data$bugun$cnt[1] else 0
  hafta_cnt <- if (nrow(data$bu_hafta) > 0) data$bu_hafta$cnt[1] else 0
  ekli_cnt <- if (nrow(data$ekli_bildirim) > 0) data$ekli_bildirim$cnt[1] else 0

  acik_cnt <- 0
  cozuldu_cnt <- 0
  kritik_cnt <- 0

  # NULL Durum/Oncelik grubu NA indeks üretip kartları NA gösterirdi; NA-güvenli.
  if (nrow(data$durum_dagilim) > 0) {
    durum_vec <- as.character(data$durum_dagilim$Durum)
    acik_cnt <- sum(data$durum_dagilim$cnt[!is.na(durum_vec) & durum_vec == "acik"], na.rm = TRUE)
    cozuldu_cnt <- sum(data$durum_dagilim$cnt[!is.na(durum_vec) & durum_vec %in% c("cozuldu", "kapandi")], na.rm = TRUE)
  }

  if (nrow(data$oncelik_dagilim) > 0) {
    oncelik_vec <- as.character(data$oncelik_dagilim$Oncelik)
    kritik_cnt <- sum(data$oncelik_dagilim$cnt[!is.na(oncelik_vec) & oncelik_vec == "kritik"], na.rm = TRUE)
  }

  cozum_oran <- if (toplam > 0) sprintf("%.0f%%", (cozuldu_cnt / toplam) * 100) else "N/A"

  shiny::tagList(
    shiny::div(
      class = "metrics-grid",
      admin_create_metric_card(
        "Toplam Bildirim",
        admin_format_number(toplam),
        "bug",
        "blue",
        tooltip = "Kullanıcılardan gelen toplam hata bildirimi sayısı."
      ),
      admin_create_metric_card(
        "Açık Bildirimler",
        admin_format_number(acik_cnt),
        "exclamation-circle",
        "orange",
        tooltip = "Henüz çözülmemiş ve açık durumda olan hata bildirimleri."
      ),
      admin_create_metric_card(
        "Çözülmüş",
        admin_format_number(cozuldu_cnt),
        "check-circle",
        "green",
        tooltip = "Çözüldü veya kapandı olarak işaretlenmiş bildirimler."
      ),
      admin_create_metric_card(
        "Kritik Hatalar",
        admin_format_number(kritik_cnt),
        "fire",
        "red",
        tooltip = "Kritik öncelik seviyesindeki hata bildirimleri."
      ),
      admin_create_metric_card(
        "Çözüm Oranı",
        cozum_oran,
        "chart-pie",
        "purple",
        tooltip = "Çözülen ve kapanan bildirimlerin toplam bildirimlere oranı."
      ),
      admin_create_metric_card(
        "Ek Dosyalı",
        admin_format_number(ekli_cnt),
        "paperclip",
        "cyan",
        tooltip = "Ekran görüntüsü veya video eklenmiş bildirim sayısı."
      ),
      admin_create_metric_card(
        "Bugün Gelen",
        admin_format_number(bugun_cnt),
        "calendar-day",
        "yellow",
        tooltip = "Bugün alınan hata bildirimi sayısı."
      ),
      admin_create_metric_card(
        "Bu Hafta",
        admin_format_number(hafta_cnt),
        "calendar-week",
        "teal",
        tooltip = "Son 7 günde alınan hata bildirimi sayısı."
      )
    ),
    shiny::fluidRow(
      shiny::column(
        width = 8,
        shiny::div(
          class = "analytics-card",
          shiny::div(
            class = "card-title-row",
            shiny::h4(
              class = "card-title",
              shiny::icon("chart-area"),
              " Günlük Hata Bildirim Trendi (30 Gün)"
            ),
            admin_create_info_button("Son 30 gündeki günlük hata bildirim sayısı eğilimi.")
          ),
          highcharter::highchartOutput(ns("ha_gunluk_trend_chart"), height = "320px")
        )
      ),
      shiny::column(
        width = 4,
        shiny::div(
          class = "analytics-card",
          shiny::div(
            class = "card-title-row",
            shiny::h4(
              class = "card-title",
              shiny::icon("chart-pie"),
              " Durum Dağılımı"
            ),
            admin_create_info_button("Hata bildirimlerinin mevcut durum bazında dağılımı.")
          ),
          highcharter::highchartOutput(ns("ha_durum_pie_chart"), height = "320px")
        )
      )
    )
  )
}

admin_ha_oncelik_ui <- function(ns) {
  shiny::tagList(
    shiny::fluidRow(
      shiny::column(
        width = 5,
        shiny::div(
          class = "analytics-card",
          shiny::div(
            class = "card-title-row",
            shiny::h4(
              class = "card-title",
              shiny::icon("signal"),
              " Öncelik Dağılımı"
            ),
            admin_create_info_button("Hata bildirimlerinin öncelik seviyesine göre dağılımı.")
          ),
          highcharter::highchartOutput(ns("ha_oncelik_chart"), height = "380px")
        )
      ),
      shiny::column(
        width = 7,
        shiny::div(
          class = "analytics-card",
          shiny::div(
            class = "card-title-row",
            shiny::h4(
              class = "card-title",
              shiny::icon("sitemap"),
              " Kategori Dağılımı (Ağaç Haritası)"
            ),
            admin_create_info_button("Hata bildirimlerinin kategori bazında görsel oransal dağılımı.")
          ),
          highcharter::highchartOutput(ns("ha_kategori_treemap_chart"), height = "380px")
        )
      )
    ),
    shiny::fluidRow(
      shiny::column(
        width = 12,
        shiny::div(
          class = "analytics-card",
          shiny::div(
            class = "card-title-row",
            shiny::h4(
              class = "card-title",
              shiny::icon("th"),
              " Öncelik \U00D7 Kategori Isı Haritası"
            ),
            admin_create_info_button(
              "Her öncelik-kategori kombinasyonu için hata bildirim yoğunluğu. Koyu renkler daha fazla bildirimi temsil eder."
            )
          ),
          highcharter::highchartOutput(ns("ha_heatmap_chart"), height = "350px")
        )
      )
    ),
    shiny::fluidRow(
      shiny::column(
        width = 12,
        shiny::div(
          class = "analytics-card",
          shiny::div(
            class = "card-title-row",
            shiny::h4(
              class = "card-title",
              shiny::icon("chart-area"),
              " Öncelik Bazlı Trend (30 Gün)"
            ),
            admin_create_info_button("Son 30 günde her öncelik seviyesindeki hata bildirim trendi.")
          ),
          highcharter::highchartOutput(ns("ha_oncelik_trend_chart"), height = "350px")
        )
      )
    )
  )
}

admin_ha_detay_ui <- function(ns) {
  shiny::tagList(
    shiny::fluidRow(
      shiny::column(
        width = 12,
        shiny::div(
          class = "analytics-card",
          shiny::div(
            class = "card-title-row",
            shiny::h4(
              class = "card-title",
              shiny::icon("table"),
              " Tüm Hata Bildirimleri"
            ),
            admin_create_info_button(
              "Tüm hata bildirimlerinin detaylı listesi. Ek dosyaları görüntülemek için 'Dosyalar' sütunundaki bağlantılara tıklayın."
            )
          ),
          shiny::div(class = "table-container", DT::DTOutput(ns("ha_detay_tablo")))
        )
      )
    ),
    shiny::tags$div(
      id = ns("ek_dosya_modal"),
      class = "modal fade admin-attachment-modal",
      `data-backdrop` = "static",
      `data-keyboard` = "true",
      tabindex = "-1",
      role = "dialog",
      shiny::tags$div(
        class = "modal-dialog",
        role = "document",
        style = "max-width: 90vw; width: 1100px; margin: 30px auto;",
        shiny::tags$div(
          class = "modal-content",
          style = "background: #1a1a1a; border: 1px solid #333; border-radius: 12px;",
          shiny::tags$div(
            class = "modal-header",
            style = "border-bottom: 1px solid #333; padding: 15px 24px;",
            shiny::h4(
              class = "modal-title",
              style = "color: #fff;",
              shiny::icon("paperclip"),
              " Ek Dosyalar"
            ),
            shiny::tags$button(
              type = "button",
              class = "close",
              `data-dismiss` = "modal",
              style = "color: #999; opacity: 0.8;",
              shiny::tags$span(htmltools::HTML("&times;"))
            )
          ),
          shiny::tags$div(
            class = "modal-body",
            style = "padding: 24px; max-height: 85vh; overflow-y: auto;",
            shiny::uiOutput(ns("ek_dosya_content"))
          )
        )
      )
    ),
    shiny::tags$div(
      id = ns("durum_modal"),
      class = "modal fade",
      `data-backdrop` = "static",
      `data-keyboard` = "true",
      tabindex = "-1",
      role = "dialog",
      shiny::tags$div(
        class = "modal-dialog",
        role = "document",
        style = "max-width: 420px;",
        shiny::tags$div(
          class = "modal-content",
          style = "background: #1a1a1a; border: 1px solid #333; border-radius: 12px;",
          shiny::tags$div(
            class = "modal-header",
            style = "border-bottom: 1px solid #333; padding: 15px 20px;",
            shiny::h4(
              class = "modal-title",
              style = "color: #fff;",
              shiny::icon("edit"),
              " Durum Güncelle"
            ),
            shiny::tags$button(
              type = "button",
              class = "close",
              `data-dismiss` = "modal",
              style = "color: #999;",
              shiny::tags$span(htmltools::HTML("&times;"))
            )
          ),
          shiny::tags$div(
            class = "modal-body",
            style = "padding: 24px; min-height: 320px;",
            shiny::tags$input(type = "hidden", id = ns("durum_bildirim_id")),
            shiny::selectInput(
              ns("yeni_durum"),
              "Yeni Durum:",
              choices = c(
                "Açık" = "acik",
                "İncelemede" = "inceleme",
                "Çözüldü" = "cozuldu",
                "Kapandı" = "kapandi",
                "Reddedildi" = "reddedildi"
              ),
              selected = "acik"
            ),
            shiny::actionButton(
              ns("durum_kaydet"),
              "Kaydet",
              class = "btn-modern btn-primary",
              style = "margin-top: 14px;"
            )
          )
        )
      )
    )
  )
}

admin_ha_zaman_ui <- function(ns) {
  shiny::tagList(
    shiny::fluidRow(
      shiny::column(
        width = 12,
        shiny::div(
          class = "analytics-card",
          shiny::div(
            class = "card-title-row",
            shiny::h4(
              class = "card-title",
              shiny::icon("chart-line"),
              " Haftalık Hata Bildirim Trendi (12 Hafta)"
            ),
            admin_create_info_button("Son 12 haftadaki hata bildirim sayıları trendi.")
          ),
          highcharter::highchartOutput(ns("ha_haftalik_trend_chart"), height = "320px")
        )
      )
    ),
    shiny::fluidRow(
      shiny::column(
        width = 6,
        shiny::div(
          class = "analytics-card",
          shiny::div(
            class = "card-title-row",
            shiny::h4(
              class = "card-title",
              shiny::icon("clock"),
              " Saatlere Göre Bildirim Dağılımı"
            ),
            admin_create_info_button("Günün hangi saatlerinde daha fazla hata bildirimi yapıldığı.")
          ),
          highcharter::highchartOutput(ns("ha_saatlik_chart"), height = "320px")
        )
      ),
      shiny::column(
        width = 6,
        shiny::div(
          class = "analytics-card",
          style = "min-height: 400px;",
          shiny::div(
            class = "card-title-row",
            shiny::h4(
              class = "card-title",
              shiny::icon("users"),
              " Kullanıcı Bazlı Bildirimler"
            ),
            admin_create_info_button("En çok hata bildirimi yapan kullanıcılar.")
          ),
          shiny::div(
            class = "table-container scrollable-table-equal",
            DT::DTOutput(ns("ha_kullanici_tablo"))
          )
        )
      )
    )
  )
}
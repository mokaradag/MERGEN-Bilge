# Dosya Yolu: R/helpers_admin_analytics.R
# Açıklama: Yönetici analitik modülleri (Genel Analiz, Geri Bildirim Analizi,
#            Hata Analizi) tarafından paylaşılan yardımcı fonksiyonlar ve sabitler.

# ==============================================================================
# SABİTLER
# ==============================================================================

# Türkçe ay kısaltmaları
admin_turkish_months <- c("Oca", "Şub", "Mar", "Nis", "May", "Haz",
                          "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara")

# Türkçe gün isimleri (Pazartesi'den başlar)
admin_turkish_days <- c("Pazartesi", "Salı", "Çarşamba",
                        "Perşembe", "Cuma", "Cumartesi", "Pazar")

# Modern renk paleti
admin_modern_colors <- list(
  primary = c("#6366f1", "#8b5cf6", "#a855f7", "#d946ef", "#ec4899"),
  success = c("#10b981", "#22c55e", "#84cc16"),
  warning = c("#f59e0b", "#f97316", "#fbbf24"),
  danger  = c("#ef4444", "#f43f5e", "#dc2626"),
  info    = c("#06b6d4", "#0ea5e9", "#3b82f6"),
  neutral = c("#64748b", "#94a3b8", "#cbd5e1")
)

# Türkçe DataTable dil ayarları
admin_turkish_dt_language <- list(
  processing   = "İşleniyor...",
  search       = "Ara:",
  lengthMenu   = "_MENU_ kayıt göster",
  info         = "_TOTAL_ kayıttan _START_ - _END_ arası gösteriliyor",
  infoEmpty    = "Kayıt yok",
  infoFiltered = "(_MAX_ kayıt içinden filtrelendi)",
  infoPostFix  = "",
  loadingRecords = "Yükleniyor...",
  zeroRecords  = "Eşleşen kayıt bulunamadı",
  emptyTable   = "Tabloda veri yok",
  paginate = list(
    first    = "İlk",
    previous = "Önceki",
    `next`   = "Sonraki",
    last     = "Son"
  ),
  aria = list(
    sortAscending  = ": artan sıralama",
    sortDescending = ": azalan sıralama"
  )
)

# DataTable başlık hizalama callback'i (tüm admin tablolarda ortak)
admin_dt_header_callback <- JS(
  "function(thead, data, start, end, display) {",
  "  var api = this.api();",
  "  api.columns().every(function(idx) {",
  "    var col = api.column(idx);",
  "    var th = $(col.header());",
  "    var td = $(col.nodes()).first();",
  "    if (td.hasClass('dt-center')) th.css('text-align', 'center');",
  "    else if (td.hasClass('dt-right')) th.css('text-align', 'right');",
  "    else th.css('text-align', 'left');",
  "    if (idx === 0) { th.css('font-size', '0'); }",
  "  });",
  "}"
)

# ==============================================================================
# YARDIMCI FONKSİYONLAR
# ==============================================================================

#' Güvenli SQL sorgusu çalıştırıcı
#' @param query SQL sorgu metni
#' @return data.frame (hata durumunda boş data.frame)
admin_safe_query <- function(query) {
  tryCatch({
    conn_info <- get_connection()
    on.exit(release_connection(conn_info))
    DBI::dbGetQuery(conn_info$conn, query)
  }, error = function(e) {
    log_error("[ADMIN] SQL Hatası: {conditionMessage(e)}")
    data.frame()
  })
}

#' Türkçe tarih formatlayıcı (ör: "05 Mar")
#' @param date_val Tarih değeri
#' @return Formatlanmış tarih metni
admin_format_turkish_date <- function(date_val) {
  if (is.na(date_val) || is.null(date_val)) return("")
  d <- as.Date(date_val)
  day_num <- format(d, "%d")
  month_num <- as.numeric(format(d, "%m"))
  paste0(day_num, " ", admin_turkish_months[month_num])
}

#' Sayı formatlayıcı (NA/NULL güvenli)
#' @param x Sayısal değer
#' @return Formatlanmış metin
admin_format_number <- function(x) {
  if (is.na(x) || is.null(x)) return("0")
  as.character(as.integer(x))
}

#' Metrik kartı oluşturucu (admin panelinde kullanılan bilgi kartları)
#' @param title Kart başlığı
#' @param value Gösterilecek değer
#' @param icon_name Font Awesome ikon adı
#' @param color_class Renk sınıfı (primary, blue, green, purple, vb.)
#' @param subtitle Alt metin (opsiyonel)
#' @param tooltip Araç ipucu metni (opsiyonel)
admin_create_metric_card <- function(title, value, icon_name, color_class = "primary",
                                     subtitle = NULL, tooltip = NULL) {
  div(
    class = paste("metric-card", color_class),
    `data-toggle` = if (!is.null(tooltip)) "tooltip" else NULL,
    title = tooltip,
    div(class = "metric-icon", icon(icon_name)),
    div(
      class = "metric-content",
      span(class = "metric-value", value),
      span(class = "metric-title", title),
      if (!is.null(subtitle)) span(class = "metric-subtitle", subtitle)
    )
  )
}

#' Bilgi butonu oluşturucu (araç ipucu ile)
#' @param info_text Araç ipucu metni
admin_create_info_button <- function(info_text) {
  tags$span(
    class = "info-btn",
    title = info_text,
    `data-toggle` = "tooltip",
    `data-placement` = "top",
    icon("info-circle")
  )
}

#' Highcharter araç ipucu teması (koyu tema)
#' @return Araç ipucu ayarları listesi
admin_hc_tooltip_theme <- function() {
  list(
    backgroundColor = "#1a1a1a",
    borderColor = "#333",
    style = list(color = "#fff")
  )
}

#' Standart admin analitik sayfa düzeni oluşturucu (üst başlık + sekmeler + kaydırılabilir içerik)
#' @param ns Modül namespace fonksiyonu
#' @param page_title Sayfa başlığı
#' @param page_icon Başlık ikonu
#' @param refresh_btn_id Yenile butonu input ID
#' @param last_update_id Son güncelleme span ID
#' @param tabs_id Sekme paneli input ID
#' @param tab_panels tabPanel listesi
#' @param content_output_id İçerik alanı uiOutput ID
admin_page_layout <- function(ns, page_title, page_icon = "chart-bar",
                              refresh_btn_id = "refresh_analytics",
                              last_update_id = "admin_last_update",
                              tabs_id = "admin_tabs",
                              tab_panels = list(),
                              content_output_id = "tab_content_area") {
  tagList(
    tags$head(
      tags$link(rel = "stylesheet", type = "text/css", href = "css/admin_analytics.css"),
      tags$link(rel = "stylesheet", type = "text/css", href = "css/admin_destek_analytics.css"),
      tags$style(HTML("
        .admin-analytics-container {
          height: 100vh;
          display: flex;
          flex-direction: column;
          overflow: hidden;
          position: relative;
        }
        .admin-tabs-container .tab-content {
          display: none !important;
        }
        .admin-header-fixed {
          position: relative;
          z-index: 1000;
          background: var(--background-light, #2a2a2a);
          flex-shrink: 0;
          border-radius: 0 16px 16px 0;
          height: 50px;
          min-height: 50px;
          box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
        }
        .admin-scrollable-content {
          flex: 1;
          overflow-y: auto;
          padding: 20px 25px 40px 25px;
        }
        .equal-height-row {
          display: flex;
          flex-wrap: wrap;
        }
        .equal-height-row > [class*='col-'] {
          display: flex;
          flex-direction: column;
        }
        .equal-height-row .analytics-card {
          flex: 1;
          display: flex;
          flex-direction: column;
        }
        .equal-height-row .analytics-card .table-container {
          flex: 1;
          display: flex;
          flex-direction: column;
        }
        .scrollable-table-equal {
          flex: 1;
          overflow-y: auto;
          max-height: 320px;
        }
        .metrics-grid-3 {
          display: grid;
          grid-template-columns: repeat(3, 1fr);
          gap: 20px;
          margin-bottom: 20px;
        }
        .metrics-grid-5 {
          display: grid;
          grid-template-columns: repeat(5, 1fr);
          gap: 20px;
          margin-bottom: 20px;
        }
        @media (max-width: 1200px) {
          .metrics-grid-5 { grid-template-columns: repeat(3, 1fr); }
        }
        @media (max-width: 992px) {
          .metrics-grid-3 { grid-template-columns: repeat(2, 1fr); }
          .metrics-grid-5 { grid-template-columns: repeat(2, 1fr); }
        }
        @media (max-width: 576px) {
          .metrics-grid-3, .metrics-grid-5 { grid-template-columns: 1fr; }
        }
      "))
    ),
    div(
      class = "admin-analytics-container",
      div(
        class = "admin-header-fixed",
        div(
          class = "chat-header settings-header-fixed",
          div(
            class = "chat-header-left",
            h4(page_title, class = "page-title"),
            span(class = "admin-badge", icon("shield-alt"), "ADMIN")
          ),
          div(
            class = "chat-header-right",
            span(
              id = ns(last_update_id),
              style = "color: #999; margin-right: 15px; font-size: 14px;",
              "Son Güncelleme: --"
            ),
            actionButton(
              ns(refresh_btn_id),
              label = tagList(icon("sync-alt"), "Yenile"),
              class = "btn-modern btn-primary"
            )
          )
        )
      ),
      div(
        class = "admin-tabs-sticky-wrapper",
        div(
          class = "admin-tabs-container",
          do.call(tabsetPanel, c(
            list(id = ns(tabs_id), type = "pills"),
            tab_panels
          ))
        )
      ),
      div(
        class = "admin-scrollable-content",
        uiOutput(ns(content_output_id))
      )
    )
  )
}

#' Standart admin modül sunucu altyapısı (otomatik yenileme + manuel yenileme)
#' @param input Shiny input
#' @param session Shiny session
#' @param refresh_btn_id Yenile butonu ID
#' @param last_update_id Son güncelleme span ID
#' @param refresh_interval_ms Otomatik yenileme aralığı (ms)
#' @return Liste: refresh_trigger (reactiveVal), last_update (reactiveVal)
admin_refresh_setup <- function(input, session, refresh_btn_id = "refresh_analytics",
                                last_update_id = "admin_last_update",
                                refresh_interval_ms = 600000) {
  ns <- session$ns
  refresh_trigger <- reactiveVal(0)
  last_update <- reactiveVal(format(Sys.time(), "%d.%m.%Y %H:%M:%S"))

  # Otomatik yenileme (varsayılan: 10 dakika)
  observe({
    invalidateLater(refresh_interval_ms)
    isolate({
      refresh_trigger(refresh_trigger() + 1)
      last_update(format(Sys.time(), "%d.%m.%Y %H:%M:%S"))
      session$sendCustomMessage("updateAdminTimestamp", list(
        id = ns(last_update_id),
        time = last_update()
      ))
    })
  })

  # Manuel yenileme butonu
  observeEvent(input[[refresh_btn_id]], {
    shinyjs::runjs("$('.tooltip').remove();")
    refresh_trigger(refresh_trigger() + 1)
    last_update(format(Sys.time(), "%d.%m.%Y %H:%M:%S"))
    session$sendCustomMessage("updateAdminTimestamp", list(
      id = ns(last_update_id),
      time = last_update()
    ))
    showToast(session, "Veriler güncellendi", "success")
  })

  list(
    trigger = refresh_trigger,
    last_update = last_update
  )
}

#' Bootstrap tooltip'lerini yeniden başlat (sekme değişikliğinden sonra)
#' @param session Shiny session
admin_init_tooltips <- function(session) {
  shinyjs::delay(100, {
    shinyjs::runjs("$('.admin-scrollable-content [data-toggle=\"tooltip\"]').tooltip({container: 'body', trigger: 'hover', delay: {show: 100, hide: 300}});")
  })
}

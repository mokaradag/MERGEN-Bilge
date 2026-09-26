# ==============================================================================
# Dosya Yolu: R/module_health_worker_metrics.R
# Açıklama: Sağlık ekranındaki işçi havuzu kartı için biçimlendirme yardımcıları.
# ==============================================================================

render_worker_health_html <- function(worker_info) {
  # Renkler tema CSS'inde (www/css/health_dashboard.css); satır içi beyaz yazı
  # açık temada okunmuyordu. İş türü adları kaçırılarak yazılır.
  kacis <- function(x) htmltools::htmlEscape(as.character(x %||% ""))
  breakdown <- worker_info$task_type_breakdown %||% list()

  breakdown_text <- if (length(breakdown) > 0) {
    paste(
      vapply(names(breakdown), function(nm) {
        paste0(kacis(nm), ": ", kacis(breakdown[[nm]]))
      }, character(1)),
      collapse = "<br>"
    )
  } else {
    "Aktif asenkron iş yok"
  }

  # Eksik ya da NA sayaç satırı düşürmez ve "NA" yazmaz; "—" gösterilir.
  sayi <- function(x, bicim = "%d", donustur = as.integer) {
    v <- suppressWarnings(donustur(x %||% NA)[1])
    if (length(v) == 1L && !is.na(v)) sprintf(bicim, v) else "\u2014"
  }

  satir <- function(etiket, deger) {
    sprintf('<span class="health-worker-stat-label">%s</span> <span class="health-worker-stat-value">%s</span><br>',
            etiket, deger)
  }

  HTML(paste0(
    '<div class="health-worker-stats">',
    satir("Toplam İşçi:", sayi(worker_info$total_workers)),
    satir("Boş İşçi:", sayi(worker_info$free_workers)),
    satir("Aktif İşçi:", sayi(worker_info$active_workers)),
    satir("Aktif İş:", sayi(worker_info$active_jobs)),
    satir("Kuyruktaki İş:", sayi(worker_info$queued_jobs)),
    satir("Kullanım Oranı:", sayi(worker_info$usage_pct, "%.1f%%", as.numeric)),
    '<br><span class="health-worker-types-title">İş Türleri:</span><br>',
    '<span class="health-worker-types">', breakdown_text, '</span><br><br>',
    '<span class="health-worker-note">', kacis(worker_info$note), '</span>',
    '</div>'
  ))
}

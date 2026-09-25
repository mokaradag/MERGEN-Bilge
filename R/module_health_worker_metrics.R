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

  satir <- function(etiket, deger) {
    sprintf('<span class="health-worker-stat-label">%s</span> <span class="health-worker-stat-value">%s</span><br>',
            etiket, deger)
  }

  HTML(paste0(
    '<div class="health-worker-stats">',
    satir("Toplam İşçi:", sprintf("%d", as.integer(worker_info$total_workers))),
    satir("Boş İşçi:", sprintf("%d", as.integer(worker_info$free_workers))),
    satir("Aktif İşçi:", sprintf("%d", as.integer(worker_info$active_workers))),
    satir("Aktif İş:", sprintf("%d", as.integer(worker_info$active_jobs))),
    satir("Kuyruktaki İş:", sprintf("%d", as.integer(worker_info$queued_jobs))),
    satir("Kullanım Oranı:", sprintf("%.1f%%", as.numeric(worker_info$usage_pct))),
    '<br><span class="health-worker-types-title">İş Türleri:</span><br>',
    '<span class="health-worker-types">', breakdown_text, '</span><br><br>',
    '<span class="health-worker-note">', kacis(worker_info$note), '</span>',
    '</div>'
  ))
}

# ==============================================================================
# Dosya Yolu: R/module_health_worker_metrics.R
# Açıklama: Sağlık ekranındaki işçi havuzu kartı için biçimlendirme yardımcıları.
# ==============================================================================

render_worker_health_html <- function(worker_info) {
  breakdown <- worker_info$task_type_breakdown %||% list()

  breakdown_text <- if (length(breakdown) > 0) {
    paste(
      vapply(names(breakdown), function(nm) {
        paste0(nm, ": ", breakdown[[nm]])
      }, character(1)),
      collapse = "<br>"
    )
  } else {
    "Aktif asenkron iş yok"
  }

  HTML(sprintf(
    '<div style="line-height: 2;">
      <span style="color: #60a5fa;">Toplam İşçi:</span> <span style="color: #fff;">%d</span><br>
      <span style="color: #60a5fa;">Boş İşçi:</span> <span style="color: #fff;">%d</span><br>
      <span style="color: #60a5fa;">Aktif İşçi:</span> <span style="color: #fff;">%d</span><br>
      <span style="color: #60a5fa;">Aktif İş:</span> <span style="color: #fff;">%d</span><br>
      <span style="color: #60a5fa;">Kuyruktaki İş:</span> <span style="color: #fff;">%d</span><br>
      <span style="color: #60a5fa;">Kullanım Oranı:</span> <span style="color: #fff;">%.1f%%</span><br><br>

      <span style="color: #a78bfa; font-weight: bold;">İş Türleri:</span><br>
      <span style="color: #fff; margin-left: 10px;">%s</span><br><br>

      <span style="color: #94a3b8;">%s</span>
    </div>',
    worker_info$total_workers,
    worker_info$free_workers,
    worker_info$active_workers,
    worker_info$active_jobs,
    worker_info$queued_jobs,
    worker_info$usage_pct,
    breakdown_text,
    worker_info$note
  ))
}
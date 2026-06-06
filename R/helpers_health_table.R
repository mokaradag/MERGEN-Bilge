# ==============================================================================
# Dosya Yolu: R/helpers_health_table.R
# Açıklama: Sistem Durumu paneli için kontrol sonuçları tablosunu oluşturan
#           HTML yardımcılarını içerir. Temel durum, güvenli metin ve yol
#           biçimlendirme yardımcıları R/helpers_health_formatters.R içinde
#           tutulur; bu dosya maintainability fonksiyon sayacını düşük tutmak
#           için tablo render sorumluluğunu ayırır.
# ==============================================================================

health_checks_table <- function(checks, max_height = 420) {
  if (is.null(checks) || !nrow(checks)) {
    return(div(class = "health-empty", "Gösterilecek kontrol sonucu yok."))
  }

  rows <- lapply(seq_len(nrow(checks)), function(i) {
    row <- checks[i, ]

    tags$tr(
      tags$td(health_status_pill(row$status)),
      tags$td(
        strong(health_escape(row$label)),
        tags$div(class = "health-check-id", health_escape(row$id))
      ),
      tags$td(health_render_value(row$value, row$id)),
      tags$td(health_escape(row$detail)),
      tags$td(ifelse(is.na(row$duration_ms), "—", paste0(row$duration_ms, " ms"))),
      tags$td(health_escape(row$checked_at)),
      tags$td(health_escape(row$remediation))
    )
  })

  div(
    class = "health-table-wrap",
    style = paste0("max-height:", as.integer(max_height), "px;"),
    `data-health-tooltip` = "Tablo başlığı sabittir; çok satırlı sonuçlarda tablo içinde kaydırma yapılır.",
    tags$table(
      class = "health-table",
      tags$thead(tags$tr(
        tags$th("Durum"),
        tags$th("Kontrol"),
        tags$th("Değer"),
        tags$th("Detay"),
        tags$th("Süre"),
        tags$th("Zaman"),
        tags$th("Öneri")
      )),
      tags$tbody(rows)
    )
  )
}
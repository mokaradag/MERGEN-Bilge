# ==============================================================================
# Dosya Yolu: R/module_health_diagnostics.R
# Açıklama: Sistem Durumu panelinin Tanılama sekmesi için detaylı tablo ve
#            iyileştirme önerisi UI yardımcılarını içerir.
# ==============================================================================

health_diagnostics_ui <- function(checks) {
  ordered <- checks[order(-checks$severity, checks$id), , drop = FALSE]
  warnings <- ordered[ordered$status %in% c("critical", "warning", "unknown"), , drop = FALSE]
  tagList(
    fluidRow(
      column(
        12,
        health_section_card(
          "Uyarılar ve İyileştirme Önerileri",
          "tools",
          if (nrow(warnings)) health_checks_table(warnings) else div(class = "health-empty", "Aktif kritik uyarı yok.")
        )
      )
    ),
    health_section_card("Tüm Kontrol Sonuçları", "clipboard-list", health_checks_table(ordered))
  )
}

# Dosya Yolu: R/module_admin_geri_bildirim.R
# Açıklama: Yönetici paneli - Geri Bildirim Analizi modülü.
#            MB_Destek_Geri_Bildirim tablosundaki kullanıcı geri bildirimlerini
#            çok boyutlu olarak analiz eder. Memnuniyet, NPS, etiket ve içerik
#            analizleri için gelişmiş grafikler ve tablolar sunar.

# ==============================================================================
# SERVER FONKSİYONU
# ==============================================================================

adminGeriBildirimServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Yenileme altyapısı (paylaşılan yardımcı)
    refresh <- admin_refresh_setup(input, session)

    # ============================================================
    # VERİ ÇEKİMİ
    # ============================================================
    gb_data <- reactive({
      refresh$trigger()
      admin_gb_fetch_data()
    })

    # ============================================================
    # ETİKET ÇÖZÜMLEME (virgülle ayrılmış etiketleri sayma)
    # ============================================================
    etiket_sayilari <- reactive({
      ham <- gb_data()$etiketler_ham
      admin_gb_count_tags(ham)
    })

    # ============================================================
    # SEKME İÇERİĞİ YÖNLENDİRİCİ
    # ============================================================
    output$tab_content_area <- renderUI({
      tab <- input$admin_tabs
      if (is.null(tab)) tab <- "gb_overview"

      admin_init_tooltips(session)

      admin_gb_tab_ui(
        tab = tab,
        ns = ns,
        data_provider = gb_data
      )
    })

    # Grafik ve tablo çıktı renderer'ları bakım bütçesi için ayrı dosyada:
    # R/module_admin_geri_bildirim_outputs.R -> admin_gb_outputs()
    admin_gb_outputs(output = output, gb_data = gb_data, etiket_sayilari = etiket_sayilari)

  })
}
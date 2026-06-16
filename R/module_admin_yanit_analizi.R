# Dosya Yolu: R/module_admin_yanit_analizi.R
# Açıklama: Yönetici paneli - Yanıt Geri Bildirimi Analizi modülü.
#            MB_Feedback tablosundaki kullanıcıların yapay zekâ yanıtlarına verdikleri
#            beğeni/beğenmeme geri bildirimlerini çok boyutlu olarak analiz eder.
#            Model performansı, kullanıcı davranışları, etiket analizi ve zaman bazlı
#            trendler için gelişmiş grafikler ve tablolar sunar.

# ==============================================================================
# UI FONKSİYONU
# ==============================================================================

adminYanitAnaliziUI <- function(id) {
  ns <- NS(id)

  admin_page_layout(
    ns = ns,
    page_title = "Yanıt Geri Bildirimi Analizi",
    page_icon = "thumbs-up",
    tab_panels = list(
      tabPanel(
        title = tags$span(
          title = "Genel geri bildirim metrikleri ve özet göstergeler",
          tagList(icon("chart-line"), " Genel Bakış")
        ),
        value = "ya_overview"
      ),
      tabPanel(
        title = tags$span(
          title = "Model bazlı performans karşılaştırması ve analiz",
          tagList(icon("robot"), " Model Performansı")
        ),
        value = "ya_model"
      ),
      tabPanel(
        title = tags$span(
          title = "Etiket dağılımı ve kullanıcı yorumları detaylı analiz",
          tagList(icon("tags"), " Etiket & Yorum Analizi")
        ),
        value = "ya_etiket"
      ),
      tabPanel(
        title = tags$span(
          title = "Zamana göre geri bildirim trendleri ve kullanıcı davranışları",
          tagList(icon("clock"), " Zaman & Kullanıcı Analizi")
        ),
        value = "ya_zaman"
      )
    )
  )
}

# ==============================================================================
# SERVER FONKSİYONU
# ==============================================================================

adminYanitAnaliziServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Yenileme altyapısı (paylaşılan yardımcı)
    refresh <- admin_refresh_setup(input, session)

    # ============================================================
    # VERİ ÇEKİMİ
    # ============================================================
    ya_data <- reactive({
      refresh$trigger()
      admin_yanit_collect_data(admin_safe_query)
    })

    # ============================================================
    # ETİKET ÇÖZÜMLEME
    # ============================================================
    etiket_sayilari <- reactive({
      admin_yanit_tag_counts(ya_data()$etiketler_ham)
    })

    # ============================================================
    # SEKME İÇERİĞİ YÖNLENDİRİCİ
    # ============================================================
    output$tab_content_area <- renderUI({
      tab <- input$admin_tabs
      if (is.null(tab)) tab <- "ya_overview"

      admin_init_tooltips(session)

      switch(tab,
        "ya_overview" = admin_yanit_overview_ui(ya_data(), ns),
        "ya_model"    = admin_yanit_model_ui(ns),
        "ya_etiket"   = admin_yanit_etiket_ui(ns),
        "ya_zaman"    = admin_yanit_zaman_ui(ns),
        admin_yanit_overview_ui(ya_data(), ns)
      )
    })

    # Grafik ve tablo çıktı renderer'ları bakım bütçesi için ayrı dosyada:
    # R/module_admin_yanit_analizi_outputs.R -> admin_yanit_outputs()
    admin_yanit_outputs(
      output = output,
      ya_data = ya_data,
      etiket_sayilari = etiket_sayilari,
      refresh = refresh
    )

  })
}
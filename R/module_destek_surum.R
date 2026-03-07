# R/module_destek_surum.R
# Dosya Yolu: R/module_destek_surum.R
# Açıklama: Sürüm bilgilendirme alt sayfası modülü.
#            Uygulama sürüm geçmişi, güncelleme detayları ve
#            değişiklik kayıtlarını gösterir.

# ==============================================================================
# SÜRÜM BİLGİLENDİRME UI
# ==============================================================================

destekSurumUI <- function(id) {
  ns <- NS(id)
  tagList(
    div(
      class = "destek-surum-container",

      # Hero Bölümü
      div(
        class = "destek-surum-hero",
        div(class = "destek-surum-hero-bg"),
        div(
          class = "destek-surum-hero-content",
          div(class = "destek-surum-hero-icon",
            icon("rocket")
          ),
          h2(class = "destek-surum-title",
            "Sürüm Bilgilendirme"
          ),
          p(class = "destek-surum-subtitle",
            "MERGEN Bilge'nin gelişim yolculuğu ve güncelleme detayları"
          )
        )
      ),

      # Sürüm seçici sekmeler
      div(
        class = "destek-surum-tabs",
        id = ns("version_tabs")
      ),

      # Sürüm içerik alanı
      div(
        class = "destek-surum-content",
        id = ns("version_content")
      )
    )
  )
}

# ==============================================================================
# SÜRÜM BİLGİLENDİRME SERVER
# ==============================================================================

destekSurumServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Sürüm verilerini yükle ve istemciye gönder
    observe({
      version_data <- get_version_history()
      if (is.null(version_data)) return()

      session$sendCustomMessage("initSurumPage", list(
        versions = version_data$versions,
        current_version = version_data$current_version,
        tabsId = ns("version_tabs"),
        contentId = ns("version_content")
      ))
    }) |> bindEvent(TRUE, once = TRUE)

    invisible(NULL)
  })
}
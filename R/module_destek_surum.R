# R/module_destek_surum.R
# Dosya Yolu: R/module_destek_surum.R
# Aciklama: Surum bilgilendirme alt sayfasi modulu.
#            Uygulama surum gecmisi, guncelleme detaylari ve
#            degisiklik kayitlarini gosterir.

# ==============================================================================
# SURUM BILGILENDIRME UI
# ==============================================================================

destekSurumUI <- function(id) {
  ns <- NS(id)
  tagList(
    div(
      class = "destek-surum-container",

      # Hero Bolumu
      div(
        class = "destek-surum-hero",
        div(class = "destek-surum-hero-bg"),
        div(
          class = "destek-surum-hero-content",
          div(class = "destek-surum-hero-icon",
            icon("rocket")
          ),
          h2(class = "destek-surum-title",
            "Surum Bilgilendirme"
          ),
          p(class = "destek-surum-subtitle",
            "MERGEN Bilge'nin gelisim yolculugu ve guncelleme detaylari"
          )
        )
      ),

      # Surum secici sekmeler
      div(
        class = "destek-surum-tabs",
        id = ns("version_tabs")
      ),

      # Surum icerik alani
      div(
        class = "destek-surum-content",
        id = ns("version_content")
      )
    )
  )
}

# ==============================================================================
# SURUM BILGILENDIRME SERVER
# ==============================================================================

destekSurumServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Surum verilerini yukle ve istemciye gonder
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

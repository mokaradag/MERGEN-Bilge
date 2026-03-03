# Dosya Yolu: R/module_destek.R
# Açıklama: Destek sayfası ana koordinatör modülü.
#            Alt sayfalar (Yardım Merkezi, Geri Bildirim & Hata, Hakkında)
#            arasındaki gezinmeyi ve veri akışını yönetir.

# ==============================================================================
# DESTEK ANA UI
# ==============================================================================

destekUI <- function(id) {
  ns <- NS(id)
  tagList(
    div(
      class = "destek-container",
      # Sayfa başlığı (MERGEN Bilge standart header)
      fluidRow(
        column(
          width = 12,
          div(
            class = "chat-header settings-header-fixed",
            div(
              class = "chat-header-left",
              h4("Destek", class = "page-title"),
              span(class = "destek-badge",
                icon("life-ring"), "DESTEK"
              )
            ),
            div(
              class = "chat-header-right",
              span(
                class = "destek-version-info",
                "MERGEN Bilge v0.9"
              )
            )
          )
        )
      ),
      # Ana içerik alanı: Sol gezinme + Sağ içerik
      div(
        class = "destek-layout",
        # Sol gezinme paneli
        div(
          class = "destek-sidebar",
          div(
            class = "destek-sidebar-section",
            h5(class = "destek-sidebar-title", "Destek"),
            div(
              class = "destek-nav-item active",
              id = ns("nav_yardim"),
              onclick = sprintf("Shiny.setInputValue('%s', 'yardim', {priority: 'event'})", ns("destek_sayfa")),
              icon("circle-question"),
              span("Yardım Merkezi")
            ),
            div(
              class = "destek-nav-item",
              id = ns("nav_geri_bildirim"),
              onclick = sprintf("Shiny.setInputValue('%s', 'geri_bildirim', {priority: 'event'})", ns("destek_sayfa")),
              icon("comment-dots"),
              span("Geri Bildirim & Hata")
            ),
            div(
              class = "destek-nav-item",
              id = ns("nav_hakkinda"),
              onclick = sprintf("Shiny.setInputValue('%s', 'hakkinda', {priority: 'event'})", ns("destek_sayfa")),
              icon("info-circle"),
              span(HTML("Hakk\u0131nda"))
            )
          )
        ),
        # Sağ içerik alanı
        div(
          class = "destek-content",
          # Yardım Merkezi
          div(
            id = ns("sayfa_yardim"),
            class = "destek-page active",
            destekYardimUI(ns("yardim_module"))
          ),
          # Geri Bildirim & Hata Bildirimi
          div(
            id = ns("sayfa_geri_bildirim"),
            class = "destek-page",
            style = "display: none;",
            destekGeriBildirimUI(ns("geri_bildirim_module")),
          ),
          # Hakkında
          div(
            id = ns("sayfa_hakkinda"),
            class = "destek-page",
            style = "display: none;",
            destekHakkindaUI(ns("hakkinda_module"))
          )
        )
      )
    )
  )
}

# ==============================================================================
# DESTEK ANA SERVER
# ==============================================================================

destekServer <- function(id, current_user_id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Alt modül sunucularını başlat
    destekYardimServer("yardim_module")
    destekGeriBildirimServer("geri_bildirim_module", current_user_id = current_user_id)
    destekHakkindaServer("hakkinda_module")

    # Sayfa gezinme gözlemcisi
    observeEvent(input$destek_sayfa, {
      sayfa <- input$destek_sayfa

      # Tüm sayfaları gizle, seçili sayfayı göster
      sayfalar <- c("yardim", "geri_bildirim", "hakkinda")
      for (s in sayfalar) {
        shinyjs::hide(paste0("sayfa_", s))
        shinyjs::runjs(sprintf(
          "document.getElementById('%s').classList.remove('active');",
          ns(paste0("nav_", s))
        ))
      }

      shinyjs::show(paste0("sayfa_", sayfa))
      shinyjs::runjs(sprintf(
        "document.getElementById('%s').classList.add('active');",
        ns(paste0("nav_", sayfa))
      ))
    }, ignoreInit = TRUE)

    invisible(NULL)
  })
}

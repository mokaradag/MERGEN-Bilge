# Dosya Yolu: R/module_destek.R
# Açıklama: Destek sayfası ana koordinatör modülü.
#            Alt sayfalar (Yardım Merkezi, Geri Bildirim & Hata, Hakkında)
#            ana sidebar'daki menuSubItem'lar üzerinden yönetilir.

# ==============================================================================
# DESTEK ANA UI
# ==============================================================================

destekUI <- function(id, sayfa = "yardim") {
  ns <- NS(id)

  # Sayfa başlığını belirle
  baslik <- switch(sayfa,
    "yardim" = "Yardım Merkezi",
    "geri_bildirim" = "Geri Bildirim & Hata",
    "hakkinda" = "Hakkında",
    "Destek"
  )

  baslik_ikon <- switch(sayfa,
    "yardim" = "circle-question",
    "geri_bildirim" = "comment-dots",
    "hakkinda" = "info-circle",
    "life-ring"
  )

  tagList(
    div(
      class = "destek-container",
      # Sayfa başlığı (Sade başlık - sürüm bilgisi olmadan)
      fluidRow(
        column(
          width = 12,
          div(
            class = "chat-header settings-header-fixed",
            div(
              class = "chat-header-left",
              h4(baslik, class = "page-title"),
              span(class = "destek-badge",
                icon(baslik_ikon), "DESTEK"
              )
            )
          )
        )
      ),
      # İçerik alanı (tam genişlik, sidebar yok)
      div(
        class = "destek-content-full",
        if (sayfa == "yardim") {
          div(class = "destek-page", destekYardimUI(ns("yardim_module")))
        } else if (sayfa == "geri_bildirim") {
          div(class = "destek-page", destekGeriBildirimUI(ns("geri_bildirim_module")))
        } else if (sayfa == "hakkinda") {
          div(class = "destek-page", destekHakkindaUI(ns("hakkinda_module")))
        }
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
    destekYardimServer("yardim_module", current_user_id = current_user_id)
    destekGeriBildirimServer("geri_bildirim_module", current_user_id = current_user_id)
    destekHakkindaServer("hakkinda_module")

    invisible(NULL)
  })
}
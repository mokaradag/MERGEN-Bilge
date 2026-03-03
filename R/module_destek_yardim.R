# Dosya Yolu: R/module_destek_yardim.R
# Açıklama: Yardım Merkezi alt sayfası modülü.
#            E-posta ve telefon destek bilgilerini gösterir.

# ==============================================================================
# YARDIM MERKEZİ UI
# ==============================================================================

destekYardimUI <- function(id) {
  ns <- NS(id)
  tagList(
    div(
      class = "destek-yardim-container",
      # Başlık ve giriş
      div(
        class = "destek-section-header",
        div(class = "destek-section-icon destek-icon-pulse",
          icon("circle-question")
        ),
        h3(HTML("Yard\u0131m Merkezi")),
        p(
          class = "destek-section-desc",
          HTML("Herhangi bir sorunuz veya yard\u0131ma ihtiyac\u0131n\u0131z oldu\u011funda a\u015fa\u011f\u0131daki kanallardan bize ula\u015fabilirsiniz.")
        )
      ),
      # İletişim kartları
      div(
        class = "destek-contact-grid",
        # E-posta kartı
        div(
          class = "destek-contact-card",
          div(class = "destek-contact-icon destek-icon-float",
            icon("envelope")
          ),
          h4("E-posta Destek"),
          p(class = "destek-contact-desc",
            HTML("Sorular\u0131n\u0131z\u0131 ve taleplerinizi e-posta ile iletebilirsiniz. En k\u0131sa s\u00fcrede d\u00f6n\u00fc\u015f sa\u011flanacakt\u0131r.")
          ),
          tags$a(
            href = "mailto:destek@mergen.ai",
            class = "destek-contact-link",
            icon("arrow-right"),
            "destek@mergen.ai"
          )
        ),
        # Telefon kartı
        div(
          class = "destek-contact-card",
          div(class = "destek-contact-icon destek-icon-rotate",
            icon("phone")
          ),
          h4("Telefon Destek"),
          p(class = "destek-contact-desc",
            HTML("Acil durumlar ve h\u0131zl\u0131 destek i\u00e7in telefon hatt\u0131m\u0131zdan bize ula\u015fabilirsiniz.")
          ),
          tags$a(
            href = "tel:+908501234567",
            class = "destek-contact-link",
            icon("arrow-right"),
            "+90 850 123 45 67"
          )
        )
      )
    )
  )
}

# ==============================================================================
# YARDIM MERKEZİ SERVER
# ==============================================================================

destekYardimServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    # Yardım merkezi sayfası statik içerik, sunucu mantığı gerekmez
    invisible(NULL)
  })
}

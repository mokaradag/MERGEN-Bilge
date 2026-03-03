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
        h3(HTML("Yardım Merkezi")),
        p(
          class = "destek-section-desc",
          HTML("Herhangi bir sorunuz veya yardıma ihtiyacınız olduğunda aşağıdaki kanallardan bize ulaşabilirsiniz.")
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
            HTML("Sorularınızı ve taleplerinizi e-posta ile iletebilirsiniz. En kısa sürede dönüş sağlanacaktır.")
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
            HTML("Acil durumlar ve hızlı destek için telefon hattımızdan bize ulaşabilirsiniz.")
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
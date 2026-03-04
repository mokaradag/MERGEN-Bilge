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
          HTML("Size nas\u0131l yard\u0131mc\u0131 olabiliriz? \u0130leti\u015fim kanallar\u0131m\u0131zdan bize 7/24 ula\u015fabilirsiniz.")
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
          h4(class = "destek-email-title", "E-posta Destek"),
          p(class = "destek-contact-desc",
            HTML("Her t\u00fcrl\u00fc sorunuz, \u00f6neriniz veya \u015fikayetiniz i\u00e7in bize e-posta g\u00f6nderebilirsiniz. Ekibimiz en k\u0131sa s\u00fcrede d\u00f6n\u00fc\u015f yapacakt\u0131r.")
          ),
          tags$a(
            href = paste0(
              "mailto:destek@mergen.ai",
              "?subject=", utils::URLencode("MERGEN Bilge - Destek Talebi"),
              "&body=", utils::URLencode(paste0(
                "Say\u0131n MERGEN Bilge Destek Ekibi,\n\n",
                "A\u015fa\u011f\u0131daki konu hakk\u0131nda deste\u011finize ihtiyac\u0131m bulunmaktad\u0131r:\n\n",
                "Konu: \n",
                "A\u00e7\u0131klama: \n\n",
                "Bilgilerinize sayg\u0131yla arz ederim.\n\n",
                "Kullan\u0131c\u0131 Bilgileri:\n",
                "Uygulama: MERGEN Bilge v0.9\n",
                "Tarih: ", format(Sys.Date(), "%d.%m.%Y")
              ))
            ),
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
          h4(class = "destek-phone-title", "Telefon Destek"),
          p(class = "destek-contact-desc",
            HTML("Acil durumlar ve an\u0131nda destek gerektiren konular i\u00e7in m\u00fc\u015fteri hizmetlerimizi arayabilirsiniz.")
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
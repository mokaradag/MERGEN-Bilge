# Dosya Yolu: R/module_destek_hakkinda.R
# Açıklama: Hakkında alt sayfası modülü.
#            MERGEN Bilge uygulamasının detaylı tanıtımı, sayfa açıklamaları
#            ve kullanıcı rehberliği içeriğini sunar.

# ==============================================================================
# HAKKINDA UI
# ==============================================================================

destekHakkindaUI <- function(id) {
  ns <- NS(id)
  tagList(
    div(
      class = "destek-hakkinda-container",

      # Hero Bölümü
      div(
        class = "destek-hakkinda-hero",
        div(class = "destek-hakkinda-hero-bg"),
        div(
          class = "destek-hakkinda-hero-content",
          div(class = "destek-hakkinda-hero-icon destek-icon-sparkle",
            icon("wand-magic-sparkles")
          ),
          h2(class = "destek-hakkinda-title",
            HTML("MERGEN Bilge ile Tan\u0131\u015f\u0131n")
          ),
          p(class = "destek-hakkinda-subtitle",
            HTML("T\u00fcrk ve Altay mitolojisinden esinlenen, kurumsal ortamlar i\u00e7in tasarlanm\u0131\u015f gelişmiş yapay zeka asistan\u0131n\u0131z.")
          )
        )
      ),

      # Özellik Kartları Izgarası
      div(
        class = "destek-hakkinda-features",
        h3(class = "destek-hakkinda-section-title",
          HTML("Temel \u00d6zellikler")
        ),
        div(
          class = "destek-features-grid",
          # Kart 1: Akıllı Sohbet
          div(
            class = "destek-feature-card destek-feature-amber",
            div(class = "destek-feature-icon",
              icon("bolt")
            ),
            h4(HTML("Ak\u0131ll\u0131 Sohbet")),
            p(HTML("Do\u011fal dilde soru sorma, analiz isteme ve fikir al\u0131\u015fveri\u015fi. Ger\u00e7ek zamanl\u0131 ak\u0131\u015f (streaming) ile h\u0131zl\u0131 yan\u0131tlar, kod vurgulama ve takip sorular\u0131 deste\u011fi."))
          ),
          # Kart 2: Güvenlik
          div(
            class = "destek-feature-card destek-feature-emerald",
            div(class = "destek-feature-icon",
              icon("shield-halved")
            ),
            h4(HTML("\u00dcst\u00fcn G\u00fcvenlik")),
            p(HTML("T\u00fcm sohbetler kullan\u0131c\u0131 baz\u0131nda ayr\u0131 tutulur. API anahtarlar\u0131 \u015fifrelenerek saklan\u0131r. Oturum zaman a\u015f\u0131m\u0131 ile g\u00fcvenlik sa\u011flan\u0131r."))
          ),
          # Kart 3: Dosya Analizi
          div(
            class = "destek-feature-card destek-feature-blue",
            div(class = "destek-feature-icon",
              icon("microchip")
            ),
            h4(HTML("Ak\u0131ll\u0131 Dosya Analizi")),
            p(HTML("Excel, PDF, Word, RData ve daha birçok format desteklenir. MCP araçlar\u0131yla derinlemesine analiz, özetleme ve veri işleme yetenekleri."))
          ),
          # Kart 4: Çoklu Karakter
          div(
            class = "destek-feature-card destek-feature-purple",
            div(class = "destek-feature-icon",
              icon("globe")
            ),
            h4("5 Benzersiz Karakter"),
            p(HTML("T\u00fcrk ve Altay mitolojisinden esinlenen 5 farkl\u0131 karakter. Her biri farkl\u0131 uzmanl\u0131k alan\u0131 ve ileti\u015fim tarz\u0131na sahip."))
          )
        )
      ),

      # Sayfa Rehberi
      div(
        class = "destek-hakkinda-guide",
        h3(class = "destek-hakkinda-section-title", "Sayfa Rehberi"),
        p(class = "destek-hakkinda-guide-intro",
          HTML("MERGEN Bilge'nin her sayfas\u0131, farkl\u0131 bir ihtiyaca y\u00f6nelik tasarlanm\u0131\u015ft\u0131r. A\u015fa\u011f\u0131da her sayfan\u0131n detayl\u0131 a\u00e7\u0131klamas\u0131n\u0131 bulabilirsiniz.")
        ),

        # Ana Söyleşi
        div(
          class = "destek-guide-card",
          div(class = "destek-guide-icon destek-guide-icon-chat",
            icon("comments")
          ),
          div(
            class = "destek-guide-content",
            h4(HTML("Ana S\u00f6yle\u015fi")),
            p(HTML("Uygulaman\u0131n kalbidir. Alt k\u0131s\u0131mdaki metin kutusuna sorunuzu veya iste\u011finizi yaz\u0131n ve G\u00f6nder butonuna bas\u0131n. Yan\u0131tlar ger\u00e7ek zamanl\u0131 olarak ekrana yans\u0131t\u0131l\u0131r.")),
            div(class = "destek-guide-tips",
              tags$strong(HTML("\u0130pu\u00e7lar\u0131:")),
              tags$ul(
                tags$li(HTML("Dosya payla\u015f\u0131m\u0131 i\u00e7in s\u00fcr\u00fckle-b\u0131rak veya ata\u00e7 simgesini kullan\u0131n")),
                tags$li(HTML("Mikrofon butonu ile sesli mesaj g\u00f6nderebilirsiniz")),
                tags$li(HTML("Yan\u0131t sonundaki takip sorular\u0131na t\u0131klayarak sohbeti derinle\u015ftirebilirsiniz")),
                tags$li(HTML("Ho\u015f geldin ekran\u0131ndaki h\u0131zl\u0131 eylem kartlar\u0131 ile do\u011frudan ba\u015flayabilirsiniz"))
              )
            )
          )
        ),

        # Söyleşi Yönetimi
        div(
          class = "destek-guide-card",
          div(class = "destek-guide-icon destek-guide-icon-history",
            icon("folder-open")
          ),
          div(
            class = "destek-guide-content",
            h4(HTML("S\u00f6yle\u015fi Y\u00f6netimi")),
            p(HTML("Ge\u00e7mi\u015f sohbetlerinizi y\u00f6netmenizi sa\u011flayan \u00fc\u00e7 alt sayfadan olu\u015fur.")),
            div(class = "destek-guide-sub",
              tags$strong(HTML("S\u00f6yle\u015fi Ge\u00e7mi\u015fi:")),
              HTML(" T\u00fcm sohbetlerinizin kronolojik listesi. Herhangi birine t\u0131klayarak o ana geri d\u00f6nebilirsiniz.")
            ),
            div(class = "destek-guide-sub",
              tags$strong(HTML("Kay\u0131tl\u0131 S\u00f6yle\u015filer:")),
              HTML(" Otomatik kaydedilen sohbetler. Arama, yer imi ve silme i\u015flemleri yapabilirsiniz.")
            ),
            div(class = "destek-guide-sub",
              tags$strong(HTML("G\u00f6rsel Galerisi:")),
              HTML(" Yapay zeka ile olu\u015fturdu\u011funuz t\u00fcm g\u00f6rsellerin koleksiyonu. B\u00fcy\u00fctme, indirme ve kaynak sohbet referans\u0131.")
            )
          )
        ),

        # Dosya Yönetimi
        div(
          class = "destek-guide-card",
          div(class = "destek-guide-icon destek-guide-icon-files",
            icon("folder")
          ),
          div(
            class = "destek-guide-content",
            h4(HTML("Dosya Y\u00f6netimi")),
            p(HTML("Dosyalar\u0131n\u0131z\u0131 y\u00f6netti\u011finiz merkezi alan. S\u00fcr\u00fckle-b\u0131rak deste\u011fi ile dosya y\u00fckleme, \u00f6nizleme ve sohbete ekleme.")),
            div(class = "destek-guide-tips",
              tags$strong("Desteklenen Formatlar:"),
              HTML(" Excel (.xlsx, .xls), PDF, Word (.docx), CSV, RData, metin dosyalar\u0131 ve daha fazlas\u0131.")
            )
          )
        ),

        # Ayarlar
        div(
          class = "destek-guide-card",
          div(class = "destek-guide-icon destek-guide-icon-settings",
            icon("cog")
          ),
          div(
            class = "destek-guide-content",
            h4("Ayarlar"),
            p(HTML("Ki\u015fiselle\u015ftirme ve yap\u0131land\u0131rma se\u00e7eneklerini i\u00e7eren iki alt sayfadan olu\u015fur.")),
            div(class = "destek-guide-sub",
              tags$strong(HTML("Ki\u015fiselle\u015ftirme:")),
              HTML(" Deneyim modu (Odak, Dinamik, B\u00fct\u00fcnle\u015fik) ve yapay zeka karakter se\u00e7imi. Her karakterin kendine \u00f6zg\u00fc ki\u015fili\u011fi ve uzmanl\u0131k alan\u0131 vard\u0131r.")
            ),
            div(class = "destek-guide-sub",
              tags$strong(HTML("Yap\u0131land\u0131rma:")),
              HTML(" YZ model se\u00e7imi, analiz ara\u00e7lar\u0131, aray\u00fcz tercihleri (yaz\u0131 boyutu, animasyonlar, geni\u015f ekran), ses ve TTS/STT ayarlar\u0131.")
            )
          )
        ),

        # Destek
        div(
          class = "destek-guide-card",
          div(class = "destek-guide-icon destek-guide-icon-destek",
            icon("life-ring")
          ),
          div(
            class = "destek-guide-content",
            h4("Destek"),
            p(HTML("\u015eu an bulundu\u011funuz sayfa! \u00dc\u00e7 alt b\u00f6l\u00fcmden olu\u015fur.")),
            div(class = "destek-guide-sub",
              tags$strong(HTML("Yard\u0131m Merkezi:")),
              HTML(" E-posta ve telefon destek kanallar\u0131.")
            ),
            div(class = "destek-guide-sub",
              tags$strong("Geri Bildirim & Hata:"),
              HTML(" Memnuniyet de\u011ferlendirmesi, \u00f6neriler ve hata bildirimi.")
            ),
            div(class = "destek-guide-sub",
              tags$strong(HTML("Hakk\u0131nda:")),
              HTML(" Uygulama \u00f6zellikleri ve sayfa rehberi (bu sayfa).")
            )
          )
        )
      ),

      # İstatistikler
      div(
        class = "destek-hakkinda-stats",
        h3(class = "destek-hakkinda-section-title", HTML("S\u00fcrekli Geli\u015fiyoruz")),
        div(
          class = "destek-stats-grid",
          div(class = "destek-stat-item",
            span(class = "destek-stat-number", "99%"),
            span(class = "destek-stat-label", "Memnuniyet")
          ),
          div(class = "destek-stat-divider"),
          div(class = "destek-stat-item",
            span(class = "destek-stat-number", "24/7"),
            span(class = "destek-stat-label", "Destek")
          )
        )
      ),

      # Alt Bilgi
      div(
        class = "destek-hakkinda-footer",
        div(
          class = "destek-footer-content",
          icon("heart"),
          HTML(" \u00d6zenle geli\u015ftirildi"),
          span(class = "destek-footer-divider", "\u2022"),
          HTML("S\u00fcr\u00fcm 0.9")
        )
      )
    )
  )
}

# ==============================================================================
# HAKKINDA SERVER
# ==============================================================================

destekHakkindaServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    # Hakkında sayfası statik içerik, sunucu mantığı gerekmez
    invisible(NULL)
  })
}

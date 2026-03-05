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
            "MERGEN Bilge ile Tanışın"
          ),
          p(class = "destek-hakkinda-subtitle",
            "Türk ve Altay mitolojisinden esinlenen, kurumsal ortamlar için tasarlanmış gelişmiş yapay zeka asistanınız."
          )
        )
      ),

      # Özellik Kartları Izgarası
      div(
        class = "destek-hakkinda-features",
        h3(class = "destek-hakkinda-section-title",
          "Temel Özellikler"
        ),
        div(
          class = "destek-features-grid",
          # Kart 1: Akıllı Sohbet
          div(
            class = "destek-feature-card destek-feature-amber",
            div(class = "destek-feature-icon",
              icon("bolt")
            ),
            h4("Akıllı Sohbet"),
            p("Doğal dilde soru sorma, analiz isteme ve fikir alışverişi. Gerçek zamanlı akış (streaming) ile hızlı yanıtlar, kod vurgulama ve takip soruları desteği.")
          ),
          # Kart 2: Güvenlik
          div(
            class = "destek-feature-card destek-feature-emerald",
            div(class = "destek-feature-icon",
              icon("shield-halved")
            ),
            h4("Üstün Güvenlik"),
            p("Tüm sohbetler kullanıcı bazında ayrı tutulur. API anahtarları şifrelenerek saklanır. Oturum zaman aşımı ile güvenlik sağlanır.")
          ),
          # Kart 3: Dosya Analizi
          div(
            class = "destek-feature-card destek-feature-blue",
            div(class = "destek-feature-icon",
              icon("microchip")
            ),
            h4("Akıllı Dosya Analizi"),
            p("Excel, PDF, Word, RData ve daha birçok format desteklenir. MCP araçlarıyla derinlemesine analiz, özetleme ve veri işleme yetenekleri.")
          ),
          # Kart 4: Çoklu Karakter
          div(
            class = "destek-feature-card destek-feature-purple",
            div(class = "destek-feature-icon",
              icon("globe")
            ),
            h4("5 Benzersiz Karakter"),
            p("Türk ve Altay mitolojisinden esinlenen 5 farklı karakter. Her biri farklı uzmanlık alanı ve iletişim tarzına sahip.")
          )
        )
      ),

      # Sayfa Rehberi
      div(
        class = "destek-hakkinda-guide",
        h3(class = "destek-hakkinda-section-title", "Sayfa Rehberi"),
        p(class = "destek-hakkinda-guide-intro",
          "MERGEN Bilge'nin her sayfası, farklı bir ihtiyaca yönelik tasarlanmıştır. Aşağıda her sayfanın detaylı açıklamasını bulabilirsiniz."
        ),

        # Ana Söyleşi
        div(
          class = "destek-guide-card",
          div(class = "destek-guide-icon destek-guide-icon-chat",
            icon("comments")
          ),
          div(
            class = "destek-guide-content",
            h4("Ana Söyleşi"),
            p("Uygulamanın kalbidir. Alt kısımdaki metin kutusuna sorunuzu veya isteğinizi yazın ve Gönder butonuna basın. Yanıtlar gerçek zamanlı olarak ekrana yansıtılır."),
            div(class = "destek-guide-tips",
              tags$strong("İpuçları:"),
              tags$ul(
                tags$li("Dosya paylaşımı için sürükle-bırak veya ataç simgesini kullanın"),
                tags$li("Mikrofon butonu ile sesli mesaj gönderebilirsiniz"),
                tags$li("Yanıt sonundaki takip sorularına tıklayarak sohbeti derinleştirebilirsiniz"),
                tags$li("Hoş geldin ekranındaki hızlı eylem kartları ile doğrudan başlayabilirsiniz")
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
            h4("Söyleşi Yönetimi"),
            p("Geçmiş sohbetlerinizi yönetmenizi sağlayan üç alt sayfadan oluşur."),
            div(class = "destek-guide-sub",
              tags$strong("Söyleşi Geçmişi:"),
              " Tüm sohbetlerinizin kronolojik listesi. Herhangi birine tıklayarak o ana geri dönebilirsiniz."
            ),
            div(class = "destek-guide-sub",
              tags$strong("Kayıtlı Söyleşiler:"),
              " Otomatik kaydedilen sohbetler. Arama, yer imi ve silme işlemleri yapabilirsiniz."
            ),
            div(class = "destek-guide-sub",
              tags$strong("Görsel Galerisi:"),
              " Yapay zeka ile oluşturduğunuz tüm görsellerin koleksiyonu. Büyütme, indirme ve kaynak sohbet referansı."
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
            h4("Dosya Yönetimi"),
            p("Dosyalarınızı yönettiğiniz merkezi alan. Sürükle-bırak desteği ile dosya yükleme, önizleme ve sohbete ekleme."),
            div(class = "destek-guide-tips",
              tags$strong("Desteklenen Formatlar:"),
              " Excel (.xlsx, .xls), PDF, Word (.docx), CSV, RData, metin dosyaları ve daha fazlası."
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
            p("Kişiselleştirme ve yapılandırma seçeneklerini içeren iki alt sayfadan oluşur."),
            div(class = "destek-guide-sub",
              tags$strong("Kişiselleştirme:"),
              " Deneyim modu (Odak, Dinamik, Bütünleşik) ve yapay zeka karakter seçimi. Her karakterin kendine özgü kişiliği ve uzmanlık alanı vardır."
            ),
            div(class = "destek-guide-sub",
              tags$strong("Yapılandırma:"),
              " YZ model seçimi, analiz araçları, arayüz tercihleri (yazı boyutu, animasyonlar, geniş ekran), ses ve TTS/STT ayarları."
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
            p("Şu an bulunduğunuz sayfa! Üç alt bölümden oluşur."),
            div(class = "destek-guide-sub",
              tags$strong("Yardım Merkezi:"),
              " E-posta ve telefon destek kanalları ile yapay zeka destekli sohbet asistanı."
            ),
            div(class = "destek-guide-sub",
              tags$strong("Geri Bildirim & Hata:"),
              " Memnuniyet değerlendirmesi, öneriler ve hata bildirimi."
            ),
            div(class = "destek-guide-sub",
              tags$strong("Hakkında:"),
              " Uygulama özellikleri ve sayfa rehberi (bu sayfa)."
            )
          )
        )
      ),

      # İstatistikler (sayılar sayfa kaydırıldığında animasyonlu sayar)
      div(
        class = "destek-hakkinda-stats",
        id = "destek-stats-section",
        h3(class = "destek-hakkinda-section-title", "Sürekli Gelişiyoruz"),
        div(
          class = "destek-stats-grid",
          div(class = "destek-stat-item",
            div(class = "destek-stat-icon-wrapper destek-stat-icon-green",
              icon("face-smile")
            ),
            span(
              class = "destek-stat-number destek-stat-animated",
              `data-target` = "99",
              `data-suffix` = "%",
              `data-gradient` = "true",
              "0%"
            ),
            span(class = "destek-stat-label", "Memnuniyet")
          ),
          div(class = "destek-stat-divider"),
          div(class = "destek-stat-item",
            div(class = "destek-stat-icon-wrapper destek-stat-icon-blue",
              icon("microchip")
            ),
            span(
              class = "destek-stat-number destek-stat-animated",
              `data-target` = "10",
              `data-suffix` = "+",
              "0+"
            ),
            span(class = "destek-stat-label", "Yapay Zeka Aracı")
          )
        )
      ),

      # Alt Bilgi
      div(
        class = "destek-hakkinda-footer",
        div(
          class = "destek-footer-content",
          icon("heart"),
          " Özenle geliştirildi",
          span(class = "destek-footer-divider", "•"),
          "Sürüm 0.9"
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
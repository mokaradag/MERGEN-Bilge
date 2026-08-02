# ==============================================================================
# Dosya Yolu: R/module_settings_yapilandirma_advanced_ui.R
# Açıklama: Yapılandırma alt sekmesinin medya/görsel/analiz ayar kartları.
#            R/module_settings_yapilandirma_ui.R ana kompozitörü bu saf kart
#            yapıcılarını çağırır; server/runtime mantığı içermez.
#            Denetim açıklamaları `data-settings-tooltip` ile salt-CSS ipucu
#            olarak verilir (bkz. www/css/settings_page.css).
# ==============================================================================

.syap_audio_card <- function(ns) {
  div(
    class = "settings-card",
    h3("Ses Ayarları", class = "settings-title"),
    fluidRow(
      column(
        width = 4,
        h4("Sesli Yanıt", class = "setting-subtitle"),
        div(
          class = "checkbox-item",
          style = "margin-top: 8px;",
          `data-settings-tooltip` = "Yapay zekâ yanıtlarını otomatik olarak seslendirir.",
          checkboxInput(
            inputId = ns("enable_tts_audio"),
            label = tags$span("Yanıtları Seslendir"),
            value = FALSE
          )
        )
      ),
      column(
        width = 4,
        h4("Müzik", class = "setting-subtitle"),
        div(
          class = "checkbox-item",
          style = "margin-top: 8px;",
          `data-settings-tooltip` = "Uygulama genelinde arka plan müziği çalar.",
          checkboxInput(
            inputId = ns("enable_background_music"),
            label = tags$span("Arka Fon Müziği"),
            value = FALSE
          )
        )
      ),
      column(
        width = 4,
        h4("Ses Seviyesi", class = "setting-subtitle"),
        div(
          class = "setting-item",
          style = "margin-top: 8px;",
          `data-settings-tooltip` = "Müzik ses seviyesi; değişiklik anında uygulanır.",
          sliderInput(
            inputId = ns("music_volume"),
            label = NULL,
            min = 0,
            max = 1,
            value = 0.3,
            step = 0.05,
            width = "100%"
          )
        )
      )
    )
  )
}

.syap_ai_expert_card <- function(ns) {
  div(
    class = "settings-card ai-expert-settings-card",
    id = ns("ai_expert_settings_card"),
    h3("AI Uzman Konuşması", class = "settings-title"),
    p(
      "Bütünleşik modda AI uzmanın proaktif konuşma davranışını yapılandırın. Bu ayarlar yalnızca Bütünleşik (Keşif) modu aktifken geçerlidir.",
      class = "setting-description"
    ),
    fluidRow(
      column(
        width = 3,
        h4("Durum", class = "setting-subtitle"),
        div(
          class = "checkbox-item",
          style = "margin-top: 8px;",
          `data-settings-tooltip` = "AI uzmanını etkinleştirir veya devre dışı bırakır.",
          checkboxInput(
            inputId = ns("enable_ai_expert"),
            label = tags$span("AI Uzman Konuşması"),
            value = FALSE
          )
        )
      ),
      column(
        width = 3,
        h4("Konuşma Uzunluğu", class = "setting-subtitle"),
        div(
          class = "setting-item",
          style = "margin-top: 8px; max-width: 200px;",
          `data-settings-tooltip` = "AI uzmanın her konuşmasının ne kadar uzun olacağını belirler.",
          selectInput(
            inputId = ns("ai_expert_talk_length"),
            label = NULL,
            choices = c(
              "Kısa (1-2 cümle)" = "kisa",
              "Orta (3-5 cümle)" = "orta",
              "Uzun (5-8 cümle)" = "uzun"
            ),
            selected = "orta",
            width = "100%"
          )
        )
      ),
      column(
        width = 3,
        h4("Konuşma Sıklığı", class = "setting-subtitle"),
        div(
          class = "setting-item",
          style = "margin-top: 8px; max-width: 200px;",
          `data-settings-tooltip` = "AI uzmanın ne sıklıkla boşta konuşma başlatacağını belirler.",
          selectInput(
            inputId = ns("ai_expert_talk_frequency"),
            label = NULL,
            choices = c(
              "Az (60 sn)" = "az",
              "Orta (35 sn)" = "orta",
              "Sık (20 sn)" = "sik"
            ),
            selected = "orta",
            width = "100%"
          )
        )
      ),
      column(
        width = 3,
        h4("Konuşma Tarzı", class = "setting-subtitle"),
        div(
          class = "setting-item",
          style = "margin-top: 8px; max-width: 200px;",
          `data-settings-tooltip` = "AI uzmanın konuşma tonunu ve tarzını belirler.",
          selectInput(
            inputId = ns("ai_expert_talk_style"),
            label = NULL,
            choices = c(
              "Profesyonel" = "profesyonel",
              "Samimi" = "samimi",
              "Motivasyonel" = "motivasyonel",
              "Bilimsel" = "bilimsel"
            ),
            selected = "profesyonel",
            width = "100%"
          )
        )
      )
    )
  )
}

.syap_image_card <- function(ns) {
  div(
    class = "settings-card image-settings-card",
    id = ns("image_settings_card"),
    h3("Görsel Oluşturma Ayarları", class = "settings-title"),
    p(
      "DALL-E-3 ile görsel oluşturma ayarlarını yapılandırın. Bu ayarlar yalnızca 'Görsel Uzmanı' modu aktifken geçerlidir.",
      class = "setting-description"
    ),
    fluidRow(
      column(
        width = 6,
        div(
          class = "setting-item",
          `data-settings-tooltip` = "Üretilecek görselin en-boy oranını ve çözünürlüğünü belirler.",
          h4("Görsel Boyutu", class = "setting-subtitle"),
          selectInput(
            inputId = ns("image_size"),
            label = NULL,
            choices = c(
              "Kare (1024x1024)" = "1024x1024",
              "Yatay (1792x1024)" = "1792x1024",
              "Dikey (1024x1792)" = "1024x1792"
            ),
            selected = "1024x1024",
            width = "100%"
          )
        )
      ),
      column(
        width = 6,
        div(
          class = "setting-item",
          `data-settings-tooltip` = "Standart veya HD kalite. HD daha ayrıntılıdır ancak üretimi daha uzun sürer.",
          h4("Görsel Kalitesi", class = "setting-subtitle"),
          div(
            class = "quality-switch-container",
            tags$label(
              class = "quality-switch",
              tags$input(
                type = "checkbox",
                id = ns("image_quality_hd"),
                class = "quality-switch-input"
              ),
              tags$span(class = "quality-switch-slider"),
              tags$span(class = "quality-label-sd", "Standart"),
              tags$span(class = "quality-label-hd", "HD")
            )
          )
        )
      )
    )
  )
}

.syap_summarization_card <- function(ns) {
  div(
    class = "settings-card summarization-settings-card",
    id = ns("summarization_settings_card"),
    h3("Özetleme Ayarları", class = "settings-title"),
    p(
      "Dosya özetleme modunun davranışını yapılandırın. Bu ayarlar 'Dosya Özetleme' modu aktifken geçerlidir.",
      class = "setting-description"
    ),
    fluidRow(
      column(
        width = 6,
        div(
          class = "setting-item",
          `data-settings-tooltip` = "Özetin ne kadar ayrıntılı olacağını belirler.",
          h4("Detay Seviyesi", class = "setting-subtitle"),
          selectInput(
            inputId = ns("summary_detail_level"),
            label = NULL,
            choices = c(
              "Kısa Özet" = "brief",
              "Standart" = "standard",
              "Detaylı" = "detailed"
            ),
            selected = "standard",
            width = "100%"
          )
        )
      ),
      column(
        width = 6,
        div(
          class = "setting-item",
          `data-settings-tooltip` = "Özetin hangi konulara ağırlık vereceğini belirler.",
          h4("Odak Modu", class = "setting-subtitle"),
          selectInput(
            inputId = ns("summary_focus_mode"),
            label = NULL,
            choices = c(
              "Genel" = "general",
              "Sayısal Veri" = "numerical",
              "Karar & Öneri" = "decisions",
              "Karşılaştırma" = "comparison"
            ),
            selected = "general",
            width = "100%"
          )
        )
      )
    )
  )
}

.syap_analysis_card <- function(ns) {
  div(
    class = "settings-card analysis-settings-card",
    id = ns("analysis_settings_card"),
    h3("Proje ve Kaynak Analizi Ayarları", class = "settings-title"),
    p(
      "Veri analizi modunun davranışını yapılandırın. 'Derin Düşünme' aktifken çoklu sorgu analizi yapılır.",
      class = "setting-description"
    ),
    fluidRow(
      column(
        width = 6,
        div(
          class = "setting-item",
          `data-settings-tooltip` = "Aktifken birden fazla sorgu seçilir ve toplu analiz yapılır.",
          h4("Derin Düşünme", class = "setting-subtitle"),
          div(
            class = "deep-thinking-switch-container",
            tags$label(
              class = "deep-thinking-switch",
              tags$input(
                type = "checkbox",
                id = ns("analysis_deep_thinking"),
                class = "deep-thinking-switch-input"
              ),
              tags$span(class = "switch-slider")
            ),
            tags$span(class = "deep-thinking-label", "Çoklu Sorgu Analizi")
          )
        )
      ),
      column(
        width = 6,
        div(
          class = "setting-item",
          `data-settings-tooltip` = "Yanıtın ne kadar ayrıntılı olacağını belirler.",
          h4("Detay Seviyesi", class = "setting-subtitle"),
          selectInput(
            inputId = ns("analysis_detail_level"),
            label = NULL,
            choices = c(
              "Özet" = "ozet",
              "Standart" = "standart",
              "Detaylı" = "detayli"
            ),
            selected = "standart",
            width = "100%"
          )
        )
      )
    )
  )
}

#' Başlangıç Deneyimi kartı (Hızlı Başlangıç / Zengin Deneyim)
#' @description Başlangıç şeridi seçimi. Hızlı Başlangıç sinematik girişi,
#'   açılış müziğini ve zengin medya ön yüklemesini atlar; Zengin Deneyim
#'   mevcut sinematik açılışı korur. Tercih localStorage'a
#'   (mergen_settings.startup_lane) kaydedilir ve bir sonraki açılışta
#'   uygulanır. Saf UI; sunucu gözlemcisi R/module_settings_yapilandirma.R
#'   içindedir.
.syap_startup_lane_card <- function(ns) {
  div(
    class = "settings-card startup-lane-card",
    id = ns("startup_lane_card"),
    h3("Başlangıç Deneyimi", class = "settings-title"),
    p(
      "Uygulama açılışının nasıl davranacağını seçin. Tercihiniz bu tarayıcıda saklanır ve bir sonraki açılışta tam olarak uygulanır.",
      class = "setting-description"
    ),
    fluidRow(
      column(
        width = 6,
        div(
          class = "setting-item startup-lane-choices",
          radioButtons(
            inputId = ns("startup_experience_lane"),
            label = NULL,
            choiceNames = list(
              tagList(
                tags$strong("Hızlı Başlangıç"),
                tags$span(
                  class = "setting-description startup-lane-choice-desc",
                  "Doğrudan Ana Söyleşi'ye geç. Zengin medya ve diğer sayfalar gerektiğinde yüklenir."
                )
              ),
              tagList(
                tags$strong("Zengin Deneyim"),
                tags$span(
                  class = "setting-description startup-lane-choice-desc",
                  "MERGEN Bilge'nin sinematik açılışını, Keşfet akışını ve gelişmiş deneyim modlarını kullan."
                )
              )
            ),
            choiceValues = list("fast_lane", "rich_lane"),
            selected = character(0)
          )
        )
      ),
      column(
        width = 6,
        h4("Ayrıntılar", class = "setting-subtitle"),
        p(
          paste(
            "Hızlı Başlangıç'ta derin uzay girişi, açılış müziği ve sinematik/persona",
            "medya ön yüklemesi atlanır; Deneyim Modu kartları Zengin Deneyim'e",
            "taşınır. Hiçbir özellik silinmez: Kayıtlı Söyleşiler, Söyleşi Geçmişi,",
            "Görsel Galerisi ve Dosya Yönetimi açıldıklarında tam çalışır."
          ),
          class = "setting-description"
        )
      )
    )
  )
}

# R/module_settings_yapilandirma.R
# Dosya Yolu: R/module_settings_yapilandirma.R
# Açıklama: Ayarlar sayfasının "Yapılandırma" alt sekmesi.
#            Model ayarları, analiz araçları, arayüz ayarları, ses ayarları,
#            görsel oluşturma, özetleme ve proje analizi kartlarını içerir.
#            Teknik ve sistem düzeyindeki ayarları bir araya getirir.

#' Yapılandırma Alt Sekmesi UI
#'
#' @param id Modül ad alanı kimliği
#' @return Yapılandırma sekmesi için UI tanımı
settingsYapilandirmaUI <- function(id) {
  ns <- NS(id)

  tagList(
    div(
      class = "settings-container",
      # Üst başlık çubuğu (Kaydet / Sıfırla butonları)
      fluidRow(
        id = ns("settings_header"),
        column(
          width = 12,
          div(
            class = "chat-header settings-header-fixed",
            div(
              class = "chat-header-left",
              h4("Yapılandırma", class = "page-title")
            ),
            div(
              class = "chat-header-right",
              actionButton(ns("save_settings"), label = tagList(icon("save"), "Ayarları Kaydet"), class = "btn-modern btn-primary"),
              actionButton(ns("reset_settings"), label = tagList(icon("undo"), "Varsayılana Dön"), class = "btn-modern btn-secondary")
            )
          )
        )
      ),
      # Kaydırılabilir içerik
      div(
        class = "settings-scrollable-content",
        fluidRow(
          column(
            width = 12,
            # Model Ayarları Kartı
            div(
              class = "settings-card",
              h3("Model Ayarları", class = "settings-title"),
              fluidRow(
                # Model Seçimi
                column(
                  width = 4,
                  h4("Model Seçimi", class = "setting-subtitle"),
                  p("Kullanmak istediğiniz modeli seçin.", class = "setting-description", style = "margin-top:4px;"),
                  div(
                    class = "setting-item",
                    style = "max-width: 250px;",
                    selectInput(
                      inputId = ns("model_selection"),
                      label   = NULL,
                      choices = api_config$local_models,
                      selected = api_config$local_models[1],
                      width = "100%"
                    ),
                    uiOutput(ns("model_description_text"))
                  )
                ),
                # Yanıt Sonrası Öneriler
                column(
                  width = 4,
                  div(
                    class = "setting-item followup-toggle",
                    h4("Yanıt Sonrası Öneriler", class = "setting-subtitle"),
                    p("Model yanıtlarının sonunda otomatik takip soruları görüntüleyin.", class = "setting-description", style = "margin-top:4px;"),
                    div(
                      class = "checkbox-item followup-checkbox",
                      checkboxInput(
                        inputId = ns("enable_followups"),
                        label = tags$span("Takip sorusu önerilerini göster"),
                        value = FALSE
                      )
                    )
                  )
                ),
                # API Anahtarını Güncelle
                column(
                  width = 4,
                  h4("API Anahtarını Güncelle", class = "setting-subtitle"),
                  p("LLM erişimi için kişisel API anahtarınızı yönetin.", class = "setting-description"),
                  div(
                    class = "setting-item",
                    div(
                      style = "display:flex; flex-direction:column; gap:10px; align-items:flex-start;",
                      actionButton(
                        ns("update_api_key_btn"),
                        label = tagList(icon("key"), "API Anahtarını Güncelle"),
                        class = "btn-modern btn-warning"
                      ),
                      tags$a(
                        href   = getOption(
                          "mergen.rate_limit_url",
                          Sys.getenv("SERVICE_DESK_RATE_LIMIT_URL", "https://service-desk.example.com/rate-limit")
                        ),
                        target = "_blank",
                        class  = "btn-modern btn-rate",
                        tagList(icon("gauge-high"), span("Rate Limit Artışı"))
                      )
                    )
                  )
                )
              )
            ),
            # Analiz Araçları Kartı
            div(
              class = "settings-card tool-selector-card",
              h3("Analiz Araçları", class = "settings-title"),
              # Gizli checkbox'lar (mevcut Shiny mantığı korunuyor)
              div(
                style = "display:none;",
                checkboxInput(ns("enable_rdata_tools"), "rData", value = FALSE),
                checkboxInput(ns("enable_mcp_tools"), "MCP Excel", value = FALSE),
                checkboxInput(ns("enable_summarization_tools"), "Özetleme", value = FALSE),
                checkboxInput(ns("enable_coding_tools"), "Kodlama", value = FALSE),
                checkboxInput(ns("enable_process_tools"), "Süreç", value = FALSE),
                checkboxInput(ns("enable_app_expert_tools"), "Uygulama", value = FALSE),
                checkboxInput(ns("enable_image_tools"), "Görsel", value = FALSE)
              ),
              # Buton seçici (JS tarafından doldurulur)
              div(
                class = "tool-selector-buttons",
                id = ns("tool_buttons")
              ),
              # Açıklama alanı
              div(
                class = "tool-description-area",
                p(
                  class = "tool-desc-subtext",
                  "Analiz araçları, yapay zeka modelinin harici veri kaynakları ve uzman yetenekleri ile etkileşime girmesini sağlar. Aynı anda yalnızca bir araç aktif olabilir."
                ),
                p(class = "tool-desc-detail", id = ns("tool_desc_text"))
              )
            ),
            # Claude Code Yapılandırma Kartı
            div(
              class = "settings-card cc-config-card",
              h3("Claude Code Yapılandırma", class = "settings-title"),
              p("Claude Code CLI bağlantı ayarları, zaman aşımı ve durum bilgisi.",
                class = "setting-description"),
              fluidRow(
                # Zaman Aşımı
                column(
                  width = 4,
                  h4("Zaman Aşımı", class = "setting-subtitle"),
                  p("Claude Code komutları için maksimum bekleme süresi.", class = "setting-description", style = "margin-top:4px;"),
                  div(
                    class = "setting-item",
                    style = "max-width: 200px;",
                    numericInput(
                      inputId = ns("claude_code_timeout"),
                      label = NULL,
                      value = claude_code_config$timeout_seconds,
                      min = 30,
                      max = 600,
                      step = 30
                    ),
                    tags$small(class = "setting-description", "30-600 saniye arası")
                  )
                ),
                # Bağlantı Testi
                column(
                  width = 4,
                  h4("Bağlantı Testi", class = "setting-subtitle"),
                  p("Claude Code CLI erişimini test edin.", class = "setting-description", style = "margin-top:4px;"),
                  div(
                    class = "setting-item",
                    actionButton(
                      ns("cc_test_connection"),
                      label = tagList(icon("satellite-dish"), "Bağlantı Testi"),
                      class = "btn-modern btn-primary"
                    ),
                    uiOutput(ns("cc_test_result_ui"))
                  )
                ),
                # CLI Durumu
                column(
                  width = 4,
                  h4("CLI Durumu", class = "setting-subtitle"),
                  p("Claude Code CLI kurulum ve erişim bilgisi.", class = "setting-description", style = "margin-top:4px;"),
                  uiOutput(ns("cc_cli_status_info"))
                )
              )
            ),
            # Arayüz Ayarları ve Kısayollar
            fluidRow(
              column(
                width = 9,
                div(
                  class = "settings-card",
                  style = "min-height: 425px;",
                  h3("Arayüz Ayarları", class = "settings-title"),
                  div(
                    class = "settings-grid",
                    div(
                      class = "setting-column",
                      h4("Görünüm", class = "setting-subtitle"),
                      div(
                        class = "toggle-group",
                        div(class = "checkbox-item", checkboxInput(ns("enable_timestamps"), "Zaman Damgaları", value = TRUE)),
                        div(class = "checkbox-item", checkboxInput(ns("enable_typing_indicator"), "Yazma Göstergesi", value = TRUE)),
                        div(class = "checkbox-item", checkboxInput(ns("enable_animations"), "Animasyonlar", value = TRUE)),
                        div(class = "checkbox-item", checkboxInput(ns("enable_widescreen"), "Geniş Ekran", value = TRUE)),
                        div(class = "checkbox-item", checkboxInput(ns("enable_streaming"), "Akış Modu", value = TRUE))
                      )
                    ),
                    div(
                      class = "setting-column",
                      div(
                        class = "setting-item",
                        style = "max-width: 250px;",
                        selectInput(
                          inputId = ns("font_size"),
                          label = "Yazı Tipi Boyutu:",
                          choices = list("Küçük (14px)" = "small", "Orta (16px)" = "medium", "Büyük (18px)" = "large", "Çok Büyük (20px)" = "xlarge"),
                          selected = "medium",
                          width = "100%"
                        ),
                        p("Mesajların yazı tipi boyutunu ayarlayın", class = "setting-description")
                      ),
                      div(
                        class = "setting-item",
                        style = "margin-top: 16px;",
                        h4("Giriş Ekranı", class = "setting-subtitle"),
                        div(
                          class = "checkbox-item",
                          checkboxInput(
                            inputId = ns("show_intro_animation"),
                            label = "Giriş animasyonunu göster",
                            value = TRUE
                          )
                        ),
                        p("Uygulama açılışında derin uzay giriş ekranını gösterir", class = "setting-description")
                      )
                    )
                  )
                )
              ),
              column(
                width = 3,
                div(
                  class = "settings-card",
                  style = "min-height: 425px;",
                  h3("Kısayollar", class = "settings-title", style = "margin-bottom: 16px;"),
                  div(
                    class = "shortcut-list",
                    div(class = "shortcut-item", tags$kbd("Enter"), " - Mesaj gönder"),
                    div(class = "shortcut-item", tags$kbd("Shift + Enter"), " - Yeni satır"),
                    div(class = "shortcut-item", tags$kbd("Ctrl + U"), " - Dosya yükle"),
                    div(class = "shortcut-item", tags$kbd("Ctrl + N"), " - Yeni sohbet"),
                    div(class = "shortcut-item", tags$kbd("Page Up/Down"), " - Sayfa kaydır")
                  )
                )
              )
            ),
            # Ses Ayarları Kartı (AI Uzman ayrı karta taşındı)
            div(
              class = "settings-card",
              h3("Ses Ayarları", class = "settings-title"),
              fluidRow(
                # Sesli Yanıt
                column(
                  width = 4,
                  h4("Sesli Yanıt", class = "setting-subtitle"),
                  div(
                    class = "checkbox-item",
                    style = "margin-top: 8px;",
                    checkboxInput(
                      inputId = ns("enable_tts_audio"),
                      label = tags$span("Yanıtları Seslendir"),
                      value = FALSE
                    )
                  ),
                  p("AI yanıtlarını otomatik seslendir.", class = "setting-description", style = "margin-top: 4px;")
                ),
                # Müzik
                column(
                  width = 4,
                  h4("Müzik", class = "setting-subtitle"),
                  div(
                    class = "checkbox-item",
                    style = "margin-top: 8px;",
                    checkboxInput(
                      inputId = ns("enable_background_music"),
                      label = tags$span("Arka Fon Müziği"),
                      value = FALSE
                    )
                  ),
                  p("Uygulama genelinde arka plan müziği çal.", class = "setting-description", style = "margin-top: 4px;")
                ),
                # Ses Seviyesi
                column(
                  width = 4,
                  h4("Ses Seviyesi", class = "setting-subtitle"),
                  div(
                    style = "margin-top: 8px;",
                    sliderInput(
                      inputId = ns("music_volume"),
                      label = NULL,
                      min = 0,
                      max = 1,
                      value = 0.3,
                      step = 0.05,
                      width = "100%"
                    )
                  ),
                  p("Müzik ses seviyesi (anlık uygulanır).", class = "setting-description", style = "margin-top: 4px;")
                )
              )
            ),
            # AI Uzman Konuşması Kartı (yeni, ayrı kart)
            div(
              class = "settings-card ai-expert-settings-card",
              id = ns("ai_expert_settings_card"),
              h3("AI Uzman Konuşması", class = "settings-title"),
              p("Bütünleşik modda AI uzmanın proaktif konuşma davranışını yapılandırın. Bu ayarlar yalnızca Bütünleşik (Keşif) modu aktifken geçerlidir.",
                class = "setting-description"),
              fluidRow(
                # AI Uzman Etkinleştirme
                column(
                  width = 3,
                  h4("Durum", class = "setting-subtitle"),
                  div(
                    class = "checkbox-item",
                    style = "margin-top: 8px;",
                    checkboxInput(
                      inputId = ns("enable_ai_expert"),
                      label = tags$span("AI Uzman Konuşması"),
                      value = FALSE
                    )
                  ),
                  p("AI uzmanını etkinleştir veya devre dışı bırak.", class = "setting-description", style = "margin-top: 4px;")
                ),
                # Konuşma Uzunluğu
                column(
                  width = 3,
                  h4("Konuşma Uzunluğu", class = "setting-subtitle"),
                  div(
                    class = "setting-item",
                    style = "margin-top: 8px; max-width: 200px;",
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
                  ),
                  p("AI uzmanın her konuşmasının ne kadar uzun olacağını belirler.", class = "setting-description", style = "margin-top: 4px;")
                ),
                # Konuşma Sıklığı
                column(
                  width = 3,
                  h4("Konuşma Sıklığı", class = "setting-subtitle"),
                  div(
                    class = "setting-item",
                    style = "margin-top: 8px; max-width: 200px;",
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
                  ),
                  p("AI uzmanın ne sıklıkla boşta konuşma başlatacağını belirler.", class = "setting-description", style = "margin-top: 4px;")
                ),
                # Konuşma Tarzı
                column(
                  width = 3,
                  h4("Konuşma Tarzı", class = "setting-subtitle"),
                  div(
                    class = "setting-item",
                    style = "margin-top: 8px; max-width: 200px;",
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
                  ),
                  p("AI uzmanın konuşma tonunu ve tarzını belirler.", class = "setting-description", style = "margin-top: 4px;")
                )
              )
            ),
            # Görsel Oluşturma Ayarları Kartı
            div(
              class = "settings-card image-settings-card",
              id = ns("image_settings_card"),
              h3("Görsel Oluşturma Ayarları", class = "settings-title"),
              p("DALL-E-3 ile görsel oluşturma ayarlarını yapılandırın. Bu ayarlar yalnızca 'Görsel Uzmanı' modu aktifken geçerlidir.",
                class = "setting-description"),
              fluidRow(
                column(
                  width = 6,
                  div(
                    class = "setting-item",
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
            ),
            # Özetleme Ayarları Kartı
            div(
              class = "settings-card summarization-settings-card",
              id = ns("summarization_settings_card"),
              h3("Özetleme Ayarları", class = "settings-title"),
              p("Dosya özetleme modunun davranışını yapılandırın. Bu ayarlar 'Dosya Özetleme' modu aktifken geçerlidir.",
                class = "setting-description"),
              fluidRow(
                column(
                  width = 6,
                  div(
                    class = "setting-item",
                    h4("Detay Seviyesi", class = "setting-subtitle"),
                    p("Özetin ne kadar ayrıntılı olacağını belirler.", class = "setting-description", style = "margin-top:4px;"),
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
                    h4("Odak Modu", class = "setting-subtitle"),
                    p("Özetin hangi konulara ağırlık vereceğini belirler.", class = "setting-description", style = "margin-top:4px;"),
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
            ),
            # Proje ve Kaynak Analizi Ayarları Kartı
            div(
              class = "settings-card analysis-settings-card",
              id = ns("analysis_settings_card"),
              h3("Proje ve Kaynak Analizi Ayarları", class = "settings-title"),
              p("Veri analizi modunun davranışını yapılandırın. 'Derin Düşünme' aktifken çoklu sorgu analizi yapılır.",
                class = "setting-description"),
              fluidRow(
                column(
                  width = 6,
                  div(
                    class = "setting-item",
                    h4("Derin Düşünme", class = "setting-subtitle"),
                    p("Aktifken birden fazla sorgu seçilir ve toplu analiz yapılır.", class = "setting-description", style = "margin-top:4px;"),
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
                    h4("Detay Seviyesi", class = "setting-subtitle"),
                    p("Yanıtın ne kadar ayrıntılı olacağını belirler.", class = "setting-description", style = "margin-top:4px;"),
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
          )
        )
      )
    )
  )
}

#' Yapılandırma Alt Sekmesi Sunucu
#'
#' @param id Modül ad alanı kimliği
#' @param settings Merkezi ayarlar reaktif değerleri (paylaşımlı)
#' @param parent_session Üst oturum nesnesi
#' @return Koordinatörün kullanacağı reaktif değerleri içeren liste
settingsYapilandirmaServer <- function(id, settings, parent_session = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Kaydet/Sıfırla tetikleyicileri (koordinatör tarafından dinlenir)
    save_trigger <- reactiveVal(0)
    reset_trigger <- reactiveVal(0)

    observeEvent(input$save_settings, {
      save_trigger(isolate(save_trigger()) + 1)
    }, ignoreInit = TRUE)

    observeEvent(input$reset_settings, {
      reset_trigger(isolate(reset_trigger()) + 1)
    }, ignoreInit = TRUE)

    # Model açıklamasını dinamik göster
    output$model_description_text <- renderUI({
      req(input$model_selection)
      descriptions <- api_config$local_model_descriptions %||% list()
      desc <- descriptions[[input$model_selection]]
      if (!is.null(desc) && nzchar(desc)) {
        tags$p(
          class = "setting-description",
          style = "margin-top: 4px; font-size: 12px; color: #999; font-style: italic;",
          desc
        )
      } else {
        NULL
      }
    })

    # Geçici değişkenler (kaydet butonuna basılana kadar uygulanmaz)
    temp_model_selection <- reactiveVal(api_config$local_models[1])
    temp_image_size <- reactiveVal("1024x1024")
    temp_image_quality_hd <- reactiveVal(FALSE)
    temp_summary_detail_level <- reactiveVal("standard")
    temp_summary_focus_mode <- reactiveVal("general")
    temp_analysis_deep_thinking <- reactiveVal(FALSE)
    temp_analysis_detail_level <- reactiveVal("standart")

    # Model seçimi geçici değişken
    observeEvent(input$model_selection, {
      temp_model_selection(input$model_selection)
    }, ignoreInit = TRUE)

    # Ana Söyleşi'den model değiştirilirse Yapılandırma'yı da güncelle
    observeEvent(settings$model_selection, {
      req(settings$model_selection)
      if (settings$model_selection != temp_model_selection()) {
        temp_model_selection(settings$model_selection)
        updateSelectInput(session, "model_selection", selected = settings$model_selection)
      }
    })

    # API Anahtarı güncelleme modalı
    observeEvent(input$update_api_key_btn, {
      showModal(modalDialog(
        title = "API Anahtarı Güncelleme",
        easyClose = TRUE, size = "m",
        passwordInput(ns("api_key_plain_input"), label = "Yeni API Anahtarı", width = "100%"),
        footer = tagList(
          tags$button("Kapat", class = "btn-modern btn-secondary", `data-dismiss` = "modal"),
          actionButton(ns("api_key_save_btn"), "Kaydet", class = "btn-modern btn-primary")
        )
      ))
    }, ignoreInit = TRUE)

    observeEvent(input$api_key_save_btn, {
      req(input$api_key_plain_input)
      key_plain <- trimws(input$api_key_plain_input)
      if (!nzchar(key_plain)) {
        showToast(session, "Anahtar boş olamaz.", "warning"); return()
      }

      target <- determine_api_key_validation_target(isolate(settings$model_selection), api_config)
      if (!isTRUE(target$allow_user_key) || !nzchar(target$endpoint)) {
        showToast(session, "Bu model için kullanıcı tarafından yönetilen bir API anahtarı yok.", "error")
        return()
      }

      if (isTRUE(target$fallback_used)) {
        showToast(session, "Seçili model sabit anahtar kullanıyor; doğrulama birincil uç nokta ile yapılacak.", "info")
      }

      vres <- try(
        validate_api_key(
          key_plain,
          model_id = target$model_id,
          endpoint = target$endpoint,
          timeout_seconds = 6
        ),
        silent = TRUE
      )
      if (inherits(vres, "try-error") || !is.list(vres)) {
        err_msg <- tryCatch(conditionMessage(attr(vres, "condition")), error = function(e) "Bilinmeyen hata")
        showToast(session, paste("Anahtar doğrulaması başarısız:", err_msg), "error")
        return()
      }
      if (identical(vres$valid, FALSE)) {
        showToast(session, paste("API anahtarı geçersiz:", vres$message %||% ""), "error")
        return()
      }
      if (!isTRUE(vres$valid)) {
        showToast(session, paste("Anahtar doğrulanamadı (kaydedilmedi):", vres$message %||% "Doğrulama başarısız."), "error")
        return()
      }

      # Kaydet + oturuma yaz
      tryCatch({
        system_username <- session$userData$system_username %||% Sys.info()[["user"]]
        save_user_api_key(system_username, key_plain)
        session$userData$ai_api_key <- key_plain
        removeModal()
        success_msg <- vres$message %||% "API anahtarı güncellendi."
        if (isTRUE(target$fallback_used)) {
          success_msg <- paste(success_msg, "Not: Doğrulama birincil uç nokta ile tamamlandı.")
        }
        if (!nzchar(success_msg)) {
          success_msg <- "API anahtarı güncellendi."
        } else if (!grepl("API anahtarı", success_msg, fixed = TRUE)) {
          success_msg <- paste("API anahtarı güncellendi \U2014", success_msg)
        }
        showToast(session, success_msg, "success")
      }, error = function(e) {
        showToast(session, paste("API anahtarı kaydedilemedi:", conditionMessage(e)), "error")
      })
    }, ignoreInit = TRUE)

    # Müzik ayarları observer'ları
    # Checkbox değişikliği müziği hemen başlatmaz/durdurmaz.
    # Müzik durumu yalnızca "Ayarları Kaydet" butonuna basıldığında uygulanır.
    # Bu sayede yarış durumları ve üst üste çalma engellenir.
    observeEvent(input$enable_background_music, {
      cat(sprintf("[MUSIC] Checkbox değişti: %s (kaydedilmeden uygulanmayacak)\n", isTRUE(input$enable_background_music)))
    }, ignoreInit = TRUE)

    observeEvent(input$music_volume, {
      settings$music_volume <- input$music_volume
      session$sendCustomMessage("setMusicVolume", input$music_volume)
    }, ignoreInit = TRUE)

    # Giriş animasyonu ayarı
    observeEvent(input$show_intro_animation, {
      settings$show_intro_animation <- isTRUE(input$show_intro_animation)
      shinyjs::runjs(sprintf(
        "try { var s = JSON.parse(localStorage.getItem('mergen_settings') || '{}'); s.skip_intro = %s; localStorage.setItem('mergen_settings', JSON.stringify(s)); } catch(e) {}",
        tolower(as.character(!isTRUE(input$show_intro_animation)))
      ))
    }, ignoreInit = TRUE)

    # Görsel ayarları değişiklik observer'ları - sadece geçici değişkenleri güncelle
    observeEvent(input$image_size, {
      temp_image_size(input$image_size)
    }, ignoreInit = TRUE)

    observeEvent(input$image_quality_hd, {
      temp_image_quality_hd(isTRUE(input$image_quality_hd))
    }, ignoreInit = TRUE)

    # Özetleme ayarları değişiklik observer'ları
    observeEvent(input$summary_detail_level, {
      temp_summary_detail_level(input$summary_detail_level)
    }, ignoreInit = TRUE)

    observeEvent(input$summary_focus_mode, {
      temp_summary_focus_mode(input$summary_focus_mode)
    }, ignoreInit = TRUE)

    # Analiz ayarları değişiklik observer'ları
    observeEvent(input$analysis_deep_thinking, {
      temp_analysis_deep_thinking(isTRUE(input$analysis_deep_thinking))
    }, ignoreInit = TRUE)

    observeEvent(input$analysis_detail_level, {
      temp_analysis_detail_level(input$analysis_detail_level)
    }, ignoreInit = TRUE)

    # Ana Söyleşi'den gelen değişiklikleri Yapılandırma sayfasına yansıt
    observeEvent(settings$image_size, {
      current_temp <- temp_image_size()
      if (!identical(settings$image_size, current_temp)) {
        temp_image_size(settings$image_size)
        updateSelectInput(session, "image_size", selected = settings$image_size)
      }
    }, ignoreInit = TRUE)

    observeEvent(settings$image_quality_hd, {
      current_temp <- temp_image_quality_hd()
      if (!identical(settings$image_quality_hd, current_temp)) {
        temp_image_quality_hd(settings$image_quality_hd)
        if (isTRUE(settings$image_quality_hd)) {
          shinyjs::runjs(sprintf("$('#%s').prop('checked', true);", ns("image_quality_hd")))
        } else {
          shinyjs::runjs(sprintf("$('#%s').prop('checked', false);", ns("image_quality_hd")))
        }
      }
    }, ignoreInit = TRUE)

    observeEvent(settings$summary_detail_level, {
      current_temp <- temp_summary_detail_level()
      if (!identical(settings$summary_detail_level, current_temp)) {
        temp_summary_detail_level(settings$summary_detail_level)
        updateSelectInput(session, "summary_detail_level", selected = settings$summary_detail_level)
      }
    }, ignoreInit = TRUE)

    observeEvent(settings$summary_focus_mode, {
      current_temp <- temp_summary_focus_mode()
      if (!identical(settings$summary_focus_mode, current_temp)) {
        temp_summary_focus_mode(settings$summary_focus_mode)
        updateSelectInput(session, "summary_focus_mode", selected = settings$summary_focus_mode)
      }
    }, ignoreInit = TRUE)

    observeEvent(settings$analysis_deep_thinking, {
      current_temp <- temp_analysis_deep_thinking()
      if (!identical(settings$analysis_deep_thinking, current_temp)) {
        temp_analysis_deep_thinking(settings$analysis_deep_thinking)
        if (isTRUE(settings$analysis_deep_thinking)) {
          shinyjs::runjs(sprintf("$('#%s').prop('checked', true);", ns("analysis_deep_thinking")))
        } else {
          shinyjs::runjs(sprintf("$('#%s').prop('checked', false);", ns("analysis_deep_thinking")))
        }
      }
    }, ignoreInit = TRUE)

    observeEvent(settings$analysis_detail_level, {
      current_temp <- temp_analysis_detail_level()
      if (!identical(settings$analysis_detail_level, current_temp)) {
        temp_analysis_detail_level(settings$analysis_detail_level)
        updateSelectInput(session, "analysis_detail_level", selected = settings$analysis_detail_level)
      }
    }, ignoreInit = TRUE)

    # Arayüz ayarları - anlık güncelleme
    observeEvent(input$font_size,               { settings$font_size               <- input$font_size })
    observeEvent(input$enable_animations,       { settings$enable_animations       <- input$enable_animations })
    observeEvent(input$enable_timestamps,       { settings$enable_timestamps       <- input$enable_timestamps })
    observeEvent(input$enable_typing_indicator, { settings$enable_typing_indicator <- input$enable_typing_indicator })
    observeEvent(input$enable_streaming,        { settings$enable_streaming        <- input$enable_streaming })
    observeEvent(input$enable_widescreen,       { settings$enable_widescreen       <- input$enable_widescreen })
    observeEvent(input$enable_tts_audio,        { settings$enable_tts_audio        <- isTRUE(input$enable_tts_audio) })
    observeEvent(input$enable_ai_expert,        { settings$enable_ai_expert        <- isTRUE(input$enable_ai_expert) })
    observeEvent(input$enable_followups,        { settings$enable_followups        <- isTRUE(input$enable_followups) })

    # AI Uzman konuşma ayarları - anlık güncelleme
    observeEvent(input$ai_expert_talk_length,   { settings$ai_expert_talk_length   <- input$ai_expert_talk_length })
    observeEvent(input$ai_expert_talk_frequency, { settings$ai_expert_talk_frequency <- input$ai_expert_talk_frequency })
    observeEvent(input$ai_expert_talk_style,    { settings$ai_expert_talk_style    <- input$ai_expert_talk_style })

    # Analiz araçları - karşılıklı dışlama mantığı
    ANALYSIS_TOOLS <- c(
      "enable_rdata_tools",
      "enable_mcp_tools",
      "enable_summarization_tools",
      "enable_coding_tools",
      "enable_process_tools",
      "enable_app_expert_tools",
      "enable_image_tools"
    )

    lapply(ANALYSIS_TOOLS, function(tool_name) {
      observeEvent(input[[tool_name]], {
        settings[[tool_name]] <- isTRUE(input[[tool_name]])

        if (isTRUE(input[[tool_name]])) {
          # Diğer araçları devre dışı bırak
          other_tools <- setdiff(ANALYSIS_TOOLS, tool_name)
          for (other in other_tools) {
            if (isTRUE(input[[other]])) {
              updateCheckboxInput(session, other, value = FALSE)
              settings[[other]] <- FALSE
            }
          }

          # Görsel Uzmanı aktifleştirildiğinde otomatik model ayarla
          if (tool_name == "enable_image_tools") {
            image_model <- Sys.getenv("IMAGE_GEN_MODEL", "dall-e-3")
            settings$model_selection <- image_model
            temp_model_selection(image_model)
            session$sendCustomMessage("toggleImageMode", list(active = TRUE))
            session$sendCustomMessage("toggleSummaryMode", list(active = FALSE))
            session$sendCustomMessage("toggleAnalysisMode", list(active = FALSE))
          }

          # Dosya Özetleme aktifleştirildiğinde kontrolleri göster
          if (tool_name == "enable_summarization_tools") {
            session$sendCustomMessage("toggleSummaryMode", list(active = TRUE))
            session$sendCustomMessage("toggleImageMode", list(active = FALSE))
            session$sendCustomMessage("toggleAnalysisMode", list(active = FALSE))
          }

          # Proje ve Kaynak Analizi aktifleştirildiğinde kontrolleri göster
          if (tool_name == "enable_rdata_tools") {
            session$sendCustomMessage("toggleAnalysisMode", list(active = TRUE))
            session$sendCustomMessage("toggleImageMode", list(active = FALSE))
            session$sendCustomMessage("toggleSummaryMode", list(active = FALSE))
            session$sendCustomMessage("syncAnalysisSettingsToChat", list(
              deep_thinking = isTRUE(settings$analysis_deep_thinking),
              detail_level = settings$analysis_detail_level %||% "standart"
            ))
          }

          # Diğer araçlar aktifken kontrolleri gizle
          if (!tool_name %in% c("enable_rdata_tools", "enable_image_tools", "enable_summarization_tools")) {
            session$sendCustomMessage("toggleAnalysisMode", list(active = FALSE))
            session$sendCustomMessage("toggleImageMode", list(active = FALSE))
            session$sendCustomMessage("toggleSummaryMode", list(active = FALSE))
          }
        } else {
          # Görsel Uzmanı devre dışı bırakıldığında varsayılan modele dön
          if (tool_name == "enable_image_tools") {
            default_model <- api_config$local_models[1]
            settings$model_selection <- default_model
            temp_model_selection(default_model)
            updateSelectInput(session, "model_selection", selected = default_model)
            session$sendCustomMessage("saveSettings", list(model_selection = default_model))
            session$sendCustomMessage("toggleImageMode", list(active = FALSE))
          }

          if (tool_name == "enable_summarization_tools") {
            session$sendCustomMessage("toggleSummaryMode", list(active = FALSE))
          }

          if (tool_name == "enable_rdata_tools") {
            session$sendCustomMessage("toggleAnalysisMode", list(active = FALSE))
          }
        }
      }, ignoreInit = TRUE)
    })

    # --- Claude Code Yapılandırma Kartı ---

    # CLI durumunu göster
    output$cc_cli_status_info <- renderUI({
      yol <- resolve_claude_cli_path(claude_code_config$cli_path)

      if (!is.null(yol)) {
        tags$div(
          style = "padding: 8px 10px; border-radius: 8px; font-size: 12px; background: rgba(76,175,80,0.1); color: #81C784; border: 1px solid rgba(76,175,80,0.2);",
          icon("check-circle"),
          tags$span("CLI bulundu:"),
          tags$br(),
          tags$code(style = "font-size: 11px; word-break: break-all; background: rgba(0,0,0,0.2); padding: 1px 4px; border-radius: 3px;", yol)
        )
      } else {
        tags$div(
          style = "padding: 8px 10px; border-radius: 8px; font-size: 12px; background: rgba(255,152,0,0.1); color: #FFB74D; border: 1px solid rgba(255,152,0,0.2);",
          icon("exclamation-triangle"),
          tags$span("CLI otomatik tespit edilemedi."),
          tags$br(),
          tags$small("npm ile Claude Code kurulu olduğundan emin olun.")
        )
      }
    })

    # Bağlantı testi
    observeEvent(input$cc_test_connection, {
      cli_yolu <- resolve_claude_cli_path(claude_code_config$cli_path)

      shinyjs::disable("cc_test_connection")
      output$cc_test_result_ui <- renderUI({
        tags$span(style = "font-size: 12px; color: #64B5F6;",
                  icon("spinner", class = "fa-spin"), "Test ediliyor...")
      })

      future_promise({
        test_claude_code_connection(
          cli_path = cli_yolu,
          workdir = tempdir()
        )
      }) %...>% (function(sonuc) {
        # Sonucu Claude Code sayfasına da ilet
        settings$claude_code_connection_ok <- sonuc$success

        output$cc_test_result_ui <- renderUI({
          if (sonuc$success) {
            tags$div(
              style = "font-size: 12px; color: #81C784; margin-top: 8px;",
              icon("check-circle"),
              tags$span(sonuc$message),
              tags$br(),
              tags$small(style = "opacity: 0.8;", sonuc$details)
            )
          } else {
            tags$div(
              style = "font-size: 12px; color: #E57373; margin-top: 8px;",
              icon("exclamation-triangle"),
              tags$span(sonuc$message),
              tags$br(),
              tags$small(style = "opacity: 0.8;", sonuc$details)
            )
          }
        })
        shinyjs::enable("cc_test_connection")
      }) %...!% (function(hata) {
        settings$claude_code_connection_ok <- FALSE
        # Süslü parantezleri temizle (glue formatter çakışmasını önle)
        temiz_hata <- gsub("[{}]", "", conditionMessage(hata))
        output$cc_test_result_ui <- renderUI({
          tags$div(
            style = "font-size: 12px; color: #E57373; margin-top: 8px;",
            icon("exclamation-triangle"),
            tags$span("Test sırasında beklenmeyen hata."),
            tags$small(temiz_hata)
          )
        })
        shinyjs::enable("cc_test_connection")
      })
    }, ignoreInit = TRUE)

    # Zaman aşımı değerini settings'e aktar
    observeEvent(input$claude_code_timeout, {
      settings$claude_code_timeout <- input$claude_code_timeout
    }, ignoreInit = TRUE)

    # Koordinatöre döndürülecek değerler
    return(list(
      save_trigger = save_trigger,
      reset_trigger = reset_trigger,
      temp_model_selection = temp_model_selection,
      temp_image_size = temp_image_size,
      temp_image_quality_hd = temp_image_quality_hd,
      temp_summary_detail_level = temp_summary_detail_level,
      temp_summary_focus_mode = temp_summary_focus_mode,
      temp_analysis_deep_thinking = temp_analysis_deep_thinking,
      temp_analysis_detail_level = temp_analysis_detail_level
    ))
  })
}
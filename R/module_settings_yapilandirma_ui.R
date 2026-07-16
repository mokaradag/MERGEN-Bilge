# ==============================================================================
# Dosya Yolu: R/module_settings_yapilandirma_ui.R
# Açıklama: Ayarlar sayfasının "Yapılandırma" alt sekmesi UI tanımı. Sunucu
#            mantığı R/module_settings_yapilandirma.R içinde kalır.
#            settingsYapilandirmaUIImpl(id) ince bir kompozitördür; her ayar
#            kartı odaklı, saf bir .syap_*(ns) yapıcısına bölünmüştür. Üretilen
#            tag ağacı ve sunucuya bağlanan tüm ns kimlikleri birebir korunur
#            (bkz. tests/testthat/test-settings-yapilandirma-ui-id-surface-behavior.R).
# ==============================================================================

#' Yapılandırma Alt Sekmesi UI Uygulaması
#'
#' @param id Modül ad alanı kimliği
#' @return Yapılandırma sekmesi için UI tanımı
settingsYapilandirmaUIImpl <- function(id) {
  ns <- NS(id)

  tagList(
    div(
      class = "settings-container",
      .syap_header_row(ns),
      div(
        class = "settings-scrollable-content",
        fluidRow(
          column(
            width = 12,
            .syap_model_card(ns),
            .syap_api_key_card(ns),
            .syap_tools_card(ns),
            .syap_claude_code_card(ns),
            .syap_interface_shortcuts_row(ns),
            .syap_startup_lane_card(ns),
            .syap_audio_card(ns),
            .syap_ai_expert_card(ns),
            .syap_image_card(ns),
            .syap_summarization_card(ns),
            .syap_analysis_card(ns)
          )
        )
      )
    )
  )
}

.syap_header_row <- function(ns) {
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
          actionButton(
            ns("save_settings"),
            label = tagList(icon("save"), "Ayarları Kaydet"),
            class = "btn-modern btn-primary"
          ),
          actionButton(
            ns("reset_settings"),
            label = tagList(icon("undo"), "Varsayılana Dön"),
            class = "btn-modern btn-secondary"
          )
        )
      )
    )
  )
}

.syap_model_card <- function(ns) {
  div(
    class = "settings-card",
    h3("Model Ayarları", class = "settings-title"),
    fluidRow(
      column(
        width = 3,
        h4("Model Seçimi", class = "setting-subtitle"),
        p(
          "Kullanmak istediğiniz modeli seçin.",
          class = "setting-description",
          style = "margin-top:4px;"
        ),
        div(
          class = "setting-item",
          style = "max-width: 250px;",
          {
            model_ids <- unname(api_config$local_models)
            model_labels <- names(api_config$local_models)

            model_choices_with_icons <- stats::setNames(
              object = model_ids,
              nm = vapply(seq_along(model_ids), function(i) {
                model_id <- model_ids[i]
                model_label <- model_labels[i]
                model_icon <- api_config$local_model_icons[[model_id]] %||% ""
                trimws(paste(model_icon, model_label))
              }, character(1))
            )

            selectInput(
              inputId   = ns("model_selection"),
              label     = NULL,
              choices   = model_choices_with_icons,
              selected  = model_ids[1],
              width     = "100%",
              selectize = FALSE
            )
          }
        )
      ),
      column(
        width = 5,
        h4("Model Bilgisi", class = "setting-subtitle"),
        div(
          class = "model-info-panel",
          id = ns("model_info_panel"),
          `data-model-meta` = {
            model_meta <- list()
            for (mid in api_config$local_models) {
              caps <- api_config$local_model_capabilities[[mid]]
              model_meta[[mid]] <- list(
                description  = api_config$local_model_descriptions[[mid]] %||% "",
                context_size = api_config$local_model_context_sizes[[mid]] %||% "",
                thinking     = isTRUE(caps$thinking),
                icon         = api_config$local_model_icons[[mid]] %||% ""
              )
            }
            as.character(jsonlite::toJSON(model_meta, auto_unbox = TRUE))
          },
          div(class = "model-info-description", id = ns("model_info_desc")),
          div(
            class = "model-info-badges",
            div(
              class = "model-badge context-badge",
              title = "Bağlam penceresi boyutu",
              tags$i(class = "fas fa-microchip"),
              tags$span(class = "context-value", "-")
            ),
            div(
              class = "model-badge thinking-badge thinking-inactive",
              title = "Düşünme (thinking) yeteneği",
              tags$i(class = "fas fa-brain"),
              tags$span(class = "thinking-label", "Düşünme")
            )
          )
        )
      ),
      column(
        width = 4,
        div(
          class = "setting-item followup-toggle",
          h4("Yanıt Sonrası Öneriler", class = "setting-subtitle"),
          p(
            "Model yanıtlarının sonunda otomatik takip soruları görüntüleyin.",
            class = "setting-description",
            style = "margin-top:4px;"
          ),
          div(
            class = "checkbox-item followup-checkbox",
            checkboxInput(
              inputId = ns("enable_followups"),
              label = tags$span("Takip sorusu önerilerini göster"),
              value = FALSE
            )
          )
        )
      )
    )
  )
}

.syap_api_key_card <- function(ns) {
  div(
    class = "settings-card",
    h3("API Anahtarı Yönetimi", class = "settings-title"),
    fluidRow(
      column(
        width = 6,
        h4("API Anahtarını Güncelle", class = "setting-subtitle"),
        p(
          "LLM erişimi için kişisel API anahtarınızı yönetin.",
          class = "setting-description"
        ),
        div(
          class = "setting-item",
          div(
            style = "display:flex; flex-direction:row; gap:12px; align-items:center; flex-wrap:wrap;",
            actionButton(
              ns("update_api_key_btn"),
              label = tagList(icon("key"), "API Anahtarını Güncelle"),
              class = "btn-modern btn-warning"
            ),
            tags$a(
              href = getOption(
                "mergen.rate_limit_url",
                Sys.getenv("SERVICE_DESK_RATE_LIMIT_URL", "https://service-desk.example.com/rate-limit")
              ),
              target = "_blank",
              class = "btn-modern btn-rate",
              tagList(icon("gauge-high"), span("Rate Limit Artışı"))
            )
          )
        )
      )
    )
  )
}

.syap_tools_card <- function(ns) {
  div(
    class = "settings-card tool-selector-card",
    h3("Analiz Araçları", class = "settings-title"),
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
    div(
      class = "tool-selector-buttons",
      id = ns("tool_buttons")
    ),
    div(
      class = "tool-description-area",
      p(
        class = "tool-desc-subtext",
        "Analiz araçları, yapay zeka modelinin harici veri kaynakları ve uzman yetenekleri ile etkileşime girmesini sağlar. Aynı anda yalnızca bir araç aktif olabilir."
      ),
      p(class = "tool-desc-detail", id = ns("tool_desc_text"))
    )
  )
}

.syap_claude_code_card <- function(ns) {
  div(
    class = "settings-card cc-config-card",
    h3("Claude Code Yapılandırma", class = "settings-title"),
    p(
      "Claude Code CLI bağlantı ayarları, zaman aşımı ve durum bilgisi.",
      class = "setting-description"
    ),
    fluidRow(
      column(
        width = 4,
        h4("Zaman Aşımı", class = "setting-subtitle"),
        p(
          "Claude Code komutları için maksimum bekleme süresi.",
          class = "setting-description",
          style = "margin-top:4px;"
        ),
        div(
          class = "setting-item",
          style = "max-width: 200px;",
          numericInput(
            inputId = ns("claude_code_timeout"),
            label = NULL,
            value = claude_code_config$timeout_seconds,
            min = 30,
            max = 14400,
            step = 300
          ),
          tags$small(
            class = "setting-description",
            "30-14.400 saniye arası (en fazla 4 saat)"
          )
        )
      ),
      column(
        width = 4,
        h4("Bağlantı Testi", class = "setting-subtitle"),
        p(
          "Claude Code CLI erişimini test edin.",
          class = "setting-description",
          style = "margin-top:4px;"
        ),
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
      column(
        width = 4,
        h4("CLI Durumu", class = "setting-subtitle"),
        p(
          "Claude Code CLI kurulum ve erişim bilgisi.",
          class = "setting-description",
          style = "margin-top:4px;"
        ),
        uiOutput(ns("cc_cli_status_info"))
      )
    )
  )
}

.syap_interface_shortcuts_row <- function(ns) {
  fluidRow(
    class = "settings-equal-height-row",
    column(
      width = 9,
      class = "settings-equal-height-column",
      div(
        class = "settings-card settings-equal-height-card",
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
              div(class = "checkbox-item", checkboxInput(ns("enable_streaming"), "Akış Modu", value = TRUE)),
              # Araç bağlamlı sohbet arka plan animasyonları açma/kapama anahtarı.
              # Aktif olduğunda welcome ekranından bir araç seçildiğinde sohbet
              # arka planında ilgili araç temasına uygun hafif heptagon ve
              # bağlam parçacık animasyonları görüntülenir.
              div(class = "checkbox-item", checkboxInput(ns("enable_tool_backgrounds"), "Araç Arka Plan Animasyonları", value = TRUE)),
              tags$p(
                "Araç sohbetlerinde heptagon ve bağlama uygun arka plan parçacıklarını gösterir.",
                class = "setting-description",
                style = "margin-top: 2px; margin-bottom: 6px; padding-left: 24px;"
              )
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
                choices = list(
                  "Küçük (14px)" = "small",
                  "Orta (16px)" = "medium",
                  "Büyük (18px)" = "large",
                  "Çok Büyük (20px)" = "xlarge"
                ),
                selected = "medium",
                width = "100%"
              ),
              p(
                "Mesajların yazı tipi boyutunu ayarlayın",
                class = "setting-description"
              )
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
              p(
                "Uygulama açılışında derin uzay giriş ekranını gösterir",
                class = "setting-description"
              ),
              div(
                class = "checkbox-item",
                checkboxInput(
                  inputId = ns("show_api_key_onboarding"),
                  label = "API anahtarı seçim ekranını göster",
                  value = TRUE
                )
              ),
              p(
                "Kişisel API anahtarınız yoksa açılışta API anahtarı seçim ekranını gösterir. Kapatırsanız tekrar sorulmaz; varsayılan kurum anahtarıyla devam edebilirsiniz.",
                class = "setting-description"
              )
            )
          )
        )
      )
    ),
    column(
      width = 3,
      class = "settings-equal-height-column",
      div(
        class = "settings-card settings-equal-height-card",
        style = "min-height: 425px;",
        h3("Kısayollar", class = "settings-title", style = "margin-bottom: 16px;"),
        div(
          class = "shortcut-list",
          div(class = "shortcut-item", tags$kbd("Enter"), " - Mesaj gönder"),
          div(class = "shortcut-item", tags$kbd("Shift + Enter"), " - Yeni satır"),
          div(class = "shortcut-item", tags$kbd("Ctrl + Alt + U"), " - Dosya yükle"),
          div(class = "shortcut-item", tags$kbd("Ctrl + Alt + N"), " - Yeni sohbet"),
          div(class = "shortcut-item", tags$kbd("Page Up/Down"), " - Sayfa kaydır")
        )
      )
    )
  )
}
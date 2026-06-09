# ==============================================================================
# Dosya Yolu: tests/testthat/test-settings-yapilandirma-ui-id-surface-behavior.R
# Açıklama: Yapılandırma sekmesi UI'sinin (settingsYapilandirmaUIImpl) sunucuya
#           bağlanan Shiny input/output kimlik yüzeyini ve kart yapısını dondurur.
#           Bu, UI'nin küçük saf kart yapıcılarına bölünmesi sırasında hiçbir
#           kimliğin düşmediğini/yeniden adlandırılmadığını kanıtlayan
#           karakterizasyon testidir. Gerçek DB/LLM/sunucu gerektirmez; yalnızca
#           UI tagList'i render edip HTML üzerinde kimlik/yapı doğrular.
# ==============================================================================

testthat::local_edition(3)

if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

# UI render-zamanı api_config / claude_code_config / %||% global'lerine bağlıdır.
# İzole render için minimal, deterministik stub'lar hazırlanır.
.syap_render_env <- new.env(parent = globalenv())
.syap_render_env$api_config <- list(
  local_models = c("Model A" = "model-a", "Model B" = "model-b"),
  local_model_icons = list("model-a" = "A", "model-b" = ""),
  local_model_capabilities = list(
    "model-a" = list(thinking = TRUE),
    "model-b" = list(thinking = FALSE)
  ),
  local_model_descriptions = list("model-a" = "A aciklama"),
  local_model_context_sizes = list("model-a" = "32k")
)
.syap_render_env$claude_code_config <- list(timeout_seconds = 120)
.syap_render_env$`%||%` <- function(a, b) if (is.null(a)) b else a

source(
  file.path(resolve_repo_root_for_tests(), "R", "module_settings_yapilandirma_ui.R"),
  encoding = "UTF-8",
  local = .syap_render_env
)

.syap_render_html <- function(id = "cfg") {
  as.character(.syap_render_env$settingsYapilandirmaUIImpl(id))
}

# Sunucunun bağlandığı tüm ns kimlikleri (ön ek olmadan). Bölme sonrası bu kümenin
# bire bir korunması gerekir.
.syap_expected_ids <- c(
  "settings_header", "save_settings", "reset_settings",
  "model_selection", "model_info_panel", "model_info_desc", "enable_followups",
  "update_api_key_btn",
  "enable_rdata_tools", "enable_mcp_tools", "enable_summarization_tools",
  "enable_coding_tools", "enable_process_tools", "enable_app_expert_tools",
  "enable_image_tools", "tool_buttons", "tool_desc_text",
  "claude_code_timeout", "cc_test_connection", "cc_test_result_ui",
  "cc_cli_status_info",
  "enable_timestamps", "enable_typing_indicator", "enable_animations",
  "enable_widescreen", "enable_streaming", "enable_tool_backgrounds",
  "font_size", "show_intro_animation", "show_api_key_onboarding",
  "enable_tts_audio", "enable_background_music", "music_volume",
  "ai_expert_settings_card", "enable_ai_expert", "ai_expert_talk_length",
  "ai_expert_talk_frequency", "ai_expert_talk_style",
  "image_settings_card", "image_size", "image_quality_hd",
  "summarization_settings_card", "summary_detail_level", "summary_focus_mode",
  "analysis_settings_card", "analysis_deep_thinking", "analysis_detail_level"
)

test_that("Yapılandırma UI tüm beklenen ns kimliklerini üretir", {
  html <- .syap_render_html("cfg")

  missing <- .syap_expected_ids[!vapply(
    .syap_expected_ids,
    function(idx) grepl(paste0("cfg-", idx), html, fixed = TRUE),
    logical(1)
  )]

  expect_equal(
    missing,
    character(0),
    info = paste("Eksik UI kimlikleri:", paste(missing, collapse = ", "))
  )
})

test_that("Yapılandırma UI fazladan/eksik ns kimliği sızdırmaz (tam küme)", {
  html <- .syap_render_html("cfg")
  ids <- unique(regmatches(html, gregexpr("cfg-[a-zA-Z0-9_]+", html))[[1]])
  ids <- sub("^cfg-", "", ids)

  expect_setequal(ids, .syap_expected_ids)
  expect_equal(length(ids), length(.syap_expected_ids))
})

test_that("Yapılandırma UI tüm kart başlıklarını ve özel yapıları korur", {
  html <- .syap_render_html("cfg")

  card_titles <- c(
    "Model Ayarları", "API Anahtarı Yönetimi", "Analiz Araçları",
    "Claude Code Yapılandırma", "Arayüz Ayarları", "Kısayollar",
    "Ses Ayarları", "AI Uzman Konuşması", "Görsel Oluşturma Ayarları",
    "Özetleme Ayarları", "Proje ve Kaynak Analizi Ayarları"
  )

  missing_titles <- card_titles[!vapply(
    card_titles,
    function(title) grepl(title, html, fixed = TRUE),
    logical(1)
  )]

  expect_equal(
    missing_titles,
    character(0),
    info = paste("Eksik kart başlıkları:", paste(missing_titles, collapse = ", "))
  )

  # Model kartının dinamik data-model-meta JSON özelliği korunmalı.
  expect_true(grepl("data-model-meta", html, fixed = TRUE))
  expect_true(grepl("model-a", html, fixed = TRUE))

  # Eşit yükseklik satırı (Arayüz Ayarları + Kısayollar) sınıfı korunmalı.
  expect_true(grepl("settings-equal-height-row", html, fixed = TRUE))
  # Araç seçici ve tema anahtarı özel sınıfları korunmalı.
  expect_true(grepl("tool-selector-card", html, fixed = TRUE))
  expect_true(grepl("deep-thinking-switch", html, fixed = TRUE))
})

test_that("Yapılandırma UI ns kimliklerini doğru biçimde ön ekler", {
  html <- .syap_render_html("baska_id")
  expect_true(grepl("baska_id-model_selection", html, fixed = TRUE))
  expect_true(grepl("baska_id-save_settings", html, fixed = TRUE))
})

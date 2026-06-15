# ==============================================================================
# Dosya Yolu: tests/testthat/test-settings-yapilandirma-ui-cards-behavior.R
# Açıklama: Yapılandırma sekmesi UI'sini oluşturan saf kart yapıcılarını
#           (.syap_header_row / .syap_model_card / .syap_api_key_card /
#           .syap_tools_card / .syap_claude_code_card / .syap_interface_shortcuts_row /
#           .syap_audio_card / .syap_ai_expert_card / .syap_image_card /
#           .syap_summarization_card / .syap_analysis_card) TEK TEK davranışsal
#           olarak sınar. Mevcut id-surface testi yalnızca BİRLEŞİK
#           settingsYapilandirmaUIImpl çıktısını dondurur; bu test her yapıcının
#           kendi ns kimliklerini ve Türkçe kart başlığını ürettiğini ve BAŞKA
#           kartların kimliklerini SIZDIRMADIĞINI (sahiplik sınırı) kanıtlar.
#           Gerçek DB/LLM/sunucu gerektirmez; yalnızca saf UI render eder.
# ==============================================================================

testthat::local_edition(3)

testthat::skip_if_not_installed("shiny")
suppressMessages(library(shiny))

# Kart yapıcıları render-zamanı api_config / claude_code_config / %||% global'lerine
# bağlıdır. İzole, deterministik stub'larla yüklenir.
.syap_cards_env <- new.env(parent = globalenv())
.syap_cards_env$api_config <- list(
  local_models = c("Model A" = "model-a", "Model B" = "model-b"),
  local_model_icons = list("model-a" = "A", "model-b" = ""),
  local_model_capabilities = list(
    "model-a" = list(thinking = TRUE),
    "model-b" = list(thinking = FALSE)
  ),
  local_model_descriptions = list("model-a" = "A aciklama"),
  local_model_context_sizes = list("model-a" = "32k")
)
.syap_cards_env$claude_code_config <- list(timeout_seconds = 120)
.syap_cards_env$`%||%` <- function(a, b) if (is.null(a)) b else a

source(
  file.path(resolve_repo_root_for_tests(), "R", "module_settings_yapilandirma_ui.R"),
  encoding = "UTF-8",
  local = .syap_cards_env
)

# Belirli bir kart yapıcısını "cfg" ad alanıyla render edip HTML'e çevirir.
.syap_card_html <- function(fn_name, id = "cfg") {
  ns <- NS(id)
  out <- .syap_cards_env[[fn_name]](ns)
  list(tag = out, html = as.character(out))
}

# Verilen kimliklerin HEPSİ "cfg-<id>" olarak HTML'de bulunmalı.
.syap_expect_ids <- function(html, ids) {
  for (idx in ids) {
    testthat::expect_true(
      grepl(paste0("cfg-", idx), html, fixed = TRUE),
      info = paste("Beklenen kimlik bulunamadı:", idx)
    )
  }
}

# Verilen kimliklerin HİÇBİRİ HTML'de bulunmamalı (sahiplik sınırı).
.syap_expect_no_ids <- function(html, ids) {
  for (idx in ids) {
    testthat::expect_false(
      grepl(paste0("cfg-", idx), html, fixed = TRUE),
      info = paste("Bu karta ait olmayan kimlik sızdı:", idx)
    )
  }
}

test_that(".syap_header_row başlık + kaydet/sıfırla butonlarını üretir", {
  r <- .syap_card_html(".syap_header_row")
  testthat::expect_s3_class(r$tag, "shiny.tag")
  .syap_expect_ids(r$html, c("settings_header", "save_settings", "reset_settings"))
  testthat::expect_true(grepl("Yapılandırma", r$html, fixed = TRUE))
  testthat::expect_true(grepl("Ayarları Kaydet", r$html, fixed = TRUE))
  testthat::expect_true(grepl("Varsayılana Dön", r$html, fixed = TRUE))
  # Başka kartların kimlikleri bu satırda olmamalı.
  .syap_expect_no_ids(r$html, c("model_selection", "enable_tts_audio"))
})

test_that(".syap_model_card model/öneri kimliklerini ve data-model-meta üretir", {
  r <- .syap_card_html(".syap_model_card")
  .syap_expect_ids(r$html, c(
    "model_selection", "model_info_panel", "model_info_desc", "enable_followups"
  ))
  testthat::expect_true(grepl("Model Ayarları", r$html, fixed = TRUE))
  # Dinamik model meta JSON özniteliği ve stub model kimliği korunmalı.
  testthat::expect_true(grepl("data-model-meta", r$html, fixed = TRUE))
  testthat::expect_true(grepl("model-a", r$html, fixed = TRUE))
  .syap_expect_no_ids(r$html, c("update_api_key_btn", "music_volume"))
})

test_that(".syap_api_key_card güncelle butonu + rate-limit bağlantısını üretir", {
  r <- .syap_card_html(".syap_api_key_card")
  .syap_expect_ids(r$html, "update_api_key_btn")
  testthat::expect_true(grepl("API Anahtarı Yönetimi", r$html, fixed = TRUE))
  testthat::expect_true(grepl("Rate Limit", r$html, fixed = TRUE))
  .syap_expect_no_ids(r$html, c("model_selection", "image_size"))
})

test_that(".syap_tools_card yedi araç checkbox'ı + buton/desc kapsayıcılarını üretir", {
  r <- .syap_card_html(".syap_tools_card")
  .syap_expect_ids(r$html, c(
    "enable_rdata_tools", "enable_mcp_tools", "enable_summarization_tools",
    "enable_coding_tools", "enable_process_tools", "enable_app_expert_tools",
    "enable_image_tools", "tool_buttons", "tool_desc_text"
  ))
  testthat::expect_true(grepl("Analiz Araçları", r$html, fixed = TRUE))
  testthat::expect_true(grepl("tool-selector-card", r$html, fixed = TRUE))
  .syap_expect_no_ids(r$html, c("claude_code_timeout", "enable_ai_expert"))
})

test_that(".syap_claude_code_card zaman aşımı + bağlantı testi + CLI durumu kimliklerini üretir", {
  r <- .syap_card_html(".syap_claude_code_card")
  .syap_expect_ids(r$html, c(
    "claude_code_timeout", "cc_test_connection", "cc_test_result_ui", "cc_cli_status_info"
  ))
  testthat::expect_true(grepl("Claude Code Yapılandırma", r$html, fixed = TRUE))
  # claude_code_config$timeout_seconds stub değeri numericInput'a yansımalı.
  testthat::expect_true(grepl("120", r$html, fixed = TRUE))
  .syap_expect_no_ids(r$html, c("enable_image_tools", "summary_focus_mode"))
})

test_that(".syap_interface_shortcuts_row arayüz checkbox'ları + kısayol kartını üretir", {
  r <- .syap_card_html(".syap_interface_shortcuts_row")
  .syap_expect_ids(r$html, c(
    "enable_timestamps", "enable_typing_indicator", "enable_animations",
    "enable_widescreen", "enable_streaming", "enable_tool_backgrounds",
    "font_size", "show_intro_animation", "show_api_key_onboarding"
  ))
  testthat::expect_true(grepl("Arayüz Ayarları", r$html, fixed = TRUE))
  testthat::expect_true(grepl("Kısayollar", r$html, fixed = TRUE))
  # Eşit yükseklik satırı sınıfı korunmalı.
  testthat::expect_true(grepl("settings-equal-height-row", r$html, fixed = TRUE))
  .syap_expect_no_ids(r$html, c("model_selection", "ai_expert_talk_style"))
})

test_that(".syap_audio_card TTS/müzik/ses-seviyesi kimliklerini üretir", {
  r <- .syap_card_html(".syap_audio_card")
  .syap_expect_ids(r$html, c("enable_tts_audio", "enable_background_music", "music_volume"))
  testthat::expect_true(grepl("Ses Ayarları", r$html, fixed = TRUE))
  .syap_expect_no_ids(r$html, c("enable_ai_expert", "analysis_deep_thinking"))
})

test_that(".syap_ai_expert_card AI uzman kart + dört ayar kimliğini üretir", {
  r <- .syap_card_html(".syap_ai_expert_card")
  .syap_expect_ids(r$html, c(
    "ai_expert_settings_card", "enable_ai_expert", "ai_expert_talk_length",
    "ai_expert_talk_frequency", "ai_expert_talk_style"
  ))
  testthat::expect_true(grepl("AI Uzman Konuşması", r$html, fixed = TRUE))
  .syap_expect_no_ids(r$html, c("image_size", "summary_detail_level"))
})

test_that(".syap_image_card görsel boyut/kalite kimliklerini üretir", {
  r <- .syap_card_html(".syap_image_card")
  .syap_expect_ids(r$html, c("image_settings_card", "image_size", "image_quality_hd"))
  testthat::expect_true(grepl("Görsel Oluşturma Ayarları", r$html, fixed = TRUE))
  .syap_expect_no_ids(r$html, c("summary_focus_mode", "analysis_detail_level"))
})

test_that(".syap_summarization_card detay/odak kimliklerini üretir", {
  r <- .syap_card_html(".syap_summarization_card")
  .syap_expect_ids(r$html, c(
    "summarization_settings_card", "summary_detail_level", "summary_focus_mode"
  ))
  testthat::expect_true(grepl("Özetleme Ayarları", r$html, fixed = TRUE))
  .syap_expect_no_ids(r$html, c("image_size", "analysis_deep_thinking"))
})

test_that(".syap_analysis_card derin düşünme + detay kimliklerini üretir", {
  r <- .syap_card_html(".syap_analysis_card")
  .syap_expect_ids(r$html, c(
    "analysis_settings_card", "analysis_deep_thinking", "analysis_detail_level"
  ))
  testthat::expect_true(grepl("Proje ve Kaynak Analizi Ayarları", r$html, fixed = TRUE))
  # Derin düşünme anahtarı özel sınıfı korunmalı.
  testthat::expect_true(grepl("deep-thinking-switch", r$html, fixed = TRUE))
  .syap_expect_no_ids(r$html, c("summary_detail_level", "enable_tts_audio"))
})

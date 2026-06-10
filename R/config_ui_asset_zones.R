# ==============================================================================
# Dosya Yolu: R/config_ui_asset_zones.R
# Açıklama: Frontend bölge (zone) sahiplik haritası.
#           R/config_ui_assets.R manifestindeki HER CSS/JS varlığı tam olarak
#           BİR bölgeye aittir; her bölgenin sahibi bir seam'dir
#           (R/config_seam_registry.R) ve en az bir guard testi vardır.
#
#           Bu dosya çalışma zamanı davranışını DEĞİŞTİRMEZ: yükleme sırasının
#           tek sahibi R/config_ui_assets.R olmaya devam eder. Buradaki harita
#           yalnızca sahiplik/sorumluluk bildirir ve sözleşme testleriyle
#           manifest'e karşı bölümleme (partition) olarak doğrulanır.
#
#           Kurallar:
#             - Manifest'e yeni bir CSS/JS varlığı eklendiğinde buradaki bir
#               bölgeye de atanmalıdır; aksi halde sözleşme testi düşer.
#             - Manifest dışı ama runtime'da kullanılan (inline/tags$head)
#               varlıklar ui_asset_unmanifested_ownership içinde sahiplenilir.
#             - www/smoke/* dosyaları üretim manifestine ASLA eklenmez; burada
#               yalnızca sahiplik kaydı tutulur.
#
#           Koruyan sözleşme testi: tests/testthat/test-ui-asset-zones-contract.R
# ==============================================================================

ui_asset_ownership_zones <- list(
  vendor_codemirror = list(
    title = "CodeMirror (vendor)",
    owner_seam = "frontend_varlik",
    css_groups = c("codemirror"),
    js_groups = c("codemirror_core", "codemirror_modes", "codemirror_addons"),
    css = character(0),
    js = character(0),
    guard_tests = c("tests/testthat/test-ui-asset-manifest-contract.R")
  ),

  vendor_threejs = list(
    title = "Three.js (vendor)",
    owner_seam = "frontend_varlik",
    css_groups = character(0),
    js_groups = c("threejs"),
    css = character(0),
    js = character(0),
    guard_tests = c("tests/testthat/test-ui-asset-manifest-contract.R")
  ),

  vendor_ikon_fontlari = list(
    title = "İkon fontları (vendor, çevrimdışı)",
    owner_seam = "frontend_varlik",
    css_groups = character(0),
    js_groups = character(0),
    css = c("css/all.min.css"),
    js = character(0),
    guard_tests = c("tests/testthat/test-runtime-network-boundary-contract.R")
  ),

  tanilama = list(
    title = "Tanılama (konsol hata probu)",
    owner_seam = "frontend_varlik",
    css_groups = character(0),
    js_groups = character(0),
    css = character(0),
    js = c("js/console_error_probe.js"),
    guard_tests = c("tests/testthat/test-ui-asset-manifest-contract.R")
  ),

  kimlik_oturum = list(
    title = "SSO kimlik ve kenar çubuğu kullanıcı paneli",
    owner_seam = "kimlik_sso",
    css_groups = character(0),
    js_groups = character(0),
    css = c("css/sso_auth.css", "css/sidebar_user_panel.css"),
    js = c("js/sso_auth.js"),
    guard_tests = c(
      "tests/testthat/test-sidebar-user-display-split-contract.R",
      "tests/testthat/test-e2e-sso-identity-readiness-regression.R"
    )
  ),

  cekirdek_kabuk = list(
    title = "Çekirdek uygulama kabuğu ve genel yüzeyler",
    owner_seam = "shiny_calisma_zamani",
    css_groups = character(0),
    js_groups = character(0),
    css = c(
      "css/fonts.css",
      "css/animations.css",
      "css/layout.css",
      "css/components.css",
      "css/datatables.css",
      "css/date_picker.css",
      "css/disconnect_overlay.css",
      "css/custom_buttons.css",
      "css/utilities.css",
      "css/responsive.css",
      "css/accessibility.css",
      "css/layout_overrides.css",
      "css/pagination_custom.css",
      "css/modals_custom.css",
      "css/empty_state.css",
      "css/animations_extra.css"
    ),
    js = c(
      "js/utils.js",
      "js/ui_init.js",
      "js/interaction_handlers.js",
      "js/app_core.js",
      "js/toast.js",
      "js/layout-manager.js",
      "js/shortcuts_manager.js"
    ),
    guard_tests = c(
      "tests/testthat/test-frontend-selector-contract.R",
      "tests/testthat/test-accessibility-contract.R"
    )
  ),

  tema = list(
    title = "Tema sistemi (koyu varsayılan + açık tema katmanları)",
    owner_seam = "frontend_varlik",
    css_groups = character(0),
    js_groups = character(0),
    css = c(
      "css/variables.css",
      "css/theme_tokens.css",
      "css/theme_light.css",
      "css/theme_light_extras.css",
      "css/theme_light_refinements.css",
      "css/theme_light_welcome.css",
      "css/theme_light_chat.css",
      "css/theme_light_modals.css",
      "css/theme_light_bilge_yolac.css",
      "css/theme_light_personalization.css",
      "css/theme_light_polish.css",
      "css/theme_light_overhaul.css",
      "css/theme_light_overhaul_phase2.css",
      "css/theme_light_user_polish.css",
      "css/theme_light_user_polish_v2.css",
      "css/brand_title.css"
    ),
    js = c("js/theme_manager.js"),
    guard_tests = c(
      "tests/testthat/test-ui-asset-manifest-contract.R",
      "tests/testthat/test-brand-title-single-source-contract.R",
      "tests/testthat/test-sidebar-theme-sync-contract.R"
    )
  ),

  kodlama_metin = list(
    title = "İstemci tarafı encoding/mojibake savunması",
    owner_seam = "veritabani_kodlama",
    css_groups = character(0),
    js_groups = character(0),
    css = character(0),
    js = c("js/encoding_utils.js"),
    guard_tests = c("tests/testthat/test-ui-asset-manifest-contract.R")
  ),

  shiny_mesaj_koprusu = list(
    title = "Shiny özel mesaj köprüsü",
    owner_seam = "shiny_calisma_zamani",
    css_groups = character(0),
    js_groups = character(0),
    css = character(0),
    js = c("js/shiny_message_handlers.js"),
    guard_tests = c(
      "tests/testthat/test-ui-asset-manifest-contract.R",
      "tests/testthat/test-frontend-selector-contract.R"
    )
  ),

  akis_markdown_guvenligi = list(
    title = "Streaming ve markdown HTML güvenlik sınırı",
    owner_seam = "sohbet_llm_akis",
    css_groups = character(0),
    js_groups = character(0),
    css = c("css/premium_reasoning.css"),
    js = c(
      "js/streaming_markdown_safety.js",
      "js/markdown-parser.js",
      "js/streaming_manager.js",
      "js/premium_reasoning.js"
    ),
    guard_tests = c(
      "tests/testthat/test-streaming-markdown-safety-contract.R",
      "tests/testthat/test-e2e-streaming-client-request-id-regression.R",
      "tests/testthat/test-e2e-premium-reasoning-ui-regression.R"
    )
  ),

  sohbet_girisi_mesajlar = list(
    title = "Sohbet girişi, mesaj görünümü ve kod blokları",
    owner_seam = "sohbet_llm_akis",
    css_groups = character(0),
    js_groups = character(0),
    css = c(
      "css/model_selector.css",
      "css/codemirror-custom.css",
      "css/code_highlighting.css",
      "css/chat_messages.css",
      "css/chat_input.css",
      "css/chat_header.css",
      "css/message_actions.css",
      "css/code_collapse.css",
      "css/citation_styles.css",
      "css/capabilities.css"
    ),
    js = c(
      "js/input_handlers.js",
      "js/code-collapse.js",
      "js/table_scroll_handler.js",
      "js/codemirror-manager.js",
      "js/citation_handler.js"
    ),
    guard_tests = c(
      "tests/testthat/test-frontend-selector-contract.R",
      "tests/testthat/test-accessibility-contract.R"
    )
  ),

  karsilama_intro = list(
    title = "Karşılama ekranı, intro ve persona deneyimi",
    owner_seam = "kimlik_sso",
    css_groups = character(0),
    js_groups = character(0),
    css = c(
      "css/welcome_modern.css",
      "css/welcome_greeting_personal.css",
      "css/character-selector.css",
      "css/character_video.css",
      "css/welcome_screen.css",
      "css/cinematic_intro.css",
      "css/deep_space_intro.css",
      "css/mode_selection.css",
      "css/explore_cinematic.css",
      "css/quick_templates.css",
      "css/welcome_styles.css",
      "css/recent_chats_custom.css",
      "css/explore_character_step.css"
    ),
    js = c(
      "js/welcome_tooltip_manager.js",
      "js/cinematic_video.js",
      "js/character_typing.js",
      "js/intro_animation.js",
      "js/neural_welcome.js",
      "js/welcome_video_player.js",
      "js/welcome_neural_modern.js",
      "js/welcome_greeting.js",
      "js/welcome_greeting_personal.js",
      "js/character_manager.js",
      "js/deep_space_intro_earth_shader.js",
      "js/deep_space_intro_solar.js",
      "js/deep_space_intro.js",
      "js/mode_selection.js",
      "js/explore_cinematic.js",
      "js/explore_character_video.js",
      "js/explore_character_step.js"
    ),
    guard_tests = c(
      "tests/testthat/test-e2e-boot-welcome-regression.R",
      "tests/testthat/test-ux-regression-guardrails.R"
    )
  ),

  arac_arka_plan = list(
    title = "Araç bağlamsal arka plan animasyonları",
    owner_seam = "kimlik_sso",
    css_groups = character(0),
    js_groups = character(0),
    css = c("css/tool_backgrounds.css"),
    js = c("js/tool_backgrounds_snippets.js", "js/tool_backgrounds.js"),
    guard_tests = c("tests/testthat/test-tool-backgrounds-contract.R")
  ),

  ses_yasam_dongusu = list(
    title = "TTS/STT/müzik ses yaşam döngüsü ve AI Uzman",
    owner_seam = "medya_ses",
    css_groups = character(0),
    js_groups = character(0),
    css = c(
      "css/tts_visualizer.css",
      "css/stt.css",
      "css/music_slider.css",
      "css/ai_expert_subtitle.css"
    ),
    js = c(
      "js/tts_visualizer.js",
      "js/music_manager.js",
      "js/audio_lifecycle_guard.js",
      "js/stt_client.js",
      "js/tts_manager.js",
      "js/ai_expert_manager.js",
      "js/space_intro_music.js"
    ),
    guard_tests = c(
      "tests/testthat/test-e2e-media-audio-state-regression.R",
      "tests/testthat/test-audio-lifecycle-owner-smoke.R"
    )
  ),

  dosya_yonetimi = list(
    title = "Dosya Yönetimi ön yüzü",
    owner_seam = "dosya_yasam_dongusu",
    css_groups = character(0),
    js_groups = character(0),
    css = c("css/file_manager.css"),
    js = c("js/file_handlers.js"),
    guard_tests = c(
      "tests/testthat/test-file-manager-display-name-contract.R",
      "tests/testthat/test-frontend-selector-contract.R"
    )
  ),

  gorsel_uretim_galeri = list(
    title = "Görsel üretimi ve Görsel Galerisi",
    owner_seam = "medya_ses",
    css_groups = character(0),
    js_groups = character(0),
    css = c("css/image_tools.css", "css/image_gallery.css"),
    js = c("js/image_tools.js", "js/image_gallery.js"),
    guard_tests = c("tests/testthat/test-generated-image-card-html-contract.R")
  ),

  ozetleme_analiz = list(
    title = "Özetleme, analiz araçları ve ChartLab render",
    owner_seam = "mcp_analiz",
    css_groups = character(0),
    js_groups = character(0),
    css = c(
      "css/summarization_tools.css",
      "css/analysis_tools.css",
      "css/tools_model_lock.css",
      "css/mcp_indicator.css"
    ),
    js = c(
      "js/summarization_tools.js",
      "js/analysis_tools.js",
      "js/excel_coding_deep_thinking.js",
      "js/tools_model_lock.js",
      "js/chart_renderer.js"
    ),
    guard_tests = c(
      "tests/testthat/test-frontend-selector-contract.R",
      "tests/testthat/test-quick-action-routing.R"
    )
  ),

  gecmis_kayit_arama = list(
    title = "Söyleşi geçmişi, kayıtlı söyleşiler ve arama",
    owner_seam = "sohbet_llm_akis",
    css_groups = character(0),
    js_groups = character(0),
    css = c("css/history_saved_chats.css", "css/chat_search_modal.css"),
    js = c("js/history_date_range.js", "js/chat_search_modal.js"),
    guard_tests = c("tests/testthat/test-chat-history-datatable-safety-contract.R")
  ),

  ayarlar_api_anahtar = list(
    title = "Ayarlar sayfaları ve API anahtarı modalı",
    owner_seam = "api_anahtar_model",
    css_groups = character(0),
    js_groups = character(0),
    css = c(
      "css/settings_page.css",
      "css/settings_tools.css",
      "css/settings_model_info.css",
      "css/api_key_choice_modal.css",
      "css/api_key_password_toggle.css"
    ),
    js = c(
      "js/settings_tools.js",
      "js/settings_model_info.js",
      "js/api_key_choice_modal.js"
    ),
    guard_tests = c("tests/testthat/test-api-key-choice-modal-contract.R")
  ),

  geri_bildirim_destek = list(
    title = "Geri bildirim, destek sayfaları ve Yenilikler",
    owner_seam = "destek_yonetici_saglik",
    css_groups = character(0),
    js_groups = character(0),
    css = c(
      "css/feedback_modal.css",
      "css/destek_page.css",
      "css/destek_yardim_chatbot.css",
      "css/surum_bilgilendirme.css"
    ),
    js = c(
      "js/feedback_modal.js",
      "js/destek_form.js",
      "js/destek_yardim_chatbot.js",
      "js/surum_bilgilendirme.js"
    ),
    guard_tests = c("tests/testthat/test-accessibility-contract.R")
  ),

  yonetici_saglik = list(
    title = "Yönetici panelleri ve Sistem Durumu panosu",
    owner_seam = "destek_yonetici_saglik",
    css_groups = character(0),
    js_groups = character(0),
    css = c(
      "css/health_check.css",
      "css/health_dashboard.css",
      "css/admin_destek_analytics.css",
      "css/admin_yanit_analizi.css",
      "css/admin_documentation.css"
    ),
    js = c("js/health_dashboard.js", "js/admin_documentation.js"),
    guard_tests = c("tests/testthat/test-e2e-health-dashboard-regression.R")
  ),

  bilge_yolac_calisma = list(
    title = "Bilge Yolaç çalışma alanı ve streaming",
    owner_seam = "bilge_yolac",
    css_groups = character(0),
    js_groups = character(0),
    css = c(
      "css/claude_code.css",
      "css/claude_code_generated_files.css",
      "css/claude_code_streaming.css",
      "css/claude_code_plugins.css"
    ),
    js = c(
      "js/claude_code_pixel_chars.js",
      "js/claude_code.js",
      "js/claude_code_streaming.js",
      "js/claude_code_plugins.js"
    ),
    guard_tests = c(
      "tests/testthat/test-claude-code-stream-html-safety-contract.R"
    )
  ),

  bilge_yolac_oyun = list(
    title = "Bilge Yolaç oyun ve karşılama katmanı",
    owner_seam = "bilge_yolac",
    css_groups = character(0),
    js_groups = c("bilge_yolac"),
    css = c("css/bilge_yolac_welcome.css"),
    js = character(0),
    guard_tests = c("tests/testthat/test-frontend-maintainability-ratchet.R")
  )
)

# Manifest DIŞI ama runtime'da bilinçli olarak kullanılan ya da smoke-only
# olan frontend dosyalarının sahiplik kaydı. Buradaki yollar www/ köküne
# görelidir ve ASLA R/config_ui_assets.R manifestine eklenmemelidir.
ui_asset_unmanifested_ownership <- list(
  "css/admin_analytics.css" = list(
    owner_seam = "destek_yonetici_saglik",
    reason = "R/helpers_admin_analytics.R tags$head ile sayfa-yerel yükler."
  ),
  "css/app_loading.css" = list(
    owner_seam = "kimlik_sso",
    reason = "R/module_app_loading.R başlangıç overlay'inde inline gömer."
  ),
  "js/app_loading.js" = list(
    owner_seam = "kimlik_sso",
    reason = "R/module_app_loading.R başlangıç overlay'inde inline gömer."
  ),
  "js/app_loading_codestream.js" = list(
    owner_seam = "kimlik_sso",
    reason = "R/module_app_loading.R başlangıç overlay'inde inline gömer."
  ),
  "js/app_loading_snippets.js" = list(
    owner_seam = "kimlik_sso",
    reason = "R/module_app_loading.R başlangıç overlay'inde inline gömer."
  ),
  "js/app_loading_content.js" = list(
    owner_seam = "kimlik_sso",
    reason = "R/module_app_loading.R başlangıç overlay'inde inline gömer."
  ),
  "js/app_loading_media.js" = list(
    owner_seam = "kimlik_sso",
    reason = "R/module_app_loading.R başlangıç overlay'inde inline gömer."
  ),
  "smoke/ux-smoke.html" = list(
    owner_seam = "frontend_varlik",
    reason = "Smoke-only tarayıcı harness'ı; üretim manifestine eklenmez."
  ),
  "smoke/ux-smoke-probes.js" = list(
    owner_seam = "frontend_varlik",
    reason = "Smoke-only probe katmanı; üretim manifestine eklenmez."
  )
)

ui_asset_zone_ids <- function(zones = ui_asset_ownership_zones) {
  names(zones)
}

ui_asset_zone_get <- function(id, zones = ui_asset_ownership_zones) {
  if (!is.character(id) || length(id) != 1L || !nzchar(id)) {
    stop("Bölge id tek bir boş olmayan karakter değeri olmalıdır.", call. = FALSE)
  }

  zone <- zones[[id]]

  if (is.null(zone)) {
    stop(sprintf("Frontend bölge haritasında bulunamadı: %s", id), call. = FALSE)
  }

  zone
}

# Bir bölgenin CSS yollarını çözer: açık liste + manifest grup referansları.
ui_asset_zone_css_paths <- function(zone, css_groups = ui_asset_css_groups) {
  paths <- zone$css

  for (group_name in zone$css_groups) {
    group_paths <- css_groups[[group_name]]

    if (is.null(group_paths)) {
      stop(sprintf("Bölge bilinmeyen CSS grubuna işaret ediyor: %s", group_name), call. = FALSE)
    }

    paths <- c(paths, unname(unlist(group_paths, use.names = FALSE)))
  }

  paths
}

# Bir bölgenin JS yollarını çözer: açık liste + manifest grup referansları.
ui_asset_zone_js_paths <- function(zone, js_groups = ui_asset_js_groups) {
  paths <- zone$js

  for (group_name in zone$js_groups) {
    group_paths <- js_groups[[group_name]]

    if (is.null(group_paths)) {
      stop(sprintf("Bölge bilinmeyen JS grubuna işaret ediyor: %s", group_name), call. = FALSE)
    }

    paths <- c(paths, unname(unlist(group_paths, use.names = FALSE)))
  }

  paths
}

# Bölge -> sahip seam haritası. Seam kayıt defteri doğrulaması, buradaki
# sahiplerin gerçek seam id'leri olduğunu çapraz kontrol eder.
ui_asset_zone_owner_seams <- function(zones = ui_asset_ownership_zones) {
  owners <- character(0)

  for (zone_id in names(zones)) {
    owners <- c(owners, stats::setNames(zones[[zone_id]]$owner_seam, zone_id))
  }

  owners
}

# Verilen seam'in sahiplendiği bölge id'lerini türetir (tek kaynak: zones).
ui_asset_zones_for_seam <- function(seam_id, zones = ui_asset_ownership_zones) {
  owners <- ui_asset_zone_owner_seams(zones)
  names(owners[owners == seam_id])
}

# Saf bölümleme doğrulaması: manifest CSS/JS listeleri ile bölge haritası
# birebir örtüşmelidir. Sorun yoksa character(0) döner.
ui_asset_zones_validate <- function(zones = ui_asset_ownership_zones,
                                    css_paths = ui_asset_all_css(),
                                    js_paths = ui_asset_all_js(),
                                    css_groups = ui_asset_css_groups,
                                    js_groups = ui_asset_js_groups,
                                    unmanifested = ui_asset_unmanifested_ownership,
                                    repo_root = NULL) {
  problems <- character(0)

  if (!is.list(zones) || length(zones) == 0L) {
    return("Frontend bölge haritası boş olmayan bir liste olmalıdır.")
  }

  zone_ids <- names(zones)

  if (is.null(zone_ids) || any(!nzchar(zone_ids)) || anyDuplicated(zone_ids) > 0L) {
    problems <- c(problems, "Frontend bölgeleri benzersiz ve boş olmayan adlarla adlandırılmalıdır.")
  }

  required_fields <- c("title", "owner_seam", "css_groups", "js_groups", "css", "js", "guard_tests")

  zone_css <- character(0)
  zone_js <- character(0)

  for (zone_id in zone_ids) {
    zone <- zones[[zone_id]]

    missing_fields <- setdiff(required_fields, names(zone))

    if (length(missing_fields) > 0L) {
      problems <- c(problems, sprintf(
        "Bölge '%s' zorunlu alanları eksik: %s",
        zone_id,
        paste(missing_fields, collapse = ", ")
      ))
      next
    }

    if (!is.character(zone$owner_seam) || length(zone$owner_seam) != 1L || !nzchar(zone$owner_seam)) {
      problems <- c(problems, sprintf("Bölge '%s' için owner_seam tek seam id olmalıdır.", zone_id))
    }

    if (!is.character(zone$guard_tests) || length(zone$guard_tests) == 0L) {
      problems <- c(problems, sprintf("Bölge '%s' en az bir guard testi bildirmelidir.", zone_id))
    }

    resolved_css <- tryCatch(
      ui_asset_zone_css_paths(zone, css_groups = css_groups),
      error = function(e) {
        problems <<- c(problems, sprintf("Bölge '%s': %s", zone_id, conditionMessage(e)))
        character(0)
      }
    )

    resolved_js <- tryCatch(
      ui_asset_zone_js_paths(zone, js_groups = js_groups),
      error = function(e) {
        problems <<- c(problems, sprintf("Bölge '%s': %s", zone_id, conditionMessage(e)))
        character(0)
      }
    )

    zone_css <- c(zone_css, resolved_css)
    zone_js <- c(zone_js, resolved_js)
  }

  duplicate_css <- sort(unique(zone_css[duplicated(zone_css)]))
  duplicate_js <- sort(unique(zone_js[duplicated(zone_js)]))

  if (length(duplicate_css) > 0L) {
    problems <- c(problems, sprintf(
      "CSS varlığı birden fazla bölgeye atanmış: %s",
      paste(duplicate_css, collapse = ", ")
    ))
  }

  if (length(duplicate_js) > 0L) {
    problems <- c(problems, sprintf(
      "JS varlığı birden fazla bölgeye atanmış: %s",
      paste(duplicate_js, collapse = ", ")
    ))
  }

  missing_css <- setdiff(css_paths, zone_css)
  unknown_css <- setdiff(zone_css, css_paths)
  missing_js <- setdiff(js_paths, zone_js)
  unknown_js <- setdiff(zone_js, js_paths)

  if (length(missing_css) > 0L) {
    problems <- c(problems, sprintf(
      "Sahipsiz manifest CSS varlığı var (bir bölgeye atayın): %s",
      paste(missing_css, collapse = ", ")
    ))
  }

  if (length(unknown_css) > 0L) {
    problems <- c(problems, sprintf(
      "Bölge haritası manifestte olmayan CSS varlığına işaret ediyor: %s",
      paste(unknown_css, collapse = ", ")
    ))
  }

  if (length(missing_js) > 0L) {
    problems <- c(problems, sprintf(
      "Sahipsiz manifest JS varlığı var (bir bölgeye atayın): %s",
      paste(missing_js, collapse = ", ")
    ))
  }

  if (length(unknown_js) > 0L) {
    problems <- c(problems, sprintf(
      "Bölge haritası manifestte olmayan JS varlığına işaret ediyor: %s",
      paste(unknown_js, collapse = ", ")
    ))
  }

  unmanifested_paths <- names(unmanifested)
  overlap_with_manifest <- intersect(unmanifested_paths, c(css_paths, js_paths))

  if (length(overlap_with_manifest) > 0L) {
    problems <- c(problems, sprintf(
      "Manifest dışı sahiplik kaydı manifestte de listelenmiş: %s",
      paste(overlap_with_manifest, collapse = ", ")
    ))
  }

  for (path in unmanifested_paths) {
    entry <- unmanifested[[path]]

    if (!is.list(entry) ||
        !is.character(entry$owner_seam) ||
        length(entry$owner_seam) != 1L ||
        !nzchar(entry$owner_seam) ||
        !is.character(entry$reason) ||
        length(entry$reason) != 1L ||
        !nzchar(entry$reason)) {
      problems <- c(problems, sprintf(
        "Manifest dışı sahiplik kaydı owner_seam ve reason alanlarını içermelidir: %s",
        path
      ))
    }
  }

  if (!is.null(repo_root)) {
    guard_files <- character(0)

    for (zone_id in zone_ids) {
      guard_files <- c(guard_files, zones[[zone_id]]$guard_tests)
    }

    guard_files <- unique(guard_files)
    missing_guards <- guard_files[!file.exists(file.path(repo_root, guard_files))]

    if (length(missing_guards) > 0L) {
      problems <- c(problems, sprintf(
        "Bölge guard testleri repoda yok: %s",
        paste(missing_guards, collapse = ", ")
      ))
    }

    missing_unmanifested <- unmanifested_paths[
      !file.exists(file.path(repo_root, "www", unmanifested_paths))
    ]

    if (length(missing_unmanifested) > 0L) {
      problems <- c(problems, sprintf(
        "Manifest dışı sahiplik kaydındaki dosya repoda yok: %s",
        paste(missing_unmanifested, collapse = ", ")
      ))
    }
  }

  problems
}

# www/css ve www/js altındaki fiziksel dosyalar için sahiplik boşluğu raporu.
# Bir dosya ya manifest bölgesi üzerinden ya da manifest dışı sahiplik
# kaydıyla sahiplenilmelidir. Boşluk yoksa character(0) döner.
ui_asset_frontend_ownership_gaps <- function(repo_root = getwd(),
                                             zones = ui_asset_ownership_zones,
                                             css_paths = ui_asset_all_css(),
                                             js_paths = ui_asset_all_js(),
                                             unmanifested = ui_asset_unmanifested_ownership) {
  www_root <- file.path(repo_root, "www")

  physical <- character(0)

  for (sub in c("css", "js")) {
    sub_dir <- file.path(www_root, sub)

    if (!dir.exists(sub_dir)) {
      next
    }

    files <- list.files(sub_dir, pattern = "\\.(css|js)$", recursive = FALSE)

    if (length(files) > 0L) {
      physical <- c(physical, file.path(sub, files))
    }
  }

  owned <- c(css_paths, js_paths, names(unmanifested))

  sort(setdiff(physical, owned))
}

# ==============================================================================
# Dosya Yolu: R/config_ui_asset_zones.R
# Açıklama: Frontend bölge (zone) sahiplik haritası — SAF VERİ.
#           R/config_ui_assets.R manifestindeki HER CSS/JS varlığı tam olarak
#           BİR bölgeye aittir; her bölgenin sahibi bir seam'dir
#           (R/config_seam_registry.R) ve en az bir guard testi vardır.
#
#           Bu dosya yalnızca iki veri nesnesini barındırır:
#             - ui_asset_ownership_zones (frontend bölge -> seam/guard haritası)
#             - ui_asset_unmanifested_ownership (manifest dışı/smoke varlık kaydı)
#           Bölge çözümleme ve bölümleme (partition) doğrulama API'si (saf
#           fonksiyonlar) R/config_ui_asset_zone_validators.R dosyasındadır ve
#           bu dosyadan HEMEN SONRA yüklenir. Bu, config_source_manifest.R
#           (veri) + bootstrap_source_manifest.R (doğrulayıcı) ayrımıyla aynı
#           desendir.
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
#           Koruyan sözleşme testleri:
#             - tests/testthat/test-ui-asset-zones-contract.R
#             - tests/testthat/test-ui-asset-zone-validators-split-contract.R
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
    title = "Tema sistemi (koyu varsayılan + açık tema alan katmanları)",
    owner_seam = "frontend_varlik",
    css_groups = character(0),
    js_groups = character(0),
    css = c(
      "css/variables.css",
      "css/theme_tokens.css",
      "css/theme_light_core.css",
      "css/theme_light_welcome.css",
      "css/theme_light_chat.css",
      "css/theme_light_modals.css",
      "css/theme_light_bilge_yolac.css",
      "css/theme_light_personalization.css",
      "css/theme_light_pages.css",
      "css/brand_title.css"
    ),
    js = c("js/theme_manager.js"),
    guard_tests = c(
      "tests/testthat/test-ui-asset-manifest-contract.R",
      "tests/testthat/test-theme-light-modular-contract.R",
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
    js = c("js/shiny_message_handlers.js", "js/modern_welcome_handler.js"),
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
      "css/citation_styles.css"
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
      "js/deep_space_intro_lifecycle.js",
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
      "js/ai_expert_handlers.js",
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
      "css/process_tools.css",
      "css/analysis_tools.css",
      "css/tools_model_lock.css",
      "css/mcp_indicator.css"
    ),
    js = c(
      "js/summarization_tools.js",
      "js/process_tools.js",
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
    title = "Söyleşi geçmişi, kayıtlı söyleşiler, arama ve ortak oturumlar",
    owner_seam = "sohbet_llm_akis",
    css_groups = character(0),
    js_groups = character(0),
    # Ortak Oturumlar yüzeyi (işbirlikçi çalışma odaları) bu bölgeye aittir:
    # paylaşılan sohbet/oda geçmişi de bir söyleşi-geçmişi yüzeyidir.
    css = c(
      "css/history_saved_chats.css",
      "css/chat_search_modal.css",
      "css/ortak_oturumlar.css",
      "css/ortak_oturumlar_room.css",
      "css/ortak_oturumlar_bilge_yolac.css"
    ),
    js = c(
      "js/history_date_range.js",
      "js/chat_search_modal.js",
      "js/ortak_oturumlar.js"
    ),
    guard_tests = c(
      "tests/testthat/test-chat-history-datatable-safety-contract.R",
      "tests/testthat/test-ortak-oturum-ui-contract.R"
    )
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
      "css/destek_forms.css",
      "css/destek_submission.css",
      "css/destek_about_responsive.css",
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
      "css/claude_code_plugins.css",
      "css/claude_code_sessions.css"
    ),
    js = c(
      "js/claude_code_pixel_chars.js",
      "js/claude_code.js",
      "js/claude_code_streaming.js",
      "js/claude_code_plugins.js",
      "js/claude_code_sessions.js"
    ),
    guard_tests = c(
      "tests/testthat/test-claude-code-stream-html-safety-contract.R",
      "tests/testthat/test-claude-code-sessions-module-contract.R"
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
  "js/app_loading_lane.js" = list(
    owner_seam = "kimlik_sso",
    reason = "R/module_app_loading.R başlangıç overlay'inde inline gömer (başlangıç şeridi çözümleyici + ilk açılış seçicisi)."
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
  ),
  # optional_in_checkout = TRUE: dosya yalnızca on-prem VM çalışma kopyasında
  # bulunur (renv.lock provenance deseni). Cloud checkout'unda yokluğu hata
  # değildir; VM'de mevcutken sahiplik boşluğu raporlanmasını engeller.
  "js/fontfaceobserver.js" = list(
    owner_seam = "frontend_varlik",
    reason = "Manifest dışı tutulan vendor/font yükleme yardımcı dosyası; üretim manifestiyle otomatik yüklenmez. Yalnızca on-prem VM kopyasında bulunur.",
    optional_in_checkout = TRUE
  ),
  "js/highlight.min.js" = list(
    owner_seam = "frontend_varlik",
    reason = "Manifest dışı tutulan legacy/vendor syntax highlighting dosyası; üretim manifestiyle otomatik yüklenmez. Yalnızca on-prem VM kopyasında bulunur.",
    optional_in_checkout = TRUE
  )
)

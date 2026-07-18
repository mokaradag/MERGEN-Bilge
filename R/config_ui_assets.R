# ==============================================================================
# Dosya Yolu: R/config_ui_assets.R
# Açıklama: ui.R yerel CSS/JS varlık manifesti (SADECE VERİ).
#           Yükleme sırası bu dosyada açık gruplarla korunur ve yükleme
#           sırasının TEK sahibi bu dosyadır.
#
#           VERİ / DOĞRULAYICI / RENDER ayrımı (config_ui_asset_zones.R ile
#           aynı desen):
#             - R/config_ui_assets.R            -> VERİ: gruplar, ertelenmiş
#               grup listesi, render planı, JS/CSS sıra kuralları, düzleştirme
#               yardımcısı.
#             - R/config_ui_asset_validators.R  -> SAF çözümleyici/doğrulayıcı
#               API'si (ui_asset_all_css/js, sıra ve render planı doğrulaması).
#             - R/config_ui_asset_tags.R        -> htmltools etiket render
#               katmanı (ui_asset_tags vb.).
#           Doğrulayıcı ve etiket fonksiyonları veriyi ÇAĞRI ANINDA çözer, bu
#           yüzden bu dosya manifestte onlardan ÖNCE yüklenir. Yeni bir varlık
#           eklerken doğru gruba/sıraya bu dosyada ekleyin; fonksiyon mantığını
#           bu dosyaya geri taşımayın.
# ==============================================================================

ui_asset_flatten_groups <- function(groups) {
  unname(unlist(groups, use.names = FALSE))
}

ui_asset_css_groups <- list(
  critical = c(
    "css/fonts.css",
    "css/welcome_modern.css",
    "css/welcome_greeting_personal.css",
    "css/all.min.css",
    "css/model_selector.css",
    "css/codemirror-custom.css",
    "css/character-selector.css",
    "css/character_video.css",
    "css/premium_reasoning.css",
    "css/tts_visualizer.css",
    "css/stt.css",
    "css/music_slider.css"
  ),
  page = ui_asset_flatten_groups(list(
    # Tema mimarisi (tek-tanım sözleşmesi):
    #   variables.css   -> eski değişken uyumluluk katmanı
    #   theme_tokens.css-> koyu (varsayılan) + açık tema token tabanı
    #   theme_light_*   -> açık temanın ALAN-ODAKLI katmanları; her seçici
    #                      bu zincirde yalnızca BİR kez tanımlanır.
    # Eski 13 dosyalık override/patch zinciri (extras, refinements, polish,
    # overhaul, overhaul_phase2, user_polish, user_polish_v2) kaskad sonucu
    # bire bir korunarak bu alan dosyalarına konsolide edilmiştir. Yeni açık
    # tema kuralı eklerken İLGİLİ ALAN dosyasındaki mevcut seçiciyi
    # genişletin; yeni bir "override katmanı" dosyası EKLEMEYİN
    # (tests/testthat/test-theme-light-modular-contract.R bunu engeller).
    theme_base = c(
      "css/variables.css",
      "css/theme_tokens.css",
      "css/theme_light_core.css"
    ),
    # Alan katmanları (yükleme sırası kasıtlıdır):
    #   1. core (kabuk: gövde, kenar çubuğu, üst şerit, genel widget'lar)
    #   2. welcome (karşılama cam yüzeyi, hızlı eylemler, son konuşmalar)
    #   3. chat (söyleşi konteyneri, baloncuklar, giriş alanı, reasoning)
    #   4. modals (feedback / dosya önizleme / STT / arama / toast)
    #   5. bilge_yolac (AJAN-karakter rozetleri, tool blokları, akış)
    #   6. personalization (Kişiselleştirme + Yapılandırma kart yüzeyleri)
    #   7. pages (Dosya Yönetimi, geçmiş/galeri, Destek, Yönetici, Sağlık)
    theme_light_modules = c(
      "css/theme_light_welcome.css",
      "css/theme_light_chat.css",
      "css/theme_light_modals.css",
      "css/theme_light_bilge_yolac.css",
      "css/theme_light_personalization.css",
      "css/theme_light_pages.css"
    ),
    layout_foundation = c(
      "css/animations.css",
      "css/layout.css",
      "css/components.css",
      "css/brand_title.css",
      "css/sidebar_user_panel.css",
      "css/tool_backgrounds.css",
      "css/code_highlighting.css",
      "css/welcome_screen.css",
      "css/datatables.css",
      "css/chat_messages.css",
      "css/chat_input.css",
      "css/date_picker.css"
    ),
    navigation_and_tools = c(
      "css/cinematic_intro.css",
      "css/deep_space_intro.css",
      "css/mode_selection.css",
      "css/explore_cinematic.css",
      "css/mcp_indicator.css",
      "css/file_manager.css",
      "css/history_saved_chats.css",
      "css/settings_page.css",
      "css/health_dashboard.css",
      "css/disconnect_overlay.css",
      "css/chat_header.css",
      "css/quick_templates.css",
      "css/custom_buttons.css",
      "css/utilities.css",
      "css/responsive.css",
      "css/accessibility.css",
      "css/layout_overrides.css",
      "css/pagination_custom.css",
      "css/modals_custom.css",
      "css/welcome_styles.css",
      "css/empty_state.css",
      "css/animations_extra.css",
      "css/message_actions.css"
    ),
    feature_surfaces = c(
      "css/feedback_modal.css",
      "css/api_key_choice_modal.css",
      "css/api_key_password_toggle.css",
      "css/image_tools.css",
      "css/image_gallery.css",
      "css/summarization_tools.css",
      "css/process_tools.css",
      "css/code_collapse.css",
      "css/chat_search_modal.css",
      "css/settings_tools.css",
      "css/settings_model_info.css",
      "css/analysis_tools.css",
      "css/tools_model_lock.css",
      "css/citation_styles.css",
      "css/ai_expert_subtitle.css",
      "css/destek_page.css",
      "css/destek_forms.css",
      "css/destek_submission.css",
      "css/destek_about_responsive.css",
      "css/destek_yardim_chatbot.css",
      "css/admin_destek_analytics.css",
      "css/admin_yanit_analizi.css",
      "css/admin_documentation.css",
      "css/explore_character_step.css",
      "css/surum_bilgilendirme.css",
      "css/ortak_oturumlar.css",
      "css/ortak_oturumlar_light.css",
      "css/ortak_oturumlar_room.css",
      "css/ortak_oturumlar_bilge_yolac.css"
    ),
    enterprise_and_bilge_yolac = c(
      "css/sso_auth.css",
      "css/claude_code.css",
      "css/claude_code_generated_files.css",
      "css/claude_code_streaming.css",
      "css/claude_code_plugins.css",
      "css/claude_code_sessions.css",
      "css/bilge_yolac_welcome.css",
      "css/bilge_savunmasi.css"
    )
  )),
  codemirror = c(
    "codemirror/codemirror.min.css",
    "codemirror/theme/material-darker.min.css",
    "codemirror/addon/fold/foldgutter.min.css"
  )
)

ui_asset_js_groups <- list(
  diagnostics = c(
    "js/console_error_probe.js"
  ),
  codemirror_core = c(
    "codemirror/codemirror.min.js"
  ),
  codemirror_modes = c(
    "codemirror/mode/r.min.js",
    "codemirror/mode/python.min.js",
    "codemirror/mode/javascript.min.js",
    "codemirror/mode/sql.min.js",
    "codemirror/mode/shell.min.js",
    "codemirror/mode/css.min.js",
    "codemirror/mode/xml.min.js",
    "codemirror/mode/htmlmixed.min.js",
    "codemirror/mode/clike.min.js",
    "codemirror/mode/php.min.js",
    "codemirror/mode/ruby.min.js",
    "codemirror/mode/go.min.js",
    "codemirror/mode/swift.min.js",
    "codemirror/mode/powershell.min.js",
    "codemirror/mode/commonlisp.min.js",
    "codemirror/mode/vb.min.js",
    "codemirror/mode/fortran.min.js",
    "codemirror/mode/octave.min.js",
    "codemirror/mode/julia.min.js"
  ),
  codemirror_addons = c(
    "codemirror/addon/comment/comment.min.js",
    "codemirror/addon/fold/foldcode.min.js",
    "codemirror/addon/fold/foldgutter.min.js",
    "codemirror/addon/fold/brace-fold.min.js",
    "codemirror/addon/fold/comment-fold.min.js",
    "codemirror/addon/fold/indent-fold.min.js",
    "codemirror/addon/fold/xml-fold.js"
  ),
  threejs = c(
    "lib/threejs/three.min.js",
    "lib/threejs/OrbitControls.js",
    "lib/threejs/CopyShader.js",
    "lib/threejs/LuminosityHighPassShader.js",
    "lib/threejs/Pass.js",
    "lib/threejs/ShaderPass.js",
    "lib/threejs/EffectComposer.js",
    "lib/threejs/RenderPass.js",
    "lib/threejs/UnrealBloomPass.js",
    "lib/threejs/Lensflare.js"
  ),
  sso = c(
    "js/sso_auth.js"
  ),
  critical = c(
    "js/utils.js",
    "js/encoding_utils.js",
    "js/theme_manager.js",
	"js/shiny_message_handlers.js",
    "js/modern_welcome_handler.js",
	"js/ui_init.js",
    "js/input_handlers.js",
    "js/interaction_handlers.js",
    "js/app_core.js",
    "js/welcome_tooltip_manager.js",
    "js/streaming_markdown_safety.js",
    "js/markdown-parser.js",
    "js/streaming_manager.js",
    "js/premium_reasoning.js",
    "js/toast.js",
    "js/layout-manager.js",
    "js/tool_backgrounds_snippets.js",
    "js/tool_backgrounds.js"
  ),
  deferred = ui_asset_flatten_groups(list(
    code_and_tables = c(
      "js/code-collapse.js",
      "js/file_handlers.js",
      "js/chart_renderer.js",
      "js/table_scroll_handler.js",
      "js/history_date_range.js",
      "js/codemirror-manager.js"
    ),
    welcome_and_media = c(
      "js/cinematic_video.js",
      "js/character_typing.js",
      "js/tts_visualizer.js",
      "js/music_manager.js",
      "js/audio_lifecycle_guard.js",
      "js/speech_controller.js",
      "js/stt_client.js",
      "js/intro_animation.js",
      "js/neural_welcome.js",
      "js/welcome_video_player.js",
      "js/welcome_neural_modern.js",
      "js/welcome_greeting.js",
      "js/welcome_greeting_personal.js",
      "js/tts_manager.js",
      "js/character_manager.js",
      "js/shortcuts_manager.js"
    ),
    modal_and_analysis_tools = c(
      "js/feedback_modal.js",
      "js/api_key_choice_modal.js",
      "js/image_tools.js",
      "js/image_gallery.js",
      "js/summarization_tools.js",
      "js/process_tools.js",
      "js/chat_search_modal.js",
      "js/deep_space_intro_earth_shader.js",
      "js/deep_space_intro_solar.js",
      "js/deep_space_intro_lifecycle.js",
      "js/deep_space_intro.js",
      "js/mode_selection.js",
      "js/explore_cinematic.js",
      "js/settings_tools.js",
      "js/settings_model_info.js",
      "js/analysis_tools.js",
      "js/excel_coding_deep_thinking.js",
      "js/tools_model_lock.js",
      "js/citation_handler.js"
    ),
    admin_and_enterprise = c(
      "js/ai_expert_manager.js",
      "js/ai_expert_handlers.js",
      "js/destek_form.js",
      "js/destek_yardim_chatbot.js",
      "js/health_dashboard.js",
      "js/admin_documentation.js",
      "js/space_intro_music.js",
      "js/explore_character_video.js",
      "js/explore_character_step.js",
      "js/surum_bilgilendirme.js",
      "js/claude_code_pixel_chars.js",
      "js/bilge_yolac_karsilama.js",
      "js/claude_code.js",
      "js/claude_code_streaming.js",
      "js/claude_code_plugins.js",
      "js/claude_code_sessions.js",
      "js/ortak_oturumlar.js"
    )
  )),
  # Bilge Savunması (kule savunma oyunu): çekirdek altyapı -> denge/harita
  # verisi -> dalga -> saf simülasyon -> çizim/efekt/girdi/HUD -> ses ->
  # Shiny köprüsü -> menü/sonuç katmanları -> sayfa orkestratörü. Oyun motoru
  # sayfa açılana kadar başlatılmaz; bu grup yalnızca tanımları yükler.
  bilge_savunmasi = c(
    "js/bilge_savunmasi_cekirdek.js",
    "js/bilge_savunmasi_denge.js",
    "js/bilge_savunmasi_haritalar.js",
    "js/bilge_savunmasi_dalga.js",
    "js/bilge_savunmasi_sim.js",
    "js/bilge_savunmasi_cizim.js",
    "js/bilge_savunmasi_efekt.js",
    "js/bilge_savunmasi_girdi.js",
    "js/bilge_savunmasi_hud.js",
    "js/bilge_savunmasi_ses.js",
    "js/bilge_savunmasi_kopru.js",
    "js/bilge_savunmasi_menu.js",
    "js/bilge_savunmasi_sonuc.js",
    "js/bilge_savunmasi_uygulama.js"
  )
)

ui_asset_deferred_js_groups <- c("threejs", "deferred", "bilge_savunmasi")

ui_asset_js_render_plan <- list(
  list(group = "diagnostics", defer = FALSE),
  list(group = "codemirror_core", defer = FALSE),
  list(group = "codemirror_modes", defer = FALSE),
  list(group = "codemirror_addons", defer = FALSE),
  list(group = "threejs", defer = TRUE),
  list(group = "sso", defer = FALSE),
  list(group = "critical", defer = FALSE),
  list(group = "deferred", defer = TRUE),
  list(group = "bilge_savunmasi", defer = TRUE)
)

# Kritik istemci tarafı bağımlılık sırası.
# Bu kurallar kullanıcı deneyimini değiştirmez; manifest bakımında yanlış
# sıralamayı erken yakalamak için doğrulanır.
ui_asset_js_order_rules <- list(
  c("js/console_error_probe.js", "codemirror/codemirror.min.js"),
  c("js/console_error_probe.js", "js/sso_auth.js"),
  c("js/console_error_probe.js", "js/utils.js"),

  c("codemirror/codemirror.min.js", "codemirror/mode/r.min.js"),
  c("codemirror/codemirror.min.js", "codemirror/addon/fold/foldcode.min.js"),

  c("lib/threejs/three.min.js", "lib/threejs/OrbitControls.js"),
  c("lib/threejs/three.min.js", "lib/threejs/Pass.js"),
  c("lib/threejs/Pass.js", "lib/threejs/ShaderPass.js"),
  c("lib/threejs/Pass.js", "lib/threejs/RenderPass.js"),
  c("lib/threejs/Pass.js", "lib/threejs/UnrealBloomPass.js"),
  c("lib/threejs/ShaderPass.js", "lib/threejs/EffectComposer.js"),
  c("lib/threejs/ShaderPass.js", "lib/threejs/UnrealBloomPass.js"),
  c("lib/threejs/LuminosityHighPassShader.js", "lib/threejs/UnrealBloomPass.js"),
  c("lib/threejs/three.min.js", "lib/threejs/EffectComposer.js"),
  c("lib/threejs/three.min.js", "lib/threejs/UnrealBloomPass.js"),

  c("js/sso_auth.js", "js/utils.js"),
  c("js/utils.js", "js/encoding_utils.js"),
  c("js/encoding_utils.js", "js/theme_manager.js"),
  c("js/theme_manager.js", "js/shiny_message_handlers.js"),
  c("js/encoding_utils.js", "js/shiny_message_handlers.js"),
  c("js/encoding_utils.js", "js/claude_code_streaming.js"),
  c("js/utils.js", "js/input_handlers.js"),
  c("js/input_handlers.js", "js/app_core.js"),
  c("js/app_core.js", "js/welcome_tooltip_manager.js"),
  c("js/welcome_tooltip_manager.js", "js/streaming_markdown_safety.js"),
  c("js/streaming_markdown_safety.js", "js/markdown-parser.js"),
  c("js/streaming_markdown_safety.js", "js/streaming_manager.js"),
  c("js/markdown-parser.js", "js/streaming_manager.js"),
  c("js/welcome_tooltip_manager.js", "js/streaming_manager.js"),
  c("js/app_core.js", "js/tool_backgrounds.js"),

  c("js/shiny_message_handlers.js", "js/health_dashboard.js"),
  c("js/shiny_message_handlers.js", "js/neural_welcome.js"),
  c("js/shiny_message_handlers.js", "js/modern_welcome_handler.js"),
  c("js/modern_welcome_handler.js", "js/neural_welcome.js"),
  c("js/modern_welcome_handler.js", "js/welcome_video_player.js"),
  c("js/welcome_video_player.js", "js/welcome_neural_modern.js"),
  c("js/welcome_neural_modern.js", "js/welcome_greeting.js"),
  c("js/welcome_greeting.js", "js/welcome_greeting_personal.js"),

  c("js/streaming_manager.js", "js/claude_code_streaming.js"),

  c("js/tts_visualizer.js", "js/music_manager.js"),
  c("js/music_manager.js", "js/audio_lifecycle_guard.js"),
  c("js/audio_lifecycle_guard.js", "js/stt_client.js"),
  c("js/audio_lifecycle_guard.js", "js/tts_manager.js"),
  c("js/audio_lifecycle_guard.js", "js/ai_expert_manager.js"),
  c("js/audio_lifecycle_guard.js", "js/space_intro_music.js"),
  # Konuşma denetleyicisi (token kaydı + PCM oynatıcı) tüketicilerinden önce
  c("js/audio_lifecycle_guard.js", "js/speech_controller.js"),
  c("js/speech_controller.js", "js/tts_manager.js"),
  c("js/speech_controller.js", "js/ai_expert_manager.js"),
  c("js/speech_controller.js", "js/ai_expert_handlers.js"),
  c("js/music_manager.js", "js/stt_client.js"),
  c("js/tts_visualizer.js", "js/tts_manager.js"),
  c("js/music_manager.js", "js/tts_manager.js"),

  c("js/image_tools.js", "js/summarization_tools.js"),
  c("js/summarization_tools.js", "js/analysis_tools.js"),
  c("js/analysis_tools.js", "js/excel_coding_deep_thinking.js"),
  c("js/excel_coding_deep_thinking.js", "js/tools_model_lock.js"),

  c("js/claude_code_pixel_chars.js", "js/claude_code.js"),
  # Retro karşılama sahnesi piksel persona verisine bağımlıdır.
  c("js/claude_code_pixel_chars.js", "js/bilge_yolac_karsilama.js"),
  c("js/claude_code.js", "js/claude_code_streaming.js"),
  c("js/claude_code_streaming.js", "js/claude_code_plugins.js"),
  # Oturum hidrasyonu claude_code.js'in window.MergenClaudeCode köprüsüne bağlıdır.
  c("js/claude_code.js", "js/claude_code_sessions.js"),
  c("js/claude_code_plugins.js", "js/claude_code_sessions.js"),

  # Bilge Savunması bağımlılık zinciri: isim alanı/altyapı önce, veri
  # (denge/harita) sonra, simülasyon ve görsel katmanlar ardından, orkestratör
  # en sonda yüklenir.
  c("js/bilge_savunmasi_cekirdek.js", "js/bilge_savunmasi_denge.js"),
  c("js/bilge_savunmasi_denge.js", "js/bilge_savunmasi_haritalar.js"),
  c("js/bilge_savunmasi_haritalar.js", "js/bilge_savunmasi_dalga.js"),
  c("js/bilge_savunmasi_dalga.js", "js/bilge_savunmasi_sim.js"),
  c("js/bilge_savunmasi_sim.js", "js/bilge_savunmasi_cizim.js"),
  c("js/bilge_savunmasi_cizim.js", "js/bilge_savunmasi_efekt.js"),
  c("js/bilge_savunmasi_efekt.js", "js/bilge_savunmasi_girdi.js"),
  c("js/bilge_savunmasi_girdi.js", "js/bilge_savunmasi_hud.js"),
  c("js/bilge_savunmasi_hud.js", "js/bilge_savunmasi_ses.js"),
  c("js/bilge_savunmasi_ses.js", "js/bilge_savunmasi_kopru.js"),
  c("js/bilge_savunmasi_kopru.js", "js/bilge_savunmasi_menu.js"),
  c("js/bilge_savunmasi_menu.js", "js/bilge_savunmasi_sonuc.js"),
  c("js/bilge_savunmasi_sonuc.js", "js/bilge_savunmasi_uygulama.js")
)

# Kritik CSS katman/kaskad sırası kuralları.
# Açık tema zinciri (variables -> tokens -> core -> welcome -> chat ->
# modals -> bilge_yolac -> personalization -> pages) ve tema katmanlarından
# SONRA gelmesi gereken yüzeyler (brand_title, sidebar_user_panel,
# tool_backgrounds) kaskad sırasına bağımlıdır. Bilge Yolaç CSS zinciri de
# sıra bağımlıdır. Bu kurallar görünümü değiştirmez; manifest bakımında
# yanlış sıralamayı JS kurallarıyla aynı şekilde erken yakalar.
ui_asset_css_order_rules <- list(
  c("css/variables.css", "css/theme_tokens.css"),
  c("css/theme_tokens.css", "css/theme_light_core.css"),

  c("css/theme_light_core.css", "css/theme_light_welcome.css"),
  c("css/theme_light_welcome.css", "css/theme_light_chat.css"),
  c("css/theme_light_chat.css", "css/theme_light_modals.css"),
  c("css/theme_light_modals.css", "css/theme_light_bilge_yolac.css"),
  c("css/theme_light_bilge_yolac.css", "css/theme_light_personalization.css"),
  c("css/theme_light_personalization.css", "css/theme_light_pages.css"),

  c("css/theme_light_pages.css", "css/brand_title.css"),
  c("css/theme_light_pages.css", "css/sidebar_user_panel.css"),
  c("css/theme_light_pages.css", "css/tool_backgrounds.css"),

  c("css/welcome_modern.css", "css/theme_light_welcome.css"),

  c("css/claude_code.css", "css/claude_code_generated_files.css"),
  c("css/claude_code_generated_files.css", "css/claude_code_streaming.css"),
  c("css/claude_code_streaming.css", "css/claude_code_plugins.css"),
  c("css/claude_code_plugins.css", "css/claude_code_sessions.css")
)

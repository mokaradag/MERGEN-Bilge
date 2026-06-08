# ==============================================================================
# Dosya Yolu: R/config_ui_assets.R
# Açıklama: ui.R yerel CSS/JS varlık manifesti.
#           Yükleme sırası bu dosyada açık gruplarla korunur.
# ==============================================================================

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
  page = c(
    "css/variables.css",
    "css/theme_tokens.css",
    "css/theme_light.css",
    "css/theme_light_extras.css",
    "css/theme_light_refinements.css",
    # Açık tema cilası: odaklı küçük dosyalara bölünerek ratchet limitleri
    # altında tutulur. Yükleme sırası burada kasıtlıdır:
    #   1. welcome (en alttaki cam yüzey önce yerleşir)
    #   2. chat (söyleşi giriş + baloncuk başlığı + rozet override'ları)
    #   3. modals (feedback / dosya önizleme / STT - en üst katman)
    #   4. bilge_yolac (Bilge Yolaç light chat + komut blokları)
    #   5. personalization (Kişiselleştirme + Yapılandırma kart yüzeyleri)
    #   6. polish (admin tooltip, hero başlık, file manager notları,
    #      Yenilikler madde işareti, sidebar logout)
    "css/theme_light_welcome.css",
    "css/theme_light_chat.css",
    "css/theme_light_modals.css",
    "css/theme_light_bilge_yolac.css",
    "css/theme_light_personalization.css",
    "css/theme_light_polish.css",
    # Kullanıcı geri bildirimi toplu light tema cilası: TÜM diğer
    # theme_light_*.css dosyalarından SONRA yüklenir, çünkü onların
    # kurallarını son kez ezerek navbar şeridi, ay grubu nötr gri,
    # chat baloncuk başlıkları, Bilge Yolaç tool şeritleri, Dosya
    # Yönetimi notları, Yenilikler rozetleri ve diğer onarımları
    # garantiler.
    "css/theme_light_overhaul.css",
    # Faz 2 saldırgan onarımları: koyu yüzey leak'lerini kapatma,
    # admin nav-pills, destek-tab-btn, mesaj eylem butonları,
    # Bilge Yolaç tool dark hover regresyonu, vb. theme_light_overhaul
    # dosyasından sonra yüklenir ki onun kurallarını da son adımda
    # pekiştirebilir; ratchet limitini aşmamak için ikinci dosyaya
    # bölündü.
    "css/theme_light_overhaul_phase2.css",
    # Kullanıcı geri bildirimi cilası (Faz 1 + Faz 2): EN SON yüklenir.
    # Hero başlık kurumsal mavisi, karşılama greeting/icon, Bilge Yolaç
    # light tool yüzeyleri, Kişiselleştirme deneyim modu + karakter
    # aksanı, Sistem Durumu kart kontrastı, Geri Bildirim sekme buton
    # kenarları, Yenilikler madde/rozet/italik kontrastı, Söyleşi
    # baloncuk başlık + eylem butonları ve dosya önizleme modal başlığı
    # için kapsamlı kurumsal mavi cilası içerir. İki dosya birlikte
    # 1600 satır ratchet limitinin altında kalır.
    "css/theme_light_user_polish.css",
    "css/theme_light_user_polish_v2.css",
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
    "css/date_picker.css",
    "css/cinematic_intro.css",
    "css/deep_space_intro.css",
    "css/mode_selection.css",
    "css/explore_cinematic.css",
    "css/mcp_indicator.css",
    "css/file_manager.css",
    "css/history_saved_chats.css",
    "css/settings_page.css",
    "css/health_check.css",
    "css/health_dashboard.css",
    "css/disconnect_overlay.css",
    "css/chat_header.css",
    "css/quick_templates.css",
    "css/capabilities.css",
    "css/custom_buttons.css",
    "css/utilities.css",
    "css/responsive.css",
    "css/accessibility.css",
    "css/layout_overrides.css",
    "css/pagination_custom.css",
    "css/modals_custom.css",
    "css/welcome_styles.css",
    "css/recent_chats_custom.css",
    "css/empty_state.css",
    "css/animations_extra.css",
    "css/message_actions.css",
    "css/feedback_modal.css",
    "css/api_key_choice_modal.css",
    "css/api_key_password_toggle.css",
    "css/image_tools.css",
    "css/image_gallery.css",
    "css/summarization_tools.css",
    "css/code_collapse.css",
    "css/chat_search_modal.css",
    "css/settings_tools.css",
    "css/settings_model_info.css",
    "css/analysis_tools.css",
    "css/tools_model_lock.css",
    "css/citation_styles.css",
    "css/ai_expert_subtitle.css",
    "css/destek_page.css",
    "css/destek_yardim_chatbot.css",
    "css/admin_destek_analytics.css",
    "css/admin_yanit_analizi.css",
    "css/admin_documentation.css",
    "css/explore_character_step.css",
    "css/surum_bilgilendirme.css",
	"css/sso_auth.css",
	"css/claude_code.css",
	"css/claude_code_generated_files.css",
	"css/claude_code_streaming.css",
	"css/claude_code_plugins.css",
	"css/bilge_yolac_welcome.css"
  ),
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
  deferred = c(
    "js/code-collapse.js",
    "js/file_handlers.js",
    "js/chart_renderer.js",
    "js/table_scroll_handler.js",
    "js/history_date_range.js",
    "js/codemirror-manager.js",
    "js/cinematic_video.js",
    "js/character_typing.js",
    "js/tts_visualizer.js",
    "js/music_manager.js",
    "js/audio_lifecycle_guard.js",
    "js/stt_client.js",
    "js/intro_animation.js",
    "js/neural_welcome.js",
    "js/welcome_video_player.js",
    "js/welcome_neural_modern.js",
    "js/welcome_greeting.js",
    "js/welcome_greeting_personal.js",
    "js/tts_manager.js",
    "js/character_manager.js",
    "js/shortcuts_manager.js",
    "js/feedback_modal.js",
    "js/api_key_choice_modal.js",
    "js/image_tools.js",
    "js/image_gallery.js",
    "js/summarization_tools.js",
    "js/chat_search_modal.js",
    "js/deep_space_intro_earth_shader.js",
    "js/deep_space_intro_solar.js",
    "js/deep_space_intro.js",
    "js/mode_selection.js",
    "js/explore_cinematic.js",
    "js/settings_tools.js",
    "js/settings_model_info.js",
    "js/analysis_tools.js",
    "js/excel_coding_deep_thinking.js",
    "js/tools_model_lock.js",
    "js/citation_handler.js",
    "js/ai_expert_manager.js",
    "js/destek_form.js",
    "js/destek_yardim_chatbot.js",
    "js/health_dashboard.js",
    "js/admin_documentation.js",
    "js/space_intro_music.js",
    "js/explore_character_video.js",
    "js/explore_character_step.js",
    "js/surum_bilgilendirme.js",
    "js/claude_code_pixel_chars.js",
    "js/claude_code.js",
    "js/claude_code_streaming.js",
    "js/claude_code_plugins.js"
  ),
  bilge_yolac = c(
    "js/bilge_yolac_motor.js",
    "js/bilge_yolac_fizik.js",
    "js/bilge_yolac_varliklar.js",
    "js/bilge_yolac_seviye.js",
    "js/bilge_yolac_dunya.js",
    "js/bilge_yolac_karakterler.js",
    "js/bilge_yolac_cephanelik.js",
    "js/bilge_yolac_dusmanlar.js",
    "js/bilge_yolac_efektler.js",
    "js/bilge_yolac_arayuz.js",
    "js/bilge_yolac_etkilesim.js",
    "js/bilge_yolac_oyun.js",
    "js/bilge_yolac_kopru.js"
  )
)

ui_asset_deferred_js_groups <- c("threejs", "deferred", "bilge_yolac")

ui_asset_js_render_plan <- list(
  list(group = "diagnostics", defer = FALSE),
  list(group = "codemirror_core", defer = FALSE),
  list(group = "codemirror_modes", defer = FALSE),
  list(group = "codemirror_addons", defer = FALSE),
  list(group = "threejs", defer = TRUE),
  list(group = "sso", defer = FALSE),
  list(group = "critical", defer = FALSE),
  list(group = "deferred", defer = TRUE),
  list(group = "bilge_yolac", defer = TRUE)
)

ui_asset_render_plan_groups <- function(render_plan = ui_asset_js_render_plan) {
  vapply(render_plan, function(item) item$group, character(1))
}

ui_asset_render_plan_deferred <- function(render_plan = ui_asset_js_render_plan) {
  deferred <- vapply(render_plan, function(item) isTRUE(item$defer), logical(1))
  ui_asset_render_plan_groups(render_plan)[deferred]
}

ui_asset_validate_js_render_plan <- function(render_plan = ui_asset_js_render_plan,
                                             groups = ui_asset_js_groups) {
  if (!is.list(render_plan) || length(render_plan) == 0) {
    stop("UI JS render planı boş olamaz.", call. = FALSE)
  }

  for (item in render_plan) {
    if (!is.list(item) ||
        !is.character(item$group) ||
        length(item$group) != 1 ||
        !is.logical(item$defer) ||
        length(item$defer) != 1 ||
        is.na(item$defer)) {
      stop(
        "UI JS render planı her kayıt için group ve defer alanlarını içermelidir.",
        call. = FALSE
      )
    }
  }

  render_groups <- ui_asset_render_plan_groups(render_plan)
  duplicate_groups <- sort(unique(render_groups[duplicated(render_groups)]))

  if (length(duplicate_groups) > 0) {
    stop(
      "UI JS render planında yinelenen grup var: ",
      paste(duplicate_groups, collapse = ", "),
      call. = FALSE
    )
  }

  missing_groups <- setdiff(names(groups), render_groups)
  extra_groups <- setdiff(render_groups, names(groups))

  if (length(missing_groups) > 0) {
    stop(
      "UI JS render planında eksik grup var: ",
      paste(missing_groups, collapse = ", "),
      call. = FALSE
    )
  }

  if (length(extra_groups) > 0) {
    stop(
      "UI JS render planında manifestte olmayan grup var: ",
      paste(extra_groups, collapse = ", "),
      call. = FALSE
    )
  }

  if (!identical(ui_asset_render_plan_deferred(render_plan), ui_asset_deferred_js_groups)) {
    stop(
      "UI JS render planı ile ertelenmiş grup listesi uyuşmuyor.",
      call. = FALSE
    )
  }

  invisible(TRUE)
}

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
  c("js/shiny_message_handlers.js", "js/welcome_video_player.js"),
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
  c("js/music_manager.js", "js/stt_client.js"),
  c("js/tts_visualizer.js", "js/tts_manager.js"),
  c("js/music_manager.js", "js/tts_manager.js"),

  c("js/image_tools.js", "js/summarization_tools.js"),
  c("js/summarization_tools.js", "js/analysis_tools.js"),
  c("js/analysis_tools.js", "js/excel_coding_deep_thinking.js"),
  c("js/excel_coding_deep_thinking.js", "js/tools_model_lock.js"),

  c("js/claude_code_pixel_chars.js", "js/claude_code.js"),
  c("js/claude_code.js", "js/claude_code_streaming.js"),
  c("js/claude_code_streaming.js", "js/claude_code_plugins.js"),

  c("js/bilge_yolac_motor.js", "js/bilge_yolac_fizik.js"),
  c("js/bilge_yolac_fizik.js", "js/bilge_yolac_varliklar.js"),
  c("js/bilge_yolac_varliklar.js", "js/bilge_yolac_seviye.js"),
  c("js/bilge_yolac_seviye.js", "js/bilge_yolac_dunya.js"),
  c("js/bilge_yolac_dunya.js", "js/bilge_yolac_karakterler.js"),
  c("js/bilge_yolac_karakterler.js", "js/bilge_yolac_cephanelik.js"),
  c("js/bilge_yolac_cephanelik.js", "js/bilge_yolac_dusmanlar.js"),
  c("js/bilge_yolac_dusmanlar.js", "js/bilge_yolac_efektler.js"),
  c("js/bilge_yolac_efektler.js", "js/bilge_yolac_arayuz.js"),
  c("js/bilge_yolac_arayuz.js", "js/bilge_yolac_etkilesim.js"),
  c("js/bilge_yolac_etkilesim.js", "js/bilge_yolac_oyun.js"),
  c("js/bilge_yolac_oyun.js", "js/bilge_yolac_kopru.js")
)

ui_asset_flatten_groups <- function(groups) {
  unname(unlist(groups, use.names = FALSE))
}

ui_asset_all_css <- function() {
  ui_asset_flatten_groups(ui_asset_css_groups)
}

ui_asset_all_js <- function() {
  ui_asset_flatten_groups(ui_asset_js_groups)
}

ui_asset_deferred_js_paths <- function() {
  missing_groups <- setdiff(ui_asset_deferred_js_groups, names(ui_asset_js_groups))

  if (length(missing_groups) > 0) {
    stop(
      "UI ertelenmiş JS grup tanımı manifestte yok: ",
      paste(missing_groups, collapse = ", "),
      call. = FALSE
    )
  }

  ui_asset_flatten_groups(ui_asset_js_groups[ui_asset_deferred_js_groups])
}

ui_asset_validate_js_order <- function(js_paths = ui_asset_all_js()) {
  for (rule in ui_asset_js_order_rules) {
    if (!is.character(rule) || length(rule) != 2) {
      stop("UI JS sıra kuralı iki dosyadan oluşmalıdır.", call. = FALSE)
    }

    before_path <- rule[[1]]
    after_path <- rule[[2]]

    before_pos <- match(before_path, js_paths)
    after_pos <- match(after_path, js_paths)

    if (is.na(before_pos)) {
      stop(
        "UI JS sıra kuralının ilk dosyası manifestte yok: ",
        before_path,
        call. = FALSE
      )
    }

    if (is.na(after_pos)) {
      stop(
        "UI JS sıra kuralının ikinci dosyası manifestte yok: ",
        after_path,
        call. = FALSE
      )
    }

    if (before_pos >= after_pos) {
      stop(
        "UI JS varlık yükleme sırası bozuldu: ",
        before_path,
        " dosyası ",
        after_path,
        " dosyasından önce yüklenmelidir.",
        call. = FALSE
      )
    }
  }

  invisible(TRUE)
}

ui_asset_duplicate_paths <- function(paths) {
  sort(unique(paths[duplicated(paths)]))
}

ui_asset_public_root <- function(root = getwd()) {
  if (dir.exists(file.path(root, "css")) &&
      dir.exists(file.path(root, "js"))) {
    return(root)
  }

  file.path(root, "www")
}

ui_asset_validate <- function(root = getwd(), check_files = FALSE) {
  css_paths <- ui_asset_all_css()
  js_paths <- ui_asset_all_js()

  duplicate_css <- ui_asset_duplicate_paths(css_paths)
  duplicate_js <- ui_asset_duplicate_paths(js_paths)

  if (length(duplicate_css) > 0) {
    stop(
      "UI CSS varlık manifestinde yinelenen kayıt var: ",
      paste(duplicate_css, collapse = ", "),
      call. = FALSE
    )
  }

  if (length(duplicate_js) > 0) {
    stop(
      "UI JS varlık manifestinde yinelenen kayıt var: ",
      paste(duplicate_js, collapse = ", "),
      call. = FALSE
    )
  }

  ui_asset_validate_js_order(js_paths)
  ui_asset_deferred_js_paths()
  ui_asset_validate_js_render_plan()

  if (isTRUE(check_files)) {
    all_paths <- c(css_paths, js_paths)
    asset_root <- ui_asset_public_root(root)
    missing_paths <- all_paths[!file.exists(file.path(asset_root, all_paths))]

    if (length(missing_paths) > 0) {
      stop(
        "UI varlık manifestinde bulunamayan dosya var: ",
        paste(missing_paths, collapse = ", "),
        call. = FALSE
      )
    }
  }

  invisible(TRUE)
}

ui_asset_css_tag <- function(path) {
  if (grepl("^codemirror/", path)) {
    return(tags$link(rel = "stylesheet", href = path))
  }

  tags$link(rel = "stylesheet", type = "text/css", href = path)
}

ui_asset_script_tag <- function(path, defer = FALSE) {
  if (isTRUE(defer)) {
    return(tags$script(src = path, defer = "defer"))
  }

  tags$script(src = path)
}

ui_asset_css_tags <- function() {
  htmltools::tagList(lapply(ui_asset_all_css(), ui_asset_css_tag))
}

ui_asset_js_tags <- function() {
  js_tags <- unlist(
    lapply(ui_asset_js_render_plan, function(item) {
      lapply(
        ui_asset_js_groups[[item$group]],
        ui_asset_script_tag,
        defer = item$defer
      )
    }),
    recursive = FALSE,
    use.names = FALSE
  )

  htmltools::tagList(js_tags)
}

ui_asset_tags <- function(root = getwd(), check_files = FALSE) {
  ui_asset_validate(root = root, check_files = check_files)

  htmltools::tagList(
    ui_asset_css_tags(),
    ui_asset_js_tags()
  )
}
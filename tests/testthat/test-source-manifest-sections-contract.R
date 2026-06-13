# ==============================================================================
# Dosya Yolu: tests/testthat/test-source-manifest-sections-contract.R
# Açıklama: R/config_source_manifest.R artık özellik/katman ailelerine göre
#           adlandırılmış bölümlerle (source_manifest_sections) düzenlenmiştir.
#           Bu sözleşme; bölüm sırasını, türetme bütünlüğünü ve bölüm sınır
#           dosyalarını dondurarak yükleme sırasının (load order) bölümleme
#           sonrası birebir korunmasını garanti eder. Uygulamayı başlatmaz.
# ==============================================================================

.load_source_manifest_env_for_sections <- function() {
  repo_root <- resolve_repo_root_for_tests()
  manifest_env <- new.env(parent = globalenv())

  source(
    file.path(repo_root, "R", "config_source_manifest.R"),
    encoding = "UTF-8",
    local = manifest_env
  )

  manifest_env
}

# Dondurulmuş bölüm sırası. Bir bölüm eklenir/çıkarılır/yeniden adlandırılır ya
# da sırası değişirse bu liste bilinçli olarak güncellenmelidir.
.expected_manifest_section_keys <- c(
  "foundation",
  "post_future_utils",
  "config_app_core",
  "config_api_model_keys",
  "config_claude_code",
  "config_ui_assets",
  "architecture_governance",
  "database",
  "sql_library",
  "language_messaging",
  "mcp_tools",
  "chartlab_helpers",
  "files_preview_pipeline",
  "file_manager_helpers",
  "chat_send_message_runtime",
  "summarization_followup",
  "analysis_helpers",
  "sso_identity_helpers",
  "support_admin_health_helpers",
  "ai_expert_helpers",
  "claude_code_helpers",
  "llm_pipeline",
  "module_chat",
  "module_files_media",
  "module_settings_api_key",
  "module_ai_audio",
  "module_identity_startup",
  "module_claude_code",
  "module_analysis",
  "module_support",
  "module_admin",
  "module_health_chartlab",
  "server_init_runtime",
  "server_core_outputs_welcome",
  "server_observers",
  "server_handlers_send_message"
)

# Her bölümün ilk/son dosyası ve eleman sayısı. Bu çapalar; bir dosyanın
# bölümler arasında kaymasını veya bölüm sınırlarının değişmesini yakalar.
.expected_manifest_section_anchors <- list(
  foundation = list(first = "R/config_packages.R", last = "R/helpers_worker_monitor.R", n = 7L),
  post_future_utils = list(first = "R/utils_path_helpers.R", last = "R/utils_excel_reader.R", n = 9L),
  # config_app_core n = 7L -> 8L bilinçli güncelleme: indeks kilidi
  # (R/config_file_store_index_lock.R) fonksiyon-yoğunluk bölmesiyle ayrı dosyaya alındı.
  config_app_core = list(first = "R/config_sso.R", last = "R/config_version_history.R", n = 8L),
  config_api_model_keys = list(first = "R/helpers_vision_model_capabilities.R", last = "R/helpers_api_key_password_toggle.R", n = 9L),
  config_claude_code = list(first = "R/config_claude_code.R", last = "R/config_claude_code_plugins.R", n = 2L),
  config_ui_assets = list(first = "R/config_ui_assets.R", last = "R/config_ui_asset_zones.R", n = 2L),
  architecture_governance = list(first = "R/config_seam_registry.R", last = "R/config_seam_registry.R", n = 1L),
  database = list(first = "R/helpers_db_unicode_escape.R", last = "R/helpers_database.R", n = 11L),
  sql_library = list(first = "R/library_queries.R", last = "R/config_sql_loader.R", n = 2L),
  language_messaging = list(first = "R/helpers_language.R", last = "R/helpers_messaging.R", n = 2L),
  mcp_tools = list(first = "R/helpers_mcp_context.R", last = "R/helpers_mcp_tools.R", n = 9L),
  chartlab_helpers = list(first = "R/helpers_chartlab_spec.R", last = "R/helpers_chartlab.R", n = 2L),
  files_preview_pipeline = list(first = "R/helpers_image_gallery.R", last = "R/helpers_files.R", n = 5L),
  file_manager_helpers = list(first = "R/helpers_file_manager_policy.R", last = "R/helpers_file_manager_table_runtime.R", n = 10L),
  chat_send_message_runtime = list(first = "R/helpers_chat_runtime.R", last = "R/helpers_quick_action_intro_messages.R", n = 9L),
  summarization_followup = list(first = "R/helpers_summarization_modes.R", last = "R/helpers_followup_questions.R", n = 3L),
  analysis_helpers = list(first = "R/helpers_deep_analysis.R", last = "R/helpers_pk_analysis_query_selection.R", n = 5L),
  sso_identity_helpers = list(first = "R/helpers_sso_signature.R", last = "R/helpers_logout_url.R", n = 3L),
  # Bilinçli güncelleme: R/helpers_release_evidence.R (release kanıt artifact
  # okuyucusu) health_checks'ten önce bölüme eklendi; 6 -> 7 dosya.
  support_admin_health_helpers = list(first = "R/helpers_destek_database.R", last = "R/helpers_health_checks.R", n = 7L),
  ai_expert_helpers = list(first = "R/helpers_ai_expert.R", last = "R/helpers_ai_expert_chunking.R", n = 2L),
  claude_code_helpers = list(first = "R/helpers_claude_code_user_guard.R", last = "R/helpers_claude_code_run_lifecycle.R", n = 26L),
  llm_pipeline = list(first = "R/helpers_llm_tool_formatters.R", last = "R/helpers_llm_worker.R", n = 11L),
  module_chat = list(first = "R/module_chat_history_background.R", last = "R/module_feedback.R", n = 9L),
  module_files_media = list(first = "R/module_file_manager_ui.R", last = "R/module_summarization.R", n = 6L),
  module_settings_api_key = list(first = "R/module_settings_kisisel.R", last = "R/module_api_key.R", n = 6L),
  module_ai_audio = list(first = "R/module_ai_processing.R", last = "R/module_character_video.R", n = 6L),
  module_identity_startup = list(first = "R/module_sso.R", last = "R/module_quick_actions.R", n = 11L),
  module_claude_code = list(first = "R/module_claude_code_plugins.R", last = "R/module_claude_code.R", n = 5L),
  module_analysis = list(first = "R/module_proje_kaynak_analizi.R", last = "R/module_proje_kaynak_analizi.R", n = 1L),
  module_support = list(first = "R/module_destek_yardim.R", last = "R/module_destek.R", n = 6L),
  module_admin = list(first = "R/module_admin_genel_bakis.R", last = "R/module_admin_documentation.R", n = 19L),
  module_health_chartlab = list(first = "R/module_health_worker_metrics.R", last = "R/module_chartlab.R", n = 9L),
  server_init_runtime = list(first = "R/server_session_cache.R", last = "R/server_init_chat_runtime.R", n = 13L),
  server_core_outputs_welcome = list(first = "R/server_core_observer_runtime.R", last = "R/server_welcome_handlers.R", n = 7L),
  server_observers = list(first = "R/server_observers_startup.R", last = "R/server_observers_misc.R", n = 11L),
  server_handlers_send_message = list(first = "R/server_tts_handlers.R", last = "R/server_send_message.R", n = 8L)
)

test_that("source_manifest_sections beklenen sırada ve adlarda bölümler içerir", {
  env <- .load_source_manifest_env_for_sections()

  expect_true(
    exists("source_manifest_sections", envir = env, inherits = FALSE),
    info = "config_source_manifest.R source_manifest_sections nesnesini tanımlamalıdır."
  )

  sections <- get("source_manifest_sections", envir = env, inherits = FALSE)

  expect_true(is.list(sections), info = "source_manifest_sections bir liste olmalıdır.")

  expect_equal(
    names(sections),
    .expected_manifest_section_keys,
    info = "Bölüm anahtarları veya sırası beklenenden farklı (onboarding sözleşmesi)."
  )
})

test_that("her bölüm boş olmayan karakter vektörüdür ve sınır dosyaları dondurulmuştur", {
  env <- .load_source_manifest_env_for_sections()
  sections <- get("source_manifest_sections", envir = env, inherits = FALSE)

  for (key in names(.expected_manifest_section_anchors)) {
    vec <- sections[[key]]

    expect_true(
      is.character(vec) && length(vec) > 0L,
      info = sprintf("Bölüm boş veya karakter vektörü değil: %s", key)
    )

    anchor <- .expected_manifest_section_anchors[[key]]

    expect_equal(
      length(vec),
      anchor$n,
      info = sprintf("Bölüm eleman sayısı değişti: %s", key)
    )

    expect_equal(
      vec[1],
      anchor$first,
      info = sprintf("Bölümün ilk dosyası değişti: %s", key)
    )

    expect_equal(
      vec[length(vec)],
      anchor$last,
      info = sprintf("Bölümün son dosyası değişti: %s", key)
    )
  }
})

test_that("kanonik manifest nesneleri bölümlerden birebir türetilir", {
  env <- .load_source_manifest_env_for_sections()
  sections <- get("source_manifest_sections", envir = env, inherits = FALSE)
  group_1 <- get("source_manifest_group_1_paths", envir = env, inherits = FALSE)
  after_future <- get("source_manifest_after_future_paths", envir = env, inherits = FALSE)
  runtime <- get("source_manifest_runtime_paths", envir = env, inherits = FALSE)

  # group_1 = foundation bölümü
  expect_identical(
    group_1,
    sections$foundation,
    info = "source_manifest_group_1_paths foundation bölümüyle aynı olmalıdır."
  )

  # after_future = foundation dışındaki tüm bölümlerin sıralı birleşimi
  expect_identical(
    after_future,
    unlist(sections[-1L], use.names = FALSE),
    info = "source_manifest_after_future_paths foundation dışı bölümlerin birleşimi olmalıdır."
  )

  # runtime = group_1 + after_future
  expect_identical(
    runtime,
    c(group_1, after_future),
    info = "source_manifest_runtime_paths group_1 + after_future birleşimiyle aynı olmalıdır."
  )

  # Tüm bölümlerin sıralı birleşimi runtime listesinin tamamını üretmelidir
  expect_identical(
    unlist(sections, use.names = FALSE),
    runtime,
    info = "Bölümlerin sıralı birleşimi runtime yükleme listesini birebir üretmelidir."
  )
})

test_that("bölümlenmiş manifest tekrar içermez ve tüm dosyalar repoda mevcuttur", {
  repo_root <- resolve_repo_root_for_tests()
  env <- .load_source_manifest_env_for_sections()
  runtime <- get("source_manifest_runtime_paths", envir = env, inherits = FALSE)

  # 260L -> 261L bilinçli güncelleme: R/config_file_store_index_lock.R
  # fonksiyon-yoğunluk bölmesiyle manifest'e eklendi.
  # 261L -> 262L bilinçli güncelleme: R/helpers_release_evidence.R (release
  # kanıt artifact okuyucusu) support_admin_health_helpers bölümüne eklendi.
  expect_equal(length(runtime), 262L, info = "Toplam kaynak sayısı beklenenden farklı.")

  duplicate_paths <- unique(runtime[duplicated(runtime)])
  duplicate_r_paths <- duplicate_paths[grepl("^R/", duplicate_paths)]

  expect_equal(
    duplicate_r_paths,
    character(0),
    info = paste("Bölümlenmiş manifestte tekrar eden R/ kaydı:", paste(duplicate_r_paths, collapse = ", "))
  )

  missing_paths <- runtime[!file.exists(file.path(repo_root, runtime))]

  expect_equal(
    missing_paths,
    character(0),
    info = paste("Bölümlenmiş manifestte olmayan dosyalar:", paste(missing_paths, collapse = ", "))
  )
})

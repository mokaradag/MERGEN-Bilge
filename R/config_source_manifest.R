# ==============================================================================
# Dosya Yolu: R/config_source_manifest.R
# Açıklama: global.R çalışma zamanı kaynak manifesti.
#           Bu dosya uygulama kodu yüklemez; yalnızca açık, sıralı ve
#           incelenebilir kaynak listesini tanımlar.
#
#           Manifest, onboarding yükünü azaltmak için özellik/katman ailelerine
#           göre adlandırılmış bölümlere (source_manifest_sections) ayrılmıştır.
#           Bölümler yalnızca okunabilirlik içindir; çalışma zamanı yükleme
#           sırası bölümlerin sırayla birleştirilmesiyle BİREBİR korunur.
#
#           Üç kanonik nesne bölümlerden türetilir ve global.R ile bootstrap
#           doğrulaması bu nesneleri kullanmaya devam eder:
#             - source_manifest_group_1_paths     (foundation bölümü)
#             - source_manifest_after_future_paths (foundation dışındaki bölümler)
#             - source_manifest_runtime_paths      (ikisinin birleşimi)
#
#           Bölüm sırası/üyeliği değiştirilirken:
#             - tests/testthat/test-source-manifest-sections-contract.R bölüm
#               sırasını, türetme bütünlüğünü ve sınır dosyalarını dondurur,
#             - R/bootstrap_source_manifest.R içindeki source_manifest_required_order
#               kritik ikili yükleme sırası kurallarını doğrular.
#           Dosyaya yeni bir kaynak eklerken ilgili bölüme doğru sırada ekleyin.
# ==============================================================================

source_manifest_sections <- list(
  # foundation: Temel altyapı (future cluster başlamadan önce yüklenir): paket
  # doğrulama, ortak yardımcılar, metin ve mailto encoding, loglama, rate
  # limiter ve worker monitor.
  foundation = c(
    "R/config_packages.R",
    "R/utils_common.R",
    "R/utils_text_encoding.R",
    "R/helpers_mailto_encoding.R",
    "R/config_logging_daily_file.R",
    "R/config_logging.R",
    "R/helpers_performance_instrumentation.R",
    "R/helpers_index_page_cache.R",
    "R/utils_rate_limiter.R",
    "R/helpers_worker_monitor.R"
  ),

  # post_future_utils: Future cluster sonrası temel yardımcılar: yol/güvenli
  # yol, atomik yazma, upload doğrulama, log redaksiyonu, oturum temizliği,
  # güvenli worker koşumu, dosya indeks ve Excel okuyucu.
  post_future_utils = c(
    "R/utils_path_helpers.R",
    "R/utils_safe_path.R",
    "R/utils_atomic_write.R",
    "R/utils_upload_validator.R",
    "R/utils_log_redact.R",
    "R/utils_session_cleanup.R",
    "R/utils_safe_worker_run.R",
    "R/utils_file_index.R",
    "R/utils_excel_reader.R"
  ),

  # config_app_core: Çekirdek yapılandırma: SSO, dosya deposu
  # (kilit/indeks/listeleme/registry), karakter/persona ve sürüm geçmişi.
  config_app_core = c(
    "R/config_sso.R",
    "R/config_file_store.R",
    "R/config_file_store_index_lock.R",
    "R/config_file_store_index_mutation.R",
    "R/config_file_store_listing_helpers.R",
    "R/config_file_store_registry.R",
    "R/config_characters.R",
    "R/config_version_history.R"
  ),

  # config_api_model_keys: Model yeteneği/görsel anlama/derin düşünme işaretleme,
  # API yapılandırması (config_api.R), model/araç runtime çözümleme ve API
  # anahtarı kripto/kimlik/özellik yardımcıları. Yetenek işaretleme helper'ları
  # config_api.R'den ÖNCE yüklenmelidir (source-time guard'lı çağrı).
  config_api_model_keys = c(
    "R/helpers_vision_model_capabilities.R",
    "R/helpers_deep_thinking_model_capabilities.R",
    "R/config_api.R",
    "R/helpers_api_model_config.R",
    "R/helpers_api_model_tool_runtime.R",
    "R/helpers_api_key_crypto.R",
    "R/helpers_api_key_identity.R",
    "R/helpers_feature_api_key.R",
    "R/helpers_api_key_password_toggle.R"
  ),

  # config_claude_code: Bilge Yolaç (Claude Code) yapılandırması ve eklenti
  # yapılandırması.
  config_claude_code = c(
    "R/config_claude_code.R",
    "R/config_claude_code_plugins.R"
  ),

  # config_ui_assets: Frontend CSS/JS varlık manifesti (yükleme sırası
  # sözleşmesi) ve frontend bölge (zone) sahiplik haritası. Bölge haritası
  # manifestten SONRA yüklenir; yükleme sırasının tek sahibi manifest kalır.
  # Varlık manifesti VERİ / DOĞRULAYICI / RENDER olarak üç dosyaya bölünmüştür
  # (config_ui_asset_zones.R deseninin aynısı): VERİ (config_ui_assets.R) ->
  # SAF çözümleyici/doğrulayıcı API'si (config_ui_asset_validators.R) ->
  # htmltools etiket render katmanı (config_ui_asset_tags.R). Doğrulayıcı/etiket
  # fonksiyonları veriyi çağrı anında çözer; veriden hemen sonra yüklenir.
  # Bölge VERİSİ (config_ui_asset_zones.R) ile bölge DOĞRULAYICI API'si
  # (config_ui_asset_zone_validators.R) ayrı dosyalardır; doğrulayıcı saf
  # fonksiyonlar veriden hemen sonra yüklenir (boot'ta çağrılmaz).
  config_ui_assets = c(
    "R/config_ui_assets.R",
    "R/config_ui_asset_validators.R",
    "R/config_ui_asset_tags.R",
    "R/config_ui_asset_zones.R",
    "R/config_ui_asset_zone_validators.R"
  ),

  # architecture_governance: Üretim-kritik dikiş (seam) kayıt defteri. Saf
  # veri + saf doğrulama yardımcıları; çalışma zamanı davranışı değiştirmez.
  # Bölüm -> seam sahipliği test-seam-registry-contract.R ile doğrulanır.
  architecture_governance = c(
    "R/config_seam_registry.R"
  ),

  # database: DB sınırları: Unicode escape, encoding guard, bağlantı, işlem-güvenli
  # bağlantı havuzu (helpers_db_pool.R; bağlantıdan SONRA), kullanıcı encoding,
  # doğrulama, markdown güvenliği, mesaj formatlama, sohbet okuyucu/mutasyon,
  # geri bildirim ve üst seviye DB orkestrasyonu.
  database = c(
    "R/helpers_db_unicode_escape.R",
    "R/helpers_db_encoding.R",
    "R/helpers_db_connection.R",
    "R/helpers_db_pool.R",
    "R/helpers_db_user_encoding.R",
    "R/helpers_db_validation.R",
    "R/helpers_markdown_safety.R",
    "R/helpers_chat_message_formatting.R",
    "R/helpers_db_chat_read_queries.R",
    "R/helpers_db_chat_readers.R",
    "R/helpers_db_chat_mutations.R",
    "R/helpers_db_feedback.R",
    "R/helpers_database.R"
  ),

  # sql_library: SQL kütüphane sorguları ve SQL loader.
  sql_library = c(
    "R/library_queries.R",
    "R/config_sql_loader.R"
  ),

  # language_messaging: Dil tespiti ve mesaj render/işleme yardımcıları.
  language_messaging = c(
    "R/helpers_language.R",
    "R/helpers_messaging.R"
  ),

  # mcp_tools: MCP zinciri: context, bootstrap, tablo okuyucu, dosya
  # çözümleyici, şema, temel araçlar, grafik araçları, analiz+görsel ve araç
  # router.
  mcp_tools = c(
    "R/helpers_mcp_context.R",
    "R/helpers_mcp_bootstrap.R",
    "R/helpers_mcp_table_readers.R",
    "R/helpers_mcp_file_resolver.R",
    "R/helpers_mcp_schema_helpers.R",
    "R/helpers_mcp_basic_tools.R",
    "R/helpers_mcp_chart_tools.R",
    "R/helpers_mcp_analyze_visualize.R",
    "R/helpers_mcp_tools.R"
  ),

  # chartlab_helpers: ChartLab saf spec yardımcıları ve Shiny grafik çıktısı
  # bağlama.
  chartlab_helpers = c(
    "R/helpers_chartlab_spec.R",
    "R/helpers_chartlab.R"
  ),

  # files_preview_pipeline: Görsel galeri, önizleme, dosya pipeline ve dosya
  # yol/okuma yardımcıları.
  files_preview_pipeline = c(
    "R/helpers_image_gallery.R",
    "R/helpers_preview.R",
    "R/helpers_file_pipeline.R",
    "R/helpers_files_path.R",
    "R/helpers_files.R"
  ),

  # file_manager_helpers: Dosya Yönetimi yardımcı zinciri: politika, bağlam
  # politikası, tablo, refresh guard, oturum registry, runtime, depolama, state
  # runtime ve attach/tablo runtime istemci yardımcıları.
  file_manager_helpers = c(
    "R/helpers_file_manager_policy.R",
    "R/helpers_file_manager_context_policy.R",
    "R/helpers_file_manager_table.R",
    "R/helpers_file_manager_refresh_guard.R",
    "R/helpers_file_manager_session_registry.R",
    "R/helpers_file_manager_runtime.R",
    "R/helpers_file_manager_storage.R",
    "R/helpers_file_manager_state_runtime.R",
    "R/helpers_file_manager_attach_client.R",
    "R/helpers_file_manager_table_runtime.R"
  ),

  # chat_send_message_runtime: Sohbet runtime ve send_message hattı: istek
  # yaşam döngüsü, model runtime, streaming abort/poll kararları, core,
  # görsel bağlam, prompting ve hızlı eylem giriş mesajları.
  chat_send_message_runtime = c(
    "R/helpers_chat_runtime.R",
    "R/helpers_send_message_request_lifecycle.R",
    "R/helpers_send_message_model_runtime.R",
    "R/helpers_streaming_abort_lifecycle.R",
    "R/helpers_streaming_poll_lifecycle.R",
    "R/helpers_send_message_core.R",
    "R/helpers_vision_context.R",
    "R/helpers_send_message_prompting.R",
    "R/helpers_quick_action_intro_messages.R"
  ),

  # summarization_followup: Özetleme modları/promptları ve takip sorusu
  # yardımcıları.
  summarization_followup = c(
    "R/helpers_summarization_modes.R",
    "R/helpers_summarization_prompts.R",
    "R/helpers_followup_questions.R"
  ),

  # analysis_helpers: Derin analiz ve Proje/Kaynak Analizi çekirdek/RLS-güvenlik
  # özeti/filtre/sorgu-seçimi yardımcıları.
  analysis_helpers = c(
    "R/helpers_deep_analysis.R",
    "R/helpers_pk_analysis_core.R",
    "R/helpers_pk_analysis_security_summary.R",
    "R/helpers_pk_analysis_filters.R",
    "R/helpers_pk_analysis_query_selection.R"
  ),

  # sso_identity_helpers: SSO imza doğrulama, SSO akışı ve logout URL
  # yardımcıları.
  sso_identity_helpers = c(
    "R/helpers_sso_signature.R",
    "R/helpers_sso.R",
    "R/helpers_logout_url.R"
  ),

  # support_admin_health_helpers: Destek DB, admin analitik ve sağlık
  # (formatlama/tablo/runtime kontrol/kontrol) yardımcıları.
  support_admin_health_helpers = c(
    "R/helpers_destek_database.R",
    "R/helpers_admin_analytics.R",
    "R/helpers_health_formatters.R",
    "R/helpers_health_table.R",
    "R/helpers_health_runtime_checks.R",
    # Release/doğrulama kanıt artifact'larının secret-safe okuyucusu; sağlık
    # kontrolleri ileride bu özetleri tüketebilsin diye health_checks'ten önce.
    "R/helpers_release_evidence.R",
    "R/helpers_health_checks.R"
  ),

  # ai_expert_helpers: AI Uzman konuşma ve TTS metin parçalama yardımcıları.
  # Worker-safe DB okuyucuları (helpers_ai_expert_user_data.R) önce yüklenir;
  # helpers_ai_expert.R::build_ai_expert_user_context() bunları çağırır.
  # helpers_ai_expert_handlers_support.R, R/server_ai_expert_handlers.R'nin
  # kullandığı saf karar yardımcılarını (sayfa adı, sıklık, boşta bağlam) taşır;
  # handler dosyasından çok önce yüklenir.
  ai_expert_helpers = c(
    "R/helpers_ai_expert_user_data.R",
    "R/helpers_ai_expert.R",
    "R/helpers_ai_expert_chunking.R",
    "R/helpers_ai_expert_handlers_support.R"
  ),

  # claude_code_helpers: Bilge Yolaç yardımcı zinciri: kullanıcı guard, upload
  # klasörü, model config, süreç/runtime workdir, güvenlik politikası, dizin
  # listeleme, streaming/formatlama, indirmeler, workdir tarama/snapshot,
  # doküman çıkarma ve çalıştırma yaşam döngüsü.
  claude_code_helpers = c(
    "R/helpers_claude_code_user_guard.R",
    "R/helpers_claude_code_upload_folder.R",
    "R/helpers_claude_code_model_config.R",
    "R/helpers_claude_code_session_context.R",
    "R/helpers_claude_code_dir_ui.R",
    "R/helpers_claude_code_process.R",
    "R/helpers_claude_code_api_key.R",
    "R/helpers_claude_code_runtime_resolver.R",
    "R/helpers_claude_code_runtime_workdir.R",
    "R/helpers_claude_code_security_policy.R",
    "R/helpers_claude_code_path_policy.R",
    "R/helpers_claude_code_prompt_security_policy.R",
    "R/helpers_claude_code_directory_listing.R",
    "R/helpers_claude_code.R",
    "R/helpers_claude_code_server_setup.R",
    "R/helpers_claude_code_streaming.R",
    "R/helpers_claude_code_formatters.R",
    "R/helpers_claude_code_downloads.R",
    "R/helpers_claude_code_downloads_html.R",
    "R/helpers_claude_code_existing_file_link.R",
    "R/helpers_claude_code_workdir_scan.R",
    "R/helpers_claude_code_workdir_snapshot.R",
    "R/helpers_claude_code_plugins.R",
    "R/helpers_claude_code_document_extractors.R",
    "R/helpers_claude_code_documents.R",
    "R/helpers_claude_code_document_summary.R",
    "R/helpers_claude_code_run_lifecycle.R"
  ),

  # llm_pipeline: LLM hattı: araç formatlayıcılar, yanıt post-process,
  # non-streaming API, stream I/O, SSE event/akış ve worker
  # (payload/araç-sonuç/ikinci geçiş/worker).
  llm_pipeline = c(
    "R/helpers_llm_tool_formatters.R",
    "R/helpers_llm_response_postprocess.R",
    "R/helpers_llm_api.R",
    "R/helpers_llm_stream_io.R",
    "R/helpers_llm_sse_events.R",
    "R/helpers_llm_sse.R",
    "R/helpers_llm_worker_payload.R",
    "R/helpers_llm_worker_tool_results_preview.R",
    "R/helpers_llm_worker_tool_results.R",
    "R/helpers_llm_worker_second_pass.R",
    "R/helpers_llm_worker.R"
  ),

  # module_chat: Sohbet modülleri: geçmiş, kayıtlı söyleşiler, mesaj/sohbet
  # arama, takip soruları, sohbet eylemleri, dışa aktarma ve geri bildirim.
  module_chat = c(
    "R/module_chat_history_background.R",
    "R/module_chat_history.R",
    "R/module_saved_chats.R",
    "R/module_message_search.R",
    "R/module_chat_search.R",
    "R/module_followup_questions.R",
    "R/module_chat_actions.R",
    "R/module_chat_export.R",
    "R/module_feedback.R"
  ),

  # module_files_media: Dosya/medya modülleri: Dosya Yönetimi UI/server,
  # önizleme, görsel üretimi/galeri ve özetleme.
  module_files_media = c(
    "R/module_file_manager_ui.R",
    "R/module_file_manager.R",
    "R/module_file_preview.R",
    "R/module_image_generation.R",
    "R/module_image_generation_ui.R",
    "R/module_image_gallery.R",
    "R/module_summarization.R"
  ),

  # module_settings_api_key: Ayarlar modülleri: Kişiselleştirme, Yapılandırma
  # UI/server, ayar koordinatörü ve API anahtarı seçim modalı/modülü.
  module_settings_api_key = c(
    "R/module_settings_kisisel.R",
    "R/module_settings_yapilandirma_advanced_ui.R",
    "R/module_settings_yapilandirma_ui.R",
    "R/module_settings_yapilandirma.R",
    "R/module_settings.R",
    "R/module_api_key_choice_modal.R",
    "R/module_api_key.R"
  ),

  # module_ai_audio: Yapay zeka/ses modülleri: AI işleme, AI Uzman, TTS/TTS
  # görselleştirici, STT ve karakter video.
  module_ai_audio = c(
    "R/module_ai_processing.R",
    "R/module_ai_expert.R",
    "R/module_tts.R",
    "R/module_tts_visualizer.R",
    "R/module_stt.R",
    "R/module_character_video.R"
  ),

  # module_identity_startup: Kimlik/başlangıç modülleri: SSO, oturum zaman
  # aşımı, performans, kullanıcı kimliği, boot hazırlığı, başlangıç ekranı,
  # yükleme overlay, araç arka planı, kenar çubuğu kullanıcı paneli (saf
  # görünüm yardımcıları + modül) ve hızlı eylemler.
  module_identity_startup = c(
    "R/module_sso.R",
    "R/module_session_timeout.R",
    "R/module_performance.R",
    "R/module_user_identity.R",
    "R/module_boot_readiness.R",
    "R/module_startup_screen_ui.R",
    "R/module_startup_screen.R",
    "R/module_app_loading.R",
    "R/module_tool_background_settings.R",
    "R/helpers_sidebar_user_display.R",
    "R/module_sidebar_user_panel.R",
    "R/module_quick_actions.R"
  ),

  # module_claude_code: Bilge Yolaç modülleri: eklentiler, UI, akış, stream
  # poll ve ana server modülü.
  module_claude_code = c(
    "R/module_claude_code_plugins.R",
    "R/module_claude_code_ui.R",
    "R/module_claude_code_akis.R",
    "R/module_claude_code_stream_poll.R",
    "R/module_claude_code.R"
  ),

  # module_analysis: Proje/Kaynak Analizi modülü.
  module_analysis = c(
    "R/module_proje_kaynak_analizi.R"
  ),

  # module_support: Destek modülleri: Yardım Merkezi, Hakkında, Yenilikler,
  # Hata Bildir, Geri Bildirim ve Destek koordinatörü.
  module_support = c(
    "R/module_destek_yardim.R",
    "R/module_destek_hakkinda.R",
    "R/module_destek_surum.R",
    "R/module_destek_hata_bildir.R",
    "R/module_destek_geri_bildirim.R",
    "R/module_destek.R"
  ),

  # module_admin: Yönetici paneli modülleri: genel bakış,
  # kullanıcı/YZ/zaman/gelişmiş analizler, analitik, geri bildirim, hata
  # analizi, yanıt analizi ve dokümantasyon (ilgili yardımcılarla).
  module_admin = c(
    "R/module_admin_genel_bakis.R",
    "R/module_admin_kullanici_analizi.R",
    "R/module_admin_yz_performans.R",
    "R/module_admin_geri_bildirim_genel.R",
    "R/module_admin_sohbet_kalitesi.R",
    "R/module_admin_zaman_analizi.R",
    "R/module_admin_gelismis_analizler.R",
    "R/module_admin_analytics.R",
    "R/helpers_admin_geri_bildirim.R",
    "R/helpers_admin_geri_bildirim_queries.R",
    "R/helpers_admin_geri_bildirim_output_tables.R",
    "R/module_admin_geri_bildirim_outputs.R",
    "R/module_admin_geri_bildirim.R",
    "R/helpers_admin_hata_analizi.R",
    "R/helpers_admin_hata_heatmap_data.R",
    "R/helpers_admin_hata_detail_runtime.R",
    "R/module_admin_hata_analizi.R",
    "R/helpers_admin_yanit_analizi.R",
    "R/module_admin_yanit_analizi_outputs.R",
    "R/module_admin_yanit_analizi.R",
    "R/helpers_admin_documentation.R",
    "R/module_admin_documentation.R"
  ),

  # module_health_chartlab: Sistem Durumu (sağlık) modülleri ve ChartLab
  # etkileşimli modülü.
  module_health_chartlab = c(
    "R/module_health_worker_metrics.R",
    "R/module_health_overview.R",
    "R/module_health_connectivity.R",
    "R/module_health_storage.R",
    "R/module_health_runtime.R",
    "R/module_health_security.R",
    "R/module_health_diagnostics.R",
    "R/module_health_release.R",
    "R/module_health.R",
    "R/module_chartlab.R"
  ),

  # server_init_runtime: Server init/runtime: oturum cache, forward ref,
  # kullanıcı kimliği/oturum, runtime context sözleşmeleri/context/function
  # slot, modül wiring, chat engine ve oturum/sohbet runtime init.
  server_init_runtime = c(
    "R/server_session_cache.R",
    "R/server_init_forward_refs.R",
    "R/helpers_user_session_identity.R",
    "R/server_init_user_session.R",
    "R/helpers_server_runtime_contracts.R",
    "R/helpers_server_runtime_named_contracts.R",
    "R/server_runtime_context.R",
    "R/server_runtime_auth_ready.R",
    "R/server_runtime_function_slot.R",
    "R/server_module_wiring.R",
    "R/server_chat_engine_dependencies.R",
    "R/server_chat_engine_runtime.R",
    "R/server_init_session_state.R",
    "R/server_init_chat_runtime.R"
  ),

  # server_core_outputs_welcome: Server çekirdek orkestrasyon: core
  # observer/interaction runtime, sohbet/indirme çıktıları ve welcome
  # ekranı/handler'ları.
  server_core_outputs_welcome = c(
    "R/server_core_observer_runtime.R",
    "R/server_core_interaction_runtime.R",
    "R/server_outputs_chat.R",
    "R/server_outputs_downloads.R",
    "R/welcome_screen_modern.R",
    "welcome_screen.R",
    "R/server_welcome_handlers.R"
  ),

  # server_observers: Server observer katmanı: başlangıç, navigasyon, sohbet
  # UI/giriş, dosya/dosya tıklama, depolama, kayıtlı söyleşi, görsel galeri,
  # ayarlar ve diğer.
  server_observers = c(
    "R/server_observers_startup.R",
    "R/server_observers_navigation.R",
    "R/server_observers_chat_ui.R",
    "R/server_observers_chat_input.R",
    "R/server_observers_files.R",
    "R/server_observers_file_clicks.R",
    "R/server_observers_storage.R",
    "R/server_observers_saved_chats.R",
    "R/server_observers_image_gallery.R",
    "R/server_observers_settings.R",
    "R/server_observers_misc.R"
  ),

  # server_handlers_send_message: Server handler/gönderme hattı: TTS/müzik/AI
  # Uzman handler'ları, özetleme/görsel üretimi/gerçek streaming handler'ları,
  # LLM yanıt handler'ları ve send_message.
  server_handlers_send_message = c(
    "R/server_tts_handlers.R",
    "R/server_music_handlers.R",
    "R/server_ai_expert_handlers.R",
    "R/server_handler_summarization.R",
    "R/server_handler_image_generation.R",
    "R/server_handler_true_streaming.R",
    "R/server_handler_streaming_tts.R",
    "R/server_llm_response_handlers.R",
    "R/server_send_message.R"
  )
)

# group_1: future cluster başlamadan önce yüklenen temel altyapı bölümü.
source_manifest_group_1_paths <- source_manifest_sections$foundation

# after_future: future cluster kurulduktan sonra yüklenen tüm bölümler,
# tanımlandıkları sırayla (foundation hariç) birleştirilir.
source_manifest_after_future_paths <- unlist(
  source_manifest_sections[-1L],
  use.names = FALSE
)

# runtime: kanonik tam yükleme listesi. Bootstrap doğrulaması bu değerin
# group_1 + after_future birleşimiyle birebir aynı olmasını bekler.
source_manifest_runtime_paths <- c(
  source_manifest_group_1_paths,
  source_manifest_after_future_paths
)

# ==============================================================================
# Dosya Yolu: R/config_source_manifest.R
# Açıklama: global.R çalışma zamanı kaynak manifesti.
#           Bu dosya uygulama kodu yüklemez; yalnızca açık, sıralı ve
#           incelenebilir kaynak listesini tanımlar.
#
#           Manifest, adlandırılmış bölümlere (source_manifest_sections)
#           ayrılmıştır. Bölümler yalnızca okunabilirlik içindir; yükleme sırası
#           bölümlerin sırayla birleştirilmesiyle BİREBİR korunur.
#
#           Üç kanonik nesne bölümlerden türetilir ve global.R ile bootstrap
#           doğrulaması bu nesneleri kullanmaya devam eder:
#             - source_manifest_group_1_paths     (foundation bölümü)
#             - source_manifest_after_future_paths (foundation dışındaki bölümler)
#             - source_manifest_runtime_paths      (ikisinin birleşimi)
#
#           Bölüm sırası/üyeliği değiştirilirken
#           tests/testthat/test-source-manifest-sections-contract.R bölüm
#           sırasını/türetme bütünlüğünü, R/bootstrap_source_manifest.R
#           içindeki source_manifest_required_order ise kritik ikili yükleme
#           sırası kurallarını doğrular. Yeni kaynağı doğru bölüme ekleyin.
# ==============================================================================

source_manifest_sections <- list(
  # foundation: Temel altyapı (future cluster'dan ÖNCE): paket doğrulama, ortak
  # yardımcılar, metin/mailto encoding, loglama, rate limiter, worker monitor.
  foundation = c(
    "R/config_packages.R",
    "R/utils_common.R",
    "R/utils_text_encoding.R",
    "R/helpers_mailto_encoding.R",
    "R/config_logging_daily_file.R",
    "R/config_logging.R",
    "R/helpers_performance_instrumentation.R",
    "R/helpers_runtime_metrics.R",
    "R/helpers_request_backpressure.R",
    "R/helpers_index_page_cache.R",
    "R/helpers_app_http_routes.R",
    "R/utils_rate_limiter.R",
    "R/helpers_worker_monitor.R"
  ),

  # post_future_utils: Future cluster SONRASI yardımcılar: yol/güvenli yol,
  # atomik yazma, upload doğrulama, log redaksiyonu, oturum temizliği, güvenli
  # worker koşumu, dosya indeks ve Excel okuyucu.
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

  # config_app_core: SSO, dosya deposu (kilit/indeks/listeleme/registry),
  # karakter/persona ve sürüm geçmişi.
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

  # config_api_model_keys: Model yeteneği/görsel/derin düşünme işaretleme, API
  # yapılandırması, model/araç runtime çözümleme ve API anahtarı
  # kripto/kimlik/özellik yardımcıları. Yetenek işaretleme helper'ları
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

  # config_claude_code: Bilge Yolaç (Claude Code) + eklenti yapılandırması.
  config_claude_code = c(
    "R/config_claude_code.R",
    "R/config_claude_code_plugins.R"
  ),

  # config_ui_assets: Frontend CSS/JS varlık manifesti + bölge sahiplik
  # haritası. VERİ -> DOĞRULAYICI -> RENDER; bölge haritası manifestten SONRA.
  config_ui_assets = c(
    "R/config_ui_assets.R",
    "R/config_ui_asset_validators.R",
    "R/config_ui_asset_tags.R",
    "R/config_ui_asset_zones.R",
    "R/config_ui_asset_zone_validators.R"
  ),

  # architecture_governance: Üretim-kritik dikiş (seam) kayıt defteri. Saf veri
  # + doğrulayıcılar. Bölüm -> seam sahipliği test-seam-registry-contract.R ile
  # doğrulanır; guard test listesi AYRI dosyadadır ve defterden ÖNCE gelir.
  architecture_governance = c(
    "R/config_seam_guard_tests.R",
    "R/config_seam_registry.R"
  ),

  # database: Unicode escape, encoding guard, bağlantı, işlem güvenli havuz
  # (bağlantıdan SONRA), kullanıcı encoding, doğrulama, markdown güvenliği,
  # mesaj formatlama, sohbet okuyucu/mutasyon, geri bildirim, DB orkestrasyonu.
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
    # Hızlı Başlangıç "Son Konuşmalar" ön izlemesi: dar bağımlılık sözleşmeli
    # (explicit worker-export) ham sorgu + ana süreç biçimlendirme katmanı.
    "R/helpers_startup_chat_preview.R",
    "R/helpers_db_chat_mutations.R",
    "R/helpers_db_feedback.R",
    # Bilge Yolaç kalıcı oturum katmanı: SAF sorgu/başlık/kısaltma yardımcıları
    # önce, DB orkestrasyon yardımcıları sonra yüklenir. MB_Chats/MB_Messages
    # ailesinden ayrı MB_ClaudeCode_* tablolarını yönetir.
    "R/helpers_db_claude_code_session_queries.R",
    "R/helpers_db_claude_code_sessions.R",
    "R/helpers_db_claude_code_session_lifecycle.R",
    "R/helpers_database.R"
  ),

  # pk_query_metadata: PK sorgu metadata SÖZLEŞMESİ (Faz 3a). Sıra §6 ile
  # ZORUNLU: Türkçe katlama önce, sonra dört veri katmanı; hepsi
  # config_sql_loader.R'den ÖNCE biter. Yerel iki dosya BİLİNÇLİ opsiyoneldir
  # (gitignore'lu); bulut checkout'unda yoklukları NORMALDİR.
  pk_query_metadata = c(
    "R/helpers_pk_ascii_tokens.R", "R/helpers_pk_text_turkish.R",  # makine belirteçleri (ASCII katlama), sonra Türkçe metin
    "R/helpers_pk_query_meta_schema.R",
    "R/helpers_pk_query_meta_access.R",
    "R/library_query_meta_auto.R",
    "R/library_query_meta_local.R",
    "R/library_query_meta.R",
    "R/library_query_aliases_local.R",
    "R/helpers_pk_query_meta.R"
  ),

  # sql_library: SQL kütüphane sorguları + loader.
  sql_library = c(
    "R/library_queries.R",
    "R/config_sql_loader.R"
  ),

  # language_messaging: Dil tespiti + mesaj render/işleme.
  language_messaging = c(
    "R/helpers_language.R",
    "R/helpers_messaging.R"
  ),

  # mcp_tools: MCP zinciri: context, bootstrap, tablo okuyucu, dosya
  # çözümleyici, şema, temel/grafik araçlar, analiz+görsel ve araç router.
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

  # files_preview_pipeline: Görsel galeri, önizleme, dosya pipeline, dosya
  # yol/okuma yardımcıları ve bloklamayan dosya alım (ingestion) hattı.
  # Alım zinciri saf plan -> worker -> kuyruk -> ana süreç runtime sırasını
  # korur ve copy_to_mcp_base tanımlandıktan SONRA yüklenir.
  files_preview_pipeline = c(
    "R/helpers_image_gallery.R",
    "R/helpers_preview.R",
    "R/helpers_file_pipeline.R",
    "R/helpers_files_path.R",
    "R/helpers_files.R",
    "R/helpers_file_ingestion_task.R",
    "R/helpers_file_ingestion_worker.R",
    "R/helpers_file_ingestion_queue.R",
    "R/helpers_file_ingestion_runtime.R"
  ),

  # file_manager_helpers: Dosya Yönetimi yardımcı zinciri: politika, bağlam
  # politikası, tablo, refresh guard, oturum registry, runtime, depolama, silme,
  # state runtime ve attach/tablo runtime istemci yardımcıları.
  file_manager_helpers = c(
    "R/helpers_file_manager_policy.R",
    "R/helpers_file_manager_context_policy.R",
    "R/helpers_file_manager_table.R",
    "R/helpers_file_manager_refresh_guard.R",
    "R/helpers_file_manager_session_registry.R",
    "R/helpers_file_manager_runtime.R",
    "R/helpers_file_manager_storage.R",
    "R/helpers_file_manager_upload_runtime.R",
    "R/helpers_file_manager_delete_runtime.R",
    "R/helpers_file_manager_state_runtime.R",
    "R/helpers_file_manager_attach_client.R",
    "R/helpers_file_manager_table_runtime.R"
  ),

  # chat_send_message_runtime: Sohbet runtime ve send_message hattı: istek
  # yaşam döngüsü, model runtime, streaming abort/poll kararları, core,
  # görsel bağlam, prompting ve hızlı eylem giriş mesajları. Langflow kaynak
  # çıkarımı/Kaynakça işaretleyici yardımcıları runtime yardımcılarından SONRA
  # yüklenir (.langflow_pluck bağımlılığı).
  chat_send_message_runtime = c(
    "R/helpers_chat_runtime.R",
    "R/helpers_send_message_request_lifecycle.R",
    "R/helpers_send_message_thinking_panel.R",
    "R/helpers_send_message_model_runtime.R",
    "R/helpers_streaming_abort_lifecycle.R",
    "R/helpers_streaming_poll_lifecycle.R",
    "R/helpers_streaming_io.R",
    "R/helpers_stream_load_control.R",
    "R/helpers_send_message_core.R",
    "R/helpers_langflow_runtime.R",
    "R/helpers_langflow_sources.R",
    "R/helpers_langflow_inline_sources.R",
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
    # Faz 0: yapılandırma -> köken -> telemetri kaydı (saf) -> telemetri
    # yazımı (DB). Sıra ZORUNLUDUR: yazım katmanı diğer üçünü de kullanır.
    "R/helpers_pk_config.R",
    # Faz 6 (§5.10) bloklamayan yürütme; sıra ZORUNLU (bkz. dosya başlıkları).
    "R/helpers_pk_async_cancel.R",
    "R/helpers_pk_exec_context.R",
    # Sira ZORUNLU: HTTP iptali -> metadata -> boyut -> onbellek -> getirim.
    "R/helpers_pk_cancel_http.R",
    "R/helpers_pk_result_columns.R",
    "R/helpers_pk_result_size.R",
    "R/helpers_pk_cache_key.R",
    "R/helpers_pk_cache.R",
    "R/helpers_pk_sql_execute.R",
    "R/helpers_pk_sql_connection.R",
    # İşçi ortamı + havuz admisyonu bootstrap'tan ÖNCE.
    "R/helpers_pk_async_worker_env.R",
    "R/helpers_pk_async_worker_pool.R",
    "R/helpers_pk_async_bootstrap.R",
    "R/helpers_pk_async_snapshot_validate.R",
    "R/helpers_pk_async_snapshot.R",
    "R/helpers_pk_async_probe.R",  # sonda, plan çözümleyicisinden ÖNCE
    "R/helpers_pk_async_plan.R",
    "R/helpers_pk_async_request.R",
    "R/helpers_pk_async_worker_sql.R",
    "R/helpers_pk_async_worker.R",
    "R/helpers_pk_provenance.R",
    "R/helpers_pk_provenance_peek.R",  # tüketmeyen kip okuması: sahibinden SONRA
    "R/helpers_pk_telemetry_record.R",
    "R/helpers_pk_telemetry_base.R",
    "R/helpers_pk_telemetry.R",
    # Faz 1 koşulsuz güvenlik katmanı: hata redaksiyonu (D22), salt-okunur SQL
    # sınıflandırıcısı (D23) ve kapalı başarısız RLS kararı (D6/D6b). Üçü de
    # hem derin analiz hem ana modül tarafından tüketildiği için onlardan ÖNCE
    # yüklenir. RLS kararı, Faz 3a metadata erişimcilerine dayanır; onlar
    # pk_query_metadata bölümünde çok daha önce yüklenmiştir.
    "R/helpers_pk_safe_errors.R",
    "R/helpers_pk_sql_statements.R", "R/helpers_pk_sql_readonly.R",
    "R/helpers_pk_rls.R",
    # Faz 4 (§5.4) varlık çözümleme: normalleştirme -> puanlama -> karar
    # politikası -> geçmiş daraltması (D11). Sıra ZORUNLU; dördü de SAFTIR ve
    # Türkçe katlamayı pk_query_metadata'daki `pk_tr_fold()` üzerinden alır.
    # Filtre derlemesinden ÖNCE gelir: bulanıklık HANGİ DEĞERİ çözer.
    "R/helpers_pk_entity_morph.R",
    "R/helpers_pk_entity_normalize.R",
    "R/helpers_pk_entity_mention.R",
    "R/helpers_pk_entity_alias.R",
    "R/helpers_pk_entity_score.R",
    "R/helpers_pk_entity_scan.R",
    "R/helpers_pk_entity_resolver.R",
    "R/helpers_pk_entity_history.R",
    "R/helpers_pk_entity_context.R", "R/helpers_pk_entity_tree.R", "R/helpers_pk_entity_apply.R",  # baglam anahtari + filtre agaci gezintisi ONCE
    # Faz 1 v2 davranış katmanı (MERGEN_PK_ENGINE=v2 arkasında): saf filtre
    # derleyicisi -> saf sıfır-eşleşme politikası -> v2 yürütücüsü. Yürütücü
    # ikisini de kullandığı için en sonda gelir; üçü de v1 uyumluluk yüzeyi
    # olan helpers_pk_analysis_filters.R'den ÖNCE yüklenmelidir.
    "R/helpers_pk_filter_compile.R", "R/helpers_pk_filter_group.R",  # ikincisi: açık AND/OR gruplarının inert değerlendiricisi
    "R/helpers_pk_filter_policy.R",
    "R/helpers_pk_analysis_filters_v2.R",
    # Saf istem bütçesi/yük kurucusu ve saf sistem istemi kurucusu; modül
    # bunları yalnızca tüketir (modül KÜÇÜLMELİ, büyümemeli).
    "R/helpers_pk_prompt_budget.R",
    "R/helpers_pk_analysis_prompts.R",
    # Faz 2 (v2 arkasında) bağımlılık sırası: olgu çekirdeği -> paket -> paket
    # metni -> sayısal köken -> dışa aktarım planı/G-Ç -> kompozisyon -> sonuç.
    "R/helpers_pk_precision.R", "R/helpers_pk_packet_stats.R",
    "R/helpers_pk_analysis_packet.R",
    "R/helpers_pk_packet_render.R",
    "R/helpers_pk_numeric_provenance.R",
    "R/helpers_pk_export_plan.R",
    "R/helpers_pk_export_csv.R",
    "R/helpers_pk_export_xlsx.R",
    "R/helpers_pk_export_serve.R",
    "R/helpers_pk_answer_compose.R",
    "R/helpers_pk_analysis_result.R",
    # Derin analiz: detay kataloğu + bağlam kurucu orkestratörden ÖNCE; Faz 6
    # (D16) uzlaştırma katmanı ikisinden de ÖNCE (ikisi de onu çağırır).
    "R/helpers_deep_analysis_sql.R",
    "R/helpers_deep_analysis_reconcile.R",
    "R/helpers_deep_analysis_phase6.R",
    "R/helpers_deep_analysis_selector.R",
    "R/helpers_deep_analysis_detail.R",
    "R/helpers_deep_analysis_context.R",
    "R/helpers_deep_analysis.R",
    "R/helpers_pk_analysis_core_impl.R",  # saf gövde: çekirdekten ÖNCE
    "R/helpers_pk_analysis_core.R",
    "R/helpers_pk_p1_runtime_guards.R",   # tanımları EZER: her ikisinden SONRA
    "R/helpers_pk_rls_identity.R", "R/helpers_pk_analysis_security_summary.R",
    "R/helpers_pk_statistical_summary.R",
    "R/helpers_pk_analysis_filters_base.R",
    "R/helpers_pk_analysis_filters.R",
    "R/helpers_pk_analysis_query_selection.R",
    # v1 AI seçicisi modülden ÇIKARILDI (ratchet bölünmesi); davranış BİREBİR
    # korunur ve v2 hattı bu dosyayı çağırmaz.
    "R/helpers_pk_analysis_ai_selector.R",
    # Faz 5 (§5.2) iki geçişli sorgu seçimi; bağımlılık zinciri ZORUNLU:
    # sözlüksel getirim (saf) -> katı JSON ilkeleri -> kapalı-başarısız
    # yapılandırma -> istem yükü -> mesaj kurulumu -> `requirements` doğrulaması
    # -> ayrıştırma -> karar politikası -> bozulma kipi -> geçmiş kimliği ->
    # oturum durumu -> recall tohumu -> LLM orkestrasyonu -> derin analiz
    # köprüsü -> çalışma zamanına bağlama. Tümü v1 sezgiselinden SONRA yüklenir
    # (bağlama katmanı v1 uyumlu `all_scores` tablosunu kurar). Sözlüksel katman
    # KARAR VERMEZ (D10); yalnızca bozulma/uyuşmazlık/altın küme tanılaması içindir.
    "R/helpers_pk_query_retrieval.R",
    "R/helpers_pk_query_selection_json.R",
    "R/helpers_pk_query_selection_config.R",
    "R/helpers_pk_query_selection_payload.R",
    "R/helpers_pk_query_selection_prompt.R",
    "R/helpers_pk_query_selection_canonical.R", "R/helpers_pk_query_selection_requirements.R",  # varolus->sayim imasi ONCE
    "R/helpers_pk_query_selection_parse.R",
    "R/helpers_pk_query_selection_decide.R",
    "R/helpers_pk_query_selection_degraded.R",
    "R/helpers_pk_query_selection_history.R",
    "R/helpers_pk_query_selection_session.R",
    "R/helpers_pk_query_selection_seed.R",
    "R/helpers_pk_query_selection_ai.R",
    "R/helpers_pk_query_selection_deep.R",
    "R/helpers_pk_query_selection_apply.R"
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
  # helpers_ai_expert_handlers_support.R saf karar yardımcılarını taşır.
  ai_expert_helpers = c(
    "R/helpers_ai_expert_user_data.R",
    "R/helpers_ai_expert.R",
    "R/helpers_ai_expert_chunking.R",
    "R/helpers_ai_expert_chunk_pipeline.R",
    "R/helpers_ai_expert_handlers_support.R"
  ),

  # speech_assets: Hibrit VoxCPM2 konuşma katmanı. Sıra BAĞIMLIDIR:
  # yapılandırma -> WAV -> persona profilleri/voice-lock -> VoxCPM2 adaptörü ->
  # manifest -> oynatma politikası -> ısındırma.
  speech_assets = c(
    "R/config_speech_assets.R",
    "R/config_speech_asset_paths.R",
    "R/helpers_speech_wav.R",
    "R/helpers_speech_voice_profiles.R",
    "R/helpers_speech_voxcpm2_adapter.R",
    "R/helpers_speech_manifest.R",
    "R/helpers_speech_playback_policy.R",
    "R/helpers_speech_warmup.R"
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
    "R/helpers_claude_code_bounded_scan.R",
    # Ad eşleştirme (prompt anmaları, depolama öneki -> görünen ad) hazırlık
    # katmanından ÖNCE yüklenir; girdi ve doküman seçimi buna dayanır.
    "R/helpers_claude_code_input_matching.R",
    "R/helpers_claude_code_runtime_prepare.R",
    "R/helpers_claude_code_output_sync.R",
    "R/helpers_claude_code_runtime_workdir.R",
    "R/helpers_claude_code_security_policy.R",
    "R/helpers_claude_code_path_policy.R",
    "R/helpers_claude_code_prompt_security_policy.R",
    "R/helpers_claude_code_directory_listing.R",
    # Dizin gezgini numaralandırmasını ana olay döngüsünden çıkaran worker
    # global paketi; listeleme yardımcısından SONRA yüklenmelidir.
    "R/helpers_claude_code_dir_listing_async.R",
    "R/helpers_claude_code.R",
    "R/helpers_claude_code_server_setup.R",
    "R/helpers_claude_code_streaming.R",
    "R/helpers_claude_code_formatters.R",
    "R/helpers_claude_code_downloads.R",
    "R/helpers_claude_code_downloads_html.R",
    "R/helpers_claude_code_existing_file_link.R",
    "R/helpers_claude_code_workdir_scan.R",
    "R/helpers_claude_code_file_stability.R",
    "R/helpers_claude_code_workdir_snapshot.R",
    "R/helpers_claude_code_plugins.R",
    "R/helpers_claude_code_document_extractors.R",
    "R/helpers_claude_code_documents.R",
    "R/helpers_claude_code_document_summary.R",
    # Arka plan hazırlık görevi: sınırlı tarama + girdi kopyalama + doküman
    # çıkarımı + çalıştırma öncesi snapshot. Runtime workdir, workdir scan ve
    # doküman yardımcılarından SONRA yüklenmelidir.
    "R/helpers_claude_code_run_prepare_task.R",
    # Kalıcı oturum runtime köprüsü: DB katmanı (database bölümü) ile çalışma
    # alanı modülü arasında; run_lifecycle bu köprüdeki persist çağrılarını
    # guard'lı exists() ile kullanır. Workbench oturum API fabrikası
    # (hidrasyon + yeni oturum) module_claude_code.R tarafından çağrılır.
    "R/helpers_claude_code_session_persistence.R",
    "R/helpers_claude_code_workbench_session_api.R",
    "R/helpers_claude_code_run_lifecycle.R",
    # Ana süreç tarafı: hazırlık gönderimi/aşama durumu ve süreç başlatma,
    # ardından çalıştırma sonrası çıktı işleme ve sonlandırma.
    "R/helpers_claude_code_run_dispatch.R",
    "R/helpers_claude_code_run_completion.R",
    # PR #672 Codex inceleme sertleştirmeleri. Bu iki dosya yukarıdaki Bilge
    # Yolaç yardımcılarında tanımlı fonksiyonların bir kısmını fail-closed
    # sürümleriyle DEĞİŞTİRİR; bu yüzden zincirin EN SONUNDA ve runtime ->
    # output sırasıyla yüklenmelidir. Manifest dışı geç-yükleme denenmemeli:
    # o yol dosyaları sahipsiz bırakıp (seam doctor) sessizce ölü koda çevirir.
    "R/helpers_claude_code_codex_runtime_fixes.R",
    "R/helpers_claude_code_codex_output_fixes.R"
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
    "R/helpers_stt_transcription.R",
    "R/module_stt.R",
    "R/module_character_video.R"
  ),

  # module_identity_startup: Kimlik/başlangıç modülleri: SSO, oturum zaman
  # aşımı, performans, kullanıcı kimliği, başlangıç şeridi, boot hazırlığı,
  # başlangıç ekranı, yükleme overlay, araç arka planı, kenar çubuğu kullanıcı
  # paneli ve hızlı eylemler. R/helpers_startup_lane.R saf şerit çözümlemesidir
  # ve appLoadingUI() ortam varsayılanını gömdüğü için R/module_app_loading.R'den
  # ÖNCE yüklenmelidir.
  module_identity_startup = c(
    "R/module_sso.R",
    "R/module_session_timeout.R",
    "R/module_performance.R",
    "R/module_user_identity.R",
    "R/helpers_startup_lane.R",
    "R/module_startup_lane.R",
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
  # poll, Oturumlar sayfası (UI + server) ve ana server modülü.
  module_claude_code = c(
    "R/module_claude_code_plugins.R",
    "R/module_claude_code_ui.R",
    "R/module_claude_code_akis.R",
    "R/module_claude_code_stream_poll.R",
    "R/module_claude_code_sessions_ui.R",
    "R/module_claude_code_sessions.R",
    "R/module_claude_code.R"
  ),

  # bilge_savunmasi: Bilge Savunması (kule savunma oyunu). Yapılandırma +
  # persona oyun manifesti önce, saf doğrulama/puanlama katmanı sonra, DB
  # katmanı (çekirdek altyapı -> koşu yaşam döngüsü -> eşzamansız topluluk)
  # ardından, UI ve sunucu modülü en sonda. MB_Game_* tabloları yoksa tüm
  # katman güvenli boş sonuçla çalışır (docs/bilge-savunmasi.md).
  bilge_savunmasi = c(
    "R/config_bilge_savunmasi.R",
    "R/helpers_bilge_savunmasi_validation.R",
    "R/helpers_db_bilge_savunmasi_cekirdek.R",
    "R/helpers_db_bilge_savunmasi_kosu.R",
    "R/helpers_db_bilge_savunmasi_topluluk.R",
    "R/module_bilge_savunmasi_ui.R",
    "R/module_bilge_savunmasi.R"
  ),

  # ortak_oturumlar: Ortak Oturumlar (işbirlikçi çalışma odaları): saf
  # yetki/e-posta yardımcıları önce, DB katmanı (çekirdek -> katılım -> davet
  # -> mesaj -> belge -> bakım) sonra, UI/davet/oda/hub modülleri en sonda.
  # DB katmanı MB_OrtakOturumlar ailesini yönetir; kişisel MB_Chats /
  # MB_ClaudeCode_* tablolarına yazmaz (docs/ortak-oturumlar.md).
  ortak_oturumlar = c(
    "R/helpers_ortak_oturum_permissions.R",
    "R/helpers_ortak_oturum_sunum.R",
    "R/helpers_ortak_oturum_email.R",
    "R/helpers_ortak_oturum_db.R",
    "R/helpers_ortak_oturum_db_katilim.R",
    "R/helpers_ortak_oturum_db_davet.R",
    "R/helpers_ortak_oturum_db_mesajlar.R",
    "R/helpers_ortak_oturum_db_bilge_yolac.R",
    "R/helpers_ortak_oturum_db_kuyruk.R",
    "R/helpers_ortak_oturum_files.R",
    "R/helpers_ortak_oturum_belgeler.R",
    "R/helpers_ortak_oturum_arac_uretim.R",
    "R/helpers_ortak_oturum_arac.R",
    "R/helpers_ortak_oturum_bakim.R",
    "R/helpers_ortak_oturum_by_calisma_alani.R",
    "R/helpers_ortak_oturum_by_akis.R",
    "R/helpers_ortak_oturum_ws_kopyalama.R",
    "R/helpers_ortak_oturum_yanit_icerik.R",
    "R/module_ortak_oturum_room_ui.R",
    "R/module_ortak_oturum_belge_paneli.R",
    "R/module_ortak_oturum_arac.R",
    "R/module_ortak_oturum_invites.R",
    "R/module_ortak_oturum_yz.R",
    "R/module_ortak_oturum_by_calistirma.R",
    "R/module_ortak_oturum_bilge_yolac.R",
    "R/module_ortak_oturum_room.R",
    "R/module_ortak_calismalar.R"
  ),

  # module_analysis: Proje/Kaynak Analizi modülü.
  module_analysis = c(
    "R/module_proje_kaynak_analizi.R",
    # Faz 6: PK gözlemci sarmalayıcıları (işçi-güvenli; bootstrap yüzeyinde de).
    # Doğrudan-çıkış sarmalayıcısı `.pk_worker_is_wrapped()` kullanır: SIRA ÖNEMLİ.
    "R/helpers_pk_worker_observers.R",
    "R/helpers_pk_worker_direct_exit.R"
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
    "R/module_admin_bilge_yolac.R",
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

  # server_handlers_send_message: Server handler/gönderme hattı: hibrit konuşma
  # çalışma zamanı (statik karşılama/rehberlik + kişisel önek) ve PCM akış
  # köprüsü, TTS/müzik/AI Uzman handler'ları, özetleme/görsel üretimi/gerçek
  # streaming handler'ları, LLM yanıt handler'ları ve send_message. Konuşma
  # çalışma zamanı, ai_expert handler'larından ÖNCE yüklenmelidir.
  server_handlers_send_message = c(
    "R/server_speech_assets_runtime.R",
    "R/server_speech_pcm_stream.R",
    "R/server_tts_handlers.R",
    "R/server_music_handlers.R",
    "R/server_ai_expert_handlers.R",
    "R/server_handler_summarization.R",
    "R/server_handler_image_generation.R",
    "R/server_handler_langflow.R",
    "R/helpers_llm_true_streaming_worker.R",
    "R/server_handler_true_streaming.R",
    "R/server_handler_streaming_tts.R",
    # Faz 6: PK gönderim katmanı; uygulama yardımcıları orkestratörden, ikisi de
    # send_message'dan ÖNCE (o DELEGE eder).
    # Sıra: istek işaretleri -> kayıt defteri -> yönlendirme -> yaşam döngüsü.
    "R/helpers_pk_async_request_markers.R",
    "R/helpers_pk_async_session_registry.R",
    "R/helpers_pk_async_routing.R",
    "R/helpers_pk_async_lifecycle.R",
    "R/helpers_pk_async_apply.R",
    "R/server_handler_pk_async.R",
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

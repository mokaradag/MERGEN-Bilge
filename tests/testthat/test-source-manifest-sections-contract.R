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

  # Zorunlu sıra ve OPSİYONEL yol tanımları ayrı VERİ dosyalarındadır
  # (Faz 4, E5): manifest tek satır bakım borcu tavanına dayanmıştı.
  for (manifest_dosyasi in c("bootstrap_source_manifest.R", "config_source_manifest.R")) {
    source(
      file.path(repo_root, "R", manifest_dosyasi),
      encoding = "UTF-8",
      local = manifest_env
    )
  }

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
  "pk_query_metadata",
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
  "speech_assets",
  "claude_code_helpers",
  "llm_pipeline",
  "module_chat",
  "module_files_media",
  "module_settings_api_key",
  "module_ai_audio",
  "module_identity_startup",
  "module_claude_code",
  "bilge_savunmasi",
  "ortak_oturumlar",
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
  # Bilinçli güncelleme: kök sayfa (GET /) HTML önbelleği yardımcısı
  # (R/helpers_index_page_cache.R) perf instrumentation'dan sonra eklendi. 8 -> 9.
  # 9 -> 10 bilinçli güncelleme: günlük log dosyası yardımcıları
  # (R/config_logging_daily_file.R) config_logging.R fonksiyon-yoğunluk bölmesiyle
  # ayrı dosyaya alındı; config_logging.R'den ÖNCE yüklenir.
  # 10 -> 13 bilinçli güncelleme: süreç-içi çalışma-zamanı metrikleri
  # (R/helpers_runtime_metrics.R), backpressure kabul-denetimi
  # (R/helpers_request_backpressure.R) ve sağlık/hazırlık + kök sayfa
  # yönlendiricisi (R/helpers_app_http_routes.R) yatay-ölçekleme/performans için
  # eklendi; metrikler index önbelleğinden ÖNCE, router index önbelleğinden SONRA.
  foundation = list(first = "R/config_packages.R", last = "R/helpers_worker_monitor.R", n = 13L),
  post_future_utils = list(first = "R/utils_path_helpers.R", last = "R/utils_excel_reader.R", n = 9L),
  # config_app_core n = 7L -> 8L bilinçli güncelleme: indeks kilidi
  # (R/config_file_store_index_lock.R) fonksiyon-yoğunluk bölmesiyle ayrı dosyaya alındı.
  config_app_core = list(first = "R/config_sso.R", last = "R/config_version_history.R", n = 8L),
  config_api_model_keys = list(first = "R/helpers_vision_model_capabilities.R", last = "R/helpers_api_key_password_toggle.R", n = 9L),
  config_claude_code = list(first = "R/config_claude_code.R", last = "R/config_claude_code_plugins.R", n = 2L),
  # Bilinçli güncelleme: bölge VERİSİ (config_ui_asset_zones.R) ile bölge
  # DOĞRULAYICI API'si (config_ui_asset_zone_validators.R) ayrı dosyalara
  # bölündü; en büyük runtime dosyası 777 satırdan iki dosyaya indi. 2 -> 3.
  # Bilinçli güncelleme: varlık manifesti VERİ/DOĞRULAYICI/RENDER olarak üç
  # dosyaya bölündü (config_ui_asset_validators.R + config_ui_asset_tags.R);
  # config_ui_assets.R 690 satırdan VERİ-odaklı dosyaya indi. 3 -> 5.
  config_ui_assets = list(first = "R/config_ui_assets.R", last = "R/config_ui_asset_zone_validators.R", n = 5L),
  # Bilinçli güncelleme: seam guard test/odaklı doğrulama listesi AYRI veri
  # dosyasına (R/config_seam_guard_tests.R) çıkarıldı. Kayıt defteri tam
  # 580/580 bakım tavanındaydı ve Faz 4 guard testleri bu yüzden hiçbir
  # seam'e KAYDEDİLEMİYORDU. Birleştirme mergen_seam_registry() içindedir;
  # genel API değişmedi. 1 -> 2 dosya.
  architecture_governance = list(first = "R/config_seam_guard_tests.R", last = "R/config_seam_registry.R", n = 2L),
  # database n = 12L -> 13L bilinçli güncelleme: işlem-güvenli DB bağlantı havuzu
  # (R/helpers_db_pool.R) helpers_db_connection.R'den SONRA bölüme eklendi.
  # 13L -> 15L bilinçli güncelleme: Bilge Yolaç kalıcı oturum katmanı
  # (R/helpers_db_claude_code_session_queries.R + R/helpers_db_claude_code_sessions.R)
  # helpers_db_feedback.R'den sonra, helpers_database.R'den önce eklendi.
  # 15L -> 16L bilinçli güncelleme: Bilge Yolaç arşiv geri yükleme + KALICI silme
  # yaşam döngüsü (R/helpers_db_claude_code_session_lifecycle.R) orkestrasyon
  # dosyasından SONRA, helpers_database.R'den önce eklendi (ratchet bütçesi).
  # 16L -> 17L bilinçli güncelleme: Hızlı Başlangıç "Son Konuşmalar" ön izleme
  # worker katmanı (R/helpers_startup_chat_preview.R) helpers_db_chat_readers.R
  # sonrası, helpers_db_chat_mutations.R öncesi eklendi.
  database = list(first = "R/helpers_db_unicode_escape.R", last = "R/helpers_database.R", n = 17L),
  # Faz 3a: sorgu metadata sözleşmesi. Türkçe katlama yardımcısı + sözlük/
  # doğrulayıcı + erişimci yardımcıları, ardından dört veri katmanı
  # (iskelet -> üretilen -> küre edilmiş -> yerel alias) ve birleştirici;
  # hepsi R/config_sql_loader.R'den ÖNCE (master plan §6 zorunlu sırası).
  pk_query_metadata = list(first = "R/helpers_pk_text_turkish.R", last = "R/helpers_pk_query_meta.R", n = 8L),
  sql_library = list(first = "R/library_queries.R", last = "R/config_sql_loader.R", n = 2L),
  language_messaging = list(first = "R/helpers_language.R", last = "R/helpers_messaging.R", n = 2L),
  mcp_tools = list(first = "R/helpers_mcp_context.R", last = "R/helpers_mcp_tools.R", n = 9L),
  chartlab_helpers = list(first = "R/helpers_chartlab_spec.R", last = "R/helpers_chartlab.R", n = 2L),
  # 5L -> 9L bilinçli güncelleme: bloklamayan dosya alım hattı (saf plan ->
  # worker -> kuyruk -> ana süreç runtime) helpers_files.R'den SONRA eklendi.
  files_preview_pipeline = list(first = "R/helpers_image_gallery.R", last = "R/helpers_file_ingestion_runtime.R", n = 9L),
  file_manager_helpers = list(first = "R/helpers_file_manager_policy.R", last = "R/helpers_file_manager_table_runtime.R", n = 12L),
  # Bilinçli güncelleme: R/helpers_langflow_runtime.R (kurumsal Langflow akış
  # çağrısı saf yardımcıları) send_message core'dan sonra bölüme eklendi; 11 -> 12.
  # 12 -> 13 bilinçli güncelleme: Langflow belge kaynak çıkarımı + tıklanabilir
  # Kaynakça işaretleyici yardımcıları (R/helpers_langflow_sources.R)
  # helpers_langflow_runtime.R'den SONRA eklendi (.langflow_pluck bağımlılığı).
  # 13 -> 14 bilinçli güncelleme: Langflow düzyazı "Kaynak:" bölümü + satır içi
  # <sup>(n)</sup> atıf yükseltme yardımcıları (R/helpers_langflow_inline_sources.R)
  # helpers_langflow_sources.R'den SONRA eklendi (marker bloğu bağımlılığı).
  chat_send_message_runtime = list(first = "R/helpers_chat_runtime.R", last = "R/helpers_quick_action_intro_messages.R", n = 15L),
  summarization_followup = list(first = "R/helpers_summarization_modes.R", last = "R/helpers_followup_questions.R", n = 3L),
  # Faz 0 (Proje ve Kaynak Analizi yeniden inşası): yapılandırma çözümleyicisi,
  # köken/bozulma ve telemetri yardımcıları bölümün BAŞINA eklendi
  # (bağımlılık sırası: config -> provenance -> telemetry).
  # n: 11 -> 13. R/helpers_deep_analysis.R bakım borcu ratchet bütçesini aştığı
  # için iki saf yardımcıya bölündü (detail + context) ve ikisi de bu bölüme,
  # orkestratörden ÖNCE eklendi. Bkz. test-deep-analysis-split-contract.R.
  # Bilinçli güncelleme (Faz 1 — cerrahi doğruluk): koşulsuz güvenlik katmanı
  # (safe_errors / sql_readonly / rls) + v2 davranış katmanı (filter_compile /
  # filter_policy / filters_v2) + saf istem katmanı (prompt_budget /
  # analysis_prompts) eklendi + saf istatistiksel özet kurucusu; 13 -> 22 dosya.
  # Bilinçli güncelleme: PR #698 inceleme düzeltmeleri —
  # R/helpers_pk_export_csv.R (akışlı + doğrulanmış CSV yedeği ve çakışmasız
  # dosya yolu tabanı) export_plan ile export_xlsx arasına eklendi; 30 -> 31.
  # n 31 -> 35: Faz 4 varlık çözümleme dört saf dosya ekledi.
  # Bilinçli güncelleme: Faz 4 (§5.4) varlık çözümleme hattı bölüme eklendi
  # (morfoloji -> normalleştirme -> anım -> alias -> puanlama -> tarama ->
  # karar -> geçmiş -> filtre hattına bağlama); 35 -> 40 dosya.
  # Bilinçli güncelleme: Faz 5 (§5.2) iki geçişli sorgu seçimi beş dosya
  # ekledi (getirim -> istem -> ayrıştırma/karar -> LLM -> bağlama); 40 -> 45.
  # PR #701 inceleme düzeltmeleri: history/seed/deep sahipleri ayrıştırıldı;
  # analysis_helpers bölümüne üç kayıt daha eklendi. 53 -> 56.
  analysis_helpers = list(first = "R/helpers_pk_config.R", last = "R/helpers_pk_query_selection_apply.R", n = 56L),
  sso_identity_helpers = list(first = "R/helpers_sso_signature.R", last = "R/helpers_logout_url.R", n = 3L),
  # Bilinçli güncelleme: R/helpers_release_evidence.R (release kanıt artifact
  # okuyucusu) health_checks'ten önce bölüme eklendi; 6 -> 7 dosya.
  support_admin_health_helpers = list(first = "R/helpers_destek_database.R", last = "R/helpers_health_checks.R", n = 7L),
  # Bilinçli güncelleme: R/helpers_ai_expert_handlers_support.R (AI Uzman handler
  # saf karar yardımcıları) bölüm sonuna eklendi; 3 -> 4 dosya.
  ai_expert_helpers = list(first = "R/helpers_ai_expert_user_data.R", last = "R/helpers_ai_expert_handlers_support.R", n = 5L),
  # Bilinçli güncelleme: hibrit VoxCPM2 konuşma katmanı (speech_assets) yeni
  # bölüm olarak ai_expert_helpers'tan sonra eklendi (8 dosya; yapı tanımı +
  # yol kurucuları fonksiyon-yoğunluk bölmesiyle iki dosyadır).
  speech_assets = list(first = "R/config_speech_assets.R", last = "R/helpers_speech_warmup.R", n = 8L),
  # 26 -> 27: doküman özetleme orkestrasyonu helpers_claude_code_documents.R'den
  # R/helpers_claude_code_document_summary.R'ye ayrıldı (documents'tan sonra,
  # run_lifecycle'dan önce).
  # 27 -> 29: kalıcı oturum runtime köprüsü
  # (R/helpers_claude_code_session_persistence.R) ve workbench oturum API
  # fabrikası (R/helpers_claude_code_workbench_session_api.R) run_lifecycle'dan
  # önce eklendi.
  # 29L -> 36L bilinçli güncelleme: Bilge Yolaç bloklamayan çalıştırma hattı.
  # Sınırlı tarayıcı (bounded_scan), izole runtime hazırlığı (runtime_prepare),
  # yalnızca-değişen çıktı aktarımı (output_sync), dosya kararlılık beklemesi
  # (file_stability), arka plan hazırlık görevi (run_prepare_task) ile ana
  # süreç gönderim/sonlandırma katmanları (run_dispatch, run_completion).
  # 36L -> 38L bilinçli güncelleme: PR #672 Codex sertleştirme dosyaları
  # manifest dışı geç-yükleme yerine bölümün sonuna alındı (sahipsiz runtime
  # dosyası + sessiz ölü kod sorununu giderir).
  claude_code_helpers = list(first = "R/helpers_claude_code_user_guard.R", last = "R/helpers_claude_code_codex_output_fixes.R", n = 40L),
  llm_pipeline = list(first = "R/helpers_llm_tool_formatters.R", last = "R/helpers_llm_worker.R", n = 11L),
  module_chat = list(first = "R/module_chat_history_background.R", last = "R/module_feedback.R", n = 9L),
  module_files_media = list(first = "R/module_file_manager_ui.R", last = "R/module_summarization.R", n = 7L),
  module_settings_api_key = list(first = "R/module_settings_kisisel.R", last = "R/module_api_key.R", n = 7L),
  # 6L -> 7L bilinçli güncelleme: STT ses parçası çevirisi SAF worker-güvenli
  # yardımcısı (R/helpers_stt_transcription.R) module_stt.R'den ÖNCE eklendi;
  # ağır av dönüştürme + HTTP POST arka plana (tracked_future_promise) taşındı.
  module_ai_audio = list(first = "R/module_ai_processing.R", last = "R/module_character_video.R", n = 7L),
  # Bilinçli güncelleme: başlangıç şeridi (startup lane) için saf çözümleme
  # yardımcıları (R/helpers_startup_lane.R; appLoadingUI ortam varsayılanını
  # gömer) ve şerit sunucu gözlemcileri (R/module_startup_lane.R;
  # startupScreenObserversInit delege eder) bölüme eklendi. 12 -> 14.
  module_identity_startup = list(first = "R/module_sso.R", last = "R/module_quick_actions.R", n = 14L),
  # 5 -> 7 bilinçli güncelleme: Bilge Yolaç Oturumları sayfası
  # (R/module_claude_code_sessions_ui.R + R/module_claude_code_sessions.R)
  # stream_poll'dan sonra, ana server modülünden önce eklendi.
  module_claude_code = list(first = "R/module_claude_code_plugins.R", last = "R/module_claude_code.R", n = 7L),
  # Bilinçli ekleme: Bilge Savunması (kule savunma oyunu) bölümü.
  # Yapılandırma/persona manifesti + saf doğrulama + MB_Game_* DB katmanı
  # (çekirdek -> koşu -> topluluk) + UI/sunucu modülü (7 dosya,
  # module_claude_code'dan sonra, ortak_oturumlar'dan önce).
  bilge_savunmasi = list(first = "R/config_bilge_savunmasi.R", last = "R/module_bilge_savunmasi.R", n = 7L),
  # Bilinçli güncelleme: Ortak Oturumlar (işbirlikçi çalışma odaları) bölümü
  # eklendi: saf yetki/e-posta yardımcıları + MB_OrtakOturumlar DB katmanı +
  # oda/davet/hub modülleri (12 dosya, module_claude_code'dan sonra).
  # 21L -> 22L bilinçli güncelleme: Ortak Bilge Yolaç çalışma alanı SAF
  # yardımcıları (R/helpers_ortak_oturum_by_calisma_alani.R; özel proje dizini
  # izolasyon kapısı + panel kart üreticileri) modül dosyalarından önce eklendi.
  # 22L -> 24L bilinçli güncelleme: Ortak Bilge Yolaç CANLI çalıştırma seti:
  # akış SAF yardımcıları (R/helpers_ortak_oturum_by_akis.R; yan dosyalar +
  # ilerleme kayıtları/metni) ve CANLI çalıştırma köprüsü
  # (R/module_ortak_oturum_by_calistirma.R; stream-json ajan yürütmesi +
  # KismiYanit ilerleme yayını + durdurma) eklendi.
  ortak_oturumlar = list(first = "R/helpers_ortak_oturum_permissions.R", last = "R/module_ortak_calismalar.R", n = 27L),
  module_analysis = list(first = "R/module_proje_kaynak_analizi.R", last = "R/module_proje_kaynak_analizi.R", n = 1L),
  module_support = list(first = "R/module_destek_yardim.R", last = "R/module_destek.R", n = 6L),
  # Bilinçli güncelleme: at-budget admin modüllerinin inline highcharter/DT
  # renderer'ları *_outputs() dosyalarına çıkarıldı (geri_bildirim + yanit);
  # her modül bölüme bir *_outputs dosyası ekledi. 19 -> 21.
  # 22L -> 23L bilinçli güncelleme: Bilge Yolaç yönetici sekmesi ayrı modül
  # dosyasına (R/module_admin_bilge_yolac.R) çıkarıldı; diğer admin sekme
  # modülleriyle aynı desen. module_admin_gelismis_analizler.R'den sonra,
  # koordinatör module_admin_analytics.R'den önce eklendi.
  module_admin = list(first = "R/module_admin_genel_bakis.R", last = "R/module_admin_documentation.R", n = 23L),
  module_health_chartlab = list(first = "R/module_health_worker_metrics.R", last = "R/module_chartlab.R", n = 10L),
  # Bilinçli güncelleme: SSO auth-ready / yenilenebilir modül wiring katmanı
  # R/server_runtime_auth_ready.R dosyasına ayrıldı (server_runtime_context.R'den
  # sonra). 13 -> 14.
  server_init_runtime = list(first = "R/server_session_cache.R", last = "R/server_init_chat_runtime.R", n = 14L),
  server_core_outputs_welcome = list(first = "R/server_core_observer_runtime.R", last = "R/server_welcome_handlers.R", n = 7L),
  server_observers = list(first = "R/server_observers_startup.R", last = "R/server_observers_misc.R", n = 11L),
  # Bilinçli güncelleme: R/server_handler_langflow.R (Süreç/Uygulama Uzmanı
  # Langflow işleyicisi) görsel üretim handler'ından sonra bölüme eklendi; 10 -> 11.
  # 11 -> 13 bilinçli güncelleme: hibrit konuşma çalışma zamanı
  # (R/server_speech_assets_runtime.R) ve PCM akış köprüsü
  # (R/server_speech_pcm_stream.R) bölüm başına eklendi; ai_expert
  # handler'larından önce yüklenirler.
  server_handlers_send_message = list(first = "R/server_speech_assets_runtime.R", last = "R/server_send_message.R", n = 13L)
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
  # 262L -> 263L bilinçli güncelleme: R/module_health_release.R (Sistem Durumu
  # "Release Kanıtı" sekmesi) module_health_chartlab bölümüne eklendi.
  # 263L -> 264L bilinçli güncelleme: R/helpers_ai_expert_user_data.R (AI Uzman
  # worker-safe DB okuyucuları) ai_expert_helpers bölümüne eklendi.
  # 264L -> 265L bilinçli güncelleme: R/helpers_ai_expert_handlers_support.R
  # (AI Uzman handler saf karar yardımcıları) ai_expert_helpers bölümüne eklendi.
  # 265L -> 266L bilinçli güncelleme: R/config_ui_asset_zone_validators.R
  # (frontend bölge doğrulayıcı API'si; VERİ/DOĞRULAYICI ayrımı) config_ui_assets
  # bölümüne eklendi.
  # 266L -> 268L bilinçli güncelleme: at-budget admin modüllerinin inline
  # renderer'ları R/module_admin_geri_bildirim_outputs.R ve
  # R/module_admin_yanit_analizi_outputs.R dosyalarına çıkarıldı.
  # 268L -> 269L bilinçli güncelleme: derin uzay giriş ekranı UI'si
  # R/module_startup_screen_ui.R dosyasına çıkarıldı (UI/sunucu ayrımı).
  # 269L -> 270L bilinçli güncelleme: görsel oluşturma UI/HTML render katmanı
  # R/module_image_generation_ui.R dosyasına çıkarıldı (UI/runtime ayrımı).
  # 270L -> 271L bilinçli güncelleme: Yapılandırma gelişmiş UI kartları
  # R/module_settings_yapilandirma_advanced_ui.R dosyasına çıkarıldı.
  # 271L -> 272L bilinçli güncelleme: Geri Bildirim Analizi detay/kullanıcı
  # tablo veri hazırlama helpers_admin_geri_bildirim_output_tables.R dosyasına çıkarıldı.
  # 272L -> 273L bilinçli güncelleme: opt-in performans ölçüm yardımcısı
  # logging sonrası foundation bölümüne eklendi.
  # 273L -> 274L bilinçli güncelleme: kök sayfa (GET /) HTML önbelleği yardımcısı
  # R/helpers_index_page_cache.R foundation bölümüne eklendi.
  # 274L -> 275L bilinçli güncelleme: günlük log dosyası yardımcıları
  # R/config_logging_daily_file.R config_logging.R'den ayrılıp foundation
  # bölümüne (config_logging.R'den ÖNCE) eklendi.
  # 275L -> 276L bilinçli güncelleme: TTS açık streaming dalı send_message'tan
  # R/server_handler_streaming_tts.R dosyasına çıkarıldı (gerçek SSE /
  # non-streaming dallarıyla simetrik handler).
  # 276L -> 277L bilinçli güncelleme: sohbet okuma SQL sorgu üreticileri
  # R/helpers_db_chat_read_queries.R dosyasına çıkarıldı (helpers_db_chat_readers.R
  # orkestrasyonundan ayrı, saf ASCII SQL; encoding sınırına dokunmaz).
  # 277L -> 279L bilinçli güncelleme: varlık manifesti VERİ/DOĞRULAYICI/RENDER
  # olarak üç dosyaya bölündü; R/config_ui_asset_validators.R (çözümleyici/
  # doğrulayıcı API'si) ve R/config_ui_asset_tags.R (htmltools etiket render
  # katmanı) config_ui_assets bölümüne eklendi.
  # 279L -> 280L bilinçli güncelleme: SSO auth-ready / yenilenebilir modül wiring
  # katmanı R/server_runtime_auth_ready.R server_init_runtime bölümüne eklendi
  # (server_runtime_context.R'den sonra, server_runtime_function_slot.R'den önce).
  # 280L -> 281L bilinçli güncelleme: işlem-güvenli DB bağlantı havuzu katmanı
  # R/helpers_db_pool.R database bölümüne (helpers_db_connection.R'den sonra) eklendi.
  # 281L -> 282L bilinçli güncelleme: Bilge Yolaç doküman özetleme orkestrasyonu
  # R/helpers_claude_code_document_summary.R claude_code_helpers bölümüne
  # (helpers_claude_code_documents.R'den sonra, run_lifecycle'dan önce) eklendi.
  # 282L -> 283L bilinçli güncelleme: gerçek SSE worker-export globals fabrikası
  # R/helpers_llm_true_streaming_worker.R server_handlers_send_message bölümüne
  # (server_handler_true_streaming.R'den ÖNCE) eklendi.
  # 283L -> 284L bilinçli güncelleme: Dosya Yönetimi attach/client
  # yardımcıları R/helpers_file_manager_attach_client.R dosyasına çıkarıldı
  # ve file_manager_helpers bölümünde tablo runtime öncesine eklendi.
  # 285L -> 288L bilinçli güncelleme: yatay-ölçekleme/performans için foundation
  # bölümüne süreç-içi çalışma-zamanı metrikleri (R/helpers_runtime_metrics.R),
  # backpressure kabul-denetimi (R/helpers_request_backpressure.R) ve sağlık/
  # hazırlık + kök sayfa yönlendiricisi (R/helpers_app_http_routes.R) eklendi.
  # 288L -> 290L bilinçli güncelleme: akış olay-döngüsü sertleştirmesi için
  # chat_send_message_runtime bölümüne artımlı akış G/Ç + uyarlanır yoklama
  # (R/helpers_streaming_io.R) ve takip/saved-chats yük denetimi
  # (R/helpers_stream_load_control.R) yardımcıları eklendi.
  # 290L -> 292L bilinçli güncelleme: kurumsal Langflow entegrasyonu için
  # saf yardımcılar (R/helpers_langflow_runtime.R, chat_send_message_runtime)
  # ve Süreç/Uygulama Uzmanı işleyicisi (R/server_handler_langflow.R,
  # server_handlers_send_message) eklendi.
  # 292L -> 294L bilinçli güncelleme: başlangıç şeridi (Hızlı Başlangıç /
  # Zengin Deneyim) için saf çözümleme yardımcıları (R/helpers_startup_lane.R)
  # ve şerit sunucu gözlemcileri (R/module_startup_lane.R) eklendi
  # (module_identity_startup bölümü).
  # 294L -> 300L bilinçli güncelleme: Bilge Yolaç kalıcı oturum katmanı eklendi:
  # DB saf sorgu + orkestrasyon yardımcıları (database bölümü, +2), runtime
  # persist köprüsü + workbench oturum API fabrikası (claude_code_helpers
  # bölümü, +2) ve Oturumlar sayfası UI/server modülleri (module_claude_code
  # bölümü, +2).
  # 300L -> 302L bilinçli güncelleme: Oturumlar sayfasına arşiv geri yükleme +
  # KALICI silme yaşam döngüsü (R/helpers_db_claude_code_session_lifecycle.R,
  # database bölümü +1) ve yönetici paneli Bilge Yolaç istatistik sekmesi
  # (R/module_admin_bilge_yolac.R, module_admin bölümü +1) eklendi.
  # 302L -> 314L bilinçli güncelleme: Ortak Oturumlar bölümü (ortak_oturumlar)
  # 12 dosyayla eklendi: saf yetki/e-posta yardımcıları, MB_OrtakOturumlar DB
  # katmanı (çekirdek/katılım/davet/mesaj/belge/bakım) ve oda/davet/hub modülleri.
  # 314L -> 319L bilinçli güncelleme: Ortak Oturumlar tamamlama seti +5 dosya:
  # saf sunum-karar yardımcıları (R/helpers_ortak_oturum_sunum.R; rol etiketi /
  # canlı durum rozeti), yapay zekâ kuyruğu/kısmi yayın/geçmiş kopyalama DB
  # katmanı (R/helpers_ortak_oturum_db_kuyruk.R), Ortak Bilge Yolaç DB katmanı
  # (R/helpers_ortak_oturum_db_bilge_yolac.R; mesaj/kilit katmanından ayrıldı),
  # yapay zekâ üretim motoru (R/module_ortak_oturum_yz.R) ve Ortak Bilge Yolaç
  # çalışma alanı köprüsü (R/module_ortak_oturum_bilge_yolac.R).
  # 319L -> 323L bilinçli güncelleme: Ortak Söyleşi büyütme seti +4 dosya:
  # paylaşılan belge girdileri DB/depolama katmanı
  # (R/helpers_ortak_oturum_belgeler.R), araç seçici saf karar/plan katmanı
  # (R/helpers_ortak_oturum_arac.R), Ortak Belgeler paneli + sohbeti temizle
  # bağlayıcısı (R/module_ortak_oturum_belge_paneli.R) ve araç seçici UI/model
  # kilidi bağlayıcısı (R/module_ortak_oturum_arac.R).
  # 323L -> 324L bilinçli güncelleme: Ortak Bilge Yolaç çalışma alanı SAF
  # yardımcıları (R/helpers_ortak_oturum_by_calisma_alani.R; özel proje dizini
  # izolasyon kapısı + etkin dizin çözümü + panel kart üreticileri) eklendi.
  # 324L -> 325L bilinçli güncelleme: Hızlı Başlangıç "Son Konuşmalar" ön izleme
  # worker katmanı (R/helpers_startup_chat_preview.R; dar explicit worker-export
  # sözleşmesi + ana süreç biçimlendirme) database bölümüne eklendi.
  # 325L -> 327L bilinçli güncelleme: Ortak Bilge Yolaç CANLI çalıştırma seti
  # (R/helpers_ortak_oturum_by_akis.R + R/module_ortak_oturum_by_calistirma.R)
  # ortak_oturumlar bölümüne eklendi.
  # 327L -> 328L bilinçli güncelleme: Langflow belge kaynak çıkarımı +
  # tıklanabilir Kaynakça işaretleyici yardımcıları
  # (R/helpers_langflow_sources.R) chat_send_message_runtime bölümüne eklendi.
  # 328L -> 331L bilinçli güncelleme: Ortak Oturum onarım/büyütme seti:
  # çalışma alanı kopyalama aşamalı tanılama yardımcıları
  # (R/helpers_ortak_oturum_ws_kopyalama.R) ve yapay zekâ yanıtı zengin içerik
  # katmanı (R/helpers_ortak_oturum_yanit_icerik.R; kod blokları + chartlab)
  # ortak_oturumlar bölümüne; düşünme paneli plan/kabuk yardımcıları
  # (R/helpers_send_message_thinking_panel.R; request_lifecycle bölünmesi)
  # chat_send_message_runtime bölümüne eklendi.
  # 332L -> 333L bilinçli güncelleme: Langflow düzyazı "Kaynak:" bölümü + satır içi
  # <sup>(n)</sup> atıf yükseltme yardımcıları (R/helpers_langflow_inline_sources.R)
  # chat_send_message_runtime bölümüne eklendi.
  # 333L -> 343L bilinçli güncelleme: hibrit VoxCPM2 konuşma katmanı: yeni
  # speech_assets bölümü (8 dosya) + server_handlers_send_message başına
  # R/server_speech_assets_runtime.R ve R/server_speech_pcm_stream.R eklendi.
  # 343L -> 350L bilinçli güncelleme: Bilge Savunması bölümü (7 dosya:
  # config + doğrulama + MB_Game_* DB katmanı + UI/sunucu modülü) eklendi.
  # 350L -> 351L bilinçli güncelleme: AI Uzman TTS parça hattı (sınırlı
  # eşzamanlılık + sıralı teslim + başlangıç tamponu kapısı)
  # R/helpers_ai_expert_chunk_pipeline.R olarak ai_expert_helpers bölümüne
  # (chunking'den sonra) eklendi.
  # 351L -> 352L bilinçli güncelleme: STT ses parçası çevirisi SAF worker-güvenli
  # yardımcısı (R/helpers_stt_transcription.R) module_ai_audio bölümüne
  # (module_stt.R'den ÖNCE) eklendi.
  # 352L -> 356L bilinçli güncelleme: bloklamayan dosya alım (ingestion) hattı
  # files_preview_pipeline bölümüne (helpers_files.R'den SONRA) eklendi:
  # saf plan (R/helpers_file_ingestion_task.R), worker yürütme
  # (R/helpers_file_ingestion_worker.R), sınırlı eşzamanlılık/kuyruk
  # (R/helpers_file_ingestion_queue.R) ve ana süreç orkestrasyonu
  # (R/helpers_file_ingestion_runtime.R).
  # 356L -> 363L bilinçli güncelleme: Bilge Yolaç bloklamayan çalıştırma hattı
  # için eklenen yedi yeni yardımcı dosya (claude_code_helpers bölümü).
  # 363L -> 365L bilinçli güncelleme: PR #672 Codex sertleştirme dosyaları
  # (runtime + output) manifeste alındı; önceki manifest dışı geç-yükleme
  # onları seam sahipliği olmayan ölü koda çeviriyordu.
  # 365L -> 366L bilinçli güncelleme: dizin gezgini numaralandırması ana Shiny
  # olay döngüsünden çıkarıldı (R/helpers_claude_code_dir_listing_async.R).
  # 367 -> 371: Faz 0 dört PK yardımcısı ekledi (config/provenance/telemetry-record/telemetry).
  # 371 -> 373: Faz 0 ayrıca iki temel dosya ekledi (telemetry_base/analysis_filters_base);
  # bunlar sarmalayıcılarından hemen önce yüklenir.
  # 373 -> 381: Faz 3a yeni `pk_query_metadata` bölümünü ekledi (8 dosya):
  # Türkçe katlama + metadata sözlük/erişim/birleştirme yardımcıları ve dört
  # veri katmanı. İkisi (meta_local / aliases_local) BİLİNÇLİ olarak
  # opsiyoneldir ve bulut checkout'unda bulunmaz; aşağıdaki eksik-dosya
  # kontrolü onları opsiyonel listesi üzerinden hariç tutar.
  # 381 -> 383: helpers_deep_analysis_detail.R + helpers_deep_analysis_context.R
  # 383 -> 392: Faz 1 (cerrahi doğruluk) dokuz yeni PK yardımcı dosyası
  # (ratchet bölünmesi, analysis_helpers bölümü).
  # 392 -> 400: Faz 2 (deterministik analiz + dışa aktarım) sekiz yeni PK
  # yardımcı dosyası: paket istatistikleri/kurucusu/metni, sayısal köken,
  # dışa aktarım planı/G-Ç, yanıt kompozisyonu ve sonuç kurucusu.
  # 400 -> 401: PR #698 inceleme düzeltmeleri, R/helpers_pk_export_csv.R.
  # 401 -> 405: Faz 4 varlık çözümleme (normalize/score/resolver/history).
  # 411 -> 416: Faz 5 sorgu seçimi (retrieval/prompt/parse/ai/apply).
  # 416 -> 423: Faz 5 inceleme düzeltmeleri (json/config/payload/requirements/
  # decide/degraded/session bölünmeleri; ratchet bütçeleri korunur).
  # 424 -> 427: PR #701 history/seed/deep seçim sahiplerini manifeste ekledi.
  expect_equal(length(runtime), 427L, info = "Toplam kaynak sayısı beklenenden farklı.")

  duplicate_paths <- unique(runtime[duplicated(runtime)])
  duplicate_r_paths <- duplicate_paths[grepl("^R/", duplicate_paths)]

  expect_equal(
    duplicate_r_paths,
    character(0),
    info = paste("Bölümlenmiş manifestte tekrar eden R/ kaydı:", paste(duplicate_r_paths, collapse = ", "))
  )

  # Bilinçli olarak opsiyonel işaretlenmiş yollar bir çalışma kopyasında
  # bulunmayabilir (boot güvenliği sözleşmesi).
  opsiyonel <- as.character(
    .load_source_manifest_env_for_sections()$source_manifest_optional_source_paths %||% character(0)
  )
  missing_paths <- setdiff(runtime[!file.exists(file.path(repo_root, runtime))], opsiyonel)

  expect_equal(
    missing_paths,
    character(0),
    info = paste("Bölümlenmiş manifestte olmayan dosyalar:", paste(missing_paths, collapse = ", "))
  )
})
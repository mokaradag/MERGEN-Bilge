# MERGEN Bilge — Özellik Sahiplik Haritası

Bu belge bakımcı/kodlama ajanı için hızlı yön bulma amaçlıdır: "X özelliği hangi
dosyalarda, hangi testlerle, hangi DB tablosu/servisle korunuyor ve sıradaki
sertleştirme hedefi ne?" Otoritatif çalışma kuralları için [`../CLAUDE.md`](../CLAUDE.md),
mimari için [`architecture-map.md`](architecture-map.md), seam sahipliği için
`R/config_seam_registry.R` esas alınır. Burası kısa tutulur; uzun anlatım değil
navigasyon tablosudur.

Seam karşılığı sütunu `R/config_seam_registry.R` içindeki üretim-kritik seam
kimliğini gösterir (guard testleri ve odaklı doğrulama komutları orada da listelidir).

---

## Sohbet / Streaming

- **Seam:** `sohbet_llm_akis`
- **Birincil R dosyaları:** `R/server_send_message.R`, `R/helpers_send_message_*.R`,
  `R/server_handler_true_streaming.R`, `R/helpers_streaming_abort_lifecycle.R`,
  `R/helpers_streaming_poll_lifecycle.R`, `R/helpers_llm_api.R`,
  `R/helpers_llm_sse.R`, `R/helpers_llm_sse_events.R`, `R/helpers_llm_stream_io.R`,
  `R/helpers_llm_worker*.R`, `R/server_llm_response_handlers.R`.
- **UI/server modülleri:** `R/server_outputs_chat.R`, `R/module_chat_actions.R`,
  `R/module_followup_questions.R`, `R/helpers_chat_runtime.R`.
- **JS/CSS:** `www/js/streaming_manager.js`, `www/js/markdown-parser.js`,
  `www/js/streaming_markdown_safety.js`, `www/js/premium_reasoning.js`,
  `www/js/input_handlers.js`.
- **DB/servis:** `MB_Messages`, `MB_Chats`; yerel LLM uç noktası (`LOCAL_LLM_ENDPOINT`).
- **Testler:** `test-send-message-*`, `test-true-streaming-reset-ui-contract.R`,
  `test-streaming-poll-lifecycle-*`, `test-llm-*`, `test-streaming-markdown-safety-contract.R`,
  `test-e2e-streaming-client-request-id-regression.R`,
  `test-server-init-chat-runtime-behavior.R` (`serverInitChatRuntime` fabrikası +
  add_message canlı user-id sözleşmesi), `test-chat-simulate-streaming-behavior.R`
  (`chat_simulate_streaming` TTS/stop KARAR ve erken-çıkış dalları), `test-chat-runtime-*`.
- **Smoke/kanıt:** `www/smoke/ux-smoke.html` (streaming init/delta/stale/finalize),
  VM evidence `browser_ux_smoke`.
- **Bilinen risk / sıradaki hedef:** `serverInitChatRuntime` ve
  `chat_simulate_streaming` (KARAR/erken-çıkış dalları) kapsandı;
  `chat_simulate_streaming` invalidateLater(25) akış döngüsü ile `sendMessageInit`
  ve `call_llm_worker` hâlâ davranışsal test edilmedi (ağır testServer + yoğun stub).

## Dosya Yaşam Döngüsü

- **Seam:** `dosya_yasam_dongusu`
- **Birincil R dosyaları:** `R/config_file_store.R`, `R/config_file_store_index_lock.R`,
  `R/config_file_store_index_mutation.R`, `R/config_file_store_listing_helpers.R`,
  `R/config_file_store_registry.R`, `R/utils_safe_path.R`, `R/utils_upload_validator.R`,
  `R/helpers_files.R`, `R/helpers_mcp_file_resolver.R`.
- **UI/server modülleri:** `R/module_file_manager_ui.R`, `R/module_file_manager.R`,
  `R/module_file_preview.R`, `R/helpers_file_manager_*.R`, `R/server_observers_files.R`.
- **JS/CSS:** `www/js/input_handlers.js` (drag/drop), `www/css/file_manager*.css`.
- **DB/servis:** JSON indeks (`MERGEN_INDEX_PATH`); disk depoları
  (`MERGEN_FILES_ROOT`, `MERGEN_UPLOADS_DIR`, `MCP_FILES_BASE`).
- **Testler:** `test-file-lifecycle-hardening-contract.R`,
  `test-file-resolution-security-contract.R`, `test-resolve-uploaded-file.R`,
  `test-upload-validator*.R`, `test-file-store-*`, `test-file-manager-*`,
  `test-file-pipeline-summarize-behavior.R` (LLM ile içerik dökümü + fallback),
  `test-file-pipeline-upload-batch-behavior.R` (`handle_file_upload_batch`:
  uzantı-reddi + gizli kaydedilmiş-ama-geçersiz yükleme yok + kopyalama-hatası
  temizliği + bildirim yaşam döngüsü),
  `test-adversarial-hostile-input-behavior.R` (traversal/bidi/safe_join).
- **Smoke/kanıt:** `run_fragile_flow_manual_preflight.R`, ux-smoke File Manager
  Türkçe display-name kontrolü.
- **Bilinen risk / sıradaki hedef:** bidi-override reddi + `summarize_file_with_llm`
  + `handle_file_upload_batch` (uzantı-reddi dalı dahil) davranışsal kapsama
  eklendi; kalan açık alan kalmadı (yeni yükleme davranışı eklenince genişletilir).

## DB / Persistence ve Türkçe Kodlama

- **Seam:** `veritabani_kodlama`
- **Birincil R dosyaları:** `R/helpers_db_unicode_escape.R`, `R/helpers_db_encoding.R`,
  `R/helpers_db_connection.R`, `R/helpers_db_user_encoding.R`, `R/helpers_db_validation.R`,
  `R/helpers_chat_message_formatting.R`, `R/helpers_db_chat_readers.R`,
  `R/helpers_db_chat_mutations.R`, `R/helpers_db_feedback.R`, `R/helpers_database.R`,
  `R/utils_text_encoding.R`.
- **DB/servis:** `MB_Users`, `MB_Chats`, `MB_Messages`, `MB_Feedback`, `MB_Usage_Log`;
  SQL Server / ODBC (`DB_DSN`, `DB_CLIENT_ENCODING=WINDOWS-1254`).
- **Testler:** `test-db-normalization-contract.R`, `test-db-refactor-contract.R`,
  `test-db-user-visible-encoding-boundaries.R`, `test-text-encoding-utils.R`,
  `test-db-chat-readers-behavior.R`, `test-db-user-encoding-normalization-behavior.R`.
- **Smoke/kanıt:** `run_vm_encoding_preflight_real.R` (yazma/okuma/rollback),
  VM evidence `db_encoding_preflight`. **Yalnızca Windows VM + SSMS kanıtı geçerlidir.**
- **Bilinen risk / sıradaki hedef:** legacy mojibake satırlar (yalnızca yedek +
  onaylı tek seferlik onarım); yeni yazımlar guard'lıdır.

## SSO / Auth

- **Seam:** `kimlik_sso`
- **Birincil R dosyaları:** `R/config_sso.R`, `R/helpers_sso.R`,
  `R/helpers_sso_signature.R` (JWT imza/JWKS), `R/helpers_logout_url.R`,
  `R/server_init_user_session.R`, `R/helpers_user_session_identity.R`.
- **UI/server modülleri:** `R/module_sso.R`, `www/js/sso_auth.js`, `www/css/sso_auth.css`.
- **DB/servis:** `MB_Users`; Keycloak (`SSO_KEYCLOAK_URL`, JWKS uç noktası).
- **Testler:** `test-sso-jwt-signature.R`, `test-sso-authorization-failclosed.R`,
  `test-sso-signature-parsing.R`, `test-sso-jwt.R`, `test-sso-der-tlv-behavior.R`,
  `test-sso-fetch-jwks-behavior.R`, `test-sso-auth-server-behavior.R` (ssoAuthServer
  fail-closed testServer akışı), `test-e2e-sso-identity-readiness-regression.R`.
- **Smoke/kanıt:** `run_vm_preflight_real.R` (`MERGEN_PREFLIGHT_REQUIRE_SSO=TRUE`).
  **Gerçek Keycloak/SSO yalnızca VM'de kanıtlanır.**
- **Bilinen risk / sıradaki hedef:** `ssoAuthServer` davranışsal testServer kapsaması
  eklendi; gerçek Keycloak token/JWKS akışı yalnızca VM'de kanıtlanır.

## API Anahtarları

- **Seam:** `api_anahtar_model`
- **Birincil R dosyaları:** `R/helpers_api_key_crypto.R`, `R/helpers_api_key_identity.R`,
  `R/helpers_feature_api_key.R`, `R/config_api.R`.
- **UI/server modülleri:** `R/module_api_key.R`, `R/module_api_key_choice_modal.R`,
  `R/helpers_api_key_password_toggle.R`, `www/js/api_key_choice_modal.js`,
  `www/css/api_key_choice_modal.css`.
- **DB/servis:** şifreli kullanıcı anahtar dosyaları (`API_KEYS_DIR`); kurum
  varsayılan anahtarı `MERGEN_DEFAULT_API_KEY` (yalnızca sunucu tarafı).
- **Testler:** `test-config-api-key-crypto-behavior.R`, `test-api-key-choice-modal-contract.R`,
  `test-api-key-choice-modal-builders-behavior.R`, `test-api-key-identity-resolution-behavior.R`,
  `test-api-key-server-behavior.R` (apiKeyServer kaydet/temizle/varsayılan akışı).
- **Smoke/kanıt:** secret-leak contract (`test-secret-leak-contract.R`); anahtarlar
  asla loglanmaz/commit edilmez.
- **Bilinen risk / sıradaki hedef:** `validate_api_key`/`derive_models_url` httr-mock
  uç-nokta doğrulama kapsaması opsiyonel.

## Görsel / Vision

- **Seam:** `api_anahtar_model` (yetenek), `dosya_yasam_dongusu` (galeri)
- **Birincil R dosyaları:** `R/helpers_vision_model_capabilities.R`,
  `R/helpers_vision_context.R`, `R/helpers_image_gallery.R`,
  `R/helpers_markdown_safety.R` (görsel kartı + session-scoped sunum).
- **UI/server modülleri:** `R/module_image_generation.R`, `R/module_image_gallery.R`,
  `R/server_handler_image_generation.R`, `R/server_observers_image_gallery.R`.
- **DB/servis:** `MB_Messages` (görsel kayıtları); görsel üretim uç noktası
  (`IMAGE_GEN_ENDPOINT`), vision modelleri (`MERGEN_VISION_MODELS`).
- **Testler:** `test-vision-context-behavior.R`, `test-vision-model-capabilities-behavior.R`,
  `test-vision-llm-payload-serialization-behavior.R`, `test-image-gallery-helpers-behavior.R`,
  `test-generated-image-card-html-contract.R`, `test-markdown-safety-image-serve-behavior.R`.
- **Smoke/kanıt:** Vision VM-live doğrulandı (kullanıcı onayı, gerçek `MERGEN_VISION_MODELS`).
- **Bilinen risk / sıradaki hedef:** opsiyonel Yapılandırma toggle / `max_bytes`.

## Admin / Sistem Sağlığı

- **Seam:** `destek_yonetici_saglik`
- **Birincil R dosyaları:** `R/helpers_health_checks.R`, `R/helpers_health_runtime_checks.R`,
  `R/helpers_health_formatters.R`, `R/helpers_health_table.R`,
  `R/helpers_release_evidence.R` (release kanıt artifact okuyucu),
  `R/helpers_admin_analytics.R`, `R/helpers_admin_*` aileleri.
- **UI/server modülleri:** `R/module_health*.R` (Sistem Durumu sekmeleri:
  `R/module_health_overview.R`...`R/module_health_diagnostics.R` +
  `R/module_health_release.R` "Doğrulama Kanıtı" sekmesi), `R/module_admin_*.R`,
  `www/js/health_dashboard.js`, `www/css/health_dashboard.css`.
- **DB/servis:** `MB_*` analitik okumaları; DB/LLM/file-store sağlık probe'ları
  (mock'lanır, gerçek internet uç noktası çağrılmaz); release kanıt sekmesi
  yalnızca `artifacts/` ve günlük log dosyalarını okur (DB/ağ çağrısı yok).
- **Testler:** `test-health-check*.R`, `test-health-checks-probes-behavior.R`,
  `test-admin-*-outputs-behavior.R`, `test-release-evidence-behavior.R`,
  `test-release-evidence-error-contexts-behavior.R` (secret-safe hata kategorisi),
  `test-release-evidence-ai-latency-behavior.R` (secret-safe AI çağrı istek-süresi
  özeti), `test-health-release-ui-behavior.R` (UI builder + healthServer yönlendirme).
- **Smoke/kanıt:** VM evidence gate (`run_vm_evidence_gate.R`), seam doctor,
  frontend complexity doctor; `artifacts/vm-evidence/<ts>/evidence.json`.
- **Bilinen risk / sıradaki hedef:** release kanıt okuyucusu Sistem Durumu
  "Doğrulama Kanıtı" sekmesine bağlandı; hata-kategorisi (bağlam) özeti
  (`release_evidence_summarize_error_contexts`) ve AI çağrı istek-süresi (latency)
  özeti (`release_evidence_summarize_ai_call_latency`; `log_ai_call` "duration=<sn>s"
  satırından yalnızca sayısal özet) eklendi — her ikisi secret-safe. Sıradaki:
  post-deploy smoke artifact ailesi (üretici henüz yok). Latency/log özetleri
  yalnızca VM'de gerçek `logs/mergen_*.log` ile canlı doğrulanır.

## Bilge Yolaç / Claude Code

- **Seam:** `bilge_yolac`
- **Birincil R dosyaları:** `R/config_claude_code*.R`, `R/helpers_claude_code_*.R`
  (~30 dosya: güvenlik politikası, yol politikası, runtime workdir, süreç,
  streaming, doküman çıkarma, indirme, çalıştırma yaşam döngüsü).
- **UI/server modülleri:** `R/module_claude_code_ui.R`, `R/module_claude_code.R`,
  `R/module_claude_code_akis.R`, `R/module_claude_code_stream_poll.R`,
  `R/module_claude_code_plugins.R`, `www/js/claude_code*.js`, `www/css/claude_code*.css`.
- **DB/servis:** Claude Code CLI (`CLAUDE_CODE_CLI_PATH`); `bilge_yolac_downloads/`,
  `bilge_yolac_plugins/`.
- **Testler:** `test-claude-code-security-policy-*`, `test-claude-code-prompt-path-policy-behavior.R`,
  `test-claude-code-run-lifecycle-contract.R`, `test-claude-code-stream-html-safety-contract.R`,
  `test-claude-code-workdir-*`, `test-cc-path-policy-collapse-behavior.R`,
  `test-claude-code-parse-stream-event-behavior.R` (stream-json olay ayrıştırma),
  `test-claude-code-connection-behavior.R` (check_claude_code_status processx-mock +
  test_claude_code_connection),
  `test-claude-code-run-streaming-behavior.R` (`run_claude_code_streaming` processx-mock:
  boş komut/CLI yok/workdir-prompt politika reddi/akış başarısı/çıkış kodu/zaman aşımı/
  süreç başlatma hatası/on_chunk),
  `test-claude-code-document-orchestration-behavior.R`
  (`prepare_claude_code_document_context` + `write_claude_code_document_summary_file` +
  `summarize_claude_code_documents_with_local_llm`; çıkarıcı/LLM stub'lı),
  `test-claude-code-stream-poll-binding-behavior.R`
  (`cc_bind_claude_code_stream_polling` testServer: stop gözlemcisi request-id
  kapsamlı finalize + klavye gözlemcisi + poll durduruldu/zaman-aşımı erken dalları),
  `test-claude-code-existing-file-link-security-behavior.R`
  (`format_claude_code_existing_file_link_html`: izinli-kök-dışı reddi/traversal +
  öznitelik escape XSS sınırı).
- **Smoke/kanıt:** Windows VM manuel akış (UNC/SSO/`.cmd`); cloud'da kanıtlanmaz.
- **Bilinen risk / sıradaki hedef:** `parse_stream_event`, bağlantı durumu,
  `run_claude_code_streaming`, doküman özet orkestratörleri ve `cc_bind_claude_code_stream_polling`
  (stop/poll erken dalları) kapsandı; doğrudan indirme bağlantısı artık öznitelik
  bağlamında `htmlEscape(attribute=TRUE)` ile sertleştirildi (öznitelik enjeksiyonu
  savunması). Gerçek CLI/UNC/SSO ve canlı akış tamamlanma dalı yalnızca VM'de kanıtlanır.

## Destek / Geri Bildirim

- **Seam:** `destek_yonetici_saglik`
- **Birincil R dosyaları:** `R/helpers_destek_database.R`,
  `R/helpers_markdown_safety.R` (yardım chatbot bot yanıtı HTML güvenliği),
  `R/config_version_history.R`, `ai_rehber.md`, `version_history.md`.
- **UI/server modülleri:** `R/module_destek.R`, `R/module_destek_yardim.R`,
  `R/module_destek_geri_bildirim.R`, `R/module_destek_hata_bildir.R`,
  `R/module_destek_surum.R`, `R/module_destek_hakkinda.R`,
  `R/module_admin_geri_bildirim.R`, `R/module_admin_hata_analizi.R`.
- **DB/servis:** `MB_Feedback`, hata bildirim tabloları; Service Desk
  (`SERVICE_DESK_API_KEY_URL`).
- **Testler:** `test-destek-database-helpers-behavior.R`,
  `test-destek-db-text-normalization-behavior.R`, `test-admin-geri-bildirim-*`,
  `test-admin-hata-analizi-*`, `test-mailto-encoding*.R`,
  `test-adversarial-hostile-input-behavior.R` (kötü amaçlı geri bildirim/markdown).
- **Smoke/kanıt:** geri bildirim/hata yazımları DB encoding preflight kapsamında.
- **Bilinen risk / sıradaki hedef:** kullanıcı/LLM-kontrollü metin DB sınırlarında
  görünür-vs-teknik normalizasyon ayrımı korunmalı.

---

## Kanıt sınırı hatırlatması

Cloud/Linux koşumları VM/SSO/DB/SQL Server Türkçe kodlama/gerçek tarayıcı/vision
kanıtı üretmez. Bir özelliğin "VM-proven" olduğu yalnızca ilgili VM kapısı
(`run_vm_preflight_real.R`, `run_vm_encoding_preflight_real.R`,
`run_vm_evidence_gate.R`) `passed` raporladığında söylenebilir. SKIP edilen adım
kanıt değildir.

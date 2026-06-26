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
  `R/server_handler_true_streaming.R`, `R/server_handler_streaming_tts.R`
  (`handle_streaming_tts_mode`: TTS açık streaming dalı; gerçek SSE/non-streaming
  ile simetrik handler), `R/helpers_streaming_abort_lifecycle.R`,
  `R/helpers_streaming_poll_lifecycle.R`,
  `R/helpers_llm_true_streaming_worker.R` (`mergen_true_streaming_worker_globals`:
  gerçek SSE işçisine aktarılan worker-export globals listesini kuran saf fabrika;
  handler delege eder), `R/helpers_llm_api.R`,
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
  (`chat_simulate_streaming` TTS/stop KARAR ve erken-çıkış dalları),
  `test-send-message-init-guards-behavior.R` (`sendMessageInit` send_message
  erken-dönüş korumaları: SSO-kimlik user-id'den önce / user-id<=0 / çift-gönderim /
  boş mesaj), `test-llm-worker-call-behavior.R` (`call_llm_worker` araçsız yol +
  HTTP/hata normalizasyon: RATE_LIMIT/AUTH_ERROR/SERVER_ERROR/API_ERROR/
  EMPTY_RESPONSE/UNKNOWN_ERROR/TIMEOUT, reasoning taşıma),
  `test-llm-worker-tool-path-behavior.R` (`call_llm_worker` mcp_excel araç yolu:
  araç-hata erken dönüş / strict_data_only / mcp_excel fallback+Kaynakça /
  ikinci-geçiş ok=FALSE-TRUE-boş orkestrasyon dalları),
  `test-llm-worker-second-pass-{contract,pure-behavior,flow-behavior}.R`
  (`llm_worker_run_mcp_second_pass` SSE + NON-SSE + retry-fallback;
  `llm_worker_call_second_pass_non_streaming` gerçek httr 200/200-dışı),
  `test-server-handler-streaming-tts-contract.R` (`handle_streaming_tts_mode`
  yapısal ayrım + promise zinciri davranışı: başarı/başarısız/durdurulmuş/
  reddedilmiş yollar, deterministik `promises`+`later` ile),
  `test-chat-runtime-*`.
- **Smoke/kanıt:** `www/smoke/ux-smoke.html` (streaming init/delta/stale/finalize),
  VM evidence `browser_ux_smoke`.
- **Bilinen risk / sıradaki hedef:** `serverInitChatRuntime`, `chat_simulate_streaming`
  (KARAR/erken-çıkış dalları), `sendMessageInit` (send_message erken-dönüş korumaları),
  `call_llm_worker` (araçsız + araç-yürütme/ikinci-geçiş dalları) ve ikinci-geçiş iç
  akışı (`llm_worker_run_mcp_second_pass` SSE/NON-SSE/retry-fallback +
  `llm_worker_call_second_pass_non_streaming` httr) davranışsal kapsandı.
  Kalan derin dallar: `chat_simulate_streaming` invalidateLater(25) akış döngüsü,
  `sendMessageInit` mod-dispatch
  sonrası tam akış — hepsi ağır testServer/yoğun stub ister, sıradaki hedef.
  `send_message` üç terminal LLM dalı (gerçek SSE / non-streaming / TTS streaming)
  artık simetrik ctx tabanlı handler'lara yönlendirir: TTS açık streaming dalı
  `R/server_handler_streaming_tts.R`'ye (`handle_streaming_tts_mode`) çıkarıldı;
  `server_send_message.R` 694/14 → 590/9'a indi ve küresel en büyük dosya satırı
  694 → 690'a düştü. Promise zinciri davranışı deterministik test ile korunur.
  Ardından gerçek SSE worker-export globals listesi (reasoning delta / stop-file /
  model request override yardımcıları) saf fabrikaya
  (`mergen_true_streaming_worker_globals`, `R/helpers_llm_true_streaming_worker.R`)
  çıkarıldı; `server_handler_true_streaming.R` onu delege eder ve 681 → 655 satıra
  indi. Liste içeriği byte-birebir korundu (31 isim golden) ve worker-export
  sözleşmesi `test-true-streaming-worker-globals-contract.R` +
  `test-sse-worker-export-contract.R` ile kilitlenir. Küresel en büyük dosya satırı
  681 → 678 (`module_admin_yanit_analizi_outputs.R`) sıkılaştırıldı. Sıradaki
  repo-geneli yakın-bütçe adayları: `R/module_admin_yanit_analizi_outputs.R` (678,
  tek-fonksiyon flat renderer — düşük öncelik), `R/module_file_manager.R` (550/9; delete + toplu-upload runtime split sonrası);
  frontend `www/js/deep_space_intro.js` (820) / `www/js/ai_expert_manager.js` (802/45).

## Dosya Yaşam Döngüsü

- **Seam:** `dosya_yasam_dongusu`
- **Birincil R dosyaları:** `R/config_file_store.R`, `R/config_file_store_index_lock.R`,
  `R/config_file_store_index_mutation.R`, `R/config_file_store_listing_helpers.R`,
  `R/config_file_store_registry.R`, `R/utils_safe_path.R`, `R/utils_upload_validator.R`,
  `R/helpers_files.R`, `R/helpers_mcp_file_resolver.R`.
- **UI/server modülleri:** `R/module_file_manager_ui.R`, `R/module_file_manager.R`,
  `R/module_file_preview.R`, `R/helpers_file_manager_*.R` (özellikle
  `R/helpers_file_manager_delete_runtime.R`: kalıcı dosya silme + indeks temizliği; `R/helpers_file_manager_upload_runtime.R`: toplu upload doğrulama/kalıcılaştırma/indeks yazma),
  `R/server_observers_files.R`.
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
  `test-adversarial-hostile-input-behavior.R` (traversal/bidi/safe_join),
  `test-file-manager-delete-runtime-behavior.R` (doğrudan kalıcı yol silme,
  Türkçe display-name ile indeks temizliği, resolve/fallback sırası),
  `test-file-manager-state-runtime-contract.R` (toplu upload helper ayrımı,
  duplicate/validasyon/kalıcı kopya ve Türkçe dosya adı davranışı).
- **Smoke/kanıt:** `run_fragile_flow_manual_preflight.R`, ux-smoke File Manager
  Türkçe display-name kontrolü.
- **Bilinen risk / sıradaki hedef:** bidi-override reddi + `summarize_file_with_llm`
  + `handle_file_upload_batch` (uzantı-reddi dalı dahil) davranışsal kapsama
  eklendi; `module_file_manager.R` kalıcı silme fiziksel lifecycle dalı
  `helpers_file_manager_delete_runtime.R` içine, toplu upload dosya başı
  doğrulama/kalıcılaştırma dalı `helpers_file_manager_upload_runtime.R` içine
  çıkarıldı ve `module_file_manager.R` 550/9 bütçeye indi. Kalan açık alan
  kalmadı (yeni yükleme/silme davranışı eklenince genişletilir).

## DB / Persistence ve Türkçe Kodlama

- **Seam:** `veritabani_kodlama`
- **Birincil R dosyaları:** `R/helpers_db_unicode_escape.R`, `R/helpers_db_encoding.R`,
  `R/helpers_db_connection.R`, `R/helpers_db_user_encoding.R`, `R/helpers_db_validation.R`,
  `R/helpers_chat_message_formatting.R`, `R/helpers_db_chat_read_queries.R`
  (saf sohbet-okuma SQL üreticileri: önizleme/liste/mesaj/toplu/geçmiş; `with_reasoning`
  + `scoped` dalları, `c.UserID = ?` + `c.IsDeleted = 0` güvenlik filtreleri),
  `R/helpers_db_chat_readers.R` (bağlantı/normalizasyon orkestrasyonu; üreticileri çağırır),
  `R/helpers_db_chat_mutations.R`, `R/helpers_db_feedback.R`, `R/helpers_database.R`,
  `R/utils_text_encoding.R`.
- **DB/servis:** `MB_Users`, `MB_Chats`, `MB_Messages`, `MB_Feedback`, `MB_Usage_Log`;
  SQL Server / ODBC (`DB_DSN`, `DB_CLIENT_ENCODING=WINDOWS-1254`).
- **Testler:** `test-db-normalization-contract.R`, `test-db-refactor-contract.R`,
  `test-db-user-visible-encoding-boundaries.R`, `test-text-encoding-utils.R`,
  `test-db-chat-readers-behavior.R`, `test-db-user-encoding-normalization-behavior.R`,
  `test-db-chat-read-queries-contract.R` (SQL üretici yapısal ayrım + saf üretici
  davranışı: `with_reasoning`/`scoped` dalları, güvenlik filtresi, placeholder),
  `test-db-user-scope-contract.R` (kullanıcı izolasyonu + soft-delete güvenlik
  sözleşmesi, üreticilere yönlendirme).
- **Smoke/kanıt:** `run_vm_encoding_preflight_real.R` (yazma/okuma/rollback),
  VM evidence `db_encoding_preflight`. **Yalnızca Windows VM + SSMS kanıtı geçerlidir.**
- **Bilinen risk / sıradaki hedef:** sohbet-okuma SQL'i saf üretici dosyasına
  (`helpers_db_chat_read_queries.R`) ayrıldı; `helpers_db_chat_readers.R` 680/13 → 522/13
  (SQL byte-birebir korundu, golden + golden-fragment testi). SQL stringleri ASCII'dir
  ve encoding sınırına dokunmaz; `normalize_db_read_visible_frame()` reader'da kaldı.
  legacy mojibake satırlar (yalnızca yedek + onaylı tek seferlik onarım); yeni
  yazımlar guard'lıdır.

## SSO / Auth

- **Seam:** `kimlik_sso`
- **Birincil R dosyaları:** `R/config_sso.R`, `R/helpers_sso.R`,
  `R/helpers_sso_signature.R` (JWT imza/JWKS), `R/helpers_logout_url.R`,
  `R/server_init_user_session.R`, `R/helpers_user_session_identity.R`.
- **UI/server modülleri:** `R/module_sso.R`, `www/js/sso_auth.js`, `www/css/sso_auth.css`.
  Bu seam ayrıca açılış/başlangıç ekranını da kapsar (`module_identity_startup`
  bölümü): `R/module_startup_screen_ui.R` (derin uzay giriş ekranı UI'si +
  `createStartupScreenUI()` + saf `.startup_*()` yapıcıları; üç deneyim-modu kartı
  tek veri-odaklı `.startup_mode_card()` ile üretilir) ve `R/module_startup_screen.R`
  (skip-intro/Three.js/deneyim-modu/persona-müzik gözlemcileri + `apply_experience_mode`).
- **DB/servis:** `MB_Users`; Keycloak (`SSO_KEYCLOAK_URL`, JWKS uç noktası).
- **Testler:** `test-sso-jwt-signature.R`, `test-sso-authorization-failclosed.R`,
  `test-sso-signature-parsing.R`, `test-sso-jwt.R`, `test-sso-der-tlv-behavior.R`,
  `test-sso-fetch-jwks-behavior.R`, `test-sso-auth-server-behavior.R` (ssoAuthServer
  fail-closed testServer akışı), `test-e2e-sso-identity-readiness-regression.R`,
  `test-startup-screen-module-behavior.R` (UI yapısı + `apply_experience_mode` +
  skip-intro gözlemcisi), `test-startup-screen-ui-refactor-contract.R` (UI/sunucu
  ayrım sözleşmesi + üç mod kartının veri-odaklı açık/kapalı özellik davranışı).
- **Smoke/kanıt:** `run_vm_preflight_real.R` (`MERGEN_PREFLIGHT_REQUIRE_SSO=TRUE`).
  **Gerçek Keycloak/SSO yalnızca VM'de kanıtlanır.**
- **Bilinen risk / sıradaki hedef:** `ssoAuthServer` davranışsal testServer kapsaması
  eklendi; gerçek Keycloak token/JWKS akışı yalnızca VM'de kanıtlanır. Açılış ekranı
  UI/sunucu olarak bölündü (`module_startup_screen.R` 740 → 358; UI
  `module_startup_screen_ui.R` 407, üç mod kartı tek veri-odaklı yapıcıda) — at-budget
  pini KALMADI. Derin uzay/karakter video akışı yalnızca VM/manuel tarayıcıda kanıtlanır.

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
  `test-api-key-server-behavior.R` (apiKeyServer kaydet/temizle/varsayılan akışı),
  `test-config-api-validate-api-key-behavior.R` (`validate_api_key` httr-mock uç-nokta
  doğrulama dalları: boş anahtar / `derive_models_url` türetme / model-listesi
  GET 200/401/403/429/500 / sağlık uç noktası / sohbet ping POST 200/401/429/hata /
  endpoint tanımsız), `test-settings-reset-ui-contract.R` (Yapılandırma `Varsayılana Dön`
  görünür input senkronizasyonu: Görünüm, takip sorusu, AI Uzman, ses, görsel, özetleme,
  analiz ve Claude Code zaman aşımı).
- **Smoke/kanıt:** secret-leak contract (`test-secret-leak-contract.R`); anahtarlar
  asla loglanmaz/commit edilmez.
- **Bilinen risk / sıradaki hedef:** `validate_api_key` uç-nokta doğrulama dalları
  (`derive_models_url` dahil) httr-mock ile davranışsal kapsandı. Kalan opsiyonel
  alan yok; gerçek LLM/sağlık uç noktası davranışı yalnızca VM/canlı ortamda
  kanıtlanır.

## Görsel / Vision

- **Seam:** `api_anahtar_model` (yetenek), `dosya_yasam_dongusu` (galeri)
- **Birincil R dosyaları:** `R/helpers_vision_model_capabilities.R`,
  `R/helpers_vision_context.R`, `R/helpers_image_gallery.R`,
  `R/helpers_markdown_safety.R` (görsel kartı + session-scoped sunum).
- **UI/server modülleri:** `R/module_image_generation.R` (IO/üretim/çeviri runtime
  yardımcıları + `generate_image` worker-export global), `R/module_image_generation_ui.R`
  (saf UI/HTML render katmanı: `imageSettingsUI`, `imageChatControlsUI`,
  `render_generated_image_html`, `render_image_from_saved_path`),
  `R/module_image_gallery.R`, `R/server_handler_image_generation.R`,
  `R/server_observers_image_gallery.R`.
- **DB/servis:** `MB_Messages` (görsel kayıtları); görsel üretim uç noktası
  (`IMAGE_GEN_ENDPOINT`), vision modelleri (`MERGEN_VISION_MODELS`).
- **Testler:** `test-vision-context-behavior.R`, `test-vision-model-capabilities-behavior.R`,
  `test-vision-llm-payload-serialization-behavior.R`, `test-image-gallery-helpers-behavior.R`,
  `test-generated-image-card-html-contract.R`, `test-markdown-safety-image-serve-behavior.R`,
  `test-image-generation-module-behavior.R` (çeviri/anahtar/endpoint/web URL/UI/HTML +
  XSS), `test-image-generation-ui-refactor-contract.R` (UI/runtime ayrım sözleşmesi +
  manifest sırası + worker-yolu bağımsızlığı).
- **Smoke/kanıt:** Vision VM-live doğrulandı (kullanıcı onayı, gerçek `MERGEN_VISION_MODELS`).
- **Bilinen risk / sıradaki hedef:** görsel oluşturma UI/HTML render katmanı runtime
  IO/üretim yardımcılarından ayrıldı (`module_image_generation.R` 730/22 → 545/17;
  UI dosyası 194/5) — at-budget pini KALMADI; `generate_image` worker-export globali
  ve iç çeviri/kaydetme çağrıları runtime dosyasında kaldığı için worker globals
  çözümü etkilenmedi. Opsiyonel: Yapılandırma vision toggle / `max_bytes`.

## Medya / Ses / AI Uzman

- **Seam:** `medya_ses`
- **Birincil R dosyaları:** `R/helpers_ai_expert.R` (sistem istemi + bağlam +
  LLM çağrısı + telaffuz düzeltici), `R/helpers_ai_expert_user_data.R`
  (worker-safe DB okuyucuları: `fetch_user_full_name`, `fetch_user_work_context`,
  `fetch_recent_user_prompts`, `fetch_user_last_login`),
  `R/helpers_ai_expert_chunking.R` (TTS metin parçalama),
  `R/helpers_ai_expert_handlers_support.R` (handler saf karar yardımcıları:
  `ai_expert_page_name_tr`, `ai_expert_first_idle_delay_ms`,
  `ai_expert_idle_interval_ms`, `build_ai_expert_idle_user_context`).
- **UI/server modülleri:** `R/module_ai_expert.R`, `R/server_ai_expert_handlers.R`,
  `R/module_tts.R`, `R/module_tts_visualizer.R`, `R/module_stt.R`,
  `R/module_character_video.R`, `R/server_tts_handlers.R`,
  `R/server_music_handlers.R`.
- **JS/CSS:** `www/js/ai_expert_manager.js`, `www/js/tts_manager.js`,
  `www/js/tts_visualizer.js`, `www/js/stt_client.js`, `www/js/music_manager.js`,
  ilgili CSS varlıkları.
- **DB/servis:** `MB_Users` (AI Uzman bağlamı: ad/birim/son giriş), `MB_Messages`
  (son mesajlar); TTS/STT uç noktaları (`LOCAL_TTS_ENDPOINT`,
  `LOCAL_STT_ENDPOINT`), `AI_EXPERT_MODEL`; referans bilgi tabanı `ai_rehber.md`.
- **Testler:** `test-ai-expert-db-fetch-behavior.R`,
  `test-ai-expert-user-data-split-contract.R` (worker-safe DB okuyucu ayrımı +
  kaynak sırası + okuma sınırı sözleşmesi),
  `test-ai-expert-handlers-support-behavior.R` (handler saf karar yardımcıları:
  sayfa adı / sıklık→ms / boşta bağlam davranışı),
  `test-ai-expert-handlers-support-contract.R` (handler saf karar ayrımı +
  kaynak sırası + handler'ın inline mantığı geri almaması),
  `test-ai-expert-prompt-builders-behavior.R`,
  `test-ai-expert-page-guidance-stale-behavior.R`, `test-ai-expert-call-llm-behavior.R`,
  `test-ai-expert-pronunciation-behavior.R`, `test-ai-expert-chunking-behavior.R`,
  `test-e2e-media-audio-state-regression.R`, `test-audio-lifecycle-owner-smoke.R`,
  `test-saved-chat-reload-no-tts-contract.R`.
- **Smoke/kanıt:** ux-smoke ses/TTS/STT duck-restore yaşam döngüsü; kayıtlı sohbet
  reload'da eski TTS otomatik oynatma yok.
- **Bilinen risk / sıradaki hedef:** AI Uzman sunucu işleyicilerinin saf karar
  mantığı (sayfa adı, sıklık→ms, boşta bağlam) `helpers_ai_expert_handlers_support.R`'ye
  ayrıldı; `server_ai_expert_handlers.R` 24-fonksiyon küresel tavanının bir
  altından iki altına indi (726/23 → 652/22). `helpers_ai_expert.R` daha önce
  680/24 → 507/13 indirilmişti. Sıradaki yakın-bütçe adayı `R/module_ai_expert.R`
  (617/22); ancak içeriği büyük ölçüde reaktif/promise tabanlı TTS orkestrasyonudur
  (saf çıkarım sınırlı, ayrı oturum kararı gerektirir). AI Uzman LLM future
  blokları VM-only async yoldur; cloud'da yeniden yapılandırılmamalıdır.

## Admin / Sistem Sağlığı

- **Seam:** `destek_yonetici_saglik`
- **Birincil R dosyaları:** `R/helpers_health_checks.R`, `R/helpers_health_runtime_checks.R`,
  `R/helpers_health_formatters.R`, `R/helpers_health_table.R`,
  `R/helpers_release_evidence.R` (release kanıt artifact okuyucu; VM evidence,
  ai-validation, **post-deploy smoke** ve günlük log sağlık özetleri),
  `R/helpers_admin_analytics.R`, `R/helpers_admin_*` aileleri.
- **Dağıtım sonrası kanıt (script):** `tests/scripts/run_post_deploy_smoke.R`
  (kapı; `artifacts/post-deploy-smoke/<ts>/post-deploy-smoke.json` yazar) +
  `tests/scripts/helpers_post_deploy_smoke.R` (saf değerlendirici
  `mergen_post_deploy_smoke_evaluate` + saf kanıt-kaydı üretici
  `mergen_post_deploy_smoke_artifact_record`).
- **UI/server modülleri:** `R/module_health*.R` (Sistem Durumu sekmeleri:
  `R/module_health_overview.R`...`R/module_health_diagnostics.R` +
  `R/module_health_release.R` "Doğrulama Kanıtı" sekmesi), `R/module_admin_*.R`,
  `www/js/health_dashboard.js`, `www/css/health_dashboard.css`.
- **DB/servis:** `MB_*` analitik okumaları; DB/LLM/file-store sağlık probe'ları
  (mock'lanır, gerçek internet uç noktası çağrılmaz); release kanıt sekmesi
  yalnızca `artifacts/` ve günlük log dosyalarını okur (DB/ağ çağrısı yok).
- **Testler:** `test-health-check*.R`, `test-health-checks-probes-behavior.R`,
  `test-admin-*-outputs-behavior.R`, `test-release-evidence-behavior.R`
  (VM/ai/**post-deploy smoke** okuyucuları + overview), `test-post-deploy-smoke-contract.R`
  (saf değerlendirici + saf kanıt-kaydı üretici + kapı betiği artifact sözleşmesi),
  `test-release-evidence-error-contexts-behavior.R` (secret-safe hata kategorisi),
  `test-release-evidence-ai-latency-behavior.R` (secret-safe AI çağrı istek-süresi
  özeti), `test-health-release-ui-behavior.R` (UI builder + healthServer yönlendirme +
  post-deploy kartı).
- **Smoke/kanıt:** VM evidence gate (`run_vm_evidence_gate.R`), seam doctor,
  frontend complexity doctor; `artifacts/vm-evidence/<ts>/evidence.json`,
  `artifacts/post-deploy-smoke/<ts>/post-deploy-smoke.json`.
- **Bilinen risk / sıradaki hedef:** post-deploy smoke artifact ailesi TAMAMLANDI:
  kapı artık `stop`'tan önce secret-safe `post-deploy-smoke.json` yazar
  (saf `mergen_post_deploy_smoke_artifact_record`; `does_prove`/`does_not_prove`
  dürüstlük alanları), okuyucu `release_evidence_post_deploy_smoke_summary()`
  overview'a bağlandı ve Sistem Durumu > Doğrulama Kanıtı sekmesinde "Dağıtım
  Sonrası Duman Testi" kartı + metrik kutusu olarak görünür. Bu anlık sağlık
  fotoğrafıdır; yük/eşzamanlılık/uzun-süre/VM/SSO/SQL Server kanıtı DEĞİLDİR.
  Gerçek artifact yalnızca uygulama ayaktayken (VM) üretilir; latency/log özetleri
  yine yalnızca VM'de gerçek `logs/mergen_*.log` ile canlı doğrulanır. Sıradaki
  repo-geneli yakın-bütçe adayları bu seam dışında `R/server_handler_true_streaming.R`
  (681, küresel pin — canlı SSE closure'ları nedeniyle yalnızca VM'de kanıtlanabilir,
  riskli) ve `R/module_file_manager.R` (550/9; delete + toplu-upload runtime split sonrası); frontend `www/js/deep_space_intro.js`
  (820) / `www/js/ai_expert_manager.js` (802/45). (`helpers_claude_code_documents.R`
  679 → 407'ye indirildi.)

## Bilge Yolaç / Claude Code

- **Seam:** `bilge_yolac`
- **Birincil R dosyaları:** `R/config_claude_code*.R`, `R/helpers_claude_code_*.R`
  (~31 dosya: güvenlik politikası, yol politikası, runtime workdir, süreç,
  streaming, doküman çıkarma `R/helpers_claude_code_document_extractors.R`,
  doküman BAĞLAM hazırlığı `R/helpers_claude_code_documents.R` (+ paylaşılan UTF-8
  BOM yazıcı), doküman ÖZETLEME orkestrasyonu `R/helpers_claude_code_document_summary.R`,
  indirme, çalıştırma yaşam döngüsü).
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
  `test-claude-code-document-summary-refactor-contract.R` (özetleme orkestrasyonu
  `R/helpers_claude_code_document_summary.R`'ye ayrım sözleşmesi + manifest sırası +
  BOM yazıcının documents.R'de kalması + sıkı bütçe),
  `test-claude-code-stream-poll-binding-behavior.R`
  (`cc_bind_claude_code_stream_polling` testServer: stop gözlemcisi request-id
  kapsamlı finalize + klavye gözlemcisi + poll durduruldu/zaman-aşımı erken dalları),
  `test-claude-code-existing-file-link-security-behavior.R`
  (`format_claude_code_existing_file_link_html`: izinli-kök-dışı reddi/traversal +
  öznitelik escape XSS sınırı),
  `test-claude-code-downloads-security-behavior.R`
  (`resolve_claude_code_generated_path` / `list_claude_code_generated_file_paths` /
  `stage_claude_code_downloads`: üretilen dosya yalnızca izin verilen kökler
  içindeyse indirilebilir kart olur — kök-dışı traversal düşürülür),
  `test-claude-code-downloads-html-behavior.R`
  (`format_claude_code_generated_downloads_html`: kart HTML + öznitelik escape XSS sınırı).
- **Smoke/kanıt:** Windows VM manuel akış (UNC/SSO/`.cmd`); cloud'da kanıtlanmaz.
- **Bilinen risk / sıradaki hedef:** doküman ÖZETLEME orkestrasyonu (detay seviyesi,
  özet mesajları, `summarize_..._with_local_llm`, özet dosya yazımı)
  `R/helpers_claude_code_documents.R`'den `R/helpers_claude_code_document_summary.R`'ye
  ayrıldı; documents.R **679/17 → 407/10**, yeni özet dosyası 281/7. Paylaşılan UTF-8
  BOM yazıcı documents.R'de kaldı (run_lifecycle de `exists()` guard'ıyla kullanır);
  `summarize_...` run_lifecycle worker'ında otomatik globals çözümüyle çalıştığı için
  ayrı dosyaya taşınması worker'ı etkilemedi. `parse_stream_event`, bağlantı durumu,
  `run_claude_code_streaming`, doküman özet orkestratörleri, `cc_bind_claude_code_stream_polling`
  (stop/poll erken dalları) ve üretilen-dosya indirme yolu çözümleme/staging/HTML
  kartı güvenlik sınırı kapsandı; her iki indirme HTML üreticisi de öznitelik
  bağlamında `htmlEscape(attribute=TRUE)` ile sertleştirildi. Gerçek CLI/UNC/SSO ve
  canlı akış tamamlanma dalı yalnızca VM'de kanıtlanır.

## Destek / Geri Bildirim

- **Seam:** `destek_yonetici_saglik`
- **Birincil R dosyaları:** `R/helpers_destek_database.R`,
  `R/helpers_markdown_safety.R` (yardım chatbot bot yanıtı HTML güvenliği),
  `R/config_version_history.R`, `ai_rehber.md`, `version_history.md`.
- **UI/server modülleri:** `R/module_destek.R`, `R/module_destek_yardim.R`,
  `R/module_destek_geri_bildirim.R`, `R/module_destek_hata_bildir.R`,
  `R/module_destek_surum.R`, `R/module_destek_hakkinda.R`,
  `R/module_admin_geri_bildirim.R` (veri/sekme orkestrasyonu) +
  `R/module_admin_geri_bildirim_outputs.R` (`admin_gb_outputs`: 13 highcharter/DT
  renderer) + `R/helpers_admin_geri_bildirim_output_tables.R` (kullanıcı/detay DT
  tablo görünüm verisi), `R/module_admin_hata_analizi.R`, `R/module_admin_yanit_analizi.R`
  (veri/sekme orkestrasyonu) + `R/module_admin_yanit_analizi_outputs.R`
  (`admin_yanit_outputs`: 13 renderer) + `R/helpers_admin_yanit_analizi.R`
  (Yanıt Geri Bildirimi Analizi: veri toplama + etiket sayımı + sekme UI'ları).
- **DB/servis:** `MB_Feedback`, hata bildirim tabloları; Service Desk
  (`SERVICE_DESK_API_KEY_URL`).
- **Testler:** `test-destek-database-helpers-behavior.R`,
  `test-destek-db-text-normalization-behavior.R`, `test-admin-geri-bildirim-*`
  (refactor-contract + query-contract + `test-admin-geri-bildirim-outputs-behavior.R`
  golden grafik sözleşmesi: seri adı/renk/NPS hesabı/treemap/boş-veri +
  `test-admin-geri-bildirim-output-tables-behavior.R` saf tablo veri hazırlama),
  `test-admin-hata-analizi-*`, `test-admin-yanit-tag-counts-behavior.R`,
  `test-admin-yanit-data-presentation-behavior.R` (`admin_yanit_collect_data`
  17-sorgu sözleşmesi + `admin_yanit_overview_ui` beğeni/yorum oranı hesaplaması,
  toplam=0 / boş-çerçeve N/A korumaları, Türkçe metrik kartları),
  `test-admin-yanit-analizi-outputs-behavior.R` (golden grafik sözleşmesi:
  areaspline/tip pastası/model bar/treemap/refresh-bağımlı ısı haritası),
  `test-mailto-encoding*.R`,
  `test-adversarial-hostile-input-behavior.R` (kötü amaçlı geri bildirim/markdown).
- **Frontend varlıkları:** `www/css/destek_page.css` (ana düzen/yardım merkezi/sekme),
  `www/css/destek_forms.css` (form kartları ve seçim alanları),
  `www/css/destek_submission.css` (dosya yükleme/gönderim/durum),
  `www/css/destek_about_responsive.css` (Hakkında + duyarlı tasarım),
  `www/css/destek_yardim_chatbot.css`, `www/js/destek_form.js`,
  `www/js/destek_yardim_chatbot.js`.
- **Smoke/kanıt:** geri bildirim/hata yazımları DB encoding preflight kapsamında.
- **Bilinen risk / sıradaki hedef:** kullanıcı/LLM-kontrollü metin DB sınırlarında
  görünür-vs-teknik normalizasyon ayrımı korunmalı. Destek sayfası CSS'i tek
  1527 satırlık dosyadan dört sıralı manifest parçasına bölündü; destek CSS
  için yakın-bütçe riski çözüldü ve frontend CSS ratchet'i 1150 satıra indirildi. At-budget admin modüllerinin
  (`module_admin_geri_bildirim.R` 760/5, `module_admin_yanit_analizi.R` 753/4)
  inline highcharter/DT renderer'ları `*_outputs()` dosyalarına çıkarıldı:
  modüller 55 ve 106 satıra indi, renderer'lar 728/678 satırlık tek-sorumluluk
  dosyalarında, golden grafik davranış testleriyle kilitli. At-budget pini KALMADI.
  Kalan büyük dosyalar bu seam'de `R/helpers_admin_yanit_analizi.R` (565) ve
  yeni `*_outputs` dosyaları; bunlar tek-fonksiyon flat renderer listeleri olduğu
  için düşük öncelik. Sıradaki repo-geneli yakın-bütçe adayı bu seam dışında
  `module_settings_yapilandirma_ui.R` küçültüldü (758 → 411) ve gelişmiş medya/görsel/analiz kartları
  `module_settings_yapilandirma_advanced_ui.R` (353) dosyasına ayrıldı.
  `server_send_message.R` TTS streaming dalı `R/server_handler_streaming_tts.R`'ye
  çıkarılarak 694/14 → 590/9'a indi. `R/config_ui_assets.R` (690) VERİ/DOĞRULAYICI/
  RENDER olarak üç dosyaya bölündü ve VERİ-odaklı 425/1'e indi. `R/server_runtime_context.R`
  (687) SSO auth-ready / yenilenebilir modül wiring katmanı
  `R/server_runtime_auth_ready.R`'ye ayrılarak 503/13'e indi; küresel en büyük dosya
  satırı 690 → 687 → 681 oldu. `R/helpers_claude_code_documents.R` (679) doküman
  özetleme orkestrasyonu `R/helpers_claude_code_document_summary.R`'ye ayrılarak
  407'ye indi. Sıradaki repo-geneli yakın-bütçe adayları artık
  `R/helpers_claude_code_process.R` (665/20; yalnızca discovery gerçek risk gösterirse) ve frontend yoğunluk adaylarıdır; `R/module_admin_yanit_analizi_outputs.R` tek-fonksiyon flat renderer olarak düşük öncelik kalır.

## Frontend Varlık ve Yönetişim

- **Seam:** `frontend_varlik`
- **Birincil R dosyaları:** `R/config_ui_assets.R` (SAF VERİ: CSS/JS varlık
  manifesti + ertelenmiş grup listesi + render planı + JS/CSS sıra kuralları +
  `ui_asset_flatten_groups` — yükleme sırasının TEK sahibi),
  `R/config_ui_asset_validators.R` (SAF çözümleyici/doğrulayıcı API'si:
  `ui_asset_all_css/js`, `ui_asset_deferred_js_paths`, `ui_asset_validate*`,
  `ui_asset_render_plan_*`, `ui_asset_public_root` — veriyi çağrı anında çözer),
  `R/config_ui_asset_tags.R` (htmltools etiket render katmanı: `ui_asset_tags`,
  `ui_asset_css_tags`, `ui_asset_js_tags`, `ui_asset_css_tag`,
  `ui_asset_script_tag`), `R/config_ui_asset_zones.R` (SAF VERİ: 23 frontend
  bölgesi + manifest dışı sahiplik haritası), `R/config_ui_asset_zone_validators.R`
  (bölge çözümleme + bölümleme/partition doğrulama API'si:
  `ui_asset_zone_ids/get/css_paths/js_paths`, `ui_asset_zone_owner_seams`,
  `ui_asset_zones_for_seam`, `ui_asset_zones_validate`,
  `ui_asset_frontend_ownership_gaps` — boot'ta çağrılmaz, yalnızca seam doctor +
  sözleşme testleri kullanır).
- **JS/CSS:** `www/css/*`, `www/js/*` (her varlık tam olarak bir bölgeye atanır;
  manifest dışı/smoke varlıklar gerekçeli sahiplenilir).
- **Testler:** `test-ui-asset-manifest-contract.R`,
  `test-ui-asset-config-split-contract.R` (varlık manifesti VERİ/DOĞRULAYICI/RENDER
  ayrımı + bölme sonrası sıra/etiket doğrulaması),
  `test-config-ui-assets-helpers-behavior.R`, `test-ui-asset-tag-builders-behavior.R`,
  `test-ui-asset-zones-contract.R`, `test-ui-asset-zone-validators-split-contract.R`
  (VERİ/DOĞRULAYICI ayrımı + bölümleme korunumu),
  `test-frontend-maintainability-ratchet.R`, `test-frontend-selector-contract.R`.
- **Smoke/kanıt:** seam doctor (`tests/scripts/seam_doctor.R`), frontend complexity
  doctor, `www/smoke/ux-smoke.html`.
- **Bilinen risk / sıradaki hedef:** varlık manifesti VERİ/DOĞRULAYICI/RENDER
  olarak üç dosyaya bölündü (`config_ui_asset_zones.R` deseni):
  `config_ui_assets.R` 690/17 → 425/1 (SADECE VERİ; sıranın TEK sahibi),
  çözümleyici/doğrulayıcılar `config_ui_asset_validators.R`'de (253/11), htmltools
  etiket render katmanı `config_ui_asset_tags.R`'de (59/5). Çıktı byte-birebir
  korundu (golden + HEAD karşılaştırması, tag md5 `11c977dd…`). Ardından
  `R/server_runtime_context.R` (687) SSO auth-ready / yenilenebilir modül wiring
  katmanı `R/server_runtime_auth_ready.R`'ye ayrılarak 503/13'e indi; küresel en
  büyük dosya satırı 690 → 687 → 681 olarak sıkılaştırıldı. Bölge VERİSİ/DOĞRULAYICI
  ayrımı da korunur: `config_ui_asset_zones.R` 502/0 (SADECE veri), doğrulayıcı API
  `config_ui_asset_zone_validators.R`'de (312/10). Sıradaki repo-geneli yakın-bütçe
  adayları artık daha çok frontend yoğunluk dosyalarıdır; R tarafında `R/helpers_claude_code_process.R`
  (665/20) yalnızca taze raporda gerçek riskse seçilmeli. Frontend tarafında en yoğun adaylar
  `www/js/deep_space_intro.js` (820/32) ve `www/js/ai_expert_manager.js`
  (802/45/12 event/8 Shiny handler).

---

## Kanıt sınırı hatırlatması

Cloud/Linux koşumları VM/SSO/DB/SQL Server Türkçe kodlama/gerçek tarayıcı/vision
kanıtı üretmez. Bir özelliğin "VM-proven" olduğu yalnızca ilgili VM kapısı
(`run_vm_preflight_real.R`, `run_vm_encoding_preflight_real.R`,
`run_vm_evidence_gate.R`) `passed` raporladığında söylenebilir. SKIP edilen adım
kanıt değildir.

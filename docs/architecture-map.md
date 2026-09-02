# MERGEN Bilge Mimari Haritası

Bu belge, MERGEN Bilge koduna dokunmadan önce yön bulmak isteyen geliştiriciler, bakımcılar, kodlama ajanları ve üretim operatörleri için hazırlanmıştır. Amaç, uygulamanın gerçek depo yapısını ve korunması gereken sınırları hızlıca göstermektir; sıkı çalışma kuralları için İngilizce [`../CLAUDE.md`](../CLAUDE.md) otoritatif kalır.

## Üst Seviye Bakış

MERGEN Bilge, R/Shiny tabanlı bir kurumsal yapay zekâ uygulamasıdır. Kök girişleri `app.R`, `global.R`, `ui.R` ve `server.R` dosyalarıdır. `global.R`, kaynak manifesti üzerinden R dosyalarını sıralı yükler; `ui.R` görsel kabuğu kurar; `server.R` server modüllerini ve observer katmanını bağlar.

```text
Kullanıcı / Tarayıcı
        |
        v
R/Shiny uygulama kabuğu: app.R -> global.R -> ui.R + server.R
        |
        +-- UI modülleri, CSS/JS varlıkları, medya ve smoke seam'leri
        +-- Server modülleri, session runtime context ve observer katmanı
        +-- LLM/model entegrasyonu, tool model çözümleme ve streaming
        +-- Dosya yükleme, dosya deposu, önizleme ve analiz yardımcıları
        +-- DB/persistence, SSO/JWT, API anahtarı ve kullanıcı kimliği sınırları
        +-- TTS/STT, AI Uzman, Destek, Yönetici/Sistem Durumu ve Bilge Yolaç
```

## Ana Runtime Katmanları

| Katman | Gerçek depo kanıtı | Ne işe yarar? |
|---|---|---|
| R/Shiny uygulama kabuğu | `app.R`, `global.R`, `ui.R`, `server.R`, `run_mergen_prod.R`, `run_mergen_prod.bat` | Uygulama başlangıcı, kaynak yükleme, UI/server bağlama ve üretim başlangıcı. |
| Kaynak manifesti | `R/config_source_manifest.R` | R kaynaklarının açık ve test edilebilir sırayla yüklenmesi. Load-order değişiklikleri risklidir. |
| UI asset manifesti | `R/config_ui_assets.R` | CSS/JS varlıklarının sırası; encoding, streaming ve smoke sınırları için kritiktir. |
| Yapılandırma | `.Renviron.example`, `R/config_api.R`, `R/config_packages.R`, `R/config_sso.R`, `R/config_file_store.R`, `R/config_claude_code.R` | Ortam değişkenleri, modeller, paket manifesti, SSO, dosya deposu ve Bilge Yolaç ayarları. |
| UI modülleri | `R/module_*.R`, `www/css/`, `www/js/`, `www/assets/`, `www/characters/`, `www/videos/` | Sayfa ve bileşen deneyimi, tema, medya, tarayıcı davranışları. |
| Server logic | `server.R`, `R/helpers_*runtime*.R`, `R/module_*` | Session state, observer katmanı, modül server bağlama ve runtime context. |
| LLM/model entegrasyonu | `R/helpers_llm_*.R`, `R/helpers_api_model_config.R`, `R/helpers_api_model_tool_runtime.R`, `R/helpers_send_message_*.R`, `R/helpers_streaming_*.R` | Chat/completion istekleri, SSE/streaming, tool sonuçları, model çözümleme ve worker payload sınırı. True streaming abort kararları `R/helpers_streaming_abort_lifecycle.R`, yoklama döngüsü satır sınıflandırma / reasoning geri kazanım kararları `R/helpers_streaming_poll_lifecycle.R` içindedir; `R/server_handler_true_streaming.R` bu saf kararları yalnızca orkestre eder. `send_message` üç terminal LLM dalını simetrik ctx tabanlı handler'lara yönlendirir: gerçek SSE (`handle_true_streaming_mode`), non-streaming ve TTS açık streaming (`handle_streaming_tts_mode`, `R/server_handler_streaming_tts.R`). |
| Model yeteneği ve görsel anlama | `R/helpers_vision_model_capabilities.R`, `R/helpers_deep_thinking_model_capabilities.R`, `R/helpers_vision_context.R`, `R/config_api.R`, `.Renviron.example` | Image Input destekli modellerin çözülmesi, Derin Düşünme modellerinin yetenek/endpoint kaydı (tek sahip saf helper, `config_api.R` guard'lı çağırır) ve görsel bağlamın LLM isteğine eklenmesi. |
| Görsel üretimi | `R/module_image_generation.R`, `R/module_image_gallery.R`, `R/helpers_image_gallery.R`, `.Renviron.example` | Görsel üretimi ve galeri akışları. |
| Dosya yönetimi | `R/helpers_file_*`, `R/helpers_files*.R`, `R/module_file_manager*.R`, `R/module_file_preview.R` | Upload, indeks, kullanıcı izolasyonu, önizleme, dosya deposu ve analiz hazırlığı. Kullanıcıya görünen dosya adı sınırı `R/helpers_file_manager_table.R::fm_normalize_uploaded_file_info()` üzerinden korunur; storage-prefix temizliği ve Türkçe/UTF-8 onarımı kanonik dosya deposu helper'ına delege edilir. Kalıcı dosya silme fiziksel yol/resolve/fallback/indeks temizliği `R/helpers_file_manager_delete_runtime.R::fm_delete_persisted_file_artifacts()` sınırındadır; toplu upload dosya başı doğrulama/kalıcılaştırma/indeks yazma akışı `R/helpers_file_manager_upload_runtime.R::fm_process_bulk_upload_batch()` sınırındadır. |
| DB/persistence | `R/helpers_db_unicode_escape.R`, `R/helpers_db_encoding.R`, `R/helpers_db_connection.R`, `R/helpers_db_pool.R` (işlem-güvenli bağlantı havuzu), `R/helpers_db_chat_read_queries.R` (saf sohbet-okuma SQL üreticileri), `R/helpers_db_chat_readers.R`, `R/helpers_db_chat_mutations.R`, `R/helpers_database.R`, [`database-schema.md`](database-schema.md) | DB bağlantısı, encoding guard'ları, chat/feedback okuma-yazma, tablo yapısı ve kalıcılık. **Bağlantı havuzu** `helpers_db_pool.R`: opt-in (`MERGEN_DB_POOL_ENABLED`, varsayılan KAPALI), `init_db_pool_once`/`close_db_pool_once`, salt-okunur `with_db_connection`, işlem-güvenli `with_db_transaction` (gerçek `poolCheckout`; bağlantı iade edilmeden önce rollback). Okuma yolları `get_connection()` üzerinden otomatik havuzlanır; `save_message_to_db()` işlem-güvenli checkout kullanır. Havuz `app.R` `onStart`'ta başlatılır, `onStop`'ta kapatılır. Sohbet-okuma SQL'i (önizleme/liste/mesaj/toplu/geçmiş) `helpers_db_chat_read_queries.R` üreticilerinde; reader dosyası bağlantı/normalizasyon orkestrasyonunu yapar ve üreticileri çağırır. |
| SSO/auth | `R/config_sso.R`, `R/helpers_sso.R`, `R/helpers_sso_signature.R`, `R/helpers_logout_url.R` | Yerel geliştirme ve Keycloak/JWT sınırı. |
| API anahtarı | `R/helpers_api_key_crypto.R`, `R/helpers_api_key_identity.R`, `R/helpers_feature_api_key.R`, `R/helpers_api_key_password_toggle.R`, `www/js/api_key_choice_modal.js` | Kişisel anahtar şifreli saklama katmanı (`config_api.R`'den taşınan save/load/verify + NUL-tuz guard'ı), kişisel/kurumsal anahtar çözümleme, modal UX ve secret safety. |
| TTS/STT/audio | `R/helpers_ai_expert.R`, `R/helpers_ai_expert_user_data.R`, `R/helpers_ai_expert_chunking.R`, `R/helpers_ai_expert_handlers_support.R`, ilgili UI/JS/CSS varlıkları ve `.Renviron.example` | AI Uzman konuşması, TTS/STT ve ses yaşam döngüsü. `helpers_ai_expert_user_data.R` worker-safe DB okuyucularını (ad/birim/son mesaj/son giriş), `helpers_ai_expert_handlers_support.R` ise handler saf karar yardımcılarını (sayfa adı, sıklık→ms, boşta bağlam metni) ayrı tutar. |
| Destek/Yardım/Yenilikler | `R/helpers_destek_database.R`, `version_history.md`, destek modülleri ve CSS/JS varlıkları | Yardım Merkezi, Geri Bildirim & Hata, Yenilikler ve Hakkında alanları. |
| Admin/Sistem Durumu | `R/helpers_admin_analytics.R`, `R/helpers_health_*.R`, admin modülleri | Yönetim panelleri, hata/feedback analizleri, sağlık kontrolleri. |
| Bilge Yolaç / Claude Code | `R/helpers_claude_code_*.R`, `R/config_claude_code*.R`, `bilge_yolac_plugins/` | Web-wrapped Claude Code oturumu, güvenli çalışma dizini, streaming, download ve eklenti sistemi. Çalıştırma hattı BLOKLAMAZ: sınırlı dizin tarayıcısı (`helpers_claude_code_bounded_scan.R`), izole `input`/`output`/`metadata`/`document_support` runtime düzeni (`helpers_claude_code_runtime_prepare.R`), yalnızca-değişen çıktı aktarımı (`helpers_claude_code_output_sync.R`), arka plan hazırlık görevi (`helpers_claude_code_run_prepare_task.R`) ve ana süreç gönderim/sonlandırma katmanı (`helpers_claude_code_run_dispatch.R`, `helpers_claude_code_run_completion.R`). |
| Bilge Savunması (oyun) | `R/config_bilge_savunmasi.R`, `R/helpers_bilge_savunmasi_validation.R`, `R/helpers_db_bilge_savunmasi_*.R`, `R/module_bilge_savunmasi*.R`, `www/js/bilge_savunmasi_*.js` | Adanmış kule savunma sayfası: sunucu-otoriter doğrulama/puanlama, MB_Game_* kalıcılığı, eşzamansız haftalık meydan okuma/plan/topluluk. |

## Kaynak Manifesti ve Yükleme Sırası

`R/config_source_manifest.R`, `global.R` tarafından kullanılan sıralı kaynak listesini tanımlar. Dosya; temel altyapı, yapılandırma, DB/SQL, core helper, LLM, modül ve server handler katmanlarını açık listeler.

### Özellik bölümleri (onboarding haritası)

255+ R dosyası içinde yön bulmayı kolaylaştırmak için manifest, özellik/katman ailelerine göre adlandırılmış bölümlerden oluşan tek bir sıralı liste (`source_manifest_sections`) olarak düzenlenmiştir. "X özelliği hangi dosyalarda?" sorusunun ilk cevabı bu bölümlerdir. Üç kanonik nesne (`source_manifest_group_1_paths`, `source_manifest_after_future_paths`, `source_manifest_runtime_paths`) bu bölümlerden türetilir ve yükleme sırası bölümlerin sırayla birleştirilmesiyle birebir korunur.

Öne çıkan bölümler ve karşılık geldikleri özellikler:

| Bölüm anahtarı | Özellik / katman | Tipik giriş noktası |
|---|---|---|
| `foundation` / `post_future_utils` | Temel altyapı (encoding, log, yol, upload doğrulama, indeks) | `R/utils_*.R` |
| `config_app_core` / `config_api_model_keys` | SSO/dosya deposu/karakter yapılandırması, model ve API anahtarı çözümleme | `R/config_*.R`, `R/helpers_api_*` |
| `database` / `sql_library` | DB encoding/bağlantı/okuma-yazma ve SQL kütüphanesi | `R/helpers_db_*`, `R/helpers_database.R` |
| `mcp_tools` / `chartlab_helpers` | MCP araç zinciri ve ChartLab | `R/helpers_mcp_*`, `R/helpers_chartlab*.R` |
| `files_preview_pipeline` / `file_manager_helpers` | Dosya yaşam döngüsü, önizleme, bloklamayan dosya alım hattı, Dosya Yönetimi yardımcıları | `R/helpers_file*`, `R/module_file_manager*.R`; alım hattı `helpers_files.R` SONRASINDA saf plan → worker → kuyruk → ana süreç runtime sırasıyla yüklenir; upload runtime helper storage sonrası/delete runtime öncesi, delete runtime helper ise state runtime öncesi source edilir. |
| `chat_send_message_runtime` / `llm_pipeline` | Sohbet/gönderme akışı ve LLM/SSE/worker hattı | `R/helpers_send_message_*`, `R/helpers_streaming_*`, `R/helpers_llm_*` |
| `claude_code_helpers` / `module_claude_code` | Bilge Yolaç yardımcıları ve modülleri; bloklamayan çalıştırma hattı sırayla yüklenir: sınırlı tarayıcı → runtime hazırlık → çıktı senkron planı → runtime workdir → workdir scan → dosya kararlılık → doküman zinciri → arka plan hazırlık görevi → run lifecycle → dispatch → completion | `R/helpers_claude_code_*`, `R/module_claude_code*.R` |
| `ortak_oturumlar` | Ortak Oturumlar (işbirlikçi çalışma odaları): saf yetki/e-posta yardımcıları, `MB_OrtakOturumlar` DB katmanı ve oda/davet/hub modülleri | `R/helpers_ortak_oturum_*`, `R/module_ortak_*` |
| `module_*` aileleri | Sohbet, dosya/medya, ayarlar, AI/ses, kimlik/başlangıç, destek, admin, sağlık UI modülleri | `R/module_*.R` |
| `server_init_runtime` / `server_core_outputs_welcome` / `server_observers` / `server_handlers_send_message` | Server init/runtime context, observer katmanı ve handler/gönderme hattı | `R/server_*.R` |

Yapılandırma sayfasında gelişmiş medya/görsel/analiz kartları `R/module_settings_yapilandirma_advanced_ui.R` içinde, ana kompozitör ve temel kartlar `R/module_settings_yapilandirma_ui.R` içinde, server/runtime ise `R/module_settings_yapilandirma.R` içinde tutulur; manifest sırası advanced UI → UI → server şeklindedir.

Yeni bir runtime dosyası eklerken doğru bölüme, doğru sırada eklenmelidir. Bölüm sırası ve sınır dosyaları `tests/testthat/test-source-manifest-sections-contract.R` tarafından dondurulur; kritik ikili yükleme sırası kuralları ise `R/bootstrap_source_manifest.R` içindeki `source_manifest_required_order` ile doğrulanır.

Özellikle şu sıralar korunmalıdır:

- `R/utils_text_encoding.R`, logging/DB/metin tüketicilerinden önce yüklenir.
- `R/helpers_mailto_encoding.R`, `R/utils_text_encoding.R` sonrasında erken yüklenir.
- DB tarafında Unicode escape, encoding, connection ve üst seviye DB helper sırası korunur.
- `R/helpers_vision_model_capabilities.R`, model/API yapılandırması bağlamında yüklenir.
- Bilge Yolaç helper zinciri ve LLM worker/streaming helper zinciri birlikte değerlendirilmelidir.

`R/config_ui_assets.R`, frontend asset sırasının tek görünür manifestidir. Encoding JS, Shiny message handler'ları ve Claude Code streaming dosyalarının sırası tarayıcı tarafı regresyonları önlemek için kritiktir. Uzun `page` CSS ve `deferred` JS manifestleri artık `ui_asset_flatten_groups(list(...))` içindeki named feature/layer bölümleriyle okunur; bu bölümler yalnızca onboarding amaçlıdır ve üretilen final CSS/JS vektör sırası `tests/testthat/test-ui-asset-manifest-contract.R` içindeki birebir sıra sözleşmesiyle korunur. Varlık manifesti, bölge haritası (`config_ui_asset_zones.R`) deseniyle aynı şekilde VERİ / DOĞRULAYICI / RENDER olarak üç dosyaya bölünmüştür: `R/config_ui_assets.R` SADECE VERİ (gruplar, ertelenmiş grup listesi, render planı, JS/CSS sıra kuralları, `ui_asset_flatten_groups`) ve yükleme sırasının TEK sahibidir; `R/config_ui_asset_validators.R` saf çözümleyici/doğrulayıcı API'sini (`ui_asset_all_css/js`, sıra/render planı doğrulaması) taşır; `R/config_ui_asset_tags.R` htmltools etiket render katmanını (`ui_asset_tags` vb.) taşır. Üçü manifestte VERİ → DOĞRULAYICI → RENDER sırasında yüklenir ve doğrulayıcı/etiket fonksiyonları veriyi çağrı anında çözer; bölme `tests/testthat/test-ui-asset-config-split-contract.R` ile dondurulur. Destek yüzeyi CSS'i de aynı sıraya duyarlı manifest disiplinindedir: `destek_page.css` → `destek_forms.css` → `destek_submission.css` → `destek_about_responsive.css` → `destek_yardim_chatbot.css`. AI Uzman frontend sınırında durum makinesi `js/ai_expert_manager.js` içinde, Shiny handler bağlayıcıları ise hemen ardından yüklenen `js/ai_expert_handlers.js` içinde kalır; bu sıra `test-ui-asset-manifest-contract.R` ve `test-ai-expert-frontend-split-contract.R` ile korunur. Deep Space sınırında lifecycle helper `js/deep_space_intro_lifecycle.js`, solar kurulumdan sonra ve sahne modülünden hemen önce yüklenir; timeout/rAF/auto-init cleanup delegasyonu `test-deep-space-frontend-lifecycle-contract.R` ile korunur.

### Açık tema mimarisi (tek-tanım sözleşmesi)

Açık tema, `theme_tokens.css` token tabanı (koyu varsayılan + `html[data-theme="light"]` override blokları) üzerine kurulu YEDİ alan dosyasından oluşur: `theme_light_core.css` (uygulama kabuğu), `theme_light_welcome.css`, `theme_light_chat.css`, `theme_light_modals.css`, `theme_light_bilge_yolac.css`, `theme_light_personalization.css` ve `theme_light_pages.css` (Dosya Yönetimi, geçmiş/galeri, Destek, Yönetici, Sistem Durumu). Zincirde her seçici yalnızca BİR kez tanımlanır; eski 13 dosyalık override/patch zinciri (extras/refinements/polish/overhaul/overhaul_phase2/user_polish/user_polish_v2) kaskad sonucu bire bir korunarak bu alan dosyalarına konsolide edilmiş ve eski adlar tombstone'lanmıştır. Yeni açık tema kuralı eklerken ilgili alan dosyasındaki mevcut seçici genişletilir; ikinci bir override katmanı eklenmez. Bileşen CSS dosyaları kendi sahip oldukları seçiciler için `html[data-theme="light"]` incelmeleri taşıyabilir (tema zincirinden sonra yüklendikleri için son söz onlarındır); bu desen `tests/testthat/test-frontend-maintainability-ratchet.R` içindeki light-tekrar bütçesiyle sınırlanır. Koruyan sözleşme: `tests/testthat/test-theme-light-modular-contract.R` (dondurulmuş dosya kümesi, tombstone, tek-tanım, kapsam disiplini, gerçek-seçici çapaları).

## Seam Kayıt Defteri ve Frontend Bölge Sahipliği (Yönetişim Katmanı)

Üretim-kritik sınırların sahipliği artık iki makine tarafından okunabilir haritada toplanır. Bu katman çalışma zamanı davranışını değiştirmez; saf veri + saf doğrulama yardımcılarından oluşur ve sözleşme testleriyle gerçekliğe karşı doğrulanır.

| Yönetişim dosyası | İçerik | Koruyan test |
|---|---|---|
| `R/config_seam_registry.R` | 12 üretim-kritik seam: her seam'in sahiplendiği manifest bölümleri, manifest dışı runtime dosyaları, guard testleri, odaklı doğrulama komutları ve ilişkili seam'ler. | `tests/testthat/test-seam-registry-contract.R` |
| `R/config_ui_asset_zones.R` | SAF VERİ: 23 frontend bölgesi (manifestteki HER CSS/JS varlığının tam olarak BİR bölgeye atanması, bölge başına sahip seam + guard testleri) + manifest dışı (inline/smoke) varlıkların gerekçeli sahiplik kaydı. | `tests/testthat/test-ui-asset-zones-contract.R` |
| `R/config_ui_asset_zone_validators.R` | Bölge çözümleme + bölümleme (partition) doğrulama API'si (saf fonksiyonlar): `ui_asset_zone_ids/get/css_paths/js_paths`, `ui_asset_zone_owner_seams`, `ui_asset_zones_for_seam`, `ui_asset_zones_validate`, `ui_asset_frontend_ownership_gaps`. Veriden hemen sonra yüklenir; boot'ta çağrılmaz (yalnızca seam doctor + sözleşme testleri kullanır). | `tests/testthat/test-ui-asset-zone-validators-split-contract.R` |
| `tests/scripts/seam_doctor.R` (`tools/seam_doctor.sh`) | Seam/bölge/manifest tutarlılığını raporlayan hafif operasyonel araç; `artifacts/seam-doctor/` altına secret-safe JSON artifact yazar. Ağır doğrulama çalıştırmaz. | `tests/testthat/test-seam-doctor-contract.R` |
| `tests/scripts/run_vm_evidence_gate.R` (`tools/vm_evidence_gate.sh`) | TEK tekrarlanabilir preflight kanıt kapısı: mevcut doğrulama betiklerini temiz çocuk R oturumlarında sıralı adımlar olarak koşar; `artifacts/vm-evidence/<timestamp>/evidence.json` altına secret-safe kanıt artifact'ı yazar. En son 2026-08-18 Windows VM yeniden doğrulamasında 13/13 adım geçti (`full_testthat`, `browser_ux_smoke`, `vm_preflight_real`, `db_encoding_preflight` dahil; artifact `artifacts/vm-evidence/20260818-163559/evidence.json`). Profiller: `vm` (VM-yalnız kapılar zorunlu) / `cloud` (gerekçeli SKIP). | `tests/testthat/test-vm-evidence-gate-contract.R` |
| `tests/scripts/run_post_deploy_smoke.R` (saf değerlendirici `tests/scripts/helpers_post_deploy_smoke.R`) | Dağıtım sonrası duman testi kapısı: uygulamayı güvenli boot modunda yükler, sağlık kontrollerini toplar, genel durumu (`pass`/`degraded`/`fail`) hesaplar ve kritik bozulmada stop eder. `stop`'tan ÖNCE secret-safe `artifacts/post-deploy-smoke/<timestamp>/post-deploy-smoke.json` yazar (yalnızca kontrol kimlikleri + durum sayaçları + `does_prove`/`does_not_prove`; ham log/ortam değeri yok). Saf okuyucu `release_evidence_post_deploy_smoke_summary()` artifact'ı Sistem Durumu > Doğrulama Kanıtı sekmesine taşır. Anlık sağlık fotoğrafıdır; yük/stabilite/VM/SSO/SQL Server Türkçe kodlama kanıtı DEĞİLDİR. | `tests/testthat/test-post-deploy-smoke-contract.R`, `tests/testthat/test-release-evidence-behavior.R` |

Seam listesi (id -> sahiplenilen manifest bölümleri):

| Seam | Manifest bölümleri | Örnek guard testleri |
|---|---|---|
| `temel_altyapi` | `foundation`, `post_future_utils`, `config_app_core`, `architecture_governance` (+ `app.R`, `global.R`, bootstrap/manifest dosyaları) | source-manifest + production contracts |
| `veritabani_kodlama` | `database`, `sql_library` | DB normalization/refactor, text-encoding |
| `kimlik_sso` | `sso_identity_helpers`, `module_identity_startup` | JWT imza, fail-closed yetkilendirme, SSO readiness |
| `api_anahtar_model` | `config_api_model_keys`, `module_settings_api_key` | config-api split, anahtar kripto, anahtar modalı |
| `sohbet_llm_akis` | `language_messaging`, `chat_send_message_runtime`, `summarization_followup`, `llm_pipeline`, `module_chat`, `ortak_oturumlar`, `server_handlers_send_message` | istek yaşam döngüsü, stream I/O, markdown güvenliği, ortak oturum LLM yolu |
| `mcp_analiz` | `mcp_tools`, `chartlab_helpers`, `analysis_helpers`, `module_analysis` | MCP excel/bootstrap, PK analiz RLS |
| `dosya_yasam_dongusu` | `files_preview_pipeline`, `file_manager_helpers`, `module_files_media` | dosya lifecycle, çözümleme güvenliği, upload doğrulama |
| `medya_ses` | `ai_expert_helpers`, `module_ai_audio` | ses yaşam döngüsü, TTS autoplay koruması |
| `bilge_yolac` | `config_claude_code`, `claude_code_helpers`, `module_claude_code`, `bilge_savunmasi` | güvenlik politikası, run lifecycle, stream HTML güvenliği, oyun yaşam döngüsü/DB davranışı |
| `destek_yonetici_saglik` | `support_admin_health_helpers`, `module_support`, `module_admin`, `module_health_chartlab` | admin refactor + tablo helper sözleşmeleri, sağlık panosu |
| `shiny_calisma_zamani` | `server_init_runtime`, `server_core_outputs_welcome`, `server_observers` (+ `server.R`, `ui.R`) | runtime context, core interaction/observer, module wiring |
| `frontend_varlik` | `config_ui_assets` | UI asset manifest, bölge sözleşmesi, frontend ratchet |

Disiplin kuralları:

- Her source-manifest bölümü tam olarak bir seam'e aittir; sahipsiz bölüm veya çift sahiplik sözleşme testini düşürür.
- `R/` altında manifest + seam allowlist dışında sahipsiz runtime R dosyası kalamaz.
- `www/css/` ve `www/js/` altındaki her fiziksel dosya ya manifest üzerinden bir bölgeye ya da `ui_asset_unmanifested_ownership` kaydına (gerekçesiyle) bağlanır.
- `ui_asset_unmanifested_ownership` içinde `optional_in_checkout = TRUE` taşıyan girdiler (örn. `js/fontfaceobserver.js`, `js/highlight.min.js`) yalnızca on-prem VM çalışma kopyasında fiziksel olarak bulunur (renv.lock provenance deseni); cloud/CI checkout'unda yoklukları yapısal sorun değildir, VM'de mevcutken sahiplik boşluğu raporlanmaz.
- Yükleme sırasının tek sahibi `R/config_ui_assets.R` kalır; bölge haritası sırayı DEĞİL sahipliği bildirir.
- Tema override kaskadı (tokens -> light -> extras -> modüller -> overhaul -> user_polish) ve Bilge Yolaç CSS zinciri artık `ui_asset_css_order_rules` ile makine doğrulamalıdır; `ui_asset_validate_css_order()` JS sıra kuralları gibi UI render edilmeden önce çalışır.
- Yeni seam/bölge eklemek bilinçli bir karardır: dondurulmuş id listeleri ve bu belge birlikte güncellenir.

## Kritik Korunan Sınırlar

| Sınır | Neden kritik? | Önce okunacak belge/dosya |
|---|---|---|
| Türkçe karakter bütünlüğü ve mojibake | Windows VM, SQL Server/DB encoding, mailto, JSON/log ve UI sınırlarında veri bozulmasını önler. | [`../CLAUDE.md`](../CLAUDE.md), `R/utils_text_encoding.R`, `R/helpers_db_encoding.R` |
| DB write/read normalizasyonu | Legacy veri kirli olabilir; guard'lar zayıflatılmamalıdır. | [`../CLAUDE.md`](../CLAUDE.md), DB helper dosyaları |
| Source/load order | Erken yardımcılar geç yüklenirse runtime veya test davranışı bozulur. | `R/config_source_manifest.R`, `tests/testthat/helper_bootstrap.R` |
| Frontend asset order | Encoding, streaming, toast, modern welcome lifecycle, smoke seam ve tema davranışı sıra bağımlıdır. | `R/config_ui_assets.R`, ilgili asset manifest testleri |
| Windows/on-prem yol davranışı | UNC yollar, Türkçe karakterli path'ler, launcher ve SSO profili Windows VM üzerinde doğrulanır. | [`../RUNBOOK.md`](../RUNBOOK.md), `run_mergen_prod.bat`, `run_mergen_prod.R` |
| Dosya depolama ve upload lifecycle | Kullanıcı izolasyonu, güvenli yol çözümleme, önizleme ve cleanup davranışları hassastır. | Dosya helper/modül dosyaları, [`../CLAUDE.md`](../CLAUDE.md) |
| API key ve secret safety | Anahtarlar loglanmaz, dokümantasyona yazılmaz, kullanıcıya sızdırılmaz. | `.Renviron.example`, API key helper'ları, [`../CLAUDE.md`](../CLAUDE.md) |
| SSO/JWT sınırı | Üretimde fail-closed davranış ve imza doğrulaması önemlidir. | `R/config_sso.R`, `R/helpers_sso_signature.R`, [`../RUNBOOK.md`](../RUNBOOK.md) |
| Bağımlılık kilitleme / renv | `renv.lock` üretimi Windows VM/on-prem kuralına bağlıdır. | [`dependency-locking.md`](dependency-locking.md), [`../RENV_LOCK_STATUS.md`](../RENV_LOCK_STATUS.md) |
| Doğrulama kanıtı | `cloud-quick` ile tam VM doğrulaması aynı şey değildir. | [`../CLAUDE.md`](../CLAUDE.md), [`../RUNBOOK.md`](../RUNBOOK.md), `tools/ai_validate.sh` |
| Maintainability ratchet ve browser smoke | Frontend karmaşıklığı ve UX regresyonları kontrollü tutulur. `MERGEN_REQUIRE_BROWSER_UX_SMOKE=true` veya açık `MERGEN_BROWSER_BIN` browser smoke'u bloklayıcı yapar; `MERGEN_BROWSER_UX_BASE_URL` external-app modunda zaten çalışan app'i test eder. Başarılı kanıt `UX_SMOKE_DONE:PASS` işaretidir. | `tests/scripts/frontend_complexity_doctor.R`, `tests/scripts/ai_browser_ux_smoke.R` |
| Seam/bölge sahiplik yönetişimi | Üretim-kritik sınırların sahipliği, guard testleri ve manifest disiplini tek haritadan doğrulanır. | `R/config_seam_registry.R`, `R/config_ui_asset_zones.R`, `tests/scripts/seam_doctor.R` |
| Bilge Yolaç kalıcı oturum katmanı | Ajan oturumları `MB_Chats`/`MB_Messages`'tan ayrı `MB_ClaudeCode_*` tablolarında saklanır; persist hatası canlı yanıtı asla bozmamalı, tablolar yoksa bellek-içi mod korunmalıdır. | [`database-schema.md`](database-schema.md), `docs/sql/2026-07-bilge-yolac-sessions.sql`, `R/helpers_db_claude_code_sessions.R`, `R/helpers_claude_code_session_persistence.R` |

### Bilge Yolaç oturum saklama mimarisi

Bilge Yolaç, Claude Code Web benzeri kalıcı bir ajan oturum deneyimi sunar. Katman sahipliği:

- **DB katmanı**: `R/helpers_db_claude_code_session_queries.R` (saf başlık/kısaltma/SQL üreticileri) + `R/helpers_db_claude_code_sessions.R` (parametreli SQL orkestrasyonu, kullanıcı-izole liste/yükleme/yumuşak silme, tablo-yok güvenli düşüş). Tablolar: `MB_ClaudeCode_Sessions` + `MB_ClaudeCode_Runs` (bkz. [`database-schema.md`](database-schema.md)).
- **Runtime persist köprüsü**: `R/helpers_claude_code_session_persistence.R` — çalıştırma öncesi oturum kaydı açma (`cc_persist_session_begin`), akış sonu başarılı/başarısız/durdurulan çalıştırma kalıcılaştırma (`cc_persist_run_result`), bağ koparma (`cc_persist_detach_session`; Çıktıyı Temizle/model/workdir değişimi geçmişi SİLMEZ) ve test edilebilir hidrasyon planı (`cc_session_hydration_plan`; resume güvenlik kontrolü dahil).
- **Workbench oturum API'si**: `R/helpers_claude_code_workbench_session_api.R` — `claudeCodeServer()`'ın Oturumlar sayfasına açtığı `load_persisted_session` (geçmiş her zaman görünür; CLI `--resume` yalnızca runtime dizini erişilebilirse kurulur) ve `start_new_session` fonksiyonlarını üretir.
- **Oturumlar sayfası**: `R/module_claude_code_sessions_ui.R` (UI + saf kart/rozet/zaman üreticileri) + `R/module_claude_code_sessions.R` (liste/filtre/detay/arşiv sunucusu). Navigasyon: `Bilge Yolaç > Çalışma Alanı` (`claude_code`) ve `Bilge Yolaç > Oturumlar` (`claude_code_sessions`).
- **Frontend**: `www/js/claude_code_sessions.js` (`cc-hydrate-session` işleyicisi; mesaj görünümünü `window.MergenClaudeCode.addMessage` köprüsüyle tek kaynaktan yeniden oynatır) + `www/css/claude_code_sessions.css` (tamamı tema token'lı; koyu/açık tema otomatik).

## Ana Dizinler

| Dizin/dosya | İçerik |
|---|---|
| `R/` | Uygulama modülleri, helper katmanları, yapılandırma manifestleri ve entegrasyon kodu. |
| `www/` | Statik frontend varlıkları: CSS, JS, karakterler, video/müzik, smoke probeları ve lokal kütüphaneler. |
| `docs/` | Dokümantasyon merkezi, mimari harita, değişiklik notları ve bağımlılık kilitleme rehberi. |
| `tests/` | `testthat` testleri, smoke script'leri, CI/AI doğrulama yardımcıları ve bakım raporları. |
| `tools/` | `ai_validate.sh`, `renv_snapshot.R`, R ortam hazırlama, validation doctor ve launcher self-test. |
| `bilge_yolac_plugins/` | Bilge Yolaç eklenti dizinleri: code review, doc-gen, feature-dev, security-audit vb. |
| `MergenLauncher/` | Windows launcher ilişkili yardımcı alan. |
| `.Renviron.example` | Gerçek secret içermeyen yapılandırma örneği. |
| `RENV_LOCK_STATUS.md` | On-prem `renv.lock` görünürlük/commit sınırı açıklaması. |

## “X'i Düzenlemeden Önce Y'yi Oku” Tablosu

| Değişiklik alanı | Önce oku / kontrol et |
|---|---|
| DB helper'ları, bağlantı havuzu veya SQL bağlantısı | [`../CLAUDE.md`](../CLAUDE.md) encoding/DB kuralları, [`database-schema.md`](database-schema.md), `R/helpers_db_unicode_escape.R`, `R/helpers_db_encoding.R`, `R/helpers_db_connection.R`, `R/helpers_db_pool.R` (işlem-güvenli havuz; `with_db_transaction` rollback-before-return sözleşmesini koru). |
| Operasyonel soak / yük kanıtı | [`operational-soak-gate.md`](operational-soak-gate.md), `tests/scripts/run_operational_soak_gate.R`, `tests/scripts/soak_interactive_lane.R` (etkileşimli DB-havuz/işlem seridi), `tests/testthat/test-operational-soak-gate-contract.R`. |
| Dosya upload/preview/file manager | Bu dosyanın dosya lifecycle bölümü, `R/helpers_file_*`, `R/module_file_manager*.R`, ilgili testler. |
| Model routing, tool model veya vision | `R/config_api.R`, `R/helpers_api_model_config.R`, `R/helpers_vision_model_capabilities.R`, [`release-notes.md`](release-notes.md). |
| UI asset veya tema | `R/config_ui_assets.R`, `R/config_ui_asset_zones.R`, `www/css/`, `www/js/`, asset manifest/bölge/front-end testleri. |
| Yeni runtime R dosyası veya frontend varlığı | Bu belgenin seam/bölge bölümü, `R/config_seam_registry.R`, `R/config_ui_asset_zones.R`, `tests/testthat/test-seam-registry-contract.R`, `tests/testthat/test-ui-asset-zones-contract.R`. |
| Streaming veya Markdown/HTML güvenliği | `R/helpers_llm_sse*.R`, `R/helpers_markdown_safety.R`, `www/js/claude_code_streaming.js`, [`../CLAUDE.md`](../CLAUDE.md). |
| TTS/STT veya AI Uzman konuşması | `R/helpers_ai_expert.R`, `R/helpers_ai_expert_user_data.R`, `R/helpers_ai_expert_chunking.R`, `R/helpers_ai_expert_handlers_support.R`, `R/server_ai_expert_handlers.R`, API key helper'ları ve `.Renviron.example`. |
| SSO veya kimlik | `R/config_sso.R`, `R/helpers_sso.R`, `R/helpers_sso_signature.R`, [`../RUNBOOK.md`](../RUNBOOK.md). |
| Bilge Yolaç / Claude Code | `R/config_claude_code.R`, `R/helpers_claude_code_*.R`, `bilge_yolac_plugins/`, [`../CLAUDE.md`](../CLAUDE.md). |
| Bilge Savunması oyunu | [`bilge-savunmasi.md`](bilge-savunmasi.md), `R/config_bilge_savunmasi.R`, `R/helpers_bilge_savunmasi_validation.R`, `docs/sql/2026-07-bilge-savunmasi.sql`. |
| Deployment, VM veya launcher | [`../RUNBOOK.md`](../RUNBOOK.md), `run_mergen_prod.bat`, `run_mergen_prod.R`, `tools/test_mergen_prod_launcher.ps1`. |
| Paket veya `renv` | [`dependency-locking.md`](dependency-locking.md), [`../RENV_LOCK_STATUS.md`](../RENV_LOCK_STATUS.md), `R/config_packages.R`, `tools/renv_snapshot.R`. |
| Dokümantasyon-only değişiklik | README/dokümantasyon haritası, [`../AGENTS.md`](../AGENTS.md), uygun hafif doğrulama komutu. |

## Yeni Katkıcı Kontrol Listesi

- [ ] Önce [`../README.md`](../README.md) ile ürün kapsamını, sonra bu mimari haritayla depo yönünü anladım.
- [ ] Kodlama ajanı veya bakımcıysam [`../CLAUDE.md`](../CLAUDE.md) dosyasındaki İngilizce sözleşmenin otoritatif olduğunu biliyorum.
- [ ] Turkish encoding, DB normalization, source/load order ve secret safety sınırlarına dokunmadan önce ilgili helper/testleri okudum.
- [ ] Windows VM/on-prem davranışını README'den değil [`../RUNBOOK.md`](../RUNBOOK.md) üzerinden değerlendiriyorum.
- [ ] `renv.lock` üretimi için Linux/cloud/Codex ortamını kullanmayacağım.
- [ ] Yalnızca gerçekten çalıştırdığım doğrulama komutlarını kanıt olarak raporlayacağım.

## İlgili Belgeler

- İlk giriş: [`../README.md`](../README.md)
- Kodlama ajanı sözleşmesi: [`../CLAUDE.md`](../CLAUDE.md)
- Ajan özeti: [`../AGENTS.md`](../AGENTS.md)
- Operasyon kılavuzu: [`../RUNBOOK.md`](../RUNBOOK.md)
- Değişiklik notları: [`release-notes.md`](release-notes.md)
- Bağımlılık kilitleme: [`dependency-locking.md`](dependency-locking.md)
- Veritabanı tablo yapısı: [`database-schema.md`](database-schema.md)
- renv durumu: [`../RENV_LOCK_STATUS.md`](../RENV_LOCK_STATUS.md)
- Kullanıcı/asistan davranışı: [`../ai_rehber.md`](../ai_rehber.md)

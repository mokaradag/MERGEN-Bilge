# MERGEN Bilge Refactor Günlüğü

Bu günlük, kod davranışını değiştirmeden karmaşıklığı ve onboarding yükünü azaltmayı hedefleyen yapısal iyileştirmeleri kaydeder. Her giriş; seçilen iz(ler)i, değişen dosyaları, önce/sonra karmaşıklık notlarını, korunan davranış sözleşmelerini, eklenen/güncellenen testleri, gerçekten çalıştırılan doğrulamaları, kullanıcı için manuel QA listesini ve bilinen riskleri/atlanan doğrulamaları içerir.

Sıkı çalışma kuralları için İngilizce [`../CLAUDE.md`](../CLAUDE.md) otoritatif kalır.

---


## 2026-07-25 — Bloklamayan dosya alım (ingestion) hattı

### Seçilen paket / neden
Dosya yükleme, Shiny olay döngüsünde senkron çalışan tek büyük kalan iş yüküydü.
Hem Dosya Yönetimi toplu yüklemesi hem de Ana Söyleşi yüklemesi; doğrulama,
tam dosya hash'i, kalıcı klasöre kopyalama, boyut doğrulaması ve dosya başına
`index.json` oku/değiştir/yaz işlemini observer içinde yapıyordu. Çok dosyalı
bir parti bu yüzden yükleyen oturumu ve aynı R sürecini paylaşan diğer
oturumları donduruyordu. Ayrıca aynı dosya iki kez indeksleniyordu.

### Değişen dosyalar
- Yeni: `R/helpers_file_ingestion_task.R` (saf plan: normalizasyon, worker görev
  anlık görüntüsü, ucuz üstveri reddi, duplicate tespiti, özet/metrik),
  `R/helpers_file_ingestion_worker.R` (worker: yetkili doğrulama + kopyalama +
  bütünlük + yarım hedef temizliği + önbelleğe alınmış global paketi),
  `R/helpers_file_ingestion_queue.R` (sınırlı eşzamanlılık, sınırlı kuyruk,
  worker havuzu kapasite kapısı, `later` yeniden deneme pompası),
  `R/helpers_file_ingestion_runtime.R` (gönderim, oturum/iptal denetleyicisi,
  toplu indeks commit'i, tamamlanma geri çağrısı).
- `R/helpers_file_manager_upload_runtime.R`: `fm_process_bulk_upload_batch()`
  yerine `fm_dispatch_bulk_upload_batch()` + `fm_commit_bulk_upload_results()` +
  `fm_create_upload_runtime()`; `withProgress()` senkron döngüsü kaldırıldı.
- `R/helpers_file_pipeline.R`: `handle_file_upload_batch()` plan + gönderim
  şekline geçti (`process_next()` özyinelemesi kaldırıldı),
  `chat_upload_commit_results()` eklendi, `processAndSummarizeFile()`
  `already_persisted` bayrağını aldı (tam-bir-kez kayıt).
- `R/config_file_store_index_mutation.R`: `.file_store_index_entry()` ortak
  normalizasyonu + `mergen_index_persisted_files()` (parti başına TEK mutasyon).
- `R/module_file_manager.R`: yükleme runtime fabrikası, iptal denetleyicisinin
  "Tümünü Temizle" akışına bağlanması.
- Kayıt/sözleşme: `R/config_source_manifest.R` (files_preview_pipeline 5 → 9),
  `.Renviron.example` (yeni alım değişkenleri).
- Soak: `tests/scripts/soak_interactive_lane.R` + `tests/scripts/soak_artifacts.R`
  (`interactive_file_ingestion` kontrolü).

### Önce/sonra
- `fm_process_bulk_upload_batch()` (senkron for + `withProgress`) → gönderim
  anında dönen `fm_dispatch_bulk_upload_batch()`; pahalı iş worker'da.
- Dosya başına 2 indeks yazımı (pipeline + özetleyici) → parti başına 1 yazım.
- Dosya başına sınırsız future riski → parti başına tek worker görevi,
  varsayılan 2 eşzamanlı parti, 32'lik sınırlı kuyruk.
- `R/helpers_file_manager_upload_runtime.R` 118/3 → 165/6 (bütçe bilinçli olarak
  175/7'ye güncellendi); `R/module_file_manager.R` 559/9 → 557/9.
- Küresel bakım skoru 100/100, en büyük dosya 778 satır / 24 fonksiyon: DEĞİŞMEDİ.

### Korunan davranış sözleşmeleri
- Kullanıcı izolasyonu (`user_<id>` kovası), Türkçe görünen ad, storage adının
  UI'ya sızmaması, uzantı beyaz listesi, 25 MB dosya-başı sınırı, duplicate
  uyarısı, özetleme devri, önizleme/indirme/silme/yenileme/temizleme akışları.
- Desteklenmeyen uzantı worker'a HİÇ gönderilmez (gizli kaydedilmiş-ama-geçersiz
  yükleme yok).
- Bir dosyanın hatası partiyi düşürmez; yarım hedef silinir.
- Oturum kapanışında dosya yine indekslenir ama UI mutasyonu yapılmaz; açık
  iptalde kopyalar silinir ve indekse yazılmaz.

### Eklenen/güncellenen testler
- Yeni: `tests/testthat/test-file-ingestion-pipeline-behavior.R` (92 assertion),
  `tests/testthat/test-file-ingestion-contract.R`.
- Güncellendi: `test-file-pipeline-upload-batch-behavior.R` (async sözleşme +
  "gönderim anında yan etki yok" performans kontratı),
  `test-file-manager-state-runtime-contract.R`, `test-file-manager-module-policy-wiring.R`,
  `test-upload-size-policy.R` (dosya-başı sınır semantiği),
  `test-source-manifest-sections-contract.R`, `test-maintainability-ratchet.R`.

### Gerçekten çalıştırılan doğrulamalar
`parse_sanity_check.R` (1012 dosya), `smoke_app_boot.R`, `seam_doctor.R`,
maintainability raporu + ratchet, kaynak manifest/bölüm/seam/zone sözleşmeleri,
production + secret-leak sözleşmeleri, dosya/upload/manager/store/worker/pipeline/
ingestion/mcp/session desenine uyan tüm testthat dosyaları (0 fail), operasyonel
soak gate sözleşmesi.

### Manuel QA (kullanıcı tarafı)
- Dosya Yönetimi'ne 5-10 dosyalık bir parti bırakın; parti işlenirken tabloda
  gezinin, başka sekmeye geçin ve bir hızlı eylem tıklayın — arayüz donmamalı.
- Aynı anda ikinci bir tarayıcı oturumu açın; ilk oturum yüklerken ikinci oturum
  yanıt vermeye devam etmeli.
- Türkçe adlı bir dosya yükleyin, tam yeniden başlatma sonrası adın korunduğunu
  doğrulayın.
- Yükleme sürerken "Tümünü Temizle" deneyin; parti tabloya satır geri
  eklememeli.
- Desteklenmeyen uzantı ve 25 MB üstü dosya reddedilmeli.

### Bilinen risk / atlanan doğrulama
- Gerçek UNC/ağ paylaşımı kopyalama gecikmesi, Windows kısa yol/Türkçe path
  davranışı, çok kullanıcılı SSO eşzamanlılığı ve büyük parti sırasında ikinci
  tarayıcı oturumunun gerçek yanıt süresi YALNIZCA Windows VM'de doğrulanabilir.
- Kalıcı indeks yazımı hâlâ ana süreçtedir (bilinçli); çok büyük indekslerde bu
  maliyet ölçülmelidir.


## 2026-07-03 — Başlangıç şeritleri: Hızlı Başlangıç / Zengin Deneyim

### Seçilen paket / neden
Açılış deneyimi iki şeritli modele taşındı: kullanıcılar ya doğrudan Ana Söyleşi'ye inen minimal bir açılış (Hızlı Başlangıç) ya da mevcut sinematik gösteriyi koruyan akış (Zengin Deneyim) seçer. İlke: Hızlı Başlangıç açılış yükünü kaldırır, işlevselliği kaldırmaz; Zengin Deneyim korunur ve ilerleme ekranı daha dürüst/şeffaf olur. Ek olarak sinematik başlangıç yüzeyleri açık temadan tamamen ayrıştırıldı (koyu-tema kilidi) ve ekli Codex P2 bulgusu (süreç akışı seçici sıfırlaması) düzeltildi.

### Değişen dosyalar
- Yeni: `R/helpers_startup_lane.R` (saf şerit çözümleme: normalize/env-default/resolve/is_fast + şerit hazır-olma anahtar kümeleri), `R/module_startup_lane.R` (şerit sunucu gözlemcileri: intro kararı köprüsü + `startup_lane_resolved` işleme + hızlı şeritte `character_media_ready` erteleme işareti), `www/js/app_loading_lane.js` (istemci çözümleyici + ilk açılış iki-kart seçicisi; overlay'e satır içi gömülür).
- `R/module_app_loading.R`: seçici işaretlemesi (`app_loading_lane_selector_ui()`), `MERGEN_STARTUP_LANE` ortam varsayılanının istemciye gömülmesi, lane betiğinin `app_loading.js`'ten önce satır içi eklenmesi.
- `www/js/app_loading.js`: şeride duyarlı ilerleme (FAST_LANE_PCT / FAST_LANE_REQUIRED, `maybeFinishFastLane`), zengin şerit alt-ilerleme sayacı ("· 4 / 12") ve 6 sn+ etkin-aşama metni ("· sürüyor"), seçici açıkken gözcü bekletme.
- `www/js/app_loading_media.js`: şerit çözümüne göre başlatma (`startForLane`); hızlı şeritte ön yükleme ertelenir ve `character_media_preload_ready` `fast_lane_deferred` ile hemen bildirilir; zengin şeritte seri tam-tampon davranışı birebir korunur; ilerleme sayaçları iletilir.
- `R/module_startup_screen.R`: şerit gözlemcileri `startupLaneObserversInit()`'e delege edildi; hızlı şeritte açılışta müzik başlatılmaz.
- `R/server_welcome_handlers.R`: `welcome_client_ready` sondası hızlı şeritte video-oynuyor koşulunu beklemez.
- `www/js/modern_welcome_handler.js` + `www/css/welcome_modern.css`: hızlı şeritte video/neural başlatılmaz; statik premium koyu degrade zemin; selamlama korunur.
- `www/js/theme_manager.js`: sinematik koyu-tema kilidi (`holdCinematicDark`/`releaseCinematicDark`; `body.deep-space-active`/`app-ready` yaşam döngüsü izlenir).
- `www/css/theme_light_personalization.css`, `www/css/theme_light_pages.css`, `www/css/surum_bilgilendirme.css`: sinematik başlangıç yüzeylerinin açık-tema override'ları kaldırıldı (Destek > Yenilikler sayfası `.destek-surum-tab` açık tema kuralları korunur).
- `www/css/explore_cinematic.css`: mod kartlarında premium koyu cam yüzey + ölçülü spotlight.
- Ayarlar: `R/module_settings_yapilandirma_advanced_ui.R` (`.syap_startup_lane_card`), `R/module_settings_yapilandirma_ui.R` (kompozitör çağrısı), `R/module_settings_yapilandirma.R` (şerit gözlemcisi: saveSettings + applyStartupLane + toast), `R/module_settings.R` (varsayılan `ask_once`, yükleme/sıfırlama), `R/module_settings_kisisel.R` (+`www/css/settings_page.css`): hızlı şeritte Deneyim Modu kartları gizlenir, not gösterilir.
- Codex P2 düzeltmesi: `www/js/process_tools.js` (`resetProcessFlowSelect`), `R/module_settings.R` (sıfırlamada gönderim).
- Kayıt/sözleşme: `R/config_source_manifest.R` (module_identity_startup 12→14), `R/config_ui_asset_zones.R` + `tests/scripts/frontend_maintainability_report.R` (`js/app_loading_lane.js` sahipliği/allowlist).

### Önce/sonra
- `R/module_startup_screen.R` 359 → 357 satır (şerit gözlemcileri ayrı dosyada); `R/module_settings_yapilandirma_ui.R` 412 satır (yeni kart gelişmiş dosyada, bütçe 430 korunur); `R/module_settings_yapilandirma_advanced_ui.R` 353 → 415 (bütçe 370/6 → 430/7, yeni ürün yüzeyi gerekçesiyle bilinçli güncelleme); `R/module_settings.R` 676 satır (küresel 678 pini altında).

### Korunan davranış sözleşmeleri
- Zengin şerit: derin uzay girişi, giriş müziği, Keşfet, skip-intro, Odak/Dinamik/Bütünleşik, Bütünleşik karakter adımı, seri tam-tampon medya ön yükleme, tek `loadExploreAllCharVideos` handler'ı, gerçek-ilerleme (sahte trickle yok), stall gözcüsü + 180 sn mutlak sınır.
- Hızlı şerit: karşılama ekranı + hızlı eylem kartları + sohbet girişi + gönder/durdur + model seçici eksiksiz; ertelenen sayfalar açıldıklarında tam çalışır; işlev silinmez.
- Şerit API'si yokken tüm dosyalar eski davranışa düşer (savunmacı geriye dönük uyum).

### Eklenen/güncellenen testler
- Yeni: `tests/testthat/test-startup-lane-resolver-behavior.R` (çözümleyici davranışı), `tests/testthat/test-startup-lane-contract.R` (seçici/hızlı-şerit/zengin-korunum/koyu-kilit/ayarlar/manifest sözleşmeleri).
- Güncellenen: `test-source-manifest-sections-contract.R` (bölüm çapaları 12→14, toplam 292→294), `test-settings-yapilandirma-ui-id-surface-behavior.R` (+`startup_lane_card`, `startup_experience_lane`, "Başlangıç Deneyimi"), `test-maintainability-ratchet.R` (gelişmiş kart dosyası 430/7), `test-startup-screen-module-behavior.R` (gerçek sahip dosyaları source eder), `test-frontend-selector-contract.R` (süreç akışı sıfırlama sözleşmesi).

### Gerçekten çalıştırılan doğrulamalar
- `bash tools/ai_validate.sh quick`: environment/parse/app-source-smoke/focused-contract-tests, 0 failed / 0 skipped (`artifacts/ai-validation/20260703-003714/summary.json`).
- Odaklı testler: startup-lane (yeni 2 dosya), app-loading (behavior+brand), settings (kisisel/reset/yapilandirma kartlar+id-surface+refactor), startup-screen (UI refactor + module behavior), boot-readiness, startup-observers smoke, e2e-boot-welcome, manifest (sections/global/source), seam-registry, ui-asset-zones, ui-asset-manifest, theme-light-modular, frontend-maintainability-ratchet, maintainability-ratchet, production-contracts, runtime-network-boundary, secret-leak, browser-smoke-harness, ux-smoke-browser, langflow (handler/runtime), frontend-selector — tümü geçti.
- `bash tools/ai_validate.sh full --boot-smoke` çalıştırıldı (sonucu bu girişin altındaki doğrulama notunda ve PR raporunda).

### Manuel QA (VM/tarayıcı)
- İlk açılışta (tercih yokken) şerit seçicisinin gelmesi; seçim sonrası bir daha sorulmaması.
- Hızlı Başlangıç: doğrudan Ana Söyleşi, hızlı eylemler/giriş/gönder-durdur/model seçici; müzik/intro/video yok; Kayıtlı Söyleşiler/Geçmiş/Galeri/Dosya Yönetimi açıldığında tam çalışma.
- Zengin Deneyim: derin uzay + müzik + Keşfet + mod/karakter akışı; ilerleme alt-sayaç ve "sürüyor" metni; %100 sonrası temiz geçiş.
- Açık temalı kullanıcıda sinematik akışın koyu kalması ve kapanışta açık temaya dönüş.
- "Ayarları Sıfırla" sonrası Süreç modunun eski akışı yeniden kalıcılaştırmaması.

### Bilinen riskler / atlanan doğrulamalar
- Gerçek tarayıcı UX (UX_SMOKE_DONE:PASS), VM/SSO, Keycloak yönlendirme zamanlaması ve gerçek medya tamponlama davranışı cloud'da doğrulanamaz; VM'de doğrulanmalıdır.
- Hızlı şeritte sunucu tarafı arka plan hazırlıkları (kayıtlı sohbet önizleme, dosya indeksi, galeri taraması) bilinçli olarak korunur (asenkron; kapanışı bloklamaz). Şeride göre sunucu tarafı tam erteleme (dosya indeksi/galeri taramasının sekme açılışına taşınması) ayrı, sözleşme-yoğun bir izleme işi olarak önerilir.
- Boşta ısınma (idle warm-up) bu pakette uygulanmadı; hızlı şeridin mevcut arka plan hazırlıkları zaten hafif meta düzeyindedir.

## 2026-07-02 — Langflow temizliği, çoklu süreç akışı ve ikinci LLM uç noktasının kaldırılması

### Seçilen paket / neden
Süreç Yönetimi ve Uygulama Uzmanı araçları kurumsal Langflow'a taşındıktan sonra biriken teknik borç temizlendi: (1) bu araçlarda görsel-oluşturma spinner'ı yerine standart düşünme paneli kullanımı, (2) stale `model_id` tanımları, (3) yerel model rozetinin yanıltıcı gösterimi, (4) artık kullanılmayan ikinci LLM uç noktası kavramı. Ayrıca Süreç Yönetimi için çoklu adlandırılmış Langflow akışı seçimi eklendi.

### Değişen dosyalar
- `R/config_api.R`: ikinci LLM uç noktası (`secondary_llm_endpoint`/`secondary_llm_api_key`, `LOCAL_LLM_ENDPOINT_ALT*`) ve `LANGFLOW_API_KEY` ALT-fallback'i kaldırıldı; `local_llm_endpoints`/`_keys`/`_user_managed` ve endpoint haritası tek `primary`'ye indirgendi; `process`/`app_expert` `model_id`'leri kaldırıldı; Langflow ham çoklu-akış env alanları (`process_flow_ids_raw`/`_names_raw`/`_legacy_id`) eklendi.
- `R/helpers_langflow_runtime.R`: `mergen_parse_langflow_process_flows`, `mergen_langflow_process_flows`, `mergen_langflow_process_flow_id`, `mergen_langflow_process_flow_label`, `mergen_langflow_setting_flags` eklendi; `mergen_langflow_flow_id_for_family` `process` ailesi için `selected_flow` çözümlemesi yapar.
- `R/helpers_send_message_request_lifecycle.R`: `mergen_build_thinking_panel_plan` `force_simulated_panel` argümanı (Langflow için model etiketsiz simüle panel).
- `R/helpers_send_message_core.R`: `mergen_build_langflow_ctx` (seçili akış çözümlemesi + ctx; server_send_message.R bütçesi korunur).
- `R/server_send_message.R`: Langflow dalı `force_simulated_panel` + `mergen_build_langflow_ctx` kullanır.
- `R/server_handler_langflow.R`: görsel-oluşturma spinner ekleme bloğu kaldırıldı (standart düşünme paneli korunur); seçili süreç akışı çözülür ve loglama için akış adı eklenir.
- `R/server_outputs_chat.R`: `current_model_display` Langflow aracı aktifken gizlenir (`mergen_langflow_setting_flags` ile).
- `R/helpers_api_model_tool_runtime.R`: `build_main_actions_data_from_config` Langflow araçlarına model enjekte etmez.
- `R/module_quick_actions.R`, `R/module_settings_yapilandirma.R`, `R/module_settings.R`, `R/server_observers_image_gallery.R`: `toggleProcessMode` gösterme/gizleme; Langflow araçlarında model değişimi atlanır.
- `ui.R`: `process_chat_controls` / `chat_process_flow` süreç akışı seçici (model seçicinin yanında).
- Yeni frontend varlıkları: `www/js/process_tools.js`, `www/css/process_tools.css`; `R/config_ui_assets.R` ve `R/config_ui_asset_zones.R` kaydı.
- `R/utils_log_redact.R`, `tests/scripts/soak_secret_redaction.R`: stale ALT anahtar adları çıkarıldı; `LANGFLOW_API_KEY`/`LANGFLOW_BASE_URL` korundu/eklendi.
- Testler: `test-langflow-runtime-behavior.R`, `test-langflow-handler-behavior.R`, `test-chat-outputs-behavior.R`, `test-api-model-config-refactor-contract.R`, `test-ui-asset-manifest-contract.R` güncellendi/genişletildi.
- Dokümanlar: `.Renviron.example`, `docs/technical-reference.md`, `docs/release-notes.md`, `docs/refactor-log.md`.

### Korunan davranış
Langflow olmayan tüm araçlar (normal sohbet, Excel, kodlama, özetleme, SQL analizi, görsel oluşturma) için model seçimi, model rozeti, thinking/streaming davranışı ve TTS/STT değişmedi. Langflow bayat-istek/Durdur/temizlik/backpressure ve "yapılandırma eksik → normal LLM'ye düşme" davranışı korunur.

### Çalıştırılan doğrulamalar (cloud `C.UTF-8`)
- `testthat::test_file(...)`: langflow-runtime (87), langflow-handler (33), chat-outputs (20), api-model-config-refactor (46), quick-actions-server (37), ui-asset-manifest (229), ui-asset-zones (17), frontend-selector (81), frontend-maintainability-ratchet, maintainability-ratchet (258), log-redact, secret-leak, send-message-* , source-manifest, production-contracts, quick-action-routing, ux-regression-guardrails, e2e-quick-actions-streaming — hepsi 0 fail.
- `source("app.R")` boot smoke: çoklu akış parse/çözümleme, tek `primary` uç nokta, `process`/`app_expert` `model_id` NULL doğrulandı.

### Manuel QA (VM/tarayıcı — cloud'da kanıtlanamaz)
- Süreç Yönetimi/Uygulama Uzmanı prompt gönder → görsel spinner yerine düşünme paneli; yanıt gelince nihai cevap.
- Süreç Yönetimi açılır menüsünden farklı akış seç → seçilen akışın çağrıldığını doğrula.
- Langflow araçlarında model rozetinin gizlendiğini, diğer araçlarda göründüğünü doğrula.
- Açık/koyu temada süreç akışı açılır menüsünü doğrula.

### Bilinen riskler / atlanan doğrulamalar
Gerçek Langflow uç noktası, tarayıcı UX ve VM/SSO davranışı cloud'da doğrulanamaz; VM'de manuel doğrulama gerekir.


## 2026-06-26 — Modern welcome otoritatif sahiplik sözleşmesi düzeltmesi

### Seçilen paket / neden
Codex review notu, önceki modern welcome split'inden sonra `CLAUDE.md` otoritatif sözleşmesinin güncel sahiplikle tam hizalanmadığını işaret etti: `initModernWelcome` artık `www/js/modern_welcome_handler.js` içinde yaşarken gelecekteki maintainer/agent yönlendirmesi bu sınırı açıkça korumuyordu. Bu paket, runtime davranışını değiştirmeden review ile kanıtlanan sahiplik drift riskini kapattı.

### Değişen dosyalar
- `CLAUDE.md`: modern welcome frontend ownership bölümü eklendi; `www/js/modern_welcome_handler.js` dosyasının `initModernWelcome` ve görünür welcome startup lifecycle sahibi olduğu, `www/js/shiny_message_handlers.js` dosyasının genel mesaj köprüsü olarak kalacağı açıkça yazıldı.
- `tests/testthat/test-modern-welcome-handler-split-contract.R`: mevcut split/manifest sözleşmesine, otoritatif maintainer contract'ın aynı sahipliği belgelediğini doğrulayan deterministik metin koruması eklendi.
- `docs/feature-ownership-map.md`: modern welcome sahiplik riskinin kapatıldığı ve sonraki hedeflerin güncel raporlara göre seçilmesi gerektiği belirtildi.
- `.ai/next-session-eliminate-weaknesses-prompt.md`: handoff kompakt biçimde yenilendi.

### Önce / sonra etki
- Önce: Kod ve asset contract `initModernWelcome` sahipliğini `modern_welcome_handler.js` altında koruyordu; ancak otoritatif maintainer rehberinde bu yeni sahiplik açıkça sabitlenmediği için gelecek oturumlar generic Shiny köprüsüne geri taşıma riski taşıyordu.
- Sonra: Otoritatif rehber, manifest/zone/test contract ile aynı sahipliği söylüyor; test, bu belge-sözleşme drift'ini yakalayacak. Runtime JS/R davranışı, asset sırası, DB/SSO/encoding sınırları değişmedi.

### Korunan davranış
`initModernWelcome` mesaj adı, modern welcome retry/timer/video/neural/greeting lifecycle sahipliği, `shiny_message_handlers.js` içindeki genel toast/scroll/quick-action/fade davranışları, frontend asset order ve zone ownership korunur.

### Çalıştırılan doğrulamalar
- `git status` / `git diff --stat` başlangıç keşfi.
- `LANG=C.UTF-8 LC_ALL=C.UTF-8 Rscript tests/scripts/maintainability_report.R` başlangıç keşfi.
- `LANG=C.UTF-8 LC_ALL=C.UTF-8 Rscript tests/scripts/frontend_complexity_doctor.R` başlangıç keşfi.
- `LANG=C.UTF-8 LC_ALL=C.UTF-8 Rscript tests/scripts/seam_doctor.R` başlangıç keşfi.
- Odaklı testler ve normal quick validation bu girişten sonra final doğrulama bölümünde kaydedildi.

### Kalan riskler / atlanan kanıtlar
Bu paket docs + deterministic contract test düzeyindedir; VM, gerçek browser, SQL Server, SSO ve canlı endpoint davranışı kanıtlamaz.

---
## 2026-06-26 — Modern welcome Shiny handler/lifecycle ayrımı

### Seçilen paket / neden
Frontend handler-density paketi seçildi. Taze `frontend_complexity_doctor` çıktısı `www/js/shiny_message_handlers.js` dosyasını en yüksek Shiny handler yoğunluğuna sahip app-owned JS dosyası olarak gösterdi (önce 535 satır / 45 fonksiyon / 18 event handler / 17 Shiny handler) ve handoff bu dosyayı en iyi anlamlı hedef olarak işaretliyordu. Kod incelemesinde `initModernWelcome` retry/timer/video/neural/greeting lifecycle kümesinin genel Shiny mesaj köprüsü içinde ayrı ve stateful bir sınır oluşturduğu görüldü.

### Değişen dosyalar
- `www/js/modern_welcome_handler.js`: `initModernWelcome` Shiny mesaj handler'ı, boot retry timer temizliği, DOM/dependency readiness kontrolü, welcome video resume denemesi, neural/greeting init ve karakter accent fallback davranışını taşıyan yeni odaklı dosya.
- `www/js/shiny_message_handlers.js`: genel mesaj köprüsünde toast/scroll/CodeMirror/font/follow-up/neural/search/storage/removeExcel/quick-action handler'ları kaldı; modern welcome lifecycle kümesi çıkarıldı.
- `R/config_ui_assets.R`: yeni dosya `shiny_message_handlers.js` sonrasında ve `ui_init.js` / welcome video-neural varlıklarından önce yüklenecek şekilde manifestlendi; sıralama kuralı eklendi.
- `R/config_ui_asset_zones.R`: yeni JS varlığı `shiny_mesaj_koprusu` bölgesinde sahiplenildi.
- `tests/testthat/test-modern-welcome-handler-split-contract.R`: yeni manifest/zone/order ve davranışsal metin sözleşmesi eklendi.
- `tests/testthat/test-frontend-selector-contract.R`, `tests/testthat/test-e2e-boot-welcome-regression.R`: modern welcome lifecycle sözleşmeleri yeni dosyaya taşındığı için güncellendi.

### Önce / sonra karmaşıklık ve risk
- Önce: `www/js/shiny_message_handlers.js` 535 satır / 45 fonksiyon / 18 event handler / 17 Shiny handler; modern welcome lifecycle timer'ı merkezi mesaj köprüsünün içinde yaşıyordu.
- Sonra: `www/js/shiny_message_handlers.js` 401 satır / 38 fonksiyon / 17 event handler / 16 Shiny handler; `www/js/modern_welcome_handler.js` odaklı lifecycle asset'i olarak manifest/zone kapsamına alındı.
- Ana risk azaltımı: `initModernWelcome` retry/timer/DOM readiness/video-neural-greeting orchestration tek sahipli bir dosyaya ayrıldı; genel mesaj köprüsünün handler yoğunluğu azaldı ve yeni contract test bu sınırın geri kaymasını yakalar.

### Davranış korundu
`initModernWelcome` mesaj adı, `MAX_ATTEMPTS = 80` / `RETRY_DELAY_MS = 50` bekleme akışı, görünür DOM ve dependency readiness kontrolleri, aynı video konteynerini zorla destroy etmeme sözleşmesi, autoplay resume denemesi, `MERGEN_SAVED_CHARACTER_ACCENT` önceliği, `MERGEN_ACTIVE_CHARACTER_ACCENT` geriye dönük fallback'i ve `WelcomeNeuralNetwork` / `WelcomeGreeting` init çağrıları korunur. `showNeuralAnimation`, hızlı eylem debounce, localStorage restore, takip soruları ve sağlık/yönetici timestamp handler'ları merkezi köprüde kaldı.

### Testler / doğrulama
- `node --check www/js/shiny_message_handlers.js` → PASS.
- `node --check www/js/modern_welcome_handler.js` → PASS.
- `Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-modern-welcome-handler-split-contract.R", reporter = "summary")'` → PASS.
- `Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-ui-asset-manifest-contract.R", reporter = "summary")'` → PASS.
- `Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-ui-asset-zones-contract.R", reporter = "summary")'` → PASS.
- `Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-frontend-selector-contract.R", reporter = "summary")'` → PASS.
- `Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-e2e-boot-welcome-regression.R", reporter = "summary")'` → PASS.
- `LANG=C.UTF-8 LC_ALL=C.UTF-8 Rscript tests/scripts/frontend_complexity_doctor.R` → PASS; artifact `artifacts/frontend-complexity-doctor/frontend-complexity-doctor-20260626-201016.json`.
- `LANG=C.UTF-8 LC_ALL=C.UTF-8 Rscript tests/scripts/maintainability_report.R` → PASS; R maintainability 100/100 kaldı.
- `LANG=C.UTF-8 LC_ALL=C.UTF-8 Rscript tests/scripts/seam_doctor.R` → PASS / OK; artifact `artifacts/seam-doctor/seam-doctor-20260626-201021.json`.
- `Rscript tests/scripts/parse_sanity_check.R` → PASS (868 dosya).
- `Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-maintainability-ratchet.R", reporter = "summary")'` → PASS.
- `Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-frontend-maintainability-ratchet.R", reporter = "summary")'` → PASS.
- `Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-ux-regression-guardrails.R", reporter = "summary")'` → PASS after updating the moved modern welcome expectation.
- `bash tools/ai_validate.sh quick` → PASS; failed_steps=0, skipped_steps=0; artifact `artifacts/ai-validation/20260626-201659/summary.json`.

### Atlanan / başarısız doğrulamalar
`bash tools/ai_validate.sh full --boot-smoke` çalıştırıldı ancak full testthat suite adımında daha önce handoff'ta da görülen Shiny destroyed-reactive izolasyon hataları (`test-chat-actions-behavior.R`, `test-image-gallery-observers-behavior.R`) nedeniyle durdu; boot-smoke aşamasına ulaşılamadı. İlk full denemede ayrıca bu split sonrası güncellenmemiş `test-ux-regression-guardrails.R` statik beklentisi yakalandı ve düzeltildi; ikinci full denemede yalnız destroyed-reactive hataları kaldı. Artifact `artifacts/ai-validation/20260626-201800/summary.json`. VM, gerçek browser, DB, SSO, SQL Server Türkçe encoding, live endpoint ve production app boot kanıtı üretilmedi; kapsam frontend statik asset/order/contract ve JS syntax düzeyindedir.

### Kalan riskler / sonraki adaylar
Gerçek tarayıcıda video/neural görsel eşdeğerlik ayrıca browser smoke ile kanıtlanmalıdır. Sonraki anlamlı frontend hedefleri `www/js/claude_code.js` Shiny handler yoğunluğu, `www/js/tool_backgrounds.js` fonksiyon yoğunluğu veya `www/js/file_handlers.js` event handler yoğunluğudur.

## 2026-06-26 — Deep Space frontend yaşam döngüsü sınırı

### Seçilen paket / neden
Frontend yaşam döngüsü paketi seçildi. Taze `frontend_complexity_doctor` çıktısı `www/js/deep_space_intro.js` dosyasını en büyük app-owned JS dosyası olarak gösterdi (820 satır / 32 fonksiyon) ve handoff Deep Space scene lifecycle, render-loop, resize ve startup cleanup sınırını yüksek değerli hedef olarak işaretliyordu.

### Değişen dosyalar
- `www/js/deep_space_intro_lifecycle.js`: timeout/rAF takip-iptal yardımcıları, skip-intro okuması ve tekil DOMContentLoaded auto-init bağlayıcısı eklendi.
- `www/js/deep_space_intro.js`: loading timeout, fallback startup, resize rAF ve auto-init sorumluluklarını lifecycle helper'a delege eder; sahne/Three.js/shader davranışı korunur.
- `R/config_ui_assets.R`, `R/config_ui_asset_zones.R`, `tests/testthat/test-ui-asset-manifest-contract.R`: yeni helper `deep_space_intro_solar.js` ile `deep_space_intro.js` arasına manifestlenip `karsilama_intro` bölgesine sahipletildi.
- `tests/testthat/test-deep-space-frontend-lifecycle-contract.R`: helper API'si, tekil DOMContentLoaded davranışı, cleanup delegasyonu ve manifest/zone sırası için statik sözleşme eklendi.

### Önce / sonra karmaşıklık ve risk
- Önce: `www/js/deep_space_intro.js` 820 satır / 32 fonksiyon; scene setup, loading timers, fallback startup, resize rAF ve auto-init aynı dosyadaydı.
- Sonra: `www/js/deep_space_intro.js` 791 satır; zamanlayıcı/rAF/auto-init sınırı ayrı `www/js/deep_space_intro_lifecycle.js` dosyasına taşındı.
- Ana risk azaltımı: destroy sonrası gecikmiş loading/fallback/resize callback sahipliği tek `cancelAll()` sınırıyla kapatılır; yeni testler bu delegasyonun geri alınmasını yakalar.

### Davranış korundu
Deep Space public API (`init`, `destroy`, `isActive`), `mergen_settings.skip_intro` davranışı, local Three.js/offline asset kullanımı, `deep-space-active` gövde sınıfı, shader/solar kurulum sırası ve texture path varsayılanı korunur. Manifest sırası artık `earth_shader` → `solar` → `lifecycle` → `deep_space_intro` olarak açıkça test edilir.

### Testler / doğrulama
- `node --check www/js/deep_space_intro_lifecycle.js` → PASS.
- `node --check www/js/deep_space_intro.js` → PASS.
- `Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-deep-space-frontend-lifecycle-contract.R", reporter="summary")'` → PASS.
- `Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-ui-asset-manifest-contract.R", reporter="summary")'` → PASS.
- `Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-ui-asset-zones-contract.R", reporter="summary")'` → PASS.
- `LANG=C.UTF-8 LC_ALL=C.UTF-8 Rscript tests/scripts/frontend_complexity_doctor.R` → PASS; `www/js/deep_space_intro.js` 820 → 791, artifact `artifacts/frontend-complexity-doctor/frontend-complexity-doctor-20260626-184650.json`.
- `LANG=C.UTF-8 LC_ALL=C.UTF-8 Rscript tests/scripts/maintainability_report.R` → PASS; R maintainability 100/100 kaldı.
- `LANG=C.UTF-8 LC_ALL=C.UTF-8 Rscript tests/scripts/seam_doctor.R` → PASS / OK; artifact `artifacts/seam-doctor/seam-doctor-20260626-184658.json`.
- `Rscript tests/scripts/parse_sanity_check.R` → PASS (867 dosya).
- `Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-frontend-maintainability-ratchet.R", reporter="summary")'` → PASS.
- `Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-maintainability-ratchet.R", reporter="summary")'` → PASS.
- `bash tools/ai_validate.sh quick` → PASS; failed_steps=0, skipped_steps=0; artifact `artifacts/ai-validation/20260626-184912/summary.json`.
- `bash tools/ai_validate.sh full --boot-smoke` → FAIL; full testthat suite adımında daha önce handoff'ta da belirtilen Shiny destroyed-reactive izolasyon hataları (`test-chat-actions-behavior.R`, `test-image-gallery-observers-behavior.R`) nedeniyle durdu; boot-smoke aşamasına ulaşılamadı. Artifact `artifacts/ai-validation/20260626-185055/summary.json`.

### Atlanan doğrulamalar
Full validation boot-smoke aşamasına ulaşamadığı için VM, gerçek tarayıcı, DB, SSO, SQL Server Türkçe encoding, live endpoint ve production app boot kanıtı üretilmedi; görsel sahne eşdeğerliği statik sözleşme ve JS syntax düzeyinde doğrulandı.

### Kalan riskler / sonraki adaylar
Deep Space shader/solar math değiştirilmedi; gerçek WebGL görsel kontrol VM/browser smoke ile ayrıca kanıtlanabilir. Sonraki anlamlı frontend hedefleri `www/js/shiny_message_handlers.js` handler yoğunluğu, `www/js/claude_code.js` Shiny handler yoğunluğu veya `www/js/tool_backgrounds.js` fonksiyon yoğunluğudur.

## 2026-06-26 — File Manager toplu yükleme runtime ayrımı

### Seçilen paket / neden
File Manager paketi seçildi. Güncel discovery çıktısında `R/module_file_manager.R` 642/10 ile hâlâ en büyük R dosyaları arasındaki gerçek lifecycle orkestrasyon adayıydı; `module_admin_yanit_analizi_outputs.R` belgelenmiş flat renderer olduğu için tekrar hedeflenmedi. Toplu upload dalı dosya doğrulama, kalıcı kopyalama, indeks yazma ve Shiny mesajlarını tek observer içinde taşıyordu.

### Değişen dosyalar
- `R/helpers_file_manager_upload_runtime.R`: toplu yükleme doğrulama, SSO-ready gate, kalıcı kopya, indeks yazma ve `process_uploaded_file()` delegasyonunu tek runtime helper'a taşıdı.
- `R/module_file_manager.R`: `execute_bulk_upload` observer'ı UI reset/mesaj orkestrasyonunda kaldı; dosya başı lifecycle işlemini helper'a delege eder.
- `R/config_source_manifest.R`, `tests/testthat/test-source-manifest-contract.R`, `tests/testthat/test-source-manifest-sections-contract.R`: yeni helper storage sonrası / delete-runtime öncesi açık kaynak sırasına eklendi.
- `tests/testthat/test-file-manager-state-runtime-contract.R`: helper extraction contract ve Türkçe dosya adlı toplu yükleme davranış testi eklendi.
- `tests/testthat/test-maintainability-ratchet.R`: `module_file_manager.R` bütçesi 560/10'a, yeni upload helper bütçesi 140/3'e sıkılaştırıldı.

### Önce / sonra karmaşıklık
- Önce: `R/module_file_manager.R` 642 satır / 10 fonksiyon.
- Sonra: `R/module_file_manager.R` 550 satır / 9 fonksiyon; yeni `R/helpers_file_manager_upload_runtime.R` 118 satır / 1 fonksiyon.
- Maintainability skoru 100/100 kaldı; 800+ R dosyası yok; küresel en büyük dosya 678 satır olarak değişmedi.

### Davranış korundu
Toplu upload sırası korunur: duplicate ayrımı, SSO/auth-ready fail-closed gate, merkezi `validate_uploaded_file()` + `fm_normal_allowed_extensions()` kontrolü, `copy_to_mcp_base()`, persisted-size güncellemesi, kalıcı indeks yazma, `process_uploaded_file(..., generate_message = FALSE)`, başarı mesajı ve `files_added_to_context()` bildirimi. Traversal/safe-path/upload doğrulama ve Türkçe görünen dosya adı sözleşmeleri gevşetilmedi.

### Testler / doğrulama
- `Rscript tests/scripts/parse_sanity_check.R` → PASS (865 dosya).
- `Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-file-manager-state-runtime-contract.R", reporter="summary")'` → PASS.
- `Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-source-manifest-contract.R", reporter="summary")'` → PASS.
- `Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-source-manifest-sections-contract.R", reporter="summary")'` → PASS.
- `Rscript tests/scripts/maintainability_report.R` → PASS (100/100; `module_file_manager.R` 550/9).
- `Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-maintainability-ratchet.R", reporter="summary")'` → PASS.

### Ek doğrulama sonuçları
- `Rscript tests/scripts/frontend_complexity_doctor.R` → PASS; R-only değişiklik olduğu için mevcut frontend risk listesi değişmedi; artifact `artifacts/frontend-complexity-doctor/frontend-complexity-doctor-20260626-125422.json`.
- `Rscript tests/scripts/seam_doctor.R` → PASS / OK; `dosya_yasam_dongusu` runtime dosyası 24 olarak güncellendi; artifact `artifacts/seam-doctor/seam-doctor-20260626-125427.json`.
- `bash tools/ai_validate.sh quick` → PASS; failed_steps=0, skipped_steps=0; artifact `artifacts/ai-validation/20260626-125434/summary.json`.
- `bash tools/ai_validate.sh full --boot-smoke` → FAIL; `full testthat suite` adımında Shiny destroyed-reactive test izolasyonu hataları (`test-chat-actions-behavior.R`, `test-image-gallery-observers-behavior.R`) nedeniyle durdu; File Manager policy-wiring contract hatası düzeltildikten sonra tekrarlandı ve kalan hatalar bu paketle ilişkili olmayan full-suite izolasyon hatalarıdır. Artifact `artifacts/ai-validation/20260626-125941/summary.json`; boot-smoke adımına ulaşılamadı.

### Atlanan doğrulamalar
Full validation boot-smoke aşamasına ulaşamadığı için VM, DB, SSO, gerçek tarayıcı, SQL Server Türkçe encoding ve gerçek app boot kanıtı üretilmedi; bu paket Linux/cloud statik + testthat + quick-validation kanıtıyla sınırlıdır.

### Kalan riskler / sonraki adaylar
File Manager'da en yüksek churn'lü lifecycle dalları artık küçük helper'lara ayrıldı; yeniden aynı splitleri yapmayın. Güncel en iyi sonraki hedefler frontend yoğunluk paketleri: `www/js/deep_space_intro.js` ve `www/js/ai_expert_manager.js`. R tarafında `helpers_claude_code_process.R` ancak discovery onu açık top risk yaparsa ele alınmalı.

## 2026-06-25 — File Manager kalıcı silme runtime ayrımı

### Seçilen paket / neden
File Manager paketi seçildi. Discovery çıktısında `R/module_file_manager.R` 677 satırla R tarafındaki en büyük gerçek refactor adayıydı; `module_admin_yanit_analizi_outputs.R` ise belgelenmiş düşük-öncelikli flat renderer olarak bırakıldı.

### Değişen dosyalar
- `R/helpers_file_manager_delete_runtime.R`: fiziksel dosya silme, resolve fallback, kullanıcı klasörü fallback ve indeks temizliği için yeni helper.
- `R/module_file_manager.R`: `confirm_delete_file` observer'ı fiziksel lifecycle temizliğini helper'a delege eder; Shiny state/UI yan etkileri modülde kalır.
- `R/config_source_manifest.R`, `R/bootstrap_source_manifest.R`, `tests/testthat/helper_bootstrap.R`, `tests/testthat/test-source-manifest-contract.R`: yeni helper storage sonrası / state runtime öncesi source edilir.
- `tests/testthat/test-file-manager-delete-runtime-behavior.R`: doğrudan silme + Türkçe dosya adı + indeks temizliği ve resolve/fallback sırası davranış testleri.
- `tests/testthat/test-maintainability-ratchet.R`: File Manager bütçesi sıkılaştırıldı; yeni delete helper küçük kalacak şekilde kilitlendi.

### Önce / sonra karmaşıklık
- Önce: `R/module_file_manager.R` 677 satır / 11 fonksiyon.
- Sonra: `R/module_file_manager.R` 642 satır / 10 fonksiyon; yeni helper 57 satır / 4 fonksiyon.
- Maintainability skoru 100/100 kaldı; 800+ R dosyası yok; küresel en büyük dosya 678 satır olarak değişmedi.

### Davranış korundu
Silme sırası korunur: doğrudan bilinen yollar, `resolve_uploaded_file()`, kullanıcı klasöründe basename fallback ve son olarak `mergen_remove_from_index()`. Modülün seçim temizliği, temp dosya temizliği, tablo satırı kaldırma, toast ve mesaj tetikleme davranışı değişmedi. Traversal/safe-path/upload doğrulama sözleşmeleri gevşetilmedi.

### Testler / doğrulama
- `Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-file-manager-delete-runtime-behavior.R", reporter="summary")'` → PASS.
- `Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-source-manifest-contract.R", reporter="summary")'` → PASS.
- `Rscript tests/scripts/parse_sanity_check.R` → PASS (864 dosya).
- `Rscript tests/scripts/maintainability_report.R` → PASS (100/100; `module_file_manager.R` 642/10).
- `Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-maintainability-ratchet.R", reporter="summary")'` → PASS.
- `Rscript tests/scripts/seam_doctor.R` → PASS / OK.
- `Rscript tests/scripts/frontend_complexity_doctor.R` → PASS (frontend değişikliği yok; mevcut JS/CSS risk listesi değişmedi).
- `bash tools/ai_validate.sh quick` → PASS; failed_steps=0, skipped_steps=0; artifact `artifacts/ai-validation/20260625-201131/summary.json`.

### Atlanan doğrulamalar
VM, DB, SSO, gerçek tarayıcı ve SQL Server Türkçe encoding doğrulaması yapılmadı; bu paket Linux/cloud'da statik + testthat + source-manifest + seam kanıtıyla sınırlıdır.

### Kalan riskler / sonraki adaylar
En iyi sıradaki paketler frontend tarafında `www/js/deep_space_intro.js` veya `www/js/ai_expert_manager.js` yoğunluğunu azaltmaktır. R tarafında `helpers_claude_code_process.R` ancak discovery raporu onu gerçek top risk olarak gösterirse ele alınmalı; `module_admin_yanit_analizi_outputs.R` flat renderer olduğu için düşük öncelik kalır.

## 2026-06-24 — Gerçek SSE worker-export globals listesinin saf fabrikaya çıkarılması

### Seçilen iz(ler)
- **Track 1 — en büyük / yakın-bütçe R dosyasından bütünleşik çıkarım** (öncelik #1).
  `R/server_handler_true_streaming.R` (681/18) repo genelindeki en büyük R dosyası ve
  küresel `MERGEN_TEST_MAX_FILE_LINES` pini idi. `sohbet_llm_akis` seam'inde tek paket.

### Özet ve gerekçe
Bu dosya, paylaşılan değişebilir `stream_env` üzerinde sıkıca bağlı iç closure'lardan
oluşan tek bir streaming durum makinesidir; closure'ları üst düzeye çıkarmak büyük bir
bağlam aktarımı gerektirir (yüksek churn, hassas yolda yüksek risk). Davranış-koruyan
TEK temiz çıkarım, `tracked_future_promise(..., globals = list(...))` içindeki ~35
satırlık **worker-export globals listesidir** — düz, bildirimsel, çoğunluğu global
sembol. Bu liste aynı zamanda CLAUDE.md-korumalı bir sözleşmedir (reasoning delta /
stop-file / model request override yardımcıları işçi tarafında görünür kalmalı).

Liste, yeni saf fabrika `mergen_true_streaming_worker_globals()`'a BİREBİR taşındı
(31 isim: 4 isteğe-özel arg + 25 yardımcı + `%||%` + `api_config`). İsteğe-özel 4
nesne argümandır; geri kalanı çağrı anında global ortamda çözülür. Golden kontrol:
stub'lı ortamda fabrika çıktısı orijinal liste isimleriyle aynı sırada birebir (31/31).

### Değişen dosyalar
**Kaynak**
- `R/helpers_llm_true_streaming_worker.R` (yeni, 62/1) — `mergen_true_streaming_worker_globals()`.
- `R/server_handler_true_streaming.R` — **681/18 → 655/18**; satır içi `globals = list(...)`
  yerine `globals = mergen_true_streaming_worker_globals(...)`.
- `R/config_source_manifest.R` — `server_handlers_send_message` bölümüne yeni dosya
  `server_handler_true_streaming.R`'den ÖNCE (9 → 10).
- `R/bootstrap_source_manifest.R` — kritik sıra kuralı:
  `helpers_llm_true_streaming_worker.R → server_handler_true_streaming.R`.
- `R/config_seam_registry.R` — `sohbet_llm_akis` guard_tests'e yeni split-contract testi (8 → 9).

**Test**
- `tests/testthat/test-true-streaming-worker-globals-contract.R` (yeni) — yapısal ayrım
  (fabrika yeni dosyada; handler delege eder; satır içi liste yok; manifest sırası) +
  davranış (31 isim, arg geçişi, CLAUDE.md-korumalı worker-export adları, `%||%`/`api_config`).
- `tests/testthat/test-sse-worker-export-contract.R` — globals sözleşmesi artık yeni
  sahip dosyada doğrulanır + handler delegasyon kontrolü.
- `tests/testthat/test-llm-reasoning-request-overrides.R` — `apply_model_request_overrides`
  globals kontrolü yeni sahip dosyaya yönlendirildi.
- `tests/testthat/test-source-manifest-sections-contract.R` — `server_handlers_send_message`
  n=9→10; toplam runtime 282→283.
- `tests/testthat/test-maintainability-ratchet.R` — küresel `MERGEN_TEST_MAX_FILE_LINES`
  681 → 678; bütçeler `server_handler_true_streaming.R` 660/18, helper 80/1.

**Dokümantasyon**
- `CLAUDE.md` (worker-export globals sözleşmesi 3 referans güncellendi),
  `docs/feature-ownership-map.md`, `docs/refactor-log.md`,
  `.ai/next-session-eliminate-weaknesses-prompt.md`.

### Önce / sonra
- Önce: `server_handler_true_streaming.R` 681/18 (küresel pin). Sonra: handler 655/18,
  helper 62/1. Skor 100/100; 800+ satır / 25+ fonksiyon = 0. Küresel en büyük dosya
  satırı **681 → 678** (yeni pin `module_admin_yanit_analizi_outputs.R`). Ratchet
  GEVŞETİLMEDİ; sıkılaştırıldı.

### Korunan davranış sözleşmeleri
- Globals listesi içeriği byte-birebir (31 isim, aynı sıra, golden doğrulama). Worker
  task_fn, promise zinciri, poll observer, finalize/abort, request-id, stop-file,
  reasoning recovery yolları DEĞİŞMEDİ. SSE/streaming davranışı aynı.
- DB/SSO/encoding/source-order/UX runtime sınırlarına dokunulmadı (saf yapısal relocate).

### Gerçekten çalıştırılan doğrulamalar (bu oturumda, Linux/cloud, R 4.6.0)
- Golden: stub'lı ortamda fabrika çıktısı = orijinal 31 isim (aynı sıra), arg geçişi TRUE.
- `Rscript tests/scripts/maintainability_report.R` → 100/100; handler 655/18; helper 62/1;
  en büyük dosya 681 → 678.
- `Rscript tests/scripts/parse_sanity_check.R` → OK (858 dosya).
- `Rscript tests/scripts/seam_doctor.R` → `SEAM_DOCTOR_RESULT: OK`.
- Odak testler 0 fail/0 warn/0 skip: yeni split-contract (3), sse-worker-export (2),
  source-manifest-sections (4), source-manifest-contract (17), global-source-manifest (6),
  maintainability-ratchet (22), seam-registry (6), seam-doctor (2),
  true-streaming-reset-ui (2), streaming-poll-lifecycle (5),
  llm-reasoning-request-overrides (6), production-contracts (10).
- `bash tools/ai_validate.sh full --boot-smoke` → **TAM**: app source smoke passed,
  **full testthat suite passed (159.4s)**, shiny boot passed, browser smoke SKIPPED;
  failed=0, skipped=0 (`artifacts/ai-validation/20260624-121349/summary.json`).

### Manuel QA (kullanıcı/VM tarafı)
- Düşünen bir modelle Akış modunda mesaj gönderin; canlı SSE akışının, reasoning
  panelinin, durdurma temizliğinin ve DB kalıcılığının eskisi gibi çalıştığını doğrulayın.

### Bilinen riskler / atlanan doğrulamalar
- VM/SSO/gerçek DB/SQL Server/gerçek tarayıcı/canlı LLM SSE kanıtı alınmadı (bulut
  oturumu). Saf yapısal relocate; globals byte-birebir korundu, ancak canlı SSE uçtan
  uca akış yalnızca VM/manuel tarayıcıda son kez kanıtlanır.
- Sıradaki adaylar: `R/module_file_manager.R` (677); frontend
  `www/js/deep_space_intro.js` (820) / `www/js/ai_expert_manager.js` (802/45).

---

## 2026-06-24 — Bilge Yolaç doküman ÖZETLEME orkestrasyonunun ayrı dosyaya çıkarılması

### Seçilen iz(ler)
- **Track 1 — yakın-bütçe R dosyasından bütünleşik (saf, verbatim) çıkarım**
  (öncelik #1). 2. en büyük R dosyası (`R/helpers_claude_code_documents.R`, 679/17,
  küresel 681 pin bandında). `bilge_yolac` seam'inde tek paket. (Aynı oturumda
  post-deploy smoke paketinden SONRA, kullanıcı "continue" yönlendirmesiyle.)

### Özet ve gerekçe
Keşif (maintainability 100/100, en büyük dosya 681 = `server_handler_true_streaming.R`;
seam doctor OK): `R/helpers_claude_code_documents.R` **679/17 ile 2. en büyük R
dosyasıydı** ve küresel pin bandındaydı. Dosya iki bütünleşik sorumluluğu
karıştırıyordu: (1) doküman BAĞLAM hazırlığı (manifest/inline-payload/prompt/
prepare-context) ve (2) doküman ÖZETLEME orkestrasyonu (detay seviyesi, özet
mesajları, yerel LLM ile özetleme, `dosya_aciklamalari.txt` yazımı).

Küresel pin'i (`server_handler_true_streaming.R` 681) düşürmek o dosyanın
bölünmesini gerektirir; ancak o dosya TEK büyük reaktif fonksiyondur (stream_env/
values/session üzerine kapanan iç closure'lar + worker globals listesi) ve canlı
SSE yolunda closure semantiğini değiştirir — yalnızca VM'de kanıtlanabilir, yüksek
riskli. Bu yüzden bu oturumda DÜŞÜK RİSKLİ, kanıtlanmış verbatim-taşıma deseni
seçildi: 4 üst-düzey özet fonksiyonu yeni `R/helpers_claude_code_document_summary.R`
dosyasına BAYT-BİREBİR taşındı (extraction byte-preserving bir R betiğiyle yapıldı,
531-533. satırlardaki tab/space karışımı korundu). Paylaşılan UTF-8 BOM yazıcı
`write_claude_code_utf8_bom_text_file()` documents.R'de KALDI (run_lifecycle de
`exists()` guard'ıyla kullanır). `summarize_..._with_local_llm` run_lifecycle
worker'ında OTOMATİK globals çözümüyle çalışır; sourced dosya değişmesi worker'ı
etkilemez (globaller çalışma zamanında globalenv'de çözülür).

### Değişen dosyalar
**Kaynak**
- `R/helpers_claude_code_document_summary.R` (yeni, 281/7) — `resolve_..._detail_level`,
  `write_..._summary_file`, `build_..._summary_messages`, `summarize_..._with_local_llm`.
- `R/helpers_claude_code_documents.R` — **679/17 → 407/10** (bağlam hazırlığı + paylaşılan
  BOM yazıcı kaldı).
- `R/config_source_manifest.R` — `claude_code_helpers` bölümüne summary dosyası
  documents'tan SONRA, run_lifecycle'dan ÖNCE eklendi.
- `R/bootstrap_source_manifest.R` — kritik sıra kuralları: documents → summary,
  summary → run_lifecycle.

**Test**
- `tests/testthat/test-claude-code-document-summary-refactor-contract.R` (yeni, 5 test) —
  yapısal ayrım + davranış (detay seviyesi, mesaj rolleri) + manifest sırası +
  documents.R'nin özet fonksiyonlarını tanımlamaması + BOM yazıcının documents.R'de
  kalması + sıkı bütçe (summary < 320/≤9, documents < 430/≤12).
- Üç davranış testi summary dosyasını da source eder: `test-claude-code-detail-level-behavior.R`,
  `test-claude-code-document-builders-behavior.R`, `test-claude-code-document-orchestration-behavior.R`.
- `tests/testthat/test-source-manifest-sections-contract.R` — `claude_code_helpers`
  n=26→27, toplam runtime 281→282.

**Dokümantasyon**
- `CLAUDE.md` (doküman modülerleştirme sözleşmesi + iki Group yükleme listesi),
  `docs/feature-ownership-map.md` (bilge_yolac + eskimiş 679 notları), `docs/refactor-log.md`,
  `.ai/next-session-eliminate-weaknesses-prompt.md`.

### Önce / sonra karmaşıklık notları
- Önce: documents.R 679/17 (2. en büyük, pin bandında).
- Sonra: documents.R 407/10, summary 281/7. Skor 100/100; 800+ satır / 25+ fonksiyon = 0;
  **küresel en büyük dosya 681 DEĞİŞMEDİ** (`server_handler_true_streaming.R` pin'i; bu
  paket o dosyaya dokunmadı). documents.R pin bandından çıktı; yeni split-contract
  bütçesiyle kilitlendi. Ratchet GEVŞETİLMEDİ.

### Korunan davranış sözleşmeleri
- 4 fonksiyon byte-birebir taşındı (R betiğiyle aralık kopyalama; tab/space korundu).
- Paylaşılan BOM yazıcı documents.R'de kaldı; summary dosyası ondan SONRA yüklenir,
  `write_..._summary_file` BOM yazıcıyı çağrı anında çözer.
- `summarize_...` worker yolu (run_lifecycle `tracked_future_promise` otomatik globals)
  değişmedi. Extractor split sözleşmesi (documents.R extractor fonksiyonlarını
  tanımlamaz + extractor fallback referansı) korundu.
- Encoding/DB/SSO/UX runtime sınırlarına dokunulmadı (saf yapısal relocate + manifest).

### Gerçekten çalıştırılan doğrulamalar (bu oturumda, Linux/cloud, R 4.6.0)
- `Rscript tests/scripts/parse_sanity_check.R` → OK (856 dosya).
- Odak testler (test_dir filtre, 0 fail/0 warn/0 skip): yeni split-contract (5),
  detail-level-behavior (4), document-builders-behavior (9), document-orchestration-behavior (15),
  extractors-refactor-contract (4), extractors-maintainability-contract (2),
  document-download-link-encoding (3), source-manifest-contract (11),
  source-manifest-sections-contract (4), global-source-manifest-contract (6).
- `Rscript tests/scripts/maintainability_report.R` → 100/100, en büyük dosya 681
  (değişmedi), documents.R 407.
- `Rscript tests/scripts/seam_doctor.R` → `SEAM_DOCTOR_RESULT: OK`; `bilge_yolac`
  runtime-dosya 33 → 34 (yeni dosya claude_code_helpers'ta, bilge_yolac sahipli; orphan yok).
- `bash tools/ai_validate.sh full --boot-smoke` → **TAM**: app source smoke passed,
  **full testthat suite passed (159.0s)**, shiny boot passed, browser smoke SKIPPED
  (tarayıcı yok); failed=0, skipped=0 (`artifacts/ai-validation/20260624-112452/summary.json`).

### Manuel QA (kullanıcı/VM tarafı)
- Bilge Yolaç'ta bir doküman (PDF/DOCX/XLSX) özetleme akışını çalıştırın; özet metnin
  üretildiğini, `dosya_aciklamalari.txt`'nin UTF-8 BOM ile yazıldığını ve indirme
  kartının göründüğünü doğrulayın (worker yolu otomatik globals).

### Bilinen riskler / atlanan doğrulamalar
- VM/SSO/gerçek CLI/gerçek tarayıcı kanıtı alınmadı (bulut oturumu). Değişiklik saf
  yapısal verbatim-relocate'tir; doküman özet worker akışı yalnızca Windows VM'de canlı
  kanıtlanır.
- Küresel pin (`server_handler_true_streaming.R` 681) DEĞİŞMEDİ; bu dosya canlı SSE
  closure'ları içerdiği için bilinçli olarak bu oturumda bölünmedi (VM-only kanıt + yüksek risk).
- Sıradaki paket adayları: `R/module_file_manager.R` (677, 725/14 dosya bütçesi),
  `R/helpers_claude_code_process.R` (665/20, fonksiyon-sayısı baskısı); frontend
  `www/js/ai_expert_manager.js` (802/45, bütçe içinde — böl-sonra-sıkılaştır).

---

## 2026-06-24 — Dağıtım sonrası duman testi kanıt artifact akışının tamamlanması

### Seçilen iz(ler)
- **Track 3 — post-deploy smoke artifact ailesi**: dokümante açık taşıma kalemi
  ("üretici henüz yok"). Üretici/okuyucu/UI entegrasyonu eksikti; bu paket onu
  uçtan uca tamamladı. `destek_yonetici_saglik` seam'inde tek, bütünleşik paket.
- **Track 6 — eskimiş "sıradaki hedef" notlarının güncellenmesi**: feature-ownership
  ve handoff'ta "post-deploy smoke artifact ailesi (üretici henüz yok)" notu
  yenilendi.

### Özet ve gerekçe
Keşif (maintainability 100/100, en büyük dosya 681; seam doctor OK; frontend
bütçe içinde): `tests/scripts/run_post_deploy_smoke.R` ve saf değerlendirici
`tests/scripts/helpers_post_deploy_smoke.R` zaten vardı, ancak kapı YALNIZCA
konsola yazıp `stop()` ediyordu — **makinece okunabilir artifact üretmiyordu** ve
`R/helpers_release_evidence.R` içinde VM evidence + ai-validation okuyucuları
varken **post-deploy smoke okuyucusu yoktu**. Bu, talimatların #3 hedefindeki
"artifact producer/reader integration is incomplete" boşluğuydu.

Paket, repoda zaten kanıtlanmış VM/ai evidence desenini (üretici → secret-safe
`artifacts/<aile>/<ts>/<dosya>.json` → saf okuyucu → Sistem Durumu UI) birebir
post-deploy smoke'a uyguladı. Değerlendirici sonucundan kayıt kurma mantığı SAF,
izole test edilebilir bir yardımcıya (`mergen_post_deploy_smoke_artifact_record`)
çıkarıldı; kapı yalnızca dosyaya yazar (git'i en iyi çaba toplar, `stop`'tan ÖNCE
yazar → `fail`/`degraded` koşumlar da iz bırakır). `does_prove`/`does_not_prove`
dürüstlük alanları zorunlu kılındı.

### Değişen dosyalar
**Kaynak/script**
- `tests/scripts/helpers_post_deploy_smoke.R` — yeni SAF üretici
  `mergen_post_deploy_smoke_artifact_record()` (kendi içinde küçük yerel
  yardımcılarla; standalone source edilebilir, `%||%` kullanmaz).
- `tests/scripts/run_post_deploy_smoke.R` — `stop`'tan önce secret-safe artifact
  yazar: `artifacts/post-deploy-smoke/<timestamp>/post-deploy-smoke.json`
  (jsonlite + redaktör + `tryCatch` → artifact hatası kapıyı çökertmez).
- `R/helpers_release_evidence.R` — yeni okuyucu
  `release_evidence_post_deploy_smoke_summary()` (beyaz-listeli alanlar, not_found
  dürüstlüğü) + `release_evidence_overview()`'a `post_deploy_smoke` eklendi.
  Fonksiyon sayısı 21 → 22 (savunmacı `tryCatch(error=function)` closure'ları
  bilinçle kullanılmadı; ayrıştırılmış JSON listesinde `$` erişimi hata vermez —
  küresel 24-fonksiyon tavanından uzak kalındı).
- `R/module_health_release.R` — yeni `.health_release_post_deploy_card()` + Sistem
  Durumu > Doğrulama Kanıtı sekmesine "Dağıtım Sonrası Duman Testi" kartı + metrik
  kutusu (5 → 6 fonksiyon). Bulunamayan kanıt "Bulunamadı" gösterir; artifact yolu
  UI'ye taşınmaz (secret-safe).

**Test**
- `tests/testthat/test-post-deploy-smoke-contract.R` — `*_artifact_record()` davranış
  testleri (pass/fail/UTC default; counts isimli int listesi; does_prove/
  does_not_prove zorunlu) + kapı betiği artifact üretim token sözleşmesi.
- `tests/testthat/test-release-evidence-behavior.R` — `.makePostDeploySmokeFixture()`
  + okuyucu davranışı (en-yeni seçim, eski-koşu kritik bozulma, not_found) +
  overview'da `post_deploy_smoke` anahtarı.
- `tests/testthat/test-health-release-ui-behavior.R` — fixture'a `post_deploy_smoke`
  eklendi; kart render + secret-safe (artifact yolu render edilmez) + not_found.

**Dokümantasyon**
- `RUNBOOK.md` (§10), `docs/feature-ownership-map.md` (destek_yonetici_saglik —
  "üretici yok" notu kaldırıldı), `docs/architecture-map.md` (artifact ailesi satırı),
  `docs/technical-reference.md` (yeni alt bölüm), `AGENTS.md` (operasyonel not),
  `docs/refactor-log.md` (bu giriş), `.ai/next-session-eliminate-weaknesses-prompt.md`.

### Önce / sonra
- Önce: post-deploy smoke kapısı artifact üretmiyordu; okuyucu/UI yoktu (açık boşluk).
- Sonra: uçtan uca akış (üretici → secret-safe JSON → saf okuyucu → Sistem Durumu
  UI), `does_prove`/`does_not_prove` dürüstlük alanlarıyla. Maintainability 100/100
  korundu (en büyük dosya 681, en yüksek fonksiyon 24; helpers_release_evidence 22,
  module_health_release 6 — tavan altında). Ratchet GEVŞETİLMEDİ.

### Korunan davranış sözleşmeleri
- `mergen_post_deploy_smoke_evaluate()` davranışı DEĞİŞMEDİ (saf değerlendirici).
- Kapı `stop`-on-critical sözleşmesi korundu; artifact yazımı `stop`'tan önce ve
  `tryCatch` ile sarmalı (kanıt yazılamazsa bile dürüst başarısızlık gizlenmez).
- Secret-safe sınır: yalnızca kontrol kimlikleri + sayaçlar; ham log/ortam/secret
  yok; yazımdan önce redaktör. UI artifact yolunu render etmez. not_found dürüstlüğü.
- Encoding/DB/SSO/source-order/UX runtime sınırlarına dokunulmadı (additive evidence
  altyapısı + bir health UI kartı).

### Gerçekten çalıştırılan doğrulamalar (bu oturumda, Linux/cloud, R 4.6.0)
- Uçtan uca mantık probu: evaluate → record → toJSON → write → okuyucu geri-oku;
  pass/degraded/fail/not_found yolları doğru.
- Odak testler (test_dir filtre, 0 fail/0 warn/0 skip): post-deploy-smoke-contract,
  release-evidence-behavior (17), health-release-ui-behavior, maintainability-ratchet
  (22), e2e-health-dashboard-regression (5).
- `Rscript tests/scripts/maintainability_report.R` → 100/100, max 681, max fn 24.
- `Rscript tests/scripts/seam_doctor.R` → `SEAM_DOCTOR_RESULT: OK` (yapısal drift yok).
- `Rscript tests/scripts/parse_sanity_check.R` → OK (854 dosya).
- `bash tools/ai_validate.sh quick` → TAM (failed=0, skipped=0, app_source_smoke=passed;
  `artifacts/ai-validation/20260624-102241/summary.json`).
- `bash tools/ai_validate.sh full --boot-smoke` → **TAM**: app source smoke passed,
  **full testthat suite passed (181.6s)**, shiny boot passed, browser smoke SKIPPED
  (tarayıcı yok); failed=0, skipped=0
  (`artifacts/ai-validation/20260624-102401/summary.json`). NOT: `logger` kurulu +
  placeholder env ile; önceki oturumların "logging testi tıkayıcısı" bu koşumda
  tekrarlanmadı (ortam-bootstrap kaynaklıydı, test-izolasyon hatası değil).

### Manuel QA (kullanıcı/VM tarafı)
- VM'de uygulama ayaktayken `Rscript tests/scripts/run_post_deploy_smoke.R` çalıştırın;
  `artifacts/post-deploy-smoke/<ts>/post-deploy-smoke.json` üretildiğini ve içinde
  ham secret/ortam değeri OLMADIĞINI doğrulayın.
- Sistem Durumu > Doğrulama Kanıtı sekmesinde "Dağıtım Sonrası Duman Testi" kartının
  ve metrik kutusunun en son koşumu gösterdiğini; kanıt yokken "Bulunamadı" dediğini
  doğrulayın.

### Bilinen riskler / atlanan doğrulamalar
- VM/SSO/gerçek DB/SQL Server/gerçek tarayıcı kanıtı alınmadı (bulut oturumu). Gerçek
  `post-deploy-smoke.json` yalnızca uygulama ayaktayken (VM) üretilir; kapı betiğinin
  app-boot gerektiren artifact yazımı bulutta canlı koşulmadı (saf üretici + okuyucu
  uçtan uca probu ve token sözleşmesiyle kanıtlandı).
- Bu artifact anlık sağlık fotoğrafıdır; yük/eşzamanlılık/uzun-süre/VM/SSO/SQL Server
  Türkçe kodlama kanıtı DEĞİLDİR.
- Sıradaki paket adayları: `R/server_handler_true_streaming.R` (681, küresel pin),
  `R/helpers_claude_code_documents.R` (679), `R/module_file_manager.R` (677); frontend
  `www/js/deep_space_intro.js` (820) / `www/js/ai_expert_manager.js` (802/45).

### Codex review düzeltmeleri (aynı oturum, 3 × P2)
- **Serileştirilmiş JSON redaksiyonu artifact'ı bozabilir (P2):** `.smoke_redact()`
  serileştirilmiş JSON üzerinde `gsub(fixed)` çalıştırdığı için kısa/ortak alt-dize
  veya JSON noktalama içeren bir secret env değeri JSON syntax'ını ezip dosyayı
  GEÇERSİZ kılabilirdi (okuyucu NULL döner → panel koşumu "yok" sanar). Yeni saf
  yardımcı `mergen_post_deploy_smoke_redact_json_safe()` redaksiyonu yalnızca
  GEÇERLİ JSON üretiyorsa uygular; aksi halde zaten secret-safe olan orijinali
  korur. `run_post_deploy_smoke.R` artık bu güvenli yazıcıyı kullanır.
- **`should_fail` UI'de kritik gösterilmiyordu (P2):** gate hiç kontrol toplayamazsa
  değerlendirici `overall="unknown"` ama `should_fail=TRUE` döner (`reason="no_checks"`).
  Önceki UI yalnızca `overall`'a bakıp nötr "Bilinmiyor" gösteriyor, bloklamayı
  gizliyordu. `R/module_health_release.R` artık `should_fail=TRUE` olduğunda hem
  metrik kutusunu hem kart pill'ini "Başarısız" + `health-status-critical` gösterir.
- **`does_prove` çalışan-servis kanıtını abartıyordu (P2):** kapı `MERGEN_RUN_APP=false`
  ile çalışır (Shiny servisi başlatılmaz, app URL probe edilmez). `does_prove` artık
  yalnızca in-process / güvenli-boot sağlık kontrollerini iddia eder; `does_not_prove`
  "dağıtılan Shiny servisinin ayakta olduğunu KANITLAMAZ (app URL probe edilmez)"
  uyarısını ekler.
- **Eklenen testler:** `test-post-deploy-smoke-contract.R` (redact-safe yardımcı:
  geçerli redaksiyon uygulanır / bozan redaksiyon orijinale düşer / NULL redaktör;
  + does_prove/does_not_prove dar iddia) ve `test-health-release-ui-behavior.R`
  (no_checks should_fail → kritik "Başarısız"). Doğrulama: 3 odak test dosyası
  0 fail/0 warn/0 skip (16/17/11); `ai_validate quick` TAM (failed=0, skipped=0,
  app_source_smoke=passed; `artifacts/ai-validation/20260624-120029/summary.json`).
  Maintainability etkilenmez (değişiklikler tests/scripts + bir health UI modülü).

#### Codex review 2. tur (2 × P2 — 1. turu sertleştirir)
- **Redaksiyon şemayı bozabilir, yalnızca JSON söz dizimi yetmez (P2):** 1. turdaki
  `mergen_post_deploy_smoke_redact_json_safe()` yalnızca redaksiyon-SONRASI JSON'un
  geçerli olduğunu denetliyordu. Ancak `ok` gibi bir secret değeri serileştirilmiş
  JSON'da `counts.ok` ANAHTARINI `<hidden>` ile ezse JSON yine geçerli kalır ve
  okuyucu YANLIŞ "sıfır geçen kontrol" raporlar. Çözüm: json-metin yaklaşımı
  KALDIRILDI; yerine `mergen_post_deploy_smoke_redact_record()` geldi — redaksiyon
  SERİLEŞTİRMEDEN ÖNCE yalnızca yapısal string DEĞERLERE uygulanır; liste anahtarları,
  sayılar ve sayaçlar (counts) hiç dokunulmaz. Böylece şema asla bozulmaz ve toJSON
  her zaman geçerli JSON üretir. `run_post_deploy_smoke.R` artık kaydı serileştirmeden
  önce bu redaktörden geçirir.
- **`degraded` kart pill'inde tanınmıyordu (P2):** `.health_release_pill()` `degraded`
  durumunu tanımayıp kartta nötr/ham "degraded" gösteriyordu (metrik kutusu ise doğru
  "Kısmi"/uyarı gösteriyordu → tutarsız). Pill `degraded`/`warning` → `warning` rengi +
  "Kısmi"/"Uyarı" etiketine genişletildi; kart ve metrik kutusu artık tutarlı.
- **Test güncellemeleri:** `test-post-deploy-smoke-contract.R` redaksiyon testi
  şema-koruyan kayıt redaksiyonuna çevrildi (counts anahtarı/sayısı korunur; `ok`
  secret token simülasyonu); `test-health-release-ui-behavior.R` degraded kart pill'inin
  `health-status-warning` gösterdiğini ve ham "degraded" göstermediğini doğrular.
  Doğrulama: 3 odak test 0 fail/warn/skip (16/17/11); `ai_validate quick` TAM
  (`artifacts/ai-validation/20260624-153221/summary.json`).

#### Codex review 3. tur (2 × P2 — 2. turu sertleştirir)
- **Durum enum'ları redaksiyonda korunmalı (P2):** 2. tur yalnızca string DEĞERLERİ
  redakte ediyordu (anahtarlar/sayaçlar korunuyordu). Ancak `overall` bir durum
  ENUM'udur; secret değeri `pass`/`degraded` gibi kısa bir enum'a denk gelseydi
  `.smoke_redact` `record$overall`'ı serileştirmeden önce ezer, JSON geçerli kalır,
  `should_fail` false olur ve panel GEÇEN/degraded kapıyı nötr/unknown gösterirdi.
  Çözüm: `mergen_post_deploy_smoke_redact_record()` artık walk SONRASI
  `overall`/`reason`/`gate`/`validation_execution_status` enum/kimlik alanlarını
  orijinalden geri yükler (bu alanlar tasarımca asla secret içermez).
- **Erken çıkışlarda başarısızlık artifact'ı yazılmalı (P2):** kapı; zorunlu env
  eksik / `app.R` source başarısız / `health_collect_checks()` yok durumlarında
  artifact bloğuna ULAŞMADAN stop ediyordu → o başarısızlık modlarında
  `post-deploy-smoke.json` yazılmıyor, panel koşumu `not_found` (hiç koşmamış gibi)
  sanıyordu. Çözüm: helper'lar ÖNCE (app.R'den önce) yüklenir; `.smoke_redact`,
  `.smoke_write_artifact`, `.smoke_fail_and_stop` ve `critical_ids`/`fail_on_unknown`
  erken tanımlanır; yeni saf `mergen_post_deploy_smoke_failure_result(reason)` ile
  3 erken çıkış (missing_required_env / app_boot_failed / health_collect_checks_missing)
  stop'tan ÖNCE bir `overall="fail"` artifact'ı yazar. `app.R` source'u tryCatch'e alındı.
- **Test güncellemeleri:** `test-post-deploy-smoke-contract.R` enum-koruma testi
  (degraded/fail enum'ları redaksiyon sonrası korunur) + failure-result testi
  (fail kaydı + boş/NA neden fallback) + kapı sözleşmesine
  `mergen_post_deploy_smoke_failure_result` grep'i eklendi. Doğrulama: 3 odak test
  0 fail/warn/skip (18/17/11); `ai_validate quick` TAM
  (`artifacts/ai-validation/20260624-155351/summary.json`).

#### Codex review 4. tur (1 × P1 — kritik kapı doğruluğu)
- **Sağlık kontrolleri SATIR bazında değerlendirilmeli (P1):**
  `health_collect_checks()` `do.call(rbind, ...)` ile bir DATA FRAME döndürür
  (satır başına bir kontrol). `mergen_post_deploy_smoke_evaluate()` ise
  `for (chk in checks)` ile gezerken bir veri çerçevesinde SÜTUNLARI dolaşıyordu;
  atomik sütunlar `is.list(chk)` dalını atladığı için tüm id'ler boş, tüm durumlar
  "unknown" kalıyordu. Sonuç: gerçek bir `db.primary`/`app.boot` "critical" sonucu
  `critical_failures`'a hiç eklenmiyor, `should_fail` false kalıyor ve kapı kritik
  kontrole rağmen GEÇİYORDU. Çözüm: değerlendirici, boş kontrolü ve döngüden ÖNCE
  veri çerçevesini satır-kayıtlarına çevirir
  (`lapply(seq_len(nrow), function(i) as.list(checks[i, , drop = FALSE]))`);
  `is.data.frame` `is.list`'TEN önce kontrol edilir (veri çerçevesi de bir listedir).
  Liste-kayıt yolu (mevcut testler) değişmez.
- **Test:** `test-post-deploy-smoke-contract.R` data-frame satır-değerlendirme
  testi (kritik `db.primary` satırı `should_fail`/`fail`/`critical_failures`
  tetikler; tümü-ok → pass; 0 satır → no_checks). Doğrulama: 3 odak test
  0 fail/warn/skip (19/17/11); `ai_validate quick` TAM
  (`artifacts/ai-validation/20260624-161202/summary.json`).

---

## 2026-06-20 — ServerRuntimeContext SSO auth-ready / yenilenebilir modül wiring katmanının ayrılması

### Seçilen iz(ler)
- **Track 1 — en büyük / yakın-bütçe R dosyasından bütünleşik (kohezif) katman
  çıkarımı** (öncelik #1; dokümante #2 sıradaki hedef, aynı oturumda config_ui_assets
  paketinden sonra). `shiny_calisma_zamani` seam'inde tek paket.
- **Track 6 — eskimiş "sıradaki hedef" notlarının güncellenmesi**: feature-ownership'te
  `server_runtime_context.R` (687) sıradaki hedef gösteren üç not yenilendi.

### Özet ve gerekçe
Önceki paket (`config_ui_assets.R` bölünmesi) sonrası `R/server_runtime_context.R`
repo genelindeki **en büyük R dosyası oldu (687/17)** ve küresel
`MERGEN_TEST_MAX_FILE_LINES` bütçesini (687) kilitliyordu. Dosya; context init/attach/
require yardımcılarını, modül kayıt yardımcılarını VE SSO sonrası (post-auth) +
yenilenebilir modül wiring katmanını karıştırıyordu. Talimatların açıkça önerdiği
kohezif çıkarım, "auth-ready/refreshable-module helpers" idi.

Üç fonksiyon — `serverRuntimeOnSsoAuthReady()`,
`serverRuntimeRefreshModuleOnSsoAuthReady()`, `serverRuntimeAttachRefreshableModule()` —
yeni `R/server_runtime_auth_ready.R` dosyasına BİREBİR taşındı. Bunlar context'in
modül kayıt yardımcılarını (`serverRuntimeAttachModule/GetModule/ExposeSessionData`)
ve düşük seviyeli sözleşme yardımcılarını ÇAĞRI ANINDA kullanır, bu yüzden manifestte
context'ten SONRA, function_slot'tan ÖNCE yüklenir. SSO zamanlama davranışı
(ignoreInit/once/fail-fast, immediate-ready yolu, yerel-mod no-op) korundu.

### Değişen dosyalar
**Kaynak**
- `R/server_runtime_auth_ready.R` (yeni, 242/4) — üç wiring fonksiyonu + izole
  test/debug için WD-bağımsız yedek yükleme (context yoksa onu yükler; bu, repo'nun
  context.R'deki blessed bootstrap deseninin aynısıdır).
- `R/server_runtime_context.R` — **687/17 → 503/13** (context init/attach/require +
  modül kayıt yardımcıları; header üç fonksiyonun yeni konumunu işaret eder).
- `R/config_source_manifest.R` — `server_init_runtime` bölümüne yeni dosya
  context'ten SONRA, function_slot'tan ÖNCE eklendi (13 → 14).
- `R/bootstrap_source_manifest.R` — kritik sıra kuralları:
  `server_runtime_context.R → server_runtime_auth_ready.R → server_runtime_function_slot.R`.
- `R/config_seam_registry.R` — `shiny_calisma_zamani` guard_tests listesine yeni
  split-contract testi eklendi (6 → 7).

**Test**
- `tests/testthat/test-server-runtime-auth-ready-split-contract.R` (yeni, 33 assertion)
  — yapısal ayrım (fonksiyonlar yeni dosyada; context'te inline yok; manifest sırası)
  + odaklı davranış (yerel-mod no-op, SSO ready-now immediate callback, attach+expose,
  SSO modunda eksik-modül reddi).
- Üç fonksiyonu çalıştıran testler yeni dosyayı da kaynak alacak şekilde güncellendi:
  `test-server-runtime-context.R`, `test-e2e-sso-identity-readiness-regression.R`,
  `test-server-module-wiring-chat-engine.R`, `test-server-module-wiring-runtime-bindings.R`,
  `test-server-core-interaction-runtime.R`; `test-production-contracts.R` parse listesine eklendi.
- `tests/testthat/test-source-manifest-sections-contract.R` — `server_init_runtime`
  n=13→14; toplam runtime 279→280.
- `tests/testthat/test-maintainability-ratchet.R` — küresel
  `MERGEN_TEST_MAX_FILE_LINES` 687 → 681; bütçeler `server_runtime_context.R` 540/15,
  `server_runtime_auth_ready.R` 290/6.

**Dokümantasyon**
- `CLAUDE.md`, `docs/feature-ownership-map.md`, `docs/technical-reference.md`,
  `docs/refactor-log.md`, `.ai/next-session-eliminate-weaknesses-prompt.md`.
  (`docs/architecture-map.md` değişmedi: yeni dosya mevcut `server_init_runtime`
  bölümü / `shiny_calisma_zamani` seam tanımı içinde kalıyor.)

### Önce / sonra karmaşıklık notları
- Önce: `server_runtime_context.R` 687/17 (repo genelinde en büyük; küresel bütçede).
- Sonra: context 503/13, auth_ready 242/4. Skor 100/100; 800+ satır / 25+ fonksiyon = 0.
  **Küresel en büyük dosya satırı 687 → 681** (yeni en büyük
  `server_handler_true_streaming.R`). Küresel `MERGEN_TEST_MAX_FILE_LINES` 687 → 681.

### Korunan davranış sözleşmeleri
- (context + auth_ready) birlikte yüklendiğinde fonksiyon kümesi ve HER fonksiyonun
  gövdesi HEAD context.R ile BİREBİR aynı (24 fonksiyon, 0 gövde farkı — `deparse`
  karşılaştırması). SSO immediate-ready / observer-fired yolları aynı
  `.server_runtime_invoke_auth_ready_callback()` üzerinden geçer; yerel-mod no-op
  korundu; ignoreInit/once/fail-fast aynı.
- DB/SSO/encoding/source-order/UX runtime sözleşmelerine dokunulmadı (saf yapısal
  relocate).

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- Altın eşdeğerlik: HEAD context vs (yeni context + auth_ready) → fonksiyon kümesi
  identical, 0 gövde farkı. Boot sonrası iki dosyanın fonksiyonları da global'de mevcut.
- `Rscript tests/scripts/maintainability_report.R` → skor 100/100; en büyük dosya
  687 → 681; context 503/13, auth_ready 242/4.
- `Rscript tests/scripts/seam_doctor.R` → `SEAM_DOCTOR_RESULT: OK`; `shiny_calisma_zamani`
  runtime-dosya 33 → 34, guard-test 6 → 7.
- `Rscript tests/scripts/parse_sanity_check.R` → OK (851 dosya).
- Odak testler tek tek geçti (0 FAIL / 0 WARN / 0 SKIP): yeni split-contract (33),
  server-runtime-context (57), server-runtime-context-accessors (6),
  server-core-interaction-runtime (25), server-module-wiring-chat-engine (14),
  server-module-wiring-contract (5), server-module-wiring-runtime-bindings (31),
  e2e-sso-identity-readiness (22), source-manifest-sections (154),
  source-manifest-contract (165), global-source-manifest (12), seam-registry (12),
  maintainability-ratchet (243), production-contracts (21).
- `bash tools/ai_validate.sh full --boot-smoke` → **tam geçti**; app source smoke
  PASSED, **full testthat suite PASSED (181.2s)**, shiny boot smoke PASSED, browser
  smoke SKIPPED (tarayıcı yok); `failed_steps: 0`, `skipped_steps: 0`
  (`artifacts/ai-validation/20260620-170730/summary.json`). NOT: bu bulut oturumunda
  `logger` paketi kurularak ve placeholder env değişkenleri verilerek koşuldu.

### Manuel QA (kullanıcı/VM tarafı)
- Windows VM'de SSO açıkken giriş yapın; Dosya Yönetimi kalıcı dosyalarının ve Görsel
  Galerisi'nin SSO kimlik hazır olduktan SONRA (kullanıcı id'si 0 değilken) bir kez
  yenilendiğini doğrulayın. Yerel (SSO kapalı) modda davranışın değişmediğini doğrulayın.

### Bilinen riskler / atlanan doğrulamalar
- VM/SSO/gerçek DB/SQL Server/gerçek tarayıcı kanıtı alınmadı (bulut oturumu).
  Değişiklik saf yapısal relocate'tir; fonksiyon gövdeleri byte-birebir korundu, ancak
  gerçek SSO post-auth yenileme zamanlaması yalnızca Windows VM'de son kez kanıtlanır.
- Sıradaki paket adayları: `R/server_handler_true_streaming.R` (681),
  `R/helpers_claude_code_documents.R` (679), `R/module_file_manager.R` (677); frontend
  `www/js/deep_space_intro.js` (820) / `www/js/ai_expert_manager.js` (802).

---

## 2026-06-20 — UI varlık manifestinin VERİ / DOĞRULAYICI / RENDER olarak bölünmesi

### Seçilen iz(ler)
- **Track 1 — en büyük / yakın-bütçe R dosyasından bütünleşik (saf) çıkarım**
  (öncelik #1; dokümante #1 sıradaki hedef). `frontend_varlik` seam'inde tek paket.
- **Track 6 — eskimiş "sıradaki hedef" notlarının güncellenmesi**: feature-ownership
  ve handoff'ta `config_ui_assets.R` (690) sıradaki hedef gösteren notlar yenilendi.

### Özet ve gerekçe
Keşif raporu (maintainability 100/100; seam doctor OK): `R/config_ui_assets.R`
repo genelindeki **en büyük R dosyasıydı (690/17)** ve küresel
`MERGEN_TEST_MAX_FILE_LINES` bütçesini (690) kilitliyordu. Dosya tek başına
varlık manifesti VERİSİNİ (CSS/JS grupları, ertelenmiş grup listesi, render planı,
JS/CSS sıra kuralları), SAF çözümleyici/doğrulayıcı fonksiyonlarını
(`ui_asset_all_css/js`, sıra/render planı doğrulaması) ve htmltools etiket render
katmanını (`ui_asset_tags` vb.) karıştırıyordu.

Repoda zaten kanıtlanmış bir desen vardı: `config_ui_asset_zones.R` (VERİ) +
`config_ui_asset_zone_validators.R` (DOĞRULAYICI). Aynı desen birebir uygulandı:
manifest VERİSİ tek sahip olarak `config_ui_assets.R`'de kaldı, çözümleyici/
doğrulayıcılar `config_ui_asset_validators.R`'ye, etiket render katmanı
`config_ui_asset_tags.R`'ye taşındı. Tüm fonksiyonlar veriyi ÇAĞRI ANINDA çözdüğü
için (tembel değerlendirme), runtime davranışı değişmez. Bölme öncesi/sonrası
TÜM çıktılar altın referansla doğrulandı: **byte-birebir aynı**
(`ui_asset_all_css/js`, sıra kuralları, render planı, ertelenmiş gruplar ve tam
`ui_asset_tags()` HTML md5 `11c977dd…` — `identical()` TRUE; HEAD vs çalışma ağacı
da birebir aynı).

### Değişen dosyalar
**Kaynak**
- `R/config_ui_asset_validators.R` (yeni, 253/11) — `ui_asset_render_plan_groups`,
  `ui_asset_render_plan_deferred`, `ui_asset_validate_js_render_plan`,
  `ui_asset_all_css`, `ui_asset_all_js`, `ui_asset_deferred_js_paths`,
  `ui_asset_validate_css_order`, `ui_asset_validate_js_order`,
  `ui_asset_duplicate_paths`, `ui_asset_public_root`, `ui_asset_validate`.
- `R/config_ui_asset_tags.R` (yeni, 59/5) — `ui_asset_css_tag`,
  `ui_asset_script_tag`, `ui_asset_css_tags`, `ui_asset_js_tags`, `ui_asset_tags`.
- `R/config_ui_assets.R` — **690/17 → 425/1** (SADECE VERİ + `ui_asset_flatten_groups`
  düzleştirme yardımcısı; sıranın TEK sahibi).
- `R/config_source_manifest.R` — `config_ui_assets` bölümüne iki yeni dosya
  `config_ui_assets.R`'den SONRA, `config_ui_asset_zones.R`'den ÖNCE eklendi (3 → 5).
- `R/config_seam_registry.R` — `frontend_varlik` guard_tests listesine yeni
  split-contract testi eklendi (8 → 9).
- `tests/scripts/seam_doctor.R`, `tests/scripts/frontend_maintainability_report.R` —
  çözümleyici/etiket fonksiyonları (ui_asset_all_css/js) artık ayrı dosyalarda
  olduğundan üç dosyayı da kaynak alır.

**Test**
- `tests/testthat/test-ui-asset-config-split-contract.R` (yeni, 100 assertion) —
  yapısal ayrım (fonksiyonlar yeni dosyalarda; veri dosyasında inline fonksiyon
  yok; manifest sırası VERİ → DOĞRULAYICI → RENDER) + bölme sonrası
  `ui_asset_validate()`/`ui_asset_tags()` davranış doğrulaması.
- Çözümleyici/etiket fonksiyonu çalıştıran testlerin source yardımcıları üç dosyayı
  da yükleyecek şekilde güncellendi: `test-ui-asset-manifest-contract.R`,
  `test-config-ui-assets-helpers-behavior.R`, `test-ui-asset-tag-builders-behavior.R`,
  `test-streaming-markdown-safety-contract.R`, `test-ui-asset-zones-contract.R`,
  `test-seam-registry-contract.R`, `test-ui-asset-zone-validators-split-contract.R`.
- `tests/testthat/test-source-manifest-sections-contract.R` — `config_ui_assets`
  n=3→5; toplam runtime 277→279 bilinçli güncellendi.
- `tests/testthat/test-maintainability-ratchet.R` — küresel
  `MERGEN_TEST_MAX_FILE_LINES` 690 → 687 sıkılaştırıldı; üç dosya için bütçe:
  `config_ui_assets.R` 470/2, `config_ui_asset_validators.R` 300/13,
  `config_ui_asset_tags.R` 110/8.

**Dokümantasyon**
- `CLAUDE.md`, `docs/feature-ownership-map.md`, `docs/architecture-map.md`,
  `docs/technical-reference.md`, `docs/refactor-log.md`,
  `.ai/next-session-eliminate-weaknesses-prompt.md`.

### Önce / sonra karmaşıklık notları
- Önce: `config_ui_assets.R` 690/17 (repo genelinde en büyük; küresel bütçede).
- Sonra: VERİ 425/1, validators 253/11, tags 59/5. Skor 100/100; 800+ satır /
  25+ fonksiyon = 0. **Küresel en büyük dosya satırı 690 → 687** (yeni en büyük
  `server_runtime_context.R`, değişmedi). Küresel `MERGEN_TEST_MAX_FILE_LINES`
  690 → 687.

### Korunan davranış sözleşmeleri
- Tüm CSS/JS yolları, sıra kuralları (CSS + JS), render planı, ertelenmiş gruplar
  ve tam `ui_asset_tags()` HTML çıktısı byte-birebir korundu (altın md5 + HEAD
  karşılaştırması). Yükleme sırasının TEK sahibi `config_ui_assets.R` kaldı.
- Asset-order / render plan / defer davranışı ve `ui_asset_validate()` doğrulaması
  bozulmadı; tema kaskad zinciri ve Bilge Yolaç CSS/JS zinciri korundu.
- DB/SSO/encoding/source-order/UX runtime sözleşmelerine dokunulmadı (saf yapısal
  ayrım).

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- Altın çıktı karşılaştırması: bölme öncesi 11 fonksiyon çıktısı + HEAD vs çalışma
  ağacı; tümü `identical()` TRUE (tam tag md5 `11c977ddce2c3aee5307eadc5fa4995a`).
- `Rscript tests/scripts/maintainability_report.R` → skor 100/100; en büyük dosya
  690 → 687; VERİ 425/1, validators 253/11, tags 59/5.
- `Rscript tests/scripts/seam_doctor.R` → `SEAM_DOCTOR_RESULT: OK`; `frontend_varlik`
  runtime-dosya 3 → 5, guard-test 8 → 9.
- `Rscript tests/scripts/frontend_complexity_doctor.R` → rapor üretildi.
- `Rscript tests/scripts/parse_sanity_check.R` → OK (849 dosya).
- Odak testler tek tek geçti (0 FAIL / 0 WARN / 0 SKIP): yeni split-contract (100),
  ui-asset-manifest (224), config-ui-assets-helpers (13), ui-asset-tag-builders (18),
  source-manifest-sections (154), maintainability-ratchet (240),
  source-manifest-contract (165), global-source-manifest (12), seam-registry (12),
  seam-doctor (6), ui-asset-zones (17), ui-asset-zone-validators-split (36),
  streaming-markdown-safety (53), frontend-maintainability-ratchet (92),
  frontend-selector (80), e2e-health-dashboard (45), production-contracts (21),
  e2e-boot-welcome (29 — `logger` kurulu + placeholder env ile).
- `bash tools/ai_validate.sh quick` → geçti; `failed_steps: 0`, `skipped_steps: 0`,
  app source smoke PASSED (`artifacts/ai-validation/20260620-152956/summary.json`).
- `bash tools/ai_validate.sh full --boot-smoke` → **tam geçti**; app source smoke
  PASSED, **full testthat suite PASSED (138.5s)**, shiny boot smoke PASSED, browser
  smoke SKIPPED (tarayıcı yok); `failed_steps: 0`, `skipped_steps: 0`
  (`artifacts/ai-validation/20260620-153104/summary.json`). NOT: bu bulut oturumunda
  `logger` paketi kurularak ve placeholder env değişkenleri verilerek koşuldu; bu
  sayede önceki oturumların bildirdiği "logging testi tıkayıcısı" bu koşumda
  tekrarlanmadı (full suite temiz geçti).

### Manuel QA (kullanıcı/VM tarafı)
- Uygulamayı başlatın; tüm sayfaların (Ana Söyleşi, Bilge Yolaç, Yönetici, Sağlık,
  Destek) CSS/JS varlıklarının eskisi gibi yüklendiğini ve tema (koyu/açık) ile
  CodeMirror/Three.js/Bilge Yolaç yükleme sırasının bozulmadığını doğrulayın.
- Tarayıcı konsolunda eksik/yanlış-sıralı asset veya JS hatası olmadığını doğrulayın.

### Bilinen riskler / atlanan doğrulamalar
- VM/SSO/gerçek DB/SQL Server Türkçe encoding/gerçek tarayıcı kanıtı alınmadı (bulut
  oturumu). Değişiklik saf yapısal ayrımdır ve çıktı byte-birebir golden + HEAD
  karşılaştırmasıyla korundu; gerçek tarayıcı asset yükleme yalnızca VM/manuel
  tarayıcıda son kez doğrulanır.
- Sıradaki paket adayları: `R/server_runtime_context.R` (687, yeni en büyük;
  SSO auth-ready/refreshable-module helper çıkarımı), ardından 678–681 bandındaki
  `helpers_claude_code_documents.R`, `server_handler_true_streaming.R`,
  `module_file_manager.R`; veya frontend tarafında `www/js/deep_space_intro.js`
  (820) / `www/js/ai_expert_manager.js` (802/45/12 event/8 Shiny handler).

---

## 2026-06-20 — Sohbet-okuma SQL sorgu üreticilerinin reader dosyasından ayrılması

### Seçilen iz(ler)
- **Track 1 — yakın-bütçe R dosyasından bütünleşik (saf) çıkarım** (öncelik #1).
  `veritabani_kodlama` seam'inde tek paket.

### Özet ve gerekçe
Keşif raporu (maintainability 100/100; en büyük dosya 690): `R/helpers_db_chat_readers.R`
**680/13 ile 3. en büyük R dosyasıydı** ve yakın-bütçe bandındaydı. Dosya ~200 satırlık
**saf ASCII SQL string'i** (önizleme/liste/mesaj/toplu/geçmiş; with_reasoning ve
kullanıcı-kapsamlı null/scoped varyantlar dahil) ile bağlantı/normalizasyon/formatlama
orkestrasyonunu karıştırıyordu. SQL string'leri encoding-hassas DEĞİLDİR (encoding
işleme tamamen `normalize_db_read_visible_frame()` içinde, reader'da kalır), bu yüzden
SQL'i ayrı bir üretici modülüne taşımak, en korumalı seam'in (Türkçe encoding) hiçbir
sınırına dokunmadan davranış-koruyan ve byte-birebir doğrulanabilir bir çıkarımdır.

SQL, yeni `R/helpers_db_chat_read_queries.R` dosyasındaki 6 saf üreticiye taşındı.
`with_reasoning` (ReasoningContent sütunu) ve `scoped` (`AND c.UserID = ?`) varyantları
koşullu `paste0`/fragment'larla DRY hale getirildi; çıktı eski satır içi SQL ile
**byte-birebir aynıdır** (extraction öncesi 14 SQL string'i stub'lı bağlantı ile
yakalanıp golden olarak doğrulandı; tüm string'ler `identical()` TRUE).

### Değişen dosyalar
**Kaynak**
- `R/helpers_db_chat_read_queries.R` (yeni, 133/6) — `db_chat_preview_query_sql`,
  `db_chat_list_summary_query_sql`, `db_chat_list_full_query_sql`,
  `db_chat_messages_query_sql`, `db_chat_messages_batch_query_sql`,
  `db_history_rows_query_sql`. Saf, bağlantısız, encoding'siz; kullanıcı izolasyonu
  (`c.UserID = ?`) + soft-delete (`c.IsDeleted = 0`) güvenlik filtreleri burada.
- `R/helpers_db_chat_readers.R` — **680/13 → 522/13**; satır içi SQL yerine üreticileri
  çağırır; bağlantı/normalizasyon/formatlama orkestrasyonu korunur.
- `R/config_source_manifest.R` — `database` bölümüne üretici dosyası
  `helpers_chat_message_formatting.R`'den sonra, `helpers_db_chat_readers.R`'den ÖNCE
  eklendi (11 → 12 dosya; toplam 276 → 277).
- `R/bootstrap_source_manifest.R` — kritik sıra kuralı:
  `helpers_db_chat_read_queries.R` → `helpers_db_chat_readers.R`.
- `R/config_seam_registry.R` — `veritabani_kodlama` guard_tests listesine yeni
  contract testi eklendi (5 → 6).
- `tests/testthat/helper_bootstrap.R` — DB kaynak zinciri üretici dosyasını reader'dan
  önce yükleyecek şekilde güncellendi.

**Test**
- `tests/testthat/test-db-chat-read-queries-contract.R` (yeni, 52 assertion) — yapısal
  ayrım (üreticiler yeni dosyada; reader üreticileri çağırır; büyük satır içi SQL
  gövdeleri reader'da yok; manifest sırası) + saf üretici davranışı (with_reasoning →
  ReasoningContent, legacy → yok; scoped → AND c.UserID = ?; güvenlik filtresi;
  placeholder enjeksiyonu; with/legacy YALNIZCA reasoning satırıyla farklılaşır).
- `tests/testthat/test-db-user-scope-contract.R` — güvenlik filtresi (kullanıcı
  izolasyonu + soft-delete) artık üretici dosyasında doğrulanır; okuyucuların
  kullanıcı-kapsamlı üreticilere yönlendiği eklendi.
- `tests/testthat/test-db-refactor-contract.R` — etkinlik-zamanı ORDER BY sözleşmesi
  artık üretici dosyasında aranır; reader-tarafı toplu sıralama kontrolü korundu.
- `tests/testthat/test-source-manifest-sections-contract.R` — `database` n=11→12;
  toplam 276→277 bilinçli güncellendi.
- `tests/testthat/test-maintainability-ratchet.R` — dosya bazlı bütçeler:
  `helpers_db_chat_readers.R` 560/14, `helpers_db_chat_read_queries.R` 180/8.

**Dokümantasyon**
- `CLAUDE.md` — DB helper modularization contract: üretici dosyası source sırasına +
  sorumluluklara + korumalı test listesine eklendi; reader sorumluluğu "üreticileri
  çağırır" olarak güncellendi; Group 3 yükleme listesi.
- `docs/feature-ownership-map.md` — DB seam'ine üretici dosyası + iki test;
  "sıradaki hedef" notu güncellendi (680/13 → 522/13).
- `docs/architecture-map.md` — DB/persistence satırına üretici dosyası notu.
- `docs/technical-reference.md` — SQL üretici extraction + golden + bütçe notu.
- `docs/refactor-log.md` — bu giriş.

### Önce / sonra karmaşıklık notları
- Önce: `helpers_db_chat_readers.R` 680/13 (3. en büyük R dosyası, yakın-bütçe);
  ~200 satır satır içi SQL + bağlantı/normalizasyon orkestrasyonu karışık.
- Sonra: reader 522/13 (orkestrasyon-odaklı); üreticiler 133/6 (tek-sorumluluk saf SQL).
  Skor 100/100; 800+ satır / 25+ fonksiyon = 0; en büyük dosya 690 (değişmedi).
  Reader yakın-bütçe bandından çıktı; iki dosya da dosya-özel bütçeyle kilitli.

### Korunan davranış sözleşmeleri
- 14 SQL string'inin tamamı byte-birebir korundu (golden `identical()` TRUE).
- Kullanıcı izolasyonu (`c.UserID = ?`) + soft-delete (`c.IsDeleted = 0`) güvenlik
  filtreleri ve reasoning-fallback (with_reasoning → legacy) deseni korundu; statik
  güvenlik sözleşmesi üretici dosyasını hedefleyecek şekilde güncellendi.
- `normalize_db_read_visible_frame()` / `normalize_text_frame_utf8()` encoding okuma
  normalizasyonu reader dosyasında kaldı; encoding sınırına dokunulmadı.
- DB/SSO/source-order/UX runtime sözleşmelerine dokunulmadı (saf SQL relocate + DRY).

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- Golden SQL karşılaştırması: extraction öncesi/sonrası 14 SQL string'i stub'lı
  bağlantı ile yakalandı; tümü byte-birebir aynı (`identical()` TRUE).
- `Rscript tests/scripts/maintainability_report.R` → skor 100/100; reader 522/13;
  üretici 133/6; en büyük dosya 690.
- `Rscript tests/scripts/seam_doctor.R` → `SEAM_DOCTOR_RESULT: OK`; `veritabani_kodlama`
  runtime-dosya 13 → 14, guard-test 5 → 6.
- `Rscript tests/scripts/parse_sanity_check.R` → OK (846 dosya).
- Odak testler tek tek geçti (0 FAIL / 0 WARN / 0 SKIP): yeni queries-contract (52),
  güncellenen db-user-scope (13), db-chat-readers-behavior (21), db-refactor-contract (31),
  db-normalization-contract (38), db-user-visible-encoding-boundaries (31),
  text-encoding-utils (14), chat-message-formatting-refactor (26), production-contracts (21),
  e2e-chat-persistence-regression (43), image-gallery-observers-behavior (8),
  startup-observers-runtime-smoke (5), source-manifest-sections (154),
  source-manifest-contract (165), global-source-manifest (12), seam-registry (12),
  seam-doctor (6), maintainability-ratchet (231).
- `bash tools/ai_validate.sh quick` → geçti; `failed_steps: 0`, `skipped_steps: 0`,
  app source smoke PASSED (`artifacts/ai-validation/20260620-035411/summary.json`).
- `bash tools/ai_validate.sh full --boot-smoke` → app source smoke PASSED; tam strict
  testthat suite yalnızca ÖNCEDEN VAR OLAN ve ilgisiz iki logging testinde
  (`test-config-logging-caller-frame.R`, `test-logging-resolvers-behavior.R` — bulut
  log-dizini yazılabilirlik hatası, değişiklik kümem hiçbir logging dosyasına dokunmuyor)
  başarısız oldu.

### Manuel QA (kullanıcı/VM tarafı)
- Kayıtlı Söyleşiler ve Söyleşi Geçmişi sayfalarını açın; sohbet önizleme listesi,
  kayıtlı sohbet yükleme, geçmiş satır çiftleri ve toplu hidratasyonun eskisi gibi
  çalıştığını ve yalnızca giriş yapan kullanıcının sohbetlerinin göründüğünü doğrulayın.
- Türkçe karakterli sohbet başlıklarının/mesajlarının doğru göründüğünü doğrulayın.

### Bilinen riskler / atlanan doğrulamalar
- VM/SSO/gerçek SQL Server/gerçek tarayıcı kanıtı alınmadı (bulut oturumu; gerçek DB
  bağlantısı yok). Değişiklik saf SQL string relocate + DRY'dir ve SQL byte-birebir
  golden ile korundu; gerçek sorgu çalıştırma yalnızca VM/canlı DB'de kanıtlanır.
- Tam strict testthat suite bu bulut checkout'unda ÖNCEDEN VAR OLAN ilgisiz logging
  testleri nedeniyle tamamlanmıyor; bu paket bu testleri ne kırdı ne onardı.
- Sıradaki paket adayları: `R/config_ui_assets.R` (690, asset-order hassas — dikkatli),
  `R/server_runtime_context.R` (687, sıkı sözleşme), ya da frontend tarafında yoğun
  `www/js/ai_expert_manager.js` (802/45/12 event/8 Shiny handler).

---

## 2026-06-20 — TTS açık streaming dalının send_message'tan ayrı handler'a çıkarılması

### Seçilen iz(ler)
- **Track 1 — en büyük / yakın-bütçe R dosyasından bütünleşik (terminal dal) çıkarımı**
  (öncelik #1). `sohbet_llm_akis` seam'inde tek paket.
- **Track 6 — eskimiş "sıradaki hedef" risk notlarının temizlenmesi**:
  feature-ownership-map'te `server_send_message.R`'yi yanlış/garbled biçimde
  (728, "flat renderer listesi") sıradaki hedef gösteren iki not güncellendi.

### Özet ve gerekçe
Keşif raporları (maintainability 100/100; frontend yapısal temiz; seam doctor OK):
`R/server_send_message.R` repo genelindeki **en büyük R dosyasıydı (694/14)** ve tam
olarak küresel `MERGEN_TEST_MAX_FILE_LINES` bütçesindeydi (geçen oturum 796 → 694
sıkılaştırılmıştı), yani küresel sınırı kilitliyor ve dokümante "sıradaki hedef" idi.

`send_message()` içindeki `send_message` kapanışı, LLM çağrısını üç terminal dala
yönlendiriyordu: gerçek SSE (`handle_true_streaming_mode`), non-streaming
(`generate_non_streaming_stoppable_fn`) ve TTS açık streaming. İlk ikisi zaten ayrı
`R/server_handler_*` dosyalarına çıkarılmış ctx tabanlı handler'lardı; yalnızca **TTS
açık streaming dalı (~135 satır promise zinciri) satır içi** kalmıştı. Bu dal mevcut
deseni birebir izleyerek yeni `R/server_handler_streaming_tts.R` dosyasındaki
`handle_streaming_tts_mode(ctx)` işleyicisine taşındı (gövde birebir korundu;
ctx-destructuring başlığı yerel adları eski isimlere eşler). Üç dal artık simetriktir.

### Değişen dosyalar
**Kaynak**
- `R/server_handler_streaming_tts.R` (yeni, 172/6) — `handle_streaming_tts_mode(ctx)`:
  TTS açık streaming promise zinciri (LLM streaming çağrısı, stale/stopped/current
  istek kararı, takip soruları, TTS sesi çözümü, `simulate_streaming_stoppable_fn`).
- `R/server_send_message.R` — **694/14 → 590/9**; satır içi dal artık ~25 satırlık
  `streaming_tts_ctx <- list(...)` + `handle_streaming_tts_mode(streaming_tts_ctx)`.
- `R/config_source_manifest.R` — `server_handlers_send_message` bölümüne handler
  `R/server_handler_true_streaming.R`'den sonra, `R/server_send_message.R`'den önce
  eklendi (8 → 9 dosya; toplam 275 → 276).
- `R/bootstrap_source_manifest.R` — kritik sıra kuralı:
  `R/server_handler_streaming_tts.R` → `R/server_send_message.R`.
- `R/config_seam_registry.R` — `sohbet_llm_akis` guard_tests listesine yeni
  split-contract testi eklendi (7 → 8).

**Test**
- `tests/testthat/test-server-handler-streaming-tts-contract.R` (yeni, 29 assertion) —
  yapısal ayrım (handler yeni dosyada; send_message ctx ile devreder; satır içi
  promise zinciri / `ai_processor$call_llm_streaming` / `simulate_streaming_stoppable_fn`
  send_message'ta kalmadı) + manifest sırası + deterministik promise zinciri davranışı
  (gerçek `promises`+`later`, stub'lı: başarı → simulate; başarısız → abort; durdurulmuş
  → cleanup; reddedilmiş → abort, "API_ERROR:" öneki soyulur).
- `tests/testthat/test-source-manifest-sections-contract.R` —
  `server_handlers_send_message` n=8→9; toplam runtime 275→276 bilinçli güncellendi.
- `tests/testthat/test-maintainability-ratchet.R` — küresel `MERGEN_TEST_MAX_FILE_LINES`
  694 → 690 sıkılaştırıldı; `server_send_message.R` bütçesi 760/14 → 620/11; yeni
  handler için 200/8 bütçesi eklendi.

**Dokümantasyon**
- `CLAUDE.md` — send_message contract: handler sorumluluğu + simetrik üç-dal notu +
  re-inline yasağı + yeni test "Protected by" listesinde; Group 7 yükleme listesi.
- `docs/feature-ownership-map.md` — Sohbet/Streaming seam'ine handler + test eklendi;
  iki eskimiş `server_send_message.R` "sıradaki hedef" notu güncellendi (yeni adaylar
  `config_ui_assets.R` 690, `server_runtime_context.R` 687).
- `docs/architecture-map.md` — LLM entegrasyonu satırına simetrik üç-dal handler notu.
- `docs/technical-reference.md` — TTS streaming handler extraction + yeni ratchet tabanı.
- `docs/refactor-log.md` — bu giriş.

### Önce / sonra karmaşıklık notları
- Önce: `server_send_message.R` 694/14 (repo genelinde en büyük; küresel bütçede).
- Sonra: `server_send_message.R` 590/9; yeni handler 172/6. Skor 100/100; 800+ satır /
  25+ fonksiyon = 0. **Küresel en büyük dosya satırı 694 → 690** (yeni en büyük
  `config_ui_assets.R`, değişmedi). Küresel `MERGEN_TEST_MAX_FILE_LINES` 694 → 690.

### Korunan davranış sözleşmeleri
- TTS açık streaming promise zinciri gövdesi birebir taşındı (gövde değişmedi; yalnızca
  ctx-destructuring başlığı eklendi). Stale-istek/durdurma kararları istek kimliği
  kapsamlı kalır; başarı/başarısız/durdurulmuş/reddedilmiş yollar deterministik testle
  kanıtlandı.
- Gerçek SSE ve non-streaming dalları değişmedi. send_message orkestrasyonu, SSO/kullanıcı
  korumaları, mod-dispatch, API/model kurulumu aynı.
- DB/SSO/encoding/source-order/frontend asset order/UX runtime sınırlarına dokunulmadı.

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- `Rscript tests/scripts/maintainability_report.R` → skor 100/100; en büyük dosya
  694 → 690; `server_send_message.R` 590/9; yeni handler 172/6.
- `Rscript tests/scripts/seam_doctor.R` → `SEAM_DOCTOR_RESULT: OK`; `sohbet_llm_akis`
  runtime-dosya 42 → 43, guard-test 7 → 8.
- `Rscript tests/scripts/frontend_complexity_doctor.R` → rapor üretildi; frontend
  varlığı değişmedi.
- `Rscript tests/scripts/parse_sanity_check.R` → OK (844 dosya).
- Odak testler tek tek geçti (0 FAIL / 0 WARN / 0 SKIP): yeni split+behavior contract
  (PASS 29), source-manifest-sections (154), source-manifest-contract (165),
  global-source-manifest (12), maintainability-ratchet (225), seam-registry-contract
  (12), seam-doctor-contract (6), send-message-prompting (21),
  send-message-request-lifecycle (42), send-message-maintainability-ratchet (8),
  true-streaming-reset-ui (6), e2e-quick-actions-streaming-regression (75),
  streaming-poll-lifecycle (25), production-contracts (21).
- `bash tools/ai_validate.sh quick` → geçti; `failed_steps: 0`, `skipped_steps: 0`,
  app source smoke PASSED (`artifacts/ai-validation/20260620-032037/summary.json`).
- `bash tools/ai_validate.sh full --boot-smoke` → app source smoke PASSED; tam strict
  testthat suite, yalnızca ÖNCEDEN VAR OLAN ve ilgisiz iki logging testinde
  (`test-config-logging-caller-frame.R`, `test-logging-resolvers-behavior.R` — bulut
  log-dizini yazılabilirlik/file connection hataları) başarısız oldu. Bu iki test
  `git stash` ile değişikliklerim çıkarıldığında temiz tabanda da BİREBİR aynı şekilde
  başarısız (FAIL 3 / FAIL 1); değişiklik kümem hiçbir logging dosyasına dokunmuyor.
  Artifact: `artifacts/ai-validation/20260620-032137/summary.json`
  (`app_source_smoke_status="passed"`, `full_testthat_suite_status="failed"`,
  `failed_step_labels=["full testthat suite"]`).

### Manuel QA (kullanıcı/VM tarafı)
- Ana Söyleşi'de "Yanıtları Seslendir" (TTS) açıkken streaming bir model ile mesaj
  gönderin; yanıtın canlı geldiğini, takip sorularının üretildiğini ve sesli oynatmanın
  başladığını doğrulayın.
- Streaming sırasında "Durdur" basın; durdurma temizliğinin (gönder/typing/thinking
  durumunun sıfırlanması) eskisi gibi çalıştığını doğrulayın.
- TTS kapalıyken gerçek SSE yolunun ve MCP/non-streaming yolunun değişmediğini doğrulayın.

### Bilinen riskler / atlanan doğrulamalar
- VM/SSO/gerçek DB/SQL Server Türkçe encoding/gerçek tarayıcı/gerçek TTS uç noktası
  kanıtı alınmadı (bulut oturumu). Değişiklik davranış-koruyan terminal-dal
  extraction'ıdır; promise zinciri davranışı deterministik test ile kanıtlandı, ancak
  canlı TTS sesi/streaming uç-uca akış yalnızca VM/manuel tarayıcıda kanıtlanır.
- Tam strict testthat suite bu bulut checkout'unda ÖNCEDEN VAR OLAN ilgisiz logging
  testleri nedeniyle tamamlanmıyor (CLAUDE.md'de belgelenmiş durum); bu paket bu
  testleri ne kırdı ne onardı.
- Sıradaki paket adayları: `R/config_ui_assets.R` (690, asset-order hassas — dikkatli),
  `R/server_runtime_context.R` (687), ya da frontend tarafında yoğun
  `www/js/ai_expert_manager.js` (802/45/12 handler/8 Shiny handler).

---

## 2026-06-18 — Geri Bildirim tablo testi Windows/RStudio parse onarımı

### Seçilen iz(ler)
- **Test parse uyumluluğu / önceki paketin takip onarımı**: kullanıcı raporunda tam `testthat` koşumunun `test-admin-geri-bildirim-output-tables-behavior.R` içinde Türkçe kolon adına `$` ile erişim satırında parse hatası verdiği görüldü.

### Özet ve gerekçe
Yeni tablo helper testinde data.frame kolonları Türkçe başlıkları koruyordu; ancak test assertion'ları `sonuc$Kullanıcı` ve `sonuc$Geliştirilecek` gibi kaynak-kod parser'ına ortam/console encoding'e göre daha hassas non-ASCII `$` sembol erişimleri kullanıyordu. Davranış değişmeden, tüm kullanıcıya görünen Türkçe kolon kontrolleri `sonuc[["..."]]` biçimine çevrildi. Bu biçim UTF-8 string literal sınırını korur ve RStudio/Windows parse yolunda beklenmeyen end-of-file hatasını önler.

### Değişen dosyalar
- `tests/testthat/test-admin-geri-bildirim-output-tables-behavior.R` — Türkçe/non-syntactic kolon assertion'ları `$` yerine `[[...]]` ile okunur.
- `docs/refactor-log.md` — takip onarım ve doğrulama kaydı.

### Önce / sonra karmaşıklık notları
- Runtime kod değişmedi; yalnızca test kaynak erişim biçimi düzeltildi. Maintainability tabanı değişmedi.

### Korunan davranış sözleşmeleri
- Türkçe kolon adları ve kullanıcıya görünen değerler aynen test edilmeye devam eder.
- DB/SSO/encoding/source manifest/frontend asset order sınırlarına dokunulmadı.

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- `Rscript tests/scripts/maintainability_report.R` → skor 100/100, en büyük dosya 694.
- `Rscript tests/scripts/frontend_complexity_doctor.R` → rapor üretildi; frontend değişikliği yapılmadı.
- `Rscript tests/scripts/seam_doctor.R` → `SEAM_DOCTOR_RESULT: OK`.
- `Rscript -e 'parse(file="tests/testthat/test-admin-geri-bildirim-output-tables-behavior.R", encoding="UTF-8"); testthat::test_file("tests/testthat/test-admin-geri-bildirim-output-tables-behavior.R")'` → geçti.
- `Rscript tests/scripts/parse_sanity_check.R` → geçti; 836 dosya parse edildi.
- `bash tools/ai_validate.sh quick` → geçti; failed steps 0, skipped steps 0 (`artifacts/ai-validation/20260618-161101/summary.json`).

### Bilinen riskler / atlanan doğrulamalar
- Gerçek Windows/RStudio tam testthat ekranı bu Linux/Codex ortamında birebir kanıtlanamaz; onarım, kullanıcının raporladığı parse satırındaki non-ASCII `$` sembol erişimini kaldırır.

---

## 2026-06-18 — Geri Bildirim Analizi tablo hazırlama yardımcılarının renderer dosyasından ayrılması

### Seçilen iz(ler)
- **Track 1 — yakın-bütçe R dosyası sadeleştirme**: `destek_yonetici_saglik` seam'inde `R/module_admin_geri_bildirim_outputs.R` repo genelindeki en büyük dosyaydı (728 satır / 5 fonksiyon) ve flat renderer listesi içinde iki DT tablosunun görünüm veri hazırlığı da bulunuyordu.

### Özet ve gerekçe
Keşif raporu en büyük R dosyasını `R/module_admin_geri_bildirim_outputs.R` olarak gösterdi. Grafik/DT renderer kayıt davranışını değiştirmeden, kullanıcı memnuniyet tablosu ve detaylı geri bildirim tablosunun saf data.frame hazırlama mantığı yeni helper dosyasına taşındı. Böylece renderer dosyası yalnızca output kaydı + highcharter/DT seçeneklerine odaklandı; tablo dönüşümleri Shiny/DT başlatmadan test edilebilir hale geldi.

### Değişen dosyalar
- `R/helpers_admin_geri_bildirim_output_tables.R` (yeni) — kullanıcı bazlı memnuniyet ve detaylı geri bildirim tablosu görünüm verisi hazırlama yardımcıları.
- `R/module_admin_geri_bildirim_outputs.R` — iki DT renderer artık saf helper çıktısını `DT::datatable()` içine bağlar.
- `R/config_source_manifest.R`, `R/config_seam_registry.R` — yeni helper `module_admin` bölümünde outputs dosyasından önce yüklendi ve seam guard listesine davranış testi eklendi.
- `tests/testthat/test-admin-geri-bildirim-output-tables-behavior.R` (yeni) — Türkçe kolon başlıkları, yuvarlatma, sıralama sütunları, iletişim izni, mailto ikon HTML'i ve boş/değer yedekleri test edildi.
- `tests/testthat/test-admin-geri-bildirim-outputs-behavior.R`, `tests/testthat/test-admin-geri-bildirim-refactor-contract.R`, `tests/testthat/test-source-manifest-sections-contract.R`, `tests/testthat/test-maintainability-ratchet.R` — helper source sırası, manifest sayısı ve sıkılaştırılmış bütçeler güncellendi.
- `docs/feature-ownership-map.md`, `docs/architecture-map.md`, `docs/technical-reference.md`, `docs/refactor-log.md` — sahiplik, source manifest yapısı ve yeni taban çizgisi kaydedildi.

### Önce / sonra karmaşıklık notları
- Önce: `R/module_admin_geri_bildirim_outputs.R` 728 satır / 5 fonksiyon; repo genelindeki en büyük R dosyasıydı.
- Sonra: `R/module_admin_geri_bildirim_outputs.R` 656 satır / 4 fonksiyon; yeni helper 134 satır / 4 fonksiyon. Repo genelinde en büyük dosya 694 satıra indi ve global `MERGEN_TEST_MAX_FILE_LINES` tabanı 796 → 694 olarak sıkılaştırıldı.

### Korunan davranış sözleşmeleri
- 13 output ID, highcharter chart seçenekleri ve DT seçenekleri korunur; renderer dosyası hâlâ output kayıt noktasıdır.
- Tablo kolon başlıkları, sıralama yardımcı sütunları, memnuniyet/NPS gösterimi, iletişim izni ve mailto ikon üretimi davranışı focused test ile korunur.
- DB/SSO/encoding/frontend asset order/runtime app boot sınırlarına dokunulmadı.

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- `Rscript tests/scripts/maintainability_report.R` → başlangıç raporu; skor 100/100, en büyük dosya 728.
- `Rscript tests/scripts/frontend_complexity_doctor.R` → başlangıç raporu; frontend değişikliği yapılmadı.
- `Rscript tests/scripts/seam_doctor.R` → başlangıçta `SEAM_DOCTOR_RESULT: OK`.
- `Rscript -e 'testthat::test_file("tests/testthat/test-admin-geri-bildirim-output-tables-behavior.R")'` → geçti.
- `Rscript -e 'testthat::test_file("tests/testthat/test-admin-geri-bildirim-outputs-behavior.R"); testthat::test_file("tests/testthat/test-admin-geri-bildirim-refactor-contract.R"); testthat::test_file("tests/testthat/test-source-manifest-sections-contract.R"); testthat::test_file("tests/testthat/test-maintainability-ratchet.R")'` → outputs behavior testinde `highcharter` eksikliği nedeniyle 6 skip; refactor/source-manifest/maintainability geçti.
- `bash tools/ai_validate.sh quick` → geçti; failed steps 0, skipped steps 0 (`artifacts/ai-validation/20260618-154526/summary.json`).

### Bilinen riskler / atlanan doğrulamalar
- Gerçek tarayıcı, VM, DB, SSO veya admin panel manuel tıklama kanıtı alınmadı; paket davranış-preserving R helper extraction'dır.
- Sıradaki yüksek kaldıraç adayları: `R/server_send_message.R` (694 satır), `R/config_ui_assets.R` (690 satır; asset-order hassas), veya frontend tarafında `www/js/deep_space_intro.js` / `www/js/ai_expert_manager.js`.

---

## 2026-06-17 — Yapılandırma reset UI senkronizasyonu onarımı

### Seçilen iz(ler)
- **Kullanıcı bildirimiyle gelen davranış onarımı**: Yapılandırma sayfasında `Varsayılana Dön` merkezi ayar state'ini sıfırlıyor, ancak birçok görünür input aynı anda varsayılan UI değerine çekilmiyordu.

### Özet ve gerekçe
Önceki UI dosya ayrımı sonrasında yapılan manuel kontrolde `Varsayılana Dön` düğmesinin Görünüm checkbox'ları, AI Uzman konuşması seçimleri, müzik ses seviyesi, Görsel/Özetleme/Analiz ayarları, Claude Code zaman aşımı ve takip sorusu checkbox'ı üzerinde görünür etki üretmediği bildirildi. Kök neden, `reset_all_settings()` içinde reactive `settings` değerlerinin ve bazı araç checkbox'larının sıfırlanmasına rağmen, Yapılandırma alt modülündeki görünür Shiny inputlarının tamamına `update*Input()` / özel switch DOM reset mesajı gönderilmemesiydi.

### Değişen dosyalar
- `R/module_settings.R` — `reset_all_settings()` artık Yapılandırma sayfasındaki tüm ilgili select/numeric/slider/checkbox inputlarını varsayılanlara günceller; `image_quality_hd` ve `analysis_deep_thinking` özel HTML switch'leri için `checked=false` + `change` tetiklenir; `settings$claude_code_timeout` da varsayılana çekilir.
- `tests/testthat/test-settings-reset-ui-contract.R` (yeni) — reset akışının kullanıcı tarafından bildirilen görünür inputların tamamını kapsadığını ve özel switch'lerin DOM/Shiny change reset yolunu koruduğunu statik sözleşmeyle doğrular.
- `docs/feature-ownership-map.md`, `docs/technical-reference.md`, `docs/refactor-log.md` — reset davranışı ve yeni guard testi kaydedildi.

### Önce / sonra karmaşıklık notları
- Davranış onarımı küçük bir reset senkronizasyon bloğu ekledi; maintainability skoru 100/100 kaldı. Büyük dosya/fonksiyon ratchetleri zayıflatılmadı.

### Korunan davranış sözleşmeleri
- `settings` reactive değerleri için mevcut varsayılanlar korunur.
- Reset sonrası görünen Yapılandırma UI değeri ile uygulanmış merkezi settings değeri tekrar hizalanır.
- DB/SSO/encoding/source-order/frontend asset-order sınırlarına dokunulmadı.

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- `Rscript tests/scripts/maintainability_report.R` → skor 100/100.
- `Rscript tests/scripts/frontend_complexity_doctor.R` → rapor üretildi; frontend varlığı değişmedi.
- `Rscript tests/scripts/seam_doctor.R` → `SEAM_DOCTOR_RESULT: OK`.
- `Rscript -e 'testthat::test_file("tests/testthat/test-settings-reset-ui-contract.R")'` → geçti.
- `bash tools/ai_validate.sh quick` → final doğrulama için çalıştırıldı.

### Bilinen riskler / atlanan doğrulamalar
- Bu ortamda gerçek tarayıcı/VM manuel tıklama kanıtı alınmadı. Kullanıcı tarafında özellikle Yapılandırma → `Varsayılana Dön` sonrası bildirilen tüm alanların görsel olarak varsayılanlara dönmesi manuel doğrulanmalıdır.
- Sıradaki aday: bu reset sözleşmesini ileride browser smoke'a taşımak veya `shiny::testServer` ile daha davranışsal hale getirmek.

---

## 2026-06-16 — Yapılandırma gelişmiş UI kartlarının ana UI dosyasından ayrılması

### Seçilen iz(ler)
- **Track 1 — en büyük R dosyasını kontrollü saf UI çıkarımıyla küçültme.** `api_anahtar_model` / ayarlar seam'inde tek paket.

### Özet ve gerekçe
Keşif raporu `R/module_settings_yapilandirma_ui.R` dosyasını repo genelindeki en büyük R dosyası olarak gösterdi (758 satır / 12 fonksiyon). Dosya server/runtime mantığı taşımıyordu; ancak temel ayarlar kartları ile medya, AI Uzman, görsel oluşturma, özetleme ve analiz kartları aynı dosyada toplanmıştı. En düşük riskli iyileştirme, ileri/gelişmiş kartları ayrı saf UI dosyasına taşımak ve ana kompozitörün aynı `.syap_*` çağrı yüzeyini korumasıydı.

### Değişen dosyalar
- `R/module_settings_yapilandirma_advanced_ui.R` (yeni) — `.syap_audio_card`, `.syap_ai_expert_card`, `.syap_image_card`, `.syap_summarization_card`, `.syap_analysis_card` saf UI yapıcıları.
- `R/module_settings_yapilandirma_ui.R` — ana kompozitör + header/model/API/tools/Claude Code/arayüz/kısayol kartları olarak küçültüldü.
- `R/config_source_manifest.R` ve `R/bootstrap_source_manifest.R` — `module_settings_api_key` sırası advanced UI → UI → server olarak güncellendi.
- `tests/testthat/test-settings-yapilandirma-ui-*.R`, `tests/testthat/test-source-manifest-sections-contract.R`, `tests/testthat/test-maintainability-ratchet.R` — izole source sırası, split sözleşmesi ve dosya bütçeleri güncellendi.
- `CLAUDE.md`, `docs/architecture-map.md`, `docs/technical-reference.md`, `docs/feature-ownership-map.md`, `docs/refactor-log.md` — yeni sahiplik/sıra ve sıradaki hedef notları güncellendi.

### Önce / sonra karmaşıklık notları
- Önce: `R/module_settings_yapilandirma_ui.R` 758/12; repo genelindeki en büyük R dosyasıydı.
- Sonra: `R/module_settings_yapilandirma_ui.R` 411 satır; `R/module_settings_yapilandirma_advanced_ui.R` 353 satır. Maintainability skoru 100/100 kaldı; 800+ satır ve 25+ fonksiyon dosyası yok; en büyük dosya artık 728 satır.

### Korunan davranış sözleşmeleri
- Public `settingsYapilandirmaUI(id)` wrapper ve `settingsYapilandirmaUIImpl(id)` kompozitör yüzeyi değişmedi.
- Sunucuya bağlanan 47 Shiny input/output id yüzeyi korundu.
- Her kartın Türkçe başlığı ve kendi id sahipliği `test-settings-yapilandirma-ui-cards-behavior.R` ile korunmaya devam ediyor.
- DB/SSO/encoding/frontend asset order/streaming davranışlarına dokunulmadı; değişiklik saf R/Shiny UI kaynak ayrımıdır.

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- `Rscript tests/scripts/maintainability_report.R` → skor 100/100; en büyük dosya 728; refactor adayı yok.
- `Rscript tests/scripts/frontend_complexity_doctor.R` → rapor üretildi; frontend runtime varlığı değişmedi.
- `Rscript tests/scripts/seam_doctor.R` → `SEAM_DOCTOR_RESULT: OK`.
- Odak testler: `test-settings-yapilandirma-ui-cards-behavior.R`, `test-settings-yapilandirma-ui-id-surface-behavior.R`, `test-settings-yapilandirma-ui-refactor-contract.R`, `test-source-manifest-sections-contract.R`, `test-maintainability-ratchet.R` geçti.
- `bash tools/ai_validate.sh quick` → final doğrulama için çalıştırıldı.

### Bilinen riskler / atlanan doğrulamalar
- VM/SSO/gerçek DB/SQL Server/gerçek tarayıcı kanıtı alınmadı; paket saf UI dosya ayrımıdır ve bu kanıtları gerektiren boundary'lere dokunmadı.
- Sıradaki paket adayı: `R/module_admin_geri_bildirim_outputs.R` (728 satırlık flat renderer listesi) veya davranışsal değeri daha yüksek ama riski daha fazla olan `R/server_send_message.R` (694).

---

## 2026-06-16 — Görsel oluşturma UI/HTML render katmanının runtime'dan ayrılması

### Seçilen iz(ler)
- **Track 1 — En büyük / yakın-bütçe (iki eksende) R dosyasından bütünleşik (saf)
  UI/HTML katmanı çıkarımı** (öncelik #1; "Move pure decision logic out of large
  Shiny/server modules"). `dosya_yasam_dongusu` (görsel) seam'inde tek paket.

### Özet ve gerekçe
`module_image_generation.R` İKİ eksende de yakın-bütçeydi (730 satır / 22 fonksiyon;
22, küresel 24-fonksiyon tavanına yakın) ve önceki oturumun belgelenmiş #2 adayıydı.
Dosya aslında bir Shiny server modülü DEĞİL — IO/üretim/çeviri runtime yardımcıları
(`generate_image`, `save_image_locally`, `translate_*`, `get_user_image_dir`,
`get_image_web_url`) + saf UI/HTML render yapıcıları (`imageSettingsUI`,
`imageChatControlsUI`, `render_generated_image_html`, `render_image_from_saved_path`)
karışımıydı. UI/HTML render yapıcıları async görsel worker'ında HİÇ koşmaz
(`generate_image` worker-export globalidir ve yalnızca runtime yardımcılarını çağırır),
bu da UI katmanını ayırmayı en güvenli, en bütünleşik çıkarım yaptı.

UI/HTML render katmanı yeni `R/module_image_generation_ui.R` dosyasına BİREBİR taşındı;
runtime IO/üretim yardımcıları + `IMAGE_SIZE_OPTIONS` sabiti runtime dosyasında kaldı.
render_* yapıcıları `get_image_web_url`/`IMAGE_SIZE_OPTIONS`/`mergen_generated_image_card_html`'i
çağrı anında çözdüğü için dosyalar bağımlılık-önce sırada (runtime → ui) yüklenir.
Refactor öncesi/sonrası dört yapıcının render çıktısı altın referansla doğrulandı:
**byte-birebir aynı** (md5 `8887d208…`, `identical()` TRUE).

### Değişen dosyalar
**Kaynak**
- `R/module_image_generation_ui.R` (yeni, 194 satır / 5 fonksiyon) — 4 UI/HTML render
  yapıcısı (ayarlar paneli, sohbet kontrolleri, oluşturulan/kaydedilmiş görsel kartı HTML).
- `R/module_image_generation.R` — **730/22 → 545/17** (yalnızca runtime IO/üretim/çeviri
  yardımcıları + config/sabitler).
- `R/config_source_manifest.R` — `module_files_media` bölümüne
  `R/module_image_generation_ui.R`, `R/module_image_generation.R`'den SONRA eklendi
  (6 → 7 dosya; toplam 269 → 270).
- `R/bootstrap_source_manifest.R` — kritik sıra kuralı eklendi (bağımlılık-önce):
  `module_image_generation.R` → `module_image_generation_ui.R`.
- `R/config_seam_registry.R` — `dosya_yasam_dongusu` guard_tests listesine yeni
  split-contract testi eklendi (6 → 7).

**Test**
- `tests/testthat/test-image-generation-ui-refactor-contract.R` (yeni) — UI/runtime
  ayrım sözleşmesi (UI yapıcıları UI dosyasında; runtime dosyası onları içermez +
  IO/üretim yardımcıları + `IMAGE_SIZE_OPTIONS` runtime'da kalır); manifest sırası
  runtime→ui; runtime dosyasının UI render fonksiyonlarını ÇAĞIRMAMASI (worker-yolu
  bağımsızlığı).
- `tests/testthat/test-image-generation-module-behavior.R` — her iki dosyayı da source
  edecek şekilde güncellendi; mevcut çeviri/anahtar/endpoint/web URL/UI/HTML+XSS
  davranış kapsaması korundu.
- `tests/testthat/test-generated-image-card-html-contract.R` — render_* tüketicileri
  UI dosyasına taşındığından kanonik-kart-yardımcısı sözleşmesi `module_image_generation_ui.R`'yi
  hedefleyecek şekilde güncellendi (re-inline yasağı UI dosyasını da kapsar; sözleşme korundu).
- `tests/testthat/test-source-manifest-sections-contract.R` — `module_files_media`
  n=6→7, toplam 269→270 bilinçli güncellendi.
- `tests/testthat/test-maintainability-ratchet.R` — `module_image_generation.R`
  765/22 → 560/18 sıkılaştırıldı; `module_image_generation_ui.R` 220/8 bütçesi eklendi.

**Dokümantasyon**
- `CLAUDE.md` — yeni "Image generation UI/runtime split contract"; kanonik görsel-kart
  notu render_* konumunu UI dosyası olarak güncellendi; Group 6 yükleme listesi.
- `docs/feature-ownership-map.md` — Görsel/Vision seam'ine UI dosyası + 2 test;
  at-budget risk notu güncellendi; Frontend "sıradaki hedef" işaretçisi güncellendi.
- `docs/technical-reference.md` — görsel UI/runtime ayrımı + bağımlılık-önce sıra notu.
- `docs/refactor-log.md` — bu giriş.

### Önce / sonra karmaşıklık notları
- Önce: `module_image_generation.R` 730/22 (iki eksende yakın-bütçe; 22, 24-fonksiyon
  tavanına yakın). Sonra: runtime 545/17, UI 194/5; her ikisi dosya-özel bütçeyle kilitli.
  Skor 100/100; 800+ satır / 25+ fonksiyon = 0. At-budget görsel pini KALMADI.

### Korunan davranış sözleşmeleri
- Dört UI/HTML render yapıcısının render çıktısı byte-birebir korundu (altın md5 eşleşti).
  XSS kaçışı (`render_generated_image_html` hata kutusu + revised_prompt) ve kanonik
  kart yardımcısı delegasyonu testlerle kilitli.
- `generate_image` worker-export globali ve iç çeviri/kaydetme çağrıları runtime
  dosyasında kaldı; worker globals (`tracked_future_promise` auto-derive) çözümü
  değişmedi. UI yapıcıları worker görevinde koşmaz.
- DB/SSO/encoding/streaming/UX çalışma-zamanı sözleşmelerine dokunulmadı.

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- Altın render karşılaştırması (4 yapıcı): `identical()` TRUE, md5
  `8887d2089226e171637ba09326241554` eşleşti.
- Odak testler tek tek geçti (0 FAIL / 0 WARN): yeni split-contract, güncellenen
  image-generation-module-behavior, generated-image-card-html-contract,
  image-generation-handler-behavior, maintainability-ratchet, source-manifest-sections,
  source-manifest-contract, global-source-manifest, seam-registry-contract,
  seam-doctor-contract.
- `Rscript tests/scripts/seam_doctor.R` → OK; `dosya_yasam_dongusu` runtime-dosya +1,
  guard-test 6 → 7; sahipsiz dosya yok.
- `Rscript tests/scripts/maintainability_report.R` → skor 100/100; en büyük 758;
  refactor adayı yok.
- `bash tools/ai_validate.sh full --boot-smoke` → (commit'te artifact); app source
  smoke + tam strict testthat + shiny boot smoke.

### Manuel QA (kullanıcı/VM tarafı)
- Görsel Oluşturma hızlı eylemi: ayarlar panelinin (boyut/HD), sohbet içi görsel
  kontrollerinin ve oluşturulan görsel kartının (görsel + MERGEN Bilge filigranı +
  indir/kopyala/yazdır butonları + açıklama) eskisi gibi render olduğunu doğrulayın.
- Görsel oluşturma akışının (Türkçe prompt → İngilizce çeviri → üretim → kaydetme →
  Türkçe revised prompt) eskisi gibi çalıştığını doğrulayın.

### Bilinen riskler / atlanan doğrulamalar
- VM/SSO/gerçek DB/SQL Server/gerçek tarayıcı/gerçek görsel-üretim uç noktası kanıtı
  alınmadı (bulut oturumu; httr/worker mock'lu). Değişiklik saf UI/runtime ayrımıdır,
  render çıktısı byte-birebir korundu; gerçek DALL-E/görsel uç noktası yalnızca VM/canlı
  ortamda kanıtlanır.
- Sıradaki paket adayı: `module_settings_yapilandirma_ui.R` (758, en büyük runtime
  dosyası — zaten saf `.syap_*` alt-yapıcılı; ayrı UI dosyasına bölünebilir) ya da
  frontend büyük CSS dosyaları (`destek_page.css` 1527 vb. — görsel regresyon riski,
  VM QA ister).

---

## 2026-06-16 — Derin uzay açılış ekranı UI/sunucu ayrımı + veri-odaklı mod-kartı dedup

### Seçilen iz(ler)
- **Track 1 — En büyük / yakın-bütçe R dosyasından bütünleşik (saf) UI çıkarımı**
  (öncelik #1). `kimlik_sso` başlangıç seam'inde tek paket.
- **Track 4 — belgelenmiş "sıradaki hedef" risk notunu gerçek davranış kapsamasına
  çevirme**: üç deneyim-modu kartının veri-odaklı açık/kapalı özellik davranışı.

### Özet ve gerekçe
Keşif (maintainability 100/100; frontend yapısal temiz; seam doctor OK):
`module_startup_screen.R` **#2 en büyük runtime dosyasıydı (740 satır / 6 fonksiyon)**
ve hem refactor-log hem feature-ownership-map'te açık "sıradaki hedef" idi. Dosya
TEK dosyada UI + sunucu mantığını karıştırıyordu: ~380 satırlık monolitik bir saf
UI fonksiyonu (`createStartupScreenUI()`) + ~280 satırlık gözlemci kümesi
(`startupScreenObserversInit()`) + `apply_experience_mode()`. UI içindeki üç deneyim-modu
kartı (Odak/Dinamik/Bütünleşik) ~180 satır boyunca neredeyse birebir tekrar ediyordu
(yalnızca beş özellik göstergesinin açık/kapalı durumu, ikon, başlık farklı).

Repo'da güçlü bir UI/sunucu ayrım deseni mevcut (`module_file_manager_ui.R`,
`module_settings_yapilandirma_ui.R`, `module_claude_code_ui.R`). Aynı desen izlendi:
UI yeni dosyaya alındı ve saf `.startup_*()` alt-yapıcılarına bölündü; üç mod kartı tek
veri-odaklı `.startup_mode_card()` + iki küçük veri tablosu + `.startup_mode_feature_icon()`
ile üretilir (gerçek DRY/karmaşıklık azaltımı, yalnızca satır taşıma değil). Refactor'dan
ÖNCE `createStartupScreenUI()` çıktısı altın referans olarak yakalandı; refactor'dan
SONRA üretilen HTML **byte-birebir aynı** (md5 `5f763a51…`, `identical()` TRUE, diff yok).

### Değişen dosyalar
**Kaynak**
- `R/module_startup_screen_ui.R` (yeni, 407 satır / 14 fonksiyon) — `createStartupScreenUI()`
  ince kompozitör + saf `.startup_*()` yapıcıları (`.startup_intro_music_tag`,
  `.startup_company_logo`, `.startup_version_badge`, `.startup_version_modal`,
  `.startup_branding`, `.startup_explore_button`, `.startup_skip_checkbox`,
  `.startup_mode_modal`, `.startup_character_step`) + veri-odaklı mod-kartı katmanı
  (`.startup_mode_feature_defs`, `.startup_mode_card_defs`, `.startup_mode_feature_icon`,
  `.startup_mode_card`).
- `R/module_startup_screen.R` — **740 → 358 satır** (yalnızca `startupScreenObserversInit`
  + `apply_experience_mode`; UI dosyasına işaret eden yeni başlık).
- `R/config_source_manifest.R` — `module_identity_startup` bölümüne
  `R/module_startup_screen_ui.R`, `R/module_startup_screen.R`'den ÖNCE eklendi
  (11 → 12 dosya; toplam 268 → 269).
- `R/bootstrap_source_manifest.R` — kritik sıra kuralı eklendi:
  `module_startup_screen_ui.R` → `module_startup_screen.R`.
- `R/config_seam_registry.R` — `kimlik_sso` guard_tests listesine yeni split-contract
  testi eklendi (5 → 6).

**Test**
- `tests/testthat/test-startup-screen-ui-refactor-contract.R` (yeni, ~60 assertion) —
  UI/sunucu ayrım sözleşmesi (UI yapıcısı UI dosyasında; sunucu dosyası yapıcıyı
  içermez; manifest sırası UI→sunucu); kart kabuğunun kaynakta TEK kez tanımlanması +
  `lapply(.startup_mode_card_defs(), .startup_mode_card)` ile üretilmesi (kopyalama-yok
  regresyon koruması); `.startup_mode_feature_icon()` açık/kapalı sınıf+ikon+ipucu;
  ÜÇ modun tamamı için kart HTML'inde özellik açık/kapalı ikon/ipucu (Odak hepsi
  kapalı, Bütünleşik hepsi açık, Dinamik karışık).
- `tests/testthat/test-startup-screen-module-behavior.R` — her iki dosyayı da source
  edecek şekilde güncellendi (UI yapıcısı taşındı); mevcut UI/`apply_experience_mode`/
  skip-intro gözlemci testleri korundu.
- `tests/testthat/test-source-manifest-sections-contract.R` — `module_identity_startup`
  n=11→12 ve toplam 268→269 bilinçli güncellendi.
- `tests/testthat/test-maintainability-ratchet.R` — yeni dosya bütçeleri eklendi:
  `module_startup_screen.R` 380/7, `module_startup_screen_ui.R` 430/16 (geri birleşmeyi
  ve büyümeyi kilitler).

**Dokümantasyon**
- `CLAUDE.md` — yeni "Startup screen UI/server split contract" + Group 6 yükleme listesi.
- `docs/feature-ownership-map.md` — SSO/Auth (kimlik_sso) seam'ine açılış UI/sunucu
  dosyaları + iki test eklendi; stale "sıradaki hedef" işaretçileri (Destek + Frontend
  bölümlerindeki `module_startup_screen.R 740` / tamamlanmış admin modülleri) güncellendi.
- `docs/technical-reference.md` — açılış ekranı UI/sunucu ayrımı + bütçe + sözleşme notu.
- `docs/refactor-log.md` — bu giriş.

### Önce / sonra karmaşıklık notları
- Önce: `module_startup_screen.R` 740/6; UI + sunucu tek dosyada; ~380 satırlık
  monolitik UI fonksiyonu; üç mod kartı ~180 satır tekrar.
- Sonra: sunucu dosyası 358 satır (gözlemci-odaklı); UI dosyası 407 satır (kompozitör +
  saf alt-yapıcılar, üç kart tek veri-odaklı yapıcıdan). Skor 100/100; en büyük runtime
  dosyası 758 (settings UI, değişmedi); 800+ satır / 25+ fonksiyon = 0. Açılış ekranı
  at-budget pini KALMADI.

### Korunan davranış sözleşmeleri
- `createStartupScreenUI()` üretilen HTML byte-birebir korundu (altın md5 eşleşti,
  diff yok). Üç mod kartının `data-mode`, beş özellik göstergesi (açık/kapalı sınıf,
  ikon, `data-tooltip`), ikon kutusu, başlık ve kısa metni golden testlerle kilitlendi.
- Sunucu gözlemcileri (skip-intro kararı, Three.js init, deneyim-modu→ayar eşlemesi,
  persona/müzik senkronizasyonu, karakter-medya preload) ve `apply_experience_mode`
  mod tablosu birebir taşındı; davranış testleri korundu.
- DB/SSO/encoding/streaming/UX çalışma-zamanı sözleşmelerine dokunulmadı (saf UI/sunucu
  yeniden yapılandırma).

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- Refactor öncesi/sonrası altın HTML karşılaştırması: `identical()` TRUE, md5
  `5f763a5152d1ad239b0f5c1d8915786a` eşleşti, `diff` boş.
- Odak testler tek tek geçti (0 FAIL / 0 WARN / 0 SKIP): yeni split-contract,
  güncellenen startup-behavior, source-manifest-contract, source-manifest-sections,
  global-source-manifest, maintainability-ratchet, maintainability-ratchet-contract,
  seam-registry-contract, seam-doctor-contract.
- `Rscript tests/scripts/seam_doctor.R` → `SEAM_DOCTOR_RESULT: OK`; `kimlik_sso`
  runtime-dosya 14 → 15, guard-test 5 → 6; sahipsiz dosya yok.
- `Rscript tests/scripts/maintainability_report.R` → skor 100/100; en büyük 758;
  refactor adayı yok.
- `bash tools/ai_validate.sh full --boot-smoke` → **geçti**: environment OK, parse
  sanity OK (820 dosya), **app source smoke OK (7.1s — yeni manifest + ui.R build)**,
  **tam strict testthat suite OK (173.4s)**, shiny boot smoke OK (8.1s);
  `failed_steps: 0`, `skipped_steps: 0`. Artifact:
  `artifacts/ai-validation/20260616-134655/summary.json`
  (`validation_execution_status="ran_by_ai_repo_check"`, profile full/full,
  `app_source_smoke_status="passed"`, `full_testthat_suite_status="passed"`,
  `shiny_boot_smoke_status="passed"`, `browser_smoke_status="skipped"`,
  `db_sso_vm_validation_performed=false`). `logger`/`highcharter` oturum içinde kuruldu.
  Tüm komutlar `LANG=C.UTF-8`.

### Manuel QA (kullanıcı/VM tarafı)
- SSO etkin/devre-dışı başlat; derin uzay giriş ekranının (logo, sürüm rozeti, KEŞFET
  butonu, "Bir daha gösterme", üç deneyim-modu kartı, karakter adımı) eskisi gibi
  render olduğunu doğrulayın.
- Üç modun (Odak/Dinamik/Bütünleşik) kartlarındaki özellik göstergelerinin (sesli yanıt,
  takip, müzik, ses, karakter) açık/kapalı ikon ve ipuçlarının doğru olduğunu doğrulayın.
- KEŞFET → mod seç → (Bütünleşik'te) karakter seç akışının ve "Bir daha gösterme"
  atlama akışının eskisi gibi çalıştığını doğrulayın.

### Bilinen riskler / atlanan doğrulamalar
- VM/SSO/gerçek DB/SQL Server Türkçe encoding/gerçek tarayıcı kanıtı alınmadı
  (bulut oturumu; browser smoke SKIPPED, `db_sso_vm_validation_performed=false`).
  Değişiklik saf UI/sunucu ayrımıdır ve HTML byte-birebir korunduğundan bu kapılar
  bu paket için gerekli değildir; derin uzay Three.js sahnesi ve karakter video akışı
  yalnızca VM/manuel tarayıcıda görsel olarak kanıtlanır.
- Sıradaki paket adayları: `module_settings_yapilandirma_ui.R` (758, en büyük runtime
  dosyası — zaten saf `.syap_*` alt-yapıcılı; yalnızca dosya boyutu) ayrı UI dosyasına
  taşınabilir; ya da `module_image_generation.R` (730/22, iki eksende yakın-bütçe) saf
  yardımcı çıkarımı; ya da frontend tarafında büyük CSS dosyaları (`destek_page.css` 1527,
  `theme_light_core.css` 1148) — ancak CSS bölme görsel regresyon riski taşır ve VM QA ister.

---

## 2026-06-16 — At-budget admin modüllerinin inline renderer'larını *_outputs() dosyalarına çıkarma

### Seçilen iz(ler)
- **Track 1 — En büyük / yakın-bütçe R dosyalarından bütünleşik çıkarım**
  (öncelik #1). İki at-budget admin modülü (`destek_yonetici_saglik` seam) tek pakette.
- **Track 4 — belgelenmiş "sıradaki hedef" risk notunu gerçek davranış kapsamasına
  çevirme** (golden grafik sözleşmeleri).

### Özet ve gerekçe
Önceki paketten sonra en büyük runtime dosyası 760'tı (`module_admin_geri_bildirim.R`)
ve ona yakın `module_admin_yanit_analizi.R` (753) — her ikisi de ratchet'te at-budget
PİN'lenmişti (760/5, 753/4). İkisi de aynı yapıya sahipti: ince bir veri/sekme
orkestrasyon katmanı (zaten helper dosyalarında) üzerine ~700 satırlık inline
highcharter/DT renderer bloğu. `feature-ownership-map.md` "sıradaki hedef" notu
tam olarak bu extraction'ı işaret ediyordu; veri->sunum guardrail'i önceki oturumda
hazırlanmıştı. Repoda zaten 7 admin modülü `admin_*_outputs(output, data_fn, ...)`
desenini kullanıyordu (test edilebilir renderer-kayıt fonksiyonu); büyük modüller
için ayrı dosya örneği `module_admin_hata_analizi.R` → helper dosyaları ayrımıydı.

Her iki modülün renderer bloğu BİREBİR (byte-korumalı) yeni `*_outputs.R` dosyalarına
taşındı; modüller veri/sekme orkestrasyonuna indi. Renderer'lar `JS`,
`admin_turkish_dt_language`, `admin_dt_header_callback`, `admin_format_turkish_date`
gibi global yardımcıları eskisi gibi çağrı anında çözer (globalenv'e source edildikleri
için davranış aynı). Golden davranış testleri seri adı/renk/NPS hesabı/treemap/boş-veri/
refresh-bağımlılığını kilitleyerek grafik sözleşmelerinin korunduğunu KANITLAR.

### Değişen dosyalar
**Kaynak**
- `R/module_admin_geri_bildirim_outputs.R` (yeni, 728 satır / 5 fonksiyon) —
  `admin_gb_outputs(output, gb_data, etiket_sayilari)`: 13 highcharter/DT renderer
  (günlük trend, memnuniyet polar/column/trend, korelasyon, NPS gauge/dağılım/trend/pie,
  etiket treemap/bar, kullanıcı + detay tabloları). Modülden BİREBİR çıkarıldı (CRLF korundu).
- `R/module_admin_geri_bildirim.R` — **760 → 55 satır** (veri reaktifleri + sekme
  yönlendirici + `admin_gb_outputs(...)` çağrısı).
- `R/module_admin_yanit_analizi_outputs.R` (yeni, 678 satır / 3 fonksiyon) —
  `admin_yanit_outputs(output, ya_data, etiket_sayilari, refresh)`: 13 renderer.
  `ya_saat_gun_heatmap`/`ya_saatlik_chart` `refresh$trigger()` bağımlılığı için
  `refresh` parametresi alır.
- `R/module_admin_yanit_analizi.R` — **753 → 106 satır** (UI + veri/sekme orkestrasyonu
  + `admin_yanit_outputs(...)` çağrısı).
- `R/config_source_manifest.R` — `module_admin` bölümüne iki `*_outputs` dosyası
  ilgili modülden ÖNCE eklendi (19 → 21 dosya; toplam 266 → 268).
- `R/config_seam_registry.R` — `destek_yonetici_saglik` seam guard_tests listesine
  iki yeni golden behavior testi eklendi (5 → 7).

**Test**
- `tests/testthat/test-admin-geri-bildirim-outputs-behavior.R` (yeni, 6 test) —
  golden grafik sözleşmesi: çift-eksenli trend (column #06b6d4 + spline #f59e0b),
  5-seviye memnuniyet pastası (Türkçe etiket + renk + cnt eşleme), NPS solid gauge
  hesabı ((promoter-detractor)/toplam*100 = 45, sarı eşik), etiket treemap, boş-veri
  korumaları, kullanıcı tablosu.
- `tests/testthat/test-admin-yanit-analizi-outputs-behavior.R` (yeni, 6 test) —
  areaspline trend (30-gün pencere, Beğeni yeşil/Beğenmeme kırmızı), tip pastası
  (like/dislike → Türkçe + renk), model bar (oran sırası), etiket treemap, refresh-bağımlı
  saat-gün ısı haritası (trigger() sayacı kontrolü), boş-veri korumaları.
- `tests/testthat/test-admin-geri-bildirim-refactor-contract.R` /
  `test-admin-yanit-analizi-refactor-contract.R` — yeni `*_outputs` dosyası varlığı +
  `admin_*_outputs` tanımı + modülün çağrı yapması + modülde artık `renderHighchart`/
  `renderDT` olmaması + 13 output ID'sinin outputs dosyasında bulunması + manifest sırası
  (outputs → module) eklendi.
- `test-source-manifest-sections-contract.R` — `module_admin` çapası (n=19→21) ve
  toplam (266 → 268) güncellendi.
- `test-maintainability-ratchet.R` — modül bütçeleri sıkılaştırıldı (geri_bildirim
  760/5 → 90/3, yanit 753/4 → 140/4; dedicated env defaultları da 799→90 / 799→140);
  yeni `*_outputs` dosyaları için 760/6 ve 710/5 bütçeleri eklendi.

**Dokümantasyon**
- `CLAUDE.md` — Admin Feedback/Yanıt Analizi modularization sözleşmeleri (kaynak
  sırası + sorumluluklar + bütçeler + testler) + Group 6 admin yükleme listesi güncellendi.
- `docs/feature-ownership-map.md` — Destek/Geri Bildirim seam'i: outputs dosyaları +
  golden testler eklendi; at-budget risk notu "KALMADI" olarak güncellendi.
- `docs/technical-reference.md` — Geri Bildirim/Yanıt Analizi outputs extraction notu +
  bütçe eşikleri güncellendi.
- `docs/refactor-log.md` — bu giriş.

### Önce / sonra karmaşıklık notları
- Önce: iki at-budget modül 760/753 satır; her biri ~700 satır inline renderer
  + ince veri/orkestrasyon; küresel max-file-length metriğini ve ratchet pinlerini
  süren dosyalar.
- Sonra: modüller 55/106 satır (orkestrasyon-odaklı); renderer'lar 728/678 satırlık
  tek-sorumluluk dosyalarında (düz, bağımsız renderer listeleri — düşük cyclomatic
  karmaşıklık), dosya-özel bütçelerle kilitli. **Küresel en büyük runtime dosyası
  760 → 758 satıra indi** (yeni en büyük `module_settings_yapilandirma_ui.R`, mevcut).
  Değerlendirilen dosya 272 → 274; skor 100/100; 800+ satır / 25+ fonksiyon = 0.
  At-budget admin pini KALMADI.

### Korunan davranış sözleşmeleri
- 26 renderer'ın (13+13) gövdeleri BİREBİR taşındı (byte-korumalı; CRLF/LF native
  korundu). Seri adları, renk paletleri, NPS hesabı, treemap/pie/areaspline veri
  eşlemeleri, boş-veri korumaları, `refresh$trigger()` bağımlılıkları ve Türkçe
  etiketler golden testlerle kanıtlandı (highcharter kuruluyken gerçekten KOŞTU).
- Bare global yardımcılar (`JS`, `admin_turkish_dt_language`, `admin_dt_header_callback`,
  `admin_format_turkish_date`, `admin_turkish_days`) çağrı anında eskisi gibi çözülür;
  veri reaktifleri (`gb_data`/`ya_data`/`etiket_sayilari`) ve `refresh` argüman olarak geçer.
- Helper/UI ayrım sözleşmeleri (mevcut refactor-contract'lar) bozulmadan geçti.
- DB/SSO/encoding/streaming/UX sözleşmelerine dokunulmadı.

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- İki golden behavior testi (6+6) highcharter KURULUYKEN tek tek geçti
  (0 FAIL / 0 WARN / 0 SKIP) — grafik sözleşmeleri gerçekten doğrulandı, atlanmadı.
- İki refactor-contract (6+5), query-contract (3), veri->sunum behavior (6),
  maintainability-ratchet (12), source-manifest-sections (4), source-manifest-contract (11),
  global-source-manifest (6) → tümü 0 FAIL / 0 WARN.
- `Rscript tests/scripts/maintainability_report.R` → skor 100/100; 274 dosya;
  en büyük 758; refactor adayı yok.
- `Rscript tests/scripts/seam_doctor.R` → `SEAM_DOCTOR_RESULT: OK`; `destek_yonetici_saglik`
  runtime-dosya 42 → 44 (iki yeni dosya sahipli); sahipsiz dosya yok.
- `bash tools/ai_validate.sh full --boot-smoke` → **geçti**: environment OK, parse
  sanity OK, **app source smoke OK (5.5s — yeni manifest boot'ta yükleniyor)**,
  **tam strict testthat suite OK (161.0s; highcharter kurulu olduğundan tüm chart
  testleri KOŞTU)**, shiny boot smoke OK (7.2s); `failed_steps: 0`, `skipped_steps: 0`.
  Artifact: `artifacts/ai-validation/20260616-092004/summary.json`
  (`validation_execution_status="ran_by_ai_repo_check"`, profile full/full,
  `app_source_smoke_status="passed"`, `shiny_boot_smoke_status="passed"`,
  `browser_smoke_status="skipped"`, `db_sso_vm_validation_performed=false`).
  `highcharter` ve `logger` paketleri oturum içinde CRAN'dan kuruldu. Tüm komutlar `LANG=C.UTF-8`.

### Manuel QA (kullanıcı/VM tarafı)
- Yönetici Paneli → Geri Bildirim Analizi: Genel Bakış / Memnuniyet / NPS / Etiket &
  İçerik sekmelerindeki tüm grafiklerin ve tabloların eskisi gibi render olduğunu doğrulayın.
- Yönetici Paneli → Yanıt Geri Bildirimi Analizi: Genel Bakış / Model Performansı /
  Etiket & Yorum / Zaman & Kullanıcı sekmelerindeki grafik/tabloları doğrulayın.
- Yenile butonunun saat-gün ısı haritası ve saatlik grafikleri güncellediğini doğrulayın.
- Davranış değişmedi; test grafik sözleşmelerini kilitler.

### Bilinen riskler / atlanan doğrulamalar
- VM/SSO/gerçek DB/SQL Server Türkçe encoding/gerçek tarayıcı kanıtı alınmadı
  (bulut oturumu; browser smoke SKIPPED). Renderer'lar grafik motoruna (highcharter)
  bağlı; golden testler highcharter ile gerçek render JSON'ını doğruladı ama canlı
  tarayıcıda görsel render yalnızca VM/manuel QA'da kanıtlanır.
- Yeni `*_outputs` dosyaları büyük (728/678) ama tek-fonksiyon flat renderer listeleridir
  (düşük öncelik). İstenirse tab bazında (overview/memnuniyet/nps/etiket) daha da
  bölünebilir; bu pakette tek `*_outputs` dosyası (paket hedefi) tercih edildi.
- Sıradaki paket adayı: bu seam dışında `module_settings_yapilandirma_ui.R` (758) ve
  `module_startup_screen.R` (740) yakın-bütçe UI dosyaları; ya da frontend complexity
  doctor'daki duplike CSS selector temizliği.

---

## 2026-06-16 — Frontend bölge yönetişim katmanının VERİ/DOĞRULAYICI ayrımı (en büyük runtime dosyasını düşür)

### Seçilen iz(ler)
- **Track 1 — En büyük / yakın-bütçe R dosyasından bütünleşik (saf) yardımcı
  çıkarımı** (öncelik #1) + **Track 3 — yükleme sırası/manifest/bölge sahipliği
  yönetişimini sağlamlaştırma** (öncelik #3). `frontend_varlik` seam'inde tek paket.

### Özet ve gerekçe
Keşif (maintainability 100/100, frontend temiz, seam doctor OK): `R/config_ui_asset_zones.R`
**en büyük runtime dosyasıydı (777 satır)** — küresel `max-file-length` metriğini
süren ve 800-satır tavanının 23 satır altındaki en net "yakın bütçe" sinyali.
Dosya doğal olarak iki sorumluluğa ayrılıyordu: (a) SAF VERİ — iki sahiplik
haritası (`ui_asset_ownership_zones` 23 bölge + `ui_asset_unmanifested_ownership`),
(b) bölge çözümleme + bölümleme (partition) DOĞRULAMA API'si (8 adlandırılmış saf
fonksiyon). Kritik gözlem: bu fonksiyonlar runtime UI render'ında (`ui_asset_validate`)
HİÇ çağrılmaz — yalnızca seam doctor ve sözleşme testleri kullanır; bu da ayırmayı
davranış-koruyan ve sıfır-runtime-riskli kılar. Ayrım, repoda zaten var olan
`config_source_manifest.R` (veri) + `bootstrap_source_manifest.R` (doğrulayıcı)
desenini birebir izler.

### Değişen dosyalar
**Kaynak**
- `R/config_ui_asset_zone_validators.R` (yeni, 312 satır / 10 fonksiyon) — 8
  adlandırılmış erişimci/doğrulayıcı + 2 anonim `error = function(e)` handler'ı
  birebir taşındı; veri nesnelerine tembel-değerlendirilen varsayılan argümanlarla
  referans verir (çağrı anında aynı ortamda görünür).
- `R/config_ui_asset_zones.R` — fonksiyon bloğu fiziksel olarak kesilerek
  (head -n 491; veri byte-korumalı) SADECE veriye indirildi; başlık VERİ/DOĞRULAYICI
  ayrımını belgeler. **777/10 → 502/0** (artık fonksiyon içermez).
- `R/config_source_manifest.R` — `config_ui_assets` bölümüne yeni dosya
  `config_ui_asset_zones.R`'den HEMEN SONRA eklendi (2 → 3 dosya; toplam 265 → 266).
- `R/config_seam_registry.R` — `frontend_varlik` seam guard_tests listesine yeni
  split-contract testi eklendi (7 → 8 guard test).

**Test**
- `tests/testthat/test-ui-asset-zone-validators-split-contract.R` (yeni, 5 test) —
  yeni dosya varlığı + 8 fonksiyon yüzeyi, manifest sırası (veri → doğrulayıcı),
  veri dosyasının SADECE veri olması (hiç `<- function(` yok), doğrulayıcı dosyasının
  veriyi yeniden tanımlamaması, ve **bölme sonrası bölümleme korunumu**
  (`ui_asset_zones_validate()` gerçek manifeste karşı `character(0)` döner).
- 5 source noktası yeni dosyayı da yükler: `tests/scripts/seam_doctor.R`,
  `test-ui-asset-zones-contract.R`, `test-seam-registry-contract.R`,
  `test-seam-doctor-contract.R` (+ required_tokens), `test-misc-runtime-predicates-behavior.R`
  (`.miscPredicatesSource` çok-yollu hale getirildi; `ui_asset_zone_get` artık
  doğrulayıcı dosyada).
- `test-source-manifest-sections-contract.R` — `config_ui_assets` çapası
  (last/n=2→3) ve toplam kaynak sayısı (265 → 266) bilinçli güncellendi.
- `test-maintainability-ratchet.R` — `config_ui_asset_zones.R` 790/12 → **550/2**
  (veri dosyası ~0 fonksiyonda kilitli; runtime mantık sızması erken yakalanır);
  `config_ui_asset_zone_validators.R` için **360/12** bütçesi eklendi. Geri
  birleşme kilitlenir.

**Dokümantasyon**
- `CLAUDE.md` — seam/zone yönetişim sözleşmesinde VERİ/DOĞRULAYICI ayrımı + manifest
  yükleme şekli (3 dosya) + yeni test güncellendi.
- `docs/architecture-map.md` — yönetişim tablosuna yeni doğrulayıcı dosyası satırı.
- `docs/technical-reference.md` — frontend bölge katmanı VERİ + DOĞRULAYICI notu.
- `docs/feature-ownership-map.md` — yeni "Frontend Varlık ve Yönetişim" bölümü.
- `docs/refactor-log.md` — bu giriş.

### Önce / sonra karmaşıklık notları
- Önce: `config_ui_asset_zones.R` 777/10 — en büyük runtime dosyası; küresel
  max-file-length metriğini sürüyor; veri + doğrulama mantığı tek dosyada karışık.
- Sonra: veri dosyası 502/0 (SADECE veri, fonksiyon yok), doğrulayıcı 312/10;
  her ikisi dosya-özel bütçeyle kilitli. **Küresel en büyük runtime dosyası
  777 → 760 satıra indi** (yeni en büyük `module_admin_geri_bildirim.R`).
  Değerlendirilen dosya 271 → 272; skor 100/100 korunur; 800+ satır / 25+ fonksiyon
  dosya sayısı 0 kalır.

### Korunan davranış sözleşmeleri
- 8 fonksiyonun gövdeleri, varsayılan argümanları, `error = function(e)` düşüşleri
  ve `optional_in_checkout` (yalnızca on-prem VM dosyaları) doğrulama mantığı
  birebir aynı; veri (23 bölge + manifest dışı kayıt) byte-korumalı taşındı.
- `ui_asset_validate()` (runtime UI render) bu fonksiyonları HİÇ çağırmaz; yükleme
  sırasının tek sahibi `R/config_ui_assets.R` kalır. Bölme sonrası bölümleme
  korunumu test ile kanıtlandı (`ui_asset_zones_validate()` → `character(0)`).
- DB/SSO/encoding/streaming/UX sözleşmelerine dokunulmadı.

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- Odak testler tek tek geçti (0 FAIL / 0 WARN / 0 SKIP): yeni split-contract (5),
  ui-asset-zones-contract (8), ui-asset-manifest-contract (6),
  misc-runtime-predicates (4), source-manifest-sections (güncel), source-manifest-contract (11),
  seam-registry-contract, seam-doctor-contract (2), global-source-manifest (6),
  maintainability-ratchet.
- `Rscript tests/scripts/seam_doctor.R` → `SEAM_DOCTOR_RESULT: OK`; `frontend_varlik`
  runtime-dosya 2 → 3 (yeni dosya sahipli), guard-test 7 → 8; sahipsiz dosya yok.
- `Rscript tests/scripts/maintainability_report.R` → skor 100/100; 272 dosya;
  en büyük dosya 760 satır; refactor adayı yok.
- `bash tools/ai_validate.sh full --boot-smoke` → **geçti**: environment OK,
  parse sanity OK, **app source smoke OK (5.8s — yeni manifest boot'ta yükleniyor)**,
  **tam strict testthat suite OK (139.5s)**, shiny boot smoke OK (6.9s);
  `failed_steps: 0`, `skipped_steps: 0`. Artifact:
  `artifacts/ai-validation/20260616-084950/summary.json`
  (`validation_execution_status="ran_by_ai_repo_check"`, profile full/full,
  `app_source_smoke_status="passed"`, `shiny_boot_smoke_status="passed"`,
  `browser_smoke_status="skipped"` — konteynerde tarayıcı yok,
  `db_sso_vm_validation_performed=false`). `logger` paketi oturum içinde kuruldu.
  Tüm komutlar `LANG=C.UTF-8`.

### Manuel QA (kullanıcı/VM tarafı)
- Bu yalnızca yönetişim (governance) veri/doğrulayıcı ayrımıdır; runtime UI render
  yolunu DEĞİŞTİRMEZ. Özel kullanıcı-tarafı QA gerekmez; yine de uygulama açılışı
  sonrası tüm sayfaların (frontend varlıkları) eskisi gibi yüklendiği doğrulanabilir.

### Bilinen riskler / atlanan doğrulamalar
- VM/SSO/gerçek DB/SQL Server Türkçe encoding/gerçek tarayıcı kanıtı alınmadı
  (bulut oturumu; `db_sso_vm_validation_performed=false`, browser smoke SKIPPED).
  Değişiklik yapısal yönetişim/manifest ayrımıdır; runtime davranışı değişmedi,
  bu yüzden bu kapılar bu paket için gerekli değildir ama tam VM kanıtı vermez.
- Sıradaki paket adayları: at-budget admin modülleri `module_admin_geri_bildirim.R`
  (760/5) ve `module_admin_yanit_analizi.R` (753/4) inline chart renderer'larını
  `*_outputs()` desenine taşıyıp at-budget pininden indirmek (veri->sunum
  guardrail'i mevcut; chart kontratları VM görsel QA ister). Frontend tarafında:
  duplike CSS selector temizliği (frontend complexity doctor raporu) tek zone'da
  toplanabilir.

---

## 2026-06-16 — Yanıt Analizi veri->sunum katmanının davranışsal kapsanması (at-budget modül için guardrail)

### Seçilen iz(ler)
- **Track — Belgelenmiş kapsama boşluğunun deterministik teste çevrilmesi**
  (öncelik #4). `destek_yonetici_saglik` seam'inde Yanıt Geri Bildirimi Analizi
  veri/sunum yardımcıları davranışsal olarak kapatıldı.

### Özet ve gerekçe
Keşif: skor 100/100, frontend temiz, seam doctor OK. Küresel 24-fonksiyon tavanını
tutan iki dosya belgeli "yoğun-tasarım" + farklı seam (bölme = düşük değerli churn).
At-budget dosyalar `module_admin_yanit_analizi.R` (753/753) ve
`module_admin_geri_bildirim.R` (760/760) en net "yakın bütçe" sinyaliydi (öncelik #1);
ancak bunları küçültmek inline chart renderer'ları ayrı dosyaya taşımayı gerektiriyor —
chart kontratları (seri/renk/Türkçe etiket) VM görsel QA ister ve `*_outputs()` desenli
TÜM admin modülleri zaten kapsanmış, kalan modüllerde ayrılmış outputs fonksiyonu YOK.
Bulut oturumunda bu extraction yüksek riskli olduğundan, KONTROLLÜ ve TAMAMEN ADDITIVE
bir alt-paket seçildi: at-budget Yanıt Analizi modülünün veri->sunum katmanını kapsamak.

`R/helpers_admin_yanit_analizi.R` içinde `admin_yanit_collect_data` (17 MB_Feedback
sorgusu toplayıcı) ve `admin_yanit_overview_ui` (beğeni/yorum oranı hesabı + N/A
korumaları + Türkçe metrik kartları) davranışsal olarak SINANMAMIŞTI — kardeş
`admin_gb_fetch_data` ise query-contract testine sahip (asimetrik boşluk). Bu paket
o boşluğu kapatır ve gelecekteki renderer-extraction refactor'ü için guardrail kurar.

### Değişen dosyalar
**Test (yeni)**
- `tests/testthat/test-admin-yanit-data-presentation-behavior.R` (25 assertion) —
  izole env'e `utils_common.R` + `helpers_admin_yanit_analizi.R` source; admin
  helper'ları (`admin_create_metric_card`/`admin_format_number`/`admin_create_info_button`)
  env'de stub'lanır, `safe_query` mock'lanır. Kapsanan: collect_data 17-anahtar +
  safe_query çağrı sözleşmesi + kilit SQL çapaları (MB_Feedback, 30-gün filtre +
  MB_Messages JOIN, like/dislike ayrımı, FeedbackTags); overview_ui %.1f%% oran
  hesabı (150/200=75.0%, 80/200=40.0%), toplam=0 ve boş-çerçeve N/A korumaları,
  altı Türkçe metrik kartı etiketi.

**Dokümantasyon**
- `docs/feature-ownership-map.md` — Destek/Geri Bildirim seam'ine Yanıt Analizi
  modül/helper'ı ve yeni test eklendi; "sıradaki hedef" notu at-budget renderer
  extraction guardrail'ine güncellendi.
- `docs/refactor-log.md` — bu giriş.

### Önce / sonra karmaşıklık notları
- Önce: Yanıt Analizi veri toplama + genel-bakış metrik hesabı (kullanıcıya görünür
  oranlar/sayılar) davranışsal olarak sınanmamıştı; yalnızca yapısal refactor-contract
  vardı. Kardeş geri_bildirim'in query-contract'ı varken yanit'ınki yoktu.
- Sonra: 17-sorgu sözleşmesi + oran/N-A/etiket hesabı 25 assertion ile deterministik
  (offline) kilitli. Runtime kodu/satır/fonksiyon değişmedi (skor 100/100 korunur).

### Korunan davranış sözleşmeleri
- Hiçbir runtime R kodu değişmedi; `admin_yanit_collect_data`/`admin_yanit_overview_ui`
  davranışı testlerle kilitlendi, değiştirilmedi.
- Türkçe metrik etiketleri (Toplam Geri Bildirim, Beğeni Oranı, Beğeni, Beğenmeme,
  Bugün Gelen, Yorum İçeren) ve oran formülleri (begeni/toplam, yorumlu/toplam)
  birebir doğrulandı.

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- Yeni test tek başına: 25 pass / 0 fail / 0 warn / 0 skip (highcharter kuruluyken;
  kurulu değilken overview_ui dalları zaman_analizi vb. ile aynı `skip_if_not_installed`
  desenini izler).
- `bash tools/ai_validate.sh full --boot-smoke` → geçti: parse sanity, app source
  smoke, **tam strict testthat suite 185.0s** (highcharter kurulu olduğundan önceden
  skip edilen tüm chart testleri DE koştu), shiny boot smoke; `failed_steps: 0`,
  `skipped_steps: 0`. Artifact: `artifacts/ai-validation/20260616-050445/summary.json`.
- `logger` ve `highcharter` paketleri oturum içinde CRAN'dan kuruldu (CI required
  paket listesinde değiller; VM'de renv.lock ile mevcut). Tüm komutlar `LANG=C.UTF-8`.

### Manuel QA (kullanıcı/VM tarafı)
- Yönetici Paneli → Yanıt Geri Bildirimi Analizi → Genel Bakış: metrik kartlarının
  (Toplam, Beğeni Oranı, Beğeni, Beğenmeme, Bugün, Yorum İçeren) doğru sayı/oranları
  ve Türkçe etiketleri gösterdiğini, geri bildirim yokken N/A geldiğini doğrulayın
  (davranış değişmedi; test mevcut davranışı kilitler).

### Bilinen riskler / atlanan doğrulamalar
- Additive test paketi; runtime davranışı değişmedi. Chart renderer'lar (highcharter
  çıktıları) bu pakette KAPSANMADI — onların kapsanması için renderer'ların ayrı
  `admin_yanit_outputs()` dosyasına taşınması (at-budget modülü küçülten refactor)
  gerekir; bu chart kontratları için VM görsel QA gerektirir ve ayrı oturuma bırakıldı.
- VM/SSO/gerçek DB/SQL Server Türkçe encoding/gerçek tarayıcı kanıtı alınmadı.
- Sıradaki paket adayı: `module_admin_yanit_analizi.R` (ve `module_admin_geri_bildirim.R`)
  inline renderer'larını `*_outputs()` desenine taşıyıp at-budget pininden indirmek
  (artık veri->sunum guardrail'i mevcut; chart-data prep için golden before/after
  ve outputs-behavior testi ile de-risk edilebilir).

---

## 2026-06-16 — validate_api_key uç-nokta doğrulama dallarının davranışsal kapsanması (belgeli boşluğu kapat)

### Seçilen iz(ler)
- **Track — Belgelenmiş "bilinen risk" boşluğunun deterministik teste çevrilmesi**
  (öncelik #4 + #6). `api_anahtar_model` seam'inin `docs/feature-ownership-map.md`
  "sıradaki hedef" notu olan `validate_api_key`/`derive_models_url` httr-mock
  kapsaması ele alındı.

### Özet ve gerekçe
Keşif: maintainability skoru 100/100, frontend yapısal olarak temiz (legacy
selector/sahipsiz varlık yok), seam doctor OK. Yapısal öncelikler (#1-#3)
büyük ölçüde çözülmüş; küresel 24-fonksiyon tavanını tutan iki dosya
(`helpers_file_manager_runtime.R`, `helpers_health_formatters.R`) belgeli
"yoğun-tasarım" kararı ve farklı seam'lerde olduğundan bölme = düşük değerli
churn olurdu (skor zaten 100). `feature-ownership-map.md` "Bilinen risk /
sıradaki hedef" notları (yönerge bunları tercih etmemi söylüyor) çoğunlukla
davranış-kapsama boşluklarını işaret ediyordu.

`R/config_api.R::validate_api_key()` — kişisel API anahtarı "Doğrula" akışının
çekirdeği (kullanıcıya görünür) — DEDİKE davranış testi yoktu; yalnızca yapısal
split sözleşmesinde anılıyordu. Fonksiyon zengin dallı (boş anahtar, `/v1/models`
URL türetme, model-listesi GET 200/401/403/429/500, sağlık uç noktası, sohbet
ping POST 200/401/429/hata, endpoint tanımsız) ve tamamı httr-mock'lanabilir.
`derive_models_url` iç closure'u, mock'lanan `GET`'e geçen URL yakalanarak DOLAYLI
sınandı. Bu paket TAMAMEN ADDITIVE'dir: çalışma zamanı R kodu DEĞİŞMEDİ; gerçek
bir bug bulunmadı (test doğru davranışı kilitler). Bu da onu bulut oturumu için
düşük riskli ve uygun kılar (VM/SSO/DB/tarayıcı kanıtı gerekmez).

### Değişen dosyalar
**Test (yeni)**
- `tests/testthat/test-config-api-validate-api-key-behavior.R` (37 assertion) —
  kanıtlanmış config_api bootstrap deseni (placeholder env + vision/deep-thinking
  guard'lı + `config_api.R` globalenv'e guard'lı source); `httr` GET/POST/status_code
  `local_mocked_bindings(.package="httr")` ile mock'lanır; URL yakalama ile
  `derive_models_url` dolaylı doğrulanır. Sahte anahtar (`gecersiz-test-anahtari`,
  gerçek önek yok) ile secret-safe.

**Dokümantasyon**
- `docs/feature-ownership-map.md` — API seam Testler listesine yeni dosya eklendi;
  "Bilinen risk / sıradaki hedef" notu opsiyonel boşluktan "kapsandı"ya güncellendi
  (öncelik #6: artık doğru olmayan risk notu temizlendi).
- `docs/refactor-log.md` — bu giriş.

### Önce / sonra karmaşıklık notları
- Önce: `validate_api_key` (kullanıcıya görünür anahtar doğrulama) yalnızca yapısal
  split sözleşmesinde anılıyordu; uç-nokta doğrulama dalları davranışsal olarak hiç
  sınanmamıştı; `feature-ownership-map.md` bunu "opsiyonel" boşluk olarak belgeliyordu.
- Sonra: 14 dal/durum 37 assertion ile deterministik (offline, httr-mock) kilitli;
  belgeli boşluk kapatıldı. Runtime kodu/satır/fonksiyon sayıları değişmedi
  (skor 100/100 korunur).

### Korunan davranış sözleşmeleri
- Hiçbir runtime R kodu değişmedi; `validate_api_key`/`derive_models_url` davranışı
  testlerle kilitlendi, değiştirilmedi.
- Secret safety: yalnızca sahte anahtar kullanıldı; gerçek anahtar/önek loglanmadı,
  yazılmadı (`test-secret-leak-contract.R` geçer).

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- Yeni test tek başına: 37 pass / 0 fail / 0 warn / 0 skip.
- Komşu config_api/api-key testleriyle AYNI oturumda (globalenv config_api.R
  source çapraz-bulaşma kontrolü): yeni test + config-api-split (36) +
  crypto (32) + reasoning-overrides (14) + api-model-config (35) +
  endpoint-resolution (41) + ai-feature-api-key (13) + deep-thinking (28) →
  TOTAL 0 fail / 0 warn.
- `test-secret-leak-contract.R` (8) + `test-log-redact-default-api-key-behavior.R` (4)
  → 0 fail/warn (sahte anahtar fixture'ı secret tarayıcısını tetiklemez).
- `Rscript tests/scripts/parse_sanity_check.R` → 811 dosya OK.
- `Rscript tests/scripts/maintainability_report.R` → skor 100/100; runtime
  dosya/fonksiyon değişmedi.
- `bash tools/ai_validate.sh full --boot-smoke` → (aşağıdaki commit'te artifact).

### Manuel QA (kullanıcı/VM tarafı)
- Yapılandırma → kişisel API anahtarı girip "Doğrula"ya basın; geçerli anahtarda
  "doğrulandı", geçersizde "reddedildi" mesajının eskisi gibi geldiğini doğrulayın
  (davranış değişmedi; test yalnızca mevcut davranışı kilitler).

### Bilinen riskler / atlanan doğrulamalar
- Additive test paketi; runtime davranışı değişmedi. Gerçek LLM/sağlık uç noktası
  yanıtları yalnızca VM/canlı ortamda kanıtlanır (testler httr'yi mock'lar).
- VM/SSO/gerçek DB/SQL Server Türkçe encoding/gerçek tarayıcı kanıtı bu oturumda
  alınmadı (bulut oturumu; kapsam dışı).
- Sıradaki paket adayları: yapısal tarafta küresel fonksiyon-tavanı dosyaları
  (belgeli yoğun-tasarım — ayrı karar gerektirir); kapsama tarafında
  `.ai/next-session-test-coverage-prompt.md` aktif workstream'inin dal/şube
  hedefleri (`cc_policy_validate_workdir`, SSO fail-closed derin dallar,
  `sendMessageInit` mod-dispatch).

---

## 2026-06-15 — AI Uzman sunucu işleyicilerinden saf karar yardımcılarının ayrılması (yakın-bütçe handler küçültme)

### Seçilen iz(ler)
- **Track B — Complex runtime kodundan saf yardımcı çıkarımı**
  (`R/server_ai_expert_handlers.R` → yeni `R/helpers_ai_expert_handlers_support.R`).
- Aynı risk alanı (`medya_ses` / AI Uzman seam) içinde 3-4 bütünleşik saf
  karar çıkarımı tek pakette toplandı.

### Özet ve gerekçe
`docs/feature-ownership-map.md` "sıradaki hedef" notu ve keşif raporları
`R/server_ai_expert_handlers.R`'yi (726 satır / 23 fonksiyon) işaret ediyordu:
dosya küresel 24-fonksiyon tavanının BİR ALTINDAydı; herhangi bir küçük AI Uzman
eklemesi tavanı zorlayacaktı. Dosyada üç senaryo (karşılama / sayfa rehberliği /
boşta konuşma) için tekrarlayan SAF karar mantığı vardı: iki ayrı yerde aynı
sayfa→Türkçe ad `switch` haritası, iki sıklık→ms `switch` sarmalayıcısı ve ~44
satırlık boşta konuşma bağlam metni kurulumu. Bunların hiçbiri Shiny/DB/LLM
başlatmadan test edilemiyordu.

Dört saf yardımcı yeni `R/helpers_ai_expert_handlers_support.R` dosyasına alındı:
`ai_expert_page_name_tr()` (iki kopya sayfa haritasını tek kaynağa indirir),
`ai_expert_first_idle_delay_ms()` / `ai_expert_idle_interval_ms()` (sıklık→ms),
`build_ai_expert_idle_user_context()` (boşta bağlam metni, `Sys.time()` yerine
dışarıdan `now_text` alır → deterministik). Handler aynı orkestrasyona odaklı
kaldı. **VM-only async yol (üç `tracked_future_promise(call_ai_expert_llm)`
bloğu) BİLEREK ELLENMEDİ**: worker globals export davranışı yalnızca VM'de
kanıtlanır ve cloud'da doğrulanamaz; gereksiz regresyon riski alınmadı.

### Değişen dosyalar
**Kaynak**
- `R/helpers_ai_expert_handlers_support.R` (yeni, 144 satır / 5 fonksiyon) — dört
  saf karar yardımcısı + bir özel sıklık normalizasyonu; Shiny/DB/ağ/worker yan
  etkisi yok. Türkçe etiketler birebir korundu.
- `R/server_ai_expert_handlers.R` — iki sıklık sarmalayıcısı `current_talk_frequency()`
  + saf helper çağrılarına, iki sayfa haritası tek `ai_expert_page_name_tr()`
  çağrısına, boşta bağlam bloğu `build_ai_expert_idle_user_context()` çağrısına
  indirildi. **726 → 652 satır / 23 → 22 fonksiyon.**
- `R/config_source_manifest.R` — yeni dosya `ai_expert_helpers` bölümü sonuna
  (handler'dan çok önce yüklenecek şekilde) eklendi (3 → 4 dosya; toplam 264 → 265).

**Test**
- `tests/testthat/test-ai-expert-handlers-support-behavior.R` (yeni, ~57 assertion)
  — sayfa adı (bilinen/chat/bilinmeyen/geçersiz), sıklık→ms (az/orta/sik/varsayılan),
  boşta bağlam (taban/departman+müdürlük/birim/müdürlük-boş düşüş/200-120 kırpma/
  tam birleşim/NULL girişler) davranışı.
- `tests/testthat/test-ai-expert-handlers-support-contract.R` (yeni, 16 assertion)
  — yeni dosya varlığı + yüzey, manifest sırası (helper → handler), taşınan
  mantığın handler'a geri dönmemesi, handler'ın yeni yardımcıları çağırması,
  helper'ın Shiny/DB/ağ-bağsızlığı.
- `tests/testthat/test-ai-expert-page-guidance-stale-behavior.R` — izole env yeni
  support dosyasını da source eder (handler artık `ai_expert_page_name_tr` çağırır;
  3 assertion değişmeden geçer).
- `tests/testthat/test-source-manifest-sections-contract.R` — `ai_expert_helpers`
  çapası (last/n=4) ve toplam (264 → 265) bilinçli güncellendi.
- `tests/testthat/test-maintainability-ratchet.R` — `server_ai_expert_handlers.R`
  bütçesi 726/23 → **660/22** sıkılaştırıldı; yeni dosya için 180L/8F bütçesi eklendi.

**Dokümantasyon**
- `CLAUDE.md` — Group 4 yükleme listesine yeni dosya eklendi.
- `docs/architecture-map.md`, `docs/feature-ownership-map.md`,
  `docs/technical-reference.md` — sahiplik/sıradaki hedef satırları güncellendi.
- `docs/refactor-log.md` — bu giriş.

### Önce / sonra karmaşıklık notları
- Önce: `server_ai_expert_handlers.R` 726/23 — küresel fonksiyon tavanının bir
  altında; sayfa haritası iki kopya; boşta bağlam ve sıklık mantığı Shiny
  observer gövdesine gömülü, test edilemez.
- Sonra: handler 652/22 (tavandan iki altında, gerçek baş boşluk); saf karar
  mantığı bağımsız, deterministik test edilebilir dosyada; her iki dosya da
  dosya-özel bütçeyle kilitli. Maintainability skoru 100/100 korunur; değerlendirilen
  dosya 270 → 271. Küresel 24-fonksiyon değeri sıkılaştırılMAdı (tavanı hâlâ
  `helpers_file_manager_runtime.R` / `helpers_health_formatters.R` tutuyor).

### Korunan davranış sözleşmeleri
- Üç senaryo LLM çağrı bloğu (`tracked_future_promise` + `call_ai_expert_llm` +
  globals export) ve promise zincirleri birebir aynı; worker dependency export
  yolu DEĞİŞMEDİ.
- Sayfa adı eşlemesi: `ai_expert_page_name_tr("chat")` → "Ana Söyleşi", bilinen
  sekmeler → aynı Türkçe etiketler, bilinmeyen → NULL. Sayfa rehberliği yolu
  "chat"a hiç ulaşmaz (erken dönüş korunur); boşta yol `%||% "Ana Söyleşi"` ile
  aynı varsayılanı verir.
- Sıklık→ms değerleri (30000/20000/12000 ve 60000/35000/20000), boşta bağlam
  metninin tüm Türkçe cümleleri, 200/120 karakter kırpma ve `\n\n` birleştirme
  birebir korundu (`now_text` dışarıdan verilir).
- DB/SSO/frontend/UX/streaming sözleşmelerine dokunulmadı.

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- Odak testler tek tek geçti (0 FAIL / 0 WARN / 0 SKIP): yeni davranış,
  yeni split sözleşmesi (16), page-guidance-stale (3), db-fetch (20),
  prompt-builders (30), call-llm (14), pronunciation (11), chunking (22),
  source-manifest (165), sections (154), global-manifest (12),
  maintainability-ratchet (183), ratchet-contract (3), seam-registry (12),
  ai-feature-api-key (13).
- `bash tools/ai_validate.sh full --boot-smoke` → **geçti**: environment OK,
  parse sanity OK, app source smoke OK (7.2s), **tam strict testthat suite geçti
  (172.0s)**, shiny boot smoke OK (9.1s); `failed_steps: 0`, `skipped_steps: 0`.
  `browser_smoke_status: "skipped"` (konteynerde tarayıcı binary'si yok —
  bloklamayan). Artifact: `artifacts/ai-validation/20260615-192828/summary.json`
  (`validation_execution_status="ran_by_ai_repo_check"`, profile full/full,
  `app_source_smoke_status="passed"`, `shiny_boot_smoke_status="passed"`,
  `db_sso_vm_validation_performed=FALSE`).
- `Rscript tests/scripts/maintainability_report.R` → skor 100/100; 271 dosya;
  `server_ai_expert_handlers.R` 652/22; refactor adayı yok.
- `Rscript tests/scripts/seam_doctor.R` → `SEAM_DOCTOR_RESULT: OK`; `medya_ses`
  runtime-dosya 9 → 10 (yeni dosya sahipli), sahipsiz dosya yok.
- App boot smoke (`tests/scripts/smoke_app_boot.R`) → OK. Tüm komutlar
  `LANG=C.UTF-8` ile; `logger` paketi oturum içinde CRAN'dan kuruldu.

### Manuel QA (kullanıcı/VM tarafı)
- Windows VM'de SSO ile başlatın; Ana Söyleşi'ye girince AI Uzman karşılama
  konuşmasının (ses + altyazı) eskisi gibi geldiğini doğrulayın.
- Söyleşi Geçmişi / Kayıtlı Söyleşiler / Görsel Galerisi / Bilge Yolaç / Dosya
  Yönetimi / Yapılandırma / Yardım Merkezi / Yenilikler / Hakkında sekmelerine
  geçince sayfa rehberliği konuşmasının doğru Türkçe sayfa adıyla geldiğini;
  yasaklı sayfaya (Kişiselleştirme/Yönetici/Sistem Durumu) geçince
  seslendirilmediğini doğrulayın.
- Boşta bekleyince (idle) AI Uzman konuşmasının son mesaj/departman bağlamıyla
  geldiğini ve sıklık ayarının (az/orta/sık) gecikmeyi etkilediğini doğrulayın.

### Bilinen riskler / atlanan doğrulamalar
- Browser UX smoke gerçek tarayıcıyla ÇALIŞTIRILMADI (konteynerde Chrome/Edge yok;
  `browser_smoke_status="skipped"`); statik harness sözleşmeleri geçti, VM'de
  bloklayıcı modda koşulmalıdır.
- VM/SSO/gerçek DB/SQL Server Türkçe encoding kapıları bu oturumda çalıştırılmadı
  (`db_sso_vm_validation_performed=FALSE`); AI Uzman canlı ses/DB akışı yalnızca
  VM'de kanıtlanır. Runtime davranışı değişmedi (4 saf yardımcı ayrı dosyaya +
  manifest); LLM future blokları bilerek ellenmedi.
- Küresel 24-fonksiyon ratchet değeri sıkılaştırılMAdı; sıradaki yakın-bütçe
  adayı `R/module_ai_expert.R` (617/22) — ancak içeriği büyük ölçüde reaktif/
  promise tabanlı TTS orkestrasyonudur (saf çıkarım sınırlı, ayrı oturum kararı).

---

## 2026-06-15 — AI Uzman worker-safe DB okuyucularının ayrılması (24-fonksiyon tavanından indirme)

### Seçilen iz(ler)
- **Track 1 — Yakın-bütçe R dosyasından bütünleşik yardımcı çıkarımı**
  (`R/helpers_ai_expert.R` → `R/helpers_ai_expert_user_data.R`).

### Özet ve gerekçe
Keşif raporları (skor 100/100, refactor adayı yok) sonrası en yüksek kaldıraçlı
zayıflık küresel **fonksiyon tavanıydı**. Resmî bakım metriği (`(<-|=) function(`)
ile üç dosya 24-fonksiyon küresel tavanında oturuyordu: `helpers_ai_expert.R`
(680 satır), `helpers_file_manager_runtime.R` (259 satır) ve
`helpers_health_formatters.R` (256 satır). Son ikisi belgelenmiş, küçük ve kararlı
"yoğun-tasarım" yardımcılarıdır; `helpers_ai_expert.R` ise hem en büyük (680 satır)
hem de aktif olarak geliştirilen bir özelliğin dosyası — yani bir sonraki AI Uzman
değişikliğinde bütçeyi kıracak en olası aday.

Dosyanın doğal sınırı netti: dört worker-safe DB okuyucusu (`fetch_user_full_name`,
`fetch_user_work_context`, `fetch_recent_user_prompts`, `fetch_user_last_login`)
hem bütünleşik bir sorumluluk (MB_Users/MB_Messages okuma) hem de çok sayıda
`error = function(e)` anonim işleyici taşıdığından, taşınmaları **hem satır hem
fonksiyon** sayısını birden düşürdü. Okuyucular `R/helpers_ai_expert_user_data.R`
dosyasına birebir taşındı; `helpers_ai_expert.R` sistem istemi/bağlam/LLM-çağrısı/
telaffuz orkestrasyonuna odaklı kaldı. `build_ai_expert_user_context()` çalışma
zamanında `fetch_recent_user_prompts()`'u çağırdığından, yeni dosya manifest'te
ÖNCE yüklenir.

### Değişen dosyalar
**Kaynak**
- `R/helpers_ai_expert_user_data.R` (yeni, 187 satır / 11 fonksiyon) — dört
  worker-safe DB okuyucusu, roxygen açıklamaları ve okuma-sınırı
  (`normalize_db_read_visible_value`) sözleşmesiyle birebir taşındı.
- `R/helpers_ai_expert.R` — dört okuyucu kaldırıldı; başlığa yeni dosyaya
  yönlendirme notu eklendi. **680 → 507 satır / 24 → 13 fonksiyon.**
- `R/config_source_manifest.R` — `ai_expert_helpers` bölümüne yeni dosya
  `helpers_ai_expert.R`'den ÖNCE eklendi (2 → 3 dosya; toplam 263 → 264).

**Test**
- `tests/testthat/test-ai-expert-user-data-split-contract.R` (yeni, 19 assertion)
  — yeni dosya varlığı + okuyucu yüzeyi, manifest sırası (okuyucular → helper),
  okuyucuların `helpers_ai_expert.R`'ye geri dönmemesi, korunan orkestrasyon
  fonksiyonları, okuma-sınırı (`normalize_db_read_visible_value`) ve Shiny-bağsızlık.
- `tests/testthat/test-ai-expert-db-fetch-behavior.R` — iki source noktası
  `helpers_ai_expert.R` yerine `helpers_ai_expert_user_data.R`'yi source eder
  (20 assertion değişmeden geçer).
- `tests/testthat/test-ai-expert-page-guidance-stale-behavior.R` — handler'ın
  çağırdığı okuyucular için yeni dosya da source edilir; `fetch_user_full_name`
  stub'ı yine override eder (2 assertion).
- `tests/testthat/test-source-manifest-sections-contract.R` — `ai_expert_helpers`
  çapası (first/n) ve toplam (263 → 264) bilinçli güncellendi.
- `tests/testthat/test-maintainability-ratchet.R` — dosya-özel bütçe eklendi:
  `helpers_ai_expert.R` 540L/15F, `helpers_ai_expert_user_data.R` 220L/13F
  (24-fonksiyon tavanına geri tırmanış kilitlendi).

**Dokümantasyon**
- `CLAUDE.md` — Group 4 yükleme listesine yeni dosya eklendi (yük sırası doğruluğu).
- `docs/architecture-map.md` — TTS/STT/audio ownership ve "önce oku" satırlarına
  yeni dosya eklendi.
- `docs/technical-reference.md` — AI Uzman worker-safe DB okuyucu sınırı notu.
- `docs/feature-ownership-map.md` — yeni "Medya / Ses / AI Uzman" özellik bölümü
  (eksik olan `medya_ses` seam satırı) eklendi.
- `docs/refactor-log.md` — bu giriş.

### Önce / sonra karmaşıklık notları
- Önce: `helpers_ai_expert.R` 680/24 — küresel fonksiyon tavanında; herhangi bir
  küçük AI Uzman eklemesi global ratchet'i kıracaktı; DB okuma + prompt + LLM
  çağrısı aynı dosyada karışıktı.
- Sonra: `helpers_ai_expert.R` 507/13 (küresel tavandan indi); okuyucular ayrı,
  bütünleşik, bağımsız test edilebilir dosyada; her iki dosya da dosya-özel
  bütçeyle kilitli. Maintainability skoru 100/100 korunur, değerlendirilen dosya
  269 → 270. Küresel 24-fonksiyon değeri BİLEREK sıkılaştırılmadı: tavanı hâlâ
  `helpers_file_manager_runtime.R` ve `helpers_health_formatters.R` tutuyor
  (belgelenmiş yoğun-tasarım dosyaları; ayrı oturum kararı).

### Korunan davranış sözleşmeleri
- Dört okuyucunun gövdesi, sorguları, `error = function(e)` güvenli düşüşleri,
  `.aix_read_visible` iç yardımcısı ve `normalize_db_read_visible_value` okuma
  sınırı birebir aynı (mevcut 20 davranış assertion'ı değişmeden geçer).
- `build_ai_expert_user_context()`, `build_ai_expert_system_prompt()`,
  `call_ai_expert_llm()`, `get_ai_expert_generation_config()`,
  `sanitize_ai_expert_pronunciation()` `helpers_ai_expert.R`'de kaldı; çağrı
  imzaları ve Türkçe metinler değişmedi.
- Manifest yük sırası `helpers_ai_expert.R` → `helpers_claude_code_upload_folder.R`
  ilişkisi korundu (yeni dosya daha erken bölümde). DB/SSO/frontend/UX'e dokunulmadı.

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- Odak testler tek tek geçti (0 FAIL / 0 WARN / 0 SKIP): yeni split sözleşmesi (19),
  db-fetch davranış (20), prompt-builders (9), page-guidance-stale (2),
  call-llm (7), pronunciation (4), chunking (8), sections (4 test bloğu),
  source-manifest (11), global-manifest (6), maintainability-ratchet (12),
  ratchet-contract (2), seam-registry (6), upload-folder-refactor (4).
- `Rscript tests/scripts/maintainability_report.R` → skor 100/100; 270 dosya;
  refactor adayı yok; `helpers_ai_expert.R` 507/13.
- App boot smoke (`tests/scripts/smoke_app_boot.R`) → OK; manifest yeni dosyayı
  sırasıyla yükledi, `create_mergen_app()` shiny.appobj döndürdü.
- `bash tools/ai_validate.sh full --boot-smoke` → **geçti**: environment OK,
  parse sanity OK, app source smoke OK (4.6s), **tam strict testthat suite geçti
  (130.3s)**, shiny boot smoke OK (5.8s); `failed_steps: 0`, `skipped_steps: 0`.
  `browser_smoke_status: "skipped"` (konteynerde tarayıcı binary'si yok — bloklamayan).
  Artifact: `artifacts/ai-validation/20260615-153048/summary.json`
  (`validation_execution_status="ran_by_ai_repo_check"`,
  `app_source_smoke_status="passed"`, `shiny_boot_smoke_status="passed"`).
- Ortam notu: konteynerde yalnızca `logger` paketi eksikti (diğer ağır paketler
  kuruluydu); oturum içinde CRAN'dan kuruldu. Tüm komutlar `LANG=C.UTF-8` ile.

### Manuel QA (kullanıcı/VM tarafı)
- Windows VM'de SSO ile başlatın; Ana Söyleşi'ye girince AI Uzman karşılama
  konuşmasının (ses + altyazı) eskisi gibi geldiğini doğrulayın.
- Farklı sayfalara (örn. Söyleşi Geçmişi) geçince sayfa rehberliği konuşmasının
  geldiğini; yasaklı sayfaya (Kişiselleştirme/Yönetici/Sistem Durumu) geçince
  bayat rehberliğin SESLENDİRİLMEDİĞİNİ doğrulayın.
- Türkçe karakterli ad/birim bilgisinin (MB_Users) AI Uzman bağlamında doğru
  göründüğünü; eski mojibake bir adın TTS/altyazıda onarılmış geldiğini doğrulayın.
- Boşta bekleyince (idle) AI Uzman konuşmasının son mesaj bağlamıyla geldiğini
  doğrulayın.

### Bilinen riskler / atlanan doğrulamalar
- Browser UX smoke gerçek tarayıcıyla ÇALIŞTIRILMADI (konteynerde Chrome/Edge yok);
  statik harness sözleşmeleri geçti, VM'de bloklayıcı modda koşulmalıdır.
- VM/SSO/gerçek DB/SQL Server Türkçe encoding kapıları bu oturumda çalıştırılmadı;
  runtime davranışı değişmedi (yalnızca 4 fonksiyon ayrı dosyaya taşındı + manifest).
  AI Uzman canlı ses/DB akışı yalnızca VM'de kanıtlanır.
- Küresel 24-fonksiyon ratchet değeri sıkılaştırılMAdı; tavanı hâlâ
  `helpers_file_manager_runtime.R` ve `helpers_health_formatters.R` tutuyor
  (sıradaki olası hedefler veya kabul edilen yoğun-tasarım kararı).

---

## 2026-06-15 — Windows VM evidence gate rerun: güncel release kanıtı

`tests/scripts/run_vm_evidence_gate.R` tam Windows VM koşumu 15 Haziran 2026 tarihinde yeniden uçtan uca geçti: `Toplam: 13 passed, 0 failed, 0 skipped`. Güncel passed adımlar: `env_config`, `parse_sanity`, `app_boot_smoke`, `full_testthat`, `maintainability_report`, `frontend_ratchet`, `seam_doctor`, `source_manifest_contracts`, `ui_asset_manifest_contracts`, `browser_ux_smoke`, `vm_preflight_real`, `db_encoding_preflight`, `renv_status`. Son artifact: `artifacts/vm-evidence/20260615-130127/evidence.json`; kalıcı artifact düzeni `artifacts/vm-evidence/<timestamp>/evidence.json`.

Operasyonel olarak browser proof, external-app modunda alındı: uygulama ayrı pencerede `http://127.0.0.1:28081` üzerinde açık tutuldu, gate ikinci pencerede `MERGEN_BROWSER_UX_BASE_URL=http://127.0.0.1:28081` ve `MERGEN_REQUIRE_BROWSER_UX_SMOKE=true` ile çalıştırıldı. Bu mod `UX_SMOKE_DONE:PASS` üretmediği sürece blocking kabul edilir.

Milestone sırasında doğrulanan bakım iyileştirmeleri: isolated health UI testleri gerekli health table helper'larını source eder; LLM worker tool-result isolated testleri preview-dataframe helper'ını formatter'dan önce source eder; `run_full_testthat_isolated.R` start/end index aralığıyla devam koşumunu destekler; full testthat çocuk süreçleri browser UX evidence env leakage'a karşı korunur; VM preflight path handling Türkçe karakterli ve boşluklu mapped-drive / UNC-style path'ler için sertleştirildi.

Bu kayıt release/readiness kanıtıdır, davranış değişikliği iddiası değildir. Kanıt yalnızca `evidence.json` içinde `passed` görünen adımlar için geçerlidir; uzun süreli saha yükü ve manuel kırılgan-akış QA'sı ayrıca gerekir.

## 2026-06-10 — Seam kayıt defteri, frontend bölge sahipliği ve CSS kaskad kuralları (yönetişim katmanı)

### Seçilen iz(ler)
- **Track A — Üretim-kritik seam dağınıklığı:** Shiny runtime, DB/encoding, SSO/JWT, LLM streaming, dosya yaşam döngüsü, API anahtarları, medya/ses, yönetici panelleri ve Bilge Yolaç sınırlarının sahipliği tek makine-okur haritada toplandı.
- **Track B — Frontend kırılganlığı:** Sıralı CSS/JS katmanları, tema override zinciri, streaming handler sırası ve varlık sahipliği için bölge haritası + makine doğrulamalı CSS kaskad kuralları + tarayıcı smoke zorlaması sıkılaştırması eklendi.

### Özet ve gerekçe
Sahiplik bilgisi CLAUDE.md düzyazısına ve onlarca sözleşme testine dağılmıştı; "bu dosyaya kim bakar, hangi test korur?" sorusunun tek cevabı yoktu. Yeni runtime R dosyaları manifest'e, yeni frontend dosyaları manifest+rapora eklenebiliyor ama hiçbir katman sahiplik bildirimi ZORLAMIYORDU. Tema override zinciri (tokens → light → extras → modüller → overhaul → user_polish) yalnızca dondurulmuş vektör sırasıyla korunuyordu; JS'teki gibi anlamlı ikili sıra kuralları yoktu.

Çözüm runtime davranışını değiştirmeyen üç saf katman: (1) `R/config_seam_registry.R` — 12 seam'in bölüm/dosya/guard-test/odaklı-doğrulama sahipliği; (2) `R/config_ui_asset_zones.R` — manifestteki her CSS/JS varlığının tam olarak bir bölgeye (23 bölge) atanması + manifest dışı bilinçli varlıkların gerekçeli sahiplik kaydı; (3) `ui_asset_css_order_rules` + `ui_asset_validate_css_order()` — tema/Bilge Yolaç CSS kaskadının JS kuralları gibi hem boot'ta hem testte zorlanması. Operasyonel rapor için `tests/scripts/seam_doctor.R` (+ `tools/seam_doctor.sh`) eklendi. Tarayıcı smoke: `MERGEN_BROWSER_BIN` açıkça verilmişse require modu otomatik açılır ve kullanılamayan binary erken/net hata verir.

### Değişen dosyalar
**Kaynak (yeni)**
- `R/config_seam_registry.R` (539 satır / 6 fonksiyon) — 12 seam kaydı + `mergen_seam_registry_validate()` (bölüm tekil sahiplik, guard-test/dosya varlığı, bölge sahibi çapraz kontrolü) + `mergen_seam_runtime_allowlist()` (manifest dışı runtime R dosyaları için TEK allowlist).
- `R/config_ui_asset_zones.R` (764 satır / 10 fonksiyon) — 23 bölge, `ui_asset_zones_validate()` (çift yönlü tam bölümleme), `ui_asset_unmanifested_ownership` (app_loading*, admin_analytics.css, smoke dosyaları), `ui_asset_frontend_ownership_gaps()` (fiziksel www/css|js kapsama).
- `tests/scripts/seam_doctor.R`, `tools/seam_doctor.sh` — yapısal doğrulama + secret-safe JSON artifact (`artifacts/seam-doctor/`); `source(...)`-güvenli (quit yok, drift'te `stop()`).

**Kaynak (güncellenen)**
- `R/config_source_manifest.R` — `config_ui_assets` bölümüne bölge haritası eklendi (n: 1→2); yeni `architecture_governance` bölümü (`R/config_seam_registry.R`); toplam 258→260 dosya.
- `R/config_ui_assets.R` — `ui_asset_css_order_rules` (21 kural: variables→tokens→light→extras→refinements→6 tema modülü→overhaul→phase2→user_polish→v2; tema-sonrası brand_title/sidebar_user_panel/tool_backgrounds; welcome_modern→theme_light_welcome; Bilge Yolaç CSS zinciri) + `ui_asset_validate_css_order()` `ui_asset_validate(...)` zincirine bağlandı. Üretilen tag çıktısı bayt-denk değişmedi.
- `tests/scripts/ai_browser_ux_smoke.R` — explicit `MERGEN_BROWSER_BIN` ⇒ require modu otomatik + kullanılamayan binary için erken `MERGEN_BROWSER_BIN kullanılamıyor` hatası.
- `tests/scripts/ai_repo_check.R` — quick profiline 4 yeni sözleşme testi eklendi (sections, seam-registry, ui-asset-zones, seam-doctor).
- `.gitignore` — `artifacts/seam-doctor/`, `artifacts/frontend-complexity-doctor/`, `artifacts/validation-doctor/` eklendi.

**Test**
- `tests/testthat/test-seam-registry-contract.R` (yeni, 6 test / 12 assertion) — dondurulmuş seam id listesi, manifest/bölge/dosya gerçekliği doğrulaması, bölüm→seam tekil sahiplik, R/ sahipsiz dosya yasağı, kök giriş dosyaları sahipliği, erişim yardımcıları.
- `tests/testthat/test-ui-asset-zones-contract.R` (yeni, 7 test / 13 assertion) — dondurulmuş bölge id listesi, manifest tam bölümleme, fiziksel sahiplik boşluğu yasağı, bölge sahiplerinin gerçek seam olması, seam→bölge türetimi, smoke sızıntı yasağı, bilinmeyen grup referansı hataları.
- `tests/testthat/test-seam-doctor-contract.R` (yeni, 2 test / 6 assertion) — statik hafiflik/secret-safety/source-güvenlik sözleşmesi + doctor'ın gerçek repoda sorunsuz çalışıp artifact üretmesi (warn seviyesi test sonunda geri yüklenir).
- `tests/testthat/test-ui-asset-manifest-contract.R` — yeni CSS kural bloğu (kural çapaları, gerçek manifestte sağlama, sentetik ihlal yakalama, validate zinciri bağlılığı): 178→233 assertion.
- `tests/testthat/test-source-manifest-sections-contract.R` — bölüm anahtarları + çapalar + toplam (260) bilinçli güncellendi.
- `tests/testthat/test-browser-ux-smoke-runner-contract.R` — yeni zorlama tokenları (`browser_bin_explicit`, `MERGEN_BROWSER_BIN kullanılamıyor`) donduruldu.
- `tests/testthat/test-maintainability-ratchet.R` — yönetişim dosyalarına dosya-özel bütçe: zones 780L/12F, registry 580L/8F.

**Dokümantasyon**
- `CLAUDE.md` — yeni "Seam registry and frontend ownership zone contract" bölümü; manifest ekleme kurallarına seam sahipliği maddesi; UI asset sözleşmesine bölge + CSS kural maddeleri; tema sözleşmesine yürütülebilir kaskad notu; browser smoke kurallarına explicit-bin zorlaması; "Where to go next" işaretçisi.
- `docs/architecture-map.md` — yönetişim katmanı bölümü (seam tablosu, disiplin kuralları, CSS kaskad notu); kritik sınırlar ve "önce oku" tabloları güncellendi.
- `RUNBOOK.md` — hızlı referans + 7.4 seam/bölge doğrulaması + 7.5 tarayıcı smoke zorlaması.
- `docs/technical-reference.md`, `docs/README.md` — yönetişim katmanı referansları.

### Önce / sonra karmaşıklık notları
- Önce: 35 manifest bölümü ve 215 manifest frontend varlığı için sahiplik yalnızca düzyazıda; R/ ve www/ altına sahipsiz dosya eklemek mümkündü; tema kaskadı yalnızca dondurulmuş vektörle korunuyordu; tarayıcı bildiren ortamda smoke sessizce atlanabiliyordu.
- Sonra: 36 bölüm → 12 seam (tekil sahiplik, testle zorlanır); 95 CSS + 120 JS manifest varlığı → 23 bölge (çift yönlü tam bölümleme); www/css|js fiziksel kapsama + R/ sahipsiz dosya yasağı; 21 yürütülebilir CSS kaskad kuralı boot+test seviyesinde; explicit browser yapılandırması bloklayıcı. Maintainability skoru 100/100 korunur; yeni dosyalar dosya-özel bütçeyle kilitli.

### Korunan davranış sözleşmeleri
- Çalışma zamanı UX bayt-denk: yönetişim dosyaları saf veri+fonksiyon tanımlar, boot'ta doğrulama çağrılmaz (CSS sıra doğrulayıcısı hariç — o da mevcut `ui_asset_validate(...)` kalıbının genişletilmesidir ve gerçek manifestte sessiz geçer).
- Yükleme sırası sahipliği değişmedi: kaynak sırası `R/config_source_manifest.R`, varlık sırası `R/config_ui_assets.R`.
- Hiçbir mevcut test/ratchet/guard zayıflatılmadı; sections sözleşmesi bilinçli genişletildi, ratchet bütçeleri yalnızca SIKILAŞTIRILDI.
- Smoke-only dosyalar üretim manifestine eklenmedi; CDN/ağ bağımlılığı yok; secret yazılmadı.

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- `Rscript tests/testthat.R` (tam strict suite, `stop_on_failure`/`stop_on_warning`) → **exit 0**; 0 FAIL / 0 WARN; 5 ortam-koşullu SKIP (Windows-only .cmd testi, openxlsx kurulu değil ×3, strict-offline opt-in) — tümü önceden var olan, dokümante skip semantiği.
- Odaklı testler (0 FAIL / 0 WARN / 0 SKIP): seam-registry (12), ui-asset-zones (13), seam-doctor (6), sections (154), source-manifest (165), global-manifest (12), ui-asset-manifest (233), maintainability-ratchet (174), frontend-ratchet (86), all-runtime-parse (2), production-contracts (21), secret-leak (8), network-boundary (2), browser-ux-runner (5), e2e-boot-welcome (29).
- `Rscript tests/scripts/parse_sanity_check.R` → 744 dosya parse OK.
- `Rscript tests/scripts/maintainability_report.R` → skor 100/100; 0 refactor adayı; 800+/25+ dosya yok.
- `Rscript tests/scripts/frontend_complexity_doctor.R` → artifact üretildi; manifest dışı app-owned varlık 0.
- `Rscript tests/scripts/seam_doctor.R` → `SEAM_DOCTOR_RESULT: OK`, 12 seam / 36 bölüm / 23 bölge / 9 manifest-dışı sahipli dosya; artifact yazıldı.
- App boot smoke: `source("app.R")` + `validate_boot_state()` → OK; seam registry + bölge haritası runtime'da yüklü (CSS sıra doğrulayıcısı boot zincirinde sessiz geçti).
- `bash tools/ai_validate.sh full --boot-smoke` → **geçti**: 6/6 adım OK (`environment`, `parse sanity`, `app source smoke`, `full testthat suite` 111.3s, `shiny boot smoke`, `browser UX smoke` adımı), `failed_steps: 0`, `skipped_steps: 0`, `full_testthat_suite_status: "passed"`, `shiny_boot_smoke_status: "passed"`; `browser_smoke_status: "skipped"` — adım çalıştı ama konteynerde tarayıcı binary'si olmadığından kendi içinde bloklamayan SKIP üretti. Artifact: `artifacts/ai-validation/20260610-155750/summary.json`.
- Tüm komutlar `LANG=C.utf8` ile çalıştırıldı.

### Manuel QA (kullanıcı/VM tarafı)
- Windows VM'de SSO ile normal başlatma: karşılama ekranı, koyu/açık tema geçişi (özellikle açık tema cilası: navbar şeridi, chat baloncukları, Bilge Yolaç yüzeyleri), hızlı eylemler ve Bilge Yolaç akışının görsel olarak değişmediğini doğrulayın.
- Tarayıcılı ortamda `MERGEN_REQUIRE_BROWSER_UX_SMOKE=true bash tools/ai_validate.sh full --boot-smoke` ile `UX_SMOKE_DONE:PASS` alın; `MERGEN_BROWSER_BIN` ayarlıysa artık otomatik bloklayıcı olduğunu bilin.
- `bash tools/seam_doctor.sh` çalıştırıp `SEAM_DOCTOR_RESULT: OK` görün.

### Bilinen riskler / atlanan doğrulamalar
- Browser UX smoke bu oturumda gerçek tarayıcıyla ÇALIŞTIRILMADI (konteynerde Chrome/Chromium/Edge yok); statik harness/runner sözleşmeleri geçti. VM'de bloklayıcı modda koşulmalıdır.
- VM/SSO/gerçek DB/SQL Server Türkçe encoding kapıları bu oturumun kapsamı dışındadır (runtime davranışı değişmedi); normal VM preflight rutini yeterlidir.

---

## 2026-06-09 — Sidebar kullanıcı paneli saf görünüm yardımcılarının ayrılması

### Seçilen iz(ler)
- **Track B — Complex runtime kodundan saf yardımcı çıkarımı** (`R/module_sidebar_user_panel.R` → `R/helpers_sidebar_user_display.R`).
- Tamamlayıcı: dosya, 24-fonksiyon küresel ratchet tavanında oturan üç dosyadan biriydi; bölünme bu dosyayı tavandan indirir ve korunan Departman/tema/iskelet sözleşmelerine bağımsız test edilebilir bir sahip verir.

### Özet ve gerekçe
`R/module_sidebar_user_panel.R` (581 satır / 24 fonksiyon) saf görünüm kararlarını (Türkçe-güvenli baş harf üretimi, avatar URL placeholder reddi, korunan `Departman → departman → department` seçim sırası, tema anahtarı/kontrol satırı/kullanıcı rozeti HTML üreticileri) Shiny render/observer orkestrasyonuyla aynı dosyada taşıyordu. Dosya küresel 24-fonksiyon tavanında oturduğundan, panele eklenecek herhangi bir küçük yardımcı küresel ratchet'i kırardı.

Altı saf yardımcı (`mb_sidebar_user_initials`, `mb_sidebar_user_avatar_url`, `mb_sidebar_user_department`, `mb_sidebar_theme_switch`, `mb_sidebar_controls_row`, `mb_sidebar_user_badge_ui`) birebir `R/helpers_sidebar_user_display.R` dosyasına taşındı. Modül; UI kabuğu (`mb_sidebar_user_panel_ui`), logout olayı (`mb_sidebar_handle_logout_event`) ve server render (`mb_sidebar_user_panel_server`) sorumluluklarına odaklı kaldı. Üretilen tag ağacı, sınıf adları, logout onclick JS'i ve iskelet davranışı bayt-denk korunur.

### Değişen dosyalar
**Kaynak**
- `R/helpers_sidebar_user_display.R` (yeni, 285 satır / 9 fonksiyon) — altı saf görünüm yardımcısı, roxygen açıklamalarıyla birlikte birebir taşındı.
- `R/module_sidebar_user_panel.R` — taşınan tanımlar kaldırıldı; başlığa yeni sahiplik notu eklendi. **581 → 316 satır / 24 → 15 fonksiyon.**
- `R/config_source_manifest.R` — `module_identity_startup` bölümüne helper, modülden hemen önce eklendi (10 → 11 dosya).

**Test**
- `tests/testthat/test-sidebar-user-display-split-contract.R` (yeni, 32 assertion) — helper varlığı/yüzeyi, manifest sırası (helper → modül), taşınan tanımların modüle geri dönmemesi, modülün orkestrasyon sorumluluklarını korunması, helper'ın Shiny-bağsız kalması ve davranış sözleşmeleri (Türkçe baş harf, Departman sırası, Mudurluk reddi, placeholder avatar reddi).
- `tests/testthat/test-sidebar-user-panel-behavior.R` — bootstrap'e helper source eklendi (12 assertion değişmeden geçer).
- `tests/testthat/test-sidebar-departman-contract.R` — izole yükleyici helper'ı da source eder; `pick("Departman")` statik taraması yeni sahibe (helper dosyası) yönlendirildi; Mudurluk negatif taraması her İKİ dosyada da korunur (16 assertion).
- `tests/testthat/test-sidebar-theme-sync-contract.R` — tema butonu attribute taraması yeni sahibe yönlendirildi (19 assertion).
- `tests/testthat/test-source-manifest-sections-contract.R` — `module_identity_startup` n 10→11, toplam 257→258.
- `tests/testthat/test-maintainability-ratchet.R` — yeni dosya-özel bütçeler: modül 360L/17F, helper 320L/11F (24-fonksiyon tavanına geri tırmanma kilitlendi).

**Dokümantasyon**
- `CLAUDE.md` — sidebar ownership satırı iki dosyalı yapıya güncellendi; korunan test listesine split sözleşmesi eklendi.
- `docs/technical-reference.md` — sidebar notuna saf yardımcı sınırı eklendi.
- `docs/refactor-log.md` — bu giriş.

### Önce / sonra karmaşıklık notları
- Önce: tek dosyada saf karar + Shiny orkestrasyon karışımı; dosya 24-fonksiyon küresel tavanında; Departman/tema sözleşmeleri yalnızca modül-dosyası statik taramasıyla korunuyordu.
- Sonra: saf yardımcılar Shiny olmadan source edilip test edilebilir; modül 15 fonksiyona indi; her iki dosya dosya-özel bütçeyle kilitli. Küresel 24-fonksiyon tavanı İKİ başka dosya (`helpers_file_manager_runtime.R`, `helpers_health_formatters.R`) tarafından tutulduğu için küresel değer BİLEREK sıkılaştırılmadı (dürüst sınır: bu oturum yalnızca sidebar'ı tavandan indirir).

### Korunan davranış sözleşmeleri
- Üretilen HTML/tag ağacı, sınıf adları (`mb-sidebar-*`, `theme-switch-*`), `data-mergen-theme-toggle` attribute'u, logout onclick JS'i ve `mergen_sidebar_logout` Shiny olayı birebir aynı.
- Departman seçim sırası `Departman → departman → department`; `Mudurluk` görünür alan olarak ASLA seçilmez (statik + davranışsal olarak iki dosyada da doğrulanır).
- İskelet/instant-render sözleşmesi: `mb-sidebar-user-skeleton`, `mb-sidebar-controls-skeleton`, slot-output sınıfları ve `mb_sidebar_controls_row(show_logout = FALSE)` çağrısı modülde kaldı (test anchorsları değişmedi).
- Görünür sürüm tek kaynağı `get_app_version_label()` modülde; tema senkronizasyonu, SSO auth-ready yeniden render ve `suspendWhenHidden = FALSE` davranışı dokunulmadı.

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- Odak testler tek tek geçti (0 FAIL / 0 WARN / 0 SKIP): yeni split sözleşmesi (32), sidebar davranış (12), sidebar server davranış (20), departman (16), tema-sync (19), instant-render (11), version-single-source (11), logout-url (33), source manifest (165), sections (150), global manifest (12), maintainability ratchet (168), network boundary (2), secret leak (8), production contracts (21), e2e boot/welcome (29), UX guardrails (28).
- İlk tam koşu, taşınan tanımlara modül dosyasında bakan iki ek statik sözleşmeyi yakaladı (`test-logout-url-contract.R` çıkış-butonu taraması ve `test-sidebar-user-panel-server-behavior.R` izole source); her ikisi yeni sahibe yönlendirildi/bootstrap'e helper eklendi — davranış sözleşmeleri zayıflatılmadı.
- `bash tools/ai_validate.sh full --boot-smoke` (düzeltme sonrası) → geçti; **tam strict testthat suite geçti**, Shiny boot smoke geçti, `failed_steps: 0`, `skipped_steps: 0` (browser UX smoke container'da tarayıcı olmadığından bloklamayan SKIP). Artifact: `artifacts/ai-validation/20260610-031858/summary.json`.
- `Rscript tests/scripts/maintainability_report.R` → skor 100/100; modül 316/15, helper 285/9.
- Tüm komutlar `LANG=C.UTF-8 LC_ALL=C.UTF-8` ile çalıştırıldı.

### Manuel QA (kullanıcı/VM tarafı)
- Uygulamayı normal Windows VM launcher ile başlatın; sol menü altındaki kullanıcı panelinin İLK renderda iskeletle birlikte geldiğini doğrulayın.
- SSO girişi sonrası ad/avatar ve Departman değerinin (MB_Users) doğru göründüğünü; Türkçe karakterli adların baş harflerinin bozulmadığını doğrulayın.
- Tema düğmesine tıklayın: koyu/açık geçişin çalıştığını ve etiketin güncellendiğini doğrulayın; sidebar yeniden render sonrası düğmenin çalışmaya devam ettiğini kontrol edin.
- `MERGEN_LOGOUT_URL` tanımlıysa çıkış butonunun göründüğünü, tıklayınca konsola logout logunun düştüğünü ve tarayıcının hedef URL'ye gittiğini doğrulayın.
- Sürüm satırının doğru sürümü gösterdiğini kontrol edin.

### Bilinen riskler / atlanan doğrulamalar
- Küresel 24-fonksiyon ratchet değeri sıkılaştırılMAdı; tavanı hâlâ `helpers_file_manager_runtime.R` ve `helpers_health_formatters.R` tutuyor (her ikisi de belgelenmiş yoğun-tasarım dosyaları; ayrı oturum kararı gerektirir).
- Windows VM launcher ve gerçek tarayıcı/SSO doğrulaması bu cloud oturumunda çalıştırılmadı; sidebar SSO yeniden render davranışı için kullanıcı tarafı QA gereklidir.

---

## 2026-06-09 — config_api.R baş boşluğu: Derin Düşünme kayıt konsolidasyonu + API anahtarı kripto katmanı ayrımı

### Seçilen iz(ler)
- **Track E — Duplicate mechanism consolidation**: `config_api.R` içinde İKİ ayrı source-time blok olarak yaşayan Derin Düşünme yetenek/endpoint kayıt mekanizması tek saf yardımcıda birleştirildi (`R/helpers_deep_thinking_model_capabilities.R`).
- **Track B/A — Cohesive boundary extraction**: kullanıcı API anahtarı şifreli saklama katmanı (~152 satır) `R/helpers_api_key_crypto.R` dosyasına taşındı.
- Tamamlayıcı cerrahi düzeltme: bir önceki oturumda "bilinen risk" olarak belgelenen `decode_stream_delta_payload()` skaler dönüş ucu kapatıldı.

### Özet ve gerekçe
`R/config_api.R` repodaki EN sıkışık dosyaydı: 699 satır / 700 satırlık dosya-özel ratchet bütçesi — yani 1 satır boşluk. Her yeni model, env değişkeni veya yetenek alanı bu dosyaya dokunmak zorunda olduğundan, ilk masum değişiklik plansız bir refactor'ü başka birinin görevine zorlamış olacaktı.

İki yapısal sorun çözüldü: (1) Derin Düşünme model kayıt mantığı dosyada iki ayrı blokta yaşıyordu — biri tabloda olmayan modele şablon + endpoint ekleyen erken blok, diğeri dosya sonunda `modifyList` ile eksik alanları tamamlayan ikinci blok. İki mekanizmanın bileşimi belgesizdi ve gelecekte tek tarafın değiştirilmesi sessiz davranış kayması üretirdi. Mekanizma, vision işaretleme deseniyle birebir aynı şekilde (`config_api.R`'den ÖNCE yüklenen saf helper + guard'lı çağrı) tek sahibe indirildi; birleşik davranışın eski iki-blok bileşimiyle **birebir aynı** olduğu hem test içi denklik fixture'larıyla hem de oturum içi git-HEAD diferansiyel karşılaştırmasıyla kanıtlandı (4 env senaryosunda `identical(api_config_eski, api_config_yeni) == TRUE`: varsayılan, bilinmeyen deep modeller, vision+deep birlikte, boş deep env). (2) Anahtar şifreleme/saklama katmanı (API_KEYS_DIR, hash, AES-GCM/CBC, save/load/exists/verify) yapılandırma dosyasının içinde yaşıyordu; kendi başına tutarlı bir sorumluluk olarak ayrı dosyaya taşındı (kod birebir, davranış değişikliği yok).

### Değişen dosyalar
**Kaynak**
- `R/helpers_deep_thinking_model_capabilities.R` (yeni, 113 satır) — `collect_deep_thinking_model_ids()`, `apply_deep_thinking_model_capabilities()`; Shiny/DB/ağ/dosya yan etkisi yok.
- `R/helpers_api_key_crypto.R` (yeni, 167 satır) — kripto/saklama katmanı `config_api.R`'den birebir taşındı; NUL-tuz regresyon guard'ı, UTF-8 gidiş-dönüş ve atomik JSON yazımı korunur.
- `R/config_api.R` — iki Derin Düşünme bloğu guard'lı tek helper çağrısıyla değiştirildi; kripto bloğu kaldırıldı (yerinde yönlendirme yorumu). **699 → 468 satır / 12 → 2 fonksiyon (rapor metriği).**
- `R/helpers_llm_stream_io.R` — `decode_stream_delta_payload()` artık her girişte skaler karakter döndürür; bozuk satırdan gelen `[]`/NA alan şekilleri `if()` içinde NA üretemez. Geçerli b64/düz metin davranışı değişmedi.
- `R/config_source_manifest.R` — `config_api_model_keys` bölümü: deep helper vision sonrası/config_api öncesi, kripto helper tool-runtime sonrası/api_key_identity öncesi eklendi (7 → 9 dosya).

**Test**
- `tests/testthat/test-deep-thinking-model-capabilities-behavior.R` (yeni, 28 assertion) — kimlik toplama, bilinmeyen model varsayılanları, açık tanımın kazanması, endpoint onarımı, boş/geçersiz girişler ve eski iki-blok mekanizmasına karşı 4 fixture'lı birebir denklik.
- `tests/testthat/test-config-api-split-contract.R` (yeni, 36 assertion) — iki helper'ın varlığı/yüzeyi, manifest sırası (vision → deep → config_api → crypto → identity), guard'lı delegasyon, taşınan mantığın `config_api.R`'ye geri dönmemesi, deep helper'ın yan-etkisizliği.
- `tests/testthat/test-config-api-key-crypto-behavior.R` — bootstrap artık `config_api.R` yerine doğrudan `helpers_api_key_crypto.R` source eder (32 assertion değişmeden geçer).
- `tests/testthat/test-api-model-config-refactor-contract.R` ve `tests/testthat/test-llm-reasoning-request-overrides.R` — izole `config_api.R` source bağlamlarına deep helper ön-yüklemesi eklendi (belgelenmiş izole-test deseni).
- `tests/testthat/test-llm-stream-io-contract.R` — decode skaler dönüş regresyon testleri eklendi (bozuk `[]`/NA şekilleri, NULL/alansız payload, Türkçe b64 round-trip, b64 önceliği).
- `tests/testthat/test-source-manifest-sections-contract.R` — `config_api_model_keys` n 7→9, toplam 255→257.
- `tests/testthat/test-maintainability-ratchet.R` — `R/config_api.R` bütçesi 700L/14F → **520L/6F** sıkılaştırıldı; iki yeni helper için 160L/4F ve 220L/12F bütçeleri eklendi.

**Dokümantasyon**
- `CLAUDE.md` — "API model configuration contract" bölümü yeni kaynak sırası ve iki helper sorumluluğuyla güncellendi; vision bölümündeki 700-satır bütçe referansı 520/6 olarak düzeltildi; Group 2 yükleme listesi güncellendi.
- `docs/architecture-map.md` — model yeteneği ve API anahtarı ownership satırları yeni dosyaları gösterir.
- `docs/technical-reference.md` — Derin Düşünme kayıt tek-sahip notu, kripto taşıma notu ve decode skaler garanti notu eklendi.
- `docs/refactor-log.md` — bu giriş.

### Önce / sonra karmaşıklık notları
- Önce: `config_api.R` 699/700 satır (1 satır boşluk); Derin Düşünme kaydı iki kopya mekanizmada; kripto katmanı yapılandırma dosyasına gömülü; decode ucu belgelenmiş ama açık.
- Sonra: `config_api.R` 468 satır / 2 fonksiyon (≈%33 küçülme, yeni bütçeyle ~52 satır gerçek boşluk + bütçe kilidi); kayıt mekanizması tek saf sahip + 28 deterministik assertion; kripto katmanı kendi dosyasında aynı davranış testleriyle; decode her zaman skaler.

### Korunan davranış sözleşmeleri
- `api_config` nesnesi 4 env senaryosunda git-HEAD sürümüyle `identical()` — model yetenekleri, endpoint haritası, tool-mode yapılandırması, TTS/STT yapılandırması bayt-denk.
- Kripto fonksiyon adları/davranışı değişmedi; çağıranlar (`R/module_api_key.R`, `R/module_settings_yapilandirma.R`) dokunulmadı. NUL-tuz guard'ı, AES-GCM→CBC düşüşü, UTF-8 anahtar gidiş-dönüşü, atomik yazım aynen.
- `validate_api_key()` orkestrasyonu, `user_config`, `SERVICE_DESK`, endpoint/env okuma config_api.R'de kaldı.
- Streaming: geçerli b64/düz metin decode çıktıları birebir aynı; üretim yazıcısının boş metin yazmama guard'ı zaten koruyordu, okuyucu artık ek olarak sağlam.
- DB, SSO, dosya yaşam döngüsü, frontend varlıkları, Shiny ID'leri ve UX'e dokunulmadı.

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- Git-HEAD diferansiyeli (oturum içi geçici script): eski `config_api.R` (HEAD) + vision helper ile yeni zincir (vision + deep helper + yeni config_api) 4 env senaryosunda `identical(api_config) == TRUE`.
- Odak testler tek tek geçti (0 FAIL / 0 WARN / 0 SKIP): yeni davranış (28), yeni split sözleşmesi (36), kripto davranış (32), api-model-config refactor (35), llm-reasoning overrides (14), stream-io (19), source manifest (165), sections (150), global manifest (12), maintainability ratchet (162), deep-thinking model resolution (16), runtime model resolution (24), api-key effective/identity resolution (35+37), streaming poll lifecycle (67+25), utf8 stream decoder (30), secret leak (8), network boundary (2), production contracts (21), production env policy (8).
- `bash tools/ai_validate.sh full --boot-smoke` → geçti; **tam strict testthat suite dahil**, `failed_steps: 0`, `skipped_steps: 0` (browser UX smoke bu container'da tarayıcı olmadığından bloklamayan SKIP). Artifact yolu aşağıdaki commit mesajında ve `artifacts/ai-validation/` altında.
- `Rscript tests/scripts/maintainability_report.R` → skor 100/100; `config_api.R` 468/2.
- Tüm komutlar `LANG=C.UTF-8 LC_ALL=C.UTF-8` ile çalıştırıldı (container'ın C-locale varsayılanı, koddan bağımsız ortam kısıtı).

### Manuel QA (kullanıcı/VM tarafı)
- Uygulamayı normal Windows VM launcher ile başlatın; başlangıçta kırmızı hata olmadığını ve modellerin Model Değiştir/Yapılandırma listelerinde göründüğünü doğrulayın.
- Excel Analizi ve Kodlama Desteği araçlarında Derin Düşünme düğmesini düşük/yüksek seviyelerde açın; Düşünce Akışı rozetinin beklenen deep modeli gösterdiğini ve yanıtın aktığını doğrulayın.
- Yapılandırma → kişisel API anahtarı kaydedin (sahte/test anahtarı değil, gerçek akışınız neyse o); kaydet → doğrula → temizle akışının çalıştığını, Türkçe karakter içeren bir anahtar değerinin kaydet/yükle sonrası bozulmadığını doğrulayın.
- `api_keys/<kullanıcı>_api_key` dosyasının oluştuğunu ve düz metin anahtar içermediğini (şifreli JSON) doğrulayın.
- Var olan kayıtlı anahtarın (bu değişiklikten önce kaydedilmiş) yeniden yüklenebildiğini doğrulayın (format değişmedi; geriye dönük uyum beklenir).
- Normal Türkçe sohbet + streaming + Durdur akışını bir kez doğrulayın (config_api zinciri her istekte kullanılır).

### Bilinen riskler / atlanan doğrulamalar
- `helpers_api_key_crypto.R` kaynak anında `getwd()/api_keys` klasörünü oluşturur (config_api.R'deki davranışın birebir taşınması). Manifest yük sırası içinde `getwd()` uygulama köküdür; davranış değişmedi.
- Windows VM launcher, gerçek tarayıcı smoke, VM/SSO/gerçek DB preflight ve SQL Server Türkçe encoding preflight bu cloud oturumunda çalıştırılmadı; kullanıcı tarafı manuel QA gereklidir.
- `.Renviron`'daki gerçek üretim deep model kimlikleri cloud'da görünmez; VM'de Derin Düşünme rozet/akış kontrolü önerilir (yukarıdaki QA maddesi).

---

## 2026-06-09 — True streaming yoklama döngüsü kararlarının saf yardımcıya çıkarılması

### Seçilen iz(ler)
- **Track B — Complex runtime kodundan saf yardımcı çıkarımı** (`R/server_handler_true_streaming.R` → `R/helpers_streaming_poll_lifecycle.R`).
- Tamamlayıcı: var olan streaming yaşam döngüsü desenini (`R/helpers_streaming_abort_lifecycle.R` / `mergen_stream_abort_cleanup_plan()`) yoklama tarafına genişletir.

### Özet ve gerekçe
`handle_true_streaming_mode()` içindeki yoklama (poll) observer'ı; akış JSONL satırlarının delta / akıl yürütme / debug olarak sınıflandırılmasını, worker dönüşünde gelen reasoning metninin canlı panelle uzlaştırılmasını (tam metin mi, eksik kuyruk mu, hiçbir şey mi gönderileceği kararı), yoklama aralığı normalizasyonunu ve ertelenen sohbet kalıcılaştırma gecikmesi kararını Shiny observer gövdesine gömülü taşıyordu. Bu kararlar kullanıcıya en görünür regresyon yüzeyidir (akış metni, Düşünce Akışı paneli, `MB_Messages.ReasoningContent` kalıcılığı) ama hiçbiri Shiny/DB/LLM başlatmadan test edilemiyordu.

Dört saf yardımcı `R/helpers_streaming_poll_lifecycle.R` dosyasına çıkarıldı: `mergen_stream_classify_poll_lines()` (satır sınıflandırma; bozuk/yarım satırlar sessizce atlanır, sıra korunur), `mergen_stream_reasoning_recovery_plan()` (none / replace_full / append_suffix kararı; reasoning'in yalnızca final chunk'ta geldiği uçlarda DB'de ReasoningContent'in NULL kalmasını engelleyen yolun saf çekirdeği), `mergen_stream_poll_interval_ms()` ve `mergen_stream_persist_delay()`. Handler aynı custom message payload'larını (`streamingReasoningDelta`, `streamingDelta`, `streamingUpdate`) aynı sırayla gönderen ince bir orkestratöre dönüştü; tüm statik sözleşme çapaları (request-id, finalize/cleanup, reasoning alanları) yerinde kaldı.

### Değişen dosyalar
**Kaynak**
- `R/helpers_streaming_poll_lifecycle.R` (yeni, ~203 satır) — dört saf karar yardımcısı; Shiny/DB/dosya/LLM yan etkisi yok.
- `R/server_handler_true_streaming.R` — inline sınıflandırma döngüsü, reasoning geri kazanım bloğu, poll aralığı ve persist gecikmesi karar satırları helper çağrılarıyla değiştirildi. **690 → 647 satır.**
- `R/config_source_manifest.R` — yeni helper `chat_send_message_runtime` bölümüne `R/helpers_streaming_abort_lifecycle.R` sonrasına eklendi; bölüm yorumu güncellendi.

**Test**
- `tests/testthat/test-streaming-poll-lifecycle-behavior.R` (yeni) — 67 assertion: satır sınıflandırma (bozuk JSON/boş delta/bilinmeyen tip atlanır, sıra korunur, gerçek `decode_stream_delta_payload` ile Türkçe + emoji base64 round-trip), reasoning geri kazanım planının tüm dalları (UTF-8 çok baytlı önek/kuyruk sınırı dahil), yoklama aralığı ve persist gecikmesi kararları.
- `tests/testthat/test-streaming-poll-lifecycle-contract.R` (yeni) — 25 assertion: helper dosyası varlığı ve fonksiyon yüzeyi, manifest sırası (abort → poll → handler), handler delegasyonu, inline mantığın geri dönmemesi, helper'ın yan-etkisiz kalması.
- `tests/testthat/test-source-manifest-sections-contract.R` — `chat_send_message_runtime` bölüm sayısı 8→9, toplam kaynak sayısı 254→255 güncellendi.

**Dokümantasyon**
- `CLAUDE.md` — UX sözleşmeleri bölümüne poll-loop delegasyon kuralı eklendi; kaynak manifest sözleşmesindeki yükleme sırası notu iki streaming helper'ı kapsayacak şekilde genişletildi.
- `docs/architecture-map.md` — LLM/model entegrasyonu ownership satırı ve `chat_send_message_runtime` bölüm satırı `R/helpers_streaming_*` ailesini gösterir.
- `docs/technical-reference.md` — streaming notlarına yoklama döngüsü saf yardımcı sınırı eklendi.
- `docs/refactor-log.md` — bu giriş.

### Önce / sonra karmaşıklık notları
- Önce: satır sınıflandırma + accumulate + ilk-delta logu + custom message gönderimi tek observer gövdesinde iç içeydi; reasoning geri kazanım kararı yalnızca canlı SSE akışıyla uçtan uca tetiklenebiliyordu.
- Sonra: karar mantığı (hangi satır hangi kanala, hangi reasoning parçası gönderilecek, hangi aralık/gecikme) saf fonksiyonlarda; observer yalnızca state yazma ve mesaj gönderme yan etkilerini taşır. 92 yeni deterministik assertion bu kararları offline karakterize eder.
- Maintainability skoru 100/100 korunur; handler 690→647 satıra indi, yeni helper bütçe eşiklerinin çok altında.

### Korunan davranış sözleşmeleri
- Custom message adları, payload alanları ve gönderim sırası değişmedi: reasoning batch'i delta batch'inden önce gönderilir; `started` bayrağı, `requestId` ve mesaj id alanları birebir aynı.
- `test-true-streaming-reset-ui-contract.R`, `test-e2e-premium-reasoning-ui-regression.R`, `test-e2e-streaming-client-request-id-regression.R`, `test-sse-worker-export-contract.R` çapalarının tamamı yerinde (hepsi bu oturumda yeşil).
- Stop/cancel davranışı, `mergen_stream_abort_cleanup_plan()` delegasyonu, stop dosyası üretimi ve `reset_chat_state_fn()` çağrı yolu değişmedi.
- Türkçe/emoji akış metni davranışı korunur: sınıflandırma `decode_stream_delta_payload` (base64 + UTF-8) üzerinden aynı çözücüyle çalışır; davranış testi Türkçe + emoji round-trip'i kanıtlar.
- DB şeması, SSO, dosya yaşam döngüsü, frontend asset/source manifest yükleme davranışı değişmedi (manifest yalnızca yeni helper satırı kazandı).

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- `Rscript -e "testthat::test_file('tests/testthat/test-streaming-poll-lifecycle-behavior.R')"` → geçti (67 PASS / 0 FAIL / 0 WARN / 0 SKIP).
- `Rscript -e "testthat::test_file('tests/testthat/test-streaming-poll-lifecycle-contract.R')"` → geçti (25 PASS).
- Korunan streaming/manifest sözleşmeleri tek tek çalıştırıldı ve geçti: `test-true-streaming-reset-ui-contract.R` (6), `test-e2e-premium-reasoning-ui-regression.R` (40), `test-e2e-streaming-client-request-id-regression.R` (5), `test-sse-worker-export-contract.R` (3), `test-source-manifest-contract.R` (165), `test-source-manifest-sections-contract.R` (150), `test-global-source-manifest-contract.R` (12), `test-send-message-request-lifecycle-contract.R` (42), `test-streaming-abort-lifecycle-smoke.R` (16), `test-e2e-quick-actions-streaming-regression.R` (75), `test-maintainability-ratchet.R` (156), `test-production-contracts.R` (21); tümünde 0 FAIL / 0 WARN.
- Diferansiyel parite kontrolleri (oturum içi geçici script, repoya eklenmedi): eski inline sınıflandırma algoritması ile `mergen_stream_classify_poll_lines()` 300 rastgele fixture denemesinde (Türkçe, emoji, satır sonu, bozuk JSON, boş metin, bilinmeyen tip, base64/düz karışık) 0 uyumsuzluk; eski inline reasoning geri kazanım dalları ile `mergen_stream_reasoning_recovery_plan()` 84 kombinasyonda 0 uyumsuzluk.
- `Rscript tests/scripts/maintainability_report.R` → skor 100/100, refactor adayı yok (260→261 dosya).
- `source("tests/scripts/parse_sanity_check.R")` → OK (732 dosya parse edildi).
- `bash tools/ai_validate.sh quick` → geçti; `failed_steps: 0`, `skipped_steps: 0`. Artifact: `artifacts/ai-validation/20260609-181259/summary.json`.
- `bash tools/ai_validate.sh full --boot-smoke` → geçti; environment OK, parse sanity OK, app source smoke OK, **tam strict testthat suite geçti (132.7 sn)**, Shiny boot smoke geçti; browser UX smoke bu container'da tarayıcı ikilisi olmadığı için bloklamayan SKIP (beklenen davranış). `failed_steps: 0`, `skipped_steps: 0`, `full_validation_status: "passed"`. Artifact: `artifacts/ai-validation/20260609-181405/summary.json`.
- Not: bu cloud container'da R oturumu varsayılan olarak "C" locale ile başlıyor; tüm komutlar `LANG=C.UTF-8 LC_ALL=C.UTF-8` ile çalıştırıldı (önceden var olan ortam kısıtı, kod değişikliğiyle ilgisiz; önceki oturumda görülen unrelated tam-suite hataları bu locale ile yeniden üretilmedi).

### Manuel QA (kullanıcı/VM tarafı)
- Uygulamayı normal Windows VM launcher ile başlatın; kırmızı hata ve yeni browser console hatası olmadığını doğrulayın.
- Ana Söyleşi'de `ç ğ ı İ ö ş ü` içeren basit bir Türkçe mesaj gönderin; akış metninin doğru render edildiğini ve geçmişe doğru kaydedildiğini doğrulayın.
- Uzun bir yanıt başlatıp Durdur'a basın; gönder düğmesinin normale döndüğünü, typing/streaming durumunun takılı kalmadığını ve sonrasında yeni mesajın çalıştığını doğrulayın.
- Düşünme destekli bir modelle (Düşünüyorum=TRUE) soru sorun; Düşünce Akışı panelinin canlı aktığını, yanıt bitince panelin arşiv olarak kaldığını ve kayıtlı sohbeti yeniden yüklediğinizde reasoning arşivinin göründüğünü (SSMS'te `MB_Messages.ReasoningContent` dolu) doğrulayın.
- Reasoning'i yalnızca yanıt sonunda üreten bir uç durum varsa (kısa yanıt + uzun düşünme), panelin yine dolduğunu doğrulayın (geri kazanım yolu).
- Hızlı profil yollarını (Kodlama Desteği hızlı akışı) bir kez deneyin; ilk parçaların gecikmeden aktığını doğrulayın.
- Saved chat reload sonrası eski TTS otomatik oynatma olmadığını teyit edin.

### Bilinen riskler / atlanan doğrulamalar
- Davranış birebir korunacak şekilde tasarlandı; tek bilinçli mikro fark, aynı poll tick'i içinde `stream_debug` log satırlarının artık delta loglarından önce yazılması (yalnızca tanılama log sırası; UI/DB/payload etkisi yok).
- Windows VM launcher, gerçek tarayıcı smoke (`UX_SMOKE_DONE:PASS`), VM/SSO/gerçek DB preflight, SQL Server Türkçe encoding preflight ve gerçek SSE uç noktasıyla canlı akış bu cloud/container oturumunda çalıştırılmadı (summary.json bu sınırları `not_performed_by_ai_validate` olarak işaretler); kullanıcı tarafı manuel QA gereklidir.
- `decode_stream_delta_payload()` içinde önceden var olan bir uç durum gözlemlendi (boş metnin base64'ü `text_b64` alanında `[]`'e dönüşürse `if` koşulu NA üretebilir); üretim yazıcısı `create_stream_line_appender()` boş metni hiç yazmadığı için bu uç gerçek akışta oluşmaz, eski ve yeni yol aynı çözücüyü aynı şekilde çağırır. Bilerek bu oturumda dokunulmadı (cerrahi kapsam); ileride ayrı küçük bir görev olarak ele alınabilir.

---

## 2026-06-09 — Dosya Yönetimi görünen dosya adı normalizasyon sınırı

### Seçilen iz(ler)
- **Track B — Complex runtime kodundan saf yardımcı çıkarımı** (`R/helpers_file_manager_state_runtime.R` yükleme yolu → `R/helpers_file_manager_table.R::fm_normalize_uploaded_file_info()`).
- **Track E — Duplicate mechanism consolidation** (upload state ve tablo satırı görünen ad temizliği artık aynı kanonik helper zincirini kullanır).

### Özet ve gerekçe
Dosya Yönetimi içinde yükleme state yolu, storage-prefix taşıyan kalıcı dosya adlarını elle `recover_display_name_from_storage_name()` ile temizliyordu; tablo satırı yolu ise `fm_clean_file_display_name()` üzerinden benzer fallback zinciri taşıyordu. Bu iki mekanizma aynı görünür davranışı hedeflediği halde farklı noktalarda tutulduğu için Türkçe dosya adı, storage-prefix ve `display` metadata önceliği bakımında gizli coupling oluşturuyordu.

`fm_normalize_uploaded_file_info()` adlı saf yardımcı eklendi. Yardımcı, mümkün olduğunda kanonik `normalize_file_display_name()` davranışına delege eder; `display` metadata önceliğini, storage-prefix temizliğini ve UTF-8/Türkçe karakter onarımını tek sınırda toplar. `fm_clean_file_display_name()` geriye uyumlu wrapper olarak korundu ve aynı yardımcıya bağlandı. `process_uploaded_file()` artık kendi dosya adı temizleme bloğunu taşımıyor; normalize edilmiş `file_info` ve `file_name` değerlerini saf yardımcıdan alıyor.

### Değişen dosyalar
**Kaynak**
- `R/helpers_file_manager_table.R` — `fm_normalize_uploaded_file_info()` eklendi; `fm_clean_file_display_name()` uyumluluk wrapper'ı aynı helper'a delege edecek şekilde sadeleştirildi.
- `R/helpers_file_manager_state_runtime.R` — upload işleme yolundaki yerel storage-prefix temizleme bloğu kaldırıldı ve yeni saf helper çağrısına indirildi.

**Test**
- `tests/testthat/test-file-manager-table-contract.R` — dosya deposu normalizasyon helper'ı test ortamına yüklendi; Türkçe storage-prefix temizliği ve `display` metadata önceliği için deterministik saf helper testleri eklendi.

**Dokümantasyon**
- `docs/architecture-map.md` — Dosya Yönetimi ownership satırı, görünen dosya adı sınırını ve kanonik helper delegasyonunu açıklar.
- `docs/technical-reference.md` — Dosya Yönetimi runtime notlarına upload/tablo görünen ad normalizasyon sınırı eklendi.
- `docs/refactor-log.md` — bu giriş.

### Önce / sonra karmaşıklık notları
- Önce: upload state yolu ve tablo yolu benzer görünen ad temizleme kararlarını ayrı bloklarda taşıyordu.
- Sonra: storage-prefix temizliği, `display` metadata önceliği ve UTF-8/Türkçe onarım tek saf yardımcıyla karakterize edildi; wrapper adı korundu.
- Runtime modül davranışı değişmeden, side-effect içeren `process_uploaded_file()` dosya adı kararından arındırıldı ve daha ince bir orkestratöre dönüştü.

### Korunan davranış sözleşmeleri
- Dosya Yönetimi tablo kolonları, HTML class/selector değerleri, Shiny download/attach ID kalıpları değişmedi.
- Storage-prefix kullanıcıya gösterilmez; `İhale_çalışması.pdf` gibi Türkçe karakterli dosya adları korunur.
- Explicit `display` metadata, storage dosya adından öncelikli kalır.
- File upload/list/preview/analyze, Excel MCP yolu, DB schema, SSO ve frontend asset/source manifest sırası değiştirilmedi.

### Eklenen / güncellenen testler
- `test-file-manager-table-contract.R` içindeki yeni testler:
  - `fm_normalize_uploaded_file_info()` storage-prefix içeren Türkçe dosya adını okunabilir kullanıcı adına indirger.
  - `fm_clean_file_display_name()` compatibility wrapper'ı aynı sonucu üretir.
  - Explicit `display` metadata storage dosya adına üstün gelir.

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- `Rscript tests/scripts/maintainability_report.R` → geçti; skor 100/100, refactor adayı eşiği ihlali yok.
- `Rscript -e "testthat::test_file('tests/testthat/test-file-manager-table-contract.R')"` → geçti.
- `Rscript -e "testthat::test_file('tests/testthat/test-file-lifecycle-hardening-contract.R'); testthat::test_file('tests/testthat/test-file-manager-table-contract.R'); testthat::test_file('tests/testthat/test-file-manager-state-runtime-contract.R')"` → geçti.
- `bash tools/ai_validate.sh quick` → geçti; `failed_steps: 0`, `skipped_steps: 0`.
- `Rscript tests/testthat.R` → başarısız; bu oturumda unrelated environment/repo fixture failures görüldü (`test-claude-code-security-policy-contract.R`, `.Renviron` logout URL fixture, eksik vendored UI assets, upload-validator fixture path). Odak Dosya Yönetimi testleri aynı oturumda geçti.
- `bash tools/ai_validate.sh full --boot-smoke` → başarısız; full suite adımında yukarıdaki unrelated testthat failure sınıfı nedeniyle `failed_steps: 1`. Boot-smoke adımına geçilemedi. Artifact: `artifacts/ai-validation/20260609-143057/summary.json`.

### Manuel QA (kullanıcı/VM tarafı)
- Uygulamayı normal Windows VM launcher ile başlatın; kırmızı hata ve yeni browser console hatası olmadığını doğrulayın.
- Dosya Yönetimi sekmesine gidin.
- `İhale_çalışması_çğıİöşü.txt` gibi Türkçe karakterli bir TXT yükleyin; listede ve preview/attach davranışında okunabilir kaldığını doğrulayın.
- CSV/TXT içinde Türkçe karakterler yükleyip önizleme ve bağlama ekleme davranışını doğrulayın.
- Aynı isimli dosya tekrar yükleme davranışının değişmediğini kontrol edin.
- Excel dosyası yükleyin; yanlış özetleme yoluna girmediğini ve amaçlanan Excel/MCP analiz yolu için kullanılabilir kaldığını kontrol edin.
- Kaydedilmiş söyleşiye dosya referansı ekleyip reload/history sonrasında görünen adın ve Türkçe karakterlerin korunduğunu doğrulayın.

### Bilinen riskler / atlanan doğrulamalar
- Bu refactor dosya adı kararını saf helper'a taşıdı; DB schema, frontend varlıkları, SSO ve Excel okuyucu davranışı bilerek değiştirilmedi.
- Windows VM launcher ve gerçek tarayıcı smoke bu cloud/container oturumunda çalıştırılmadı; kullanıcı tarafı manuel QA gereklidir.

---


## 2026-06-09 — Proje/Kaynak Analizi sezgisel sorgu skorlamasının saf yardımcıya çıkarılması

### Seçilen iz(ler)
- **Track B — Complex runtime kodundan saf yardımcı çıkarımı** (`R/module_proje_kaynak_analizi.R` → `R/helpers_pk_analysis_query_selection.R`).
- Tamamlayıcı: var olan PK helper bölme desenini (core/filters/security-summary) sürdürür.

### Özet ve gerekçe
`select_smart_query()` içindeki "Akıllı Sorgu Seçici" sezgisel skorlama mantığı (isim alt-dize +50, isim kelime ×10, açıklama kelime ×2, yedi Türkçe alan anahtar kelime bonusu +8, max'a göre %100 normalizasyon, `THRESHOLD_RAW=2`/`THRESHOLD_PCT=30` eşiği) limite yakın bir modülün (717 satır) içinde, AI çağrısı + `cat` + oturum yan etkileriyle iç içe gömülüydü ve **hiç testi yoktu**. Bu, ileride bir bakımcının ağırlıkları/anahtar kelimeleri değiştirmesi durumunda sessiz regresyon riski taşıyan, gerçek iş kuralı içeren bir karar mantığıdır.

Skorlama ve skor-tablosu raporlaması saf bir yardımcı dosyaya çıkarıldı; `select_smart_query()` orkestratör olarak modülde kaldı (AI seçimi + `find_best_query_with_ai()` çağrısı + `cat` + sonuç montajı) ve artık çıkarılan saf yardımcıları çağırıyor. Davranış birebir korunur.

### Değişen dosyalar
**Kaynak**
- `R/helpers_pk_analysis_query_selection.R` (yeni, ~140 satır) — `pk_init_query_score_table()`, `pk_score_query_relevance()`, `pk_compute_heuristic_query_scores()` ve taşınan `print_score_table()`.
- `R/module_proje_kaynak_analizi.R` — `pk_required_helpers` fallback listesine yeni helper eklendi; `select_smart_query()` skorlama bloğu helper çağrılarıyla değiştirildi; `print_score_table()` modülden kaldırıldı. **717 → 633 satır.**
- `R/config_source_manifest.R` — yeni helper `analysis_helpers` bölümüne (filters sonrası, modül öncesi) eklendi.

**Test**
- `tests/testthat/test-pk-analysis-query-selection-behavior.R` (yeni) — saf skorlama kurallarını elle hesaplanmış beklenen değerlerle karakterize eder (önceden testsizdi).
- `tests/testthat/test-pk-analysis-query-selection-refactor-contract.R` (yeni) — dosya varlığı, helper'ların açığa çıkması, kaynak sırası (filters → query_selection → module), modülün artık taşınan helper'ları içermemesi, fallback referansının korunması ve helper'ın yan-etki-hafif olması.
- `tests/testthat/test-source-manifest-sections-contract.R` — `analysis_helpers` çapası (`last`/`n` 4→5) ve toplam dosya sayısı (253→254) güncellendi.

**Dokümantasyon**
- `CLAUDE.md` — yeni "Proje/Kaynak Analizi query-selection modularization contract" bölümü; `global.R` yükleme sırası listesine helper eklendi.
- `docs/refactor-log.md` — bu giriş.

### Önce / sonra karmaşıklık notları
- `R/module_proje_kaynak_analizi.R`: 717 → 633 satır (limite-yakın dosyada ~84 satır rahatlama).
- Önceden testsiz, gömülü sezgisel skorlama → adlandırılmış, saf, deterministik test edilen üç yardımcı.
- Maintainability skoru: 100/100 (değişmedi); değerlendirilen dosya 259 → 260; en büyük dosya satırı 760 ve en yüksek fonksiyon sayısı 24 (etkilenmedi).

### Korunan davranış sözleşmeleri
- Skorlama formülü ve `all_scores` tablo yapısı birebir korunur; yedi Türkçe alan-bonus `grepl()` deseni bayt-bayt aynı (UTF-8).
- `select_smart_query()` orkestratör olarak modülde kalır; `R/helpers_deep_analysis.R` çağrısı etkilenmez.
- AI seçim dalı, eşik kararı, heuristic seçim metodu/gerekçesi ve `cat` çıktıları korunur.
- Türkçe karakter bütünlüğü ve UTF-8 korunur; mojibake yok.

### Eklenen / güncellenen testler
- Yukarıdaki iki yeni test + bölüm sözleşmesi güncellemesi.

### Gerçekten çalıştırılan doğrulamalar (bu cloud oturumunda)
- **Eşdeğerlik kanıtı (en güçlü):** geçici bir koşum aracıyla HEAD orijinal modül vs refactor edilmiş (helper + modül) `select_smart_query()` sezgisel sonuçları **72 (3 kütüphane × 24 prompt) vakada birebir aynı** (`FULL_EQUIVALENCE_OK`); ayrıca 8 vakalık baseline `EQUIVALENCE_OK`. Bu araç commit edilmedi.
- `Rscript tests/scripts/parse_sanity_check.R` → `OK: 729 dosya parse edildi.`
- `Rscript tests/scripts/maintainability_report.R` → Skor 100/100, 0 eşik ihlali.
- Odaklı testler (C.utf8 locale ile, app helper yüklemeden doğrudan source): `test-pk-analysis-query-selection-behavior.R`, `test-pk-analysis-query-selection-refactor-contract.R`, `test-source-manifest-sections-contract.R`, `test-source-manifest-contract.R`, `test-pk-analysis-maintainability-contract.R`, `test-pk-analysis-filters-refactor-contract.R`, `test-pk-analysis-core-refactor-contract.R`, `test-pk-analysis-security-summary-contract.R`, `test-maintainability-ratchet.R`, `test-global-source-manifest-contract.R`, `test-production-contracts.R` → hepsi geçti, başarısızlık yok.
- `bash tools/ai_validate.sh cloud-quick` → `failed_steps: 0`, `skipped_steps: 1`; `summary.json`: `profile_requested="cloud-quick"`, `profile_effective="quick"`, `parse sanity: OK`, `app source smoke: SKIPPED`, `focused contract tests: passed`.

### Manuel QA (kullanıcı/VM tarafı)
- Uygulamayı normal Windows VM başlatıcısıyla başlatın; kırmızı hata olmadan açıldığını doğrulayın.
- "Proje ve Kaynak Analizi" hızlı eylemini açın; Türkçe bir analiz sorusu sorun (ör. "proje bütçe durumu nedir", "aktivite gecikme süresi", "kaynak personel atama").
- Konsol/loglarda `SORGU İLGİLİLİK SKORLARI` tablosunun ve `Heuristic EN IYI ESLESME` / `Hicbir sorgu yeterli skora ulasamadi` mesajlarının eskisiyle aynı davrandığını doğrulayın.
- AI tabanlı sorgu seçiminin (gerçek LLM ile) ve heuristic'e düşüş yolunun çalıştığını doğrulayın.
- Türkçe karakterlerin (ç, ğ, ı, İ, ö, ş, ü) doğru render edildiğini doğrulayın.

### Bilinen riskler / bilinçli atlanan doğrulamalar
- Bu cloud checkout'unda tam strict suite (`tests/testthat.R`) ortam nedeniyle (locale `C`, eksik `.Renviron`/`www` varlıkları; `helper-load-app.R` app boot'u başarısız) eksiksiz tamamlanmaz. Odaklı testler bu nedenle minimum kurulumla `C.utf8` locale altında doğrudan source edilerek çalıştırıldı; sonuçlar geçerlidir.
- `cloud-quick` tam runtime/app boot, gerçek tarayıcı UX, VM/SSO/DB veya SQL Server Türkçe encoding doğrulaması DEĞİLDİR; bunlar VM tarafı gate'leridir ve bu oturumda çalıştırılmadı.
- **Tespit edilen, kapsam dışı bırakılan ön-var olan kenar durumu (refactor kaynaklı değil):** hem HEAD hem refactor, bir sorgu kaydının `name = NULL` olması durumunda `grepl(name_clean, ...)` ile aynı şekilde hata verir (`tolower(NULL)` → `character(0)`). Skorlama `%||%` ile korunmamıştır; gerçek kütüphanede isimler her zaman dolu olduğundan davranış değiştirilmedi (davranış-koruma ilkesi). İleride istenirse ayrı bir bugfix olarak ele alınabilir.

---

## 2026-06-09 — Kaynak manifestinin özellik bölümlerine ayrılması

### Seçilen iz(ler)
- **Track D — Manifest sectioning without load-order change** (`R/config_source_manifest.R`).
- Tamamlayıcı doküman tarafı: özellik sahipliği haritası (`docs/architecture-map.md`).

### Özet ve gerekçe
255+ R dosyası içeren depoda en çok okunan "içindekiler" dosyası, çalışma zamanı kaynak manifestidir. Manifest daha önce yalnızca boş satırlarla gruplanmış, etiketsiz ve düz bir liste (`source_manifest_after_future_paths`) idi; bir bakımcı "X özelliği hangi dosyalarda?" sorusunu yanıtlamak için tek tek grep yapmak zorundaydı.

Manifest artık özellik/katman ailelerine göre adlandırılmış, açıklamalı **35 bölümden** oluşan tek bir sıralı liste (`source_manifest_sections`) olarak düzenlendi. Çalışma zamanı yükleme sırası **birebir korunur**: üç kanonik nesne bu bölümlerden türetilir ve `unlist(source_manifest_sections, use.names = FALSE)` değeri eski `source_manifest_runtime_paths` ile bayt bayt aynıdır.

Bu, davranışsal olarak sıfır risk taşır (yalnızca yorumlar ve adlandırılmış bölümleme eklenir; yükleme sırası değişmez) ama onboarding için yüksek kaldıraçlıdır.

### Değişen dosyalar
**Kaynak**
- `R/config_source_manifest.R` — düz `c(...)` listesi, adlandırılmış bölüm listesi (`source_manifest_sections`) + türetme olarak yeniden yapılandırıldı. Üç kanonik nesne (`source_manifest_group_1_paths`, `source_manifest_after_future_paths`, `source_manifest_runtime_paths`) korunur ve bölümlerden türetilir.

**Test**
- `tests/testthat/test-source-manifest-sections-contract.R` (yeni) — bölüm sırasını, türetme bütünlüğünü, bölüm sınır dosyalarını (ilk/son çapaları) ve toplam dosya sayısını dondurur.

**Dokümantasyon**
- `docs/architecture-map.md` — "Özellik bölümleri (onboarding haritası)" alt bölümü eklendi (bölüm → özellik → giriş noktası tablosu).
- `CLAUDE.md` — kaynak manifesti sözleşmesi, bölümlenmiş yapıyı ve yeni testi yansıtacak şekilde cerrahi olarak güncellendi.
- `docs/refactor-log.md` (yeni) — bu günlük oluşturuldu.

### Önce / sonra karmaşıklık notları
- Önce: 283 satır, etiketsiz boş-satır grupları, tek düz `after_future` vektörü; özellik sınırları örtük.
- Sonra: 484 satır, 35 adlandırılmış özellik/katman bölümü, her bölümde kısa Türkçe açıklama; özellik sahipliği açık ve greplenebilir.
- Yükleme sırası: değişmedi (bayt bayt aynı 253 yol; doğrulandı).
- Maintainability skoru: 100/100 (değişmedi); manifest fonksiyon sayısı 0 (değişmedi); en büyük dosya satırı 760 (etkilenmedi; manifest sınırın çok altında).

### Korunan davranış sözleşmeleri
- Üç kanonik manifest nesnesi adları ve değerleri birebir korunur.
- `source_manifest_runtime_paths == c(source_manifest_group_1_paths, source_manifest_after_future_paths)` değişmez.
- `global.R` bootstrap/yükleme çağrıları değişmedi (`source_manifest_load(source_manifest_group_1_paths)` / `... after_future`).
- `R/bootstrap_source_manifest.R` doğrulaması (nesne varlığı, tekrar, eksik dosya, parse, sıra kuralları) aynen geçerli.
- Tüm yol dize literalleri dosya metninde korunduğu için metin tabanlı sözleşme testleri (logout, ui-asset, streaming-markdown vb.) etkilenmez.
- Türkçe karakter bütünlüğü ve UTF-8 korunur; mojibake yok.

### Eklenen / güncellenen testler
- `tests/testthat/test-source-manifest-sections-contract.R`: dondurulmuş bölüm sırası (35 anahtar), bölüm başına ilk/son dosya ve eleman sayısı çapaları, türetme bütünlüğü (`group_1 = foundation`, `after_future = unlist(sections[-1L])`, `runtime = c(...)`, `unlist(sections) = runtime`), tekrar yok ve toplam 253 dosya.

### Gerçekten çalıştırılan doğrulamalar (bu cloud oturumunda)
- `bash tools/ai_validate.sh cloud-quick` → `failed_steps: 0`, `skipped_steps: 1`; `summary.json`: `profile_requested="cloud-quick"`, `profile_effective="quick"`, `parse sanity: OK`, `app source smoke: SKIPPED`, `focused contract tests: passed`.
- `testthat::test_file("tests/testthat/test-source-manifest-sections-contract.R")` → PASS.
- `testthat::test_file("tests/testthat/test-source-manifest-contract.R")` → 165 PASS / 0 FAIL.
- `testthat::test_file("tests/testthat/test-global-source-manifest-contract.R")` → 12 PASS / 0 FAIL.
- `testthat::test_file("tests/testthat/test-production-contracts.R")` → 21 PASS / 0 FAIL.
- `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")` → 156 PASS / 0 FAIL.
- R ile bayt bayt yükleme sırası karşılaştırması: yeni manifest `source_manifest_runtime_paths` == eski (HEAD) sürüm (TRUE).
- `R/bootstrap_source_manifest.R` `source_manifest_try_parse_file` + `source_manifest_validate_config_objects`: PARSE_OK + CONFIG_OBJECTS_OK.

### Manuel QA (kullanıcı/VM tarafı)
Bu değişiklik runtime davranışını değiştirmez, ancak boot manifestine dokunduğu için VM'de bir kez doğrulanması önerilir:
- Uygulamayı normal Windows VM başlatıcısıyla başlatın; kırmızı hata olmadan açıldığını doğrulayın.
- Ana Söyleşi karşılama ekranı, hızlı eylemler, Dosya Yönetimi, Bilge Yolaç ve Yönetici/Sistem Durumu sayfalarının yüklendiğini doğrulayın.
- Türkçe karakter içeren bir mesaj gönderip yanıtın doğru render edildiğini doğrulayın.
- (İsteğe bağlı) VM'de `bash tools/ai_validate.sh full --boot-smoke` ile boot smoke çalıştırın.

### Bilinen riskler / bilinçli atlanan doğrulamalar
- Bu cloud checkout'unda `.Renviron` ve bazı `www` varlıkları bulunmadığından tam strict suite (`tests/testthat.R`) eksiksiz tamamlanmaz. `test-logout-url-contract.R` (2), `test-ui-asset-manifest-contract.R` (1) ve `test-claude-code-security-policy-contract.R` (2) başarısızlıkları ORİJİNAL manifestle de birebir oluşur; bu değişiklikten kaynaklanmaz (CLAUDE.md cloud notlarıyla uyumlu, ortam kaynaklı).
- `cloud-quick` tam runtime/app boot, gerçek tarayıcı UX, VM/SSO/DB veya SQL Server Türkçe encoding doğrulaması DEĞİLDİR; bunlar VM tarafı gate'leridir ve bu oturumda çalıştırılmadı.

---

## 2026-06-09 — UI asset manifest sectioning without order change

### Seçilen iz(ler)
- **Track D — Manifest Sectioning Without Load-Order Change** (`R/config_ui_assets.R` CSS `page` ve JS `deferred` listeleri).

### Özet ve gerekçe
`R/config_ui_assets.R` içinde en uzun onboarding yükü, tek blok hâlindeki `page` CSS listesi ve `deferred` JS listesindeydi. Bu listeler çalışma zamanı açısından hassas olduğu için dosya taşımak, selector değiştirmek veya asset sırasını değiştirmek yerine yalnızca manifestin okunabilirlik sınırı iyileştirildi.

CSS `page` listesi tema tabanı, light theme modülleri, light override katmanları, layout temeli, navigasyon/araç yüzeyleri, feature yüzeyleri ve enterprise/Bilge Yolaç katmanı olarak adlandırıldı. JS `deferred` listesi code/table, welcome/media, modal/analysis tools ve admin/enterprise alt bölümlerine ayrıldı. Her iki yol da `ui_asset_flatten_groups()` ile aynı adsız vektöre indirildiği için UI tag üretimi, `defer` planı ve tarayıcı yükleme sırası değişmedi.

### Değişen dosyalar
**Kaynak**
- `R/config_ui_assets.R` — `ui_asset_flatten_groups()` helper'ı manifest listelerinden önce tanımlandı; uzun `page` CSS ve `deferred` JS listeleri named alt bölümlere ayrıldı; `ui_asset_public_root()` içindeki unreachable duplicate `return(root)` temizlendi.

**Test**
- `tests/testthat/test-ui-asset-manifest-contract.R` — sectioning refactor'ının `ui_asset_css_groups$page` ve `ui_asset_js_groups$deferred` vektörlerini birebir değiştirmediğini doğrulayan sıra sözleşmesi eklendi.

**Dokümantasyon**
- `docs/architecture-map.md` — UI asset manifestinin bölümleme/onboarding sınırı ve order-stability testi açıklandı.
- `docs/technical-reference.md` — sectioning'in runtime/tag/defer sözleşmesini değiştirmediği ve ilgili test koruması eklendi.
- `docs/refactor-log.md` — bu giriş.

### Önce / sonra karmaşıklık notları
- Önce: maintainer'ın uzun CSS/JS vektörlerinde tema, feature, media, admin ve Bilge Yolaç assetlerini tek listede zihinsel olarak ayırması gerekiyordu.
- Sonra: uzun listeler feature/layer başlıklarıyla okunuyor; final vektör tek kaynakta kalıyor ve order stability testle donduruluyor.
- Runtime dosyaları, frontend selector'ları, Shiny input/output ID'leri, browser message adları veya asset dosya adları değiştirilmedi.

### Korunan davranış sözleşmeleri
- CSS/JS dosya sırası ve `ui_asset_all_css()` / `ui_asset_all_js()` çıktıları korunur.
- `ui_asset_js_render_plan`, `ui_asset_deferred_js_groups`, `defer` davranışı ve `ui_asset_js_order_rules` korunur.
- Encoding, streaming markdown safety, TTS/STT/media, SSO, Bilge Yolaç, admin/health ve tema assetleri aynı dosya yollarıyla yüklenmeye devam eder.
- Türkçe dokümantasyon metni UTF-8 korunarak yazıldı; DB schema, renv.lock, source manifest ve runtime davranışı değiştirilmedi.

### Eklenen / güncellenen testler
- `test-ui-asset-manifest-contract.R` içindeki yeni test:
  - `ui_asset_css_groups$page` tam vektörünün sectioning sonrası beklenen sırayla birebir aynı kaldığını doğrular.
  - `ui_asset_js_groups$deferred` tam vektörünün sectioning sonrası beklenen sırayla birebir aynı kaldığını doğrular.
  - Flatten edilmiş manifest vektörlerinde isim sızıntısı olmadığını doğrular.

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- `Rscript tests/scripts/maintainability_report.R` → geçti; skor 100/100.
- `Rscript -e "source('R/config_ui_assets.R', encoding='UTF-8'); ui_asset_validate(root='.', check_files=FALSE); cat(length(ui_asset_all_css()), length(ui_asset_all_js()), '\n')"` → geçti; CSS/JS sayıları `95 120`.
- `Rscript -e "testthat::test_file('tests/testthat/test-ui-asset-manifest-contract.R')"` → başarısız; yeni sıra testi geçti, ancak mevcut fixture ortamında vendored `www/codemirror`, `www/lib/threejs` ve `www/css/all.min.css` dosyaları eksik olduğu için aynı test dosyasının `check_files = TRUE` offline asset varlık kontrolü başarısız oldu.
- `Rscript tests/testthat.R` → başarısız; mevcut fixture/env sınıfında Bilge Yolaç security prompt traversal beklentisi, eksik `.Renviron` logout URL fixture'ı, eksik vendored UI assets ve upload-validator fixture path kontrolleri fail verdi. Yeni UI manifest sıra testi bu koşuda geçti (`ui-asset-manifest-contract: ....5.6.....................` çıktı nokta/başarılı assertion akışında yeni test assertion'larını içerir), ancak dosyanın mevcut asset varlık kontrolü aynı eksik vendored assetlerle başarısız kaldı.
- `bash tools/ai_validate.sh quick` → geçti; `failed_steps: 0`, `skipped_steps: 0`, artifact: `artifacts/ai-validation/20260609-153404/summary.json`.

### Manuel QA (kullanıcı/VM tarafı)
- Uygulamayı normal Windows VM launcher ile başlatın; kırmızı hata ve yeni browser console hatası olmadığını doğrulayın.
- Hard refresh yapın; dark theme ve welcome ekranının aynı render edildiğini kontrol edin.
- Light theme destekleniyorsa açık temaya geçin; welcome, chat, modal, Dosya Yönetimi, admin/health, destek ve Bilge Yolaç yüzeylerinde yeni koyu/leaky yüzey olmadığını kontrol edin.
- Ana Söyleşi'de Türkçe karakterli bir mesaj (`ç, ğ, ı, İ, ö, ş, ü`) gönderin; streaming ve Stop davranışını kontrol edin.
- Dosya Yönetimi'nde Türkçe adlı TXT/CSV yükleyin; liste/önizleme görünümünün değişmediğini kontrol edin.
- Bilge Yolaç sekmesini açın; arayüz ve streaming/cancel davranışında console hatası olmadığını kontrol edin.

### Bilinen riskler / atlanan doğrulamalar
- Bu refactor frontend dosyalarının içeriğine dokunmadı; browser smoke manuel VM QA'ya bırakıldı.
- `check_files = TRUE` asset varlık testi mevcut cloud/container fixture'ında eksik vendored assetler nedeniyle başarısız olabiliyor; Windows/on-prem paketlenmiş asset ortamında ayrıca doğrulanmalıdır.
- Source manifest, DB schema/encoding, SSO, file lifecycle, streaming logic ve `renv.lock` bilerek değiştirilmedi.

## 2026-06-11 — Açık tema mimarisinin alan-odaklı konsolidasyonu (13 dosyalık override zincirinin kaldırılması)

### Sorun
Açık tema, 13 dosyalık sıralı bir override/patch zinciriydi (`theme_light.css` + `extras` + `refinements` + 6 modül + `polish` + `overhaul` + `overhaul_phase2` + `user_polish` + `user_polish_v2`): toplam ~10.7k satır (tüm CSS'in ~%33'ü), aynı seçici 5-8 kez yeniden tanımlanıyor, ~2.480 `!important` bildirimi katmanlar arası savaşıyordu. Kaskad analizi iki yapısal sorunu kanıtladı: (1) tüm bildirimlerin %25'i (2.485/9.943) sonraki katmanlarca ezilen ÖLÜ bildirimdi; (2) benzersiz 2.334 (media, seçici) anahtarının 1.082'si (%46) DOM'da hiç var olmamış HAYALET sınıf/attribute'lara bağlıydı (`.fm-drop-zone`, `.file-preview-modal`, `.yenilikler-page`, `[data-cc-badge]`, `[data-thinking-toggle]` vb. — runtime R/JS kaynaklarında adı geçmeyen, tahminle yazılmış seçiciler). "Bazı açık tema seçenekleri beklendiği gibi davranmıyor" şikayetinin kök nedeni buydu: cila katmanları kısmen hiç eşleşmeyen seçicilere yazılmıştı.

### Yapılan
- Zincirin kaskad sonucu (media bağlamı + özgüllük + `!important` + kaynak sırası hesaplanarak) anahtar başına KAZANAN bildirim kümesi olarak çıkarıldı; bağımsız bir doğrulayıcı ile eski zincir ↔ yeni dosyalar birebir eşdeğer kanıtlandı (0 kayıp anahtar, 0 kazanan-bildirim farkı, 0 dosyalar-arası sıra riski).
- Hayalet seçiciler iki aşamalı güvenlik filtresiyle ayıklandı: tam-ad grep (R/, www/js, www/smoke, kök R dosyaları, tema dışı CSS) + dinamik üretim öneki koruması (`paste0("health-status-", ...)`, `'cc-message-' +`, `toast-${...}` aileleri ASLA silinmedi) + vendor sınıf desenleri (Bootstrap/DataTables/Shiny/highcharts/CodeMirror) korundu.
- Kalan 1.252 anahtar YEDİ alan dosyasına yerleştirildi (her seçici tam BİR kez): `theme_light_core.css` (kabuk), `welcome`, `chat`, `modals`, `bilge_yolac`, `personalization`, `pages`. En sık literal renkler token'lara bağlandı (`var(--mb-brand-primary)` vb.).
- Plotly grid CSS'i (motor runtime'dan kaldırılmıştı) ve yalnızca hayalet kurallarca kullanılan `@keyframes mergen-cpu-core-pulse` ölü kod olarak silindi.
- Manifest (`R/config_ui_assets.R` grupları + `ui_asset_css_order_rules`), bölge haritası (`R/config_ui_asset_zones.R` `tema` bölgesi), CLAUDE.md tema sözleşmesi, `docs/architecture-map.md` ve `docs/technical-reference.md` yeni mimariye güncellendi.
- Gelecek koruması: `test-theme-light-modular-contract.R` yeniden yazıldı (dondurulmuş dosya kümesi + 8 eski dosya adı için tombstone + tema dosyaları arası TEK-TANIM sözleşmesi + `html[data-theme="light"]` kapsam disiplini ve belgeli kapsamsız allowlist + yalnızca GERÇEK seçici çapaları). `frontend_maintainability_report.R` artık tema bölgesi toplam satırını, dosyalar-arası light-tekrar seçici sayısını ve tombstone ihlalini raporluyor; `test-frontend-maintainability-ratchet.R` bunları bütçeyle bağlıyor (light-tekrar ≤ 44, tema bölgesi ≤ 6.400 satır, tombstone = 0).
- `test-ui-asset-manifest-contract.R` ve `test-tool-background-lifecycle-contract.R` yeni zincire göre güncellendi; `module_saved_chats.R` / `module_image_gallery.R` içindeki bayat dosya-adı yorumları düzeltildi.

### Sonuç
- Tema bölgesi: ~10.7k → 5.6k satır (%48 küçülme); CSS toplamı ~32.0k → ~27.1k satır.
- `html[data-theme="light"]` kapsamlı dosyalar-arası tekrar seçici: ~150+ çoklu-katman kopyasından 44 adede (tamamı bilinçli tema+bileşen 2x çifti) indi; tema dosyaları İÇİNDE tekrar 0.
- Eski testin bazı çapalarının (örn. `blur(18px)`) hiç uygulanmayan ölü metin olduğu kanıtlandı; yeni test gerçek kazanan değerlere (`blur(10px) saturate(132%)`) çapalandı.
- JS denetimi: manifest JS dosyalarında ölü dosya bulunamadı; tema-düşmanı inline renk ataması yok; `theme_manager.js` R senkronizasyonu sağlam. JS tarafında riskli cerrahi gerekmedi.

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- Node tabanlı kaskad eşdeğerlik doğrulayıcısı → `EŞDEĞER ✓` (0 kayıp / 0 fark / 0 sıra riski).
- `Rscript tests/scripts/parse_sanity_check.R` → OK (749 dosya).
- `testthat::test_file` yeşil: theme-light-modular (96), ui-asset-manifest (224), ui-asset-zones (17), frontend-maintainability-ratchet (89, yeni disiplin testi dahil), frontend-selector (80), tool-background-lifecycle (21), brand-title (22), sidebar-theme-sync (19), ux-regression-guardrails (28), accessibility (38), tool-backgrounds (39), browser-smoke-harness (12), smoke-probes (6), runtime-network-boundary (2), e2e-boot-welcome (29; `logger` paketi kurulduktan sonra tam geçti — ilk hata bu cloud ortamındaki eksik paketti, kod regresyonu değildi).
- `bash tools/ai_validate.sh quick` → geçti; `failed_steps: 0`, `skipped_steps: 0`, app source smoke dahil. Artifact: `artifacts/ai-validation/20260611-185513/summary.json`.

### Manuel QA (kullanıcı/VM tarafı)
- Açık temaya geçin ve şu yüzeyleri gezin: karşılama ekranı (cam kart + hızlı eylemler + son konuşmalar), Ana Söyleşi (baloncuklar, giriş alanı, mesaj eylemleri, derin düşünme), modallar (geri bildirim, STT, dosya önizleme, API anahtarı), Bilge Yolaç (AJAN/karakter rozetleri, tool blokları), Kişiselleştirme + Yapılandırma, Dosya Yönetimi, Söyleşi Geçmişi/Kayıtlı/Galeri (ay grupları), Destek sayfaları (NPS butonları, Yenilikler rozetleri), Yönetici panelleri ve Sistem Durumu.
- Koyu temada aynı yüzeylerde değişiklik OLMAMALI (kapsamsız taban kurallar korunmuştur).
- Tema geçiş butonunu birkaç kez ileri-geri kullanın; sayfa yenilemesi sonrası tema kalıcılığını doğrulayın.

### Bilinen riskler / atlanan doğrulamalar
- Eşdeğerlik kanıtı statik kaskad düzeyindedir; gerçek tarayıcı görsel doğrulaması bu cloud ortamında yapılamadı (tarayıcı yok) ve VM manuel QA'ya bırakıldı.
- Hayalet seçici silme kararı tam-ad + üretim-öneki + vendor-desen taramasına dayanır; teorik kalan risk, kaynak dışından (ör. tarayıcı eklentisi) eklenen sınıflar içindir ve üretimde beklenmez.
- Bileşen CSS dosyalarındaki (chat_header, sidebar_user_panel, surum_bilgilendirme vb.) component-owned light kuralları bilinçli yerinde bırakıldı; 44 adetlik 2x tema+bileşen çifti ratchet bütçesiyle sınırlandı.
- `code_highlighting.css` içindeki `hljs-*` kuralları (highlight.min.js yalnızca on-prem VM kopyasında mevcut) ve `health_check.css` mirası bu kapsamda BİLEREK değiştirilmedi; ayrı değerlendirme gerektirir.

## 2026-06-11 — Bileşen CSS hayalet seçici temizliği ve kalıcı orphan taraması (Faz H)

### Sorun
Açık tema konsolidasyonu hayalet seçicilerin tema zinciriyle sınırlı olmadığını gösterdi. Aynı denetimli yöntem (tam-ad corpus taraması + İNCELENMİŞ dinamik üretim önekleri + vendor desenleri) tüm bileşen CSS'ine uygulandığında: tamamı ölü 3 dosya (`capabilities.css`, `health_check.css`, `recent_chats_custom.css` — modern karşılama öncesi eski welcome ailesi ve legacy sağlık stilleri) ve 29 dosyada ~149 ölü kural bulundu (eski welcome ekranı kalıntıları, BS4-stili kullanılmayan spacing utility'leri, var olmayan modal/sınıf adlarına yazılmış kurallar).

### Kritik metodoloji bulgusu
İlk önek listesi orta-string birleştirmeleri kaçırıyordu: `paste0("destek-tag-btn destek-tag-", renk)`, `"alo-ch alo-tok-" + tok.c`, `paste0("cc-dir-item cc-dir-", tip)`, `'... destek-chatbot-message-' + tip` gibi aileler corpus genelinde "önek-ile-biten string literal" taramasıyla TEK TEK incelenip korumaya alındı; `health-`/`index-health-` eşleşmelerinin tempfile pattern'i olduğu (sınıf üretimi OLMADIĞI) doğrulandı. İtilmiş tema konsolidasyonu bu sıkı listeye karşı yeniden doğrulandı: yanlış silinen kural YOK (0).

### Yapılan
- 3 tamamı-ölü dosya silindi; manifest (`navigation_and_tools`), bölge haritası (`sohbet_girisi_mesajlar`, `karsilama_intro`, `yonetici_saglik`) ve `test-ui-asset-manifest-contract.R` listesi birlikte güncellendi; `test-e2e-health-dashboard-regression.R` canlı stil kaynağına (`health_dashboard.css`) yeniden çapalandı.
- 29 dosyada 149 ölü kural yerinde silindi (span-koruyucu araç: hayatta kalan kurallar bayt-bayt aynı; kurala bitişik yorumlar birlikte kaldırıldı; boşalan @media blokları temizlendi). Grup içinde canlı üyesi olan seçiciler BİLİNÇLİ bırakıldı (kural canlı).
- BİLİNÇLİ atlananlar: `brand_title.css` (10 ölü kural — sözleşme testi ölü `.mergen-brand-*` sınıflarını metin olarak sabitliyor; bilinçli sözleşme güncellemesi gerektirir), `theme_tokens.css` (tek orphan grup üyesi), `tool-bg-caret` benzeri sözleşme-yorumunda anılan tarihsel sınıflar yalnızca test yorumunun izin verdiği biçimde kaldırıldı.
- Kalıcılaştırma: hayalet seçici taraması `tests/scripts/frontend_maintainability_report.R` içine taşındı (runtime corpus + vendor desenleri + incelenmiş `frontend_orphan_constructed_prefixes` listesi); `test-frontend-maintainability-ratchet.R` toplamı bütçeyle bağladı: global ölü seçici ≤ 42 (taban: brand_title 18 + canlı-grup kalıntıları), tema alan dosyaları ≤ 7.

### Sonuç
- CSS ~26.9k → ~26.0k satır; tamamı-ölü kural kalan tek dosya bilinçli atlanan `brand_title.css`.
- Yeni hayalet seçici eklemek artık ratchet kırar; yeni dinamik sınıf ailesi eklerken önek listesine bilinçli kayıt gerekir.

### Gerçekten çalıştırılan doğrulamalar (bu oturumda)
- Odaklı süitler yeşil: frontend-maintainability-ratchet (92), ui-asset-manifest (224), ui-asset-zones (17), theme-light-modular (96), e2e-health-dashboard (45), tool-background-lifecycle (21), frontend-selector (80).
- `bash tools/ai_validate.sh full --boot-smoke` bu girdinin yazıldığı sırada arka planda koşuyordu; sonucu commit mesajında ve oturum raporunda beyan edilir.

### Manuel QA (kullanıcı/VM tarafı)
- Sistem Durumu panosunu açın (stil kaynağı artık yalnız `health_dashboard.css`); kart/tooltip görünümünü iki temada doğrulayın.
- Dosya Yönetimi başlığı ("Yüklenen Dosyalar" `.section-title`), karşılama ekranı, Yenilikler rozeti ve Bilge Yolaç yüzeylerinde değişiklik OLMAMALI.

### Bilinen riskler / atlanan doğrulamalar
- Tarayıcı görsel doğrulaması yine cloud'da yapılamadı; silinen her kural "DOM'da eşleşmesi imkânsız" kanıtına dayanır (sınıf hiçbir runtime kaynağında yok + dinamik üretim önekleri korunmuş).
- `brand_title.css` ölü kuralları ve `code_highlighting.css` hljs bloğu bilinçli yerinde; ayrı sözleşme kararı gerektirir.

## 2026-06-12 — brand_title.css hayalet sınıf API'sinin kaldırılması ve sözleşmenin token mekanizmasına yeniden çapalanması

### Karar
`test-brand-title-single-source-contract.R`, DOM'da hiç var olmamış `.mergen-brand-title*` paralel sınıf API'sini metin olarak sabitliyordu. İnceleme, tek-kaynak hizalamanın GERÇEK mekanizmasının `--mergen-brand-*` token ailesi olduğunu doğruladı: üç canlı marka yüzeyi (`.brand-text`, `#app-loading-overlay .alo-wordmark`, `.deep-space-branding .deep-space-title`) aynı `var(--mergen-brand-font-stack)` tokenini tüketir. Bilinçli sözleşme güncellemesi yapıldı:
- 10 ölü kural kaldırıldı (`.mergen-brand-title*`, `.mergen-brand-mark`, hayalet `.ds-modal-*` / `.ds-version-modal-*` ailesi, `.deep-space-title-accent`, `.deep-space-version-text`); brand_title.css 314 → 237 satır.
- Test, token tanımları + üç canlı yüzeyin token TÜKETİMİ (≥3 `var(--mergen-brand-font-stack)`) üzerine yeniden çapalandı ve hayalet sınıf ailesinin geri eklenmesini açıkça YASAKLAYAN bir assertion eklendi.
- Hayalet seçici ratchet tabanı 42 → 26'ya İNDİRİLDİ (kalan 26'nın tamamı canlı kuralların grup üyesi kalıntılarıdır; tek başına ölü kural kalmadı).

### hljs doğrulaması (kayıt)
`highlight.min.js` / `hljs` için R çalışma zamanı kaynaklarında (R/, ui.R, server.R, global.R) SIFIR yükleyici referansı doğrulandı: repo içinden bu dosyayı yükleyen hiçbir mekanizma yoktur; `code_highlighting.css` hljs bloğu repo-kanıtıyla ölüdür. Dosya yalnızca on-prem VM kopyasında fiziksel olarak bulunduğu için bloğun kaldırılması VM-doğrulamalı bir oturuma bırakılmıştır (vendor desenleri ratchet'te zaten korumalıdır; acil risk yok).

### Doğrulamalar
- `test-brand-title-single-source-contract.R` → 23 PASS / 0 FAIL.
- Hayalet tarama yeni tabanı: toplam 26 (tema: 7).
- Tam kapı (`ai_validate full --boot-smoke`) bu commit öncesi yeniden koşuldu; sonuç commit mesajında.

## 2026-06-12 — Grup üyesi ölü seçicilerin budanması: hayalet seçici tabanı SIFIR

Canlı kuralların grubunda kalan son 26 ölü seçici (hiçbir zaman eşleşemeyen grup üyeleri) 12 dosyadan budandı (kural gövdeleri bayt-bayt korunur; tamamen ölü kural 0 doğrulandı). `frontend_maintainability_report.R` hayalet taraması artık 0/0 raporlar ve ratchet bütçeleri SIFIRA indirildi (`MERGEN_TEST_MAX_FRONTEND_DEAD_SELECTORS=0`, `MERGEN_TEST_MAX_THEME_DEAD_SELECTORS=0`): bundan sonra eklenen HER hayalet seçici CI'da yakalanır. Odaklı süitler yeşil (ratchet 92, theme-modular 96, brand 23, manifest 224, tool-bg 21); tam kapı sonucu commit mesajında.

## 2026-06-16 — Destek sayfası CSS modülerleştirme ve frontend CSS ratchet sıkılaştırması

### Seçilen paket / zayıflık alanı
Frontend karmaşıklığı paketinde, discovery raporunun en büyük app-owned CSS dosyası olarak işaretlediği `www/css/destek_page.css` hedeflendi. Dosya 1527 satırla 1500+ frontend dosya eşiğini tek başına tüketiyor ve destek yüzeyi için yükleme sırası/zone sahipliği tek büyük dosyaya bağlı kalıyordu.

### Neden bu paket seçildi
Öncelik listesinde R dosyalarında 800+ satır aday kalmadı; en yüksek kaldıraçlı açık risk frontend tarafındaki oversized CSS idi. Destek yüzeyi tek seam (`destek_yonetici_saglik`) altında kaldığı için kontrollü, davranış koruyucu bir paket olarak ayrıştırılabildi.

### Değişen dosyalar
- `www/css/destek_page.css`: ana destek kabuğu, yardım merkezi kartları ve sekme sistemi olarak küçültüldü.
- `www/css/destek_forms.css`: form kartları, memnuniyet/NPS/etiket/metin/konu/kategori/öncelik seçimleri için yeni manifest parçası.
- `www/css/destek_submission.css`: dosya yükleme, onay kutusu, gönderim butonu, hata ve başarı ekranları için yeni manifest parçası.
- `www/css/destek_about_responsive.css`: Hakkında sayfası, ikon animasyonları ve responsive kurallar için yeni manifest parçası.
- `R/config_ui_assets.R`, `R/config_ui_asset_zones.R`, `tests/testthat/test-ui-asset-manifest-contract.R`: yeni CSS parçaları aynı destek sırası ve aynı `geri_bildirim_destek` zone sahipliğiyle kaydedildi.
- `tests/testthat/test-frontend-maintainability-ratchet.R`: frontend CSS satır bütçesi 1600 → 1150, 1500+ satır frontend dosya bütçesi 1 → 0 olarak sıkılaştırıldı.
- `docs/feature-ownership-map.md`, `docs/architecture-map.md`: destek CSS sahipliği ve sıralı manifest sınırı güncellendi.

### Önce / sonra karmaşıklık notları
- Önce: `www/css/destek_page.css` 1527 satırdı ve frontend raporunda en büyük app-owned CSS dosyasıydı; 1500+ satır dosya sayısı 1 idi.
- Sonra: destek CSS parçaları 252 / 574 / 294 / 415 satır; en büyük app-owned CSS artık `theme_light_core.css` (1148 satır). 1500+ satır frontend dosya sayısı 0.
- Seçici gövdeleri davranış koruyucu şekilde taşındı; kaskad sırası orijinal dosya içi sıra ile aynı kalacak biçimde manifestte ardışık listelendi.

### Davranış korundu
Kural içerikleri ve göreli sıraları korunarak yalnızca dosya sınırları değiştirildi. Yeni CSS dosyaları üretim manifestine ve zone haritasına eklendi; manifest dışı runtime varlık oluşturulmadı.

### Testler / doğrulama
- `Rscript tests/scripts/maintainability_report.R` → PASS (R maintainability discovery; 800+ R dosyası yok).
- `Rscript tests/scripts/frontend_complexity_doctor.R` → PASS (başlangıç discovery; destek CSS 1527 satır riskini gösterdi).
- `Rscript tests/scripts/seam_doctor.R` → PASS (başlangıç discovery; yapısal sorun yok).
- `Rscript -e 'testthat::test_file("tests/testthat/test-ui-asset-manifest-contract.R")'` → PASS.
- `Rscript -e 'testthat::test_file("tests/testthat/test-ui-asset-zones-contract.R")'` → PASS.
- `Rscript -e 'testthat::test_file("tests/testthat/test-frontend-maintainability-ratchet.R")'` → PASS.

### Atlanan doğrulamalar ve neden
Bu paket CSS dosya sınırı/manifest sahipliği refactor'ıdır; VM, DB, SSO ve gerçek tarayıcı smoke çalıştırılmadı. Görsel davranış korunumu statik manifest sırası ve dosya içeriği taşıma disiplinine dayanır; canlı tarayıcı görsel kanıtı bu oturumda üretilmedi.

### Kalan riskler / sonraki adaylar
Frontend raporunda en büyük CSS adayları artık açık tema alan dosyaları (`theme_light_core.css` 1148, `theme_light_pages.css` 1136) ve `claude_code.css` (1041). En iyi sonraki paket, tema alanlarından birini semantik alt parçalara ayırmak veya `deep_space_intro.js` / `ai_expert_manager.js` JS büyüklüğünü azaltmaktır.

## 2026-06-26 — AI Uzman frontend handler-density split

### Seçilen paket / neden
Fresh `frontend_complexity_doctor` raporu `www/js/ai_expert_manager.js` dosyasını en büyük ve handler-yoğun app-owned JS adaylarından biri olarak gösterdi (802 satır, 45 fonksiyon, 12 event handler, 8 Shiny handler). Deep Space daha büyük olsa da AI Uzman tarafında Shiny binding katmanı, durum makinesinden güvenli biçimde ayrılabilen net bir seam sundu.

### Değişen dosyalar
- `www/js/ai_expert_manager.js`: altyazı/ses durum makinesi ve `window.AIExpertManager` export'u kaldı; Shiny handler kayıtları çıkarıldı.
- `www/js/ai_expert_handlers.js`: AI Uzman Shiny özel mesaj handler'ları, visualizer visibility helper'ı ve stop-button click binding'i eklendi.
- `R/config_ui_assets.R`, `R/config_ui_asset_zones.R`: yeni JS varlığı manager'dan hemen sonra ve `ses_yasam_dongusu` sahipliğiyle kaydedildi.
- `tests/testthat/test-ui-asset-manifest-contract.R`, `tests/testthat/test-ai-expert-frontend-split-contract.R`: yükleme sırası, sahiplik ve handler delegasyonu sözleşmeleri eklendi/güncellendi.
- `.ai/next-session-eliminate-weaknesses-prompt.md`, `docs/feature-ownership-map.md`, `docs/architecture-map.md`, `docs/technical-reference.md`: handoff ve frontend varlık davranışı notları güncellendi.

### Önce / sonra etki
- `www/js/ai_expert_manager.js`: 802/45/12/8 → 744/35/2/0 (satır/fonksiyon/event/Shiny handler).
- Yeni `www/js/ai_expert_handlers.js`: 75/12/10/8; handler yoğunluğu küçük bağlama dosyasında toplanır, durum makinesi dosyası artık Shiny handler kaydı içermez.
- Asset order kırılmadı: manifestte `js/ai_expert_manager.js` hemen ardından `js/ai_expert_handlers.js` gelir.

### Davranış korundu
Mevcut handler adları (`aiExpertStartWithAudio`, `aiExpertStartSubtitle`, `aiExpertQueueAudioChunk`, `aiExpertPlayAudio`, `aiExpertNoAudioFallback`, `aiExpertStopSubtitle`, `aiExpertVisualizerVisibility`, `aiExpertSetPage`) aynı kaldı ve manager metodlarına delege edilir. TTS/STT/music ducking, altyazı token/time-out davranışı, Türkçe log/metinler ve offline asset varsayımları değiştirilmedi.

### Testler / doğrulama
- `LANG=C.UTF-8 LC_ALL=C.UTF-8 Rscript -e 'testthat::test_file("tests/testthat/test-ai-expert-frontend-split-contract.R")'` → PASS.
- `LANG=C.UTF-8 LC_ALL=C.UTF-8 Rscript tests/scripts/frontend_complexity_doctor.R` → PASS; artifact `artifacts/frontend-complexity-doctor/frontend-complexity-doctor-20260626-155643.json`.
- `bash tools/ai_validate.sh quick` → PASS; failed_steps=0, skipped_steps=0; summary `artifacts/ai-validation/20260626-155649/summary.json`.

### Atlanan / kalan kanıtlar
VM, gerçek tarayıcı, DB, SSO, SQL Server, live endpoint ve soak doğrulaması çalıştırılmadı. Görsel davranış korunumu statik asset sırası ve handler-delegation sözleşmeleriyle doğrulandı.

### Kalan riskler / sonraki adaylar
`www/js/deep_space_intro.js` en büyük app JS olarak kaldı; sonraki yüksek değerli paket Deep Space modülerleştirmesi veya `shiny_message_handlers.js` / `claude_code.js` handler-density azaltımıdır.

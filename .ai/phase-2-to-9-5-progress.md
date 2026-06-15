# Phase 2 → 9.5 Kalite Kampanyası — Ana İlerleme Takipçisi

Bu dosya, MERGEN Bilge'yi 9.5+ kurumsal kalite puanına taşıma kampanyasının
oturumlar arası ana ilerleme kaydıdır. Her oturum sonunda güncellenir.
Tamamlanan işler yeniden yapılmaz; eski sonuç bayatladıysa önce yeniden doğrulanır.

## Faz tanımları

- **Faz 2 — Davranışsal kapsama kampanyası:** kalan yüksek değerli untested
  fonksiyon kümelerini gerçek girdi→çıktı testleriyle kapatmak.
- **Faz 3 — Release kanıtı ve canlı sağlık görünürlüğü:** VM evidence /
  ai-validation / seam-doctor artifact'larını secret-safe okuyan helper katmanı
  ve (sonraki adım) operatör görünürlüğü.
- **Faz 4 — Özellik sahiplik haritaları:** `docs/feature-ownership-map.md`.
- **Faz 5 — Adversarial/güvenlik regresyon kapsaması:** gerçekçi düşman girdiler.

## Önceki oturumlardan devralınan durum (2026-06-12 itibarıyla)

Aşağıdakiler ÖNCEKİ oturumlarda tamamlandı (`.ai/next-session-*.md` ayrıntılı):

- Admin `*_outputs` renderer'larının TAMAMI kapsandı: `test-admin-genel-bakis-outputs-behavior.R`,
  `test-admin-yz-performans-outputs-behavior.R`, `test-admin-geri-bildirim-genel-outputs-behavior.R`,
  `test-admin-sohbet-kalitesi-outputs-behavior.R`, `test-admin-zaman-analizi-outputs-behavior.R`,
  `test-admin-gelismis-analizler-outputs-behavior.R`, `test-admin-users-outputs-behavior.R`.
- Health check probe'ları kapsandı: `test-health-checks-probes-behavior.R`.
- Destek DB helper'ları kapsandı: `test-destek-database-helpers-behavior.R`.
- Görsel galerisi helper'ları kapsandı: `test-image-gallery-helpers-behavior.R`
  (`get_image_thumbnail_base64`, `get_chat_title_for_image`).
- DOCX async clobber FİKSİ + testi, vision pipeline (VM-live doğrulandı),
  admin dokümantasyon görüntüleyici, renv iskeleti: hepsi merged.
- Windows VM evidence gate milestone: 13/13 adım geçti
  (`artifacts/vm-evidence/20260612-211836/evidence.json`).

`.ai/next-session-*.md` dosyalarındaki "do NOT redo" listeleri geçerlidir.

## Oturum kaydı

### Oturum: 2026-06-15 (C) — branch `claude/quirky-tesla-vbv62b` (bu oturum)

Kullanıcının Windows VM testthat suite'indeki 1 hata giderildi ve Faz 2 kalan
14 untested fonksiyon davranışsal kapatıldı (untested 17 → 3). Cerrahi, additive;
ratchet/manifest/seam/encoding sözleşmeleri yeşil. Çalışma zamanı R kodu
DEĞİŞMEDİ (yalnızca 1 test düzeltmesi + 4 yeni test dosyası).

**Windows VM hata düzeltmesi (kullanıcı ekran görüntüsü) — 1 hata / 1 dosya:**
- `test-claude-code-existing-file-link-security-behavior.R:124` —
  `format_claude_code_existing_file_link_html` XSS testi gerçek diskte
  `kotu<b>"x.txt` adlı bir dosya oluşturmaya çalışıyordu. `<`, `>`, `"` Windows
  dosya adlarında GEÇERSİZ olduğundan `writeLines` "cannot open the connection"
  hatası (+ uyarı) veriyor ve `skip_if_not(file.exists(...))` satırına
  ULAŞILAMADAN test patlıyordu (yazar yalnızca Linux'ta doğrulamış). **Düzeltme:**
  XSS sınırı artık iki bölümde sınanır: (1) platformdan bağımsız bölüm — altyazı
  (`display_path`) eleman-metni escape'i gerçek dosya adına ihtiyaç duymaz, her
  platformda çalışır; (2) gerçek dosya adındaki `&quot;` öznitelik escape'i
  yalnızca dosya sisteminin izin verdiği platformlarda (Linux) çalışır, oluşturma
  uyarısı/hatası `tryCatch(warning=, error=)` ile yutulur. Skip YOK, Windows'ta
  hata YOK, XSS kapsaması korunur. Sweep: tüm test dizininde gerçek diskte
  Windows-yasaklı (`< > : " | ? *`) ADla dosya oluşturan TEK test buydu; diğer
  XSS testleri ham string geçiriyor veya güvenli ad (`özet.txt`) kullanıyor.

**Faz 2 — 4 yeni davranış testi (129 doğrulama, 0 fail/warn/skip; untested 17 → 3):**
- `test-settings-yapilandirma-ui-cards-behavior.R` (91) — 11 `.syap_*` kart
  yapıcısı TEK TEK. Mevcut id-surface testi yalnızca BİRLEŞİK
  `settingsYapilandirmaUIImpl` çıktısını donduruyordu (yapıcıları isimle
  çağırmıyordu). Bu test her yapıcıyı ayrı çağırır, kendi ns kimliklerini +
  Türkçe başlığını üretir VE başka kartların temsilci kimliklerini SIZDIRMADIĞINI
  (sahiplik sınırı) kanıtlar. Stub env (api_config/claude_code_config/%||%) +
  `as.character(tag)` HTML doğrulaması.
- `test-llm-worker-call-behavior.R` (14) — `call_llm_worker` ARAÇSIZ yol + hata
  normalizasyon. **GOTCHA:** fonksiyon çok sayıda `llm_worker_*` payload
  yardımcısını enclosing env'de çözer → izole env'e source edip hepsini
  deterministik stub'la (chat_history_to_messages passthrough, add_fallback_chart
  identity, merge_system_messages identity); `extract_llm_content_and_sources`/
  `strip_planner_text` env stub (test başına override). httr namespace
  `local_mocked_bindings(POST/status_code/content, .package="httr")` ile mock
  (POST sentinel döndürür; content `as="parsed"`→liste, `as="text"`→""). Kapanan
  dallar: mutlu yol (içerik+süre+boş chart_store+NULL reasoning), reasoning
  taşıma, EMPTY_RESPONSE, HTTP 429→RATE_LIMIT / 401→AUTH_ERROR / 5xx→SERVER_ERROR
  / 418→API_ERROR, genel hata→UNKNOWN_ERROR, Timeout→TIMEOUT. Hata testlerinde
  error-handler `cat("[ERROR]")` gürültüsü `expect_error(capture.output(...))`
  ile yutulur. İkinci-geçiş/araç-yürütme zinciri (çok ağır) mock dışı bırakıldı.
- `test-send-message-init-guards-behavior.R` (14) — `sendMessageInit` send_message
  erken-dönüş korumaları. **KEŞİF:** fabrika gözlemci KAYDETMEZ, yalnızca
  `list(send_message=send_message)` döndürür → testServer GEREKMEZ, doğrudan
  çağrılır. Kapanan korumalar: SSO açık+kimlik doğrulanmamış → kullanıcı-id
  ÇÖZÜLMEDEN reddedilir (resolve stub `stop()` ile kanıtlanır — kimlik sınırı
  user-id'den önce gelir); etkin kullanıcı-id<=0 (NA→0 dönüşümü dahil);
  çift-gönderim (`values$is_sending=TRUE`); boş mesaj+yükleme yok (snapshot stub).
  **GOTCHA:** `SSO_ENABLED`/`showToast`/`resolve_effective_user_id`/
  `mergen_clear_welcome_for_send_message`/`mergen_build_send_message_prompt_snapshot`
  izole env'e konur → batch globalenv'i gölgelenir (deterministik); 24 argüman
  NULL/stub geçilir (tembel değerlendirme, fabrika çağrısında zorlanmaz);
  `values` env (in-place `$<-`); toast'lar recorder env'de toplanır.
- `test-character-video-debug-behavior.R` (10) — `.character_video_debug`:
  log_debug varsa msg+... iletir, yoksa sessiz no-op + invisible(NULL).
  **GOTCHA:** `exists("log_debug",inherits=TRUE)` deterministik olsun diye modül
  `new.env(parent=baseenv())`'e source edilir (zincirde globalenv YOK → batch'te
  globalenv'deki log_debug sızmaz). `withVisible` ile görünmezlik kanıtlanır.

**Kalan 3 untested — BİLİNÇLİ atlandı (sözleşme dışı):**
`.helpers_llm_sse_source_sibling` (helpers_llm_sse.R), `.mcp_bootstrap_assign_global_function`,
`.mcp_bootstrap_require_tool_functions` (helpers_mcp_bootstrap.R) — ÜÇÜ DE
tanımlandıktan sonra runtime'da `rm()` ile SİLİNİR (kalıcı çalışma-zamanı
fonksiyonu değil). Kampanya kuralı: runtime'da kaldırılan bootstrap yardımcıları
gerçek bir sözleşme korumadıkça test etme. Bunlar fallback source köprüleridir,
gerçek davranış sözleşmesi taşımazlar → atlandı.

**Doğrulama (bu container, R 4.6.0 — Linux/cloud):**
- `bash tools/ai_validate.sh quick` → **TAM GEÇTİ** (failed_steps=0,
  skipped_steps=0, app_source_smoke=passed, focused contract tests OK)
  (`artifacts/ai-validation/20260615-100023/summary.json`;
  validation_execution_status=ran_by_ai_repo_check, shiny_boot_smoke=not_requested,
  browser_smoke=not_requested, db_sso_vm=false, sql_server Türkçe encoding=
  not_performed_by_ai_validate).
- `parse_sanity_check.R` OK (800 dosya). `maintainability-ratchet` 174 PASS
  (skor değişmedi; max 24 fn, max 777 satır — değişiklikler test-only).
- 4 yeni test tek tek + `test_dir` batch: **129 doğrulama, 0 fail/warn/skip.**
- XSS test düzeltmesi: Linux'ta 16 PASS (her iki dal koşar); Windows'ta öznitelik
  dalı sessizce atlanır, platformdan bağımsız dal yine koşar.

**KANITLANMAYAN / cloud sınırı:** Windows VM/SSO/DB/SQL Server Türkçe encoding/
gerçek browser UX/vision live bu oturumda KANITLANMADI. XSS test düzeltmesi yapı
gereği Windows-taşınabilir ama gerçek VM doğrulaması kullanıcının suite'inde
yapılmalı. `full --boot-smoke` bu oturumda koşulmadı (yalnızca test-only
değişiklik; `quick` yeterli kanıt sınırı).

**Devam (aynı oturum, "continue") — call_llm_worker araç-yolu derin dal kapsaması
(10 doğrulama):**
- `test-llm-worker-tool-path-behavior.R` (10) — `call_llm_worker` MCP araç yolu
  (`enable_tools=TRUE`, `tool_family="mcp_excel"`) orkestrasyon sözleşmesi. Araçsız
  yol + hata normalizasyonu zaten kapsanmıştı; bu test araç-yürütme + ikinci-geçiş
  dallarını kilitler: araç `$error` → "Araç hatası:" ERKEN dönüş (ikinci geçişe
  gitmez — stub `stop()` ile kanıtlı); `strict_data_only=TRUE` → yalnızca GERÇEK
  VERİ metni (ikinci geçiş atlanır); araç çağrısı yok → `mcp_excel_tool_fallback`
  + "Kaynakça:"; ikinci geçiş `ok=FALSE` → helper response aynen; `ok=TRUE`+içerik
  → ai2 + reasoning_content; `ok=TRUE`+boş ai2 → `format_answer_from_tool_results`
  yedeği. **GOTCHA:** httr mock `content` `as="parsed"` için test-başına değişen
  `.clwt_env$.resp` döndürür (yapısal tool_calls vs düz yanıt); `helpers_mcp_tools`
  liste-stub (yaprak fonksiyonlar test-başına override); ikinci-geçiş/biçimleme
  yardımcıları (`llm_worker_run_mcp_second_pass`/`_format_tool_results_for_prompt`/
  `format_answer_from_tool_results`/`mcp_excel_tool_fallback`) env stub; erken-dönüş
  kanıtı için ikinci-geçiş stub'ı `stop()`. Doğrulama: tek tek 10 + iki llm-worker
  dosyası batch 24 doğrulama 0 fail/warn/skip; `ai_validate quick` TAM (failed=0,
  skipped=0); parse_sanity 801 dosya OK. Kalan en derin dal: ikinci-geçiş
  helper'ının KENDİ iç SSE/non-stream akışı (ayrı, daha ağır hedef).

**Devam-2 (aynı oturum, "continue") — ikinci-geçiş iç akış dalları (18 doğrulama):**
- `test-llm-worker-second-pass-flow-behavior.R` (18) — `helpers_llm_worker_second_pass.R`
  mevcut testlerinin (contract + pure-behavior) kapsamadığı GERÇEK akış dallarını
  doldurur. KEŞİF: sözleşme testi `llm_worker_call_second_pass_non_streaming`'i HEP
  stub'lıyordu (gerçek httr davranışı hiç test edilmemişti) ve YALNIZCA SSE-açık
  yolu kapsıyordu; üretimdeki yaygın NON-SSE yolu hiç sınanmamıştı. Kapanan dallar:
  (1) `llm_worker_call_second_pass_non_streaming` gerçek httr — 200→success+içerik/
  reasoning+error_body="" / 200-dışı(500)→success=FALSE+status+error_body; (2)
  `llm_worker_run_mcp_second_pass` NON-SSE — non-stream başarı→ok=TRUE/ai2/reasoning2,
  non-stream hata→ok=FALSE/`format_answer_from_tool_results` yedeği; (3) SSE başarısız
  + non-stream retry de başarısız → ok=FALSE/yedek, `reasoning_content` SSE canlı
  düşünce metninden taşınır. **GOTCHA:** izole `.sp_env`'e source + stub'lar; gerçek
  non-streaming yardımcısı source SONRASI saklanır (A testleri gerçeği sınar, B/C
  `on.exit` ile override/restore eder); httr namespace `local_mocked_bindings`;
  `call_local_llm_sse_worker` yalnızca C'de tanımlanıp `rm` ile temizlenir.
  Doğrulama: tek tek 18 + beş worker/second-pass dosyası batch 83 doğrulama
  0 fail/warn/skip; `ai_validate quick` TAM (failed=0, skipped=0); parse_sanity
  802 dosya OK. İkinci-geçiş orkestrasyonu artık SSE + NON-SSE + retry-fallback
  dallarıyla tam davranışsal kapsanıyor.

### Oturum: 2026-06-15 — branch `claude/zen-gauss-w423sz` (bu oturum)

Faz 2 kalan AĞIR runtime closure'larından üçü davranışsal kapatıldı, Faz 5
adversarial bir güvenlik boşluğu kapatılıp 1 cerrahi sertleştirme yapıldı ve
kullanıcının Windows VM testthat suite'inde gördüğü 4 hata (3 dosya) giderildi.
Cerrahi, additive; ratchet/manifest/seam/encoding sözleşmeleri yeşil.

**Faz 2 — 3 yeni davranış testi (94 doğrulamanın 81'i; untested 20 → 17):**
- `test-server-init-chat-runtime-behavior.R` (41) — `serverInitChatRuntime`
  fabrikası: dört kapanış (`reset_chat_state`/`add_message`/
  `generate_title_from_prompt`/`simulate_streaming_stoppable`) doğru temsilciye
  yönlendirir; **`add_message` kullanıcı kimliğini ÇAĞRI ANINDA canlı
  sağlayıcıdan çözer (SSO anlık görüntü değil)** — sağlayıcının dönüşü çağrılar
  arası değiştirilerek kanıtlandı; tüm argümanlar + stop_generation iletilir.
  Temsilciler source SONRASI stub'lanır.
- `test-chat-simulate-streaming-behavior.R` (19) — `chat_simulate_streaming`
  KARAR/ERKEN-ÇIKIŞ dalları: TTS yok→hemen başlat, boş yanıt→TTS beklenmez,
  TTS promise başarılı/reddedilen/`success=FALSE`→akış yine başlatma yoluna
  girer. **Tüm testler `stop_generation=function() TRUE` kullanır** → kırılgan
  `shiny::observe`/`invalidateLater(25)` döngüsüne GİRİLMEZ; tamamen senkron.
  GOTCHA: dosyada tanımlı `chat_reset_state`/`push_followup_update`/
  `chat_store_message_in_saved_chats` source SONRASI stub'lanmalı (source onları
  ezer); promise cat çıktısı `.css_drain()` ile capture.output İÇİNDE çalışır.
- `test-claude-code-stream-poll-binding-behavior.R` (21) —
  `cc_bind_claude_code_stream_polling` testServer: **stop gözlemcisi
  request-id kapsamlı "Durduruldu" finalize + süreç kill + env$durduruldu +
  cc-stream-end** (korumalı sözleşme); çalışmıyorken no-op; klavye gözlemcisi
  run_command tıklar/tıklamaz; poll gözlemcisi `durduruldu` + zaman aşımı erken
  dalları (request-id kapsamlı finalize + cc-add-message). `invalidateLater(200)`
  ilerletilmez; her dal tek flush. GOTCHA: bağlayıcı moduleServer değil → küçük
  modül sarmalayıcı rv döndürür; `session$returned$is_running <- TRUE` +
  `session$flushReact()` ile poll dalları tetiklenir; `shinyjs::click`
  `local_mocked_bindings(.package="shinyjs")`; processx fake env.

**Faz 5 — adversarial güvenlik + 1 cerrahi sertleştirme:**
- `test-claude-code-existing-file-link-security-behavior.R` (13) —
  `format_claude_code_existing_file_link_html`: **izinli kök DIŞINDAKİ var olan
  dosya → boş bağlantı (gerçek traversal/kaçış savunması)**. KEŞİF: mevcut
  encoding testi `cc_policy_path_inside_roots`'u YÜKLEMEDİĞİ için bu dal
  (helpers_claude_code_existing_file_link.R:48-56) davranışsal olarak hiç
  sınanmamıştı → yeni test gerçek `helpers_claude_code_path_policy.R` yükler.
  Ayrıca kök-içi→kart, kök-yok→boş, var-olmayan/dizin/boş/NA→boş, ve
  HTML-metakarakterli dosya adı → htmlEscape.
- Cerrahi sertleştirme: `R/helpers_claude_code_existing_file_link.R` öznitelik
  bağlamındaki `href`/`download`/`title` değerleri artık
  `htmlEscape(..., attribute = TRUE)` ile escape edilir; dosya adındaki çift/tek
  tırnak öznitelikten kaçamaz (öznitelik enjeksiyonu savunması). XSS testi
  fail-before/pass-after kanıtlı. Eleman metni (span) varsayılan escape'te kalır.
  CLAUDE.md HTML güvenlik sınırı (1C) ile uyumlu.

**Windows VM testthat hataları (kullanıcı ekran görüntüsü) — 4 hata / 3 dosya giderildi:**
- `test-file-click-observers-behavior.R:119,134` (2 hata) — `analysis_file_clicked`
  www-önekli + göreli yol testleri `beklenen <- file.path(getwd(), ...)` + `%in%`
  kullanıyordu. Üretim kodu repo kökünü `normalizePath(getwd(), winslash="/")` ile
  çözüyor; Windows UNC'de `normalizePath` `\\sunucu/...`, ham `getwd()` ise
  `//sunucu/...` veriyor → önek uyuşmazlığı. **Düzeltme (test):** mutlak önekten
  bağımsız `any(endsWith(exists_paths, "www/img/x.png"))` suffix doğrulaması.
  Mutlak-yol testi (satır 126) zaten geçiyordu (kimlik stub) — analiz doğrulandı.
- `test-pk-analiz-process-request-behavior.R:155` (1 hata) — yasaklı SQL reddi
  testi `grepl("Guvenlik ihlali", res)` arıyordu. **Kök neden (üretim):**
  `module_proje_kaynak_analizi.R:223` güvenlik kapısı `toupper(enc2utf8(final_sql))`
  + locale-duyarlı `grepl` kullanıyordu; `final_sql` UTF-8 işaretli olduğundan
  Windows Türkçe (UTF-8 olmayan) yerel ayarda bu kombinasyon HATA veriyor →
  tryCatch yakalıyor → res "Veritabanı Hatası" içeriyor ama "Guvenlik ihlali"
  içermiyor (satır 154 geçer, 155 başarısız). Karşılaştırma: `helpers_deep_analysis.R:289`
  AYNI kapıyı `enc2utf8` OLMADAN kullanır → VM'de geçer (bu da `enc2utf8`+`toupper`
  kombinasyonunu suçlu olarak teyit eder). **Düzeltme (üretim):** `toupper`
  kaldırıldı; tarama `grepl(..., final_sql, ignore.case=TRUE, perl=TRUE,
  useBytes=TRUE)` ile yerelden bağımsız yapıldı (ASCII anahtar kelimeler; kapı
  her yerel ayarda güvenilir tetiklenir, false-positive yok, uyarı yok).
  `helpers_deep_analysis.R` dokunulmadı (testi VM'de geçtiği için — cerrahi).
- `test-release-evidence-behavior.R:334` (1 hata) — `release_evidence_artifact_root("/repo/kok")`
  testi `/repo/kok/artifacts` bekliyordu ama VM'de `\\rehisds/uygulamalar/repo/kok/artifacts`
  döndü. **Kök neden:** "/repo/kok" Windows'ta MUTLAK değil (sürücü/UNC yok) →
  `release_evidence_resolve_repo_root` içindeki `normalizePath(..., mustWork=FALSE)`
  onu UNC cwd'ye göre çözüyor. Üretim DOĞRU; test fixture'ı Linux'a özgüydü.
  **Düzeltme (test):** `withr::local_tempdir()` (OS-bağımsız gerçek mutlak yol) +
  beklenen değer üretim ile aynı normalize biçiminde + `basename(...)=="artifacts"`.

**Doğrulama (bu container, R 4.6.0 — Linux/cloud):**
- `bash tools/ai_validate.sh quick` → **TAM GEÇTİ** (failed=0, skipped=0,
  app_source_smoke=passed) (`artifacts/ai-validation/20260615-074956/summary.json`).
- `bash tools/ai_validate.sh full --boot-smoke` → **TAM GEÇTİ** (failed=0,
  skipped=0; **full testthat suite passed 162.7s**, shiny_boot_smoke=passed,
  app_source_smoke=passed; browser_smoke=**skipped** (browser binary yok — kanıt
  değil); db_sso_vm=false; sql_server Türkçe encoding=not_performed)
  (`artifacts/ai-validation/20260615-075105/summary.json`). **Önceki oturumlarda
  full suite'te tek başarısız olan `test-file-click-observers-behavior.R` artık
  Linux full suite'te de GEÇİYOR** (suffix düzeltmesi sayesinde).
- `parse_sanity_check.R` OK (794 dosya). `maintainability-ratchet` 174 PASS
  (skor 100/100, max 24 fn; +6/+8 satırlık üretim değişiklikleri bütçe içinde).
  `seam_doctor.R` OK (yapısal sorun yok). pk/release/deep-analysis/security
  contract testleri 0 fail/warn.
- 4 yeni test tek tek + `test_dir` batch: **94 doğrulama, 0 fail/warn/skip.**
  Güvenlik sertleştirmesi fail-before/pass-after kanıtlı.

**KANITLANMAYAN / cloud sınırı:** Windows VM/SSO/DB/SQL Server Türkçe encoding/
gerçek browser UX/vision live bu oturumda KANITLANMADI. VM hata düzeltmeleri
yapı gereği Windows-taşınabilir; gerçek VM doğrulaması kullanıcının suite'inde
yapılmalı. Bir önceki oturumun "VM'de geçiyor" iddiası `test-file-click-observers`
için BAYATTI (kullanıcı VM'de fail gösterdi) — bu oturumda gerçekten düzeltildi.

**Devam (aynı oturum, "add more test") — 2 yeni Faz 5 güvenlik testi + 1 cerrahi
sertleştirme (35 doğrulama):**
- `test-claude-code-downloads-security-behavior.R` (18) — Bilge Yolaç üretilen-dosya
  indirme GÜVENLİK sınırı (yalnızca statik referanslıydı, davranışsal değil):
  `resolve_claude_code_generated_path` (izinli kök içi→normalize / **kök DIŞI
  var-olan dosya→"" = traversal savunması** / göreli→workdir altında / boş→""),
  `list_claude_code_generated_file_paths` (yalnızca write/edit araçları;
  read/bash yok sayılır; **kök-dışı yazma yolu düşürülür**; dedup; boş→character(0)),
  `stage_claude_code_downloads` (kök-içi dosya geçici indirme köküne kopyalanır;
  **kök-dışı düşürülür**; boş→list()). GOTCHA: `resolve_*` var-olmayan yolda
  1.5sn `Sys.sleep` bekleme döngüsüne girer → testler var-olan dosya + mutlak yol
  + `withr::local_dir(wd)` kullanır (bekleme yok); indirme kökü
  `withr::local_options(mergen.claude_code_download_root=tempdir)` ile yönlendirilir
  (repo kirliliği yok).
- `test-claude-code-downloads-html-behavior.R` (17) —
  `format_claude_code_generated_downloads_html` (yalnızca policy-split contract'ında
  statik referanslıydı): boş/NULL→"", geçerli/çoklu kayıt→kart, **HTML
  metakarakterli url/dosya adı/yol → htmlEscape (XSS/öznitelik enjeksiyonu sınırı)**.
- Cerrahi sertleştirme: `R/helpers_claude_code_downloads_html.R` da (existing-file-link
  ile AYNI açık) `href`/`download`/`title` öznitelikleri artık
  `htmlEscape(..., attribute=TRUE)` → tırnak öznitelikten kaçamaz. Fail-before/
  pass-after kanıtlı. Ratchet güvenli (yorum +4 satır, bütçe içinde; 174 PASS).
- Doğrulama: 6 yeni test dosyası `test_dir` batch **129 doğrulama, 0 fail/warn/skip**;
  policy-split (47)/downloads-helpers (25)/stream-html-safety (6)/ratchet (174)
  contract'ları 0 fail; parse_sanity 796 dosya OK; encoding 0 mojibake; stray
  indirme artifact'ı YOK (options override).

### Oturum: 2026-06-14 — branch `claude/affectionate-faraday-yksxki` (bu oturum)

Faz 2 davranışsal kapsama görev önceliği sırasıyla derinleştirildi (dosya yaşam
döngüsü → derin/proje analizi → Bilge Yolaç streaming → doküman orkestrasyonu) ve
Faz 3 operatör görünürlüğü genişletildi (secret-safe AI çağrı istek-süresi/latency
özeti). Cerrahi, additive; ratchet/manifest/seam/encoding sözleşmeleri yeşil.

**Faz 2 — 5 yeni davranış testi (185 doğrulamanın 153'ü; 8 untested fn kapandı):**
- `test-file-pipeline-upload-batch-behavior.R` (42) — `handle_file_upload_batch`:
  NULL/boş df/okunamayan girdi, **desteklenmeyen uzantı reddi + HİÇBİR kalıcı yan
  etki yok (gizli kaydedilmiş-ama-geçersiz yükleme yok = Faz 5)**, geçerli dosya
  kopyala+indeksle+özetle, büyük-harf uzantı, karışık toplu yükleme, kopyalama
  hatası temizliği (oturumda tut + uyar), liste-biçimli tek yükleme. GOTCHA:
  `shinyjs::delay` `local_mocked_bindings(.package="shinyjs")` ile `force(expr)`
  yapan stub → senkron özyineleme; copy_to_mcp_base/global_register_file/
  processAndSummarizeFile/showToast/showNotification env'e kaydedici stub.
- `test-deep-analysis-process-behavior.R` (16) — `pk_deep_analysis_process`
  orkestrasyon: başlangıç/RLS-sonrası durdurma, yetki reddi, çoklu→tekil fallback,
  boş-sonuç, sorgu-hatası→başarısız sonuç bağlama taşınır. get_connection/
  get_user_rls_info/find_multiple_queries_with_ai/select_smart_query/
  execute_single_deep_query/build_deep_analysis_context env stub.
- `test-pk-analiz-process-request-behavior.R` (28) — `pk_analiz_process_request`
  erken-dönüş + **YASAKLI SQL reddi (DELETE/DROP/TRUNCATE/ALTER → gerçek exec
  ÇALIŞMAZ = Faz 5)**, SSO kimliği hazır değilse DB'ye GİTMEDEN döner (kimlik
  sınırı), yapılandırma hataları (boş SQL/eksik dosya/yol algılama/geçersiz SQL);
  ayrıca `find_best_query_with_ai` (LLM JSON match_id→sorgu, null/aralık-dışı/
  ```json çiti/geçersiz JSON→NULL). GOTCHA: modül kaynak-zamanı `pk_required_helpers`
  guard döngüsü; 12 yardımcı adı env'e ÖNCEDEN stub konarak `exists(inherits=TRUE)`
  tatmin edilir → guard dosya kaynaklamayı atlar (globalenv kirliliği yok).
- `test-claude-code-run-streaming-behavior.R` (24) — `run_claude_code_streaming`
  processx-mock: boş komut, CLI yok, workdir/prompt politika reddi, normal akış
  başarısı, çıkış kodu, zaman aşımı (süreç öldürülür), süreç başlatma hatası,
  on_chunk her satır. GOTCHA: `processx::process` R6 üreticisi
  `local_mocked_bindings(process=list(new=function(...) fake), .package="processx")`;
  fake_proc is_alive sayaçlı (N kez TRUE sonra FALSE), poll_io/read_output_lines/
  read_all_output/read_all_error/get_exit_status/kill. timeout_sec=-1 ile zaman
  aşımı deterministik.
- `test-claude-code-document-orchestration-behavior.R` (43) —
  `prepare_claude_code_document_context` (okuma niyeti yok/oluşturma niyeti/doküman
  yok/liste boş/tam çıkarım+manifest+prompt/desteklenmeyen uzantı/boş metin),
  `write_claude_code_document_summary_file` (boş dizin-metin/geçerli BOM yaz/yazıcı
  FALSE), `summarize_claude_code_documents_with_local_llm` (hazır-değil/başarı+dosya+
  file_write tool_use/çıktı dizini yok/boş LLM/LLM hata). GOTCHA: kaynak-zamanı
  extractor-guard'ı (extract_supported_document_text_for_claude +
  get_office_document_reader_template_path) env'e ÖNCEDEN stub → guard atlanır;
  gerçek PDF/Excel/DOCX fixture YOK (çıkarıcı stub).

**Faz 3 — secret-safe AI çağrı istek-süresi (latency) özeti (log formatı doğrulandı):**
- Log formatı KANITLANDI: `log_ai_call()` →
  `"AI Call: user=..., model=..., duration=<sn>s, success=<TRUE/FALSE>, tokens=..."`.
  Güvenilir sayısal süre verisi mevcut → latency özeti eklendi (uydurma format yok).
- `R/helpers_release_evidence.R`: YENİ saf `release_evidence_summarize_ai_call_latency()`
  — `duration=<sayı>s` kalıbından YALNIZCA sayısal süre + başarı/başarısızlık sayar;
  kullanıcı/model içeriği ASLA taşınmaz. count/min/median/mean/max/success/fail döner;
  eşleşme yoksa boş liste. `release_evidence_log_health()` çıktısına additive
  `ai_call_latency` alanı (AI Call satırları `grepl("AI Call:", fixed=TRUE)` ile süzülür).
- `R/module_health_release.R`: YENİ `.health_release_ai_latency()` — "Günlük Log
  Sağlığı" kartına latency satırları (alan boşsa NULL → eski UI değişmez, regresyon yok).
- Kanıt: `test-release-evidence-ai-latency-behavior.R` (32; saf özet/yuvarlama/
  süre-içermeyen-satır yok sayma + **secret-safety: kullanıcı/model taşınmaz** +
  log_health entegrasyonu + UI yüzeyi + eski-davranış regresyon yok).
- Ratchet güvenli: `helpers_release_evidence.R` 20→21 fn, `module_health_release.R`
  4→5 fn (rapor `(<-|=)\s*function\s*\(` sayar; anonim handler sayılmaz). Global cap
  24 (helpers_ai_expert/helpers_file_manager_runtime/helpers_health_formatters); dokunulmadı.

**Doğrulama (bu container, R 4.6.0 — Linux/cloud):**
- `bash tools/ai_validate.sh quick` → **TAM GEÇTİ** (failed_steps=0, skipped_steps=0,
  app_source_smoke=passed, focused contract tests OK) — hem behavioral commit hem
  latency commit sonrası (`artifacts/ai-validation/20260614-073737/summary.json`).
- `parse_sanity_check.R` OK (783 dosya). `maintainability-ratchet` 174 PASS / 0 fail
  (max 24 fn korunur); `release-evidence-behavior` 98, `release-evidence-error-contexts`
  37, `health-release-ui` 56, `e2e-health-dashboard` 45 — hepsi 0 fail/warn.
- 6 yeni test dosyası tek tek + `test_dir` batch: **185 doğrulama, 0 fail/warn/skip**.
- Untested top-level fn taraması: **36 → 28** (handle_file_upload_batch,
  pk_deep_analysis_process, pk_analiz_process_request, find_best_query_with_ai,
  run_claude_code_streaming, prepare_claude_code_document_context,
  write_claude_code_document_summary_file,
  summarize_claude_code_documents_with_local_llm kapandı; 2 yeni latency fn de kapsamlı).

**KANITLANMAYAN / cloud sınırı + ÖNEMLİ NOT:**
- `bash tools/ai_validate.sh full --boot-smoke` → full testthat suite 1 başarısız
  adım: SADECE `test-file-click-observers-behavior.R` (satır 119/134). Bu test
  benim DEĞİL (PR #464'te commit edildi), benim 5 dosyam YÜKLENMEDEN tek başına
  da başarısız (`file.path(getwd(), "www/...")` üyelik + MockShinySession
  prime-then-set coalescing → çalışma-dizini/sürüm duyarlı). **Kullanıcı onayı:
  GitHub testthat suite uygulamayı çalıştıran Windows VM'de GEÇİYOR.** Bu yüzden
  Linux/cloud-only artifact; gerçek regresyon değil. Benim 6 dosyam tam suite
  içinde de geçti.
- Windows VM/SSO/DB/SQL Server Türkçe encoding/gerçek browser UX/vision live
  bu oturumda KANITLANMADI. Latency/log özetleri yalnızca VM'de gerçek
  `logs/mergen_*.log` ile canlı doğrulanır.

**Devam (aynı oturum, "continue") — 4 yeni test, 5 untested fn daha kapandı (27 doğrulama):**
- `test-claude-code-refresh-fm-after-run-behavior.R` (8) —
  `cc_refresh_user_file_manager_after_run`: oturum/userData/file_manager_data/
  refresh-fonksiyon guard'ları → FALSE; refresh varsa `"bilge_yolac_generated"`
  tetikleyici + hata yutma → TRUE.
- `test-admin-ha-show-modal-behavior.R` (6) — `admin_ha_show_modal`: `shinyjs::runjs`
  `local_mocked_bindings(.package="shinyjs")` ile yakalanır; ns'lenmiş `#id` +
  `appendTo('body')` + `moved-to-body` + `modal('show')` doğrulanır.
- `test-config-packages-attach-behavior.R` (7) — `attach_required_packages`:
  `library` env'e kaydedici stub; kaynak-zamanı validate+stop+attach
  `tryCatch(source)` ile yutulur (fn tanımı stop'tan önce → env'de kalır);
  her paket `character.only=TRUE` + sıra + varsayılan manifest.
- `test-gc-scheduler-behavior.R` (6) — `gc_scheduler` (gc çalıştır + later 300sn;
  gc hata → later 600sn) ve `start_gc_scheduler_once` (ilk TRUE+bayrak yaz, ikinci
  FALSE). GOTCHA: `later::later` `local_mocked_bindings(.package="later")` ile
  yakalanır (gerçek callback zamanlanmaz); `gc` env stub; `.mergen_gc_scheduler_started`
  `.GlobalEnv` bayrağı `withr::defer` ile save/restore (batch kirliliği yok).
- Doğrulama: 4 dosya tek tek + `test_dir` batch 27 doğrulama 0 fail/warn/skip;
  `ai_validate quick` TAM geçti (failed=0, skipped=0). Untested **28 → 23**.
  config_file_store.R testthat bağlamında temiz source olur (gc fn'leri tanımlı).

**Devam-2 (aynı oturum, "cover the next targets") — 3 yeni test, 3 untested fn daha (36 doğrulama):**
- `test-session-cache-init-behavior.R` (22) — `sessionCacheInit`: döndürülen API
  (`cache_session_token` boş→sess_/güvensiz karakter sanitize, `setup_user_session`
  kullanıcıya özel dizin + `onSessionEnded` kaydı, `cache_mcp_file_locally` geçici
  dosyayı kopyala / boş-var olmayan→NULL, `update_mcp_registry_snapshot` snapshot
  helper'ına devir, `get_cache_dir`, başlangıç snapshot kurulumu). Sahte oturum
  (env) + yol/MCP bağımlılıkları env stub; gerçek geçici dosya sistemi.
- `test-config-logging-console-appender-behavior.R` (6) — `mergen_console_appender`:
  tek/çok satır cat, NULL güvenli, `normalize_text_for_log` mevcutsa kullanma
  (önekli stub), Linux UTF-8'de Türkçe koruma. GOTCHA: config_logging.R kaynak-zamanı
  logger global durumunu değiştirir → geçici MERGEN_LOG_DIR + `log_threshold`/
  `log_appender(index=1/2)`/`log_layout` save/restore (test-config-logging-sinks
  ile aynı korumalı desen); index 2 appender susturulur.
- `test-mcp-prepare-chart-data-behavior.R` (8) — `helpers_mcp_tools$prepare_chart_data`
  (kaynak-zamanı `.mcp_prepare_chart_data_fn` olarak tanımlanıp atanır ve rm edilir;
  runtime'da YALNIZCA `helpers_mcp_tools$prepare_chart_data` üzerinden erişilir).
  Erken-dönüş dalları: resolve_file_argument$ok=FALSE → list(error,ok=FALSE);
  safe_read_table_generic hata → "Dosya okunamadı"; auto_file_name/normalize_chart_type
  argüman normalizasyonu. MCP zinciri globalenv'e tekil yüklenir; yaprak araçlar
  test başına override + `withr::defer` ile geri yüklenir (batch kirliliği yok).
- Doğrulama: 3 dosya tek tek + `test_dir` batch 36 doğrulama 0 fail/warn/skip;
  `ai_validate quick` TAM geçti (failed=0, skipped=0). Untested **23 → 20**.

### Oturum: 2026-06-13 (B) — branch `claude/serene-bell-3l1xw6` (bu oturum)

Faz 2 davranışsal kapsama derinleştirildi (servis-bağlı runtime mantığı) ve Faz 3
operatör görünürlüğü genişletildi (secret-safe hata kategorisi özeti). Cerrahi,
additive; ratchet/manifest/seam/encoding sözleşmeleri yeşil.

**Ek (kullanıcı "add a small batch"): admin UI builder testi (untested 37 → 34):**
- `test-admin-ui-builders-behavior.R` — `adminYanitAnaliziUI` (4 sekme value/Türkçe
  başlık/ns), `admin_doc_group_tab_panels` (her kayıt grubu için bir sekme),
  `adminDokumantasyonUI` (Dokümantasyon sayfası). Gerçek `admin_page_layout`
  (helpers_admin_analytics.R; `htmlwidgets::JS` source-time gerektirir → `library(htmlwidgets)`).
  170 doğrulama batch'te 0 fail/warn/skip.
- NOT: `.mcp_bootstrap_assign_global_function`/`_require_tool_functions` BİLİNÇLİ
  geçici (bootstrap sonunda `rm()` edilir, runtime'da yok) — birim testi düşük
  değerli/kırılgan; atlandı.

**Faz 2 — 5 yeni davranış testi (servis-bağlı, daha derin runtime):**
- `test-file-pipeline-summarize-behavior.R` — `summarize_file_with_llm`
  (list($content)/karakter çıkarımı, boş/NA fallback, LLM hata fallback'i,
  60000 karakter kısaltma, sistem talimatı "ÇIKARTMAK" + kullanıcı mesajına
  dosya adı/içerik). `call_llm_with_retry` env'e stub.
- `test-deep-analysis-execute-query-behavior.R` — `execute_single_deep_query`
  erken-dönüş + GÜVENLİK dalları: durdurma talebi→NULL, bağlantı yok, boş SQL,
  **tehlikeli SQL (DROP/DELETE/TRUNCATE/ALTER + noktalı virgül zinciri) reddi**,
  boş sonuç, RLS sonrası boş veri (yetki hatası) ve başarılı orkestrasyon.
  `get_connection`/`release_connection` env'e, `DBI::dbGetQuery` mock'a. Hem
  Faz 2 (davranış) hem Faz 5 (SQL injection reddi) kapsar.
- `test-deep-analysis-multi-query-behavior.R` — `find_multiple_queries_with_ai`
  LLM JSON eşleşme→kütüphane sorgusu eşleme: NULL/boş matches→NULL, tekrarlı
  match_id eleme, güven<30 atma, azalan sıralama, max_queries kapağı, aralık-dışı
  id yok sayma, ```json çiti temizleme, geçersiz JSON→NULL, list($content).
  `call_local_llm`/`resolve_local_llm_credentials` env'e stub; `mergen.filter_model`
  option set (api_config'e dokunulmaz; R.utils::withTimeout gerçek koşar).
- `test-mcp-execute-parsed-tool-behavior.R` — `helpers_mcp_tools$execute_parsed_tool`
  yönlendirici: boş/bilinmeyen araç reddi, 8 araca yönlendirme + argüman alias
  çözümü (x/xlabel/x_col, get_column_stats→get_column_statistics), limit/analysis_type
  varsayılanları, büyük/küçük harf duyarsızlığı. MCP zinciri globalenv'e yüklenir;
  yaprak araçlar test başına `withr::defer(envir=parent.frame())` ile geri yüklenir
  (batch kirliliği yok — mcp-tools-parse + mcp-excel-resolve ile birlikte yeşil).
- `test-server-core-runtime-guards-behavior.R` — wiring-guard testinde İSİMLE
  çağrılmayan saf guard'lar: `.server_runtime_stop`, `.server_core_interaction_stop`/
  `_require_context`/`_require_values`/`_require_functions`/`_resolve_bundle`
  (NULL→inşa, geçerli→döndür, geçersiz→stop), `.server_core_observer_require_functions`,
  `.server_core_observer_call_with_optional_boot_ready` (4 dal: explicit param/`...`/
  NULL boot_ready/kabul etmeyen fn'e enjekte edilmez).

**Faz 3 — release kanıt görünürlüğü: secret-safe hata kategorisi özeti:**
- `R/helpers_release_evidence.R`: YENİ saf `release_evidence_summarize_error_contexts()`.
  ERROR satırlarındaki `Error in <bağlam>:` (log_error_with_context çıktısı; bağlam
  ve mesaj zaten redakte yazılır) kalıbından YALNIZCA bağlam etiketini sayar; mesaj
  içeriği taşınmaz. Savunma derinliği: güvenli karakter sınıfı + 60 karakter sınırı;
  eşleşmeyen ERROR satırları "diğer" kovasına; top_n azalan. `release_evidence_log_health()`
  çıktısına additive `error_contexts` alanı eklendi (mevcut alan adları korunur).
- `R/module_health_release.R`: YENİ `.health_release_error_contexts()` — "Günlük Log
  Sağlığı" kartına bağlam etiketi + sayım listesi ekler (yalnızca alan doluysa;
  yoksa eski UI değişmez → regresyon yok). Bu, görev tanımındaki "recent error
  categories" sinyalini operatöre getirir.
- Kanıt: `test-release-evidence-error-contexts-behavior.R` (saf özet sayım/sıralama/
  top_n/güvenli-karakter ayıklama + **secret-safety: iki noktadan sonraki mesaj
  taşınmaz** + log_health entegrasyonu + UI yüzeyi + eski-davranış regresyon yok).

**Doğrulama (bu container, R 4.6.0):**
- `bash tools/ai_validate.sh quick` → failed_steps=0, skipped_steps=0,
  **app_source_smoke=passed**, focused contract tests OK
  (`artifacts/ai-validation/20260613-125538/summary.json`).
- `bash tools/ai_validate.sh full --boot-smoke` → failed_steps=0, skipped_steps=0,
  **full testthat suite passed (138.8s)**, app_source_smoke=passed,
  shiny_boot_smoke=passed, browser_smoke=**skipped** (browser binary yok — kanıt
  değil), db_sso_vm_validation_performed=false, sql_server Türkçe encoding=not_performed
  (`artifacts/ai-validation/20260613-125639/summary.json`).
- `parse_sanity_check.R` OK (775 dosya). maintainability-ratchet 0 fail/warn
  (max 24 fn, over-budget yok), source-manifest + seam-registry 0 fail/warn.
- 6 yeni test dosyası tek tek + `test_dir` batch (10 dosya, 319 doğrulama)
  0 fail/warn/skip. MCP yaprak-araç geri yükleme batch'te kanıtlandı.
- Untested top-level fn taraması: **49 → 37** (summarize_file_with_llm,
  execute_single_deep_query, find_multiple_queries_with_ai, execute_parsed_tool,
  8 server core runtime guard fonksiyonu kapsandı).

**Bu oturumda KANITLANMAYAN (cloud sınırı):** Windows VM/SSO/DB/SQL Server Türkçe
encoding/gerçek browser UX smoke/vision live. Release Kanıtı sekmesindeki hata
kategorisi gösterimi yalnızca gerçek `logs/mergen_*.log` ile VM'de canlı doğrulanır.

### Oturum: 2026-06-13 — branch `claude/affectionate-bohr-ietfly`

Önceki oturumun bıraktığı en somut "sonraki adım" tamamlandı: **Faz 3 release
kanıt görünürlüğünün UI bağlaması.** Ek olarak Faz 2 davranışsal kapsama
genişletildi. Cerrahi, additive; ratchet/manifest/seam/encoding sözleşmeleri yeşil.

**Faz 3 — Sistem Durumu "Release Kanıtı" sekmesi (operatör görünürlüğü):**
- `R/module_health_release.R` (YENİ): `health_release_ui` + `.health_release_pill` +
  `.health_release_steps_table`. `helpers_release_evidence.R` saf okuyucusunun
  secret-safe özetini (en son VM evidence gate, ai_validate summary, günlük log
  ERROR/WARN sayaçları) mevcut sağlık UI bloklarıyla gösterir. Kanıt-yok
  dürüstlüğü: "Bulunamadı" başarı değil, "Atlandı" (SKIP) kanıt değil; artifact
  yolu / ham log içeriği render EDİLMEZ (savunma derinliği).
- `R/module_health.R`: yeni "Release Kanıtı" sekme paneli, refresh tetikleyicisine
  bağlı saf `release_evidence_overview` reactive'i (DB/LLM/ağ çağrısı yok),
  `switch` yönlendirmesi (`release = health_release_ui(...)`).
- `R/config_source_manifest.R`: `module_health_chartlab` bölümüne `module_health.R`
  ÖNCESİNE eklendi (seam `destek_yonetici_saglik` sahipliği korunur).
- Sections contract: `module_health_chartlab` n 9→10, toplam 262→263 bilinçli güncellendi.

**Faz 2 — davranış testleri (önceki untested kümeden):**
- `test-claude-code-parse-stream-event-behavior.R` — `parse_stream_event()` tüm
  Anthropic stream-json olay türleri + normalizasyon sınırı + NULL düşüşleri.
- `test-release-evidence-behavior.R` genişletildi — `release_evidence_artifact_root`,
  `release_evidence_read_json`, `.release_evidence_scalar` doğrudan testleri.
- `test-health-release-ui-behavior.R` — yeni UI builder davranışı + secret-safe
  sınır + `healthServer` "release" yönlendirme testServer kanıtı.

**Faz 2 — devam (kullanıcı "add more relevant tests"): 5 yeni test (93 doğrulama):**
- `test-sso-auth-server-behavior.R` — `ssoAuthServer` testServer fail-closed akışı
  (en çok bayraklanan güvenlik boşluğu): SSO kapalı→ADMIN; boş/geçersiz token,
  eksik claim, yetkisiz→authenticated FALSE + sso_auth_error; geçerli+yetkili→
  DB zenginleştirme + sso_auth_success. GOTCHA: observeEvent ignoreInit=TRUE →
  PRIME-THEN-SET; custom message yakalama için kök oturum override.
- `test-claude-code-connection-behavior.R` — `check_claude_code_status` (5 dal,
  `processx::process` R6 üreticisi `local_mocked_bindings` ile mock) +
  `test_claude_code_connection` (3 dal, deps stub).
- `test-ai-expert-call-llm-behavior.R` — `call_ai_expert_llm` httr-mock (gövde
  yakalama + max_tokens/temperature kıstaslama + telaffuz düzeltmesi).
  GOTCHA: httr mock'unu test_that bloğuna kapsamak için yardımcı içinde
  `local_mocked_bindings(..., .env = parent.frame())` şart.
- `test-misc-runtime-predicates-behavior.R` — `.path_text_encoding_helper_available`
  (fonksiyon ortamı rebind ile FALSE/TRUE), `.fm_runtime_is_reactivevalues`,
  `ui_asset_zone_get` (geçerli/geçersiz/bilinmeyen id).
- `test-send-message-request-callbacks-behavior.R` —
  `mergen_build_send_message_request_callbacks` cleanup/abort kapanışlarının
  req_id'yi request-scoped yakalayıp ilettiği (bayat callback koruması).
- Ayrıca `module_health_release.R`'den kullanılmayan `.health_release_kv` ölü kodu
  kaldırıldı (taslak artığı).

**Doğrulama (bu container, R 4.6.0):**
- `bash tools/ai_validate.sh quick` → failed_steps=0, skipped_steps=0,
  **app_source_smoke=passed** (her iki commit setinden sonra), focused contract tests OK.
- `bash tools/ai_validate.sh full --boot-smoke` → failed_steps=0, skipped_steps=0,
  **full testthat suite passed (121.5s)**, shiny_boot_smoke=passed,
  app_source_smoke=passed, browser_smoke=**skipped** (browser binary yok — kanıt değil),
  db_sso_vm=false, sql_server Türkçe encoding=not_performed.
- `parse_sanity_check.R` OK (770 dosya). Sections/source-manifest/seam-registry/
  maintainability-ratchet/e2e-health contract testleri: 0 fail/warn.
- Tüm yeni/değişen test dosyaları tek tek + `test_dir` batch'te 0 fail/warn/skip
  (Faz 3 üçlü batch 147 PASS; Faz 2 devam beşli batch 93 PASS).
- `seam_doctor.R` OK (destek_yonetici_saglik runtime-dosya 41→42).
- Untested top-level fn taraması: 61 → ~52 (parse_stream_event, release internals,
  ssoAuthServer, check/test_claude_code_connection, call_ai_expert_llm,
  3 misc predicate, mergen_build_send_message_request_callbacks kapsandı).

**Bu oturumda KANITLANMAYAN (cloud sınırı):** Windows VM/SSO/DB/SQL Server Türkçe
encoding/gerçek browser UX smoke/vision live. Release Kanıtı sekmesinin gerçek
artifact'larla canlı görünümü yalnızca VM'de (artifact üretildikten sonra) doğrulanır.

### Oturum: 2026-06-12 — branch `claude/peaceful-ritchie-hvd1y7`

Başlangıç tespiti: untested top-level fonksiyon sayısı 85 (FIXED-string tarama).
Admin renderer / health probe / destek DB / galeri kümeleri zaten kapalı olduğu
için `.ai` prompt'larındaki o hedefler atlandı (yeniden doğrulandı, bayat değil).

**TAMAMLANDI.** Yapılanlar:

**Faz 2 — 9 yeni davranış testi (379 doğrulama, batch dahil 0 fail/warn/skip):**
- `test-cc-path-policy-collapse-behavior.R` (18) — cc_policy_collapse_dot_segments.
- `test-admin-doc-internal-helpers-behavior.R` (25) — admin_doc_lookup/repo_root/
  strip_tags/allowed_tags.
- `test-markdown-safety-image-serve-behavior.R` (21) — mergen_serve_image_data_url +
  .mergen_register_image_data_obj (session-scoped URL, memoizasyon, base64 fallback,
  içerik türü eşlemesi).
- `test-server-wiring-guard-behavior.R` (35) — chat engine deps bundle + core
  interaction/observer bundle guard'ları.
- `test-sso-fetch-jwks-behavior.R` (16) — httr-mock JWKS getirme.
- `test-config-logging-sinks-behavior.R` (21) — log_ai_call/log_user_action/
  log_error_with_context/.forward_log_call gerçek dosya appender ile (9C glue).
- `test-rate-limiter-worker-pool-behavior.R` (15) — monitor_workers + stop_future_cluster.
- `test-quick-actions-server-behavior.R` (37) — quickActionsInit testServer.
- `test-api-key-server-behavior.R` (26) — apiKeyServer testServer.

**Faz 3 — release kanıt görünürlüğü:**
- `R/helpers_release_evidence.R` (saf, secret-safe artifact okuyucu) +
  manifest wiring (support_admin_health_helpers, health_checks'ten önce) +
  `test-release-evidence-behavior.R` (49 doğrulama).
- Sections contract anchor'ları bilinçli güncellendi (n 6→7, toplam 261→262).
- UI bağlama (Sistem Durumu sekmesi) SONRAKİ oturuma bırakıldı.

**Faz 4 — `docs/feature-ownership-map.md`** (9 özellik; tüm somut test referansları
repoda doğrulandı; docs/README.md'ye bağlandı).

**Faz 5 — adversarial + 2 cerrahi güvenlik sertleştirmesi:**
- `mergen_sanitize_markdown_links`: javascript: yanında vbscript: ve data:text/html
  link protokollerini de etkisizleştirir (güvenli data:image/http/https korunur).
- `utils_upload_validator`: Unicode bidi-override (Trojan Source) dosya adlarını
  reddeder (.upload_has_bidi_control). Türkçe adlar etkilenmez.
- `test-adversarial-hostile-input-behavior.R` (116 doğrulama).

**Doğrulama (bu container, R 4.6.0):**
- `bash tools/ai_validate.sh quick` → failed_steps=0, app_source_smoke=passed.
- `bash tools/ai_validate.sh full --boot-smoke` → failed_steps=0,
  app_source_smoke=passed, **full testthat suite=passed (130.8s)**,
  shiny_boot_smoke=passed, browser_smoke=**skipped** (browser binary yok — kanıt değil),
  db_sso_vm_validation_performed=FALSE, sql_server Türkçe encoding=not_performed.
- `parse_sanity_check.R` OK (762 dosya). `maintainability_report.R` 100/100
  (max 24 fn, max 777 satır). `seam_doctor.R` OK. `frontend_complexity_doctor.R` OK.
- Yeni 11 dosya hem tek tek hem `test_dir` batch'te 379 PASS / 0 fail/warn/skip.

**Bu oturumda KANITLANMAYAN (cloud sınırı):** Windows VM/SSO/DB/SQL Server Türkçe
encoding/gerçek browser UX smoke/vision live. Bunlar VM kapılarının işidir.

## Kalan yüksek değerli untested kümeler (sonraki oturumlar için)

Güncel tarama (2026-06-15 (C) sonrası): **3 untested top-level fn** — ÜÇÜ DE
runtime'da `rm()` ile silinen bootstrap yardımcısı, gerçek sözleşme taşımıyor,
BİLİNÇLİ atlandı:

- `.helpers_llm_sse_source_sibling` (helpers_llm_sse.R) — tanım sonrası `rm()`.
- `.mcp_bootstrap_assign_global_function` (helpers_mcp_bootstrap.R) — `rm()`.
- `.mcp_bootstrap_require_tool_functions` (helpers_mcp_bootstrap.R) — `rm()`.

By-name taraması bu noktada pratik olarak tükenmiştir. Bundan sonraki kapsama
işi, isimle çağrılan ama davranışsal olarak zayıf test edilen fonksiyonların
dal/şube kapsamasını derinleştirmek (ör. `call_llm_worker` ikinci-geçiş/araç
zinciri, `sendMessageInit` mod-dispatch sonrası akışlar) veya yeni eklenen
runtime kodu olmalıdır.

2026-06-15 (C) oturumunda KAPSANANLAR (yukarıdan çıkarıldı): 11 `.syap_*` kart
yapıcısı (TEK TEK, sahiplik sınırı), `call_llm_worker` (araçsız yol + hata
normalizasyon), `sendMessageInit` (send_message erken-dönüş korumaları),
`.character_video_debug`.

2026-06-15 oturumunda KAPSANANLAR (yukarıdan çıkarıldı): `serverInitChatRuntime`,
`chat_simulate_streaming` (KARAR/erken-çıkış dalları; observer döngüsü hariç),
`cc_bind_claude_code_stream_polling` (stop/klavye gözlemcileri + poll erken
dalları). Ayrıca `format_claude_code_existing_file_link_html` traversal/öznitelik
güvenlik kapsaması (zaten referanslıydı; davranışsal dal açığı kapandı).

2026-06-14 oturumunda KAPSANANLAR (yukarıdan çıkarıldı): `handle_file_upload_batch`,
`pk_deep_analysis_process`, `pk_analiz_process_request`, `find_best_query_with_ai`,
`run_claude_code_streaming`, `prepare_claude_code_document_context`,
`write_claude_code_document_summary_file`,
`summarize_claude_code_documents_with_local_llm` (+ 2 latency fn); CONTINUE'da ayrıca
`cc_refresh_user_file_manager_after_run`, `admin_ha_show_modal`,
`attach_required_packages`, `gc_scheduler`, `start_gc_scheduler_once`; CONTINUE-2'de
`sessionCacheInit`, `mergen_console_appender`, `.mcp_prepare_chart_data_fn`
(runtime adı `helpers_mcp_tools$prepare_chart_data`).
- `.syap_*` kart builder'ları (module_settings_yapilandirma_ui.R) —
  `test-settings-yapilandirma-ui-id-surface-behavior.R` id yüzeyini dolaylı
  koruyor; doğrudan birim testi DÜŞÜK öncelik.
- UI builder'lar: `adminYanitAnaliziUI`, `adminDokumantasyonUI`,
  `admin_doc_group_tab_panels` — saf/kolay; hızlı kazanım (KÜÇÜK).
- `admin_ha_show_modal` (runjs string builder), `attach_required_packages`,
  `cc_refresh_user_file_manager_after_run`, `cc_bind_claude_code_stream_polling`,
  `.mcp_bootstrap_assign_global_function`/`_require_tool_functions`,
  `.mcp_prepare_chart_data_fn`, `.helpers_llm_sse_source_sibling` — küçük/orta.

2026-06-13 (B) oturumunda KAPSANANLAR (yukarıdan çıkarıldı): `summarize_file_with_llm`,
`execute_single_deep_query`, `find_multiple_queries_with_ai`, `execute_parsed_tool`,
ve 8 server core runtime guard (`.server_runtime_stop`,
`.server_core_interaction_stop/_require_context/_require_values/_require_functions/
_resolve_bundle`, `.server_core_observer_require_functions/_call_with_optional_boot_ready`).

2026-06-13 (A) oturumunda KAPSANANLAR: `ssoAuthServer`,
`check_claude_code_status`/`test_claude_code_connection`, `call_ai_expert_llm`,
`ui_asset_zone_get`, `.fm_runtime_is_reactivevalues`,
`.path_text_encoding_helper_available`, `mergen_build_send_message_request_callbacks`,
`parse_stream_event`, release evidence iç yardımcıları.

## Faz 3 sonraki adımlar

- ✅ Sistem Durumu "Release Kanıtı" sekmesi UI bağlaması 2026-06-13'te tamamlandı
  (`R/module_health_release.R` + `R/module_health.R` switch). Operatör artık
  uygulamayı kapatmadan en son kanıt özetini görüyor.
- ✅ Hata kategorisi özeti 2026-06-13 (B) oturumunda eklendi
  (`release_evidence_summarize_error_contexts` + `release_evidence_log_health$error_contexts`
  + Release Kanıtı sekmesinde `.health_release_error_contexts`). `Error in <bağlam>:`
  kalıbından secret-safe bağlam sayımı; mesaj içeriği taşınmaz.
- ✅ Latency / istek-süresi özeti 2026-06-14'te eklendi. Log formatı
  doğrulandı (`log_ai_call` → `AI Call: ... duration=<sn>s, success=...`);
  `release_evidence_summarize_ai_call_latency` (secret-safe, yalnızca sayısal) +
  `log_health$ai_call_latency` additive alanı + `.health_release_ai_latency` UI
  (Doğrulama Kanıtı > Günlük Log Sağlığı kartı). Uydurma format YOK.
- KALAN: post-deploy smoke durumu için ayrı bir artifact ailesi gerekir (üretici
  henüz yok — uydurma kanıt eklenmez). Latency özetinin gerçek `logs/mergen_*.log`
  ile canlı görünümü bir VM oturumunda gözle doğrulanmalı.
- Release Kanıtı sekmesinin gerçek artifact'larla VM canlı görünümü (artifact +
  gerçek `logs/mergen_*.log` üretildikten sonra) bir VM oturumunda gözle doğrulanmalı.

## Doğrulama kanıt sınırı (her oturum geçerli)

- Cloud koşumları VM/DB/SSO/browser/tam-suite kanıtı DEĞİLDİR.
- `renv.lock` asla Linux/cloud'dan üretilmez.
- Tam strict suite cloud checkout'ta önceden var olan ortam eksikleri nedeniyle
  tamamlanmaz (vendored www varlıkları, `.Renviron`); dosya-bazlı + batch
  koşumlarla doğrulanır.

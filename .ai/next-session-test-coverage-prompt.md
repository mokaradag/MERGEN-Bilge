# CONTEXT — Faz 2→9.5 oturumu `claude/zen-gauss-w423sz` (2026-06-15, do NOT redo)

Bu oturum 3 AĞIR runtime closure'unu davranışsal kapattı (94 doğrulama, 0
fail/warn/skip), 1 Faz-5 adversarial güvenlik boşluğu + 1 cerrahi sertleştirme
yaptı ve kullanıcının Windows VM testthat suite'indeki 4 hatayı (3 dosya)
düzeltti. Untested 20 → 17. ZATEN YAPILDI — tekrar etme:
- `test-server-init-chat-runtime-behavior.R` — `serverInitChatRuntime` fabrikası
  (4 kapanış + **add_message canlı user-id**). GOTCHA: dosyada tanımlı
  temsilciler (`chat_reset_state`/`chat_add_message`/`chat_generate_title_from_prompt`/
  `chat_simulate_streaming`) source SONRASI stub'lanmalı.
- `test-chat-simulate-streaming-behavior.R` — `chat_simulate_streaming` KARAR/
  erken-çıkış dalları. **GOTCHA (kritik):** tüm testler `stop_generation=function() TRUE`
  → `shiny::observe`/`invalidateLater(25)` döngüsüne GİRİLMEZ (tam senkron,
  kırılgan değil). Dosyada tanımlı `chat_reset_state`/`push_followup_update`/
  `chat_store_message_in_saved_chats` source SONRASI stub'lanır; promise cat
  çıktısı `.css_drain()` (later::run_now sınırlı döngü) ile `capture.output` İÇİNDE.
- `test-claude-code-stream-poll-binding-behavior.R` — `cc_bind_claude_code_stream_polling`.
  GOTCHA: bağlayıcı moduleServer DEĞİL → `function(id) moduleServer(id, ...)` ile
  sar, rv döndür; `session$returned$is_running <- TRUE` + `session$flushReact()`
  ile poll dalları tetiklenir (capture-in-place gerekiyorsa is_running=FALSE
  başlat, root$sendCustomMessage override et, sonra flip). `shinyjs::click`
  `local_mocked_bindings(.package="shinyjs")`; processx fake `new.env` (kill/
  poll_io/read_*/is_alive/get_exit_status). stop gözlemcisi request-id kapsamlı
  finalize'i kanıtlanır (korumalı sözleşme). invalidateLater ilerletilmez.
- `test-claude-code-existing-file-link-security-behavior.R` (Faz 5) —
  `format_claude_code_existing_file_link_html`. KEŞİF: mevcut encoding testinin
  source helper'ı `helpers_claude_code_path_policy.R`'yi YÜKLEMEDİĞİ için
  `cc_policy_path_inside_roots` `exists(...)` FALSE → izinli-kök-dışı reddi dalı
  hiç sınanmamıştı. Yeni test gerçek path-policy'yi yükler. Cerrahi sertleştirme:
  öznitelik bağlamı escape'i `attribute=TRUE` (fail-before/pass-after). Linux'ta
  bir dosya adına `"`/`<`/`>` koyup XSS sınırı kanıtlanabilir.

Windows VM hata düzeltmeleri (kullanıcı ekranı; do NOT redo):
- `test-file-click-observers-behavior.R`: `file.path(getwd(),...)` + `%in%` →
  `any(endsWith(exists_paths, "www/.../x.png"))`. Üretim `normalizePath(getwd(),
  winslash="/")` ile UNC `\\sunucu/...` üretirken ham getwd() `//sunucu/...`
  veriyor; suffix doğrulama platform-bağımsız.
- `module_proje_kaynak_analizi.R:223` (ÜRETİM): yasaklı-SQL kapısı
  `toupper(enc2utf8(final_sql))` + locale-grepl → Windows Türkçe locale'de hata.
  `grepl(...,final_sql,ignore.case=TRUE,perl=TRUE,useBytes=TRUE)` (toupper YOK).
  `helpers_deep_analysis.R:289` enc2utf8 kullanmadığından VM'de geçer → dokunma.
- `test-release-evidence-behavior.R:334`: "/repo/kok" Windows'ta mutlak değil →
  `withr::local_tempdir()` + `normalizePath(...,winslash="/")` ile beklenen.

GENEL DERS: `getwd()`-tabanlı tam-yol test beklentileri ve sabit POSIX "/x"
yolları Windows VM'de kırılır; suffix/`endsWith` + `withr::local_tempdir()`
kullan. `enc2utf8`+`toupper`+`grepl` Windows Türkçe locale'de zehirlidir; ASCII
anahtar taramasını `useBytes=TRUE` ile yerelden bağımsız yap.

Devam (aynı oturum, "add more test") — 2 Faz-5 güvenlik testi + 1 sertleştirme:
- `test-claude-code-downloads-security-behavior.R` —
  `resolve_claude_code_generated_path`/`list_claude_code_generated_file_paths`/
  `stage_claude_code_downloads` (yalnızca izinli kök içi indirilebilir; kök-dışı
  traversal düşürülür). GOTCHA: `resolve_*` var-olmayan yolda 1.5sn `Sys.sleep`
  döngüsü → var-olan dosya + mutlak yol + `withr::local_dir(wd)`; indirme kökü
  `withr::local_options(mergen.claude_code_download_root=tempdir)`.
- `test-claude-code-downloads-html-behavior.R` —
  `format_claude_code_generated_downloads_html` kart + XSS sınırı; öznitelik
  escape (`R/helpers_claude_code_downloads_html.R` href/download/title
  `attribute=TRUE`'ya sertleştirildi).
Genel ders: Bilge Yolaç indirme HTML üreticilerinde öznitelik bağlamı escape'i
`attribute=TRUE` olmalı; downloads helper'larındaki `Sys.sleep` bekleme döngüleri
için testlerde HEP var-olan dosya kullan.

Kalan en yüksek değerli untested (~17, çoğu ağır): `sendMessageInit`,
`call_llm_worker` (çok ağır testServer/ikinci-pass), `.syap_*` 11 UI builder
(dolaylı korunuyor, düşük öncelik), küçük bootstrap/debug helper'ları.

---

# CONTEXT — Faz 2→9.5 oturumu `claude/affectionate-faraday-yksxki` (2026-06-14, do NOT redo)

Bu oturum görev önceliği sırasıyla 8 untested fonksiyonu davranışsal kapattı + Faz 3
latency özetini ekledi. 6 yeni test, **185 doğrulama, 0 fail/warn/skip** (tek tek +
`test_dir` batch). `ai_validate quick` TAM geçti (failed=0, skipped=0,
app_source_smoke=passed). Untested 36 → 28. ZATEN YAPILDI — tekrar etme:
- `test-file-pipeline-upload-batch-behavior.R` — `handle_file_upload_batch`. GOTCHA:
  `shinyjs::delay` `local_mocked_bindings(delay=function(ms,expr){force(expr)},
  .package="shinyjs")` → senkron özyineleme; copy_to_mcp_base/global_register_file/
  processAndSummarizeFile/showToast/showNotification/cat env'e kaydedici stub; gerçek
  temp dosya ile file.info boyutu doğrulanır. **Faz 5:** geçersiz uzantı → kopya/indeks/
  UI/özet HİÇBİRİ çalışmaz (gizli kaydedilmiş-ama-geçersiz yükleme yok).
- `test-deep-analysis-process-behavior.R` — `pk_deep_analysis_process` (orkestrasyon/
  çoklu→tekil fallback/boş-sonuç/yetki/durdurma; tüm servis helper'ları env stub).
- `test-pk-analiz-process-request-behavior.R` — `pk_analiz_process_request` (erken-dönüş
  + **Faz 5 YASAKLI SQL reddi**; SSO-kimlik-hazır-değil DB'ye gitmeden döner) +
  `find_best_query_with_ai`. **GOTCHA (kritik):** `module_proje_kaynak_analizi.R`
  kaynak-zamanı `pk_required_helpers` guard döngüsü içerir — guard'ın aradığı 12
  yardımcı adını env'e ÖNCEDEN `assign(fn, function(...) NULL, envir=env)` ile koy,
  SONRA `source(module, local=env)`; `exists(inherits=TRUE)` tatmin → guard
  `source(...,local=globalenv())` ATLAR (globalenv kirliliği yok). `find_best` için
  `withr::local_options(mergen.filter_model="m1")` ile api_config default'unu tembel tut.
- `test-claude-code-run-streaming-behavior.R` — `run_claude_code_streaming`. GOTCHA:
  `local_mocked_bindings(process=list(new=function(...) fake), .package="processx")`;
  fake_proc env'i is_alive sayaçlı (alive_times kez TRUE sonra FALSE) + poll_io/
  read_output_lines (ilk çağrı satırlar, sonra character(0))/read_all_output/
  read_all_error/get_exit_status/kill. timeout_sec=-1 ile zaman aşımı deterministik.
- `test-claude-code-document-orchestration-behavior.R` — 3 doküman orkestratörü.
  GOTCHA: `helpers_claude_code_documents.R` kaynak-zamanı extractor-guard'ı
  (`extract_supported_document_text_for_claude` + `get_office_document_reader_template_path`)
  — bu iki adı env'e ÖNCEDEN stub koy → guard atlanır + bunlar zaten test stub'ların.
  Gerçek PDF/Excel/DOCX fixture YOK (çıkarıcı stub döndürür).
- Faz 3: `release_evidence_summarize_ai_call_latency` (saf; `AI Call: ... duration=<sn>s`
  → yalnızca sayısal; kullanıcı/model taşımaz) + `log_health$ai_call_latency` +
  `.health_release_ai_latency` UI. Kanıt: `test-release-evidence-ai-latency-behavior.R`.
  **GOTCHA:** maintainability raporu YALNIZCA `(<-|=)\s*function\s*\(` (atama) sayar;
  anonim `lapply(x, function(...))` SAYILMAZ — saf summarizer ratchet'i etkilemedi
  (helpers_release_evidence 20→21, module_health_release 4→5; global cap 24).

ÖNEMLİ — `full --boot-smoke` testthat suite'inde TEK başarısız:
`test-file-click-observers-behavior.R` (PR #464; BENİM DEĞİL; benim dosyalarım
yüklenmeden TEK BAŞINA da fail). Linux/cloud çalışma-dizini/MockShinySession
prime-then-set artifact'ı; **kullanıcı: Windows VM'de GitHub testthat suite GEÇİYOR.**
Trust VM over cloud; DOKUNMA.

DEVAM (aynı oturum, "continue") — 4 yeni test, 5 untested fn daha (27 doğrulama,
untested 28 → 23). ZATEN YAPILDI — tekrar etme:
- `test-claude-code-refresh-fm-after-run-behavior.R` — `cc_refresh_user_file_manager_after_run`
  (oturum/userData/fm_data/refresh guard'ları + "bilge_yolac_generated" + hata yutma).
- `test-admin-ha-show-modal-behavior.R` — `admin_ha_show_modal`. GOTCHA: `shinyjs::runjs`
  `local_mocked_bindings(.package="shinyjs")` ile yakalanır; ns(modal_id) JS string'i.
- `test-config-packages-attach-behavior.R` — `attach_required_packages`. GOTCHA:
  `library` env'e kaydedici stub; config_packages.R source-time validate+stop+attach
  `tryCatch(source(...))` ile yutulur (fn tanımı stop'tan ÖNCE → env'de kalır);
  kaynak-zamanı attach gürültüsünü test başında rec sıfırlayarak temizle.
- `test-gc-scheduler-behavior.R` — `gc_scheduler`/`start_gc_scheduler_once`. GOTCHA:
  `later::later` `local_mocked_bindings(.package="later")` ile yakalanır (gerçek
  callback zamanlanmaz); `gc` env stub; `.mergen_gc_scheduler_started` `.GlobalEnv`
  bayrağı `withr::defer` ile save/restore (batch kirliliği yok). config_file_store.R
  testthat bağlamında temiz source olur (helper_bootstrap dışı standalone source
  testthat::teardown_env nedeniyle abort eder — test_file içinde çalıştır).

DEVAM-2 (aynı oturum, "cover the next targets") — 3 yeni test, 3 untested fn daha
(36 doğrulama, untested 23 → 20). ZATEN YAPILDI — tekrar etme:
- `test-session-cache-init-behavior.R` — `sessionCacheInit`: döndürülen cache API
  (cache_session_token/setup_user_session/cache_mcp_file_locally/
  update_mcp_registry_snapshot/get_cache_dir). GOTCHA: sahte oturum env (token +
  userData + onSessionEnded); yol/MCP serbest bağımlılıkları (safe_windows_short_path,
  path_exists_relaxed→file.exists, normalize_excel_path, session_runtime_store_snapshot_mcp)
  env stub; gerçek geçici dosya sistemi kullanılır.
- `test-config-logging-console-appender-behavior.R` — `mergen_console_appender`.
  GOTCHA: config_logging.R kaynak-zamanı logger global durumunu (threshold +
  appender/layout index 1/2) değiştirir → geçici MERGEN_LOG_DIR + save/restore
  (`logger::log_appender(index=1)`/`log_layout(index=1)`/`log_threshold()` yakala,
  `withr::defer` ile geri yükle, index 2'yi `delete_logger_index` + sustur). cat
  çıktısı `utils::capture.output` ile yakalanır.
- `test-mcp-prepare-chart-data-behavior.R` — `helpers_mcp_tools$prepare_chart_data`.
  GOTCHA (kritik): top-level `.mcp_prepare_chart_data_fn` kaynak sonunda
  helpers_mcp_tools$prepare_chart_data'ya atanıp `rm` edilir → globalenv'de
  `.mcp_prepare_chart_data_fn` YOK; runtime'da YALNIZCA `hmt$prepare_chart_data`
  üzerinden çağrılır. MCP zinciri globalenv'e tekil yüklenir; yaprak araçlar
  (auto_file_name/normalize_chart_type/resolve_file_argument/safe_read_table_generic)
  test başına override + `withr::defer` ile geri yüklenir. Erken-dönüş dalları
  (ok=FALSE / "Dosya okunamadı") + argüman normalizasyonu deterministik.

Kalan en yüksek değerli untested küme (~20, hepsi AĞIR): `sendMessageInit`,
`serverInitChatRuntime`, `chat_simulate_streaming`, `call_llm_worker` (testServer +
yoğun stub), `cc_bind_claude_code_stream_polling` (büyük observer-bağlama). Kalan
küçükler (`.mcp_bootstrap_*` rm'd, `.helpers_llm_sse_source_sibling`,
`.character_video_debug`) düşük değer/kırılgan — bir güvenilir ağır test, çok sayıda
kırılgan teste tercih edilir.

---

# CONTEXT — Faz 2→9.5 oturumu `claude/serene-bell-3l1xw6` (2026-06-13 B, do NOT redo)

Bu oturum servis-bağlı runtime mantığına 5 davranış testi + Faz 3 secret-safe hata
kategorisi özeti ekledi. Hepsi 0 fail/warn/skip (tek tek + `test_dir` batch 319
doğrulama). `ai_validate quick` TAM geçti (failed=0, skipped=0, app_source_smoke=passed)
ve `full --boot-smoke` TAM geçti (full testthat suite **passed 138.8s**, shiny boot
passed; browser smoke SKIPPED — browser yok). Untested fn 49 → 37. ZATEN YAPILDI:
- `test-file-pipeline-summarize-behavior.R` — `summarize_file_with_llm`
  (`call_llm_with_retry` env stub; list($content)/char/boş/NA/hata fallback,
  60000 kısaltma, "ÇIKARTMAK" sistem talimatı).
- `test-deep-analysis-execute-query-behavior.R` — `execute_single_deep_query`
  erken-dönüş + GÜVENLİK (DROP/DELETE/TRUNCATE/ALTER + `;` zinciri reddi → "Güvenlik
  ihlali."), bağlantı yok/boş SQL/boş sonuç/RLS-yetki, başarı orkestrasyonu.
  GOTCHA: `get_connection`/`release_connection` env'e; `DBI::dbGetQuery`
  `local_mocked_bindings(.package="DBI")`; disable_ai_filters=TRUE ile AI filtre
  çağrısını atla; success path için `apply_rls_to_data`/`generate_statistical_summary`
  env stub.
- `test-deep-analysis-multi-query-behavior.R` — `find_multiple_queries_with_ai`
  (LLM JSON→sorgu eşleme; dedup/güven<30/sıralama/max_queries/aralık-dışı/```json
  çiti/geçersiz JSON/list($content)). GOTCHA: `withr::local_options(mergen.filter_model=...)`
  set et ki getOption default'u (`api_config$local_models[1]`) tembel kalsın;
  `call_local_llm`/`resolve_local_llm_credentials` env stub; R.utils kurulu olduğundan
  `withTimeout` gerçek koşar (mock gerekmez).
- `test-mcp-execute-parsed-tool-behavior.R` — `helpers_mcp_tools$execute_parsed_tool`
  yönlendirme. GOTCHA: MCP zinciri globalenv'i ZORUNLU kılar (bootstrap
  helpers_mcp_tools'u globalenv'de arar, fresh env'de "MCP helper ortamı
  başlatılamadı" stop'u verir). Zinciri globalenv'e source-once yükle, yaprak
  araçları (`analyze_uploaded_file` vb.) recorder ile değiştir, test başına
  `withr::defer(envir=parent.frame())` ile ORİJİNALLERİ GERİ YÜKLE (batch'te
  mcp-tools-parse/mcp-excel-resolve ile çakışmayı önler).
- `test-server-core-runtime-guards-behavior.R` — wiring-guard testinde İSİMLE
  çağrılmayan saf guard'lar: `.server_runtime_stop`, `.server_core_interaction_*`
  (stop/require_context/require_values/require_functions/resolve_bundle),
  `.server_core_observer_require_functions`, `_call_with_optional_boot_ready` (4 dal).
- Faz 3: `R/helpers_release_evidence.R` `release_evidence_summarize_error_contexts`
  (saf, `Error in <bağlam>:` etiketini sayar, mesaj taşımaz, güvenli karakter +
  60 sınır, "diğer" kovası, top_n) + `release_evidence_log_health$error_contexts`
  additive alanı + `R/module_health_release.R` `.health_release_error_contexts`
  (Günlük Log Sağlığı kartına kategori listesi; alan yoksa eski UI değişmez).
  Kanıt: `test-release-evidence-error-contexts-behavior.R` (secret-safety:
  iki noktadan sonraki mesaj taşınmaz).

Ek (aynı oturum, "small batch"): `test-admin-ui-builders-behavior.R` — `adminYanitAnaliziUI`/
`adminDokumantasyonUI`/`admin_doc_group_tab_panels` (gerçek `admin_page_layout`;
`library(htmlwidgets)` ŞART çünkü helpers_admin_analytics.R source-time `JS()` kullanır).
NOT: `.mcp_bootstrap_*` bootstrap sonunda `rm()` ile silinen GEÇİCİ helper'lar —
runtime'da yok; birim testi kırılgan, ATLA. Untested 37 → 34.

Kalan en yüksek değerli untested küme (~34): `sendMessageInit`, `chat_simulate_streaming`,
`call_llm_worker`, `pk_deep_analysis_process`/`pk_analiz_process_request`/
`find_best_query_with_ai`, `handle_file_upload_batch` (uzantı-reddi dalı = Faz 5),
`run_claude_code_streaming`, claude_code document orkestratörleri, UI builder'lar
(`adminYanitAnaliziUI`/`adminDokumantasyonUI`/`admin_doc_group_tab_panels` — kolay),
`admin_ha_show_modal`, `.mcp_bootstrap_*`, `gc_scheduler`/`start_gc_scheduler_once`.

---

# CONTEXT — Faz 2→9.5 oturumu `claude/affectionate-bohr-ietfly` (2026-06-13, do NOT redo)

Bu oturum Faz 3 release-kanıt UI bağlamasını tamamladı ve 2 Faz 2 davranış testi
ekledi. Hepsi 0 fail/warn/skip (tek tek + `test_dir` batch). `ai_validate quick`
TAM geçti (failed=0, skipped=0, app_source_smoke=passed). ZATEN YAPILDI — tekrar etme:
- **Faz 3 UI:** `R/module_health_release.R` (`health_release_ui`,
  `.health_release_pill`, `.health_release_steps_table`) Sistem Durumu'na
  "Release Kanıtı" sekmesi olarak bağlandı (`R/module_health.R` switch +
  refresh'e bağlı saf `release_evidence_overview` reactive; manifest
  `module_health_chartlab` n 9→10, toplam 263). Kanıt: `test-health-release-ui-behavior.R`
  (UI builder + secret-safe sınır + healthServer "release" yönlendirme testServer).
- `parse_stream_event()` (helpers_claude_code_streaming.R) tüm stream-json olay
  türleriyle kapsandı: `test-claude-code-parse-stream-event-behavior.R`. GOTCHA:
  `content_block_start` text yolu normalize ETMEZ; yalnızca `content_block_delta`
  text_delta/input_json_delta ve `result` normalize eder — testte
  `normalize_text_utf8`'i env'e tanınabilir önekli stub ile koyup yolu kanıtla.
- `release_evidence_artifact_root` / `release_evidence_read_json` /
  `.release_evidence_scalar` doğrudan testleri `test-release-evidence-behavior.R`'a eklendi.

Aynı oturum devamı (kullanıcı "add more relevant tests") — 5 yeni test (93 doğrulama),
do NOT redo:
- `test-sso-auth-server-behavior.R` — `ssoAuthServer` testServer (fail-closed SSO).
  GOTCHA: `observeEvent(input$sso_jwt_token, ignoreInit=TRUE)` → PRIME-THEN-SET
  (`setInputs(sso_jwt_token="__prime__"); setInputs(sso_jwt_token=REAL)`); custom
  message yakalama için `root <- .subset2(session,"parent"); root$sendCustomMessage <- ...`.
  SSO kapalı testinde `MERGEN_AUTH_LEVEL=NA` ile env'i KALDIR (boş "" değil) ki
  `Sys.getenv(...,"ADMIN")` varsayılanı dönsün.
- `test-claude-code-connection-behavior.R` — `check_claude_code_status` (5 dal:
  CLI yok/başarı/sıfırdan farklı çıkış/zaman aşımı/başlatma hatası) ve
  `test_claude_code_connection` (3 dal). GOTCHA: `processx::process` R6 üreticisi
  `local_mocked_bindings(process = list(new=function(...) fake_proc), .package="processx")`
  ile mock'lanır (fake_proc: wait/is_alive/read_all_output/read_all_error/
  get_exit_status/kill).
- `test-ai-expert-call-llm-behavior.R` — `call_ai_expert_llm` httr-mock. GOTCHA:
  mock'u test_that bloğuna kapsamak için YARDIMCI fonksiyon içinde
  `local_mocked_bindings(..., .env = parent.frame())` ŞART; yoksa mock yardımcı
  dönünce kalkar ve gerçek `httr::POST` çalışır.
- `test-misc-runtime-predicates-behavior.R` — `.path_text_encoding_helper_available`
  (`environment(f) <- new.env(parent=baseenv())` ile arama yolunu kontrol et,
  globalenv'deki gerçek normalize_text_utf8'i atlamak için), `.fm_runtime_is_reactivevalues`,
  `ui_asset_zone_get`.
- `test-send-message-request-callbacks-behavior.R` —
  `mergen_build_send_message_request_callbacks` (cleanup/abort req_id capture).
- Ölü kod kaldırıldı: `module_health_release.R` `.health_release_kv`.

Kalan en yüksek değerli untested küme (~52): `sendMessageInit`, `chat_add_message`/
`chat_simulate_streaming`, `call_llm_worker`, deep_analysis/pk_analysis servis-bağlı
helper'lar, `run_claude_code_streaming`, `execute_parsed_tool`, claude_code document
helper'ları, `cc_refresh_user_file_manager_after_run`, `admin_ha_show_modal`,
`.syap_*` kart builder'ları (id yüzeyi dolaylı korunuyor; düşük öncelik).

---

# CONTEXT — Faz 2→9.5 oturumu `claude/peaceful-ritchie-hvd1y7` (do NOT redo)

Bu oturum 11 yeni davranış testi (~444 doğrulama) ekledi ve 2 cerrahi güvenlik
sertleştirmesi yaptı. Hepsi 0 fail/warn/skip (tek tek + `test_dir` batch).
ZATEN KAPSANDI — tekrar etme:
- `cc_policy_collapse_dot_segments` (`test-cc-path-policy-collapse-behavior.R`).
- `admin_doc_lookup`/`admin_doc_repo_root`/`admin_doc_strip_tags`/
  `admin_doc_allowed_tags` (`test-admin-doc-internal-helpers-behavior.R`).
- `mergen_serve_image_data_url` + `.mergen_register_image_data_obj`
  (`test-markdown-safety-image-serve-behavior.R`).
- Server wiring guard'ları: `.server_wiring_*`, `serverBuildChatEngineDependencyBundle`,
  `.server_core_interaction_require_bundle`, `.server_core_observer_require_bundle`
  (`test-server-wiring-guard-behavior.R`).
- `sso_fetch_jwks` httr-mock (`test-sso-fetch-jwks-behavior.R`).
- `log_ai_call`/`log_user_action`/`log_error_with_context`/`.forward_log_call`
  GERÇEK logger dosya appender'ı ile (`test-config-logging-sinks-behavior.R`) —
  frame-sayımlı stub DEĞİL: config_logging.R'yi geçici MERGEN_LOG_DIR ile source et,
  index-2 konsol appender'ını sustur, logger global durumunu withr::defer ile
  geri yükle, dosyaya yazılan satırları oku. NOT: log_error_with_context "Stack
  trace:" DEBUG satırı test kodunu deparse ettiği için `^ERROR` ile filtrele.
- `monitor_workers` + `stop_future_cluster` (`test-rate-limiter-worker-pool-behavior.R`)
  — parallel::stopCluster mock + future::plan geri yükleme.
- `quickActionsInit` testServer (`test-quick-actions-server-behavior.R`) — GOTCHA:
  `get_tool_mode_config` stub'ı ÜÇÜNCÜ `config` argümanını da almalı (intro builder
  `build_quick_action_intro_message(..., config=api_config)` çağırır), yoksa
  show_quick_action_intro sessizce patlar.
- `apiKeyServer` testServer (`test-api-key-server-behavior.R`) — tüm anahtar
  yardımcıları yerel sahte stub; gerçek anahtar/dosya/uç nokta yok.
- `R/helpers_release_evidence.R` (Faz 3 yeni saf okuyucu) +
  `test-release-evidence-behavior.R`.
- Adversarial: `test-adversarial-hostile-input-behavior.R` (traversal/bidi/markdown/
  görsel kartı XSS).

İKİ CERRAHİ SERTLEŞTİRME (regresyon koruması var, geri alma):
- `mergen_sanitize_markdown_links` artık vbscript: ve data:text/html link
  protokollerini de nötrler (javascript: davranışı korunur; data:image/http/https
  etkilenmez).
- `utils_upload_validator` `.upload_has_bidi_control` ile bidi-override (U+200E/F,
  U+202A-E, U+2066-9) dosya adlarını reddeder (Türkçe etkilenmez).

GOTCHA — secret-leak contract: test fixture'larında `api_key = "..."` değeri 24+
karakter olursa secret tarayıcı (`api[_-]?key\s*=\s*['"][...]{24,}['"]`) yakalar;
kısa yer tutucu kullan.

Doğrulama bu container'da (R 4.6.0): `ai_validate.sh full --boot-smoke` TAM geçti
(full testthat suite 130.8s passed, shiny boot passed, app source smoke passed);
browser UX smoke SKIPPED (browser yok), DB/SSO/SQL-Server Türkçe encoding NOT run.

Kalan yüksek değerli untested kümeler `.ai/phase-2-to-9-5-progress.md` sonunda
listelidir (sendMessageInit, ssoAuthServer, chat_add_message/simulate_streaming,
call_llm_worker, deep_analysis/pk_analysis service-bound, claude_code streaming).

---

# PROMPT — Behavioral test coverage, session 4 (deep runtime + service-bound logic)

TASK: Continue eliminating the **"Module / runtime-logic test coverage"** weakness in this
R/Shiny repo (MERGEN Bilge) by adding MANY focused, deterministic, OFFLINE behavioral tests under
`tests/testthat/`. Quantity matters, but every test must assert REAL input→output behavior — no
"function exists" tests, no snapshot fluff. Comments and `test_that` descriptions MUST be in Turkish
with proper Turkish characters (ç ğ ı İ ö ş ü) — never Latinize them.

Read `CLAUDE.md` first — it is the binding operational guide; follow every contract exactly
(additive-only, surgical bug-fix-with-test, source order, encoding, no heavy/browser/CDN deps).

## BRANCH / PR RULES (read carefully)
- Do **NOT** push to `claude/keen-newton-Gi2j1`, `claude/modest-franklin-9rRWC`, or any prior session
  branch, and do **NOT** touch PR #441.
- Develop on **your own session's freshly-assigned branch** (the harness assigns one — use it as-is).
  If for some reason no branch is assigned, create a brand-new one (e.g. `claude/test-coverage-s3-*`).
- When you finish, **open a NEW pull request** for your fresh branch. Commit messages in Turkish.

## CONTEXT — what the LATEST session (`claude/sharp-brown-inTxI`) added (do NOT redo)
- **NEW FEATURE: admin documentation viewer** ("Yönetici Paneli > Dokümantasyon").
  Pure helper `R/helpers_admin_documentation.R` + module `R/module_admin_documentation.R`
  + `www/css/admin_documentation.css` + `www/js/admin_documentation.js`. Renders
  allowlisted repo docs (README/RUNBOOK/RENV_LOCK_STATUS/ai_rehber/docs/*; CLAUDE.md &
  AGENTS.md excluded) as safe rich HTML with a TOC. Renders via
  `commonmark::markdown_html` directly THEN a tag-whitelist output sanitizer (NOT
  `render_safe_markdown_html`, which pre-escapes `<`/`>` and would corrupt R code
  `x <- 1`). Fast risk-scan (`admin_doc_html_has_risk`) skips the expensive tokenize
  for clean docs (240 KB doc: 7.8 s -> 0.42 s).
- **3 behavioral test deliverables (174 assertions total, 0 fail/0 warn/0 skip,
  standalone + batch):**
  - `test-admin-documentation-behavior.R` (135): registry/allowlist, CLAUDE/AGENTS
    exclusion, path safety (unknown/`..`/absolute -> ""), UTF-8 Turkish, code(`<-`)/
    table/list render, XSS boundary (script/iframe/on*/javascript: neutralized — direct
    `admin_doc_sanitize_html`/`_html_has_risk`/`_clean_attributes`/`_clean_one_tag`/
    `_extract_toc` AND via render), TOC anchors + Turkish ASCII slug + uniqueness, all-10-docs
    render, UI builders (`admin_doc_card_list_ui`/`_toc_ui`/`_build_content_ui`),
    `testServer` (group switch / doc select / unknown-id reject / refresh toast).
  - `test-source-manifest-read-parse-behavior.R` (19): `source_manifest_read_file_with_encoding`
    (BOM strip, **CRLF/CR -> real LF** — proves no literal "n" corruption + parses) and
    `source_manifest_try_parse_file` (valid->TRUE, CRLF-valid->TRUE, syntax->stop). Temp
    files via `writeBin(charToRaw(...))` for exact bytes.
  - `test-server-runtime-contracts-behavior.R` (20): `is_server_runtime_context`,
    `.server_runtime_require_context`/`_require_values`/`_require_functions`/
    `_invoke_auth_ready_callback` + `.server_runtime_require_named_functions`/
    `_require_environment` (pure boot-contract guards; Turkish error + owner label).
- **GOTCHAS confirmed this session:** the doc-viewer refresh observer is
  `observeEvent(input$refresh_analytics, ignoreInit=TRUE)` -> a SINGLE `setInputs` is
  consumed as init; use PRIME-THEN-SET. `commonmark::markdown_html` passes raw HTML
  through (no safe arg) -> sanitize the OUTPUT. Turkish `tolower("I")` -> "ı" -> for
  ASCII slugs transliterate then `chartr`, never `tolower`. Untested top-level fn
  count is now ~73 (admin_doc internals + manifest IO + runtime-contract guards covered).

## CONTEXT — what session `claude/beautiful-goodall-8yK70` added (do NOT redo)
- **DOCX async clobber FIXED** in `R/module_file_preview.R` (inline `docx_preview_seq`
  reactiveVal guard on the large-DOCX `%...>%`/`%...!%` callbacks) +
  `test-file-preview-docx-async-clobber-behavior.R` (testServer; `future::future`
  stubbed via `local_mocked_bindings(.package="future")` returning a manually-resolvable
  `promises::promise`; NON-EXISTENT datapath → `file.info()$size` NA → async branch
  without a 10 MB fixture; proven fails-before/passes-after).
- **6 new behavioral files (~78 assertions, 0 fail/warn/skip, standalone + batch):**
  - `test-llm-call-retry-behavior.R`: `call_llm_with_retry` (stub `call_local_llm` +
    `Sys.sleep`).
  - `test-sso-der-tlv-behavior.R`: `.sso_der_length`/`.sso_der_tlv`/`.sso_der_integer`
    (deterministic DER bytes).
  - `test-file-store-mutation-helpers-behavior.R`: `.file_store_drop_stale_entries`/
    `.file_store_apply_rehydrated_paths` (stub `.file_store_mutate_index` over an
    in-memory index; real `normalize_for_path_compare` via `helpers_files_path.R`).
  - `test-sidebar-user-panel-server-behavior.R`: `mb_sidebar_theme_switch`,
    `mb_sidebar_handle_logout_event`, `mb_sidebar_user_panel_server` (moduleServer
    testServer wrapper; badge render states + logout observer).
  - `test-claude-runtime-source-dir-behavior.R`: `resolve_claude_runtime_source_dir`.
  - `test-get-user-profile-from-db-behavior.R`: `get_user_profile_from_db` (DBI-mocked
    WHERE routing + visible/technical normalization).
- **Fixed a PRE-EXISTING red contract test**: `test-file-resolution-security-contract.R`
  (the "MCP resolver mutlak path" test) grepped the stale string `"Absolute path
  argument ignored"`; production was strengthened to `"Absolute path argument
  rejected"` (+ `ok=FALSE` + Turkish error). Re-anchored to `is_abs` + "Mutlak dosya
  yolu kabul edilmez" (stable behavior, not a debug-log string).
- **NEW GOTCHAS (this session):**
  - **`logger` is NOT installed in base cloud** → sourcing `config_logging.R` auto-SKIPs
    the test (`{logger} is not installed`). Install it from RSPM first if you must, OR
    avoid sourcing it. I DROPPED a `log_error_with_context` test: capturing the
    interpolated message via a `log_error` stub needs `glue(.envir=parent.frame(N))`
    and the correct `N` differs between a direct call vs nested-in-`test_that` —
    a fragile frame count that passes on Linux but would fail on the VM. Do NOT ship it.
  - **Turkish `toupper` is locale-dependent** — assert a locale-independent marker
    stub (e.g. `"VIS:"` prefix), not an uppercased Turkish string.
  - `future::future({...})` is mockable with `local_mocked_bindings(future = stub,
    .package="future")` returning a `promises::promise` whose executor pushes
    `resolve/reject` to a queue; never force the expr; drain with a bounded
    `while(!later::loop_empty()) later::run_now(timeout=0)`.
  - MCP/health `getwd()`-relative fallback guards do NOT break any isolated test —
    do not touch them.

## CONTEXT — what session 5 (`claude/exciting-einstein-JGkKQ`) added (do NOT redo)
- **Vision finished** (config + capability-primary kill-switch): `R/helpers_vision_model_capabilities.R`
  (`parse_vision_models_env`, `apply_vision_model_capabilities`) covered by
  `test-vision-model-capabilities-behavior.R`; multimodal `image_url` serialization through the REAL
  `call_local_llm` (httr) + `call_local_llm_sse_worker` (curl) covered by
  `test-vision-llm-payload-serialization-behavior.R`; `test-vision-context-behavior.R` updated for
  default-ON gating. See the eliminate-weaknesses prompt for full details.
- **7 NEW behavioral files (~290 assertions, 0 fail/0 warn standalone + batch):**
  - `test-claude-code-document-builders-behavior.R`: `build_claude_code_document_prompt`,
    `build_claude_code_document_inline_payload`, `build_claude_code_document_summary_messages`,
    `write_claude_code_document_manifest`.
  - `test-send-message-lifecycle-helpers-behavior.R`: `mergen_clear_welcome_for_send_message`,
    `mergen_prepare_send_message_chat` (defer/DB branches), `mergen_prepare_mcp_session_files`
    (non-mcp_excel + no-files branches).
  - `test-deep-analysis-context-builder-behavior.R`: `build_deep_analysis_context`.
  - `test-mcp-tools-parse-behavior.R`: `parse_tool_calls_from_text`, `get_mcp_tools_prompt`,
    `get_openai_tools` (full MCP chain source-once into globalenv, guarded).
  - `test-claude-code-plugins-server-behavior.R`: `claudeCodePluginsServer` + `refresh_local_plugins`
    via `testServer` (real plugin scan).
  - `test-ai-expert-db-fetch-behavior.R`: `fetch_user_last_login`, `fetch_recent_user_prompts`,
    `fetch_user_work_context` (DBI-mocked).
- **NEW GOTCHAS (session 5):**
  - `claudeCodePluginsServer`/`scan_local_plugins()` resolves the plugin dir via
    `resolve_app_root()` → `shiny::getShinyOption("appDir")` FIRST. In `testServer` that points
    elsewhere, so set `shiny::shinyOptions(appDir = repo_root)` (with restore) inside the expr or the
    scan returns 0 plugins. Deps: source `helpers_claude_code_path_policy.R` +
    `config_claude_code_plugins.R` + `helpers_claude_code_plugins.R` (path_policy provides
    `cc_policy_path_inside_roots`).
  - `parse_tool_calls_from_text` requires the FULL MCP chain (context→bootstrap→table_readers→
    file_resolver→schema→basic→chart→analyze→tools) because `helpers_mcp_tools.R` bootstrap
    VALIDATES all are loaded (`stop()` otherwise). A `<tool_call>{json}</tool_call>` legitimately
    matches BOTH the block path and the inline-JSON path → 2 entries (assert real behavior, not count=1).
  - `get_openai_tools()` returns `list(tools = list(<defs>))` (named, wrapped) — access `out$tools[[i]]$type`.
  - Functions called UNQUALIFIED that belong to non-attached packages (e.g. `removeUI` from shiny when
    shiny isn't `library()`'d) cannot be intercepted by `local_mocked_bindings(.package=...)`; assign the
    stub directly into the helper's sourced env (`env$removeUI <- ...`).
  - **CRLF + non-UTF-8-locale = mojibake:** any R `readLines()+writeBin` rewrite of a Turkish/CRLF file
    MUST run with `LANG=C.UTF-8 LC_ALL=C.UTF-8`; otherwise Turkish bytes become literal `<c4><b1>` text.
    Verify with `grep -c '<c3>\|<c4>\|<c5>' file` == 0 and a small `git diff --stat`.

## CONTEXT — what the LATEST session (`claude/exciting-knuth-pTGt1`) added (do NOT redo)
- **Vision feature** `R/helpers_vision_context.R` + send-message `none`-branch wiring (config-gated,
  OFF by default). Covered by `test-vision-context-behavior.R` (pure helpers, none-branch ON/OFF,
  multimodal builder, image-unreadable fallback, `toJSON` round-trip). See the eliminate-weaknesses prompt.
- **3 new behavioral files, ~65 assertions (0 fail/0 warn, standalone + batch):**
  - `test-claude-code-runtime-path-pure-behavior.R`: `is_windows_single_slash_network_path` (non-Windows),
    `.cc_runtime_workdir_token`, `.cc_runtime_workdir_reusable`.
  - `test-health-formatters-path-behavior.R`: `health_is_storage_path_id`, `health_as_windows_explorer_path`.
  - `test-ai-expert-prompt-builders-behavior.R`: `get_ai_expert_generation_config`,
    `build_ai_expert_system_prompt`, `build_ai_expert_user_context` (DB off via `include_recent_prompts=FALSE`).
- Re-ran the untested-function scan: **104** top-level fns still unreferenced by name. Highest-value NOT-yet-done
  clusters for NEXT session (verify 0-ref first): admin `*_outputs` renderers (genel_bakis, yz_performans,
  geri_bildirim_genel, sohbet_kalitesi, zaman_analizi, gelismis_analizler, yanit_analizi) via `testServer`;
  `helpers_destek_database` (mock DB); `helpers_deep_analysis` builders; `helpers_claude_code_documents`
  builders (`build_claude_code_document_prompt`/`_inline_payload`/`write_*_manifest`); `helpers_send_message_*`
  (`mergen_prepare_mcp_session_files`, `mergen_prepare_send_message_chat`, `mergen_clear_welcome_for_send_message`);
  `module_*` servers via `testServer` (`apiKeyServer`, `claudeCodePluginsServer`, `ssoAuthServer`,
  `quickActionsInit`); `helpers_mcp_tools` (`get_openai_tools`, `parse_tool_calls_from_text`).
- Did a full concurrency re-audit (PRIORITY 1) — re-confirmed clean; no new bug. Did NOT manufacture a fix.

## CONTEXT — what sessions 1, 2 & 3 already did (do NOT redo)
- ~140+ `tests/testthat/test-*-behavior.R` / `-contract.R` files already exist.
- Session 2 added 23 behavioral files (~442 assertions) covering previously file-untested modules and
  the easy **pure top-level** helpers (file_manager_attach_client/table_runtime, stt, chartlab,
  image_generation, startup_screen, ai_expert, admin_hata_analizi; plus user_identity, music URL
  encode, .db_chat_*, messaging, version-history resolver, sidebar initials, welcome builders,
  followup flag, readFileContentToString, health_formatters, validate_required_packages,
  workdir_snapshot normalize, config_logging resolvers, claude_code format/thinking).
- Session 2 surgical bugs (do NOT reintroduce): `module_chartlab make_id` 32-bit `as.integer`
  overflow → `sprintf("%.0f", ...)`; `.db_chat_as_numeric_timestamp` `as.POSIXct("garbage")` error →
  `tryCatch(..., error = NA)`.
- **Session 3 (branch `claude/confident-wright-9crdA`) added 10 behavioral files (~165 assertions)** and
  several fixes. Already COVERED (do NOT redo): file_manager_session_registry (`.fm_registry_chr`,
  `fm_session_registry_entry`, `fm_normalize_session_registry_path`, register/unregister),
  config_file_store_listing_helpers (`.file_store_deduplicate_rows`/`_lifecycle_key`/`_index_record_row`/
  `_list_user_files_relaxed`/`_file_size_safe`/`_merge_same_user_filesystem`/`_user_dir_paths`),
  `.normalize_user_session_id`, `.mb_feature_api_key_scalar`, `.fm_context_chr`,
  `llm_worker_format_single_tool_result` (all 6 branches), helpers_admin_hata_analizi UI builders
  (`admin_ha_overview_ui`/`_oncelik_ui`/`_detay_ui`/`_zaman_ui`), config_ui_assets tag builders
  (`ui_asset_css_tag`/`script_tag`/`flatten_groups`/`css_tags`/`js_tags`/`validate_js_render_plan`),
  `load_image_descriptions_for_user` (DBI-mocked), `.sanitize_log_value`, and the image/summarization
  stale-request race guard (with `test-async-handler-stale-request-race-behavior.R`).
- Session 3 found/fixed REAL bugs (do NOT reintroduce): (a) two server-side staleness races in
  `server_handler_image_generation.R` and `server_handler_summarization.R` (async callbacks now use
  `mergen_is_current_request`); (b) `module_startup_screen.R` skip-intro path was missing the
  `updateNeuralColor` send that the experience-mode path has → added (persona neural tint on skip);
  (c) `helpers_claude_code_documents.R` extractor fallback guard made working-directory-independent;
  (d) 3 behavior tests sourced the wrong helper after the api-model tool-runtime split — they now
  source `helpers_api_model_tool_runtime.R` so they pass standalone.
- **Session 4/5 (branch `claude/clever-carson-fV8c3`) added 9 behavioral files (~190 assertions)** plus
  fixes. Already COVERED (do NOT redo): UI builders `historyUI`/`savedChatsUI`/`imageGalleryUI`/`sttUI`/
  `chartLabUI`/`destekHataBildirUI`/`settingsKisiselUI`/`healthUI` + `history_accessible_date_range_input`
  (aria-labelledby) + `health_source_optional` (`test-module-ui-builders-behavior.R`); api-key-choice
  modal builders `api_key_choice_request_url`/`.api_key_choice_personal_card`/`_corporate_card`/
  `api_key_choice_modal_dialog` + `llm_worker_extract_preview_df` (Turkish-name tolerance)
  (`test-api-key-choice-modal-builders-behavior.R`); `admin_users_outputs` (highcharter series + empty-data
  + DT) (`test-admin-users-outputs-behavior.R`); `push_followup_update` + `update_messages_after_bulk_deletion`
  guard (`test-chat-runtime-followup-push-behavior.R`); `update_sso_fields` (DBI-mocked SSO write boundary)
  (`test-update-sso-fields-behavior.R`); `normalize_claude_code_text_files`
  (`test-normalize-claude-code-text-files-behavior.R`); the non-streaming LLM stale-request race
  (`test-nonstreaming-handler-stale-request-race-behavior.R`); the AI Expert page-guidance stale-speech
  guard (`test-ai-expert-page-guidance-stale-behavior.R` — note the `aiExpertHandlersInit` testServer
  WRAPPER pattern: `library(promises)`+`library(shiny)`, source `utils_common.R`+`helpers_ai_expert.R`,
  stub `tracked_future_promise` by `task_type`, mock `shinyjs::delay/runjs`, PRIME-THEN-SET `input$tabs`);
  image-upload policy (`test-image-upload-allowed-behavior.R`).
- Session 4/5 found/fixed REAL bugs (do NOT reintroduce): (a) non-streaming LLM handler stale-request
  race in `server_llm_response_handlers.R` (onRejected/finally now request-scoped); (b) AI Expert
  page-guidance spoke stale guidance after navigating to a muted page → page-staleness check added;
  (c) `server_runtime_context.R` fallback guard made working-directory-independent (fixed 5 server tests
  in isolation); (d) 8 test files made standalone-runnable (missing `library(shiny)` / moved-helper
  sources); (e) Dosya Yönetimi "saved-but-hidden" upload leak — `execute_bulk_upload` now validates the
  extension before `copy_to_mcp_base`; images are now an allowed type (`fm_image_extensions()`).
- Session 4/5 also added the **renv dependency-lock scaffolding** (`.Rprofile` with a populated-library
  guard, `renv/activate.R`, `tools/renv_snapshot.R`, `docs/dependency-locking.md`, ci-restore fallback,
  `RENV_LOCK_STATUS.md` marker) and merged current `main` (ratchet fully GREEN). Covered by
  `test-renv-lock-contract.R`. The user GENERATED `renv.lock` on the Windows VM (R 4.6.0, ~116 pkgs); it
  is a USER/VM action — never generate it from Linux/cloud. Also added **image inline preview**
  (`module_file_preview.R` via `registerDataObj`); covered behaviorally by `test-image-upload-allowed-behavior.R`.
- **WINDOWS-VM TEST LESSON (critical — cloud masks it):** the renv/image/api-key tests passed on Linux but
  FAILED on the user's Windows VM full suite (passed individually). Causes + fixes now applied: tests that
  scan repo files MUST use the byte-safe reader (`readBin`+`iconv(sub="byte")`+`grepl(useBytes=TRUE)` over
  ASCII anchors), NOT `readLines(encoding="UTF-8")+grepl` over Turkish-commented files; do NOT assert
  `!is.na(iconv(x,"UTF-8","UTF-8"))` on possibly-native-encoded strings; and `.Rprofile`/`tools/renv_snapshot.R`
  are ASCII-only. After a refactor moves a function, update the test's `source(...)` to the new owner
  (main's `_preview.R` split moved `llm_worker_extract_preview_df`). Apply these to EVERY new file-scanning test.
  One KNOWN cloud-only failure remains: `test-runtime-network-boundary-contract.R` (redacted `https://url......./`
  avatar placeholder in `helpers_messaging.R`/`module_sidebar_user_panel.R`, pre-existing on `main`, green on VM).

## STEP 1 — TARGET the remaining UNTESTED logic (the harder, higher-value stuff)
The cheap pure functions are mostly done. What remains is where bugs hide: **nested closures inside
`moduleServer`/`*Init` bodies, Shiny `*_outputs` renderers, and service-bound (HTTP/DB/LLM) helpers.**

Re-scan for genuinely-untested TOP-LEVEL functions (FIXED-string match — `\b` regex breaks on
dot-prefixed names like `.db_chat_*`, so do NOT use it):

```r
rfiles <- list.files("R", pattern="\\.R$", full.names=TRUE)
tfiles <- setdiff(list.files("tests/testthat", pattern="\\.R$", full.names=TRUE),
                  list.files("tests/testthat","helper_bootstrap", full.names=TRUE))
blob <- paste(unlist(lapply(tfiles, readLines, warn=FALSE, encoding="UTF-8")), collapse="\n")
pat <- "^([A-Za-z.][A-Za-z0-9._]*)[[:space:]]*(<-|=)[[:space:]]*function\\("   # column-0 = top-level
for (f in rfiles) {
  fns <- unique(na.omit(vapply(regmatches(readLines(f,warn=FALSE,encoding="UTF-8"),
           regexec(pat, readLines(f,warn=FALSE,encoding="UTF-8"))), function(x) x[2], character(1))))
  un <- fns[nzchar(fns) & !vapply(fns, function(fn) grepl(fn, blob, fixed=TRUE), logical(1))]
  if (length(un)) cat(sprintf("%-44s %s\n", basename(f), paste(un, collapse=", ")))
}
```

Highest-value remaining clusters (verify each is still 0-ref before writing — some may get covered):
- **Admin `*_outputs` renderers** (testServer + stubbed `*_collect_data`/query fns, then read
  `output$...` and assert highcharter series / DT rows). `admin_users_outputs` is now COVERED
  (`test-admin-users-outputs-behavior.R`); REMAINING: `module_admin_genel_bakis admin_overview_outputs`,
  `module_admin_yz_performans admin_ai_perf_outputs`, `module_admin_geri_bildirim_genel admin_feedback_outputs`,
  `module_admin_sohbet_kalitesi`, `module_admin_zaman_analizi`, `module_admin_gelismis_analizler`,
  `module_admin_yanit_analizi`. Pattern proven in `test-admin-users-outputs-behavior.R` and
  `test-admin-hata-analizi-module-behavior.R` (stub helpers in env, read `output$x` JSON, parse with
  `jsonlite::fromJSON` → `$x$hc_opts$series`).
- **helpers_admin_hata_detail_runtime**: `admin_ha_detail_datatable`, `admin_ha_attachment_public_path`,
  `admin_ha_attachment_download_button`, `admin_ha_show_modal` (DT/HTML builders — partly pure).
- **helpers_health_checks** (mock the probe seams): `health_check_disk_free`, `health_check_app_boot`,
  `health_check_db_connection` / `health_check_db_schema` / `health_check_llm_endpoint` /
  `health_check_reasoning_readiness` — these return the structured `health_result(...)` contract; mock
  `get_connection`/`httr` and assert status/severity/remediation fields. Must NOT hit real DB/network.
- ~~**config_api crypto/key-file helpers**~~ — ALREADY COVERED by `test-config-api-key-crypto-behavior.R`;
  do NOT duplicate. `validate_api_key`/`derive_models_url` (nested in `validate_api_key`) still need an
  `httr`-mocked test if you want endpoint-validation coverage.
- **helpers_destek_database** (mock DB): `destek_geri_bildirim_listele`, `destek_hata_bildirim_listele`,
  `destek_hata_durum_guncelle`, ... — `local_mocked_bindings` `get_connection`/`dbGetQuery`/`dbExecute`.
- **helpers_llm_tool_formatters**: `build_excel_digest_json`, `mcp_excel_tool_fallback` (pure-ish).
- **helpers_image_gallery**: `get_image_thumbnail_base64`, `get_chat_title_for_image` (mock DB / temp
  file). NOTE: `load_image_descriptions_for_user` is now COVERED (session 3, DBI-mocked).
- ~~**config_file_store_listing_helpers** `.file_store_*`~~ — COVERED in session 3
  (`test-file-store-listing-helpers-behavior.R`). Do NOT redo.
- **config_sql_loader** `.remove_utf8_bom`, `.sql_has_text`, `.sql_placeholder_text`, `.read_sql_file_text`:
  the file `stop()`s at source time without `query_library` — source `R/library_queries.R` FIRST, or
  `tryCatch(source(...), error=...)` (functions defined before the stop remain in env), then test.
- **module servers via `shiny::testServer`** where logic is reachable: `module_api_key apiKeyServer`,
  `module_claude_code_plugins claudeCodePluginsServer` (+ `refresh_local_plugins`), `module_image_gallery
  imageGalleryServer` (coerce_user_id/empty_images_df/gallery_images_same), `module_performance`
  count/cleanup helpers.
- ~~**UI builders**: `historyUI`/`history_accessible_date_range_input`, `savedChatsUI`, `imageGalleryUI`,
  `healthUI`, `sttUI`, `chartLabUI`, `destekHataBildirUI`, `settingsKisiselUI`, `module_api_key_choice_modal`
  card builders + `api_key_choice_request_url`~~ — ALL COVERED in session 4/5
  (`test-module-ui-builders-behavior.R`, `test-api-key-choice-modal-builders-behavior.R`). Do NOT redo.
  REMAINING UI builders: `module_chartlab` other builders, `adminYanitAnaliziUI`, and the
  `ui_asset_css_tag`/`ui_asset_script_tag`/`ui_asset_flatten_groups` manifest tag helpers (if still 0-ref).

When a function is a NESTED closure (not column-0), test it **through its module** via `testServer`
(returned closures = `session$returned$...`; renderers = read `output$...`). Stub the heavy deps in the
sourced env; never launch the real app/DB/LLM.

## STEP 2 — TECHNIQUES (proven in sessions 1–2; reuse + the new gotchas)
ENV: `export LANG=C.UTF-8 LC_ALL=C.UTF-8`. `highcharter`+`logger` may be missing — install once from RSPM:
`Rscript -e 'options(repos=c(CRAN="https://packagemanager.posit.co/cran/__linux__/noble/latest")); install.packages(c("highcharter","logger"))'`. `officer`/`plotly` may stay absent → guard `skip_if_not_installed`.

ISOLATION: per file `env <- new.env(parent=globalenv()); source(file.path(resolve_repo_root_for_tests(),
"R","X.R"), encoding="UTF-8", local=env)`. `helper_bootstrap.R` auto-loads (`%||%`, `log_*`,
`normalize_character_id`, DB/file-manager helpers, persona data). Put LOCAL stubs in `env`.

PURE fn → call directly. UI builder → `paste(as.character(ui), collapse="\n")`, assert ids/classes/Turkish.
For unqualified `div()/fluidRow()/selectInput()` etc., `suppressMessages(library(shiny))` at file top
(testServer auto-loads shiny; standalone UI calls do NOT).

`shiny::testServer(env$xxxServer, args=list(...), { ... })`: returned value = `session$returned`;
read render outputs as `output$x`. renderUI/renderText come back as CHAR VECTOR → `paste(as.character(.),
collapse="")`. **renderHighchart / renderDT come back as a `json` string** → `jsonlite::fromJSON(
as.character(output$x), simplifyVector=FALSE)$x$hc_opts$series` to assert series names/colors; or grep the
JSON for ASCII tokens (hex colors are safe; Turkish names may be `\u`-escaped — parse instead of grep).
`req()` failure RE-THROWS on read → `expect_error(force(output$x))`.

CUSTOM-MESSAGE CAPTURE: non-module root session → assign `session$sendCustomMessage <- function(type,msg){...}`
before triggering. moduleServer (session is a proxy) → override the ROOT:
`root <- .subset2(session,"parent"); root$sendCustomMessage <- function(type,msg){...}`. `shinyjs::runjs/
addClass` flow through this too — OR mock them via `testthat::local_mocked_bindings(runjs=..., delay=function(ms,
expr) expr, .package="shinyjs")` (the `delay` mock that forces `expr` runs delayed sends immediately).

MOCK `pkg::fn`: `testthat::local_mocked_bindings(POST=fn, status_code=fn, content=fn, add_headers=fn,
timeout=fn, .package="httr")` — intercepts `httr::POST`. Same for `shiny` (`showModal`/`updateCheckboxInput`
reject a plain-list session → mock to no-op) and DB bindings if exported.

OBSERVER DRIVING: MockShinySession defers `observeEvent` and reads the CURRENT input at next flush.
- For a **`once=TRUE`** observer, a SINGLE `session$setInputs(x=REAL)` fires it once reading REAL (do NOT prime
  with a different value — the prime consumes the single fire on the WRONG value).
- For a non-once observer that must re-fire, use PRIME-THEN-SET: `setInputs(x="__p__"); setInputs(x=REAL)`.
- Negative guards ("must NOT call"): use a stubbed-recorder count `==0`; never assert exact fire counts.

NEW SESSION-2 GOTCHAS (save hours):
- Coverage scan: use FIXED-string membership, not `\bname\b` — `\b` fails before a leading `.` and gives
  false "untested" positives for `.dot_prefixed` functions.
- Files with a top-level `stop()` guard (e.g. `config_packages`, `config_sql_loader`): functions defined
  BEFORE the stop survive a `tryCatch(source(...), error=function(e) NULL)` — test them from the partial env.
- `config_logging` prints a one-time `INFO ... Application starting up` via logger at source time — wrap the
  source in `suppressMessages(...)` (it may still reach stderr via `cat`; that's fine, it's not a warning).
- ALWAYS probe the real output before asserting locale/encoding-sensitive behavior: Turkish `toupper`/
  `chartr` is locale-dependent (assert unambiguous ç/ş/ğ/ü/ö + the reliable `İ→i`, avoid `i↔I↔ı`); and e.g.
  `normalize_claude_code_text_file_to_utf8` returns TRUE for already-valid UTF-8 WITHOUT stripping the BOM —
  assert the real contract, not the assumed one.
- `withr::defer(env$fn <- .orig)` to restore env stubs you mutate inside a `test_that`.
- `cat()`-noisy fns → wrap calls in `invisible(utils::capture.output(res <- expr)); res`.

NEW SESSION-3 GOTCHAS:
- **Wrong-source-after-split trap**: a helper may have MOVED files in a refactor. Several tool-mode
  helpers (`get_tool_mode_config`, `resolve_tool_model_for_family`, `build_main_actions_data_from_config`,
  `resolve_deep_thinking_model`) now live in `helpers_api_model_tool_runtime.R`, NOT
  `helpers_api_model_config.R`. If your test sources the old file it passes in the FULL suite (the runtime
  file is loaded by `global.R`) but ERRORS standalone. Before writing a source-guard, `grep -rn 'fn <-
  function' R/` to find the REAL owner. Make tests self-contained for individual runs.
- **Promise/async handlers**: to drive `%...>%`/`promises::then` callbacks, stub the worker
  (`tracked_future_promise`/`call_llm_non_streaming`) to return `promises::promise_resolve(x)` /
  `promise_reject(e)`, then drain with a bounded `while(!later::loop_empty()) later::run_now(timeout=0)`
  loop. Mock `shinyjs::runjs` via `local_mocked_bindings(.package="shinyjs")`. See
  `test-async-handler-stale-request-race-behavior.R`.
- **CRLF files**: many `R/*.R` and `www/css/*.css` files are CRLF. Editing them with an LF-only tool can
  corrupt line endings. Prefer a small R `readLines()/writeLines(..., sep="\r\n", useBytes=TRUE)` script
  for CRLF files; verify with `grep -c $'\r' file` == `wc -l`.
- **FontAwesome 6 icon aliases**: `icon("sync-alt")` renders as `fa-rotate`, `icon("trash-alt")` as
  `far fa-trash-can`. Don't assert the alias name; assert the rendered class or be tolerant.

WARNINGS = FAILURES under the strict runner (`stop_on_warning=TRUE`): every test must be 0 WARN. Watch
`gregexpr(fixed=TRUE, ignore.case=TRUE)`, unguarded `as.integer(...)` (overflow), `as.POSIXct("garbage")`
(errors). If PRODUCTION emits a spurious warning/error on a reachable input, that's a surgical bug-fix
candidate (with a regression test) — see the `make_id` / `.db_chat_as_numeric_timestamp` precedents.

## STEP 3 — IF YOU FIND A REAL BUG
Fix it surgically in the R file with a Turkish comment explaining why; keep the test that proves it. Do not
change runtime behavior otherwise. Respect the maintainability ratchet (`tests/testthat/
test-maintainability-ratchet.R`) — keep near-limit files within budget (collapse a fix to one line if needed,
like `make_id`). Do not weaken/edit existing contract tests.

## STEP 4 — VALIDATE (be honest)
- After EACH new file: `Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-X.R",
  reporter="summary")'` → require 0 FAIL / 0 WARN / 0 accidental SKIP. Run files individually AND as a batch
  (`testthat::test_dir("tests/testthat", filter="...")`) to catch global leakage; always `new.env(parent=
  globalenv())`.
- After any R source edit: `Rscript tests/scripts/parse_sanity_check.R` and
  `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")`.
- IMPORTANT — the FULL strict suite (`tests/testthat.R`) does NOT complete in this cloud checkout due to
  PRE-EXISTING failures unrelated to new tests: missing vendored assets (`www/css/all.min.css`,
  `www/codemirror/*`, `www/lib/threejs/*`) and missing `.Renviron`. Sessions 1–2 proved these fail
  identically on the base commit. Do NOT try to "fix" them; classify as environment/checkout limits.
  Validate your work via per-file + batch runs, not the full suite.

## CONSTRAINTS
Additive only. Preserve Turkish user-facing strings; Turkish + UTF-8 comments/descriptions. No new heavy/
browser/CDN deps (no Playwright/Selenium/shinytest2/chromote). Keep stubs local; isolate with
`new.env(parent=globalenv())`. Never print/log real secrets — use fake key/token fixtures.

## DELIVERABLE
- As many new green `tests/testthat/test-*-behavior.R` files as you can for the remaining runtime/renderer/
  service-bound logic (each 0 fail / 0 warn). Prioritize the admin `*_outputs` renderers, `helpers_health_
  checks` probes (mocked), `config_api` key crypto (round-trip + reject), and `config_file_store_listing_
  helpers` `.file_store_*` transforms.
- Any real bug found → surgical fix + regression test, documented in the PR body.
- Short honest final report: files covered, test-file + assertion counts, bugs found & fixed, and an
  explicit per-file list of anything you could NOT cover offline and why.
- Commit with clear Turkish messages, push to YOUR fresh branch, and OPEN A NEW PR (do not reuse PR #441 or
  any prior session branch).

Begin with STEP 1 (re-scan), show the remaining-function list, then generate tests file by file, validating
each.

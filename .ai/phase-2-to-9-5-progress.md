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

### Oturum: 2026-06-12 — branch `claude/peaceful-ritchie-hvd1y7` (bu oturum)

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

2026-06-12 taramasından, bu oturumda KAPSANMAYANLAR:

- `sendMessageInit` (server_send_message.R) — ağır; testServer + yoğun stub ister.
- `serverInitChatRuntime`, `sessionCacheInit` — testServer ile orta zorluk.
- `ssoAuthServer` (module_sso.R) — SSO akışı; httr/jwt stub'ları ile.
- `chat_add_message`, `chat_simulate_streaming` (helpers_chat_runtime.R) — ağır.
- `call_llm_worker` (helpers_llm_worker.R) — çok ağır; ikinci-pass zinciri.
- `pk_deep_analysis_process`, `find_multiple_queries_with_ai`,
  `execute_single_deep_query` (helpers_deep_analysis.R) — LLM/DB mock ister.
- `pk_analiz_process_request`, `find_best_query_with_ai` (module_proje_kaynak_analizi.R).
- `summarize_file_with_llm`, `handle_file_upload_batch` (helpers_file_pipeline.R).
- `run_claude_code_streaming`, `parse_stream_event` (helpers_claude_code_streaming.R).
- `check_claude_code_status`, `test_claude_code_connection` (processx mock).
- `prepare_claude_code_document_context`, `write_claude_code_document_summary_file`,
  `summarize_claude_code_documents_with_local_llm`.
- `execute_parsed_tool` (helpers_mcp_tools.R) — MCP zinciri source edilerek.
- `gc_scheduler`, `start_gc_scheduler_once` (config_file_store.R) — later mock.
- `.syap_*` kart builder'ları — `test-settings-yapilandirma-ui-id-surface-behavior.R`
  id yüzeyini dolaylı koruyor; doğrudan birim testi düşük öncelik.
- `attach_required_packages`, `ui_asset_zone_get`, `admin_ha_show_modal`,
  `cc_refresh_user_file_manager_after_run`, `cc_bind_claude_code_stream_polling`,
  `mergen_build_send_message_request_callbacks`, `.fm_runtime_is_reactivevalues`,
  `.path_text_encoding_helper_available`, `.mcp_bootstrap_*` — küçük/orta.

## Faz 3 sonraki adımlar

- Helper katmanı bu oturumda eklendiyse: Sistem Durumu (health) sayfasına
  "Release Kanıtı" sekmesi/karti olarak bağlamak (UI wiring) sonraki oturuma.
- Post-deploy smoke durumu ve hata kategorisi/latency özetleri için mevcut log
  formatları incelenmeli (`logs/mergen_*.log` yapısı).

## Doğrulama kanıt sınırı (her oturum geçerli)

- Cloud koşumları VM/DB/SSO/browser/tam-suite kanıtı DEĞİLDİR.
- `renv.lock` asla Linux/cloud'dan üretilmez.
- Tam strict suite cloud checkout'ta önceden var olan ortam eksikleri nedeniyle
  tamamlanmaz (vendored www varlıkları, `.Renviron`); dosya-bazlı + batch
  koşumlarla doğrulanır.

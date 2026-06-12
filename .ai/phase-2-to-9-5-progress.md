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

Bu oturum hedefleri:

1. Faz 2: config_logging sink'leri, server wiring guard'ları, sso_fetch_jwks,
   quickActionsInit + apiKeyServer testServer, rate limiter cluster,
   cc_policy_collapse_dot_segments, admin_doc iç helper'ları,
   mergen_serve_image_data_url.
2. Faz 3: `R/helpers_release_evidence.R` (saf artifact okuyucu) + manifest
   wiring + davranış testleri.
3. Faz 4: `docs/feature-ownership-map.md`.
4. Faz 5: `test-adversarial-hostile-input-behavior.R` (bidi dosya adları,
   markdown javascript: link, split-tag, admin-doc svg/math/nested-splice,
   %2e%2e ve UNC-child yol vektörleri).

(Oturum sonunda sonuçlarla güncellenecek.)

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

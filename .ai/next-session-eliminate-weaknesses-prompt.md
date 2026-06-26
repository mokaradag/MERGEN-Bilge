# PROMPT — Eliminate ALL remaining weaknesses in MERGEN Bilge (fresh branch)

You are continuing hardening work on the **MERGEN Bilge** R/Shiny app. Your mission this session is to systematically and thoroughly eliminate as many remaining weaknesses as possible — correctness, concurrency, stale-request races, test coverage, test isolation, production robustness, and UX consistency — while preserving every UX and contract guarantee.

Read `CLAUDE.md` FIRST and in full. It is the binding operational guide and overrides default behavior: surgical changes only, additive-only tests, Turkish comments with proper Turkish characters (ç ğ ı İ ö ş ü — never Latinize), no CDN/heavy/browser dependencies, respect source-manifest order, encoding boundaries, and the maintainability ratchet.

Also read `.ai/next-session-test-coverage-prompt.md` for the behavioral-test technique catalog and the up-to-date "already covered, do NOT redo" list.

---

## LATEST SESSION RESULTS — Codex (2026-06-26)

## JUST COMPLETED — do NOT redo
- File Manager toplu yükleme runtime ayrımı tamamlandı: `R/module_file_manager.R` içindeki `execute_bulk_upload` dosya başı doğrulama/kalıcılaştırma/indeks yazma döngüsü `R/helpers_file_manager_upload_runtime.R::fm_process_bulk_upload_batch()` sınırına taşındı.
- Önce/sonra: `R/module_file_manager.R` 642/10 → 550/9; yeni helper 118/1. Maintainability 100/100; 800+ R dosyası yok; global max 678.
- Korunan davranış: duplicate uyarısı, SSO/auth-ready gate, `validate_uploaded_file()` + `fm_normal_allowed_extensions()`, `copy_to_mcp_base()`, persisted size, `ensure_persisted_upload_index()`, `process_uploaded_file(..., generate_message = FALSE)`, Türkçe dosya adı ve başarı mesajı akışı.
- Yeni/updated tests: `test-file-manager-state-runtime-contract.R`, source manifest contract/sections, maintainability ratchet. Budgetler: `module_file_manager.R` 560/10; upload helper 140/3.
- Validation: parse sanity PASS (865 files); focused File Manager state/runtime contract PASS; File Manager module policy wiring PASS; source-manifest contract PASS; source-manifest-sections contract PASS; maintainability_report PASS (100/100; module_file_manager 550/9); maintainability-ratchet PASS; frontend_complexity_doctor PASS (R-only, unchanged frontend risks); seam_doctor PASS/OK; `bash tools/ai_validate.sh quick` PASS (failed_steps=0, skipped_steps=0, artifact `artifacts/ai-validation/20260626-125434/summary.json`). `bash tools/ai_validate.sh full --boot-smoke` was attempted and FAILED before boot-smoke in full testthat suite due to existing Shiny destroyed-reactive isolation failures in `test-chat-actions-behavior.R` and `test-image-gallery-observers-behavior.R`; artifact `artifacts/ai-validation/20260626-125941/summary.json`. Not VM/DB/SSO/real-browser/SQL Server proof.

## CURRENT BEST NEXT TARGETS
1. Frontend Deep Space: `www/js/deep_space_intro.js` remains the largest app JS file (~820/32 in discovery before this R-only package). Split scene/shader/solar/UI/lifecycle only if preserving local Three.js/offline asset order.
2. Frontend AI Expert: `www/js/ai_expert_manager.js` remains dense (~802/45). Prefer handler-density extraction (idle scheduling, Shiny bindings, subtitle/audio coordination).
3. R-side fallback: `R/helpers_claude_code_process.R` only if fresh maintainability reports show it as a real top risk. Do not chase `module_admin_yanit_analizi_outputs.R`; it is a documented low-priority flat renderer.

## GOTCHAS DISCOVERED
- File Manager upload validation still intentionally resolves `validate_uploaded_file` from `globalenv()` because that matches the existing runtime guard. Tests that exercise the helper must bind/stub it in `globalenv()` and restore it.
- New R source file means `source_manifest_sections` total count and file-manager helper section count must stay aligned.
- Do not redo File Manager delete-runtime split, state-runtime split, upload-runtime split, display-name normalization, refresh guard, or attach-client split.


## LATEST SESSION RESULTS — Codex (2026-06-25, File Manager delete-runtime split)

Shipped a **behavior-preserving File Manager package**. Do NOT redo this slice:

- **What/why:** `R/module_file_manager.R` was the top R maintainability candidate after the documented low-priority flat admin renderer. The risky physical-delete / index-cleanup branch was still inline in the Shiny observer.
- **Extraction:** new `R/helpers_file_manager_delete_runtime.R` owns `fm_delete_persisted_file_artifacts()`: direct persisted/datapath/path deletion, `resolve_uploaded_file()` fallback, user-folder basename fallback, and `mergen_remove_from_index()` cleanup. The module now stays focused on Shiny state/UI side effects and delegates physical lifecycle cleanup.
- **Wiring:** `R/config_source_manifest.R`, `R/bootstrap_source_manifest.R`, and `tests/testthat/helper_bootstrap.R` now load `helpers_file_manager_delete_runtime.R` after storage and before state runtime. Source-manifest contract updated.
- **Tests:** new `test-file-manager-delete-runtime-behavior.R` covers Turkish display-name direct deletion, index cleanup, and resolve-before-fallback ordering with deterministic temp files and injected dependencies.
- **Ratchet tightened:** `R/module_file_manager.R` 677/11 → 642/10; near-limit budget tightened to 650/11. New delete helper budget locked at 90/4. Maintainability remains 100/100, global max still 678 (`module_admin_yanit_analizi_outputs.R`).
- **VALIDATION (Linux/cloud):** focused delete test PASS; source-manifest contract PASS; parse sanity PASS (864 files); maintainability_report PASS (100/100, module_file_manager 642/10); maintainability-ratchet PASS; seam_doctor OK; frontend_complexity_doctor rerun unchanged/no structural frontend issue. `bash tools/ai_validate.sh quick` PASS; failed_steps=0, skipped_steps=0; artifact `artifacts/ai-validation/20260625-201131/summary.json`. NOT VM/DB/SSO/real-browser proof.
- **BEST NEXT TARGETS:** Frontend Deep Space (`www/js/deep_space_intro.js` 820/32) or Frontend AI Expert (`www/js/ai_expert_manager.js` 802/45). R-side next options: `helpers_claude_code_process.R` (665/20) only if reports make it top risk; `module_admin_yanit_analizi_outputs.R` remains low-priority flat renderer.

---

## LATEST SESSION RESULTS — `claude/tender-keller-vasw96` (2026-06-24, true-SSE worker-globals split)

Shipped a **behavior-preserving extraction of the global ratchet pin**
`R/server_handler_true_streaming.R` (681 → 655). Surgical, additive. Do NOT redo:

- **What/why:** this file is one tightly-coupled streaming state machine over a shared
  mutable `stream_env`; the inner closures can't be hoisted without threading a huge
  context (high risk on the sensitive SSE path). The ONE clean, behavior-preserving
  extraction is the ~35-line `tracked_future_promise(..., globals = list(...))`
  worker-export list — flat, declarative, mostly global symbols, AND a CLAUDE.md-protected
  contract (reasoning delta / stop-file / model request-override helpers must stay
  visible worker-side).
- **Extraction:** new pure factory `mergen_true_streaming_worker_globals()` in
  **`R/helpers_llm_true_streaming_worker.R`** (62/1). 31 names moved BYTE-IDENTICAL
  (4 request-scoped args + 25 helpers + `%||%` + `api_config`); handler now calls
  `globals = mergen_true_streaming_worker_globals(chat_history_for_sse, settings_for_sse,
  stream_file_for_sse, stop_file_for_sse)`. GOLDEN proof: stubbed-env factory output ==
  original 31 names in the same order; arg passthrough TRUE.
- **Wiring:** manifest `server_handlers_send_message` 9→10 (helper BEFORE handler);
  bootstrap order rule `helpers_llm_true_streaming_worker.R → server_handler_true_streaming.R`;
  seam `sohbet_llm_akis` guard_tests 8→9; section contract total 282→283.
- **Tests:** new `test-true-streaming-worker-globals-contract.R` (structural split + 31-name
  worker-export contract + arg passthrough). REPOINTED two existing tests that grepped the
  handler for the moved names → now assert the new owner: `test-sse-worker-export-contract.R`
  (+handler-delegation check) and `test-llm-reasoning-request-overrides.R:221`. GOTCHA:
  both of those grep the *file text* for `apply_model_request_overrides = ...` etc., so any
  globals-list move MUST repoint them or they fail.
- **Ratchet TIGHTENED:** global `MERGEN_TEST_MAX_FILE_LINES` 681 → **678** (new pin
  `module_admin_yanit_analizi_outputs.R` 678). Budgets: handler 660/18, helper 80/1.
- **VALIDATION (Linux/cloud, R 4.6.0, logger + placeholder env):** `ai_validate full
  --boot-smoke` FULL PASS — app source smoke passed, **full testthat suite passed
  (159.4s)**, shiny boot passed, browser SKIPPED; failed=0, skipped=0
  (`artifacts/ai-validation/20260624-121349/summary.json`). parse_sanity 858; seam_doctor
  OK; maintainability 100/100 max 678. NOT VM/SSO/DB/real-browser/live-SSE proof.
- **GOTCHA:** the factory references ~25 global functions + `api_config` BY NAME; they
  resolve at CALL time (runtime), so the factory must only be called where those globals
  exist (the handler's runtime). Tests stub all of them in an isolated env before sourcing.
- **BEST NEXT TARGETS:** frontend
  `www/js/deep_space_intro.js` (820), `www/js/ai_expert_manager.js` (802/45 — within budget,
  split-then-tighten). `module_admin_yanit_analizi_outputs.R` (678) is a flat single-function
  renderer list → low priority.

---

## LATEST SESSION RESULTS — `claude/tender-keller-vasw96` (2026-06-24, package 2: Bilge Yolaç doküman summary split)

Same branch/session as the post-deploy package below; after the user said "continue"
this session shipped a **second** behavior-preserving structural split. Do NOT redo:

- **Split `R/helpers_claude_code_documents.R` 679/17 → 407/10** by moving the document
  SUMMARY orchestration (`resolve_claude_code_document_detail_level`,
  `write_claude_code_document_summary_file`, `build_claude_code_document_summary_messages`,
  `summarize_claude_code_documents_with_local_llm`) verbatim into NEW
  `R/helpers_claude_code_document_summary.R` (281/7). Document CONTEXT prep
  (manifest/inline-payload/prompt/prepare-context) + the shared
  `write_claude_code_utf8_bom_text_file()` BOM writer STAY in documents.R.
- **Why this and NOT the global pin:** the global `MERGEN_TEST_MAX_FILE_LINES` pin is
  `R/server_handler_true_streaming.R` (681) — but that file is ONE big reactive
  function (inner closures over stream_env/values/session + an inline worker-globals
  list that CLAUDE.md forbids relocating). Splitting it changes closure semantics on
  the live-SSE path and is only VM-provable → high risk / low cloud value. Prior
  sessions deliberately left it alone; this split instead reduced the 2nd-largest file
  with the proven verbatim-move pattern. **Global pin stays 681 (unchanged).**
- **Byte-preserving extraction:** done with an R script copying exact line ranges
  (lines 531–533 mix tabs/spaces; retyping would drift). BOM writer kept in documents.R
  because `R/helpers_claude_code_run_lifecycle.R` also uses it (via `exists()` guard).
  `summarize_...` runs in run_lifecycle's `tracked_future_promise` worker via AUTOMATIC
  globals detection — moving it between sourced files does NOT change worker resolution
  (globals resolve in globalenv at runtime, file-independent).
- **Wiring:** manifest `claude_code_helpers` documents → **summary** → run_lifecycle;
  bootstrap order rules documents→summary, summary→run_lifecycle; section count n=26→27,
  total runtime 281→282.
- **Tests:** NEW `test-claude-code-document-summary-refactor-contract.R` (5 tests: split
  + behavior + manifest order + documents.R no longer owns the 4 fns + BOM writer stays
  + tightened budget summary<320/≤9, documents<430/≤12). Updated 3 behavior tests to
  source the summary file (detail-level, document-builders, document-orchestration).
- **Ratchet NOT loosened.** maintainability 100/100, max file 681, max fn 24 (unchanged).
  documents.R left the near-pin band; new file locked by the split-contract budget.
- **VALIDATION (Linux/cloud, R 4.6.0):** `ai_validate full --boot-smoke` FULL PASS:
  app source smoke passed, **full testthat suite passed (159.0s)**, shiny boot passed,
  browser smoke SKIPPED; failed=0, skipped=0
  (`artifacts/ai-validation/20260624-112452/summary.json`). parse_sanity 856; seam_doctor
  OK (`bilge_yolac` runtime 33→34, no orphan); maintainability 100/100 max 681. NOT
  VM/SSO/CLI/real-browser proof — the document-summary worker flow is VM-only-provable.
- **BEST NEXT TARGETS:** `R/server_handler_true_streaming.R` (681, global pin — only on
  the VM with a maintainer, sensitive SSE closures), `R/helpers_claude_code_process.R` (665/20, function-count
  pressure). Frontend `www/js/ai_expert_manager.js` (802/45, within budget →
  split-then-tighten). GOTCHA: the maintainability fn metric counts inline
  `= function(` (e.g. `error = function(e)`) — `summarize`'s tryCatch added inline fns,
  so summary file is 7 not 4; budget accordingly.

---

## LATEST SESSION RESULTS — `claude/tender-keller-vasw96` (2026-06-24, post-deploy smoke artifact flow)

This session **completed the post-deploy smoke evidence flow** (the documented Faz-3
carryover "üretici henüz yok"). Additive + one health UI card; behavior-preserving.
Do NOT redo:

- **Gap closed:** `tests/scripts/run_post_deploy_smoke.R` + the pure evaluator
  `tests/scripts/helpers_post_deploy_smoke.R` already existed, but the gate only
  `cat()`-printed and `stop()`-ed — it wrote **no machine-readable artifact**, and
  `R/helpers_release_evidence.R` had readers for vm-evidence + ai-validation but
  **none for post-deploy smoke**. Now uçtan uca: producer → secret-safe JSON →
  pure reader → Sistem Durumu UI.
- **Producer:** new pure `mergen_post_deploy_smoke_artifact_record()` in
  `helpers_post_deploy_smoke.R` (self-contained, no `%||%` — the contract test
  sources it standalone). `run_post_deploy_smoke.R` writes
  `artifacts/post-deploy-smoke/<timestamp>/post-deploy-smoke.json` **before** `stop()`
  (so fail/degraded runs also leave evidence), wrapped in `tryCatch` + redactor.
  Mandatory `does_prove`/`does_not_prove` honesty fields; only check-ids + status
  counts + overall metadata (no raw log/env/secret).
- **Reader:** new `release_evidence_post_deploy_smoke_summary()` in
  `R/helpers_release_evidence.R` (whitelisted fields, not_found honesty) wired into
  `release_evidence_overview()` as `post_deploy_smoke`. helpers_release_evidence
  21 → 22 fns (deliberately AVOIDED `tryCatch(error=function)` closures because the
  report metric counts `= function(` — a parsed-JSON `$` access never errors, so
  direct access keeps the file off the global 24-fn ceiling; it briefly hit 24
  before I removed the two closures).
- **UI:** new `.health_release_post_deploy_card()` + a "Dağıtım Sonrası Duman Testi"
  card + a metric tile in `R/module_health_release.R` (5 → 6 fns). not_found shows
  "Bulunamadı", never success; artifact path NOT rendered (secret-safe).
- **Tests:** extended `test-post-deploy-smoke-contract.R` (record-helper behavior +
  artifact-writer token contract), `test-release-evidence-behavior.R` (fixture +
  reader + overview key), `test-health-release-ui-behavior.R` (card render +
  secret-safe + not_found). No NEW test file → no seam-registry/section-count churn
  (the seam guard_tests is a curated subset; these test files were already not in it).
- **Ratchet NOT loosened.** maintainability 100/100, max file 681, max fn 24
  (unchanged). No manifest/source-order/zone change (scripts + 2 runtime helpers +
  tests + docs only).
- **Codex review follow-up — round 1 (3× P2):** (1) redacting the *serialized* JSON
  could corrupt it → first added `mergen_post_deploy_smoke_redact_json_safe`
  (redact-if-valid-else-original) — SUPERSEDED in round 2, see below. (2) UI ignored
  `should_fail`, so the no-checks case (`overall="unknown"` + `should_fail=TRUE`) showed
  neutral "Bilinmiyor" → now forced to critical "Başarısız" (tile + card pill). (3)
  `does_prove` overstated "çalışan uygulama" though the gate runs `MERGEN_RUN_APP=false`
  (no Shiny service, no URL probe) → narrowed to in-process checks; `does_not_prove`
  adds the "deployed service up / app URL not probed" caveat.
- **Codex review follow-up — round 2 (2× P2, hardens round 1):** (1) JSON-validate
  guard checked *syntax* only — a secret value like `ok` could rewrite the `counts.ok`
  KEY yet still validate → reader reports zero passing checks. REPLACED the json-text
  helper with `mergen_post_deploy_smoke_redact_record()`: redaction runs on structural
  STRING VALUES only, BEFORE serialization; list keys + numbers + counts are never
  touched, so the schema can't break and toJSON always yields valid JSON. (2)
  `.health_release_pill()` didn't recognize `degraded` → the card rendered raw/unknown
  while the tile showed Kısmi/warning; extended the pill to map `degraded`/`warning`
  → warning/"Kısmi"/"Uyarı". Tests: contract redaction test rewritten to assert
  key/count preservation under an `ok`-targeting redactor; UI test asserts the degraded
  card pill is `health-status-warning` (not raw "degraded"). Focused 3-file run 16/17/11
  0-fail; `ai_validate quick` PASS (`artifacts/ai-validation/20260624-153221/summary.json`).
  GOTCHA: any future change to the worker-export-style redaction must redact VALUES not
  the serialized blob — never let redaction touch JSON keys/counts.
- **Codex review follow-up — round 3 (2× P2, hardens round 2):** (1) round 2 still
  redacted ALL string values; `overall` is a status ENUM, so a secret value equal to
  `pass`/`degraded` could rewrite `record$overall` → valid JSON, `should_fail` false →
  panel shows neutral for a passing/degraded gate. FIX: `mergen_post_deploy_smoke_redact_record()`
  now RESTORES `overall`/`reason`/`gate`/`validation_execution_status` from the original
  AFTER the value-walk (these are constants/enums/git-metadata, never secrets). (2) the
  gate `stop()`-ed on missing-env / `app.R` source failure / absent `health_collect_checks`
  BEFORE the artifact block → those failure modes left no artifact (panel `not_found`,
  masking the failure). FIX: helpers now source BEFORE `app.R`; `.smoke_redact`/
  `.smoke_write_artifact`/`.smoke_fail_and_stop` + `critical_ids`/`fail_on_unknown` are
  defined early; new pure `mergen_post_deploy_smoke_failure_result(reason)` lets all 3
  early exits write an `overall="fail"` artifact before stopping (and `source("app.R")`
  is wrapped in tryCatch). Tests: enum-restore + failure-result + a gate grep for
  `mergen_post_deploy_smoke_failure_result`. Focused 18/17/11 0-fail; `ai_validate quick`
  PASS (`artifacts/ai-validation/20260624-155351/summary.json`). GOTCHA: the post-deploy
  redaction is now "redact free-form string VALUES, then restore the enum/identity scalars"
  — if you add a new reader-interpreted enum field, add it to the restore set too.
- **Codex review follow-up — round 4 (1× P1, gate correctness):** `health_collect_checks()`
  returns a DATA FRAME (`do.call(rbind, ...)`, one row per check), but
  `mergen_post_deploy_smoke_evaluate()` used `for (chk in checks)` which iterates a
  data frame's COLUMNS, not rows. Atomic columns skipped the `is.list(chk)` branch →
  every id blank, every status "unknown" → a real `db.primary`/`app.boot` critical was
  never added to `critical_failures`, `should_fail` stayed FALSE, and the gate PASSED
  despite a critical check. FIX: before the empty-check and loop, convert a data frame to
  row records (`lapply(seq_len(nrow(checks)), function(i) as.list(checks[i, , drop = FALSE]))`);
  `is.data.frame` is checked BEFORE `is.list` (a data frame is also a list). The
  list-of-records path (existing tests) is unchanged. Test: data-frame row evaluation
  (critical `db.primary` row triggers fail/critical_failures; all-ok → pass; 0 rows →
  no_checks). Focused 19/17/11 0-fail; `ai_validate quick` PASS
  (`artifacts/ai-validation/20260624-161202/summary.json`). GOTCHA: any future evaluator
  input-shape change must keep the data-frame→rows normalization first; never iterate a
  health-checks data frame directly with `for (x in df)`.
- **VALIDATION (Linux/cloud, R 4.6.0, logger + placeholder env):**
  `ai_validate quick` FULL PASS (failed=0, skipped=0, app_source_smoke=passed,
  `artifacts/ai-validation/20260624-102241/summary.json`). `ai_validate full
  --boot-smoke` FULL PASS: app source smoke passed, **full testthat suite passed
  (181.6s)**, shiny boot passed, browser smoke SKIPPED (no browser); failed=0,
  skipped=0 (`artifacts/ai-validation/20260624-102401/summary.json`). seam_doctor OK;
  parse_sanity 854; maintainability 100/100 max 681. The prior "logging test
  full-suite blocker" did NOT reproduce (it is environment-bootstrap: needs `logger`
  + placeholder `LOCAL_LLM_ENDPOINT`/`DB_DSN`/`AI_KEYS_MASTER`, not a test-isolation
  bug). NOT VM/SSO/DB/SQL-Server Turkish encoding/real-browser proof.
- **NOT proven (by design):** the gate's live artifact write needs app boot on the
  VM; cloud verified the pure producer + reader end-to-end (evaluate→record→toJSON→
  write→read-back) + the script token contract, not a live VM run. The artifact is a
  deployment-moment **snapshot** of health — NOT load/concurrency/long-stability/
  real-browser/VM-SSO-SQLServer proof.
- **GOTCHAS:** (1) `helpers_post_deploy_smoke.R` is sourced STANDALONE by its contract
  test → do not use `%||%` there (use explicit null checks like the existing
  evaluator). (2) The maintainability report counts `(<-|=)\s*function\s*\(`, so
  inline `error = function(e)` handlers DO count toward the per-file fn budget —
  watch the 24 ceiling on near-budget files. (3) Run discovery scripts with
  `LANG=C.UTF-8 LC_ALL=C.UTF-8` (Turkish files; C/POSIX locale throws "invalid
  input"). (4) Focused tests that use `resolve_repo_root_for_tests()` need helpers →
  run via `testthat::test_dir("tests/testthat", filter=...)`, not bare `test_file`.

- **BEST NEXT TARGETS** (from this session's reports): #1 `R/server_handler_true_streaming.R`
  (681, the global ratchet pin — extract a cohesive helper layer; SSE/streaming is
  sensitive, preserve request-id/stop-file/reasoning-recovery contracts). Then
  `R/helpers_claude_code_documents.R` (679), `R/module_file_manager.R` (642/10 after delete-runtime split; has a
  725/14 file budget). Frontend: `www/js/ai_expert_manager.js` (802/45/12 event/8
  Shiny handler — top function/handler density but WITHIN the 850-line/60-fn/20-shiny
  budgets, so it's a "split then tighten budget" exercise, not a budget breach) and
  `www/js/deep_space_intro.js` (820, scene orchestrator with companion shader/solar
  files already split). No post-deploy carryover remains.

---

## LATEST SESSION RESULTS — `claude/optimistic-carson-q8jihd` (2026-06-20, TWO complexity packages)

This session shipped **two behavior-preserving structural splits of the two largest R
files** (each was the global ratchet pin in turn). Both surgical, additive, byte-identical.
Do NOT redo either.

### Package 2 — `R/server_runtime_context.R` SSO auth-ready/refreshable-module split (committed after Package 1)

- **SSO post-auth + yenilenebilir modül wiring katmanı ayrıldı** (the documented #2
  target): `serverRuntimeOnSsoAuthReady`, `serverRuntimeRefreshModuleOnSsoAuthReady`,
  `serverRuntimeAttachRefreshableModule` moved verbatim from `R/server_runtime_context.R`
  to **`R/server_runtime_auth_ready.R`** (YENİ, 242/4). Context dropped **687/17 → 503/13**
  (keeps init/attach/require + the module registry helpers AttachModule/GetModule/
  ExposeSessionData).
- Manifest order: `server_runtime_context.R → server_runtime_auth_ready.R →
  server_runtime_function_slot.R` (functions resolve deps at call time; new file loads
  after context). New file has a WD-independent fallback (sources context if its module
  registry is missing) — the same blessed pattern context.R itself uses.
- **BYTE-IDENTICAL proof:** (context + auth_ready) vs HEAD context → function set
  identical, **0 body mismatches** (`deparse` of all 24 functions). SSO timing
  (ignoreInit/once/fail-fast, immediate-ready path, local-mode no-op) preserved.
- **Ratchet TIGHTENED:** global `MERGEN_TEST_MAX_FILE_LINES` 687 → **681** (new largest
  = `server_handler_true_streaming.R` 681). Budgets: context 540/15, auth_ready 290/6.
- **New test** `tests/testthat/test-server-runtime-auth-ready-split-contract.R` (33).
  Wired into `shiny_calisma_zamani` seam guard (6→7); section `server_init_runtime`
  13→14; total runtime 279→280. Tests that EXECUTE the 3 functions now source the new
  file: `test-server-runtime-context.R`, `test-e2e-sso-identity-readiness-regression.R`,
  `test-server-module-wiring-{chat-engine,runtime-bindings}.R`,
  `test-server-core-interaction-runtime.R`; production-contracts parse list updated.
- **VALIDATION:** `ai_validate full --boot-smoke` FULL PASS (app source smoke passed,
  **full testthat suite passed 181.2s**, shiny boot passed, browser skipped),
  `artifacts/ai-validation/20260620-170730/summary.json`. seam_doctor OK; maintainability
  100/100 max 681; parse_sanity 851. NOT VM/SSO/DB/real-browser proof.
- **NEXT TARGETS now:** `R/server_handler_true_streaming.R` (681),
  `R/helpers_claude_code_documents.R` (679), frontend
  `www/js/deep_space_intro.js` (820/32), `www/js/ai_expert_manager.js` (802/45).

### Package 1 — `R/config_ui_assets.R` DATA/VALIDATORS/RENDER split

This session shipped a **behavior-preserving structural split of the largest R file**
(`R/config_ui_assets.R`, the global ratchet pin). Surgical, additive. Do NOT redo:

- **UI varlık manifesti VERİ / DOĞRULAYICI / RENDER olarak bölündü** (the established
  `config_ui_asset_zones.R` DATA + `config_ui_asset_zone_validators.R` validators
  pattern, applied to the asset manifest):
  - `R/config_ui_assets.R` 690/17 → **425/1** (SADECE VERİ: groups, deferred list,
    render plan, JS/CSS order rules, `ui_asset_flatten_groups`; single owner of order).
  - `R/config_ui_asset_validators.R` (YENİ, 253/11): `ui_asset_all_css/js`,
    `ui_asset_deferred_js_paths`, `ui_asset_public_root`, `ui_asset_render_plan_*`,
    `ui_asset_duplicate_paths`, `ui_asset_validate_css_order/js_order/js_render_plan`,
    `ui_asset_validate`.
  - `R/config_ui_asset_tags.R` (YENİ, 59/5): `ui_asset_css_tag`, `ui_asset_script_tag`,
    `ui_asset_css_tags`, `ui_asset_js_tags`, `ui_asset_tags`.
  - Manifest order DATA → VALIDATORS → RENDER (all before `config_ui_asset_zones.R`);
    functions resolve data at call time (lazy), so data loads first.
- **BYTE-IDENTICAL proof:** golden capture of all 11 function outputs before the split
  + HEAD-vs-worktree comparison → `ui_asset_all_css/js`, css/js order rules, render
  plan, deferred groups, full `ui_asset_tags()` HTML all `identical()` TRUE (tag md5
  `11c977ddce2c3aee5307eadc5fa4995a`). Runtime UX/asset-order unchanged.
- **Ratchet TIGHTENED (not loosened):** global `MERGEN_TEST_MAX_FILE_LINES` 690 → **687**
  (new largest = `server_runtime_context.R` 687). Per-file budgets added:
  `config_ui_assets.R` 470/2, `config_ui_asset_validators.R` 300/13,
  `config_ui_asset_tags.R` 110/8.
- **New test** `tests/testthat/test-ui-asset-config-split-contract.R` (100 assertions):
  structural split + post-split `ui_asset_validate()`/`ui_asset_tags()` behavior. Wired
  into `frontend_varlik` seam guard_tests (8 → 9). Source manifest section
  `config_ui_assets` n=3 → 5; total runtime 277 → 279.
- **Sourcing sites updated** (functions moved out of `config_ui_assets.R`):
  `tests/scripts/seam_doctor.R`, `tests/scripts/frontend_maintainability_report.R`,
  and tests `test-ui-asset-manifest-contract.R`, `test-config-ui-assets-helpers-behavior.R`,
  `test-ui-asset-tag-builders-behavior.R`, `test-streaming-markdown-safety-contract.R`,
  `test-ui-asset-zones-contract.R`, `test-seam-registry-contract.R`,
  `test-ui-asset-zone-validators-split-contract.R` now source all three files.
- **GOTCHAS:** (1) Cloud R locale is C/POSIX → `seam_doctor.R`/`frontend_complexity_doctor.R`
  throw "invalid input found on input connection" on Turkish files; run with
  `export LANG=C.UTF-8 LC_ALL=C.UTF-8`. `maintainability_report.R` is unaffected
  (reads lines, no parse). (2) The "logging test full-suite blocker" from prior
  sessions did **not** reproduce here: the real cause is the missing `logger` package
  + missing `.Renviron`; after `install.packages("logger")` and setting placeholder
  `LOCAL_LLM_ENDPOINT`/`DB_DSN`/`AI_KEYS_MASTER`, the FULL strict testthat suite
  passed clean (138.5s). So the blocker is environment-bootstrap, not a test-isolation
  bug to fix. (3) Tests that only grep the manifest TEXT (theme-light, brand-title,
  tool-backgrounds, e2e-boot/health `ui_asset_tags()` in `ui.R`) read DATA and needed
  no change; only function-EXECUTING sites did.
- **VALIDATION (Linux/cloud, R 4.6.0, logger installed + placeholder env):**
  `ai_validate quick` FULL PASS (failed=0, skipped=0, app_source_smoke=passed,
  `artifacts/ai-validation/20260620-152956/summary.json`). `ai_validate full --boot-smoke`
  FULL PASS: app source smoke passed, **full testthat suite passed (138.5s)**, shiny
  boot smoke passed, browser smoke SKIPPED (no browser),
  `artifacts/ai-validation/20260620-153104/summary.json`. parse_sanity 849 files;
  seam_doctor OK (`frontend_varlik` runtime 3→5, guard 8→9); maintainability 100/100
  max 687. Cloud run is NOT VM/SSO/DB/SQL-Server Turkish encoding/real-browser/vision
  proof.
- **BEST NEXT TARGETS** (from this session's reports): #1 `R/server_runtime_context.R`
  (687, new largest — extract SSO auth-ready/refreshable-module helpers or repeated
  require/attach validators; preserve SSO timing/ignoreInit/once contracts). Then
  678–681 band: `helpers_claude_code_documents.R`, `server_handler_true_streaming.R`,
  `module_file_manager.R`. Frontend: `www/js/deep_space_intro.js` (820/32) and
  `www/js/ai_expert_manager.js` (802/45/12 event/8 Shiny handler). Post-deploy smoke
  artifact family still has no producer (Faz 3 carryover).

---

## LATEST SESSION RESULTS — `claude/pensive-davinci-8p2jkh` (2026-06-15 D, Faz 2→9.5)

By-name untested taraması tükendiği için bu oturum **dal/şube derinleştirme +
Faz 5 adversarial** önceliğine geçti. İki Bilge Yolaç GÜVENLİK sınırının
davranışsal olarak hiç sınanmamış dalları kapatıldı (33 doğrulama, 0
fail/warn/skip). Çalışma zamanı R kodu DEĞİŞMEDİ (2 yeni test, additive); gerçek
bug bulunmadı — iki sınır da doğru davranıyor, testler sözleşmeyi kilitler.
Do NOT redo:

- **`test-claude-code-prompt-intent-validate-behavior.R`** — pre-CLI güvenlik
  kapısı `cc_policy_validate_prompt_file_intent()` orkestratör DALLARI. Mevcut
  sözleşme testi yalnızca 4 durumu + HER ZAMAN açık `allowed_roots` ile sınıyordu
  (run-streaming STUB'lıyor, run-lifecycle statik grepl). Kapatılan dallar:
  no-write-intent→ok, no-token→ok, **türetilen kökler** (`allowed_roots` boşken
  `cc_policy_allowed_output_roots`; içeri izinli/dışarı engelli), göreli `../`+
  boş-workdir→engel, `../` traversal→engel, `blocked_paths`+hata sözleşmesi
  (`ok=FALSE`), uzantısız+var-olmayan dış token→ATLA (false-positive önleme).
- **`test-claude-code-generated-file-filter-behavior.R`** —
  `cc_policy_filter_generated_file_paths()` (üretilen-dosya indirme filtresi).
  Sözleşme testi yalnızca 1 durum sınıyordu. Adversarial dallar: **`..` kökten
  KAÇAN yol normalize-sonra-reddet** (download-bypass savunması), `..` geri dönen→
  collapse korunur, boş/NULL→character(0), dedup, NA/boş elenir, çoklu kök-içi+dışı.
- **GOTCHA'lar:** orkestrator bağımlılıkları 3 AYRI dosyada → PER-FILE source
  guard (kardeş test yalnızca prompt-policy'yi globalenv'e yüklüyor → tek guard
  yetmez). `cc_policy_extract_path_like_tokens` SLASH'sız (`rapor.txt`) veya
  baştan-`/`-siz (`alt/x.txt`) göreli adı ÇIKARMAZ → göreli dalı `../...` ile sına.
  Türetilen kökleri deterministik kılmak için `withr::local_envvar` ile
  `CLAUDE_CODE_ALLOWED_*`/`DEFAULT_WORKDIR` temizle + dış dizin tempdir kardeşi.
  Filtre `log_warn`+`CLAUDE_CODE_LOG_PREFIX` kullanır → izole `test_env`'e stub'la.
- **VALIDATION (Linux/cloud, R 4.6.0):** `ai_validate quick` TAM (failed=0,
  skipped=0, app_source_smoke=passed); parse_sanity 804; ratchet 0 fail
  (test-only). `full --boot-smoke` koşulmadı (additive test; runtime değişmedi →
  `quick` yeterli). Cloud koşumu VM/SSO/DB/SQL-Server Türkçe encoding/gerçek-
  browser/vision kanıtı DEĞİLDİR. Sıradaki: `cc_policy_validate_workdir` dalları,
  SSO fail-closed derin dallar, `sendMessageInit` mod-dispatch sonrası.

- **Devam (aynı oturum, "continue") — `test-sso-extract-user-claims-behavior.R`:**
  `extract_user_claims` (Keycloak JWT payload→kimlik eşlemesi). test-sso-jwt.R onu
  yalnızca yorumda anıyor (doğrudan test YOK). Kapatılan güvenlik dalları: NULL→NULL,
  SSO_CLAIM_MAP eşlemesi+token meta, username küçük-harf+teknik normalize, **görünen
  vs teknik mojibake ayrımı** (email/sicil/keycloak_sub/username repair=FALSE), first_name
  fallback, boş claim→"". GOTCHA: ayrımı `normalize_text_utf8`'i globalenv'de `V:/T:`
  kayıt-edici stub ile geçici değiştirip `withr::defer` (had=FALSE→`rm`) ile geri
  yükleyerek kontrol-akışı düzeyinde kanıtla (mojibake fixture YOK; Windows-VM güvenli).
  14-dosyalık SSO batch yeşil (recorder sızmıyor). `ai_validate quick` TAM.

---

## LATEST SESSION RESULTS — `claude/quirky-tesla-vbv62b` (2026-06-15 C, Faz 2→9.5)

Bu oturum kullanıcının Windows VM testthat suite'indeki 1 hatayı giderdi ve Faz 2
kalan 14 untested fonksiyonu davranışsal kapattı (**untested 17 → 3**; kalan 3'ü
runtime'da `rm()` edilen bootstrap yardımcısı, bilinçli atlandı). Çalışma zamanı R
kodu DEĞİŞMEDİ (1 test fix + 4 yeni test). Cerrahi, additive. Do NOT redo:

- **Windows VM fix — `test-claude-code-existing-file-link-security-behavior.R:124`:**
  XSS testi gerçek diskte `kotu<b>"x.txt` oluşturuyordu; `< > "` Windows'ta
  GEÇERSİZ → `writeLines` "cannot open the connection" hatası + uyarı, `skip_if_not`
  satırına ulaşılamıyordu. Fix: XSS sınırı iki bölüm — (1) platformdan bağımsız
  altyazı (`display_path`) eleman-metni escape'i (gerçek dosya adı gerekmez); (2)
  gerçek dosya adındaki `&quot;` öznitelik escape'i yalnızca Linux'ta, oluşturma
  uyarısı/hatası `tryCatch(warning=,error=)` ile yutulur. Skip yok, Windows'ta hata
  yok. **GENEL DERS:** gerçek diskte Windows-yasaklı ad (`< > : " | ? *`) ile dosya
  oluşturan test YAZMA; ham string geçir veya güvenli ad (`özet.txt`) kullan +
  caller-controlled display alanını escape doğrulaması için kullan.
- **4 yeni davranış testi (129 doğrulama, 0 fail/warn/skip; tek tek + batch):**
  `test-settings-yapilandirma-ui-cards-behavior.R` (11 `.syap_*` kart yapıcısı TEK
  TEK — sahiplik sınırı: her kart yalnızca KENDİ ns kimliklerini üretir;
  id-surface testi yalnızca birleşik UI'yi donduruyordu),
  `test-llm-worker-call-behavior.R` (`call_llm_worker` araçsız yol + HTTP/hata
  normalizasyon — httr `local_mocked_bindings`, payload helper'ları stub),
  `test-send-message-init-guards-behavior.R` (`sendMessageInit` send_message
  erken-dönüş korumaları — fabrika gözlemci kaydetmez, doğrudan çağrılır;
  SSO-kimlik user-id'den ÖNCE, user-id<=0/NA, çift-gönderim, boş mesaj),
  `test-character-video-debug-behavior.R` (`.character_video_debug` forward/no-op).
- **GOTCHA'lar:** (1) `call_llm_worker` enclosing-env'de çözülen `llm_worker_*`
  payload helper'larını stub'la + `extract_llm_content_and_sources`/
  `strip_planner_text` env override; httr namespace mock `content` iki imzayı
  karşılamalı (`as="parsed"`→liste / `as="text"`→""); error-handler `cat("[ERROR]")`
  gürültüsünü `expect_error(capture.output(...))` ile yut. (2) `sendMessageInit`
  bir FABRİKA (gözlemci yok) → testServer gereksiz; 24 argümanı NULL/stub geç
  (tembel değerlendirme); `SSO_ENABLED`/`showToast`/`resolve_effective_user_id`'ı
  izole env'e koy → batch globalenv'i gölgele; SSO-auth korumasının user-id'den
  önce geldiğini resolve stub'ını `stop()` yaparak kanıtla. (3) Sadece-fonksiyon-
  tanımı modülünü `new.env(parent=baseenv())`'e source et → `exists(...,inherits=TRUE)`
  zincirinde globalenv yok, batch pollution'dan bağımsız deterministik.
- **Kalan 3 untested bilinçli atlandı:** `.helpers_llm_sse_source_sibling`,
  `.mcp_bootstrap_assign_global_function`, `.mcp_bootstrap_require_tool_functions` —
  üçü de tanım sonrası `rm()` edilir (runtime'da yok). Test ETME.
- **VALIDATION (Linux/cloud, R 4.6.0):** `ai_validate quick` TAM (failed=0,
  skipped=0, app_source_smoke=passed); parse_sanity 800 dosya OK; ratchet 174 PASS
  (test-only, skor değişmedi). `full --boot-smoke` koşulmadı (test-only değişiklik).
  Cloud koşumu VM/SSO/DB/SQL-Server Türkçe encoding/gerçek-browser/vision kanıtı
  DEĞİLDİR.

---

## LATEST SESSION RESULTS — `claude/zen-gauss-w423sz` (2026-06-15, Faz 2→9.5)

Bu oturum 3 AĞIR runtime closure'unu davranışsal kapattı, 1 Faz-5 adversarial
güvenlik boşluğu + 1 cerrahi sertleştirme yaptı ve kullanıcının Windows VM
testthat suite'inde gördüğü 4 hatayı (3 dosya) gerçekten düzeltti. Cerrahi,
additive. Do NOT redo:

- **Faz 2 — 3 yeni davranış testi (94 doğrulama, 0 fail/warn/skip; untested 20→17):**
  `test-server-init-chat-runtime-behavior.R` (`serverInitChatRuntime` fabrikası;
  **add_message kullanıcı kimliğini ÇAĞRI ANINDA canlı sağlayıcıdan çözer** =
  SSO sözleşmesi), `test-chat-simulate-streaming-behavior.R` (`chat_simulate_streaming`
  KARAR/erken-çıkış dalları — TTS yok/var/promise resolve/reject/success=FALSE;
  **hepsi stop_generation=TRUE ile observer döngüsüne girMEDEN** senkron),
  `test-claude-code-stream-poll-binding-behavior.R` (`cc_bind_claude_code_stream_polling`
  testServer; stop gözlemcisi **request-id kapsamlı finalize**, klavye gözlemcisi,
  poll `durduruldu`/zaman-aşımı erken dalları; invalidateLater ilerletilmez).
- **Faz 5 — adversarial + sertleştirme:** `test-claude-code-existing-file-link-security-behavior.R`
  (`format_claude_code_existing_file_link_html`: **izinli kök DIŞINDAKİ dosya →
  boş bağlantı** — mevcut encoding testi `cc_policy_path_inside_roots`'u
  YÜKLEMEDİĞİ için bu dal hiç sınanmamıştı; yeni test gerçek path-policy yükler).
  Cerrahi: `R/helpers_claude_code_existing_file_link.R` öznitelik bağlamı
  (`href`/`download`/`title`) artık `htmlEscape(..., attribute=TRUE)` → tırnak
  öznitelikten kaçamaz. Fail-before/pass-after kanıtlı.
- **Windows VM 4 hata (3 dosya) — GERÇEKTEN düzeltildi (önceki "VM'de geçiyor"
  iddiası BAYATMIŞ):**
  1+2. `test-file-click-observers-behavior.R:119,134` — üretim repo kökünü
     `normalizePath(getwd(),winslash="/")` ile çözer (UNC `\\sunucu/...`), test ham
     `getwd()` (`//sunucu/...`) kullanıyordu → önek uyuşmazlığı. Fix (test):
     `any(endsWith(exists_paths, "www/img/x.png"))` suffix doğrulaması.
  3. `test-pk-analiz-process-request-behavior.R:155` — üretim güvenlik kapısı
     (`module_proje_kaynak_analizi.R:223`) `toupper(enc2utf8(final_sql))` +
     locale-duyarlı grepl kullanıyordu; UTF-8-işaretli string Windows Türkçe
     (UTF-8-olmayan) yerel ayarda grepl/toupper'ı HATA verdiriyor → res
     "Veritabanı Hatası" içeriyor ama "Guvenlik ihlali" içermiyordu. Fix (ÜRETİM):
     `toupper` kaldırıldı; `grepl(...,final_sql,ignore.case=TRUE,perl=TRUE,
     useBytes=TRUE)` (yerelden bağımsız, ASCII anahtarlar). `helpers_deep_analysis.R:289`
     AYNI kapıyı `enc2utf8` OLMADAN kullandığı için VM'de geçiyor → DOKUNULMADI.
  4. `test-release-evidence-behavior.R:334` — "/repo/kok" Windows'ta MUTLAK değil
     → `normalizePath` UNC cwd'ye göre çözüyor. Fix (test): `withr::local_tempdir()`
     + üretimle aynı normalize biçiminde beklenen + `basename(...)=="artifacts"`.
- **VALIDATION (Linux/cloud, R 4.6.0):** `ai_validate quick` TAM (failed=0,
  skipped=0, app_source_smoke=passed); `full --boot-smoke` TAM (**full testthat
  suite passed 162.7s** — `test-file-click-observers` artık Linux full suite'te
  de GEÇİYOR; shiny boot passed; browser smoke SKIPPED — browser yok; DB/SSO/
  SQL-Server Türkçe encoding NOT performed). parse_sanity 794 dosya OK; ratchet
  174 (100/100, max 24 fn); seam_doctor OK. Cloud koşumu VM/DB/SSO/vision/gerçek-
  browser kanıtı DEĞİLDİR.
- **GOTCHA'lar:** (1) dosyada TANIMLI helper'ları (chat_reset_state vb.) source
  SONRASI stub'la — source onları ezer. (2) promise cat çıktısı `.css_drain()`
  ile capture.output İÇİNDE çalıştırılmalı. (3) observer-bağlayıcı moduleServer
  değilse küçük modül sarmalayıcı rv döndür; `session$returned$is_running<-TRUE` +
  `session$flushReact()` ile poll dallarını tetikle (capture-in-place için
  is_running=FALSE başlat, expr içinde flip). (4) `enc2utf8`+`toupper`+`grepl`
  Windows Türkçe locale'de zehirli; ASCII anahtar taraması `useBytes=TRUE` ile
  yerelden bağımsız yapılmalı. (5) `getwd()`-tabanlı tam-yol test beklentileri
  Windows UNC'de `normalizePath` önek farkıyla kırılır → suffix/endsWith kullan.
  (6) Sabit "/repo/kok" Windows'ta mutlak değil → `withr::local_tempdir()`.

- **Devam (aynı oturum, "add more test") — 2 Faz-5 güvenlik testi + 1 sertleştirme
  (35 doğrulama):** `test-claude-code-downloads-security-behavior.R`
  (`resolve_claude_code_generated_path`/`list_claude_code_generated_file_paths`/
  `stage_claude_code_downloads` — üretilen dosya yalnızca izinli kök içindeyse
  indirilebilir; kök-dışı traversal düşürülür; daha önce yalnızca statik referanslı),
  `test-claude-code-downloads-html-behavior.R`
  (`format_claude_code_generated_downloads_html` kart + XSS sınırı). Cerrahi:
  `R/helpers_claude_code_downloads_html.R` href/download/title artık
  `htmlEscape(attribute=TRUE)` (existing-file-link ile aynı açık). GOTCHA:
  `resolve_*` var-olmayan yolda 1.5sn `Sys.sleep` döngüsüne girer → var-olan
  dosya + mutlak yol + `withr::local_dir(wd)` kullan; indirme kökünü
  `withr::local_options(mergen.claude_code_download_root=tempdir)` ile yönlendir
  (repo kirliliği yok).

---

## LATEST SESSION RESULTS — `claude/affectionate-faraday-yksxki` (2026-06-14, Faz 2→9.5)

Bu oturum görev önceliği sırasıyla 8 untested fonksiyonu davranışsal kapattı (dosya
yaşam döngüsü → derin/proje analizi → Bilge Yolaç streaming → doküman orkestrasyonu)
ve Faz 3 latency özetini ekledi. Cerrahi, additive. Do NOT redo:

- **Faz 2 — 5 yeni davranış testi (0 fail/warn/skip; tek tek + batch 185 doğrulama):**
  `test-file-pipeline-upload-batch-behavior.R` (`handle_file_upload_batch` —
  **uzantı reddi + gizli kaydedilmiş-ama-geçersiz yükleme YOK + kopyalama-hatası
  temizliği** = Faz 5), `test-deep-analysis-process-behavior.R`
  (`pk_deep_analysis_process` orkestrasyon/fallback/durdurma/yetki),
  `test-pk-analiz-process-request-behavior.R` (`pk_analiz_process_request` erken-dönüş
  + **YASAKLI SQL reddi DELETE/DROP/TRUNCATE/ALTER** = Faz 5; SSO-kimlik-hazır-değil
  DB'ye gitmeden döner; + `find_best_query_with_ai` LLM JSON eşleme),
  `test-claude-code-run-streaming-behavior.R` (`run_claude_code_streaming` processx-mock:
  boş/CLI-yok/politika-reddi/akış/çıkış-kodu/zaman-aşımı/başlatma-hatası/on_chunk),
  `test-claude-code-document-orchestration-behavior.R`
  (`prepare_claude_code_document_context` + `write_claude_code_document_summary_file` +
  `summarize_claude_code_documents_with_local_llm`; çıkarıcı/LLM stub'lı, gerçek
  PDF/Excel/DOCX fixture YOK).
- **Faz 3 — secret-safe AI çağrı latency özeti:** log formatı KANITLANDI
  (`log_ai_call` → `AI Call: ... duration=<sn>s, success=...`).
  `release_evidence_summarize_ai_call_latency` (saf; yalnızca sayısal süre +
  başarı/başarısızlık; kullanıcı/model taşınmaz) + `log_health$ai_call_latency`
  additive alanı + `.health_release_ai_latency` (Doğrulama Kanıtı > Günlük Log Sağlığı).
  Kanıt: `test-release-evidence-ai-latency-behavior.R`. Ratchet güvenli
  (helpers_release_evidence 20→21 fn, module_health_release 4→5; global cap 24 dokunulmadı).
- **GOTCHA'lar:** (1) Modül kaynak-zamanı guard döngüleri
  (`module_proje_kaynak_analizi.R` `pk_required_helpers`, `helpers_claude_code_documents.R`
  extractor-guard) — guard'ın aradığı fonksiyon adlarını env'e ÖNCEDEN stub koy →
  `exists(inherits=TRUE)` tatmin → guard `source(..., local=globalenv())` ATLANIR
  (globalenv kirliliği yok, batch-safe). (2) `shinyjs::delay`
  `local_mocked_bindings(delay=function(ms,expr){force(expr)}, .package="shinyjs")` ile
  senkron özyineleme. (3) `processx::process$new` →
  `local_mocked_bindings(process=list(new=...), .package="processx")` + is_alive sayaçlı
  fake_proc; timeout_sec=-1 ile zaman aşımı deterministik. (4) Maintainability raporu
  YALNIZCA `(<-|=)\s*function\s*\(` (atama) sayar; anonim `lapply(x, function(...))`
  SAYILMAZ → saf summarizer'da anonim handler kullanmak ratchet'i etkilemez.
- **VALIDATION (Linux/cloud, R 4.6.0):** `ai_validate quick` **TAM GEÇTİ** (failed=0,
  skipped=0, app_source_smoke=passed) — hem behavioral hem latency commit sonrası.
  parse_sanity 783 dosya OK; ratchet 174 PASS (max 24 fn korunur); release-evidence/
  health-release/e2e-health 0 fail. Untested 36 → 28.
- **ÖNEMLİ — `full --boot-smoke` testthat suite 1 başarısız adım: SADECE
  `test-file-click-observers-behavior.R` (PR #464'te commit edildi, BENİM DEĞİL,
  benim dosyalarım yüklenmeden TEK BAŞINA da başarısız).** Kök neden:
  `file.path(getwd(),"www/...")` üyelik + MockShinySession prime-then-set coalescing →
  Linux/cloud çalışma-dizini/sürüm duyarlı. **Kullanıcı onayı: GitHub testthat suite
  uygulamayı çalıştıran Windows VM'de GEÇİYOR.** Linux/cloud-only artifact; gerçek
  regresyon değil; DOKUNMA. Cloud koşumu VM/SSO/DB/SQL Server Türkçe encoding/gerçek
  browser/vision live kanıtı DEĞİLDİR.

**DEVAM (aynı oturum, "continue") — 4 yeni test, 5 untested fn daha (27 doğrulama,
untested 28 → 23):** `cc_refresh_user_file_manager_after_run`
(`test-claude-code-refresh-fm-after-run-behavior.R`), `admin_ha_show_modal`
(`test-admin-ha-show-modal-behavior.R`; shinyjs::runjs mock), `attach_required_packages`
(`test-config-packages-attach-behavior.R`; library mock + `tryCatch(source)` ile
source-time validate/stop/attach yutulur), `gc_scheduler`/`start_gc_scheduler_once`
(`test-gc-scheduler-behavior.R`; `later::later` mock + `.GlobalEnv` bayrağı
`withr::defer` save/restore). config_file_store.R testthat'te temiz source olur.

**DEVAM-2 (aynı oturum, "cover the next targets") — 3 yeni test, 3 untested fn daha
(36 doğrulama, untested 23 → 20):** `sessionCacheInit`
(`test-session-cache-init-behavior.R`; döndürülen cache API + sahte oturum env),
`mergen_console_appender` (`test-config-logging-console-appender-behavior.R`; logger
global durumu save/restore, geçici MERGEN_LOG_DIR), `helpers_mcp_tools$prepare_chart_data`
(`test-mcp-prepare-chart-data-behavior.R`; kaynak-zamanı `.mcp_prepare_chart_data_fn`
rm edilir → runtime'da YALNIZCA `prepare_chart_data` erişilir; erken-dönüş dalları +
MCP zinciri globalenv'e tekil yükleme + yaprak override/restore). `ai_validate quick`
her ikisinde de TAM geçti.

Sıradaki yüksek değerli hedefler: `sendMessageInit`/`serverInitChatRuntime`/
`chat_simulate_streaming`/`call_llm_worker` (ağır testServer + yoğun stub),
`cc_bind_claude_code_stream_polling` (büyük observer-bağlama). Kalan küçük helper'lar
(`.mcp_bootstrap_*` runtime'da rm edilir, `.helpers_llm_sse_source_sibling`,
`.character_video_debug`) düşük değer/kırılgan. Faz 3 sıradaki: post-deploy smoke
artifact ailesi (üretici yok → uydurma).

---

## LATEST SESSION RESULTS — `claude/serene-bell-3l1xw6` (2026-06-13 B, Faz 2→9.5)

Bu oturum servis-bağlı runtime mantığına davranışsal kapsama (Faz 2) ve operatör
görünürlüğüne secret-safe hata-kategorisi özeti (Faz 3) ekledi. Cerrahi, additive.
Do NOT redo:

- **Faz 2 — 5 yeni davranış testi (servis-bağlı, 0 fail/warn/skip):**
  `test-file-pipeline-summarize-behavior.R` (`summarize_file_with_llm`),
  `test-deep-analysis-execute-query-behavior.R` (`execute_single_deep_query` —
  erken-dönüş + **SQL DROP/DELETE/TRUNCATE/ALTER reddi** = Faz 5 örtüşmesi),
  `test-deep-analysis-multi-query-behavior.R` (`find_multiple_queries_with_ai` —
  dedup/güven<30/sıralama/cap), `test-mcp-execute-parsed-tool-behavior.R`
  (`execute_parsed_tool` yönlendirme; MCP zinciri globalenv'e, yaprak araçlar
  test başına geri yüklenir), `test-server-core-runtime-guards-behavior.R`
  (8 saf server core runtime guard).
- **Faz 3 — secret-safe hata kategorisi:** `release_evidence_summarize_error_contexts`
  (`Error in <bağlam>:` etiketini sayar, mesaj taşımaz, güvenli karakter + 60
  sınır, "diğer", top_n) + `release_evidence_log_health$error_contexts` additive
  alan + `.health_release_error_contexts` (Sistem Durumu > Release Kanıtı > Günlük
  Log Sağlığı kartı). Kanıt: `test-release-evidence-error-contexts-behavior.R`.
- **VALIDATION (bu container, R 4.6.0):** `ai_validate quick` TAM (failed=0,
  skipped=0, app_source_smoke=passed); `full --boot-smoke` TAM (**full testthat
  suite passed 138.8s**, shiny boot passed; browser smoke SKIPPED — browser yok;
  DB/SSO/SQL-Server Türkçe encoding NOT performed). parse_sanity 775 dosya OK;
  maintainability-ratchet 0 fail (max 24 fn); seam-registry/source-manifest 0 fail.
  Untested top-level fn 49 → 37. Cloud koşumu VM/DB/SSO/vision/gerçek-browser
  kanıtı DEĞİLDİR.

Sıradaki yüksek değerli hedefler: `handle_file_upload_batch` (uzantı-reddi dalı),
`pk_deep_analysis_process`/`pk_analiz_process_request`, `run_claude_code_streaming`
(processx mock), claude_code document orkestratörleri, kolay UI builder'lar
(`adminYanitAnaliziUI`/`adminDokumantasyonUI`/`admin_doc_group_tab_panels`),
`.mcp_bootstrap_*`. Faz 3 sıradaki: latency özeti (log formatı doğrulanırsa).

---

## LATEST SESSION RESULTS — `claude/affectionate-bohr-ietfly` (2026-06-13, Faz 2→9.5)

Bu oturum, önceki oturumun bıraktığı en somut adımı tamamladı: **Faz 3 release
kanıt görünürlüğünün UI bağlaması.** Do NOT redo:

- **Sistem Durumu > "Release Kanıtı" sekmesi (operatör görünürlüğü):**
  `R/module_health_release.R` (YENİ) `helpers_release_evidence.R` saf okuyucusunun
  secret-safe özetini (en son VM evidence gate, ai_validate summary, günlük log
  ERROR/WARN) gösterir. `R/module_health.R`'a "release" sekme paneli + switch +
  refresh'e bağlı saf `release_evidence_overview` reactive (DB/LLM/ağ yok) eklendi.
  Manifest `module_health_chartlab` n 9→10 (toplam 263). Kanıt-yok dürüstlüğü
  korunur; artifact yolu / ham log içeriği render edilmez.
- **Davranış testleri (0 fail/warn/skip, tek tek + batch):**
  `test-health-release-ui-behavior.R` (UI builder + secret-safe sınır +
  healthServer "release" yönlendirme testServer), `test-claude-code-parse-stream-event-behavior.R`
  (`parse_stream_event` tüm olay türleri), `test-release-evidence-behavior.R`
  genişletildi (3 iç yardımcı).
- **Aynı oturum devamı (kullanıcı "add more relevant tests") — 5 yeni test (93 doğrulama):**
  `test-sso-auth-server-behavior.R` (ssoAuthServer fail-closed testServer),
  `test-claude-code-connection-behavior.R` (check_claude_code_status processx-mock
  + test_claude_code_connection), `test-ai-expert-call-llm-behavior.R` (httr-mock,
  gövde yakalama + telaffuz), `test-misc-runtime-predicates-behavior.R`
  (.path_text_encoding_helper_available / .fm_runtime_is_reactivevalues /
  ui_asset_zone_get), `test-send-message-request-callbacks-behavior.R`
  (mergen_build_send_message_request_callbacks req_id capture). Ölü kod
  `.health_release_kv` kaldırıldı. GOTCHA'lar test-coverage prompt'unda.
- **Doğrulama:** `ai_validate.sh quick` → failed=0, skipped=0, app_source_smoke=passed
  (her iki commit setinden sonra); `full --boot-smoke` → full testthat suite passed
  (121.5s), shiny boot passed, browser smoke SKIPPED (browser yok). parse_sanity 770
  dosya OK; sections/source-manifest/seam-registry/ratchet/e2e-health 0 fail; seam_doctor
  OK. Cloud koşumu VM/SSO/DB/SQL Server Türkçe encoding/gerçek browser/vision kanıtı DEĞİLDİR.

Sıradaki yüksek değerli hedefler: deep_analysis/pk_analysis servis-bağlı helper'lar
(LLM/DB mock), `run_claude_code_streaming` (processx mock), `execute_parsed_tool`
(MCP zinciri), `sendMessageInit`/`chat_simulate_streaming` (ağır testServer).
Faz 3 sonraki: log kategori/latency özeti.

---

## LATEST SESSION RESULTS — `claude/peaceful-ritchie-hvd1y7` (Faz 2→9.5 kampanyası)

Bu oturum davranışsal kapsamayı derinleştirdi, release kanıt görünürlüğü
katmanı ekledi, özellik sahiplik haritası oluşturdu ve 2 cerrahi güvenlik
sertleştirmesi yaptı. Do NOT redo:

- **11 yeni davranış testi (~444 doğrulama, 0 fail/warn/skip, tek tek + batch)** —
  tam liste `.ai/next-session-test-coverage-prompt.md` başında. Öne çıkanlar:
  `quickActionsInit`/`apiKeyServer` testServer, `sso_fetch_jwks`, config_logging
  sink'leri (gerçek appender), wiring guard'ları, release evidence okuyucu,
  adversarial battery.
- **Faz 3 — `R/helpers_release_evidence.R`**: vm-evidence/ai-validation
  artifact'larını ve günlük log ERROR/WARN sayaçlarını SECRET-SAFE okuyan saf
  katman. Manifest'e `support_admin_health_helpers` içinde (health_checks'ten
  önce) eklendi; sections contract n 6→7, toplam 261→262 bilinçli güncellendi.
  Sistem Durumu UI bağlama SONRAKİ oturuma bırakıldı (saf helper + test hazır).
- **Faz 4 — `docs/feature-ownership-map.md`**: 9 kritik özellik için dosya/test/
  servis sahipliği + sıradaki hedefler; docs/README.md'ye bağlandı.
- **2 cerrahi güvenlik sertleştirmesi (regresyon testli):**
  - `mergen_sanitize_markdown_links` → vbscript: ve data:text/html link
    protokollerini de nötrler (javascript: + data:image/http/https davranışı korunur).
  - `utils_upload_validator` → `.upload_has_bidi_control` ile Unicode bidi-override
    (Trojan Source) dosya adlarını reddeder; Türkçe adlar kod-noktası düzeyinde
    denetlendiği için etkilenmez.

VALIDATION (bu container, R 4.6.0): `ai_validate.sh quick` ve `full --boot-smoke`
TAM geçti — full testthat suite passed (130.8s), shiny boot passed, app source
smoke passed; browser UX smoke SKIPPED (browser binary yok); DB/SSO/SQL-Server
Türkçe encoding NOT run (VM-only). `seam_doctor.R` OK, `frontend_complexity_doctor.R`
OK, maintainability 100/100. Cloud koşumu VM/DB/SSO/vision/gerçek-browser kanıtı
DEĞİLDİR.

---

## LATEST SESSION RESULTS — `claude/sharp-brown-inTxI` (assume merged)

This session shipped the **admin documentation viewer** (primary feature) plus a
focused hardening/coverage batch. Do NOT redo:

### NEW FEATURE — admin-only in-app documentation viewer (DONE)

- New page **"Yönetici Paneli > Dokümantasyon"** (`tabName = "admin_dokumantasyon"`),
  consistent with the other admin tabs (uses `admin_page_layout()` pills + ADMIN badge).
- `R/helpers_admin_documentation.R` (PURE, 20 fns / 445 lines): allowlist registry
  (`admin_doc_registry`, 10 docs in 4 Turkish groups), path safety
  (`admin_doc_resolve_path` — unknown id / `..` / absolute => `""`, root containment),
  UTF-8 read (`admin_doc_read_markdown` via `read_text_lines_utf8`), Turkish-aware
  ASCII slug (`admin_doc_slugify` — chartr lower, NOT `tolower`, locale-safe),
  tag-WHITELIST sanitizer (`admin_doc_sanitize_html` + `admin_doc_html_has_risk`),
  TOC + heading-id injection (`admin_doc_extract_toc`), high-level render
  (`admin_doc_render_markdown` / `admin_doc_render_document`).
- `R/module_admin_documentation.R` (6 fns / 246 lines): `adminDokumantasyonUI`,
  group pills, doc cards, TOC, render cache, `adminDokumantasyonServer`.
- `www/css/admin_documentation.css` (theme-aware, light overrides scoped to
  `html[data-theme="light"]`), `www/js/admin_documentation.js` (one delegated click
  handler: card select -> namespaced `doc_select` input, TOC scroll, TOC toggle).
- **CLAUDE.md and AGENTS.md are intentionally NOT in the registry** (AI-agent contracts).
- **Rendering decision (IMPORTANT):** docs are full of R code with `<-`. The project
  `render_safe_markdown_html()` PRE-escapes `<`/`>`, which corrupts code blocks
  (`x <- 1` -> `x &lt;- 1` -> displays `&lt;`). So the viewer renders with
  `commonmark::markdown_html(..., extensions=c("strikethrough","table"))` directly
  (allowed — only `helpers_messaging.R` is contract-banned from direct commonmark;
  `helpers_chartlab.R`/`helpers_claude_code.R` already call it) THEN runs the
  tag-whitelist output sanitizer. Docs are TRUSTED allowlisted repo files; the
  sanitizer is defense-in-depth (escapes script/iframe/style/etc., strips on*/style,
  neutralizes javascript:/vbscript:/data:text/html). DO NOT switch the viewer to
  `render_safe_markdown_html` — it breaks R code display.
- **Perf:** `admin_doc_html_has_risk` is a fast single-pass risk scan; if NO xss
  pattern exists the expensive tokenize is skipped. This took technical-reference.md
  (240 KB) from ~7.8 s to ~0.42 s. Renders are cached per doc per session. Do NOT
  remove the fast path; the whole-string tokenize on a 270 KB string is ~5 s
  (gregexpr+regmatches splice), so only run it when risk is actually present.
- Wiring: `R/config_source_manifest.R` (helper before module, after admin_yanit),
  `R/config_ui_assets.R` (css in `page` group after `admin_yanit_analizi.css`; js in
  `deferred` group after `health_dashboard.js`), `ui.R` tabItem,
  `R/server_observers_misc.R` menuSubItem + `adminDokumantasyonServer(...)` init.
- Test `tests/testthat/test-admin-documentation-behavior.R` (135 assertions, 0/0/0/0):
  registry/allowlist, CLAUDE/AGENTS exclusion, path safety, UTF-8, code/table/list
  render, XSS boundary (direct + indirect), TOC anchors + uniqueness, slugify,
  all-docs render, UI builders, `testServer` (group switch / doc select / unknown-id
  reject / refresh toast). NOTE: the refresh observer is `ignoreInit=TRUE` ->
  PRIME-THEN-SET (`setInputs(refresh_analytics=1); setInputs(refresh_analytics=2)`).

### PRIORITY 1 — concurrency: NOT triggered

The new module uses NO async primitives (`%...>%`/`promises`/`later`/
`tracked_future_promise`). No async audit was needed. The DOCX clobber fix from the
prior session is still the only known concrete async bug and is already fixed.

### PRIORITY 5 — 2 new behavioral test files (+39 assertions, 0/0/0/0)

- `test-source-manifest-read-parse-behavior.R` (19): `source_manifest_read_file_with_encoding`
  (BOM strip, **CRLF/CR -> real LF** contract — proves no literal "n" corruption,
  result parses), `source_manifest_try_parse_file` (valid->TRUE, CRLF-valid->TRUE,
  syntax-error->stop). Temp files written with `writeBin(charToRaw(...))` for exact bytes.
- `test-server-runtime-contracts-behavior.R` (20): `is_server_runtime_context`,
  `.server_runtime_require_context`/`_require_values`/`_require_functions`/
  `_invoke_auth_ready_callback` (contracts file) and `.server_runtime_require_named_functions`/
  `_require_environment` (named-contracts file). Pure guards; assert Turkish error
  + owner label propagation.
- Untested top-level fn count: 83 -> **73** (admin_doc internals + the above now covered).

### VALIDATION (this session)

- `Rscript tests/scripts/parse_sanity_check.R` -> OK (722 files).
- `test-maintainability-ratchet.R` -> 156 pass / 0 fail / 0 warn, **score 100/100**,
  max file lines 765, max fns 24, 0 over-budget. (New files: helper 445/20, module 246/6.)
- New/changed tests standalone + `test_dir` batch -> 174 assertions, 0 fail/warn/skip.
- Contract regressions clean: `test-runtime-network-boundary-contract.R`,
  `test-frontend-selector-contract.R`, `test-production-contracts.R`,
  `test-streaming-markdown-safety-contract.R`, `test-accessibility-contract.R`,
  `test-source-manifest-contract.R`, `test-global-source-manifest-contract.R`,
  `test-frontend-maintainability-ratchet.R` all PASS.
- `bash tools/ai_validate.sh quick` -> FAILED at app-source-smoke (cloud: `logger`
  package absent). Fell back to `bash tools/ai_validate.sh cloud-quick` -> PASS:
  `failed_steps=0`, `skipped_steps=1`, `profile_requested=cloud-quick`,
  `profile_effective=quick`, `app_source_smoke_status=skipped`,
  `db_sso_vm_validation_performed=false`,
  `sql_server_turkish_encoding_preflight_status=not_performed_by_ai_validate`.
- KNOWN cloud-only: `test-ui-asset-manifest-contract.R` still fails on MISSING VENDORED
  assets (`css/all.min.css`, `codemirror/*`, `lib/threejs/*`) — pre-existing, NOT my
  files (`css/admin_documentation.css` / `js/admin_documentation.js` exist & pass the
  ordering checks). App boot / browser / VM / DB / SQL-Server Turkish encoding were
  NOT proven (cloud limit, not a regression). No screenshot (cloud cannot boot the app).

### NEW LESSONS

- `commonmark::markdown_html` has NO `safe`/escape arg in this version, and PASSES
  raw HTML blocks/tags through unescaped -> sanitize the OUTPUT, do not trust it.
- PRE-escaping `<`/`>` before commonmark corrupts code blocks (`<-` -> `&lt;-` ->
  rendered `&amp;lt;`). For docs with code, render then sanitize, don't pre-escape.
- `gregexpr`/`regmatches<-` on a 270 KB string is ~2 s EACH -> guard expensive
  tokenization behind a cheap whole-string risk grep.
- Turkish `tolower("I")` -> "ı" (locale-dependent) -> for ASCII slugs transliterate
  Turkish first, then `chartr("A-Z","a-z")`, never `tolower`.

---

## LATEST SESSION RESULTS — `claude/beautiful-goodall-8yK70` (assume merged)

This session is COMPLETE. Do NOT redo the following:

### PRIORITY 1 — DOCX async clobber: FIXED + proven

- `R/module_file_preview.R`: added an inline `docx_preview_seq <- reactiveVal(0L)`
  in the module scope, increment-on-open with a captured `docx_open_token`, and
  guarded BOTH the async success `%...>%` and error `%...!%` callbacks with
  `identical(isolate(docx_preview_seq()), docx_open_token)`. A stale large-DOCX
  callback no longer renders the wrong document into a newer modal; the error
  toast is also suppressed for stale opens. No new top-level helper (function
  count stayed 22 ≤ 24; ratchet green).
- Regression test `tests/testthat/test-file-preview-docx-async-clobber-behavior.R`
  (15 assertions) is deterministic via `testServer` + a `local_mocked_bindings(
  future = ..., .package = "future")` stub that returns a manually-resolvable
  `promises::promise` (task_fn never forced → no real file/base64enc). Uses a
  NON-EXISTENT datapath so `file.info()$size` is NA → async branch taken without
  a 10 MB fixture. PROVEN: neutralizing the guard (`if (FALSE && ...)`) makes the
  test fail; restoring it passes.
- Re-ran the async audit (`%...>%`/`%...!%`/`promises::then`/`later::later`):
  the DOCX path was the ONLY unguarded fixed-target cross-modal clobber. All
  others are request-scoped (`mergen_is_current_request`/`req_id`), state-guarded
  (`is_speaking()` in `module_ai_expert.R`), or benign worker results. Did NOT
  manufacture fixes.

### PRIORITY 3 — fixed one PRE-EXISTING red contract test

- `tests/testthat/test-file-resolution-security-contract.R` test "MCP resolver
  mutlak path argümanını doğrudan kabul etmez" was RED on pristine `origin/main`
  (standalone AND in-suite): it grepped for the literal `"Absolute path argument
  ignored"`, but the production code was strengthened to REJECT (line ~224 of
  `R/helpers_mcp_file_resolver.R`: `"Absolute path argument rejected"` + `ok =
  FALSE` + Turkish error `"Mutlak dosya yolu kabul edilmez"`). Re-anchored the
  contract on STABLE behavioral anchors (`is_abs` check + the Turkish rejection
  message) instead of a drift-prone English debug string. Security guarantee
  NOT weakened — absolute paths are still rejected. Now green standalone (10
  assertions).

### PRIORITY 4 — no fallback guards needed

- Spot-checked standalone: all 5 MCP refactor-contract tests
  (`test-mcp-{chart-tools,schema-helpers,basic-tools,file-resolver,table-readers}-
  refactor-contract.R`) and all 4 health-check tests pass standalone (0 fail/err/
  skip). The `getwd()`-relative fallback guards in those MCP helpers and
  `helpers_health_checks.R` do NOT break any isolated test → left UNTOUCHED per
  the "fix only if an isolated test breaks" rule.

### PRIORITY 5 — 6 new behavioral test files (~78 new assertions, 0 fail/0 warn/0 skip)

- `test-llm-call-retry-behavior.R` (10): `call_llm_with_retry` — first-try
  success, character→list wrap, N-1-fail-then-success (Sys.sleep stubbed),
  exhausted-retries re-stop.
- `test-sso-der-tlv-behavior.R` (16): `.sso_der_length` (short/long form),
  `.sso_der_tlv` (TLV layout), `.sso_der_integer` (leading-zero strip + 0x00
  sign byte). Deterministic byte assertions.
- `test-file-store-mutation-helpers-behavior.R` (14):
  `.file_store_drop_stale_entries` / `.file_store_apply_rehydrated_paths` — stub
  `.file_store_mutate_index` over a controlled in-memory index; real
  `normalize_for_path_compare` (source `helpers_files_path.R` first).
- `test-sidebar-user-panel-server-behavior.R` (20): `mb_sidebar_theme_switch`
  (UI), `mb_sidebar_handle_logout_event` (session close + log), and
  `mb_sidebar_user_panel_server` via a `moduleServer` testServer wrapper —
  fallback / "Oturum hazırlanıyor" / full-identity badge renders, logout-button
  visibility, and the `mergen_sidebar_logout` observer (PRIME-THEN-SET).
- `test-claude-runtime-source-dir-behavior.R` (6): `resolve_claude_runtime_source_dir`
  — empty/NA, relaxed-resolver priority, real existing dir, non-existent → "".
- `test-get-user-profile-from-db-behavior.R` (12): `get_user_profile_from_db` —
  DBI-mocked early-NULL, UserID vs KullaniciAdi WHERE routing + params,
  no-rows→NULL, visible vs technical field normalization.

### NEW LESSONS (apply next time)

- **`logger` is NOT installed in the base cloud checkout.** Any test that
  `source()`s `R/config_logging.R` will be auto-SKIPPED (`{logger} is not
  installed`) → violates "0 skip". Either `install.packages("logger")` from RSPM
  first, OR avoid sourcing config_logging.R. I DROPPED a `log_error_with_context`
  test because (a) logger absent, and (b) capturing the interpolated message via
  a `log_error`/`log_debug` stub needs `glue(..., .envir = parent.frame(N))` and
  the correct `N` DIFFERS between a direct call (1) and a call nested inside
  `test_that` (2) — a fragile, environment-dependent frame count that "passes on
  Linux, fails on VM". Do NOT ship frame-count-dependent capture stubs.
- **Turkish `toupper` is locale-dependent** (C.UTF-8 vs Turkish): assert a
  locale-independent marker (e.g. a `"VIS:"` prefix stub) instead of asserting an
  uppercased Turkish string (`"BILGI İŞLEM"` vs `"BILGI IŞLEM"`).
- testServer `observeEvent(..., ignoreInit = TRUE)` needs PRIME-THEN-SET
  (`setInputs(x=1); setInputs(x=2)`) to fire; a single `setInputs` is consumed as
  the init.
- For module testServer custom-message capture, override the ROOT session:
  `root <- .subset2(session, "parent"); root$sendCustomMessage <- function(...)`.
- The `future::future({...})` async path is mockable with
  `local_mocked_bindings(future = stub, .package = "future")` where the stub
  returns a `promises::promise` and never forces the expr; drain with a bounded
  `while(!later::loop_empty()) later::run_now(timeout=0)`.

### VALIDATION RUN (this session)

- `Rscript tests/scripts/parse_sanity_check.R` → OK (716 files).
- `test-maintainability-ratchet.R` + `-contract.R` → 0 fail / 0 warn (max fns 24,
  0 over-budget files).
- Batch of all 7 new/changed test files via `test_dir(filter=...)` → 43 tests,
  93 assertions, 0 fail / 0 warn / 0 skip.
- `bash tools/ai_validate.sh quick` → FAILED at app-source-smoke (cloud limit:
  `R/config_sql_loader.R` needs SQL library files + placeholder index folders
  absent in the cloud checkout). Fell back to `bash tools/ai_validate.sh
  cloud-quick` → PASS: `failed_steps=0`, `skipped_steps=1`,
  `profile_requested=cloud-quick`, `profile_effective=quick`,
  `app_source_smoke_status=skipped`, `shiny_boot_smoke_status=not_requested`,
  `browser_smoke_status=not_requested`, `db_sso_vm_validation_performed=false`,
  `sql_server_turkish_encoding_preflight_status=not_performed_by_ai_validate`.
  App boot / browser / VM / DB / SQL-Server Turkish encoding / manual fragile-flow
  were NOT proven (cloud limitation, not a regression).

---

## BRANCH / PR RULES

- Start with a **fresh branch** from the latest `origin/main` or the latest merged state.
- Do **NOT** commit to, push to, or build on `claude/exciting-einstein-JGkKQ`, `claude/clever-carson-fV8c3`, or any earlier session branch.
- If the harness assigns a new branch, use it as-is. Otherwise create one, for example `claude/eliminate-weaknesses-*`.
- Commit in small, themed commits with **Turkish** messages.
- When done, open a **NEW pull request** with a Turkish description.
- Do NOT reopen, force-push, or reuse any prior session branch/PR.

---

## LATEST USER-CONFIRMED STATUS — VISION IS NOW LIVE-VERIFIED ON WINDOWS VM

The previous remaining VM-only vision task is now DONE.

The user confirmed that on the Windows VM they set:

`MERGEN_VISION_MODELS=<real Image-Input model IDs>`

in `.Renviron`, and the relevant image-input models now work as expected end-to-end with image attachments.

Treat vision live verification as complete. Do **not** keep it as an unresolved top priority.

Still preserve these contracts:

- Do NOT fake vision.
- Do NOT regress the text-only path.
- Non-vision models must remain text-only and must show the explicit Turkish note.
- `MERGEN_ENABLE_VISION=false` remains the global kill-switch.
- `CODING_DEEP_*` models are auto-marked by the capability helper.
- Optional future work: a Yapılandırma toggle and/or `max_bytes` config may be added only if surgical, deterministic, and well tested.

---

## WHAT IS ALREADY DONE — DO NOT REDO WITHOUT RE-VERIFYING

### Latest prior session: `claude/exciting-einstein-JGkKQ` / PR #460

Assume this session is merged.

#### Vision pipeline completed and now VM-live-verified

- `R/helpers_vision_model_capabilities.R` exists and is sourced before `config_api.R`.
- `parse_vision_models_env()` splits `MERGEN_VISION_MODELS` on `;` and `,` only. Do NOT split on whitespace because model IDs may contain spaces.
- `apply_vision_model_capabilities(api_config, extra_vision_models, env_value)` normalizes all model capabilities to `vision = FALSE`, then marks env-listed and caller-extra models as `vision = TRUE`.
- `R/config_api.R` calls the helper with `extra_vision_models = c(coding_deep_low_model, coding_deep_high_model)`.
- `mergen_vision_enabled()` is capability-primary and default-enabled. It is disabled only by explicit false values in `options(mergen.vision_enabled)` or `MERGEN_ENABLE_VISION`.
- Multimodal `image_url` content survives serialization through the real `call_local_llm` httr JSON path and the SSE worker curl JSON body path.
- Tests already added:
  - `test-vision-context-behavior.R`
  - `test-vision-model-capabilities-behavior.R`
  - `test-vision-llm-payload-serialization-behavior.R`
- Windows VM live test is now confirmed by the user: real `.Renviron` model IDs were set and image-attached prompts work as expected.

#### Maintainability ratchet contract corrected

The two per-file baselines in `test-maintainability-ratchet-contract.R` were bumped to real measured values with a Turkish comment:

- `R/module_startup_screen.R`
- `R/helpers_ai_expert.R`

This is the intended per-file baseline maintenance mechanism. The global ratchet in `test-maintainability-ratchet.R` was NOT loosened and must remain untouched.

#### Runtime network-boundary cloud issue resolved

The redacted internal avatar host placeholder `https://url......./` was allowlisted with regex `^https?://url\.+/` in `test-runtime-network-boundary-contract.R`. It is treated as an intentional redaction placeholder, not a public dependency.

#### One fallback guard fixed

`R/helpers_llm_sse.R` no longer relies only on `getwd()`-relative `file.path("R", ...)` loading for sibling helpers. It now uses the candidate-root pattern.

Remaining fallback-guard suspects are listed under Priority 4.

#### Concurrency audit result

Most async paths were re-audited and found guarded or benign:

- `server_handler_summarization.R`
- `module_settings_yapilandirma.R`
- `server_observers_startup.R`
- `helpers_file_pipeline.R`
- `module_ai_processing.R`
- `module_chat_history_background.R`
- TTS-related paths

The only concrete deferred finding is the DOCX-preview async clobber in `R/module_file_preview.R`.

#### Behavioral coverage added

Latest prior session added or updated behavioral tests including:

- `test-claude-code-document-builders-behavior.R`
- `test-send-message-lifecycle-helpers-behavior.R`
- `test-deep-analysis-context-builder-behavior.R`
- `test-mcp-tools-parse-behavior.R`
- `test-claude-code-plugins-server-behavior.R`
- `test-ai-expert-db-fetch-behavior.R`
- vision behavior/capability/serialization tests

Do not duplicate these unless a regression requires it.

#### Critical encoding lesson

When rewriting CRLF/Turkish files with R scripts, use:

`LANG=C.UTF-8 LC_ALL=C.UTF-8`

Otherwise `readLines()` + `enc2utf8()` + `writeBin()` can corrupt Turkish bytes into literal `<c4><b1>`-style text.

After such edits:

- run `grep -c '<c3>\|<c4>\|<c5>' file`;
- result must be 0 except intentional mojibake-example docs;
- inspect `git diff --stat`;
- preserve CRLF where required.

LF files can use the normal Edit tool.

#### renv status

Do NOT generate `renv.lock` from Linux/cloud.

The real production lock belongs to the Windows VM / R 4.6.0 environment. It may be absent from the GitHub/cloud checkout. `git ls-files renv.lock` being empty in cloud is expected and not a bug. `test-renv-lock-contract.R` passes whether or not the lock is present.

`renv/library` may intentionally remain empty on the production VM so the app keeps using the global library. Do not run `renv::restore()` on the production VM without user agreement.

---

### Earlier sessions — still valid

#### Concurrency / stale-request races fixed

- `R/server_llm_response_handlers.R` non-streaming stoppable handler is request-scoped with `mergen_is_current_request` and newer-request checks.
- `R/server_ai_expert_handlers.R` page guidance now speaks only if the user is still on the page for which guidance was generated.
- Existing regression tests:
  - `test-nonstreaming-handler-stale-request-race-behavior.R`
  - `test-ai-expert-page-guidance-stale-behavior.R`

#### Working-directory-independent fallback guard fixed

- `R/server_runtime_context.R` fallback loader no longer relies on `getwd()`-relative `"R/<file>"`.

#### Test isolation improved

Most standalone-broken tests were fixed. The only known remaining standalone/environmental blocker in cloud is:

- `test-ui-asset-manifest-contract.R`

Reason: the cloud checkout lacks vendored assets such as `www/css/all.min.css`, `www/codemirror/*`, and `www/lib/threejs/*`. This is not a code bug.

#### Image uploads allowed and leak fixed

- Image extensions are centralized through `fm_normal_allowed_extensions()`.
- Bulk upload validates extension before `copy_to_mcp_base`.
- Chat upload path uses the same centralized list.
- Existing test:
  - `test-image-upload-allowed-behavior.R`

#### Toast and refresh-button UX fixes

- Toast duration now scales from 5–12 seconds by message length.
- Refresh buttons use unified `btn-modern btn-refresh` styling.

---

## PRIORITY 0 — TRUST WINDOWS VM OVER CLOUD

The cloud/Linux environment masks Windows-specific failures: locale/encoding, full-suite pollution, live LLM/vision endpoint, DB/SSO, vendored assets, and `.Renviron`.

Do NOT claim:

- "all green";
- "app booted";
- "VM proven";
- "DB/SSO proven";
- "vision proven";
- "full strict suite passed";

unless the matching Windows VM or live-service proof actually exists.

Vision proof now exists by user confirmation. Do not redo it as an open task unless you changed the vision path.

For renv:

- Never generate `renv.lock` from Linux/cloud.
- If it is absent in cloud, treat that as expected.
- If it is present, `test-renv-lock-contract.R` enforces consistency.
- Do not populate `renv/library` on the production VM without user agreement.

---

## PRIORITY 1 — FIX THE REAL DOCX-PREVIEW ASYNC CLOBBER

Open finding:

`R/module_file_preview.R` around lines 378–393.

For a DOCX larger than the sync base64 threshold, encoding runs in a future. The callback sends `openDocxPreview` to fixed `ns("docx_preview_container")`. If the user opens DOCX A, then opens DOCX B before A finishes, A’s late callback can render A into B’s modal.

Fix:

- Add an inline `docx_preview_seq <- reactiveVal(0L)` inside the module/server scope.
- Increment it on every DOCX modal open.
- Capture the token in the async closure.
- Before sending the UI message, guard with:

`identical(isolate(docx_preview_seq()), captured)`

Constraints:

- Do NOT create a top-level helper; `module_file_preview.R` is near the function-count ratchet.
- Keep the fix inline and surgical.
- Add a deterministic `testServer` regression test.
- The test should prove A’s delayed async result cannot clobber B’s newer modal.
- Stub/defer `future::future` or the async boundary as needed.
- Reuse existing stale-request patterns where applicable.
- Do NOT invent a broader abstraction.

After the fix, re-run the async audit for new or missed callbacks involving:

- `%...>%`
- `%...!%`
- `promises::then`
- `later::later`
- `tracked_future_promise`

Only fix real cross-request or cross-modal clobbers. Do not manufacture fixes for benign callbacks.

---

## PRIORITY 2 — PARALLEL-PATH PARITY AUDIT

Only audit deeply if you touch relevant files.

Sensitive areas:

- startup skip-intro vs experience-mode vs `apply_experience_mode`;
- welcome screen attached vs fresh paths;
- new-chat / saved-chat-load / quick-action entry;
- any path that should produce the same UX through different branches.

The original class of bug was a parallel-path divergence. Preserve parity.

---

## PRIORITY 3 — TEST ISOLATION

Every test should run standalone unless blocked by a documented environment limitation.

Re-run the standalone scan:

```r
for (f in list.files("tests/testthat", "^test-.*\\.R$")) {
  out <- system2("Rscript", c("-e", shQuote(sprintf(
    'library(testthat); r <- as.data.frame(test_file("tests/testthat/%s", reporter = "silent")); cat(sum(r$error))', f))),
    stdout = TRUE, stderr = TRUE)
}
```

Expected known environmental exception in cloud:

- `test-ui-asset-manifest-contract.R`

Any new standalone-ERROR test must be fixed by finding the real helper owner and adding a narrow source guard. Watch for moved-helper traps after refactors.

---

## PRIORITY 4 — WORKING-DIRECTORY-INDEPENDENT FALLBACK GUARDS

Already fixed:

- `R/server_runtime_context.R`
- `R/helpers_llm_sse.R`
- `R/helpers_claude_code_documents.R`

Remaining suspects:

- `R/helpers_mcp_chart_tools.R`
- `R/helpers_mcp_schema_helpers.R`
- `R/helpers_mcp_basic_tools.R`
- `R/helpers_mcp_file_resolver.R`
- `R/helpers_mcp_table_readers.R`
- `R/helpers_health_checks.R`

These still use `getwd()`-relative `file.path("R", ...)` fallback guards.

Fix only if an isolated test actually breaks or if a deterministic contract clearly proves the issue.

Use the proven candidate-root pattern:

- repo root;
- parent/ancestor root;
- `../../` from `tests/testthat`;
- `MERGEN_REPO_ROOT`;
- `repo_root_for_tests` if already available.

Do not break MCP refactor contracts.

---

## PRIORITY 5 — BEHAVIORAL TEST COVERAGE

The documented #1 weakness remains behavioral test coverage.

Begin by re-running the FIXED-string untested-function scan from `.ai/next-session-test-coverage-prompt.md`. Last known rough count was about 96 remaining candidates.

Highest-value clusters:

### Admin renderers via `shiny::testServer`

Use the proven pattern from `test-admin-users-outputs-behavior.R`.

Targets:

- `genel_bakis_outputs`
- `yz_performans_outputs`
- `geri_bildirim_genel_outputs`
- `sohbet_kalitesi_outputs`
- `zaman_analizi_outputs`
- `gelismis_analizler_outputs`
- `yanit_analizi_outputs`

Assert real rendered output behavior, not just existence.

### Health checks

Targets:

- `helpers_health_checks`
- `helpers_health_runtime_checks`

Mock:

- `get_connection`
- DBI calls
- `httr`/network probes

Assert the `health_result(...)` contract:

- status;
- severity;
- message;
- remediation;
- deterministic offline behavior.

### Database helper boundaries

Targets:

- `helpers_destek_database`
- AI/user/support database helpers not already covered

Use DBI mocks. Never hit the real DB.

### Module servers via `testServer`

Targets:

- `apiKeyServer`
- `ssoAuthServer`
- `quickActionsInit`
- `imageGalleryServer`
- selected `module_performance` helpers

Use real inputs and assert real output/state transitions.

### Image gallery helpers

Targets:

- `get_image_thumbnail_base64`
- `get_chat_title_for_image`

Use small deterministic fixtures. Do not rely on external files unless created inside the test tempdir.

### Logging helpers

Targets:

- `log_ai_call`
- `log_user_action`
- `log_error_with_context`

Mock DB/log sinks and assert payload shape/content.

### SQL loader helpers

Targets:

- `.sql_*`
- `.read_sql_*`

Source `R/library_queries.R` first where necessary. Do not connect to a real SQL Server.

### SSO signature helpers

Target:

- `.sso_der_tlv`

Assert deterministic byte/format behavior with fixed fixtures.

### Test requirements

Every new test must:

- assert real input→output behavior;
- be deterministic and offline;
- produce 0 fail / 0 warn;
- run green standalone;
- run green in a `test_dir` batch;
- avoid brittle "exists only" tests;
- use byte-safe repo scanning when scanning files.

Useful gotchas from prior sessions:

- set `shiny::shinyOptions(appDir = repo_root)` for plugin/app-root scans;
- source the full MCP chain once;
- `get_openai_tools()` returns `list(tools = list(...))`;
- stub unqualified non-attached functions directly in the helper’s environment;
- for AI expert handler tests, use the existing page-guidance stale test as the pattern.

---

## PRIORITY 6 — MAINTAINABILITY HEADROOM

Do not regress the ratchet.

If a fix would push a near-limit file over its budget:

- extract a small focused helper into a new file;
- update `R/config_source_manifest.R`;
- update source-manifest tests;
- keep ordering correct.

Do NOT loosen thresholds in `test-maintainability-ratchet.R`.

The per-file baselines in `test-maintainability-ratchet-contract.R` may be bumped only to real measured values with a Turkish comment explaining legitimate growth.

---

## CANDIDATE WEAKNESSES TO INVESTIGATE

### Real candidate: DOCX preview async clobber

This is the top concrete bug. See Priority 1.

### Remaining fallback guards

See Priority 4.

### Optional vision polish

Vision is now live-verified on the Windows VM. Optional polish only:

- Yapılandırma toggle;
- max image bytes config;
- clearer UI display of which models are vision-capable.

Do not destabilize the verified pipeline.

### Duplicate allowed-extension policies

Centralization improved, but grep for remaining hardcoded extension whitelists. Centralize only if drift is real.

### Toast duration contract

Toast duration plumbing was changed. Consider a lightweight JS/node-checkable contract only if useful.

### Frontend duplicate CSS selectors

`tests/scripts/frontend_maintainability_report.R` may list duplicate selectors. Review for genuine conflicts, not cosmetic duplication.

### renv lock

Do not generate from cloud. If absent, report honestly. If present, validate with existing contract.

---

## VALIDATION DISCIPLINE

After every new or edited test:

```sh
Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-X.R", reporter = "summary")'
```

Require:

- 0 FAIL;
- 0 WARN;
- no accidental SKIP.

Also run the test standalone and in a `test_dir` batch where appropriate.

After any R edit:

```sh
Rscript tests/scripts/parse_sanity_check.R
Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-maintainability-ratchet.R", reporter = "summary")'
```

After JS edits:

```sh
node --check path/to/file.js
```

if node is available.

Run the repo gate:

```sh
bash tools/ai_validate.sh quick
```

If the cloud environment blocks app-source-smoke because of missing vendored assets, `.Renviron`, heavy packages, SQL libraries, or live services, fall back to:

```sh
bash tools/ai_validate.sh cloud-quick
```

Report honestly:

- `profile_requested`
- `profile_effective`
- `app_source_smoke_status`
- `failed_steps`
- `skipped_steps`
- `db_sso_vm_validation_performed`
- `sql_server_turkish_encoding_preflight_status`

Do not claim full-suite success from the cloud checkout.

---

## WHAT TO DELIVER

Deliver:

- surgical fixes for real bugs;
- regression tests that fail before / pass after where applicable;
- additional behavioral tests for uncovered runtime/renderer/service-bound logic;
- test-isolation fixes only where needed;
- fallback-guard fixes only where proven useful;
- no UX regressions;
- no ratchet regression;
- no encoding damage;
- no secret/path-literal leak.

Final report must include:

- weaknesses found;
- fixes applied;
- tests added or updated;
- assertion counts if available;
- validation commands and results;
- what could not be covered offline and why;
- what remains for the next session.

At the end, update BOTH:

- `.ai/next-session-eliminate-weaknesses-prompt.md`
- `.ai/next-session-test-coverage-prompt.md`

The updates must record:

- what you did;
- what is now covered/fixed;
- what should not be redone;
- new weaknesses or false positives;
- exact validation commands and results;
- a new copy-paste prompt for the session after you.

Then open a NEW pull request with a Turkish description.

Begin by reading `CLAUDE.md`, `.ai/next-session-eliminate-weaknesses-prompt.md`, and `.ai/next-session-test-coverage-prompt.md`; then run the untested-function scan and standalone-test-isolation scan, show both lists, and work top-down by priority.

---

## COPY-PASTE PROMPT FOR THE NEXT SESSION

> Continue hardening MERGEN Bilge (R/Shiny). Read `CLAUDE.md` FIRST and in full,
> then `.ai/phase-2-to-9-5-progress.md`, `.ai/next-session-eliminate-weaknesses-prompt.md`
> and `.ai/next-session-test-coverage-prompt.md`. The session
> `claude/zen-gauss-w423sz` is MERGED — do NOT rebuild/push to it.
> Start/use a FRESH branch. Surgical, additive only. Turkish comments with real
> Turkish chars (ç ğ ı İ ö ş ü). Byte-safe readers for any repo-scanning test.
> NEVER write a Windows user-profile absolute path literal in test code OR comments.
> No CDN/heavy/browser deps. Respect source-manifest order. Do NOT loosen
> `test-maintainability-ratchet.R`. Use `LANG=C.UTF-8 LC_ALL=C.UTF-8` for any R
> readLines/writeBin rewrite of CRLF/Turkish files (then verify
> `grep -c '<c3>\|<c4>\|<c5>' file` is 0).
>
> ALREADY DONE — do NOT redo (latest session `claude/zen-gauss-w423sz`):
> behavioral coverage for `serverInitChatRuntime` (live-user-id-at-call-time = SSO
> contract), `chat_simulate_streaming` (TTS/stop DECISION+early-exit branches only,
> stop_generation=TRUE → no observer loop), `cc_bind_claude_code_stream_polling`
> (testServer: stop observer request-id-scoped finalize, keyboard observer, poll
> durduruldu/timeout early branches). Phase 5: `format_claude_code_existing_file_link_html`
> outside-allowed-roots rejection + attribute-escape hardening
> (`htmlEscape(...,attribute=TRUE)` for href/download/title in
> `R/helpers_claude_code_existing_file_link.R`; fail-before/pass-after). FIXED the
> user's 4 Windows-VM testthat failures: file-click tests now use endsWith suffix
> (UNC normalizePath vs getwd() prefix), pk forbidden-SQL guard now
> `grepl(...,ignore.case=TRUE,perl=TRUE,useBytes=TRUE)` (dropped toupper; the
> `enc2utf8`+`toupper` combo poisoned grepl on the Turkish locale —
> `helpers_deep_analysis.R:289` was left alone as it has no enc2utf8 and passes on
> VM), and release-evidence artifact_root test uses `withr::local_tempdir()`
> (Linux-only "/repo/kok" isn't absolute on Windows). The prior claim that
> `test-file-click-observers-behavior.R` "passes on the VM" was STALE — it was
> really failing; now fixed.
>
> ALREADY DONE — do NOT redo (session `claude/affectionate-faraday-yksxki`):
> behavioral coverage for `handle_file_upload_batch` (extension-reject + no-hidden-
> invalid-upload + copy-fail cleanup = Phase 5), `pk_deep_analysis_process`,
> `pk_analiz_process_request` (incl. DELETE/DROP/TRUNCATE/ALTER rejection = Phase 5;
> SSO-not-ready returns before DB), `find_best_query_with_ai`,
> `run_claude_code_streaming` (processx mock), and the 3 claude_code document
> orchestrators (`prepare_claude_code_document_context`/
> `write_claude_code_document_summary_file`/
> `summarize_claude_code_documents_with_local_llm`; extractor/LLM stubbed, no real
> doc fixtures). Faz 3: secret-safe `release_evidence_summarize_ai_call_latency`
> (`AI Call: ... duration=<s>s` → numeric-only) + `log_health$ai_call_latency` +
> `.health_release_ai_latency` UI (Doğrulama Kanıtı > Günlük Log Sağlığı). Same
> session "continue": `cc_refresh_user_file_manager_after_run`, `admin_ha_show_modal`
> (shinyjs::runjs mock), `attach_required_packages` (library mock + tryCatch source),
> `gc_scheduler`/`start_gc_scheduler_once` (later::later mock + `.GlobalEnv` flag
> save/restore). Same session "continue-2": `sessionCacheInit` (returned cache API),
> `mergen_console_appender` (logger global save/restore), and
> `helpers_mcp_tools$prepare_chart_data` (source-time `.mcp_prepare_chart_data_fn` is
> rm'd → only reachable as `prepare_chart_data`; early-return branches). Earlier
> sessions: `summarize_file_with_llm`, `execute_single_deep_query`,
> `find_multiple_queries_with_ai`, `execute_parsed_tool`, server core runtime guards,
> error-context summary, DOCX-preview async clobber FIXED, `ssoAuthServer`,
> `apiKeyServer`, `quickActionsInit`, `parse_stream_event`, `check_claude_code_status`.
> Vision is VM-live-verified. MCP/health `getwd()` fallback guards do NOT break
> isolated tests — leave them.
>
> KNOWN CLOUD-ONLY FAILURE (do NOT chase): `test-file-click-observers-behavior.R`
> (PR #464, NOT a recent session's file) fails standalone in Linux/cloud
> (`file.path(getwd(),"www/...")` membership + MockShinySession prime-then-set
> coalescing) but PASSES on the Windows VM that runs the app (user-confirmed). Trust
> the VM over cloud; do not "fix" it.
>
> PRIORITY 1 (concurrency): re-run the async audit if you touch any `%...>%` /
> `%...!%` / `promises::then` / `later::later` / `tracked_future_promise` path.
> Only fix REAL cross-request/cross-modal clobbers; do not manufacture fixes.
>
> PRIORITY 5 (behavioral coverage — the #1 weakness): re-run the FIXED-string
> untested-function scan (see test-coverage prompt; ~20 candidates remain).
> Highest-value targets still open are all HEAVY: `sendMessageInit`,
> `serverInitChatRuntime`, `chat_simulate_streaming`, `call_llm_worker` (testServer +
> heavy stubbing), `cc_bind_claude_code_stream_polling` (big observer-binding). The
> remaining small ones (`.mcp_bootstrap_*` rm'd at runtime,
> `.helpers_llm_sse_source_sibling`, `.character_video_debug`) are low-value/brittle —
> prefer ONE reliable heavy test over many fragile ones. Every
> test: real input→output, deterministic,
> OFFLINE, 0 fail / 0 warn / 0 skip, green standalone AND in a `test_dir` batch with
> `new.env(parent=globalenv())`. Watch: module source-time guard loops (pre-populate
> the guard's expected fn names in env so `exists(inherits=TRUE)` is satisfied and
> `source(...,local=globalenv())` is SKIPPED — no globalenv pollution), the Turkish
> `toupper` locale trap, the testServer `ignoreInit` PRIME-THEN-SET gotcha, the
> `shinyjs::delay`/`processx::process$new` mock patterns, and that the maintainability
> report counts ONLY `(<-|=)\s*function\s*\(` (anonymous handlers do NOT count).
>
> PRIORITY 3 (isolation): re-run the standalone scan. `test-ui-asset-manifest-
> contract.R` remains the only documented cloud-blocked one (missing vendored www
> assets). Fix any NEW standalone-ERROR test by sourcing the real owner helper.
>
> PRIORITY 6 (maintainability): do not regress the ratchet; extract a small sourced
> helper + update `R/config_source_manifest.R` + manifest-order tests if a fix
> would exceed a budget.
>
> Validate: per-file `testthat::test_file(..., reporter="summary")` (0 fail/warn/
> skip), `Rscript tests/scripts/parse_sanity_check.R`, `test-maintainability-
> ratchet.R`, then `bash tools/ai_validate.sh quick` (fall back to `cloud-quick`
> if app-source-smoke is blocked) and, for runtime/health/security changes,
> `full --boot-smoke`. Report the summary.json fields honestly. NEVER claim app
> boot / VM / DB / vision / browser proof from the cloud checkout (browser smoke
> SKIPs without a binary). At the END, update `.ai/phase-2-to-9-5-progress.md`,
> BOTH `.ai` prompts, `docs/feature-ownership-map.md`, and open a NEW pull request
> with a Turkish description.
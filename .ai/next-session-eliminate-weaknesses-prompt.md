# PROMPT — Eliminate ALL remaining weaknesses in MERGEN Bilge (fresh branch)

You are continuing hardening work on the **MERGEN Bilge** R/Shiny app. Your mission this session is to
**systematically and thoroughly eliminate as many remaining weaknesses as possible** — correctness,
concurrency, test coverage, test isolation, production robustness, and UX consistency — while preserving
every UX and contract guarantee.

Read `CLAUDE.md` FIRST and in full. It is the binding operational guide and OVERRIDES default behavior:
surgical changes only, additive-only tests, Turkish comments with proper Turkish characters
(ç ğ ı İ ö ş ü — never Latinize), no CDN/heavy/browser deps, respect source-manifest order, encoding
boundaries, and the maintainability ratchet. Also read `.ai/next-session-test-coverage-prompt.md` for the
behavioral-test technique catalog and the up-to-date "already covered, do NOT redo" list.

## ⚠️ BRANCH / PR RULES (read carefully)
- Start with a **FRESH START on a brand-new branch**. Do **NOT** commit to, push to, or build on
  `claude/clever-carson-fV8c3` (the previous session's branch) or any earlier session branch.
- If the harness assigns you a new branch, use it as-is. Otherwise create one, e.g.
  `claude/eliminate-weaknesses-*`. Base it on the latest `main` (or the latest merged state), NOT on
  any prior session branch.
- Commit in small, themed commits with **Turkish** messages. When done, **open a NEW pull request**.
- Do NOT reopen or force-push any prior session branch/PR.

## WHAT'S ALREADY DONE (do NOT redo — re-verify before duplicating)
Assume the previous session's branch (`claude/clever-carson-fV8c3`) is merged. It delivered:

**Concurrency / stale-request races (FIXED):**
- `R/server_llm_response_handlers.R` `generate_non_streaming_stoppable`: `onRejected`, the `onFulfilled`
  staleness guard, AND the `finally` are now request-scoped (`mergen_is_current_request` + an explicit
  `newer_request_active` check). A stale non-streaming/MCP result no longer clobbers a newer request's
  typing wrapper / `values$typing` / chat reset, and no stale error toast. Test:
  `test-nonstreaming-handler-stale-request-race-behavior.R`.
- `R/server_ai_expert_handlers.R` page-guidance: speaks only if the user is still on the page the
  guidance was generated for (`identical(isolate(input$tabs), page)`) — no stale speech after navigating
  to a muted page. Test: `test-ai-expert-page-guidance-stale-behavior.R`.
- Audited clean (no change needed): streaming `server_send_message` branch (already guarded), TTS
  (`stop_generation` + client owner model), `module_ai_processing` (pure transform), proje/deep-analysis
  (synchronous + `stop_check`), source-time schedulers (`start_gc_scheduler_once` guarded).

**Working-directory-independent fallback guard (FIXED, Priority 4 root cause):**
- `R/server_runtime_context.R`: the contract-helper fallback loader no longer uses a `getwd()`-relative
  `"R/<file>"` path; it resolves via candidate roots (`getwd()`, parent dirs, `MERGEN_REPO_ROOT`,
  `repo_root_for_tests`). This fixed 5 server tests that `stop()`-ed in isolation. Dormant in production.

**Test isolation (11/12 standalone-broken tests FIXED):**
- Added missing source-guards / `library(shiny)` / moved-helper sources to: `test-worker-monitor.R`,
  `test-create-code-block-html-behavior.R`, `test-messaging-html-builders-behavior.R`,
  `test-quick-action-routing.R`, `test-e2e-quick-actions-streaming-regression.R`,
  `test-chat-message-formatting-refactor-contract.R`, `test-server-core-interaction-runtime.R`, and (via
  the runtime_context fix) the 4 `test-server-runtime-context*/module-wiring*` tests.
- The ONLY remaining standalone-ERROR test is `test-ui-asset-manifest-contract.R`, which is an
  **environment limitation** (the cloud checkout is missing vendored `www/css/all.min.css`,
  `www/codemirror/*`, `www/lib/threejs/*`). NOT a code bug — do not "fix" it.

**Behavioral coverage (9 new test files):** `test-module-ui-builders-behavior.R` (historyUI,
savedChatsUI, imageGalleryUI, sttUI, chartLabUI, destekHataBildirUI, settingsKisiselUI, healthUI,
`history_accessible_date_range_input`, `health_source_optional`), `test-api-key-choice-modal-builders-behavior.R`
(api_key_choice modal builders + `llm_worker_extract_preview_df`), `test-admin-users-outputs-behavior.R`
(`admin_users_outputs` highcharter), `test-chat-runtime-followup-push-behavior.R` (`push_followup_update`
+ `update_messages_after_bulk_deletion` guard), `test-update-sso-fields-behavior.R` (DBI-mocked SSO
write boundary), `test-normalize-claude-code-text-files-behavior.R`.

**UX fixes (this session, also merged):**
- **Image uploads now ALLOWED** (`fm_image_extensions()`; jpg/jpeg/png/gif/webp/bmp/svg in
  `fm_normal_allowed_extensions()`). The Dosya Yönetimi "saved-but-hidden" leak is fixed:
  `execute_bulk_upload` now validates the extension (`validate_uploaded_file(allowed_ext = ...)`) BEFORE
  `copy_to_mcp_base`. `readFileContentToString` returns a clean Turkish note for images (no binary
  garbage). **NOTE: there is still NO image/vision pipeline** — uploaded images cannot be analyzed by the
  LLM yet (see "New candidate weaknesses" below). Test: `test-image-upload-allowed-behavior.R`.
- **Toasts** now display 5–12 s scaled by message length (was a flat 3 s): `www/js/toast.js`
  smart default, `shiny_message_handlers.js` passes `data.duration`, R `showToast` default → `NULL`.
- **"Yenile" buttons unified**: all refresh buttons (Söyleşi Geçmişi, Kayıtlı Söyleşiler, Görsel Galerisi,
  all Yönetici pages, Sistem Durumu) now use `btn-modern btn-refresh`; `.btn-modern.btn-refresh` is now
  container-agnostic in both `file_manager.css` (dark teal) and `theme_light_user_polish.css` (light blue).

---

## PRIORITY 1 — Concurrency / stale-request race audit (highest correctness value)
Most async paths are now guarded (see "done" above). Re-run the audit for anything new or missed. For each
`%...>%`, `promises::then`, `%...!%`, `later::later`, and `tracked_future_promise` callback in `R/`, check:
does it mutate `values`/UI/`current_chat_id`/DB WITHOUT verifying the originating request is still current?
- `R/server_handler_summarization.R` fast-stream path → confirm request-id propagation to
  `handle_true_streaming_mode`.
- `R/module_file_preview.R`, `R/module_settings_yapilandirma.R`, `R/server_observers_startup.R`,
  `R/helpers_file_pipeline.R` (`summarize_file_with_llm` / `handle_file_upload_batch`) async callbacks —
  do late results mutate state for a file/flow the user already navigated away from?
- `R/module_tts.R` chunked synth — already `stop_generation`-guarded; confirm no other gap.
Reuse the existing pattern — do NOT invent a new abstraction. Prove each fix with a deterministic test
following `tests/testthat/test-async-handler-stale-request-race-behavior.R` and
`test-nonstreaming-handler-stale-request-race-behavior.R` (stub the worker to return
`promises::promise_resolve/reject`, flip the active request id, drain `later::run_now`).
DO NOT chase JavaScript "TOCTOU" claims — JS is single-threaded and the client races are already guarded.

## PRIORITY 2 — Parallel-path parity audit
Hunt for code paths that should do the same thing but diverge (the original skip-intro neural-color bug).
`R/module_startup_screen.R` skip-intro vs experience-mode vs `apply_experience_mode`,
`R/server_welcome_handlers.R` attached vs fresh welcome (both confirmed consistent last session — re-verify
only if you touch them), new-chat / saved-chat-load / quick-action entry into the welcome screen.

## PRIORITY 3 — Test isolation: keep EVERY test runnable standalone
Re-run the standalone scan (only `test-ui-asset-manifest-contract.R` should remain, and that's
environmental):
```r
for (f in list.files("tests/testthat", "^test-.*\\.R$")) {
  out <- system2("Rscript", c("-e", shQuote(sprintf(
    'library(testthat); r<-as.data.frame(test_file("tests/testthat/%s",reporter="silent")); cat(sum(r$error))', f))),
    stdout=TRUE, stderr=TRUE)
}
```
Any NEW standalone-ERROR test (e.g. after a future refactor moves a helper): find the REAL owner
(`grep -rn 'name <- function' R/`) and add an additive source-guard. Watch for "moved-by-refactor" traps.

## PRIORITY 4 — Working-directory-independent fallback guards
`server_runtime_context.R` and `helpers_claude_code_documents.R` are fixed. Audit every OTHER file that
source-loads a sibling helper via a `getwd()`-relative path inside a fallback guard (grep
`source(.*file.path("R"` and `source(.*"R/"` near a top-level `if (!exists(...))`). Make them try
repo-root / parent-dir / `tests/testthat` / `MERGEN_REPO_ROOT` candidates. Likely remaining suspects:
MCP bootstrap bridges (`helpers_mcp_*`), `config_sql_loader.R`, summarization helpers.

## PRIORITY 5 — Behavioral test coverage (the documented #1 weakness)
Drive the remaining untested top-level functions toward zero. Use the scan + technique catalog in
`.ai/next-session-test-coverage-prompt.md` (re-run the FIXED-string scan first — many UI builders and
admin renderers are now covered). Highest-value remaining clusters:
- Remaining admin `*_outputs` renderers via `shiny::testServer` (proven pattern in
  `test-admin-users-outputs-behavior.R`): genel_bakis, yz_performans, geri_bildirim_genel,
  sohbet_kalitesi, zaman_analizi, gelismis_analizler, yanit_analizi.
- `helpers_health_checks` / `helpers_health_runtime_checks` probes (mock `get_connection`/`httr`; assert
  the `health_result(...)` status/severity/remediation contract; never hit real DB/network).
- `helpers_destek_database` (mock DB), `helpers_llm_tool_formatters`, `helpers_image_gallery`
  (`get_image_thumbnail_base64`, `get_chat_title_for_image`), `config_sql_loader` `.sql_*`/`.read_sql_*`
  (source `R/library_queries.R` first, or `tryCatch(source(...))` past the top-level `stop()`).
- Module servers via `testServer`: `apiKeyServer`, `claudeCodePluginsServer` (+ `refresh_local_plugins`),
  `imageGalleryServer`, `module_performance` helpers. `aiExpertHandlersInit` is now testable via a wrapper
  (see `test-ai-expert-page-guidance-stale-behavior.R` for the pattern: `library(promises)`,
  `library(shiny)`, source `utils_common.R`+`helpers_ai_expert.R`, stub `tracked_future_promise` by
  task_type, mock `shinyjs::delay/runjs`, PRIME-THEN-SET `input$tabs`).
Every test must assert REAL input→output (no "exists" tests), be deterministic/OFFLINE, 0 fail / 0 warn
under `stop_on_warning=TRUE`, and run green BOTH standalone and in a `test_dir` batch.

## PRIORITY 6 — Maintainability headroom (do NOT regress the ratchet)
If a fix would push a near-limit file over its budget, extract a small focused helper into a new sourced
file (update `R/config_source_manifest.R` + order tests) rather than growing the dense file. Do NOT loosen
any threshold in `test-maintainability-ratchet.R`. **Known PRE-EXISTING ratchet failures on clean `main`**
(R 4.6 cloud checkout, NOT caused by recent work; the function-count regex counts 3 vs a locked budget of
2): `R/helpers_llm_worker_tool_results.R` and `R/helpers_llm_worker.R`. Leave them unless you are
deliberately asked to recalibrate that single file budget WITH a documented reason — do not loosen the
global thresholds.

## NEW CANDIDATE WEAKNESSES (investigate; pick the highest-value ones)
- **Image/vision pipeline (feature-shaped, optional):** images now upload but the LLM request payload
  never includes them. If (and only if) the deployed local model supports vision, wiring base64 image
  parts into the chat request (`R/server_send_message.R` / `helpers_llm_*`) would make uploaded images
  actually answerable. This is a real feature, not a quick fix — scope it carefully, gate behind a config
  flag, and do NOT regress the text path. If you do NOT build it, leave the current clean "not analyzed"
  note in place.
- **Duplicated allowed-extension lists / policy:** centralization improved this session
  (`fm_normal_allowed_extensions` is the single source for both upload paths). Grep for any other
  hardcoded extension whitelist that drifted and centralize it.
- **`showToast` duration plumbing:** R `showToast` now passes `duration` through; confirm no caller relies
  on the old fixed 3 s, and consider a contract test for the smart-duration JS (node-checkable).
- **Frontend duplicate-CSS-selector report:** `tests/scripts/frontend_maintainability_report.R` lists
  duplicate selectors — review for any genuine conflicts (not cosmetic).

---

## VALIDATION DISCIPLINE (be honest — this is graded)
- After EVERY new/edited test: `Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-X.R",
  reporter="summary")'` → require 0 FAIL / 0 WARN / 0 accidental SKIP, standalone AND in a `test_dir` batch.
- After any R edit: `Rscript tests/scripts/parse_sanity_check.R` and
  `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")` (expect only the 2 PRE-EXISTING
  failures above; confirm your files are NOT among them).
- After JS edits: `node --check <file>` if node is available; verify CRLF preserved.
- Run the repo gate: `bash tools/ai_validate.sh quick`. If app-source-smoke fails because the cloud
  checkout is missing vendored assets (`www/css/all.min.css`, `www/codemirror/*`, `www/lib/threejs/*`),
  SQL library files (`[SQL_LOADER] HATA: N adet SQL yüklenemedi`), or `.Renviron`, that is a PRE-EXISTING
  environment limitation — fall back to `bash tools/ai_validate.sh cloud-quick` and report it honestly
  (report `profile_requested`, `profile_effective`, `app_source_smoke_status`, `failed_steps`,
  `skipped_steps`, `db_sso_vm_validation_performed`, `sql_server_turkish_encoding_preflight_status`).
- The FULL strict suite (`tests/testthat.R`) will NOT complete in the cloud checkout for the same
  environmental reasons. Validate via per-file + targeted contract runs. Do NOT claim "full validation
  passed", "app booted", or "VM/SSO/DB/SQL-Server proven" unless the matching proof field actually says so.
- CRLF files (many `R/*.R`, all `www/css/*.css`, `www/js/*.js`): edit with a CRLF-preserving R
  `readLines()` + `writeBin(charToRaw(enc2utf8(paste(ls, collapse="\r\n"))), con)` script (preserve the
  original trailing-newline state so line counts don't drift), and verify `grep -c $'\r' file`. LF files
  can use normal edits.

## WHAT TO DELIVER
- Each real bug fixed surgically with a Turkish-commented explanation + a regression test that fails
  before / passes after.
- As many new green behavioral tests as you can for the remaining runtime/renderer/service-bound logic.
- Test-isolation and fallback-guard fixes that keep the suite robust to run order and working directory.
- A short, honest final report: weaknesses found, fixes applied, tests added (file + assertion counts),
  what you could NOT cover offline and why, and the exact validation commands you ran with their results.
- A NEW pull request from your fresh branch, Turkish commit messages.
- Update BOTH `.ai/next-session-eliminate-weaknesses-prompt.md` and
  `.ai/next-session-test-coverage-prompt.md` at the end so the NEXT session does not redo your work.

Begin by reading `CLAUDE.md` and `.ai/next-session-test-coverage-prompt.md`, then run the
untested-function scan and the standalone-test-isolation scan, show both lists, and work top-down by
priority — validating after every change.

# PROMPT — Eliminate ALL remaining weaknesses in MERGEN Bilge (fresh branch)

You are continuing hardening work on the **MERGEN Bilge** R/Shiny app. Your mission this session is to
**systematically eliminate as many remaining weaknesses as possible** — correctness, concurrency, test
coverage, test isolation, and production robustness — while preserving every UX and contract guarantee.

Read `CLAUDE.md` FIRST and in full. It is the binding operational guide and OVERRIDES default behavior:
surgical changes only, additive-only tests, Turkish comments with proper Turkish characters
(ç ğ ı İ ö ş ü — never Latinize), no CDN/heavy/browser deps, respect source-manifest order, encoding
boundaries, and the maintainability ratchet. Also read `.ai/next-session-test-coverage-prompt.md` for the
behavioral-test technique catalog and the up-to-date "already covered, do NOT redo" list.

## ⚠️ BRANCH / PR RULES (read carefully)
- Start with a **FRESH START on a brand-new branch**. Do **NOT** commit to, push to, or build on
  `claude/confident-wright-9crdA` (the previous session's branch) or any earlier session branch.
- If the harness assigns you a new branch, use it as-is. Otherwise create one, e.g.
  `claude/eliminate-weaknesses-*`. Base it on the latest `main` (or the latest merged state), NOT on
  `claude/confident-wright-9crdA`.
- Commit in small, themed commits with **Turkish** messages. When done, **open a NEW pull request**.
- Do NOT reopen or force-push any prior session branch/PR.

## WHAT'S ALREADY DONE (do NOT redo)
Session 3 on `claude/confident-wright-9crdA` already: fixed two server-side stale-request races
(image-gen + summarization non-streaming), fixed the `module_startup_screen.R` skip-intro
`updateNeuralColor` gap, made `helpers_claude_code_documents.R`'s extractor fallback guard
working-directory-independent, fixed 3 behavior tests that sourced the wrong helper after the
api-model tool-runtime split, and added 10 behavioral test files. Assume that branch is merged; if a
fix below is already present, skip it. Re-verify before duplicating.

---

## PRIORITY 1 — Concurrency / stale-request race audit (highest correctness value)
The true-streaming path is rigorously request-id-guarded (`mergen_is_current_request`,
`mergen_remove_typing_wrapper_if_safe`, `finalize_streaming(request_id=...)`). Audit EVERY OTHER async
path for the same staleness discipline. For each `%...>%`, `promises::then`, `%...!%`, `later::later`,
and `tracked_future_promise` callback in `R/`, check: does it mutate `values`/UI/`current_chat_id`
WITHOUT verifying the originating request is still current?

Concrete targets to verify (fix only if a real gap exists; some may already be guarded):
- `R/server_send_message.R` non-streaming branch (~lines 530–660): the `chat_id_val` snapshot is used
  in delayed callbacks — confirm a stale callback cannot log/persist into a newer chat. Add a
  `mergen_send_message_request_state(...)` re-check at each callback entry if missing.
- `R/server_handler_summarization.R` fast-stream path and any other handler that hands off to
  `handle_true_streaming_mode` — confirm request-id propagation.
- `R/module_proje_kaynak_analizi.R` / `R/helpers_deep_analysis.R` non-streaming LLM callbacks.
- `R/server_ai_expert_handlers.R`, `R/server_tts_handlers.R`: ensure no stale audio/subtitle callback
  reactivates after navigation/stop.
- Source-time side effects: confirm every timer/scheduler/observer created at file-source time has a
  once-only guard (grep for `later::later`, `invalidateLater`, `start_*_once`).

Reuse the existing pattern — do NOT invent a new abstraction. Prove each fix with a deterministic test
(stub the worker to return `promises::promise_resolve/reject`, flip the active request id, drain
`later::run_now`), following `tests/testthat/test-async-handler-stale-request-race-behavior.R`.

DO NOT chase JavaScript "TOCTOU" claims — JS is single-threaded; the client races (requestId in
streaming_manager, `_pendingRequestId` in music_manager, `lifecycleToken` in stt_client, audio-identity
checks) are already guarded. Only touch client JS if you find a concrete, reproducible defect.

## PRIORITY 2 — Parallel-path parity audit (find more "skip-intro vs experience-mode" bugs)
The startup neural-color bug was caused by two code paths that should do the same thing diverging. Hunt
for similar divergences and reconcile them (with a regression test):
- `R/module_startup_screen.R`: compare the `startup_skip_intro` path vs the `selected_experience_mode`
  path vs `apply_experience_mode` — every persona/theme/music/welcome message one sends, the other
  should send (unless intentionally different and commented).
- `R/server_welcome_handlers.R`: attached-welcome reboot path vs fresh-boot path (initModernWelcome /
  initPersonalGreeting / neural / video) — confirm parity (CLAUDE.md "Attached welcome-screen animation
  contract").
- New-chat / saved-chat-load / quick-action entry into the welcome screen — confirm consistent cleanup
  and re-init.

## PRIORITY 3 — Test isolation: make EVERY test runnable standalone
Tests that pass only inside the full suite (because an earlier file leaked a global) are fragile and
hide regressions. Find and fix them:
```r
# Run each test file in a FRESH child R session; collect the ones that ERROR standalone.
for (f in list.files("tests/testthat", "^test-.*\\.R$")) {
  out <- system2("Rscript", c("-e", shQuote(sprintf(
    'library(testthat); r<-as.data.frame(test_file("tests/testthat/%s",reporter="silent")); cat(sum(r$error))', f))),
    stdout=TRUE, stderr=TRUE)
  # nonzero error count with no real failure usually == missing-dependency / wrong-source isolation bug
}
```
For each isolation failure: find the REAL owner of the missing function (`grep -rn 'name <- function' R/`)
and make the test's source-guard load it. Watch for more "moved-by-refactor" cases like the api-model
tool-runtime split. Keep changes additive (guards only fire when the symbol is absent, so the full-suite
behavior is unchanged).

## PRIORITY 4 — Working-directory-independent fallback guards
`helpers_claude_code_documents.R` was fixed. Audit every OTHER file that source-loads a sibling helper
via a `getwd()`-relative path inside a fallback guard (grep `file.path("R"` / `source(` near top-level
`if (!exists(...))`). Make them try repo-root, `tests/testthat`, and `MERGEN_REPO_ROOT` candidates, per
the CLAUDE.md contract ("fallback source guards must be working-directory independent and warning-free").
Likely suspects: MCP bootstrap bridges, claude_code helpers, summarization, sql_loader.

## PRIORITY 5 — Behavioral test coverage (the documented #1 weakness)
Drive the remaining ~130 untested top-level functions toward zero. Use the scan + technique catalog in
`.ai/next-session-test-coverage-prompt.md`. Highest-value remaining clusters:
- Admin `*_outputs` renderers via `shiny::testServer` (stub `*_collect_data`/query fns; read `output$x`,
  parse highcharter JSON `$x$hc_opts$series`): genel_bakis, kullanici_analizi, yz_performans,
  geri_bildirim_genel, sohbet_kalitesi, zaman_analizi, gelismis_analizler, yanit_analizi.
- `helpers_health_checks` probes (mock `get_connection`/`httr`; assert `health_result` status/severity/
  remediation; never hit real DB/network).
- `helpers_destek_database` (mock DB), `helpers_llm_tool_formatters`, `helpers_image_gallery`
  (`get_image_thumbnail_base64`, `get_chat_title_for_image`), `config_sql_loader` `.sql_*`/`.read_sql_*`.
- Module servers via `testServer`: `apiKeyServer`, `claudeCodePluginsServer`, `imageGalleryServer`,
  `module_performance` helpers. Remaining UI builders: `historyUI`, `savedChatsUI`, `imageGalleryUI`,
  `healthUI`, api-key-choice card builders.
Every test must assert REAL input→output (no "exists" tests), be deterministic/OFFLINE, 0 fail / 0 warn
under `stop_on_warning=TRUE`, and run green BOTH standalone and in a `test_dir` batch.

## PRIORITY 6 — Maintainability headroom (do NOT regress the ratchet)
`R/module_claude_code.R`, `R/server_send_message.R`, `R/module_admin_*`, `R/helpers_llm_sse.R` and other
near-limit files have little headroom. If a Priority-1..4 fix would push a file over its budget, extract
a small focused helper into a new sourced file (update `R/config_source_manifest.R` + order tests) rather
than growing the dense file. Do NOT loosen any threshold in `test-maintainability-ratchet.R`.

---

## VALIDATION DISCIPLINE (be honest — this is graded)
- After EVERY new/edited test: `Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-X.R",
  reporter="summary")'` → require 0 FAIL / 0 WARN / 0 accidental SKIP, standalone AND in a `test_dir`
  batch. Use `new.env(parent=globalenv())` isolation.
- After any R edit: `Rscript tests/scripts/parse_sanity_check.R` and
  `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")`.
- Run the repo gate: `bash tools/ai_validate.sh quick`. If app-source-smoke fails because the cloud
  checkout is missing vendored assets (`www/css/all.min.css`, `www/codemirror/*`, `www/lib/threejs/*`),
  SQL library files (`[SQL_LOADER] HATA: N adet SQL yüklenemedi`), or `.Renviron`, that is a PRE-EXISTING
  environment limitation — fall back to `bash tools/ai_validate.sh cloud-quick` and report it honestly.
- The FULL strict suite (`tests/testthat.R`) will NOT complete in the cloud checkout for the same
  environmental reasons. Validate via per-file + targeted contract runs. Do NOT claim "full validation
  passed", "app booted", or "VM/SSO/DB/SQL-Server proven" unless the matching proof field actually says so.
- CRLF files: edit with a CRLF-preserving R `readLines/writeLines(sep="\r\n", useBytes=TRUE)` script and
  verify `grep -c $'\r' file == wc -l`. LF files can use normal edits.

## WHAT TO DELIVER
- Each real bug fixed surgically with a Turkish-commented explanation + a regression test that fails
  before / passes after.
- As many new green behavioral tests as you can for the remaining runtime/renderer/service-bound logic.
- Test-isolation and fallback-guard fixes that make the suite robust to run order and working directory.
- A short, honest final report: weaknesses found, fixes applied, tests added (file + assertion counts),
  what you could NOT cover offline and why, and the exact validation commands you ran with their results.
- A NEW pull request from your fresh branch, Turkish commit messages.

Begin by reading `CLAUDE.md` and `.ai/next-session-test-coverage-prompt.md`, then run the
untested-function scan and the standalone-test-isolation scan, show both lists, and work top-down by
priority — validating after every change.

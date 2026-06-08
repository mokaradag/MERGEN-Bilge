# PROMPT — Eliminate ALL remaining weaknesses in MERGEN Bilge (fresh branch)

You are continuing hardening work on the **MERGEN Bilge** R/Shiny app. Your mission this session is to systematically and thoroughly eliminate as many remaining weaknesses as possible — correctness, concurrency, stale-request races, test coverage, test isolation, production robustness, and UX consistency — while preserving every UX and contract guarantee.

Read `CLAUDE.md` FIRST and in full. It is the binding operational guide and overrides default behavior: surgical changes only, additive-only tests, Turkish comments with proper Turkish characters (ç ğ ı İ ö ş ü — never Latinize), no CDN/heavy/browser dependencies, respect source-manifest order, encoding boundaries, and the maintainability ratchet.

Also read `.ai/next-session-test-coverage-prompt.md` for the behavioral-test technique catalog and the up-to-date "already covered, do NOT redo" list.

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
# PROMPT — Meaningful and Safe Improvements in MERGEN Bilge

You are continuing hardening work on the **MERGEN Bilge** R/Shiny app.

Your mission is **not** to make tiny cosmetic splits, line-count games, or low-value helper extractions.

Your mission is to deliver **meaningful, safe, evidence-based gains** while preserving every UX, security, encoding, source-order, asset-order, and validation contract.

A meaningful gain must do at least one of the following:

* Fix a real reproducible failure.
* Remove or substantially reduce a real runtime, validation, concurrency, stale-request, security, source-order, asset-order, frontend lifecycle, or maintainability risk.
* Reduce a whole complexity cluster, not just move a few lines.
* Turn important untested behavior into deterministic, offline coverage.
* Improve frontend modularity or handler density in a way that lowers future defect risk.
* Make validation more reliable, more diagnostic, or more honest.
* Remove stale risk documentation only after code/tests prove the risk is actually closed.

Do **not** do tiny splits just because a file is long.
A one-function helper extraction is acceptable only if it protects a real boundary, fixes a real issue, enables better tests, or removes meaningful fragility.

---

## 1. Required Reading

Start by reading, in this order:

1. `CLAUDE.md`
2. `AGENTS.md`
3. `.ai/next-session-eliminate-weaknesses-prompt.md`
4. `.ai/next-session-test-coverage-prompt.md`
5. `docs/refactor-log.md`
6. `docs/feature-ownership-map.md`
7. `docs/architecture-map.md`
8. `docs/technical-reference.md`
9. `RUNBOOK.md`
10. `tests/testthat/test-maintainability-ratchet.R`
11. `tests/testthat/test-frontend-maintainability-ratchet.R`

`CLAUDE.md` is binding. It overrides default behavior.

Preserve:

* Turkish characters: ç ğ ı İ ö ş ü
* UTF-8 integrity
* no mojibake
* no CDN/runtime network dependencies
* source-manifest order
* frontend asset order
* DB encoding boundaries
* SSO/JWT fail-closed behavior
* secret-safe logs/artifacts
* maintainability and frontend ratchets

---

## 2. Start from Evidence, Not Memory

Before editing code, run or inspect:

```sh
git status
git diff --stat
LANG=C.UTF-8 LC_ALL=C.UTF-8 Rscript tests/scripts/maintainability_report.R
LANG=C.UTF-8 LC_ALL=C.UTF-8 Rscript tests/scripts/frontend_complexity_doctor.R
LANG=C.UTF-8 LC_ALL=C.UTF-8 Rscript tests/scripts/seam_doctor.R
```

If relevant, also inspect recent validation artifacts under:

```text
artifacts/ai-validation/
artifacts/frontend-complexity-doctor/
artifacts/post-deploy-smoke/
artifacts/vm-evidence/
```

Do not assume the old handoff is current. Verify.

---

## 3. Current Known State — Do Not Redo Without Fresh Evidence

The following work is already completed. Do not redo it unless fresh evidence proves a regression:

### Frontend / UI Assets

* `R/config_ui_assets.R` split into DATA / VALIDATORS / RENDER:

  * `R/config_ui_assets.R`
  * `R/config_ui_asset_validators.R`
  * `R/config_ui_asset_tags.R`
* Frontend zone DATA / VALIDATOR split:

  * `R/config_ui_asset_zones.R`
  * `R/config_ui_asset_zone_validators.R`
* AI Expert frontend handler split:

  * `www/js/ai_expert_manager.js`
  * `www/js/ai_expert_handlers.js`
* Support CSS split.
* Admin renderer output splits.

### Runtime / R Structure

* `R/server_runtime_context.R` auth-ready / refreshable-module split:

  * `R/server_runtime_auth_ready.R`
* `R/server_handler_true_streaming.R` worker-globals extraction:

  * `R/helpers_llm_true_streaming_worker.R`
* `R/server_send_message.R` TTS streaming handler extraction:

  * `R/server_handler_streaming_tts.R`
* `R/helpers_claude_code_documents.R` document-summary extraction:

  * `R/helpers_claude_code_document_summary.R`
* DB chat-read query split:

  * `R/helpers_db_chat_read_queries.R`
  * `R/helpers_db_chat_readers.R`
* File Manager runtime splits:

  * `R/helpers_file_manager_delete_runtime.R`
  * `R/helpers_file_manager_upload_runtime.R`
* Startup screen UI/server split.
* Image generation UI split.
* Settings Yapılandırma advanced UI split.

### Evidence / Health

* Post-deploy smoke artifact flow is complete:

  * producer
  * secret-safe JSON
  * reader
  * health UI card
* Release evidence includes:

  * VM evidence
  * AI validation
  * post-deploy smoke
  * log health summaries
  * AI latency summaries
  * error context summaries

### Vision

Vision is user-confirmed as live-verified on the Windows VM. Do not treat vision as an unresolved top priority unless you modify the vision path.

Preserve:

* text-only fallback
* `MERGEN_ENABLE_VISION=false` kill switch
* explicit Turkish note for non-vision models
* capability-primary model detection
* real image-input model support

---

## 4. Current Best Direction

Use fresh reports to choose the package, but current evidence suggests the next meaningful work is likely in one of these areas:

### A. Fix a real validation blocker

If `bash tools/ai_validate.sh full --boot-smoke` still fails because of reproducible Shiny destroyed-reactive isolation failures, stale reactive access, broken teardown, or test-order pollution, this is a high-value package.

Known recent suspects to re-verify:

* `test-chat-actions-behavior.R`
* `test-image-gallery-observers-behavior.R`

Rules:

* Reproduce the failure first.
* Fix root cause.
* Do not skip, weaken, quarantine, or mark tests as expected failures.
* Add regression coverage so the failure cannot return.
* If the issue is environment-only, document the boundary precisely.

### B. Frontend Deep Space package

Likely target:

* `www/js/deep_space_intro.js`

Choose this only if `frontend_complexity_doctor.R` still shows it as a top app-owned JS risk.

Look for a real complexity cluster:

* scene lifecycle
* render loop
* requestAnimationFrame ownership
* cleanup/disposal
* resize handling
* Three.js object ownership
* shader/solar orchestration
* startup-mode state
* local/offline asset assumptions

Do not merely move a small helper.

Preserve:

* visual behavior
* local Three.js usage
* offline/no-CDN behavior
* exact manifest/deferred order
* startup screen UX

If new JS/CSS files are added, update:

* `R/config_ui_assets.R`
* `R/config_ui_asset_zones.R`
* relevant frontend manifest/zone tests

### C. Frontend handler-density package

Possible targets, if fresh reports confirm:

* `www/js/shiny_message_handlers.js`
* `www/js/claude_code.js`
* any app-owned JS file with high Shiny handler/event density

Goal:

* reduce handler concentration
* clarify lifecycle ownership
* avoid duplicated global state
* make future defects less likely

Preserve:

* Shiny message names
* public APIs
* load order
* event delegation behavior
* saved-chat behavior
* TTS/STT/audio lifecycle behavior where relevant

### D. CSS density / cascade package

Possible targets, if fresh reports confirm:

* `theme_light_core.css`
* `theme_light_pages.css`
* other largest app-owned CSS files

Rules:

* Do not split CSS cosmetically.
* Preserve cascade order exactly.
* Do not reintroduce old light-theme patch chains.
* Preserve zero-dead-selector discipline.
* Add/adjust selector and frontend ratchet coverage.

### E. R-side fallback package

Choose R-side complexity work only if fresh reports show a real top risk.

Do not chase low-priority flat renderer files just because they are large.

Possible R-side target only if confirmed:

* `R/helpers_claude_code_process.R`

Rules:

* Extract a coherent runtime boundary, not a tiny helper.
* Preserve Windows/UNC behavior.
* Preserve CLI/processx boundaries.
* Preserve Bilge Yolaç security/path contracts.
* Add deterministic processx/mock tests if behavior changes or becomes easier to cover.

---

## 5. Package Selection Bar

Before editing code, write a short internal package selection note:

```text
Selected package:
Evidence:
Why this is meaningful:
Why this is safer/better than a tiny split:
Behavior/contracts to preserve:
Tests/validation that will prove the gain:
Risk boundary:
```

Pick **one** substantial package.

Do not mix unrelated areas.

A good package normally includes:

* code changes,
* focused tests,
* discovery report updates,
* documentation/handoff updates.

A docs-only package is acceptable only when stale documentation is actively steering future work in the wrong direction.

---

## 6. Hard Constraints

Never violate these:

* Do not Latinize Turkish text.
* Do not introduce mojibake.
* Do not weaken DB encoding, visible-vs-technical normalization, Unicode escape/restore, mailto encoding, JSON/log/browser text boundaries, or MB_Messages post-insert guards.
* Do not weaken SSO/JWT fail-closed behavior.
* Do not expose secrets, API keys, tokens, DSNs, auth headers, private endpoints, real user paths, or credentials.
* Do not generate `renv.lock` from Linux/cloud/Codex sessions.
* Do not run `renv::restore()` on the production VM without user approval.
* Do not bypass or loosen `R/config_source_manifest.R`.
* Do not bypass or loosen frontend asset order protections.
* Do not add CDN/runtime network dependencies.
* Do not raise maintainability/frontend ratchets to pass tests.
* Do not claim VM, browser, DB, SSO, SQL Server, live endpoint, app boot, full validation, or soak proof unless the relevant command actually ran and passed.

---

## 7. Durable Gotchas

Keep these lessons. They are still useful.

### Encoding / locale

Use this for R scripts that read/write Turkish or CRLF-sensitive files:

```sh
LANG=C.UTF-8 LC_ALL=C.UTF-8
```

Avoid:

* `toupper(enc2utf8(...))` with Turkish text.
* locale-dependent case conversion for security checks.
* rewriting Turkish files under C/POSIX locale.

Prefer:

* ASCII marker checks where possible.
* `grepl(..., ignore.case = TRUE, perl = TRUE, useBytes = TRUE)` for ASCII security keywords.
* byte-safe scanning for repo-wide tests.

### Windows / paths

Do not create test files with Windows-invalid characters:

```text
< > : " | ? *
```

Do not rely on raw `getwd()` prefix equality across Windows UNC paths.

Prefer:

* `normalizePath(..., winslash = "/")`
* `endsWith(...)` for suffix checks
* `withr::local_tempdir()` instead of fake absolute paths such as `/repo/kok`

### Shiny tests

For `observeEvent(..., ignoreInit = TRUE)`, use PRIME-THEN-SET:

```r
session$setInputs(x = 1)
session$setInputs(x = 2)
```

For destroyed-reactive/test teardown failures:

* reproduce in focused and batch context,
* check stale observers,
* check reactive access after session destruction,
* fix lifecycle/teardown root cause,
* do not silence the failure.

### Frontend reports

`Shiny.addCustomMessageHandler(...)` counts as both event and Shiny handler.

If splitting handlers:

* keep message names unchanged,
* delegate to the existing manager/state owner,
* do not duplicate state-machine logic.

AI Expert gotcha:

* media/audio frontend zone key is `ses_yasam_dongusu`.
* `ai_expert_handlers.js` should call `getManager()` at call time and delegate to `window.AIExpertManager`.

### Maintainability reports

The R maintainability report counts assigned functions matching roughly:

```text
(<-|=)\s*function\s*\(
```

Inline handlers such as `error = function(e)` count.

Avoid adding many assigned/inline handlers in near-budget files.

### Post-deploy smoke

Do not redact serialized JSON text.

Redact string values structurally before serialization. Preserve keys, counts, enum fields, and identity/status scalars.

If evaluating a data frame of health checks, convert rows to records first. Do not iterate a data frame directly with `for (x in df)`.

### True SSE worker globals

`mergen_true_streaming_worker_globals()` resolves global helpers by name at call time. Only call it where the real runtime globals exist, or stub them deliberately in isolated tests.

---

## 8. Frontend Rules

If touching JS/CSS:

1. Inspect:

   * `R/config_ui_assets.R`
   * `R/config_ui_asset_validators.R`
   * `R/config_ui_asset_tags.R`
   * `R/config_ui_asset_zones.R`
   * `R/config_ui_asset_zone_validators.R`

2. Preserve load order unless tests prove the new order is equivalent.

3. If adding/splitting frontend files, update:

   * asset manifest,
   * deferred group,
   * frontend zone ownership,
   * manifest/zone tests.

4. Preserve offline/local assumptions.

5. Run syntax checks if available:

```sh
node --check path/to/file.js
```

6. Re-run frontend discovery:

```sh
LANG=C.UTF-8 LC_ALL=C.UTF-8 Rscript tests/scripts/frontend_complexity_doctor.R
```

7. Tighten frontend budgets only after behavior is preserved and the reduction is real.

---

## 9. R Runtime Rules

If adding an R file:

1. Update `R/config_source_manifest.R`.
2. Update bootstrap/source-order contracts as needed.
3. Update `tests/testthat/helper_bootstrap.R` if tests need the file.
4. Update seam ownership only if the new test is a real production guard.
5. Add focused behavior/contract tests.
6. Re-run source manifest and maintainability tests.

Keep Shiny modules focused on:

* observers,
* reactive wiring,
* UI side effects.

Move only coherent boundaries:

* pure decision logic,
* formatting,
* validation,
* deterministic orchestration,
* repeated lifecycle transitions.

Do not split just because a block is long.

---

## 10. Validation Discipline

Always run focused tests for the changed area.

For a changed test file:

```sh
Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-X.R", reporter = "summary")'
```

For R edits:

```sh
Rscript tests/scripts/parse_sanity_check.R
Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-maintainability-ratchet.R", reporter = "summary")'
```

For source/manifest changes:

```sh
Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-source-manifest-contract.R", reporter = "summary")'
Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-source-manifest-sections-contract.R", reporter = "summary")'
```

For frontend changes:

```sh
LANG=C.UTF-8 LC_ALL=C.UTF-8 Rscript tests/scripts/frontend_complexity_doctor.R
Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-frontend-maintainability-ratchet.R", reporter = "summary")'
Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-ui-asset-manifest-contract.R", reporter = "summary")'
```

For seam/source/asset ownership changes:

```sh
LANG=C.UTF-8 LC_ALL=C.UTF-8 Rscript tests/scripts/seam_doctor.R
```

Run the repo gate:

```sh
bash tools/ai_validate.sh quick
```

For risky runtime, source-order, frontend asset, SSO, DB, file lifecycle, streaming, Bilge Yolaç, security-path, or validation changes, also run if supported:

```sh
bash tools/ai_validate.sh full --boot-smoke
```

If the cloud environment blocks full proof, say so clearly.

Report:

* command run,
* artifact path,
* failed steps,
* skipped steps,
* whether browser smoke ran or skipped,
* whether VM/DB/SSO/SQL Server proof exists.

Do not convert skipped proof into success.

---

## 11. What to Deliver

Deliver a package that has a clear before/after story.

Final response must include:

```text
Package completed:
Why this was meaningful:
Main risk reduced or failure fixed:
Files changed:
Before/after complexity or evidence impact:
Tests added/updated:
Validation actually run:
Validation failed/skipped and why:
Docs/handoff updated:
Remaining risks:
Best next meaningful target:
```

Be explicit if any of these were **not** proven:

* VM
* browser
* DB
* SSO
* SQL Server Turkish encoding
* live endpoint
* full strict suite
* soak/load behavior

---

## 12. Documentation Updates Required

At the end of the session, update only what is relevant.

Always update:

1. `.ai/next-session-eliminate-weaknesses-prompt.md`

   Keep it short. Do not paste long historical logs.

   Include:

   * what was just completed,
   * why it mattered,
   * what not to redo,
   * exact validation results,
   * gotchas discovered,
   * best next meaningful targets.

2. `docs/refactor-log.md`

   Add a dated package entry:

   * package selected and why,
   * evidence used,
   * files changed,
   * before/after metrics,
   * behavior preserved,
   * tests added/updated,
   * validation commands and results,
   * skipped/failed proof,
   * next targets.

3. `docs/feature-ownership-map.md`

   Update affected feature/seam sections:

   * helper/test ownership,
   * resolved risks,
   * current next targets.

Update only if applicable:

* `docs/architecture-map.md`
* `docs/technical-reference.md`
* `RUNBOOK.md`
* `.ai/next-session-test-coverage-prompt.md`
* `CLAUDE.md`
* `AGENTS.md`

Do not modify `CLAUDE.md` or `AGENTS.md` unless the coding-agent contract itself changed.

---

## 13. Branch / PR Rules

Start from a fresh branch based on the latest `origin/main` or the harness-provided branch.

Do not reuse old session branches.

Commit in small, themed commits with Turkish commit messages.

Open a new pull request with a Turkish description.

Do not force-push or reopen an old PR unless the user explicitly asks.

---

## 14. First Action

Begin by reading the required files and running the discovery commands.

Then choose one meaningful package based on current evidence.

Do not start with a tiny split.

Do not start with stale historical priorities.

Do not start with work that the handoff says is already complete.
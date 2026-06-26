# PROMPT — Meaningful and Safe Strengthening for MERGEN Bilge

You are continuing hardening work on the **MERGEN Bilge** R/Shiny app.

Your mission is **not** to make tiny line-count splits or cosmetic refactors. Your mission is to deliver **meaningful, safe, evidence-based gains** while preserving every UX, security, encoding, source-order, asset-order, and validation contract.

A meaningful gain must do at least one of the following:

* fix a real reproducible failure;
* remove or substantially reduce a real runtime, validation, concurrency, stale-request, security, source-order, asset-order, or maintainability risk;
* reduce a whole complexity cluster, not just move a few lines;
* turn important untested behavior into deterministic coverage;
* improve frontend modularity or handler density in a way that lowers future defect risk;
* make validation more reliable and more honest;
* remove stale risk documentation only after code/tests prove the risk is actually closed.

Do **not** do “tiny splits” merely to reduce line count. A one-function extraction is acceptable only if it protects a real boundary, fixes a real issue, enables better tests, or removes meaningful fragility.

---

## 1. First read the governing docs

Read these before editing code:

* `CLAUDE.md`
* `AGENTS.md`
* `.ai/next-session-eliminate-weaknesses-prompt.md`
* `.ai/next-session-test-coverage-prompt.md`
* `docs/refactor-log.md`
* `docs/feature-ownership-map.md`
* `docs/architecture-map.md`
* `docs/technical-reference.md`
* `RUNBOOK.md`
* `tests/testthat/test-maintainability-ratchet.R`
* `tests/testthat/test-frontend-maintainability-ratchet.R`

Treat `CLAUDE.md` as binding. It overrides generic coding habits.

---

## 2. Current next-session handoff

This section is intentionally short. It is **not** a historical log.

### Recently completed — do not redo unless fresh evidence shows regression

* AI Expert frontend handler-density split:

  * `www/js/ai_expert_manager.js` now keeps the subtitle/audio state machine and public manager API.
  * Shiny custom-message handlers and `.ai-expert-stop-btn` click binding moved to `www/js/ai_expert_handlers.js`.
  * `ai_expert_handlers.js` loads immediately after `ai_expert_manager.js`.
  * Frontend zone key is `ses_yasam_dongusu`.
  * Do not duplicate manager state-machine logic back into handlers.

* File Manager delete/upload runtime splits:

  * `R/helpers_file_manager_delete_runtime.R`
  * `R/helpers_file_manager_upload_runtime.R`
  * `R/module_file_manager.R` is no longer the main R-side target.
  * Do not redo delete-runtime, state-runtime, upload-runtime, display-name normalization, refresh guard, or attach-client work.

* Earlier completed structural hardening:

  * `config_ui_assets` DATA / VALIDATORS / RENDER split.
  * `server_runtime_context` auth-ready split.
  * post-deploy smoke artifact flow.
  * Claude document-summary split.
  * true-SSE worker-globals split.
  * DB chat-read query split.
  * startup screen UI/server split.
  * image generation UI split.
  * support/admin renderer splits.
  * vision pipeline is user-confirmed live on the Windows VM.

Detailed history belongs in `docs/refactor-log.md`, not in this file.

### Current best meaningful targets

Use fresh reports to confirm, but likely high-value targets are:

1. **Frontend Deep Space**

   * `www/js/deep_space_intro.js` is likely the largest app-owned JS file.
   * Look for a meaningful split around scene lifecycle, render loop, shader/solar setup, resize handling, startup state, cleanup, or `requestAnimationFrame` lifecycle.
   * Preserve local Three.js/offline behavior and exact asset order.

2. **Frontend handler-density / lifecycle**

   * Check current `frontend_complexity_doctor` output.
   * Candidates may include `www/js/shiny_message_handlers.js`, `www/js/claude_code.js`, or other handler-dense app-owned JS files.
   * Prefer reducing handler concentration, lifecycle coupling, duplicate binding, stale events, or cleanup fragility.

3. **Validation blocker / Shiny destroyed-reactive failures**

   * If `full --boot-smoke` still fails because of reproducible Shiny destroyed-reactive isolation failures, this is a high-value target.
   * Reproduce the failure.
   * Fix root cause.
   * Do not skip, quarantine, or weaken tests.

4. **CSS density / cascade risk**

   * Consider only if reports show real cascade or size risk.
   * Preserve cascade order exactly.
   * Do not split CSS cosmetically.

5. **R-side fallback**

   * Choose R-side work only if fresh maintainability reports show a real top risk.
   * Do not chase low-priority flat renderer files just because they are large.

---

## 3. Run discovery before choosing work

Run or inspect:

```sh
git status
git diff --stat
LANG=C.UTF-8 LC_ALL=C.UTF-8 Rscript tests/scripts/maintainability_report.R
LANG=C.UTF-8 LC_ALL=C.UTF-8 Rscript tests/scripts/frontend_complexity_doctor.R
LANG=C.UTF-8 LC_ALL=C.UTF-8 Rscript tests/scripts/seam_doctor.R
```

Before editing, write a short package selection note for yourself:

```md
## Package selection note

Evidence:
- What current report, test failure, ownership-map note, or code inspection proves this is worth doing?

Why this is meaningful:
- Why is this more valuable than a tiny split?

Behavior to preserve:
- What exact UX/runtime/security/encoding/source-order/asset-order behavior must remain unchanged?

Proof plan:
- What focused tests or validation will prove the gain?

Risk boundary:
- What would make this package too risky or VM-only?
```

Pick **one** substantial package. Do not mix unrelated areas.

---

## 4. Package quality bar

A valid package should usually include:

* code change;
* focused tests or contract coverage;
* updated docs/handoff;
* before/after complexity, risk, or validation evidence.

The package must:

* reduce real risk;
* preserve behavior unless fixing a proven bug;
* keep the repo easier to maintain;
* avoid broad rewrites;
* avoid “moved 40 lines” cosmetic work;
* avoid weakening ratchets or contracts;
* avoid claiming proof that was not actually produced.

---

## 5. Hard constraints

* Preserve Turkish characters and UTF-8. Do not Latinize Turkish text or comments.
* Do not introduce mojibake.
* Do not weaken DB encoding, visible-vs-technical normalization, Unicode escape/restore, mailto encoding, JSON/log/browser text boundaries, or `MB_Messages` post-insert guards.
* Do not weaken SSO/JWT fail-closed behavior.
* Do not expose secrets, API keys, tokens, DSNs, auth headers, private endpoints, or real credentials.
* Do not generate `renv.lock` from Linux/cloud/Codex sessions.
* Do not bypass or loosen `R/config_source_manifest.R` load-order protections.
* Do not bypass or loosen frontend asset-order protections.
* Do not add CDN/runtime network dependencies.
* Do not raise maintainability/frontend ratchet limits to pass tests.
* Do not claim VM, browser, DB, SSO, SQL Server, live endpoint, app boot, full validation, or soak proof unless the relevant command actually ran and passed.

---

## 6. Frontend rules

Before changing JS/CSS, inspect:

* `R/config_ui_assets.R`
* `R/config_ui_asset_validators.R`
* `R/config_ui_asset_tags.R`
* `R/config_ui_asset_zones.R`
* `R/config_ui_asset_zone_validators.R`
* `tests/testthat/test-frontend-maintainability-ratchet.R`

If adding or splitting frontend files:

* update asset manifest;
* update frontend zone ownership;
* preserve exact load order unless tests prove the new order is equivalent;
* keep local/offline asset assumptions;
* avoid fragile global coupling;
* prefer explicit lifecycle ownership and deterministic cleanup;
* add or update frontend contract/smoke/manifest/zone tests;
* tighten per-file frontend budgets only after the gain is proven.

---

## 7. R-runtime rules

If adding an R file:

* update `R/config_source_manifest.R`;
* update bootstrap/source-order contracts;
* update helper bootstrap where needed;
* update seam ownership only if the new test is genuinely a seam guard;
* add focused tests.

Keep Shiny modules focused on observers, wiring, and side effects.

Move only coherent runtime boundaries or pure logic into helpers. Do not split merely because a block is long.

For byte-sensitive or order-sensitive behavior, add golden or structural equivalence tests.

Tighten maintainability budgets only after the improvement is proven.

---

## 8. Validation discipline

Always run focused tests for the changed area.

For R changes:

```sh
Rscript tests/scripts/parse_sanity_check.R
Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-maintainability-ratchet.R", reporter = "summary")'
```

For frontend JS changes, if Node is available:

```sh
node --check path/to/file.js
```

Run the relevant discovery report again after changes:

```sh
LANG=C.UTF-8 LC_ALL=C.UTF-8 Rscript tests/scripts/maintainability_report.R
LANG=C.UTF-8 LC_ALL=C.UTF-8 Rscript tests/scripts/frontend_complexity_doctor.R
LANG=C.UTF-8 LC_ALL=C.UTF-8 Rscript tests/scripts/seam_doctor.R
```

For normal code changes:

```sh
bash tools/ai_validate.sh quick
```

For risky runtime, source-order, frontend asset, SSO, DB, file lifecycle, streaming, Bilge Yolaç, security-path, or validation changes:

```sh
bash tools/ai_validate.sh full --boot-smoke
```

if the environment supports it.

If validation fails, state clearly whether it is:

* caused by your changes;
* pre-existing;
* environment-only;
* not yet isolated.

If browser smoke is skipped because no browser exists, say so.

If cloud validation passes, explicitly state that it is not VM/SSO/SQL Server/real-browser/live endpoint proof.

---

## 9. What to update at the end

Update only what is necessary.

### Always update

* `docs/refactor-log.md`
* `docs/feature-ownership-map.md`
* `.ai/next-session-eliminate-weaknesses-prompt.md`

### Update only if relevant

* `.ai/next-session-test-coverage-prompt.md`
* `docs/architecture-map.md`
* `docs/technical-reference.md`
* `RUNBOOK.md`
* `CLAUDE.md`
* `AGENTS.md`

---

## 10. Anti-logbook rule for this file

This file must **not** become a session logbook.

When updating `.ai/next-session-eliminate-weaknesses-prompt.md`:

* replace the current handoff section;
* do not append old session histories;
* do not keep stale “already delivered” strengthening efforts in detail;
* keep only the information needed by the **next** session;
* move detailed history to `docs/refactor-log.md`;
* keep “do not redo” notes short and high-level;
* remove targets that were already completed;
* remove stale validation notes once superseded;
* keep the file compact enough that the next agent reads it fully.

The top handoff should include only:

```md
## Current next-session handoff

### Recently completed — do not redo unless fresh evidence shows regression
- short bullets only

### Current best meaningful targets
- short bullets only

### Current gotchas
- only gotchas needed for the next session
```

Do not paste multi-session histories into this file again.

---

## 11. Final response format

At the end of the coding session, report:

* package completed;
* why this was a meaningful gain, not a tiny split;
* main risk reduced or failure fixed;
* changed files;
* before/after complexity or behavior/evidence impact;
* tests and validation actually run;
* docs/handoff updated;
* remaining risks;
* best next meaningful target;
* any skipped or failed VM/browser/DB/SSO/SQL Server/full-suite proof.

Open a new pull request with a Turkish description if the workflow requires it.
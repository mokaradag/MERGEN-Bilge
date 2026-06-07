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

### ✅ THIS LATEST SESSION (`claude/exciting-einstein-JGkKQ`) — open PR
**VISION FINISHED (PRIORITY 0 — config + capability-primary gating + live-serialize proof):**
- `R/config_api.R`: every `local_model_capabilities` entry now carries a per-model
  `vision` attribute (default FALSE), driven by a NEW pure helper
  `R/helpers_vision_model_capabilities.R` (manifest BEFORE `config_api.R`):
  `parse_vision_models_env` (splits `MERGEN_VISION_MODELS` on `;`/`,` ONLY — model
  IDs may contain spaces, so do NOT split on whitespace) and
  `apply_vision_model_capabilities(api_config, extra_vision_models, env_value)`
  (normalizes vision=FALSE on all caps, then sets TRUE for env list + caller extras).
  `config_api.R` calls it via a guarded `if (exists("apply_vision_model_capabilities", ...))`
  with `extra_vision_models = c(coding_deep_low_model, coding_deep_high_model)` (Kodlama
  Uzmanı deep models support Image Input per the model catalog). **config_api.R stayed at
  its EXACT 700-line per-file ratchet budget** (extracted to the helper + trimmed one
  redundant comment to net-zero — the budget in `test-maintainability-ratchet.R` is OFF-LIMITS).
- `mergen_vision_enabled()` flipped to a **capability-primary kill-switch**: default ENABLED,
  disabled ONLY by an explicit false value (`false`/`f`/`0`/`no`/`off`/`hayır`/`kapalı`) on
  `options(mergen.vision_enabled)` or `MERGEN_ENABLE_VISION`. So marking a model
  `vision = TRUE` is now SUFFICIENT to enable vision for it; non-capable models still get the
  explicit Turkish "analiz edilemiyor" note (text path byte-identical).
- Confirmed the multimodal `image_url` array survives serialization through the REAL
  `call_local_llm` (httr `encode="json"`) AND `call_local_llm_sse_worker` (curl `postfields`
  `toJSON(auto_unbox=TRUE)`) — body-capture tests, not just an isolated toJSON.
- Tests: updated `test-vision-context-behavior.R` (default-ON semantics; OFF cases now use
  explicit FALSE or a non-vision model), NEW `test-vision-model-capabilities-behavior.R`
  (helper), NEW `test-vision-llm-payload-serialization-behavior.R` (real API+SSE body capture).
  All green standalone + batch (109 + 17 assertions).
- **REMAINING for next session (VM-only):** decide which deployed model IDs actually support
  Image Input, set `MERGEN_VISION_MODELS=...` (and/or rely on the CODING_DEEP_* defaults) in
  `.Renviron`, then send a real image + question and confirm an end-to-end answer (the
  base64→HTTP-body path is real but still UNTESTED against a live vision endpoint). Optionally
  add a Yapılandırma toggle + `max_bytes` config.

**KNOWN pre-existing failure #2 RESOLVED (ratchet-contract):** bumped ONLY the two per-file
baselines in `test-maintainability-ratchet-contract.R` to real measured values
(`module_startup_screen.R` 695→740 lines / 5→6 fns; `helpers_ai_expert.R` 619→662 lines /
19→23 fns) with a Turkish comment. This is the per-file baseline's intended maintenance; the
GLOBAL ratchet (`test-maintainability-ratchet.R`) was NOT touched (still 100/100).

**KNOWN cloud-only failure RESOLVED (network-boundary):** allowlisted the redacted internal
avatar host placeholder `https://url......./` in `test-runtime-network-boundary-contract.R`
(regex `^https?://url\.+/`). It is an intentional commit-time redaction (like `technical name 1`),
not a public dependency. Test is now green in the cloud checkout too.

**PRIORITY 4 (wd-independent fallback guard):** `R/helpers_llm_sse.R` previously loaded its
sibling helpers (`helpers_llm_stream_io.R`, `helpers_llm_sse_events.R`) via a `getwd()`-relative
`file.path("R", ...)` only → isolated source from `tests/testthat` cwd lost
`append_stream_delta_line`. Now uses the proven candidate pattern (repo root / `../../` /
`MERGEN_REPO_ROOT`). REMAINING getwd-relative guards (DORMANT in prod, contract-protected, lower
priority): the 5 MCP helper files (`helpers_mcp_chart_tools/_schema_helpers/_basic_tools/
_file_resolver/_table_readers.R` → `.mcp_context_path <- file.path("R", ...)` with a hard
`stop()`) and `helpers_health_checks.R` (`runtime_checks_path`). These only fire when sourced
in isolation from a non-repo-root cwd AND the helper env isn't already loaded — note them, fix
only if an isolated test actually breaks.

**PRIORITY 1 concurrency re-audit — re-confirmed clean, NO new fix:** re-audited every flagged
async file. `server_handler_summarization.R` (fast-stream propagates `active_request_id`+
`stop_generation`; non-streaming uses `mergen_is_current_request`), `module_settings_yapilandirma.R`
(button-disabled singleton), `server_observers_startup.R` (one-time hydration), `helpers_file_pipeline.R`
(per-file, callbacks run sequentially on the single main thread → no read-modify-write race),
`module_ai_processing.R` (pure transform; consumer is request-guarded), `module_chat_history_background.R`
(id-keyed cache warming). The ONE real-but-low-probability finding is DEFERRED (see New candidates).

**PRIORITY 5 behavioral coverage — 7 NEW files (+1 updated), ~290 assertions, 0 fail/0 warn:**
- `test-claude-code-document-builders-behavior.R`: `build_claude_code_document_prompt`,
  `_inline_payload`, `_summary_messages`, `write_claude_code_document_manifest`.
- `test-send-message-lifecycle-helpers-behavior.R`: `mergen_clear_welcome_for_send_message`,
  `mergen_prepare_send_message_chat` (defer/DB branches), `mergen_prepare_mcp_session_files`.
- `test-deep-analysis-context-builder-behavior.R`: `build_deep_analysis_context` (error-only,
  data_analysis, max_tokens scaling + 8192 ceiling, failed-note).
- `test-mcp-tools-parse-behavior.R`: `parse_tool_calls_from_text` (tool_call/inline JSON/plain
  SQL fallback/empty), `get_mcp_tools_prompt`, `get_openai_tools` (full MCP chain source-once).
- `test-claude-code-plugins-server-behavior.R`: `claudeCodePluginsServer` via `testServer`
  (real `bilge_yolac_plugins/` scan; **gotcha: set `shiny::shinyOptions(appDir = repo_root)` so
  `resolve_app_root()` finds the dir — testServer's default appDir points elsewhere**).
- `test-ai-expert-db-fetch-behavior.R`: `fetch_user_last_login`, `fetch_recent_user_prompts`,
  `fetch_user_work_context` (DBI-mocked via `local_mocked_bindings(.package="DBI")`).
- Plus the 2 vision test files above.

**CRITICAL ENCODING LESSON (cost me two corruptions this session — do NOT repeat):** when
rewriting a CRLF file with an R `readLines()+writeBin(charToRaw(enc2utf8(...)))` script, you MUST
run that script with `LANG=C.UTF-8 LC_ALL=C.UTF-8` set. WITHOUT a UTF-8 locale, `readLines` +
`enc2utf8`/`charToRaw` MANGLES every Turkish byte into the literal ASCII text `<c4><b1>` (a
catastrophic whole-file mojibake diff). Always: set the locale, run the edit, then verify with
`grep -c '<c3>\|<c4>\|<c5>' file` (must be 0) AND `git diff --stat` (must be small). LF files are
safe with the normal Edit tool.

**Validation run:** per-file testthat for all 9 touched/new files = 0 fail/0 warn standalone AND
in a `test_dir` batch (222+ assertions); `parse_sanity_check.R` (710 files OK); contracts GREEN
(`source-manifest` 165, `global-source-manifest` 12, `api-model-config` 35, `llm-reasoning-overrides`
14, `llm-content-reasoning-fallback` 24, `send-message-prompting` 21, `send-message-request-lifecycle`
42, `maintainability-ratchet` 156, `maintainability-ratchet-contract` 3, `runtime-network-boundary`
2, `secret-leak` 8, `production-contracts` 21, `renv-lock-contract` 23). Repo gate
`bash tools/ai_validate.sh cloud-quick` = failed_steps 0 / skipped_steps 1
(`profile_requested=cloud-quick`, `profile_effective=quick`, `app_source_smoke_status=skipped`,
`db_sso_vm_validation_performed=false`). `quick` itself reached app-source-smoke then hit the
documented heavy-package limit (`logger` not installed; vendored www assets + `.Renviron` absent).

**renv (PRIORITY 0):** STILL NOT in this git checkout (`git ls-files renv.lock` empty; only
`RENV_LOCK_STATUS.md` marker, which claims a 2026-06-06 R 4.6.0 VM commit). `renv-lock-contract`
passes with it absent. **User action:** `git add renv.lock && git push` from the Windows VM if it
should land in GitHub. Do NOT generate it from Linux/cloud.

### Earlier session (`claude/exciting-knuth-pTGt1`) — merged via a new PR
**VISION GAP CLOSED (PRIORITY 0 — config-gated, real, not faked):**
- New pure helper file `R/helpers_vision_context.R` (sourced in manifest BEFORE
  `helpers_send_message_prompting.R`): `mergen_vision_image_extensions`,
  `mergen_is_image_file`, `mergen_image_mime_type`, `mergen_vision_enabled`
  (option `mergen.vision_enabled` → env `MERGEN_ENABLE_VISION`, default FALSE),
  `mergen_is_vision_model` (reads `api_config$local_model_capabilities[[m]]$vision`,
  mirrors `is_thinking_model`), `mergen_vision_active` (BOTH gates),
  `mergen_vision_unavailable_note` (explicit Turkish note), `mergen_build_image_data_url`
  (base64 data-url, 5 MB cap, NULL on fail), `mergen_build_vision_user_content`
  (OpenAI multimodal `[{type:text},{type:image_url,image_url:{url}}]`),
  `mergen_vision_prepare_context_blocks` (owns the `none`-branch file-block loop).
- `R/helpers_send_message_prompting.R` `none` branch is now vision-aware (with a
  wd-independent fallback source-guard at the top so the file is standalone-sourceable):
  when `mergen_vision_active(model_selected, api_config)` AND a real image encodes →
  the final user message `content` becomes a multimodal ARRAY (image_url base64 parts);
  otherwise content stays a STRING and images get the explicit
  "…bu sürümde analiz edilemiyor…" note instead of the silent generic "okunamadı".
  Both `helpers_llm_api.R` and `helpers_llm_sse.R` already preserve list-content and
  serialize via `toJSON(..., auto_unbox=TRUE)`, so the array survives to the body
  UNCHANGED. `server_send_message.R` call site now passes `model_selected`+`api_config`.
- **Vision is OFF by default → production text path is byte-identical to before.** The
  full base64-into-HTTP-body path is real but UNTESTED against a live vision endpoint
  (no endpoint in cloud); the deterministic tests prove the message/body STRUCTURE.
- Tests: `tests/testthat/test-vision-context-behavior.R` (~63 assertions): pure helpers,
  data-url build+size-cap, multimodal builder, none-branch vision ON (image_url part)
  / OFF (explicit note + string) / image-unreadable fallback, and a `toJSON` round-trip
  asserting `"type":"image_url"` + `"url":"data:image/png;base64,…"`.
- `helpers_send_message_prompting.R` stays within its 260-line/8-fn budget (now 244 lines);
  ratchet fully GREEN. `fm_image_extensions()` comment updated (vision is now optional, not "yok").

**CONCURRENCY RE-AUDIT (PRIORITY 1) — re-confirmed clean, NO new fix needed:**
- Independently audited all 18 async-callback files. The prior session's fixes hold.
  Remaining flags are benign: TTS `attach_tts_audio` is keyed by stable `message_id`
  (correct target even if a newer msg exists), `module_ai_processing` chart_store is
  append-only/id-keyed with a request-guarded consumer, `trigger_idle_chat` is guarded
  by `can_speak()` (which re-checks MUTED_PAGES/enable/mode/cooldown at completion),
  settings Claude-Code connection test is button-disabled + singleton status,
  `helpers_file_pipeline` summary is per-file with synchronous pre-registration.
  **Did NOT manufacture a fix where there is no real cross-request clobber.**

**BEHAVIORAL COVERAGE (PRIORITY 5) — 3 new files, ~65 assertions, 0 fail/warn:**
- `test-claude-code-runtime-path-pure-behavior.R`: `is_windows_single_slash_network_path`
  (non-Windows contract), `.cc_runtime_workdir_token` (sanitize+`run_` prefix),
  `.cc_runtime_workdir_reusable` (only under `/claude_code_runtime/user_<id>/` + dir.exists).
- `test-health-formatters-path-behavior.R`: `health_is_storage_path_id`,
  `health_as_windows_explorer_path`.
- `test-ai-expert-prompt-builders-behavior.R`: `get_ai_expert_generation_config`
  (exact token/temperature for scenario×length×style + 200 floor),
  `build_ai_expert_system_prompt` (scenario branches + conditional name instruction),
  `build_ai_expert_user_context` (unit/login/session branches, `include_recent_prompts=FALSE`).

**renv (PRIORITY 0):** STILL NOT committed in git (only `RENV_LOCK_STATUS.md` marker
present; `renv.lock` absent, `renv/library` empty as expected). MUST be `git add`ed by the
user from the Windows VM (R 4.6.0) — never generate from cloud. Re-verify next session.

**Validation run:** per-file testthat (all new files 0 fail/0 warn standalone AND in a
`test_dir` batch = 127 pass), `parse_sanity_check.R` (698 files OK), manifest contracts
(165+12), maintainability ratchet GREEN, send-message ratchet GREEN. Repo gate via
`tools/ai_validate.sh cloud-quick` (cloud lacks vendored www assets + .Renviron, so full
`quick` app-source-smoke can't run — documented limitation).

### Earlier sessions (still valid)
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
  `copy_to_mcp_base`; the chat-upload path (`helpers_file_pipeline.R`) was centralized onto the same list.
  `readFileContentToString`'s existing default switch case already returns a clean Turkish "okunamadı"
  string for images (no binary garbage) — verified by test; do NOT add a per-image case, `helpers_files.R`
  is at its exact 260-line budget. **NOTE: there is still NO image/vision pipeline** — uploaded images
  cannot be analyzed by the LLM yet (see "New candidate weaknesses"). Test: `test-image-upload-allowed-behavior.R`.
- **Toasts** now display 5–12 s scaled by message length (was a flat 3 s): `www/js/toast.js`
  smart default, `shiny_message_handlers.js` passes `data.duration`, R `showToast` default → `NULL`.
- **"Yenile" buttons unified**: all refresh buttons (Söyleşi Geçmişi, Kayıtlı Söyleşiler, Görsel Galerisi,
  all Yönetici pages, Sistem Durumu) now use `btn-modern btn-refresh`; `.btn-modern.btn-refresh` is now
  container-agnostic in both `file_manager.css` (dark teal) and `theme_light_user_polish.css` (light blue).

**renv dependency lock (this session — scaffolding + on-prem lock generated by the user):**
- Added offline-safe **conditional** `.Rprofile`, canonical `renv/activate.R` + `renv/.gitignore`, refined
  root `.gitignore`, `tools/renv_snapshot.R` (VM helper, ASCII-only), `docs/dependency-locking.md`,
  RUNBOOK §10, a renv-restore preference in `ci_install_packages.R` (falls back to RSPM/CRAN), and
  `renv.lock` in the mergen-ai-validation cache key. Test: `test-renv-lock-contract.R`.
- **`.Rprofile` activates renv ONLY when ALL hold:** `renv/activate.R` + `renv.lock` + renv installed +
  **`renv/library` actually populated** (bounded `Sys.glob(.../DESCRIPTION)`); otherwise NO-OP (global
  library); never downloads; never crashes; escape hatch `MERGEN_DISABLE_RENV_AUTOLOAD=true`. The
  populated-library condition was ADDED after a real VM trap was found: `tools/renv_snapshot.R` only
  RECORDS the lock and does NOT populate `renv/library`, so without it the VM would switch to an empty
  project library on the next R restart and break the app. Do NOT remove that condition or revert to the
  standard unconditional `source("renv/activate.R")`.
- `.Rprofile` and `tools/renv_snapshot.R` are intentionally **ASCII-only** (Windows/Turkish-locale safety;
  they are sourced/`parse()`-ed by tests).
- **The user GENERATED `renv.lock` on the Windows VM** (R 4.6.0, ~116 packages, ~4295 lines). It may or
  may not be committed to git yet (the user couldn't paste it via the web UI). `RENV_LOCK_STATUS.md` is a
  committed MARKER recording this. If a real `renv.lock` is now present in the repo, the
  `test-renv-lock-contract.R` consistency check enforces `required_packages` ⊆ `renv.lock`. Do NOT
  generate or reconstruct `renv.lock` from Linux/cloud; if it's missing from git, remind the user to
  `git add renv.lock` from the VM. Do NOT create a fake/partial file literally named `renv.lock`.

**WINDOWS VM TEST-ROBUSTNESS LESSON (important — the cloud env masks this):** the first renv/image/api-key
tests passed on Linux/cloud but FAILED on the user's Windows VM (Turkish/Windows-1254 locale) in the FULL
suite (they passed individually — earlier suite tests change locale/encoding state). Root causes + fixes,
now applied: (a) tests that scan repo files MUST use the byte-safe reader (`readBin` + `iconv(sub="byte")`)
with `grepl(useBytes=TRUE)` over ASCII anchors — never `readLines(encoding="UTF-8")+grepl()` over
Turkish-commented files (that throws `input string 1 is invalid UTF-8`); (b) do NOT assert
`!is.na(iconv(x,"UTF-8","UTF-8"))` on strings that may be native-encoded on Windows — use byte checks;
(c) after a refactor moves a function (e.g. main's `_preview.R` split of `llm_worker_extract_preview_df`),
update the test's `source(...)` to the NEW owner. ALWAYS apply these patterns to new file-scanning tests.

**Branch maintenance (prior step):** merged current `origin/main` into the branch (clean, no conflicts).
This pulled main's `helpers_llm_worker_tool_results.R` → `_preview.R` split, which **resolved the 2
previously "pre-existing" maintainability-ratchet failures** — the ratchet is now fully GREEN on this branch.

**KNOWN pre-existing failure #2 — ✅ RESOLVED in `claude/exciting-einstein-JGkKQ`** (per-file
baselines bumped to real measured values with a Turkish comment; global ratchet untouched).
Original note kept for context:
`test-maintainability-ratchet-contract.R` (the PER-FILE baseline contract, distinct from
`test-maintainability-ratchet.R` which is GREEN) fails on a CLEAN `origin/main` worktree in the cloud:
`R/module_startup_screen.R` is ~740 lines (baseline 695, limit 730) and `R/helpers_ai_expert.R` is
~661 lines / over its fn baseline (baseline 619, limit 650). These two files grew in EARLIER merged
PRs (skip-intro neural-color fix; AI-Expert staleness + TTS chunking) that updated the GLOBAL ratchet
baseline but NOT this per-file contract baseline. This session did NOT touch either file (verified:
empty `git diff origin/main` on both). The user's Windows VM full-suite run reached DONE past it (their
checkout/strict-runner differs), so it was not blocking them. **NEXT SESSION:** confirm on the VM, then
either (a) split a small focused helper out of each file to get back under baseline (preferred per CLAUDE.md),
or (b) bump ONLY these two per-file entries in `test-maintainability-ratchet-contract.R` to their real
current measured values with a Turkish comment noting the legitimate merged growth — this is the per-file
baseline mechanism's intended maintenance and does NOT loosen the global ratchet. Do NOT touch the global
thresholds in `test-maintainability-ratchet.R`.

**KNOWN cloud-only failure — ✅ RESOLVED in `claude/exciting-einstein-JGkKQ`** (allowlisted the
redacted `https://url......./` placeholder via regex `^https?://url\.+/`; it is a commit-time
redaction, not a public dependency). Original note kept for context:
`test-runtime-network-boundary-contract.R` fails in the cloud checkout because `R/helpers_messaging.R:337`
and `R/module_sidebar_user_panel.R:88` contain a **redacted** avatar URL `paste0("https://url......./", ...)`.
This placeholder is unchanged since the merge-base, untouched by this session, and is almost certainly a
cloud-side redaction of the real internal avatar host (which the network-boundary allowlist /
`MERGEN_ALLOWED_INTERNAL_URL_REGEX` would accept on the real VM). Investigate whether the redaction should
be allowlisted or the placeholder normalized — but do NOT "fix" it by inventing a public URL.

---

## PRIORITY 0 — Trust the Windows VM over the cloud env; close the two known gaps
The cloud/Linux env MASKS Windows-specific failures (locale/encoding, full-suite pollution). Do NOT declare
"all green" from cloud runs alone for file-scanning/encoding-sensitive tests. The authoritative signal is the
user's `source("tests/testthat.R")` on the Windows VM (R 4.6.0). Two concrete items to close:
- **Vision — ✅ config + capability-primary gating + serialization proof DONE in
  `claude/exciting-einstein-JGkKQ` (see "THIS LATEST SESSION" above). NOW DEFAULT-ENABLED per
  capability.** REMAINING (VM-only): on the Windows VM set `MERGEN_VISION_MODELS=<real image-capable
  model IDs>` in `.Renviron` (the CODING_DEEP_* models are auto-marked), confirm the deployed model
  truly accepts `image_url` parts, then send a real image + question and confirm an end-to-end answer
  (the base64→HTTP-body path is real but UNTESTED against a live endpoint). Global kill-switch:
  `MERGEN_ENABLE_VISION=false` disables everywhere. Optionally add a Yapılandırma toggle + `max_bytes`.
  Do NOT fake vision; do NOT regress the text path (non-capable models still get the explicit note).
- **renv on the VM:** confirm the user committed the real `renv.lock` (or remind them to `git add renv.lock`
  from the VM). Confirm `tests.yml`'s `setup-r-dependencies@v2` works with the lock once committed
  (`docs/dependency-locking.md` §6). Never generate `renv.lock` from Linux/cloud.
  - **`renv/library` is intentionally EMPTY on the production VM and that is OK** — the app runs on the
    global library; `renv.lock` is just the version RECORD. Populating `renv/library` via
    `renv::restore()` (which then makes `.Rprofile` switch to the project-local library) is an OPTIONAL
    project-isolation decision, NOT a requirement. Discuss with the user before running `renv::restore()`
    on the production VM; if they want global-library behavior to stay, leave `renv/library` empty (the
    `.Rprofile` populated-library guard already keeps this safe).

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
any threshold in `test-maintainability-ratchet.R`. NOTE: the 2 ratchet failures that earlier sessions saw
(`helpers_llm_worker_tool_results.R` / `helpers_llm_worker.R`) were RESOLVED by main's `_preview.R` split
and merged in; the ratchet is now fully GREEN. Keep it that way.

## NEW CANDIDATE WEAKNESSES (investigate; pick the highest-value ones)
- **DOCX preview async clobber (DEFERRED this session — real but very-low-probability, needs a
  testServer proof):** `R/module_file_preview.R` lines ~378-393 — for a DOCX > `SYNC_B64_THRESHOLD`
  (10 MB), base64 encoding runs in a `future` and the `%...>%` callback sends `openDocxPreview` to the
  FIXED `ns("docx_preview_container")`. If the user opens DOCX A (>10 MB, async), then opens DOCX B
  before A finishes, A's late callback renders A's content into B's modal (wrong document shown). Fix:
  a `docx_preview_seq <- reactiveVal(0L)` token incremented on each DOCX modal open, captured in the
  async closure, and guard the send with `identical(isolate(docx_preview_seq()), captured)`. It's LF
  so the Edit tool is safe. NOTE: a top-level extractable helper would bump `module_file_preview.R`'s
  `function(` count (currently ~24-26 — near the global 25-fn ratchet); prefer an INLINE guard (no new
  `function(`) + a `testServer` test that stubs `future::future` to defer A's resolution past B's open.
  Was deferred only because a clean deterministic test (futures + modal timing) is involved and the
  race is cosmetic/transient (preview-only, self-corrects on reopen).
- **Remaining getwd-relative fallback guards (PRIORITY 4 leftovers):** see the PRIORITY 4 note in
  "THIS LATEST SESSION" — 5 MCP helper files + `helpers_health_checks.R` still use
  `file.path("R", ...)` in their `if (!exists(...))` guards. Dormant in prod; fix with the candidate
  pattern only if an isolated test actually breaks (the MCP ones `stop()` hard, so be careful — they
  are contract-protected by `test-mcp-*-refactor-contract.R`).
- **Vision pipeline (TOP — see PRIORITY 0):** image UPLOAD, leak-fix, and inline PREVIEW are done
  (`module_file_preview.R` renders images via `registerDataObj`). What is NOT done: the LLM cannot answer
  questions about an attached image (no base64 image parts in the request). This is the user's main
  remaining pain point. Scope a real vision integration (config-gated) or, if the model lacks vision, make
  the assembled-prompt note explicit. Do NOT fake it.
- **Duplicated allowed-extension lists / policy:** centralization improved this session
  (`fm_normal_allowed_extensions` is the single source for both upload paths). Grep for any other
  hardcoded extension whitelist that drifted and centralize it.
- **`showToast` duration plumbing:** R `showToast` now passes `duration` through; confirm no caller relies
  on the old fixed 3 s, and consider a contract test for the smart-duration JS (node-checkable).
- **Frontend duplicate-CSS-selector report:** `tests/scripts/frontend_maintainability_report.R` lists
  duplicate selectors — review for any genuine conflicts (not cosmetic).
- **renv lock generation (USER/VM action, not cloud):** the renv scaffolding is in place but `renv.lock`
  is NOT generated. It must be produced on the Windows VM (R 4.6.0) via `Rscript tools/renv_snapshot.R`
  and committed. Do NOT generate it from Linux/cloud. After it is committed, verify `tests.yml`'s
  `setup-r-dependencies@v2` still works with the lock (see `docs/dependency-locking.md` §6); the
  `test-renv-lock-contract.R` consistency check will then enforce `required_packages` ⊆ `renv.lock`.
- **Redacted avatar URL vs network-boundary test (see KNOWN failure above):** decide whether to allowlist
  the redacted `https://url......./` placeholder or normalize it, so `test-runtime-network-boundary-contract.R`
  is green in the cloud checkout too.

---

## VALIDATION DISCIPLINE (be honest — this is graded)
- After EVERY new/edited test: `Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-X.R",
  reporter="summary")'` → require 0 FAIL / 0 WARN / 0 accidental SKIP, standalone AND in a `test_dir` batch.
- After any R edit: `Rscript tests/scripts/parse_sanity_check.R` and
  `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")` (must be fully GREEN now — the
  earlier pre-existing failures were resolved by the main merge; do not regress it).
- Known cloud-only failure to expect: `test-runtime-network-boundary-contract.R` (redacted avatar URL,
  see above). Confirm your changes are NOT the cause before touching it.
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

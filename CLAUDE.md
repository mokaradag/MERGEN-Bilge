# CLAUDE.md - MERGEN Bilge Codebase Guide

## Purpose of This File

This document is the operational guide for coding agents working inside the **MERGEN Bilge** repository. It explains how the application is structured, how it boots, which files are critical, which areas are fragile, and what repo-specific working style must be followed.

The repository is an R/Shiny application with a dark-theme, multimedia-heavy, Turkish-first user experience. It includes:

- conversational AI,
- file upload and analysis,
- MCP-enabled workflows,
- TTS and STT,
- AI Expert proactive guidance,
- support and version history pages,
- a web-wrapped Claude Code experience named **Bilge Yolaç**,
- SSO-ready deployment for VM/enterprise environments.

This file should be read before touching the code.

Documentation note: `README.md` gives the product-level feature overview, while `ai_rehber.md` defines user-facing assistant behavior; this guide remains the primary reference for repository-safe implementation practices.

---

## Non-Negotiable Repo Rules

### 1) Preserve Turkish text integrity
This project is extremely sensitive to encoding regressions.

Always assume:

- files must remain UTF-8,
- Turkish characters must not be Latinized,
- any “simple cleanup” can accidentally introduce mojibake on VM/SSO flows.

If you touch file reading, file writing, `.Renviron`, DB writes, JSON writes, or browser-rendered text, be extra careful.

### 1B) Text encoding and mojibake boundary contract
Turkish text, emoji, and mojibake repair are centralized. Do not reintroduce scattered ad hoc replacement maps.

Current contract:

- Server-side text normalization belongs in `R/utils_text_encoding.R`.
- Client-side defensive mojibake fallback belongs in `www/js/encoding_utils.js`.
- `R/utils_text_encoding.R` must be loaded early through `R/config_source_manifest.R`, before logging, DB helpers, and downstream text consumers.
- `www/js/encoding_utils.js` must be loaded through `R/config_ui_assets.R` before `www/js/shiny_message_handlers.js` and before `www/js/claude_code_streaming.js`.
- DB write parameters, DB read/hydration paths, saved chat reloads, version-history/Yenilikler reads, uploaded-file display names, Bilge Yolaç process/stream output, JSON/text boundaries, and logs should use the shared helper path instead of local encoding fixes.
- DB normalization is intentionally opt-in for mojibake repair. Use `normalize_db_params(..., repair_mojibake = TRUE)` or `normalize_db_value(..., repair_mojibake = TRUE)` only at user-visible text write boundaries such as chat titles, message content, reasoning content, edited message content, worker-saved assistant responses, and SSO/user display fields. Keep the default `repair_mojibake = FALSE` for technical parameters, IDs, flags, and non-user-visible values.
- The SQL Server DB write boundary is production-sensitive on the Windows VM / SSO deployment. Do not force raw UTF-8 into DBI/ODBC parameter writes merely because the configured client encoding says UTF-8. That behavior can store Turkish text as mojibake across MB tables.
- For the production VM, Turkish DB writes must preserve the stable Windows-native / `WINDOWS-1254` behavior. `DB_CLIENT_ENCODING=WINDOWS-1254` is the safe operational setting unless a live VM + SSMS validation proves otherwise.
- Treat emoji persistence as a separate DB capability question. Before changing DB write encoding for emoji, verify the relevant SQL Server column types (`nvarchar` vs `varchar`) and run a real write/read test through the app and SSMS. Do not trade Turkish text integrity for emoji display.
- Read-side normalization may defensively repair display of older mojibake values, but it must not be used as an excuse to allow new mojibake writes. New records in `MB_Users`, `MB_Chats`, `MB_Messages`, `MB_Feedback`, and other MB tables must be validated at rest in SQL Server.
- Test bootstrap must mirror runtime encoding order. `tests/testthat/helper_bootstrap.R` should source `R/utils_text_encoding.R` before DB helpers so isolated `testthat::test_file(...)` runs exercise the same mojibake repair path as the application.
- File Manager display-name repair depends on the shared text helper. Tests that source `R/config_file_store_index_mutation.R` in isolation must also load `R/utils_text_encoding.R`, otherwise mojibake filename fixtures can appear unchanged even though runtime behavior is correct.
- Do not replace deterministic byte-built mojibake fixtures in tests with fragile console-dependent mojibake or emoji literals when the test must pass on Windows VM sessions.
- Logging should pass user-visible text through the shared log normalization path so Turkish text stays readable and ANSI escape sequences are not made worse.
- Bilge Yolaç streaming must keep the browser-side fallback, but `www/js/claude_code_streaming.js` must not grow another large local mojibake map. Use `window.MergenEncoding` from `www/js/encoding_utils.js`.
- Do not replace UTF-8-safe byte reading helpers with plain `readLines(..., encoding = "UTF-8")` in Windows/VM-sensitive paths unless the regression tests prove it is safe.
- Be careful with R constants: use exactly `NA_character_`. A typo such as `NA_character__` can break app startup through DB parameter normalization.
- Do not add CDN or external dependencies for encoding repair.

Protected by:

- `tests/testthat/test-text-encoding-utils.R`
- `tests/testthat/test-db-normalization-contract.R`
- `tests/testthat/test-file-manager-display-name-contract.R`
- `tests/testthat/test-maintainability-ratchet-contract.R`
- `tests/testthat/test-claude-code-process-refactor-contract.R`
- `tests/testthat/test-ui-asset-manifest-contract.R`

Focused validation:

- `testthat::test_file("tests/testthat/test-text-encoding-utils.R")`
- `testthat::test_file("tests/testthat/test-db-normalization-contract.R")`
- `testthat::test_file("tests/testthat/test-file-manager-display-name-contract.R")`
- `testthat::test_file("tests/testthat/test-maintainability-ratchet-contract.R")`
- `testthat::test_file("tests/testthat/test-claude-code-process-refactor-contract.R")`
- `testthat::test_file("tests/testthat/test-ui-asset-manifest-contract.R")`

VM-only manual validation after any DB encoding change:
- Start the app on the Windows VM with SSO enabled.
- Create a new chat message containing: ç ğ ı İ ö ş ü Ç Ğ I Ö Ş Ü
- Add feedback tags/comments containing Turkish characters.
- Verify the new rows directly in SSMS for `MB_Users`, `MB_Chats`, `MB_Messages`, and `MB_Feedback`.
- Reject the change if SQL Server stores values like `Ã§`, `Ä±`, `Ã¶`, `ÅŸ`, or `ÄŸ`.

### 1A) Keep new code identifiers ASCII-safe when practical
Preserve Turkish text integrity in user-facing strings, docs, comments, DB text, JSON text, and rendered UI. However, for Windows VM parser robustness, **new code identifiers** should be ASCII-only where practical (variable/helper names, unquoted `data.frame(...)` column names, `$field_name` accessors, and similar code symbols that can become mojibake-sensitive). This is **not** permission to Latinize visible product text; it applies only to code symbols/identifiers.

### 2) Comments added to code must be in Turkish
If you add comments in code, write them in Turkish.

### 3) Prefer surgical changes
Do not perform wide refactors unless the user explicitly asks for them.

Preferred style:

- smallest safe patch,
- minimal file churn,
- minimal new abstractions,
- preserve existing naming and structure.

### 4) Do not create unnecessary new files
This repo already has a lot of modules. New files should only be introduced when there is a clear benefit and the sourcing order in `global.R` is updated correctly.

### 5) Respect the project’s modular load order
A new helper/module is not “done” unless:

- it is placed in the correct layer,
- it is listed in `R/config_source_manifest.R`,
- dependencies are loaded before it,
- `ui.R` / `server.R` wiring is updated where necessary.

### Source manifest validation contract

The runtime source order is now owned by `R/config_source_manifest.R`, not by a long `safe_source()` list inside `global.R`.

`global.R` must remain a high-level boot orchestrator. It is responsible for UTF-8 options, upload limits, resource-path registration, bootstrap loading, manifest-file validation, manifest object validation, manifest file/order/parse validation, future/test-mode setup, and calling the manifest loader. It must not grow back into a giant order-dependent source manifest, and it must not reintroduce duplicated inline `safe_source()` blocks for the manifest groups. `app.R` must keep `R/config_source_manifest.R` in `required_boot_files` so a missing manifest fails before the rest of the app boot proceeds. The expected runtime loading shape is: validate `R/config_source_manifest.R` itself with `source_manifest_validate(order_rules = list(), paths = "R/config_source_manifest.R")`, load it with `safe_source("R/config_source_manifest.R", encoding = "UTF-8")`, call `source_manifest_validate_config_objects()`, call `source_manifest_load(source_manifest_group_1_paths)`, run future/test-mode setup, then call `source_manifest_load(source_manifest_after_future_paths)`.

The current source-manifest layers are:

- `R/utils_safe_source.R`: defines UTF-8-safe `safe_source()` and preserves the Windows/VM fallback behavior.
- `R/bootstrap_source_manifest.R`: defines manifest object-shape validation, critical order rules, parse/file checks, explicit-path validation, and `source_manifest_load()`.
- `R/config_source_manifest.R`: defines the explicit runtime source order through `source_manifest_group_1_paths`, `source_manifest_after_future_paths`, and `source_manifest_runtime_paths`.
- `global.R`: validates `R/config_source_manifest.R` before sourcing it, validates the manifest objects, validates runtime paths, and loads files through `safe_source()` without owning or reconstructing the full list inline.

When adding, moving, or splitting a runtime file:

- add the file to the correct position in `R/config_source_manifest.R`,
- keep dependency order explicit and reviewable,
- when splitting Claude Code security helpers, preserve the order `R/helpers_claude_code_security_policy.R` before `R/helpers_claude_code_prompt_security_policy.R`, and keep both before the Claude Code runtime, process, streaming, lifecycle, and module files that call the policy helpers.
- keep loading through `safe_source()`; do not replace it with plain `source()`,
- keep `global.R` validating `R/config_source_manifest.R` before sourcing it and loading manifest groups through `source_manifest_load(...)`; do not manually duplicate group entries with individual `safe_source()` calls,
- keep `source_manifest_runtime_paths` exactly equal to `c(source_manifest_group_1_paths, source_manifest_after_future_paths)`; do not maintain a separate divergent runtime list,
- update `source_manifest_required_order` in `R/bootstrap_source_manifest.R` only for genuinely critical dependency boundaries,
- keep `R/bootstrap_source_manifest.R` small, bootstrap-only, and free of feature/module loading,
- do not add automatic directory sourcing, alphabetical sourcing, package-style discovery, or runtime source-order inference,
- do not reintroduce `global.R` scraping or `source_file = "global.R"` style fallback validation; `source_manifest_validate()` must receive explicit paths from `R/config_source_manifest.R`,
- preserve `MERGEN_RUN_APP=false` and `MERGEN_DISABLE_FUTURES=true` boot safety,
- keep comments added to R code in Turkish.

The File Manager attach-state browser handler is intentionally split into `R/helpers_file_manager_attach_client.R`. Keep this helper listed in `R/config_source_manifest.R` after `R/helpers_file_manager_state_runtime.R` and before `R/module_file_manager.R`. Do not move the inline JavaScript registration back into `R/module_file_manager.R`; that module is protected by near-limit maintainability ratchet checks and should remain focused on Shiny orchestration.

Source-order tests must read `R/config_source_manifest.R` as the source of truth. Do not write new tests that scrape `global.R` for every runtime `safe_source("R/...")` entry. Static `global.R` tests should only protect the bootstrap contract, the explicit pre-source validation of `R/config_source_manifest.R`, the manifest object validation call `source_manifest_validate_config_objects()`, and the two high-level manifest loading calls: `source_manifest_load(source_manifest_group_1_paths)` and `source_manifest_load(source_manifest_after_future_paths)`. Use the shared manifest test helper in `tests/testthat/helper_source_manifest_contract.R`, especially:

- `source_manifest_paths_for_tests()`
- `expect_source_manifest_contains_for_tests()`
- `expect_source_manifest_order_for_tests()`

The validation layer should continue to fail early with clear Turkish boot errors when it detects:

- missing source files, including a missing `R/config_source_manifest.R` during the app boot-file check,
- missing or invalid manifest objects,
- divergence between `source_manifest_runtime_paths` and the two explicit manifest groups,
- unintended duplicate source entries,
- unparseable source files, including an unparseable `R/config_source_manifest.R` before it is sourced,
- unsupported attempts to validate by scraping `global.R`,
- critical source-order regressions.

Protected by:

- `tests/testthat/helper_source_manifest_contract.R`
- `tests/testthat/test-global-source-manifest-contract.R`
- `tests/testthat/test-source-manifest-contract.R`
- `tests/testthat/test-e2e-boot-welcome-regression.R`
- `tests/testthat/test-production-contracts.R`
- `tests/testthat/test-maintainability-ratchet.R`

Focused validation:

- `testthat::test_file("tests/testthat/test-global-source-manifest-contract.R")`
- `testthat::test_file("tests/testthat/test-source-manifest-contract.R")`
- `testthat::test_file("tests/testthat/test-e2e-boot-welcome-regression.R")`
- `testthat::test_file("tests/testthat/test-production-contracts.R")`
- `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")`
- `source("tests/scripts/maintainability_report.R", encoding = "UTF-8")`
- `source("tests/testthat.R", encoding = "UTF-8")`

### File resolution, upload-size, and user-isolation contract

File resolution is a security-sensitive boundary. Normal runtime code must treat uploaded files as user-scoped resources, not as general filesystem paths.

Current contract:

- `resolve_uploaded_file()` must remain user-bucket-first.
- Normal user flows must not call `resolve_uploaded_file(..., user_id = NULL)`.
- Normal user flows must not pass `allow_direct_path = TRUE`.
- Normal user flows must not pass `allow_cross_bucket = TRUE`.
- Direct path resolution is denied by default. It may only be used by explicit admin/maintenance code, and only with a trusted root allowlist through `trusted_roots`.
- Cross-bucket resolution is denied by default. It may only be used by explicit migration/repair/admin code.
- Same-user filesystem fallback is allowed and intentional. It exists so files physically present in the current user's upload folder can still resolve when the JSON index is stale, empty, unreadable, or has UTF-8/display-name drift.
- Same-user filesystem fallback must not scan other users' folders.
- MCP file resolution must not convert arbitrary absolute path arguments into readable files.
- MCP legacy root-level index fallback must remain opt-in only through the existing explicit cross-bucket lookup controls.
- Do not reintroduce broad global file lookup in chat, preview, summarization, File Manager, or MCP user flows.

Upload-size policy:

- The central upload limit is `getOption("mergen.upload_max_mb", 25L)`.
- `shiny.maxRequestSize` must be derived from that central option.
- Do not reintroduce a separate hard-coded Shiny upload size such as `30 * 1024^2` in file-store configuration.
- Browser-side upload warnings, server-side validation, and Shiny request limits should stay aligned.

Protected by:

- `tests/testthat/test-resolve-uploaded-file.R`
- `tests/testthat/test-mcp-excel-resolve.R`
- `tests/testthat/test-file-resolution-security-contract.R`
- `tests/testthat/test-upload-size-policy.R`
- `tests/testthat/test-upload-validator.R`
- `tests/testthat/test-upload-validator-branches.R`
- `tests/testthat/test-upload-validator-edge-cases.R`
- `tests/testthat/test-file-store-index.R`
- `tests/testthat/test-e2e-file-context-regression.R`
- `tests/scripts/run_vm_preflight_real.R` when `MERGEN_PREFLIGHT_CHECK_FILE_STORE=TRUE`

Focused validation:

- `testthat::test_file("tests/testthat/test-resolve-uploaded-file.R")`
- `testthat::test_file("tests/testthat/test-mcp-excel-resolve.R")`
- `testthat::test_file("tests/testthat/test-file-resolution-security-contract.R")`
- `testthat::test_file("tests/testthat/test-upload-size-policy.R")`
- `testthat::test_file("tests/testthat/test-upload-validator.R")`
- `testthat::test_file("tests/testthat/test-file-store-index.R")`
- `testthat::test_file("tests/testthat/test-e2e-file-context-regression.R")`
- `Sys.setenv(MERGEN_PREFLIGHT_CHECK_FILE_STORE = "TRUE")`
- `source("tests/scripts/run_vm_preflight_real.R", encoding = "UTF-8")`

### Bilge Yolaç Claude Code execution security contract

Bilge Yolaç wraps Claude Code CLI inside the Shiny UI. This is a security-sensitive and UX-sensitive boundary. Keep CLI argument construction, workdir validation, dangerous-mode decisions, generated-file staging, and prompt-path safety centralized in the Claude Code security helper layer. `R/helpers_claude_code_security_policy.R` owns core policy decisions such as dangerous permissions, permission args, workdir roots, output roots, and path-inside-root checks. `R/helpers_claude_code_prompt_security_policy.R` owns prompt-level path-intent checks. Do not scatter ad hoc permission checks or CLI flags across modules.

Current execution contract:

- `--dangerously-skip-permissions` must remain off by default.
- Dangerous permission bypass may only be enabled through the central policy and an explicit admin/development override such as `CLAUDE_CODE_ALLOW_DANGEROUS_PERMISSIONS=TRUE`.
- When dangerous mode is enabled, it must be logged clearly.
- Normal UX must not require repeated Claude permission prompts for ordinary in-workdir read/write/edit tasks.
- The safe default is `--permission-mode acceptEdits`.
- Default extra allowed tools are `Read`, `Write`, `Edit`, `MultiEdit`, `Glob`, `Grep`, and `LS`.
- `Bash` must not be allowed by default. Add it only through explicit configuration in controlled trusted internal development environments.
- Do not pass policy prose to Claude as part of the user prompt.
- Do not inject Bilge Yolaç policy text through `--append-system-prompt` unless a future change explicitly proves it is safe and updates the regression tests. The current contract is no policy/system prompt injection.
- Preserve the exact user prompt as the final prompt argument.
- Because `--allowedTools` and `--disallowedTools` can behave like variadic CLI flags, always place the final user prompt after a `--` argument separator. This prevents the prompt from being consumed as another tool name and avoids the Claude CLI error: “Input must be provided either through stdin or as a prompt argument when using --print.”
- Do not remove the `--` prompt separator without updating the security policy tests and manually verifying all model tiers.
- Dangerous skip-permission mode must not be enabled by ordinary per-session or per-user settings alone. It must require the central admin/development override path.
- If dangerous mode is requested from an untrusted setting path, ignore it and log a warning instead of silently enabling bypass mode.
- The non-streaming and standalone streaming helper paths must keep a fallback prompt-path guard before process creation.

Workdir and output contract:

- Workdir validation belongs in the central policy helper.
- User-selected existing workdirs may be approved for the current run when `CLAUDE_CODE_ALLOW_USER_SELECTED_WORKDIRS=TRUE`.
- Workdirs must be normalized before use.
- UNC paths, Windows paths, network shares, and Turkish-character paths should use the existing relaxed directory resolver where applicable.
- Path traversal and unintended outside-root access must remain blocked.
- Prompt-level file write/edit/delete/copy/move intent checks belong in `R/helpers_claude_code_prompt_security_policy.R`.
- Obvious requests to write, edit, delete, copy, move, rename, touch, mkdir, or remove files through absolute paths or `../` traversal outside the allowed roots must be rejected before the CLI process starts.
- `R/module_claude_code.R` must not inline this security workflow. It should call `cc_prepare_safe_workdir_for_run()` from `R/helpers_claude_code_run_lifecycle.R`.
- `cc_prepare_safe_workdir_for_run()` should remain the lifecycle-level coordinator for selected-workdir validation plus prompt-path safety.
- A blocked prompt must clean the active run state, send a clear user-visible blocked-message payload, and log the blocked path.
- Do not weaken this guard for UX convenience. Normal UX should be preserved by allowing safe in-workdir file creation and editing, not by allowing unrestricted paths.
- Generated/downloadable files must be staged only when they are inside the selected workdir, runtime workdir, or an explicitly allowed output root.
- Do not silently allow unrestricted filesystem access just to improve UX.
- Do not regress to unconditional dangerous mode.

Recommended safe environment baseline:

    CLAUDE_CODE_ALLOW_DANGEROUS_PERMISSIONS=FALSE
    CLAUDE_CODE_ALLOW_USER_SELECTED_WORKDIRS=TRUE
    CLAUDE_CODE_PERMISSION_MODE=acceptEdits
    CLAUDE_CODE_ALLOWED_TOOLS=Read;Write;Edit;MultiEdit;Glob;Grep;LS
    CLAUDE_CODE_DISALLOWED_TOOLS=

Protected by:

- `tests/testthat/test-claude-code-security-policy-contract.R`
- `tests/testthat/test-claude-code-run-lifecycle-contract.R`
- `tests/testthat/test-claude-code-process-refactor-contract.R`
- `tests/testthat/test-claude-code-runtime-workdir-contract.R`
- `tests/testthat/test-claude-code-workdir-scan-contract.R`
- `tests/testthat/test-maintainability-ratchet.R`

Focused validation:

- `testthat::test_file("tests/testthat/test-claude-code-security-policy-contract.R")`
- `testthat::test_file("tests/testthat/test-claude-code-run-lifecycle-contract.R")`
- `testthat::test_file("tests/testthat/test-claude-code-process-refactor-contract.R")`
- `testthat::test_file("tests/testthat/test-claude-code-runtime-workdir-contract.R")`
- `testthat::test_file("tests/testthat/test-claude-code-workdir-scan-contract.R")`
- `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")`

Manual validation after changes to this boundary:

- Open Bilge Yolaç.
- Select a normal project folder.
- Run a harmless code-review prompt.
- Confirm the prompt is not swallowed by `--allowedTools`.
- Confirm there is no `--print` missing-input error.
- Confirm the assistant does not answer or discuss Bilge Yolaç policy text.
- Confirm ordinary file inspection works without repeated permission prompts.
- Ask it to create a small `.txt` or `.md` file in the selected workdir and confirm the generated download link appears.
- Ask it to write outside the selected workdir and confirm it is rejected or fails safely.
- Ask it to create `../blocked.txt` or an absolute outside-root file path and confirm the CLI does not start, the UI shows a clear blocked message, and logs mention the blocked path.
- Confirm logs show safe mode / `acceptEdits` and do not show dangerous mode unless explicitly enabled.

### API model configuration contract

API model/endpoint/tool-mode helper logic is intentionally split from the main API configuration file.

Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/config_api.R",               encoding = "UTF-8")
safe_source("R/helpers_api_model_config.R", encoding = "UTF-8")
safe_source("R/config_claude_code.R",       encoding = "UTF-8")
```

Responsibilities:

* `R/config_api.R`: environment loading, global API configuration objects, `api_config`, TTS/STT configuration, and API-key validation orchestration.
* `R/helpers_api_model_config.R`: pure model capability, request override, endpoint credential, validation-target, tool-mode, and main-action model resolution helpers.

`R/helpers_api_model_config.R` owns these public helper functions:

```text
get_local_model_capabilities()
merge_named_list_deep()
apply_model_request_overrides()
is_thinking_model()
should_omit_temperature()
should_stream_reasoning()
should_allow_reasoning_fallback()
resolve_local_llm_endpoint()
resolve_local_llm_credentials()
determine_api_key_validation_target()
get_tool_mode_config()
resolve_tool_model_for_family()
resolve_tool_model_for_flag()
build_main_actions_data_from_config()
```

Do not move these helpers back into `R/config_api.R`. The split keeps `R/config_api.R` below the 800-line maintainability threshold while preserving existing public function names.

The LLM, SSE, non-streaming API, and future-worker paths rely on `apply_model_request_overrides()`, `merge_named_list_deep()`, `should_omit_temperature()`, and the endpoint-resolution helpers being loaded before the LLM helper layer. If a future refactor changes this boundary, update `R/config_source_manifest.R`, any genuinely critical order rules in `R/bootstrap_source_manifest.R`, and the contract tests; do not move this ordering back into inline `global.R` source calls.

Protected by:

```text
tests/testthat/test-api-model-config-refactor-contract.R
tests/testthat/test-llm-reasoning-request-overrides.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-sse-worker-export-contract.R
tests/testthat/test-maintainability-ratchet.R
```

Current maintainability ratchet baseline after the latest send_message prompting extraction is: score `100/100`, at most `0` 800+ line files, at most `0` 25+ function files, `0` 1500+ line files, maximum runtime file length `792` when `R/library_queries.R` is ignored as the external SQL library holder, and maximum function count `24`. Do not loosen these limits without an explicit reason. The ratchet also locks the current budgets of near-limit runtime files such as `R/module_claude_code.R`, `R/server_send_message.R`, `R/module_admin_hata_analizi.R`, `R/module_image_generation.R`, `R/helpers_llm_sse.R`, and other high-line/high-function files so remaining headroom cannot be silently consumed. There is no remaining score-driven refactor candidate in the latest maintainability report; future refactors should be selected for concrete production reliability, race-condition reduction, or cohesive architectural risk reduction rather than score chasing. Small helper extraction is preferred when a near-limit runtime file would otherwise consume remaining headroom; the File Manager attach-state client helper is an example of this pattern. Recent file-resolution hardening required one File Manager function-count budget update after tests passed; do not loosen additional ratchet values unless the code change genuinely changes the measured baseline and the reason is documented. The prompt-path security split is part of this contract: keep `R/helpers_claude_code_prompt_security_policy.R` separate from the already dense core security policy helper, and keep `R/module_claude_code.R` delegating workdir/prompt safety to the lifecycle helper instead of growing inline security blocks.

### send_message prompting and file-context contract

The central send_message runtime path is intentionally split so `R/server_send_message.R` does not become the owner of every prompt, style, and uploaded-file context detail.

Preserve this source order in `R/config_source_manifest.R`:

    safe_source("R/helpers_send_message_request_lifecycle.R", encoding = "UTF-8")
    safe_source("R/helpers_send_message_core.R",              encoding = "UTF-8")
    safe_source("R/helpers_send_message_prompting.R",         encoding = "UTF-8")

Responsibilities:

* `R/helpers_send_message_request_lifecycle.R`: request ids, stale/current/stopped request checks, prompt snapshots, deferred chat creation decisions, welcome cleanup, and thinking-panel shell setup.
* `R/helpers_send_message_core.R`: tool-family routing, send-message cleanup/abort helpers, stream profile selection, and MCP session-file preparation.
* `R/helpers_send_message_prompting.R`: citation instruction construction, character/style/system prompt assembly, SQL system prompt merging, MCP Excel uploaded-file context prompts, and MCP-disabled uploaded-file context prompts.
* `R/server_send_message.R`: request orchestration, SSO/user guards, chat/message lifecycle, mode dispatch, API/model setup, and streaming/non-streaming handoff.

Do not move prompt/style/file-context assembly back into `R/server_send_message.R`. Keeping this boundary creates maintainability headroom below the 800-line threshold and reduces the risk that future prompt changes accidentally alter request lifecycle or streaming state.

Race-condition and behavior contracts:

* `send_message()` must continue to create a single request id and pass it to both the thinking/reasoning shell and the true-streaming path.
* Send-message cleanup and abort paths must remain request-scoped when a request id is available. A stale async callback must not remove a newer request’s `#typing-animation-wrapper`.
* `mergen_remove_typing_wrapper_if_safe()` is the focused helper for this guard. Keep it injectable in tests through its remove-UI function argument and do not replace it with unconditional `removeUI("#typing-animation-wrapper")`.
* `send_message()` must bind cleanup/abort closures to the request id created for that invocation before later async paths can call cleanup.
* SQL analysis must merge the style instruction into an existing system message instead of adding a second competing system message.
* MCP Excel prompts must continue to require file tools such as `analyze_uploaded_file`, `get_column_statistics`, or `sql_query_uploaded_file` instead of letting the model guess file contents.
* MCP-disabled uploaded-file prompts must continue to use stored summaries or safe file excerpts and must still end with a Turkish `Kaynakça:` section.
* The helper extraction must not change user-visible Turkish text, filename display behavior, citation behavior, or source-order contracts.
* Avoid introducing local variables that shadow globally important helpers such as `is_thinking_model()` in the send-message runtime path.

Protected by:

    tests/testthat/test-send-message-prompting-contract.R
    tests/testthat/test-send-message-request-lifecycle-contract.R
    tests/testthat/test-send-message-maintainability-ratchet.R
    tests/testthat/test-source-manifest-contract.R
    tests/testthat/test-maintainability-ratchet.R
    tests/testthat/test-e2e-quick-actions-streaming-regression.R
    tests/testthat/test-e2e-streaming-client-request-id-regression.R

Focused validation:

    testthat::test_file("tests/testthat/test-send-message-prompting-contract.R")
    testthat::test_file("tests/testthat/test-send-message-request-lifecycle-contract.R")
    testthat::test_file("tests/testthat/test-send-message-maintainability-ratchet.R")
    testthat::test_file("tests/testthat/test-source-manifest-contract.R")
    testthat::test_file("tests/testthat/test-maintainability-ratchet.R")
    testthat::test_file("tests/testthat/test-frontend-selector-contract.R")
    source("tests/scripts/maintainability_report.R", encoding = "UTF-8")
    source("tests/testthat.R", encoding = "UTF-8")

### Frontend selector and DOM contract

Frontend JavaScript must stay aligned with the actual UI IDs and classes. Do not reintroduce stale chat input selectors such as `#message_input`. The current chat input contract is `#user_input`, `.chat-input`, and `textarea[name="user_input"]`, centralized in `www/js/input_handlers.js` and exposed through `window.MERGEN_CHAT_INPUT_SELECTOR` plus `window.getMergenChatInputElement()`. Send, Enter, Shift+Enter, Escape, character counter, textarea resize, capability-message submission, and stop-mode behavior should continue to use that shared selector path or a safe fallback with the same selector set. Programmatic input events that are intended to trigger delegated handlers must bubble.

The chat content root contract is now explicit. Message observers and CodeMirror observers must attach only to current real chat roots such as `#chat_content_container` or `.chat-container`; do not reintroduce the stale `#_content_container` fallback. The main message observer must be reattached through an explicit helper such as `attachMessageObserver(...)` after Shiny reconnects, just like the CodeMirror observer. Any MutationObserver that is re-established after Shiny reconnects must disconnect the previous observer first, and disconnect cleanup must run on `shiny:disconnected`. This prevents duplicate observers, stale DOM references, lost auto-scroll or widescreen wrapper updates after reconnects, and hidden repeated CodeMirror initialization after reconnects or page refreshes.

Chart rendering must follow the same chat-root contract. `www/js/chart_renderer.js` must not reintroduce stale roots such as `chat_content_wrapper`; saved ChartLab rendering should resolve the current real chat root through `#chat_content_container` or `.chat-container` before calling `window.renderSavedCharts(...)`. Keep this lookup centralized through a small helper such as `getChartRenderRoot(wrapperId)`. Do not fall back to broad `document.body` scans and do not construct dynamic class selectors such as `querySelector('.' + wrapperId)` for this path, because those fallbacks can hide selector drift and initialize charts outside the intended chat surface.

Dynamic drag/drop handlers must not cache Shiny-rendered DOM nodes at document-ready time when the node can be redrawn later. For chat upload and File Manager upload surfaces, keep delegated event handlers, but resolve `#chat_input_wrapper` and `#file_manager_module-main_drop_zone` at use time through small getter helpers. This preserves behavior while avoiding stale jQuery object references after tab switches, redraws, or UI refreshes.

Server-side activity and browser-side send/stop wiring must refer to the real `send_stop_btn` input. Do not reintroduce the stale `send_btn` identifier for the main chat send button. If timeout/activity tracking or JavaScript send helpers are changed, update the UI contract and `tests/testthat/test-frontend-selector-contract.R` together.

The TTS visualizer can receive Shiny messages before its delayed browser-side initializer has completed. `updateTTSVisualizer` must guard against a missing visualizer/state object and return safely rather than throwing null-init errors. This is a lifecycle guard only; it must not change the visual appearance or placement behavior of the visualizer.

The welcome neural animation message contract must remain single-owner. `showNeuralAnimation` should be registered as a Shiny custom message handler only in `www/js/shiny_message_handlers.js`. `www/js/neural_welcome.js` should expose `window.startNeuralWelcomeAnimation(...)` and own the animation implementation, but it must not register another `Shiny.addCustomMessageHandler('showNeuralAnimation', ...)`. This prevents load-order-dependent behavior when deferred welcome scripts initialize after the synchronous Shiny message handler layer.

#### Follow-up suggestions contract

Follow-up suggestions are controlled by the Yapılandırma setting `enable_followups`. This setting must be read through the tolerant server-side resolution path so logical, numeric, and string-like truthy values do not silently disable the feature. Keep the helper boundary around `coerce_followup_flag()` and `resolve_followup_enabled()` intact unless replacing it with an equally tolerant and tested path.

`build_followup_suggestions()` must not depend exclusively on an additional AI call. Local/deterministic suggestions and safe default suggestions are the reliability baseline; AI-generated suggestions may override them only when they are valid and non-empty. If the AI follow-up generator fails, returns malformed JSON, or returns too few suggestions, the UI should still receive usable follow-up suggestions whenever `enable_followups` is enabled.

Streaming messages may render the initial AI bubble before follow-up suggestions are known. The browser-side `updateFollowupSuggestions` handler must therefore continue to create `#followup_container_<message_id>` on demand when the container was not rendered by R. Do not assume the container always exists at initial message render time.

`push_followup_update()` should continue to send only non-empty cleaned suggestions and keep lightweight diagnostic logging for payload dispatch. Do not remove this logging unless an equivalent regression diagnostic is added elsewhere.

Protected by:
- `tests/testthat/test-followup-suggestions-regression.R`
- `tests/testthat/test-frontend-selector-contract.R`

Focused validation:
- `testthat::test_file("tests/testthat/test-followup-suggestions-regression.R")`
- `testthat::test_file("tests/testthat/test-frontend-selector-contract.R")`

### UI asset manifest contract

The frontend CSS/JS loading surface is now owned by `R/config_ui_assets.R`, not by a long inline asset list inside `ui.R`.

Current contract:

- `ui.R` should render frontend assets through `ui_asset_tags()`.
- Page or feature modules must not silently reintroduce local `tags$head(...)` CSS/JS includes for assets that are globally owned by `R/config_ui_assets.R`.
- The health dashboard is part of the global UI asset manifest: keep `css/health_dashboard.css` and `js/health_dashboard.js` in `R/config_ui_assets.R`, not in a local `tags$head(...)` block inside `R/module_health.R`.
- `www/js/health_dashboard.js` owns health-dashboard-specific behavior such as `initHealthTooltips`, `removeHealthTooltips`, tooltip cleanup, path-copy button binding, and unload cleanup.
- `updateHealthTimestamp` and `updateAdminTimestamp` are single-owned by `www/js/shiny_message_handlers.js` through the shared timestamp update helper. Do not register these message handlers again in `www/js/health_dashboard.js`.
- Do not reintroduce a giant inline list of `tags$link(...)` and `tags$script(...)` calls in `ui.R`.
- Browser-facing asset paths must remain public Shiny paths such as `css/...`, `js/...`, `codemirror/...`, and `lib/threejs/...`; file existence validation must resolve them under the Shiny public asset root, normally `www/`.
- Keep CodeMirror core, modes, and addons synchronous and ordered before CodeMirror-dependent code.
- Keep the SSO script synchronous and before critical app scripts.
- Keep Three.js dependencies ordered and deferred as a group; preserve the explicit order rules for `three.min.js`, `OrbitControls.js`, shader passes, `EffectComposer`, `RenderPass`, `UnrealBloomPass`, and `Lensflare.js`.
- Keep critical app scripts synchronous where existing client boot behavior depends on them.
- Keep deferred feature scripts deferred unless there is a demonstrated dependency that requires synchronous loading.
- Keep Bilge Yolaç modules in their explicit dependency order, starting with `js/bilge_yolac_motor.js` and ending with `js/bilge_yolac_kopru.js`.
- Keep `ui_asset_js_order_rules` as the manifest-level source of truth for critical browser dependency boundaries. Do not duplicate the same ordering logic in tests as a separate hard-coded list.
- Keep `ui_asset_validate_js_order()` wired into `ui_asset_validate(...)` so bad asset ordering fails early before the UI is rendered.
- Keep `ui_asset_deferred_js_paths()` as the single helper for resolving deferred JS groups; do not hand-flatten deferred groups in tests or UI rendering code.
- Keep `ui_asset_js_render_plan` as the single render-order plan for JS groups. `ui_asset_js_tags()` must render scripts from this plan rather than duplicating another hard-coded group order.
- Keep `ui_asset_validate_js_render_plan()` wired into `ui_asset_validate(...)`. It must fail early when a JS group is missing from the render plan, appears more than once, references a non-existent group, or disagrees with `ui_asset_deferred_js_groups`.
- Keep `ui_asset_render_plan_groups()` and `ui_asset_render_plan_deferred()` as the shared helpers for render-plan tests. Do not hand-reconstruct the same render-plan logic inside tests.
- When adding, removing, or renaming a JS group, update `ui_asset_js_groups`, `ui_asset_js_render_plan`, `ui_asset_deferred_js_groups` when applicable, and `tests/testthat/test-ui-asset-manifest-contract.R` together.
- Keep `js/music_manager.js` before `js/stt_client.js` and `js/tts_manager.js`. STT and TTS guard for missing globals, but the maintained asset contract should load the music manager before media consumers so duck/unduck behavior remains deterministic.
- Keep the background music lifecycle single-source. `MusicManager` should own one active audio element and must not allow overlapping main-theme, character-theme, TTS, STT, or intro music paths.
- Keep the startup music sequence deterministic: intro music belongs to `SpaceIntroMusic`; after the deep-space intro is dismissed, `MusicManager` starts the main theme once and then moves to randomized character music.
- Do not let duplicate `toggleMusic(TRUE)` calls skip the main theme. If a theme playlist request is pending, another same-state enabled toggle must not issue an early character playlist request or invalidate the pending theme request.
- Character music folders under `www/music/Karakter/` use stable lowercase character ids: `mergen`, `ulgen`, `kayra`, `erlik`, and `umay`. Do not rename these folders to visible labels such as `Ülgen` or `Umay Ana`.
- Keep welcome startup dependencies ordered so `js/shiny_message_handlers.js` owns the boot handler and `js/welcome_video_player.js`, `js/welcome_neural_modern.js`, `js/welcome_greeting.js`, and `js/welcome_greeting_personal.js` are available through the retry-based `initModernWelcome` path.
- Keep `js/encoding_utils.js` before `js/shiny_message_handlers.js` and before `js/claude_code_streaming.js`; both general Shiny messages and Bilge Yolaç streaming depend on the shared client-side encoding fallback.
- Keep deferred welcome handlers resilient to first-connect timing. `www/js/welcome_neural_modern.js` must register `updateNeuralColor` idempotently even when the script loads after the initial `shiny:connected` event; do not move this handler behind a connect-only registration that can be missed until reconnect.
- Keep `js/streaming_manager.js` before `js/claude_code_streaming.js`, and keep `js/claude_code.js`, `js/claude_code_streaming.js`, and `js/claude_code_plugins.js` in that order.
- Tests must continue to scan loaded JS files for duplicate `Shiny.addCustomMessageHandler(...)` message names.
- Asset-manifest tests should validate files that are intentionally loaded by the manifest. Do not require every physical file under `www/css` or `www/js` to appear in the manifest, because optional, legacy, or feature-specific public files may exist without being globally loaded.
- When adding, removing, renaming, or moving a frontend asset, update `R/config_ui_assets.R` and the asset manifest tests together.
- Do not add CDN usage. The app must remain fully offline/on-prem.
- Do not register duplicate `Shiny.addCustomMessageHandler(...)` handlers for the same message type.

Protected by:

- `tests/testthat/test-ui-asset-manifest-contract.R`
- `tests/testthat/test-frontend-selector-contract.R`
- `tests/testthat/test-e2e-boot-welcome-regression.R`
- `tests/testthat/test-e2e-health-dashboard-regression.R`

Focused validation:

- `testthat::test_file("tests/testthat/test-ui-asset-manifest-contract.R")`
- `testthat::test_file("tests/testthat/test-frontend-selector-contract.R")`
- `testthat::test_file("tests/testthat/test-e2e-boot-welcome-regression.R")`
- `testthat::test_file("tests/testthat/test-e2e-health-dashboard-regression.R")`

### Media and background music contract

Background music is a race-sensitive and encoding-sensitive boundary. Keep the current architecture intact:

- `SpaceIntroMusic` is only for the deep-space intro screen.
- `MusicManager` owns the main application background music after the intro is dismissed.
- The intended sequence is: main theme once, then randomized selected-character tracks.
- The main theme must not be skipped when Dinamik or Bütünleşik mode starts music from the welcome flow.
- Same-state duplicate `toggleMusic(TRUE)` calls must be idempotent while a theme playlist request is pending.
- Playlist responses must remain request-id guarded so stale responses cannot overwrite a newer music state.
- Audio load errors must remain bounded. Do not reintroduce a tight error -> next track -> error loop that can freeze the browser tab.
- Character music URL generation must encode each path segment as UTF-8. On Windows/Turkish locale, `Ülgen` filenames must produce `%C3%9C`, not native-byte `%DC`.
- Do not call `URLencode()` on a full native-encoded relative path for music files. Use the existing UTF-8 music URL helper path in `R/server_music_handlers.R`.
- Keep user-visible Turkish labels separate from stable character ids. The character id `ulgen` may correspond to visible text `Ülgen`, but the filesystem folder remains `www/music/Karakter/ulgen`.

Protected by:

- `tests/testthat/test-e2e-media-audio-state-regression.R`
- `tests/testthat/test-ui-asset-manifest-contract.R`
- `tests/testthat/test-frontend-selector-contract.R`
- `tests/testthat/test-e2e-boot-welcome-regression.R`
- `tests/testthat/test-global-source-manifest-contract.R`
- `tests/testthat/test-source-manifest-contract.R`
- `tests/testthat/test-production-contracts.R`
- `tests/testthat/test-maintainability-ratchet.R`

Focused validation:

- `testthat::test_file("tests/testthat/test-e2e-media-audio-state-regression.R")`
- `testthat::test_file("tests/testthat/test-ui-asset-manifest-contract.R")`
- `testthat::test_file("tests/testthat/test-frontend-selector-contract.R")`
- `testthat::test_file("tests/testthat/test-e2e-boot-welcome-regression.R")`
- `testthat::test_file("tests/testthat/test-global-source-manifest-contract.R")`
- `testthat::test_file("tests/testthat/test-source-manifest-contract.R")`
- `testthat::test_file("tests/testthat/test-production-contracts.R")`
- `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")`

When editing the UI asset contract, run `testthat::test_file("tests/testthat/test-ui-asset-manifest-contract.R")` first. This test intentionally uses the manifest’s `ui_asset_js_order_rules` and `ui_asset_js_render_plan` helpers instead of maintaining second independent order/render lists. Keep expectations compatible with the project’s installed `testthat` version; avoid optional expectation arguments that are not supported in older local environments.

### Attached welcome-screen animation contract

Returning from Kişiselleştirme to an already-attached Ana Söyleşi welcome screen must reboot the modern welcome animation stack after the welcome container is visible.

Current contract:

- The attached welcome-screen path in `R/server_welcome_handlers.R` must still show `#welcome_fullscreen_container`, hide `#chat_content_container`, refresh recent chats, and then send `initModernWelcome`.
- The same path must also send `initPersonalGreeting` so the personalized greeting sequence is not skipped.
- `www/js/character_manager.js` must not destroy and reinitialize the modern welcome neural canvas while that canvas is hidden or has zero dimensions. Hidden character changes may update stored/accent state, but visible canvas initialization should happen when the welcome screen is visible again.
- `www/js/shiny_message_handlers.js` owns `initModernWelcome` bootstrapping and must continue to initialize the video player, modern neural canvas, and greeting text through the existing boot/retry path.
- This behavior must preserve the existing UX: selecting a different character from Kişiselleştirme and then directly opening Ana Söyleşi should immediately show the left video, right neural animation, and dynamic greeting without requiring a quick action or Yeni Söyleşi round trip.

Protected by:

- `tests/testthat/test-e2e-boot-welcome-regression.R`
- `tests/testthat/test-frontend-selector-contract.R`

Focused validation:

- `testthat::test_file("tests/testthat/test-e2e-boot-welcome-regression.R")`
- `testthat::test_file("tests/testthat/test-frontend-selector-contract.R")`

High-risk frontend anchors are protected by `tests/testthat/test-frontend-selector-contract.R`. This test covers:

- chat input and send/stop wiring,
- centralized chat-input helper export and reuse by adjacent JS,
- stale `send_btn` regression protection for the main chat send/stop contract,
- quick-action button DOM wiring,
- TTS visualizer anchors and null-init guard,
- Bilge Yolaç dynamic tool-block lookup without unsafe selector interpolation.
- welcome and chat content containers,
- file upload, drag/drop, and file button selectors,
- File Manager attach checkbox and silent attach-state contracts,
- STT visualizer anchors,
- Bilge Yolaç prompt, output, welcome, and streaming anchors.
- stale selector regression scanning across all `www/js/*.js` files,
- message and CodeMirror chat-root observer cleanup and Shiny reconnect contracts,
- ChartLab rendering through current chat roots only, with stale `chat_content_wrapper`, broad `document.body`, and dynamic wrapper class selector regression protection,
- single-owner `showNeuralAnimation` Shiny handler wiring with `window.startNeuralWelcomeAnimation(...)` delegated animation startup,
- dynamic drag/drop getter usage for chat upload and File Manager upload surfaces,
- centralized File Manager attach-state handler registration.

When changing UI IDs/classes or JS selectors, update the actual UI, the JS handler, and the selector contract test together. Prefer robust delegated handlers for dynamic UI such as DataTables redraws. Do not remove working fallback selectors unless the UI contract has been verified.

File names must not be interpolated directly into CSS attribute selectors. For File Manager attach checkboxes, compare `data-filename` as a plain string after selecting `input.attach-checkbox[data-filename]`. This avoids hidden browser selector errors for filenames containing quotes, brackets, backslashes, or other selector-sensitive characters.

The same rule applies to Bilge Yolaç streaming tool identifiers. Do not interpolate streamed `toolId` values directly into CSS attribute selectors. Use a helper that selects `.cc-tool-block[data-tool-id]` elements and compares `data-tool-id` as a plain string. This prevents hidden `querySelector()` syntax failures when streamed tool IDs contain quotes, brackets, backslashes, or other selector-sensitive characters.

The File Manager attach-state browser handler must remain centralized in `R/helpers_file_manager_attach_client.R`. Do not move the inline JavaScript registration back into `R/module_file_manager.R`, and do not duplicate `Shiny.addCustomMessageHandler(nsPrefix + 'setAttachState', ...)` inside the module. The global `initAttachHandlerOnce` no-op handler should be registered once, while namespace-specific `setAttachState` handlers remain scoped by module namespace.

Because some JS files can contain invalid UTF-8 byte sequences in Windows VM environments, selector-contract tests that scan JS files must use the binary-safe reader pattern with `readBin(...)`, `iconv(..., sub = "byte")`, and byte-safe fixed matching. Do not replace this with plain `readLines(..., encoding = "UTF-8")` plus ordinary `grepl()` over unnormalized text. The selector contract test should continue to scan every `www/js/*.js` file for stale `message_input` references and should keep explicit checks that `app_core.js` does not reintroduce `#_content_container`. The same selector-contract scan must continue to reject stale `chat_content_wrapper` references across `www/js/*.js` and must keep the `showNeuralAnimation` handler centralized.

### E2E/race regression test foundation contract

The repository now has a deterministic E2E-style regression foundation for quick actions and true-streaming request lifecycle behavior. It intentionally uses `testthat` plus local state/service stubs instead of adding a browser automation dependency. This keeps the suite compatible with offline/on-prem Windows VM environments and avoids real DB, real LLM, TTS/STT, image endpoint, or public internet requirements.

The latest behavioral coverage pass also strengthens focused unit/integration checks for quick-action routing, duplicate quick-action configuration protection, LLM response parsing, request-scoped send-message cleanup, File Manager storage and upload policy, MCP Excel context cleanup, refresh guard behavior, Bilge Yolaç stale finalization and directory observation, document-summary CLI context reset, and SSO identity readiness. These tests are intentionally fast, deterministic, and service-free: they must not require a real DB, real LLM endpoint, real SSO/Keycloak server, browser automation, API keys, or internet access.

Current files:

- `tests/testthat/helper_e2e_race_harness.R`
- `tests/testthat/test-e2e-quick-actions-streaming-regression.R`

The quick-action/streaming slice also protects the browser-side duplicate-click boundary for welcome quick-action buttons. `www/js/shiny_message_handlers.js` must debounce the same action/model pair before calling `Shiny.setInputValue('quick_template', ...)`, temporarily disable the clicked button with `aria-disabled`, and then restore it after the debounce window. The deterministic harness in `helper_e2e_race_harness.R` models this client gate, and `test-e2e-quick-actions-streaming-regression.R` checks both the state behavior and the static JS token order so the debounce guard remains before the Shiny event.

Additional behavioral contract tests:

- `tests/testthat/test-quick-action-routing.R`: verifies every quick-action id resolves to the expected tool family, setting flag, and configured model; applying an action leaves only one tool flag active; the real `mergen_determine_tool_family()` routing helper is covered; MCP Excel without files does not route to `mcp_excel`; `skip_mcp_once` has precedence; duplicate ids/families/flags and unexpected model ids remain protected; and the quick-action/file-policy boundary stays aligned so summarization rejects Excel while MCP Excel cleanup keeps only one Excel file and removes non-Excel or excess selections.
- `tests/testthat/test-llm-content-reasoning-fallback.R`: verifies `message$content`, top-level `message$content`, `delta$content`, choice `text`, top-level `response$text`, nested text nodes, `reasoning_content`, choices-free top-level `reasoning_content`, and reasoning fallback enabled/disabled behavior.
- `tests/testthat/test-send-message-request-lifecycle-contract.R`: verifies current/stale/stopped request states, stopped active-request cleanup, request-scoped typing-wrapper cleanup, stale cleanup paths that must not remove a newer request’s wrapper, and cleanup that fails closed when `active_request_id` cannot be read.
- `tests/testthat/test-file-manager-policy-contract.R`: verifies upload policy helpers, user id normalization, user-specific upload folder derivation, invalid-user persistence prevention, summarization-mode Excel rejection, MCP Excel cleanup, and stale refresh guard behavior.
- `tests/testthat/test-upload-validator.R`: verifies too-large file rejection, unsafe filename rejection, ASCII control-byte filename rejection, unsupported extension rejection when a whitelist exists, dotted whitelist entries and uppercase visible extensions, valid UTF-8 Turkish filename acceptance, and invalid UTF-8 filename rejection.
- `tests/testthat/test-claude-code-run-lifecycle-contract.R`: verifies stale/active Bilge Yolaç finalization, stale directory observation suppression, early-abort cleanup, blocked-message payload safety, stop finalization, and document-summary CLI context reset.
- `tests/testthat/test-e2e-sso-identity-readiness-regression.R`: verifies refreshable modules wait for SSO identity readiness, do not refresh while `authenticated=TRUE` but `auth_ready=FALSE`, refresh immediately when already ready, preserve local non-SSO behavior, and can be run individually without depending on full-suite bootstrap side effects.

Additional media/audio race files:

- `tests/testthat/helper_e2e_media_audio_harness.R`
- `tests/testthat/test-e2e-media-audio-state-regression.R`

Additional file-context and refresh race files:

- `tests/testthat/helper_e2e_file_context_harness.R`
- `tests/testthat/test-e2e-file-context-regression.R`

Additional saved-chat/history/gallery race files:

- `tests/testthat/helper_e2e_chat_persistence_harness.R`
- `tests/testthat/test-e2e-chat-persistence-regression.R`

Additional health dashboard race files:

- `tests/testthat/helper_e2e_health_dashboard_harness.R`
- `tests/testthat/test-e2e-health-dashboard-regression.R`

Additional boot/welcome regression file:

- `tests/testthat/test-e2e-boot-welcome-regression.R`

Additional premium reasoning / thinking UI race files:

- `tests/testthat/helper_e2e_reasoning_ui_harness.R`
- `tests/testthat/test-e2e-premium-reasoning-ui-regression.R`

Additional streaming client request-id safety file:

- `tests/testthat/test-e2e-streaming-client-request-id-regression.R`

Additional SSO identity readiness race files:

- `tests/testthat/helper_e2e_sso_identity_harness.R`
- `tests/testthat/test-e2e-sso-identity-readiness-regression.R`

The saved-chat/history/gallery slice follows the same deterministic `testthat` strategy. It must not require a real browser, real production DB, real LLM, real image-generation endpoint, TTS/STT endpoint, or public internet. It models saved-chat ordering, final-answer persistence idempotency, stale delete/load events, loaded-chat TTS suppression, history refresh cache safety, and user-scoped image gallery refresh behavior through local state stubs.

The health dashboard slice follows the same deterministic testthat strategy. It must not require a real browser, real production DB, real LLM, real TTS/STT endpoint, real image-generation endpoint, or public internet. It models rendered health tab snapshots, secret redaction, public endpoint skip behavior before network probing, idempotent refresh application, stale refresh suppression, timestamp/tooltip cleanup message contracts, and static wiring contracts for R/helpers_health_checks.R, R/module_health.R, ui.R, and www/js/health_dashboard.js.

The boot/welcome slice follows the same deterministic `testthat` strategy. It must not require a real browser, real production DB, real LLM, real TTS/STT endpoint, real image-generation endpoint, or public internet. It models non-SSO test boot safety, `MERGEN_RUN_APP=false` and `MERGEN_DISABLE_FUTURES=true` guard behavior, valid `create_mergen_app()` construction, modern welcome-screen rendering, quick-action button wiring, recent-chat ordering, prompt-send separation, browser/localStorage restore wiring, and the requirement that loading old chat state must not trigger TTS or music side effects. It also protects UTF-8 Turkish text in rendered welcome HTML and static client contracts.

The premium reasoning / thinking UI slice follows the same deterministic `testthat` strategy. It must not require a real browser DOM, real production DB, real LLM, real SSE endpoint, real TTS/STT endpoint, real image-generation endpoint, or public internet. It models PremiumReasoning-style request-scoped panel lifecycle behavior through local state stubs and protects duplicate/flicker prevention, stale reasoning callback suppression, stream-start migration into the assistant bubble, idempotent reset/finalization, simulated reasoning cleanup, and strict separation between visible answer text and persisted reasoning traces.

The streaming client request-id safety slice follows the same deterministic `testthat` strategy. It must not require a real browser DOM, real production DB, real LLM, real SSE endpoint, real TTS/STT endpoint, real image-generation endpoint, or public internet. It protects the wiring between server-side request ids and browser custom-message handlers by checking that `premiumReasoningStart`, `premiumReasoningStreamStart`, `initStreamingMessage`, `streamingReasoningDelta`, `streamingDelta`, `streamingUpdate`, and `finalizeStreamingMessage` carry or honor `requestId` where required. It also protects client-side stale callback suppression and duplicate finalization guards so old async stream/reasoning callbacks cannot contaminate a newer active request.

The SSO identity readiness slice follows the same deterministic `testthat` strategy. It must not require a real browser, real Keycloak server, real production DB, real LLM, real TTS/STT endpoint, real image-generation endpoint, or public internet. It models refreshable File Manager and Image Gallery module wiring while the session still has a temporary `user_id = 0`, verifies that user-scoped refresh happens only after SSO authentication and identity readiness are complete, verifies that already-ready SSO sessions refresh immediately without waiting for a stale observer event, and verifies that local non-SSO mode is not changed by the SSO auth-ready hook.

The file-context slice follows the same deterministic `testthat` strategy. It must not require a real browser, real production DB, real persistent file store, real LLM, TTS/STT endpoint, image endpoint, or public internet. It models File Manager upload/context state, summarization-mode extension restrictions, MCP Excel-only attachment behavior, single-Excel enforcement, invalid or early user-id refresh skips, stale refresh request protection, and browser/client restore with stale attachment IDs through local state stubs.

The saved-chat/history/gallery slice intentionally stays browserless. It protects the server-side state and wiring contracts that are most likely to regress before a manual VM/browser run: saved chat ordering after a final answer, exactly-once persistence for a request, stale load suppression after delete, no TTS autoplay when loading old chats, invalid or early user-id refresh skips for history/gallery, and user-scoped gallery cache replacement.

The media/audio slice follows the same deterministic `testthat` strategy. It must not require a real browser, real `Audio`, microphone access, DB, LLM, TTS/STT endpoint, image endpoint, or public internet. It models TTS queueing, STT modal audio suppression, and background-music exclusivity with local state stubs, and it also checks that the key JS hook contracts remain present in `music_manager.js`, `tts_manager.js`, `stt_client.js`, and `premium_reasoning.js`.

Because Windows VM environments can expose JS comments or other text as native/ANSI rather than valid UTF-8, the media JS contract test reads JS files as raw bytes and normalizes non-ASCII bytes before searching for ASCII hook names. Do not replace this byte-safe reader with plain `readLines(..., encoding = "UTF-8")` or `grepl(..., perl = TRUE)` over unnormalized text; that can reintroduce invalid UTF-8 warnings and false-negative contract failures on the VM.

The first slice protects these contracts:

- quick-action clicks select the expected tool/model mode,
- quick-action clicks hide the welcome state and show a ready-made intro message,
- quick-action clicks must not trigger an LLM request by themselves,
- quick-action intro messages must not be persisted to DB, added to saved chats, or included in model context,
- rapid quick-action clicks must converge to one active tool mode,
- the same quick-action/model pair double-clicked within the client debounce window must be suppressed before it becomes a Shiny event,
- rapidly switching to a different quick action must still be allowed and the last selected tool/model state must win,
- a prompt sent immediately after a quick-action click must produce exactly one user request,
- SSE visible deltas and reasoning deltas must remain separate,
- stream finalization must be idempotent for a request,
- stale request finalization must not update the newer active request,
- stop-generation state must be request-scoped and must not poison the next request,
- simulated reasoning phases must not be persisted as real reasoning.

The media/audio slice protects these contracts:

- background music must have at most one active audio source,
- stale playlist responses must not overwrite newer music state,
- character or mode changes must stop the previous track before starting the next flow,
- TTS chunks must be queued and played in chunk-index order,
- TTS playback must duck background music and must not unduck it until the queue drains,
- TTS stop must clear the queue, current audio, and reported playing state,
- STT start must fully duck/silence background music,
- ordinary TTS/music unduck calls must not restore music while STT is active,
- STT cleanup must restore music state safely,
- navigation or new-chat cleanup must not leave stale TTS, STT, or music state behind,
- static JS contracts must continue to expose the expected audio/reasoning hooks.

The file-context slice protects these contracts:

- summarization upload validation must reject Excel files while accepting valid UTF-8 Turkish document filenames,
- MCP Excel context cleanup must remove non-Excel files, stale selection ids, and excess Excel files,
- refresh request guards must reject invalid or stale request ids before applying refreshed file state,
- upload validation must reject invalid UTF-8 filenames and ASCII control-byte filenames in addition to path traversal, unsupported extensions, and oversized files, while accepting valid UTF-8 Turkish filenames.

Use raw-byte checks for ASCII control characters in filenames; do not replace them with `grepl("[[:cntrl:]]", ..., useBytes = TRUE)`, because that can misclassify valid UTF-8 Turkish characters on Windows/R locales.

- supported uploads must appear in File Manager table/state,
- Model Context attachment toggles must update the parent session context,
- summarization mode must reject unsupported file types and keep supported document types,
- MCP/Excel mode must reject non-Excel files,
- MCP/Excel mode must keep only one Excel file attached,
- switching MCP/Excel mode on must remove non-Excel and excess Excel selections,
- invalid user IDs such as `0`, `unknown`, empty, or `NULL` must not wipe existing File Manager state during refresh,
- SSO-not-ready refresh attempts must skip safely without mutating current file state,
- stale refresh results must not overwrite a newer refresh result,
- refresh restore must preserve previously attached files by display name,
- browser/client restore must ignore ghost attachment IDs safely,
- static File Manager JS/server hook contracts must continue to expose upload, file action, attach toggle, and silent attach-state behavior.

The saved-chat/history/gallery slice protects these contracts:

- saved chat ordering must follow last activity after a new final answer,
- stream/finalization persistence must be idempotent for the same request id,
- loading an old saved chat must not trigger TTS autoplay,
- deleting the current chat must return safely to the welcome state,
- stale load events for a just-deleted chat must be ignored,
- history refresh attempts with invalid or early user ids must not wipe the last valid cache,
- image gallery refresh must remain user-scoped,
- invalid gallery refresh attempts must not wipe the last valid user cache,
- static contracts in `server_observers_saved_chats.R`, `module_saved_chats.R`, `module_chat_history.R`, `module_image_gallery.R`, and `server_module_wiring.R` must remain present.

The health dashboard slice protects these contracts:

- raw secret values such as API keys, tokens, passwords, and credentials must not leak into health check output or rendered tab snapshots,
- public internet endpoints must not be called from the health dashboard; they must be skipped with a warning before any network probe,
- local/on-prem endpoint checks are represented by deterministic stubs in tests and must not require public internet,
- a refresh result must be applied at most once for a refresh id,
- stale refresh results must not overwrite newer dashboard state,
- timestamp and tooltip cleanup custom-message contracts must remain wired,
- health dashboard JavaScript must not introduce public URL dependencies,
- offline refresh, public URL guard, and cleanup hook contracts must remain present in R/helpers_health_checks.R, R/module_health.R, ui.R, and www/js/health_dashboard.js.

The boot/welcome slice protects these contracts:

- app.R can be sourced in non-SSO test mode without launching the Shiny app,
- test boot must keep future execution disabled or sequential,
- `validate_boot_state()` and `create_mergen_app()` must remain valid,
- the modern welcome screen must render the expected root, greeting, quick-action, and recent-chat anchors,
- quick-action buttons must preserve `data-action-id`, `data-action-model`, and `_handleQuickAction` wiring,
- recent chats on the welcome screen must remain ordered by latest activity,
- quick-action input and normal prompt-send input must remain separate,
- browser/localStorage restore must route through `load_chat_from_storage`,
- browser/localStorage restore must not trigger TTS, audio, or music side effects for old chats,
- Turkish characters must remain intact in welcome HTML and static JS/R contract checks.

The premium reasoning / thinking UI slice protects these contracts:

- starting premium reasoning for one request must create at most one live panel,
- repeated start events for the same request must not duplicate or flicker the panel state,
- a new request must cleanly replace the previous active reasoning shell,
- stale reasoning deltas from an old request must not contaminate the active request,
- stale stream-start events from an old request must be ignored,
- stream start for the active request must migrate the reasoning panel into the assistant bubble model,
- reset/finalization must be idempotent for a request,
- simulated reasoning phases for non-thinking models must be removed on visible stream start,
- simulated reasoning must never be persisted as real reasoning,
- visible answer text and reasoning trace text must remain separate through finalization,
- static JS/R wiring contracts for `premiumReasoningStart`, `premiumReasoningStreamStart`, `streamingReasoningDelta`, `finalizeStreamingMessage`, `reasoning_content`, and `reasoning_trace_value` must remain present.

The streaming client request-id safety slice protects these contracts:

- `send_message()` must create one request id and pass it into both the reasoning shell and true-streaming path,
- `handle_true_streaming_mode()` must prefer `ctx$request_id` and only generate a new request id as a fallback,
- true-streaming browser messages must include `requestId` for `premiumReasoningStreamStart`, `initStreamingMessage`, `streamingReasoningDelta`, `streamingDelta`, `streamingUpdate`, and `finalizeStreamingMessage`,
- `www/js/streaming_manager.js` must store the active message request id, ignore stale streaming payloads, and finalize a message at most once,
- `www/js/premium_reasoning.js` must track the active reasoning request id and ignore stale reasoning deltas or stream-start callbacks,
- server-side request lifecycle guards and client-side stale callback guards must remain aligned,
- maintainability ratchet limits must remain strict; do not loosen thresholds to make these checks pass.

The SSO identity readiness slice protects these contracts:

- authenticated SSO sessions must still wait for `auth_ready = TRUE`; `authenticated = TRUE` alone must not trigger user-scoped refresh with temporary user ids.
- refreshable modules must not run user-scoped refresh work with temporary or invalid user ids such as `0`, empty, `unknown`, or `NULL`,
- File Manager must receive `auth_ready_provider = identity$is_auth_ready` before being attached as a refreshable module,
- File Manager and Image Gallery refresh hooks must wait for SSO authentication and identity readiness when SSO is still in progress,
- if SSO authentication and identity readiness are already complete before observer registration, the refresh callback must run immediately instead of waiting for an event that already happened,
- local non-SSO mode must remain a no-op for SSO auth-ready refresh hooks,
- `R/server_module_wiring.R` must keep the File Manager and Image Gallery auth-ready refresh wiring visible and testable,
- `R/server_runtime_context.R` must bootstrap all helper functions from `R/helpers_server_runtime_contracts.R`, not only `is_server_runtime_context()`. Individually run tests must not depend on helper functions left in the global environment by earlier full-suite tests.
- the slice must remain test-only under `tests/testthat/` and must not require updates to `global.R` or runtime source order,
- maintainability ratchet limits must remain strict; do not loosen thresholds to make these checks pass.

Focused validation:

    testthat::test_file("tests/testthat/test-e2e-boot-welcome-regression.R")
    testthat::test_file("tests/testthat/test-e2e-premium-reasoning-ui-regression.R")
    testthat::test_file("tests/testthat/test-e2e-streaming-client-request-id-regression.R")
    testthat::test_file("tests/testthat/test-e2e-sso-identity-readiness-regression.R")
    testthat::test_file("tests/testthat/test-e2e-quick-actions-streaming-regression.R")
    testthat::test_file("tests/testthat/test-e2e-media-audio-state-regression.R")
    testthat::test_file("tests/testthat/test-e2e-file-context-regression.R")
    testthat::test_file("tests/testthat/test-e2e-chat-persistence-regression.R")
    testthat::test_file("tests/testthat/test-e2e-health-dashboard-regression.R")

Related focused tests:

    testthat::test_file("tests/testthat/test-send-message-request-lifecycle-contract.R")
    testthat::test_file("tests/testthat/test-quick-action-routing.R")
    testthat::test_file("tests/testthat/test-llm-content-reasoning-fallback.R")
    testthat::test_file("tests/testthat/test-file-manager-policy-contract.R")
    testthat::test_file("tests/testthat/test-upload-validator.R")
    testthat::test_file("tests/testthat/test-claude-code-run-lifecycle-contract.R")
    testthat::test_file("tests/testthat/test-send-message-prompting-contract.R")
    testthat::test_file("tests/testthat/test-llm-stream-io-contract.R")
    testthat::test_file("tests/testthat/test-streaming-should-stop.R")
    testthat::test_file("tests/testthat/test-sse-worker-export-contract.R")
    testthat::test_file("tests/testthat/test-file-manager-context-policy-contract.R")
    testthat::test_file("tests/testthat/test-file-manager-refresh-guard-contract.R")
    testthat::test_file("tests/testthat/test-file-manager-state-runtime-contract.R")
    testthat::test_file("tests/testthat/test-file-manager-module-policy-wiring.R")
    testthat::test_file("tests/testthat/test-resolve-uploaded-file.R")
    testthat::test_file("tests/testthat/test-server-chat-persistence-wiring-contract.R")
    testthat::test_file("tests/testthat/test-health-check-formatters.R")
    testthat::test_file("tests/testthat/test-health-check-paths.R")
    testthat::test_file("tests/testthat/test-health-check-env-contract.R")
    testthat::test_file("tests/testthat/test-health-check-runtime-contract.R")
    testthat::test_file("tests/testthat/test-maintainability-ratchet.R")
    source("tests/scripts/maintainability_report.R", encoding = "UTF-8")

Full strict validation remains:

    source("tests/testthat.R", encoding = "UTF-8")

`tests/testthat/test-resolve-uploaded-file.R` must remain safe to run individually with `testthat::test_file(...)`. It should explicitly bootstrap the minimal File Store source chain it tests instead of relying on full-suite side effects or functions left in the global environment by earlier tests. This protects diagnostic workflows where a single resolver/file-store test is run after an E2E failure.

`tests/testthat/test-llm-reasoning-request-overrides.R` must remain safe and warning-free when run individually with `testthat::test_file(...)`. Its bootstrap should prepare a valid temporary test log directory, preserve any inherited `MERGEN_LOG_DIR` directory if present, and redirect the logger file appender to a test-local log file before sourcing `R/config_api.R`. This protects the strict suite from missing log-file warnings under `stop_on_warning = TRUE` while still testing reasoning request override contracts.

The saved-chat/history/gallery E2E slice is also test-only and must remain under `tests/testthat/`. It should not require updates to `global.R`, should not be sourced by runtime code, and should not affect the runtime maintainability ratchet because `tests/scripts/maintainability_report.R` evaluates runtime files only.

The health dashboard E2E slice is also test-only and must remain under tests/testthat/. It should not require updates to global.R, should not be sourced by runtime code, and should not affect the runtime maintainability ratchet because tests/scripts/maintainability_report.R evaluates runtime files only.

The SSO identity readiness E2E slice is also test-only and must remain under `tests/testthat/`. It should not require updates to `global.R`, should not be sourced by runtime code, and should not affect the runtime maintainability ratchet because `tests/scripts/maintainability_report.R` evaluates runtime files only.

Do not replace this foundation with Playwright, Cypress, shinytest2, or another browser-level dependency unless the dependency is explicitly available in the offline/on-prem deployment environment or vendored/installed through an approved offline process. Browser-level tests may be added later as a separate layer, but they should not weaken or remove these deterministic contract tests.

### LLM worker tool-result formatting contract

The non-streaming LLM worker is intentionally split across three helper layers. Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/helpers_llm_worker_payload.R",       encoding = "UTF-8")
safe_source("R/helpers_llm_worker_tool_results.R", encoding = "UTF-8")
safe_source("R/helpers_llm_worker.R",               encoding = "UTF-8")
```

Responsibilities:

* `R/helpers_llm_worker_payload.R`: chat-history-to-message conversion, system-message merging, chart intent detection, fallback chart hooks, chart summaries, and automatic insight text helpers.
* `R/helpers_llm_worker_tool_results.R`: MCP tool-result logging, dataframe/chart/plain-text result formatting, dataframe-to-markdown conversion for second-pass prompts, and aggregation of formatted tool results.
* `R/helpers_llm_worker.R`: public `call_llm_worker(...)` runtime API, model/request assembly, MCP tool schema selection, API call handling, MCP tool execution orchestration, strict-data-only handling, second-pass orchestration, and final error normalization.

Do not move MCP tool-result formatting back into `R/helpers_llm_worker.R`; doing so can bring the worker back to the 800+ line threshold and blur the runtime orchestration boundary.

Race-condition contract:

* `call_llm_worker(...)` may prepare a `session_obj` from `settings$mcp_registry_snapshot` when the live Shiny session is missing or no longer has the needed file registry.
* MCP tool execution must use that prepared `session_obj`.
* Do not reintroduce `current_session <- if (!is.null(settings$shiny_session)) settings$shiny_session else NULL` in the MCP execution path. That bypasses the snapshot guard and can make async workers resolve files from stale or empty live session state.

Maintainability note:

* `tests/scripts/maintainability_report.R` counts simple `function(` patterns, including anonymous handlers in code and misleading examples in comments. Keep new helper files small, avoid unnecessary anonymous handlers in ratcheted files, and avoid comment text that accidentally contains patterns such as `= function(` unless truly needed.

Protected by:

```text
tests/testthat/test-llm-worker-payload-refactor-contract.R
tests/testthat/test-llm-worker-tool-results-refactor-contract.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-maintainability-ratchet.R
```


### Bilge Yolaç run lifecycle request-id contract

Bilge Yolaç normal streaming finalization must remain request-scoped. `R/module_claude_code.R` creates a `run_request_id`, stores it in `rv$active_request_id`, and carries it through `stream_env$request_id`. Any normal streaming completion path that calls `finalize_streaming()` for `Tamamlandı` or `Hata` must pass `request_id = env$request_id`.

This requirement is not cosmetic. `finalize_streaming()` intentionally accepts a request id so stale poll/callback results cannot clear the runtime state of a newer active Bilge Yolaç run. Do not reintroduce request-id-less normal completion or error finalization calls such as `finalize_streaming("Tamamlandı", ...)` or `finalize_streaming("Hata", ...)` without the request id.

The stop and timeout paths must also remain request-scoped. The normal success/error paths now follow the same stale-run safety boundary.

Early-abort paths before streaming starts must also clear state through the shared lifecycle helper. If a run has already called `cc_mark_active_run(rv, run_request_id)` but then fails preflight or process-start checks, use `cc_abort_run_before_streaming(rv, run_request_id)` instead of manually setting only `rv$is_running <- FALSE`. This prevents a blocked or failed pre-stream run from leaving stale `rv$active_request_id` state that could affect the next run. Blocked-run UI error payloads should go through `cc_send_run_blocked_message()` so the repeated `cc-add-message` error shape stays centralized and safely escaped.

Protected by:
- `tests/testthat/test-claude-code-run-lifecycle-contract.R`
- `tests/testthat/test-maintainability-ratchet.R`

Focused validation:
- `testthat::test_file("tests/testthat/test-claude-code-run-lifecycle-contract.R")`
- `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")`
- `source("tests/scripts/maintainability_report.R", encoding = "UTF-8")`
- `source("tests/testthat.R", encoding = "UTF-8")`

Validation after edits:
- These are documentation-only changes.
- Ensure README.md remains Turkish and UTF-8.
- Ensure CLAUDE.md remains English and UTF-8.
- Run a diff and confirm only README.md and CLAUDE.md changed.
- Do not run or change runtime code.
- Do not delete any existing documentation content.

### Bilge Yolaç directory-listing contract

Bilge Yolaç directory listing is intentionally split from the broad CLI helper file.

Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/helpers_claude_code_process.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_runtime_workdir.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_directory_listing.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_server_setup.R", encoding = "UTF-8")
```

Responsibilities:

* `R/helpers_claude_code_directory_listing.R`: directory path variant generation, relaxed directory listing, persistent storage display-name resolution, directory entry normalization, and the public-compatible `list_directory_contents()` helper.
* `R/helpers_claude_code.R`: Claude Code CLI run orchestration, CLI status/connection checks, output formatting, tool-use HTML formatting, and thinking-message selection.

Do not move `list_directory_contents()` or its directory display-name/path-variant logic back into `R/helpers_claude_code.R`. Keeping this boundary prevents `R/helpers_claude_code.R` from returning to the 25+ function maintainability threshold.

Race-condition contracts:

* Directory listing must not run before the SSO/user identity readiness check in `R/helpers_claude_code_server_setup.R`.
* Directory refresh results must remain protected by `dir_refresh_guard$is_latest(refresh_id)` so stale refreshes cannot overwrite newer UI state.
* Display-name resolution must continue to use persistent file-store metadata so timestamp/hash storage names do not leak into the Bilge Yolaç directory UI.

Protected by:

```text
tests/testthat/test-claude-code-directory-listing-contract.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-claude-code-dir-ui-refactor-contract.R
tests/testthat/test-maintainability-ratchet.R
```

### Windows VM real preflight SSO contract

tests/scripts/run_vm_preflight_real.R is the production-like Windows VM preflight entry point. It must not silently pass when the VM is accidentally running in local/non-SSO identity mode, and it must fail early when mandatory production environment variables are missing.

Current contract:

- MERGEN_PREFLIGHT_REQUIRE_SSO defaults to TRUE.
- When MERGEN_PREFLIGHT_REQUIRE_SSO=TRUE, the preflight must fail unless SSO_ENABLED=TRUE.
- Local or developer smoke runs may explicitly set MERGEN_PREFLIGHT_REQUIRE_SSO=FALSE.
- LOCAL_LLM_ENDPOINT, DB_DSN, and AI_KEYS_MASTER are mandatory for the real preflight.
- When SSO is enabled, SSO_KEYCLOAK_URL is also mandatory.
- Missing mandatory environment variables must fail fast before app boot with a clear error message.
- After app.R is sourced and validate_boot_state() passes, the preflight must verify that SSO_ENABLED is active and that SSO_CONFIG contains usable keycloak_base_url, issuer_url, auth_endpoint, logout_endpoint, token_endpoint, client_id, and realm values.
- Derived SSO URL fields must remain valid http:// or https:// URLs.
- The preflight sources `tests/scripts/helpers_vm_preflight_checks.R` for reusable VM checks instead of keeping every probe inline in `run_vm_preflight_real.R`.
- The default VM preflight includes core writable path checks, atomic-write probe, UTF-8 file write/read roundtrip, live `current_user_id` provider contract, SSO auth-ready immediate refresh contract, real DB health check, and local LLM endpoint reachability.
- `run_vm_preflight_real.R` must restore any process-wide environment variables it changes on exit. In particular, it must not leak `MERGEN_DISABLE_FUTURES`, `MERGEN_RUN_APP`, or `MERGEN_SQL_LOADER_STRICT` into later tests or developer commands in the same R session.
- File Store roundtrip validation is optional and must remain disabled by default. It should run only when `MERGEN_PREFLIGHT_CHECK_FILE_STORE=TRUE` is explicitly set, because it touches real shared/indexed file storage and is a deeper diagnostic rather than the normal fast VM preflight path.
- Expected preflight degradations that should not fail the run should be printed as `INFO:` or `WARN:` console lines, not emitted through `warning()`, because the strict suite uses `stop_on_warning = TRUE`.
- Do not weaken this preflight into a generic boot-only check. Boot, DB, storage, atomic-write, and LLM endpoint checks are necessary but not sufficient for the Windows VM production profile.

This contract prevents a real VM validation run from passing while the app is actually using the local process user instead of the authenticated SSO user. That failure mode can mask user-scoped saved-chat, history, gallery, file-manager, and DB persistence regressions.

The VM preflight also protects the post-auth refresh timing contract. If SSO authentication and identity readiness are already complete before a refreshable module registers its auth-ready observer, `serverRuntimeOnSsoAuthReady(...)` must run the callback immediately instead of waiting for an event that has already happened. This prevents File Manager, Image Gallery, and similar refreshable modules from missing their first user-scoped refresh after SSO login.

Focused guard behavior:

- tests/testthat/test-vm-preflight-guard-contract.R keeps the missing-env-var failure path isolated from the SSO guard by setting MERGEN_PREFLIGHT_REQUIRE_SSO=FALSE.
- Keep that test focused on missing mandatory env vars. Do not make it depend on child-process stdout/stderr parsing.

The helper contract test must stay static and fast. It should inspect the helper/preflight script contracts without sourcing `app.R`, running the real VM preflight, touching the real DB, contacting the LLM endpoint, or performing the optional File Store roundtrip.

Protected by:

    tests/testthat/test-vm-preflight-contract.R
    tests/testthat/test-vm-preflight-guard-contract.R
    tests/testthat/test-vm-preflight-helper-contract.R

### User session initialization contract

Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/server_init_forward_refs.R",  encoding = "UTF-8")
safe_source("R/helpers_user_session_identity.R", encoding = "UTF-8")
safe_source("R/server_init_user_session.R",  encoding = "UTF-8")
safe_source("R/helpers_server_runtime_contracts.R", encoding = "UTF-8")
safe_source("R/server_runtime_context.R",    encoding = "UTF-8")
safe_source("R/server_runtime_function_slot.R", encoding = "UTF-8")
safe_source("R/server_module_wiring.R",      encoding = "UTF-8")
safe_source("R/server_init_session_state.R", encoding = "UTF-8")
safe_source("R/server_init_chat_runtime.R",  encoding = "UTF-8")
```

Server runtime contract helper split:

- R/helpers_server_runtime_contracts.R owns the low-level runtime validation and error helpers used by the server runtime context layer.
- R/server_runtime_context.R owns runtime context orchestration, context attach/require helpers, refreshable module registration, and SSO auth-ready refresh behavior.
- Do not move is_server_runtime_context(), .server_runtime_stop(), .server_runtime_require_context(), .server_runtime_require_values(), .server_runtime_require_functions(), or .server_runtime_invoke_auth_ready_callback() back into R/server_runtime_context.R.
- serverRuntimeOnSsoAuthReady() must keep the already-auth-ready path and the observer-fired path on the same .server_runtime_invoke_auth_ready_callback() helper. This prevents immediate SSO refresh behavior and delayed observer refresh behavior from drifting apart.
- This boundary creates maintainability headroom under the 25-function file threshold without changing public runtime APIs.

Protected by:

- tests/testthat/test-server-runtime-context.R
- tests/testthat/test-source-manifest-contract.R
- tests/testthat/test-maintainability-ratchet.R
- tests/testthat/test-e2e-sso-identity-readiness-regression.R

`R/server_core_interaction_runtime.R` is sourced later in `global.R`, after observer/output helpers such as `R/server_outputs_downloads.R`. This is intentional: the core interaction binder depends on concrete observer/output functions and should not rely on forward placeholders.

- `R/helpers_user_session_identity.R` owns pure user-session identity helpers: `build_user_session_config()`, `apply_user_session_identity()`, `make_current_user_id_provider()`, and `make_user_session_data_accessors()`.
- `R/server_init_user_session.R` owns local/SSO identity setup orchestration and must be sourced after `R/helpers_user_session_identity.R`.
- Identity-related compatibility reads and writes to `session$userData` must flow through `make_user_session_data_accessors()` rather than new ad hoc assignments.
- `apply_user_session_identity()` must remain the public compatibility write path, but internally it should delegate to `make_user_session_data_accessors()`.
- SSO placeholder state such as `user_id = 0L`, `sso_active = TRUE`, and `auth_initialized = FALSE` should be written through the session-data accessor, not by loose assignments in server initialization code.
- Runtime code should prefer accessors exposed through `runtime_ctx$identity`.
- Identity display values should come from `identity$get_first_name` and `identity$get_display_name` rather than direct `session$userData` reads in `server.R`.
- Auth readiness should come from `identity$is_auth_ready`.

`R/server_runtime_context.R` owns the early server boot contract that carries identity, cache, forward references, session state, and chat runtime into `server.R` through one explicit context object.

The source-order contract is intentional: `R/helpers_user_session_identity.R` must load before `R/server_init_user_session.R`, and `R/server_init_user_session.R` must load before `R/server_runtime_context.R`. Do not collapse the helper back into the initializer unless a future refactor replaces it with an equally explicit and tested boundary.

`R/server_module_wiring.R` owns medium-level server module wiring through focused helper functions. It binds service modules, settings/forward references/Bilge Yolaç startup wiring, media modules, the file-preview/follow-up prelude, and the chat engine wiring boundary. Keep this helper sourced after `R/server_runtime_context.R` and before session/chat runtime initialization.

`R/server_core_interaction_runtime.R` sits one level above those wiring helpers: `server.R` calls `serverBindCoreInteractionRuntime(...)`, and that helper delegates File Manager setup to `serverBindFileManagerRuntime(...)` and saved-chat/history/gallery/welcome/download/message-search setup to `serverBindChatPersistenceModules(...)`.

In `server.R`, do not read identity values directly from `user_session` anymore. The expected contract is:

```r
runtime_ctx <- serverRuntimeContextInit(
  session = session,
  session_cache = session_cache,
  sso_state = sso_state,
  user_session = user_session
)

identity <- serverRuntimeRequireIdentity(
  runtime_ctx,
  required_values = c("user_config_rv"),
  required_functions = c(
    "resolve_current_user_id",
    "current_user_id_provider",
    "get_first_name",
    "get_display_name"
  ),
  owner = "server.R identity"
)

user_config_rv <- identity$user_config_rv
resolve_current_user_id <- identity$resolve_current_user_id
current_user_id_provider <- identity$current_user_id_provider
current_user_first_name <- identity$get_first_name
current_user_display_name <- identity$get_display_name
```

Identity accessors must be safe outside reactive consumers. When reading `user_config_rv` inside helper accessors, use `shiny::isolate(...)` or another explicit Shiny-safe pattern. Do not introduce unqualified Shiny calls in init/helper files when a namespaced call is practical; prefer `shiny::reactiveVal`, `shiny::reactiveValues`, `shiny::observeEvent`, `shiny::req`, and `shiny::isolate`.

Keep `R/helpers_user_session_identity.R` pure. It should not create Shiny observers, call the database, read Keycloak state directly, or depend on module wiring. It is a small testable boundary for identity/config shaping, live user-id provider construction, and centralized identity-related `session$userData` compatibility access. If identity orchestration changes are needed, make them in `R/server_init_user_session.R`; if only config shaping, compatibility reads/writes, or user-data accessor behavior changes, keep them in the helper and update `tests/testthat/test-user-session-identity-contract.R`.

Never read `sso_state$authenticated` directly during initialization checks such as `is.null(sso_state$authenticated)`. In production SSO, that field is reactive and direct reads can crash the app with “Can't access reactive value outside of reactive consumer.” Watch it with `shiny::observeEvent(sso_state$authenticated, ...)` and read it only inside a reactive consumer/handler.

Post-auth refreshable modules should use the `ServerRuntimeContext` refreshable-module contract instead of ad hoc `observeEvent(sso_state$authenticated, ...)` blocks in `server.R`. The low-level combined helper remains `serverRuntimeAttachRefreshableModule(...)`. File Manager is still wired through `serverBindFileManagerRuntime(...)`, and chat-persistence-related modules are still wired through `serverBindChatPersistenceModules(...)`; however, `server.R` should reach both through `serverBindCoreInteractionRuntime(...)`, not by calling them directly.

File Manager auth readiness must be injected through a validated identity section, not raw context access. In `serverBindFileManagerRuntime(...)`, use `identity <- serverRuntimeRequireIdentity(...)` and pass `auth_ready_provider = identity$is_auth_ready`. Do not reintroduce direct File Manager checks against `session$userData$auth_initialized`; that couples persisted-file refresh to SSO timing and can bring back user-id `0` refresh regressions.

Protected by:

```text
tests/testthat/test-server-user-session-context.R
tests/testthat/test-user-session-identity-contract.R
tests/testthat/test-server-runtime-context.R
tests/testthat/test-server-runtime-context-accessors.R
tests/testthat/test-server-core-interaction-runtime.R
tests/testthat/test-session-user-data-store.R
tests/testthat/test-server-module-wiring-contract.R
tests/testthat/test-server-module-wiring-runtime-bindings.R
tests/testthat/test-server-module-wiring-chat-engine.R
tests/testthat/test-server-boundary-contract.R
tests/testthat/test-server-live-user-provider-contract.R
tests/testthat/test-server-chat-persistence-wiring-contract.R
tests/testthat/test-effective-user-id.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-production-contracts.R
tests/testthat/test-file-manager-module-policy-wiring.R
```

### ServerRuntimeContext contract

`R/server_runtime_context.R` is a small boot-time context boundary, not a broad application framework.

Current accepted identity boundary: keep `server.R` using `identity <- serverRuntimeRequireIdentity(...)` followed by the existing local aliases (`user_config_rv`, `resolve_current_user_id`, `current_user_id_provider`, `current_user_first_name`, and `current_user_display_name`). Do not introduce `serverRuntimeBuildIdentityPorts()` or an `identity_ports` wrapper unless a future refactor removes an equal or greater amount of complexity and keeps the maintainability ratchet at or above the current baseline.

The context now exposes typed section accessors: `serverRuntimeRequireIdentity(...)`, `serverRuntimeRequireState(...)`, and `serverRuntimeRequireCache(...)`. Prefer these accessors in server wiring code when a helper needs a validated context section. They should fail early on missing or malformed boot sections and keep orchestration code from depending on undocumented `runtime_ctx$...` shape.

Its purpose is to reduce loose boot-state leakage in `server.R` and fail early when required boot objects are missing or malformed.

It currently covers only:

- `session_cache`
- `user_session` / live current-user providers / identity display accessors / auth-readiness provider
- `forward_refs`
- `state_bundle`
- typed section accessors for identity, state, and cache contracts: `serverRuntimeRequireIdentity(...)`, `serverRuntimeRequireState(...)`, and `serverRuntimeRequireCache(...)`
- file runtime objects in `runtime_ctx$file`, including file preview/follow-up prelude handles and the File Manager module handle
- `chat_runtime`
- late-bound runtime function slots are intentionally kept in `R/server_runtime_function_slot.R` instead of this file, to avoid growing `R/server_runtime_context.R` into a broader service locator
- narrowly registered module return objects in `runtime_ctx$modules`
- SSO auth-ready callback registration through `serverRuntimeOnSsoAuthReady(...)`, registered-module refresh wiring through `serverRuntimeRefreshModuleOnSsoAuthReady(...)`, and the higher-level refreshable-module wiring helper `serverRuntimeAttachRefreshableModule(...)`

Do not expand it casually into a large service locator. Add to it only when a server boot object is already created in `server.R`, has a clear required-function contract, and is passed across multiple downstream modules. `runtime_ctx$modules` is not a general global registry; use it narrowly for module return objects that need a validated runtime contract, such as File Manager and Image Gallery post-auth refresh wiring. This file is also close to the function-count ratchet, so adding new public helpers here must be offset by removing or extracting comparable complexity; otherwise the 25-function threshold can regress. The accepted SSO auth-ready refresh hardening intentionally kept the immediate-ready guard inline inside `serverRuntimeOnSsoAuthReady(...)` instead of adding new top-level helper functions, preserving the maintainability ratchet baseline of score `100/100`, `0` 25+ function files, and maximum function count `24`.

The file subsystem now has a focused FileRuntime boundary under `runtime_ctx$file`. Use `serverRuntimeAttachFilePrelude(...)`, `serverRuntimeAttachFileManager(...)`, and `serverRuntimeRequireFileRuntime(...)` for file prelude and File Manager handles instead of passing those objects through ad hoc local variables or direct `session$userData` reads. This boundary is intentionally narrow: it is for file-preview/follow-up prelude objects and `file_manager_data`, not a general registry for every file-related helper.

When code needs to read a registered module from the context, prefer `serverRuntimeGetModule(...)` over direct `ctx$modules$...` access. This keeps missing-module and missing-function failures explicit and testable. In `server.R`, post-auth module refreshes should normally use `serverRuntimeRefreshModuleOnSsoAuthReady(...)` rather than custom callbacks that manually inspect `ctx$modules`.

`serverRuntimeOnSsoAuthReady(...)` has an important race-condition contract: in SSO mode, if `ctx$sso_state$authenticated` is already true and `identity$is_auth_ready()` is already true when the helper is called, the callback must run immediately and the helper should not register an unnecessary observer. This covers the case where authentication finishes before File Manager, Image Gallery, or another refreshable module attaches its post-auth refresh hook.

Expected attach sequence in `server.R`:

```r
runtime_ctx <- serverRuntimeContextInit(...)

identity <- serverRuntimeRequireIdentity(...)

user_config_rv <- identity$user_config_rv
resolve_current_user_id <- identity$resolve_current_user_id
current_user_id_provider <- identity$current_user_id_provider
current_user_first_name <- identity$get_first_name
current_user_display_name <- identity$get_display_name

settings_bundle <- serverBindSettingsAndRefs(
  ...,
  runtime_ctx = runtime_ctx,
  ...
)

runtime_ctx <- settings_bundle$runtime_ctx

file_prelude_modules <- serverBindFilePreludeModules(
  session = session,
  runtime_ctx = runtime_ctx
)

runtime_ctx <- file_prelude_modules$runtime_ctx

file_runtime <- serverRuntimeRequireFileRuntime(
  runtime_ctx,
  require_prelude = TRUE,
  require_manager = FALSE
)

runtime_ctx <- serverRuntimeAttachState(runtime_ctx, ...)

state <- serverRuntimeRequireState(...)

core_interaction <- serverBindCoreInteractionRuntime(
  ...,
  runtime_ctx = runtime_ctx,
  media_modules = media_modules,
  user_config_provider = function(default = NULL) {
    runtime_ctx$identity$get_user_config(default = default)
  },
  user_first_name_fn = function(default = "") {
    current_user_first_name(default = default)
  }
)

runtime_ctx <- core_interaction$runtime_ctx
saved_chats_data <- core_interaction$saved_chats_data
file_manager_data <- core_interaction$file_manager_data
filePreview <- core_interaction$filePreview

chat_engine <- serverBindChatEngineRuntime(
  ...,
  runtime_ctx = runtime_ctx,
  saved_chats_data = saved_chats_data,
  send_message_fns = send_message_fns,
  send_message_proxy = send_message
)

runtime_ctx <- chat_engine$runtime_ctx
```

For File Manager and chat-persistence-related modules, `server.R` should not call `serverBindFileManagerRuntime(...)` or `serverBindChatPersistenceModules(...)` directly. It should delegate to `serverBindCoreInteractionRuntime(...)`. That helper owns the core observer/File Manager/chat-persistence orchestration and then delegates to the narrower wiring helpers in `R/server_module_wiring.R`.

Keep the compatibility exports intact unless a later refactor explicitly removes them. `serverBindFileManagerRuntime(...)` still registers File Manager in `runtime_ctx$modules$file_manager` and exposes `session$userData$file_manager_data` for older downstream code, while `runtime_ctx$file$file_manager_data` is the preferred boundary for new server wiring.

Use `serverRuntimeAttachRefreshableModule(...)` directly only inside runtime/wiring helper layers or for a genuinely new refreshable module pattern that does not fit an existing wiring helper.

Do not re-expand the saved chats, history, image gallery, welcome handlers, download outputs, or message search wiring back into `server.R`; keep that cluster behind `serverBindChatPersistenceModules(...)`.

Use the lower-level `serverRuntimeAttachModule(...)`, `serverRuntimeRefreshModuleOnSsoAuthReady(...)`, and `serverRuntimeExposeSessionData(...)` helpers only when the combined helper does not fit the case. Do not re-expand the File Manager or Image Gallery wiring back into separate attach/refresh/expose blocks in `server.R`.

Legacy `session$userData` exports should also be explicit. If a refreshable module still requires a compatibility value such as `file_manager_data`, prefer `expose_session_key = "file_manager_data"` in `serverRuntimeAttachRefreshableModule(...)`. For non-refreshable cases, expose compatibility values through `serverRuntimeExposeSessionData(...)` instead of adding loose `session$userData$... <- ...` assignments in `server.R`.

Keep the validated identity section from `serverRuntimeRequireIdentity(...)` as the single early boot identity boundary in `server.R`. Do not mix direct `user_session$...` reads, raw `runtime_ctx$identity` assumptions, or direct identity-related `session$userData$...` reads back into `server.R`.

Send-message wiring should use cache functions from the context:

### Session userData list-store contract

Session-local list-shaped stores under `session$userData` are centralized through a small SessionRuntimeStore facade in `R/utils_session_cleanup.R`.

The low-level list helpers still own safe list access:

```r
session_user_data_get_list(...)
session_user_data_set_list(...)
session_user_data_put_list_item(...)
session_user_data_remove_list_item(...)
session_user_data_reset_lists(...)
```

Use the SessionRuntimeStore facade for list stores such as:

* `current_session_files`
* `file_summaries`
* `chart_store`
* `mcp_registry_snapshot`

Do not add new loose assignments in `server.R` such as:

```r
session$userData$current_session_files <- list()
session$userData$file_summaries <- list()
session$userData$chart_store <- list()
session$userData$mcp_registry_snapshot <- list()
```

The expected initialization boundary is `R/server_init_session_state.R`, which prepares shared stores through `session_runtime_store_reset(session)`.

MCP registry snapshot synchronization in `R/server_session_cache.R` should flow through `session_runtime_store_snapshot_mcp(session, files_snapshot)`.

The file upload/summary pipeline, file-click observers, and new-chat cleanup should use `session_runtime_store_*` helpers instead of assuming another module already created the list.

This prevents hidden source-order and state-orchestration coupling around file context, MCP Excel visibility, summaries, and chart storage.

Protected by:

```text
tests/testthat/test-session-user-data-store.R
tests/testthat/test-source-manifest-contract.R
```

```r
cache <- serverRuntimeRequireCache(...)

cache_mcp_file_locally_fn = cache$cache_mcp_file_locally
update_mcp_registry_snapshot_fn = cache$update_mcp_registry_snapshot
```

Do not reintroduce loose early aliases such as:

```r
cache_mcp_file_locally <- session_cache$cache_mcp_file_locally
update_mcp_registry_snapshot <- session_cache$update_mcp_registry_snapshot
user_config_rv <- user_session$user_config_rv
resolve_current_user_id <- user_session$resolve_current_user_id
current_user_id_provider <- user_session$current_user_id_provider
current_user_first_name <- session$userData$user_first_name
current_user_display_name <- session$userData$user_config$name
session$userData$auth_initialized <- FALSE
session$userData$sso_active <- TRUE
session$userData$user_config
session$userData$user_first_name
session$userData$auth_source
session$userData$file_manager_data <- file_manager_data
auth_ready <- session$userData$auth_initialized
auth_ready_provider = runtime_ctx$identity$is_auth_ready
cache <- runtime_ctx$cache
state <- runtime_ctx$state
identity <- runtime_ctx$identity
```

* Do not replace the accepted `identity <- serverRuntimeRequireIdentity(...)` pattern with `identity_ports <- serverRuntimeBuildIdentityPorts(...)`; the current tests intentionally protect the existing runtime-context identity contract.

The context contract is protected by:

```text
tests/testthat/test-server-runtime-context.R
tests/testthat/test-server-runtime-context-accessors.R
tests/testthat/test-user-session-identity-contract.R
tests/testthat/test-server-boundary-contract.R
tests/testthat/test-server-live-user-provider-contract.R
tests/testthat/test-server-chat-persistence-wiring-contract.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-production-contracts.R
tests/testthat/test-file-manager-module-policy-wiring.R
```



### Core interaction runtime contract

`R/server_core_interaction_runtime.R` is the focused boundary for the middle part of `server.R` that used to be heavily order-dependent. It owns the core interaction setup sequence after session state exists and before the chat engine is bound.

It currently wires:

- chat export,
- quick actions,
- settings observers,
- session timeout,
- File Manager runtime through `serverBindFileManagerRuntime(...)`,
- chat UI observers,
- navigation observers,
- startup observers,
- startup screen observers,
- AI Expert handlers,
- storage observers,
- file observers,
- file-click observers,
- chat persistence through `serverBindChatPersistenceModules(...)`.

Do not move those calls back into `server.R`. `server.R` should call `serverBindCoreInteractionRuntime(...)`, unpack only the returned handles it needs, and then continue to `serverBindChatEngineRuntime(...)`.

This boundary is protected by:

```text
tests/testthat/test-server-core-interaction-runtime.R
tests/testthat/test-production-contracts.R
tests/testthat/test-server-live-user-provider-contract.R
tests/testthat/test-server-chat-persistence-wiring-contract.R
tests/testthat/test-file-manager-module-policy-wiring.R
```

### Server module wiring contract

`R/server_module_wiring.R` is a narrow wiring boundary for medium-level server module setup. It is not a new framework and should not become a general service locator.

It currently owns these helper entry points:

```r
serverBindServiceModules(...)
serverBindSettingsAndRefs(...)
serverBindMediaModules(...)
serverBindFilePreludeModules(...)
serverBindFileManagerRuntime(...)
serverBindImageGalleryRuntime(...)
serverBindChatPersistenceModules(...)
serverBindChatEngineRuntime(...)
```

Responsibilities:

* `serverBindServiceModules(...)`: binds performance stats, health, and support modules while preserving the live `current_user_id_provider`.
* `serverBindSettingsAndRefs(...)`: binds settings, forward references, Bilge Yolaç startup wiring, visual settings sync, chat output headers, and `load_chat_in_progress`.
* `serverBindMediaModules(...)`: binds feedback, AI processing, TTS, TTS visualizer, music handlers, AI Expert, and STT.
* `serverBindFilePreludeModules(...)`: binds file preview, fallback follow-up tools, follow-up module tools, DOCX preview JavaScript, and optionally attaches these prelude handles to `runtime_ctx$file` when a runtime context is supplied.
* `serverBindFileManagerRuntime(...)`: binds `fileManagerServer(...)`, injects the live user-id provider and the auth-readiness provider from `serverRuntimeRequireIdentity(...)`, registers the module through `ServerRuntimeContext`, attaches `file_manager_data` to the focused FileRuntime boundary, wires one-time SSO-ready persisted-file refresh, and preserves the explicit `session$userData$file_manager_data` compatibility export.
* `serverBindImageGalleryRuntime(...)`: binds `imageGalleryServer(...)` with the live user-id provider and registers the gallery refresh function through `ServerRuntimeContext`.
* `serverBindChatPersistenceModules(...)`: binds saved chats, saved-chat observers, chat content search, image gallery runtime and observers, welcome handlers, download outputs, history, and message search while preserving the live `current_user_id_provider`, explicit user-config provider, and explicit user-first-name provider.
* `serverBindChatEngineRuntime(...)`: binds chat runtime, LLM response handlers, chat input observers, miscellaneous chat/UI observers, chat actions, TTS handlers, and `sendMessageInit(...)`; it also assigns the final `send_message_fns$send_message` implementation and uses `serverRuntimeCreateFunctionSlot(...)` to avoid fragile TTS placeholder reassignment in `server.R`. It should read identity, state, and cache through `serverRuntimeRequireIdentity(...)`, `serverRuntimeRequireState(...)`, and `serverRuntimeRequireCache(...)` rather than assuming raw `runtime_ctx$...` shape.

Do not move these direct calls back into `server.R`:

```r
performanceStatsServer(...)
healthServer(...)
destekServer(...)
settingsInit(...)
serverInitForwardRefs(...)
claudeCodeServer(...)
visualSettingsSyncInit(...)
chatOutputsInit(...)
feedbackServer(...)
aiProcessingServer(...)
ttsProcessingServer(...)
ttsVisualizerServer(...)
musicHandlersInit(...)
aiExpertServer(...)
sttServer(...)
filePreviewServer(...)
create_followup_suggestions_tool(...)
followupSuggestionsServer(...)
init_docx_preview_js(...)
fileManagerServer(...)
imageGalleryServer(...)
savedChatsServer(...)
savedChatsObserversInit(...)
chatSearchInit(...)
imageGalleryObserversInit(...)
welcomeHandlersInit(...)
downloadOutputsInit(...)
historyServer(...)
messageSearchInit(...)
serverInitChatRuntime(...)
llmResponseHandlersInit(...)
chatInputObserversInit(...)
miscObserversInit(...)
chatActionsInit(...)
ttsHandlersInit(...)
sendMessageInit(...)
```

`server.R` should delegate to high-level boundaries and then unpack only the returned handles it needs. For the core observer/File Manager/chat-persistence sequence, the high-level boundary is `serverBindCoreInteractionRuntime(...)`; for chat engine wiring, it remains `serverBindChatEngineRuntime(...)`. The helper must preserve existing module IDs, current initialization order, and user/provider behavior. In particular, user-scoped service bindings must keep using the live provider rather than a startup user-id snapshot.

For chat persistence, `server.R` should not call `serverBindChatPersistenceModules(...)` directly. `serverBindCoreInteractionRuntime(...)` calls it and returns `runtime_ctx` plus `saved_chats_data` to `server.R`.

Do not re-expand the chat runtime, LLM handler, TTS handler, chat action, miscellaneous observer, or send-message wiring back into `server.R`; keep that cluster behind `serverBindChatEngineRuntime(...)`.

`R/server_runtime_function_slot.R` must stay sourced after `R/server_runtime_context.R` and before `R/server_module_wiring.R`, because it uses the runtime stop helper and is consumed by chat engine wiring.

For file-related wiring, prefer `serverRuntimeRequireFileRuntime(...)` after the relevant boundary has attached file prelude or File Manager objects. In `server.R`, File Manager attachment should now arrive through `serverBindCoreInteractionRuntime(...)`. Do not reintroduce direct `filePreview <- ...`, `followup_tools <- ...`, or `file_manager_data <- ...` propagation patterns when the value is already available through `runtime_ctx$file`.

Protected by:

```text
tests/testthat/test-server-module-wiring-contract.R
tests/testthat/test-server-module-wiring-runtime-bindings.R
tests/testthat/test-server-module-wiring-chat-engine.R
tests/testthat/test-server-core-interaction-runtime.R
tests/testthat/test-production-contracts.R
tests/testthat/test-server-live-user-provider-contract.R
tests/testthat/test-server-chat-persistence-wiring-contract.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-server-boundary-contract.R
```

### Database helper modularization contract
The database layer is now intentionally split into smaller responsibility-focused helpers. Preserve this source order:

```r
safe_source("R/helpers_db_connection.R", encoding = "UTF-8")
safe_source("R/helpers_db_validation.R", encoding = "UTF-8")
safe_source("R/helpers_chat_message_formatting.R", encoding = "UTF-8")
safe_source("R/helpers_db_chat_readers.R", encoding = "UTF-8")
safe_source("R/helpers_db_chat_mutations.R", encoding = "UTF-8")
safe_source("R/helpers_database.R", encoding = "UTF-8")
```

Responsibilities:

* `R/helpers_db_connection.R`: DB connection, release, health probe, worker-side DB connection, and DB parameter encoding normalization.
* `R/helpers_db_validation.R`: validation helpers such as `validate_username()`, `validate_chat_title()`, and `validate_message_content()`.
* `R/helpers_chat_message_formatting.R`: conversion of DB message rows into app message objects, including generated-image HTML, ChartLab saved-chat placeholder regeneration, markdown fallback, timestamps, and `ReasoningContent` propagation.
* `R/helpers_db_chat_readers.R`: chat list loading, chat message hydration, reasoning-column fallback SELECTs, batch chat hydration, and lightweight history row reads. Chat list reads must preserve latest-activity ordering using message timestamps when available.
* `R/helpers_db_chat_mutations.R`: chat/message write-side mutations, including chat creation, message save/update, reasoning-content update, title update, delete/clear chat helpers, worker-safe assistant response persistence, and `sanitize_input()` compatibility.
* `R/helpers_database.R`: user creation/update, SSO field update, feedback operations, usage logging, and remaining DB orchestration.

MessageOrder race protection in `save_message_to_db()` and `worker_save_assistant_response()` must keep the `UPDLOCK/HOLDLOCK` query contract.

Do not move connection, validation, message-formatting, chat-reader, or chat/message mutation functions back into `R/helpers_database.R`. The split is protected by `test-db-refactor-contract.R`, `test-chat-message-formatting-refactor-contract.R`, `test-source-manifest-contract.R`, and `test-maintainability-ratchet.R`.

When updating `tests/testthat/helper_bootstrap.R`, keep its DB source order aligned with production `global.R`. Tests must load the extracted DB helper files before `helpers_database.R`.

### ChartLab rendering and saved-chat hydration contract

ChartLab rendering is intentionally split between pure chart-spec helpers and Shiny output wiring.

Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/helpers_mcp_chart_tools.R",       encoding = "UTF-8")
safe_source("R/helpers_mcp_analyze_visualize.R", encoding = "UTF-8")
safe_source("R/helpers_chartlab_spec.R",         encoding = "UTF-8")
safe_source("R/helpers_chartlab.R",              encoding = "UTF-8")
```

Responsibilities:

* `R/helpers_chartlab_spec.R`: pure ChartLab helpers for chart type normalization, mapping value normalization, missing/invalid axis guessing, and shared aggregation behavior.
* `R/helpers_chartlab.R`: parsing `chartlab ...` message blocks, producing Shiny chart output placeholders, and wiring those placeholders through `wire_chart_output(...)`.
* `R/helpers_chat_message_formatting.R`: when DB messages are hydrated, ChartLab content must be converted back into the same Shiny output placeholder shape used by live messages.
* `chat_rebind_all_charts(...)`: after saved-chat UI is inserted, chart outputs must be rebound after Shiny flush via `session$onFlushed(..., once = TRUE)` and loop variables must be captured with `local(...)`.

Do not reintroduce a separate static JS-only rendering path as the primary saved-chat ChartLab recovery mechanism. Saved and browser-refreshed chats should use the same server-side Shiny output identity contract as live ChartLab messages.

Do not move chart type aliasing, mapping guessing, or aggregation helpers back into `R/helpers_chartlab.R`.

Protected by:

```text
tests/testthat/test-chartlab-spec-refactor-contract.R
tests/testthat/test-chat-message-formatting-refactor-contract.R
tests/testthat/test-mcp-chart-tools-refactor-contract.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-maintainability-ratchet.R
```

### File Store registry/index modularization contract

The file-store layer is split so that path/root initialization stays separate from upload registry mutation and lookup behavior. Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/config_file_store.R",                encoding = "UTF-8")
safe_source("R/config_file_store_index_mutation.R", encoding = "UTF-8")
safe_source("R/config_file_store_registry.R",       encoding = "UTF-8")
```

Responsibilities:

* `R/config_file_store.R`: file-store root paths, low-level UTF-8 index load/save helpers, environment validation, memory management, and scheduler-related configuration.
* `R/config_file_store_index_mutation.R`: index write/mutation guard, upload registration, display-name repair, storage-name recovery, public `global_register_file()` wrapper, and index removal.
* `R/config_file_store_registry.R`: uploaded-file resolution, user upload directory resolution, display-name lookup, user file listing, stale index pruning, and filesystem fallback listing.

Do not move `mergen_register_uploaded_file()`, `global_register_file()`, `resolve_uploaded_file()`, `mergen_user_upload_dir()`, `mergen_resolve_display_name()`, `recover_display_name_from_storage_name()`, `mergen_list_user_files()`, or `mergen_remove_from_index()` back into `R/config_file_store.R`.

The split is protected by:

* `tests/testthat/test-config-file-store-registry-refactor-contract.R`
* `tests/testthat/test-source-manifest-contract.R`
* `tests/testthat/test-maintainability-ratchet.R`

The index mutation path must keep a guard around read-modify-write operations so delayed file refresh or stale prune operations cannot overwrite a newer upload index entry.

### Bilge Yolaç run lifecycle and stop-finalization contract

Bilge Yolaç command execution now has a focused run-lifecycle boundary in `R/helpers_claude_code_run_lifecycle.R`.

Bilge Yolaç runtime workdir mirroring has a separate helper boundary in `R/helpers_claude_code_runtime_workdir.R`. This file owns user workspace creation and the Windows/UNC/Unicode workdir mirroring helpers: `get_user_workspace()`, `is_problematic_windows_workdir()`, `mirror_directory_to_local_workspace()`, `prepare_claude_runtime_workdir()`, and `sync_claude_runtime_workdir_back()`. Keep it sourced after `R/helpers_claude_code_process.R` and before `R/helpers_claude_code.R`.

Do not restore the old shared `active_dir` runtime folder pattern. Mirrored runtime workdirs must be per run, using the active `run_request_id` as the runtime token when `R/module_claude_code.R` calls `prepare_claude_runtime_workdir(...)`. This prevents rapid sequential or overlapping Bilge Yolaç runs for the same user from deleting each other’s mirrored workdir while snapshot comparison, generated-download collection, process polling, or sync-back is still using it.


### Bilge Yolaç workdir scan and generated-download contract

Bilge Yolaç workdir scanning is intentionally split from generated-download staging.

Responsibilities:

- `R/helpers_claude_code_workdir_scan.R` owns prompt intent detection for binary document creation/read flows, canonical file path normalization, duplicate path removal, workdir snapshot creation, snapshot diffing, and the short generated-file stability guard `wait_for_stable_claude_code_file_paths(...)`.
- `R/helpers_claude_code_workdir_snapshot.R` owns Turkish text encoding normalization and generated-download collection/staging orchestration through `collect_claude_code_workdir_changes_downloads(...)`.

Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/helpers_claude_code_downloads.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_workdir_scan.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_workdir_snapshot.R", encoding = "UTF-8")
```

Do not move scan/diff/path helpers back into `R/helpers_claude_code_workdir_snapshot.R`. That file should remain focused on text encoding normalization and generated-download staging.

`collect_claude_code_workdir_changes_downloads(...)` must keep calling `wait_for_stable_claude_code_file_paths(...)` before text normalization or staging. This is a Windows VM race-condition guard: Claude Code or child processes may have just produced a file, and size/mtime can still change briefly after the process appears complete. The guard reduces partial copy and premature `.txt` normalization risk while preserving best-effort generated-file collection.

Protected by:

```text
tests/testthat/test-claude-code-workdir-scan-contract.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-maintainability-ratchet.R
```

Responsibilities:

- active run request-id generation,
- active/stale run checks,
- stale async/promise callback protection,
- document-summary async result finalization guards,
- safe directory refresh after async completion,
- compatibility wrappers for request-id-aware finalization.

`R/module_claude_code.R` should remain focused on Shiny orchestration, command dispatch, process startup, and polling. Do not move the extracted async document-summary promise callback logic back into `R/module_claude_code.R`.

Stop handling is intentionally finalized directly inside the `input$stop_command` observer. When the user presses `Durdur`, the process may be killed and `active_process` may no longer be available to the polling observer. Therefore, the stop observer must not rely on the poll observer to reach the `env$durduruldu` branch. It must send the stream-end/finalization path itself so that the second counter, thinking animation, stop button, and disabled `Çalıştır` button are reset immediately.

Keep this behavior intact:

- `input$stop_command` should mark the environment as stopped when available.
- It may kill the active process.
- It should not manually clear all runtime state with ad hoc assignments.
- It should call `finalize_streaming("Durduruldu", ...)` with the active request id.
- `finalize_streaming(...)` remains the single state/UI cleanup boundary for run button, stop button, thinking overlay, status text, `rv$is_running`, `rv$active_process`, `rv$poll_state`, `rv$stream_env`, and `rv$active_request_id`.

Protected by:

```text
tests/testthat/test-claude-code-run-lifecycle-contract.R
tests/testthat/test-claude-code-runtime-workdir-contract.R
tests/testthat/test-claude-code-workdir-scan-contract.R
tests/testthat/test-claude-code-stream-finalize-contract.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-maintainability-ratchet.R
```

### Bilge Yolaç document extractor modularization contract

The Bilge Yolaç document-processing layer now has a focused extractor split. Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/helpers_claude_code_document_extractors.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_documents.R", encoding = "UTF-8")
```

Responsibilities:

* `R/helpers_claude_code_document_extractors.R`: binary-document extension policy, cache-name sanitization, text truncation, binary document discovery, temporary document-support directory creation, PDF/Excel/DOCX text extraction, supported-document dispatch, and office reader template path resolution.
* `R/helpers_claude_code_documents.R`: document manifest generation, inline payload construction, document prompt construction, document context preparation, summary detail-level detection, summary messages, and summary file output.

Do not move extractor helpers back into `R/helpers_claude_code_documents.R`. Keep the fallback source guard in `helpers_claude_code_documents.R` so the file can still be sourced directly in isolated tests/debug sessions. The split is protected by `test-claude-code-document-extractors-refactor-contract.R` and `test-claude-code-document-extractors-maintainability-contract.R`.

For maintainability refactors, prefer extracting one clear responsibility at a time and preserving public function names. After each extraction, update `global.R`, `tests/testthat/helper_bootstrap.R`, and add a small contract test that prevents the old monolithic responsibility from silently returning.



### Project/Resource Analysis security-summary helper contract

Project/Resource Analysis keeps RLS, identity-readiness, and statistical-summary helper logic outside the main Shiny module.

Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/helpers_pk_analysis_core.R",      encoding = "UTF-8")
safe_source("R/helpers_pk_analysis_security_summary.R", encoding = "UTF-8")
safe_source("R/helpers_pk_analysis_filters.R",   encoding = "UTF-8")
safe_source("R/module_proje_kaynak_analizi.R", encoding = "UTF-8")
```

Responsibilities:

R/helpers_pk_analysis_core.R: low-side-effect core helpers such as column summaries, date conversion, SQL Server identifier normalization, UTF-8 dataframe normalization, and Unicode SQL execution.

R/helpers_pk_analysis_security_summary.R: resolve_pk_analysis_username(), get_user_rls_info(), apply_rls_to_data(), and generate_statistical_summary().

R/helpers_pk_analysis_filters.R: AI-driven filter extraction and smart dataframe filtering.

R/module_proje_kaynak_analizi.R: request orchestration, query selection, SQL execution flow, filtering flow, LLM handoff, and stop-check handling.


Do not move the RLS helpers, SSO readiness resolver, or statistical-summary generator back into R/module_proje_kaynak_analizi.R.

resolve_pk_analysis_username() is a production safety boundary. In Windows VM SSO mode, Project/Resource Analysis must not proceed to RLS/DB lookup with username "Unknown" while session$userData$auth_initialized is still false. If identity is not ready, the analysis path should return the existing user-facing "identity/authentication is preparing" message instead of opening a DB connection.

The public helper names must remain stable unless compatibility wrappers are preserved.

Protected by:

tests/testthat/test-pk-analysis-security-summary-contract.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-maintainability-ratchet.R

### Send-message request lifecycle contract

`R/helpers_send_message_request_lifecycle.R` owns the focused helper boundary for `sendMessageInit(...)` request lifecycle behavior. Keep it sourced before `R/helpers_send_message_core.R`, `R/server_handler_true_streaming.R`, and `R/server_send_message.R`.

Responsibilities:

- request id generation through `mergen_new_send_message_request_id()`,
- current/stale/stopped request-state checks through `mergen_send_message_request_state(...)`,
- prompt snapshotting before routing,
- deferred chat creation decisions and chat preparation,
- welcome-screen cleanup for message send,
- thinking-panel planning and wrapper insertion,
- true-streaming deferred persistence guard through `mergen_should_run_deferred_stream_persist(...)`.

`R/server_send_message.R` should remain focused on orchestration, routing, mode dispatch, and LLM handoff. Do not move the extracted request lifecycle, prompt snapshot, welcome cleanup, thinking panel, or deferred chat preparation blocks back into `R/server_send_message.R`.

`R/server_handler_true_streaming.R` must use `mergen_new_send_message_request_id()` for request ids. Any delayed `later::later(...)` callback that can create or persist a chat for an active stream must check `mergen_should_run_deferred_stream_persist(active_request_id, stream_env$req_id, stream_env)` before calling `ensure_chat_ready()`. This prevents stale true-streaming callbacks from mutating `values$current_chat_id` after a stop, finalized stream, or newer request.

Protected by:

```text
tests/testthat/test-send-message-request-lifecycle-contract.R
tests/testthat/test-send-message-maintainability-ratchet.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-maintainability-ratchet.R
```

### LLM SSE stream I/O contract

The true-streaming LLM layer keeps the stream-file JSONL protocol separate from SSE parsing and worker orchestration. Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/helpers_llm_tool_formatters.R",      encoding = "UTF-8")
safe_source("R/helpers_llm_response_postprocess.R", encoding = "UTF-8")
safe_source("R/helpers_llm_api.R",                  encoding = "UTF-8")
safe_source("R/helpers_llm_stream_io.R",            encoding = "UTF-8")
safe_source("R/helpers_llm_sse.R",                  encoding = "UTF-8")
safe_source("R/helpers_llm_worker_payload.R",       encoding = "UTF-8")
safe_source("R/helpers_llm_worker.R",               encoding = "UTF-8")
```

Responsibilities:

R/helpers_llm_stream_io.R: stream JSONL delta/reasoning line writing, base64 payload decoding, and stop-file cancellation checks.

R/helpers_llm_sse.R: SSE event parsing, delta/reasoning extraction, HTTP stream handling, and worker orchestration.

### LLM worker payload helper contract

`R/helpers_llm_worker_payload.R` owns pure helper logic used by `R/helpers_llm_worker.R`:

- chat history to OpenAI-compatible message payload conversion,
- system-message merging,
- chart intent and chart type detection,
- disabled fallback chart passthrough,
- chart summary generation,
- automatic insight generation from tool results.

Keep this file free of Shiny session access, reactive reads, filesystem writes, HTTP calls, database calls, and mutable runtime state. It must remain safe to source in isolated tests and worker contexts.

`R/helpers_llm_worker.R` should keep orchestration responsibilities: API request construction, model request overrides, MCP tool schema handling, tool execution, second-pass logic, chart block collection, response post-processing, and error handling.

Keep the compatibility wrapper `merge_system_messages_to_front()` unless every old second-pass/recursive call path has been removed and tests prove that removal is safe. New code should call the canonical `llm_worker_merge_system_messages_to_front()` helper.

Protected by:

```text
tests/testthat/test-llm-worker-payload-refactor-contract.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-maintainability-ratchet.R
```


Do not move append_stream_delta_line(), append_stream_reasoning_line(), decode_stream_delta_payload(), or streaming_should_stop() back into R/helpers_llm_sse.R.

streaming_should_stop() must treat only a real file as a stop flag. A directory, empty string, NULL, or NA must not abort a stream.

Protected by:

tests/testthat/test-llm-stream-io-contract.R
tests/testthat/test-streaming-should-stop.R
tests/testthat/test-sse-worker-export-contract.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-maintainability-ratchet.R

### Bilge Yolaç UI and model/config modularization contract

Bilge Yolaç is now split into smaller responsibility-focused files. Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/helpers_claude_code_user_guard.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_upload_folder.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_model_config.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_session_context.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_dir_ui.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_process.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_runtime_workdir.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_server_setup.R", encoding = "UTF-8")
```

For the module UI/server split, preserve this order around the Bilge Yolaç module files:

```r
safe_source("R/module_claude_code_plugins.R", encoding = "UTF-8")
safe_source("R/module_claude_code_ui.R", encoding = "UTF-8")
safe_source("R/module_claude_code_akis.R", encoding = "UTF-8")
safe_source("R/module_claude_code.R", encoding = "UTF-8")
```

Responsibilities:

* `R/module_claude_code_ui.R`: `claudeCodeUI()` and Bilge Yolaç page UI layout.
* `R/module_claude_code.R`: `claudeCodeServer()` and server/runtime logic for the Bilge Yolaç page.
* `R/helpers_claude_code_upload_folder.R`: Bilge Yolaç upload-folder resolution helpers, including relaxed directory checks, candidate folder scoring, explicit session file registry handling, and placeholder user-id rejection.
* `R/helpers_claude_code_model_config.R`: Claude CLI path resolution, `settings.json` reading, model-tier mapping, model capability helpers, thinking-model detection, binary-document prompt detection, and execution-model fallback decisions.
* `R/helpers_claude_code_user_guard.R`: owns the Bilge Yolaç auth/user readiness contract. It checks SSO readiness and resolves a positive live user id before user-scoped workspace, upload-folder, directory listing, or command execution paths continue.
* `R/helpers_claude_code_server_setup.R`: owns the Bilge Yolaç server setup/observer binding cluster, including CLI path probing, connection badge updates, character/theme/font sync, upload-folder navigation, local folder upload, model-change session reset, scenario buttons, directory refresh, clear-output handling, and thinking tick updates.
* `R/helpers_claude_code_session_context.R`: Bilge Yolaç active-character and user first-name reactive context helpers used by `R/module_claude_code.R`.
* `R/helpers_claude_code_process.R`: Node/CLI process path resolution, processx command construction, Windows `.cmd`/UNC handling, process output UTF-8 normalization, non-ASCII escaping, Claude Code JSON/JSONL output parsing, and safe CLI workdir selection.
* `R/helpers_claude_code.R`: Claude Code CLI execution orchestration, status checks, runtime command handling, workspace helpers, and remaining Claude Code runtime helpers.

Do not move the setup observer cluster back into `R/module_claude_code.R`. That file should keep the public `claudeCodeServer()`entry point and the main command/streaming runtime flow, while setup and user/workspace readiness behavior remains behind`cc_bind_server_setup(...)`and`cc_require_ready_user_id(...)`. User-scoped Bilge Yolaç actions must not proceed with unresolved `user_id = 0`, especially in SSO startup timing windows.

Naming note: `R/helpers_claude_code_upload_folder.R`intentionally keeps its existing string-returning`cc_normalize_positive_user_id()`helper for upload-folder compatibility.`R/helpers_claude_code_user_guard.R`must use`cc_normalize_ready_user_id()`for integer readiness checks. Do not reintroduce a second`cc_normalize_positive_user_id()` definition in the user-guard file, because source order would make the two helpers collide.

When adding future Bilge Yolaç behavior:
- add pure/testable helpers for user-id readiness or setup decisions instead of new ad hoc observer logic in `R/module_claude_code.R`;
- preserve the live user-id provider pattern instead of capturing a startup user id;
- keep stale directory refresh protection through `cc_create_dir_refresh_guard()` / `dir_refresh_guard$is_latest(...)`;
- update `test-source-manifest-contract.R` whenever a new helper file is introduced;
- keep `tests/testthat.R` strict with `stop_on_failure = TRUE` and `stop_on_warning = TRUE`.

Do not move `claudeCodeUI()` back into `R/module_claude_code.R`.
Do not move model/settings helper functions back into `R/helpers_claude_code.R`.

The split is protected by:

* `tests/testthat/test-claude-code-ui-refactor-contract.R`
* `tests/testthat/test-claude-code-model-config-refactor-contract.R`
* `tests/testthat/test-claude-code-process-refactor-contract.R`
* `tests/testthat/test-claude-code-user-guard-contract.R`
* `tests/testthat/test-claude-code-dir-ui-refactor-contract.R`
* `tests/testthat/test-claude-code-upload-folder-refactor-contract.R`
* `tests/testthat/test-claude-code-run-lifecycle-contract.R`
* `tests/testthat/test-claude-code-stream-finalize-contract.R`
* `tests/testthat/test-source-manifest-contract.R`
* `tests/testthat/test-maintainability-ratchet.R`

For future maintainability refactors, keep using the ratcheted approach: extract one coherent responsibility, preserve public function names, update `global.R`, add a focused contract test, run the full strict test suite, then tighten `test-maintainability-ratchet.R` only after `tests/scripts/maintainability_report.R` confirms the new baseline.

### Proje/Kaynak Analizi filter modularization contract

The Proje/Kaynak Analizi layer now has a focused filter-helper split. Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/helpers_pk_analysis_core.R",      encoding = "UTF-8")
safe_source("R/helpers_pk_analysis_filters.R",   encoding = "UTF-8")
safe_source("R/module_proje_kaynak_analizi.R",   encoding = "UTF-8")
```

Responsibilities:

* `R/helpers_pk_analysis_core.R`: pure PK analysis helpers such as column summaries, date conversion, UTF-8 normalization, SQL Unicode execution, and SQL Server identifier normalization.
* `R/helpers_pk_analysis_filters.R`: AI filter criteria extraction, stop-after-LLM guard, JSON filter parsing, smart dataframe filtering, and aggregation.
* `R/module_proje_kaynak_analizi.R`: Proje/Kaynak Analizi runtime orchestration, RLS, DB/query execution, module behavior, and fallback helper loading.

Do not move `extract_filter_criteria_from_prompt()` or `apply_smart_filters()` back into `R/module_proje_kaynak_analizi.R`. Preserve their public function names because `R/helpers_deep_analysis.R` calls them directly.

The split is protected by:

* `tests/testthat/test-pk-analysis-filters-refactor-contract.R`
* `tests/testthat/test-pk-analysis-core-refactor-contract.R`
* `tests/testthat/test-pk-analysis-maintainability-contract.R`

### File Manager modularization contract

The File Manager layer is intentionally split to keep the large runtime module from growing again. Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/helpers_file_manager_policy.R", encoding = "UTF-8")
safe_source("R/helpers_file_manager_context_policy.R", encoding = "UTF-8")
safe_source("R/helpers_file_manager_table.R", encoding = "UTF-8")
safe_source("R/helpers_file_manager_refresh_guard.R", encoding = "UTF-8")
safe_source("R/helpers_file_manager_session_registry.R", encoding = "UTF-8")
safe_source("R/helpers_file_manager_runtime.R", encoding = "UTF-8")
safe_source("R/helpers_file_manager_storage.R", encoding = "UTF-8")
safe_source("R/helpers_file_manager_state_runtime.R", encoding = "UTF-8")
safe_source("R/module_file_manager_ui.R", encoding = "UTF-8")
safe_source("R/module_file_manager.R", encoding = "UTF-8")
```

Responsibilities:

* `R/helpers_file_manager_policy.R`: pure File Manager policy/helpers such as upload-size normalization, upload-size byte conversion, summarization/normal allowed extension policy, attach-rule hint text, File Manager user-id normalization, file-extension icon HTML, and file timestamp formatting.
* `R/helpers_file_manager_context_policy.R`: pure File Manager model-context cleanup planning, including stale selection IDs, MCP Excel-only enforcement, and single-Excel selection planning.
* `R/helpers_file_manager_table.R`: pure File Manager table helpers such as empty table schema, action button HTML, model-context checkbox HTML, and single-row table construction. This file must not mutate Shiny reactive state.
* `R/helpers_file_manager_refresh_guard.R`: pure File Manager persisted-refresh request generation guard. This file owns the monotonically increasing request token used to prevent stale refreshes from applying older file state.
* `R/helpers_file_manager_session_registry.R`: pure-ish File Manager session file registry helpers. This file owns `session$userData$current_session_files` entry shape, registry initialization, register/unregister behavior, and registry path normalization.
* `R/helpers_file_manager_runtime.R`: File Manager server runtime helper factory. It preserves local helper names used by `fileManagerServer()` while keeping settings resolution, effective user-id resolution, debug logging, registry wrappers, parent attach/detach synchronization, and extension/toast helpers outside the server module body.
* `R/helpers_file_manager_storage.R`: File Manager persistent storage helper factory. It owns user upload folder resolution, MCP-base path checks, user-folder listing, and persisted upload index synchronization.
* `R/helpers_file_manager_state_runtime.R`: focused File Manager state/action helper factory and persisted refresh construction (`fm_create_file_action_helpers(...)`, `fm_create_refresh_from_user_folder(...)`) extracted from the module runtime body.
* `R/module_file_manager_ui.R`: public `fileManagerUI(id)` definition, File Manager UI layout, and browser-side upload-size guard.
* `R/module_file_manager.R`: public `fileManagerServer(...)` definition, server-side upload processing, attach/detach orchestration, deletion/clear operations, and parent-session synchronization while delegating File Manager state mutation and persisted file refresh construction to dedicated helpers. Small pure decisions should delegate to File Manager helper files instead of being reimplemented inline.

### File Manager state runtime extraction contract

The File Manager state mutation and persisted-folder refresh runtime are intentionally extracted into `R/helpers_file_manager_state_runtime.R`. Keep this file sourced after `R/helpers_file_manager_storage.R` and before `R/module_file_manager_ui.R` / `R/module_file_manager.R`.

Responsibilities:
- `R/module_file_manager.R`: Shiny module orchestration, observer wiring, UI event handling, and delegation to helper factories.
- `R/helpers_file_manager_state_runtime.R`: focused File Manager state/action helpers and persisted refresh construction, including `fm_create_file_action_helpers(...)` and `fm_create_refresh_from_user_folder(...)`.
- `R/helpers_file_manager_refresh_guard.R`: pure request-token guard that prevents stale persisted refreshes from overwriting newer File Manager state.
- `R/helpers_file_manager_table.R`: file table schema and row HTML construction.

Do not move `sync_file_to_context`, `append_uploaded_file_row`, `remove_file_by_name`, `process_uploaded_file`, or `fm_create_refresh_from_user_folder()` back into `R/module_file_manager.R`. New File Manager state mutation helpers should either belong in `R/helpers_file_manager_state_runtime.R` or in a narrower helper if a clearly separate responsibility emerges.

Bulk upload must not mutate persisted File Manager state before SSO/auth identity is ready. Keep the auth-readiness guard in the upload path and keep File Manager auth readiness injected through the validated identity provider rather than direct `session$userData$auth_initialized` checks.

File Manager storage policy tests now cover the user-specific upload directory and invalid-user persistence boundary. `fm_create_server_storage_helpers()` should keep deriving upload folders under the configured MCP base as `user_<id>`, while `ensure_persisted_upload_index()` must return without registering files for invalid user ids such as `0`, `unknown`, empty, or NULL. Do not weaken this guard to make refresh or upload flows appear successful.

Protected by:
```text
tests/testthat/test-file-manager-state-runtime-contract.R
tests/testthat/test-file-manager-module-policy-wiring.R
tests/testthat/test-file-manager-refresh-guard-contract.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-maintainability-ratchet.R
```

This extraction reduced `R/module_file_manager.R` below the 800-line threshold and raised the maintainability baseline to 70/100.

Do not move `fileManagerUI()` back into `R/module_file_manager.R`. Do not duplicate upload-size, allowed-extension, attach-rule text, user-id placeholder handling, file-extension icon HTML, file timestamp formatting, or session file registry path/entry decisions inside the module when the helper already owns that policy.

The persisted-file refresh path uses a request-generation guard from `fm_create_refresh_request_guard()` (`refresh_guard$next_id()` and `refresh_guard$is_latest(...)`) so stale refreshes cannot overwrite newer file state. Preserve that guard when editing `refresh_from_user_folder(...)`.

This split is protected by:

* `test-file-manager-policy-contract.R`
* `test-file-manager-context-policy-contract.R`
* `test-file-manager-table-contract.R`
* `test-file-manager-refresh-guard-contract.R`
* `test-file-manager-module-policy-wiring.R`
* `test-file-manager-state-runtime-contract.R`
* `test-file-manager-ui-refactor-contract.R`
* `test-file-manager-upload-limit-ui.R`
* `test-source-manifest-contract.R`
* `test-maintainability-ratchet.R`

### Settings Yapılandırma UI modularization contract

The Yapılandırma settings page is split so that the large UI layout does not grow inside the runtime server module. Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/module_settings_kisisel.R", encoding = "UTF-8")
safe_source("R/module_settings_yapilandirma_ui.R", encoding = "UTF-8")
safe_source("R/module_settings_yapilandirma.R", encoding = "UTF-8")
safe_source("R/module_settings.R", encoding = "UTF-8")
```

Responsibilities:

* `R/module_settings_yapilandirma_ui.R`: `settingsYapilandirmaUIImpl(id)` and the Yapılandırma page UI cards/layout only.
* `R/module_settings_yapilandirma.R`: public `settingsYapilandirmaUI(id)` wrapper, `settingsYapilandirmaServer(...)`, temporary settings state, save/reset triggers, runtime outputs, and observer logic.
* `R/module_settings.R`: central settings coordinator, localStorage restore, save/reset orchestration, and cross-module synchronization.

Do not move the large Yapılandırma UI card layout back into `R/module_settings_yapilandirma.R`. Do not move runtime observers, `reactiveVal(...)`, `moduleServer(...)`, or `session$sendCustomMessage(...)` into `R/module_settings_yapilandirma_ui.R`.

This split is protected by:

* `tests/testthat/test-settings-yapilandirma-ui-refactor-contract.R`
* `tests/testthat/test-source-manifest-contract.R`
* `tests/testthat/test-maintainability-ratchet.R`

### Admin Hata Analizi modularization contract

`R/module_admin_hata_analizi.R` has been reduced by extracting pure/query/UI helper responsibilities into `R/helpers_admin_hata_analizi.R`.

Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/helpers_admin_hata_analizi.R", encoding = "UTF-8")
safe_source("R/module_admin_hata_analizi.R",  encoding = "UTF-8")
```

Responsibilities:

* `R/helpers_admin_hata_analizi.R`: Admin Hata Analizi SQL query bundle, Turkish category/priority/status labels, category counting, tab UI router, and tab UI builders.
* `R/module_admin_hata_analizi.R`: public Shiny module API, refresh/reactive orchestration, chart/table rendering, attachment/status modal handling, and event logic.

Do not move the helper responsibilities back into `R/module_admin_hata_analizi.R`. Keep the public module names unchanged.

Protected by:

```text
tests/testthat/test-admin-hata-analizi-refactor-contract.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-maintainability-ratchet.R
```

Important: if isolated tests source `R/helpers_admin_hata_analizi.R` directly, keep test-only stubs local to the test file instead of sourcing broad runtime modules.

### Admin Yanıt Analizi modularization contract

Yanıt Geri Bildirimi Analizi sayfası, büyük admin modüllerinin kademeli küçültülmesi yaklaşımıyla ayrı yardımcı dosyaya bölünmüştür. Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/helpers_admin_yanit_analizi.R", encoding = "UTF-8")
safe_source("R/module_admin_yanit_analizi.R",  encoding = "UTF-8")
```

Responsibilities:

* `R/helpers_admin_yanit_analizi.R`: MB_Feedback odaklı sorgu paketi, yanıt geri bildirim etiket çözümleme mantığı ve Yanıt Analizi sekme UI helperları.
* `R/module_admin_yanit_analizi.R`: public `adminYanitAnaliziUI()` / `adminYanitAnaliziServer()` API'si, Shiny refresh/reactive orkestrasyonu, chart/table output render fonksiyonları ve modül wiring.

Do not move `admin_yanit_collect_data()`, `admin_yanit_tag_counts()`, `admin_yanit_overview_ui()`, `admin_yanit_model_ui()`, `admin_yanit_etiket_ui()` or `admin_yanit_zaman_ui()` back into `R/module_admin_yanit_analizi.R`.

This split is protected by:

* `tests/testthat/test-admin-yanit-analizi-refactor-contract.R`
* `tests/testthat/test-source-manifest-contract.R`
* `tests/testthat/test-maintainability-ratchet.R`

---

# 6) When the user asks for exact patches, be exact

---

# 7. Automated validation commands

Run from repo root:

```r
source("tests/scripts/maintainability_report.R", encoding = "UTF-8")
```

Focused validation for the current server runtime architecture boundary:

```r
testthat::test_file("tests/testthat/test-server-user-session-context.R")
testthat::test_file("tests/testthat/test-server-runtime-context.R")
testthat::test_file("tests/testthat/test-server-core-interaction-runtime.R")
testthat::test_file("tests/testthat/test-server-module-wiring-runtime-bindings.R")
testthat::test_file("tests/testthat/test-session-user-data-store.R")
testthat::test_file("tests/testthat/test-server-module-wiring-contract.R")
testthat::test_file("tests/testthat/test-server-live-user-provider-contract.R")
testthat::test_file("tests/testthat/test-source-manifest-contract.R")
testthat::test_file("tests/testthat/test-production-contracts.R")
```

Then run the full strict suite:

```r
source("tests/testthat.R", encoding = "UTF-8")
```

The user often wants:

- full replacement blocks,
- precise before/after snippets,
- exact file names,
- exact insertion locations,
- concrete testing instructions.

Do not answer vaguely.

### 7) Preserve existing UX wording
User-facing strings are mostly Turkish and intentionally stylized. Avoid rewriting labels unless required.

### 7A) Prefer canonical identity resolution helpers
When resolving effective user/session identity, prefer shared canonical helpers (for example `resolve_effective_user_id(...)`) instead of copy-pasted local resolver variants.

Avoid re-implementing local `resolve_current_user_id()` snippets unless there is a compelling, scoped reason. In this repo, SSO timing regressions often come from duplicated identity-resolution code paths drifting apart.

In SSO flows, do not pass the startup `current_user_id` snapshot into user-scoped modules. The startup value may temporarily be `0L`. Pass a live provider such as `current_user_id_provider` / `resolve_current_user_id()` so modules resolve the effective user at use time. `resolve_effective_user_id(...)` must treat placeholder/invalid session IDs such as `0`, `NA`, and non-numeric values as missing, then fall back to the live provider before returning `0L`. This protects saved chats, history, file manager, gallery, support, and performance flows from SSO user-ID drift.

User/session bootstrap is centralized in `R/server_init_user_session.R`. Do not move local/SSO identity setup logic back into `server.R`.

`server.R` should initialize `user_session` with `serverInitUserSession(...)`, then pass it into `serverRuntimeContextInit(...)`. Downstream aliases must come from `runtime_ctx$identity`, not directly from `user_session`.

Expected pattern:

```r
user_session <- serverInitUserSession(...)

runtime_ctx <- serverRuntimeContextInit(
  session = session,
  session_cache = session_cache,
  sso_state = sso_state,
  user_session = user_session
)

identity <- serverRuntimeRequireIdentity(
  runtime_ctx,
  required_values = c("user_config_rv"),
  required_functions = c(
    "resolve_current_user_id",
    "current_user_id_provider",
    "get_first_name",
    "get_display_name"
  ),
  owner = "server.R identity"
)

user_config_rv <- identity$user_config_rv
resolve_current_user_id <- identity$resolve_current_user_id
current_user_id_provider <- identity$current_user_id_provider
current_user_first_name <- identity$get_first_name
current_user_display_name <- identity$get_display_name
```

For auth-sensitive modules, pass `identity$is_auth_ready` as a provider rather than checking `session$userData$auth_initialized` directly.

Do not pass startup `current_user_id` snapshots to user-scoped modules. In SSO mode, the startup value may temporarily be `0L`; use the live provider exposed through `runtime_ctx$identity$current_user_id_provider`.

### 8) Async jobs visible in health metrics must use tracked wrapper
For application-monitored async flows, do not use raw `future_promise(...)` directly.

Use `tracked_future_promise(task_fn = function() { ... }, task_type = "...", session_token = session$token)` with a meaningful `task_type`.

Do not pass raw expression blocks as positional `expr`; `tracked_future_promise()` now expects `task_fn`.

### 8A) tracked_future_promise() is also a worker dependency wrapper

In this repository, `tracked_future_promise(...)` is not used only for tracking/metrics. It is also the standard entry point for safely transferring global functions and required packages used in `task_fn` to the worker side.

Practical result:
- In a new async flow, using raw `future_promise(...)` should be considered prohibited.
- `tracked_future_promise(...)` automatically derives dependencies inside `task_fn` when possible.
- In special flows, explicitly passing dependencies with `globals = list(...)` is still a correct approach.

In particular, the following errors are usually not a source-order issue, but a worker dependency transfer issue:
- `call_llm_worker function not found`
- `generate_image function not found`

For true SSE streaming, keep the worker prewarm/export contract aligned with the `tracked_future_promise(..., globals = list(...))` contract in `R/server_handler_true_streaming.R`. Reasoning deltas, stop-file checks, and model-specific request overrides require helpers such as `append_stream_reasoning_line`, `streaming_should_stop`, `apply_model_request_overrides`, and `merge_named_list_deep` to remain visible on the worker side.

These errors can be more visible especially under these conditions:
- `SSO_ENABLED=TRUE`
- Windows VM
- Running the entire `app.R` file with `Ctrl+Enter`
- Use of persistent cluster workers

### 8B) Source-time side effects must be guarded
Source-time background loops/timers must always use a once-only guard pattern.

Repository convention:
- periodic GC scheduling is started through a once-only guard (`start_gc_scheduler_once()` pattern),
- do not reintroduce unguarded source-time scheduling that can stack duplicate loops when files are sourced repeatedly in the same R session.

### Upload-size policy and client-side guard
File upload size enforcement is layered and must remain that way:

* browser/client-side guard in `R/module_file_manager_ui.R` rejects files above the configured limit before Shiny upload starts,
* `shiny.maxRequestSize` provides request-level protection,
* `validate_uploaded_file()` provides the final server-side trust boundary.

The default production policy is 25 MB per file. Do not remove the browser-side guard. The browser-side guard is implemented in `R/module_file_manager_ui.R`; keep it there unless the File Manager UI split is intentionally redesigned. Without it, large files may still make the Dosya Yönetimi page appear frozen because Shiny begins uploading immediately when a user selects or drops a file, before server-side validation can show a toast.

---

## Health Dashboard Architecture

The “Sistem Durumu” page is a modular, offline-compatible health dashboard for on-prem Windows VM deployments. Keep the public Shiny module API stable and backward compatible:

```r
healthUI(id)
healthServer(id, perf_tracker)
```

Do not break existing callers of these functions.

Implementation split (keep responsibilities scoped):
- `R/helpers_health_formatters.R`: status/severity normalization, secret-safe formatting, path-copy helpers, shared rendering helpers.
- `R/helpers_health_runtime_checks.R`: runtime, SSO, paket, işletim sistemi/süreç, worker ve Bilge Yolaç sağlık kontrolleri.
- `R/helpers_health_checks.R`: environment, storage, DB, LLM/service endpoint kontrolleri ve genel sağlık kontrol orkestrasyonu; Shiny UI coupling içermez.
- `R/module_health_overview.R`: overview tab helpers.
- `R/module_health_connectivity.R`: DB/LLM/TTS/STT/image connectivity helpers.
- `R/module_health_storage.R`: storage/path/index/log/disk helpers.
- `R/module_health_runtime.R`: worker/runtime/memory/session/package/OS/CPU-core helpers.
- `R/module_health_security.R`: SSO/env/secret-redaction/DB-schema-readiness helpers.
- `R/module_health_diagnostics.R`: diagnostics table/remediation helpers.
- `R/module_health.R`: stable coordinator module.
- `www/css/health_dashboard.css` and `www/js/health_dashboard.js`: local-only dashboard assets.

Health checks must remain safe, non-destructive, lightweight, and offline-compatible. They must not mutate production data and must not call public internet endpoints. Optional integrations should degrade to `not_configured` or `unknown` without unhandled errors.

Secrets must always be redacted: never print raw credentials, tokens, or API keys.

Path actions intentionally copy full paths to clipboard instead of attempting direct folder open; users then paste into Windows File Explorer and press Enter.

Health tooltips use CSS-only `data-health-tooltip`. Do **not** reintroduce Bootstrap tooltip initialization for health dashboard elements; it previously caused frozen tooltip artifacts during refresh/navigation.

Every new health check should return a structured result contract:

```r
id
label
status
severity
value
detail
duration_ms
checked_at
remediation
```

Focused health validation:

```r
source("tests/testthat.R", encoding = "UTF-8")

testthat::test_file("tests/testthat/test-health-check-formatters.R")
testthat::test_file("tests/testthat/test-health-check-paths.R")
testthat::test_file("tests/testthat/test-health-check-env-contract.R")
testthat::test_file("tests/testthat/test-health-check-runtime-contract.R")
```

---

### 9) If there is a bug fix, include a test when possible
Unit tests should be added when possible for helper and decision-logic changes. Previously observed regressions should not be left untested. Test additions should be aligned with repo style, small, and surgical. Especially for helper behaviors that previously caused regressions such as encoding/BOM and promise cleanup, test expectations should be resilient enough to account for event-loop timing and Windows VM differences.

For session-lifecycle helpers, keep testability in mind: repository tests may use fake Shiny-like session objects implemented either as `list` or as `environment`. Do not over-constrain helper inputs if the real contract is “has a usable `onSessionEnded` callback”.

On Windows VM, contract tests should prioritize stable behavioral invariants over rigid assumptions about serialized JSON shape, exact raw-text rendering, or platform-sensitive loader output. If the test targets a real repository contract, avoid locking to a single internal representation when equivalent forms are valid.

### 9A) Decomposing the MCP Excel path-resolution chain
- MCP context sorumlulukları `R/helpers_mcp_context.R` içinde tutulmalıdır. Bu dosya `helpers_mcp_tools` ortamını, MCP debug kapısını (`mcp_debug_enabled` / `mcp_debug_log`) ve scalar kullanıcı kimliği çözümlemeyi (`get_session_user_id`) sağlar.
- MCP bootstrap/fallback source sorumlulukları `R/helpers_mcp_bootstrap.R` içinde tutulmalıdır. Bu dosya worker/izole test bağlamlarında kritik MCP yardımcılarını `helpers_mcp_tools` ortamında hazırlar, destek dosyalarını çalışma dizininden bağımsız bulur ve bootstrap sözleşmesini doğrular.
- MCP tablo okuyucu sorumlulukları `R/helpers_mcp_table_readers.R` içinde tutulmalıdır. Bu dosya `helpers_mcp_tools$safe_read_excel_table`, `helpers_mcp_tools$safe_read_table_generic` ve `helpers_mcp_tools$create_md_table` tanımlarını sağlar.
- MCP dosya kayıt/çözümleme sorumlulukları `R/helpers_mcp_file_resolver.R` içinde tutulmalıdır. Bu dosya `helpers_mcp_tools$ensure_session_file_registry`, `helpers_mcp_tools$register_uploaded_file`, `helpers_mcp_tools$get_default_file_name`, `helpers_mcp_tools$auto_file_name` ve `helpers_mcp_tools$resolve_file_argument` tanımlarını sağlar.
- MCP dosya şeması, akıllı kolon eşleştirme, argüman normalizasyonu, grafik tipi normalizasyonu ve sonuç sütun adı güzelleştirme yardımcıları `R/helpers_mcp_schema_helpers.R` içinde tutulmalıdır. Bu dosya `helpers_mcp_tools$extract_mcp_file_schema`, `helpers_mcp_tools$find_matching_column`, `helpers_mcp_tools$find_columns_by_context`, `helpers_mcp_tools$normalize_args`, `helpers_mcp_tools$normalize_chart_type`, `helpers_mcp_tools$prettify_column_name` ve `helpers_mcp_tools$prettify_result_colnames` tanımlarını sağlar.
- MCP temel dosya özeti, kolon istatistiği, DuckDB varlık kontrolü ve yüklenen dosya üzerinde SQL çalıştırma araçları `R/helpers_mcp_basic_tools.R` içinde tutulmalıdır. Bu dosya `helpers_mcp_tools$safe_has_duckdb`, `helpers_mcp_tools$analyze_uploaded_file`, `helpers_mcp_tools$get_column_statistics` ve `helpers_mcp_tools$sql_query_uploaded_file` tanımlarını sağlar.
- MCP grafik veri hazırlama, akıllı eksen/kolon eşleştirme, çoklu seri dönüşümü ve ChartLab payload üretimi `R/helpers_mcp_chart_tools.R` dosyasında tutulmalıdır. `helpers_mcp_tools$prepare_chart_data` public adı korunmalı; bu fonksiyon tekrar `R/helpers_mcp_tools.R` içine taşınmamalıdır. Chart helper debug çıktıları raw `cat()` yerine `helpers_mcp_tools$mcp_debug_log(...)` üzerinden geçmelidir.
- MCP R-first filtrelenmiş analiz, gruplandırılmış istatistik ve analiz+grafik köprü aracı `R/helpers_mcp_analyze_visualize.R` dosyasında tutulmalıdır. `helpers_mcp_tools$analyze_and_visualize` public adı korunmalı; bu fonksiyon tekrar `R/helpers_mcp_tools.R` içine taşınmamalıdır. Smart-match debug çıktıları raw `cat()` yerine `helpers_mcp_tools$mcp_debug_log(...)` üzerinden geçmelidir.
- `global.R` içinde MCP kaynak sırası şu şekilde korunmalıdır: `R/helpers_mcp_context.R` → `R/helpers_mcp_bootstrap.R` → `R/helpers_mcp_tools.R` → `R/helpers_mcp_table_readers.R` → `R/helpers_mcp_file_resolver.R` → `R/helpers_mcp_schema_helpers.R` → `R/helpers_mcp_basic_tools.R` → `R/helpers_mcp_chart_tools.R` → `R/helpers_mcp_analyze_visualize.R`.
- `helpers_mcp_tools.R` doğrudan source edildiğinde de çalışabilmelidir. Bu nedenle `helpers_mcp_tools.R`, `R/helpers_mcp_bootstrap.R` dosyasını working-directory bağımsız fallback source köprüsüyle yükleyebilmelidir. MCP destek dosyalarının (`helpers_mcp_table_readers.R`, `helpers_mcp_file_resolver.R`, `helpers_mcp_schema_helpers.R`, `helpers_mcp_basic_tools.R`) izole test/debug/worker bağlamlarında bulunması ve sözleşme doğrulaması `R/helpers_mcp_bootstrap.R` sorumluluğudur. Bu köprü yalnızca repo kökünün `getwd()` olduğunu varsaymamalı; `repo_root_for_tests`, `MERGEN_REPO_ROOT`, `getwd()` ve üst dizin adaylarını güvenli biçimde denemelidir.
- Source-time geçici değişken temizliği warning üretmemelidir. Örneğin `.mcp_table_readers_path`, `.mcp_file_resolver_path`, `.mcp_schema_helpers_path` ve `.mcp_basic_tools_path` gibi değişkenler yalnızca `exists(..., inherits = FALSE)` kontrolünden sonra `rm()` edilmelidir. Bu temizlik sözleşmesi artık `R/helpers_mcp_bootstrap.R` içinde korunur. `tests/testthat.R` `stop_on_warning = TRUE` ile çalıştığı için source-time cleanup warning’leri suite’i kırar.
- MCP tablo okuyucu fonksiyon tanımları `R/helpers_mcp_table_readers.R` içinde kalmalı; ancak bu dosyanın tekil test/debug/app-boot bağlamlarında güvenli yüklenmesi `R/helpers_mcp_bootstrap.R` üzerinden yapılmalıdır. `helpers_mcp_tools.R` doğrudan source edildiğinde önce bootstrap dosyasını yükleyerek bu dolaylı sözleşmeyi korur. Bu sözleşme `test-mcp-bootstrap-refactor-contract.R` ve `test-mcp-table-readers-refactor-contract.R` ile korunmalıdır.
- `R/helpers_mcp_table_readers.R`, `helpers_mcp_tools$safe_read_excel_table`, `helpers_mcp_tools$safe_read_table_generic` ve `helpers_mcp_tools$create_md_table` fonksiyonlarının environment değerini `helpers_mcp_tools` olarak korumalıdır. Bu özellikle worker/MCP araç bağlamlarında `normalize_excel_path`, `resolve_readable_path` ve `path_exists_relaxed` gibi yardımcıların görünür kalması için gereklidir.
- Fonksiyon environment ataması kesinlikle `environment(get(...)) <- ...` biçiminde yapılmamalıdır. R bunu `get<-` replacement çağrısı gibi yorumlar ve app boot/test zincirini `"get<-" function not found` hatasıyla kırar. Önce fonksiyonu geçici değişkene alın, environment değerini değiştirin, sonra `assign(...)` ile geri yazın.
- `utils_excel_reader.R` içindeki global `safe_read_excel_table()` MCP ortamına kopyalanırsa environment değeri `helpers_mcp_tools` olarak yeniden bağlanmalıdır; aksi halde runtime’da `"normalize_excel_path" function not found` hatası tekrar oluşabilir.
- `helpers_mcp_tools$get_session_user_id()` SSO başlangıç placeholder değerlerini (`0`, `unknown`, `null`, `NA`, `NaN`) gerçek kullanıcı kimliği gibi kullanmamalıdır. MCP dosya çözümleme akışında global `current_user_id` fallback'i tekrar eklenmemelidir.
- `helpers_mcp_file_resolver.R` içindeki cross-bucket index lookup üretimde varsayılan kapalı kalmalıdır. Aynı dosya adı başka kullanıcı bucket'ında bulunuyorsa bu yol yalnızca geçiş/migrasyon amaçlı açık opt-in ile çalışmalıdır: `options(mergen.mcp.allow_cross_bucket_lookup = TRUE)` veya `MERGEN_MCP_ALLOW_CROSS_BUCKET_LOOKUP=true`.
- `helpers_mcp_tools`, `helpers_files`, `utils_path_helpers`, `utils_excel_reader`, `helpers_mcp_table_readers` ve `helpers_send_message_core` birlikte çalışan bir zincirdir.
- Bu alanlarda yapılan küçük değişiklikler bile özellikle Windows VM / SSO / MCP akışında regresyon üretebilir.
- `path_exists_relaxed` ve `resolve_readable_path` gibi yardımcıların yalnızca global ortamda var olduğunu varsaymak güvenli değildir; araç/worker bağlamında erişilebilirlik korunmalıdır.
- Windows’ta kısa yol (8.3) path basename’i orijinal dosya adından farklı olabilir; testlerde fiziksel basename yerine `display` / okunabilirlik / gerçek çözüm başarısı tercih edilmelidir.
- `helpers_mcp_tools$get_session_user_id()` must remain scalar and must never fall back to `session$userData$current_session_files`; that object is a file registry, not an identity source.
- MCP/file resolver helpers should not assume path helpers are available only from `globalenv()`. Keep local fallbacks such as `helpers_mcp_tools$normalize_excel_path()` for worker and isolated-test contexts.
- Resolver diagnostics must go through `helpers_mcp_tools$mcp_debug_log(...)`; do not reintroduce raw `cat("[RESOLVE] ...")` output inside `resolve_file_argument()`. Production debug output must stay off by default and be enabled only through `MERGEN_MCP_DEBUG=true` or `options(mergen.mcp.debug = TRUE)`.

### 9B) Logging wrappers must preserve caller-frame glue evaluation

- `R/config_logging.R` içindeki güvenli log sarmalayıcıları hassas karakter verilerini redakte edebilir; ancak `logger` glue çözümlemesini bozmamalıdır.
- `{nchar(token)}` gibi ifadeler, log çağrısının yapıldığı gerçek çağıran ortamda çözülmeye devam etmelidir (ör. SSO observer scope'u).
- `logger::log_*` çağrılarını generic bir dispatch helper içine taşıyıp çağıran frame'i kaybetmek bu repoda gerçek VM/SSO runtime regression üretir.
- Eğer bir log wrapper eklenecekse veya değiştirilecekse, caller environment açıkça korunmalı; yalnızca secret masking test etmek yeterli sayılmamalıdır.
- `MERGEN_LOG_DIR` and `MERGEN_LOG_THRESHOLD` are now part of the repository contract; do not hardcode `logs/` in code/tests/scripts when active logging paths are environment-configurable.
- Caller-frame logging tests should keep working-directory control inside the test scope and assert against the active configured log directory (from `MERGEN_LOG_DIR` or fallback default).
- After sourcing `app.R`, test setup should not leak real logging side effects into the rest of the suite.
- Console color logging is opt-in. Keep `MERGEN_LOG_CONSOLE_COLORS=false` as the production default so ANSI color escape sequences do not leak into Windows VM/service logs.
- Do not replace this with unconditional `layout_glue_colors` for console logs. Local colored console output may be enabled temporarily with `MERGEN_LOG_CONSOLE_COLORS=true`.

---

## Test Suite and Execution Rules

In this repository, the main test suite runner is `tests/testthat.R`. `tests/testthat/helper_bootstrap.R` should be used as the bootstrap helper that initializes test context.

`helper_bootstrap.R` may sandbox filesystem and log paths via temp env vars (`MERGEN_LOG_DIR`, `MERGEN_FILES_ROOT`, `MERGEN_UPLOADS_DIR`, `MERGEN_INDEX_PATH`, `MERGEN_MCP_BASE_DIR`); contract tests must respect these env-driven paths instead of fixed repository-relative assumptions.

Tests should always be run from the repository root directory. When running tests on Windows VM, prefer a clean R session when possible. It is normal for the `summary` reporter output to end with `== DONE ==` without an explicit PASS line.

For promise/later-based tests, do not assume a single `later::run_now()` flush is always sufficient. When validating cleanup/final state, prefer a small bounded drain helper that consumes the later queue until the expected stable condition is reached.

Helper stubs used in tests must be visible in the same environment as the sourced helper functions. When changing helper files covered by tests, related test files should also be updated together.

In MCP Excel regression tests, validating based on physical Windows short-path basename can be fragile. In such tests, prioritize helper accessibility, resolution success via session registry, the `display` value, and whether the file can truly be read.

For single-record Turkish JSON/index edge cases on Windows VM, validate at contract level and tolerate equivalent serialized forms or loader-shape differences instead of treating them as product regressions.

Do not unit-test embedded NUL-byte behavior by forcing normal R character strings on Windows VM. In this repository, keep the runtime NUL guard in the helper, but write Windows-compatible tests around reliably representable path-safety rules. Avoid brittle tests that depend on platform-specific character construction behavior.

Quality-gate tests for repository scripts and entrypoint contracts should prefer parse-based inspection over fragile raw UTF-8 text scanning when possible; parse-based checks are more resilient on Windows VM.

Reasoning/SSE contract tests must remain runnable both through `source("tests/testthat.R", encoding = "UTF-8")` and individually via `testthat::test_file(...)`. If a test directly exercises helpers from `R/config_api.R`, `R/helpers_llm_response_postprocess.R`, or `R/helpers_llm_sse.R`, it must explicitly bootstrap/source those dependencies or use the established test bootstrap pattern.

Individual tests passing is not enough; tests that inspect source files must also pass when run through the full `source("tests/testthat.R", encoding = "UTF-8")` suite, because the full suite runs in a shared R session and is more sensitive to leaked warnings.

When a refactor introduces a new helper file that is also loaded indirectly by another helper, test both paths: direct `source("R/new_helper.R", ...)` and indirect source through the older public entry file. In this repo, isolated tests often source helper files before `global.R`; fallback source guards must therefore be working-directory independent and warning-free.

### Strict test runner rule
`tests/testthat.R` is a strict gate and should keep:

```r
stop_on_failure = TRUE
stop_on_warning = TRUE
```

Do not weaken the main runner to hide warnings. If a test produces noisy warnings only during full `test_dir()` execution, fix the test so it is deterministic and warning-safe. Source-inspection tests should avoid broad warning-prone recursive scans inside the main suite. Prefer targeted contract checks over scanning the whole repository when the test is part of the strict default runner.

Default-suite source-inspection tests must be warning-safe on Windows. Avoid warning-prone combinations such as `grepl(..., fixed = TRUE, ignore.case = TRUE, useBytes = TRUE)` inside broad scan loops. Prefer normalizing text/patterns first (for example lowercasing both) and then using fixed byte matching without `ignore.case`.

Atomic-write tests should prefer deterministic UTF-8-safe or raw-byte assertions instead of locale-dependent `readLines()` comparisons on Windows VM.

Windows-safe child-session test authoring rules:
- Avoid embedding non-ASCII repository paths directly into generated child-R scripts when this can be avoided.
- Prefer setting env vars in the parent test process and relying on inherited environment in child sessions.
- Prefer `withr::with_dir(...)` (or equivalent parent-side working-directory control) over serializing `setwd("...")` lines that may contain Turkish characters.
- For early-stop guard contracts (for example required-env preflight guards), prefer stable in-process `expect_error(...)` assertions over fragile child stdout/stderr capture.

### Current baseline coverage
- `safe_source` UTF-8 BOM + Turkish-character contract coverage (`test-safe-source-encoding-contract.R`)
- `safe_source` syntax-error passthrough coverage (real syntax errors must not be swallowed)
- `global.R` critical source-manifest ordering contract coverage (`test-global-source-manifest-contract.R`)
- production env policy contract coverage for strict `MERGEN_RUN_APP` parsing and the 25 MB upload cap (`test-production-env-policy-contract.R`)
- non-streaming LLM request-override parity coverage via `test-llm-reasoning-request-overrides.R`
- LLM content/reasoning fallback contract coverage via `test-llm-content-reasoning-fallback.R`
- maintainability ratchet coverage via `test-maintainability-ratchet.R`, including baseline score/count regression protection and Windows VM `testthat` compatibility through `expect_true(..., info = ...)`
- canonical effective user-id resolver coverage via `test-effective-user-id.R`, including SSO placeholder `0L` fallback to the live provider
- Server user-session context coverage via `test-server-user-session-context.R`, including local/SSO identity config construction and live provider fallback behavior
- Server runtime context coverage via `test-server-runtime-context.R`, including early boot contract validation for cache, identity, forward refs, state, chat runtime, and optional module attachments
- SSO live user-id provider contract coverage via `test-server-live-user-provider-contract.R`, ensuring `server.R` obtains live identity providers through `runtime_ctx$identity` and does not regress to startup snapshots
- File Manager policy/helper wiring coverage via `test-file-manager-policy-contract.R` and `test-file-manager-module-policy-wiring.R`, including delegated user-id normalization, icon HTML, timestamp formatting, and persisted refresh stale-request guards
- Bilge Yolaç UI/server split contract coverage ensuring `claudeCodeUI()` remains in `R/module_claude_code_ui.R`, `claudeCodeServer()` remains in `R/module_claude_code.R`, and the source order stays correct (`test-claude-code-ui-refactor-contract.R`)
- Bilge Yolaç model/config helper split contract coverage ensuring model/settings helpers remain in `R/helpers_claude_code_model_config.R`, process/runtime helpers remain in `R/helpers_claude_code.R`, source order stays correct, and core helper behavior is preserved (`test-claude-code-model-config-refactor-contract.R`)
- `safe_source`
- BOM-marked UTF-8 safe_source loading behavior
- tracked_future_promise task-registry cleanup behavior
- `register_session_cleanup_on_end()` / `safe_unlink_if_exists()` session-end cleanup behavior, including fake session compatibility for both `list` and `environment`-style test doubles
- database validation helpers
- file indexing helpers
- worker monitor helpers
- send-message core tool-family / stream-profile decisions
- `safe_join_path` path-safety behavior on Windows-compatible test inputs
- MCP Excel session-registry path resolution and helper-environment availability
- `config_logging.R` redaction wrappers and `dbg_dump()` behavior, including preservation of caller-frame `logger` glue evaluation
- MCP session user-id contract coverage ensuring file registries are not used as user identity (`test-mcp-session-user-id-contract.R`)
- MCP path fallback contract coverage for worker/isolated helper contexts (`test-mcp-path-fallback-contract.R`)
- MCP resolver debug-output contract coverage preventing raw `cat("[RESOLVE] ...")` production output (`test-mcp-debug-output-contract.R`)
- production console-color logging policy coverage (`test-logging-console-color-policy.R`)
- `app.R` boot-contract coverage for `boot_step(...)`, `validate_boot_state()`, `create_mergen_app()`, and `run_mergen_app()`, including strict `MERGEN_RUN_APP` autorun-flag parsing and explicit invalid `run_mergen_app(port = ...)` normalization fallback to `8009`
- caller-frame logging-wrapper behavior under Windows-safe test setup
- parse-based quality-gate coverage for `app.R`, `tests/testthat.R`, and `tests/scripts/*`
- Windows-safe file-store index regression coverage with shape-agnostic checks, including Turkish display-name edge handling
- Windows-safe atomic-write UTF-8 verification strategy
- thinking/reasoning model request_overrides contract coverage, including deep merge of `chat_template_kwargs$enable_thinking`
- true SSE request-body override coverage for `apply_model_request_overrides(body, selected_model)`
- future worker globals contract coverage for `apply_model_request_overrides`
- true SSE worker export/globals contract coverage for reasoning deltas, stop-file checks, and request overrides
- default offline baseline contract coverage for CDN/public asset dependency detection in runtime R/CSS/JS files
- warning-safe source-inspection strategy for strict `stop_on_warning` test runs
- SSE delta reasoning parser coverage for `delta$content`, `delta$reasoning`, `delta$reasoning_content`, and atomic delta/message edge cases
- production-default reasoning debug gate coverage via `MERGEN_REASONING_DEBUG=FALSE`
- production contract coverage for critical boot/runtime entry files without warning-prone broad recursive scans
- upload-size policy coverage for the 25 MB default and >25 MB rejection path
- file-manager client-side upload guard coverage via `test-file-manager-upload-limit-ui.R`
- File Manager policy helper contract coverage for upload limits, allowed extensions, and attach-rule hint text (`test-file-manager-policy-contract.R`)
- File Manager UI/server split coverage preserving `fileManagerUI(id)` in `R/module_file_manager_ui.R` and `fileManagerServer(...)` in `R/module_file_manager.R` (`test-file-manager-ui-refactor-contract.R`)
- File Manager module wiring coverage for policy-helper usage and persisted refresh stale-request protection (`test-file-manager-module-policy-wiring.R`)
- DB helper modularization contract coverage for `helpers_db_connection.R`, `helpers_db_validation.R`, and `helpers_database.R` source ordering (`test-db-refactor-contract.R`)
- chat message formatting refactor coverage for `helpers_chat_message_formatting.R`, including normal message formatting, empty data handling, and `ReasoningContent` propagation (`test-chat-message-formatting-refactor-contract.R`)
- Bilge Yolaç document extractor refactor coverage for `helpers_claude_code_document_extractors.R` source ordering and public extractor helper availability (`test-claude-code-document-extractors-refactor-contract.R`)
- Bilge Yolaç document maintainability ratchet coverage ensuring `helpers_claude_code_documents.R` stays below the intended extractor-refactor thresholds (`test-claude-code-document-extractors-maintainability-contract.R`)
- maintainability report support via `tests/scripts/maintainability_report.R` for tracking large files, line counts, and function counts without making the report itself a failing test gate
- strict test runner compatibility for `source("tests/testthat.R", encoding = "UTF-8")`
- source manifest contract coverage for `global.R` `safe_source(...)` existence/order/duplicate protection (`test-source-manifest-contract.R`)
- secret leak contract coverage across runtime files/tests with masking for known fake redaction fixtures (`test-secret-leak-contract.R`)
- runtime network-boundary contract coverage for accidental public URL/CDN dependencies with comment stripping, SVG namespace/example placeholders/internal host allow rules, optional `MERGEN_ALLOWED_INTERNAL_URL_REGEX`, and vendored offline asset skips for `www/js/highlight.min.js` + `www/css/all.min.css` (`test-runtime-network-boundary-contract.R`)
- expanded production parse contract coverage for additional high-risk runtime files (`test-production-contracts.R`)
- production BAT startup contract for UNC-safe `pushd`, app-root execution, Rscript/package preflight, and startup diagnostics through `logs/run_mergen_prod_console.log`
- runtime log-viewing contract via `view_latest_mergen_app_log.bat`, with the redundant console-log viewer files intentionally removed
- local Windows VM launcher self-test coverage for mapped-drive startup, dynamic Rscript selection, package visibility, UNC-safe log viewing, `MERGEN_PORT=8009`, and Turkish-path mojibake resistance

### Scripted validation flow (`tests/scripts/`)
- `tests/scripts/parse_sanity_check.R`: parse-only UTF-8 syntax sanity check from repo root.
- `tests/scripts/smoke_app_boot.R`: boot smoke for `app.R` without launching full runtime; verifies `safe_source`, `ui`, `server`, and `create_mergen_app()`, then confirms a `shiny.appobj` can be created.
- `tests/scripts/run_ci_local.R`: local equivalent of GitHub CI; intentionally runs `tests/testthat.R` in a **CLEAN CHILD R SESSION** to avoid global/session contamination after parse/smoke/bootstrap steps.
- `tests/scripts/run_vm_preflight_real.R`: real Windows VM preflight using real on-prem environment assumptions for production-like validation; it must check required env guards (`LOCAL_LLM_ENDPOINT`, `DB_DSN`, `AI_KEYS_MASTER`) before deeper boot/integration validation.
- `tests/scripts/maintainability_report.R`: non-failing maintainability report that lists large runtime files, approximate line counts, and function counts; use it to guide incremental refactors without changing the strict test runner.
- `tests/scripts/maintainability_report.R` remains the reporting tool, while `tests/testthat/test-maintainability-ratchet.R` is the default-suite regression guard; the ratchet is intended to prevent backsliding, not force a big-bang refactor. After the File Manager, Bilge Yolaç process/streaming, LLM SSE stream I/O, MCP analyze/visualize, Admin Response Analysis, Admin Feedback Analysis SQL query extraction, Admin Error Analysis, and Project/Resource Analysis security-summary refactors plus the related maintainability-ratchet update, the default maintainability ratchet baseline has been intentionally tightened: score `100/100`, at most `0` 800+ line files, at most `0` 25+ function files, `0` 1500+ line files, maximum file length `796`, and maximum function count `24`. Tighten these global values only when the maintainability report shows a real improvement in the corresponding global metric.

The Admin Hata Analizi extraction is now part of the ratchet baseline: `R/module_admin_hata_analizi.R` must remain below 800 lines, and `R/helpers_admin_hata_analizi.R` must remain below the helper size/function thresholds enforced by `test-maintainability-ratchet.R`.

`R/helpers_claude_code_workdir_scan.R` is budgeted at 423 lines and 14 functions.
`R/helpers_claude_code_workdir_snapshot.R` is budgeted at 450 lines and 24 functions.
`R/helpers_claude_code.R` remains budgeted at 617 lines and 29 functions.

Admin Feedback Analysis is now protected by `MERGEN_TEST_MAX_ADMIN_GERI_BILDIRIM_LINES = 799`and`MERGEN_TEST_MAX_ADMIN_GERI_BILDIRIM_FUNCTIONS = 5`. The extracted SQL helper file `R/helpers_admin_geri_bildirim_queries.R` is protected with a 260-line and 3-function budget.

### Admin Feedback Analysis modularization contract

Admin Feedback Analysis is intentionally split across a small UI/data-helper boundary, a SQL-query boundary, and the Shiny server module.

Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/helpers_admin_geri_bildirim.R",         encoding = "UTF-8")
safe_source("R/helpers_admin_geri_bildirim_queries.R", encoding = "UTF-8")
safe_source("R/module_admin_geri_bildirim.R",          encoding = "UTF-8")
```

Responsibilities:

* `R/helpers_admin_geri_bildirim.R`: public `adminGeriBildirimUI()`, tab UI helpers, and pure tag-counting/data-presentation helpers. It should not create Shiny observers or query the database.
* `R/helpers_admin_geri_bildirim_queries.R`: `admin_gb_feedback_queries()` and `admin_gb_fetch_data()`. This file owns the feedback SQL query package and the injectable query function boundary so tests can validate the contract without touching the database.
* `R/module_admin_geri_bildirim.R`: Shiny server orchestration, refresh/reactive flow, tab routing, and chart/table render functions.

Do not move the SQL query list or the public UI shell back into `R/module_admin_geri_bildirim.R`. The module should remain below the 800-line threshold.

Protected by:

```text
tests/testthat/test-admin-geri-bildirim-refactor-contract.R
tests/testthat/test-admin-geri-bildirim-query-contract.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-maintainability-ratchet.R
```

The Bilge Yolaç setup and run-lifecycle extraction is also protected by a file-specific ratchet: `R/module_claude_code.R` should remain at or below `MERGEN_TEST_MAX_CLAUDE_CODE_LINES = 799` by default. The latest maintainability report after the extraction shows `R/module_claude_code.R` at 799 lines, down from 1254 lines. Only tighten this threshold when a new maintainability report proves a lower stable baseline; do not loosen it to hide unrelated growth.

The LLM worker payload extraction is also protected by file-specific ratchets: `MERGEN_TEST_MAX_LLM_WORKER_LINES = 860`, `MERGEN_TEST_MAX_LLM_WORKER_PAYLOAD_LINES = 320`, and `MERGEN_TEST_MAX_LLM_WORKER_PAYLOAD_FUNCTIONS = 12`.
- Focused hardening checks can be run directly with:
  ```r
  testthat::test_file("tests/testthat/test-server-user-session-context.R")
  testthat::test_file("tests/testthat/test-server-runtime-context.R")
  testthat::test_file("tests/testthat/test-server-module-wiring-runtime-bindings.R")
  testthat::test_file("tests/testthat/test-server-live-user-provider-contract.R")
  testthat::test_file("tests/testthat/test-sse-worker-export-contract.R")
  testthat::test_file("tests/testthat/test-offline-baseline-contract.R")
  testthat::test_file("tests/testthat/test-mcp-session-user-id-contract.R")
  testthat::test_file("tests/testthat/test-mcp-path-fallback-contract.R")
  testthat::test_file("tests/testthat/test-mcp-debug-output-contract.R")
  testthat::test_file("tests/testthat/test-logging-console-color-policy.R")
  testthat::test_file("tests/testthat/test-llm-content-reasoning-fallback.R")
  testthat::test_file("tests/testthat/test-file-manager-policy-contract.R")
  testthat::test_file("tests/testthat/test-file-manager-module-policy-wiring.R")
  testthat::test_file("tests/testthat/test-file-manager-ui-refactor-contract.R")
  testthat::test_file("tests/testthat/test-file-manager-upload-limit-ui.R")
  testthat::test_file("tests/testthat/test-config-file-store-registry-refactor-contract.R")
  testthat::test_file("tests/testthat/test-maintainability-ratchet.R")
  testthat::test_file("tests/testthat/test-pk-analysis-security-summary-contract.R")
  testthat::test_file("tests/testthat/test-claude-code-ui-refactor-contract.R")
  testthat::test_file("tests/testthat/test-claude-code-model-config-refactor-contract.R")
  testthat::test_file("tests/testthat/test-source-manifest-contract.R")
  testthat::test_file("tests/testthat/test-secret-leak-contract.R")
  testthat::test_file("tests/testthat/test-runtime-network-boundary-contract.R")
  testthat::test_file("tests/testthat/test-production-contracts.R")
  testthat::test_file("tests/testthat/test-claude-code-document-extractors-refactor-contract.R")
  testthat::test_file("tests/testthat/test-claude-code-document-extractors-maintainability-contract.R")
  ```

CI guidance: GitHub CI is intentionally infra-independent. It does **not** access the real on-prem DB or the real local LLM; placeholder env vars are only used to satisfy startup guards and validate repository boot/structure/isolated tests. Real integration/preflight checks must run on Windows VM via `run_vm_preflight_real.R`, including writable-path probes against active configured directories (active log dir from `MERGEN_LOG_DIR` or fallback default).

### Production operation
Production startup on the Windows VM uses a two-layer launcher flow.

Local VM launcher:

```bat
C:\MergenLauncher\start_mergen_prod.bat
```

Repository/app-folder launcher:

```bat
run_mergen_prod.bat
```

Do not point a Windows shortcut directly at the UNC-path copy of `run_mergen_prod.bat`. `cmd.exe` cannot reliably use UNC paths as current directories. The shortcut should target the local VM launcher under `C:\MergenLauncher`, and the local launcher should temporarily map `\\rehisds\uygulamalar` to a drive letter before calling the real app-folder launcher.

Production launcher contract:

* `MERGEN_PORT` must remain `8009`.
* `MERGEN_HOST` should remain `0.0.0.0` for the VM production profile.
* `SSO_ENABLED` should be `TRUE` for the production VM profile.
* `run_mergen_prod.bat` must call `run_mergen_prod.R`, not bypass it with a direct `shiny::runApp('.')` call.
* `run_mergen_prod.bat` should dynamically select the newest `Rscript.exe` under `C:\Program Files\R\R-*`.
* Do not reintroduce fixed-only R version checks that fall back to the wrong `Rscript.exe` while a newer R is installed.
* The launcher should print R diagnostics, including `R.home()`, R version, `R_LIBS_USER`, and `.libPaths()`.
* Package visibility checks should use the same Rscript session that will launch production.
* Avoid `pushd "%APP_DIR%."`; use `pushd "%APP_DIR%"` if entering the app folder is needed.
* Avoid fragile parenthesized `if (...)` blocks containing `echo` lines with literal parentheses; this has caused CMD parse errors such as `from was unexpected at this time`.

Runtime log viewer:

```bat
view_latest_mergen_app_log.bat
```

The log viewer must remain UNC-safe. It should not depend on launching directly from a UNC current directory and must not regress to a plain `pushd "%~dp0"` pattern. It should use mapped-drive logic or another UNC-safe equivalent.

Startup failure diagnostics should be read from the launcher console output and/or:

```text
logs/run_mergen_prod_console.log
```

Normal runtime logs are:

```text
logs/mergen_YYYYMMDD.log
```

### Production launcher self-test

The Windows VM has a local self-test for the production launcher chain:

```bat
C:\MergenLauncher\test_mergen_prod_launcher.bat
```

This self-test must not start the Shiny app. It validates the launch environment only.

It should check:

* mapping `\\rehisds\uygulamalar` to a temporary drive,
* discovering the real `MERGEN Bilge` app folder without hard-coding Turkish path segments such as `Geliştirme`,
* presence of `run_mergen_prod.bat`, `run_mergen_prod.R`, and `app.R`,
* `MERGEN_PORT=8009` in `run_mergen_prod.bat`,
* absence of the unsafe `pushd "%APP_DIR%."` pattern,
* absence of UNC-fragile `pushd "%~dp0"` behavior in the log viewer,
* dynamic newest-Rscript detection under `C:\Program Files\R\R-*`,
* R library paths and required package visibility,
* required `.Renviron` / environment variables,
* port 8009 status.

The PowerShell self-test should be ASCII-safe where possible. Do not hard-code Turkish path components in the test. It should discover the app folder by searching under the mapped drive for `run_mergen_prod.bat` inside a folder named `MERGEN Bilge`.

For R snippets inside the PowerShell test, prefer writing temporary ASCII R scripts and executing those scripts instead of passing complex package vectors through fragile `Rscript -e` quoting. This prevents errors such as R interpreting `arrow` as an object instead of the string `"arrow"`.

Expected successful result:

```text
[RESULT] PASSED
```

---

## Reasoning Flow for Düşünüyorum=TRUE Models (New Standard)

In this codebase, the pre-response/in-response experience for models with thinking capability has been updated.

### Premium reasoning card behavior
- If `local_model_capabilities[[model]]$thinking == TRUE`, show the premium reasoning card instead of the classic typing animation.
- The card reuses the existing `#typing-animation-wrapper` container; it is opened with `premiumReasoningStart` on both thinking and non-thinking model paths.
- On the server side, send `premiumReasoningStart` at the beginning, `premiumReasoningStreamStart` during streaming, and `premiumReasoningReset` or `premiumReasoningError` on completion/error.
- The old “Düşünüyorum” snake animation has been fully removed (including `typing-indicator.css`, `typing_animation.js`, `ui.R` registration, and `app_core.js` cleanup).
- For non-thinking models, the `simulated` flag (inverse of `thinking_model_active`) is sent only when reasoning content is not expected; if real `reasoning_delta` is absent, synthetic phase text is shown sequentially on the client.
- Instead of the classic ring, insert an empty panel shell with `data-panel-takeover="true"`.
- In tools that depend on a thinking model (such as Kodlama Desteği/Excel Analizi), the panel model label must be derived from the `tool-resolved model`.

### UI/JS principles
- State machine: `idle → preparing → thinking → streaming → interrupted/error`
- Phase rotation: 2.6s
- Simulated phase text cadence: 1.8s
- Flicker guard: 420ms
- Minimum visibility: 1200ms
- Model names and error text must be HTML-escaped (XSS prevention).
- The `MutationObserver` in `app_core.js` must skip `TypingAnimationManager.create(...)` for shells marked with `data-panel-takeover="true"` to prevent duplicate animation/flicker.

### Live reasoning panel and persistence
- Reasoning content is streamed token-by-token in the live panel and does not disappear when the answer finishes; it remains collapsible in `completed/interrupted` states.
- Persistence is DB-backed via `MB_Messages.ReasoningContent`.
- On non-streaming paths, reasoning content must also be carried from worker output through message persistence, and `MB_Messages.ReasoningContent` must not be empty for thinking-model responses.
- In chat-history rendering, the archive block must be produced from a single source of truth; do not allow a duplicated live-panel + archive layered view.
- Simulated flows (without real reasoning text) must not be persisted to the bubble/archive; the panel should fade out as soon as answer streaming starts.

### Model-specific request_overrides contract
For thinking/reasoning models, `thinking = TRUE` alone must not be treated as sufficient; some local OpenAI-compatible endpoints require extra request fields to emit reasoning.
The `local_model_capabilities[[model]]$request_overrides` field in `R/config_api.R` must be preserved.

For Gemma-style models, use the following override when needed to enable reasoning flow:

```r
request_overrides = list(
  chat_template_kwargs = list(
    enable_thinking = TRUE
  )
)
```

`apply_model_request_overrides(body, selected_model)` must be applied after constructing the true SSE streaming body and before sending the HTTP request.
The same helper must also be applied on non-streaming LLM paths; otherwise streaming and non-streaming behavior diverges.
`R/helpers_llm_api.R::call_local_llm()` is explicitly part of this contract and must keep calling `apply_model_request_overrides(body, selected_model)` after building the non-streaming body and after temperature handling; removing this call can make tool/fallback/non-streaming routes diverge from true SSE streaming behavior for Düşünüyorum/reasoning models.
For helper visibility on the true streaming future worker side, keep `apply_model_request_overrides = apply_model_request_overrides` in `tracked_future_promise(..., globals = list(...))` within `R/server_handler_true_streaming.R`.
Kimi-style models may send reasoning as `delta$reasoning`; Gemma-style models may fall back to normal `delta$content` streaming with empty `ReasoningContent` when the override is missing.

### LLM content/reasoning fallback contract
- For thinking/reasoning models, empty `message$content` or `delta$content` must not overwrite usable `reasoning` / `reasoning_content`.
- `extract_llm_content_and_sources()` must only replace `ai_content` with non-empty candidates.
- Reasoning fallback should be applied after all normal content extraction attempts.
- This contract is protected by `tests/testthat/test-llm-content-reasoning-fallback.R`.

### Reasoning debug log policy
`[REASONING DEBUG]` lines must remain disabled by default in production.
Debug should be enabled only for temporary diagnostics via `MERGEN_REASONING_DEBUG=TRUE`.
A production-behavior patch must not leave debug output permanently enabled.

### Critical note for CSS regressions
- `.reasoning-panel.rp-live` must remain visible in the base state (`opacity: 1`, `transform: translateY(0)`).
- The entry animation must start from the `0%` frame of `rp-enter` with `both` fill mode.
- Otherwise, opacity can drop back to 0 during state transitions such as `data-state="completed"`, causing the panel to disappear.
- To prevent `[object Object]` regressions in the panel title, a client-side defense such as `sanitizeModelLabel()` is mandatory.
- The purple bottom-edge shimmer (`rp-shimmer`) should run only during active thinking/streaming phases and must be disabled in `completed`, `interrupted/stopped`, and `error` states, as well as under `prefers-reduced-motion`.

---

## What MERGEN Bilge Is

**MERGEN Bilge** is a Turkish-language AI assistant platform built on **Shiny** and **shinydashboard** for internal/corporate usage.

It combines:

- AI chat,
- conversation history and saved chats,
- file upload / preview / context injection,
- image generation,
- summarization,
- project/resource analysis,
- process guidance,
- character-based personas,
- AI Expert proactive speech,
- TTS/STT,
- support center,
- analytics/admin screens,
- version history,
- and a separate coding workspace called **Bilge Yolaç**.

The application is designed for a polished, immersive experience:

- cinematic startup,
- welcome screen,
- dynamic greeting,
- mythological character system,
- dark theme,
- audio and animation layers.

---

## High-Level Boot Flow

### Entry point: `app.R`
`app.R` is the real entry point and must be treated as special.

It does the following:

1. validates required boot files (`R/utils_safe_source.R`, `global.R`, `ui.R`, `server.R`),
2. sources `R/utils_safe_source.R`,
3. loads `global.R` via `safe_source()`,
4. loads `ui.R` via `safe_source()`,
5. loads `server.R` via `safe_source()`,
6. registers `www/` subdirectories with `addResourcePath()`,
7. registers `www/` root under the `img` prefix,
8. starts the app with `runApp(shinyApp(ui, server), ...)`.

### Why `app.R` matters
This repo intentionally avoids relying on plain `runApp(".")` logic inside the app because:

- Windows VM path behavior is fragile,
- `Ctrl+Enter` execution is used in practice,
- static asset resolution can break if resource paths are not explicitly registered.

If startup or missing asset issues appear, check `app.R` first.

Boot hardening note: `app.R` now includes explicit boot validation and fail-fast checks; coding agents must preserve `validate_boot_state()`, `create_mergen_app()`, and `run_mergen_app()` names/behaviors because smoke validation depends on them. `MERGEN_RUN_APP` autorun decisions now rely on explicit truthy/falsy normalization, and `run_mergen_app()` must re-normalize explicit call-time `port` inputs (not only env-derived defaults); invalid/missing/non-numeric/out-of-range values must deterministically fall back to `8009`. Boot-contract tests intentionally restore test stubs and isolate side effects after sourcing `app.R`, so entrypoint verification does not contaminate the remaining suite.

### Production runtime entrypoint contract

Keep the real `run_mergen_prod.bat` in the application root. If operators need a Desktop launcher, create a Desktop shortcut to the root BAT; do not copy the BAT to Desktop. The BAT relies on `%~dp0` to locate the app root, so a copied Desktop BAT will incorrectly run from Desktop and may create Desktop-local `logs/` output.

The BAT must continue using `pushd "%~dp0"` rather than `cd /d "%~dp0"` because production may run from a UNC/network path. `pushd` temporarily maps the UNC path to a drive letter and prevents the classic CMD error “CMD does not support UNC paths as current directories.”

`run_mergen_prod.bat` must keep writing startup/preflight/stdout/stderr diagnostics to `logs/run_mergen_prod_console.log` and must continue doing an Rscript/package preflight before app launch. Missing required packages should fail fast before startup. Optional `R_LIBS_USER` may be set for a fixed production package library on the Windows VM.

Do not reintroduce a dedicated live console-log viewer unless there is a clear operational need.

### Production log viewing contract

Runtime log viewing should use `view_latest_mergen_app_log.bat`. This viewer tails the newest `logs/mergen_*.log` file in read-only mode and can remain open while users interact with the app. It must not write to logs or stop the app.

`logs/run_mergen_prod_console.log` should be treated as a startup diagnostic log for Rscript, package preflight, boot messages, stdout, and stderr. It does not need a live viewer in normal operation.

The removed files `view_mergen_prod_console_log.bat` and `view_mergen_prod_console_log.ps1` should not be reintroduced casually. They were redundant for normal operations and were prone to Turkish mojibake in classic `cmd.exe`. If startup diagnostics are needed, inspect `logs/run_mergen_prod_console.log` directly or rely on `run_mergen_prod.bat` printing the last log lines on failure.

---

## Encoding and Safe Sourcing

The canonical `safe_source()` helper lives in `R/utils_safe_source.R`.

`app.R` sources that file first, then calls `safe_source()` for `global.R`, `ui.R`, and `server.R`.

Fallback behavior is intentionally defensive and BOM-aware:

- first tries standard `source(..., encoding = "UTF-8")`,
- if it encounters encoding/BOM-related errors or warnings, it falls back,
- reads the file as raw bytes,
- strips UTF-8 BOM when present,
- attempts `UTF-8`, `WINDOWS-1254`, and `latin1`,
- then runs parse/eval recovery in the target environment.

This design exists because this codebase has had real encoding sensitivity, especially on Windows and SSO-enabled VM environments, including BOM-marked UTF-8 files.

### Practical rule
If you add a new R file, it should be source-safe and UTF-8 safe.

---

## Required Environment Variables

The application validates required environment variables in `R/config_file_store.R`.

These are mandatory:

- `LOCAL_LLM_ENDPOINT`
- `DB_DSN`
- `AI_KEYS_MASTER`

If one is missing, startup stops with an explicit error.

### Important optional environment groups

#### Database
- `DB_DSN`
- `DB_DSN_2`
- `DB_DSN_3`
- `DB_CLIENT_ENCODING`
- `DB_NAME_ENCODING`

#### LLM
- `LOCAL_LLM_ENDPOINT`
- `LOCAL_LLM_API_KEY`
- `LOCAL_LLM_ENDPOINT_ALT`
- `LOCAL_LLM_ENDPOINT_ALT_API_KEY`
- `FILTER_MODEL`
- `AI_EXPERT_MODEL`
- `DESTEK_CHATBOT_MODEL`

#### TTS
- `LOCAL_TTS_ENDPOINT`
- `LOCAL_TTS_API_KEY`
- `LOCAL_TTS_MODEL`
- `LOCAL_TTS_VOICE`
- `LOCAL_TTS_TIMEOUT`
- `LOCAL_TTS_VERIFY_SSL`

#### STT
- `LOCAL_STT_ENDPOINT`
- `LOCAL_STT_MODEL`

#### SSO / Keycloak
- `SSO_ENABLED`
- `SSO_KEYCLOAK_URL`
- `SSO_REALM`
- `SSO_CLIENT_ID`
- `SSO_VALIDATE_ISSUER`
- `SSO_VALIDATE_EXPIRY`
- `SSO_TOKEN_REFRESH_MARGIN`
- `SSO_DEBUG`

#### Bilge Yolaç / Claude Code
- `CLAUDE_CODE_CLI_PATH`
- `CLAUDE_CODE_DEFAULT_WORKDIR`
- `CLAUDE_CODE_TIMEOUT`
- `CLAUDE_CODE_MODEL`
- `CLAUDE_CODE_MAX_CONCURRENT`
- `CLAUDE_CODE_PERSIST_SESSIONS`

#### Bilge Yolaç Plugins
- `CLAUDE_CODE_PLUGINS_ALLOW_TOGGLE`

#### Image generation
- `IMAGE_GEN_ENDPOINT`
- `IMAGE_GEN_MODEL`
- `IMAGE_GEN_TIMEOUT`
- `TRANSLATION_MODEL`

#### Service desk
- `SERVICE_DESK_API_KEY_URL`
- `SERVICE_DESK_RATE_LIMIT_URL`

#### File storage
- `MCP_FILES_BASE`

---

## Real Architecture

## Root-Level Files

- `app.R` - startup entry point, safe sourcing, resource path registration, app launch
- `global.R` - global options, locale handling, dependency sourcing order
- `ui.R` - full `shinydashboard` UI composition
- `server.R` - main server wiring and session flow
- `welcome_screen.R` - welcome screen data and quick action definitions
- `version_history.md` - source of the Yenilikler / version history page
- `README.md` - repository overview
- `CLAUDE.md` - coding-agent guide
- `ai_rehber.md` - knowledge base for Support chatbot and AI Expert reference

## Root-Level Directories (non-R/)

- `R/` - all application R modules, helpers, and configuration files
- `www/` - static assets (CSS, JS, CodeMirror, images, fonts)
- `bilge_yolac_plugins/` - Bilge Yolaç auto-discovered plugin directory. Each subdirectory is one plugin with `plugin.json` and optional `skills/`, `commands/`, `agents/`, `hooks/`, `mcp/`, `templates/`. No CLI, no internet required.
- `bilge_yolac_downloads/` - persistent directory where files generated by Bilge Yolaç (document summaries, agent outputs, etc.) are exposed as downloadable links. It is registered by `global.R` into Shiny with the `bilge_yolac_downloads` resource path name. It is included in the repository as empty via `.gitkeep`.

---

## `global.R` Load Order

The sourcing order in `global.R` is critical and should be respected.

### Group 1 - Foundation
Loaded first, no application-layer assumptions:

- `R/config_packages.R`
- `R/utils_common.R`
- `R/config_logging.R`
- `R/utils_rate_limiter.R`
- `R/helpers_worker_monitor.R`
- `R/utils_path_helpers.R`
- `R/utils_safe_path.R`
- `R/utils_atomic_write.R`
- `R/utils_upload_validator.R`
- `R/utils_log_redact.R`
- `R/utils_session_cleanup.R`
- `R/utils_safe_worker_run.R`
- `R/utils_file_index.R`
- `R/utils_excel_reader.R`

### Group 2 - Configuration
Defines application-wide configuration:

- `R/config_sso.R`
- `R/config_file_store.R`
- `R/config_file_store_index_mutation.R`
- `R/config_file_store_registry.R`
- `R/config_characters.R`
- `R/config_version_history.R`
- `R/config_api.R`
- `R/config_claude_code.R`
- `R/config_claude_code_plugins.R`

### Group 3 - Database and SQL
Core persistence and DB access:

- `R/helpers_db_connection.R`
- `R/helpers_db_validation.R`
- `R/helpers_chat_message_formatting.R`
- `R/helpers_db_chat_readers.R`
- `R/helpers_database.R`
- `R/library_queries.R`
- `R/config_sql_loader.R`

### Group 4 - Core Helpers
Shared utilities used across modules:

- `R/helpers_language.R`
- `R/helpers_messaging.R`
- `R/helpers_mcp_context.R`
- `R/helpers_mcp_bootstrap.R`
- `R/helpers_mcp_tools.R`
- `R/helpers_mcp_table_readers.R`
- `R/helpers_mcp_file_resolver.R`
- `R/helpers_mcp_schema_helpers.R`
- `R/helpers_mcp_basic_tools.R`
- `R/helpers_mcp_chart_tools.R`
- `R/helpers_mcp_analyze_visualize.R`
- `R/helpers_chartlab.R`
- `R/helpers_image_gallery.R`
- `R/helpers_preview.R`
- `R/helpers_file_pipeline.R`
- `R/helpers_files.R`
- `R/helpers_file_manager_policy.R`
- `R/helpers_file_manager_context_policy.R`
- `R/helpers_file_manager_table.R`
- `R/helpers_file_manager_refresh_guard.R`
- `R/helpers_file_manager_session_registry.R`
- `R/helpers_file_manager_runtime.R`
- `R/helpers_file_manager_storage.R`
- `R/helpers_chat_runtime.R`
- `R/helpers_send_message_core.R`
- `R/helpers_quick_action_intro_messages.R`
- `R/helpers_summarization_modes.R`
- `R/helpers_summarization_prompts.R`
- `R/helpers_followup_questions.R`
- `R/helpers_deep_analysis.R`
- `R/helpers_pk_analysis_core.R`
- `R/helpers_pk_analysis_filters.R`
- `R/helpers_sso.R`
- `R/helpers_destek_database.R`
- `R/helpers_admin_analytics.R`
- `R/helpers_health_formatters.R`
- `R/helpers_health_runtime_checks.R`
- `R/helpers_health_checks.R`
- `R/helpers_ai_expert.R`
- `R/helpers_claude_code_upload_folder.R`
- `R/helpers_claude_code_model_config.R`
- `R/helpers_claude_code_session_context.R`
- `R/helpers_claude_code_dir_ui.R`
- `R/helpers_claude_code_process.R`
- `R/helpers_claude_code.R`
- `R/helpers_claude_code_streaming.R`
- `R/helpers_claude_code_formatters.R`
- `R/helpers_claude_code_downloads.R`
- `R/helpers_claude_code_workdir_snapshot.R`
- `R/helpers_claude_code_plugins.R`
- `R/helpers_claude_code_document_extractors.R`
- `R/helpers_claude_code_documents.R`

### Group 5 - LLM Integration Layer
Model calls, tool formatting, SSE, worker execution:

- `R/helpers_llm_tool_formatters.R`
- `R/helpers_llm_response_postprocess.R`
- `R/helpers_llm_api.R`
- `R/helpers_llm_sse.R`
- `R/helpers_llm_worker.R`

### Group 6 - Shiny Modules
User-facing and system-facing modules.

#### Chat and messaging
- `R/module_chat_history.R`
- `R/module_saved_chats.R`
- `R/module_message_search.R`
- `R/module_chat_search.R`
- `R/module_followup_questions.R`
- `R/module_chat_actions.R`
- `R/module_chat_export.R`
- `R/module_feedback.R`

#### Files and media
- `R/module_file_manager_ui.R`
- `R/module_file_manager.R`
- `R/module_file_preview.R`
- `R/module_image_generation.R`
- `R/module_image_gallery.R`
- `R/module_summarization.R`

#### Settings
- `R/module_settings_kisisel.R`
- `R/module_settings_yapilandirma_ui.R`
- `R/module_settings_yapilandirma.R`
- `R/module_settings.R`
- `R/module_api_key.R`

#### AI / audio / character experience
- `R/module_ai_processing.R`
- `R/module_ai_expert.R`
- `R/module_tts.R`
- `R/module_tts_visualizer.R`
- `R/module_stt.R`
- `R/module_character_video.R`

#### Identity / session / startup / Bilge Yolaç
- `R/module_sso.R`
- `R/module_session_timeout.R`
- `R/module_performance.R`
- `R/module_user_identity.R`
- `R/module_startup_screen.R`
- `R/module_quick_actions.R`
- `R/module_claude_code_plugins.R`
- `R/module_claude_code_ui.R`
- `R/module_claude_code_akis.R`
- `R/module_claude_code.R`

#### Analysis
- `R/module_proje_kaynak_analizi.R`

#### Support
- `R/module_destek_yardim.R`
- `R/module_destek_hakkinda.R`
- `R/module_destek_surum.R`
- `R/module_destek_hata_bildir.R`
- `R/module_destek_geri_bildirim.R`
- `R/module_destek.R`

#### Admin
- `R/module_admin_genel_bakis.R`
- `R/module_admin_kullanici_analizi.R`
- `R/module_admin_yz_performans.R`
- `R/module_admin_geri_bildirim_genel.R`
- `R/module_admin_sohbet_kalitesi.R`
- `R/module_admin_zaman_analizi.R`
- `R/module_admin_gelismis_analizler.R`
- `R/module_admin_analytics.R`
- `R/helpers_admin_geri_bildirim.R`
- `R/module_admin_geri_bildirim.R`
- `R/module_admin_hata_analizi.R`
- `R/helpers_admin_yanit_analizi.R`
- `R/module_admin_yanit_analizi.R`
- `R/module_health_worker_metrics.R`
- `R/module_health_overview.R`
- `R/module_health_connectivity.R`
- `R/module_health_storage.R`
- `R/module_health_runtime.R`
- `R/module_health_security.R`
- `R/module_health_diagnostics.R`
- `R/module_health.R`
- `R/module_chartlab.R`

### Group 7 - Server-side Handlers and Observers
Wiring and runtime flow. Welcome recency correctness depends on **both** refresh timing (saved chats refreshed before welcome re-render) and recency sorting semantics (`last_message_timestamp` preference):

- `R/server_session_cache.R`
- `R/server_init_forward_refs.R`
- `R/server_init_user_session.R`
- `R/server_runtime_context.R`
- `R/server_init_session_state.R`
- `R/server_init_chat_runtime.R`
- `R/server_outputs_chat.R`
- `R/server_llm_response_handlers.R`
- `R/server_handler_summarization.R`
- `R/server_handler_image_generation.R`
- `R/server_handler_true_streaming.R`
- `R/server_send_message.R`
- `R/server_tts_handlers.R`
- `R/server_music_handlers.R`
- `R/server_ai_expert_handlers.R`
- `welcome_screen.R`
- `R/welcome_screen_modern.R`
- `R/server_welcome_handlers.R`
- `R/server_observers_settings.R`
- `R/server_observers_storage.R`
- `R/server_observers_files.R`
- `R/server_observers_saved_chats.R`
- `R/server_observers_image_gallery.R`
- `R/server_observers_chat_ui.R`
- `R/server_observers_navigation.R`
- `R/server_observers_file_clicks.R`
- `R/server_observers_startup.R`
- `R/server_observers_chat_input.R`
- `R/server_observers_misc.R`
- `R/server_outputs_downloads.R`

---

## UI Structure

`ui.R` defines the main sidebar and tab structure.

### Main navigation
- `Ana Söyleşi`
- `Söyleşi Yönetimi`
  - `Söyleşi Geçmişi`
  - `Kayıtlı Söyleşiler`
  - `Görsel Galerisi`
- `Bilge Yolaç`
- `Dosya Yönetimi`
- `Ayarlar`
  - `Kişiselleştirme`
  - `Yapılandırma`
- `Destek`
  - `Yardım Merkezi`
  - `Geri Bildirim & Hata`
  - `Yenilikler`
  - `Hakkında`
- dynamic admin menu for authorized users

### UI assets
The UI loads a large amount of static assets from `www/`:

- CSS themes
- JS handlers
- CodeMirror bundles
- Three.js files
- support page assets
- SSO assets
- Bilge Yolaç assets
- welcome screen assets
- TTS/STT/music scripts

### Important static directories
- `www/css/`
- `www/js/`
- `www/codemirror/`
- `www/lib/`
- `www/characters/`
- root files under `www/` exposed via `/img/...`

---

## Server Flow

`server.R` is the main **composition root** of the application.

It should remain the central wiring layer, but not become a dumping ground for every startup helper, reactive flag definition, or wrapper closure. Recent cleanup moved some of that responsibility into dedicated `R/server_init_*.R` files and the early `ServerRuntimeContext` boundary so that `server.R` stays readable while behavior remains unchanged.

### Current server initialization helper layer

The following files exist specifically to reduce orchestration coupling in `server.R`:

- `R/server_init_forward_refs.R` - delayed binding wrappers for welcome and send-message flows
- `R/server_init_user_session.R` - local/SSO identity setup, user config, live current-user provider, and compatibility session writes
- `R/server_runtime_context.R` - early boot contract object for cache, identity, forward refs, state, and chat runtime
- `R/server_init_session_state.R` - session-local reactive state and startup feedback loading
- `R/server_init_chat_runtime.R` - chat runtime helper closures such as reset/add-message/streaming wrappers

Rule:
- keep `server.R` as the wiring/composition layer
- put reusable startup/setup helpers into `server_init_*` or a small context helper when there is a clear boot contract
- do not move business logic into `server_init_*`
- do not use `ServerRuntimeContext` as a broad service locator

At a high level it performs:

1. session cache initialization,
2. SSO/local auth setup,
3. server runtime context initialization,
4. API key module wiring,
5. performance and health module startup,
6. support module startup,
7. settings initialization,
8. forward-reference attachment to runtime context,
9. Bilge Yolaç startup,
10. media stack initialization,
11. file manager / preview wiring,
12. chat state initialization and attachment to runtime context,
13. observers and navigation,
14. welcome handlers,
15. gallery / saved chat / history wiring,
16. chat engine / LLM response pipeline and chat runtime attachment,
17. TTS handlers,
18. final `send_message` function registration.

### SSO behavior
The application supports two auth flows:

#### Local development
When `SSO_ENABLED=FALSE`:

- `resolveUserIdentity()` derives the local/system identity,
- `get_or_create_user()` ensures DB user presence,
- session user data is populated synchronously.

#### Production / VM / Keycloak
When `SSO_ENABLED=TRUE`:

- `ssoAuthServer()` validates token flow,
- session starts with temporary user placeholders,
- once authenticated, Keycloak claims are mapped,
- DB user is created/updated,
- session becomes fully initialized.

If anything “works locally but not on VM”, SSO and encoding are the first things to inspect.

---

## Major Functional Systems

## 1) Welcome Screen and Quick Actions

`welcome_screen.R` defines `MAIN_ACTIONS_DATA`.

Current quick actions:

- `Process Management System`
- `Application Expert`
- `Proje ve Kaynak Analizi`
- `Excel Analizi`
- `Görsel Oluşturma`
- `Kodlama Desteği`
- `Özetleme Desteği`

Each action includes:

- id
- title
- description
- icon
- theme color
- model value

Quick actions no longer auto-send a seed prompt to the LLM.

Current behavior:
- the welcome card click sends only the action identity and model metadata,
- `R/module_quick_actions.R` activates the relevant tool mode,
- model selection is updated when needed,
- the chat view is opened,
- a prebuilt assistant-style intro message is inserted locally,
- the real LLM pipeline starts only after the user submits an actual prompt.

These intro messages are:
- generated from local prepared text variants,
- not produced by the LLM,
- intentionally excluded from persistent history and prompt context,
- personalized with `first_name` when available from session user data.

Treat quick-action logic as behavioral infrastructure.

---

## 2) Character System

Characters are defined in `R/config_characters.R`.

Current roster:

- `Mergen`
- `Ülgen`
- `Kayra`
- `Erlik`
- `Umay Ana`

Each character includes:

- id
- display labels
- avatar path
- image path
- accent colors
- lore
- style description
- profile metrics
- signature moves
- system prompt
- TTS voice

### Default
`Mergen` is the default style.

### Practical note
Many visual and behavioral systems depend on the selected character:

- welcome visuals,
- accent colors,
- AI Expert tone,
- character videos,
- Bilge Yolaç thinking flavor,
- TTS voice defaults.

---

## 3) Chat / LLM Pipeline

Core files:

- `R/server_send_message.R`
- `R/helpers_llm_api.R`
- `R/helpers_llm_worker.R`
- `R/helpers_llm_sse.R`
- `R/server_llm_response_handlers.R`
- `R/helpers_chat_runtime.R`

Key behaviors:

- user message capture,
- background worker execution,
- optional MCP tool usage,
- response streaming,
- message persistence,
- follow-up suggestion generation,
- optional TTS attachment.

### Critical pattern
Never pass live reactive objects into workers.

Always capture plain values first.

Correct pattern:

```r
chat_id <- isolate(rv$current_chat_id)
user_id <- isolate(rv$user_id)

future({
  some_worker(chat_id, user_id)
})
```

Incorrect pattern:

```r
future({
  some_worker(rv$current_chat_id, rv$user_id)
})
```

This repo is highly sensitive to reactive-scope mistakes.

---

## 4) File Storage and Indexing

Core files:

- `R/config_file_store.R`
- `R/config_file_store_index_mutation.R`
- `R/config_file_store_registry.R`

This subsystem provides:

- shared file root,
- persistent upload dir,
- MCP base dir support,
- JSON index,
- per-user buckets,
- registration and resolution helpers,
- stale index cleanup,
- filesystem fallback listing,
- periodic garbage collection.

### Important paths
- `MERGEN_FILES_ROOT`
- `MERGEN_UPLOADS_DIR`
- `MERGEN_MCP_BASE_DIR`
- `MERGEN_INDEX_PATH`

File-store roots are now environment-overridable and intentionally testable (`MERGEN_FILES_ROOT`, `MERGEN_UPLOADS_DIR`, `MERGEN_INDEX_PATH`); tests may sandbox these paths with temp directories, and coding agents must preserve this behavior.

### Key helpers
- `mergen_register_uploaded_file()`
- `global_register_file()`
- `resolve_uploaded_file()`
- `mergen_user_upload_dir()`
- `mergen_list_user_files()`
- `mergen_remove_from_index()`
- `mergen_clear_user_bucket()`

### Practical behavior
- Index writes are atomic (write temp file, then move/copy into place).
- Empty/corrupt `index.json` must degrade safely to an empty state instead of crashing file flows.
- Corrupt index files are backed up with a `.corrupt_<timestamp>` suffix before fallback.
- Physical file names may be timestamped/uniquified, while user-facing display names stay separate and preserved.
- Fallback display-name recovery may strip timestamp/randomized storage prefixes when needed.
- File-manager refresh is intentionally rollback-safe: on rebuild failure, previous in-memory file state is preserved; on success, previously attached files are restored.

If the UI shows the wrong filename or files disappear after refresh, investigate:

- index write path and atomic replacement,
- display-name persistence/recovery,
- user bucket resolution,
- filesystem fallback listing,
- encoding at JSON write/read boundaries,
- refresh rollback behavior.

---

## 5) Support Pages

Support area is coordinated by `R/module_destek.R`.

Subpages:

- `Yardım Merkezi` - `R/module_destek_yardim.R`
- `Geri Bildirim & Hata` - `R/module_destek_geri_bildirim.R` and `R/module_destek_hata_bildir.R`
- `Yenilikler` - `R/module_destek_surum.R`
- `Hakkında` - `R/module_destek_hakkinda.R`

### Knowledge base
`ai_rehber.md` is used as the help knowledge base and as AI Expert reference material.

This means changes to `ai_rehber.md` directly affect:

- support chatbot answers,
- AI Expert guidance quality,
- in-app help consistency.

### Version history
`version_history.md` is parsed by `R/config_version_history.R` and rendered by `R/module_destek_surum.R`.

If Yenilikler content is wrong, check `version_history.md` first.

---

## 6) AI Expert

Core files:

- `R/helpers_ai_expert.R`
- `R/module_ai_expert.R`
- `R/server_ai_expert_handlers.R`
- `ai_rehber.md`

AI Expert handles:

- greeting,
- page guidance,
- idle/proactive talk,
- character-aware phrasing,
- TTS-assisted speech,
- subtitle rendering.

### Important prompt sources
AI Expert system prompt is built from:

- selected character data,
- scenario type,
- current page context,
- user context from DB,
- `ai_rehber.md`.

### Important behavior constraints
AI Expert text is meant to be spoken aloud.

Therefore prompt rules emphasize:

- Turkish only,
- plain text,
- no emoji,
- no markdown,
- natural, smooth phrasing,
- no unusual Unicode decoration.

If output looks robotic or noisy, inspect `helpers_ai_expert.R` and `ai_rehber.md`.

---

## 7) TTS / STT / Music

Core files:

- `R/module_tts.R`
- `R/module_tts_visualizer.R`
- `R/server_tts_handlers.R`
- `R/module_stt.R`
- `R/server_music_handlers.R`

Related front-end files include:

- `www/js/tts_visualizer.js`
- `www/js/tts_manager.js`
- `www/js/stt_client.js`
- `www/js/music_manager.js`
- `www/css/tts_visualizer.css`
- `www/css/stt.css`

These systems interact with each other and are regression-prone.

Typical coupling areas:

- TTS audio + floating visualizer,
- STT modal + music pause/resume,
- background music + ducking,
- AI Expert speech + subtitles + TTS,
- navigation changes while audio is active.

Treat audio logic as concurrency-sensitive.

---

## 8) Bilge Yolaç (Claude Code Integration)

Core files:

- `R/config_claude_code.R`
- `R/config_claude_code_plugins.R`
- `R/helpers_claude_code_upload_folder.R`
- `R/helpers_claude_code_model_config.R`
- `R/helpers_claude_code_session_context.R`
- `R/helpers_claude_code_dir_ui.R`
- `R/helpers_claude_code_process.R`
- `R/helpers_claude_code.R`
- `R/helpers_claude_code_streaming.R`
- `R/helpers_claude_code_formatters.R`
- `R/helpers_claude_code_downloads.R`
- `R/helpers_claude_code_workdir_snapshot.R`
- `R/helpers_claude_code_plugins.R`
- `R/helpers_claude_code_document_extractors.R`
- `R/helpers_claude_code_documents.R`
- `R/module_claude_code_ui.R`
- `R/module_claude_code_akis.R`
- `R/module_claude_code_plugins.R`
- `R/module_claude_code.R`
- `www/js/claude_code.js`
- `www/js/claude_code_streaming.js`
- `www/js/claude_code_plugins.js`
- `www/css/claude_code.css`
- `www/css/claude_code_streaming.css`
- `www/css/claude_code_plugins.css`
- Bilge Yolaç welcome JS files under `www/js/bilge_yolac_*.js`

Bilge Yolaç is a web wrapper around Claude Code CLI-like behavior.

It includes:

- folder browsing,
- workdir selection,
- local folder copy-to-working-area (the "Copy local folder to Bilge Yolaç workspace" button copies the selected folder into the runtime working directory; it does **not** simply upload files),
- model tiers,
- tool-use rendering,
- streaming shell/file activity,
- themed welcome/game experience,
- connection tests,
- scenario templates,
- offline PDF/XLS/XLSX/DOCX text extraction and local LLM summarization,
- auto-generated `dosya_aciklamalari.txt` summary file in the working directory,
- downloadable generated file links rendered after each run.

### Document extraction and download flow

When the user's prompt or the working directory contains binary office documents (PDF, XLS, XLSX, DOCX), the pipeline in `R/helpers_claude_code_documents.R` intercepts the request before it reaches the Claude Code process:

1. `prepare_claude_code_document_context()` detects binary documents in the working directory via `list_claude_code_binary_documents()`.
2. For each supported file, text is extracted locally:
   - **PDF** → `pdftools::pdf_text()`, page-by-page, max 25 pages
   - **XLS/XLSX** → `readxl::read_excel()`, up to 5 sheets × 60 rows
   - **DOCX** → unzip + `xml2` parse of `word/document.xml`, max 500 paragraphs
   - **DOC** → **not supported**; user is instructed to convert to `.docx`
3. Extracted texts are written as `.txt` sidecar files in a temporary `document_support/` subdirectory.
4. A manifest file `BILGE_YOLAC_DOKUMAN_REHBERI.md` is written listing all sidecar paths.
5. The original prompt is replaced with an enriched prompt containing the extracted text inline so Claude can answer without invoking any file-reading tools.
6. For document summarization tasks, `summarize_claude_code_documents_with_local_llm()` calls the local LLM directly and writes the summary to `dosya_aciklamalari.txt` in the output directory.

After a run completes (both document-summary and standard streaming paths), `collect_claude_code_generated_downloads()` scans tool uses for written files, copies them into `bilge_yolac_downloads/`, and `format_claude_code_generated_downloads_html()` renders them as clickable download cards (`.cc-generated-file-card` CSS class) appended to the assistant message.

Document-summary runs must not resume or inherit Claude Code CLI session context. `cc_reset_document_summary_session_context()` clears `rv$cli_session_id`, resets `rv$conversation_context`, and sets `rv$current_runtime_model` before the local document-summary path starts. Keep this behavior separate from normal CLI streaming/resume behavior and protected by `tests/testthat/test-claude-code-run-lifecycle-contract.R`.

### bilge_yolac_downloads/ directory

`bilge_yolac_downloads/` at the repository root holds files that Bilge Yolaç has written and that the user should be able to download directly from the browser. Key facts:

- Created at startup if missing (in `global.R`).
- Registered with `shiny::addResourcePath("bilge_yolac_downloads", ...)` so files are accessible at `/bilge_yolac_downloads/<filename>` without exposing the full server path.
- The path is stored in `getOption("mergen.claude_code_download_root")`.
- Committed to the repo as an empty directory with `.gitkeep`.
- Do **not** source or process files inside this directory; it is purely a static serving endpoint.

### Model tiers
Defined in `R/config_claude_code.R`:

- `Hızlı`
- `Dengeli`
- `Güçlü`

### Streaming notes
The streaming UI renders:

- shell commands,
- file operations,
- tool results,
- live assistant text.

This area is especially sensitive to:

- Unicode symbol handling,
- browser mojibake,
- incremental HTML rendering,
- shell block toggling,
- partial JSON parsing.

### Bilge Yolaç Plugin Subsystem

Bilge Yolaç has a dedicated, offline-friendly plugin system. Plugins live under `bilge_yolac_plugins/` at the repository root and are **auto-discovered** at runtime. No CLI, no internet, no manual registration.

#### Plugin architecture files
- `R/config_claude_code_plugins.R` - status labels, component types, log prefix
- `R/helpers_claude_code_plugins.R` - `scan_local_plugins()`, `detect_plugin_components()`, `resolve_app_root()`
- `R/module_claude_code_plugins.R` - `claudeCodePluginsUI()` and `claudeCodePluginsServer()`
- `www/js/claude_code_plugins.js` - badge count update handler
- `www/css/claude_code_plugins.css` - plugin panel and card styles

#### Plugin directory layout
Each plugin lives in `bilge_yolac_plugins/<plugin-name>/` and follows this layout:

```text
<plugin-name>/
├── plugin.json          # Required: name, description, version
├── skills/              # Optional: knowledge files for Claude
│   └── main.md
├── commands/            # Optional: slash commands
├── agents/              # Optional: sub-agents
├── hooks/               # Optional: lifecycle scripts
├── mcp/                 # Optional: MCP server configs
└── templates/           # Optional: ready-to-use code helpers
```

#### Recognized component directories
`detect_plugin_components()` detects these subdirectories and shows them as Turkish badges:

| Directory | Component key | Turkish label |
|-----------|---------------|---------------|
| `commands/` | `commands` | Komutlar |
| `agents/` | `agents` | Ajanlar |
| `skills/` | `skills` | Yetenekler |
| `hooks/` | `hooks` | Kancalar |
| `mcp/` | `mcp_servers` | MCP Sunucuları |
| `templates/` | `templates` | Şablonlar |

If a new component type is added, update BOTH:
1. `claude_code_plugin_bilesenler` in `R/config_claude_code_plugins.R`
2. `detect_plugin_components()` in `R/helpers_claude_code_plugins.R`

#### Current plugin roster (15 plugins)
The `bilge_yolac_plugins/` directory ships with these plugins:

**Foundational:**
- `skill-creator` - guide for creating Claude Code skill files
- `plugin-dev` - plugin development guide
- `frontend-design` - frontend/UI design expertise
- `claude-md-management` - CLAUDE.md file management

**Development workflow:**
- `code-review` - systematic code review checklist
- `code-simplifier` - code simplification and refactoring
- `commit-commands` - Git commit management (Conventional Commits)
- `feature-dev` - feature development lifecycle
- `pr-review-toolkit` - pull request review workflow
- `ralph-loop` - polling/automation loops

**Quality and analysis:**
- `test-gen` - test generation across R/JS/Python
- `security-audit` - OWASP-aligned security review
- `doc-gen` - code documentation generation
- `debug-detective` - systematic debugging methodology

**Document generation:**
- `office` - DOCX, XLSX, PPTX, PDF via R helpers (see below)

#### Office plugin template framework
The `office` plugin is the only one that currently ships with a `templates/` directory containing actual R helper files:

- `bilge_yolac_plugins/office/templates/docx_helpers.R` - officer-based DOCX helpers
- `bilge_yolac_plugins/office/templates/xlsx_helpers.R` - openxlsx-based XLSX helpers
- `bilge_yolac_plugins/office/templates/pptx_helpers.R` - officer-based PPTX helpers
- `bilge_yolac_plugins/office/templates/pdf_helpers.R` - grDevices-based PDF helpers (no extra packages)
- `bilge_yolac_plugins/office/templates/document_readers.R` - offline text extraction helpers for PDF (`pdftools`), XLS/XLSX (`readxl`) and DOCX (unzip + `xml2`). `.doc` format is explicitly unsupported; the user is prompted to convert to `.docx`. This file mirrors the extraction logic in `R/helpers_claude_code_documents.R` but is provided as a standalone template that Claude Code can `source()` inside a session when additional extraction is needed.

These helpers are NOT sourced into the Shiny app. They are standalone R files that Claude Code references via `source()` inside Bilge Yolaç sessions. The separation of concerns is:
- `skills/main.md` - domain knowledge (when and why to use each format)
- `templates/*.R` - reusable implementation (actual working code)

If you extend the office framework, keep this separation. Never source template files into `global.R`.

#### Plugin panel UI behavior
The plugin panel is rendered by `claudeCodePluginsUI()` in the Bilge Yolaç left sidebar and is:

- **Collapsible** via the header click handler
- **Collapsed by default** (class `cc-plugins-collapsed` applied on initial render)
- **Auto-refreshed** on page load via an observer with priority 40
- **Manually refreshable** via the refresh button

**Important collapse implementation detail:** The `cc-plugins-collapsed` class MUST be toggled on the outer wrapper `div` (`ns("plugins_wrapper")`), NOT on the inner content `div`. The CSS selectors `.cc-plugins-collapsed .cc-plugins-content` and `.cc-plugins-collapsed .cc-plugins-toggle-icon` are descendant selectors and will only match when the class lives on an ancestor. Do not regress this by moving the class toggle to the content div.

---

## 9) SSO

Core files:

- `R/config_sso.R`
- `R/helpers_sso.R`
- `R/module_sso.R`
- `R/server_init_user_session.R`
- `R/server_runtime_context.R`
- `www/js/sso_auth.js`
- `www/css/sso_auth.css`

SSO is Keycloak-based and controlled by the global `SSO_ENABLED` flag.

### Practical rule
If a bug appears only when `SSO_ENABLED=TRUE`, check:

- token claim extraction,
- encoding of claim text,
- auth-initialization timing,
- delayed session setup,
- live current-user provider propagation through `runtime_ctx$identity`,
- user-specific file loading after auth.

---

## 10) Admin / Analytics

Main admin modules include:

- `R/module_admin_analytics.R`
- `R/module_admin_geri_bildirim.R`
- `R/module_admin_hata_analizi.R`
- `R/module_admin_yanit_analizi.R`
- helper modules in the admin family
- `R/helpers_admin_analytics.R`

Admin area includes:

- general analytics,
- feedback analytics,
- bug analytics,
- response feedback analytics,
- health monitoring.

Health worker metrics here are **application-level async occupancy metrics** and should not be described as logged-in user count or literal OS-level worker telemetry.

This area is role-sensitive and should not accidentally leak into normal-user flow.

---

## Worker Monitoring and Async Task Tracking

The admin health screen now includes application-level worker/task monitoring.

### What these metrics mean
The worker card does **not** show logged-in user count. It shows async workload occupancy derived from the app’s own task registry.

Displayed values are based on:
- configured future cluster size
- tracked active async jobs
- inferred free/busy worker counts
- queued work beyond cluster capacity

### Source files
- `R/helpers_worker_monitor.R`
- `R/module_health_worker_metrics.R`

### Operational rule
If you add a new async flow that should appear in the health screen, do **not** use raw `future_promise(...)` directly.

Use:

```r
tracked_future_promise(
  task_fn = function() {
    # async work
  },
  task_type = "meaningful_task_type",
  session_token = session$token
)
```

Important: `tracked_future_promise()` expects `task_fn`, not a raw expr block.

Incorrect:

```r
future_promise({
  some_async_work(...)
})
```

Also incorrect:

```r
tracked_future_promise({
  some_async_work(...)
})
```

Correct:

```r
tracked_future_promise(
  task_fn = function() {
    some_async_work(...)
  },
  task_type = "llm_non_streaming",
  session_token = session$token
)
```

The second critical purpose of `tracked_future_promise(...)` usage is safe transfer of worker dependencies. In this repo, “tracking” and “worker export safety” are combined in the same wrapper. Therefore, skipping the wrapper while writing async paths does not only leave the health screen incomplete; it can also cause runtime errors such as function-not-found inside workers.

### Current tracked async families
At minimum, health metrics are expected to include these async flows when present:
- non-streaming LLM
- streaming LLM
- true streaming SSE worker
- TTS
- image generation

If a new future-based path is added without the tracked wrapper, the health page will under-report worker usage.

---

## Front-End Structure Notes

## CSS
Large number of page- and feature-specific styles live under `www/css/`.

Important families:

- welcome / intro
- layout / components
- chat messages / inputs
- file manager
- settings
- support
- admin analytics
- SSO
- Bilge Yolaç
- version history

## JS
Important families under `www/js/`:

- core app bootstrapping
- streaming manager
- input and interaction handlers
- chat / markdown / citations
- welcome animation / neural / greeting
- TTS / STT / music
- support page JS
- AI Expert manager
- Bilge Yolaç streaming and game assets

### Practical rule
If a UI feature looks broken but R code seems correct, inspect the paired JS/CSS files before patching server logic.

---

## Current User-Facing Pages and What They Mean

### `chat`
Main conversation page.

Contains:

- welcome screen placeholder,
- chat header,
- model display,
- message count,
- new/copy/export actions,
- chat container,
- file prompt indicator,
- textarea,
- drag-and-drop support,
- model selector,
- send / voice / file actions,
- contextual controls for image, summary, and analysis tools.

### `history`
Conversation history.

### `saved_chats`
Saved conversation management.

### `image_gallery`
Generated image gallery.

### `claude_code`
Bilge Yolaç.

### `files`
File upload, preview, file management.

### `settings_kisisel`
Character and mode personalization.

### `settings_yapilandirma`
Model, tools, UI preferences, voice and technical settings.

### `destek_yardim`
Support contact information and help chatbot.

### `destek_geri_bildirim`
Feedback and bug reporting.

### `destek_surum`
Version / release notes.

### `destek_hakkinda`
Hakkında page / user guide.

### `health`
Health monitor, admin-facing.

---

## Repo-Specific Working Preferences

This section reflects how work in this repo is usually requested.

### Prefer:
- exact patches,
- clear file-level scope,
- preserving existing architecture,
- Turkish comments if comments are added,
- no unnecessary code movement,
- concrete testing steps.

### Avoid:
- broad rewrites,
- “cleanup” refactors without approval,
- renaming stable identifiers casually,
- introducing English comments into Turkish-heavy files,
- changing visible labels unless needed.

### `server.R` editing rule

When changing `server.R`, prefer this order of decisions:

1. Can this stay as wiring only?
2. Can the helper be moved into an existing `server_handler_*`, `server_observers_*`, or `server_init_*` file?
3. Is the dependency part of the early boot contract and therefore appropriate for `ServerRuntimeContext`?
4. Is a new file really justified?

Preferred:
- smaller `server.R`
- explicit helper bundles returned as lists
- session-local setup extracted cleanly
- no hidden dependencies on object creation order
- live identity and cache providers accessed through `runtime_ctx$identity` and `runtime_ctx$cache`

Avoid:
- adding more inline helper closures to `server.R` unless truly necessary
- mixing business logic with startup orchestration
- reintroducing direct `user_session$...` identity aliases in `server.R`
- reintroducing direct `session_cache$...` cache aliases when `runtime_ctx$cache` already owns the contract

---

## Sensitive / Regression-Prone Areas

These areas have produced regressions recently or are structurally fragile. Treat them carefully.

### 1) Encoding and mojibake
Especially sensitive in:

- VM deployments,
- SSO-enabled sessions,
- streamed text,
- DB reads/writes,
- JSON index files,
- Bilge Yolaç incremental rendering,
- support/version-history content.

### 2) Welcome screen layout
Sensitive interactions exist between:

- hidden chat header,
- fullscreen welcome wrapper,
- neural animation,
- greeting overlay,
- intro state,
- modern welcome CSS.

A small CSS change can break the top alignment or shift multiple panels.

### 3) Audio concurrency
Sensitive interactions between:

- TTS,
- STT,
- background music,
- character music,
- AI Expert speech,
- page navigation.

### 4) File indexing and display names
Be careful with:

- timestamped storage names vs display names,
- index rehydration,
- Excel persistence after restart,
- user-bucket scanning.

For large modules (especially `R/module_file_manager.R`), prefer tiny local helper extractions for repeated UI hint text, allowed-extension policy resolution, and repeated HTML row/action builders. Preserve behavior, reduce duplication, avoid broad rewrites.

### 5) Quick-action tool switching
Quick actions are tied to model/tool behavior. Regressions can make a tool appear active while another tool-family actually handles the request.

### 5A) Quick-action intro message behavior

Quick-action intro messages must remain assistant-style (`type = "ai"`) rather than system-style in order to preserve normal left-aligned chat rendering.

If editing the prepared intro message helper:
- keep emoji escapes valid in R strings,
- use single-backslash Unicode escapes such as `\U0001F44B` where escape form is preferred,
- prefer `first_name` over full display name for greeting personalization,
- keep these intro messages out of DB persistence and LLM conversation context unless explicitly changing product behavior.

### 6) Saved-chat restore
Loading a saved chat can accidentally route the user back into a stale welcome state if observers are wired incorrectly.

### 6A) Welcome recency invariants
- Welcome recent list represents most-recent **activity**, not just creation time.
- On transitions like `Yeni Söyleşi`, saved chat state must be refreshed before welcome re-render.
- Recency ordering should prefer `last_message_timestamp` and use creation timestamp only as fallback.

### 6B) Saved-chat state freshness regressions
Watch for divergence between in-memory `values$saved_chats` and DB-backed truth. This is a known source of top-3 recent chat regressions and the welcome screen being “one behind” when refresh ordering is changed incorrectly.

### 7) Streaming handlers
The chat stream and Bilge Yolaç stream both have fragile incremental rendering paths. Small output-format changes can break UI rendering.

### 8) Async worker dependency export

Streaming and non-streaming flows may not behave identically. Do not assume other async flows are safe just because one flow works.

Especially in non-streaming LLM, image-generation, and similar worker-based flows:
- `tracked_future_promise(...)` should be used
- required dependencies should be transferred to the worker
- reactive objects should be reduced to plain values beforehand
- the VM + SSO + Ctrl+Enter scenario should be considered

### 8A) Startup guards must match their execution context

Some startup helpers run inside reactive consumers in SSO flows, but may also run as plain function calls in local (`SSO_ENABLED=FALSE`) startup.

Practical rule:
- do not introduce `reactiveVal()` or `req()` into a startup guard unless that code is guaranteed to run inside a reactive context
- for one-time startup flags, prefer plain session-local state (for example, a local environment flag) unless reactive invalidation is truly needed
- `R/server_observers_startup.R` is especially sensitive here

### 8B) Path helper edge cases
- `safe_join_path()` must accept safe descendant paths on Windows VM and must not regress into false negatives for non-existing but valid child paths.
- Preserve defenses against traversal, absolute paths, and dot-only suspicious segments.
- Do not reintroduce brittle embedded-NUL tests that rely on normal R string construction on Windows.

### 8C) ServerRuntimeContext and identity/cache drift
- `server.R` should obtain user identity aliases from `runtime_ctx$identity`, not directly from `user_session`.
- `server.R` should pass send-message cache functions from `runtime_ctx$cache`, not from loose `session_cache` aliases.
- `ServerRuntimeContext` should remain small and focused on early boot objects.
- Do not add arbitrary downstream modules to `runtime_ctx` unless they have a clear repeated server boot contract and required-function validation.
- If full-suite tests fail after a runtime-context edit but individual tests pass, inspect stale static contract tests first. They may still be checking older `user_session$...` or `session_cache$...` patterns.

---

## If You Add or Change a Module

Follow this checklist:

1. Put the file in the correct layer.
2. Add `safe_source()` entry in the correct `global.R` group.
3. Update `ui.R` if the module has UI.
4. Update `server.R` wiring if the module has server logic.
5. Verify namespace consistency.
6. Verify Turkish strings remain UTF-8 safe.
7. Test both local mode and, if relevant, SSO-sensitive flow assumptions.
8. For welcome quick actions, prefer local UI-side prepared guidance over automatic LLM kickoff unless the product requirement explicitly says otherwise.

---

## If You Touch DB Logic

Remember:

- worker-safe patterns only,
- no pool object serialization into futures,
- capture reactivity before background execution,
- keep Turkish text encoding safe,
- check how user creation and authorization behave under SSO.

---

## If You Touch `ai_rehber.md`

Understand the impact:

- support chatbot quality changes,
- AI Expert prompt context changes,
- page guidance behavior changes,
- help-page consistency changes.

This file is not passive documentation. It is live prompt context.

---

## If You Touch `version_history.md`

Understand the impact:

- Yenilikler page content changes,
- current version display changes,
- support/about references may need alignment.

---

## If You Touch `www/js/claude_code_streaming.js`

Be especially careful with:

- Unicode symbols,
- emoji-like icons,
- mojibake risk on VM,
- incremental text assembly,
- shell visibility toggles,
- HTML escaping,
- copy/paste fidelity.

Prefer Unicode escape sequences over literal emoji if browser/VM rendering is unstable.

---

## Minimal Local Run Instructions

Typical local flow:

1. configure `.Renviron`,
2. open the project in R,
3. run `app.R` directly.

Do not assume a plain `runApp(".")` workflow is the safest path for this repo.

---

## Recommended Validation After a Patch

After changing anything non-trivial, test:

### Core
- app starts,
- sidebar loads,
- welcome screen appears,
- chat page is usable.

### Encoding
- Turkish labels display correctly,
- streamed assistant text displays correctly,
- support/version content displays correctly.

### Files
- upload works,
- file appears with correct visible name,
- refresh/reopen behavior still works.

### Chat
- send message,
- stream response,
- follow-up actions render,
- export/copy still works.
- regression check: finish a chat, click `Yeni Söyleşi`, and verify the just-finished chat appears immediately in welcome recent top-3 without manual refresh.

### Unit tests (helper / decision-logic changes)
For helper or decision-logic patches, run the unit test suite from repository root. Minimum command:

```r
source("tests/testthat.R", encoding = "UTF-8")
```

If needed, rerun only the target file with `testthat::test_file(...)`.

Contract-focused validation snippet:

```r
source("tests/testthat.R", encoding = "UTF-8")

testthat::test_file("tests/testthat/test-safe-source-encoding-contract.R")
testthat::test_file("tests/testthat/test-global-source-manifest-contract.R")
testthat::test_file("tests/testthat/test-production-env-policy-contract.R")
testthat::test_file("tests/testthat/test-llm-reasoning-request-overrides.R")
testthat::test_file("tests/testthat/test-server-user-session-context.R")
testthat::test_file("tests/testthat/test-server-runtime-context.R")
testthat::test_file("tests/testthat/test-server-module-wiring-runtime-bindings.R")
testthat::test_file("tests/testthat/test-server-live-user-provider-contract.R")
testthat::test_file("tests/testthat/test-source-manifest-contract.R")
testthat::test_file("tests/testthat/test-secret-leak-contract.R")
testthat::test_file("tests/testthat/test-runtime-network-boundary-contract.R")
testthat::test_file("tests/testthat/test-production-contracts.R")
```

Recent production-hardening coverage adds focused contract tests for source manifest integrity, secret leakage, runtime network boundaries, and expanded UTF-8 parse coverage of high-risk production files. The runtime network-boundary test is intended to catch accidental public internet/CDN dependencies in executable runtime code, not harmless documentation/license references: it strips R/JS/CSS comments, allows SVG namespace URLs, `example.*` placeholders, known internal/intranet hosts, and skips vendored offline assets such as `www/js/highlight.min.js` and `www/css/all.min.css`. Use `MERGEN_ALLOWED_INTERNAL_URL_REGEX` only for additional organization-specific internal URL allowlisting.

If a patch touches path-validation helpers, confirm behavior with Windows-style separators and Turkish-character file names, and avoid platform-brittle assertions for embedded NUL character construction.

### Audio
- TTS still plays,
- STT modal still opens,
- music does not overlap incorrectly.

### Bilge Yolaç
- page loads,
- scenario buttons work,
- stream blocks render,
- special icons/text do not mojibake.

### SSO-sensitive logic
If relevant to your change, verify assumptions for `SSO_ENABLED=TRUE` paths, even if you cannot fully run Keycloak locally.

---

## Key Files to Read First

If you are new to the repo, read in this order:

1. `app.R`
2. `global.R`
3. `ui.R`
4. `server.R`
5. `R/server_init_user_session.R`
6. `R/server_runtime_context.R`
7. `R/server_init_forward_refs.R`
8. `R/server_init_session_state.R`
9. `R/server_init_chat_runtime.R`
10. `welcome_screen.R`
11. `R/config_file_store.R`
12. `R/config_api.R`
13. `R/config_sso.R`
14. `R/config_characters.R`
15. `R/helpers_ai_expert.R`
16. `R/module_claude_code.R`
17. `R/module_claude_code_plugins.R`
18. `R/helpers_claude_code_plugins.R`
19. `R/module_destek_yardim.R`
20. `bilge_yolac_plugins/` (skim plugin layout and `office/templates/` as an example)

---

## Current Product Version Reference

Current public version history file shows:

- `v1.0` - official launch
- previous `v0.9` - beta

If any document mentions older release framing only, update it.

---

## Final Guidance for Coding Agents

When in doubt:

- preserve Turkish,
- preserve structure,
- patch surgically,
- wire modules carefully,
- respect `global.R` load order,
- keep `ServerRuntimeContext` small and explicit,
- test encoding-sensitive paths,
- and do not treat `ai_rehber.md` or `version_history.md` as passive docs.

They are live product behavior inputs.

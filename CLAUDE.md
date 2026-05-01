# CLAUDE.md - MERGEN Bilge Codebase Guide

## Purpose of This File

This document is the operational guide for coding agents working inside the **MERGEN Bilge** repository. It explains how the application is structured, how it boots, which files are critical, which areas are fragile, and what repository-specific working style must be followed.

`README.md` is the Turkish product and architecture overview. `ai_rehber.md` defines user-facing assistant behavior. This file is the primary English implementation guide for repository-safe code changes.

The repository is an R/Shiny application with a dark-theme, multimedia-heavy, Turkish-first user experience. It includes conversational AI, file upload and analysis, MCP workflows, image generation, TTS/STT, AI Expert guidance, support pages, admin analytics, health dashboard, SSO deployment, and a web-wrapped Claude Code experience named **Bilge Yolaç**.

---

## Non-Negotiable Repo Rules

### 1) Preserve Turkish text integrity

All user-facing Turkish text must remain UTF-8 and must not be Latinized. Be careful with file reading/writing, JSON, database writes, `.Renviron`, browser-rendered text, and Windows VM/SSO flows.

### 2) Keep new code identifiers ASCII-safe when practical

Use ASCII-safe helper, variable, list-field, and test helper names where practical. This is for Windows VM parser robustness. It is not permission to Latinize visible product text.

### 3) Code comments added to R files must be Turkish

When adding comments inside R/JS/CSS source files, follow the project style. R comments added by agents should be Turkish unless the surrounding file clearly uses another convention.

### 4) Prefer surgical, behavior-preserving changes

Avoid broad rewrites. Prefer one coherent refactor batch at a time, with exact file paths, small responsibility boundaries, and tests that prevent regression.

### 5) No internet-dependent runtime behavior

The application is an on-prem/offline-friendly Windows VM deployment. Do not introduce CDN, public internet asset loading, cloud-only services, or runtime downloads.

---

## Boot and Source-Order Model

Main entry points:

- `app.R`: boot entry and app factory/run guard
- `global.R`: explicit source manifest and global setup
- `ui.R`: UI composition
- `server.R`: top-level Shiny server wiring

`global.R` is still an explicit manifest. Source order matters. A new helper/module is not complete unless:

1. it is in the correct layer,
2. it is sourced in `global.R`,
3. dependencies are sourced before it,
4. server/UI wiring is updated where needed,
5. a focused contract test protects the new boundary.

Do not add a new file just to move a few lines. Add a new file only when it creates a clear, testable responsibility boundary.

---

## Current Architectural Direction

The project is moving away from hidden coupling caused by:

- strict source-order fragility,
- implicit globals,
- `session$userData` side effects spread across modules,
- `current_user_id` / SSO timing drift,
- large orchestration blocks inside `server.R`,
- forward references and placeholder functions,
- helper files that silently depend on previously sourced functions.

The preferred direction is incremental:

- pure helper functions,
- explicit contracts,
- small runtime context objects,
- dependency injection,
- focused initialization helpers,
- contract tests for source order and runtime wiring.

Do not propose a full framework rewrite or migration away from Shiny.

---

## UserSessionContext Contract

User identity and local/SSO session bootstrap now live in:

```r
R/server_init_user_session.R
```

This file owns the user-session initialization boundary and reduces direct identity orchestration inside `server.R`.

### Responsibilities

`R/server_init_user_session.R` is responsible for:

- building the app-level `user_config` structure from local or SSO identity,
- preserving the existing `session$userData` keys for backward compatibility,
- creating live `resolve_current_user_id` and `current_user_id_provider` functions,
- preventing SSO startup placeholder user id `0L` from leaking into user-scoped modules,
- keeping `server.R` from directly assigning identity/session fields,
- exposing a small initialization object returned by `serverInitUserSession(...)`.

### Required source order

Preserve this order in `global.R`:

```r
safe_source("R/server_init_forward_refs.R",  encoding = "UTF-8")
safe_source("R/server_init_user_session.R",  encoding = "UTF-8")
safe_source("R/server_init_session_state.R", encoding = "UTF-8")
safe_source("R/server_init_chat_runtime.R",  encoding = "UTF-8")
```

`R/server_init_user_session.R` must be sourced after `R/module_user_identity.R`, because it depends on the canonical identity resolver, and before downstream server init helpers that need a stable user provider.

### Required server.R pattern

`server.R` should initialize user identity through one object:

```r
user_session <- serverInitUserSession(
  session = session,
  session_cache = session_cache,
  sso_state = sso_state,
  base_user_config = user_config,
  sso_enabled = SSO_ENABLED,
  touch_session_fn = function(uid) {
    if (exists("perf_tracker", inherits = FALSE) &&
        is.list(perf_tracker) &&
        is.function(perf_tracker$touch_session)) {
      perf_tracker$touch_session(uid)
    }
  }
)

user_config_rv <- user_session$user_config_rv
resolve_current_user_id <- user_session$resolve_current_user_id
current_user_id_provider <- user_session$current_user_id_provider
```

Do not move local/SSO identity bootstrap code back into `server.R`. In particular, `server.R` should not directly assign identity fields such as:

```r
session$userData$user_identity
session$userData$user_first_name
session$userData$system_username
session$userData$user_id
session$userData$user_config
```

Those assignments belong behind the `serverInitUserSession(...)` boundary.

### Live user provider rule

In SSO flows, startup user id may temporarily be `0L`. Do not pass the startup snapshot into user-scoped modules. Pass a live provider such as:

```r
current_user_id_provider
resolve_current_user_id
```

This protects:

- File Manager,
- Saved Chats,
- Chat History,
- Image Gallery,
- Support modules,
- performance/session tracking,
- download and persisted-file flows.

### Tests protecting this contract

Run after touching identity/session bootstrapping:

```r
testthat::test_file("tests/testthat/test-server-user-session-context.R")
testthat::test_file("tests/testthat/test-server-live-user-provider-contract.R")
testthat::test_file("tests/testthat/test-effective-user-id.R")
testthat::test_file("tests/testthat/test-source-manifest-contract.R")
testthat::test_file("tests/testthat/test-production-contracts.R")
```

---

## Canonical Identity Resolution

Use `resolve_effective_user_id(...)` from `R/utils_common.R` when resolving the active user id. It must treat invalid or placeholder values such as `0`, `NA`, non-numeric strings, and missing values as absent, then fall back to the live provider before returning `0L`.

Avoid copy-pasted local `resolve_current_user_id()` variants. SSO regressions often come from duplicated identity-resolution snippets drifting apart.

---

## Major Modularization Contracts

### Database helper split

Preserve this order:

```r
safe_source("R/helpers_db_connection.R",          encoding = "UTF-8")
safe_source("R/helpers_db_validation.R",          encoding = "UTF-8")
safe_source("R/helpers_chat_message_formatting.R", encoding = "UTF-8")
safe_source("R/helpers_db_chat_readers.R",        encoding = "UTF-8")
safe_source("R/helpers_database.R",               encoding = "UTF-8")
```

Do not move connection, validation, chat message formatting, or chat-reader helpers back into `R/helpers_database.R`.

### File Store registry/index split

Preserve this order:

```r
safe_source("R/config_file_store.R",                encoding = "UTF-8")
safe_source("R/config_file_store_index_mutation.R", encoding = "UTF-8")
safe_source("R/config_file_store_registry.R",       encoding = "UTF-8")
```

`R/config_file_store.R` owns roots and low-level index IO. `R/config_file_store_index_mutation.R` owns guarded index mutation and upload registration. `R/config_file_store_registry.R` owns lookup, user upload directory resolution, stale pruning, and filesystem fallback listing.

### File Manager split

Preserve this order:

```r
safe_source("R/helpers_file_manager_policy.R", encoding = "UTF-8")
safe_source("R/helpers_file_manager_context_policy.R", encoding = "UTF-8")
safe_source("R/helpers_file_manager_table.R", encoding = "UTF-8")
safe_source("R/helpers_file_manager_refresh_guard.R", encoding = "UTF-8")
safe_source("R/helpers_file_manager_session_registry.R", encoding = "UTF-8")
safe_source("R/helpers_file_manager_runtime.R", encoding = "UTF-8")
safe_source("R/helpers_file_manager_storage.R", encoding = "UTF-8")
safe_source("R/module_file_manager_ui.R", encoding = "UTF-8")
safe_source("R/module_file_manager.R", encoding = "UTF-8")
```

`R/module_file_manager_ui.R` owns `fileManagerUI()` and browser-side upload-size checks. `R/module_file_manager.R` owns Shiny runtime orchestration. Pure decisions should stay in helper files.

### MCP split

Preserve the MCP source order:

```r
safe_source("R/helpers_mcp_context.R",           encoding = "UTF-8")
safe_source("R/helpers_mcp_bootstrap.R",         encoding = "UTF-8")
safe_source("R/helpers_mcp_tools.R",             encoding = "UTF-8")
safe_source("R/helpers_mcp_table_readers.R",     encoding = "UTF-8")
safe_source("R/helpers_mcp_file_resolver.R",     encoding = "UTF-8")
safe_source("R/helpers_mcp_schema_helpers.R",    encoding = "UTF-8")
safe_source("R/helpers_mcp_basic_tools.R",       encoding = "UTF-8")
safe_source("R/helpers_mcp_chart_tools.R",       encoding = "UTF-8")
safe_source("R/helpers_mcp_analyze_visualize.R", encoding = "UTF-8")
```

Do not move extracted MCP readers, resolver, schema, basic tools, chart tools, or analyze/visualize helpers back into `R/helpers_mcp_tools.R`.

### Bilge Yolaç split

Preserve helper order:

```r
safe_source("R/helpers_claude_code_upload_folder.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_model_config.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_session_context.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_dir_ui.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_process.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code.R", encoding = "UTF-8")
```

Preserve module order:

```r
safe_source("R/module_claude_code_plugins.R", encoding = "UTF-8")
safe_source("R/module_claude_code_ui.R", encoding = "UTF-8")
safe_source("R/module_claude_code_akis.R", encoding = "UTF-8")
safe_source("R/module_claude_code.R", encoding = "UTF-8")
```

Do not move `claudeCodeUI()` back into `R/module_claude_code.R`. Do not move model/settings helpers back into `R/helpers_claude_code.R`.

### Bilge Yolaç document extractor split

Preserve this order:

```r
safe_source("R/helpers_claude_code_document_extractors.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_documents.R", encoding = "UTF-8")
```

Extractor helpers own binary-document detection and PDF/Excel/DOCX text extraction. Document helpers own prompt/context/manifest/summary behavior.

### Health Dashboard split

Keep the public Shiny API stable:

```r
healthUI(id)
healthServer(id, perf_tracker)
```

Health checks must remain offline-compatible, lightweight, secret-safe, and non-destructive. They must not call public internet endpoints.

---

## Async and Worker Rules

Application-monitored async flows must use:

```r
tracked_future_promise(
  task_fn = function() {
    ...
  },
  task_type = "...",
  session_token = session$token
)
```

Do not introduce raw `future_promise(...)` in critical runtime paths. `tracked_future_promise(...)` is both a monitoring wrapper and a dependency-transfer boundary for worker-side functions.

For true SSE streaming, keep worker prewarm/export and `tracked_future_promise(..., globals = list(...))` aligned. Reasoning deltas, stop-file checks, and model-specific request overrides require helpers such as:

- `append_stream_reasoning_line`
- `streaming_should_stop`
- `apply_model_request_overrides`
- `merge_named_list_deep`

---

## Upload-Size Policy

File upload size enforcement is layered:

1. browser/client-side guard,
2. `shiny.maxRequestSize`,
3. server-side `validate_uploaded_file()` trust boundary.

The default production policy is 25 MB per file. Do not remove the browser-side guard; otherwise large uploads can make the File Manager page appear frozen before server validation can show a toast.

---

## Testing Rules

The main test runner must remain strict:

```r
source("tests/testthat.R", encoding = "UTF-8")
```

`tests/testthat.R` should keep:

```r
stop_on_failure = TRUE
stop_on_warning = TRUE
```

Contract tests should be deterministic and warning-safe. Avoid broad recursive source scans that produce platform-specific warnings.

For maintainability checks:

```r
source("tests/scripts/maintainability_report.R", encoding = "UTF-8")
```

Tighten `test-maintainability-ratchet.R` only after the report confirms a real new baseline. Do not loosen ratchets casually.

---

## Safe Refactor Pattern

When asked for architecture progress, choose one focused area only. A good batch usually has 4-8 related changes and includes:

1. exact file paths,
2. clear before/after snippets,
3. one new or updated helper boundary,
4. source-order update in `global.R`,
5. focused contract tests,
6. no unrelated cosmetic churn,
7. no behavior change unless explicitly requested.

Preferred next areas after the UserSessionContext batch:

- introduce a small FileRuntimeContext around `file_manager_data`, `session_files`, and `file_to_add`,
- reduce the forward-reference pattern around `welcome_fns` and `send_message_fns`,
- extract another large admin or Bilge Yolaç responsibility only if the boundary is clear.

---

## Final Safety Checklist for Code Changes

After a refactor batch, verify:

- R files parse,
- `testthat` passes,
- app boots locally with `SSO_ENABLED=FALSE`,
- app boots on VM with `SSO_ENABLED=TRUE`,
- file manager loads persisted files,
- saved chats load,
- new chat renders welcome screen,
- quick actions select correct model/tool mode,
- SSE streaming works,
- TTS/STT/music behavior is unaffected unless intentionally touched,
- Turkish characters render correctly.

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
- it is sourced in `global.R`,
- dependencies are loaded before it,
- `ui.R` / `server.R` wiring is updated where necessary.

### Database helper modularization contract
The database layer is now intentionally split into smaller responsibility-focused helpers. Preserve this source order:

```r
safe_source("R/helpers_db_connection.R", encoding = "UTF-8")
safe_source("R/helpers_db_validation.R", encoding = "UTF-8")
safe_source("R/helpers_chat_message_formatting.R", encoding = "UTF-8")
safe_source("R/helpers_database.R", encoding = "UTF-8")
```

Responsibilities:

* `R/helpers_db_connection.R`: DB connection, release, health probe, worker-side DB connection, and DB parameter encoding normalization.
* `R/helpers_db_validation.R`: validation helpers such as `validate_username()`, `validate_chat_title()`, and `validate_message_content()`.
* `R/helpers_chat_message_formatting.R`: conversion of DB message rows into app message objects, including generated-image HTML, Chartlab rendering, markdown fallback, timestamps, and `ReasoningContent` propagation.
* `R/helpers_database.R`: user/chat/message persistence and DB operations.

Do not move connection, validation, or message-formatting functions back into `R/helpers_database.R`. The split is protected by `test-db-refactor-contract.R` and `test-chat-message-formatting-refactor-contract.R`.

When updating `tests/testthat/helper_bootstrap.R`, keep its DB source order aligned with production `global.R`. Tests must load the extracted DB helper files before `helpers_database.R`.

### Bilge Yolaç document extractor modularization contract

The Bilge Yolaç document-processing layer now has a focused extractor split. Preserve this source order in `global.R`:

```r
safe_source("R/helpers_claude_code_document_extractors.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_documents.R", encoding = "UTF-8")
```

Responsibilities:

* `R/helpers_claude_code_document_extractors.R`: binary-document extension policy, cache-name sanitization, text truncation, binary document discovery, temporary document-support directory creation, PDF/Excel/DOCX text extraction, supported-document dispatch, and office reader template path resolution.
* `R/helpers_claude_code_documents.R`: document manifest generation, inline payload construction, document prompt construction, document context preparation, summary detail-level detection, summary messages, and summary file output.

Do not move extractor helpers back into `R/helpers_claude_code_documents.R`. Keep the fallback source guard in `helpers_claude_code_documents.R` so the file can still be sourced directly in isolated tests/debug sessions. The split is protected by `test-claude-code-document-extractors-refactor-contract.R` and `test-claude-code-document-extractors-maintainability-contract.R`.

For maintainability refactors, prefer extracting one clear responsibility at a time and preserving public function names. After each extraction, update `global.R`, `tests/testthat/helper_bootstrap.R`, and add a small contract test that prevents the old monolithic responsibility from silently returning.

### Bilge Yolaç UI and model/config modularization contract

Bilge Yolaç is now split into smaller responsibility-focused files. Preserve this source order in `global.R`:

```r
safe_source("R/helpers_claude_code_upload_folder.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_model_config.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_session_context.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_process.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code.R", encoding = "UTF-8")
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
* `R/helpers_claude_code_session_context.R`: Bilge Yolaç active-character and user first-name reactive context helpers used by `R/module_claude_code.R`.
* `R/helpers_claude_code_process.R`: Node/CLI process path resolution, processx command construction, Windows `.cmd`/UNC handling, process output UTF-8 normalization, non-ASCII escaping, Claude Code JSON/JSONL output parsing, and safe CLI workdir selection.
* `R/helpers_claude_code.R`: Claude Code CLI execution orchestration, status checks, runtime command handling, workspace helpers, and remaining Claude Code runtime helpers.

Do not move `claudeCodeUI()` back into `R/module_claude_code.R`.
Do not move model/settings helper functions back into `R/helpers_claude_code.R`.

The split is protected by:

* `tests/testthat/test-claude-code-ui-refactor-contract.R`
* `tests/testthat/test-claude-code-model-config-refactor-contract.R`
* `tests/testthat/test-claude-code-process-refactor-contract.R`
* `tests/testthat/test-claude-code-stream-finalize-contract.R`

For future maintainability refactors, keep using the ratcheted approach: extract one coherent responsibility, preserve public function names, update `global.R`, add a focused contract test, run the full strict test suite, then tighten `test-maintainability-ratchet.R` only after `tests/scripts/maintainability_report.R` confirms the new baseline.

### Proje/Kaynak Analizi filter modularization contract

The Proje/Kaynak Analizi layer now has a focused filter-helper split. Preserve this source order in `global.R`:

```r
safe_source("R/helpers_pk_analysis_core.R",      encoding = "UTF-8")
safe_source("R/helpers_pk_analysis_filters.R",   encoding = "UTF-8")
safe_source("R/module_proje_kaynak_analizi.R",   encoding = "UTF-8")
```r

Responsibilities:

R/helpers_pk_analysis_core.R: pure PK analysis helpers such as column summaries, date conversion, UTF-8 normalization, SQL Unicode execution, and SQL Server identifier normalization.
R/helpers_pk_analysis_filters.R: AI filter criteria extraction, stop-after-LLM guard, JSON filter parsing, smart dataframe filtering, and aggregation.
R/module_proje_kaynak_analizi.R: Proje/Kaynak Analizi runtime orchestration, RLS, DB/query execution, module behavior, and fallback helper loading.

Do not move extract_filter_criteria_from_prompt() or apply_smart_filters() back into R/module_proje_kaynak_analizi.R. Preserve their public function names because R/helpers_deep_analysis.R calls them directly.

The split is protected by:

tests/testthat/test-pk-analysis-filters-refactor-contract.R
tests/testthat/test-pk-analysis-core-refactor-contract.R
tests/testthat/test-pk-analysis-maintainability-contract.R

### File Manager modularization contract

The File Manager layer is intentionally split to keep the large runtime module from growing again. Preserve this source order in `global.R`:

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

Responsibilities:

* `R/helpers_file_manager_policy.R`: pure File Manager policy/helpers such as upload-size normalization, upload-size byte conversion, summarization/normal allowed extension policy, attach-rule hint text, File Manager user-id normalization, file-extension icon HTML, and file timestamp formatting.
* `R/helpers_file_manager_context_policy.R`: pure File Manager model-context cleanup planning, including stale selection IDs, MCP Excel-only enforcement, and single-Excel selection planning.
* `R/helpers_file_manager_table.R`: pure File Manager table helpers such as empty table schema, action button HTML, model-context checkbox HTML, and single-row table construction. This file must not mutate Shiny reactive state.
* `R/helpers_file_manager_refresh_guard.R`: pure File Manager persisted-refresh request generation guard. This file owns the monotonically increasing request token used to prevent stale refreshes from applying older file state.
* `R/helpers_file_manager_session_registry.R`: pure-ish File Manager session file registry helpers. This file owns `session$userData$current_session_files` entry shape, registry initialization, register/unregister behavior, and registry path normalization.
* `R/helpers_file_manager_runtime.R`: File Manager server runtime helper factory. It preserves local helper names used by `fileManagerServer()` while keeping settings resolution, effective user-id resolution, debug logging, registry wrappers, parent attach/detach synchronization, and extension/toast helpers outside the server module body.
* `R/helpers_file_manager_storage.R`: File Manager persistent storage helper factory. It owns user upload folder resolution, MCP-base path checks, user-folder listing, and persisted upload index synchronization.
* `R/module_file_manager_ui.R`: public `fileManagerUI(id)` definition, File Manager UI layout, and browser-side upload-size guard.
* `R/module_file_manager.R`: public `fileManagerServer(...)` definition, server-side upload processing, file table state mutation, attach/detach orchestration, persisted file refresh, deletion/clear operations, and parent-session synchronization. Small pure decisions should delegate to File Manager helper files instead of being reimplemented inline.

Do not move `fileManagerUI()` back into `R/module_file_manager.R`. Do not duplicate upload-size, allowed-extension, attach-rule text, user-id placeholder handling, file-extension icon HTML, file timestamp formatting, or session file registry path/entry decisions inside the module when the helper already owns that policy.

The persisted-file refresh path uses a request-generation guard from `fm_create_refresh_request_guard()` (`refresh_guard$next_id()` and `refresh_guard$is_latest(...)`) so stale refreshes cannot overwrite newer file state. Preserve that guard when editing `refresh_from_user_folder(...)`.

This split is protected by:

* `test-file-manager-policy-contract.R`
* `test-file-manager-context-policy-contract.R`
* `test-file-manager-table-contract.R`
* `test-file-manager-refresh-guard-contract.R`
* `test-file-manager-module-policy-wiring.R`
* `test-file-manager-ui-refactor-contract.R`
* `test-file-manager-upload-limit-ui.R`
* `test-source-manifest-contract.R`
* `test-maintainability-ratchet.R`

### 6) When the user asks for exact patches, be exact
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

* browser/client-side guard in `R/module_file_manager.R` rejects files above the configured limit before Shiny upload starts,
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
- `R/helpers_health_checks.R`: pure/safe health-check logic without Shiny UI coupling.
- `R/helpers_health_formatters.R`: status/severity normalization, secret-safe formatting, path-copy helpers, shared rendering helpers.
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
- `global.R` içinde MCP kaynak sırası şu şekilde korunmalıdır: `R/helpers_mcp_context.R` → `R/helpers_mcp_bootstrap.R` → `R/helpers_mcp_tools.R` → `R/helpers_mcp_table_readers.R` → `R/helpers_mcp_file_resolver.R` → `R/helpers_mcp_schema_helpers.R` → `R/helpers_mcp_basic_tools.R` → `R/helpers_mcp_chart_tools.R`.
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
- thinking/reasoning model request_overrides contract coverage, including deep merge of chat_template_kwargs$enable_thinking
- true SSE request-body override coverage for apply_model_request_overrides(body, selected_model)
- future worker globals contract coverage for apply_model_request_overrides
- true SSE worker export/globals contract coverage for reasoning deltas, stop-file checks, and request overrides
- SSO live user-id provider contract coverage to prevent startup current_user_id snapshot drift
- default offline baseline contract coverage for CDN/public asset dependency detection in runtime R/CSS/JS files
- warning-safe source-inspection strategy for strict stop_on_warning test runs
- SSE delta reasoning parser coverage for delta$content, delta$reasoning, delta$reasoning_content, and atomic delta/message edge cases
- production-default reasoning debug gate coverage via MERGEN_REASONING_DEBUG=FALSE
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
- `tests/scripts/maintainability_report.R` remains the reporting tool, while `tests/testthat/test-maintainability-ratchet.R` is the default-suite regression guard; the ratchet is intended to prevent backsliding, not force a big-bang refactor. After the Bilge Yolaç UI and model/config extractions, the ratchet baseline was intentionally tightened to the current maintainability report; do not loosen it unless a deliberate rollback is required.
- Focused hardening checks can be run directly with:
  ```r
  testthat::test_file("tests/testthat/test-sse-worker-export-contract.R")
  testthat::test_file("tests/testthat/test-server-live-user-provider-contract.R")
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
  testthat::test_file("tests/testthat/test-maintainability-ratchet.R")
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
- `R/utils_file_index.R`
- `R/utils_excel_reader.R`

### Group 2 - Configuration
Defines application-wide configuration:

- `R/config_sso.R`
- `R/config_file_store.R`
- `R/config_characters.R`
- `R/config_version_history.R`
- `R/config_api.R`
- `R/config_claude_code.R`
- `R/config_claude_code_plugins.R`

### Group 3 - Database and SQL
Core persistence and DB access:

- `R/helpers_database.R`
- `R/library_queries.R`
- `R/config_sql_loader.R`

### Group 4 - Core Helpers
Shared utilities used across modules:

- `R/helpers_language.R`
- `R/helpers_messaging.R`
- `R/helpers_mcp_tools.R`
- `R/helpers_chartlab.R`
- `R/helpers_image_gallery.R`
- `R/helpers_preview.R`
- `R/helpers_file_pipeline.R`
- `R/helpers_files.R`
- `R/helpers_chat_runtime.R`
- `R/helpers_summarization_modes.R`
- `R/helpers_summarization_prompts.R`
- `R/helpers_followup_questions.R`
- `R/helpers_deep_analysis.R`
- `R/helpers_sso.R`
- `R/helpers_destek_database.R`
- `R/helpers_admin_analytics.R`
- `R/helpers_ai_expert.R`
- `R/helpers_claude_code.R`
- `R/helpers_claude_code_streaming.R`
- `R/helpers_claude_code_formatters.R`
- `R/helpers_claude_code_downloads.R`
- `R/helpers_claude_code_plugins.R`
- `R/helpers_claude_code_documents.R`
- `R/helpers_quick_action_intro_messages.R`

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
- `R/module_file_manager.R`
- `R/module_file_preview.R`
- `R/module_image_generation.R`
- `R/module_image_gallery.R`
- `R/module_summarization.R`

#### Settings
- `R/module_settings_kisisel.R`
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
- `R/module_claude_code_klasor.R`
- `R/module_claude_code_akis.R`
- `R/module_claude_code_plugins.R`
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
- `R/module_admin_geri_bildirim.R`
- `R/module_admin_hata_analizi.R`
- `R/module_admin_yanit_analizi.R`
- `R/module_health.R`
- `R/module_health_worker_metrics.R`
- `R/module_chartlab.R`

### Group 7 - Server-side Handlers and Observers
Wiring and runtime flow. Welcome recency correctness depends on **both** refresh timing (saved chats refreshed before welcome re-render) and recency sorting semantics (`last_message_timestamp` preference):

- `R/server_session_cache.R`
- `R/server_init_forward_refs.R`
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

It should remain the central wiring layer, but not become a dumping ground for every startup helper, reactive flag definition, or wrapper closure. Recent cleanup moved some of that responsibility into dedicated `R/server_init_*.R` files so that `server.R` stays readable while behavior remains unchanged.

### Current `server_init_*` helper layer

The following files exist specifically to reduce orchestration coupling in `server.R`:

- `R/server_init_forward_refs.R` - delayed binding wrappers for welcome and send-message flows
- `R/server_init_session_state.R` - session-local reactive state and startup feedback loading
- `R/server_init_chat_runtime.R` - chat runtime helper closures such as reset/add-message/streaming wrappers

Rule:
- keep `server.R` as the wiring/composition layer
- put reusable startup/setup helpers into `server_init_*`
- do not move business logic into `server_init_*`

At a high level it performs:

1. session cache initialization,
2. SSO/local auth setup,
3. API key module wiring,
4. performance and health module startup,
5. support module startup,
6. settings initialization,
7. Bilge Yolaç startup,
8. media stack initialization,
9. file manager / preview wiring,
10. chat state initialization,
11. observers and navigation,
12. welcome handlers,
13. gallery / saved chat / history wiring,
14. chat engine / LLM response pipeline,
15. TTS handlers,
16. final `send_message` function registration.

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

Core file: `R/config_file_store.R`

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
- `R/helpers_claude_code.R`
- `R/helpers_claude_code_streaming.R`
- `R/helpers_claude_code_formatters.R`
- `R/helpers_claude_code_downloads.R`
- `R/helpers_claude_code_plugins.R`
- `R/helpers_claude_code_documents.R`
- `R/module_claude_code.R`
- `R/module_claude_code_klasor.R`
- `R/module_claude_code_akis.R`
- `R/module_claude_code_plugins.R`
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

```
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
- `www/js/sso_auth.js`
- `www/css/sso_auth.css`

SSO is Keycloak-based and controlled by the global `SSO_ENABLED` flag.

### Practical rule
If a bug appears only when `SSO_ENABLED=TRUE`, check:

- token claim extraction,
- encoding of claim text,
- auth-initialization timing,
- delayed session setup,
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
3. Is a new file really justified?

Preferred:
- smaller `server.R`
- explicit helper bundles returned as lists
- session-local setup extracted cleanly
- no hidden dependencies on object creation order

Avoid:
- adding more inline helper closures to `server.R` unless truly necessary
- mixing business logic with startup orchestration

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

### 8B) Path helper edge cases
- `safe_join_path()` must accept safe descendant paths on Windows VM and must not regress into false negatives for non-existing but valid child paths.
- Preserve defenses against traversal, absolute paths, and dot-only suspicious segments.
- Do not reintroduce brittle embedded-NUL tests that rely on normal R string construction on Windows.

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
5. `welcome_screen.R`
6. `R/config_file_store.R`
7. `R/config_api.R`
8. `R/config_sso.R`
9. `R/config_characters.R`
10. `R/helpers_ai_expert.R`
11. `R/module_claude_code.R`
12. `R/module_claude_code_plugins.R`
13. `R/helpers_claude_code_plugins.R`
14. `R/module_destek_yardim.R`
15. `bilge_yolac_plugins/` (skim plugin layout and `office/templates/` as an example)

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
- test encoding-sensitive paths,
- and do not treat `ai_rehber.md` or `version_history.md` as passive docs.

They are live product behavior inputs.

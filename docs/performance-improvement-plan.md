# MERGEN performance improvement plan

Last updated: 2026-06-19

## Current baseline

Known evidence at the start of this workstream:

| Lane / probe | Result | Interpretation |
|---|---:|---|
| Fake lane steady run | 20 active concurrent users / 300 seconds PASS | Current safe tested fake-lane capacity. |
| Fake lane boundary | 23 users / 60 seconds PASS, near timeout edge | Capacity headroom exists but is thin. |
| Fake lane failure edge | ~24 users / 60 seconds timeout saturation | Primary near-term bottleneck to profile. |
| Proxy lane | Key routing/isolation confirmed; heavier proxy stress saturates | Proxy proves isolation, not app capacity at high stress. |
| Real canary | Reaches real LLM gateway; blocked by HTTP 500 / ERR-234 rate-limit policy | Upstream gateway/admin configuration blocker, not MERGEN app-capacity proof. |

Do not claim improved capacity until a comparable soak artifact demonstrates it.

## Main runtime paths to inspect

| Path | Primary files / entry points | Notes |
|---|---|---|
| App startup | `global.R`, `server.R`, `R/config_source_manifest.R`, `R/bootstrap_source_manifest.R` | Source order is protected; add runtime helpers only through the manifest. |
| Session initialization | `server.R`, `R/server_init.R`, `R/server_observers.R`, SSO helpers | Watch repeated per-session work and DB/user bootstrap calls. |
| Message send flow | `R/server_send_message.R`, `R/helpers_send_message_*.R` | Current first instrumentation target. |
| Local/proxy/real LLM path | `R/helpers_llm_api.R`, `R/helpers_llm_sse.R`, `R/helpers_llm_worker*.R`, `tests/scripts/mock_llm_server.R`, `tests/scripts/proxy_llm_server.R` | Separate app saturation from upstream gateway/rate limits. |
| DB read/write path | `R/helpers_db_connection.R`, `R/helpers_db_chat_readers.R`, `R/helpers_db_chat_mutations.R`, `R/helpers_database.R` | Check direct vs pooled connection behavior and chat/message query frequency. |
| File upload/context path | `R/module_file_manager.R`, `R/helpers_file_manager_*.R`, `R/helpers_files.R`, `R/helpers_file_pipeline.R` | Watch large objects in session state and repeated context construction. |
| Saved chats/history | `R/module_chat_history.R`, `R/module_saved_chats.R`, `R/helpers_db_chat_readers.R` | Watch chat list/message hydration latency. |
| Streaming/non-streaming | `R/server_handler_true_streaming.R`, `R/helpers_streaming_*.R`, `R/helpers_llm_stream_io.R`, `R/helpers_worker_monitor.R` | LLM latency must not exhaust Shiny capacity. |

## Bottleneck hypotheses

1. LLM request latency or stalled fake/proxy requests occupy too much Shiny/future capacity near 24 active users.
2. Message send preparation may perform repeated synchronous work before handing off to the async/streaming path.
3. **[ELEVATED — static evidence 2026-06-19]** No DB connection pooling: `R/config_file_store.R` sets `pool <- NULL` and there is **no `dbPool`/`poolCreate` anywhere in runtime R**, so `get_connection()` opens a fresh direct ODBC connection (and disconnects) on *every* call. `finalize_stream_message()` in `R/server_handler_true_streaming.R` runs a **sequence** of these synchronous DB ops on the main Shiny event loop per finished message: `ensure_chat_ready()` (create chat + save user msg), `log_ai_usage()`, `save_message_to_db()`, `update_message_reasoning_content()`, and `saved_chats_data$refresh()`. Under concurrency these connect/disconnect cycles serialize on one thread — a strong candidate for the ~24-user timeout saturation. **Transaction-safety constraint:** `save_message_to_db()` runs a multi-statement transaction (`dbBegin`/`dbGetQuery`/`dbCommit`) on the connection from `get_connection()`, so a naive global `pool::dbPool` would be *unsafe* (a `Pool` cannot hold a transaction across statements). The current code is only correct *because* `pool` is always `NULL`. Pooling must therefore use transaction-aware checkout (`poolCheckout`/`poolWithTransaction`) and be VM-validated.
4. File context/MCP registry preparation may repeatedly scan or copy session file metadata.
5. Streaming/promise callback cleanup may add pressure when many requests time out simultaneously.
6. A single Shiny process may be the long-term architecture limit; do not change deployment before measuring app-path bottlenecks.

## Planned phases

| Phase | Status | Scope |
|---|---|---|
| Phase 0 — Orientation and baseline | In progress | Repository/docs/runtime path map created in this document. |
| Phase 1 — Profiling and instrumentation | In progress | Opt-in `[PERF]` timing for send-message segments, LLM HTTP/parse, and (new 2026-06-19) DB connection open/close. Static profiling has identified the leading bottleneck candidate (unpooled per-call ODBC connects on the main event loop). |
| Phase 2 — Low-risk performance wins | Not started | Cache/avoid repeated static work only after evidence identifies targets. |
| Phase 3 — LLM path hardening | Not started | Timeouts, bounded concurrency/backpressure, duplicate-send guards. |
| Phase 3.5 — DB connection pooling (transaction-safe) | Designed, not implemented | Highest-leverage candidate. Requires `poolCheckout`/`poolWithTransaction` for transaction sites and VM + SSMS Turkish-encoding validation. Do not implement blind from cloud. |
| Phase 4 — Concurrency architecture | Not started | Multi-process/reverse-proxy/queue options after profiling. |
| Phase 5 — Evidence gate expansion | Not started | Profiles/artifact summaries/boundary probes. |
| Phase 6 — Documentation and handoff | Continuous | Update this file each session. |

## Evidence table

| Date | Change | Command / artifact | Result | Capacity conclusion |
|---|---|---|---|---|
| 2026-06-18 | Added opt-in performance instrumentation helper and send-message/LLM timing probes. | `Rscript -e 'testthat::test_file("tests/testthat/test-performance-instrumentation.R")'` | PASS | Instrumentation only; no capacity improvement claimed. |
| 2026-06-19 | Added opt-in `[PERF] db.connection_open/db.connection_close` timing in `R/helpers_db_connection.R`; new `test-db-connection-perf-instrumentation.R`; mirrored perf helper in test bootstrap. | `testthat::test_file("tests/testthat/test-db-connection-perf-instrumentation.R")` | PASS (5 assertions) | Instrumentation only; quantifies per-call ODBC connect/disconnect overhead on the next VM run. No capacity claim. |
| 2026-06-19 | Restored global maintainability ratchet: reverted `R/server_send_message.R` instrumentation bloat (722→693, broke the 694 cap in commit c10683e) and relocated the 4 send-message segment timers into their prep helpers. | `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")`; `test-send-message-maintainability-ratchet.R`; `test-send-message-prompting-contract.R`; `test-send-message-request-lifecycle-contract.R` | PASS (ratchet max file = 694 ≤ 694; 0 fail/warn/skip) | No threshold weakened; profiling value preserved (timers moved, not deleted). |
| 2026-06-19 | Whole-repo parse + cloud validation gate. | `tests/scripts/parse_sanity_check.R` (839 files); `bash tools/ai_validate.sh cloud-quick` | PASS (parse OK; cloud-quick failed_steps=0, skipped_steps=1) | cloud-quick proves parse + focused contract scope only; NOT app-boot/runtime/browser/VM/DB/SQL-Server/soak. |

## Session notes

### 2026-06-19 — Phase 1: DB-path profiling + ratchet repair

Targeted bottleneck: the ~24-user timeout saturation, focusing on synchronous main-event-loop work in the message-finish path.

Diagnosis (static profiling, file:line evidence):

- DB connection pooling is effectively **off**. `R/config_file_store.R:249` sets `pool <- NULL` (comment claims "initialized in server.R", but nothing ever creates it), and there is no `dbPool`/`poolCreate` anywhere in runtime R. So `get_connection()` opens a fresh direct ODBC connection and disconnects on every call.
- `get_connection()` is called many times per request across `helpers_db_chat_mutations.R` (8), `helpers_db_chat_readers.R` (5), `helpers_db_feedback.R` (6), `helpers_image_gallery.R` (5), etc.
- `finalize_stream_message()` (`R/server_handler_true_streaming.R`) runs on the main Shiny event loop and performs a *sequence* of these synchronous DB ops per finished message: `ensure_chat_ready()` (create chat + save user msg), `log_ai_usage()`, `save_message_to_db()`, `update_message_reasoning_content()`, `saved_chats_data$refresh()`. Under concurrency the connect/disconnect cycles serialize on one thread — the leading candidate for timeout saturation.
- Transaction-safety constraint: `save_message_to_db()` and `worker_save_assistant_response()` run multi-statement transactions (`dbBegin`/`dbGetQuery`/`dbCommit`, with `UPDLOCK/HOLDLOCK`) on the `get_connection()` connection. A naive global `pool::dbPool` would break this (a `Pool` checks out a different connection per statement). Pooling must use transaction-aware checkout.

Changed (all additive / behavior-preserving):

- `R/helpers_db_connection.R`: added opt-in `[PERF] db.connection_open` / `db.connection_close` timing (guarded `.db_perf_log`, no-op when `mergen_perf_log` is absent or `MERGEN_PERF_LOG` is off). This isolates connection overhead from query time so the next VM run can quantify it. Also logs `pooled=TRUE/FALSE` so logs reveal whether pooling is active.
- `tests/testthat/helper_bootstrap.R`: source the perf helper (mirrors the runtime manifest order) so opt-in `[PERF]` hooks are visible in isolated tests.
- `tests/testthat/test-db-connection-perf-instrumentation.R` (new): offline test (fake `Pool`, no ODBC) proving the hook fires only when enabled.
- Repaired a pre-existing maintainability-ratchet regression: the prior "Add performance instrumentation hooks" commit (`c10683e`) grew `R/server_send_message.R` 693→722, exceeding the global 694 line cap and leaving `test-maintainability-ratchet.R` red on this branch. Reverted that file's instrumentation to the known-good `a572d49` form (693 lines) and **relocated the 4 send-message segment timers into their prep helpers** (`helpers_send_message_request_lifecycle.R`, `helpers_send_message_prompting.R`, `helpers_send_message_core.R`), which have budget. The redundant cumulative milestones (overlapping the existing `[CHAT PERF]` logs) were dropped. No threshold was weakened; the `helpers_llm_api.R` LLM HTTP/parse timing from the prior session is untouched.

Evidence:

- `tests/scripts/parse_sanity_check.R`: 839 files parse OK.
- Focused tests (0 fail / 0 warn / 0 skip): `test-db-connection-perf-instrumentation.R`, `test-db-refactor-contract.R`, `test-db-pool-healthy.R`, `test-performance-instrumentation.R`, `test-maintainability-ratchet.R` (max file 694 ≤ 694), `test-send-message-maintainability-ratchet.R`, `test-send-message-prompting-contract.R`, `test-send-message-request-lifecycle-contract.R`.
- `bash tools/ai_validate.sh cloud-quick`: `failed_steps=0`, `skipped_steps=1` (app source smoke skipped). `profile_requested=cloud-quick`, `profile_effective=quick`, `validation_execution_status=ran_by_ai_repo_check`, `db_sso_vm_validation_performed=FALSE`, `sql_server_turkish_encoding_preflight_status=not_performed_by_ai_validate`.

Capacity conclusion: **unknown — no capacity claim.** This session added measurement and repaired a broken gate; it produced no soak artifact (the fake-lane load phase needs a running app at `MERGEN_SOAK_APP_URL`, not available in this cloud session). cloud-quick proves parse + focused-contract scope only — not app boot, runtime, browser, VM/SSO/DB, SQL Server Turkish encoding, or soak.

### 2026-06-18 — Phase 1 instrumentation slice

Targeted bottleneck: timeout saturation around 24 fake-lane users, with first focus on synchronous message preparation and non-streaming LLM HTTP latency.

Changed:

- Added `R/helpers_performance_instrumentation.R`, an opt-in helper controlled by `MERGEN_PERF_LOG=1` or `options(mergen.perf_log = TRUE)`.
- Loaded the helper immediately after logging setup in `R/config_source_manifest.R` so runtime files can call it without changing source order-sensitive DB/LLM helpers.
- Added sanitized `[PERF]` timing points in `R/server_send_message.R` for request start, route selection, chat preparation, prompt planning, file context construction, MCP preparation, and LLM-ready handoff.
- Added sanitized timing around non-streaming `httr::POST()` and response parsing in `R/helpers_llm_api.R`.
- Added `tests/testthat/test-performance-instrumentation.R` to keep the helper opt-in and secret-redacting.

Evidence:

- Focused instrumentation unit test passed.
- R parse checks passed for `R/server_send_message.R` and `R/helpers_llm_api.R`.

Capacity conclusion: unknown. This session intentionally added measurement hooks only; no soak evidence was produced and no higher-capacity claim is made.

## Open risks

- Enabling verbose performance logging during high-concurrency tests may add small I/O overhead; compare with and without `MERGEN_PERF_LOG=1` if results are close to threshold.
- Probes now cover send-message segments, LLM HTTP/parse, and DB connection open/close, but **not** per-query (statement-level) timing yet.
- Single-process Shiny capacity may still dominate after app-path micro-optimizations.
- DB connection pooling (Phase 3.5) is the leading fix candidate but is **not implemented**: it is production-VM/SQL-Server/ODBC/SSO/Turkish-encoding sensitive, cannot be validated from a cloud session, and must be transaction-safe (`save_message_to_db`/`worker_save_assistant_response` use `dbBegin`/`dbCommit`). Implement only on a VM-validated session.
- The global maintainability ratchet sits exactly at its cap (`server_send_message.R` = 694 ≤ 694). Any further line addition to that file will fail the ratchet; new send-message work must extract a helper first. Note the send-message-specific ratchet allows up to 760, so this is purely the global "largest file" cap.
- Real-canary ERR-234 remains an upstream gateway/admin policy blocker and should stay separate from app-capacity testing.

## Next recommended step

On the production VM (running app), run an attach-mode fake-lane boundary probe with `MERGEN_PERF_LOG=1` at 20, 23, and 24 users:

1. Sum the new `[PERF] event=db.connection_open` / `db.connection_close` lines per request to quantify how much main-event-loop time is spent purely on ODBC connect/disconnect (vs query and LLM time). Cross-check against the send-message segment timers (`send_message.prepare_chat/prompt_plan/file_context/mcp_prepare`) and the existing `[CHAT PERF]` milestones.
2. If connection overhead is confirmed as a large share at 23–24 users, prototype **transaction-safe** connection pooling (Phase 3.5): create a `pool::dbPool` at server startup, route `get_connection()` to it, and convert the transaction sites (`save_message_to_db`, `worker_save_assistant_response`) to `poolCheckout`/`poolWithTransaction`. Validate on the VM with the DB encoding preflight (`run_vm_encoding_preflight_real.R`, `MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST=TRUE`) + SSMS Turkish-encoding spot checks, then re-run the soak boundary probe at 24/26/28 users to measure the capacity delta. Do not weaken any soak threshold.
3. Re-introduce the dropped send-message cumulative milestones only if room is made by a real helper extraction (the file is at the 694 cap).

# MERGEN performance improvement plan

Last updated: 2026-06-18

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
3. DB chat creation/message writes may be opening direct connections or issuing multiple sequential operations per request.
4. File context/MCP registry preparation may repeatedly scan or copy session file metadata.
5. Streaming/promise callback cleanup may add pressure when many requests time out simultaneously.
6. A single Shiny process may be the long-term architecture limit; do not change deployment before measuring app-path bottlenecks.

## Planned phases

| Phase | Status | Scope |
|---|---|---|
| Phase 0 — Orientation and baseline | In progress | Repository/docs/runtime path map created in this document. |
| Phase 1 — Profiling and instrumentation | In progress | Add opt-in, sanitized timing logs for send-message and LLM HTTP/parse segments. |
| Phase 2 — Low-risk performance wins | Not started | Cache/avoid repeated static work only after evidence identifies targets. |
| Phase 3 — LLM path hardening | Not started | Timeouts, bounded concurrency/backpressure, duplicate-send guards. |
| Phase 4 — Concurrency architecture | Not started | Multi-process/reverse-proxy/queue options after profiling. |
| Phase 5 — Evidence gate expansion | Not started | Profiles/artifact summaries/boundary probes. |
| Phase 6 — Documentation and handoff | Continuous | Update this file each session. |

## Evidence table

| Date | Change | Command / artifact | Result | Capacity conclusion |
|---|---|---|---|---|
| 2026-06-18 | Added opt-in performance instrumentation helper and send-message/LLM timing probes. | `Rscript -e 'testthat::test_file("tests/testthat/test-performance-instrumentation.R")'` | PASS | Instrumentation only; no capacity improvement claimed. |

## Session notes

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
- Current probes measure milestone latency but not DB-level per-query timing yet.
- Single-process Shiny capacity may still dominate after app-path micro-optimizations.
- Real-canary ERR-234 remains an upstream gateway/admin policy blocker and should stay separate from app-capacity testing.

## Next recommended step

Run an attach-mode fake-lane boundary probe with `MERGEN_PERF_LOG=1` against the production VM URL (`http://127.0.0.1:8009/`) at 20, 23, and 24 users. Compare `[PERF]` log milestones with soak artifacts to identify whether saturation appears before LLM handoff, during HTTP calls, or during cleanup/finalization.

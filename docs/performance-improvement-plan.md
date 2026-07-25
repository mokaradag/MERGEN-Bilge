# MERGEN performance improvement plan

Last updated: 2026-07-10

## Current baseline

Known evidence at the start of this workstream:

| Lane / probe | Result | Interpretation |
|---|---:|---|
| Historical fake lane steady run | 22 active concurrent users / 300 seconds PASS (pre-index-cache, 2026-06-19) | Historical baseline; kept for regression context. |
| Post-index-cache fake lane steady run | 1000 active concurrent users / 420 seconds PASS (VM console observed, `artifacts/soak/20260619-205535/soak_evidence.json`) | Strongest observed smoke/fake VM evidence, subject to artifact JSON verification; not real human chat/LLM capacity. |
| Post-index-cache fake lane corroboration | 250 users / 420 seconds PASS and 1000 users / 30 seconds PASS (VM console observed) | Shows much larger fake-lane envelope after index caching; do not promote the short 30-second run above sustained 420-second evidence. |
| Proxy lane | Key routing/isolation confirmed; heavier proxy stress saturates | Proxy proves isolation, not app capacity at high stress. |
| Saturday 2026-06-27 two-worker direct split-load | 2 workers on 8008/8009; strongest observed 750 total active proxy users / 30 minutes PASS with zero errors/timeouts | Direct split-load backend evidence only; not a single load-balanced URL proof. Loadgen loop lag high at 375 per worker means the load generator itself may be contributing pressure, so do not overclaim beyond direct split evidence. |
| Real canary | Reaches real LLM gateway; blocked by HTTP 500 / ERR-234 rate-limit policy | Upstream gateway/admin configuration blocker, not MERGEN app-capacity proof. |

As of the pre-index-cache 2026-06-19 baseline, the comparable fake-lane smoke artifact demonstrated 22 active concurrent users / 300 seconds PASS. After the root-page/index-cache optimization, VM console observations report 250 active users / 420 seconds PASS and 1000 active users / 420 seconds PASS in smoke/fake mode with 0 errors/timeouts; however, the referenced `artifacts/soak/20260619-204704/soak_evidence.json` and `artifacts/soak/20260619-205535/soak_evidence.json` files are not present in this checkout, so these values remain VM-console-observed until JSON artifacts are verified. These runs improve the GET-only fake-lane envelope; they do not prove browser/websocket human-chat capacity or faster real LLM generation.

## Main runtime paths to inspect

| Path | Primary files / entry points | Notes |
|---|---|---|
| App startup | `global.R`, `server.R`, `R/config_source_manifest.R`, `R/bootstrap_source_manifest.R` | Source order is protected; add runtime helpers only through the manifest. |
| Session initialization | `server.R`, `R/server_init.R`, `R/server_observers.R`, SSO helpers | Watch repeated per-session work and DB/user bootstrap calls. |
| Message send flow | `R/server_send_message.R`, `R/helpers_send_message_*.R` | Current first instrumentation target. |
| Local/proxy/real LLM path | `R/helpers_llm_api.R`, `R/helpers_llm_sse.R`, `R/helpers_llm_worker*.R`, `tests/scripts/mock_llm_server.R`, `tests/scripts/proxy_llm_server.R` | Separate app saturation from upstream gateway/rate limits. |
| DB read/write path | `R/helpers_db_connection.R`, `R/helpers_db_pool.R`, `R/helpers_db_chat_readers.R`, `R/helpers_db_chat_mutations.R`, `R/helpers_database.R` | Transaction-safe pool layer is `R/helpers_db_pool.R` (opt-in via `MERGEN_DB_POOL_ENABLED`). Reads auto-pool through `get_connection()`; transactions use `db_acquire_tx_connection()`/`with_db_transaction()` (real checkout, rollback-before-return). |
| File upload/context path | `R/module_file_manager.R`, `R/helpers_file_manager_*.R`, `R/helpers_files.R`, `R/helpers_file_pipeline.R` | Watch large objects in session state and repeated context construction. |
| Saved chats/history | `R/module_chat_history.R`, `R/module_saved_chats.R`, `R/helpers_db_chat_readers.R` | Watch chat list/message hydration latency. |
| Streaming/non-streaming | `R/server_handler_true_streaming.R`, `R/helpers_streaming_*.R`, `R/helpers_llm_stream_io.R`, `R/helpers_worker_monitor.R` | LLM latency must not exhaust Shiny capacity. |

## Bottleneck hypotheses

1. LLM request latency or stalled fake/proxy requests occupy too much Shiny/future capacity near 24 active users.
2. Message send preparation may perform repeated synchronous work before handing off to the async/streaming path.
3. **[ADDRESSED in code 2026-06-22; VM/SQL-Server validation pending]** DB connection pooling is now **implemented as an opt-in, transaction-safe layer** in `R/helpers_db_pool.R` (was previously absent — `R/config_file_store.R` still keeps `pool <- NULL` as the backward-compatible default). Before this change `get_connection()` opened a fresh direct ODBC connection (and disconnected) on *every* call, and `finalize_stream_message()` in `R/server_handler_true_streaming.R` ran a **sequence** of these synchronous DB ops on the main Shiny event loop per finished message (`ensure_chat_ready()`, `log_ai_usage()`, `save_message_to_db()`, `update_message_reasoning_content()`, `saved_chats_data$refresh()`). The **transaction-safety constraint still holds and is now respected**: `save_message_to_db()` runs a multi-statement transaction (`dbBegin`/`dbGetQuery`/`dbCommit`), and a naive global `pool::dbPool` *would* be unsafe (a `Pool` cannot hold a transaction across statements). The new layer therefore uses transaction-aware checkout — `db_acquire_tx_connection()` does `pool::poolCheckout()` for the transaction site, rolls back **before** returning the connection, and `with_db_transaction()`/`with_db_connection()` guarantee return on every path. Reads are pooled automatically (the pool object is registered into `.GlobalEnv$pool`, which the unchanged `get_connection()` already consults). Pooling is **default OFF** (`MERGEN_DB_POOL_ENABLED`), so cloud/test/boot behavior is unchanged; it is initialized once at app start (`app.R` `onStart`) and closed on `onStop`. Offline leak/checkout/release/rollback/encoding tests pass against real SQLite (`tests/testthat/test-db-pool-behavior.R`) and the interactive soak lane proves no leak (checkout==return) under repeated session load. **Still pending:** enabling `MERGEN_DB_POOL_ENABLED=TRUE` on the Windows VM and re-validating Turkish at-rest writes against SQL Server (`run_vm_encoding_preflight_real.R`) plus a re-run of the attach soak boundary to measure the real-chat capacity delta.
4. **[ADDRESSED in code 2026-07-25; VM validation pending]** File upload ingestion ran fully on the Shiny event loop. Both entry points (`fm_process_bulk_upload_batch()` in the File Manager, `handle_file_upload_batch()` in Ana Söyleşi) executed `validate_uploaded_file()` + `digest::digest(file=)` hashing + `fs::file_copy()` + size verification + a per-file `index.json` read/modify/write **synchronously inside an observer**; the File Manager path additionally wrapped the whole `for` loop in `withProgress()`. A multi-file batch therefore froze the uploading session *and every other session on that R process* for the duration of the disk work — worst on UNC/network shares and near the 25 MB per-file cap. The same file was also registered **twice** (pipeline + summarizer), doubling index lock/IO. This is now a bounded-concurrency background pipeline (`R/helpers_file_ingestion_*.R`): the observer does only cheap metadata planning and returns; validation/hash/copy/verify run in one future task per batch (files sequential), capped by `MERGEN_FILE_INGESTION_MAX_CONCURRENT` (default 2) with a bounded queue and a `future::nbrOfFreeWorkers()` gate so uploads cannot starve LLM/streaming/TTS/STT. Persistent index writes stay in the main process **on purpose** (the `dir.create` index lock polls with `Sys.sleep()`; cross-process contention would be worse than one short local write) but are now **batched into a single mutation per batch**. Registration happens exactly once. **Still pending:** measuring real UNC copy latency and second-session responsiveness during a large batch on the Windows VM.
5. Streaming/promise callback cleanup may add pressure when many requests time out simultaneously.
6. A single Shiny process may be the long-term architecture limit; do not change deployment before measuring app-path bottlenecks.
7. **[CONFIRMED for the pre-cache soak number; mitigated by index cache — static + VM-console evidence 2026-06-19]** The fake/smoke soak lane is **GET-only** against the app root (`soak_client.R:86,108-110` `httpget=TRUE`; load target `cfg$app_url` per `run_operational_soak_gate.R:235`). It serves the static `dashboardPage` index (`ui.R:7`) by re-serializing the tag tree per request on one httpuv thread, and never opens a websocket session — so it does **not** exercise hypotheses 1–5 (chat/LLM/DB). The historical 22→24 cliff was single-threaded **index-serving** saturation. After index caching, repeated isolated VM `GET /` timings improved from ~0.64 s to ~0.007 s warm cache, and VM console soak observations report 250/420 s and 1000/420 s PASS in smoke/fake mode. Therefore the soak-lane lever was per-request index serialization cost; DB pooling remains a separate real-chat/session concern.

## Planned phases

| Phase | Status | Scope |
|---|---|---|
| Phase 0 — Orientation and baseline | In progress | Repository/docs/runtime path map created in this document. |
| Phase 1 — Profiling and instrumentation | In progress | Opt-in `[PERF]` timing for send-message segments, LLM HTTP/parse, and (new 2026-06-19) DB connection open/close. Static profiling has identified the leading bottleneck candidate (unpooled per-call ODBC connects on the main event loop). |
| Phase 2 — Low-risk performance wins | Not started | Cache/avoid repeated static work only after evidence identifies targets. |
| Phase 3 — LLM path hardening | Not started | Timeouts, bounded concurrency/backpressure, duplicate-send guards. |
| Phase 3.5 — DB connection pooling (transaction-safe) | **Implemented (opt-in) 2026-06-22; production-hardened 2026-06-27; VM/SQL-Server validation pending** | `R/helpers_db_pool.R` adds `init_db_pool_once`/`close_db_pool_once`/`is_db_pool_enabled`/`with_db_connection`/`with_db_transaction`/`db_acquire_tx_connection`/`db_release_tx_connection`/`db_pool_status_snapshot`. Transaction site `save_message_to_db()` migrated to transaction-safe checkout. Default OFF; enable with `MERGEN_DB_POOL_ENABLED=TRUE`. **2026-06-27 hardening:** opt-in `MERGEN_DB_POOL_FAIL_FAST`; latent Pool-into-transaction fallback bug fixed; `/readyz` `db_pool` observability + `fail_fast`; VM mechanics preflight `run_vm_db_pool_preflight_real.R`. Offline SQLite leak/rollback/encoding/failure-mode tests pass. Remaining: VM enable + SSMS Turkish-encoding re-validation + attach soak boundary re-measure (no streaming-path change). |
| Phase 4 — Concurrency architecture | Runtime support implemented; production load-balanced URL proof pending | Multi-worker runtime support exists (`/healthz`, `/readyz`, `tools/run_mergen_workers.R`, optional backpressure, runtime metrics, index-cache observability). Saturday direct split-load evidence supports the horizontal-scaling hypothesis, but real Keycloak/reverse-proxy load-balanced URL proof and 90-minute certification remain pending. |
| Phase 5 — Evidence gate expansion | In progress | Added the **interactive (in-process session) soak lane** (`tests/scripts/soak_interactive_lane.R`): real DB-pool/transaction/encoding/streaming-decision/upload/key-isolation exercises against real SQLite, with per-action metrics, DB-pool leak counters, isolation/rollback/mojibake checks, and a new `interactive_lane` evidence block + `interactive_metrics.csv`. Closes the "GET-only soak lane" gap. |
| Phase 6 — Documentation and handoff | Continuous | Update this file each session. |

## Evidence table

| Date | Change | Command / artifact | Result | Capacity conclusion |
|---|---|---|---|---|
| 2026-06-29 | **Streaming event-loop hardening** (this workstream) + a fresh proxy/interactive capacity ladder to 450 users. Code: incremental stream-file reading (no full reread per poll), opt-in adaptive poll backoff, broader delta-transport opt-in, follow-up generation throttle/kill-switch, saved-chats refresh debounce, per-operation backpressure kinds, defensive stream/reasoning size caps, secret-safe stream/follow-up/refresh counters. | `tests/scripts/run_operational_soak_gate.R` with `MERGEN_SOAK_PROFILE=proxy_llm`, `MERGEN_SOAK_PROXY_FORWARD_REAL=FALSE`, `MERGEN_SOAK_CAPACITY_LADDER=TRUE`, `MERGEN_SOAK_CAPACITY_USERS=100,300,350,400,425,450`, `MERGEN_SOAK_CAPACITY_STEP_SECONDS=300`, `MERGEN_SOAK_STABLE_SUCCESS_RATE_MIN=0.98` (VM console observed; artifact `artifacts/soak/20260629-082244/soak_evidence.json` not present in this checkout). Offline: focused behavior/contract tests for the new helpers + manifest/seam/ratchet contracts. | **PASS** — ladder all steps pass, `stabil=450`, `ilk_basarisiz=NA`, `onerilen_sonraki=450`; overall `effective_success_rate=0.9984`, errors=0, timeouts=164/104042 (all `connection_timeout`); p50/p95/p99=2407/12504.8/13880 ms; per-step p95 854→2966→10996→12545→13384→14254 ms; throughput 7566→5728→1874/min beyond 300u while `cpu_max` 21–31%; interactive lane no-leak/isolation/rollback PASS; key routing 5/5, isolation TRUE, mojibake 0, secret_leak 0, redaction verified. | Strong **proxy + GET-only HTTP index + in-process interactive (real SQLite)** evidence to **450 active users on a single worker (port 8009)**. Does **NOT** prove real LLM throughput (`PROXY_FORWARD_REAL=FALSE`), real browser/websocket human-chat concurrency, or SQL Server at-rest correctness. The throughput collapse + p95 climb past ~300 users at **low CPU** confirms single-event-loop/index-serving serialization as the remaining lever: a load-balanced URL over **only 8009 + 8008** plus enabling the new event-loop knobs (`MERGEN_STREAM_POLL_IDLE_BACKOFF`, `MERGEN_STREAM_DELTA_DEFAULT`, the `MERGEN_MAX_CONCURRENT_*` limits). No new capacity number is claimed beyond this lane. |
| 2026-06-27 | DB pool **production hardening** (no streaming-path change): added `MERGEN_DB_POOL_FAIL_FAST` (env/option, default OFF) to `init_db_pool_once()` + `app.R` `onStart` (default path byte-identical); fixed a latent transaction-safety bug where `db_acquire_tx_connection()` could pass a stale/invalid `Pool` from `get_connection()` into `dbBegin/dbCommit` (now routes to a single real `poolCheckout`, never a Pool object); surfaced `fail_fast` in `db_pool_status_snapshot()` (already on `/readyz`); added VM mechanics/observability preflight `tests/scripts/run_vm_db_pool_preflight_real.R`. | `testthat::test_dir(filter="db-pool")` (behavior + new `test-db-pool-production-readiness-contract.R` + `test-db-pool-failure-modes.R`, 0 fail / 0 warn); `test-maintainability-ratchet.R` (100/100, `helpers_db_pool.R` 23 functions, 0 net added); `test-app-http-routes-contract.R`; `test-production-contracts.R`. | PASS (offline) | Hardens fail/fallback behavior + observability; **no capacity number claimed**. SQL Server at-rest/throughput remain VM gates (`run_vm_db_pool_preflight_real.R` + `run_vm_sqlserver_pool_preflight_real.R` + attach soak). Streaming/SSE path unchanged. |
| 2026-06-27/28 | Long split proxy soak diagnostic evidence (operator screenshots; raw `artifacts/soak/20260627-180246` and `20260627-180302` JSON not present in this checkout). | Direct split runs against 8008 and 8009 with `proxy_llm`, `MERGEN_SOAK_CONCURRENT_USERS=350` per lane, `MERGEN_SOAK_DURATION_SECONDS=86400`, wall≈86497/86505s. Operator described “375+375 / 18h”; artifacts/screens show 350 per lane and ~86.5k wall seconds, so artifact values are source of truth unless raw evidence supersedes them. | **FAIL/FAIL capacity gate**: 8008 627226 requests / 256467 successes / 370759 timeouts / effective≈0.4089; 8009 627007 requests / 248673 successes / 378334 timeouts / effective≈0.3965; threshold 0.98, errors=0, dominant connection timeout, p95≈26s, p99≈27.2s, throughput≈435 op/min/lane, `loadgen_loop_lag_high`. Positive privacy/routing/isolation/DB-pool/encoding-helper/interactive checks passed in screenshots. | Failed capacity proof and useful negative diagnostic soak. Does not prove 1000 active users, 750 split readiness for this long duration, real LLM throughput, real browser/websocket concurrency, production SQL Server at-rest Turkish correctness, or a staged 50→100→250→500→1000 ladder because the capacity ladder was closed/not executed. |
| 2026-06-27 | Saturday direct two-worker split-load evidence after the horizontal-scaling commit. | VM screenshot-observed direct runs against two local workers: 8008 and 8009; artifacts `artifacts/soak/20260627-141848`, `20260627-141858`, `20260627-143534`, `20260627-143541`, `20260627-144755`, `20260627-144759`. | PASS/PASS at 425 total (212+213) for 10 min; PASS/PASS at 600 total (300+300) for 10 min; strongest observed PASS/PASS at 750 total active proxy users (375+375) for 30 min with zero errors/timeouts. 375-per-worker artifact reports `saturation_hint=loadgen_loop_lag_high`, so the load generator itself may be contributing pressure. | Supports horizontal-scaling/backlog hypothesis versus prior single-worker 400-425 connection-timeout/backlog boundary. Direct split-load only: still pending real Keycloak/reverse-proxy load-balanced URL proof, 90-minute production-like certification, real browser/websocket concurrency lane, real LLM throughput, and SQL Server at-rest validation where applicable. |
| 2026-06-27 | Latest proxy attach retest narrowed the 300→450 gap. | VM screenshot-transcribed `artifacts/soak/20260627-093805/soak_evidence.json`. | Overall FAIL: 136185 requests, 132043 successes, 4142 timeouts, effective_success_rate=0.9696 < 0.98; ladder PASS at 100/300/350/400 users for 600 s each, FAIL at 425 (8201/12243, effective≈0.6644). | Latest short staged PASS is 400 active proxy users / 10 min; longest stable proxy attach evidence remains 300 active proxy users / 90 min. Probe 410/415/420 and separate loadgen loop lag/burst effects before capacity claims. |
| 2026-06-22 | Implemented transaction-safe DB pool layer (`R/helpers_db_pool.R`), migrated `save_message_to_db()` to transaction-safe checkout (rollback-before-return), wired pool init/close into `app.R` `onStart`/`onStop`, and added the interactive soak lane. | `testthat::test_file("tests/testthat/test-db-pool-behavior.R")` (54 PASS); `test-maintainability-ratchet.R` (100/100); `test-operational-soak-gate-contract.R` (157 PASS); `MERGEN_SOAK_HTTP_LANE=false Rscript tests/scripts/run_operational_soak_gate.R` (PASS; interactive: 15 sessions/120 actions, checkout=return=121, leak=0, tx commit=45 rollback=15, mojibake=0, isolation PASS). | PASS (offline) | Proves pool checkout/return/commit/rollback/no-leak + interactive session DB writes against **real SQLite**. Does NOT prove SQL Server T-SQL at-rest behavior, real LLM throughput, or websocket concurrency — those remain VM gates. No capacity number claimed. |
| 2026-06-18 | Added opt-in performance instrumentation helper and send-message/LLM timing probes. | `Rscript -e 'testthat::test_file("tests/testthat/test-performance-instrumentation.R")'` | PASS | Instrumentation only; no capacity improvement claimed. |
| 2026-06-19 | Added opt-in `[PERF] db.connection_open/db.connection_close` timing in `R/helpers_db_connection.R`; new `test-db-connection-perf-instrumentation.R`; mirrored perf helper in test bootstrap. | `testthat::test_file("tests/testthat/test-db-connection-perf-instrumentation.R")` | PASS (5 assertions) | Instrumentation only; quantifies per-call ODBC connect/disconnect overhead on the next VM run. No capacity claim. |
| 2026-06-19 | Restored global maintainability ratchet: reverted `R/server_send_message.R` instrumentation bloat (722→693, broke the 694 cap in commit c10683e) and relocated the 4 send-message segment timers into their prep helpers. | `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")`; `test-send-message-maintainability-ratchet.R`; `test-send-message-prompting-contract.R`; `test-send-message-request-lifecycle-contract.R` | PASS (ratchet max file = 694 ≤ 694; 0 fail/warn/skip) | No threshold weakened; profiling value preserved (timers moved, not deleted). |
| 2026-06-19 | Whole-repo parse + cloud validation gate. | `tests/scripts/parse_sanity_check.R` (839 files); `bash tools/ai_validate.sh cloud-quick` | PASS (parse OK; cloud-quick failed_steps=0, skipped_steps=1) | cloud-quick proves parse + focused contract scope only; NOT app-boot/runtime/browser/VM/DB/SQL-Server/soak. |
| 2026-06-19 | Soak HTTP-lane bottleneck attribution (analysis only; no code change). | Static request-path map (`run_operational_soak_gate.R:235`, `soak_client.R:86,108-110`, `ui.R:7`, `app.R:145-152`) + latency math vs `artifacts/soak/20260619-153052` | N/A (analysis) | Pre-cache soak number was single-threaded index-serving bound, not DB-bound; no capacity claim from cloud. |
| 2026-06-19 | Root-page/index caching VM evidence (documentation update; no runtime code changed in this docs task). | Windows curl timing command documented below; VM console observed `artifacts/soak/20260619-204455`, `20260619-204704`, `20260619-205535`, `20260619-210427` (JSON not present in this checkout). | Warm `GET /` ~0.006-0.008 s after first request; cold `[PERF] event=index_render elapsed_ms=740 cache=miss_build`; smoke/fake 250 users / 420 s PASS p95=1983.8 ms; smoke/fake 1000 users / 420 s PASS p95=8377.8 ms; stress/proxy final p95=734.5 ms. | Stronger fake-lane/index-serving evidence only; does NOT prove real LLM generation is faster, browser console clean, memory growth clean, or 1000 real human chat sessions. |
| 2026-06-19 | Phase 3 (perceived responsiveness): defer follow-up suggestion generation off the chat finalize critical path in BOTH `R/server_handler_true_streaming.R` (streaming) and `R/server_llm_response_handlers.R` (non-streaming). Finalize/render the answer immediately with `followups = NULL`, then generate + `push_followup_update()` from a non-blocking `later(delay = 0)`. Added default-OFF `[PERF]` markers `stream.first_delta`, `stream.followups`, `nonstream.followups`. | `testthat::test_file(...)` for true-streaming reset/finalize, e2e streaming request-id, streaming poll lifecycle, sse worker export, follow-up regression, non-streaming stale-request race, e2e quick-actions streaming, e2e premium reasoning, maintainability ratchet, production contracts, source manifest | PASS (0 fail / 0 warn; cloud `C.UTF-8`) | Removes the synchronous follow-up `call_local_llm()` round-trip from the post-answer critical path. Cloud proves contracts/behavior only; the actual seconds saved must be measured on the VM (no real LLM endpoint in cloud). No threshold weakened. |
| 2026-06-19 | Restored maintainability ratchet after the daily-log-file reliability work pushed `R/config_logging.R` to 27 functions: extracted the daily-file cluster (`current_mergen_log_date`, `current_mergen_log_file_path`, `mergen_daily_file_appender`, `mergen_ensure_daily_log_file`) to new foundation file `R/config_logging_daily_file.R` (loaded before `config_logging.R`). | `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")` (222 PASS) + manifest/seam/zone/section contracts + `parse_sanity_check.R` (842 files) | PASS (score 100/100, max functions 24, 0 files ≥25 functions) | Behavior byte-for-byte unchanged; pure maintainability split. |

## Session notes

### 2026-07-25 — File upload ingestion moved off the Shiny event loop (bounded concurrency)

Root cause confirmed by reading the pre-change code, not by inference:

| Entry point | Blocking work on the event loop |
|---|---|
| `fm_process_bulk_upload_batch()` (`R/helpers_file_manager_upload_runtime.R`) | Whole batch inside one `observeEvent`, wrapped in `withProgress()`: per file `validate_uploaded_file()` (stat + `file.access`), `copy_to_mcp_base()` (xxhash64 of the full file + `fs::file_copy` + size check), `ensure_persisted_upload_index()` → `mergen_register_uploaded_file()` (index lock + full `index.json` read/write), `process_uploaded_file()`. |
| `handle_file_upload_batch()` (`R/helpers_file_pipeline.R`) | `shinyjs::delay(50, ...)` yielded *between* files, but each file still ran `copy_to_mcp_base()` + size verification + `global_register_file()` synchronously. |
| `processAndSummarizeFile()` | Called `global_register_file()` **again** for the same file → duplicate index lock + full index write per upload. |

Only the summarization step was already async.

Change: a shared four-layer ingestion pipeline (`R/helpers_file_ingestion_task.R`
pure plan → `R/helpers_file_ingestion_worker.R` worker execution →
`R/helpers_file_ingestion_queue.R` bounded slots/queue →
`R/helpers_file_ingestion_runtime.R` main-process dispatch/commit/cancel). One
future task per **batch** (its files sequential) instead of one per file, so a
20-file drop cannot fan out into 20 workers. Worker dispatch uses
`dependency_mode = "explicit"` with a **memoized** globals bundle
(`file_ingestion_worker_globals()`), so the recursive `.GlobalEnv` dependency
scan runs once per R process rather than per batch — the same trap that caused
the 2026-07-11 fast-lane regression.

Deliberate non-changes:

- Persistent index writes stay in the main process. The index lock is
  `dir.create`-based and polls with `Sys.sleep()` when contended; today only the
  main process writes it, so contention is zero. Moving writes into workers
  would introduce genuine cross-process contention and could block the event
  loop for up to the 5 s lock timeout. Instead the write is now **one batched
  mutation per batch** (`mergen_index_persisted_files()`), so main-process index
  cost is independent of batch size.
- The 25 MB cap is unchanged. Verified (not assumed) that Shiny's `FileUploader`
  POSTs **one file per HTTP request**, so `shiny.maxRequestSize` is effectively a
  per-file limit and the existing "Dosya başına en fazla 25 MB" wording is
  accurate; a regression test now locks that semantics.

Evidence produced in this session (offline, Linux cloud checkout):

| Check | Result |
|---|---|
| `test-file-ingestion-pipeline-behavior.R` | PASS (92 assertions; real temp-FS copy, integrity, cleanup, per-user isolation, queue bounds, cancel/session gating) |
| `test-file-ingestion-contract.R` | PASS (layer split, no live Shiny object in the worker path, index stays main-process, exactly-once registration, dispatch does no expensive work) |
| `test-file-pipeline-upload-batch-behavior.R` | PASS (42 assertions; unsupported extension never reaches the worker; dispatch returns with zero copy/index/summarize side effects) |
| `test-upload-size-policy.R` | PASS (per-file semantics, `shiny.maxRequestSize` derivation, browser guard checks each file) |
| `test-maintainability-ratchet.R` | PASS (score 100/100, max file 778 lines / 24 functions unchanged) |
| `smoke_app_boot.R`, `parse_sanity_check.R`, `seam_doctor.R` | PASS |
| soak `interactive_file_ingestion` check | Added to the interactive lane; runs real copy + user-bucket isolation per session |

Not proven here: real UNC/network-share copy latency, Windows short-path/Turkish
path behavior under load, real multi-user SSO concurrency, and actual
event-loop responsiveness of a second browser session during a large batch.
Those remain Windows VM gates.

### 2026-07-11 — Fast-lane startup: preview `tracked_future_promise()` synchronous dependency scan blocked the critical path

Field report (Windows VM, Hızlı Başlangıç, three login attempts, cumulative
`[STARTUP PERF]` checkpoint times from session start):

| Checkpoint | Cold (attempt 1) | Warm refresh (attempt 2) | Warm refresh (attempt 3) |
|---|---:|---:|---:|
| `file_index_ready` (deferred) | 9,960 ms | 2,785 ms | 2,472 ms |
| `auth_ready` | 9,964 ms | 2,789 ms | 2,476 ms |
| `character_media_ready` (deferred) | 12,742 ms | 3,145 ms | 2,787 ms |
| `saved_chats_full_loaded` (deferred=TRUE) | 24,299 ms | 12,235 ms | 11,529 ms |
| `saved_chats_preview_ready` (deferred=TRUE) | 27,385 ms | 14,325 ms | 13,595 ms |
| `welcome_client_ready` | 27,908 ms | 14,473 ms | 13,740 ms |

The ~9-14 s gap between `character_media_ready` and the `saved_chats_full_loaded`
"deferred" marker, plus a `Registered S3 method overwritten by 'quantmod'` warning
appearing inside that gap, were the signature.

Root cause (proven by reading the wrapper, not by wall-clock alone): the fast-lane
branch DID call `tracked_future_promise(load_chats_preview_from_db, …)` for the
6-chat preview, but `tracked_future_promise()` performed substantial **synchronous**
work on the main event loop *before* dispatch — `future::getGlobalsAndPackages()`
over the task body, then a **recursive** `codetools::findGlobals()` walk of
`.GlobalEnv` (`worker_monitor_collect_nested_globals()`), `mget()`-ing every
referenced global function and expanding *their* globals in turn. As the app's
`.GlobalEnv` grew (chartlab/highcharter helpers, MCP tools, DB layer, Ortak Oturum),
this scan reached functions whose globals resolution force-loaded the **highcharter**
namespace, which registers `quantmod`'s `as.zoo.data.frame` S3 method → the stray
warning, on the fast-lane critical path. The late `saved_chats_full_loaded deferred=TRUE`
timestamp therefore did **not** mean the full list loaded; it revealed the preview
future's *scheduling/export* overhead. (`file_index_ready`'s ~10 s cold timestamp is
separately just cumulative pre-first-flush server wiring — it is already `deferred=TRUE`
and does no scan; a new `[STARTUP PERF] first_flush elapsed_ms=…` line now isolates that
phase.)

Architecture chosen (all additive, Rich Lane untouched):

1. **Explicit dependency mode for `tracked_future_promise()`** (`R/helpers_worker_monitor.R`).
   New `dependency_mode = c("auto","explicit")` + `packages` param. `"auto"` is the
   unchanged default for every existing LLM/SSE/image/TTS/Ortak-Oturum caller (the
   scan + nested expansion still run). `"explicit"` skips *all* auto-detection and
   re-binds the task function's environment to an isolated env containing only the
   supplied globals (so observer/session closure chains are never serialized to the
   worker). Auto-scan/expand are now named helpers
   (`worker_monitor_detect_task_deps`, `worker_monitor_expand_function_globals`) so a
   test can prove explicit mode never calls them.
2. **Lean startup preview worker** (`R/helpers_startup_chat_preview.R`, new; in the
   `database` manifest section). `db_chat_preview_fetch_raw()` runs on the worker with
   a **narrow contract** (DBI/odbc + the pure `db_chat_preview_query_sql` only; opens
   its own connection, closes on every path, never runs if the user id is invalid).
   Turkish visible-text normalization stays in the **main** process
   (`db_chat_preview_format_frame()`, byte-aligned with `load_chats_preview_from_db`'s
   list shape) so the central encoding contract is untouched. `mergen_startup_chat_preview_promise()`
   dispatches via explicit mode with a 7-symbol export set.
3. **Preview hydration deferred past first render** (`R/server_observers_startup.R`).
   Fast lane now marks `saved_chats_preview_ready` as `deferred=TRUE` *immediately*
   and starts the real dispatch only on `input$welcome_client_ready` (idempotent; a
   `~10 s` `later::later` safety timer covers the case where the client signal never
   arrives — the fallback never re-enters required readiness). Real hydration reports a
   **separate** `saved_chats_preview_hydrated` checkpoint (because `bootReadinessInit()`
   only logs a key's *first* occurrence, reusing one key for both "deferred" and
   "loaded" would hide the real completion). Full-list deferral renamed to
   `saved_chats_full_deferred`; `saved_chats_full_loaded` now fires only on genuine
   completion.

Why safe: fast-lane closing contract unchanged (`connect + auth_ready +
welcome_client_ready`); DB queries stay user-filtered in SQL; all prior race/isolation
protections kept (stale/late preview cannot overwrite a local mutation or a started
full list; closed-session callbacks are ignored; identity is re-resolved at hydration
time; invalid ids never query; preview dispatch/reject failures degrade to a warning
and never hold the overlay open). No global cross-user cache introduced. The
quantmod/zoo warning is removed from the startup path by **eliminating the unnecessary
dependency scan**, not by suppressing the warning (highcharter still loads lazily when a
chart is actually rendered).

What is / is not part of fast-lane readiness now: **in** = `connect`, `auth_ready`,
`welcome_client_ready`. **out (deferred, background)** = saved-chat preview hydration,
full saved-chat list, file index, image gallery, character/cinematic media.

Validation (cloud, `LC_ALL=C.UTF-8` — no real LLM/DB/browser/VM here):
`test-startup-observers-runtime-smoke.R` (69), `test-startup-chat-preview-behavior.R`
(34, new), `test-worker-monitor.R` (15), `test-boot-readiness-behavior.R` (36),
`test-startup-lane-contract.R` (158), `test-startup-lane-resolver-behavior.R` (42),
`test-source-manifest-sections-contract.R` (158), `test-source-manifest-contract.R`
(169), `test-global-source-manifest-contract.R` (12), `test-maintainability-ratchet.R`,
`test-seam-registry-contract.R`, `test-true-streaming-worker-globals-contract.R`,
`test-sse-worker-export-contract.R`, `test-db-refactor-contract.R` — all 0 fail /
0 warn. App boot smoke PASS; parse sanity 945 files OK.

**VM re-check result (2026-07-11 operator console screenshots):** the requested
Hızlı Başlangıç rerun now shows the expected improvement, without replacing the
pre-fix diagnostic table above. The first server-start + first-user run reaches the
deferred readiness band at about **13.0 s** and then logs `welcome_client_ready` at
**15.6 s**; already-running-server refresh/login runs log `welcome_client_ready` at
**3.1-3.6 s**. The measured checkpoint rows were:

| Checkpoint | First server-start + first user | Warm run 1 | Warm run 2 |
|---|---:|---:|---:|
| `first_flush` | 8,105 ms | 1,730 ms | 1,824 ms |
| `file_index_ready` (deferred) | 10,147 ms | 2,865 ms | 2,303 ms |
| `auth_ready` | 10,152 ms | 2,869 ms | 2,307 ms |
| `character_media_ready` (deferred) | 13,002 ms | 3,204 ms | 2,656 ms |
| `saved_chats_preview_ready` (deferred=TRUE) | 13,010 ms | 3,214 ms | 2,663 ms |
| `saved_chats_full_deferred` (deferred=TRUE) | 13,012 ms | 3,217 ms | 2,665 ms |
| `welcome_client_ready` | 15,588 ms | 3,605 ms | 3,057 ms |
| `saved_chats_preview_hydrated` | 16,410 ms | 3,771 ms | 3,187 ms |

Interpretation: the ~13 s value is the deferred-readiness checkpoint band from the
operator observation, not the overlay-close checkpoint. The stricter
`welcome_client_ready` value remains the engineering/user-interaction readiness point
and was **15.6 s** in this first server-start + first-user log; warm runs reached that
same checkpoint in **3.1-3.6 s**. Fake/GET-only soak evidence is **not** browser
startup evidence and is not claimed here.

### 2026-07-09 — Fast-lane startup regression: saved-chat load raced lane resolution

Field report: with Hızlı Başlangıç selected, startup still took ~34 s and the
`[STARTUP PERF]` summary contained `saved_chats_full_loaded=25396 ms` — a fast-lane
contract violation.

Root cause (race): `load_initial_saved_chats()` fired on `sso_state$authenticated`
(SSO) or synchronously at server init (local), while the lane only reached the server
later via the `startup_lane_resolved` client round-trip. With the first-boot lane
selector open (or always, in local mode) the server did not know the lane yet, assumed
rich lane, and started the synchronous preview plus the background FULL saved-chat
load anyway. `character_media_ready` deferral arrived only when the user finally
clicked the selector card.

Fix (`R/server_observers_startup.R` + `R/module_startup_lane.R` bridge):

- Saved-chat startup decisions are now gated on lane resolution: no saved-chat DB call
  starts before the `startup_lane_resolved` payload arrives (decision reads the payload
  directly; the racy `session$userData$startup_lane` read is gone).
- Fast lane: the full list is never loaded at startup (lazy, once, on first Kayıtlı
  Söyleşiler / Söyleşi Geçmişi open); the 6-chat preview no longer blocks the critical
  path — it runs in a `tracked_future_promise` worker (`startup_saved_chats_preview`).
- Rich lane keeps the existing behavior (sync preview + background full load).
- The lazy full load re-resolves the effective user id at run time; invalid ids never
  load. Clients without the lane API get a `legacy_no_api` rich_lane bridge signal so
  the gate can never deadlock. Fast-lane closing contract unchanged
  (`connect + auth_ready + welcome_client_ready`); DB queries stay user-filtered in SQL.

Also fixed the Windows VM full-suite `W` warning flood: running tests in a session that
had run the app leaves `global.R`'s `options(encoding = "UTF-8")` active; on a CP1254
native code page every test `readLines(..., encoding = "UTF-8")` then double-decodes and
each `grepl()` warns once per Turkish line (repo files are valid UTF-8; unrelated to the
recent commits). `tests/testthat/helper_bootstrap.R` now pins the test run to
`native.enc`; guarded by `test-testthat-encoding-guard-contract.R`.

Validation (cloud): startup smoke/lane/contract/source-manifest/production/boot-welcome
suites 0 fail / 0 warn; parse sanity 935 files OK. VM re-check: fast-lane
`[STARTUP PERF]` must show `saved_chats_full_loaded` only as `deferred=TRUE`.

### 2026-07-04 — Cold-start critical path + interaction hotspots (single instance, single port)

Baseline evidence for this session: the full VM evidence gate passed immediately before
this work (`artifacts/vm-evidence/20260704-085658/evidence.json`, **13 passed / 0 failed /
0 skipped**, `full_testthat` 3647.7 s, `browser_ux_smoke` 233.8 s PASS with
`MERGEN_BROWSER_UX_BASE_URL` attach mode, `vm_preflight_real` + `db_encoding_preflight`
PASS). That gate must be re-run on the VM after this session's changes.

Root causes found (file:line evidence, all synchronous work on the single Shiny event
loop during session boot, which also explains why fast lane stalled at the old
"Dosyalar hazırlanıyor" stage — the overlay was waiting for `welcome_client_ready`,
whose round-trip was queued behind these observers):

1. **Persisted file scan at boot** — `R/module_file_manager.R` `observeEvent(TRUE)` /
   `refresh_persisted_files("auth_ready")` ran `refresh_from_user_folder()` synchronously:
   index load + 5-6 filesystem stats per file (`path_exists_relaxed`, `file.exists`,
   `fs::file_exists`, `fs::file_info`, then `process_uploaded_file`'s own checks) —
   expensive on UNC shares even for 5 small files.
2. **Image gallery eager scan + hidden render** — `R/module_image_gallery.R` scanned
   `user_images` and ran `load_image_descriptions_for_user()` (an **N+1** DB query:
   one "next AI message" query per image) at session start, and
   `outputOptions(gallery_content, suspendWhenHidden = FALSE)` forced the FULL gallery
   grid (base64 of every image on the page) to render into the boot websocket payload
   before the gallery was ever opened.
3. **"Yeni Söyleşi" triple render + full-list DB query** — welcome was built up to 3×
   (insert in `chat_start_new_chat`, full re-render in `start_new_chat`, third delayed
   re-render in `chatUIObserversInit` after 300 ms) with a synchronous
   `load_chats_from_db(include_messages = FALSE)` (ALL chats) in the middle.
4. **First-token latency** included persistent-worker package cold load
   (jsonlite/curl/httr/DBI load on first future per worker).

Fixes (all preserve UX/features; lazy, not removed):

- Lazy persisted file inventory (both lanes): startup triggers only mark
  `file_index_ready` with `detail=list(deferred=TRUE)`; the real scan runs on first
  Dosya Yönetimi open (`file_manager_module-page_opened` from the navigation observer)
  or manual/tool triggers. Overlay stage label renamed to the truthful
  "Dosyalar gerektiğinde yüklenecek".
- Lazy gallery activation (`gallery_activated`), `suspendWhenHidden` back to default
  TRUE for `gallery_content`, and the descriptions N+1 collapsed into ONE correlated
  query (`SonrakiYanit` subselect; behavior contract preserved: next-AI-answer wins
  over inline description).
- Yeni Söyleşi: single authoritative welcome render; the full-list query replaced by
  `load_chats_preview_from_db(limit = 6)` merged into the in-memory list (welcome
  recent-top-3 recency invariant preserved; messages kept when already hydrated).
- Truthful toasts: immediate "Söyleşi yükleniyor..." on saved-chat click; success toast
  is sent AFTER the content insert messages (client processes in order). Gallery
  navigate already had a loading state; timing logs added to both.
- `prewarm_future_workers_once()` (`R/utils_rate_limiter.R`, called once from
  `global.R` after `init_future_cluster()`): dispatches one tiny package-load task per
  persistent worker so the first real prompt does not pay worker package cold start.
  No-op under `MERGEN_DISABLE_FUTURES=true`.
- Instrumentation: `[STARTUP PERF] checkpoint=<key> elapsed_ms=<t> deferred=<flag>` per
  boot checkpoint (`R/module_boot_readiness.R`), scan duration in the file-manager
  refresh log, gallery scan duration, saved-chat/gallery load duration, Yeni Söyleşi
  duration. Existing `[CHAT PERF]` markers (`future_promise gönderiliyor`, worker's
  first raw HTTP chunk, `İlk delta`, first UI shell) remain the way to split
  app-side vs upstream (gateway/proxy buffering) first-token/thinking-burst latency:
  if the worker's first raw chunk is late while dispatch was fast, the delay is
  upstream and cannot be fixed app-side (documented limitation).

Honesty/scope: no capacity number is claimed; these are event-loop/critical-path and
perceived-latency fixes for the current single-instance single-port (8009) deployment.
Cloud validation covered focused behavior/contract tests (0 fail / 0 warn) and
whole-repo parse sanity (909 files); actual cold-start seconds and first-token deltas
must be measured on the VM via the new `[STARTUP PERF]` / `[CHAT PERF]` lines, and the
VM evidence gate must be re-run.

### 2026-06-29 — Phase 3 (cont.): streaming event-loop hardening + 450-user proxy/interactive ladder

Motivation (file:line evidence): the long split-proxy soak (2026-06-27/28) failed its
capacity gate dominated by **connection timeouts** and `loadgen_loop_lag_high`, i.e.
the single Shiny/httpuv event loop saturates under many concurrent sessions. The fresh
2026-06-29 ladder (proxy lane, GET-only HTTP, in-process interactive) PASSES to 450
users but shows the same signature: throughput collapses 7566→1874/min past 300 users
and p95 climbs to ~14 s while **CPU stays at 21–31 %** — serialization on one event
loop, not CPU exhaustion.

Changes (all additive; default behavior byte-for-byte preserved unless an env flag is
set). New pure/runtime helpers `R/helpers_streaming_io.R` and
`R/helpers_stream_load_control.R` (both in the `chat_send_message_runtime` manifest
section), wired into `R/server_handler_true_streaming.R` and `R/server_send_message.R`:

1. **Incremental stream-file reading.** The true-streaming poll observer no longer
   `readLines()`-es the whole `stream_env$stream_file` every poll. `mergen_stream_read_new_lines(path, state)`
   tracks a byte offset + partial-line raw buffer and returns only newly appended
   complete lines (dedup via `processed_line_count`; UTF-8/NUL/invalid-byte tolerant;
   truncation/read-error → safe full-read fallback). This removes the
   grows-with-the-answer per-poll cost on the event loop.
2. **Adaptive poll backoff** (`MERGEN_STREAM_POLL_IDLE_BACKOFF`, default OFF). When
   enabled, idle polls back off `min→max` by a factor and reset to `min` on any new
   delta. Reduces event-loop wakeups for many concurrent idle streams. Default OFF =
   fixed interval (current behavior).
3. **Broader delta transport** (`MERGEN_STREAM_DELTA_DEFAULT`, default OFF;
   `MERGEN_STREAM_FULL_UPDATE_LEGACY` to force legacy). Avoids resending the full
   accumulated answer per delta for long answers. Default preserves current per-profile
   behavior.
4. **Follow-up throttle / kill-switch** (`MERGEN_FOLLOWUPS_ENABLED`,
   `MERGEN_MAX_CONCURRENT_FOLLOWUPS`, `MERGEN_DISABLE_FOLLOWUPS_UNDER_BACKPRESSURE`,
   `MERGEN_FOLLOWUP_DELAY_SECONDS`). The post-answer follow-up LLM round-trip (already
   off the critical path) is now admission-controlled via a `followups` backpressure
   kind and can be skipped under load or disabled globally — without blocking
   finalization. Default = enabled + unlimited + delay 0 (current behavior).
5. **Saved-chats refresh debounce** (`MERGEN_SAVED_CHATS_REFRESH_DEBOUNCE_MS`, default
   0 = immediate). Coalesces repeated `saved_chats_data$refresh()` per session into one
   timer. Default 0 preserves current immediate refresh.
6. **Per-operation backpressure kinds.** `send_message` now resolves the admission
   `kind` from the tool family (`sql_analysis`/`mcp_excel`/`summarization` get their own
   `MERGEN_MAX_CONCURRENT_*` pools; everything else shares `llm`) and acquires the slot
   **after** the tool family is known. Limits default 0 (OFF) → no-op, so heavy ops
   cannot starve plain chat once limits are set, and a rejection in one kind does not
   reject another.
7. **Defensive stream/reasoning size caps** (`MERGEN_MAX_STREAM_CHARS`=120000,
   `MERGEN_MAX_REASONING_CHARS`=80000). Finalized answer/reasoning are truncated at a
   UTF-8 character boundary (Turkish/emoji safe) with a polite Turkish note and a
   counter; `<=0` disables. Normal responses are far below the cap and unchanged.
8. **Secret-safe counters.** New numeric-only runtime counters surface on `/readyz`
   via the existing snapshot: `stream_poll_file_read_calls/fallback/bytes`,
   `stream_poll_idle_backoff_count`, `stream_poll_delta_reset_count`,
   `stream_text_truncated`, `stream_reasoning_truncated`, `followups_*`,
   `saved_chats_refresh_*`, plus the existing `backpressure_reject_*`.

Honesty / scope: these are event-loop/streaming **hardening** changes. They do not, by
themselves, raise the GET-only index-serving soak envelope (that lever remains
per-request index serialization + horizontal serving), and they claim **no** new
capacity number. The 450-user ladder above is proxy + GET-only + interactive evidence
only. The app remains constrained to app ports **8009 and 8008** until IT opens more
ports; the recommended next validation is a load-balanced URL over **only 8009 + 8008**
with the knobs in the table below enabled, plus the still-pending real-LLM / browser /
SQL-Server gates.

### 2026-06-19 — Phase 3 (perceived responsiveness): follow-up generation moved off the chat critical path

Problem (file:line evidence): after the model finished, follow-up suggestion
generation ran **before** the answer was finalized/rendered, and
`build_followup_suggestions()` (`R/helpers_followup_questions.R:210`) calls
`generate_ai_followups()` → `call_local_llm()` (`R/helpers_followup_questions.R:146`),
a **synchronous LLM round-trip on the main R thread**.

- Streaming path (`R/server_handler_true_streaming.R`): `build_followup_suggestions()`
  was called in the poll observer **before** `finalize_stream_message()`. Because
  `session$sendCustomMessage("finalizeStreamingMessage", ...)` only flushes at the end
  of the reactive cycle, the streamed answer stayed visually "streaming" (action buttons
  hidden, code blocks unrendered) for the entire follow-up LLM call after the model had
  already stopped producing text.
- Non-streaming path (`R/server_llm_response_handlers.R`): the same call ran **before**
  `add_message_fn()` rendered/persisted the message, so the **whole** answer was withheld
  from the UI for the follow-up LLM duration (worse than streaming). This is the TTS-on /
  MCP / non-streaming-model lane.

Fix (both paths, identical pattern): finalize/render the answer immediately with
`followups = NULL`, then generate the suggestions and `push_followup_update()` from a
non-blocking `later(delay = 0)` callback. This is the contract-supported deferred path:
the browser `updateFollowupSuggestions` handler creates `followup_container_<id>` on
demand by locating `message_wrapper_<id>` → `.ai-message`
(`www/js/shiny_message_handlers.js:152-169`), so the bubble can finalize before the
chips arrive. The deterministic/default follow-up baseline and the
`build_followup_suggestions()` builder itself are unchanged.

Expected effect: the answer appears "complete" (final markdown, action buttons, copy/
TTS affordances) the moment the model stops, instead of waiting an extra
follow-up-LLM round-trip. The model's own generation time (~10–16 s non-thinking,
~29 s+ thinking) is upstream and **unchanged** — this only removes a post-generation
stall that was attributed to the app.

Diagnostics added (default OFF; `MERGEN_PERF_LOG=1`, secret-redacted, grep-friendly):
`[PERF] event=stream.first_delta` (model TTFT), `[PERF] event=stream.followups` and
`[PERF] event=nonstream.followups` (follow-up generation time, now proven to be off the
critical path). These sit alongside the existing always-on `[CHAT PERF]` milestones.

Cloud validation (this session, `LC_ALL=C.UTF-8`): all listed contract/behavior tests
PASS (0 fail / 0 warn). `logger` is not installed in the cloud checkout, so the
`logger`-dependent logging behavior tests and full app boot were **not** runnable here
(environment limitation, not a code regression).

VM validation still required (cannot be done from cloud — no real LLM endpoint):

```powershell
$env:MERGEN_PERF_LOG="1"
& "C:\MergenLauncher\start_mergen_prod.bat"
# Root page (should stay warm-cached):
curl.exe -w "%{time_total}`n" -o NUL -s http://127.0.0.1:8009/
```

Then send a short non-thinking prompt, a longer non-thinking prompt, and one thinking
prompt, and in `logs/mergen_YYYYMMDD.log`:

- confirm the answer's action buttons appear immediately when streaming text stops
  (no multi-second "frozen streaming" gap), and the follow-up chips appear a moment later;
- read `[PERF] event=stream.followups elapsed_ms=...` / `nonstream.followups` to quantify
  how many ms/seconds were moved off the critical path;
- read `[PERF] event=stream.first_delta elapsed_ms=...` for model TTFT;
- confirm Turkish text, code blocks, charts, saved-chat reload, and TTS still render
  correctly, and that follow-up chips are clickable.

### 2026-06-19 — Post-index-cache Windows VM observations (docs-only update)

Observed root-page timing changed from the pre-cache isolated `GET /` baseline of about
0.623-0.669 s (median about 0.64 s) to repeated warm-cache timings mostly around
0.006-0.008 s, with a first observed request of 0.014524 s. The VM log also showed
`[PERF] event=index_render elapsed_ms=740 cache=miss_build bytes=311206`, so the
cold index build remains roughly 740 ms while subsequent root-page requests are served
from cache. Reproduction command on the Windows VM:

```powershell
curl.exe -w "%{time_total}`n" -o NUL -s http://127.0.0.1:8009/
```

VM console observed post-cache soak values:

| Artifact path | Lane | Users / duration | Result | p95 | Throughput | Notes |
|---|---|---:|---|---:|---:|---|
| `artifacts/soak/20260619-204455/soak_evidence.json` | smoke/fake | 1000 / 30 s | PASS | 9427.6 ms | 8532.4/min | VM console observed; JSON not present in this checkout. |
| `artifacts/soak/20260619-204704/soak_evidence.json` | smoke/fake | 250 / 420 s | PASS | 1983.8 ms | 8016.8/min | VM console observed; JSON not present in this checkout. |
| `artifacts/soak/20260619-205535/soak_evidence.json` | smoke/fake | 1000 / 420 s | PASS | 8377.8 ms | 7931.4/min | Strongest sustained fake-lane observation; JSON not present in this checkout. |
| `artifacts/soak/20260619-210427/soak_evidence.json` | stress/proxy | final summary | PASS | 734.5 ms | 8029.2/min | VM console observed; JSON not present in this checkout. |

Guardrails were VM-console-observed as PASS for success rates, mojibake, encoding
roundtrip, key routing 5/5, cross-session key isolation, upload validation 7/7,
secret leak 0, server crash, and temp growth 0.31 MB. `memory_growth_mb` and
`browser_console_errors` remained UNMEASURED. Real-chat PERF evidence remains separate:
DB open was observed around 60-230 ms, DB close usually 0-20 ms, while non-thinking
model response time remained dominated by upstream model/SSE latency around 10-16 s.
This optimization materially improves GET `/` and the operational fake/proxy soak path;
it does not prove real LLM/model generation became faster or that DB pooling is
unnecessary forever.

### 2026-06-19 — Phase 1 (cont.): soak HTTP-lane bottleneck attribution (analysis only, no code change, no capacity claim)

Goal of this slice: before implementing any fix, pin down **what the headline soak
number actually measures**, because the leading fix candidate (DB pooling, Phase 3.5)
and the soak metric may not be measuring the same path.

Request-path map for the fake/smoke lane (file:line evidence):

- The load driver targets the **app URL**, not the mock LLM:
  `run_operational_soak_gate.R:235` `load_url <- cfg$app_url`. The mock LLM
  (`mock_llm_server.R`) only feeds the app's LLM dependency; it is not the load target.
- For an app-root URL the driver runs in **GET mode**:
  `soak_client.R:86` `app_http_mode <- !grepl("/v1/chat/completions/?$", url)` and
  `soak_client.R:108-110` set `httpget = TRUE`. So each request is a plain
  `GET /?_soak_user=...&_soak_scenario=...&_soak_t=...`.
- The app has **no `_soak_*` request handler** (repo-wide grep is empty), so those
  query params are ignored.
- `ui` is a **static object built once** (`ui.R:7` `ui <- dashboardPage(...)`), passed
  as `shiny::shinyApp(ui = ui, ...)` (`app.R:145-152`); `onStart` runs once, not per
  request. There is no custom per-request httpuv handler.

Conclusion (high confidence, static): the fake/smoke HTTP lane measures **single-threaded
httpuv index-page serving** — Shiny re-serializes the large static `dashboardPage` tag
tree to HTML on **every** GET. It does **not** open a websocket Shiny session and therefore
does **not** exercise the server function, chat send, streaming, or the DB write path
(`finalize_stream_message()` / `get_connection()`), which only run on a real session.
(The soak doc already states the matching limitation: it does not prove websocket Shiny
session concurrency — `docs/operational-soak-gate.md` §10/§12.)

Latency math agrees with index-serving saturation, not DB serialization:

- 22 users / 300 s = 408 requests → 1.36 req/s sustained → ~735 ms of single-thread CPU
  per GET. With 22 in flight on one thread, expected closed-loop latency ≈ 22 × 0.735 ≈
  16.2 s, matching the observed p50 ≈ 17.0 s and p95 ≈ 18.4 s.
- The 22→24 behaviour is a classic single-server saturation **cliff**: at 22 the offered
  load ≈ the service rate (high but stable latency, 0 timeouts in 300 s); at 24 the offered
  load exceeds the service rate, the queue grows unboundedly, and the 20 s client timeout
  trips (24/300 s → 334 timeouts). The non-monotonic 25/30 s PASS vs 24/300 s FAIL is the
  expected "short run doesn't saturate / long run does" signature of a cliff, not real
  headroom at 25.

Implication for the fix plan (important):

- **DB connection pooling (Phase 3.5) will not move this specific soak number**, because
  the GET-only lane never touches the DB path. Pooling remains the right, high-leverage fix
  for **real chat throughput** (websocket sessions running `finalize_stream_message()`), and
  that work/justification is unchanged — but it should not be expected to raise the
  24-user **soak** envelope.
- The lever that *would* move the soak HTTP-lane envelope is reducing **per-request index
  serialization cost** on the single R thread (e.g., serving a memoized pre-rendered index
  HTML so each GET is a byte-copy instead of a full `htmltools` re-serialization, or
  trimming what is inlined per render), and/or **multi-process serving** behind a load
  balancer (infra). Any index-HTML caching change is Shiny-internals- and SSO-sensitive and
  must be VM-measured; it was **not** attempted blind from this cloud session.

Why no code change this session: a blind, unmeasured change to the UI-serving or DB path
would violate the workstream's own honesty rules and the task constraints ("carefully
tested change", "do not implement [pooling] blind from cloud", "do not claim success
unless measured"). This cloud session cannot run the soak (no running app at
`MERGEN_SOAK_APP_URL`; heavy runtime packages unavailable), so it produced **no soak
artifact and makes no capacity claim**.

VM measurement recipe to confirm the attribution cheaply (no code change required):

1. With the app running, time an **isolated** single GET of the index:
   `curl -s -o /dev/null -w "%{time_total}\n" "http://127.0.0.1:8009/"` a few times.
   If a single, uncontended GET already costs on the order of ~0.7 s, index serialization
   is confirmed as the soak-lane bottleneck (DB is not involved in this path).
2. Cross-check against a real session: open the app in a browser, send one message with
   `MERGEN_PERF_LOG=1`, and read the `[PERF] db.connection_open/close` + `[CHAT PERF]`
   lines. That quantifies the *chat/DB* path separately (the Phase 3.5 target), keeping the
   two bottlenecks from being conflated.

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
- DB connection pooling (Phase 3.5) is now **implemented and offline-tested** (transaction-safe, opt-in via `MERGEN_DB_POOL_ENABLED`, default OFF). It has **not yet been enabled/validated on the production VM against SQL Server**: enabling it there requires re-running `run_vm_encoding_preflight_real.R` (Turkish at-rest writes through the pooled connection), confirming `MB_Messages`/`MB_Chats` rows are clean in SSMS, and re-running the attach soak boundary to measure the real-chat capacity delta. `worker_save_assistant_response()` intentionally still uses a direct `worker_db_connect()` (workers run in separate processes where no pool exists), so its transaction path is unchanged.
- The global maintainability ratchet sits exactly at its cap (`server_send_message.R` = 694 ≤ 694). Any further line addition to that file will fail the ratchet; new send-message work must extract a helper first. Note the send-message-specific ratchet allows up to 760, so this is purely the global "largest file" cap.
- Real-canary ERR-234 remains an upstream gateway/admin policy blocker and should stay separate from app-capacity testing.
- The follow-up deferral moves the synchronous follow-up `call_local_llm()` round-trip into a `later(delay = 0)` callback. It is now **off the answer's critical path** (the answer finalizes first), but it still runs on the main R thread, so it briefly occupies the event loop for that session *after* the answer is shown. This does not increase total main-thread work versus before; it only reorders it so the answer paints first. A future improvement could run follow-up generation in a tracked future worker, but that is not required for the perceived-latency win and was intentionally not attempted blind from cloud.
- The new `[PERF]` streaming markers (`stream.first_delta`, `stream.followups`, `nonstream.followups`) are default OFF; they are diagnostics only and add no overhead unless `MERGEN_PERF_LOG=1`.

## Next recommended step

First, separate the two bottlenecks (they are not the same path — see the
"soak HTTP-lane bottleneck attribution" session note):

- **To move the 24-user soak number** (GET-only index-serving lane): on the VM, time an
  isolated single `GET /` (`curl -w "%{time_total}"`). If it is ~0.7 s uncontended, the
  lever is per-request index serialization (memoize a pre-rendered index HTML, or trim what
  is inlined per render) and/or multi-process serving — *not* DB pooling. Re-run the soak
  boundary at 24/26 users only after such a change, and do not weaken any threshold.
- **To improve real chat throughput** (websocket sessions, the DB write path): proceed with
  the DB-pooling profiling below. This is valuable on its own merits but is not expected to
  raise the GET-only soak envelope.

On the production VM (running app), run an attach-mode fake-lane boundary probe with `MERGEN_PERF_LOG=1` at 20, 23, and 24 users:

1. Sum the new `[PERF] event=db.connection_open` / `db.connection_close` lines per request to quantify how much main-event-loop time is spent purely on ODBC connect/disconnect (vs query and LLM time). Cross-check against the send-message segment timers (`send_message.prepare_chat/prompt_plan/file_context/mcp_prepare`) and the existing `[CHAT PERF]` milestones.
2. If connection overhead is confirmed as a large share at 23–24 users, prototype **transaction-safe** connection pooling (Phase 3.5): create a `pool::dbPool` at server startup, route `get_connection()` to it, and convert the transaction sites (`save_message_to_db`, `worker_save_assistant_response`) to `poolCheckout`/`poolWithTransaction`. Validate on the VM with the DB encoding preflight (`run_vm_encoding_preflight_real.R`, `MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST=TRUE`) + SSMS Turkish-encoding spot checks, then re-run the soak boundary probe at 24/26/28 users to measure the capacity delta. Do not weaken any soak threshold.
3. Re-introduce the dropped send-message cumulative milestones only if room is made by a real helper extraction (the file is at the 694 cap).

### Streaming event-loop hardening knobs (2026-06-29)

These are **documented, not hardcoded** validation settings. Defaults preserve current
behavior; set them to opt into the new event-loop levers. The app remains constrained to
app ports **8009 and 8008** until IT opens more ports — do not assume or recommend any
other port. The next capacity validation should be a load-balanced URL over **only
8009 + 8008**; it does not prove 1000 real users, real LLM throughput, real
browser/websocket concurrency, or SQL Server at-rest correctness.

```
MERGEN_APP_PORTS=8009,8008
MERGEN_FUTURE_WORKERS=2
MERGEN_DB_POOL_ENABLED=TRUE
MERGEN_DB_POOL_FAIL_FAST=TRUE
MERGEN_DB_POOL_MIN_SIZE=1
MERGEN_DB_POOL_MAX_SIZE=8
MERGEN_MAX_CONCURRENT_LLM=50
MERGEN_MAX_CONCURRENT_SQL_ANALYSIS=10
MERGEN_MAX_CONCURRENT_MCP_EXCEL=8
MERGEN_MAX_CONCURRENT_SUMMARIZATION=10
MERGEN_MAX_CONCURRENT_FOLLOWUPS=5
MERGEN_BACKPRESSURE_TTL_SECONDS=300
MERGEN_STREAM_POLL_IDLE_BACKOFF=true
MERGEN_STREAM_POLL_MIN_MS=25
MERGEN_STREAM_POLL_MAX_MS=250
MERGEN_STREAM_POLL_BACKOFF_FACTOR=1.5
MERGEN_STREAM_DELTA_DEFAULT=true
MERGEN_FOLLOWUP_DELAY_SECONDS=1
MERGEN_DISABLE_FOLLOWUPS_UNDER_BACKPRESSURE=true
MERGEN_SAVED_CHATS_REFRESH_DEBOUNCE_MS=1000
MERGEN_MAX_STREAM_CHARS=120000
MERGEN_MAX_REASONING_CHARS=80000
```

| Knob | Default | Effect when set |
|---|---|---|
| `MERGEN_STREAM_POLL_IDLE_BACKOFF` | `false` (fixed interval) | Idle stream polls back off `MIN→MAX` by `FACTOR`, reset to `MIN` on new delta — fewer event-loop wakeups under many concurrent idle streams. Trade-off: finalization of an idle, just-resolved stream can lag up to `MAX_MS`. |
| `MERGEN_STREAM_DELTA_DEFAULT` | `false` (per-profile) | Prefer incremental `streamingDelta` for all true-streaming, not just fast profiles. `MERGEN_STREAM_FULL_UPDATE_LEGACY=true` forces the old full-accumulated update. Finalize always sends the full final HTML once. |
| `MERGEN_FOLLOWUPS_ENABLED` | `true` | Global kill-switch for post-answer follow-up generation. |
| `MERGEN_MAX_CONCURRENT_FOLLOWUPS` | `0` (off) | Caps concurrent follow-up LLM round-trips (`followups` backpressure kind). With `MERGEN_DISABLE_FOLLOWUPS_UNDER_BACKPRESSURE=true`, follow-ups are skipped (not queued) past the cap. |
| `MERGEN_FOLLOWUP_DELAY_SECONDS` | `0` | Extra defer before follow-up generation fires. |
| `MERGEN_SAVED_CHATS_REFRESH_DEBOUNCE_MS` | `0` (immediate) | Coalesces per-session saved-chats refreshes into one timer. |
| `MERGEN_MAX_CONCURRENT_{LLM,SQL_ANALYSIS,MCP_EXCEL,SUMMARIZATION}` | `0` (off) | Per-operation admission limits resolved from tool family; rejection returns a friendly "server busy" toast without breaking stop/cancel. |
| `MERGEN_MAX_STREAM_CHARS` / `MERGEN_MAX_REASONING_CHARS` | `120000` / `80000` | Defensive UTF-8-safe truncation of finalized answer/reasoning; `<=0` disables. |

Rollback: unset the new env flags to return to previous behavior. None of these change
runtime behavior at their defaults.

## 2026-07 — Production-safe MB_* SQL Server indexing rollout

A production-safe MB_* indexing rollout was completed in four waves after an initial unsafe all-at-once attempt caused login failure. The original script is superseded and must not be recommended. It applied many indexes together and included a newly-created `UNIQUE` login-path candidate on `MB_Users(KullaniciAdi)`; after that attempt, users could not log in and logs did not show a clear error. All newly-created indexes were rolled back and login recovered. The outage is documented as likely caused by unsafe all-at-once deployment / schema-locking / overly aggressive unique login-path index attempt; root cause not conclusively proven.

The final stable set uses wave-by-wave manual application, no destructive statements, and no new unique indexes. `IX_MB_Feedback_User_Message` and `IX_MB_Users_KullaniciAdi_Lookup` are intentionally non-unique. Production metadata also shows a pre-existing unique `MB_Users(KullaniciAdi)` constraint/index named like `UQ__MB_Users__5BAE6A75C24F52F9`; the safe explicit performance index exists alongside it and does not replace or alter it.

Observed validation after Wave 1-4:

- The app starts with `start_mergen_prod.bat`.
- Users can log in.
- Admin pages' first click and first content load are visibly faster.
- Metadata checks confirmed the new indexes exist and are enabled.
- Representative `SET STATISTICS IO ON; SET STATISTICS TIME ON;` admin list checks were cheap in the current database and matched the observed UI improvement. Because the support/admin tables are currently small, these results do **not** prove index seek usage or future large-table behavior.

| Representative query | Observed rows | Scan count | Logical reads | Physical reads | Read-ahead reads | CPU | Elapsed |
|---|---:|---:|---:|---:|---:|---:|---:|
| `SELECT TOP 100 ... FROM dbo.MB_Destek_Hata_Bildir hb ORDER BY hb.OlusturmaTarihi DESC` | 20 | 1 | 3 | 0 | 0 | 0 ms | 0 ms |
| `SELECT TOP 100 ... FROM dbo.MB_Destek_Geri_Bildirim gb ORDER BY gb.OlusturmaTarihi DESC` | 16 | 1 | 3 | 0 | 0 | 0 ms | 0 ms |

Capacity wording: these indexes help DB-heavy paths, chat/message hydration, login/profile lookup, support feedback lookup, and admin first-click latency. They should not be presented as proof of higher real-user, browser, websocket, or real-LLM capacity. GET-only soak lanes may not change much because the historical GET-only path primarily exercises root/index serving rather than the SQL Server query paths.

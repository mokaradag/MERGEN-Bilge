# Proje ve Kaynak Analizi — Rebuild Progress

**Purpose.** This file carries the *reasoning*; git carries the *code*. A session that
reads only one of the two will make avoidable mistakes.

**Work order:** [`docs/proje-kaynak-analizi-master-plan.md`](../docs/proje-kaynak-analizi-master-plan.md)
**Integration branch:** `pk/rebuild` (base for every phase PR; `main` stays frozen)

---

## Phases merged into `pk/rebuild`, in order

| # | Phase | Status | Merge SHA on `pk/rebuild` |
|---|---|---|---|
| 0 | Instrumentation + status plumbing | `in_review` | — (PR open) |

Planned order (§11): **0 → 3a → 1 → 2 → 4 → 5 → 6**, with **3b on the VM**.

> A session must not start phase N+1 while phase N is still `in_review`.
> Before starting, run `git fetch origin pk/rebuild && git log --oneline -8 origin/pk/rebuild`
> and cross-check this table against the log. **Trust the log**, and record any discrepancy.

---

## Phase 0 — Instrumentation + status plumbing

* **Status:** `in_review`
* **Branch:** `pk/phase-0-telemetry`
* **PR:** base `pk/rebuild` ← head `pk/phase-0-telemetry` (see PR link in the repo)
* **Merge SHA:** _pending_

### Defects re-verified before writing code (§0.1)

Line numbers had drifted; each was re-read in the current checkout.

| Defect | Verdict | Evidence in current code |
|---|---|---|
| **D9** — filter-LLM timeout is indistinguishable from "no filter needed" | **REPRODUCES** | `R/helpers_pk_analysis_filters.R` had **9 distinct return paths** (pre-LLM stop, pre-call stop, LLM error/timeout, post-call stop, empty content, `nchar < 50`, no-JSON, parse failure, all-filters-invalid, outer handler) all returning the byte-identical `list(filters = list(), aggregation = NULL)` — the same value the success path returns when the model legitimately produces no filter. `filter_timeout <- 8` was at line 169. |
| **D4** — a zero-match filter is reported as "no data" | **REPRODUCES** | Zero-row branch returned only *"Filtreleme sonrası veri bulunamadı"* with no cause. |
| **D21** — `data = secure_data` is a dead pre-filter payload | **REPRODUCES** | Still returned; still unread by `R/server_send_message.R`. Left untouched (Phase 2 owns it). |
| **D15** — synchronous execution on the event loop | **REPRODUCES** | `pk_analiz_process_request` still called directly at `R/server_send_message.R`. Phase 6 owns it. |

No claim from the plan was found to be withdrawn. Nothing in §3.9 was resurrected.

### Files added

| File | Purpose |
|---|---|
| `R/helpers_pk_config.R` | Config resolver. Precedence **query metadata → env → `options()` → default**. Worker-safe (`Sys.getenv()` inline). |
| `R/helpers_pk_provenance.R` | Typed filter statuses, degradation records, user-visible provenance footer, request-scoped footer slot + idempotent decorator. Pure. |
| `R/helpers_pk_telemetry_record.R` | **Pure** telemetry-record layer: question normalization, keyed fingerprint, field clipping, row assembly, DB encoding normalization. |
| `R/helpers_pk_telemetry.R` | **DB** layer: once-per-process readiness detection, fail-soft write, `pk_analysis_observe()` entry point. |
| `docs/sql/2026-08-pk-analiz-log.sql` | Idempotent `MB_Analiz_Log` DDL. Manual DBA apply, never at startup, no destructive statement. |
| `docs/sql/2026-08-pk-analiz-log-rollback.sql` | Separate destructive rollback script. |

### Files modified

| File | Change |
|---|---|
| `R/helpers_pk_analysis_filters.R` | Every empty-result return now carries a **typed `status`**. `filters`/`aggregation` shape and content unchanged. |
| `R/module_proje_kaynak_analizi.R` | Observation at three exits (RLS-zero, filter-zero, success); zero-row message now names the degradation cause. |
| `R/helpers_send_message_model_runtime.R` | Per-request provenance slot reset (see design decision D3). |
| `R/server_handler_true_streaming.R`, `R/server_llm_response_handlers.R`, `R/helpers_chat_runtime.R` | Footer attachment at the three answer-finalization seams. |
| `R/config_source_manifest.R` | Four new files at the head of `analysis_helpers`, in dependency order. |
| `.Renviron.example` | Five Phase-0 knobs with Turkish comments. |
| `tests/testthat/test-source-manifest-sections-contract.R` | Frozen anchors updated (required by CLAUDE.md in the same change): `analysis_helpers` n 5→9, first file, total 367→371. |

### Tests added, and what each **proves**

| Test | Proves |
|---|---|
| `test-pk-config-resolver-behavior.R` (31) | Full precedence chain incl. metadata > env > options > default; invalid/out-of-enum values fall through silently rather than being accepted; Turkish logical spellings; unknown key **errors** instead of inventing a default; resolver works in a clean worker-like env from `Sys.getenv` alone; secret snapshot never emits the raw key. |
| `test-pk-telemetry-failsoft-contract.R` (42) | **The core test.** Missing `MB_Analiz_Log` → tool fully functional, no error thrown, footer still produced; readiness detected **once per process** (proved behaviorally: creating the table afterwards does *not* flip the cached answer); warning logged **once**, not per request; INSERT error never propagates and is logged once; disabled/NULL-conn paths skip cleanly; with the table present a row is really written with Turkish round-trip intact. |
| `test-pk-telemetry-privacy-contract.R` (26) | With `MERGEN_PK_LOG_QUESTION_TEXT=false` the raw question reaches **no column**; the fingerprint equals an independently computed **HMAC-SHA256** and is *not* the unkeyed digest; different keys → different fingerprints; **no key → no fingerprint at all**; the key itself never lands in the row; arbitrary caller fields (DSN/API-key shaped) never enter the record. |
| `test-pk-provenance-footer-behavior.R` (53) | Footer never shows the pre-RLS count for a scoped user — **even if `pre_rls_rows` is passed into the builder** (structural guarantee); an ADMIN whose scope is the whole set *does* see the full number; footer names query id/name, filters and degradations; filter values cannot break markdown structure; take-once/stale-request-id/idempotency of attachment. |
| `test-pk-degradation-disclosure-contract.R` (36) | `ok_no_filter`, `timeout` and `error` are **three distinct** statuses from the real adapter driven by a stubbed LLM; `malformed` covers four separate bad-response shapes; the timeout reaches the **user-visible answer text**; `filters`/`aggregation`/`group_column`/`filter_expression` contract is unchanged (observation-only); static proof that all three finalization seams decorate, and that the TTS path decorates **after** `tts_engine(full_response, …)` so the footer is never spoken. |

Total: **188 new assertions**, all offline — no DB, LLM, browser, network or real secret.
Real SQLite (`RSQLite`, in-memory) is used for the telemetry tests, per the repo precedent
`test-ortak-oturum-db-behavior.R`.

### Design decisions, with reasoning

**D1 — The footer is attached to the answer *content*, at three finalization seams, not rendered by the model.**
The plan requires an R-owned footer, but for `sql_analysis` the prose comes from the LLM
downstream of the module. There is no single answer-finalization funnel in this codebase, so
the decorator is called at exactly three places: `finalize_stream_message()` (true streaming),
`add_message_fn(result$content, …)` (non-streaming), and the `final_text` assignment inside
`chat_simulate_streaming()` (TTS). Attaching to *content* rather than to rendered HTML also
means the footer is persisted in `MB_Messages.MessageContent`, so a reloaded saved chat still
shows provenance. Each call site is `exists()`-guarded and degrades to a no-op.

**D2 — In the TTS path the footer must not be spoken.**
`chat_simulate_streaming()` calls `tts_engine(full_response, tts_voice)` *before* the streaming
loop finalizes. Decorating `full_response` (or `res$content` in
`R/server_handler_streaming_tts.R`) would have made the assistant read the footer aloud.
Decorating the local `final_text` inside the finalization block instead reaches display and
persistence only. A static ordering assertion in the disclosure test locks this in.

**D3 — The per-request slot reset lives in `mergen_build_send_message_request_callbacks()`, not in `server_send_message.R`.**
The footer is known *before* the LLM runs and consumed *after* it finishes, so it needs a
request-scoped slot. Clearing at request start is what stops a stale footer attaching to a later
answer. `R/server_send_message.R` had exactly **1 line** of ratchet headroom (633 actual vs 634
budget), and CLAUDE.md forbids raising budgets. `mergen_build_send_message_request_callbacks()`
receives both `session` and `req_id` and runs exactly once per request, which makes it the
correct lifecycle seam anyway. Cost there: 7 lines, well inside that file's budget.

**D4 — Staleness trade-off is deliberate: a missing footer is safe, a wrong footer is not.**
The slot is cleared at every request start and consumed on read, and `pk_provenance_take()`
additionally rejects a request-id mismatch. A late-finishing older request can therefore lose
its footer. That is the intended direction of failure.

**D5 — `MERGEN_PK_FILTER_TIMEOUT_SEC` is deliberately NOT implemented in Phase 0.**
§9 gives it a default of `20`; v1 currently hard-codes `8`. Registering it with default 20 would
change which filters v1 applies (fewer timeouts → more filters), and §8/§10 assign D9's *fix* to
v2. Registering it with default 8 would contradict the plan's table. So Phase 0 leaves the
timeout untouched and only adds the typed status. **Phase 1 owns this knob.**

**D6 — Added three statuses beyond the plan's `no_filter`/`timeout`/`error`/`malformed`.**
`stopped` (user cancelled), `disabled` (`disable_ai_filters = TRUE`) and `not_reached` (analysis
never got to the filter stage, e.g. zero rows after RLS). Recording any of those as
`ok_no_filter` would assert the model ran and produced no filter — a claim Phase 0 cannot make
(§8: *"Phase 0 does not claim telemetry for a state it cannot observe"*). None is treated as a
degradation.

**D7 — `helpers_pk_telemetry.R` was split into a pure record layer + a DB layer.**
The single file hit **28** function expressions against the global ceiling of 24 (the naive
scanner counts anonymous `function(e)` handlers). Rather than raise the budget, the pure half
moved to `R/helpers_pk_telemetry_record.R`. This is a better boundary regardless: it lets the
privacy decision be proven without a database. Result: 100/100, max functions 24.

**D8 — Turkish thousands grouping is done manually, not with `format`/`formatC`.**
Turkish uses `.` as the thousands separator, which collides with R's default `decimal.mark`;
`prettyNum` then emits *"'big.mark' and 'decimal.mark' are both '.'"*, and the strict suite runs
`stop_on_warning = TRUE`. Both `format()` and `formatC()` route through `prettyNum`. The manual
regex grouping is also independent of `getOption("OutDec")`, which matters given the repo's
locale-sensitivity rules.

**D9 — `utils::modifyList()` is avoided for list-valued fields.**
It merges *recursively by name*, so `modifyList(base, list(filters = list()))` silently keeps
`base$filters` instead of overriding it, and unnamed lists (like the degradation list) are
dropped. This was caught by a failing test and fixed in both production (`pk_analysis_observe`,
`pk_observe`) and test helpers. Worth remembering — it is an easy silent-wrong-value trap.

**D10 — Telemetry reuses the caller's DB connection; it never opens its own.**
`pk_telemetry_log_analysis(info, conn)` takes the connection the module already holds. Opening a
second connection for an observation-only feature would add pool pressure to exactly the path
Phase 6 is trying to make non-blocking.

### Deviations from the plan

Only D5 and D6 above, both argued there. Everything else follows §5.11, §9, §10 and §13 as
written. No maintainability budget was raised; no v1 filter/selection decision was changed.

### Review findings received and how each was resolved

None yet — PR just opened.

### What remains unproven and needs the VM

* `MB_Analiz_Log` DDL applied against real SQL Server (only idempotency-by-construction and
  SQLite-shaped writes are proven here).
* Turkish at-rest values in `MB_Analiz_Log` under `DB_CLIENT_ENCODING=WINDOWS-1254`
  (`normalize_db_visible_value` / `normalize_db_technical_value` are exercised only when loaded).
* The fail-soft path against a **real ODBC** connection where the missing table surfaces as a
  driver error rather than an RSQLite error.
* The footer actually rendering in the three real answer paths (browser).
* Real filter-LLM timeout classification against the on-prem endpoint — the `timeout` vs `error`
  split is matched on the error message, which is proven here only against synthetic messages.
* Whether the observed `filter_status` distribution justifies Phase 1's timeout change.

### Exact validation commands run, and their real results

Environment note: this container starts in a **POSIX/C locale**, which makes R fail to read the
repo's UTF-8 sources. All commands below were run with `LC_ALL=C.utf8 LANG=C.utf8`.

| Command | Result |
|---|---|
| `source("tests/scripts/parse_sanity_check.R", encoding = "UTF-8")` | `OK: 1043 dosya parse edildi.` |
| 5 new Phase-0 test files | `pass=188 fail=0 warn=0 skip=0` |
| All `test-pk-*` / `test-deep-*` / manifest / seam / ratchet / production / secret files (32 files) | `pass=1256 fail=0 warn=0 skip=0` |
| Broader touched-area run (60 files incl. send-message, streaming, stale-request races, frontend selectors) | `pass=2053 fail=0 warn=0 skip=0` |
| `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")` | `pass=270 fail=0 warn=0` |
| `source("tests/scripts/maintainability_report.R", encoding = "UTF-8")` | Skor **100/100**, 25+ fonksiyon dosya sayısı **0**, en yüksek fonksiyon sayısı **24**, en büyük dosya 795 satır |
| `bash tools/seam_doctor.sh` | `SEAM_DOCTOR_RESULT: OK (yapısal sorun yok)` |
| `bash tools/ai_validate.sh quick` | **PASSED** — `failed_steps: 0`, `skipped_steps: 0`. Artifact: `artifacts/ai-validation/20260802-164539/summary.json` |
| `bash tools/ai_validate.sh full --boot-smoke` | **PASSED** — `failed_steps: 0`, `skipped_steps: 0`. Artifact: `artifacts/ai-validation/20260802-164655/summary.json` |

`full --boot-smoke` proof fields (verbatim from `summary.json`):

```
validation_execution_status: ran_by_ai_repo_check
profile_requested: full          profile_effective: full
failed_steps: 0                  skipped_steps: 0
app_source_smoke_status:      passed
full_testthat_suite_status:   passed      (301.0s, zero failures)
shiny_boot_smoke_status:      passed
browser_smoke_status:         skipped     <-- no Chrome/Chromium/Edge binary in this container
db_sso_vm_validation_status:  not_performed_by_ai_validate
sql_server_turkish_encoding_preflight_status: not_performed_by_ai_validate
manual_fragile_flow_evidence_status:          not_performed_by_ai_validate
```

**Honesty boundary.** The mandatory `full --boot-smoke` gate for this phase **did run and did
pass**, including app source smoke, the full testthat suite and Shiny boot smoke. Browser UX
smoke **SKIPPED** (no browser binary — the runner exits 0 on that skip by design, so it is *not*
browser proof). Nothing here proves runtime, VM, SSO, real DB, SQL Server Turkish encoding, or
browser behavior; those remain the VM gates listed in §14 of the plan.

Full-suite skips seen in the run are pre-existing and unrelated to this phase: `{highcharter}`
is not installed in this container.

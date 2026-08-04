# Proje ve Kaynak Analizi — Rebuild Progress

**Purpose.** This file carries the *reasoning*; git carries the *code*. A session that
reads only one of the two will make avoidable mistakes.

**Work order:** [`docs/proje-kaynak-analizi-master-plan.md`](../docs/proje-kaynak-analizi-master-plan.md)
**Integration branch:** `pk/rebuild` (base for every phase PR; `main` stays frozen)

---

## Phases merged into `pk/rebuild`, in order

| # | Phase | Status | Merge SHA on `pk/rebuild` |
|---|---|---|---|
| 0 | Instrumentation + status plumbing | `merged_to_rebuild` | `b1805f5` (PR #695) |
| 3a | Metadata contract | `merged_to_rebuild` | `aa39652` (PR #696) |
| 1 | Surgical correctness | `merged_to_rebuild` | `f1368b2` (PR #697) |
| 2 | Deterministic analysis + export | `in_review` | — (PR open) |

Planned order (§11): **0 → 3a → 1 → 2 → 4 → 5 → 6**, with **3b on the VM**.

> A session must not start phase N+1 while phase N is still `in_review`.
> Before starting, run `git fetch origin pk/rebuild && git log --oneline -8 origin/pk/rebuild`
> and cross-check this table against the log. **Trust the log**, and record any discrepancy.

---

## Phase 0 — Instrumentation + status plumbing

* **Status:** `merged_to_rebuild`
* **Branch:** `pk/phase-0-telemetry`
* **PR:** #695, base `pk/rebuild` ← head `pk/phase-0-telemetry` — **merged**
* **Merge SHA:** `b1805f5` (merge commit on `pk/rebuild`)

> **Stale-record correction (made at the start of the Phase-3a session).** This
> section previously read `in_review` / `_pending_`. `git log --oneline -8
> origin/pk/rebuild` shows `b1805f5 Merge pull request #695 from
> mokaradag/pk/phase-0-telemetry` at the tip, so Phase 0 was already merged. Per
> §11 ("trust the log, and record any discrepancy") the log wins and the table
> above was corrected. This is exactly the inconsistency that rule exists to
> catch: without the cross-check, this session would have refused to start
> Phase 3a on the grounds that Phase 0 was still `in_review`.

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

---

## Phase 3a — Metadata contract

* **Status:** `merged_to_rebuild`
* **Branch:** `claude/pk-phase-3a-metadata-5nf9m1` (see "Deviations" — the branch
  name is the session's assigned branch, not `pk/phase-3a-metadata`; it is cut
  from the same `origin/pk/rebuild` tip `b1805f5`)
* **PR:** #696, base `pk/rebuild` ← head `claude/pk-phase-3a-metadata-5nf9m1` — **merged**
* **Merge SHA:** `aa39652` (merge commit on `pk/rebuild`)

> **Stale-record correction (made at the start of the Phase-1 session).** This
> section previously read `in_review` / `_pending_`, and the phase table listed
> Phase 3a as `in_review`. `git log --oneline -8 origin/pk/rebuild` shows
> `aa39652 Merge pull request #696 from mokaradag/claude/pk-phase-3a-metadata-5nf9m1`
> at the tip, so Phase 3a was already merged. Per §11 ("trust the log, and record
> any discrepancy") the log wins and both the table and this section were
> corrected. **This is the second consecutive phase in which the record was left
> stale**; the same cross-check caught it both times. A session that skipped the
> cross-check would have refused to start Phase 1 on the grounds that Phase 3a
> was still `in_review`.

### Claims re-verified before writing code (§0.1)

Phase 3a is a *contract* phase, so the relevant re-verification is of the plan's
structural claims rather than of runtime defects.

| Plan claim | Verdict | Evidence in the current checkout |
|---|---|---|
| `R/library_queries.R` ships only placeholder queries | **HOLDS** | 4 entries: `q001`, `q002`, `q003`, `q_ornek_id`. Production has ~169. This is why `pk_query_meta` ships **empty** — see design decision M2. |
| `R/config_sql_loader.R` is the merge point and is a top-level script | **HOLDS** | 397 lines of top-level code ending in an `rm()` cleanup; it `stop()`s under `.SQL_LOADER_STRICT`. This is what forced the merge/validation logic into pure helper files (M1). |
| `chartr()`/code-point folding is not viable | **HOLDS, re-measured** | `stringi::stri_trans_tolower(x, locale = "tr")` produced byte-identical output under `LC_ALL=C`, `C.UTF-8` and `tr_TR.UTF-8`. Measured additionally: NFC alone does **not** normalize a *lowercase* `i` + U+0307, so the helper strips that mark explicitly (M3). |
| the manifest already supports `optional` paths | **HOLDS, but incomplete** | The mechanism exists (`source_manifest_optional_source_groups`), but it emits a loud per-boot "layer DISABLED" `message()`. That is correct for `codex_hardening` and wrong for files whose absence is by design (M4). |

Nothing in the plan was found to be withdrawn.

### Files added

| File | Purpose |
|---|---|
| `R/helpers_pk_text_turkish.R` | `pk_tr_fold()` — minimal, NFC-normalizing, locale-independent Turkish fold + `pk_tr_fold_is_blank()`. Pure. Loaded **before** every metadata layer. |
| `R/helpers_pk_query_meta_schema.R` | Contract vocabulary (`PK_META_ROLES`, `..._AGGREGATES`, `..._MATCH_MODES`, `..._PERCENT_SCALES`, `..._CAPABILITY_ROLES`, `..._ALIAS_PROVENANCE`) + schema-independent validators for the capability registry, a single column, and an alias map. Pure; returns error strings, never `stop()`s. |
| `R/helpers_pk_query_meta_access.R` | Tier-0 structural inference, the **named** Tier-0 fallback record, consumer accessors, the pre-SQL capability gate, and the mandatory post-fetch actual-column validation. Pure. |
| `R/helpers_pk_query_meta.R` | Layer merge (curated wins), alias-only local overlay, query-level/cross-column validation, schema-dependent validation, tracked-alias audit, and the single `stop()`-owning entry point `pk_query_meta_attach()`. Pure. |
| `R/library_query_meta_auto.R` | Committed **empty** scaffold so the Tier-0 boot path works in a fresh checkout. Never populated in Git. |
| `R/library_query_meta.R` | Curated layer: the capability registry (populated with the plan's six baseline IDs) and `pk_query_meta` — deliberately **empty**, see M2. |
| `tests/testthat/test-pk-text-turkish-behavior.R` | 36 assertions. |
| `tests/testthat/test-pk-query-meta-contract.R` | 145 assertions. |

Not added, by design: `R/library_query_meta_local.R` and
`R/library_query_aliases_local.R`. These are **gitignored, VM-only** and their
absence in a cloud checkout is the contract, not a defect.

### Files modified

| File | Change |
|---|---|
| `R/config_source_manifest.R` | New `pk_query_metadata` section (8 files) placed immediately **before** `sql_library`, in the §6-mandated order. Both local layers registered as optional single-member groups, plus the new `source_manifest_expected_absent_source_groups`. |
| `R/bootstrap_source_manifest.R` | `source_manifest_expected_absent_groups()` added; `source_manifest_present_paths()` now iterates groups **by name** and suppresses the "layer DISABLED" message for expected-absent groups only (M4). |
| `R/config_seam_registry.R` | `pk_query_metadata` assigned to the `mcp_analiz` seam; two new guard tests + one focused-validation command registered. |
| `R/config_sql_loader.R` | Calls `pk_query_meta_attach(query_library)` after SQL loading, **outside** the `.SQL_LOADER_STRICT` branch (M5). |
| `R/helpers_pk_config.R` | Registers `MERGEN_PK_ROW_CAP` (integer, default `50000`, min 1) — the only §9 knob Phase 3a actually consumes (M6). |
| `.Renviron.example` | `MERGEN_PK_ROW_CAP` with a Turkish comment. |
| `.gitignore` | The two local metadata/alias layers, with the reasoning inline. |
| `tests/testthat/helper_source_manifest_contract.R` | New shared `source_manifest_sections_for_tests()` so section-internal order can be asserted without re-sourcing the manifest per test. |
| `tests/testthat/test-source-manifest-sections-contract.R` | Frozen anchors updated **consciously**: section order gains `pk_query_metadata`; new boundary anchor `first/last/n = 8`; total 373 → 381. |
| `tests/testthat/test-bootstrap-source-manifest-behavior.R` | Three new tests for the expected-absent behavior introduced in `R/bootstrap_source_manifest.R` (M4). |

### Tests added, and what each **proves**

| Test | Proves |
|---|---|
| `test-pk-text-turkish-behavior.R` (36) | `İ/I/ı/i` fold under Turkish rules (`KALIP → kalıp`, **not** `kalip`); composed `İ`, decomposed uppercase `I`+U+0307 and decomposed *lowercase* `i`+U+0307 all produce the **same** key; whitespace collapse; `NA` positions preserved; a **golden UTF-8 byte assertion** that catches locale drift anywhere it runs, including the VM; byte-identity across every `LC_COLLATE` this container can set; a static guard that `chartr()` has not returned and that `stri_trans_nfc` + `stri_trans_tolower(locale = "tr")` are still the implementation; and the Phase-3a **load-order** contract (fold helper first, four data layers in the §6 order, whole section before `config_sql_loader.R`). |
| `test-pk-query-meta-contract.R` (145) | **Capability registry:** unknown ID, role mismatch, unit mismatch, unstable ID shape, `id` as a capability role, and a unit on a dimension/date capability are each rejected; two columns exposing one capability require an explicit `capability_variants$prefer`, and the gate then names that column. **Schema-independent contract:** invalid `role`/`aggregate`/`match`, missing `percent_scale` when `unit = "%"`, fuzzy `match` on an `id` column, `weight_by` not naming a declared measure, `latest` without `latest_by` **and** `latest_tie_by`, `primary_entity`/`default_measures` pointing at undeclared (or non-measure) columns, and non-positive `row_cap` — each fails, and each fails **startup** through `pk_query_meta_attach()`. **Aliases:** keys are NFC-normalized and Turkish-folded (decomposed and composed forms collapse to one key); one folded alias mapping to two canonical values is a hard error while a same-value duplicate is deduped; wrong type and empty key/target rejected; the overlay writes **only** `aliases` and leaves `grain`/`primary_entity`/`capability`/`role`/`match` untouched; the overlay cannot target an unknown query id, an undeclared column, or an `id`/`exact` column unless a reviewed `allow_aliases = TRUE` opens it; an unapproved alias in the **tracked** file fails startup, while a `local_overlay` alias does not trip that audit. **Merge:** curated wins field-by-field, untouched lower-layer fields survive, and an intentionally emptied list field in the upper layer is **honored** (the `modifyList` trap from Phase-0 D9). **Schema present vs absent:** with a schema, a declared RLS column missing from it fails startup naming the D6 hole, and a role/type mismatch fails too; without a schema, `pending_no_schema` + `tier = 0` are recorded and the query still boots — and the *same* contract is then enforced unconditionally post-fetch, where a missing RLS column sets `fail_closed`. **Tier-0:** structural roles are inferred from class, but `capability` stays `NULL`, `match` is `none`, `filterable` is `FALSE`, `high_cardinality` is `NA` and the `id` role is **never** assigned — so a prefix sample cannot manufacture identifier/low-cardinality claims. **Capability gate:** a semantic requirement against a Tier-0 candidate returns `unknown_no_semantic_metadata` **before SQL**, an empty requirement set passes, and neither a raw column name (`KalanIscilik_sa`) nor an invented token (`iscilik`) can stand in for a capability ID. **Named fallbacks:** all 15 consumer fallbacks exist and are non-empty, and the behavior of the five load-bearing ones (`primary_entity`, `additive`, `match`, `filterable`, `row_cap`) is asserted directly. **Repo contract:** the tracked auto scaffold and `pk_query_meta` are empty, the tracked registry validates clean, both local layers are gitignored *and* manifest-optional *and* expected-absent, and the loader calls the contract outside the strict flag. |

| `test-bootstrap-source-manifest-behavior.R` (+7) | An expected-absent optional group is skipped **silently**; a normal optional group missing stays **loud** and names the file; and marking a group expected-absent does **not** change group atomicity — a two-member group with one missing member still drops both. This is what stops the new suppression from becoming a way to hide a genuinely broken working copy. |

Total: **188 new assertions**, all offline — no DB, LLM, browser, SSO, network or
real secret. Every fixture is synthetic (`SENTETIK PROJE A`, `q001`); no real
project or programme name appears anywhere in the tests.

**Mutation-checked.** Each new test was verified to actually fail when the fix it
guards is reverted, rather than merely being green:

| Reverted behavior | Result |
|---|---|
| `stri_trans_tolower(locale = "tr")` → plain `tolower()` | 6 failures |
| the `i`+U+0307 strip removed | 1 failure |
| `pk_query_meta_attach()` no longer `stop()`s | 4 failures |
| alias collision check disabled | 1 failure |
| Tier-0 `match = "none"` / `filterable = FALSE` loosened | 6 failures |
| capability gate always returns `ok` | 4 failures |
| expected-absent message suppression removed | 2 failures |
| `percent_scale` requirement removed | 1 failure |

### Design decisions, with reasoning

**M1 — Merge and validation live in pure helpers; `config_sql_loader.R` only calls them.**
The plan (§6) assigns the merge to the loader, and the loader *is* the call site.
But `R/config_sql_loader.R` is a 397-line top-level script that `rm()`s its own
helpers at the end and `stop()`s mid-file; logic placed there cannot be unit
tested without executing the whole loader, and the file has no ratchet headroom.
So the loader gained ~15 lines that call `pk_query_meta_attach()`, and every
decision it makes is a pure function in a sourced helper. The plan's constraint
("do not `source()` any of them ad hoc from the loader") is respected — all four
data layers and all three helpers are manifest-declared and seam-owned.

**M2 — `pk_query_meta` ships EMPTY; only the capability registry is populated.**
This is the single most important restraint in this phase. The checkout's four
queries are placeholders with ids (`q001`…) that almost certainly collide with
*different, real* queries on the VM. Writing plausible `grain`/`additive`/
`primary_entity` for `q001` here would silently bind invented semantics to a real
production query — precisely the "never invent query metadata" prohibition in
§11, and worse than having no metadata at all, because the Tier-0 gate would
stop guarding it. The registry *is* populated, with the six IDs the plan itself
specifies: those are stable semantic identifiers, contain no production names,
and are the vocabulary Phases 1/2 will write requirements against. An unknown
capability ID fails startup, so the operator extending the registry gets a clear
error rather than a silent miss.

**M3 — `pk_tr_fold()` strips U+0307 after `i`, and fails closed without `stringi`.**
Measured: NFC recomposes `I`+U+0307 into `İ` (so uppercase decomposed input folds
correctly on its own), but there is **no** precomposed form for lowercase
`i`+U+0307, so NFC leaves it and the two spellings of the same alias would
produce different keys — a silent alias miss. The helper therefore strips that
mark explicitly after folding. And when `stringi` is unavailable the helper
`stop()`s rather than falling back: a silently wrong fold corrupts alias keys
invisibly, which is the exact failure mode the plan forbids. `stringi` is already
a `required_packages` entry validated at startup, so this cannot fire in practice.

**M4 — "Expected absent" is a new, separate concept from "optional".**
The existing optional mechanism prints a per-boot
`[KAYNAK MANIFESTI] … katman DEVRE DISI` message. For `codex_hardening` that is
right: absence there means a broken working copy. For the two PK local layers it
is exactly backwards — absence is the **normal** state of every cloud and CI
checkout, and warning about it each boot would train operators to ignore the
message that does signal a real problem. So
`source_manifest_expected_absent_source_groups` suppresses the *message only*;
the files remain optional, still skipped when absent, and still loaded normally
when present.

**M5 — Metadata validation is deliberately NOT behind `.SQL_LOADER_STRICT`.**
§5.1 says "always fail the build" for schema-independent contract violations, and
that has to mean *always*. A non-strict loader run exists so a missing SQL file
degrades to a placeholder; degrading *invalid metadata* the same way would boot an
app that answers with the wrong grain or sums a non-additive measure. A test
asserts the call site is not nested under the strict flag, so a future edit cannot
quietly move it there.

**M6 — Only `MERGEN_PK_ROW_CAP` is registered, following Phase-0's D5 precedent.**
§9 lists ~40 knobs. Registering ones this phase does not consume would either be
dead configuration or, worse, change v1 behavior (Phase 0 hit this exactly with
`MERGEN_PK_FILTER_TIMEOUT_SEC`). `row_cap` is the one field the metadata layer
genuinely resolves, and it demonstrates the §9 precedence chain end to end,
because the per-query metadata field is literally named `row_cap` and therefore
overrides the global through the existing `pk_config_resolve()` machinery with no
special-casing.

**M7 — An alias for an unknown query id or undeclared column is a hard error.**
§5.1 names only collisions and (schema permitting) missing targets as hard
errors, so this is stricter than written. Rationale: the alternative is dropping
the alias silently, which means the operator believes an alias works when it does
not — the "silently wrong" failure the plan's corollary rules out. The file is
operator-maintained on their own machine, the message names the query/column, and
the fix is one line. Recorded here as a conscious tightening rather than an
oversight.

**M8 — `pk_meta_validate_actual_columns()` is defined and tested but NOT wired.**
§8's acceptance requires that a post-fetch actual-column mismatch always fails
closed. The function implements and proves that verdict. It is deliberately not
called from `pk_analiz_process_request()`: doing so would change v1 runtime
answers, and §10/§11 restrict v1 changes to four named cross-engine items, of
which unconditional RLS fail-closed belongs to **Phase 1**. Phase 3a is a pure
contract/data layer and changes no runtime behavior. **Phase 1 must wire this
function**; that is the one loose end this phase deliberately leaves.

**M9 — Three helper files rather than one.**
Splitting vocabulary/validators (302 lines), Tier-0 + accessors (333) and
merge/attach (493) keeps every file far below the 800-line / 25-function
ceilings without raising any budget, and — more usefully — lets the Tier-0
fallback decisions be tested without the merge machinery and vice versa.

### Deviations from the plan

1. **Branch name.** The plan says `pk/phase-3a-metadata`; this session's harness
   assigned `claude/pk-phase-3a-metadata-5nf9m1` and forbids pushing elsewhere.
   The substance of the rule is preserved: the branch is cut from the same
   `origin/pk/rebuild` tip (`b1805f5`), carries exactly one phase, and its PR
   targets `pk/rebuild`, never `main`.
2. **A new manifest section** (`pk_query_metadata`) rather than extending an
   existing one. §6 requires the fold helper and all four data layers to load
   before `config_sql_loader.R`, which sits in `sql_library` near the front of
   the manifest — far ahead of `analysis_helpers`, where the other PK helpers
   live. Putting them in `sql_library` would have handed them to the
   `veritabani_kodlama` seam; a dedicated section owned by `mcp_analiz` keeps
   ownership honest. The section is registered in the frozen order list, the
   seam registry and the boundary anchors in the same change.
3. **M7** (unknown alias id/column is fatal) is stricter than §5.1, argued above.
4. **M2/M8** are scope restraints, not disagreements with the plan.

Nothing else departs from §5.1, §6, §7, §9, §10 or §13. No maintainability budget
was raised; no v1 runtime behavior was changed.

### Review findings received and how each was resolved

None yet — PR just opened.

### What remains unproven and needs the VM

* **The generator has never run.** `R/library_query_meta_local.R` cannot exist in
  a cloud session, so the merge has only ever been exercised against synthetic
  layers. The three-layer merge against a *real* generated inventory is Phase 3b.
* **No real query metadata exists yet.** Every capability, `grain`, `additive`
  and `percent_scale` decision for the ~169 production queries is still to be
  made on the VM. Until then every production query boots at Tier-0 and any
  semantically-scoped request returns `unknown_no_semantic_metadata` — which is
  the designed behavior, but it means the gate's *usefulness* is unproven.
* **The alias overlay has never seen a real vocabulary.** Alias target validation
  against a closed vocabulary is written but only exercised against synthetic
  domains.
* **`schema_validation = "validated"` has never been reached with a real schema**,
  because no real `result_schema` exists in this checkout.
* **Turkish folding on the Windows VM.** The golden-byte assertion will detect
  drift there, but it has not yet been *run* under a real Turkish Windows locale.
* **`pk_meta_validate_actual_columns()` in a live request** — see M8; it is
  unwired by design and Phase 1 owns the wiring.
* The startup `stop()` path has been proven against synthetic invalid contracts,
  not against a genuinely malformed operator-authored file on the VM.

### Exact validation commands run, and their real results

Environment note: this container starts in a **POSIX/C locale**, which makes R
fail to read the repo's UTF-8 sources. Every command below was run with
`LC_ALL=C.UTF-8`.

| Command | Result |
|---|---|
| `Rscript tests/scripts/parse_sanity_check.R` | `OK: 1057 dosya parse edildi.` |
| `testthat::test_file("tests/testthat/test-pk-text-turkish-behavior.R")` | `FAIL 0, WARN 0, SKIP 0, PASS 36` |
| `testthat::test_file("tests/testthat/test-pk-query-meta-contract.R")` | `FAIL 0, WARN 0, SKIP 0, PASS 145` |
| `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")` | DONE, 0 failures |
| `testthat::test_file("tests/testthat/test-source-manifest-sections-contract.R")` | DONE, 0 failures |
| `testthat::test_file("tests/testthat/test-seam-registry-contract.R")` | DONE, 0 failures |
| `testthat::test_file("tests/testthat/test-source-manifest-contract.R")` | DONE, 0 failures |
| `testthat::test_file("tests/testthat/test-global-source-manifest-contract.R")` | DONE, 0 failures |
| `testthat::test_file("tests/testthat/test-bootstrap-source-manifest-behavior.R")` | DONE, 0 failures |
| `testthat::test_file("tests/testthat/test-seam-doctor-contract.R")` | DONE, 0 failures |
| `testthat::test_file("tests/testthat/test-pk-config-resolver-behavior.R")` | DONE, 0 failures |
| `bash tools/seam_doctor.sh` | `SEAM_DOCTOR_RESULT: OK (yapısal sorun yok)` |
| `source("tests/scripts/maintainability_report.R")` | Skor **100/100**; 800+ satır dosya **0**; 25+ fonksiyon dosya **0**; en büyük dosya **795** satır; en yüksek fonksiyon sayısı **24** — Faz 0 taban çizgisiyle aynı, hiçbir bütçe yükseltilmedi |
| manual app-source boot (`MERGEN_RUN_APP=false`, placeholder env) | `[SQL_LOADER] PK metadata sozlesmesi dogrulandi: 4 sorgu.` → `BOOT_OK`; `schema_validation=pending_no_schema`, `tier=0`, `row_cap=50000`, `pk_tr_fold("İSTANBUL PROJESI")="istanbul projesı"`, capability gate `unknown_no_semantic_metadata`; **no** optional-file warning noise |

#### `bash tools/ai_validate.sh full --boot-smoke` — **UNMET GATE (pre-existing failure, not Phase 3a)**

The mandatory gate was run twice on the final tree. It **FAILED**, and the
failure is **not caused by this phase**. Artifact:
`artifacts/ai-validation/20260803-111112/summary.json`.

```
validation_execution_status: ran_by_ai_repo_check
profile_requested: full          profile_effective: full
failed_steps: 1                  skipped_steps: 0
failed_step_labels:           ['full testthat suite']
app_source_smoke_status:      passed
full_testthat_suite_status:   failed
shiny_boot_smoke_status:      not_requested   <-- never reached; the run halts on the suite failure
browser_smoke_status:         not_requested
db_sso_vm_validation_status:                  not_performed_by_ai_validate
sql_server_turkish_encoding_preflight_status: not_performed_by_ai_validate
manual_fragile_flow_evidence_status:          not_performed_by_ai_validate
```

**The only two failures in the whole suite:**

```
1. Failure ('test-maintainability-ratchet-contract.R:277:3')
   Satır sayısı ratchet limitini aşan dosyalar: R/helpers_deep_analysis.R
2. Failure ('test-maintainability-ratchet-contract.R:286:3')
   Fonksiyon sayısı ratchet limitini aşan dosyalar: R/helpers_deep_analysis.R
```

**Proof that this is pre-existing.** A clean worktree was checked out at the
untouched `pk/rebuild` tip and the same test was run there with **none** of this
phase's changes present:

```
git worktree add /tmp/pkbase b1805f5
cd /tmp/pkbase && Rscript -e 'testthat::test_file("tests/testthat/test-maintainability-ratchet-contract.R")'
→ [ FAIL 2 | WARN 0 | SKIP 0 | PASS 1 ]   (byte-identical failure text)
```

**The numbers.** `tests/scripts/maintainability_report.R` reports
`R/helpers_deep_analysis.R` at **780 lines / 16 functions**. The ratchet baseline
for that file is **627 lines / 12 functions**, giving allowances of **659 lines**
(`+max(25, 5%)`) and **15 functions** (`+max(3, 10%)`). It is therefore **121
lines and 1 function over budget**. `git show b1805f5^1:R/helpers_deep_analysis.R`
is **626 lines**, so the growth came from Phase 0's per-query deep-analysis
instrumentation (`c8a6072 Instrument deep PK analysis per query`).

**This contradicts the Phase-0 record above**, which reports
`full --boot-smoke` **PASSED** with `failed_steps: 0`. Both statements cannot
describe the merged tree. The most likely explanation is that the Phase-0 gate
was run before its last commits landed and was not re-run afterwards. Flagging
it here rather than quietly repairing it, because it is Phase-0/Phase-1 territory:
the correct fix is to **split `R/helpers_deep_analysis.R`** (CLAUDE.md forbids
raising the budget), which is a real refactor of an analysis file this phase does
not own and must not smuggle into a metadata-contract PR.

**Consequence for this phase, stated plainly:** the mandatory
`full --boot-smoke` gate is **NOT MET**. Shiny boot smoke never executed, because
the runner halts on the suite failure. Per §11 this phase must be recorded as
*"full --boot-smoke NOT PASSED — a pre-existing `helpers_deep_analysis.R` ratchet
breach on `pk/rebuild` must be fixed, and the gate re-run, before this phase is
merged to main."* Nothing here should be described as fully validated.

**What the run does establish for Phase 3a.** Inside that same full-suite run,
every test this phase touches passed with zero failures, warnings and skips:

```
pk-text-turkish-behavior:            36 passed
pk-query-meta-contract:             145 passed
bootstrap-source-manifest-behavior:  23 passed
source-manifest-sections-contract:  all passed
seam-registry-contract:             all passed
```

and `app source smoke` (which loads the whole runtime source chain, including the
new `pk_query_metadata` section and the metadata contract validation) reported
**passed** in `7.7s`.

**Recommended next step for the operator (not done here):** fix the
`helpers_deep_analysis.R` breach as its own small PR into `pk/rebuild` — by
splitting the file, not by raising the budget — then re-run
`bash tools/ai_validate.sh full --boot-smoke`. Both this phase and Phase 0 should
be re-validated afterwards.

---

## Phase 3a — post-review fixes (independent review pass)

The Codex reviewer never ran on PR #696 (it replied "You have reached your Codex
usage limits for code reviews"), so no automated findings existed. The findings
below come from an independent review of the phase diff plus the base branch.

### 1 — Pre-existing ratchet breach fixed (was blocking the mandatory gate)

`R/helpers_deep_analysis.R` was **780 lines / 16 functions** against a ratchet
baseline of 627/12 (allowance 659/15). Reproduced on the untouched `pk/rebuild`
tip, so it was **not** introduced by Phase 3a — it came from Phase 0's
instrumentation commit. It was the ONLY thing failing the full suite (exactly two
failures), and it halted the runner before Shiny boot smoke could execute.

Fixed by **splitting**, never by raising the budget (CLAUDE.md forbids that):

| New file | Moved responsibility | Purity |
|---|---|---|
| `R/helpers_deep_analysis_detail.R` | `ANALYSIS_DETAIL_LEVELS`, `get_analysis_detail_config()`, `get_analysis_detail_instruction()` | pure |
| `R/helpers_deep_analysis_context.R` | `build_deep_analysis_context()` | pure |

`helpers_deep_analysis.R` keeps query selection, single-query execution and
`pk_deep_analysis_process()`, and drops to **595 lines / 13 functions**. Both new
files load in `analysis_helpers` BEFORE the orchestrator. Frozen counts updated in
the same change (`analysis_helpers` n 11 -> 13, total runtime 381 -> 383), as §6
requires. `test-deep-analysis-split-contract.R` freezes the split, the purity of
the two helpers, the manifest order and the post-split budget.

### 2 — Empty capability registry rejected the legitimate Tier-0 state (P1)

`pk_meta_validate_capability_registry(list())` returned an error, because
`names(list())` is `NULL` and the "must be a named list" branch fired. Every
sibling validator (`.pk_meta_validate_named_layer`, `.pk_meta_validate_rls_columns`)
accepts empty input; this one did not. Since `pk_query_meta_attach()` `stop()`s on
any finding and `.pk_meta_collect_layer()` falls back to `list()`, an
uncurated-yet registry — the documented Tier-0 / fresh-checkout state — was
**boot-fatal**. Fixed with the same early return the siblings use.

### 3 — Empty domain map rejected, inconsistently with aliases (P2)

`pk_meta_validate_domain_map(id, col, list())` errored for the same `names(NULL)`
reason, while the sibling field `aliases` explicitly accepts an empty map. A
column declaring `domain = list()` (declared, no mappings entered yet) aborted
boot. Fixed; the two fields now behave identically.

### 4 — RLS fail-closed verdict depended on whitespace (P2)

In `pk_meta_validate_actual_columns()`, `missing_rls` compared RLS column names
with `trimws()` but the duplicate-column collision test compared the **raw**
declared value. A declaration of `" ProjeKodu "` therefore did not match a
duplicated actual `ProjeKodu` column, and `fail_closed` stayed silently `FALSE` —
an ambiguous RLS column read as safe. §8 makes this verdict Phase 1's
unconditional gate, so the inconsistency was fixed now rather than inherited.
Both forms now produce the same verdict.

### 5 — Restored documentation deleted from `R/helpers_pk_config.R`

Phase 3a removed the file header rationale, the priority-chain step comments and
the roxygen blocks for `pk_config_resolve()` / `pk_config_safe_snapshot()` while
adding `MERGEN_PK_ROW_CAP`. No ratchet covers this file (144 lines, no budget), so
nothing forced the deletion. Restored verbatim, plus a comment for the new key.
Comment-only; behavior untouched.

### Reported, deliberately NOT changed

`.pk_meta_validate_query_library()` requires non-empty SQL for every library
entry, and `pk_query_meta_attach()` `stop()`s independently of
`MERGEN_SQL_LOADER_STRICT`. A query declaring neither `sql_file` nor `sql` is left
without SQL by the loader's non-strict path (unlike the read-error path, which
assigns a placeholder), so in non-strict mode — used by `smoke_app_boot.R`,
`run_ci_local.R` and several regression tests — boot now aborts with a
metadata-flavoured message for what is really a SQL-loader problem. This is
fail-closed, documented in `config_sql_loader.R`, and covered by an explicit test,
so it is recorded as a deliberate design decision rather than silently changed.

### Mutation checks

Every fix was verified to actually fail when reverted, not merely to be green:

| Reverted behavior | Result |
|---|---|
| empty-registry early return removed | 3 failures |
| empty-domain early return removed | 2 failures |
| RLS `trimws()` alignment removed | 1 failure |
| split moved back into the orchestrator | ratchet + split contract fail |

One of my own fixtures was wrong rather than the code: `"AYNI"` folds to `aynı`
(dotless ı) under Turkish rules and correctly does NOT collide with ASCII
`"Ayni"` -> `ayni`. The fixture now asserts both the real collision (`"Aynı"` /
`"AYNI"`) and the correct non-collision.

---

## Phase 1 — Surgical correctness

* **Status:** `merged_to_rebuild`
* **Branch:** `claude/pk-phase-1-surgical-correctness-o6e6sg` (see "Deviations" — the
  harness-assigned branch name, not `pk/phase-1-correctness`; it is cut from the
  `origin/pk/rebuild` tip `aa39652`, which matched the expected tip exactly)
* **PR:** #697, base `pk/rebuild` ← head `claude/pk-phase-1-surgical-correctness-o6e6sg`
  — **merged**
* **Merge SHA:** `f1368b2` (merge commit on `pk/rebuild`)

> **Stale-record correction (made at the start of the Phase-2 session).** This
> section and the header table read `in_review` / `_pending_`, but
> `git log --oneline -3 origin/pk/rebuild` shows
> `f1368b2 Merge pull request #697 from mokaradag/claude/pk-phase-1-surgical-correctness-o6e6sg`
> at the tip. Per §11 ("trust the log, and record any discrepancy") the log wins
> and both records were corrected. **This is the third consecutive phase whose
> record was left stale by the session that opened its PR** — the correction is
> cheap only because the cross-check is mandatory; the durable fix is to update
> this file at merge time, not at PR time.

### Defects re-verified before writing code (§0.1)

Line numbers had drifted; each was re-read in the current checkout. **Every claim
still reproduces.** Nothing in the plan was found to be withdrawn.

| Defect | Verdict | Evidence in the current code |
|---|---|---|
| **D1** same-column AND | **REPRODUCES** | `R/helpers_pk_analysis_filters.R` reassigns `dt <- dt[grepl(...), ]` per filter inside one loop; two `contains` leaves on one column intersect. |
| **D2** multi-value truncation | **REPRODUCES** | `val_str <- .pk_filter_observation_scalar(val)` returns `as.character(x)[1]`. |
| **D3** Turkish case | **REPRODUCES** | three `grepl(..., ignore.case = TRUE)` call sites for `exact_match`/`contains`/default. |
| **D4** zero-match | **REPRODUCES** | module returns only *"Filtreleme sonrası veri bulunamadı"*. |
| **D5** `eval(parse())` | **REPRODUCES** | `dt <- subset(dt, eval(parse(text = expr_str)))`. |
| **D6** RLS column | **REPRODUCES** | three `if (col_name %in% names(filtered_data))` guards silently skip; `if (yetki == "ADMIN")` errors on `NA`. |
| **D6b** role scope | **REPRODUCES** | `tryCatch(..., error = function(e) NULL)` **and** `if (nrow(user_rows) > 0)` both leave the scope `NULL`; `apply_rls_to_data` then skips the predicate. |
| **D7** budget | **REPRODUCES** | budget checked against `summary_parts` only; `preview_json` assembled afterwards in the module. |
| **D8** warning lost | **REPRODUCES** | the over-budget recursion passes only `max_preview_rows`/`max_total_chars`/`pre_aggregated_columns`. |
| **D9** silent degradation | **REPRODUCES** | `filter_timeout <- 8`; degraded status recorded (Phase 0) but the analysis still proceeds over the full set. |
| **D12** dead guard | **REPRODUCES** | condition requires `length(filters) == 0`, body assigns `filters <- list()`. |
| **D22** ODBC leak | **REPRODUCES** | `conditionMessage(e)` embedded in the user-visible message. |
| **D23** SQL gate | **REPRODUCES** | blocklist `\b(DELETE|DROP|TRUNCATE|ALTER)\b` plus a validator that **accepts** `INSERT|UPDATE|EXEC`; deep mode additionally uses locale-dependent `toupper()`. |

### Engine boundary as implemented

| Item | Gating | Where |
|---|---|---|
| D6 / D6b RLS fail-closed | **unconditional** | `R/helpers_pk_rls.R` + `apply_rls_to_data()` |
| D23 read-only SQL classifier | **unconditional** | `R/helpers_pk_sql_readonly.R`, called by module **and** deep mode |
| D22 ODBC redaction | **unconditional** | `R/helpers_pk_safe_errors.R` |
| M8 actual-column gate (RLS verdict) | **unconditional** | `pk_meta_actual_column_gate()` |
| D1 D2 D3 D4 D5 D7 D8 D9 D12 | `MERGEN_PK_ENGINE=v2` | compiler / policy / v2 executor / budget |

Three of those files are **statically proven** free of `MERGEN_PK_ENGINE` and
`pk_engine_is_v2` references, so a safety fix cannot be hidden behind the flag.

### Files added

| File | Purpose | Purity |
|---|---|---|
| `R/helpers_pk_sql_readonly.R` | D23 statement-aware, fail-closed read-only classifier: literal/comment/identifier masking, statement split (`;` + `GO`), forbidden keyword/prefix families, CTE terminal-statement check. | pure |
| `R/helpers_pk_safe_errors.R` | D22 redaction: unsafe-diagnostic detection, generic Turkish message, log-then-return helper. | pure |
| `R/helpers_pk_rls.R` | D6/D6b decision layer: `pk_rls_code_norm()`, collision guard, scope states, `pk_rls_plan()`, classed `pk_rls_stop()`, plus the M8 `pk_meta_actual_column_gate()`. | pure |
| `R/helpers_pk_filter_compile.R` | D1/D2/D3 compiler: OR-in-column, AND-across-column, AND for complementary bounds, NOT, multi-value, Turkish fold, no-op detection. | pure |
| `R/helpers_pk_filter_policy.R` | D4 zero-match policy (primary refuses / secondary drops with disclosure), D9 degraded gate, disclosure block. | pure |
| `R/helpers_pk_analysis_filters_v2.R` | v2 executor tying compiler+policy to the v1 return shape; carries the decision as an attribute. | pure |
| `R/helpers_pk_prompt_budget.R` | D7 whole-payload accountant + the single v1/v2 payload builder. | pure |
| `R/helpers_pk_analysis_prompts.R` | System prompt builder, moved **byte-identically** out of the module. | pure |
| `R/helpers_pk_statistical_summary.R` | `generate_statistical_summary()`, split out to hold the ≤400-line contract on the RLS file. | pure |

### Files modified

| File | Change |
|---|---|
| `R/module_proje_kaynak_analizi.R` | SQL gate before execution; redacted DB errors; M8 gate; RLS abort handling; v2 degraded gate + refusal; payload builder. **700 → 682 lines** (it shrank, per §6). |
| `R/helpers_pk_analysis_security_summary.R` | `get_user_rls_info()` records typed scope states; `apply_rls_to_data()` delegates to `pk_rls_plan()` and fails closed. **373 → 194 lines.** |
| `R/helpers_pk_statistical_summary.R` (new home) | D8: v2 recursion carries `mode`/`rls_total_rows`/`user_filter_applied`, and the basic-summary fallback keeps the warning. |
| `R/helpers_deep_analysis.R` | Same shared SQL gate (locale-dependent `toupper()` removed), M8 gate, RLS abort handling. |
| `R/helpers_pk_analysis_filters.R` | v2 dispatch in front of the untouched v1 body; observation contract preserved on both paths. |
| `R/helpers_pk_analysis_filters_base.R` | `MERGEN_PK_FILTER_TIMEOUT_SEC` consumed **only** under v2; v1 keeps its literal 8. |
| `R/helpers_pk_config.R` | New `double` type; three knobs; `pk_engine_mode()` / `pk_engine_is_v2()`. |
| `R/config_source_manifest.R` | Nine new files in `analysis_helpers`, dependency-ordered. |
| `.Renviron.example` | Three new knobs with Turkish comments stating they are v2-only. |
| `tests/.../test-source-manifest-sections-contract.R` | Frozen anchors updated consciously: `analysis_helpers` 13 → 22, total 383 → 392. |

### Tests added, and what each **proves**

| Test | Proves |
|---|---|
| `test-pk-sql-readonly-gate-contract.R` (72) | Single SELECT / CTE-SELECT / parenthesised UNION accepted; Turkish `[bracketed]` and `"quoted"` identifiers and `]]` escapes are **not** false positives; keywords inside literals, line comments and **nested** block comments are inert; `SELECT ... INTO`, data-modifying CTEs and all 14 write/DDL/DCL/backup/execute families rejected; `sp_`/`xp_` prefixes rejected; multi-statement and `GO` batches rejected **with the reason named**; unterminated literal/comment/identifier and unknown statements fail **closed**; the refusal message carries neither the SQL nor the table name; both the module and deep mode call the same gate; the old blocklist and the write-accepting validator are gone; the classifier is statically free of engine-flag references. |
| `test-pk-rls-failclosed-contract.R` (66) | Missing declared RLS column **aborts**, never skips; unavailable scope aborts, empty scope yields **zero** rows (never all), and a caller carrying no scope state falls to the safe side; `NA`/empty `Yetki` fails closed instead of erroring; ADMIN unchanged; a resolved-but-unenforceable scope is reported, not silent; `pk_rls_code_norm()` is minimal (no case folding, no suffix/punctuation handling) and statically does not use `pk_tr_fold`; the collision guard is proven to fire **when the normalizer is loosened** (the honest test, since the minimal normalizer cannot collide); the user message leaks no column/code/reason; M8 aborts unconditionally on an RLS mismatch while a non-RLS metadata mismatch aborts only under v2; both call sites are wired. |
| `test-pk-filter-compile-behavior.R` (25) | Two same-column `contains` return the **union** (v1 returned 0); cross-column stays AND; complementary date **and** numeric bounds stay AND on one column; multi-value vectors and JSON lists survive intact; `İSTANBUL`/`KALIP` fold under Turkish rules where `ignore.case` fails; exclusions, invalid leaves, no-op ratio on both sides of the threshold, zero-match provenance, empty inputs; and the fold helper **fails closed** rather than falling back to `tolower()`. |
| `test-pk-filter-policy-behavior.R` (51) | Primary zero-match **refuses** and names value + column, with no nearest-candidate text (Phase 4 owns that); secondary zero-match drops with disclosure while the primary filter still applies; primary resolution follows metadata → sole-leaf fallback → undetermined; degraded statuses refuse and say analysis was **not** run, while legitimate statuses do not; the `filter_expression` side-effect counter proves it is **never evaluated** in v2, and the source is free of `eval(parse(`/`subset(dt`; the dead D12 guard is absent; the v2 return shape matches v1 for list/count/sum/group_by/empty. |
| `test-pk-prompt-budget-behavior.R` (22) | The budget covers the **whole** payload (short summary + huge JSON is trimmed); an over-budget summary sends zero preview rows and discloses it; a fitting payload is untouched; v1 payload building is byte-shape unchanged and un-budgeted; v2 emits the budget note; D8 — the v2 recursion **keeps** `FİLTRELEME UYARISI` while v1 still loses it; the knob follows metadata → env → default and rejects invalid values. |
| `test-pk-safe-error-redaction-contract.R` (25) | Five synthetic ODBC/driver/DSN shapes all collapse to the generic message; our own Turkish validation text passes through; empty/NA fall back; detail is **logged** and not lost; the module uses the helper and the old `err_msg` embedding is gone; redaction is engine-independent. |
| `test-pk-v1-compatibility-contract.R` (34) | `v1` is the default; under `v1` the D1 intersection, the D2 truncation, the D5 expression execution and the absence of the D4 policy are **all still present**, while the same fixtures under `v2` produce the corrected result; the v1 filter timeout literal is preserved; the Phase-0 observation contract holds on **both** engines; the four cross-engine files are statically flag-free while the module's v2 behavior is flag-gated. |

Total: **295 new assertions**, all offline — no DB, LLM, browser, SSO, network or
real secret. Every fixture is synthetic (`SENTETIK ...`, `q_sentetik`,
`SentetikDsn`); no real project or programme name appears anywhere.

**Mutation-checked.** Every new test was verified to actually fail when the fix it
guards is reverted, rather than merely being green:

| Reverted behavior | Failures |
|---|---|
| SQL gate accepts multi-statement batches | 6 |
| SQL literal/comment/identifier masking removed | 11 |
| missing RLS column skipped again (D6) | 3 |
| unavailable/empty scope means "no filter" again (D6b) | 8 |
| same-column AND instead of OR (D1) | 2 |
| multi-value truncated to `[1]` (D2) | 3 |
| `tolower()` instead of `pk_tr_fold()` (D3) | 3 |
| zero-match policy disabled (D4) | 9 |
| degraded-status gate disabled (D9) | 9 |
| `eval(parse())` restored in v2 (D5) | 2 |
| budget measured on the summary only (D7) | 3 |
| v2 recursion drops context again (D8) | 2 |
| raw ODBC message returned to the user (D22) | 7 |
| M8 gate never aborts | 2 |
| engine dispatch removed (v1 leak) | 5 |

### Design decisions, with reasoning

**P1 — `SET NOCOUNT ON;` before a SELECT is now refused, and that is a real
deployment risk the operator must check.** §5.4/D23 is explicit: "no second
statement". A production `.sql` file that opens with a session setting will
therefore be rejected with reason `multiple_statements`. This is fail-closed and
plan-conformant, but it is the single most likely way Phase 1 breaks a working
query on the VM. The classifier logs the reason and statement count so the
diagnosis is one log line, and a dedicated test pins the behavior. **Before
enabling this on the VM, grep the ~169 query files for leading `SET`/`GO`.** If
any exist, the conscious choice is to strip them or to extend the classifier with
a narrow allowlist of provably side-effect-free session settings — not to weaken
the single-statement rule generally.

**P2 — `INTO` is a forbidden keyword anywhere in the statement, not just after
`SELECT`.** Matching `SELECT ... INTO` positionally is fragile once CTEs, unions
and subqueries are involved. Because bracketed/quoted identifiers are masked
first, a column literally named `[Into]` is unaffected; only a bare `INTO` token
trips it. Fail-closed beats clever parsing here.

**P3 — RLS row matching stays byte-identical to v1; only the scope list is
normalized.** `pk_rls_code_norm()` is applied to the *declared scope*, never to
the data column being compared. Normalizing the data side (e.g. trimming) could
make previously non-matching rows match, which **widens** a user's scope — the
wrong direction for a security fix. The comparison remains `%in%` on raw column
values, exactly as before.

**P4 — The collision guard cannot fire today, and that is the point.** With a
normalizer that only does UTF-8/NFC/trim, two genuinely distinct codes cannot
collapse. The guard compares each code's `pk_rls_code_norm()` key against a
*reference* key (NFC + trim), so it fires precisely when someone later loosens the
normalizer. The test proves this by re-sourcing the file into an environment where
`pk_rls_code_norm` has been replaced with a case-folding version. Asserting a
collision against the production normalizer would have required a fixture that
cannot exist.

**P5 — A resolved-but-unenforceable scope keeps v1 behavior, and is logged.**
If a scoped role has a valid scope but the query declares no matching
`rls_columns` entry, there is no predicate to apply. Returning zero rows there
would break every non-project-scoped query for PY users. The plan's long-term
answer is SQL-side predicates (§5.6); until then this is reported in
`plan$unenforced` and logged, never silent. **This is the one place where D6b's
"never all rows" is not literally enforced, and it is stated here rather than
buried.** The two cases the plan calls out — unavailable scope and empty scope —
*are* enforced literally.

**P6 — M8 is split into two verdicts, only one of which is unconditional.** A
`fail_closed` verdict (declared RLS column missing/invalid/duplicated) aborts on
both engines: it is a security verdict. A non-RLS metadata mismatch aborts only
under v2, because v1 uses metadata for no decision at all, and aborting v1 for it
would be a behavior change outside the four §10 cross-engine items. Since every
production query is currently Tier-0, the second branch is inert in practice.

**P7 — D9 refuses rather than continuing with disclosure.** §8 says "prevent
silent full-set continuation". When the filter plan timed out we do not know what
the user asked to filter on, so a disclosed full-set analysis would still answer a
different question (§5.4 rule 6). v2 therefore returns an explicit Turkish
"could not be determined" message and records the outcome. v1 is untouched.

**P8 — `utils::modifyList()` is avoided again, and it bit again.** `pk_rls_plan()`
and `pk_filter_compile()` both initially used it for their result skeletons; it
merges list-valued fields recursively by name and silently **drops unnamed
lists**, so `predicates` came back empty and the PY fixture returned all rows.
This is the same trap recorded as Phase-0 D9. Both now use plain assignment. It
was caught by an existing test, not by a new one — which is the argument for
keeping that older coverage.

**P9 — Two files were split purely for budget, with byte-identical content.**
`pk_build_analysis_system_prompt()` was moved out of the module (verified
byte-identical for both `full` and `summary` modes against the pre-change code)
so the module could absorb the new call sites and still shrink; and
`generate_statistical_summary()` moved to `R/helpers_pk_statistical_summary.R`
because the RLS file's own contract test caps it at 400 lines. **No budget was
raised anywhere.** The second split also isolates the function §5.7 says Phase 2
will replace.

**P10 — v2 decisions travel back to the module as an attribute, not a new return
type.** `apply_smart_filters()` must keep returning a `data.frame` for every
existing caller (including the Ortak Oturum bridge). The v2 policy decision rides
in `attr(x, PK_FILTER_V2_ATTR)`, which the module reads **before**
`normalize_pk_dataframe_utf8()` drops attributes.

**P11 — Secondary drops reuse the Phase-0 provenance pipeline.** Rather than
inventing a second disclosure channel, dropped zero-match columns are recorded as
`dropped_filters` in the existing filter-observation store, which
`pk_analysis_observe()` already converts into user-visible footer warnings.

### Deviations from the plan

1. **Branch name.** The plan says `pk/phase-1-correctness`; the harness assigned
   `claude/pk-phase-1-surgical-correctness-o6e6sg`. The substance holds: cut from
   the `origin/pk/rebuild` tip `aa39652` (which matched the expected tip), one
   phase only, PR base `pk/rebuild`, never `main`.
2. **Nine new files instead of the five §6 names.** §6 lists
   `helpers_pk_filter_compile.R` and `helpers_pk_text_turkish.R` (the latter
   already landed in Phase 3a). The other seven exist because the alternative was
   growing `module_proje_kaynak_analizi.R` and
   `helpers_pk_analysis_security_summary.R` past their contracts. Each new file is
   single-purpose, pure, manifest-declared and seam-owned.
3. **P5** (unenforceable-scope boundary) is narrower than a literal reading of
   D6b, argued above.
4. **P6/P7** are scope decisions, argued above.
5. **Nearest-value hints deliberately omitted** — §8 assigns candidate ranking to
   the Phase 4 resolver. A test asserts the refusal message does **not** contain
   them, so a later phase upgrading the message is a conscious change.

No maintainability budget was raised. No v1 selection or filter decision changed.

### Review findings received and how each was resolved

None yet — PR just opened.

### What remains unproven and needs the VM

* **The SQL classifier against the ~169 real query files.** Every fixture here is
  synthetic. If any production query carries a leading `SET`/`GO`, a data-modifying
  CTE, or an `EXEC`, it will now be refused (see **P1**). This is the highest-risk
  item in the phase and must be checked before flipping anything on.
* **Real SQL Server behavior** of the accepted statements — the classifier reasons
  about text, not about what the driver executes.
* **Real ODBC error shapes.** Redaction is matched against synthetic driver
  messages; the real `nanodbc` text on the Windows VM may differ.
* **Real RLS data.** `DC01_user_base`, `sql_permission_py` and `sql_permission_eps`
  are never contacted here. The unavailable-vs-empty split is proven only against
  a stubbed connection, and the **operational impact** of the new fail-closed
  behavior (how many users/queries newly abort or return zero rows) is unknown
  until it runs on the VM.
* **Turkish folding on a Turkish Windows locale** for the filter comparisons —
  Phase 3a's golden-byte assertion will detect drift, but it has not run there.
* **The v2 path end to end.** No v2 request has ever been executed against a real
  query, real data or a real filter LLM. `MERGEN_PK_ENGINE=v2` is off by default
  and must stay off until the VM validates it.
* **Deep mode** interaction with the new gates under real multi-query load.
* Browser UX smoke **SKIPPED** in this container (no browser binary).

### Exact validation commands run, and their real results

Environment note: this container starts in a **POSIX/C locale**, which makes R fail
to read the repo's UTF-8 sources. Every command below was run with `LC_ALL=C.UTF-8`.

| Command | Result |
|---|---|
| `Rscript tests/scripts/parse_sanity_check.R` | `OK: 1077 dosya parse edildi.` |
| 7 new Phase-1 test files | `pass=295 fail=0 warn=0 skip=0` |
| All `test-pk-*` / `test-deep-analysis-*` + manifest/seam/ratchet/production/secret files | `fail=0 warn=0` |
| `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")` | `FAIL 0 WARN 0 PASS 270` |
| `testthat::test_file("tests/testthat/test-pk-analysis-maintainability-contract.R")` | `FAIL 0 WARN 0 PASS 7` |
| `testthat::test_file("tests/testthat/test-source-manifest-sections-contract.R")` | `FAIL 0 WARN 0 PASS 170` |
| `testthat::test_file("tests/testthat/test-seam-registry-contract.R")` | `FAIL 0 WARN 0 PASS 12` |
| `bash tools/seam_doctor.sh` | `SEAM_DOCTOR_RESULT: OK (yapısal sorun yok)` |
| `source("tests/scripts/maintainability_report.R")` | Skor **100/100**; 800+ satır **0**; 25+ fonksiyon **0**; en büyük dosya **795**; en yüksek fonksiyon **24** — Faz 0/3a taban çizgisiyle aynı, hiçbir bütçe yükseltilmedi |
| `bash tools/ai_validate.sh full --boot-smoke` | **PASSED** — `failed_steps: 0`, `skipped_steps: 0`. Artifact: `artifacts/ai-validation/20260804-060423/summary.json` |

`full --boot-smoke` proof fields (verbatim from `summary.json`):

```
validation_execution_status: ran_by_ai_repo_check
profile_requested: full          profile_effective: full
failed_steps: 0                  skipped_steps: 0
app_source_smoke_status:      passed
full_testthat_suite_status:   passed      (412.2s, zero failures)
shiny_boot_smoke_status:      passed
browser_smoke_status:         skipped     <-- no Chrome/Chromium/Edge binary in this container
db_sso_vm_validation_status:  not_performed_by_ai_validate
sql_server_turkish_encoding_preflight_status: not_performed_by_ai_validate
manual_fragile_flow_evidence_status:          not_performed_by_ai_validate
```

**Honesty boundary.** The mandatory `full --boot-smoke` gate for this phase **did
run and did pass**, including app source smoke, the full testthat suite and Shiny
boot smoke. Browser UX smoke **SKIPPED** (no browser binary — the runner exits 0 on
that skip by design, so it is *not* browser proof). Nothing here proves runtime,
VM, SSO, real DB, SQL Server Turkish encoding, or browser behavior; those remain
the VM gates in §14 of the plan. In particular, **no claim is made that the
read-only classifier accepts the real production queries** (see **P1**).

Note: the pre-existing `helpers_deep_analysis.R` ratchet breach that blocked the
Phase-3a gate was already fixed on `pk/rebuild` (post-review split into
`helpers_deep_analysis_detail.R` / `helpers_deep_analysis_context.R`), so the full
suite runs clean here.

### Behavior changes made to existing tests (coverage extended, never deleted)

| Test | Change |
|---|---|
| `test-pk-analysis-security-summary-contract.R` | Loader sources `helpers_pk_rls.R` + `helpers_pk_statistical_summary.R`; three new tests assert the D6/D6b fail-closed contract alongside the unchanged ADMIN/PY/EPS cases. |
| `test-deep-analysis-execute-query-behavior.R` | Loader sources the shared gate helpers; the expected refusal message is now the more specific D23 text. |
| `test-pk-analiz-process-request-behavior.R` | Loader sources the new helpers; the forbidden-SQL test now asserts the gate refuses **before** connecting and leaks neither the SQL nor a DB-error wrapper; a new test asserts D22 redaction end to end. |

**M8 is now closed.** `pk_meta_validate_actual_columns()`, written and tested but
deliberately unwired in Phase 3a, is called from both the main module and deep
mode immediately before RLS. That was the one loose end Phase 3a left.

---

## Phase 1 — PR #697 review fixes

A second pass over the Phase-1 diff found six defects. Each is fixed below with a
mutation-verified regression test (the new assertions genuinely fail when the fix
is reverted). No behavior beyond these defects was changed, and no budget was
raised.

| # | Sev | Defect | Fix |
|---|---|---|---|
| 1 | P1 | `pk_sql_split_statements()` only recognised a standalone `GO` when the line ended with `\n`. Deep mode passes the SQL file **raw** and Windows/SSMS files are CRLF, so the *same* query was classified differently by line ending: the LF form was allowed, the CRLF form was rejected as `forbidden_keyword`. A real multi-batch CRLF file was also mis-reported as a single statement. | Separator pattern now covers CR / LF / CRLF on both sides. |
| 2 | P1 | `.pk_filter_mask_date()` parsed filter values with `suppressWarnings(as.Date(x))`, but `as.Date()` raises an **error** (not a warning) for unparseable text. LLM-produced values such as `"gecen ay"` therefore escaped through `apply_smart_filters()` and aborted the whole analysis with a raw English R error instead of dropping the leaf with a reason. | Both the value parse and the column parse go through a `tryCatch`-guarded helper; an unparseable value returns `NULL` and the leaf is dropped with its reason, as designed. |
| 3 | P1 | Engine mode was resolved from two different fields. The module reads `selected_query$meta`, but `apply_smart_filters()` passed `context$query_meta` — which is the **full query object**, not its metadata block — so `pk_config_resolve()` read `selected_query$engine`. A query declaring `meta$engine = "v2"` got v2 policy/budget in the module while the filters silently stayed on the v1 body (D1–D5 disabled); a stray top-level `engine` field flipped the split the other way and discarded the v2 refusal verdict. | The filter surface resolves the engine from `context$query_meta$meta`, exactly like the module. The executor still receives the full query, because `pk_meta_primary_entity()` resolves the metadata block itself. |
| 4 | P2 | `pk_meta_actual_column_gate()` swallowed a validator exception into `error = function(e) NULL` and returned the *open* verdict with no trace at all. | The reason is now carried out in `warn`, which the module already logs as `METADATA/RLS SUTUN UYUSMAZLIGI`. The gate deliberately stays open here — the authoritative fail-closed decision for a missing declared RLS column is `pk_rls_plan()`, which is unaffected — but it is no longer silent. |
| 5 | P2 | `pk_config_safe_snapshot()` used `out[[key]] <- value`; assigning `NULL` **deletes** the element, so a key that failed to resolve vanished from the diagnostic snapshot instead of being reported. | Unresolvable values are written as `NA`, so "absent" and "unresolvable" stay distinguishable. |
| 6 | P2 | `helpers_pk_analysis_filters_base.R`, `helpers_pk_analysis_security_summary.R` and `test-pk-analysis-security-summary-contract.R` were rewritten from CRLF to LF, turning an 11-line change into a 911-line diff and hiding the real edits. The repo has no `.gitattributes` and mixes endings (157 of 393 `R/*.R` files are CRLF). | Original CRLF endings restored. `helpers_pk_analysis_filters_base.R` 911 → **11** changed lines, `helpers_pk_analysis_security_summary.R` 568 → **284**, the test file 603 → **105**; ~1,700 lines of pure noise removed from the PR. |

### Regression tests added

| Test file | Asserts |
|---|---|
| `test-pk-sql-readonly-gate-contract.R` | A trailing `GO` line is a separator and a single SELECT stays allowed for CR, LF **and** CRLF; a genuine two-statement batch is rejected with `multiple_statements` in all three. Fails 4× before the fix. |
| `test-pk-filter-compile-behavior.R` | An unparseable date value drops the leaf with a reason and leaves the row mask untouched, while a parseable value still filters. Errors before the fix. |
| `test-pk-v1-compatibility-contract.R` | `meta$engine = "v2"` puts the filter surface on the v2 body; a top-level `engine` field does not. Fails 2× before the fix. |

### Validation of the review fixes

| Gate | Result |
|---|---|
| `Rscript tests/scripts/parse_sanity_check.R` | `OK: 1077 dosya parse edildi.` |
| All `test-pk-*` / `test-deep-analysis-*` + ratchet / manifest / seam / production contracts | `pass=1057 fail=0 err=0 warn=0 skip=0` |
| Mutation check (fixes reverted, tests kept) | 4 failures + 1 error + 2 failures — every new assertion is load-bearing |

### Residual risks deliberately left alone

Two fail-open paths inside the RLS layer are **pre-existing, documented policy**,
not review findings, and changing either would lock out users without VM evidence:

* `plan$unenforced` — a resolved scope whose query never declares the matching
  column is logged and the rows are returned **unfiltered**. Already documented in
  `helpers_pk_rls.R` as a bounded limit whose real fix is pushing the predicate
  into SQL.
* `MasrafYeriKodu` NA/`"ADMIN"` yields `allowed_depts = NULL`, which reads as
  "no department restriction". `scope_state_depts` is never set, so the
  `unavailable` state is unreachable for that dimension — harmless today because
  the department code comes from the same `DC01_user_base` row that already
  succeeded, but worth an explicit decision during VM validation.

---

## Phase 1 — PR #697 review, second round

A third pass over the Phase-1 diff (after the six fixes above) found **two more
fail-open / crash defects and two correctness defects**. Each production fix
below is mutation-verified: the new assertions genuinely fail when the fix is
reverted. Nothing outside these findings changed and no budget was raised.

| # | Sev | Defect | Fix |
|---|---|---|---|
| 7 | **P1** | `pk_sql_mask_literals()` ended a `--` line comment on `\n` only. T-SQL ends it on CR, LF **or** CRLF, so in a CR-terminated file the masker swallowed the rest of the batch as comment and `SELECT 1 -- x<CR>DROP TABLE T` classified as a single read-only SELECT — the fail-closed gate **silently opened**. The main module normalises line endings before the gate, but deep mode passes the SQL file **raw**, so the hole was reachable. Round 2 fixed the same line-ending class for `GO`; this is its fail-**open** twin. | The line-comment state now terminates on CR as well as LF, and the terminator character is preserved so the `GO` splitter still sees it. |
| 8 | **P1** | The module recognised an error return from `execute_pk_sql_unicode()` only by the `⚠️` prefix, but `pk_safe_error_message()` is deliberately **pass-through** for text that does not look like infrastructure diagnostics. `execute_pk_sql_unicode()`'s own first check raises exactly such a message (`"Bos SQL metni gonderilemez."`), as does any plain R error. The unprefixed text then failed the sentinel, was treated as the result set, and the flow died inside `apply_rls_to_data()` with a raw English `argument is of length zero`. Before this PR the handler always emitted the prefix, so this is a regression introduced by the D22 change. | `pk_user_error_text()` (new, in `helpers_pk_safe_errors.R`) guarantees the shared marker without touching `pk_safe_error_message()`'s tested redaction contract, and the module's sentinel is now the type check `is.character(raw_data)` — a successful query always returns a data.frame, so a character value can only be the error branch. |
| 9 | P2 | `pk_filter_zero_match_policy()`: when no primary entity can be identified (every production query is Tier-0 today, so this is the normal case with ≥2 filter columns) **and every applied filter matched zero rows**, rule 2 dropped all of them and the analysis proceeded over the **entire authorised set** with only a footnote. That is precisely the outcome D4 exists to prevent — the user names a record that does not exist and receives whole-table statistics answering a different question. | When the primary column is unresolvable and *all* groups are zero-match, the verdict is `refuse`, matching the primary-column rule. The legitimate secondary-drop path is untouched: as long as at least one filter still narrows, behaviour is unchanged. |
| 10 | P2 | `pk_filter_normalize_leaf()` lower-cased the operation name with `tolower()`. On the Turkish Windows VM — the production platform — `tolower("CONTAINS")` yields `contaıns` (dotless i), which matches no operation list, so a substring search silently degrades to **exact match** and returns wrong (usually empty) results. Uppercase operation names are an ordinary LLM output variation. This is the D3 defect this very file was written to fix; the same pattern also affected `pk_config_meta_key()` (`..._HMAC_KEY_ID` → `..._hmac_key_ıd`, so its metadata/`options()` steps were unreachable) and the v2 aggregation name. | All three now fold with an ASCII-only `chartr("A-Z","a-z")`. `pk_tr_fold()` is deliberately not used — these are ASCII protocol tokens, not Turkish prose — and the "no `chartr` for Turkish folding" rule in `helpers_pk_text_turkish.R` is unaffected. |

### Hardening (not a defect)

`apply_smart_filters()`'s v2 branch stored the compiler's normalised leaves
(`values`, plural) directly as the observation's applied/dropped filters, while
the provenance footer and the dropped-filter degradation text read `f$value`.
This works **today** only because `$` does partial name matching on lists. The
rescue is accidental: `[[` does not partial-match, and adding any second field
starting with `value` makes the match ambiguous and returns `NULL`, at which
point the user-visible line becomes `ProjeAdi = "" (içerir)`. The leaves are now
translated to the v1 filter shape explicitly, and a regression guard locks the
footer output. This assertion passes with and without the change — it is a guard,
not evidence of a live bug.

### Regression tests added

| Test file | Asserts | Without the fix |
|---|---|---|
| `test-pk-sql-readonly-gate-contract.R` | A `--` comment followed by `DROP` / a second batch is rejected for CR, LF **and** CRLF; a leading comment line still leaves a valid SELECT allowed. | **4 failures** |
| `test-pk-analiz-process-request-behavior.R` | A non-infrastructure SQL error (`"Bos SQL metni gonderilemez."`, `could not find function ...`) returns a single marked user message and never reaches `apply_rls_to_data()`. | **1 error** (`apply_rls_to_data` called with the error text) |
| `test-pk-safe-error-redaction-contract.R` | `pk_user_error_text()` marks unmarked text, never double-marks, falls back to the generic message on empty/NA, and does not weaken redaction. | new coverage |
| `test-pk-filter-policy-behavior.R` | No primary + all groups zero-match ⇒ `refuse` with zero mask; at least one surviving filter ⇒ the secondary-drop path is unchanged. | **4 failures** |
| `test-pk-filter-compile-behavior.R` | `CONTAINS` / `STARTS_WITH` / `NOT_IN` / `IN` / `MIN` resolve locale-independently and `contains` still filters; source-level guard that `tolower(` does not return to the compiler. | **1 failure** |
| `test-pk-v1-compatibility-contract.R` | The v2 observation exposes `column` / `value` / `operation` and the footer prints the real value. | guard (see above) |

### Still true after this round

The PR body's **highest-risk item is unchanged**: the read-only classifier has
never been run against the ~169 real production queries, and a file that opens
with `SET NOCOUNT ON;` is still rejected as `multiple_statements`. That remains a
deliberate §5.4 decision, so the pre-merge action is unchanged — **scan the query
files for a leading `SET` / `GO` before enabling this on the VM.** The two
residual RLS fail-open paths documented above are also unchanged; they are
pre-existing policy, not review findings.

---

## Phase 2 — Deterministic analysis + export

* **Status:** `in_review`
* **Branch:** `claude/pk-phase-2-analysis-export-otxf78` (harness-assigned; see
  "Deviations"). Cut from the `origin/pk/rebuild` tip `f1368b2`, which matched
  the expected tip exactly.
* **PR:** base `pk/rebuild` ← head `claude/pk-phase-2-analysis-export-otxf78`
* **Merge SHA:** _pending_

### Defects re-verified before writing code (§0.1)

Line numbers had drifted (Phase 1 moved two of these functions into new files).
Each was re-read in the current checkout. **Every claim still reproduces.**

| Defect | Verdict | Evidence in the current code |
|---|---|---|
| **D17** statistics computed and thrown away | **REPRODUCES** | `R/helpers_pk_statistical_summary.R`: `lapply(head(cat_cols, 5), ...)` summarizes only the first five categorical columns, computes `top5 <- head(tbl, 5)` and then uses `as.integer(top5[1])` only. Silent on both counts. |
| **D18** positionally biased sample | **REPRODUCES** | module: `dynamic_preview_rows <- if (nrow(filtered_data) <= 500) nrow(...) else 500`, then `preview_data <- head(data, max_preview_rows)`. |
| **D19** scientific notation | **REPRODUCES** | `paste(capture.output(print(num_summary_df, row.names = FALSE)), collapse = "\n")` for the numeric AND date AND categorical tables. |
| **D20** contradictory prompt | **REPRODUCES** | `pk_build_analysis_system_prompt()` demands `KÖK SEBEP` + `sektör benchmarks'leri` while forbidding speculation, and both branches carry `sonuçları MUTLAKA markdown tablo formatında sun`. |
| **D21** dead pre-filter payload | **REPRODUCES** | module returned `data = secure_data`; `grep` confirms `server_send_message.R` reads only `prompt_context` / `user_context` / `max_tokens`, and the Ortak Oturum bridge only `prompt_context`. |

Nothing in the plan was found to be withdrawn; nothing from §3.9 was resurrected.

### Engine boundary as implemented

§10 lists exactly four unconditional cross-engine items, and **all four already
landed in Phases 0 and 1**. Phase 2 therefore adds **nothing** to v1: every new
behavior sits behind `MERGEN_PK_ENGINE=v2`.

| Item | Gating | Where |
|---|---|---|
| Analysis packet, packet text, budget | `v2` | `.pk_result_v2()` only |
| Epistemic system prompt, no markdown-table instruction | `v2` | `pk_build_analysis_system_prompt_v2()`; the v1 builder is byte-untouched |
| R-owned table + XLSX/CSV attachment | `v2` | `.pk_result_v2()` only |
| Numeric provenance (`log`) | `v2` | activates only when the request stashed `facts`; v1 never does |
| D21 `data = filtered_data` | `v2` | v1 still returns `secure_data` |

`pk_build_analysis_result()` is the **single** place that branches. The six pure
Phase-2 files are statically proven free of `pk_engine_is_v2`.

### Files added

| File | Purpose | Purity |
|---|---|---|
| `R/helpers_pk_packet_stats.R` | Locale-independent Turkish number formatting (D19), stable ASCII fact ids, scope signature, per-measure statistics under the sparse/non-finite contract, weighted-mean invalid-weight contract, `latest` tie contract. | pure |
| `R/helpers_pk_analysis_packet.R` | Packet assembly: scope, filters, coverage, facts, categorical (ALL dimensions), dates, groups, stratified examples, limitations. | pure |
| `R/helpers_pk_packet_render.R` | Packet → Turkish text + budget accountant with an explicit degradation ladder. | pure |
| `R/helpers_pk_numeric_provenance.R` | `[fact:...]` claim extraction, Turkish number parsing, value **and** semantic (unit/availability) validation, `off/log/warn/block`, secret-safe mismatch-rate report. | pure |
| `R/helpers_pk_export_plan.R` | Row ordinals, part planning / explicit refusal, writer-specific percent contract, CSV formula neutralization, `Bilgi` + `Özet` sheets, multiset verification. | pure |
| `R/helpers_pk_export_xlsx.R` | writexl baseline + gated openxlsx formatting, `readxl` read-back verification, BOM CSV fallback, session-scoped serving + cleanup. | I/O |
| `R/helpers_pk_answer_compose.R` | Ordered first-match rendering rules, R-owned markdown table, attachment card, deterministic facts summary. | pure |
| `R/helpers_pk_analysis_result.R` | The one v1/v2 branch; owns the module's former tail. | I/O |

### Files modified

| File | Change |
|---|---|
| `R/module_proje_kaynak_analizi.R` | Tail (statistics → payload → prompt → return) delegated to `pk_build_analysis_result()`. **689 → 654 lines** (it shrank, per §6). |
| `R/helpers_pk_analysis_prompts.R` | v1 builder **byte-untouched**; new `pk_build_analysis_system_prompt_v2()` added. |
| `R/helpers_pk_provenance.R` | `- **Ek:**` footer line (incl. explicit refusal); `pk_provenance_stash()` optionally carries facts/fallback/query id; `pk_provenance_decorate()` runs numeric-provenance validation before appending. |
| `R/helpers_pk_telemetry.R` | `pk_analysis_observe()` passes `attachment` into the footer and stashes `answer_block` + `facts` + `fallback_text`. |
| `R/helpers_pk_config.R` | 12 new knobs (packet depth, composition thresholds, export limits, provenance mode). |
| `R/config_source_manifest.R` | Eight new files in `analysis_helpers`, dependency-ordered. |
| `R/config_seam_registry.R` | Three new guard tests + two focused-validation commands on `mcp_analiz`. |
| `.Renviron.example` | All 12 knobs with Turkish comments stating they are v2-only. |
| `tests/.../test-source-manifest-sections-contract.R` | Frozen anchors updated consciously: `analysis_helpers` 22 → 30, total 392 → 400. |
| `tests/.../test-pk-observation-accuracy-contract.R`, `test-pk-provenance-delivery-contract.R` | Stubbed `pk_provenance_stash` signature widened with `...` to mirror the grown production signature (see design decision E9). |

### Tests added, and what each **proves**

| Test | Proves |
|---|---|
| `test-pk-analysis-packet-behavior.R` (146) | **D19**: 1.234.567.890 never becomes `1.23e+09`, output is byte-identical under `OutDec = ","`, and no packet file uses `capture.output`. **Sparse contract**: an all-missing measure yields `unavailable_no_finite_values` and **never** a factual zero; one observation yields `single_observation` for sum/mean/median/min/max and `insufficient_data` (value-free) for sd/percentiles/IQR; **no fact anywhere carries NA/NaN/Inf**. **Tier-0**: without `additive` neither sum nor mean is emitted, while distribution statistics still are. **Weighted mean**: zero-weight and missing pairs are excluded *with the count disclosed*; a negative or infinite weight invalidates the whole set; no positive pair returns `weighted_mean_unavailable` — never an unweighted mean, zero or `NaN`. **`latest`**: unique `latest_tie_by` resolves, a duplicated newest-timestamp key returns `ambiguous_latest`, and a missing tie declaration refuses. **Fact contract**: ids are stable ASCII even from a Turkish column name, and carry capability/unit/label/scope. **D17**: all six categorical columns are summarized (five would have been the old cap), top-K carries count **and** share, the remainder rolls into `Diğer (15 deger)`. **D18**: the example set is not `head()` — it spans ≥3 strata of a 400-row frame ordered by group, is reproducible under a fixed seed, and **restores the global RNG state**. **D7/D8**: the budget measures the whole payload and trims examples first, and `FİLTRELEME UYARISI` plus the degradation line survive **all five** budget levels down to 1000 chars; what was dropped is stated. **Scope**: a `pre_rls_rows` value passed into the builder appears nowhere in the packet or its rendered text. |
| `test-pk-numeric-provenance-contract.R` (65) | Turkish/plain number parsing incl. rejection of ambiguous `1.234,56.7`. Correct value on the right fact passes; wrong value is `value_mismatch`; declared rounding tolerance accepts `18.420` for 18.420,5 but rejects `18.419`. **The plan's own example**: `47` exists in the packet as a distinct-person count, so *"tamamlanma %47"* citing that fact is rejected as `unit_mismatch`, while *"47 farklı kaynak"* citing the same fact passes — token membership alone can never authorize a claim. Unknown fact id, unavailable fact, and a fabricated `pre_rls.count.overall` citation are all rejected. Mode contract: default is `log`; `log` records but does **not** alter user-visible text; markers are stripped in every mode; `warn` marks the figures visibly; `block` replaces prose with the deterministic summary but does **not** fire when there is no mismatch. The mismatch-rate report contains counts/reasons and **not** the prose. |
| `test-pk-export-xlsx-behavior.R` (~100) | Part planning covers every row exactly once; above the part ceiling the export is **explicitly refused** with a "narrow your request" message, not silently truncated. Sheet names are Excel-legal and keep Turkish characters. **Writer-specific percentage**: the `writexl` baseline stores `61.3` under `Tamamlanma (%)`, the `openxlsx` path stores `0.613` under `Tamamlanma`, `fraction` scales correctly in both, an undeclared `percent_scale` is **not** rescaled and is disclosed, and no path can display a value above 100 (i.e. `%6130,0` is unreachable). **Real 5,000-row XLSX**: read back with `readxl` — 5,000 rows, `Veri`/`Ozet`/`Bilgi` sheets, `Tutar` still **numeric** `-125.50`, `Tamamlanma (%)` still numeric `61.3`, Turkish `SENTETIK ÇALIŞMA İSTANBUL` intact. `Bilgi` carries the authorized and post-filter counts and **not** a `pre_rls_rows` value even when the caller passes one. Multipart: 250 rows at 100/part produce `Veri_001..003` whose union is exactly 1..250. Eight identical rows stay eight rows (no dedup); multiset verification still catches a missing or altered row. CSV fallback: verification failure deletes the unverified XLSX, writes a **UTF-8 BOM** CSV, neutralizes character `=1+1`/`-KAPALI-`/`@kullanici`/`+ek` while ordinary Turkish text and the **numeric** `-125.50` are untouched. Static: the export files never mention `bilge_yolac_downloads` or `addResourcePath` and do use `registerDataObj` + session cleanup, and serving really registers one cleanup per file. **Composition**: the ordered rules are proven with the plan's own ambiguous case (100×20 → attachment, not inline), Turkish `LİSTEYİ VER` is detected locale-independently, a 400-row result produces a <30-line bubble (not a table wall), and the R-owned markdown table escapes `|` and newlines. |
| `test-pk-v1-compatibility-contract.R` (+13 new) | **D21** v1 still returns the 20-row pre-filter frame while v2 returns the 10-row post-filter frame. `prompt_context`/`user_context`/`query_name`/`max_tokens` — the fields `server_send_message.R` and the Ortak Oturum bridge read — are intact on **both** engines. **D20** the `markdown tablo` instruction is still present in the v1 prompt (both modes) and gone from v2, which instead carries all five epistemic labels and forbids invented benchmarks. Facts/answer block/attachment exist only on v2; the v1 payload keeps its `ISTATISTIKSEL OZET` + `ORNEK SATIRLAR (JSON)` shape and contains no `[fact:` marker. The six pure Phase-2 files are statically flag-free. Numeric provenance does not run at all when no facts were stashed (the v1 path), and when they are stashed the markers are stripped and the R block lands **before** the footer. The footer shows the attachment (and an explicit refusal) while never printing the pre-RLS count. |

Total: **~324 new assertions**, all offline — no DB, LLM, browser, SSO, network
or real secret. Every fixture is synthetic (`SENTETIK ...`, `q_sentetik`); no
real project or programme name appears anywhere.

**Mutation-checked.** Each new test was verified to genuinely fail when the fix
it guards is reverted:

| Reverted behavior | Failures |
|---|---|
| only the first five categorical columns summarized (D17) | 2 |
| example rows back to `head(data, n)` (D18) | 6 |
| number formatting back to `as.character()` (D19) | 14 |
| `additive` gate removed (always sum) | 2 |
| invalid weights fall back to an unweighted mean | 7 |
| `FİLTRELEME UYARISI` droppable under budget (D8) | 5 |
| writexl baseline stops rescaling/labelling percent | 4 |
| part ceiling silently truncates instead of refusing | 7 |
| CSV neutralization applied to numeric columns too | 2 |
| pre-RLS count written into the `Bilgi` sheet | 1 |
| composition rules reordered (rule 3 before rule 2) | 3 |
| semantic unit check removed (token-only provenance) | 2 fail + 2 error |
| `[fact:...]` markers left in the displayed text | 5 |
| v2 returns the pre-filter frame (D21 reverted) | 1 |
| v2 prompt keeps the markdown-table instruction (D20) | 4 |

### Design decisions, with reasoning

**E1 — Tier-0 emits distribution statistics but never a sum or a mean.**
Phase 3a's named fallback is *"additive yok -> toplama YAPILMAZ"*, and every
production query is Tier-0 today. Taken literally that would leave the packet
with almost nothing. The distinction drawn here is between an **entity-level
aggregate claim** (sum, mean — these need `additive`/`aggregate` and are
withheld, with the reason stated in the fact's `note`) and a **description of
the rows actually returned** (median, percentiles, min/max, sd, IQR outliers —
these are true of the returned rows regardless of grain, because the Tier-0
grain fallback is "each row is its own grain"). So Tier-0 still produces a
usable packet without inventing additivity. Every withheld aggregate is a
visible `KULLANILAMAZ (insufficient_data)` line, not a silent omission.

**E2 — The outlier COUNT does not inherit the measure's unit.**
Caught while smoke-testing: the first render produced
`IQR uc deger sayisi: 0,0 saat`. A count is not a quantity. The `iqr_outliers`
fact now uses a unit-free, zero-decimal spec.

**E3 — The scope signature is readable text, not a hash.**
§5.7 asks for a "scope signature". A hash would need a digest dependency and is
useless in a log; `yetki=12405|filtre=312` is deterministic, greppable, and by
construction cannot contain a pre-RLS count.

**E4 — Multipart verification uses the plan's second permitted method.**
§5.9 item 7 asks for a stable ordinal written into each part, read back, then
removed from the served workbook — which means writing every file twice
(unverified-with-ordinal, then served-without). The plan explicitly permits the
alternative: *"verify a multiset key of `(serialized row value, occurrence
index)`"*. The ordinal is still what makes the split deterministic
(`plan$parts[[i]]$ordinals`), and verification compares per-part row/column
counts plus the occurrence-indexed multiset, so legitimate duplicate rows are
preserved and a missing/extra/altered row is still caught. A test asserts both
directions.

**E5 — The `dt` render mode is decided but presented as attachment + preview.**
The pure decision function implements all four ordered rules faithfully and
returns `mode = "dt"` for rule 4. Rendering it as a real `DT` widget needs an
output-binding seam plus `pk_rebind_all_tables()` on saved-chat hydration
(§5.9), which is browser-unprovable in a cloud session and materially larger
than the rest of this phase. Until that lands, `dt` is rendered the same way as
the attachment path (10-row preview + downloadable file), which is conservative
in both directions: never a wall of table, never a broken widget. A later phase
changes one renderer branch, not the decision. **Recorded as a deviation, not a
silently narrowed scope.**

**E6 — The mismatch rate is reported through a secret-safe log line, not a
second `MB_Analiz_Log` row.** Validation happens at the answer-finalization
seam, where there is no DB connection (`pk_analysis_observe()` runs earlier and
owns the only `conn`). §8 asks for the measured rate to be *reported*; the log
line carries mode, query id, claim count, mismatch count, rate and the distinct
reasons — and provably not the prose. Writing it into `MB_Analiz_Log` needs the
async request context that Phase 6 introduces.

**E7 — `block` mode refuses and shows the deterministic summary; it does not
regenerate.** §5.11 describes "rejected and regenerated once; on a second
failure the deterministic table plus a short factual summary". The decorate seam
cannot re-invoke the LLM. The deterministic fallback — the half that protects
the user — is implemented; the single regeneration belongs to whoever owns the
request loop. `block` is not the shipped mode (`log` is), so nothing depends on
this today.

**E8 — Reusing the Phase-0 provenance slot instead of inventing a second
channel.** The R-owned block (table/preview + attachment card) is concatenated
in front of the footer and travels through the existing single-slot stash, so it
inherits Phase 0's request-id staleness guard, take-once semantics and
idempotency for free. Facts and the fallback text ride alongside as optional
fields; when they are absent the decorator behaves exactly as in Phase 0.

**E9 — Two existing test stubs were widened, not weakened.**
`pk_provenance_stash` grew three optional parameters. Three stubs declared the
old three-argument signature, so the real call failed with "unused arguments"
inside `pk_analysis_observe()`'s `tryCatch` and the tests captured nothing. The
stubs now take `...`. No assertion was removed or relaxed.

**E10 — The manifest comment was compressed rather than the ratchet raised.**
Adding eight manifest entries pushed `R/config_source_manifest.R` to 797 lines
against the frozen 795 maximum. The fix was to shorten the comment I had just
added (five lines → two), not to touch the budget. The file is 793 lines and the
global baseline is unchanged: score 100/100, 0 files ≥800 lines, 0 files ≥25
functions, max file 795, max functions 24.

**E11 — `openxlsx` is not installed in this container, so only the baseline path
executed for real.** That is the intended shape: `writexl` is the required
baseline (R2) and a cloud session must not add packages. The `openxlsx` value
contract (`0.613` + `Tamamlanma`) is proven through the pure preparation
function, which is where the two-orders-of-magnitude bug would live. The
formatted **file** and its rendered style remain unproven here.

### Deviations from the plan

1. **Branch name.** The plan says `pk/phase-2-...`; the harness assigned
   `claude/pk-phase-2-analysis-export-otxf78`. Substance preserved: cut from the
   `origin/pk/rebuild` tip `f1368b2`, one phase only, PR base `pk/rebuild`.
2. **Eight new files instead of the four §6 names.** §6 lists
   `helpers_pk_analysis_packet.R`, `helpers_pk_answer_compose.R` and
   `helpers_pk_export_xlsx.R`. The other five exist because the alternative was
   growing files past their budgets: statistics/fact core and rendering split
   out of the packet, the export plan split out of export I/O, numeric
   provenance stands alone, and the result builder exists so the module could
   **shrink** rather than grow. Each is single-purpose, manifest-declared and
   seam-owned.
3. **E5** (`dt` mode rendered as attachment + preview) is the one functional
   narrowing, argued above.
4. **E4**, **E6**, **E7** are method/scope choices within what the plan permits,
   argued above.
5. **`pk_rebind_all_tables()` and the saved-chat expiry card are NOT
   implemented.** They belong to the `DT`-widget seam deferred in E5. Today a
   reloaded saved chat shows the persisted prose, the R-owned markdown table and
   the footer; the attachment link is session-scoped and simply stops resolving
   after the session ends — which is the plan's own "expiry is the safe default"
   position, but **without** the explicit expired-state card. That card is the
   remaining §5.9 hydration item.

No maintainability budget was raised. No v1 selection, filter or output decision
changed.

### Review findings received and how each was resolved

None yet — PR just opened.

### What remains unproven and needs the VM

* **Real Excel rendering on Turkish Windows.** `readxl` proves the **stored
  value**, never the rendered style. That `Tamamlanma (%) = 61.3` reads as a
  percentage to a human, and that the file opens without a repair dialog, are
  VM/browser gates.
* **The `openxlsx` formatted path end to end.** `openxlsx` is absent in this
  container, so `.pk_export_write_openxlsx()` — number formats, freeze panes,
  auto column widths, the `0.0%` style — **has never executed**. Its
  value-scaling decision is tested; its file output is not. This is the single
  largest untested code path in the phase.
* **The download card in a real browser.** Session-scoped `registerDataObj`
  serving, the `Content-Disposition` filename with Turkish characters, and
  cleanup on session end are all offline-stubbed here.
* **v2 end to end.** No v2 request has run against a real query, real data, a
  real filter LLM or a real endpoint. `MERGEN_PK_ENGINE=v2` is off by default
  and must stay off until the VM validates it.
* **The numeric-provenance false-positive rate.** `log` mode exists precisely
  because that rate is unknown; it must be measured on real Turkish answers
  before anyone considers `warn`.
* **Memory/latency of building a packet over a large authorized set.** All
  statistics are single-pass over the full vector by design (§5.7), but the
  largest frame tested here is 5,000 rows.
* **Saved-chat hydration behavior** for an expired attachment (see deviation 5).
* Browser UX smoke **SKIPPED** in this container (no browser binary).

### Exact validation commands run, and their real results

Environment note: this container starts in a **POSIX/C locale**, which makes R
fail to read the repo's UTF-8 sources. Every command below was run with
`LC_ALL=C.UTF-8` (as Phase 1 documented).

| Command | Result |
|---|---|
| `Rscript tests/scripts/parse_sanity_check.R` | `OK: 1088 dosya parse edildi.` |
| 3 new + 1 extended Phase-2 test file | `fail=0 err=0 warn=0 skip=0` |
| All `test-pk-*` / `test-deep-analysis-*` / `test-ortak-oturum-*` + manifest / seam / ratchet / production / secret contracts | `fail=0 err=0 warn=0` |
| `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")` | `FAIL 0 WARN 0` |
| `testthat::test_file("tests/testthat/test-pk-analysis-maintainability-contract.R")` | `FAIL 0 WARN 0` |
| `testthat::test_file("tests/testthat/test-source-manifest-sections-contract.R")` | `FAIL 0 WARN 0` |
| `testthat::test_file("tests/testthat/test-seam-registry-contract.R")` | `FAIL 0 WARN 0` |
| `bash tools/seam_doctor.sh` | `SEAM_DOCTOR_RESULT: OK (yapısal sorun yok)` |
| `source("tests/scripts/maintainability_report.R")` | Skor **100/100**; 800+ satır **0**; 25+ fonksiyon **0**; en büyük dosya **795**; en yüksek fonksiyon **24** — Faz 0/3a/1 taban çizgisiyle AYNI |
| `bash tools/ai_validate.sh full --boot-smoke` | **PASSED** — `failed_steps: 0`, `skipped_steps: 0`. Artifact: `artifacts/ai-validation/20260804-183205/summary.json` |

`full --boot-smoke` proof fields (verbatim from `summary.json`):

```
validation_execution_status: ran_by_ai_repo_check
profile_requested: full          profile_effective: full
failed_steps: 0                  skipped_steps: 0
app_source_smoke_status:      passed
full_testthat_suite_status:   passed      (359.2s, zero failures)
shiny_boot_smoke_status:      passed
browser_smoke_status:         skipped     <-- no Chrome/Chromium/Edge binary in this container
db_sso_vm_validation_status:  not_performed_by_ai_validate
sql_server_turkish_encoding_preflight_status: not_performed_by_ai_validate
manual_fragile_flow_evidence_status:          not_performed_by_ai_validate
```

**Honesty boundary.** The mandatory `full --boot-smoke` gate for this phase
**did run and did pass**, including app source smoke, the full testthat suite
and Shiny boot smoke. Browser UX smoke **SKIPPED** (no browser binary — the
runner exits 0 on that skip by design, so it is *not* browser proof). Nothing
here proves runtime, VM, SSO, real DB, SQL Server Turkish encoding, real Excel
rendering, or browser behavior; those remain the VM gates in §14 of the plan.

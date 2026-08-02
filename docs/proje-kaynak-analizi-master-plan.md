# Proje ve Kaynak Analizi — Master Rebuild Plan

**Status:** design / work order. No code has been changed for this plan yet.
**Audience:** the coding agent (and maintainers) who will implement it.
**Language note:** this document is English like `CLAUDE.md`, because it is an agent
contract. In the implementation, *user-facing* strings and R comments stay Turkish
(`CLAUDE.md` rules 1 and 2), while **code identifiers stay ASCII** — function,
variable and column names, and `$` accessors — per `CLAUDE.md` rule 1A, for Windows VM
parser robustness. Do not Latinize visible Turkish text, and do not put Turkish
characters into code symbols.

---

## 0. How to use this document

This is a **work order with evidence**, not a specification to follow blindly.

1. **Verify before you trust.** Every defect below carries a `file:line` anchor and
   the reasoning behind it. Line numbers drift. Re-read the code, re-confirm the
   defect still exists and still behaves as described, and say so if it does not.
   Two claims in the source analysis were *withdrawn* after being tested in R
   (see §3.9) — apply the same discipline.
2. **This document was written against the GitHub checkout.** The production
   Windows VM repository has ~169 real queries in `R/library_queries.R`; the
   checkout ships only 4 placeholder examples. Design for 169+, but never assume
   you can see them.
3. **Nothing here overrides `CLAUDE.md`.** Where they disagree, `CLAUDE.md` wins.
   §13 lists the constraints that most commonly get violated in this area.
4. **Phases are independently shippable.** Do not attempt the whole plan in one
   change. Phase 1 alone fixes most of what users report today.
5. **Validation honesty is mandatory.** Cloud sessions cannot prove runtime, VM,
   SSO, SQL Server, or browser behavior. §14 lists what is VM-only.
6. **If you are building while the operator has no VM access, read §11 first.** It
   defines the phase order by offline verifiability, the one-phase-per-PR rule, the
   `MERGEN_PK_ENGINE` flag discipline, and the `.ai/pk-rebuild-progress.md` handoff
   contract that lets the next session continue without re-deriving everything.

---

## 1. The governing principle

> **The LLM proposes intent and writes prose.
> Deterministic R code resolves entities, decides logic, enforces security,
> performs every arithmetic operation, and renders every number.**

Every design decision below follows from this. The current implementation violates
it in five places: the model picks canonical DB values, defines executable filter
logic, implicitly decides aggregation, regenerates tables from JSON, and is the
only thing standing between a failed filter and a wrong answer.

A corollary that must hold in the finished tool:

> **The tool is never silently wrong.** Every degradation — LLM timeout, dropped
> filter, unresolved entity, truncated data, narrowed RLS scope — must appear in
> the answer the user reads, not only in the server log.

---

## 2. Current architecture (as-is)

```
send_message (tool_family == "sql_analysis")        R/server_send_message.R:253-311
  └─ pk_analiz_process_request()                    R/module_proje_kaynak_analizi.R:65
       ├─ resolve_pk_analysis_username()            R/helpers_pk_analysis_security_summary.R:7
       ├─ get_connection()  [SYNCHRONOUS, main process]
       ├─ get_user_rls_info()                       …security_summary.R:65
       ├─ select_smart_query()                      …module:576
       │    ├─ find_best_query_with_ai()   [LLM #1, no timeout]      …module:484
       │    └─ pk_compute_heuristic_query_scores()  R/helpers_pk_analysis_query_selection.R:79
       ├─ execute_pk_sql_unicode()                  R/helpers_pk_analysis_core.R:175
       ├─ convert_date_columns()                    …core.R:61
       ├─ apply_rls_to_data()                       …security_summary.R:126
       ├─ extract_filter_criteria_from_prompt()  [LLM #2, 8s timeout] R/helpers_pk_analysis_filters.R:9
       ├─ apply_smart_filters()                     …filters.R:286
       ├─ generate_statistical_summary()            …security_summary.R:168
       └─ returns list(type="data_analysis", data=, prompt_context=, user_context=)
            └─ appended to the LLM message chain    R/server_send_message.R:296-310

Deep Thinking variant: pk_deep_analysis_process()   R/helpers_deep_analysis.R:519
  └─ find_multiple_queries_with_ai() [LLM] + up to 5 × execute_single_deep_query()
       (each doing its own SQL + its own filter-extraction LLM call)
```

Supporting files: `R/helpers_pk_analysis_core.R` (pure helpers, UTF-8 normalization,
`sp_executesql` wrapper), `R/config_sql_loader.R` (startup SQL preload),
`R/library_queries.R` (query library + permission SQL).

Existing tests: `tests/testthat/test-pk-analysis-*.R`,
`tests/testthat/test-deep-analysis-*.R`.

---

## 3. Verified defect inventory

Severity: **S1** = security or silent wrong answer · **S2** = primary user-visible
failure · **S3** = quality/latency/maintainability.

### D1 · S2 · Same-column filters AND together → guaranteed empty result

`R/helpers_pk_analysis_filters.R:358-391` reassigns `dt` on every iteration, so
filters intersect:

```r
for (f in filters) { ... dt <- dt[grepl(...), ] }
```

`ProjeAdi contains "Radar"` **AND** `ProjeAdi contains "Elektronik Harp"` requires
one project name to contain both phrases. Reproduced in R: two `contains` filters
on the same column returned **0 rows**. This is the reported "no values are
displayed" symptom and it is deterministic — no model can avoid it.

Required semantics: **OR within a column, AND across columns**, plus AND for
complementary range bounds on the same column (`>= 2025-01-01` and `<= 2025-12-31`),
and NOT for explicit exclusions.

### D2 · S2 · Multi-value filters silently truncated

`filters.R:366` — `val_str <- as.character(val)[1]`. When the model emits
`"value": ["P1234","P1235"]` (common and correct behavior), every value after the
first is discarded without a log line.

### D3 · S2 · Turkish case-insensitive matching is broken

`filters.R:372,374` use `grepl(..., ignore.case = TRUE)`. Verified in R:

```
grepl("^istanbul$", "İSTANBUL", ignore.case = TRUE)   →  FALSE
grepl("^kalip$",    "KALIP",    ignore.case = TRUE)   →  TRUE
```

`ignore.case` does not know the İ/I/ı/i mapping, so `exact_match` fails on any
Turkish value containing İ or I — and the behavior differs between the Turkish VM
and a C-locale CI run. Every comparison in this tool must go through a single
deterministic Turkish fold helper.

### D4 · S1 · A filter that matches nothing is applied instead of dropped

`module_proje_kaynak_analizi.R:328-334` returns *"Filtreleme sonrası veri
bulunamadı"*. The user cannot distinguish "this data does not exist" from "the
model guessed a project name that is not in the database". See §5.4 for the
required policy.

### D5 · S1 · `eval(parse())` on model-generated text

`filters.R:344`:

```r
dt <- subset(dt, eval(parse(text = expr_str)))
```

`expr_str` is LLM output influenced by user prompt text. `subset()` evaluates with
the calling frame as parent, so `system(...)`, `file.remove(...)` and friends
resolve. This is an RCE-shaped vector reachable by prompt injection, and it is out
of character for a codebase that maintains `render_safe_markdown_html()` and
`oo_arac_oda_guvenli_yanit()`. Also note `applied_expression_success <- FALSE` at
`filters.R:350` assigns in the *handler* frame and is dead code.

### D6 · S1 · RLS fails **OPEN** when a declared column is missing

`R/helpers_pk_analysis_security_summary.R:141,150,159`:

```r
if (col_name %in% names(filtered_data)) { filtered_data <- filtered_data[...] }
```

If `rls_columns$masraf_yeri_col` contains a typo, or the SQL is edited and the
column renamed, **the security filter is silently skipped and the user sees every
row**. Across 169 hand-maintained query definitions this is a matter of time. Also
`if (yetki == "ADMIN")` (`:133`) errors when `Yetki` is `NA`.

**D6b — the role scope fails open too, and not only transiently.**
`get_user_rls_info()` leaves `allowed_projects` / `allowed_eps` as `NULL` in *two*
cases: the permission query errors (`tryCatch(..., error = function(e) NULL)`,
`:99`/`:112`) **and** it succeeds but returns zero rows for that user
(`if (nrow(user_rows) > 0)`, `:102`/`:115`). `apply_rls_to_data()` then skips the
predicate entirely, because it filters only when the scope is non-`NULL`
(`:148`, `:157`). So a `PY` user whose permission lookup fails — or who is simply
absent from the permission table — sees **every project**. The second case is a
permanent hole, not a transient one.

Together, D6 and D6b are the single most serious finding in the inventory.

### D7 · S1 · The prompt-size budget does not cover the payload

`MAX_ANALYSIS_PROMPT_CHARS` (`core.R:10`) is checked at
`security_summary.R:352` against `summary_text` **only**. The actual payload is
assembled afterwards in the module:

```r
dynamic_preview_rows <- if (nrow(filtered_data) <= 500) nrow(filtered_data) else 500  # module:339
preview_json <- jsonlite::toJSON(preview_data_safe, ...)                              # module:354-356
data_str <- paste0(stat_summary$summary_text, "--- ORNEK SATIRLAR (JSON) ---", preview_json, ...)
```

500 rows × 25 key-repeated columns is roughly 300–600 KB (100K+ tokens), entirely
outside the budget check.

### D8 · S1 · The filtering warning disappears exactly when data is large

`security_summary.R:356` — the over-budget recursion passes only
`max_preview_rows`, `max_total_chars`, `pre_aggregated_columns`, dropping `mode`,
`rls_total_rows`, and `user_filter_applied`. So the `FİLTRELEME UYARISI` block
(`:211-216`) vanishes on exactly the large datasets where a wrong denominator does
the most damage.

### D9 · S1 · Silent degradation on filter-LLM timeout

`filters.R:169` sets an 8-second timeout; on timeout or error the function returns
`list(filters = list(), aggregation = NULL)` — **indistinguishable from "no filter
was needed"**. The user asks about one project, the endpoint is slow, and the tool
confidently analyzes all 4,000 projects without ever saying so. This plausibly
accounts for a large share of "filtering does not work" reports.

### D10 · S2 · Neither selection path can say "I don't know"

* **AI branch** (`module:552-566`): `confidence` is recorded into `all_scores` and
  then never compared to anything. `{"match_id":3,"confidence":10}` is accepted and
  logged as *"AI tarafindan kesin eslesme bulundu"*.
* **Heuristic branch** (`query_selection.R:90-107`): scores are normalized by their
  own maximum, so `max_score_pct` is **always exactly 100** whenever any score is
  non-zero. `passes_threshold <- (max_score >= 2) || (max_score_pct >= 30)` is
  therefore unconditionally TRUE whenever a single description word ≥3 characters
  matches. The heuristic never declines and always reports perfect confidence.

### D11 · S3 · `chat_history` is declared and never read

`select_smart_query(prompt, library, chat_history)` (`module:576`) — verified: the
parameter is not referenced anywhere in the body. Follow-up refinement
(*"peki 2024 için?"*, *"sadece aktif olanlar"*) is structurally impossible.

### D12 · S3 · Dead "general question" guard

`filters.R:311-314` — the condition requires `length(filters) == 0` and the body
sets `filters <- list()`. It has never had an effect. `spesifik_varlik_var`
(`:308-309`) also matches any two capitalized Turkish words (e.g. "Proje Yönetimi").

### D13 · S3 · Query IDs are list positions

`find_best_query_with_ai` (`module:490`) sends `ID: %d` = the index in
`query_library`, and `parsed$match_id` is used as an index (`:553-554`). Reordering
or inserting an entry in `R/library_queries.R` silently changes what every prompt
means. The library already has stable `id` fields (`q001`, `q002`, …) — use them.

### D14 · S3 · Selection call has no timeout and a pointless retry

`find_best_query_with_ai` sets no `request_timeout_sec` (compare `filters.R:169`),
so a hung endpoint blocks the event loop. `module:588-592` then retries the
*identical* deterministic call (same prompt, temperature 0.0) up to twice.

### D15 · S1 · Blocking the Shiny event loop

`pk_analiz_process_request` is called directly from `server_send_message.R:276` on
the main process: SQL fetch + 2 serial LLM calls. Deep mode
(`helpers_deep_analysis.R:519`) is 1 + up to 5 LLM calls **plus** 5 SQL round trips.
On the VM this freezes every other user's session, and it contradicts the
non-blocking contracts `CLAUDE.md` already enforces for file ingestion and the
Bilge Yolaç run pipeline.

### D16 · S3 · `helpers_deep_analysis.R` has diverged from the main path

| Line | Divergence |
|---|---|
| `:289` | `grepl("...", toupper(sql_query_text))` — the **locale-dependent `toupper` bug already fixed** at `module:230-233` with an explicit `useBytes = TRUE` comment. Fixed in one place only. |
| `:536` | Reads `session$userData$system_username %||% "Unknown"` directly, **bypassing `resolve_pk_analysis_username()`** — the SSO-readiness guard `CLAUDE.md` documents as a production safety boundary. Deep mode can perform RLS lookups as `"Unknown"` during SSO startup. |
| `:250-279` | Re-reads SQL files at request time instead of using preloaded `query$sql`, contradicting `module:157-159`. Slow on UNC, and can diverge from what single mode runs. |
| `:295` | Plain `dbGetQuery` instead of `execute_pk_sql_unicode()` — different Turkish-identifier handling between modes. |

### D17 · S2 · Statistics computed and thrown away; most columns never summarized

`security_summary.R:286-306` computes `top5` per categorical column and then uses
only `top5[1]`. Worse, only the **first five** categorical columns are summarized
at all (`head(cat_cols, 5)`), silently, with no note to the model.

### D18 · S2 · Positionally biased sample

`head(data, 500)` is whatever order SQL happened to return. If the query is ordered
by project, the model characterizes "the data" from project A only.

### D19 · S2 · Numbers reach the model in scientific notation

`security_summary.R:257` uses `capture.output(print(num_summary_df, row.names = FALSE))`,
so a budget arrives as `1.234568e+09`. `print` also wraps wide frames across lines,
mangling the table. For financial data this is a correctness problem, not cosmetics.

### D20 · S3 · Contradictory analysis prompt

`module:376-410` demands *"KÖK SEBEP"* analysis and *"sektör benchmarks"* while
supplying neither causal evidence nor any benchmark data, and simultaneously
forbids speculation (`:392`, `:408`). This instructs the model to hallucinate.

### D21 · S3 · Result-contract inconsistency

`module:471` returns `data = secure_data` — the **pre-filter** frame — and no caller
uses it. Dead payload today, wrong data the moment anyone renders it.

### D22 · S2 · Raw ODBC errors leak into chat

`module:253-257` embeds `conditionMessage(e)` (driver/DSN/server detail) into the
user-visible message. `oo_arac_oda_guvenli_yanit()` already exists for exactly this
in the Ortak Oturum path and is not applied here.

### D23 · S3 · SQL gate is a blocklist over a possibly-writable connection

`module:230` blocks `DELETE|DROP|TRUNCATE|ALTER`, while `module:196` *validates*
SQL by accepting `INSERT|UPDATE|EXEC`. `MERGE`, `sp_`, `xp_` are unblocked. Replace
this with a **statement-aware, fail-closed read-only classifier** over a physically
read-only DB principal.

A prefix allowlist and a larger denylist are both insufficient. SQL Server accepts
side-effecting forms such as data-modifying CTEs, `SELECT ... INTO`, `CREATE`, `DENY`,
`REVOKE`, `BACKUP`, multi-statement batches and other syntax that an incomplete token
list will miss. After comments and string literals are handled correctly, the gate must
parse/classify the complete batch and allow only one read-only `SELECT` statement
(including a CTE only when its terminal statement is that `SELECT`), with no `INTO`, no
second statement and no unsupported or unclassified construct. Any parse ambiguity or
unknown statement type is a rejection. The physically read-only principal remains the
primary control; the application classifier is mandatory defense in depth, not a
substitute for least privilege.

**D23 is owned by Phase 1 and is mandatory before any rollout.** The classifier is
implemented in the shared SQL execution path used by v1, v2, deep mode and the metadata
generator. Regression fixtures cover data-modifying CTEs, `SELECT ... INTO`, every
write/DDL/DCL/backup/execute family (`INSERT`, `UPDATE`, `DELETE`, `MERGE`, `CREATE`,
`DROP`, `ALTER`, `TRUNCATE`, `GRANT`, `DENY`, `REVOKE`, `BACKUP`, `RESTORE`, `EXEC`,
`sp_`, `xp_`), multiple statements, comments and string literals. Availability of a
physically read-only principal remains an operator question and a defense-in-depth
improvement; it is not permission to leave the application classifier unimplemented.

### D24 · S3 · No row cap, no caching, no telemetry

Nothing limits result size before it lands in R memory; identical follow-ups re-run
SQL plus both LLM calls; and no record exists of which of the 169 queries are
actually used or how often selection/filtering is wrong.

### 3.9 Claims tested and **withdrawn** — do not "fix" these

Both were plausible from reading and were disproved in R. Re-test before acting on
any similar-looking claim.

| Suspected | Test | Result |
|---|---|---|
| `grepl("\\{.*\\}", ai_text)` at `filters.R:208` rejects multi-line JSON | `grepl("\\{.*\\}", "{\
 \"filters\": []\
}")` | **TRUE** — R's default TRE `.` matches newline. Not a bug. |
| `nchar(ai_text) < 50` at `filters.R:203` rejects valid short JSON | minimal empty-filter JSON = 60 chars; single-filter JSON = 70 chars | Not triggered in practice. Still fragile (prefer structural validation), but not a live defect. |

---

## 4. Target architecture

Each stage produces a **typed result with a status**, so a wrong answer can be
traced to the stage that produced it.

```
 1. Request intake            user prompt + chat history + session identity
 2. Query selection           AI recall → AI precision → capability validation
 3. Pre-execution contract    typed requirements vs declared/generated schema
 4. SQL execution             row-capped, statement-gated, read-only, async
 5. Actual-result + RLS       validate returned columns, then enforce RLS FAIL-CLOSED
 6. Intent & filter plan      LLM → typed filter tree (never R code)
 7. Entity resolution         Turkish fuzzy → canonical values (deterministic)
 8. Filter compilation        typed tree → data.table ops (OR-in-column / AND-across)
 9. Analysis packet           whole-dataset statistics, computed in R
10. Answer composition        LLM prose + R table + R attachment
11. Provenance & telemetry    what ran, what resolved, what degraded
```

Stage 3 never claims to inspect live result columns. It validates only the typed request
against metadata and any declared/generated static schema. Stage 5 begins with a
mandatory comparison against the columns SQL actually returned, before any RLS,
filtering or analysis can proceed; stale or absent generated schema can defer detection
to this point, never skip it.

Stage boundaries are the testing seams. **Stage 6 splits into an impure adapter and a
pure seam**, because filter-plan *inference* is an LLM call:

* **6a — plan inference (impure).** Prompt the model, receive raw text. Tested with a
  stub, not asserted for correctness offline.
* **6b — plan parse + validation (pure).** Turn raw text into a typed tree, reject
  anything invalid. Fully offline-testable against recorded plans.

**Stages 6b–9 are pure functions** and must be offline-testable with no DB, LLM, or
browser. Stages 2 and 6a are LLM adapters; stages 4, 5 and 11 touch the DB. Do not
claim purity for those.

---

## 5. Stage designs

### 5.1 Query metadata contract (`R/library_query_meta.R`)

**Keep this out of `R/library_queries.R`.** 169 × ~40 lines inline would add ~7,000
lines to one file and breach the maintainability ratchet. Store metadata keyed by
stable query `id`, merged at load time in `R/config_sql_loader.R`.

The curated file also declares one **ASCII-safe capability registry** shared by request
requirements and per-column metadata. Capability IDs are stable semantic identifiers,
not labels and not column names:

```r
pk_capability_registry <- list(
  "labor.remaining_hours"   = list(role = "measure", unit = "saat"),
  "labor.planned_hours"     = list(role = "measure", unit = "saat"),
  "progress.completion_pct" = list(role = "measure", unit = "%"),
  "dimension.resource"      = list(role = "dimension", unit = NULL),
  "date.project_start"      = list(role = "date", unit = NULL),
  "date.project_finish"     = list(role = "date", unit = NULL)
)
```

```r
"q042" = list(
  # --- selection ---
  keywords         = c("rol", "atama", "görevlendirme", "assignment", "kaynak ataması"),
  sample_questions = c("X projesinde kimler görevli?",
                       "Rol atanmamış aktiviteler hangileri?",
                       "Elektronik Tasarım'da kaç kişi atanmış?"),
  intents          = c("kim_calisiyor", "atama_eksigi"),
  not_for          = c("bütçe", "maliyet"),

  # --- semantics (THE part no machine can infer) ---
  grain            = "activity_assignment",   # insan tarafından okunur etiket
  grain_columns    = c("ProjeKodu", "AktiviteKodu", "KaynakKodu"),  # satırı benzersiz kılan anahtar
  primary_entity   = "ProjeAdi",
  default_group_by = c("ProjeKodu"),
  default_measures = c("KalanIscilik_sa"),
  row_cap          = 50000L,

  # --- per-column (mostly auto-generated, see below) ---
  column_meta = list(
    ProjeKodu       = list(label = "Proje Kodu", role = "id",
                           entity = "project", match = "exact"),
    ProjeAdi        = list(label = "Proje Adı", role = "dimension",
                           entity = "project", high_cardinality = TRUE,
                           match = "resolve", filterable = TRUE,
                           # Yalnız sentetik/onaylı örnek; üretim hedefleri yerel katmandadır
                           aliases = c("örnek modernizasyon" =
                             "ÖRNEK MODERNİZASYON PROJESİ")),
    KaynakKodu      = list(label = "Kaynak Kodu", role = "dimension",
                           entity = "resource", capability = "dimension.resource",
                           match = "exact", filterable = TRUE),
    Durum           = list(label = "Durum", role = "dimension",
                           filterable = TRUE,
                           domain = list("1" = "Aktif", "0" = "Pasif")),
    BaslangicTarihi = list(label = "Başlangıç Tarihi", role = "date",
                           capability = "date.project_start", filterable = TRUE),
    KalanIscilik_sa = list(label = "Kalan İşçilik", role = "measure",
                           capability = "labor.remaining_hours",
                           unit = "saat", decimals = 1, additive = TRUE),
    TamamlanmaYuzde = list(label = "Tamamlanma", role = "measure",
                           capability = "progress.completion_pct",
                           unit = "%", decimals = 1, additive = FALSE,
                           percent_scale = "points",   # 61.3 demek %61,3
                           aggregate = "weighted_mean",
                           weight_by = "PlanlananIscilik_sa"),
    PlanlananIscilik_sa = list(label = "Planlanan İşçilik", role = "measure",
                           capability = "labor.planned_hours",
                           unit = "saat", decimals = 1, additive = TRUE)
  )
)
```

**Field roles.** `role ∈ {id, dimension, measure, date}` drives summarization.
`additive` decides whether SUM is legal at all. `aggregate ∈ {sum, mean,
weighted_mean, latest, none}` plus `weight_by` prevents averaging averages.
For `weighted_mean`, runtime considers only pairs with a finite measure and a finite,
strictly positive weight. Missing measure/weight pairs and zero weights are excluded
with counts disclosed in packet limitations. Any negative or infinite weight returns
`invalid_weight_set` for that aggregate; if no positive pair remains, return
`weighted_mean_unavailable` and emit no numeric fact. Never silently fall back to an
unweighted mean, zero or `NaN`.
`aggregate = "latest"` additionally **requires `latest_by`** (the ordering column)
and `latest_tie_by` (one or more stable columns whose combined value uniquely orders
rows within a grain at the newest timestamp). Without both, `latest` is not executable
when a query has several date columns or duplicate rows at the newest timestamp.
Rows with `NA` in `latest_by` are excluded. The loader rejects missing tie columns;
runtime validation rejects a newest-timestamp group when `latest_tie_by` is duplicated
or missing, returning an explicit `ambiguous_latest` status instead of choosing a value.
Database return order, `grain_columns` order and a final “first row” fallback are never
valid tie breakers.
`match ∈ {exact, resolve, contains, none}` drives entity resolution — **codes and
sicil numbers must be `exact` and must never be fuzzily altered**. `unit` and
`decimals` drive both number formatting and Excel cell formats.
`percent_scale ∈ {points, fraction}` is **mandatory whenever `unit = "%"`** — without
it an Excel `0.0%` format turns 61.3 into 6130,0% (§5.9). `grain` is what stops
project totals being summed once per activity row.

**Measure, date and output-dimension capabilities are explicit and stable.** Every
measure, date or output dimension that participates in query capability selection
declares exactly one `column_meta[[column]]$capability` from
`pk_capability_registry`. Pass-B requirements use those same IDs in `measures[]`,
`dates[]` and `dimensions[]`. Labels such as "İşçilik", concrete columns such as
`KalanIscilik_sa`, broad invented tokens such as `iscilik`, and a boolean such as
`needs_date = true` are never compared lexically. The loader rejects an unknown
capability ID, a role/unit mismatch with the registry, or two columns exposing the same
capability in one query unless metadata explicitly declares a deterministic
variant-selection rule. This lets the gate distinguish planned from remaining labor,
project start from project finish, and a query that returns people/resources from one
that merely has a project as its subject before SQL.

**Known aliases have one storage and privacy contract.** Alias maps are named character
vectors, where the name is the user-facing alias and the value is the canonical value
from that column's closed vocabulary. The loader normalizes alias keys with
`pk_tr_fold()`, verifies every target canonical value exists when a schema/vocabulary is
available, and rejects collisions: one normalized alias may map to exactly one canonical
value. A duplicate alias pointing to different values is a hard contract error, never
“last one wins.” Code/ID columns remain exact and must not acquire fuzzy aliases unless
a separately reviewed business rule explicitly permits one.

Tracked `R/library_query_meta.R` may contain only synthetic examples or alias mappings
whose canonical targets have been explicitly approved for export to Git. Real VM
project/programme names and other production-derived canonical targets belong only in
the operator-maintained, gitignored `R/library_query_aliases_local.R`. The generator
never writes that file. Exporting an alias map from the VM follows the same explicit
approval/redaction boundary as production metadata and the real golden set; a routine
`git add -A` must never publish it.

#### Four files — generated, local aliases and curated

This split is mandatory. Without it, re-running the generator would destroy human
curation, and the operator would be unable to refresh metadata after a SQL change.

| File | Written by | Tracked in Git | Contents |
|---|---|---|---|
| `R/library_query_meta_local.R` | generator, **every run** | **NO — gitignored** | `column_meta` skeletons derived from production: real column names, types, cardinality, null rates, `high_cardinality`, detected ids/dates/measure candidates |
| `R/library_query_aliases_local.R` | operator on the VM; **never the generator** | **NO — gitignored** | production alias → canonical-value maps containing real internal names; optional |
| `R/library_query_meta_auto.R` | nobody | yes — **committed empty scaffold** | exists only so the Tier-0 boot path works in a fresh checkout; never populated in Git |
| `R/library_query_meta.R` | human | yes | capability registry; `grain`, `grain_columns`, `additive`, `unit`, `primary_entity`, `intents`, `not_for`, `default_measures`, `default_group_by`, `row_cap`, `keywords`, `sample_questions`, plus approved/synthetic `column_meta` overrides |

**The generator must never write to a tracked file or the operator alias file.** Its
output is a production-derived inventory of real column names, cardinalities, null rates
and detected identifiers — exactly the internal schema statistics that are intentionally
absent from the GitHub checkout. Overwriting a tracked scaffold means one later
`git add -A` ships them. So the generator writes only
`R/library_query_meta_local.R`, which is in `.gitignore` (same provenance pattern as
`renv.lock`), and any export of that content off the VM is an explicit, approved action
— never a side effect of committing. This is the same rule as the golden-set split in
§7.

`R/config_sql_loader.R` first merges the scaffold, generated metadata and tracked
curation field by field with **curated values winning**, then applies the optional local
alias overlay only to `column_meta[[column]]$aliases` and runs the same collision/target
validation. The alias overlay cannot change capabilities, grain, RLS, SQL or any other
contract field. The operator can therefore re-run the generator after any SQL change,
or after adding query #170, with zero risk to their alias work or tracked curation.

#### Generation strategy — do not hand-write this

| Tier | How | Effort |
|---|---|---|
| 0 | **Structural-only fallback.** Infer `role` from R type + cardinality, `high_cardinality` from `n_distinct > 50`, and `date` from class. This can support safe inspection/rendering only; stable semantic measure, date and output-dimension capability IDs remain unknown. | 0 |
| 1 | Generator `tools/pk/generate_query_meta.R` (VM-only, NOT in the source manifest) → writes the **gitignored** `R/library_query_meta_local.R`, never a tracked file or `R/library_query_aliases_local.R`. **Also validates declared `rls_columns` against actual result columns, surfacing every D6 hole.** | ~1 day to build, minutes to run |
| 2 | `keywords` + `sample_questions` — **OPTIONAL**, see below | 0–45 s/query |
| 3 | Human-only: capability IDs, `grain`, `additive`, `unit`, `primary_entity`, `intents`, `default_measures` | ~2 min/query |

**Tier 0 has a hard semantic limit that must not be glossed over.** Type and
cardinality inference needs the executed result, which exists only at stage 4, and raw
roles or column names cannot prove that a date means project start rather than finish,
or that a numeric column means planned rather than remaining labor. Therefore:

* Pass A/B may rank a metadata-free query, but when `requirements.measures`,
  `requirements.dates` or `requirements.dimensions` is non-empty and the candidate
  lacks those curated/generated capability mappings, execution stops before SQL with
  `capability_check = "unknown_no_semantic_metadata"`. The user receives an explicit
  metadata-required/clarification response; the tool never guesses from labels or raw
  column names and never answers from that candidate.
* A post-execution check may verify only that **already declared** capability columns
  physically exist and have compatible structural roles/types. It must not assign or
  infer semantic capability IDs from the returned schema.
* The generator's `describe` mode is the intended fix: it produces a static column
  schema without executing the query, while Tier 3 curation assigns the semantic IDs.
  Those mappings are a prerequisite for requests with semantic capability requirements,
  not optional polish.

#### Running the generator (operator instructions)

RStudio on the Windows VM, matching the existing `tests/scripts/*.R` convention:

```r
Sys.setenv(MERGEN_PK_META_MODE = "sample")   # or "describe"
source("tools/pk/generate_query_meta.R", encoding = "UTF-8")
```

Not SSMS (it must walk `query_library` in R), not PowerShell. It uses the normal
`get_connection()` path and the SQL already preloaded by `R/config_sql_loader.R`.

Two modes, because some production queries are expensive:

* **`describe`** — uses `sys.dm_exec_describe_first_result_set` to obtain column
  names and types **without executing** the query. Fast, zero DB load, no cardinality.
* **`sample`** (default) — `TOP <MERGEN_PK_META_SAMPLE_ROWS>` (default 500) per query
  for cardinality, null rate, ID detection and `high_cardinality` flags.

A 500-row sample **cannot** tell a 501-row result from a five-million-row one, so it
cannot support a row-cap finding on its own. Either run a bounded probe
(`SELECT COUNT(*)`, or `TOP (row_cap + 1)` and check whether the extra row appears) or
record the cardinality as **`unknown`** in the health report. Never report a row-cap
pass that the sample could not actually establish.

Hard requirements for the generator:

* **`source(...)`-safe**: never call `quit()`.
* **Resumable**: per-query state file, so a run interrupted at query 120 resumes there.
* **Never aborts on one failing query** — record the failure and continue.
* **Read-only**: every statement passes the same Phase-1 statement-aware SQL classifier
  as production execution, then runs through a physically read-only principal when one
  is available. Never DDL, writes or EXEC.
* **Secret-safe**: no DSN, credential, or connection string in output or logs.
* **Turkish-safe**: results pass through `normalize_pk_dataframe_utf8()`; the emitted
  R file is UTF-8 with Turkish comments.

#### Query-library health report

The generator also writes `artifacts/pk-meta/<timestamp>/health.json` + a readable
summary. This is valuable **before any metadata is consumed**, because it audits all
169 queries at once:

* declared `rls_columns` that do not exist in the actual result → **every D6
  fail-open hole, enumerated**
* queries that error, return zero rows, or return more than `row_cap`
* duplicate or missing `id` values
* `date_columns` / `pre_aggregated_columns` naming columns that do not exist
* columns whose type differs from what metadata declares

#### On `keywords` / `sample_questions` — do NOT use the on-prem LLM

These two fields are **optional**. Trigram+IDF retrieval over `name` + `description`
plus two-pass AI selection (§5.2) work without them; they improve selection quality
but are never required. Three acceptable paths:

1. **Skip.** A permanently reasonable choice.
2. **Draft in a capable cloud assistant session**, human-reviewed. Export a compact
   `id, name, description, columns` CSV, have the draft produced there, paste into
   `R/library_query_meta.R`, and edit. **The operator must first confirm that query
   names and descriptions are permitted to leave the corporate network** — they are
   library metadata rather than data, but may reveal programme names. If that answer
   is no, use option 1 or 3.
3. **Organic.** When telemetry shows a query was mis-selected, add two keywords to it.
   Self-correcting, zero upfront cost.

Do **not** generate these with the local on-prem models. Sub-par synonym sets would
silently degrade retrieval, and the failure would be invisible until it caused a
wrong query selection.

**Prioritize by telemetry, not by list order.** Ship Phase 0 telemetry first; after a
week the top ~30 queries will cover most traffic. Enrich those; the tail can stay at
Tier 0/1 indefinitely.

**Startup validation** is split into schema-independent and schema-dependent checks:

* **Always fail the build** for duplicate ids, missing SQL, malformed metadata,
  unknown `role`/`aggregate` values, invalid alias collisions, unknown capability IDs,
  capability role/unit mismatches, or `weight_by` pointing at a declared non-measure.
* **Validate `rls_columns`, `column_meta` keys, alias targets and other output-column
  references at startup only when a declared/generated schema is available.** Before
  the VM-only generator has produced that schema, record
  `schema_validation = "pending_no_schema"` and allow the documented Tier-0 boot path;
  do not execute every production query merely to make startup validation possible.
* **At request time, after SQL returns and before RLS or analysis, validate those same
  references unconditionally against the actual result.** A missing declared RLS
  column always fails closed. The absence of startup schema can defer detection, never
  weaken request-time enforcement.

The generator health report remains the VM-wide way to surface every pending
schema-dependent mismatch before users encounter it.

### 5.2 Query selection

Replace the current AI-or-heuristic split. **The lexical scorer must never make a
selection decision** — a shortlist that drops the correct query is an unrecoverable
silent failure, which is exactly the bottleneck to avoid.

**Pass A — recall (LLM, full library).** Send **every** query as one compact line
carrying enough semantics to be findable:
`id | name | short description | keywords | sample_questions[1:2]`. The sample-question
segment is bounded (at most two questions and a fixed character budget per query), so
169 queries remain comfortably within the 256 K context while terminology that exists
only in a sample question is still visible during recall. Resolve
`MERGEN_PK_SELECT_RECALL_N` through the §9 precedence contract (default 5), validate it
as a positive bounded integer, and ask for exactly that many candidate **ids**. Full
recall by construction over the supplied semantic fields.

**Do not reduce Pass A to `id | name`, and do not postpone all sample questions to
Pass B.** A user's terminology frequently appears only in a query's description,
keywords or sample questions; if Pass A cannot see that terminology, Pass B can never
recover a candidate that was omitted. If the payload ever needs shrinking, truncate
individual descriptions and questions under deterministic per-field budgets — never
drop the fields globally.

**Pass B — precision (LLM, resolved recall candidates).** Send exactly the candidates
returned under the resolved `MERGEN_PK_SELECT_RECALL_N` value with full description,
`sample_questions`, column labels, `intents`/`not_for`, and the last 2 conversation
turns. No literal five may remain in either pass. Return:

```json
{"id":"q042","confidence":78,"reason":"...",
 "alternates":[{"id":"q108","confidence":63},{"id":"q055","confidence":41}],
 "missing_info":null}
```

**Alternates must carry their own confidence values.** With only ids, deterministic R
code cannot compute the runner-up margin, cannot enforce
`MERGEN_PK_SELECT_MIN_MARGIN`, and cannot tell a clear winner from a near-tie — which
would leave the main safety gate against confidently running the wrong financial query
unimplementable.

**Then, deterministically:**

* **Stable ids only.** Never list positions (D13).
* **Capability validation needs a typed statement of what the request needs.** The
  gate cannot compare prose against metadata. Pass B therefore also returns a
  `requirements` object — the entity kind, stable measure capability IDs, exact date
  capability IDs, required output-dimension capability IDs and grouping the question
  implies — which R validates deterministically against the candidate's `column_meta`:

  ```json
  "requirements": {"entity": "project",
                   "measures": ["labor.planned_hours"],
                   "dates": ["date.project_start"],
                   "dimensions": ["dimension.resource"], "group_by": null}
  ```

  Every `requirements.measures[]`, `requirements.dates[]` and
  `requirements.dimensions[]` value must be an allowlisted ID from
  `pk_capability_registry`, and the selected query must expose that exact ID through a
  column's `capability` field with the matching role. R never infers equivalence from
  labels or column names. Thus planned labor cannot be confused with remaining labor, a
  query exposing only `BitisTarihi` cannot satisfy *"2024'te başlayan projeler"*, and
  declaring `entity = "project"` cannot satisfy *"projede kimler görevliydi"* unless a
  person/resource output-dimension capability is also present.

  Without this typed result there is no structured input to validate: intake is raw
  prose and the typed filter plan does not exist until stage 6a, after SQL. A confident
  model pointing at a query without the exact required capability cannot answer the
  question, and the gate must prove that **before** execution.
* **Confidence is a signal, not a probability.** Combine it with the margin over the
  runner-up, capability validation, and lexical agreement.
* **Below threshold, or alternates too close → ask.** Render the top 3 as clickable
  chips. Executing nothing beats executing the wrong financial query.
* **Timeout on both passes** (D14). Retry only on malformed/timed-out output, and
  make the retry a *repair* attempt that includes the validation error — never an
  identical replay.

**Lexical retrieval (`R/helpers_pk_query_retrieval.R`) — non-deciding roles only:**
degraded mode when the LLM is unavailable (show top 3 as options, never auto-run);
a disagreement signal that lowers confidence; golden-set diagnostics.

Build it as **character 3-gram cosine similarity with IDF weighting** over
Turkish-folded `name + description + keywords + sample_questions + column labels`.
Trigrams absorb Turkish agglutination without a stemmer or synonym list
(`projelerin`/`projeye`/`projedeki` all share `pro`,`roj`,`oje`); IDF stops
high-frequency words like `proje` from dominating.
**Delete the 7 hardcoded `grepl` domain bonuses** at `query_selection.R:65-71` and
the normalize-by-max scoring that guarantees 100% (D10).

### 5.3 Intent and filter plan — a typed tree, never R code

The LLM returns a **typed structure**; it never returns executable text and never
returns a canonical DB value.

```json
{
  "aggregation": {"kind": "list"},
  "filter": {
    "op": "AND",
    "children": [
      {"op": "OR", "children": [
        {"column": "ProjeAdi", "match": "resolve", "phrase": "elektronik harp modernizasyon"},
        {"column": "ProjeAdi", "match": "resolve", "phrase": "radar modernizasyon"}
      ]},
      {"column": "Durum", "match": "domain", "phrase": "aktif"},
      {"column": "BaslangicTarihi", "match": "range",
       "from": "2024-01-01", "to": "2024-12-31"}
    ]
  }
}
```

Rules: allowed node ops are `AND`/`OR`/`NOT` plus leaves; leaf
`match ∈ {exact, resolve, domain, contains, range, gt, lt, in}` — **`domain` is
required**, since it is what the canonical example above uses for semantic categorical
filters such as `Durum = aktif`; R resolves the phrase through `column_meta$domain` and
rejects the leaf when the column declares no domain map or the phrase matches no label;
**`phrase` carries the user's own words**,
never a guessed DB value; every `column` must exist and be `filterable` in
`column_meta` or the leaf is rejected with a logged reason (never silently dropped —
D9). Depth and node count are bounded. `filter_expression` and `eval(parse())` are
removed entirely (D5).

Turkish relative dates (*"son 3 ay"*, *"geçen yıl"*, *"2024 Q3"*) are extracted as
phrases and resolved **in R** — never by model arithmetic.

**Anchor them to the request timestamp in the business timezone (Europe/Istanbul,
fixed +3), not to the dataset's date range.** P6 plans routinely contain
future-dated planned records, and an extract can be days or weeks stale; anchoring
*"son 3 ay"* to `max(BitisTarihi)` would silently shift the window by months or years
and produce statistics for the wrong period. The dataset range is used only to report
coverage and to warn when the requested interval falls partly or wholly outside the
available data (*"İstenen aralığın bir kısmı veride yok"*).

### 5.4 Entity resolution (`R/helpers_pk_entity_resolver.R`)

Deterministic, pure, offline-testable. Resolves a user phrase against the **closed
vocabulary** of a column's actual distinct values.

**Normalization pipeline (shared `pk_tr_fold()` — the single Turkish authority):**
Unicode NFC → locale-pinned Turkish case fold → strip apostrophe clitics
(`ANKA'nın`, `PGRM'deki`, `Ahmet Yılmaz'ın`) → strip common suffixes for matching only
(`-nin`, `-de`, `-deki`, `-siyle`) → collapse punctuation and whitespace → token set.
**`pk_tr_fold()` must replace every `tolower()` and `ignore.case = TRUE` in this
subsystem** (D3).

**The fold must never call bare `tolower()`.** Mapping only `İ` and `I` and then
delegating to `tolower()` leaves `Ş Ğ Ü Ö Ç` at the mercy of the process locale and
encoding, so a C-locale CI run and the Turkish Windows VM can produce different
resolver keys — the exact failure this helper exists to prevent, and one `CLAUDE.md`
already documents for `toupper`/`tolower`.

Use **`stringi`** (already in `required_packages`), which is ICU-based and takes the
locale as an explicit argument rather than reading the process locale. NFC composition
must happen before lowercasing; `enc2utf8()` alone does not make canonically equivalent
code-point sequences identical:

```r
# Türkçe katlama; NFC ve locale açıkça verilerek yerel ayardan bağımsız tutulur
pk_tr_fold <- function(x) {
  x <- stringi::stri_trans_nfc(enc2utf8(x))
  stringi::stri_trans_tolower(x, locale = "tr")
}
```

The minimal helper lands in **Phase 3a**, before metadata aliases are loaded and
validated. Phase 1 consumes it to replace unsafe comparisons; Phase 4 builds the full
resolver/token/suffix behavior on top of the already-owned helper. No phase duplicates
or privately redefines the fold.

Two alternatives were tested and rejected — do not reintroduce them:

| Rejected approach | Why it fails |
|---|---|
| `chartr(UPPER, lower, x)` | Operates on **bytes** when the string is not UTF-8-marked in a non-UTF-8 locale. Measured: `nchar()` reported 38 instead of 32 for the 32-character Turkish alphabet, and the output was mojibake. |
| Manual `utf8ToInt` codepoint mapping | Depends on how each string happens to be encoding-marked. Measured: folded ASCII and `I→ı` correctly but left `İ`, `Ş`, `Ü`, `Ö`, `Ç` untouched. |

Verified behavior of the `stringi` form: `İSTANBUL→istanbul`, `KALIP→kalıp`,
`ŞGÜÖÇ→şgüöç`, byte-identical under both C and Turkish `LC_CTYPE`; composed and
canonically decomposed spellings of the same Turkish text produce the same key.

**Also build an ASCII-folded secondary key.** Users routinely type without Turkish
characters (`kalip` for `kalıp`, `elektronik` for `elektronİk`). Keep a second
diacritic-stripped key (`ı→i`, `ş→s`, `ğ→g`, `ü→u`, `ö→o`, `ç→c`). An exact match on
this secondary key scores **90**, below a known alias (95) and a true Turkish-fold exact
match (100), but above token containment. If the same ASCII key maps to more than one
canonical Turkish value, return every colliding value tied at 90; never select one by
iteration order. The normal ambiguity-margin rule then requires clarification.

**Scoring cascade** (`stringdist` is already in `required_packages`):

| Tier | Rule | Score |
|---|---|---|
| 1 | Exact Turkish-fold match | 100 |
| 2 | Known alias from the validated local/approved alias registry | 95 |
| 3 | Exact ASCII-secondary-key match | 90 |
| 4 | All user tokens contained, order-free | 85–89 |
| 5 | Token-set Jaccard ≥ 0.6 | 60–84 |
| 6 | Normalized edit distance ≤ 0.2 (typos) | 50–69 |

Token-set similarity outranks plain edit distance for long project names, where the
right words appear in a different order. Contract fixtures include `kalip → kalıp`
(score 90) and an ASCII-key collision that must clarify rather than auto-select.

**Decision policy — this is the safety mechanism, not the scoring:**

| Situation | Action |
|---|---|
| 1 | Exact code / ID match | Filter automatically |
| 2 | Top ≥ `MERGEN_PK_RESOLVE_MIN_SCORE` **and** margin over #2 < `MERGEN_PK_RESOLVE_AMBIGUITY_MARGIN` | **Ask.** Render the tied candidates as chips, with a "Tümü" option |
| 3 | The user's phrase is explicitly plural and 2–5 candidates score ≥ `MERGEN_PK_RESOLVE_MULTI_SCORE` | **Ask**, defaulting the candidate chips to "Tümü"; do not let a high-scoring first candidate suppress the rest |
| 4 | Request is singular (or lacks several strong candidates), Top ≥ `MERGEN_PK_RESOLVE_AUTO_SCORE`, and margin over #2 is clear | Filter automatically on that single canonical value |
| 5 | `MERGEN_PK_RESOLVE_MIN_SCORE` ≤ Top < `MERGEN_PK_RESOLVE_AUTO_SCORE` with a clear margin | **Ask for confirmation**, with that one candidate pre-selected: *"Şunu mu kastettiniz: …?"* Never auto-filter on it |
| 6 | Top < `MERGEN_PK_RESOLVE_MIN_SCORE` **and** the entity is the subject of the question | **Do not analyze.** Report that the value could not be resolved and offer the nearest candidates |
| 7 | Top < `MERGEN_PK_RESOLVE_MIN_SCORE` and the entity was a secondary refinement | Proceed unfiltered **with prominent disclosure** |

Rule 5 exists because it is the **most common** outcome for long Turkish project names
matched by token-set or edit distance — for example, a top score of 75 against a
runner-up of 20 can be below the configured auto threshold, is not ambiguous, is not
plural, and is not unresolved under the configured minimum. Without it the ordered
table has a fall-through hole in exactly the band real traffic lands in, and the
"first match wins" safety claim would be false. A one-click confirmation is the correct
action: it neither guesses nor discards a probably-correct match.

**Every branch uses the resolved configuration values; no literal `40`, `85`, or other
default may be embedded in the decision code or branch descriptions.** Tests override
`MERGEN_PK_RESOLVE_MIN_SCORE` and `MERGEN_PK_RESOLVE_AUTO_SCORE` to prove the policy
remains exhaustive under supported configurations.

**Validate threshold relationships at startup before this table can run.** All score
values must be finite and within `0..100`, with
`MIN_SCORE <= MULTI_SCORE <= AUTO_SCORE`; the ambiguity margin must be within `0..100`
and max candidates within `1..5`. An invalid or unparsable configuration is a fail-safe
contract error: disable automatic resolution for the tool and surface a clear operator
error rather than evaluating partially ordered branches. Contract tests include
`MIN_SCORE = 90, AUTO_SCORE = 85` and prove that no below-minimum candidate can be
auto-accepted.

**Rules are evaluated in order and the first match wins — the order is the safety
mechanism, not the scores.** Ambiguity (rule 2) is checked before plural expansion, and
the plural multi-candidate rule (rule 3) is checked before single-candidate
auto-acceptance (rule 4). Thus a plural family request with scores 92, 81 and 76 cannot
silently collapse to the 92-point candidate merely because it clears the auto threshold.
Likewise two candidates scoring 88 and 85 trigger clarification rather than an automatic
union. A union is applied only when the user picks "Tümü", or when the filter plan
contained several *distinct* phrases that each resolved unambiguously.

The last two rows are deliberate. Analyzing 4,000 projects when the user asked about
one is misleading even with a disclaimer, because every figure in the prose answers a
different question. But a failed secondary refinement should not block an otherwise
useful answer. **Decide by the entity's role in the question, not by a single global
rule.**

Filtering is always applied as an **exact `%in%` on resolved canonical values** —
fuzziness resolves *which values*, never *which rows*. This is what stops fuzzy
matching from becoming a new filtering problem.

### 5.5 Filter compilation and execution

Pure function: typed tree + resolved entities + `column_meta` → `data.table`
operation, with full multi-value support (D2) and Turkish-folded comparison (D3).

**The compiler preserves the validated tree exactly.** `AND`, `OR` and `NOT` nodes are
compiled as written; an explicit cross-column disjunction such as
`ProjeKodu = "P1234" OR Departman = "Ankara"` must remain a disjunction. Forcing AND
across differing columns would silently rewrite the user's Boolean expression and
return a wrongly narrowed result.

**"OR within a column, AND across columns" is the normalization rule for FLAT filter
lists only** — the legacy shape that caused D1. When a plan arrives as a flat list with
no explicit tree (or from the v1 compatibility path), group leaves by column and AND
across column groups. Within one column:

* OR alternative equality/`in`/`contains` values that represent substitute choices.
* **AND compatible lower and upper bounds** (`>`, `>=`, `from` with `<`, `<=`, `to`) so
  `Tarih >= 2025-01-01` plus `Tarih <= 2025-12-31` becomes an interval, not the almost
  universal predicate `>= start OR <= end`.
* Keep explicit exclusions as NOT/AND constraints.

Reject contradictory duplicate bounds with a disclosed validation error. Once an
explicit tree exists, no flat-list regrouping rule applies.

Additional required behaviors:

* **No-op detection.** A filter matching ≥95% of rows is reported as ineffective.
* **Zero-match handling** per the §5.4 policy (D4) — never an empty screen with no
  explanation.
* **Provenance record per leaf:**
  `{requested_column, user_phrase, canonical_values, match_method, confidence,
    logical_group, rows_before, rows_after, warnings}`.
  This structure feeds the answer footer, the Excel `Bilgi` sheet, and telemetry.

### 5.6 RLS hardening

* **Fail closed on the column** (D6): a declared RLS column absent from the result set
  aborts the query with a clear Turkish error and a loud log line. Never silently skip.
* **Fail closed on the role scope** (D6b): a role that implies a scope (`PY`, `KY-P`,
  `DIR-P`) must resolve a **non-`NULL`** scope before any predicate is skipped. An
  *unavailable* scope (permission query errored) aborts; an *empty* scope (user absent
  from the permission table) yields **zero rows**, never all rows. Distinguish the two
  in the user-facing message — "yetki bilgisi alınamadı" versus "tanımlı projeniz
  yok" — and cover both in `test-pk-rls-failclosed-contract.R`. Today both cases leave
  the scope `NULL` and silently disable the filter.
* Validate `rls_columns` at startup **when a declared/generated result schema is
  available**. When it is not, mark the check pending and perform the same validation
  unconditionally against the actual result before request-time RLS. No-metadata boot
  support must never become no-validation execution.
* Guard `NA` in `Yetki` (`security_summary.R:133`).
* **Do NOT reuse `pk_tr_fold()` for authorization codes.** That pipeline strips
  clitics and suffixes and collapses punctuation (§5.4), which is correct for matching
  a project *name* and dangerous for a *code*: two distinct `MasrafYeriKodu` or
  `EPSKodu` values differing only by punctuation or a suffix-like ending could collapse
  to the same key and admit rows outside the user's scope. Use a separate, deliberately
  minimal `pk_rls_code_norm()` — UTF-8 normalization, trim, and only explicitly
  approved case handling. No suffix stripping, no clitic stripping, no punctuation
  collapsing. If two distinct authorization codes ever normalize to the same key, that
  is a **hard error**, not a merge; assert it in the contract test.
* Record the RLS scope in provenance (rows before/after, which rule applied).
* **Longer term:** push predicates into SQL or use secured views, so unauthorized
  rows never enter R memory.

### 5.7 Analysis packet (`R/helpers_pk_analysis_packet.R`)

Replaces `generate_statistical_summary()`. **Computed over ALL rows**, never a
sample. The LLM receives facts, not data.

```
Scope           selected query (id + name), grain, primary key, freshness
Filters         applied filters, resolved canonical entities, rows before/after RLS & filter
Coverage        null rate per column, duplicate count at declared grain
Numeric         per additive measure: n, sum, mean, median, p5/p25/p75/p95, min, max, sd,
                IQR-outlier count.  Non-additive measures: NEVER summed; weighted mean
                where `aggregate = "weighted_mean"`, under the invalid-weight contract
Categorical     per dimension: distinct count, top-10 values with counts AND shares,
                "Diğer (N)" roll-up
Dates           range + rows-per-month/quarter histogram
Groups          group-by over `default_group_by` × `default_measures`, sorted,
                top 15 + "Diğer"
Cross-tabs      only those relevant to the detected intent
Anomalies       IQR outliers, threshold breaches, rule violations
Examples        ~20-40 rows: top-N + bottom-N by primary measure + outliers +
                fixed-seed STRATIFIED sample  (never head(500) — D18)
Limitations     what this query cannot answer; what was truncated
```

Every numeric fact also carries a stable `fact_id` plus semantic provenance:
`measure_capability`, display label, exact value, unit, aggregation, authorized/filter
scope signature, grouping keys and time window. These fields are consumed by the
numeric-provenance validator in §5.11; a bare number without its meaning is not a
sufficient fact contract.

**Formatting:** every number rendered explicitly with `formatC`/`format` using
`decimals` and `unit` from metadata. **No `capture.output(print(...))`** (D19). Use
one consistent naming system (`label` from metadata) for both the statistics and the
example rows — currently the summary prettifies names while the JSON does not.

**Budget accounting:** one accountant over the **entire assembled prompt** — summary
+ tables + example rows (D7). Budget derives from the model's context window, not a
hardcoded constant. Degrade in priority order: example rows → top-K depth →
low-signal columns; **always state what was omitted**. The `FİLTRELEME UYARISI` must
survive every degradation path (D8).

**Very broad queries — partition the narrative, never the global statistics.**
Medians, p5/p25/p75/p95, distinct counts and IQR-outlier counts **cannot** be
reconstructed from per-partition summaries, especially when an entity appears in
several departments or months. Merging them would silently contradict the "computed
over ALL rows" guarantee. Therefore:

* **Global statistics are always computed in one pass over the full vector.** R handles
  millions of rows for `quantile`, `median` and `uniqueN` without partitioning.
* **Partitioning applies only to group-level breakdowns** (per department / programme /
  month), which are per-partition by definition and merge trivially.
* If a dataset is ever genuinely too large for a single pass, retain **exact mergeable
  state** (count, sum, sum of squares, min, max, full value histograms, distinct-value
  hash sets) or an explicitly documented sketch — and **label the affected statistics
  as approximate** in the packet. Never present a merged approximation as an exact
  whole-dataset figure.

The model performs narrative synthesis over reconciled figures — never arithmetic
map-reduce.

### 5.8 Answer composition — prose + table + attachment

| Part | Owner | Rule |
|---|---|---|
| Prose | LLM | May cite only structured facts present in the packet. Computes nothing. |
| Table | R | Deterministic render. **Never regenerated by the model.** |
| Attachment | R | Exact authorized, filtered result when the export contract can preserve every row; otherwise multipart export or explicit refusal — never a silently capped file described as complete. |

**Thresholds (configurable):**

Rules are **ordered and first-match wins**, so the predicates cannot overlap:

| # | Condition | Rendering |
|---|---|---|
| 1 | User says *liste / döküm / rapor / excel / dışa aktar* | **XLSX attachment** + 10-row inline preview |
| 2 | rows > `MERGEN_PK_DT_MAX_ROWS` **or** cols > `MERGEN_PK_INLINE_MAX_COLS_DT` (12) | **XLSX attachment** + 10-row inline preview |
| 3 | rows ≤ `MERGEN_PK_INLINE_MAX_ROWS` (15) **and** cols ≤ `MERGEN_PK_INLINE_MAX_COLS` (8) | Markdown table inline |
| 4 | otherwise | Scrollable `DT` widget in the bubble (same seam as ChartLab's `wire_chart_output`) |

Without the ordering, a 100-row × 20-column result satisfies both "≤ 200 rows" and
"> 12 cols", and two implementations would render it differently.

**Remove the "produce a markdown table" instruction** from the system prompts
(`module:400-403`, `:433-436`). It is the highest-risk, lowest-value LLM task in the
tool and the direct source of rounded and invented figures.

**Epistemic labelling.** Replace the contradictory *"kök sebep + benchmark, ama
spekülasyon yapma"* prompt (D20) with an explicit taxonomy the model must use:
**Gözlem** (computed fact) · **Yorum** (defensible reading) · **Olası açıklama**
(hypothesis needing verification) · **Öneri** · **Sınırlılık**. A hypothesis must
never be presented as a proven root cause, and benchmarks must not be requested
unless benchmark data is supplied.

**Provenance footer** on every answer, in the app's existing `Kaynakça` style:
which query ran (id + name), applied filters, resolved entities, row counts, any
degradation, and the attachment link. Users can only catch a wrong query selection if
the selection is visible.

**The user-visible footer must start from the user's authorized population.** Showing
the pre-RLS total (e.g. *"41.930 → 12.405 (yetki) → 312"*) discloses how many rows exist
**outside** the requester's scope. Row existence and aggregate counts beyond a user's
authorization are themselves protected information, and they can be probed across
queries and filters to map data the user cannot read. So a scoped user sees
*"12.405 → 312 (filtre)"*; the pre-RLS figure is retained only in restricted server
telemetry. An `ADMIN` whose scope is the whole set naturally sees the full number
because it *is* their authorized population — the rule is "start from what you may
see", not "hide a specific field".

### 5.9 Excel export (`R/helpers_pk_export_xlsx.R`)

**Dependencies.** `writexl`, `readxl`, `DT`, `stringdist` are already in
`required_packages`; `openxlsx` is **not**. Build on `writexl` as the baseline —
correct native types, multiple sheets, zero new dependency (`renv.lock` is
VM-generated, so a cloud session must not add packages). Gate formatting
enhancements (number formats, freeze panes, autofilter, column widths) behind
`requireNamespace("openxlsx")`: plain-but-correct without it, polished with it.

**Percentage correctness must not depend on the optional package.** With `writexl`
alone there is no cell style, so `0.613` would display as `0.613` and `61.3` as a bare
number — neither is the required `61,3%`. Define the two paths explicitly:

| Path | Stored value | Header | Result |
|---|---|---|---|
| `writexl` baseline | point-scaled numeric `61.3` | `Tamamlanma (%)` | numeric, sortable, unambiguous |
| `openxlsx` present | fraction `0.613` + `0.0%` style | `Tamamlanma` | renders `61,3%` |

Both are numeric and neither can be misread by two orders of magnitude. State the
acceptance criterion **per path** rather than requiring a rendering the baseline cannot
produce.

**Correctness requirements — these are what prevent "corrupted / wrong" files:**

1. **Native types.** Numeric as numeric, Date as Date. Never `as.character()`
   everything — this is the primary cause of "the Excel table is wrong".
2. **Number formats from metadata.** `unit = "TL"` → `#,##0.00`; hours → `#,##0.0`.
   Another dividend from §5.1.
   **Percentages need an explicit scale.** Excel's `0.0%` format multiplies the stored
   value by 100, so a percentage-point value such as `TamamlanmaYuzde = 61.3` written
   with `0.0%` displays **6130,0%** — two orders of magnitude wrong, in a file destined
   for management reporting. `column_meta` must declare
   `percent_scale ∈ {points, fraction}` whenever `unit = "%"`. The baseline fixture
   must round-trip a numeric `61.3` under a `Tamamlanma (%)` header. The formatted
   fixture, run only when `openxlsx` is available (or made required), must store `0.613`
   with a `0.0%` style and inspect the value/style pair; `readxl` alone cannot prove
   rendered presentation. Real Excel rendering remains a VM gate. Neither path may
   produce 6130,0%.
3. **Values only, no formulas.** Formula writing is what triggers Excel's repair
   dialog.
4. **Turkish.** XLSX is UTF-8 XML internally and is safe *provided* strings pass
   through `normalize_pk_dataframe_utf8()` first. Sanitize sheet names (≤31 chars,
   no `[]:*?/\`); Turkish characters are allowed in them.
5. **Three sheets:** `Veri` (full data), `Özet` (the R-computed statistics),
   **`Bilgi`** (provenance: query id/name, run timestamp, user, applied filters,
   resolved canonical entities, RLS scope, **authorized rows before user filters**,
   rows after user filters, truncation notice). The pre-RLS population is restricted
   telemetry only and must never be written into XLSX/CSV or another user-visible
   artifact for a scoped user. The `Bilgi` sheet is what makes a figure defensible when
   it is pasted into a management report without disclosing data outside the user's
   authorization.
6. **Export-part limit, not a completeness loophole.**
   `MERGEN_PK_EXPORT_MAX_ROWS` (suggest 100,000) is the maximum rows in one exported
   sheet/file part, well below Excel's 1,048,576-row sheet limit. When the exact
   authorized filtered result is larger, split it deterministically into numbered
   `Veri_001`, `Veri_002`, … sheets or numbered XLSX files and include a manifest in
   `Bilgi`; every row must appear exactly once. If the full result cannot be represented
   within Excel's hard limits or the configured safe file/part ceiling, **refuse the
   export and ask the user to narrow the request**. Never truncate at the export limit
   while promising a complete attachment. The prose and `Bilgi` state part counts or
   the explicit refusal.
7. **Verify before serving.** Read every written part back with `readxl`; assert total
   row count across parts, per-part column count, no duplicate/missing partition rows,
   and sample-column checksums. On failure **do not serve the file** — fall back to
   UTF-8-**BOM** CSV parts (Excel needs the BOM to detect UTF-8, the same rule as the
   Bilge Yolaç `.txt` contract) and say so in the answer.
8. **Neutralize spreadsheet formulas in the CSV fallback, without corrupting typed
   values.** Apply neutralization only to cells whose **original column is character**
   and whose text begins with `=`, `+`, `-`, `@`, a tab or a carriage return. Prefix
   those character values with a single quote (or wrap them) before writing, leaving
   ordinary Turkish text untouched. Numeric, integer, logical, Date and POSIX columns
   retain their native serialization; a legitimate numeric `-125.50` must remain a
   number, while a character value such as `-KAPALI-` is neutralized. Fixtures must
   cover both cases. This is CSV-specific: `writexl` stores strings as strings, so the
   XLSX path is unaffected.

**Serving — security requirement.** These exports are **RLS-filtered per user**.
They must **NOT** be written into `bilge_yolac_downloads/`, which is registered
globally with `addResourcePath` — a guessable URL there would expose one user's
authorized rows to another. Serve session-scoped via `session$registerDataObj`
(the pattern `mergen_serve_image_data_url()` uses in `R/helpers_markdown_safety.R`)
or a `downloadHandler`. Clean up on session end with the existing
`register_session_cleanup_on_end()` / `safe_unlink_if_exists()`.

**Saved-chat hydration must be defined, not left to chance.** An analysis message is
persisted, the session ends, its session-scoped artifact is deleted — and reopening
that chat would leave a dead download card and an unbound `DT` output. Contract:

* **Do not silently persist artifacts long-term.** RLS scope can change between the
  original run and the reload, so re-serving a stale file could expose rows the user is
  no longer authorized to see. Expiry is the safe default.
* On hydration, a card whose artifact no longer exists renders an explicit **expired**
  state — *"Bu analiz ekinin süresi doldu; yeniden çalıştırın"* — with a re-run action,
  never a broken link.
* The `DT` output needs its own rebind seam on saved-chat hydration, mirroring
  `chat_rebind_all_charts()`. `R/server_observers_saved_chats.R` currently rebinds only
  charts, so a PK table would silently fail to render after reload. Add
  `pk_rebind_all_tables()` alongside it and wire it in the same `session$onFlushed`
  pass.
* If long-lived artifacts are ever wanted, they must live in an authorization-checked
  per-user store with retention, and re-authorization must be re-evaluated at download
  time — not merely at creation time.

**UI.** A download card in the same visual language as `.cc-generated-file-card`,
but PK-specific: icon, filename (`Aktivite_Rol_Atamalari_P1234_20260801.xlsx`),
row × column count, file size, "İndir". Dark and light themes. Any new CSS/JS must
be registered in `R/config_ui_assets.R` **and** assigned a zone in
`R/config_ui_asset_zones.R`.

### 5.10 Non-blocking execution

Move SQL + LLM work off the Shiny event loop (D15) using
`tracked_future_promise(..., dependency_mode = "explicit")` with a fully enumerated
`globals` list — the pattern `CLAUDE.md` already mandates for file ingestion,
Bilge Yolaç preparation, and STT.

Requirements: never serialize a Shiny session, reactive value, or DB connection into
the worker; memoize the worker global bundle once per process; guard every promise
callback with the request-id check (`mergen_is_current_request` pattern) so a stale
analysis cannot overwrite a newer one; wrap reactive reads in `shiny::isolate()`
inside promise/`later` callbacks (see the Ortak Oturum reactive-context lesson in
`CLAUDE.md`); surface a real progress stage per pipeline step rather than a single
opaque spinner.

**Cancellation must reach the worker; stale-callback guards are not enough.** The
current synchronous path calls `stop_check` between stages, but that is a reactive
closure and cannot be serialized into an explicit-mode future. Discarding the callback
after the user presses Stop leaves the worker running, still holding a DB connection
and a worker slot; a hung ODBC query holds them indefinitely. A handful of stopped or
slow analyses would then exhaust the pool and stall every user. Required:

* **A worker-visible cancellation token**, not a closure — reuse the existing
  `stop_file` pattern from the true-streaming path (`streaming_should_stop()` in
  `R/helpers_llm_stream_io.R`). The worker polls it between stages and before each
  expensive step.
* **A SQL execution deadline** on the query itself (ODBC query timeout), so a hung
  statement fails instead of blocking forever.
* **A wall-clock deadline for the whole analysis**, after which the worker aborts.
* **Guaranteed connection release** via `on.exit(..., add = TRUE)` inside the worker,
  on every exit path including cancellation and error.
* A test asserting that a cancelled analysis releases its connection and frees its
  worker slot.

Also add a cache keyed on `(query_id, rls_signature, filter_signature)` so follow-ups
are instant. **Bound it by size, not only by time.** A TTL alone lets every large result
produced inside the window stay resident at once; a handful of 50,000-row frames across
enough distinct signatures can exhaust the worker's memory before anything expires.
Required: LRU eviction with a maximum entry count (`MERGEN_PK_CACHE_MAX_ENTRIES`) and a
total byte budget (`MERGEN_PK_CACHE_MAX_MB`), rejection of any single entry above
`MERGEN_PK_CACHE_MAX_ENTRY_MB` rather than evicting everything else to fit it, and a
test asserting eviction order and the oversized-entry rejection.

**Row capping is not a simple `TOP n`, and getting it wrong is a correctness bug.**
SQL runs at stage 4, actual-result validation and RLS at stage 5, and filtering at stage
8. A blind `TOP 50000` against a 200,000-row result keeps an arbitrary prefix that may
contain few or none of the current user's authorized rows even though authorized
matches exist further down — and statistics over that biased subset are simply wrong,
however prominent the truncation notice. Permitted approaches, in order of preference:

1. **Push the RLS predicate (and any resolved filter) into SQL**, then cap. The cap
   then applies to an already-authorized, already-filtered set.
2. **Compute aggregates over the whole authorized set and cap only the delivered detail
   rows.** Statistics stay exact; only example and attachment rows are limited.
3. **Refuse explicitly** when neither is possible and the result exceeds the active-result
   ceiling: *"Sonuç kümesi çok büyük, lütfen sorunuzu daraltın."* A clear refusal beats
   a confident answer computed over an arbitrary prefix.

The ceiling must be **real and pre-emptive**, not aspirational. `MERGEN_PK_MAX_RESULT_MB`
(default 512) bounds a single materialized result, and the decision has to be made
*before* the frame is loaded — the cache byte budget applies only after materialization,
so it cannot save a worker from one wide query.

A `COUNT(*) × estimated_width` preflight is accepted only when `estimated_width` is a
**proven upper bound** derived from declared maximum widths for every variable-width
text/binary column, plus a conservative documented allowance for R/driver object
overhead. Declared SQL types without their maximum lengths, observed sample widths,
averages or heuristics are not upper bounds and cannot authorize full materialization.
When no such bound exists, use the mandatory bounded chunked-fetch path: fetch a fixed
chunk, account for its actual in-memory bytes, retain only while the running total stays
below `MERGEN_PK_MAX_RESULT_MB`, poll cancellation/deadlines between chunks, and abort
before accepting the chunk that would cross the ceiling. The implementation must never
hold the full frame plus an unbounded staging copy. Tests cover `varchar(max)`,
`varbinary(max)`, underestimated sample widths and a chunk that would breach the cap.

A naked `TOP` cap applied **before** authorization is not acceptable.

### 5.11 Provenance, telemetry, degradation

**Every** degradation must appear in the answer: LLM timeout, dropped filter,
unresolved entity, truncated rows, narrowed RLS scope, omitted columns.

**Telemetry writes must be fail-soft, and this is not optional.** The DDL is applied
manually by a DBA while telemetry defaults to on for both engines, so any deployment
where the application update lands before the script would otherwise attempt to write a
nonexistent table on **every** analysis — turning an observation-only feature into a
break of the whole tool, including working v1 analyses. Required: detect table
readiness once per process, degrade to disabled with a single logged warning when it is
absent, wrap every write in `tryCatch` so an insert error can never propagate into the
user request, and cover "missing table keeps the tool fully functional" in the contract
test. This mirrors the `MB_Ortak*` / `MB_Game_*` rule that missing tables must keep the
feature usable.

**Telemetry table `MB_Analiz_Log`** (idempotent DDL under `docs/sql/`, manual DBA
apply, never at startup — same rules as the other `MB_*` families): question hash,
selected query id, confidence, alternates, resolution outcomes, rows before/after,
per-stage latency, degradation flags, attachment produced. This is how the tool
becomes measurable — and it is what tells you which 30 of 169 queries deserve
metadata first.

**Numeric provenance check — semantic enforcement, not token membership.** A bare
comparison of numeric tokens is insufficient: if `47` is a distinct-person count, prose
that says *"tamamlanma %47"* must fail even though the packet contains the token `47`.
The packet therefore exposes structured facts with `fact_id`, capability/label, value,
unit, aggregation, authorized/filter scope, grouping keys and time window. The
composition prompt requires every numeric claim to carry an adjacent machine-readable
fact reference (for example `[fact:people.distinct.overall]`), which is removed from the
final display only after validation.

The validator checks the rendered number and its semantic use against the referenced
fact: correct measure capability, unit, aggregation, scope/group and date window, with
only declared rounding/formatting tolerance. Unknown fact IDs, a correct value cited for
the wrong measure, or a changed scope are mismatches. Bare token membership may remain
a diagnostic signal but can never authorize a claim. Deterministic tables/attachments
carry fact IDs internally and bypass LLM claim parsing because R owns their semantics.
Logging alone still does **not** satisfy the packet-only-facts contract: the invented or
mislabelled figure would reach the user and merely increment a counter.

Enforcement is staged through `MERGEN_PK_NUMERIC_PROVENANCE_MODE`:

| Mode | Behavior |
|---|---|
| `off` | disabled |
| `log` | semantic mismatches recorded in telemetry only — **calibration mode**, used to measure the false-positive rate before enforcing |
| `warn` | the answer is shown with unsupported or semantically mis-cited figures visibly marked and a Turkish note that they could not be verified against the computed fact |
| `block` | the answer is rejected and regenerated once; on a second failure the deterministic table plus a short factual summary is shown without the prose |

Ship in `log`, review the real mismatch rate on the VM, then move to `warn`. Do **not**
start in `block`: a legitimate phrase such as *"yaklaşık üçte biri"* can trip a naive
matcher, and silently withholding a correct answer is its own failure mode. Acceptance
criteria must name the active mode rather than asserting an absolute.

**Empty-result taxonomy** — four distinct messages, not one: no such data · none
within your authorization · filter matched nothing · query returned nothing.

---

### 5.12 Worked example — what "correct" looks like end to end

Concrete target behavior for one realistic Turkish request. Every artifact below is
produced by R except the prose.

**Question:** *"elektronik harp modernizasyon projesinde 2024'te kimler görevliydi,
listeyi ver"*

| Stage | Output |
|---|---|
| 2 Selection | Pass A → `q042, q055, q108, q011, q077`. Pass B → `q042` (Aktivite Rol Atamaları), confidence 82, alternates `q055`. Capability check: has `project`, `date.project_start`, and the required `dimension.resource` output capability ✓ |
| 3 Pre-contract | Typed requirements match the declared/generated schema and capability metadata ✓; no claim is made yet about live returned columns |
| 4 SQL | 41,930 rows (`row_cap` 50,000 not hit) |
| 5 Actual result + RLS | Returned columns satisfy `column_meta` and `rls_columns`; then `Yetki = PY` → 12,405 rows |
| 6 Filter plan | `AND[ OR[ ProjeAdi resolve "elektronik harp modernizasyon" ], BaslangicTarihi range 2024-01-01..2024-12-31 ]` — the date phrase *"2024'te"* resolved **in R** |
| 7 Resolution | `ELEKTRONİK HARP SİSTEMLERİ MODERNİZASYON PROJESİ` — score **88** (declared token-containment tier), margin **18** over #2 → clears 85 and the margin gate → **auto-accept**, single canonical value |
| 8 Filtering | `ProjeAdi %in% c(...)` AND date range → 312 rows. Provenance recorded per leaf |
| 9 Packet | Stats over **all 312 rows**: 47 distinct `KaynakAdi`, `KalanIscilik_sa` sum 18,420.5 (additive ✓), `TamamlanmaYuzde` weighted mean 61.3% (**not** summed; positive finite weights available), per-month histogram, 4 IQR outliers, 30 representative rows (top/bottom/outlier/stratified, seed 42) |
| 10 Answer | 312 > `MERGEN_PK_DT_MAX_ROWS` (200) → **attachment path**: XLSX plus a 10-row inline preview, not a `DT` widget. The explicit *"listeyi ver"* would have forced the attachment in any case. Prose cites only packet facts |
| 11 Provenance | Footer + `Bilgi` sheet + `MB_Analiz_Log` row |

**Answer footer the scoped user sees:**

```
Kaynak: q042 · Aktivite Rol Atamaları
Filtre: ProjeAdi = "ELEKTRONİK HARP SİSTEMLERİ MODERNİZASYON PROJESİ"
        (eşleşme: bulanık, %88) · BaslangicTarihi: 2024-01-01 – 2024-12-31
Satır:  12.405 → 312 (filtre)
Ek:     Aktivite_Rol_Atamalari_20260801.xlsx (312 satır × 14 sütun)
```

The pre-RLS `41.930` count remains available only in restricted server telemetry, not
in the scoped user's footer or `Bilgi` sheet.

**Two contrasting outcomes the same request must be able to produce:**

*Ambiguous* — two projects score **88** and **85** (margin 3 < `MERGEN_PK_RESOLVE_AMBIGUITY_MARGIN`) → **no analysis runs.** The user sees
chips: *"Hangisini kastettiniz?"* with both names and a "Tümü" option.

*Unresolved* — best score **31** (below the configured
`MERGEN_PK_RESOLVE_MIN_SCORE`, whose default is 40) and the project is the subject of
the question → **no full-set analysis.** The user sees: *"'elektronik harp
modernizasyon' ile eşleşen bir proje bulunamadı. En yakın adaylar: … Farklı bir ifade
deneyebilir veya proje kodunu verebilirsiniz."*

Neither outcome is an empty table, and neither is a confident answer about the wrong
population.

---

## 6. File map

**New (all must be added to `R/config_source_manifest.R` in dependency order, and
assigned to a seam in `R/config_seam_registry.R`):**

| File | Responsibility | Purity |
|---|---|---|
| `R/helpers_pk_text_turkish.R` | `pk_tr_fold()`, tokenization, suffix/clitic strip | pure |
| `R/helpers_pk_query_retrieval.R` | trigram + IDF lexical retrieval (non-deciding) | pure |
| `R/helpers_pk_query_selection_ai.R` | 2-pass AI selection, capability validation | LLM |
| `R/helpers_pk_filter_plan.R` | typed filter tree parse + validate | pure |
| `R/helpers_pk_entity_resolver.R` | Turkish fuzzy resolution + decision policy | pure |
| `R/helpers_pk_filter_compile.R` | tree → data.table ops, provenance | pure |
| `R/helpers_pk_analysis_packet.R` | whole-dataset statistics + budget accountant | pure |
| `R/helpers_pk_answer_compose.R` | prose/table/attachment routing + thresholds | pure-ish |
| `R/helpers_pk_export_xlsx.R` | XLSX build + verify + session-scoped serve | I/O |
| `R/helpers_pk_telemetry.R` | `MB_Analiz_Log` writes, degradation records | DB |
| `R/library_query_meta_auto.R` | committed **empty scaffold** so the Tier-0 boot path works in a fresh checkout; never populated in Git | data |
| `R/library_query_meta_local.R` | generator output, **gitignored**, VM-only (§5.1) | data |
| `R/library_query_aliases_local.R` | operator-maintained production aliases, **gitignored**, optional, never generator-written | data |
| `R/library_query_meta.R` | **curated** capability registry and approved/synthetic per-query metadata keyed by stable id | data |
| `tools/pk/generate_query_meta.R` | VM-only metadata generator (NOT in the manifest) | script |

All four metadata/alias files are runtime data and **must appear in
`R/config_source_manifest.R`**, loaded after `R/helpers_pk_text_turkish.R` in the order
`R/library_query_meta_auto.R` → `R/library_query_meta_local.R` →
`R/library_query_meta.R` → `R/library_query_aliases_local.R` →
`R/config_sql_loader.R`. The loader merges metadata with curated winning, then applies
the alias-only local overlay and validates it. Mark both local files `optional` in the
manifest — they are absent in cloud checkouts by design — and do not `source()` any of
them ad hoc from the loader: that would leave them unowned and invisible to
`bash tools/seam_doctor.sh`.

**Modified:** `R/module_proje_kaynak_analizi.R` (becomes a thin orchestrator),
`R/helpers_pk_analysis_filters.R` (rewritten around the typed tree),
`R/helpers_pk_analysis_security_summary.R` (RLS fail-closed; summary moves out),
`R/helpers_pk_analysis_query_selection.R` (heuristic demoted to non-deciding),
`R/helpers_deep_analysis.R` (reconciled with the main path — D16),
`R/library_queries.R` (unchanged structurally; metadata lives elsewhere),
`R/config_sql_loader.R` (merge metadata/alias layers, validate contracts at startup),
`R/server_send_message.R` (async dispatch + multi-part answer).

**Watch the maintainability ratchet.** `R/module_proje_kaynak_analizi.R` is
currently 641 lines. It must **shrink**, not grow. Do not raise any budget in
`tests/testthat/test-maintainability-ratchet.R` or
`test-pk-analysis-maintainability-contract.R` to accommodate this work — split
instead.

---

## 7. Testing

**Existing tests must keep passing** (`test-pk-analysis-*.R`,
`test-deep-analysis-*.R`). Where behavior intentionally changes (e.g. same-column
OR), update the test to assert the *new correct* behavior and say so — do not
delete coverage.

**New offline, deterministic tests** (no DB, no LLM, no browser, no network):

| Test | Covers |
|---|---|
| `test-pk-text-turkish-behavior.R` | `pk_tr_fold()` on İ/I/ı/i, composed/decomposed NFC equivalents, clitics, suffixes; locale independence; Phase-3a load-order availability |
| `test-pk-filter-compile-behavior.R` | **OR-in-column / AND-across** (D1), complementary same-column range bounds stay AND, multi-value (D2), ranges, NOT, no-op detection |
| `test-pk-entity-resolver-behavior.R` | all 6 scoring tiers, exact ASCII-fold score 90 + collision clarification, validated local/approved alias registry + collision rejection, every decision-policy branch under overridden min/auto thresholds including plural-before-auto, invalid threshold ordering fails safe, code-exactness |
| `test-pk-query-selection-contract.R` | resolved `MERGEN_PK_SELECT_RECALL_N` controls both Pass-A requested IDs and Pass-B candidate input; non-default value 3 is honored; no literal five; stable IDs and alternate confidences |
| `test-pk-filter-plan-contract.R` | typed tree validation; **rejects any executable expression** (D5) |
| `test-pk-rls-failclosed-contract.R` | missing declared RLS column → **abort, not skip** (D6); startup schema check may be pending only when schema is unavailable, but request-time validation remains unconditional; an unavailable role scope aborts and an empty role scope yields **zero** rows, never all rows (D6b); `NA` in `Yetki` does not error; **no configuration value anywhere restores fail-open filtering** |
| `test-pk-sql-readonly-gate-contract.R` | shared cross-engine parser/classifier allows only a single read-only SELECT/CTE-SELECT; rejects data-modifying CTEs, `SELECT INTO`, multiple statements, write/DDL/DCL/BACKUP/RESTORE/EXEC/sp_/xp_ forms; harmless keywords inside literals/comments do not create false positives; unknown syntax fails closed; generator uses the same gate (D23) |
| `test-pk-analysis-packet-behavior.R` | additive vs non-additive; weighted means exclude disclosed missing/zero pairs, reject negative/non-finite weights, and return unavailable when no positive weight remains; stable `latest_by` + unique `latest_tie_by`; duplicate newest-row ties return `ambiguous_latest`; structured fact IDs and semantic context; budget accountant; stratified sample; `FİLTRELEME UYARISI` survives degradation (D7, D8) |
| `test-pk-numeric-provenance-contract.R` | value plus fact ID/capability/unit/aggregation/scope/group/date validation; same token used for a wrong measure is rejected; warn/block fallbacks are deterministic |
| `test-pk-export-xlsx-behavior.R` | native types, Turkish round-trip, writer-specific percentage contract, no pre-RLS count in `Bilgi`, multipart completeness or explicit refusal above the per-part limit, verification failure → CSV fallback, character formula neutralization while numeric `-125.50` remains numeric, **not served from `bilge_yolac_downloads`** |
| `test-pk-query-meta-contract.R` | pre-execution declared/generated-schema validation is distinct from mandatory post-fetch actual-column validation; startup validation covers duplicate ids, capability registry/column/requirements consistency including exact measure/date/output-dimension capabilities, semantic requirements without mappings return `unknown_no_semantic_metadata`, optional local alias layer cannot alter non-alias fields, tracked aliases are synthetic/approved, conditional schema-dependent checks, actual `column_meta` match when schema exists, alias target/collision rules |
| `test-pk-deep-reconciliation-contract.R` | cross-query arithmetic requires the same stable measure capability/fact identity and compatible scope; equal overlapping facts deduplicate deterministically; conflicting values emit `conflicting_fact` and refuse the combined figure |
| `test-pk-async-deadline-contract.R` | each normal/deep SQL timeout is clamped to the remaining whole-analysis deadline, zero residual budget prevents dispatch, cancellation/error releases the connection |
| `test-pk-degradation-disclosure-contract.R` | Phase-0 typed filter adapter distinguishes `no_filter`, `timeout` and `error`; every degradation path reaches the user-visible answer (D9) |
| `test-pk-result-size-preflight-contract.R` | variable-width columns require declared maximum-width upper bounds or bounded chunk fetch; sample/average width cannot authorize materialization; breach aborts before retaining the over-limit chunk |

**Turkish golden set** — the thing that makes "world class" measurable.

**Split it in two, and keep real traffic out of Git.** Populating the committed fixture
from production traffic would push raw user questions, internal project and programme
names, and real row counts into the GitHub checkout — a data-exfiltration path, not a
test asset.

| Corpus | Location | Contents |
|---|---|---|
| Committed | `tests/fixtures/pk_golden_set.json` | **synthetic or explicitly approved, redacted** cases only; invented project names; row counts replaced by shape assertions |
| Real | VM-side, access-controlled, **never committed** | actual questions and expected results, with a stated retention period and an export-approval step before anything leaves the VM |

The offline suite runs the committed corpus. The live scored run (VM, opt-in) runs the
real one and reports only aggregate rates — never raw questions — back into any
artifact that could leave the VM. Target ~100–200 cases per corpus:

```json
{"soru": "elektronik harp modernizasyon projesinde kimler görevli?",
 "expected_query_id": "q042",
 "expected_entity": {"column": "ProjeAdi", "kind": "project"},
 "expected_resolution": "auto|clarify|unresolved",
 "expected_filter_logic": "OR(ProjeAdi IN [...])",
 "expected_row_count": 37,
 "expected_aggregation_grain": "activity_assignment"}
```

Two harnesses:

* **Offline (default suite):** stubbed LLM returning recorded outputs → asserts
  resolution, filter compilation, packet math, budget. Fully deterministic.
* **Live scored run (VM, opt-in):** real endpoint → reports selection accuracy,
  filter accuracy, clarification rate, zero-result rate, silent-fallback rate.
  Never a blocking gate; it is the metric that tells you whether prompt or metadata
  changes actually helped.

---

## 8. Phased plan

Each phase is independently shippable, independently validatable, and lands as its
**own pull request**. Do not accumulate all phases on one branch — the operator must
be able to review, validate and merge them one at a time.

**Sequencing is by offline verifiability, not by phase number.** See §11 for the
recommended order when the VM is unavailable.

### Phase 0 — Instrumentation + status plumbing (½ day)
Telemetry (`MB_Analiz_Log`) + degradation disclosure + provenance footer, plus the
minimal typed filter-adapter result needed to distinguish `status = "ok_no_filter"`,
`"timeout"`, `"error"` and `"malformed"`. This plumbing observes the current v1 path;
it does not change which filters v1 applies. **Do this first**: it costs little, it
immediately makes today's silent failures visible, and it produces the usage data that
prioritizes Phase 3.

*Acceptance:* every answer carries a provenance footer; the adapter returns a distinct
typed status for a legitimate no-filter result versus timeout/error; every timeout or
dropped filter appears in the answer and in the log. Phase 0 therefore does not claim
telemetry for a state it cannot observe.

### Phase 1 — Surgical correctness (2–3 days) ← **fixes most reported symptoms**
D1 (OR-in-column, complementary range bounds stay AND) · D2 (multi-value) · D3
(consume the Phase-3a `pk_tr_fold()` helper and replace unsafe comparisons) · D4
(zero-match policy) · D5 (remove `eval(parse)`) · D6 (RLS fail-closed) · D7/D8
(budget + warning) · D9 (consume the Phase-0 typed timeout/error status and prevent
silent full-set continuation) · D12 (dead code) · D22 (redact ODBC errors) · **D23
(shared statement-aware read-only SQL classifier for v1/v2/deep/generator)**.
*Acceptance:* the new offline tests pass; a two-value same-column question returns the
**union** of both; a nonsense value on the query's **primary** filter column produces an
explicit *"çözümlenemedi"* response — **never an empty screen, and never a full-set
analysis**, because statistics over every project answer a different question than the
one asked (§5.4, rule 6). A nonsense value on a *secondary* filter is dropped with
prominent disclosure and the analysis continues. The SQL classifier rejects
single-statement side effects (`SELECT INTO` included), data-modifying CTEs, multiple
statements and every write/DDL/DCL/backup/execute fixture before any connection executes
it, independent of whether the read-only DB principal is already available.

Phase 1 decides primary-versus-secondary from `primary_entity` (available because
Phase 3a lands first), falling back to "the sole filter leaf is primary" when metadata
is absent. **Nearest-value hints are NOT part of Phase 1 acceptance** — candidate
ranking is owned by the Phase 4 resolver, and requiring it here would force Phase 1 to
duplicate part of it. Phase 1 says "bulunamadı"; Phase 4 upgrades that to "bulunamadı,
en yakın adaylar: …".

### Phase 2 — Deterministic analysis + export (3–5 days)
Analysis packet (§5.7) · answer composition (§5.8) · XLSX export (§5.9) ·
epistemic labelling · remove the "generate a markdown table" instruction.
*Acceptance:* a 5,000-row result produces a correct XLSX and a CSV fallback where
character formula-like values are neutralized while legitimate negative numeric amounts
remain numeric; weighted percentages never emit `NaN`, silently use negative weights or
fall back to an unweighted mean; a result above `MERGEN_PK_EXPORT_MAX_ROWS` is either
complete across verified numbered parts or explicitly refused — never silently
truncated; the `Bilgi` sheet contains authorized-population-before-filter and
after-filter counts only; the bubble is not a wall of table; and numeric-provenance runs
in `log` mode with semantic fact references and its measured mismatch rate reported
(§5.11). Percentage acceptance is **writer-specific**: the required `writexl` baseline
round-trips through `readxl` as numeric `61.3` under `Tamamlanma (%)`; only when
`openxlsx` is installed (or made a required dependency) must the formatted path store
`0.613` with a percent style and render `61,3%`, never `6130,0%`. `readxl` proves stored
values, not rendered styles; the style/value contract is inspected separately and real
Excel rendering remains VM-only.

### Phase 3a — Metadata contract (offline; **must precede Phases 1 and 2**)
The metadata schema (§5.1), capability registry, the auto/generated/curated metadata
split plus the optional gitignored alias overlay and their merge, the minimal
locale-independent NFC-normalizing `pk_tr_fold()` helper loaded before metadata,
schema-independent alias/capability validation, Tier-0 inference, and a documented
Tier-0 fallback for every consumer. Phases 1 and 2 depend on `primary_entity`, `grain`,
`grain_columns`, `additive`, `aggregate`, `unit` and `percent_scale`; none of these can
be inferred at Tier 0, so building those phases first would force each to invent an ad
hoc substitute.
*Acceptance:* startup fails on every schema-independent invalid contract; alias keys
are NFC-normalized and folded by the one Phase-3a helper and collisions are rejected;
production alias targets remain in the optional gitignored alias file while tracked
aliases are synthetic/approved; capability IDs are allowlisted and role/unit consistent;
when a result schema exists, schema-dependent mismatches also fail startup; when no
schema is yet available, startup records a pending check and the query still boots
through the documented Tier-0 structural path, while a request with semantic capability
requirements returns `unknown_no_semantic_metadata` before SQL and a mandatory
post-fetch actual-column mismatch always fails closed. The fallback for each consumer is
named in a test.

### Phase 3b — Metadata generator and population (tooling offline, run on the VM)
Generator (`tools/pk/generate_query_meta.R`) · the metadata/alias file split ·
merge-with-curated-winning plus alias-only local overlay in `config_sql_loader.R` ·
startup contract validation · Tier-0 inference for unenriched queries · query-library
health report. Then, on the VM: run the generator, act on the health report, and enrich
the top ~30 queries by telemetry without overwriting operator aliases.
*Acceptance (offline):* generator is written, `source(...)`-safe, resumable, uses the
Phase-1 SQL classifier, never writes the alias overlay, and is unit-tested against a
fake query library with a stubbed DBI connection; startup fails on an invalid contract
when the relevant schema exists; Tier-0 inference produces a usable structural
`column_meta` for a query with no metadata at all but does not invent semantic
capability IDs.
*Acceptance (VM):* generator runs clean over all 169 queries; health report is empty
or every finding is triaged.

### Phase 4 — Entity resolution (2–3 days)
Resolver built on the Phase-3a `pk_tr_fold()` helper · ASCII-secondary-key tier ·
validated local/approved alias registry · decision policy · clarification chips ·
`chat_history` wiring for follow-up refinement (D11).
*Acceptance:* long project names resolve from partial Turkish phrases; aliases exercise
the 95-point tier without collisions or leaking production targets to Git; composed and
decomposed Turkish strings resolve identically; `kalip → kalıp` scores exactly 90 and an
ASCII-key collision clarifies; plural multi-candidate requests are evaluated before
single-candidate auto-acceptance; every branch follows validated overridden configured
thresholds; invalid threshold relationships fail safe before resolution; ambiguity
produces chips, not a guess; codes are never fuzzed.

### Phase 5 — Selection rebuild (2–3 days)
Two-pass AI · stable ids (D13) · exact measure/date/output-dimension capability
registry/validation · confidence gate · timeouts + repair retry (D14) · heuristic
demoted to non-deciding (D10) · trigram+IDF retrieval.
*Acceptance:* low-confidence requests ask instead of guessing; planned-vs-remaining
labor, start-vs-finish dates and required person/resource output dimensions select by
stable capability ID rather than lexical similarity, subject entity or a generic date
boolean; metadata-free semantic requirements refuse before SQL; reordering
`library_queries.R` changes nothing; the resolved `MERGEN_PK_SELECT_RECALL_N` value is
honored by both passes (including a non-default value of 3); recall@N is measured on the
golden set, including a case whose distinguishing phrase appears only in
`sample_questions`.

### Phase 6 — Non-blocking + performance (2–3 days) — **highest runtime risk**
Async dispatch (D15) · worker-visible cancellation + SQL deadline + guaranteed
connection release (§5.10) · authorization-aware row caps · conservative result-size
preflight/chunk cap · caching · deep-mode reconciliation to the v2 multi-query contract
(D16, §10).

This phase touches the send-message/streaming path and its core benefit
(event-loop responsiveness) **cannot be proven offline**. It therefore gets its own
flag, `MERGEN_PK_ASYNC` (default `false`), independent of `MERGEN_PK_ENGINE`, so the
v2 engine can be adopted on the VM *before* async execution is enabled. Build it
last, ship it as the last PR, and validate it on its own.

*Acceptance (offline):* worker global bundle is complete and memoized; no session,
reactive value, or DB connection is serialized; every promise callback carries a
request-id guard; every reactive read inside a promise/`later` callback is
`shiny::isolate()`-wrapped; stale-callback tests pass with mocked `future`/`promises`;
variable-width preflight tests prove that only a maximum-width upper bound or bounded
chunk fetch can authorize materialization; every normal/deep ODBC timeout is capped by
the remaining whole-analysis deadline and zero residual budget prevents dispatch.
*Acceptance (VM):* a second browser session stays responsive while a large analysis
runs; deep mode produces the same result as before the reconciliation.
**Plus the operational soak gate** (`docs/operational-soak-gate.md`,
`tests/scripts/run_operational_soak_gate.R`) with a PK-analysis scenario added: at
minimum its fake-lane smoke profile must pass **before** `MERGEN_PK_ASYNC=true` is
enabled. A two-browser check cannot exercise cancellation storms, worker-pool
saturation, bounded shadow dispatch, or sustained cache and connection pressure — and
Phase 6 is the highest-risk concurrency change in the plan. Keep the existing honesty
boundary from that document: the fake lane is **not** real-LLM proof and **not** a
production-scale capacity claim.

### Phase 7 — Measurement (ongoing)
Golden set to ~200 cases · live scored run · audit dashboard (selection accuracy,
filter accuracy, clarification rate, zero-result rate, silent-fallback rate,
numeric-provenance mismatch rate).

---

## 9. Configuration surface

**Nothing in this tool may be a hard-coded magic number.** Every threshold, timeout,
score cut-off and limit is resolved through one helper with a fixed precedence:

> **per-query metadata → `.Renviron` env var → `options()` → built-in default**

Per-query metadata beats the global, so one heavy financial query can carry
`row_cap = 200000` while the global stays at 50,000, with no code change. This mirrors
the `DB_CLIENT_ENCODING` contract in `CLAUDE.md`: the environment is honoured **before**
R options and defaults.

The resolver must be **worker-safe** — read with `Sys.getenv()` inside futures, never
by serializing a helper closure (same rule as `MERGEN_LLM_TIMEOUT_SEC`).

| Variable | Default | Purpose |
|---|---|---|
| `MERGEN_PK_ENGINE` | `v1` | `v1` = current pipeline, `v2` = rebuilt pipeline. **Master kill switch.** |
| `MERGEN_PK_ASYNC` | `false` | Off-event-loop execution (Phase 6), independent of the engine flag |
| `MERGEN_PK_SHADOW_MODE` | `false` | Run v2 alongside v1, log the comparison, show v1 (§10) |
| `MERGEN_PK_SHADOW_SAMPLE_PCT` | `20` | Percentage of requests shadowed |
| `MERGEN_PK_SELECT_TIMEOUT_SEC` | `20` | Per-pass selection LLM timeout (currently **absent** — D14) |
| `MERGEN_PK_SELECT_RECALL_N` | `5` | Candidates requested by Pass A and carried unchanged into Pass B; both passes use the resolved value, never a literal 5 |
| `MERGEN_PK_SELECT_MIN_CONFIDENCE` | `50` | Below this → clarify instead of executing |
| `MERGEN_PK_SELECT_MIN_MARGIN` | `15` | Minimum gap to the runner-up before auto-executing |
| `MERGEN_PK_FILTER_TIMEOUT_SEC` | `20` | Filter-plan LLM timeout (today's `8` is too aggressive — D9) |
| `MERGEN_PK_SQL_TIMEOUT_SEC` | `120` | ODBC query timeout, so a hung statement fails instead of holding a connection forever (§5.10). Per-query metadata may raise it for known-heavy queries, but never beyond the remaining analysis deadline |
| `MERGEN_PK_ANALYSIS_DEADLINE_SEC` | `300` | Wall-clock deadline for the whole analysis; the worker aborts and releases its connection past it |
| `MERGEN_PK_CACHE_MAX_ENTRIES` | `50` | LRU cache entry ceiling |
| `MERGEN_PK_CACHE_MAX_MB` | `512` | Total cache byte budget |
| `MERGEN_PK_CACHE_MAX_ENTRY_MB` | `128` | Single entry above this is not cached at all |
| `MERGEN_PK_DEEP_MAX_QUERIES` | `5` | Deep Thinking ranked-set ceiling (§10) |
| `MERGEN_PK_RESOLVE_AUTO_SCORE` | `85` | Single-candidate auto-accept threshold |
| `MERGEN_PK_RESOLVE_MULTI_SCORE` | `70` | Plural candidate threshold; candidates are presented for confirmation, not silently unioned |
| `MERGEN_PK_RESOLVE_MIN_SCORE` | `40` | Below this → unresolved; every resolver branch reads this resolved value, never a literal 40 |
| `MERGEN_PK_RESOLVE_AMBIGUITY_MARGIN` | `10` | Top-two gap below which we ask instead of guessing |
| `MERGEN_PK_RESOLVE_MAX_CANDIDATES` | `5` | Maximum canonical values in one confirmed OR group |
| `MERGEN_PK_NOOP_FILTER_RATIO` | `0.95` | Filter retaining more than this share is reported as ineffective |
| `MERGEN_PK_ENABLED` | `true` | Master on/off for the whole tool. `false` disables Proje ve Kaynak Analizi with a clear Turkish message. **This is the only rollback for an RLS contract problem** — there is deliberately no flag that restores fail-open filtering |
| `MERGEN_PK_ROW_CAP` | `50000` | SQL-side row cap; per-query `row_cap` overrides |
| `MERGEN_PK_PROMPT_CHAR_BUDGET` | `120000` | Whole-payload budget (summary **+** tables **+** rows — D7) |
| `MERGEN_PK_SAMPLE_ROWS` | `30` | Representative example rows in the packet |
| `MERGEN_PK_SAMPLE_SEED` | `42` | Fixed seed → reproducible stratified sample |
| `MERGEN_PK_TOPK_CATEGORIES` | `10` | Top-K values per categorical column |
| `MERGEN_PK_GROUP_TOPN` | `15` | Groups before the `Diğer` roll-up |
| `MERGEN_PK_INLINE_MAX_ROWS` | `15` | Markdown-table ceiling |
| `MERGEN_PK_INLINE_MAX_COLS` | `8` | Markdown-table column ceiling |
| `MERGEN_PK_DT_MAX_ROWS` | `200` | `DT` widget row ceiling; above it → attachment |
| `MERGEN_PK_INLINE_MAX_COLS_DT` | `12` | `DT` widget column ceiling; above it → attachment |
| `MERGEN_PK_EXPORT_MAX_ROWS` | `100000` | Maximum rows per exported sheet/file part; larger exact results split into verified parts or are explicitly refused, never silently truncated |
| `MERGEN_PK_MAX_RESULT_MB` | `512` | Active-result ceiling, enforced by a **pre-fetch proven upper bound or bounded chunk fetch** (§5.10). Distinct from the cache budget, which applies only after materialization |
| `MERGEN_PK_CACHE_TTL_SEC` | `300` | `(query_id, rls_signature, filter_signature)` cache lifetime |
| `MERGEN_PK_TELEMETRY` | `true` | Write `MB_Analiz_Log`. Applies to **both** engines — see §10 |
| `MERGEN_PK_LOG_QUESTION_TEXT` | `false` | **Privacy:** store the raw question, or only a keyed fingerprint. With `false`, the fingerprint MUST be a normalized, server-keyed **HMAC** with key rotation — a plain unsalted hash does not protect low-entropy prompts drawn from a finite project vocabulary, since anyone who can read the table can hash the candidate questions and recover matches. If no key can be managed, omit the fingerprint entirely |
| `MERGEN_PK_NUMERIC_PROVENANCE_MODE` | `log` | `off` / `log` / `warn` / `block` — enforcement level for answer facts that are absent or semantically mis-cited (§5.11). Ship in `log`, move to `warn` once the false-positive rate is calibrated on the VM |
| `MERGEN_PK_META_MODE` | `sample` | Generator mode: `sample` or `describe` |
| `MERGEN_PK_META_SAMPLE_ROWS` | `500` | Rows fetched per query in `sample` mode |

**SQL timeout precedence is bounded by the remaining whole-analysis budget.** At
analysis start compute an absolute deadline. Immediately before every ODBC statement —
including every Deep Thinking query — recompute the remaining seconds and set
`effective_sql_timeout = min(resolved per-query/default SQL timeout, remaining budget)`.
If no positive budget remains, do not dispatch the statement. A per-query override may
raise the configured SQL timeout but can never extend the analysis deadline; the active
driver timeout or cancellation path must interrupt the statement and `on.exit` must
release the connection. Tests cover a 600-second query override under a 300-second
analysis deadline and a later deep query receiving only the residual budget.

Add every new knob to `.Renviron.example` with a Turkish comment, and cover the
precedence order with a contract test.

---

## 10. Feature flag, rollback and shadow mode

This work replaces the engine of a production tool. It must be reversible without a
code change.

### Kill switch

`MERGEN_PK_ENGINE` selects the pipeline. **`v1` is the default until the operator
validates `v2` on the VM.** The v1 **decision logic** must remain unchanged — do not
refactor it "while you're in there". Deleting v1 happens later, in its own cleanup PR,
only after v2 has run in production.

Four changes deliberately cross both engines and carry their own rollback contracts,
because gating them behind `v2` would defeat their purpose:

| Change | Flag | Why it cannot wait for v2 |
|---|---|---|
| RLS fail-closed (D6 / D6b) | none — **unconditional** | It is a security fix; dormant under the default engine the hole stays open, and a flag that re-enables fail-open filtering is not a rollback, it is the vulnerability. If an RLS contract mismatch blocks a query, fix the contract or disable the tool with `MERGEN_PK_ENABLED=false` — never resume serving unfiltered rows |
| Statement-aware read-only SQL classifier (D23) | none — **unconditional** | The current shared validator explicitly accepts write forms. Both engines and the metadata generator must refuse any batch that is not provably one read-only SELECT before execution, regardless of read-only-principal availability |
| ODBC error redaction (D22) | none — always on | Same |
| Telemetry + provenance footer + typed filter-adapter status (Phase 0) | `MERGEN_PK_TELEMETRY` (default `true`) for writes; status/disclosure remains fail-soft | Instrumentation behind `v2` records nothing while `v1` is the default. Distinguishing `ok_no_filter` from timeout/error is required for Phase-0 telemetry to be truthful, and does not change v1's selection/filter decision |

All four are **observation-only or fail-safe**; none changes a v1 query-selection or
filter-selection decision. That is the precise sense in which v1 is "unchanged" — its
decision logic is untouched, while it may be observed, may refuse unsafe SQL, and may
refuse rather than over-share. Each has its own independent rollback: operational
misconfiguration is fixed or the tool is disabled; unsafe execution is never restored.

Rollback is one `.Renviron` line plus a **full R process restart** (a browser refresh
is not enough — same rule as the DB encoding variables).

`MERGEN_PK_ASYNC` is deliberately separate, so v2 can be adopted while execution stays
synchronous, isolating the riskiest change (§8, Phase 6).

### Shadow mode — validate on real traffic without exposing users

`MERGEN_PK_SHADOW_MODE=true` runs **both** engines for a sampled share of requests,
shows the user the **v1** answer, and logs a structured comparison:

| Compared | Not compared |
|---|---|
| selected query id + confidence | the LLM prose (non-deterministic, not meaningful to diff) |
| resolved canonical entities | wording, ordering of narrative points |
| filter provenance and logical grouping | |
| rows before/after RLS and filtering | |
| degradation flags raised | |

This is the cheapest way to earn confidence in v2 against real Turkish questions and
real data before flipping the switch. It costs roughly double the work per sampled
request, so it is off by default and sampled (`MERGEN_PK_SHADOW_SAMPLE_PCT`).

Recommended adoption sequence on the VM:

1. `MERGEN_PK_ASYNC=true` first, validated on its own (§8, Phase 6) — see the
   constraint below.
2. `MERGEN_PK_ENGINE=v1` + `MERGEN_PK_SHADOW_MODE=true` for a few days → review
   disagreements.
3. `MERGEN_PK_ENGINE=v2`, shadow off.
4. v1 removal PR.

**Shadow mode requires async execution; it must refuse to run without it.** With
`MERGEN_PK_ASYNC=false`, a sampled request executes the already-blocking v1 path *and*
the synchronous v2 path before rendering v1 — roughly doubling the window in which the
Shiny process cannot serve any other session, and doing so continuously for days. That
turns a validation aid into an amplifier of D15, the single worst production problem in
the current tool. `MERGEN_PK_SHADOW_MODE=true` with `MERGEN_PK_ASYNC=false` must fail
fast at startup with an explanatory message rather than silently degrading the whole
deployment. The v2 shadow evaluation additionally runs as a **bounded background
dispatch** that never blocks or delays the user-facing v1 answer, and is dropped rather
than queued when no worker is free.

### Backward compatibility that must not break

* `disable_ai_filters = TRUE` in a query definition must keep working in v2.
* `analysis_mode = "full"`, `pre_aggregated_columns`, `date_columns`, `rls_columns`,
  `db_target`, `info_file`, `info_url`, `sql_file` / inline `sql` all keep their
  current meaning.
* The Ortak Oturum bridge (`R/helpers_ortak_oturum_arac.R:406-455`) consumes
  `prompt_context` / `user_context` from this tool. The v2 return contract must keep
  those fields, or that call site must be updated in the same PR.
* Deep Thinking (`analysis_deep_thinking`) and `analysis_detail_level` remain
  user-visible settings with unchanged semantics — but "unchanged" needs a defined v2
  path, because the target pipeline produces one SQL result and one packet while
  `pk_deep_analysis_process()` selects up to five queries and runs each. Leaving this
  to "deep-mode reconciliation" in Phase 6 would force implementers to choose between
  silently collapsing Deep Thinking to a single query and keeping the divergent v1 path
  (D16). The v2 contract is:

  1. **Selection.** Pass A is unchanged. Pass B returns a **ranked set** for deep mode
     (`MERGEN_PK_DEEP_MAX_QUERIES`, default 5), each entry carrying its own confidence.
     The confidence gate applies **per query**: a candidate below
     `MERGEN_PK_SELECT_MIN_CONFIDENCE` is dropped from the set, not auto-executed.
     If that filtering leaves **zero candidates**, stop before stages 3–10 with a typed
     `no_confident_query` result. Show the top three rejected candidates as optional
     clarification chips (or an explicit *"Bu istek için güvenilir bir sorgu
     bulunamadı"* response); never enter execution/composition with an empty packet
     list and never produce a blank answer.
  2. **Execution.** Each selected query runs stages 3–9 **independently and in full**:
     its own pre-execution contract validation, SQL, mandatory post-fetch actual-column
     validation plus RLS, filter plan, entity resolution, filtering and packet. No
     shared state between them; one failing query never fails the run.
  3. **Reconciliation is deterministic and operates on packets, not statistics.**
     Packets are concatenated with their provenance intact; cross-query figures are
     **never** added, averaged or otherwise combined by default. Matching `grain` and
     `grain_columns` is **not sufficient** to combine them — two queries can declare the
     same grain while returning overlapping instances of those keys, covering different
     populations, or carrying measures with different units and aggregation semantics.
     Combining on a metadata name match alone would count the same assignment twice and
     corrupt Deep Thinking totals. Combination is permitted only when **all** of the
     following hold, and is otherwise refused in favour of keeping the figures separate:
     identical `grain` and `grain_columns`; the **same stable measure capability and
     fact identity** (not merely the same unit); compatible authorized/filter/time scope
     and population semantics; identical `unit`, `aggregate` and `additive = TRUE`; and
     deduplication on the actual grain-key values. Planned and remaining labor therefore
     cannot be combined merely because both are additive hours. If an overlapping grain
     key carries the same fact identity and equal values within declared tolerance, keep
     one deterministic value. If values conflict, emit `conflicting_fact`, preserve both
     packets with provenance, and refuse the combined figure — never pick one, add them
     or average them. When any condition fails, packets stay side by side and the
     narrative compares them qualitatively. The LLM synthesizes narrative across
     packets; it performs no arithmetic.
  4. **Budget.** The whole-payload accountant (§5.7) spans **all** packets combined, and
     degrades by dropping the lowest-confidence query's example rows first, then that
     query entirely — disclosing what was dropped.
  5. **Failures are reported, not hidden**, exactly as `build_deep_analysis_context()`
     does today.

---

## 11. Building without VM access — execution plan and session handoff

The operator may be away for an extended period. Most of this plan is buildable and
**genuinely provable** offline, because the hard logic lives in pure functions. What
follows is how to do that safely.

### What is provable offline

| Phase | Buildable | Provable offline | Gap |
|---|---|---|---|
| 0 Telemetry | 95% | ~80% | DDL written, not applied; test against real SQLite |
| 3a Metadata contract | 100% | ~95% | none for the contract itself |
| 1 Correctness | 100% | ~80% | Pure helper contracts are offline-testable; the SQL Server read-only statement gate, ODBC timeout/error behavior and production RLS integration require the Windows VM |
| 2 Packet + Excel | 100% | ~95% | `DT` widget rendering and real Excel presentation need a browser/VM |
| 4 Entity resolver | 100% | **100%** | clarification chips UI needs a browser |
| 5 Selection | 100% | ~60% | logic yes; **accuracy needs a real endpoint** |
| 3b Metadata population | generator only | 0% | generator cannot be **run**; metadata cannot be populated |
| 6 Async | 100% | **~30%** | event-loop responsiveness is VM-only |

### Recommended order when the VM is unavailable

**0 → 3a → 1 → 2 → 4 → 5 → 6**, with **3b on the VM** when the operator returns.

**Phase 3 must be split, and its contract half must come before Phases 1 and 2.** They
consume metadata that cannot be inferred at Tier 0: Phase 1's primary-versus-secondary
zero-match decision needs `primary_entity`; Phase 2's aggregation and Excel formatting
need `grain`, `grain_columns`, `additive`, `aggregate`, `unit` and `percent_scale`.
Building them before the contract exists would force each to invent its own ad hoc
substitute.

* **Phase 3a — contract (offline, comes early):** the metadata schema and stable
  capability registry; the minimal NFC-normalizing `pk_tr_fold()` helper loaded before
  metadata so aliases can be validated; the auto/generated/curated metadata split and
  the optional gitignored operator-alias overlay; startup contract validation; Tier-0
  inference; and the documented Tier-0 fallback for **every** consumer (e.g. "no
  `primary_entity` → treat the sole filter leaf as primary"; "no `additive` → do not
  sum, report the measure per row"). Schema-independent checks fail startup;
  schema-dependent checks are pending only until a declared/generated schema exists and
  remain mandatory after SQL returns and before RLS. Nothing here needs a database.
* **Phase 3b — population (VM):** run the generator, act on the health report, curate
  the top ~30 queries by telemetry, and maintain real aliases only in the local alias
  overlay.

Otherwise: highest-confidence work first, riskiest last. Phase 6 lands last and on its
own flag.

### Branch and PR strategy — how phases build on each other

The phases are sequentially dependent, but `main` must stay frozen until the operator
can validate on the VM. Both properties are satisfied by an **integration branch**.

```
main  ──────────────────────────────────────────────────────►  (frozen, production)
   └── pk/rebuild  ─●───●───●───●───●───●───●──►  final PR → main (after VM validation)
                    │   │   │   │   │   │   │
                    └───┴───┴───┴───┴───┴───┴──  one squash-merged PR per phase
                                                 (pk/phase-1-correctness, …)
```

**Per-phase procedure:**

1. Branch `pk/phase-<N>-<slug>` **from the tip of `origin/pk/rebuild`** — never from
   `main`. It therefore already contains every previously completed phase.
2. Open the PR with **base = `pk/rebuild`**, not `main`. The diff then shows *only*
   that phase, so automated review sees ~1 phase of change instead of re-reviewing
   everything already reviewed.
3. Apply review findings as commits on the phase branch until clean.
4. **Squash-merge into `pk/rebuild`.** This is safe: `pk/rebuild` is not production and
   nothing ships from it.
5. The next session branches from the updated `pk/rebuild`.

**At the end:** a single PR `pk/rebuild → main`. Because every phase is squash-merged,
`pk/rebuild` carries exactly one commit per phase, which keeps that final PR readable.
The operator validates on the VM with `MERGEN_PK_ENGINE=v1` (everything dormant),
flips to `v2`, then merges.

**Rules:**

* **Never** open a phase PR against `main`; the accumulated diff makes review useless.
* **Never** branch a phase from `main`; it silently discards prior phases.
* Do **not** leave the per-phase PRs unmerged waiting for VM validation — that is what
  breaks the dependency chain. Merge them into `pk/rebuild`; `main` is protected by the
  integration branch, not by leaving PRs open.
* If `main` moves during the effort, merge `main` into `pk/rebuild` periodically so
  conflicts surface early rather than all at once in the final PR.
* If a later phase reveals an earlier phase was wrong, fix it as a normal PR into
  `pk/rebuild`. Do not rewrite merged history.
* Verify on the first PR that the repository's automated review runs against a
  non-`main` base. If it does not, fall back to `main` as the base and accept the
  redundant diff.

### Session structure

One phase ≈ one Claude Code session ≈ one pull request. Do not attempt multiple
phases in a single session; context exhaustion mid-phase produces half-migrated code,
which is worse than not starting.

Each session must:

1. **Branch from `origin/pk/rebuild`** and confirm it is at the expected tip:
   `git fetch origin pk/rebuild && git log --oneline -8 origin/pk/rebuild`.
2. Read `.ai/pk-rebuild-progress.md`, then **cross-check its claims against that git
   log**. If the file says phase 3 is merged and the log does not show it, trust the
   log and record the discrepancy. This catches stale checkouts and sessions that
   forgot to update the file.
3. Read this document **and re-verify** the defects it is about to fix (§0.1). Report
   any that no longer reproduce.
4. Implement exactly one phase. **v2 pipeline work goes behind `MERGEN_PK_ENGINE=v2`;
   the four cross-engine changes must NOT** — RLS fail-closed (D6/D6b, unconditional),
   statement-aware SQL classifier (D23, unconditional), ODBC error redaction (D22), and
   observation-only telemetry plus typed filter status (`MERGEN_PK_TELEMETRY`,
   fail-soft). Gating those behind `v2` would leave the fail-open RLS path and unsafe
   SQL validator live, while collecting incomplete usage data for as long as `v1` is
   the default, which is the entire period this work runs. See §10.
5. Add the offline tests listed for that phase in §7.
6. Run `source("tests/scripts/parse_sanity_check.R", encoding = "UTF-8")`,
   `bash tools/seam_doctor.sh`, the maintainability ratchet test, and
   `bash tools/ai_validate.sh quick` (or `cloud-quick` when heavy packages cannot
   install).

   **Additionally, `bash tools/ai_validate.sh full --boot-smoke` is MANDATORY for any
   phase touching RLS/security, runtime source order, DB behavior, async execution,
   streaming, or the download lifecycle** — which is Phases 0, 1, 2, 3a and 6.
   `quick` / `cloud-quick` do not perform app-source or Shiny boot smoke, and
   `CLAUDE.md` / `AGENTS.md` require the full profile for exactly these categories.
   Do not defer the only full gate to the final rollout, where a boot failure would be
   attributed to the wrong phase.

   If the full profile genuinely cannot run in the session (heavy package bootstrap
   failure), that is an **unmet gate**, not a pass: record it explicitly in the PR and
   in `.ai/pk-rebuild-progress.md` as *"full --boot-smoke NOT RUN — must run on the VM
   before this phase is merged to main"*, and report the real failing command output.
   Never describe the phase as validated.
7. **Update `.ai/pk-rebuild-progress.md`** before finishing — this is not optional; it
   is the only channel through which reasoning reaches the next session.
8. Open a PR for that phase only, with base `pk/rebuild`.

### `.ai/pk-rebuild-progress.md` contract

Created by the first session, appended by every later one. This file carries the
**reasoning**; git carries the **code**. A session that reads only one of the two will
make avoidable mistakes.

Per phase:

* status: `not_started` / `in_progress` / `in_review` / `merged_to_rebuild` /
  `vm_validated`
* branch name and PR link; the squash-merge commit SHA on `pk/rebuild` once merged
* files added and modified
* tests added, and what each proves
* **design decisions taken, with reasoning** — so a later session does not silently
  reverse them
* deviations from this plan, and why
* review findings received and how each was resolved
* what remains unproven and requires the VM
* exact validation commands run, and their real results

Plus a short header listing, in order, which phases are already merged into
`pk/rebuild`. A session must not start phase N+1 while phase N is still `in_review`.

### Rules for the agent while the operator is away

* **Never claim VM, runtime, browser, SSO, DB or SQL Server validation.** Cloud runs
  prove parse sanity and offline contract tests, nothing more (`CLAUDE.md`, validation
  honesty).
* **Never delete or refactor the v1 path** to make v2 cleaner.
* **Never raise a maintainability ratchet budget.** Split instead.
* **Never invent query metadata.** The checkout has 4 placeholder queries; production
  has ~169. Metadata is generated on the VM, not guessed here.
* **If blocked, stop and document** in the progress file rather than guessing at
  production behavior. A clearly documented blocker is a good outcome; a plausible
  guess baked into the engine is not.
* **If a design decision in this document turns out to be wrong when implemented, say
  so in the progress file and in the PR**, and propose the alternative. This plan is
  evidence-based, not infallible.

---

## 12. Design decisions to confirm with the operator

### Resolved

| # | Decision |
|---|---|---|
| R1 | **Phase 0 (telemetry) ships first, with typed timeout/error/no-filter status plumbing.** It is cheap, it makes today's silent failures visible immediately, and its usage data is what prioritizes the Phase 3 metadata work. |
| R2 | **`writexl` is the export baseline** — already in `required_packages`, correct native types, multi-sheet, zero new dependency (`renv.lock` is VM-generated, so a cloud session must not add packages). `openxlsx` formatting is gated behind `requireNamespace()`: plain-but-correct without it, polished with it. Phase-2 acceptance is writer-specific; `readxl` cannot prove rendered styles. |
| R3 | **`keywords` / `sample_questions` are optional and must not be generated by the on-prem LLMs** (§5.1). When present, a bounded sample-question representation is included in Pass A so recall cannot lose terminology that appears only there. |
| R4 | **Metadata uses four runtime layers** — committed empty scaffold `R/library_query_meta_auto.R`, gitignored generator output `R/library_query_meta_local.R`, tracked approved/synthetic curation `R/library_query_meta.R`, and the gitignored operator-maintained production alias overlay `R/library_query_aliases_local.R`. The generator writes only its local metadata output, so production schema statistics and alias targets cannot reach GitHub through a routine commit (§5.1). |
| R5 | **The v2 *pipeline* ships behind `MERGEN_PK_ENGINE`, with `v1` remaining the default** until VM validation (§10). Four things sit outside that gate by design because they must apply to both engines: RLS fail-closed, the statement-aware SQL classifier, error redaction, and observation-only instrumentation plus typed filter status. |
| R6 | **Capability validation uses stable ASCII-safe IDs for measures, date meanings and required output dimensions.** `requirements.measures` / `requirements.dates` / `requirements.dimensions` and `column_meta$capability` share one allowlisted registry, so planned versus remaining labor, start versus finish dates, and person/resource output cannot be confused by labels, subject entities, generic booleans or lexical matching. |

### Still open

1. Clarification UX — chips in the chat bubble vs a modal.
2. Inline table threshold — is `MERGEN_PK_DT_MAX_ROWS = 200` right for the `DT` widget?
3. Should XLSX export be automatic above the threshold, or an explicit user action?
4. Is a physically read-only DB principal available for the analysis connection (D23)?
   The application statement classifier is mandatory regardless; this question concerns
   defense in depth and deployment configuration only.
5. `MB_Analiz_Log` retention, and whether raw question text may be stored
   (`MERGEN_PK_LOG_QUESTION_TEXT`) — questions may contain project names.
6. **May query names and descriptions leave the corporate network** for the optional
   `keywords` / `sample_questions` drafting path (§5.1, option 2)? If no, use option 1
   or 3.
7. Default `MERGEN_PK_ROW_CAP = 50000` — acceptable for the heaviest of the 169
   queries, or should specific queries carry a larger per-query `row_cap`?
8. Shadow-mode sampling percentage and how long to run it before flipping
   `MERGEN_PK_ENGINE=v2` (§10).
9. Should `openxlsx` be added to `required_packages` on the VM, enabling formatted
   export permanently?

---

## 13. Non-negotiable constraints (from `CLAUDE.md`)

* **Turkish text integrity.** UTF-8 everywhere; no Latinization; no mojibake. All
  DB writes go through `normalize_db_visible_value()` / `normalize_db_technical_value()`;
  never whole-list `repair_mojibake = TRUE` on mixed parameter lists.
* **Turkish comments** in all R code added by this work.
* **Source order.** Every new runtime R file must be declared in
  `R/config_source_manifest.R` in dependency order and owned by exactly one seam in
  `R/config_seam_registry.R`. Every new CSS/JS asset must be in
  `R/config_ui_assets.R` **and** in `R/config_ui_asset_zones.R`. There must be no
  orphan runtime file — `bash tools/seam_doctor.sh` must stay green.
* **Maintainability ratchet.** Do not raise any budget. Split into focused helpers.
* **No CDN, no runtime downloads, no new heavy dependencies.** Offline/on-prem only.
* **No `renv.lock` generation from a cloud session.**
* **No DDL at startup.** `MB_Analiz_Log` ships as an idempotent script under
  `docs/sql/` for manual DBA application, with a separate rollback script.
* **Secret safety.** Never log or surface API keys, tokens, DSNs, connection strings,
  or raw ODBC diagnostics.
* **Async safety.** `tracked_future_promise(..., dependency_mode = "explicit")`;
  never serialize sessions or reactive values; `shiny::isolate()` every reactive read
  inside a promise/`later` callback; request-id guards on every callback.
* **Validation honesty.** Never claim a gate passed unless the command ran and
  reported zero failures. `cloud-quick` is not runtime, VM, DB, browser, or SQL
  Server proof.

---

## 14. What cannot be proven in a cloud session

These require the Windows VM and must be reported as unproven until run there:

* Real behavior against the 169-query production library.
* **Running `tools/pk/generate_query_meta.R`** — it needs the real query library and a
  live DB connection, so `R/library_query_meta_local.R` cannot be produced in a cloud
  session, and the query-library health report cannot be generated.
* Production alias/vocabulary validation against the optional
  `R/library_query_aliases_local.R` overlay.
* Shadow-mode agreement rates against real Turkish questions.
* SQL Server execution, the read-only statement gate against SQL Server grammar,
  ODBC timeout/error behavior, Turkish at-rest values, and `sp_executesql` behavior.
* RLS correctness against real `DC01_user_base` / PY / EPS permission data.
* SSO identity readiness timing.
* Real LLM endpoint latency, selection accuracy, and timeout behavior with
  `gemma-4-31B-it`.
* Excel files opening correctly in real Excel on Turkish Windows.
* Event-loop responsiveness for a second concurrent session.
* UNC path and network-share latency.

Required VM gates for this work: `bash tools/ai_validate.sh full --boot-smoke`,
`tests/scripts/run_vm_preflight_real.R`,
`tests/scripts/run_vm_encoding_preflight_real.R` with
`MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST=TRUE`, and
`bash tools/vm_evidence_gate.sh`.

---

## 15. Success criteria

The tool is done when all of the following hold:

1. A question naming two projects returns both — never zero rows.
2. A partial/misspelled Turkish project name resolves, or asks, or explains — never
   silently returns nothing and never silently analyzes everything.
3. Every number in every answer traces to the correct structured R fact — measure,
   unit, aggregation, authorized/filter scope, group and date window — over the **full**
   dataset.
4. A 50,000-row result is summarized as accurately as a 500-row result, at
   comparable token cost.
5. Requesting a long list yields a correct, verified, complete multipart Excel/CSV
   export or an explicit request to narrow the result — never a silently capped file —
   and a readable bubble.
6. Every answer states which query ran, which filters applied, and what degraded.
7. A missing or mistyped RLS column stops the query instead of exposing data.
8. Any SQL batch not provably one read-only SELECT is rejected by the shared
   statement-aware classifier before v1, v2, deep mode or metadata tooling can execute
   it.
9. One user's large analysis does not freeze another user's session or exhaust memory
   through an underestimated variable-width result.
10. Selection accuracy, filter accuracy, and clarification rate are **numbers on a
   dashboard**, not opinions.
11. Adding query #170 means filling a metadata template — not touching engine code.

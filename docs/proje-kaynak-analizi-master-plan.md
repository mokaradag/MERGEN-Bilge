# Proje ve Kaynak Analizi — Master Rebuild Plan

**Status:** design / work order. No code has been changed for this plan yet.
**Audience:** the coding agent (and maintainers) who will implement it.
**Language note:** this document is English like `CLAUDE.md`, because it is an agent
contract. All *user-facing* strings, R comments, and identifiers produced by the
implementation must stay Turkish per `CLAUDE.md` rules 1 and 2.

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
   §10 lists the constraints that most commonly get violated in this area.
4. **Phases are independently shippable.** Do not attempt the whole plan in one
   change. Phase 1 alone fixes most of what users report today.
5. **Validation honesty is mandatory.** Cloud sessions cannot prove runtime, VM,
   SSO, SQL Server, or browser behavior. §11 lists what is VM-only.

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

This is the single most serious finding in the inventory.

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
SQL by accepting `INSERT|UPDATE|EXEC`. `MERGE`, `sp_`, `xp_` are unblocked. Should
be an allowlist (`^\s*(WITH|SELECT)`) over a physically read-only DB principal.

### D24 · S3 · No row cap, no caching, no telemetry

Nothing limits result size before it lands in R memory; identical follow-ups re-run
SQL plus both LLM calls; and no record exists of which of the 169 queries are
actually used or how often selection/filtering is wrong.

### 3.9 Claims tested and **withdrawn** — do not "fix" these

Both were plausible from reading and were disproved in R. Re-test before acting on
any similar-looking claim.

| Suspected | Test | Result |
|---|---|---|
| `grepl("\\{.*\\}", ai_text)` at `filters.R:208` rejects multi-line JSON | `grepl("\\{.*\\}", "{\n \"filters\": []\n}")` | **TRUE** — R's default TRE `.` matches newline. Not a bug. |
| `nchar(ai_text) < 50` at `filters.R:203` rejects valid short JSON | minimal empty-filter JSON = 60 chars; single-filter JSON = 70 chars | Not triggered in practice. Still fragile (prefer structural validation), but not a live defect. |

---

## 4. Target architecture

Each stage produces a **typed result with a status**, so a wrong answer can be
traced to the stage that produced it.

```
 1. Request intake            user prompt + chat history + session identity
 2. Query selection           AI recall → AI precision → capability validation
 3. Query contract validation declared metadata vs actual result columns
 4. SQL execution             row-capped, read-only, async
 5. RLS enforcement           FAIL-CLOSED
 6. Intent & filter plan      LLM → typed filter tree (never R code)
 7. Entity resolution         Turkish fuzzy → canonical values (deterministic)
 8. Filter compilation        typed tree → data.table ops (OR-in-column / AND-across)
 9. Analysis packet           whole-dataset statistics, computed in R
10. Answer composition        LLM prose + R table + R attachment
11. Provenance & telemetry    what ran, what resolved, what degraded
```

Stage boundaries are the testing seams. Stages 6–9 are pure functions and must be
offline-testable with no DB, LLM, or browser.

---

## 5. Stage designs

### 5.1 Query metadata contract (`R/library_query_meta.R`)

**Keep this out of `R/library_queries.R`.** 169 × ~40 lines inline would add ~7,000
lines to one file and breach the maintainability ratchet. Store metadata keyed by
stable query `id`, merged at load time in `R/config_sql_loader.R`.

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
  grain            = "activity_assignment",   # one row = one assignment
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
                           match = "resolve", filterable = TRUE),
    Durum           = list(label = "Durum", role = "dimension",
                           domain = list("1" = "Aktif", "0" = "Pasif")),
    KalanIscilik_sa = list(label = "Kalan İşçilik", role = "measure",
                           unit = "saat", decimals = 1, additive = TRUE),
    TamamlanmaYuzde = list(label = "Tamamlanma", role = "measure",
                           unit = "%", decimals = 1, additive = FALSE,
                           aggregate = "weighted_mean",
                           weight_by = "PlanlananIscilik_sa")
  )
)
```

**Field roles.** `role ∈ {id, dimension, measure, date}` drives summarization.
`additive` decides whether SUM is legal at all. `aggregate ∈ {sum, mean,
weighted_mean, latest, none}` plus `weight_by` prevents averaging averages.
`match ∈ {exact, resolve, contains, none}` drives entity resolution — **codes and
sicil numbers must be `exact` and must never be fuzzily altered**. `unit` and
`decimals` drive both number formatting and Excel cell formats. `grain` is what
stops project totals being summed once per activity row.

**Generation strategy — do not hand-write this.**

| Tier | How | Effort |
|---|---|---|
| 0 | **No metadata must still work.** Infer `role` from R type + cardinality, `high_cardinality` from `n_distinct > 50`, `date` from class. Degraded but functional. | 0 |
| 1 | One-time generator (`tools/pk/generate_query_meta.R`, VM-only, `TOP 500` per query): emits the `column_meta` skeleton with names, types, cardinality, null rate, ID detection, date detection, measure candidates. **Also validates declared `rls_columns` against actual columns → immediately surfaces every D6 hole.** | ~1 day, once |
| 2 | LLM-drafted `keywords` + `sample_questions` from existing `name`/`description`/columns; human reviews. | ~45 s/query |
| 3 | Human-only: `grain`, `additive`, `unit`, `primary_entity`, `intents`, `default_measures`. | ~2 min/query |

**Prioritize by telemetry, not by list order.** Ship Phase 0 telemetry first; after a
week the top ~30 queries will cover most traffic. Enrich those; the tail can stay at
Tier 0/1 indefinitely.

**Startup validation** (contract test, must fail the build): duplicate ids, missing
SQL, `rls_columns` referencing non-existent columns, `column_meta` keys not present
in the result, `weight_by` pointing at a non-measure, unknown `role`/`aggregate`
values.

### 5.2 Query selection

Replace the current AI-or-heuristic split. **The lexical scorer must never make a
selection decision** — a shortlist that drops the correct query is an unrecoverable
silent failure, which is exactly the bottleneck to avoid.

**Pass A — recall (LLM, full library).** Send all queries as compact one-liners
(`q042 | Aktivite Rol Atamaları`, ~30 chars each ≈ 5 KB for 169). Ask for the top 5
candidate **ids**. Full recall by construction.

**Pass B — precision (LLM, 5 candidates).** Send those 5 with full description,
`sample_questions`, column labels, `intents`/`not_for`, and the last 2 conversation
turns. Return:

```json
{"id":"q042","confidence":78,"reason":"...","alternates":["q108","q055"],
 "missing_info":null}
```

**Then, deterministically:**

* **Stable ids only.** Never list positions (D13).
* **Capability validation.** Verify the selected query actually contains the entity,
  measure and dimension the request needs. A confident model pointing at a query with
  no date column cannot answer "2024'te".
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
      {"column": "Durum", "match": "exact", "value": "1"},
      {"column": "BaslangicTarihi", "match": "range",
       "from": "2024-01-01", "to": "2024-12-31"}
    ]
  }
}
```

Rules: allowed node ops are `AND`/`OR`/`NOT` plus leaves; leaf `match ∈ {exact,
resolve, contains, range, gt, lt, in}`; **`phrase` carries the user's own words**,
never a guessed DB value; every `column` must exist and be `filterable` in
`column_meta` or the leaf is rejected with a logged reason (never silently dropped —
D9). Depth and node count are bounded. `filter_expression` and `eval(parse())` are
removed entirely (D5).

Turkish relative dates (*"son 3 ay"*, *"geçen yıl"*, *"2024 Q3"*) are extracted as
phrases and resolved **in R** against the dataset's actual date range — never by
model arithmetic.

### 5.4 Entity resolution (`R/helpers_pk_entity_resolver.R`)

Deterministic, pure, offline-testable. Resolves a user phrase against the **closed
vocabulary** of a column's actual distinct values.

**Normalization pipeline (shared `pk_tr_fold()` — the single Turkish authority):**
Unicode NFC → Turkish-aware fold (explicit `İ→i`, `I→ı`, then `tolower`) →
strip apostrophe clitics (`ANKA'nın`, `PGRM'deki`, `Ahmet Yılmaz'ın`) → strip common
suffixes for matching only (`-nin`, `-de`, `-deki`, `-siyle`) → collapse punctuation
and whitespace → token set. **`pk_tr_fold()` must replace every `tolower()` and
`ignore.case = TRUE` in this subsystem** (D3).

**Scoring cascade** (`stringdist` is already in `required_packages`):

| Tier | Rule | Score |
|---|---|---|
| 1 | Exact fold match | 100 |
| 2 | Known alias | 95 |
| 3 | All user tokens contained, order-free | 85–92 |
| 4 | Token-set Jaccard ≥ 0.6 | 60–85 |
| 5 | Normalized edit distance ≤ 0.2 (typos) | 50–70 |

Token-set similarity outranks plain edit distance for long project names, where the
right words appear in a different order.

**Decision policy — this is the safety mechanism, not the scoring:**

| Situation | Action |
|---|---|
| Exact code / ID match | Filter automatically |
| One candidate ≥ 85 with clear margin over #2 | Filter automatically |
| 2–5 candidates ≥ 70 | Filter with `%in%` on **all** of them (OR) **and name them** in the answer |
| Ambiguous (top two within ~10 points) | **Ask** — render candidates as chips |
| Best < 40 **and** the entity is the subject of the question | **Do not analyze.** Report that the value could not be resolved and offer the nearest candidates |
| Best < 40 and the entity was a secondary refinement | Proceed unfiltered **with prominent disclosure** |

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
operation. **OR within a column, AND across columns** (D1), full multi-value support
(D2), Turkish-folded comparison (D3).

Additional required behaviors:

* **No-op detection.** A filter matching ≥95% of rows is reported as ineffective.
* **Zero-match handling** per the §5.4 policy (D4) — never an empty screen with no
  explanation.
* **Provenance record per leaf:**
  `{requested_column, user_phrase, canonical_values, match_method, confidence,
    logical_group, rows_before, rows_after, warnings}`.
  This structure feeds the answer footer, the Excel `Bilgi` sheet, and telemetry.

### 5.6 RLS hardening

* **Fail closed** (D6): a declared RLS column absent from the result set aborts the
  query with a clear Turkish error and a loud log line. Never silently skip.
* Validate `rls_columns` for all queries **at startup**, not per request.
* Guard `NA` in `Yetki` (`security_summary.R:133`).
* Normalize both sides of `%in%` comparisons through `pk_tr_fold()` so whitespace or
  casing drift in `MasrafYeriKodu` does not silently empty the result.
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
                where `aggregate = "weighted_mean"`
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

**Formatting:** every number rendered explicitly with `formatC`/`format` using
`decimals` and `unit` from metadata. **No `capture.output(print(...))`** (D19). Use
one consistent naming system (`label` from metadata) for both the statistics and the
example rows — currently the summary prettifies names while the JSON does not.

**Budget accounting:** one accountant over the **entire assembled prompt** — summary
+ tables + example rows (D7). Budget derives from the model's context window, not a
hardcoded constant. Degrade in priority order: example rows → top-K depth →
low-signal columns; **always state what was omitted**. The `FİLTRELEME UYARISI` must
survive every degradation path (D8).

**Very broad queries:** partition deterministically (department / programme / month),
summarize each partition in R, merge the numbers in R, and give the LLM the merged
packet. The model performs narrative synthesis over reconciled figures — never
arithmetic map-reduce.

### 5.8 Answer composition — prose + table + attachment

| Part | Owner | Rule |
|---|---|---|
| Prose | LLM | May cite only numbers present in the packet. Computes nothing. |
| Table | R | Deterministic render. **Never regenerated by the model.** |
| Attachment | R | Complete result, exact values. |

**Thresholds (configurable):**

| Result size | Rendering |
|---|---|
| ≤ 15 rows and ≤ 8 cols | Markdown table inline |
| ≤ 200 rows | Scrollable `DT` widget in the bubble (same seam as ChartLab's `wire_chart_output`) |
| > 200 rows, or > 12 cols, or the user says *liste / döküm / rapor / excel / dışa aktar* | **XLSX attachment** + 10-row inline preview |

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
which query ran (id + name), applied filters, resolved entities, rows before/after
RLS and filtering, any degradation, and the attachment link. Users can only catch a
wrong query selection if the selection is visible.

### 5.9 Excel export (`R/helpers_pk_export_xlsx.R`)

**Dependencies.** `writexl`, `readxl`, `DT`, `stringdist` are already in
`required_packages`; `openxlsx` is **not**. Build on `writexl` as the baseline —
correct native types, multiple sheets, zero new dependency (`renv.lock` is
VM-generated, so a cloud session must not add packages). Gate formatting
enhancements (number formats, freeze panes, autofilter, column widths) behind
`requireNamespace("openxlsx")`: plain-but-correct without it, polished with it.

**Correctness requirements — these are what prevent "corrupted / wrong" files:**

1. **Native types.** Numeric as numeric, Date as Date. Never `as.character()`
   everything — this is the primary cause of "the Excel table is wrong".
2. **Number formats from metadata.** `unit = "TL"` → `#,##0.00`; hours → `#,##0.0`;
   percent → `0.0%`. Another dividend from §5.1.
3. **Values only, no formulas.** Formula writing is what triggers Excel's repair
   dialog.
4. **Turkish.** XLSX is UTF-8 XML internally and is safe *provided* strings pass
   through `normalize_pk_dataframe_utf8()` first. Sanitize sheet names (≤31 chars,
   no `[]:*?/\`); Turkish characters are allowed in them.
5. **Three sheets:** `Veri` (full data), `Özet` (the R-computed statistics),
   **`Bilgi`** (provenance: query id/name, run timestamp, user, applied filters,
   resolved canonical entities, RLS scope, rows before/after, truncation notice).
   The `Bilgi` sheet is what makes a figure defensible when it is pasted into a
   management report.
6. **Row cap** well below Excel's 1,048,576 (suggest 100,000), disclosed in `Bilgi`
   **and** in the prose.
7. **Verify before serving.** Read the written file back with `readxl`; assert row
   count, column count, and a sample-column checksum. On failure **do not serve the
   file** — fall back to UTF-8-**BOM** CSV (Excel needs the BOM to detect UTF-8, the
   same rule as the Bilge Yolaç `.txt` contract) and say so in the answer.

**Serving — security requirement.** These exports are **RLS-filtered per user**.
They must **NOT** be written into `bilge_yolac_downloads/`, which is registered
globally with `addResourcePath` — a guessable URL there would expose one user's
authorized rows to another. Serve session-scoped via `session$registerDataObj`
(the pattern `mergen_serve_image_data_url()` uses in `R/helpers_markdown_safety.R`)
or a `downloadHandler`. Clean up on session end with the existing
`register_session_cleanup_on_end()` / `safe_unlink_if_exists()`.

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

Also add: a per-query `row_cap` pushed into SQL (`TOP`/`OFFSET-FETCH`) with a
truncation notice, and a short-TTL cache keyed on `(query_id, rls_signature,
filter_signature)` so follow-ups are instant.

### 5.11 Provenance, telemetry, degradation

**Every** degradation must appear in the answer: LLM timeout, dropped filter,
unresolved entity, truncated rows, narrowed RLS scope, omitted columns.

**Telemetry table `MB_Analiz_Log`** (idempotent DDL under `docs/sql/`, manual DBA
apply, never at startup — same rules as the other `MB_*` families): question hash,
selected query id, confidence, alternates, resolution outcomes, rows before/after,
per-stage latency, degradation flags, attachment produced. This is how the tool
becomes measurable — and it is what tells you which 30 of 169 queries deserve
metadata first.

**Numeric provenance check.** Extract numeric tokens from the model's answer and
compare against the numbers present in the packet (with formatting tolerance). Log
mismatches as a metric. Even as telemetry-only, this gives a *measured* hallucination
rate — the enforceable form of "the LLM must never invent numbers."

**Empty-result taxonomy** — four distinct messages, not one: no such data · none
within your authorization · filter matched nothing · query returned nothing.

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
| `R/library_query_meta.R` | per-query metadata keyed by stable id | data |
| `tools/pk/generate_query_meta.R` | VM-only metadata generator (NOT in manifest) | script |

**Modified:** `R/module_proje_kaynak_analizi.R` (becomes a thin orchestrator),
`R/helpers_pk_analysis_filters.R` (rewritten around the typed tree),
`R/helpers_pk_analysis_security_summary.R` (RLS fail-closed; summary moves out),
`R/helpers_pk_analysis_query_selection.R` (heuristic demoted to non-deciding),
`R/helpers_deep_analysis.R` (reconciled with the main path — D16),
`R/library_queries.R` (unchanged structurally; metadata lives elsewhere),
`R/config_sql_loader.R` (merge metadata, validate contracts at startup),
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
| `test-pk-text-turkish-behavior.R` | `pk_tr_fold()` on İ/I/ı/i, clitics, suffixes; locale independence |
| `test-pk-filter-compile-behavior.R` | **OR-in-column / AND-across** (D1), multi-value (D2), ranges, NOT, no-op detection |
| `test-pk-entity-resolver-behavior.R` | all 5 scoring tiers, every decision-policy branch, code-exactness |
| `test-pk-filter-plan-contract.R` | typed tree validation; **rejects any executable expression** (D5) |
| `test-pk-rls-failclosed-contract.R` | missing declared RLS column → **abort, not skip** (D6) |
| `test-pk-analysis-packet-behavior.R` | additive vs non-additive, weighted means, budget accountant, stratified sample, `FİLTRELEME UYARISI` survives degradation (D7, D8) |
| `test-pk-export-xlsx-behavior.R` | native types, Turkish round-trip, verification failure → CSV fallback, **not served from `bilge_yolac_downloads`** |
| `test-pk-query-meta-contract.R` | startup validation: duplicate ids, RLS columns exist, `column_meta` matches result |
| `test-pk-degradation-disclosure-contract.R` | every degradation path reaches the user-visible answer (D9) |

**Turkish golden set** — the thing that makes "world class" measurable.
`tests/fixtures/pk_golden_set.json`, target ~100–200 real questions:

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

Each phase is independently shippable and independently validatable.

### Phase 0 — Instrumentation (½ day)
Telemetry (`MB_Analiz_Log`) + degradation disclosure + provenance footer.
**Do this first**: it costs little, it immediately makes today's silent failures
visible, and it produces the usage data that prioritizes Phase 3.
*Acceptance:* every answer carries a provenance footer; every timeout/dropped
filter appears in the answer and in the log.

### Phase 1 — Surgical correctness (2–3 days) ← **fixes most reported symptoms**
D1 (OR-in-column) · D2 (multi-value) · D3 (`pk_tr_fold`) · D4 (zero-match policy) ·
D5 (remove `eval(parse)`) · D6 (RLS fail-closed) · D7/D8 (budget + warning) ·
D9 (disclose timeout) · D12 (dead code) · D22 (redact ODBC errors).
*Acceptance:* the new offline tests pass; a two-value same-column question returns
rows; a nonsense project name returns an explained full-set answer or a clarification,
never an empty screen.

### Phase 2 — Deterministic analysis + export (3–5 days)
Analysis packet (§5.7) · answer composition (§5.8) · XLSX export (§5.9) ·
epistemic labelling · remove the "generate a markdown table" instruction.
*Acceptance:* a 5,000-row result produces a correct XLSX that round-trips through
`readxl`, a bubble that is not a wall of table, and prose containing no number
absent from the packet.

### Phase 3 — Metadata foundation (1 day tooling + rolling enrichment)
Generator · `R/library_query_meta.R` · startup contract validation · Tier-0
inference for unenriched queries · enrich the top ~30 queries by telemetry.
*Acceptance:* startup fails on an invalid contract; every enriched query has
`grain` + `additive` + `unit`; unenriched queries still work.

### Phase 4 — Entity resolution (2–3 days)
`pk_tr_fold`-based resolver · decision policy · clarification chips ·
`chat_history` wiring for follow-up refinement (D11).
*Acceptance:* long project names resolve from partial Turkish phrases; ambiguity
produces chips, not a guess; codes are never fuzzed.

### Phase 5 — Selection rebuild (2–3 days)
Two-pass AI · stable ids (D13) · capability validation · confidence gate ·
timeouts + repair retry (D14) · heuristic demoted to non-deciding (D10) ·
trigram+IDF retrieval.
*Acceptance:* low-confidence requests ask instead of guessing; reordering
`library_queries.R` changes nothing; recall@5 measured on the golden set.

### Phase 6 — Non-blocking + performance (2–3 days)
Async dispatch (D15) · SQL row caps · caching · deep-mode reconciliation (D16).
*Acceptance:* a second browser session stays responsive while a large analysis runs
on the VM.

### Phase 7 — Measurement (ongoing)
Golden set to ~200 cases · live scored run · audit dashboard (selection accuracy,
filter accuracy, clarification rate, zero-result rate, silent-fallback rate,
numeric-provenance mismatch rate).

---

## 9. Design decisions to confirm with the operator

1. Clarification UX — chips in the chat bubble vs a modal.
2. Inline table threshold — is 200 rows right for the DT widget?
3. Should XLSX export be automatic above the threshold, or an explicit user action?
4. Add `openxlsx` to `required_packages` on the VM (for formatted export), or stay
   on `writexl` only?
5. Is a physically read-only DB principal available for the analysis connection?
6. `MB_Analiz_Log` retention policy and whether question text may be stored
   (it may contain project names — treat as sensitive).

---

## 10. Non-negotiable constraints (from `CLAUDE.md`)

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

## 11. What cannot be proven in a cloud session

These require the Windows VM and must be reported as unproven until run there:

* Real behavior against the 169-query production library.
* SQL Server execution, Turkish at-rest values, and `sp_executesql` behavior.
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

## 12. Success criteria

The tool is done when all of the following hold:

1. A question naming two projects returns both — never zero rows.
2. A partial/misspelled Turkish project name resolves, or asks, or explains — never
   silently returns nothing and never silently analyzes everything.
3. Every number in every answer traces to an R computation over the **full** dataset.
4. A 50,000-row result is summarized as accurately as a 500-row result, at
   comparable token cost.
5. Requesting a long list yields a correct, verified, downloadable Excel file and a
   readable bubble.
6. Every answer states which query ran, which filters applied, and what degraded.
7. A missing or mistyped RLS column stops the query instead of exposing data.
8. One user's large analysis does not freeze another user's session.
9. Selection accuracy, filter accuracy, and clarification rate are **numbers on a
   dashboard**, not opinions.
10. Adding query #170 means filling a metadata template — not touching engine code.

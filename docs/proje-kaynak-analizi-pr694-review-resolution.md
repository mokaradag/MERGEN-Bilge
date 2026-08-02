# PR #694 — Normative Codex Resolution Addendum

This addendum is part of the Proje ve Kaynak Analizi master work order and is **normative**. Where the master-plan wording is incomplete or conflicts with this file, this file wins. It resolves the five remaining Codex P1/P2 findings without changing runtime code, dependencies, source manifests, or maintainability ratchets.

## 1. Independent capability requirements (P1)

Capability intent is derived **before candidate selection** by a separate adapter that receives only:

- the raw user request;
- bounded relevant conversation context;
- the allowlisted capability registry.

It must not receive query IDs, query names, descriptions, SQL, candidate columns, or `column_meta`. Its typed result is validated by deterministic R code before recall begins:

```json
{
  "status": "ok",
  "requirements": {
    "entity": "project",
    "measures": ["labor.planned_hours"],
    "dates": ["date.project_start"],
    "dimensions": ["dimension.resource"],
    "group_by": null
  },
  "ambiguities": []
}
```

Pass B may rank candidates, but it may not create, amend, or weaken `requirements`. A selected query executes only when its metadata satisfies the independently derived requirements exactly. Ambiguous, malformed, or unknown capability intent produces clarification and no SQL execution.

**Required regression:** a stubbed candidate that exposes `labor.remaining_hours` cannot redefine a request for `labor.planned_hours`; selection fails even when candidate ID, confidence, and self-description are internally consistent.

## 2. Applicable RLS enforcement for every scoped role (P1)

Authorization is role-to-scope specific and fail-closed.

- Project-scoped roles such as `PY`, `KY-P`, and `DIR-P` require a non-`NULL`, non-empty project enforcement column.
- EPS-scoped roles require a non-`NULL`, non-empty EPS enforcement column.
- `NULL`, `NA`, an empty string, or an absent returned column is a contract failure. It never means “skip authorization.”
- The query stops before filtering, analysis, composition, or export when the active scoped role has no applicable predicate.

The only permitted alternative is an explicit `rls_enforcement` contract with:

- `mode = "secured_view"`;
- an exact allowlisted secured object identifier;
- the applicable `scope_kind`;
- a reviewed DBA control/attestation identifier.

Startup validation checks role applicability when a declared/generated schema is available. Request-time validation repeats the check unconditionally against the actual returned columns before any row is used.

**Required regressions:** project-scoped and EPS-scoped roles with `NULL`, empty, missing, or mistyped enforcement columns abort; an arbitrary view name or comment does not bypass the predicate; only an exact attested secured-view contract is accepted.

## 3. Duplicate grain blocks additive facts (P1)

Declared `grain_columns` are a correctness gate, not informational metadata.

Before emitting any additive overall or grouped fact, R must verify that:

1. every declared grain column exists; and
2. the combined grain key is unique within the authorized, user-filtered analysis scope.

If duplicates exist, every additive measure and additive derived group fact returns typed status `invalid_grain_duplicates`, includes the duplicate-key count, and emits **no numeric value**. Coverage, exact row export, and unaffected non-additive facts may remain available with an explicit limitation.

The implementation must not call `unique()`, keep the first row, or silently aggregate duplicate keys to force success. The SQL or metadata must be corrected to the true finer grain, or a separately reviewed pre-aggregated query contract must be supplied.

**Required regression:** duplicated grain keys produce no additive sum even when every measure value is finite; legitimate duplicate rows remain preserved in exact exports.

## 4. Request-wide export budgets (P2)

`MERGEN_PK_EXPORT_MAX_ROWS` is only the per-part limit. The complete export request is additionally bounded by:

| Variable | Default | Meaning |
|---|---:|---|
| `MERGEN_PK_EXPORT_MAX_TOTAL_ROWS` | `500000` | Maximum rows across the whole export |
| `MERGEN_PK_EXPORT_MAX_PARTS` | `10` | Maximum XLSX/CSV parts or data sheets |
| `MERGEN_PK_EXPORT_MAX_TOTAL_MB` | `512` | Maximum cumulative staged bytes, including verification and fallback copies |

Before creating the first temporary artifact, compute the exact row count and expected part count and establish a conservative serialized-byte upper bound from native types, declared maximum widths, and documented container/XML overhead. If any ceiling is exceeded—or no conservative byte bound can be established—refuse before staging and ask the user to narrow the request.

During writing, a request-scoped quota tracks actual cumulative temporary bytes and aborts with full cleanup before accepting a part that would cross the byte ceiling. Results within all budgets are split deterministically, every row appears exactly once, and the manifest records total rows, parts, and bytes. Truncation while claiming completeness is forbidden.

**Required regressions:** refusal occurs before the first temporary file for total-row, total-part, or estimated-byte violations; actual staged-byte overflow cleans every partial artifact; per-part success cannot bypass a request-wide limit.

## 5. Business ordering for `latest` ties (P2)

`aggregate = "latest"` requires all of the following:

- `latest_by`;
- `latest_by_direction` in `{asc, desc}`;
- ordered `latest_tie_order` entries, each containing `column`, `direction`, and reviewed business `semantics` explaining why that field orders revisions or authority.

Example:

```r
latest_by = "GuncellemeZamani",
latest_by_direction = "desc",
latest_tie_order = list(
  list(
    column = "RevizyonNo",
    direction = "desc",
    semantics = "higher_revision_is_newer"
  )
)
```

Uniqueness alone is not ordering. UUIDs, hashes, arbitrary surrogate IDs, database return order, `grain_columns` order, and “first row” are invalid tie breakers.

Runtime selects by `latest_by`, then applies the declared tie fields in order and direction. If a tie field is missing, contains missing values for the tied group, lacks business semantics, is not meaningfully orderable, or still leaves multiple rows, return `ambiguous_latest` and emit no latest fact.

**Required regressions:** a unique UUID does not resolve a timestamp tie; a declared revision number with direction and semantics does; unresolved ties never fall back to row order.

## Acceptance and scope

The five contracts above must be reflected in the implementation-phase tests named in the master plan:

- `test-pk-query-selection-contract.R`
- `test-pk-rls-failclosed-contract.R`
- `test-pk-analysis-packet-behavior.R`
- `test-pk-export-xlsx-behavior.R`
- `test-pk-query-meta-contract.R`

This PR remains documentation-only. It adds no runtime package, manifest entry, source-order change, generated artifact, or ratchet increase.

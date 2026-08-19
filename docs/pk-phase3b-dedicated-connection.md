# Phase 3b — Dedicated DB connection and `SET NOCOUNT ON` descriptor note

This note documents the 19 August 2026 compatibility correction for the Proje ve Kaynak Analizi metadata generator on PR #705.

## Why this was needed

A query-library health run can be executed from a long-lived RStudio process. When application pooling is enabled, the process may already contain a global `Pool` created earlier in the session. Reusing that pool for metadata discovery can make the generator describe queries through a stale physical connection/DSN context. The visible symptom is a sudden library-wide cluster of `describe_failed` / `object_missing` findings even though the same SQL works in SSMS and worked in an earlier health run.

Phase 3b metadata generation therefore no longer reuses the application/global pool. The generator opens one dedicated ODBC connection per configured target (`DB_DSN`, `DB_DSN_2`, `DB_DSN_3`) and the inventory loop reuses that connection for that target for the duration of the run. This is not a reconnect-per-query design and does not change the application's normal pooling behavior.

## `SET NOCOUNT ON` handling

The production SQL file remains unchanged. The common read-only gate still permits only the narrow compatibility form:

```sql
SET NOCOUNT ON;
<one read-only SELECT or CTE + SELECT>
```

All previous fail-closed protections remain in force. `SET NOCOUNT OFF`, other `SET` directives, extra statements, writes/DDL, `EXEC`, `SELECT ... INTO`, data-changing CTEs and sequence mutation remain rejected.

For static metadata description only, after the complete batch has already passed the shared read-only gate, the descriptor copy may remove the exact leading `SET NOCOUNT ON;` directive (and only that directive). SQL Server does not need `NOCOUNT` to determine the result-set schema. Runtime execution still receives the original approved batch, including `SET NOCOUNT ON;`.

This distinction is intentional:

- **SQL file:** unchanged.
- **Read-only security classification:** unchanged except for the already approved narrow NOCOUNT compatibility case.
- **Runtime execution:** original batch unchanged.
- **Static `describe` input:** exact safe NOCOUNT preamble may be omitted because it has no result-schema effect.

## Expected operator result

After pulling the correction, rerun:

```r
Sys.setenv(MERGEN_PK_META_MODE = "describe")
source("tools/pk/generate_query_meta.R", encoding = "UTF-8")
```

A query that previously showed `sql_not_readonly ... multiple_statements` solely because of `SET NOCOUNT ON;` should no longer be skipped for that reason. A run that previously showed a broad `object_missing` wave caused by a stale application pool should use a fresh dedicated connection from the configured DSN instead.

If a small number of individual queries still report `object_missing`, those should then be investigated as genuine query/database-object issues rather than treated as a library-wide connection-context failure.

## Ratchets

No maintainability, test-count, security, RLS, result-size, timeout, or other ratchet threshold is changed by this correction. The application pool implementation is not modified. The change is isolated to the operator-only Phase 3b metadata DB bridge plus focused regression coverage.

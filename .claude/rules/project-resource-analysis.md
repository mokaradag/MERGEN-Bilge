---
paths:
  - "R/helpers_pk_*.R"
  - "R/helpers_deep_analysis*.R"
  - "R/module_proje_kaynak_analizi.R"
  - "R/server_handler_pk_async.R"
  - "tools/pk/**"
  - "sql_queries/**"
  - "tests/**/*pk-*.R"
---

# Proje ve Kaynak Analizi

- Preserve one-session/one-query and authorized-real-data semantics where the
  current implementation/tests enforce them.
- Query selection, filter compilation, metadata, provenance, precision, packet
  construction, AI selection and async execution have separate ownership seams;
  do not recombine them into oversized helpers.
- Identity/RLS decisions are security boundaries. Never broaden data access on
  missing/ambiguous identity or metadata.
- SQL stays read-only and parameterized/validated through the owning helpers.
  Do not bypass local-temp/read-only guards or safe identifier handling.
- Turkish entity/filter text and technical tokens have different encoding
  constraints; keep ASCII-safe protocol tokens only where required.
- Large-result/prompt fitting must be bounded and deterministic; do not silently
  discard provenance or invent facts to fit a prompt.
- Real DB facts must remain distinguishable from model synthesis. Preserve
  source-table/provenance and numeric precision contracts.
- Async worker lifecycle, cancellation, markers, secrets and current-request
  checks remain non-blocking and fail-closed.
- Keep artifact serving, URL verification and disk cleanup in
  `R/helpers_pk_async_artifact.R`, loaded after the lifecycle helper and before
  the apply helper. Isolated lifecycle tests must also source the artifact helper.
- Generated query metadata/tooling is VM/operator-sensitive; do not claim cloud
  checks prove live DB metadata generation.
- Current query/schema inventories must be derived from the query library and
  metadata sources, not copied into Claude memory.
- For deep historical rationale, consult the archive's Proje/Kaynak analysis
  filter/query-selection/non-blocking/prompt-fitting/metadata sections.

---
paths:
  - "app.R"
  - "global.R"
  - "server.R"
  - "R/bootstrap*.R"
  - "R/config_source_manifest.R"
  - "R/config_seam*.R"
  - "R/server_*.R"
  - "R/helpers_performance_instrumentation.R"
  - "R/**/*runtime*.R"
  - "R/**/*async*.R"
  - "tests/**/*source-manifest*.R"
  - "tests/**/*runtime*.R"
  - "tests/**/*async*.R"
---

# Runtime architecture, source order and async work

- Boot/source order is production behavior. Register runtime files in the
  canonical source manifest at the correct dependency point; do not add ad-hoc
  sourcing.
- Treat `R/config_source_manifest.R`, seam registries, and source-manifest tests
  as the current source of truth; do not copy file inventories into docs/rules.
- Respect seam/zone ownership and maintainability budgets. Split through the
  existing ownership pattern instead of raising global ratchets.
- Keep `ServerRuntimeContext` small, explicit and synchronized with module
  wiring. Avoid hidden globals or stale startup snapshots.
- Session userData stores, auth-ready state, request IDs, and current-run guards
  have lifecycle semantics. Re-check current/active state in async callbacks.
- Expensive I/O/worker-safe work stays off the Shiny event loop where the
  architecture already dispatches it.
- `tracked_future_promise()` is both monitoring and a worker dependency
  boundary. Explicit dependency mode requires complete globals.
- Async jobs represented in health metrics must preserve tracked success/failure
  accounting.
- Source-time side effects remain guarded so isolated tests can source helpers
  without launching app/workers/network/services.
- Startup stage labels must represent actual readiness; do not announce a stage
  before it begins.
- Production launch/log behavior is Windows/on-prem sensitive; cloud success is
  not proof of launcher behavior.
- Consult archived runtime/ServerRuntimeContext/startup sections only when
  current code/tests do not explain a protected decision.

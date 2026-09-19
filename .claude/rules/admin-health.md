---
paths:
  - "R/helpers_admin*.R"
  - "R/helpers_health*.R"
  - "R/module_admin*.R"
  - "R/module_health*.R"
  - "R/config_logging*.R"
  - "tests/**/*admin*.R"
  - "tests/**/*health*.R"
  - "tests/**/*log*.R"
  - "tests/scripts/*health*.R"
  - "tests/scripts/*smoke*.R"
---

# Admin, health, telemetry and logging

- Health/admin status must report what was actually measured; missing evidence
  is not success and degraded/unknown states must remain distinguishable.
- Never expose raw secrets, env values, auth headers, user-controlled HTML, or
  sensitive endpoints in diagnostics, admin tables, logs, or evidence artifacts.
- Structured error logging must preserve caller context and canonical redaction.
  Do not replace logging wrappers with raw console output.
- Async worker metrics reflect tracked jobs; preserve registration/cleanup and
  success/failure aggregation.
- Post-deploy/VM/soak artifacts have explicit `does_prove` /
  `does_not_prove` semantics. Do not overstate them.
- Admin renderers that intentionally use unescaped HTML must pre-escape
  user/LLM-controlled fields at the owning boundary.
- Current metric/check inventories are derived from health/instrumentation code,
  not duplicated in Claude memory.
- Production connectivity checks may differ from cloud/offline tests; report
  unverified live services honestly.
- For detailed history, consult archive health-dashboard, worker-monitoring,
  feedback-analysis and structured-logging sections.

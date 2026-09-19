---
paths:
  - "tests/**"
  - "tools/ai_validate.sh"
  - "tools/seam_doctor.sh"
  - "tools/setup_ai_r_environment.sh"
  - ".claude/hooks/**"
---

# Testing and validation

- Do not weaken assertions, scans, ratchets, skips or validation semantics merely
  to make an unrelated change green.
- Prefer focused behavior tests for the changed boundary, then the appropriate
  validation profile from root `CLAUDE.md`.
- Strict suite behavior matters: warnings can be failures. Isolate env/config
  dependencies explicitly instead of relying on a developer machine.
- Test bootstrap/source order should mirror runtime where the subsystem requires
  it, especially encoding/DB helpers.
- PK source scans must use `tests/testthat/helper_pk_source_scan.R` to strip
  inline comments while preserving string literals and Turkish source text;
  do not reintroduce separate full-line-only readers.
- Windows-sensitive fixtures must avoid locale/console-dependent assumptions;
  use deterministic byte/Unicode construction where needed.
- Tests must stay offline/deterministic unless explicitly designated as
  service/VM/operator validation.
- VM evidence, browser smoke, live SQL Server/SSO/service checks and soak/load
  tests prove different things. Never substitute one for another.
- A passing historical artifact is not proof that current code still passes;
  only claim results from the exact run performed.
- The current coverage inventory is `tests/`; do not maintain a giant
  "Current baseline coverage" list in Claude instructions.
- Maintainability thresholds are guardrails. Split code when a budget is reached
  rather than increasing global limits without an explicit architectural reason.
- The Stop hook may block a final response after quick validation failure; use
  its artifact/log rather than hiding the failure.
- Historical test inventories and maintenance lessons remain in the archive for
  archaeology, not as always-loaded memory.

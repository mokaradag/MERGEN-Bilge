---
paths:
  - "README.md"
  - "RUNBOOK.md"
  - "RENV_LOCK_STATUS.md"
  - "version_history.md"
  - "ai_rehber.md"
  - ".Renviron.example"
  - "docs/**"
  - ".claude/**"
  - "tools/*renv*.R"
---

# Documentation, versions and operations

- Documentation-only work stays documentation-only unless runtime changes are
  explicitly requested.
- `version_history.md` is the canonical current product-version source. Do not
  hardcode a "Current Product Version Reference" in Claude memory.
- `.Renviron.example` plus owning config code are the current configuration
  surface. Never paste real secrets/internal endpoints into documentation.
- `R/config_source_manifest.R`, UI asset manifests, plugin directories, tests
  and code are better current-state sources than copied inventories.
- `RUNBOOK.md` owns production operations; dependency locking belongs in
  `docs/dependency-locking.md` / `RENV_LOCK_STATUS.md`.
- Do not generate/update `renv.lock` from Linux/cloud Claude sessions.
- `ai_rehber.md` is user-facing assistant behavior input, not passive prose;
  edit it deliberately and preserve Turkish meaning.
- `version_history.md` is runtime-parsed product input. Preserve its expected
  structure and update tests if its parser contract changes.
- Release/evidence notes must distinguish dated historical proof from current
  validation. Never turn a past VM run into a present-tense claim.
- Avoid duplicating dynamic counts, rosters, page lists, source lists, model
  inventories or coverage inventories in maintainer instructions.
- The full former CLAUDE contract is intentionally archived under
  `docs/maintainers/`; never import it into live memory.

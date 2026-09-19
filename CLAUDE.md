# CLAUDE.md — MERGEN Bilge

## Purpose

This is the always-loaded coding-agent contract for MERGEN Bilge. Keep it concise.
Subsystem detail belongs in path-scoped `.claude/rules/*.md` files and loads
only when Claude works with matching files.

The former full contract is preserved at
`docs/maintainers/claude-code-full-contract-reference.md`. It is an audit and
edge-case reference, not startup memory. Never `@`-import that archive from a
live Claude instruction file.

## Non-negotiable rules

1. Preserve Turkish text integrity. Repository text stays UTF-8; never Latinize
   Turkish characters or introduce mojibake.
2. Treat Windows VM/on-prem behavior as production-relevant. UNC paths, Windows
   code pages, SSO, SQL Server/ODBC, and enterprise launch constraints are not
   optional edge cases.
3. Never add secrets, API keys, passwords, tokens, private DSNs, auth headers,
   or sensitive internal endpoints to code, docs, tests, logs, PR text, or
   validation artifacts.
4. Prefer surgical changes. Preserve existing UX and behavior unless the task
   explicitly requires a behavior change.
5. Keep documentation-only tasks documentation-only. Do not change runtime,
   tests, deployment, DB, UI, or validation behavior merely to support docs.
6. Respect canonical source/load order. Do not casually reorder
   `R/config_source_manifest.R`, DB helpers, server bootstrap files, or
   `R/config_ui_assets.R`.
7. Do not bypass centralized encoding, identity, path-safety, secret-redaction,
   transaction, concurrency, async, or browser-safety helpers with local fixes.
8. Do not weaken maintainability ratchets, security scans, behavioral tests, or
   validation gates just to make a patch pass. Split/refactor instead.
9. New code comments should be brief and in Turkish, consistent with the repo.
10. Do not generate or update `renv.lock` from Linux/cloud/Claude Code
    sessions. Dependency locking is governed by the Windows VM/on-prem workflow.
11. For bug fixes, add or update focused regression coverage when practical.
12. Never claim a test, app boot, browser smoke, VM check, production check, or
    evidence gate passed unless that exact check ran successfully.

## Ground truth, not snapshots

Do not copy volatile "current state" inventories into this file. Derive them
from their canonical sources when needed:

- Current product version: `version_history.md`.
- Runtime source/load order: `R/config_source_manifest.R` and bootstrap code.
- Frontend asset order/ownership: `R/config_ui_assets.R` and asset-zone config.
- Environment/config surface: `.Renviron.example` plus the owning config code.
- Bilge Yolaç plugin roster: `bilge_yolac_plugins/`.
- Test/coverage inventory: `tests/` and validation scripts.
- Current user-facing pages/modules: `ui.R`, server/module wiring, and manifests.
- Current async task families/health metrics: instrumentation and health code.

If a sentence contains "current", "latest", "recent", a version number, count,
roster, file inventory, or rollout status, verify it from the repository before
using it as fact. Prefer pointing to the source of truth over duplicating it.

## Working method

- Inspect the current implementation and nearby tests before editing.
- Reuse canonical helpers and ownership seams instead of duplicating logic.
- Keep runtime files modular and within existing line/function budgets.
- Preserve existing Turkish UI wording unless the task requires copy changes.
- Treat automated review findings as hypotheses: verify each against current
  code before changing behavior.
- When a scoped rule applies, read the relevant implementation and tests before
  changing the protected boundary.
- Use the archived full contract deliberately for historical rationale or a
  rare edge case; do not restore it to always-loaded context.

## Validation

Normal code-change validation:

`bash tools/ai_validate.sh quick`

Claude/cloud fallback when the normal environment cannot be prepared:

`bash tools/ai_validate.sh cloud-quick`

For risky changes affecting runtime startup, SSO, DB encoding, source order,
file lifecycle, streaming, frontend asset order, Bilge Yolaç/Claude Code,
security/path/download boundaries, or production VM behavior:

`bash tools/ai_validate.sh full --boot-smoke`

Rules:

- Run focused tests for the changed behavior before/with the normal profile.
- The Stop hook also runs quick validation when the working tree changed.
- Cloud validation does not prove Windows VM, browser, live SSO, SQL Server,
  real external services, or production deployment behavior.
- VM-only evidence remains VM-only; report it as unverified when it did not run.
- If validation fails, report the failed step and artifact/log path honestly.

## Scoped rule map

Claude Code loads these when matching files are read:

- `.claude/rules/encoding-database.md`
- `.claude/rules/security-identity.md`
- `.claude/rules/runtime-architecture.md`
- `.claude/rules/frontend-ui.md`
- `.claude/rules/files-storage.md`
- `.claude/rules/bilge-yolac.md`
- `.claude/rules/project-resource-analysis.md`
- `.claude/rules/llm-chat-streaming.md`
- `.claude/rules/speech-media.md`
- `.claude/rules/admin-health.md`
- `.claude/rules/testing-validation.md`
- `.claude/rules/docs-operations.md`
- `.claude/rules/special-features.md`

Do not remove `paths:` frontmatter from these files unless the rule truly must
be loaded in every session; an unscoped rule defeats this refactor.

## Canonical references

- Product overview: `README.md`
- Documentation hub: `docs/README.md`
- Architecture: `docs/architecture-map.md`
- Database schema: `docs/database-schema.md`
- Operations: `RUNBOOK.md`
- Dependency locking: `docs/dependency-locking.md`
- User-facing assistant behavior: `ai_rehber.md`
- Migration map: `docs/maintainers/claude-code-instruction-refactor-map.md`
- Staleness audit: `docs/maintainers/claude-code-staleness-audit.md`
- Former full contract: `docs/maintainers/claude-code-full-contract-reference.md`

## High-level architecture

MERGEN Bilge is an R/Shiny application with a Turkish-first UI, conversational
AI, file analysis, MCP workflows, SSO-ready enterprise deployment, multimedia,
AI Expert, and Bilge Yolaç.

Entrypoints are `app.R`, `global.R`, `ui.R`, and `server.R`. Runtime source
ownership is declared through `R/config_source_manifest.R`; frontend assets are
owned through `R/config_ui_assets.R` and the asset/zone registries. Prefer
those manifests over ad-hoc sourcing or asset injection.

When in doubt: preserve Turkish, preserve security boundaries, preserve load
order, patch surgically, test the changed behavior, and state evidence precisely.

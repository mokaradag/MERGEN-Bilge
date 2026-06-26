# PROMPT — Meaningful and Safe Strengthening for MERGEN Bilge

## Current next-session handoff

### Recently completed — do not redo unless fresh evidence shows regression
- Deep Space frontend lifecycle boundary split:
  - `www/js/deep_space_intro_lifecycle.js` now owns timeout/rAF tracking, skip-intro auto-init, and DOMContentLoaded binding.
  - `www/js/deep_space_intro.js` remains the scene/Three.js orchestration module and delegates stale-callback cleanup to the lifecycle helper.
  - Manifest order is `deep_space_intro_earth_shader.js` → `deep_space_intro_solar.js` → `deep_space_intro_lifecycle.js` → `deep_space_intro.js`.
  - Guard: `tests/testthat/test-deep-space-frontend-lifecycle-contract.R`.
- Do not redo File Manager delete/state/upload runtime splits, AI Expert manager/handler split, config UI asset DATA/VALIDATORS/RENDER split, server runtime auth-ready split, post-deploy smoke artifact flow, Claude document-summary split, true-SSE worker-globals split, DB chat-read query split, startup screen UI/server split, image generation UI split, support/admin renderer splits, or the Deep Space lifecycle split unless fresh evidence shows regression.

### Current best meaningful targets
- Frontend handler-density package: `www/js/shiny_message_handlers.js` still has the highest Shiny handler concentration; prefer a coherent handler cluster with manifest/zone/contract coverage.
- Claude Code frontend handler-density package: inspect `www/js/claude_code.js` for Shiny handler grouping or lifecycle cleanup boundaries; preserve streaming/asset order.
- Frontend function-density package: `www/js/tool_backgrounds.js` remains high by function count; choose only if inspection finds a real coherent boundary, not a tiny split.
- Validation blocker package: if `full --boot-smoke` still fails on reproducible Shiny destroyed-reactive isolation, reproduce and fix root cause without weakening tests.

### Current gotchas
- Keep `.ai/next-session-eliminate-weaknesses-prompt.md` compact; historical detail belongs in `docs/refactor-log.md`.
- Preserve Turkish UTF-8, frontend asset order, local/offline asset assumptions, SSO fail-closed behavior, source manifest protections, and DB/encoding boundaries.
- Do not claim VM/browser/DB/SSO/SQL Server/full-suite proof unless the exact command ran and passed.

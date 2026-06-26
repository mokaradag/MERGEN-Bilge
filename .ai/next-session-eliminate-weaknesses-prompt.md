# PROMPT — Meaningful and Safe Strengthening for MERGEN Bilge

## Current next-session handoff

### Recently completed — do not redo unless fresh evidence shows regression
- Modern welcome ownership contract alignment:
  - `CLAUDE.md` now explicitly says `www/js/modern_welcome_handler.js` owns `initModernWelcome` and visible modern-welcome startup lifecycle.
  - `www/js/shiny_message_handlers.js` remains the generic Shiny message bridge; do not move `initModernWelcome` back there without redesigning manifest order, zone ownership, and split-contract tests together.
  - `tests/testthat/test-modern-welcome-handler-split-contract.R` now guards this authoritative maintainer-contract alignment.
- Do not redo File Manager delete/state/upload runtime splits, AI Expert manager/handler split, config UI asset DATA/VALIDATORS/RENDER split, server runtime auth-ready split, post-deploy smoke artifact flow, Claude document-summary split, true-SSE worker-globals split, DB chat-read query split, startup screen UI/server split, image generation UI split, support/admin renderer splits, Deep Space lifecycle split, or the modern welcome handler/ownership split unless fresh evidence shows regression.

### Current best meaningful targets
- Claude Code frontend handler-density package: inspect `www/js/claude_code.js` for a coherent Shiny handler grouping or lifecycle cleanup boundary; preserve streaming/asset order.
- Frontend function-density package: `www/js/tool_backgrounds.js` remains high by function count; choose only if inspection finds a real coherent boundary, not a tiny split.
- Frontend event-density package: `www/js/file_handlers.js` has the highest event-handler concentration; only target it with deterministic lifecycle/handler tests.
- Validation blocker package: if `full --boot-smoke` still fails on reproducible Shiny destroyed-reactive isolation, reproduce and fix root cause without weakening tests.

### Current gotchas
- Keep `.ai/next-session-eliminate-weaknesses-prompt.md` compact; historical detail belongs in `docs/refactor-log.md`.
- Preserve Turkish UTF-8, frontend asset order, local/offline asset assumptions, SSO fail-closed behavior, source manifest protections, and DB/encoding boundaries.
- Do not claim VM/browser/DB/SSO/SQL Server/full-suite proof unless the exact command ran and passed.

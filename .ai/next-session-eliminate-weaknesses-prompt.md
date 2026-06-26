# PROMPT — Meaningful and Safe Strengthening for MERGEN Bilge

## Current next-session handoff

### Recently completed — do not redo unless fresh evidence shows regression
- Modern welcome frontend handler/lifecycle split:
  - `www/js/modern_welcome_handler.js` now owns `initModernWelcome`, retry timer cleanup, DOM/dependency readiness, welcome video resume, neural init, greeting init, and saved-character accent fallback.
  - `www/js/shiny_message_handlers.js` remains the generic Shiny message bridge for toast/scroll/CodeMirror/font/follow-up/neural animation/search/storage/removeExcel/quick-action handlers.
  - Manifest order keeps `modern_welcome_handler.js` after `shiny_message_handlers.js` and before `ui_init.js`, `neural_welcome.js`, and `welcome_video_player.js`.
  - Guard: `tests/testthat/test-modern-welcome-handler-split-contract.R` plus updated selector/boot welcome contracts.
- Do not redo File Manager delete/state/upload runtime splits, AI Expert manager/handler split, config UI asset DATA/VALIDATORS/RENDER split, server runtime auth-ready split, post-deploy smoke artifact flow, Claude document-summary split, true-SSE worker-globals split, DB chat-read query split, startup screen UI/server split, image generation UI split, support/admin renderer splits, Deep Space lifecycle split, or the modern welcome handler split unless fresh evidence shows regression.

### Current best meaningful targets
- Claude Code frontend handler-density package: inspect `www/js/claude_code.js` for a coherent Shiny handler grouping or lifecycle cleanup boundary; preserve streaming/asset order.
- Frontend function-density package: `www/js/tool_backgrounds.js` remains high by function count; choose only if inspection finds a real coherent boundary, not a tiny split.
- Frontend event-density package: `www/js/file_handlers.js` has the highest event-handler concentration; only target it with deterministic lifecycle/handler tests.
- Validation blocker package: if `full --boot-smoke` still fails on reproducible Shiny destroyed-reactive isolation, reproduce and fix root cause without weakening tests.

### Current gotchas
- Keep `.ai/next-session-eliminate-weaknesses-prompt.md` compact; historical detail belongs in `docs/refactor-log.md`.
- Preserve Turkish UTF-8, frontend asset order, local/offline asset assumptions, SSO fail-closed behavior, source manifest protections, and DB/encoding boundaries.
- Do not claim VM/browser/DB/SSO/SQL Server/full-suite proof unless the exact command ran and passed.

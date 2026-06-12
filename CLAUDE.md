# CLAUDE.md - MERGEN Bilge Codebase Guide


## Read this first

This file is the authoritative coding-agent and maintainer contract for the MERGEN Bilge repository. Read it before changing code, validation behavior, deployment behavior, or safety-critical documentation. The detailed rules below remain authoritative; this section is only a short entry point.

Non-negotiable rules:

1. Preserve Turkish text integrity everywhere; files must stay UTF-8 and Turkish characters must not be Latinized.
2. Do not introduce mojibake, and do not weaken the centralized encoding, DB normalization, mailto, JSON, log, or browser text boundaries.
3. Keep documentation-only tasks documentation-only; do not change runtime behavior, tests, deployment scripts, DB logic, UI behavior, or validation logic unless the task explicitly requires it.
4. Never add secrets, API keys, passwords, tokens, private DSNs, auth headers, or sensitive internal endpoints to code, docs, logs, PR text, or validation artifacts.
5. Respect source/load order, especially `R/config_source_manifest.R`, helper bootstrap order, DB helper order, and frontend asset order in `R/config_ui_assets.R`.
6. Respect DB encoding boundaries: do not bypass DB-safe Unicode escape/restore, DB read/write normalization, or mojibake guards because legacy data is dirty.
7. Respect Windows VM/on-prem assumptions, including UNC paths, Turkish path behavior, SSO profile behavior, and production launcher constraints.
8. Do not generate `renv.lock` from Linux/cloud/Codex sessions; dependency locking is governed by the Windows VM/on-prem workflow.
9. Run only validation appropriate to the change, and be explicit about what the command proves and does not prove.
10. Do not claim full validation, VM validation, browser smoke, app boot, or test success unless the relevant command actually ran and passed with zero failed steps.
11. Preserve maintainability ratchets, browser/UX smoke seams, security-path-download protections, and Bilge Yolaç/Claude Code execution boundaries.

Where to go next:

- Product overview and first run: [`README.md`](README.md)
- Documentation hub: [`docs/README.md`](docs/README.md)
- User-facing assistant behavior: [`ai_rehber.md`](ai_rehber.md)
- Architecture map: [`docs/architecture-map.md`](docs/architecture-map.md)
- Seam/zone ownership map: `R/config_seam_registry.R`, `R/config_ui_asset_zones.R` (validate with `bash tools/seam_doctor.sh`)
- Database schema: [`docs/database-schema.md`](docs/database-schema.md)
- Operations/runbook: [`RUNBOOK.md`](RUNBOOK.md)
- Dependency locking: [`docs/dependency-locking.md`](docs/dependency-locking.md)
- Release notes: [`docs/release-notes.md`](docs/release-notes.md)
- Agent summary: [`AGENTS.md`](AGENTS.md)

---
## Purpose of This File

This document is the operational guide for coding agents working inside the **MERGEN Bilge** repository. It explains how the application is structured, how it boots, which files are critical, which areas are fragile, and what repo-specific working style must be followed.

The repository is an R/Shiny application with a dark-theme, multimedia-heavy, Turkish-first user experience. It includes:

- conversational AI,
- file upload and analysis,
- MCP-enabled workflows,
- TTS and STT,
- AI Expert proactive guidance,
- support and version history pages,
- a web-wrapped Claude Code experience named **Bilge Yolaç**,
- SSO-ready deployment for VM/enterprise environments.

This file should be read before touching the code.

Documentation note: `README.md` gives the product-level feature overview, while `ai_rehber.md` defines user-facing assistant behavior; this guide remains the primary reference for repository-safe implementation practices.

---

## Non-Negotiable Repo Rules

### 1) Preserve Turkish text integrity
This project is extremely sensitive to encoding regressions.

Always assume:

- files must remain UTF-8,
- Turkish characters must not be Latinized,
- any “simple cleanup” can accidentally introduce mojibake on VM/SSO flows.

If you touch file reading, file writing, `.Renviron`, DB writes, JSON writes, or browser-rendered text, be extra careful.

### 1B) Text encoding and mojibake boundary contract
Turkish text, emoji, and mojibake repair are centralized. Do not reintroduce scattered ad hoc replacement maps.

Current contract:

- Server-side text normalization belongs in `R/utils_text_encoding.R`.
- DB-safe unsupported Unicode escape/restore belongs in `R/helpers_db_unicode_escape.R`. It converts characters that the resolved DB client encoding cannot represent into ASCII tokens such as `[[MERGEN-U+1F680]]`, and restores those tokens on read/UI boundaries.
- DB parameter encoding, visible/technical DB normalization, mojibake detection, and the `MB_Messages` post-insert guard belong in `R/helpers_db_encoding.R`.
- `R/helpers_db_connection.R` must stay focused on connection, pool, and worker connection helpers. Do not move Unicode escape, DB normalization, or mojibake guard helpers back into it.
- Client-side defensive mojibake fallback belongs in `www/js/encoding_utils.js`.
- Mailto subject/body encoding for user-visible Turkish text belongs in `R/helpers_mailto_encoding.R`. Do not use raw `utils::URLencode()` directly for `mailto:` subject or body values, because Windows/VM native-byte encoding can corrupt Turkish characters in Outlook. Use `mergen_mailto_href()` / `mergen_mailto_percent_encode()` so the mailto boundary is encoded from UTF-8 bytes. Keep this helper loaded immediately after `R/utils_text_encoding.R` in `R/config_source_manifest.R`, and keep `tests/testthat/helper_bootstrap.R` aligned with that order. The focused regression coverage belongs in `tests/testthat/test-mailto-encoding.R`.
- `R/utils_text_encoding.R` must be loaded early through `R/config_source_manifest.R`, before logging, DB helpers, and downstream text consumers. The DB helper order must remain explicit: `R/helpers_db_unicode_escape.R`, then `R/helpers_db_encoding.R`, then `R/helpers_db_connection.R`, followed by DB user encoding, validation, chat formatting, chat readers, chat mutations, `R/helpers_db_feedback.R`, and `R/helpers_database.R`.
- `www/js/encoding_utils.js` must be loaded through `R/config_ui_assets.R` before `www/js/shiny_message_handlers.js` and before `www/js/claude_code_streaming.js`.
- DB write parameters, DB read/hydration paths, saved chat reloads, version-history/Yenilikler reads, uploaded-file display names, Bilge Yolaç process/stream output, JSON/text boundaries, and logs should use the shared helper path instead of local encoding fixes.
- `dataframeToMarkdown()` in `R/helpers_files.R` must keep producing simple CSV text for data.frame previews without reintroducing UTF-8 BOM/readLines regressions on Windows. It writes preview CSV without BOM and reads through an explicit UTF-8 connection; protect this with `tests/testthat/test-files-dataframe-markdown-behavior.R`.
- MCP/LLM worker tool-result dataframe preview extraction belongs in `R/helpers_llm_worker_tool_results_preview.R`. Do not move `llm_worker_extract_preview_df()` back into `R/helpers_llm_worker_tool_results.R`, and do not rely only on direct `$` access to Turkish list names such as `raw$sonuç_önizleme`; keep support for `sonuç_önizleme`, `sonuc_onizleme`, and `preview` through the shared preview extraction boundary across Windows/RStudio/VM encoding differences.
- `R/helpers_llm_worker_tool_results.R` must remain focused on formatting tool results for the second-pass LLM prompt and stay within the maintainability ratchet function budget. The runtime manifest must load `R/helpers_llm_worker_tool_results_preview.R` before `R/helpers_llm_worker_tool_results.R`; isolated tests that source the formatting helper directly must source the preview helper first.
- The formatted real-data output contract is protected: keep the `VERİTABANINDAN GELEN GERÇEK VERİ` heading, markdown table, returned row/column counts, missing-`source_table` warning, `source_table değerleri:` listing, and empty-dataframe warning behavior intact. This boundary feeds the second-pass LLM synthesis prompt and must not silently fall back to JSON when a valid dataframe preview is present.
- Focused regression coverage belongs in `tests/testthat/test-llm-worker-format-tool-result-behavior.R`. For documentation-only updates to this note, do not run R/testthat validation unless code files are changed in a separate task.
- DB normalization is intentionally opt-in for mojibake repair. User-visible DB text must be prepared explicitly with `normalize_db_visible_value()` before parameter binding. Technical string values must use `normalize_db_technical_value()` or remain on the default no-repair path. Do not apply `repair_mojibake = TRUE` to an entire mixed parameter list that also contains IDs, enums, flags, model names, usernames, emails, sicil values, Keycloak IDs, file paths, or other non-user-visible values.
- The SQL Server DB write boundary is production-sensitive on the Windows VM / SSO deployment. Do not force raw UTF-8 into DBI/ODBC parameter writes merely because the configured client encoding says UTF-8. That behavior can store Turkish text as mojibake across MB tables.
- For the production VM, Turkish DB writes must preserve the stable Windows-native / `WINDOWS-1254` behavior. `DB_CLIENT_ENCODING=WINDOWS-1254` is the safe operational setting unless a live VM + SSMS validation proves otherwise.
- `R/helpers_db_connection.R` must honor `DB_CLIENT_ENCODING` and `DB_NAME_ENCODING` from `.Renviron` before falling back to R options/defaults. Do not hard-code the production DB client encoding back to `UTF-8`; doing so can store Turkish message content in `MB_Messages.MessageContent` as mojibake.
- SSO / `MB_Users` visible-versus-technical normalization belongs in `R/helpers_db_user_encoding.R`. Keep `normalize_sso_claims_for_db()` and `update_sso_fields()` there, loaded immediately after `R/helpers_db_connection.R`. Do not move those helpers back into `R/helpers_database.R`; that file is protected by the maintainability ratchet and should stay focused on high-level DB operations.
- `MB_Feedback` and `MB_Usage_Log` write helpers belong in `R/helpers_db_feedback.R`, loaded after chat mutations and before `R/helpers_database.R`. Do not move feedback helpers back into `R/helpers_database.R`. Extended feedback tags/comments are user-visible values and must use `normalize_db_visible_value()`, while `FeedbackType` is a technical enum and must use `normalize_db_technical_value()`. Do not apply whole-list `repair_mojibake = TRUE` to the mixed extended feedback parameter list.
- `normalize_db_value()` must respect the resolved DB client encoding. When the DB client encoding is not UTF-8, user-visible Turkish text must be prepared for that DBI/ODBC parameter boundary instead of blindly returning UTF-8.
- When the DB client encoding is not UTF-8, `normalize_db_value()` must never fall back to raw UTF-8 for strings containing unsupported Unicode. It must use the DB Unicode escape helper so the stored value remains ASCII/DB-client-safe while read paths can restore the original user-visible character.
- Keep the UTF-8 and non-UTF-8 DB parameter paths explicitly separated. The helper that detects UTF-8 DB client encoding, such as `db_client_encoding_is_utf8()`, is part of the encoding safety boundary.
- This change protects future writes; it is not an automatic data migration. Existing mojibake rows must only be repaired after a DB backup, after the write path is confirmed fixed in SSMS, and through a separate one-time repair plan.
- New `MB_Messages` writes must be verified after insert and before commit. `save_message_to_db()` and `worker_save_assistant_response()` must call `assert_mb_message_visible_encoding_clean()` for the inserted message ID before committing. If the guard detects mojibake in `MessageContent` or `ReasoningContent`, the transaction must roll back.
- Historical mojibake data and future write regressions are separate concerns. Do not weaken the post-insert guard because old rows are dirty. Old rows may remain as legacy data unless a backup-approved, one-time repair run is explicitly requested.
- `tests/scripts/run_vm_encoding_preflight_real.R` must keep transactional new-write validation strict when `MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST=TRUE`. Recent/historical `MB_Messages` mojibake scan results are warning-only by default and become blocking only when `MERGEN_PREFLIGHT_FAIL_ON_LEGACY_MOJIBAKE=TRUE`.
- `tests/scripts/repair_mb_messages_mojibake.R` is a maintenance-only, best-effort helper. It must be safe to run with `source(...)`, must not call `quit()`, and must not be treated as a guaranteed migration for every old corrupted fragment.
- Do not add literal emoji to R test sources, maintenance scripts, or parser-sensitive comments. Use parser-safe construction such as `intToUtf8(...)` in tests when emoji fixtures are unavoidable.
- Emoji and other unsupported Unicode persistence is handled through DB-safe ASCII escape tokens such as `[[MERGEN-U+1F680]]`, not by forcing raw emoji or raw UTF-8 into SQL Server/ODBC. Saved/reloaded chat display must restore those tokens through `normalize_db_read_visible_value()` or `normalize_db_read_visible_frame()`. Do not trade Turkish text integrity for emoji display.
- Read-side normalization may defensively repair display of older mojibake values, but it must not be used as an excuse to allow new mojibake writes. New records in `MB_Users`, `MB_Chats`, `MB_Messages`, `MB_Feedback`, and other MB tables must be validated at rest in SQL Server.
- Saved chat reloads, chat history previews, message formatting, and reasoning-content display should decode DB Unicode escape tokens at the read/UI boundary before rendering. The canonical storage form may contain `[[MERGEN-U+...]]` tokens; the user-facing UI should show the restored character.
- Image gallery message updates must repair only the user-visible replacement `MB_Messages.MessageContent` text. Technical values such as `MessageID` must not be included in a whole-list mojibake repair call.
- Test bootstrap must mirror runtime encoding order. `tests/testthat/helper_bootstrap.R` should source `R/utils_text_encoding.R` before DB helpers so isolated `testthat::test_file(...)` runs exercise the same mojibake repair path as the application.
- Test bootstrap must also mirror the DB helper split: source `R/helpers_db_unicode_escape.R` before `R/helpers_db_encoding.R`, and source `R/helpers_db_encoding.R` before `R/helpers_db_connection.R`.
- File Manager display-name repair depends on the shared text helper. Tests that source `R/config_file_store_index_mutation.R` in isolation must also load `R/utils_text_encoding.R`, otherwise mojibake filename fixtures can appear unchanged even though runtime behavior is correct.
- Do not replace deterministic byte-built mojibake fixtures in tests with fragile console-dependent mojibake or emoji literals when the test must pass on Windows VM sessions.
- Encoding regression tests must use deterministic Unicode construction for parser-sensitive or console-sensitive fixtures. Prefer `intToUtf8(as.integer(codepoint))` for emoji and non-ASCII fixture characters instead of literal emoji, literal mojibake, or source strings that can be reinterpreted by a Windows console/code page. This applies especially to DB Unicode escape round-trip tests and ANSI/OSC stripping tests; the production escape/read behavior must remain unchanged.
- R test files that must pass Windows VM parse sanity should avoid literal emoji in source strings; use `intToUtf8(...)` in tests instead. This is a parser-stability rule, not a product decision to remove emoji support.
- Logging should pass user-visible text through the shared log normalization path so Turkish text stays readable and ANSI escape sequences are not made worse.
- Bilge Yolaç streaming must keep the browser-side fallback, but `www/js/claude_code_streaming.js` must not grow another large local mojibake map. Use `window.MergenEncoding` from `www/js/encoding_utils.js`.
- Bilge Yolaç document-summary downloads are a protected encoding boundary. The generated `dosya_aciklamalari.txt` file must be written with `write_claude_code_utf8_bom_text_file()` so Windows Explorer, Notepad, and enterprise VM clients reliably detect Turkish text as UTF-8.
- Do not replace the UTF-8 BOM writer for downloadable `.txt` summaries with plain `writeLines(..., useBytes = TRUE)` or any locale-dependent text writer unless `tests/testthat/test-claude-code-document-download-link-encoding.R` is updated and still proves Turkish characters survive the download/open path.
- The UTF-8 BOM rule applies to downloadable Bilge Yolaç text artifacts. It does not change the SQL Server/ODBC DB write encoding contract, and it must not be used as justification to change `DB_CLIENT_ENCODING` behavior.
- Do not replace UTF-8-safe byte reading helpers with plain `readLines(..., encoding = "UTF-8")` in Windows/VM-sensitive paths unless the regression tests prove it is safe.
- Be careful with R constants: use exactly `NA_character_`. A typo such as `NA_character__` can break app startup through DB parameter normalization.
- Do not add CDN or external dependencies for encoding repair.

### File Reading, Encoding, and Ratchet Notes
- File text extraction should use the shared `read_text_lines_utf8()` helper from `R/utils_text_encoding.R`; avoid adding new local text-decoding helpers inside `R/helpers_files.R`.
- `R/helpers_files.R` is protected by the maintainability ratchet and must stay within its line/function budget.
- For text file content extraction in `readFileContentToString()`, use the shared UTF-8-safe helper and preserve large-file truncation behavior.
- Tests that depend on environment-driven configuration, such as image generation endpoint settings, should explicitly isolate or override those values instead of relying on the developer machine’s `.Renviron`.
- Startup-screen tests should avoid passing optional runtime-only arguments unless the test explicitly validates that contract.
- For docs-only changes, do not run R/testthat validation unless the user explicitly asks.

### Windows VM focused test coverage and path/API-key encoding contract

Recent VM-focused coverage converted several previously skipped tests into runnable local/Windows assertions. Keep these boundaries intact:
- `tests/testthat/test-config-sql-loader-helpers-behavior.R` intentionally isolates `query_library` while sourcing `R/config_sql_loader.R` so the pure helper functions remain available before the loader’s production cleanup boundary.
- `tests/testthat/test-downloads-outputs-behavior.R` must test that `widgetDependencyOutputsInit()` degrades gracefully when highcharter is missing (lexical `requireNamespace()` mock in the sourced environment) and that it defines no plotly output. Plotly has been fully removed; do not reintroduce a `plotly`/`deps_pl`/`plotly_html` output here.
- `tests/testthat/test-path-helpers-mojibake-behavior.R` must exercise real Windows behavior for `safe_windows_short_path()` instead of skipping on Windows.
- Strict offline runtime scanning is opt-in and should be enabled in VM/local validation with `MERGEN_STRICT_OFFLINE_TESTS=true`.

Encoding/path contracts protected by those tests:
- API-key crypto helpers must encrypt `enc2utf8()` text bytes and decode decrypted raw bytes back as UTF-8 so Turkish API key values round-trip on Windows.
- `safe_windows_short_path()` must normalize single Windows backslash separators to `/`; do not revert to a two-backslash-only replacement that leaves ordinary `C:\...` paths unnormalized.
- Returned app-facing paths should preserve the repository’s forward-slash convention unless a function explicitly documents otherwise.
- These tests are deterministic and do not require DB, LLM, browser, or network access.

### Service-dependent behavioral tests and API-key salt guard

The service-dependent runtime tests added in this area are behavioral contract tests, not broad integration proof. They should remain offline and deterministic: use stubs, temporary directories, and mocked DBI/HTTP dependencies rather than real SQL Server, browser sessions, LLM endpoints, network calls, production services, or secrets.

Future changes should preserve the intent of these tests:
- Admin analytics/output tests should verify stable chart/table contracts such as series names, colors, categories, ordering, empty-data guards, and Turkish labels. Do not turn them into pixel-perfect rendering tests.
- Health-check tests should keep public internet endpoints on the skipped/warning path and mock local endpoint responses when checking success behavior.
- DB helper tests should keep DBI calls mocked and must not require SQL Server, live credentials, or a production schema.
- API-key crypto tests must use fake keys and isolated temporary directories only. Never introduce real API keys, tokens, passwords, DSNs, cookies, or endpoint secrets into fixtures, logs, docs, or artifacts.
- The `save_user_api_key()` NUL-salt mapping is a protected regression guard. `openssl::rand_bytes()` can produce `0x00`; the hash path converts salt through `rawToChar()`, so embedded NUL bytes can fail with `embedded nul in string`. Do not remove `salt[salt == as.raw(0L)] <- as.raw(1L)` unless the hash path is redesigned and the corresponding regression test is updated.
- File-store, SQL-loader, UI asset, image-gallery, MCP/Excel formatter, PK/RLS, welcome-action, plugin UI, and worker-monitor tests should remain small input-output checks with no runtime boot requirement.

For documentation-only edits to `README.md` and `CLAUDE.md`, do not run R/testthat validation. Manual Markdown diff review is sufficient unless code files are changed in a separate task.

### Async stale-request guards, startup parity, and File Manager refresh boundary

Long-running non-streaming handlers must not let stale async callbacks mutate the state of a newer request. Image generation and summarization callbacks now carry the active request id and stop-generation check from the send-message context and must use the existing `mergen_is_current_request` pattern before touching UI, chat state, typing state, or reset callbacks. Do not replace this with a parallel abstraction. Future async handlers should follow the same small request-id snapshot plus callback-entry guard pattern and should be covered with deterministic promise/later tests.

The startup skip-intro path must remain behaviorally aligned with the experience-mode path for persona-driven UI state. In particular, skip-intro must continue sending the selected/default persona neural color update so the neural animation tint matches the persona even when the intro is skipped.

The File Manager header now includes a refresh action next to the clear action. Keep the refresh action scoped to reloading the file table from the persistent user folder through the existing refresh mechanism. Do not merge it with the destructive clear flow, and keep the refresh button visually distinct from the danger/clear button in both dark and light themes.

Fallback source guards for isolated test/debug loading must be working-directory independent. When a helper needs to source a sibling file only because the normal manifest/global load order is absent, candidate paths should cover the repository root, `tests/testthat`, and `MERGEN_REPO_ROOT` where applicable. Avoid `getwd()`-only assumptions.

Behavior tests affected by helper-file refactors must source the real owning helper file, not an older file that happens to work only in the full suite. For API model/tool runtime helpers, source the runtime helper file when the function lives there so individual `testthat::test_file(...)` runs remain standalone.

Docs-only validation note:
Keep the existing rule that README.md / CLAUDE.md-only edits do not require R or testthat validation. For this specific change, do not run R validation; review only the Markdown diff.

### Version history path resolution contract

- `version_history.md` remains at the repository root for real application version data.
- `get_version_history()` must call `resolve_version_history_md_path()`; do not revert it to `file.path(getwd(), "version_history.md")`.
- The resolver must first honor a local `version_history.md` in the current working directory, then walk upward through parent directories.
- Do not globally prefer the repository root before checking `getwd()`; parsing tests intentionally create synthetic temporary `version_history.md` files and must keep reading those local fixtures.
- `testthat` runs from `tests/testthat` should find the root `version_history.md` through upward search.
- Empty temporary directories without `version_history.md` must still produce the warning plus default fallback behavior.
- Keep `tests/testthat/test-version-history-label-behavior.R` and `tests/testthat/test-version-history-parsing-behavior.R` aligned with this contract.
- Do not solve this by broad boot, working-directory, or global path changes.

### 1C) Streaming and final markdown HTML safety boundary

Browser-rendered markdown is a protected security boundary. User-controlled and LLM-controlled prose must never pass to `innerHTML` as raw HTML.

Current contract:

- Chat history tables are a separate browser display boundary. `R/module_chat_history.R` must keep the `Söyleşi Geçmişi` DataTable on `escape = TRUE` because `Söyleşi Adı`, `Tarih`, `Soru`, and `Cevap` are plain-text previews of stored user/LLM-controlled content. Do not switch this table back to `escape = FALSE` unless every rendered column is explicitly sanitized and the contract test is updated.

- Browser-side streaming markdown escaping belongs in `www/js/streaming_markdown_safety.js` and `www/js/markdown-parser.js`.
- `www/js/markdown-parser.js` must escape raw prose before converting markdown tokens into the small allowed HTML subset used by the app.
- The allowed streaming markdown output is intentionally small: headings, strong/emphasis, inline code, fenced code blocks, line breaks, unordered lists, and the existing app-controlled code block wrappers.
- `www/js/streaming_manager.js` may assign to `innerHTML` only from the safe markdown parser. Parser-missing fallback must use `textContent`, not raw accumulated text as HTML.
- UI asset order is part of the safety boundary: `www/js/streaming_markdown_safety.js` must load before `www/js/markdown-parser.js`, and `www/js/markdown-parser.js` must load before `www/js/streaming_manager.js`.
- Server-side final and saved message markdown rendering must use `render_safe_markdown_html()` from `R/helpers_markdown_safety.R` for user/LLM-controlled prose. Do not call `commonmark::markdown_html()` directly on such prose unless raw HTML has first been escaped.
- The generated-image card markup (image + `MERGEN Bilge` watermark + download/copy/print action buttons + optional description) is a single canonical builder: `mergen_generated_image_card_html()` in `R/helpers_markdown_safety.R`. It escapes `message_id` and `description` (XSS boundary) and places the caller-trusted `img_src` into `src` as-is. It is loaded before `R/helpers_chat_message_formatting.R` and `R/module_image_generation.R`. The live image path (`render_generated_image_html()`, `render_image_from_saved_path()` in `R/module_image_generation.R`) and the saved-chat reload path (`db_message_render_image_html()` in `R/helpers_chat_message_formatting.R`) must delegate the card markup to this helper. Do not re-inline the `image-action-btn-modern` button markup in those consumers, and do not duplicate the card template in a third site. The not-found / not-loaded placeholder branches in `db_message_render_image_html()` are intentionally different (no image, no buttons) and stay local. Protected by `tests/testthat/test-generated-image-card-html-contract.R`.
- User image `img_src` is served session-scoped, not inlined as base64. The canonical serving helper is `mergen_serve_image_data_url()` in `R/helpers_markdown_safety.R`: when an active Shiny session exists it serves the file via `session$registerDataObj(...)` (session-scoped, unguessable URL → preserves per-user isolation; the browser fetches the image directly/lazily/in parallel, avoiding multi-MB base64 over the websocket), and per-session it memoizes one registered URL per file path through `session$userData$mergen_image_url_cache`. With no session (tests/non-reactive context) or on registration error it falls back to the original `data:image/png;base64,...` data URI, so existing no-session behavior and tests are unchanged. The two consumers — `get_image_web_url()` (`R/module_image_generation.R`, live generation) and `db_message_get_image_base64()` (`R/helpers_chat_message_formatting.R`, saved-chat/gallery reload) — must prefer this helper through a guarded `exists("mergen_serve_image_data_url", ...)` check and keep their inline base64 path as the fallback. Do not regress this back to unconditional inline base64; that reintroduces the slow Görsel Galerisi conversation load. Do not switch user images to a plain `addResourcePath()` public path (that would break user isolation with guessable cross-user URLs).
- Raw HTML/script/event-handler patterns such as script tags, image error handlers, javascript links, and malformed tags split across streaming chunks must remain escaped or inert.
- The browser UX smoke harness is part of this safety boundary, not a demo page. Keep `www/smoke/ux-smoke.html` and `www/smoke/ux-smoke-probes.js` explicit about streaming init/delta/stale requestId/finalize behavior, dangerous HTML-like payload inertness, finalize cleanup, audio duck ownership, saved-chat TTS non-autoplay, navigation cleanup, welcome-video init/destroy counters, and synthetic File Manager Turkish display-name refresh checks.
- Smoke-only seams must remain namespaced and inert in production: `window.MergenStreamingSmoke`, `window.MergenAudioLifecycleSmoke`, `window.MergenWelcomeVideoSmoke`, and `window.MergenUxSmokeProbes`. Do not add `www/smoke/ux-smoke-probes.js` to `R/config_ui_assets.R`.
- Do not add CDN dependencies, runtime downloads, external sanitization libraries, bundling, or minification for this boundary.

### 1D) Modern welcome light-theme and neural pointer boundary

The Ana Söyleşi modern welcome screen has a protected light-theme UX boundary. Light-theme glassmorphism for the welcome card, quick action buttons, personal greeting title, and neural-side background is intentionally tuned through scoped `html[data-theme="light"]` overrides. Keep these changes CSS-only unless behavior truly requires JavaScript. Do not regress the dark theme while adjusting light-theme surfaces.

The right-side neural network animation must only react to pointer movement inside the neural animation region. Do not restore global attraction behavior that follows the pointer over the video side, welcome card, quick action buttons, or other non-neural areas. Multi-monitor exit behavior is also protected: when the pointer leaves the browser window, especially toward a second display, the neural mouse target must reset instead of continuing to pull nodes toward the last browser-edge coordinate.

### 1E) Support and version-page light-theme UX boundary

The support pages have a protected light-theme UX boundary. Keep support-page refinements scoped and CSS-first unless behavior truly requires JavaScript or R structure changes.

Current protected expectations:
- The “Geri Bildirim & Hata” feedback tab uses visible light-theme borders for the 0-10 NPS score buttons. Preserve the existing dark-theme NPS color behavior and keep any light override scoped under `html[data-theme="light"]`.
- The “Yenilikler” page must keep version selector badges readable in light mode. The generated version selector buttons use `.destek-surum-tab`; do not target only non-existent or modal-only badge classes when fixing this page.
- The “Yenilikler” page UX should keep the hero and version selector area stable while the version card area scrolls vertically. Avoid reverting the layout to a page-wide scroll where the hero and badges move away.
- The startup/version notification badge uses a masked pseudo-element to preserve the thin animated glowing border. Keep the standard `mask` declaration with the WebKit-prefixed fallback unless a cross-browser visual test proves the fallback is no longer needed.
- The Yardım Merkezi “Yardım Asistanı” chat must have a distinct light-theme user bubble. The user bubble should use the support teal token `--mb-brand-support-teal` with sufficient white-text contrast.
- Yardım Asistanı bot responses can contain Markdown-derived HTML such as `strong`, `em`, headings, lists, and inline code. Light-theme CSS must explicitly preserve contrast for these elements inside bot bubbles without weakening the Markdown/HTML safety boundary.

### 1E.1) Light Theme Header and Badge Consistency

- Light-theme page headers are kept pixel-aligned with the MERGEN Bilge top navbar/header band.
- Header alignment rules must not force 50px `line-height` onto nested badges; AJAN, Bağlı, and ADMIN badges must keep compact badge-specific line-height.
- The Bilge Yolaç AJAN badge and Yönetici Paneli ADMIN badges use the same red pill-style badge language in light theme.
- The relevant CSS maintenance points are `www/css/chat_header.css`, `www/css/claude_code.css`, and `www/css/admin_analytics.css`.
- When touching these areas, verify visually in light theme on Bilge Yolaç and all Yönetici Paneli subpages: Genel Analiz, Geri Bildirim Analizi, Hata Analizi, Yanıt Geri Bildirimi, and Sistem Durumu.

Validation note for this documentation-only update:
- Do not run R validation for this specific docs-only change. Manual Markdown review is sufficient unless code files are changed later in a separate task.


### 1F) Effective API key resolution for non-chat AI features

TTS, AI Expert speech generation, and other non-chat AI features must not read `session$userData$ai_api_key` directly or invent separate institutional-key fallback logic. They should use the centralized feature helper in `R/helpers_feature_api_key.R`, which builds on the ownership-safe API key helpers in `R/helpers_api_key_identity.R`.

The intended resolution contract is:

- personal user key first, when it belongs to the authenticated application user;
- feature-specific service key next only when that feature explicitly needs it, such as TTS;
- allowed institutional default key when personal keys are absent and default-key use is enabled;
- legacy fallback key only as the final compatibility fallback.

This keeps “continue with institutional key” behavior consistent across normal chat, “Yanıtları Seslendir”, and “AI Uzman Konuşması” without changing runtime UX. Never log, print, expose, or include raw key, token, endpoint secret, cookie, password, or auth header values in documentation, validation reports, or diagnostics.

### API key choice modal boundary

The API key choice onboarding modal is a protected Shiny/browser boundary. Keep its runtime UX stable while preserving browser-console hygiene and secret safety.

Current contract:
- `www/js/api_key_choice_modal.js` must register Shiny custom message handlers with exactly one message argument. Do not reintroduce zero-argument custom message handlers.
- Initialize `window.MergenApiKeyChoice` before registering handlers, keep `_inputId` null-safe, and do not replace the namespace object after `_inputId` may have been set.
- Client-side code may store or report only the non-sensitive `api_key_onboarding_suppressed` preference flag under `mergen_settings`. It must never read, store, print, or log personal API keys, the default institution API key, tokens, secrets, passwords, cookies, DSNs, endpoints, or auth headers.
- `R/module_api_key_choice_modal.R` must keep the Shiny ids `api_key_plain_input`, `api_key_save_btn`, `api_key_clear_btn`, and `api_key_use_default_btn` stable so existing server observers continue to bind without UX changes.
- The password input should remain inside a non-submitting form used only to satisfy browser password-form heuristics. Keep save/clear action buttons outside the form.
- The actual password input should keep `autocomplete="new-password"`, and the same form should include a hidden username field with `autocomplete="username"` to avoid Chrome DevTools password-form verbose messages.
- Regression coverage for this boundary belongs in `tests/testthat/test-api-key-choice-modal-contract.R`. Prefer small focused assertions there rather than broad runtime tests for this browser-hygiene contract.

### Help Center chatbot light-theme contrast boundary

The Yardım Merkezi / Yardım Asistanı chatbot has a protected light-theme contrast boundary. User chat bubbles in light mode should use the support teal brand token (`--mb-brand-support-teal`, fallback `#077780`) so user messages remain visually distinct from bot responses. Bot answer bubbles should remain readable light cards, and Markdown-generated rich text such as `<strong>`, emphasis, headings, lists, and inline code must keep sufficient contrast on light surfaces. Keep these changes CSS-only and scoped to `html[data-theme="light"]`; do not regress the dark theme or alter chatbot runtime behavior.

Protected by:

- `tests/testthat/test-chat-history-datatable-safety-contract.R`

- `tests/testthat/test-streaming-markdown-safety-contract.R`
- `tests/testthat/test-ui-asset-manifest-contract.R`
- `www/smoke/ux-smoke.html`
- `www/smoke/ux-smoke-probes.js`
- `tests/scripts/ai_browser_ux_smoke.R`
- `tests/testthat/test-ux-smoke-browser-contract.R`
- `tests/testthat/test-browser-smoke-harness-contract.R`
- `tests/testthat/test-browser-ux-smoke-runner-contract.R`
- `tests/testthat/test-smoke-probes-contract.R`

Protected by:

- `tests/testthat/test-text-encoding-utils.R`
- `tests/testthat/test-db-normalization-contract.R`
- `tests/testthat/test-db-refactor-contract.R`
- `tests/testthat/test-file-manager-display-name-contract.R`
- `tests/testthat/test-maintainability-ratchet-contract.R`
- `tests/testthat/test-claude-code-process-refactor-contract.R`
- `tests/testthat/test-claude-code-document-download-link-encoding.R`
- `tests/testthat/test-ui-asset-manifest-contract.R`
- `tests/testthat/test-streaming-markdown-safety-contract.R`
- `tests/testthat/test-db-user-visible-encoding-boundaries.R`
- `tests/scripts/run_vm_encoding_preflight_real.R`
- `tests/scripts/repair_mb_messages_mojibake.R`
- `tests/scripts/parse_sanity_check.R`

Focused validation:

- `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")`
- `testthat::test_file("tests/testthat/test-claude-code-document-download-link-encoding.R")`
- `testthat::test_file("tests/testthat/test-db-user-visible-encoding-boundaries.R")`
- `testthat::test_file("tests/testthat/test-db-refactor-contract.R")`
- `testthat::test_file("tests/testthat/test-db-normalization-contract.R")`
- `testthat::test_file("tests/testthat/test-text-encoding-utils.R")`
- `testthat::test_file("tests/testthat/test-file-manager-display-name-contract.R")`
- `testthat::test_file("tests/testthat/test-production-contracts.R")`
- `source("tests/scripts/parse_sanity_check.R", encoding = "UTF-8")`
- `source("tests/scripts/run_vm_encoding_preflight_real.R", encoding = "UTF-8")`
- `Sys.setenv(MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST = "TRUE")`
- `Sys.setenv(MERGEN_PREFLIGHT_FAIL_ON_LEGACY_MOJIBAKE = "FALSE")`
- `source("tests/scripts/run_vm_encoding_preflight_real.R", encoding = "UTF-8")`
- `Sys.setenv(MERGEN_REPAIR_MOJIBAKE_APPLY = "FALSE")`
- `source("tests/scripts/repair_mb_messages_mojibake.R", encoding = "UTF-8")`
- `Sys.setenv(MERGEN_PREFLIGHT_CHECK_FILE_STORE = "TRUE")`
- `source("tests/scripts/run_vm_preflight_real.R", encoding = "UTF-8")`
- `source("tests/testthat.R", encoding = "UTF-8")`
- `testthat::test_file("tests/testthat/test-maintainability-ratchet-contract.R")`
- `testthat::test_file("tests/testthat/test-claude-code-process-refactor-contract.R")`
- `testthat::test_file("tests/testthat/test-ui-asset-manifest-contract.R")`

The latest DB encoding guardrail tightening keeps the checks inside `tests/testthat/test-db-normalization-contract.R` and `tests/testthat/test-db-refactor-contract.R`. These tests protect environment-based resolution of `DB_CLIENT_ENCODING` and `DB_NAME_ENCODING`, the `WINDOWS-1254` Turkish DB parameter path, common Turkish mojibake repair examples such as `NasÄ±l`, `TÃ¼rkiye`, `baÅŸkent`, and `yardÄ±mcÄ±`, and the DB-safe Unicode escape/restore path for unsupported characters. If these tests fail, do not deploy to the Windows VM.

VM-only manual validation after any DB encoding change:
- Start the app on the Windows VM with SSO enabled.
- Confirm `.Renviron` contains both `DB_CLIENT_ENCODING=WINDOWS-1254` and `DB_NAME_ENCODING=WINDOWS-1254`, then restart the full R process; a browser refresh is not enough.
- Run the transactional VM encoding preflight with `MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST=TRUE` and confirm it rolls back the probe records.
- Keep `MERGEN_PREFLIGHT_FAIL_ON_LEGACY_MOJIBAKE=FALSE` for normal acceptance when historical dirty rows are known to exist; use `TRUE` only when the goal is to block on all legacy mojibake.
- Confirm that the latest newly inserted `MB_Messages` rows are clean in SSMS. Historical dirty rows may remain as legacy data and should not be confused with new write regressions.
- If a one-time repair is attempted, run `tests/scripts/repair_mb_messages_mojibake.R` first with `MERGEN_REPAIR_MOJIBAKE_APPLY=FALSE`, review the preview, then use `TRUE` only after DB backup and approval.
- Never add `quit()` to repository maintenance scripts that are expected to be run via `source(...)` in RStudio or on the VM.
- Create a chat containing `Türkçe test: ç ğ ı İ ö ş ü Ç Ğ I Ö Ş Ü` and `Türkiye'nin başkenti neresidir?`.
- Create or trigger an AI answer containing a character that cannot be represented by `WINDOWS-1254`; verify that the live answer displays correctly, the saved/reloaded chat displays the restored character, and SSMS stores an ASCII token such as `[[MERGEN-U+1F680]]` rather than raw unsupported Unicode or mojibake.
- Add feedback tags/comments containing Turkish characters.
- Inspect newest `MB_Messages`, `MB_Chats.ChatTitle`, and `MB_Feedback` rows in SSMS.
- Verify the new rows directly in SSMS for `MB_Users`, `MB_Chats`, `MB_Messages`, and `MB_Feedback`.
- Upload a file with a Turkish filename and verify the display name after a full app restart.
- In SSMS, verify the relevant message/chat text column types before changing encoding behavior:
  SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, COLLATION_NAME
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_NAME IN ('MB_Messages', 'MB_Chats')
    AND COLUMN_NAME IN ('MessageContent', 'ReasoningContent', 'ChatTitle');
- Reject the change if SSMS shows new mojibake such as `Ã§`, `Ä±`, `Ã¶`, `ÅŸ`, `ÄŸ`, `TÃ¼rkiye`, `NasÄ±l`, or `yardÄ±mcÄ±`.
- Do not run an automatic startup migration for existing corrupted rows. Old rows require backup and a separate one-time repair plan after new writes are proven correct.



### 1D) Browser UX smoke coverage boundary

The fragile client-side UX flows are protected by a lightweight same-origin browser smoke harness. `www/smoke/ux-smoke.html` loads the live app in an iframe and also loads the smoke-only helper `www/smoke/ux-smoke-probes.js`. A successful manual run must end with `UX_SMOKE_DONE:PASS`.

The smoke harness covers:
- streaming lifecycle: init, delta append, stale `requestId` rejection, finalize, action button restore, follow-up pending cleanup, and duplicate assistant-message prevention;
- streaming safety: dangerous HTML-like payloads remain inert text and must not become active HTML;
- audio lifecycle: single background music source, TTS ducking, STT ducking, overlapping TTS/STT duck owners, and no saved-chat historical TTS autoplay;
- navigation/video lifecycle: Bilge Yolaç ↔ Ana Söyleşi transitions must not leave stale active tool/page panel state, stale URL hash state, stale modal/backdrop residue, or stale audio/TTS ownership, and the welcome video must not be unnecessarily destroyed or reinitialized;
- File Manager display names: Turkish names such as `Türkçe_çalışma_özeti_İstanbul.pdf` must remain readable after synthetic refresh/listing without a real DB.

Smoke-only seams must stay namespaced and inert in production:
- `window.MergenStreamingSmoke`
- `window.MergenAudioLifecycleSmoke`
- `window.MergenWelcomeVideoSmoke`
- `window.MergenUxSmokeProbes`

Do not add `www/smoke/ux-smoke-probes.js` to the production runtime asset manifest in `R/config_ui_assets.R`. Do not introduce CDN dependencies, runtime downloads, Playwright, Selenium, Cypress, chromote, or another heavy browser dependency unless the repo already supports it and the change is explicitly justified.

Relevant static contracts:
- `tests/testthat/test-browser-smoke-harness-contract.R`
- `tests/testthat/test-ux-smoke-browser-contract.R`
- `tests/testthat/test-smoke-probes-contract.R`
- `tests/testthat/test-audio-lifecycle-owner-smoke.R`
- `tests/testthat/test-true-streaming-reset-ui-contract.R`

Validation interpretation:
- In the maintainer VM/local environment, `bash tools/ai_validate.sh quick`, `bash tools/ai_validate.sh full --boot-smoke`, and `MERGEN_REQUIRE_BROWSER_UX_SMOKE=true bash tools/ai_validate.sh full --boot-smoke` have passed, and browser UX smoke ended with `UX_SMOKE_DONE:PASS` on the same-origin `/smoke/ux-smoke.html` route.
- If Codex Cloud fails before testthat starts because R package bootstrap cannot install packages such as `arrow`, `duckdb`, `odbc`, `pool`, or `shinyWidgets`, classify that as an environment/bootstrap failure, not as a code/test failure.

Browser UX smoke execution rules:
- `bash tools/ai_validate.sh full --boot-smoke` runs Shiny boot smoke first, then runs `tests/scripts/ai_browser_ux_smoke.R` opportunistically when a local Chrome/Chromium/Edge binary is available.
- Normal `--boot-smoke` may SKIP browser smoke (exit 0) when no local browser binary is found; VM/local environments that are expected to have a browser must enforce it with `MERGEN_REQUIRE_BROWSER_UX_SMOKE=true bash tools/ai_validate.sh full --boot-smoke` or `Rscript tests/scripts/ai_browser_ux_smoke.R --require-browser`.
- Use `MERGEN_BROWSER_BIN="/path/to/chrome-or-msedge"` when the browser lives outside default discovery paths.
- Explicit `MERGEN_BROWSER_BIN` configuration is BLOCKING: when it is set, the runner auto-enables require mode (silent SKIP is disabled), and an unusable path/command fails early with a clear `MERGEN_BROWSER_BIN kullanılamıyor` error instead of a late processx failure. Environments that declare a browser cannot silently skip browser smoke anymore.
- The browser route contract is the served path `/smoke/ux-smoke.html` (not repository path `www/smoke/ux-smoke.html`), and successful runs must end with `UX_SMOKE_DONE:PASS`.
- Smoke-only interfaces must remain namespaced and production-inert; `www/smoke/ux-smoke-probes.js` must not be added to `R/config_ui_assets.R`.
- Do not add CDN/runtime-download or heavy browser automation dependencies (npm, Playwright, Selenium, chromote, RSelenium, etc.) to this path.
- Forbidden dependency scans in the runner contract must ignore R comment lines before scanning so explanatory comments do not create false positives.
- Do not revert Linux/RSPM package bootstrap defaults to `pkgType = "binary"`; keep source-style defaults unless `MERGEN_AI_R_PKG_TYPE` is explicitly set.

### Claude Code on the web (cloud session) R environment contract

This repo is a Shiny app, and Claude Code web sessions need R installed before
tests can run. The provisioning is intentionally split and must stay aligned.

Current contract:

- `.claude/hooks/session-start.sh` is a SessionStart hook (matcher
  `startup|resume`) registered in `.claude/settings.json` alongside the existing
  `Stop` validation hook. It runs only in the remote/web environment
  (`CLAUDE_CODE_REMOTE=true`), is idempotent, persists test-mode env vars through
  `CLAUDE_ENV_FILE` (`TZ=UTC`, `MERGEN_RUN_APP=false`,
  `MERGEN_DISABLE_FUTURES=true`, plus placeholder `LOCAL_LLM_ENDPOINT`/`DB_DSN`/
  `AI_KEYS_MASTER`), and then calls `tools/setup_ai_r_environment.sh`. It must
  degrade gracefully (warn, exit 0) if package repos are unreachable so the
  session is not bricked.
- The hook must not duplicate the package list. `tools/setup_ai_r_environment.sh`
  remains the single installer and reads `required_packages` from
  `R/config_packages.R` via `tests/scripts/ci_install_packages.R`.
- For "install once and reuse" (environment caching), the heavy install belongs
  in the cloud environment **Setup script** field
  (`bash /home/user/MERGEN-Bilge/tools/setup_ai_r_environment.sh`),
  which is snapshotted and skipped on later sessions. The SessionStart hook is the
  per-session idempotent safety net and env-var setter, not the cache owner.
  Use the full absolute path — `$CLAUDE_PROJECT_DIR` is not set during Setup
  Script execution (only in hooks), so variable-expanded or relative paths both
  fail with exit 127.
- Network access: the web environment must allowlist `packagemanager.posit.co`
  (RSPM index), `rspm-sync.rstudio.com` (RSPM package-file CDN), and
  `cloud.r-project.org` (CRAN + the apt repo for the latest R). R is not in the
  default Trusted list; without these, package repos return HTTP 403. RSPM
  307-redirects every `.tar.gz` download to `rspm-sync.rstudio.com`, so missing
  that host makes the `PACKAGES` index resolve (200) while downloads fail with
  `downloaded length 0`. `tests/scripts/ci_install_packages.R` verifies a real
  package download (not just the index) and auto-falls back to CRAN
  (`cloud.r-project.org` serves files directly) when the RSPM CDN is blocked, so
  bootstrap still works on the current allowlist — only slower, since CRAN
  compiles heavy packages from source instead of using RSPM binaries.
- R version policy: `tools/setup_ai_r_environment.sh` installs the latest R from
  the CRAN apt repo (`<codename>-cran40`) by default to track the on-prem VM
  (currently R 4.5.1, upgraded over time), with graceful fallback to the distro
  `r-base`. Override with `MERGEN_AI_INSTALL_LATEST_R=false`. Do not pin a single
  hard-coded R version in the installer; on-prem parity and CI (R 4.4 / 4.5) must
  keep working as the on-prem version advances.
- Do not add CDN/runtime-download dependencies or duplicate the CI workflows for
  this path. GitHub CI (`.github/workflows/mergen-ai-validation.yml`,
  `tests.yml`) already covers validation independently.
- Operator/setup details live in `.claude/web-environment.md`; keep that file and
  this contract aligned when changing the hook, installer, or network policy.
- This is cloud-bootstrap/provisioning infrastructure, not app logic. A passing
  cloud session still does not prove runtime/VM/SSO/DB or SQL Server Turkish
  encoding behavior; those remain the VM preflight gates in `RUNBOOK.md`.

### AI agent validation rule

Validation doctor:

Use the lightweight validation doctor when there is any risk that an agent or developer may confuse validation profiles. The doctor is available as `tests/scripts/validation_doctor.R` and `tools/validation_doctor.sh`. It does not run heavy checks, does not launch the app, does not open a browser, and does not connect to the real DB. It only reports environment classification, browser binary availability, secret-safe environment metadata, recommended command order, what each command proves and does not prove, and blocking versus warning-only checks.

Useful commands:

- `Rscript tests/scripts/validation_doctor.R --profile cloud`
- `Rscript tests/scripts/validation_doctor.R --profile local`
- `Rscript tests/scripts/validation_doctor.R --profile vm`
- `Rscript tests/scripts/validation_doctor.R --profile all`
- `bash tools/validation_doctor.sh --profile all`
- `bash tools/validation_doctor.sh all`

The doctor writes a JSON summary under `artifacts/validation-doctor/`. This artifact is guidance only and not an execution gate: it must explicitly record `doctor_runs_heavy_checks=false`, `validation_execution_status="not_run_by_validation_doctor"`, and `doctor_execution_notes`. Agents must not cite this artifact as proof that `cloud-quick`, `quick`, `full --boot-smoke`, browser-required smoke, VM/SSO preflight, SQL Server Turkish encoding preflight, or manual fragile-flow evidence actually ran. Those remain separate evidence gates and require the corresponding validation commands to be run directly.

The execution artifact written by `tools/ai_validate.sh` / `tests/scripts/ai_repo_check.R` is `artifacts/ai-validation/<timestamp>/summary.json`. Treat this as machine-readable execution proof only for the checks it says actually ran. It must carry `validation_execution_status="ran_by_ai_repo_check"`, `profile_requested`, `profile_effective`, timestamp, git branch/SHA/dirty summary when available, app source smoke status, Shiny boot smoke status, browser smoke status, browser-required flag, VM/SSO/DB status, SQL Server Turkish encoding status, manual fragile-flow status, failed/skipped step labels, and `proof_boundary_notes`. It must not expose raw DSN, endpoint, token, key, secret, password, cookie, or auth header values.
Latest validation-doctor contract hardening: `tests/testthat/test-validation-doctor-contract.R` now more explicitly protects secret-like environment values from leaking through doctor output or artifacts. Values such as `LOCAL_LLM_ENDPOINT`, `MERGEN_BROWSER_BIN`, DSNs, URLs, keys, tokens, secrets, and passwords must be reported only as safe metadata such as presence, character length, boolean-style flags, and `value=<hidden>`, never as raw values. The same contract keeps `cloud-quick` as a wrapper-level alias in `tools/ai_validate.sh` that maps to the quick repository profile; do not add `cloud-quick` as a third internal profile in `tests/scripts/ai_repo_check.R`. This is validation contract hardening only and must not be described as a runtime UX change.


### VM evidence gate contract (single repeatable preflight path)

`tests/scripts/run_vm_evidence_gate.R` (wrapper: `bash tools/vm_evidence_gate.sh`) is the single repeatable preflight validation path. It orchestrates the EXISTING validation scripts as ordered steps in CLEAN CHILD R sessions and writes one secret-safe machine-readable evidence artifact: `artifacts/vm-evidence/<timestamp>/evidence.json` plus per-step logs.

Milestone note: a Windows VM full evidence-gate run completed with `Toplam: 13 passed, 0 failed, 0 skipped`; `full_testthat`, `browser_ux_smoke`, `vm_preflight_real`, and `db_encoding_preflight` all passed. Example artifact: `artifacts/vm-evidence/20260612-211836/evidence.json`. This is strong on-prem VM readiness evidence only for the steps reported as `passed`; it does not replace long-running production load observation or manual fragile-flow QA.

Frozen step list (conscious updates only, together with `tests/testthat/test-vm-evidence-gate-contract.R` and `RUNBOOK.md`): `env_config`, `parse_sanity`, `app_boot_smoke`, `full_testthat`, `maintainability_report`, `frontend_ratchet`, `seam_doctor`, `source_manifest_contracts`, `ui_asset_manifest_contracts`, `browser_ux_smoke`, `vm_preflight_real`, `db_encoding_preflight`, `renv_status`.

Rules:

- Profiles: `MERGEN_EVIDENCE_PROFILE=vm` makes the VM-only gates (`vm_preflight_real`, `db_encoding_preflight`, `renv_status`) REQUIRED; `cloud` skips them with explicit reasons. Default resolves from `SSO_ENABLED`.
- Honesty: every step carries `proves` / `does_not_prove`; skipped steps are NEVER evidence. The `browser_ux_smoke` step is `passed` only when the log contains a real `UX_SMOKE_DONE:PASS` marker — child exit 0 alone is not proof, because the underlying smoke script exits 0 on browser-missing SKIP.
- Secret safety: environment values are reported only as `present/nchar/value=<hidden>` metadata; step logs and `evidence.json` pass through the gate's redaction helper. Never weaken this to print raw DSN/endpoint/key/token values.
- The gate script is INTENTIONALLY ASCII-only (like `.Rprofile` and `tools/renv_snapshot.R`): operational entry-point scripts can be `source(...)`-d under POSIX/C or Windows/Turkish locales where non-ASCII content is silently truncated (which would make a gate exit 0 without running). Do not add Turkish special characters to it. Child runners set a UTF-8 `LC_CTYPE` before sourcing Turkish-content scripts; keep that header.
- The gate is `source(...)`-safe (no `quit()`); required-step failure ends with `stop()`. It does not replace the individual gates or the manual fragile-flow checklist; it consolidates them into one artifact.
- `MERGEN_EVIDENCE_STEPS=<comma-list>` re-runs a subset; filtered-out steps are recorded as skipped. Clear it before intending to run the full gate.
- Browser UX proof can be optional/non-blocking by default. `MERGEN_REQUIRE_BROWSER_UX_SMOKE=true` makes it blocking and requires `UX_SMOKE_DONE:PASS`. `MERGEN_BROWSER_UX_BASE_URL=<base-url>` activates external-app mode: the app must already be running at that URL, and the runner tests its `/smoke/ux-smoke.html` route instead of starting a temporary Shiny child process. This is the preferred VM-stable workflow for mandatory browser proof in locked-down Windows/VDI environments.
- `full_testthat` uses `tests/scripts/run_full_testthat_isolated.R`, which runs sorted `tests/testthat/test-*.R` files one by one in clean `Rscript --vanilla` child processes. `MERGEN_TESTTHAT_START_INDEX` / `MERGEN_TESTTHAT_END_INDEX` may be used to resume a sorted-index range after failure. Child testthat processes must be protected from browser UX evidence-gating environment leakage.
- This gate's artifact is execution proof ONLY for steps it reports as `passed` (`validation_execution_status="ran_by_vm_evidence_gate"`). A cloud-profile run is NOT VM/SSO/DB/SQL Server Turkish encoding/browser proof.

Protected by: `tests/testthat/test-vm-evidence-gate-contract.R`.

### Validation proof and overclaim boundary

- Treat `artifacts/ai-validation/<timestamp>/summary.json` as the only machine-readable execution proof emitted by `ai_validate`.
- Treat `artifacts/validation-doctor/*.json` as guidance only, never as execution proof.
- Never claim full validation, app boot, browser UX, VM/SSO/DB, SQL Server Turkish encoding, or manual fragile-flow proof unless the matching summary field explicitly says `passed`.
- `cloud-quick` remains a wrapper over quick and intentionally skips app source smoke; report it only within cloud-quick scope.
- `ai_answer_check.R` rejects broad overclaims (for example “All validation gates passed” or “Validation doctor passed”) when proof fields do not support those claims.
- For docs-only updates to `README.md` and `CLAUDE.md`, do not run R validation; inspect only the documentation diff. Run validation only when code, tests, commands, validation scripts, or runtime behavior changes.

Cloud fallback validation:

- Normal validation remains `bash tools/ai_validate.sh quick`.
- Risky/runtime validation remains `bash tools/ai_validate.sh full --boot-smoke`.
- Cloud fallback validation is `bash tools/ai_validate.sh cloud-quick`.

In Codex / Claude Code cloud environments where full package installation or runtime validation is impractical because heavy packages such as `duckdb`, `arrow`, `odbc`, or `pool` cannot be installed quickly or safely, the agent must run:

`bash tools/ai_validate.sh cloud-quick`

This is a cloud-safe fallback profile. It maps to the quick repository profile, skips heavy/runtime source packages, and intentionally skips app source smoke. It is valid evidence that parse sanity and focused contract tests ran in the cloud, but it is not full runtime/app boot validation.

When `cloud-quick` is used, the final answer must explicitly say:

- `bash tools/ai_validate.sh cloud-quick` was run,
- whether it exited successfully,
- the `summary.json` path if produced,
- `profile_requested`,
- `profile_effective`,
- `validation_execution_status`,
- `failed_steps`,
- `skipped_steps`,
- `app_source_smoke_status`,
- `shiny_boot_smoke_status`,
- `browser_smoke_status`,
- `db_sso_vm_validation_performed`,
- `sql_server_turkish_encoding_preflight_status`,
- that full runtime/app boot/browser/VM/SQL Server/manual fragile-flow validation was intentionally not performed unless the corresponding separate evidence gate was also run.
- if validation doctor was used, the profile, summary artifact path, and proof boundaries it reported (and that it is not a substitute for the validation gate).

Do not claim “full validation passed”, “runtime validation passed”, “the app booted”, or “VM validation passed” based only on `cloud-quick`.

### Cloud validation and stale-checkout discipline

`cloud-quick` is the intended lightweight Codex/cloud validation path. It is useful for parse sanity and focused contract tests, but it intentionally does not prove app source smoke, full runtime boot, real browser UX, Windows VM/SSO behavior, real DB behavior, or SQL Server Turkish encoding.

A clean `git status --short` in Codex only proves that the local working tree has no local changes. It does not prove that the checkout matches current GitHub `main`. If the environment has no `origin` remote, cannot fetch, or cannot compare `HEAD` to `origin/main`, contradictory Codex results must be reported as `STALE/INCONCLUSIVE` rather than treated as production regressions.

The expected successful `cloud-quick` summary is: `environment: OK`, `parse sanity: OK`, `app source smoke: SKIPPED`, `focused contract tests: OK`, `failed_steps: 0`, and `skipped_steps: 1`.

Latest validation-proof-status note: `artifacts/ai-validation/<timestamp>/summary.json` now makes the requested/effective profile boundary and non-executed heavy gates explicit. If normal `quick` fails in a cloud environment during app source smoke because heavy/runtime packages such as `arrow`, `duckdb`, `odbc`, `pool`, or `shinyWidgets` are unavailable, the cloud-safe fallback may be used with `MERGEN_AI_REQUESTED_PROFILE=cloud-quick`, `MERGEN_AI_EFFECTIVE_PROFILE=quick`, `MERGEN_AI_SKIP_SOURCE_PACKAGES=duckdb,arrow,odbc,pool`, `MERGEN_AI_SKIP_APP_SOURCE_SMOKE=true`, and `MERGEN_AI_R_PKG_TYPE=source`. A passing fallback summary such as `failed_steps=0`, `skipped_steps=1`, `profile_requested="cloud-quick"`, `profile_effective="quick"`, and `app_source_smoke_status="skipped"` is valid evidence only for parse/contract boundaries. It must not be reported as full validation, runtime app-source proof, Shiny boot proof, browser UX proof, VM/SSO/DB proof, SQL Server Turkish encoding proof, or manual fragile-flow evidence. If Windows VM/RStudio child `Rscript.exe` crashes at the environment probe before repo checks run, report it as a local validation-runner environment limitation, not as a MERGEN runtime regression.

Keep `R/helpers_db_connection.R` compatible with `cloud-quick`: it must not top-level load `odbc` or `pool` with `library()` or `require()`. Use lightweight top-level `DBI` availability checks only, and keep `odbc` checks inside the actual connection functions. This preserves cloud bootstrap compatibility without weakening real DB validation; real DB/SSO/SQL Server confidence still comes from the VM preflight scripts.

When in-house server/VM validation passes and Codex cloud reports a contradictory failure, do not change working runtime code until the Codex checkout, commit, and latest artifact log are proven current. Treat missing package bootstrap, no remote, stale artifacts, and long source compilation as environment limitations unless a current failing log proves otherwise.


Bootstrap package-type contract:
- `tests/scripts/ci_install_packages.R` must keep Linux-safe default package type as `source`.
- `MERGEN_AI_R_PKG_TYPE` override must remain supported only when explicitly set (`source` or `binary`).
- The static guard is `tests/testthat/test-ai-package-bootstrap-contract.R`.
- RSPM wiring checks in that contract must use stable URL fragments (for example `__linux__/noble/latest` and `__linux__/jammy/latest`) rather than brittle token shapes that may not exist in shell code formatting.

### renv dependency-lock contract

MERGEN Bilge pins exact package versions with `renv`. `R/config_packages.R` stays the human-readable manifest (its startup `requireNamespace` validation MUST NOT be removed); `renv.lock` is the exact-version source. The `renv.lock` MUST be generated on the working Windows VM (R 4.6.0), NOT from Linux/cloud. Full guide: `docs/dependency-locking.md`.

**WHERE `renv.lock` LIVES (read this before reporting it "missing"):** the real `renv.lock` is COMMITTED in the **on-premise Windows VM production repository** — the working copy that actually runs the app (`//rehisds/.../MERGEN Bilge/renv.lock`, R 4.6.0, ~116 packages). It is INTENTIONALLY NOT present in the GitHub repository that Claude Code / Codex cloud sessions check out, so `git ls-files renv.lock` will be empty in a cloud checkout. This is EXPECTED, not a defect. An AI agent in a cloud session must NOT claim `renv.lock` is "missing from the repo", must NOT treat its absence as a bug, and must NEVER generate/reconstruct `renv.lock` from Linux/cloud (it would record wrong/incomplete versions). The committed `RENV_LOCK_STATUS.md` marker documents this provenance; the cloud checkout intentionally ships only the marker. If the operator ever wants the lock mirrored to GitHub too, that is a manual `git add renv.lock && git push` from the VM — not a cloud-session task.

Protected behaviors (do not regress):

- The root `.Rprofile` is a deliberately CONDITIONAL, offline-safe loader. It activates renv ONLY when all of these hold: `renv/activate.R` exists, `renv.lock` exists, `renv` is installed, AND `renv/library` is actually populated (at least one installed package, checked with a bounded `Sys.glob(file.path("renv","library","*","*","*","*","DESCRIPTION"))`). Otherwise it is a NO-OP (global/system library) and never downloads renv and never crashes startup (wrapped in `tryCatch`). Escape hatch: `MERGEN_DISABLE_RENV_AUTOLOAD=true`.
  - The populated-library condition is critical: `tools/renv_snapshot.R` only RECORDS `renv.lock`; it does NOT populate `renv/library`. So on a production VM that generated the lock but did not run `renv::restore()`, the project library is empty and the app must keep using the global library. Do NOT replace this with the standard unconditional `source("renv/activate.R")` — that breaks cloud/CI/VM by switching `.libPaths()` to an empty project library.
  - `.Rprofile` and `tools/renv_snapshot.R` are intentionally ASCII-only (no Turkish special characters), because they are sourced at every startup and read/`parse()`-ed by tests on the Windows/Turkish-locale VM where non-ASCII can produce `input string 1 is invalid UTF-8`.
- `tools/renv_snapshot.R` is the VM helper that writes `renv.lock` (scoped to `required_packages` + test/CI extras + renv) from the current library, without touching `.Rprofile`. Do NOT call `renv::init()` (it overwrites `.Rprofile` with the unconditional form).
- `tests/scripts/ci_install_packages.R` prefers `renv::restore(prompt = FALSE)` when `renv.lock` exists and renv is available, then falls back to the existing RSPM/CRAN flow for anything still missing; when `renv.lock` is absent the existing behavior is unchanged. The mergen-ai-validation cache key includes `renv.lock`.
- `.gitignore` policy: commit `renv.lock`, `renv/activate.R`, `renv/settings.json`, and `renv/.gitignore`; never commit `renv/library/`, `renv/cellar/`, `renv/staging/`, `renv/sandbox/`, `renv/python/`, `renv/local/`, `renv/lock/`. Do not reintroduce a blanket `renv/` ignore (it would hide `activate.R`).
- `RENV_LOCK_STATUS.md` is a marker (NOT a real lock) recording that the real `renv.lock` is committed in the on-prem Windows VM production repo (R 4.6.0, ~116 packages). It must never be named `renv.lock`. In a cloud checkout this marker is the ONLY renv-lock artifact present, and that is expected — see "WHERE `renv.lock` LIVES" above. `tests/testthat/test-renv-lock-contract.R` is written to PASS whether or not `renv.lock` is physically present (it only enforces `required_packages` ⊆ `renv.lock` WHEN the lock exists); a green run with the lock absent is NOT a failure to chase.

Tests that scan these files (`tests/testthat/test-renv-lock-contract.R`) MUST use the byte-safe reader pattern (`readBin` + `iconv(..., sub = "byte")`) with `grepl(..., useBytes = TRUE)` over ASCII anchors. Plain `readLines(..., encoding = "UTF-8") + grepl()` over Turkish-commented files fails on the Windows VM with `invalid UTF-8` (this is why those tests pass individually but failed inside the full suite). The same Windows-safe rule applies to any new test that scans repo files for content.

Protected by:
- `tests/testthat/test-renv-lock-contract.R`
- `tests/testthat/test-ai-package-bootstrap-contract.R`

### Image upload, preview, and the vision (görsel anlama) pipeline

- Image files (`jpg`, `jpeg`, `png`, `gif`, `webp`, `bmp`, `svg`) are an allowed upload type via `fm_image_extensions()` inside `fm_normal_allowed_extensions()` (single source). The Dosya Yönetimi bulk-upload path validates the extension BEFORE copying to disk, so unsupported types no longer leak (saved-but-hidden). See `tests/testthat/test-image-upload-allowed-behavior.R`.
- The Dosya Yönetimi file preview (`R/module_file_preview.R`) renders images inline by serving the file through `session$registerDataObj(...)` (same pattern as large-PDF preview) and showing an `<img>`; it must not regress to "Desteklenmeyen Dosya Türü" for these extensions.

### DOCX preview async clobber guard

`R/module_file_preview.R` has a protected DOCX-preview concurrency boundary. Large DOCX previews encode asynchronously and write into the fixed `docx_preview_container` target. Keep the inline `docx_preview_seq <- reactiveVal(0L)` module-scope token. Each DOCX modal open must increment it, capture `docx_open_token`, and guard both the async success `%...>%` callback and the error `%...!%` callback with `identical(isolate(docx_preview_seq()), docx_open_token)` before sending UI messages or stale error toasts.

A stale callback may store a valid base64 result in the cache, but it must not write into the current modal and must not show a stale toast. Do not remove this guard, do not replace it with a global flag, and do not add a large top-level helper just for this boundary.

Regression coverage belongs in `tests/testthat/test-file-preview-docx-async-clobber-behavior.R`. Keep that test deterministic: use `testServer`, mock `future::future` with `local_mocked_bindings(.package = "future")`, return a manually resolved `promises::promise`, and use a non-existent datapath so the async branch is reached without a large fixture.

### Behavioral-test maintenance lessons

Do not redo recently completed behavioral-coverage work: DOCX async clobber protection is already implemented, the MCP absolute-path security contract is re-anchored to stable behavior, and behavioral coverage exists for `call_llm_with_retry`, `.sso_der_*`, file-store mutation helpers, sidebar user panel helpers/server behavior, `resolve_claude_runtime_source_dir`, and `get_user_profile_from_db`.

Keep these lessons in mind for future tests:
- The base cloud checkout may not have `logger`; do not source `R/config_logging.R` in a zero-skip test unless `logger` is installed first.
- Do not use fragile frame-counting `glue(.envir = parent.frame(N))` stubs for logger capture.
- Turkish `toupper` is locale-dependent; assert locale-independent markers instead of uppercased Turkish strings.
- `testServer` observers with `ignoreInit = TRUE` often need PRIME-THEN-SET input changes.
- For module custom-message capture, override the root session via `.subset2(session, "parent")`.
- Mock `future::future({...})` with a manually resolvable `promises::promise` when testing async behavior; do not force real workers or large fixtures.
- VISION IS IMPLEMENTED (capability-primary, real — NOT faked). Attaching an image to Model Bağlamı and asking about it works when (a) the selected model is vision-capable and (b) the global kill-switch is not explicitly disabled. This replaces the old "no vision pipeline" limitation.
  - Pure helpers: `R/helpers_vision_context.R` (image detection, MIME, base64 data-url with a 5 MB cap, OpenAI multimodal content builder, the `none`-branch context-block loop, the explicit Turkish "analiz edilemiyor" note, and the `mergen_vision_enabled()` kill-switch) and `R/helpers_vision_model_capabilities.R` (the pure `parse_vision_models_env()` + `apply_vision_model_capabilities()` that mark `api_config$local_model_capabilities[[m]]$vision`). Keep `R/helpers_vision_model_capabilities.R` loaded BEFORE `R/config_api.R` in the manifest, and `R/helpers_vision_context.R` BEFORE `R/helpers_send_message_prompting.R`. Neither file touches Shiny/reactive/network/DB.
  - Capability is the single source of truth: `mergen_is_vision_model(model, api_config)` reads `caps[[m]]$vision` only (mirrors `is_thinking_model`). `config_api.R` defaults `vision = FALSE` on every `local_model_capabilities` entry, then sets `vision = TRUE` for the IDs in `MERGEN_VISION_MODELS` (`;`/`,`-separated — model IDs may contain spaces, so split on `;`/`,` ONLY, never whitespace) plus the Kodlama Uzmanı deep-thinking models (`CODING_DEEP_LOW_MODEL`/`CODING_DEEP_HIGH_MODEL`). Do NOT hardcode model names in functions; drive it from config/data + env. `config_api.R` must stay within its 520-line / 6-function per-file ratchet budget — the vision marking lives in `R/helpers_vision_model_capabilities.R` and the deep-thinking capability/endpoint registration lives in `R/helpers_deep_thinking_model_capabilities.R`, both called via guarded `exists(...)` checks.
  - `mergen_vision_enabled()` is a DEFAULT-ENABLED kill-switch: active unless `options(mergen.vision_enabled)` / `MERGEN_ENABLE_VISION` is EXPLICITLY false (`false`/`f`/`0`/`no`/`off`/`hayır`/`kapalı`). So marking a model `vision = TRUE` is sufficient to enable vision for it; `MERGEN_ENABLE_VISION=false` disables vision globally.
  - When `mergen_vision_active(model, api_config)` is true AND a real image encodes, the `none`-branch final user message `content` becomes an OpenAI multimodal ARRAY (`[{type:text},{type:image_url,image_url:{url:"data:...;base64,..."}}]`); otherwise it stays a STRING and images get the explicit Turkish note. Both `R/helpers_llm_api.R` (non-streaming) and `R/helpers_llm_sse.R` (streaming) preserve list-content and serialize via `toJSON(..., auto_unbox = TRUE)`, so the array survives to the HTTP body UNCHANGED. Do NOT regress the text path (non-capable models must still get the explicit Turkish note); do NOT fake vision.
  - Protected by `tests/testthat/test-vision-context-behavior.R`, `tests/testthat/test-vision-model-capabilities-behavior.R`, and `tests/testthat/test-vision-llm-payload-serialization-behavior.R`.
  - VM-only live check (NOT provable in cloud — there is no real vision endpoint there, and `MERGEN_VISION_MODELS` is unset): on the Windows VM set `MERGEN_VISION_MODELS=<real image-capable model IDs>` in `.Renviron`, attach an image, ask about it, and confirm a usable answer end-to-end. The base64→HTTP-body path is real but has not yet been exercised against a live vision endpoint.

Before giving a final technical answer about this repository, an AI agent must run `bash tools/ai_validate.sh quick`.

For risky changes, runtime changes, source-order changes, SSO changes, DB encoding changes, file lifecycle changes, streaming changes, frontend asset order changes, Bilge Yolaç / Claude Code changes, security/path/download changes, or production/VM-sensitive changes, the AI agent must run `bash tools/ai_validate.sh full --boot-smoke`.

If an AI agent drafts a long technical answer, it should first save the draft to `.ai/proposed_answer.md`, then validate it with `bash tools/ai_validate.sh quick --answer .ai/proposed_answer.md`.

The “Rscript unavailable” rule must follow this sequence:

- first try the normal validation command when the environment supports it,
- if full cloud dependency/runtime validation is blocked by heavy packages, use `cloud-quick`,
- only report inability to validate if both the appropriate validation command and the cloud fallback cannot run.

The agent must not stop at `/bin/bash: Rscript: command not found`. If `Rscript` is missing, it must first run `bash tools/setup_ai_r_environment.sh` or use `bash tools/ai_validate.sh quick`, which performs bootstrap automatically.

An AI agent must not say “tests passed”, “I verified”, “I ran the app”, “the check is green”, or similar unless the relevant command really completed successfully and the validation summary reports zero failed steps.

Documentation-only exception:
- If a requested change modifies only `README.md` and/or `CLAUDE.md`, do not run R validation, `Rscript`, `testthat`, app boot checks, VM preflight, or `tools/ai_validate.sh` unless the user explicitly asks for runtime validation.
- For such docs-only changes, inspect the Markdown files and report `git diff -- README.md CLAUDE.md`.
- For such docs-only changes, do not run `Rscript`, `testthat`, or `tools/ai_validate.sh` unless the user explicitly asks for validation; report explicitly that validation was not run because the task was docs-only.
- For docs-only validation-profile wording changes, it is enough to inspect the edited Markdown and show the docs-only diff; do not run R validation unless the user explicitly asks for it.
- This exception does not apply to R, JS, CSS, test, config, asset-manifest, encoding, SSO, DB, streaming, Bilge Yolaç, or production-sensitive changes.

If `Rscript` is still unavailable after bootstrap, the AI agent must explicitly state that bootstrap failed, include the failing command, and must not imply the repository was validated.

If a required validation script is missing, the AI agent must state exactly which script is missing and must not invent successful results.

If validation fails, the AI agent must summarize the failing step and point to the generated artifact/log path rather than hiding the failure.

Preferred validation escalation:
- quick profile for documentation-only or low-risk explanations,
- full profile for code changes or production-sensitive behavior,
- full profile plus boot smoke for app boot/runtime confidence.

### Deep Space intro maintenance notes
- Keep `www/js/deep_space_intro.js` as the scene orchestrator; do not bloat it with specialized shader or solar-lighting internals.
- Keep Earth shader/material logic in `www/js/deep_space_intro_earth_shader.js` (desert brightness compression, day/night terminator smoothing, and night-light masking).
- Keep Sun/lens flare/halo/ambient/bloom setup in `www/js/deep_space_intro_solar.js`.
- Preserve asset load order in `R/config_ui_assets.R`: `js/deep_space_intro_earth_shader.js`, `js/deep_space_intro_solar.js`, then `js/deep_space_intro.js`.
- Preserve Moon physics separation: `moonSystemGroup` belongs under `mainGroup`, not `earthTiltGroup`.
- Chrome DevTools Verbose cold-start Three.js load violations are profiling hints, not functional failures, when browser console Errors and Warnings are both zero.
- Startup media preloading IS intentionally full-buffer now (deliberate product decision: the loading bar must not reach 100% until the welcome background videos and every persona intro video are genuinely playable). This is implemented safely in `www/js/app_loading_media.js`: videos are warmed SEQUENTIALLY (one at a time) into the browser HTTP cache, each hidden `<video>` element is REMOVED after `canplaythrough` so no live decoders linger, and buffering is serialized to avoid the decoder/disk-I/O contention that previously caused startup-music crackling. This is the agreed reconciliation of the older "no hidden full-buffer preloading" concern — keep the sequential, cache-warm, element-released pattern; do not switch to parallel `Promise.all` buffering or keep persistent hidden full-buffer `<video>` decoders alive, and do not regress to metadata-only warming.
- For this docs-only task type, do not run R validation; review markdown diff only.

### Theme system and light-theme contract

- Dark theme remains the default.
- Light theme is applied through `www/css/theme_tokens.css` (token base for BOTH themes) plus seven DOMAIN-SCOPED light files: `www/css/theme_light_core.css` (app shell: body, sidebar, navbar band, scrollbars, generic Bootstrap widgets), `theme_light_welcome.css`, `theme_light_chat.css`, `theme_light_modals.css`, `theme_light_bilge_yolac.css`, `theme_light_personalization.css`, and `theme_light_pages.css` (file manager, history/saved/gallery month groups, support pages, admin panels, health dashboard), driven by `www/js/theme_manager.js`.
- SINGLE-DEFINITION RULE: each selector is defined exactly ONCE across the theme chain. The old 13-file override/patch chain (`theme_light.css`, `theme_light_extras.css`, `theme_light_refinements.css`, `theme_light_polish.css`, `theme_light_overhaul.css`, `theme_light_overhaul_phase2.css`, `theme_light_user_polish.css`, `theme_light_user_polish_v2.css`) was consolidated into the domain files with its computed cascade result preserved one-to-one; those eight file names are TOMBSTONED and must never be reintroduced (`tests/testthat/test-theme-light-modular-contract.R` plus the frontend maintainability ratchet enforce this). To change light styling, edit the existing selector in its owning domain file — do not add another override layer, and do not re-declare a theme-chain selector in a second theme file.
- Component CSS files (for example `chat_header.css`, `sidebar_user_panel.css`, `surum_bilgilendirme.css`, `destek_yardim_chatbot.css`) may carry their own `html[data-theme="light"]` refinements for selectors they own; they load after the theme chain, so they remain the final word for their components. The cross-file light-duplicate budget in `tests/testthat/test-frontend-maintainability-ratchet.R` caps this pattern so it cannot regrow into a chain.
- Theme-chain selectors must reference classes/attributes that actually exist in runtime sources (R markup, JS, smoke). The legacy chain carried ~45% phantom selectors (guessed class names such as `.fm-drop-zone`, `.file-preview-modal`, `.yenilikler-page`, `[data-cc-badge]`) that never matched the DOM; these were removed during consolidation and the contract test now anchors only on verified-real selectors.
- Theme state is stored in `mergen_settings.theme` / localStorage and applied through `<html data-theme="...">`.
- `R/module_settings.R` must synchronize `input$mergen_theme_changed` and `input$mergen_theme_initial`; only valid `dark` / `light` values may be persisted.
- `theme_manager.js` must keep delegated click/touch/keyboard handling so the sidebar theme button still works after sidebar re-render.
- Asset ordering in `R/config_ui_assets.R` must keep `variables.css` before `theme_tokens.css`, tokens before `theme_light_core.css`, then the domain chain `core -> welcome -> chat -> modals -> bilge_yolac -> personalization -> pages`, with `brand_title.css`, `sidebar_user_panel.css`, and `tool_backgrounds.css` after the theme layers.
- These theme-layer ordering relationships are executable, not prose-only: `ui_asset_css_order_rules` in `R/config_ui_assets.R` declares the cascade chain and `ui_asset_validate_css_order()` is wired into `ui_asset_validate(...)`, so a broken theme cascade order fails early at UI build exactly like a broken JS dependency order. Do not remove rules to make a reordering pass; update the rule set consciously together with `tests/testthat/test-ui-asset-manifest-contract.R`.
- All theme_light_* rules must stay scoped to `html[data-theme="light"]`; the few intentionally theme-independent base selectors (month-group families, `.modern-welcome-bg-grid` / `.modern-welcome-action-btn` bases, `.stt-modal` titles, `.highcharts-grid-line`) are allowlisted explicitly in `tests/testthat/test-theme-light-modular-contract.R`.
- Preserve corporate blue hero headers, light cream surfaces, teal month-group accents, feedback/admin tab polish, Bilge Yolaç light tool surfaces, message action buttons, and welcome quick-action light-theme polish.
- Do not add CDN or external font dependencies.
- Do not force deep-space / cinematic / Explore modal areas into white light surfaces; they intentionally preserve the dark space experience.

### Sidebar user panel, Department, and version source contract

- Sidebar user panel ownership: `R/helpers_sidebar_user_display.R` (pure display/decision helpers: `mb_sidebar_user_initials()`, `mb_sidebar_user_avatar_url()`, `mb_sidebar_user_department()`, `mb_sidebar_theme_switch()`, `mb_sidebar_controls_row()`, `mb_sidebar_user_badge_ui()`), `R/module_sidebar_user_panel.R` (UI shell, logout event, server render orchestration), and `www/css/sidebar_user_panel.css`. Keep the display helper loaded before the module in `R/config_source_manifest.R`; do not move the pure helpers back into the module (it previously sat at the 24-function global ratchet ceiling). The split is protected by `tests/testthat/test-sidebar-user-display-split-contract.R`.
- It displays live identity-derived name/avatar, Department, theme button, version, and optional SSO logout.
- Initial render must keep the static skeleton/slot-output behavior so theme/user/logout controls do not appear late or disappear.
- After SSO completes, the sidebar user panel must bind to the live `user_config_rv()` value, not only to isolated session/userData fallbacks, so the user badge re-renders when the authenticated profile is ready.
- `MB_Users` is the authoritative fallback for sidebar-visible identity fields. Hydrate the runtime user identity from the `MB_Users` profile row before building `app_user_config`; this protects `KaynakAdi`, `Departman`, `Sicil`, `Email`, `Sektor`, `Mudurluk`, and `MasrafYeriKodu` display when Keycloak claims are incomplete or delayed.
- The sidebar user output and sidebar controls output must use `shiny::outputOptions(..., suspendWhenHidden = FALSE)` so hidden/sidebar render timing cannot leave the UI stuck on the initial “Yerel Kullanıcı” / “Departman bilgisi yok” skeleton.
- Do not query `Mudurluk` as a replacement for Department in the user panel. `Mudurluk` may be carried in config/profile data, but the visible Department line must continue to use the documented Department selection order.
- Department selection order is `Departman`, `departman`, then `department`; do not fall back to `Mudurluk`.
- Long Department text must remain safely truncated/wrapped with title tooltip behavior.
- Visible version must use `get_app_version_label()` from `R/config_version_history.R`; do not reintroduce `getOption("mergen.version", ...)` as the primary source for visible UI version.
- Protected tests: `test-sidebar-theme-sync-contract.R`, `test-sidebar-departman-contract.R`, `test-sidebar-instant-render-contract.R`, `test-sidebar-user-display-split-contract.R`, and `test-version-single-source-contract.R`.

### Brand title single-source contract

- Brand typography belongs in `www/css/brand_title.css`.
- Navbar `.brand-text`, loading `.alo-wordmark`, modern welcome title, and deep-space title/subtitle must stay aligned through this single CSS source.
- Keep the mixed-case product spelling `MERGEN Bilge`; do not force `BİLGE` through uppercase transforms.
- Keep local/system font stacks only; no external fonts or CDN.
- The `Bilge` emphasis uses the blue gradient direction established in the current implementation.
- Protected test: `test-brand-title-single-source-contract.R`.

### Tool contextual background animation contract

- Runtime/settings ownership: `R/module_tool_background_settings.R`, `www/js/tool_backgrounds_snippets.js`, `www/js/tool_backgrounds.js`, and `www/css/tool_backgrounds.css`.
- Quick action handlers are server-authoritative for `setToolBackgroundFamily`; client click handling may only be an early visual hint.
- New Chat must send clear/reset behavior so stale tool background families do not leak into new conversations.
- The lower-left heptagon cluster must stay decorative and non-blocking; no centered heptagon overlay.
- Snippets must use lane/busy-state logic to avoid overlap.
- Tool background snippets should share the welcome loading codestream renderer exposed from `www/js/app_loading_codestream.js`, including `window.MergenLoadingCodestream.buildItem`, tokenizers, and comment marks.
- Snippet family filters and fallback snippet catalogs belong in `www/js/tool_backgrounds_snippets.js`. Keep this file loaded immediately before `www/js/tool_backgrounds.js` in `R/config_ui_assets.R`.
- Do not move the snippet catalog or family filter functions back into `www/js/tool_backgrounds.js`; the split protects the app-owned frontend function budget while preserving the public `window.MergenToolBackgrounds` API.
- Preserve backward-compatible helper/class names such as `ensureLayer`, `ensureHeptagonLayer`, `ensureSnippetsHolder`, `buildHeptagonSvg`, `.tool-bg-heptagon`, and `.tool-bg-snippets` unless the tests are intentionally updated.
- Respect `prefers-reduced-motion`; decorative layers must not capture pointer events.
- Keep `www/js/tool_backgrounds.js` under the current app-owned JS budget noted by the tests.
- Protected tests: `test-tool-backgrounds-contract.R`, `test-frontend-maintainability-ratchet.R`, and `test-source-manifest-contract.R`.

### Tool-mode model lock and Excel/Coding deep-thinking contract

Current contract:

- `www/js/tools_model_lock.js` is the central browser-side model-lock coordinator for active tool modes. It detects active tool control panels and disables the chat `Model Değiştir` control plus the settings `Model Seçimi` dropdown with an explanatory tooltip.
- Individual tool scripts should call `window.MergenToolModelLock.refresh()` after showing or hiding their controls instead of implementing separate lock logic.
- `www/js/excel_coding_deep_thinking.js` owns the chat-side Deep Thinking toggle and low/high level dropdown for Excel Analysis and Coding Expert.
- Deep-thinking model resolution belongs server-side in `resolve_deep_thinking_model()` and `api_config$deep_thinking_models`.
- Deep-thinking model IDs are supplied by `EXCEL_DEEP_LOW_MODEL`, `EXCEL_DEEP_HIGH_MODEL`, `CODING_DEEP_LOW_MODEL`, and `CODING_DEEP_HIGH_MODEL`. They are runtime tool models, not normal user-facing model dropdown entries.
- If a deep-thinking model is not already listed in `local_model_capabilities`, it may be added with thinking-capable defaults, but existing explicit capability definitions must not be overwritten.
- Deep-thinking model IDs from environment variables may be absent from `api_config$local_model_endpoint_map`. That map is a named character vector, so missing-name checks must use `%in% names(endpoint_map)` and reads should use `endpoint_map[model_id]`; do not use `endpoint_map[[model_id]]` to test missing names.
- Missing deep-thinking endpoint mappings should be added with `endpoint_map[model_id] <- "primary"` while preserving the named character-vector shape. Do not convert the endpoint map to a list for this path.
- This guard prevents startup failures such as `subscript out of bounds` / `altindis sınırlar dışında` while `global.R` loads `R/config_api.R` through the source manifest, and is protected by `tests/testthat/test-api-model-config-refactor-contract.R`.
- Do not duplicate model-lock logic in `analysis_tools.js`, `image_tools.js`, `summarization_tools.js`, or future tool scripts.
- For ChartLab line/area charts, preserve the X-axis preference order: date column first, then categorical column, then numeric fallback. When categorical X values repeat, aggregate numeric Y values, defaulting to mean unless a specific aggregation is provided. Do not revert to the older behavior that selected numeric X too early and made line charts behave like scatter plots.

### Bilge Yolaç game behavior contract

The Bilge Yolaç mini-game should preserve the recent control and level-flow fixes:
- no unintended rightward team drift when no key is pressed,
- no automatic firing loop,
- SPACE is manual fire with cooldown,
- mouse click fires toward the clicked target,
- "Çıktıyı Temizle" / reset must reinitialize running state and animation frame state,
- level transitions must reset character x/y positions and movement values,
- demo AI must not move characters during victory or transition states,
- invalid or NaN level input must fall back safely.

Keep HUD, title, level, and victory text readable; do not shrink the recently enlarged game text sizes without a deliberate UI reason.

### Bilge Yolaç / Claude Code security regression contract

Bilge Yolaç security hardening is protected by focused tests. Do not weaken these contracts to fix a failing test.

Current contract:

- Direct existing-file download links must require explicit allowed roots. A caller that does not provide allowed roots must receive an empty link. The document-summary flow may still pass its explicit allowed roots so the real `dosya_aciklamalari.txt` download card continues to work.
- Prompt path-intent validation must continue to block traversal and forbidden absolute write targets before the Claude Code CLI starts.
- Prompt path-intent validation must not over-block ordinary prose. Extensionless, non-existent, path-like text that is not a real write target should remain allowed.
- Streaming/tool-use HTML must escape tool names, tool IDs, commands, paths, previews, and tool results before the browser inserts server-generated HTML.
- Synthetic tool-use entries must continue to improve visibility when generated files are detected from workdir diffs, without weakening download-root filtering.
- Generated-file and existing-file download behavior must preserve Turkish filenames, Turkish paths, UNC/network-share paths, selected-workdir scoping, and normal generated file cards.
- Keep the policy split intact. Do not move path-policy helpers back into `R/helpers_claude_code_security_policy.R`, and do not move downloads HTML helpers back into `R/helpers_claude_code_downloads.R`.

Protected by:

- `tests/testthat/test-claude-code-security-policy-contract.R`
- `tests/testthat/test-claude-code-document-download-link-encoding.R`
- `tests/testthat/test-claude-code-stream-html-safety-contract.R`
- `tests/testthat/test-claude-code-synthetic-tools-contract.R`
- `tests/testthat/test-claude-code-policy-split-contract.R`
- `tests/testthat/test-claude-code-run-lifecycle-contract.R`
- `tests/testthat/test-claude-code-runtime-workdir-contract.R`

Focused validation:

- `testthat::test_file("tests/testthat/test-claude-code-security-policy-contract.R")`
- `testthat::test_file("tests/testthat/test-claude-code-document-download-link-encoding.R")`
- `testthat::test_file("tests/testthat/test-claude-code-stream-html-safety-contract.R")`
- `testthat::test_file("tests/testthat/test-claude-code-synthetic-tools-contract.R")`
- `testthat::test_file("tests/testthat/test-claude-code-policy-split-contract.R")`


### Log redaction and secret-fixture contract

Logs must not expose raw secrets, bearer tokens, API keys, or secret-like test fixtures.

Current contract:

- `R/utils_log_redact.R` masks JWT-like values, Bearer/Basic authorization values, URL query secret parameters, generic key-value secrets such as `api_key`, `token`, `password`, and `client_secret`, and known Claude/API-related environment variable values.
- URL query redaction must preserve unrelated query parameters. For example, masking `token=...` must not remove `id=42`.
- Redaction tests must not commit realistic secret-looking literals such as real API-key prefixes. Use safe fake values and build sensitive-looking key names with runtime string construction when necessary so `test-secret-leak-contract.R` remains meaningful.
- Do not loosen `tests/testthat/test-secret-leak-contract.R` to make redaction tests pass. Fix the fixture instead.

Protected by:

- `tests/testthat/test-log-redact.R`
- `tests/testthat/test-secret-leak-contract.R`

Focused validation:

- `testthat::test_file("tests/testthat/test-log-redact.R")`
- `testthat::test_file("tests/testthat/test-secret-leak-contract.R")`

### File Manager table runtime refactor contract

The File Manager module is protected by the maintainability ratchet. Do not move table-rendering or attach-checkbox client binding code back into `R/module_file_manager.R` just to satisfy a selector test.

Current contract:

- `R/module_file_manager.R` owns the server-side File Manager flow, including the `input$attach_toggled` observer.
- `R/helpers_file_manager_table_runtime.R` owns the DT table runtime: `renderDT`, `drawCallback`, `change.attach`, `initAttachHandlerOnce`, and the call to `fm_register_attach_state_client_handler(session = session, ns = ns)`.
- `R/helpers_file_manager_attach_client.R` owns the `setAttachState` custom message handler.
- `R/config_source_manifest.R` must load `R/helpers_file_manager_table_runtime.R` after `R/helpers_file_manager_attach_client.R` and before `R/module_file_manager.R`.
- `R/bootstrap_source_manifest.R` must keep source-order rules that enforce the same boundary.
- `tests/testthat/test-frontend-selector-contract.R` must look for `drawCallback`, `change.attach`, and `fm_register_attach_state_client_handler(session = session, ns = ns)` in `R/helpers_file_manager_table_runtime.R`, not in `R/module_file_manager.R`.
- Do not raise the `R/module_file_manager.R` line/function budget in `tests/testthat/test-maintainability-ratchet.R` to hide growth. Split code into focused helpers instead.

Focused validation:

- `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")`
- `testthat::test_file("tests/testthat/test-frontend-selector-contract.R")`
- `testthat::test_file("tests/testthat/test-source-manifest-contract.R")`
- `testthat::test_file("tests/testthat/test-file-manager-state-runtime-contract.R")`

### Server core observer runtime refactor contract

The core interaction runtime has a protected second-level orchestration boundary. Do not move the extracted observer and File Manager runtime binding code back into `R/server_core_interaction_runtime.R`.

Current contract:

- `R/server_core_interaction_runtime.R` owns the high-level core interaction flow: resolving the core bundle, validating runtime state and identity, delegating core observer binding, and handing off to chat persistence.
- `R/server_core_observer_runtime.R` owns the extracted core observer runtime boundary: boot readiness, chat export binding, quick actions, settings observers, session timeout, File Manager runtime binding, chat UI observers, navigation observers, startup observers, AI Expert handlers, storage observers, file observers, and file-click observers.
- `R/server_core_observer_runtime.R` must call `serverBindFileManagerRuntime` through the injected `file_manager_runtime_fn` and pass `user_id_provider = identity$current_user_id_provider`.
- `R/server_core_observer_runtime.R` owns the session timeout activity selector contract: `user_input`, `send_stop_btn`, and `send_prompt_from_js`. Do not reintroduce legacy `send_btn` selector assumptions.
- `R/server_core_interaction_runtime.R` should delegate through `core_observer_runtime_fn = serverBindCoreObserverRuntime` and consume `core_observer_runtime$runtime_ctx`, `core_observer_runtime$file_runtime`, and `core_observer_runtime$file_manager_data`.
- `R/config_source_manifest.R` must load `R/server_core_observer_runtime.R` after `R/server_init_chat_runtime.R` and before `R/server_core_interaction_runtime.R`.
- Do not raise the maintainability ratchet to hide growth in this area. Keep `R/server_core_observer_runtime.R` small and focused; remove trivial wrapper functions before increasing budgets.
- Static contract tests must follow the new ownership boundary. If a string moved from `R/server_core_interaction_runtime.R` into `R/server_core_observer_runtime.R`, update the test to assert the new owner rather than moving runtime code back.

Protected by:

- `tests/testthat/test-server-core-observer-runtime-contract.R`
- `tests/testthat/test-file-manager-module-policy-wiring.R`
- `tests/testthat/test-frontend-selector-contract.R`
- `tests/testthat/test-production-contracts.R`
- `tests/testthat/test-source-manifest-contract.R`
- `tests/testthat/test-maintainability-ratchet.R`

Focused validation:

- `testthat::test_file("tests/testthat/test-server-core-observer-runtime-contract.R")`
- `testthat::test_file("tests/testthat/test-file-manager-module-policy-wiring.R")`
- `testthat::test_file("tests/testthat/test-frontend-selector-contract.R")`
- `testthat::test_file("tests/testthat/test-production-contracts.R")`
- `testthat::test_file("tests/testthat/test-source-manifest-contract.R")`
- `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")`
- `source("tests/scripts/parse_sanity_check.R", encoding = "UTF-8")`


### Admin Hata Analizi heatmap data boundary contract

The Admin Hata Analizi heatmap data preparation is a protected small-helper boundary. Do not move this pure transformation logic back into the main module just to make a chart change.

Current contract:

- `R/helpers_admin_hata_heatmap_data.R` owns `admin_ha_prepare_heatmap_data()`.
- The heatmap helper is pure data preparation only: no Shiny, no highcharter, no DB calls, no reactive state, no observers, and no file I/O.
- The heatmap helper receives the raw priority/category count frame plus category and priority label maps, then returns `kategoriler`, `oncelikler`, and `heatmap_data` for the existing highcharter renderer.
- `R/helpers_admin_hata_detail_runtime.R` owns the Admin Hata Analizi detail runtime boundary: detail table preparation/rendering support, priority/status badge HTML, attachment preview/download card helpers, attachment modal runtime, status update modal runtime, and `admin_ha_register_detail_runtime()`.
- `R/module_admin_hata_analizi.R` must stay focused on the Shiny module shell, reactive data providers, tab routing, and chart renderers. It should register the detail runtime through `admin_ha_register_detail_runtime()` instead of growing the dense detail table/modal/status observer block again.
- `R/helpers_admin_hata_analizi.R` still owns shared labels, query helpers, category counting, and tab UI helpers. Do not turn it into a mixed chart-rendering or modal-runtime module.
- `R/config_source_manifest.R` must load the files in this order: `R/helpers_admin_hata_analizi.R`, then `R/helpers_admin_hata_heatmap_data.R`, then `R/helpers_admin_hata_detail_runtime.R`, then `R/module_admin_hata_analizi.R`.
- Do not relax maintainability ratchet thresholds for this area. The current protected budgets are `R/module_admin_hata_analizi.R <= 640 lines / <= 7 functions` and `R/helpers_admin_hata_detail_runtime.R <= 380 lines / <= 12 functions`.
- Preserve Turkish labels and user-facing strings such as `Düşük`, `Orta`, `Yüksek`, `Kritik`, `Belirtilmedi`, `Arayüz / Tasarım`, `Çökme / Hata`, `Açık`, `İncelemede`, `Çözüldü`, `Kapandı`, and `Reddedildi`.
- R tests that access Turkish column names in this area should prefer parser-safe column lookup with `out[[column_name]]` and Unicode escape construction where necessary, instead of using non-ASCII `$` symbols such as `out$Kullanıcı` in parser-sensitive tests.

Protected by:

- `tests/testthat/test-admin-hata-analizi-refactor-contract.R`
- `tests/testthat/test-source-manifest-contract.R`
- `tests/testthat/test-global-source-manifest-contract.R`
- `tests/testthat/test-maintainability-ratchet.R`
- `tests/testthat/test-production-contracts.R`
- `tests/scripts/parse_sanity_check.R`

Focused validation after touching Admin Hata Analizi heatmap preparation, source order, or maintainability budgets:

- `source("tests/scripts/parse_sanity_check.R", encoding = "UTF-8")`
- `testthat::test_file("tests/testthat/test-admin-hata-analizi-refactor-contract.R")`
- `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")`
- `testthat::test_file("tests/testthat/test-source-manifest-contract.R")`

Manual validation after touching this area:

- Open the admin panel.
- Open Hata Analizi.
- Confirm Genel Bakış charts still render.
- Open Öncelik & Kategori.
- Confirm the priority chart, category treemap, and priority x category heatmap still render.
- Confirm heatmap labels remain Turkish and the priority ordering remains stable.
- Open Detaylı Bildirimler and confirm badges, attachment preview, and status update modal still work.

### Source manifest and MCP load-order contract

Runtime R files must be loaded through the explicit source manifest. Do not add hidden or dynamic sourcing to bypass dependency order.

Current MCP load order is protected and must remain:

- `R/helpers_mcp_context.R`
- `R/helpers_mcp_bootstrap.R`
- `R/helpers_mcp_table_readers.R`
- `R/helpers_mcp_file_resolver.R`
- `R/helpers_mcp_schema_helpers.R`
- `R/helpers_mcp_basic_tools.R`
- `R/helpers_mcp_chart_tools.R`
- `R/helpers_mcp_analyze_visualize.R`
- `R/helpers_mcp_tools.R`

Rules:

- `R/helpers_mcp_bootstrap.R` prepares the MCP helper environment and core path helpers only.
- `R/helpers_mcp_bootstrap.R` must not dynamically source downstream MCP helper files.
- Downstream MCP helper files must be declared explicitly in `R/config_source_manifest.R` in dependency order.
- `R/helpers_mcp_tools.R` must load after the downstream MCP helpers and should remain the final tool/router layer.
- Any test that manually sources MCP helper files must use the same order and keep `R/helpers_mcp_tools.R` last.
- Source-manifest rules must not be stale: every order-rule target must either be in the runtime manifest or in the explicit boot allowlist.
- `R/module_app_loading.R` is part of the startup path and must remain explicitly declared in `R/config_source_manifest.R` after `R/module_startup_screen.R` and before `R/module_quick_actions.R`. Do not dynamically source it or move it later in the manifest; `ui.R` depends on `appLoadingUI()` being available when `dashboardBody()` is built.
- Do not weaken `tests/testthat/test-source-manifest-contract.R`, `tests/testthat/test-global-source-manifest-contract.R`, or the MCP refactor tests to hide a load-order issue.

Focused validation after touching runtime source order or MCP helper files:

- `testthat::test_file("tests/testthat/test-source-manifest-contract.R")`
- `testthat::test_file("tests/testthat/test-global-source-manifest-contract.R")`
- `testthat::test_file("tests/testthat/test-mcp-bootstrap-refactor-contract.R")`
- `testthat::test_file("tests/testthat/test-mcp-table-readers-refactor-contract.R")`
- `testthat::test_file("tests/testthat/test-mcp-file-resolver-refactor-contract.R")`
- `testthat::test_file("tests/testthat/test-mcp-schema-helpers-refactor-contract.R")`
- `testthat::test_file("tests/testthat/test-mcp-basic-tools-refactor-contract.R")`
- `testthat::test_file("tests/testthat/test-mcp-chart-tools-refactor-contract.R")`
- `testthat::test_file("tests/testthat/test-mcp-analyze-visualize-refactor-contract.R")`
- `testthat::test_file("tests/testthat/test-mcp-excel-resolve.R")`
- `Sys.setenv(MERGEN_RUN_APP = "false", MERGEN_DISABLE_FUTURES = "true")`
- `source("app.R", encoding = "UTF-8")`
- `source("tests/testthat.R", encoding = "UTF-8")`

### Frontend asset manifest and maintainability ratchet contract

Frontend assets are now protected by an explicit maintainability report and ratchet. This contract is separate from the R maintainability score and must not be weakened to hide frontend growth.

Current contract:

- Runtime CSS and JS assets must continue to be loaded through `R/config_ui_assets.R` unless there is an intentionally documented page-local exception.
- Preserve asset load order. In particular, keep the existing ordering relationships around `www/js/encoding_utils.js`, `www/js/shiny_message_handlers.js`, `www/js/input_handlers.js`, `www/js/app_core.js`, `www/js/welcome_tooltip_manager.js`, `www/js/streaming_manager.js`, `www/js/claude_code.js`, `www/js/claude_code_streaming.js`, `www/js/music_manager.js`, and `www/js/audio_lifecycle_guard.js`. The current welcome-tooltip split depends on `www/js/app_core.js` loading before `www/js/welcome_tooltip_manager.js`, and `www/js/welcome_tooltip_manager.js` loading before `www/js/streaming_manager.js`.
- Do not introduce CDN dependencies, bundling, minification, runtime downloads, or hidden source loading to bypass frontend file-size pressure.
- `tests/scripts/frontend_maintainability_report.R` is a reporting script, not runtime code. It scans `www/js/*.js` and `www/css/*.css`, reads `R/config_ui_assets.R`, and reports line counts, byte counts, approximate JS function counts, event handler counts, Shiny custom message handler counts, manifest membership, app/vendor/allowlisted budget scope, duplicate CSS selectors, and forbidden legacy selector hits.
- `tests/testthat/test-frontend-maintainability-ratchet.R` protects the current frontend baseline. Its first baseline must respect the current real report values; after that, growth should fail until the relevant frontend code is split or refactored.
- App-owned frontend assets are budgeted separately from vendor/minified assets. Do not loosen app-owned thresholds merely because a third-party/minified file is large.
- New app-owned runtime CSS/JS files must not silently remain outside `R/config_ui_assets.R`. Add them to the manifest in the correct local/offline load order and update manifest/order tests when needed.
- Every manifest CSS/JS asset must also be assigned to exactly one frontend ownership zone in `R/config_ui_asset_zones.R`; intentionally unmanifested runtime/smoke assets must be owned through `ui_asset_unmanifested_ownership` with a reason. The zone map declares ownership only — load order stays single-owned by `R/config_ui_assets.R`.
- Keep `www/js/excel_coding_deep_thinking.js` loaded after `www/js/analysis_tools.js`, and keep `www/js/tools_model_lock.js` after the tool-control scripts it coordinates. Keep `www/css/tools_model_lock.css` in the CSS manifest. These files centralize Excel/Coding deep-thinking controls and tool-mode model-lock UI; do not move that behavior back into individual tool scripts.
- Forbidden legacy selectors such as `message_input`, `chat_content_wrapper`, and `#_content_container` must not be reintroduced.
- For large or mixed frontend files, prefer one focused local split at a time instead of adding more unrelated behavior to the same file. Good split candidates should preserve UX and cascade/order behavior.
- Welcome quick-action tooltip behavior for the Ana Söyleşi welcome screen lives in `www/js/welcome_tooltip_manager.js`, not in `www/js/app_core.js`. Do not move that tooltip/event-observer block back into `app_core.js`; the split keeps `app_core.js` focused on core app lifecycle, message observers, reconnection handling, and capability-message submission.
- `www/js/input_handlers.js`, `www/js/app_core.js`, `www/js/welcome_tooltip_manager.js`, `www/js/claude_code.js`, `www/js/claude_code_streaming.js`, `www/js/music_manager.js`, `www/js/audio_lifecycle_guard.js`, `www/css/claude_code.css`, and `www/css/claude_code_streaming.css` have file-specific budget protection. If one fails, inspect the report before changing thresholds. Current accepted frontend split baselines include `www/js/app_core.js` at 270 lines / 28 approximate functions / 8 event handlers / 0 Shiny handlers, and `www/js/welcome_tooltip_manager.js` at 260 lines / 22 approximate functions / 14 event handlers / 0 Shiny handlers.

Startup loading overlay contract:

- The startup loading overlay is implemented in `R/module_app_loading.R` and inserted early in `ui.R` through `appLoadingUI()`.
- The overlay CSS/JS source lives in dedicated `www` files (`www/css/app_loading.css`, `www/js/app_loading_snippets.js`, `www/js/app_loading_content.js`, `www/js/app_loading_codestream.js`, `www/js/app_loading.js`, `www/js/app_loading_media.js`). `R/module_app_loading.R` reads these files at UI build time and inlines them into the overlay markup, so `R/module_app_loading.R` stays small while the rendered overlay still ships its CSS/JS inline. The overlay must keep appearing before external app-owned CSS/JS assets finish loading; do not convert the inlined assets back into external `<link>`/`<script>` references.
- These overlay assets are intentionally kept out of the `R/config_ui_assets.R` manifest. They are allowlisted in `tests/scripts/frontend_maintainability_report.R` (`allowlisted_unmanifested_frontend_files`); keep that allowlist entry when touching these files.
- The overlay must remain SSO-aware: it watches the SSO config/overlay elements, Shiny connection/session events, and advances only forward through the startup stages.
- Preserve `mergen_settings.skip_intro` handling and the `html.mergen-skip-intro` behavior so the deep-space intro can be bypassed cleanly.
- The overlay progress must reflect REAL boot work, not a pseudo animation. The bar is driven only by real signals: server `bootReadinessCheckpoint` stages plus client-side `window.MergenAppLoading.reportMediaProgress(0..1)` during genuine media buffering. Do not reintroduce a synthetic/time-based trickle. The `file_index_ready` → `character_media_ready` band is intentionally the widest because full media buffering is the longest real operation.
- The safety timeout is a progress-aware STALL watchdog, not an absolute cap. It closes the overlay only after ~22 seconds of NO progress (no stage, checkpoint, or media-buffering advance), plus an absolute 180-second hard cap as a last resort. This preserves a 22-second safety semantic while allowing honest long media buffering to finish so that 100% truly means "everything is ready". Do not revert this to an absolute 22-second close, and keep `prefers-reduced-motion` handling.
- Character/welcome media preloading is single-source and authoritative in `www/js/app_loading_media.js`. It requests all persona videos, then fully warms the welcome cinematic background videos AND every persona's intro video into the browser HTTP cache, SEQUENTIALLY, waiting for `canplaythrough` and then removing each hidden `<video>` element (cache stays warm, no live decoders linger). It reports real progress through `window.MergenAppLoading.reportMediaProgress` and signals `character_media_preload_ready` only after the queue drains. Do not reintroduce a second competing `loadExploreAllCharVideos` / `character_media_preload_ready` handler (the old `www/js/explore_media_preload.js` was removed because two handlers raced); do not weaken it back to metadata-only warming, and do not add it to `R/config_ui_assets.R`.
- The Bilge Yolaç CLI auto connection test (`check_claude_code_status()` → `claude.cmd --version` via `processx` + `proc$wait`) is a synchronous subprocess and MUST stay off the boot-critical path. `R/helpers_claude_code_server_setup.R` defers it with `shinyjs::delay(...)` so it cannot block the boot event loop / freeze the progress bar; the connection badge stays in its "checking" state until then. Do not move this check back to an eager session-init `observe()`.
- Keep `window.MergenAppLoading` as the small external control surface for startup loading state (`finish`, `setStage`, `reportMediaProgress`).

### Startup media readiness and real-progress contract

- Startup loading progress must be driven by real boot readiness checkpoints and media buffering progress, not by synthetic/time-based trickle.
- The authoritative media preloader is `www/js/app_loading_media.js`.
- Do not reintroduce `www/js/explore_media_preload.js` or any second competing `character_media_preload_ready` / `loadExploreAllCharVideos` handler.
- Persona intro videos and welcome background videos must be buffered sequentially, wait for `canplaythrough`, report progress through `window.MergenAppLoading.reportMediaProgress`, and remove hidden video elements after warming so no persistent hidden decoder remains.
- The 22-second rule is a progress-aware stall watchdog; do not convert it back to an absolute 22-second close. Keep the 180-second absolute hard cap.
- The Bilge Yolaç CLI status check must stay deferred and off the boot-critical path because `claude.cmd --version` via `processx` / `proc$wait` can block the Shiny event loop.
- Overlay assets remain inline through `R/module_app_loading.R` and must not be moved into `R/config_ui_assets.R`.
- The corporate heptagon emblem, ASELSAN colour palette and the atmospheric code-stream layer are part of the intended look; do not strip them to simplify the file.
- Do not move this startup overlay into normal frontend asset manifests, CDN assets, bundled files, or delayed scripts.

### Accessibility contract for main chat controls and toast notifications

- Icon-only controls in the main chat input area must keep accessible names through `aria-label`.
- Decorative icons must remain hidden from screen readers with `aria-hidden`.
- Toast notifications must remain live regions using `role` / `aria-live`, and icon-only close controls must keep `aria-label`.
- The send/stop button must update both `title` and `aria-label` when switching between send and stop modes.
- Protect this with `tests/testthat/test-accessibility-contract.R`.
- Do not remove existing ids/classes or dark-theme behavior when changing accessibility attributes.

Protected by:

- `tests/scripts/frontend_maintainability_report.R`
- `tests/testthat/test-frontend-maintainability-ratchet.R`
- `tests/testthat/test-ui-asset-manifest-contract.R`
- `tests/testthat/test-frontend-selector-contract.R`
- `tests/testthat/test-maintainability-ratchet.R`

Focused validation after touching frontend JS/CSS, frontend selectors, or `R/config_ui_assets.R`:

- `source("tests/scripts/frontend_maintainability_report.R", encoding = "UTF-8")`
- `testthat::test_file("tests/testthat/test-frontend-maintainability-ratchet.R")`
- `testthat::test_file("tests/testthat/test-ui-asset-manifest-contract.R")`
- `testthat::test_file("tests/testthat/test-frontend-selector-contract.R")`
- `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")`

Manual UI validation after frontend JS/CSS changes:

- Hard refresh the browser with Ctrl+F5 or Ctrl+Shift+R.

Manual validation after startup or intro/welcome changes:
- Start the app with SSO disabled and confirm the loading overlay appears immediately, advances, and dismisses into the welcome screen.
- Start the app with SSO enabled on the VM and confirm the overlay stays visible through authentication and session initialization, then dismisses without leaving a blank or frozen screen.
- Test with `skip_intro=true` in `mergen_settings` and confirm the deep-space layer is bypassed cleanly.
- Confirm the welcome greeting starts only after the welcome screen is visible and is not lost during the deep-space-to-welcome transition.
- Open the cinematic flow and Integrated mode; confirm the default/selected character intro video starts without the previous noticeable delay.
- Open Görsel Galerisi and refresh/switch back to it; confirm there is no unnecessary flicker and no repeated refresh toast.
- Open Ana Söyleşi.
- Verify textarea auto-height, Enter send, Shift+Enter newline, Escape clear, send/stop mode, and file drag/drop.
- Click each quick action and verify the expected tool control panel appears and disappears.
- Open Bilge Yolaç and run a simple prompt; confirm live streaming still works.
- Validate TTS, STT, and background music lifecycle.
- Open Görsel Galerisi, Dosya Yönetimi, Kayıtlı Söyleşiler, and Yenilikler.
- Check the browser console for JavaScript errors.

### 1C) File lifecycle and File Manager boundary contract

Uploaded file lifecycle is a protected boundary. Do not trade security or user isolation for convenience.

Current contract:

- Storage names and display names are separate. Storage-prefixed filenames may exist on disk, but File Manager must show the original user-facing name.
- Turkish original filenames must remain legible in the UI and logs after upload, browser refresh, and full app restart.
- File Manager refresh must use the live current user provider at refresh time. In SSO mode, placeholder identities such as `0`, `unknown`, or not-yet-ready authentication state must not trigger persistent file refresh or wipe an existing valid table.
- File Manager restart/refresh restoration must preserve user-facing display names, including Turkish filenames such as `Türkçe_çalışma_özeti_İstanbul.pdf`. Storage-prefixed physical names must not leak into the table.
- The lightweight live-provider smoke test must stay close to the real helper seams and must not require the full Shiny app, DB, browser, or SSO server to launch.
- File Manager display names must pass through the central display-name helpers. Do not add local storage-prefix stripping logic in table rendering, MCP resolution, or summarization code.
- The persistent JSON index remains the first source of truth for a user bucket.
- If the index is missing, empty, or partially stale, same-user filesystem fallback is allowed only inside that same user's upload/MCP directories.
- Same-user filesystem fallback must not reintroduce duplicate File Manager rows. When index and filesystem discovery both see the same logical file, the File Manager table must keep one row.
- Cross-user and cross-bucket lookup must remain disabled by default. Any migration/admin opt-in must be explicit and must not leak into normal runtime flows.
- MCP file tools must not resolve arbitrary absolute paths from normal user arguments. Users should refer to selected file names or file tokens, not raw filesystem paths.
- Summarization mode must use only files selected for Model Bağlamı and only supported document extensions. Excel files must be excluded from summarization without removing or corrupting File Manager state.
- Excel files remain valid for MCP Excel analysis when selected through the normal File Manager/MCP flow.
- The upload size policy must remain centralized at getOption("mergen.upload_max_mb", 25L). Do not introduce another hard-coded upload limit.
- Keep file lifecycle helpers small. If registry/listing logic grows, split focused helpers into a small sourced file rather than making R/config_file_store_registry.R function-heavy.
- Any new runtime helper file must be added to R/config_source_manifest.R in dependency order and covered by manifest/order tests.
- Isolated File Store tests must load the refactored public API through `tests/testthat/helper_load_file_store.R`.
- That helper must source `R/helpers_files_path.R` before the split `config_file_store_*` files so `normalize_for_path_compare` is available.
- Do not re-inline these helper sources directly into individual tests.
- Do not re-merge `R/config_file_store_index_lock.R`, `R/config_file_store_index_mutation.R`, `R/config_file_store_listing_helpers.R`, and `R/config_file_store_registry.R` back into `R/config_file_store.R`. The index lock helper (`.file_store_with_index_lock`, stale-lock breaking, lock owner marker) lives in `R/config_file_store_index_lock.R`; do not move it back into the mutation file.

File Store and Health Dashboard Guardrails:

- Do not bypass `atomic_write_json()` for File Store index writes; index persistence must use atomic UTF-8 JSON writes to reduce partial or corrupt `index.json` risk.
- Keep `atomic_write_text()` binary-safe for UTF-8 content and preserve the `file.rename()` to `file.copy()` fallback behavior for cross-filesystem or locked-file cases.
- Do not let tests write File Store index/upload/MCP data to real repo, user, or network paths; force temporary roots for `MERGEN_FILES_ROOT`, `MERGEN_UPLOADS_DIR`, `MERGEN_INDEX_PATH`, `MERGEN_MCP_BASE_DIR`, and `MCP_FILES_BASE`.
- Persistence smoke coverage must keep supported upload display names stable across repeated listings and must not expose timestamp/hash storage names.
- Keep health path copyability strict: only an existing file or existing directory is copyable, not a missing child path whose parent exists.
- Keep base health status/value/path formatting in `R/helpers_health_formatters.R`, keep the health checks table UI builder in `R/helpers_health_table.R`, and preserve source order as formatters first, then table builder, then downstream health modules.
- Preserve maintainability ratchet constraints: no new 800+ line runtime files, no new 25+ function runtime files, and avoid adding anonymous function handlers to `R/helpers_health_formatters.R` unless absolutely necessary.

Key files:

- R/config_file_store.R
- R/config_file_store_index_lock.R
- R/config_file_store_index_mutation.R
- R/config_file_store_listing_helpers.R
- R/config_file_store_registry.R
- R/helpers_file_manager_table.R
- R/helpers_file_manager_state_runtime.R
- R/helpers_mcp_file_resolver.R
- R/module_summarization.R
- R/config_source_manifest.R

Protected by:

- tests/testthat/test-file-lifecycle-hardening-contract.R
- tests/testthat/test-file-manager-display-name-contract.R
- tests/testthat/test-file-manager-live-provider-refresh-smoke.R
- tests/scripts/run_fragile_flow_manual_preflight.R
- tests/testthat/test-fragile-flow-manual-preflight-contract.R
- tests/testthat/test-file-resolution-security-contract.R
- tests/testthat/test-resolve-uploaded-file.R
- tests/testthat/test-mcp-excel-resolve.R
- tests/testthat/test-file-store-index.R
- tests/testthat/test-e2e-file-context-regression.R
- tests/testthat/test-upload-size-policy.R
- tests/testthat/test-upload-validator.R
- tests/testthat/test-config-file-store-registry-refactor-contract.R
- tests/testthat/test-global-source-manifest-contract.R
- tests/testthat/test-maintainability-ratchet.R

Focused validation after touching file lifecycle, File Manager, MCP file resolution, summarization file selection, upload limits, or source-manifest order:

- testthat::test_file("tests/testthat/test-file-lifecycle-hardening-contract.R")
- testthat::test_file("tests/testthat/test-file-manager-display-name-contract.R")
- testthat::test_file("tests/testthat/test-file-manager-live-provider-refresh-smoke.R")
- testthat::test_file("tests/testthat/test-fragile-flow-manual-preflight-contract.R")
- testthat::test_file("tests/testthat/test-saved-chat-reload-no-tts-contract.R")
- testthat::test_file("tests/testthat/test-file-store-persistence-roundtrip-smoke.R")
- testthat::test_file("tests/testthat/test-browser-smoke-harness-contract.R")
- source("tests/scripts/run_fragile_flow_manual_preflight.R", encoding = "UTF-8")
- testthat::test_file("tests/testthat/test-file-resolution-security-contract.R")
- testthat::test_file("tests/testthat/test-resolve-uploaded-file.R")
- testthat::test_file("tests/testthat/test-mcp-excel-resolve.R")
- testthat::test_file("tests/testthat/test-file-store-index.R")
- testthat::test_file("tests/testthat/test-e2e-file-context-regression.R")
- testthat::test_file("tests/testthat/test-upload-size-policy.R")
- testthat::test_file("tests/testthat/test-upload-validator.R")
- testthat::test_file("tests/testthat/test-config-file-store-registry-refactor-contract.R")
- testthat::test_file("tests/testthat/test-global-source-manifest-contract.R")
- testthat::test_file("tests/testthat/test-maintainability-ratchet.R")

Manual validation after file lifecycle changes:

- Upload PDF, DOCX, TXT, CSV, and XLSX locally.
- Upload a Turkish filename such as Türkçe_çalışma_özeti_İstanbul.pdf.
- Verify original display names before browser refresh.
- Refresh the browser and verify the files still appear once.
- Fully restart the app and verify the files still appear once.
- Confirm storage-prefixed disk names do not leak into the File Manager table.
- Select Model Bağlamı and run summarization with a supported document.
- Select an Excel file in summarization mode and confirm it is excluded with a proper warning while File Manager state remains intact.
- Run MCP Excel analysis with an XLSX selected through File Manager.
- Confirm no cross-user files appear.
- Attempt an absolute-path file reference and confirm it is rejected or ignored without arbitrary file access.
- Inspect logs for readable Turkish filenames.

### Fragile-flow manual preflight

Some user flows require a real local or Windows VM/SSO browser session because they depend on authentication, browser media policy, microphone permission, TTS playback, background music, file persistence, and Turkish filename rendering. Do not add a heavy browser automation dependency just to cover these flows unless there is a separate approved decision.

Use `tests/scripts/run_fragile_flow_manual_preflight.R` for a repeatable manual checklist. The script does not launch the app. It records PASS/FAIL/SKIP evidence as UTF-8 CSV under `logs/`.

The checklist covers:

- local `SSO_ENABLED=FALSE` streaming send and stop behavior,
- local PDF/DOCX/TXT/CSV/XLSX upload, browser refresh, and full app restart visibility,
- saved chat reload without autoplaying old TTS,
- Windows VM/SSO authenticated identity and user-scoped recent chats/history/saved chats/gallery rows,
- Turkish filename persistence for `Türkçe_çalışma_özeti_İstanbul.pdf`,
- TTS/STT/background music single-playback and duck/unduck recovery,
- optional `/smoke/ux-smoke.html` browser smoke confirmation.

Protected by:

- tests/scripts/run_fragile_flow_manual_preflight.R
- tests/testthat/test-fragile-flow-manual-preflight-contract.R
- www/smoke/ux-smoke.html
- tests/testthat/test-ux-smoke-browser-contract.R
- tests/testthat/test-browser-smoke-harness-contract.R
- tests/testthat/test-saved-chat-reload-no-tts-contract.R

Additional lightweight smoke tests now complement the manual preflight without launching the full app: `test-sso-session-identity-smoke.R` (SSO identity smoke), `test-file-manager-live-provider-refresh-smoke.R` (File Manager live-provider refresh smoke), `test-file-store-persistence-roundtrip-smoke.R` (File Store persistence roundtrip smoke), `test-streaming-abort-lifecycle-smoke.R` (streaming abort lifecycle smoke), `test-saved-chat-reload-no-tts-contract.R` (saved-chat reload no-TTS contract + lightweight runtime smoke), `test-audio-lifecycle-owner-smoke.R` (audio lifecycle owner smoke), `test-true-streaming-reset-ui-contract.R` (server/client true-streaming reset/finalize contract without launching full app, DB, LLM, or browser), `test-chat-input-stop-button-smoke.R` (chat input stop-button observer smoke), and `test-ux-smoke-browser-contract.R` (browser UX smoke contract). These tests do not replace the Windows VM/manual browser checks.

- Browser-side streaming lifecycle is also protected without launching a real LLM request. `www/js/streaming_manager.js` exposes the smoke-only `window.MergenStreamingSmoke` seam, and `www/smoke/ux-smoke.html` drives a synthetic init → delta → stale delta rejection → finalize sequence.
- The real chat input stop-button observer path is protected by `tests/testthat/test-chat-input-stop-button-smoke.R`. Keep `input$send_stop_btn` behavior aligned with the streaming cleanup contract: `stop_generation` must become `TRUE`, `active_request_id` must move to a `cancelled_*` value, `reset_chat_state` must clear `values$is_sending` and `values$typing`, and the stop toast should still be emitted. This test must remain lightweight and must not require the full app, DB, browser, LLM, TTS, STT, or file-upload pipeline.
- True-streaming stop/cancel regressions are also protected by `tests/testthat/test-true-streaming-reset-ui-contract.R`. Keep server-side cleanup, stop-file signaling, `ctx$reset_chat_state_fn()`, `finalizeStreamingMessage`, request-id propagation, stale delta rejection, finalized state, action-button restore, and pending followup cleanup aligned. Do not make this path depend on a live LLM request for basic contract coverage.
- Do not remove or rename `window.MergenStreamingSmoke`, `handleInitStreamingMessage`, `handleStreamingDelta`, `handleStreamingUpdate`, or `handleFinalizeStreamingMessage` unless the browser smoke and contract tests are updated in the same change.
- Saved-chat reload must remain a render-only historical path. `R/server_observers_storage.R` must not call TTS synthesis or send `playAudioMessage` from the `load_chat_from_storage` observer; this contract is protected by static checks plus a lightweight `shiny::testServer` runtime smoke.
- The manual preflight script may use `MERGEN_PREFLIGHT_ASSUME_STATUS=PASS` only as an explicit operator shortcut after the steps have already been manually verified. It should not be treated as automated proof that the browser or VM was actually exercised.

`tests/testthat/test-ux-smoke-browser-contract.R` protects the browser smoke page itself. It intentionally matches ASCII structural anchors rather than Turkish assertion sentences so Windows/Turkish-locale byte matching cannot fail while the real `/smoke/ux-smoke.html` runner still passes.

- Browser-smoke contract tests should prefer stable implementation anchors such as function names, Shiny input names, and state predicates over exact Turkish UI/assertion text. Exact Turkish text is acceptable in the real smoke page, but the static contract must not depend on byte-identical Turkish strings on Windows VM sessions.
- For streaming browser smoke coverage, prefer stable anchors such as `window.MergenStreamingSmoke`, handler function names, request-id stale checks, finalized state, and action-button restore behavior. Do not make the static contract depend on exact Turkish assertion sentences from the smoke page.

Focused validation:

- testthat::test_file("tests/testthat/test-fragile-flow-manual-preflight-contract.R")
- testthat::test_file("tests/testthat/test-saved-chat-reload-no-tts-contract.R")
- testthat::test_file("tests/testthat/test-browser-smoke-harness-contract.R")
- testthat::test_file("tests/testthat/test-ux-smoke-browser-contract.R")
- testthat::test_file("tests/testthat/test-chat-input-stop-button-smoke.R")
- source("tests/scripts/run_fragile_flow_manual_preflight.R", encoding = "UTF-8")

### Bilge Yolaç document download and stream-poll contract

Current contract:

- `R/helpers_claude_code_existing_file_link.R` owns the direct existing-file download card for files that are already created in the user-selected/upload folder.
- The document-summary flow must not depend on copying `dosya_aciklamalari.txt` into `bilge_yolac_downloads` before showing a link. If the file already exists in the allowed user folder, create a direct Shiny resource link to that existing file.
- Do not reintroduce the old fallback message `İndirme kartı hazırlanamadı` as the normal success path for document summaries.
- `R/module_claude_code_stream_poll.R` owns the live stream polling, stop observer, and prompt-submit observer extracted from `R/module_claude_code.R`.
- Do not move the stream polling block back into `R/module_claude_code.R`; the maintainability ratchet expects the module to stay below the near-limit runtime budget.
- Any new helper file in this area must be added to `R/config_source_manifest.R` in dependency order.

### Tool-use visibility and stream-json compatibility

Current contract:

- Live `cc-stream-chunk` tool-use events are the preferred display path, but stream completion must also send `finalToolUsesHtml` through `cc-stream-end`. The client may use this final HTML to replace or complete a stale live tool-use section.
- If there are no final tool uses, the client should remove misleading empty or zero-count tool sections instead of leaving `ARAÇ KULLANIMLARI (0)` visible.
- When generated/downloadable files are detected but the on-prem proxy does not emit complete Anthropic `tool_use` blocks, the server may synthesize `Write` tool-use entries from generated-file paths so the UI reflects real file creation.
- Synthetic tool uses must be additive and path-deduplicated. If an existing real tool_use already covers a generated file path through `file_path`, `path`, `new_file`, or `file`, do not create a duplicate synthetic `Write` entry for the same file.
- Keep `[TOOL_USE_DEBUG]` logging around raw stream-json line counts, parsed tool-use counts, event distributions, final HTML length, and synthetic additions. These logs are the field diagnostic path for on-prem proxy format differences.
- `www/js/claude_code_streaming.js` must keep `shellVisible` explicitly declared in the streaming IIFE before it is read or toggled. In strict mode, an undeclared variable can break live tool block insertion.
- Immediate UI feedback for Bilge Yolaç refresh/run/download actions is protected UX. Do not remove the refresh spinner/loading placeholder, run “preparing” state, or generated-file download “preparing” state unless an equivalent replacement is provided.

### Stream-json parser compatibility

Current contract:

- `parse_claude_code_json_output()` and `parse_streaming_chunk()` must read assistant content from `message.content` first and fall back to `content`.
- Assistant/user `content` may arrive either as a list/array or as a single object. Normalize the single-object form before iterating.
- Assistant `tool_use` blocks and user `tool_result` blocks must be captured even when granular `content_block_start` events are missing.
- If `stream_event` / `content_block_delta` has already accumulated assistant text, aggregate assistant text blocks must not be appended again. This prevents duplicate AI answer text while still preserving tool_use parsing.
- Tool result text should be attached back to the related tool_use result when possible.

### Windows VM, UNC, and runtime workdir compatibility

Current contract:

- UNC and network-share paths must be preserved in UNC-like form; do not let `normalizePath()` silently convert them into mapped drive-letter paths.
- Backslash normalization must handle both the leading UNC marker and single backslashes between path segments.
- Runtime workdirs may be reused for follow-up questions in the same conversation when they refer to the same source. This preserves Claude CLI session/resume metadata and avoids “No conversation found with session ID” regressions.
- UNC directory existence and listing on the Windows VM may require relaxed checks or `fs` fallback behavior when base R returns false negatives.
- Prompt path-intent validation must still reject real unsafe absolute/outside-root paths, but should not block accidental non-existent, extensionless typo tokens as if they were real file paths.

Protected by:

- `tests/testthat/test-claude-code-document-download-link-encoding.R`
- `tests/testthat/test-claude-code-run-lifecycle-contract.R`
- `tests/testthat/test-claude-code-synthetic-tools-contract.R`
- `tests/testthat/test-claude-code-process-refactor-contract.R`
- `tests/testthat/test-claude-code-runtime-workdir-contract.R`
- `tests/testthat/test-claude-code-security-policy-contract.R`
- `tests/testthat/test-claude-code-policy-split-contract.R`
- `tests/testthat/test-maintainability-ratchet.R`
- `tests/testthat/test-global-source-manifest-contract.R`

Focused validation:

- `testthat::test_file("tests/testthat/test-claude-code-document-download-link-encoding.R")`
- `testthat::test_file("tests/testthat/test-claude-code-run-lifecycle-contract.R")`
- `testthat::test_file("tests/testthat/test-claude-code-synthetic-tools-contract.R")`
- `testthat::test_file("tests/testthat/test-claude-code-process-refactor-contract.R")`
- `testthat::test_file("tests/testthat/test-claude-code-runtime-workdir-contract.R")`
- `testthat::test_file("tests/testthat/test-claude-code-security-policy-contract.R")`
- `testthat::test_file("tests/testthat/test-claude-code-policy-split-contract.R")`
- `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")`
- `testthat::test_file("tests/testthat/test-global-source-manifest-contract.R")`

### 1A) Keep new code identifiers ASCII-safe when practical
Preserve Turkish text integrity in user-facing strings, docs, comments, DB text, JSON text, and rendered UI. However, for Windows VM parser robustness, **new code identifiers** should be ASCII-only where practical (variable/helper names, unquoted `data.frame(...)` column names, `$field_name` accessors, and similar code symbols that can become mojibake-sensitive). This is **not** permission to Latinize visible product text; it applies only to code symbols/identifiers.

### 2) Comments added to code must be in Turkish
If you add comments in code, write them in Turkish.

### 2A) Character / persona system contract

The application uses a modern, corporate-safe, fictional Turkish AI persona system. It must NOT use mythological, religious, Ottoman, or pre-Islamic framing.

The five canonical personas and their canonical lowercase ASCII ids are:

- `emre` — Emre Onat — Ana Asistan (default, balanced assistant)
- `selin` — Selin Sezgin — Yapıcı Uzman (constructive expert)
- `deniz` — Deniz Özgün — Stratejist (strategist)
- `can` — Can Yalın — Eleştirel Eş (critical partner / verifier)
- `ipek` — İpek Duru — Rehber (guide / teacher)

Rules:

- The single source of truth for persona identity is `R/config_characters.R`. New modules must not write their own character-name or folder switch; use `get_characters_data()`, `get_character_record()`, `get_character_asset_paths()`, and `normalize_character_id()`.
- The default selected persona is `emre`. No startup, settings, music, video, or game code may default to `mergen` anymore.
- Old mythological character ids (`mergen`, `ulgen`, `ülgen`, `kayra`, `erlik`, `umay`, `umay_ana`, `umay ana`) are supported ONLY at the `normalize_character_id()` boundary, so old saved user preferences migrate cleanly: `mergen→emre`, `ulgen→selin`, `kayra→deniz`, `erlik→can`, `umay/umay_ana→ipek`.
- "MERGEN Bilge" is the product/brand name and must be preserved. `MERGEN` is allowed only as the product name; it is not a selectable persona.
- Do not rename technical keys such as `mergen_settings`, `mergen_uploads`, `MergenAudioLifecycle`, the `mergen-skip-intro` class, log prefixes, or product-level helper namespaces.
- Persona asset folders use the canonical ASCII ids: `www/characters/avatar/<id>/`, `www/characters/resim/<id>/`, `www/characters/video/<id>/{intro,loop,select}/`, `www/music/Karakter/<id>/`, `www/assets/bilge_yolac/worlds/<id>/`, and `www/assets/bilge_yolac/projectiles/<id>/`.
- The Bilge Yolaç game layer must use the new persona ids, modern ability/projectile types (`cozum_dalgasi`, `sinyal_taramasi`, `rota_projesi`, `dogrulama_isini`, `rehber_halkasi`), and modern world packages; it must not reintroduce mythological labels.

### 3) Prefer surgical changes
Do not perform wide refactors unless the user explicitly asks for them.

Preferred style:

- smallest safe patch,
- minimal file churn,
- minimal new abstractions,
- preserve existing naming and structure.

### 3B) Preserve UX while improving architecture and security

Maintainability, source-manifest, frontend load-order, encoding, security, and Bilge Yolaç hardening work must not silently reduce the current user experience.

The following UX behaviors are protected contracts:

- The Ana Söyleşi welcome screen must keep the cinematic video, neural animation, personal greeting text, quick action cards, no-top-gap layout, and recent chats area.
- Welcome video/neural/greeting components must restart safely after reconnects, new-chat returns, tab changes, and DOM redraws.
- Quick action cards must select the correct model and tool mode, show the intro message, and avoid duplicate events on rapid double click.
- Background music must keep one active track source at a time. Character music must not overlap theme music.
- TTS must duck music while speaking and restore music after playback or failure.
- TTS `Audio` objects must be marked with the `MergenAudioLifecycle` owner `tts` before playback, so document-level audio play/pause handlers do not treat TTS as generic `external_audio`.
- TTS/STT/background music lifecycle uses owner-based ducking; browser smoke validates overlapping owners so releasing TTS while STT is still active must not restore music early, and final cleanup must leave no active duck owners.
- Background music must keep a single active `Audio` instance. `MusicManager._playTrack()` must stop the current audio before creating a new `Audio(src)`, stale audio events must be guarded with `self._audio !== audio`, and stale playlist responses must be rejected through `_pendingRequestId`.
- Do not collapse this owner model into a single boolean duck flag.
- STT must pause/duck music when the modal opens and restore music on cancel, submit, init failure, microphone-denied paths, and unexpected Bootstrap modal hidden/close paths.
- AI Expert audio must duck music while speaking and must release its duck owner if playback fails or the browser rejects autoplay; subtitle fallback behavior must remain intact.
- TTS autoplay must be limited to new AI responses. Loading saved or old chats must not auto-play historical answers.
- The stop button must stop generation and also clean active TTS playback.
- True streaming abort/cancel decisions must stay delegated to `mergen_stream_abort_cleanup_plan()` in `R/helpers_streaming_abort_lifecycle.R`; do not move this logic back into an untestable inline branch.
- True streaming poll-loop decisions must stay delegated to the pure helpers in `R/helpers_streaming_poll_lifecycle.R`: `mergen_stream_classify_poll_lines()` (JSONL delta/reasoning/debug classification), `mergen_stream_reasoning_recovery_plan()` (worker-return reasoning recovery so `MB_Messages.ReasoningContent` does not stay NULL when reasoning arrives only in the final chunk), `mergen_stream_poll_interval_ms()`, and `mergen_stream_persist_delay()`. Do not re-inline this logic into `R/server_handler_true_streaming.R`; the boundary is protected by `tests/testthat/test-streaming-poll-lifecycle-contract.R` and `tests/testthat/test-streaming-poll-lifecycle-behavior.R`.
- Reasoning/thinking panels must not break chat scroll, must appear for thinking-capable flows, and must clean up safely after completion or stop.

Implementation constraints:

- Do not remove visual polish to simplify code.
- Do not remove welcome animations.
- Do not remove quick action intro messages.
- Do not remove music, TTS, or STT to avoid race conditions.
- Do not replace targeted guards with broad UI rewrites unless explicitly requested.
- Prefer small defensive JS/R guards and lightweight contract tests.
- No CDN or internet dependency may be added for these UX protections.

The current guardrail layer includes:

- `tests/testthat/test-ux-regression-guardrails.R`
- `tests/testthat/test-e2e-boot-welcome-regression.R`
- `tests/testthat/test-frontend-selector-contract.R`
- `tests/testthat/test-e2e-media-audio-state-regression.R`
- `tests/testthat/test-quick-action-intro.R`
- `tests/testthat/test-quick-action-routing.R`
- `tests/testthat/test-ui-asset-manifest-contract.R`
- `tests/testthat/test-browser-smoke-harness-contract.R`
- `tests/testthat/test-sso-session-identity-smoke.R`
- `tests/testthat/test-streaming-abort-lifecycle-smoke.R`
- `tests/testthat/test-audio-lifecycle-owner-smoke.R`
- `tests/testthat/test-true-streaming-reset-ui-contract.R`

Focused validation after UX-sensitive refactors:

- `testthat::test_file("tests/testthat/test-ux-regression-guardrails.R")`
- `testthat::test_file("tests/testthat/test-e2e-boot-welcome-regression.R")`
- `testthat::test_file("tests/testthat/test-frontend-selector-contract.R")`
- `testthat::test_file("tests/testthat/test-e2e-media-audio-state-regression.R")`
- `testthat::test_file("tests/testthat/test-quick-action-intro.R")`
- `testthat::test_file("tests/testthat/test-quick-action-routing.R")`
- `testthat::test_file("tests/testthat/test-ui-asset-manifest-contract.R")`
- `testthat::test_file("tests/testthat/test-browser-smoke-harness-contract.R")`
- `testthat::test_file("tests/testthat/test-sso-session-identity-smoke.R")`
- `testthat::test_file("tests/testthat/test-streaming-abort-lifecycle-smoke.R")`
- `testthat::test_file("tests/testthat/test-audio-lifecycle-owner-smoke.R")`
- `testthat::test_file("tests/testthat/test-true-streaming-reset-ui-contract.R")`
- `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")`

Browser-level smoke validation:

- The repo includes a lightweight browser smoke harness at `www/smoke/ux-smoke.html`.
- The matching contract test is `tests/testthat/test-browser-smoke-harness-contract.R`; it must read `www/smoke/ux-smoke.html`, not an old root-level `www/ux-smoke.html` path.
- The optional local opener is `tests/scripts/open_ux_smoke.R`.
- The smoke harness is intentionally repo-local and dependency-free. Do not add `shinytest2`, Playwright, Chromote, Selenium, Node, npm, or another heavy browser-test dependency for this layer unless explicitly requested.
- Do not add `www/smoke/ux-smoke.html` to `R/config_ui_assets.R`; it is not part of the normal production UI asset bundle and should only run when opened directly.
- For local validation, start the app, then run:
  - `Sys.setenv(MERGEN_SMOKE_BASE_URL = "http://127.0.0.1:3838")`
  - `source("tests/scripts/open_ux_smoke.R", encoding = "UTF-8")`
- On production or SSO/Keycloak deployments, open the smoke page through the same app origin, for example `/bilge/smoke/ux-smoke.html`. Do not point the iframe through a cross-origin Keycloak/login route; browser security will block DOM access and the smoke will correctly fail with a routing/origin diagnostic.
- The expected browser result is `UX_SMOKE_DONE:PASS`.
- The default smoke is VM-safe and single-session: it loads the app once, prepares smoke-only `localStorage` to skip the human Deep Space intro, validates the welcome screen, runs the synthetic reasoning fixture before real quick-action/chat side effects, then validates quick action, chat input, media, saved-chat no-autoplay, and console sanity.
- The smoke must restore the original browser storage values after it finishes.
- The smoke validates real browser behavior for welcome boot, no-top-gap layout, quick-action double-click single-dispatch, Enter/Shift+Enter/stop-mode input behavior, auto-scroll state, TTS/STT/music duck and restore behavior, STT hidden-modal cleanup, AI Expert autoplay rejection music restore, saved-chat no historical TTS autoplay, reasoning panel lifecycle, and blocking console errors.
- Quick-action intro-message visibility is intentionally non-blocking in the VM/browser smoke because SSO routing and timing can make that visual check brittle. Deterministic focused tests remain the source of truth for quick-action intro, model, and tool-mode contracts.
- When extracting snippets from UTF-8 JavaScript files in R tests, do not mix byte-position matching such as `useBytes = TRUE` with character-position substring functions such as `substr()`. Turkish multibyte text before the target can shift byte offsets and create false test failures. Use character-position matching or consistently byte-safe extraction.
- Known `Shiny.setInputValue` / `Shiny.setinputValue` timing noise may be treated as warning-only in the smoke harness, but do not broadly ignore unrelated console errors.
- If this smoke test fails because of Keycloak redirection, iframe routing, Deep Space intro timing, or production proxy behavior, do not remove UX features to make it pass. Prefer a small defensive adjustment inside `www/smoke/ux-smoke.html` while preserving focused test coverage.

Manual validation after touching welcome, quick actions, media, TTS, STT, stop-button, streaming, or reasoning code:

- Fresh local start: confirm full welcome layout, video, neural animation, greeting text, quick action cards, and recent chats.
- Test every quick action once: confirm model/tool switch, intro message, and no duplicate behavior on rapid double click.
- Music: toggle background music, switch modes, start character chat, start a new chat, and navigate away from Ana Söyleşi; confirm no overlapping audio.
- TTS: enable TTS, send a new message, confirm the new answer is spoken, then load a saved chat and confirm old answers do not auto-play.
- STT: open modal, confirm music pauses/ducks, cancel and confirm restore, reopen and submit and confirm restore, then close the modal through an unexpected Bootstrap/browser close path and confirm music still restores.
- AI Expert audio: simulate or observe an autoplay/play rejection path and confirm the audio element is cleaned, music returns to normal volume, and subtitles still hide through the fallback timer.
- Reasoning: use a thinking-capable model, confirm the panel appears, auto-scroll works, and cleanup happens after response/stop.
- Browser console: confirm there are no JS errors, duplicate audio warnings, or missing element errors.
- Browser smoke: open the smoke page on the target deployment through the same app origin and confirm `UX_SMOKE_DONE:PASS`; on SSO deployments, remember that quick-action intro visibility is covered by focused tests rather than the smoke page. For local VM checks, prefer `tests/scripts/open_ux_smoke.R` with `MERGEN_SMOKE_BASE_URL` set to the app base URL.

### 3C) Bilge Yolaç Windows runtime and Claude Code CLI contract

Bilge Yolaç runs Claude Code from an R/Shiny process and is sensitive to Windows VM, SSO, network-share, and `.cmd` invocation behavior. Keep the following contract intact:

- User-selected upload/project folders may appear as `/rehisds/...`, `//rehisds/...`, UNC paths, or paths containing non-ASCII characters. These paths must not be passed blindly as the `processx` launch working directory on Windows.
- Problematic Windows workdirs must be resolved through the relaxed runtime resolver and, when needed, mirrored into a local temporary runtime directory before Claude Code is launched.
- The runtime resolver lives in `R/helpers_claude_code_runtime_resolver.R`; runtime mirroring and sync-back logic lives in `R/helpers_claude_code_runtime_workdir.R`. Keep these files separate to preserve the maintainability ratchet.
- `R/config_source_manifest.R` must load `R/helpers_claude_code_runtime_resolver.R` after `R/helpers_claude_code_process.R` and before `R/helpers_claude_code_runtime_workdir.R`.
- Windows `.cmd` execution must go through `build_processx_command()` and `build_windows_cmd_invocation_line()` in `R/helpers_claude_code_process.R`.
- For Windows `.cmd` execution, keep the safe local launch working directory and pass `windows_verbatim_args = TRUE` to every `processx::process$new()` call that consumes a command object returned by `build_processx_command()`.
- Do not reintroduce `cmd.exe /s /c` for the Claude Code `.cmd` wrapper. The current wrapper uses `/d /c` and relies on explicit token quoting plus verbatim argument passing.
- Claude Code status checks such as `claude.cmd --version` must not depend on the selected project/upload folder. They should run from a safe local launch directory.
- If Bilge Yolaç can answer document questions but the top-right connection badge shows disconnected, check the CLI status path first; if both fail, check the runtime workdir mirror path.

Protected by:

- `tests/testthat/test-claude-code-process-refactor-contract.R`
- `tests/testthat/test-claude-code-runtime-workdir-contract.R`
- `tests/testthat/test-global-source-manifest-contract.R`
- `tests/testthat/test-maintainability-ratchet.R`

Focused validation after touching Bilge Yolaç process launch, runtime workdir resolution, document-folder handling, source-manifest order, or Claude Code connection status:

- `testthat::test_file("tests/testthat/test-claude-code-process-refactor-contract.R")`
- `testthat::test_file("tests/testthat/test-claude-code-runtime-workdir-contract.R")`
- `testthat::test_file("tests/testthat/test-global-source-manifest-contract.R")`
- `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")`

Manual validation on the Windows VM:

- Start the app with SSO enabled.
- Open Bilge Yolaç.
- Click the upload-folder/project-folder navigation button so the project directory points to a `/rehisds/...` or `//rehisds/...` path.
- Ask a question about files in that folder.
- Confirm the response is produced without `cmd.exe` invalid directory errors, `The specified path is invalid`, or escaped quote errors such as `\"C:\...\claude.cmd\" is not recognized`.
- Open Yapılandırma and run the Claude Code connection test.
- Confirm the CLI status is connected and the top-right badge no longer shows `Bağlantı Yok`.
- Check logs for `[RUNTIME_WORKDIR]` and confirm problematic source paths are mirrored to a local temp runtime path when required.

### 4) Do not create unnecessary new files
This repo already has a lot of modules. New files should only be introduced when there is a clear benefit and the sourcing order in `global.R` is updated correctly.

### 5) Respect the project’s modular load order
A new helper/module is not “done” unless:

- it is placed in the correct layer,
- it is listed in `R/config_source_manifest.R`,
- dependencies are loaded before it,
- `ui.R` / `server.R` wiring is updated where necessary.

### Source manifest validation contract

The runtime source order is now owned by `R/config_source_manifest.R`, not by a long `safe_source()` list inside `global.R`.

`global.R` must remain a high-level boot orchestrator. It is responsible for UTF-8 options, upload limits, resource-path registration, bootstrap loading, manifest-file validation, manifest object validation, manifest file/order/parse validation, future/test-mode setup, and calling the manifest loader. It must not grow back into a giant order-dependent source manifest, and it must not reintroduce duplicated inline `safe_source()` blocks for the manifest groups. `app.R` must keep `R/config_source_manifest.R` in `required_boot_files` so a missing manifest fails before the rest of the app boot proceeds. The expected runtime loading shape is: validate `R/config_source_manifest.R` itself with `source_manifest_validate(order_rules = list(), paths = "R/config_source_manifest.R")`, load it with `safe_source("R/config_source_manifest.R", encoding = "UTF-8")`, call `source_manifest_validate_config_objects()`, call `source_manifest_load(source_manifest_group_1_paths)`, run future/test-mode setup, then call `source_manifest_load(source_manifest_after_future_paths)`.

The current source-manifest layers are:

- `R/utils_safe_source.R`: defines UTF-8-safe `safe_source()` and preserves the Windows/VM fallback behavior.
- `R/bootstrap_source_manifest.R`: defines manifest object-shape validation, critical order rules, parse/file checks, explicit-path validation, and `source_manifest_load()`.
- `R/config_source_manifest.R`: defines the explicit runtime source order. It is organized into a single ordered, named, feature/layer list `source_manifest_sections` (e.g. `foundation`, `database`, `mcp_tools`, `file_manager_helpers`, `claude_code_helpers`, `llm_pipeline`, `module_*`, `server_*`). The three canonical objects are DERIVED from it and remain the public contract: `source_manifest_group_1_paths` is `source_manifest_sections$foundation`, `source_manifest_after_future_paths` is the concatenation of the remaining sections (`unlist(source_manifest_sections[-1L], use.names = FALSE)`), and `source_manifest_runtime_paths` is their union. Sections are purely organizational; the runtime load order is byte-for-byte identical to the concatenation of the sections in order.
- `global.R`: validates `R/config_source_manifest.R` before sourcing it, validates the manifest objects, validates runtime paths, and loads files through `safe_source()` without owning or reconstructing the full list inline.

When adding, moving, or splitting a runtime file:

- add the file to the correct named section (and correct position within it) of `source_manifest_sections` in `R/config_source_manifest.R`; do not add a new top-level path vector outside the sections list,
- keep seam ownership intact: every manifest section must remain owned by exactly one seam in `R/config_seam_registry.R`, and a brand-new section must be assigned to a seam in the same change (see the seam registry and frontend ownership zone contract),
- for file-store lifecycle splits, preserve the order `R/config_file_store.R`, `R/config_file_store_index_lock.R`, `R/config_file_store_index_mutation.R`, `R/config_file_store_listing_helpers.R`, then `R/config_file_store_registry.R`,
- for server runtime/module-wiring splits, preserve the order `R/helpers_server_runtime_contracts.R`, `R/helpers_server_runtime_named_contracts.R`, `R/server_runtime_context.R`, `R/server_runtime_function_slot.R`, `R/server_module_wiring.R`, `R/server_chat_engine_dependencies.R`, `R/server_chat_engine_runtime.R`, then the session/chat runtime init files,
- keep dependency order explicit and reviewable,
- Keep `R/helpers_streaming_abort_lifecycle.R` and `R/helpers_streaming_poll_lifecycle.R` loaded before `R/server_handler_true_streaming.R`; the true streaming handler depends on the abort cleanup plan helper and on the pure poll-loop decision helpers (line classification, reasoning recovery, poll interval, persist delay).
- when splitting Claude Code security helpers, preserve the order `R/helpers_claude_code_security_policy.R` before `R/helpers_claude_code_prompt_security_policy.R`, and keep both before the Claude Code runtime, process, streaming, lifecycle, and module files that call the policy helpers.
- keep loading through `safe_source()`; do not replace it with plain `source()`,
- keep `global.R` validating `R/config_source_manifest.R` before sourcing it and loading manifest groups through `source_manifest_load(...)`; do not manually duplicate group entries with individual `safe_source()` calls,
- keep `source_manifest_runtime_paths` exactly equal to `c(source_manifest_group_1_paths, source_manifest_after_future_paths)`; do not maintain a separate divergent runtime list,
- keep the three canonical objects DERIVED from `source_manifest_sections` (do not hand-maintain them separately), so `unlist(source_manifest_sections, use.names = FALSE)` always equals `source_manifest_runtime_paths`; if you add/rename/reorder a section, update `tests/testthat/test-source-manifest-sections-contract.R` (frozen section order + per-section boundary anchors) in the same change,
- update `source_manifest_required_order` in `R/bootstrap_source_manifest.R` only for genuinely critical dependency boundaries,
- keep `R/bootstrap_source_manifest.R` small, bootstrap-only, and free of feature/module loading,
- do not add automatic directory sourcing, alphabetical sourcing, package-style discovery, or runtime source-order inference,
- do not reintroduce `global.R` scraping or `source_file = "global.R"` style fallback validation; `source_manifest_validate()` must receive explicit paths from `R/config_source_manifest.R`,
- preserve `MERGEN_RUN_APP=false` and `MERGEN_DISABLE_FUTURES=true` boot safety,
- keep comments added to R code in Turkish.

The File Manager attach-state browser handler is intentionally split into `R/helpers_file_manager_attach_client.R`. Keep this helper listed in `R/config_source_manifest.R` after `R/helpers_file_manager_state_runtime.R` and before `R/module_file_manager.R`. Do not move the inline JavaScript registration back into `R/module_file_manager.R`; that module is protected by near-limit maintainability ratchet checks and should remain focused on Shiny orchestration.

Source-order tests must read `R/config_source_manifest.R` as the source of truth. Do not write new tests that scrape `global.R` for every runtime `safe_source("R/...")` entry. Static `global.R` tests should only protect the bootstrap contract, the explicit pre-source validation of `R/config_source_manifest.R`, the manifest object validation call `source_manifest_validate_config_objects()`, and the two high-level manifest loading calls: `source_manifest_load(source_manifest_group_1_paths)` and `source_manifest_load(source_manifest_after_future_paths)`. Use the shared manifest test helper in `tests/testthat/helper_source_manifest_contract.R`, especially:

- `source_manifest_paths_for_tests()`
- `expect_source_manifest_contains_for_tests()`
- `expect_source_manifest_order_for_tests()`

The validation layer should continue to fail early with clear Turkish boot errors when it detects:

- missing source files, including a missing `R/config_source_manifest.R` during the app boot-file check,
- missing or invalid manifest objects,
- divergence between `source_manifest_runtime_paths` and the two explicit manifest groups,
- unintended duplicate source entries,
- unparseable source files, including an unparseable `R/config_source_manifest.R` before it is sourced,
- unsupported attempts to validate by scraping `global.R`,
- critical source-order regressions.

Protected by:

- `tests/testthat/helper_source_manifest_contract.R`
- `tests/testthat/test-global-source-manifest-contract.R`
- `tests/testthat/test-source-manifest-contract.R`
- `tests/testthat/test-source-manifest-sections-contract.R`
- `tests/testthat/test-e2e-boot-welcome-regression.R`
- `tests/testthat/test-production-contracts.R`
- `tests/testthat/test-maintainability-ratchet.R`

Focused validation:

- `testthat::test_file("tests/testthat/test-global-source-manifest-contract.R")`
- `testthat::test_file("tests/testthat/test-source-manifest-contract.R")`
- `testthat::test_file("tests/testthat/test-source-manifest-sections-contract.R")`
- `testthat::test_file("tests/testthat/test-e2e-boot-welcome-regression.R")`
- `testthat::test_file("tests/testthat/test-production-contracts.R")`
- `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")`
- `source("tests/scripts/maintainability_report.R", encoding = "UTF-8")`
- `source("tests/testthat.R", encoding = "UTF-8")`

### Seam registry and frontend ownership zone contract

Production-critical seam ownership is now declared in one machine-readable governance layer. This layer is pure data plus pure validators; it must never change runtime behavior, and it must never become a service locator or a dynamic loader.

Current contract:

- `R/config_seam_registry.R` owns `mergen_seam_registry()`: the canonical map of the 12 production-critical seams (`temel_altyapi`, `veritabani_kodlama`, `kimlik_sso`, `api_anahtar_model`, `sohbet_llm_akis`, `mcp_analiz`, `dosya_yasam_dongusu`, `medya_ses`, `bilge_yolac`, `destek_yonetici_saglik`, `shiny_calisma_zamani`, `frontend_varlik`). Each seam declares its owned source-manifest sections, manifest-external runtime files, guard tests, focused validation commands, and related seams.
- Every `source_manifest_sections` section is owned by exactly one seam. Adding a manifest section without assigning a seam owner, or assigning two owners, fails `tests/testthat/test-seam-registry-contract.R`.
- The seam registry's `extra_runtime_files` is the only allowlist for runtime R files outside the source manifest (currently `app.R`, `global.R`, `server.R`, `ui.R`, `R/utils_safe_source.R`, `R/bootstrap_source_manifest.R`, `R/config_source_manifest.R`). The contract test enforces "no orphan runtime R files": every file under `R/` must be in the manifest or in this allowlist.
- `R/config_ui_asset_zones.R` owns `ui_asset_ownership_zones`: 23 frontend ownership zones. Every CSS/JS asset listed in `R/config_ui_assets.R` belongs to exactly ONE zone; each zone declares a single owner seam and at least one guard test. `ui_asset_unmanifested_ownership` covers the intentionally unmanifested frontend files (the inlined app-loading overlay assets, `css/admin_analytics.css`, and the smoke-only files) with an explicit reason.
- `ui_asset_unmanifested_ownership` entries may carry `optional_in_checkout = TRUE` for vendored files that physically exist ONLY in the on-prem Windows VM working copy (the `renv.lock` provenance pattern; currently `js/fontfaceobserver.js` and `js/highlight.min.js`). `ui_asset_zones_validate()` does not treat their absence in a cloud/CI checkout as a structural problem, while the ownership entry still prevents an ownership-gap report on the VM where the file exists. Do not remove these entries to make a cloud checkout look cleaner, and do not mark a file optional merely because it is missing — optional means "intentionally on-prem-only". Non-optional unmanifested entries must keep failing validation when the file is absent; this split is protected by `tests/testthat/test-ui-asset-zones-contract.R`.
- The zone map declares OWNERSHIP only. Load order stays single-owned by `R/config_ui_assets.R` (`ui_asset_js_order_rules`, `ui_asset_js_render_plan`); do not duplicate ordering logic into the zone map, and do not derive load order from zones.
- Physical coverage is enforced: every `.css`/`.js` file directly under `www/css/` and `www/js/` must be owned through a zone (via the manifest) or through `ui_asset_unmanifested_ownership`. A new frontend file without declared ownership fails `tests/testthat/test-ui-asset-zones-contract.R`.
- The frozen seam id and zone id lists in the contract tests require conscious updates together with `docs/architecture-map.md`.
- The governance layer loads through the manifest (`config_ui_assets` section carries `R/config_ui_asset_zones.R` after `R/config_ui_assets.R`; the `architecture_governance` section carries `R/config_seam_registry.R`). Validation functions are NOT called at boot; enforcement lives in the contract tests and the seam doctor.
- `tests/scripts/seam_doctor.R` (wrapper: `bash tools/seam_doctor.sh`) is the operational report: it validates registry/zones/manifest consistency, reports per-seam section/file/zone/guard-test counts, and writes a secret-safe JSON artifact under `artifacts/seam-doctor/`. It runs no app boot, browser, DB, LLM, or network work, and it is `source(...)`-safe (no `quit()`); structural drift fails it through `stop()`. The doctor artifact is guidance plus structural proof only — it is never evidence that runtime, browser, VM/SSO/DB, or encoding validation ran.
- When a seam boundary genuinely changes (new section, renamed seam, moved zone), update `R/config_seam_registry.R` / `R/config_ui_asset_zones.R`, the frozen lists in the contract tests, and `docs/architecture-map.md` in the same change. Do not weaken the partition checks to make an unowned file pass.

Protected by:

- `tests/testthat/test-seam-registry-contract.R`
- `tests/testthat/test-ui-asset-zones-contract.R`
- `tests/testthat/test-seam-doctor-contract.R`
- `tests/testthat/test-source-manifest-sections-contract.R`

Focused validation:

- `testthat::test_file("tests/testthat/test-seam-registry-contract.R")`
- `testthat::test_file("tests/testthat/test-ui-asset-zones-contract.R")`
- `testthat::test_file("tests/testthat/test-seam-doctor-contract.R")`
- `testthat::test_file("tests/testthat/test-source-manifest-sections-contract.R")`
- `Rscript tests/scripts/seam_doctor.R`

### File resolution, upload-size, and user-isolation contract

File resolution is a security-sensitive boundary. Normal runtime code must treat uploaded files as user-scoped resources, not as general filesystem paths.

Current contract:

- `resolve_uploaded_file()` must remain user-bucket-first.
- Normal user flows must not call `resolve_uploaded_file(..., user_id = NULL)`.
- Normal user flows must not pass `allow_direct_path = TRUE`.
- Normal user flows must not pass `allow_cross_bucket = TRUE`.
- Direct path resolution is denied by default. It may only be used by explicit admin/maintenance code, and only with a trusted root allowlist through `trusted_roots`.
- Cross-bucket resolution is denied by default. It may only be used by explicit migration/repair/admin code.
- Same-user filesystem fallback is allowed and intentional. It exists so files physically present in the current user's upload folder can still resolve when the JSON index is stale, empty, unreadable, or has UTF-8/display-name drift.
- Same-user filesystem fallback must not scan other users' folders.
- MCP file resolution must not convert arbitrary absolute path arguments into readable files.
- MCP legacy root-level index fallback must remain opt-in only through the existing explicit cross-bucket lookup controls.
- Do not reintroduce broad global file lookup in chat, preview, summarization, File Manager, or MCP user flows.

Upload-size policy:

- The central upload limit is `getOption("mergen.upload_max_mb", 25L)`.
- `shiny.maxRequestSize` must be derived from that central option.
- Do not reintroduce a separate hard-coded Shiny upload size such as `30 * 1024^2` in file-store configuration.
- Browser-side upload warnings, server-side validation, and Shiny request limits should stay aligned.

Protected by:

- `tests/testthat/test-resolve-uploaded-file.R`
- `tests/testthat/test-mcp-excel-resolve.R`
- `tests/testthat/test-file-resolution-security-contract.R`
- `tests/testthat/test-upload-size-policy.R`
- `tests/testthat/test-upload-validator.R`
- `tests/testthat/test-upload-validator-branches.R`
- `tests/testthat/test-upload-validator-edge-cases.R`
- `tests/testthat/test-file-store-index.R`
- `tests/testthat/test-e2e-file-context-regression.R`
- `tests/scripts/run_vm_preflight_real.R` when `MERGEN_PREFLIGHT_CHECK_FILE_STORE=TRUE`

Focused validation:

- `testthat::test_file("tests/testthat/test-resolve-uploaded-file.R")`
- `testthat::test_file("tests/testthat/test-mcp-excel-resolve.R")`
- `testthat::test_file("tests/testthat/test-file-resolution-security-contract.R")`
- `testthat::test_file("tests/testthat/test-upload-size-policy.R")`
- `testthat::test_file("tests/testthat/test-upload-validator.R")`
- `testthat::test_file("tests/testthat/test-file-store-index.R")`
- `testthat::test_file("tests/testthat/test-e2e-file-context-regression.R")`
- `Sys.setenv(MERGEN_PREFLIGHT_CHECK_FILE_STORE = "TRUE")`
- `source("tests/scripts/run_vm_preflight_real.R", encoding = "UTF-8")`

### Bilge Yolaç Claude Code execution security contract

Bilge Yolaç wraps Claude Code CLI inside the Shiny UI. This is a security-sensitive and UX-sensitive boundary. Keep CLI argument construction, workdir validation, dangerous-mode decisions, generated-file staging, and prompt-path safety centralized in the Claude Code security helper layer. `R/helpers_claude_code_security_policy.R` owns core policy decisions such as dangerous permissions, permission args, workdir roots, output roots, and path-inside-root checks. `R/helpers_claude_code_prompt_security_policy.R` owns prompt-level path-intent checks. Do not scatter ad hoc permission checks or CLI flags across modules.

Current execution contract:

- `--dangerously-skip-permissions` must remain off by default.
- Dangerous permission bypass may only be enabled through the central policy and an explicit admin/development override such as `CLAUDE_CODE_ALLOW_DANGEROUS_PERMISSIONS=TRUE`.
- When dangerous mode is enabled, it must be logged clearly.
- Normal UX must not require repeated Claude permission prompts for ordinary in-workdir read/write/edit tasks.
- The safe default is `--permission-mode acceptEdits`.
- Default extra allowed tools are `Read`, `Write`, `Edit`, `MultiEdit`, `Glob`, `Grep`, `LS`, and `Bash`.
- MERGEN Bilge runs as a controlled internal corporate / on-prem deployment, so `Bash` is part of the default `CLAUDE_CODE_ALLOWED_TOOLS` baseline. This is required for the model to execute live shell commands and for the ARAÇ KULLANIMLARI counter to reflect actual tool usage. Operators that need a stricter profile may override `CLAUDE_CODE_ALLOWED_TOOLS` in `.Renviron` to a narrower subset; do not silently re-remove `Bash` from the source-level default.
- Do not pass policy prose to Claude as part of the user prompt.
- Do not inject Bilge Yolaç policy text through `--append-system-prompt` unless a future change explicitly proves it is safe and updates the regression tests. The current contract is no policy/system prompt injection.
- Preserve the exact user prompt as the final prompt argument.
- Because `--allowedTools` and `--disallowedTools` can behave like variadic CLI flags, always place the final user prompt after a `--` argument separator. This prevents the prompt from being consumed as another tool name and avoids the Claude CLI error: “Input must be provided either through stdin or as a prompt argument when using --print.”
- Do not remove the `--` prompt separator without updating the security policy tests and manually verifying all model tiers.
- Dangerous skip-permission mode must not be enabled by ordinary per-session or per-user settings alone. It must require the central admin/development override path.
- If dangerous mode is requested from an untrusted setting path, ignore it and log a warning instead of silently enabling bypass mode.
- The non-streaming and standalone streaming helper paths must keep a fallback prompt-path guard before process creation.

Workdir and output contract:

- Workdir validation belongs in the central policy helper.
- User-selected existing workdirs may be approved for the current run when `CLAUDE_CODE_ALLOW_USER_SELECTED_WORKDIRS=TRUE`.
- Workdirs must be normalized before use.
- UNC paths, Windows paths, network shares, and Turkish-character paths should use the existing relaxed directory resolver where applicable.
- Path traversal and unintended outside-root access must remain blocked.
- Prompt-level file write/edit/delete/copy/move intent checks belong in `R/helpers_claude_code_prompt_security_policy.R`.
- Obvious requests to write, edit, delete, copy, move, rename, touch, mkdir, or remove files through absolute paths or `../` traversal outside the allowed roots must be rejected before the CLI process starts.
- `R/module_claude_code.R` must not inline this security workflow. It should call `cc_prepare_safe_workdir_for_run()` from `R/helpers_claude_code_run_lifecycle.R`.
- `cc_prepare_safe_workdir_for_run()` should remain the lifecycle-level coordinator for selected-workdir validation plus prompt-path safety.
- A blocked prompt must clean the active run state, send a clear user-visible blocked-message payload, and log the blocked path.
- Do not weaken this guard for UX convenience. Normal UX should be preserved by allowing safe in-workdir file creation and editing, not by allowing unrestricted paths.
- Generated/downloadable files must be staged only when they are inside the selected workdir, runtime workdir, or an explicitly allowed output root.
- Do not silently allow unrestricted filesystem access just to improve UX.
- Do not regress to unconditional dangerous mode.

Recommended safe environment baseline:

    CLAUDE_CODE_ALLOW_DANGEROUS_PERMISSIONS=FALSE
    CLAUDE_CODE_ALLOW_USER_SELECTED_WORKDIRS=TRUE
    CLAUDE_CODE_PERMISSION_MODE=acceptEdits
    CLAUDE_CODE_ALLOWED_TOOLS=Read;Write;Edit;MultiEdit;Glob;Grep;LS;Bash
    CLAUDE_CODE_DISALLOWED_TOOLS=

Protected by:

- `tests/testthat/test-claude-code-security-policy-contract.R`
- `tests/testthat/test-claude-code-run-lifecycle-contract.R`
- `tests/testthat/test-claude-code-process-refactor-contract.R`
- `tests/testthat/test-claude-code-runtime-workdir-contract.R`
- `tests/testthat/test-claude-code-policy-split-contract.R`
- `tests/testthat/test-claude-code-workdir-scan-contract.R`
- `tests/testthat/test-maintainability-ratchet.R`

Focused validation:

- `testthat::test_file("tests/testthat/test-claude-code-security-policy-contract.R")`
- `testthat::test_file("tests/testthat/test-claude-code-run-lifecycle-contract.R")`
- `testthat::test_file("tests/testthat/test-claude-code-process-refactor-contract.R")`
- `testthat::test_file("tests/testthat/test-claude-code-runtime-workdir-contract.R")`
- `testthat::test_file("tests/testthat/test-claude-code-policy-split-contract.R")`
- `testthat::test_file("tests/testthat/test-claude-code-workdir-scan-contract.R")`
- `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")`

Manual validation after changes to this boundary:

- Open Bilge Yolaç.
- Select a normal project folder.
- Run a harmless code-review prompt.
- Confirm the prompt is not swallowed by `--allowedTools`.
- Confirm there is no `--print` missing-input error.
- Confirm the assistant does not answer or discuss Bilge Yolaç policy text.
- Confirm ordinary file inspection works without repeated permission prompts.
- Ask it to create a small `.txt` or `.md` file in the selected workdir and confirm the generated download link appears.
- Ask it to write outside the selected workdir and confirm it is rejected or fails safely.
- Ask it to create `../blocked.txt` or an absolute outside-root file path and confirm the CLI does not start, the UI shows a clear blocked message, and logs mention the blocked path.
- Confirm logs show safe mode / `acceptEdits` and do not show dangerous mode unless explicitly enabled.

### API model configuration contract

API model/endpoint/tool-mode helper logic is intentionally split from the main API configuration file.

Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/helpers_vision_model_capabilities.R",        encoding = "UTF-8")
safe_source("R/helpers_deep_thinking_model_capabilities.R", encoding = "UTF-8")
safe_source("R/config_api.R",                               encoding = "UTF-8")
safe_source("R/helpers_api_model_config.R",                 encoding = "UTF-8")
safe_source("R/helpers_api_model_tool_runtime.R",           encoding = "UTF-8")
safe_source("R/helpers_api_key_crypto.R",                   encoding = "UTF-8")
safe_source("R/helpers_api_key_identity.R",                 encoding = "UTF-8")
```

Responsibilities:

* `R/config_api.R`: environment loading, global API configuration objects, `api_config`, TTS/STT configuration, and API-key validation orchestration.
* `R/helpers_deep_thinking_model_capabilities.R`: the pure `collect_deep_thinking_model_ids()` + `apply_deep_thinking_model_capabilities()` registration boundary. It consolidates what used to be two separate source-time blocks in `config_api.R`: safe thinking-capable defaults for unknown deep models, completion of missing capability fields on already-defined deep models (existing explicit values always win), and missing endpoint-map entries defaulting to `"primary"` while the map stays a named character vector. `config_api.R` calls it through a guarded `exists(...)` check like the vision helper. Keep it loaded BEFORE `R/config_api.R`; isolated tests that source `config_api.R` directly must source this helper first. Do not re-inline either legacy block into `config_api.R`.
* `R/helpers_api_key_crypto.R`: the user API key encrypted storage layer moved out of `config_api.R`: `API_KEYS_DIR`, `.api_user_file()`, `.hash_key_hex()`, `.enc_key()`, `.dec_key()`, `save_user_api_key()`, `load_user_api_key()`, `user_api_key_exists()`, and `verify_user_api_key()`. Behavior, the NUL-salt regression guard, UTF-8 round-trip, and the atomic JSON write path are unchanged. Do not move these back into `config_api.R`.
* `R/helpers_api_model_config.R`: pure model capability, request override, endpoint credential, validation-target, tool-mode, and main-action model resolution helpers.

This split is protected by `tests/testthat/test-config-api-split-contract.R` and `tests/testthat/test-deep-thinking-model-capabilities-behavior.R`; the crypto behavior coverage lives in `tests/testthat/test-config-api-key-crypto-behavior.R` (now sourcing the crypto helper directly). The `R/config_api.R` ratchet budget is tightened to 520 lines / 6 functions — do not consume the freed headroom by moving logic back.

Personal API keys are user-owned credentials. They must be loaded/saved only after authenticated application identity is available, and must never fall back to `Sys.info()[["user"]]` or the Shiny/Windows service account. Session key state is cleared at session/module start, and a session key is accepted only when its owner marker matches the authenticated user. LLM request paths should use the effective-key helpers rather than directly trusting `session$userData$ai_api_key`.

The server-managed default API key is configured through deployment environment variables, not through a user key file and not in GitHub. A personal user key always takes precedence. The default key is used only when `MERGEN_ALLOW_DEFAULT_API_KEY=TRUE` and `MERGEN_REQUIRE_PERSONAL_API_KEY` is not `TRUE`; do not print or expose it in validation reports or logs.

### API key onboarding and choice modal contract

The premium API key choice/onboarding modal is part of the security boundary, not just a visual layer. Preserve these rules when touching API-key UI, settings, source order, or frontend assets:

- `R/module_api_key_choice_modal.R` must load before `R/module_api_key.R` through `R/config_source_manifest.R`.
- When a default corporate key is available, the modal presents both `Personal API Key` and `Default Corporate Key`; when it is unavailable, only the personal-key path is shown.
- Keep assets local/offline under `www/assets/api-key-choice/`, `www/css/api_key_choice_modal.css`, and `www/js/api_key_choice_modal.js`. `www/assets/api-key-choice/backdrop.mp4` is optional and may be absent; `www/assets/api-key-choice/backdrop-poster.svg` is the local fallback.
- Never send a personal API key value or the default API key value to the browser. `MERGEN_DEFAULT_API_KEY` must not appear in client-side files or modal markup.
- The only localStorage state for this flow is the non-secret `mergen_settings.api_key_onboarding_suppressed` preference. The “do not show again” checkbox is available only when a default corporate key exists, and `R/module_api_key.R` intentionally waits briefly for the client suppression flag before deciding whether to open the modal.
- `api_key_plain_input` must remain present and directly usable. `api_key_save_btn`, `api_key_clear_btn`, and `api_key_use_default_btn` are protected input IDs because server observers depend on them; keep `api_key_clear_btn` in the modal UI so the clear observer can reset the password input.
- Do not reintroduce the old reveal/toggle style for personal API key entry. Keep the modal centered with Bootstrap 3-compatible CSS and keep this modal exempt from the global `modal-body` 60vh scroll restriction.
- The choice screen must remain reopenable from settings through `show_api_key_onboarding`.
- Protected coverage: `tests/testthat/test-api-key-choice-modal-contract.R`; keep this test aligned with the modal contract and with the protected files above.

```ini
MERGEN_ALLOW_DEFAULT_API_KEY=TRUE
MERGEN_REQUIRE_PERSONAL_API_KEY=FALSE
MERGEN_DEFAULT_API_KEY=<company-default-api-key>
```

`R/helpers_api_model_config.R` owns these public helper functions:

```text
get_local_model_capabilities()
merge_named_list_deep()
apply_model_request_overrides()
is_thinking_model()
should_omit_temperature()
should_stream_reasoning()
should_allow_reasoning_fallback()
resolve_local_llm_endpoint()
resolve_local_llm_credentials()
determine_api_key_validation_target()
get_tool_mode_config()
resolve_tool_model_for_family()
resolve_tool_model_for_flag()
build_main_actions_data_from_config()
```

Do not move these helpers back into `R/config_api.R`. The split keeps `R/config_api.R` below the 800-line maintainability threshold while preserving existing public function names.

The LLM, SSE, non-streaming API, and future-worker paths rely on `apply_model_request_overrides()`, `merge_named_list_deep()`, `should_omit_temperature()`, and the endpoint-resolution helpers being loaded before the LLM helper layer. If a future refactor changes this boundary, update `R/config_source_manifest.R`, any genuinely critical order rules in `R/bootstrap_source_manifest.R`, and the contract tests; do not move this ordering back into inline `global.R` source calls.

Protected by:

```text
tests/testthat/test-api-model-config-refactor-contract.R
tests/testthat/test-llm-reasoning-request-overrides.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-sse-worker-export-contract.R
tests/testthat/test-maintainability-ratchet.R
```

Current maintainability ratchet baseline after the latest send_message prompting extraction is: score `100/100`, at most `0` 800+ line files, at most `0` 25+ function files, `0` 1500+ line files, maximum runtime file length `792` when `R/library_queries.R` is ignored as the external SQL library holder, and maximum function count `24`. Do not loosen these limits without an explicit reason. The ratchet also locks the current budgets of near-limit runtime files such as `R/module_claude_code.R`, `R/server_send_message.R`, `R/module_admin_hata_analizi.R`, `R/module_image_generation.R`, `R/helpers_llm_sse.R`, and other high-line/high-function files so remaining headroom cannot be silently consumed. There is no remaining score-driven refactor candidate in the latest maintainability report; future refactors should be selected for concrete production reliability, race-condition reduction, or cohesive architectural risk reduction rather than score chasing. Small helper extraction is preferred when a near-limit runtime file would otherwise consume remaining headroom; the File Manager attach-state client helper is an example of this pattern. Recent file-resolution hardening required one File Manager function-count budget update after tests passed; do not loosen additional ratchet values unless the code change genuinely changes the measured baseline and the reason is documented. The prompt-path security split is part of this contract: keep `R/helpers_claude_code_prompt_security_policy.R` separate from the already dense core security policy helper, and keep `R/module_claude_code.R` delegating workdir/prompt safety to the lifecycle helper instead of growing inline security blocks.

### Server runtime and module wiring contract

The server runtime/module wiring boundary was split to reduce maintainability risk without moving behavior back into `server.R`.

Current contract:

- `server.R` must remain a thin orchestration layer. It may build named dependency bundles and pass `runtime_ctx`, but it must not regain module implementation logic.
- `R/server_runtime_context.R` owns runtime context attachment and accessors for identity, state, cache, file runtime, chat runtime, registered modules, SSO auth-ready refresh hooks, and session-data exposure.
- `R/helpers_server_runtime_contracts.R` contains the small core runtime contract helpers.
- `R/helpers_server_runtime_named_contracts.R` contains named-function and environment validation helpers so the core contract file stays under the maintainability ratchet.
- `R/server_module_wiring.R` owns medium-level service, settings, media, file prelude, file manager, image gallery, and chat persistence binding.
- `R/server_chat_engine_dependencies.R` owns only the chat-engine dependency bundle contract through `serverBuildChatEngineDependencyBundle()` and `.server_wiring_resolve_chat_engine_deps()`.
- `R/server_chat_engine_runtime.R` owns `serverBindChatEngineRuntime()` and the chat-engine observer/runtime wiring.
- `R/server_core_interaction_runtime.R` owns the core interaction handoff and validates the core dependency bundle built by `serverBuildCoreInteractionBundle()`.

Keep these dependency groups as named bundles rather than re-expanding long repeated parameter lists in `server.R`:

- Core interaction bundle: `settings_data`, `api_config`, `media_modules`, welcome forward refs, send-message forward refs, load-chat state, and user display/config providers.
- Chat engine dependency bundle: `settings_data`, `api_key`, `user_config_rv`, `perf_tracker`, media processors, `saved_chats_data`, `send_message_fns`, `send_message_proxy`, `api_config`, and optional admin/feedback references.

Important constraints:

- Do not move chat-engine runtime wiring back into `R/server_module_wiring.R`.
- Do not move chat-engine dependency validation back into `server.R`.
- Do not make `runtime_ctx` a god object. Identity, state, cache, file runtime, chat runtime, and registered modules belong there; external service/module dependencies should stay in small named bundles.
- `api_key` is not required to be a plain function. Do not validate it with `.server_wiring_require_functions()`.
- Optional `admin_pool` must be handled defensively. A missing `admin_pool` symbol must resolve to `NULL`, not crash the app.
- Missing required bundle fields and functions should fail early with clear Turkish error messages.
- Keep SSO/local user identity behavior provider-based. Do not pass stale `current_user_id` snapshots into user-scoped modules.

- File Manager auth readiness is also provider-based. `serverBindFileManagerRuntime()` must obtain `identity$is_auth_ready` through `serverRuntimeRequireIdentity(...)` and pass it into `fileManagerServer()` as `auth_ready_provider = identity$is_auth_ready`. Do not make File Manager read `session$userData$auth_initialized` directly for the primary readiness decision.
- Keep the core File Manager delegation in `serverBindCoreInteractionRuntime()` as a direct call using the literal assignment `file_manager_runtime <- file_manager_runtime_fn(...)`. Tests and injected fake runtimes rely on this contract; do not wrap the call in another helper just to pass optional boot metadata.
- If File Manager needs boot readiness metadata, attach it to `runtime_ctx$modules$boot_ready` before the direct File Manager runtime call and let `serverBindFileManagerRuntime()` resolve it through its default `boot_ready` argument. Do not add extra required parameters to injected runtime functions.
- `R/module_file_manager.R` is near the maintainability ratchet limit. Do not add local helper functions or multi-line lifecycle glue there for boot marking; prefer existing helper modules, runtime wiring, or compact guarded calls that preserve the current behavior and budget.
- File Manager should mark `file_index_ready` only after `refresh_persisted_files()` runs for startup-style triggers such as `initial`, `auth_ready`, or `startup`, and only when `boot_ready$mark` is available.

Protected by:

- `tests/testthat/test-source-manifest-contract.R`
- `tests/testthat/test-production-contracts.R`
- `tests/testthat/test-server-module-wiring-chat-engine.R`
- `tests/testthat/test-server-core-interaction-runtime.R`
- `tests/testthat/test-server-live-user-provider-contract.R`
- `tests/testthat/test-maintainability-ratchet.R`
- `tests/testthat/test-file-manager-module-policy-wiring.R`

Focused validation:
- `testthat::test_file("tests/testthat/test-file-manager-module-policy-wiring.R")`

- `Sys.setenv(MERGEN_RUN_APP = "false")`
- `source("app.R", encoding = "UTF-8")`
- `testthat::test_file("tests/testthat/test-source-manifest-contract.R")`
- `testthat::test_file("tests/testthat/test-production-contracts.R")`
- `testthat::test_file("tests/testthat/test-server-module-wiring-chat-engine.R")`
- `testthat::test_file("tests/testthat/test-server-core-interaction-runtime.R")`
- `testthat::test_file("tests/testthat/test-server-live-user-provider-contract.R")`
- `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")`
- `source("tests/scripts/maintainability_report.R", encoding = "UTF-8")`

Manual validation after changing this boundary:

- Start with SSO disabled and confirm welcome screen, new chat, quick actions, File Manager, saved chats, and history still work.
- Start on the VM with SSO enabled and confirm login, user-specific saved chats, user-specific File Manager folder, and user-specific image gallery still work.
- Confirm streaming answer, non-streaming answer, stop generation, and TTS-enabled answer still work.
- Confirm there are no `current_user_id`, `streaming_state`, `ai_msg`, `admin_pool`, or `serverBuildChatEngineDependencyBundle` missing-object errors.

Final check:
After editing both files, ensure no unrelated documentation sections changed.

### send_message prompting and file-context contract

The central send_message runtime path is intentionally split so `R/server_send_message.R` does not become the owner of every prompt, style, and uploaded-file context detail.

Preserve this source order in `R/config_source_manifest.R`:

    safe_source("R/helpers_send_message_request_lifecycle.R", encoding = "UTF-8")
    safe_source("R/helpers_send_message_core.R",              encoding = "UTF-8")
    safe_source("R/helpers_send_message_prompting.R",         encoding = "UTF-8")

Responsibilities:

* `R/helpers_send_message_request_lifecycle.R`: request ids, stale/current/stopped request checks, prompt snapshots, deferred chat creation decisions, welcome cleanup, and thinking-panel shell setup.
* `R/helpers_send_message_core.R`: tool-family routing, send-message cleanup/abort helpers, stream profile selection, and MCP session-file preparation.
* `R/helpers_send_message_prompting.R`: citation instruction construction, character/style/system prompt assembly, SQL system prompt merging, MCP Excel uploaded-file context prompts, and MCP-disabled uploaded-file context prompts.
* `R/server_send_message.R`: request orchestration, SSO/user guards, chat/message lifecycle, mode dispatch, API/model setup, and streaming/non-streaming handoff.

Do not move prompt/style/file-context assembly back into `R/server_send_message.R`. Keeping this boundary creates maintainability headroom below the 800-line threshold and reduces the risk that future prompt changes accidentally alter request lifecycle or streaming state.

Race-condition and behavior contracts:

* `send_message()` must continue to create a single request id and pass it to both the thinking/reasoning shell and the true-streaming path.
* Send-message cleanup and abort paths must remain request-scoped when a request id is available. A stale async callback must not remove a newer request’s `#typing-animation-wrapper`.
* `mergen_remove_typing_wrapper_if_safe()` is the focused helper for this guard. Keep it injectable in tests through its remove-UI function argument and do not replace it with unconditional `removeUI("#typing-animation-wrapper")`.
* `send_message()` must bind cleanup/abort closures to the request id created for that invocation before later async paths can call cleanup.
* SQL analysis must merge the style instruction into an existing system message instead of adding a second competing system message.
* MCP Excel prompts must continue to require file tools such as `analyze_uploaded_file`, `get_column_statistics`, or `sql_query_uploaded_file` instead of letting the model guess file contents.
* MCP-disabled uploaded-file prompts must continue to use stored summaries or safe file excerpts and must still end with a Turkish `Kaynakça:` section.
* The helper extraction must not change user-visible Turkish text, filename display behavior, citation behavior, or source-order contracts.
* Avoid introducing local variables that shadow globally important helpers such as `is_thinking_model()` in the send-message runtime path.

Protected by:

    tests/testthat/test-send-message-prompting-contract.R
    tests/testthat/test-send-message-request-lifecycle-contract.R
    tests/testthat/test-send-message-maintainability-ratchet.R
    tests/testthat/test-source-manifest-contract.R
    tests/testthat/test-maintainability-ratchet.R
    tests/testthat/test-e2e-quick-actions-streaming-regression.R
    tests/testthat/test-e2e-streaming-client-request-id-regression.R

Focused validation:

    testthat::test_file("tests/testthat/test-send-message-prompting-contract.R")
    testthat::test_file("tests/testthat/test-send-message-request-lifecycle-contract.R")
    testthat::test_file("tests/testthat/test-send-message-maintainability-ratchet.R")
    testthat::test_file("tests/testthat/test-source-manifest-contract.R")
    testthat::test_file("tests/testthat/test-maintainability-ratchet.R")
    testthat::test_file("tests/testthat/test-frontend-selector-contract.R")
    source("tests/scripts/maintainability_report.R", encoding = "UTF-8")
    source("tests/testthat.R", encoding = "UTF-8")

### Frontend selector and DOM contract

Frontend JavaScript must stay aligned with the actual UI IDs and classes. Do not reintroduce stale chat input selectors such as `#message_input`. The current chat input contract is `#user_input`, `.chat-input`, and `textarea[name="user_input"]`, centralized in `www/js/input_handlers.js` and exposed through `window.MERGEN_CHAT_INPUT_SELECTOR` plus `window.getMergenChatInputElement()`. Send, Enter, Shift+Enter, Escape, character counter, textarea resize, capability-message submission, and stop-mode behavior should continue to use that shared selector path or a safe fallback with the same selector set. Programmatic input events that are intended to trigger delegated handlers must bubble.

The chat content root contract is now explicit. Message observers and CodeMirror observers must attach only to current real chat roots such as `#chat_content_container` or `.chat-container`; do not reintroduce the stale `#_content_container` fallback. The main message observer must be reattached through an explicit helper such as `attachMessageObserver(...)` after Shiny reconnects, just like the CodeMirror observer. Any MutationObserver that is re-established after Shiny reconnects must disconnect the previous observer first, and disconnect cleanup must run on `shiny:disconnected`. This prevents duplicate observers, stale DOM references, lost auto-scroll or widescreen wrapper updates after reconnects, and hidden repeated CodeMirror initialization after reconnects or page refreshes.

Chart rendering must follow the same chat-root contract. `www/js/chart_renderer.js` must not reintroduce stale roots such as `chat_content_wrapper`; saved ChartLab rendering should resolve the current real chat root through `#chat_content_container` or `.chat-container` before calling `window.renderSavedCharts(...)`. Keep this lookup centralized through a small helper such as `getChartRenderRoot(wrapperId)`. Do not fall back to broad `document.body` scans and do not construct dynamic class selectors such as `querySelector('.' + wrapperId)` for this path, because those fallbacks can hide selector drift and initialize charts outside the intended chat surface.

Dynamic drag/drop handlers must not cache Shiny-rendered DOM nodes at document-ready time when the node can be redrawn later. For chat upload and File Manager upload surfaces, keep delegated event handlers, but resolve `#chat_input_wrapper` and `#file_manager_module-main_drop_zone` at use time through small getter helpers. This preserves behavior while avoiding stale jQuery object references after tab switches, redraws, or UI refreshes.

Server-side activity and browser-side send/stop wiring must refer to the real `send_stop_btn` input. Do not reintroduce the stale `send_btn` identifier for the main chat send button. If timeout/activity tracking or JavaScript send helpers are changed, update the UI contract and `tests/testthat/test-frontend-selector-contract.R` together.

The TTS visualizer can receive Shiny messages before its delayed browser-side initializer has completed. `updateTTSVisualizer` must guard against a missing visualizer/state object and return safely rather than throwing null-init errors. This is a lifecycle guard only; it must not change the visual appearance or placement behavior of the visualizer.

The welcome neural animation message contract must remain single-owner. `showNeuralAnimation` should be registered as a Shiny custom message handler only in `www/js/shiny_message_handlers.js`. `www/js/neural_welcome.js` should expose `window.startNeuralWelcomeAnimation(...)` and own the animation implementation, but it must not register another `Shiny.addCustomMessageHandler('showNeuralAnimation', ...)`. This prevents load-order-dependent behavior when deferred welcome scripts initialize after the synchronous Shiny message handler layer.

#### Follow-up suggestions contract

Follow-up suggestions are controlled by the Yapılandırma setting `enable_followups`. This setting must be read through the tolerant server-side resolution path so logical, numeric, and string-like truthy values do not silently disable the feature. Keep the helper boundary around `coerce_followup_flag()` and `resolve_followup_enabled()` intact unless replacing it with an equally tolerant and tested path.

`build_followup_suggestions()` must not depend exclusively on an additional AI call. Local/deterministic suggestions and safe default suggestions are the reliability baseline; AI-generated suggestions may override them only when they are valid and non-empty. If the AI follow-up generator fails, returns malformed JSON, or returns too few suggestions, the UI should still receive usable follow-up suggestions whenever `enable_followups` is enabled.

Streaming messages may render the initial AI bubble before follow-up suggestions are known. The browser-side `updateFollowupSuggestions` handler must therefore continue to create `#followup_container_<message_id>` on demand when the container was not rendered by R. Do not assume the container always exists at initial message render time.

`push_followup_update()` should continue to send only non-empty cleaned suggestions and keep lightweight diagnostic logging for payload dispatch. Do not remove this logging unless an equivalent regression diagnostic is added elsewhere.

Protected by:
- `tests/testthat/test-followup-suggestions-regression.R`
- `tests/testthat/test-frontend-selector-contract.R`

Focused validation:
- `testthat::test_file("tests/testthat/test-followup-suggestions-regression.R")`
- `testthat::test_file("tests/testthat/test-frontend-selector-contract.R")`

### UI asset manifest contract

The frontend CSS/JS loading surface is now owned by `R/config_ui_assets.R`, not by a long inline asset list inside `ui.R`.

Current contract:

- `ui.R` should render frontend assets through `ui_asset_tags()`.
- Page or feature modules must not silently reintroduce local `tags$head(...)` CSS/JS includes for assets that are globally owned by `R/config_ui_assets.R`.
- The health dashboard is part of the global UI asset manifest: keep `css/health_dashboard.css` and `js/health_dashboard.js` in `R/config_ui_assets.R`, not in a local `tags$head(...)` block inside `R/module_health.R`.
- `www/js/health_dashboard.js` owns health-dashboard-specific behavior such as `initHealthTooltips`, `removeHealthTooltips`, tooltip cleanup, path-copy button binding, and unload cleanup.
- `updateHealthTimestamp` and `updateAdminTimestamp` are single-owned by `www/js/shiny_message_handlers.js` through the shared timestamp update helper. Do not register these message handlers again in `www/js/health_dashboard.js`.
- Do not reintroduce a giant inline list of `tags$link(...)` and `tags$script(...)` calls in `ui.R`.
- Browser-facing asset paths must remain public Shiny paths such as `css/...`, `js/...`, `codemirror/...`, and `lib/threejs/...`; file existence validation must resolve them under the Shiny public asset root, normally `www/`.
- Keep CodeMirror core, modes, and addons synchronous and ordered before CodeMirror-dependent code.
- Keep the SSO script synchronous and before critical app scripts.
- Keep Three.js dependencies ordered and deferred as a group; preserve the explicit order rules for `three.min.js`, `OrbitControls.js`, shader passes, `EffectComposer`, `RenderPass`, `UnrealBloomPass`, and `Lensflare.js`.
- Keep critical app scripts synchronous where existing client boot behavior depends on them.
- Keep deferred feature scripts deferred unless there is a demonstrated dependency that requires synchronous loading.
- Keep Bilge Yolaç modules in their explicit dependency order, starting with `js/bilge_yolac_motor.js` and ending with `js/bilge_yolac_kopru.js`.
- Keep `ui_asset_js_order_rules` as the manifest-level source of truth for critical browser dependency boundaries. Do not duplicate the same ordering logic in tests as a separate hard-coded list.
- Keep `ui_asset_css_order_rules` as the manifest-level source of truth for the theme cascade (`variables` -> `theme_tokens` -> `theme_light_core` -> `theme_light_welcome` -> `theme_light_chat` -> `theme_light_modals` -> `theme_light_bilge_yolac` -> `theme_light_personalization` -> `theme_light_pages`), the post-theme surfaces (`brand_title.css`, `sidebar_user_panel.css`, `tool_backgrounds.css`), and the Bilge Yolaç CSS chain. Keep `ui_asset_validate_css_order()` wired into `ui_asset_validate(...)` so bad cascade ordering fails early before the UI is rendered.
- Keep `ui_asset_validate_js_order()` wired into `ui_asset_validate(...)` so bad asset ordering fails early before the UI is rendered.
- Keep `ui_asset_deferred_js_paths()` as the single helper for resolving deferred JS groups; do not hand-flatten deferred groups in tests or UI rendering code.
- Keep `ui_asset_js_render_plan` as the single render-order plan for JS groups. `ui_asset_js_tags()` must render scripts from this plan rather than duplicating another hard-coded group order.
- Keep `ui_asset_validate_js_render_plan()` wired into `ui_asset_validate(...)`. It must fail early when a JS group is missing from the render plan, appears more than once, references a non-existent group, or disagrees with `ui_asset_deferred_js_groups`.
- Keep `ui_asset_render_plan_groups()` and `ui_asset_render_plan_deferred()` as the shared helpers for render-plan tests. Do not hand-reconstruct the same render-plan logic inside tests.
- When adding, removing, or renaming a JS group, update `ui_asset_js_groups`, `ui_asset_js_render_plan`, `ui_asset_deferred_js_groups` when applicable, and `tests/testthat/test-ui-asset-manifest-contract.R` together.
- Keep `js/music_manager.js` before `js/stt_client.js` and `js/tts_manager.js`. STT and TTS guard for missing globals, but the maintained asset contract should load the music manager before media consumers so duck/unduck behavior remains deterministic.
- Keep the background music lifecycle single-source. `MusicManager` should own one active audio element and must not allow overlapping main-theme, character-theme, TTS, STT, or intro music paths.
- Keep the startup music sequence deterministic: intro music belongs to `SpaceIntroMusic`; after the deep-space intro is dismissed, `MusicManager` starts the main theme once and then moves to randomized character music.
- Do not let duplicate `toggleMusic(TRUE)` calls skip the main theme. If a theme playlist request is pending, another same-state enabled toggle must not issue an early character playlist request or invalidate the pending theme request.
- Character music folders under `www/music/Karakter/` use stable lowercase persona ids: `emre`, `selin`, `deniz`, `can`, and `ipek`. Do not rename these folders to visible labels such as `Selin Sezgin`.
- Keep welcome startup dependencies ordered so `js/shiny_message_handlers.js` owns the boot handler and `js/welcome_video_player.js`, `js/welcome_neural_modern.js`, `js/welcome_greeting.js`, and `js/welcome_greeting_personal.js` are available through the retry-based `initModernWelcome` path.
- Keep `js/encoding_utils.js` before `js/shiny_message_handlers.js` and before `js/claude_code_streaming.js`; both general Shiny messages and Bilge Yolaç streaming depend on the shared client-side encoding fallback.
- Keep deferred welcome handlers resilient to first-connect timing. `www/js/welcome_neural_modern.js` must register `updateNeuralColor` idempotently even when the script loads after the initial `shiny:connected` event; do not move this handler behind a connect-only registration that can be missed until reconnect.
- Keep `js/streaming_manager.js` before `js/claude_code_streaming.js`, and keep `js/claude_code.js`, `js/claude_code_streaming.js`, and `js/claude_code_plugins.js` in that order.
- Tests must continue to scan loaded JS files for duplicate `Shiny.addCustomMessageHandler(...)` message names.
- Asset-manifest tests should validate files that are intentionally loaded by the manifest. Do not require every physical file under `www/css` or `www/js` to appear in the manifest, because optional, legacy, or feature-specific public files may exist without being globally loaded. Ownership is still mandatory: such files must be declared in `ui_asset_unmanifested_ownership` (`R/config_ui_asset_zones.R`) with an owner seam and reason, so no frontend file is unaccounted for.
- When adding, removing, renaming, or moving a frontend asset, update `R/config_ui_assets.R`, the zone assignment in `R/config_ui_asset_zones.R`, and the asset manifest/zone tests together.
- Do not add CDN usage. The app must remain fully offline/on-prem.
- Do not register duplicate `Shiny.addCustomMessageHandler(...)` handlers for the same message type.

Protected by:

- `tests/testthat/test-ui-asset-manifest-contract.R`
- `tests/testthat/test-ui-asset-zones-contract.R`
- `tests/testthat/test-frontend-selector-contract.R`
- `tests/testthat/test-e2e-boot-welcome-regression.R`
- `tests/testthat/test-e2e-health-dashboard-regression.R`

Focused validation:

- `testthat::test_file("tests/testthat/test-ui-asset-manifest-contract.R")`
- `testthat::test_file("tests/testthat/test-ui-asset-zones-contract.R")`
- `testthat::test_file("tests/testthat/test-frontend-selector-contract.R")`
- `testthat::test_file("tests/testthat/test-e2e-boot-welcome-regression.R")`
- `testthat::test_file("tests/testthat/test-e2e-health-dashboard-regression.R")`

### Frontend asset and maintainability ratchet contract

Frontend JS/CSS assets are protected by the explicit UI asset manifest and by a lightweight maintainability ratchet. Keep all frontend assets local/offline and loaded through `R/config_ui_assets.R`. Do not bundle, minify, hide source code, or introduce CDN dependencies.

### Frontend Console Hygiene Notes

- Keep the Chrome Issues date-range accessibility fix in place. In `R/module_chat_history.R`, `history_accessible_date_range_input()` intentionally avoids Shiny’s default `dateRangeInput` label wiring that can produce an invalid `label[for=inputId]` against a wrapper `div`; it uses an accessible `aria-labelledby` target instead.
- Do not introduce `src = ""` on `img` tags. For intentionally empty placeholders, use the transparent 1x1 GIF data URI: `data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==`.
- `www/js/console_error_probe.js` is an optional diagnostic helper. It is intentionally loaded from `R/config_ui_assets.R` in the diagnostics JS group before normal app JS, and intentionally silent unless `localStorage.MERGEN_DEBUG_CONSOLE_ERRORS === "1"`.
- Do not remove `console_error_probe.js` only because it appears quiet. Its gate is intentional; when enabled it helps expose resource failures (`MERGEN_DEBUG_RESOURCE_ERROR`) and runtime/promise failures (`MERGEN_DEBUG_ERROR`, `MERGEN_DEBUG_PROMISE`).
- Do not use the probe to hide or suppress errors; it is diagnosis-only.
- Browser console hygiene: Chat History date filtering is intentionally implemented with native browser date inputs plus `www/js/history_date_range.js`, not Shiny `dateRangeInput()` / bootstrap-datepicker. Do not revert this path or use `updateDateRangeInput()` for the Chat History range; doing so can reintroduce bootstrap-datepicker deprecation warnings. The JS bridge must keep a backward-compatible Shiny input setter path: prefer `Shiny.setInputValue` when available and fall back to `Shiny.onInputChange` for older Shiny clients. The previous guidance about a stale grouped DevTools `<other>` / `1 error` counter is obsolete after the latest cleanup and should not be reintroduced. Future reproducible console errors, stack traces, failed requests, or broken DOM behavior remain real regressions.

Bilge Yolaç pixel character frame data is intentionally split from runtime behavior:
- `www/js/claude_code_pixel_chars.js` contains only static 16x16 pixel character frame data exposed through `window.MergenClaudeCodePixelCharsMini`.
- `www/js/claude_code.js` owns runtime behavior: animation drawing, message rendering, thinking/status UI, prompt syncing, keyboard shortcuts, and click feedback.
- Do not move runtime behavior into the static pixel-data file.
- Do not inline the static pixel data back into `claude_code.js` unless the asset-order contract and frontend maintainability ratchet are deliberately updated.
- `R/config_ui_assets.R` must load `js/claude_code_pixel_chars.js` before `js/claude_code.js`, and `js/claude_code.js` before `js/claude_code_streaming.js`.

Frontend maintainability is measured by `tests/scripts/frontend_maintainability_report.R` and protected by `tests/testthat/test-frontend-maintainability-ratchet.R`. The report shows the largest JS/CSS files, approximate JS function and event-handler counts, Shiny custom message handlers, duplicate CSS selectors, and forbidden legacy selector hits. The ratchet is intentionally baseline-aware: it should prevent silent growth without forcing an immediate large refactor of existing frontend files. Duplicate CSS selectors are reported for visibility; do not make broad CSS rewrites only to satisfy cosmetics unless a targeted refactor is planned.

### Frontend complexity doctor

- Frontend maintainability is monitored without changing runtime UX.
- `tests/scripts/frontend_maintainability_report.R` exposes a top-risk summary covering largest JS/CSS files, highest function counts, event handler counts, Shiny handler counts, duplicate CSS selectors, unmanifested runtime assets, allowlisted non-runtime assets, and smoke-only assets.
- `tests/scripts/frontend_complexity_doctor.R` reads that report and writes a UTF-8 JSON artifact under `artifacts/frontend-complexity-doctor/frontend-complexity-doctor-*.json`.
- `www/smoke/ux-smoke-probes.js` is smoke-only and must not be added to `R/config_ui_assets.R`.
- Do not refactor runtime frontend files such as `music_manager.js`, `tts_manager.js`, `stt_client.js`, `streaming_manager.js`, or `claude_code_streaming.js` unless there is a small, explicit, test-backed reason.
- For docs-only changes, do not run R validation; just inspect the Markdown diff.

Focused validation after touching frontend JS/CSS assets, UI asset order, or Bilge Yolaç frontend files:
- `source("tests/scripts/frontend_maintainability_report.R", encoding = "UTF-8")`
- `testthat::test_file("tests/testthat/test-frontend-maintainability-ratchet.R")`
- `testthat::test_file("tests/testthat/test-ui-asset-manifest-contract.R")`
- `testthat::test_file("tests/testthat/test-frontend-selector-contract.R")`

### Media and background music contract

Background music is a race-sensitive and encoding-sensitive boundary. Keep the current architecture intact:

- `SpaceIntroMusic` is only for the deep-space intro screen.
- `MusicManager` owns the main application background music after the intro is dismissed.
- The intended sequence is: main theme once, then randomized selected-character tracks.
- The main theme must not be skipped when Dinamik or Bütünleşik mode starts music from the welcome flow.
- Same-state duplicate `toggleMusic(TRUE)` calls must be idempotent while a theme playlist request is pending.
- Playlist responses must remain request-id guarded so stale responses cannot overwrite a newer music state.
- Audio load errors must remain bounded. Do not reintroduce a tight error -> next track -> error loop that can freeze the browser tab.
- Character music URL generation must encode each path segment as UTF-8. On Windows/Turkish locale, Turkish characters in music filenames must produce UTF-8 percent-encoding (for example `Ü` -> `%C3%9C`), not native-byte `%DC`.
- Do not call `URLencode()` on a full native-encoded relative path for music files. Use the existing UTF-8 music URL helper path in `R/server_music_handlers.R`.
- Keep user-visible Turkish labels separate from stable persona ids. Persona ids are ASCII (`emre`, `selin`, `deniz`, `can`, `ipek`) and the filesystem folders use the same ASCII ids, for example `www/music/Karakter/emre`.

Protected by:

- `tests/testthat/test-e2e-media-audio-state-regression.R`
- `tests/testthat/test-ui-asset-manifest-contract.R`
- `tests/testthat/test-frontend-selector-contract.R`
- `tests/testthat/test-e2e-boot-welcome-regression.R`
- `tests/testthat/test-global-source-manifest-contract.R`
- `tests/testthat/test-source-manifest-contract.R`
- `tests/testthat/test-production-contracts.R`
- `tests/testthat/test-maintainability-ratchet.R`

Focused validation:

- `testthat::test_file("tests/testthat/test-e2e-media-audio-state-regression.R")`
- `testthat::test_file("tests/testthat/test-ui-asset-manifest-contract.R")`
- `testthat::test_file("tests/testthat/test-frontend-selector-contract.R")`
- `testthat::test_file("tests/testthat/test-e2e-boot-welcome-regression.R")`
- `testthat::test_file("tests/testthat/test-global-source-manifest-contract.R")`
- `testthat::test_file("tests/testthat/test-source-manifest-contract.R")`
- `testthat::test_file("tests/testthat/test-production-contracts.R")`
- `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")`

When editing the UI asset contract, run `testthat::test_file("tests/testthat/test-ui-asset-manifest-contract.R")` first. This test intentionally uses the manifest’s `ui_asset_js_order_rules` and `ui_asset_js_render_plan` helpers instead of maintaining second independent order/render lists. Keep expectations compatible with the project’s installed `testthat` version; avoid optional expectation arguments that are not supported in older local environments.

### Attached welcome-screen animation contract

Returning from Kişiselleştirme to an already-attached Ana Söyleşi welcome screen must reboot the modern welcome animation stack after the welcome container is visible.

Current contract:

- The attached welcome-screen path in `R/server_welcome_handlers.R` must still show `#welcome_fullscreen_container`, hide `#chat_content_container`, refresh recent chats, and then send `initModernWelcome`.
- The same path must also send `initPersonalGreeting` so the personalized greeting sequence is not skipped.
- `www/js/character_manager.js` must not destroy and reinitialize the modern welcome neural canvas while that canvas is hidden or has zero dimensions. Hidden character changes may update stored/accent state, but visible canvas initialization should happen when the welcome screen is visible again.
- `www/js/shiny_message_handlers.js` owns `initModernWelcome` bootstrapping and must continue to initialize the video player, modern neural canvas, and greeting text through the existing boot/retry path.
- This behavior must preserve the existing UX: selecting a different character from Kişiselleştirme and then directly opening Ana Söyleşi should immediately show the left video, right neural animation, and dynamic greeting without requiring a quick action or Yeni Söyleşi round trip.

Protected by:

- `tests/testthat/test-e2e-boot-welcome-regression.R`
- `tests/testthat/test-frontend-selector-contract.R`

Focused validation:

- `testthat::test_file("tests/testthat/test-e2e-boot-welcome-regression.R")`
- `testthat::test_file("tests/testthat/test-frontend-selector-contract.R")`

High-risk frontend anchors are protected by `tests/testthat/test-frontend-selector-contract.R`. This test covers:

- chat input and send/stop wiring,
- centralized chat-input helper export and reuse by adjacent JS,
- stale `send_btn` regression protection for the main chat send/stop contract,
- quick-action button DOM wiring,
- TTS visualizer anchors and null-init guard,
- Bilge Yolaç dynamic tool-block lookup without unsafe selector interpolation.
- welcome and chat content containers,
- file upload, drag/drop, and file button selectors,
- File Manager attach checkbox and silent attach-state contracts,
- STT visualizer anchors,
- Bilge Yolaç prompt, output, welcome, and streaming anchors.
- stale selector regression scanning across all `www/js/*.js` files,
- message and CodeMirror chat-root observer cleanup and Shiny reconnect contracts,
- ChartLab rendering through current chat roots only, with stale `chat_content_wrapper`, broad `document.body`, and dynamic wrapper class selector regression protection,
- single-owner `showNeuralAnimation` Shiny handler wiring with `window.startNeuralWelcomeAnimation(...)` delegated animation startup,
- dynamic drag/drop getter usage for chat upload and File Manager upload surfaces,
- centralized File Manager attach-state handler registration.

When changing UI IDs/classes or JS selectors, update the actual UI, the JS handler, and the selector contract test together. Prefer robust delegated handlers for dynamic UI such as DataTables redraws. Do not remove working fallback selectors unless the UI contract has been verified.

File names must not be interpolated directly into CSS attribute selectors. For File Manager attach checkboxes, compare `data-filename` as a plain string after selecting `input.attach-checkbox[data-filename]`. This avoids hidden browser selector errors for filenames containing quotes, brackets, backslashes, or other selector-sensitive characters.

The same rule applies to Bilge Yolaç streaming tool identifiers. Do not interpolate streamed `toolId` values directly into CSS attribute selectors. Use a helper that selects `.cc-tool-block[data-tool-id]` elements and compares `data-tool-id` as a plain string. This prevents hidden `querySelector()` syntax failures when streamed tool IDs contain quotes, brackets, backslashes, or other selector-sensitive characters.

The File Manager attach-state browser handler must remain centralized in `R/helpers_file_manager_attach_client.R`. Do not move the inline JavaScript registration back into `R/module_file_manager.R`, and do not duplicate `Shiny.addCustomMessageHandler(nsPrefix + 'setAttachState', ...)` inside the module. The global `initAttachHandlerOnce` no-op handler should be registered once, while namespace-specific `setAttachState` handlers remain scoped by module namespace.

Because some JS files can contain invalid UTF-8 byte sequences in Windows VM environments, selector-contract tests that scan JS files must use the binary-safe reader pattern with `readBin(...)`, `iconv(..., sub = "byte")`, and byte-safe fixed matching. Do not replace this with plain `readLines(..., encoding = "UTF-8")` plus ordinary `grepl()` over unnormalized text. The selector contract test should continue to scan every `www/js/*.js` file for stale `message_input` references and should keep explicit checks that `app_core.js` does not reintroduce `#_content_container`. The same selector-contract scan must continue to reject stale `chat_content_wrapper` references across `www/js/*.js` and must keep the `showNeuralAnimation` handler centralized.

### E2E/race regression test foundation contract

The repository now has a deterministic E2E-style regression foundation for quick actions and true-streaming request lifecycle behavior. It intentionally uses `testthat` plus local state/service stubs instead of adding a browser automation dependency. This keeps the suite compatible with offline/on-prem Windows VM environments and avoids real DB, real LLM, TTS/STT, image endpoint, or public internet requirements.

The latest behavioral coverage pass also strengthens focused unit/integration checks for quick-action routing, duplicate quick-action configuration protection, LLM response parsing, request-scoped send-message cleanup, File Manager storage and upload policy, MCP Excel context cleanup, refresh guard behavior, Bilge Yolaç stale finalization and directory observation, document-summary CLI context reset, and SSO identity readiness. These tests are intentionally fast, deterministic, and service-free: they must not require a real DB, real LLM endpoint, real SSO/Keycloak server, browser automation, API keys, or internet access.

The newer offline behavior and `testServer` smoke coverage should be preferred over brittle static string checks when adding regression coverage. It exercises follow-up helpers, chat title/saved-chat runtime helpers, summarization modes and prompt builders, language/code detection, AI Expert TTS chunking, common utilities, ChartLab spec inference, markdown safety and HTML builders, quick-action name resolution, admin tag counts, `dataframeToMarkdown()`, SSO/JWT edge cases, LLM post-processing, SSE chunk decoding, Bilge Yolaç stream-json chunk parsing, LLM tool formatters/`fast_profile`, deep-analysis detail configuration, and settings/visual/startup/file/chat observer smoke paths. Source-once helper bootstraps, ASCII anchors for byte-sensitive scans, `skip_if_not_installed(...)` guards, and save/restore of globals/options are intentional Windows/VM stability patterns; do not remove them just to make a test look shorter. These offline tests do not replace full runtime, browser, VM/SSO, or DB validation for risky code changes.

Current files:

- `tests/testthat/helper_e2e_race_harness.R`
- `tests/testthat/test-e2e-quick-actions-streaming-regression.R`
- `tests/testthat/test-sso-session-identity-smoke.R`
- `tests/testthat/test-streaming-abort-lifecycle-smoke.R`
- `tests/testthat/test-audio-lifecycle-owner-smoke.R`

The quick-action/streaming slice also protects the browser-side duplicate-click boundary for welcome quick-action buttons. `www/js/shiny_message_handlers.js` must debounce the same action/model pair before calling `Shiny.setInputValue('quick_template', ...)`, temporarily disable the clicked button with `aria-disabled`, and then restore it after the debounce window. The deterministic harness in `helper_e2e_race_harness.R` models this client gate, and `test-e2e-quick-actions-streaming-regression.R` checks both the state behavior and the static JS token order so the debounce guard remains before the Shiny event.

Additional behavioral contract tests:

- `tests/testthat/test-quick-action-routing.R`: verifies every quick-action id resolves to the expected tool family, setting flag, and configured model; applying an action leaves only one tool flag active; the real `mergen_determine_tool_family()` routing helper is covered; MCP Excel without files does not route to `mcp_excel`; `skip_mcp_once` has precedence; duplicate ids/families/flags and unexpected model ids remain protected; and the quick-action/file-policy boundary stays aligned so summarization rejects Excel while MCP Excel cleanup keeps only one Excel file and removes non-Excel or excess selections.
- `tests/testthat/test-llm-content-reasoning-fallback.R`: verifies `message$content`, top-level `message$content`, `delta$content`, choice `text`, top-level `response$text`, nested text nodes, `reasoning_content`, choices-free top-level `reasoning_content`, and reasoning fallback enabled/disabled behavior.
- `tests/testthat/test-send-message-request-lifecycle-contract.R`: verifies current/stale/stopped request states, stopped active-request cleanup, request-scoped typing-wrapper cleanup, stale cleanup paths that must not remove a newer request’s wrapper, and cleanup that fails closed when `active_request_id` cannot be read.
- `tests/testthat/test-file-manager-policy-contract.R`: verifies upload policy helpers, user id normalization, user-specific upload folder derivation, invalid-user persistence prevention, summarization-mode Excel rejection, MCP Excel cleanup, and stale refresh guard behavior.
- `tests/testthat/test-upload-validator.R`: verifies too-large file rejection, unsafe filename rejection, ASCII control-byte filename rejection, unsupported extension rejection when a whitelist exists, dotted whitelist entries and uppercase visible extensions, valid UTF-8 Turkish filename acceptance, and invalid UTF-8 filename rejection.
- `tests/testthat/test-claude-code-run-lifecycle-contract.R`: verifies stale/active Bilge Yolaç finalization, stale directory observation suppression, early-abort cleanup, blocked-message payload safety, stop finalization, and document-summary CLI context reset.
- `tests/testthat/test-e2e-sso-identity-readiness-regression.R`: verifies refreshable modules wait for SSO identity readiness, do not refresh while `authenticated=TRUE` but `auth_ready=FALSE`, refresh immediately when already ready, preserve local non-SSO behavior, and can be run individually without depending on full-suite bootstrap side effects.

Additional media/audio race files:

- `tests/testthat/helper_e2e_media_audio_harness.R`
- `tests/testthat/test-e2e-media-audio-state-regression.R`

Additional file-context and refresh race files:

- `tests/testthat/helper_e2e_file_context_harness.R`
- `tests/testthat/test-e2e-file-context-regression.R`

Additional saved-chat/history/gallery race files:

- `tests/testthat/helper_e2e_chat_persistence_harness.R`
- `tests/testthat/test-e2e-chat-persistence-regression.R`

Additional health dashboard race files:

- `tests/testthat/helper_e2e_health_dashboard_harness.R`
- `tests/testthat/test-e2e-health-dashboard-regression.R`

Additional boot/welcome regression file:

- `tests/testthat/test-e2e-boot-welcome-regression.R`

Additional premium reasoning / thinking UI race files:

- `tests/testthat/helper_e2e_reasoning_ui_harness.R`
- `tests/testthat/test-e2e-premium-reasoning-ui-regression.R`

Additional streaming client request-id safety file:

- `tests/testthat/test-e2e-streaming-client-request-id-regression.R`

Additional SSO identity readiness race files:

- `tests/testthat/helper_e2e_sso_identity_harness.R`
- `tests/testthat/test-e2e-sso-identity-readiness-regression.R`

The saved-chat/history/gallery slice follows the same deterministic `testthat` strategy. It must not require a real browser, real production DB, real LLM, real image-generation endpoint, TTS/STT endpoint, or public internet. It models saved-chat ordering, final-answer persistence idempotency, stale delete/load events, loaded-chat TTS suppression, history refresh cache safety, and user-scoped image gallery refresh behavior through local state stubs.

The health dashboard slice follows the same deterministic testthat strategy. It must not require a real browser, real production DB, real LLM, real TTS/STT endpoint, real image-generation endpoint, or public internet. It models rendered health tab snapshots, secret redaction, public endpoint skip behavior before network probing, idempotent refresh application, stale refresh suppression, timestamp/tooltip cleanup message contracts, and static wiring contracts for R/helpers_health_checks.R, R/module_health.R, ui.R, and www/js/health_dashboard.js.

The boot/welcome slice follows the same deterministic `testthat` strategy. It must not require a real browser, real production DB, real LLM, real TTS/STT endpoint, real image-generation endpoint, or public internet. It models non-SSO test boot safety, `MERGEN_RUN_APP=false` and `MERGEN_DISABLE_FUTURES=true` guard behavior, valid `create_mergen_app()` construction, modern welcome-screen rendering, quick-action button wiring, recent-chat ordering, prompt-send separation, browser/localStorage restore wiring, and the requirement that loading old chat state must not trigger TTS or music side effects. It also protects UTF-8 Turkish text in rendered welcome HTML and static client contracts.

The premium reasoning / thinking UI slice follows the same deterministic `testthat` strategy. It must not require a real browser DOM, real production DB, real LLM, real SSE endpoint, real TTS/STT endpoint, real image-generation endpoint, or public internet. It models PremiumReasoning-style request-scoped panel lifecycle behavior through local state stubs and protects duplicate/flicker prevention, stale reasoning callback suppression, stream-start migration into the assistant bubble, idempotent reset/finalization, simulated reasoning cleanup, and strict separation between visible answer text and persisted reasoning traces.

The streaming client request-id safety slice follows the same deterministic `testthat` strategy. It must not require a real browser DOM, real production DB, real LLM, real SSE endpoint, real TTS/STT endpoint, real image-generation endpoint, or public internet. It protects the wiring between server-side request ids and browser custom-message handlers by checking that `premiumReasoningStart`, `premiumReasoningStreamStart`, `initStreamingMessage`, `streamingReasoningDelta`, `streamingDelta`, `streamingUpdate`, and `finalizeStreamingMessage` carry or honor `requestId` where required. It also protects client-side stale callback suppression and duplicate finalization guards so old async stream/reasoning callbacks cannot contaminate a newer active request.

The SSO identity readiness slice follows the same deterministic `testthat` strategy. It must not require a real browser, real Keycloak server, real production DB, real LLM, real TTS/STT endpoint, real image-generation endpoint, or public internet. It models refreshable File Manager and Image Gallery module wiring while the session still has a temporary `user_id = 0`, verifies that user-scoped refresh happens only after SSO authentication and identity readiness are complete, verifies that already-ready SSO sessions refresh immediately without waiting for a stale observer event, and verifies that local non-SSO mode is not changed by the SSO auth-ready hook.

The file-context slice follows the same deterministic `testthat` strategy. It must not require a real browser, real production DB, real persistent file store, real LLM, TTS/STT endpoint, image endpoint, or public internet. It models File Manager upload/context state, summarization-mode extension restrictions, MCP Excel-only attachment behavior, single-Excel enforcement, invalid or early user-id refresh skips, stale refresh request protection, and browser/client restore with stale attachment IDs through local state stubs.

The saved-chat/history/gallery slice intentionally stays browserless. It protects the server-side state and wiring contracts that are most likely to regress before a manual VM/browser run: saved chat ordering after a final answer, exactly-once persistence for a request, stale load suppression after delete, no TTS autoplay when loading old chats, invalid or early user-id refresh skips for history/gallery, and user-scoped gallery cache replacement.

The media/audio slice follows the same deterministic `testthat` strategy. It must not require a real browser, real `Audio`, microphone access, DB, LLM, TTS/STT endpoint, image endpoint, or public internet. It models TTS queueing, STT modal audio suppression, and background-music exclusivity with local state stubs, and it also checks that the key JS hook contracts remain present in `music_manager.js`, `tts_manager.js`, `stt_client.js`, and `premium_reasoning.js`.

Because Windows VM environments can expose JS comments or other text as native/ANSI rather than valid UTF-8, the media JS contract test reads JS files as raw bytes and normalizes non-ASCII bytes before searching for ASCII hook names. Do not replace this byte-safe reader with plain `readLines(..., encoding = "UTF-8")` or `grepl(..., perl = TRUE)` over unnormalized text; that can reintroduce invalid UTF-8 warnings and false-negative contract failures on the VM.

The first slice protects these contracts:

- quick-action clicks select the expected tool/model mode,
- quick-action clicks hide the welcome state and show a ready-made intro message,
- quick-action clicks must not trigger an LLM request by themselves,
- quick-action intro messages must not be persisted to DB, added to saved chats, or included in model context,
- rapid quick-action clicks must converge to one active tool mode,
- the same quick-action/model pair double-clicked within the client debounce window must be suppressed before it becomes a Shiny event,
- rapidly switching to a different quick action must still be allowed and the last selected tool/model state must win,
- a prompt sent immediately after a quick-action click must produce exactly one user request,
- SSE visible deltas and reasoning deltas must remain separate,
- stream finalization must be idempotent for a request,
- stale request finalization must not update the newer active request,
- stop-generation state must be request-scoped and must not poison the next request,
- simulated reasoning phases must not be persisted as real reasoning.

The media/audio slice protects these contracts:

- background music must have at most one active audio source,
- stale playlist responses must not overwrite newer music state,
- character or mode changes must stop the previous track before starting the next flow,
- TTS chunks must be queued and played in chunk-index order,
- TTS playback must duck background music and must not unduck it until the queue drains,
- TTS stop must clear the queue, current audio, and reported playing state,
- STT start must fully duck/silence background music,
- ordinary TTS/music unduck calls must not restore music while STT is active,
- STT cleanup must restore music state safely,
- navigation or new-chat cleanup must not leave stale TTS, STT, or music state behind,
- static JS contracts must continue to expose the expected audio/reasoning hooks.

The file-context slice protects these contracts:

- summarization upload validation must reject Excel files while accepting valid UTF-8 Turkish document filenames,
- MCP Excel context cleanup must remove non-Excel files, stale selection ids, and excess Excel files,
- refresh request guards must reject invalid or stale request ids before applying refreshed file state,
- upload validation must reject invalid UTF-8 filenames and ASCII control-byte filenames in addition to path traversal, unsupported extensions, and oversized files, while accepting valid UTF-8 Turkish filenames.

Use raw-byte checks for ASCII control characters in filenames; do not replace them with `grepl("[[:cntrl:]]", ..., useBytes = TRUE)`, because that can misclassify valid UTF-8 Turkish characters on Windows/R locales.

- supported uploads must appear in File Manager table/state,
- Model Context attachment toggles must update the parent session context,
- summarization mode must reject unsupported file types and keep supported document types,
- MCP/Excel mode must reject non-Excel files,
- MCP/Excel mode must keep only one Excel file attached,
- switching MCP/Excel mode on must remove non-Excel and excess Excel selections,
- invalid user IDs such as `0`, `unknown`, empty, or `NULL` must not wipe existing File Manager state during refresh,
- SSO-not-ready refresh attempts must skip safely without mutating current file state,
- stale refresh results must not overwrite a newer refresh result,
- refresh restore must preserve previously attached files by display name,
- browser/client restore must ignore ghost attachment IDs safely,
- static File Manager JS/server hook contracts must continue to expose upload, file action, attach toggle, and silent attach-state behavior.

The saved-chat/history/gallery slice protects these contracts:

- saved chat ordering must follow last activity after a new final answer,
- stream/finalization persistence must be idempotent for the same request id,
- loading an old saved chat must not trigger TTS autoplay,
- deleting the current chat must return safely to the welcome state,
- stale load events for a just-deleted chat must be ignored,
- history refresh attempts with invalid or early user ids must not wipe the last valid cache,
- image gallery refresh must remain user-scoped,
- invalid gallery refresh attempts must not wipe the last valid user cache,
- static contracts in `server_observers_saved_chats.R`, `module_saved_chats.R`, `module_chat_history.R`, `module_image_gallery.R`, and `server_module_wiring.R` must remain present.

The health dashboard slice protects these contracts:

- raw secret values such as API keys, tokens, passwords, and credentials must not leak into health check output or rendered tab snapshots,
- public internet endpoints must not be called from the health dashboard; they must be skipped with a warning before any network probe,
- local/on-prem endpoint checks are represented by deterministic stubs in tests and must not require public internet,
- a refresh result must be applied at most once for a refresh id,
- stale refresh results must not overwrite newer dashboard state,
- timestamp and tooltip cleanup custom-message contracts must remain wired,
- health dashboard JavaScript must not introduce public URL dependencies,
- offline refresh, public URL guard, and cleanup hook contracts must remain present in R/helpers_health_checks.R, R/module_health.R, ui.R, and www/js/health_dashboard.js.

The boot/welcome slice protects these contracts:

- app.R can be sourced in non-SSO test mode without launching the Shiny app,
- test boot must keep future execution disabled or sequential,
- `validate_boot_state()` and `create_mergen_app()` must remain valid,
- the modern welcome screen must render the expected root, greeting, quick-action, and recent-chat anchors,
- quick-action buttons must preserve `data-action-id`, `data-action-model`, and `_handleQuickAction` wiring,
- recent chats on the welcome screen must remain ordered by latest activity,
- quick-action input and normal prompt-send input must remain separate,
- browser/localStorage restore must route through `load_chat_from_storage`,
- browser/localStorage restore must not trigger TTS, audio, or music side effects for old chats,
- Turkish characters must remain intact in welcome HTML and static JS/R contract checks.

The premium reasoning / thinking UI slice protects these contracts:

- starting premium reasoning for one request must create at most one live panel,
- repeated start events for the same request must not duplicate or flicker the panel state,
- a new request must cleanly replace the previous active reasoning shell,
- stale reasoning deltas from an old request must not contaminate the active request,
- stale stream-start events from an old request must be ignored,
- stream start for the active request must migrate the reasoning panel into the assistant bubble model,
- reset/finalization must be idempotent for a request,
- simulated reasoning phases for non-thinking models must be removed on visible stream start,
- simulated reasoning must never be persisted as real reasoning,
- visible answer text and reasoning trace text must remain separate through finalization,
- static JS/R wiring contracts for `premiumReasoningStart`, `premiumReasoningStreamStart`, `streamingReasoningDelta`, `finalizeStreamingMessage`, `reasoning_content`, and `reasoning_trace_value` must remain present.

The streaming client request-id safety slice protects these contracts:

- `send_message()` must create one request id and pass it into both the reasoning shell and true-streaming path,
- `handle_true_streaming_mode()` must prefer `ctx$request_id` and only generate a new request id as a fallback,
- true-streaming browser messages must include `requestId` for `premiumReasoningStreamStart`, `initStreamingMessage`, `streamingReasoningDelta`, `streamingDelta`, `streamingUpdate`, and `finalizeStreamingMessage`,
- `www/js/streaming_manager.js` must store the active message request id, ignore stale streaming payloads, and finalize a message at most once,
- `www/js/premium_reasoning.js` must track the active reasoning request id and ignore stale reasoning deltas or stream-start callbacks,
- server-side request lifecycle guards and client-side stale callback guards must remain aligned,
- maintainability ratchet limits must remain strict; do not loosen thresholds to make these checks pass.

The SSO identity readiness slice protects these contracts:

- authenticated SSO sessions must still wait for `auth_ready = TRUE`; `authenticated = TRUE` alone must not trigger user-scoped refresh with temporary user ids.
- refreshable modules must not run user-scoped refresh work with temporary or invalid user ids such as `0`, empty, `unknown`, or `NULL`,
- File Manager must receive `auth_ready_provider = identity$is_auth_ready` before being attached as a refreshable module,
- File Manager and Image Gallery refresh hooks must wait for SSO authentication and identity readiness when SSO is still in progress,
- if SSO authentication and identity readiness are already complete before observer registration, the refresh callback must run immediately instead of waiting for an event that already happened,
- local non-SSO mode must remain a no-op for SSO auth-ready refresh hooks,
- `R/server_module_wiring.R` must keep the File Manager and Image Gallery auth-ready refresh wiring visible and testable,
- `R/server_runtime_context.R` must bootstrap all helper functions from `R/helpers_server_runtime_contracts.R`, not only `is_server_runtime_context()`. Individually run tests must not depend on helper functions left in the global environment by earlier full-suite tests.
- the slice must remain test-only under `tests/testthat/` and must not require updates to `global.R` or runtime source order,
- maintainability ratchet limits must remain strict; do not loosen thresholds to make these checks pass.

Focused validation:

    testthat::test_file("tests/testthat/test-e2e-boot-welcome-regression.R")
    testthat::test_file("tests/testthat/test-e2e-premium-reasoning-ui-regression.R")
    testthat::test_file("tests/testthat/test-e2e-streaming-client-request-id-regression.R")
    testthat::test_file("tests/testthat/test-e2e-sso-identity-readiness-regression.R")
    testthat::test_file("tests/testthat/test-e2e-quick-actions-streaming-regression.R")
    testthat::test_file("tests/testthat/test-e2e-media-audio-state-regression.R")
    testthat::test_file("tests/testthat/test-e2e-file-context-regression.R")
    testthat::test_file("tests/testthat/test-e2e-chat-persistence-regression.R")
    testthat::test_file("tests/testthat/test-e2e-health-dashboard-regression.R")

Related focused tests:

    testthat::test_file("tests/testthat/test-send-message-request-lifecycle-contract.R")
    testthat::test_file("tests/testthat/test-quick-action-routing.R")
    testthat::test_file("tests/testthat/test-llm-content-reasoning-fallback.R")
    testthat::test_file("tests/testthat/test-file-manager-policy-contract.R")
    testthat::test_file("tests/testthat/test-upload-validator.R")
    testthat::test_file("tests/testthat/test-claude-code-run-lifecycle-contract.R")
    testthat::test_file("tests/testthat/test-send-message-prompting-contract.R")
    testthat::test_file("tests/testthat/test-llm-stream-io-contract.R")
    testthat::test_file("tests/testthat/test-streaming-should-stop.R")
    testthat::test_file("tests/testthat/test-sse-worker-export-contract.R")
    testthat::test_file("tests/testthat/test-file-manager-context-policy-contract.R")
    testthat::test_file("tests/testthat/test-file-manager-refresh-guard-contract.R")
    testthat::test_file("tests/testthat/test-file-manager-state-runtime-contract.R")
    testthat::test_file("tests/testthat/test-file-manager-module-policy-wiring.R")
    testthat::test_file("tests/testthat/test-resolve-uploaded-file.R")
    testthat::test_file("tests/testthat/test-server-chat-persistence-wiring-contract.R")
    testthat::test_file("tests/testthat/test-health-check-formatters.R")
    testthat::test_file("tests/testthat/test-health-check-paths.R")
    testthat::test_file("tests/testthat/test-health-check-env-contract.R")
    testthat::test_file("tests/testthat/test-health-check-runtime-contract.R")
    testthat::test_file("tests/testthat/test-maintainability-ratchet.R")
    source("tests/scripts/maintainability_report.R", encoding = "UTF-8")

Full strict validation remains:

    source("tests/testthat.R", encoding = "UTF-8")

`tests/testthat/test-resolve-uploaded-file.R` must remain safe to run individually with `testthat::test_file(...)`. It should explicitly bootstrap the minimal File Store source chain it tests instead of relying on full-suite side effects or functions left in the global environment by earlier tests. This protects diagnostic workflows where a single resolver/file-store test is run after an E2E failure.

`tests/testthat/test-llm-reasoning-request-overrides.R` must remain safe and warning-free when run individually with `testthat::test_file(...)`. Its bootstrap should prepare a valid temporary test log directory, preserve any inherited `MERGEN_LOG_DIR` directory if present, and redirect the logger file appender to a test-local log file before sourcing `R/config_api.R`. This protects the strict suite from missing log-file warnings under `stop_on_warning = TRUE` while still testing reasoning request override contracts.

The saved-chat/history/gallery E2E slice is also test-only and must remain under `tests/testthat/`. It should not require updates to `global.R`, should not be sourced by runtime code, and should not affect the runtime maintainability ratchet because `tests/scripts/maintainability_report.R` evaluates runtime files only.

The health dashboard E2E slice is also test-only and must remain under tests/testthat/. It should not require updates to global.R, should not be sourced by runtime code, and should not affect the runtime maintainability ratchet because tests/scripts/maintainability_report.R evaluates runtime files only.

The SSO identity readiness E2E slice is also test-only and must remain under `tests/testthat/`. It should not require updates to `global.R`, should not be sourced by runtime code, and should not affect the runtime maintainability ratchet because `tests/scripts/maintainability_report.R` evaluates runtime files only.

Do not replace this foundation with Playwright, Cypress, shinytest2, or another browser-level dependency unless the dependency is explicitly available in the offline/on-prem deployment environment or vendored/installed through an approved offline process. Browser-level tests may be added later as a separate layer, but they should not weaken or remove these deterministic contract tests.

### LLM worker tool-result formatting contract

The non-streaming LLM worker is intentionally split across three helper layers. Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/helpers_llm_worker_payload.R",       encoding = "UTF-8")
safe_source("R/helpers_llm_worker_tool_results.R", encoding = "UTF-8")
safe_source("R/helpers_llm_worker.R",               encoding = "UTF-8")
```

Responsibilities:

* `R/helpers_llm_worker_payload.R`: chat-history-to-message conversion, system-message merging, chart intent detection, fallback chart hooks, chart summaries, and automatic insight text helpers.
* `R/helpers_llm_worker_tool_results.R`: MCP tool-result logging, dataframe/chart/plain-text result formatting, dataframe-to-markdown conversion for second-pass prompts, and aggregation of formatted tool results.
* `R/helpers_llm_worker.R`: public `call_llm_worker(...)` runtime API, model/request assembly, MCP tool schema selection, API call handling, MCP tool execution orchestration, strict-data-only handling, second-pass orchestration, and final error normalization.

Do not move MCP tool-result formatting back into `R/helpers_llm_worker.R`; doing so can bring the worker back to the 800+ line threshold and blur the runtime orchestration boundary.

Race-condition contract:

* `call_llm_worker(...)` may prepare a `session_obj` from `settings$mcp_registry_snapshot` when the live Shiny session is missing or no longer has the needed file registry.
* MCP tool execution must use that prepared `session_obj`.
* Do not reintroduce `current_session <- if (!is.null(settings$shiny_session)) settings$shiny_session else NULL` in the MCP execution path. That bypasses the snapshot guard and can make async workers resolve files from stale or empty live session state.

Maintainability note:

* `tests/scripts/maintainability_report.R` counts simple `function(` patterns, including anonymous handlers in code and misleading examples in comments. Keep new helper files small, avoid unnecessary anonymous handlers in ratcheted files, and avoid comment text that accidentally contains patterns such as `= function(` unless truly needed.

Protected by:

```text
tests/testthat/test-llm-worker-payload-refactor-contract.R
tests/testthat/test-llm-worker-tool-results-refactor-contract.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-maintainability-ratchet.R
```


### Bilge Yolaç run lifecycle request-id contract

Bilge Yolaç normal streaming finalization must remain request-scoped. `R/module_claude_code.R` creates a `run_request_id`, stores it in `rv$active_request_id`, and carries it through `stream_env$request_id`. Any normal streaming completion path that calls `finalize_streaming()` for `Tamamlandı` or `Hata` must pass `request_id = env$request_id`.

This requirement is not cosmetic. `finalize_streaming()` intentionally accepts a request id so stale poll/callback results cannot clear the runtime state of a newer active Bilge Yolaç run. Do not reintroduce request-id-less normal completion or error finalization calls such as `finalize_streaming("Tamamlandı", ...)` or `finalize_streaming("Hata", ...)` without the request id.

The stop and timeout paths must also remain request-scoped. The normal success/error paths now follow the same stale-run safety boundary.

Early-abort paths before streaming starts must also clear state through the shared lifecycle helper. If a run has already called `cc_mark_active_run(rv, run_request_id)` but then fails preflight or process-start checks, use `cc_abort_run_before_streaming(rv, run_request_id)` instead of manually setting only `rv$is_running <- FALSE`. This prevents a blocked or failed pre-stream run from leaving stale `rv$active_request_id` state that could affect the next run. Blocked-run UI error payloads should go through `cc_send_run_blocked_message()` so the repeated `cc-add-message` error shape stays centralized and safely escaped.

Protected by:
- `tests/testthat/test-claude-code-run-lifecycle-contract.R`
- `tests/testthat/test-maintainability-ratchet.R`

Focused validation:
- `testthat::test_file("tests/testthat/test-claude-code-run-lifecycle-contract.R")`
- `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")`
- `source("tests/scripts/maintainability_report.R", encoding = "UTF-8")`
- `source("tests/testthat.R", encoding = "UTF-8")`

Validation after edits:
- These are documentation-only changes.
- Ensure README.md remains Turkish and UTF-8.
- Ensure CLAUDE.md remains English and UTF-8.
- Run a diff and confirm only README.md and CLAUDE.md changed.
- Do not run or change runtime code.
- Do not delete any existing documentation content.

### Bilge Yolaç directory-listing contract

Bilge Yolaç directory listing is intentionally split from the broad CLI helper file.

Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/helpers_claude_code_process.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_runtime_workdir.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_directory_listing.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_server_setup.R", encoding = "UTF-8")
```

Responsibilities:

* `R/helpers_claude_code_directory_listing.R`: directory path variant generation, relaxed directory listing, persistent storage display-name resolution, directory entry normalization, and the public-compatible `list_directory_contents()` helper.
* `R/helpers_claude_code.R`: Claude Code CLI run orchestration, CLI status/connection checks, output formatting, tool-use HTML formatting, and thinking-message selection.

Do not move `list_directory_contents()` or its directory display-name/path-variant logic back into `R/helpers_claude_code.R`. Keeping this boundary prevents `R/helpers_claude_code.R` from returning to the 25+ function maintainability threshold.

Race-condition contracts:

* Directory listing must not run before the SSO/user identity readiness check in `R/helpers_claude_code_server_setup.R`.
* Directory refresh results must remain protected by `dir_refresh_guard$is_latest(refresh_id)` so stale refreshes cannot overwrite newer UI state.
* Display-name resolution must continue to use persistent file-store metadata so timestamp/hash storage names do not leak into the Bilge Yolaç directory UI.

Protected by:

```text
tests/testthat/test-claude-code-directory-listing-contract.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-claude-code-dir-ui-refactor-contract.R
tests/testthat/test-maintainability-ratchet.R
```

### Windows VM real preflight SSO contract

tests/scripts/run_vm_preflight_real.R is the production-like Windows VM preflight entry point. It must not silently pass when the VM is accidentally running in local/non-SSO identity mode, and it must fail early when mandatory production environment variables are missing.

Current contract:

- MERGEN_PREFLIGHT_REQUIRE_SSO defaults to TRUE.
- When MERGEN_PREFLIGHT_REQUIRE_SSO=TRUE, the preflight must fail unless SSO_ENABLED=TRUE.
- Local or developer smoke runs may explicitly set MERGEN_PREFLIGHT_REQUIRE_SSO=FALSE.
- LOCAL_LLM_ENDPOINT, DB_DSN, and AI_KEYS_MASTER are mandatory for the real preflight.
- When SSO is enabled, SSO_KEYCLOAK_URL is also mandatory.
- Missing mandatory environment variables must fail fast before app boot with a clear error message.
- After app.R is sourced and validate_boot_state() passes, the preflight must verify that SSO_ENABLED is active and that SSO_CONFIG contains usable keycloak_base_url, issuer_url, auth_endpoint, logout_endpoint, token_endpoint, client_id, and realm values.
- Derived SSO URL fields must remain valid http:// or https:// URLs.
- The preflight sources `tests/scripts/helpers_vm_preflight_checks.R` for reusable VM checks instead of keeping every probe inline in `run_vm_preflight_real.R`.
- The default VM preflight includes core writable path checks, atomic-write probe, UTF-8 file write/read roundtrip, live `current_user_id` provider contract, SSO auth-ready immediate refresh contract, real DB health check, and local LLM endpoint reachability.
- `run_vm_preflight_real.R` must restore any process-wide environment variables it changes on exit. In particular, it must not leak `MERGEN_DISABLE_FUTURES`, `MERGEN_RUN_APP`, or `MERGEN_SQL_LOADER_STRICT` into later tests or developer commands in the same R session.
- File Store roundtrip validation is optional and must remain disabled by default. It should run only when `MERGEN_PREFLIGHT_CHECK_FILE_STORE=TRUE` is explicitly set, because it touches real shared/indexed file storage and is a deeper diagnostic rather than the normal fast VM preflight path.
- Expected preflight degradations that should not fail the run should be printed as `INFO:` or `WARN:` console lines, not emitted through `warning()`, because the strict suite uses `stop_on_warning = TRUE`.
- Do not weaken this preflight into a generic boot-only check. Boot, DB, storage, atomic-write, and LLM endpoint checks are necessary but not sufficient for the Windows VM production profile.

This contract prevents a real VM validation run from passing while the app is actually using the local process user instead of the authenticated SSO user. That failure mode can mask user-scoped saved-chat, history, gallery, file-manager, and DB persistence regressions.

The VM preflight also protects the post-auth refresh timing contract. If SSO authentication and identity readiness are already complete before a refreshable module registers its auth-ready observer, `serverRuntimeOnSsoAuthReady(...)` must run the callback immediately instead of waiting for an event that has already happened. This prevents File Manager, Image Gallery, and similar refreshable modules from missing their first user-scoped refresh after SSO login.

Focused guard behavior:

- tests/testthat/test-vm-preflight-guard-contract.R keeps the missing-env-var failure path isolated from the SSO guard by setting MERGEN_PREFLIGHT_REQUIRE_SSO=FALSE.
- Keep that test focused on missing mandatory env vars. Do not make it depend on child-process stdout/stderr parsing.

The helper contract test must stay static and fast. It should inspect the helper/preflight script contracts without sourcing `app.R`, running the real VM preflight, touching the real DB, contacting the LLM endpoint, or performing the optional File Store roundtrip.

Protected by:

    tests/testthat/test-vm-preflight-contract.R
    tests/testthat/test-vm-preflight-guard-contract.R
    tests/testthat/test-vm-preflight-helper-contract.R

### User session initialization contract

Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/server_init_forward_refs.R",  encoding = "UTF-8")
safe_source("R/helpers_user_session_identity.R", encoding = "UTF-8")
safe_source("R/server_init_user_session.R",  encoding = "UTF-8")
safe_source("R/helpers_server_runtime_contracts.R", encoding = "UTF-8")
safe_source("R/server_runtime_context.R",    encoding = "UTF-8")
safe_source("R/server_runtime_function_slot.R", encoding = "UTF-8")
safe_source("R/server_module_wiring.R",      encoding = "UTF-8")
safe_source("R/server_init_session_state.R", encoding = "UTF-8")
safe_source("R/server_init_chat_runtime.R",  encoding = "UTF-8")
```

Server runtime contract helper split:

- R/helpers_server_runtime_contracts.R owns the low-level runtime validation and error helpers used by the server runtime context layer.
- R/server_runtime_context.R owns runtime context orchestration, context attach/require helpers, refreshable module registration, and SSO auth-ready refresh behavior.
- Do not move is_server_runtime_context(), .server_runtime_stop(), .server_runtime_require_context(), .server_runtime_require_values(), .server_runtime_require_functions(), or .server_runtime_invoke_auth_ready_callback() back into R/server_runtime_context.R.
- serverRuntimeOnSsoAuthReady() must keep the already-auth-ready path and the observer-fired path on the same .server_runtime_invoke_auth_ready_callback() helper. This prevents immediate SSO refresh behavior and delayed observer refresh behavior from drifting apart.
- This boundary creates maintainability headroom under the 25-function file threshold without changing public runtime APIs.

Protected by:

- tests/testthat/test-server-runtime-context.R
- tests/testthat/test-source-manifest-contract.R
- tests/testthat/test-maintainability-ratchet.R
- tests/testthat/test-e2e-sso-identity-readiness-regression.R

`R/server_core_interaction_runtime.R` is sourced later in `global.R`, after observer/output helpers such as `R/server_outputs_downloads.R`. This is intentional: the core interaction binder depends on concrete observer/output functions and should not rely on forward placeholders.

- `R/helpers_user_session_identity.R` owns pure user-session identity helpers: `build_user_session_config()`, `apply_user_session_identity()`, `make_current_user_id_provider()`, and `make_user_session_data_accessors()`.
- `R/server_init_user_session.R` owns local/SSO identity setup orchestration and must be sourced after `R/helpers_user_session_identity.R`.
- Identity-related compatibility reads and writes to `session$userData` must flow through `make_user_session_data_accessors()` rather than new ad hoc assignments.
- `apply_user_session_identity()` must remain the public compatibility write path, but internally it should delegate to `make_user_session_data_accessors()`.
- SSO placeholder state such as `user_id = 0L`, `sso_active = TRUE`, and `auth_initialized = FALSE` should be written through the session-data accessor, not by loose assignments in server initialization code.
- Runtime code should prefer accessors exposed through `runtime_ctx$identity`.
- Identity display values should come from `identity$get_first_name` and `identity$get_display_name` rather than direct `session$userData` reads in `server.R`.
- Auth readiness should come from `identity$is_auth_ready`.

`R/server_runtime_context.R` owns the early server boot contract that carries identity, cache, forward references, session state, and chat runtime into `server.R` through one explicit context object.

The source-order contract is intentional: `R/helpers_user_session_identity.R` must load before `R/server_init_user_session.R`, and `R/server_init_user_session.R` must load before `R/server_runtime_context.R`. Do not collapse the helper back into the initializer unless a future refactor replaces it with an equally explicit and tested boundary.

`R/server_module_wiring.R` owns medium-level server module wiring through focused helper functions. It binds service modules, settings/forward references/Bilge Yolaç startup wiring, media modules, the file-preview/follow-up prelude, and the chat engine wiring boundary. Keep this helper sourced after `R/server_runtime_context.R` and before session/chat runtime initialization.

`R/server_core_interaction_runtime.R` sits one level above those wiring helpers: `server.R` calls `serverBindCoreInteractionRuntime(...)`, and that helper delegates File Manager setup to `serverBindFileManagerRuntime(...)` and saved-chat/history/gallery/welcome/download/message-search setup to `serverBindChatPersistenceModules(...)`.

In `server.R`, do not read identity values directly from `user_session` anymore. The expected contract is:

```r
runtime_ctx <- serverRuntimeContextInit(
  session = session,
  session_cache = session_cache,
  sso_state = sso_state,
  user_session = user_session
)

identity <- serverRuntimeRequireIdentity(
  runtime_ctx,
  required_values = c("user_config_rv"),
  required_functions = c(
    "resolve_current_user_id",
    "current_user_id_provider",
    "get_first_name",
    "get_display_name"
  ),
  owner = "server.R identity"
)

user_config_rv <- identity$user_config_rv
resolve_current_user_id <- identity$resolve_current_user_id
current_user_id_provider <- identity$current_user_id_provider
current_user_first_name <- identity$get_first_name
current_user_display_name <- identity$get_display_name
```

Identity accessors must be safe outside reactive consumers. When reading `user_config_rv` inside helper accessors, use `shiny::isolate(...)` or another explicit Shiny-safe pattern. Do not introduce unqualified Shiny calls in init/helper files when a namespaced call is practical; prefer `shiny::reactiveVal`, `shiny::reactiveValues`, `shiny::observeEvent`, `shiny::req`, and `shiny::isolate`.

Keep `R/helpers_user_session_identity.R` pure. It should not create Shiny observers, call the database, read Keycloak state directly, or depend on module wiring. It is a small testable boundary for identity/config shaping, live user-id provider construction, and centralized identity-related `session$userData` compatibility access. If identity orchestration changes are needed, make them in `R/server_init_user_session.R`; if only config shaping, compatibility reads/writes, or user-data accessor behavior changes, keep them in the helper and update `tests/testthat/test-user-session-identity-contract.R`.

Never read `sso_state$authenticated` directly during initialization checks such as `is.null(sso_state$authenticated)`. In production SSO, that field is reactive and direct reads can crash the app with “Can't access reactive value outside of reactive consumer.” Watch it with `shiny::observeEvent(sso_state$authenticated, ...)` and read it only inside a reactive consumer/handler.

Post-auth refreshable modules should use the `ServerRuntimeContext` refreshable-module contract instead of ad hoc `observeEvent(sso_state$authenticated, ...)` blocks in `server.R`. The low-level combined helper remains `serverRuntimeAttachRefreshableModule(...)`. File Manager is still wired through `serverBindFileManagerRuntime(...)`, and chat-persistence-related modules are still wired through `serverBindChatPersistenceModules(...)`; however, `server.R` should reach both through `serverBindCoreInteractionRuntime(...)`, not by calling them directly.

File Manager auth readiness must be injected through a validated identity section, not raw context access. In `serverBindFileManagerRuntime(...)`, use `identity <- serverRuntimeRequireIdentity(...)` and pass `auth_ready_provider = identity$is_auth_ready`. Do not reintroduce direct File Manager checks against `session$userData$auth_initialized`; that couples persisted-file refresh to SSO timing and can bring back user-id `0` refresh regressions.

Protected by:

```text
tests/testthat/test-server-user-session-context.R
tests/testthat/test-user-session-identity-contract.R
tests/testthat/test-server-runtime-context.R
tests/testthat/test-server-runtime-context-accessors.R
tests/testthat/test-server-core-interaction-runtime.R
tests/testthat/test-session-user-data-store.R
tests/testthat/test-server-module-wiring-contract.R
tests/testthat/test-server-module-wiring-runtime-bindings.R
tests/testthat/test-server-module-wiring-chat-engine.R
tests/testthat/test-server-boundary-contract.R
tests/testthat/test-server-live-user-provider-contract.R
tests/testthat/test-server-chat-persistence-wiring-contract.R
tests/testthat/test-effective-user-id.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-production-contracts.R
tests/testthat/test-file-manager-module-policy-wiring.R
```

### ServerRuntimeContext contract

`R/server_runtime_context.R` is a small boot-time context boundary, not a broad application framework.

Current accepted identity boundary: keep `server.R` using `identity <- serverRuntimeRequireIdentity(...)` followed by the existing local aliases (`user_config_rv`, `resolve_current_user_id`, `current_user_id_provider`, `current_user_first_name`, and `current_user_display_name`). Do not introduce `serverRuntimeBuildIdentityPorts()` or an `identity_ports` wrapper unless a future refactor removes an equal or greater amount of complexity and keeps the maintainability ratchet at or above the current baseline.

The context now exposes typed section accessors: `serverRuntimeRequireIdentity(...)`, `serverRuntimeRequireState(...)`, and `serverRuntimeRequireCache(...)`. Prefer these accessors in server wiring code when a helper needs a validated context section. They should fail early on missing or malformed boot sections and keep orchestration code from depending on undocumented `runtime_ctx$...` shape.

Its purpose is to reduce loose boot-state leakage in `server.R` and fail early when required boot objects are missing or malformed.

It currently covers only:

- `session_cache`
- `user_session` / live current-user providers / identity display accessors / auth-readiness provider
- `forward_refs`
- `state_bundle`
- typed section accessors for identity, state, and cache contracts: `serverRuntimeRequireIdentity(...)`, `serverRuntimeRequireState(...)`, and `serverRuntimeRequireCache(...)`
- file runtime objects in `runtime_ctx$file`, including file preview/follow-up prelude handles and the File Manager module handle
- `chat_runtime`
- late-bound runtime function slots are intentionally kept in `R/server_runtime_function_slot.R` instead of this file, to avoid growing `R/server_runtime_context.R` into a broader service locator
- narrowly registered module return objects in `runtime_ctx$modules`
- SSO auth-ready callback registration through `serverRuntimeOnSsoAuthReady(...)`, registered-module refresh wiring through `serverRuntimeRefreshModuleOnSsoAuthReady(...)`, and the higher-level refreshable-module wiring helper `serverRuntimeAttachRefreshableModule(...)`

Do not expand it casually into a large service locator. Add to it only when a server boot object is already created in `server.R`, has a clear required-function contract, and is passed across multiple downstream modules. `runtime_ctx$modules` is not a general global registry; use it narrowly for module return objects that need a validated runtime contract, such as File Manager and Image Gallery post-auth refresh wiring. This file is also close to the function-count ratchet, so adding new public helpers here must be offset by removing or extracting comparable complexity; otherwise the 25-function threshold can regress. The accepted SSO auth-ready refresh hardening intentionally kept the immediate-ready guard inline inside `serverRuntimeOnSsoAuthReady(...)` instead of adding new top-level helper functions, preserving the maintainability ratchet baseline of score `100/100`, `0` 25+ function files, and maximum function count `24`.

The file subsystem now has a focused FileRuntime boundary under `runtime_ctx$file`. Use `serverRuntimeAttachFilePrelude(...)`, `serverRuntimeAttachFileManager(...)`, and `serverRuntimeRequireFileRuntime(...)` for file prelude and File Manager handles instead of passing those objects through ad hoc local variables or direct `session$userData` reads. This boundary is intentionally narrow: it is for file-preview/follow-up prelude objects and `file_manager_data`, not a general registry for every file-related helper.

When code needs to read a registered module from the context, prefer `serverRuntimeGetModule(...)` over direct `ctx$modules$...` access. This keeps missing-module and missing-function failures explicit and testable. In `server.R`, post-auth module refreshes should normally use `serverRuntimeRefreshModuleOnSsoAuthReady(...)` rather than custom callbacks that manually inspect `ctx$modules`.

`serverRuntimeOnSsoAuthReady(...)` has an important race-condition contract: in SSO mode, if `ctx$sso_state$authenticated` is already true and `identity$is_auth_ready()` is already true when the helper is called, the callback must run immediately and the helper should not register an unnecessary observer. This covers the case where authentication finishes before File Manager, Image Gallery, or another refreshable module attaches its post-auth refresh hook.

Expected attach sequence in `server.R`:

```r
runtime_ctx <- serverRuntimeContextInit(...)

identity <- serverRuntimeRequireIdentity(...)

user_config_rv <- identity$user_config_rv
resolve_current_user_id <- identity$resolve_current_user_id
current_user_id_provider <- identity$current_user_id_provider
current_user_first_name <- identity$get_first_name
current_user_display_name <- identity$get_display_name

settings_bundle <- serverBindSettingsAndRefs(
  ...,
  runtime_ctx = runtime_ctx,
  ...
)

runtime_ctx <- settings_bundle$runtime_ctx

file_prelude_modules <- serverBindFilePreludeModules(
  session = session,
  runtime_ctx = runtime_ctx
)

runtime_ctx <- file_prelude_modules$runtime_ctx

file_runtime <- serverRuntimeRequireFileRuntime(
  runtime_ctx,
  require_prelude = TRUE,
  require_manager = FALSE
)

runtime_ctx <- serverRuntimeAttachState(runtime_ctx, ...)

state <- serverRuntimeRequireState(...)

core_interaction <- serverBindCoreInteractionRuntime(
  ...,
  runtime_ctx = runtime_ctx,
  media_modules = media_modules,
  user_config_provider = function(default = NULL) {
    runtime_ctx$identity$get_user_config(default = default)
  },
  user_first_name_fn = function(default = "") {
    current_user_first_name(default = default)
  }
)

runtime_ctx <- core_interaction$runtime_ctx
saved_chats_data <- core_interaction$saved_chats_data
file_manager_data <- core_interaction$file_manager_data
filePreview <- core_interaction$filePreview

chat_engine <- serverBindChatEngineRuntime(
  ...,
  runtime_ctx = runtime_ctx,
  saved_chats_data = saved_chats_data,
  send_message_fns = send_message_fns,
  send_message_proxy = send_message
)

runtime_ctx <- chat_engine$runtime_ctx
```

For File Manager and chat-persistence-related modules, `server.R` should not call `serverBindFileManagerRuntime(...)` or `serverBindChatPersistenceModules(...)` directly. It should delegate to `serverBindCoreInteractionRuntime(...)`. That helper owns the core observer/File Manager/chat-persistence orchestration and then delegates to the narrower wiring helpers in `R/server_module_wiring.R`.

Keep the compatibility exports intact unless a later refactor explicitly removes them. `serverBindFileManagerRuntime(...)` still registers File Manager in `runtime_ctx$modules$file_manager` and exposes `session$userData$file_manager_data` for older downstream code, while `runtime_ctx$file$file_manager_data` is the preferred boundary for new server wiring.

Use `serverRuntimeAttachRefreshableModule(...)` directly only inside runtime/wiring helper layers or for a genuinely new refreshable module pattern that does not fit an existing wiring helper.

Do not re-expand the saved chats, history, image gallery, welcome handlers, download outputs, or message search wiring back into `server.R`; keep that cluster behind `serverBindChatPersistenceModules(...)`.

Use the lower-level `serverRuntimeAttachModule(...)`, `serverRuntimeRefreshModuleOnSsoAuthReady(...)`, and `serverRuntimeExposeSessionData(...)` helpers only when the combined helper does not fit the case. Do not re-expand the File Manager or Image Gallery wiring back into separate attach/refresh/expose blocks in `server.R`.

Legacy `session$userData` exports should also be explicit. If a refreshable module still requires a compatibility value such as `file_manager_data`, prefer `expose_session_key = "file_manager_data"` in `serverRuntimeAttachRefreshableModule(...)`. For non-refreshable cases, expose compatibility values through `serverRuntimeExposeSessionData(...)` instead of adding loose `session$userData$... <- ...` assignments in `server.R`.

Keep the validated identity section from `serverRuntimeRequireIdentity(...)` as the single early boot identity boundary in `server.R`. Do not mix direct `user_session$...` reads, raw `runtime_ctx$identity` assumptions, or direct identity-related `session$userData$...` reads back into `server.R`.

Send-message wiring should use cache functions from the context:

### Session userData list-store contract

Session-local list-shaped stores under `session$userData` are centralized through a small SessionRuntimeStore facade in `R/utils_session_cleanup.R`.

The low-level list helpers still own safe list access:

```r
session_user_data_get_list(...)
session_user_data_set_list(...)
session_user_data_put_list_item(...)
session_user_data_remove_list_item(...)
session_user_data_reset_lists(...)
```

Use the SessionRuntimeStore facade for list stores such as:

* `current_session_files`
* `file_summaries`
* `chart_store`
* `mcp_registry_snapshot`

Do not add new loose assignments in `server.R` such as:

```r
session$userData$current_session_files <- list()
session$userData$file_summaries <- list()
session$userData$chart_store <- list()
session$userData$mcp_registry_snapshot <- list()
```

The expected initialization boundary is `R/server_init_session_state.R`, which prepares shared stores through `session_runtime_store_reset(session)`.

MCP registry snapshot synchronization in `R/server_session_cache.R` should flow through `session_runtime_store_snapshot_mcp(session, files_snapshot)`.

Vision / uploaded image session boundary:

- `session$userData$current_session_files` is shared by MCP file preparation and the vision/Image Input path. Do not clear it on non-`mcp_excel` requests.
- `mergen_prepare_mcp_session_files()` may return an empty MCP registry snapshot for non-MCP paths, but it must preserve the existing `current_session_files` store so follow-up questions about the same uploaded image keep working without relogin.
- Isolated tests that source `R/helpers_send_message_core.R` and exercise this helper must also source `R/utils_session_cleanup.R`, because this path uses `session_user_data_get_list()`.
- Keep `.Renviron` / `.Renviron.example` vision model IDs separated only by `;` or `,`; do not split model IDs on whitespace.

The file upload/summary pipeline, file-click observers, and new-chat cleanup should use `session_runtime_store_*` helpers instead of assuming another module already created the list.

This prevents hidden source-order and state-orchestration coupling around file context, MCP Excel visibility, summaries, and chart storage.

Protected by:

```text
tests/testthat/test-session-user-data-store.R
tests/testthat/test-source-manifest-contract.R
```

```r
cache <- serverRuntimeRequireCache(...)

cache_mcp_file_locally_fn = cache$cache_mcp_file_locally
update_mcp_registry_snapshot_fn = cache$update_mcp_registry_snapshot
```

Do not reintroduce loose early aliases such as:

```r
cache_mcp_file_locally <- session_cache$cache_mcp_file_locally
update_mcp_registry_snapshot <- session_cache$update_mcp_registry_snapshot
user_config_rv <- user_session$user_config_rv
resolve_current_user_id <- user_session$resolve_current_user_id
current_user_id_provider <- user_session$current_user_id_provider
current_user_first_name <- session$userData$user_first_name
current_user_display_name <- session$userData$user_config$name
session$userData$auth_initialized <- FALSE
session$userData$sso_active <- TRUE
session$userData$user_config
session$userData$user_first_name
session$userData$auth_source
session$userData$file_manager_data <- file_manager_data
auth_ready <- session$userData$auth_initialized
auth_ready_provider = runtime_ctx$identity$is_auth_ready
cache <- runtime_ctx$cache
state <- runtime_ctx$state
identity <- runtime_ctx$identity
```

* Do not replace the accepted `identity <- serverRuntimeRequireIdentity(...)` pattern with `identity_ports <- serverRuntimeBuildIdentityPorts(...)`; the current tests intentionally protect the existing runtime-context identity contract.

The context contract is protected by:

```text
tests/testthat/test-server-runtime-context.R
tests/testthat/test-server-runtime-context-accessors.R
tests/testthat/test-user-session-identity-contract.R
tests/testthat/test-server-boundary-contract.R
tests/testthat/test-server-live-user-provider-contract.R
tests/testthat/test-server-chat-persistence-wiring-contract.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-production-contracts.R
tests/testthat/test-file-manager-module-policy-wiring.R
```



### Core interaction runtime contract

`R/server_core_interaction_runtime.R` is the focused boundary for the middle part of `server.R` that used to be heavily order-dependent. It owns the core interaction setup sequence after session state exists and before the chat engine is bound.

It currently wires:

- chat export,
- quick actions,
- settings observers,
- session timeout,
- File Manager runtime through `serverBindFileManagerRuntime(...)`,
- chat UI observers,
- navigation observers,
- startup observers,
- startup screen observers,
- AI Expert handlers,
- storage observers,
- file observers,
- file-click observers,
- chat persistence through `serverBindChatPersistenceModules(...)`.

Do not move those calls back into `server.R`. `server.R` should call `serverBindCoreInteractionRuntime(...)`, unpack only the returned handles it needs, and then continue to `serverBindChatEngineRuntime(...)`.

This boundary is protected by:

```text
tests/testthat/test-server-core-interaction-runtime.R
tests/testthat/test-production-contracts.R
tests/testthat/test-server-live-user-provider-contract.R
tests/testthat/test-server-chat-persistence-wiring-contract.R
tests/testthat/test-file-manager-module-policy-wiring.R
```

### Server module wiring contract

`R/server_module_wiring.R` is a narrow wiring boundary for medium-level server module setup. It is not a new framework and should not become a general service locator.

It currently owns these helper entry points:

```r
serverBindServiceModules(...)
serverBindSettingsAndRefs(...)
serverBindMediaModules(...)
serverBindFilePreludeModules(...)
serverBindFileManagerRuntime(...)
serverBindImageGalleryRuntime(...)
serverBindChatPersistenceModules(...)
serverBindChatEngineRuntime(...)
```

Responsibilities:

* `serverBindServiceModules(...)`: binds performance stats, health, and support modules while preserving the live `current_user_id_provider`.
* `serverBindSettingsAndRefs(...)`: binds settings, forward references, Bilge Yolaç startup wiring, visual settings sync, chat output headers, and `load_chat_in_progress`.
* `serverBindMediaModules(...)`: binds feedback, AI processing, TTS, TTS visualizer, music handlers, AI Expert, and STT.
* `serverBindFilePreludeModules(...)`: binds file preview, fallback follow-up tools, follow-up module tools, DOCX preview JavaScript, and optionally attaches these prelude handles to `runtime_ctx$file` when a runtime context is supplied.
* `serverBindFileManagerRuntime(...)`: binds `fileManagerServer(...)`, injects the live user-id provider and the auth-readiness provider from `serverRuntimeRequireIdentity(...)`, registers the module through `ServerRuntimeContext`, attaches `file_manager_data` to the focused FileRuntime boundary, wires one-time SSO-ready persisted-file refresh, and preserves the explicit `session$userData$file_manager_data` compatibility export.
* `serverBindImageGalleryRuntime(...)`: binds `imageGalleryServer(...)` with the live user-id provider and registers the gallery refresh function through `ServerRuntimeContext`.
* `serverBindChatPersistenceModules(...)`: binds saved chats, saved-chat observers, chat content search, image gallery runtime and observers, welcome handlers, download outputs, history, and message search while preserving the live `current_user_id_provider`, explicit user-config provider, and explicit user-first-name provider.
* `serverBindChatEngineRuntime(...)`: binds chat runtime, LLM response handlers, chat input observers, miscellaneous chat/UI observers, chat actions, TTS handlers, and `sendMessageInit(...)`; it also assigns the final `send_message_fns$send_message` implementation and uses `serverRuntimeCreateFunctionSlot(...)` to avoid fragile TTS placeholder reassignment in `server.R`. It should read identity, state, and cache through `serverRuntimeRequireIdentity(...)`, `serverRuntimeRequireState(...)`, and `serverRuntimeRequireCache(...)` rather than assuming raw `runtime_ctx$...` shape.

Do not move these direct calls back into `server.R`:

```r
performanceStatsServer(...)
healthServer(...)
destekServer(...)
settingsInit(...)
serverInitForwardRefs(...)
claudeCodeServer(...)
visualSettingsSyncInit(...)
chatOutputsInit(...)
feedbackServer(...)
aiProcessingServer(...)
ttsProcessingServer(...)
ttsVisualizerServer(...)
musicHandlersInit(...)
aiExpertServer(...)
sttServer(...)
filePreviewServer(...)
create_followup_suggestions_tool(...)
followupSuggestionsServer(...)
init_docx_preview_js(...)
fileManagerServer(...)
imageGalleryServer(...)
savedChatsServer(...)
savedChatsObserversInit(...)
chatSearchInit(...)
imageGalleryObserversInit(...)
welcomeHandlersInit(...)
downloadOutputsInit(...)
historyServer(...)
messageSearchInit(...)
serverInitChatRuntime(...)
llmResponseHandlersInit(...)
chatInputObserversInit(...)
miscObserversInit(...)
chatActionsInit(...)
ttsHandlersInit(...)
sendMessageInit(...)
```

`server.R` should delegate to high-level boundaries and then unpack only the returned handles it needs. For the core observer/File Manager/chat-persistence sequence, the high-level boundary is `serverBindCoreInteractionRuntime(...)`; for chat engine wiring, it remains `serverBindChatEngineRuntime(...)`. The helper must preserve existing module IDs, current initialization order, and user/provider behavior. In particular, user-scoped service bindings must keep using the live provider rather than a startup user-id snapshot.

For chat persistence, `server.R` should not call `serverBindChatPersistenceModules(...)` directly. `serverBindCoreInteractionRuntime(...)` calls it and returns `runtime_ctx` plus `saved_chats_data` to `server.R`.

Do not re-expand the chat runtime, LLM handler, TTS handler, chat action, miscellaneous observer, or send-message wiring back into `server.R`; keep that cluster behind `serverBindChatEngineRuntime(...)`.

`R/server_runtime_function_slot.R` must stay sourced after `R/server_runtime_context.R` and before `R/server_module_wiring.R`, because it uses the runtime stop helper and is consumed by chat engine wiring.

For file-related wiring, prefer `serverRuntimeRequireFileRuntime(...)` after the relevant boundary has attached file prelude or File Manager objects. In `server.R`, File Manager attachment should now arrive through `serverBindCoreInteractionRuntime(...)`. Do not reintroduce direct `filePreview <- ...`, `followup_tools <- ...`, or `file_manager_data <- ...` propagation patterns when the value is already available through `runtime_ctx$file`.

Protected by:

```text
tests/testthat/test-server-module-wiring-contract.R
tests/testthat/test-server-module-wiring-runtime-bindings.R
tests/testthat/test-server-module-wiring-chat-engine.R
tests/testthat/test-server-core-interaction-runtime.R
tests/testthat/test-production-contracts.R
tests/testthat/test-server-live-user-provider-contract.R
tests/testthat/test-server-chat-persistence-wiring-contract.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-server-boundary-contract.R
```

### Database helper modularization contract
The database layer is now intentionally split into smaller responsibility-focused helpers. Preserve this source order:

```r
safe_source("R/helpers_db_connection.R", encoding = "UTF-8")
safe_source("R/helpers_db_validation.R", encoding = "UTF-8")
safe_source("R/helpers_chat_message_formatting.R", encoding = "UTF-8")
safe_source("R/helpers_db_chat_readers.R", encoding = "UTF-8")
safe_source("R/helpers_db_chat_mutations.R", encoding = "UTF-8")
safe_source("R/helpers_database.R", encoding = "UTF-8")
```

Responsibilities:

* `R/helpers_db_connection.R`: DB connection, release, health probe, worker-side DB connection, and DB parameter encoding normalization.
* `R/helpers_db_validation.R`: validation helpers such as `validate_username()`, `validate_chat_title()`, and `validate_message_content()`.
* `R/helpers_chat_message_formatting.R`: conversion of DB message rows into app message objects, including generated-image HTML, ChartLab saved-chat placeholder regeneration, markdown fallback, timestamps, and `ReasoningContent` propagation.
* `R/helpers_db_chat_readers.R`: chat list loading, chat message hydration, reasoning-column fallback SELECTs, batch chat hydration, and lightweight history row reads. Chat list reads must preserve latest-activity ordering using message timestamps when available.
* `R/helpers_db_chat_mutations.R`: chat/message write-side mutations, including chat creation, message save/update, reasoning-content update, title update, delete/clear chat helpers, worker-safe assistant response persistence, and `sanitize_input()` compatibility.
* `R/helpers_database.R`: user creation/update, SSO field update, feedback operations, usage logging, and remaining DB orchestration.

MessageOrder race protection in `save_message_to_db()` and `worker_save_assistant_response()` must keep the `UPDLOCK/HOLDLOCK` query contract.

Do not move connection, validation, message-formatting, chat-reader, or chat/message mutation functions back into `R/helpers_database.R`. The split is protected by `test-db-refactor-contract.R`, `test-chat-message-formatting-refactor-contract.R`, `test-source-manifest-contract.R`, and `test-maintainability-ratchet.R`.

When updating `tests/testthat/helper_bootstrap.R`, keep its DB source order aligned with production `global.R`. Tests must load the extracted DB helper files before `helpers_database.R`.

### ChartLab rendering and saved-chat hydration contract

ChartLab rendering is intentionally split between pure chart-spec helpers and Shiny output wiring.

Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/helpers_mcp_chart_tools.R",       encoding = "UTF-8")
safe_source("R/helpers_mcp_analyze_visualize.R", encoding = "UTF-8")
safe_source("R/helpers_chartlab_spec.R",         encoding = "UTF-8")
safe_source("R/helpers_chartlab.R",              encoding = "UTF-8")
```

Responsibilities:

* `R/helpers_chartlab_spec.R`: pure ChartLab helpers for chart type normalization, mapping value normalization, missing/invalid axis guessing, and shared aggregation behavior.
* `R/helpers_chartlab.R`: parsing `chartlab ...` message blocks, producing Shiny chart output placeholders, and wiring those placeholders through `wire_chart_output(...)`.
* `R/helpers_chat_message_formatting.R`: when DB messages are hydrated, ChartLab content must be converted back into the same Shiny output placeholder shape used by live messages.
* `chat_rebind_all_charts(...)`: after saved-chat UI is inserted, chart outputs must be rebound after Shiny flush via `session$onFlushed(..., once = TRUE)` and loop variables must be captured with `local(...)`.

Do not reintroduce a separate static JS-only rendering path as the primary saved-chat ChartLab recovery mechanism. Saved and browser-refreshed chats should use the same server-side Shiny output identity contract as live ChartLab messages.

Do not move chart type aliasing, mapping guessing, or aggregation helpers back into `R/helpers_chartlab.R`.

ChartLab (and the interactive `R/module_chartlab.R`) renders charts through **highcharter only**. The previous `highcharter → plotly+ggplot2 → error` fallback chain was removed: in this deployment charts always render with highcharter (`ui.R` already references `highcharter::highchartOutput` for the hidden dependency loader, and the on-prem `renv.lock` pins highcharter). The container selection is now `highchartOutput` when highcharter is present and `shiny::uiOutput` otherwise; `wire_chart_output(...)` / `render_one(...)` render with `renderHighchart` when highcharter is present and degrade to a `renderUI` error message otherwise (graceful, no crash). Do not reintroduce a `plotly::renderPlotly` / `ggplot()` / `geom_*` chart-render fallback in `R/helpers_chartlab.R` or `R/module_chartlab.R`. The dead `have_plotly_gg` / `have_highcharter` flags were removed from `R/config_file_store.R`. Plotly has since been removed entirely from the runtime: the `deps_pl`/`plotly_html` preloader in `R/server_outputs_downloads.R` and the `plotly::plotlyOutput("deps_pl")` loader in `ui.R` are gone — `widgetDependencyOutputsInit()` now only defines the highcharter `deps_hc` loader. No runtime R / `ui.R` / `server.R` code references plotly; this is locked by `tests/testthat/test-chart-engine-highcharter-only-contract.R` (the "plotly çalışma zamanı kodundan tamamen kaldırıldı" scan). Plotly is not in `required_packages` and never was; the on-prem `renv.lock` should be re-snapshotted on the VM to drop plotly. Making highcharter an explicit `required_packages` entry remains an optional separate follow-up.

Protected by:

```text
tests/testthat/test-chart-engine-highcharter-only-contract.R
tests/testthat/test-chartlab-spec-refactor-contract.R
tests/testthat/test-chat-message-formatting-refactor-contract.R
tests/testthat/test-mcp-chart-tools-refactor-contract.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-maintainability-ratchet.R
```

### File Store registry/index modularization contract

The file-store layer is split so that path/root initialization stays separate from upload registry mutation and lookup behavior. Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/config_file_store.R",                encoding = "UTF-8")
safe_source("R/config_file_store_index_lock.R",     encoding = "UTF-8")
safe_source("R/config_file_store_index_mutation.R", encoding = "UTF-8")
safe_source("R/config_file_store_registry.R",       encoding = "UTF-8")
```

Responsibilities:

* `R/config_file_store.R`: file-store root paths, low-level UTF-8 index load/save helpers, environment validation, memory management, and scheduler-related configuration.
* `R/config_file_store_index_lock.R`: the index lock boundary: `.file_store_with_index_lock`, stale-lock breaking by age, the lock owner marker file for Windows/UNC mtime reliability, and availability-first lock acquisition.
* `R/config_file_store_index_mutation.R`: index mutation through the shared lock (`.file_store_mutate_index`), upload registration, display-name repair, storage-name recovery, public `global_register_file()` wrapper, and index removal.
* `R/config_file_store_registry.R`: uploaded-file resolution, user upload directory resolution, display-name lookup, user file listing, stale index pruning, and filesystem fallback listing.

Do not move `mergen_register_uploaded_file()`, `global_register_file()`, `resolve_uploaded_file()`, `mergen_user_upload_dir()`, `mergen_resolve_display_name()`, `recover_display_name_from_storage_name()`, `mergen_list_user_files()`, or `mergen_remove_from_index()` back into `R/config_file_store.R`.

The split is protected by:

* `tests/testthat/test-config-file-store-registry-refactor-contract.R`
* `tests/testthat/test-source-manifest-contract.R`
* `tests/testthat/test-maintainability-ratchet.R`

The index mutation path must keep a guard around read-modify-write operations so delayed file refresh or stale prune operations cannot overwrite a newer upload index entry.

### Bilge Yolaç run lifecycle and stop-finalization contract

Bilge Yolaç command execution now has a focused run-lifecycle boundary in `R/helpers_claude_code_run_lifecycle.R`.

Bilge Yolaç runtime workdir mirroring has a separate helper boundary in `R/helpers_claude_code_runtime_workdir.R`. This file owns user workspace creation and the Windows/UNC/Unicode workdir mirroring helpers: `get_user_workspace()`, `is_problematic_windows_workdir()`, `mirror_directory_to_local_workspace()`, `prepare_claude_runtime_workdir()`, and `sync_claude_runtime_workdir_back()`. Keep it sourced after `R/helpers_claude_code_process.R` and before `R/helpers_claude_code.R`.

Do not restore the old shared `active_dir` runtime folder pattern. Mirrored runtime workdirs must be per run, using the active `run_request_id` as the runtime token when `R/module_claude_code.R` calls `prepare_claude_runtime_workdir(...)`. This prevents rapid sequential or overlapping Bilge Yolaç runs for the same user from deleting each other’s mirrored workdir while snapshot comparison, generated-download collection, process polling, or sync-back is still using it.


### Bilge Yolaç workdir scan and generated-download contract

Bilge Yolaç workdir scanning is intentionally split from generated-download staging.

Responsibilities:

- `R/helpers_claude_code_workdir_scan.R` owns prompt intent detection for binary document creation/read flows, canonical file path normalization, duplicate path removal, workdir snapshot creation, snapshot diffing, and the short generated-file stability guard `wait_for_stable_claude_code_file_paths(...)`.
- `R/helpers_claude_code_workdir_snapshot.R` owns Turkish text encoding normalization and generated-download collection/staging orchestration through `collect_claude_code_workdir_changes_downloads(...)`.

Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/helpers_claude_code_downloads.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_workdir_scan.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_workdir_snapshot.R", encoding = "UTF-8")
```

Do not move scan/diff/path helpers back into `R/helpers_claude_code_workdir_snapshot.R`. That file should remain focused on text encoding normalization and generated-download staging.

`collect_claude_code_workdir_changes_downloads(...)` must keep calling `wait_for_stable_claude_code_file_paths(...)` before text normalization or staging. This is a Windows VM race-condition guard: Claude Code or child processes may have just produced a file, and size/mtime can still change briefly after the process appears complete. The guard reduces partial copy and premature `.txt` normalization risk while preserving best-effort generated-file collection.

Protected by:

```text
tests/testthat/test-claude-code-workdir-scan-contract.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-maintainability-ratchet.R
```

Responsibilities:

- active run request-id generation,
- active/stale run checks,
- stale async/promise callback protection,
- document-summary async result finalization guards,
- safe directory refresh after async completion,
- compatibility wrappers for request-id-aware finalization.

`R/module_claude_code.R` should remain focused on Shiny orchestration, command dispatch, process startup, and polling. Do not move the extracted async document-summary promise callback logic back into `R/module_claude_code.R`.

Stop handling is intentionally finalized directly inside the `input$stop_command` observer. When the user presses `Durdur`, the process may be killed and `active_process` may no longer be available to the polling observer. Therefore, the stop observer must not rely on the poll observer to reach the `env$durduruldu` branch. It must send the stream-end/finalization path itself so that the second counter, thinking animation, stop button, and disabled `Çalıştır` button are reset immediately.

Keep this behavior intact:

- `input$stop_command` should mark the environment as stopped when available.
- It may kill the active process.
- It should not manually clear all runtime state with ad hoc assignments.
- It should call `finalize_streaming("Durduruldu", ...)` with the active request id.
- `finalize_streaming(...)` remains the single state/UI cleanup boundary for run button, stop button, thinking overlay, status text, `rv$is_running`, `rv$active_process`, `rv$poll_state`, `rv$stream_env`, and `rv$active_request_id`.

Protected by:

```text
tests/testthat/test-claude-code-run-lifecycle-contract.R
tests/testthat/test-claude-code-runtime-workdir-contract.R
tests/testthat/test-claude-code-workdir-scan-contract.R
tests/testthat/test-claude-code-stream-finalize-contract.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-maintainability-ratchet.R
```

### Bilge Yolaç document extractor modularization contract

The Bilge Yolaç document-processing layer now has a focused extractor split. Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/helpers_claude_code_document_extractors.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_documents.R", encoding = "UTF-8")
```

Responsibilities:

* `R/helpers_claude_code_document_extractors.R`: binary-document extension policy, cache-name sanitization, text truncation, binary document discovery, temporary document-support directory creation, PDF/Excel/DOCX text extraction, supported-document dispatch, and office reader template path resolution.
* `R/helpers_claude_code_documents.R`: document manifest generation, inline payload construction, document prompt construction, document context preparation, summary detail-level detection, summary messages, and summary file output.

Do not move extractor helpers back into `R/helpers_claude_code_documents.R`. Keep the fallback source guard in `helpers_claude_code_documents.R` so the file can still be sourced directly in isolated tests/debug sessions. The split is protected by `test-claude-code-document-extractors-refactor-contract.R` and `test-claude-code-document-extractors-maintainability-contract.R`.

For maintainability refactors, prefer extracting one clear responsibility at a time and preserving public function names. After each extraction, update `global.R`, `tests/testthat/helper_bootstrap.R`, and add a small contract test that prevents the old monolithic responsibility from silently returning.



### Project/Resource Analysis security-summary helper contract

Project/Resource Analysis keeps RLS, identity-readiness, and statistical-summary helper logic outside the main Shiny module.

Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/helpers_pk_analysis_core.R",      encoding = "UTF-8")
safe_source("R/helpers_pk_analysis_security_summary.R", encoding = "UTF-8")
safe_source("R/helpers_pk_analysis_filters.R",   encoding = "UTF-8")
safe_source("R/module_proje_kaynak_analizi.R", encoding = "UTF-8")
```

Responsibilities:

R/helpers_pk_analysis_core.R: low-side-effect core helpers such as column summaries, date conversion, SQL Server identifier normalization, UTF-8 dataframe normalization, and Unicode SQL execution.

R/helpers_pk_analysis_security_summary.R: resolve_pk_analysis_username(), get_user_rls_info(), apply_rls_to_data(), and generate_statistical_summary().

R/helpers_pk_analysis_filters.R: AI-driven filter extraction and smart dataframe filtering.

R/module_proje_kaynak_analizi.R: request orchestration, query selection, SQL execution flow, filtering flow, LLM handoff, and stop-check handling.


Do not move the RLS helpers, SSO readiness resolver, or statistical-summary generator back into R/module_proje_kaynak_analizi.R.

resolve_pk_analysis_username() is a production safety boundary. In Windows VM SSO mode, Project/Resource Analysis must not proceed to RLS/DB lookup with username "Unknown" while session$userData$auth_initialized is still false. If identity is not ready, the analysis path should return the existing user-facing "identity/authentication is preparing" message instead of opening a DB connection.

The public helper names must remain stable unless compatibility wrappers are preserved.

Protected by:

tests/testthat/test-pk-analysis-security-summary-contract.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-maintainability-ratchet.R

### Send-message request lifecycle contract

`R/helpers_send_message_request_lifecycle.R` owns the focused helper boundary for `sendMessageInit(...)` request lifecycle behavior. Keep it sourced before `R/helpers_send_message_core.R`, `R/server_handler_true_streaming.R`, and `R/server_send_message.R`.

Responsibilities:

- request id generation through `mergen_new_send_message_request_id()`,
- current/stale/stopped request-state checks through `mergen_send_message_request_state(...)`,
- prompt snapshotting before routing,
- deferred chat creation decisions and chat preparation,
- welcome-screen cleanup for message send,
- thinking-panel planning and wrapper insertion,
- true-streaming deferred persistence guard through `mergen_should_run_deferred_stream_persist(...)`.

`R/server_send_message.R` should remain focused on orchestration, routing, mode dispatch, and LLM handoff. Do not move the extracted request lifecycle, prompt snapshot, welcome cleanup, thinking panel, or deferred chat preparation blocks back into `R/server_send_message.R`.

`R/server_handler_true_streaming.R` must use `mergen_new_send_message_request_id()` for request ids. Any delayed `later::later(...)` callback that can create or persist a chat for an active stream must check `mergen_should_run_deferred_stream_persist(active_request_id, stream_env$req_id, stream_env)` before calling `ensure_chat_ready()`. This prevents stale true-streaming callbacks from mutating `values$current_chat_id` after a stop, finalized stream, or newer request.

Protected by:

```text
tests/testthat/test-send-message-request-lifecycle-contract.R
tests/testthat/test-send-message-maintainability-ratchet.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-maintainability-ratchet.R
```

### LLM SSE stream I/O contract

The true-streaming LLM layer keeps the stream-file JSONL protocol separate from SSE event/delta parsing and worker orchestration. Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/helpers_llm_tool_formatters.R",      encoding = "UTF-8")
safe_source("R/helpers_llm_response_postprocess.R", encoding = "UTF-8")
safe_source("R/helpers_llm_api.R",                  encoding = "UTF-8")
safe_source("R/helpers_llm_stream_io.R",            encoding = "UTF-8")
safe_source("R/helpers_llm_sse_events.R",           encoding = "UTF-8")
safe_source("R/helpers_llm_sse.R",                  encoding = "UTF-8")
safe_source("R/helpers_llm_worker_payload.R",       encoding = "UTF-8")
safe_source("R/helpers_llm_worker.R",               encoding = "UTF-8")
```

Responsibilities:

R/helpers_llm_stream_io.R: stream JSONL delta/reasoning line writing, base64 payload decoding, and stop-file cancellation checks.

R/helpers_llm_sse_events.R: SSE event/delta parsing helpers (`decode_utf8_raw_chunk`, `parse_llm_sse_event`, `extract_llm_delta_bundle`, `extract_llm_delta_text`, `extract_llm_event_sources`). This is a side-effect-free pure parsing layer.

R/helpers_llm_sse.R: HTTP/SSE worker orchestration (`call_local_llm_sse_worker`); event/delta parsing calls must go through `helpers_llm_sse_events.R`. Do not move SSE event/delta helpers back into this file, otherwise it can silently consume the 800-line and 25-function maintainability thresholds.


### UTF-8 streaming chunk contract

SSE chunks may split multi-byte UTF-8 characters across curl callbacks. Keep the stateful UTF-8 decoding boundary in `R/helpers_llm_stream_io.R`: `find_last_utf8_boundary()` and `create_utf8_stream_decoder()` must carry partial bytes into the next chunk instead of decoding each raw callback independently.

`R/helpers_llm_sse.R` should use the stateful decoder inside `call_local_llm_sse_worker()` and flush remaining bytes after the stream completes. Do not regress this path back to direct per-chunk `rawToChar()` / `enc2utf8()` decoding, because that can reintroduce `input string 1 is invalid UTF-8` failures on Windows VM / Turkish text streams.

### Thinking model capability contract

Thinking capability must be declared through `config$local_model_capabilities`; do not infer it from model-name regexes such as `qwen3`, `thinking`, `reasoning`, `r1`, or similar substrings.

SQL analysis and other model-sensitive branches should use `is_thinking_model(model_selected)` rather than direct `grepl()` checks. Unknown models should default to non-thinking behavior unless explicitly declared in configuration.

### LLM worker payload helper contract

`R/helpers_llm_worker_payload.R` owns pure helper logic used by `R/helpers_llm_worker.R`:

- chat history to OpenAI-compatible message payload conversion,
- system-message merging,
- chart intent and chart type detection,
- disabled fallback chart passthrough,
- chart summary generation,
- automatic insight generation from tool results.

Keep this file free of Shiny session access, reactive reads, filesystem writes, HTTP calls, database calls, and mutable runtime state. It must remain safe to source in isolated tests and worker contexts.

`R/helpers_llm_worker.R` should keep orchestration responsibilities: API request construction, model request overrides, MCP tool schema handling, tool execution, second-pass logic, chart block collection, response post-processing, and error handling.

Keep the compatibility wrapper `merge_system_messages_to_front()` unless every old second-pass/recursive call path has been removed and tests prove that removal is safe. New code should call the canonical `llm_worker_merge_system_messages_to_front()` helper.

Protected by:

```text
tests/testthat/test-llm-worker-payload-refactor-contract.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-maintainability-ratchet.R
```


Do not move append_stream_delta_line(), append_stream_reasoning_line(), decode_stream_delta_payload(), or streaming_should_stop() back into R/helpers_llm_sse.R.

streaming_should_stop() must treat only a real file as a stop flag. A directory, empty string, NULL, or NA must not abort a stream.

Protected by:

tests/testthat/test-llm-stream-io-contract.R
tests/testthat/test-streaming-should-stop.R
tests/testthat/test-sse-worker-export-contract.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-maintainability-ratchet.R

### Bilge Yolaç UI and model/config modularization contract

Bilge Yolaç is now split into smaller responsibility-focused files. Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/helpers_claude_code_user_guard.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_upload_folder.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_model_config.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_session_context.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_dir_ui.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_process.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_runtime_workdir.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code.R", encoding = "UTF-8")
safe_source("R/helpers_claude_code_server_setup.R", encoding = "UTF-8")
```

For the module UI/server split, preserve this order around the Bilge Yolaç module files:

```r
safe_source("R/module_claude_code_plugins.R", encoding = "UTF-8")
safe_source("R/module_claude_code_ui.R", encoding = "UTF-8")
safe_source("R/module_claude_code_akis.R", encoding = "UTF-8")
safe_source("R/module_claude_code.R", encoding = "UTF-8")
```

Responsibilities:

* `R/module_claude_code_ui.R`: `claudeCodeUI()` and Bilge Yolaç page UI layout.
* `R/module_claude_code.R`: `claudeCodeServer()` and server/runtime logic for the Bilge Yolaç page.
* `R/helpers_claude_code_upload_folder.R`: Bilge Yolaç upload-folder resolution helpers, including relaxed directory checks, candidate folder scoring, explicit session file registry handling, and placeholder user-id rejection.
* `R/helpers_claude_code_model_config.R`: Claude CLI path resolution, `settings.json` reading, model-tier mapping, model capability helpers, thinking-model detection, binary-document prompt detection, and execution-model fallback decisions.
* `R/helpers_claude_code_user_guard.R`: owns the Bilge Yolaç auth/user readiness contract. It checks SSO readiness and resolves a positive live user id before user-scoped workspace, upload-folder, directory listing, or command execution paths continue.
* `R/helpers_claude_code_server_setup.R`: owns the Bilge Yolaç server setup/observer binding cluster, including CLI path probing, connection badge updates, character/theme/font sync, upload-folder navigation, local folder upload, model-change session reset, scenario buttons, directory refresh, clear-output handling, and thinking tick updates.
* `R/helpers_claude_code_session_context.R`: Bilge Yolaç active-character and user first-name reactive context helpers used by `R/module_claude_code.R`.
* `R/helpers_claude_code_process.R`: Node/CLI process path resolution, processx command construction, Windows `.cmd`/UNC handling, process output UTF-8 normalization, non-ASCII escaping, Claude Code JSON/JSONL output parsing, and safe CLI workdir selection.
* `R/helpers_claude_code.R`: Claude Code CLI execution orchestration, status checks, runtime command handling, workspace helpers, and remaining Claude Code runtime helpers.

Do not move the setup observer cluster back into `R/module_claude_code.R`. That file should keep the public `claudeCodeServer()`entry point and the main command/streaming runtime flow, while setup and user/workspace readiness behavior remains behind`cc_bind_server_setup(...)`and`cc_require_ready_user_id(...)`. User-scoped Bilge Yolaç actions must not proceed with unresolved `user_id = 0`, especially in SSO startup timing windows.

Naming note: `R/helpers_claude_code_upload_folder.R`intentionally keeps its existing string-returning`cc_normalize_positive_user_id()`helper for upload-folder compatibility.`R/helpers_claude_code_user_guard.R`must use`cc_normalize_ready_user_id()`for integer readiness checks. Do not reintroduce a second`cc_normalize_positive_user_id()` definition in the user-guard file, because source order would make the two helpers collide.

When adding future Bilge Yolaç behavior:
- add pure/testable helpers for user-id readiness or setup decisions instead of new ad hoc observer logic in `R/module_claude_code.R`;
- preserve the live user-id provider pattern instead of capturing a startup user id;
- keep stale directory refresh protection through `cc_create_dir_refresh_guard()` / `dir_refresh_guard$is_latest(...)`;
- update `test-source-manifest-contract.R` whenever a new helper file is introduced;
- keep `tests/testthat.R` strict with `stop_on_failure = TRUE` and `stop_on_warning = TRUE`.

Do not move `claudeCodeUI()` back into `R/module_claude_code.R`.
Do not move model/settings helper functions back into `R/helpers_claude_code.R`.

The split is protected by:

* `tests/testthat/test-claude-code-ui-refactor-contract.R`
* `tests/testthat/test-claude-code-model-config-refactor-contract.R`
* `tests/testthat/test-claude-code-process-refactor-contract.R`
* `tests/testthat/test-claude-code-user-guard-contract.R`
* `tests/testthat/test-claude-code-dir-ui-refactor-contract.R`
* `tests/testthat/test-claude-code-upload-folder-refactor-contract.R`
* `tests/testthat/test-claude-code-run-lifecycle-contract.R`
* `tests/testthat/test-claude-code-stream-finalize-contract.R`
* `tests/testthat/test-source-manifest-contract.R`
* `tests/testthat/test-maintainability-ratchet.R`

For future maintainability refactors, keep using the ratcheted approach: extract one coherent responsibility, preserve public function names, update `global.R`, add a focused contract test, run the full strict test suite, then tighten `test-maintainability-ratchet.R` only after `tests/scripts/maintainability_report.R` confirms the new baseline.

### Proje/Kaynak Analizi filter modularization contract

The Proje/Kaynak Analizi layer now has a focused filter-helper split. Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/helpers_pk_analysis_core.R",      encoding = "UTF-8")
safe_source("R/helpers_pk_analysis_filters.R",   encoding = "UTF-8")
safe_source("R/module_proje_kaynak_analizi.R",   encoding = "UTF-8")
```

Responsibilities:

* `R/helpers_pk_analysis_core.R`: pure PK analysis helpers such as column summaries, date conversion, UTF-8 normalization, SQL Unicode execution, and SQL Server identifier normalization.
* `R/helpers_pk_analysis_filters.R`: AI filter criteria extraction, stop-after-LLM guard, JSON filter parsing, smart dataframe filtering, and aggregation.
* `R/module_proje_kaynak_analizi.R`: Proje/Kaynak Analizi runtime orchestration, RLS, DB/query execution, module behavior, and fallback helper loading.

Do not move `extract_filter_criteria_from_prompt()` or `apply_smart_filters()` back into `R/module_proje_kaynak_analizi.R`. Preserve their public function names because `R/helpers_deep_analysis.R` calls them directly.

The split is protected by:

* `tests/testthat/test-pk-analysis-filters-refactor-contract.R`
* `tests/testthat/test-pk-analysis-core-refactor-contract.R`
* `tests/testthat/test-pk-analysis-maintainability-contract.R`

### Proje/Kaynak Analizi query-selection modularization contract

The Proje/Kaynak Analizi "Akıllı Sorgu Seçici" (Smart Query Selector) heuristic scoring and score-table reporting are intentionally split out of the large module. Preserve this source order in `R/config_source_manifest.R` (the helper is in the `analysis_helpers` section, after `R/helpers_pk_analysis_filters.R` and before `R/module_proje_kaynak_analizi.R`):

```r
safe_source("R/helpers_pk_analysis_filters.R",          encoding = "UTF-8")
safe_source("R/helpers_pk_analysis_query_selection.R",  encoding = "UTF-8")
safe_source("R/module_proje_kaynak_analizi.R",          encoding = "UTF-8")
```

Responsibilities:

* `R/helpers_pk_analysis_query_selection.R`: pure heuristic query-relevance scoring and score-table reporting. It owns `pk_init_query_score_table()` (the `all_scores` skeleton with `query_id`/`query_name`/`ai_score`/`heuristic_score`/`final_score`), `pk_score_query_relevance()` (per-query raw score), `pk_compute_heuristic_query_scores()` (full library scoring + `%100` normalization + `THRESHOLD_RAW=2`/`THRESHOLD_PCT=30` decision), and `print_score_table()` (console diagnostic). Its only permitted side effect is `print_score_table()`'s `cat()` output; no Shiny observer/render/runtime, no live DB connection, no LLM call.
* `R/module_proje_kaynak_analizi.R`: keeps the `select_smart_query()` orchestrator (AI selection loop, session/`cat` orchestration, final result assembly) and calls the extracted pure helpers.

Do not move `select_smart_query()` into the helper (it calls `find_best_query_with_ai()` which stays in the module, and is itself called by `R/helpers_deep_analysis.R`). Do not move `pk_init_query_score_table()`, `pk_score_query_relevance()`, `pk_compute_heuristic_query_scores()`, or `print_score_table()` back into the module. The scoring formula (name substring `+50`, name-word match `×10`, description-word match `×2`, the seven Turkish domain-keyword bonuses `+8`, max-normalized `%100`, `THRESHOLD_RAW=2`/`THRESHOLD_PCT=30`) and the `all_scores` table shape must be preserved exactly; the seven domain-bonus `grepl()` Turkish patterns are encoding-sensitive and must stay byte-identical.

The split is protected by:

* `tests/testthat/test-pk-analysis-query-selection-refactor-contract.R`
* `tests/testthat/test-pk-analysis-query-selection-behavior.R`
* `tests/testthat/test-pk-analysis-maintainability-contract.R`
* `tests/testthat/test-source-manifest-sections-contract.R`

### File Manager modularization contract

The File Manager layer is intentionally split to keep the large runtime module from growing again. Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/helpers_file_manager_policy.R", encoding = "UTF-8")
safe_source("R/helpers_file_manager_context_policy.R", encoding = "UTF-8")
safe_source("R/helpers_file_manager_table.R", encoding = "UTF-8")
safe_source("R/helpers_file_manager_refresh_guard.R", encoding = "UTF-8")
safe_source("R/helpers_file_manager_session_registry.R", encoding = "UTF-8")
safe_source("R/helpers_file_manager_runtime.R", encoding = "UTF-8")
safe_source("R/helpers_file_manager_storage.R", encoding = "UTF-8")
safe_source("R/helpers_file_manager_state_runtime.R", encoding = "UTF-8")
safe_source("R/module_file_manager_ui.R", encoding = "UTF-8")
safe_source("R/module_file_manager.R", encoding = "UTF-8")
```

Responsibilities:

* `R/helpers_file_manager_policy.R`: pure File Manager policy/helpers such as upload-size normalization, upload-size byte conversion, summarization/normal allowed extension policy, attach-rule hint text, File Manager user-id normalization, file-extension icon HTML, and file timestamp formatting.
* `R/helpers_file_manager_context_policy.R`: pure File Manager model-context cleanup planning, including stale selection IDs, MCP Excel-only enforcement, and single-Excel selection planning.
* `R/helpers_file_manager_table.R`: pure File Manager table helpers such as empty table schema, action button HTML, model-context checkbox HTML, and single-row table construction. This file must not mutate Shiny reactive state.
* `R/helpers_file_manager_refresh_guard.R`: pure File Manager persisted-refresh request generation guard. This file owns the monotonically increasing request token used to prevent stale refreshes from applying older file state.
* `R/helpers_file_manager_session_registry.R`: pure-ish File Manager session file registry helpers. This file owns `session$userData$current_session_files` entry shape, registry initialization, register/unregister behavior, and registry path normalization.
* `R/helpers_file_manager_runtime.R`: File Manager server runtime helper factory. It preserves local helper names used by `fileManagerServer()` while keeping settings resolution, effective user-id resolution, debug logging, registry wrappers, parent attach/detach synchronization, and extension/toast helpers outside the server module body.
* `R/helpers_file_manager_storage.R`: File Manager persistent storage helper factory. It owns user upload folder resolution, MCP-base path checks, user-folder listing, and persisted upload index synchronization.
* `R/helpers_file_manager_state_runtime.R`: focused File Manager state/action helper factory and persisted refresh construction (`fm_create_file_action_helpers(...)`, `fm_create_refresh_from_user_folder(...)`) extracted from the module runtime body.
* `R/module_file_manager_ui.R`: public `fileManagerUI(id)` definition, File Manager UI layout, and browser-side upload-size guard.
* `R/module_file_manager.R`: public `fileManagerServer(...)` definition, server-side upload processing, attach/detach orchestration, deletion/clear operations, and parent-session synchronization while delegating File Manager state mutation and persisted file refresh construction to dedicated helpers. Small pure decisions should delegate to File Manager helper files instead of being reimplemented inline.

### File Manager state runtime extraction contract

The File Manager state mutation and persisted-folder refresh runtime are intentionally extracted into `R/helpers_file_manager_state_runtime.R`. Keep this file sourced after `R/helpers_file_manager_storage.R` and before `R/module_file_manager_ui.R` / `R/module_file_manager.R`.

Responsibilities:
- `R/module_file_manager.R`: Shiny module orchestration, observer wiring, UI event handling, and delegation to helper factories.
- `R/helpers_file_manager_state_runtime.R`: focused File Manager state/action helpers and persisted refresh construction, including `fm_create_file_action_helpers(...)` and `fm_create_refresh_from_user_folder(...)`.
- `R/helpers_file_manager_refresh_guard.R`: pure request-token guard that prevents stale persisted refreshes from overwriting newer File Manager state.
- `R/helpers_file_manager_table.R`: file table schema and row HTML construction.

Do not move `sync_file_to_context`, `append_uploaded_file_row`, `remove_file_by_name`, `process_uploaded_file`, or `fm_create_refresh_from_user_folder()` back into `R/module_file_manager.R`. New File Manager state mutation helpers should either belong in `R/helpers_file_manager_state_runtime.R` or in a narrower helper if a clearly separate responsibility emerges.

Bulk upload must not mutate persisted File Manager state before SSO/auth identity is ready. Keep the auth-readiness guard in the upload path and keep File Manager auth readiness injected through the validated identity provider rather than direct `session$userData$auth_initialized` checks.

File Manager storage policy tests now cover the user-specific upload directory and invalid-user persistence boundary. `fm_create_server_storage_helpers()` should keep deriving upload folders under the configured MCP base as `user_<id>`, while `ensure_persisted_upload_index()` must return without registering files for invalid user ids such as `0`, `unknown`, empty, or NULL. Do not weaken this guard to make refresh or upload flows appear successful.

Protected by:
```text
tests/testthat/test-file-manager-state-runtime-contract.R
tests/testthat/test-file-manager-module-policy-wiring.R
tests/testthat/test-file-manager-refresh-guard-contract.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-maintainability-ratchet.R
```

This extraction reduced `R/module_file_manager.R` below the 800-line threshold and raised the maintainability baseline to 70/100.

Do not move `fileManagerUI()` back into `R/module_file_manager.R`. Do not duplicate upload-size, allowed-extension, attach-rule text, user-id placeholder handling, file-extension icon HTML, file timestamp formatting, or session file registry path/entry decisions inside the module when the helper already owns that policy.

The persisted-file refresh path uses a request-generation guard from `fm_create_refresh_request_guard()` (`refresh_guard$next_id()` and `refresh_guard$is_latest(...)`) so stale refreshes cannot overwrite newer file state. Preserve that guard when editing `refresh_from_user_folder(...)`.

This split is protected by:

* `test-file-manager-policy-contract.R`
* `test-file-manager-context-policy-contract.R`
* `test-file-manager-table-contract.R`
* `test-file-manager-refresh-guard-contract.R`
* `test-file-manager-module-policy-wiring.R`
* `test-file-manager-state-runtime-contract.R`
* `test-file-manager-ui-refactor-contract.R`
* `test-file-manager-upload-limit-ui.R`
* `test-source-manifest-contract.R`
* `test-maintainability-ratchet.R`

### Settings Yapılandırma UI modularization contract

The Yapılandırma settings page is split so that the large UI layout does not grow inside the runtime server module. Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/module_settings_kisisel.R", encoding = "UTF-8")
safe_source("R/module_settings_yapilandirma_ui.R", encoding = "UTF-8")
safe_source("R/module_settings_yapilandirma.R", encoding = "UTF-8")
safe_source("R/module_settings.R", encoding = "UTF-8")
```

Responsibilities:

* `R/module_settings_yapilandirma_ui.R`: `settingsYapilandirmaUIImpl(id)` and the Yapılandırma page UI cards/layout only.
* `R/module_settings_yapilandirma.R`: public `settingsYapilandirmaUI(id)` wrapper, `settingsYapilandirmaServer(...)`, temporary settings state, save/reset triggers, runtime outputs, and observer logic.
* `R/module_settings.R`: central settings coordinator, localStorage restore, save/reset orchestration, and cross-module synchronization.

Do not move the large Yapılandırma UI card layout back into `R/module_settings_yapilandirma.R`. Do not move runtime observers, `reactiveVal(...)`, `moduleServer(...)`, or `session$sendCustomMessage(...)` into `R/module_settings_yapilandirma_ui.R`.

Inside `R/module_settings_yapilandirma_ui.R`, `settingsYapilandirmaUIImpl(id)` is a thin composer that delegates each settings card to a focused, pure `.syap_*(ns)` sub-builder (`.syap_header_row`, `.syap_model_card`, `.syap_api_key_card`, `.syap_tools_card`, `.syap_claude_code_card`, `.syap_interface_shortcuts_row`, `.syap_audio_card`, `.syap_ai_expert_card`, `.syap_image_card`, `.syap_summarization_card`, `.syap_analysis_card`). This is a readability split only: the produced tag tree and every server-bound `ns(...)` input/output id must stay byte-identical. The sub-builders must remain pure UI (no `moduleServer`/observers/`reactiveVal`/`sendCustomMessage`). Do not re-merge them back into one giant function, and do not drop or rename any of the 47 protected ids. The exact id surface and card structure are frozen by `tests/testthat/test-settings-yapilandirma-ui-id-surface-behavior.R`, which renders the UI and asserts the full id set plus card titles.

This split is protected by:

* `tests/testthat/test-settings-yapilandirma-ui-refactor-contract.R`
* `tests/testthat/test-settings-yapilandirma-ui-id-surface-behavior.R`
* `tests/testthat/test-source-manifest-contract.R`
* `tests/testthat/test-maintainability-ratchet.R`

### Admin Hata Analizi modularization contract

`R/module_admin_hata_analizi.R` has been reduced by extracting pure/query/UI helper responsibilities into `R/helpers_admin_hata_analizi.R`.

Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/helpers_admin_hata_analizi.R", encoding = "UTF-8")
safe_source("R/module_admin_hata_analizi.R",  encoding = "UTF-8")
```

Responsibilities:

* `R/helpers_admin_hata_analizi.R`: Admin Hata Analizi SQL query bundle, Turkish category/priority/status labels, category counting, tab UI router, and tab UI builders.
* `R/module_admin_hata_analizi.R`: public Shiny module API, refresh/reactive orchestration, chart/table rendering, attachment/status modal handling, and event logic.

Do not move the helper responsibilities back into `R/module_admin_hata_analizi.R`. Keep the public module names unchanged.

Protected by:

```text
tests/testthat/test-admin-hata-analizi-refactor-contract.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-maintainability-ratchet.R
```

Important: if isolated tests source `R/helpers_admin_hata_analizi.R` directly, keep test-only stubs local to the test file instead of sourcing broad runtime modules.

### Admin Yanıt Analizi modularization contract

Yanıt Geri Bildirimi Analizi sayfası, büyük admin modüllerinin kademeli küçültülmesi yaklaşımıyla ayrı yardımcı dosyaya bölünmüştür. Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/helpers_admin_yanit_analizi.R", encoding = "UTF-8")
safe_source("R/module_admin_yanit_analizi.R",  encoding = "UTF-8")
```

Responsibilities:

* `R/helpers_admin_yanit_analizi.R`: MB_Feedback odaklı sorgu paketi, yanıt geri bildirim etiket çözümleme mantığı ve Yanıt Analizi sekme UI helperları.
* `R/module_admin_yanit_analizi.R`: public `adminYanitAnaliziUI()` / `adminYanitAnaliziServer()` API'si, Shiny refresh/reactive orkestrasyonu, chart/table output render fonksiyonları ve modül wiring.

Do not move `admin_yanit_collect_data()`, `admin_yanit_tag_counts()`, `admin_yanit_overview_ui()`, `admin_yanit_model_ui()`, `admin_yanit_etiket_ui()` or `admin_yanit_zaman_ui()` back into `R/module_admin_yanit_analizi.R`.

This split is protected by:

* `tests/testthat/test-admin-yanit-analizi-refactor-contract.R`
* `tests/testthat/test-source-manifest-contract.R`
* `tests/testthat/test-maintainability-ratchet.R`

---

# 6) When the user asks for exact patches, be exact

---

# 7. Automated validation commands

Run from repo root:

```r
source("tests/scripts/maintainability_report.R", encoding = "UTF-8")
```

Focused validation for the current server runtime architecture boundary:

```r
testthat::test_file("tests/testthat/test-server-user-session-context.R")
testthat::test_file("tests/testthat/test-server-runtime-context.R")
testthat::test_file("tests/testthat/test-server-core-interaction-runtime.R")
testthat::test_file("tests/testthat/test-server-module-wiring-runtime-bindings.R")
testthat::test_file("tests/testthat/test-session-user-data-store.R")
testthat::test_file("tests/testthat/test-server-module-wiring-contract.R")
testthat::test_file("tests/testthat/test-server-live-user-provider-contract.R")
testthat::test_file("tests/testthat/test-source-manifest-contract.R")
testthat::test_file("tests/testthat/test-production-contracts.R")
```

Then run the full strict suite:

```r
source("tests/testthat.R", encoding = "UTF-8")
```

The user often wants:

- full replacement blocks,
- precise before/after snippets,
- exact file names,
- exact insertion locations,
- concrete testing instructions.

Do not answer vaguely.

### 7) Preserve existing UX wording
User-facing strings are mostly Turkish and intentionally stylized. Avoid rewriting labels unless required.

### 7A) Prefer canonical identity resolution helpers
When resolving effective user/session identity, prefer shared canonical helpers (for example `resolve_effective_user_id(...)`) instead of copy-pasted local resolver variants.

Avoid re-implementing local `resolve_current_user_id()` snippets unless there is a compelling, scoped reason. In this repo, SSO timing regressions often come from duplicated identity-resolution code paths drifting apart.

In SSO flows, do not pass the startup `current_user_id` snapshot into user-scoped modules. The startup value may temporarily be `0L`. Pass a live provider such as `current_user_id_provider` / `resolve_current_user_id()` so modules resolve the effective user at use time. `resolve_effective_user_id(...)` must treat placeholder/invalid session IDs such as `0`, `NA`, and non-numeric values as missing, then fall back to the live provider before returning `0L`. This protects saved chats, history, file manager, gallery, support, and performance flows from SSO user-ID drift.

User/session bootstrap is centralized in `R/server_init_user_session.R`. Do not move local/SSO identity setup logic back into `server.R`.

`server.R` should initialize `user_session` with `serverInitUserSession(...)`, then pass it into `serverRuntimeContextInit(...)`. Downstream aliases must come from `runtime_ctx$identity`, not directly from `user_session`.

Expected pattern:

```r
user_session <- serverInitUserSession(...)

runtime_ctx <- serverRuntimeContextInit(
  session = session,
  session_cache = session_cache,
  sso_state = sso_state,
  user_session = user_session
)

identity <- serverRuntimeRequireIdentity(
  runtime_ctx,
  required_values = c("user_config_rv"),
  required_functions = c(
    "resolve_current_user_id",
    "current_user_id_provider",
    "get_first_name",
    "get_display_name"
  ),
  owner = "server.R identity"
)

user_config_rv <- identity$user_config_rv
resolve_current_user_id <- identity$resolve_current_user_id
current_user_id_provider <- identity$current_user_id_provider
current_user_first_name <- identity$get_first_name
current_user_display_name <- identity$get_display_name
```

For auth-sensitive modules, pass `identity$is_auth_ready` as a provider rather than checking `session$userData$auth_initialized` directly.

Do not pass startup `current_user_id` snapshots to user-scoped modules. In SSO mode, the startup value may temporarily be `0L`; use the live provider exposed through `runtime_ctx$identity$current_user_id_provider`.

### 8) Async jobs visible in health metrics must use tracked wrapper
For application-monitored async flows, do not use raw `future_promise(...)` directly.

Use `tracked_future_promise(task_fn = function() { ... }, task_type = "...", session_token = session$token)` with a meaningful `task_type`.

Do not pass raw expression blocks as positional `expr`; `tracked_future_promise()` now expects `task_fn`.

### 8A) tracked_future_promise() is also a worker dependency wrapper

In this repository, `tracked_future_promise(...)` is not used only for tracking/metrics. It is also the standard entry point for safely transferring global functions and required packages used in `task_fn` to the worker side.

Practical result:
- In a new async flow, using raw `future_promise(...)` should be considered prohibited.
- `tracked_future_promise(...)` automatically derives dependencies inside `task_fn` when possible.
- In special flows, explicitly passing dependencies with `globals = list(...)` is still a correct approach.

In particular, the following errors are usually not a source-order issue, but a worker dependency transfer issue:
- `call_llm_worker function not found`
- `generate_image function not found`

For true SSE streaming, keep the worker prewarm/export contract aligned with the `tracked_future_promise(..., globals = list(...))` contract in `R/server_handler_true_streaming.R`. Reasoning deltas, stop-file checks, and model-specific request overrides require helpers such as `append_stream_reasoning_line`, `streaming_should_stop`, `apply_model_request_overrides`, and `merge_named_list_deep` to remain visible on the worker side.

These errors can be more visible especially under these conditions:
- `SSO_ENABLED=TRUE`
- Windows VM
- Running the entire `app.R` file with `Ctrl+Enter`
- Use of persistent cluster workers

### 8B) Source-time side effects must be guarded
Source-time background loops/timers must always use a once-only guard pattern.

Repository convention:
- periodic GC scheduling is started through a once-only guard (`start_gc_scheduler_once()` pattern),
- do not reintroduce unguarded source-time scheduling that can stack duplicate loops when files are sourced repeatedly in the same R session.

### Upload-size policy and client-side guard
File upload size enforcement is layered and must remain that way:

* browser/client-side guard in `R/module_file_manager_ui.R` rejects files above the configured limit before Shiny upload starts,
* `shiny.maxRequestSize` provides request-level protection,
* `validate_uploaded_file()` provides the final server-side trust boundary.

The default production policy is 25 MB per file. Do not remove the browser-side guard. The browser-side guard is implemented in `R/module_file_manager_ui.R`; keep it there unless the File Manager UI split is intentionally redesigned. Without it, large files may still make the Dosya Yönetimi page appear frozen because Shiny begins uploading immediately when a user selects or drops a file, before server-side validation can show a toast.

---

## Health Dashboard Architecture

The “Sistem Durumu” page is a modular, offline-compatible health dashboard for on-prem Windows VM deployments. Keep the public Shiny module API stable and backward compatible:

```r
healthUI(id)
healthServer(id, perf_tracker)
```

Do not break existing callers of these functions.

Implementation split (keep responsibilities scoped):
- `R/helpers_health_formatters.R`: status/severity normalization, secret-safe formatting, path-copy helpers, shared rendering helpers.
- `R/helpers_health_runtime_checks.R`: runtime, SSO, paket, işletim sistemi/süreç, worker ve Bilge Yolaç sağlık kontrolleri.
- `R/helpers_health_checks.R`: environment, storage, DB, LLM/service endpoint kontrolleri ve genel sağlık kontrol orkestrasyonu; Shiny UI coupling içermez.
- `R/module_health_overview.R`: overview tab helpers.
- `R/module_health_connectivity.R`: DB/LLM/TTS/STT/image connectivity helpers.
- `R/module_health_storage.R`: storage/path/index/log/disk helpers.
- `R/module_health_runtime.R`: worker/runtime/memory/session/package/OS/CPU-core helpers.
- `R/module_health_security.R`: SSO/env/secret-redaction/DB-schema-readiness helpers.
- `R/module_health_diagnostics.R`: diagnostics table/remediation helpers.
- `R/module_health.R`: stable coordinator module.
- `www/css/health_dashboard.css` and `www/js/health_dashboard.js`: local-only dashboard assets.

Health checks must remain safe, non-destructive, lightweight, and offline-compatible. They must not mutate production data and must not call public internet endpoints. Optional integrations should degrade to `not_configured` or `unknown` without unhandled errors.

Secrets must always be redacted: never print raw credentials, tokens, or API keys.

Path actions intentionally copy full paths to clipboard instead of attempting direct folder open; users then paste into Windows File Explorer and press Enter.

### Health Dashboard path configuration notes

This is documentation-only operational guidance from the latest production Windows VM stabilization that brought the Health Dashboard to 100%. Production Windows VM `.Renviron` files should explicitly define `MERGEN_FILES_ROOT`, `MERGEN_UPLOADS_DIR`, `MERGEN_INDEX_PATH`, `MCP_FILES_BASE`, `MERGEN_MCP_BASE_DIR`, and `MERGEN_LOG_DIR`. Keep `.Renviron` path values in forward-slash UNC form and do not double-escape backslashes there; Windows Explorer-compatible backslash conversion belongs only to Health Dashboard display/copy rendering.

`MERGEN_FILES_ROOT` must not accidentally include duplicated `/data/data`, and `MERGEN_LOG_DIR` should be explicit. UNC upload-root free-space checks may be treated as healthy when the share is writable even if WMIC cannot read the remote free-space value. For Turkish-character paths on Windows, save `.Renviron` using Windows-1254 / ANSI to avoid mojibake.

Health tooltips use CSS-only `data-health-tooltip`. Do **not** reintroduce Bootstrap tooltip initialization for health dashboard elements; it previously caused frozen tooltip artifacts during refresh/navigation.

Every new health check should return a structured result contract:

```r
id
label
status
severity
value
detail
duration_ms
checked_at
remediation
```

Focused health validation:

```r
source("tests/testthat.R", encoding = "UTF-8")

testthat::test_file("tests/testthat/test-health-check-formatters.R")
testthat::test_file("tests/testthat/test-health-check-paths.R")
testthat::test_file("tests/testthat/test-health-check-env-contract.R")
testthat::test_file("tests/testthat/test-health-check-runtime-contract.R")
```

---

### 9) If there is a bug fix, include a test when possible
Unit tests should be added when possible for helper and decision-logic changes. Previously observed regressions should not be left untested. Test additions should be aligned with repo style, small, and surgical. Especially for helper behaviors that previously caused regressions such as encoding/BOM and promise cleanup, test expectations should be resilient enough to account for event-loop timing and Windows VM differences.

For session-lifecycle helpers, keep testability in mind: repository tests may use fake Shiny-like session objects implemented either as `list` or as `environment`. Do not over-constrain helper inputs if the real contract is “has a usable `onSessionEnded` callback”.

On Windows VM, contract tests should prioritize stable behavioral invariants over rigid assumptions about serialized JSON shape, exact raw-text rendering, or platform-sensitive loader output. If the test targets a real repository contract, avoid locking to a single internal representation when equivalent forms are valid.

### 9A) Decomposing the MCP Excel path-resolution chain
- MCP context sorumlulukları `R/helpers_mcp_context.R` içinde tutulmalıdır. Bu dosya `helpers_mcp_tools` ortamını, MCP debug kapısını (`mcp_debug_enabled` / `mcp_debug_log`) ve scalar kullanıcı kimliği çözümlemeyi (`get_session_user_id`) sağlar.
- MCP bootstrap/fallback source sorumlulukları `R/helpers_mcp_bootstrap.R` içinde tutulmalıdır. Bu dosya worker/izole test bağlamlarında kritik MCP yardımcılarını `helpers_mcp_tools` ortamında hazırlar, destek dosyalarını çalışma dizininden bağımsız bulur ve bootstrap sözleşmesini doğrular.
- MCP tablo okuyucu sorumlulukları `R/helpers_mcp_table_readers.R` içinde tutulmalıdır. Bu dosya `helpers_mcp_tools$safe_read_excel_table`, `helpers_mcp_tools$safe_read_table_generic` ve `helpers_mcp_tools$create_md_table` tanımlarını sağlar.
- MCP dosya kayıt/çözümleme sorumlulukları `R/helpers_mcp_file_resolver.R` içinde tutulmalıdır. Bu dosya `helpers_mcp_tools$ensure_session_file_registry`, `helpers_mcp_tools$register_uploaded_file`, `helpers_mcp_tools$get_default_file_name`, `helpers_mcp_tools$auto_file_name` ve `helpers_mcp_tools$resolve_file_argument` tanımlarını sağlar.
- MCP dosya şeması, akıllı kolon eşleştirme, argüman normalizasyonu, grafik tipi normalizasyonu ve sonuç sütun adı güzelleştirme yardımcıları `R/helpers_mcp_schema_helpers.R` içinde tutulmalıdır. Bu dosya `helpers_mcp_tools$extract_mcp_file_schema`, `helpers_mcp_tools$find_matching_column`, `helpers_mcp_tools$find_columns_by_context`, `helpers_mcp_tools$normalize_args`, `helpers_mcp_tools$normalize_chart_type`, `helpers_mcp_tools$prettify_column_name` ve `helpers_mcp_tools$prettify_result_colnames` tanımlarını sağlar.
- MCP temel dosya özeti, kolon istatistiği, DuckDB varlık kontrolü ve yüklenen dosya üzerinde SQL çalıştırma araçları `R/helpers_mcp_basic_tools.R` içinde tutulmalıdır. Bu dosya `helpers_mcp_tools$safe_has_duckdb`, `helpers_mcp_tools$analyze_uploaded_file`, `helpers_mcp_tools$get_column_statistics` ve `helpers_mcp_tools$sql_query_uploaded_file` tanımlarını sağlar.
- MCP grafik veri hazırlama, akıllı eksen/kolon eşleştirme, çoklu seri dönüşümü ve ChartLab payload üretimi `R/helpers_mcp_chart_tools.R` dosyasında tutulmalıdır. `helpers_mcp_tools$prepare_chart_data` public adı korunmalı; bu fonksiyon tekrar `R/helpers_mcp_tools.R` içine taşınmamalıdır. Chart helper debug çıktıları raw `cat()` yerine `helpers_mcp_tools$mcp_debug_log(...)` üzerinden geçmelidir.
- MCP R-first filtrelenmiş analiz, gruplandırılmış istatistik ve analiz+grafik köprü aracı `R/helpers_mcp_analyze_visualize.R` dosyasında tutulmalıdır. `helpers_mcp_tools$analyze_and_visualize` public adı korunmalı; bu fonksiyon tekrar `R/helpers_mcp_tools.R` içine taşınmamalıdır. Smart-match debug çıktıları raw `cat()` yerine `helpers_mcp_tools$mcp_debug_log(...)` üzerinden geçmelidir.
- `global.R` içinde MCP kaynak sırası şu şekilde korunmalıdır: `R/helpers_mcp_context.R` → `R/helpers_mcp_bootstrap.R` → `R/helpers_mcp_tools.R` → `R/helpers_mcp_table_readers.R` → `R/helpers_mcp_file_resolver.R` → `R/helpers_mcp_schema_helpers.R` → `R/helpers_mcp_basic_tools.R` → `R/helpers_mcp_chart_tools.R` → `R/helpers_mcp_analyze_visualize.R`.
- `helpers_mcp_tools.R` doğrudan source edildiğinde de çalışabilmelidir. Bu nedenle `helpers_mcp_tools.R`, `R/helpers_mcp_bootstrap.R` dosyasını working-directory bağımsız fallback source köprüsüyle yükleyebilmelidir. MCP destek dosyalarının (`helpers_mcp_table_readers.R`, `helpers_mcp_file_resolver.R`, `helpers_mcp_schema_helpers.R`, `helpers_mcp_basic_tools.R`) izole test/debug/worker bağlamlarında bulunması ve sözleşme doğrulaması `R/helpers_mcp_bootstrap.R` sorumluluğudur. Bu köprü yalnızca repo kökünün `getwd()` olduğunu varsaymamalı; `repo_root_for_tests`, `MERGEN_REPO_ROOT`, `getwd()` ve üst dizin adaylarını güvenli biçimde denemelidir.
- Source-time geçici değişken temizliği warning üretmemelidir. Örneğin `.mcp_table_readers_path`, `.mcp_file_resolver_path`, `.mcp_schema_helpers_path` ve `.mcp_basic_tools_path` gibi değişkenler yalnızca `exists(..., inherits = FALSE)` kontrolünden sonra `rm()` edilmelidir. Bu temizlik sözleşmesi artık `R/helpers_mcp_bootstrap.R` içinde korunur. `tests/testthat.R` `stop_on_warning = TRUE` ile çalıştığı için source-time cleanup warning’leri suite’i kırar.
- MCP tablo okuyucu fonksiyon tanımları `R/helpers_mcp_table_readers.R` içinde kalmalı; ancak bu dosyanın tekil test/debug/app-boot bağlamlarında güvenli yüklenmesi `R/helpers_mcp_bootstrap.R` üzerinden yapılmalıdır. `helpers_mcp_tools.R` doğrudan source edildiğinde önce bootstrap dosyasını yükleyerek bu dolaylı sözleşmeyi korur. Bu sözleşme `test-mcp-bootstrap-refactor-contract.R` ve `test-mcp-table-readers-refactor-contract.R` ile korunmalıdır.
- `R/helpers_mcp_table_readers.R`, `helpers_mcp_tools$safe_read_excel_table`, `helpers_mcp_tools$safe_read_table_generic` ve `helpers_mcp_tools$create_md_table` fonksiyonlarının environment değerini `helpers_mcp_tools` olarak korumalıdır. Bu özellikle worker/MCP araç bağlamlarında `normalize_excel_path`, `resolve_readable_path` ve `path_exists_relaxed` gibi yardımcıların görünür kalması için gereklidir.
- Fonksiyon environment ataması kesinlikle `environment(get(...)) <- ...` biçiminde yapılmamalıdır. R bunu `get<-` replacement çağrısı gibi yorumlar ve app boot/test zincirini `"get<-" function not found` hatasıyla kırar. Önce fonksiyonu geçici değişkene alın, environment değerini değiştirin, sonra `assign(...)` ile geri yazın.
- `utils_excel_reader.R` içindeki global `safe_read_excel_table()` MCP ortamına kopyalanırsa environment değeri `helpers_mcp_tools` olarak yeniden bağlanmalıdır; aksi halde runtime’da `"normalize_excel_path" function not found` hatası tekrar oluşabilir.
- `helpers_mcp_tools$get_session_user_id()` SSO başlangıç placeholder değerlerini (`0`, `unknown`, `null`, `NA`, `NaN`) gerçek kullanıcı kimliği gibi kullanmamalıdır. MCP dosya çözümleme akışında global `current_user_id` fallback'i tekrar eklenmemelidir.
- `helpers_mcp_file_resolver.R` içindeki cross-bucket index lookup üretimde varsayılan kapalı kalmalıdır. Aynı dosya adı başka kullanıcı bucket'ında bulunuyorsa bu yol yalnızca geçiş/migrasyon amaçlı açık opt-in ile çalışmalıdır: `options(mergen.mcp.allow_cross_bucket_lookup = TRUE)` veya `MERGEN_MCP_ALLOW_CROSS_BUCKET_LOOKUP=true`.
- `helpers_mcp_tools`, `helpers_files`, `utils_path_helpers`, `utils_excel_reader`, `helpers_mcp_table_readers` ve `helpers_send_message_core` birlikte çalışan bir zincirdir.
- Bu alanlarda yapılan küçük değişiklikler bile özellikle Windows VM / SSO / MCP akışında regresyon üretebilir.
- `path_exists_relaxed` ve `resolve_readable_path` gibi yardımcıların yalnızca global ortamda var olduğunu varsaymak güvenli değildir; araç/worker bağlamında erişilebilirlik korunmalıdır.
- Windows’ta kısa yol (8.3) path basename’i orijinal dosya adından farklı olabilir; testlerde fiziksel basename yerine `display` / okunabilirlik / gerçek çözüm başarısı tercih edilmelidir.
- `helpers_mcp_tools$get_session_user_id()` must remain scalar and must never fall back to `session$userData$current_session_files`; that object is a file registry, not an identity source.
- MCP/file resolver helpers should not assume path helpers are available only from `globalenv()`. Keep local fallbacks such as `helpers_mcp_tools$normalize_excel_path()` for worker and isolated-test contexts.
- Resolver diagnostics must go through `helpers_mcp_tools$mcp_debug_log(...)`; do not reintroduce raw `cat("[RESOLVE] ...")` output inside `resolve_file_argument()`. Production debug output must stay off by default and be enabled only through `MERGEN_MCP_DEBUG=true` or `options(mergen.mcp.debug = TRUE)`.

MCP file resolver registry contract:
- Uploaded files must resolve through the session registry by token, display name, and basename.
- `register_uploaded_file` must preserve the registered path shape by using the resolver environment dependency `helpers_mcp_tools$normalize_excel_path`.
- Do not call or reintroduce global `normalize_mcp_path` in the registry normalization path because it can produce Windows 8.3 short-path variants.
- Avoid regressions where `.xlsx` uploads become short-path `.XLS`-looking names and are misread by Excel tooling.
- Keep absolute path rejection intact; users and tools should pass file tokens or selected/display names.

### 9B) Tool-Specific Runtime Model Resolution and Reasoning Streams

Runtime model selection must remain a single source of truth. Resolve the request model once from the active tool family, deep-thinking enabled state, deep-thinking level, and current mode, then use that same resolved model for the LLM payload, the Düşünce Akışı badge, and final-boundary request logging. The badge must never read directly from the normal model dropdown or default model when a tool-specific deep-thinking model is active.

MCP Excel uses a two-pass flow: the first pass performs tool execution, and the second pass produces the final synthesis. When enabled for a thinking-capable model, the second MCP Excel synthesis pass may use SSE to stream reasoning into the Düşünce Akışı panel. The second pass must use normalized messages rather than raw ad hoc chat history. If SSE fails or produces reasoning-like text as content, fall back to non-streaming second-pass answer generation. Do not use reasoning text as the final user-visible answer body. Avoid duplicated reasoning panels; live reasoning and persisted reasoning must not render as two visible panels in the same answer.

Model names are deployment configuration, not contract. Tests and docs must use generic model IDs or configuration keys such as `EXCEL_DEEP_LOW_MODEL`, `EXCEL_DEEP_HIGH_MODEL`, `CODING_DEEP_LOW_MODEL`, `CODING_DEEP_HIGH_MODEL`, `api_config$local_model_capabilities`, and `api_config$local_model_endpoint_map` rather than hardcoded live production model names.

Files to touch:
- Runtime model resolver changes belong in `R/helpers_api_model_tool_runtime.R`.
- Send-message runtime preparation belongs in `R/helpers_send_message_model_runtime.R`.
- MCP second-pass/SSE/fallback behavior belongs in `R/helpers_llm_worker_second_pass.R`.
- Do not add large new logic back into `R/server_send_message.R` or `R/helpers_llm_worker.R`.
- Keep `R/config_source_manifest.R` ordering correct when new helper files are introduced.

Testing expectations:
- Prefer behavior tests with synthetic model IDs.
- Do not write tests that depend on current production model names.
- Relevant regression tests include `tests/testthat/test-send-message-model-runtime-contract.R`, `tests/testthat/test-llm-worker-second-pass-contract.R`, `tests/testthat/test-api-model-config-refactor-contract.R`, `tests/testthat/test-send-message-request-lifecycle-contract.R`, and `tests/testthat/test-maintainability-ratchet.R`.
- Maintainability ratchet should be satisfied by refactoring into focused helpers, not by increasing thresholds.

### 9C) Logging wrappers must preserve caller-frame glue evaluation

- `R/config_logging.R` içindeki güvenli log sarmalayıcıları hassas karakter verilerini redakte edebilir; ancak `logger` glue çözümlemesini bozmamalıdır.
- `{nchar(token)}` gibi ifadeler, log çağrısının yapıldığı gerçek çağıran ortamda çözülmeye devam etmelidir (ör. SSO observer scope'u).
- `logger::log_*` çağrılarını generic bir dispatch helper içine taşıyıp çağıran frame'i kaybetmek bu repoda gerçek VM/SSO runtime regression üretir.
- Eğer bir log wrapper eklenecekse veya değiştirilecekse, caller environment açıkça korunmalı; yalnızca secret masking test etmek yeterli sayılmamalıdır.
- `MERGEN_LOG_DIR` and `MERGEN_LOG_THRESHOLD` are now part of the repository contract; do not hardcode `logs/` in code/tests/scripts when active logging paths are environment-configurable.
- Caller-frame logging tests should keep working-directory control inside the test scope and assert against the active configured log directory (from `MERGEN_LOG_DIR` or fallback default).
- After sourcing `app.R`, test setup should not leak real logging side effects into the rest of the suite.
- Console color logging is opt-in. Keep `MERGEN_LOG_CONSOLE_COLORS=false` as the production default so ANSI color escape sequences do not leak into Windows VM/service logs.
- Do not replace this with unconditional `layout_glue_colors` for console logs. Local colored console output may be enabled temporarily with `MERGEN_LOG_CONSOLE_COLORS=true`.

### Structured runtime error logging contract

- `shiny_error_handler()` may emit secret-redacted structured `[RUNTIME_ERROR]` JSON via `mergen_build_runtime_error_record()`.
- The global error handler must never fail because structured logging fails; keep `tryCatch` / fallback behavior.
- true streaming user-message persistence failures must be logged with `log_error_with_context(e, "TRUE_STREAM_SAVE_USER_MSG")` instead of disappearing silently.
- Do not add noisy structured logging inside hot streaming JSON-line parse loops unless there is an explicit throttling/aggregation design.
- Logs must remain secret-redacted.

---

## Test Suite and Execution Rules

In this repository, the main test suite runner is `tests/testthat.R`. `tests/testthat/helper_bootstrap.R` should be used as the bootstrap helper that initializes test context.

`helper_bootstrap.R` may sandbox filesystem and log paths via temp env vars (`MERGEN_LOG_DIR`, `MERGEN_FILES_ROOT`, `MERGEN_UPLOADS_DIR`, `MERGEN_INDEX_PATH`, `MERGEN_MCP_BASE_DIR`); contract tests must respect these env-driven paths instead of fixed repository-relative assumptions.

Tests should always be run from the repository root directory. When running tests on Windows VM, prefer a clean R session when possible. It is normal for the `summary` reporter output to end with `== DONE ==` without an explicit PASS line.

For promise/later-based tests, do not assume a single `later::run_now()` flush is always sufficient. When validating cleanup/final state, prefer a small bounded drain helper that consumes the later queue until the expected stable condition is reached.

Helper stubs used in tests must be visible in the same environment as the sourced helper functions. When changing helper files covered by tests, related test files should also be updated together.

In MCP Excel regression tests, validating based on physical Windows short-path basename can be fragile. In such tests, prioritize helper accessibility, resolution success via session registry, the `display` value, and whether the file can truly be read.

For single-record Turkish JSON/index edge cases on Windows VM, validate at contract level and tolerate equivalent serialized forms or loader-shape differences instead of treating them as product regressions.

Do not unit-test embedded NUL-byte behavior by forcing normal R character strings on Windows VM. In this repository, keep the runtime NUL guard in the helper, but write Windows-compatible tests around reliably representable path-safety rules. Avoid brittle tests that depend on platform-specific character construction behavior.

Quality-gate tests for repository scripts and entrypoint contracts should prefer parse-based inspection over fragile raw UTF-8 text scanning when possible; parse-based checks are more resilient on Windows VM.

Reasoning/SSE contract tests must remain runnable both through `source("tests/testthat.R", encoding = "UTF-8")` and individually via `testthat::test_file(...)`. If a test directly exercises helpers from `R/config_api.R`, `R/helpers_llm_response_postprocess.R`, or `R/helpers_llm_sse.R`, it must explicitly bootstrap/source those dependencies or use the established test bootstrap pattern.

Individual tests passing is not enough; tests that inspect source files must also pass when run through the full `source("tests/testthat.R", encoding = "UTF-8")` suite, because the full suite runs in a shared R session and is more sensitive to leaked warnings.

When a refactor introduces a new helper file that is also loaded indirectly by another helper, test both paths: direct `source("R/new_helper.R", ...)` and indirect source through the older public entry file. In this repo, isolated tests often source helper files before `global.R`; fallback source guards must therefore be working-directory independent and warning-free.


### Focused behavioral regression contracts

Merge commit `517f80406badfd8f393f9e0648793c3481520ea7` / PR #425 added 25 focused behavioral regression files from the 19 Sunday 31.05.2026 commits, with additions only. Treat this as contract coverage for existing helpers, not runtime feature churn; the commits compactly cover API key and endpoint fallback, Bilge Yolaç model/config/download/security/path/session helpers, UTF-8 and DB normalization boundaries, upload/MCP/Project Analysis helpers, AI Expert pronunciation, persona migration, LLM bundle extraction, quick-action intro text, and version-history label sourcing.

Future coding agents must not weaken or delete these behavioral tests to make unrelated changes pass. Treat them as executable documentation for existing helper contracts; when one fails, keep the change surgical by fixing the production helper or the narrow contract rather than rewriting the whole subsystem. Keep Turkish/UTF-8 fixtures deterministic and Windows/VM-safe. For docs-only `README.md` / `CLAUDE.md` edits, do not run R validation; review the Markdown diff only. If later code changes touch any covered boundary, run the relevant focused test(s) separately.

Protected behavioral test files:
- `tests/testthat/test-ai-expert-pronunciation-behavior.R`
- `tests/testthat/test-api-key-effective-resolution-behavior.R`
- `tests/testthat/test-api-model-endpoint-resolution-behavior.R`
- `tests/testthat/test-atomic-write-text-behavior.R`
- `tests/testthat/test-character-identity-behavior.R`
- `tests/testthat/test-claude-code-detail-level-behavior.R`
- `tests/testthat/test-claude-code-downloads-helpers-behavior.R`
- `tests/testthat/test-claude-code-model-config-behavior.R`
- `tests/testthat/test-claude-code-security-policy-behavior.R`
- `tests/testthat/test-claude-code-streaming-parsers-behavior.R`
- `tests/testthat/test-claude-code-workdir-scan-behavior.R`
- `tests/testthat/test-db-user-encoding-normalization-behavior.R`
- `tests/testthat/test-destek-db-text-normalization-behavior.R`
- `tests/testthat/test-llm-sse-delta-bundle-behavior.R`
- `tests/testthat/test-llm-text-bundle-behavior.R`
- `tests/testthat/test-mailto-encoding-behavior.R`
- `tests/testthat/test-mcp-excel-summary-behavior.R`
- `tests/testthat/test-mcp-path-normalize-behavior.R`
- `tests/testthat/test-pk-analysis-core-behavior.R`
- `tests/testthat/test-quick-action-intro-message-behavior.R`
- `tests/testthat/test-session-runtime-store-behavior.R`
- `tests/testthat/test-text-encoding-log-frame-behavior.R`
- `tests/testthat/test-upload-validator-internals-behavior.R`
- `tests/testthat/test-utils-common-text-behavior.R`
- `tests/testthat/test-version-history-label-behavior.R`


### Strict test runner rule
`tests/testthat.R` is a strict gate and should keep:

```r
stop_on_failure = TRUE
stop_on_warning = TRUE
```

Do not weaken the main runner to hide warnings. If a test produces noisy warnings only during full `test_dir()` execution, fix the test so it is deterministic and warning-safe. Source-inspection tests should avoid broad warning-prone recursive scans inside the main suite. Prefer targeted contract checks over scanning the whole repository when the test is part of the strict default runner.

Default-suite source-inspection tests must be warning-safe on Windows. Avoid warning-prone combinations such as `grepl(..., fixed = TRUE, ignore.case = TRUE, useBytes = TRUE)` inside broad scan loops. Prefer normalizing text/patterns first (for example lowercasing both) and then using fixed byte matching without `ignore.case`.

Atomic-write tests should prefer deterministic UTF-8-safe or raw-byte assertions instead of locale-dependent `readLines()` comparisons on Windows VM.

Windows-safe child-session test authoring rules:
- Avoid embedding non-ASCII repository paths directly into generated child-R scripts when this can be avoided.
- Prefer setting env vars in the parent test process and relying on inherited environment in child sessions.
- Prefer `withr::with_dir(...)` (or equivalent parent-side working-directory control) over serializing `setwd("...")` lines that may contain Turkish characters.
- For early-stop guard contracts (for example required-env preflight guards), prefer stable in-process `expect_error(...)` assertions over fragile child stdout/stderr capture.

### Current baseline coverage
- `safe_source` UTF-8 BOM + Turkish-character contract coverage (`test-safe-source-encoding-contract.R`)
- `safe_source` syntax-error passthrough coverage (real syntax errors must not be swallowed)
- `global.R` critical source-manifest ordering contract coverage (`test-global-source-manifest-contract.R`)
- production env policy contract coverage for strict `MERGEN_RUN_APP` parsing and the 25 MB upload cap (`test-production-env-policy-contract.R`)
- non-streaming LLM request-override parity coverage via `test-llm-reasoning-request-overrides.R`
- LLM content/reasoning fallback contract coverage via `test-llm-content-reasoning-fallback.R`
- maintainability ratchet coverage via `test-maintainability-ratchet.R`, including baseline score/count regression protection and Windows VM `testthat` compatibility through `expect_true(..., info = ...)`
- canonical effective user-id resolver coverage via `test-effective-user-id.R`, including SSO placeholder `0L` fallback to the live provider
- Server user-session context coverage via `test-server-user-session-context.R`, including local/SSO identity config construction and live provider fallback behavior
- Server runtime context coverage via `test-server-runtime-context.R`, including early boot contract validation for cache, identity, forward refs, state, chat runtime, and optional module attachments
- SSO live user-id provider contract coverage via `test-server-live-user-provider-contract.R`, ensuring `server.R` obtains live identity providers through `runtime_ctx$identity` and does not regress to startup snapshots
- File Manager policy/helper wiring coverage via `test-file-manager-policy-contract.R` and `test-file-manager-module-policy-wiring.R`, including delegated user-id normalization, icon HTML, timestamp formatting, and persisted refresh stale-request guards
- Bilge Yolaç UI/server split contract coverage ensuring `claudeCodeUI()` remains in `R/module_claude_code_ui.R`, `claudeCodeServer()` remains in `R/module_claude_code.R`, and the source order stays correct (`test-claude-code-ui-refactor-contract.R`)
- Bilge Yolaç model/config helper split contract coverage ensuring model/settings helpers remain in `R/helpers_claude_code_model_config.R`, process/runtime helpers remain in `R/helpers_claude_code.R`, source order stays correct, and core helper behavior is preserved (`test-claude-code-model-config-refactor-contract.R`)
- `safe_source`
- BOM-marked UTF-8 safe_source loading behavior
- tracked_future_promise task-registry cleanup behavior
- `register_session_cleanup_on_end()` / `safe_unlink_if_exists()` session-end cleanup behavior, including fake session compatibility for both `list` and `environment`-style test doubles
- database validation helpers
- file indexing helpers
- worker monitor helpers
- send-message core tool-family / stream-profile decisions
- `safe_join_path` path-safety behavior on Windows-compatible test inputs
- MCP Excel session-registry path resolution and helper-environment availability
- `config_logging.R` redaction wrappers and `dbg_dump()` behavior, including preservation of caller-frame `logger` glue evaluation
- MCP session user-id contract coverage ensuring file registries are not used as user identity (`test-mcp-session-user-id-contract.R`)
- MCP path fallback contract coverage for worker/isolated helper contexts (`test-mcp-path-fallback-contract.R`)
- MCP resolver debug-output contract coverage preventing raw `cat("[RESOLVE] ...")` production output (`test-mcp-debug-output-contract.R`)
- production console-color logging policy coverage (`test-logging-console-color-policy.R`)
- `app.R` boot-contract coverage for `boot_step(...)`, `validate_boot_state()`, `create_mergen_app()`, and `run_mergen_app()`, including strict `MERGEN_RUN_APP` autorun-flag parsing and explicit invalid `run_mergen_app(port = ...)` normalization fallback to `8009`
- caller-frame logging-wrapper behavior under Windows-safe test setup
- parse-based quality-gate coverage for `app.R`, `tests/testthat.R`, and `tests/scripts/*`
- Windows-safe file-store index regression coverage with shape-agnostic checks, including Turkish display-name edge handling
- Windows-safe atomic-write UTF-8 verification strategy
- thinking/reasoning model request_overrides contract coverage, including deep merge of `chat_template_kwargs$enable_thinking`
- true SSE request-body override coverage for `apply_model_request_overrides(body, selected_model)`
- future worker globals contract coverage for `apply_model_request_overrides`
- true SSE worker export/globals contract coverage for reasoning deltas, stop-file checks, and request overrides
- default offline baseline contract coverage for CDN/public asset dependency detection in runtime R/CSS/JS files
- warning-safe source-inspection strategy for strict `stop_on_warning` test runs
- SSE delta reasoning parser coverage for `delta$content`, `delta$reasoning`, `delta$reasoning_content`, and atomic delta/message edge cases
- production-default reasoning debug gate coverage via `MERGEN_REASONING_DEBUG=FALSE`
- production contract coverage for critical boot/runtime entry files without warning-prone broad recursive scans
- upload-size policy coverage for the 25 MB default and >25 MB rejection path
- file-manager client-side upload guard coverage via `test-file-manager-upload-limit-ui.R`
- File Manager policy helper contract coverage for upload limits, allowed extensions, and attach-rule hint text (`test-file-manager-policy-contract.R`)
- File Manager UI/server split coverage preserving `fileManagerUI(id)` in `R/module_file_manager_ui.R` and `fileManagerServer(...)` in `R/module_file_manager.R` (`test-file-manager-ui-refactor-contract.R`)
- File Manager module wiring coverage for policy-helper usage and persisted refresh stale-request protection (`test-file-manager-module-policy-wiring.R`)
- DB helper modularization contract coverage for `helpers_db_connection.R`, `helpers_db_validation.R`, and `helpers_database.R` source ordering (`test-db-refactor-contract.R`)
- chat message formatting refactor coverage for `helpers_chat_message_formatting.R`, including normal message formatting, empty data handling, and `ReasoningContent` propagation (`test-chat-message-formatting-refactor-contract.R`)
- Bilge Yolaç document extractor refactor coverage for `helpers_claude_code_document_extractors.R` source ordering and public extractor helper availability (`test-claude-code-document-extractors-refactor-contract.R`)
- Bilge Yolaç document maintainability ratchet coverage ensuring `helpers_claude_code_documents.R` stays below the intended extractor-refactor thresholds (`test-claude-code-document-extractors-maintainability-contract.R`)
- maintainability report support via `tests/scripts/maintainability_report.R` for tracking large files, line counts, and function counts without making the report itself a failing test gate
- strict test runner compatibility for `source("tests/testthat.R", encoding = "UTF-8")`
- source manifest contract coverage for `global.R` `safe_source(...)` existence/order/duplicate protection (`test-source-manifest-contract.R`)
- secret leak contract coverage across runtime files/tests with masking for known fake redaction fixtures (`test-secret-leak-contract.R`)
- runtime network-boundary contract coverage for accidental public URL/CDN dependencies with comment stripping, SVG namespace/example placeholders/internal host allow rules, optional `MERGEN_ALLOWED_INTERNAL_URL_REGEX`, and vendored offline asset skips for `www/js/highlight.min.js` + `www/css/all.min.css` (`test-runtime-network-boundary-contract.R`)
- expanded production parse contract coverage for additional high-risk runtime files (`test-production-contracts.R`)
- production BAT startup contract for UNC-safe `pushd`, app-root execution, Rscript/package preflight, and startup diagnostics through `logs/run_mergen_prod_console.log`
- runtime log-viewing contract via `view_latest_mergen_app_log.bat`, with the redundant console-log viewer files intentionally removed
- local Windows VM launcher self-test coverage for mapped-drive startup, dynamic Rscript selection, package visibility, UNC-safe log viewing, `MERGEN_PORT=8009`, and Turkish-path mojibake resistance

### Scripted validation flow (`tests/scripts/`)
- `tests/scripts/parse_sanity_check.R`: parse-only UTF-8 syntax sanity check from repo root.
- `tests/scripts/smoke_app_boot.R`: boot smoke for `app.R` without launching full runtime; verifies `safe_source`, `ui`, `server`, and `create_mergen_app()`, then confirms a `shiny.appobj` can be created.
- `tests/scripts/run_ci_local.R`: local equivalent of GitHub CI; intentionally runs `tests/testthat.R` in a **CLEAN CHILD R SESSION** to avoid global/session contamination after parse/smoke/bootstrap steps.
- `tests/scripts/run_vm_preflight_real.R`: real Windows VM preflight using real on-prem environment assumptions for production-like validation; it must check required env guards (`LOCAL_LLM_ENDPOINT`, `DB_DSN`, `AI_KEYS_MASTER`) before deeper boot/integration validation.
- `tests/scripts/maintainability_report.R`: non-failing maintainability report that lists large runtime files, approximate line counts, and function counts; use it to guide incremental refactors without changing the strict test runner.
- `tests/scripts/maintainability_report.R` remains the reporting tool, while `tests/testthat/test-maintainability-ratchet.R` is the default-suite regression guard; the ratchet is intended to prevent backsliding, not force a big-bang refactor. After the File Manager, Bilge Yolaç process/streaming, LLM SSE stream I/O, MCP analyze/visualize, Admin Response Analysis, Admin Feedback Analysis SQL query extraction, Admin Error Analysis, and Project/Resource Analysis security-summary refactors plus the related maintainability-ratchet update, the default maintainability ratchet baseline has been intentionally tightened: score `100/100`, at most `0` 800+ line files, at most `0` 25+ function files, `0` 1500+ line files, maximum file length `796`, and maximum function count `24`. Tighten these global values only when the maintainability report shows a real improvement in the corresponding global metric.

The Admin Hata Analizi extraction is now part of the ratchet baseline: `R/module_admin_hata_analizi.R` must remain below 800 lines, and `R/helpers_admin_hata_analizi.R` must remain below the helper size/function thresholds enforced by `test-maintainability-ratchet.R`.

`R/helpers_claude_code_workdir_scan.R` is budgeted at 423 lines and 14 functions.
`R/helpers_claude_code_workdir_snapshot.R` is budgeted at 450 lines and 24 functions.
`R/helpers_claude_code.R` remains budgeted at 617 lines and 29 functions.

Admin Feedback Analysis is now protected by `MERGEN_TEST_MAX_ADMIN_GERI_BILDIRIM_LINES = 799`and`MERGEN_TEST_MAX_ADMIN_GERI_BILDIRIM_FUNCTIONS = 5`. The extracted SQL helper file `R/helpers_admin_geri_bildirim_queries.R` is protected with a 260-line and 3-function budget.

### Admin Feedback Analysis modularization contract

Admin Feedback Analysis is intentionally split across a small UI/data-helper boundary, a SQL-query boundary, and the Shiny server module.

Preserve this source order in `R/config_source_manifest.R`:

```r
safe_source("R/helpers_admin_geri_bildirim.R",         encoding = "UTF-8")
safe_source("R/helpers_admin_geri_bildirim_queries.R", encoding = "UTF-8")
safe_source("R/module_admin_geri_bildirim.R",          encoding = "UTF-8")
```

Responsibilities:

* `R/helpers_admin_geri_bildirim.R`: public `adminGeriBildirimUI()`, tab UI helpers, and pure tag-counting/data-presentation helpers. It should not create Shiny observers or query the database.
* `R/helpers_admin_geri_bildirim_queries.R`: `admin_gb_feedback_queries()` and `admin_gb_fetch_data()`. This file owns the feedback SQL query package and the injectable query function boundary so tests can validate the contract without touching the database.
* `R/module_admin_geri_bildirim.R`: Shiny server orchestration, refresh/reactive flow, tab routing, and chart/table render functions.

Do not move the SQL query list or the public UI shell back into `R/module_admin_geri_bildirim.R`. The module should remain below the 800-line threshold.

Protected by:

```text
tests/testthat/test-admin-geri-bildirim-refactor-contract.R
tests/testthat/test-admin-geri-bildirim-query-contract.R
tests/testthat/test-source-manifest-contract.R
tests/testthat/test-maintainability-ratchet.R
```

The Bilge Yolaç setup and run-lifecycle extraction is also protected by a file-specific ratchet: `R/module_claude_code.R` should remain at or below `MERGEN_TEST_MAX_CLAUDE_CODE_LINES = 799` by default. The latest maintainability report after the extraction shows `R/module_claude_code.R` at 799 lines, down from 1254 lines. Only tighten this threshold when a new maintainability report proves a lower stable baseline; do not loosen it to hide unrelated growth.

The LLM worker payload extraction is also protected by file-specific ratchets: `MERGEN_TEST_MAX_LLM_WORKER_LINES = 860`, `MERGEN_TEST_MAX_LLM_WORKER_PAYLOAD_LINES = 320`, and `MERGEN_TEST_MAX_LLM_WORKER_PAYLOAD_FUNCTIONS = 12`.
- Focused hardening checks can be run directly with:
  ```r
  testthat::test_file("tests/testthat/test-server-user-session-context.R")
  testthat::test_file("tests/testthat/test-server-runtime-context.R")
  testthat::test_file("tests/testthat/test-server-module-wiring-runtime-bindings.R")
  testthat::test_file("tests/testthat/test-server-live-user-provider-contract.R")
  testthat::test_file("tests/testthat/test-sse-worker-export-contract.R")
  testthat::test_file("tests/testthat/test-offline-baseline-contract.R")
  testthat::test_file("tests/testthat/test-mcp-session-user-id-contract.R")
  testthat::test_file("tests/testthat/test-mcp-path-fallback-contract.R")
  testthat::test_file("tests/testthat/test-mcp-debug-output-contract.R")
  testthat::test_file("tests/testthat/test-logging-console-color-policy.R")
  testthat::test_file("tests/testthat/test-llm-content-reasoning-fallback.R")
  testthat::test_file("tests/testthat/test-file-manager-policy-contract.R")
  testthat::test_file("tests/testthat/test-file-manager-module-policy-wiring.R")
  testthat::test_file("tests/testthat/test-file-manager-ui-refactor-contract.R")
  testthat::test_file("tests/testthat/test-file-manager-upload-limit-ui.R")
  testthat::test_file("tests/testthat/test-config-file-store-registry-refactor-contract.R")
  testthat::test_file("tests/testthat/test-maintainability-ratchet.R")
  testthat::test_file("tests/testthat/test-pk-analysis-security-summary-contract.R")
  testthat::test_file("tests/testthat/test-claude-code-ui-refactor-contract.R")
  testthat::test_file("tests/testthat/test-claude-code-model-config-refactor-contract.R")
  testthat::test_file("tests/testthat/test-source-manifest-contract.R")
  testthat::test_file("tests/testthat/test-secret-leak-contract.R")
  testthat::test_file("tests/testthat/test-runtime-network-boundary-contract.R")
  testthat::test_file("tests/testthat/test-production-contracts.R")
  testthat::test_file("tests/testthat/test-claude-code-document-extractors-refactor-contract.R")
  testthat::test_file("tests/testthat/test-claude-code-document-extractors-maintainability-contract.R")
  ```

CI guidance: GitHub CI is intentionally infra-independent. It does **not** access the real on-prem DB or the real local LLM; placeholder env vars are only used to satisfy startup guards and validate repository boot/structure/isolated tests. Real integration/preflight checks must run on Windows VM via `run_vm_preflight_real.R`, including writable-path probes against active configured directories (active log dir from `MERGEN_LOG_DIR` or fallback default).

### Production operation
Production startup on the Windows VM uses a two-layer launcher flow.

Local VM launcher:

```bat
C:\MergenLauncher\start_mergen_prod.bat
```

Repository/app-folder launcher:

```bat
run_mergen_prod.bat
```

Do not point a Windows shortcut directly at the UNC-path copy of `run_mergen_prod.bat`. `cmd.exe` cannot reliably use UNC paths as current directories. The shortcut should target the local VM launcher under `C:\MergenLauncher`, and the local launcher should temporarily map `\\rehisds\uygulamalar` to a drive letter before calling the real app-folder launcher.

Production launcher contract:

* `MERGEN_PORT` must remain `8009`.
* `MERGEN_HOST` should remain `0.0.0.0` for the VM production profile.
* `SSO_ENABLED` should be `TRUE` for the production VM profile.
* `run_mergen_prod.bat` must call `run_mergen_prod.R`, not bypass it with a direct `shiny::runApp('.')` call.
* `run_mergen_prod.bat` should dynamically select the newest `Rscript.exe` under `C:\Program Files\R\R-*`.
* Do not reintroduce fixed-only R version checks that fall back to the wrong `Rscript.exe` while a newer R is installed.
* The launcher should print R diagnostics, including `R.home()`, R version, `R_LIBS_USER`, and `.libPaths()`.
* Package visibility checks should use the same Rscript session that will launch production.
* Avoid `pushd "%APP_DIR%."`; use `pushd "%APP_DIR%"` if entering the app folder is needed.
* Avoid fragile parenthesized `if (...)` blocks containing `echo` lines with literal parentheses; this has caused CMD parse errors such as `from was unexpected at this time`.

Runtime log viewer:

```bat
view_latest_mergen_app_log.bat
```

The log viewer must remain UNC-safe. It should not depend on launching directly from a UNC current directory and must not regress to a plain `pushd "%~dp0"` pattern. It should use mapped-drive logic or another UNC-safe equivalent.

Startup failure diagnostics should be read from the launcher console output and/or:

```text
logs/run_mergen_prod_console.log
```

Normal runtime logs are:

```text
logs/mergen_YYYYMMDD.log
```

### Production launcher self-test

The Windows VM has a local self-test for the production launcher chain:

```bat
C:\MergenLauncher\test_mergen_prod_launcher.bat
```

This self-test must not start the Shiny app. It validates the launch environment only.

It should check:

* mapping `\\rehisds\uygulamalar` to a temporary drive,
* discovering the real `MERGEN Bilge` app folder without hard-coding Turkish path segments such as `Geliştirme`,
* presence of `run_mergen_prod.bat`, `run_mergen_prod.R`, and `app.R`,
* `MERGEN_PORT=8009` in `run_mergen_prod.bat`,
* absence of the unsafe `pushd "%APP_DIR%."` pattern,
* absence of UNC-fragile `pushd "%~dp0"` behavior in the log viewer,
* dynamic newest-Rscript detection under `C:\Program Files\R\R-*`,
* R library paths and required package visibility,
* required `.Renviron` / environment variables,
* port 8009 status.

The PowerShell self-test should be ASCII-safe where possible. Do not hard-code Turkish path components in the test. It should discover the app folder by searching under the mapped drive for `run_mergen_prod.bat` inside a folder named `MERGEN Bilge`.

For R snippets inside the PowerShell test, prefer writing temporary ASCII R scripts and executing those scripts instead of passing complex package vectors through fragile `Rscript -e` quoting. This prevents errors such as R interpreting `arrow` as an object instead of the string `"arrow"`.

Expected successful result:

```text
[RESULT] PASSED
```

---

## Reasoning Flow for Düşünüyorum=TRUE Models (New Standard)

In this codebase, the pre-response/in-response experience for models with thinking capability has been updated.

### Premium reasoning card behavior
- If `local_model_capabilities[[model]]$thinking == TRUE`, show the premium reasoning card instead of the classic typing animation.
- The card reuses the existing `#typing-animation-wrapper` container; it is opened with `premiumReasoningStart` on both thinking and non-thinking model paths.
- On the server side, send `premiumReasoningStart` at the beginning, `premiumReasoningStreamStart` during streaming, and `premiumReasoningReset` or `premiumReasoningError` on completion/error.
- The old “Düşünüyorum” snake animation has been fully removed (including `typing-indicator.css`, `typing_animation.js`, `ui.R` registration, and `app_core.js` cleanup).
- For non-thinking models, the `simulated` flag (inverse of `thinking_model_active`) is sent only when reasoning content is not expected; if real `reasoning_delta` is absent, synthetic phase text is shown sequentially on the client.
- Instead of the classic ring, insert an empty panel shell with `data-panel-takeover="true"`.
- In tools that depend on a thinking model (such as Kodlama Desteği/Excel Analizi), the panel model label must be derived from the `tool-resolved model`.

### UI/JS principles
- State machine: `idle → preparing → thinking → streaming → interrupted/error`
- Phase rotation: 2.6s
- Simulated phase text cadence: 1.8s
- Flicker guard: 420ms
- Minimum visibility: 1200ms
- Model names and error text must be HTML-escaped (XSS prevention).
- The `MutationObserver` in `app_core.js` must skip `TypingAnimationManager.create(...)` for shells marked with `data-panel-takeover="true"` to prevent duplicate animation/flicker.

### Live reasoning panel and persistence
- Reasoning content is streamed token-by-token in the live panel and does not disappear when the answer finishes; it remains collapsible in `completed/interrupted` states.
- Persistence is DB-backed via `MB_Messages.ReasoningContent`.
- On non-streaming paths, reasoning content must also be carried from worker output through message persistence, and `MB_Messages.ReasoningContent` must not be empty for thinking-model responses.
- In chat-history rendering, the archive block must be produced from a single source of truth; do not allow a duplicated live-panel + archive layered view.
- Simulated flows (without real reasoning text) must not be persisted to the bubble/archive; the panel should fade out as soon as answer streaming starts.

### Model-specific request_overrides contract
For thinking/reasoning models, `thinking = TRUE` alone must not be treated as sufficient; some local OpenAI-compatible endpoints require extra request fields to emit reasoning.
The `local_model_capabilities[[model]]$request_overrides` field in `R/config_api.R` must be preserved.

For Gemma-style models, use the following override when needed to enable reasoning flow:

```r
request_overrides = list(
  chat_template_kwargs = list(
    enable_thinking = TRUE
  )
)
```

`apply_model_request_overrides(body, selected_model)` must be applied after constructing the true SSE streaming body and before sending the HTTP request.
The same helper must also be applied on non-streaming LLM paths; otherwise streaming and non-streaming behavior diverges.
`R/helpers_llm_api.R::call_local_llm()` is explicitly part of this contract and must keep calling `apply_model_request_overrides(body, selected_model)` after building the non-streaming body and after temperature handling; removing this call can make tool/fallback/non-streaming routes diverge from true SSE streaming behavior for Düşünüyorum/reasoning models.
For helper visibility on the true streaming future worker side, keep `apply_model_request_overrides = apply_model_request_overrides` in `tracked_future_promise(..., globals = list(...))` within `R/server_handler_true_streaming.R`.
Kimi-style models may send reasoning as `delta$reasoning`; Gemma-style models may fall back to normal `delta$content` streaming with empty `ReasoningContent` when the override is missing.

### LLM content/reasoning fallback contract
- For thinking/reasoning models, empty `message$content` or `delta$content` must not overwrite usable `reasoning` / `reasoning_content`.
- `extract_llm_content_and_sources()` must only replace `ai_content` with non-empty candidates.
- Reasoning fallback should be applied after all normal content extraction attempts.
- This contract is protected by `tests/testthat/test-llm-content-reasoning-fallback.R`.

### Reasoning debug log policy
`[REASONING DEBUG]` lines must remain disabled by default in production.
Debug should be enabled only for temporary diagnostics via `MERGEN_REASONING_DEBUG=TRUE`.
A production-behavior patch must not leave debug output permanently enabled.

### Critical note for CSS regressions
- `.reasoning-panel.rp-live` must remain visible in the base state (`opacity: 1`, `transform: translateY(0)`).
- The entry animation must start from the `0%` frame of `rp-enter` with `both` fill mode.
- Otherwise, opacity can drop back to 0 during state transitions such as `data-state="completed"`, causing the panel to disappear.
- To prevent `[object Object]` regressions in the panel title, a client-side defense such as `sanitizeModelLabel()` is mandatory.
- The purple bottom-edge shimmer (`rp-shimmer`) should run only during active thinking/streaming phases and must be disabled in `completed`, `interrupted/stopped`, and `error` states, as well as under `prefers-reduced-motion`.

---

## What MERGEN Bilge Is

**MERGEN Bilge** is a Turkish-language AI assistant platform built on **Shiny** and **shinydashboard** for internal/corporate usage.

It combines:

- AI chat,
- conversation history and saved chats,
- file upload / preview / context injection,
- image generation,
- summarization,
- project/resource analysis,
- process guidance,
- character-based personas,
- AI Expert proactive speech,
- TTS/STT,
- support center,
- analytics/admin screens,
- version history,
- and a separate coding workspace called **Bilge Yolaç**.

The application is designed for a polished, immersive experience:

- cinematic startup,
- welcome screen,
- dynamic greeting,
- mythological character system,
- dark theme,
- audio and animation layers.

---

## High-Level Boot Flow

### Entry point: `app.R`
`app.R` is the real entry point and must be treated as special.

It does the following:

1. validates required boot files (`R/utils_safe_source.R`, `global.R`, `ui.R`, `server.R`),
2. sources `R/utils_safe_source.R`,
3. loads `global.R` via `safe_source()`,
4. loads `ui.R` via `safe_source()`,
5. loads `server.R` via `safe_source()`,
6. registers `www/` subdirectories with `addResourcePath()`,
7. registers `www/` root under the `img` prefix,
8. starts the app with `runApp(shinyApp(ui, server), ...)`.

### Why `app.R` matters
This repo intentionally avoids relying on plain `runApp(".")` logic inside the app because:

- Windows VM path behavior is fragile,
- `Ctrl+Enter` execution is used in practice,
- static asset resolution can break if resource paths are not explicitly registered.

If startup or missing asset issues appear, check `app.R` first.

Boot hardening note: `app.R` now includes explicit boot validation and fail-fast checks; coding agents must preserve `validate_boot_state()`, `create_mergen_app()`, and `run_mergen_app()` names/behaviors because smoke validation depends on them. `MERGEN_RUN_APP` autorun decisions now rely on explicit truthy/falsy normalization, and `run_mergen_app()` must re-normalize explicit call-time `port` inputs (not only env-derived defaults); invalid/missing/non-numeric/out-of-range values must deterministically fall back to `8009`. Boot-contract tests intentionally restore test stubs and isolate side effects after sourcing `app.R`, so entrypoint verification does not contaminate the remaining suite.

### Production runtime entrypoint contract

Keep the real `run_mergen_prod.bat` in the application root. If operators need a Desktop launcher, create a Desktop shortcut to the root BAT; do not copy the BAT to Desktop. The BAT relies on `%~dp0` to locate the app root, so a copied Desktop BAT will incorrectly run from Desktop and may create Desktop-local `logs/` output.

The BAT must continue using `pushd "%~dp0"` rather than `cd /d "%~dp0"` because production may run from a UNC/network path. `pushd` temporarily maps the UNC path to a drive letter and prevents the classic CMD error “CMD does not support UNC paths as current directories.”

`run_mergen_prod.bat` must keep writing startup/preflight/stdout/stderr diagnostics to `logs/run_mergen_prod_console.log` and must continue doing an Rscript/package preflight before app launch. Missing required packages should fail fast before startup. Optional `R_LIBS_USER` may be set for a fixed production package library on the Windows VM.

Do not reintroduce a dedicated live console-log viewer unless there is a clear operational need.

### Production log viewing contract

Runtime log viewing should use `view_latest_mergen_app_log.bat`. This viewer tails the newest `logs/mergen_*.log` file in read-only mode and can remain open while users interact with the app. It must not write to logs or stop the app.

`logs/run_mergen_prod_console.log` should be treated as a startup diagnostic log for Rscript, package preflight, boot messages, stdout, and stderr. It does not need a live viewer in normal operation.

The removed files `view_mergen_prod_console_log.bat` and `view_mergen_prod_console_log.ps1` should not be reintroduced casually. They were redundant for normal operations and were prone to Turkish mojibake in classic `cmd.exe`. If startup diagnostics are needed, inspect `logs/run_mergen_prod_console.log` directly or rely on `run_mergen_prod.bat` printing the last log lines on failure.

---

## Encoding and Safe Sourcing

The canonical `safe_source()` helper lives in `R/utils_safe_source.R`.

`app.R` sources that file first, then calls `safe_source()` for `global.R`, `ui.R`, and `server.R`.

Fallback behavior is intentionally defensive and BOM-aware:

- first tries standard `source(..., encoding = "UTF-8")`,
- if it encounters encoding/BOM-related errors or warnings, it falls back,
- reads the file as raw bytes,
- strips UTF-8 BOM when present,
- attempts `UTF-8`, `WINDOWS-1254`, and `latin1`,
- then runs parse/eval recovery in the target environment.

This design exists because this codebase has had real encoding sensitivity, especially on Windows and SSO-enabled VM environments, including BOM-marked UTF-8 files.

### Source manifest newline normalization contract

The source manifest parser is sensitive to line-ending normalization. In `R/bootstrap_source_manifest.R`, `source_manifest_read_file_with_encoding()` must normalize Windows CRLF and legacy CR line endings to a real LF newline character before `parse(text = ...)` validation. Do not replace this with a literal escaped newline replacement that turns line breaks into the character "n"; doing so can make valid multi-line R files fail with "unexpected symbol" during manifest validation. This boundary protects parse validation only and should not be used as a reason to broaden encoding or source-loading changes.

### Practical rule
If you add a new R file, it should be source-safe and UTF-8 safe.

---

## Required Environment Variables

The application validates required environment variables in `R/config_file_store.R`.

These are mandatory:

- `LOCAL_LLM_ENDPOINT`
- `DB_DSN`
- `AI_KEYS_MASTER`

If one is missing, startup stops with an explicit error.

### Important optional environment groups

#### Database
- `DB_DSN`
- `DB_DSN_2`
- `DB_DSN_3`
- `DB_CLIENT_ENCODING`
- `DB_NAME_ENCODING`

#### LLM
- `LOCAL_LLM_ENDPOINT`
- `LOCAL_LLM_API_KEY`
- `LOCAL_LLM_ENDPOINT_ALT`
- `LOCAL_LLM_ENDPOINT_ALT_API_KEY`
- `FILTER_MODEL`
- `AI_EXPERT_MODEL`
- `DESTEK_CHATBOT_MODEL`
- `MERGEN_ALLOW_DEFAULT_API_KEY`
- `MERGEN_REQUIRE_PERSONAL_API_KEY`
- `MERGEN_DEFAULT_API_KEY`

#### Vision (görsel anlama)
- `MERGEN_VISION_MODELS` — `;`/`,`-separated list of model IDs that support image input (Image Input). Optional; the Kodlama Uzmanı deep-thinking models (`CODING_DEEP_*`) are auto-marked vision-capable regardless. Model IDs may contain spaces, so the list is split on `;`/`,` only.
- `MERGEN_ENABLE_VISION` — global kill-switch. Default ENABLED (capability-primary); set to `false`/`0`/`off`/`hayır`/`kapalı` to disable vision everywhere. Equivalent option: `options(mergen.vision_enabled = FALSE)`.

#### TTS
- `LOCAL_TTS_ENDPOINT`
- `LOCAL_TTS_API_KEY`
- `LOCAL_TTS_MODEL`
- `LOCAL_TTS_VOICE`
- `LOCAL_TTS_TIMEOUT`
- `LOCAL_TTS_VERIFY_SSL`

#### STT
- `LOCAL_STT_ENDPOINT`
- `LOCAL_STT_MODEL`

#### SSO / Keycloak
- `SSO_ENABLED`
- `SSO_KEYCLOAK_URL`
- `SSO_REALM`
- `SSO_CLIENT_ID`
- `SSO_VALIDATE_ISSUER`
- `SSO_VALIDATE_EXPIRY`
- `SSO_TOKEN_REFRESH_MARGIN`
- `SSO_DEBUG`

#### Bilge Yolaç / Claude Code
- `CLAUDE_CODE_CLI_PATH`
- `CLAUDE_CODE_DEFAULT_WORKDIR`
- `CLAUDE_CODE_TIMEOUT`
- `CLAUDE_CODE_MODEL`
- `CLAUDE_CODE_MAX_CONCURRENT`
- `CLAUDE_CODE_PERSIST_SESSIONS`

#### Bilge Yolaç Plugins
- `CLAUDE_CODE_PLUGINS_ALLOW_TOGGLE`

#### Image generation
- `IMAGE_GEN_ENDPOINT`
- `IMAGE_GEN_MODEL`
- `IMAGE_GEN_TIMEOUT`
- `TRANSLATION_MODEL`

#### Service desk
- `SERVICE_DESK_API_KEY_URL`
- `SERVICE_DESK_RATE_LIMIT_URL`

#### File storage
- `MCP_FILES_BASE`

---

## Real Architecture

## Root-Level Files

- `app.R` - startup entry point, safe sourcing, resource path registration, app launch
- `global.R` - global options, locale handling, dependency sourcing order
- `ui.R` - full `shinydashboard` UI composition
- `server.R` - main server wiring and session flow
- `welcome_screen.R` - welcome screen data and quick action definitions
- `version_history.md` - source of the Yenilikler / version history page
- `README.md` - repository overview
- `CLAUDE.md` - coding-agent guide
- `ai_rehber.md` - knowledge base for Support chatbot and AI Expert reference

## Root-Level Directories (non-R/)

- `R/` - all application R modules, helpers, and configuration files
- `www/` - static assets (CSS, JS, CodeMirror, images, fonts)
- `bilge_yolac_plugins/` - Bilge Yolaç auto-discovered plugin directory. Each subdirectory is one plugin with `plugin.json` and optional `skills/`, `commands/`, `agents/`, `hooks/`, `mcp/`, `templates/`. No CLI, no internet required.
- `bilge_yolac_downloads/` - persistent directory where files generated by Bilge Yolaç (document summaries, agent outputs, etc.) are exposed as downloadable links. It is registered by `global.R` into Shiny with the `bilge_yolac_downloads` resource path name. It is included in the repository as empty via `.gitkeep`.

---

## `global.R` Load Order

The sourcing order in `global.R` is critical and should be respected.

### Group 1 - Foundation
Loaded first, no application-layer assumptions:

- `R/config_packages.R`
- `R/utils_common.R`
- `R/config_logging.R`
- `R/utils_rate_limiter.R`
- `R/helpers_worker_monitor.R`
- `R/utils_path_helpers.R`
- `R/utils_safe_path.R`
- `R/utils_atomic_write.R`
- `R/utils_upload_validator.R`
- `R/utils_log_redact.R`
- `R/utils_session_cleanup.R`
- `R/utils_safe_worker_run.R`
- `R/utils_file_index.R`
- `R/utils_excel_reader.R`

### Group 2 - Configuration
Defines application-wide configuration:

- `R/config_sso.R`
- `R/config_file_store.R`
- `R/config_file_store_index_lock.R`
- `R/config_file_store_index_mutation.R`
- `R/config_file_store_registry.R`
- `R/config_characters.R`
- `R/config_version_history.R`
- `R/helpers_vision_model_capabilities.R`
- `R/helpers_deep_thinking_model_capabilities.R`
- `R/config_api.R`
- `R/helpers_api_key_crypto.R`
- `R/config_claude_code.R`
- `R/config_claude_code_plugins.R`

> `R/helpers_vision_model_capabilities.R` and `R/helpers_deep_thinking_model_capabilities.R` are loaded BEFORE `R/config_api.R` so the config can mark per-model `vision` capability and register Derin Düşünme capability/endpoint entries at build time (see the vision pipeline and API model configuration sections). `R/helpers_api_key_crypto.R` owns the user API key encrypted storage layer and loads after `R/config_api.R`.

### Group 3 - Database and SQL
Core persistence and DB access:

- `R/helpers_db_connection.R`
- `R/helpers_db_validation.R`
- `R/helpers_chat_message_formatting.R`
- `R/helpers_db_chat_readers.R`
- `R/helpers_database.R`
- `R/library_queries.R`
- `R/config_sql_loader.R`

### Group 4 - Core Helpers
Shared utilities used across modules:

- `R/helpers_language.R`
- `R/helpers_messaging.R`
- `R/helpers_mcp_context.R`
- `R/helpers_mcp_bootstrap.R`
- `R/helpers_mcp_tools.R`
- `R/helpers_mcp_table_readers.R`
- `R/helpers_mcp_file_resolver.R`
- `R/helpers_mcp_schema_helpers.R`
- `R/helpers_mcp_basic_tools.R`
- `R/helpers_mcp_chart_tools.R`
- `R/helpers_mcp_analyze_visualize.R`
- `R/helpers_chartlab.R`
- `R/helpers_image_gallery.R`
- `R/helpers_preview.R`
- `R/helpers_file_pipeline.R`
- `R/helpers_files.R`
- `R/helpers_file_manager_policy.R`
- `R/helpers_file_manager_context_policy.R`
- `R/helpers_file_manager_table.R`
- `R/helpers_file_manager_refresh_guard.R`
- `R/helpers_file_manager_session_registry.R`
- `R/helpers_file_manager_runtime.R`
- `R/helpers_file_manager_storage.R`
- `R/helpers_chat_runtime.R`
- `R/helpers_send_message_core.R`
- `R/helpers_vision_context.R`
- `R/helpers_quick_action_intro_messages.R`
- `R/helpers_summarization_modes.R`
- `R/helpers_summarization_prompts.R`
- `R/helpers_followup_questions.R`
- `R/helpers_deep_analysis.R`
- `R/helpers_pk_analysis_core.R`
- `R/helpers_pk_analysis_filters.R`
- `R/helpers_pk_analysis_query_selection.R`
- `R/helpers_sso.R`
- `R/helpers_destek_database.R`
- `R/helpers_admin_analytics.R`
- `R/helpers_health_formatters.R`
- `R/helpers_health_runtime_checks.R`
- `R/helpers_health_checks.R`
- `R/helpers_ai_expert.R`
- `R/helpers_ai_expert_chunking.R`
- `R/helpers_claude_code_upload_folder.R`
- `R/helpers_claude_code_model_config.R`
- `R/helpers_claude_code_session_context.R`
- `R/helpers_claude_code_dir_ui.R`
- `R/helpers_claude_code_process.R`
- `R/helpers_claude_code.R`
- `R/helpers_claude_code_streaming.R`
- `R/helpers_claude_code_formatters.R`
- `R/helpers_claude_code_downloads.R`
- `R/helpers_claude_code_workdir_snapshot.R`
- `R/helpers_claude_code_plugins.R`
- `R/helpers_claude_code_document_extractors.R`
- `R/helpers_claude_code_documents.R`

### Group 5 - LLM Integration Layer
Model calls, tool formatting, SSE, worker execution:

- `R/helpers_llm_tool_formatters.R`
- `R/helpers_llm_response_postprocess.R`
- `R/helpers_llm_api.R`
- `R/helpers_llm_stream_io.R`
- `R/helpers_llm_sse_events.R`
- `R/helpers_llm_sse.R`
- `R/helpers_llm_worker.R`

### Group 6 - Shiny Modules
User-facing and system-facing modules.

#### Chat and messaging
- `R/module_chat_history.R`
- `R/module_saved_chats.R`
- `R/module_message_search.R`
- `R/module_chat_search.R`
- `R/module_followup_questions.R`
- `R/module_chat_actions.R`
- `R/module_chat_export.R`
- `R/module_feedback.R`

#### Files and media
- `R/module_file_manager_ui.R`
- `R/module_file_manager.R`
- `R/module_file_preview.R`
- `R/module_image_generation.R`
- `R/module_image_gallery.R`
- `R/module_summarization.R`

#### Settings
- `R/module_settings_kisisel.R`
- `R/module_settings_yapilandirma_ui.R`
- `R/module_settings_yapilandirma.R`
- `R/module_settings.R`
- `R/module_api_key.R`

#### AI / audio / character experience
- `R/module_ai_processing.R`
- `R/module_ai_expert.R`
- `R/module_tts.R`
- `R/module_tts_visualizer.R`
- `R/module_stt.R`
- `R/module_character_video.R`

#### Identity / session / startup / Bilge Yolaç
- `R/module_sso.R`
- `R/module_session_timeout.R`
- `R/module_performance.R`
- `R/module_user_identity.R`
- `R/module_startup_screen.R`
- `R/module_quick_actions.R`
- `R/module_claude_code_plugins.R`
- `R/module_claude_code_ui.R`
- `R/module_claude_code_akis.R`
- `R/module_claude_code.R`

#### Analysis
- `R/module_proje_kaynak_analizi.R`

#### Support
- `R/module_destek_yardim.R`
- `R/module_destek_hakkinda.R`
- `R/module_destek_surum.R`
- `R/module_destek_hata_bildir.R`
- `R/module_destek_geri_bildirim.R`
- `R/module_destek.R`

#### Admin
- `R/module_admin_genel_bakis.R`
- `R/module_admin_kullanici_analizi.R`
- `R/module_admin_yz_performans.R`
- `R/module_admin_geri_bildirim_genel.R`
- `R/module_admin_sohbet_kalitesi.R`
- `R/module_admin_zaman_analizi.R`
- `R/module_admin_gelismis_analizler.R`
- `R/module_admin_analytics.R`
- `R/helpers_admin_geri_bildirim.R`
- `R/module_admin_geri_bildirim.R`
- `R/module_admin_hata_analizi.R`
- `R/helpers_admin_yanit_analizi.R`
- `R/module_admin_yanit_analizi.R`
- `R/module_health_worker_metrics.R`
- `R/module_health_overview.R`
- `R/module_health_connectivity.R`
- `R/module_health_storage.R`
- `R/module_health_runtime.R`
- `R/module_health_security.R`
- `R/module_health_diagnostics.R`
- `R/module_health.R`
- `R/module_chartlab.R`

### Group 7 - Server-side Handlers and Observers
Wiring and runtime flow. Welcome recency correctness depends on **both** refresh timing (saved chats refreshed before welcome re-render) and recency sorting semantics (`last_message_timestamp` preference):

- `R/server_session_cache.R`
- `R/server_init_forward_refs.R`
- `R/server_init_user_session.R`
- `R/server_runtime_context.R`
- `R/server_init_session_state.R`
- `R/server_init_chat_runtime.R`
- `R/server_outputs_chat.R`
- `R/server_llm_response_handlers.R`
- `R/server_handler_summarization.R`
- `R/server_handler_image_generation.R`
- `R/server_handler_true_streaming.R`
- `R/server_send_message.R`
- `R/server_tts_handlers.R`
- `R/server_music_handlers.R`
- `R/server_ai_expert_handlers.R`
- `welcome_screen.R`
- `R/welcome_screen_modern.R`
- `R/server_welcome_handlers.R`
- `R/server_observers_settings.R`
- `R/server_observers_storage.R`
- `R/server_observers_files.R`
- `R/server_observers_saved_chats.R`
- `R/server_observers_image_gallery.R`
- `R/server_observers_chat_ui.R`
- `R/server_observers_navigation.R`
- `R/server_observers_file_clicks.R`
- `R/server_observers_startup.R`
- `R/server_observers_chat_input.R`
- `R/server_observers_misc.R`
- `R/server_outputs_downloads.R`

---

## UI Structure

`ui.R` defines the main sidebar and tab structure.

### Main navigation
- `Ana Söyleşi`
- `Söyleşi Yönetimi`
  - `Söyleşi Geçmişi`
  - `Kayıtlı Söyleşiler`
  - `Görsel Galerisi`
- `Bilge Yolaç`
- `Dosya Yönetimi`
- `Ayarlar`
  - `Kişiselleştirme`
  - `Yapılandırma`
- `Destek`
  - `Yardım Merkezi`
  - `Geri Bildirim & Hata`
  - `Yenilikler`
  - `Hakkında`
- dynamic admin menu for authorized users

### UI assets
The UI loads a large amount of static assets from `www/`:

- CSS themes
- JS handlers
- CodeMirror bundles
- Three.js files
- support page assets
- SSO assets
- Bilge Yolaç assets
- welcome screen assets
- TTS/STT/music scripts

### Important static directories
- `www/css/`
- `www/js/`
- `www/codemirror/`
- `www/lib/`
- `www/characters/`
- root files under `www/` exposed via `/img/...`

---

## Server Flow

`server.R` is the main **composition root** of the application.

It should remain the central wiring layer, but not become a dumping ground for every startup helper, reactive flag definition, or wrapper closure. Recent cleanup moved some of that responsibility into dedicated `R/server_init_*.R` files and the early `ServerRuntimeContext` boundary so that `server.R` stays readable while behavior remains unchanged.

### Current server initialization helper layer

The following files exist specifically to reduce orchestration coupling in `server.R`:

- `R/server_init_forward_refs.R` - delayed binding wrappers for welcome and send-message flows
- `R/server_init_user_session.R` - local/SSO identity setup, user config, live current-user provider, and compatibility session writes
- `R/server_runtime_context.R` - early boot contract object for cache, identity, forward refs, state, and chat runtime
- `R/server_init_session_state.R` - session-local reactive state and startup feedback loading
- `R/server_init_chat_runtime.R` - chat runtime helper closures such as reset/add-message/streaming wrappers

Rule:
- keep `server.R` as the wiring/composition layer
- put reusable startup/setup helpers into `server_init_*` or a small context helper when there is a clear boot contract
- do not move business logic into `server_init_*`
- do not use `ServerRuntimeContext` as a broad service locator

At a high level it performs:

1. session cache initialization,
2. SSO/local auth setup,
3. server runtime context initialization,
4. API key module wiring,
5. performance and health module startup,
6. support module startup,
7. settings initialization,
8. forward-reference attachment to runtime context,
9. Bilge Yolaç startup,
10. media stack initialization,
11. file manager / preview wiring,
12. chat state initialization and attachment to runtime context,
13. observers and navigation,
14. welcome handlers,
15. gallery / saved chat / history wiring,
16. chat engine / LLM response pipeline and chat runtime attachment,
17. TTS handlers,
18. final `send_message` function registration.

### SSO behavior
The application supports two auth flows:

#### Local development
When `SSO_ENABLED=FALSE`:

- `resolveUserIdentity()` derives the local/system identity,
- `get_or_create_user()` ensures DB user presence,
- session user data is populated synchronously.

#### Production / VM / Keycloak
When `SSO_ENABLED=TRUE`:

- `ssoAuthServer()` validates token flow,
- session starts with temporary user placeholders,
- once authenticated, Keycloak claims are mapped,
- DB user is created/updated,
- session becomes fully initialized.

If anything “works locally but not on VM”, SSO and encoding are the first things to inspect.

### SSO JWT signature and fail-closed authorization boundary

The SSO authentication boundary is security-sensitive. JWT claims must not be trusted until the token signature has been verified against Keycloak JWKS public keys.

Current contract:
- `R/helpers_sso_signature.R` owns JWT signature verification, JWK/JWKS handling, public-key conversion, and signature checking helpers.
- `R/helpers_sso_signature.R` must be loaded before `R/helpers_sso.R` through `R/config_source_manifest.R`.
- `validate_jwt_token()` must verify the JWT signature before trusting issuer, expiry, username, role, or any other claim.
- Keep algorithm-confusion protection intact: reject `alg=none`, HMAC/HS algorithms, malformed tokens, tampered payloads, tampered signatures, missing or unknown `kid` values, and unusable JWKS keys.
- The allowed asymmetric algorithms are RS256, RS384, and RS512 unless the implementation and focused tests are intentionally updated together.
- `SSO_VALIDATE_SIGNATURE` defaults to TRUE. Treat disabling it as a temporary operational escape hatch only, not normal production behavior.
- `SSO_JWKS_URL` is an optional JWKS endpoint override; otherwise the endpoint is derived from the configured issuer/Keycloak realm.
- `SSO_JWKS_CACHE_TTL` controls JWKS cache lifetime. Unknown key IDs must be handled safely for key rotation and must not silently bypass verification.
- Authorization must remain fail-closed. DB connection failures, query errors, empty usernames, missing users, and ambiguous authorization states must deny access rather than granting fallback USER access.

Protected by:
- `tests/testthat/test-sso-jwt-signature.R`
- `tests/testthat/test-sso-authorization-failclosed.R`
- `tests/testthat/test-sso-signature-parsing.R`
- `tests/testthat/test-sso-jwt.R`

#### Windows VM / SSO / SQL Server Encoding Guardrails
- In production-like Windows VM runs, `.Renviron` must define `DB_CLIENT_ENCODING=WINDOWS-1254` and `DB_NAME_ENCODING=WINDOWS-1254`.
- Restart the full R process after changing these values; a browser refresh is not enough.
- Route all user-visible DB text write/read boundaries through the central text/DB normalization helpers.
- Do not mojibake-repair technical identifiers, flags, enums, paths, model IDs, usernames, email, sicil, Keycloak session IDs, or Keycloak subject IDs.
- Keep SSO claim display fields separate from technical identity fields.
- Treat support feedback/error text and image-gallery `MB_Messages.MessageContent` updates as protected DB boundaries.
- Do not treat emoji persistence as solved by Turkish encoding fixes; verify SQL Server column types and ODBC read/write behavior first.
- Do not add automatic migrations for old corrupted rows.
- Required focused checks: `testthat::test_file("tests/testthat/test-text-encoding-utils.R")`, `testthat::test_file("tests/testthat/test-db-normalization-contract.R")`, `testthat::test_file("tests/testthat/test-db-user-visible-encoding-boundaries.R")`, `testthat::test_file("tests/testthat/test-file-manager-display-name-contract.R")`, `testthat::test_file("tests/testthat/test-production-contracts.R")`, `source("tests/scripts/run_vm_encoding_preflight_real.R", encoding = "UTF-8")`.

Chat History / Söyleşi Geçmişi guardrail:
- The history page must be date-range driven, not fixed-count driven.
- On page selection, it should quickly load the currently selected range; the default range is the last 30 days.
- Do not reintroduce a hard first-120/125-chat cap as the final table result.
- Do not start background warming on page selection in a way that causes a second DataTable render or visible flicker.
- When the user changes or extends the date range, explicitly refresh the cache/table for that selected time frame.
- The previous regression pattern was: disabling background warming stopped flicker but left the table capped at about 125 entries; enabling background warming restored full loading but caused a second rerender. Future fixes must avoid both.

Production preflight and log safety guardrail:
- Failed-message fallback logs must redact `log_json` with `redact_sensitive_text()` before writing to disk.
- Redaction tests should read files in a Windows/VM-safe byte/UTF-8-tolerant way; do not assume `readLines(..., encoding = "UTF-8")` always yields valid UTF-8 on the VM.
- VM preflight redaction probes must use generated fake values and must not commit literal fake password/secret strings that match repository secret-scanner patterns.
- Encoding preflight must keep legacy mojibake findings separate from new-write regressions. Legacy recent-row scans may warn by default, but the transactional DB write/read/rollback probe remains the strict gate for new Turkish text writes.

---

## Major Functional Systems

## 1) Welcome Screen and Quick Actions

`welcome_screen.R` defines `MAIN_ACTIONS_DATA`.

Current quick actions:

- `Process Management System`
- `Application Expert`
- `Proje ve Kaynak Analizi`
- `Excel Analizi`
- `Görsel Oluşturma`
- `Kodlama Desteği`
- `Özetleme Desteği`

Each action includes:

- id
- title
- description
- icon
- theme color
- model value

Quick actions no longer auto-send a seed prompt to the LLM.

Current behavior:
- the welcome card click sends only the action identity and model metadata,
- `R/module_quick_actions.R` activates the relevant tool mode,
- model selection is updated when needed,
- the chat view is opened,
- a prebuilt assistant-style intro message is inserted locally,
- the real LLM pipeline starts only after the user submits an actual prompt.

These intro messages are:
- generated from local prepared text variants,
- not produced by the LLM,
- intentionally excluded from persistent history and prompt context,
- personalized with `first_name` when available from session user data.

Treat quick-action logic as behavioral infrastructure.

---

## 2) Character / Persona System

Personas are defined in `R/config_characters.R`. The system uses modern,
corporate-safe, fictional Turkish AI personas representing different working
styles. There is no mythological framing.

Current roster (id — full name — role):

- `emre` — Emre Onat — Ana Asistan (default, balanced assistant)
- `selin` — Selin Sezgin — Yapıcı Uzman (constructive expert)
- `deniz` — Deniz Özgün — Stratejist (strategist)
- `can` — Can Yalın — Eleştirel Eş (critical partner / verifier)
- `ipek` — İpek Duru — Rehber (guide / teacher)

Each persona includes:

- id, label, full_name, display_name, subtitle
- avatar path, image path
- accent colors (accent / accent_hover / accent_active)
- lore (`lore_tr`)
- style description (`style_tr`)
- profile metrics, signature moves
- system prompt (`system_prompt_en`)
- parameters, TTS voice
- video_key, music_key

### Default
`emre` (Emre Onat) is the default persona.

### Helpers (single source of truth)
Use `get_characters_data()`, `get_character_record()`,
`get_character_asset_paths()`, and `normalize_character_id()`. New modules must
not write their own character-name or folder switch.

### Migration
Old mythological ids are accepted only at the `normalize_character_id()`
boundary: `mergen→emre`, `ulgen→selin`, `kayra→deniz`, `erlik→can`,
`umay/umay_ana→ipek`. Old saved user preferences migrate automatically.

### Practical note
Many visual and behavioral systems depend on the selected persona:

- welcome visuals,
- accent colors,
- AI Expert tone,
- persona videos,
- Bilge Yolaç thinking flavor,
- TTS voice defaults.

---

## 3) Chat / LLM Pipeline

Core files:

- `R/server_send_message.R`
- `R/helpers_llm_api.R`
- `R/helpers_llm_worker.R`
- `R/helpers_llm_sse.R`
- `R/server_llm_response_handlers.R`
- `R/helpers_chat_runtime.R`

Key behaviors:

- user message capture,
- background worker execution,
- optional MCP tool usage,
- response streaming,
- message persistence,
- follow-up suggestion generation,
- optional TTS attachment.

### Critical pattern
Never pass live reactive objects into workers.

Always capture plain values first.

Correct pattern:

```r
chat_id <- isolate(rv$current_chat_id)
user_id <- isolate(rv$user_id)

future({
  some_worker(chat_id, user_id)
})
```

Incorrect pattern:

```r
future({
  some_worker(rv$current_chat_id, rv$user_id)
})
```

This repo is highly sensitive to reactive-scope mistakes.

### Worker payload snapshot contract

- Never pass live `reactiveValues`, reactive expressions, or session-bound reactive objects into workers/background promises.
- Convert `reactiveValues` to a plain list snapshot before worker boundaries.
- `as_llm_settings_list()` must detect `shiny::is.reactivevalues(settings)` before the generic `is.list(settings)` branch, because `reactiveValues` can satisfy `is.list()`.
- Use `shiny::isolate(shiny::reactiveValuesToList(settings))` and fall back safely to `list()` on error.
- This contract protects `summarize_file_with_llm()` and other background/worker payloads from "reactive value outside consumer" errors.

---

## 4) File Storage and Indexing

Core files:

- `R/config_file_store.R`
- `R/config_file_store_index_lock.R`
- `R/config_file_store_index_mutation.R`
- `R/config_file_store_registry.R`

This subsystem provides:

- shared file root,
- persistent upload dir,
- MCP base dir support,
- JSON index,
- per-user buckets,
- registration and resolution helpers,
- stale index cleanup,
- filesystem fallback listing,
- periodic garbage collection.

### Important paths
- `MERGEN_FILES_ROOT`
- `MERGEN_UPLOADS_DIR`
- `MERGEN_MCP_BASE_DIR`
- `MERGEN_INDEX_PATH`

File-store roots are now environment-overridable and intentionally testable (`MERGEN_FILES_ROOT`, `MERGEN_UPLOADS_DIR`, `MERGEN_INDEX_PATH`); tests may sandbox these paths with temp directories, and coding agents must preserve this behavior.

### Key helpers
- `mergen_register_uploaded_file()`
- `global_register_file()`
- `resolve_uploaded_file()`
- `mergen_user_upload_dir()`
- `mergen_list_user_files()`
- `mergen_remove_from_index()`
- `mergen_clear_user_bucket()`

### Practical behavior
- Index writes are atomic (write temp file, then move/copy into place).
- Empty/corrupt `index.json` must degrade safely to an empty state instead of crashing file flows.
- Corrupt index files are backed up with a `.corrupt_<timestamp>` suffix before fallback.
- Physical file names may be timestamped/uniquified, while user-facing display names stay separate and preserved.
- Fallback display-name recovery may strip timestamp/randomized storage prefixes when needed.
- File-manager refresh is intentionally rollback-safe: on rebuild failure, previous in-memory file state is preserved; on success, previously attached files are restored.

If the UI shows the wrong filename or files disappear after refresh, investigate:

- index write path and atomic replacement,
- display-name persistence/recovery,
- user bucket resolution,
- filesystem fallback listing,
- encoding at JSON write/read boundaries,
- refresh rollback behavior.

---

## 5) Support Pages

Support area is coordinated by `R/module_destek.R`.

Subpages:

- `Yardım Merkezi` - `R/module_destek_yardim.R`
- `Geri Bildirim & Hata` - `R/module_destek_geri_bildirim.R` and `R/module_destek_hata_bildir.R`
- `Yenilikler` - `R/module_destek_surum.R`
- `Hakkında` - `R/module_destek_hakkinda.R`

### Knowledge base
`ai_rehber.md` is used as the help knowledge base and as AI Expert reference material.

This means changes to `ai_rehber.md` directly affect:

- support chatbot answers,
- AI Expert guidance quality,
- in-app help consistency.

### Version history
`version_history.md` is parsed by `R/config_version_history.R` and rendered by `R/module_destek_surum.R`.

If Yenilikler content is wrong, check `version_history.md` first.

---

## 6) AI Expert

Core files:

- `R/helpers_ai_expert.R`
- `R/module_ai_expert.R`
- `R/server_ai_expert_handlers.R`
- `ai_rehber.md`

AI Expert handles:

- greeting,
- page guidance,
- idle/proactive talk,
- character-aware phrasing,
- TTS-assisted speech,
- subtitle rendering.

### Important prompt sources
AI Expert system prompt is built from:

- selected character data,
- scenario type,
- current page context,
- user context from DB,
- `ai_rehber.md`.

### Important behavior constraints
AI Expert text is meant to be spoken aloud.

Therefore prompt rules emphasize:

- Turkish only,
- plain text,
- no emoji,
- no markdown,
- natural, smooth phrasing,
- no unusual Unicode decoration.

If output looks robotic or noisy, inspect `helpers_ai_expert.R` and `ai_rehber.md`.

---

## 7) TTS / STT / Music

Core files:

- `R/module_tts.R`
- `R/module_tts_visualizer.R`
- `R/server_tts_handlers.R`
- `R/module_stt.R`
- `R/server_music_handlers.R`

Related front-end files include:

- `www/js/tts_visualizer.js`
- `www/js/tts_manager.js`
- `www/js/stt_client.js`
- `www/js/music_manager.js`
- `www/css/tts_visualizer.css`
- `www/css/stt.css`

These systems interact with each other and are regression-prone.

Typical coupling areas:

- TTS audio + floating visualizer,
- STT modal + music pause/resume,
- background music + ducking,
- AI Expert speech + subtitles + TTS,
- navigation changes while audio is active.

Treat audio logic as concurrency-sensitive.

---

## 8) Bilge Yolaç (Claude Code Integration)

Core files:

- `R/config_claude_code.R`
- `R/config_claude_code_plugins.R`
- `R/helpers_claude_code_upload_folder.R`
- `R/helpers_claude_code_model_config.R`
- `R/helpers_claude_code_session_context.R`
- `R/helpers_claude_code_dir_ui.R`
- `R/helpers_claude_code_process.R`
- `R/helpers_claude_code.R`
- `R/helpers_claude_code_streaming.R`
- `R/helpers_claude_code_formatters.R`
- `R/helpers_claude_code_downloads.R`
- `R/helpers_claude_code_workdir_snapshot.R`
- `R/helpers_claude_code_plugins.R`
- `R/helpers_claude_code_document_extractors.R`
- `R/helpers_claude_code_documents.R`
- `R/module_claude_code_ui.R`
- `R/module_claude_code_akis.R`
- `R/module_claude_code_plugins.R`
- `R/module_claude_code.R`
- `www/js/claude_code.js`
- `www/js/claude_code_streaming.js`
- `www/js/claude_code_plugins.js`
- `www/css/claude_code.css`
- `www/css/claude_code_streaming.css`
- `www/css/claude_code_plugins.css`
- Bilge Yolaç welcome JS files under `www/js/bilge_yolac_*.js`

Bilge Yolaç is a web wrapper around Claude Code CLI-like behavior.

Bilge Yolaç / Claude Code must not rely on a hardcoded auth token in `~/.claude/settings.json`. Keep model/base URL/certificate settings there, but inject the effective API key into the child process environment at runtime. Personal user keys take precedence; Bilge Yolaç must also continue to work with an allowed default key. Never write the runtime token to files or logs.

Safe `settings.json` shape:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "<internal-url>",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "<model-1>",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "<model-2>",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "<model-3>",
    "NODE_EXTRA_CA_CERTS": "<certificate-path>"
  },
  "model": "<model-1>"
}
```

It includes:

- folder browsing,
- workdir selection,
- local folder copy-to-working-area (the "Copy local folder to Bilge Yolaç workspace" button copies the selected folder into the runtime working directory; it does **not** simply upload files),
- model tiers,
- tool-use rendering,
- streaming shell/file activity,
- themed welcome/game experience,
- connection tests,
- scenario templates,
- offline PDF/XLS/XLSX/DOCX text extraction and local LLM summarization,
- auto-generated `dosya_aciklamalari.txt` summary file in the working directory,
- downloadable generated file links rendered after each run.

### Document extraction and download flow

When the user's prompt or the working directory contains binary office documents (PDF, XLS, XLSX, DOCX), the pipeline in `R/helpers_claude_code_documents.R` intercepts the request before it reaches the Claude Code process:

1. `prepare_claude_code_document_context()` detects binary documents in the working directory via `list_claude_code_binary_documents()`.
2. For each supported file, text is extracted locally:
   - **PDF** → `pdftools::pdf_text()`, page-by-page, max 25 pages
   - **XLS/XLSX** → `readxl::read_excel()`, up to 5 sheets × 60 rows
   - **DOCX** → unzip + `xml2` parse of `word/document.xml`, max 500 paragraphs
   - **DOC** → **not supported**; user is instructed to convert to `.docx`
3. Extracted texts are written as `.txt` sidecar files in a temporary `document_support/` subdirectory.
4. A manifest file `BILGE_YOLAC_DOKUMAN_REHBERI.md` is written listing all sidecar paths.
5. The original prompt is replaced with an enriched prompt containing the extracted text inline so Claude can answer without invoking any file-reading tools.
6. For document summarization tasks, `summarize_claude_code_documents_with_local_llm()` calls the local LLM directly and writes the summary to `dosya_aciklamalari.txt` in the output directory.

After a run completes (both document-summary and standard streaming paths), `collect_claude_code_generated_downloads()` scans tool uses for written files, copies them into `bilge_yolac_downloads/`, and `format_claude_code_generated_downloads_html()` renders them as clickable download cards (`.cc-generated-file-card` CSS class) appended to the assistant message.

Document-summary runs must not resume or inherit Claude Code CLI session context. `cc_reset_document_summary_session_context()` clears `rv$cli_session_id`, resets `rv$conversation_context`, and sets `rv$current_runtime_model` before the local document-summary path starts. Keep this behavior separate from normal CLI streaming/resume behavior and protected by `tests/testthat/test-claude-code-run-lifecycle-contract.R`.

### bilge_yolac_downloads/ directory

`bilge_yolac_downloads/` at the repository root holds files that Bilge Yolaç has written and that the user should be able to download directly from the browser. Key facts:

- Created at startup if missing (in `global.R`).
- Registered with `shiny::addResourcePath("bilge_yolac_downloads", ...)` so files are accessible at `/bilge_yolac_downloads/<filename>` without exposing the full server path.
- The path is stored in `getOption("mergen.claude_code_download_root")`.
- Committed to the repo as an empty directory with `.gitkeep`.
- Do **not** source or process files inside this directory; it is purely a static serving endpoint.

### Model tiers
Defined in `R/config_claude_code.R`:

- `Hızlı`
- `Dengeli`
- `Güçlü`

### Streaming notes
The streaming UI renders:

- shell commands,
- file operations,
- tool results,
- live assistant text.

This area is especially sensitive to:

- Unicode symbol handling,
- browser mojibake,
- incremental HTML rendering,
- shell block toggling,
- partial JSON parsing.

### Streaming stop/cancel regression boundary

Streaming stop/cancel behavior is a protected user-flow boundary. A stopped or aborted stream must return the send button to normal, clear sending and typing/thinking state, clear or finalize the active request safely, and must not create duplicate assistant messages.

This is covered by deterministic smoke coverage in `tests/testthat/test-e2e-quick-actions-streaming-regression.R`. Do not weaken the abort cleanup tokens or the `chat_reset_state()` assertions to make tests pass. If the implementation changes, update the test to assert the new real cleanup path rather than removing the coverage.

Focused validation:

- testthat::test_file("tests/testthat/test-e2e-quick-actions-streaming-regression.R")

### Bilge Yolaç Plugin Subsystem

Bilge Yolaç has a dedicated, offline-friendly plugin system. Plugins live under `bilge_yolac_plugins/` at the repository root and are **auto-discovered** at runtime. No CLI, no internet, no manual registration.

#### Plugin architecture files
- `R/config_claude_code_plugins.R` - status labels, component types, log prefix
- `R/helpers_claude_code_plugins.R` - `scan_local_plugins()`, `detect_plugin_components()`, `resolve_app_root()`
- `R/module_claude_code_plugins.R` - `claudeCodePluginsUI()` and `claudeCodePluginsServer()`
- `www/js/claude_code_plugins.js` - badge count update handler
- `www/css/claude_code_plugins.css` - plugin panel and card styles

#### Plugin directory layout
Each plugin lives in `bilge_yolac_plugins/<plugin-name>/` and follows this layout:

```text
<plugin-name>/
├── plugin.json          # Required: name, description, version
├── skills/              # Optional: knowledge files for Claude
│   └── main.md
├── commands/            # Optional: slash commands
├── agents/              # Optional: sub-agents
├── hooks/               # Optional: lifecycle scripts
├── mcp/                 # Optional: MCP server configs
└── templates/           # Optional: ready-to-use code helpers
```

#### Recognized component directories
`detect_plugin_components()` detects these subdirectories and shows them as Turkish badges:

| Directory | Component key | Turkish label |
|-----------|---------------|---------------|
| `commands/` | `commands` | Komutlar |
| `agents/` | `agents` | Ajanlar |
| `skills/` | `skills` | Yetenekler |
| `hooks/` | `hooks` | Kancalar |
| `mcp/` | `mcp_servers` | MCP Sunucuları |
| `templates/` | `templates` | Şablonlar |

If a new component type is added, update BOTH:
1. `claude_code_plugin_bilesenler` in `R/config_claude_code_plugins.R`
2. `detect_plugin_components()` in `R/helpers_claude_code_plugins.R`

#### Current plugin roster (15 plugins)
The `bilge_yolac_plugins/` directory ships with these plugins:

**Foundational:**
- `skill-creator` - guide for creating Claude Code skill files
- `plugin-dev` - plugin development guide
- `frontend-design` - frontend/UI design expertise
- `claude-md-management` - CLAUDE.md file management

**Development workflow:**
- `code-review` - systematic code review checklist
- `code-simplifier` - code simplification and refactoring
- `commit-commands` - Git commit management (Conventional Commits)
- `feature-dev` - feature development lifecycle
- `pr-review-toolkit` - pull request review workflow
- `ralph-loop` - polling/automation loops

**Quality and analysis:**
- `test-gen` - test generation across R/JS/Python
- `security-audit` - OWASP-aligned security review
- `doc-gen` - code documentation generation
- `debug-detective` - systematic debugging methodology

**Document generation:**
- `office` - DOCX, XLSX, PPTX, PDF via R helpers (see below)

#### Office plugin template framework
The `office` plugin is the only one that currently ships with a `templates/` directory containing actual R helper files:

- `bilge_yolac_plugins/office/templates/docx_helpers.R` - officer-based DOCX helpers
- `bilge_yolac_plugins/office/templates/xlsx_helpers.R` - openxlsx-based XLSX helpers
- `bilge_yolac_plugins/office/templates/pptx_helpers.R` - officer-based PPTX helpers
- `bilge_yolac_plugins/office/templates/pdf_helpers.R` - grDevices-based PDF helpers (no extra packages)
- `bilge_yolac_plugins/office/templates/document_readers.R` - offline text extraction helpers for PDF (`pdftools`), XLS/XLSX (`readxl`) and DOCX (unzip + `xml2`). `.doc` format is explicitly unsupported; the user is prompted to convert to `.docx`. This file mirrors the extraction logic in `R/helpers_claude_code_documents.R` but is provided as a standalone template that Claude Code can `source()` inside a session when additional extraction is needed.

These helpers are NOT sourced into the Shiny app. They are standalone R files that Claude Code references via `source()` inside Bilge Yolaç sessions. The separation of concerns is:
- `skills/main.md` - domain knowledge (when and why to use each format)
- `templates/*.R` - reusable implementation (actual working code)

If you extend the office framework, keep this separation. Never source template files into `global.R`.

#### Plugin panel UI behavior
The plugin panel is rendered by `claudeCodePluginsUI()` in the Bilge Yolaç left sidebar and is:

- **Collapsible** via the header click handler
- **Collapsed by default** (class `cc-plugins-collapsed` applied on initial render)
- **Auto-refreshed** on page load via an observer with priority 40
- **Manually refreshable** via the refresh button

**Important collapse implementation detail:** The `cc-plugins-collapsed` class MUST be toggled on the outer wrapper `div` (`ns("plugins_wrapper")`), NOT on the inner content `div`. The CSS selectors `.cc-plugins-collapsed .cc-plugins-content` and `.cc-plugins-collapsed .cc-plugins-toggle-icon` are descendant selectors and will only match when the class lives on an ancestor. Do not regress this by moving the class toggle to the content div.

---

## 9) SSO

Core files:

- `R/config_sso.R`
- `R/helpers_sso.R`
- `R/module_sso.R`
- `R/server_init_user_session.R`
- `R/server_runtime_context.R`
- `www/js/sso_auth.js`
- `www/css/sso_auth.css`

SSO is Keycloak-based and controlled by the global `SSO_ENABLED` flag.

### Practical rule
If a bug appears only when `SSO_ENABLED=TRUE`, check:

- token claim extraction,
- encoding of claim text,
- auth-initialization timing,
- delayed session setup,
- live current-user provider propagation through `runtime_ctx$identity`,
- user-specific file loading after auth.

---

## 10) Admin / Analytics

Main admin modules include:

- `R/module_admin_analytics.R`
- `R/module_admin_geri_bildirim.R`
- `R/module_admin_hata_analizi.R`
- `R/module_admin_yanit_analizi.R`
- helper modules in the admin family
- `R/helpers_admin_analytics.R`

Admin area includes:

- general analytics,
- feedback analytics,
- bug analytics,
- response feedback analytics,
- health monitoring.

Health worker metrics here are **application-level async occupancy metrics** and should not be described as logged-in user count or literal OS-level worker telemetry.

This area is role-sensitive and should not accidentally leak into normal-user flow.

---

## Worker Monitoring and Async Task Tracking

The admin health screen now includes application-level worker/task monitoring.

### What these metrics mean
The worker card does **not** show logged-in user count. It shows async workload occupancy derived from the app’s own task registry.

Displayed values are based on:
- configured future cluster size
- tracked active async jobs
- inferred free/busy worker counts
- queued work beyond cluster capacity

### Source files
- `R/helpers_worker_monitor.R`
- `R/module_health_worker_metrics.R`

### Operational rule
If you add a new async flow that should appear in the health screen, do **not** use raw `future_promise(...)` directly.

Use:

```r
tracked_future_promise(
  task_fn = function() {
    # async work
  },
  task_type = "meaningful_task_type",
  session_token = session$token
)
```

Important: `tracked_future_promise()` expects `task_fn`, not a raw expr block.

Incorrect:

```r
future_promise({
  some_async_work(...)
})
```

Also incorrect:

```r
tracked_future_promise({
  some_async_work(...)
})
```

Correct:

```r
tracked_future_promise(
  task_fn = function() {
    some_async_work(...)
  },
  task_type = "llm_non_streaming",
  session_token = session$token
)
```

The second critical purpose of `tracked_future_promise(...)` usage is safe transfer of worker dependencies. In this repo, “tracking” and “worker export safety” are combined in the same wrapper. Therefore, skipping the wrapper while writing async paths does not only leave the health screen incomplete; it can also cause runtime errors such as function-not-found inside workers.

### Current tracked async families
At minimum, health metrics are expected to include these async flows when present:
- non-streaming LLM
- streaming LLM
- true streaming SSE worker
- TTS
- image generation

If a new future-based path is added without the tracked wrapper, the health page will under-report worker usage.

---

## Front-End Structure Notes

## CSS
Large number of page- and feature-specific styles live under `www/css/`.

Important families:

- welcome / intro
- layout / components
- chat messages / inputs
- file manager
- settings
- support
- admin analytics
- SSO
- Bilge Yolaç
- version history

## JS
Important families under `www/js/`:

- core app bootstrapping
- streaming manager
- input and interaction handlers
- chat / markdown / citations
- welcome animation / neural / greeting
- TTS / STT / music
- support page JS
- AI Expert manager
- Bilge Yolaç streaming and game assets

### Practical rule
If a UI feature looks broken but R code seems correct, inspect the paired JS/CSS files before patching server logic.

---

## Current User-Facing Pages and What They Mean

### `chat`
Main conversation page.

Contains:

- welcome screen placeholder,
- chat header,
- model display,
- message count,
- new/copy/export actions,
- chat container,
- file prompt indicator,
- textarea,
- drag-and-drop support,
- model selector,
- send / voice / file actions,
- contextual controls for image, summary, and analysis tools.

### `history`
Conversation history.

### `saved_chats`
Saved conversation management.

### `image_gallery`
Generated image gallery.

### `claude_code`
Bilge Yolaç.

### `files`
File upload, preview, file management.

### `settings_kisisel`
Character and mode personalization.

### `settings_yapilandirma`
Model, tools, UI preferences, voice and technical settings.

### `destek_yardim`
Support contact information and help chatbot.

### `destek_geri_bildirim`
Feedback and bug reporting.

### `destek_surum`
Version / release notes.

### `destek_hakkinda`
Hakkında page / user guide.

### `health`
Health monitor, admin-facing.

---

## Repo-Specific Working Preferences

This section reflects how work in this repo is usually requested.

### Prefer:
- exact patches,
- clear file-level scope,
- preserving existing architecture,
- Turkish comments if comments are added,
- no unnecessary code movement,
- concrete testing steps.

### Avoid:
- broad rewrites,
- “cleanup” refactors without approval,
- renaming stable identifiers casually,
- introducing English comments into Turkish-heavy files,
- changing visible labels unless needed.

### `server.R` editing rule

When changing `server.R`, prefer this order of decisions:

1. Can this stay as wiring only?
2. Can the helper be moved into an existing `server_handler_*`, `server_observers_*`, or `server_init_*` file?
3. Is the dependency part of the early boot contract and therefore appropriate for `ServerRuntimeContext`?
4. Is a new file really justified?

Preferred:
- smaller `server.R`
- explicit helper bundles returned as lists
- session-local setup extracted cleanly
- no hidden dependencies on object creation order
- live identity and cache providers accessed through `runtime_ctx$identity` and `runtime_ctx$cache`

Avoid:
- adding more inline helper closures to `server.R` unless truly necessary
- mixing business logic with startup orchestration
- reintroducing direct `user_session$...` identity aliases in `server.R`
- reintroducing direct `session_cache$...` cache aliases when `runtime_ctx$cache` already owns the contract

---

## Sensitive / Regression-Prone Areas

These areas have produced regressions recently or are structurally fragile. Treat them carefully.

### 1) Encoding and mojibake
Especially sensitive in:

- VM deployments,
- SSO-enabled sessions,
- streamed text,
- DB reads/writes,
- JSON index files,
- Bilge Yolaç incremental rendering,
- support/version-history content.

### 2) Welcome screen layout
Sensitive interactions exist between:

- hidden chat header,
- fullscreen welcome wrapper,
- neural animation,
- greeting overlay,
- intro state,
- modern welcome CSS.

A small CSS change can break the top alignment or shift multiple panels.

### 3) Audio concurrency
Sensitive interactions between:

- TTS,
- STT,
- background music,
- character music,
- AI Expert speech,
- page navigation.

### 4) File indexing and display names
Be careful with:

- timestamped storage names vs display names,
- index rehydration,
- Excel persistence after restart,
- user-bucket scanning.

For large modules (especially `R/module_file_manager.R`), prefer tiny local helper extractions for repeated UI hint text, allowed-extension policy resolution, and repeated HTML row/action builders. Preserve behavior, reduce duplication, avoid broad rewrites.

### 5) Quick-action tool switching
Quick actions are tied to model/tool behavior. Regressions can make a tool appear active while another tool-family actually handles the request.

### 5A) Quick-action intro message behavior

Quick-action intro messages must remain assistant-style (`type = "ai"`) rather than system-style in order to preserve normal left-aligned chat rendering.

If editing the prepared intro message helper:
- keep emoji escapes valid in R strings,
- use single-backslash Unicode escapes such as `\U0001F44B` where escape form is preferred,
- prefer `first_name` over full display name for greeting personalization,
- keep these intro messages out of DB persistence and LLM conversation context unless explicitly changing product behavior.

### 6) Saved-chat restore
Loading a saved chat can accidentally route the user back into a stale welcome state if observers are wired incorrectly.

### 6A) Welcome recency invariants
- Welcome recent list represents most-recent **activity**, not just creation time.
- On transitions like `Yeni Söyleşi`, saved chat state must be refreshed before welcome re-render.
- Recency ordering should prefer `last_message_timestamp` and use creation timestamp only as fallback.

### 6B) Saved-chat state freshness regressions
Watch for divergence between in-memory `values$saved_chats` and DB-backed truth. This is a known source of top-3 recent chat regressions and the welcome screen being “one behind” when refresh ordering is changed incorrectly.

### 7) Streaming handlers
The chat stream and Bilge Yolaç stream both have fragile incremental rendering paths. Small output-format changes can break UI rendering.

### 8) Async worker dependency export

Streaming and non-streaming flows may not behave identically. Do not assume other async flows are safe just because one flow works.

Especially in non-streaming LLM, image-generation, and similar worker-based flows:
- `tracked_future_promise(...)` should be used
- required dependencies should be transferred to the worker
- reactive objects should be reduced to plain values beforehand
- the VM + SSO + Ctrl+Enter scenario should be considered

### 8A) Startup guards must match their execution context

Some startup helpers run inside reactive consumers in SSO flows, but may also run as plain function calls in local (`SSO_ENABLED=FALSE`) startup.

Practical rule:
- do not introduce `reactiveVal()` or `req()` into a startup guard unless that code is guaranteed to run inside a reactive context
- for one-time startup flags, prefer plain session-local state (for example, a local environment flag) unless reactive invalidation is truly needed
- `R/server_observers_startup.R` is especially sensitive here

### 8B) Path helper edge cases
- `R/utils_path_helpers.R` owns scalar path normalization, path existence checks, Turkish mojibake path detection/repair, safe environment path reading, and Windows short-path fallback behavior. It should use the shared repair path from `R/utils_text_encoding.R`; do not add scattered local mojibake maps or ad hoc path repair logic in feature modules. Turkish mojibake path behavior is protected by `tests/testthat/test-path-helpers-mojibake-behavior.R`.
- `safe_join_path()` must accept safe descendant paths on Windows VM and must not regress into false negatives for non-existing but valid child paths.
- Preserve defenses against traversal, absolute paths, and dot-only suspicious segments.
- Do not reintroduce brittle embedded-NUL tests that rely on normal R string construction on Windows.

### 8C) ServerRuntimeContext and identity/cache drift
- `server.R` should obtain user identity aliases from `runtime_ctx$identity`, not directly from `user_session`.
- `server.R` should pass send-message cache functions from `runtime_ctx$cache`, not from loose `session_cache` aliases.
- `ServerRuntimeContext` should remain small and focused on early boot objects.
- Do not add arbitrary downstream modules to `runtime_ctx` unless they have a clear repeated server boot contract and required-function validation.
- If full-suite tests fail after a runtime-context edit but individual tests pass, inspect stale static contract tests first. They may still be checking older `user_session$...` or `session_cache$...` patterns.

---

## If You Add or Change a Module

Follow this checklist:

1. Put the file in the correct layer.
2. Add `safe_source()` entry in the correct `global.R` group.
3. Update `ui.R` if the module has UI.
4. Update `server.R` wiring if the module has server logic.
5. Verify namespace consistency.
6. Verify Turkish strings remain UTF-8 safe.
7. Test both local mode and, if relevant, SSO-sensitive flow assumptions.
8. For welcome quick actions, prefer local UI-side prepared guidance over automatic LLM kickoff unless the product requirement explicitly says otherwise.

---

## If You Touch DB Logic

Remember:

- worker-safe patterns only,
- no pool object serialization into futures,
- capture reactivity before background execution,
- keep Turkish text encoding safe,
- check how user creation and authorization behave under SSO.

---

## If You Touch `ai_rehber.md`

Understand the impact:

- support chatbot quality changes,
- AI Expert prompt context changes,
- page guidance behavior changes,
- help-page consistency changes.

This file is not passive documentation. It is live prompt context.

---

## If You Touch `version_history.md`

Understand the impact:

- Yenilikler page content changes,
- current version display changes,
- support/about references may need alignment.

---

## If You Touch `www/js/claude_code_streaming.js`

Be especially careful with:

- Unicode symbols,
- emoji-like icons,
- mojibake risk on VM,
- incremental text assembly,
- shell visibility toggles,
- HTML escaping,
- copy/paste fidelity.

Prefer Unicode escape sequences over literal emoji if browser/VM rendering is unstable.

---

## Minimal Local Run Instructions

Typical local flow:

1. configure `.Renviron`,
2. open the project in R,
3. run `app.R` directly.

Do not assume a plain `runApp(".")` workflow is the safest path for this repo.

---

## Recommended Validation After a Patch

### Evidence hierarchy for Codex/cloud versus VM validation

For documentation-only edits limited to `README.md` and `CLAUDE.md`, do not run R/testthat validation unless the task explicitly asks for runtime validation; a text diff review is sufficient.

When Codex/cloud validation is available, interpret it strictly by the generated proof fields. A passing `cloud-quick` run is supplementary evidence for cloud-safe parse and focused contract scope only. It must not be described as full validation, app boot proof, browser UX proof, VM/SSO/DB proof, SQL Server Turkish encoding proof, or manual fragile-flow proof. `validation_doctor` is guidance only and must never be cited as execution proof.

If Codex/cloud `quick` or `full --boot-smoke` cannot complete because it enters heavy package bootstrap or compile paths, do not treat that as stronger evidence than a successful Windows VM run. For runtime, SSO, DB, and SQL Server Turkish encoding boundaries, the authoritative evidence is the VM-side run: `quick`, `full --boot-smoke`, `run_vm_preflight_real.R`, and `run_vm_encoding_preflight_real.R` with `MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST=TRUE`. If those VM gates pass, report Codex `cloud-quick` as supplementary only and clearly state what it does not prove.

After changing anything non-trivial, test:

### Core
- app starts,
- sidebar loads,
- welcome screen appears,
- chat page is usable.

### Encoding
- Turkish labels display correctly,
- streamed assistant text displays correctly,
- support/version content displays correctly.

### Files
- upload works,
- file appears with correct visible name,
- refresh/reopen behavior still works.

### Chat
- send message,
- stream response,
- follow-up actions render,
- export/copy still works.
- regression check: finish a chat, click `Yeni Söyleşi`, and verify the just-finished chat appears immediately in welcome recent top-3 without manual refresh.

### Unit tests (helper / decision-logic changes)
For helper or decision-logic patches, run the unit test suite from repository root. Minimum command:

```r
source("tests/testthat.R", encoding = "UTF-8")
```

If needed, rerun only the target file with `testthat::test_file(...)`.

Contract-focused validation snippet:

```r
source("tests/testthat.R", encoding = "UTF-8")

testthat::test_file("tests/testthat/test-safe-source-encoding-contract.R")
testthat::test_file("tests/testthat/test-global-source-manifest-contract.R")
testthat::test_file("tests/testthat/test-production-env-policy-contract.R")
testthat::test_file("tests/testthat/test-llm-reasoning-request-overrides.R")
testthat::test_file("tests/testthat/test-server-user-session-context.R")
testthat::test_file("tests/testthat/test-server-runtime-context.R")
testthat::test_file("tests/testthat/test-server-module-wiring-runtime-bindings.R")
testthat::test_file("tests/testthat/test-server-live-user-provider-contract.R")
testthat::test_file("tests/testthat/test-source-manifest-contract.R")
testthat::test_file("tests/testthat/test-secret-leak-contract.R")
testthat::test_file("tests/testthat/test-runtime-network-boundary-contract.R")
testthat::test_file("tests/testthat/test-production-contracts.R")
```

Recent production-hardening coverage adds focused contract tests for source manifest integrity, secret leakage, runtime network boundaries, and expanded UTF-8 parse coverage of high-risk production files. The runtime network-boundary test is intended to catch accidental public internet/CDN dependencies in executable runtime code, not harmless documentation/license references: it strips R/JS/CSS comments, allows SVG namespace URLs, `example.*` placeholders, known internal/intranet hosts, and skips vendored offline assets such as `www/js/highlight.min.js` and `www/css/all.min.css`. Use `MERGEN_ALLOWED_INTERNAL_URL_REGEX` only for additional organization-specific internal URL allowlisting.

### Behavioral test coverage expansion notes

- Recent behavioral-coverage updates added broad offline, deterministic behavioral coverage for previously untested modules/server files and pure helpers.
- PR #439 covered 42 previously untested R/Shiny modules/server files, added around 34 new test files, reached about 627 assertions after that wave, and included the behavior-preserving `message_search` `gregexpr(..., fixed = TRUE)` warning fix.
- PR #441 covered 20+ additional modules/helpers, including image generation, AI Expert, admin error analysis, file-manager runtime, startup screen, STT, ChartLab, user identity, messaging rendering, DB chat readers, Claude Code formatting, package validation, logging resolvers, health formatters, version history resolver, and welcome builders.
- New behavioral tests must stay offline and deterministic: use local stubs, isolated environments, `MockShinySession` / `testServer`, and no real LLM/TTS/DB/browser/network unless explicitly required by an existing validation gate.
- Warnings in focused behavior tests should be treated as regressions where the test path expects zero warnings. If production emits a spurious warning, fix it surgically with a regression test rather than suppressing it globally.
- Preserve Turkish comments and `test_that` descriptions with proper UTF-8 Turkish characters.

### Focused behavioral regression coverage

The following focused coverage list is protected and should remain behavior-level regression coverage:

- tests/testthat/test-ai-expert-chunking-behavior.R
- tests/testthat/test-api-key-identity-resolution-behavior.R
- tests/testthat/test-claude-code-plugin-components-behavior.R
- tests/testthat/test-claude-code-prompt-path-policy-behavior.R
- tests/testthat/test-claude-code-tool-use-html-behavior.R
- tests/testthat/test-deep-thinking-model-resolution-behavior.R
- tests/testthat/test-detect-tool-type-behavior.R
- tests/testthat/test-file-index-search-behavior.R
- tests/testthat/test-health-formatters-behavior.R
- tests/testthat/test-llm-response-postprocess-behavior.R
- tests/testthat/test-llm-sse-event-parsing-behavior.R
- tests/testthat/test-llm-tool-formatters-behavior.R
- tests/testthat/test-log-redact-internals-behavior.R
- tests/testthat/test-rate-limiter-behavior.R
- tests/testthat/test-split-text-and-code-behavior.R
- tests/testthat/test-summarization-user-prompt-behavior.R
- tests/testthat/test-version-history-parsing-behavior.R

These are behavior-level regression tests. They should not be weakened to make unrelated changes pass. They are intended to preserve current behavior while allowing future refactors. If future code changes touch any of these domains, the corresponding focused test file is the minimum relevant check, in addition to the normal validation profile for code changes.

If a patch touches path-validation helpers, confirm behavior with Windows-style separators and Turkish-character file names, and avoid platform-brittle assertions for embedded NUL character construction.

### Module and runtime-helper behavioral coverage batch (module/UI/pure-helper expansion)

A dedicated behavioral-coverage pass closed the gap where many runtime files were referenced ONLY by structural/manifest scanners (source-manifest, ratchet, production-contracts, secret-leak, runtime-network-boundary, frontend-selector, ui-asset-manifest) and had no input→output test. The pass added 23 new `tests/testthat/test-*-behavior.R` files (~442 assertions, 0 fail / 0 warn / 0 skip, validated individually and as a batch). All tests are deterministic and OFFLINE: no real DB, LLM, browser, SSO server, or network; each file isolates the unit under test with `new.env(parent = globalenv())` and local stubs, and all comments/`test_that` descriptions are Turkish.

Areas now behaviorally covered (previously contract/structural-only):

- Modules: `helpers_file_manager_attach_client` (setAttachState client registration), `helpers_file_manager_table_runtime` (DT render + attachment setter), `module_stt` (modal open/cancel/submit, modal-active broadcast, `accept_chunks` lock, no-API-key guard), `module_chartlab` (`mergen_dark_theme`, `push_spec` → `auto_guess_chart_spec` type/axis inference), `module_image_generation` (translation gate, endpoint/key guards, web URL, UI builders, generated-image HTML + XSS escaping), `module_startup_screen` (UI structure, `apply_experience_mode` mode→settings table, `startup_skip_intro` decision), `module_ai_expert` (subtitle UI, `can_speak` gating, start/stop_speaking, prewarm guards), `module_admin_hata_analizi` (tab UI, highcharter status/priority label+color mapping, empty-data guards, tab routing).
- Pure helpers: `module_user_identity` Turkish case/identity helpers, `server_music_handlers` UTF-8 URL encoders (`Ü→%C3%9C`, never native `%DC`), `helpers_db_chat_readers` `.db_chat_*` id/timestamp logic, `helpers_messaging` `parse_ai_response_robustly`/`process_message_content`, `config_version_history` `resolve_version_history_md_path`, `module_sidebar_user_panel` initials/avatar, `welcome_screen_modern` builders, `helpers_followup_questions` `resolve_followup_enabled`, `helpers_files` `readFileContentToString`, `helpers_health_formatters` `health_escape`/`health_status_pill`/`health_render_value`, `config_packages` `validate_required_packages`, `helpers_claude_code_workdir_snapshot` `normalize_claude_code_text_file_to_utf8`, `helpers_admin_hata_detail_runtime` badge HTML, `config_logging` `resolve_mergen_log_dir`/`resolve_mergen_log_threshold`, `helpers_claude_code` `format_claude_code_output`/`get_thinking_message`.

Two real latent bugs were found through this behavioral coverage (each surgically fixed and protected by a regression test; do NOT reintroduce):

- `R/module_chartlab.R` `make_id()`: `as.integer(as.numeric(Sys.time()) * 1000)` overflows the 32-bit integer range (~1.78e12), so every chart id became `cl_NA_<rand>` and a "NAs introduced by coercion" warning was emitted on every push (which would break the strict `stop_on_warning` suite). Fixed to `sprintf("%.0f", as.numeric(Sys.time()) * 1000)` — behavior-preserving, no overflow, real timestamp restored, kept to one line to respect the file's maintainability budget. Protected by `tests/testthat/test-chartlab-module-behavior.R`.
- `R/helpers_db_chat_readers.R` `.db_chat_as_numeric_timestamp()`: `suppressWarnings(as.POSIXct("garbage"))` throws an ERROR (not a warning), so the function's own `if (is.na(parsed)) return(0)` fallback was unreachable and chat-list ordering could crash on a malformed timestamp string. Wrapped the parse in `tryCatch(..., error = function(e) NA)` so the designed `0` fallback holds. Protected by `tests/testthat/test-db-chat-readers-behavior.R`.

Working rules for future agents in this area:

- These are behavior-level regression tests; do not weaken them to make unrelated changes pass. If a code change touches one of these domains, the matching `test-*-behavior.R` is the minimum relevant check.
- When scanning for untested functions, use FIXED-string membership, not `\bname\b` regex — `\b` fails before a leading `.` and falsely flags dot-prefixed helpers (`.db_chat_*`, `.upload_*`) as untested.
- Useful proven patterns: `shiny::testServer` reads `renderHighchart`/`renderDT` outputs back as a `json` string (parse with `jsonlite::fromJSON(as.character(output$x))$x$hc_opts$series` to assert series/colors); mock `shinyjs::runjs`/`shinyjs::delay` and `shiny::showModal`/`updateCheckboxInput` via `testthat::local_mocked_bindings(.package=...)`; for `once = TRUE` observers a single `setInputs` fires once on the real value (do not prime); attach `shiny` for standalone UI-builder tests; partially source files with a top-level `stop()` guard (functions defined before the stop survive a `tryCatch` source); always probe locale/encoding-sensitive output before asserting (Turkish `toupper` is locale-dependent; `normalize_claude_code_text_file_to_utf8` returns TRUE for valid UTF-8 WITHOUT stripping the BOM).
- The remaining gap (next behavioral-coverage target) is non-pure runtime logic: admin `*_outputs` renderers, `helpers_health_checks` probes (mocked), `config_api` key crypto/file helpers, `helpers_destek_database`, `config_file_store_listing_helpers` `.file_store_*`, and nested module-server closures reached via `testServer`. The guide for that work is `.ai/next-session-test-coverage-prompt.md`.

These were additive tests plus two one-line surgical fixes; runtime UX, encoding contracts, and source order are unchanged. The full strict suite (`tests/testthat.R`) still does not complete in the cloud checkout due to pre-existing, unrelated failures (missing vendored `www` assets + `.Renviron`); this batch was validated via per-file and `test_dir` batch runs plus `parse_sanity_check.R` and `test-maintainability-ratchet.R`.

### AI Expert speech and pronunciation contract

`sanitize_ai_expert_pronunciation()` owns the central correction for the common `Bilge Yola` -> `Bilge Yolaç` model output. Apply this correction before subtitles, TTS playback, and TTS prewarm/cache keys so visible text and spoken text stay aligned.

When navigation moves to muted pages such as `settings_kisisel`, `admin_analytics`, or `health`, active AI Expert speech must be stopped gracefully and any music ducking owner must be released. This prevents AI Expert audio/subtitles from overlapping character intro videos or muted administrative pages.


### AI Expert TTS chunking helper boundary

`R/helpers_ai_expert_chunking.R` owns pure text chunking helpers for AI Expert TTS, including `split_text_for_ai_expert_tts()` and `.ai_expert_split_long_piece()`. Keep this helper free of Shiny session access, reactive reads, filesystem writes, HTTP calls, database calls, and mutable runtime state.

Do not move these chunking helpers back into `R/module_ai_expert.R`; the separation protects the module's maintainability budget while keeping TTS startup responsive.
### Audio
- TTS still plays,
- STT modal still opens,
- music does not overlap incorrectly.

### Bilge Yolaç
- page loads,
- scenario buttons work,
- stream blocks render,
- special icons/text do not mojibake.

### SSO-sensitive logic
If relevant to your change, verify assumptions for `SSO_ENABLED=TRUE` paths, even if you cannot fully run Keycloak locally.

---

## Key Files to Read First

If you are new to the repo, read in this order:

1. `app.R`
2. `global.R`
3. `ui.R`
4. `server.R`
5. `R/server_init_user_session.R`
6. `R/server_runtime_context.R`
7. `R/server_init_forward_refs.R`
8. `R/server_init_session_state.R`
9. `R/server_init_chat_runtime.R`
10. `welcome_screen.R`
11. `R/config_file_store.R`
12. `R/config_api.R`
13. `R/config_sso.R`
14. `R/config_characters.R`
15. `R/helpers_ai_expert.R`
16. `R/module_claude_code.R`
17. `R/module_claude_code_plugins.R`
18. `R/helpers_claude_code_plugins.R`
19. `R/module_destek_yardim.R`
20. `bilge_yolac_plugins/` (skim plugin layout and `office/templates/` as an example)

---

## Current Product Version Reference

Current public version history file shows:

- `v1.0` - official launch
- previous `v0.9` - beta

If any document mentions older release framing only, update it.

---

## Final Guidance for Coding Agents

When in doubt:

- preserve Turkish,
- preserve structure,
- patch surgically,
- wire modules carefully,
- respect `global.R` load order,
- keep `ServerRuntimeContext` small and explicit,
- test encoding-sensitive paths,
- and do not treat `ai_rehber.md` or `version_history.md` as passive docs.

They are live product behavior inputs.

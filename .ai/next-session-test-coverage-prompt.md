# PROMPT — Behavioral test coverage, session 4 (deep runtime + service-bound logic)

TASK: Continue eliminating the **"Module / runtime-logic test coverage"** weakness in this
R/Shiny repo (MERGEN Bilge) by adding MANY focused, deterministic, OFFLINE behavioral tests under
`tests/testthat/`. Quantity matters, but every test must assert REAL input→output behavior — no
"function exists" tests, no snapshot fluff. Comments and `test_that` descriptions MUST be in Turkish
with proper Turkish characters (ç ğ ı İ ö ş ü) — never Latinize them.

Read `CLAUDE.md` first — it is the binding operational guide; follow every contract exactly
(additive-only, surgical bug-fix-with-test, source order, encoding, no heavy/browser/CDN deps).

## BRANCH / PR RULES (read carefully)
- Do **NOT** push to `claude/keen-newton-Gi2j1`, `claude/modest-franklin-9rRWC`, or any prior session
  branch, and do **NOT** touch PR #441.
- Develop on **your own session's freshly-assigned branch** (the harness assigns one — use it as-is).
  If for some reason no branch is assigned, create a brand-new one (e.g. `claude/test-coverage-s3-*`).
- When you finish, **open a NEW pull request** for your fresh branch. Commit messages in Turkish.

## CONTEXT — what sessions 1, 2 & 3 already did (do NOT redo)
- ~140+ `tests/testthat/test-*-behavior.R` / `-contract.R` files already exist.
- Session 2 added 23 behavioral files (~442 assertions) covering previously file-untested modules and
  the easy **pure top-level** helpers (file_manager_attach_client/table_runtime, stt, chartlab,
  image_generation, startup_screen, ai_expert, admin_hata_analizi; plus user_identity, music URL
  encode, .db_chat_*, messaging, version-history resolver, sidebar initials, welcome builders,
  followup flag, readFileContentToString, health_formatters, validate_required_packages,
  workdir_snapshot normalize, config_logging resolvers, claude_code format/thinking).
- Session 2 surgical bugs (do NOT reintroduce): `module_chartlab make_id` 32-bit `as.integer`
  overflow → `sprintf("%.0f", ...)`; `.db_chat_as_numeric_timestamp` `as.POSIXct("garbage")` error →
  `tryCatch(..., error = NA)`.
- **Session 3 (branch `claude/confident-wright-9crdA`) added 10 behavioral files (~165 assertions)** and
  several fixes. Already COVERED (do NOT redo): file_manager_session_registry (`.fm_registry_chr`,
  `fm_session_registry_entry`, `fm_normalize_session_registry_path`, register/unregister),
  config_file_store_listing_helpers (`.file_store_deduplicate_rows`/`_lifecycle_key`/`_index_record_row`/
  `_list_user_files_relaxed`/`_file_size_safe`/`_merge_same_user_filesystem`/`_user_dir_paths`),
  `.normalize_user_session_id`, `.mb_feature_api_key_scalar`, `.fm_context_chr`,
  `llm_worker_format_single_tool_result` (all 6 branches), helpers_admin_hata_analizi UI builders
  (`admin_ha_overview_ui`/`_oncelik_ui`/`_detay_ui`/`_zaman_ui`), config_ui_assets tag builders
  (`ui_asset_css_tag`/`script_tag`/`flatten_groups`/`css_tags`/`js_tags`/`validate_js_render_plan`),
  `load_image_descriptions_for_user` (DBI-mocked), `.sanitize_log_value`, and the image/summarization
  stale-request race guard (with `test-async-handler-stale-request-race-behavior.R`).
- Session 3 found/fixed REAL bugs (do NOT reintroduce): (a) two server-side staleness races in
  `server_handler_image_generation.R` and `server_handler_summarization.R` (async callbacks now use
  `mergen_is_current_request`); (b) `module_startup_screen.R` skip-intro path was missing the
  `updateNeuralColor` send that the experience-mode path has → added (persona neural tint on skip);
  (c) `helpers_claude_code_documents.R` extractor fallback guard made working-directory-independent;
  (d) 3 behavior tests sourced the wrong helper after the api-model tool-runtime split — they now
  source `helpers_api_model_tool_runtime.R` so they pass standalone.
- **Session 4/5 (branch `claude/clever-carson-fV8c3`) added 9 behavioral files (~190 assertions)** plus
  fixes. Already COVERED (do NOT redo): UI builders `historyUI`/`savedChatsUI`/`imageGalleryUI`/`sttUI`/
  `chartLabUI`/`destekHataBildirUI`/`settingsKisiselUI`/`healthUI` + `history_accessible_date_range_input`
  (aria-labelledby) + `health_source_optional` (`test-module-ui-builders-behavior.R`); api-key-choice
  modal builders `api_key_choice_request_url`/`.api_key_choice_personal_card`/`_corporate_card`/
  `api_key_choice_modal_dialog` + `llm_worker_extract_preview_df` (Turkish-name tolerance)
  (`test-api-key-choice-modal-builders-behavior.R`); `admin_users_outputs` (highcharter series + empty-data
  + DT) (`test-admin-users-outputs-behavior.R`); `push_followup_update` + `update_messages_after_bulk_deletion`
  guard (`test-chat-runtime-followup-push-behavior.R`); `update_sso_fields` (DBI-mocked SSO write boundary)
  (`test-update-sso-fields-behavior.R`); `normalize_claude_code_text_files`
  (`test-normalize-claude-code-text-files-behavior.R`); the non-streaming LLM stale-request race
  (`test-nonstreaming-handler-stale-request-race-behavior.R`); the AI Expert page-guidance stale-speech
  guard (`test-ai-expert-page-guidance-stale-behavior.R` — note the `aiExpertHandlersInit` testServer
  WRAPPER pattern: `library(promises)`+`library(shiny)`, source `utils_common.R`+`helpers_ai_expert.R`,
  stub `tracked_future_promise` by `task_type`, mock `shinyjs::delay/runjs`, PRIME-THEN-SET `input$tabs`);
  image-upload policy (`test-image-upload-allowed-behavior.R`).
- Session 4/5 found/fixed REAL bugs (do NOT reintroduce): (a) non-streaming LLM handler stale-request
  race in `server_llm_response_handlers.R` (onRejected/finally now request-scoped); (b) AI Expert
  page-guidance spoke stale guidance after navigating to a muted page → page-staleness check added;
  (c) `server_runtime_context.R` fallback guard made working-directory-independent (fixed 5 server tests
  in isolation); (d) 8 test files made standalone-runnable (missing `library(shiny)` / moved-helper
  sources); (e) Dosya Yönetimi "saved-but-hidden" upload leak — `execute_bulk_upload` now validates the
  extension before `copy_to_mcp_base`; images are now an allowed type (`fm_image_extensions()`).
- Session 4/5 also added the **renv dependency-lock scaffolding** (`.Rprofile` with a populated-library
  guard, `renv/activate.R`, `tools/renv_snapshot.R`, `docs/dependency-locking.md`, ci-restore fallback,
  `RENV_LOCK_STATUS.md` marker) and merged current `main` (ratchet fully GREEN). Covered by
  `test-renv-lock-contract.R`. The user GENERATED `renv.lock` on the Windows VM (R 4.6.0, ~116 pkgs); it
  is a USER/VM action — never generate it from Linux/cloud. Also added **image inline preview**
  (`module_file_preview.R` via `registerDataObj`); covered behaviorally by `test-image-upload-allowed-behavior.R`.
- **WINDOWS-VM TEST LESSON (critical — cloud masks it):** the renv/image/api-key tests passed on Linux but
  FAILED on the user's Windows VM full suite (passed individually). Causes + fixes now applied: tests that
  scan repo files MUST use the byte-safe reader (`readBin`+`iconv(sub="byte")`+`grepl(useBytes=TRUE)` over
  ASCII anchors), NOT `readLines(encoding="UTF-8")+grepl` over Turkish-commented files; do NOT assert
  `!is.na(iconv(x,"UTF-8","UTF-8"))` on possibly-native-encoded strings; and `.Rprofile`/`tools/renv_snapshot.R`
  are ASCII-only. After a refactor moves a function, update the test's `source(...)` to the new owner
  (main's `_preview.R` split moved `llm_worker_extract_preview_df`). Apply these to EVERY new file-scanning test.
  One KNOWN cloud-only failure remains: `test-runtime-network-boundary-contract.R` (redacted `https://url......./`
  avatar placeholder in `helpers_messaging.R`/`module_sidebar_user_panel.R`, pre-existing on `main`, green on VM).

## STEP 1 — TARGET the remaining UNTESTED logic (the harder, higher-value stuff)
The cheap pure functions are mostly done. What remains is where bugs hide: **nested closures inside
`moduleServer`/`*Init` bodies, Shiny `*_outputs` renderers, and service-bound (HTTP/DB/LLM) helpers.**

Re-scan for genuinely-untested TOP-LEVEL functions (FIXED-string match — `\b` regex breaks on
dot-prefixed names like `.db_chat_*`, so do NOT use it):

```r
rfiles <- list.files("R", pattern="\\.R$", full.names=TRUE)
tfiles <- setdiff(list.files("tests/testthat", pattern="\\.R$", full.names=TRUE),
                  list.files("tests/testthat","helper_bootstrap", full.names=TRUE))
blob <- paste(unlist(lapply(tfiles, readLines, warn=FALSE, encoding="UTF-8")), collapse="\n")
pat <- "^([A-Za-z.][A-Za-z0-9._]*)[[:space:]]*(<-|=)[[:space:]]*function\\("   # column-0 = top-level
for (f in rfiles) {
  fns <- unique(na.omit(vapply(regmatches(readLines(f,warn=FALSE,encoding="UTF-8"),
           regexec(pat, readLines(f,warn=FALSE,encoding="UTF-8"))), function(x) x[2], character(1))))
  un <- fns[nzchar(fns) & !vapply(fns, function(fn) grepl(fn, blob, fixed=TRUE), logical(1))]
  if (length(un)) cat(sprintf("%-44s %s\n", basename(f), paste(un, collapse=", ")))
}
```

Highest-value remaining clusters (verify each is still 0-ref before writing — some may get covered):
- **Admin `*_outputs` renderers** (testServer + stubbed `*_collect_data`/query fns, then read
  `output$...` and assert highcharter series / DT rows). `admin_users_outputs` is now COVERED
  (`test-admin-users-outputs-behavior.R`); REMAINING: `module_admin_genel_bakis admin_overview_outputs`,
  `module_admin_yz_performans admin_ai_perf_outputs`, `module_admin_geri_bildirim_genel admin_feedback_outputs`,
  `module_admin_sohbet_kalitesi`, `module_admin_zaman_analizi`, `module_admin_gelismis_analizler`,
  `module_admin_yanit_analizi`. Pattern proven in `test-admin-users-outputs-behavior.R` and
  `test-admin-hata-analizi-module-behavior.R` (stub helpers in env, read `output$x` JSON, parse with
  `jsonlite::fromJSON` → `$x$hc_opts$series`).
- **helpers_admin_hata_detail_runtime**: `admin_ha_detail_datatable`, `admin_ha_attachment_public_path`,
  `admin_ha_attachment_download_button`, `admin_ha_show_modal` (DT/HTML builders — partly pure).
- **helpers_health_checks** (mock the probe seams): `health_check_disk_free`, `health_check_app_boot`,
  `health_check_db_connection` / `health_check_db_schema` / `health_check_llm_endpoint` /
  `health_check_reasoning_readiness` — these return the structured `health_result(...)` contract; mock
  `get_connection`/`httr` and assert status/severity/remediation fields. Must NOT hit real DB/network.
- ~~**config_api crypto/key-file helpers**~~ — ALREADY COVERED by `test-config-api-key-crypto-behavior.R`;
  do NOT duplicate. `validate_api_key`/`derive_models_url` (nested in `validate_api_key`) still need an
  `httr`-mocked test if you want endpoint-validation coverage.
- **helpers_destek_database** (mock DB): `destek_geri_bildirim_listele`, `destek_hata_bildirim_listele`,
  `destek_hata_durum_guncelle`, ... — `local_mocked_bindings` `get_connection`/`dbGetQuery`/`dbExecute`.
- **helpers_llm_tool_formatters**: `build_excel_digest_json`, `mcp_excel_tool_fallback` (pure-ish).
- **helpers_image_gallery**: `get_image_thumbnail_base64`, `get_chat_title_for_image` (mock DB / temp
  file). NOTE: `load_image_descriptions_for_user` is now COVERED (session 3, DBI-mocked).
- ~~**config_file_store_listing_helpers** `.file_store_*`~~ — COVERED in session 3
  (`test-file-store-listing-helpers-behavior.R`). Do NOT redo.
- **config_sql_loader** `.remove_utf8_bom`, `.sql_has_text`, `.sql_placeholder_text`, `.read_sql_file_text`:
  the file `stop()`s at source time without `query_library` — source `R/library_queries.R` FIRST, or
  `tryCatch(source(...), error=...)` (functions defined before the stop remain in env), then test.
- **module servers via `shiny::testServer`** where logic is reachable: `module_api_key apiKeyServer`,
  `module_claude_code_plugins claudeCodePluginsServer` (+ `refresh_local_plugins`), `module_image_gallery
  imageGalleryServer` (coerce_user_id/empty_images_df/gallery_images_same), `module_performance`
  count/cleanup helpers.
- ~~**UI builders**: `historyUI`/`history_accessible_date_range_input`, `savedChatsUI`, `imageGalleryUI`,
  `healthUI`, `sttUI`, `chartLabUI`, `destekHataBildirUI`, `settingsKisiselUI`, `module_api_key_choice_modal`
  card builders + `api_key_choice_request_url`~~ — ALL COVERED in session 4/5
  (`test-module-ui-builders-behavior.R`, `test-api-key-choice-modal-builders-behavior.R`). Do NOT redo.
  REMAINING UI builders: `module_chartlab` other builders, `adminYanitAnaliziUI`, and the
  `ui_asset_css_tag`/`ui_asset_script_tag`/`ui_asset_flatten_groups` manifest tag helpers (if still 0-ref).

When a function is a NESTED closure (not column-0), test it **through its module** via `testServer`
(returned closures = `session$returned$...`; renderers = read `output$...`). Stub the heavy deps in the
sourced env; never launch the real app/DB/LLM.

## STEP 2 — TECHNIQUES (proven in sessions 1–2; reuse + the new gotchas)
ENV: `export LANG=C.UTF-8 LC_ALL=C.UTF-8`. `highcharter`+`logger` may be missing — install once from RSPM:
`Rscript -e 'options(repos=c(CRAN="https://packagemanager.posit.co/cran/__linux__/noble/latest")); install.packages(c("highcharter","logger"))'`. `officer`/`plotly` may stay absent → guard `skip_if_not_installed`.

ISOLATION: per file `env <- new.env(parent=globalenv()); source(file.path(resolve_repo_root_for_tests(),
"R","X.R"), encoding="UTF-8", local=env)`. `helper_bootstrap.R` auto-loads (`%||%`, `log_*`,
`normalize_character_id`, DB/file-manager helpers, persona data). Put LOCAL stubs in `env`.

PURE fn → call directly. UI builder → `paste(as.character(ui), collapse="\n")`, assert ids/classes/Turkish.
For unqualified `div()/fluidRow()/selectInput()` etc., `suppressMessages(library(shiny))` at file top
(testServer auto-loads shiny; standalone UI calls do NOT).

`shiny::testServer(env$xxxServer, args=list(...), { ... })`: returned value = `session$returned`;
read render outputs as `output$x`. renderUI/renderText come back as CHAR VECTOR → `paste(as.character(.),
collapse="")`. **renderHighchart / renderDT come back as a `json` string** → `jsonlite::fromJSON(
as.character(output$x), simplifyVector=FALSE)$x$hc_opts$series` to assert series names/colors; or grep the
JSON for ASCII tokens (hex colors are safe; Turkish names may be `\u`-escaped — parse instead of grep).
`req()` failure RE-THROWS on read → `expect_error(force(output$x))`.

CUSTOM-MESSAGE CAPTURE: non-module root session → assign `session$sendCustomMessage <- function(type,msg){...}`
before triggering. moduleServer (session is a proxy) → override the ROOT:
`root <- .subset2(session,"parent"); root$sendCustomMessage <- function(type,msg){...}`. `shinyjs::runjs/
addClass` flow through this too — OR mock them via `testthat::local_mocked_bindings(runjs=..., delay=function(ms,
expr) expr, .package="shinyjs")` (the `delay` mock that forces `expr` runs delayed sends immediately).

MOCK `pkg::fn`: `testthat::local_mocked_bindings(POST=fn, status_code=fn, content=fn, add_headers=fn,
timeout=fn, .package="httr")` — intercepts `httr::POST`. Same for `shiny` (`showModal`/`updateCheckboxInput`
reject a plain-list session → mock to no-op) and DB bindings if exported.

OBSERVER DRIVING: MockShinySession defers `observeEvent` and reads the CURRENT input at next flush.
- For a **`once=TRUE`** observer, a SINGLE `session$setInputs(x=REAL)` fires it once reading REAL (do NOT prime
  with a different value — the prime consumes the single fire on the WRONG value).
- For a non-once observer that must re-fire, use PRIME-THEN-SET: `setInputs(x="__p__"); setInputs(x=REAL)`.
- Negative guards ("must NOT call"): use a stubbed-recorder count `==0`; never assert exact fire counts.

NEW SESSION-2 GOTCHAS (save hours):
- Coverage scan: use FIXED-string membership, not `\bname\b` — `\b` fails before a leading `.` and gives
  false "untested" positives for `.dot_prefixed` functions.
- Files with a top-level `stop()` guard (e.g. `config_packages`, `config_sql_loader`): functions defined
  BEFORE the stop survive a `tryCatch(source(...), error=function(e) NULL)` — test them from the partial env.
- `config_logging` prints a one-time `INFO ... Application starting up` via logger at source time — wrap the
  source in `suppressMessages(...)` (it may still reach stderr via `cat`; that's fine, it's not a warning).
- ALWAYS probe the real output before asserting locale/encoding-sensitive behavior: Turkish `toupper`/
  `chartr` is locale-dependent (assert unambiguous ç/ş/ğ/ü/ö + the reliable `İ→i`, avoid `i↔I↔ı`); and e.g.
  `normalize_claude_code_text_file_to_utf8` returns TRUE for already-valid UTF-8 WITHOUT stripping the BOM —
  assert the real contract, not the assumed one.
- `withr::defer(env$fn <- .orig)` to restore env stubs you mutate inside a `test_that`.
- `cat()`-noisy fns → wrap calls in `invisible(utils::capture.output(res <- expr)); res`.

NEW SESSION-3 GOTCHAS:
- **Wrong-source-after-split trap**: a helper may have MOVED files in a refactor. Several tool-mode
  helpers (`get_tool_mode_config`, `resolve_tool_model_for_family`, `build_main_actions_data_from_config`,
  `resolve_deep_thinking_model`) now live in `helpers_api_model_tool_runtime.R`, NOT
  `helpers_api_model_config.R`. If your test sources the old file it passes in the FULL suite (the runtime
  file is loaded by `global.R`) but ERRORS standalone. Before writing a source-guard, `grep -rn 'fn <-
  function' R/` to find the REAL owner. Make tests self-contained for individual runs.
- **Promise/async handlers**: to drive `%...>%`/`promises::then` callbacks, stub the worker
  (`tracked_future_promise`/`call_llm_non_streaming`) to return `promises::promise_resolve(x)` /
  `promise_reject(e)`, then drain with a bounded `while(!later::loop_empty()) later::run_now(timeout=0)`
  loop. Mock `shinyjs::runjs` via `local_mocked_bindings(.package="shinyjs")`. See
  `test-async-handler-stale-request-race-behavior.R`.
- **CRLF files**: many `R/*.R` and `www/css/*.css` files are CRLF. Editing them with an LF-only tool can
  corrupt line endings. Prefer a small R `readLines()/writeLines(..., sep="\r\n", useBytes=TRUE)` script
  for CRLF files; verify with `grep -c $'\r' file` == `wc -l`.
- **FontAwesome 6 icon aliases**: `icon("sync-alt")` renders as `fa-rotate`, `icon("trash-alt")` as
  `far fa-trash-can`. Don't assert the alias name; assert the rendered class or be tolerant.

WARNINGS = FAILURES under the strict runner (`stop_on_warning=TRUE`): every test must be 0 WARN. Watch
`gregexpr(fixed=TRUE, ignore.case=TRUE)`, unguarded `as.integer(...)` (overflow), `as.POSIXct("garbage")`
(errors). If PRODUCTION emits a spurious warning/error on a reachable input, that's a surgical bug-fix
candidate (with a regression test) — see the `make_id` / `.db_chat_as_numeric_timestamp` precedents.

## STEP 3 — IF YOU FIND A REAL BUG
Fix it surgically in the R file with a Turkish comment explaining why; keep the test that proves it. Do not
change runtime behavior otherwise. Respect the maintainability ratchet (`tests/testthat/
test-maintainability-ratchet.R`) — keep near-limit files within budget (collapse a fix to one line if needed,
like `make_id`). Do not weaken/edit existing contract tests.

## STEP 4 — VALIDATE (be honest)
- After EACH new file: `Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-X.R",
  reporter="summary")'` → require 0 FAIL / 0 WARN / 0 accidental SKIP. Run files individually AND as a batch
  (`testthat::test_dir("tests/testthat", filter="...")`) to catch global leakage; always `new.env(parent=
  globalenv())`.
- After any R source edit: `Rscript tests/scripts/parse_sanity_check.R` and
  `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")`.
- IMPORTANT — the FULL strict suite (`tests/testthat.R`) does NOT complete in this cloud checkout due to
  PRE-EXISTING failures unrelated to new tests: missing vendored assets (`www/css/all.min.css`,
  `www/codemirror/*`, `www/lib/threejs/*`) and missing `.Renviron`. Sessions 1–2 proved these fail
  identically on the base commit. Do NOT try to "fix" them; classify as environment/checkout limits.
  Validate your work via per-file + batch runs, not the full suite.

## CONSTRAINTS
Additive only. Preserve Turkish user-facing strings; Turkish + UTF-8 comments/descriptions. No new heavy/
browser/CDN deps (no Playwright/Selenium/shinytest2/chromote). Keep stubs local; isolate with
`new.env(parent=globalenv())`. Never print/log real secrets — use fake key/token fixtures.

## DELIVERABLE
- As many new green `tests/testthat/test-*-behavior.R` files as you can for the remaining runtime/renderer/
  service-bound logic (each 0 fail / 0 warn). Prioritize the admin `*_outputs` renderers, `helpers_health_
  checks` probes (mocked), `config_api` key crypto (round-trip + reject), and `config_file_store_listing_
  helpers` `.file_store_*` transforms.
- Any real bug found → surgical fix + regression test, documented in the PR body.
- Short honest final report: files covered, test-file + assertion counts, bugs found & fixed, and an
  explicit per-file list of anything you could NOT cover offline and why.
- Commit with clear Turkish messages, push to YOUR fresh branch, and OPEN A NEW PR (do not reuse PR #441 or
  any prior session branch).

Begin with STEP 1 (re-scan), show the remaining-function list, then generate tests file by file, validating
each.

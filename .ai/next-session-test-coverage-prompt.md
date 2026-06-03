# PROMPT — Continue behavioral test coverage (MERGEN Bilge), session 2

TASK: Continue eliminating the "Module/UI-logic test coverage" weakness in this R/Shiny repo
(MERGEN Bilge) by adding MANY focused, deterministic, OFFLINE behavioral tests under
`tests/testthat/`. Quantity matters, but every test must assert REAL input→output behavior —
no trivial "function exists" tests, no snapshot fluff. Comments and `test_that` descriptions
MUST be in Turkish with proper Turkish characters (ç ğ ı İ ö ş ü) — never Latinize them.

Read `CLAUDE.md` first — it is the binding operational guide; follow every contract exactly
(additive-only, surgical bug-fix-with-test, source order, encoding, no heavy/browser/CDN deps).

## CONTEXT — what session 1 already did (do NOT redo)
- All 42 previously-untested `R/module_*.R` / `R/server_*.R` files now have behavioral tests.
- Plus 3 behavioral-gap files: `server_init_forward_refs`, `bootstrap_source_manifest`,
  `module_tts_visualizer`.
- 34 new `tests/testthat/test-*-behavior.R` / `-contract.R` files, ~527 assertions, all green
  (0 fail / 0 warn / 0 skip).
- One surgical bug fix: removed a spurious `ignore.case=TRUE` arg from `gregexpr(... fixed=TRUE)`
  in `R/module_message_search.R` (behavior-preserving; killed a per-search warning). Protected by
  `test-message-search-behavior.R`. Do NOT reintroduce it.

## STEP 1 — TARGET the remaining behaviorally-untested files
These are referenced ONLY by structural/manifest scanner tests (source-manifest, ratchet,
production-contracts, etc.) and have NO behavioral test. Re-scan to confirm with:

    structural="source-manifest-contract|global-source-manifest|maintainability-ratchet|production-contracts|secret-leak-contract|runtime-network-boundary|offline-baseline|helper_source_manifest|frontend-selector-contract|ui-asset-manifest|test-production-env-policy"
    for f in R/*.R; do b=$(basename "$f" .R); \
      refs=$(grep -rlF "$b" tests/testthat/ 2>/dev/null | grep -vE "$structural" | grep -v helper_bootstrap.R); \
      [ -z "$refs" ] && echo "$f ($(wc -l <"$f") lines)"; done

Current remaining (8 files), with hints — prioritize pure helpers / UI builders / returned closures:
- `R/helpers_file_manager_attach_client.R` (30)   — `fm_register_attach_state_client_handler()`; registers a
  `setAttachState` custom-message handler. Test via testServer + ROOT message capture; assert handler wired.
- `R/helpers_file_manager_table_runtime.R` (137)  — DT `renderDT`/`drawCallback`/`change.attach` runtime;
  needs `DT` (installed). Test the empty/row table HTML build + that renderDT registers; stub upstream.
- `R/module_admin_hata_analizi.R` (525)           — priority/status badge HTML builders are PURE & testable;
  charts need `highcharter`. Heatmap data prep lives in `helpers_admin_hata_heatmap_data.R` (check if tested).
- `R/module_ai_expert.R` (616)                    — LLM/TTS heavy; look for pure prompt/scenario builders and
  returned closures; chunking already covered in `helpers_ai_expert_chunking`. Stub the LLM (`httr`/local).
- `R/module_chartlab.R` (531)                      — `helpers_chartlab*` already tested; the module has parse →
  Shiny-output placeholder logic. Test pure parsing/placeholder shape; stub renderers.
- `R/module_image_generation.R` (764)             — server has size/quality resolution + prompt handling +
  `tracked_future_promise`. Test the no-API-key / guard / size-quality decision paths; stub the future.
- `R/module_startup_screen.R` (732)               — UI builder(s) + startup decision logic; render & assert
  structure/Turkish; test any pure stage/skip-intro decisions.
- `R/module_stt.R` (310)                           — STT modal open/cancel/submit observers duck/restore music
  via custom messages; capture via ROOT override + prime-then-set.

After these, OPTIONALLY deepen coverage of large already-touched files (e.g. admin `*_outputs`
renderers now that `highcharter` is installed, more `server_observers_*`, `module_summarization`,
`module_file_preview` behavior beyond what exists).

## STEP 2 — TECHNIQUES CHEAT-SHEET (hard-won in session 1 — saves hours)
ENV (fresh container each session):
- `export LANG=C.UTF-8 LC_ALL=C.UTF-8`.
- Install the two missing-but-repo-declared packages ONCE so highcharter/logger-gated code + the
  full suite can run/verify (RSPM mirror works here):
  `Rscript -e 'options(repos=c(CRAN="https://packagemanager.posit.co/cran/__linux__/noble/latest")); install.packages(c("highcharter","logger"))'`
  (`officer`/`plotly` may still be absent — guard with `skip_if_not_installed`.)
- Validate each file: `Rscript -e 'library(testthat); testthat::test_file("tests/testthat/test-X.R")'`.

ISOLATION & STUBS:
- `helper_bootstrap.R` auto-loads under `test_file` → `resolve_repo_root_for_tests()`, `%||%`, `log_*`,
  persona helpers (`normalize_character_id`/`get_character_record`), DB & file-manager helpers are in globalenv.
- Per file: `env <- new.env(parent=globalenv()); source(file.path(resolve_repo_root_for_tests(),"R","X.R"), encoding="UTF-8", local=env)`.
  Put LOCAL stubs in `env` (`showToast`, `JS`, DB getters, `get_current_version`, LLM fns, etc.). Don't source broad runtime modules.

PURE / UI:
- Pure fn → call directly. UI builder → `paste(as.character(ui), collapse="\n")`, assert ids/classes/Turkish/aria
  (`data:image/gif;base64` placeholder instead of empty `src`). Guard `skip_if_not_installed("shiny"/"highcharter"/"shinyWidgets")`.

SHINY SERVERS:
- moduleServer: `shiny::testServer(env$xxxServer, args=list(...), { ... })`; returned value is `session$returned`.
- Non-module `xxxInit(input, session, ...)` returning a list: call inside a wrapper
  `testServer(function(input,output,session){ rec$h <- env$xxxInit(input,session,...) }, { ... })`, OR for
  pure-closure inits (e.g. forward refs) call directly with a fake `session <- list(token="t")`.
- Reading `renderUI/renderText` outputs returns a CHAR VECTOR → `paste(as.character(output$x), collapse="")`.
  A `req()` failure RE-THROWS on read → assert with `testthat::expect_error(force(output$x))`.
- `downloadHandler` content is NOT reachable (locked `downloads` binding) → test the equivalent copy/runjs path.

CUSTOM-MESSAGE CAPTURE (no built-in capture in MockShinySession):
- Non-module (session is root MockShinySession): inside body, `session$sendCustomMessage <- function(type,message){ rec$msgs[[...]] <- ... }` BEFORE triggering.
- moduleServer (session is a `session_proxy`, direct assign is blocked): override on the ROOT —
  `root <- .subset2(session,"parent"); root$sendCustomMessage <- function(type,message){ ... }`.
  `shinyjs::runjs/addClass/...` also flow through this as custom messages.

OBSERVER DRIVING (critical gotcha): MockShinySession DEFERS `observeEvent` and reads the CURRENT input
value at the next flush. Use PRIME-THEN-SET: `session$setInputs(x="__prime__"); session$setInputs(x=REAL)`
→ observer fires exactly once reading REAL. For NEGATIVE guards ("must NOT call"), make BOTH prime and real
the SAME guard-kind and assert via stubbed-recorder count `==0` or `%in%` membership — never assert exact fire
counts across distinct values (coalescing is inconsistent). Read observer-mutated injected `reactiveValues`
via `shiny::isolate(rec$values$field)` (bridge `values` into a recorder env) or a probe `output`.

MOCK `pkg::fn`: `testthat::local_mocked_bindings(POST=fn, status_code=fn, content=fn, add_headers=fn, timeout=fn, .package="httr")`
inside the `test_that` — confirmed to intercept `httr::POST`. Use for any LLM/HTTP-bound observer.

NOISE & TIMERS:
- Wrap calls that `cat()`/`print()` in `invisible(utils::capture.output(...))` (cat is stdout, not a warning,
  but keep output clean). `later::later` flows: drive with `shiny::MockShinySession$new()` + `for(i in 1:20) later::run_now(0.05)`, use `delay_sec=0`.
- Relative-path file helpers (`file.path("www",...)`): control with `withr::with_dir(tmp_or_repo_root, ...)`
  and create files under the correct relative subdir.

WARNINGS = FAILURES (strict runner `stop_on_warning=TRUE`): every test must be 0 WARN. Watch for
`gregexpr(fixed=TRUE, ignore.case=TRUE)`, unguarded `as.integer("abc")`, etc. If PRODUCTION emits a spurious
warning, that's a surgical bug-fix candidate (with a regression test) — see the `message_search` precedent.

## STEP 3 — IF YOU FIND A REAL BUG
Fix it surgically in the R file with a Turkish comment explaining why; keep the test that proves it.
Do not change runtime behavior otherwise. Do not weaken/edit existing contract tests.

## STEP 4 — VALIDATE (be honest)
- After EACH new file: `testthat::test_file(...)` → require 0 FAIL / 0 WARN / 0 accidental SKIP. Run files
  individually AND as a batch (catches global leakage; always `new.env(parent=globalenv())`).
- After any R source edit: `Rscript tests/scripts/parse_sanity_check.R` and
  `testthat::test_file("tests/testthat/test-maintainability-ratchet.R")` (new tests don't affect the runtime ratchet).
- IMPORTANT — the FULL strict suite (`tests/testthat.R`) does NOT complete in this cloud checkout due to
  PRE-EXISTING failures unrelated to new tests: missing vendored minified assets
  (`www/css/all.min.css`, `www/codemirror/*`, `www/lib/threejs/*`) and missing `.Renviron`
  (`logout-url`, `ui-asset-manifest`, `runtime-network-boundary`, `claude-code-security-policy`,
  `file-resolution-security`, `maintainability-ratchet-contract`). Session 1 PROVED these fail identically on
  the base commit (clean `git worktree`). Do NOT try to "fix" them; classify as environment/checkout limits.
  Validate your work via per-file + batch runs, not the full suite.

## CONSTRAINTS
Additive only. Preserve Turkish user-facing strings; Turkish + UTF-8 comments/descriptions. No new heavy/browser/CDN deps
(no Playwright/Selenium/shinytest2/chromote). Keep stubs local; isolate with `new.env(parent=globalenv())`.

## DELIVERABLE
- As many new green `tests/testthat/test-*-behavior.R` (and `-contract.R` for UI) files as you can for the 8
  remaining files (then optional deepening). Each 0 fail / 0 warn.
- Short honest final report: files covered, test-file + assertion counts, any bug found & fixed, and an explicit
  per-file list of anything you could NOT cover offline and why.
- Commit with clear Turkish messages and push to the working branch `claude/modest-franklin-9rRWC`
  (do NOT open a new PR if one already exists for the branch).

Begin with STEP 1 (re-scan), show the remaining-file list, then generate tests file by file, validating each.

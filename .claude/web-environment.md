# Claude Code on the web — R environment

This repo is a Shiny app (not an R package). To let Claude Code web run the
test suite before answering, a **SessionStart hook** installs R and the test
dependencies when a web session begins.

## What runs automatically

`.claude/settings.json` registers `.claude/hooks/session-start.sh`, which:

1. Runs only in the remote/web environment (`CLAUDE_CODE_REMOTE=true`); it never
   touches a local machine.
2. Persists safe test-mode env vars for the whole session (via `CLAUDE_ENV_FILE`):
   `TZ=UTC`, `MERGEN_RUN_APP=false`, `MERGEN_DISABLE_FUTURES=true`, plus
   **placeholder** `LOCAL_LLM_ENDPOINT`, `DB_DSN`, `AI_KEYS_MASTER` (required by
   `R/config_file_store.R` at boot — these are not real secrets/DSNs).
3. Calls the existing `tools/setup_ai_r_environment.sh`, which installs R +
   system libraries and the R packages. The package list is read from
   `R/config_packages.R` (single source of truth) via
   `tests/scripts/ci_install_packages.R` — it is **not** duplicated in the hook.

The hook is **idempotent**: on a warm/cached container it detects that R and the
packages are already present and finishes quickly.

## Network access required

Configure the Claude Code web environment's network policy to allow:

- Ubuntu apt mirrors (system libraries + `r-base`)
- `https://packagemanager.posit.co` — Posit Package Manager (RSPM). On Ubuntu
  Noble this serves **precompiled binaries**, so even heavy packages
  (`duckdb`, `arrow`, `odbc`) install in seconds instead of compiling for many
  minutes.
- `https://cloud.r-project.org` — CRAN fallback if RSPM is unreachable.

If RSPM is blocked and it falls back to CRAN source builds, the first install
can be slow (duckdb/arrow compile from source). The cost is paid once because
the container state is cached after the hook completes.

## Validation commands

After the hook completes, these work from the repo root:

```bash
Rscript tests/testthat.R
Rscript -e 'source("tests/scripts/parse_sanity_check.R", encoding = "UTF-8")'
Rscript -e 'testthat::test_file("tests/testthat/test-api-key-choice-modal-contract.R")'
```

Or use the repo's single-entry validators:

```bash
bash tools/ai_validate.sh quick            # parse + focused contract tests
bash tools/ai_validate.sh full --boot-smoke # + app boot smoke
```

## Lighter fallback (if full install is too slow / unstable)

If the full dependency install can't complete (e.g. RSPM unreachable and source
builds time out), use the cloud-safe profile, which skips heavy source packages
(`duckdb,arrow,odbc,pool`) and the app-source smoke:

```bash
bash tools/ai_validate.sh cloud-quick
```

Tradeoff: `cloud-quick` proves parse sanity + focused contract tests only. It is
**not** proof of full runtime/app-boot. `Rscript tests/testthat.R` needs the full
dependency set.

## Sync vs async hook

The SessionStart hook currently runs **synchronously**: the session starts only
after dependencies are ready (no race conditions, but slower first start). To
trade safety for a faster start, switch it to async by making the hook's first
stdout line `echo '{"async": true, "asyncTimeout": 600000}'`.

# Claude Code on the web — R environment

This repo is a Shiny app (not an R package). To let Claude Code web run the test
suite before answering, R and the test dependencies are provisioned in the cloud
environment. There are **two cooperating pieces** plus **two one-time manual
settings** you configure in the Claude Code web UI.

## TL;DR — what you must configure once in the web UI

In the Claude Code web **environment edit dialog** ("Update cloud environment"
for the `MERGEN-Bilge` environment):

1. **Network access → Custom**, add these domains (and keep
   *"Also include default list of common package managers"* checked):
   ```
   packagemanager.posit.co
   rspm-sync.rstudio.com
   cloud.r-project.org
   ```
   R is **not** in the default Trusted allowlist, so without this the package
   repos return HTTP 403 and nothing installs.

   > **Critical:** `rspm-sync.rstudio.com` is mandatory if you want RSPM.
   > `packagemanager.posit.co` only serves the `PACKAGES` **index**; the actual
   > `.tar.gz` downloads are **307-redirected** to `rspm-sync.rstudio.com`
   > (both source `…/v4/1/packages/…` and binary `…/bin/<R>-<codename>/…`).
   > If that host is missing, the index returns 200 but every download dies with
   > `downloaded length 0 != reported length …` / HTTP 403 — the exact symptom of
   > a failed Setup script. The installer detects this and **auto-falls back to
   > CRAN** (`cloud.r-project.org`, which serves files directly), so the env still
   > works without it — just slower, because CRAN compiles heavy packages
   > (`arrow`, `duckdb`) from source instead of fetching RSPM binaries.

2. **Setup script** field → paste:
   ```bash
   bash /home/user/MERGEN-Bilge/tools/setup_ai_r_environment.sh
   ```
   This makes the install run **once** and get **cached** (see "Environment
   caching" below), so future sessions start fast and don't reinstall.

   > **Important:** Use the full absolute path. `$CLAUDE_PROJECT_DIR` is **not**
   > set during Setup Script execution (only in hooks), so
   > `"${CLAUDE_PROJECT_DIR}/tools/..."` expands to `/tools/...` and fails with
   > exit 127. Relative paths also fail because the cwd may not be the project
   > root when the Setup Script runs.

Changing either of these triggers a one-time cache rebuild on your **next**
session. Changes do **not** apply to an already-running session.

## The two repo-side pieces (already committed)

- **`.claude/hooks/session-start.sh`** — a SessionStart hook (matcher
  `startup|resume`). Remote-only, idempotent. It:
  1. Persists safe test-mode env vars for the whole session via `CLAUDE_ENV_FILE`:
     `TZ=UTC`, `MERGEN_RUN_APP=false`, `MERGEN_DISABLE_FUTURES=true`, plus
     **placeholder** `LOCAL_LLM_ENDPOINT`/`DB_DSN`/`AI_KEYS_MASTER` (required by
     `R/config_file_store.R` at boot — not real secrets/DSNs).
  2. Runs `tools/setup_ai_r_environment.sh` as an idempotent safety net. When the
     cached environment already has R + packages on disk, this is a fast no-op.
- **`tools/setup_ai_r_environment.sh`** — installs R + system libraries + R
  packages. The package list is read from `R/config_packages.R`
  (single source of truth) via `tests/scripts/ci_install_packages.R`; it is
  **not** duplicated. Idempotent.

### Setup script (cloud UI) vs SessionStart hook (repo)

| | Cloud **Setup script** | **SessionStart hook** |
|---|---|---|
| Configured in | Web UI dialog | `.claude/settings.json` (repo) |
| Runs | Before Claude launches, **only when no cached env exists** | After Claude launches, **every** startup/resume |
| Cached/reused | ✅ snapshotted, reused by later sessions | filesystem writes are not snapshotted |

This is why both are used: the **Setup script** does the heavy install once and
caches it; the **SessionStart hook** guarantees env vars and re-verifies (fast
no-op) on every session. For the "install once, reuse" behavior you want, the
**Setup script field must be set** — the hook alone would re-run per session.

## R version policy (on-prem parity)

- The on-prem Windows VM runs **R 4.5.1** and may be upgraded to newer versions.
  The production launcher (`run_mergen_prod.bat`) already auto-selects the newest
  installed R, and GitHub CI tests on R **4.4** and **4.5**.
- To keep cloud validation close to on-prem, `tools/setup_ai_r_environment.sh`
  installs the **latest R from the CRAN apt repo** (`<codename>-cran40`) by
  default, so it tracks future on-prem upgrades automatically.
- This requires `cloud.r-project.org` in the allowlist (see above). If the CRAN
  apt repo can't be added, it **falls back** to the distro `r-base` (e.g. Ubuntu
  Noble ships R 4.3.x) so setup never hard-fails.
- Override if needed:
  - `MERGEN_AI_INSTALL_LATEST_R=false` → use the distro `r-base` (faster, older).

Note: passing tests on a slightly older R is strong but not identical evidence to
on-prem. Runtime/VM/SSO/DB behavior is still proven only by the VM preflights
(see `RUNBOOK.md`).

## Network access required

Allow outbound access to:

- Ubuntu apt mirrors (system libraries, R base) — covered by the default list.
- `https://packagemanager.posit.co` — Posit Package Manager (RSPM) `PACKAGES`
  index. On Ubuntu Noble RSPM can serve **precompiled binaries**, so heavy
  packages (`duckdb`, `arrow`, `odbc`) install in seconds instead of compiling
  for many minutes.
- `https://rspm-sync.rstudio.com` — RSPM's package-file CDN. RSPM **307-redirects**
  every `.tar.gz` download here, so without this host the index resolves but
  downloads fail (HTTP 403 / `downloaded length 0`). Required for any RSPM use.
  `tests/scripts/ci_install_packages.R` verifies a real download (not just the
  index) and falls back to CRAN when this redirect is blocked.
- `https://cloud.r-project.org` — CRAN (package fallback **and** the apt repo for
  the latest R). Serves files directly with no cross-host redirect, so it works
  even when RSPM's CDN is blocked.

## Environment caching (why it's not "every prompt")

Per Claude Code web docs: the **Setup script** runs the first time you start a
session in an environment; afterward the filesystem is **snapshotted and reused**,
and the setup step is **skipped**. It re-runs only when you change the setup
script or the allowed domains, or after the cache expires (~7 days). So R and
packages are installed **once**, not per prompt and not per session.

Also: installing packages is plain shell execution — it **does not consume model
tokens**. Tokens are only spent when Claude reads/writes text. Tests run only when
explicitly invoked (or by the `Stop` hook when there are uncommitted code
changes), not on every prompt.

Keep the Setup script under ~5 minutes so the cache can build. RSPM binaries keep
the package install fast; if it ever exceeds the limit, move the install to an
**async** SessionStart hook (first stdout line
`{"async": true, "asyncTimeout": 600000}`).

## Validation commands (after the cache is built)

```bash
Rscript tests/testthat.R
Rscript -e 'source("tests/scripts/parse_sanity_check.R", encoding = "UTF-8")'
Rscript -e 'testthat::test_file("tests/testthat/test-api-key-choice-modal-contract.R")'
```

Or the repo's single-entry validators:

```bash
bash tools/ai_validate.sh quick             # parse + focused contract tests
bash tools/ai_validate.sh full --boot-smoke # + app boot smoke
bash tools/ai_validate.sh cloud-quick       # lighter fallback (skips heavy deps)
```

`cloud-quick` proves parse sanity + focused contract tests only — not full
runtime/app-boot. `Rscript tests/testthat.R` needs the full dependency set.

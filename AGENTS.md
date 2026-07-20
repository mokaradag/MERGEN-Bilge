# AGENTS.md

`CLAUDE.md` is the primary guide for this repository. It is the authoritative source for coding, testing, security, operational safeguards, and validation-honesty rules.

## Documentation map

- Product entry point: `README.md`
- Coding-agent and maintainer contract: `CLAUDE.md`
- Documentation hub: `docs/README.md`
- Architecture map: `docs/architecture-map.md`
- Database table structure: `docs/database-schema.md`
- Operations runbook: `RUNBOOK.md`
- Operational soak/load gate: `docs/operational-soak-gate.md`
- Dependency locking: `docs/dependency-locking.md`
- `renv.lock` status: `RENV_LOCK_STATUS.md`
- Release notes: `docs/release-notes.md`
- User-facing assistant behavior: `ai_rehber.md`

## Validation before final answer

- The normal validation command remains `bash tools/ai_validate.sh quick`.
- The Codex/Claude cloud fallback validation command is `bash tools/ai_validate.sh cloud-quick`.
- `cloud-quick` intentionally skips heavy runtime package bootstrap, such as `duckdb` and `arrow`, and app source smoke; agents must explicitly state when this mode was used and that full runtime/app boot validation was not performed.
- Before a final technical answer, run at least `bash tools/ai_validate.sh quick`.
- For risky changes affecting runtime, SSO, DB encoding, source order, file lifecycle, streaming, frontend asset order, Bilge Yolaç/Claude Code, security-path-download, or production VM behavior, run `bash tools/ai_validate.sh full --boot-smoke`.
- For long technical answer drafts, write the draft to `.ai/proposed_answer.md`, then validate it with `bash tools/ai_validate.sh quick --answer .ai/proposed_answer.md`.
- If `Rscript` is missing, do not give up immediately; first try to prepare the environment with `bash tools/setup_ai_r_environment.sh` or `bash tools/ai_validate.sh quick`.
- Say that `Rscript` is unavailable only if the bootstrap script also fails. In that case, include the exact command output and the failed step.
- If a required script is missing, clearly identify which script is missing; do not fabricate a successful result.
- If validation fails, summarize the failed step and any produced artifact/log path; do not hide the failure.
- Only say “tests passed,” “I verified,” “I ran the app,” or “the check is green” when the relevant command actually completed successfully and the validation summary contains zero failed steps.

### Mandatory maintainability gate for Codex and coding agents

- For every task that changes application code, R files, JavaScript, CSS, or runtime configuration, the final post-edit validation must run `bash tools/ai_validate.sh quick` at minimum.
- That validation must include and pass both `tests/testthat/test-maintainability-ratchet.R` and `tests/testthat/test-frontend-maintainability-ratchet.R`. The quick/cloud-quick validation entry point enforces these tests directly through `tools/maintainability_ratchet_gate.sh`.
- Validation performed before the last code edit does not count. If code changes after a successful validation run, run the validation again before the final answer.
- If either ratchet fails, refactor or otherwise fix the implementation before answering. Do not raise ratchet thresholds, budgets, baselines, or allowlists merely to make a regression pass unless the user explicitly requests a deliberate baseline change.
- Do not provide a successful final answer while either mandatory ratchet is failing. Report the exact failure honestly if it cannot be resolved within the task.
- The AI environment setup installs a local pre-commit hook when possible so the same mandatory ratchet gate is checked again against the final working tree before commit.

## Operational soak / load gate

- The operational soak gate (`tests/scripts/run_operational_soak_gate.R`) is **separate** from the VM evidence gate and from `ai_validate`. It does not replace them.
- It uses a three-lane design: **fake** LLM (main high-concurrency lane, zero real keys), **proxy** (personal-key routing/isolation proof), and **real-canary** (single real key, very low concurrency only).
- Do not make the main multi-user soak depend on one real LLM API key, and do not claim real 1,000-concurrent-user readiness from fake/proxy/canary runs. See `docs/operational-soak-gate.md` for profiles, env vars, artifacts, and the `does_prove`/`does_not_prove` honesty contract.
- Default profile is `smoke`. Run `Rscript tests/scripts/run_operational_soak_gate.R`; artifacts land in `artifacts/soak/<timestamp>/`.

## Post-deploy smoke evidence

- `Rscript tests/scripts/run_post_deploy_smoke.R` (run on the VM with the app up) collects health checks, computes an overall status (`pass`/`degraded`/`fail`) via the pure `mergen_post_deploy_smoke_evaluate()`, and `stop()`s on a critical break.
- It writes a secret-safe, machine-readable artifact **before** `stop()`: `artifacts/post-deploy-smoke/<timestamp>/post-deploy-smoke.json`. Built by the pure `mergen_post_deploy_smoke_artifact_record()`; it carries only health-check ids, status counts, and overall metadata plus mandatory `does_prove`/`does_not_prove` honesty fields. Never write raw log/env/secret values; keep it redacted.
- The pure reader `release_evidence_post_deploy_smoke_summary()` surfaces the latest artifact in **Sistem Durumu > Doğrulama Kanıtı**. A missing artifact is reported honestly as not_found, never as success. This is a deployment-moment **snapshot** of health only — NOT load/concurrency, long-running stability, real browser UX, or VM/SSO/SQL Server Turkish encoding proof.

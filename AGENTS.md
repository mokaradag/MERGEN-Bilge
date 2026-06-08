# AGENTS.md

`CLAUDE.md` is the primary guide for this repository. It is the authoritative source for coding, testing, security, operational safeguards, and validation-honesty rules.

## Documentation map

- Product entry point: `README.md`
- Coding-agent and maintainer contract: `CLAUDE.md`
- Documentation hub: `docs/README.md`
- Architecture map: `docs/architecture-map.md`
- Database table structure: `docs/database-schema.md`
- Operations runbook: `RUNBOOK.md`
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

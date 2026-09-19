# Claude Code instruction staleness audit

This audit accompanies the refactor of the former 8,422-line root `CLAUDE.md`.
Its purpose is to prevent a different failure mode: saving tokens by blindly
copying old claims into smaller files even when those claims are stale or are
better derived from source.

## Classification used

1. **Invariant / behavioral contract** — migrate to root or a path-scoped rule.
2. **Subsystem contract** — migrate to a path-scoped rule, preserving the
   operative constraint rather than the historical narrative.
3. **Historical rationale / regression archaeology** — preserve in the verbatim
   archive; consult deliberately when current code/tests do not explain why.
4. **Dynamic/current-state snapshot** — do not migrate as a fact. Point Claude
   at the canonical source and derive the value when needed.
5. **Confirmed stale snapshot** — keep only in the archive with this audit
   documenting that it must not be treated as current.

## Confirmed stale item

### `Current Product Version Reference`

Former `CLAUDE.md` says:

- current public version history: `v1.0`
- previous: `v0.9`

On the refactor base (`main` at commit
`0e57f7b2a55386cfeccfd86e37e3b88875dac081`), the first release entry in
`version_history.md` is `v1.3 | 2026-09-04`.

Disposition: **not migrated into live Claude instructions**. Root
`CLAUDE.md` and `.claude/rules/docs-operations.md` now require reading
`version_history.md` as the source of truth.

## Dynamic snapshot sections retired from live memory

The following old sections may contain useful history, but their inventories are
not suitable as persistent "current" facts:

| Former section | Live source of truth |
|---|---|
| Current baseline coverage | `tests/`, test runner and validation scripts |
| Current server initialization helper layer | `server.R`, `R/server_*.R`, source manifest |
| Current plugin roster (15 plugins) | `bilge_yolac_plugins/` |
| Current tracked async families | performance instrumentation + health code |
| Current User-Facing Pages and What They Mean | `ui.R`, modules and server wiring |
| Required Environment Variables | `.Renviron.example` + owning config code |
| Root-Level Files / Directories | repository tree |
| `global.R` Load Order | `R/config_source_manifest.R` + bootstrap code |

The plugin roster happened still to contain 15 top-level plugin directories at
the audit point. It is still classified as dynamic because the count can change
without this instruction file being updated.

## Historical language handled conservatively

Headings or paragraphs containing words such as `Recent`, `Current`,
`New Standard`, version numbers, dated VM evidence, exact test counts, model
rosters, file/function counts, or rollout status are not automatically promoted
to live rules.

If they express a durable invariant, that invariant is summarized in the
matching scoped rule. The dated/count/list portion remains in the archive.

## Loss-prevention rule

The archive is not evidence that a rule is safely removable from live context.
For a fragile boundary, the refactor must keep the operative constraint in the
matching scoped rule. If a reviewer cannot identify where an important
invariant moved, restore or strengthen the scoped rule rather than deleting the
constraint.

Conversely, do not restore stale snapshot prose merely to make the new files
look more complete. Prefer canonical source pointers.

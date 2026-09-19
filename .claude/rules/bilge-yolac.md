---
paths:
  - "R/config_claude_code*.R"
  - "R/helpers_claude_code*.R"
  - "R/module_claude_code*.R"
  - "R/server_*claude*.R"
  - "www/**/*claude*.js"
  - "bilge_yolac_plugins/**"
  - "tests/**/*claude-code*.R"
  - "tests/**/*bilge-yolac*.R"
---

# Bilge Yolaç / Claude Code integration

- Preserve Windows/VM CLI/workdir compatibility, request-id ownership, runtime
  leases, bounded scans, output diff/sync, and process cleanup.
- Never mirror an entire selected directory or traverse it unbounded. Required
  inputs belong in the isolated per-run workspace and scanners remain bounded.
- Expensive scan/copy/extract/snapshot/diff/download/sync work remains off the
  main Shiny event loop.
- Preparation state is distinct from model-execution state. Do not display
  "Çalışıyor" before the Claude process actually starts.
- Every async callback must re-check the active request/run before updating UI,
  DB state, files, leases, or final status.
- Process pipes must be drained safely; output buffers remain bounded. Preserve
  stop/cancel idempotence and do not let a late stop corrupt a finished run.
- Runtime cleanup/lease takeover is ownership-sensitive. Never delete or restore
  another/newer run's workspace based only on age.
- Output processing and sync happen once per run and only for approved changed
  files inside the output area.
- Stream-json parsing must preserve tool events and final result text; never
  expose raw secret-bearing CLI payloads.
- Permission modes and allowed/disallowed tools remain fail-closed.
- Plugin inventory is dynamic: inspect `bilge_yolac_plugins/`; do not hardcode
  "current plugin roster" counts in instructions.
- Generated document/download text must preserve Turkish encoding on Windows.
- For rare regressions, consult archive headings on Bilge Yolaç security,
  non-blocking pipeline, streaming, sessions, runtime leases and downloads.

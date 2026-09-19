---
paths:
  - "R/config_file_store*.R"
  - "R/helpers_file*.R"
  - "R/helpers_files*.R"
  - "R/module_file_manager*.R"
  - "R/helpers_claude_code_document*.R"
  - "R/helpers_claude_code_download*.R"
  - "R/helpers_claude_code_workdir*.R"
  - "tests/**/*file*.R"
  - "tests/**/*upload*.R"
  - "tests/**/*download*.R"
  - "tests/**/*path*.R"
---

# Files, storage, uploads and downloads

- File access is user-scoped and root-bounded. Never trust client-provided paths,
  names, relative paths, symlinks/reparse targets, or extension/MIME claims.
- Use canonical path-resolution and path-inside-root helpers. Windows drive,
  UNC, separator, device-name, ADS and Turkish-path behavior matter.
- Preserve typed accept/reject results in the file pipeline; callers must not
  treat a rejected persistence step as a successful attachment.
- Upload promotion/copy/index updates have concurrency and ownership semantics.
  Do not replace reservations, lock heartbeats, atomic promotion/write, or
  reconciliation with naive exists-then-write logic.
- File-store index lock ownership must be proven before save/release. Temporary
  filesystem uncertainty must not be interpreted as "file absent."
- Expensive ingestion, scan, copy, extraction, snapshot/diff and staging work
  stays off the Shiny event loop where currently asynchronous.
- Stale async preview/refresh results must not overwrite newer user selections.
- Download filenames/HTML/JS payloads remain escaped and root-scoped.
- Preserve UTF-8/BOM behavior for Windows-opened downloadable text where the
  owning helper/tests require it.
- Do not weaken upload-size/client guards or file isolation to make tests pass.
- For complex race/security rationale, consult archive headings on file
  lifecycle, File Manager, path resolution, ingestion, and document downloads.

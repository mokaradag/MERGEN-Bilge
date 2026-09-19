---
paths:
  - "R/utils_text_encoding.R"
  - "R/helpers_mailto_encoding.R"
  - "R/helpers_db*.R"
  - "R/helpers_database.R"
  - "R/config_sql_loader.R"
  - "tests/**/*encoding*.R"
  - "tests/**/*db*.R"
  - "tests/**/*mailto*.R"
  - "tests/scripts/*encoding*.R"
---

# Encoding and database safety

- Turkish text, emoji handling, and mojibake repair are centralized. Do not add
  scattered local replacement maps.
- Server text normalization belongs in `R/utils_text_encoding.R`.
- DB Unicode escape/restore belongs in `R/helpers_db_unicode_escape.R`; DB
  parameter/read normalization and mojibake guards belong in
  `R/helpers_db_encoding.R`; connection/pool concerns stay in connection files.
- Preserve DB helper source order: Unicode escape -> DB encoding -> connection ->
  user encoding/validation/chat helpers. Test bootstrap must mirror runtime.
- User-visible DB values use visible-value normalization. Technical IDs/enums,
  usernames, email, Sicil/Keycloak IDs, model names and paths must not receive
  blanket mojibake repair.
- On the Windows production VM, `DB_CLIENT_ENCODING=WINDOWS-1254` is the known
  safe operational setting unless live VM + SQL Server evidence proves otherwise.
  Never force raw UTF-8 into a non-UTF-8 ODBC parameter path.
- Unsupported Unicode on a non-UTF-8 DB path must use the ASCII escape-token
  boundary and restore on read/UI. Do not trade Turkish integrity for emoji.
- New `MB_Messages` writes remain guarded before commit. Preserve rollback
  semantics and legacy-schema handling; historical dirty rows do not justify
  weakening new-write guards.
- Historical mojibake repair is a separate, backup-approved maintenance task.
- Mailto subject/body encoding uses `mergen_mailto_href()` /
  `mergen_mailto_percent_encode()`, not locale-sensitive raw `URLencode()`.
- Windows/parser-sensitive tests should build unsupported Unicode deterministically
  (for example `intToUtf8()`) instead of relying on console/source literals.
- Preserve DB transaction ownership, rollback, pool checkout/return, and
  RowVersion/concurrency semantics.
- For rare rationale, consult the archived headings on text encoding,
  WINDOWS-1254 source safety, DB modularization, and transaction-safe pooling.

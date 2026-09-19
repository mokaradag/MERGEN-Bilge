---
paths:
  - "R/config_bilge_savunmasi.R"
  - "R/helpers_bilge_savunmasi*.R"
  - "R/helpers_db_bilge_savunmasi*.R"
  - "R/**/*ortak_oturum*.R"
  - "R/module_bilge_savunmasi*.R"
  - "R/module_ortak_oturum*.R"
  - "tests/**/*bilge-savunmasi*.R"
  - "tests/**/*ortak-oturum*.R"
  - "docs/ortak-oturumlar.md"
---

# Isolated feature contracts

## Bilge Savunması

- Preserve the canonical game/config/DB ownership seams and active-run/checkpoint
  query limits.
- Do not widen permissions or move game state into unrelated shared runtime
  helpers to avoid local maintainability limits.

## Ortak Oturumlar

- Membership/content access and write roles are separate authorization checks;
  removed users must not retain write access through stale role rows/state.
- Shared-workspace file operations remain root-bounded, reservation/ownership
  safe and identity-scoped.
- Presence/freshness timestamps use the established Türkiye-time semantics;
  do not mix local timestamps with UTC assumptions.
- "Odaya Yaz" and "Yapay Zekâya Sor" remain distinct interaction semantics.
- Async/poll refresh must not erase user open/closed preferences or resurrect
  stale content.
- Consult `docs/ortak-oturumlar.md` and focused tests before changing room,
  invitation, shared-document or Bilge Yolaç shared-workspace behavior.

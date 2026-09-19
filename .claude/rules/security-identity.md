---
paths:
  - "R/config_sso.R"
  - "R/helpers_sso*.R"
  - "R/helpers_api_key*.R"
  - "R/helpers_feature_api_key.R"
  - "R/module_api_key.R"
  - "R/module_user_identity.R"
  - "R/server_init_user_session.R"
  - "R/**/*identity*.R"
  - "R/**/*security*.R"
  - "tests/**/*sso*.R"
  - "tests/**/*identity*.R"
  - "tests/**/*api-key*.R"
  - "tests/**/*security*.R"
---

# Security and identity boundaries

- Authorization is fail-closed. Invalid/missing/non-scalar identity claims,
  JWT/JWKS data, user IDs, or permission modes must never widen access.
- Use canonical effective-user and SSO identity resolvers. Do not reconstruct
  identity from display names or loosely cast logical/list/nonnumeric values.
- Preserve JWT signature verification, key selection, auth-ready ordering,
  expiry handling, user-switch resets, and separation of visible vs technical
  DB normalization.
- Secrets must never appear in logs, persisted Claude Code output, fixtures,
  docs, PR text, or artifacts. Use canonical redaction helpers.
- API-key read paths may degrade safely only where designed; write/update paths
  remain strict. Validate encrypted formats before decrypt/use.
- Unknown permission modes must fall back to the documented safe strictness,
  never to a more permissive edit mode.
- Path/download authorization and per-user storage isolation are security
  boundaries, not UX conveniences.
- Do not leak cached/session state across identity switches, feedback state,
  shared sessions, File Manager state, or API-key resolution.
- Security fixes should cover both allowed and denied paths in focused tests.
- For historical edge cases, consult the archive headings on identity
  fail-closed behavior, Claude Code security, path/user isolation, and SSO.

---
paths:
  - "ui.R"
  - "welcome_screen.R"
  - "www/**"
  - "R/config_ui_asset*.R"
  - "R/welcome*.R"
  - "R/module_startup_screen.R"
  - "R/module_sidebar*.R"
  - "R/module_settings*.R"
  - "R/module_destek*.R"
  - "R/module_image_generation.R"
  - "tests/**/*frontend*.R"
  - "tests/**/*ui*.R"
  - "tests/**/*welcome*.R"
  - "tests/**/*browser*.R"
---

# Frontend and UI contract

- Preserve current polished UX unless the task explicitly changes behavior.
- Frontend assets load through `R/config_ui_assets.R`; asset/zone registries
  own dependency order. Do not inject duplicate assets or casually reorder them.
- Keep selectors and IDs stable unless all JS/server/test consumers migrate
  together. One lifecycle should have one owner.
- Preserve dark/light theme parity, contrast, modern-welcome ownership and
  accessibility of primary controls/notifications.
- Browser-rendered Turkish text uses the shared encoding boundary; do not add
  feature-local mojibake maps.
- User/model raw HTML must not bypass markdown/XSS safety, including persisted
  content restored into the browser.
- Animation/media changes must consider older/integrated corporate GPUs and
  reduced-motion behavior; avoid gratuitous continuous compositor work.
- Keep console hygiene: no recurring errors/warnings, unhandled rejections, or
  duplicate handler registration.
- CSS fixes should target the owning stacking/positioning/overflow layer rather
  than broad high-specificity overrides.
- Current pages and current asset lists are derived from UI/manifests, not copied
  into Claude rules.
- Consult archived frontend/theme/welcome/selector headings only for rationale
  not recoverable from current code and regression tests.

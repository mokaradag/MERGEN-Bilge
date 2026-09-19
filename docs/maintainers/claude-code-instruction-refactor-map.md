# Claude Code Instruction Refactor Map

This document records the conservative migration plan for the former 8,422-line root `CLAUDE.md`.

## Safety strategy

- The former `CLAUDE.md` is preserved verbatim at `docs/maintainers/claude-code-full-contract-reference.md`.
- The archive is **reference-only**. It must not be imported with `@` from live Claude instructions.
- Always-applicable rules move to a compact root `CLAUDE.md`.
- Subsystem rules move to path-scoped files under `.claude/rules/`.
- Long history, implementation narratives, exhaustive test inventories, and one-off regression archaeology remain recoverable in the archive and existing canonical docs.
- Runtime behavior is not changed by this refactor.

## Destination set

- `CLAUDE.md` — always-loaded repository contract, targeted below 200 lines.
- `.claude/rules/encoding-database.md`
- `.claude/rules/security-identity.md`
- `.claude/rules/runtime-architecture.md`
- `.claude/rules/frontend-ui.md`
- `.claude/rules/files-storage.md`
- `.claude/rules/bilge-yolac.md`
- `.claude/rules/project-resource-analysis.md`
- `.claude/rules/llm-chat-streaming.md`
- `.claude/rules/speech-media.md`
- `.claude/rules/admin-health.md`
- `.claude/rules/testing-validation.md`
- `.claude/rules/docs-operations.md`
- `.claude/rules/special-features.md`
- `docs/maintainers/claude-code-full-contract-reference.md` — verbatim historical/full-detail reference, never auto-loaded.

## Original file metrics

- Source blob: `f4c5f0dc9af920de14d460e1464dc75c6b47ae53`
- Lines: 8422
- Characters: 764188
- Headings mapped: 314

## Section-by-section migration map

Every H2–H4 heading from the former file is listed below. The archive remains the lossless source for the exact former wording even where the live rule becomes shorter.

| Original line | Level | Original heading | Primary new home |
|---:|:---:|---|---|
| 4 | H2 | Read this first | `CLAUDE.md` |
| 36 | H2 | Purpose of This File | `CLAUDE.md` |
| 57 | H2 | Non-Negotiable Repo Rules | `CLAUDE.md` |
| 59 | H3 | 1) Preserve Turkish text integrity | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 70 | H3 | 1B) Text encoding and mojibake boundary contract | `.claude/rules/encoding-database.md` |
| 124 | H3 | File Reading, Encoding, and Ratchet Notes | `.claude/rules/encoding-database.md` |
| 132 | H3 | Windows VM focused test coverage and path/API-key encoding contract | `.claude/rules/encoding-database.md` |
| 146 | H3 | Service-dependent behavioral tests and API-key salt guard | `.claude/rules/testing-validation.md` |
| 160 | H3 | Async stale-request guards, startup parity, and File Manager refresh boundary | `.claude/rules/runtime-architecture.md` |
| 179 | H3 | Version history path resolution contract | `.claude/rules/files-storage.md` |
| 190 | H3 | 1C) Streaming and final markdown HTML safety boundary | `.claude/rules/llm-chat-streaming.md` |
| 213 | H3 | 1D) Modern welcome light-theme and neural pointer boundary | `.claude/rules/frontend-ui.md` |
| 219 | H3 | 1E) Support and version-page light-theme UX boundary | `.claude/rules/frontend-ui.md` |
| 231 | H3 | 1E.1) Light Theme Header and Badge Consistency | `.claude/rules/frontend-ui.md` |
| 243 | H3 | 1F) Effective API key resolution for non-chat AI features | `.claude/rules/security-identity.md` |
| 256 | H3 | API key choice modal boundary | `.claude/rules/security-identity.md` |
| 269 | H3 | Help Center chatbot light-theme contrast boundary | `.claude/rules/frontend-ui.md` |
| 353 | H3 | 1D) Browser UX smoke coverage boundary | `.claude/rules/testing-validation.md` |
| 394 | H3 | Claude Code on the web (cloud session) R environment contract | `.claude/rules/bilge-yolac.md` |
| 447 | H3 | AI agent validation rule | `.claude/rules/testing-validation.md` |
| 470 | H3 | VM evidence gate contract (single repeatable preflight path) | `.claude/rules/testing-validation.md` |
| 492 | H3 | Validation proof and overclaim boundary | `.claude/rules/testing-validation.md` |
| 534 | H3 | Cloud validation and stale-checkout discipline | `.claude/rules/testing-validation.md` |
| 555 | H3 | renv dependency-lock contract | `.claude/rules/docs-operations.md` |
| 577 | H3 | Image upload, preview, and the vision (görsel anlama) pipeline | `.claude/rules/files-storage.md` |
| 582 | H3 | DOCX preview async clobber guard | `.claude/rules/runtime-architecture.md` |
| 590 | H3 | Behavioral-test maintenance lessons | `.claude/rules/security-identity.md` |
| 645 | H3 | Deep Space intro maintenance notes | `.claude/rules/frontend-ui.md` |
| 655 | H3 | Theme system and light-theme contract | `.claude/rules/frontend-ui.md` |
| 674 | H3 | Sidebar user panel, Department, and version source contract | `.claude/rules/frontend-ui.md` |
| 688 | H3 | Brand title single-source contract | `.claude/rules/frontend-ui.md` |
| 697 | H3 | Tool contextual background animation contract | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 712 | H3 | Tool-mode model lock and Excel/Coding deep-thinking contract | `.claude/rules/llm-chat-streaming.md` |
| 728 | H3 | Bilge Savunması (tower defense) game contract | `.claude/rules/special-features.md` |
| 750 | H3 | Bilge Yolaç / Claude Code security regression contract | `.claude/rules/security-identity.md` |
| 783 | H3 | Identity fail-closed contract (PR #717) | `.claude/rules/security-identity.md` |
| 1123 | H3 | Log redaction and secret-fixture contract | `.claude/rules/security-identity.md` |
| 1144 | H3 | File Manager table runtime refactor contract | `.claude/rules/runtime-architecture.md` |
| 1165 | H3 | Server core observer runtime refactor contract | `.claude/rules/runtime-architecture.md` |
| 1200 | H3 | Admin Hata Analizi heatmap data boundary contract | `.claude/rules/admin-health.md` |
| 1243 | H3 | Source manifest and MCP load-order contract | `.claude/rules/runtime-architecture.md` |
| 1286 | H3 | Frontend asset manifest and maintainability ratchet contract | `.claude/rules/frontend-ui.md` |
| 1319 | H3 | Startup lane contract (Hızlı Başlangıç / Zengin Deneyim) | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 1346 | H3 | Startup media readiness and real-progress contract | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 1358 | H3 | Accessibility contract for main chat controls and toast notifications | `.claude/rules/frontend-ui.md` |
| 1402 | H3 | 1C.0) Non-blocking file ingestion contract | `.claude/rules/files-storage.md` |
| 1439 | H3 | 1C) File lifecycle and File Manager boundary contract | `.claude/rules/files-storage.md` |
| 1560 | H3 | Fragile-flow manual preflight | `.claude/rules/testing-validation.md` |
| 1608 | H3 | Bilge Yolaç document download and stream-poll contract | `.claude/rules/bilge-yolac.md` |
| 1619 | H3 | Tool-use visibility and stream-json compatibility | `.claude/rules/frontend-ui.md` |
| 1631 | H3 | Stream-json parser compatibility | `.claude/rules/frontend-ui.md` |
| 1641 | H3 | Windows VM, UNC, and runtime workdir compatibility | `.claude/rules/runtime-architecture.md` |
| 1675 | H3 | 1A) Keep new code identifiers ASCII-safe when practical | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 1678 | H3 | 1G) WINDOWS-1254 source-safety contract (Windows VM parse boundary) | `.claude/rules/encoding-database.md` |
| 1719 | H3 | 2) Comments added to code must be in Turkish | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 1722 | H3 | 2A) Character / persona system contract | `.claude/rules/speech-media.md` |
| 1744 | H3 | 3) Prefer surgical changes | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 1754 | H3 | 3B) Preserve UX while improving architecture and security | `.claude/rules/security-identity.md` |
| 1850 | H3 | 3C) Bilge Yolaç Windows runtime and Claude Code CLI contract | `.claude/rules/runtime-architecture.md` |
| 1889 | H3 | 4) Do not create unnecessary new files | `.claude/rules/files-storage.md` |
| 1892 | H3 | 5) Respect the project’s modular load order | `.claude/rules/runtime-architecture.md` |
| 1900 | H3 | Source manifest validation contract | `.claude/rules/runtime-architecture.md` |
| 1972 | H3 | Seam registry and frontend ownership zone contract | `.claude/rules/frontend-ui.md` |
| 2007 | H3 | File resolution, upload-size, and user-isolation contract | `.claude/rules/files-storage.md` |
| 2057 | H3 | Bilge Yolaç Claude Code execution security contract | `.claude/rules/security-identity.md` |
| 2148 | H3 | API model configuration contract | `.claude/rules/llm-chat-streaming.md` |
| 2177 | H3 | API key onboarding and choice modal contract | `.claude/rules/security-identity.md` |
| 2232 | H3 | Server runtime and module wiring contract | `.claude/rules/runtime-architecture.md` |
| 2302 | H3 | send_message prompting and file-context contract | `.claude/rules/llm-chat-streaming.md` |
| 2357 | H3 | Frontend selector and DOM contract | `.claude/rules/frontend-ui.md` |
| 2373 | H4 | Follow-up suggestions contract | `.claude/rules/llm-chat-streaming.md` |
| 2391 | H3 | UI asset manifest contract | `.claude/rules/frontend-ui.md` |
| 2457 | H3 | Frontend asset and maintainability ratchet contract | `.claude/rules/frontend-ui.md` |
| 2461 | H3 | Frontend Console Hygiene Notes | `.claude/rules/frontend-ui.md` |
| 2479 | H3 | Frontend complexity doctor | `.claude/rules/frontend-ui.md` |
| 2494 | H3 | Subprocess pipe drain contract (PR #717) | `.claude/rules/bilge-yolac.md` |
| 2525 | H3 | Media and background music contract | `.claude/rules/speech-media.md` |
| 2564 | H3 | Attached welcome-screen animation contract | `.claude/rules/frontend-ui.md` |
| 2616 | H3 | E2E/race regression test foundation contract | `.claude/rules/testing-validation.md` |
| 2880 | H3 | LLM worker tool-result formatting contract | `.claude/rules/llm-chat-streaming.md` |
| 2918 | H3 | Bilge Yolaç Oturumlar (kalıcı oturum) sayfası contract | `.claude/rules/bilge-yolac.md` |
| 2932 | H3 | Ortak Oturumlar (Collaborative Sessions) contract | `.claude/rules/special-features.md` |
| 3409 | H3 | Sesli Giriş (STT) async transcription contract | `.claude/rules/runtime-architecture.md` |
| 3443 | H3 | Yazı Tipi Boyutu pending-until-save contract | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 3458 | H3 | Yapılandırma CSS-only setting tooltip contract | `.claude/rules/frontend-ui.md` |
| 3490 | H3 | Yönetici Paneli CSS-only tooltip contract | `.claude/rules/frontend-ui.md` |
| 3504 | H3 | Model reset / timeout / output-token notes | `.claude/rules/llm-chat-streaming.md` |
| 3525 | H3 | Long code block integrity contract | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 3551 | H3 | Bilge Yolaç run lifecycle request-id contract | `.claude/rules/bilge-yolac.md` |
| 3579 | H3 | Bilge Yolaç non-blocking run pipeline contract | `.claude/rules/bilge-yolac.md` |
| 3671 | H3 | Bilge Yolaç directory-listing contract | `.claude/rules/files-storage.md` |
| 3709 | H3 | Windows VM real preflight SSO contract | `.claude/rules/security-identity.md` |
| 3747 | H3 | User session initialization contract | `.claude/rules/security-identity.md` |
| 3860 | H3 | ServerRuntimeContext contract | `.claude/rules/runtime-architecture.md` |
| 3973 | H3 | Session userData list-store contract | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 4073 | H3 | Core interaction runtime contract | `.claude/rules/runtime-architecture.md` |
| 4106 | H3 | Server module wiring contract | `.claude/rules/runtime-architecture.md` |
| 4199 | H3 | Database helper modularization contract | `.claude/rules/encoding-database.md` |
| 4228 | H3 | Transaction-safe DB connection pool contract | `.claude/rules/encoding-database.md` |
| 4248 | H3 | ChartLab rendering and saved-chat hydration contract | `.claude/rules/llm-chat-streaming.md` |
| 4285 | H3 | File Store registry/index modularization contract | `.claude/rules/files-storage.md` |
| 4313 | H3 | Bilge Yolaç run lifecycle and stop-finalization contract | `.claude/rules/bilge-yolac.md` |
| 4322 | H3 | Bilge Yolaç workdir scan and generated-download contract | `.claude/rules/files-storage.md` |
| 4383 | H3 | Bilge Yolaç document extractor modularization contract | `.claude/rules/bilge-yolac.md` |
| 4405 | H3 | Project/Resource Analysis security-summary helper contract | `.claude/rules/security-identity.md` |
| 4441 | H3 | Send-message request lifecycle contract | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 4477 | H3 | LLM SSE stream I/O contract | `.claude/rules/llm-chat-streaming.md` |
| 4501 | H3 | UTF-8 streaming chunk contract | `.claude/rules/llm-chat-streaming.md` |
| 4507 | H3 | Thinking model capability contract | `.claude/rules/llm-chat-streaming.md` |
| 4513 | H3 | LLM worker payload helper contract | `.claude/rules/llm-chat-streaming.md` |
| 4551 | H3 | Bilge Yolaç UI and model/config modularization contract | `.claude/rules/frontend-ui.md` |
| 4617 | H3 | Proje/Kaynak Analizi filter modularization contract | `.claude/rules/project-resource-analysis.md` |
| 4641 | H3 | Proje/Kaynak Analizi query-selection modularization contract | `.claude/rules/project-resource-analysis.md` |
| 4665 | H3 | Proje ve Kaynak Analizi non-blocking execution contract (Phase 6, §5.10) | `.claude/rules/project-resource-analysis.md` |
| 5103 | H3 | Proje ve Kaynak Analizi selection prompt-fitting and capability policy | `.claude/rules/project-resource-analysis.md` |
| 5258 | H3 | Proje ve Kaynak Analizi query-metadata generator contract (Faz 3b, VM-only tooling) | `.claude/rules/project-resource-analysis.md` |
| 5602 | H3 | File Manager modularization contract | `.claude/rules/files-storage.md` |
| 5632 | H3 | File Manager state runtime extraction contract | `.claude/rules/runtime-architecture.md` |
| 5676 | H3 | Settings Yapılandırma UI modularization contract | `.claude/rules/frontend-ui.md` |
| 5706 | H3 | Startup screen UI/server split contract | `.claude/rules/frontend-ui.md` |
| 5736 | H3 | Image generation UI/runtime split contract | `.claude/rules/runtime-architecture.md` |
| 5760 | H3 | Admin Hata Analizi modularization contract | `.claude/rules/admin-health.md` |
| 5788 | H3 | Admin Yanıt Analizi modularization contract | `.claude/rules/admin-health.md` |
| 5857 | H3 | 7) Preserve existing UX wording | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 5860 | H3 | 7A) Prefer canonical identity resolution helpers | `.claude/rules/security-identity.md` |
| 5906 | H3 | 8) Async jobs visible in health metrics must use tracked wrapper | `.claude/rules/runtime-architecture.md` |
| 5913 | H3 | 8A) tracked_future_promise() is also a worker dependency wrapper | `.claude/rules/runtime-architecture.md` |
| 5934 | H3 | 8B) Source-time side effects must be guarded | `.claude/rules/runtime-architecture.md` |
| 5941 | H3 | Upload-size policy and client-side guard | `.claude/rules/files-storage.md` |
| 5952 | H2 | Health Dashboard Architecture | `.claude/rules/admin-health.md` |
| 5984 | H3 | Health Dashboard path configuration notes | `.claude/rules/admin-health.md` |
| 6019 | H3 | 9) If there is a bug fix, include a test when possible | `.claude/rules/testing-validation.md` |
| 6026 | H3 | 9A) Decomposing the MCP Excel path-resolution chain | `.claude/rules/project-resource-analysis.md` |
| 6059 | H3 | 9B) Tool-Specific Runtime Model Resolution and Reasoning Streams | `.claude/rules/runtime-architecture.md` |
| 6080 | H4 | SQL/Proje analizi (sql_analysis) live reasoning streaming contract | `.claude/rules/project-resource-analysis.md` |
| 6094 | H3 | 9C) Logging wrappers must preserve caller-frame glue evaluation | `.claude/rules/admin-health.md` |
| 6106 | H3 | Structured runtime error logging contract | `.claude/rules/runtime-architecture.md` |
| 6116 | H2 | Test Suite and Execution Rules | `.claude/rules/testing-validation.md` |
| 6143 | H3 | Focused behavioral regression contracts | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 6177 | H3 | Strict test runner rule | `.claude/rules/testing-validation.md` |
| 6185 | H3 | testthat edition declaration contract | `.claude/rules/speech-media.md` |
| 6222 | H3 | Current baseline coverage | `.claude/rules/testing-validation.md` |
| 6285 | H3 | Scripted validation flow (`tests/scripts/`) | `.claude/rules/testing-validation.md` |
| 6301 | H3 | Admin Feedback Analysis modularization contract | `.claude/rules/admin-health.md` |
| 6368 | H3 | Production operation | `.claude/rules/docs-operations.md` |
| 6418 | H3 | Production launcher self-test | `.claude/rules/runtime-architecture.md` |
| 6453 | H2 | Reasoning Flow for Düşünüyorum=TRUE Models (New Standard) | `.claude/rules/llm-chat-streaming.md` |
| 6457 | H3 | Premium reasoning card behavior | `.claude/rules/llm-chat-streaming.md` |
| 6466 | H3 | UI/JS principles | `.claude/rules/frontend-ui.md` |
| 6475 | H3 | Live reasoning panel and persistence | `.claude/rules/llm-chat-streaming.md` |
| 6482 | H3 | Model-specific request_overrides contract | `.claude/rules/llm-chat-streaming.md` |
| 6502 | H3 | LLM content/reasoning fallback contract | `.claude/rules/llm-chat-streaming.md` |
| 6508 | H3 | Reasoning debug log policy | `.claude/rules/llm-chat-streaming.md` |
| 6513 | H3 | Critical note for CSS regressions | `.claude/rules/frontend-ui.md` |
| 6522 | H2 | What MERGEN Bilge Is | `CLAUDE.md` |
| 6554 | H2 | High-Level Boot Flow | `.claude/rules/runtime-architecture.md` |
| 6556 | H3 | Entry point: `app.R` | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 6570 | H3 | Why `app.R` matters | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 6581 | H3 | Production runtime entrypoint contract | `.claude/rules/runtime-architecture.md` |
| 6591 | H3 | Production log viewing contract | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 6601 | H2 | Encoding and Safe Sourcing | `.claude/rules/encoding-database.md` |
| 6618 | H3 | Source manifest newline normalization contract | `.claude/rules/runtime-architecture.md` |
| 6622 | H3 | Practical rule | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 6627 | H2 | Required Environment Variables | `.claude/rules/runtime-architecture.md` |
| 6639 | H3 | Important optional environment groups | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 6641 | H4 | Database | `.claude/rules/encoding-database.md` |
| 6648 | H4 | LLM | `.claude/rules/llm-chat-streaming.md` |
| 6658 | H4 | Kurumsal Langflow (Süreç Yönetimi / Uygulama Uzmanı) | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 6685 | H4 | Vision (görsel anlama) | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 6689 | H4 | TTS | `.claude/rules/speech-media.md` |
| 6697 | H4 | STT | `.claude/rules/speech-media.md` |
| 6701 | H4 | SSO / Keycloak | `.claude/rules/security-identity.md` |
| 6711 | H4 | Bilge Yolaç / Claude Code | `.claude/rules/bilge-yolac.md` |
| 6719 | H4 | Bilge Yolaç Plugins | `.claude/rules/bilge-yolac.md` |
| 6722 | H4 | Image generation | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 6728 | H4 | Service desk | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 6732 | H4 | File storage | `.claude/rules/files-storage.md` |
| 6737 | H2 | Real Architecture | `.claude/rules/runtime-architecture.md` |
| 6739 | H2 | Root-Level Files | `.claude/rules/runtime-architecture.md` |
| 6751 | H2 | Root-Level Directories (non-R/) | `.claude/rules/runtime-architecture.md` |
| 6760 | H2 | `global.R` Load Order | `.claude/rules/runtime-architecture.md` |
| 6764 | H3 | Group 1 - Foundation | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 6782 | H3 | Group 2 - Configuration | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 6801 | H3 | Group 3 - Database and SQL | `.claude/rules/encoding-database.md` |
| 6813 | H3 | Group 4 - Core Helpers | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 6875 | H3 | Group 5 - LLM Integration Layer | `.claude/rules/llm-chat-streaming.md` |
| 6886 | H3 | Group 6 - Shiny Modules | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 6889 | H4 | Chat and messaging | `.claude/rules/llm-chat-streaming.md` |
| 6899 | H4 | Files and media | `.claude/rules/files-storage.md` |
| 6908 | H4 | Settings | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 6915 | H4 | AI / audio / character experience | `.claude/rules/speech-media.md` |
| 6923 | H4 | Identity / session / startup / Bilge Yolaç | `.claude/rules/security-identity.md` |
| 6936 | H4 | Analysis | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 6939 | H4 | Support | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 6947 | H4 | Admin | `.claude/rules/admin-health.md` |
| 6973 | H3 | Group 7 - Server-side Handlers and Observers | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7010 | H2 | UI Structure | `.claude/rules/frontend-ui.md` |
| 7014 | H3 | Main navigation | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7032 | H3 | UI assets | `.claude/rules/frontend-ui.md` |
| 7045 | H3 | Important static directories | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7055 | H2 | Server Flow | `.claude/rules/runtime-architecture.md` |
| 7061 | H3 | Current server initialization helper layer | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7099 | H3 | SSO behavior | `.claude/rules/security-identity.md` |
| 7102 | H4 | Local development | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7109 | H4 | Production / VM / Keycloak | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7120 | H3 | SSO JWT signature and fail-closed authorization boundary | `.claude/rules/security-identity.md` |
| 7145 | H4 | Windows VM / SSO / SQL Server Encoding Guardrails | `.claude/rules/encoding-database.md` |
| 7172 | H2 | Major Functional Systems | `CLAUDE.md` or the closest scoped rule (see rationale) |
| 7174 | H2 | 1) Welcome Screen and Quick Actions | `.claude/rules/frontend-ui.md` |
| 7217 | H2 | 2) Character / Persona System | `.claude/rules/speech-media.md` |
| 7243 | H3 | Default | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7246 | H3 | Helpers (single source of truth) | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7251 | H3 | Migration | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7256 | H3 | Practical note | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7268 | H2 | 3) Chat / LLM Pipeline | `.claude/rules/llm-chat-streaming.md` |
| 7289 | H3 | Critical pattern | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7315 | H3 | Worker payload snapshot contract | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7325 | H2 | 4) File Storage and Indexing | `.claude/rules/files-storage.md` |
| 7346 | H3 | Important paths | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7354 | H3 | Key helpers | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7363 | H3 | Practical behavior | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7382 | H2 | 5) Support Pages | `.claude/rules/frontend-ui.md` |
| 7393 | H3 | Knowledge base | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7402 | H3 | Version history | `.claude/rules/docs-operations.md` |
| 7409 | H2 | 6) AI Expert | `.claude/rules/speech-media.md` |
| 7427 | H3 | Important prompt sources | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7436 | H3 | Important behavior constraints | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7452 | H2 | 7) TTS / STT / Music | `.claude/rules/speech-media.md` |
| 7485 | H2 | 8) Bilge Yolaç (Claude Code Integration) | `.claude/rules/bilge-yolac.md` |
| 7551 | H3 | Document extraction and download flow | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7570 | H3 | bilge_yolac_downloads/ directory | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7580 | H3 | Model tiers | `.claude/rules/llm-chat-streaming.md` |
| 7587 | H3 | Streaming notes | `.claude/rules/llm-chat-streaming.md` |
| 7603 | H3 | Streaming stop/cancel regression boundary | `.claude/rules/llm-chat-streaming.md` |
| 7613 | H3 | Bilge Yolaç Plugin Subsystem | `.claude/rules/bilge-yolac.md` |
| 7617 | H4 | Plugin architecture files | `.claude/rules/files-storage.md` |
| 7624 | H4 | Plugin directory layout | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7639 | H4 | Recognized component directories | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7655 | H4 | Current plugin roster (15 plugins) | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7681 | H4 | Office plugin template framework | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7696 | H4 | Plugin panel UI behavior | `.claude/rules/frontend-ui.md` |
| 7708 | H2 | 9) SSO | `.claude/rules/security-identity.md` |
| 7722 | H3 | Practical rule | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7734 | H2 | 10) Admin / Analytics | `.claude/rules/admin-health.md` |
| 7759 | H2 | Worker Monitoring and Async Task Tracking | `.claude/rules/runtime-architecture.md` |
| 7763 | H3 | What these metrics mean | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7772 | H3 | Source files | `.claude/rules/files-storage.md` |
| 7776 | H3 | Operational rule | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7823 | H3 | Current tracked async families | `.claude/rules/runtime-architecture.md` |
| 7835 | H2 | Front-End Structure Notes | `CLAUDE.md` or the closest scoped rule (see rationale) |
| 7837 | H2 | CSS | `.claude/rules/frontend-ui.md` |
| 7853 | H2 | JS | `.claude/rules/frontend-ui.md` |
| 7866 | H3 | Practical rule | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7871 | H2 | Current User-Facing Pages and What They Mean | `.claude/rules/frontend-ui.md` |
| 7873 | H3 | `chat` | `.claude/rules/llm-chat-streaming.md` |
| 7891 | H3 | `history` | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7894 | H3 | `saved_chats` | `.claude/rules/llm-chat-streaming.md` |
| 7897 | H3 | `image_gallery` | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7900 | H3 | `claude_code` | `.claude/rules/bilge-yolac.md` |
| 7903 | H3 | `files` | `.claude/rules/files-storage.md` |
| 7906 | H3 | `settings_kisisel` | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7909 | H3 | `settings_yapilandirma` | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7912 | H3 | `destek_yardim` | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7915 | H3 | `destek_geri_bildirim` | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7918 | H3 | `destek_surum` | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7921 | H3 | `destek_hakkinda` | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7924 | H3 | `health` | `.claude/rules/admin-health.md` |
| 7929 | H2 | Repo-Specific Working Preferences | `CLAUDE.md` |
| 7933 | H3 | Prefer: | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7941 | H3 | Avoid: | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7948 | H3 | `server.R` editing rule | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 7972 | H2 | Sensitive / Regression-Prone Areas | `CLAUDE.md` or the closest scoped rule (see rationale) |
| 7976 | H3 | 1) Encoding and mojibake | `.claude/rules/encoding-database.md` |
| 7987 | H3 | 2) Welcome screen layout | `.claude/rules/frontend-ui.md` |
| 7999 | H3 | 2A) Modern welcome frontend ownership | `.claude/rules/frontend-ui.md` |
| 8016 | H3 | 3) Audio concurrency | `.claude/rules/speech-media.md` |
| 8026 | H3 | 4) File indexing and display names | `.claude/rules/files-storage.md` |
| 8036 | H3 | 5) Quick-action tool switching | `.claude/rules/llm-chat-streaming.md` |
| 8039 | H3 | 5A) Quick-action intro message behavior | `.claude/rules/llm-chat-streaming.md` |
| 8049 | H3 | 6) Saved-chat restore | `.claude/rules/llm-chat-streaming.md` |
| 8052 | H3 | 6A) Welcome recency invariants | `.claude/rules/frontend-ui.md` |
| 8057 | H3 | 6B) Saved-chat state freshness regressions | `.claude/rules/llm-chat-streaming.md` |
| 8060 | H3 | 7) Streaming handlers | `.claude/rules/llm-chat-streaming.md` |
| 8063 | H3 | 8) Async worker dependency export | `.claude/rules/runtime-architecture.md` |
| 8073 | H3 | 8A) Startup guards must match their execution context | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 8082 | H3 | 8B) Path helper edge cases | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 8088 | H3 | 8C) ServerRuntimeContext and identity/cache drift | `.claude/rules/security-identity.md` |
| 8097 | H2 | If You Add or Change a Module | `CLAUDE.md` or the closest scoped rule (see rationale) |
| 8112 | H2 | If You Touch DB Logic | `.claude/rules/encoding-database.md` |
| 8124 | H2 | If You Touch `ai_rehber.md` | `CLAUDE.md` or the closest scoped rule (see rationale) |
| 8137 | H2 | If You Touch `version_history.md` | `CLAUDE.md` or the closest scoped rule (see rationale) |
| 8147 | H2 | If You Touch `www/js/claude_code_streaming.js` | `.claude/rules/frontend-ui.md` |
| 8163 | H2 | Minimal Local Run Instructions | `.claude/rules/docs-operations.md` |
| 8175 | H2 | Recommended Validation After a Patch | `.claude/rules/testing-validation.md` |
| 8177 | H3 | Evidence hierarchy for Codex/cloud versus VM validation | `.claude/rules/testing-validation.md` |
| 8187 | H3 | Core | `docs/maintainers/claude-code-full-contract-reference.md` (reference-only unless covered by a scoped rule) |
| 8193 | H3 | Encoding | `.claude/rules/encoding-database.md` |
| 8198 | H3 | Files | `.claude/rules/files-storage.md` |
| 8203 | H3 | Chat | `.claude/rules/llm-chat-streaming.md` |
| 8210 | H3 | Unit tests (helper / decision-logic changes) | `.claude/rules/testing-validation.md` |
| 8240 | H3 | Behavioral test coverage expansion notes | `.claude/rules/testing-validation.md` |
| 8249 | H3 | Focused behavioral regression coverage | `.claude/rules/testing-validation.md` |
| 8275 | H3 | Module and runtime-helper behavioral coverage batch (module/UI/pure-helper expansion) | `.claude/rules/runtime-architecture.md` |
| 8298 | H3 | AI Expert speech and pronunciation contract | `.claude/rules/speech-media.md` |
| 8305 | H3 | AI Expert TTS chunking helper boundary | `.claude/rules/speech-media.md` |
| 8311 | H3 | AI Expert handler pure-decision support boundary | `.claude/rules/speech-media.md` |
| 8317 | H3 | AI Expert / TTS async dispatch and idle-talk priority contract | `.claude/rules/runtime-architecture.md` |
| 8326 | H3 | Hybrid VoxCPM2 speech assets and locked persona voice contract | `.claude/rules/llm-chat-streaming.md` |
| 8354 | H3 | Audio | `.claude/rules/speech-media.md` |
| 8359 | H3 | Bilge Yolaç | `.claude/rules/bilge-yolac.md` |
| 8365 | H3 | SSO-sensitive logic | `.claude/rules/security-identity.md` |
| 8370 | H2 | Key Files to Read First | `CLAUDE.md` |
| 8397 | H2 | Current Product Version Reference | `CLAUDE.md` or the closest scoped rule (see rationale) |
| 8408 | H2 | Final Guidance for Coding Agents | `CLAUDE.md` |

## Review rule

A scoped rule may intentionally summarize several historical paragraphs, but it must preserve the operative constraint. If a reviewer cannot prove that a subtle rule is represented in the new live instruction set, keep or restore it rather than deleting it. The archive is evidence, not a substitute for a necessary live rule.

# CLAUDE.md - MERGEN Bilge Codebase Guide

## Purpose of This File

This document is the operational guide for coding agents working inside the **MERGEN Bilge** repository. It explains how the application is structured, how it boots, which files are critical, which areas are fragile, and what repo-specific working style must be followed.

The repository is an R/Shiny application with a dark-theme, multimedia-heavy, Turkish-first user experience. It includes:

- conversational AI,
- file upload and analysis,
- MCP-enabled workflows,
- TTS and STT,
- AI Expert proactive guidance,
- support and version history pages,
- a web-wrapped Claude Code experience named **Bilge Yolaç**,
- SSO-ready deployment for VM/enterprise environments.

This file should be read before touching the code.

---

## Non-Negotiable Repo Rules

### 1) Preserve Turkish text integrity
This project is extremely sensitive to encoding regressions.

Always assume:

- files must remain UTF-8,
- Turkish characters must not be Latinized,
- any “simple cleanup” can accidentally introduce mojibake on VM/SSO flows.

If you touch file reading, file writing, `.Renviron`, DB writes, JSON writes, or browser-rendered text, be extra careful.

### 2) Comments added to code must be in Turkish
If you add comments in code, write them in Turkish.

### 3) Prefer surgical changes
Do not perform wide refactors unless the user explicitly asks for them.

Preferred style:

- smallest safe patch,
- minimal file churn,
- minimal new abstractions,
- preserve existing naming and structure.

### 4) Do not create unnecessary new files
This repo already has a lot of modules. New files should only be introduced when there is a clear benefit and the sourcing order in `global.R` is updated correctly.

### 5) Respect the project’s modular load order
A new helper/module is not “done” unless:

- it is placed in the correct layer,
- it is sourced in `global.R`,
- dependencies are loaded before it,
- `ui.R` / `server.R` wiring is updated where necessary.

### 6) When the user asks for exact patches, be exact
The user often wants:

- full replacement blocks,
- precise before/after snippets,
- exact file names,
- exact insertion locations,
- concrete testing instructions.

Do not answer vaguely.

### 7) Preserve existing UX wording
User-facing strings are mostly Turkish and intentionally stylized. Avoid rewriting labels unless required.

---

## What MERGEN Bilge Is

**MERGEN Bilge** is a Turkish-language AI assistant platform built on **Shiny** and **shinydashboard** for internal/corporate usage.

It combines:

- AI chat,
- conversation history and saved chats,
- file upload / preview / context injection,
- image generation,
- summarization,
- project/resource analysis,
- process guidance,
- character-based personas,
- AI Expert proactive speech,
- TTS/STT,
- support center,
- analytics/admin screens,
- version history,
- and a separate coding workspace called **Bilge Yolaç**.

The application is designed for a polished, immersive experience:

- cinematic startup,
- welcome screen,
- dynamic greeting,
- mythological character system,
- dark theme,
- audio and animation layers.

---

## High-Level Boot Flow

### Entry point: `app.R`
`app.R` is the real entry point and must be treated as special.

It does the following:

1. defines `safe_source()` before anything else,
2. loads `global.R`,
3. loads `ui.R`,
4. loads `server.R`,
5. registers `www/` subdirectories with `addResourcePath()`,
6. registers `www/` root under the `img` prefix,
7. starts the app with `runApp(shinyApp(ui, server), ...)`.

### Why `app.R` matters
This repo intentionally avoids relying on plain `runApp(".")` logic inside the app because:

- Windows VM path behavior is fragile,
- `Ctrl+Enter` execution is used in practice,
- static asset resolution can break if resource paths are not explicitly registered.

If startup or missing asset issues appear, check `app.R` first.

---

## Encoding and Safe Sourcing

Both `app.R` and `global.R` define `safe_source()`.

This function:

- tries standard `source(..., encoding = "UTF-8")`,
- falls back to raw-byte reading,
- tries decoding with `UTF-8`, `WINDOWS-1254`, and `latin1`,
- parses text manually,
- evaluates expressions into the target environment.

This is not accidental duplication. It exists because this codebase has had real encoding sensitivity, especially on Windows and SSO-enabled VM environments.

### Practical rule
If you add a new R file, it should be source-safe and UTF-8 safe.

---

## Required Environment Variables

The application validates required environment variables in `R/config_file_store.R`.

These are mandatory:

- `LOCAL_LLM_ENDPOINT`
- `DB_DSN`
- `AI_KEYS_MASTER`

If one is missing, startup stops with an explicit error.

### Important optional environment groups

#### Database
- `DB_DSN`
- `DB_DSN_2`
- `DB_DSN_3`
- `DB_CLIENT_ENCODING`
- `DB_NAME_ENCODING`

#### LLM
- `LOCAL_LLM_ENDPOINT`
- `LOCAL_LLM_API_KEY`
- `LOCAL_LLM_ENDPOINT_ALT`
- `LOCAL_LLM_ENDPOINT_ALT_API_KEY`
- `FILTER_MODEL`
- `AI_EXPERT_MODEL`
- `DESTEK_CHATBOT_MODEL`

#### TTS
- `LOCAL_TTS_ENDPOINT`
- `LOCAL_TTS_API_KEY`
- `LOCAL_TTS_MODEL`
- `LOCAL_TTS_VOICE`
- `LOCAL_TTS_TIMEOUT`
- `LOCAL_TTS_VERIFY_SSL`

#### STT
- `LOCAL_STT_ENDPOINT`
- `LOCAL_STT_MODEL`

#### SSO / Keycloak
- `SSO_ENABLED`
- `SSO_KEYCLOAK_URL`
- `SSO_REALM`
- `SSO_CLIENT_ID`
- `SSO_VALIDATE_ISSUER`
- `SSO_VALIDATE_EXPIRY`
- `SSO_TOKEN_REFRESH_MARGIN`
- `SSO_DEBUG`

#### Bilge Yolaç / Claude Code
- `CLAUDE_CODE_CLI_PATH`
- `CLAUDE_CODE_DEFAULT_WORKDIR`
- `CLAUDE_CODE_TIMEOUT`
- `CLAUDE_CODE_MODEL`
- `CLAUDE_CODE_MAX_CONCURRENT`
- `CLAUDE_CODE_PERSIST_SESSIONS`

#### Bilge Yolaç Plugins
- `CLAUDE_CODE_PLUGINS_MARKETPLACE_URL`
- `CLAUDE_CODE_PLUGINS_REFRESH_INTERVAL`
- `CLAUDE_CODE_PLUGINS_ALLOW_TOGGLE`
- `CLAUDE_CODE_PLUGINS_ALLOW_INSTALL`
- `CLAUDE_CODE_PLUGINS_ALLOW_UNINSTALL`
- `CLAUDE_CODE_PLUGINS_OPERATION_TIMEOUT`

#### Image generation
- `IMAGE_GEN_ENDPOINT`
- `IMAGE_GEN_MODEL`
- `IMAGE_GEN_TIMEOUT`
- `TRANSLATION_MODEL`

#### Service desk
- `SERVICE_DESK_API_KEY_URL`
- `SERVICE_DESK_RATE_LIMIT_URL`

#### File storage
- `MCP_FILES_BASE`

---

## Real Architecture

## Root-Level Files

- `app.R` - startup entry point, safe sourcing, resource path registration, app launch
- `global.R` - global options, locale handling, dependency sourcing order
- `ui.R` - full `shinydashboard` UI composition
- `server.R` - main server wiring and session flow
- `welcome_screen.R` - welcome screen data and quick action definitions
- `version_history.md` - source of the Yenilikler / version history page
- `README.md` - repository overview
- `CLAUDE.md` - coding-agent guide
- `ai_rehber.md` - knowledge base for Support chatbot and AI Expert reference

---

## `global.R` Load Order

The sourcing order in `global.R` is critical and should be respected.

### Group 1 - Foundation
Loaded first, no application-layer assumptions:

- `R/config_packages.R`
- `R/utils_common.R`
- `R/config_logging.R`
- `R/utils_rate_limiter.R`
- `R/utils_path_helpers.R`
- `R/utils_file_index.R`
- `R/utils_excel_reader.R`

### Group 2 - Configuration
Defines application-wide configuration:

- `R/config_sso.R`
- `R/config_file_store.R`
- `R/config_characters.R`
- `R/config_version_history.R`
- `R/config_api.R`
- `R/config_claude_code.R`
- `R/config_claude_code_plugins.R`

### Group 3 - Database and SQL
Core persistence and DB access:

- `R/helpers_database.R`
- `R/library_queries.R`
- `R/config_sql_loader.R`

### Group 4 - Core Helpers
Shared utilities used across modules:

- `R/helpers_language.R`
- `R/helpers_messaging.R`
- `R/helpers_mcp_tools.R`
- `R/helpers_chartlab.R`
- `R/helpers_image_gallery.R`
- `R/helpers_preview.R`
- `R/helpers_file_pipeline.R`
- `R/helpers_files.R`
- `R/helpers_chat_runtime.R`
- `R/helpers_summarization_modes.R`
- `R/helpers_summarization_prompts.R`
- `R/helpers_followup_questions.R`
- `R/helpers_deep_analysis.R`
- `R/helpers_sso.R`
- `R/helpers_destek_database.R`
- `R/helpers_admin_analytics.R`
- `R/helpers_ai_expert.R`
- `R/helpers_claude_code.R`
- `R/helpers_claude_code_streaming.R`
- `R/helpers_claude_code_formatters.R`
- `R/helpers_claude_code_plugins.R`

### Group 5 - LLM Integration Layer
Model calls, tool formatting, SSE, worker execution:

- `R/helpers_llm_tool_formatters.R`
- `R/helpers_llm_response_postprocess.R`
- `R/helpers_llm_api.R`
- `R/helpers_llm_sse.R`
- `R/helpers_llm_worker.R`

### Group 6 - Shiny Modules
User-facing and system-facing modules.

#### Chat and messaging
- `R/module_chat_history.R`
- `R/module_saved_chats.R`
- `R/module_message_search.R`
- `R/module_chat_search.R`
- `R/module_followup_questions.R`
- `R/module_chat_actions.R`
- `R/module_chat_export.R`
- `R/module_feedback.R`

#### Files and media
- `R/module_file_manager.R`
- `R/module_file_preview.R`
- `R/module_image_generation.R`
- `R/module_image_gallery.R`
- `R/module_summarization.R`

#### Settings
- `R/module_settings_kisisel.R`
- `R/module_settings_yapilandirma.R`
- `R/module_settings.R`
- `R/module_api_key.R`

#### AI / audio / character experience
- `R/module_ai_processing.R`
- `R/module_ai_expert.R`
- `R/module_tts.R`
- `R/module_tts_visualizer.R`
- `R/module_stt.R`
- `R/module_character_video.R`

#### Identity / session / startup / Bilge Yolaç
- `R/module_sso.R`
- `R/module_session_timeout.R`
- `R/module_performance.R`
- `R/module_user_identity.R`
- `R/module_startup_screen.R`
- `R/module_quick_actions.R`
- `R/module_claude_code_klasor.R`
- `R/module_claude_code_akis.R`
- `R/module_claude_code_plugins.R`
- `R/module_claude_code.R`

#### Analysis
- `R/module_proje_kaynak_analizi.R`

#### Support
- `R/module_destek_yardim.R`
- `R/module_destek_hakkinda.R`
- `R/module_destek_surum.R`
- `R/module_destek_hata_bildir.R`
- `R/module_destek_geri_bildirim.R`
- `R/module_destek.R`

#### Admin
- `R/module_admin_genel_bakis.R`
- `R/module_admin_kullanici_analizi.R`
- `R/module_admin_yz_performans.R`
- `R/module_admin_geri_bildirim_genel.R`
- `R/module_admin_sohbet_kalitesi.R`
- `R/module_admin_zaman_analizi.R`
- `R/module_admin_gelismis_analizler.R`
- `R/module_admin_analytics.R`
- `R/module_admin_geri_bildirim.R`
- `R/module_admin_hata_analizi.R`
- `R/module_admin_yanit_analizi.R`
- `R/module_health.R`
- `R/module_chartlab.R`

### Group 7 - Server-side Handlers and Observers
Wiring and runtime flow:

- `R/server_session_cache.R`
- `R/server_outputs_chat.R`
- `R/server_llm_response_handlers.R`
- `R/server_handler_summarization.R`
- `R/server_handler_image_generation.R`
- `R/server_handler_true_streaming.R`
- `R/server_send_message.R`
- `R/server_tts_handlers.R`
- `R/server_music_handlers.R`
- `R/server_ai_expert_handlers.R`
- `welcome_screen.R`
- `R/welcome_screen_modern.R`
- `R/server_welcome_handlers.R`
- `R/server_observers_settings.R`
- `R/server_observers_storage.R`
- `R/server_observers_files.R`
- `R/server_observers_saved_chats.R`
- `R/server_observers_image_gallery.R`
- `R/server_observers_chat_ui.R`
- `R/server_observers_navigation.R`
- `R/server_observers_file_clicks.R`
- `R/server_observers_startup.R`
- `R/server_observers_chat_input.R`
- `R/server_observers_misc.R`
- `R/server_outputs_downloads.R`

---

## UI Structure

`ui.R` defines the main sidebar and tab structure.

### Main navigation
- `Ana Söyleşi`
- `Söyleşi Yönetimi`
  - `Söyleşi Geçmişi`
  - `Kayıtlı Söyleşiler`
  - `Görsel Galerisi`
- `Bilge Yolaç`
- `Dosya Yönetimi`
- `Ayarlar`
  - `Kişiselleştirme`
  - `Yapılandırma`
- `Destek`
  - `Yardım Merkezi`
  - `Geri Bildirim & Hata`
  - `Yenilikler`
  - `Hakkında`
- dynamic admin menu for authorized users

### UI assets
The UI loads a large amount of static assets from `www/`:

- CSS themes
- JS handlers
- CodeMirror bundles
- Three.js files
- support page assets
- SSO assets
- Bilge Yolaç assets
- welcome screen assets
- TTS/STT/music scripts

### Important static directories
- `www/css/`
- `www/js/`
- `www/codemirror/`
- `www/lib/`
- `www/characters/`
- root files under `www/` exposed via `/img/...`

---

## Server Flow

`server.R` is the main integration point.

At a high level it performs:

1. session cache initialization,
2. SSO/local auth setup,
3. API key module wiring,
4. performance and health module startup,
5. support module startup,
6. settings initialization,
7. Bilge Yolaç startup,
8. media stack initialization,
9. file manager / preview wiring,
10. chat state initialization,
11. observers and navigation,
12. welcome handlers,
13. gallery / saved chat / history wiring,
14. chat engine / LLM response pipeline,
15. TTS handlers,
16. final `send_message` function registration.

### SSO behavior
The application supports two auth flows:

#### Local development
When `SSO_ENABLED=FALSE`:

- `resolveUserIdentity()` derives the local/system identity,
- `get_or_create_user()` ensures DB user presence,
- session user data is populated synchronously.

#### Production / VM / Keycloak
When `SSO_ENABLED=TRUE`:

- `ssoAuthServer()` validates token flow,
- session starts with temporary user placeholders,
- once authenticated, Keycloak claims are mapped,
- DB user is created/updated,
- session becomes fully initialized.

If anything “works locally but not on VM”, SSO and encoding are the first things to inspect.

---

## Major Functional Systems

## 1) Welcome Screen and Quick Actions

`welcome_screen.R` defines `MAIN_ACTIONS_DATA`.

Current quick actions:

- `Süreç Yönetimi Sistemi`
- `Uygulama Uzmanı`
- `Proje ve Kaynak Analizi`
- `Excel Analizi`
- `Görsel Oluşturma`
- `Kodlama Desteği`
- `Özetleme Desteği`

Each action includes:

- id
- title
- seed message
- description
- icon
- theme color
- model value

### Important rule
Quick actions are not just decorative. They are tied to:

- prompt injection,
- tool-family behavior,
- model switching,
- context preparation.

Treat quick-action logic as behavioral infrastructure.

---

## 2) Character System

Characters are defined in `R/config_characters.R`.

Current roster:

- `Mergen`
- `Ülgen`
- `Kayra`
- `Erlik`
- `Umay Ana`

Each character includes:

- id
- display labels
- avatar path
- image path
- accent colors
- lore
- style description
- profile metrics
- signature moves
- system prompt
- TTS voice

### Default
`Mergen` is the default style.

### Practical note
Many visual and behavioral systems depend on the selected character:

- welcome visuals,
- accent colors,
- AI Expert tone,
- character videos,
- Bilge Yolaç thinking flavor,
- TTS voice defaults.

---

## 3) Chat / LLM Pipeline

Core files:

- `R/server_send_message.R`
- `R/helpers_llm_api.R`
- `R/helpers_llm_worker.R`
- `R/helpers_llm_sse.R`
- `R/server_llm_response_handlers.R`
- `R/helpers_chat_runtime.R`

Key behaviors:

- user message capture,
- background worker execution,
- optional MCP tool usage,
- response streaming,
- message persistence,
- follow-up suggestion generation,
- optional TTS attachment.

### Critical pattern
Never pass live reactive objects into workers.

Always capture plain values first.

Correct pattern:

```r
chat_id <- isolate(rv$current_chat_id)
user_id <- isolate(rv$user_id)

future({
  some_worker(chat_id, user_id)
})
```

Incorrect pattern:

```r
future({
  some_worker(rv$current_chat_id, rv$user_id)
})
```

This repo is highly sensitive to reactive-scope mistakes.

---

## 4) File Storage and Indexing

Core file: `R/config_file_store.R`

This subsystem provides:

- shared file root,
- persistent upload dir,
- MCP base dir support,
- JSON index,
- per-user buckets,
- registration and resolution helpers,
- stale index cleanup,
- filesystem fallback listing,
- periodic garbage collection.

### Important paths
- `MERGEN_FILES_ROOT`
- `MERGEN_UPLOADS_DIR`
- `MERGEN_MCP_BASE_DIR`
- `MERGEN_INDEX_PATH`

### Key helpers
- `mergen_register_uploaded_file()`
- `global_register_file()`
- `resolve_uploaded_file()`
- `mergen_user_upload_dir()`
- `mergen_list_user_files()`
- `mergen_remove_from_index()`
- `mergen_clear_user_bucket()`

### Practical behavior
Physical file names may be timestamped/uniquified, while user-facing display names are preserved in the index.

If the UI shows the wrong filename or files disappear after refresh, investigate:

- index write path,
- display-name persistence,
- user bucket resolution,
- filesystem fallback listing,
- encoding at JSON write/read boundaries.

---

## 5) Support Pages

Support area is coordinated by `R/module_destek.R`.

Subpages:

- `Yardım Merkezi` - `R/module_destek_yardim.R`
- `Geri Bildirim & Hata` - `R/module_destek_geri_bildirim.R` and `R/module_destek_hata_bildir.R`
- `Yenilikler` - `R/module_destek_surum.R`
- `Hakkında` - `R/module_destek_hakkinda.R`

### Knowledge base
`ai_rehber.md` is used as the help knowledge base and as AI Expert reference material.

This means changes to `ai_rehber.md` directly affect:

- support chatbot answers,
- AI Expert guidance quality,
- in-app help consistency.

### Version history
`version_history.md` is parsed by `R/config_version_history.R` and rendered by `R/module_destek_surum.R`.

If Yenilikler content is wrong, check `version_history.md` first.

---

## 6) AI Expert

Core files:

- `R/helpers_ai_expert.R`
- `R/module_ai_expert.R`
- `R/server_ai_expert_handlers.R`
- `ai_rehber.md`

AI Expert handles:

- greeting,
- page guidance,
- idle/proactive talk,
- character-aware phrasing,
- TTS-assisted speech,
- subtitle rendering.

### Important prompt sources
AI Expert system prompt is built from:

- selected character data,
- scenario type,
- current page context,
- user context from DB,
- `ai_rehber.md`.

### Important behavior constraints
AI Expert text is meant to be spoken aloud.

Therefore prompt rules emphasize:

- Turkish only,
- plain text,
- no emoji,
- no markdown,
- natural, smooth phrasing,
- no unusual Unicode decoration.

If output looks robotic or noisy, inspect `helpers_ai_expert.R` and `ai_rehber.md`.

---

## 7) TTS / STT / Music

Core files:

- `R/module_tts.R`
- `R/module_tts_visualizer.R`
- `R/server_tts_handlers.R`
- `R/module_stt.R`
- `R/server_music_handlers.R`

Related front-end files include:

- `www/js/tts_visualizer.js`
- `www/js/tts_manager.js`
- `www/js/stt_client.js`
- `www/js/music_manager.js`
- `www/css/tts_visualizer.css`
- `www/css/stt.css`

These systems interact with each other and are regression-prone.

Typical coupling areas:

- TTS audio + floating visualizer,
- STT modal + music pause/resume,
- background music + ducking,
- AI Expert speech + subtitles + TTS,
- navigation changes while audio is active.

Treat audio logic as concurrency-sensitive.

---

## 8) Bilge Yolaç (Claude Code Integration)

Core files:

- `R/config_claude_code.R`
- `R/config_claude_code_plugins.R`
- `R/helpers_claude_code.R`
- `R/helpers_claude_code_streaming.R`
- `R/helpers_claude_code_formatters.R`
- `R/helpers_claude_code_plugins.R`
- `R/module_claude_code.R`
- `R/module_claude_code_klasor.R`
- `R/module_claude_code_akis.R`
- `R/module_claude_code_plugins.R`
- `www/js/claude_code.js`
- `www/js/claude_code_streaming.js`
- `www/js/claude_code_plugins.js`
- `www/css/claude_code.css`
- `www/css/claude_code_streaming.css`
- `www/css/claude_code_plugins.css`
- Bilge Yolaç welcome JS files under `www/js/bilge_yolac_*.js`

Bilge Yolaç is a web wrapper around Claude Code CLI-like behavior.

It includes:

- folder browsing,
- workdir selection,
- model tiers,
- tool-use rendering,
- streaming shell/file activity,
- themed welcome/game experience,
- connection tests,
- scenario templates.

### Model tiers
Defined in `R/config_claude_code.R`:

- `Hızlı`
- `Dengeli`
- `Güçlü`

### Streaming notes
The streaming UI renders:

- shell commands,
- file operations,
- tool results,
- live assistant text.

This area is especially sensitive to:

- Unicode symbol handling,
- browser mojibake,
- incremental HTML rendering,
- shell block toggling,
- partial JSON parsing.

---

## 9) SSO

Core files:

- `R/config_sso.R`
- `R/helpers_sso.R`
- `R/module_sso.R`
- `www/js/sso_auth.js`
- `www/css/sso_auth.css`

SSO is Keycloak-based and controlled by the global `SSO_ENABLED` flag.

### Practical rule
If a bug appears only when `SSO_ENABLED=TRUE`, check:

- token claim extraction,
- encoding of claim text,
- auth-initialization timing,
- delayed session setup,
- user-specific file loading after auth.

---

## 10) Admin / Analytics

Main admin modules include:

- `R/module_admin_analytics.R`
- `R/module_admin_geri_bildirim.R`
- `R/module_admin_hata_analizi.R`
- `R/module_admin_yanit_analizi.R`
- helper modules in the admin family
- `R/helpers_admin_analytics.R`

Admin area includes:

- general analytics,
- feedback analytics,
- bug analytics,
- response feedback analytics,
- health monitoring.

This area is role-sensitive and should not accidentally leak into normal-user flow.

---

## Front-End Structure Notes

## CSS
Large number of page- and feature-specific styles live under `www/css/`.

Important families:

- welcome / intro
- layout / components
- chat messages / inputs
- file manager
- settings
- support
- admin analytics
- SSO
- Bilge Yolaç
- version history

## JS
Important families under `www/js/`:

- core app bootstrapping
- streaming manager
- input and interaction handlers
- chat / markdown / citations
- welcome animation / neural / greeting
- TTS / STT / music
- support page JS
- AI Expert manager
- Bilge Yolaç streaming and game assets

### Practical rule
If a UI feature looks broken but R code seems correct, inspect the paired JS/CSS files before patching server logic.

---

## Current User-Facing Pages and What They Mean

### `chat`
Main conversation page.

Contains:

- welcome screen placeholder,
- chat header,
- model display,
- message count,
- new/copy/export actions,
- chat container,
- file prompt indicator,
- textarea,
- drag-and-drop support,
- model selector,
- send / voice / file actions,
- contextual controls for image, summary, and analysis tools.

### `history`
Conversation history.

### `saved_chats`
Saved conversation management.

### `image_gallery`
Generated image gallery.

### `claude_code`
Bilge Yolaç.

### `files`
File upload, preview, file management.

### `settings_kisisel`
Character and mode personalization.

### `settings_yapilandirma`
Model, tools, UI preferences, voice and technical settings.

### `destek_yardim`
Support contact information and help chatbot.

### `destek_geri_bildirim`
Feedback and bug reporting.

### `destek_surum`
Version / release notes.

### `destek_hakkinda`
About page / user guide.

### `health`
Health monitor, admin-facing.

---

## Repo-Specific Working Preferences

This section reflects how work in this repo is usually requested.

### Prefer:
- exact patches,
- clear file-level scope,
- preserving existing architecture,
- Turkish comments if comments are added,
- no unnecessary code movement,
- concrete testing steps.

### Avoid:
- broad rewrites,
- “cleanup” refactors without approval,
- renaming stable identifiers casually,
- introducing English comments into Turkish-heavy files,
- changing visible labels unless needed.

---

## Sensitive / Regression-Prone Areas

These areas have produced regressions recently or are structurally fragile. Treat them carefully.

### 1) Encoding and mojibake
Especially sensitive in:

- VM deployments,
- SSO-enabled sessions,
- streamed text,
- DB reads/writes,
- JSON index files,
- Bilge Yolaç incremental rendering,
- support/version-history content.

### 2) Welcome screen layout
Sensitive interactions exist between:

- hidden chat header,
- fullscreen welcome wrapper,
- neural animation,
- greeting overlay,
- intro state,
- modern welcome CSS.

A small CSS change can break the top alignment or shift multiple panels.

### 3) Audio concurrency
Sensitive interactions between:

- TTS,
- STT,
- background music,
- character music,
- AI Expert speech,
- page navigation.

### 4) File indexing and display names
Be careful with:

- timestamped storage names vs display names,
- index rehydration,
- Excel persistence after restart,
- user-bucket scanning.

### 5) Quick-action tool switching
Quick actions are tied to model/tool behavior. Regressions can make a tool appear active while another tool-family actually handles the request.

### 6) Saved-chat restore
Loading a saved chat can accidentally route the user back into a stale welcome state if observers are wired incorrectly.

### 7) Streaming handlers
The chat stream and Bilge Yolaç stream both have fragile incremental rendering paths. Small output-format changes can break UI rendering.

---

## If You Add or Change a Module

Follow this checklist:

1. Put the file in the correct layer.
2. Add `safe_source()` entry in the correct `global.R` group.
3. Update `ui.R` if the module has UI.
4. Update `server.R` wiring if the module has server logic.
5. Verify namespace consistency.
6. Verify Turkish strings remain UTF-8 safe.
7. Test both local mode and, if relevant, SSO-sensitive flow assumptions.

---

## If You Touch DB Logic

Remember:

- worker-safe patterns only,
- no pool object serialization into futures,
- capture reactivity before background execution,
- keep Turkish text encoding safe,
- check how user creation and authorization behave under SSO.

---

## If You Touch `ai_rehber.md`

Understand the impact:

- support chatbot quality changes,
- AI Expert prompt context changes,
- page guidance behavior changes,
- help-page consistency changes.

This file is not passive documentation. It is live prompt context.

---

## If You Touch `version_history.md`

Understand the impact:

- Yenilikler page content changes,
- current version display changes,
- support/about references may need alignment.

---

## If You Touch `www/js/claude_code_streaming.js`

Be especially careful with:

- Unicode symbols,
- emoji-like icons,
- mojibake risk on VM,
- incremental text assembly,
- shell visibility toggles,
- HTML escaping,
- copy/paste fidelity.

Prefer Unicode escape sequences over literal emoji if browser/VM rendering is unstable.

---

## Minimal Local Run Instructions

Typical local flow:

1. configure `.Renviron`,
2. open the project in R,
3. run `app.R` directly.

Do not assume a plain `runApp(".")` workflow is the safest path for this repo.

---

## Recommended Validation After a Patch

After changing anything non-trivial, test:

### Core
- app starts,
- sidebar loads,
- welcome screen appears,
- chat page is usable.

### Encoding
- Turkish labels display correctly,
- streamed assistant text displays correctly,
- support/version content displays correctly.

### Files
- upload works,
- file appears with correct visible name,
- refresh/reopen behavior still works.

### Chat
- send message,
- stream response,
- follow-up actions render,
- export/copy still works.

### Audio
- TTS still plays,
- STT modal still opens,
- music does not overlap incorrectly.

### Bilge Yolaç
- page loads,
- scenario buttons work,
- stream blocks render,
- special icons/text do not mojibake.

### SSO-sensitive logic
If relevant to your change, verify assumptions for `SSO_ENABLED=TRUE` paths, even if you cannot fully run Keycloak locally.

---

## Key Files to Read First

If you are new to the repo, read in this order:

1. `app.R`
2. `global.R`
3. `ui.R`
4. `server.R`
5. `welcome_screen.R`
6. `R/config_file_store.R`
7. `R/config_api.R`
8. `R/config_sso.R`
9. `R/config_characters.R`
10. `R/helpers_ai_expert.R`
11. `R/module_claude_code.R`
12. `R/module_destek_yardim.R`

---

## Current Product Version Reference

Current public version history file shows:

- `v1.0` - official launch
- previous `v0.9` - beta

If any document mentions older release framing only, update it.

---

## Final Guidance for Coding Agents

When in doubt:

- preserve Turkish,
- preserve structure,
- patch surgically,
- wire modules carefully,
- respect `global.R` load order,
- test encoding-sensitive paths,
- and do not treat `ai_rehber.md` or `version_history.md` as passive docs.

They are live product behavior inputs.

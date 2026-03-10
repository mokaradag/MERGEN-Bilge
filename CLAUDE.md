# CLAUDE.md - MERGEN-Bilge Codebase Guide

## Project Overview

**MERGEN-Bilge** is a sophisticated Turkish-language Shiny dashboard application that serves as an AI assistant with integrated conversation management, file handling, and data processing capabilities. The application is built with R and designed for enterprise deployment with multi-database support and extensive LLM integration.

### Core Capabilities
- **Interactive Conversations**: Chat interface with streaming responses, multiple language support, and code highlighting
- **Conversation Management**: Save, load, search, and bookmark conversation history
- **File Management**: Upload, process, and manage various file formats
- **Settings & Configuration**: User preferences, LLM model selection, voice settings (TTS/STT)
- **System Health Monitoring**: Real-time service status and logging
- **AI Integration**: LLM API calls with MCP (Model Context Protocol) tool support
- **Advanced Features**: Image generation, visual gallery, analytics, and custom project analysis
- **Support Pages (Destek)**: Help center with AI chatbot assistant (knowledge base: ai_rehber.md), feedback collection (satisfaction + NPS + tags), bug reporting with file attachments, and about page with app guide
- **Admin Feedback & Bug Analytics**: Dedicated admin pages for analyzing user feedback (satisfaction trends, NPS scoring, tag distribution) and bug reports (priority/category heatmap, attachment viewer, status management)

---

## Architecture & File Structure

### Root-Level Files
```
app.R                 # Application entry point - loads and starts the app
global.R              # Global configuration, package loading, and module sourcing
ui.R                  # User interface definition (shinydashboard layout)
server.R              # Main server function and session initialization
welcome_screen.R      # Welcome/login screen components
.Renviron             # Environment variables (DB connections, API keys, TTS/STT config)
Table Structure.txt   # Database schema documentation
```

### R/ Directory Structure

The R directory contains modular components organized by function:

#### Configuration Files (`config_*.R`)
- **`config_packages.R`**: Package dependencies and loading
- **`config_logging.R`**: Logging infrastructure setup
- **`config_characters.R`**: Character/persona definitions
- **`config_file_store.R`**: File storage and handling configuration
- **`config_sql_loader.R`**: SQL database loading configuration
- **`config_api.R`**: API configuration and endpoints

#### Helper Functions (`helpers_*.R`)
Core utilities and functions used throughout the application:
- **`helpers_database.R`**: Database connection management, worker-safe DB access patterns
- **`helpers_llm_api.R`**: LLM API request construction and handling
- **`helpers_llm_worker.R`**: Background worker execution for LLM calls with MCP tool support
- **`helpers_llm_tool_formatters.R`**: Tool schema formatting and response parsing
- **`helpers_chat_runtime.R`**: Chat execution flow and message processing
- **`helpers_language.R`**: Language utilities, translation, and text processing
- **`helpers_messaging.R`**: Message formatting and delivery
- **`helpers_mcp_tools.R`**: Model Context Protocol tool definitions and execution
- **`helpers_file_pipeline.R`**: File upload and processing pipeline
- **`helpers_files.R`**: File utilities and handling
- **`helpers_image_gallery.R`**: Image gallery operations
- **`helpers_chartlab.R`**: Chart/visualization specifications
- **`helpers_preview.R`**: File preview functionality
- **`helpers_followup_questions.R`**: Follow-up question generation
- **`helpers_summarization_modes.R`**: Summarization strategy definitions
- **`helpers_summarization_prompts.R`**: Prompt templates for summarization
- **`helpers_destek_database.R`**: Support page database operations (MB_Destek_Geri_Bildirim, MB_Destek_Hata_Bildir, status updates)
- **`helpers_admin_analytics.R`**: Shared utilities for admin analytics modules (metric cards, safe query, Turkish formatting, DT language, color palette)

#### Utility Functions (`utils_*.R`)
Low-level utilities:
- **`utils_common.R`**: Common operators and basic utilities (%||%, safe_nzchar, etc.)
- **`utils_path_helpers.R`**: Path normalization and Windows compatibility
- **`utils_file_index.R`**: Cached file indexing mechanism
- **`utils_excel_reader.R`**: Excel file parsing utilities
- **`utils_rate_limiter.R`**: Rate limiting and worker pool management

#### Modules (`module_*.R`)
Shiny modules for major UI sections and features:
- **`module_chat_history.R`**: Conversation history tab
- **`module_file_manager.R`**: File management tab
- **`module_saved_chats.R`**: Saved conversations feature
- **`module_settings.R`**: User settings and configuration
- **`module_tts.R`**: Text-to-speech implementation
- **`module_stt.R`**: Speech-to-text implementation
- **`module_api_key.R`**: API key management
- **`module_performance.R`**: Performance monitoring
- **`module_admin_analytics.R`**: Admin analytics dashboard (Genel Analiz - general system metrics, uses shared helpers)
- **`module_admin_geri_bildirim.R`**: Admin feedback analytics (Geri Bildirim Analizi - satisfaction, NPS, tag analysis with treemap, gauge, bubble charts)
- **`module_admin_hata_analizi.R`**: Admin bug report analytics (Hata Analizi - priority/category analysis, heatmap, attachment viewer, status management)
- **`module_admin_yanit_analizi.R`**: Admin AI response feedback analytics (Yanıt Geri Bildirimi Analizi - like/dislike analysis, model performance, tag analysis, time trends, polar charts)
- **`module_image_generation.R`**: Image generation features
- **`module_image_gallery.R`**: Image gallery display
- **`module_proje_kaynak_analizi.R`**: Project source analysis (Turkish-specific)
- **`module_chartlab.R`**: Chart specifications and visualization
- **`module_followup_questions.R`**: Auto-generated follow-up questions
- **`module_feedback.R`**: User feedback collection
- **`module_destek.R`**: Support page coordinator (Yardım Merkezi, Geri Bildirim & Hata, Hakkında)
- **`module_destek_yardim.R`**: Help center with contact information and AI chatbot assistant (uses ai_rehber.md as knowledge base, model configured via DESTEK_CHATBOT_MODEL in .Renviron)
- **`module_destek_geri_bildirim.R`**: Feedback form (satisfaction, NPS, tags, comments)
- **`module_destek_hata_bildir.R`**: Bug report form (topics, categories, priority, attachments)
- **`module_destek_hakkinda.R`**: About page with app features and page guide
- **`module_quick_actions.R`**: Quick action buttons
- **`module_message_search.R`**: Message search functionality
- **`module_chat_search.R`**: Chat history search
- **`module_user_identity.R`**: User identification and authentication
- **`module_session_timeout.R`**: Session timeout management
- **`module_file_preview.R`**: File preview in-app

#### Server Handlers (`server_*.R`)
Organized server-side logic split by functional area:
- **`server_send_message.R`**: Message sending pipeline
- **`server_llm_response_handlers.R`**: Processing LLM responses
- **`server_tts_handlers.R`**: Text-to-speech handler logic
- **`server_stt_handlers.R`**: Implicit speech-to-text handling (in STT module)
- **`server_observers_*.R`**: Reactive observers for specific UI elements
  - `chat_input.R`: Chat input and submission
  - `chat_ui.R`: Chat UI updates
  - `saved_chats.R`: Saved conversation management
  - `settings.R`: Settings changes
  - `files.R`: File operations
  - `file_clicks.R`: File interaction events
  - `image_gallery.R`: Gallery operations
  - `navigation.R`: Tab navigation
  - `storage.R`: Session storage
  - `startup.R`: Application startup
  - `misc.R`: Miscellaneous observers
- **`server_outputs_*.R`**: Shiny output renderers
  - `chat.R`: Chat message rendering
  - `downloads.R`: File download handlers
- **`server_session_cache.R`**: Session-level caching mechanisms
- **`server_music_handlers.R`**: Audio playback (if used)
- **`server_welcome_handlers.R`**: Welcome screen logic

#### Library & Queries
- **`library_queries.R`**: Pre-built SQL queries for common operations

### www/ Directory

Static assets:
```
www/
├── css/                # Stylesheets for UI theming and components
├── js/                 # JavaScript for interactive features
└── (CodeMirror, fonts, images managed here)
```

---

## Development Conventions & Patterns

### 1. File Naming Conventions

| Prefix | Purpose | Example |
|--------|---------|---------|
| `config_` | Configuration and setup | `config_api.R` |
| `helpers_` | Reusable utility functions | `helpers_database.R` |
| `utils_` | Low-level utilities | `utils_common.R` |
| `module_` | Shiny modules (UI + server) | `module_settings.R` |
| `server_` | Server-side logic | `server_send_message.R` |

### 2. Shiny Module Pattern

All Shiny modules follow this pattern:

```r
# UI Function
moduleNameUI <- function(id) {
  ns <- NS(id)
  # UI definition using ns() for namespacing
  tagList(...)
}

# Server Function
moduleNameServer <- function(id, reactive_inputs) {
  moduleServer(id, function(input, output, session) {
    # Reactive logic
  })
}
```

### 3. Encoding Convention

All files are sourced with explicit UTF-8 encoding in `global.R`:
```r
source("R/some_file.R", encoding = "UTF-8")
```
This is critical for Turkish character support (ç, ğ, ı, ö, ş, ü, etc.).

### 4. Database Access Pattern

Database helper functions are designed to be **worker-safe**:
- Main process captures reactive values BEFORE passing to `future()` workers
- Workers create fresh DB connections inside the worker process
- Never serialize pool/DBI external pointers into workers
- Always pass plain R values (strings, numbers) into futures, never reactive objects

Example pattern:
```r
# In main process
chat_id <- isolate(rv$current_chat_id)  # Capture reactive value
user_id <- isolate(rv$user_id)

# Pass primitives into future
future({
  worker_save_assistant_response(chat_id, user_id, response_text)
})
```

### 5. LLM Worker Pattern

The `call_llm_worker()` function handles LLM API calls with MCP tools support:
- Accepts chat history, settings, and API configuration
- Implements recursive tool calling (max depth: 5)
- Returns parsed response with optional tool schemas
- Handles streaming and non-streaming responses
- Formats tool calls according to LLM API specifications

### 6. Reactive Value Management

Session-level reactive values are stored in `session$userData`:
```r
session$userData$current_chat_id
session$userData$user_identity
session$userData$system_username
session$userData$current_session_files
```

Global assignment (<<-) is used sparingly for backward compatibility in single-user deployments.

### 7. MCP Tool Integration

Model Context Protocol tools are:
- Defined in `helpers_mcp_tools.R`
- Executed within `call_llm_worker()` recursion
- Return JSON-formatted results
- Support file operations, SQL queries, and custom actions

### 8. Character/Persona System

Character definitions are configured in `config_characters.R` with:
- Name, description, avatar image
- System prompt
- Optional video or special UI elements
- Settings for how the character should respond

---

## Environment Configuration (.Renviron)

The `.Renviron` file (in gitignore) contains:

### Database Configuration
```
DB_DSN="MainConnection"           # Primary database
DB_DSN_2="SecondaryConnection"    # Secondary database
DB_DSN_3="TertiaryConnection"     # Tertiary database
```

### LLM Configuration
```
LOCAL_LLM_ENDPOINT=https://endpoint/v1/chat/completions
LOCAL_LLM_API_KEY=<key>
FILTER_MODEL=<model-name>         # Optional filtering model
```

### Alternative LLM Endpoint
```
LOCAL_LLM_ENDPOINT_ALT=https://secondary-endpoint/v1/chat/completions
LOCAL_LLM_ENDPOINT_ALT_API_KEY=<secondary-key>
```

### Text-to-Speech (TTS) Configuration
```
LOCAL_TTS_ENDPOINT=https://endpoint/v1
LOCAL_TTS_MODEL=tts-1-hd
LOCAL_TTS_VOICE=tr-male-1
LOCAL_TTS_API_KEY=<key>           # Optional; primary key used if blank
LOCAL_TTS_VERIFY_SSL=TRUE         # Set to FALSE for self-signed certs
```

### Speech-to-Text (STT) Configuration
```
LOCAL_STT_ENDPOINT=http://localhost:8080/v1/audio/transcriptions
LOCAL_STT_MODEL=whisper-large-v3
LOCAL_STT_API_KEY=<key>
```

### Image Generation
```
IMAGE_GEN_ENDPOINT=https://endpoint/v1/images/generations
IMAGE_GEN_MODEL=dall-e-3
IMAGE_GEN_TIMEOUT=180             # Timeout in seconds
TRANSLATION_MODEL=<model-name>    # For prompt translation
```

### File Storage
```
MCP_FILES_BASE=//server/share/uploads  # UNC or local path for MCP file storage
```

### Destek Chatbot
```
DESTEK_CHATBOT_MODEL=<model-name>  # AI chatbot model for Help Center (falls back to AI_EXPERT_MODEL or FILTER_MODEL)
```

### Other
```
AI_KEYS_MASTER=<32+ char random secret>  # For encrypting stored API keys
```

---

## Key Concepts & Workflows

### 1. Chat Message Flow

1. User submits message in chat input
2. `server_observers_chat_input.R` captures input
3. `server_send_message.R` orchestrates the pipeline:
   - Validates input
   - Constructs chat history
   - Calls `call_llm_worker()` in background
   - Processes streaming response (if enabled)
   - Handles tool calls recursively
4. Response formatted and displayed via `server_outputs_chat.R`
5. Optional follow-up questions generated

### 2. File Processing Pipeline

1. File upload via `module_file_manager.R`
2. Stored in configured MCP_FILES_BASE directory
3. File index updated in `utils_file_index.R`
4. Preview generated (image, PDF, text, etc.)
5. File metadata indexed for search
6. Available for LLM context in subsequent messages

### 3. Conversation Saving/Loading

- Saved conversations stored in database
- Each conversation has:
  - Unique chat_id
  - User association
  - Full message history
  - Associated files/attachments
  - Metadata (created_at, updated_at, title)
- Can be searched via `module_chat_search.R`

### 4. Session Lifecycle

1. User login → `resolveUserIdentity()` authenticates
2. `get_or_create_user()` ensures DB entry
3. `sessionCacheInit()` sets up session-specific cache
4. User configuration loaded into `session$userData`
5. All modules initialized with session namespace
6. Session timeout managed by `module_session_timeout.R`

### 5. Background Processing

The application uses `future` and `promises` packages for:
- LLM API calls (non-blocking)
- Database operations (worker-safe)
- File processing (large files)
- Image generation (long-running)

Key pattern:
```r
future({
  # Worker code here - no access to session/reactives
  result <- worker_function(plain_values)
}) %...>%
  {
    # Promise continuation - back in main session
    updateUI(.)
  }
```

---

## Development Workflow

### Adding a New Feature/Module

1. **Identify the Feature Type**:
   - If it's a major UI section → Create `module_feature_name.R`
   - If it's supporting logic → Create `helpers_feature_name.R` or `server_handlers.R`
   - If it's low-level utilities → Create `utils_feature_name.R`

2. **Module Structure** (for UI features):
   ```r
   # Define UI
   featureNameUI <- function(id) {
     ns <- NS(id)
     # UI elements here
   }

   # Define Server
   featureNameServer <- function(id, ...) {
     moduleServer(id, function(input, output, session) {
       # Reactive logic here
     })
   }
   ```

3. **Register the Module**:
   - Add to `ui.R` in the appropriate tab/menu
   - Call server module in `server.R`
   - Add `source()` call to `global.R` if in R/ directory

4. **Add to Sidebar** (if needed):
   Edit `ui.R` `sidebarMenu` to add navigation item

5. **Test**:
   - Run `shiny::runApp()` locally
   - Test with UTF-8 characters
   - Verify database operations if applicable
   - Test with LLM calls if using AI features

### Modifying LLM Behavior

1. Locate relevant function in `helpers_llm_worker.R` or `server_send_message.R`
2. Understand the recursion depth and tool calling logic
3. Modify prompt/system message if needed
4. Test with actual LLM endpoint
5. Verify tool schemas parse correctly

### Adding Database Support

1. Define connection in `.Renviron` (new DB_DSN_*)
2. Create database target in `global.R` DB_TARGETS if needed
3. Add query in `library_queries.R`
4. Use `get_connection(target = "tertiary")` in helper function
5. Ensure worker-safety: pass values not connections

---

## Important Technical Details

### Character Encoding & Localization

- All R files use UTF-8 encoding
- Turkish locale set for LC_CTYPE support
- Special handling for Turkish characters in UI and database
- File names and paths normalized with `safe_windows_short_path()` on Windows

### Database Multi-Tenancy

Application supports up to 3 database targets:
- PRIMARY (required): Main application database
- SECONDARY (optional): Archive or secondary data source
- TERTIARY (optional): Additional data source

Use DB_TARGETS constants and `get_connection()` to switch between them.

### Performance Considerations

Key settings in `global.R`:
- `mergen.rdata.profile_sample_frac`: Sampling fraction for data profiling
- `mergen.rdata.enable_profiles`: Enable/disable profiling
- `mergen.rdata.enable_aggregates`: Enable/disable aggregation
- `mergen.duckdb.temp_directory`: DuckDB temporary directory
- `future.rng.onMisuse`: Handle random number issues in workers

### Security

- API keys encrypted in database (using `AI_KEYS_MASTER` secret)
- LLM API keys optionally read from encrypted session storage
- TTS API key optionally uses primary LLM key by default
- Database credentials in `.Renviron` (git-ignored)
- SSL verification configurable for on-prem deployments

### Error Handling

- Errors caught and logged via `logger` package
- Custom `shiny.error` handler in `global.R` captures session errors
- Database transaction rollback on error
- User-facing error messages in Turkish
- Debug output via `mergen_debug_cat()` for development

---

## Common Patterns & Code Style

### Null Coalescing Operator
Use `%||%` for default values:
```r
value <- var %||% "default"  # Use var if not NULL, else "default"
```

### Reactive Capture Pattern
```r
observe({
  val <- isolate(reactive_value())
  # Use val, not reactive_value() in future/worker code
})
```

### Named Lists for Settings
```r
settings <- list(
  model_selection = "gpt-4",
  temperature = 0.7,
  max_tokens = 2000,
  enable_mcp_tools = TRUE,
  shiny_session = session
)
```

### Error Messages (Turkish/English)
Use `glue()` for readable message construction:
```r
msg <- glue("Hata: {error_detail} (Error Code: {code})")
```

---

## Testing & Debugging

### Local Testing
```r
# Run the app locally
source("app.R")
# OR
shiny::runApp(".")
```

### Debug Output
Use `mergen_debug_cat()` for development-time logging:
```r
mergen_debug_cat("[DEBUG] Variable value: ", var_value, "\n")
```

### Logging
Check `logs/` directory for application logs (format: `mergen_YYYYMMDD.log`)

### Database Debugging
Use `get_pool_info()` to check connection status

### LLM Debugging
Check API response in logs and use `str()` to inspect response structures

---

## Git Workflow & Branch Conventions

### Branch Naming
Development branches follow pattern: `claude/<description>-<session-id>`

Example: `claude/add-claude-documentation-DbQhd`

### Commit Conventions
- Descriptive commit messages in present tense or Turkish
- Reference ticket/issue if applicable
- Include context about changes: "Add X feature", "Fix Y bug", "Refactor Z module"

### Pushing Code
1. Make changes on feature branch
2. Commit with clear message
3. Push with: `git push -u origin <branch-name>`
4. Branch name must start with `claude/` and end with session ID to succeed

---

## Common Troubleshooting

| Issue | Solution |
|-------|----------|
| Package not found | Run `install.packages("package_name")` and restart R session |
| Turkish characters appear as mojibake | Ensure UTF-8 encoding in all files and R session |
| Database connection fails | Check DB_DSN in `.Renviron`, verify ODBC/DBI driver installed |
| LLM API timeouts | Increase timeout in settings, check endpoint availability |
| Module not loading | Verify `source()` call in `global.R`, check file exists in R/ |
| Port 3838 already in use | Use `shiny::runApp(port = 3839)` to use different port |

---

## Key Files for AI Assistants to Understand

**Most Important (Start Here)**:
1. `global.R` - Understand module loading order and database setup
2. `server.R` - See how modules are connected and session is initialized
3. `ui.R` - Understand overall UI structure and navigation
4. `app.R` - Entry point, very simple

**For Chat/LLM Work**:
1. `R/helpers_llm_worker.R` - Core LLM calling logic
2. `R/helpers_llm_api.R` - API request construction
3. `R/server_send_message.R` - Chat message pipeline

**For File Handling**:
1. `R/module_file_manager.R` - File upload/management UI
2. `R/helpers_file_pipeline.R` - File processing
3. `R/helpers_files.R` - File utilities

**For Database Work**:
1. `R/helpers_database.R` - Connection and worker patterns
2. `R/library_queries.R` - SQL queries
3. `.Renviron` - Database connection strings

**For Settings/Configuration**:
1. `R/module_settings.R` - Settings UI and management
2. `R/config_*.R` files - Various configurations

---

### www/ Static Assets - Destek & Admin Analytics Specific
```
www/css/destek_page.css              # Main destek pages styling (full-width layout, forms, animations)
www/css/destek_yardim_chatbot.css    # Help Center AI chatbot styling (dark theme, message bubbles, thinking animation)
www/css/admin_destek_analytics.css   # Feedback & bug analytics pages styling (attachment modal, heatmap, gauge, treemap, mail icon)
www/css/admin_yanit_analizi.css     # AI response feedback analytics page styling (polar chart, badges, comment table)
www/js/destek_form.js                # Form interactions (satisfaction, NPS, tags, categories, priority, file upload, validation)
www/js/destek_yardim_chatbot.js      # Chatbot client-side logic (message sending, display, thinking indicator)
```

**For Admin Analytics Work**:
1. `R/helpers_admin_analytics.R` - Shared utilities (metric cards, safe query, DT language, Turkish formatting)
2. `R/module_admin_analytics.R` - Genel Analiz (main dashboard, refactored to use shared helpers)
3. `R/module_admin_geri_bildirim.R` - Geri Bildirim Analizi (satisfaction, NPS, tags, email contact)
4. `R/module_admin_hata_analizi.R` - Hata Analizi (priority, category, attachments, status management)
5. `R/module_admin_yanit_analizi.R` - Yanıt Geri Bildirimi Analizi (like/dislike, model performance, tags, time analysis)

### Admin Panel Menu Structure (Admin-Only)
The "Yönetici Paneli" sidebar menu is dynamically rendered for ADMIN users only, with 5 sub-items:
1. **Genel Analiz** (`admin_analytics`) - System metrics, user analytics, AI performance, chat quality, time analysis
2. **Geri Bildirim Analizi** (`admin_geri_bildirim`) - User feedback from "Geri Bildirim" form: satisfaction (1-5), NPS (0-10), tags, comments, admin email contact for users with contact permission
3. **Hata Analizi** (`admin_hata_analizi`) - Bug reports from "Hata Bildir" form: topics, categories, priority, attachments, status management
4. **Yanıt Geri Bildirimi** (`admin_yanit_analizi`) - AI response feedback from MB_Feedback: like/dislike analysis, model performance comparison, tag & comment analysis, time/user trends, polar charts
5. **Sistem Durumu** (`health`) - System health monitoring

## Last Updated
March 10, 2026

**Note**: This documentation reflects the current state of the codebase. For specific implementation details, always refer to the actual source code and inline comments in R files.

# CLAUDE.md - AI Assistant Guide for MERGEN-Bilge

**Last Updated**: 2025-11-15
**Project**: MERGEN-Bilge AI Chatbot
**Technology Stack**: R Shiny, SQL Server, DuckDB
**Primary Language**: R (with JavaScript for frontend)

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture & File Structure](#architecture--file-structure)
3. [Key Files Reference](#key-files-reference)
4. [Development Workflow](#development-workflow)
5. [Coding Conventions](#coding-conventions)
6. [Common Tasks](#common-tasks)
7. [Security Patterns](#security-patterns)
8. [Database Operations](#database-operations)
9. [AI Integration](#ai-integration)
10. [Debugging & Logging](#debugging--logging)
11. [Deployment Notes](#deployment-notes)

---

## Project Overview

MERGEN-Bilge is an enterprise-grade AI chatbot built with R Shiny, designed for interactive conversations with advanced features:

- **Multi-model AI support**: 6 pre-configured LLM endpoints with fallback support
- **Tool calling**: MCP (Model Context Protocol) Excel analysis and RData lake queries
- **Streaming responses**: Real-time character-by-character AI responses
- **File processing**: Upload and analyze TXT, PDF, DOCX, XLSX, CSV, JSON, code files
- **Enterprise data**: DuckDB-based data lake for querying project data
- **Multi-character system**: Different AI personalities with custom avatars
- **Comprehensive history**: SQL Server persistence with chat management

### Core Capabilities

1. **Chat Interface**: Real-time streaming with markdown rendering, code highlighting
2. **File Analysis**: Bulk upload with preview, summarization, and AI-powered analysis
3. **Data Querying**: Natural language queries over enterprise RData lake
4. **Chart Generation**: AI-generated visualizations via ChartLab module
5. **User Management**: Windows authentication, per-user API keys, rate limiting

---

## Architecture & File Structure

### Entry Points

```
app.R                 # Application bootstrapper (loads global, ui, server)
  ├── global.R        # Global setup: packages, database, config (2,911 lines)
  ├── ui.R            # UI definition: dashboard layout (258 lines)
  └── server.R        # Server logic: reactive values, modules (1,810 lines)
```

### Directory Structure

```
MERGEN-Bilge/
├── app.R                         # Main entry point
├── global.R                      # Global configuration
├── server.R                      # Server-side logic
├── ui.R                          # User interface
├── welcome_screen.R              # Welcome screen component
├── generate_schema_registry.R   # Schema generation utility
├── .Renviron                     # Environment variables (NOT in git)
├── .gitignore                    # Git exclusions
├── README.md                     # Project documentation
│
├── R/                            # Modular components (31 files)
│   ├── helpers_database.R        # Database operations (25K)
│   ├── helpers_mcp_tools.R       # MCP Excel tools (32K)
│   ├── helpers_rdata_lake.R      # DuckDB data lake (90K)
│   ├── helpers_chat_runtime.R    # Chat state management
│   ├── helpers_file_pipeline.R   # File processing
│   ├── helpers_language.R        # Programming language detection
│   ├── helpers_messaging.R       # Message formatting
│   ├── helpers_preview.R         # File preview generation
│   ├── helpers_chartlab.R        # Chart creation
│   ├── helpers_files.R           # File utilities
│   ├── helpers_rdata_engine.R    # RData processing
│   ├── helpers_rdata_metadata.R  # Metadata extraction
│   ├── helpers_rdata_normalize.R # Data normalization
│   ├── helpers_mcp_rdata_tools.R # MCP/RData integration
│   ├── module_settings.R         # Settings management (23K)
│   ├── module_file_manager.R     # File upload/management (33K)
│   ├── module_saved_chats.R      # Chat history management
│   ├── module_chat_history.R     # Chat history viewer
│   ├── module_ai_processing.R    # AI API calls (12K)
│   ├── module_health.R           # System health monitoring
│   ├── module_chartlab.R         # Interactive charts
│   ├── module_api_key.R          # API key management
│   ├── module_performance.R      # Performance tracking
│   ├── module_file_preview.R     # File preview modal
│   ├── module_chat_actions.R     # Like/dislike/regenerate
│   ├── module_chat_export.R      # Chat export
│   ├── module_followup_questions.R  # AI-generated follow-ups
│   ├── module_message_search.R   # In-chat search
│   ├── module_session_timeout.R  # Session management
│   ├── module_rdata_admin.R      # RData admin controls
│   ├── module_rdata_index.R      # RData indexing
│   └── schema_registry.R         # Data schema definitions
│
├── www/                          # Static web assets
│   ├── custom.css                # Custom styling (dark theme)
│   ├── script.js                 # Client-side JavaScript
│   ├── character_typing.js       # Typing animation
│   ├── codemirror/               # Code editor library
│   ├── fonts/                    # Font files
│   └── images/                   # Avatars, branding
│
└── logs/                         # Application logs
    ├── mergen_YYYYMMDD.log       # Main application log
    └── ai_debug_YYYYMMDD.log     # AI interaction debug log
```

---

## Key Files Reference

### Critical Configuration Files

#### `.Renviron` (NOT in version control)
```bash
# Database Connection
DB_SERVER=your_server_address
DB_DATABASE=your_database_name
DB_DSN=TestConnection              # ODBC DSN name

# API Key Encryption
AI_KEYS_MASTER=change_this_to_long_random_secret  # 32+ chars

# LLM Endpoints
LOCAL_LLM_ENDPOINT=https://your-api-endpoint.com/v1/chat/completions
LOCAL_LLM_ENDPOINT_ALT=https://secondary-endpoint.com/v1/chat/completions
LOCAL_LLM_ENDPOINT_ALT_API_KEY=secondary-api-key

# File Storage
MCP_FILES_BASE=//mainserver/share/mergen_uploads  # UNC path

# RData Lake
MERGEN_RDATA_DAILY_PATH=//server/share/RdataDaily
MERGEN_RDATA_WEEKLY_PATH=//server/share/Rdata

# External Services
SERVICE_DESK_API_KEY_URL=https://<your-servicedesk>/api-key
SERVICE_DESK_RATE_LIMIT_URL=https://<your-servicedesk>/rate-limit
```

### Core Application Files

#### `global.R` - Global Configuration
**Location**: `/home/user/MERGEN-Bilge/global.R` (2,911 lines)

**Key Sections**:
- Line ~1-100: Package loading (27+ packages)
- Line ~100-200: Logging configuration (`logger`)
- Line ~200-300: Database connection pool setup
- Line ~300-500: File storage initialization
- Line ~500-700: API endpoint configuration
- Line ~700-1000: Model mappings and configurations
- Line ~1000-1500: Helper function definitions
- Line ~1500-2000: Rate limiting setup
- Line ~2000-2500: DuckDB/RData lake initialization
- Line ~2500-2911: Worker pool configuration

**Important Variables**:
```r
db_pool              # Database connection pool
api_endpoint_map     # Model → endpoint mapping
model_base_folders   # Model → file path mapping
local_llm_endpoint   # Primary LLM API endpoint
rdata_db             # DuckDB connection for data lake
worker_pool          # Future worker pool (async)
```

#### `server.R` - Server Logic
**Location**: `/home/user/MERGEN-Bilge/server.R` (1,810 lines)

**Key Sections**:
- Line ~1-100: Reactive values initialization
- Line ~100-300: Module server calls
- Line ~300-600: Message sending logic
- Line ~600-900: File upload handling
- Line ~900-1200: AI response generation
- Line ~1200-1500: Chat management (new, load, save)
- Line ~1500-1810: UI updates and observers

**Critical Reactive Values**:
```r
rv$messages          # List of chat messages
rv$current_chat_id   # Active chat session ID
rv$uploaded_files    # List of uploaded files
rv$selected_model    # Current AI model
rv$selected_character # Current AI personality
rv$streaming_active  # Streaming response flag
rv$tools_enabled     # MCP/RData tools toggle
```

#### `ui.R` - User Interface
**Location**: `/home/user/MERGEN-Bilge/ui.R` (258 lines)

**Structure**:
- Dashboard header with logo and user info
- Sidebar with tabs: Chat, History, Saved Chats, Files, Settings, Health
- Main chat area with message container and input
- Cinematic intro animation
- Modals for file preview, API key entry

---

## Development Workflow

### 1. Setting Up Development Environment

```r
# Install required packages
install.packages(c(
  "shiny", "shinydashboard", "shinyjs", "shinyWidgets",
  "DBI", "odbc", "pool", "duckdb",
  "dplyr", "tidyr", "purrr", "stringr",
  "httr", "jsonlite", "future", "promises",
  "logger", "openssl"
))

# Configure .Renviron
# Copy .Renviron.example to .Renviron (if exists)
# Update with local credentials

# Set up database
# Run schema creation scripts (if available)
# Configure ODBC DSN

# Run application
shiny::runApp()
```

### 2. Development Best Practices

1. **Always source global.R**: Never modify without testing full app restart
2. **Use modules**: Create new features as Shiny modules in `R/module_*.R`
3. **Use helpers**: Utility functions go in `R/helpers_*.R`
4. **Log everything**: Use `logger::log_info()`, `log_warn()`, `log_error()`
5. **Test async code**: Use `future` for long-running operations
6. **Validate inputs**: Always validate user input before database operations

### 3. Making Changes

#### Adding a New Feature Module

```r
# 1. Create module file: R/module_myfeature.R
myfeatureUI <- function(id) {
  ns <- NS(id)
  # UI elements
}

myfeatureServer <- function(id, ...) {
  moduleServer(id, function(input, output, session) {
    # Server logic
  })
}

# 2. Add to ui.R
myfeatureUI("myfeature")

# 3. Add to server.R
myfeatureServer("myfeature", ...)

# 4. Source in global.R (if needed)
source("R/module_myfeature.R")
```

#### Adding a Helper Function

```r
# 1. Identify appropriate helpers_*.R file or create new one
# 2. Add function with roxygen-style comments
#' Brief description
#'
#' @param param1 Description
#' @return Return value description
my_helper <- function(param1) {
  # Implementation
}

# 3. Source in global.R (if new file)
source("R/helpers_myhelper.R")
```

#### Modifying Database Schema

```r
# 1. Test query in SQL Server Management Studio
# 2. Add to helpers_database.R as a function
# 3. Use parameterized queries ALWAYS
execute_my_query <- function(param) {
  DBI::dbGetQuery(
    db_pool,
    "SELECT * FROM MyTable WHERE column = ?",
    params = list(param)
  )
}
```

### 4. Testing Changes

```r
# Run locally
shiny::runApp()

# Check logs
tail -f logs/mergen_*.log

# Test database operations
DBI::dbGetQuery(db_pool, "SELECT 1 AS test")

# Test file uploads
# Use UI to upload various file types

# Test AI integration
# Send messages with different models
# Test tool calling with MCP/RData modes

# Check health monitor
# Go to Sistem Durumu tab
```

---

## Coding Conventions

### 1. R Code Style

```r
# Use snake_case for variables and functions
my_variable <- "value"
my_function <- function(param) {}

# Use <- for assignment (not =)
x <- 10  # Good
x = 10   # Avoid

# Indent with 2 spaces (no tabs)
if (condition) {
  do_something()
}

# Meaningful variable names
user_id <- get_user_id()  # Good
uid <- get_user_id()      # Avoid

# Comment complex logic
# Calculate weighted average based on project duration
weighted_avg <- sum(values * weights) / sum(weights)
```

### 2. Shiny Module Conventions

```r
# UI function ends with UI
myFeatureUI <- function(id) {
  ns <- NS(id)
  tagList(
    # UI elements with ns() wrapped IDs
    textInput(ns("input_id"), "Label")
  )
}

# Server function ends with Server
myFeatureServer <- function(id, reactive_param) {
  moduleServer(id, function(input, output, session) {
    # Use reactive() for reactive expressions
    my_reactive <- reactive({
      reactive_param() + input$input_id
    })

    # Use observe() for side effects
    observe({
      logger::log_info("Input changed: {input$input_id}")
    })

    # Return reactive values or list
    return(reactive({
      list(result = my_reactive())
    }))
  })
}
```

### 3. Database Query Conventions

```r
# ALWAYS use parameterized queries
safe_query <- function(user_input) {
  DBI::dbGetQuery(
    db_pool,
    "SELECT * FROM Users WHERE username = ?",
    params = list(user_input)
  )
}

# NEVER concatenate user input into SQL
unsafe_query <- function(user_input) {
  # DON'T DO THIS!
  DBI::dbGetQuery(
    db_pool,
    paste0("SELECT * FROM Users WHERE username = '", user_input, "'")
  )
}

# Validate input even with parameterized queries (defense in depth)
validate_username <- function(username) {
  if (!grepl("^[a-zA-Z0-9._-]{3,50}$", username)) {
    stop("Invalid username format")
  }
  username
}
```

### 4. Error Handling

```r
# Use tryCatch for external operations
result <- tryCatch({
  # Risky operation
  httr::GET(url)
}, error = function(e) {
  logger::log_error("API call failed: {e$message}")
  NULL
})

# Validate before processing
if (is.null(result)) {
  showNotification("Failed to fetch data", type = "error")
  return(NULL)
}

# Use stopifnot for internal assertions
stopifnot(is.character(username))
stopifnot(nchar(message) > 0)
```

### 5. Logging Conventions

```r
# Use appropriate log levels
logger::log_info("User {username} logged in")           # Informational
logger::log_warn("Rate limit approaching for {user}")   # Warning
logger::log_error("Database connection failed: {err}")  # Error
logger::log_debug("Variable state: {jsonlite::toJSON(var)}")  # Debug

# Include context in log messages
logger::log_info("Chat {chat_id} created by user {user_id}")

# Log entry/exit of important functions
my_function <- function() {
  logger::log_debug("Entering my_function")
  # ... logic ...
  logger::log_debug("Exiting my_function")
}
```

---

## Common Tasks

### Adding a New AI Model

**File**: `global.R`

```r
# 1. Add to model list (around line 500-700)
available_models <- c(
  "Existing Model 1",
  "Existing Model 2",
  "New Model Name"  # Add here
)

# 2. Add to endpoint mapping
api_endpoint_map <- list(
  "New Model Name" = "primary_endpoint"
)

# 3. Add to base folder mapping (for file context)
model_base_folders <- list(
  "New Model Name" = "//server/share/context_files"
)

# 4. Update UI in module_settings.R if needed
```

### Adding a New MCP Tool

**File**: `R/helpers_mcp_tools.R`

```r
# 1. Define tool schema
new_tool_schema <- list(
  type = "function",
  `function` = list(
    name = "new_tool_name",
    description = "What this tool does",
    parameters = list(
      type = "object",
      properties = list(
        param1 = list(
          type = "string",
          description = "Parameter description"
        )
      ),
      required = list("param1")
    )
  )
)

# 2. Add to get_mcp_tools() return list
get_mcp_tools <- function() {
  list(
    # Existing tools...
    new_tool_schema
  )
}

# 3. Implement handler in execute_mcp_tool()
execute_mcp_tool <- function(tool_name, arguments, user_id) {
  result <- switch(
    tool_name,
    # Existing tools...
    "new_tool_name" = {
      # Implementation
      list(
        success = TRUE,
        content = "Tool result"
      )
    },
    # Default case
    list(success = FALSE, error = "Unknown tool")
  )
  return(result)
}
```

### Adding a New Database Table

**File**: `R/helpers_database.R`

```r
# 1. Create table in SQL Server first (outside R)
CREATE TABLE MB_NewTable (
    id INT IDENTITY(1,1) PRIMARY KEY,
    user_id INT NOT NULL,
    data NVARCHAR(MAX),
    created_at DATETIME DEFAULT GETDATE()
)

# 2. Add CRUD functions
insert_new_record <- function(user_id, data) {
  DBI::dbExecute(
    db_pool,
    "INSERT INTO MB_NewTable (user_id, data) VALUES (?, ?)",
    params = list(user_id, data)
  )
}

get_new_records <- function(user_id) {
  DBI::dbGetQuery(
    db_pool,
    "SELECT * FROM MB_NewTable WHERE user_id = ?",
    params = list(user_id)
  )
}

# 3. Use in application
records <- get_new_records(session$userData$user_id)
```

### Adding a New File Type Support

**File**: `R/helpers_file_pipeline.R`

```r
# 1. Add to supported extensions
SUPPORTED_EXTENSIONS <- c(
  ".txt", ".pdf", ".docx", ".xlsx", ".csv",
  ".newext"  # Add here
)

# 2. Add reader function
read_newext_file <- function(file_path) {
  tryCatch({
    # Read file logic
    content <- readLines(file_path)
    list(
      success = TRUE,
      content = paste(content, collapse = "\n"),
      summary = substr(content, 1, 500)
    )
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# 3. Add to file processing pipeline
process_file <- function(file_path, extension) {
  result <- switch(
    extension,
    ".txt" = read_text_file(file_path),
    ".newext" = read_newext_file(file_path),
    # Other extensions...
    list(success = FALSE, error = "Unsupported file type")
  )
  return(result)
}
```

### Adding a New Character (AI Personality)

**File**: `global.R`

```r
# 1. Add character definition (around line 1000-1500)
characters <- list(
  # Existing characters...
  "New Character" = list(
    name = "New Character",
    avatar = "www/images/new_character.png",  # Add image to www/images/
    system_prompt = "You are a helpful AI assistant with [personality traits]...",
    greeting = "Hello! I'm [character name], ready to help you with..."
  )
)

# 2. Add avatar image to www/images/
# File: www/images/new_character.png (300x300px recommended)

# 3. Update UI in module_settings.R if needed
```

### Modifying Rate Limits

**File**: `global.R`

```r
# Find rate limit configuration (around line 1500-2000)
RATE_LIMIT_PER_USER <- 10      # Requests per minute per user
RATE_LIMIT_GLOBAL <- 100       # Requests per minute globally
RATE_LIMIT_WINDOW <- 60        # Time window in seconds

# Modify as needed for production load
```

---

## Security Patterns

### 1. SQL Injection Prevention

**ALWAYS use parameterized queries**:

```r
# CORRECT - Parameterized
user <- DBI::dbGetQuery(
  db_pool,
  "SELECT * FROM MB_Users WHERE username = ?",
  params = list(username)
)

# WRONG - Concatenation (NEVER DO THIS)
user <- DBI::dbGetQuery(
  db_pool,
  paste0("SELECT * FROM MB_Users WHERE username = '", username, "'")
)
```

**Validate input even with parameterization** (defense in depth):

```r
validate_username <- function(username) {
  # Length check
  if (nchar(username) < 3 || nchar(username) > 50) {
    stop("Username must be 3-50 characters")
  }

  # Pattern check
  if (!grepl("^[a-zA-Z0-9._-]+$", username)) {
    stop("Username contains invalid characters")
  }

  # SQL keyword check (extra safety)
  sql_keywords <- c("SELECT", "DROP", "INSERT", "UPDATE", "DELETE", "UNION")
  if (any(sapply(sql_keywords, grepl, x = toupper(username)))) {
    stop("Username contains forbidden patterns")
  }

  return(username)
}
```

### 2. API Key Encryption

**File**: `R/module_api_key.R`, `R/helpers_database.R`

```r
# Encrypt before storing
encrypt_api_key <- function(api_key) {
  master_key <- Sys.getenv("AI_KEYS_MASTER")

  # Use AES-GCM if available, fallback to AES-CBC
  encrypted <- tryCatch({
    openssl::aes_gcm_encrypt(
      charToRaw(api_key),
      charToRaw(master_key)
    )
  }, error = function(e) {
    openssl::aes_cbc_encrypt(
      charToRaw(api_key),
      charToRaw(master_key)
    )
  })

  base64enc::base64encode(encrypted)
}

# Decrypt when using
decrypt_api_key <- function(encrypted_key) {
  master_key <- Sys.getenv("AI_KEYS_MASTER")
  encrypted_raw <- base64enc::base64decode(encrypted_key)

  decrypted <- tryCatch({
    openssl::aes_gcm_decrypt(encrypted_raw, charToRaw(master_key))
  }, error = function(e) {
    openssl::aes_cbc_decrypt(encrypted_raw, charToRaw(master_key))
  })

  rawToChar(decrypted)
}
```

### 3. Rate Limiting

**File**: `R/helpers_database.R`, `server.R`

```r
check_rate_limit <- function(user_id) {
  # Get recent requests (last 60 seconds)
  recent_requests <- DBI::dbGetQuery(
    db_pool,
    "SELECT COUNT(*) as count FROM MB_APIUsage
     WHERE user_id = ? AND request_time > DATEADD(second, -60, GETDATE())",
    params = list(user_id)
  )

  # Check per-user limit
  if (recent_requests$count >= RATE_LIMIT_PER_USER) {
    return(list(
      allowed = FALSE,
      message = "Rate limit exceeded. Please wait before sending another message."
    ))
  }

  # Check global limit
  global_requests <- DBI::dbGetQuery(
    db_pool,
    "SELECT COUNT(*) as count FROM MB_APIUsage
     WHERE request_time > DATEADD(second, -60, GETDATE())"
  )

  if (global_requests$count >= RATE_LIMIT_GLOBAL) {
    return(list(
      allowed = FALSE,
      message = "System is currently busy. Please try again in a moment."
    ))
  }

  return(list(allowed = TRUE))
}

# Use before AI API calls
rate_check <- check_rate_limit(user_id)
if (!rate_check$allowed) {
  showNotification(rate_check$message, type = "warning")
  return(NULL)
}
```

### 4. File Upload Security

**File**: `R/module_file_manager.R`

```r
# Validate file extension
validate_file_extension <- function(filename) {
  ext <- tolower(tools::file_ext(filename))
  allowed <- c("txt", "pdf", "docx", "xlsx", "xls", "csv", "json",
               "r", "py", "md", "log", "xml", "html")

  if (!ext %in% allowed) {
    stop(paste("File type not allowed:", ext))
  }

  return(ext)
}

# Validate file size
validate_file_size <- function(file_path, max_mb = 30) {
  size_mb <- file.size(file_path) / 1024^2

  if (size_mb > max_mb) {
    stop(paste("File too large:", round(size_mb, 1), "MB (max:", max_mb, "MB)"))
  }

  return(TRUE)
}

# Sanitize filename (prevent directory traversal)
sanitize_filename <- function(filename) {
  # Remove path components
  filename <- basename(filename)

  # Remove dangerous characters
  filename <- gsub("[^a-zA-Z0-9._-]", "_", filename)

  # Prevent hidden files
  filename <- gsub("^\\.", "", filename)

  return(filename)
}
```

### 5. Session Security

**File**: `R/module_session_timeout.R`

```r
# Timeout after 30 minutes of inactivity
SESSION_TIMEOUT_MINUTES <- 30

sessionTimeoutServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    # Track last activity
    last_activity <- reactiveVal(Sys.time())

    # Update on any input change
    observe({
      reactiveValuesToList(input)
      last_activity(Sys.time())
    })

    # Check timeout every minute
    observe({
      invalidateLater(60000)  # 60 seconds

      idle_time <- difftime(Sys.time(), last_activity(), units = "mins")

      if (idle_time > SESSION_TIMEOUT_MINUTES) {
        showModal(modalDialog(
          title = "Session Expired",
          "Your session has expired due to inactivity. Please refresh the page.",
          footer = NULL,
          easyClose = FALSE
        ))

        # Log session timeout
        logger::log_info("Session timeout for user {session$userData$username}")
      }
    })
  })
}
```

---

## Database Operations

### Database Schema

**Tables**:

```sql
-- User management
MB_Users (
  user_id INT IDENTITY(1,1) PRIMARY KEY,
  username NVARCHAR(100) UNIQUE,
  email NVARCHAR(255),
  created_at DATETIME,
  last_login DATETIME
)

-- Chat sessions
MB_Chats (
  chat_id INT IDENTITY(1,1) PRIMARY KEY,
  user_id INT,
  title NVARCHAR(200),
  model_name NVARCHAR(100),
  character_name NVARCHAR(100),
  created_at DATETIME,
  updated_at DATETIME
)

-- Individual messages
MB_Messages (
  message_id INT IDENTITY(1,1) PRIMARY KEY,
  chat_id INT,
  role NVARCHAR(50),  -- 'user', 'assistant', 'system'
  content NVARCHAR(MAX),
  file_references NVARCHAR(MAX),  -- JSON array of files
  tool_calls NVARCHAR(MAX),       -- JSON of tool calls
  created_at DATETIME
)

-- Message feedback
MB_MessageFeedback (
  feedback_id INT IDENTITY(1,1) PRIMARY KEY,
  message_id INT,
  user_id INT,
  feedback_type NVARCHAR(20),  -- 'like', 'dislike'
  created_at DATETIME
)

-- API usage tracking
MB_APIUsage (
  usage_id INT IDENTITY(1,1) PRIMARY KEY,
  user_id INT,
  chat_id INT,
  model_name NVARCHAR(100),
  request_time DATETIME,
  response_time DATETIME,
  tokens_used INT,
  success BIT
)

-- User activity log
MB_UserActivityLog (
  log_id INT IDENTITY(1,1) PRIMARY KEY,
  user_id INT,
  action NVARCHAR(100),
  details NVARCHAR(MAX),
  created_at DATETIME
)
```

### Common Database Functions

**File**: `R/helpers_database.R`

```r
# Get or create user
get_or_create_user <- function(username) {
  user <- DBI::dbGetQuery(
    db_pool,
    "SELECT * FROM MB_Users WHERE username = ?",
    params = list(username)
  )

  if (nrow(user) == 0) {
    DBI::dbExecute(
      db_pool,
      "INSERT INTO MB_Users (username, created_at, last_login)
       VALUES (?, GETDATE(), GETDATE())",
      params = list(username)
    )
    user <- get_or_create_user(username)  # Recursive call to get new user
  } else {
    # Update last login
    DBI::dbExecute(
      db_pool,
      "UPDATE MB_Users SET last_login = GETDATE() WHERE user_id = ?",
      params = list(user$user_id)
    )
  }

  return(user)
}

# Create new chat
create_chat <- function(user_id, title, model_name, character_name) {
  DBI::dbExecute(
    db_pool,
    "INSERT INTO MB_Chats (user_id, title, model_name, character_name, created_at, updated_at)
     VALUES (?, ?, ?, ?, GETDATE(), GETDATE())",
    params = list(user_id, title, model_name, character_name)
  )

  # Get the newly created chat
  DBI::dbGetQuery(
    db_pool,
    "SELECT TOP 1 * FROM MB_Chats WHERE user_id = ? ORDER BY chat_id DESC",
    params = list(user_id)
  )
}

# Save message
save_message <- function(chat_id, role, content, file_references = NULL, tool_calls = NULL) {
  DBI::dbExecute(
    db_pool,
    "INSERT INTO MB_Messages (chat_id, role, content, file_references, tool_calls, created_at)
     VALUES (?, ?, ?, ?, ?, GETDATE())",
    params = list(
      chat_id,
      role,
      content,
      if (!is.null(file_references)) jsonlite::toJSON(file_references, auto_unbox = TRUE) else NULL,
      if (!is.null(tool_calls)) jsonlite::toJSON(tool_calls, auto_unbox = TRUE) else NULL
    )
  )
}

# Load chat messages
load_chat_messages <- function(chat_id) {
  DBI::dbGetQuery(
    db_pool,
    "SELECT * FROM MB_Messages WHERE chat_id = ? ORDER BY message_id ASC",
    params = list(chat_id)
  )
}

# Log API usage
log_api_usage <- function(user_id, chat_id, model_name, request_time, response_time, tokens_used, success) {
  DBI::dbExecute(
    db_pool,
    "INSERT INTO MB_APIUsage (user_id, chat_id, model_name, request_time, response_time, tokens_used, success)
     VALUES (?, ?, ?, ?, ?, ?, ?)",
    params = list(user_id, chat_id, model_name, request_time, response_time, tokens_used, success)
  )
}
```

---

## AI Integration

### AI API Flow

**File**: `R/module_ai_processing.R`

```r
# Main AI processing function
process_ai_request <- function(messages, model, tools = NULL, stream = FALSE) {
  # Get endpoint configuration
  endpoint <- api_endpoint_map[[model]]
  api_key <- get_api_key_for_endpoint(endpoint, user_id)

  # Build request body
  request_body <- list(
    messages = messages,
    temperature = 0.4,
    model = model,
    stream = stream
  )

  # Add tools if provided
  if (!is.null(tools) && length(tools) > 0) {
    request_body$tools <- tools
    stream <- FALSE  # Disable streaming when tools are active
  }

  # Make API request
  if (stream) {
    # Streaming response
    process_streaming_response(endpoint, api_key, request_body)
  } else {
    # Non-streaming response
    process_nonstreaming_response(endpoint, api_key, request_body)
  }
}
```

### Streaming Responses

```r
process_streaming_response <- function(endpoint, api_key, request_body) {
  # Open streaming connection
  response <- httr::POST(
    endpoint,
    httr::add_headers(
      "Authorization" = paste("Bearer", api_key),
      "Content-Type" = "application/json"
    ),
    body = jsonlite::toJSON(request_body, auto_unbox = TRUE),
    encode = "raw",
    httr::write_stream(function(chunk) {
      # Parse SSE chunk
      if (grepl("data: ", chunk)) {
        json_str <- sub("data: ", "", chunk)

        if (json_str == "[DONE]") {
          return(TRUE)  # End streaming
        }

        tryCatch({
          data <- jsonlite::fromJSON(json_str)
          delta <- data$choices[[1]]$delta

          if (!is.null(delta$content)) {
            # Send to client via JavaScript
            session$sendCustomMessage("streamToken", list(
              content = delta$content
            ))
          }
        }, error = function(e) {
          logger::log_warn("Failed to parse streaming chunk: {e$message}")
        })
      }
    })
  )
}
```

### Tool Calling

```r
# MCP Excel Tools
get_mcp_tools <- function() {
  list(
    list(
      type = "function",
      `function` = list(
        name = "analyze_uploaded_file",
        description = "Get structure and statistics of uploaded Excel/CSV file",
        parameters = list(
          type = "object",
          properties = list(
            file_name = list(
              type = "string",
              description = "Name of the uploaded file"
            ),
            limit = list(
              type = "integer",
              description = "Number of rows to return (default 100)"
            )
          ),
          required = list("file_name")
        )
      )
    ),
    list(
      type = "function",
      `function` = list(
        name = "sql_query_uploaded_file",
        description = "Execute SQL query on uploaded file",
        parameters = list(
          type = "object",
          properties = list(
            file_name = list(type = "string"),
            sql = list(
              type = "string",
              description = "SQL query (use 'data' as table name)"
            )
          ),
          required = list("file_name", "sql")
        )
      )
    )
    # More tools...
  )
}

# Execute tool
execute_mcp_tool <- function(tool_name, arguments, user_id) {
  result <- switch(
    tool_name,
    "analyze_uploaded_file" = {
      analyze_file(arguments$file_name, arguments$limit %||% 100, user_id)
    },
    "sql_query_uploaded_file" = {
      query_file(arguments$file_name, arguments$sql, user_id)
    },
    # Default
    list(success = FALSE, error = "Unknown tool")
  )

  return(result)
}
```

### RData Lake Queries

**File**: `R/helpers_rdata_lake.R`

```r
# Execute SQL on DuckDB data lake
rdata_sql <- function(sql, limit = 1000) {
  tryCatch({
    # Validate SQL (basic checks)
    if (grepl("(?i)(DROP|DELETE|UPDATE|INSERT|ALTER|CREATE)", sql)) {
      return(list(
        success = FALSE,
        error = "Only SELECT queries are allowed"
      ))
    }

    # Add limit if not present
    if (!grepl("(?i)LIMIT", sql)) {
      sql <- paste(sql, "LIMIT", limit)
    }

    # Execute query
    result <- DBI::dbGetQuery(rdata_db, sql)

    list(
      success = TRUE,
      rows = nrow(result),
      columns = ncol(result),
      data = result,
      preview = head(result, 10)
    )
  }, error = function(e) {
    list(
      success = FALSE,
      error = e$message
    )
  })
}

# Get project metrics
rdata_metrics <- function(proje_adi = NULL, proje_kodu = NULL) {
  # Build WHERE clause
  where_clauses <- c()
  params <- list()

  if (!is.null(proje_adi)) {
    where_clauses <- c(where_clauses, "proje_adi LIKE ?")
    params <- c(params, paste0("%", proje_adi, "%"))
  }

  if (!is.null(proje_kodu)) {
    where_clauses <- c(where_clauses, "proje_kodu = ?")
    params <- c(params, proje_kodu)
  }

  where_sql <- if (length(where_clauses) > 0) {
    paste("WHERE", paste(where_clauses, collapse = " AND "))
  } else {
    ""
  }

  # Execute query
  sql <- glue::glue("
    SELECT
      proje_adi,
      proje_kodu,
      SUM(is_gun) as total_workdays,
      COUNT(DISTINCT personel_adi) as team_size,
      MIN(tarih) as start_date,
      MAX(tarih) as end_date
    FROM rd_merged
    {where_sql}
    GROUP BY proje_adi, proje_kodu
    ORDER BY total_workdays DESC
    LIMIT 100
  ")

  result <- DBI::dbGetQuery(rdata_db, sql)

  list(
    success = TRUE,
    metrics = result
  )
}
```

---

## Debugging & Logging

### Log Files

**Location**: `/home/user/MERGEN-Bilge/logs/`

- `mergen_YYYYMMDD.log` - Main application log
- `ai_debug_YYYYMMDD.log` - AI interaction debug log

### Log Levels

```r
# Use appropriate log level
logger::log_trace("Very detailed debug info")     # Most verbose
logger::log_debug("Debug information")            # Development
logger::log_info("Informational message")         # Normal operation
logger::log_warn("Warning condition")             # Potential issues
logger::log_error("Error occurred")               # Errors
logger::log_fatal("Critical failure")             # Application crash
```

### Viewing Logs

```bash
# Tail main log
tail -f logs/mergen_$(date +%Y%m%d).log

# Tail AI debug log
tail -f logs/ai_debug_$(date +%Y%m%d).log

# Search for errors
grep "ERROR" logs/mergen_*.log

# Search for specific user
grep "user_id=123" logs/mergen_*.log
```

### Debug Mode

**File**: `global.R`

```r
# Enable debug logging
logger::log_threshold(logger::DEBUG)

# Log all AI requests/responses
AI_DEBUG_MODE <- TRUE

# In module_ai_processing.R
if (AI_DEBUG_MODE) {
  logger::log_debug("AI Request: {jsonlite::toJSON(request_body, pretty = TRUE)}")
  logger::log_debug("AI Response: {jsonlite::toJSON(response_data, pretty = TRUE)}")
}
```

### Common Debugging Scenarios

#### Database Connection Issues

```r
# Test connection
tryCatch({
  DBI::dbGetQuery(db_pool, "SELECT 1 AS test")
  logger::log_info("Database connection OK")
}, error = function(e) {
  logger::log_error("Database connection failed: {e$message}")
})

# Check pool status
print(pool::dbGetInfo(db_pool))
```

#### File Upload Issues

```r
# Check file exists
if (!file.exists(file_path)) {
  logger::log_error("File not found: {file_path}")
}

# Check file permissions
file.info(file_path)$mode

# Check file size
logger::log_info("File size: {file.size(file_path)} bytes")
```

#### AI API Issues

```r
# Log full request/response
logger::log_debug("Endpoint: {endpoint}")
logger::log_debug("Headers: {jsonlite::toJSON(headers)}")
logger::log_debug("Body: {jsonlite::toJSON(request_body, pretty = TRUE)}")
logger::log_debug("Response status: {httr::status_code(response)}")
logger::log_debug("Response body: {httr::content(response, 'text')}")
```

#### Async/Future Issues

```r
# Enable future debugging
options(future.debug = TRUE)

# Check worker status
future::nbrOfWorkers()
future::availableCores()

# Test async operation
test_future <- future::future({
  Sys.sleep(2)
  "Test complete"
})
value <- future::value(test_future)
logger::log_info("Async test result: {value}")
```

---

## Deployment Notes

### Requirements

1. **R Environment**:
   - R version: 4.0+ (preferably 4.2+)
   - All packages from `global.R` installed
   - Rscript available in PATH

2. **System Dependencies**:
   - ODBC drivers for SQL Server
   - System fonts for UI rendering
   - Network access to file shares (UNC paths)
   - SSL/TLS libraries for HTTPS

3. **Database**:
   - SQL Server instance
   - ODBC DSN configured
   - Database schema created (all MB_* tables)

4. **File Storage**:
   - UNC path accessible: `//mainserver/share/mergen_uploads`
   - Write permissions for application user
   - Sufficient disk space (depends on usage)

### Environment Configuration

**File**: `.Renviron` (create from template)

```bash
# Copy and customize
cp .Renviron.example .Renviron

# Edit with production values
nano .Renviron

# Set strong encryption key (32+ chars)
AI_KEYS_MASTER=$(openssl rand -base64 32)
```

### Deployment Checklist

- [ ] Install R and required packages
- [ ] Configure ODBC DSN for database
- [ ] Create database schema (all MB_* tables)
- [ ] Set up `.Renviron` with production credentials
- [ ] Create file storage directory structure
- [ ] Configure UNC path access
- [ ] Test database connection
- [ ] Test file upload/download
- [ ] Test AI API endpoints
- [ ] Configure log rotation
- [ ] Set up monitoring (health check endpoint)
- [ ] Configure session timeout
- [ ] Review rate limits for production load
- [ ] Enable HTTPS (if using Shiny Server)
- [ ] Configure firewall rules
- [ ] Set up backup strategy for database

### Running in Production

**Shiny Server**:

```bash
# Install Shiny Server
sudo apt-get install shiny-server

# Copy app to Shiny Server directory
sudo cp -r /path/to/MERGEN-Bilge /srv/shiny-server/mergen-bilge

# Configure shiny-server.conf
sudo nano /etc/shiny-server/shiny-server.conf

# Add:
server {
  listen 3838;

  location /mergen {
    app_dir /srv/shiny-server/mergen-bilge;
    log_dir /var/log/shiny-server/mergen;
  }
}

# Restart Shiny Server
sudo systemctl restart shiny-server
```

**RStudio Connect**:

```r
# Deploy from RStudio
library(rsconnect)

rsconnect::deployApp(
  appDir = "/path/to/MERGEN-Bilge",
  appName = "mergen-bilge",
  account = "your-account"
)
```

### Monitoring

```r
# Health check endpoint (built-in)
# Access via UI: Sistem Durumu tab

# Metrics to monitor:
# - Database connection status
# - Worker pool availability
# - Request count and duration
# - Error rate
# - Memory usage
# - Log file size
```

### Backup Strategy

```bash
# Database backup (SQL Server)
sqlcmd -S server -d database -Q "BACKUP DATABASE database TO DISK='backup.bak'"

# File storage backup
rsync -av //server/share/mergen_uploads /backup/mergen_uploads

# Application code backup (git)
git push origin main
```

### Troubleshooting Deployment

**Database connection fails**:
```r
# Test ODBC connection
DBI::dbCanConnect(odbc::odbc(), dsn = "TestConnection")

# Check DSN configuration
odbcinst -q -s
```

**File uploads fail**:
```bash
# Check UNC path access
ls //mainserver/share/mergen_uploads

# Check permissions
touch //mainserver/share/mergen_uploads/test.txt
```

**AI API fails**:
```r
# Test endpoint
httr::GET(
  local_llm_endpoint,
  httr::add_headers("Authorization" = paste("Bearer", api_key))
)
```

---

## AI Assistant Guidelines

### When Working on This Codebase

1. **Always check logs first** when debugging issues
2. **Use parameterized queries** for ALL database operations
3. **Validate user input** before processing
4. **Log important events** with appropriate log levels
5. **Test async code** thoroughly (use `future` correctly)
6. **Follow module pattern** for new features
7. **Document complex logic** with comments
8. **Update this file** when making architectural changes

### Common Pitfalls

1. **Don't use string concatenation for SQL** - always use `params`
2. **Don't forget to source new files in global.R**
3. **Don't block the main thread** - use `future` for long operations
4. **Don't commit `.Renviron`** - keep secrets out of git
5. **Don't skip input validation** - validate even with parameterization
6. **Don't ignore error handling** - wrap risky operations in `tryCatch`
7. **Don't modify `global.R` without testing full restart**

### Best Practices for AI Assistants

1. **Read existing code** before suggesting changes
2. **Follow established patterns** in the codebase
3. **Test changes locally** before committing
4. **Update documentation** when adding features
5. **Log your changes** in git commits
6. **Ask for clarification** when requirements are unclear
7. **Consider security implications** of all changes

---

## Additional Resources

### R Shiny Documentation
- [Shiny Official Docs](https://shiny.rstudio.com/)
- [Shiny Modules Guide](https://shiny.rstudio.com/articles/modules.html)
- [shinydashboard](https://rstudio.github.io/shinydashboard/)

### Database
- [DBI Package](https://dbi.r-dbi.org/)
- [pool Package](https://rstudio.github.io/pool/)
- [DuckDB for R](https://duckdb.org/docs/api/r)

### Async Programming
- [future Package](https://future.futureverse.org/)
- [promises Package](https://rstudio.github.io/promises/)

### Security
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [SQL Injection Prevention](https://cheatsheetseries.owasp.org/cheatsheets/SQL_Injection_Prevention_Cheat_Sheet.html)

---

**Document Maintenance**:
- Update this file when making architectural changes
- Document new modules and helpers
- Keep security patterns current
- Add new common tasks as they arise
- Review and update deployment checklist periodically

**Questions or Issues**:
- Check logs first: `logs/mergen_*.log`
- Review health monitor: Sistem Durumu tab
- Consult this guide for patterns and conventions
- Add new sections to this guide as needed

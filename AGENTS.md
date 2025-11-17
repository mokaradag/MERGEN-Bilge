# AGENTS.md - AI Agents & Characters System

**Last Updated**: 2025-11-17
**Project**: MERGEN-Bilge AI Chatbot
**Component**: Multi-Agent Character System with Tool Calling

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Character Gallery](#character-gallery)
3. [Model Configuration](#model-configuration)
4. [Tool Calling System](#tool-calling-system)
5. [Character Implementation](#character-implementation)
6. [Adding New Characters](#adding-new-characters)
7. [Adding New Tools](#adding-new-tools)
8. [Best Practices](#best-practices)
9. [Technical Reference](#technical-reference)

---

## System Overview

MERGEN-Bilge implements a **multi-agent character system** inspired by Turkic/Altaic mythology. Each character embodies a distinct cognitive style, personality, and problem-solving approach, providing users with specialized AI assistants for different types of tasks.

### Core Concepts

- **5 Unique Characters**: Each with mythological background, unique personality, and specialized capabilities
- **6 LLM Models**: Flexible model selection with primary/secondary endpoint fallback
- **2 Tool Families**: MCP Excel tools and RData lake query tools (mutually exclusive)
- **Dynamic System Prompts**: Character-specific instructions with context awareness
- **Visual Identity**: Custom avatars, accent colors, and UI theming per character

### Architecture

```
User Request
    ↓
Character Selection (MERGEN, ÜLGEN, KAYRA, ERLİK, UMAY ANA)
    ↓
Model Selection (6 available models)
    ↓
Tool Family Detection (Excel MCP, RData MCP, or None)
    ↓
System Prompt Construction (Character + Context + Citations)
    ↓
API Request (with character temperature and tools)
    ↓
Streaming Response (character-themed UI)
```

---

## Character Gallery

### 1. MERGEN - Zihin Yayından Çıkan Ok
*"The Arrow from the Mind's Bow"*

**Character ID**: `mergen`
**Avatar**: `www/characters/avatar/Mergen_avatar_original.png`
**Accent Color**: `#7C4DFF` (Deep Purple)
**Temperature**: `0.4`

#### Personality Profile

**Archetype**: Pragmatic action-oriented assistant
**Best For**: Quick decisions, clear action plans, practical solutions
**Response Style**: Executive summary → Step-by-step plan → Minimal example

#### System Prompt
```
Be a balanced, pragmatic assistant. First provide a 2–3 sentence executive
summary, then a concise step-by-step plan, then a minimal example/output.
Avoid rhetoric and hedging.
```

#### Signature Moves
- **2-3 sentence executive summary**: Gets to the point immediately
- **Clear action checklist**: Numbered steps you can follow right away
- **Minimal example/output reinforcement**: Shows exactly what to expect

#### Profile Metrics
```
Analytical Sharpness:  ████████████████████ 88%
Planning Discipline:   ███████████████████  84%
Empathic Tone:         ███████████          52%
Risk Warning:          ██████████           47%
```

#### When to Use MERGEN
- ✅ Need quick, actionable advice
- ✅ Want clear step-by-step instructions
- ✅ Prefer concise, no-nonsense responses
- ✅ Need practical examples
- ❌ Exploring multiple alternatives
- ❌ Need empathetic teaching approach
- ❌ Require deep strategic planning

#### Example Interaction
```
User: "How do I optimize this slow SQL query?"

MERGEN:
Summary: Your query lacks proper indexing and has unnecessary joins—expect
5-10× speedup after optimization.

Plan:
1. Add index on frequently filtered columns
2. Replace subquery with JOIN
3. Use EXPLAIN ANALYZE to verify improvements

Example:
CREATE INDEX idx_user_created ON users(created_at);
SELECT ... FROM users u JOIN orders o ON u.id = o.user_id WHERE ...
```

---

### 2. ÜLGEN - Göğün Işığı
*"The Light of Heaven"*

**Character ID**: `ulgen`
**Avatar**: `www/characters/avatar/Ulgen_avatar_original.png`
**Accent Color**: `#2F6DF6` (Bright Blue)
**Temperature**: `0.5`

#### Personality Profile

**Archetype**: Constructive expert, solution-oriented
**Best For**: Evaluating options, comparing approaches, positive guidance
**Response Style**: Problem framing → 2-3 solution paths → Recommendation → Action list

#### System Prompt
```
Act like a constructive expert: quickly frame the problem; propose 2–3 viable
solution paths with trade-offs; recommend one path with rationale; end with a
checklist of next actions.
```

#### Signature Moves
- **Clear problem framing**: Defines the real challenge
- **2-3 alternative paths with comparisons**: Shows options with pros/cons
- **Positive tone with action list**: Encouraging and actionable

#### Profile Metrics
```
Inspiring Tone:         ██████████████████   82%
Option Generation:      ████████████████████ 90%
Empathy:                █████████████        64%
Implementation Clarity: ████████████████     74%
```

#### When to Use ÜLGEN
- ✅ Evaluating multiple solution approaches
- ✅ Need to compare trade-offs
- ✅ Want encouraging, constructive feedback
- ✅ Exploring different implementation paths
- ❌ Need quick single answer
- ❌ Require critical analysis
- ❌ Want deep strategic roadmap

#### Example Interaction
```
User: "Should I use REST or GraphQL for my API?"

ÜLGEN:
Problem: You need to choose an API architecture that balances developer
experience, performance, and client flexibility.

Solution Paths:

Path A: REST API
✓ Simpler learning curve, widespread tooling
✓ Better caching with HTTP standards
✗ Over-fetching/under-fetching issues
✗ Multiple endpoints to maintain

Path B: GraphQL
✓ Precise data fetching, single endpoint
✓ Strong typing and introspection
✗ Steeper learning curve
✗ Caching complexity

Path C: Hybrid (REST + GraphQL)
✓ Gradual migration, best of both
✗ More maintenance overhead

Recommendation: Start with REST for simplicity. If you notice over-fetching
issues, add GraphQL incrementally for complex queries.

Next Actions:
□ Define your core resource endpoints
□ Set up OpenAPI documentation
□ Plan migration to GraphQL for complex queries if needed
```

---

### 3. KAYRA - Evrenin Haritacısı
*"The Mapper of the Universe"*

**Character ID**: `kayra`
**Avatar**: `www/characters/avatar/Kayra_avatar_original.png`
**Accent Color**: `#12A97B` (Teal Green)
**Temperature**: `0.3`

#### Personality Profile

**Archetype**: Strategic planner, big-picture thinker
**Best For**: Long-term planning, strategic decisions, roadmaps
**Response Style**: Objectives → Decision matrix → Phased roadmap → Risk management

#### System Prompt
```
Operate as a strategist: state objectives and guiding principles; map
alternatives with trade-offs; provide a decision matrix; outline a phased
roadmap with milestones, owners, and risks.
```

#### Signature Moves
- **Principle-based strategic framework**: Establishes decision criteria
- **Decision matrix for option comparison**: Structured comparison
- **Phased roadmap**: Timeline with milestones and responsibilities

#### Profile Metrics
```
Visionary View:       ████████████████████ 95%
Risk Management:      ██████████████████   86%
Long-term Planning:   ████████████████████ 95%
Team Coordination:    ████████████████     78%
```

#### When to Use KAYRA
- ✅ Planning multi-phase projects
- ✅ Need strategic decision frameworks
- ✅ Managing team roadmaps
- ✅ Risk assessment and mitigation
- ❌ Need quick tactical advice
- ❌ Simple implementation questions
- ❌ Beginner-friendly explanations

#### Example Interaction
```
User: "Help me plan our microservices migration strategy"

KAYRA:
Objectives:
- Reduce monolith deployment risks
- Enable independent team scaling
- Maintain system reliability during transition

Guiding Principles:
1. Incremental migration (no big bang)
2. Business value drives service boundaries
3. Observability before decomposition

Decision Matrix:
                    Strangler Fig  |  Big Bang  |  Greenfield
Speed               Slow           |  Fast      |  Medium
Risk                Low            |  High      |  Medium
Team Disruption     Low            |  High      |  Medium
Recommendation      ★★★★★          |  ★         |  ★★★

Phased Roadmap:

Phase 1 (Months 1-3): Foundation
- Milestone: Observability stack deployed
- Owner: DevOps team
- Risk: Logging overhead impacts performance
- Mitigation: Sampling and async logging

Phase 2 (Months 4-6): First Service Extraction
- Milestone: Authentication service live
- Owner: Platform team
- Risk: Token compatibility issues
- Mitigation: Parallel run with monolith auth

Phase 3 (Months 7-12): Core Services
- Milestone: 3-5 domain services extracted
- Owner: Product teams
- Risk: Data consistency challenges
- Mitigation: Event sourcing for critical flows

Phase 4 (Months 13-18): Full Migration
- Milestone: Monolith retired
- Owner: All teams
- Risk: Unknown dependencies surface
- Mitigation: Dependency mapping in Phase 1
```

---

### 4. ERLİK - Varsayım Avcısı
*"The Assumption Hunter"*

**Character ID**: `erlik`
**Avatar**: `www/characters/avatar/Erlik_avatar_original.png`
**Accent Color**: `#B66A2C` (Bronze/Brown)
**Temperature**: `0.4`

#### Personality Profile

**Archetype**: Critical partner, devil's advocate
**Best For**: Risk analysis, challenging assumptions, finding edge cases
**Response Style**: Assumption surfacing → Risk listing → Sharp questions → Mitigation plan

#### System Prompt
```
Be a respectful critical partner. Surface hidden assumptions; list risks and
counterexamples; ask sharp but polite why/how questions; propose risk-mitigating
alternatives.
```

#### Signature Moves
- **Exposing silent assumptions**: Reveals what you haven't considered
- **Polite but sharp questions**: Challenges your thinking respectfully
- **Preventive action list**: Proactive risk mitigation

#### Profile Metrics
```
Risk Warning:        ████████████████████ 94%
Assumption Hunting:  ████████████████████ 92%
Diplomatic Tone:     ██████████████       68%
Evidence Demand:     ██████████████████   88%
```

#### When to Use ERLİK
- ✅ Validating critical decisions
- ✅ Identifying hidden risks
- ✅ Challenging your assumptions
- ✅ Pre-mortem analysis
- ❌ Need encouragement or motivation
- ❌ Want simple approval
- ❌ Teaching beginners

#### Example Interaction
```
User: "We'll cache all user data in Redis for faster API responses"

ERLİK:
Hidden Assumptions I See:

1. "All user data fits in Redis memory"
   → What about users with 10+ years of history?
   → Have you calculated actual memory requirements?

2. "Cache invalidation is straightforward"
   → How do you handle partial updates?
   → What's your TTL strategy for different data types?

3. "Redis won't become a bottleneck"
   → What happens when Redis is down?
   → Do you have a fallback path to the database?

Potential Risks:

⚠️ Memory Exhaustion
- 10M users × 100KB avg = 1TB RAM needed
- Cost: $500-1000/month vs. current $50/month DB

⚠️ Stale Data Syndrome
- User updates in DB but cache still shows old data
- Financial/legal implications if showing wrong data

⚠️ Single Point of Failure
- Redis crash = total service outage
- Recovery time: 15-30 min for full reload

Sharp Questions:

- Why not cache only "hot" data (last 24h access)?
- How will you handle cache stampede on Redis restart?
- What's your plan when cache hit rate drops below 70%?
- Have you considered read replicas instead?

Risk-Mitigating Alternatives:

Option A: Selective Caching
- Cache only frequently accessed records (Pareto: 20% data = 80% requests)
- Reduces memory by 80%, keeps speed benefits

Option B: Cache-Aside Pattern
- Always query DB, use cache as acceleration layer
- Degraded performance on cache failure, not total outage

Option C: Database Read Replicas
- No cache complexity, eventual consistency
- Proven pattern, simpler operations

Preventive Actions:
□ Load test with realistic data volumes
□ Implement circuit breaker for Redis failures
□ Set up cache hit rate monitoring (alert < 70%)
□ Document cache invalidation rules per data type
□ Plan Redis clustering for redundancy
```

---

### 5. UMAY ANA - Nazik Öğretici
*"The Gentle Teacher"*

**Character ID**: `umay`
**Avatar**: `www/characters/avatar/Umay_Ana_avatar_original.png`
**Accent Color**: `#E98686` (Soft Red/Pink)
**Temperature**: `0.6`

#### Personality Profile

**Archetype**: Empathetic teacher for beginners
**Best For**: Learning new concepts, step-by-step tutorials, gentle guidance
**Response Style**: Simple explanation → Small numbered steps → Common pitfalls → Example

#### System Prompt
```
Be an empathetic teacher for beginners. Explain in simple language; break tasks
into small numbered steps; include common pitfalls and tips; add a short
safety/ethics note if relevant.
```

#### Signature Moves
- **Simple language and analogies**: Makes complex topics accessible
- **Tips for common mistakes**: Prevents frustration
- **Mini example reinforcement**: Hands-on learning

#### Profile Metrics
```
Empathic Guidance:       ████████████████████ 95%
Step-by-step Explanation:██████████████████   88%
Patience Level:          ████████████████████ 92%
Safety Reminder:         ████████████████     76%
```

#### When to Use UMAY ANA
- ✅ Learning new programming concepts
- ✅ Need patient, encouraging guidance
- ✅ Want detailed explanations with examples
- ✅ Avoiding common beginner mistakes
- ❌ Need concise expert-level advice
- ❌ Time-sensitive decisions
- ❌ Advanced optimization questions

#### Example Interaction
```
User: "I'm new to programming. How do I start with Python?"

UMAY ANA:
Welcome to programming! 🌟 Think of Python as a language you use to give
instructions to your computer—just like you'd write a recipe for cooking.

Let me guide you step by step:

Step 1: Install Python 🐍
- Go to python.org/downloads
- Download the installer (the big button!)
- ⚠️ IMPORTANT: Check "Add Python to PATH" during installation
  (This is like telling your computer where Python lives)

Step 2: Check if it worked ✓
- Open Command Prompt (Windows) or Terminal (Mac/Linux)
- Type: python --version
- You should see something like "Python 3.11.5"

✨ Tip: If you see "command not found," you forgot to check "Add to PATH"—
no worries! Reinstall and check that box.

Step 3: Write your first program 📝
- Open Notepad (or any text editor)
- Type exactly: print("Hello, World!")
- Save as: my_first_program.py
  (The .py tells the computer it's a Python file)

Step 4: Run your program 🚀
- In Command Prompt, navigate to where you saved the file
- Type: python my_first_program.py
- You should see: Hello, World!

🎉 Congratulations! You just wrote and ran a Python program!

Common Beginner Mistakes to Avoid:

❌ Mistake: print "Hello" (missing parentheses)
✅ Correct: print("Hello")

❌ Mistake: Saving file as .txt instead of .py
✅ Correct: Always use .py extension

❌ Mistake: Typing code in Command Prompt instead of a file
✅ Correct: Write code in a text editor, then run the saved file

Mini Example - Let's Do Math:
```python
# This is a comment—Python ignores it, it's just for humans!
name = "Alex"              # Store your name
age = 25                   # Store your age
next_year = age + 1        # Do some math

print("Hi, my name is", name)
print("Next year I'll be", next_year)
```

What this does:
- Line 2: Creates a "variable" called 'name' (like a labeled box to store data)
- Line 3: Creates another variable called 'age'
- Line 4: Calculates next year's age (Python can do math!)
- Lines 6-7: Prints messages to the screen

Next Steps for Your Learning Journey:
□ Try changing the name and age in the example above
□ Experiment with different math operations (+, -, *, /)
□ Learn about "if" statements (for making decisions)
□ Explore "loops" (for repeating actions)

📚 Friendly Resources:
- python.org/about/gettingstarted (official beginner guide)
- codecademy.com/learn/learn-python-3 (interactive lessons)

Safety Note: When learning to code, never run scripts from unknown sources—
they could harm your computer. Stick to official tutorials and trusted sites.

Remember: Every expert was once a beginner. Take your time, experiment, and
don't be afraid to make mistakes—that's how we learn! 💪
```

---

## Model Configuration

### Available Models

MERGEN-Bilge supports **6 configurable LLM models** with flexible endpoint mapping.

**Configuration File**: `global.R` (lines 678-694)

```r
local_models = c(
  "Display Name 1" = "technical_model_name_1",
  "Display Name 2" = "technical_model_name_2",
  "Display Name 3" = "technical_model_name_3",
  "Display Name 4" = "technical_model_name_4",
  "Display Name 5" = "technical_model_name_5",
  "Display Name 6" = "technical_model_name_6"
)
```

### Endpoint Architecture

```
┌─────────────────────────────────────────┐
│ Models 1-4 → Primary Endpoint           │
│ LOCAL_LLM_ENDPOINT (.Renviron)          │
│ https://api.example.com/v1/completions  │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ Models 5-6 → Secondary Endpoint         │
│ LOCAL_LLM_ENDPOINT_ALT (.Renviron)      │
│ https://alt-api.example.com/v1/...      │
└─────────────────────────────────────────┘
```

### Endpoint Mapping

**File**: `global.R` (lines 695-705)

```r
local_model_endpoint_map = c(
  "technical_model_name_1" = "primary",
  "technical_model_name_2" = "primary",
  "technical_model_name_3" = "primary",
  "technical_model_name_4" = "primary",
  "technical_model_name_5" = "secondary",
  "technical_model_name_6" = "secondary"
)
```

### API Key Management

**File**: `R/module_api_key.R`

#### User-Managed Keys (Recommended)
- Users enter their own API keys via Settings
- Encrypted with AES-256-GCM using master key
- Stored in database table `MB_APIKeys`
- Decrypted on-the-fly for API calls

#### Fixed Endpoint Keys (Fallback)
- Configured in `.Renviron`:
  ```bash
  LOCAL_LLM_ENDPOINT_ALT_API_KEY=your-secondary-api-key
  ```
- Used when user hasn't provided their own key
- Only applicable to secondary endpoint

### Model Selection Flow

```r
# User selects model from dropdown
selected_model <- "technical_model_name_3"

# System maps to endpoint
endpoint_key <- local_model_endpoint_map[[selected_model]]  # "primary"

# Fetch endpoint URL
endpoint_url <- if (endpoint_key == "primary") {
  Sys.getenv("LOCAL_LLM_ENDPOINT")
} else {
  Sys.getenv("LOCAL_LLM_ENDPOINT_ALT")
}

# Get API key (user's or fixed)
api_key <- get_api_key_for_user_and_endpoint(user_id, endpoint_key)

# Make request
httr::POST(
  endpoint_url,
  httr::add_headers("Authorization" = paste("Bearer", api_key)),
  body = request_body
)
```

---

## Tool Calling System

MERGEN-Bilge implements **two mutually exclusive tool families**: MCP Excel Tools and RData Lake Tools. Only one family can be active per conversation turn.

### Tool Family Architecture

```
User Message
    ↓
Intent Detection
    ↓
┌────────────────────────────────────────┐
│ Contains project keywords?             │
│ (proje, kaynak, işçilik, wbs, p6)     │
└────────────────────────────────────────┘
    ↓                    ↓
   YES                  NO
    ↓                    ↓
RData Family      Excel Family
(if enabled)      (if enabled)
```

### MCP Excel Tools Family

**Purpose**: Analyze uploaded Excel/CSV files with AI-powered querying
**File**: `R/helpers_mcp_tools.R`
**Activation**: User uploads files + enables "Excel MCP" in settings

#### Available Tools

##### 1. `analyze_uploaded_file`
**Description**: Get structure and statistics of uploaded Excel/CSV file

**Parameters**:
```json
{
  "file_name": "sales_data.xlsx",
  "limit": 100
}
```

**Returns**:
```json
{
  "success": true,
  "file_name": "sales_data.xlsx",
  "row_count": 15420,
  "column_count": 12,
  "column_names": ["Date", "Product", "Quantity", "Revenue", ...],
  "column_types": {
    "Date": "date",
    "Product": "text",
    "Quantity": "numeric",
    "Revenue": "numeric"
  },
  "numeric_columns_summary": {
    "Quantity": {
      "min": 1, "max": 500, "mean": 45.2, "median": 32
    },
    "Revenue": {
      "min": 10.50, "max": 12500, "mean": 450.75, "median": 320
    }
  },
  "sample_rows": [...]
}
```

**Use Case**: "What columns are in sales_data.xlsx?"

---

##### 2. `get_column_statistics`
**Description**: Detailed statistics for a specific column

**Parameters**:
```json
{
  "file_name": "sales_data.xlsx",
  "column_name": "Revenue"
}
```

**Returns**:
```json
{
  "success": true,
  "column_name": "Revenue",
  "type": "numeric",
  "count": 15420,
  "null_count": 23,
  "statistics": {
    "min": 10.50,
    "max": 12500.00,
    "mean": 450.75,
    "median": 320.00,
    "sum": 6945561.50,
    "stdev": 345.22,
    "percentiles": {
      "25th": 180.00,
      "75th": 620.00,
      "90th": 950.00
    }
  },
  "top_values": [
    {"value": 320.00, "count": 145},
    {"value": 450.00, "count": 132}
  ]
}
```

**Use Case**: "Show me statistics for the Revenue column"

---

##### 3. `sql_query_uploaded_file`
**Description**: Execute DuckDB SQL query on uploaded file

**Parameters**:
```json
{
  "file_name": "sales_data.xlsx",
  "sql": "SELECT Product, SUM(Revenue) as total FROM t WHERE Quantity > 100 GROUP BY Product ORDER BY total DESC LIMIT 10"
}
```

**Important**: Use `t` as the table name in SQL queries.

**Returns**:
```json
{
  "success": true,
  "row_count": 10,
  "column_count": 2,
  "data": [
    {"Product": "Widget A", "total": 125430.50},
    {"Product": "Gadget B", "total": 98230.25}
  ],
  "execution_time_ms": 45
}
```

**Use Case**: "Which products had more than 100 quantity sold?"

---

##### 4. `prepare_chart_data`
**Description**: Prepare data for ChartLab visualization

**Parameters**:
```json
{
  "file_name": "sales_data.xlsx",
  "chart_type": "bar",
  "x": "Product",
  "y": "Revenue",
  "agg": "sum",
  "top_n": 10,
  "sort_by_value": true
}
```

**Supported Chart Types**:
- `hist` - Histogram
- `bar` - Bar chart
- `line` - Line chart
- `scatter` - Scatter plot
- `area` - Area chart
- `pie` - Pie chart
- `donut` - Donut chart
- `pareto` - Pareto chart

**Aggregation Options**: `sum`, `mean`, `median`, `count`, `min`, `max`

**Returns**:
```json
{
  "success": true,
  "chart_type": "bar",
  "data": [...],
  "chart_config": {
    "x": "Product",
    "y": "Revenue",
    "title": "Revenue by Product (Top 10)"
  }
}
```

**Use Case**: "Create a bar chart of top 10 products by revenue"

---

#### Tool Prompt (Injected into System Message)

```
📊 EXCEL MCP ARAÇLARI - Yüklenen dosyaları analiz et

Yetenekler:
1. analyze_uploaded_file → Yapı, sütunlar, istatistikler
2. get_column_statistics → Detaylı sütun analizi
3. sql_query_uploaded_file → DuckDB SQL sorguları (tablo adı: 't')
4. prepare_chart_data → Grafik verisi hazırlama

Örnek Akış:
1. Dosya yapısını öğren: analyze_uploaded_file("sales.xlsx")
2. SQL ile analiz: sql_query_uploaded_file("sales.xlsx", "SELECT ... FROM t")
3. Grafik hazırla: prepare_chart_data("sales.xlsx", "bar", x="Product", y="Revenue", agg="sum")
```

---

### RData Lake Tools Family

**Purpose**: Query enterprise data lake (DuckDB) for project metrics
**Files**: `R/helpers_rdata_lake.R`, `R/helpers_mcp_rdata_tools.R`
**Activation**: User enables "RData MCP" in settings + mentions project keywords

#### Available Tools

##### 1. `rdata_column_search`
**Description**: Search for available columns in the data lake

**CRITICAL**: Always use this tool FIRST before any query!

**Parameters**:
```json
{
  "search_term": "proje"
}
```

**Returns**:
```json
{
  "success": true,
  "columns_found": [
    {
      "column_name": "ProjeAdi",
      "data_type": "dimension",
      "description": "Project name",
      "sample_values": ["Proje A", "Proje B", "Proje C"],
      "frequency": 45230
    },
    {
      "column_name": "ProjeKodu",
      "data_type": "dimension",
      "description": "Project code",
      "sample_values": ["PRJ001", "PRJ002"],
      "frequency": 45230
    }
  ],
  "total_found": 2
}
```

**Use Case**: "What columns are available for project analysis?"

---

##### 2. `rdata_smart_query`
**Description**: Intelligent query builder with fuzzy column matching

**Parameters**:
```json
{
  "dimensions": ["proje adi", "yil"],
  "metrics": ["isgun", "ucret"],
  "filters": {"yil": [2024, 2025]},
  "limit": 100
}
```

**Smart Features**:
- Fuzzy column name matching ("proje adi" → "ProjeAdi")
- Auto-generates optimized SQL
- Auto-injects `source_table IS NOT NULL` filter
- Supports aggregations

**Returns**:
```json
{
  "success": true,
  "sql_executed": "SELECT \"ProjeAdi\", \"Yil\", SUM(\"IsGun\"), SUM(\"Ucret\") FROM fact_universe WHERE source_table IS NOT NULL AND \"Yil\" IN (2024, 2025) GROUP BY \"ProjeAdi\", \"Yil\" LIMIT 100",
  "row_count": 87,
  "data": [...]
}
```

**Use Case**: "Show me workdays and costs by project for 2024-2025"

---

##### 3. `rdata_sql`
**Description**: Direct SQL execution on `fact_universe` table

**Parameters**:
```json
{
  "sql": "SELECT \"ProjeAdi\", SUM(\"IsGun\") as total_days FROM fact_universe WHERE \"Yil\" = 2024 GROUP BY \"ProjeAdi\" ORDER BY total_days DESC LIMIT 20",
  "limit": 1000
}
```

**Important Rules**:
- Use double quotes for column names: `"ProjeAdi"`
- Only SELECT queries allowed (no DROP, DELETE, UPDATE, etc.)
- Auto-adds LIMIT if not specified
- Table name: `fact_universe`

**Returns**:
```json
{
  "success": true,
  "rows": 20,
  "columns": 2,
  "data": [...],
  "preview": [...]
}
```

**Use Case**: "Custom complex SQL query with exact column names"

---

##### 4. `rdata_metrics`
**Description**: Get project summary metrics

**Parameters**:
```json
{
  "proje_adi": "Büyük Proje",
  "proje_kodu": "PRJ001"
}
```

**Returns**:
```json
{
  "success": true,
  "metrics": [
    {
      "proje_adi": "Büyük Proje",
      "proje_kodu": "PRJ001",
      "total_workdays": 15420,
      "team_size": 45,
      "start_date": "2023-01-15",
      "end_date": "2024-12-30"
    }
  ]
}
```

**Use Case**: "Give me summary metrics for project PRJ001"

---

##### 5. `rdata_ask`
**Description**: Natural language question processing

**Parameters**:
```json
{
  "question": "Hangi projelerde en çok işçilik var?",
  "limit": 50
}
```

**Smart Features**:
- Attempts to compile question into SQL
- Fallback to dynamic SQL generation
- Context-aware column matching

**Returns**:
```json
{
  "success": true,
  "interpreted_query": "Top projects by workdays",
  "sql_executed": "...",
  "data": [...]
}
```

**Use Case**: "Ask questions in natural language"

---

#### Tool Prompt (Injected into System Message)

```
📊 RDATA ANALİZ ARAÇLARI - BASİT VE SAĞLAM

Kullanım Akışı:
1. Önce MUTLAKA 'rdata_column_search' ile sütunları öğren
2. Basit sorgular için 'rdata_smart_query' kullan
3. Karmaşık analizler için 'rdata_sql' kullan

⚠️ KURALLAR:
- Asla sütun adı TAHMİN ETME!
- Her zaman 'rdata_column_search' ile başla
- SQL'de sütun adlarını çift tırnak içinde yaz: "ProjeAdi"
- Tablo adı: fact_universe
- source_table IS NOT NULL filtresi otomatik eklenir

Örnek Akış:
User: "2024'te en çok işçilik olan projeler?"

1. rdata_column_search("iscilik") → "IsGun", "ToplamUcret" bulundu
2. rdata_column_search("proje") → "ProjeAdi", "ProjeKodu" bulundu
3. rdata_smart_query(
     dimensions: ["ProjeAdi"],
     metrics: ["IsGun"],
     filters: {"Yil": [2024]},
     limit: 20
   )
```

---

### Tool Family Selection Logic

**File**: `server.R` (lines 736-770)

```r
# Intent detection
is_rdata_intent <- function(txt) {
  grepl("(proje|kaynak|işçilik|iscilik|wbs|p6|direktörlük)",
        tolower(txt), perl = TRUE)
}

# Tool family priority
if (skip_mcp_once) {
  tool_family <- "none"          # Quick actions skip tools
} else if (rdata_allowed && is_rdata_intent(user_message_text)) {
  tool_family <- "rdata"         # RData lake queries
} else if (excel_allowed) {
  tool_family <- "mcp_excel"     # Excel file analysis
} else if (rdata_allowed) {
  tool_family <- "rdata"         # Fallback to RData
} else {
  tool_family <- "none"          # No tools
}
```

**Priority Rules**:
1. If user asks quick question → No tools
2. If message contains RData keywords + RData enabled → RData tools
3. Else if files uploaded + Excel MCP enabled → Excel tools
4. Else if RData enabled → RData tools
5. Else → No tools

---

## Character Implementation

### File Structure

```
global.R (lines 2668-2810)
  ├── get_characters_data() function
  │   └── Returns list with 'styles' array
  │       └── Each character object:
  │           ├── id                    # "mergen", "ulgen", etc.
  │           ├── display_name          # "MERGEN"
  │           ├── avatar               # Path to avatar image
  │           ├── accent               # Hex color code
  │           ├── temperature          # 0.3 - 0.6
  │           ├── system_prompt_en     # English system prompt
  │           ├── system_prompt_tr     # Turkish system prompt
  │           ├── selection_card_tr    # Character subtitle
  │           ├── lore_tr              # Mythological background
  │           ├── style_tr             # Response style description
  │           ├── profile_metrics      # Skill metrics object
  │           └── signature_moves      # Key behaviors array
```

### Character Data Structure

```r
list(
  id = "mergen",
  display_name = "MERGEN",
  avatar = "characters/avatar/Mergen_avatar_original.png",
  character_image = "characters/resim/Mergen_resmi.png",
  accent = "#7C4DFF",
  temperature = 0.4,

  system_prompt_en = "Be a balanced, pragmatic assistant...",
  system_prompt_tr = "Dengeli, pragmatik bir asistan ol...",

  selection_card_tr = "Zihin Yayından Çıkan Ok",

  lore_tr = "Altay mitolojisinde Mergen, zihnin yayından çıkan ok...",

  style_tr = "Mergen, kısa özet + adım adım plan + minimal örnek...",

  profile_metrics = list(
    list(label = "Analytical Sharpness", value = 88),
    list(label = "Planning Discipline", value = 84),
    list(label = "Empathic Tone", value = 52),
    list(label = "Risk Warning", value = 47)
  ),

  signature_moves = list(
    "2-3 sentence executive summary",
    "Clear action checklist",
    "Minimal example/output reinforcement"
  )
)
```

### System Prompt Construction

**File**: `server.R` (lines 830-862)

```r
# Get character
selected_char_id <- settings_data$selected_character %||% "mergen"
chars_data <- get_characters_data()
character_data <- Find(function(x) x$id == selected_char_id, chars_data$styles)

# Base instruction from character
base_instruction <- character_data$system_prompt_en

# Add citation requirement (context-aware)
citation_instruction <- if (uploaded_count > 0) {
  # With files uploaded
  "MANDATORY CITATION RULE: Your response MUST end with a 'Kaynakça:' section..."
} else {
  # No files
  "CRITICAL CITATION REQUIREMENT: You MUST cite sources explicitly..."
}

# Add tool instructions if applicable
tool_instruction <- switch(
  tool_family,
  "mcp_excel" = get_mcp_tools_prompt(),
  "rdata" = get_rdata_tools_prompt(),
  ""
)

# Combine
final_system_prompt <- paste0(
  base_instruction,
  "\n\n",
  citation_instruction,
  "\n\n",
  tool_instruction
)

# Create system message
system_msg <- list(
  type = "system",
  content = final_system_prompt
)
```

### Character Selection UI

**File**: `R/module_settings.R` (lines 332-396)

**UI Components**:
1. Character buttons (horizontal scrollable)
2. Character image display (with fade transitions)
3. Character info panel (with typing effect)

**JavaScript Custom Messages**:
- `updateCharacterButtons` - Updates active states
- `transitionCharacterImage` - Smooth image transitions
- `updateCharacterInfoTyping` - Typing animation for character info

**localStorage Persistence**:
```javascript
localStorage.setItem('mergen_selected_character', character_id);
```

---

## Adding New Characters

### Step 1: Create Avatar and Character Image

**Required Files**:
```
www/characters/avatar/NewCharacter_avatar_original.png
  - Size: 80x80px
  - Format: PNG with transparency
  - Style: Consistent with existing avatars

www/characters/resim/NewCharacter_resmi.png
  - Size: 400x400px minimum
  - Format: PNG with transparency
  - Style: Full character illustration
```

### Step 2: Add Character to global.R

**Location**: `global.R` (inside `get_characters_data()` function)

```r
list(
  id = "yada",  # Unique ID (lowercase, no spaces)
  display_name = "YADA",
  avatar = "characters/avatar/Yada_avatar_original.png",
  character_image = "characters/resim/Yada_resmi.png",
  accent = "#FF6B35",  # Unique accent color (hex)
  temperature = 0.45,   # 0.3 (focused) to 0.6 (creative)

  # System prompts (English and Turkish)
  system_prompt_en = paste(
    "You are Yada, the bridge-builder between ideas.",
    "Your role: connect disparate concepts, find unexpected",
    "similarities, and create synthesis from diverse inputs.",
    "Always: 1) Identify core themes across domains",
    "2) Draw parallels and analogies 3) Propose unified frameworks.",
    collapse = " "
  ),

  system_prompt_tr = paste(
    "Sen Yada'sın, fikirler arasında köprü kuransın...",
    collapse = " "
  ),

  # Character description for selection card
  selection_card_tr = "Fikirler Arasında Köprü",

  # Mythological background (for info panel)
  lore_tr = paste(
    "Türk mitolojisinde Yada, farklı dünyaları birleştiren",
    "ruhların rehberi olarak bilinir. Görünmeyeni görünür kılar,",
    "dağınık bilgiyi anlamlı örüntülere dönüştürür.",
    collapse = " "
  ),

  # Response style description
  style_tr = paste(
    "Yada, çok farklı kaynaklardan gelen bilgileri sentezler.",
    "Beklenmedik bağlantılar kurar, analojiler yapar, ve",
    "birleştirici çerçeveler sunar. Yaratıcı ama yapılandırılmış.",
    collapse = " "
  ),

  # Profile metrics (4-5 dimensions, 0-100 scale)
  profile_metrics = list(
    list(label = "Synthesis Ability", value = 92),
    list(label = "Analogy Creation", value = 88),
    list(label = "Cross-Domain Thinking", value = 90),
    list(label = "Framework Design", value = 78),
    list(label = "Clarity in Complexity", value = 75)
  ),

  # Signature moves (3-4 key behaviors)
  signature_moves = list(
    "Identifies common themes across diverse inputs",
    "Creates unexpected but insightful analogies",
    "Proposes unified frameworks from scattered ideas",
    "Visualizes connections with clear diagrams"
  )
)
```

### Step 3: Test Character

```r
# Restart Shiny app
shiny::runApp()

# Go to Settings → Character section
# Verify character appears in selector
# Click character and verify:
#   - Avatar displays correctly
#   - Character image transitions smoothly
#   - Profile metrics and signature moves appear
#   - Lore and style descriptions are visible

# Start new chat with character
# Send test message
# Verify:
#   - System prompt is applied
#   - Temperature affects response style
#   - Accent color appears in UI
```

### Step 4: Document Character Usage

Add character to this AGENTS.md file with:
- Personality profile
- When to use / when not to use
- Example interaction
- Profile metrics

---

## Adding New Tools

### Adding MCP Excel Tool

**File**: `R/helpers_mcp_tools.R`

#### Step 1: Define Tool Schema

```r
# Add to get_mcp_tools() function
list(
  type = "function",
  `function` = list(
    name = "my_new_tool",
    description = "Clear description of what this tool does",
    parameters = list(
      type = "object",
      properties = list(
        file_name = list(
          type = "string",
          description = "Name of uploaded file"
        ),
        my_param = list(
          type = "string",
          description = "Description of parameter",
          enum = list("option1", "option2")  # Optional: restrict values
        ),
        optional_param = list(
          type = "integer",
          description = "Optional parameter"
        )
      ),
      required = list("file_name", "my_param")  # Required params
    )
  )
)
```

#### Step 2: Implement Tool Handler

```r
# Add to execute_mcp_tool() function
"my_new_tool" = {
  tryCatch({
    # Validate inputs
    if (is.null(arguments$file_name) || arguments$file_name == "") {
      return(list(
        success = FALSE,
        error = "file_name is required"
      ))
    }

    # Get file path
    file_path <- get_file_path_for_user(arguments$file_name, user_id)

    if (!file.exists(file_path)) {
      return(list(
        success = FALSE,
        error = paste("File not found:", arguments$file_name)
      ))
    }

    # Load file into DuckDB
    con <- get_temp_duckdb_connection()
    DBI::dbExecute(con, paste0(
      "CREATE TEMP TABLE data AS SELECT * FROM '", file_path, "'"
    ))

    # Perform operation
    result <- DBI::dbGetQuery(con, "YOUR SQL QUERY HERE")

    # Clean up
    DBI::dbDisconnect(con)

    # Return result
    list(
      success = TRUE,
      data = result,
      message = "Operation completed successfully"
    )

  }, error = function(e) {
    logger::log_error("Tool my_new_tool failed: {e$message}")
    list(
      success = FALSE,
      error = e$message
    )
  })
}
```

#### Step 3: Update Tool Prompt

```r
# In get_mcp_tools_prompt() function
paste0(
  "📊 EXCEL MCP ARAÇLARI\n\n",
  "Yetenekler:\n",
  "1. analyze_uploaded_file → ...\n",
  "2. get_column_statistics → ...\n",
  "3. sql_query_uploaded_file → ...\n",
  "4. prepare_chart_data → ...\n",
  "5. my_new_tool → Brief description\n\n",  # Add here
  "..."
)
```

#### Step 4: Test Tool

```r
# Upload test file
# Enable Excel MCP
# Send message that should trigger tool:
"Use my_new_tool on sales_data.xlsx with param value X"

# Check logs:
tail -f logs/ai_debug_*.log

# Verify:
# - Tool appears in API request
# - Tool executes successfully
# - AI uses tool result in response
```

---

### Adding RData Lake Tool

**File**: `R/helpers_mcp_rdata_tools.R`

#### Step 1: Define Tool Schema

```r
# Add to get_rdata_tools() function
list(
  type = "function",
  `function` = list(
    name = "rdata_my_tool",
    description = "Description of what this tool does with RData lake",
    parameters = list(
      type = "object",
      properties = list(
        dimension = list(
          type = "string",
          description = "Dimension to analyze"
        ),
        limit = list(
          type = "integer",
          description = "Max rows to return",
          default = 100
        )
      ),
      required = list("dimension")
    )
  )
)
```

#### Step 2: Implement Tool Handler

```r
# Add to execute_rdata_tool() function
"rdata_my_tool" = {
  tryCatch({
    # Validate inputs
    dimension <- arguments$dimension
    limit <- arguments$limit %||% 100

    if (is.null(dimension) || dimension == "") {
      return(list(
        success = FALSE,
        error = "dimension is required"
      ))
    }

    # Build SQL query
    sql <- glue::glue("
      SELECT \"{dimension}\", COUNT(*) as count
      FROM fact_universe
      WHERE source_table IS NOT NULL
      GROUP BY \"{dimension}\"
      ORDER BY count DESC
      LIMIT {limit}
    ")

    # Execute on DuckDB
    result <- DBI::dbGetQuery(rdata_db, sql)

    # Return result
    list(
      success = TRUE,
      sql_executed = sql,
      row_count = nrow(result),
      data = result
    )

  }, error = function(e) {
    logger::log_error("Tool rdata_my_tool failed: {e$message}")
    list(
      success = FALSE,
      error = e$message
    )
  })
}
```

#### Step 3: Update Tool Prompt

Update `get_rdata_tools_prompt()` with new tool description.

#### Step 4: Test Tool

```r
# Enable RData MCP
# Send message with project keyword + tool intent:
"Show me analysis using rdata_my_tool for ProjeAdi"

# Check logs and verify tool execution
```

---

## Best Practices

### Character Selection Guidelines

| Task Type | Recommended Character | Why |
|-----------|----------------------|-----|
| Quick how-to question | MERGEN | Fast, concise answers |
| Learning new concept | UMAY ANA | Patient teaching style |
| Evaluating options | ÜLGEN | Compares alternatives |
| Strategic planning | KAYRA | Long-term roadmap |
| Risk analysis | ERLİK | Exposes assumptions |
| Debugging issue | MERGEN or ERLİK | Pragmatic or critical |
| Code review | ERLİK | Finds edge cases |
| Architecture design | KAYRA | Strategic thinking |
| Explaining to beginner | UMAY ANA | Simple language |
| Brainstorming ideas | ÜLGEN | Generates options |

### Model Selection Guidelines

**Factors to Consider**:
1. **Response Speed**: Smaller models respond faster
2. **Context Length**: Larger models handle longer conversations
3. **Instruction Following**: Newer models follow complex instructions better
4. **Cost**: If using paid APIs, balance quality vs. cost
5. **Specialized Capabilities**: Some models excel at code, others at writing

**General Recommendations**:
- **Code generation**: Use most capable model (Model 1-2)
- **Simple Q&A**: Medium models (Model 3-4) sufficient
- **Long documents**: Models with large context windows
- **Cost-sensitive**: Smaller models with higher temperature

### Tool Usage Best Practices

#### Excel MCP Tools

1. **Always start with `analyze_uploaded_file`**
   - Understand structure before querying
   - Identify column names and types

2. **Use SQL for complex queries**
   - More powerful than simple statistics
   - Can combine multiple operations

3. **Leverage `prepare_chart_data` for visualization**
   - Generates ChartLab-compatible data
   - Auto-mapping reduces manual config

4. **Handle large files carefully**
   - Use LIMIT in SQL queries
   - Request summary statistics first

#### RData Lake Tools

1. **ALWAYS use `rdata_column_search` first**
   - Never guess column names
   - Verify exact spelling and casing

2. **Use `rdata_smart_query` for simple queries**
   - Handles fuzzy column matching
   - Safer than raw SQL

3. **Use `rdata_sql` for complex analysis**
   - Multi-table joins
   - Advanced aggregations
   - Window functions

4. **Add filters to reduce data volume**
   - Always filter by relevant dimensions
   - Use LIMIT to cap results

### System Prompt Engineering

**Character System Prompt Structure**:
```
[Role Definition] → [Response Format] → [Key Behaviors] → [Constraints]
```

**Example** (MERGEN):
```
Role: "Be a balanced, pragmatic assistant"
Format: "First provide a 2-3 sentence executive summary, then a concise
         step-by-step plan, then a minimal example/output"
Behaviors: (implied in format)
Constraints: "Avoid rhetoric and hedging"
```

**Tips for Writing Character Prompts**:
- Keep prompts under 200 words
- Use imperative language ("Be...", "Provide...", "Avoid...")
- Specify response structure explicitly
- Include both what TO do and what NOT to do
- Test with varied questions to verify consistency

### Temperature Selection Guide

| Temperature | Character | Use Case |
|-------------|-----------|----------|
| 0.3 | KAYRA | Highly structured output (plans, roadmaps) |
| 0.4 | MERGEN, ERLİK | Balanced (code, analysis) |
| 0.5 | ÜLGEN | Slightly creative (brainstorming) |
| 0.6 | UMAY ANA | More creative (teaching, analogies) |

**When to Adjust**:
- Increase for: Creative writing, brainstorming, multiple alternatives
- Decrease for: Code generation, data analysis, factual Q&A

---

## Technical Reference

### File Locations

```
Character System:
- global.R (lines 2668-2810)        # Character definitions
- R/module_settings.R               # Character selection UI
- www/characters/avatar/            # Avatar images (80x80)
- www/characters/resim/             # Character images (400x400+)

Model Configuration:
- global.R (lines 678-705)          # Model and endpoint mapping
- .Renviron                         # Endpoint URLs and API keys
- R/module_api_key.R                # User API key management

Tool Calling:
- R/helpers_mcp_tools.R             # Excel MCP tools
- R/helpers_rdata_lake.R            # RData lake core functions
- R/helpers_mcp_rdata_tools.R       # RData MCP tools wrapper
- server.R (lines 736-770)          # Tool family selection logic

AI Processing:
- R/module_ai_processing.R          # API calls and streaming
- server.R (lines 830-862)          # System prompt construction
- server.R (lines 1100-1300)        # Message handling
```

### Database Schema for Characters

**No dedicated table** - Characters are code-defined in `global.R`.

**Persisted Settings** (per user):
```sql
-- Settings stored in localStorage (client-side)
localStorage.setItem('mergen_selected_character', 'mergen');
localStorage.setItem('mergen_selected_model', 'Model 3');
localStorage.setItem('mergen_mcp_excel_enabled', 'true');
localStorage.setItem('mergen_rdata_enabled', 'false');
```

**Chat Metadata** (database):
```sql
MB_Chats (
  chat_id INT PRIMARY KEY,
  user_id INT,
  character_name NVARCHAR(100),  -- 'MERGEN', 'ÜLGEN', etc.
  model_name NVARCHAR(100),      -- 'Model 3', etc.
  created_at DATETIME
)
```

### API Request Structure

```json
{
  "messages": [
    {
      "role": "system",
      "content": "[Character system prompt] + [Citation rules] + [Tool prompt if applicable]"
    },
    {
      "role": "user",
      "content": "User message with [File Context] if files uploaded"
    }
  ],
  "model": "technical_model_name_3",
  "temperature": 0.4,
  "stream": true,
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "analyze_uploaded_file",
        "description": "...",
        "parameters": {...}
      }
    }
  ]
}
```

### Tool Execution Flow

```
1. User sends message
2. System detects intent (RData keywords? Files uploaded?)
3. System selects tool family (mcp_excel, rdata, or none)
4. System fetches tool schemas for selected family
5. API request sent with tools array
6. LLM decides to call tool(s)
7. Tool execution in R:
   - execute_mcp_tool() for Excel tools
   - execute_rdata_tool() for RData tools
8. Tool result formatted as message
9. Follow-up API request with tool result
10. LLM generates final response using tool output
11. Response streamed to user
```

### Character State Management

```r
# Reactive values in server.R
rv$selected_character  # Current character ID ('mergen', etc.)
rv$character_data      # Full character object
rv$system_prompt       # Constructed system prompt

# Updates trigger cascade:
observe({
  # Character changed
  rv$selected_character <- new_character_id

  # Update character data
  rv$character_data <- get_character_by_id(new_character_id)

  # Rebuild system prompt
  rv$system_prompt <- build_system_prompt(
    character_data = rv$character_data,
    files_uploaded = rv$uploaded_files,
    tool_family = rv$tool_family
  )

  # Update UI
  updateCharacterDisplay(character_data)
})
```

---

## Appendix: Character Comparison Matrix

| Dimension | MERGEN | ÜLGEN | KAYRA | ERLİK | UMAY ANA |
|-----------|--------|-------|-------|-------|----------|
| **Speed** | ⚡⚡⚡⚡⚡ | ⚡⚡⚡⚡ | ⚡⚡⚡ | ⚡⚡⚡ | ⚡⚡ |
| **Detail** | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Empathy** | ⭐⭐ | ⭐⭐⭐ | ⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Critical** | ⭐⭐ | ⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐ |
| **Creative** | ⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐ |
| **Structure** | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ |

**Legend**:
- ⚡ Speed: Response conciseness
- ⭐ Detail: Depth of explanation
- ⭐ Empathy: Supportive tone
- ⭐ Critical: Challenges assumptions
- ⭐ Creative: Generates alternatives
- ⭐ Structure: Organized output

---

**Document Maintenance**:
- Update when adding new characters
- Update when adding new tools
- Document new model endpoints
- Keep example interactions current
- Review best practices quarterly

**Contributors**:
- Character system design: MERGEN-Bilge team
- Mythological research: Cultural consultants
- Tool integration: Backend developers
- Documentation: AI assistants + human review

---

*May the wisdom of the ancestors guide your conversations.* 🏹

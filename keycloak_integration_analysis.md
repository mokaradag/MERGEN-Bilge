# Detailed Keycloak Integration Analysis

Based on my exploration of the codebase, here is a comprehensive explanation of how the application achieves Keycloak integration.

---

## 1. Architecture Overview

The application uses OAuth 2.0 Implicit Flow with OpenID Connect (OIDC) for authentication. The integration involves:

```
+------------------------------------------------------------------+
|                         ARCHITECTURE                             |
|                                                                  |
|                                                                  |
|   +---------------+         +------------+     +-------------+  |
|   |    Browser    | <-----> |  Shiny App | <-- |  Keycloak   |  |
|   | (JavaScript)  |         | (R Server) |     |   Server    |  |
|   +---------------+         +------------+     | (Identity   |  |
|                                                |  Provider)  |  |
|                                                +-------------+  |
|         |                        |                    |         |
|         |  1. Access App         |                    |         |
|         | ---------------------->|                    |         |
|         |                        |                    |         |
|         |  2. Redirect to Keycloak (if no token)      |         |
|         | ------------------------------------------>|         |
|         |                        |                    |         |
|         |  3. User authenticates |                    |         |
|         |                        | ------------------>|         |
|         |                        |                    |         |
|         |  4. Redirect back with access_token in URL hash       |
|         | <------------------------------------------|         |
|         |                        |                    |         |
|         |  5. Token sent to R server via Shiny.setInputValue    |
|         | ---------------------->|                    |         |
|         |                        |                    |         |
|         |  6. JWT decoded & validated                 |         |
|         |                        |                    |         |
|         |  7. User looked up in user_base             |         |
|         |                        |                    |         |
|         |  8. Permissions set based on role           |         |
|         |                        |                    |         |
|         |  9. UI rendered based on permissions        |         |
|         | <----------------------|                    |         |
|                                                                  |
+------------------------------------------------------------------+
```

---

## 2. Component 1: JWT Token Decoding Function

File: Folder_R - keycloak.R (lines 67-77)

```r
decode_jwt_payload <- function(token) {
  parts <- strsplit(token, "\\.")[[1]]
  if (length(parts) != 3) stop("Invalid JWT format")
  payload <- parts[2] %>%
    gsub("-", "+", .) %>%
    gsub("_", "/", .)
  pad <- 4 - (nchar(payload) %% 4)
  if (pad < 4) payload <- paste0(payload, strrep("=", pad))
  raw <- base64decode(payload)
  fromJSON(rawToChar(raw))
}
```

How it works:

| Step | Operation                           | Purpose                                                        |
|------|-------------------------------------|----------------------------------------------------------------|
| 1    | strsplit(token, "\\.")[[1]]         | JWT has 3 parts separated by dots: header.payload.signature    |
| 2    | parts[2]                            | Extract the payload (middle part)                              |
| 3    | gsub("-", "+") and gsub("_", "/")   | Convert URL-safe Base64 to standard Base64                     |
| 4    | Padding calculation                 | Base64 strings must have length divisible by 4                 |
| 5    | base64decode(payload)               | Decode Base64 to raw bytes                                     |
| 6    | fromJSON(rawToChar(raw))            | Convert raw bytes to JSON object                               |

Example JWT Payload Structure (after decoding):
```json
{
  "preferred_username": "username",
  "exp": 1700000000,
  "iat": 1699999999,
  "iss": "https://keycloak.....", <the URL is masked>
  "sub": "abc123-def456",
  "email": "example@company.com.tr"
}
```

---

## 3. Component 2: Client-Side Authentication Flow

File: Folder_R - keycloak.R (lines 230-256)

```r
tags$script(HTML("
  (function waitForShiny(){
    // Step 1: Wait for Shiny to be ready
    if (!window.Shiny || typeof Shiny.setInputValue !== 'function') {
      return setTimeout(waitForShiny, 50);
    }

    // Step 2: Build the base URL for redirects
    var origin = window.location.origin;
    var path   = window.location.pathname;
    var baseUrl= origin + (path.endsWith('/') ? path : path + '/');

    // Step 3: Check for token in URL hash (after Keycloak redirect)
    var m      = window.location.hash.match(/access_token=([^&]+)/);
    var tok    = m ? m[1] : localStorage.getItem('jwt_token');

    // Step 4: If token found in URL, store it and clean up
    if (m) {
      localStorage.setItem('jwt_token', tok);
      history.replaceState(null, '', baseUrl);  // Remove token from URL for security
    }

    // Step 5: If no token found, redirect to Keycloak
    if (!tok) {
      var authUrl = [
        'https://keycloak..../protocol/openid-connect/auth',
        '?client_id=mergen',
        '&redirect_uri=', encodeURIComponent(baseUrl),
        '&response_type=token',
        '&scope=openid'
      ].join('');
      window.top.location.href = authUrl;
    } else {
      // Step 6: Send token to Shiny server
      Shiny.setInputValue('jwt_token', tok, { priority:'event' });
    }
  })();
"))
```

Detailed Flow:

**Step 1: Shiny Readiness Check**

```javascript
if (!window.Shiny || typeof Shiny.setInputValue !== 'function') {
  return setTimeout(waitForShiny, 50);
}
```
- Polls every 50ms until Shiny is fully loaded
- Required because this script runs before Shiny initializes

**Step 2: URL Construction**

```javascript
var origin = window.location.origin;  // e.g., "https://mergen.com.tr"
var path   = window.location.pathname; // e.g., "/" or "/app/"
var baseUrl= origin + (path.endsWith('/') ? path : path + '/');
```

**Step 3: Token Extraction**

Two sources for the token:

| Source             | When it happens                   | Code                                                      |
|--------------------|-----------------------------------|-----------------------------------------------------------|
| URL Hash Fragment  | After Keycloak redirects back     | window.location.hash.match(/access_token=([^&]+)/)        |
| LocalStorage       | On subsequent page loads          | localStorage.getItem('jwt_token')                         |

**Step 4: Keycloak Authorization URL Parameters**

| Parameter      | Value            | Purpose                                        |
|----------------|------------------|------------------------------------------------|
| client_id      | mergen           | Identifies the application in Keycloak         |
| redirect_uri   | Current page URL | Where Keycloak sends the user after login      |
| response_type  | token            | OAuth 2.0 Implicit Flow                        |
| scope          | openid           | Request OpenID Connect authentication          |

**Step 5: Token Storage**

```javascript
localStorage.setItem('jwt_token', tok);  // Persist across sessions
history.replaceState(null, '', baseUrl); // Remove #access_token=... from URL
```
- Security reason: Tokens in URL can leak via browser history, referrer headers, or logs

---

## 4. Component 3: Server-Side Token Validation

File: functions/serverLocal - keycloak.R (lines 5-61)

### 4.1 Reactive Values Initialization

```r
#### keycloak ----
user_data      <- reactiveVal(NULL)      # Stores decoded JWT payload
auth_failed    <- reactiveVal(FALSE)     # Tracks authentication failure
kullaniciAdi   <- reactiveVal(NULL)      # Username from Keycloak
connectionTime <- reactiveVal(NULL)      # Login timestamp
yetki          <- reactiveVal(NULL)      # Permission level (SUPERADMIN, ADMIN, etc.)
MasrafYeriKodu <- reactiveVal(NULL)      # Cost center codes for authorization
control        <- reactiveVal(FALSE)     # Control flag
```

### 4.2 Token Processing Observer

```r
observeEvent(input$jwt_token, {
  # Step 1: Decode the JWT token
  tok <- tryCatch(
    decode_jwt_payload(input$jwt_token),
    error = function(e) {
      auth_failed(TRUE); NULL  # Mark as failed if decoding errors
    }
  )
  req(tok)  # Stop if token is NULL

  # Step 2: Validate user against local user_base
  if (!is.null(tok$preferred_username) &
      any(tolower(user_base$KullaniciAdi) == tok$preferred_username, na.rm = TRUE)) {

    # Step 3: User is valid - set authentication state
    user_data(tok)
    auth_failed(FALSE)
    session$sendCustomMessage("openSidebar", TRUE)  # Open sidebar via JS
    kullaniciAdi(tok$preferred_username)
    connectionTime(Sys.time())

    # Log the connection
    cat("NEW CONNECTION FROM: ", kullaniciAdi(), "\t",
        format(connectionTime(), "%d.%m.%Y %H:%M:%S"), "\n")

    # Step 4: Determine permission level
    if(tok$preferred_username %in% c("admin_user_1", "admin_user_2", "admin_user_3", "admin_user_4")){
      # Superadmin - hardcoded list
      yetki("SUPERADMIN")
    } else {
      # Regular permissions from database
      yetki(user_base %>%
              filter(tolower(KullaniciAdi) %in% tok$preferred_username) %>%
              pull(Yetki))
    }

    # Step 5: Set cost center authorization
    MasrafYeriKodu(user_base %>%
              filter(tolower(KullaniciAdi) %in% tok$preferred_username) %>%
              pull(MasrafYeriKodu))
  }
  else {
    # User not found in user_base - deny access
    auth_failed(TRUE)
  }
})
```

### 4.3 Validation Logic Breakdown

```
+----------------------------------------------------------+
|                     VALIDATION FLOW                      |
|                                                          |
|  JWT Token received via input$jwt_token                  |
|         |                                                |
|         v                                                |
|  +---------------------+                                 |
|  | decode_jwt_payload()|                                 |
|  | - Decode Base64     |                                 |
|  |   payload           |                                 |
|  | - Parse JSON        |                                 |
|  +---------------------+                                 |
|         |                                                |
|         v                                                |
|  +--------------------+  NO   +----------------------+  |
|  | Decoding           |------>| auth_failed = TRUE   |  |
|  | successful?        |       | Show access denied   |  |
|  +--------------------+       +----------------------+  |
|         |                                                |
|        YES                                               |
|         v                                                |
|  +---------------------+                                 |
|  | Extract              |                                |
|  | preferred_username   |                                |
|  | from decoded token   |                                |
|  +---------------------+                                 |
|         |                                                |
|         v                                                |
|  +----------------------+  NO   +----------------------+ |
|  | User exists in        |------>| auth_failed = TRUE   | |
|  | user_base$KullaniciAdi|       | Show access denied   | |
|  +----------------------+       +----------------------+ |
|         |                                                |
|        YES                                               |
|         v                                                |
|  +------------------------------+                        |
|  | Check if superadmin          |                        |
|  | (hardcoded usernames)        |                        |
|  +------------------------------+                        |
|         |              |                                 |
|         v              v                                 |
|  +----------+   +--------------+                         |
|  |SUPERADMIN|   | Regular user |                         |
|  +----------+   +--------------+                         |
|                        |                                 |
|                        v                                 |
|               +------------------+                       |
|               | Look up Yetki    |                       |
|               | from user_base   |                       |
|               | table            |                       |
|               +------------------+                       |
|         |              |                                 |
|         v              v                                 |
|  +----------------------------+                          |
|  | Set reactive values:       |                          |
|  | - user_data                |                          |
|  | - kullaniciAdi             |                          |
|  | - yetki                    |                          |
|  | - MasrafYeriKodu           |                          |
|  | - connectionTime           |                          |
|  +----------------------------+                          |
|                                                          |
+----------------------------------------------------------+
```

---

## 5. Component 4: User Base (Authorization Database)

### 5.1 Data Source

File: Folder2/dailyQueryScript.R (lines 393-1096)

The user_base table is created daily from SQL queries against DatabaseName.dbo.DC01_user_base:

```r
# The user_base is loaded from yetkilendirme.Rdata
load(file = "//…/ShinyApp/Rdata/yetkilendirme.Rdata")
```

### 5.2 user_base Table Structure

| Column         | Type           | Description                                        |
|----------------|----------------|----------------------------------------------------|
| KullaniciAdi   | NVARCHAR(20)   | Username (e.g., "dummyUsername")                   |
| KaynakAdi      | NVARCHAR(50)   | Full name (e.g., "John ANDREW")                    |
| MasrafYeriKodu | NVARCHAR(200)  | Cost center code(s), comma-separated               |
| Sifre          | NVARCHAR(20)   | Password (for legacy auth, not used with Keycloak) |
| Yetki          | VARCHAR(5)     | Permission level                                   |
| UserObjectId   | INT            | Primavera P6 user ID                               |

### 5.3 Permission Hierarchy

```sql
# From dailyQueryScript.R (lines 465-477)
CASE
  WHEN Yetki = 'ADMIN' THEN 1    -- Highest (after SUPERADMIN)
  WHEN Yetki = 'DIR'   THEN 2    -- Director
  WHEN Yetki = 'DIR-P' THEN 3    -- Director with project-specific access
  WHEN Yetki = 'KY-P'  THEN 4    -- Quality department with project access
  WHEN Yetki = 'KY'    THEN 5    -- Quality department
  WHEN Yetki = 'PY'    THEN 6    -- Project manager
END AS Sira  -- Sorting priority
```

### 5.4 Authorization Assignment Logic

From SQL query (dailyQueryScript.R, lines 487-530):

```sql
-- ADMIN permissions
WHEN (pf.ObjectId IN (87, 126) AND uo.OBSObjectId = 595)
    OR u.ObjectId = 13509
    OR u.ObjectId = 13733
    OR u.ObjectId = 13623
    OR u.ObjectId = 7852
THEN 'ADMIN'

-- Director permissions with cost center codes
WHEN resa.ResourceObjectId = 26696
THEN '4041000-8,4041100-8,4041200-8,4041250-8,...'

WHEN uo.OBSObjectId = 6950
THEN '4021000-5,4021200-4,4021300-4,...'
```

---

## 6. Component 5: UI Rendering Based on Auth Status

File: functions/serverLocal - keycloak.R (lines 74-298)

### 6.1 Three-State UI Rendering

```r
output$pageUI <- renderUI({

  if (auth_failed()) {
    # =============================================================
    # STATE 1: ACCESS DENIED
    # =============================================================
    dashboardPage(
      dashboardHeader(
        title = span(a(href = "pdfs/Mergen.pdf", target = "_blank",
                            img(src = "pdfs/MERGEN_Logo-03.png", width = 100)))
      ),
      dashboardSidebar(disable = TRUE),  # Sidebar hidden
      dashboardBody(
        tags$iframe(src = "pdfs/accessDenied.html",
                    style = "height: 880px; width: 100%; border: none;")
      )
    )

  } else {
    if (!is.null(user_data())) {
      # =============================================================
      # STATE 2: AUTHENTICATED - Show full application
      # =============================================================
      dashboardPage(
        title = "Mergen",
        dashboardHeader(
          # ... header with user info, logout button, etc.
        ),
        dashboardSidebar(
          collapsed = FALSE,
          sidebarMenuOutput("sidebar")  # Dynamic menu based on role
        ),
        dashboardBody(
          tabItems(
            # ... all application tabs
          )
        )
      )

    } else {
      # =============================================================
      # STATE 3: WAITING - Show loading message
      # =============================================================
      dashboardPage(
        dashboardHeader(title = "MERGEN"),
        dashboardSidebar(disable = TRUE),
        dashboardBody(
          h2("Logging in…"),
          p("Redirecting to Keycloak.")
        )
      )
    }
  }
})
```

### 6.2 Dynamic Sidebar Menu

File: functions/serverLocal - keycloak.R (lines 507-800+)

```r
output$sidebar <- renderMenu({

  if(yetki() == "SUPERADMIN"){
    # =============================================================
    # SUPERADMIN MENU - Full access to all features
    # =============================================================
    sidebarMenu(
      id = "tabs",
      menuItem("Proje", icon = icon("folder-open"),
              menuSubItem("Giriş", tabName = "projeMainPage"),
              menuSubItem("A3 Takvimi", tabName = "A3Semasi"),
              # ... more items
      ),
      menuItem("Finansal", icon = icon("dollar-sign"),
              # ... financial reports
      ),
      menuItem("AI", tabName = "MERGENAI", icon = icon("robot")),
      menuItem("Admin Panel", icon = icon("chess-king"),
              menuSubItem("Log Görüntüleme", tabName = "AdminPanel"),
              menuSubItem("Kontrol Paneli", tabName = "AdminKontrolPanel")
      ),
      menuItem("Modelleme", tabName = "Modelleme")
    )

  } else if(yetki() %in% c("ADMIN", "DIR", "DIR-P", "KY", "KY-P")){
    # =============================================================
    # ADMIN/DIRECTOR/QUALITY MENU - Most features, no admin panel
    # =============================================================
    sidebarMenu(
      # Similar structure but WITHOUT:
      # - Admin Panel
      # - Modelleme
      # - AI (varies by role)
    )

  } else if(yetki() == "KAL"){
    # =============================================================
    # QUALITY MENU - Limited to project viewing
    # =============================================================

  } else if(yetki() == "PY"){
    # =============================================================
    # PROJECT MANAGER MENU - Only their assigned projects
    # =============================================================
    sidebarMenu(
      # Very limited menu - only relevant project pages
    )
  }
})
```

---

## 7. Component 6: Authorization Functions

File: functions/yetkilendirme.R

### 7.1 Cost Center Authorization

```r
masrafYeriYetkilendirme <- function(yetki){

  if(yetki %in% c("SUPERADMIN","ADMIN")){
    # Full access to all cost centers
    sort(unique(masrafYeri$MasrafYeriTanimi))

  } else {
    # Parse comma-separated cost center codes from permission string
    MYList <- yetki %>% strsplit(., split = ",") %>% unlist()

    # Return only authorized cost centers
    masrafYeri %>%
      filter(MasrafYeriKodu %in% MYList) %$%
      sort(unique(MasrafYeriTanimi))
  }
}
```

### 7.2 Project Authorization

```r
projeYetkilendirme <- function(yetki, username, spec = NULL){

  # Determine which project dataset to use
  if(is.null(spec)){
    projelerData <- projeler            # All projects
  } else if(spec == "KritikYol"){
    projelerData <- kritikYol           # Only critical path projects
  }

  if(yetki %in% c("SUPERADMIN","ADMIN", "DIR", "KY", "KAL", "TEST")){
    # Full access to all projects
    unique(projelerData$ProjeAdi) %>% sort()

  } else if(yetki == "KY-P"){
    # Quality staff with project-specific access
    # Look up EPS codes assigned to user
    yetkiProje %>%
      filter(ParentEpsId %in% c(
        proje_KYP_base %>%
          filter(tolower(KullaniciAdi) == tolower(username) |
                       tolower(SicilNo) == tolower(username)) %>%
          select(EPSKodu) %>% unlist() %>%
          strsplit(., split = ",") %>% unlist()
      )) %>%
      select(ProjectName) %>% unlist()

  } else if(yetki == "PY"){
    # Project manager - only their assigned projects
    project_filter <- proje_PY_base %>%
      filter(KullaniciAdi == username | SicilNo == username) %>%
      select(ProjeKodu) %>% unlist() %>%
      strsplit(., split = ",") %>% unlist()

    yetkiProje %>%
      filter(Id %in% project_filter) %>%
      select(ProjectName) %>% unlist()

  } else {
    "Projeleri Görüntüleme Yetkiniz Yoktur."  # No access
  }
}
```

### 7.3 Authorization Data Tables

Loaded from yetkilendirme.Rdata:

| Table            | Purpose                                   |
|------------------|-------------------------------------------|
| user_base        | Main user authorization table             |
| proje_KYP_base   | Quality department project assignments    |
| proje_PY_base    | Project manager project assignments       |
| proje_DirP_base  | Director project assignments              |
| yetkiProje       | Project-EPS relationship lookup           |

---

## 8. Component 7: Logout Integration

File: functions/serverLocal - keycloak.R (lines 163-165)

```r
shinyauthr::logoutUI("logout", label = "",
                      icon = icon("running"),
                      style = "border-color: transparent; color:White;
                              background-color:#606C38; border-radius: 50%;")
```

The logout uses the shinyauthr package. For complete Keycloak logout, the session would need to also:
1. Clear localStorage.removeItem('jwt_token') via JavaScript
2. Redirect to Keycloak's logout endpoint:
https://keycloak..../protocol/openid-connect/logout?redirect_uri=...

---

## 9. Complete Request Flow Diagram

```
+------------------------------------------------------------------+
|                    COMPLETE REQUEST FLOW                         |
|                                                                  |
|  USER OPENS BROWSER                                              |
|         |                                                        |
|         v                                                        |
|  +-------------------------------+                               |
|  | 1. BROWSER REQUESTS SHINY APP |                               |
|  |    GET https://mergen.com/    |                               |
|  +-------------------------------+                               |
|         |                                                        |
|         v                                                        |
|  +-------------------------------------+                         |
|  | 2. SHINY RETURNS UI WITH JAVASCRIPT |                         |
|  |    - waitForShiny() function        |                         |
|  |    - Checks localStorage for        |                         |
|  |      jwt_token                      |                         |
|  +-------------------------------------+                         |
|         |                    |                                   |
|         v                    v                                   |
|  +----------------+   +-----------+                              |
|  | Token exists   |   | No token  |                              |
|  | in localStorage|   | found     |                              |
|  +----------------+   +-----------+                              |
|                              |                                   |
|                              v                                   |
|                    +----------------------+                      |
|                    | 3. REDIRECT TO       |                      |
|                    |    KEYCLOAK          |                      |
|                    |    Location:         |                      |
|                    |    keycloak.../auth? |                      |
|                    |    client_id=mergen  |                      |
|                    |    response_type=    |                      |
|                    |    token             |                      |
|                    +----------------------+                      |
|                              |                                   |
|                              v                                   |
|                    +----------------------+                      |
|                    | 4. KEYCLOAK LOGIN    |                      |
|                    |    PAGE              |                      |
|                    |    User enters       |                      |
|                    |    credentials       |                      |
|                    +----------------------+                      |
|                              |                                   |
|                              v                                   |
|                    +----------------------+                      |
|                    | 5. KEYCLOAK          |                      |
|                    |    VALIDATES         |                      |
|                    |    Issues JWT access |                      |
|                    |    token             |                      |
|                    |    Redirects back    |                      |
|                    |    with:             |                      |
|                    |    #access_token=    |                      |
|                    |    eyJhbGc...        |                      |
|                    +----------------------+                      |
|                              |                                   |
|                              v                                   |
|                    +----------------------+                      |
|                    | 6. JAVASCRIPT        |                      |
|                    |    EXTRACTS TOKEN    |                      |
|                    |    localStorage      |                      |
|                    |    .setItem()        |                      |
|                    |    history           |                      |
|                    |    .replaceState()   |                      |
|                    |    (remove from URL) |                      |
|                    +----------------------+                      |
|         |                                                        |
|         v                                                        |
|  +---------------------------+                                   |
|  | 7. JAVASCRIPT SENDS TOKEN |                                   |
|  |    TO R                   |                                   |
|  |    Shiny.setInputValue(   |                                   |
|  |      'jwt_token', tok     |                                   |
|  |    )                      |                                   |
|  +---------------------------+                                   |
|         |                                                        |
|         v                                                        |
|  +---------------------------+                                   |
|  | 8. R SERVER:              |                                   |
|  |    observeEvent()         |                                   |
|  |    triggers on            |                                   |
|  |    input$jwt_token        |                                   |
|  +---------------------------+                                   |
|         |                                                        |
|         v                                                        |
|  +---------------------------+                                   |
|  | 9. DECODE JWT PAYLOAD     |                                   |
|  |    decode_jwt_payload()   |                                   |
|  |    Extract:               |                                   |
|  |    preferred_username     |                                   |
|  +---------------------------+                                   |
|         |                                                        |
|         v                                                        |
|  +---------------------------+                                   |
|  | 10. LOOKUP USER IN        |                                   |
|  |     user_base             |                                   |
|  |     filter by             |                                   |
|  |     preferred_username    |                                   |
|  |     Get: Yetki,           |                                   |
|  |     MasrafYeriKodu        |                                   |
|  +---------------------------+                                   |
|         |                    |                                   |
|         v                    v                                   |
|  +--------------+   +------------------+                        |
|  | User found   |   | User NOT found   |                        |
|  | in user_base |   | in user_base     |                        |
|  +--------------+   +------------------+                        |
|         |                    |                                   |
|         v                    v                                   |
|  +--------------------+  +----------------------+               |
|  | 11. SET REACTIVE   |  | auth_failed(TRUE)    |               |
|  |     VALUES         |  | Show access denied   |               |
|  |  - user_data(tok)  |  | page                 |               |
|  |  - yetki(role)     |  +----------------------+               |
|  |  - kullaniciAdi()  |                                         |
|  |  - MasrafYeriKodu()|                                         |
|  +--------------------+                                         |
|         |                                                        |
|         v                                                        |
|  +---------------------------+                                   |
|  | 12. RENDER SIDEBAR MENU   |                                   |
|  |  output$sidebar <-        |                                   |
|  |    renderMenu({           |                                   |
|  |    if(yetki() ==          |                                   |
|  |      "SUPERADMIN"){...}   |                                   |
|  |    else if(yetki() ==     |                                   |
|  |      "ADMIN"){...}        |                                   |
|  |    ...                    |                                   |
|  |  })                       |                                   |
|  +---------------------------+                                   |
|         |                                                        |
|         v                                                        |
|  +---------------------------+                                   |
|  | 13. RENDER FULL           |                                   |
|  |     APPLICATION           |                                   |
|  |  - Dynamic sidebar        |                                   |
|  |    based on role          |                                   |
|  |  - Project list filtered  |                                   |
|  |    by auth                |                                   |
|  |  - Cost center access     |                                   |
|  |    limited                |                                   |
|  +---------------------------+                                   |
|                                                                  |
+------------------------------------------------------------------+
```

---

## 10. Security Considerations

**What the app does right:**

1. Token stored in localStorage - Persists across sessions
2. Token removed from URL - Prevents leakage via history/logs
3. Server-side validation - Token decoded and validated on server
4. Local user_base check - Even valid Keycloak users must be in local database
5. Role-based access control - Fine-grained permissions per user

**Potential improvements:**

1. Token expiration checking - The decoded JWT has exp claim but it's not validated
2. Token refresh - Implicit flow tokens expire; refresh token flow not implemented
3. HTTPS enforcement - Ensure all traffic uses HTTPS
4. Rate limiting - Prevent brute force attacks
5. Session timeout - Automatic logout after inactivity

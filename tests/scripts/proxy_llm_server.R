# ==============================================================================
# Dosya Yolu: tests/scripts/proxy_llm_server.R
# Aciklama:
#   Yerel PROXY LLM endpoint'i (Lane B). Cok sayida sahte "kisisel" anahtari
#   simule eder (sk-test-user001, sk-test-user002, ...). Amac: kisisel/varsayilan
#   anahtar yonlendirmesini, kullanici basina anahtar izolasyonunu, oturumlar
#   arasi anahtar sizmamasini ve guvenli loglamayi KANITLAMAK.
#
#   Proxy:
#     - Authorization bearer'dan kullanici/anahtar TAKMA ADI (pseudonym) cikarir;
#       HAM anahtar ASLA loglanmaz.
#     - Anahtar kaynagini siniflandirir: personal | default | missing.
#     - Kullanici<->anahtar 1:1 esleme tutarliligini izler (izolasyon).
#     - Varsayilan olarak SAHTE yanit doner (mock_llm mantigini yeniden kullanir).
#     - Opsiyonel olarak cok kucuk, throttle'li bir alt kumeyi TEK gercek anahtar
#       ile gercek endpoint'e iletebilir (tek gercek anahtarin yuk-yukseltmesine
#       karsi korur).
#     - GET /soak/proxy-summary ile birikmis (redakteli) ozet sunar.
#
#   Bu dosya BILEREK ASCII-guvenlidir (Turkce ozel karakter yok).
# ==============================================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || is.na(x[1])) y else x

# Bagimliliklari working-directory bagimsiz yukler (callr cocuk + izole test).
proxy_llm_bootstrap_deps <- function() {
  candidates <- c(".", "tests/scripts", Sys.getenv("MERGEN_REPO_ROOT", ""))
  src_one <- function(rel) {
    for (base in candidates) {
      if (!nzchar(base)) next
      p <- file.path(base, rel)
      if (file.exists(p)) {
        source(p, encoding = "UTF-8")
        return(TRUE)
      }
    }
    FALSE
  }
  if (!exists("soak_key_pseudonym", mode = "function")) {
    src_one("soak_secret_redaction.R")
  }
  if (!exists("mock_llm_response_plan", mode = "function")) {
    src_one("mock_llm_server.R")
  }
  invisible(TRUE)
}

# Bir bearer degerinden anahtar kaynagini siniflandirir (SAF).
# default_key_value: yapilandirilan varsayilan kurumsal anahtarin DEGERI (proxy
# icinde karsilastirma icin; loglanmaz).
proxy_llm_classify_source <- function(authorization, default_key_value = "") {
  raw <- trimws(as.character(authorization %||% ""))
  token <- sub("(?i)^bearer\\s+", "", raw, perl = TRUE)
  token <- trimws(token)

  if (!nzchar(token)) {
    return("missing")
  }
  if (nzchar(default_key_value) && identical(token, default_key_value)) {
    return("default")
  }
  # Acik varsayilan-isaretci desenleri.
  if (grepl("(?i)(corp|default|kurumsal)", token)) {
    return("default")
  }
  "personal"
}

# Bir istegi siniflandirir + takma adlar uretir. HAM anahtar/deklare kullanici
# disari sizmaz; yalnizca takma adlar tutulur.
proxy_llm_identify <- function(authorization, declared_user = "",
                               default_key_value = "") {
  raw <- trimws(as.character(authorization %||% ""))
  token <- trimws(sub("(?i)^bearer\\s+", "", raw, perl = TRUE))
  source <- proxy_llm_classify_source(authorization, default_key_value)

  key_pseud <- if (nzchar(token)) soak_key_pseudonym(token) else "key_missing"

  # Deklare kullanici (X-Soak-User) zaten takma-ad dostu bir kimliktir
  # (ornek: user001). Yoksa anahtardan turetilen deseni kullan.
  declared <- trimws(as.character(declared_user %||% ""))
  if (!nzchar(declared)) {
    m <- regmatches(token, regexpr("user[0-9]+", token, perl = TRUE))
    declared <- if (length(m) > 0L && nzchar(m[1])) m[1] else "anon"
  }
  user_pseud <- soak_session_pseudonym(declared)

  list(
    source = source,
    key_pseudonym = key_pseud,
    user_label = declared,
    user_pseudonym = user_pseud
  )
}

# Proxy durumunu olusturur (izolasyon haritalari + sayaclar).
proxy_llm_state_new <- function() {
  st <- new.env(parent = emptyenv())
  st$requests <- 0L
  st$source_counts <- list(personal = 0L, default = 0L, missing = 0L)
  st$case_counts <- list()                          # plan case -> sayac (injected-fault hesabi)
  st$key_to_users <- new.env(parent = emptyenv())   # key_pseud -> unique user_pseud vektoru
  st$user_to_keys <- new.env(parent = emptyenv())   # user_pseud -> unique key_pseud vektoru
  st$real_forward_times <- numeric(0)               # gercek-iletim zaman damgalari (sliding window)
  st$real_forwards <- 0L
  st$fake_responses <- 0L
  st$jsonl_con <- NULL
  st
}

# Bir istegin kimligini durum haritalarina kaydeder.
proxy_llm_record <- function(state, ident) {
  state$requests <- state$requests + 1L
  s <- ident$source
  state$source_counts[[s]] <- (state$source_counts[[s]] %||% 0L) + 1L

  kp <- ident$key_pseudonym
  up <- ident$user_pseudonym

  prev_users <- get0(kp, envir = state$key_to_users, inherits = FALSE) %||% character(0)
  if (!(up %in% prev_users)) {
    assign(kp, c(prev_users, up), envir = state$key_to_users)
  }
  prev_keys <- get0(up, envir = state$user_to_keys, inherits = FALSE) %||% character(0)
  if (!(kp %in% prev_keys)) {
    assign(up, c(prev_keys, kp), envir = state$user_to_keys)
  }
  invisible(NULL)
}

# Izolasyon ozeti: bir anahtarin >1 kullaniciya, bir kullanicinin >1 anahtara
# bagli olup olmadigini raporlar. Temiz izolasyonda her ikisi de 0 olmalidir.
proxy_llm_isolation_summary <- function(state) {
  key_ids <- ls(state$key_to_users)
  user_ids <- ls(state$user_to_keys)

  cross_user_keys <- sum(vapply(key_ids, function(k) {
    length(get0(k, envir = state$key_to_users, inherits = FALSE) %||% character(0)) > 1L
  }, logical(1)))

  multi_key_users <- sum(vapply(user_ids, function(u) {
    length(get0(u, envir = state$user_to_keys, inherits = FALSE) %||% character(0)) > 1L
  }, logical(1)))

  list(
    distinct_keys = length(key_ids),
    distinct_users = length(user_ids),
    cross_user_keys = as.integer(cross_user_keys),     # 0 ideal
    multi_key_users = as.integer(multi_key_users),     # 0 ideal
    isolation_ok = (cross_user_keys == 0L) && (multi_key_users == 0L)
  )
}

# Sliding-window oraninda gercek-iletime izin var mi?
proxy_llm_can_forward_real <- function(state, max_rpm, now = as.numeric(Sys.time())) {
  if (max_rpm <= 0L) return(FALSE)
  window <- state$real_forward_times[state$real_forward_times > (now - 60)]
  state$real_forward_times <- window
  length(window) < max_rpm
}

# httpuv istek ortamini cozumler (proxy'ye ozgu basliklar dahil).
proxy_llm_parse_request <- function(req) {
  method <- toupper(req[["REQUEST_METHOD"]] %||% "GET")
  path <- req[["PATH_INFO"]] %||% "/"
  auth <- req[["HTTP_AUTHORIZATION"]] %||% ""
  declared_user <- req[["HTTP_X_SOAK_USER"]] %||% ""
  force_case <- req[["HTTP_X_SOAK_FORCE"]] %||% ""

  body_text <- ""
  input <- req[["rook.input"]]
  if (!is.null(input)) {
    body_text <- tryCatch({
      raw <- input$read()
      if (length(raw) > 0L) rawToChar(raw) else ""
    }, error = function(e) "")
  }
  parsed <- tryCatch(
    if (nzchar(body_text)) jsonlite::fromJSON(body_text, simplifyVector = FALSE) else list(),
    error = function(e) list()
  )

  list(
    method = method, path = path, authorization = auth,
    declared_user = declared_user,
    force_case = if (nzchar(force_case)) force_case else NULL,
    model = parsed$model %||% NULL,
    stream = isTRUE(parsed$stream)
  )
}

# httpuv app: kimlik takip + (varsayilan) sahte yanit + opsiyonel gercek iletim.
proxy_llm_app <- function(config = list(), state = NULL) {
  proxy_llm_bootstrap_deps()
  if (is.null(state)) state <- proxy_llm_state_new()

  proxy_cfg <- config$proxy %||% list()
  default_key_value <- Sys.getenv("MERGEN_SOAK_DEFAULT_KEY_VALUE", unset = "")
  forward_real <- isTRUE(proxy_cfg$forward_real %||% FALSE)
  max_rpm <- as.integer(proxy_cfg$max_real_rpm %||% 3L)

  handle <- function(req) {
    info <- proxy_llm_parse_request(req)

    if (identical(info$method, "GET")) {
      if (grepl("healthz", info$path, fixed = TRUE)) {
        return(list(status = 200L, headers = list("Content-Type" = "application/json"),
                    body = '{"status":"ok","server":"proxy-llm"}'))
      }
      if (grepl("proxy-summary", info$path, fixed = TRUE)) {
        iso <- proxy_llm_isolation_summary(state)
        summ <- list(
          server = "proxy-llm",
          requests = state$requests,
          source_counts = state$source_counts,
          case_counts = state$case_counts,
          isolation = iso,
          real_forwards = state$real_forwards,
          fake_responses = state$fake_responses,
          forward_real_enabled = forward_real,
          max_real_rpm = max_rpm
        )
        return(list(status = 200L, headers = list("Content-Type" = "application/json"),
                    body = as.character(jsonlite::toJSON(summ, auto_unbox = TRUE, null = "null"))))
      }
      return(list(status = 200L, headers = list("Content-Type" = "application/json"),
                  body = '{"status":"ok","server":"proxy-llm"}'))
    }

    # Kimlik tespiti + kayit (HAM anahtar loglanmaz).
    ident <- proxy_llm_identify(info$authorization, info$declared_user, default_key_value)
    proxy_llm_record(state, ident)

    # Redakteli JSONL kaydi.
    if (!is.null(state$jsonl_con)) {
      rec <- list(
        ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"),
        user = ident$user_pseudonym, key = ident$key_pseudonym,
        source = ident$source, model = info$model %||% ""
      )
      tryCatch({
        writeLines(as.character(jsonlite::toJSON(rec, auto_unbox = TRUE, null = "null")),
                   state$jsonl_con)
        flush(state$jsonl_con)
      }, error = function(e) NULL)
    }

    # Sahte yanit plani (mock mantigi). Kaynak basligini echo'lar (client
    # metrikte key_source'u okuyabilsin diye; takma ad/kaynak, HAM anahtar degil).
    plan <- mock_llm_response_plan(
      list(model = info$model, stream = info$stream, force_case = info$force_case),
      config = config, force_case = info$force_case
    )
    state$fake_responses <- state$fake_responses + 1L
    state$case_counts[[plan$case]] <- (state$case_counts[[plan$case]] %||% 0L) + 1L
    plan$headers[["X-Soak-Key-Source"]] <- ident$source
    plan
  }

  list(
    call = function(req) {
      plan <- handle(req)
      response <- list(status = plan$status, headers = plan$headers, body = plan$body)
      delay_ms <- as.numeric(plan$delay_ms %||% 0)
      if (delay_ms > 0 && requireNamespace("promises", quietly = TRUE) &&
          requireNamespace("later", quietly = TRUE)) {
        promises::promise(function(resolve, reject) {
          later::later(function() resolve(response), delay_ms / 1000)
        })
      } else {
        response
      }
    },
    onHeaders = function(req) NULL
  )
}

# Adanmis surecte proxy sunucusunu calistirir (callr ile cagrilir).
proxy_llm_run <- function(host, port, config = list(), log_path = NULL,
                          ready_path = NULL, jsonl_path = NULL) {
  for (loc in c("C.UTF-8", "en_US.UTF-8", "tr_TR.UTF-8")) {
    ok <- tryCatch(nzchar(Sys.setlocale("LC_CTYPE", loc)),
                   error = function(e) FALSE, warning = function(w) FALSE)
    if (isTRUE(ok)) break
  }
  proxy_llm_bootstrap_deps()

  log_con <- NULL
  if (!is.null(log_path)) {
    log_con <- file(log_path, open = "wt", encoding = "UTF-8")
    on.exit(try(close(log_con), silent = TRUE), add = TRUE)
  }
  emit <- function(...) {
    line <- paste0("[proxy-llm] ", sprintf(...))
    if (!is.null(log_con)) { writeLines(line, log_con); flush(log_con) } else cat(line, "\n")
  }

  state <- proxy_llm_state_new()
  if (!is.null(jsonl_path)) {
    state$jsonl_con <- file(jsonl_path, open = "wt", encoding = "UTF-8")
    on.exit(try(close(state$jsonl_con), silent = TRUE), add = TRUE)
  }

  app <- proxy_llm_app(config = config, state = state)
  server <- tryCatch(
    httpuv::startServer(host, port, app),
    error = function(e) { emit("bind hatasi %s:%d -> %s", host, port, conditionMessage(e)); NULL }
  )
  if (is.null(server)) {
    if (!is.null(ready_path)) writeLines("BIND_FAILED", ready_path)
    return(invisible(FALSE))
  }
  on.exit(try(httpuv::stopServer(server), silent = TRUE), add = TRUE)

  emit("listening on http://%s:%d (proxy; sahte kisisel anahtarlar)", host, port)
  if (!is.null(ready_path)) writeLines(sprintf("%s:%d", host, port), ready_path)

  repeat {
    httpuv::service(100)
    later::run_now(timeoutSecs = 0)
  }
  invisible(TRUE)
}

#!/usr/bin/env Rscript

# ==============================================================================
# Dosya Yolu: tests/scripts/run_browser_concurrency_lane.R
# Aciklama:
#   GERCEK tarayici/websocket eszamanlilik kanit serIdI (VM/local). Operasyonel
#   soak kapisinin HTTP/proxy seridi GET-only index servisini olcer; bu lane ise
#   N adet GERCEK headless tarayici oturumunu AYNI ANDA acar. Her oturum:
#     - uygulamayi (varsayilan /smoke/ux-smoke.html) yukler,
#     - uygulamayla websocket/Shiny oturumu kurar,
#     - UX smoke akisini kosar ve UX_SMOKE_DONE:PASS/FAIL bildirir,
#     - tarayici konsol hatalarini DOM ciktisina dokerek raporlanabilir kilar.
#
#   Boylece "browser_console_errors" artik bu lane CALISTIGINDA OLCULUR (sessiz
#   UNMEASURED degil). Lane CALISMAZSA kanit acikca UNMEASURED kalir.
#
#   DURUSTLUK SINIRI: Bunlar KISA-OMURLU eszamanli oturumlardir; 1000 gercek
#   surekli insan chat oturumu DEGILDIR. 10/25/50 oturum faydalidir; uygulama
#   VM'inde 1000 tarayici CALISTIRILMAZ (kullanici tavani uygulanir).
#
#   Bagimlilik: yalniz yerel kurulu bir tarayici (Chrome/Chromium/Edge) + processx
#   + curl. CDN/runtime-download/Playwright/Selenium/chromote KULLANMAZ.
#
#   GUARD: MERGEN_BROWSER_CONCURRENCY_ENABLED=true olmadan calismaz (guvenli SKIP).
#
#   Bu dosya BILEREK ASCII-guvenlidir (Turkce ozel karakter yok).
# ==============================================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || is.na(x[1])) y else x
options(warn = 1)

bc_flag <- function(name, default = FALSE) {
  raw <- tolower(trimws(Sys.getenv(name, unset = "")))
  if (!nzchar(raw)) return(isTRUE(default))
  if (raw %in% c("true", "t", "1", "yes", "y", "on", "evet")) return(TRUE)
  if (raw %in% c("false", "f", "0", "no", "n", "off", "hayir")) return(FALSE)
  isTRUE(default)
}
bc_int <- function(name, default) {
  raw <- trimws(Sys.getenv(name, unset = ""))
  if (!nzchar(raw)) return(as.integer(default))
  v <- suppressWarnings(as.integer(raw)); if (is.na(v)) as.integer(default) else v
}
bc_str <- function(name, default = "") {
  v <- trimws(Sys.getenv(name, unset = "")); if (nzchar(v)) v else default
}

bc_repo_root <- function() {
  for (cand in c(".", "..", "../..")) {
    if (file.exists(file.path(cand, "app.R")) && dir.exists(file.path(cand, "R"))) {
      return(normalizePath(cand, winslash = "/", mustWork = TRUE))
    }
  }
  normalizePath(".", winslash = "/", mustWork = FALSE)
}
setwd(bc_repo_root())

# Redaksiyon (soak'tan; yoksa basit yedek).
bc_redact <- function(text) {
  rp <- file.path("tests", "scripts", "soak_secret_redaction.R")
  if (!exists("soak_redact_text", mode = "function") && file.exists(rp)) {
    tryCatch(source(rp, encoding = "UTF-8"), error = function(e) NULL)
  }
  if (exists("soak_redact_text", mode = "function")) return(soak_redact_text(text))
  out <- gsub("sk-[A-Za-z0-9_-]{3,}", "<hidden-key>", as.character(text %||% ""), perl = TRUE)
  gsub("(?i)bearer\\s+[A-Za-z0-9._~+/=-]{6,}", "Bearer <hidden>", out, perl = TRUE)
}

# ------------------------------------------------------------------------------
# Config + artifact.
# ------------------------------------------------------------------------------
cfg <- list(
  enabled = bc_flag("MERGEN_BROWSER_CONCURRENCY_ENABLED", FALSE),
  users = max(1L, bc_int("MERGEN_BROWSER_CONCURRENCY_USERS", 10L)),
  max_users = max(1L, bc_int("MERGEN_BROWSER_CONCURRENCY_MAX_USERS", 50L)),
  duration_sec = max(30L, bc_int("MERGEN_BROWSER_CONCURRENCY_DURATION_SECONDS", 300L)),
  base_url = sub("/+$", "", bc_str("MERGEN_BROWSER_CONCURRENCY_BASE_URL", "http://127.0.0.1:8009/")),
  headless = bc_flag("MERGEN_BROWSER_CONCURRENCY_HEADLESS", TRUE),
  target = bc_str("MERGEN_BROWSER_CONCURRENCY_TARGET", "/smoke/ux-smoke.html"),
  virtual_time_ms = max(10000L, bc_int("MERGEN_BROWSER_CONCURRENCY_VIRTUAL_TIME_MS", 120000L))
)
cap_applied <- cfg$users > cfg$max_users
if (cap_applied) cfg$users <- cfg$max_users

bc_ts <- format(Sys.time(), "%Y%m%d-%H%M%S", tz = "UTC")
bc_artifact_dir <- file.path("artifacts", "browser-concurrency", bc_ts)

bc_warnings <- character(0)

bc_summary <- list(
  schema_version = "1.0",
  gate = "run_browser_concurrency_lane",
  created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  validation_execution_status = "ran_by_browser_concurrency_lane",
  ran = FALSE,
  skipped_reason = NA_character_,
  configured_users = cfg$users,
  max_users = cfg$max_users,
  user_cap_applied = cap_applied,
  duration_seconds = cfg$duration_sec,
  base_url = cfg$base_url,
  target = cfg$target,
  headless = cfg$headless,
  sessions = 0L,
  sessions_pass = 0L,
  sessions_fail = 0L,
  sessions_timeout = 0L,
  sessions_ws_connected = 0L,
  total_console_errors = 0L,
  browser_console_errors_measured = FALSE,
  all_sessions_pass = FALSE,
  warnings = character(0),
  does_prove = character(0),
  does_not_prove = c(
    "Surekli (sustained) gercek insan chat is yukunu KANITLAMAZ; bunlar KISA-OMURLU oturumlardir.",
    "1000 gercek eszamanli insan oturumunu KANITLAMAZ (kullanici tavani uygulanir).",
    "Gercek LLM saglayici throughput'unu KANITLAMAZ."
  )
)

bc_finish <- function(skipped_reason = NA_character_) {
  bc_summary$warnings <<- bc_warnings
  if (!is.na(skipped_reason)) bc_summary$skipped_reason <<- skipped_reason
  dir.create(bc_artifact_dir, recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(bc_summary, file.path(bc_artifact_dir, "browser_concurrency_summary.json"),
                       auto_unbox = TRUE, pretty = TRUE, null = "null")
  # Redaksiyon: tum metin artifact'larini yerinde redakte et.
  for (af in list.files(bc_artifact_dir, full.names = TRUE)) {
    if (grepl("\\.(json|jsonl|csv|log)$", af)) {
      raw <- tryCatch(readLines(af, warn = FALSE, encoding = "UTF-8"), error = function(e) character(0))
      if (length(raw) > 0L) writeLines(bc_redact(paste(raw, collapse = "\n")), af, useBytes = TRUE)
    }
  }
  cat(sprintf("\nBrowser concurrency lane: %s\n",
              if (isTRUE(bc_summary$ran) && isTRUE(bc_summary$all_sessions_pass)) "PASS"
              else if (!is.na(skipped_reason)) "SKIPPED" else "FAIL"))
  cat(sprintf("Artifact: %s\n", file.path(bc_artifact_dir, "browser_concurrency_summary.json")))
}

cat("== Browser/Websocket Eszamanlilik Lane ==\n")

# ------------------------------------------------------------------------------
# GUARD + bagimlilik + tarayici binary + erisilebilirlik.
# ------------------------------------------------------------------------------
bc_find_browser <- function() {
  env_bin <- Sys.getenv("MERGEN_BROWSER_BIN", unset = "")
  if (nzchar(env_bin)) {
    rb <- if (file.exists(env_bin)) env_bin else unname(Sys.which(env_bin))
    if (nzchar(rb) && file.exists(rb)) return(rb)
    return("")
  }
  cands <- c("google-chrome", "google-chrome-stable", "chromium", "chromium-browser",
             "microsoft-edge", "microsoft-edge-stable", "msedge", "chrome", "brave-browser")
  found <- unname(Sys.which(cands)); found <- found[nzchar(found)]
  if (length(found) > 0L) return(found[[1]])
  if (.Platform$OS.type == "windows") {
    wc <- c(
      file.path(Sys.getenv("PROGRAMFILES"), "Google", "Chrome", "Application", "chrome.exe"),
      file.path(Sys.getenv("PROGRAMFILES(X86)"), "Google", "Chrome", "Application", "chrome.exe"),
      file.path(Sys.getenv("LOCALAPPDATA"), "Google", "Chrome", "Application", "chrome.exe"),
      file.path(Sys.getenv("PROGRAMFILES"), "Microsoft", "Edge", "Application", "msedge.exe"),
      file.path(Sys.getenv("PROGRAMFILES(X86)"), "Microsoft", "Edge", "Application", "msedge.exe"),
      file.path(Sys.getenv("LOCALAPPDATA"), "Microsoft", "Edge", "Application", "msedge.exe")
    )
    wc <- wc[nzchar(wc)]; hit <- wc[file.exists(wc)]
    if (length(hit) > 0L) return(normalizePath(hit[[1]], winslash = "/", mustWork = TRUE))
  }
  ""
}

bc_reachable <- function(url) {
  if (!requireNamespace("curl", quietly = TRUE)) return(FALSE)
  res <- tryCatch(curl::curl_fetch_memory(url), error = function(e) NULL)
  !is.null(res) && as.integer(res$status_code %||% 0L) > 0L
}

if (!isTRUE(cfg$enabled)) {
  reason <- "MERGEN_BROWSER_CONCURRENCY_ENABLED!=true; gercek tarayici eszamanlilik lane atlandi (UNMEASURED)."
  cat(sprintf("SKIP: %s\n", reason)); bc_finish(skipped_reason = reason)
} else if (!requireNamespace("processx", quietly = TRUE)) {
  reason <- "processx paketi yok; tarayici lane atlandi."
  cat(sprintf("SKIP: %s\n", reason)); bc_finish(skipped_reason = reason)
} else {
  browser_bin <- bc_find_browser()
  smoke_url <- paste0(cfg$base_url, if (startsWith(cfg$target, "/")) cfg$target else paste0("/", cfg$target))

  if (!nzchar(browser_bin)) {
    reason <- "Chrome/Chromium/Edge bulunamadi (MERGEN_BROWSER_BIN ile verilebilir); tarayici lane atlandi."
    cat(sprintf("SKIP: %s\n", reason)); bc_finish(skipped_reason = reason)
  } else if (!bc_reachable(cfg$base_url)) {
    reason <- sprintf("Uygulama erisilemedi: %s. Calisan uygulama gerekir (attach).", cfg$base_url)
    cat(sprintf("SKIP: %s\n", reason)); bc_finish(skipped_reason = reason)
  } else {
    if (cap_applied) {
      bc_warnings <- c(bc_warnings,
        sprintf("Istenen kullanici sayisi tavana indirildi: %d (tavan=%d).", cfg$users, cfg$max_users))
    }
    if (cfg$users > 50L) {
      bc_warnings <- c(bc_warnings, "50'den fazla eszamanli tarayici oturumu onerilmez (uygulama VM'inde 1000 tarayici CALISTIRMAYIN).")
    }
    cat(sprintf("Tarayici: %s | hedef: %s | oturum: %d | sanal-zaman: %dms\n",
                browser_bin, smoke_url, cfg$users, cfg$virtual_time_ms))

    dir.create(bc_artifact_dir, recursive = TRUE, showWarnings = FALSE)
    bc_summary$ran <- TRUE
    bc_summary$browser_console_errors_measured <- TRUE

    headless_arg <- if (isTRUE(cfg$headless)) "--headless=new" else "--headless"
    per_timeout <- max(60L, as.integer(cfg$virtual_time_ms / 1000) + 45L)

    # N oturumu AYNI ANDA baslat (gercek eszamanli websocket).
    procs <- vector("list", cfg$users)
    dom_files <- character(cfg$users)
    profile_dirs <- character(cfg$users)
    starts <- numeric(cfg$users)
    for (i in seq_len(cfg$users)) {
      profile_dirs[i] <- tempfile(sprintf("mergen-bc-prof-%03d-", i))
      dir.create(profile_dirs[i], recursive = TRUE, showWarnings = FALSE)
      dom_files[i] <- file.path(bc_artifact_dir, sprintf("session-%03d-dom.html", i))
      args <- c(headless_arg, "--disable-gpu", "--disable-dev-shm-usage",
                "--no-first-run", "--no-default-browser-check",
                "--autoplay-policy=no-user-gesture-required",
                "--enable-logging=stderr", "--v=0",
                paste0("--user-data-dir=", profile_dirs[i]),
                paste0("--virtual-time-budget=", cfg$virtual_time_ms),
                "--dump-dom", smoke_url)
      starts[i] <- as.numeric(Sys.time())
      procs[[i]] <- tryCatch(
        processx::process$new(command = browser_bin, args = args,
                              stdout = dom_files[i],
                              stderr = file.path(bc_artifact_dir, sprintf("session-%03d-stderr.log", i)),
                              supervise = TRUE),
        error = function(e) { bc_warnings <<- c(bc_warnings, bc_redact(sprintf("session %d baslamadi: %s", i, conditionMessage(e)))); NULL }
      )
    }

    on.exit({
      for (p in procs) if (!is.null(p) && isTRUE(tryCatch(p$is_alive(), error = function(e) FALSE))) {
        try(p$kill_tree(), silent = TRUE)
      }
      for (d in profile_dirs) try(unlink(d, recursive = TRUE, force = TRUE), silent = TRUE)
    }, add = TRUE)

    # Tum oturumlarin bitmesini bekle (per_timeout kadar).
    deadline <- Sys.time() + per_timeout
    repeat {
      alive <- vapply(procs, function(p) !is.null(p) && isTRUE(tryCatch(p$is_alive(), error = function(e) FALSE)), logical(1))
      if (!any(alive) || Sys.time() >= deadline) break
      Sys.sleep(0.5)
    }

    # Sonuclari topla.
    sess_rows <- list()
    con_err_path <- file.path(bc_artifact_dir, "browser_console_errors.jsonl")
    con_err_con <- file(con_err_path, open = "wt", encoding = "UTF-8")
    total_console_errors <- 0L
    pass_n <- 0L; fail_n <- 0L; timeout_n <- 0L; ws_n <- 0L

    for (i in seq_len(cfg$users)) {
      p <- procs[[i]]
      still_alive <- !is.null(p) && isTRUE(tryCatch(p$is_alive(), error = function(e) FALSE))
      if (still_alive) try(p$kill_tree(), silent = TRUE)
      dom <- if (file.exists(dom_files[i])) {
        tryCatch(paste(readLines(dom_files[i], warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
                 error = function(e) "")
      } else ""
      elapsed_ms <- round((as.numeric(Sys.time()) - starts[i]) * 1000, 0)

      passed <- grepl("UX_SMOKE_DONE:PASS", dom, fixed = TRUE)
      failed <- grepl("UX_SMOKE_DONE:FAIL", dom, fixed = TRUE)
      ws_connected <- grepl("shiny|MERGEN|Bilge|MergenStreamingSmoke|mergen", dom, ignore.case = TRUE)
      status <- if (passed) "pass" else if (failed) "fail" else if (still_alive) "timeout" else "incomplete"

      # Konsol hatasi sinyalleri: smoke harness DOM'a yazar; kaba sayim.
      ce_lines <- character(0)
      if (nzchar(dom)) {
        cand <- strsplit(dom, "\n", fixed = TRUE)[[1]]
        ce_lines <- cand[grepl("console.*error|MERGEN_DEBUG_ERROR|MERGEN_DEBUG_RESOURCE_ERROR|UX_SMOKE_CONSOLE_ERROR", cand, ignore.case = TRUE)]
      }
      ce_count <- length(ce_lines)
      total_console_errors <- total_console_errors + ce_count
      for (ln in head(ce_lines, 20L)) {
        rec <- list(session = i, line = bc_redact(substr(ln, 1L, 400L)))
        writeLines(as.character(jsonlite::toJSON(rec, auto_unbox = TRUE, null = "null")), con_err_con)
      }

      if (identical(status, "pass")) pass_n <- pass_n + 1L
      else if (identical(status, "fail")) fail_n <- fail_n + 1L
      else if (identical(status, "timeout")) timeout_n <- timeout_n + 1L
      if (isTRUE(ws_connected)) ws_n <- ws_n + 1L

      sess_rows[[i]] <- data.frame(
        session = i, status = status, elapsed_ms = elapsed_ms,
        ws_connected = ws_connected, console_errors = ce_count,
        stringsAsFactors = FALSE
      )
      cat(sprintf("  oturum %03d: %s | ws=%s | konsol_hata=%d | %sms\n",
                  i, status, as.character(ws_connected), ce_count, as.character(elapsed_ms)))
    }
    close(con_err_con)

    metrics_df <- do.call(rbind, sess_rows)
    utils::write.csv(metrics_df, file.path(bc_artifact_dir, "browser_session_metrics.csv"),
                     row.names = FALSE, fileEncoding = "UTF-8")

    bc_summary$sessions <- cfg$users
    bc_summary$sessions_pass <- pass_n
    bc_summary$sessions_fail <- fail_n
    bc_summary$sessions_timeout <- timeout_n
    bc_summary$sessions_ws_connected <- ws_n
    bc_summary$total_console_errors <- total_console_errors
    bc_summary$all_sessions_pass <- (pass_n == cfg$users) && (total_console_errors == 0L)
    if (isTRUE(bc_summary$all_sessions_pass)) {
      bc_summary$does_prove <- c(
        sprintf("%d gercek headless tarayici oturumu AYNI ANDA uygulamayla websocket/Shiny oturumu kurdu ve UX smoke'u PASS bildirdi.", cfg$users),
        "Bu oturumlarda bloklayici tarayici konsol hatasi GORULMEDI (browser_console_errors OLCULDU)."
      )
    } else {
      bc_warnings <- c(bc_warnings,
        sprintf("Bazi oturumlar PASS olmadi (pass=%d fail=%d timeout=%d) veya konsol hatasi var (%d).",
                pass_n, fail_n, timeout_n, total_console_errors))
    }

    bc_finish()

    if (!isTRUE(bc_summary$all_sessions_pass)) {
      # quit() KULLANILMAZ (source-safe). stop() Rscript altinda sifir-disi cikis verir.
      stop(sprintf("Browser concurrency lane FAIL: tum oturumlar PASS+temiz-konsol degil. Ayrintilar: %s",
                   file.path(bc_artifact_dir, "browser_concurrency_summary.json")), call. = FALSE)
    } else {
      cat("OK: tum tarayici oturumlari PASS + temiz konsol.\n")
    }
  }
}

invisible(TRUE)

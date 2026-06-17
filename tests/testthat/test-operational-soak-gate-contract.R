# ==============================================================================
# Dosya Yolu: tests/testthat/test-operational-soak-gate-contract.R
# Aciklama:
#   Operasyonel soak kapisi (tests/scripts/run_operational_soak_gate.R + yardimci
#   modulleri) icin HIZLI, OFFLINE, DETERMINISTIK sozlesme testi. Tam uygulamayi
#   BOOT ETMEZ; gercek DB/LLM/tarayici/SSO GEREKTIRMEZ.
#
#   Kapsanan sozlesmeler:
#     - Operasyonel betikler ASCII-guvenli (parser-stability) + parse edilebilir.
#     - Fake LLM yanit plani: OpenAI-uyumlu non-streaming + SSE + hata durumlari.
#     - Proxy: anahtar kaynak siniflandirma, izolasyon ve kontaminasyon tespiti.
#     - Redaksiyon: ham anahtar/token/sir maskeleme + tarama.
#     - Metrikler: yuzdelik, dilim ozeti, enjekte-fault, etkin basari orani.
#     - In-process alistirmalar: encoding round-trip, upload, key-routing,
#       oturumlar-arasi izolasyon (gercek uygulama yardimcilarini cagirir).
#     - Esik degerlendirme: olculemeyen esikler sessizce gecmez; FAIL tespiti.
#     - Evidence semasi + does_prove / does_not_prove + redaksiyon self-check.
#
#   Opsiyonel canli sunucu smoke testi MERGEN_SOAK_TEST_LIVE=true ile acilir;
#   varsayilan kapali (deterministik kalmak icin).
# ==============================================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || is.na(x[1])) y else x

# UTF-8 locale: app helper'lari ve Turkce fiksturler in-process yuklenir.
local({
  for (loc in c("C.UTF-8", "en_US.UTF-8", "tr_TR.UTF-8")) {
    if (tryCatch(nzchar(Sys.setlocale("LC_CTYPE", loc)),
                 error = function(e) FALSE, warning = function(w) FALSE)) break
  }
})

soak_repo_root_for_test <- local({
  cands <- c(".", "..", "../..", "../../..")
  hit <- NULL
  for (cand in cands) {
    if (file.exists(file.path(cand, "tests", "scripts", "run_operational_soak_gate.R"))) {
      hit <- normalizePath(cand, winslash = "/", mustWork = TRUE)
      break
    }
  }
  hit
})

soak_script_path <- function(rel) file.path(soak_repo_root_for_test, "tests", "scripts", rel)

soak_source_modules <- function(env = parent.frame()) {
  mods <- c("soak_secret_redaction.R", "soak_config.R", "soak_metrics.R",
            "soak_scenarios.R", "mock_llm_server.R", "proxy_llm_server.R",
            "soak_client.R", "soak_artifacts.R")
  for (m in mods) {
    suppressWarnings(suppressMessages(sys.source(soak_script_path(m), envir = env)))
  }
}

soak_operational_scripts <- function() {
  c("run_operational_soak_gate.R", "soak_config.R", "soak_secret_redaction.R",
    "soak_metrics.R", "soak_scenarios.R", "soak_client.R", "soak_artifacts.R",
    "mock_llm_server.R", "proxy_llm_server.R")
}

# Byte-safe okuyucu (Windows VM uyumlu); CLAUDE.md repo-tarama kurali.
soak_read_bytes <- function(path) {
  if (!file.exists(path)) return(raw(0))
  readBin(path, what = "raw", n = file.info(path)$size)
}

# ------------------------------------------------------------------------------
testthat::test_that("operasyonel soak betikleri ASCII-guvenli (parser-stability)", {
  testthat::skip_if(is.null(soak_repo_root_for_test), "Repo koku bulunamadi.")
  for (f in soak_operational_scripts()) {
    bytes <- soak_read_bytes(soak_script_path(f))
    high <- which(as.integer(bytes) > 127L)
    testthat::expect_length(high, 0L)
    # NUL byte da olmamali.
    testthat::expect_false(any(bytes == as.raw(0L)), info = f)
  }
})

testthat::test_that("tum soak modulleri parse edilebilir", {
  testthat::skip_if(is.null(soak_repo_root_for_test), "Repo koku bulunamadi.")
  for (f in soak_operational_scripts()) {
    testthat::expect_silent(parse(soak_script_path(f)))
  }
})

# ------------------------------------------------------------------------------
testthat::test_that("config: varsayilan smoke + env override + public config sir icermez", {
  env <- new.env()
  soak_source_modules(env)

  withr::with_envvar(list(MERGEN_SOAK_PROFILE = NA, MERGEN_SOAK_LLM_MODE = NA,
                          MERGEN_SOAK_CONCURRENT_USERS = NA, MERGEN_SOAK_DURATION_MINUTES = NA), {
    cfg <- env$soak_resolve_config()
    testthat::expect_equal(cfg$profile, "smoke")
    testthat::expect_equal(cfg$llm_lane, "fake")
    testthat::expect_true(cfg$concurrent_users >= 1L)
  })

  withr::with_envvar(list(MERGEN_SOAK_PROFILE = "org", MERGEN_SOAK_CONCURRENT_USERS = "77",
                          MERGEN_SOAK_LLM_MODE = "proxy"), {
    cfg <- env$soak_resolve_config()
    testthat::expect_equal(cfg$profile, "org")
    testthat::expect_equal(cfg$concurrent_users, 77L)
    testthat::expect_equal(cfg$llm_lane, "proxy")
  })

  # Windows/RStudio .Renviron edits sometimes leave shell-style quotes and
  # trailing inline comments in values.
  withr::with_envvar(list(MERGEN_SOAK_PROFILE = "'smoke'        # smoke|pilot|org",
                          MERGEN_SOAK_LLM_MODE = "'fake'        # fake|proxy|real-canary"), {
    cfg <- env$soak_resolve_config()
    testthat::expect_equal(cfg$profile, "smoke")
    testthat::expect_equal(cfg$llm_lane, "fake")
  })

  # real-canary kullanici tavani uygulanir.
  withr::with_envvar(list(MERGEN_SOAK_PROFILE = "real_llm",
                          MERGEN_SOAK_CONCURRENT_USERS = "500"), {
    cfg <- env$soak_resolve_config()
    testthat::expect_equal(cfg$llm_lane, "real-canary")
    testthat::expect_true(cfg$concurrent_users <= 5L)
  })

  # Public config ham endpoint/key icermemeli. Sahte ama uzun anahtarlar
  # CALISMA ZAMANI insa edilir (statik secret-leak tarayicisi tetiklenmesin;
  # CLAUDE.md kurali).
  k_corp <- paste0("sk-", "corp-fake-value-aaaaaaaa11")
  k_real <- paste0("sk-", "real-fake-value-bbbbbbbb22")
  withr::with_envvar(list(MERGEN_DEFAULT_API_KEY = k_corp,
                          MERGEN_SOAK_REAL_API_KEY = k_real), {
    cfg <- env$soak_resolve_config()
    pub <- env$soak_config_public(cfg)
    pub_txt <- jsonlite::toJSON(pub, auto_unbox = TRUE)
    testthat::expect_false(grepl(k_corp, pub_txt, fixed = TRUE))
    testthat::expect_false(grepl(k_real, pub_txt, fixed = TRUE))
  })
})

# ------------------------------------------------------------------------------
testthat::test_that("fake LLM yanit plani: OpenAI non-streaming + SSE + hata durumlari", {
  env <- new.env(); soak_source_modules(env)
  cfg <- list(fake = list(stream = TRUE, stream_chunks = 6L,
                          latency_ms_min = 10, latency_ms_max = 20,
                          error_rate = 0, timeout_rate = 0, long_response_rate = 0),
              client_timeout_sec = 20)

  # normal non-streaming -> 200, parse edilebilir choices[].message.content
  p <- env$mock_llm_response_plan(list(model = "m1", stream = FALSE), config = cfg, force_case = "normal")
  testthat::expect_equal(p$status, 200L)
  testthat::expect_equal(p$headers[["Content-Type"]], "application/json")
  parsed <- jsonlite::fromJSON(p$body, simplifyVector = FALSE)
  testthat::expect_true(nzchar(parsed$choices[[1]]$message$content))

  # streaming -> text/event-stream, data: ... [DONE]
  ps <- env$mock_llm_response_plan(list(model = "m1", stream = TRUE), config = cfg, force_case = "normal")
  testthat::expect_equal(ps$headers[["Content-Type"]], "text/event-stream")
  testthat::expect_true(grepl("data: ", ps$body, fixed = TRUE))
  testthat::expect_true(grepl("data: [DONE]", ps$body, fixed = TRUE))

  # interrupted -> [DONE] YOK
  pi <- env$mock_llm_response_plan(list(stream = TRUE), config = cfg, force_case = "interrupted")
  testthat::expect_false(grepl("[DONE]", pi$body, fixed = TRUE))

  # hata durumlari
  testthat::expect_equal(env$mock_llm_response_plan(list(), cfg, "http500")$status, 500L)
  testthat::expect_equal(env$mock_llm_response_plan(list(), cfg, "http429")$status, 429L)
  testthat::expect_equal(env$mock_llm_response_plan(list(), cfg, "empty")$body, "")
  # malformed -> gecerli JSON DEGIL
  pm <- env$mock_llm_response_plan(list(), cfg, "malformed")
  testthat::expect_error(jsonlite::fromJSON(pm$body))
  # timeout -> client timeout'undan buyuk gecikme
  pt <- env$mock_llm_response_plan(list(), cfg, "timeout")
  testthat::expect_true(pt$delay_ms > cfg$client_timeout_sec * 1000)

  # Turkce icerik gercekten Turkce ozel karakter tasir.
  ptr <- env$mock_llm_response_plan(list(stream = FALSE), cfg, "turkish")
  body_obj <- jsonlite::fromJSON(ptr$body, simplifyVector = FALSE)
  content <- body_obj$choices[[1]]$message$content
  testthat::expect_true(any(utf8ToInt(content) > 127L))
})

# ------------------------------------------------------------------------------
testthat::test_that("proxy: kaynak siniflandirma, izolasyon ve kontaminasyon tespiti", {
  env <- new.env(); soak_source_modules(env)

  testthat::expect_equal(env$proxy_llm_classify_source("Bearer sk-test-user001"), "personal")
  testthat::expect_equal(env$proxy_llm_classify_source("Bearer sk-corp-default"), "default")
  testthat::expect_equal(env$proxy_llm_classify_source(""), "missing")

  st <- env$proxy_llm_state_new()
  for (u in sprintf("user%03d", 1:20)) {
    id <- env$proxy_llm_identify(paste0("Bearer sk-test-", u), declared_user = u)
    env$proxy_llm_record(st, id)
  }
  iso <- env$proxy_llm_isolation_summary(st)
  testthat::expect_equal(iso$distinct_keys, 20L)
  testthat::expect_equal(iso$distinct_users, 20L)
  testthat::expect_equal(iso$cross_user_keys, 0L)
  testthat::expect_equal(iso$multi_key_users, 0L)
  testthat::expect_true(iso$isolation_ok)

  # Kontaminasyon: userX, user001'in anahtarini sunar -> cross_user_keys artar.
  env$proxy_llm_record(st, env$proxy_llm_identify("Bearer sk-test-user001", declared_user = "userX"))
  iso2 <- env$proxy_llm_isolation_summary(st)
  testthat::expect_true(iso2$cross_user_keys >= 1L)
  testthat::expect_false(iso2$isolation_ok)

  # Rate limit
  testthat::expect_false(env$proxy_llm_can_forward_real(st, 0L))
  testthat::expect_true(env$proxy_llm_can_forward_real(st, 3L))
})

# ------------------------------------------------------------------------------
testthat::test_that("redaksiyon: ham anahtar/token/sir maskelenir ve taranir", {
  env <- new.env(); soak_source_modules(env)

  # Sahte sirlar CALISMA ZAMANI insa edilir (statik secret-leak tarayicisi
  # tetiklenmesin; CLAUDE.md kurali).
  secret <- paste0("sk-", "corp-fake-secret-cccccccc33")
  bearer_key <- paste0("sk-", "test-user001abc")
  jwt_fake <- paste0("eyJ", "hbGciOi.", "eyJ", "zdWIiOi.SflKxwRJ")
  withr::with_envvar(list(MERGEN_DEFAULT_API_KEY = secret), {
    txt <- paste(
      paste0("Authorization: Bearer ", bearer_key),
      paste0("api_key=", secret, " token=mytok12345 password=hunter2xx"),
      paste0("jwt ", jwt_fake),
      sep = "\n")
    testthat::expect_true(env$soak_scan_for_secrets(txt) > 0L)
    red <- env$soak_redact_text(txt)
    testthat::expect_equal(env$soak_scan_for_secrets(red), 0L)
    testthat::expect_false(grepl(bearer_key, red, fixed = TRUE))
    testthat::expect_false(grepl("fake-secret-cccccccc", red, fixed = TRUE))
  })

  # Pseudonimler kararli + farkli anahtarlar farkli.
  testthat::expect_identical(env$soak_key_pseudonym("sk-test-user001"),
                             env$soak_key_pseudonym("sk-test-user001"))
  testthat::expect_false(identical(env$soak_key_pseudonym("sk-test-user001"),
                                   env$soak_key_pseudonym("sk-test-user002")))
  # Pseudonym ham anahtari ICERMEZ.
  testthat::expect_false(grepl("sk-test-user001", env$soak_key_pseudonym("sk-test-user001"), fixed = TRUE))
})

# ------------------------------------------------------------------------------
testthat::test_that("metrikler: yuzdelik, dilim ozeti, enjekte-fault, etkin oran", {
  env <- new.env(); soak_source_modules(env)

  m <- env$soak_metrics_new()
  for (i in 1:90) env$soak_metrics_record(m, "fake", "chat_short", 100 + i, "ok", 200L, 50, "n/a")
  for (i in 1:7)  env$soak_metrics_record(m, "fake", "chat_short", 500, "error", 500L, 0, "n/a")
  for (i in 1:3)  env$soak_metrics_record(m, "fake", "chat_short", 20000, "timeout", NA, 0, "n/a")
  s <- env$soak_metrics_summary(m)
  testthat::expect_equal(s$requests, 100L)
  testthat::expect_equal(s$success, 90L)
  testthat::expect_equal(s$errors, 7L)
  testthat::expect_equal(s$timeouts, 3L)
  testthat::expect_equal(s$success_rate, 0.9)
  testthat::expect_true(is.finite(s$p95_latency_ms))
  testthat::expect_true(s$p99_latency_ms >= s$p95_latency_ms)

  # Enjekte-fault hesabi: case_counts'tan http500+http429+timeout.
  testthat::expect_equal(env$soak_injected_fault_count(list(http500 = 5L, http429 = 2L, timeout = 3L,
                                                            normal = 100L)), 10L)
  testthat::expect_equal(env$soak_injected_fault_count(NULL), 0L)

  # Etkin oran: 10 gozlenen fault, 10 enjekte -> 0 beklenmeyen -> effective 1.0
  cfg <- list(thresholds = list(success_rate_min = 0.98, p95_latency_ms_max = 0L,
                                memory_growth_mb_max = -1, temp_growth_mb_max = -1,
                                fail_on_browser_console_errors = FALSE, fail_on_mojibake = TRUE,
                                fail_on_secret_leak = TRUE), llm_lane = "fake")
  inproc <- list(available = FALSE)
  mg <- list(rss_measured = FALSE, process_rss_growth_mb = NA)
  checks <- env$soak_evaluate_thresholds(cfg, s, inproc, list(total_leaks = 0L), mg, NA, TRUE,
                                         injected_faults = 10L)
  eff <- Filter(function(c) c$name == "effective_success_rate", checks)[[1]]
  testthat::expect_true(eff$measured)
  testthat::expect_true(isTRUE(eff$pass))
})

# ------------------------------------------------------------------------------
testthat::test_that("senaryolar + key-routing matrisi + upload durumlari", {
  env <- new.env(); soak_source_modules(env)
  cat_ <- env$soak_scenario_catalog()
  testthat::expect_true(length(cat_) >= 6L)
  # Her senaryonun bir prompt'u ve id'si var.
  testthat::expect_true(all(vapply(cat_, function(s) nzchar(s$id) && nzchar(s$prompt), logical(1))))
  # En az bir senaryo Turkce ozel karakter tasimali.
  testthat::expect_true(any(vapply(cat_, function(s) any(utf8ToInt(s$prompt) > 127L), logical(1))))
  body <- env$soak_build_chat_body(env$soak_pick_scenario(cat_))
  testthat::expect_true(nzchar(jsonlite::fromJSON(body)$model))

  testthat::expect_equal(length(env$soak_key_routing_matrix()), 5L)
  testthat::expect_true(length(env$soak_upload_cases()) >= 5L)
  testthat::expect_true(length(env$soak_failure_probe_cases()) >= 7L)
})

# ------------------------------------------------------------------------------
testthat::test_that("in-process alistirmalar: encoding/upload/key-routing/izolasyon (gercek helper)", {
  env <- new.env(); soak_source_modules(env)
  ex <- tryCatch(env$soak_inprocess_exercises(list(), iterations = 5L),
                 error = function(e) list(available = FALSE, reason = conditionMessage(e)))
  testthat::skip_if_not(isTRUE(ex$available),
                        sprintf("Uygulama yardimcilari yuklenemedi: %s", ex$reason %||% ""))

  # Encoding round-trip: Turkce + emoji korunur, mojibake URETILMEZ.
  testthat::expect_equal(ex$encoding$mojibake_hits, 0L)
  testthat::expect_equal(ex$encoding$roundtrip_pass, ex$encoding$iterations)
  testthat::expect_true(ex$encoding$mojibake_detection_ok)

  # Upload: tum kabul/ret kararlari dogru.
  testthat::expect_true(ex$upload$all_correct)

  # Key routing: 5/5 dogru + oturumlar-arasi izolasyon.
  testthat::expect_true(ex$key_routing$all_correct)
  testthat::expect_true(ex$key_routing$cross_session_isolation_pass)
  testthat::expect_equal(ex$key_routing$source_counts$personal, 2L)
  testthat::expect_equal(ex$key_routing$source_counts$missing, 2L)

  # Atomic write + safe path + cleanup.
  testthat::expect_true(ex$atomic_path$atomic_write_ok)
  testthat::expect_true(ex$atomic_path$safe_path_rejects_traversal)
  testthat::expect_true(ex$session_cleanup$safe_unlink_ok)
})

# ------------------------------------------------------------------------------
testthat::test_that("evidence semasi + does_prove/does_not_prove + redaksiyon self-check", {
  env <- new.env(); soak_source_modules(env)

  cfg <- withr::with_envvar(list(MERGEN_SOAK_PROFILE = "smoke"), env$soak_resolve_config())
  m <- env$soak_metrics_new()
  for (i in 1:50) env$soak_metrics_record(m, "fake", "chat_short", 100 + i, "ok", 200L, 40, "n/a")
  s <- env$soak_metrics_summary(m)
  inproc <- list(available = TRUE,
                 encoding = list(iterations = 5L, roundtrip_pass = 5L, roundtrip_pass_rate = 1.0,
                                 mojibake_hits = 0L, mojibake_detection_pass = 5L, mojibake_detection_ok = TRUE),
                 upload = list(total = 7L, correct = 7L, all_correct = TRUE, detail = list()),
                 key_routing = list(rows_total = 5L, rows_correct = 5L, all_correct = TRUE,
                                    source_counts = list(personal = 2L, default = 1L, missing = 2L),
                                    cross_session_isolation_pass = TRUE, detail = list()),
                 atomic_path = list(atomic_write_ok = TRUE, safe_path_rejects_traversal = TRUE,
                                    safe_path_allows_safe = TRUE),
                 session_cleanup = list(safe_unlink_ok = TRUE))
  mg <- env$soak_memory_growth(env$soak_sample_memory(), env$soak_sample_memory())
  checks <- env$soak_evaluate_thresholds(cfg, s, inproc, list(total_leaks = 0L), mg, 0, TRUE, 0L)
  outcome <- env$soak_threshold_outcome(checks)
  proofs <- env$soak_proof_statements(cfg, s, inproc, list(reachable = FALSE))
  ev <- env$soak_build_evidence(cfg, s, inproc, NULL, list(), list(total_leaks = 0L),
                                list(), mg, list(), list(reachable = FALSE), NULL, checks, outcome,
                                proofs, 1.0, character(0), character(0), TRUE, 0L)

  # Sema alanlari mevcut.
  for (field in c("schema_version", "llm_lane", "user_base_target", "configured_concurrent_users",
                  "metrics", "key_sources", "secret_redaction_confirmed", "raw_key_leak_count",
                  "db_roundtrip_encoding_pass", "pass", "does_prove", "does_not_prove",
                  "thresholds", "threshold_checks")) {
    testthat::expect_true(field %in% names(ev), info = field)
  }
  testthat::expect_true(length(ev$does_prove) >= 1L)
  testthat::expect_true(length(ev$does_not_prove) >= 3L)
  testthat::expect_true(ev$metrics$effective_success_rate >= 0.99)
  testthat::expect_true(ev$pass)

  # Artifact yazimi + redaksiyon self-check (gecici dizinde).
  tmp <- file.path(tempdir(), paste0("soak_art_", as.integer(stats::runif(1, 1, 1e6))))
  red <- env$soak_write_artifacts(tmp, cfg, m, ev, NULL, list(), NULL)
  testthat::expect_equal(red$total_leaks, 0L)
  testthat::expect_true(file.exists(file.path(tmp, "soak_evidence.json")))
  testthat::expect_true(file.exists(file.path(tmp, "summary.md")))
  testthat::expect_true(file.exists(file.path(tmp, "metrics.csv")))
  testthat::expect_true(file.exists(file.path(tmp, "config.json")))
  testthat::expect_true(file.exists(file.path(tmp, "key_routing_summary.json")))
  unlink(tmp, recursive = TRUE)
})

# ------------------------------------------------------------------------------
# Opsiyonel canli sunucu smoke (varsayilan KAPALI; deterministik kalmak icin).
# Kapaliyken test_that() kaydedilmez; boylece hizli lokal/VM kosular skip uretmez.
if (tolower(Sys.getenv("MERGEN_SOAK_TEST_LIVE", "")) %in% c("true", "1", "yes")) {
  testthat::test_that("canli fake sunucu smoke (opsiyonel)", {
  testthat::skip_if_not_installed("callr")
  testthat::skip_if_not_installed("curl")
  env <- new.env(); soak_source_modules(env)

  port <- httpuv::randomPort(min = 12000, max = 19999)
  ready <- tempfile(); repo <- soak_repo_root_for_test
  proc <- callr::r_bg(function(repo, port, ready) {
    setwd(repo)
    for (loc in c("C.UTF-8", "en_US.UTF-8")) if (tryCatch(nzchar(Sys.setlocale("LC_CTYPE", loc)), error = function(e) FALSE, warning = function(w) FALSE)) break
    source("tests/scripts/mock_llm_server.R", encoding = "UTF-8")
    mock_llm_run("127.0.0.1", port, config = list(fake = list(latency_ms_min = 10, latency_ms_max = 20,
                 error_rate = 0, timeout_rate = 0, stream = FALSE, long_response_rate = 0)),
                 ready_path = ready)
  }, args = list(repo, port, ready), supervise = TRUE)
  on.exit(tryCatch(proc$kill(), error = function(e) NULL), add = TRUE)

  ok <- FALSE
  for (i in 1:60) { if (file.exists(ready) && nzchar(readLines(ready, warn = FALSE)[1])) { ok <- TRUE; break }; Sys.sleep(0.1) }
  testthat::expect_true(ok)

  h <- tryCatch(curl::curl_fetch_memory(sprintf("http://127.0.0.1:%d/healthz", port)), error = function(e) NULL)
  testthat::expect_equal(as.integer(h$status_code), 200L)

  body <- '{"model":"m1","messages":[{"role":"user","content":"merhaba"}],"stream":false}'
  hnd <- curl::new_handle(url = sprintf("http://127.0.0.1:%d/v1/chat/completions", port))
  curl::handle_setheaders(hnd, "Content-Type" = "application/json")
  curl::handle_setopt(hnd, post = TRUE, postfields = body, timeout_ms = 10000)
  r <- curl::curl_fetch_memory(sprintf("http://127.0.0.1:%d/v1/chat/completions", port), handle = hnd)
  testthat::expect_equal(as.integer(r$status_code), 200L)
  parsed <- jsonlite::fromJSON(rawToChar(r$content), simplifyVector = FALSE)
  testthat::expect_true(nzchar(parsed$choices[[1]]$message$content))
  })
}

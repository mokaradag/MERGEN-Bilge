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
            "soak_scenarios.R", "soak_system_telemetry.R", "mock_llm_server.R",
            "proxy_llm_server.R", "soak_client.R", "soak_interactive_lane.R",
            "soak_artifacts.R")
  for (m in mods) {
    suppressWarnings(suppressMessages(sys.source(soak_script_path(m), envir = env)))
  }
}

soak_operational_scripts <- function() {
  c("run_operational_soak_gate.R", "soak_config.R", "soak_secret_redaction.R",
    "soak_metrics.R", "soak_scenarios.R", "soak_system_telemetry.R", "soak_client.R",
    "soak_interactive_lane.R", "soak_artifacts.R", "mock_llm_server.R",
    "proxy_llm_server.R")
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
  # Bu blok profil varsayilanini test eder; VM/RStudio .Renviron icindeki
  # MERGEN_SOAK_LLM_MODE=fake/proxy gibi ortam degerleri sonucu kirletmemeli.
  withr::with_envvar(list(MERGEN_SOAK_PROFILE = "real_llm",
                          MERGEN_SOAK_LLM_MODE = NA,
                          MERGEN_SOAK_REAL_CANARY_USERS = NA,
                          MERGEN_SOAK_REAL_CANARY_MAX_USERS = NA,
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
testthat::test_that("app HTTP soak URL timestamp does not overflow Windows integer range", {
  env <- new.env(); soak_source_modules(env)

  fixed_now <- as.POSIXct("2026-06-17 12:34:56", tz = "UTC")
  millis <- testthat::expect_no_warning(env$soak_epoch_millis_text(fixed_now))
  testthat::expect_type(millis, "character")
  testthat::expect_match(millis, "^[0-9]+$")
  testthat::expect_gt(as.numeric(millis), .Machine$integer.max)

  url <- testthat::expect_no_warning(
    env$soak_app_request_url("http://127.0.0.1:28081", "user001", "turkish_prompt", fixed_now)
  )
  testthat::expect_match(url, "[?]_soak_user=user001", fixed = FALSE)
  testthat::expect_match(url, "&_soak_scenario=turkish_prompt", fixed = TRUE)
  testthat::expect_match(url, paste0("&_soak_t=", millis), fixed = TRUE)
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
  # Bu test genel evidence semasini dogrular; etkilesimli serit sonucu saglamaz.
  # Bu yuzden seridi istemiyoruz (aksi halde "istenen ama calismayan" enforce
  # kurali bilincli olarak FAIL uretirdi; o davranis ayri testte dogrulanir).
  cfg$interactive_lane <- FALSE
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
testthat::test_that("config etkilesimli serit alanlarini sunar ve public config sir icermez", {
  env <- new.env(); soak_source_modules(env)
  withr::with_envvar(list(MERGEN_SOAK_PROFILE = "smoke", MERGEN_SOAK_INTERACTIVE_LANE = NA,
                          MERGEN_SOAK_INTERACTIVE_USERS = "7"), {
    cfg <- env$soak_resolve_config()
    testthat::expect_true(isTRUE(cfg$interactive_lane))
    testthat::expect_equal(cfg$interactive_users, 7L)
    testthat::expect_true(cfg$interactive_iterations >= 1L)
    pub <- env$soak_config_public(cfg)
    testthat::expect_true("interactive_lane" %in% names(pub))
    testthat::expect_true("interactive_users" %in% names(pub))
  })
})

# ------------------------------------------------------------------------------
testthat::test_that("etkilesimli serit: gercek DB havuzu/islem/encoding/izolasyon (offline)", {
  testthat::skip_if_not_installed("pool")
  testthat::skip_if_not_installed("RSQLite")
  testthat::skip_if_not_installed("DBI")

  env <- new.env(); soak_source_modules(env)
  cfg <- list(interactive_users = 5L, interactive_iterations = 1L, interactive_lane = TRUE,
              thresholds = list(success_rate_min = 0.98, p95_latency_ms_max = 0L,
                                memory_growth_mb_max = -1, temp_growth_mb_max = -1,
                                fail_on_browser_console_errors = FALSE, fail_on_mojibake = TRUE,
                                fail_on_secret_leak = TRUE, fail_on_interactive_db_leak = TRUE,
                                fail_on_interactive_unavailable = TRUE),
              llm_lane = "fake")

  res <- tryCatch(env$soak_interactive_lane(cfg, sessions = 5L),
                  error = function(e) list(available = FALSE, reason = conditionMessage(e)))
  testthat::skip_if_not(isTRUE(res$available),
                        sprintf("Etkilesimli serit yardimcilari yuklenemedi: %s", res$reason %||% ""))

  # Gercek DB havuzu: checkout == return (sizinti yok).
  testthat::expect_equal(res$db_pool$outstanding_checkouts, 0L)
  testthat::expect_true(res$db_pool$no_leak)
  testthat::expect_true(res$db_pool$tx_commit >= 1L)
  testthat::expect_true(res$db_pool$tx_rollback >= 1L)

  # Oturum eylemleri basarili; izolasyon/rollback/upload/mojibake guvenli.
  testthat::expect_equal(res$summary$success_rate, 1)
  testthat::expect_true(res$isolation_pass)
  # Gercek scoping kaniti: ayni okuyucu KOMSU kullanici satirini disladi.
  testthat::expect_true(res$isolation_excludes_other)
  testthat::expect_equal(res$isolation_exclusion_failures, 0L)
  # Anahtar-sahip uyusmazligi: yabanci sahipli anahtar reddedildi.
  testthat::expect_true(res$key_owner_mismatch_rejected)
  testthat::expect_equal(res$key_owner_mismatch_failures, 0L)
  testthat::expect_true(res$rollback_pass)
  testthat::expect_true(res$upload_pass)
  testthat::expect_equal(res$mojibake_hits, 0L)
  testthat::expect_true(res$actions >= res$sessions * 6L)

  # Esik degerlendirme: interactive kontrolleri olculur ve gecer.
  s <- env$soak_metrics_summary(env$soak_metrics_new())  # bos HTTP ozeti
  inproc <- list(available = FALSE)
  mg <- list(rss_measured = FALSE, process_rss_growth_mb = NA)
  checks <- env$soak_evaluate_thresholds(cfg, s, inproc, list(total_leaks = 0L), mg, NA,
                                         TRUE, 0L, res)
  names_checks <- vapply(checks, function(c) c$name, character(1))
  for (nm in c("interactive_db_no_leak", "interactive_cross_session_isolation",
               "interactive_isolation_excludes_other", "interactive_key_owner_mismatch_rejected",
               "interactive_upload_validation")) {
    testthat::expect_true(nm %in% names_checks, info = nm)
  }
  for (nm in c("interactive_db_no_leak", "interactive_isolation_excludes_other",
               "interactive_key_owner_mismatch_rejected", "interactive_upload_validation")) {
    chk <- Filter(function(c) c$name == nm, checks)[[1]]
    testthat::expect_true(isTRUE(chk$measured) && isTRUE(chk$pass), info = nm)
  }

  # Evidence interactive blogu icerir; metrics_df ham dosya yolu sizdirmaz.
  outcome <- env$soak_threshold_outcome(checks)
  proofs <- env$soak_proof_statements(cfg, s, inproc, list(reachable = FALSE), res)
  ev <- env$soak_build_evidence(cfg, s, inproc, NULL, list(), list(total_leaks = 0L),
                                list(), mg, list(), list(reachable = FALSE), NULL, checks, outcome,
                                proofs, 1.0, character(0), character(0), TRUE, 0L, res)
  testthat::expect_true("interactive_lane" %in% names(ev))
  testthat::expect_true(isTRUE(ev$interactive_lane$available))
  testthat::expect_true(ev$interactive_lane$db_pool$no_leak)
  testthat::expect_true(isTRUE(ev$interactive_lane$isolation_excludes_other_user))
  ev_txt <- jsonlite::toJSON(ev, auto_unbox = TRUE, null = "null")
  testthat::expect_false(grepl(".sqlite", ev_txt, fixed = TRUE))
})

# ------------------------------------------------------------------------------
testthat::test_that("istenen ama calismayan etkilesimli serit ENFORCED FAIL'dir (sessiz PASS degil)", {
  env <- new.env(); soak_source_modules(env)
  s <- env$soak_metrics_summary(env$soak_metrics_new())
  inproc <- list(available = FALSE)
  mg <- list(rss_measured = FALSE, process_rss_growth_mb = NA)
  base_th <- list(success_rate_min = 0.98, p95_latency_ms_max = 0L,
                  memory_growth_mb_max = -1, temp_growth_mb_max = -1,
                  fail_on_browser_console_errors = FALSE, fail_on_mojibake = TRUE,
                  fail_on_secret_leak = TRUE, fail_on_interactive_db_leak = TRUE)
  unavailable <- list(available = FALSE, reason = "paket eksik")

  # Varsayilan (enforce TRUE): istenen ama calismayan serit -> olculen FAIL.
  cfg_enforce <- list(interactive_lane = TRUE, llm_lane = "fake", http_lane = TRUE,
                      thresholds = c(base_th, list(fail_on_interactive_unavailable = TRUE)))
  checks <- env$soak_evaluate_thresholds(cfg_enforce, s, inproc, list(total_leaks = 0L),
                                         mg, NA, TRUE, 0L, unavailable)
  chk <- Filter(function(c) c$name == "interactive_lane_available", checks)
  testthat::expect_equal(length(chk), 1L)
  testthat::expect_true(isTRUE(chk[[1]]$measured))
  testthat::expect_false(isTRUE(chk[[1]]$pass))
  outcome <- env$soak_threshold_outcome(checks)
  testthat::expect_false(outcome$pass)  # gate FAIL olmali

  # Opt-out (enforce FALSE): UNMEASURED, gate'i kirmaz.
  cfg_off <- list(interactive_lane = TRUE, llm_lane = "fake", http_lane = TRUE,
                  thresholds = c(base_th, list(fail_on_interactive_unavailable = FALSE)))
  checks2 <- env$soak_evaluate_thresholds(cfg_off, s, inproc, list(total_leaks = 0L),
                                          mg, NA, TRUE, 0L, unavailable)
  chk2 <- Filter(function(c) c$name == "interactive_lane_available", checks2)[[1]]
  testthat::expect_false(isTRUE(chk2$measured))
})

# ------------------------------------------------------------------------------
testthat::test_that("izolasyon ve upload, DB-leak opt-out'undan BAGIMSIZ enforced kalir", {
  env <- new.env(); soak_source_modules(env)
  s <- env$soak_metrics_summary(env$soak_metrics_new())
  inproc <- list(available = FALSE)
  mg <- list(rss_measured = FALSE, process_rss_growth_mb = NA)
  th <- list(success_rate_min = 0.98, p95_latency_ms_max = 0L,
             memory_growth_mb_max = -1, temp_growth_mb_max = -1,
             fail_on_browser_console_errors = FALSE, fail_on_mojibake = TRUE,
             fail_on_secret_leak = TRUE,
             fail_on_interactive_db_leak = FALSE,        # operator yalniz leak sayacindan opt-out
             fail_on_interactive_unavailable = TRUE)
  cfg <- list(interactive_lane = TRUE, llm_lane = "fake", http_lane = TRUE, thresholds = th)

  base_i <- list(available = TRUE,
                 summary = list(requests = 10L, success = 10L, errors = 0L, timeouts = 0L,
                                success_rate = 1, p50_latency_ms = 1, p95_latency_ms = 1,
                                p99_latency_ms = 1, throughput_ops_per_min = 1, scenario_counts = list()),
                 db_pool = list(checkout = 10L, returned = 9L, outstanding_checkouts = 1L,
                                tx_begin = 10L, tx_commit = 8L, tx_rollback = 2L, no_leak = FALSE),
                 isolation_pass = TRUE, isolation_excludes_other = TRUE,
                 key_owner_mismatch_rejected = TRUE, upload_pass = TRUE, upload_failures = 0L,
                 rollback_pass = TRUE, mojibake_hits = 0L)

  # Izolasyon REGRESYONU + leak opt-out: izolasyon yine de measured FAIL olmali.
  bad_iso <- base_i; bad_iso$isolation_pass <- FALSE
  checks <- env$soak_evaluate_thresholds(cfg, s, inproc, list(total_leaks = 0L), mg, NA, TRUE, 0L, bad_iso)
  iso_chk <- Filter(function(c) c$name == "interactive_cross_session_isolation", checks)[[1]]
  testthat::expect_true(isTRUE(iso_chk$measured))
  testthat::expect_false(isTRUE(iso_chk$pass))
  leak_chk <- Filter(function(c) c$name == "interactive_db_no_leak", checks)[[1]]
  testthat::expect_true(isTRUE(leak_chk$pass))   # leak opt-out edildi (raporlandi-only)
  testthat::expect_false(env$soak_threshold_outcome(checks)$pass)  # gate FAIL (izolasyon)

  # Upload REGRESYONU: her zaman enforced (leak opt-out etkilemez).
  bad_upload <- base_i; bad_upload$upload_pass <- FALSE; bad_upload$upload_failures <- 3L
  checks2 <- env$soak_evaluate_thresholds(cfg, s, inproc, list(total_leaks = 0L), mg, NA, TRUE, 0L, bad_upload)
  up_chk <- Filter(function(c) c$name == "interactive_upload_validation", checks2)[[1]]
  testthat::expect_true(isTRUE(up_chk$measured))
  testthat::expect_false(isTRUE(up_chk$pass))
  testthat::expect_false(env$soak_threshold_outcome(checks2)$pass)

  # Anahtar-sahip uyusmazligi REGRESYONU: enforced.
  bad_key <- base_i; bad_key$key_owner_mismatch_rejected <- FALSE
  checks3 <- env$soak_evaluate_thresholds(cfg, s, inproc, list(total_leaks = 0L), mg, NA, TRUE, 0L, bad_key)
  key_chk <- Filter(function(c) c$name == "interactive_key_owner_mismatch_rejected", checks3)[[1]]
  testthat::expect_true(isTRUE(key_chk$measured))
  testthat::expect_false(isTRUE(key_chk$pass))
  testthat::expect_false(env$soak_threshold_outcome(checks3)$pass)
})

# ------------------------------------------------------------------------------
testthat::test_that("telemetri: config + port cozumleme + olculemeyen guvenli ozet", {
  env <- new.env(); soak_source_modules(env)

  withr::with_envvar(list(MERGEN_SOAK_TELEMETRY_ENABLED = NA,
                          MERGEN_SOAK_TELEMETRY_INTERVAL_SECONDS = NA,
                          MERGEN_SOAK_APP_URL = NA), {
    tc <- env$soak_telemetry_config()
    testthat::expect_true(isTRUE(tc$enabled))            # varsayilan ACIK
    testthat::expect_true(tc$interval_sec >= 1L)
    testthat::expect_equal(tc$app_port, 8009L)           # varsayilan uretim portu
  })

  # Port URL'den cozulur.
  testthat::expect_equal(env$soak_telemetry_port_from_url("http://127.0.0.1:28081/"), 28081L)
  testthat::expect_equal(env$soak_telemetry_port_from_url(""), 8009L)

  # Olculemeyen ozet: CSV yok -> available FALSE + uyari (sessiz PASS DEGIL).
  s <- env$soak_telemetry_summarize(file.path(tempdir(), "no_such_telemetry.csv"))
  testthat::expect_false(isTRUE(s$telemetry_available))
  testthat::expect_equal(s$samples, 0L)
  testthat::expect_true(length(s$telemetry_warnings) >= 1L)

  # Tum sutunlar mevcut (CSV semasi sabit).
  cols <- env$soak_telemetry_columns()
  for (c in c("ts_epoch", "total_cpu_percent", "mem_used_mb", "r_proc_mem_mb",
              "sqlserver_mem_mb", "tcp_connections_to_app")) {
    testthat::expect_true(c %in% cols, info = c)
  }
})

# ------------------------------------------------------------------------------
testthat::test_that("telemetri arka surec: gercek ornek + ozet uretir (offline)", {
  testthat::skip_if_not_installed("callr")
  env <- new.env(); soak_source_modules(env)
  ad <- file.path(tempdir(), paste0("tel_", as.integer(stats::runif(1, 1, 1e6))))
  dir.create(ad, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(ad, recursive = TRUE), add = TRUE)

  h <- env$soak_telemetry_start(ad, list(enabled = TRUE, interval_sec = 1L, app_port = 8009L),
                                max_seconds = 20, loadgen_pid = Sys.getpid())
  testthat::skip_if_not(isTRUE(h$started), "telemetri arka surec baslamadi")
  Sys.sleep(3)
  env$soak_telemetry_stop(h)
  testthat::expect_true(file.exists(h$csv_path))
  s <- env$soak_telemetry_summarize(h$csv_path)
  testthat::expect_true(s$samples >= 1L)
  # Linux'ta CPU/bellek okunabilir -> telemetry_available TRUE; degilse en azindan
  # kontrat olarak NA + uyari (sessiz PASS degil).
  testthat::expect_true(is.logical(s$telemetry_available))
})

# ------------------------------------------------------------------------------
testthat::test_that("hata atfi: siniflandirma + retryable + toplu kirilim", {
  env <- new.env(); soak_source_modules(env)

  testthat::expect_equal(env$soak_classify_failure("ok", 200L, "", "app"), "n/a")
  testthat::expect_equal(env$soak_classify_failure("timeout", NA, "Failed to connect", "app"),
                         "connection_timeout")
  testthat::expect_equal(env$soak_classify_failure("timeout", NA, "Timeout was reached", "app"),
                         "response_timeout")
  testthat::expect_equal(env$soak_classify_failure("timeout", NA, "Operation timed out", "fake_llm"),
                         "fake_llm_timeout")
  testthat::expect_equal(env$soak_classify_failure("timeout", NA, "x", "proxy_llm"),
                         "proxy_llm_timeout")
  testthat::expect_equal(env$soak_classify_failure("error", 429L, "", "app"), "rate_limited")
  testthat::expect_equal(env$soak_classify_failure("error", 500L, "", "app"), "app_http_error")
  testthat::expect_equal(env$soak_classify_failure("error", 500L, "", "real_llm"),
                         "real_llm_gateway_error")
  testthat::expect_equal(env$soak_classify_failure("error", NA, "Connection refused", "app"),
                         "connection_error")

  testthat::expect_true(env$soak_failure_retryable("response_timeout", NA))
  testthat::expect_true(env$soak_failure_retryable("app_http_error", 503L))
  testthat::expect_false(env$soak_failure_retryable("app_http_error", 404L))

  # Toplu kirilim: timeout_class dagilimini + en yaygin sinifi uretir.
  m <- env$soak_metrics_new()
  for (i in 1:30) env$soak_metrics_record(m, "fake", "chat_short", 120, "ok", 200L, 10, "n/a", "n/a", "app")
  for (i in 1:8) env$soak_metrics_record(m, "fake", "chat_long", 20000, "timeout", NA, 0, "n/a", "response_timeout", "app")
  for (i in 1:2) env$soak_metrics_record(m, "fake", "chat_code", 200, "error", 500L, 0, "n/a", "app_http_error", "app")
  df <- env$soak_metrics_as_df(m)
  testthat::expect_true("timeout_class" %in% names(df))
  testthat::expect_true("endpoint_kind" %in% names(df))
  attr <- env$soak_timeout_attribution(df)
  testthat::expect_equal(attr$total_failures, 10L)
  testthat::expect_equal(attr$timeout_breakdown$response_timeout, 8L)
  testthat::expect_equal(attr$timeout_breakdown$app_http_error, 2L)
  testthat::expect_equal(attr$top_failure_classes[[1]]$class, "response_timeout")
})

# ------------------------------------------------------------------------------
testthat::test_that("kademeli merdiven: ozet (stabil/ilk-basarisiz/onerilen) + ipuclari", {
  env <- new.env(); soak_source_modules(env)

  # 50 ve 100 gecti, 250 basarisiz (eff < 0.98). stop_on_first ile 250'de durur.
  steps <- list(
    list(users = 50L, effective_success_rate = 1.0, p95_latency_ms = 200, pass = TRUE,
         telemetry = list(telemetry_available = TRUE, max_total_cpu_percent = 40)),
    list(users = 100L, effective_success_rate = 0.999, p95_latency_ms = 400, pass = TRUE,
         telemetry = list(telemetry_available = TRUE, max_total_cpu_percent = 55)),
    list(users = 250L, effective_success_rate = 0.62, p95_latency_ms = 17000, pass = FALSE,
         telemetry = list(telemetry_available = TRUE, max_total_cpu_percent = 60))
  )
  lad <- env$soak_capacity_ladder_summarize(steps, c(50L, 100L, 250L, 500L, 1000L),
                                            stable_min = 0.98, stop_on_first = TRUE)
  testthat::expect_true(lad$ran)
  testthat::expect_equal(lad$stable_capacity_users, 100L)
  testthat::expect_equal(lad$first_failed_capacity_users, 250L)
  testthat::expect_equal(lad$recommended_next_target, 250L)  # stabil(100) sonrasi ladder adimi
  testthat::expect_false(lad$all_steps_pass)
  # p95 keskin sicradi (400 -> 17000) + CPU dusuk (60<70) -> event-loop kuyruklanma ipucu.
  testthat::expect_true("possible_app_or_event_loop_queueing" %in% lad$bottleneck_hints)

  # CPU saturasyonu senaryosu.
  steps_cpu <- list(
    list(users = 50L, effective_success_rate = 1.0, p95_latency_ms = 200, pass = TRUE,
         telemetry = list(telemetry_available = TRUE, max_total_cpu_percent = 60)),
    list(users = 100L, effective_success_rate = 0.5, p95_latency_ms = 9000, pass = FALSE,
         telemetry = list(telemetry_available = TRUE, max_total_cpu_percent = 96))
  )
  lad2 <- env$soak_capacity_ladder_summarize(steps_cpu, c(50L, 100L), 0.98, TRUE)
  testthat::expect_equal(lad2$stable_capacity_users, 50L)
  testthat::expect_true("possible_cpu_saturation" %in% lad2$bottleneck_hints)

  # Telemetri yok + basarisiz -> "unknown_timeout_saturation" (durust UNMEASURED).
  steps_unk <- list(
    list(users = 50L, effective_success_rate = 1.0, p95_latency_ms = 200, pass = TRUE,
         telemetry = list(telemetry_available = FALSE)),
    list(users = 100L, effective_success_rate = 0.4, p95_latency_ms = 18000, pass = FALSE,
         telemetry = list(telemetry_available = FALSE))
  )
  lad3 <- env$soak_capacity_ladder_summarize(steps_unk, c(50L, 100L), 0.98, TRUE)
  testthat::expect_true("unknown_timeout_saturation" %in% lad3$bottleneck_hints)

  # Hicbiri basarisiz degil -> stabil = en ust adim, ipucu "no_failure...".
  steps_ok <- list(
    list(users = 50L, effective_success_rate = 1, p95_latency_ms = 100, pass = TRUE,
         telemetry = list(telemetry_available = TRUE, max_total_cpu_percent = 30))
  )
  lad4 <- env$soak_capacity_ladder_summarize(steps_ok, c(50L), 0.98, TRUE)
  testthat::expect_true(lad4$all_steps_pass)
  testthat::expect_equal(lad4$bottleneck_hints, "no_failure_observed_within_ladder")
})

# ------------------------------------------------------------------------------
testthat::test_that("kademeli merdiven esigi: basarisiz adim ENFORCED FAIL; istenmeyen UNMEASURED", {
  env <- new.env(); soak_source_modules(env)
  s <- env$soak_metrics_summary(env$soak_metrics_new())
  inproc <- list(available = FALSE)
  mg <- list(rss_measured = FALSE, process_rss_growth_mb = NA)
  base_th <- list(success_rate_min = 0.98, p95_latency_ms_max = 0L,
                  memory_growth_mb_max = -1, temp_growth_mb_max = -1,
                  fail_on_browser_console_errors = FALSE, fail_on_mojibake = TRUE,
                  fail_on_secret_leak = TRUE)

  # Merdiven calisti, bir adim FAIL -> capacity_ladder_all_steps_pass measured FAIL.
  cfg <- list(capacity_ladder_enabled = TRUE, llm_lane = "fake", http_lane = TRUE,
              interactive_lane = FALSE, thresholds = base_th)
  lad <- list(ran = TRUE, stable_capacity_users = 100L, first_failed_capacity_users = 250L,
              all_steps_pass = FALSE, stable_success_rate_min = 0.98,
              steps = list(list(users = 50L), list(users = 250L)))
  checks <- env$soak_evaluate_thresholds(cfg, s, inproc, list(total_leaks = 0L), mg, NA, TRUE, 0L,
                                         NULL, lad)
  chk <- Filter(function(c) c$name == "capacity_ladder_all_steps_pass", checks)[[1]]
  testthat::expect_true(isTRUE(chk$measured))
  testthat::expect_false(isTRUE(chk$pass))
  testthat::expect_false(env$soak_threshold_outcome(checks)$pass)

  # Tum adimlar gecti -> PASS.
  lad_ok <- lad; lad_ok$all_steps_pass <- TRUE; lad_ok$first_failed_capacity_users <- NA
  checks_ok <- env$soak_evaluate_thresholds(cfg, s, inproc, list(total_leaks = 0L), mg, NA, TRUE, 0L,
                                            NULL, lad_ok)
  chk_ok <- Filter(function(c) c$name == "capacity_ladder_all_steps_pass", checks_ok)[[1]]
  testthat::expect_true(isTRUE(chk_ok$pass))

  # Istendi ama calismadi -> UNMEASURED (sessiz PASS degil, ama gate'i de kirmaz).
  checks_unrun <- env$soak_evaluate_thresholds(cfg, s, inproc, list(total_leaks = 0L), mg, NA, TRUE,
                                               0L, NULL, NULL)
  chk_unrun <- Filter(function(c) c$name == "capacity_ladder_all_steps_pass", checks_unrun)[[1]]
  testthat::expect_false(isTRUE(chk_unrun$measured))
})

# ------------------------------------------------------------------------------
testthat::test_that("real-LLM yanit siniflandirmasi: gateway/auth/policy/uretim ayrimi", {
  env <- new.env(); soak_source_modules(env)

  testthat::expect_equal(env$soak_classify_real_llm_response(200L, "{}", "", FALSE),
                         "generation_completed")
  testthat::expect_equal(env$soak_classify_real_llm_response(200L, "{}", "", TRUE),
                         "streaming_completed")
  testthat::expect_equal(env$soak_classify_real_llm_response(401L, "", "", FALSE), "auth_rejected")
  testthat::expect_equal(env$soak_classify_real_llm_response(404L, "", "", FALSE),
                         "model_or_route_not_found")
  testthat::expect_equal(env$soak_classify_real_llm_response(429L, "", "", FALSE), "rate_limited")
  # ERR-234 / rate limit policy failed -> gateway_policy_failed (app yuk hatasi DEGIL).
  testthat::expect_equal(
    env$soak_classify_real_llm_response(
      500L, '{"faultCode":"ERR-234","faultString":"Endpoint Rate Limit policy failed"}', "", FALSE),
    "gateway_policy_failed")
  testthat::expect_equal(env$soak_classify_real_llm_response(NA, "", "Timeout was reached", FALSE),
                         "real_llm_timeout")
  testthat::expect_equal(env$soak_classify_real_llm_response(NA, "", "Could not connect", FALSE),
                         "app_unreachable")
})

# ------------------------------------------------------------------------------
testthat::test_that("config: telemetri + merdiven + real-llm throughput alanlari ve secret-safe", {
  env <- new.env(); soak_source_modules(env)

  withr::with_envvar(list(MERGEN_SOAK_PROFILE = "smoke", MERGEN_SOAK_CAPACITY_LADDER = "true",
                          MERGEN_SOAK_CAPACITY_USERS = "50,100,250",
                          MERGEN_SOAK_CAPACITY_STEP_SECONDS = NA,
                          MERGEN_SOAK_STABLE_SUCCESS_RATE_MIN = NA,
                          MERGEN_REAL_LLM_THROUGHPUT_PROBE = "true",
                          MERGEN_REAL_LLM_THROUGHPUT_USERS = "9"), {
    cfg <- env$soak_resolve_config()
    testthat::expect_true(isTRUE(cfg$capacity_ladder_enabled))
    testthat::expect_equal(cfg$capacity_ladder_users, c(50L, 100L, 250L))
    testthat::expect_equal(cfg$capacity_ladder_step_seconds, 600L)   # ladder varsayilani
    testthat::expect_equal(cfg$stable_success_rate_min, 0.98)
    testthat::expect_true(isTRUE(cfg$telemetry_enabled))
    testthat::expect_true(isTRUE(cfg$real_llm_throughput_enabled))
    # Kullanici tavani (varsayilan 5) uygulanir.
    testthat::expect_true(cfg$real_llm_throughput$users <= 5L)

    pub <- env$soak_config_public(cfg)
    for (k in c("capacity_ladder_enabled", "capacity_ladder_users", "telemetry_enabled",
                "real_llm_throughput_enabled", "stable_success_rate_min")) {
      testthat::expect_true(k %in% names(pub), info = k)
    }
  })

  # Merdiven varsayilan KAPALI; ladder default kullanicilari 1000'e kadar.
  withr::with_envvar(list(MERGEN_SOAK_CAPACITY_LADDER = NA, MERGEN_SOAK_CAPACITY_USERS = NA), {
    cfg2 <- env$soak_resolve_config()
    testthat::expect_false(isTRUE(cfg2$capacity_ladder_enabled))
    testthat::expect_true(1000L %in% cfg2$capacity_ladder_users)
  })
})

# ------------------------------------------------------------------------------
testthat::test_that("yeni artifact alanlari evidence'a girer ve redaksiyondan gecer", {
  env <- new.env(); soak_source_modules(env)
  cfg <- withr::with_envvar(list(MERGEN_SOAK_PROFILE = "smoke"), env$soak_resolve_config())
  cfg$interactive_lane <- FALSE

  m <- env$soak_metrics_new()
  for (i in 1:20) env$soak_metrics_record(m, "fake", "chat_short", 100 + i, "ok", 200L, 40, "n/a", "n/a", "app")
  for (i in 1:3) env$soak_metrics_record(m, "fake", "chat_long", 20000, "timeout", NA, 0, "n/a", "response_timeout", "app")
  s <- env$soak_metrics_summary(m)
  inproc <- list(available = FALSE)
  mg <- list(rss_measured = FALSE, process_rss_growth_mb = NA)

  # Planlanmis sahte sir: telemetri uyarisi + ipucu icine konur (redaksiyon kapsamali).
  secret <- paste0("sk-", "leak-fake-value-zzzzzz99")
  telemetry <- list(telemetry_available = TRUE, samples = 5L, max_total_cpu_percent = 80,
                    max_tcp_connections_to_app = 120L, max_mem_used_mb = 2048,
                    max_r_process_memory_mb = 512, max_sqlserver_memory_mb = 1024,
                    telemetry_warnings = c(paste0("uyari token=", secret)))
  ladder <- list(ran = TRUE, stable_capacity_users = 100L, first_failed_capacity_users = 250L,
                 recommended_next_target = 250L, all_steps_pass = FALSE,
                 stable_success_rate_min = 0.98,
                 bottleneck_hints = c("possible_cpu_saturation"),
                 steps = list(list(users = 50L, duration_seconds = 600, requests = 100L,
                                   success = 100L, errors = 0L, timeouts = 0L,
                                   raw_success_rate = 1, effective_success_rate = 1,
                                   p50_latency_ms = 100, p95_latency_ms = 200, p99_latency_ms = 250,
                                   throughput_ops_per_min = 600, db_pool = NULL,
                                   telemetry = list(telemetry_available = TRUE,
                                                    max_total_cpu_percent = 40,
                                                    max_tcp_connections_to_app = 50L),
                                   pass = TRUE)))
  ta <- env$soak_timeout_attribution(env$soak_metrics_as_df(m))

  checks <- env$soak_evaluate_thresholds(cfg, s, inproc, list(total_leaks = 0L), mg, 0, TRUE, 3L,
                                         NULL, ladder)
  outcome <- env$soak_threshold_outcome(checks)
  proofs <- env$soak_proof_statements(cfg, s, inproc, list(reachable = FALSE), NULL,
                                      telemetry, ladder)
  ev <- env$soak_build_evidence(cfg, s, inproc, NULL, list(), list(total_leaks = 0L),
                                list(), mg, list(), list(reachable = FALSE), NULL, checks, outcome,
                                proofs, 1.0, character(0), character(0), TRUE, 3L,
                                NULL, telemetry, ladder, ta)

  testthat::expect_true("system_telemetry" %in% names(ev))
  testthat::expect_true("capacity_ladder" %in% names(ev))
  testthat::expect_true("timeout_attribution" %in% names(ev))
  testthat::expect_true(isTRUE(ev$system_telemetry$telemetry_available))
  testthat::expect_equal(ev$capacity_ladder$stable_capacity_users, 100L)
  testthat::expect_equal(ev$timeout_attribution$total_failures, 3L)

  # Artifact yazimi: yeni dosyalar uretilir + redaksiyon planlanmis siri yakalar.
  tmp <- file.path(tempdir(), paste0("soak_art2_", as.integer(stats::runif(1, 1, 1e6))))
  red <- env$soak_write_artifacts(tmp, cfg, m, ev, NULL, list(), NULL)
  testthat::expect_equal(red$total_leaks, 0L)   # planlanmis sir redakte edildi
  testthat::expect_true(file.exists(file.path(tmp, "capacity_ladder.csv")))
  testthat::expect_true(file.exists(file.path(tmp, "capacity_ladder_summary.json")))
  testthat::expect_true(file.exists(file.path(tmp, "system_telemetry_summary.json")))
  testthat::expect_true(file.exists(file.path(tmp, "timeout_attribution.json")))
  # Sahte sir hicbir artifact'ta ham gorunmemeli.
  for (af in list.files(tmp, full.names = TRUE, recursive = TRUE)) {
    if (grepl("\\.(json|jsonl|csv|md)$", af)) {
      body <- paste(readLines(af, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
      testthat::expect_false(grepl("leak-fake-value-zzzzzz99", body, fixed = TRUE), info = basename(af))
    }
  }
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
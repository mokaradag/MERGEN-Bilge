# ==============================================================================
# Dosya Yolu: tests/scripts/run_operational_soak_gate.R
# Aciklama:
#   MERGEN Bilge icin OPERASYONEL SOAK/YUK kapisi. Uc seritli tasarim:
#     Lane A (fake)        : yerel sahte OpenAI-uyumlu LLM; ana yuksek
#                            eszamanlilik seridi; SIFIR gercek anahtar.
#     Lane B (proxy)       : sahte kisisel anahtar yonlendirme/izolasyon kaniti;
#                            opsiyonel throttle'li gercek iletim.
#     Lane C (real-canary) : tek gercek anahtar, cok dusuk eszamanlilik canary.
#
#   Bu kapi VM kanit kapisinin (run_vm_evidence_gate.R) YERINE GECMEZ; ayridir.
#   Her zaman artifact uretir (basarisizlikta bile). Durustluk: does_prove /
#   does_not_prove acikca yazilir; olculemeyen esikler SESSIZCE GECMEZ.
#
#   Profiller (MERGEN_SOAK_PROFILE): smoke (varsayilan), pilot, org, stress,
#   fake_llm, proxy_llm, real_llm.
#
#   Bu dosya BILEREK ASCII-guvenlidir (Turkce ozel karakter yok); operasyonel
#   giris noktasidir ve farkli locale'lerde source/Rscript ile calistirilir.
#
#   Kullanim (Windows CMD):
#     Rscript tests/scripts/run_operational_soak_gate.R
#     set MERGEN_SOAK_PROFILE=pilot && Rscript tests/scripts/run_operational_soak_gate.R
# ==============================================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || is.na(x[1])) y else x

# --- UTF-8 locale (Turkce icerikli app helper'lari in-process yuklenir) --------
for (.loc in c("C.UTF-8", "en_US.UTF-8", "tr_TR.UTF-8")) {
  ok <- tryCatch(nzchar(Sys.setlocale("LC_CTYPE", .loc)),
                 error = function(e) FALSE, warning = function(w) FALSE)
  if (isTRUE(ok)) break
}
options(warn = 1)

# --- Repo kokunu bul + oraya gec ----------------------------------------------
soak_repo_root <- function() {
  for (cand in c(".", "..", "../..")) {
    if (file.exists(file.path(cand, "app.R")) &&
        dir.exists(file.path(cand, "R")) &&
        dir.exists(file.path(cand, "tests", "scripts"))) {
      return(normalizePath(cand, winslash = "/", mustWork = TRUE))
    }
  }
  stop("run_operational_soak_gate.R repo kokunden calistirilmalidir.", call. = FALSE)
}
repo_root <- soak_repo_root()
old_wd <- getwd()
setwd(repo_root)
on.exit(setwd(old_wd), add = TRUE)

# --- .Renviron (varsa) yukle; mevcut shell degerleri oncelikli ----------------
soak_load_repo_renviron <- function(path = ".Renviron") {
  if (!file.exists(path)) return(FALSE)
  before <- Sys.getenv(names(Sys.getenv()), unset = NA_character_)
  keep <- names(before)[!is.na(before) & nzchar(before)]
  ok <- tryCatch(readRenviron(path), error = function(e) FALSE, warning = function(w) FALSE)
  if (!isTRUE(ok)) return(FALSE)
  for (nm in keep) do.call(Sys.setenv, stats::setNames(list(unname(before[nm])), nm))
  TRUE
}
invisible(soak_load_repo_renviron(".Renviron"))

# --- Bagimliliklar -------------------------------------------------------------
for (pkg in c("httpuv", "curl", "jsonlite", "callr", "later", "promises")) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop(sprintf("Soak kapisi icin '%s' paketi gereklidir.", pkg), call. = FALSE)
  }
}

soak_src <- function(rel) source(file.path("tests", "scripts", rel), encoding = "UTF-8")
soak_src("soak_secret_redaction.R")
soak_src("soak_config.R")
soak_src("soak_metrics.R")
soak_src("soak_scenarios.R")
soak_src("mock_llm_server.R")
soak_src("proxy_llm_server.R")
soak_src("soak_client.R")
soak_src("soak_artifacts.R")

cfg <- soak_resolve_config()
artifact_dir <- cfg$artifact_dir
dir.create(file.path(artifact_dir, "logs"), recursive = TRUE, showWarnings = FALSE)

cat("== MERGEN Operasyonel Soak Kapisi ==\n")
cat(sprintf("Profil: %s | Serit: %s | Eszamanli: %d | Sure: %.0fs\n",
            cfg$profile, cfg$llm_lane, cfg$concurrent_users, cfg$duration_sec))
cat(sprintf("Kullanici tabani hedefi: %d | Artifact: %s\n",
            cfg$user_base_target, artifact_dir))
cat(sprintf("Kapasite egrisi: %s\n",
            if (isTRUE(cfg$capacity_curve_enabled)) paste(cfg$capacity_curve_users, collapse = ",") else "kapali"))

# ------------------------------------------------------------------------------
# LLM serit sunucusunu baslatir (fake/proxy). Port cakismasinda yeniden dener.
# ------------------------------------------------------------------------------
soak_start_llm_server <- function(cfg, artifact_dir) {
  lane <- cfg$llm_lane
  host <- cfg$server_host
  log_path <- file.path(artifact_dir, "logs",
                        if (identical(lane, "proxy")) "proxy_llm.log" else "fake_llm.log")
  jsonl_path <- if (identical(lane, "proxy"))
    file.path(artifact_dir, "logs", "proxy_requests.jsonl") else NULL
  repo <- normalizePath(".")
  run_fn <- if (identical(lane, "proxy")) "proxy_llm_run" else "mock_llm_run"

  for (attempt in seq_len(6L)) {
    port <- if (cfg$server_port > 0L) cfg$server_port else httpuv::randomPort(min = 12000, max = 19999)
    ready <- tempfile(fileext = ".ready")
    proc <- callr::r_bg(
      function(repo, host, port, cfg, log_path, ready, jsonl_path, run_fn) {
        setwd(repo)
        for (loc in c("C.UTF-8", "en_US.UTF-8", "tr_TR.UTF-8")) {
          if (tryCatch(nzchar(Sys.setlocale("LC_CTYPE", loc)),
                       error = function(e) FALSE, warning = function(w) FALSE)) break
        }
        source("tests/scripts/soak_secret_redaction.R", encoding = "UTF-8")
        source("tests/scripts/mock_llm_server.R", encoding = "UTF-8")
        source("tests/scripts/proxy_llm_server.R", encoding = "UTF-8")
        if (identical(run_fn, "proxy_llm_run")) {
          proxy_llm_run(host, port, config = cfg, log_path = log_path,
                        ready_path = ready, jsonl_path = jsonl_path)
        } else {
          mock_llm_run(host, port, config = cfg, log_path = log_path, ready_path = ready)
        }
      },
      args = list(repo, host, port, cfg, log_path, ready, jsonl_path, run_fn),
      supervise = TRUE
    )

    ok <- FALSE; bind_failed <- FALSE
    for (i in seq_len(120L)) {
      if (file.exists(ready)) {
        content <- tryCatch(readLines(ready, warn = FALSE), error = function(e) character(0))
        if (any(grepl("BIND_FAILED", content))) { bind_failed <- TRUE; break }
        if (length(content) >= 1L && nzchar(content[1])) { ok <- TRUE; break }
      }
      if (!proc$is_alive()) break
      Sys.sleep(0.1)
    }

    if (isTRUE(ok)) {
      health_ok <- FALSE
      for (i in seq_len(40L)) {
        h <- tryCatch(curl::curl_fetch_memory(sprintf("http://%s:%d/healthz", host, port)),
                      error = function(e) NULL)
        if (!is.null(h) && identical(as.integer(h$status_code), 200L)) { health_ok <- TRUE; break }
        Sys.sleep(0.1)
      }
      summary_path <- if (identical(lane, "proxy")) "soak/proxy-summary" else "soak/mock-summary"
      return(list(proc = proc, url = sprintf("http://%s:%d/v1/chat/completions", host, port),
                  health_url = sprintf("http://%s:%d/healthz", host, port),
                  summary_url = sprintf("http://%s:%d/%s", host, port, summary_path),
                  port = port, host = host, log_path = log_path, jsonl_path = jsonl_path,
                  ok = health_ok))
    }

    tryCatch(proc$kill(), error = function(e) NULL)
    if (cfg$server_port > 0L && !bind_failed) break  # sabit port istendi ama acilamadi
  }
  list(proc = NULL, ok = FALSE, error = "LLM serit sunucusu baslatilamadi/baglanamadi.")
}

# ------------------------------------------------------------------------------
# Ana akis (her zaman artifact uretmek icin tryCatch ile sarili).
# ------------------------------------------------------------------------------
metrics <- soak_metrics_new()
capacity_rows <- list()
warnings_vec <- character(0)
skipped_vec <- character(0)
proxy_summary <- NULL
failure_probe <- NULL
server_handle <- NULL
server_alive_at_end <- FALSE
injected_faults <- 0L
server_summary <- NULL
main_error <- NULL
attach_result <- list(configured = FALSE, reachable = FALSE)
inprocess <- list(available = FALSE, reason = "calismadi")

mem_before <- soak_sample_memory()
temp_dirs <- unique(c(tempdir(), Sys.getenv("MERGEN_UPLOADS_DIR", ""),
                      Sys.getenv("MERGEN_MCP_BASE_DIR", "")))
temp_before <- soak_sample_tempdirs(temp_dirs)

run_started <- Sys.time()

main_result <- tryCatch({

  # --- In-process uygulama-yolu alistirmalari ---
  if (isTRUE(cfg$in_process_exercises)) {
    cat("[soak] in-process uygulama-yolu alistirmalari...\n")
    inprocess <- soak_inprocess_exercises(cfg, iterations = 40L)
    if (!isTRUE(inprocess$available)) {
      warnings_vec <- c(warnings_vec, sprintf("In-process alistirmalar calismadi: %s", inprocess$reason))
      skipped_vec <- c(skipped_vec, "in_process_exercises")
    }
  } else {
    skipped_vec <- c(skipped_vec, "in_process_exercises (kapali)")
  }

  # --- Attach modu (calisan uygulama) ---
  attach_result <- soak_attach_probe(cfg$app_url)

  # --- LLM serit + yuk ---
  if (identical(cfg$llm_lane, "real-canary")) {
    real_url <- cfg$proxy$real_endpoint
    real_key <- Sys.getenv("MERGEN_SOAK_REAL_API_KEY", unset = "")
    if (!nzchar(real_url) || !nzchar(real_key)) {
      warnings_vec <- c(warnings_vec,
        "real-canary: MERGEN_SOAK_REAL_ENDPOINT_URL / MERGEN_SOAK_REAL_API_KEY ayarli degil; HTTP serit atlandi.")
      skipped_vec <- c(skipped_vec, "real_canary_http_lane")
    } else {
      cat(sprintf("[soak] real-canary: %d kullanici, %ds aralik, %.0fs sure...\n",
                  cfg$real_canary$users, cfg$real_canary$interval_sec, cfg$duration_sec))
      soak_real_canary_load(real_url, real_key, cfg, metrics, cfg$duration_sec)
    }
  } else {
    cat(sprintf("[soak] %s LLM sunucusu baslatiliyor...\n", cfg$llm_lane))
    server_handle <- soak_start_llm_server(cfg, artifact_dir)
    if (!isTRUE(server_handle$ok)) {
      stop(sprintf("LLM serit sunucusu hazir degil: %s", server_handle$error %||% "bilinmeyen"))
    }
    cat(sprintf("[soak] LLM serit sunucusu hazir: %s\n", server_handle$url))
    if (!nzchar(cfg$app_url)) {
      stop(paste(
        "MERGEN_SOAK_APP_URL ayarlanmadi; fake/proxy yuk fazi uygulama URL'sine",
        "karsi kosulmalidir. Yerel LLM serit endpoint'i sadece uygulamanin",
        "LLM bagimliligini beslemek ve hata-probe/ozet icin kullanilir."
      ))
    }
    if (!isTRUE(attach_result$reachable)) {
      stop(sprintf("MERGEN_SOAK_APP_URL erisilebilir degil; yuk fazi baslatilmadi: %s",
                   attach_result$note %||% "bilinmeyen"))
    }
    load_url <- cfg$app_url
    cat(sprintf("[soak] uygulama yuk hedefi: %s\n", load_url))
    user_keys <- soak_make_user_keys(cfg$concurrent_users, cfg$llm_lane)

    if (isTRUE(cfg$capacity_curve_enabled)) {
      cat("[soak] kapasite egrisi taramasi...\n")
      for (uc in cfg$capacity_curve_users) {
        from_idx <- soak_metrics_count(metrics) + 1L
        uk <- soak_make_user_keys(uc, cfg$llm_lane)
        cat(sprintf("  - %d kullanici / %ds ...\n", uc, cfg$capacity_step_seconds))
        soak_http_load(load_url, cfg, metrics, cfg$capacity_step_seconds,
                       uc, uk, cfg$llm_lane)
        s <- soak_metrics_slice_summary(metrics, from_idx,
                                        wall_seconds = cfg$capacity_step_seconds)
        capacity_rows[[length(capacity_rows) + 1L]] <- list(
          users = uc, requests = s$requests, success_rate = s$success_rate,
          p95_latency_ms = s$p95_latency_ms, throughput_ops_per_min = s$throughput_ops_per_min
        )
        cat(sprintf("    -> istek=%d basari=%s p95=%sms tput=%s/dk\n",
                    s$requests, as.character(s$success_rate),
                    as.character(s$p95_latency_ms), as.character(s$throughput_ops_per_min)))
      }
    } else {
      cat(sprintf("[soak] yuk: %d eszamanli kullanici, %.0fs...\n",
                  cfg$concurrent_users, cfg$duration_sec))
      soak_http_load(load_url, cfg, metrics, cfg$duration_sec,
                     cfg$concurrent_users, user_keys, cfg$llm_lane)
    }

    # --- Yuk-fazi sunucu ozeti (enjekte-fault hesabi + proxy izolasyon) ---
    # Probe'tan ONCE alinir: probe'un zorladigi faultlar enjekte sayisina karismaz.
    ss <- tryCatch(curl::curl_fetch_memory(server_handle$summary_url), error = function(e) NULL)
    if (!is.null(ss) && identical(as.integer(ss$status_code), 200L)) {
      server_summary <- tryCatch(jsonlite::fromJSON(rawToChar(ss$content), simplifyVector = TRUE),
                                 error = function(e) NULL)
      if (!is.null(server_summary)) {
        injected_faults <- soak_injected_fault_count(server_summary$case_counts)
        if (identical(cfg$llm_lane, "proxy")) proxy_summary <- server_summary
      }
    }

    # --- Hata-enjeksiyon probe (her hata durumunu bir kez zorla) ---
    # AYRI metrics: kasitli enjekte edilen hatalar ana basari oranini kirletmez;
    # her durumun ele alinma sonucu evidence$failure_injection altinda raporlanir.
    cat("[soak] hata-enjeksiyon probe...\n")
    probe_metrics <- soak_metrics_new()
    failure_probe <- tryCatch(
      soak_failure_probe(server_handle$url, cfg, probe_metrics, cfg$llm_lane),
      error = function(e) { warnings_vec <<- c(warnings_vec, sprintf("failure_probe: %s", conditionMessage(e))); NULL }
    )

    server_alive_at_end <- isTRUE(server_handle$proc$is_alive())
  }

  "ok"
}, error = function(e) {
  main_error <<- soak_redact_text(conditionMessage(e))
  warnings_vec <<- c(warnings_vec, sprintf("Ana akis hatasi: %s", main_error))

  # Ana akis erken dusse bile sunucu canlilik bayragini dogru olc.
  if (!is.null(server_handle) && !is.null(server_handle$proc)) {
    server_alive_at_end <<- isTRUE(server_handle$proc$is_alive())

    if (!isTRUE(server_alive_at_end)) {
      warnings_vec <<- c(
        warnings_vec,
        "LLM serit sunucusu ana akis sirasinda sonlanmis gorunuyor."
      )
    }
  }

  paste0("error: ", main_error)
})

duration_actual <- as.numeric(difftime(Sys.time(), run_started, units = "secs"))

# Sunucuyu durdurmadan hemen once canlilik bayragini son kez ornekle.
# Boylece yuk surucusu erken hata verse bile no_server_crash yanlis FAIL olmaz.
if (!identical(cfg$llm_lane, "real-canary") &&
    !is.null(server_handle) && !is.null(server_handle$proc)) {
  server_alive_at_end <- isTRUE(server_handle$proc$is_alive())
}

# Sunucuyu durdur.
if (!is.null(server_handle) && !is.null(server_handle$proc)) {
  invisible(tryCatch(server_handle$proc$kill(), error = function(e) NULL))
}

mem_after <- soak_sample_memory()
temp_after <- soak_sample_tempdirs(temp_dirs)
memory_growth <- soak_memory_growth(mem_before, mem_after)
temp_growth_mb <- (temp_after$bytes - temp_before$bytes) / (1024 * 1024)
temp_summary <- list(before = temp_before, after = temp_after,
                     growth_mb = round(temp_growth_mb, 2))

# ------------------------------------------------------------------------------
# Ozet + esik + kanit + artifact (her zaman calisir).
# ------------------------------------------------------------------------------
summary <- soak_metrics_summary(metrics)

# Redaksiyon kontrolu icin once artifact'lari yazip sonra kontrol etmemiz gerek;
# ancak threshold redaksiyon sonucuna baglidir. Sirayi soyle cozeriz: once
# artifact'lari yaz (gecici evidence ile), redaksiyon self-check yap, sonra
# threshold + evidence'i FINALIZE edip tekrar yaz.

redaction0 <- list(total_leaks = 0L, files = list(), checked = 0L)

threshold_checks <- soak_evaluate_thresholds(
  cfg, summary, inprocess, redaction0, memory_growth, temp_growth_mb,
  server_alive_at_end, injected_faults
)
threshold_outcome <- soak_threshold_outcome(threshold_checks)
proofs <- soak_proof_statements(cfg, summary, inprocess, attach_result)

evidence <- soak_build_evidence(
  cfg, summary, inprocess, proxy_summary, capacity_rows, redaction0,
  list(before = mem_before, after = mem_after), memory_growth, temp_summary,
  attach_result, failure_probe, threshold_checks, threshold_outcome, proofs,
  duration_actual, warnings_vec, skipped_vec, server_alive_at_end, injected_faults
)

redaction <- soak_write_artifacts(artifact_dir, cfg, metrics, evidence,
                                  proxy_summary, capacity_rows, NULL)

# Redaksiyon sonucunu esik + evidence'a yansit ve FINALIZE et.
threshold_checks <- soak_evaluate_thresholds(
  cfg, summary, inprocess, redaction, memory_growth, temp_growth_mb,
  server_alive_at_end, injected_faults
)
threshold_outcome <- soak_threshold_outcome(threshold_checks)
evidence <- soak_build_evidence(
  cfg, summary, inprocess, proxy_summary, capacity_rows, redaction,
  list(before = mem_before, after = mem_after), memory_growth, temp_summary,
  attach_result, failure_probe, threshold_checks, threshold_outcome, proofs,
  duration_actual, warnings_vec, skipped_vec, server_alive_at_end, injected_faults
)
redaction <- soak_write_artifacts(artifact_dir, cfg, metrics, evidence,
                                  proxy_summary, capacity_rows, NULL)

# ------------------------------------------------------------------------------
# Konsol ozeti
# ------------------------------------------------------------------------------
cat("\n=== Soak Ozeti ===\n")
cat(sprintf("Istek: %d | Basari: %d (%.3f) | Hata: %d | Timeout: %d\n",
            summary$requests, summary$success, summary$success_rate %||% NA,
            summary$errors, summary$timeouts))
cat(sprintf("Gecikme p50/p95/p99 (ms): %s / %s / %s | Throughput: %s/dk\n",
            as.character(summary$p50_latency_ms), as.character(summary$p95_latency_ms),
            as.character(summary$p99_latency_ms), as.character(summary$throughput_ops_per_min)))
if (isTRUE(inprocess$available)) {
  kr <- inprocess$key_routing
  cat(sprintf("Anahtar yonlendirme: %d/%d dogru | izolasyon=%s | mojibake_hits=%d\n",
              kr$rows_correct, kr$rows_total, kr$cross_session_isolation_pass,
              inprocess$encoding$mojibake_hits))
}
cat(sprintf("Sir sizinti: %d | Redaksiyon dogrulandi: %s\n",
            redaction$total_leaks, identical(as.integer(redaction$total_leaks), 0L)))
cat("\nEsik kontrolleri:\n")
for (c in threshold_checks) {
  flag <- if (!isTRUE(c$measured)) "UNMEASURED" else if (isTRUE(c$pass)) "PASS" else "FAIL"
  cat(sprintf("  %-32s %-11s deger=%s\n", c$name, flag, as.character(c$value)))
}
cat(sprintf("\nGenel sonuc: %s\n", if (isTRUE(evidence$pass)) "PASS" else "FAIL"))
cat(sprintf("Artifact dizini: %s\n", artifact_dir))
cat(sprintf("Kanit: %s\n", file.path(artifact_dir, "soak_evidence.json")))

if (length(evidence$failure_reasons) > 0L) {
  cat("\nBasarisizlik nedenleri:\n")
  for (r in evidence$failure_reasons) cat(sprintf("  - %s\n", r))
}

if (length(warnings_vec) > 0L) {
  cat("\nUyarilar / ana akis detaylari:\n")
  for (w in warnings_vec) cat(sprintf("  - %s\n", w))
}

if (!is.null(main_error) && nzchar(main_error)) {
  cat(sprintf("\nAna akis hatasi: %s\n", main_error))
}

# quit() kullanilmaz: source(...) ile guvenli. stop() Rscript altinda sifir-disi
# cikis kodu uretir. Artifact'lar zaten yazildi.
if (!isTRUE(evidence$pass)) {
  stop(sprintf("Operasyonel soak kapisi FAIL. Ayrintilar: %s",
               file.path(artifact_dir, "soak_evidence.json")), call. = FALSE)
}

cat("OK: Operasyonel soak kapisi PASS.\n")
invisible(TRUE)
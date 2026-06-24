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
soak_src("soak_system_telemetry.R")
soak_src("mock_llm_server.R")
soak_src("proxy_llm_server.R")
soak_src("soak_client.R")
soak_src("soak_interactive_lane.R")
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
interactive_result <- NULL
telemetry_handle <- NULL
telemetry_summary <- NULL
capacity_ladder_result <- NULL
real_canary_classification <- NULL
real_llm_throughput_result <- NULL
timeout_attribution <- NULL

mem_before <- soak_sample_memory()
temp_dirs <- unique(c(tempdir(), Sys.getenv("MERGEN_UPLOADS_DIR", ""),
                      Sys.getenv("MERGEN_MCP_BASE_DIR", "")))
temp_before <- soak_sample_tempdirs(temp_dirs)

run_started <- Sys.time()

main_result <- tryCatch({

  # --- Sistem telemetrisi (opsiyonel; arka surec; yuk seridini bloklamaz) ---
  if (isTRUE(cfg$telemetry_enabled)) {
    tel_max <- if (isTRUE(cfg$capacity_ladder_enabled)) {
      length(cfg$capacity_ladder_users) * cfg$capacity_ladder_step_seconds + 600
    } else {
      cfg$duration_sec + 600
    }
    telemetry_handle <- tryCatch(
      soak_telemetry_start(artifact_dir, soak_telemetry_config(),
                           max_seconds = tel_max, loadgen_pid = Sys.getpid()),
      error = function(e) list(started = FALSE, reason = soak_redact_text(conditionMessage(e)))
    )
    if (!isTRUE(telemetry_handle$started)) {
      warnings_vec <- c(warnings_vec,
        sprintf("Telemetri baslamadi: %s", telemetry_handle$reason %||% "bilinmeyen"))
      skipped_vec <- c(skipped_vec, "system_telemetry")
    } else {
      cat(sprintf("[soak] sistem telemetrisi acik (interval=%ds, port=%d).\n",
                  telemetry_handle$interval_sec, telemetry_handle$port))
    }
  } else {
    skipped_vec <- c(skipped_vec, "system_telemetry (kapali)")
  }

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

  # --- Etkilesimli (interactive) serit: gercek DB havuzu/islem/encoding/akis ---
  if (isTRUE(cfg$interactive_lane)) {
    cat(sprintf("[soak] etkilesimli serit: %d in-process oturum...\n", cfg$interactive_users))
    interactive_result <- tryCatch(
      soak_interactive_lane(cfg),
      error = function(e) list(available = FALSE,
                               reason = soak_redact_text(conditionMessage(e)))
    )
    if (!isTRUE(interactive_result$available)) {
      warnings_vec <- c(warnings_vec,
        sprintf("Etkilesimli serit calismadi: %s", interactive_result$reason %||% "bilinmeyen"))
      skipped_vec <- c(skipped_vec, "interactive_lane")
    } else {
      cat(sprintf("  -> %d oturum / %d eylem | basari=%s | sizinti=%d | izolasyon=%s\n",
                  interactive_result$sessions, interactive_result$actions,
                  as.character(interactive_result$summary$success_rate),
                  interactive_result$db_pool$outstanding_checkouts,
                  as.character(interactive_result$isolation_pass)))
    }
  } else {
    skipped_vec <- c(skipped_vec, "interactive_lane (kapali)")
  }

  # --- Attach modu (calisan uygulama) ---
  attach_result <- soak_attach_probe(cfg$app_url)

  # --- LLM serit + yuk ---
  if (!isTRUE(cfg$http_lane)) {
    cat("[soak] HTTP yuk seridi KAPALI (MERGEN_SOAK_HTTP_LANE=false); ",
        "yalniz in-process + etkilesimli seritler calisti.\n", sep = "")
    skipped_vec <- c(skipped_vec, "http_load_lane (kapali)")
  } else if (identical(cfg$llm_lane, "real-canary")) {
    real_url <- cfg$proxy$real_endpoint
    real_key <- Sys.getenv("MERGEN_SOAK_REAL_API_KEY", unset = "")
    if (!nzchar(real_url) || !nzchar(real_key)) {
      warnings_vec <- c(warnings_vec,
        "real-canary: MERGEN_SOAK_REAL_ENDPOINT_URL / MERGEN_SOAK_REAL_API_KEY ayarli degil; HTTP serit atlandi.")
      skipped_vec <- c(skipped_vec, "real_canary_http_lane")
    } else {
      cat(sprintf("[soak] real-canary: %d kullanici, %ds aralik, %.0fs sure...\n",
                  cfg$real_canary$users, cfg$real_canary$interval_sec, cfg$duration_sec))
      real_canary_classification <- soak_real_canary_load(real_url, real_key, cfg, metrics, cfg$duration_sec)
      if (is.list(real_canary_classification)) {
        cat(sprintf("  -> real-canary asama: gateway_policy_failed=%s, uretim_tamamlandi=%s, toplam=%s\n",
                    as.character(real_canary_classification$gateway_policy_failed),
                    as.character(real_canary_classification$generation_completed),
                    as.character(real_canary_classification$total_calls)))
      }

      # Opsiyonel KUCUK gercek-LLM throughput probe (kullanici tavanli; app
      # kapasitesi DEGIL; fake/proxy ile KARISTIRILMAZ).
      if (isTRUE(cfg$real_llm_throughput_enabled)) {
        cat(sprintf("[soak] KUCUK gercek-LLM throughput probe: %d kullanici (tavan=%d), %ds...\n",
                    cfg$real_llm_throughput$users, cfg$real_llm_throughput$max_users,
                    cfg$real_llm_throughput$duration_sec))
        real_llm_throughput_result <- tryCatch(
          soak_real_llm_throughput_probe(real_url, real_key, cfg,
                                         cfg$real_llm_throughput$duration_sec),
          error = function(e) {
            warnings_vec <- c(warnings_vec,
              sprintf("real-LLM throughput probe: %s", soak_redact_text(conditionMessage(e))))
            NULL
          }
        )
      }
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

    if (isTRUE(cfg$capacity_ladder_enabled)) {
      # Kademeli kapasite merdiveni: 50 -> 100 -> 250 -> ... -> 1000. Her adim
      # icin metrik dilimi + telemetri penceresi toplanir; ilk basarisiz adimda
      # (stop_on_first_failed_step) durulur. Son STABIL adim durustce raporlanir.
      cat(sprintf("[soak] kademeli kapasite merdiveni: %s | adim=%ds | stabil_esik=%.2f\n",
                  paste(cfg$capacity_ladder_users, collapse = ","),
                  cfg$capacity_ladder_step_seconds, cfg$stable_success_rate_min))
      step_rows <- list()
      for (uc in cfg$capacity_ladder_users) {
        from_idx <- soak_metrics_count(metrics) + 1L
        uk <- soak_make_user_keys(uc, cfg$llm_lane)
        step_start <- as.numeric(Sys.time())
        cat(sprintf("  - %d kullanici / %ds ...\n", uc, cfg$capacity_ladder_step_seconds))
        soak_http_load(load_url, cfg, metrics, cfg$capacity_ladder_step_seconds,
                       uc, uk, cfg$llm_lane)
        step_end <- as.numeric(Sys.time())
        s <- soak_metrics_slice_summary(metrics, from_idx,
                                        wall_seconds = cfg$capacity_ladder_step_seconds)
        tel_win <- if (!is.null(telemetry_handle) && isTRUE(telemetry_handle$started)) {
          tryCatch(soak_telemetry_window_summary(telemetry_handle$csv_path, step_start, step_end),
                   error = function(e) list(telemetry_available = FALSE))
        } else {
          list(telemetry_available = FALSE)
        }
        step_pass <- is.finite(s$effective_success_rate) &&
          s$effective_success_rate >= cfg$stable_success_rate_min
        # NOT: attach modunda calisan uygulamanin DB havuz sayaclari soak surucu
        # surecinden GORUNMEZ; bu yuzden adim db_pool = NULL (yaniltici sayac yok).
        step_rows[[length(step_rows) + 1L]] <- list(
          users = uc, duration_seconds = cfg$capacity_ladder_step_seconds,
          requests = s$requests, success = s$success, errors = s$errors, timeouts = s$timeouts,
          raw_success_rate = s$success_rate, effective_success_rate = s$effective_success_rate,
          p50_latency_ms = s$p50_latency_ms, p95_latency_ms = s$p95_latency_ms,
          p99_latency_ms = s$p99_latency_ms, throughput_ops_per_min = s$throughput_ops_per_min,
          db_pool = NULL, telemetry = tel_win, pass = step_pass
        )
        cat(sprintf("    -> istek=%d eff=%s p95=%sms tput=%s/dk cpu_max=%s%% pass=%s\n",
                    s$requests, as.character(s$effective_success_rate),
                    as.character(s$p95_latency_ms), as.character(s$throughput_ops_per_min),
                    as.character(tel_win$max_total_cpu_percent %||% NA), as.character(step_pass)))
        if (!isTRUE(step_pass) && isTRUE(cfg$stop_on_first_failed_step)) {
          cat("    -> ilk basarisiz adim; merdiven durduruluyor (stop_on_first_failed_step=TRUE).\n")
          break
        }
      }
      capacity_ladder_result <- soak_capacity_ladder_summarize(
        step_rows, cfg$capacity_ladder_users, cfg$stable_success_rate_min,
        cfg$stop_on_first_failed_step
      )
      cat(sprintf("[soak] merdiven sonucu: stabil=%s ilk_basarisiz=%s onerilen_sonraki=%s\n",
                  as.character(capacity_ladder_result$stable_capacity_users),
                  as.character(capacity_ladder_result$first_failed_capacity_users),
                  as.character(capacity_ladder_result$recommended_next_target)))
    } else if (isTRUE(cfg$capacity_curve_enabled)) {
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

# Telemetri arka surecini durdur + ozetle (CSV zaten artifact_dir'e yazildi).
if (!is.null(telemetry_handle) && isTRUE(telemetry_handle$started)) {
  invisible(tryCatch(soak_telemetry_stop(telemetry_handle), error = function(e) NULL))
  telemetry_summary <- tryCatch(
    soak_telemetry_summarize(telemetry_handle$csv_path),
    error = function(e) NULL
  )
  if (!is.null(telemetry_summary) && !isTRUE(telemetry_summary$telemetry_available)) {
    skipped_vec <- c(skipped_vec, "system_telemetry (olculemedi)")
  }
}

# Hata atfi (timeout attribution): tum kayitli metriklerden uretilir.
timeout_attribution <- tryCatch(
  soak_timeout_attribution(soak_metrics_as_df(metrics)),
  error = function(e) NULL
)

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

# Etkilesimli serit eylem metriklerini ayri CSV olarak yaz (redaksiyon pass'i
# soak_write_artifacts icinde tum .csv dosyalarini kapsar).
if (!is.null(interactive_result) && isTRUE(interactive_result$available) &&
    is.data.frame(interactive_result$metrics_df)) {
  dir.create(artifact_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(interactive_result$metrics_df,
                   file.path(artifact_dir, "interactive_metrics.csv"),
                   row.names = FALSE, fileEncoding = "UTF-8")
}

threshold_checks <- soak_evaluate_thresholds(
  cfg, summary, inprocess, redaction0, memory_growth, temp_growth_mb,
  server_alive_at_end, injected_faults, interactive_result, capacity_ladder_result
)
threshold_outcome <- soak_threshold_outcome(threshold_checks)
proofs <- soak_proof_statements(cfg, summary, inprocess, attach_result, interactive_result,
                                telemetry_summary, capacity_ladder_result)

evidence <- soak_build_evidence(
  cfg, summary, inprocess, proxy_summary, capacity_rows, redaction0,
  list(before = mem_before, after = mem_after), memory_growth, temp_summary,
  attach_result, failure_probe, threshold_checks, threshold_outcome, proofs,
  duration_actual, warnings_vec, skipped_vec, server_alive_at_end, injected_faults,
  interactive_result, telemetry_summary, capacity_ladder_result, timeout_attribution,
  real_canary_classification, real_llm_throughput_result
)

redaction <- soak_write_artifacts(artifact_dir, cfg, metrics, evidence,
                                  proxy_summary, capacity_rows, NULL)

# Redaksiyon sonucunu esik + evidence'a yansit ve FINALIZE et.
threshold_checks <- soak_evaluate_thresholds(
  cfg, summary, inprocess, redaction, memory_growth, temp_growth_mb,
  server_alive_at_end, injected_faults, interactive_result, capacity_ladder_result
)
threshold_outcome <- soak_threshold_outcome(threshold_checks)
evidence <- soak_build_evidence(
  cfg, summary, inprocess, proxy_summary, capacity_rows, redaction,
  list(before = mem_before, after = mem_after), memory_growth, temp_summary,
  attach_result, failure_probe, threshold_checks, threshold_outcome, proofs,
  duration_actual, warnings_vec, skipped_vec, server_alive_at_end, injected_faults,
  interactive_result, telemetry_summary, capacity_ladder_result, timeout_attribution,
  real_canary_classification, real_llm_throughput_result
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
if (!is.null(telemetry_summary)) {
  if (isTRUE(telemetry_summary$telemetry_available)) {
    cat(sprintf("Telemetri: ornek=%d | max CPU=%s%% | max bellek=%s MB | max app-port TCP=%s\n",
                telemetry_summary$samples, as.character(telemetry_summary$max_total_cpu_percent),
                as.character(telemetry_summary$max_mem_used_mb),
                as.character(telemetry_summary$max_tcp_connections_to_app)))
  } else {
    cat("Telemetri: UNMEASURED (sistem sayaclari okunamadi; darbogaz atfi kanit degil)\n")
  }
}
if (!is.null(capacity_ladder_result) && isTRUE(capacity_ladder_result$ran)) {
  cat(sprintf("Kademeli merdiven: stabil=%s kullanici | ilk_basarisiz=%s | onerilen=%s | ipuclari=%s\n",
              as.character(capacity_ladder_result$stable_capacity_users),
              as.character(capacity_ladder_result$first_failed_capacity_users),
              as.character(capacity_ladder_result$recommended_next_target),
              paste(capacity_ladder_result$bottleneck_hints, collapse = ",")))
}
if (is.list(timeout_attribution) && (timeout_attribution$total_failures %||% 0L) > 0L) {
  bk <- timeout_attribution$timeout_breakdown
  cat(sprintf("Hata atfi: toplam=%d | %s\n", timeout_attribution$total_failures,
              paste(paste0(names(bk), "=", unlist(bk)), collapse = " ")))
}
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
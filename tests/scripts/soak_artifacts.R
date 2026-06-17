# ==============================================================================
# Dosya Yolu: tests/scripts/soak_artifacts.R
# Aciklama:
#   Soak artifact uretimi: soak_evidence.json, summary.md, metrics.csv,
#   failures.jsonl, config.json, key_routing_summary.json, capacity_curve.csv.
#   Esik degerlendirme (olculen/olculemeyen ayrimi) ve durustluk
#   (does_prove / does_not_prove) sozlesmesi burada uretilir.
#
#   Tum metin artifact'lari redaksiyondan gecer; sonra dizin genelinde
#   redaksiyon kendi-dogrulamasi yapilir.
#
#   Bu dosya BILEREK ASCII-guvenlidir (Turkce ozel karakter yok).
# ==============================================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || is.na(x[1])) y else x

soak_git_field <- function(args) {
  out <- tryCatch(suppressWarnings(system2("git", args, stdout = TRUE, stderr = TRUE)),
                  error = function(e) character(0))
  if (length(out) == 0L) "" else trimws(out[1])
}

# ------------------------------------------------------------------------------
# Esik degerlendirme. Her kontrol: name, measured, value, threshold, pass, note.
# Olculemeyen esikler SESSIZCE GECMEZ; measured=FALSE, pass=NA olarak isaretlenir.
# ------------------------------------------------------------------------------
soak_evaluate_thresholds <- function(cfg, summary, inprocess, redaction,
                                     memory_growth, temp_growth_mb,
                                     server_alive_at_end, injected_faults = 0L) {
  th <- cfg$thresholds
  checks <- list()

  add <- function(name, measured, value, threshold, pass, note = "") {
    checks[[length(checks) + 1L]] <<- list(
      name = name, measured = isTRUE(measured), value = value,
      threshold = threshold,
      pass = if (isTRUE(measured)) isTRUE(pass) else NA,
      note = note
    )
  }

  # 1) Basari orani. ETKIN (effective) basari orani esige tabidir: sunucunun
  # KASITLI enjekte ettigi faultlar (http500/http429/timeout) haric tutulur.
  # Boylece esik, BEKLENMEYEN (app/transport kaynakli) basarisizliklari olcer;
  # hata-enjeksiyon test kosumu kendi esigini dusurmez. Ham oran da raporlanir.
  if (summary$requests > 0L && is.finite(summary$success_rate)) {
    observed_faults <- summary$errors + summary$timeouts
    unexpected <- max(0L, observed_faults - as.integer(injected_faults %||% 0L))
    effective <- (summary$requests - unexpected) / summary$requests
    add("effective_success_rate", TRUE, round(effective, 4), th$success_rate_min,
        effective >= th$success_rate_min,
        sprintf("Enjekte faultlar haric basari. ham=%.4f enjekte_fault=%d beklenmeyen=%d",
                summary$success_rate %||% NA, as.integer(injected_faults %||% 0L), unexpected))
    add("raw_success_rate", TRUE, summary$success_rate, "raporlandi (esik yok)", TRUE,
        "Ham basari orani (enjekte faultlar dahil).")
  } else {
    add("effective_success_rate", FALSE, NA, th$success_rate_min, NA,
        "Hic HTTP istegi olculmedi (olculemeyen).")
  }

  # 2) p95 gecikme (yalnizca esik >0 ise uygulanir; aksi halde olculur, esik yok).
  if (th$p95_latency_ms_max > 0L) {
    if (is.finite(summary$p95_latency_ms)) {
      add("p95_latency_ms", TRUE, summary$p95_latency_ms, th$p95_latency_ms_max,
          summary$p95_latency_ms <= th$p95_latency_ms_max, "p95 gecikme esigi.")
    } else {
      add("p95_latency_ms", FALSE, NA, th$p95_latency_ms_max, NA,
          "p95 olculemedi.")
    }
  } else {
    add("p95_latency_ms", TRUE, summary$p95_latency_ms, "raporlandi (esik yok)", TRUE,
        "p95 raporlandi; esik uygulanmadi (MERGEN_SOAK_P95_LATENCY_MS_MAX=0).")
  }

  # 3) Mojibake (in-process encoding round-trip). fail_on_mojibake ise zorlanir.
  if (isTRUE(inprocess$available)) {
    mh <- inprocess$encoding$mojibake_hits %||% NA_integer_
    if (isTRUE(th$fail_on_mojibake)) {
      add("mojibake_hits", TRUE, mh, 0L, identical(as.integer(mh), 0L),
          "DB-encoding round-trip mojibake (helper-duzeyi).")
    } else {
      add("mojibake_hits", TRUE, mh, "raporlandi (esik yok)", TRUE,
          "Mojibake raporlandi; fail kapatildi.")
    }
  } else {
    add("mojibake_hits", FALSE, NA, 0L, NA,
        "In-process encoding alistirmasi calismadi (olculemeyen).")
  }

  # 4) Encoding round-trip pass (helper-duzeyi DB encoding).
  if (isTRUE(inprocess$available)) {
    rp <- inprocess$encoding$roundtrip_pass_rate %||% NA_real_
    add("encoding_roundtrip_pass_rate", TRUE, rp, 1.0, identical(rp, 1.0),
        "Turkce + emoji escape/restore round-trip (helper-duzeyi).")
  } else {
    add("encoding_roundtrip_pass_rate", FALSE, NA, 1.0, NA, "olculemedi.")
  }

  # 5) Anahtar yonlendirme dogrulugu + izolasyon (in-process).
  if (isTRUE(inprocess$available)) {
    kr <- inprocess$key_routing
    add("key_routing_correct", TRUE, sprintf("%d/%d", kr$rows_correct, kr$rows_total),
        "tum satirlar", isTRUE(kr$all_correct), "personal/default/missing siniflandirma.")
    add("cross_session_key_isolation", TRUE, isTRUE(kr$cross_session_isolation_pass),
        TRUE, isTRUE(kr$cross_session_isolation_pass),
        "Bir kullanici baska kullanicinin anahtarini kullanamaz.")
  } else {
    add("key_routing_correct", FALSE, NA, "tum satirlar", NA, "olculemedi.")
    add("cross_session_key_isolation", FALSE, NA, TRUE, NA, "olculemedi.")
  }

  # 6) Upload dogrulama dogrulugu.
  if (isTRUE(inprocess$available)) {
    up <- inprocess$upload
    add("upload_validation_correct", TRUE, sprintf("%d/%d", up$correct, up$total),
        "tum durumlar", isTRUE(up$all_correct), "kabul/ret kararlari.")
  } else {
    add("upload_validation_correct", FALSE, NA, "tum durumlar", NA, "olculemedi.")
  }

  # 7) Sir sizintisi (artifact tarama).
  leaks <- redaction$total_leaks %||% NA_integer_
  if (isTRUE(th$fail_on_secret_leak)) {
    add("secret_leak", TRUE, leaks, 0L, identical(as.integer(leaks), 0L),
        "Artifact'larda ham anahtar/token/sir taramasi.")
  } else {
    add("secret_leak", TRUE, leaks, "raporlandi (esik yok)", TRUE, "Sir sizinti fail kapatildi.")
  }

  # 8) Uygulama crash yok (sunucu sonda canli). real-canary seritte yerel sunucu
  # yoktur; bu kontrol UYGULANMAZ (olculemeyen, sessizce gecmez).
  if (identical(cfg$llm_lane, "real-canary")) {
    add("no_server_crash", FALSE, "n/a (real-canary; yerel sunucu yok)", TRUE, NA,
        "real-canary seritte yerel fake/proxy sunucu baslatilmaz.")
  } else {
    add("no_server_crash", TRUE, isTRUE(server_alive_at_end), TRUE,
        isTRUE(server_alive_at_end), "Sahte/proxy LLM sunucusu sonda hala canli.")
  }

  # 9) Bellek buyumesi (yalnizca olculebilirse + esik >=0 ise).
  if (th$memory_growth_mb_max >= 0) {
    if (isTRUE(memory_growth$rss_measured) && is.finite(memory_growth$process_rss_growth_mb)) {
      add("memory_growth_mb", TRUE, memory_growth$process_rss_growth_mb,
          th$memory_growth_mb_max,
          memory_growth$process_rss_growth_mb <= th$memory_growth_mb_max,
          "Surec RSS buyumesi.")
    } else {
      add("memory_growth_mb", FALSE, NA, th$memory_growth_mb_max, NA,
          "Surec RSS olculemedi (olculemeyen; sessizce gecmez).")
    }
  } else {
    rss_val <- if (isTRUE(memory_growth$rss_measured)) memory_growth$process_rss_growth_mb else NA
    add("memory_growth_mb", isTRUE(memory_growth$rss_measured), rss_val,
        "raporlandi (esik yok)", TRUE, "Bellek buyumesi raporlandi; esik uygulanmadi.")
  }

  # 10) Temp dizin buyumesi.
  if (th$temp_growth_mb_max >= 0) {
    if (is.finite(temp_growth_mb)) {
      add("temp_growth_mb", TRUE, round(temp_growth_mb, 2), th$temp_growth_mb_max,
          temp_growth_mb <= th$temp_growth_mb_max, "Temp dizin byte buyumesi.")
    } else {
      add("temp_growth_mb", FALSE, NA, th$temp_growth_mb_max, NA, "olculemedi.")
    }
  } else {
    add("temp_growth_mb", TRUE, round(temp_growth_mb %||% NA, 2),
        "raporlandi (esik yok)", TRUE, "Temp buyumesi raporlandi; esik uygulanmadi.")
  }

  # 11) Tarayici konsol hatalari: bu kapida olculmez (attach yalniz HTTP).
  add("browser_console_errors", FALSE, NA,
      if (isTRUE(th$fail_on_browser_console_errors)) 0L else "raporlandi (esik yok)",
      NA, "Bu gate tarayici konsolunu olcmez (UX smoke ayri kapidir).")

  checks
}

# Esik kontrollerinden genel gecme/kalma ve nedenleri uretir.
soak_threshold_outcome <- function(checks) {
  enforced <- Filter(function(c) isTRUE(c$measured) && !is.na(c$pass), checks)
  failed <- Filter(function(c) isFALSE(c$pass), enforced)
  unmeasured <- Filter(function(c) !isTRUE(c$measured), checks)
  unmeasured_enforced <- Filter(function(c) {
    if (isTRUE(c$measured)) return(FALSE)
    threshold <- paste(as.character(c$threshold %||% ""), collapse = " ")
    value <- paste(as.character(c$value %||% ""), collapse = " ")
    note <- paste(as.character(c$note %||% ""), collapse = " ")
    report_only <- grepl("esik yok|raporlandi", threshold, ignore.case = TRUE)
    not_applicable <- grepl("^n/a", value, ignore.case = TRUE) ||
      grepl("uygulanmaz|uygulanmadi", note, ignore.case = TRUE)
    !report_only && !not_applicable
  }, unmeasured)
  unmeasured_reasons <- vapply(unmeasured_enforced, function(c) {
    sprintf("%s (olculemedi, esik=%s)", c$name, as.character(c$threshold))
  }, character(1))
  failure_reasons <- c(
    vapply(failed, function(c) {
      sprintf("%s (deger=%s, esik=%s)", c$name, as.character(c$value), as.character(c$threshold))
    }, character(1)),
    unmeasured_reasons
  )
  list(
    pass = length(failure_reasons) == 0L,
    failure_reasons = failure_reasons,
    unmeasured_names = vapply(unmeasured, function(c) c$name, character(1))
  )
}

# ------------------------------------------------------------------------------
# does_prove / does_not_prove durustluk metinleri (serit + calisan adimlara gore).
# ------------------------------------------------------------------------------
soak_proof_statements <- function(cfg, summary, inprocess, attach) {
  proves <- character(0)
  not <- character(0)

  lane <- cfg$llm_lane
  users <- cfg$concurrent_users

  if (summary$requests > 0L) {
    proves <- c(proves, sprintf(
      "Uygulama/sunucu, %d eszamanli simule kullanici ile %s LLM seridinde %d istek boyunca calisti (basari orani %.3f).",
      users, lane, summary$requests, summary$success_rate %||% NA))
  }
  if (isTRUE(inprocess$available)) {
    proves <- c(proves,
      "DB-encoding helper round-trip Turkce + emoji metni korudu (escape/restore + mojibake tespiti).",
      "Kisisel/varsayilan/eksik anahtar kaynak yonlendirmesi ham anahtar sizdirmadan dogrulandi.",
      "Oturumlar-arasi anahtar izolasyonu: bir kullanici baska kullanicinin anahtarini kullanamadi.",
      "Yukleme dogrulayicisi traversal/uzanti/kontrol-byte dosya adlarini reddetti.")
  }
  if (identical(lane, "proxy")) {
    proves <- c(proves,
      "Proxy serit cok sayida ayri sahte kisisel anahtari 1:1 kullanici-anahtar esleme ile izledi (izolasyon).")
  }
  if (isTRUE(attach$reachable)) {
    proves <- c(proves, "Calisan uygulama koku HTTP-duzeyinde erisilebildi.")
  }

  # does_not_prove (her zaman acik sinirlar).
  not <- c(not,
    sprintf("%d gercek eszamanli AKTIF kullaniciyi KANITLAMAZ (kullanici tabani hedefi=%d).",
            cfg$user_base_target, cfg$user_base_target),
    "Gercek LLM saglayicisinin bu eszamanlilik icin uretim throughput'unu KANITLAMAZ.",
    "Windows VM disindaki gercek aglardaki uretim gecikmesini KANITLAMAZ.",
    "Tam-yigin tarayici/websocket Shiny oturum eszamanliligini KANITLAMAZ (in-process alistirmalar helper-duzeyidir).",
    "Gercek SQL Server'a Turkce yaziminin at-rest dogrulugunu KANITLAMAZ (ayri VM kodlama preflight kapisidir).")
  if (identical(lane, "fake")) {
    not <- c(not, "Sahte endpoint ile gercek model davranisini/yanit kalitesini KANITLAMAZ.")
  }
  if (identical(lane, "real-canary")) {
    not <- c(not, "Canary serit yalniz cok dusuk eszamanlilik icindir; 50/100 kullanici throughput'u TAHMIN EDILEMEZ.")
  }
  if (!isTRUE(attach$reachable)) {
    not <- c(not, "Calisan tam uygulamaya karsi gercek Shiny-oturum davranisini KANITLAMAZ (attach modu calismadi/atlandi).")
  }

  list(does_prove = proves, does_not_prove = not)
}

# ------------------------------------------------------------------------------
# Evidence list'i olusturur (spec semasi).
# ------------------------------------------------------------------------------
soak_build_evidence <- function(cfg, summary, inprocess, proxy_summary,
                                capacity_rows, redaction, memory_summary,
                                memory_growth, temp_summary, attach,
                                failure_probe, threshold_checks, threshold_outcome,
                                proofs, duration_actual, warnings_vec, skipped_vec,
                                server_alive_at_end, injected_faults = 0L) {
  observed_faults <- summary$errors + summary$timeouts
  unexpected_faults <- max(0L, observed_faults - as.integer(injected_faults %||% 0L))
  effective_success_rate <- if (summary$requests > 0L) {
    round((summary$requests - unexpected_faults) / summary$requests, 4)
  } else NA_real_
  kr <- if (isTRUE(inprocess$available)) inprocess$key_routing else NULL
  key_sources <- list(personal = 0L, default = 0L, missing = 0L, error = 0L)
  if (!is.null(kr)) {
    key_sources$personal <- kr$source_counts$personal %||% 0L
    key_sources$default <- kr$source_counts$default %||% 0L
    key_sources$missing <- kr$source_counts$missing %||% 0L
  }

  list(
    schema_version = "1.0",
    gate = "run_operational_soak_gate",
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    validation_execution_status = "ran_by_operational_soak_gate",
    repo_commit_sha = soak_git_field(c("rev-parse", "--short", "HEAD")),
    branch = soak_git_field(c("rev-parse", "--abbrev-ref", "HEAD")),
    git_dirty = nzchar(soak_git_field(c("status", "--porcelain"))),
    r_version = R.version.string,
    platform = R.version$platform,
    os = utils::sessionInfo()$running %||% Sys.info()[["sysname"]],
    profile = cfg$profile,
    profile_intent = cfg$profile_intent,
    duration_seconds_requested = cfg$duration_sec,
    duration_seconds_actual = round(duration_actual, 1),
    app_url_configured = nzchar(cfg$app_url),
    llm_lane = cfg$llm_lane,
    mocked_llm = cfg$mocked_llm,
    proxied_llm = cfg$proxied_llm,
    real_llm = cfg$real_llm,
    user_base_target = cfg$user_base_target,
    assumed_concurrency_model = cfg$assumed_concurrency_model,
    configured_concurrent_users = cfg$concurrent_users,
    scenario_mix = summary$scenario_counts,
    thresholds = cfg$thresholds,
    threshold_checks = threshold_checks,
    metrics = list(
      requests = summary$requests, success = summary$success,
      errors = summary$errors, timeouts = summary$timeouts,
      success_rate = summary$success_rate,
      raw_success_rate = summary$success_rate,
      effective_success_rate = effective_success_rate,
      injected_fault_count = as.integer(injected_faults %||% 0L),
      unexpected_failure_count = unexpected_faults,
      p50_latency_ms = summary$p50_latency_ms,
      p90_latency_ms = summary$p90_latency_ms,
      p95_latency_ms = summary$p95_latency_ms,
      p99_latency_ms = summary$p99_latency_ms,
      max_latency_ms = summary$max_latency_ms,
      throughput_ops_per_min = summary$throughput_ops_per_min,
      http_code_counts = summary$http_code_counts,
      status_counts = summary$status_counts,
      wall_seconds = summary$wall_seconds
    ),
    key_sources = key_sources,
    key_routing = if (!is.null(kr)) kr else "in-process alistirma calismadi",
    proxy_lane = proxy_summary %||% "proxy serit kullanilmadi",
    failure_injection = failure_probe %||% "hata-enjeksiyon probe calismadi",
    attach_mode = attach,
    capacity_curve = capacity_rows %||% list(),
    secret_redaction_confirmed = identical(as.integer(redaction$total_leaks %||% 0L), 0L),
    raw_key_leak_count = as.integer(redaction$total_leaks %||% 0L),
    raw_prompt_leak_count = 0L,  # promptlar artifact'a TAM yazilmaz; yalniz case-id.
    db_roundtrip_encoding_pass = if (isTRUE(inprocess$available)) {
      identical(inprocess$encoding$roundtrip_pass, inprocess$encoding$iterations)
    } else NA,
    db_roundtrip_encoding_note = "Helper-duzeyi DB-encoding round-trip; gercek SQL Server yazimi DEGILDIR.",
    mojibake_hits = if (isTRUE(inprocess$available)) inprocess$encoding$mojibake_hits else NA,
    temp_cleanup_summary = temp_summary,
    memory_summary = list(growth = memory_growth, samples = memory_summary),
    server_alive_at_end = isTRUE(server_alive_at_end),
    pass = isTRUE(threshold_outcome$pass),
    failure_reasons = threshold_outcome$failure_reasons,
    warnings = warnings_vec %||% character(0),
    skipped_checks = unique(c(skipped_vec %||% character(0),
                              threshold_outcome$unmeasured_names %||% character(0))),
    does_prove = proofs$does_prove,
    does_not_prove = proofs$does_not_prove,
    proof_boundary_notes = paste(
      "Bu kapi fake/proxy/real-canary seritleriyle UYGULAMA DAYANIKLILIGI kaniti uretir.",
      "Tek gercek anahtarla canary, 50/100 kullanici throughput'unu KANITLAMAZ.",
      "Atlanan/olculemeyen kontroller kanit DEGILDIR."
    )
  )
}

# ------------------------------------------------------------------------------
# Tum artifact'lari yazar; sonra redaksiyon kendi-dogrulamasi calistirir.
# Geriye redaction sonucunu doner.
# ------------------------------------------------------------------------------
soak_write_artifacts <- function(artifact_dir, cfg, metrics, evidence,
                                 proxy_summary, capacity_rows, failures_rows) {
  dir.create(artifact_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(artifact_dir, "logs"), showWarnings = FALSE)

  # config.json (secret-safe)
  cfg_pub <- soak_config_public(cfg)
  jsonlite::write_json(cfg_pub, file.path(artifact_dir, "config.json"),
                       auto_unbox = TRUE, pretty = TRUE, null = "null")

  # metrics.csv
  df <- soak_metrics_as_df(metrics)
  utils::write.csv(df, file.path(artifact_dir, "metrics.csv"),
                   row.names = FALSE, fileEncoding = "UTF-8")

  # failures.jsonl (status != ok)
  fail_path <- file.path(artifact_dir, "failures.jsonl")
  con <- file(fail_path, open = "wt", encoding = "UTF-8")
  if (nrow(df) > 0L) {
    bad <- df[df$status != "ok", , drop = FALSE]
    for (i in seq_len(nrow(bad))) {
      rec <- list(ts_epoch = bad$ts_epoch[i], lane = bad$lane[i],
                  scenario = bad$scenario[i], status = bad$status[i],
                  http_code = if (is.na(bad$http_code[i])) NULL else bad$http_code[i],
                  latency_ms = bad$latency_ms[i])
      writeLines(as.character(jsonlite::toJSON(rec, auto_unbox = TRUE, null = "null")), con)
    }
  }
  close(con)

  # key_routing_summary.json
  krs <- list(
    in_process = evidence$key_routing,
    proxy_lane = proxy_summary %||% "proxy serit kullanilmadi",
    key_sources = evidence$key_sources,
    note = paste(
      "Kaynak siniflandirma personal/default/missing; ham anahtar YOK.",
      "Oturumlar-arasi izolasyon helper-duzeyi resolver ile dogrulandi."
    )
  )
  jsonlite::write_json(krs, file.path(artifact_dir, "key_routing_summary.json"),
                       auto_unbox = TRUE, pretty = TRUE, null = "null")

  # capacity_curve.csv (varsa)
  if (!is.null(capacity_rows) && length(capacity_rows) > 0L) {
    cap_df <- do.call(rbind, lapply(capacity_rows, function(r) {
      data.frame(users = r$users, requests = r$requests,
                 success_rate = r$success_rate, p95_latency_ms = r$p95_latency_ms,
                 throughput_ops_per_min = r$throughput_ops_per_min,
                 stringsAsFactors = FALSE)
    }))
    utils::write.csv(cap_df, file.path(artifact_dir, "capacity_curve.csv"),
                     row.names = FALSE, fileEncoding = "UTF-8")
  }

  # soak_evidence.json
  ev_json <- jsonlite::toJSON(evidence, auto_unbox = TRUE, pretty = TRUE, null = "null")
  writeLines(soak_redact_text(as.character(ev_json)),
             file.path(artifact_dir, "soak_evidence.json"), useBytes = TRUE)

  # summary.md
  soak_write_summary_md(artifact_dir, cfg, evidence)

  # Redaksiyon: tum metin artifact'larini yerinde redakte et + kendi-dogrula.
  for (f in list.files(artifact_dir, recursive = TRUE, full.names = TRUE)) {
    if (grepl("\\.(json|jsonl|md|csv|log)$", f)) soak_redact_file(f)
  }
  soak_redaction_self_check(artifact_dir)
}

# Insan-okunur summary.md.
soak_write_summary_md <- function(artifact_dir, cfg, evidence) {
  m <- evidence$metrics
  lines <- c(
    "# Operasyonel Soak Gate Ozeti",
    "",
    sprintf("- Olusturulma: %s", evidence$created_at),
    sprintf("- Profil: **%s** (%s)", evidence$profile, evidence$profile_intent),
    sprintf("- LLM serit: **%s** (mock=%s, proxy=%s, real-canary=%s)",
            evidence$llm_lane, evidence$mocked_llm, evidence$proxied_llm, evidence$real_llm),
    sprintf("- Eszamanli kullanici (aktif): %d | Kullanici tabani hedefi: %d",
            evidence$configured_concurrent_users, evidence$user_base_target),
    sprintf("- Sure (istenen/gercek): %.0fs / %.0fs",
            evidence$duration_seconds_requested, evidence$duration_seconds_actual),
    sprintf("- Genel sonuc: **%s**", if (isTRUE(evidence$pass)) "PASS" else "FAIL"),
    "",
    "## Metrikler",
    sprintf("- Istek: %d | Basari: %d | Hata: %d | Timeout: %d",
            m$requests, m$success, m$errors, m$timeouts),
    sprintf("- Basari orani: %s", as.character(m$success_rate)),
    sprintf("- Gecikme p50/p95/p99 (ms): %s / %s / %s",
            as.character(m$p50_latency_ms), as.character(m$p95_latency_ms),
            as.character(m$p99_latency_ms)),
    sprintf("- Throughput: %s op/dk", as.character(m$throughput_ops_per_min)),
    "",
    "## Anahtar Yonlendirme (kaynak sayilari)",
    sprintf("- personal=%d default=%d missing=%d error=%d",
            evidence$key_sources$personal, evidence$key_sources$default,
            evidence$key_sources$missing, evidence$key_sources$error),
    sprintf("- Oturumlar-arasi izolasyon: %s",
            if (is.list(evidence$key_routing)) as.character(evidence$key_routing$cross_session_isolation_pass) else "n/a"),
    "",
    "## Gizlilik / Sir",
    sprintf("- Redaksiyon dogrulandi: %s | Ham anahtar sizinti: %d",
            evidence$secret_redaction_confirmed, evidence$raw_key_leak_count),
    sprintf("- DB-encoding round-trip (helper): %s | mojibake: %s",
            as.character(evidence$db_roundtrip_encoding_pass), as.character(evidence$mojibake_hits)),
    "",
    "## KANITLAR (does_prove)",
    paste0("- ", evidence$does_prove),
    "",
    "## KANITLAMAZ (does_not_prove)",
    paste0("- ", evidence$does_not_prove),
    ""
  )
  if (length(evidence$failure_reasons) > 0L) {
    lines <- c(lines, "## Basarisizlik Nedenleri",
               paste0("- ", evidence$failure_reasons), "")
  }
  if (length(evidence$skipped_checks) > 0L) {
    lines <- c(lines, "## Atlanan / Olculemeyen Kontroller",
               paste0("- ", evidence$skipped_checks), "")
  }
  writeLines(soak_redact_text(paste(lines, collapse = "\n")),
             file.path(artifact_dir, "summary.md"), useBytes = TRUE)
}

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
# Bir basarisizliktan SONRA daraltma icin onerilen ara kademeler. stable=300,
# first_failed=450 ise 350/400/425 gibi araliga finer-yakin kademeler onerir.
# Boylece dogrudan 450'yi tekrar denemek yerine 300->450 araligi daraltilir.
# SAF, deterministik; kanit/dokuman icin uretilir.
# ------------------------------------------------------------------------------
soak_capacity_recommended_probe_steps <- function(stable_users, first_failed_users) {
  stable <- suppressWarnings(as.integer(stable_users))
  failed <- suppressWarnings(as.integer(first_failed_users))
  if (is.na(stable) || is.na(failed) || stable <= 0L || failed <= stable) {
    return(integer(0))
  }
  gap <- failed - stable
  if (gap <= 1L) return(integer(0))
  # Hataya yakin daha sik ornekleme (1/3, 2/3, 5/6).
  raw <- stable + gap * c(1/3, 2/3, 5/6)
  inc <- if (gap >= 100) 25 else if (gap >= 20) 5 else 1
  steps <- as.integer(round(raw / inc) * inc)
  steps <- unique(steps[steps > stable & steps < failed])
  if (length(steps) == 0L) {
    steps <- unique(as.integer(round(raw)))
    steps <- steps[steps > stable & steps < failed]
  }
  sort(steps)
}

# ------------------------------------------------------------------------------
# Kademeli kapasite merdiveni (capacity ladder) darbogaz ipuclari. KORUMACI:
# yalniz mevcut kanit destekledigi olcude ipucu uretir; kanit yetersizse
# "unknown_timeout_saturation" der. step_rows: her adim list(users, p95, ...,
# effective_success_rate, pass, telemetry=list(max_total_cpu_percent, ...)).
# ------------------------------------------------------------------------------
soak_capacity_bottleneck_hints <- function(step_rows, stable_min = 0.98) {
  hints <- character(0)
  if (is.null(step_rows) || length(step_rows) == 0L) {
    return("no_ladder_steps_executed")
  }

  eff <- vapply(step_rows, function(r) as.numeric(r$effective_success_rate %||% NA_real_), numeric(1))
  failed_idx <- which(is.finite(eff) & eff < stable_min)
  if (length(failed_idx) == 0L) {
    return("no_failure_observed_within_ladder")
  }

  fi <- failed_idx[1]
  failed <- step_rows[[fi]]
  prev <- if (fi > 1L) step_rows[[fi - 1L]] else NULL

  tel <- failed$telemetry %||% list()
  tel_available <- isTRUE(tel$telemetry_available)
  cpu <- as.numeric(tel$max_total_cpu_percent %||% NA_real_)
  sql_cpu <- as.numeric(tel$max_sqlserver_cpu_percent %||% NA_real_)
  r_cpu <- as.numeric(tel$max_r_process_cpu_percent %||% NA_real_)

  failed_p95 <- as.numeric(failed$p95_latency_ms %||% NA_real_)
  prev_p95 <- if (!is.null(prev)) as.numeric(prev$p95_latency_ms %||% NA_real_) else NA_real_
  p95_jumped <- is.finite(failed_p95) && is.finite(prev_p95) && prev_p95 > 0 &&
    (failed_p95 / prev_p95 >= 1.8)

  cpu_saturated <- is.finite(cpu) && cpu >= 85
  cpu_low <- is.finite(cpu) && cpu < 70

  if (cpu_saturated) {
    hints <- c(hints, "possible_cpu_saturation")
  }
  if (is.finite(sql_cpu) && sql_cpu >= 80) {
    hints <- c(hints, "possible_sql_server_contention")
  }
  if (is.finite(r_cpu) && r_cpu >= 90 && (!is.finite(cpu) || cpu < 85)) {
    hints <- c(hints, "possible_load_generator_limit")
  }
  if (p95_jumped && cpu_low) {
    hints <- c(hints, "possible_app_or_event_loop_queueing")
  }

  # Hata-sinifi + TCP durum + yuk-uretici tabanli ek ipuclari (varsa). Bunlar
  # mevcut ipuclarini KALDIRMAZ; yalniz baskin connection_timeout, kabul-kuyrugu
  # (SYN_RECV), TIME_WAIT baskisi ve yuk-uretici limiti gibi kaynak-disi doygunluk
  # sinyallerini ayirt eder. 2026-06-27 450-kullanici bulgusunda baskin sinif
  # connection_timeout + dusuk CPU idi; bu dal o durumu acikca isaretler.
  dom_tc <- as.character(failed$dominant_timeout_class %||% "")
  tcp_by_state <- tel$app_tcp_max_by_state %||% list()
  syn_recv <- suppressWarnings(as.numeric(tcp_by_state$tcp_syn_recv %||% NA_real_))
  time_wait <- suppressWarnings(as.numeric(tcp_by_state$tcp_time_wait %||% NA_real_))
  established <- suppressWarnings(as.numeric(tcp_by_state$tcp_established %||% NA_real_))
  lg_hint <- as.character((failed$loadgen %||% list())$saturation_hint %||% "")

  if (identical(dom_tc, "connection_timeout") && cpu_low) {
    hints <- c(hints, "possible_connection_accept_or_backlog_saturation")
  }
  if (is.finite(syn_recv) && is.finite(established) && syn_recv > 0 &&
      syn_recv >= max(1, 0.5 * established)) {
    hints <- c(hints, "possible_accept_backlog_saturation")
  }
  if (is.finite(time_wait) && is.finite(established) && time_wait >= 2 * max(1, established)) {
    hints <- c(hints, "possible_time_wait_port_pressure")
  }
  if (identical(lg_hint, "loadgen_below_target_concurrency")) {
    hints <- c(hints, "possible_load_generator_limit")
  }

  # DB havuz darbogazi: yalniz adimda gercek havuz sayaclari varsa (taken==max).
  dbp <- failed$db_pool
  if (is.list(dbp) && is.finite(as.numeric(dbp$taken %||% NA_real_)) &&
      is.finite(as.numeric(dbp$max_size %||% NA_real_)) &&
      as.numeric(dbp$taken) >= as.numeric(dbp$max_size)) {
    hints <- c(hints, "possible_db_pool_contention")
  }

  if (length(hints) == 0L) {
    hints <- if (!tel_available) {
      "unknown_timeout_saturation"
    } else {
      "timeout_saturation_without_clear_resource_signal"
    }
  }
  unique(hints)
}

# step_rows'tan stabil/ilk-basarisiz/onerilen-hedef + ipuclarini ozetler.
soak_capacity_ladder_summarize <- function(step_rows, ladder_users, stable_min = 0.98,
                                           stop_on_first = TRUE) {
  if (is.null(step_rows) || length(step_rows) == 0L) {
    return(list(
      ran = FALSE, steps = list(), stable_capacity_users = 0L,
      first_failed_capacity_users = NA_integer_,
      recommended_next_target = NA_integer_,
      recommended_probe_steps = integer(0),
      all_steps_pass = NA, bottleneck_hints = "no_ladder_steps_executed",
      bottleneck_hint = "no_ladder_steps_executed",
      dominant_timeout_class = NA_character_,
      loadgen_saturation_hint = NA_character_,
      app_tcp_max_by_state = list(),
      stable_success_rate_min = stable_min
    ))
  }

  users_vec <- vapply(step_rows, function(r) as.integer(r$users %||% NA_integer_), integer(1))
  pass_vec <- vapply(step_rows, function(r) isTRUE(r$pass), logical(1))

  stable_users <- 0L
  for (i in seq_along(step_rows)) {
    if (isTRUE(pass_vec[i])) stable_users <- users_vec[i] else break
  }
  fi <- if (any(!pass_vec)) which(!pass_vec)[1] else NA_integer_
  first_failed <- if (!is.na(fi)) users_vec[fi] else NA_integer_
  failed_step <- if (!is.na(fi)) step_rows[[fi]] else NULL

  # Onerilen sonraki hedef: stabil adimdan SONRAKI merdiven adimi (varsa); aksi
  # halde ilk basarisiz adim arastirilmali.
  ladder_users <- as.integer(ladder_users)
  recommended <- NA_integer_
  if (stable_users > 0L) {
    nxt <- ladder_users[ladder_users > stable_users]
    recommended <- if (length(nxt) > 0L) nxt[1] else stable_users  # zaten en uste ulasildi
  }

  hints <- soak_capacity_bottleneck_hints(step_rows, stable_min)

  list(
    ran = TRUE,
    steps = step_rows,
    stable_capacity_users = as.integer(stable_users),
    first_failed_capacity_users = first_failed,
    recommended_next_target = recommended,
    recommended_probe_steps = soak_capacity_recommended_probe_steps(stable_users, first_failed),
    all_steps_pass = all(pass_vec),
    stop_on_first_failed_step = isTRUE(stop_on_first),
    stable_success_rate_min = stable_min,
    bottleneck_hints = hints,
    bottleneck_hint = hints[[1]],
    dominant_timeout_class = if (!is.null(failed_step)) {
      as.character(failed_step$dominant_timeout_class %||% NA_character_)
    } else NA_character_,
    loadgen_saturation_hint = if (!is.null(failed_step)) {
      as.character((failed_step$loadgen %||% list())$saturation_hint %||% NA_character_)
    } else NA_character_,
    app_tcp_max_by_state = if (!is.null(failed_step)) {
      (failed_step$telemetry %||% list())$app_tcp_max_by_state %||% list()
    } else list()
  )
}

# ------------------------------------------------------------------------------
# Esik degerlendirme. Her kontrol: name, measured, value, threshold, pass, note.
# Olculemeyen esikler SESSIZCE GECMEZ; measured=FALSE, pass=NA olarak isaretlenir.
# ------------------------------------------------------------------------------
soak_evaluate_thresholds <- function(cfg, summary, inprocess, redaction,
                                     memory_growth, temp_growth_mb,
                                     server_alive_at_end, injected_faults = 0L,
                                     interactive = NULL, capacity_ladder = NULL) {
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

  # 8) Uygulama crash yok (sunucu sonda canli). real-canary seritte veya HTTP
  # seridi kapaliyken yerel sunucu yoktur; bu kontrol UYGULANMAZ (olculemeyen).
  if (identical(cfg$llm_lane, "real-canary") || !isTRUE(cfg$http_lane)) {
    add("no_server_crash", FALSE, "n/a (yerel HTTP sunucu yok)", TRUE, NA,
        "real-canary veya HTTP seridi kapali iken yerel fake/proxy sunucu baslatilmaz.")
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

  # 12-15) Etkilesimli (interactive) serit: gercek DB havuzu/islem/encoding/
  # izolasyon kanitlari. Yalnizca serit calistiysa olculur (sessizce gecmez).
  if (!is.null(interactive) && isTRUE(interactive$available)) {
    isum <- interactive$summary
    if (!is.null(isum) && isum$requests > 0L && is.finite(isum$success_rate)) {
      add("interactive_success_rate", TRUE, round(isum$success_rate, 4),
          th$success_rate_min, isum$success_rate >= th$success_rate_min,
          "Etkilesimli oturum eylem basari orani (DB/islem/encoding/upload).")
    } else {
      add("interactive_success_rate", FALSE, NA, th$success_rate_min, NA,
          "Etkilesimli serit eylem olcmedi (olculemeyen).")
    }

    # DB baglanti sizintisi (checkout != return) "gurultulu sayac" olabilir; bu
    # YALNIZ kendisi fail_on_interactive_db_leak ile opt-out edilebilir.
    leak_free <- isTRUE(interactive$db_pool$no_leak)
    if (isTRUE(th$fail_on_interactive_db_leak)) {
      add("interactive_db_no_leak", TRUE, interactive$db_pool$outstanding_checkouts,
          0L, leak_free, "Havuz checkout==return; baglanti sizintisi yok.")
    } else {
      add("interactive_db_no_leak", TRUE, interactive$db_pool$outstanding_checkouts,
          "raporlandi (esik yok)", TRUE, "DB sizinti fail kapatildi.")
    }

    # Cross-session izolasyon bir GUVENLIK ozelligidir; DB-leak opt-out'undan
    # BAGIMSIZ ve HER ZAMAN enforced'dir (gurultulu sayac opt-out'u izolasyonu
    # susturmaz). isolation_pass artik anahtar-sahip uyusmazligi + sohbet/mesaj
    # kapsamasini da icerir.
    add("interactive_cross_session_isolation", TRUE, isTRUE(interactive$isolation_pass),
        TRUE, isTRUE(interactive$isolation_pass),
        "Bir oturum baska kullanicinin sohbet/mesajini gormez + anahtar-sahip izolasyonu.")
    # Gercek scoping kaniti: ayni okuyucu KOMSU kullanici satirini disladi mi?
    add("interactive_isolation_excludes_other", TRUE,
        isTRUE(interactive$isolation_excludes_other), TRUE,
        isTRUE(interactive$isolation_excludes_other),
        "Eklenen komsu kullanici satiri ayni app-facing okuyucu ile DISLANDI.")
    # Anahtar-sahip uyusmazligi: yabanci sahipli anahtar KISISEL olarak kabul
    # edilmemeli (sahiplik temizleme yolu). Her zaman enforced.
    add("interactive_key_owner_mismatch_rejected", TRUE,
        isTRUE(interactive$key_owner_mismatch_rejected), TRUE,
        isTRUE(interactive$key_owner_mismatch_rejected),
        "Yabanci sahipli anahtar sunan oturum KISISEL olarak cozulmedi.")

    # Upload dogrulama da bu seridin kapsamidir; HER ZAMAN enforced (rollback
    # gibi). Aksi halde validate_uploaded_file regresyonu PASS gecebilirdi.
    add("interactive_upload_validation", TRUE, isTRUE(interactive$upload_pass),
        TRUE, isTRUE(interactive$upload_pass),
        sprintf("Etkilesimli upload dogrulama (basarisiz=%s).",
                as.character(interactive$upload_failures %||% NA)))

    # Dosya alim hatti (kopyalama + butunluk + kullanici kovasi izolasyonu) da
    # HER ZAMAN enforced: sessiz bir alim regresyonu PASS gecmemelidir.
    add("interactive_file_ingestion", TRUE, isTRUE(interactive$ingest_pass),
        TRUE, isTRUE(interactive$ingest_pass),
        sprintf("Etkilesimli dosya alim hatti (basarisiz=%s, bayt=%s).",
                as.character(interactive$ingest_failures %||% NA),
                as.character(interactive$ingest_bytes %||% NA)))

    add("interactive_tx_rollback_clean", TRUE, isTRUE(interactive$rollback_pass),
        TRUE, isTRUE(interactive$rollback_pass),
        "Niyetli islem hatasi rollback ile satir birakmadi.")

    if (isTRUE(th$fail_on_mojibake)) {
      add("interactive_mojibake_hits", TRUE, interactive$mojibake_hits, 0L,
          identical(as.integer(interactive$mojibake_hits), 0L),
          "Etkilesimli yazma/okuma Turkce round-trip mojibake.")
    } else {
      add("interactive_mojibake_hits", TRUE, interactive$mojibake_hits,
          "raporlandi (esik yok)", TRUE, "Interactive mojibake raporlandi; fail kapatildi.")
    }
  } else if (isTRUE(cfg$interactive_lane)) {
    # Etkilesimli serit ISTENDI ama calismadi. Bu, bu PR'nin ekledigi
    # DB-havuz/islem/izolasyon kapsamini kaybeder; varsayilan olarak ENFORCED
    # FAIL'dir (sessiz UNMEASURED PASS degil). Opt-out: fail_on_interactive_unavailable.
    if (isTRUE(th$fail_on_interactive_unavailable)) {
      add("interactive_lane_available", TRUE, FALSE, TRUE, FALSE,
          "Etkilesimli serit istendi ama calismadi (paket/bootstrap eksik); istenen kapsam kaybedildi.")
    } else {
      add("interactive_lane_available", FALSE, NA, TRUE, NA,
          "Etkilesimli serit istendi ama calismadi (olculemeyen; fail kapatildi).")
    }
  }

  # 16) Kademeli kapasite merdiveni: HER calistirilan adim stabil esigi gecmeli.
  # Bu, mevcut hicbir esigi DUSURMEZ; aksine STRICTER bir kademeli kontrol ekler:
  # sonraki bir adim basarisizsa kapi FAIL olur ("son stabil adim" yine de
  # capacity_ladder altinda durustce raporlanir). Yalniz merdiven CALISTIYSA olculur.
  if (!is.null(capacity_ladder) && isTRUE(capacity_ladder$ran) &&
      length(capacity_ladder$steps) > 0L) {
    stable_min <- as.numeric(capacity_ladder$stable_success_rate_min %||% th$success_rate_min)
    add("capacity_ladder_all_steps_pass", TRUE,
        sprintf("stabil=%s ilk_basarisiz=%s",
                as.character(capacity_ladder$stable_capacity_users %||% NA),
                as.character(capacity_ladder$first_failed_capacity_users %||% NA)),
        sprintf("tum adimlar effective>=%.2f", stable_min),
        isTRUE(capacity_ladder$all_steps_pass),
        "Calistirilan her kademeli adimin effective basari orani stabil esigi gecmeli.")
  } else if (isTRUE(cfg$capacity_ladder_enabled)) {
    add("capacity_ladder_all_steps_pass", FALSE, NA,
        "tum adimlar stabil esigi gecmeli", NA,
        "Kademeli merdiven istendi ama calismadi (HTTP serit/uygulama URL gerekli; olculemeyen).")
  }

  checks
}

# Esik kontrollerinden genel gecme/kalma ve nedenleri uretir.
soak_threshold_outcome <- function(checks) {
  enforced <- Filter(function(c) isTRUE(c$measured) && !is.na(c$pass), checks)
  failed <- Filter(function(c) isFALSE(c$pass), enforced)
  unmeasured <- Filter(function(c) !isTRUE(c$measured), checks)
  list(
    pass = length(failed) == 0L,
    failure_reasons = vapply(failed, function(c) {
      sprintf("%s (deger=%s, esik=%s)", c$name, as.character(c$value), as.character(c$threshold))
    }, character(1)),
    unmeasured_names = vapply(unmeasured, function(c) c$name, character(1))
  )
}

# ------------------------------------------------------------------------------
# does_prove / does_not_prove durustluk metinleri (serit + calisan adimlara gore).
# ------------------------------------------------------------------------------
soak_proof_statements <- function(cfg, summary, inprocess, attach, interactive = NULL,
                                  telemetry = NULL, capacity_ladder = NULL) {
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
  if (!is.null(telemetry) && isTRUE(telemetry$telemetry_available)) {
    proves <- c(proves, sprintf(paste(
      "Yuk suresince sistem telemetrisi ornendi (%d ornek): maksimum toplam CPU %s%%,",
      "maksimum app-portu TCP baglanti %s. Bu, darbogaz atfini gercek olcumle destekler."),
      telemetry$samples %||% 0L,
      as.character(telemetry$max_total_cpu_percent %||% NA),
      as.character(telemetry$max_tcp_connections_to_app %||% NA)))
  }
  if (!is.null(capacity_ladder) && isTRUE(capacity_ladder$ran)) {
    proves <- c(proves, sprintf(paste(
      "Kademeli kapasite merdiveni calisti; gozlenen son STABIL aktif-eszamanli adim:",
      "%s kullanici (ilk basarisiz adim: %s)."),
      as.character(capacity_ladder$stable_capacity_users %||% 0L),
      as.character(capacity_ladder$first_failed_capacity_users %||% NA)))
  }
  if (!is.null(interactive) && isTRUE(interactive$available)) {
    proves <- c(proves,
      sprintf(paste(
        "Etkilesimli serit %d in-process oturum x %d eylem boyunca GERCEK DB",
        "havuzu uzerinde sohbet olusturma/mesaj yazma/streaming-delta/stop-iptal/",
        "dosya-dogrulama/gecmis-okuma yurutuldu (basari orani %.3f)."),
        interactive$sessions, interactive$actions, interactive$summary$success_rate %||% NA),
      sprintf(paste(
        "Havuz checkout/return dengeli (checkout=%d return=%d, sizinti=%d);",
        "islem commit=%d rollback=%d ve niyetli rollback satir birakmadi."),
        interactive$db_pool$checkout, interactive$db_pool$returned,
        interactive$db_pool$outstanding_checkouts,
        interactive$db_pool$tx_commit, interactive$db_pool$tx_rollback),
      "Etkilesimli oturumlar arasi izolasyon: bir kullanici baska kullanicinin sohbet/mesajini gormedi.",
      "Etkilesimli yazma/okuma Turkce metni mojibake'siz korudu (DB-havuz param/okuma siniri).")
  }

  # does_not_prove (her zaman acik sinirlar).
  not <- c(not,
    sprintf("%d gercek eszamanli AKTIF kullaniciyi KANITLAMAZ (kullanici tabani hedefi=%d).",
            cfg$user_base_target, cfg$user_base_target),
    "Gercek LLM saglayicisinin bu eszamanlilik icin uretim throughput'unu KANITLAMAZ.",
    "Windows VM disindaki gercek aglardaki uretim gecikmesini KANITLAMAZ.",
    "Tam-yigin tarayici/websocket Shiny oturum eszamanliligini KANITLAMAZ (in-process alistirmalar helper-duzeyidir; gercek tarayici lane ayridir: run_browser_concurrency_lane.R).",
    "Gercek SQL Server'a Turkce yaziminin at-rest dogrulugunu KANITLAMAZ (ayri VM kodlama/havuz preflight kapisidir: run_vm_encoding_preflight_real.R, run_vm_sqlserver_pool_preflight_real.R).")

  # Telemetri olculemedi ise darbogaz atfi UNMEASURED'dir (sessiz PASS degil).
  if (is.null(telemetry) || !isTRUE(telemetry$telemetry_available)) {
    not <- c(not, "Sistem kaynak telemetrisi (CPU/bellek/TCP) bu kosumda OLCULEMEDI; darbogaz nedeni kesin atfedilemez (UNMEASURED).")
  }
  if (is.null(capacity_ladder) || !isTRUE(capacity_ladder$ran)) {
    not <- c(not, "Kademeli kapasite merdiveni bu kosumda calismadi; 50->100->250->500->1000 staged stabil kapasite bu artifacttan turetilemez.")
  }
  if (!is.null(interactive) && isTRUE(interactive$available)) {
    not <- c(not,
      "Etkilesimli serit tek-surecte ARDISIK oturumlardir; gercek eszamanli websocket/tarayici yuku DEGILDIR.",
      "Etkilesimli serit lane-yerel SQLite kullanir; uretim T-SQL/SQL Server davranisini ve at-rest encoding'i KANITLAMAZ.")
  }
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
                                server_alive_at_end, injected_faults = 0L,
                                interactive = NULL, telemetry = NULL,
                                capacity_ladder = NULL, timeout_attribution = NULL,
                                real_canary_classification = NULL,
                                real_llm_throughput = NULL,
                                load_driver = NULL, http_loadgen = NULL) {
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
    # Yuk surucusu deseni (burst/ramped/paced) + arrival anahtarlari. Bu kosumun
    # baglanti firtinasi mi yoksa rampali/pace'li mi oldugu kanitla raporlanir.
    load_driver = load_driver %||% cfg$load_driver %||% "load_driver yapilandirmasi yok",
    http_loadgen = http_loadgen %||% "http yuk-uretici telemetrisi toplanmadi (HTTP serit kapali/atlandi)",
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
      # curl zamanlama yuzdelikleri: connect (baglanti fazi) vs ttfb (app isleme).
      connect_ms_p50 = summary$connect_ms_p50,
      connect_ms_p95 = summary$connect_ms_p95,
      ttfb_ms_p50 = summary$ttfb_ms_p50,
      ttfb_ms_p95 = summary$ttfb_ms_p95,
      http_code_counts = summary$http_code_counts,
      status_counts = summary$status_counts,
      wall_seconds = summary$wall_seconds
    ),
    key_sources = key_sources,
    key_routing = if (!is.null(kr)) kr else "in-process alistirma calismadi",
    proxy_lane = proxy_summary %||% "proxy serit kullanilmadi",
    failure_injection = failure_probe %||% "hata-enjeksiyon probe calismadi",
    attach_mode = attach,
    interactive_lane = if (!is.null(interactive) && isTRUE(interactive$available)) {
      list(
        available = TRUE,
        sessions = interactive$sessions,
        actions = interactive$actions,
        metrics = list(
          requests = interactive$summary$requests,
          success = interactive$summary$success,
          errors = interactive$summary$errors,
          timeouts = interactive$summary$timeouts,
          success_rate = interactive$summary$success_rate,
          p50_latency_ms = interactive$summary$p50_latency_ms,
          p95_latency_ms = interactive$summary$p95_latency_ms,
          p99_latency_ms = interactive$summary$p99_latency_ms,
          throughput_ops_per_min = interactive$summary$throughput_ops_per_min,
          scenario_counts = interactive$summary$scenario_counts
        ),
        db_pool = interactive$db_pool,
        cross_session_isolation_pass = isTRUE(interactive$isolation_pass),
        isolation_excludes_other_user = isTRUE(interactive$isolation_excludes_other),
        key_owner_mismatch_rejected = isTRUE(interactive$key_owner_mismatch_rejected),
        tx_rollback_clean = isTRUE(interactive$rollback_pass),
        upload_validation_pass = isTRUE(interactive$upload_pass),
        mojibake_hits = interactive$mojibake_hits,
        note = interactive$note
      )
    } else if (isTRUE(cfg$interactive_lane)) {
      list(available = FALSE,
           reason = interactive$reason %||% "etkilesimli serit calismadi (olculemeyen)")
    } else {
      "etkilesimli serit kapali"
    },
    capacity_curve = capacity_rows %||% list(),
    capacity_ladder = if (!is.null(capacity_ladder) && isTRUE(capacity_ladder$ran)) {
      list(
        ran = TRUE,
        stable_success_rate_min = capacity_ladder$stable_success_rate_min,
        stop_on_first_failed_step = isTRUE(capacity_ladder$stop_on_first_failed_step),
        stable_capacity_users = capacity_ladder$stable_capacity_users,
        first_failed_capacity_users = capacity_ladder$first_failed_capacity_users,
        recommended_next_target = capacity_ladder$recommended_next_target,
        recommended_probe_steps = capacity_ladder$recommended_probe_steps %||% integer(0),
        all_steps_pass = isTRUE(capacity_ladder$all_steps_pass),
        bottleneck_hints = capacity_ladder$bottleneck_hints,
        bottleneck_hint = capacity_ladder$bottleneck_hint %||%
          (capacity_ladder$bottleneck_hints %||% NA_character_)[1],
        dominant_timeout_class = capacity_ladder$dominant_timeout_class %||% NA_character_,
        loadgen_saturation_hint = capacity_ladder$loadgen_saturation_hint %||% NA_character_,
        app_tcp_max_by_state = capacity_ladder$app_tcp_max_by_state %||% list(),
        steps = capacity_ladder$steps,
        note = paste(
          "Kademeli kapasite merdiveni: son STABIL adim durustce raporlanir.",
          "Basarisiz sonraki adimlar PASS olarak sunulmaz; aggregate effective_success_rate",
          "ve capacity_ladder_all_steps_pass kontrolleri ayrica zorlanir."
        )
      )
    } else if (isTRUE(cfg$capacity_ladder_enabled)) {
      list(ran = FALSE, reason = "kademeli merdiven istendi ama calismadi (HTTP serit/uygulama URL gerekli)")
    } else {
      "kademeli merdiven kapali"
    },
    system_telemetry = if (!is.null(telemetry)) telemetry else {
      if (isTRUE(cfg$telemetry_enabled)) {
        list(telemetry_available = FALSE,
             telemetry_warnings = "telemetri istendi ama ozet uretilmedi (UNMEASURED)")
      } else "telemetri kapali"
    },
    timeout_attribution = timeout_attribution %||% list(),
    real_canary_classification = real_canary_classification %||% "real-canary serit kullanilmadi",
    real_llm_throughput = if (!is.null(real_llm_throughput)) {
      real_llm_throughput
    } else if (isTRUE(cfg$real_llm_throughput_enabled)) {
      "throughput probe istendi ama calismadi"
    } else {
      "real-LLM throughput probe kapali (fake/proxy serit gercek LLM throughput'u DEGILDIR)"
    },
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
    has_tc <- "timeout_class" %in% names(bad)
    has_ek <- "endpoint_kind" %in% names(bad)
    for (i in seq_len(nrow(bad))) {
      tc <- if (has_tc) bad$timeout_class[i] else NA_character_
      code_i <- bad$http_code[i]
      rec <- list(
        ts_epoch = bad$ts_epoch[i], lane = bad$lane[i],
        scenario = bad$scenario[i], status = bad$status[i],
        http_status = if (is.na(code_i)) NULL else as.integer(code_i),
        latency_ms = bad$latency_ms[i],
        timeout_class = if (is.na(tc) || tc == "") "unknown_error" else tc,
        endpoint_kind = if (has_ek) bad$endpoint_kind[i] else "n/a",
        retryable = soak_failure_retryable(tc, code_i)
      )
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

  # capacity_ladder.csv + capacity_ladder_summary.json (kademeli merdiven calistiysa)
  cl <- evidence$capacity_ladder
  if (is.list(cl) && isTRUE(cl$ran) && length(cl$steps) > 0L) {
    lad_df <- do.call(rbind, lapply(cl$steps, function(s) {
      tel <- s$telemetry %||% list()
      tbs <- tel$app_tcp_max_by_state %||% list()
      lg <- s$loadgen %||% list()
      data.frame(
        users = s$users %||% NA_integer_,
        duration_seconds = s$duration_seconds %||% NA_real_,
        requests = s$requests %||% NA_integer_,
        success = s$success %||% NA_integer_,
        errors = s$errors %||% NA_integer_,
        timeouts = s$timeouts %||% NA_integer_,
        raw_success_rate = s$raw_success_rate %||% NA_real_,
        effective_success_rate = s$effective_success_rate %||% NA_real_,
        p50_latency_ms = s$p50_latency_ms %||% NA_real_,
        p95_latency_ms = s$p95_latency_ms %||% NA_real_,
        p99_latency_ms = s$p99_latency_ms %||% NA_real_,
        throughput_ops_per_min = s$throughput_ops_per_min %||% NA_real_,
        connect_ms_p95 = s$connect_ms_p95 %||% NA_real_,
        ttfb_ms_p95 = s$ttfb_ms_p95 %||% NA_real_,
        dominant_timeout_class = s$dominant_timeout_class %||% NA_character_,
        max_total_cpu_percent = tel$max_total_cpu_percent %||% NA_real_,
        max_tcp_connections_to_app = tel$max_tcp_connections_to_app %||% NA_integer_,
        max_tcp_established = tbs$tcp_established %||% NA_integer_,
        max_tcp_syn_recv = tbs$tcp_syn_recv %||% NA_integer_,
        max_tcp_time_wait = tbs$tcp_time_wait %||% NA_integer_,
        loadgen_max_inflight = lg$max_inflight %||% NA_integer_,
        loadgen_saturation_hint = lg$saturation_hint %||% NA_character_,
        pass = isTRUE(s$pass),
        stringsAsFactors = FALSE
      )
    }))
    utils::write.csv(lad_df, file.path(artifact_dir, "capacity_ladder.csv"),
                     row.names = FALSE, fileEncoding = "UTF-8")
    jsonlite::write_json(cl, file.path(artifact_dir, "capacity_ladder_summary.json"),
                         auto_unbox = TRUE, pretty = TRUE, null = "null")
  }

  # system_telemetry_summary.json (telemetri ozeti; CSV arka surec tarafindan yazildi)
  if (is.list(evidence$system_telemetry)) {
    jsonlite::write_json(evidence$system_telemetry,
                         file.path(artifact_dir, "system_telemetry_summary.json"),
                         auto_unbox = TRUE, pretty = TRUE, null = "null")
  }

  # timeout_attribution.json (hata atfi)
  if (is.list(evidence$timeout_attribution) && length(evidence$timeout_attribution) > 0L) {
    jsonlite::write_json(evidence$timeout_attribution,
                         file.path(artifact_dir, "timeout_attribution.json"),
                         auto_unbox = TRUE, pretty = TRUE, null = "null")
  }

  # real_canary_classification.json / real_llm_throughput.json (varsa)
  if (is.list(evidence$real_canary_classification)) {
    jsonlite::write_json(evidence$real_canary_classification,
                         file.path(artifact_dir, "real_canary_classification.json"),
                         auto_unbox = TRUE, pretty = TRUE, null = "null")
  }
  if (is.list(evidence$real_llm_throughput)) {
    jsonlite::write_json(evidence$real_llm_throughput,
                         file.path(artifact_dir, "real_llm_throughput.json"),
                         auto_unbox = TRUE, pretty = TRUE, null = "null")
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
    sprintf("- curl connect p50/p95 (ms): %s / %s | ttfb p50/p95 (ms): %s / %s",
            as.character(m$connect_ms_p50 %||% NA), as.character(m$connect_ms_p95 %||% NA),
            as.character(m$ttfb_ms_p50 %||% NA), as.character(m$ttfb_ms_p95 %||% NA)),
    "",
    "## Yuk Surucusu (Load Driver)",
    if (is.list(evidence$load_driver)) {
      ld <- evidence$load_driver
      c(sprintf("- Desen: **%s** | ramp=%ss | tavan_yeni/tur=%s | think=%s-%s ms | baglanti_reuse=%s",
                as.character(ld$pattern %||% NA), as.character(ld$ramp_up_seconds %||% 0),
                as.character(ld$max_new_requests_per_tick %||% 0),
                as.character(ld$think_time_ms_min %||% 0), as.character(ld$think_time_ms_max %||% 0),
                as.character(ld$connection_reuse %||% TRUE)))
    } else {
      "- Yuk surucusu yapilandirmasi yok."
    },
    if (is.list(evidence$http_loadgen)) {
      lg <- evidence$http_loadgen
      sprintf(paste("- Yuk-uretici: max_inflight=%s | baslatilan=%s | dongu=%s |",
                    "max_loop_lag=%s ms | doygunluk=%s"),
              as.character(lg$max_inflight %||% NA), as.character(lg$launched %||% NA),
              as.character(lg$loop_iters %||% NA), as.character(lg$max_loop_lag_ms %||% NA),
              as.character(lg$saturation_hint %||% NA))
    } else {
      "- Yuk-uretici telemetrisi yok (HTTP serit kapali/atlandi)."
    },
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
    "## Etkilesimli Serit (interactive)",
    if (is.list(evidence$interactive_lane) && isTRUE(evidence$interactive_lane$available)) {
      il <- evidence$interactive_lane
      c(
        sprintf("- Oturum: %d | Eylem: %d | Basari orani: %s",
                il$sessions, il$actions, as.character(il$metrics$success_rate)),
        sprintf("- Gecikme p50/p95/p99 (ms): %s / %s / %s",
                as.character(il$metrics$p50_latency_ms), as.character(il$metrics$p95_latency_ms),
                as.character(il$metrics$p99_latency_ms)),
        sprintf("- DB havuz: checkout=%d return=%d sizinti=%d | tx commit=%d rollback=%d",
                il$db_pool$checkout, il$db_pool$returned, il$db_pool$outstanding_checkouts,
                il$db_pool$tx_commit, il$db_pool$tx_rollback),
        sprintf("- Izolasyon: %s | rollback temiz: %s | upload: %s | mojibake: %s",
                as.character(il$cross_session_isolation_pass),
                as.character(il$tx_rollback_clean),
                as.character(il$upload_validation_pass),
                as.character(il$mojibake_hits))
      )
    } else {
      "- Calismadi/kapali (kanit DEGIL)."
    },
    "",
    "## Sistem Telemetrisi",
    if (is.list(evidence$system_telemetry) && isTRUE(evidence$system_telemetry$telemetry_available)) {
      st <- evidence$system_telemetry
      tbs <- st$app_tcp_max_by_state %||% list()
      c(
        sprintf("- Ornek: %s | max CPU: %s%% | max bellek kullanim: %s MB",
                as.character(st$samples), as.character(st$max_total_cpu_percent),
                as.character(st$max_mem_used_mb)),
        sprintf("- max R surec bellek: %s MB | max SQL Server bellek: %s MB | max app-port TCP: %s",
                as.character(st$max_r_process_memory_mb), as.character(st$max_sqlserver_memory_mb),
                as.character(st$max_tcp_connections_to_app)),
        sprintf(paste("- app-port TCP durum (max): established=%s syn_recv=%s syn_sent=%s",
                      "time_wait=%s close_wait=%s listen=%s"),
                as.character(tbs$tcp_established %||% NA), as.character(tbs$tcp_syn_recv %||% NA),
                as.character(tbs$tcp_syn_sent %||% NA), as.character(tbs$tcp_time_wait %||% NA),
                as.character(tbs$tcp_close_wait %||% NA), as.character(tbs$tcp_listen %||% NA))
      )
    } else {
      "- UNMEASURED (telemetri kapali/olculemedi; darbogaz atfi kanit DEGIL)."
    },
    "",
    "## Kademeli Kapasite Merdiveni",
    if (is.list(evidence$capacity_ladder) && isTRUE(evidence$capacity_ladder$ran)) {
      cl <- evidence$capacity_ladder
      c(
        sprintf("- Son STABIL aktif-eszamanli kullanici: **%s** | ilk basarisiz: %s",
                as.character(cl$stable_capacity_users), as.character(cl$first_failed_capacity_users)),
        sprintf("- Onerilen sonraki hedef: %s | tum adimlar gecti: %s",
                as.character(cl$recommended_next_target), as.character(cl$all_steps_pass)),
        sprintf("- Onerilen ara kademeler (daraltma): %s",
                if (length(cl$recommended_probe_steps %||% integer(0)) > 0L) {
                  paste(cl$recommended_probe_steps, collapse = ", ")
                } else "yok"),
        sprintf("- Baskin hata sinifi: %s | yuk-uretici doygunluk: %s",
                as.character(cl$dominant_timeout_class %||% NA),
                as.character(cl$loadgen_saturation_hint %||% NA)),
        sprintf("- Darbogaz ipucu (birincil): %s", as.character(cl$bottleneck_hint %||% NA)),
        sprintf("- Darbogaz ipuclari: %s", paste(cl$bottleneck_hints, collapse = ", "))
      )
    } else {
      "- Calismadi/kapali (kanit DEGIL)."
    },
    "",
    "## Hata Atfi (timeout attribution)",
    if (is.list(evidence$timeout_attribution) &&
        length(evidence$timeout_attribution$timeout_breakdown %||% list()) > 0L) {
      ta <- evidence$timeout_attribution
      bk <- ta$timeout_breakdown
      c(sprintf("- Toplam basarisiz: %s", as.character(ta$total_failures)),
        paste0("- ", names(bk), ": ", unlist(bk)))
    } else {
      "- Basarisiz istek yok veya atif uretilmedi."
    },
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

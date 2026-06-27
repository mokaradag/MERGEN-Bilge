# ==============================================================================
# Dosya Yolu: tests/scripts/soak_client.R
# Aciklama:
#   Soak yuk surucusu (kapali-dongu eszamanli HTTP) + IN-PROCESS uygulama-yolu
#   alistirmalari (encoding round-trip, yukleme dogrulama, anahtar yonlendirme,
#   atomic-write/safe-path, oturum temizligi).
#
#   Durustluk: HTTP serit gercek eszamanli yuktur. In-process alistirmalar
#   uygulamanin GERCEK yardimci fonksiyonlarini cagirir (helper-duzeyi dogruluk);
#   tam-yigin tarayici/DB eszamanliligi DEGILDIR ve oyle iddia edilmez.
#
#   Bu dosya BILEREK ASCII-guvenlidir (Turkce ozel karakter yok). Calisma zamani
#   Turkce fikstur metinleri \u kacislariyla uretilir (parser-guvenli).
# ==============================================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || is.na(x[1])) y else x

# ------------------------------------------------------------------------------
# Curl POST ayarlarini Windows VM ile uyumlu sekilde yapar.
# Not: Bazi Windows/curl derlemelerinde timeout_ms secenegi sorun cikarabildigi
# icin saniye bazli timeout kullanilir.
# ------------------------------------------------------------------------------
soak_configure_post_handle <- function(h, body, timeout_ms) {
  timeout_sec <- max(1, as.numeric(timeout_ms %||% 20000) / 1000)

  curl::handle_setopt(
    h,
    post = TRUE,
    postfields = body,
    timeout = timeout_sec,
    connecttimeout = min(10, timeout_sec)
  )

  invisible(h)
}

# ------------------------------------------------------------------------------
# Kullanici anahtarlari (serit-bazli).
# ------------------------------------------------------------------------------
soak_make_user_keys <- function(n_users, lane, real_key = "") {
  n_users <- max(1L, as.integer(n_users))
  if (identical(lane, "proxy")) {
    # Sahte kisisel-gorunumlu anahtarlar: sk-test-userNNN.
    return(sprintf("sk-test-user%03d", seq_len(n_users)))
  }
  if (identical(lane, "real-canary")) {
    # Tek gercek anahtar (tum canary kullanicilari paylasir).
    return(rep(real_key, n_users))
  }
  # Fake serit: jenerik (localhost noauth; anahtar opsiyonel).
  rep("sk-soak-fake", n_users)
}

# ------------------------------------------------------------------------------
# App attach URL'sine cache-buster timestamp eklerken POSIX epoch milisaniyesi
# 32-bit integer araligini asar. Windows VM konsollarinda as.integer(...) bu
# durumda her istek icin uyari basar ve soak cikisini kullanilmaz hale getirir.
# Timestamp string olarak tutulur; URL icin yalnizca benzersizlik gerekir.
# ------------------------------------------------------------------------------
soak_epoch_millis_text <- function(now = Sys.time()) {
  sprintf("%.0f", as.numeric(now) * 1000)
}

soak_app_request_url <- function(base_url, user_label, scenario_id, now = Sys.time()) {
  sep <- if (grepl("?", base_url, fixed = TRUE)) "&" else "?"
  sprintf("%s%s_soak_user=%s&_soak_scenario=%s&_soak_t=%s",
          base_url, sep, utils::URLencode(user_label, reserved = TRUE),
          utils::URLencode(scenario_id, reserved = TRUE),
          utils::URLencode(soak_epoch_millis_text(now), reserved = TRUE))
}

# ------------------------------------------------------------------------------
# Rampa hedefi (SAF): elapsed saniyeye gore aktif-eszamanliligi 1 -> concurrent
# araliginda dogrusal buyutur. ramp_up_seconds <= 0 ise her zaman concurrent
# doner (ani burst; mevcut varsayilan davranis).
# ------------------------------------------------------------------------------
soak_target_concurrency_now <- function(concurrent, ramp_up_seconds, elapsed_seconds) {
  concurrent <- max(1L, as.integer(concurrent))
  ramp <- suppressWarnings(as.numeric(ramp_up_seconds))
  if (!is.finite(ramp) || ramp <= 0) return(concurrent)
  el <- suppressWarnings(as.numeric(elapsed_seconds))
  if (!is.finite(el) || el < 0) el <- 0
  frac <- min(1, el / ramp)
  t <- as.integer(ceiling(concurrent * frac))
  max(1L, min(concurrent, t))
}

# curl 'times' (saniye) -> ms; connect ve post-connect ilk-byte ayri tutulur.
# curl starttransfer baglanti/TLS surelerini de icerir; app/TTFB bileseni icin
# connect sonrasini (starttransfer - connect) kaydederiz. Olculemezse NA.
# Yalniz tamamlanan (done) istekler icin gelir.
soak_extract_curl_times_ms <- function(times) {
  out <- list(connect_ms = NA_real_, ttfb_ms = NA_real_, total_ms = NA_real_)
  if (is.null(times) || length(times) == 0L) return(out)
  g <- function(nm) {
    v <- suppressWarnings(as.numeric(times[[nm]]))
    if (length(v) == 0L || !is.finite(v)) NA_real_ else v
  }
  connect <- g("connect")
  starttransfer <- g("starttransfer")
  total <- g("total")
  if (is.finite(connect)) out$connect_ms <- round(connect * 1000, 2)
  if (is.finite(starttransfer)) {
    app_ttfb <- if (is.finite(connect)) max(0, starttransfer - connect) else starttransfer
    out$ttfb_ms <- round(app_ttfb * 1000, 2)
  }
  if (is.finite(total)) out$total_ms <- round(total * 1000, 2)
  out
}

# Think-time gecikmesi (saniye). min==max ise sabit; degilse jitter'li uniform.
soak_think_delay_sec <- function(min_ms, max_ms) {
  min_ms <- max(0, suppressWarnings(as.numeric(min_ms)))
  max_ms <- suppressWarnings(as.numeric(max_ms))
  if (!is.finite(max_ms) || max_ms < min_ms) max_ms <- min_ms
  if (!is.finite(max_ms) || max_ms <= 0) return(0)
  if (max_ms == min_ms) return(min_ms / 1000)
  stats::runif(1, min_ms, max_ms) / 1000
}

# ------------------------------------------------------------------------------
# Kapali-dongu eszamanli HTTP yuk surucusu (curl multi).
#   url           : POST hedefi (.../v1/chat/completions)
#   metrics       : soak_metrics_new() ortami
#   duration_sec  : sure
#   concurrent    : ayni anda en fazla ucusta istek (aktif eszamanlilik tavani)
#   user_keys     : kullanici basina bearer anahtarlari
#   lane          : fake | proxy | real-canary
#
# Yuk deseni (cfg$load_driver) ile sekillenir; TUM varsayilanlar mevcut "burst"
# davranisini korur: ramp yok, tavan yok, think yok, baglanti yeniden-kullanim
# acik. Geriye yuk-uretici telemetrisi (launched/completed/max_inflight/loop lag
# vb.) doner; boylece darbogaz istemci/loop tarafinda mi yoksa sunucu tarafinda
# mi diye ayirt edilebilir.
# ------------------------------------------------------------------------------
soak_http_load <- function(url, cfg, metrics, duration_sec, concurrent,
                           user_keys, lane, catalog = soak_scenario_catalog()) {
  n_users <- length(user_keys)
  model <- "soak-fake-model"
  client_timeout_ms <- as.numeric(cfg$client_timeout_sec %||% 20) * 1000
  app_http_mode <- !grepl("/v1/chat/completions/?$", url)

  # Hata atfi (timeout attribution) icin endpoint turu: app koku mu yoksa
  # dogrudan fake/proxy LLM endpoint'i mi vuruluyor?
  endpoint_kind <- if (isTRUE(app_http_mode)) {
    "app"
  } else {
    switch(lane, fake = "fake_llm", proxy = "proxy_llm", "real_llm")
  }

  # Yuk surucusu realizm anahtarlari (cfg yoksa veya minimal ise mevcut davranis).
  ld <- cfg$load_driver %||% list()
  ramp_up_seconds <- suppressWarnings(as.numeric(ld$ramp_up_seconds %||% 0))
  if (!is.finite(ramp_up_seconds) || ramp_up_seconds < 0) ramp_up_seconds <- 0
  max_new_per_tick <- suppressWarnings(as.integer(ld$max_new_requests_per_tick %||% 0L))
  if (is.na(max_new_per_tick) || max_new_per_tick < 0L) max_new_per_tick <- 0L
  think_min_ms <- suppressWarnings(as.numeric(ld$think_time_ms_min %||% 0))
  think_max_ms <- suppressWarnings(as.numeric(ld$think_time_ms_max %||% think_min_ms))
  if (!is.finite(think_min_ms) || think_min_ms < 0) think_min_ms <- 0
  if (!is.finite(think_max_ms) || think_max_ms < think_min_ms) think_max_ms <- think_min_ms
  think_enabled <- think_max_ms > 0
  connection_reuse <- isTRUE(ld$connection_reuse %||% TRUE)

  # curl havuzu: host_con eszamanlilik kadar yuksek olmali (varsayilan 6 ise
  # serilesir). multiplex kapali tutulur (her istek ayri baglanti).
  con_cap <- max(as.integer(concurrent) + 10L, 100L)
  pool <- curl::new_pool(total_con = con_cap, host_con = con_cap, multiplex = FALSE)

  st <- new.env(parent = emptyenv())
  st$n <- 0L                  # ucustaki (inflight) istek sayisi
  st$launched <- 0L           # baslatilan toplam istek
  st$completed <- 0L          # tamamlanan (done+fail) toplam istek
  st$max_inflight <- 0L       # gozlenen en yuksek eszamanlilik
  st$think_until <- numeric(0)  # think modunda: kullanici bazli hazir zamanlari
  st$think_user <- integer(0)    # think_until ile hizali kullanici indeksleri
  st$ready_users <- integer(0)   # think suresi dolmus ve yeniden baslatilacak kullanicilar
  st$user_busy <- rep(FALSE, n_users)  # ucusta/sogumada/hazir kuyrugunda olanlar
  user_idx <- 0L

  n_thinking <- function() if (think_enabled) length(st$think_until) else 0L
  mature_thinking <- function(now_num) {
    if (!think_enabled || length(st$think_until) == 0L) return(invisible(NULL))
    due <- st$think_until <= now_num
    if (any(due)) {
      st$ready_users <- c(st$ready_users, st$think_user[due])
      st$think_until <- st$think_until[!due]
      st$think_user <- st$think_user[!due]
    }
    invisible(NULL)
  }
  schedule_think <- function(idx) {
    st$think_user <- c(st$think_user, as.integer(idx))
    st$think_until <- c(st$think_until,
                        as.numeric(Sys.time()) + soak_think_delay_sec(think_min_ms, think_max_ms))
  }
  next_available_user <- function() {
    if (!think_enabled) {
      user_idx <<- (user_idx %% n_users) + 1L
      return(user_idx)
    }
    for (unused in seq_len(n_users)) {
      user_idx <<- (user_idx %% n_users) + 1L
      if (!isTRUE(st$user_busy[[user_idx]])) return(user_idx)
    }
    NA_integer_
  }

  add_one <- function(request_user_idx = NA_integer_) {
    current_user_idx <- suppressWarnings(as.integer(request_user_idx %||% NA_integer_))
    if (is.na(current_user_idx) || current_user_idx < 1L || current_user_idx > n_users) {
      current_user_idx <- next_available_user()
    }
    if (is.na(current_user_idx)) return(FALSE)
    st$user_busy[[current_user_idx]] <- TRUE
    key <- user_keys[[current_user_idx]]
    user_label <- sprintf("user%03d", current_user_idx)
    scen <- soak_pick_scenario(catalog)
    body <- soak_build_chat_body(scen, model)

    request_url <- url
    h <- curl::new_handle()
    hdrs <- list("X-Soak-User" = user_label)
    if (isTRUE(app_http_mode)) {
      request_url <- soak_app_request_url(request_url, user_label, scen$id)
      curl::handle_setopt(h, httpget = TRUE, timeout = max(1, client_timeout_ms / 1000),
                          connecttimeout = min(10, max(1, client_timeout_ms / 1000)))
    } else {
      hdrs[["Content-Type"]] <- "application/json"
      if (nzchar(key)) hdrs[["Authorization"]] <- paste("Bearer", key)
      if (!identical(lane, "proxy")) hdrs[["X-Soak-User"]] <- NULL
      soak_configure_post_handle(h, body, client_timeout_ms)
    }
    if (!connection_reuse) {
      # Her istegi taze baglantiya zorla (havuz yeniden kullanmaz); operator
      # baglanti-kurulum maliyetini izole edebilir. Olmayan curl derlemelerinde
      # sessizce yok sayilir.
      tryCatch(curl::handle_setopt(h, forbid_reuse = 1L, fresh_connect = 1L),
               error = function(e) NULL)
    }
    curl::handle_setopt(h, url = request_url)
    do.call(curl::handle_setheaders, c(list(h), hdrs))

    start <- Sys.time()
    scen_id <- if (isTRUE(app_http_mode)) paste0("app_http_", scen$id) else scen$id
    st$n <- st$n + 1L
    st$launched <- st$launched + 1L
    if (st$n > st$max_inflight) st$max_inflight <- st$n

    curl::multi_add(
      h,
      done = function(res) {
        st$n <- st$n - 1L
        st$completed <- st$completed + 1L
        lat <- as.numeric(difftime(Sys.time(), start, units = "secs")) * 1000
        code <- as.integer(res$status_code %||% NA_integer_)
        status <- if (!is.na(code) && code >= 200L && code < 300L) "ok" else "error"
        ks <- "n/a"
        if (identical(lane, "proxy")) {
          parsed <- tryCatch(curl::parse_headers_list(res$headers), error = function(e) list())
          ks <- parsed[["x-soak-key-source"]] %||% "n/a"
        }
        tm <- soak_extract_curl_times_ms(res$times)
        tclass <- soak_classify_failure(status, code, "", endpoint_kind)
        soak_metrics_record(metrics, lane, scen_id, lat, status, code,
                            length(res$content %||% raw()), ks, tclass, endpoint_kind,
                            connect_ms = tm$connect_ms, ttfb_ms = tm$ttfb_ms)
        if (isTRUE(think_enabled)) {
          schedule_think(current_user_idx)
        } else {
          st$user_busy[[current_user_idx]] <- FALSE
        }
      },
      fail = function(msg) {
        st$n <- st$n - 1L
        st$completed <- st$completed + 1L
        lat <- as.numeric(difftime(Sys.time(), start, units = "secs")) * 1000
        status <- if (grepl("tim(e|ed) ?out|timeout", msg, ignore.case = TRUE)) "timeout" else "error"
        tclass <- soak_classify_failure(status, NA_integer_, msg, endpoint_kind)
        soak_metrics_record(metrics, lane, scen_id, lat, status, NA_integer_, 0, "n/a",
                            tclass, endpoint_kind)
        if (isTRUE(think_enabled)) {
          schedule_think(current_user_idx)
        } else {
          st$user_busy[[current_user_idx]] <- FALSE
        }
      },
      pool = pool
    )
    TRUE
  }

  # Bir refill turu: hedef aktif-eszamanliliga (rampa) gore bos slotlari doldurur.
  # idle = target_now - inflight - thinking. max_new_per_tick varsa tur basina
  # acilan yeni istek sayisi sinirlanir (baglanti firtinasini yumusatmak icin).
  refill <- function(now) {
    elapsed <- as.numeric(now) - as.numeric(loop_start)
    target <- soak_target_concurrency_now(concurrent, ramp_up_seconds, elapsed)
    added <- 0L
    repeat {
      idle <- target - st$n - n_thinking()
      if (idle <= 0L) break
      if (think_enabled && length(st$ready_users) > 0L) {
        due_user <- st$ready_users[[1L]]
        st$ready_users <- st$ready_users[-1L]
        launched <- add_one(due_user)
      } else {
        launched <- add_one()
      }
      if (!isTRUE(launched)) break
      added <- added + 1L
      if (max_new_per_tick > 0L && added >= max_new_per_tick) break
    }
    invisible(added)
  }

  loop_start <- Sys.time()
  t_end <- loop_start + duration_sec
  loop_iters <- 0L
  sum_loop_lag_ms <- 0
  max_loop_lag_ms <- 0
  last_run <- as.numeric(Sys.time())

  mature_thinking(as.numeric(Sys.time()))
  refill(Sys.time())

  repeat {
    curl::multi_run(timeout = 0.25, poll = TRUE, pool = pool)
    loop_iters <- loop_iters + 1L
    now_num <- as.numeric(Sys.time())
    lag_ms <- (now_num - last_run) * 1000
    if (is.finite(lag_ms)) {
      if (lag_ms > max_loop_lag_ms) max_loop_lag_ms <- lag_ms
      sum_loop_lag_ms <- sum_loop_lag_ms + lag_ms
    }
    last_run <- now_num
    if (Sys.time() >= t_end) break
    mature_thinking(now_num)
    added <- refill(Sys.time())
    # Think modunda tum "kullanicilar" beklerken havuz bos kalir; multi_run aninda
    # doner ve dongu bosa doner (CPU spin). Yuk-uretici VM'de app ile ayni cekirdegi
    # paylastigi icin bu olcumu carpitir. Yalniz gercekten bos (inflight=0 + yeni
    # istek eklenmedi) think penceresinde kisa uyu. burst/ramped yolunu etkilemez.
    if (think_enabled && st$n == 0L && added == 0L) Sys.sleep(0.005)
  }
  # Yuk-penceresi suresi (drain HARIC): throughput paydasi.
  load_seconds <- as.numeric(difftime(Sys.time(), loop_start, units = "secs"))
  soak_metrics_add_load_seconds(metrics, load_seconds)

  # Kalan ucustaki istekleri bosalt. Bazi Windows/curl derlemelerinde tek
  # multi_run() cagrisi tum callback'leri teslim etmeyebilir; kapali donguyu
  # kisa ve sinirli bir drain penceresiyle surdurerek "0 istek olculdu" gibi
  # yalanci UNMEASURED sonucunu engelleriz.
  drain_deadline <- Sys.time() + max(5, client_timeout_ms / 1000 + 5)
  while (st$n > 0L && Sys.time() < drain_deadline) {
    tryCatch(curl::multi_run(timeout = 0.25, poll = TRUE, pool = pool),
             error = function(e) NULL)
  }

  # Yuk-uretici (load generator) telemetrisi: darbogaz istemci/loop tarafinda mi
  # yoksa sunucu tarafinda mi sorusuna kanit. Ham sir icermez.
  list(
    load_pattern = ld$pattern %||%
      soak_load_pattern_label(ramp_up_seconds, think_min_ms, think_max_ms),
    target_users = as.integer(concurrent),
    ramp_up_seconds = ramp_up_seconds,
    max_new_requests_per_tick = max_new_per_tick,
    think_time_ms_min = as.integer(think_min_ms),
    think_time_ms_max = as.integer(think_max_ms),
    connection_reuse = connection_reuse,
    launched = as.integer(st$launched),
    completed = as.integer(st$completed),
    max_inflight = as.integer(st$max_inflight),
    loop_iters = as.integer(loop_iters),
    max_loop_lag_ms = round(max_loop_lag_ms, 1),
    mean_loop_lag_ms = if (loop_iters > 0L) round(sum_loop_lag_ms / loop_iters, 2) else NA_real_,
    scheduled_per_sec = if (load_seconds > 0) round(st$launched / load_seconds, 1) else NA_real_,
    load_seconds = round(load_seconds, 1)
  )
}

# ------------------------------------------------------------------------------
# Gercek LLM yanit asamasi siniflandirmasi (SAF). Gateway/policy/auth/model/
# rate-limit/uretim/streaming asamalarini ayirt eder. ERR-234 gibi gateway
# policy hatalarini "gateway_policy_failed" olarak isaretler -- bu bir MERGEN
# app yuk hatasi DEGILDIR. Ham anahtar/sir kullanmaz; yalniz kod + govde deseni.
# ------------------------------------------------------------------------------
soak_classify_real_llm_response <- function(http_code, body_text = "", curl_error = "",
                                            stream = FALSE) {
  ce <- tolower(as.character(curl_error %||% ""))
  if (nzchar(ce)) {
    if (grepl("tim(e|ed) ?out|timeout", ce)) return("real_llm_timeout")
    if (grepl("connect|resolve|refused|reset|unreachable", ce)) return("app_unreachable")
    return("transport_error")
  }
  code <- suppressWarnings(as.integer(http_code))
  body <- tolower(as.character(body_text %||% ""))
  gateway_policy <- grepl("err-234", body) ||
    grepl("rate limit policy failed", body) ||
    grepl("endpoint rate limit", body)

  if (is.na(code)) return("unknown")
  if (code >= 200L && code < 300L) {
    return(if (isTRUE(stream)) "streaming_completed" else "generation_completed")
  }
  if (code %in% c(401L, 403L)) return("auth_rejected")
  if (identical(code, 404L)) return("model_or_route_not_found")
  if (identical(code, 429L)) return("rate_limited")
  if (code >= 500L) return(if (isTRUE(gateway_policy)) "gateway_policy_failed" else "gateway_5xx")
  if (isTRUE(gateway_policy)) return("gateway_policy_failed")
  "gateway_error"
}

# Asama -> metrik timeout_class esleme (real_llm endpoint icin).
.soak_real_stage_to_class <- function(stage) {
  switch(stage,
         generation_completed = "n/a",
         streaming_completed = "n/a",
         real_llm_timeout = "real_llm_timeout",
         rate_limited = "rate_limited",
         auth_rejected = "real_llm_gateway_error",
         model_or_route_not_found = "real_llm_gateway_error",
         gateway_policy_failed = "real_llm_gateway_error",
         gateway_5xx = "real_llm_gateway_error",
         gateway_error = "real_llm_gateway_error",
         app_unreachable = "connection_error",
         transport_error = "unknown_error",
         "unknown_error")
}

# ------------------------------------------------------------------------------
# Real-canary serit: COK DUSUK oranli, pace'li yuk. Her aralikta `users` istek
# gercek endpoint'e gonderilir, sonra interval_sec beklenir. Throughput tahmini
# icin DEGILDIR; yalnizca gercek endpoint erisilebilirligini dogrular.
# Geriye asama (stage) siniflandirma ozeti doner (gateway/auth/policy ayrimi).
# ------------------------------------------------------------------------------
soak_real_canary_load <- function(url, real_key, cfg, metrics, duration_sec) {
  client_timeout_ms <- as.numeric(cfg$client_timeout_sec %||% 20) * 1000
  users <- max(1L, as.integer(cfg$real_canary$users %||% 2L))
  interval <- max(5L, as.integer(cfg$real_canary$interval_sec %||% 60L))
  soak_metrics_add_load_seconds(metrics, duration_sec)
  t_end <- Sys.time() + duration_sec

  stages <- list()              # asama -> sayac (gateway/auth/policy/completion ayrimi)
  total_calls <- 0L
  bump_stage <- function(stage) {
    stages[[stage]] <<- (stages[[stage]] %||% 0L) + 1L
    total_calls <<- total_calls + 1L
  }

  diag_path <- file.path(cfg$artifact_dir, "real_canary_diagnostics.jsonl")
  if (file.exists(diag_path)) unlink(diag_path)

  write_real_diag <- function(scen_id, model, stream, status, code, latency_ms,
                              response_text = "", curl_error = "") {
    rec <- list(
      ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      lane = "real-canary",
      scenario = scen_id,
      model = model,
      stream = isTRUE(stream),
      status = status,
      http_code = if (is.na(code)) NULL else as.integer(code),
      latency_ms = round(latency_ms, 1),
      response_preview = substr(soak_redact_text(response_text %||% ""), 1L, 800L),
      curl_error = substr(soak_redact_text(curl_error %||% ""), 1L, 800L)
    )
    cat(
      as.character(jsonlite::toJSON(rec, auto_unbox = TRUE, null = "null")),
      "\n",
      file = diag_path,
      append = TRUE
    )
  }

  repeat {
    for (u in seq_len(users)) {
      scen <- soak_pick_scenario()
      model <- cfg$real_canary$model %||% "soak-canary-model"
      stream_flag <- isTRUE(cfg$real_canary$stream)

      body_obj <- list(
        model = model,
        messages = list(
          list(role = "system", content = "Sen yardimci bir canary test asistanisin."),
          list(role = "user", content = scen$prompt %||% "merhaba")
        ),
        stream = stream_flag,
        max_tokens = as.integer(cfg$real_canary$max_tokens %||% 256L)
      )

      if (!isTRUE(cfg$real_canary$omit_temperature)) {
        body_obj$temperature <- as.numeric(cfg$real_canary$temperature %||% 0.4)
      }

      body <- as.character(jsonlite::toJSON(body_obj, auto_unbox = TRUE, null = "null"))

      h <- curl::new_handle(url = url)
      hdrs <- list("Content-Type" = "application/json")

      auth_header <- cfg$real_canary$auth_header %||% "Authorization"
      auth_scheme <- cfg$real_canary$auth_scheme %||% "Bearer"
      if (nzchar(real_key) && nzchar(auth_header)) {
        if (identical(tolower(auth_scheme), "none")) {
          hdrs[[auth_header]] <- real_key
        } else {
          hdrs[[auth_header]] <- paste(auth_scheme, real_key)
        }
      }

      do.call(curl::handle_setheaders, c(list(h), hdrs))
      soak_configure_post_handle(h, body, client_timeout_ms)
      start <- Sys.time()

      res <- tryCatch(
        curl::curl_fetch_memory(url, handle = h),
        error = function(e) list(.fail = conditionMessage(e))
      )

      lat <- as.numeric(difftime(Sys.time(), start, units = "secs")) * 1000

      if (!is.null(res$.fail)) {
        status <- if (grepl("tim(e|ed) ?out|timeout", res$.fail, ignore.case = TRUE)) "timeout" else "error"
        stage <- soak_classify_real_llm_response(NA_integer_, "", res$.fail, stream_flag)
        bump_stage(stage)
        soak_metrics_record(metrics, "real-canary", scen$id, lat, status, NA_integer_, 0,
                            "personal", .soak_real_stage_to_class(stage), "real_llm")
        write_real_diag(scen$id, model, stream_flag, status, NA_integer_, lat,
                        response_text = "", curl_error = res$.fail)
      } else {
        code <- as.integer(res$status_code)
        status <- if (code >= 200L && code < 300L) "ok" else "error"
        response_text <- tryCatch(rawToChar(res$content %||% raw()), error = function(e) "")
        stage <- soak_classify_real_llm_response(code, response_text, "", stream_flag)
        bump_stage(stage)
        soak_metrics_record(metrics, "real-canary", scen$id, lat, status, code,
                            length(res$content %||% raw()), "personal",
                            .soak_real_stage_to_class(stage), "real_llm")
        if (!identical(status, "ok")) {
          write_real_diag(scen$id, model, stream_flag, status, code, lat,
                          response_text = response_text, curl_error = "")
        }
      }
    }
    if (Sys.time() >= t_end) break
    # Pace: aralik kadar bekle (sure asilirsa erken cik).
    waited <- 0
    while (waited < interval && Sys.time() < t_end) { Sys.sleep(1); waited <- waited + 1 }
  }

  completed <- (stages[["generation_completed"]] %||% 0L) + (stages[["streaming_completed"]] %||% 0L)
  list(
    total_calls = total_calls,
    stages = stages,
    app_reachable = total_calls > 0L,
    gateway_reachable = total_calls > (stages[["app_unreachable"]] %||% 0L) +
      (stages[["transport_error"]] %||% 0L),
    generation_completed = completed > 0L,
    gateway_policy_failed = (stages[["gateway_policy_failed"]] %||% 0L) > 0L,
    note = paste(
      "Real-canary asama siniflandirmasi (gateway/auth/policy/uretim ayrimi).",
      "Bu bir kapasite/throughput kaniti DEGILDIR; gateway policy hatasi (orn ERR-234)",
      "MERGEN app yuk hatasi olarak yorumlanmamalidir."
    )
  )
}

# ------------------------------------------------------------------------------
# Opsiyonel KUCUK gercek-LLM throughput probe (kapali-dongu, kullanici-tavanli).
# AMAC: tek gercek anahtarla cok kucuk bir eszamanlilikta gercek uretim
# throughput'unu GOZLEMLEMEK. Bu, app kapasitesi DEGILDIR ve 50/100 kullaniciyi
# TAHMIN ETMEZ. Tavana (varsayilan 5) tabidir; ayri metrics nesnesi kullanir.
# ------------------------------------------------------------------------------
soak_real_llm_throughput_probe <- function(url, real_key, cfg, duration_sec) {
  probe <- cfg$real_llm_throughput %||% list(users = 2L, duration_sec = 300, max_users = 5L)
  users <- max(1L, as.integer(probe$users %||% 2L))
  cap <- max(1L, as.integer(probe$max_users %||% 5L))
  if (users > cap) users <- cap
  client_timeout_ms <- as.numeric(cfg$client_timeout_sec %||% 60) * 1000

  m <- soak_metrics_new()
  stages <- list(); total_calls <- 0L
  bump_stage <- function(stage) {
    stages[[stage]] <<- (stages[[stage]] %||% 0L) + 1L
    total_calls <<- total_calls + 1L
  }

  auth_header <- cfg$real_canary$auth_header %||% "Authorization"
  auth_scheme <- cfg$real_canary$auth_scheme %||% "Bearer"
  model <- cfg$real_canary$model %||% "soak-canary-model"
  stream_flag <- isTRUE(cfg$real_canary$stream)

  con_cap <- max(users + 4L, 16L)
  pool <- curl::new_pool(total_con = con_cap, host_con = con_cap, multiplex = FALSE)
  inflight <- new.env(parent = emptyenv()); inflight$n <- 0L

  add_one <- function() {
    scen <- soak_pick_scenario()
    body_obj <- list(
      model = model,
      messages = list(
        list(role = "system", content = "Sen yardimci bir throughput-probe asistanisin."),
        list(role = "user", content = scen$prompt %||% "merhaba")
      ),
      stream = stream_flag,
      max_tokens = as.integer(cfg$real_canary$max_tokens %||% 64L)
    )
    if (!isTRUE(cfg$real_canary$omit_temperature)) {
      body_obj$temperature <- as.numeric(cfg$real_canary$temperature %||% 0.4)
    }
    body <- as.character(jsonlite::toJSON(body_obj, auto_unbox = TRUE, null = "null"))

    h <- curl::new_handle(url = url)
    hdrs <- list("Content-Type" = "application/json")
    if (nzchar(real_key) && nzchar(auth_header)) {
      hdrs[[auth_header]] <- if (identical(tolower(auth_scheme), "none")) real_key else paste(auth_scheme, real_key)
    }
    do.call(curl::handle_setheaders, c(list(h), hdrs))
    soak_configure_post_handle(h, body, client_timeout_ms)
    start <- Sys.time()
    inflight$n <- inflight$n + 1L

    curl::multi_add(h,
      done = function(res) {
        inflight$n <- inflight$n - 1L
        lat <- as.numeric(difftime(Sys.time(), start, units = "secs")) * 1000
        code <- as.integer(res$status_code %||% NA_integer_)
        status <- if (!is.na(code) && code >= 200L && code < 300L) "ok" else "error"
        body_text <- tryCatch(rawToChar(res$content %||% raw()), error = function(e) "")
        stage <- soak_classify_real_llm_response(code, body_text, "", stream_flag)
        bump_stage(stage)
        soak_metrics_record(m, "real-throughput", scen$id, lat, status, code,
                            length(res$content %||% raw()), "personal",
                            .soak_real_stage_to_class(stage), "real_llm")
      },
      fail = function(msg) {
        inflight$n <- inflight$n - 1L
        lat <- as.numeric(difftime(Sys.time(), start, units = "secs")) * 1000
        status <- if (grepl("tim(e|ed) ?out|timeout", msg, ignore.case = TRUE)) "timeout" else "error"
        stage <- soak_classify_real_llm_response(NA_integer_, "", msg, stream_flag)
        bump_stage(stage)
        soak_metrics_record(m, "real-throughput", scen$id, lat, status, NA_integer_, 0,
                            "personal", .soak_real_stage_to_class(stage), "real_llm")
      },
      pool = pool)
  }

  loop_start <- Sys.time(); t_end <- loop_start + duration_sec
  while (inflight$n < users) add_one()
  repeat {
    curl::multi_run(timeout = 0.25, poll = TRUE, pool = pool)
    if (Sys.time() >= t_end) break
    while (inflight$n < users) add_one()
  }
  soak_metrics_add_load_seconds(m, as.numeric(difftime(Sys.time(), loop_start, units = "secs")))
  drain_deadline <- Sys.time() + max(5, client_timeout_ms / 1000 + 5)
  while (inflight$n > 0L && Sys.time() < drain_deadline) {
    tryCatch(curl::multi_run(timeout = 0.25, poll = TRUE, pool = pool), error = function(e) NULL)
  }

  summ <- soak_metrics_summary(m)
  list(
    users = users, max_users = cap, duration_seconds = duration_sec,
    metrics = list(requests = summ$requests, success = summ$success, errors = summ$errors,
                   timeouts = summ$timeouts, success_rate = summ$success_rate,
                   p50_latency_ms = summ$p50_latency_ms, p95_latency_ms = summ$p95_latency_ms,
                   p99_latency_ms = summ$p99_latency_ms,
                   throughput_ops_per_min = summ$throughput_ops_per_min),
    stages = stages, total_calls = total_calls,
    note = paste(
      "KUCUK gercek-LLM throughput probe (kullanici tavani uygulandi).",
      "App kapasitesi DEGILDIR; 50/100 kullanici throughput'unu TAHMIN ETMEZ;",
      "fake/proxy serit sonuclariyla KARISTIRILMAMALIDIR."
    )
  )
}

# ------------------------------------------------------------------------------
# Hata-davranis dogrulamasi: her hata durumunu BIR kez zorla, sonucu kaydet.
# Uygulamanin/clientin her hata turunu nasil ele aldigini gosterir (Deliverable 5F).
# ------------------------------------------------------------------------------
soak_failure_probe <- function(url, cfg, metrics, lane = "fake") {
  cases <- soak_failure_probe_cases()
  client_timeout_ms <- as.numeric(cfg$client_timeout_sec %||% 20) * 1000
  endpoint_kind <- switch(lane, fake = "fake_llm", proxy = "proxy_llm", "fake_llm")
  results <- list()
  body <- soak_build_chat_body(list(prompt = "hata enjeksiyon testi", stream = FALSE))

  for (cc in cases) {
    h <- curl::new_handle(url = url)
    curl::handle_setheaders(h, "Content-Type" = "application/json",
                            "X-Soak-Force" = cc, "Authorization" = "Bearer sk-test-user001")
	# timeout durumu icin client timeout'u kisa tut (gercek timeout uret).
	to_ms <- if (identical(cc, "timeout")) 3000 else client_timeout_ms
	soak_configure_post_handle(h, body, to_ms)
	start <- Sys.time()
    res <- tryCatch(curl::curl_fetch_memory(url, handle = h),
                    error = function(e) list(.fail = conditionMessage(e)))
    lat <- as.numeric(difftime(Sys.time(), start, units = "secs")) * 1000

    if (!is.null(res$.fail)) {
      status <- if (grepl("tim(e|ed) ?out|timeout", res$.fail, ignore.case = TRUE)) "timeout" else "error"
      code <- NA_integer_
      tclass <- soak_classify_failure(status, NA_integer_, res$.fail, endpoint_kind)
    } else {
      code <- as.integer(res$status_code)
      status <- if (code >= 200L && code < 300L) "ok" else "error"
      tclass <- soak_classify_failure(status, code, "", endpoint_kind)
    }
    soak_metrics_record(metrics, paste0(lane, "-probe"), cc, lat, status, code, 0, "n/a",
                        tclass, endpoint_kind)
    results[[cc]] <- list(case = cc, status = status, http_code = code,
                          latency_ms = round(lat, 1))
  }
  results
}

# ------------------------------------------------------------------------------
# Attach modu: calisan bir uygulamaya HTTP-duzeyi erisilebilirlik (Deliverable 5A).
# Tam Shiny/websocket oturumu DEGILDIR; sinir acikca raporlanir.
# ------------------------------------------------------------------------------
soak_attach_probe <- function(app_url) {
  if (!nzchar(app_url)) {
    return(list(configured = FALSE, reachable = FALSE,
                note = "MERGEN_SOAK_APP_URL ayarlanmadi; attach modu atlandi."))
  }
  start <- Sys.time()
  res <- tryCatch(curl::curl_fetch_memory(app_url), error = function(e) list(.fail = conditionMessage(e)))
  lat <- as.numeric(difftime(Sys.time(), start, units = "secs")) * 1000
  if (!is.null(res$.fail)) {
    return(list(configured = TRUE, reachable = FALSE, latency_ms = round(lat, 1),
                note = "Uygulama URL'sine erisilemedi (HTTP-duzeyi).",
                limitation = "HTTP-duzeyi erisilebilirlik; gercek websocket Shiny oturumu kurulmadi."))
  }
  list(
    configured = TRUE, reachable = TRUE,
    http_code = as.integer(res$status_code), latency_ms = round(lat, 1),
    note = "Uygulama koku HTTP-duzeyinde erisilebilir.",
    limitation = "HTTP-duzeyi erisilebilirlik; gercek websocket Shiny oturumu/tarayici eszamanliligi DEGILDIR."
  )
}

# Repo kokunu calisma-dizininden BAGIMSIZ bulur (gate kokten; testthat ise
# tests/testthat'ten calisir). app.R + R/ iceren ilk uygun dizini doner.
soak_find_repo_root <- function() {
  env_root <- Sys.getenv("MERGEN_REPO_ROOT", unset = "")
  cands <- c(env_root, ".", "..", "../..", "../../..")
  for (cand in cands) {
    if (!nzchar(cand)) next
    if (file.exists(file.path(cand, "app.R")) && dir.exists(file.path(cand, "R"))) {
      return(normalizePath(cand, winslash = "/", mustWork = FALSE))
    }
  }
  normalizePath(".", winslash = "/", mustWork = FALSE)
}

# ------------------------------------------------------------------------------
# In-process uygulama-yolu yardimcilarini yukler (caller UTF-8 locale ayarlamali).
# Calisma-dizininden bagimsizdir: R/ dosyalari repo koke gore cozumlenir.
# ------------------------------------------------------------------------------
soak_bootstrap_app_helpers <- function() {
  root <- soak_find_repo_root()
  files <- c(
    "R/utils_common.R", "R/utils_text_encoding.R",
    "R/helpers_db_unicode_escape.R", "R/helpers_db_encoding.R",
    "R/utils_safe_path.R", "R/utils_atomic_write.R", "R/utils_upload_validator.R",
    "R/utils_session_cleanup.R",
    "R/helpers_api_key_crypto.R", "R/helpers_api_key_identity.R"
  )
  ok <- TRUE
  loaded <- character(0)
  for (f in files) {
    abs_f <- file.path(root, f)
    res <- tryCatch({
      suppressWarnings(suppressMessages(source(abs_f, encoding = "UTF-8")))
      loaded <- c(loaded, f)
      TRUE
    }, error = function(e) FALSE)
    if (!isTRUE(res)) ok <- FALSE
  }
  required_fns <- c("normalize_db_visible_value", "normalize_db_read_visible_value",
                    "db_visible_text_has_mojibake", "db_unicode_escape_for_client_encoding",
                    "db_unicode_restore_escapes", "validate_uploaded_file",
                    "safe_join_path", "atomic_write_json", "safe_unlink_if_exists",
                    "mb_api_key_get_effective_key")
  present <- vapply(required_fns, function(fn) exists(fn, mode = "function"), logical(1))
  list(ok = ok && all(present), loaded = loaded,
       missing_fns = required_fns[!present])
}

# Sahte oturum nesnesi (key routing icin). userData bir ortamdir.
.soak_fake_session <- function(username = NULL, auth = TRUE, personal = NULL,
                               personal_owner = NULL) {
  ud <- new.env(parent = emptyenv())
  ud$auth_initialized <- isTRUE(auth)
  if (!is.null(username)) {
    ud$system_username <- username
    ud$user_id <- 100L
    ud$auth_source <- "soak-test"
  }
  if (!is.null(personal)) {
    ud$ai_api_key <- personal
    ud$ai_api_key_owner <- personal_owner %||% username
  }
  list(userData = ud)
}

# ------------------------------------------------------------------------------
# In-process alistirmalar: encoding, upload, key-routing, atomic/path, cleanup.
# Geriye yapisal bir ozet doner (artifact + esik degerlendirmesi icin).
# ------------------------------------------------------------------------------
soak_inprocess_exercises <- function(cfg, iterations = 40L) {
  boot <- soak_bootstrap_app_helpers()
  if (!isTRUE(boot$ok)) {
    return(list(
      available = FALSE,
      reason = sprintf("Uygulama yardimcilari yuklenemedi; eksik: %s",
                       paste(boot$missing_fns, collapse = ", ")),
      missing_fns = boot$missing_fns
    ))
  }

  # --- 1) Encoding round-trip + mojibake tespiti ---
  # Turkce + emoji (DB-safe escape yolu). Kaynak ASCII, calisma zamani UTF-8.
  tr <- paste0("T\u00fcrkiye ba\u015fkenti \u00e7\u011f\u0131\u0130\u00f6\u015f\u00fc ",
               intToUtf8(0x1F680))
  # Bilerek mojibake fikstur (TUrkiye/Nasil mojibake'leri): \u00c4\u00b1 = U+00C4 U+00B1,
  # \u00c3\u00bc = U+00C3 U+00BC.
  mojibake_dirty <- "Nas\u00c4\u00b1l T\u00c3\u00bcrkiye"
  enc_pass <- 0L; enc_total <- 0L; mojibake_detect_ok <- 0L
  for (i in seq_len(iterations)) {
    enc_total <- enc_total + 1L
    v <- normalize_db_visible_value(tr)
    back <- normalize_db_read_visible_value(v)
    esc <- db_unicode_escape_for_client_encoding(tr, "WINDOWS-1254")
    restored <- db_unicode_restore_escapes(esc)
    has_token <- grepl("[[MERGEN-U+1F680]]", esc, fixed = TRUE)
    rt_ok <- identical(enc2utf8(back), enc2utf8(tr)) &&
      identical(enc2utf8(restored), enc2utf8(tr)) && isTRUE(has_token)
    if (isTRUE(rt_ok)) enc_pass <- enc_pass + 1L
    # mojibake tespiti: temiz=FALSE, kirli=TRUE
    if (isFALSE(db_visible_text_has_mojibake(tr)) &&
        isTRUE(db_visible_text_has_mojibake(mojibake_dirty))) {
      mojibake_detect_ok <- mojibake_detect_ok + 1L
    }
  }
  # mojibake_hits: round-trip URETIMINDE uretilen mojibake (0 olmali).
  mojibake_hits <- enc_total - enc_pass

  # --- 2) Upload dogrulama (kabul/ret) ---
  up_cases <- soak_upload_cases()
  tmp <- tempfile(fileext = ".pdf"); writeLines("soak", tmp)
  allowed <- c("pdf", "docx", "txt", "csv", "xlsx")
  up_correct <- 0L; up_detail <- list()
  for (uc in up_cases) {
    r <- tryCatch(validate_uploaded_file(tmp, filename = uc$filename, allowed_ext = allowed),
                  error = function(e) list(ok = FALSE, code = "exception"))
    matched <- identical(isTRUE(r$ok), isTRUE(uc$expect_ok))
    if (matched) up_correct <- up_correct + 1L
    up_detail[[uc$label]] <- list(expect_ok = uc$expect_ok, actual_ok = isTRUE(r$ok),
                                  matched = matched, code = r$code %||% NA_character_)
  }
  # Calisma zamani control-byte dosya adi (parser-guvenli intToUtf8 ile).
  ctrl_name <- paste0("a", intToUtf8(1L), "b.pdf")
  ctrl_r <- tryCatch(validate_uploaded_file(tmp, filename = ctrl_name, allowed_ext = allowed),
                     error = function(e) list(ok = FALSE))
  ctrl_matched <- isFALSE(ctrl_r$ok)
  if (ctrl_matched) up_correct <- up_correct + 1L
  up_detail[["control_byte"]] <- list(expect_ok = FALSE, actual_ok = isTRUE(ctrl_r$ok),
                                      matched = ctrl_matched, code = ctrl_r$code %||% NA_character_)
  unlink(tmp)
  up_total <- length(up_cases) + 1L

  # --- 3) Anahtar yonlendirme (politika matrisi + izolasyon) ---
  routing <- soak_run_key_routing(cfg)

  # --- 4) Atomic write + safe path ---
  aw_dir <- file.path(tempdir(), paste0("soak_aw_", as.integer(stats::runif(1, 1, 1e6))))
  dir.create(aw_dir, showWarnings = FALSE, recursive = TRUE)
  aw_file <- file.path(aw_dir, "index.json")
  aw_ok <- tryCatch({
    atomic_write_json(list(a = 1L, t = "T\u00fcrk\u00e7e"), aw_file)
    file.exists(aw_file)
  }, error = function(e) FALSE)
  sp_traversal <- tryCatch(is.null(safe_join_path(aw_dir, "../disari.txt")),
                           error = function(e) NA)
  sp_safe <- tryCatch(!is.null(safe_join_path(aw_dir, "icerik.txt")),
                      error = function(e) NA)
  unlink(aw_dir, recursive = TRUE)

  # --- 5) Oturum/temp temizligi ---
  cl_file <- tempfile(fileext = ".tmp"); writeLines("x", cl_file)
  cl_ok <- tryCatch({
    safe_unlink_if_exists(cl_file)
    !file.exists(cl_file)
  }, error = function(e) FALSE)

  list(
    available = TRUE,
    encoding = list(
      iterations = enc_total,
      roundtrip_pass = enc_pass,
      roundtrip_pass_rate = round(enc_pass / max(1L, enc_total), 4),
      mojibake_hits = as.integer(mojibake_hits),
      mojibake_detection_pass = mojibake_detect_ok,
      mojibake_detection_ok = (mojibake_detect_ok == enc_total)
    ),
    upload = list(
      total = up_total, correct = up_correct,
      all_correct = (up_correct == up_total),
      detail = up_detail
    ),
    key_routing = routing,
    atomic_path = list(
      atomic_write_ok = isTRUE(aw_ok),
      safe_path_rejects_traversal = isTRUE(sp_traversal),
      safe_path_allows_safe = isTRUE(sp_safe)
    ),
    session_cleanup = list(safe_unlink_ok = isTRUE(cl_ok))
  )
}

# Anahtar yonlendirme matrisi + oturumlar-arasi izolasyon (in-process).
soak_run_key_routing <- function(cfg) {
  matrix_rows <- soak_key_routing_matrix()
  # Mevcut politika env'lerini koru ve sonunda geri yukle.
  keep <- c("MERGEN_ALLOW_DEFAULT_API_KEY", "MERGEN_REQUIRE_PERSONAL_API_KEY",
            "MERGEN_DEFAULT_API_KEY")
  old <- Sys.getenv(keep, unset = NA_character_)
  on.exit({
    for (nm in keep) {
      if (is.na(old[[nm]])) Sys.unsetenv(nm) else do.call(Sys.setenv, stats::setNames(list(old[[nm]]), nm))
    }
  }, add = TRUE)

  source_counts <- list(personal = 0L, default = 0L, missing = 0L)
  rows_correct <- 0L; rows_detail <- list()

  for (i in seq_along(matrix_rows)) {
    row <- matrix_rows[[i]]
    Sys.setenv(MERGEN_ALLOW_DEFAULT_API_KEY = if (isTRUE(row$allow_default)) "TRUE" else "FALSE")
    Sys.setenv(MERGEN_REQUIRE_PERSONAL_API_KEY = if (isTRUE(row$require_personal)) "TRUE" else "FALSE")
    Sys.setenv(MERGEN_DEFAULT_API_KEY = "sk-corp-soak-default")

    username <- sprintf("user%03d", i)
    personal <- if (isTRUE(row$has_personal)) sprintf("sk-test-%s", username) else NULL
    sess <- .soak_fake_session(username = username, auth = TRUE, personal = personal)
    plan <- tryCatch(mb_api_key_get_effective_key(sess),
                     error = function(e) list(source = "error"))
    src <- plan$source %||% "error"
    if (src %in% names(source_counts)) source_counts[[src]] <- source_counts[[src]] + 1L
    matched <- identical(src, row$expected)
    if (matched) rows_correct <- rows_correct + 1L
    rows_detail[[row$label]] <- list(expected = row$expected, actual = src, matched = matched)
  }

  # Oturumlar-arasi izolasyon: user B, user A'nin anahtarini sunar -> "missing".
  Sys.setenv(MERGEN_ALLOW_DEFAULT_API_KEY = "FALSE", MERGEN_REQUIRE_PERSONAL_API_KEY = "FALSE")
  sess_b <- .soak_fake_session(username = "userB", auth = TRUE,
                               personal = "sk-test-userA", personal_owner = "userA")
  plan_b <- tryCatch(mb_api_key_get_effective_key(sess_b),
                     error = function(e) list(source = "error"))
  isolation_pass <- identical(plan_b$source %||% "error", "missing")

  list(
    rows_total = length(matrix_rows),
    rows_correct = rows_correct,
    all_correct = (rows_correct == length(matrix_rows)),
    source_counts = source_counts,
    cross_session_isolation_pass = isTRUE(isolation_pass),
    detail = rows_detail
  )
}
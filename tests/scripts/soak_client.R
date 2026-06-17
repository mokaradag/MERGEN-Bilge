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
# Kapali-dongu eszamanli HTTP yuk surucusu (curl multi).
#   url           : POST hedefi (.../v1/chat/completions)
#   metrics       : soak_metrics_new() ortami
#   duration_sec  : sure
#   concurrent    : ayni anda en fazla ucusta istek (aktif eszamanlilik)
#   user_keys     : kullanici basina bearer anahtarlari
#   lane          : fake | proxy | real-canary
# ------------------------------------------------------------------------------
soak_http_load <- function(url, cfg, metrics, duration_sec, concurrent,
                           user_keys, lane, catalog = soak_scenario_catalog()) {
  n_users <- length(user_keys)
  model <- "soak-fake-model"
  client_timeout_ms <- as.numeric(cfg$client_timeout_sec %||% 20) * 1000
  app_http_mode <- !grepl("/v1/chat/completions/?$", url)

  # curl havuzu: host_con eszamanlilik kadar yuksek olmali (varsayilan 6 ise
  # serilesir). multiplex kapali tutulur (her istek ayri baglanti).
  con_cap <- max(as.integer(concurrent) + 10L, 100L)
  pool <- curl::new_pool(total_con = con_cap, host_con = con_cap, multiplex = FALSE)

  inflight <- new.env(parent = emptyenv())
  inflight$n <- 0L
  user_idx <- 0L

  add_one <- function() {
    user_idx <<- (user_idx %% n_users) + 1L
    key <- user_keys[[user_idx]]
    user_label <- sprintf("user%03d", user_idx)
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
    curl::handle_setopt(h, url = request_url)
	do.call(curl::handle_setheaders, c(list(h), hdrs))

	start <- Sys.time()
    scen_id <- if (isTRUE(app_http_mode)) paste0("app_http_", scen$id) else scen$id
    inflight$n <- inflight$n + 1L

    curl::multi_add(
      h,
      done = function(res) {
        inflight$n <- inflight$n - 1L
        lat <- as.numeric(difftime(Sys.time(), start, units = "secs")) * 1000
        code <- as.integer(res$status_code %||% NA_integer_)
        status <- if (!is.na(code) && code >= 200L && code < 300L) "ok" else "error"
        ks <- "n/a"
        if (identical(lane, "proxy")) {
          parsed <- tryCatch(curl::parse_headers_list(res$headers), error = function(e) list())
          ks <- parsed[["x-soak-key-source"]] %||% "n/a"
        }
        soak_metrics_record(metrics, lane, scen_id, lat, status, code,
                            length(res$content %||% raw()), ks)
      },
      fail = function(msg) {
        inflight$n <- inflight$n - 1L
        lat <- as.numeric(difftime(Sys.time(), start, units = "secs")) * 1000
        status <- if (grepl("tim(e|ed) ?out|timeout", msg, ignore.case = TRUE)) "timeout" else "error"
        soak_metrics_record(metrics, lane, scen_id, lat, status, NA_integer_, 0, "n/a")
      },
      pool = pool
    )
  }

  loop_start <- Sys.time()
  t_end <- loop_start + duration_sec
  while (inflight$n < concurrent) add_one()

  repeat {
    curl::multi_run(timeout = 0.25, poll = TRUE, pool = pool)
    if (Sys.time() >= t_end) break
    while (inflight$n < concurrent) add_one()
  }
  # Yuk-penceresi suresi (drain HARIC): throughput paydasi.
  soak_metrics_add_load_seconds(metrics, as.numeric(difftime(Sys.time(), loop_start, units = "secs")))

  # Kalan ucustaki istekleri bosalt. Bazi Windows/curl derlemelerinde tek
  # multi_run() cagrisi tum callback'leri teslim etmeyebilir; kapali donguyu
  # kisa ve sinirli bir drain penceresiyle surdurerek "0 istek olculdu" gibi
  # yalanci UNMEASURED sonucunu engelleriz.
  drain_deadline <- Sys.time() + max(5, client_timeout_ms / 1000 + 5)
  while (inflight$n > 0L && Sys.time() < drain_deadline) {
    tryCatch(curl::multi_run(timeout = 0.25, poll = TRUE, pool = pool),
             error = function(e) NULL)
  }
  invisible(metrics)
}

# ------------------------------------------------------------------------------
# Real-canary serit: COK DUSUK oranli, pace'li yuk. Her aralikta `users` istek
# gercek endpoint'e gonderilir, sonra interval_sec beklenir. Throughput tahmini
# icin DEGILDIR; yalnizca gercek endpoint erisilebilirligini dogrular.
# ------------------------------------------------------------------------------
soak_real_canary_load <- function(url, real_key, cfg, metrics, duration_sec) {
  client_timeout_ms <- as.numeric(cfg$client_timeout_sec %||% 20) * 1000
  users <- max(1L, as.integer(cfg$real_canary$users %||% 2L))
  interval <- max(5L, as.integer(cfg$real_canary$interval_sec %||% 60L))
  soak_metrics_add_load_seconds(metrics, duration_sec)
  t_end <- Sys.time() + duration_sec

  repeat {
    for (u in seq_len(users)) {
      scen <- soak_pick_scenario()
      body <- soak_build_chat_body(scen, model = "soak-canary-model")
      h <- curl::new_handle(url = url)
      hdrs <- list("Content-Type" = "application/json")
      if (nzchar(real_key)) hdrs[["Authorization"]] <- paste("Bearer", real_key)
	  do.call(curl::handle_setheaders, c(list(h), hdrs))
	  soak_configure_post_handle(h, body, client_timeout_ms)
	  start <- Sys.time()
      res <- tryCatch(curl::curl_fetch_memory(url, handle = h),
                      error = function(e) list(.fail = conditionMessage(e)))
      lat <- as.numeric(difftime(Sys.time(), start, units = "secs")) * 1000
      if (!is.null(res$.fail)) {
        status <- if (grepl("tim(e|ed) ?out|timeout", res$.fail, ignore.case = TRUE)) "timeout" else "error"
        soak_metrics_record(metrics, "real-canary", scen$id, lat, status, NA_integer_, 0, "personal")
      } else {
        code <- as.integer(res$status_code)
        status <- if (code >= 200L && code < 300L) "ok" else "error"
        soak_metrics_record(metrics, "real-canary", scen$id, lat, status, code,
                            length(res$content %||% raw()), "personal")
      }
    }
    if (Sys.time() >= t_end) break
    # Pace: aralik kadar bekle (sure asilirsa erken cik).
    waited <- 0
    while (waited < interval && Sys.time() < t_end) { Sys.sleep(1); waited <- waited + 1 }
  }
  invisible(metrics)
}

# ------------------------------------------------------------------------------
# Hata-davranis dogrulamasi: her hata durumunu BIR kez zorla, sonucu kaydet.
# Uygulamanin/clientin her hata turunu nasil ele aldigini gosterir (Deliverable 5F).
# ------------------------------------------------------------------------------
soak_failure_probe <- function(url, cfg, metrics, lane = "fake") {
  cases <- soak_failure_probe_cases()
  client_timeout_ms <- as.numeric(cfg$client_timeout_sec %||% 20) * 1000
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
    } else {
      code <- as.integer(res$status_code)
      status <- if (code >= 200L && code < 300L) "ok" else "error"
    }
    soak_metrics_record(metrics, paste0(lane, "-probe"), cc, lat, status, code, 0, "n/a")
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
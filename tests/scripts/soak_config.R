# ==============================================================================
# Dosya Yolu: tests/scripts/soak_config.R
# Aciklama:
#   Operasyonel soak gate icin profil + ortam-degiskeni yapilandirma cozumlemesi.
#   Tum env override'lari profil varsayilanlarini gecersiz kilar.
#
#   Profiller (MERGEN_SOAK_PROFILE): smoke, pilot, org, stress, fake_llm,
#   proxy_llm, real_llm. Varsayilan: smoke.
#
#   LLM seritleri (MERGEN_SOAK_LLM_MODE): fake, proxy, real-canary.
#
#   Bu dosya BILEREK ASCII-guvenlidir (Turkce ozel karakter yok).
# ==============================================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || is.na(x[1])) y else x

soak_env_str <- function(name, default = "") {
  v <- trimws(Sys.getenv(name, unset = ""))
  if (!nzchar(v)) return(default)

  first <- substr(v, 1L, 1L)
  if (first %in% c("'", "\"")) {
    chars <- strsplit(v, "", fixed = TRUE)[[1]]
    close <- which(chars == first & seq_along(chars) > 1L)
    if (length(close) > 0L) {
      v <- paste(chars[seq.int(2L, close[1L] - 1L)], collapse = "")
    }
  } else {
    v <- sub("[[:space:]]+#.*$", "", v)
  }

  v <- trimws(v)
  if (nzchar(v)) v else default
}

soak_env_flag <- function(name, default = FALSE) {
  raw <- tolower(trimws(Sys.getenv(name, unset = "")))
  if (!nzchar(raw)) return(isTRUE(default))
  if (raw %in% c("true", "t", "1", "yes", "y", "on", "evet")) return(TRUE)
  if (raw %in% c("false", "f", "0", "no", "n", "off", "hayir")) return(FALSE)
  isTRUE(default)
}

soak_env_int <- function(name, default) {
  raw <- trimws(Sys.getenv(name, unset = ""))
  if (!nzchar(raw)) return(as.integer(default))
  val <- suppressWarnings(as.integer(raw))
  if (is.na(val)) as.integer(default) else val
}

soak_env_num <- function(name, default) {
  raw <- trimws(Sys.getenv(name, unset = ""))
  if (!nzchar(raw)) return(as.numeric(default))
  val <- suppressWarnings(as.numeric(raw))
  if (is.na(val)) as.numeric(default) else val
}

# Yuk surucusu arrival deseni etiketini turetir (SAF, deterministik). Bu, kanit
# ve config.json icinde kosumun "ani burst" mi, "rampali" mi yoksa "think'li
# pace'li" mi oldugunu acikca raporlar. Hicbir esigi etkilemez; yalniz tanidir.
#   burst        : ramp yok + think yok (mevcut varsayilan davranis).
#   ramped       : ramp_up_seconds > 0, think yok.
#   paced        : think_time > 0, ramp yok.
#   ramped_paced : hem ramp hem think aktif.
soak_load_pattern_label <- function(ramp_up_seconds, think_ms_min, think_ms_max) {
  ramp_on <- is.finite(ramp_up_seconds) && ramp_up_seconds > 0
  think_on <- (is.finite(think_ms_min) && think_ms_min > 0) ||
    (is.finite(think_ms_max) && think_ms_max > 0)
  if (ramp_on && think_on) return("ramped_paced")
  if (ramp_on) return("ramped")
  if (think_on) return("paced")
  "burst"
}

# Profil -> taban yogunluk + serit varsayilanlari. Bu sadece TABAN; env
# override'lari her zaman kazanir.
soak_profile_defaults <- function(profile) {
  switch(
    profile,
    smoke = list(
      users = 3L, minutes = 5, lane = "fake",
      capacity = FALSE, intent = "Gelistirici makinesi icin guvenli hizli duman testi."
    ),
    pilot = list(
      users = 15L, minutes = 30, lane = "fake",
      capacity = FALSE, intent = "Kucuk pilot yuk; fake LLM."
    ),
    org = list(
      users = 100L, minutes = 120, lane = "fake",
      capacity = TRUE, intent = "Kurum-olcegi aktif kullanici hedefi; fake LLM."
    ),
    stress = list(
      users = 150L, minutes = 10, lane = "fake",
      capacity = TRUE, intent = "Kapasite kesfi; varsayilan DEGIL."
    ),
    fake_llm = list(
      users = 15L, minutes = 15, lane = "fake",
      capacity = FALSE, intent = "Acik fake endpoint serit modu."
    ),
    proxy_llm = list(
      users = 15L, minutes = 15, lane = "proxy",
      capacity = FALSE, intent = "Sahte kisisel-anahtar/proxy serit modu."
    ),
    real_llm = list(
      users = 2L, minutes = 5, lane = "real-canary",
      capacity = FALSE, intent = "Gercek endpoint canary; cok dusuk eszamanlilik."
    ),
    # Bilinmeyen profil -> smoke gibi davran.
    list(users = 3L, minutes = 5, lane = "fake", capacity = FALSE,
         intent = "Bilinmeyen profil; smoke varsayilanlari.")
  )
}

soak_valid_profiles <- function() {
  c("smoke", "pilot", "org", "stress", "fake_llm", "proxy_llm", "real_llm")
}

soak_valid_lanes <- function() c("fake", "proxy", "real-canary")

# Stress profili icin kapasite egrisi adimlari (kullanici sayilari).
soak_default_capacity_curve <- function() {
  raw <- soak_env_str("MERGEN_SOAK_CAPACITY_USERS", "")
  if (nzchar(raw)) {
    parts <- suppressWarnings(as.integer(trimws(strsplit(raw, ",", fixed = TRUE)[[1]])))
    parts <- parts[!is.na(parts) & parts > 0L]
    if (length(parts) > 0L) return(parts)
  }
  c(10L, 25L, 50L, 100L)
}

# Kademeli kapasite merdiveni (capacity ladder) adimlari. Ayni MERGEN_SOAK_CAPACITY_USERS
# env'ini okur (operator hangi mod aktifse onu ayarlar); ayarli degilse 1000'e kadar
# kademeli varsayilan kullanir (50 -> 100 -> ... -> 1000). Boylece dogrudan 1000'e
# atlamak yerine son STABIL adim durustce belirlenebilir.
soak_default_capacity_ladder <- function() {
  raw <- soak_env_str("MERGEN_SOAK_CAPACITY_USERS", "")
  if (nzchar(raw)) {
    parts <- suppressWarnings(as.integer(trimws(strsplit(raw, ",", fixed = TRUE)[[1]])))
    parts <- parts[!is.na(parts) & parts > 0L]
    if (length(parts) > 0L) return(parts)
  }
  c(50L, 100L, 150L, 250L, 500L, 750L, 1000L)
}

# Tum yapilandirmayi cozumler ve tek bir liste doner.
soak_resolve_config <- function() {
  profile <- tolower(soak_env_str("MERGEN_SOAK_PROFILE", "smoke"))
  if (!profile %in% soak_valid_profiles()) {
    warning(sprintf(
      "Bilinmeyen MERGEN_SOAK_PROFILE='%s'; 'smoke' kullaniliyor.", profile
    ), call. = FALSE)
    profile <- "smoke"
  }

  defaults <- soak_profile_defaults(profile)

  # Serit: env override > profil varsayilani.
  lane <- tolower(soak_env_str("MERGEN_SOAK_LLM_MODE", defaults$lane))
  if (!lane %in% soak_valid_lanes()) {
    warning(sprintf("Bilinmeyen MERGEN_SOAK_LLM_MODE='%s'; '%s' kullaniliyor.",
                    lane, defaults$lane), call. = FALSE)
    lane <- defaults$lane
  }

  users <- soak_env_int("MERGEN_SOAK_CONCURRENT_USERS", defaults$users)
  if (users < 1L) users <- 1L

  minutes <- soak_env_num("MERGEN_SOAK_DURATION_MINUTES", defaults$minutes)
  if (minutes <= 0) minutes <- defaults$minutes
  duration_sec <- as.numeric(minutes) * 60

  # Hizli kendi-dogrulama icin saniye-bazli override (testler ve smoke icin).
  # MERGEN_SOAK_DURATION_SECONDS verilirse dakika hesabini gecersiz kilar.
  dur_sec_override <- soak_env_int("MERGEN_SOAK_DURATION_SECONDS", -1L)
  if (dur_sec_override > 0L) {
    duration_sec <- as.numeric(dur_sec_override)
  }

  # Real-canary serit: emniyet icin kullanici/sure tavanlari uygulanir.
  real_canary_users <- soak_env_int("MERGEN_SOAK_REAL_CANARY_USERS", 2L)
  real_canary_interval <- soak_env_int("MERGEN_SOAK_REAL_CANARY_INTERVAL_SECONDS", 60L)
  real_canary_model <- soak_env_str("MERGEN_SOAK_REAL_MODEL", "soak-canary-model")

  # Real endpoint compatibility knobs. Defaults are conservative for canary:
  # non-streaming, small output, normal Bearer auth.
  real_canary_stream <- soak_env_flag("MERGEN_SOAK_REAL_STREAM", FALSE)
  real_canary_max_tokens <- soak_env_int("MERGEN_SOAK_REAL_MAX_TOKENS", 256L)
  real_canary_temperature <- soak_env_num("MERGEN_SOAK_REAL_TEMPERATURE", 0.4)
  real_canary_omit_temperature <- soak_env_flag("MERGEN_SOAK_REAL_OMIT_TEMPERATURE", FALSE)
  real_canary_auth_header <- soak_env_str("MERGEN_SOAK_REAL_AUTH_HEADER", "Authorization")
  real_canary_auth_scheme <- soak_env_str("MERGEN_SOAK_REAL_AUTH_SCHEME", "Bearer")

  if (identical(lane, "real-canary")) {
    cap <- soak_env_int("MERGEN_SOAK_REAL_CANARY_MAX_USERS", 5L)
    if (users > cap) users <- cap
    if (real_canary_users > cap) real_canary_users <- cap
    users <- real_canary_users
  }

  thresholds <- soak_resolve_thresholds(profile)

  # Fake endpoint davranis parametreleri.
  fake <- list(
    latency_ms_min = soak_env_int("MERGEN_SOAK_FAKE_LATENCY_MS_MIN", 80L),
    latency_ms_max = soak_env_int("MERGEN_SOAK_FAKE_LATENCY_MS_MAX", 600L),
    error_rate = soak_env_num("MERGEN_SOAK_FAKE_ERROR_RATE", 0.02),
    timeout_rate = soak_env_num("MERGEN_SOAK_FAKE_TIMEOUT_RATE", 0.01),
    stream = soak_env_flag("MERGEN_SOAK_FAKE_STREAM", TRUE),
    long_response_rate = soak_env_num("MERGEN_SOAK_FAKE_LONG_RESPONSE_RATE", 0.05),
    stream_chunks = soak_env_int("MERGEN_SOAK_FAKE_STREAM_CHUNKS", 12L)
  )

  # Proxy serit parametreleri.
  proxy <- list(
    forward_real = soak_env_flag("MERGEN_SOAK_PROXY_FORWARD_REAL", FALSE),
    max_real_rpm = soak_env_int("MERGEN_SOAK_MAX_REAL_LLM_RPM", 3L),
    real_endpoint = soak_env_str("MERGEN_SOAK_REAL_ENDPOINT_URL", ""),
    real_key_present = nzchar(soak_env_str("MERGEN_SOAK_REAL_API_KEY", ""))
  )

  app_url <- soak_env_str("MERGEN_SOAK_APP_URL", "")

  in_process <- soak_env_flag("MERGEN_SOAK_IN_PROCESS_EXERCISES", TRUE)

  # Etkilesimli (interactive) serit: in-process sohbet-benzeri oturumlar; gercek
  # DB havuzu/islem/encoding/streaming-karar/dosya/anahtar yollarini calistirir.
  # Tek-surecte ardisik oldugu icin oturum sayisi makul bir varsayilanla sinirlidir;
  # env ile override edilebilir.
  interactive_lane <- soak_env_flag("MERGEN_SOAK_INTERACTIVE_LANE", TRUE)
  interactive_users_default <- min(max(users, 8L), 50L)
  interactive_users <- soak_env_int("MERGEN_SOAK_INTERACTIVE_USERS", interactive_users_default)
  if (interactive_users < 1L) interactive_users <- 1L
  interactive_iterations <- soak_env_int("MERGEN_SOAK_INTERACTIVE_ITERATIONS", 1L)
  if (interactive_iterations < 1L) interactive_iterations <- 1L

  # HTTP yuk seridi: calisan bir uygulama (MERGEN_SOAK_APP_URL) gerektirir.
  # Varsayilan ACIK (mevcut davranis). KAPALI yapildiginda gate yalnizca
  # in-process + etkilesimli seritleri calistirir (bulut/uygulamasiz kanit).
  http_lane <- soak_env_flag("MERGEN_SOAK_HTTP_LANE", TRUE)

  # Per-istek client timeout (saniye). Fake timeout enjeksiyonunu test edebilmek
  # icin kisa tutulur.
  client_timeout_sec <- soak_env_int("MERGEN_SOAK_CLIENT_TIMEOUT_SECONDS", 20L)

  # --- Yuk surucusu (load driver) realizm anahtarlari ---------------------------
  # Bu anahtarlarin TUMU VARSAYILANI MEVCUT DAVRANISI KORUR (burst, ramp yok,
  # think yok, baglanti yeniden-kullanim acik). Boylece bu degisiklik gecmis kapi
  # pass/fail anlamini SESSIZCE DEGISTIRMEZ. Operator, bir sonraki VM kosumunda
  # baglanti-timeout doygunlugunun "ani baglanti firtinasi" mi yoksa "kararli-durum
  # doygunlugu" mu oldugunu ayirt etmek icin rampa/think ekleyebilir.
  #   ramp_up_seconds : aktif eszamanliligi 1 -> concurrent'a bu sure boyunca
  #                     dogrusal buyutur (0 = ani burst, mevcut davranis).
  #   max_new_per_tick: her multi_run dongusunde acilan YENI istek sayisi tavani
  #                     (0 = sinirsiz, mevcut davranis).
  #   think_time_ms   : tamamlanan bir istek ile ayni "kullanicinin" sonraki
  #                     istegi arasindaki jitter'li bekleme (0 = think yok).
  #   connection_reuse: TRUE ise libcurl havuzu baglantilari yeniden kullanir
  #                     (mevcut davranis); FALSE her istegi yeni baglantiya zorlar.
  ramp_up_seconds <- soak_env_num("MERGEN_SOAK_RAMP_UP_SECONDS", 0)
  if (!is.finite(ramp_up_seconds) || ramp_up_seconds < 0) ramp_up_seconds <- 0
  max_new_per_tick <- soak_env_int("MERGEN_SOAK_MAX_NEW_PER_TICK", 0L)
  if (is.na(max_new_per_tick) || max_new_per_tick < 0L) max_new_per_tick <- 0L
  think_time_ms_min <- soak_env_int("MERGEN_SOAK_THINK_TIME_MS_MIN", 0L)
  if (is.na(think_time_ms_min) || think_time_ms_min < 0L) think_time_ms_min <- 0L
  think_time_ms_max <- soak_env_int("MERGEN_SOAK_THINK_TIME_MS_MAX", think_time_ms_min)
  if (is.na(think_time_ms_max) || think_time_ms_max < think_time_ms_min) {
    think_time_ms_max <- think_time_ms_min
  }
  connection_reuse <- soak_env_flag("MERGEN_SOAK_CONNECTION_REUSE", TRUE)
  load_pattern <- soak_load_pattern_label(ramp_up_seconds, think_time_ms_min, think_time_ms_max)

  capacity_enabled <- soak_env_flag(
    "MERGEN_SOAK_CAPACITY_CURVE",
    isTRUE(defaults$capacity)
  )

  # Kademeli kapasite merdiveni (staged capacity ladder): dogrudan 1000'e atlamadan
  # 50 -> 100 -> 250 -> 500 -> 1000 gibi adimlarla son STABIL kapasiteyi olcer.
  capacity_ladder_enabled <- soak_env_flag("MERGEN_SOAK_CAPACITY_LADDER", FALSE)
  capacity_ladder_users <- soak_default_capacity_ladder()
  capacity_ladder_step_seconds <- soak_env_int("MERGEN_SOAK_CAPACITY_STEP_SECONDS", 600L)
  stop_on_first_failed_step <- soak_env_flag("MERGEN_SOAK_STOP_ON_FIRST_FAILED_STEP", TRUE)
  stable_success_rate_min <- soak_env_num("MERGEN_SOAK_STABLE_SUCCESS_RATE_MIN", 0.98)

  # Sistem telemetrisi (opsiyonel; CPU/bellek/TCP ornekleme). Varsayilan ACIK,
  # ama OS sayaclari okunamazsa soak'u KIRMAZ (UNMEASURED olarak raporlanir).
  telemetry_enabled <- soak_env_flag("MERGEN_SOAK_TELEMETRY_ENABLED", TRUE)
  telemetry_interval_sec <- max(1L, soak_env_int("MERGEN_SOAK_TELEMETRY_INTERVAL_SECONDS", 5L))

  # Opsiyonel KUCUK gercek-LLM throughput probe (kullanici tavanli; app kapasitesi
  # DEGIL). Yalniz acikca etkinlestirildiginde calisir.
  real_llm_throughput_enabled <- soak_env_flag("MERGEN_REAL_LLM_THROUGHPUT_PROBE", FALSE)
  real_llm_throughput_users <- soak_env_int("MERGEN_REAL_LLM_THROUGHPUT_USERS", 2L)
  real_llm_throughput_max_users <- soak_env_int("MERGEN_REAL_LLM_THROUGHPUT_MAX_USERS", 5L)
  real_llm_throughput_duration <- soak_env_int("MERGEN_REAL_LLM_THROUGHPUT_DURATION_SECONDS", 300L)
  if (real_llm_throughput_users > real_llm_throughput_max_users) {
    real_llm_throughput_users <- real_llm_throughput_max_users
  }

  gate_timestamp <- format(Sys.time(), "%Y%m%d-%H%M%S", tz = "UTC")
  artifact_dir <- file.path("artifacts", "soak", gate_timestamp)

  list(
    profile = profile,
    profile_intent = defaults$intent,
    llm_lane = lane,
    mocked_llm = identical(lane, "fake"),
    proxied_llm = identical(lane, "proxy"),
    real_llm = identical(lane, "real-canary"),
    user_base_target = soak_env_int("MERGEN_SOAK_USER_BASE_TARGET", 1000L),
    concurrent_users = users,
    duration_sec = duration_sec,
    assumed_concurrency_model = paste(
      "Kapali-dongu (closed-loop): her an en fazla N=concurrent_users",
      "ayni anda ucusta olan istek tutulur; tamamlandikca yeniden doldurulur.",
      "Bu AKTIF eszamanlilik modelidir, kullanici tabani DEGIL."
    ),
    client_timeout_sec = client_timeout_sec,
    load_driver = list(
      pattern = load_pattern,
      ramp_up_seconds = ramp_up_seconds,
      max_new_requests_per_tick = max_new_per_tick,
      think_time_ms_min = think_time_ms_min,
      think_time_ms_max = think_time_ms_max,
      connection_reuse = connection_reuse
    ),
    fake = fake,
    proxy = proxy,
    real_canary = list(
      users = real_canary_users,
      interval_sec = real_canary_interval,
      model = real_canary_model,
      stream = real_canary_stream,
      max_tokens = real_canary_max_tokens,
      temperature = real_canary_temperature,
      omit_temperature = real_canary_omit_temperature,
      auth_header = real_canary_auth_header,
      auth_scheme = real_canary_auth_scheme
    ),
    app_url = app_url,
    in_process_exercises = in_process,
    http_lane = http_lane,
    interactive_lane = interactive_lane,
    interactive_users = interactive_users,
    interactive_iterations = interactive_iterations,
    capacity_curve_enabled = capacity_enabled,
    capacity_curve_users = soak_default_capacity_curve(),
    capacity_step_seconds = soak_env_int("MERGEN_SOAK_CAPACITY_STEP_SECONDS", 30L),
    capacity_ladder_enabled = capacity_ladder_enabled,
    capacity_ladder_users = capacity_ladder_users,
    capacity_ladder_step_seconds = capacity_ladder_step_seconds,
    stop_on_first_failed_step = stop_on_first_failed_step,
    stable_success_rate_min = stable_success_rate_min,
    telemetry_enabled = telemetry_enabled,
    telemetry_interval_sec = telemetry_interval_sec,
    real_llm_throughput_enabled = real_llm_throughput_enabled,
    real_llm_throughput = list(
      users = real_llm_throughput_users,
      max_users = real_llm_throughput_max_users,
      duration_sec = real_llm_throughput_duration
    ),
    thresholds = thresholds,
    artifact_dir = artifact_dir,
    gate_timestamp = gate_timestamp,
    server_host = soak_env_str("MERGEN_SOAK_SERVER_HOST", "127.0.0.1"),
    server_port = soak_env_int("MERGEN_SOAK_SERVER_PORT", 0L)
  )
}

# Esik degerleri: olcum guvenilir degilse "unmeasured" olarak isaretlenir.
soak_resolve_thresholds <- function(profile) {
  # Profil bazli varsayilan basari orani.
  success_default <- if (profile %in% c("smoke", "stress")) 0.95 else 0.98

  list(
    success_rate_min = soak_env_num("MERGEN_SOAK_SUCCESS_RATE_MIN", success_default),
    p95_latency_ms_max = soak_env_int("MERGEN_SOAK_P95_LATENCY_MS_MAX", 0L), # 0 => olcum raporlanir, esik uygulanmaz
    memory_growth_mb_max = soak_env_num("MERGEN_SOAK_MEMORY_GROWTH_MB_MAX", -1), # <0 => olcum raporlanir, esik uygulanmaz
    temp_growth_mb_max = soak_env_num("MERGEN_SOAK_TEMP_GROWTH_MB_MAX", -1),
    fail_on_browser_console_errors = soak_env_flag("MERGEN_SOAK_FAIL_ON_BROWSER_CONSOLE_ERRORS", FALSE),
    fail_on_mojibake = soak_env_flag("MERGEN_SOAK_FAIL_ON_MOJIBAKE", TRUE),
    fail_on_secret_leak = soak_env_flag("MERGEN_SOAK_FAIL_ON_SECRET_LEAK", TRUE),
    # Etkilesimli seritte DB havuz baglanti sizintisi (checkout != return) ve
    # oturumlar-arasi kontaminasyon varsayilan olarak FAIL'dir.
    fail_on_interactive_db_leak = soak_env_flag("MERGEN_SOAK_FAIL_ON_INTERACTIVE_DB_LEAK", TRUE),
    # Etkilesimli serit ISTENDI ama calismadiysa (paket/bootstrap eksik) bu PR'nin
    # ekledigi DB-havuz/islem/izolasyon kapsami kaybedilir; varsayilan olarak FAIL.
    # Havuz paketleri olmayan minimal ortamlar bunu FALSE yapabilir veya
    # MERGEN_SOAK_INTERACTIVE_LANE=false ile seridi hic istemeyebilir.
    fail_on_interactive_unavailable = soak_env_flag("MERGEN_SOAK_FAIL_ON_INTERACTIVE_UNAVAILABLE", TRUE)
  )
}

# config.json artifact'i icin secret-guvenli yapilandirma kopyasi. Ham
# endpoint/key degerleri ICERMEZ; yalnizca davranis parametreleri ve varlik
# bayraklari tutulur.
soak_config_public <- function(cfg) {
  list(
    profile = cfg$profile,
    profile_intent = cfg$profile_intent,
    llm_lane = cfg$llm_lane,
    mocked_llm = cfg$mocked_llm,
    proxied_llm = cfg$proxied_llm,
    real_llm = cfg$real_llm,
    user_base_target = cfg$user_base_target,
    concurrent_users = cfg$concurrent_users,
    duration_seconds = cfg$duration_sec,
    assumed_concurrency_model = cfg$assumed_concurrency_model,
    client_timeout_seconds = cfg$client_timeout_sec,
    load_driver = cfg$load_driver,
    fake_behavior = cfg$fake,
    proxy_behavior = list(
      forward_real = cfg$proxy$forward_real,
      max_real_rpm = cfg$proxy$max_real_rpm,
      real_endpoint_configured = nzchar(cfg$proxy$real_endpoint),
      real_key_present = cfg$proxy$real_key_present
    ),
    real_canary = cfg$real_canary,
    app_url_configured = nzchar(cfg$app_url),
    in_process_exercises = cfg$in_process_exercises,
    http_lane = cfg$http_lane,
    interactive_lane = cfg$interactive_lane,
    interactive_users = cfg$interactive_users,
    interactive_iterations = cfg$interactive_iterations,
    capacity_curve_enabled = cfg$capacity_curve_enabled,
    capacity_curve_users = cfg$capacity_curve_users,
    capacity_ladder_enabled = cfg$capacity_ladder_enabled,
    capacity_ladder_users = cfg$capacity_ladder_users,
    capacity_ladder_step_seconds = cfg$capacity_ladder_step_seconds,
    stop_on_first_failed_step = cfg$stop_on_first_failed_step,
    stable_success_rate_min = cfg$stable_success_rate_min,
    telemetry_enabled = cfg$telemetry_enabled,
    telemetry_interval_sec = cfg$telemetry_interval_sec,
    real_llm_throughput_enabled = cfg$real_llm_throughput_enabled,
    real_llm_throughput = cfg$real_llm_throughput,
    thresholds = cfg$thresholds
  )
}
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

  # Per-istek client timeout (saniye). Fake timeout enjeksiyonunu test edebilmek
  # icin kisa tutulur.
  client_timeout_sec <- soak_env_int("MERGEN_SOAK_CLIENT_TIMEOUT_SECONDS", 20L)

  capacity_enabled <- soak_env_flag(
    "MERGEN_SOAK_CAPACITY_CURVE",
    isTRUE(defaults$capacity)
  )

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
    fake = fake,
    proxy = proxy,
    real_canary = list(users = real_canary_users, interval_sec = real_canary_interval),
    app_url = app_url,
    in_process_exercises = in_process,
    capacity_curve_enabled = capacity_enabled,
    capacity_curve_users = soak_default_capacity_curve(),
    capacity_step_seconds = soak_env_int("MERGEN_SOAK_CAPACITY_STEP_SECONDS", 30L),
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
    fail_on_secret_leak = soak_env_flag("MERGEN_SOAK_FAIL_ON_SECRET_LEAK", TRUE)
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
    capacity_curve_enabled = cfg$capacity_curve_enabled,
    capacity_curve_users = cfg$capacity_curve_users,
    thresholds = cfg$thresholds
  )
}

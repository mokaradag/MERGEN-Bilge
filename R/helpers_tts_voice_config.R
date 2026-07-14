# ==============================================================================
# Dosya Yolu: R/helpers_tts_voice_config.R
# Açıklama:   VoxCPM2 referans-ses profili TTS yapılandırma yardımcıları.
#             Merkezi TTS yapılandırmasını (tts_config) güvenli çevre değişkeni
#             ayrıştırmasıyla üretir ve persona -> ses profili çözümlemesini
#             tek noktada toplar.
#
#             config_api.R bu dosyayı source-time'da çağırdığı için manifestte
#             config_api.R'den ÖNCE yüklenir. Saf ayrıştırma yardımcıları
#             (Shiny/DB/ağ yan etkisi yoktur); profil çözümleyici persona
#             kaydını okumak için get_character_record()'a güvenir.
# ==============================================================================

# İzole test/worker bağlamında güvenli olması için yerel %||% köprüsü.
if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
}

# Çevre değişkenini güvenli tek değer (scalar) olarak okur. Ayarlanmamış VEYA boş
# değer güvenli varsayılana düşer (üretim varsayılanları amaçlanan yedeği kodlar).
.mergen_tts_env_scalar <- function(name, default = "") {
  value <- tryCatch(Sys.getenv(name, unset = default), error = function(e) default)
  if (length(value) == 0L || is.na(value[[1]])) return(default)
  value <- trimws(as.character(value[[1]]))
  if (!nzchar(value)) return(default)
  value
}

# Serbest biçimli değeri mantıksal (bool) değere çevirir; geçersizse varsayılan.
.mergen_tts_parse_bool <- function(value, default = FALSE) {
  value <- tolower(trimws(as.character(value %||% "")[1]))
  if (is.na(value) || !nzchar(value)) return(default)
  if (value %in% c("true", "t", "1", "yes", "y", "evet", "acik", "açık", "on")) return(TRUE)
  if (value %in% c("false", "f", "0", "no", "n", "hayir", "hayır", "kapali", "kapalı", "off")) return(FALSE)
  default
}

# Serbest biçimli değeri sayıya çevirir; geçersiz veya sınır dışıysa varsayılan.
.mergen_tts_parse_num <- function(value, default, min_value = NULL, max_value = NULL) {
  num <- suppressWarnings(as.numeric(trimws(as.character(value %||% "")[1])))
  if (length(num) == 0L || is.na(num)) return(default)
  if (!is.null(min_value) && num < min_value) return(default)
  if (!is.null(max_value) && num > max_value) return(default)
  num
}

# Modelin VoxCPM2 (referans-ses klonlama) ailesinden olup olmadığını belirler.
mergen_tts_model_is_voxcpm <- function(model) {
  model <- tolower(trimws(as.character(model %||% "")[1]))
  if (is.na(model) || !nzchar(model)) return(FALSE)
  grepl("voxcpm", model, fixed = TRUE)
}

#' Merkezi TTS Yapılandırmasını Üret
#'
#' @description LOCAL_TTS_* çevre değişkenlerini güvenli varsayılanlarla okuyup
#'   tts_config global nesnesinin içeriğini döndürür. Eksik/bozuk değerler
#'   güvenli varsayılana düşer. Kişisel/kurum API anahtarı çözümlemesi bu
#'   fonksiyonda YAPILMAZ (o sınır helpers_feature_api_key.R'dedir).
#' @return TTS yapılandırma listesi
mergen_build_tts_config <- function() {
  list(
    base_url        = .mergen_tts_env_scalar("LOCAL_TTS_ENDPOINT", ""),
    api_key         = .mergen_tts_env_scalar("LOCAL_TTS_API_KEY", ""),
    model           = .mergen_tts_env_scalar("LOCAL_TTS_MODEL", "tts-1-hd"),
    default_voice   = .mergen_tts_env_scalar("LOCAL_TTS_VOICE", "default"),
    timeout_seconds = .mergen_tts_parse_num(.mergen_tts_env_scalar("LOCAL_TTS_TIMEOUT", "90"), 90, min_value = 1),
    verify_ssl      = .mergen_tts_parse_bool(.mergen_tts_env_scalar("LOCAL_TTS_VERIFY_SSL", "TRUE"), default = TRUE),

    # --- VoxCPM2 referans-ses profili ayarları ---
    profiles_enabled = .mergen_tts_parse_bool(.mergen_tts_env_scalar("LOCAL_TTS_PROFILES_ENABLED", "TRUE"), default = TRUE),
    voice_dir        = .mergen_tts_env_scalar("LOCAL_TTS_VOICE_DIR", ""),
    speed            = .mergen_tts_parse_num(.mergen_tts_env_scalar("LOCAL_TTS_SPEED", "1.0"), 1.0, min_value = 0.25, max_value = 4.0),
    response_format  = tolower(.mergen_tts_env_scalar("LOCAL_TTS_RESPONSE_FORMAT", "wav")),
    use_ref_text     = .mergen_tts_parse_bool(.mergen_tts_env_scalar("LOCAL_TTS_USE_REF_TEXT", "TRUE"), default = TRUE),
    max_concurrency  = as.integer(.mergen_tts_parse_num(.mergen_tts_env_scalar("LOCAL_TTS_MAX_CONCURRENCY", "2"), 2, min_value = 1, max_value = 16)),

    # --- Üretilen ses (generated-audio) önbelleği ---
    cache_enabled  = .mergen_tts_parse_bool(.mergen_tts_env_scalar("LOCAL_TTS_CACHE_ENABLED", "TRUE"), default = TRUE),
    cache_dir      = .mergen_tts_env_scalar("LOCAL_TTS_CACHE_DIR", ""),
    cache_max_mb   = .mergen_tts_parse_num(.mergen_tts_env_scalar("LOCAL_TTS_CACHE_MAX_MB", "512"), 512, min_value = 1),
    cache_ttl_days = .mergen_tts_parse_num(.mergen_tts_env_scalar("LOCAL_TTS_CACHE_TTL_DAYS", "30"), 30, min_value = 0)
  )
}

#' VoxCPM2 Referans-Ses Profilleri Etkin mi?
#'
#' @description Referans-ses profillerinin gerçekten kullanılabilmesi için üç
#'   koşul birlikte sağlanmalıdır: profiller açık, model VoxCPM2 ailesinden ve
#'   yapılandırılmış bir ses profili dizini var. Aksi halde jenerik (profilsiz)
#'   TTS yolu kullanılır ve eski modele geri dönüş (rollback) mümkün kalır.
#' @param config TTS yapılandırması (varsayılan global tts_config)
#' @return Mantıksal
mergen_tts_voice_profiles_enabled <- function(config = NULL) {
  if (is.null(config)) config <- if (exists("tts_config", inherits = TRUE)) get("tts_config", inherits = TRUE) else list()
  isTRUE(config$profiles_enabled) &&
    mergen_tts_model_is_voxcpm(config$model %||% "") &&
    nzchar(config$voice_dir %||% "")
}

#' Persona İçin TTS Profil Kimliğini Çöz
#'
#' @description Persona kimliğinden (eski kimlikler dahil) VoxCPM2 ses profili
#'   kimliğini döndürür. Tek çözümleme noktasıdır; her modül kendi arama mantığını
#'   yazmamalıdır. Persona kaydındaki tts_profile alanı önceliklidir; yoksa
#'   normalleştirilmiş persona kimliğine düşülür (persona kimlikleri profil
#'   kimlikleriyle aynıdır).
#' @param char_id Persona kimliği (eski veya yeni biçim)
#' @return Profil kimliği (emre, selin, deniz, can, ipek)
mergen_tts_profile_for_character <- function(char_id) {
  norm_id <- if (exists("normalize_character_id", mode = "function", inherits = TRUE)) {
    normalize_character_id(char_id)
  } else {
    tolower(trimws(as.character(char_id %||% "")[1]))
  }

  rec <- tryCatch(
    if (exists("get_character_record", mode = "function", inherits = TRUE)) get_character_record(norm_id) else NULL,
    error = function(e) NULL
  )

  profile <- rec$tts_profile %||% rec$id %||% norm_id
  profile <- tolower(trimws(as.character(profile %||% "")[1]))
  if (is.na(profile) || !nzchar(profile)) return(norm_id)
  profile
}

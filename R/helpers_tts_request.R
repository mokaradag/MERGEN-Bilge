# ==============================================================================
# Dosya Yolu: R/helpers_tts_request.R
# Açıklama:   VoxCPM2 istek gövdesi oluşturma ve konuşma planı hazırlama.
#             İstek gövdesi tek noktadan kurulur; profil etkinse ref_audio +
#             ref_text eklenir, değilse jenerik (profilsiz) davranış korunur.
#             prepare_speech_plan; profil çözümlemesini, üretilen-ses önbelleği
#             anahtar/okuma işini worker BAŞLAMADAN ana süreçte yapar (worker'ın
#             her istekte WAV'ı yeniden base64'lemesini önler).
# ==============================================================================

if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
}

#' VoxCPM2/OpenAI Uyumlu İstek Gövdesi Oluştur
#'
#' @param text Seslendirilecek nihai metin (input)
#' @param model Model adı
#' @param voice Ses adı (jenerik yedek)
#' @param response_format Yanıt biçimi
#' @param speed Hız (NULL ise gövdeye eklenmez; jenerik eski davranış korunur)
#' @param ref_audio Referans ses base64 veri URL'si (NULL ise eklenmez)
#' @param ref_text Referans sesin birebir dökümü (NULL ise eklenmez)
#' @return İstek gövdesi listesi
mergen_tts_build_request_body <- function(text, model, voice, response_format,
                                          speed = NULL, ref_audio = NULL, ref_text = NULL) {
  body <- list(
    model = as.character(model %||% "")[1],
    input = as.character(text %||% "")[1],
    voice = as.character(voice %||% "default")[1],
    response_format = as.character(response_format %||% "wav")[1]
  )
  if (!is.null(speed) && !is.na(suppressWarnings(as.numeric(speed)))) {
    body$speed <- as.numeric(speed)
  }
  if (!is.null(ref_audio) && nzchar(as.character(ref_audio)[1])) {
    body$ref_audio <- as.character(ref_audio)[1]
  }
  if (!is.null(ref_text) && nzchar(as.character(ref_text)[1])) {
    body$ref_text <- as.character(ref_text)[1]
  }
  body
}

#' Konuşma Planı Hazırla (profil çözümleme + önbellek anahtarı/okuma)
#'
#' @description Profil etkinse referans-ses profilini bellek önbelleğinden çözer,
#'   VoxCPM2 istek gövdesini kurar, üretilen-ses önbellek anahtarını hesaplar ve
#'   önbellekte hazır ses varsa onu (base64 veri URL'si) döndürür. Profil çözümü
#'   başarısızsa güvenli biçimde jenerik yola düşer.
#' @param text Nihai metin
#' @param config TTS yapılandırması (varsayılan global tts_config)
#' @param profile_id Persona ses profili kimliği (NULL/boş ise jenerik)
#' @param voice Jenerik yedek ses
#' @param cache_lookup Üretilen-ses önbelleğinden okuma yapılsın mı
#' @param profile_loader Test için enjekte edilebilir profil yükleyici
#' @return Plan listesi (body, model, voice, response_format, mime_type, speed,
#'   profile_active, profile_error, cached_audio_src, cache_write_path,
#'   profile_version, wav_sha256)
mergen_tts_prepare_speech_plan <- function(text, config = NULL, profile_id = NULL,
                                           voice = NULL, cache_lookup = TRUE,
                                           profile_loader = NULL) {
  if (is.null(config)) config <- if (exists("tts_config", inherits = TRUE)) get("tts_config", inherits = TRUE) else list()
  if (is.null(profile_loader)) profile_loader <- mergen_tts_load_profile_cached

  model <- as.character(config$model %||% "tts-1-hd")[1]
  voice <- as.character(voice %||% config$default_voice %||% "default")[1]
  profile_id <- tolower(trimws(as.character(profile_id %||% "")[1]))

  profiles_on <- isTRUE(mergen_tts_voice_profiles_enabled(config)) && nzchar(profile_id)
  profile_active <- FALSE
  profile_error <- NULL
  profile <- NULL

  if (isTRUE(profiles_on)) {
    profile <- tryCatch(profile_loader(profile_id, config), error = function(e) list(ok = FALSE, error = conditionMessage(e)))
    if (isTRUE(profile$ok)) {
      profile_active <- TRUE
    } else {
      profile_error <- profile$error %||% "Ses profili çözülemedi."
    }
  }

  if (isTRUE(profile_active)) {
    response_format <- config$response_format %||% "wav"
    speed <- profile$speed %||% config$speed %||% 1.0
    ref_text <- if (isTRUE(config$use_ref_text)) profile$ref_text else NULL
    body <- mergen_tts_build_request_body(
      text = text, model = model, voice = voice, response_format = response_format,
      speed = speed, ref_audio = profile$audio_data_url, ref_text = ref_text
    )
  } else {
    # Jenerik (profilsiz) yol: mevcut davranışla uyumlu; hız eklenmez, mp3.
    response_format <- "mp3"
    speed <- NULL
    body <- mergen_tts_build_request_body(
      text = text, model = model, voice = voice, response_format = response_format
    )
  }

  cached_audio_src <- NULL
  cache_write_path <- ""
  if (isTRUE(profile_active) && isTRUE(config$cache_enabled) && nzchar(config$cache_dir %||% "")) {
    key <- mergen_tts_audio_cache_key(
      model = model, profile_id = profile_id, profile_version = profile$version,
      wav_sha256 = profile$wav_sha256, transcript_sha256 = profile$transcript_sha256,
      text = text, speed = speed, response_format = response_format
    )
    cache_path <- mergen_tts_audio_cache_path(config$cache_dir, key, response_format)
    if (nzchar(cache_path)) {
      cache_write_path <- cache_path
      if (isTRUE(cache_lookup)) {
        cached_raw <- mergen_tts_audio_cache_read(cache_path)
        if (!is.null(cached_raw)) {
          cached_audio_src <- mergen_tts_raw_to_data_url(cached_raw, response_format)
        }
      }
    }
  }

  list(
    body = body,
    model = model,
    voice = voice,
    response_format = response_format,
    mime_type = mergen_tts_mime_for_format(response_format),
    speed = speed,
    profile_active = profile_active,
    profile_error = profile_error,
    cached_audio_src = cached_audio_src,
    cache_write_path = cache_write_path,
    profile_version = if (!is.null(profile)) profile$version else NA_integer_,
    wav_sha256 = if (!is.null(profile)) profile$wav_sha256 else ""
  )
}

# R/helpers_speech_voice_profiles.R
# Persona ses profili TEK yetkili kaynağı ve kilitli referans ses (voice-lock)
# doğrulaması. Fail-closed kimlik politikası buradadır: kilitli referans yoksa
# ya da bozulmuşsa persona konuşması reddedilir; hiçbir zaman genel/başka bir
# sese sessizce düşülmez. Eski karakter kimlikleri YALNIZCA bilinen geçiş
# haritası üzerinden çevrilir; rastgele bilinmeyen ses etiketleri NA döner.

#' Ses/konuşma katmanı için kanonik persona çözümü.
#' Kanonik kimlikler aynen geçer; bilinen ESKİ kimlikler geçiş sınırından
#' çevrilir; bilinmeyen her değer NA_character_ döner (fail-closed).
mergen_speech_canonical_persona <- function(voice_id) {
  if (is.null(voice_id) || length(voice_id) == 0) return(NA_character_)
  raw <- tryCatch(as.character(voice_id)[1], error = function(e) NA_character_)
  if (is.na(raw)) return(NA_character_)

  key <- tolower(trimws(raw))
  if (!nzchar(key)) return(NA_character_)

  if (key %in% mergen_speech_personas()) return(key)

  legacy_map <- get0(".character_legacy_id_map", ifnotfound = NULL)
  normalize_fn <- get0("normalize_character_id", mode = "function")
  if (!is.null(legacy_map) && !is.null(normalize_fn) && key %in% names(legacy_map)) {
    mapped <- tryCatch(normalize_fn(key), error = function(e) NA_character_)
    if (!is.na(mapped) && mapped %in% mergen_speech_personas()) return(mapped)
  }

  NA_character_
}

#' UTF-8 metin dosyasını bayt-güvenli oku; geçersiz UTF-8 reddedilir.
.speech_read_utf8_text <- function(path) {
  if (!is.character(path) || length(path) != 1L || !file.exists(path)) return(NULL)
  size <- suppressWarnings(file.info(path)$size)
  if (is.na(size) || size <= 0) return(NULL)

  bytes <- readBin(path, "raw", n = size)
  # UTF-8 BOM varsa at
  if (length(bytes) >= 3 && identical(bytes[1:3], as.raw(c(0xEF, 0xBB, 0xBF)))) {
    bytes <- bytes[-(1:3)]
  }
  txt <- rawToChar(bytes)
  Encoding(txt) <- "UTF-8"
  if (!all(validUTF8(txt))) return(NULL)
  txt <- gsub("\r\n", "\n", txt, fixed = TRUE)
  trimws(txt)
}

#' Ham (raw) özet vektörünü hex metnine çevir.
.speech_hash_hex <- function(hash_raw) {
  paste(sprintf("%02x", as.integer(hash_raw)), collapse = "")
}

#' Dosyanın SHA-256 özeti (hex). openssl kullanılamıyorsa NA döner.
mergen_speech_sha256_file <- function(path) {
  if (!is.character(path) || length(path) != 1L || !file.exists(path)) {
    return(NA_character_)
  }
  if (!requireNamespace("openssl", quietly = TRUE)) return(NA_character_)
  size <- suppressWarnings(file.info(path)$size)
  if (is.na(size)) return(NA_character_)
  bytes <- readBin(path, "raw", n = size)
  .speech_hash_hex(openssl::sha256(bytes))
}

#' UTF-8 metnin SHA-256 özeti (hex).
mergen_speech_sha256_text <- function(text) {
  if (is.null(text) || length(text) != 1L || is.na(text)) return(NA_character_)
  if (!requireNamespace("openssl", quietly = TRUE)) return(NA_character_)
  .speech_hash_hex(openssl::sha256(charToRaw(enc2utf8(as.character(text)))))
}

#' Persona ses profili: kimlik, sabit referans yolları, model ve kimliği
#' etkileyen sentez parametreleri. Üretici, çalışma zamanı ve testler AYNI
#' profili kullanır; ayarlar başka dosyada kopyalanmaz.
mergen_speech_voice_profile <- function(persona, root = mergen_speech_root()) {
  persona <- mergen_speech_canonical_persona(persona)
  if (is.na(persona)) return(NULL)

  record <- NULL
  record_fn <- get0("get_character_record", mode = "function")
  if (!is.null(record_fn)) {
    record <- tryCatch(record_fn(persona), error = function(e) NULL)
  }

  speed <- suppressWarnings(as.numeric(Sys.getenv("VOXCPM2_SPEED", "1.0")))
  if (is.na(speed) || speed <= 0) speed <- 1.0

  cfg_value <- Sys.getenv("VOXCPM2_CFG_VALUE", "")
  inference_timesteps <- Sys.getenv("VOXCPM2_INFERENCE_TIMESTEPS", "")

  identity_params <- list(speed = speed)
  if (nzchar(cfg_value)) {
    identity_params$cfg_value <- suppressWarnings(as.numeric(cfg_value))
  }
  if (nzchar(inference_timesteps)) {
    identity_params$inference_timesteps <- suppressWarnings(as.integer(inference_timesteps))
  }

  wav_profile <- mergen_speech_expected_wav_profile()

  list(
    persona_id = persona,
    full_name = if (!is.null(record)) as.character(record$full_name %||% persona) else persona,
    role = if (!is.null(record)) as.character(record$subtitle %||% "") else "",
    reference_text_path = mergen_speech_reference_text_path(persona, root),
    reference_wav_path = mergen_speech_reference_wav_path(persona, root),
    voice_lock_path = mergen_speech_voice_lock_path(persona, root),
    model = Sys.getenv("LOCAL_TTS_MODEL", "voxcpm2"),
    response_format = "wav",
    identity_params = identity_params,
    expected_sample_rate = wav_profile$sample_rate,
    expected_channels = wav_profile$channels,
    expected_bits_per_sample = wav_profile$bits_per_sample
  )
}

#' Profilin kimliği etkileyen alanlarından deterministik parmak izi üret.
#' Model, hız ve kimlik parametreleri değişirse kilit geçersizleşir.
mergen_speech_profile_identity_fingerprint <- function(profile) {
  if (is.null(profile)) return(NA_character_)
  params <- profile$identity_params %||% list()
  params <- params[order(names(params))]
  canonical <- paste(
    c(
      sprintf("persona=%s", profile$persona_id),
      sprintf("model=%s", profile$model),
      sprintf("format=%s", profile$response_format),
      sprintf("sample_rate=%s", profile$expected_sample_rate),
      sprintf("channels=%s", profile$expected_channels),
      sprintf("bits=%s", profile$expected_bits_per_sample),
      vapply(names(params), function(nm) {
        sprintf("%s=%s", nm, format(params[[nm]], scientific = FALSE))
      }, character(1))
    ),
    collapse = "|"
  )
  mergen_speech_sha256_text(canonical)
}

#' Onaylanan referans için voice-lock içeriği üret.
mergen_speech_voice_lock_payload <- function(profile, wav_path = NULL, reference_text = NULL) {
  if (is.null(profile)) return(NULL)
  wav_path <- wav_path %||% profile$reference_wav_path
  reference_text <- reference_text %||% .speech_read_utf8_text(profile$reference_text_path)

  wav_info <- mergen_wav_parse(wav_path)

  list(
    schema_version = 1L,
    persona_id = profile$persona_id,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    reference_wav_sha256 = mergen_speech_sha256_file(wav_path),
    reference_text_sha256 = mergen_speech_sha256_text(reference_text),
    profile_fingerprint = mergen_speech_profile_identity_fingerprint(profile),
    model = profile$model,
    identity_params = profile$identity_params,
    reference_wav = list(
      sample_rate = wav_info$sample_rate,
      channels = wav_info$channels,
      bits_per_sample = wav_info$bits_per_sample,
      duration_ms = wav_info$duration_ms
    )
  )
}

#' voice-lock.json dosyasını oku; yoksa/bozuksa NULL.
mergen_speech_voice_lock_read <- function(persona, root = mergen_speech_root()) {
  persona <- mergen_speech_canonical_persona(persona)
  if (is.na(persona)) return(NULL)
  path <- mergen_speech_voice_lock_path(persona, root)
  if (!file.exists(path)) return(NULL)
  tryCatch(
    jsonlite::fromJSON(path, simplifyVector = TRUE, simplifyDataFrame = FALSE),
    error = function(e) NULL
  )
}

#' Kilitli referansı doğrula (fail-closed). Referans WAV/metin/lock üçlüsü
#' mevcut ve özetleri tutarlı olmalı; profil parmak izi kilitle eşleşmeli.
#'
#' @return list(ok, reason, lock, reference_text)
mergen_speech_voice_lock_validate <- function(persona, root = mergen_speech_root(),
                                              profile = NULL) {
  fail <- function(reason) list(ok = FALSE, reason = reason, lock = NULL, reference_text = NULL)

  persona <- mergen_speech_canonical_persona(persona)
  if (is.na(persona)) return(fail("bilinmeyen_persona"))

  if (is.null(profile)) profile <- mergen_speech_voice_profile(persona, root)
  if (is.null(profile)) return(fail("profil_yok"))

  lock <- mergen_speech_voice_lock_read(persona, root)
  if (is.null(lock)) return(fail("voice_lock_yok"))
  if (!identical(as.character(lock$persona_id), persona)) return(fail("kilit_persona_uyusmuyor"))

  if (!file.exists(profile$reference_wav_path)) return(fail("referans_wav_yok"))
  ref_text <- .speech_read_utf8_text(profile$reference_text_path)
  if (is.null(ref_text) || !nzchar(ref_text)) return(fail("referans_metni_yok"))

  wav_sha <- mergen_speech_sha256_file(profile$reference_wav_path)
  if (is.na(wav_sha) || !identical(wav_sha, as.character(lock$reference_wav_sha256))) {
    return(fail("referans_wav_ozeti_uyusmuyor"))
  }

  text_sha <- mergen_speech_sha256_text(ref_text)
  if (is.na(text_sha) || !identical(text_sha, as.character(lock$reference_text_sha256))) {
    return(fail("referans_metin_ozeti_uyusmuyor"))
  }

  fingerprint <- mergen_speech_profile_identity_fingerprint(profile)
  if (is.na(fingerprint) || !identical(fingerprint, as.character(lock$profile_fingerprint))) {
    return(fail("profil_parmak_izi_uyusmuyor"))
  }

  wav_check <- mergen_wav_validate(
    profile$reference_wav_path,
    expected = list(
      sample_rate = profile$expected_sample_rate,
      channels = profile$expected_channels,
      bits_per_sample = profile$expected_bits_per_sample
    ),
    min_ms = 500, max_ms = 120000
  )
  if (!isTRUE(wav_check$ok)) {
    return(fail(paste0("referans_wav_gecersiz:", wav_check$reason)))
  }

  list(ok = TRUE, reason = NULL, lock = lock, reference_text = ref_text)
}

# Süreç kapsamlı referans yükü önbelleği (persona + kilit özeti anahtarıyla).
if (!exists(".mergen_speech_reference_cache", inherits = FALSE)) {
  .mergen_speech_reference_cache <- new.env(parent = emptyenv())
}

#' Sentez isteklerinde kullanılacak referans yükünü çöz (fail-closed).
#' Başarıda base64 referans sesi + birebir referans metni + profil döner.
#'
#' @return list(ok, reason, persona_id, ref_b64, ref_text, profile)
mergen_speech_reference_payload <- function(persona, root = mergen_speech_root()) {
  fail <- function(reason) {
    list(ok = FALSE, reason = reason, persona_id = NA_character_,
         ref_b64 = NULL, ref_text = NULL, profile = NULL)
  }

  persona <- mergen_speech_canonical_persona(persona)
  if (is.na(persona)) return(fail("bilinmeyen_persona"))

  profile <- mergen_speech_voice_profile(persona, root)
  if (is.null(profile)) return(fail("profil_yok"))

  validation <- mergen_speech_voice_lock_validate(persona, root, profile = profile)
  if (!isTRUE(validation$ok)) return(fail(validation$reason))

  lock_sha <- as.character(validation$lock$reference_wav_sha256)
  cache_key <- sprintf("%s::%s", persona, lock_sha)
  cached <- get0(cache_key, envir = .mergen_speech_reference_cache, ifnotfound = NULL)
  if (!is.null(cached)) return(cached)

  if (!requireNamespace("base64enc", quietly = TRUE)) {
    return(fail("base64enc_paketi_yok"))
  }

  size <- suppressWarnings(file.info(profile$reference_wav_path)$size)
  ref_bytes <- readBin(profile$reference_wav_path, "raw", n = size)

  payload <- list(
    ok = TRUE, reason = NULL,
    persona_id = persona,
    ref_b64 = base64enc::base64encode(ref_bytes),
    ref_text = validation$reference_text,
    profile = profile
  )

  assign(cache_key, payload, envir = .mergen_speech_reference_cache)
  payload
}

#' Referans yük önbelleğini temizle (test/yeniden üretim sonrası).
mergen_speech_reference_cache_clear <- function() {
  rm(list = ls(envir = .mergen_speech_reference_cache),
     envir = .mergen_speech_reference_cache)
  invisible(NULL)
}

# ==============================================================================
# Dosya Yolu: tests/testthat/helper_tts_voice_fixtures.R
# Açıklama: VoxCPM2 ses profili testleri için ortak sabitler (fixtures).
#           Gerçek biyometrik referans kaydı GEREKMEZ: geçici dizinlerde
#           sentetik (sessizlik) WAV dosyaları, manifest ve transcript üretir.
#           Gerçek TTS uç noktası, ağ, DB veya tarayıcı KULLANILMAZ.
# ==============================================================================

if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
}

# VoxCPM2 yardımcı dosyalarını (ve gerekli persona config'ini) yükler.
tts_fixture_source_helpers <- function() {
  root <- resolve_repo_root_for_tests()
  files <- c(
    "R/config_characters.R",
    "R/helpers_tts_voice_config.R",
    "R/helpers_tts_voice_manifest.R",
    "R/helpers_tts_voice_cache.R",
    "R/helpers_tts_audio_cache.R",
    "R/helpers_tts_request.R",
    "R/helpers_tts_queue.R",
    "R/helpers_tts_profile_preload.R"
  )
  for (f in files) {
    source(file.path(root, f), encoding = "UTF-8", local = globalenv())
  }
  invisible(TRUE)
}

# Sentetik PCM WAV (sessizlik) yazar. Varsayılan: mono, 16-bit, 16 kHz.
tts_fixture_write_wav <- function(path, seconds = 1,
                                  sample_rate = 16000L, channels = 1L, bits = 16L) {
  n_samples   <- as.integer(round(seconds * sample_rate))
  byte_per    <- as.integer(bits / 8)
  byte_rate   <- as.integer(sample_rate * channels * byte_per)
  block_align <- as.integer(channels * byte_per)
  data_size   <- as.integer(n_samples * channels * byte_per)

  con <- file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  writeChar("RIFF", con, eos = NULL)
  writeBin(as.integer(36 + data_size), con, size = 4, endian = "little")
  writeChar("WAVE", con, eos = NULL)
  writeChar("fmt ", con, eos = NULL)
  writeBin(as.integer(16), con, size = 4, endian = "little")
  writeBin(as.integer(1), con, size = 2, endian = "little")           # PCM
  writeBin(as.integer(channels), con, size = 2, endian = "little")
  writeBin(as.integer(sample_rate), con, size = 4, endian = "little")
  writeBin(as.integer(byte_rate), con, size = 4, endian = "little")
  writeBin(as.integer(block_align), con, size = 2, endian = "little")
  writeBin(as.integer(bits), con, size = 2, endian = "little")
  writeChar("data", con, eos = NULL)
  writeBin(as.integer(data_size), con, size = 4, endian = "little")
  if (n_samples > 0L) {
    writeBin(integer(n_samples * channels), con, size = byte_per, endian = "little")
  }
  invisible(normalizePath(path, winslash = "/", mustWork = TRUE))
}

# Ortak transcript metni (üretimdeki kanonik pasajın kısa test eşleniği).
tts_fixture_transcript_text <- function() {
  paste0(
    "Merhaba, bu Mergen Bilge icin sentetik bir Turkce ses ornegidir. ",
    "Sakin bir hizla ve acik bir soyleyisle konusuyorum."
  )
}

# Beş profilli tam bir ses profili dizini kurar (manifest + transcript + WAV'lar).
# Döndürür: voice_dir yolu.
tts_fixture_build_voice_dir <- function(base_dir = tempfile("tts_voices_"),
                                        ids = c("emre", "selin", "deniz", "can", "ipek"),
                                        seconds = 1,
                                        transcript = tts_fixture_transcript_text()) {
  dir.create(base_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(transcript, file.path(base_dir, "reference_transcript_tr_v1.txt"), useBytes = TRUE)

  profiles <- list()
  for (id in ids) {
    dir.create(file.path(base_dir, id), recursive = TRUE, showWarnings = FALSE)
    tts_fixture_write_wav(file.path(base_dir, id, "reference.wav"), seconds = seconds)
    profiles[[id]] <- list(
      audio = paste0(id, "/reference.wav"),
      transcript_id = "tr_common_v1",
      version = 1L,
      speed = 1.0,
      enabled = TRUE
    )
  }

  manifest <- list(
    schema_version = 1L,
    transcripts = list(
      tr_common_v1 = list(file = "reference_transcript_tr_v1.txt", language = "tr-TR", version = 1L)
    ),
    profiles = profiles
  )
  jsonlite::write_json(manifest, file.path(base_dir, "manifest.json"),
                       auto_unbox = TRUE, pretty = TRUE)
  normalizePath(base_dir, winslash = "/", mustWork = TRUE)
}

# Test için jenerik TTS yapılandırması üretir (profil parametreleri ile).
tts_fixture_config <- function(voice_dir = "", model = "VoxCPM2", cache_dir = "",
                               profiles_enabled = TRUE, use_ref_text = TRUE,
                               response_format = "wav", speed = 1.0, cache_enabled = TRUE) {
  list(
    base_url = "https://example.invalid/v1",
    api_key = "",
    model = model,
    default_voice = "default",
    timeout_seconds = 90,
    verify_ssl = TRUE,
    profiles_enabled = profiles_enabled,
    voice_dir = voice_dir,
    speed = speed,
    response_format = response_format,
    use_ref_text = use_ref_text,
    max_concurrency = 2L,
    cache_enabled = cache_enabled,
    cache_dir = cache_dir,
    cache_max_mb = 512,
    cache_ttl_days = 30
  )
}

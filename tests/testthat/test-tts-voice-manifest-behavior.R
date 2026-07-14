# ==============================================================================
# Dosya Yolu: tests/testthat/test-tts-voice-manifest-behavior.R
# Açıklama: WAV doğrulama, manifest yükleme ve tek profil çözümleme davranış
#           testleri. Sentetik WAV/manifest kullanılır; gerçek ses GEREKMEZ.
# ==============================================================================

if (!exists("tts_fixture_source_helpers", mode = "function")) {
  source(file.path(resolve_repo_root_for_tests(), "tests", "testthat", "helper_tts_voice_fixtures.R"),
         encoding = "UTF-8", local = FALSE)
}
tts_fixture_source_helpers()

test_that("mergen_tts_validate_wav geçerli 16k mono 16-bit WAV'ı kabul eder", {
  wav <- tempfile(fileext = ".wav")
  tts_fixture_write_wav(wav, seconds = 1)
  res <- mergen_tts_validate_wav(wav)
  expect_true(res$ok)
  expect_identical(res$metadata$channels, 1)
  expect_identical(res$metadata$sample_rate, 16000)
  expect_identical(res$metadata$bits_per_sample, 16)
})

test_that("mergen_tts_validate_wav stereo/8-bit/8k/süre dışı dosyaları reddeder", {
  stereo <- tempfile(fileext = ".wav"); tts_fixture_write_wav(stereo, seconds = 1, channels = 2L)
  expect_false(mergen_tts_validate_wav(stereo)$ok)

  eight_bit <- tempfile(fileext = ".wav"); tts_fixture_write_wav(eight_bit, seconds = 1, bits = 8L)
  expect_false(mergen_tts_validate_wav(eight_bit)$ok)

  low_sr <- tempfile(fileext = ".wav"); tts_fixture_write_wav(low_sr, seconds = 1, sample_rate = 8000L)
  expect_false(mergen_tts_validate_wav(low_sr)$ok)

  too_short <- tempfile(fileext = ".wav"); tts_fixture_write_wav(too_short, seconds = 0.1)
  expect_false(mergen_tts_validate_wav(too_short, min_secs = 0.5, max_secs = 30)$ok)

  ok_wav <- tempfile(fileext = ".wav"); tts_fixture_write_wav(ok_wav, seconds = 1)
  expect_false(mergen_tts_validate_wav(ok_wav, min_secs = 0, max_secs = 0.5)$ok)  # üst sınır
})

test_that("mergen_tts_validate_wav RIFF/WAVE olmayan dosyayı reddeder", {
  bogus <- tempfile(fileext = ".wav")
  writeBin(charToRaw("NOTAWAVEFILE00000000"), bogus)
  expect_false(mergen_tts_validate_wav(bogus)$ok)
})

test_that("mergen_tts_safe_relative_path traversal ve mutlak yolu reddeder", {
  expect_false(mergen_tts_safe_relative_path("/base", "../etc/passwd")$ok)
  expect_false(mergen_tts_safe_relative_path("/base", "/etc/passwd")$ok)
  expect_false(mergen_tts_safe_relative_path("/base", "C:/Windows/x")$ok)
  expect_false(mergen_tts_safe_relative_path("/base", "")$ok)
  ok <- mergen_tts_safe_relative_path("/base", "emre/reference.wav")
  expect_true(ok$ok)
  expect_identical(ok$path, file.path("/base", "emre/reference.wav"))
})

test_that("mergen_tts_load_voice_manifest eksik/geçersiz manifesti güvenli reddeder", {
  # Eksik dizin
  expect_false(mergen_tts_load_voice_manifest(tempfile("yok_"))$ok)

  # Geçersiz schema
  vd <- tempfile("vd_"); dir.create(vd)
  jsonlite::write_json(list(schema_version = 2L, transcripts = list(a = list(file = "t")), profiles = list(emre = list())),
                       file.path(vd, "manifest.json"), auto_unbox = TRUE)
  expect_false(mergen_tts_load_voice_manifest(vd)$ok)
})

test_that("mergen_tts_resolve_profile geçerli profili çözer ve base64 üretir", {
  vd <- tts_fixture_build_voice_dir()
  cfg <- tts_fixture_config(voice_dir = vd)
  res <- mergen_tts_resolve_profile("emre", cfg)

  expect_true(res$ok)
  expect_identical(res$profile_id, "emre")
  expect_identical(res$version, 1L)
  expect_true(startsWith(res$audio_data_url, "data:audio/wav;base64,"))
  expect_true(nchar(res$ref_text) > 0)
  expect_identical(nchar(res$wav_sha256), 64L)
  expect_identical(nchar(res$transcript_sha256), 64L)
  expect_identical(res$channels, 1)
})

test_that("mergen_tts_resolve_profile bilinmeyen/tanımsız profili reddeder", {
  vd <- tts_fixture_build_voice_dir(ids = c("emre"))
  cfg <- tts_fixture_config(voice_dir = vd)
  expect_false(mergen_tts_resolve_profile("bilinmeyen", cfg)$ok)  # bilinmeyen kimlik
  expect_false(mergen_tts_resolve_profile("selin", cfg)$ok)       # manifestte yok
})

test_that("mergen_tts_resolve_profile devre dışı profili reddeder", {
  vd <- tts_fixture_build_voice_dir()
  # emre profilini devre dışı bırak
  man <- jsonlite::fromJSON(file.path(vd, "manifest.json"), simplifyVector = FALSE)
  man$profiles$emre$enabled <- FALSE
  jsonlite::write_json(man, file.path(vd, "manifest.json"), auto_unbox = TRUE)
  cfg <- tts_fixture_config(voice_dir = vd)
  expect_false(mergen_tts_resolve_profile("emre", cfg)$ok)
})

test_that("mergen_tts_resolve_profile bozuk WAV içeren profili reddeder ama diğerlerini etkilemez", {
  vd <- tts_fixture_build_voice_dir()
  # selin WAV'ını stereo yaparak bozalım
  tts_fixture_write_wav(file.path(vd, "selin", "reference.wav"), seconds = 1, channels = 2L)
  cfg <- tts_fixture_config(voice_dir = vd)
  expect_false(mergen_tts_resolve_profile("selin", cfg)$ok)
  expect_true(mergen_tts_resolve_profile("emre", cfg)$ok)   # tek bozuk profil diğerini engellemez
})

test_that("mergen_tts_resolve_profile geçersiz UTF-8 transcript'i reddeder", {
  vd <- tts_fixture_build_voice_dir()
  # Geçersiz UTF-8 baytları yaz
  writeBin(as.raw(c(0xFF, 0xFE, 0x41, 0x42)), file.path(vd, "reference_transcript_tr_v1.txt"))
  cfg <- tts_fixture_config(voice_dir = vd)
  expect_false(mergen_tts_resolve_profile("emre", cfg)$ok)
})

# ==============================================================================
# Dosya Yolu: tests/testthat/test-tts-request-behavior.R
# Açıklama: VoxCPM2 istek gövdesi ve konuşma planı davranış testleri.
#           Profil etkinken ref_audio/ref_text/hız; jenerik yolda bunların
#           bulunmaması ve önbellek isabeti doğrulanır.
# ==============================================================================

if (!exists("tts_fixture_source_helpers", mode = "function")) {
  source(file.path(resolve_repo_root_for_tests(), "tests", "testthat", "helper_tts_voice_fixtures.R"),
         encoding = "UTF-8", local = FALSE)
}
tts_fixture_source_helpers()

test_that("build_request_body profil alanlarını koşullu ekler", {
  body <- mergen_tts_build_request_body("Metin", "VoxCPM2", "default", "wav",
                                        speed = 1.0, ref_audio = "data:audio/wav;base64,AAA", ref_text = "Ref")
  expect_identical(body$model, "VoxCPM2")
  expect_identical(body$input, "Metin")
  expect_identical(body$response_format, "wav")
  expect_identical(body$speed, 1.0)
  expect_identical(body$ref_audio, "data:audio/wav;base64,AAA")
  expect_identical(body$ref_text, "Ref")
})

test_that("build_request_body jenerik yolda hız/ref alanlarını atlar", {
  body <- mergen_tts_build_request_body("Metin", "tts-1-hd", "default", "mp3")
  expect_null(body$speed)
  expect_null(body$ref_audio)
  expect_null(body$ref_text)
  expect_identical(body$response_format, "mp3")
})

test_that("redact_error_text ref_audio ve data URL sızıntılarını gizler", {
  leaked <- paste0(
    '{"error":"bad","ref_audio":"data:audio/wav;base64,',
    paste(rep("A", 120), collapse = ""),
    '","input":"Merhaba"}'
  )
  redacted <- mergen_tts_redact_error_text(leaked)

  expect_match(redacted, "\\[REDACTED_REF_AUDIO\\]")
  expect_false(grepl("data:audio/wav;base64", redacted, fixed = TRUE))
  expect_false(grepl(paste(rep("A", 80), collapse = ""), redacted, fixed = TRUE))
  expect_match(redacted, '"input":"Merhaba"', fixed = TRUE)
})

test_that("streaming TTS entegrasyonu persona profilini synthesize_speech çağrısına taşır", {
  handler_src <- readLines(file.path(resolve_repo_root_for_tests(), "R", "server_handler_streaming_tts.R"),
                           warn = FALSE, encoding = "UTF-8")
  handler_text <- paste(handler_src, collapse = "\n")

  expect_match(handler_text, "streaming_profile_sel <-")
  expect_match(handler_text, "mergen_tts_profile_for_character\\(local_char_id\\)")
  expect_match(handler_text, "profile_id = streaming_profile_sel")
})

test_that("prepare_speech_plan profil etkinken referans ses + hız (1.0) + wav üretir", {
  vd <- tts_fixture_build_voice_dir(ids = c("emre"))
  cfg <- tts_fixture_config(voice_dir = vd, model = "VoxCPM2")
  plan <- mergen_tts_prepare_speech_plan("Merhaba dünya", config = cfg, profile_id = "emre", voice = "default")

  expect_true(plan$profile_active)
  expect_false(is.null(plan$body$ref_audio))
  expect_true(startsWith(plan$body$ref_audio, "data:audio/wav;base64,"))
  expect_false(is.null(plan$body$ref_text))
  expect_identical(plan$body$speed, 1.0)
  expect_identical(plan$body$response_format, "wav")
  expect_identical(plan$mime_type, "audio/wav")
})

test_that("prepare_speech_plan use_ref_text=FALSE iken ref_text eklemez", {
  vd <- tts_fixture_build_voice_dir(ids = c("emre"))
  cfg <- tts_fixture_config(voice_dir = vd, use_ref_text = FALSE)
  plan <- mergen_tts_prepare_speech_plan("Merhaba", config = cfg, profile_id = "emre")
  expect_true(plan$profile_active)
  expect_false(is.null(plan$body$ref_audio))
  expect_null(plan$body$ref_text)
})

test_that("prepare_speech_plan jenerik (non-VoxCPM) yolda referans alanları eklemez", {
  vd <- tts_fixture_build_voice_dir(ids = c("emre"))
  cfg <- tts_fixture_config(voice_dir = vd, model = "tts-1-hd")
  plan <- mergen_tts_prepare_speech_plan("Merhaba", config = cfg, profile_id = "emre", voice = "default")
  expect_false(plan$profile_active)
  expect_null(plan$body$ref_audio)
  expect_null(plan$body$ref_text)
  expect_identical(plan$body$response_format, "mp3")  # eski davranış korunur
})

test_that("prepare_speech_plan profil çözülemezse jenerik yola güvenli düşer", {
  cfg <- tts_fixture_config(voice_dir = tempfile("yok_"), model = "VoxCPM2")  # manifest yok
  plan <- mergen_tts_prepare_speech_plan("Merhaba", config = cfg, profile_id = "emre")
  expect_false(plan$profile_active)
  expect_false(is.null(plan$profile_error))
  expect_null(plan$body$ref_audio)
})

test_that("prepare_speech_plan önbellek isabetinde base64 döndürür ve worker'ı atlar", {
  mergen_tts_invalidate_all_profiles()
  vd <- tts_fixture_build_voice_dir(ids = c("emre"))
  cache_dir <- tempfile("tts_cache_"); dir.create(cache_dir)
  cfg <- tts_fixture_config(voice_dir = vd, cache_dir = cache_dir, cache_enabled = TRUE)

  # İlk plan: önbellek boş -> cache_write_path dolu, cached_audio_src NULL
  plan1 <- mergen_tts_prepare_speech_plan("Sabit ifade", config = cfg, profile_id = "emre")
  expect_true(nzchar(plan1$cache_write_path))
  expect_null(plan1$cached_audio_src)

  # Worker'ın yazdığını taklit et: cache dosyasına sentetik wav bayt yaz
  writeBin(as.raw(c(1, 2, 3, 4)), plan1$cache_write_path)

  # İkinci plan: aynı metin -> önbellek isabeti
  plan2 <- mergen_tts_prepare_speech_plan("Sabit ifade", config = cfg, profile_id = "emre")
  expect_false(is.null(plan2$cached_audio_src))
  expect_true(startsWith(plan2$cached_audio_src, "data:audio/wav;base64,"))
})

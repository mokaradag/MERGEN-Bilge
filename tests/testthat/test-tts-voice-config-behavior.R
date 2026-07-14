# ==============================================================================
# Dosya Yolu: tests/testthat/test-tts-voice-config-behavior.R
# Açıklama: VoxCPM2 TTS yapılandırma üreticisi ve persona -> profil çözümleyici
#           davranış testleri. Gerçek TTS/DB/ağ GEREKMEZ.
# ==============================================================================

if (!exists("tts_fixture_source_helpers", mode = "function")) {
  source(file.path(resolve_repo_root_for_tests(), "tests", "testthat", "helper_tts_voice_fixtures.R"),
         encoding = "UTF-8", local = FALSE)
}
tts_fixture_source_helpers()

test_that("mergen_tts_model_is_voxcpm VoxCPM ailesini tanır", {
  expect_true(mergen_tts_model_is_voxcpm("VoxCPM2"))
  expect_true(mergen_tts_model_is_voxcpm("voxcpm2"))
  expect_true(mergen_tts_model_is_voxcpm("voxcpm"))
  expect_false(mergen_tts_model_is_voxcpm("tts-1-hd"))
  expect_false(mergen_tts_model_is_voxcpm(""))
  expect_false(mergen_tts_model_is_voxcpm(NULL))
})

test_that(".mergen_tts_parse_bool geçerli/geçersiz değerleri güvenli çözer", {
  expect_true(.mergen_tts_parse_bool("TRUE", FALSE))
  expect_true(.mergen_tts_parse_bool("1", FALSE))
  expect_true(.mergen_tts_parse_bool("evet", FALSE))
  expect_false(.mergen_tts_parse_bool("false", TRUE))
  expect_false(.mergen_tts_parse_bool("hayır", TRUE))
  expect_identical(.mergen_tts_parse_bool("", TRUE), TRUE)      # boş -> varsayılan
  expect_identical(.mergen_tts_parse_bool("saçma", FALSE), FALSE)
})

test_that(".mergen_tts_parse_num sınırları uygular ve güvenli varsayılana düşer", {
  expect_identical(.mergen_tts_parse_num("1.5", 1.0), 1.5)
  expect_identical(.mergen_tts_parse_num("abc", 2.0), 2.0)
  expect_identical(.mergen_tts_parse_num("", 3.0), 3.0)
  expect_identical(.mergen_tts_parse_num("100", 1.0, max_value = 4.0), 1.0)  # sınır dışı -> varsayılan
  expect_identical(.mergen_tts_parse_num("0.1", 1.0, min_value = 0.25), 1.0)
})

test_that("mergen_build_tts_config eksik ortamda güvenli varsayılanlar üretir", {
  testthat::skip_if_not_installed("withr")
  cfg <- withr::with_envvar(
    c(LOCAL_TTS_ENDPOINT = "", LOCAL_TTS_MODEL = "", LOCAL_TTS_VOICE = "",
      LOCAL_TTS_PROFILES_ENABLED = "", LOCAL_TTS_VOICE_DIR = "",
      LOCAL_TTS_SPEED = "", LOCAL_TTS_RESPONSE_FORMAT = "", LOCAL_TTS_USE_REF_TEXT = "",
      LOCAL_TTS_MAX_CONCURRENCY = "", LOCAL_TTS_CACHE_ENABLED = "",
      LOCAL_TTS_CACHE_DIR = "", LOCAL_TTS_CACHE_MAX_MB = "", LOCAL_TTS_CACHE_TTL_DAYS = "",
      LOCAL_TTS_TIMEOUT = "", LOCAL_TTS_VERIFY_SSL = ""),
    mergen_build_tts_config()
  )
  expect_identical(cfg$model, "tts-1-hd")          # geriye dönük varsayılan
  expect_identical(cfg$default_voice, "default")
  expect_true(cfg$profiles_enabled)
  expect_identical(cfg$speed, 1.0)
  expect_identical(cfg$response_format, "wav")
  expect_true(cfg$use_ref_text)
  expect_identical(cfg$max_concurrency, 2L)
  expect_true(cfg$cache_enabled)
  expect_identical(cfg$cache_max_mb, 512)
  expect_identical(cfg$cache_ttl_days, 30)
  expect_identical(cfg$timeout_seconds, 90)
  expect_true(cfg$verify_ssl)
})

test_that("mergen_build_tts_config üretim değerlerini okur", {
  testthat::skip_if_not_installed("withr")
  cfg <- withr::with_envvar(
    c(LOCAL_TTS_MODEL = "VoxCPM2", LOCAL_TTS_VOICE = "default",
      LOCAL_TTS_PROFILES_ENABLED = "TRUE", LOCAL_TTS_VOICE_DIR = "C:/MERGEN_Bilge_Data/tts_voices",
      LOCAL_TTS_SPEED = "1.0", LOCAL_TTS_RESPONSE_FORMAT = "wav",
      LOCAL_TTS_MAX_CONCURRENCY = "3", LOCAL_TTS_CACHE_DIR = "C:/MERGEN_Bilge_Data/tts_cache"),
    mergen_build_tts_config()
  )
  expect_identical(cfg$model, "VoxCPM2")
  expect_identical(cfg$voice_dir, "C:/MERGEN_Bilge_Data/tts_voices")
  expect_identical(cfg$max_concurrency, 3L)
  expect_identical(cfg$cache_dir, "C:/MERGEN_Bilge_Data/tts_cache")
})

test_that("mergen_tts_voice_profiles_enabled üç koşulu birlikte ister", {
  base <- tts_fixture_config(voice_dir = "/x", model = "VoxCPM2", profiles_enabled = TRUE)
  expect_true(mergen_tts_voice_profiles_enabled(base))

  off <- base; off$profiles_enabled <- FALSE
  expect_false(mergen_tts_voice_profiles_enabled(off))

  not_vox <- base; not_vox$model <- "tts-1-hd"
  expect_false(mergen_tts_voice_profiles_enabled(not_vox))

  no_dir <- base; no_dir$voice_dir <- ""
  expect_false(mergen_tts_voice_profiles_enabled(no_dir))
})

test_that("mergen_tts_profile_for_character beş persona için doğru profil verir", {
  expect_identical(mergen_tts_profile_for_character("emre"), "emre")
  expect_identical(mergen_tts_profile_for_character("selin"), "selin")
  expect_identical(mergen_tts_profile_for_character("deniz"), "deniz")
  expect_identical(mergen_tts_profile_for_character("can"), "can")
  expect_identical(mergen_tts_profile_for_character("ipek"), "ipek")
  # Eski kimlik migrasyonu
  expect_identical(mergen_tts_profile_for_character("mergen"), "emre")
  expect_identical(mergen_tts_profile_for_character("kayra"), "deniz")
  # Geçersiz -> varsayılan
  expect_identical(mergen_tts_profile_for_character(NULL), "emre")
  expect_identical(mergen_tts_profile_for_character("yok"), "emre")
})

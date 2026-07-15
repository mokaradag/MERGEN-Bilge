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

  encoded <- "ref_audio=data%3Aaudio%2Fwav%3Bbase64%2CAAAAA&input=Merhaba"
  expect_false(grepl("data%3Aaudio%2Fwav", mergen_tts_redact_error_text(encoded), fixed = TRUE))

  escaped_json <- '{"ref_audio":"data:audio\\/wav;base64,BBBBB","error":"bad"}'
  expect_false(grepl("data:audio", mergen_tts_redact_error_text(escaped_json), fixed = TRUE))
})

test_that("resolve_profile_id açık profili korur ve eksik profili personadan çözer", {
  cfg <- list(profiles_enabled = TRUE, model = "VoxCPM2", voice_dir = tempdir())

  expect_identical(mergen_tts_resolve_profile_id(profile_id = " Selin ", config = cfg), "selin")
  expect_identical(mergen_tts_resolve_profile_id(char_id = "can", config = cfg), "can")
  expect_null(mergen_tts_resolve_profile_id(char_id = "can", config = list(profiles_enabled = FALSE)))
})

test_that("streaming TTS entegrasyonu persona profilini davranışsal olarak taşır", {
  test_env <- new.env(parent = globalenv())
  test_env$`%...!%` <- get("%...!%", asNamespace("promises"))
  source(file.path(resolve_repo_root_for_tests(), "R", "server_handler_streaming_tts.R"),
         encoding = "UTF-8", local = test_env)

  test_env$log_debug <- function(...) invisible(NULL)
  test_env$log_warn <- function(...) invisible(NULL)
  test_env$dbg_dump <- function(...) invisible(NULL)
  test_env$mergen_log_llm_request_debug <- function(...) invisible(NULL)
  test_env$log_ai_usage <- function(...) invisible(NULL)
  test_env$mb_api_key_invalidate_send_cache_on_auth_error <- function(...) invisible(NULL)
  test_env$mergen_send_message_request_state <- function(...) "current"
  test_env$build_followup_suggestions <- function(...) character()
  test_env$normalize_character_id <- function(x) x
  test_env$get_characters_data <- function() list(styles = list(list(id = "ipek", tts_voice = "tr-female-1")))
  test_env$tts_config <- list(profiles_enabled = TRUE, model = "VoxCPM2", voice_dir = tempdir())
  test_env$mergen_tts_resolve_profile_id <- function(profile_id = NULL, char_id = NULL, config = NULL) {
    paste0("profile-", char_id)
  }

  active_value <- NULL
  stop_value <- FALSE
  captured_profile <- NULL
  captured_voice <- NULL

  ctx <- list(
    session = list(userData = new.env(parent = emptyenv())),
    values = new.env(parent = emptyenv()),
    settings_data = list(enable_tts_audio = TRUE),
    stop_generation = function(value) {
      if (!missing(value)) stop_value <<- value
      stop_value
    },
    active_request_id = function(value) {
      if (!missing(value)) active_value <<- value
      active_value
    },
    perf_tracker = list(track_request = function(...) invisible(NULL), track_error = function(...) invisible(NULL)),
    api_config = list(),
    ai_processor = list(call_llm_streaming = function(...) promises::promise_resolve(list(
      success = TRUE, content = "Yanıt metni", duration = 0.01, chart_store = list()
    ))),
    tts_processor = list(synthesize_speech = function(text, voice = NULL, profile_id = NULL, ...) {
      captured_voice <<- voice
      captured_profile <<- profile_id
      promises::promise_resolve(list(success = TRUE, audio_src = "", duration = 0))
    }),
    followup_tools = list(),
    fallback_followup_tool = NULL,
    simulate_streaming_stoppable_fn = function(full_response, followups, tts_engine, tts_voice, on_start, on_complete) {
      tts_engine(full_response, tts_voice)
      invisible(NULL)
    },
    cleanup_send_message = function(...) invisible(NULL),
    abort_send_message = function(...) invisible(NULL),
    current_settings = list(selected_character = "ipek"),
    model_selected = "model",
    messages_to_process = list(),
    user_message_text = "Soru",
    user_prompt_msg = list(db_id = 1),
    chat_id_val = 1,
    current_user_id = 1,
    request_id = "req-1"
  )

  test_env$handle_streaming_tts_mode(ctx)
  for (i in seq_len(5)) later::run_now(1)

  expect_identical(captured_voice, "tr-female-1")
  expect_identical(captured_profile, "profile-ipek")
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

  # Worker'ın yazdığını taklit et: cache dosyasına GEÇERLİ bir WAV yaz.
  # (Üretilen-ses doğrulaması artık okuma yolunda uygulandığı için önbellek
  # dosyasının yapısal olarak geçerli olması gerekir.)
  tts_fixture_write_wav(plan1$cache_write_path, seconds = 1)

  # İkinci plan: aynı metin -> önbellek isabeti + doğrulanmış süre
  plan2 <- mergen_tts_prepare_speech_plan("Sabit ifade", config = cfg, profile_id = "emre")
  expect_false(is.null(plan2$cached_audio_src))
  expect_true(startsWith(plan2$cached_audio_src, "data:audio/wav;base64,"))
  expect_true(is.finite(plan2$cached_duration) && plan2$cached_duration > 0)
})

test_that("prepare_speech_plan bozuk/kesik WAV önbelleğini isabet saymaz ve siler", {
  mergen_tts_invalidate_all_profiles()
  vd <- tts_fixture_build_voice_dir(ids = c("emre"))
  cache_dir <- tempfile("tts_cache_"); dir.create(cache_dir)
  cfg <- tts_fixture_config(voice_dir = vd, cache_dir = cache_dir, cache_enabled = TRUE)

  plan1 <- mergen_tts_prepare_speech_plan("Sabit ifade", config = cfg, profile_id = "emre")
  expect_true(nzchar(plan1$cache_write_path))

  # Bozuk (WAV olmayan) baytlar yaz -> önbellek isabeti olmamalı ve dosya silinmeli.
  writeBin(as.raw(c(1, 2, 3, 4)), plan1$cache_write_path)
  expect_true(file.exists(plan1$cache_write_path))

  plan2 <- mergen_tts_prepare_speech_plan("Sabit ifade", config = cfg, profile_id = "emre")
  expect_null(plan2$cached_audio_src)
  expect_false(file.exists(plan1$cache_write_path))  # güvenle silindi
})

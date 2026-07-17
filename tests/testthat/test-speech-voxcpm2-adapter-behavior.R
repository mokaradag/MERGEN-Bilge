# ==============================================================================
# Dosya Yolu: tests/testthat/test-speech-voxcpm2-adapter-behavior.R
# Açıklama: VoxCPM2 adaptörü davranış testleri: mod çözümü, uç nokta URL'si,
#           yapılandırılabilir referans alan adları, istek gövdesi kurulumu
#           (kilitli/legacy), fail-closed gövde reddi ve gizli değer/base64
#           redaksiyonu. Gerçek uç noktaya istek atılmaz.
# ==============================================================================

testthat::test_that("ses kimlik modu ve akış modu güvenli çözülür", {
  speech_tests_source_chain()

  withr::local_envvar(MERGEN_SPEECH_VOICE_MODE = "", VOXCPM2_STREAMING_MODE = "")
  testthat::expect_identical(mergen_speech_voice_mode(), "locked_reference")
  testthat::expect_identical(mergen_voxcpm2_streaming_mode(), "buffered")

  withr::local_envvar(MERGEN_SPEECH_VOICE_MODE = "legacy_alias",
                      VOXCPM2_STREAMING_MODE = "chunked_pcm")
  testthat::expect_identical(mergen_speech_voice_mode(), "legacy_alias")
  testthat::expect_identical(mergen_voxcpm2_streaming_mode(), "chunked_pcm")

  # Bilinmeyen değerler güvenli varsayılana düşer
  withr::local_envvar(MERGEN_SPEECH_VOICE_MODE = "saçma",
                      VOXCPM2_STREAMING_MODE = "websocket")
  testthat::expect_identical(mergen_speech_voice_mode(), "locked_reference")
  testthat::expect_identical(mergen_voxcpm2_streaming_mode(), "buffered")
})

testthat::test_that("uç nokta URL'si /audio/speech biçimine tamamlanır", {
  speech_tests_source_chain()

  testthat::expect_identical(
    mergen_voxcpm2_endpoint_url("https://tts.local/v1"),
    "https://tts.local/v1/audio/speech"
  )
  testthat::expect_identical(
    mergen_voxcpm2_endpoint_url("https://tts.local/v1/audio/speech"),
    "https://tts.local/v1/audio/speech"
  )
  testthat::expect_identical(mergen_voxcpm2_endpoint_url(""), "")
})

testthat::test_that("referans alan adları ortamdan eşlenebilir", {
  speech_tests_source_chain()

  withr::local_envvar(VOXCPM2_REF_AUDIO_FIELD = "", VOXCPM2_REF_TEXT_FIELD = "")
  fields <- mergen_voxcpm2_ref_field_names()
  testthat::expect_identical(fields$audio, "ref_audio")
  testthat::expect_identical(fields$text, "ref_text")

  withr::local_envvar(VOXCPM2_REF_AUDIO_FIELD = "prompt_audio",
                      VOXCPM2_REF_TEXT_FIELD = "prompt_text")
  fields2 <- mergen_voxcpm2_ref_field_names()
  testthat::expect_identical(fields2$audio, "prompt_audio")
  testthat::expect_identical(fields2$text, "prompt_text")
})

testthat::test_that("kilitli modda gövde referans sesi + birebir metni taşır", {
  speech_tests_source_chain()
  speech_tests_reset_caches()
  root <- withr::local_tempdir()
  speech_tests_make_tree(root, with_audio = FALSE)

  payload <- mergen_speech_reference_payload("emre", root)
  testthat::expect_true(payload$ok)

  body <- mergen_voxcpm2_request_body(
    payload$profile,
    "Merhaba dünya",
    payload,
    response_format = "wav"
  )

  # Uç nokta yalnızca "default" kabul eder; persona kimliği referans yükündedir.
  testthat::expect_identical(body$voice, "default")
  testthat::expect_identical(body$input, "Merhaba dünya")
  testthat::expect_identical(body$response_format, "wav")

  ref_audio_prefix <- "data:audio/wav;base64,"

  testthat::expect_true(
    startsWith(body$ref_audio, ref_audio_prefix)
  )

  testthat::expect_identical(
    substring(
      body$ref_audio,
      nchar(ref_audio_prefix) + 1L
    ),
    payload$ref_b64
  )

  testthat::expect_identical(body$ref_text, payload$ref_text)
  testthat::expect_identical(body$speed, 1.0)
  testthat::expect_null(body$stream)

  streamed <- mergen_voxcpm2_request_body(payload$profile, "Selam", payload,
                                          response_format = "pcm", stream = TRUE)
  testthat::expect_true(streamed$stream)

  # Alan adları eşlenince gövde yeni adları kullanır
  withr::local_envvar(VOXCPM2_REF_AUDIO_FIELD = "speaker_audio",
                      VOXCPM2_REF_TEXT_FIELD = "speaker_prompt")
  mapped <- mergen_voxcpm2_request_body(
    payload$profile,
    "Selam",
    payload
  )

  testthat::expect_identical(
    mapped$speaker_audio,
    paste0(
      "data:audio/wav;base64,",
      payload$ref_b64
    )
  )

  testthat::expect_identical(
    mapped$speaker_prompt,
    payload$ref_text
  )

  testthat::expect_null(mapped$ref_audio)
})

testthat::test_that("kilitli modda referanssız gövde kurulumu hata verir (fail-closed)", {
  speech_tests_source_chain()

  withr::local_envvar(MERGEN_SPEECH_VOICE_MODE = "locked_reference")
  testthat::expect_error(
    mergen_voxcpm2_request_body(NULL, "Merhaba", reference = NULL),
    regexp = "fail-closed"
  )
})

testthat::test_that("legacy_alias modu yalnızca bilinçli geçişte eski etiketi kullanır", {
  speech_tests_source_chain()

  withr::local_envvar(MERGEN_SPEECH_VOICE_MODE = "legacy_alias")
  body <- mergen_voxcpm2_request_body(NULL, "Merhaba", reference = NULL,
                                      legacy_voice = "tr-male-1")
  testthat::expect_identical(body$voice, "tr-male-1")
  testthat::expect_null(body$ref_audio)
})

testthat::test_that("redaksiyon anahtar/bearer/base64 değerlerini gizler", {
  speech_tests_source_chain()

  long_b64 <- paste(rep("QWJjZGVmZ2hpamtsbW5vcA", 20), collapse = "")
  raw_text <- sprintf(
    '{"Authorization":"Bearer cok-gizli-token-123","ref_audio":"%s","api_key":"gizli-anahtar"}',
    long_b64
  )
  red <- mergen_voxcpm2_redact(raw_text)

  testthat::expect_false(grepl("cok-gizli-token-123", red, fixed = TRUE))
  testthat::expect_false(grepl(long_b64, red, fixed = TRUE))
  testthat::expect_false(grepl("gizli-anahtar", red, fixed = TRUE))
})

testthat::test_that("bloklayıcı sentez uç nokta yokken güvenli hata döner", {
  speech_tests_source_chain()

  res <- mergen_voxcpm2_synthesize_blocking(list(input = "x"), endpoint_url = "")
  testthat::expect_false(res$success)
  testthat::expect_match(res$error, "yapılandırılmamış")

  res2 <- mergen_voxcpm2_stream_to_file(list(input = "x"), tempfile(),
                                        endpoint_url = "")
  testthat::expect_false(res2$success)
})

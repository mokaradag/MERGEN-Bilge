# ==============================================================================
# Dosya Yolu: tests/testthat/test-speech-generator-chunking-behavior.R
# Açıklama: Statik VoxCPM2 varlık üretiminde sabit ~10 sn çıktı tavanına karşı
#           metin parçalama, PCM sınır sessizliği kırpma, noktalama-duyarlı kısa
#           geçişler, tek WAV birleştirme ve üretim hattı imzası davranışları.
#           Gerçek uç noktaya istek atılmaz.
# ==============================================================================

.speech_chunk_test_wav <- function(
    sample_rate = mergen_speech_expected_wav_profile()$sample_rate,
    leading_ms = 100L,
    active_ms = 200L,
    trailing_ms = 100L,
    amplitude = 2000L) {
  leading <- integer(as.integer(sample_rate * leading_ms / 1000L))
  active <- rep(as.integer(amplitude), as.integer(sample_rate * active_ms / 1000L))
  trailing <- integer(as.integer(sample_rate * trailing_ms / 1000L))
  samples <- c(leading, active, trailing)

  mergen_wav_build_pcm(
    n_samples = length(samples),
    sample_rate = sample_rate,
    channels = 1L,
    bits_per_sample = 16L,
    samples = samples
  )
}

.speech_chunk_test_setup <- function(root, persona = "emre") {
  speech_tests_make_tree(
    root,
    with_references = FALSE,
    with_audio = FALSE,
    personas = persona
  )
  dir.create(
    mergen_speech_voice_dir(persona, root),
    recursive = TRUE,
    showWarnings = FALSE
  )
  writeLines(
    sprintf("Merhaba, ben %s referans metniyim.", persona),
    mergen_speech_reference_text_path(persona, root)
  )
  invisible(TRUE)
}

testthat::test_that("statik metin parçalaması kesin tavanı ve metin bütünlüğünü korur", {
  speech_tests_source_generator()
  withr::local_envvar(
    VOXCPM2_ASSET_MAX_CHUNK_CHARS = "60",
    VOXCPM2_ASSET_MIN_CHUNK_CHARS = "20"
  )

  text <- paste(
    "MERGEN Bilge'ye hoş geldiniz.",
    "Ana Söyleşi'de doğrudan bir soru sorabilir, hızlı eylem kartlarından bir çalışma biçimi seçebilir",
    "ya da dosyanızı ekleyerek hemen başlayabilirsiniz."
  )
  chunks <- speech_gen_split_asset_text(text)

  testthat::expect_gt(length(chunks), 1L)
  testthat::expect_true(all(nchar(chunks) <= 60L))
  testthat::expect_identical(
    .speech_gen_normalize_space(paste(chunks, collapse = " ")),
    .speech_gen_normalize_space(text)
  )
  testthat::expect_true(endsWith(chunks[[length(chunks)]], "hemen başlayabilirsiniz."))
})

testthat::test_that(
  "uzun metin aynı referansla kısa isteklerde üretilir, kırpılır ve tek WAV olur",
  {
    speech_tests_source_generator()
    speech_tests_reset_caches()
    root <- withr::local_tempdir()
    .speech_chunk_test_setup(root)

    withr::local_envvar(
      VOXCPM2_ASSET_MAX_CHUNK_CHARS = "70",
      VOXCPM2_ASSET_MIN_CHUNK_CHARS = "20",
      VOXCPM2_ASSET_TRIM_THRESHOLD = "250",
      VOXCPM2_ASSET_TRIM_KEEP_MS = "20",
      VOXCPM2_ASSET_GAP_SENTENCE_MS = "45",
      VOXCPM2_ASSET_GAP_CLAUSE_MS = "25",
      VOXCPM2_ASSET_GAP_OTHER_MS = "30"
    )

    profile <- mergen_speech_voice_profile("emre", root)
    reference <- list(
      ok = TRUE,
      persona_id = "emre",
      ref_b64 = "QUJDREVGRw==",
      ref_text = "Merhaba referans",
      profile = profile
    )

    source_wav <- .speech_chunk_test_wav()
    sent_bodies <- list()
    fake_synth <- function(body) {
      sent_bodies[[length(sent_bodies) + 1L]] <<- body
      list(
        success = TRUE,
        audio_raw = source_wav,
        content_type = "audio/wav",
        http_status = 200L,
        error = NULL
      )
    }

    text <- paste(
      "MERGEN Bilge'ye hoş geldiniz.",
      "Ana Söyleşi'de doğrudan bir soru sorabilir, hızlı eylem kartlarından bir çalışma biçimi seçebilir",
      "ya da dosyanızı ekleyerek hemen başlayabilirsiniz."
    )
    result <- speech_gen_synthesize_wav(
      text,
      reference = reference,
      profile = profile,
      synth_fn = fake_synth
    )

    testthat::expect_true(result$success)
    testthat::expect_gt(result$chunk_count, 1L)
    testthat::expect_identical(length(sent_bodies), result$chunk_count)
    testthat::expect_true(all(vapply(
      sent_bodies,
      function(body) identical(body$voice, "default"),
      logical(1)
    )))
    testthat::expect_true(all(vapply(
      sent_bodies,
      function(body) startsWith(body$ref_audio, "data:audio/wav;base64,"),
      logical(1)
    )))
    testthat::expect_true(endsWith(
      sent_bodies[[length(sent_bodies)]]$input,
      "hemen başlayabilirsiniz."
    ))

    out <- tempfile(fileext = ".wav")
    writeBin(result$audio_raw, out)
    info <- mergen_wav_parse(out)
    testthat::expect_true(info$ok)

    # Kaynak fixture parça başına 400 ms'dir. 100+100 ms sınır sessizliği
    # kırpıldığı için birleşik sonuç, ham parçaların toplamından kısa olmalıdır;
    # buna karşın etkin 200 ms konuşma ve kontrollü geçişlerden uzun kalmalıdır.
    testthat::expect_lt(info$duration_ms, result$chunk_count * 400)
    testthat::expect_gt(info$duration_ms, result$chunk_count * 200)
  }
)

testthat::test_that("kısa metin tek istekte kalır ve WAV baytları değiştirilmez", {
  speech_tests_source_generator()
  speech_tests_reset_caches()
  root <- withr::local_tempdir()
  .speech_chunk_test_setup(root)

  profile <- mergen_speech_voice_profile("emre", root)
  reference <- list(
    ok = TRUE,
    persona_id = "emre",
    ref_b64 = "QUJDREVGRw==",
    ref_text = "Merhaba referans",
    profile = profile
  )
  source_wav <- .speech_chunk_test_wav()
  calls <- 0L
  fake_synth <- function(body) {
    calls <<- calls + 1L
    list(
      success = TRUE,
      audio_raw = source_wav,
      content_type = "audio/wav",
      http_status = 200L,
      error = NULL
    )
  }

  result <- speech_gen_synthesize_wav(
    "Kısa ve açık bir deneme cümlesi.",
    reference = reference,
    profile = profile,
    synth_fn = fake_synth
  )

  testthat::expect_true(result$success)
  testthat::expect_identical(result$chunk_count, 1L)
  testthat::expect_identical(calls, 1L)
  testthat::expect_identical(result$audio_raw, source_wav)
})

testthat::test_that(
  "üretim hattı imzası değişince WAV'lar yeniden planlanır ve manifest fail-closed olur",
  {
    speech_tests_source_generator()
    speech_tests_reset_caches()
    root <- withr::local_tempdir()
    .speech_chunk_test_setup(root)

    fake <- function(body) {
      list(
        success = TRUE,
        audio_raw = .speech_chunk_test_wav(),
        content_type = "audio/wav",
        http_status = 200L,
        error = NULL
      )
    }

    speech_gen_reference_candidate("emre", root, synth_fn = fake)
    speech_gen_reference_approve("emre", root)
    generated <- speech_gen_run("emre", root, synth_fn = fake)
    testthat::expect_identical(generated$generated, 150L)

    state <- speech_gen_state_read("emre", root)
    signature <- speech_gen_generation_pipeline_signature()
    testthat::expect_true(all(vapply(
      state,
      function(entry) identical(
        as.character(entry$generation_pipeline_signature %||% ""),
        signature
      ),
      logical(1)
    )))
    testthat::expect_identical(sum(speech_gen_plan("emre", root)$action == "skip"), 150L)

    withr::local_envvar(VOXCPM2_ASSET_GAP_SENTENCE_MS = "46")
    changed_plan <- speech_gen_plan("emre", root)
    testthat::expect_identical(sum(changed_plan$action == "generate"), 150L)
    testthat::expect_true(all(changed_plan$reason == "uretim_hatti_degisti"))

    build <- mergen_speech_manifest_build(root)
    testthat::expect_false(build$ok)
    testthat::expect_identical(build$manifest$audio_count, 0L)
    testthat::expect_true(any(grepl("üretim hattı imzası", build$problems)))
  }
)

# ==============================================================================
# Dosya Yolu: tests/testthat/test-speech-wav-behavior.R
# Açıklama: WAV ayrıştırıcı/doğrulayıcı davranış testleri. Uzantıya değil
#           gerçek RIFF/WAVE başlığına güvenilir; süre başlık verisinden
#           hesaplanır. Bozuk/kesik/yanlış biçimli dosyalar reddedilir.
# ==============================================================================

testthat::test_that("mergen_wav_build_pcm gecerli PCM WAV üretir ve ayrıştırılır", {
  speech_tests_source_chain()

  tmp <- tempfile(fileext = ".wav")
  on.exit(unlink(tmp), add = TRUE)
  writeBin(mergen_wav_build_pcm(n_samples = 16000L, sample_rate = 16000L), tmp)

  info <- mergen_wav_parse(tmp)
  testthat::expect_true(info$ok)
  testthat::expect_identical(info$format_code, 1L)
  testthat::expect_identical(info$channels, 1L)
  testthat::expect_identical(info$sample_rate, 16000L)
  testthat::expect_identical(info$bits_per_sample, 16L)
  testthat::expect_equal(info$duration_ms, 1000, tolerance = 1)
})

testthat::test_that("farklı örnekleme hızı/kanal/bit derinliği doğru çıkarılır", {
  speech_tests_source_chain()

  tmp <- tempfile(fileext = ".wav")
  on.exit(unlink(tmp), add = TRUE)
  writeBin(mergen_wav_build_pcm(n_samples = 24000L, sample_rate = 24000L,
                                channels = 2L), tmp)

  info <- mergen_wav_parse(tmp)
  testthat::expect_true(info$ok)
  testthat::expect_identical(info$sample_rate, 24000L)
  testthat::expect_identical(info$channels, 2L)
})

testthat::test_that("boş ve kesik dosyalar reddedilir", {
  speech_tests_source_chain()

  empty <- tempfile(fileext = ".wav")
  file.create(empty)
  on.exit(unlink(empty), add = TRUE)
  testthat::expect_identical(mergen_wav_parse(empty)$reason, "bos_dosya")

  short <- tempfile(fileext = ".wav")
  writeBin(as.raw(1:20), short)
  on.exit(unlink(short), add = TRUE)
  testthat::expect_identical(mergen_wav_parse(short)$reason, "kesik_dosya")

  testthat::expect_identical(mergen_wav_parse(tempfile())$reason, "dosya_yok")
})

testthat::test_that("geçersiz RIFF/WAVE imzaları ve eksik chunk'lar reddedilir", {
  speech_tests_source_chain()

  good <- mergen_wav_build_pcm(n_samples = 4000L)

  bad_riff <- good; bad_riff[1:4] <- charToRaw("XXXX")
  p1 <- tempfile(fileext = ".wav"); writeBin(bad_riff, p1)
  on.exit(unlink(p1), add = TRUE)
  testthat::expect_identical(mergen_wav_parse(p1)$reason, "riff_imzasi_gecersiz")

  bad_wave <- good; bad_wave[9:12] <- charToRaw("XXXX")
  p2 <- tempfile(fileext = ".wav"); writeBin(bad_wave, p2)
  on.exit(unlink(p2), add = TRUE)
  testthat::expect_identical(mergen_wav_parse(p2)$reason, "wave_imzasi_gecersiz")

  bad_fmt <- good; bad_fmt[13:16] <- charToRaw("xxxx")
  p3 <- tempfile(fileext = ".wav"); writeBin(bad_fmt, p3)
  on.exit(unlink(p3), add = TRUE)
  res3 <- mergen_wav_parse(p3)
  testthat::expect_false(res3$ok)

  bad_data <- good; bad_data[37:40] <- charToRaw("xxxx")
  p4 <- tempfile(fileext = ".wav"); writeBin(bad_data, p4)
  on.exit(unlink(p4), add = TRUE)
  res4 <- mergen_wav_parse(p4)
  testthat::expect_false(res4$ok)
})

testthat::test_that("kesik data chunk (başlık bütün, veri eksik) reddedilir", {
  speech_tests_source_chain()

  good <- mergen_wav_build_pcm(n_samples = 4000L)
  truncated <- good[1:(length(good) - 1000L)]
  p <- tempfile(fileext = ".wav"); writeBin(truncated, p)
  on.exit(unlink(p), add = TRUE)

  res <- mergen_wav_parse(p)
  testthat::expect_false(res$ok)
  testthat::expect_identical(res$reason, "data_kesik")
})

testthat::test_that("PCM olmayan kodlama reddedilir", {
  speech_tests_source_chain()

  good <- mergen_wav_build_pcm(n_samples = 4000L)
  # fmt chunk'taki audio_format alanı (21. bayttan itibaren) 3 = IEEE float
  non_pcm <- good; non_pcm[21] <- as.raw(3L)
  p <- tempfile(fileext = ".wav"); writeBin(non_pcm, p)
  on.exit(unlink(p), add = TRUE)

  testthat::expect_identical(mergen_wav_parse(p)$reason, "desteklenmeyen_kodlama")
})

testthat::test_that("mergen_wav_validate üretim profili uyuşmazlıklarını yakalar", {
  speech_tests_source_chain()

  p <- tempfile(fileext = ".wav")
  writeBin(mergen_wav_build_pcm(n_samples = 8000L, sample_rate = 16000L), p)
  on.exit(unlink(p), add = TRUE)

  ok <- mergen_wav_validate(p, expected = list(sample_rate = 16000L, channels = 1L,
                                               bits_per_sample = 16L))
  testthat::expect_true(ok$ok)

  bad_rate <- mergen_wav_validate(p, expected = list(sample_rate = 24000L))
  testthat::expect_identical(bad_rate$reason, "ornekleme_hizi_uyusmuyor")

  bad_ch <- mergen_wav_validate(p, expected = list(channels = 2L))
  testthat::expect_identical(bad_ch$reason, "kanal_sayisi_uyusmuyor")

  bad_bits <- mergen_wav_validate(p, expected = list(bits_per_sample = 8L))
  testthat::expect_identical(bad_bits$reason, "bit_derinligi_uyusmuyor")
})

testthat::test_that("mergen_wav_validate makul olmayan süreleri reddeder", {
  speech_tests_source_chain()

  tiny <- tempfile(fileext = ".wav")
  writeBin(mergen_wav_build_pcm(n_samples = 160L, sample_rate = 16000L), tiny)
  on.exit(unlink(tiny), add = TRUE)
  testthat::expect_identical(mergen_wav_validate(tiny)$reason, "sure_cok_kisa")

  normal <- tempfile(fileext = ".wav")
  writeBin(mergen_wav_build_pcm(n_samples = 8000L, sample_rate = 16000L), normal)
  on.exit(unlink(normal), add = TRUE)
  testthat::expect_identical(
    mergen_wav_validate(normal, max_ms = 100)$reason, "sure_cok_uzun"
  )
})

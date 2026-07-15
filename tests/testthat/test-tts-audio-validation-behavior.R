# ==============================================================================
# Dosya Yolu: tests/testthat/test-tts-audio-validation-behavior.R
# Açıklama: Üretilen-ses (TTS yanıtı) WAV yapısal doğrulama davranış testleri.
#           Sentetik bellek-içi WAV'lar kullanır (gerçek ses/ağ GEREKMEZ).
#           Sunucudan gelen bozuk/eksik/kesik WAV'ın önbelleğe yazılmadan ve
#           tarayıcıya gönderilmeden reddedilmesini kanıtlar (yarıda kesilme
#           belirtisi). Ayrıca JSON sarmalı base64 ve süre/metin makullük kuralı.
# ==============================================================================

if (!exists("tts_fixture_source_helpers", mode = "function")) {
  source(file.path(resolve_repo_root_for_tests(), "tests", "testthat", "helper_tts_voice_fixtures.R"),
         encoding = "UTF-8", local = FALSE)
}
tts_fixture_source_helpers()

test_that("geçerli PCM WAV kabul edilir ve gerçek süre döner (yapısal)", {
  raw <- tts_fixture_wav_raw(seconds = 1)
  res <- mergen_tts_validate_generated_wav(raw)
  expect_true(res$ok)
  expect_true(is.finite(res$duration) && res$duration > 0)
  expect_identical(res$channels, 1)
  expect_identical(res$sample_rate, 16000)
  expect_identical(res$bits_per_sample, 16)
})

test_that("data'dan önce ek yasal chunk (LIST) bulunan WAV kabul edilir", {
  raw <- tts_fixture_wav_raw(seconds = 1, extra_chunk_before_data = TRUE)
  res <- mergen_tts_validate_generated_wav(raw)
  expect_true(res$ok)
  expect_true(res$duration > 0)
})

test_that("geçerli WAV + makul metin geçer; makul olmayan (çok kısa) metin reddedilir", {
  # 5 sn ses. ~156 karakter metin makuldür (156/45 ~ 3.5 sn < 5 sn).
  raw5 <- tts_fixture_wav_raw(seconds = 5)
  ok_text <- paste(rep("Bu makul uzunlukta bir cumle parcasidir tamam.", 3), collapse = " ")
  expect_true(mergen_tts_validate_generated_wav(raw5, text = ok_text)$ok)

  # 0.5 sn ses ama uzun metin -> yarıda kesilmiş olabilir -> reddedilir.
  raw_short <- tts_fixture_wav_raw(seconds = 0.5)
  long_text <- paste(rep("Bu oldukca uzun bir metin parcasidir ve birkac saniye surer.", 4), collapse = " ")
  short_res <- mergen_tts_validate_generated_wav(raw_short, text = long_text)
  expect_false(short_res$ok)
  expect_true(isTRUE(short_res$retryable))
})

test_that("RIFF imzası eksikse reddedilir", {
  raw <- tts_fixture_wav_raw(seconds = 1, riff_tag = "RIFX")
  res <- mergen_tts_validate_generated_wav(raw)
  expect_false(res$ok)
})

test_that("WAVE imzası eksikse reddedilir", {
  raw <- tts_fixture_wav_raw(seconds = 1, wave_tag = "WAVX")
  res <- mergen_tts_validate_generated_wav(raw)
  expect_false(res$ok)
})

test_that("fmt chunk eksikse reddedilir", {
  raw <- tts_fixture_wav_raw(seconds = 1, include_fmt = FALSE)
  res <- mergen_tts_validate_generated_wav(raw)
  expect_false(res$ok)
})

test_that("data chunk eksikse reddedilir", {
  raw <- tts_fixture_wav_raw(seconds = 1, include_data = FALSE)
  res <- mergen_tts_validate_generated_wav(raw)
  expect_false(res$ok)
})

test_that("truncated RIFF payload (RIFF boyutu şişirilmiş) reddedilir", {
  raw <- tts_fixture_wav_raw(seconds = 0.5, riff_size_override = 5000000L)
  res <- mergen_tts_validate_generated_wav(raw)
  expect_false(res$ok)
  expect_true(isTRUE(res$retryable))
})

test_that("truncated data payload (gerçek baytlar kesilmiş) reddedilir", {
  full <- tts_fixture_wav_raw(seconds = 1)
  cut  <- full[seq_len(200L)]  # gövde kesildi
  res <- mergen_tts_validate_generated_wav(cut)
  expect_false(res$ok)
})

test_that("bildirilen data boyutu alınan bayttan büyükse reddedilir", {
  # RIFF doğru boyutta ama data chunk'ı bildirilen boyut fiziksel bayttan büyük.
  raw <- tts_fixture_wav_raw(seconds = 1, data_size_override = 9999999L,
                             riff_size_override = 36L + 32000L)
  res <- mergen_tts_validate_generated_wav(raw)
  expect_false(res$ok)
})

test_that("örnekleme hızı sıfırsa reddedilir", {
  raw <- tts_fixture_wav_raw(seconds = 1, sample_rate = 0L)
  res <- mergen_tts_validate_generated_wav(raw)
  expect_false(res$ok)
})

test_that("kanal sayısı sıfırsa reddedilir", {
  raw <- tts_fixture_wav_raw(seconds = 1, channels = 0L)
  res <- mergen_tts_validate_generated_wav(raw)
  expect_false(res$ok)
})

test_that("desteklenmeyen bit derinliği (12-bit) reddedilir", {
  raw <- tts_fixture_wav_raw(seconds = 1, bits = 12L)
  res <- mergen_tts_validate_generated_wav(raw)
  expect_false(res$ok)
})

test_that("sıfır süreli ses (data yok) reddedilir", {
  raw <- tts_fixture_wav_raw(seconds = 0)
  res <- mergen_tts_validate_generated_wav(raw)
  expect_false(res$ok)
})

test_that("geçerli JSON-sarmalı base64 WAV kabul edilir", {
  raw <- tts_fixture_wav_raw(seconds = 1)
  data_url <- paste0("data:audio/wav;base64,", base64enc::base64encode(raw))
  res <- mergen_tts_validate_generated_wav(data_url)
  expect_true(res$ok)
  expect_true(res$duration > 0)

  # Öneksiz base64 de kabul edilir.
  res2 <- mergen_tts_validate_generated_wav(base64enc::base64encode(raw))
  expect_true(res2$ok)
})

test_that("geçersiz JSON-sarmalı base64 (WAV olmayan) reddedilir", {
  data_url <- paste0("data:audio/wav;base64,", base64enc::base64encode(as.raw(1:40)))
  res <- mergen_tts_validate_generated_wav(data_url)
  expect_false(res$ok)

  # Bozuk base64 dizgesi güvenle reddedilir (exception fırlatmaz).
  res2 <- mergen_tts_validate_generated_wav("!!!not-base64!!!")
  expect_false(res2$ok)
})

test_that("streaming (data boyutu=0) WAV gerçek baytlarla süre hesaplar", {
  # data boyutu 0 bildirilmiş ama fiziksel örnekler mevcut (akış WAV'ı).
  raw <- tts_fixture_wav_raw(seconds = 1, data_size_override = 0L)
  res <- mergen_tts_validate_generated_wav(raw)
  expect_true(res$ok)
  expect_true(res$duration > 0)
})

test_that("süre/metin makullük kuralı çok kısa sesi (uzun metinde) yakalar ama hızlı konuşmayı reddetmez", {
  # Varsayılan üst hız 45 kar/sn: N karakter için makul süre >= N/45.
  # 90 karakter -> makul süre >= 2.0 sn.
  expect_true(mergen_tts_audio_duration_plausible(2.5, 90))   # 2.5 >= 2.0 -> makul
  expect_false(mergen_tts_audio_duration_plausible(1.0, 90))  # 1.0 <  2.0 -> makul değil
  # Kısa metinde (48 karakter altı) denetim UYGULANMAZ (yanlış-pozitif kaçınma).
  expect_true(mergen_tts_audio_duration_plausible(0.05, 10))
  # Gerçekçi hızlı Türkçe konuşma reddedilmez: 200 karakter ~24 kar/sn = 8.3 sn.
  expect_true(mergen_tts_audio_duration_plausible(200 / 24, 200))
  # NA süre veya sıfır süre uzun metinde makul değildir.
  expect_false(mergen_tts_audio_duration_plausible(NA_real_, 200))
  expect_false(mergen_tts_audio_duration_plausible(0, 200))
})

test_that("boş/NULL/raw-olmayan girdi güvenle reddedilir", {
  expect_false(mergen_tts_validate_generated_wav(raw(0))$ok)
  expect_false(mergen_tts_validate_generated_wav(NULL)$ok)
  expect_false(mergen_tts_validate_generated_wav("")$ok)
})

test_that("mergen_tts_decode_audio_payload data-URL önekini soyar ve hatada NULL döner", {
  raw <- tts_fixture_wav_raw(seconds = 1)
  b64 <- base64enc::base64encode(raw)
  expect_identical(mergen_tts_decode_audio_payload(paste0("data:audio/wav;base64,", b64)), raw)
  expect_identical(mergen_tts_decode_audio_payload(b64), raw)
  expect_null(mergen_tts_decode_audio_payload(""))
  expect_null(mergen_tts_decode_audio_payload("!!!"))
})

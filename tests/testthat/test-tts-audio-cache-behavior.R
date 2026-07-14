# ==============================================================================
# Dosya Yolu: tests/testthat/test-tts-audio-cache-behavior.R
# Açıklama: Üretilen-ses önbelleği davranış testleri: anahtar determinizmi ve
#           duyarlılığı, atomik okuma/yazma, bozuk girdi, TTL ve boyut temizliği,
#           kapalı önbellek. Gerçek ses üretimi GEREKMEZ (sentetik baytlar).
# ==============================================================================

if (!exists("tts_fixture_source_helpers", mode = "function")) {
  source(file.path(resolve_repo_root_for_tests(), "tests", "testthat", "helper_tts_voice_fixtures.R"),
         encoding = "UTF-8", local = FALSE)
}
tts_fixture_source_helpers()

.k <- function(...) {
  defaults <- list(model = "VoxCPM2", profile_id = "emre", profile_version = 1L,
                   wav_sha256 = "wsha", transcript_sha256 = "tsha",
                   text = "Merhaba", speed = 1.0, response_format = "wav")
  args <- modifyList(defaults, list(...))
  do.call(mergen_tts_audio_cache_key, args)
}

test_that("anahtar deterministiktir ve her belirleyici bileşene duyarlıdır", {
  base <- .k()
  expect_identical(nchar(base), 64L)
  expect_identical(base, .k())                                  # deterministik
  expect_false(identical(base, .k(model = "tts-1-hd")))         # model
  expect_false(identical(base, .k(profile_version = 2L)))       # sürüm
  expect_false(identical(base, .k(wav_sha256 = "farkli")))      # WAV sağlaması
  expect_false(identical(base, .k(transcript_sha256 = "farkli"))) # transcript sağlaması
  expect_false(identical(base, .k(speed = 1.5)))                # hız
  expect_false(identical(base, .k(text = "Baska metin")))       # metin
  expect_false(identical(base, .k(response_format = "mp3")))    # biçim
})

test_that("yazma atomiktir ve okuma birebir baytları döndürür", {
  cache_dir <- tempfile("tts_cache_"); dir.create(cache_dir)
  key <- .k()
  path <- mergen_tts_audio_cache_path(cache_dir, key, "wav")
  payload <- as.raw(c(1, 2, 3, 4, 5, 250, 0, 128))

  expect_null(mergen_tts_audio_cache_read(path))               # önce yok
  expect_true(mergen_tts_audio_cache_write(path, payload))
  expect_false(any(grepl("\\.tmp-", list.files(cache_dir))))   # geçici dosya kalmaz
  expect_identical(mergen_tts_audio_cache_read(path), payload) # birebir
})

test_that("boş bayt yazımı reddedilir ve boş dosya NULL okunur", {
  cache_dir <- tempfile("tts_cache_"); dir.create(cache_dir)
  path <- mergen_tts_audio_cache_path(cache_dir, .k(), "wav")
  expect_false(mergen_tts_audio_cache_write(path, raw(0)))
  file.create(path)  # boş dosya
  expect_null(mergen_tts_audio_cache_read(path))
})

test_that("mime ve uzantı yardımcıları biçimi doğru eşler", {
  expect_identical(mergen_tts_mime_for_format("wav"), "audio/wav")
  expect_identical(mergen_tts_mime_for_format("mp3"), "audio/mpeg")
  expect_identical(mergen_tts_format_ext("mp3"), "mp3")
  expect_identical(mergen_tts_format_ext("bilinmeyen"), "wav")  # güvenli varsayılan
  expect_true(startsWith(mergen_tts_raw_to_data_url(as.raw(1:4), "wav"), "data:audio/wav;base64,"))
})

test_that("TTL temizliği eski dosyaları siler, yeniyi korur", {
  cache_dir <- tempfile("tts_cache_"); dir.create(cache_dir)
  old_file <- file.path(cache_dir, "old.wav"); new_file <- file.path(cache_dir, "new.wav")
  writeBin(as.raw(1:10), old_file); writeBin(as.raw(1:10), new_file)
  Sys.setFileTime(old_file, Sys.time() - 40 * 86400)  # 40 gün eski

  mergen_tts_audio_cache_cleanup(cache_dir, max_mb = 512, ttl_days = 30)
  expect_false(file.exists(old_file))
  expect_true(file.exists(new_file))
})

test_that("boyut temizliği en eski dosyaları sınırın altına iner", {
  cache_dir <- tempfile("tts_cache_"); dir.create(cache_dir)
  # 3 x ~50KB dosya; sınır ~0.09 MB -> en yeni ~1 dosya kalmalı
  for (i in 1:3) {
    f <- file.path(cache_dir, sprintf("f%d.wav", i))
    writeBin(as.raw(rep(1L, 50 * 1024)), f)
    Sys.setFileTime(f, Sys.time() - (4 - i) * 3600)  # f1 en eski, f3 en yeni
  }
  mergen_tts_audio_cache_cleanup(cache_dir, max_mb = 0.09, ttl_days = 0)
  remaining <- list.files(cache_dir)
  expect_true(length(remaining) < 3)
  expect_true("f3.wav" %in% remaining)   # en yeni korunur
})

test_that("prepare_speech_plan kapalı önbellekte önbellek yolu üretmez", {
  vd <- tts_fixture_build_voice_dir(ids = c("emre"))
  cfg <- tts_fixture_config(voice_dir = vd, cache_enabled = FALSE)
  plan <- mergen_tts_prepare_speech_plan("Merhaba", config = cfg, profile_id = "emre")
  expect_identical(plan$cache_write_path, "")
  expect_null(plan$cached_audio_src)
})

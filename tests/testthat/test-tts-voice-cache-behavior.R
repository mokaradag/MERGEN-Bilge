# ==============================================================================
# Dosya Yolu: tests/testthat/test-tts-voice-cache-behavior.R
# Açıklama: VoxCPM2 ses profili bellek önbelleği davranış testleri: dedup,
#           kaynak değişiminde geçersizleme, açık geçersizleme, hata sonrası
#           kurtarma. Sentetik WAV/manifest kullanılır.
# ==============================================================================

if (!exists("tts_fixture_source_helpers", mode = "function")) {
  source(file.path(resolve_repo_root_for_tests(), "tests", "testthat", "helper_tts_voice_fixtures.R"),
         encoding = "UTF-8", local = FALSE)
}
tts_fixture_source_helpers()

test_that("aynı profil bir kez yüklenir (dedup)", {
  mergen_tts_invalidate_all_profiles()
  vd <- tts_fixture_build_voice_dir(ids = c("emre"))
  cfg <- tts_fixture_config(voice_dir = vd)

  r1 <- mergen_tts_load_profile_cached("emre", cfg)
  r2 <- mergen_tts_load_profile_cached("emre", cfg)
  r3 <- mergen_tts_load_profile_cached("emre", cfg)

  expect_true(r1$ok && r2$ok && r3$ok)
  expect_identical(mergen_tts_profile_load_count(), 1L)
})

test_that("açık geçersizleme yeniden yükleme yaptırır", {
  mergen_tts_invalidate_all_profiles()
  vd <- tts_fixture_build_voice_dir(ids = c("emre"))
  cfg <- tts_fixture_config(voice_dir = vd)

  mergen_tts_load_profile_cached("emre", cfg)
  mergen_tts_invalidate_profile("emre")
  mergen_tts_load_profile_cached("emre", cfg)
  expect_identical(mergen_tts_profile_load_count(), 2L)
})

test_that("WAV değişimi önbelleği geçersiz kılar", {
  mergen_tts_invalidate_all_profiles()
  vd <- tts_fixture_build_voice_dir(ids = c("emre"))
  cfg <- tts_fixture_config(voice_dir = vd)

  mergen_tts_load_profile_cached("emre", cfg)
  # WAV'ı farklı boyutta yeniden yaz (boyut değişimi tazeliği bozar)
  tts_fixture_write_wav(file.path(vd, "emre", "reference.wav"), seconds = 2)
  mergen_tts_load_profile_cached("emre", cfg)
  expect_identical(mergen_tts_profile_load_count(), 2L)
})

test_that("transcript değişimi önbelleği geçersiz kılar", {
  mergen_tts_invalidate_all_profiles()
  vd <- tts_fixture_build_voice_dir(ids = c("emre"))
  cfg <- tts_fixture_config(voice_dir = vd)

  mergen_tts_load_profile_cached("emre", cfg)
  writeLines(paste0(tts_fixture_transcript_text(), " Ek cumle."),
             file.path(vd, "reference_transcript_tr_v1.txt"), useBytes = TRUE)
  mergen_tts_load_profile_cached("emre", cfg)
  expect_identical(mergen_tts_profile_load_count(), 2L)
})

test_that("profil sürümü (manifest) değişimi önbelleği geçersiz kılar", {
  mergen_tts_invalidate_all_profiles()
  vd <- tts_fixture_build_voice_dir(ids = c("emre"))
  cfg <- tts_fixture_config(voice_dir = vd)

  mergen_tts_load_profile_cached("emre", cfg)
  man <- jsonlite::fromJSON(file.path(vd, "manifest.json"), simplifyVector = FALSE)
  man$profiles$emre$version <- 2L
  jsonlite::write_json(man, file.path(vd, "manifest.json"), auto_unbox = TRUE)
  res <- mergen_tts_load_profile_cached("emre", cfg)
  expect_identical(mergen_tts_profile_load_count(), 2L)
  expect_identical(res$version, 2L)
})

test_that("başarısız yükleme, dosya düzeltildikten sonra kurtarılır", {
  mergen_tts_invalidate_all_profiles()
  vd <- tempfile("vd_"); dir.create(vd)   # manifest yok -> başarısız
  cfg <- tts_fixture_config(voice_dir = vd)

  fail <- mergen_tts_load_profile_cached("emre", cfg)
  expect_false(fail$ok)

  # Manifesti oluştur (aynı dizinde) -> manifest mtime NA'dan değişir -> yeniden çöz
  tts_fixture_build_voice_dir(base_dir = vd, ids = c("emre"))
  ok <- mergen_tts_load_profile_cached("emre", cfg)
  expect_true(ok$ok)
})

test_that("bir profildeki hata diğer profillerin önbelleklenmesini engellemez", {
  mergen_tts_invalidate_all_profiles()
  vd <- tts_fixture_build_voice_dir()
  tts_fixture_write_wav(file.path(vd, "selin", "reference.wav"), seconds = 1, channels = 2L)  # boz
  cfg <- tts_fixture_config(voice_dir = vd)

  expect_false(mergen_tts_load_profile_cached("selin", cfg)$ok)
  expect_true(mergen_tts_load_profile_cached("emre", cfg)$ok)
})

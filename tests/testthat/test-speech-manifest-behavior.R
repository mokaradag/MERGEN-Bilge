# ==============================================================================
# Dosya Yolu: tests/testthat/test-speech-manifest-behavior.R
# Açıklama: speech_manifest.json üret/doğrula/yükle davranışları: sayılar,
#           süreler WAV başlığından, göreli yollar, yinelenen/sahipsiz/eksik
#           varlık redleri, kilit-özet uyuşmazlığı, bayat özet tespiti, atomik
#           yazım, süreç önbelleği, kontrollü yenileme ve manifest yokken
#           zarif davranış. Tamamı geçici dizinlerde koşar.
# ==============================================================================

testthat::test_that("manifest tam ağaçtan doğru sayılarla üretilir", {
  speech_tests_source_chain()
  speech_tests_reset_caches()
  root <- withr::local_tempdir()
  speech_tests_make_tree(root)

  build <- mergen_speech_manifest_build(root)
  testthat::expect_true(build$ok)
  testthat::expect_length(build$problems, 0L)

  m <- build$manifest
  testthat::expect_identical(as.integer(m$schema_version), 1L)
  testthat::expect_identical(as.integer(m$script_count), 150L)
  testthat::expect_identical(as.integer(m$persona_count), 5L)
  testthat::expect_identical(as.integer(m$audio_count), 750L)
  testthat::expect_setequal(names(m$personas), mergen_speech_personas())

  asset <- m$personas$emre$assets[[1]]
  testthat::expect_true(startsWith(asset$script_path, "www/speech/"))
  testthat::expect_true(startsWith(asset$audio_path, "www/speech/"))
  # Süre gerçek WAV başlığından: 8000 örnek @16kHz = 500 ms
  testthat::expect_equal(as.numeric(asset$duration_ms), 500, tolerance = 2)
  testthat::expect_identical(as.integer(asset$sample_rate), 16000L)
  testthat::expect_true(nchar(asset$script_sha256) == 64L)
  testthat::expect_true(nchar(asset$audio_sha256) == 64L)
})

testthat::test_that("doğrulama sahipsiz/eksik/yinelenen varlıkları reddeder", {
  speech_tests_source_chain()
  speech_tests_reset_caches()
  root <- withr::local_tempdir()
  speech_tests_make_tree(root)

  build <- mergen_speech_manifest_build(root)
  m <- build$manifest

  # Sahipsiz WAV
  orphan <- file.path(root, "audio", "emre", "welcome", "sahipsiz_99.wav")
  writeBin(mergen_wav_build_pcm(n_samples = 8000L), orphan)
  val <- mergen_speech_manifest_validate(m, root)
  testthat::expect_false(val$ok)
  testthat::expect_true(any(grepl("sahipsiz", val$problems)))
  unlink(orphan)

  # Eksik WAV
  victim <- file.path(root, "audio", "selin", "welcome", "welcome_01.wav")
  unlink(victim)
  val2 <- mergen_speech_manifest_validate(m, root)
  testthat::expect_false(val2$ok)
  testthat::expect_true(any(grepl("ses dosyası yok", val2$problems)))
  writeBin(mergen_wav_build_pcm(n_samples = 8000L), victim)

  # Yinelenen kimlik
  m_dup <- m
  m_dup$personas$emre$assets[[2]] <- m_dup$personas$emre$assets[[1]]
  val3 <- mergen_speech_manifest_validate(m_dup, root)
  testthat::expect_false(val3$ok)
  testthat::expect_true(any(grepl("yinelenen", val3$problems)))
})

testthat::test_that("doğrulama bilinmeyen persona/sayfa ve sessiz sayfa sesini reddeder", {
  speech_tests_source_chain()
  speech_tests_reset_caches()
  root <- withr::local_tempdir()
  speech_tests_make_tree(root)

  m <- mergen_speech_manifest_build(root)$manifest

  m_bad_persona <- m
  m_bad_persona$personas$hayalet <- m$personas$emre
  val <- mergen_speech_manifest_validate(m_bad_persona, root)
  testthat::expect_false(val$ok)

  m_bad_page <- m
  m_bad_page$personas$emre$assets[[11]]$page <- "admin_analytics"
  val2 <- mergen_speech_manifest_validate(m_bad_page, root)
  testthat::expect_false(val2$ok)
  testthat::expect_true(any(grepl("sessiz sayfa|bilinmeyen", val2$problems)))

  # Kök dışına kaçan yol
  m_escape <- m
  m_escape$personas$emre$assets[[1]]$audio_path <- "../../etc/passwd"
  val3 <- mergen_speech_manifest_validate(m_escape, root)
  testthat::expect_false(val3$ok)
  testthat::expect_true(any(grepl("dışına", val3$problems)))
})

testthat::test_that("bayat metin özeti ve kilit uyuşmazlığı tespit edilir", {
  speech_tests_source_chain()
  speech_tests_reset_caches()
  root <- withr::local_tempdir()
  expected <- speech_tests_make_tree(root)

  m <- mergen_speech_manifest_build(root)$manifest

  # Metin değişti -> özet bayat
  writeLines("Yepyeni metin çğı.", expected$script_path[1])
  val <- mergen_speech_manifest_validate(m, root)
  testthat::expect_false(val$ok)
  testthat::expect_true(any(grepl("metin özeti bayat", val$problems)))

  # Kilit değişti -> manifest bayat
  root2 <- withr::local_tempdir()
  speech_tests_make_tree(root2)
  m2 <- mergen_speech_manifest_build(root2)$manifest
  lock_path <- mergen_speech_voice_lock_path("emre", root2)
  lock <- jsonlite::fromJSON(lock_path, simplifyVector = FALSE)
  lock$created_at <- "2020-01-01T00:00:00+0000"
  writeLines(as.character(jsonlite::toJSON(lock, auto_unbox = TRUE)), lock_path)
  val2 <- mergen_speech_manifest_validate(m2, root2)
  testthat::expect_false(val2$ok)
  testthat::expect_true(any(grepl("voice-lock özeti", val2$problems)))

  # Derin özet: ses dosyası tahrifatı yalnızca deep_hashes ile yakalanır
  root3 <- withr::local_tempdir()
  speech_tests_make_tree(root3)
  m3 <- mergen_speech_manifest_build(root3)$manifest
  target <- file.path(root3, "audio", "can", "welcome", "welcome_02.wav")
  writeBin(mergen_wav_build_pcm(n_samples = 8800L), target)
  testthat::expect_true(mergen_speech_manifest_validate(m3, root3)$ok)
  val3 <- mergen_speech_manifest_validate(m3, root3, deep_hashes = TRUE)
  testthat::expect_false(val3$ok)
  testthat::expect_true(any(grepl("ses özeti bayat", val3$problems)))
})

testthat::test_that("manifest atomik yazılır ve yüklenir", {
  speech_tests_source_chain()
  speech_tests_reset_caches()
  root <- withr::local_tempdir()
  speech_tests_make_tree(root)

  m <- mergen_speech_manifest_build(root)$manifest
  path <- mergen_speech_manifest_path(root)
  mergen_speech_manifest_write(m, path)

  testthat::expect_true(file.exists(path))
  # Geçici artık dosya kalmamalı
  leftovers <- list.files(dirname(path), pattern = "\\.tmp_", full.names = TRUE)
  testthat::expect_length(leftovers, 0L)

  loaded <- mergen_speech_manifest_load(root)
  testthat::expect_true(loaded$ok)
  testthat::expect_identical(as.integer(loaded$manifest$audio_count), 750L)
})

testthat::test_that("çalışma zamanı önbelleği bir kez yükler; yenileme kontrollüdür", {
  speech_tests_source_chain()
  speech_tests_reset_caches()
  root <- withr::local_tempdir()
  speech_tests_make_tree(root)

  m <- mergen_speech_manifest_build(root)$manifest
  mergen_speech_manifest_write(m, mergen_speech_manifest_path(root))

  first <- mergen_speech_manifest_runtime(root)
  testthat::expect_true(first$ok)

  # Manifest silinse bile önbellek eski sonucu sunar (oturum başına tarama yok)
  unlink(mergen_speech_manifest_path(root))
  cached <- mergen_speech_manifest_runtime(root)
  testthat::expect_true(cached$ok)

  # Kontrollü yenileme diskteki gerçeği görür
  refreshed <- mergen_speech_manifest_refresh(root)
  testthat::expect_false(refreshed$ok)
  testthat::expect_identical(refreshed$reason, "manifest_yok")
})

testthat::test_that("manifest yokken davranış zariftir: kullanılamaz ama kırılmaz", {
  speech_tests_source_chain()
  speech_tests_reset_caches()
  root <- withr::local_tempdir()

  loaded <- mergen_speech_manifest_runtime(root)
  testthat::expect_false(loaded$ok)
  testthat::expect_identical(loaded$reason, "manifest_yok")
  testthat::expect_false(mergen_speech_persona_static_ready("emre", root))
})

testthat::test_that("persona_static_ready canlı kilit özetini manifestle karşılaştırır", {
  speech_tests_source_chain()
  speech_tests_reset_caches()
  root <- withr::local_tempdir()
  speech_tests_make_tree(root)

  m <- mergen_speech_manifest_build(root)$manifest
  mergen_speech_manifest_write(m, mergen_speech_manifest_path(root))
  testthat::expect_true(mergen_speech_persona_static_ready("emre", root))

  # Kilit dosyası değişti -> manifest bayat -> hazır DEĞİL
  lock_path <- mergen_speech_voice_lock_path("emre", root)
  lock <- jsonlite::fromJSON(lock_path, simplifyVector = FALSE)
  lock$created_at <- "2019-01-01T00:00:00+0000"
  writeLines(as.character(jsonlite::toJSON(lock, auto_unbox = TRUE)), lock_path)
  testthat::expect_false(mergen_speech_persona_static_ready("emre", root))
})

testthat::test_that("asset_lookup doğru kaydı bulur", {
  speech_tests_source_chain()
  speech_tests_reset_caches()
  root <- withr::local_tempdir()
  speech_tests_make_tree(root, personas = mergen_speech_personas())

  m <- mergen_speech_manifest_build(root)$manifest

  asset <- mergen_speech_asset_lookup(m, "ipek", "page_guidance", "files", 3L)
  testthat::expect_identical(asset$id, "files_03")
  testthat::expect_identical(asset$page, "files")

  welcome <- mergen_speech_asset_lookup(m, "emre", "welcome", NULL, 7L)
  testthat::expect_identical(welcome$id, "welcome_07")

  testthat::expect_null(mergen_speech_asset_lookup(m, "emre", "page_guidance", "olmayan", 1L))
  testthat::expect_null(mergen_speech_asset_lookup(m, "hayalet", "welcome", NULL, 1L))
})

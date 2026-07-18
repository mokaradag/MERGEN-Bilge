# ============================================================================== 
# Dosya Yolu: tests/testthat/test-speech-voice-profiles-behavior.R
# Açıklama: Persona ses kimliği fail-closed sözleşmesi: kanonik persona çözümü
#           (eski kimlikler yalnızca geçiş sınırından; bilinmeyenler NA),
#           voice-lock üret/doğrula, tahrifat tespiti, profil parmak izi ve
#           referans yükü önbelleği. Ağ/DB/Shiny gerekmez.
# ==============================================================================

testthat::test_that("kanonik persona çözümü fail-closed davranır", {
  speech_tests_source_chain()

  # Kanonik kimlikler aynen geçer
  for (p in c("emre", "selin", "deniz", "can", "ipek")) {
    testthat::expect_identical(mergen_speech_canonical_persona(p), p)
  }
  testthat::expect_identical(mergen_speech_canonical_persona("  EMRE  "), "emre")

  # Genel/eski ses takma adları PERSONA DEĞİLDİR: NA döner (Emre'ye düşmez)
  for (bad in c("tr-male-1", "tr-female-1", "default", "bilinmeyen", "voice42", "")) {
    testthat::expect_true(is.na(mergen_speech_canonical_persona(bad)),
                          info = sprintf("NA beklenirdi: %s", bad))
  }
  testthat::expect_true(is.na(mergen_speech_canonical_persona(NULL)))
  testthat::expect_true(is.na(mergen_speech_canonical_persona(NA)))
})

testthat::test_that("eski kimlikler yalnızca bilinen geçiş haritasından çevrilir", {
  speech_tests_source_chain()
  repo_root <- resolve_repo_root_for_tests()

  # Geçiş sınırı config_characters.R'de yaşar; testte yükle
  if (!exists("normalize_character_id", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "config_characters.R"),
           encoding = "UTF-8", local = globalenv())
  }

  testthat::expect_identical(mergen_speech_canonical_persona("mergen"), "emre")
  testthat::expect_identical(mergen_speech_canonical_persona("ulgen"), "selin")
  testthat::expect_identical(mergen_speech_canonical_persona("kayra"), "deniz")
  testthat::expect_identical(mergen_speech_canonical_persona("erlik"), "can")
  testthat::expect_identical(mergen_speech_canonical_persona("umay"), "ipek")

  # normalize_character_id bilinmeyeni emre'ye düşürür; ses katmanı DÜŞÜRMEZ
  testthat::expect_identical(normalize_character_id("rastgele_deger"), "emre")
  testthat::expect_true(is.na(mergen_speech_canonical_persona("rastgele_deger")))
})

testthat::test_that("beş persona profili ayrık ve tam alanlıdır", {
  speech_tests_source_chain()
  root <- withr::local_tempdir()

  fingerprints <- character(0)
  for (p in mergen_speech_personas()) {
    profile <- mergen_speech_voice_profile(p, root)
    testthat::expect_identical(profile$persona_id, p)
    testthat::expect_true(nzchar(profile$reference_wav_path))
    testthat::expect_true(nzchar(profile$voice_lock_path))
    testthat::expect_true(profile$expected_sample_rate > 0)
    testthat::expect_identical(profile$expected_channels, 1L)
    testthat::expect_identical(profile$expected_bits_per_sample, 16L)
    fingerprints <- c(fingerprints, mergen_speech_profile_identity_fingerprint(profile))
  }
  # Parmak izleri persona kimliğini içerir -> beş AYRI kimlik
  testthat::expect_identical(length(unique(fingerprints)), 5L)
})

testthat::test_that("voice-lock doğrulaması eksik dosyalarda fail-closed olur", {
  speech_tests_source_chain()
  speech_tests_reset_caches()
  root <- withr::local_tempdir()

  # Hiçbir şey yok -> kilit yok
  res <- mergen_speech_voice_lock_validate("emre", root)
  testthat::expect_false(res$ok)
  testthat::expect_identical(res$reason, "voice_lock_yok")

  payload <- mergen_speech_reference_payload("emre", root)
  testthat::expect_false(payload$ok)

  # Ağaç kurulunca doğrulama geçer
  speech_tests_make_tree(root, with_audio = FALSE)
  res2 <- mergen_speech_voice_lock_validate("emre", root)
  testthat::expect_true(res2$ok)
  testthat::expect_true(nzchar(res2$reference_text))
})

testthat::test_that("tahrif edilen referans WAV/metin özet uyuşmazlığıyla reddedilir", {
  speech_tests_source_chain()
  speech_tests_reset_caches()
  root <- withr::local_tempdir()
  speech_tests_make_tree(root, with_audio = FALSE)

  # WAV tahrifatı
  wav_path <- mergen_speech_reference_wav_path("emre", root)
  bytes <- readBin(wav_path, "raw", n = file.info(wav_path)$size)
  bytes[100] <- as.raw(255L)
  writeBin(bytes, wav_path)
  res <- mergen_speech_voice_lock_validate("emre", root)
  testthat::expect_false(res$ok)
  testthat::expect_identical(res$reason, "referans_wav_ozeti_uyusmuyor")

  # Metin tahrifatı (selin'de)
  speech_tests_write_utf8_text(
    "Değiştirilmiş referans metni.",
    mergen_speech_reference_text_path("selin", root)
  )
  res2 <- mergen_speech_voice_lock_validate("selin", root)
  testthat::expect_false(res2$ok)
  testthat::expect_identical(res2$reason, "referans_metin_ozeti_uyusmuyor")
})

testthat::test_that("kimliği etkileyen parametre değişimi kilidi geçersiz kılar", {
  speech_tests_source_chain()
  speech_tests_reset_caches()
  root <- withr::local_tempdir()
  speech_tests_make_tree(root, with_audio = FALSE)

  testthat::expect_true(mergen_speech_voice_lock_validate("deniz", root)$ok)

  withr::local_envvar(VOXCPM2_SPEED = "1.25")
  res <- mergen_speech_voice_lock_validate("deniz", root)
  testthat::expect_false(res$ok)
  testthat::expect_identical(res$reason, "profil_parmak_izi_uyusmuyor")
})

testthat::test_that("referans yükü başarıda base64 ses + birebir metin döner ve önbelleklenir", {
  speech_tests_source_chain()
  speech_tests_reset_caches()
  root <- withr::local_tempdir()
  speech_tests_make_tree(root, with_audio = FALSE)

  payload <- mergen_speech_reference_payload("can", root)
  testthat::expect_true(payload$ok)
  testthat::expect_identical(payload$persona_id, "can")
  testthat::expect_true(nchar(payload$ref_b64) > 100)
  testthat::expect_match(payload$ref_text, "can referans metniyim")

  # İkinci çağrı önbellekten aynı nesneyi döndürür
  payload2 <- mergen_speech_reference_payload("can", root)
  testthat::expect_identical(payload$ref_b64, payload2$ref_b64)
})

testthat::test_that("bozuk WAV başlıklı referans fail-closed reddedilir", {
  speech_tests_source_chain()
  speech_tests_reset_caches()
  root <- withr::local_tempdir()
  speech_tests_make_tree(root, with_audio = FALSE)

  # Kilidin özetiyle eşleşen ama başlığı bozuk dosya: özet zaten uyuşmaz;
  # burada kilit + dosyayı birlikte bozup başlık denetimini hedefliyoruz.
  wav_path <- mergen_speech_reference_wav_path("ipek", root)
  writeBin(as.raw(rep(65L, 5000L)), wav_path)

  profile <- mergen_speech_voice_profile("ipek", root)
  ref_text <- .speech_read_utf8_text(profile$reference_text_path)
  lock <- mergen_speech_voice_lock_payload(profile, wav_path, ref_text)
  writeLines(as.character(jsonlite::toJSON(lock, auto_unbox = TRUE)),
             mergen_speech_voice_lock_path("ipek", root))

  res <- mergen_speech_voice_lock_validate("ipek", root)
  testthat::expect_false(res$ok)
  testthat::expect_match(res$reason, "referans_wav_gecersiz")
})

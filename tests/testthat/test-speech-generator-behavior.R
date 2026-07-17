# ==============================================================================
# Dosya Yolu: tests/testthat/test-speech-generator-behavior.R
# Açıklama: RStudio üretici davranışları (tamamı sahte sentezle, geçici
#           dizinlerde): aday referans + onay/kilit akışı, sessiz değişim
#           reddi, bilinçli reset ve çıktı geçersizleştirme, 150/750 plan,
#           önizleme/max_files/atlama/devam, atomik yazım, yeniden deneme
#           sınıflandırması, eşzamanlılık kilidi ve gizli değer redaksiyonu.
# ==============================================================================

.speech_gen_test_fake_synth <- function(sample_rate = 16000L) {
  wav <- mergen_wav_build_pcm(n_samples = 8000L, sample_rate = sample_rate)
  function(body) {
    list(success = TRUE, audio_raw = wav, content_type = "audio/wav",
         http_status = 200L, error = NULL)
  }
}

.speech_gen_test_setup <- function(root, personas = NULL) {
  speech_tests_make_tree(root, with_references = FALSE, with_audio = FALSE)
  if (is.null(personas)) personas <- mergen_speech_personas()
  for (persona in personas) {
    dir.create(mergen_speech_voice_dir(persona, root), recursive = TRUE,
               showWarnings = FALSE)
    writeLines(sprintf("Merhaba, ben %s referans metniyim.", persona),
               mergen_speech_reference_text_path(persona, root))
  }
  invisible(TRUE)
}

testthat::test_that("metin ağacı doğrulaması 150 dosyayı ve UTF-8 bütünlüğünü denetler", {
  speech_tests_source_generator()
  speech_tests_reset_caches()
  root <- withr::local_tempdir()
  .speech_gen_test_setup(root)

  tree <- speech_gen_validate_script_tree(root)
  testthat::expect_true(tree$ok)
  testthat::expect_identical(nrow(tree$scripts), 150L)

  # Eksik metin yakalanır
  unlink(tree$scripts$script_path[10])
  tree2 <- speech_gen_validate_script_tree(root)
  testthat::expect_false(tree2$ok)
  testthat::expect_true(any(grepl("eksik", tree2$problems)))

  # Geçersiz UTF-8 yakalanır
  writeBin(as.raw(c(0x54, 0xFF, 0xFE, 0x54)), tree$scripts$script_path[10])
  tree3 <- speech_gen_validate_script_tree(root)
  testthat::expect_false(tree3$ok)
  testthat::expect_true(any(grepl("UTF-8|mojibake", tree3$problems)))
})

testthat::test_that("onaysız persona koşusu açık hatayla reddedilir", {
  speech_tests_source_generator()
  speech_tests_reset_caches()
  root <- withr::local_tempdir()
  .speech_gen_test_setup(root)

  testthat::expect_error(
    speech_gen_run("emre", root, synth_fn = .speech_gen_test_fake_synth()),
    regexp = "onaylı referans yok"
  )
})

testthat::test_that("aday -> onay -> kilit akışı; sessiz değişim reddedilir", {
  speech_tests_source_generator()
  speech_tests_reset_caches()
  root <- withr::local_tempdir()
  .speech_gen_test_setup(root)

  fake <- .speech_gen_test_fake_synth()
  cand <- speech_gen_reference_candidate("emre", root, synth_fn = fake)
  testthat::expect_true(file.exists(cand))

  speech_gen_reference_approve("emre", root)
  testthat::expect_true(file.exists(mergen_speech_voice_lock_path("emre", root)))
  testthat::expect_true(mergen_speech_voice_lock_validate("emre", root)$ok)

  # Onaylı referans reset olmadan DEĞİŞTİRİLEMEZ
  testthat::expect_error(
    speech_gen_reference_approve("emre", root),
    regexp = "reset_reference"
  )
})

testthat::test_that("persona koşusu 150 çıktı planlar; max_files/önizleme/devam çalışır", {
  speech_tests_source_generator()
  speech_tests_reset_caches()
  root <- withr::local_tempdir()
  .speech_gen_test_setup(root)

  fake <- .speech_gen_test_fake_synth()
  speech_gen_reference_candidate("selin", root, synth_fn = fake)
  speech_gen_reference_approve("selin", root)

  # Önizleme: plan var, dosya yazılmadı
  prev <- speech_gen_run("selin", root, preview = TRUE)
  testthat::expect_true(prev$preview)
  testthat::expect_identical(sum(prev$plan$action == "generate"), 150L)
  testthat::expect_length(
    list.files(file.path(root, "audio", "selin"), pattern = "\\.wav$",
               recursive = TRUE), 0L
  )

  # max_files deneme koşusu
  r1 <- speech_gen_run("selin", root, max_files = 3, synth_fn = fake)
  testthat::expect_identical(r1$generated, 3L)

  # Devam: kalan 147 üretilir, 3 geçerli mevcut atlanır
  r2 <- speech_gen_run("selin", root, synth_fn = fake)
  testthat::expect_identical(r2$generated, 147L)
  testthat::expect_identical(r2$skipped, 3L)
  testthat::expect_identical(r2$failed, 0L)

  # Tam tekrar: 150 atlanır (varsayılan üzerine yazmaz)
  r3 <- speech_gen_run("selin", root, synth_fn = fake)
  testthat::expect_identical(r3$generated, 0L)
  testthat::expect_identical(r3$skipped, 150L)

  # overwrite açıkça istenirse yeniden üretilir
  plan_ow <- speech_gen_plan("selin", root, overwrite = TRUE)
  testthat::expect_identical(sum(plan_ow$action == "generate"), 150L)
})

testthat::test_that("metin değişimi ve geçersiz mevcut WAV yeniden üretimi tetikler", {
  speech_tests_source_generator()
  speech_tests_reset_caches()
  root <- withr::local_tempdir()
  expected <- mergen_speech_expected_assets(root)
  .speech_gen_test_setup(root)

  fake <- .speech_gen_test_fake_synth()
  speech_gen_reference_candidate("deniz", root, synth_fn = fake)
  speech_gen_reference_approve("deniz", root)
  speech_gen_run("deniz", root, synth_fn = fake)

  # Metin değişti -> yalnızca o varlık üretilir
  writeLines("Güncellenmiş metin çğı.", expected$script_path[5])
  plan <- speech_gen_plan("deniz", root)
  testthat::expect_identical(sum(plan$action == "generate"), 1L)
  testthat::expect_identical(plan$reason[5], "metin_degisti")

  r <- speech_gen_run("deniz", root, synth_fn = fake)
  testthat::expect_identical(r$generated, 1L)

  # Mevcut dosya bozulursa (kesik WAV) atlanamaz
  bad_path <- plan$audio_path[8]
  writeBin(as.raw(1:16), bad_path)
  plan2 <- speech_gen_plan("deniz", root)
  testthat::expect_identical(plan2$action[8], "generate")
  testthat::expect_match(plan2$reason[8], "wav_gecersiz")
})

testthat::test_that("referans reset persona çıktılarının tamamını geçersiz kılar", {
  speech_tests_source_generator()
  speech_tests_reset_caches()
  root <- withr::local_tempdir()
  .speech_gen_test_setup(root)

  fake <- .speech_gen_test_fake_synth()
  speech_gen_reference_candidate("can", root, synth_fn = fake)
  speech_gen_reference_approve("can", root)
  speech_gen_run("can", root, synth_fn = fake)

  testthat::expect_identical(sum(speech_gen_plan("can", root)$action == "skip"), 150L)

  # Yeni aday + bilinçli reset
  new_wav_synth <- function(body) {
    list(success = TRUE,
         audio_raw = mergen_wav_build_pcm(n_samples = 9600L, sample_rate = 16000L),
         content_type = "audio/wav", http_status = 200L, error = NULL)
  }
  speech_gen_reference_candidate("can", root, synth_fn = new_wav_synth)
  speech_gen_reference_approve("can", root, reset_reference = TRUE)

  plan <- speech_gen_plan("can", root)
  testthat::expect_identical(sum(plan$action == "generate"), 150L)
})

testthat::test_that(
  paste0("referans reset eski WAV'ları diskten siler; yarım kalan yeniden ",
         "üretim manifest yayınını fail-closed biçimde engeller"),
  {
    speech_tests_source_generator()
    speech_tests_reset_caches()
    root <- withr::local_tempdir()
    .speech_gen_test_setup(root)

    fake <- .speech_gen_test_fake_synth()
    speech_gen_reference_candidate("can", root, synth_fn = fake)
    speech_gen_reference_approve("can", root)
    speech_gen_run("can", root, synth_fn = fake)

    plan_before <- speech_gen_plan("can", root)
    testthat::expect_identical(sum(plan_before$action == "skip"), 150L)
    testthat::expect_true(all(file.exists(plan_before$audio_path)))

    # Bilinçli reset: eski WAV'lar diskten silinmelidir (yeni referansla asla
    # karışmasınlar diye), yeniden üretim henüz yapılmamış olsa bile.
    new_wav_synth <- function(body) {
      list(success = TRUE,
           audio_raw = mergen_wav_build_pcm(n_samples = 9600L, sample_rate = 16000L),
           content_type = "audio/wav", http_status = 200L, error = NULL)
    }
    speech_gen_reference_candidate("can", root, synth_fn = new_wav_synth)
    speech_gen_reference_approve("can", root, reset_reference = TRUE)

    testthat::expect_false(any(file.exists(plan_before$audio_path)))

    # Yeniden üretim ATLANIRSA/kesintiye uğrarsa, manifest üretimi eksik-dosya
    # hatasıyla GÜVENLİ biçimde engellenmelidir; eski ses hiçbir zaman yeni
    # voice-lock kimliği altında yayınlanamaz (bkz. Codex P2 incelemesi).
    build <- mergen_speech_manifest_build(root)
    testthat::expect_false(build$ok)
    testthat::expect_true(any(grepl("can.*dosya_yok", build$problems)))
  }
)

testthat::test_that("atomik yazım: geçersiz sentez çıktısı hedefe asla ulaşmaz", {
  speech_tests_source_generator()
  speech_tests_reset_caches()
  root <- withr::local_tempdir()

  final_path <- file.path(root, "audio", "emre", "welcome", "welcome_01.wav")
  res <- speech_gen_write_wav_atomic(as.raw(1:32), final_path)
  testthat::expect_false(res$ok)
  testthat::expect_false(file.exists(final_path))
  testthat::expect_length(
    list.files(dirname(final_path), pattern = "\\.tmp_"), 0L
  )

  ok <- speech_gen_write_wav_atomic(mergen_wav_build_pcm(n_samples = 8000L), final_path)
  testthat::expect_true(ok$ok)
  testthat::expect_true(file.exists(final_path))
})

testthat::test_that("yeniden deneme sınıflandırması geçici/kalıcı ayrımını yapar", {
  speech_tests_source_generator()

  testthat::expect_true(speech_gen_should_retry(429L))
  testthat::expect_true(speech_gen_should_retry(500L))
  testthat::expect_true(speech_gen_should_retry(502L))
  testthat::expect_true(speech_gen_should_retry(503L))
  testthat::expect_true(speech_gen_should_retry(504L))
  testthat::expect_true(speech_gen_should_retry(NA_integer_, "Connection timed out"))

  # Kimlik/istek hataları YENİDEN DENENMEZ
  testthat::expect_false(speech_gen_should_retry(400L))
  testthat::expect_false(speech_gen_should_retry(401L))
  testthat::expect_false(speech_gen_should_retry(403L))
  testthat::expect_false(speech_gen_should_retry(422L))

  # Sınırlı üstel geri çekilme
  testthat::expect_identical(speech_gen_backoff_secs(1), 2)
  testthat::expect_identical(speech_gen_backoff_secs(2), 4)
  testthat::expect_identical(speech_gen_backoff_secs(10), 30)
})

testthat::test_that("geçici hata sınırlı denemeyle aşılır; kalıcı hata hemen döner", {
  speech_tests_source_generator()
  speech_tests_reset_caches()
  root <- withr::local_tempdir()
  .speech_gen_test_setup(root, personas = "emre")

  calls <- 0L
  flaky <- function(body) {
    calls <<- calls + 1L
    if (calls < 3L) {
      return(list(success = FALSE, audio_raw = NULL, content_type = NA,
                  http_status = 503L, error = "geçici"))
    }
    list(success = TRUE, audio_raw = mergen_wav_build_pcm(n_samples = 8000L),
         content_type = "audio/wav", http_status = 200L, error = NULL)
  }

  profile <- mergen_speech_voice_profile("emre", root)
  fake_reference <- list(ok = TRUE, persona_id = "emre",
                         ref_b64 = "QUJDREVGRw==", ref_text = "Merhaba referans")
  slept <- numeric(0)
  res <- speech_gen_synthesize_wav("Merhaba", reference = fake_reference,
                                   profile = profile,
                                   max_attempts = 3, synth_fn = flaky,
                                   sleep_fn = function(s) slept <<- c(slept, s))
  testthat::expect_true(res$success)
  testthat::expect_identical(calls, 3L)
  # Üstel geri çekilme sıralaması: 2 sn, 4 sn
  testthat::expect_identical(slept, c(2, 4))

  # Kalıcı 401: tek çağrı, yeniden deneme yok
  calls2 <- 0L
  auth_fail <- function(body) {
    calls2 <<- calls2 + 1L
    list(success = FALSE, audio_raw = NULL, content_type = NA,
         http_status = 401L, error = "Unauthorized")
  }
  res2 <- speech_gen_synthesize_wav("Merhaba", reference = fake_reference,
                                    profile = profile,
                                    max_attempts = 3, synth_fn = auth_fail)
  testthat::expect_false(res2$success)
  testthat::expect_identical(calls2, 1L)
})

testthat::test_that("eşzamanlılık kilidi ikinci üreticiyi engeller ve bırakılabilir", {
  speech_tests_source_generator()
  root <- withr::local_tempdir()

  speech_gen_acquire_lock(root)
  testthat::expect_error(speech_gen_acquire_lock(root), regexp = "kilidi aktif")
  speech_gen_release_lock(root)
  testthat::expect_no_error(speech_gen_acquire_lock(root))
  speech_gen_release_lock(root)
})

testthat::test_that("üretici hata metinleri gizli değer/base64 sızdırmaz", {
  speech_tests_source_generator()
  speech_tests_reset_caches()
  root <- withr::local_tempdir()
  .speech_gen_test_setup(root, personas = "emre")

  fake <- .speech_gen_test_fake_synth()
  speech_gen_reference_candidate("emre", root, synth_fn = fake)
  speech_gen_reference_approve("emre", root)

  secret_err <- function(body) {
    list(success = FALSE, audio_raw = NULL, content_type = NA,
         http_status = 400L,
         error = 'istek reddedildi: {"api_key":"super-gizli-999","Authorization":"Bearer tok-abc"}')
  }
  res <- speech_gen_run("emre", root, max_files = 1, synth_fn = secret_err)
  testthat::expect_identical(res$failed, 1L)
  joined <- paste(res$failed_ids, collapse = " ")
  testthat::expect_false(grepl("super-gizli-999", joined, fixed = TRUE))
  testthat::expect_false(grepl("tok-abc", joined, fixed = TRUE))
})

testthat::test_that("durum dosyası atomik yazılır ve kesinti sonrası devam sağlar", {
  speech_tests_source_generator()
  speech_tests_reset_caches()
  root <- withr::local_tempdir()

  state <- list(welcome_01 = list(script_sha256 = "abc"))
  speech_gen_state_write("emre", state, root)
  path <- mergen_speech_generation_state_path("emre", root)
  testthat::expect_true(file.exists(path))
  testthat::expect_length(list.files(dirname(path), pattern = "\\.tmp_"), 0L)

  back <- speech_gen_state_read("emre", root)
  testthat::expect_identical(back$welcome_01$script_sha256, "abc")

  # Bozuk durum dosyası boş listeye düşer (koşuyu kırmaz)
  writeLines("{bozuk json", path)
  testthat::expect_identical(speech_gen_state_read("emre", root), list())
})

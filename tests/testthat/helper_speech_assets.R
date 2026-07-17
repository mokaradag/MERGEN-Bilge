# ==============================================================================
# Dosya Yolu: tests/testthat/helper_speech_assets.R
# Açıklama: Hibrit konuşma katmanı testleri için ortak yükleyici ve geçici
#           sahte varlık ağacı kurucuları. Gerçek VoxCPM2 uç noktasına ASLA
#           istek atılmaz; WAV fixture'ları mergen_wav_build_pcm ile üretilir.
# ==============================================================================

speech_tests_source_chain <- function() {
  if (exists("mergen_speech_manifest_build", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }

  root <- resolve_repo_root_for_tests()

  if (!exists("%||%", envir = globalenv(), inherits = TRUE)) {
    assign("%||%", function(a, b) if (is.null(a)) b else a, envir = globalenv())
  }

  files <- c(
    "R/config_speech_assets.R",
    "R/config_speech_asset_paths.R",
    "R/helpers_speech_wav.R",
    "R/helpers_speech_voice_profiles.R",
    "R/helpers_speech_voxcpm2_adapter.R",
    "R/helpers_speech_manifest.R",
    "R/helpers_speech_playback_policy.R",
    "R/helpers_speech_warmup.R"
  )
  for (f in files) {
    source(file.path(root, f), encoding = "UTF-8", local = globalenv())
  }

  invisible(TRUE)
}

speech_tests_source_generator <- function() {
  speech_tests_source_chain()
  if (exists("speech_gen_plan", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "tools", "speech",
              "helpers_speech_generator.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

# Geçici kökte ortak metin ağacı + (isteğe bağlı) referans/kilit/WAV kur.
# Dönen kök MERGEN_SPEECH_ROOT olarak ayarlanmaz; testler withr ile ayarlar.
speech_tests_make_tree <- function(root,
                                   with_references = TRUE,
                                   with_audio = TRUE,
                                   personas = NULL,
                                   sample_rate = 16000L) {
  speech_tests_source_chain()
  if (is.null(personas)) personas <- mergen_speech_personas()

  expected <- mergen_speech_expected_assets(root)
  for (i in seq_len(nrow(expected))) {
    dir.create(dirname(expected$script_path[i]), recursive = TRUE, showWarnings = FALSE)
    writeLines(sprintf("Deneme metni %s: dosyalarınızı buradan yönetin.", expected$id[i]),
               expected$script_path[i])
  }

  wav_bytes <- mergen_wav_build_pcm(n_samples = 8000L, sample_rate = sample_rate)

  if (isTRUE(with_references)) {
    for (persona in personas) {
      dir.create(mergen_speech_voice_dir(persona, root), recursive = TRUE,
                 showWarnings = FALSE)
      writeLines(sprintf("Merhaba, ben %s referans metniyim.", persona),
                 mergen_speech_reference_text_path(persona, root))
      writeBin(wav_bytes, mergen_speech_reference_wav_path(persona, root))

      profile <- mergen_speech_voice_profile(persona, root)
      lock <- mergen_speech_voice_lock_payload(profile)
      writeLines(
        as.character(jsonlite::toJSON(lock, auto_unbox = TRUE)),
        mergen_speech_voice_lock_path(persona, root)
      )
    }
  }

  if (isTRUE(with_audio)) {
    for (persona in personas) {
      for (i in seq_len(nrow(expected))) {
        page <- if (is.na(expected$page[i])) NULL else expected$page[i]
        ap <- mergen_speech_audio_path(persona, expected$scenario[i], page,
                                       expected$variant[i], root)
        dir.create(dirname(ap), recursive = TRUE, showWarnings = FALSE)
        writeBin(wav_bytes, ap)
      }
    }
  }

  invisible(expected)
}

# Önbellekleri sıfırla (kök değişimlerinde bayat durum kalmasın)
speech_tests_reset_caches <- function() {
  speech_tests_source_chain()
  mergen_speech_manifest_cache_clear()
  mergen_speech_reference_cache_clear()
  invisible(TRUE)
}

# Sahte oturum: userData ortamı olan minimal env (mergen_speech_state için)
speech_tests_fake_session <- function() {
  session <- new.env(parent = emptyenv())
  session$userData <- new.env(parent = emptyenv())
  session$token <- "test_token_123"
  session
}

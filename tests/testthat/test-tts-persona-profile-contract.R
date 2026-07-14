# ==============================================================================
# Dosya Yolu: tests/testthat/test-tts-persona-profile-contract.R
# Açıklama: Persona -> VoxCPM2 ses profili eşleme sözleşmesi. Beş persona beş
#           ayrı profile çözülür; hiçbiri üretim değeri olarak tr-male-1 /
#           tr-female-1 / tts-1-hd taşımaz.
# ==============================================================================

.persona_profile_root <- resolve_repo_root_for_tests()
if (!exists("get_characters_data", mode = "function")) {
  source(file.path(.persona_profile_root, "R", "config_characters.R"), encoding = "UTF-8", local = globalenv())
}
if (!exists("mergen_tts_profile_for_character", mode = "function")) {
  source(file.path(.persona_profile_root, "R", "helpers_tts_voice_config.R"), encoding = "UTF-8", local = globalenv())
}

.expected_persona_profiles <- c(emre = "emre", selin = "selin", deniz = "deniz", can = "can", ipek = "ipek")

test_that("her persona tts_profile alanına sahiptir", {
  chars <- get_characters_data()
  for (persona in chars$styles) {
    expect_true("tts_profile" %in% names(persona),
                info = paste0("Persona '", persona$id, "' tts_profile alanını içermeli"))
    expect_true(nzchar(persona$tts_profile))
  }
})

test_that("beş persona beş AYRI profile eşlenir", {
  chars <- get_characters_data()
  profiles <- vapply(chars$styles, function(x) x$tts_profile, character(1))
  expect_length(profiles, 5L)
  expect_length(unique(profiles), 5L)
})

test_that("persona -> profil eşlemesi tam olarak beklenendir", {
  for (id in names(.expected_persona_profiles)) {
    rec <- get_character_record(id)
    expect_identical(rec$tts_profile, unname(.expected_persona_profiles[[id]]))
    expect_identical(mergen_tts_profile_for_character(id), unname(.expected_persona_profiles[[id]]))
  }
})

test_that("hiçbir persona üretim değeri olarak eski jenerik sesleri taşımaz", {
  chars <- get_characters_data()
  for (persona in chars$styles) {
    expect_false(identical(persona$tts_voice, "tr-male-1"),
                 info = paste0("Persona '", persona$id, "' tr-male-1 taşımamalı"))
    expect_false(identical(persona$tts_voice, "tr-female-1"),
                 info = paste0("Persona '", persona$id, "' tr-female-1 taşımamalı"))
    expect_false(identical(persona$tts_profile, "tr-male-1"))
    expect_false(identical(persona$tts_profile, "tr-female-1"))
    # Jenerik yedek ses "default" olmalı
    expect_identical(persona$tts_voice, "default")
  }
})

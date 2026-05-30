# ==============================================================================
# Dosya Yolu: tests/testthat/test-quick-action-intro-name-behavior.R
# Açıklama: resolve_quick_action_user_name() davranışsal testleri. Kimlik
#           kaynak önceliği, ilk-isim ayıklama (çok kelimeli adda ilk kelime)
#           ve eksik kimlik davranışı doğrulanır. Pozitif senaryolar session/
#           settings öncelik sırasına dayandığından global user_config'e bağlı
#           değildir. DB/LLM/tarayıcı gerekmez.
# ==============================================================================

.quick_action_intro_source_once <- function() {
  if (exists("resolve_quick_action_user_name", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }

  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_quick_action_intro_messages.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  invisible(TRUE)
}

testthat::test_that("resolve_quick_action_user_name session first_name'i önceliklendirir", {
  .quick_action_intro_source_once()

  fake_session <- list(
    userData = list(user_config = list(first_name = "Mehmet"))
  )

  testthat::expect_identical(
    resolve_quick_action_user_name(session = fake_session, settings_data = NULL),
    "Mehmet"
  )
})

testthat::test_that("resolve_quick_action_user_name session yoksa settings first_name'e düşer", {
  .quick_action_intro_source_once()

  fake_settings <- list(user_config = list(first_name = "Zeynep"))

  # session = NULL iken aday #1 boş; aday #2 (settings first_name) seçilmeli.
  testthat::expect_identical(
    resolve_quick_action_user_name(session = NULL, settings_data = fake_settings),
    "Zeynep"
  )
})

testthat::test_that("resolve_quick_action_user_name çok kelimeli addan ilk kelimeyi alır", {
  .quick_action_intro_source_once()

  fake_session <- list(
    userData = list(user_config = list(first_name = "Ahmet Veli"))
  )

  testthat::expect_identical(
    resolve_quick_action_user_name(session = fake_session),
    "Ahmet"
  )
})

testthat::test_that("resolve_quick_action_user_name boşlukları kırpar", {
  .quick_action_intro_source_once()

  fake_session <- list(
    userData = list(user_config = list(first_name = "  Elif  "))
  )

  testthat::expect_identical(
    resolve_quick_action_user_name(session = fake_session),
    "Elif"
  )
})

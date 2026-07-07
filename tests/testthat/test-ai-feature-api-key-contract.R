# ==============================================================================
# Dosya Yolu: tests/testthat/test-ai-feature-api-key-contract.R
# Açıklama:   Sohbet dışı özelliklerin kişisel/kurumsal API anahtarı çözümleme
#             sözleşmesini doğrular.
# ==============================================================================

source(
  file.path(repo_root_for_tests, "R", "helpers_api_key_identity.R"),
  encoding = "UTF-8",
  local = globalenv()
)

source(
  file.path(repo_root_for_tests, "R", "helpers_feature_api_key.R"),
  encoding = "UTF-8",
  local = globalenv()
)

.read_static_utf8_lines <- function(path) {
  if (!exists("read_text_lines_utf8", mode = "function", inherits = TRUE)) {
    source(file.path(resolve_repo_root_for_tests(), "R", "utils_text_encoding.R"), encoding = "UTF-8")
  }
  read_text_lines_utf8(path)
}

.make_feature_api_key_session <- function(auth_initialized = TRUE,
                                          system_username = "user_a",
                                          ai_api_key = NULL,
                                          ai_api_key_owner = NULL) {
  user_data <- new.env(parent = emptyenv())
  user_data$auth_initialized <- auth_initialized
  user_data$system_username <- system_username
  user_data$user_id <- 42L
  user_data$auth_source <- "keycloak"
  user_data$user_identity <- list(username = system_username)
  user_data$user_config <- list(KullaniciAdi = system_username)

  if (!is.null(ai_api_key)) {
    user_data$ai_api_key <- ai_api_key
  }

  if (!is.null(ai_api_key_owner)) {
    user_data$ai_api_key_owner <- ai_api_key_owner
  }

  list(userData = user_data)
}

.with_default_api_key_env <- function(code) {
  old_env <- Sys.getenv(
    c(
      "MERGEN_ALLOW_DEFAULT_API_KEY",
      "MERGEN_REQUIRE_PERSONAL_API_KEY",
      "MERGEN_DEFAULT_API_KEY"
    ),
    unset = NA_character_
  )

  on.exit({
    for (nm in names(old_env)) {
      if (is.na(old_env[[nm]])) {
        Sys.unsetenv(nm)
      } else {
        do.call(
          Sys.setenv,
          as.list(stats::setNames(old_env[[nm]], nm))
        )
      }
    }
  }, add = TRUE)

  Sys.setenv(
    MERGEN_ALLOW_DEFAULT_API_KEY = "TRUE",
    MERGEN_REQUIRE_PERSONAL_API_KEY = "FALSE",
    MERGEN_DEFAULT_API_KEY = "test-default-key"
  )

  force(code)
}

test_that("özellik anahtarı kişisel anahtarı kurum ve servis anahtarına tercih eder", {
  .with_default_api_key_env({
    session <- .make_feature_api_key_session(
      system_username = "user_a"
    )

    mb_api_key_set_session_key(
      session,
      "test-personal-key",
      owner = list(username = "user_a")
    )

    key <- mb_api_key_get_feature_key_value(
      session = session,
      service_key = "test-service-key",
      fallback_key = "test-legacy-key",
      require_auth = TRUE,
      prefer_service_key_after_personal = TRUE
    )

    expect_equal(key, "test-personal-key")
  })
})

test_that("TTS servis anahtarı kişisel anahtar yokken kurum anahtarından önce gelir", {
  .with_default_api_key_env({
    session <- .make_feature_api_key_session(
      system_username = "user_without_personal_key"
    )

    key <- mb_api_key_get_feature_key_value(
      session = session,
      service_key = "test-tts-service-key",
      fallback_key = "test-legacy-key",
      require_auth = TRUE,
      prefer_service_key_after_personal = TRUE
    )

    expect_equal(key, "test-tts-service-key")
  })
})

test_that("kişisel ve servis anahtarı yoksa izinli kurum anahtarı döner", {
  .with_default_api_key_env({
    session <- .make_feature_api_key_session(
      system_username = "user_without_personal_key"
    )

    key <- mb_api_key_get_feature_key_value(
      session = session,
      service_key = "",
      fallback_key = "test-legacy-key",
      require_auth = TRUE,
      prefer_service_key_after_personal = FALSE
    )

    expect_equal(key, "test-default-key")
  })
})

test_that("kurum anahtarı yoksa eski fallback anahtar kullanılabilir", {
  old_env <- Sys.getenv(
    c(
      "MERGEN_ALLOW_DEFAULT_API_KEY",
      "MERGEN_REQUIRE_PERSONAL_API_KEY",
      "MERGEN_DEFAULT_API_KEY"
    ),
    unset = NA_character_
  )

  on.exit({
    for (nm in names(old_env)) {
      if (is.na(old_env[[nm]])) {
        Sys.unsetenv(nm)
      } else {
        do.call(
          Sys.setenv,
          as.list(stats::setNames(old_env[[nm]], nm))
        )
      }
    }
  }, add = TRUE)

  Sys.setenv(
    MERGEN_ALLOW_DEFAULT_API_KEY = "FALSE",
    MERGEN_REQUIRE_PERSONAL_API_KEY = "FALSE",
    MERGEN_DEFAULT_API_KEY = "test-default-key"
  )

  session <- .make_feature_api_key_session(
    system_username = "user_without_personal_key"
  )

  key <- mb_api_key_get_feature_key_value(
    session = session,
    service_key = "",
    fallback_key = "test-legacy-key",
    require_auth = TRUE,
    prefer_service_key_after_personal = FALSE
  )

  expect_equal(key, "test-legacy-key")
})

test_that("TTS ve AI Uzman doğrudan oturum anahtarı okumaz", {
  tts_lines <- .read_static_utf8_lines(file.path(repo_root_for_tests, "R", "module_tts.R"))

  ai_expert_lines <- .read_static_utf8_lines(file.path(repo_root_for_tests, "R", "server_ai_expert_handlers.R"))

  expect_true(any(grepl("mb_api_key_get_feature_key_value\\(", tts_lines)))
  expect_true(any(grepl("mb_api_key_get_feature_key_value\\(", ai_expert_lines)))

  expect_false(any(grepl("session\\$userData\\$ai_api_key", tts_lines)))
  expect_false(any(grepl("session\\$userData\\$ai_api_key", ai_expert_lines)))
})

test_that("özellik anahtarı helper'ı manifestte TTS ve AI Uzman modüllerinden önce yüklenir", {
  manifest_lines <- .read_static_utf8_lines(file.path(repo_root_for_tests, "R", "config_source_manifest.R"))

  helper_pos <- grep("\"R/helpers_feature_api_key\\.R\"", manifest_lines)
  ai_expert_pos <- grep("\"R/server_ai_expert_handlers\\.R\"", manifest_lines)
  tts_pos <- grep("\"R/module_tts\\.R\"", manifest_lines)

  expect_length(helper_pos, 1)
  expect_length(ai_expert_pos, 1)
  expect_length(tts_pos, 1)

  expect_lt(helper_pos, ai_expert_pos)
  expect_lt(helper_pos, tts_pos)
})

# ==============================================================================
# Dosya Yolu: tests/testthat/test-api-key-identity-isolation-contract.R
# Açıklama:   Kişisel API anahtarlarının yalnızca doğrulanmış uygulama
#             kullanıcısına bağlandığını ve paylaşımlı OS kullanıcısına
#             düşülmediğini doğrular.
# ==============================================================================

source(
  file.path(repo_root_for_tests, "R", "helpers_api_key_identity.R"),
  encoding = "UTF-8",
  local = globalenv()
)

.make_api_key_identity_session <- function(auth_initialized = TRUE,
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

test_that("API anahtarı sahibi SSO kimliği hazır olmadan çözümlenmez", {
  session <- .make_api_key_identity_session(
    auth_initialized = FALSE,
    system_username = "user_a"
  )

  expect_null(mb_api_key_resolve_owner(session, require_auth = TRUE))
})

test_that("API anahtarı sahibi doğrulanmış uygulama kullanıcısından çözümlenir", {
  session <- .make_api_key_identity_session(
    auth_initialized = TRUE,
    system_username = "user_a"
  )

  owner <- mb_api_key_resolve_owner(session, require_auth = TRUE)

  expect_type(owner, "list")
  expect_equal(owner$username, "user_a")
  expect_equal(owner$user_id, 42L)
  expect_equal(owner$auth_source, "keycloak")
})

test_that("oturumdaki API anahtarı yalnızca aynı kullanıcı sahibine aitse döner", {
  session <- .make_api_key_identity_session(
    auth_initialized = TRUE,
    system_username = "user_a"
  )

  mb_api_key_set_session_key(session, "test-key-user-a", owner = list(username = "user_a"))

  expect_equal(
    mb_api_key_get_session_key(session, require_auth = TRUE),
    "test-key-user-a"
  )
})

test_that("farklı kullanıcıya ait oturum anahtarı temizlenir ve kullanılmaz", {
  session <- .make_api_key_identity_session(
    auth_initialized = TRUE,
    system_username = "user_b",
    ai_api_key = "test-key-user-a",
    ai_api_key_owner = "user_a"
  )

  expect_equal(
    mb_api_key_get_session_key(session, require_auth = TRUE),
    ""
  )

  expect_false(exists("ai_api_key", envir = session$userData, inherits = FALSE))
  expect_false(exists("ai_api_key_owner", envir = session$userData, inherits = FALSE))
})

test_that("API anahtarı modülleri Sys.info kullanıcısına fallback yapmaz", {
  module_api_key_lines <- readLines(
    file.path(repo_root_for_tests, "R", "module_api_key.R"),
    warn = FALSE,
    encoding = "UTF-8"
  )

  settings_lines <- readLines(
    file.path(repo_root_for_tests, "R", "module_settings_yapilandirma.R"),
    warn = FALSE,
    encoding = "UTF-8"
  )

  forbidden_pattern <- "Sys\\.info\\(\\)\\[\\[\"user\"\\]\\]"

  expect_false(any(grepl(forbidden_pattern, module_api_key_lines)))
  expect_false(any(grepl(forbidden_pattern, settings_lines)))
})

test_that("API anahtarı helper manifestte modüllerden önce yüklenir", {
  manifest_lines <- readLines(
    file.path(repo_root_for_tests, "R", "config_source_manifest.R"),
    warn = FALSE,
    encoding = "UTF-8"
  )

  helper_pos <- grep("\"R/helpers_api_key_identity\\.R\"", manifest_lines)
  api_module_pos <- grep("\"R/module_api_key\\.R\"", manifest_lines)
  settings_module_pos <- grep("\"R/module_settings_yapilandirma\\.R\"", manifest_lines)

  expect_length(helper_pos, 1)
  expect_length(api_module_pos, 1)
  expect_length(settings_module_pos, 1)

  expect_lt(helper_pos, api_module_pos)
  expect_lt(helper_pos, settings_module_pos)
})

test_that("LLM çağrı yolları sahiplik doğrulayan etkin API anahtarı helper'ını kullanır", {
  send_message_lines <- readLines(
    file.path(repo_root_for_tests, "R", "server_send_message.R"),
    warn = FALSE,
    encoding = "UTF-8"
  )

  summarization_lines <- readLines(
    file.path(repo_root_for_tests, "R", "server_handler_summarization.R"),
    warn = FALSE,
    encoding = "UTF-8"
  )

  ai_processing_lines <- readLines(
    file.path(repo_root_for_tests, "R", "module_ai_processing.R"),
    warn = FALSE,
    encoding = "UTF-8"
  )

  # send_message hızlı yol için sahiplik doğrulayan ÖNBELLEKLİ etkin anahtar
  # yardımcısını kullanır; bu yardımcı kendi içinde mb_api_key_get_effective_key'e
  # delege eder (önbellek ıskası/sahip değişiminde tam çözümleme + clear_on_mismatch).
  expect_true(any(grepl(
    "mb_api_key_get_cached_for_send\\(|mb_api_key_get_effective_key\\(",
    send_message_lines
  )))
  expect_true(any(grepl("mb_api_key_get_effective_key_value\\(", summarization_lines)))
  expect_true(any(grepl("mb_api_key_get_effective_key_value\\(", ai_processing_lines)))

  expect_false(any(grepl("session\\$userData\\$ai_api_key", send_message_lines, fixed = TRUE)))
  expect_false(any(grepl("ctx\\$session\\$userData\\$ai_api_key", summarization_lines, fixed = TRUE)))
})

test_that("etkin API anahtarı kişisel anahtarı varsayılan kurum anahtarına tercih eder", {
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

  session <- .make_api_key_identity_session(
    auth_initialized = TRUE,
    system_username = "user_a"
  )

  mb_api_key_set_session_key(
    session,
    "test-personal-key",
    owner = list(username = "user_a")
  )

  plan <- mb_api_key_get_effective_key(session, require_auth = TRUE)

  expect_equal(plan$key, "test-personal-key")
  expect_equal(plan$source, "personal")
})

test_that("etkin API anahtarı kişisel anahtar yoksa izinli varsayılan kurum anahtarını döner", {
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

  session <- .make_api_key_identity_session(
    auth_initialized = TRUE,
    system_username = "user_without_personal_key"
  )

  plan <- mb_api_key_get_effective_key(session, require_auth = TRUE)

  expect_equal(plan$key, "test-default-key")
  expect_equal(plan$source, "default")
})
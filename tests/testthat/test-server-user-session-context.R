# ==============================================================================
# Dosya Yolu: tests/testthat/test-server-user-session-context.R
# Açıklama: server_init_user_session.R içindeki saf/yarı-saf yardımcıların
#           kullanıcı kimliği, user_config ve canlı provider sözleşmesini doğrular.
# ==============================================================================

repo_root <- resolve_repo_root_for_tests()

source(file.path(repo_root, "R", "utils_common.R"), encoding = "UTF-8", local = globalenv())
source(file.path(repo_root, "R", "server_init_user_session.R"), encoding = "UTF-8", local = globalenv())

.test_base_user_config <- list(
  icon = "user-icon",
  auth_level = "ADMIN"
)

.test_identity <- function(auth_source = "local") {
  list(
    username = "test_user",
    first_name = "Test",
    full_name = "Test User",
    sicil = if (identical(auth_source, "keycloak")) "12345" else NULL,
    email = if (identical(auth_source, "keycloak")) "test@example.local" else NULL,
    last_name = "User",
    sektor = "REHIS",
    department = "Test Department",
    mudurluk = "Test Mudurluk",
    masraf_yeri_kodu = "M001",
    auth_level = "USER",
    auth_source = auth_source
  )
}

test_that("build_user_session_config local davranışı korur", {
  cfg <- build_user_session_config(
    user_identity = .test_identity("local"),
    user_id = 42L,
    base_user_config = .test_base_user_config,
    auth_source = "local"
  )

  expect_equal(cfg$name, "Test User")
  expect_equal(cfg$icon, "user-icon")
  expect_equal(cfg$userId, "42")
  expect_equal(cfg$auth_level, "ADMIN")
  expect_null(cfg$sicil)
  expect_equal(cfg$first_name, "Test")
})

test_that("build_user_session_config SSO sicil ve yetki davranışını korur", {
  cfg <- build_user_session_config(
    user_identity = .test_identity("keycloak"),
    user_id = 42L,
    base_user_config = .test_base_user_config,
    auth_source = "keycloak"
  )

  expect_equal(cfg$userId, "12345")
  expect_equal(cfg$auth_level, "USER")
  expect_equal(cfg$email, "test@example.local")
  expect_equal(cfg$sektor, "REHIS")
})

test_that("apply_user_session_identity beklenen session$userData alanlarını yazar", {
  fake_session <- list(userData = new.env(parent = emptyenv()))

  cfg <- build_user_session_config(
    user_identity = .test_identity("keycloak"),
    user_id = 77L,
    base_user_config = .test_base_user_config,
    auth_source = "keycloak"
  )

  apply_user_session_identity(
    session = fake_session,
    user_identity = .test_identity("keycloak"),
    user_id = 77L,
    app_user_config = cfg,
    sso_active = TRUE,
    auth_source = "keycloak",
    auth_initialized = TRUE
  )

  expect_equal(fake_session$userData$user_id, 77L)
  expect_true(fake_session$userData$sso_active)
  expect_true(fake_session$userData$auth_initialized)
  expect_equal(fake_session$userData$auth_source, "keycloak")
  expect_equal(fake_session$userData$user_config$userId, "12345")
  expect_equal(fake_session$userData$user_first_name, "Test")
})

test_that("make_current_user_id_provider session kimliğini fallback üstünde önceler", {
  fake_session <- list(userData = new.env(parent = emptyenv()))
  fallback_uid <- 10L

  provider_bundle <- make_current_user_id_provider(
    session = fake_session,
    current_user_id_ref = function() fallback_uid
  )

  expect_equal(provider_bundle$current_user_id_provider(), 10L)

  fake_session$userData$user_id <- 88L
  expect_equal(provider_bundle$current_user_id_provider(), 88L)
})

test_that("make_current_user_id_provider SSO placeholder 0 iken canlı fallback kullanır", {
  fake_session <- list(userData = new.env(parent = emptyenv()))
  fake_session$userData$user_id <- 0L

  fallback_uid <- 55L

  provider_bundle <- make_current_user_id_provider(
    session = fake_session,
    current_user_id_ref = function() fallback_uid
  )

  expect_equal(provider_bundle$resolve_current_user_id(), 55L)
})
# ==============================================================================
# Dosya Yolu: tests/testthat/test-user-session-identity-contract.R
# Açıklama: Kullanıcı oturumu kimlik yardımcılarının SSO/local davranışını,
#           session$userData yazımını ve canlı kullanıcı kimliği sağlayıcısını
#           Shiny uygulamasını başlatmadan doğrular.
# ==============================================================================

if (!exists("resolve_effective_user_id", mode = "function")) {
  source(
    file.path(repo_root_for_tests, "R", "utils_common.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
}

source(
  file.path(repo_root_for_tests, "R", "helpers_user_session_identity.R"),
  encoding = "UTF-8",
  local = globalenv()
)

.make_user_session_identity_test_identity <- function(auth_source = "local") {
  list(
    username = "okaradag",
    first_name = "Onur",
    full_name = "Mehmet Onur Karadağ",
    sicil = "123456",
    email = "onur@example.local",
    last_name = "Karadağ",
    sektor = "REHİS",
    department = "Radar",
    mudurluk = "Müdürlük",
    masraf_yeri_kodu = "MM001",
    auth_level = "ADMIN",
    auth_source = auth_source
  )
}

.make_user_session_identity_test_base_config <- function() {
  list(
    icon = "user",
    auth_level = "USER"
  )
}

test_that("build_user_session_config yerel modda sayısal kullanıcı id değerini kullanır", {
  config <- build_user_session_config(
    user_identity = .make_user_session_identity_test_identity("local"),
    user_id = 42L,
    base_user_config = .make_user_session_identity_test_base_config(),
    auth_source = "local"
  )

  expect_equal(config$userId, "42")
  expect_equal(config$auth_level, "USER")
  expect_equal(config$first_name, "Onur")
  expect_equal(config$sicil, "123456")
})

test_that("build_user_session_config SSO modunda sicil ve SSO yetkisini korur", {
  config <- build_user_session_config(
    user_identity = .make_user_session_identity_test_identity("keycloak"),
    user_id = 42L,
    base_user_config = .make_user_session_identity_test_base_config(),
    auth_source = "keycloak"
  )

  expect_equal(config$userId, "123456")
  expect_equal(config$auth_level, "ADMIN")
  expect_equal(config$name, "Mehmet Onur Karadağ")
  expect_equal(config$department, "Radar")
})

test_that("apply_user_session_identity session$userData alanlarını tek noktadan yazar", {
  session <- list(userData = new.env(parent = emptyenv()))
  user_identity <- .make_user_session_identity_test_identity("keycloak")
  app_user_config <- build_user_session_config(
    user_identity = user_identity,
    user_id = 42L,
    base_user_config = .make_user_session_identity_test_base_config(),
    auth_source = "keycloak"
  )

  sonuc <- apply_user_session_identity(
    session = session,
    user_identity = user_identity,
    user_id = 42L,
    app_user_config = app_user_config,
    sso_active = TRUE,
    auth_source = "keycloak",
    auth_initialized = TRUE
  )

  expect_identical(sonuc, app_user_config)
  expect_equal(session$userData$user_id, 42L)
  expect_true(session$userData$sso_active)
  expect_true(session$userData$auth_initialized)
  expect_equal(session$userData$auth_source, "keycloak")
  expect_equal(session$userData$user_first_name, "Onur")
  expect_equal(session$userData$system_username, "okaradag")
  expect_identical(session$userData$user_config, app_user_config)
})

test_that("make_current_user_id_provider session kimliği hazır olduğunda onu öncelikli kullanır", {
  session <- list(userData = new.env(parent = emptyenv()))
  current_user_id <- 17L

  provider <- make_current_user_id_provider(
    session = session,
    current_user_id_ref = function() current_user_id
  )

  expect_equal(provider$current_user_id_provider(), 17L)

  session$userData$user_id <- 42L
  current_user_id <- 99L

  expect_equal(provider$resolve_current_user_id(), 42L)
  expect_equal(provider$current_user_id_provider(), 42L)
})

test_that("make_current_user_id_provider SSO placeholder 0 yerine canlı fallback kullanır", {
  session <- list(userData = new.env(parent = emptyenv()))
  session$userData$user_id <- 0L

  current_user_id <- 77L

  provider <- make_current_user_id_provider(
    session = session,
    current_user_id_ref = function() current_user_id
  )

  expect_equal(provider$current_user_id_provider(), 77L)
})
# ==============================================================================
# Dosya Yolu: tests/testthat/test-sso-session-identity-smoke.R
# Açıklama: SSO kimlik sağlayıcısının placeholder user_id=0 durumundan gerçek
#           DB kullanıcı kimliğine canlı olarak geçtiğini doğrular.
#           Uygulamayı, DB'yi veya tarayıcıyı başlatmaz.
# ==============================================================================

.find_sso_smoke_repo_root <- function() {
  candidates <- unique(normalizePath(
    c(getwd(), file.path(getwd(), ".."), file.path(getwd(), "..", "..")),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "tests", "testthat"))) {
      return(candidate)
    }
  }

  stop("SSO smoke repo kökünü bulamadı.", call. = FALSE)
}

repo_root_sso_smoke <- .find_sso_smoke_repo_root()

if (!exists("resolve_repo_root_for_tests", envir = globalenv(), inherits = FALSE)) {
  source(
    file.path(repo_root_sso_smoke, "tests", "testthat", "helper_bootstrap.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
}

repo_root_sso_smoke <- resolve_repo_root_for_tests()

.sso_smoke_source_once <- function(path, required_function = NULL) {
  if (!is.null(required_function) &&
      exists(required_function, envir = globalenv(), inherits = TRUE)) {
    return(invisible(TRUE))
  }

  source(
    file.path(repo_root_sso_smoke, path),
    encoding = "UTF-8",
    local = globalenv()
  )

  invisible(TRUE)
}

.sso_smoke_source_once("R/utils_common.R", "%||%")
.sso_smoke_source_once("R/helpers_user_session_identity.R", "make_current_user_id_provider")
.sso_smoke_source_once("R/server_init_user_session.R", "serverInitUserSession")

testthat::test_that("SSO placeholder user_id=0 gerçek kimliğe canlı geçer", {
  testthat::skip_if_not_installed("shiny")

  cache_ids <- integer()
  touched_ids <- integer()

  fake_session_cache <- list(
    setup_user_session = function(uid) {
      cache_ids <<- c(cache_ids, as.integer(uid))
      tempfile("sso_cache_")
    }
  )

  fake_claims <- list(
    username = "mehmet.karadag",
    sicil = "12345",
    email = "mehmet.karadag@example.local",
    full_name = enc2utf8("Mehmet Onur Karadağ"),
    first_name = enc2utf8("Mehmet"),
    last_name = enc2utf8("Karadağ"),
    sektor = NULL,
    department = NULL,
    mudurluk = NULL,
    masraf_yeri_kodu = NULL
  )

  resolve_identity_fn <- function(sso_claims = NULL) {
    list(
      username = sso_claims$username,
      full_name = sso_claims$full_name,
      first_name = sso_claims$first_name,
      last_name = sso_claims$last_name,
      sicil = sso_claims$sicil,
      email = sso_claims$email,
      auth_level = "USER",
      sektor = sso_claims$sektor,
      department = sso_claims$department,
      mudurluk = sso_claims$mudurluk,
      masraf_yeri_kodu = sso_claims$masraf_yeri_kodu,
      auth_source = "keycloak"
    )
  }

  get_or_create_user_fn <- function(username, sso_claims = NULL) {
    testthat::expect_identical(username, "mehmet.karadag")
    testthat::expect_identical(sso_claims$sicil, "12345")
    4242L
  }

  touch_session_fn <- function(uid) {
    touched_ids <<- c(touched_ids, as.integer(uid))
    invisible(TRUE)
  }

  shiny::testServer(function(input, output, session) {
    sso_state <- shiny::reactiveValues(
      authenticated = FALSE,
      user_claims = NULL,
      auth_level = NULL,
      raw_token = NULL
    )

    identity <- serverInitUserSession(
      session = session,
      session_cache = fake_session_cache,
      sso_state = sso_state,
      base_user_config = list(icon = "user", auth_level = "USER"),
      sso_enabled = TRUE,
      resolve_identity_fn = resolve_identity_fn,
      get_or_create_user_fn = get_or_create_user_fn,
      touch_session_fn = touch_session_fn
    )

    session$userData$.sso_state <- sso_state
    session$userData$.identity <- identity
  }, {
    identity <- session$userData$.identity
    sso_state <- session$userData$.sso_state

    testthat::expect_false(identity$is_auth_ready())
    testthat::expect_identical(identity$get_current_user_id_snapshot(), 0L)
    testthat::expect_identical(session$userData$user_id, 0L)
    testthat::expect_false(isTRUE(session$userData$auth_initialized))

    sso_state$user_claims <- fake_claims
    sso_state$authenticated <- TRUE
    session$flushReact()

    testthat::expect_true(identity$is_auth_ready())
    testthat::expect_identical(identity$get_current_user_id_snapshot(), 4242L)
    testthat::expect_identical(identity$current_user_id_provider(), 4242L)
    testthat::expect_identical(session$userData$user_id, 4242L)
    testthat::expect_true(isTRUE(session$userData$auth_initialized))
    testthat::expect_identical(identity$get_first_name(), enc2utf8("Mehmet"))
    testthat::expect_identical(cache_ids, 4242L)
    testthat::expect_identical(touched_ids, 4242L)
  })
})
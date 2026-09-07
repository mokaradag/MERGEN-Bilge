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

    # observeEvent(..., ignoreInit = TRUE) ilk reaktif turu yutacağı için
    # SSO TRUE sinyalinden önce observer'ın başlangıç turunu tamamlat.
    session$flushReact()

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

# `user_claims` DEĞİŞTİĞİNDE aynı kullanıcı adı için yetki yeniden uygulanmalıdır:
# hazır-kimlik guard'ı `setup_user_identity()` çağrısını atladığında oturum
# DÜŞÜRÜLEN yetkiyi görmeden önceki (daha yüksek) `auth_level` ile devam ediyordu.
testthat::test_that("aynı kullanıcı için düşürülen yetki oturuma yansır", {
  testthat::skip_if_not_installed("shiny")

  # Ortam nesnesi: `testServer()` gövdesi ayrı bir maskede değerlendirildiği
  # için basit yerel atama closure değişkenini DEĞİŞTİRMEZ.
  durum <- new.env(parent = emptyenv())
  durum$yetki <- "ADMIN"
  durum$db_cagri <- 0L

  resolve_identity_fn <- function(sso_claims = NULL) {
    list(
      username = "ayse.demir",
      full_name = "Ayse Demir",
      first_name = "Ayse",
      last_name = "Demir",
      sicil = "55555",
      email = "ayse.demir@example.local",
      auth_level = durum$yetki,
      sektor = NULL,
      department = NULL,
      mudurluk = NULL,
      masraf_yeri_kodu = NULL,
      auth_source = "keycloak"
    )
  }

  get_or_create_user_fn <- function(username, sso_claims = NULL) {
    durum$db_cagri <- durum$db_cagri + 1L
    7L
  }

  shiny::testServer(function(input, output, session) {
    sso_state <- shiny::reactiveValues(
      authenticated = FALSE,
      user_claims = NULL
    )

    identity <- serverInitUserSession(
      session = session,
      session_cache = list(setup_user_session = function(uid) tempfile("yetki_cache_")),
      sso_state = sso_state,
      base_user_config = list(icon = "user", auth_level = "USER"),
      sso_enabled = TRUE,
      resolve_identity_fn = resolve_identity_fn,
      get_or_create_user_fn = get_or_create_user_fn
    )

    session$userData$.sso_state <- sso_state
    session$userData$.identity <- identity
  }, {
    identity <- session$userData$.identity
    sso_state <- session$userData$.sso_state
    session$flushReact()

    sso_state$user_claims <- list(username = "ayse.demir", yetki = "ADMIN")
    sso_state$authenticated <- TRUE
    session$flushReact()

    testthat::expect_true(identity$is_auth_ready())
    testthat::expect_identical(session$userData$user_id, 7L)
    testthat::expect_identical(session$userData$user_config$auth_level, "ADMIN")
    testthat::expect_identical(durum$db_cagri, 1L)

    # AYNI kullanıcı adı, DÜŞÜRÜLEN yetki taşıyan İKİNCİ token.
    durum$yetki <- "USER"
    sso_state$user_claims <- list(username = "ayse.demir", yetki = "USER")
    session$flushReact()

    testthat::expect_identical(session$userData$user_config$auth_level, "USER")
    testthat::expect_identical(session$userData$user_identity$auth_level, "USER")
    testthat::expect_identical(session$userData$user_id, 7L)
    testthat::expect_true(identity$is_auth_ready())
    # Yeniden uygulama DB kullanıcı aramasını TEKRARLAMAZ.
    testthat::expect_identical(durum$db_cagri, 1L)

    # Kimlik DEĞİŞMEDİYSE yeniden uygulama da yapılmaz.
    sso_state$user_claims <- list(username = "ayse.demir", yetki = "USER", ek = 1L)
    session$flushReact()
    testthat::expect_identical(session$userData$user_config$auth_level, "USER")
    testthat::expect_identical(durum$db_cagri, 1L)
  })
})

# Kimlik kurulumu BAŞARISIZ olduğunda oturum önceki kullanıcıda kalmamalıdır.
testthat::test_that("başarısız ikinci kullanıcı kurulumu önceki kimliği temizler", {
  testthat::skip_if_not_installed("shiny")

  kimlik_durumu <- new.env(parent = emptyenv())
  kimlik_durumu$kullanici <- "birinci.kullanici"

  resolve_identity_fn <- function(sso_claims = NULL) {
    list(
      username = kimlik_durumu$kullanici,
      full_name = kimlik_durumu$kullanici,
      first_name = kimlik_durumu$kullanici,
      last_name = "",
      sicil = NULL,
      email = NULL,
      auth_level = "USER",
      sektor = NULL,
      department = NULL,
      mudurluk = NULL,
      masraf_yeri_kodu = NULL,
      auth_source = "keycloak"
    )
  }

  get_or_create_user_fn <- function(username, sso_claims = NULL) {
    if (identical(username, "birinci.kullanici")) 11L else 0L
  }

  shiny::testServer(function(input, output, session) {
    sso_state <- shiny::reactiveValues(authenticated = FALSE, user_claims = NULL)

    identity <- serverInitUserSession(
      session = session,
      session_cache = list(setup_user_session = function(uid) tempfile("basarisiz_cache_")),
      sso_state = sso_state,
      base_user_config = list(icon = "user", auth_level = "USER"),
      sso_enabled = TRUE,
      resolve_identity_fn = resolve_identity_fn,
      get_or_create_user_fn = get_or_create_user_fn
    )

    session$userData$.sso_state <- sso_state
    session$userData$.identity <- identity
  }, {
    identity <- session$userData$.identity
    sso_state <- session$userData$.sso_state
    session$flushReact()

    sso_state$user_claims <- list(username = "birinci.kullanici")
    sso_state$authenticated <- TRUE
    session$flushReact()

    testthat::expect_identical(session$userData$user_id, 11L)
    testthat::expect_true(identity$is_auth_ready())

    # İKİNCİ kullanıcı: DB kimliği çözülemiyor.
    kimlik_durumu$kullanici <- "ikinci.kullanici"
    sso_state$user_claims <- list(username = "ikinci.kullanici")
    session$flushReact()

    testthat::expect_false(identity$is_auth_ready())
    testthat::expect_identical(identity$get_current_user_id_snapshot(), 0L)
    testthat::expect_identical(identity$current_user_id_provider(), 0L)
    testthat::expect_identical(session$userData$user_id, 0L)
    testthat::expect_false(isTRUE(session$userData$auth_initialized))
    testthat::expect_null(session$userData$user_identity)
    testthat::expect_null(session$userData$user_config)
    testthat::expect_null(session$userData$system_username)
    testthat::expect_null(identity$user_config_rv())
  })
})
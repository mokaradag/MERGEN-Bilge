# ==============================================================================
# Dosya Yolu: R/server_init_user_session.R
# Açıklama: server.R içindeki kullanıcı kimliği, SSO/local oturum kurulumu ve
#           canlı current_user_id provider sözleşmesini tek yerde toplar.
# ==============================================================================

build_user_session_config <- function(user_identity, user_id, base_user_config,
                                      auth_source = NULL) {
  auth_source <- auth_source %||% user_identity$auth_source %||% "local"
  is_sso <- identical(auth_source, "keycloak")

  list(
    name       = user_identity$full_name,
    icon       = base_user_config$icon,
    userId     = if (is_sso) {
      user_identity$sicil %||% as.character(user_id)
    } else {
      as.character(user_id)
    },
    auth_level = if (is_sso) {
      user_identity$auth_level %||% base_user_config$auth_level
    } else {
      base_user_config$auth_level
    },
    sicil             = user_identity$sicil,
    email             = user_identity$email,
    first_name        = user_identity$first_name,
    last_name         = user_identity$last_name,
    sektor            = user_identity$sektor,
    department        = user_identity$department,
    mudurluk          = user_identity$mudurluk,
    masraf_yeri_kodu  = user_identity$masraf_yeri_kodu
  )
}

apply_user_session_identity <- function(session, user_identity, user_id,
                                        app_user_config,
                                        sso_active,
                                        auth_source,
                                        auth_initialized = TRUE) {
  if (is.null(session) || is.null(session$userData)) {
    stop("apply_user_session_identity: session$userData bulunamadı.", call. = FALSE)
  }

  session$userData$user_identity    <- user_identity
  session$userData$user_first_name  <- user_identity$first_name
  session$userData$system_username  <- user_identity$username
  session$userData$user_id          <- as.integer(user_id)
  session$userData$sso_active       <- isTRUE(sso_active)
  session$userData$auth_source      <- auth_source
  session$userData$auth_initialized <- isTRUE(auth_initialized)
  session$userData$user_config      <- app_user_config

  invisible(app_user_config)
}

make_current_user_id_provider <- function(session, current_user_id_ref) {
  if (!is.function(current_user_id_ref)) {
    snapshot_user_id <- current_user_id_ref
    current_user_id_ref <- function() snapshot_user_id
  }

  resolve_current_user_id <- function() {
    resolve_effective_user_id(
      session = session,
      current_user_id = current_user_id_ref
    )
  }

  list(
    resolve_current_user_id = resolve_current_user_id,
    current_user_id_provider = resolve_current_user_id
  )
}

serverInitUserSession <- function(session,
                                  session_cache,
                                  sso_state,
                                  base_user_config,
                                  sso_enabled = SSO_ENABLED,
                                  resolve_identity_fn = resolveUserIdentity,
                                  get_or_create_user_fn = get_or_create_user,
                                  touch_session_fn = NULL) {
  user_config_rv <- shiny::reactiveVal(NULL)
  current_user_id <- 0L
  auth_ready <- FALSE
  last_cache_dir <- NULL

  set_current_user_id <- function(user_id) {
    uid <- suppressWarnings(as.integer(user_id %||% 0L))
    if (is.na(uid) || uid < 0L) uid <- 0L
    current_user_id <<- uid
    invisible(uid)
  }

  user_id_provider_bundle <- make_current_user_id_provider(
    session = session,
    current_user_id_ref = function() current_user_id
  )

  setup_user_identity <- function(user_identity, user_id, sso_active, auth_source) {
    uid <- set_current_user_id(user_id)

    app_user_config <- build_user_session_config(
      user_identity = user_identity,
      user_id = uid,
      base_user_config = base_user_config,
      auth_source = auth_source
    )

    apply_user_session_identity(
      session = session,
      user_identity = user_identity,
      user_id = uid,
      app_user_config = app_user_config,
      sso_active = sso_active,
      auth_source = auth_source,
      auth_initialized = TRUE
    )

    user_config_rv(app_user_config)

    if (is.list(session_cache) && is.function(session_cache$setup_user_session)) {
      last_cache_dir <<- session_cache$setup_user_session(uid)
    }

    if (isTRUE(sso_active) && is.function(touch_session_fn)) {
      try(touch_session_fn(uid), silent = TRUE)
    }

    auth_ready <<- TRUE

    invisible(list(
      user_id = uid,
      user_identity = user_identity,
      user_config = app_user_config,
      cache_dir = last_cache_dir
    ))
  }

  if (!isTRUE(sso_enabled)) {
    user_identity <- resolve_identity_fn()
    system_username <- user_identity$username
    uid <- get_or_create_user_fn(system_username)

    setup_user_identity(
      user_identity = user_identity,
      user_id = uid,
      sso_active = FALSE,
      auth_source = "local"
    )
  } else {
    set_current_user_id(0L)
    session$userData$auth_initialized <- FALSE
    session$userData$sso_active <- TRUE

    observeEvent(sso_state$authenticated, {
      req(isTRUE(sso_state$authenticated))

      claims <- sso_state$user_claims
      user_identity <- resolve_identity_fn(sso_claims = claims)
      system_username <- user_identity$username
      uid <- get_or_create_user_fn(system_username, sso_claims = claims)

      setup_user_identity(
        user_identity = user_identity,
        user_id = uid,
        sso_active = TRUE,
        auth_source = "keycloak"
      )

      log_info(
        "SSO oturum kuruldu: kullanıcı={system_username}, id={uid}, yetki={user_identity$auth_level}"
      )
    }, ignoreInit = TRUE, once = TRUE)
  }

  get_user_config <- function(default = NULL) {
    cfg <- tryCatch(
      shiny::isolate(user_config_rv()),
      error = function(e) NULL
    )

    if (!is.null(cfg)) {
      return(cfg)
    }

    session$userData$user_config %||% default
  }

  get_first_name <- function(default = "") {
    cfg <- get_user_config()

    value <- cfg$first_name %||%
      session$userData$user_first_name %||%
      default

    value <- as.character(value %||% default)

    if (!nzchar(value)) {
      return(default)
    }

    value
  }

  get_display_name <- function(default = "Kullanıcı") {
    cfg <- get_user_config()

    value <- cfg$name %||%
      get_first_name(default = default) %||%
      default

    value <- as.character(value %||% default)

    if (!nzchar(value)) {
      return(default)
    }

    value
  }

  get_auth_source <- function(default = NULL) {
    session$userData$auth_source %||%
      default %||%
      if (isTRUE(sso_enabled)) "keycloak" else "local"
  }

  list(
    user_config_rv = user_config_rv,
    resolve_current_user_id = user_id_provider_bundle$resolve_current_user_id,
    current_user_id_provider = user_id_provider_bundle$current_user_id_provider,
    is_auth_ready = function() isTRUE(auth_ready),
    is_sso_active = function() isTRUE(sso_enabled),
    get_auth_source = get_auth_source,
    get_user_config = get_user_config,
    get_first_name = get_first_name,
    get_display_name = get_display_name,
    get_current_user_id_snapshot = function() current_user_id,
    get_cache_dir = function() last_cache_dir
  )
}
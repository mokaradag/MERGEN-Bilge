# ==============================================================================
# Dosya Yolu: R/server_init_user_session.R
# Açıklama: server.R içindeki kullanıcı kimliği, SSO/local oturum kurulumu ve
#           canlı current_user_id provider sözleşmesini tek yerde toplar.
# ==============================================================================

local({
  gerekli_kimlik_yardimcilari <- c(
    "build_user_session_config",
    "merge_user_profile_into_identity",
    "apply_user_session_identity",
    "make_current_user_id_provider",
    "make_user_session_data_accessors"
  )

  eksik_kimlik_yardimcilari <- gerekli_kimlik_yardimcilari[!vapply(
    gerekli_kimlik_yardimcilari,
    function(ad) exists(ad, mode = "function", inherits = TRUE),
    logical(1)
  )]

  if (length(eksik_kimlik_yardimcilari) > 0L) {
    stop(
      sprintf(
        paste0(
          "server_init_user_session.R yüklenmeden önce ",
          "R/helpers_user_session_identity.R yüklenmelidir. Eksik: %s"
        ),
        paste(eksik_kimlik_yardimcilari, collapse = ", ")
      ),
      call. = FALSE
    )
  }
})

serverInitUserSession <- function(session,
                                  session_cache,
                                  sso_state,
                                  base_user_config,
                                  sso_enabled = SSO_ENABLED,
                                  resolve_identity_fn = resolveUserIdentity,
                                  get_or_create_user_fn = get_or_create_user,
                                  get_user_profile_fn = NULL,
                                  touch_session_fn = NULL) {
  user_config_rv <- shiny::reactiveVal(NULL)
  current_user_id <- 0L
  auth_ready <- FALSE
  last_cache_dir <- NULL
  session_data <- make_user_session_data_accessors(session)
  
  if (is.null(get_user_profile_fn) &&
      exists("get_user_profile_from_db", mode = "function", inherits = TRUE)) {
    get_user_profile_fn <- get("get_user_profile_from_db", mode = "function", inherits = TRUE)
  }

  if (!is.null(get_user_profile_fn) && !is.function(get_user_profile_fn)) {
    get_user_profile_fn <- NULL
  }

  set_current_user_id <- function(user_id) {
    current_user_id <<- .normalize_user_session_id(
      user_id,
      allow_zero = TRUE
    )

    invisible(current_user_id)
  }

  user_id_provider_bundle <- make_current_user_id_provider(
    session = session,
    current_user_id_ref = function() current_user_id
  )

  setup_user_identity <- function(user_identity, user_id, sso_active, auth_source) {
    uid <- set_current_user_id(user_id)

    user_profile <- NULL

    if (!is.null(get_user_profile_fn) && uid > 0L) {
      user_profile <- tryCatch(
        get_user_profile_fn(
          user_id = uid,
          username = user_identity$username %||% NULL
        ),
        error = function(e) {
          if (exists("log_warn", mode = "function", inherits = TRUE)) {
            log_warn("MB_Users kullanıcı profili okunamadı (UserID={uid}): {e$message}")
          }
          NULL
        }
      )
    }

    user_identity <- merge_user_profile_into_identity(
      user_identity = user_identity,
      user_profile = user_profile
    )

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
    session_data$set_auth_placeholder(
      sso_active = TRUE,
      auth_source = "keycloak"
    )

    # Önemli: Bu observer yüksek öncelikle çalışır. SSO doğrulandığında
    # (sso_state$authenticated FALSE -> TRUE) birden çok observer aynı
    # flush turunda tetiklenir: kayıtlı sohbetler, dosya yöneticisi
    # yenilemesi, geri bildirim yüklemesi, görsel galerisi. Bunların
    # hepsi kimlik kurulumunun (user_id ve auth_ready) tamamlanmış
    # olmasına bağlıdır. priority yüksek tutularak kimlik kurulumunun
    # her zaman diğer auth observer'larından ÖNCE çalışması garanti
    # edilir; aksi halde ilk girişte dosya/sohbet yüklemesi user_id=0
    # ile atlanabilir ve yalnızca tarayıcı yenilemesinde düzelir.
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
    }, ignoreInit = TRUE, once = TRUE, priority = 1000L)
  }

  get_user_config <- function(default = NULL) {
    cfg <- tryCatch(
      shiny::isolate(user_config_rv()),
      error = function(e) NULL
    )

    if (!is.null(cfg)) {
      return(cfg)
    }

    session_data$get_user_config(default = default)
  }

  get_first_name <- function(default = "") {
    cfg <- get_user_config()

    value <- cfg$first_name %||%
      session_data$get_first_name(default = NULL) %||%
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
    fallback_source <- default %||%
      if (isTRUE(sso_enabled)) "keycloak" else "local"

    session_data$get_auth_source(default = fallback_source)
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
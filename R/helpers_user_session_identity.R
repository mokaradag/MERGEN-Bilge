# ==============================================================================
# Dosya Yolu: R/helpers_user_session_identity.R
# Açıklama: Kullanıcı oturumu kimlik/config yardımcılarını saf ve test edilebilir
#           şekilde toplar. Shiny observer veya veritabanı işlemi içermez.
# ==============================================================================

.normalize_user_session_id <- function(user_id, allow_zero = TRUE) {
  uid <- suppressWarnings(as.integer(user_id %||% 0L))

  if (is.na(uid) || uid < 0L || (!isTRUE(allow_zero) && uid <= 0L)) {
    return(0L)
  }

  uid
}

make_user_session_data_accessors <- function(session) {
  if (is.null(session) || is.null(session$userData)) {
    stop(
      "make_user_session_data_accessors: session$userData bulunamadı.",
      call. = FALSE
    )
  }

  user_data <- session$userData

  get_value <- function(key, default = NULL) {
    if (exists(key, envir = user_data, inherits = FALSE)) {
      value <- get(key, envir = user_data, inherits = FALSE)

      if (!is.null(value)) {
        return(value)
      }
    }

    default
  }

  set_value <- function(key, value) {
    user_data[[key]] <- value
    invisible(value)
  }

  list(
    write_identity = function(user_identity,
                              user_id,
                              app_user_config,
                              sso_active,
                              auth_source,
                              auth_initialized = TRUE) {
      uid <- .normalize_user_session_id(user_id, allow_zero = TRUE)

      set_value("user_identity", user_identity)
      set_value("user_first_name", user_identity$first_name)
      set_value("system_username", user_identity$username)
      set_value("user_id", uid)
      set_value("sso_active", isTRUE(sso_active))
      set_value("auth_source", auth_source)
      set_value("auth_initialized", isTRUE(auth_initialized))
      set_value("user_config", app_user_config)

      invisible(app_user_config)
    },

    set_auth_placeholder = function(sso_active = TRUE,
                                    auth_source = "keycloak") {
      set_value("user_id", 0L)
      set_value("sso_active", isTRUE(sso_active))
      set_value("auth_source", auth_source)
      set_value("auth_initialized", FALSE)

      invisible(NULL)
    },

    get_user_id = function(default = 0L) {
      .normalize_user_session_id(
        get_value("user_id", default),
        allow_zero = TRUE
      )
    },

    get_user_config = function(default = NULL) {
      get_value("user_config", default)
    },

    get_first_name = function(default = "") {
      get_value("user_first_name", default)
    },

    get_auth_source = function(default = NULL) {
      get_value("auth_source", default)
    }
  )
}

build_user_session_config <- function(user_identity,
                                      user_id,
                                      base_user_config,
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

apply_user_session_identity <- function(session,
                                        user_identity,
                                        user_id,
                                        app_user_config,
                                        sso_active,
                                        auth_source,
                                        auth_initialized = TRUE) {
  session_data <- make_user_session_data_accessors(session)

  session_data$write_identity(
    user_identity = user_identity,
    user_id = user_id,
    app_user_config = app_user_config,
    sso_active = sso_active,
    auth_source = auth_source,
    auth_initialized = auth_initialized
  )
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
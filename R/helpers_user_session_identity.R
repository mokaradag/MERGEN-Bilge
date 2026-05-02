# ==============================================================================
# Dosya Yolu: R/helpers_user_session_identity.R
# Açıklama: Kullanıcı oturumu kimlik/config yardımcılarını saf ve test edilebilir
#           şekilde toplar. Shiny observer veya veritabanı işlemi içermez.
# ==============================================================================

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
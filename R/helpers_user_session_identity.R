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

merge_user_profile_into_identity <- function(user_identity, user_profile = NULL) {
  if (is.null(user_identity) || !is.list(user_identity)) {
    user_identity <- list()
  }

  if (is.null(user_profile) || !is.list(user_profile)) {
    return(user_identity)
  }

  pick_non_empty <- function(keys, fallback = NULL) {
    for (key in keys) {
      value <- user_profile[[key]]
      if (!is.null(value)) {
        value <- trimws(as.character(value)[1])
        if (!is.na(value) && nzchar(value)) {
          return(value)
        }
      }
    }

    fallback <- fallback %||% ""
    fallback <- trimws(as.character(fallback)[1])
    if (is.na(fallback)) "" else fallback
  }

  previous_full_name <- user_identity$full_name %||% ""

  user_identity$username <- pick_non_empty(
    c("KullaniciAdi", "username"),
    user_identity$username
  )

  user_identity$full_name <- pick_non_empty(
    c("KaynakAdi", "name", "full_name"),
    user_identity$full_name
  )

  user_identity$sicil <- pick_non_empty(
    c("Sicil", "sicil"),
    user_identity$sicil
  )

  user_identity$email <- pick_non_empty(
    c("Email", "email"),
    user_identity$email
  )

  user_identity$sektor <- pick_non_empty(
    c("Sektor", "sektor"),
    user_identity$sektor
  )

  user_identity$department <- pick_non_empty(
    c("Departman", "department", "departman"),
    user_identity$department
  )

  user_identity$mudurluk <- pick_non_empty(
    c("Mudurluk", "mudurluk"),
    user_identity$mudurluk
  )

  user_identity$masraf_yeri_kodu <- pick_non_empty(
    c("MasrafYeriKodu", "masraf_yeri_kodu"),
    user_identity$masraf_yeri_kodu
  )

  # DB'deki KaynakAdi geldiyse first_name de ona göre güncellensin.
  if (
    nzchar(user_identity$full_name %||% "") &&
    (
      !nzchar(user_identity$first_name %||% "") ||
      !identical(previous_full_name, user_identity$full_name)
    ) &&
    exists("extractFirstName", mode = "function", inherits = TRUE)
  ) {
    user_identity$first_name <- extractFirstName(user_identity$full_name)
  }

  user_identity
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

  full_name <- user_identity$full_name %||% ""
  department <- user_identity$department %||% user_identity$Departman %||% ""
  sektor <- user_identity$sektor %||% user_identity$Sektor %||% ""
  mudurluk <- user_identity$mudurluk %||% user_identity$Mudurluk %||% ""
  masraf_yeri_kodu <- user_identity$masraf_yeri_kodu %||%
    user_identity$MasrafYeriKodu %||% ""

  list(
    name       = full_name,
    KaynakAdi  = full_name,
    icon       = base_user_config$icon,
    userId     = if (is_sso) {
      user_identity$sicil %||% as.character(user_id)
    } else {
      as.character(user_id)
    },
    KullaniciAdi = user_identity$username,
    auth_level = if (is_sso) {
      user_identity$auth_level %||% base_user_config$auth_level
    } else {
      base_user_config$auth_level
    },
    sicil             = user_identity$sicil,
    Sicil             = user_identity$sicil,
    email             = user_identity$email,
    Email             = user_identity$email,
    first_name        = user_identity$first_name,
    last_name         = user_identity$last_name,
    sektor            = sektor,
    Sektor            = sektor,
    department        = department,
    Departman         = department,
    mudurluk          = mudurluk,
    Mudurluk          = mudurluk,
    masraf_yeri_kodu  = masraf_yeri_kodu,
    MasrafYeriKodu    = masraf_yeri_kodu
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
# ==============================================================================
# Dosya Yolu: R/helpers_api_key_identity.R
# Açıklama:   API anahtarı sahipliğini doğrulayan oturum yardımcıları.
#             Kişisel API anahtarları yalnızca kimliği doğrulanmış uygulama
#             kullanıcısına bağlanır; Shiny sunucu OS kullanıcısına düşülmez.
# ==============================================================================

.mb_api_key_user_data <- function(session) {
  if (is.null(session) || is.null(session$userData)) {
    return(NULL)
  }

  session$userData
}

.mb_api_key_get_user_data_value <- function(session, key, default = NULL) {
  user_data <- .mb_api_key_user_data(session)
  if (is.null(user_data) || !nzchar(as.character(key)[1])) {
    return(default)
  }

  key <- as.character(key)[1]

  if (!exists(key, envir = user_data, inherits = FALSE)) {
    return(default)
  }

  value <- get(key, envir = user_data, inherits = FALSE)
  if (is.null(value)) {
    return(default)
  }

  value
}

.mb_api_key_first_non_empty <- function(...) {
  values <- list(...)

  for (value in values) {
    if (is.null(value)) {
      next
    }

    value <- trimws(as.character(value)[1])
    if (!is.na(value) && nzchar(value)) {
      return(value)
    }
  }

  ""
}

mb_api_key_resolve_owner <- function(session, require_auth = TRUE) {
  user_data <- .mb_api_key_user_data(session)
  if (is.null(user_data)) {
    return(NULL)
  }

  auth_initialized <- .mb_api_key_get_user_data_value(
    session,
    "auth_initialized",
    FALSE
  )

  # SSO akışı tamamlanmadan kişisel anahtar yükleme/kaydetme yapılmaz.
  # Bu, Sys.info()[["user"]] gibi paylaşımlı OS hesabına düşmeyi engeller.
  if (isTRUE(require_auth) && !isTRUE(auth_initialized)) {
    return(NULL)
  }

  user_identity <- .mb_api_key_get_user_data_value(session, "user_identity", list())
  user_config <- .mb_api_key_get_user_data_value(session, "user_config", list())

  username <- .mb_api_key_first_non_empty(
    .mb_api_key_get_user_data_value(session, "system_username", NULL),
    if (is.list(user_identity)) user_identity$username else NULL,
    if (is.list(user_config)) user_config$KullaniciAdi else NULL,
    if (is.list(user_config)) user_config$username else NULL
  )

  if (!nzchar(username)) {
    return(NULL)
  }

  list(
    username = username,
    user_id = .mb_api_key_get_user_data_value(session, "user_id", NULL),
    auth_source = .mb_api_key_get_user_data_value(session, "auth_source", NULL)
  )
}

mb_api_key_clear_session_key <- function(session) {
  user_data <- .mb_api_key_user_data(session)
  if (is.null(user_data)) {
    return(invisible(NULL))
  }

  keys <- c("ai_api_key", "ai_api_key_owner")
  existing_keys <- keys[vapply(
    keys,
    exists,
    logical(1),
    envir = user_data,
    inherits = FALSE
  )]

  if (length(existing_keys) > 0L) {
    rm(list = existing_keys, envir = user_data)
  }

  invisible(NULL)
}

mb_api_key_set_session_key <- function(session, key_plain, owner = NULL) {
  user_data <- .mb_api_key_user_data(session)
  if (is.null(user_data)) {
    stop("API anahtarı oturumu bulunamadı.", call. = FALSE)
  }

  if (is.null(owner)) {
    owner <- mb_api_key_resolve_owner(session, require_auth = TRUE)
  }

  if (is.null(owner) || !nzchar(owner$username %||% "")) {
    stop(
      "Kimlik doğrulama tamamlanmadan API anahtarı oturuma yazılamaz.",
      call. = FALSE
    )
  }

  key_plain <- as.character(key_plain %||% "")[1]
  if (is.na(key_plain) || !nzchar(key_plain)) {
    stop("API anahtarı boş.", call. = FALSE)
  }

  user_data$ai_api_key <- key_plain
  user_data$ai_api_key_owner <- owner$username

  invisible(owner)
}

mb_api_key_get_session_key <- function(session,
                                       require_auth = TRUE,
                                       clear_on_mismatch = TRUE) {
  owner <- mb_api_key_resolve_owner(session, require_auth = require_auth)
  if (is.null(owner) || !nzchar(owner$username %||% "")) {
    return("")
  }

  key_plain <- .mb_api_key_get_user_data_value(session, "ai_api_key", "")
  key_plain <- as.character(key_plain %||% "")[1]

  if (is.na(key_plain) || !nzchar(key_plain)) {
    return("")
  }

  key_owner <- .mb_api_key_get_user_data_value(session, "ai_api_key_owner", "")
  key_owner <- as.character(key_owner %||% "")[1]

  if (is.na(key_owner) || !identical(key_owner, owner$username)) {
    if (isTRUE(clear_on_mismatch)) {
      mb_api_key_clear_session_key(session)
    }

    return("")
  }

  key_plain
}
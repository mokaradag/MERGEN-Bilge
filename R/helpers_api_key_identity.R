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

  keys <- c("ai_api_key", "ai_api_key_owner", "ai_api_key_send_cache")
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

  # Gönderim önbelleği geçersiz kılınır; sonraki istek anahtarı yeniden çözer.
  if (exists("ai_api_key_send_cache", envir = user_data, inherits = FALSE)) {
    rm("ai_api_key_send_cache", envir = user_data)
  }

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

mb_api_key_default_allowed <- function() {
  require_personal <- isTRUE(as.logical(
    Sys.getenv("MERGEN_REQUIRE_PERSONAL_API_KEY", "FALSE")
  ))

  allow_default <- isTRUE(as.logical(
    Sys.getenv("MERGEN_ALLOW_DEFAULT_API_KEY", "FALSE")
  ))

  isTRUE(allow_default) && !isTRUE(require_personal)
}

mb_api_key_get_default_key <- function(allow_default = NULL) {
  if (is.null(allow_default)) {
    allow_default <- mb_api_key_default_allowed()
  }

  if (!isTRUE(allow_default)) {
    return("")
  }

  default_key <- Sys.getenv("MERGEN_DEFAULT_API_KEY", "")
  default_key <- as.character(default_key %||% "")[1]

  if (is.na(default_key) || !nzchar(default_key)) {
    return("")
  }

  default_key
}

mb_api_key_get_effective_key <- function(session,
                                         require_auth = TRUE,
                                         allow_default = NULL,
                                         clear_on_mismatch = TRUE) {
  owner <- mb_api_key_resolve_owner(session, require_auth = require_auth)

  if (isTRUE(require_auth) && (is.null(owner) || !nzchar(owner$username %||% ""))) {
    return(list(
      key = "",
      source = "missing",
      owner = NULL
    ))
  }

  personal_key <- mb_api_key_get_session_key(
    session = session,
    require_auth = require_auth,
    clear_on_mismatch = clear_on_mismatch
  )

  if (nzchar(personal_key)) {
    return(list(
      key = personal_key,
      source = "personal",
      owner = owner
    ))
  }

  default_key <- mb_api_key_get_default_key(allow_default = allow_default)

  if (nzchar(default_key)) {
    return(list(
      key = default_key,
      source = "default",
      owner = owner
    ))
  }

  list(
    key = "",
    source = "missing",
    owner = owner
  )
}

mb_api_key_get_effective_key_value <- function(session,
                                               require_auth = TRUE,
                                               allow_default = NULL,
                                               clear_on_mismatch = TRUE) {
  plan <- mb_api_key_get_effective_key(
    session = session,
    require_auth = require_auth,
    allow_default = allow_default,
    clear_on_mismatch = clear_on_mismatch
  )

  as.character(plan$key %||% "")[1]
}

# Her gönderimde ucuz, oturum-belleği önbellekli etkin anahtar çözümü.
# Etkin anahtar zaten oturum belleğinden okunur (disk/ağ/DB yok); bu yardımcı
# ilk-token öncesi sahiplik/kaynak çözümleme tekrarını da atlayarak küçük bir
# memo tutar. Önbellek YALNIZCA sunucu tarafı oturum belleğinde durur; tarayıcıya
# asla gönderilmez ve anahtar değeri loglanmaz.
#
# Önbellek isabeti yalnızca şu durumda kullanılır: kimliği doğrulanmış mevcut
# sahip, önbellekteki sahip ile birebir aynıdır ve önbellekteki anahtar doludur.
# Sahip değişimi, oturum/auth hazır değilse veya anahtar boşsa tam çözümlemeye
# (mb_api_key_get_effective_key) düşülür ve önbellek güncellenir. Önbellek
# anahtar kaydetme/temizleme yollarında (mb_api_key_set_session_key /
# mb_api_key_clear_session_key) geçersiz kılınır.
# Yalnızca gönderim önbelleğini (ai_api_key_send_cache) temizler; oturum
# anahtarını (ai_api_key) KORUR. 401/403 gibi yetkilendirme hatalarından sonra
# bir sonraki gönderimin tam sahiplik yeniden-çözümünü (clear_on_mismatch dahil)
# garanti etmek için kullanılır.
mb_api_key_invalidate_send_cache <- function(session) {
  user_data <- .mb_api_key_user_data(session)
  if (is.null(user_data)) {
    return(invisible(FALSE))
  }

  if (exists("ai_api_key_send_cache", envir = user_data, inherits = FALSE)) {
    rm("ai_api_key_send_cache", envir = user_data)
    return(invisible(TRUE))
  }

  invisible(FALSE)
}

# Hata metni yetkilendirme hatasına benziyor mu? (401/403/AUTH_MISSING_KEY/...).
# Zaman aşımı, ağ, iptal gibi yetkilendirme dışı hatalarda FALSE döner.
mb_api_key_error_is_auth <- function(error_text) {
  txt <- tryCatch(as.character(error_text %||% "")[1], error = function(e) "")
  if (is.na(txt) || !nzchar(txt)) {
    return(FALSE)
  }

  grepl(
    "AUTH_MISSING_KEY|API_HTTP_ERROR_401|API_HTTP_ERROR_403|(^|[^0-9])(401|403)([^0-9]|$)|unauthorized|forbidden",
    txt,
    ignore.case = TRUE,
    perl = TRUE
  )
}

# Hata metni yetkilendirme hatasıysa gönderim anahtarı önbelleğini geçersiz kılar.
# Yetkilendirme dışı hatalarda hiçbir şey yapmaz (no-op).
mb_api_key_invalidate_send_cache_on_auth_error <- function(session, error_text) {
  if (isTRUE(mb_api_key_error_is_auth(error_text))) {
    return(mb_api_key_invalidate_send_cache(session))
  }

  invisible(FALSE)
}

mb_api_key_get_cached_for_send <- function(session,
                                           require_auth = TRUE,
                                           allow_default = NULL,
                                           clear_on_mismatch = TRUE) {
  user_data <- .mb_api_key_user_data(session)

  owner <- mb_api_key_resolve_owner(session, require_auth = require_auth)
  owner_username <- if (is.null(owner)) "" else as.character(owner$username %||% "")[1]

  cache <- if (!is.null(user_data)) {
    .mb_api_key_get_user_data_value(session, "ai_api_key_send_cache", NULL)
  } else {
    NULL
  }

  # Önbellek isabeti: sahip eşleşiyor ve anahtar dolu.
  if (is.list(cache) &&
      nzchar(owner_username) &&
      identical(as.character(cache$owner %||% "")[1], owner_username) &&
      nzchar(as.character(cache$key %||% "")[1])) {
    return(list(
      key = as.character(cache$key)[1],
      source = as.character(cache$source %||% "unknown")[1],
      owner = owner,
      cached = TRUE
    ))
  }

  # Önbellek yok/geçersiz: tam (yine de oturum-belleği) çözümleme ve sakla.
  plan <- mb_api_key_get_effective_key(
    session = session,
    require_auth = require_auth,
    allow_default = allow_default,
    clear_on_mismatch = clear_on_mismatch
  )

  key_val <- as.character(plan$key %||% "")[1]
  source_val <- as.character(plan$source %||% "unknown")[1]

  if (!is.null(user_data) && nzchar(owner_username) && nzchar(key_val)) {
    user_data$ai_api_key_send_cache <- list(
      owner = owner_username,
      key = key_val,
      source = source_val
    )
  }

  list(
    key = key_val,
    source = source_val,
    owner = plan$owner %||% owner,
    cached = FALSE
  )
}
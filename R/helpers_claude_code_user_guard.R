# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_user_guard.R
# Açıklama: Bilge Yolaç çalışma zamanı kullanıcı kimliği ve SSO hazır olma
#           kontrollerini saf/test edilebilir yardımcılar halinde toplar.
# ==============================================================================

cc_normalize_positive_user_id <- function(value) {
  value <- value %||% 0L
  if (length(value) == 0L) {
    return(0L)
  }

  uid <- suppressWarnings(as.integer(value[1]))
  if (is.na(uid) || uid <= 0L) {
    return(0L)
  }

  uid
}

cc_auth_is_ready <- function(session = NULL, sso_enabled = FALSE) {
  if (!isTRUE(sso_enabled)) {
    return(TRUE)
  }

  if (is.null(session) || is.null(session$userData)) {
    return(FALSE)
  }

  isTRUE(session$userData$auth_initialized)
}

cc_resolve_effective_user_id <- function(session = NULL, current_user_id = NULL) {
  resolve_effective_user_id(
    session = session,
    current_user_id = current_user_id
  )
}

cc_require_ready_user_id <- function(session = NULL,
                                     current_user_id = NULL,
                                     sso_enabled = FALSE,
                                     action_label = "işlem") {
  action_label <- as.character(action_label %||% "işlem")
  action_label <- action_label[1]

  if (is.na(action_label) || !nzchar(trimws(action_label))) {
    action_label <- "işlem"
  }

  if (!cc_auth_is_ready(session = session, sso_enabled = sso_enabled)) {
    return(list(
      ok = FALSE,
      user_id = 0L,
      code = "auth_pending",
      message = sprintf(
        "Kimlik doğrulama tamamlanmadan %s işlemi yapılamaz.",
        action_label
      )
    ))
  }

  uid <- cc_normalize_positive_user_id(
    cc_resolve_effective_user_id(
      session = session,
      current_user_id = current_user_id
    )
  )

  if (uid <= 0L) {
    return(list(
      ok = FALSE,
      user_id = 0L,
      code = "user_pending",
      message = "Kullanıcı kimliği hazır değil. Lütfen sayfayı yenileyin."
    ))
  }

  list(
    ok = TRUE,
    user_id = uid,
    code = "ok",
    message = ""
  )
}
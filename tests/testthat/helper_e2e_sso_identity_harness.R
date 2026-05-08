# ==============================================================================
# Dosya Yolu: tests/testthat/helper_e2e_sso_identity_harness.R
# Açıklama: SSO kimlik hazır olma ve modül yenileme yarış durumları için
#           deterministik E2E benzeri test yardımcıları.
# ==============================================================================

e2e_sso_fake_runtime_session <- function() {
  list(
    userData = new.env(parent = emptyenv()),
    token = "e2e-sso-token"
  )
}

e2e_sso_fake_session_cache <- function() {
  list(
    mcp_saved_path = function(...) NULL,
    cache_root = tempdir(),
    setup_user_session = function(user_id) {
      file.path(tempdir(), paste0("user_", user_id))
    },
    cache_mcp_file_locally = function(path) path,
    update_mcp_registry_snapshot = function(files_snapshot = NULL) {
      files_snapshot
    },
    get_cache_dir = function() tempdir()
  )
}

e2e_sso_new_runtime_context <- function(user_id = 0L,
                                         auth_ready = FALSE,
                                         authenticated = FALSE,
                                         sso_active = TRUE) {
  state <- new.env(parent = emptyenv())
  state$user_id <- user_id
  state$auth_ready <- isTRUE(auth_ready)
  state$sso_active <- isTRUE(sso_active)

  sso_state <- list(
    authenticated = isTRUE(authenticated)
  )

  user_session <- list(
    user_config_rv = function(...) NULL,
    resolve_current_user_id = function() state$user_id,
    current_user_id_provider = function() state$user_id,
    is_auth_ready = function() isTRUE(state$auth_ready),
    is_sso_active = function() isTRUE(state$sso_active),
    get_auth_source = function(default = NULL) {
      if (isTRUE(state$sso_active)) "keycloak" else "local"
    },
    get_user_config = function(default = NULL) {
      list(
        name = "SSO Test User",
        first_name = "SSO",
        userId = as.character(state$user_id)
      )
    },
    get_first_name = function(default = "") "SSO",
    get_display_name = function(default = "Kullanıcı") "SSO Test User",
    get_current_user_id_snapshot = function() state$user_id,
    get_cache_dir = function() tempdir()
  )

  session <- e2e_sso_fake_runtime_session()

  ctx <- serverRuntimeContextInit(
    session = session,
    session_cache = e2e_sso_fake_session_cache(),
    sso_state = sso_state,
    user_session = user_session
  )

  list(
    ctx = ctx,
    state = state,
    session = session
  )
}

e2e_sso_mark_ready <- function(runtime, user_id) {
  runtime$state$user_id <- user_id
  runtime$state$auth_ready <- TRUE
  runtime$ctx$sso_state$authenticated <- TRUE
  runtime
}

e2e_sso_req <- function(...) {
  values <- list(...)
  ok <- all(vapply(values, isTRUE, logical(1)))

  if (!isTRUE(ok)) {
    stop("e2e_sso_req_failed", call. = FALSE)
  }

  invisible(TRUE)
}

e2e_sso_new_observer_probe <- function() {
  state <- new.env(parent = emptyenv())
  state$records <- list()
  state$triggers <- list()

  state$observe_event <- function(eventExpr,
                                  handlerExpr,
                                  ignoreInit = TRUE,
                                  once = TRUE) {
    expr <- substitute(handlerExpr)
    expr_env <- parent.frame()
    fired <- new.env(parent = emptyenv())
    fired$value <- FALSE

    index <- length(state$records) + 1L

    state$records[[index]] <- list(
      expr = expr,
      expr_env = expr_env,
      ignoreInit = ignoreInit,
      once = once,
      fired = fired
    )

    trigger <- function() {
      record <- state$records[[index]]

      if (isTRUE(record$once) && isTRUE(record$fired$value)) {
        return(invisible(FALSE))
      }

      record$fired$value <- TRUE
      eval(record$expr, envir = record$expr_env)
      invisible(TRUE)
    }

    state$triggers[[index]] <- trigger

    list(
      ignoreInit = ignoreInit,
      once = once,
      trigger = trigger
    )
  }

  state$count <- function() {
    length(state$triggers)
  }

  state$trigger_all <- function() {
    invisible(lapply(state$triggers, function(trigger) trigger()))
  }

  state
}

e2e_sso_new_refresh_log <- function() {
  log <- new.env(parent = emptyenv())
  log$events <- list()

  log$record <- function(module, reason, user_id) {
    index <- length(log$events) + 1L
    log$events[[index]] <- list(
      module = as.character(module),
      reason = as.character(reason %||% ""),
      user_id = as.integer(user_id)
    )

    invisible(TRUE)
  }

  log$count <- function(module = NULL) {
    if (is.null(module)) {
      return(length(log$events))
    }

    sum(vapply(
      log$events,
      function(event) identical(event$module, module),
      logical(1)
    ))
  }

  log$modules <- function() {
    vapply(log$events, function(event) event$module, character(1))
  }

  log$user_ids <- function() {
    vapply(log$events, function(event) event$user_id, integer(1))
  }

  log$reasons <- function() {
    vapply(log$events, function(event) event$reason, character(1))
  }

  log
}

e2e_sso_require_valid_user_id <- function(user_id, owner) {
  user_id_chr <- trimws(as.character(user_id %||% ""))

  if (!nzchar(user_id_chr) ||
      user_id_chr %in% c("0", "NA", "NaN", "NULL", "unknown")) {
    stop(
      sprintf("%s geçersiz kullanıcı kimliğiyle yenilendi: %s", owner, user_id_chr),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

e2e_sso_file_manager_server_stub <- function(refresh_log) {
  function(id,
           new_file_trigger,
           session_files_reactive,
           mcp_enabled_reactive,
           user_id,
           settings_data,
           auth_ready_provider) {
    list(
      refresh_persisted_files = function(reason = NULL) {
        if (!isTRUE(auth_ready_provider())) {
          stop("file_manager auth hazır olmadan yenilendi", call. = FALSE)
        }

        current_user <- user_id()
        e2e_sso_require_valid_user_id(current_user, "file_manager")

        refresh_log$record(
          module = "file_manager",
          reason = reason %||% "",
          user_id = current_user
        )

        invisible(TRUE)
      },
      file_contents = function(...) list()
    )
  }
}

e2e_sso_image_gallery_server_stub <- function(refresh_log) {
  function(id, current_user_id) {
    list(
      refresh = function() {
        current_user <- current_user_id()
        e2e_sso_require_valid_user_id(current_user, "image_gallery")

        refresh_log$record(
          module = "image_gallery",
          reason = "refresh",
          user_id = current_user
        )

        invisible(TRUE)
      }
    )
  }
}

e2e_sso_read_repo_ascii <- function(repo_root, ...) {
  path <- file.path(repo_root, ...)

  if (!file.exists(path)) {
    stop(sprintf("Beklenen dosya bulunamadi: %s", path), call. = FALSE)
  }

  size <- suppressWarnings(file.info(path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)
  raw_data[raw_data == as.raw(0L)] <- as.raw(0x20)
  raw_data[as.integer(raw_data) > 127L] <- as.raw(0x20)

  text <- rawToChar(raw_data)
  Encoding(text) <- "UTF-8"
  text
}
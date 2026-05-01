# ==============================================================================
# Dosya Yolu: R/helpers_file_manager_runtime.R
# Açıklama: Dosya Yönetimi sunucu modülü için çalışma zamanı yardımcıları.
# ==============================================================================

.fm_runtime_is_reactivevalues <- function(value) {
  inherits(value, "reactivevalues")
}

fm_create_server_runtime_helpers <- function(session,
                                             user_id,
                                             settings_data,
                                             session_files_reactive,
                                             mcp_enabled_reactive,
                                             ns,
                                             module_values_provider,
                                             auth_ready_provider = NULL) {
  safe_settings_data <- shiny::reactive({
    if (!is.null(settings_data)) {
      return(settings_data)
    }

    fm_debug("settings_missing", "settings_data parametresi verilmedi; NULL kullanılacak")
    NULL
  })

  get_summarization_mode <- function() {
    settings_obj <- safe_settings_data()
    if (is.null(settings_obj)) {
      return(FALSE)
    }

    if (.fm_runtime_is_reactivevalues(settings_obj)) {
      return(isTRUE(settings_obj$enable_summarization_tools))
    }

    if (is.list(settings_obj)) {
      return(isTRUE(settings_obj$enable_summarization_tools))
    }

    FALSE
  }

  build_attach_rule_hint_text <- function(mcp_enabled = FALSE,
                                          summarization_mode = FALSE,
                                          allow_summarization_text = FALSE) {
    fm_attach_rule_hint_text(
      mcp_enabled = mcp_enabled,
      summarization_mode = summarization_mode,
      allow_summarization_text = allow_summarization_text
    )
  }

  update_attach_rule_hint <- function(summarization_mode = FALSE,
                                      allow_summarization_text = FALSE) {
    shinyjs::html(
      id = "attach_rule_hint",
      html = build_attach_rule_hint_text(
        mcp_enabled = isTRUE(mcp_enabled_reactive()),
        summarization_mode = isTRUE(summarization_mode),
        allow_summarization_text = isTRUE(allow_summarization_text)
      ),
      add = FALSE
    )
  }

  get_effective_user_id <- function() {
    if (exists("resolve_effective_user_id", mode = "function", inherits = TRUE)) {
      resolved_uid <- resolve_effective_user_id(
        session = session,
        current_user_id = user_id
      )
      return(fm_normalize_user_id(resolved_uid))
    }

    session_uid <- fm_normalize_user_id(session$userData$user_id)
    if (fm_valid_user_id(session_uid)) {
      return(session_uid)
    }

    provided_raw <- if (exists("resolve_runtime_value", mode = "function", inherits = TRUE)) {
      resolve_runtime_value(user_id)
    } else if (is.function(user_id)) {
      tryCatch(user_id(), error = function(e) NULL)
    } else {
      user_id
    }

    provided_uid <- fm_normalize_user_id(provided_raw)
    if (fm_valid_user_id(provided_uid)) {
      return(provided_uid)
    }

    "unknown"
  }

  module_user_id_chr <- function() {
    get_effective_user_id()
  }

  fm_debug <- function(event, ...) {
    parts <- vapply(list(...), function(x) {
      if (length(x) == 0) return("")
      paste(as.character(x), collapse = " ")
    }, character(1))
    msg <- trimws(paste(parts, collapse = " "))
    cat(sprintf(
      "[FILE_MANAGER][user:%s][%s] %s\n",
      module_user_id_chr() %||% "unknown",
      event %||% "event",
      if (nzchar(msg)) msg else "(no details)"
    ))
  }

  ensure_session_registry <- function() {
    initialized <- fm_ensure_session_registry(session)
    if (isTRUE(initialized)) {
      fm_debug("ensure_registry", "session registry initialized")
    }
    invisible(TRUE)
  }

  register_session_file <- function(filename, fpath) {
    fname <- as.character(filename %||% "")
    ok <- fm_register_session_file(session, filename, fpath)

    if (isTRUE(ok)) {
      entry <- session$userData$current_session_files[[fname]]
      fm_debug("register", sprintf("%s -> %s", fname, entry$datapath %||% ""))
    }

    invisible(ok)
  }

  unregister_session_file <- function(filename) {
    ok <- fm_unregister_session_file(session, filename)
    invisible(ok)
  }

  ext_icon_html <- function(ext) {
    fm_file_ext_icon_html(ext)
  }

  get_summarization_allowed_extensions <- function() {
    fm_summarization_allowed_extensions()
  }

  get_normal_allowed_extensions <- function() {
    fm_normal_allowed_extensions()
  }

  resolve_allowed_extensions <- function(generate_message, summarization_mode) {
    fm_resolve_allowed_extensions(
      generate_message = generate_message,
      summarization_mode = summarization_mode
    )
  }

  show_unsupported_extension_toast <- function(file_ext, summarization_mode) {
    summarization_allowed <- get_summarization_allowed_extensions()
    normal_allowed <- get_normal_allowed_extensions()

    if (isTRUE(summarization_mode)) {
      showToast(
        session,
        sprintf(
          "Dosya Özetleme modunda sadece şu formatlar desteklenir: %s.",
          paste(toupper(summarization_allowed), collapse = ", ")
        ),
        "warning"
      )
      return(invisible(TRUE))
    }

    showToast(
      session,
      sprintf(
        "'%s' uzantılı dosya desteklenmiyor. Desteklenen türler: %s.",
        toupper(file_ext),
        paste(toupper(normal_allowed), collapse = ", ")
      ),
      "warning"
    )

    invisible(TRUE)
  }

  get_file_by_id <- function(fid) {
    module_values <- module_values_provider()
    module_values$file_contents[[fid]] %||% NULL
  }

  update_session_files <- function(update_fn) {
    if (is.null(session_files_reactive)) return(invisible())
    try({
      cur <- session_files_reactive()
      session_files_reactive(update_fn(cur))
    }, silent = TRUE)
  }

  attach_in_parent <- function(file_obj) {
    if (is.null(session_files_reactive)) return(invisible())
    update_session_files(function(cur) {
      cur <- cur %||% list()
      cur[[file_obj$name]] <- cur[[file_obj$name]] %||% list(name = file_obj$name)
      cur
    })
    fm_debug("attach", sprintf("added %s to session context", file_obj$name))
  }

  detach_in_parent <- function(file_name) {
    if (is.null(session_files_reactive)) return(invisible())
    update_session_files(function(cur) {
      cur <- cur %||% list()
      cur[[file_name]] <- NULL
      cur
    })
    fm_debug("detach", sprintf("removed %s from session context", file_name))
  }

  format_timestamp <- function(path = NULL, fallback_time = Sys.time()) {
    fm_format_file_timestamp(path = path, fallback_time = fallback_time)
  }
  
  is_auth_ready <- function() {
    if (is.function(auth_ready_provider)) {
      return(isTRUE(tryCatch(
        auth_ready_provider(),
        error = function(e) FALSE
      )))
    }

    isTRUE(session$userData$auth_initialized)
  }

  list(
    safe_settings_data = safe_settings_data,
    get_summarization_mode = get_summarization_mode,
    build_attach_rule_hint_text = build_attach_rule_hint_text,
    update_attach_rule_hint = update_attach_rule_hint,
    get_effective_user_id = get_effective_user_id,
    module_user_id_chr = module_user_id_chr,
    is_auth_ready = is_auth_ready,
    fm_debug = fm_debug,
    ensure_session_registry = ensure_session_registry,
    register_session_file = register_session_file,
    unregister_session_file = unregister_session_file,
    ext_icon_html = ext_icon_html,
    get_summarization_allowed_extensions = get_summarization_allowed_extensions,
    get_normal_allowed_extensions = get_normal_allowed_extensions,
    resolve_allowed_extensions = resolve_allowed_extensions,
    show_unsupported_extension_toast = show_unsupported_extension_toast,
    get_file_by_id = get_file_by_id,
    update_session_files = update_session_files,
    attach_in_parent = attach_in_parent,
    detach_in_parent = detach_in_parent,
    format_timestamp = format_timestamp
  )
}
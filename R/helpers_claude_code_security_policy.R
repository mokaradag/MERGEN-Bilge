# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_security_policy.R
# Açıklama: Bilge Yolaç Claude Code CLI çalıştırma güvenlik ilkesi.
#           Çalışma dizini, çıktı kökü ve tehlikeli izin modu kararları burada
#           merkezi olarak yönetilir.
# ==============================================================================

cc_policy_truthy <- function(value) {
  if (is.null(value) || !length(value)) return(FALSE)

  if (is.logical(value)) {
    return(isTRUE(value[1]))
  }

  deger <- tolower(trimws(as.character(value[1] %||% "")))

  deger %in% c("1", "true", "yes", "y", "evet", "on", "enabled")
}

cc_policy_split_roots <- function(value) {
  value <- as.character(value %||% character(0))
  value <- value[nzchar(value)]

  if (!length(value)) {
    return(character(0))
  }

  parcalar <- unlist(strsplit(value, "[;,\n\r]+", perl = TRUE), use.names = FALSE)
  unique(trimws(parcalar[nzchar(trimws(parcalar))]))
}

cc_policy_normalize_path <- function(path, must_exist = FALSE) {
  path <- as.character(path %||% "")[1]
  if (is.na(path) || !nzchar(path)) return("")

  sonuc <- tryCatch(
    normalizePath(path, winslash = "/", mustWork = isTRUE(must_exist)),
    error = function(e) {
      tryCatch(
        normalizePath(path, winslash = "/", mustWork = FALSE),
        error = function(e2) path
      )
    }
  )

  sonuc <- gsub("\\\\", "/", sonuc, fixed = TRUE)
  sub("/+$", "", sonuc, perl = TRUE)
}

cc_policy_normalize_roots <- function(roots) {
  roots <- cc_policy_split_roots(roots)
  if (!length(roots)) return(character(0))

  roots <- vapply(
    roots,
    cc_policy_normalize_path,
    character(1),
    must_exist = FALSE,
    USE.NAMES = FALSE
  )

  unique(roots[nzchar(roots)])
}

cc_policy_default_user_workspace <- function(user_id = NULL) {
  user_id <- suppressWarnings(as.integer(user_id %||% NA_integer_))

  if (is.na(user_id) || user_id <= 0L) {
    return("")
  }

  if (!exists("get_user_workspace", mode = "function", inherits = TRUE)) {
    return("")
  }

  tryCatch(
    get_user_workspace(user_id),
    error = function(e) ""
  )
}

cc_policy_allowed_workdir_roots <- function(user_id = NULL,
                                            extra_roots = character(0),
                                            allow_system_temp = FALSE) {
  configured <- character(0)

  if (exists("claude_code_config", inherits = TRUE)) {
    configured <- c(
      configured,
      claude_code_config$allowed_workdir_roots %||% "",
      claude_code_config$default_workdir %||% ""
    )
  }

  configured <- c(
    configured,
    Sys.getenv("CLAUDE_CODE_ALLOWED_WORKDIR_ROOTS", ""),
    cc_policy_default_user_workspace(user_id),
    extra_roots
  )

  if (isTRUE(allow_system_temp)) {
    configured <- c(configured, tempdir())
  }

  cc_policy_normalize_roots(configured)
}

cc_policy_allowed_output_roots <- function(user_id = NULL, workdir = "") {
  configured <- character(0)

  if (exists("claude_code_config", inherits = TRUE)) {
    configured <- c(configured, claude_code_config$allowed_output_roots %||% "")
  }

  download_root <- if (exists("get_claude_code_download_root", mode = "function", inherits = TRUE)) {
    tryCatch(get_claude_code_download_root(), error = function(e) "")
  } else {
    ""
  }

  configured <- c(
    configured,
    Sys.getenv("CLAUDE_CODE_ALLOWED_OUTPUT_ROOTS", ""),
    workdir %||% "",
    cc_policy_allowed_workdir_roots(user_id),
    download_root
  )

  cc_policy_normalize_roots(configured)
}

cc_policy_path_inside_roots <- function(path, roots, must_exist = FALSE) {
  hedef <- cc_policy_normalize_path(path, must_exist = must_exist)
  kokler <- cc_policy_normalize_roots(roots)

  if (!nzchar(hedef) || !length(kokler)) {
    return(FALSE)
  }

  hedef_key <- if (.Platform$OS.type == "windows") tolower(hedef) else hedef

  for (kok in kokler) {
    kok_key <- if (.Platform$OS.type == "windows") tolower(kok) else kok

    if (identical(hedef_key, kok_key) || startsWith(hedef_key, paste0(kok_key, "/"))) {
      return(TRUE)
    }
  }

  FALSE
}

cc_policy_validate_workdir <- function(workdir,
                                       user_id = NULL,
                                       extra_allowed_roots = character(0),
                                       allow_system_temp = FALSE,
                                       allow_selected_workdir = FALSE) {
  ham_yol <- as.character(workdir %||% "")[1]

  if (is.na(ham_yol) || !nzchar(ham_yol)) {
    return(list(
      ok = FALSE,
      path = "",
      error = "Çalışma dizini boş olamaz."
    ))
  }

  # UNC / Türkçe karakter / native encoding durumları için mevcut relaxed resolver'ı kullan.
  resolved_existing <- ""
  if (exists("cc_resolve_existing_dir_relaxed", mode = "function", inherits = TRUE)) {
    resolved_existing <- tryCatch(
      cc_resolve_existing_dir_relaxed(ham_yol),
      error = function(e) ""
    )
  }

  if (!nzchar(resolved_existing)) {
    aday_yol <- cc_policy_normalize_path(ham_yol, must_exist = FALSE)
    exists_base <- tryCatch(
      isTRUE(dir.exists(aday_yol)) || isTRUE(fs::dir_exists(aday_yol)),
      error = function(e) FALSE
    )

    if (isTRUE(exists_base)) {
      resolved_existing <- aday_yol
    }
  }

  if (!nzchar(resolved_existing)) {
    return(list(
      ok = FALSE,
      path = cc_policy_normalize_path(ham_yol, must_exist = FALSE),
      error = paste0("Çalışma dizini bulunamadı: ", ham_yol)
    ))
  }

  yol <- cc_policy_normalize_path(resolved_existing, must_exist = FALSE)

  selected_roots <- character(0)
  if (isTRUE(allow_selected_workdir)) {
    selected_roots <- yol
  }

  kokler <- cc_policy_allowed_workdir_roots(
    user_id = user_id,
    extra_roots = c(extra_allowed_roots, selected_roots),
    allow_system_temp = allow_system_temp
  )

  allowed_by_base_policy <- cc_policy_path_inside_roots(
    yol,
    cc_policy_allowed_workdir_roots(
      user_id = user_id,
      extra_roots = extra_allowed_roots,
      allow_system_temp = allow_system_temp
    ),
    must_exist = TRUE
  )

  if (!cc_policy_path_inside_roots(yol, kokler, must_exist = TRUE)) {
    return(list(
      ok = FALSE,
      path = yol,
      error = paste0(
        "Çalışma dizini güvenlik ilkesi tarafından engellendi: ",
        ham_yol,
        ". İzin verilen köklerden biri içinde bir klasör seçin veya ",
        "CLAUDE_CODE_ALLOWED_WORKDIR_ROOTS ayarını açıkça yapılandırın."
      )
    ))
  }

  if (isTRUE(allow_selected_workdir) && !isTRUE(allowed_by_base_policy)) {
    log_warn(paste(
      CLAUDE_CODE_LOG_PREFIX,
      "Çalışma dizini kullanıcı seçimiyle bu çalışma için onaylandı:",
      gsub("[{}]", "", yol)
    ))
  }

  list(ok = TRUE, path = yol, error = "")
}

cc_policy_dangerous_permissions_allowed <- function(user_id = NULL, settings_data = NULL) {
  config_on <- FALSE

  if (exists("claude_code_config", inherits = TRUE)) {
    config_on <- cc_policy_truthy(
      claude_code_config$allow_dangerous_permissions %||% FALSE
    )
  }

  env_on <- cc_policy_truthy(
    Sys.getenv("CLAUDE_CODE_ALLOW_DANGEROUS_PERMISSIONS", "FALSE")
  )

  settings_on <- FALSE
  if (!is.null(settings_data) &&
      !is.null(settings_data$claude_code_allow_dangerous_permissions)) {
    settings_on <- cc_policy_truthy(
      settings_data$claude_code_allow_dangerous_permissions
    )
  }

  isTRUE(config_on || env_on || settings_on)
}

cc_policy_build_cli_args <- function(prompt,
                                     output_format = c("json", "stream-json"),
                                     model = NULL,
                                     session_id = NULL,
                                     include_partial_messages = FALSE,
                                     verbose = FALSE,
                                     user_id = NULL,
                                     settings_data = NULL) {
  output_format <- match.arg(output_format)

  args <- c("--print")

  if (isTRUE(verbose)) {
    args <- c(args, "--verbose")
  }

  args <- c(args, "--output-format", output_format)

  if (isTRUE(include_partial_messages)) {
    args <- c(args, "--include-partial-messages")
  }

  if (cc_policy_dangerous_permissions_allowed(
    user_id = user_id,
    settings_data = settings_data
  )) {
    args <- c(args, "--dangerously-skip-permissions")

    log_warn(paste(
      CLAUDE_CODE_LOG_PREFIX,
      "DİKKAT: Claude Code tehlikeli izin atlama modu açık.",
      "Bu yalnızca açık yönetici/geliştirme onayıyla kullanılmalıdır."
    ))
  } else {
    log_info(paste(
      CLAUDE_CODE_LOG_PREFIX,
      "Claude Code güvenli izin modu ile çalıştırılıyor."
    ))
  }

  if (!is.null(model) && nzchar(model)) {
    args <- c(args, "--model", model)
  }

  if (!is.null(session_id) && nzchar(session_id)) {
    args <- c(args, "--resume", session_id)
  }

  args <- c(args, prompt)
  args
}

cc_policy_filter_generated_file_paths <- function(file_paths,
                                                  allowed_roots,
                                                  context = "üretilen dosya") {
  file_paths <- unique(Filter(nzchar, as.character(file_paths %||% character(0))))

  if (!length(file_paths)) {
    return(character(0))
  }

  izinli <- character(0)

  for (yol in file_paths) {
    yol_norm <- cc_policy_normalize_path(yol, must_exist = FALSE)

    if (!cc_policy_path_inside_roots(yol_norm, allowed_roots, must_exist = FALSE)) {
      log_warn(paste(
        CLAUDE_CODE_LOG_PREFIX,
        context,
        "izin verilen köklerin dışında olduğu için engellendi:",
        gsub("[{}]", "", yol_norm)
      ))
      next
    }

    izinli <- c(izinli, yol_norm)
  }

  unique(izinli)
}
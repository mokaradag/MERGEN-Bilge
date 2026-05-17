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

cc_policy_cli_list <- function(value) {
  value <- as.character(value %||% character(0))
  value <- value[nzchar(value)]

  if (!length(value)) {
    return(character(0))
  }

  parcalar <- unlist(strsplit(value, "[;,\n\r]+", perl = TRUE), use.names = FALSE)
  unique(trimws(parcalar[nzchar(trimws(parcalar))]))
}

cc_policy_permission_mode <- function(settings_data = NULL) {
  raw_mode <- ""

  if (exists("claude_code_config", inherits = TRUE)) {
    raw_mode <- claude_code_config$permission_mode %||% ""
  }

  env_mode <- Sys.getenv("CLAUDE_CODE_PERMISSION_MODE", "")
  if (nzchar(env_mode)) {
    raw_mode <- env_mode
  }

  if (!is.null(settings_data) && !is.null(settings_data$claude_code_permission_mode)) {
    settings_mode <- as.character(settings_data$claude_code_permission_mode %||% "")[1]
    if (!is.na(settings_mode) && nzchar(settings_mode)) {
      raw_mode <- settings_mode
    }
  }

  raw_mode <- trimws(as.character(raw_mode %||% "")[1])
  if (is.na(raw_mode) || !nzchar(raw_mode)) {
    return("")
  }

  allowed_modes <- c("default", "acceptEdits", "plan")
  dangerous_modes <- c(
    "bypassPermissions",
    "bypasspermissions",
    "bypass",
    "dangerous",
    "dangerously-skip-permissions"
  )

  if (raw_mode %in% dangerous_modes) {
    log_warn(paste(
      CLAUDE_CODE_LOG_PREFIX,
      "CLAUDE_CODE_PERMISSION_MODE tehlikeli bypass değerine ayarlanmış.",
      "Bu yol kullanılmadı; tehlikeli mod yalnızca",
      "CLAUDE_CODE_ALLOW_DANGEROUS_PERMISSIONS ile açılabilir."
    ))
    return("acceptEdits")
  }

  matched <- allowed_modes[tolower(allowed_modes) == tolower(raw_mode)]
  if (length(matched)) {
    return(matched[1])
  }

  log_warn(paste(
    CLAUDE_CODE_LOG_PREFIX,
    "Bilinmeyen Claude Code permission_mode değeri:",
    raw_mode,
    "- acceptEdits kullanılacak."
  ))

  "acceptEdits"
}

cc_policy_permission_args <- function(settings_data = NULL) {
  mode <- cc_policy_permission_mode(settings_data = settings_data)
  args <- character(0)

  if (nzchar(mode) && !identical(mode, "default")) {
    args <- c(args, "--permission-mode", mode)
  }

  allowed_tools <- character(0)
  disallowed_tools <- character(0)

  if (exists("claude_code_config", inherits = TRUE)) {
    allowed_tools <- c(allowed_tools, claude_code_config$allowed_tools %||% "")
    disallowed_tools <- c(disallowed_tools, claude_code_config$disallowed_tools %||% "")
  }

  allowed_tools <- c(allowed_tools, Sys.getenv("CLAUDE_CODE_ALLOWED_TOOLS", ""))
  disallowed_tools <- c(disallowed_tools, Sys.getenv("CLAUDE_CODE_DISALLOWED_TOOLS", ""))

  allowed_tools <- cc_policy_cli_list(allowed_tools)
  disallowed_tools <- cc_policy_cli_list(disallowed_tools)

  if (length(allowed_tools)) {
    args <- c(args, "--allowedTools", allowed_tools)
  }

  if (length(disallowed_tools)) {
    args <- c(args, "--disallowedTools", disallowed_tools)
  }

  log_info(paste(
    CLAUDE_CODE_LOG_PREFIX,
    "Claude Code izin modu:",
    if (nzchar(mode)) mode else "CLI varsayılanı",
    "| allowedTools:",
    if (length(allowed_tools)) paste(allowed_tools, collapse = ",") else "(yok)",
    "| disallowedTools:",
    if (length(disallowed_tools)) paste(disallowed_tools, collapse = ",") else "(yok)"
  ))

  args
}

cc_policy_user_prompt <- function(prompt) {
  prompt <- as.character(prompt %||% "")[1]
  if (is.na(prompt)) prompt <- ""
  prompt
}

cc_policy_append_prompt_argument <- function(args, prompt) {
  prompt <- cc_policy_user_prompt(prompt)

  # Claude Code CLI'da --allowedTools / --disallowedTools variadic davranabilir.
  # Promptu "--" sonlandırıcısından sonra vermek, promptun yanlışlıkla araç adı
  # olarak tüketilmesini engeller.
  c(args, "--", prompt)
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

  # UNC yolları (\\server\share veya //server/share) Windows VM'de mapped
  # drive harfine çözülebiliyor (örn. //rehisds/... -> M:/rehisds/...). Çözülen
  # M:/ formu is_problematic_windows_workdir tarafından UNC olarak algılanmadığı
  # için runtime aynalama atlanır ve processx'in spawn ettiği cmd.exe oturumu
  # M:/ drive haritalamasına sahip değilse "directory is empty" veya
  # "The system cannot find the path specified" hatasıyla biter. Bu yüzden
  # güvenlik politikası katmanı UNC yollarını UNC olarak korur.
  #
  # NOT: gsub("\\\\", "/", x, fixed=TRUE) yalnızca ardışık çift ters slash'ı
  # eşler; bu yüzden \\server\share\sub gibi tek aralık ters slash'lı UNC'ler
  # için yanlış pozitif/negatif üretebilir. is_windows_unc_path hem çift slash
  # hem de tek slash ağ yolu varyantlarını birlikte tanır; mevcutsa onu
  # kullanırız. Yoksa yedek olarak tüm ters slash'ları forward slash'a çevirip
  # yeniden test ederiz.
  is_unc <- FALSE
  if (exists("is_windows_unc_path", mode = "function", inherits = TRUE)) {
    is_unc <- tryCatch(
      isTRUE(is_windows_unc_path(path)),
      error = function(e) FALSE
    )
  }

  if (!isTRUE(is_unc)) {
    candidate_slash <- gsub("\\", "/", path, fixed = TRUE)
    is_unc <- grepl("^//[^/]+/[^/]+", candidate_slash, perl = TRUE)
  }

  if (isTRUE(is_unc)) {
    if (exists("normalize_mcp_path", mode = "function", inherits = TRUE)) {
      cozulen <- tryCatch(
        normalize_mcp_path(path, must_exist = must_exist),
        error = function(e) NA_character_
      )

      if (!is.na(cozulen) && nzchar(cozulen)) {
        cozulen_slash <- gsub("\\", "/", cozulen, fixed = TRUE)
        if (grepl("^//", cozulen_slash, perl = TRUE)) {
          return(sub("/+$", "", cozulen_slash, perl = TRUE))
        }
      }
    }

    cleaned <- gsub("\\", "/", path, fixed = TRUE)
    cleaned <- paste0("//", sub("^/+", "", cleaned))
    return(sub("/+$", "", cleaned, perl = TRUE))
  }

  sonuc <- tryCatch(
    normalizePath(path, winslash = "/", mustWork = isTRUE(must_exist)),
    error = function(e) {
      tryCatch(
        normalizePath(path, winslash = "/", mustWork = FALSE),
        error = function(e2) path
      )
    }
  )

  # NOT: normalizePath winslash="/" ile zaten forward slash üretir ama herhangi
  # bir karma slash kalırsa tek ters slash'a göre değiştirme yaparız (çiftli
  # gsub baştaki çift slash dışında diğer ters slash'ları kaçırırdı).
  sonuc <- gsub("\\", "/", sonuc, fixed = TRUE)
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

  settings_requested <- FALSE
  if (!is.null(settings_data) &&
      !is.null(settings_data$claude_code_allow_dangerous_permissions)) {
    settings_requested <- cc_policy_truthy(
      settings_data$claude_code_allow_dangerous_permissions
    )
  }

  if (isTRUE(settings_requested) && !isTRUE(config_on || env_on)) {
    log_warn(paste(
      CLAUDE_CODE_LOG_PREFIX,
      "Kullanıcı/oturum ayarından gelen tehlikeli izin isteği yok sayıldı.",
      "Bu mod yalnızca CLAUDE_CODE_ALLOW_DANGEROUS_PERMISSIONS veya merkezi config ile açılabilir."
    ))
  }

  isTRUE(config_on || env_on)
}

cc_policy_build_cli_args <- function(prompt,
                                     output_format = c("json", "stream-json"),
                                     model = NULL,
                                     session_id = NULL,
                                     include_partial_messages = FALSE,
                                     verbose = FALSE,
                                     user_id = NULL,
                                     settings_data = NULL,
                                     workdir = NULL) {
  output_format <- match.arg(output_format)

  args <- c("--print")

  if (isTRUE(verbose)) {
    args <- c(args, "--verbose")
  }

  args <- c(args, "--output-format", output_format)

  if (isTRUE(include_partial_messages)) {
    args <- c(args, "--include-partial-messages")
  }

  dangerous_allowed <- cc_policy_dangerous_permissions_allowed(
    user_id = user_id,
    settings_data = settings_data
  )

  if (isTRUE(dangerous_allowed)) {
    args <- c(args, "--dangerously-skip-permissions")

    log_warn(paste(
      CLAUDE_CODE_LOG_PREFIX,
      "DİKKAT: Claude Code tehlikeli izin atlama modu açık.",
      "Bu yalnızca açık yönetici/geliştirme onayıyla kullanılmalıdır."
    ))
  } else {
    args <- c(args, cc_policy_permission_args(settings_data = settings_data))

    log_info(paste(
      CLAUDE_CODE_LOG_PREFIX,
      "Claude Code güvenli izin modu ile çalıştırılıyor; tehlikeli izin atlama kapalı."
    ))
  }

  prompt <- cc_policy_user_prompt(prompt)

  if (!is.null(model) && nzchar(model)) {
    args <- c(args, "--model", model)
  }

  if (!is.null(session_id) && nzchar(session_id)) {
    args <- c(args, "--resume", session_id)
  }

  args <- cc_policy_append_prompt_argument(args, prompt)
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
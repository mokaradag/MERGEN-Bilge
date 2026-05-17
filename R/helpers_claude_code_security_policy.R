# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_security_policy.R
# Açıklama: Bilge Yolaç Claude Code CLI çalıştırma güvenlik ilkesi.
#           Tehlikeli izin modu kararları, --permission-mode/--allowedTools
#           argümanları ve CLI argüman birleştirme burada merkezi olarak
#           yönetilir. Yol/kök doğrulama helper'ları
#           R/helpers_claude_code_path_policy.R dosyasındadır.
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

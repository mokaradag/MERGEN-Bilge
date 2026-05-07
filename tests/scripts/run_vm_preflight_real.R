# ==============================================================================
# Dosya Yolu: tests/scripts/run_vm_preflight_real.R
# Açıklama: Windows VM üzerinde gerçek ortam değişkenleriyle uygulamanın
# production-benzeri ön kontrolünü yapar. Gerçek boot doğrulaması, gerçek
# veritabanı sağlık kontrolü ve LLM endpoint erişilebilirlik kontrolü içerir.
# ==============================================================================

normalize_preflight_bool <- function(value,
                                     default = FALSE,
                                     env_name = "value") {
  if (is.null(value) || length(value) == 0L || is.na(value[1])) {
    return(default)
  }

  norm <- tolower(trimws(as.character(value[1])))

  if (!nzchar(norm)) {
    return(default)
  }

  if (norm %in% c("true", "t")) {
    return(TRUE)
  }

  if (norm %in% c("false", "f")) {
    return(FALSE)
  }

  stop(sprintf(
    "VM preflight durduruldu. %s geçersiz: %s. TRUE/FALSE kullanın.",
    env_name,
    as.character(value[1])
  ), call. = FALSE)
}

require_preflight_env_vars <- function(vars, label = "zorunlu ortam değişkenleri") {
  vars <- unique(as.character(vars))
  missing_vars <- vars[!nzchar(trimws(Sys.getenv(vars, "")))]

  if (length(missing_vars) > 0) {
    stop(sprintf(
      "VM preflight durduruldu. Eksik %s: %s",
      label,
      paste(missing_vars, collapse = ", ")
    ), call. = FALSE)
  }

  invisible(TRUE)
}

preflight_require_sso <- normalize_preflight_bool(
  Sys.getenv("MERGEN_PREFLIGHT_REQUIRE_SSO", "TRUE"),
  default = TRUE,
  env_name = "MERGEN_PREFLIGHT_REQUIRE_SSO"
)

preflight_sso_enabled <- normalize_preflight_bool(
  Sys.getenv("SSO_ENABLED", "FALSE"),
  default = FALSE,
  env_name = "SSO_ENABLED"
)

preflight_check_file_store <- normalize_preflight_bool(
  Sys.getenv("MERGEN_PREFLIGHT_CHECK_FILE_STORE", "FALSE"),
  default = FALSE,
  env_name = "MERGEN_PREFLIGHT_CHECK_FILE_STORE"
)

if (isTRUE(preflight_require_sso) && !isTRUE(preflight_sso_enabled)) {
  stop(
    paste(
      "VM preflight durduruldu.",
      "Bu gerçek VM preflight koşumu varsayılan olarak SSO ister.",
      "SSO_ENABLED=TRUE ayarlayın.",
      "Yerel/non-SSO smoke koşumu için MERGEN_PREFLIGHT_REQUIRE_SSO=FALSE kullanın."
    ),
    call. = FALSE
  )
}

required_env_vars <- c("LOCAL_LLM_ENDPOINT", "DB_DSN", "AI_KEYS_MASTER")

if (isTRUE(preflight_sso_enabled)) {
  required_env_vars <- c(required_env_vars, "SSO_KEYCLOAK_URL")
}

require_preflight_env_vars(required_env_vars)

.preflight_env_to_restore <- c(
  "MERGEN_DISABLE_FUTURES",
  "MERGEN_RUN_APP",
  "MERGEN_SQL_LOADER_STRICT"
)

.preflight_env_snapshot <- Sys.getenv(
  .preflight_env_to_restore,
  unset = NA_character_
)

on.exit({
  for (nm in names(.preflight_env_snapshot)) {
    old_value <- .preflight_env_snapshot[[nm]]

    if (is.na(old_value)) {
      Sys.unsetenv(nm)
    } else {
      do.call(Sys.setenv, stats::setNames(list(old_value), nm))
    }
  }
}, add = TRUE)

Sys.setenv(
  MERGEN_DISABLE_FUTURES = "true",
  MERGEN_RUN_APP = "false",
  MERGEN_SQL_LOADER_STRICT = "true"
)

source("tests/scripts/parse_sanity_check.R", encoding = "UTF-8")
source("tests/scripts/helpers_vm_preflight_checks.R", encoding = "UTF-8")
source("app.R", encoding = "UTF-8")

if (!exists("validate_boot_state", envir = globalenv(), mode = "function", inherits = FALSE)) {
  stop("VM preflight başarısız: validate_boot_state() tanımlanmadı.")
}

validate_boot_state()

if (isTRUE(preflight_sso_enabled)) {
  if (!exists("SSO_ENABLED", envir = globalenv(), inherits = FALSE)) {
    stop("VM preflight başarısız: SSO_ENABLED global değeri yüklenmedi.", call. = FALSE)
  }

  if (!isTRUE(SSO_ENABLED)) {
    stop(
      "VM preflight başarısız: SSO_ENABLED=TRUE bekleniyordu ancak app.R sonrası aktif değil.",
      call. = FALSE
    )
  }

  if (!exists("SSO_CONFIG", envir = globalenv(), inherits = FALSE) ||
      !is.list(SSO_CONFIG)) {
    stop("VM preflight başarısız: SSO_CONFIG yüklenmedi veya liste değil.", call. = FALSE)
  }

  required_sso_config_fields <- c(
    "keycloak_base_url",
    "issuer_url",
    "auth_endpoint",
    "logout_endpoint",
    "token_endpoint",
    "client_id",
    "realm"
  )

  missing_sso_config_fields <- required_sso_config_fields[!vapply(
    required_sso_config_fields,
    function(nm) {
      value <- SSO_CONFIG[[nm]]
      !is.null(value) && nzchar(trimws(as.character(value[1])))
    },
    logical(1)
  )]

  if (length(missing_sso_config_fields) > 0L) {
    stop(sprintf(
      "VM preflight başarısız: SSO_CONFIG eksik alan(lar): %s",
      paste(missing_sso_config_fields, collapse = ", ")
    ), call. = FALSE)
  }

  sso_url_fields <- c("issuer_url", "auth_endpoint", "logout_endpoint", "token_endpoint")
  bad_sso_urls <- sso_url_fields[!vapply(
    sso_url_fields,
    function(nm) {
      grepl("^https?://", as.character(SSO_CONFIG[[nm]][1]))
    },
    logical(1)
  )]

  if (length(bad_sso_urls) > 0L) {
    stop(sprintf(
      "VM preflight başarısız: SSO_CONFIG URL alanları geçersiz: %s",
      paste(bad_sso_urls, collapse = ", ")
    ), call. = FALSE)
  }

  cat(sprintf(
    "OK: SSO preflight yapılandırması doğrulandı. issuer=%s, client_id=%s\n",
    SSO_CONFIG$issuer_url,
    SSO_CONFIG$client_id
  ))
}

if (!exists("create_mergen_app", envir = globalenv(), mode = "function", inherits = FALSE)) {
  stop("VM preflight başarısız: create_mergen_app() tanımlanmadı.")
}

app_obj <- create_mergen_app()

if (!inherits(app_obj, "shiny.appobj")) {
  stop("VM preflight başarısız: create_mergen_app() shiny.appobj döndürmedi.")
}

cat("OK: app.R source edildi, validate_boot_state() geçti ve shiny.appobj oluşturuldu.\n")

# ----------------------------------------------------------------------
# Dosya sistemi / yazılabilirlik / UTF-8 / File Store / canlı kimlik on kontrolleri
# ----------------------------------------------------------------------
preflight_paths <- vm_preflight_check_core_writable_paths()
vm_preflight_check_atomic_write_probe(preflight_paths$active_log_dir)
vm_preflight_check_utf8_roundtrip(preflight_paths$active_log_dir)

if (isTRUE(preflight_check_file_store)) {
  vm_preflight_check_file_store_roundtrip()
} else {
  cat("INFO: File Store roundtrip preflight atlandı. Etkinleştirmek için MERGEN_PREFLIGHT_CHECK_FILE_STORE=TRUE ayarlayın.\n")
}

vm_preflight_check_live_user_id_provider_contract()

# ----------------------------------------------------------------------
# Gerçek DB sağlık kontrolü
# ----------------------------------------------------------------------
if (exists("db_pool_healthy", envir = globalenv(), mode = "function", inherits = FALSE)) {
  db_ok <- tryCatch(
    db_pool_healthy(timeout_sec = 5),
    error = function(e) {
      cat(sprintf("[DB CHECK ERROR] %s\n", conditionMessage(e)))
      FALSE
    }
  )

  if (!isTRUE(db_ok)) {
    stop("VM preflight başarısız: gerçek DB sağlık kontrolü başarısız.")
  }

  cat("OK: Gerçek DB sağlık kontrolü başarılı.\n")
} else {
  warning("db_pool_healthy() bulunamadı; DB sağlık kontrolü atlandı.")
}

# ----------------------------------------------------------------------
# Gerçek LLM endpoint erişilebilirlik kontrolü
# Bu adım model üretimi yapmaz; yalnızca endpoint'e ağ seviyesinde erişim
# kurulabildiğini doğrulamaya çalışır.
# ----------------------------------------------------------------------
llm_url <- Sys.getenv("LOCAL_LLM_ENDPOINT", "")

if (!nzchar(llm_url)) {
  stop("VM preflight başarısız: LOCAL_LLM_ENDPOINT boş.")
}

if (!requireNamespace("curl", quietly = TRUE)) {
  warning("curl paketi bulunamadı; LLM endpoint erişilebilirlik kontrolü atlandı.")
} else {
  probe_llm_endpoint <- function(url) {
    head_ok <- tryCatch({
      handle <- curl::new_handle(
        nobody = TRUE,
        customrequest = "HEAD",
        connecttimeout = 3,
        timeout = 5
      )

      res <- curl::curl_fetch_memory(url, handle = handle)
      is.list(res) && !is.null(res$status_code)
    }, error = function(e) {
      cat(sprintf("[LLM CHECK HEAD ERROR] %s\n", conditionMessage(e)))
      FALSE
    })

    if (isTRUE(head_ok)) {
      return(TRUE)
    }

    tryCatch({
      handle <- curl::new_handle(
        customrequest = "GET",
        range = "0-0",
        connecttimeout = 3,
        timeout = 5
      )

      res <- curl::curl_fetch_memory(url, handle = handle)
      is.list(res) && !is.null(res$status_code)
    }, error = function(e) {
      cat(sprintf("[LLM CHECK GET ERROR] %s\n", conditionMessage(e)))
      FALSE
    })
  }

  llm_probe_ok <- probe_llm_endpoint(llm_url)

  if (!isTRUE(llm_probe_ok)) {
    stop("VM preflight başarısız: gerçek LLM endpoint erişilebilirlik kontrolü başarısız.")
  }

  cat("OK: Gerçek LLM endpoint erişilebilirlik kontrolü başarılı.\n")
}

cat("OK: Windows VM gerçek preflight başarıyla tamamlandı.\n")
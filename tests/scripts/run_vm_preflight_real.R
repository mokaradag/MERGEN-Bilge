# ==============================================================================
# Dosya Yolu: tests/scripts/run_vm_preflight_real.R
# Açıklama: Windows VM üzerinde gerçek ortam değişkenleriyle uygulamanın
# production-benzeri ön kontrolünü yapar. Gerçek boot doğrulaması, gerçek
# veritabanı sağlık kontrolü ve LLM endpoint erişilebilirlik kontrolü içerir.
# ==============================================================================

required_env_vars <- c("LOCAL_LLM_ENDPOINT", "DB_DSN", "AI_KEYS_MASTER")
missing_vars <- required_env_vars[!nzchar(Sys.getenv(required_env_vars, ""))]

if (length(missing_vars) > 0) {
  stop(sprintf(
    "VM preflight durduruldu. Eksik ortam değişkenleri: %s",
    paste(missing_vars, collapse = ", ")
  ))
}

Sys.setenv(
  MERGEN_DISABLE_FUTURES = "true",
  MERGEN_RUN_APP = "false",
  MERGEN_SQL_LOADER_STRICT = "true"
)

source("tests/scripts/parse_sanity_check.R", encoding = "UTF-8")
source("app.R", encoding = "UTF-8")

if (!exists("validate_boot_state", envir = globalenv(), mode = "function", inherits = FALSE)) {
  stop("VM preflight başarısız: validate_boot_state() tanımlanmadı.")
}

validate_boot_state()

if (!exists("create_mergen_app", envir = globalenv(), mode = "function", inherits = FALSE)) {
  stop("VM preflight başarısız: create_mergen_app() tanımlanmadı.")
}

app_obj <- create_mergen_app()

if (!inherits(app_obj, "shiny.appobj")) {
  stop("VM preflight başarısız: create_mergen_app() shiny.appobj döndürmedi.")
}

cat("OK: app.R source edildi, validate_boot_state() geçti ve shiny.appobj oluşturuldu.\n")

# ----------------------------------------------------------------------
# Dosya sistemi / yazilabilirlik on kontrolleri
# ----------------------------------------------------------------------
check_writable_dir <- function(dir_path, label) {
  dir.create(dir_path, recursive = TRUE, showWarnings = FALSE)

  probe_file <- file.path(
    dir_path,
    sprintf(".preflight_write_probe_%s.tmp", as.integer(Sys.time()))
  )

  ok <- tryCatch({
    writeLines("ok", probe_file, useBytes = TRUE)
    file.exists(probe_file)
  }, error = function(e) FALSE)

  try(unlink(probe_file, force = TRUE), silent = TRUE)

  if (!isTRUE(ok)) {
    stop(sprintf(
      "VM preflight başarısız: %s yazılabilir değil (%s).",
      label,
      dir_path
    ))
  }

  cat(sprintf("OK: %s yazılabilir: %s\n", label, dir_path))
}

check_writable_dir("logs", "log dizini")
check_writable_dir("mergen_uploads", "MERGEN yükleme dizini")
check_writable_dir("destek_uploads", "destek yükleme dizini")
check_writable_dir("bilge_yolac_downloads", "Bilge Yolaç indirme dizini")

if (exists("atomic_write_text", envir = globalenv(), mode = "function", inherits = FALSE)) {
  atomic_probe <- file.path("logs", "preflight_atomic_write_probe.json")

  tryCatch({
    atomic_write_text('{"ok":true}', atomic_probe)
    if (!file.exists(atomic_probe)) {
      stop("atomic write probe dosyasi olusmadi.")
    }
    cat("OK: atomic_write_text probe başarılı.\n")
  }, error = function(e) {
    stop(sprintf(
      "VM preflight başarısız: atomic_write_text probe başarısız: %s",
      conditionMessage(e)
    ))
  }, finally = {
    try(unlink(atomic_probe, force = TRUE), silent = TRUE)
  })
} else {
  warning("atomic_write_text() bulunamadı; atomic write probe atlandı.")
}

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
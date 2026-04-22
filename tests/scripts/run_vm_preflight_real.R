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
  MERGEN_RUN_APP = "false"
)

source("tests/scripts/parse_sanity_check.R", encoding = "UTF-8")
source("app.R", encoding = "UTF-8")

if (!exists("safe_source", envir = globalenv(), mode = "function", inherits = FALSE)) {
  stop("VM preflight başarısız: safe_source() tanımlanmadı.")
}

if (!exists("ui", envir = globalenv(), inherits = FALSE)) {
  stop("VM preflight başarısız: ui nesnesi tanımlanmadı.")
}

if (!exists("server", envir = globalenv(), mode = "function", inherits = FALSE)) {
  stop("VM preflight başarısız: server fonksiyonu tanımlanmadı.")
}

if (!exists("create_mergen_app", envir = globalenv(), mode = "function", inherits = FALSE)) {
  stop("VM preflight başarısız: create_mergen_app() tanımlanmadı.")
}

app_obj <- create_mergen_app()

if (!inherits(app_obj, "shiny.appobj")) {
  stop("VM preflight başarısız: create_mergen_app() shiny.appobj döndürmedi.")
}

cat("OK: app.R source edildi ve shiny.appobj oluşturuldu.\n")

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
  llm_probe_ok <- tryCatch({
    handle <- curl::new_handle(
      nobody = TRUE,
      customrequest = "HEAD",
      timeout = 5
    )

    res <- curl::curl_fetch_memory(llm_url, handle = handle)

    # Herhangi bir HTTP yanıtı almak erişilebilirlik için yeterlidir.
    is.list(res) && !is.null(res$status_code)
  }, error = function(e) {
    cat(sprintf("[LLM CHECK ERROR] %s\n", conditionMessage(e)))
    FALSE
  })

  if (!isTRUE(llm_probe_ok)) {
    stop("VM preflight başarısız: gerçek LLM endpoint erişilebilirlik kontrolü başarısız.")
  }

  cat("OK: Gerçek LLM endpoint erişilebilirlik kontrolü başarılı.\n")
}

cat("OK: Windows VM gerçek preflight başarıyla tamamlandı.\n")
# ==============================================================================
# Dosya Yolu: tests/scripts/smoke_app_boot.R
# Açıklama: app.R ana giriş noktasının CI ortamında uygulamayı gerçekten
# başlatmadan source edilebildiğini ve create_mergen_app() fonksiyonunun
# geçerli bir shiny.appobj döndürdüğünü doğrulayan smoke test betiği.
# ==============================================================================

Sys.setenv(
  MERGEN_RUN_APP = "false",
  MERGEN_DISABLE_FUTURES = "true"
)

# config_file_store.R zorunlu değişkenleri ister; CI'de placeholder yeterlidir.
if (!nzchar(Sys.getenv("LOCAL_LLM_ENDPOINT", ""))) {
  Sys.setenv(LOCAL_LLM_ENDPOINT = "http://test.local/v1")
}

if (!nzchar(Sys.getenv("DB_DSN", ""))) {
  Sys.setenv(DB_DSN = "test-dsn")
}

if (!nzchar(Sys.getenv("AI_KEYS_MASTER", ""))) {
  Sys.setenv(AI_KEYS_MASTER = "test-master-key-ci-placeholder")
}

source("app.R", encoding = "UTF-8")

if (!exists("safe_source", envir = globalenv(), mode = "function", inherits = FALSE)) {
  stop("Smoke test başarısız: safe_source() tanımlanmadı.")
}

if (!exists("ui", envir = globalenv(), inherits = FALSE)) {
  stop("Smoke test başarısız: ui nesnesi tanımlanmadı.")
}

if (!exists("server", envir = globalenv(), mode = "function", inherits = FALSE)) {
  stop("Smoke test başarısız: server fonksiyonu tanımlanmadı.")
}

if (!exists("create_mergen_app", envir = globalenv(), mode = "function", inherits = FALSE)) {
  stop("Smoke test başarısız: create_mergen_app() tanımlanmadı.")
}

app_obj <- create_mergen_app()

if (!inherits(app_obj, "shiny.appobj")) {
  stop("Smoke test başarısız: create_mergen_app() shiny.appobj döndürmedi.")
}

cat("OK: app.R source edildi ve create_mergen_app() shiny.appobj döndürdü.\n")
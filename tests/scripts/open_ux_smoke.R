# ==============================================================================
# Dosya Yolu: tests/scripts/open_ux_smoke.R
# Açıklama: Repo-local UX smoke sayfasını varsayılan tarayıcıda açar.
# ==============================================================================

is_env_true <- function(name) {
  value <- Sys.getenv(name, unset = "")
  value <- tolower(trimws(value))
  value %in% c("1", "true", "yes", "evet")
}

base_url <- Sys.getenv("MERGEN_SMOKE_BASE_URL", unset = "http://127.0.0.1:3838")
base_url <- sub("/+$", "", base_url)

base_url_was_default <- !nzchar(Sys.getenv("MERGEN_SMOKE_BASE_URL", unset = ""))

sso_enabled <- tolower(trimws(Sys.getenv("SSO_ENABLED", unset = ""))) %in%
  c("1", "true", "yes", "evet")

if (isTRUE(sso_enabled) && isTRUE(base_url_was_default)) {
  warning(
    paste(
      "SSO_ENABLED=TRUE görünüyor ancak MERGEN_SMOKE_BASE_URL verilmemiş.",
      "127.0.0.1 üzerinden SSO/Keycloak yönlendirmesi iframe'i cross-origin yapabilir.",
      "VM/üretim smoke için gerçek uygulama adresini kullanın:",
      "Sys.setenv(MERGEN_SMOKE_BASE_URL = 'https://mergen.aselsan.com.tr/bilge')",
      sep = "\n"
    ),
    call. = FALSE
  )
}

smoke_url <- paste0(base_url, "/smoke/ux-smoke.html")

if (is_env_true("MERGEN_SMOKE_FULL_QUICK_ACTIONS")) {
  smoke_url <- paste0(smoke_url, "?fullQuickActions=1")
}

cat("UX smoke sayfası:\n", smoke_url, "\n\n", sep = "")
cat("Önce uygulamanın çalıştığından emin olun. Örnek:\n")
cat("Rscript -e \"shiny::runApp('.', host='127.0.0.1', port=3838, launch.browser=FALSE)\"\n\n")
cat("Başarılı sonuç: UX_SMOKE_DONE:PASS\n")

utils::browseURL(smoke_url)

invisible(smoke_url)
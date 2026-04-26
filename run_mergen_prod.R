# ==============================================================================
# Dosya Yolu: run_mergen_prod.R
# Aciklama: MERGEN Bilge uretim R giris noktasi.
# ==============================================================================

options(encoding = "UTF-8")

Sys.setenv(MERGEN_RUN_APP = "false")

source("app.R", encoding = "UTF-8")

host <- Sys.getenv("MERGEN_HOST", "0.0.0.0")
port <- Sys.getenv("MERGEN_PORT", "8009")

validate_boot_state()
run_mergen_app(
  host = host,
  port = port,
  launch.browser = FALSE,
  quiet = FALSE
)

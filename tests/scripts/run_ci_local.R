# ==============================================================================
# Dosya Yolu: tests/scripts/run_ci_local.R
# Açıklama: GitHub Actions'taki CI akışının yerel eşdeğerini çalıştırır.
# Gerçek DB/LLM erişimi beklemez; placeholder değişkenlerle parse, smoke ve
# testthat adımlarını sırayla yürütür.
# ==============================================================================

Sys.setenv(
  MERGEN_DISABLE_FUTURES = "true",
  MERGEN_RUN_APP = "false",
  MERGEN_SQL_LOADER_STRICT = "false",
  LOCAL_LLM_ENDPOINT = "http://test.local/v1",
  DB_DSN = "test-dsn",
  AI_KEYS_MASTER = "test-master-key-ci-placeholder"
)

source("tests/scripts/parse_sanity_check.R", encoding = "UTF-8")
source("tests/scripts/smoke_app_boot.R", encoding = "UTF-8")
source("tests/testthat.R", encoding = "UTF-8")

cat("OK: Yerel CI eşdeğeri başarıyla tamamlandı.\n")
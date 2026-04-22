# ==============================================================================
# Dosya Yolu: tests/testthat.R
# Açıklama: testthat altyapısını başlatır ve tests/testthat altındaki tüm
# birim testlerini özet raporlayıcı ile çalıştırır.
# ==============================================================================

library(testthat)

Sys.setenv(TZ = "UTC")
testthat::local_edition(3)

results <- testthat::test_dir(
  "tests/testthat",
  reporter = "summary",
  stop_on_failure = TRUE,
  stop_on_warning = TRUE
)

invisible(results)
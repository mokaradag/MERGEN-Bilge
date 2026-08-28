# ==============================================================================
# Dosya Yolu: tests/testthat.R
# Açıklama: testthat altyapısını başlatır ve tests/testthat altındaki tüm
# birim testlerini özet raporlayıcı ile çalıştırır.
# ==============================================================================

library(testthat)

repo_root <- normalizePath(".", winslash = "/", mustWork = TRUE)
if (!file.exists(file.path(repo_root, "app.R")) ||
    !dir.exists(file.path(repo_root, "tests", "testthat"))) {
  stop(
    "tests/testthat.R repo kökünden çalıştırılmalıdır.",
    call. = FALSE
  )
}

Sys.setenv(TZ = "UTC")

# Test koşumu hiçbir durumda Shiny uygulamasını veya paralel worker cluster'ını
# başlatmamalıdır. Bu bayraklar helper_bootstrap.R'de de var; burada tekrar
# edilmesi test giriş noktasını kendi başına güvenli yapar.
Sys.setenv(
  MERGEN_RUN_APP = "false",
  MERGEN_DISABLE_FUTURES = "true"
)

testthat::local_edition(3)

results <- testthat::test_dir(
  file.path("tests", "testthat"),
  reporter = "summary",
  stop_on_failure = TRUE,
  stop_on_warning = TRUE
)

invisible(results)

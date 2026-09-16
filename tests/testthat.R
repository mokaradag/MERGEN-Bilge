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

# testthat SÜRÜMÜ AÇIKÇA BİLDİRİLİR. Depoda DESCRIPTION / Config/testthat/edition
# yoktur; bildirim olmadan `find_edition()` sessizce 2. sürüme düşer ve CI hangi
# sürümün koştuğunu bilmeden yeşile döner. Bildirim ortam değişkeniyle yapılır ve
# YALNIZCA `test_dir()` çağrısını kapsar; `testthat::local_edition(3)` ÜST DÜZEYDE
# çağrılmaz, çünkü küresel bir ertelenmiş işleyici kaydedip Rscript çıkışında
# "deferred_run fonksiyonu bulunamadı" hatası üretiyordu.
results <- local({
  onceki_edition <- Sys.getenv("TESTTHAT_EDITION", unset = NA_character_)
  on.exit({
    if (is.na(onceki_edition)) {
      Sys.unsetenv("TESTTHAT_EDITION")
    } else {
      Sys.setenv(TESTTHAT_EDITION = onceki_edition)
    }
  }, add = TRUE)

  Sys.setenv(TESTTHAT_EDITION = "3")

  testthat::test_dir(
    file.path("tests", "testthat"),
    reporter = "summary",
    stop_on_failure = TRUE,
    stop_on_warning = TRUE
  )
})

invisible(results)

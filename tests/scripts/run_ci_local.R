# ==============================================================================
# Dosya Yolu: tests/scripts/run_ci_local.R
# Açıklama: GitHub Actions'taki CI akışının yerel eşdeğerini çalıştırır.
# Gerçek DB/LLM erişimi beklemez; placeholder değişkenlerle parse ve smoke
# adımlarını mevcut oturumda, testthat adımını ise AYRI ve temiz bir R oturumunda
# yürütür.
#
# Neden?
# - Smoke + testthat aynı oturumda çalışınca global ortama yüklenmiş helper
#   fonksiyonları testlerin beklediği temiz başlangıç durumunu bozabiliyor.
# - Özellikle atomic_write_text gibi helper'lar test dosyalarında "yoksa source et"
#   mantığıyla yüklendiği için, temiz child-session en güvenli çözümdür.
# ==============================================================================

Sys.setenv(
  MERGEN_DISABLE_FUTURES = "true",
  MERGEN_RUN_APP = "false",
  MERGEN_SQL_LOADER_STRICT = "false",
  LOCAL_LLM_ENDPOINT = "http://test.local/v1",
  DB_DSN = "test-dsn",
  AI_KEYS_MASTER = "test-master-key-ci-placeholder"
)

# 1) Parse kontrolü (mevcut oturum)
source("tests/scripts/parse_sanity_check.R", encoding = "UTF-8")

# 2) Smoke boot kontrolü (mevcut oturum)
source("tests/scripts/smoke_app_boot.R", encoding = "UTF-8")

# 3) Testthat'i temiz bir child R oturumunda çalıştır
rscript_bin <- file.path(R.home("bin"), "Rscript")
if (.Platform$OS.type == "windows") {
  rscript_bin <- paste0(rscript_bin, ".exe")
}

if (!file.exists(rscript_bin)) {
  stop(sprintf("Rscript bulunamadi: %s", rscript_bin))
}

test_runner_file <- tempfile(pattern = "run_testthat_clean_", fileext = ".R")
child_stdout_log <- tempfile(pattern = "run_testthat_stdout_", fileext = ".log")
child_stderr_log <- tempfile(pattern = "run_testthat_stderr_", fileext = ".log")

on.exit(
  unlink(c(test_runner_file, child_stdout_log, child_stderr_log), force = TRUE),
  add = TRUE
)

runner_lines <- c(
  "Sys.setenv(",
  "  MERGEN_DISABLE_FUTURES = 'true',",
  "  MERGEN_RUN_APP = 'false',",
  "  MERGEN_SQL_LOADER_STRICT = 'false',",
  "  LOCAL_LLM_ENDPOINT = 'http://test.local/v1',",
  "  DB_DSN = 'test-dsn',",
  "  AI_KEYS_MASTER = 'test-master-key-ci-placeholder',",
  "  TZ = 'UTC'",
  ")",
  "",
  "source('tests/testthat.R', encoding = 'UTF-8')"
)

writeLines(enc2utf8(runner_lines), test_runner_file, useBytes = TRUE)

exit_status <- system2(
  rscript_bin,
  args = c("--vanilla", test_runner_file),
  stdout = child_stdout_log,
  stderr = child_stderr_log
)

if (!identical(exit_status, 0L)) {
  child_stdout <- tryCatch(
    paste(readLines(child_stdout_log, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
    error = function(e) ""
  )
  child_stderr <- tryCatch(
    paste(readLines(child_stderr_log, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
    error = function(e) ""
  )

  stop(sprintf(
    paste0(
      "run_ci_local: testthat child session basarisiz oldu (exit code: %s).\n",
      "--- CHILD STDOUT ---\n%s\n",
      "--- CHILD STDERR ---\n%s"
    ),
    exit_status,
    child_stdout,
    child_stderr
  ))
}

cat("OK: Yerel CI eşdeğeri başarıyla tamamlandı.\n")
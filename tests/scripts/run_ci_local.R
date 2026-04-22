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
on.exit(unlink(test_runner_file, force = TRUE), add = TRUE)

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
  args = c(test_runner_file),
  stdout = "",
  stderr = ""
)

if (!identical(exit_status, 0L)) {
  stop(sprintf("run_ci_local: testthat child session basarisiz oldu (exit code: %s).", exit_status))
}

cat("OK: Yerel CI eşdeğeri başarıyla tamamlandı.\n")
# ==============================================================================
# Dosya Yolu: tests/testthat/test-run-mergen-prod-boot-log-contract.R
# Açıklama: Üretim başlatıcısının app.R/config_logging yüklenmeden önce
#           bugünkü mergen_YYYYMMDD.log dosyasına tanılama yazma sözleşmesi.
# ==============================================================================

testthat::local_edition(3)

run_prod_path <- file.path(resolve_repo_root_for_tests(), "run_mergen_prod.R")
run_prod_text <- readLines(run_prod_path, encoding = "UTF-8", warn = FALSE)
run_prod_joined <- paste(run_prod_text, collapse = "\n")

test_that("run_mergen_prod.R parses after production boot logging changes", {
  expect_no_error(parse(file = run_prod_path, encoding = "UTF-8"))
})

test_that("run_mergen_prod.R creates mergen daily log before sourcing app.R", {
  app_source_pos <- grep('source\\("app\\.R"', run_prod_text)
  boot_log_pos <- grep('write_prod_boot_log\\("INFO", "app\\.R source ediliyor\\.\\.\\."', run_prod_text)

  expect_length(app_source_pos, 1)
  expect_length(boot_log_pos, 1)
  expect_lt(boot_log_pos, app_source_pos)
  expect_match(run_prod_joined, "sprintf\\(\"mergen_%s\\.log\"")
  expect_match(run_prod_joined, "dir\\.create\\(log_dir, recursive = TRUE")
})

test_that("run_mergen_prod.R logs startup failures to the daily mergen log", {
  expect_match(run_prod_joined, "tryCatch\\(\\{")
  expect_match(run_prod_joined, "Üretim başlatması hata ile durdu")
  expect_match(run_prod_joined, "Eksik zorunlu ortam değişkenleri")
})

# ==============================================================================
# Dosya Yolu: tests/testthat/test-vm-preflight-contract.R
# Aciklama: run_vm_preflight_real.R icindeki kritik operasyonel kontratlari
# statik olarak korur.
# ==============================================================================

parse_repo_code_text_vm <- function(rel_path) {
  abs_path <- file.path(repo_root_for_tests, rel_path)

  if (!file.exists(abs_path)) {
    stop(sprintf("Dosya bulunamadi: %s", rel_path))
  }

  exprs <- parse(
    file = abs_path,
    keep.source = FALSE,
    encoding = "UTF-8"
  )

  paste(
    vapply(
      exprs,
      function(expr) paste(deparse(expr, width.cutoff = 500L), collapse = "\n"),
      character(1)
    ),
    collapse = "\n"
  )
}

test_that("run_vm_preflight_real kritik kontrolleri korur", {
  txt <- parse_repo_code_text_vm(file.path("tests", "scripts", "run_vm_preflight_real.R"))

  expect_true(grepl('required_env_vars <- c\\("LOCAL_LLM_ENDPOINT", "DB_DSN", "AI_KEYS_MASTER"\\)', txt))
  expect_true(grepl('source\\("tests/scripts/parse_sanity_check\\.R"', txt))
  expect_true(grepl('source\\("app\\.R"', txt))
  expect_true(grepl("validate_boot_state\\(", txt))
  expect_true(grepl("create_mergen_app\\(", txt))
  expect_true(grepl("db_pool_healthy\\(", txt))
  expect_true(grepl("curl::new_handle", txt, fixed = TRUE))

  expect_true(grepl("check_writable_dir <- function", txt, fixed = TRUE))
  expect_true(grepl('check_writable_dir\\("logs"', txt))
  expect_true(grepl('check_writable_dir\\("mergen_uploads"', txt))
  expect_true(grepl('check_writable_dir\\("destek_uploads"', txt))
  expect_true(grepl('check_writable_dir\\("bilge_yolac_downloads"', txt))
  expect_true(grepl("atomic_write_text\\(", txt))
})
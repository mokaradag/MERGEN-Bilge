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

  expect_true(grepl("normalize_preflight_bool <- function", txt, fixed = TRUE))
  expect_true(grepl("require_preflight_env_vars <- function", txt, fixed = TRUE))
  expect_true(grepl("MERGEN_PREFLIGHT_REQUIRE_SSO", txt, fixed = TRUE))
  expect_true(grepl("preflight_sso_enabled <- normalize_preflight_bool", txt, fixed = TRUE))
  expect_true(grepl('required_env_vars <- c\\("LOCAL_LLM_ENDPOINT", "DB_DSN", "AI_KEYS_MASTER"\\)', txt))
  expect_true(grepl('"SSO_KEYCLOAK_URL"', txt, fixed = TRUE))
  expect_true(grepl("required_sso_config_fields <- c", txt, fixed = TRUE))
  expect_true(grepl('"issuer_url"', txt, fixed = TRUE))
  expect_true(grepl('"auth_endpoint"', txt, fixed = TRUE))
  expect_true(grepl('"logout_endpoint"', txt, fixed = TRUE))
  expect_true(grepl('"token_endpoint"', txt, fixed = TRUE))
  expect_true(grepl("bad_sso_urls", txt, fixed = TRUE))
  expect_true(grepl("SSO preflight", txt, fixed = TRUE))

  expect_true(grepl('source\\("tests/scripts/parse_sanity_check\\.R"', txt))
  expect_true(grepl('source\\("tests/scripts/helpers_vm_preflight_checks\\.R"', txt))
  expect_true(grepl('source\\("app\\.R"', txt))
  expect_true(grepl("validate_boot_state\\(", txt))
  expect_true(grepl("create_mergen_app\\(", txt))
  expect_true(grepl("db_pool_healthy\\(", txt))
  expect_true(grepl("curl::new_handle", txt, fixed = TRUE))

  expect_true(grepl("preflight_paths <- vm_preflight_check_core_writable_paths\\(", txt))
  expect_true(grepl("vm_preflight_check_atomic_write_probe\\(preflight_paths\\$active_log_dir\\)", txt))
  expect_true(grepl("vm_preflight_check_utf8_roundtrip\\(preflight_paths\\$active_log_dir\\)", txt))
  expect_true(grepl("vm_preflight_check_file_store_roundtrip\\(", txt))
  expect_true(grepl("vm_preflight_check_live_user_id_provider_contract\\(", txt))
})
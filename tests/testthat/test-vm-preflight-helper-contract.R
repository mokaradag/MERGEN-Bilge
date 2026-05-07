# ==============================================================================
# Dosya Yolu: tests/testthat/test-vm-preflight-helper-contract.R
# Açıklama: Windows VM preflight helper dosyasının kritik üretim kontrollerini
#           statik ve hızlı biçimde korur. Bu test app.R veya gerçek preflight
#           çalıştırmaz.
# ==============================================================================

.read_vm_preflight_text <- function(rel_path) {
  full_path <- file.path(repo_root_for_tests, rel_path)

  if (!file.exists(full_path)) {
    stop(sprintf("Dosya bulunamadı: %s", rel_path), call. = FALSE)
  }

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

test_that("VM preflight helper kritik fonksiyonları tanımlar", {
  helper_txt <- .read_vm_preflight_text(
    file.path("tests", "scripts", "helpers_vm_preflight_checks.R")
  )

  expected_definitions <- c(
    "vm_preflight_check_core_writable_paths <- function",
    "vm_preflight_check_atomic_write_probe <- function",
    "vm_preflight_check_utf8_roundtrip <- function",
    "vm_preflight_check_file_store_roundtrip <- function",
    "vm_preflight_check_live_user_id_provider_contract <- function"
  )

  found <- vapply(
    expected_definitions,
    function(pattern) grepl(pattern, helper_txt, fixed = TRUE),
    logical(1)
  )

  expect_true(
    all(found),
    info = paste(
      "VM preflight helper kritik fonksiyon tanımları eksik:",
      paste(expected_definitions[!found], collapse = ", ")
    )
  )
})

test_that("run_vm_preflight_real helper dosyasını kaynaklar ve kritik kontrolleri çağırır", {
  script_txt <- .read_vm_preflight_text(
    file.path("tests", "scripts", "run_vm_preflight_real.R")
  )

  expected_calls <- c(
    'source("tests/scripts/helpers_vm_preflight_checks.R"',
    "preflight_paths <- vm_preflight_check_core_writable_paths()",
    "vm_preflight_check_atomic_write_probe(preflight_paths$active_log_dir)",
    "vm_preflight_check_utf8_roundtrip(preflight_paths$active_log_dir)",
    "preflight_check_file_store <- normalize_preflight_bool",
    "MERGEN_PREFLIGHT_CHECK_FILE_STORE",
    "if (isTRUE(preflight_check_file_store))",
    "vm_preflight_check_file_store_roundtrip()",
    "vm_preflight_check_live_user_id_provider_contract()"
  )

  found <- vapply(
    expected_calls,
    function(pattern) grepl(pattern, script_txt, fixed = TRUE),
    logical(1)
  )

  expect_true(
    all(found),
    info = paste(
      "run_vm_preflight_real.R helper çağrı sözleşmesi eksik:",
      paste(expected_calls[!found], collapse = ", ")
    )
  )
})

test_that("run_vm_preflight_real preflight env değişikliklerini on.exit ile geri alır", {
  script_txt <- .read_vm_preflight_text(
    file.path("tests", "scripts", "run_vm_preflight_real.R")
  )

  expected_patterns <- c(
    ".preflight_env_to_restore <- c(",
    '"MERGEN_DISABLE_FUTURES"',
    '"MERGEN_RUN_APP"',
    '"MERGEN_SQL_LOADER_STRICT"',
    ".preflight_env_snapshot <- Sys.getenv(",
    "on.exit({",
    "Sys.unsetenv(nm)",
    "Sys.setenv"
  )

  found <- vapply(
    expected_patterns,
    function(pattern) grepl(pattern, script_txt, fixed = TRUE),
    logical(1)
  )

  expect_true(
    all(found),
    info = paste(
      "run_vm_preflight_real.R env restore sözleşmesi eksik:",
      paste(expected_patterns[!found], collapse = ", ")
    )
  )
})
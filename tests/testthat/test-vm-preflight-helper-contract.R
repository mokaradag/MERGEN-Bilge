# ==============================================================================
# Dosya Yolu: tests/testthat/test-vm-preflight-helper-contract.R
# Açıklama: Windows VM preflight helper dosyasının kritik üretim kontrollerini
#           koruduğunu doğrular.
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

.load_vm_preflight_helper_for_tests <- function() {
  helper_env <- new.env(parent = globalenv())

  source(
    file.path(repo_root_for_tests, "tests", "scripts", "helpers_vm_preflight_checks.R"),
    encoding = "UTF-8",
    local = helper_env
  )

  helper_env
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

test_that("VM preflight helper yazılabilirlik ve UTF-8 roundtrip kontrollerini çalıştırır", {
  helper_env <- .load_vm_preflight_helper_for_tests()
  tmp_dir <- withr::local_tempdir(pattern = "vm-preflight-helper-")

  expect_true(
    is.character(helper_env$vm_preflight_check_writable_dir(tmp_dir, "test temp dir"))
  )

  expect_true(
    isTRUE(helper_env$vm_preflight_check_utf8_roundtrip(tmp_dir))
  )
})

test_that("VM preflight helper canlı user id provider kontratını çalıştırır", {
  source(
    file.path(repo_root_for_tests, "R", "helpers_user_session_identity.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  helper_env <- .load_vm_preflight_helper_for_tests()

  expect_true(
    isTRUE(helper_env$vm_preflight_check_live_user_id_provider_contract())
  )
})
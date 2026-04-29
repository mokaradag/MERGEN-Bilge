# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-manager-refresh-guard-contract.R
# Açıklama: Dosya Yönetimi kalıcı dosya yenileme istek nesli korumasını doğrular.
# ==============================================================================

.load_file_manager_refresh_guard_helpers <- function() {
  repo_root <- resolve_repo_root_for_tests()
  helper_env <- new.env(parent = globalenv())

  source(
    file.path(repo_root, "R", "helpers_file_manager_refresh_guard.R"),
    encoding = "UTF-8",
    local = helper_env
  )

  helper_env
}

test_that("file manager refresh guard monotonik istek kimliği üretir", {
  env <- .load_file_manager_refresh_guard_helpers()
  guard <- env$fm_create_refresh_request_guard()

  expect_equal(guard$current(), 0L)

  first_id <- guard$next_id()
  second_id <- guard$next_id()

  expect_equal(first_id, 1L)
  expect_equal(second_id, 2L)
  expect_false(guard$is_latest(first_id))
  expect_true(guard$is_latest(second_id))
  expect_equal(guard$current(), 2L)
})

test_that("file manager refresh guard geçersiz request id değerlerini en son saymaz", {
  env <- .load_file_manager_refresh_guard_helpers()
  guard <- env$fm_create_refresh_request_guard(start_at = 5L)

  latest_id <- guard$next_id()

  expect_equal(latest_id, 6L)
  expect_false(guard$is_latest(NULL))
  expect_false(guard$is_latest(NA))
  expect_false(guard$is_latest("gecersiz"))
  expect_false(guard$is_latest(5L))
  expect_true(guard$is_latest("6"))
})
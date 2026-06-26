# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-manager-delete-runtime-behavior.R
# Açıklama: Dosya Yöneticisi kalıcı silme helper davranışını doğrular.
# ==============================================================================

.load_file_manager_delete_runtime_helpers <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  source(
    file.path(repo_root, "R", "helpers_file_manager_delete_runtime.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

test_that("fm_delete_persisted_file_artifacts doğrudan kalıcı yolu siler ve indeksi temizler", {
  env <- .load_file_manager_delete_runtime_helpers()
  temp_dir <- withr::local_tempdir()
  target <- file.path(temp_dir, "Türkçe dosya.txt")
  writeLines("içerik", target, useBytes = TRUE)

  removed_index <- list()
  result <- env$fm_delete_persisted_file_artifacts(
    info = list(name = "Türkçe dosya.txt", persisted_path = target),
    uid = "u42",
    get_user_upload_dir = function() temp_dir,
    path_exists_fn = file.exists,
    unlink_fn = function(x, force = FALSE) base::unlink(x, force = force),
    resolve_fn = function(...) stop("resolve çağrılmamalı"),
    remove_index_fn = function(uid, name) removed_index <<- list(uid = uid, name = name)
  )

  expect_true(result$deleted_physical)
  expect_identical(result$deleted_path, target)
  expect_false(file.exists(target))
  expect_identical(removed_index, list(uid = "u42", name = "Türkçe dosya.txt"))
})

test_that("fm_delete_persisted_file_artifacts resolve ve fallback sırasını korur", {
  env <- .load_file_manager_delete_runtime_helpers()
  temp_dir <- withr::local_tempdir()
  resolved <- file.path(temp_dir, "çözülmüş.xlsx")
  fallback <- file.path(temp_dir, "rapor.xlsx")
  writeLines("resolved", resolved, useBytes = TRUE)
  writeLines("fallback", fallback, useBytes = TRUE)

  calls <- character()
  result <- env$fm_delete_persisted_file_artifacts(
    info = list(name = "rapor.xlsx", datapath = file.path(temp_dir, "yok.xlsx")),
    uid = "u43",
    get_user_upload_dir = function() temp_dir,
    path_exists_fn = function(path) file.exists(path),
    unlink_fn = function(x, force = FALSE) {
      calls <<- c(calls, x)
      base::unlink(x, force = force)
    },
    resolve_fn = function(name, user_id) {
      expect_identical(name, "rapor.xlsx")
      expect_identical(user_id, "u43")
      resolved
    },
    remove_index_fn = function(uid, name) invisible(TRUE)
  )

  expect_true(result$deleted_physical)
  expect_identical(result$deleted_path, resolved)
  expect_identical(calls, resolved)
  expect_false(file.exists(resolved))
  expect_true(file.exists(fallback))
})

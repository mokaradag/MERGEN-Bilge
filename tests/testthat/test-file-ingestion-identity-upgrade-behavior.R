# Zayıf Windows metadata kanıtı terfi sırasında güçlü kimliğe yükseltilebilir;
# kalıcı sahiplik ve rollback device/inode ya da SHA-256 kanıtıyla açılır.

test_that("zayıf terfi kanıtı güçlü hedef kimliğine yükselir", {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  source(file.path(resolve_repo_root_for_tests(), "R/helpers_file_ingestion_identity.R"),
    local = env, encoding = "UTF-8")
  env$resolve_readable_path <- base::identity

  dest <- withr::local_tempfile(fileext = ".bin")
  writeBin(as.raw(c(1, 2, 3, 4)), dest)
  marker <- withr::local_tempfile()
  unlink(marker)
  env$file_ingestion_owner_path <- function(...) marker
  env$path_exists_relaxed <- function(path) file.exists(path)

  info <- file.info(dest)
  weak <- list(
    size = as.character(info$size[1]),
    modification_time = as.character(info$mtime[1])
  )
  strong <- c(list(device_id = "7", inode = "42"), weak)

  saveRDS(list(id = "tx", state = "copying"), marker)
  saveRDS(list(id = "tx", state = "promoting", file_key = weak), paste0(marker, ".identity"))
  env$file_ingestion_physical_identity <- function(...) strong

  owner <- env$file_ingestion_read_owner(dest)
  expect_identical(owner$state, "claimed")
  expect_identical(attr(owner$identity, "file_key"), strong)

  env$file_ingestion_physical_identity <- function(...) weak
  weak_identity <- env$file_ingestion_file_identity(dest)
  env$file_ingestion_physical_identity <- function(...) strong
  strong_identity <- env$file_ingestion_file_identity(dest)
  expect_true(env$file_ingestion_identity_matches(strong_identity, weak_identity))
  expect_false(env$file_ingestion_identity_matches(weak_identity, strong_identity))
})

test_that("zayıf son kimlik kalıcı sahiplik açmaz", {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  source(file.path(resolve_repo_root_for_tests(), "R/helpers_file_ingestion_identity.R"),
    local = env, encoding = "UTF-8")
  env$resolve_readable_path <- base::identity

  dest <- withr::local_tempfile(fileext = ".bin")
  writeBin(as.raw(c(5, 6, 7, 8)), dest)
  marker <- withr::local_tempfile()
  unlink(marker)
  env$file_ingestion_owner_path <- function(...) marker
  env$path_exists_relaxed <- function(path) file.exists(path)
  env$.file_store_with_index_lock <- function(expr, ...) force(expr)

  info <- file.info(dest)
  weak <- list(
    size = as.character(info$size[1]),
    modification_time = as.character(info$mtime[1])
  )
  env$file_ingestion_physical_identity <- function(...) weak

  saveRDS(list(id = "tx", state = "copying"), marker)
  saveRDS(list(id = "tx", state = "promoting", file_key = weak), paste0(marker, ".identity"))
  expect_identical(env$file_ingestion_read_owner(dest)$state, "copying")

  unlink(c(marker, paste0(marker, ".identity")))
  expected <- env$file_ingestion_file_identity(dest)
  env$file_ingestion_write_owner <- function(...) stop("weak-claim-escaped")
  expect_error(
    env$file_ingestion_claim_artifact(dest, expected = expected),
    "Kopyalanan dosyanın sahipliği doğrulanamadı",
    fixed = TRUE
  )
})

test_that("zayıf doğrulama güçlü güncel kanıtla güvenle temizlenir", {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  source(file.path(resolve_repo_root_for_tests(), "R/helpers_file_ingestion_identity.R"),
    local = env, encoding = "UTF-8")
  env$resolve_readable_path <- base::identity

  dest <- withr::local_tempfile(fileext = ".bin")
  writeBin(as.raw(c(9, 10, 11, 12)), dest)
  marker <- withr::local_tempfile()
  unlink(marker)
  env$file_ingestion_owner_path <- function(...) marker
  env$path_exists_relaxed <- function(path) file.exists(path)
  env$.file_store_with_index_lock <- function(expr, ...) force(expr)
  env$file_ingestion_discard_dest <- function(dest_path, ...) {
    unlink(dest_path, force = TRUE)
    invisible(TRUE)
  }

  info <- file.info(dest)
  weak <- list(
    size = as.character(info$size[1]),
    modification_time = as.character(info$mtime[1])
  )
  strong <- c(list(device_id = "11", inode = "99"), weak)
  env$file_ingestion_physical_identity <- function(...) weak
  expected <- env$file_ingestion_file_identity(dest)
  env$file_ingestion_physical_identity <- function(...) strong

  env$file_ingestion_discard_unclaimed(dest, "", expected)
  expect_false(file.exists(dest))
  expect_false(file.exists(marker))
})

test_that("inode'suz paylaşım SHA-256 ile sahiplik ve rollback kanıtlar", {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  source(file.path(resolve_repo_root_for_tests(), "R/helpers_file_ingestion_identity.R"),
    local = env, encoding = "UTF-8")
  env$resolve_readable_path <- base::identity

  dest <- withr::local_tempfile(fileext = ".bin")
  writeBin(as.raw(c(13, 14, 15, 16)), dest)
  marker <- withr::local_tempfile()
  unlink(marker)
  env$file_ingestion_owner_path <- function(...) marker
  env$path_exists_relaxed <- function(path) file.exists(path)
  env$.file_store_with_index_lock <- function(expr, ...) force(expr)

  fixed <- base::file.info(dest)[c("size", "mtime", "ctime")]
  env$file.info <- function(...) fixed
  testthat::local_mocked_bindings(file_info = function(...) data.frame(
    size = fixed$size[1], modification_time = fixed$mtime[1],
    device_id = 1, inode = 0
  ), .package = "fs")

  weak <- env$file_ingestion_physical_identity(dest)
  expect_false("content_sha256" %in% names(weak))
  strong <- env$file_ingestion_physical_identity(dest, strong = TRUE)
  expect_true(is.character(strong$content_sha256))
  expect_true(nzchar(strong$content_sha256))

  expected <- env$file_ingestion_file_identity(dest)
  id <- env$file_ingestion_claim_artifact(dest, expected = expected)
  owner <- env$file_ingestion_read_owner(dest)
  expect_identical(owner$id, id)
  expect_true(nzchar(attr(owner$identity, "file_key")$content_sha256))
  expect_true(env$file_ingestion_artifact_owned(
    list(dest = dest, artifact_id = id), require_strong = TRUE
  ))

  owner$state <- "deleting"
  env$file_ingestion_write_owner(owner, marker)
  expect_true(env$file_ingestion_artifact_owned(list(dest = dest, artifact_id = id)))

  # Boyut/mtime/ctime aynı kalsa bile farklı içerikli bir replacement silme
  # yetkisi kazanamaz; karar SHA-256 kanıtında kapanır.
  writeBin(as.raw(c(16, 15, 14, 13)), dest)
  expect_false(env$file_ingestion_artifact_owned(list(dest = dest, artifact_id = id)))
})

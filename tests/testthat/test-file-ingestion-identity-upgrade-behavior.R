# Zayıf Windows metadata kanıtı terfi sırasında güçlü kimliğe yükseltilebilir;
# kalıcı sahiplik ve rollback ise yalnız güçlü device/inode kanıtıyla açılır.

test_that("zayıf terfi kanıtı güçlü hedef kimliğine yükselir", {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  source(file.path(resolve_repo_root_for_tests(), "R/helpers_file_ingestion_identity.R"),
    local = env, encoding = "UTF-8")

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

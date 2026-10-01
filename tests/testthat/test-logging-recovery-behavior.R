.log_recovery_env <- function() {
  env <- new.env(parent = globalenv())
  for (ad in c("config_logging_locks.R", "config_logging_daily_file.R")) {
    source(file.path(resolve_repo_root_for_tests(), "R", ad), encoding = "UTF-8", local = env)
  }
  env
}

test_that("bırakılan yerel kilitler ortamda birikmez", {
  skip_if_not_installed("filelock")
  env <- .log_recovery_env()
  yol <- file.path(withr::local_tempdir(), "yazim.lock")
  for (i in 1:50) {
    jeton <- env$.mergen_log_lock_acquire(yol, 0.1, 60)
    expect_type(jeton, "character")
    env$.mergen_log_lock_release(yol, jeton)
  }
  expect_length(ls(env$.MERGEN_LOG_NATIVE_LOCKS), 0L)
})

test_that("ana kilit açma hatası günlük satırını süreç yedeğine yönlendirir", {
  skip_if_not_installed("filelock")
  env <- .log_recovery_env()
  withr::local_envvar(c(MERGEN_LOG_SHARED_WRITERS = "true"))
  ana <- file.path(withr::local_tempdir(), "mergen_20260101.log")
  yerel_lock <- filelock::lock
  testthat::local_mocked_bindings(lock = function(path, ...) {
    if (endsWith(path, ".mutex")) stop("kilit açılamıyor")
    yerel_lock(path, ...)
  }, .package = "filelock")
  expect_true(env$mergen_log_write_utf8("kayit", ana))
  yedek <- list.files(dirname(ana), pattern = "\\.p.*\\.log$", full.names = TRUE)
  expect_length(yedek, 1L)
  expect_identical(readLines(yedek), "kayit")
})

test_that("hedef açılmazsa her denemede girdi bağlantısı kapatılır", {
  skip_if_not_installed("filelock")
  env <- .log_recovery_env()
  dizin <- withr::local_tempdir()
  ana <- file.path(dizin, "ana.log")
  yedek <- file.path(dizin, "yedek.log")
  writeLines("kayit", yedek)
  env$file <- function(description, ...) {
    if (identical(description, ana)) stop("paylaşım hatası")
    base::file(description, ...)
  }
  once <- nrow(showConnections(all = TRUE))
  for (i in 1:150) expect_false(env$.mergen_log_merge_fallback(ana, yedek))
  expect_identical(nrow(showConnections(all = TRUE)), once)
})

test_that("silinemeyen birleştirme yan dosyası sıfırlanır ve yeni baytlar atlanmaz", {
  skip_if_not_installed("filelock")
  env <- .log_recovery_env()
  dizin <- withr::local_tempdir()
  ana <- file.path(dizin, "ana.log")
  yedek <- file.path(dizin, "yedek.log")
  writeLines("12", paste0(yedek, ".birlesen"))
  env$unlink <- function(x, ...) {
    if (endsWith(x, ".birlesen")) return(1L)
    base::unlink(x, ...)
  }
  expect_true(env$.mergen_log_merged_offset(yedek, 0))
  expect_identical(readLines(paste0(yedek, ".birlesen")), "0")
  writeLines("yeni ve daha uzun kayit", yedek)
  expect_true(env$.mergen_log_merge_fallback(ana, yedek))
  expect_identical(readLines(ana), "yeni ve daha uzun kayit")
  env$writeLines <- function(...) stop("yan dosya yazılamıyor")
  expect_false(env$.mergen_log_merged_offset(yedek, 0))
})

test_that("rastgele UTF-8 yedeği tek süreçte de bulunur ve birleştirilir", {
  skip_if_not_installed("filelock")
  env <- .log_recovery_env()
  dizin <- withr::local_tempdir()
  ana <- file.path(dizin, "mergen_20260101.log")
  yedek <- sub("\\.log$", ".utf8-abc123.log", ana)
  writeLines("onceki", yedek)
  Sys.setFileTime(yedek, Sys.time() - 600)
  expect_true(env$mergen_log_write_utf8("yeni", ana))
  expect_identical(readLines(ana), c("onceki", "yeni"))
})
